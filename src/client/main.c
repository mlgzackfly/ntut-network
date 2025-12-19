#include "log.h"
#include "net.h"
#include "proto.h"
#include "shm_state.h"
#include "stats.h"

#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

typedef enum {
  MIX_MIXED = 0,
  MIX_TRADE_HEAVY = 1,
  MIX_CHAT_HEAVY = 2,
} mix_t;

typedef struct {
  const char *host;
  uint16_t port;
  int timeout_ms;
  int room_id;

  int thread_id;
  int conns;
  int duration_s;
  mix_t mix;
  int payload_size; // For CHAT_SEND payload size (bytes)

  stats_t stats;
} thread_ctx_t;

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint64_t now_ms_wall(void) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)(ts.tv_nsec / 1000000ull);
}

static uint64_t xorshift64(uint64_t *s) {
  uint64_t x = *s;
  x ^= x << 13u;
  x ^= x >> 7u;
  x ^= x << 17u;
  *s = x;
  return x;
}

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
    if (n > 0) off += (size_t)n;
    else if (n == 0) return -1;
    else if (errno == EINTR) continue;
    else return -1;
  }
  return 0;
}

static int read_frame(int fd, ns_header_t *out_hdr, uint8_t **out_body, uint32_t *out_body_len) {
  if (read_full(fd, (uint8_t *)out_hdr, sizeof(*out_hdr)) != 0) return -1;
  uint32_t bl = ns_be32(&out_hdr->body_len);
  *out_body_len = bl;
  if (bl == 0) {
    *out_body = NULL;
    return 0;
  }
  uint8_t *body = (uint8_t *)malloc(bl);
  if (!body) return -1;
  if (read_full(fd, body, bl) != 0) {
    free(body);
    return -1;
  }
  *out_body = body;
  return 0;
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

  while (true) {
    ns_header_t rh;
    uint8_t *rb = NULL;
    uint32_t rbl = 0;
    if (read_frame(fd, &rh, &rb, &rbl) != 0) return -1;

    // validate checksum for responses/pushes
    if (!ns_validate_header_basic(&rh, 65536) || !ns_validate_checksum(&rh, rb, rbl)) {
      free(rb);
      return -1;
    }

    uint16_t rop = ns_be16(&rh.opcode);
    uint64_t rrid = ns_be64(&rh.req_id);
    if (rop == OP_CHAT_BROADCAST && rrid == 0) {
      // server push, ignore for sync request-response
      free(rb);
      continue;
    }
    if (rrid != req_id) {
      // unexpected frame; ignore for now
      free(rb);
      continue;
    }

    *out_hdr = rh;
    *out_body = rb;
    *out_body_len = rbl;
    return 0;
  }
}

static int do_handshake_login(int fd, const char *username, uint32_t *out_user_id, uint64_t *inout_req_id) {
  // HELLO -> nonce
  ns_header_t rh;
  uint8_t *rb = NULL;
  uint32_t rbl = 0;
  uint64_t rid = ++(*inout_req_id);
  if (send_and_wait(fd, OP_HELLO, rid, NULL, 0, &rh, &rb, &rbl) != 0) return -1;
  if (ns_be16(&rh.status) != ST_OK || rbl != 8) { free(rb); return -1; }
  uint64_t nonce = ns_be64(rb);
  free(rb);

  // LOGIN: u16 uname_len + uname + u32 token
  size_t ulen = strnlen(username, NS_MAX_USERNAME - 1);
  if (ulen == 0 || ulen >= NS_MAX_USERNAME) return -1;
  uint8_t body[2 + NS_MAX_USERNAME + 4];
  ns_put_be16(body + 0, (uint16_t)ulen);
  memcpy(body + 2, username, ulen);
  uint8_t tmp[NS_MAX_USERNAME + 8];
  memcpy(tmp, username, ulen);
  ns_put_be64(tmp + ulen, nonce);
  uint32_t token = ns_crc32(tmp, ulen + 8u);
  ns_put_be32(body + 2 + ulen, token);

  rid = ++(*inout_req_id);
  if (send_and_wait(fd, OP_LOGIN, rid, body, (uint32_t)(2u + ulen + 4u), &rh, &rb, &rbl) != 0) return -1;
  if (ns_be16(&rh.status) != ST_OK || rbl < 4) { free(rb); return -1; }
  *out_user_id = ns_be32(rb);
  free(rb);
  return 0;
}

