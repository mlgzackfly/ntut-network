#include "worker.h"

#include "log.h"
#include "net.h"
#include "proto.h"

#include <errno.h>
#include <linux/limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

typedef struct conn {
  int fd;
  bool authed;
  uint32_t user_id;

  uint8_t rbuf[65536];
  size_t rlen;

  uint8_t *wbuf;
  size_t wcap;
  size_t wlen;
  size_t wpos;
} conn_t;

static void metric_inc_u64(uint64_t *p, uint64_t v) {
  (void)__atomic_fetch_add(p, v, __ATOMIC_RELAXED);
}

static uint64_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)(ts.tv_nsec / 1000000ull);
}

static void conn_free(conn_t *c) {
  if (!c) return;
  if (c->fd >= 0) close(c->fd);
  free(c->wbuf);
  free(c);
}

static int conn_ensure_wcap(conn_t *c, size_t need) {
  if (c->wcap >= need) return 0;
  size_t newcap = c->wcap ? c->wcap : 4096u;
  while (newcap < need) newcap *= 2u;
  uint8_t *p = (uint8_t *)realloc(c->wbuf, newcap);
  if (!p) return -1;
  c->wbuf = p;
  c->wcap = newcap;
  return 0;
}

static int conn_queue(conn_t *c, const uint8_t *data, size_t len) {
  if (conn_ensure_wcap(c, c->wlen + len) != 0) return -1;
  memcpy(c->wbuf + c->wlen, data, len);
  c->wlen += len;
  return 0;
}

static int ep_mod(int epfd, int fd, uint32_t events, void *ptr) {
  struct epoll_event ev;
  memset(&ev, 0, sizeof(ev));
  ev.events = events;
  ev.data.ptr = ptr;
  return epoll_ctl(epfd, EPOLL_CTL_MOD, fd, &ev);
}

static int ep_add(int epfd, int fd, uint32_t events, void *ptr) {
  struct epoll_event ev;
  memset(&ev, 0, sizeof(ev));
  ev.events = events;
  ev.data.ptr = ptr;
  return epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev);
}

static void send_simple_response(conn_t *c, uint16_t opcode, uint16_t status, uint64_t req_id,
                                 const uint8_t *body, uint32_t body_len) {
  uint8_t frame[sizeof(ns_header_t) + 1024];
  if (body_len > 1024u) return;
  ns_header_t hdr;
  ns_build_header(&hdr, NS_FLAG_IS_RESPONSE, opcode, status, req_id, body, body_len);
  memcpy(frame, &hdr, sizeof(hdr));
  if (body_len) memcpy(frame + sizeof(hdr), body, body_len);
  (void)conn_queue(c, frame, sizeof(hdr) + body_len);
}

static void handle_chat_broadcast(ns_shm_t *shm, conn_t **fdmap, size_t fdcap, uint64_t *inout_seq) {
  ns_chat_event_t batch[64];
  uint64_t n = ns_chat_read_from(shm, inout_seq, batch, 64);
  for (uint64_t i = 0; i < n; i++) {
    const ns_chat_event_t *e = &batch[i];
    uint8_t body[2 + 4 + 2 + NS_MAX_CHAT_MSG];
    ns_put_be16(body + 0, e->room_id);
    ns_put_be32(body + 2, e->from_user_id);
    ns_put_be16(body + 6, e->msg_len);
    memcpy(body + 8, e->msg, e->msg_len);
    uint32_t body_len = 8u + (uint32_t)e->msg_len;

    for (size_t fd = 0; fd < fdcap; fd++) {
      conn_t *c = fdmap[fd];
      if (!c || !c->authed) continue;
      if (!ns_room_is_member(shm, e->room_id, c->user_id)) continue;

      // Push frame: opcode=CHAT_BROADCAST, req_id=0
      uint8_t frame[sizeof(ns_header_t) + sizeof(body)];
      ns_header_t hdr;
      ns_build_header(&hdr, 0, OP_CHAT_BROADCAST, ST_OK, 0, body, body_len);
      memcpy(frame, &hdr, sizeof(hdr));
      memcpy(frame + sizeof(hdr), body, body_len);
      (void)conn_queue(c, frame, sizeof(hdr) + body_len);
    }
  }
}

