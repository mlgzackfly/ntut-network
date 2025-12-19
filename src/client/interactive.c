#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#include "log.h"
#include "net.h"
#include "proto.h"
#include "shm_state.h"

#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

static int g_fd = -1;
static bool g_running = true;
static uint32_t g_user_id = 0;
static uint16_t g_room_id = UINT16_MAX; // Use UINT16_MAX to indicate "not in room"
static uint64_t g_req_id = 0;
static pthread_mutex_t g_socket_mutex = PTHREAD_MUTEX_INITIALIZER;

static int write_full(int fd, const uint8_t *buf, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = send(fd, buf + off, len - off, 0);
    if (n > 0) off += (size_t)n;
    else if (n < 0 && errno == EINTR) continue;
    else return -1;
  }
  return 0;
}

static int read_full(int fd, uint8_t *buf, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = recv(fd, buf + off, len - off, 0);
    if (n > 0) {
      off += (size_t)n;
    } else if (n == 0) {
      return -1; // EOF
    } else {
      // Handle non-blocking socket: EAGAIN/EWOULDBLOCK means no data available yet
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return -1; // Would block - caller should use select/poll first
      } else if (errno == EINTR) {
        continue; // Interrupted, retry
      } else {
        return -1; // Error
      }
    }
  }
  return 0;
}

static int read_frame(int fd, ns_header_t *out_hdr, uint8_t **out_body, uint32_t *out_body_len) {
  pthread_mutex_lock(&g_socket_mutex);
  int ret = 0;
  if (read_full(fd, (uint8_t *)out_hdr, sizeof(*out_hdr)) != 0) {
    ret = -1;
    goto out;
  }
  uint32_t bl = ns_be32(&out_hdr->body_len);
  *out_body_len = bl;
  if (bl == 0) {
    *out_body = NULL;
    goto out;
  }
  uint8_t *body = (uint8_t *)malloc(bl);
  if (!body) {
    ret = -1;
    goto out;
  }
  if (read_full(fd, body, bl) != 0) {
    free(body);
    ret = -1;
    goto out;
  }
  *out_body = body;
out:
  pthread_mutex_unlock(&g_socket_mutex);
  return ret;
}

static int send_frame(int fd, uint16_t opcode, uint64_t req_id, const uint8_t *body, uint32_t body_len) {
  uint8_t hdrbuf[sizeof(ns_header_t)];
  ns_header_t hdr;
  ns_build_header(&hdr, 0, opcode, ST_OK, req_id, body, body_len);
  memcpy(hdrbuf, &hdr, sizeof(hdr));
  if (write_full(fd, hdrbuf, sizeof(hdrbuf)) != 0) return -1;
  if (body_len && write_full(fd, body, body_len) != 0) return -1;
  return 0;
}

static int send_and_wait(int fd, uint16_t opcode, uint64_t req_id, const uint8_t *body, uint32_t body_len,
                         ns_header_t *out_hdr, uint8_t **out_body, uint32_t *out_body_len) {
  if (send_frame(fd, opcode, req_id, body, body_len) != 0) return -1;

  // Try up to 10 times to get the right response (with timeout handling)
  for (int attempts = 0; attempts < 10; attempts++) {
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    
    // Use select with timeout
    fd_set rfds;
    struct timeval tv;
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);
    tv.tv_sec = 2;
    tv.tv_usec = 0;
    
    int sel_ret = select(fd + 1, &rfds, NULL, NULL, &tv);
    if (sel_ret <= 0) {
      // Timeout or error
      continue;
    }
    
    if (read_frame(fd, &rh, &rb, &rbl) != 0) {
      // In non-blocking mode, EAGAIN shouldn't happen after select, but handle it anyway
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        continue; // No data available, retry
      }
      return -1; // Real error
    }

    if (!ns_validate_header_basic(&rh, 65536) || !ns_validate_checksum(&rh, rb, rbl)) {
      free(rb);
      continue;
    }

    uint16_t rop = ns_be16(&rh.opcode);
    uint64_t rrid = ns_be64(&rh.req_id);
    
    // Skip chat broadcasts - receive_thread handles them
    // Broadcasts have req_id == 0 and are server pushes
    if (rop == OP_CHAT_BROADCAST && rrid == 0) {
      free(rb);
      continue;
    }
    
    // Check if this is the response we're waiting for
    if (rrid == req_id) {
      *out_hdr = rh;
      *out_body = rb;
      *out_body_len = rbl;
      return 0;
    }
    
    // Wrong req_id - this shouldn't happen, but free and continue
    free(rb);
  }
  
  // Timeout - didn't get response
  return -1;
}