static int do_join_room(int fd, uint16_t room, uint64_t *inout_req_id) {
  uint8_t body[2];
  ns_put_be16(body, room);
  ns_header_t rh;
  uint8_t *rb = NULL;
  uint32_t rbl = 0;
  uint64_t rid = ++(*inout_req_id);
  if (send_and_wait(fd, OP_JOIN_ROOM, rid, body, 2, &rh, &rb, &rbl) != 0) return -1;
  uint16_t st = ns_be16(&rh.status);
  free(rb);
  return st == ST_OK ? 0 : -1;
}

static void *thread_main(void *arg) {
  thread_ctx_t *ctx = (thread_ctx_t *)arg;
  char pname[64];
  snprintf(pname, sizeof(pname), "client-t%d", ctx->thread_id);
  log_set_program(pname);

  stats_init(&ctx->stats);

  int *fds = (int *)calloc((size_t)ctx->conns, sizeof(int));
  uint64_t *req_ids = (uint64_t *)calloc((size_t)ctx->conns, sizeof(uint64_t));
  uint32_t *user_ids = (uint32_t *)calloc((size_t)ctx->conns, sizeof(uint32_t));
  if (!fds || !req_ids || !user_ids) return NULL;

  uint64_t rng = (now_ms_wall() << 1u) ^ (uint64_t)(ctx->thread_id + 1);

  for (int i = 0; i < ctx->conns; i++) {
    int fd = net_connect_tcp(ctx->host, ctx->port, ctx->timeout_ms);
    if (fd < 0) {
      ctx->stats.err++;
      fds[i] = -1;
      continue;
    }
    (void)net_set_tcp_nodelay(fd);
    fds[i] = fd;
    req_ids[i] = 0;

    char uname[NS_MAX_USERNAME];
    snprintf(uname, sizeof(uname), "u%d_%d", ctx->thread_id, i);
    if (do_handshake_login(fd, uname, &user_ids[i], &req_ids[i]) != 0) {
      ctx->stats.err++;
      close(fd);
      fds[i] = -1;
      continue;
    }
    if (do_join_room(fd, (uint16_t)ctx->room_id, &req_ids[i]) != 0) {
      ctx->stats.err++;
      close(fd);
      fds[i] = -1;
      continue;
    }
  }

  uint64_t end_ns = now_ns() + (uint64_t)ctx->duration_s * 1000000000ull;
  uint32_t *backoff_ms = (uint32_t *)calloc((size_t)ctx->conns, sizeof(uint32_t)); // per-connection backoff
  if (!backoff_ms) {
    free(fds);
    free(req_ids);
    free(user_ids);
    return NULL;
  }

  while (now_ns() < end_ns) {
    for (int i = 0; i < ctx->conns; i++) {
      int fd = fds[i];
      if (fd < 0) continue;

      // Exponential backoff: wait if backoff > 0
      if (backoff_ms[i] > 0) {
        uint64_t wait_ns = (uint64_t)backoff_ms[i] * 1000000ull;
        uint64_t wait_end = now_ns() + wait_ns;
        while (now_ns() < wait_end && now_ns() < end_ns) {
          usleep(10000); // 10ms
        }
        // Reset backoff after waiting (will be set again if ERR_SERVER_BUSY)
        backoff_ms[i] = 0;
        continue;
      }

      uint64_t r = xorshift64(&rng);
      uint16_t opcode = OP_BALANCE;
      uint8_t body[512];
      uint32_t body_len = 0;

      // Pick opcode by mix
      uint32_t pick = (uint32_t)(r % 100u);
      if (ctx->mix == MIX_TRADE_HEAVY) {
        opcode = (pick < 40) ? OP_TRANSFER : (pick < 70) ? OP_WITHDRAW : (pick < 90) ? OP_DEPOSIT : OP_BALANCE;
      } else if (ctx->mix == MIX_CHAT_HEAVY) {
        opcode = (pick < 70) ? OP_CHAT_SEND : (pick < 85) ? OP_BALANCE : OP_TRANSFER;
      } else {
        opcode = (pick < 30) ? OP_CHAT_SEND : (pick < 55) ? OP_TRANSFER : (pick < 75) ? OP_WITHDRAW : (pick < 90) ? OP_DEPOSIT : OP_BALANCE;
      }

      if (opcode == OP_CHAT_SEND) {
        // Generate message with specified payload size
        // Body: u16 room_id + u16 msg_len + msg_bytes
        // Total body = 4 + msg_len, so msg_len = payload_size - 4 (min 1)
        uint16_t target_msg_len = (ctx->payload_size > 4) ? (uint16_t)(ctx->payload_size - 4) : 1;
        if (target_msg_len > 512) target_msg_len = 512; // Limit to buffer size
        
        ns_put_be16(body + 0, (uint16_t)ctx->room_id);
        ns_put_be16(body + 2, target_msg_len);
        // Fill message with pattern (repeating "x" or random data)
        for (uint16_t i = 0; i < target_msg_len; i++) {
          body[4 + i] = (uint8_t)('a' + (i % 26));
        }
        body_len = 4u + target_msg_len;
      } else if (opcode == OP_DEPOSIT || opcode == OP_WITHDRAW) {
        uint64_t amt = (xorshift64(&rng) % 100u) + 1u;
        ns_put_be64(body + 0, amt);
        body_len = 8;
      } else if (opcode == OP_TRANSFER) {
        uint32_t to = (uint32_t)(xorshift64(&rng) % NS_MAX_USERS);
        if (to == user_ids[i]) to = (to + 1) % NS_MAX_USERS;
        uint64_t amt = (xorshift64(&rng) % 50u) + 1u;
        ns_put_be32(body + 0, to);
        ns_put_be64(body + 4, amt);
        body_len = 12;
      } else {
        body_len = 0;
      }

      ns_header_t rh;
      uint8_t *rb = NULL;
      uint32_t rbl = 0;
      uint64_t req_id = ++req_ids[i];
      uint64_t t0 = now_ns();
      if (send_and_wait(fd, opcode, req_id, body_len ? body : NULL, body_len, &rh, &rb, &rbl) != 0) {
        ctx->stats.err++;
        free(rb);
        close(fd);
        fds[i] = -1;
        continue;
      }
      uint16_t st = ns_be16(&rh.status);
      uint64_t t1 = now_ns();
      uint64_t us = (t1 - t0) / 1000ull;
      (void)stats_push_latency_us(&ctx->stats, us);
      
      if (st == ST_OK) {
        ctx->stats.ok++;
        backoff_ms[i] = 0; // Reset backoff on success
      } else if (st == ST_ERR_SERVER_BUSY) {
        ctx->stats.err++;
        // Exponential backoff: start at 10ms, double each time, max 1000ms
        if (backoff_ms[i] == 0) backoff_ms[i] = 10;
        else {
          backoff_ms[i] *= 2;
          if (backoff_ms[i] > 1000) backoff_ms[i] = 1000;
        }
      } else {
        ctx->stats.err++;
        backoff_ms[i] = 0;
      }
      free(rb);
    }
  }

  free(backoff_ms);

  for (int i = 0; i < ctx->conns; i++) {
    if (fds[i] >= 0) close(fds[i]);
  }
  free(backoff_ms);
  free(fds);
  free(req_ids);
  free(user_ids);
  return NULL;
}

