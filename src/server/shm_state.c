#include "shm_state.h"

#include "log.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static uint64_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (uint64_t)ts.tv_sec * 1000ull + (uint64_t)(ts.tv_nsec / 1000000ull);
}

int ns_shm_create_or_open(ns_shm_handle_t *out, const char *name, bool create) {
  memset(out, 0, sizeof(*out));
  int flags = O_RDWR;
  if (create) flags |= O_CREAT;

  int fd = shm_open(name, flags, 0600);
  if (fd < 0) return -1;

  size_t sz = sizeof(ns_shm_t);
  if (create) {
    if (ftruncate(fd, (off_t)sz) != 0) {
      close(fd);
      return -1;
    }
  } else {
    struct stat st;
    if (fstat(fd, &st) != 0) {
      close(fd);
      return -1;
    }
    if ((size_t)st.st_size < sz) {
      errno = EINVAL;
      close(fd);
      return -1;
    }
  }

  void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (p == MAP_FAILED) {
    close(fd);
    return -1;
  }

  out->shm_fd = fd;
  out->shm = (ns_shm_t *)p;
  return 0;
}

static int init_mutex(pthread_mutex_t *m, pthread_mutexattr_t *attr) {
  int rc = pthread_mutex_init(m, attr);
  return rc == 0 ? 0 : -1;
}

int ns_shm_init_if_needed(ns_shm_handle_t *h) {
  if (!h || !h->shm) {
    errno = EINVAL;
    return -1;
  }

  ns_shm_t *s = h->shm;
  if (s->magic == NS_SHM_MAGIC && s->version == 1u) return 0;

  memset(s, 0, sizeof(*s));
  s->magic = NS_SHM_MAGIC;
  s->version = 1u;

  // Nonce: best-effort randomness
  uint64_t seed = now_ms() ^ ((uint64_t)getpid() << 32u);
  s->server_nonce = seed ^ 0x9E3779B97F4A7C15ull;

  pthread_mutexattr_t attr;
  if (pthread_mutexattr_init(&attr) != 0) return -1;
  if (pthread_mutexattr_setpshared(&attr, PTHREAD_PROCESS_SHARED) != 0) return -1;

  if (init_mutex(&s->user_mu, &attr) != 0) return -1;
  if (init_mutex(&s->chat_mu, &attr) != 0) return -1;
  if (init_mutex(&s->txn_mu, &attr) != 0) return -1;

  for (uint32_t i = 0; i < NS_MAX_USERS; i++) {
    if (init_mutex(&s->acct_mu[i], &attr) != 0) return -1;
    s->balance[i] = 100000; // initial balance for demos/tests
  }
  for (uint32_t r = 0; r < NS_MAX_ROOMS; r++) {
    if (init_mutex(&s->room_mu[r], &attr) != 0) return -1;
  }

  pthread_mutexattr_destroy(&attr);
  LOG_INFO("Initialized shared memory state (nonce=%llu)", (unsigned long long)s->server_nonce);
  return 0;
}

void ns_shm_close(ns_shm_handle_t *h, const char *name, bool unlink_on_close) {
  if (!h) return;
  if (h->shm) {
    munmap(h->shm, sizeof(ns_shm_t));
    h->shm = NULL;
  }
  if (h->shm_fd > 0) {
    close(h->shm_fd);
    h->shm_fd = 0;
  }
  if (unlink_on_close && name) {
    shm_unlink(name);
  }
}

int ns_user_find_or_create(ns_shm_t *s, const char *uname, uint32_t *out_user_id) {
  if (!s || !uname || !out_user_id) return -1;
  size_t n = strnlen(uname, NS_MAX_USERNAME);
  if (n == 0 || n >= NS_MAX_USERNAME) return -1;

  // Simple hash
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < n; i++) {
    h ^= (uint8_t)uname[i];
    h *= 16777619u;
  }
  uint32_t start = h % NS_MAX_USERS;

  for (uint32_t step = 0; step < NS_MAX_USERS; step++) {
    uint32_t id = (start + step) % NS_MAX_USERS;
    if (!s->user_used[id]) {
      s->user_used[id] = true;
      s->user_online[id] = true;
      memset(s->username[id], 0, NS_MAX_USERNAME);
      memcpy(s->username[id], uname, n);
      *out_user_id = id;
      return 0;
    }
    if (strncmp(s->username[id], uname, NS_MAX_USERNAME) == 0) {
      s->user_online[id] = true;
      *out_user_id = id;
      return 0;
    }
  }
  return -1;
}

static inline void bit_set(uint64_t *bits, uint32_t idx, bool on) {
  uint32_t w = idx / 64u;
  uint32_t b = idx % 64u;
  uint64_t mask = 1ull << b;
  if (on) bits[w] |= mask;
  else bits[w] &= ~mask;
}
static inline bool bit_get(const uint64_t *bits, uint32_t idx) {
  uint32_t w = idx / 64u;
  uint32_t b = idx % 64u;
  return ((bits[w] >> b) & 1ull) != 0ull;
}

void ns_room_set_member(ns_shm_t *s, uint16_t room_id, uint32_t user_id, bool member) {
  if (!s) return;
  if (room_id >= NS_MAX_ROOMS) return;
  if (user_id >= NS_MAX_USERS) return;
  bit_set(s->room_members[room_id], user_id, member);
}