static int do_login(int fd, const char *username) {
  // HELLO
  ns_header_t rh;
  uint8_t *rb = NULL;
  uint32_t rbl = 0;
  uint64_t rid = ++g_req_id;
  if (send_and_wait(fd, OP_HELLO, rid, NULL, 0, &rh, &rb, &rbl) != 0) {
    printf("HELLO failed\n");
    return -1;
  }
  if (ns_be16(&rh.status) != ST_OK || rbl != 8) {
    free(rb);
    printf("HELLO response invalid\n");
    return -1;
  }
  uint64_t nonce = ns_be64(rb);
  free(rb);

  // LOGIN
  size_t ulen = strnlen(username, NS_MAX_USERNAME - 1);
  if (ulen == 0 || ulen >= NS_MAX_USERNAME) {
    printf("Username too long\n");
    return -1;
  }
  uint8_t body[2 + NS_MAX_USERNAME + 4];
  ns_put_be16(body + 0, (uint16_t)ulen);
  memcpy(body + 2, username, ulen);
  uint8_t tmp[NS_MAX_USERNAME + 8];
  memcpy(tmp, username, ulen);
  ns_put_be64(tmp + ulen, nonce);
  uint32_t token = ns_crc32(tmp, ulen + 8u);
  ns_put_be32(body + 2 + ulen, token);

  rid = ++g_req_id;
  if (send_and_wait(fd, OP_LOGIN, rid, body, (uint32_t)(2u + ulen + 4u), &rh, &rb, &rbl) != 0) {
    printf("LOGIN failed\n");
    return -1;
  }
  uint16_t st = ns_be16(&rh.status);
  if (st != ST_OK || rbl < 12) {
    free(rb);
    printf("LOGIN failed: status=%u\n", st);
    return -1;
  }
  g_user_id = ns_be32(rb);
  int64_t balance = (int64_t)ns_be64(rb + 4);
  free(rb);
  printf("Login successful! User ID: %u, Balance: %ld\n", g_user_id, balance);
  return 0;
}

// Periodically send HEARTBEAT frames to keep the connection alive.
// This prevents the server from timing out idle interactive clients.
static void *heartbeat_thread(void *arg) {
  (void)arg;
  const int interval_ms = 10000; // 10 seconds, must be < server's 30s timeout

  while (g_running && g_fd >= 0) {
    struct timespec ts;
    ts.tv_sec = interval_ms / 1000;
    ts.tv_nsec = (long)(interval_ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);

    if (!g_running || g_fd < 0) break;

    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;

    // Fire-and-forget: we don't show anything to the user, just keep connection alive.
    if (send_and_wait(g_fd, OP_HEARTBEAT, rid, NULL, 0, &rh, &rb, &rbl) != 0) {
      free(rb);
      // If heartbeat fails, likely the connection is broken; exit loop.
      break;
    }
    free(rb);
  }
  return NULL;
}

