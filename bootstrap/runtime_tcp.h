#ifndef PACT_RUNTIME_TCP_H
#define PACT_RUNTIME_TCP_H

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

PACT_UNUSED static int64_t pact_tcp_listen(const char* host, int64_t port) {
    (void)host;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = INADDR_ANY;
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    if (listen(fd, 128) < 0) {
        close(fd);
        return -1;
    }
    return (int64_t)fd;
}

PACT_UNUSED static int64_t pact_tcp_accept(int64_t listen_fd) {
    int client = accept((int)listen_fd, NULL, NULL);
    return (int64_t)client;
}

PACT_UNUSED static const char* pact_tcp_read(int64_t fd, int64_t max_bytes) {
    char* buf = (char*)pact_alloc(max_bytes + 1);
    int64_t total = 0;
    while (total < max_bytes) {
        ssize_t n = read((int)fd, buf + total, (size_t)(max_bytes - total));
        if (n <= 0) break;
        total += n;
        if (total >= 4 && memcmp(buf + total - 4, "\r\n\r\n", 4) == 0) break;
    }
    buf[total] = '\0';
    return buf;
}

PACT_UNUSED static void pact_tcp_write(int64_t fd, const char* data) {
    size_t len = strlen(data);
    size_t written = 0;
    while (written < len) {
        ssize_t n = write((int)fd, data + written, len - written);
        if (n <= 0) break;
        written += (size_t)n;
    }
}

PACT_UNUSED static void pact_tcp_close(int64_t fd) {
    close((int)fd);
}

PACT_UNUSED static int64_t pact_tcp_connect(const char* host, int64_t port) {
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%lld", (long long)port);
    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    int gai = getaddrinfo(host, port_str, &hints, &res);
    if (gai != 0) return -2;
    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(res);
        return -1;
    }
    if (connect(fd, res->ai_addr, res->ai_addrlen) < 0) {
        int err = errno;
        freeaddrinfo(res);
        close(fd);
        if (err == ETIMEDOUT) return -3;
        return -1;
    }
    freeaddrinfo(res);
    return (int64_t)fd;
}

PACT_UNUSED static void pact_tcp_set_timeout(int64_t fd, int64_t ms) {
    if (ms <= 0) return;
    struct timeval tv;
    tv.tv_sec = (time_t)(ms / 1000);
    tv.tv_usec = (long)((ms % 1000) * 1000);
    setsockopt((int)fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt((int)fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}

PACT_UNUSED static const char* pact_tcp_read_all(int64_t fd) {
    int64_t cap = 4096;
    int64_t len = 0;
    char* buf = (char*)pact_alloc(cap);
    while (1) {
        if (len + 1024 > cap) {
            cap *= 2;
            buf = (char*)realloc(buf, (size_t)cap);
            if (!buf) return "";
        }
        ssize_t n = read((int)fd, buf + len, (size_t)(cap - len - 1));
        if (n <= 0) break;
        len += n;
    }
    buf[len] = '\0';
    return buf;
}

#endif
