#include "net.h"

#include "log.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

int net_set_nonblocking(int fd, bool nonblocking) {
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0) return -1;
  if (nonblocking) flags |= O_NONBLOCK;
  else flags &= ~O_NONBLOCK;
  return fcntl(fd, F_SETFL, flags);
}

int net_set_reuseaddr(int fd) {
  int on = 1;
  return setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, (socklen_t)sizeof(on));
}

int net_set_reuseport(int fd) {
#ifdef SO_REUSEPORT
  int on = 1;
  return setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, (socklen_t)sizeof(on));
#else
  (void)fd;
  errno = ENOTSUP;
  return -1;
#endif
}

int net_set_tcp_nodelay(int fd) {
  int on = 1;
  return setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &on, (socklen_t)sizeof(on));
}

int net_set_timeouts_ms(int fd, int recv_timeout_ms, int send_timeout_ms) {
  struct timeval tv;
  if (recv_timeout_ms >= 0) {
    tv.tv_sec = recv_timeout_ms / 1000;
    tv.tv_usec = (recv_timeout_ms % 1000) * 1000;
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, (socklen_t)sizeof(tv)) != 0) return -1;
  }
  if (send_timeout_ms >= 0) {
    tv.tv_sec = send_timeout_ms / 1000;
    tv.tv_usec = (send_timeout_ms % 1000) * 1000;
    if (setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, (socklen_t)sizeof(tv)) != 0) return -1;
  }
  return 0;
}

int net_listen_tcp(const char *bind_ip, uint16_t port, int backlog, bool reuseport) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return -1;

  if (net_set_reuseaddr(fd) != 0) LOG_WARN("SO_REUSEADDR failed: %s", strerror(errno));
  if (reuseport) {
    if (net_set_reuseport(fd) != 0) LOG_WARN("SO_REUSEPORT failed: %s", strerror(errno));
  }

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  addr.sin_addr.s_addr = bind_ip ? inet_addr(bind_ip) : htonl(INADDR_ANY);

  if (bind(fd, (struct sockaddr *)&addr, (socklen_t)sizeof(addr)) != 0) {
    close(fd);
    return -1;
  }

  if (listen(fd, backlog) != 0) {
    close(fd);
    return -1;
  }

  return fd;
}

static int connect_with_timeout(int fd, const struct sockaddr *sa, socklen_t salen, int timeout_ms) {
  if (timeout_ms <= 0) return connect(fd, sa, salen);

  if (net_set_nonblocking(fd, true) != 0) return -1;
  int rc = connect(fd, sa, salen);
  if (rc == 0) {
    (void)net_set_nonblocking(fd, false);
    return 0;
  }
  if (errno != EINPROGRESS) return -1;

  fd_set wfds;
  FD_ZERO(&wfds);
  FD_SET(fd, &wfds);
  struct timeval tv;
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  rc = select(fd + 1, NULL, &wfds, NULL, &tv);
  if (rc <= 0) {
    errno = (rc == 0) ? ETIMEDOUT : errno;
    return -1;
  }

  int soerr = 0;
  socklen_t slen = (socklen_t)sizeof(soerr);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &slen) != 0) return -1;
  if (soerr != 0) {
    errno = soerr;
    return -1;
  }

  (void)net_set_nonblocking(fd, false);
  return 0;
}

int net_connect_tcp(const char *host, uint16_t port, int timeout_ms) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return -1;

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  if (inet_pton(AF_INET, host, &addr.sin_addr) != 1) {
    close(fd);
    errno = EINVAL;
    return -1;
  }

  if (connect_with_timeout(fd, (struct sockaddr *)&addr, (socklen_t)sizeof(addr), timeout_ms) != 0) {
    close(fd);
    return -1;
  }

  return fd;
}



