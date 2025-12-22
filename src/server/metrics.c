#include "shm_state.h"
#include "log.h"
#
#include <errno.h>
#include <stdio.h>
#include <string.h>
#
// Simple CLI tool to dump shared-memory metrics for debugging/auditing.
// Usage:
//   ./bin/metrics [shm_name]
// Default shm_name: /ns_trading_chat
#
int main(int argc, char **argv)
{
  const char *shm_name = "/ns_trading_chat";
  if (argc >= 2)
  {
    shm_name = argv[1];
  }

  log_set_program("metrics");

  ns_shm_handle_t h;
  if (ns_shm_create_or_open(&h, shm_name, false) != 0)
  {
    fprintf(stderr, "Failed to open shared memory '%s': %s\n", shm_name, strerror(errno));
    return 1;
  }

  ns_shm_t *s = h.shm;
  printf("Shared memory metrics (shm=%s)\n", shm_name);
  printf("total_connections=%llu\n", (unsigned long long)s->total_connections);
  printf("total_requests=%llu\n", (unsigned long long)s->total_requests);
  printf("total_errors=%llu\n", (unsigned long long)s->total_errors);

  printf("op_counts:\n");
  for (size_t i = 0; i < sizeof(s->op_counts) / sizeof(s->op_counts[0]); i++)
  {
    uint64_t v = s->op_counts[i];
    if (v == 0)
      continue;
    printf("  opcode=0x%04zx count=%llu\n", i, (unsigned long long)v);
  }

  ns_shm_close(&h, NULL, false);
  return 0;
}


