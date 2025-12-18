#include "log.h"
#include "net.h"
#include "shm_state.h"
#include "worker.h"

#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __linux__
#include <sys/eventfd.h>
#endif

static volatile sig_atomic_t g_stop = 0;
static void on_sig(int sig) {
  (void)sig;
  g_stop = 1;
}

static void usage(const char *prog) {
  fprintf(stderr,
          "Usage: %s [--bind 0.0.0.0] [--port 9000] [--workers 4] [--shm /ns_shm]\n",
          prog);
}

static uint16_t parse_u16(const char *s, uint16_t def) {
  if (!s) return def;
  long v = strtol(s, NULL, 10);
  if (v <= 0 || v > 65535) return def;
  return (uint16_t)v;
}

static int parse_i(const char *s, int def) {
  if (!s) return def;
  long v = strtol(s, NULL, 10);
  if (v <= 0 || v > 1024) return def;
  return (int)v;
}

int main(int argc, char **argv) {
  log_set_program("server");

  server_cfg_t cfg;
  memset(&cfg, 0, sizeof(cfg));
  cfg.bind_ip = NULL; // INADDR_ANY
  cfg.port = 9000;
  cfg.workers = 4;
  cfg.shm_name = "/ns_trading_chat";
  cfg.max_body_len = 65536;
  cfg.max_connections_per_worker = 1000; // Default limit per worker
  cfg.recv_timeout_ms = 30000; // 30 seconds
  cfg.send_timeout_ms = 30000; // 30 seconds

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--bind") == 0 && i + 1 < argc) {
      cfg.bind_ip = argv[++i];
    } else if (strcmp(argv[i], "--port") == 0 && i + 1 < argc) {
      cfg.port = parse_u16(argv[++i], cfg.port);
    } else if (strcmp(argv[i], "--workers") == 0 && i + 1 < argc) {
      cfg.workers = parse_i(argv[++i], cfg.workers);
    } else if (strcmp(argv[i], "--shm") == 0 && i + 1 < argc) {
      cfg.shm_name = argv[++i];
    } else if (strcmp(argv[i], "--help") == 0) {
      usage(argv[0]);
      return 0;
    } else {
      usage(argv[0]);
      return 2;
    }
  }

  signal(SIGINT, on_sig);
  signal(SIGTERM, on_sig);

  ns_shm_handle_t shm_h;
  if (ns_shm_create_or_open(&shm_h, cfg.shm_name, true) != 0) {
    LOG_ERROR("shm_open failed: %s", strerror(errno));
    return 1;
  }
  if (ns_shm_init_if_needed(&shm_h) != 0) {
    LOG_ERROR("shm init failed: %s", strerror(errno));
    ns_shm_close(&shm_h, cfg.shm_name, true);
    return 1;
  }

  int listen_fd = net_listen_tcp(cfg.bind_ip, cfg.port, 4096, true);
  if (listen_fd < 0) {
    LOG_ERROR("listen failed: %s", strerror(errno));
    ns_shm_close(&shm_h, cfg.shm_name, true);
    return 1;
  }

  int notify_rfd = -1;
  int notify_wfd = -1;
#ifdef __linux__
  int efd = eventfd(0, EFD_NONBLOCK);
  if (efd < 0) {
    LOG_ERROR("eventfd failed: %s", strerror(errno));
    close(listen_fd);
    ns_shm_close(&shm_h, cfg.shm_name, true);
    return 1;
  }
  notify_rfd = efd;
  notify_wfd = efd;
#else
  int pfd[2];
  if (pipe(pfd) != 0) {
    LOG_ERROR("pipe failed: %s", strerror(errno));
    close(listen_fd);
    ns_shm_close(&shm_h, cfg.shm_name, true);
    return 1;
  }
  notify_rfd = pfd[0];
  notify_wfd = pfd[1];
#endif

  LOG_INFO("Server starting: port=%u workers=%d shm=%s", cfg.port, cfg.workers, cfg.shm_name);

  pid_t *pids = (pid_t *)calloc((size_t)cfg.workers, sizeof(pid_t));
  if (!pids) {
    if (notify_rfd >= 0) close(notify_rfd);
#ifndef __linux__
    if (notify_wfd >= 0) close(notify_wfd);
#endif
    close(listen_fd);
    ns_shm_close(&shm_h, cfg.shm_name, true);
    return 1;
  }

  for (int w = 0; w < cfg.workers; w++) {
    pid_t pid = fork();
    if (pid < 0) {
      LOG_ERROR("fork failed: %s", strerror(errno));
      g_stop = 1;
      break;
    }
    if (pid == 0) {
      // worker
      (void)worker_run2(w, listen_fd, notify_rfd, notify_wfd, shm_h.shm, &cfg);
      _exit(0);
    }
    pids[w] = pid;
  }

  // master loop: wait for stop, restart dead workers
  while (!g_stop) {
    int status = 0;
    pid_t pid = waitpid(-1, &status, WNOHANG);
    if (pid > 0) {
      // Find which worker exited
      int worker_idx = -1;
      for (int w = 0; w < cfg.workers; w++) {
        if (pids[w] == pid) {
          worker_idx = w;
          break;
        }
      }
      if (worker_idx >= 0) {
        LOG_WARN("Worker %d exited pid=%d status=%d, restarting...", worker_idx, (int)pid, status);
        // Restart the worker
        pid_t new_pid = fork();
        if (new_pid < 0) {
          LOG_ERROR("Failed to restart worker %d: %s", worker_idx, strerror(errno));
          pids[worker_idx] = 0; // Mark as failed
        } else if (new_pid == 0) {
          // worker
          (void)worker_run2(worker_idx, listen_fd, notify_rfd, notify_wfd, shm_h.shm, &cfg);
          _exit(0);
        } else {
          pids[worker_idx] = new_pid;
          LOG_INFO("Worker %d restarted with pid=%d", worker_idx, (int)new_pid);
        }
      }
    }
    usleep(200000);
  }

  LOG_INFO("Shutting down...");
  // Stop accepting new connections and signal workers to stop
  for (int w = 0; w < cfg.workers; w++) {
    if (pids[w] > 0) {
      kill(pids[w], SIGTERM);
    }
  }
  // Wait for all workers to exit (with timeout)
  for (int w = 0; w < cfg.workers; w++) {
    if (pids[w] > 0) {
      int waited = 0;
      for (int i = 0; i < 50; i++) { // 5 second timeout
        pid_t pid = waitpid(pids[w], NULL, WNOHANG);
        if (pid == pids[w]) {
          waited = 1;
          break;
        }
        usleep(100000); // 100ms
      }
      if (!waited) {
        LOG_WARN("Worker %d (pid=%d) did not exit gracefully, sending SIGKILL", w, (int)pids[w]);
        kill(pids[w], SIGKILL);
        waitpid(pids[w], NULL, 0);
      }
    }
  }

  free(pids);
#ifdef __linux__
  close(notify_rfd);
#else
  close(notify_rfd);
  close(notify_wfd);
#endif
  close(listen_fd);
  ns_shm_close(&shm_h, cfg.shm_name, true);
  LOG_INFO("Shutdown complete.");
  return 0;
}