static uint16_t rd_u16(const uint8_t *p, size_t n, size_t off, bool *ok) {
  if (off + 2 > n) { *ok = false; return 0; }
  return ns_be16(p + off);
}
static uint32_t rd_u32(const uint8_t *p, size_t n, size_t off, bool *ok) {
  if (off + 4 > n) { *ok = false; return 0; }
  return ns_be32(p + off);
}
static uint64_t rd_u64(const uint8_t *p, size_t n, size_t off, bool *ok) {
  if (off + 8 > n) { *ok = false; return 0; }
  return ns_be64(p + off);
}

static void handle_request(ns_shm_t *shm, int notify_efd, conn_t *c,
                           const ns_header_t *hdr, const uint8_t *body, uint32_t body_len) {
  const uint16_t opcode = ns_be16(&hdr->opcode);
  const uint64_t req_id = ns_be64(&hdr->req_id);

  metric_inc_u64(&shm->total_requests, 1);
  if (opcode < (uint16_t)(sizeof(shm->op_counts) / sizeof(shm->op_counts[0]))) {
    metric_inc_u64(&shm->op_counts[opcode], 1);
  }

  // Require login for most ops
  if (!c->authed) {
    if (opcode != OP_HELLO && opcode != OP_LOGIN && opcode != OP_HEARTBEAT) {
      send_simple_response(c, opcode, ST_ERR_UNAUTHORIZED, req_id, NULL, 0);
      return;
    }
  }

  switch (opcode) {
    case OP_HELLO: {
      uint8_t resp[8];
      ns_put_be64(resp, shm->server_nonce);
      send_simple_response(c, OP_HELLO, ST_OK, req_id, resp, (uint32_t)sizeof(resp));
      break;
    }
    case OP_LOGIN: {
      // Body: u16 uname_len + uname + u32 token
      bool ok = true;
      uint16_t ulen = rd_u16(body, body_len, 0, &ok);
      if (!ok || ulen == 0 || (size_t)ulen + 2u + 4u > body_len || ulen >= NS_MAX_USERNAME) {
        send_simple_response(c, OP_LOGIN, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }
      const char *uname = (const char *)(body + 2);
      uint32_t token = rd_u32(body, body_len, 2u + (size_t)ulen, &ok);
      if (!ok) {
        send_simple_response(c, OP_LOGIN, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }

      // Token = CRC32(username || server_nonce_be64) (simple demo auth)
      uint8_t tmp[NS_MAX_USERNAME + 8];
      memcpy(tmp, uname, ulen);
      ns_put_be64(tmp + ulen, shm->server_nonce);
      uint32_t want = ns_crc32(tmp, (size_t)ulen + 8u);
      if (token != want) {
        send_simple_response(c, OP_LOGIN, ST_ERR_UNAUTHORIZED, req_id, NULL, 0);
        break;
      }

      uint32_t uid = 0;
      pthread_mutex_lock(&shm->user_mu);
      char ustr[NS_MAX_USERNAME];
      memset(ustr, 0, sizeof(ustr));
      memcpy(ustr, uname, ulen);
      int rc = ns_user_find_or_create(shm, ustr, &uid);
      pthread_mutex_unlock(&shm->user_mu);
      if (rc != 0) {
        send_simple_response(c, OP_LOGIN, ST_ERR_INTERNAL, req_id, NULL, 0);
        break;
      }
      c->authed = true;
      c->user_id = uid;

      // Response body: u32 user_id + i64 balance
      uint8_t resp[4 + 8];
      ns_put_be32(resp, uid);
      int64_t bal = shm->balance[uid];
      ns_put_be64(resp + 4, (uint64_t)bal);
      send_simple_response(c, OP_LOGIN, ST_OK, req_id, resp, (uint32_t)sizeof(resp));
      break;
    }
    case OP_HEARTBEAT: {
      send_simple_response(c, OP_HEARTBEAT, ST_OK, req_id, NULL, 0);
      break;
    }
    case OP_JOIN_ROOM: {
      bool ok = true;
      uint16_t room = rd_u16(body, body_len, 0, &ok);
      if (!ok || room >= NS_MAX_ROOMS) {
        send_simple_response(c, OP_JOIN_ROOM, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }
      pthread_mutex_lock(&shm->room_mu[room]);
      ns_room_set_member(shm, room, c->user_id, true);
      pthread_mutex_unlock(&shm->room_mu[room]);
      send_simple_response(c, OP_JOIN_ROOM, ST_OK, req_id, NULL, 0);
      break;
    }
    case OP_LEAVE_ROOM: {
      bool ok = true;
      uint16_t room = rd_u16(body, body_len, 0, &ok);
      if (!ok || room >= NS_MAX_ROOMS) {
        send_simple_response(c, OP_LEAVE_ROOM, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }
      pthread_mutex_lock(&shm->room_mu[room]);
      ns_room_set_member(shm, room, c->user_id, false);
      pthread_mutex_unlock(&shm->room_mu[room]);
      send_simple_response(c, OP_LEAVE_ROOM, ST_OK, req_id, NULL, 0);
      break;
    }
    case OP_CHAT_SEND: {
      // Body: u16 room_id + u16 msg_len + msg
      bool ok = true;
      uint16_t room = rd_u16(body, body_len, 0, &ok);
      uint16_t mlen = rd_u16(body, body_len, 2, &ok);
      if (!ok || room >= NS_MAX_ROOMS || (size_t)mlen + 4u > body_len) {
        send_simple_response(c, OP_CHAT_SEND, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }
      pthread_mutex_lock(&shm->room_mu[room]);
      bool member = ns_room_is_member(shm, room, c->user_id);
      pthread_mutex_unlock(&shm->room_mu[room]);
      if (!member) {
        send_simple_response(c, OP_CHAT_SEND, ST_ERR_UNAUTHORIZED, req_id, NULL, 0);
        break;
      }

      ns_chat_append(shm, room, c->user_id, (const char *)(body + 4), mlen);
      // notify all workers
      uint64_t one = 1;
      (void)write(notify_efd, &one, sizeof(one));
      send_simple_response(c, OP_CHAT_SEND, ST_OK, req_id, NULL, 0);
      break;
    }
    case OP_DEPOSIT:
    case OP_WITHDRAW: {
      bool ok = true;
      if (body_len < 8u) {
        send_simple_response(c, opcode, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }
      int64_t amount = (int64_t)rd_u64(body, body_len, 0, &ok);
      if (!ok) {
        send_simple_response(c, opcode, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }
      if (amount <= 0) {
        send_simple_response(c, opcode, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }

      uint16_t st = ST_OK;
      pthread_mutex_lock(&shm->acct_mu[c->user_id]);
      if (opcode == OP_WITHDRAW && shm->balance[c->user_id] < amount) {
        st = ST_ERR_INSUFFICIENT_FUNDS;
      } else {
        shm->balance[c->user_id] += (opcode == OP_DEPOSIT) ? amount : -amount;
      }
      int64_t bal = shm->balance[c->user_id];
      pthread_mutex_unlock(&shm->acct_mu[c->user_id]);

      ns_txn_append(shm, opcode, st, c->user_id, c->user_id, amount);

      uint8_t resp[8];
      ns_put_be64(resp, (uint64_t)bal);
      send_simple_response(c, opcode, st, req_id, resp, (uint32_t)sizeof(resp));
      break;
    }
    case OP_TRANSFER: {
      // Body: u32 to_user_id + i64 amount
      bool ok = true;
      uint32_t to_uid = rd_u32(body, body_len, 0, &ok);
      int64_t amount = (int64_t)rd_u64(body, body_len, 4, &ok);
      if (!ok || to_uid >= NS_MAX_USERS || amount <= 0) {
        send_simple_response(c, OP_TRANSFER, ST_ERR_BAD_PACKET, req_id, NULL, 0);
        break;
      }
      uint32_t from = c->user_id;
      uint32_t a = from < to_uid ? from : to_uid;
      uint32_t b = from < to_uid ? to_uid : from;

      uint16_t st = ST_OK;
      pthread_mutex_lock(&shm->acct_mu[a]);
      pthread_mutex_lock(&shm->acct_mu[b]);
      if (shm->balance[from] < amount) {
        st = ST_ERR_INSUFFICIENT_FUNDS;
      } else {
        shm->balance[from] -= amount;
        shm->balance[to_uid] += amount;
      }
      int64_t bal = shm->balance[from];
      pthread_mutex_unlock(&shm->acct_mu[b]);
      pthread_mutex_unlock(&shm->acct_mu[a]);

      ns_txn_append(shm, OP_TRANSFER, st, from, to_uid, amount);

      uint8_t resp[8];
      ns_put_be64(resp, (uint64_t)bal);
      send_simple_response(c, OP_TRANSFER, st, req_id, resp, (uint32_t)sizeof(resp));
      break;
    }
    case OP_BALANCE: {
      pthread_mutex_lock(&shm->acct_mu[c->user_id]);
      int64_t bal = shm->balance[c->user_id];
      pthread_mutex_unlock(&shm->acct_mu[c->user_id]);
      uint8_t resp[8];
      ns_put_be64(resp, (uint64_t)bal);
      send_simple_response(c, OP_BALANCE, ST_OK, req_id, resp, (uint32_t)sizeof(resp));
      break;
    }
    default:
      send_simple_response(c, opcode, ST_ERR_BAD_PACKET, req_id, NULL, 0);
      break;
  }
}

static int handle_conn_io(int epfd, ns_shm_t *shm, int notify_efd, conn_t *c, const server_cfg_t *cfg) {
  // Read
  while (true) {
    ssize_t n = recv(c->fd, c->rbuf + c->rlen, sizeof(c->rbuf) - c->rlen, 0);
    if (n > 0) {
      c->rlen += (size_t)n;
    } else if (n == 0) {
      return -1;
    } else {
      if (errno == EAGAIN || errno == EWOULDBLOCK) break;
      return -1;
    }
  }

  // Parse frames
  size_t off = 0;
  while (c->rlen - off >= sizeof(ns_header_t)) {
    ns_header_t hdr;
    memcpy(&hdr, c->rbuf + off, sizeof(hdr));
    if (!ns_validate_header_basic(&hdr, cfg->max_body_len)) {
      metric_inc_u64(&shm->total_errors, 1);
      return -1;
    }
    uint32_t body_len = ns_be32(&hdr.body_len);
    size_t frame_len = sizeof(ns_header_t) + (size_t)body_len;
    if (c->rlen - off < frame_len) break;

    const uint8_t *body = (body_len ? (c->rbuf + off + sizeof(ns_header_t)) : NULL);
    if (!ns_validate_checksum(&hdr, body, body_len)) {
      metric_inc_u64(&shm->total_errors, 1);
      // respond with checksum error and close
      send_simple_response(c, ns_be16(&hdr.opcode), ST_ERR_CHECKSUM_FAIL, ns_be64(&hdr.req_id), NULL, 0);
      return -1;
    }

    handle_request(shm, notify_efd, c, &hdr, body, body_len);

    off += frame_len;
  }

  if (off > 0) {
    memmove(c->rbuf, c->rbuf + off, c->rlen - off);
    c->rlen -= off;
  }

  // Write
  while (c->wpos < c->wlen) {
    ssize_t n = send(c->fd, c->wbuf + c->wpos, c->wlen - c->wpos, 0);
    if (n > 0) c->wpos += (size_t)n;
    else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) break;
    else return -1;
  }

  if (c->wpos == c->wlen) {
    c->wpos = c->wlen = 0;
    // back to read-only interest
    (void)ep_mod(epfd, c->fd, EPOLLIN | EPOLLRDHUP, c);
  } else {
    (void)ep_mod(epfd, c->fd, EPOLLIN | EPOLLOUT | EPOLLRDHUP, c);
  }

  return 0;
}

int worker_run(int worker_id, int listen_fd, int notify_efd, ns_shm_t *shm, const server_cfg_t *cfg) {
  char pname[64];
  snprintf(pname, sizeof(pname), "server-w%d", worker_id);
  log_set_program(pname);

  int epfd = epoll_create1(0);
  if (epfd < 0) return -1;

  // fd map for connection pointers
  struct rlimit rl;
  if (getrlimit(RLIMIT_NOFILE, &rl) != 0) {
    close(epfd);
    return -1;
  }
  size_t fdcap = (size_t)rl.rlim_cur;
  if (fdcap > 200000u) fdcap = 200000u;
  conn_t **fdmap = (conn_t **)calloc(fdcap, sizeof(conn_t *));
  if (!fdmap) {
    close(epfd);
    return -1;
  }

  // add listen fd and notify efd
  (void)net_set_nonblocking(listen_fd, true);
  if (ep_add(epfd, listen_fd, EPOLLIN, (void *)(uintptr_t)listen_fd) != 0) {
    free(fdmap);
    close(epfd);
    return -1;
  }
  if (ep_add(epfd, notify_efd, EPOLLIN, (void *)(uintptr_t)notify_efd) != 0) {
    free(fdmap);
    close(epfd);
    return -1;
  }

  uint64_t last_chat_seq = ns_chat_latest_seq(shm);
  struct epoll_event events[256];

  LOG_INFO("Worker started (pid=%d)", (int)getpid());

  while (true) {
    int n = epoll_wait(epfd, events, 256, 1000);
    if (n < 0) {
      if (errno == EINTR) continue;
      break;
    }

    // periodic broadcast drain (in case notifications are coalesced)
    handle_chat_broadcast(shm, fdmap, fdcap, &last_chat_seq);

    for (int i = 0; i < n; i++) {
      void *ptr = events[i].data.ptr;
      if (ptr == (void *)(uintptr_t)listen_fd) {
        while (true) {
          struct sockaddr_storage ss;
          socklen_t sl = (socklen_t)sizeof(ss);
          int cfd = accept(listen_fd, (struct sockaddr *)&ss, &sl);
          if (cfd < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            break;
          }
          (void)net_set_nonblocking(cfd, true);
          (void)net_set_tcp_nodelay(cfd);
          metric_inc_u64(&shm->total_connections, 1);

          if ((size_t)cfd >= fdcap) {
            close(cfd);
            continue;
          }

          conn_t *c = (conn_t *)calloc(1, sizeof(*c));
          c->fd = cfd;
          c->wcap = 0;
          c->wbuf = NULL;
          fdmap[cfd] = c;

          (void)ep_add(epfd, cfd, EPOLLIN | EPOLLRDHUP, c);
        }
        continue;
      }

      if (ptr == (void *)(uintptr_t)notify_efd) {
        uint64_t val = 0;
        while (read(notify_efd, &val, sizeof(val)) > 0) {
          // drain
        }
        handle_chat_broadcast(shm, fdmap, fdcap, &last_chat_seq);
        continue;
      }

      conn_t *c = (conn_t *)ptr;
      int fd = c->fd;
      if (fd < 0 || (size_t)fd >= fdcap || fdmap[fd] != c) continue;

      if ((events[i].events & (EPOLLHUP | EPOLLERR | EPOLLRDHUP)) != 0u) {
        fdmap[fd] = NULL;
        conn_free(c);
        continue;
      }

      if (handle_conn_io(epfd, shm, notify_efd, c, cfg) != 0) {
        fdmap[fd] = NULL;
        conn_free(c);
        continue;
      }
    }
  }

  // cleanup
  for (size_t fd = 0; fd < fdcap; fd++) {
    if (fdmap[fd]) conn_free(fdmap[fd]);
  }
  free(fdmap);
  close(epfd);
  return 0;
}