bool ns_room_is_member(const ns_shm_t *s, uint16_t room_id, uint32_t user_id) {
  if (!s) return false;
  if (room_id >= NS_MAX_ROOMS) return false;
  if (user_id >= NS_MAX_USERS) return false;
  return bit_get(s->room_members[room_id], user_id);
}

void ns_chat_append(ns_shm_t *s, uint16_t room_id, uint32_t from_user_id, const char *msg, uint16_t msg_len) {
  if (!s || !msg) return;
  if (room_id >= NS_MAX_ROOMS) return;
  if (msg_len > NS_MAX_CHAT_MSG) msg_len = NS_MAX_CHAT_MSG;

  pthread_mutex_lock(&s->chat_mu);
  uint64_t seq = ++s->chat_write_seq;
  ns_chat_event_t *e = &s->chat_ring[seq % NS_CHAT_RING_SIZE];
  memset(e, 0, sizeof(*e));
  e->seq = seq;
  e->ts_ms = now_ms();
  e->room_id = room_id;
  e->from_user_id = from_user_id;
  e->msg_len = msg_len;
  memcpy(e->msg, msg, msg_len);
  pthread_mutex_unlock(&s->chat_mu);
}

uint64_t ns_chat_latest_seq(const ns_shm_t *s) {
  return s ? s->chat_write_seq : 0;
}

uint64_t ns_chat_read_from(ns_shm_t *s, uint64_t *inout_seq, ns_chat_event_t *out_events, uint32_t max_events) {
  if (!s || !inout_seq || !out_events || max_events == 0) return 0;

  pthread_mutex_lock(&s->chat_mu);
  uint64_t latest = s->chat_write_seq;
  uint64_t seq = *inout_seq;

  if (seq + NS_CHAT_RING_SIZE < latest) {
    // fell behind; skip to the oldest available
    seq = latest > NS_CHAT_RING_SIZE ? (latest - NS_CHAT_RING_SIZE) : 0;
  }

  uint64_t count = 0;
  for (uint64_t cur = seq + 1; cur <= latest && count < max_events; cur++) {
    out_events[count] = s->chat_ring[cur % NS_CHAT_RING_SIZE];
    count++;
    seq = cur;
  }
  *inout_seq = seq;
  pthread_mutex_unlock(&s->chat_mu);
  return count;
}

void ns_txn_append(ns_shm_t *s, uint16_t opcode, uint16_t status, uint32_t from_uid, uint32_t to_uid, int64_t amount) {
  if (!s) return;
  pthread_mutex_lock(&s->txn_mu);
  uint64_t seq = ++s->txn_write_seq;
  ns_txn_event_t *e = &s->txn_ring[seq % NS_TXN_RING_SIZE];
  memset(e, 0, sizeof(*e));
  e->seq = seq;
  e->ts_ms = now_ms();
  e->opcode = opcode;
  e->status = status;
  e->from_user_id = from_uid;
  e->to_user_id = to_uid;
  e->amount = amount;
  pthread_mutex_unlock(&s->txn_mu);
}

int ns_check_asset_conservation(const ns_shm_t *s, int64_t *out_current_total, int64_t *out_expected_total) {
  if (!s || !out_current_total || !out_expected_total) {
    errno = EINVAL;
    return -1;
  }

  // Compute current sum of balances (need to lock all account mutexes)
  int64_t current_total = 0;
  for (uint32_t i = 0; i < NS_MAX_USERS; i++) {
    pthread_mutex_lock((pthread_mutex_t *)&s->acct_mu[i]);
    current_total += s->balance[i];
    pthread_mutex_unlock((pthread_mutex_t *)&s->acct_mu[i]);
  }

  // Compute expected total: initial_total + deposits - withdrawals
  // Initial total: NS_MAX_USERS * 100000 (from shm_state.c line 91)
  const int64_t initial_total = (int64_t)NS_MAX_USERS * 100000LL;
  int64_t deposits = 0;
  int64_t withdrawals = 0;

  pthread_mutex_lock((pthread_mutex_t *)&s->txn_mu);
  uint64_t latest_seq = s->txn_write_seq;
  // Scan transaction log ring buffer
  uint64_t start_seq = (latest_seq > NS_TXN_RING_SIZE) ? (latest_seq - NS_TXN_RING_SIZE + 1) : 1;
  for (uint64_t seq = start_seq; seq <= latest_seq; seq++) {
    const ns_txn_event_t *e = &s->txn_ring[seq % NS_TXN_RING_SIZE];
    if (e->seq != seq) continue; // Skip uninitialized entries
    if (e->status != ST_OK) continue; // Only count successful transactions
    
    if (e->opcode == OP_DEPOSIT) {
      deposits += e->amount;
    } else if (e->opcode == OP_WITHDRAW) {
      withdrawals += e->amount;
    }
    // TRANSFER doesn't change total (debit + credit cancel out)
  }
  pthread_mutex_unlock((pthread_mutex_t *)&s->txn_mu);

  int64_t expected_total = initial_total + deposits - withdrawals;
  *out_current_total = current_total;
  *out_expected_total = expected_total;

  return (current_total == expected_total) ? 0 : -1;
}




