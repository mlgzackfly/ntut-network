#include "stats.h"

#include <stdlib.h>

void stats_init(stats_t *s) {
  s->lat_us = NULL;
  s->len = 0;
  s->cap = 0;
  s->ok = 0;
  s->err = 0;
}

void stats_free(stats_t *s) {
  if (!s) return;
  free(s->lat_us);
  s->lat_us = NULL;
  s->len = 0;
  s->cap = 0;
}

int stats_push_latency_us(stats_t *s, uint64_t us) {
  if (s->len == s->cap) {
    size_t ncap = s->cap ? s->cap * 2u : 4096u;
    uint64_t *p = (uint64_t *)realloc(s->lat_us, ncap * sizeof(uint64_t));
    if (!p) return -1;
    s->lat_us = p;
    s->cap = ncap;
  }
  s->lat_us[s->len++] = us;
  return 0;
}

static int cmp_u64(const void *a, const void *b) {
  uint64_t x = *(const uint64_t *)a;
  uint64_t y = *(const uint64_t *)b;
  if (x < y) return -1;
  if (x > y) return 1;
  return 0;
}

uint64_t stats_percentile_us(stats_t *s, double p) {
  if (!s || s->len == 0) return 0;
  if (p < 0) p = 0;
  if (p > 100) p = 100;

  // Sort in-place (caller should call at the end)
  qsort(s->lat_us, s->len, sizeof(uint64_t), cmp_u64);
  double rank = (p / 100.0) * (double)(s->len - 1);
  size_t idx = (size_t)rank;
  return s->lat_us[idx];
}