static void *receive_thread(void *arg) {
  (void)arg;
  // Simplified: receive_thread only handles chat broadcasts
  // All other responses are handled by send_and_wait
  // We use a very short timeout to avoid blocking send_and_wait
  while (g_running && g_fd >= 0) {
    fd_set rfds;
    struct timeval tv;
    FD_ZERO(&rfds);
    FD_SET(g_fd, &rfds);
    tv.tv_sec = 0;
    tv.tv_usec = 50000; // 50ms - very short to not interfere with send_and_wait
    
    int ret = select(g_fd + 1, &rfds, NULL, NULL, &tv);
    if (ret <= 0) continue;
    
    // Read frame (read_frame handles socket mutex locking)
    ns_header_t hdr;
    uint8_t *body = NULL;
    uint32_t body_len = 0;
    
    if (read_frame(g_fd, &hdr, &body, &body_len) != 0) {
      // In non-blocking mode, EAGAIN means no data available yet (shouldn't happen after select)
      // Other errors mean connection closed or error
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        continue; // No data available, continue loop
      }
      if (g_running) printf("\n[Connection closed]\n");
      break;
    }

    if (!ns_validate_header_basic(&hdr, 65536) || !ns_validate_checksum(&hdr, body, body_len)) {
      free(body);
      continue;
    }

    uint16_t opcode = ns_be16(&hdr.opcode);
    uint64_t req_id = ns_be64(&hdr.req_id);
    
    // Only handle CHAT_BROADCAST (req_id == 0 indicates server push)
    // Server format: u16 room_id + u32 from_user_id + u16 msg_len + msg
    if (opcode == OP_CHAT_BROADCAST && req_id == 0) {
      if (body_len >= 8) {
        uint16_t room = ns_be16(body + 0);  // room_id at offset 0
        uint32_t from_uid = ns_be32(body + 2);  // from_user_id at offset 2
        uint16_t msg_len = ns_be16(body + 6);  // msg_len at offset 6
        if (msg_len > 0 && msg_len <= body_len - 8) {
          char msg[257];
          size_t copy_len = (size_t)msg_len < 256 ? msg_len : 256;
          memcpy(msg, body + 8, copy_len);
          msg[copy_len] = '\0';
          // Show all messages (including our own from server broadcast)
          if (from_uid == g_user_id) {
            printf("\n[Room %u] You: %s\n> ", room, msg);
          } else {
            printf("\n[Room %u] User %u: %s\n> ", room, from_uid, msg);
          }
          fflush(stdout);
        }
      }
      free(body);
    } else {
      // Not a broadcast - this is a response to a request
      // We can't "unread" it, so we need to buffer it somehow
      // For now, we'll just free it and let send_and_wait retry
      // This is not ideal, but send_and_wait has retry logic
      free(body);
    }
  }
  return NULL;
}

static void print_menu(void) {
  printf("\n=== Menu ===\n");
  printf("1. Join room (join <room_id>)\n");
  printf("2. Send message (chat <message>)\n");
  printf("3. Check balance (balance)\n");
  printf("4. Deposit (deposit <amount>)\n");
  printf("5. Withdraw (withdraw <amount>)\n");
  printf("6. Transfer (transfer <user_id> <amount>)\n");
  printf("7. Leave room (leave)\n");
  printf("8. Quit (quit)\n");
  printf("> ");
  fflush(stdout);
}

