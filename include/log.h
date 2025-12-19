#pragma once

#include <stdint.h>

typedef enum {
  LOG_LEVEL_DEBUG = 0,
  LOG_LEVEL_INFO = 1,
  LOG_LEVEL_WARN = 2,
  LOG_LEVEL_ERROR = 3,
} log_level_t;

void log_set_level(log_level_t level);
void log_set_program(const char *name);

void log_msg(log_level_t level, const char *file, int line, const char *fmt, ...);

#define LOG_DEBUG(...) log_msg(LOG_LEVEL_DEBUG, __FILE__, __LINE__, __VA_ARGS__)
#define LOG_INFO(...)  log_msg(LOG_LEVEL_INFO,  __FILE__, __LINE__, __VA_ARGS__)
#define LOG_WARN(...)  log_msg(LOG_LEVEL_WARN,  __FILE__, __LINE__, __VA_ARGS__)
#define LOG_ERROR(...) log_msg(LOG_LEVEL_ERROR, __FILE__, __LINE__, __VA_ARGS__)




