#pragma once

#include "shm_state.h"

#include <stdint.h>

typedef struct {
  const char *bind_ip;
  uint16_t port;
  int workers;
  const char *shm_name;
  uint32_t max_body_len;
  uint32_t max_connections_per_worker; // 0 = unlimited
  int recv_timeout_ms;
  int send_timeout_ms;
} server_cfg_t;

int worker_run(int worker_id, int listen_fd, int notify_efd, ns_shm_t *shm, const server_cfg_t *cfg);
// notify_rfd is used for epoll read; notify_wfd is used to wake other workers.
// On Linux with eventfd you can pass the same fd for both.
int worker_run2(int worker_id, int listen_fd, int notify_rfd, int notify_wfd, ns_shm_t *shm, const server_cfg_t *cfg);