static void handle_command(const char *line) {
  char cmd[256];
  int n = sscanf(line, "%255s", cmd);
  if (n != 1) return;

  if (strcmp(cmd, "quit") == 0 || strcmp(cmd, "q") == 0) {
    g_running = false;
    return;
  }

  if (strcmp(cmd, "balance") == 0 || strcmp(cmd, "bal") == 0) {
    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (send_and_wait(g_fd, OP_BALANCE, rid, NULL, 0, &rh, &rb, &rbl) != 0) {
      printf("Failed to query balance\n");
      return;
    }
    uint16_t st = ns_be16(&rh.status);
    if (st == ST_OK && rbl >= 8) {
      int64_t bal = (int64_t)ns_be64(rb);
      printf("Balance: %ld\n", bal);
    } else {
      printf("Failed to query balance: status=%u\n", st);
    }
    free(rb);
    return;
  }

  if (strncmp(cmd, "join", 4) == 0) {
    uint16_t room = 0;
    if (sscanf(line, "join %hu", &room) != 1) {
      printf("Usage: join <room_id>\n");
      return;
    }
    uint8_t body[2];
    ns_put_be16(body, room);
    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (send_and_wait(g_fd, OP_JOIN_ROOM, rid, body, 2, &rh, &rb, &rbl) != 0) {
      printf("Failed to join room (connection error)\n");
      return;
    }
    uint16_t rop = ns_be16(&rh.opcode);
    uint16_t st = ns_be16(&rh.status);
    uint64_t rrid = ns_be64(&rh.req_id);
    if (rop == OP_JOIN_ROOM && st == ST_OK && rrid == rid) {
      g_room_id = room;
      printf("Joined room %u\n", room);
    } else {
      printf("Failed to join room: opcode=%u status=%u\n", rop, st);
    }
    free(rb);
    return;
  }

  if (strncmp(cmd, "chat", 4) == 0) {
    if (g_room_id == UINT16_MAX) {
      printf("Please join a room first (join <room_id>)\n");
      return;
    }
    const char *msg = line + 4;
    while (*msg == ' ') msg++;
    if (*msg == '\0') {
      printf("Usage: chat <message>\n");
      return;
    }
    size_t msg_len = strlen(msg);
    if (msg_len > NS_MAX_CHAT_MSG) msg_len = NS_MAX_CHAT_MSG;
    
    uint8_t body[4 + NS_MAX_CHAT_MSG];
    ns_put_be16(body + 0, g_room_id);
    ns_put_be16(body + 2, (uint16_t)msg_len);
    memcpy(body + 4, msg, msg_len);
    
    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (send_and_wait(g_fd, OP_CHAT_SEND, rid, body, (uint32_t)(4u + msg_len), &rh, &rb, &rbl) != 0) {
      printf("Failed to send message\n");
      return;
    }
    uint16_t st = ns_be16(&rh.status);
    if (st != ST_OK) {
      printf("Failed to send message: status=%u\n", st);
    }
    // Message will appear via server broadcast automatically
    free(rb);
    return;
  }

  if (strncmp(cmd, "deposit", 7) == 0) {
    int64_t amount = 0;
    if (sscanf(line, "deposit %ld", &amount) != 1 || amount <= 0) {
      printf("Usage: deposit <amount>\n");
      return;
    }
    uint8_t body[8];
    ns_put_be64(body, (uint64_t)amount);
    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (send_and_wait(g_fd, OP_DEPOSIT, rid, body, 8, &rh, &rb, &rbl) != 0) {
      printf("Failed to deposit\n");
      return;
    }
    uint16_t st = ns_be16(&rh.status);
    if (st == ST_OK && rbl >= 8) {
      int64_t bal = (int64_t)ns_be64(rb);
      printf("Deposit successful! New balance: %ld\n", bal);
    } else {
      printf("Failed to deposit: status=%u\n", st);
    }
    free(rb);
    return;
  }

  if (strncmp(cmd, "withdraw", 8) == 0) {
    int64_t amount = 0;
    if (sscanf(line, "withdraw %ld", &amount) != 1 || amount <= 0) {
      printf("Usage: withdraw <amount>\n");
      return;
    }
    uint8_t body[8];
    ns_put_be64(body, (uint64_t)amount);
    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (send_and_wait(g_fd, OP_WITHDRAW, rid, body, 8, &rh, &rb, &rbl) != 0) {
      printf("Failed to withdraw\n");
      return;
    }
    uint16_t st = ns_be16(&rh.status);
    if (st == ST_OK && rbl >= 8) {
      int64_t bal = (int64_t)ns_be64(rb);
      printf("Withdraw successful! New balance: %ld\n", bal);
    } else if (st == ST_ERR_INSUFFICIENT_FUNDS) {
      printf("Insufficient funds\n");
    } else {
      printf("Failed to withdraw: status=%u\n", st);
    }
    free(rb);
    return;
  }

  if (strncmp(cmd, "transfer", 8) == 0) {
    uint32_t to_uid = 0;
    int64_t amount = 0;
    if (sscanf(line, "transfer %u %ld", &to_uid, &amount) != 2 || amount <= 0) {
      printf("Usage: transfer <user_id> <amount>\n");
      return;
    }
    uint8_t body[12];
    ns_put_be32(body + 0, to_uid);
    ns_put_be64(body + 4, (uint64_t)amount);
    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (send_and_wait(g_fd, OP_TRANSFER, rid, body, 12, &rh, &rb, &rbl) != 0) {
      printf("Failed to transfer\n");
      return;
    }
    uint16_t st = ns_be16(&rh.status);
    if (st == ST_OK && rbl >= 8) {
      int64_t bal = (int64_t)ns_be64(rb);
      printf("Transfer successful! New balance: %ld\n", bal);
    } else if (st == ST_ERR_INSUFFICIENT_FUNDS) {
      printf("Insufficient funds\n");
    } else {
      printf("Failed to transfer: status=%u\n", st);
    }
    free(rb);
    return;
  }

  if (strcmp(cmd, "leave") == 0) {
    if (g_room_id == UINT16_MAX) {
      printf("Not in any room\n");
      return;
    }
    uint8_t body[2];
    ns_put_be16(body, g_room_id);
    uint64_t rid = ++g_req_id;
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (send_and_wait(g_fd, OP_LEAVE_ROOM, rid, body, 2, &rh, &rb, &rbl) != 0) {
      printf("Failed to leave room\n");
      return;
    }
    uint16_t st = ns_be16(&rh.status);
    if (st == ST_OK) {
      printf("Left room %u\n", g_room_id);
      g_room_id = UINT16_MAX;
    } else {
      printf("Failed to leave room: status=%u\n", st);
    }
    free(rb);
    return;
  }

  printf("Unknown command: %s\n", cmd);
  print_menu();
}