static void usage(const char *p) {
  fprintf(stderr,
          "Usage: %s --host 127.0.0.1 --port 9000 --connections 100 --threads 16 --duration 60 --mix mixed --payload-size 32 --out results.csv\n",
          p);
}

static mix_t parse_mix(const char *s) {
  if (!s) return MIX_MIXED;
  if (strcmp(s, "trade-heavy") == 0) return MIX_TRADE_HEAVY;
  if (strcmp(s, "chat-heavy") == 0) return MIX_CHAT_HEAVY;
  return MIX_MIXED;
}

int main(int argc, char **argv) {
  log_set_program("client");

  const char *host = "127.0.0.1";
  uint16_t port = 9000;
  int connections = 100;
  int threads = 16;
  int duration_s = 30;
  const char *mix_s = "mixed";
  const char *out_path = "results.csv";
  int payload_size = 32; // Default payload size for CHAT_SEND (bytes)

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--host") == 0 && i + 1 < argc) host = argv[++i];
    else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) port = (uint16_t)atoi(argv[++i]);
    else if (strcmp(argv[i], "--connections") == 0 && i + 1 < argc) connections = atoi(argv[++i]);
    else if (strcmp(argv[i], "--threads") == 0 && i + 1 < argc) threads = atoi(argv[++i]);
    else if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) duration_s = atoi(argv[++i]);
    else if (strcmp(argv[i], "--mix") == 0 && i + 1 < argc) mix_s = argv[++i];
    else if (strcmp(argv[i], "--payload-size") == 0 && i + 1 < argc) payload_size = atoi(argv[++i]);
    else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) out_path = argv[++i];
    else if (strcmp(argv[i], "--help") == 0) { usage(argv[0]); return 0; }
    else { usage(argv[0]); return 2; }
  }

  if (threads <= 0 || connections <= 0 || duration_s <= 0) return 2;

  mix_t mix = parse_mix(mix_s);
  int base = connections / threads;
  int rem = connections % threads;

  pthread_t *ths = (pthread_t *)calloc((size_t)threads, sizeof(pthread_t));
  thread_ctx_t *ctxs = (thread_ctx_t *)calloc((size_t)threads, sizeof(thread_ctx_t));
  if (!ths || !ctxs) return 1;

  for (int t = 0; t < threads; t++) {
    ctxs[t].host = host;
    ctxs[t].port = port;
    ctxs[t].timeout_ms = 2000;
    ctxs[t].room_id = 0;
    ctxs[t].thread_id = t;
    ctxs[t].conns = base + (t < rem ? 1 : 0);
    ctxs[t].duration_s = duration_s;
    ctxs[t].mix = mix;
    ctxs[t].payload_size = payload_size;
    (void)pthread_create(&ths[t], NULL, thread_main, &ctxs[t]);
  }

  uint64_t ok = 0, err = 0;
  stats_t agg;
  stats_init(&agg);

  for (int t = 0; t < threads; t++) {
    (void)pthread_join(ths[t], NULL);
    ok += ctxs[t].stats.ok;
    err += ctxs[t].stats.err;
    // merge latencies
    for (size_t i = 0; i < ctxs[t].stats.len; i++) {
      (void)stats_push_latency_us(&agg, ctxs[t].stats.lat_us[i]);
    }
    stats_free(&ctxs[t].stats);
  }

  uint64_t total = ok + err;
  double rps = duration_s > 0 ? (double)total / (double)duration_s : 0.0;

  uint64_t p50 = stats_percentile_us(&agg, 50.0);
  uint64_t p95 = stats_percentile_us(&agg, 95.0);
  uint64_t p99 = stats_percentile_us(&agg, 99.0);

  FILE *f = fopen(out_path, "w");
  if (f) {
    fprintf(f, "host,port,connections,threads,duration_s,total,ok,err,rps,p50_us,p95_us,p99_us\n");
    fprintf(f, "%s,%u,%d,%d,%d,%llu,%llu,%llu,%.2f,%llu,%llu,%llu\n",
            host, port, connections, threads, duration_s,
            (unsigned long long)total, (unsigned long long)ok, (unsigned long long)err,
            rps,
            (unsigned long long)p50, (unsigned long long)p95, (unsigned long long)p99);
    fclose(f);
  }

  printf("connections=%d threads=%d duration=%ds total=%llu ok=%llu err=%llu rps=%.2f p50=%lluus p95=%lluus p99=%lluus\n",
         connections, threads, duration_s,
         (unsigned long long)total, (unsigned long long)ok, (unsigned long long)err,
         rps,
         (unsigned long long)p50, (unsigned long long)p95, (unsigned long long)p99);

  stats_free(&agg);
  free(ths);
  free(ctxs);
  return 0;
}


