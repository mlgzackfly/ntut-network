#pragma once

#include "shm_state.h"

#include <stdint.h>

typedef struct {
  const char *bind_ip;
  uint16_t port;
  int workers;
  const char *shm_name;
  uint32_t max_body_len;
} server_cfg_t;

int worker_run(int worker_id, int listen_fd, int notify_efd, ns_shm_t *shm, const server_cfg_t *cfg);


