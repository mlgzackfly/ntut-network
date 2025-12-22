#include "shm_state.h"
#include "proto.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void init_local_shm(ns_shm_t *s) {
  memset(s, 0, sizeof(*s));
  pthread_mutex_init(&s->chat_mu, NULL);
  pthread_mutex_init(&s->txn_mu, NULL);
  for (uint32_t i = 0; i < NS_MAX_USERS; i++) {
    pthread_mutex_init(&s->acct_mu[i], NULL);
    s->balance[i] = 100000; // mirror ns_shm_init_if_needed default
  }
  for (uint32_t r = 0; r < NS_MAX_ROOMS; r++) {
    pthread_mutex_init(&s->room_mu[r], NULL);
  }
}

static void test_room_membership(void) {
  ns_shm_t s;
  init_local_shm(&s);

  uint16_t room = 1;
  uint32_t uid = 10;
  assert(!ns_room_is_member(&s, room, uid));
  ns_room_set_member(&s, room, uid, true);
  assert(ns_room_is_member(&s, room, uid));
  ns_room_set_member(&s, room, uid, false);
  assert(!ns_room_is_member(&s, room, uid));
}

static void test_chat_ring(void) {
  ns_shm_t s;
  init_local_shm(&s);

  uint64_t seq = 0;
  ns_chat_event_t evs[4];

  ns_chat_append(&s, 1, 10, "hi", 2);
  ns_chat_append(&s, 1, 11, "yo", 2);

  uint64_t n = ns_chat_read_from(&s, &seq, evs, 4);
  assert(n == 2);
  assert(evs[0].room_id == 1 && evs[0].from_user_id == 10);
  assert(evs[1].room_id == 1 && evs[1].from_user_id == 11);
}

static void test_asset_conservation(void) {
  ns_shm_t s;
  init_local_shm(&s);

  int64_t current = 0, expected = 0;
  // 初始狀態：所有帳戶都是 100000，應該通過資產守恆檢查
  assert(ns_check_asset_conservation(&s, &current, &expected) == 0);
  assert(current == expected);

  // 模擬一次成功 DEPOSIT 與 WITHDRAW
  uint32_t uid = 5;
  int64_t dep = 1000;
  int64_t wd = 500;

  pthread_mutex_lock(&s.acct_mu[uid]);
  s.balance[uid] += dep;
  pthread_mutex_unlock(&s.acct_mu[uid]);
  ns_txn_append(&s, OP_DEPOSIT, ST_OK, uid, uid, dep);

  pthread_mutex_lock(&s.acct_mu[uid]);
  s.balance[uid] -= wd;
  pthread_mutex_unlock(&s.acct_mu[uid]);
  ns_txn_append(&s, OP_WITHDRAW, ST_OK, uid, uid, wd);

  assert(ns_check_asset_conservation(&s, &current, &expected) == 0);
  assert(current == expected);

  // 人為破壞一個帳戶餘額，應該檢查失敗
  pthread_mutex_lock(&s.acct_mu[0]);
  s.balance[0] += 1;
  pthread_mutex_unlock(&s.acct_mu[0]);
  assert(ns_check_asset_conservation(&s, &current, &expected) == -1);
}

int main(void) {
  test_room_membership();
  test_chat_ring();
  test_asset_conservation();
  printf("test_shm: OK\n");
  return 0;
}


