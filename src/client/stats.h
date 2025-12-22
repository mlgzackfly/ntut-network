#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint64_t *lat_us;
  size_t len;
  size_t cap;

  uint64_t ok;
  uint64_t err;

  // Detailed error breakdown by status code (for auditing/analysis)
  uint64_t err_bad_packet;
  uint64_t err_checksum_fail;
  uint64_t err_unauthorized;
  uint64_t err_not_found;
  uint64_t err_insufficient_funds;
  uint64_t err_server_busy;
  uint64_t err_timeout;
  uint64_t err_internal;
} stats_t;

void stats_init(stats_t *s);
void stats_free(stats_t *s);
int stats_push_latency_us(stats_t *s, uint64_t us);

// percentiles: p in [0,100], returns 0 if empty
uint64_t stats_percentile_us(stats_t *s, double p);




