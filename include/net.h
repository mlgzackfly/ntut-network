#pragma once

#include <stdbool.h>
#include <stdint.h>

int net_set_nonblocking(int fd, bool nonblocking);
int net_set_reuseaddr(int fd);
int net_set_reuseport(int fd);
int net_set_tcp_nodelay(int fd);
int net_set_timeouts_ms(int fd, int recv_timeout_ms, int send_timeout_ms);

int net_listen_tcp(const char *bind_ip, uint16_t port, int backlog, bool reuseport);
int net_connect_tcp(const char *host, uint16_t port, int timeout_ms);



