#pragma once

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>

#define NS_MAX_USERS 1024u
#define NS_MAX_ROOMS 64u
#define NS_MAX_USERNAME 32u
#define NS_MAX_CHAT_MSG 256u

#define NS_CHAT_RING_SIZE 4096u
#define NS_TXN_RING_SIZE 4096u

#define NS_SHM_MAGIC 0x4E535348u /* 'N''S''S''H' */

typedef struct {
  uint64_t seq;
  uint64_t ts_ms;
  uint16_t room_id;
  uint32_t from_user_id;
  uint16_t msg_len;
  char msg[NS_MAX_CHAT_MSG];
} ns_chat_event_t;

typedef struct {
  uint64_t seq;
  uint64_t ts_ms;
  uint16_t opcode;
  uint16_t status;
  uint32_t from_user_id;
  uint32_t to_user_id;
  int64_t amount;
} ns_txn_event_t;

typedef struct {
  uint32_t magic;
  uint32_t version;
  uint64_t server_nonce;

  // Global metrics (use atomic add on these)
  uint64_t total_connections;
  uint64_t total_requests;
  uint64_t total_errors;
  uint64_t op_counts[0x0300]; // enough for our opcodes

  // User table
  pthread_mutex_t user_mu;
  bool user_used[NS_MAX_USERS];
  bool user_online[NS_MAX_USERS];
  char username[NS_MAX_USERS][NS_MAX_USERNAME];

  // Ledger
  pthread_mutex_t acct_mu[NS_MAX_USERS];
  int64_t balance[NS_MAX_USERS];

  // Rooms (bitset: NS_MAX_USERS bits per room)
  pthread_mutex_t room_mu[NS_MAX_ROOMS];
  uint64_t room_members[NS_MAX_ROOMS][NS_MAX_USERS / 64u];

  // Chat event ring (cross-worker broadcast)
  pthread_mutex_t chat_mu;
  uint64_t chat_write_seq;
  ns_chat_event_t chat_ring[NS_CHAT_RING_SIZE];

  // Transaction log ring (auditing)
  pthread_mutex_t txn_mu;
  uint64_t txn_write_seq;
  ns_txn_event_t txn_ring[NS_TXN_RING_SIZE];
} ns_shm_t;

typedef struct {
  int shm_fd;
  ns_shm_t *shm;
} ns_shm_handle_t;

int ns_shm_create_or_open(ns_shm_handle_t *out, const char *name, bool create);
int ns_shm_init_if_needed(ns_shm_handle_t *h);
void ns_shm_close(ns_shm_handle_t *h, const char *name, bool unlink_on_close);

// User helpers (expect caller to hold user_mu where needed)
int ns_user_find_or_create(ns_shm_t *s, const char *username, uint32_t *out_user_id);

// Room membership helpers
void ns_room_set_member(ns_shm_t *s, uint16_t room_id, uint32_t user_id, bool member);
bool ns_room_is_member(const ns_shm_t *s, uint16_t room_id, uint32_t user_id);

// Ring buffer helpers
void ns_chat_append(ns_shm_t *s, uint16_t room_id, uint32_t from_user_id, const char *msg, uint16_t msg_len);
uint64_t ns_chat_latest_seq(const ns_shm_t *s);
uint64_t ns_chat_read_from(ns_shm_t *s, uint64_t *inout_seq, ns_chat_event_t *out_events, uint32_t max_events);

void ns_txn_append(ns_shm_t *s, uint16_t opcode, uint16_t status, uint32_t from_uid, uint32_t to_uid, int64_t amount);

// Asset conservation invariant check
// Returns 0 if invariant holds, -1 if violated
// Computes: sum(balances) == initial_total + sum(deposits) - sum(withdrawals)
int ns_check_asset_conservation(const ns_shm_t *s, int64_t *out_current_total, int64_t *out_expected_total);