int main(int argc, char **argv) {
  log_set_program("interactive");
  log_set_level(LOG_LEVEL_WARN); // 减少日志输出

  const char *host = "127.0.0.1";
  uint16_t port = 9000;
  char username[NS_MAX_USERNAME] = "user1";

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--host") == 0 && i + 1 < argc) {
      host = argv[++i];
    } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
      port = (uint16_t)atoi(argv[++i]);
    } else if (strcmp(argv[i], "--user") == 0 && i + 1 < argc) {
      snprintf(username, sizeof(username), "%s", argv[++i]);
    } else if (strcmp(argv[i], "--help") == 0) {
      printf("Usage: %s [--host 127.0.0.1] [--port 9000] [--user username]\n", argv[0]);
      return 0;
    }
  }

  printf("Connecting to server %s:%u...\n", host, port);
  g_fd = net_connect_tcp(host, port, 5000);
  if (g_fd < 0) {
    printf("Connection failed\n");
    return 1;
  }
  (void)net_set_tcp_nodelay(g_fd);
  // Set socket to non-blocking to prevent deadlock between receive_thread and send_and_wait
  (void)net_set_nonblocking(g_fd, true);

  printf("Logging in as: %s\n", username);
  if (do_login(g_fd, username) != 0) {
    printf("Login failed\n");
    close(g_fd);
    return 1;
  }

  // Start receive thread (for chat broadcasts)
  pthread_t recv_th;
  if (pthread_create(&recv_th, NULL, receive_thread, NULL) != 0) {
    printf("Failed to create receive thread\n");
    close(g_fd);
    return 1;
  }

  // Start heartbeat thread (to prevent server idle timeout)
  pthread_t hb_th;
  if (pthread_create(&hb_th, NULL, heartbeat_thread, NULL) != 0) {
    printf("Failed to create heartbeat thread\n");
    g_running = false;
    pthread_join(recv_th, NULL);
    close(g_fd);
    return 1;
  }

  print_menu();

  char line[512];
  while (g_running && fgets(line, sizeof(line), stdin) != NULL) {
    size_t len = strlen(line);
    if (len > 0 && line[len - 1] == '\n') {
      line[len - 1] = '\0';
    }
    if (strlen(line) == 0) {
      print_menu();
      continue;
    }
    handle_command(line);
    if (g_running) {
      printf("> ");
      fflush(stdout);
    }
  }

  g_running = false;
  pthread_join(hb_th, NULL);
  pthread_join(recv_th, NULL);
  close(g_fd);
  printf("\nGoodbye!\n");
  return 0;
}
