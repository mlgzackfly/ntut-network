#include "log.h"

#include <stdarg.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

static log_level_t g_level = LOG_LEVEL_INFO;
static const char *g_prog = "app";

void log_set_level(log_level_t level) { g_level = level; }
void log_set_program(const char *name) {
  if (name && *name) g_prog = name;
}

static const char *level_name(log_level_t lvl) {
  switch (lvl) {
    case LOG_LEVEL_DEBUG: return "DEBUG";
    case LOG_LEVEL_INFO: return "INFO";
    case LOG_LEVEL_WARN: return "WARN";
    case LOG_LEVEL_ERROR: return "ERROR";
    default: return "UNK";
  }
}

void log_msg(log_level_t level, const char *file, int line, const char *fmt, ...) {
  if (level < g_level) return;

  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  struct tm tm;
  localtime_r(&ts.tv_sec, &tm);

  char tbuf[64];
  strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", &tm);

  fprintf(stderr, "%s.%03ld [%s] pid=%d %s %s:%d: ",
          tbuf, ts.tv_nsec / 1000000L, g_prog, (int)getpid(),
          level_name(level), file, line);

  va_list ap;
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
}


