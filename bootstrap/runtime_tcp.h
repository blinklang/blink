#ifndef BLINK_RUNTIME_TCP_H
#define BLINK_RUNTIME_TCP_H

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>

BLINK_RT_FN int64_t blink_tcp_listen(const char* host, int64_t port);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_tcp_listen(const char* host, int64_t port) {
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
#endif

BLINK_RT_FN int64_t blink_tcp_accept(int64_t listen_fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_tcp_accept(int64_t listen_fd) {
    int client = accept((int)listen_fd, NULL, NULL);
    return (int64_t)client;
}
#endif

BLINK_RT_FN const char* blink_tcp_read(int64_t fd, int64_t max_bytes);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_tcp_read(int64_t fd, int64_t max_bytes) {
    char* buf = (char*)blink_alloc(max_bytes + 1);
    ssize_t n = read((int)fd, buf, (size_t)max_bytes);
    if (n < 0) n = 0;
    buf[n] = '\0';
    return buf;
}
#endif

BLINK_RT_FN void blink_tcp_write(int64_t fd, const char* data);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_tcp_write(int64_t fd, const char* data) {
    size_t len = strlen(data);
    size_t written = 0;
    while (written < len) {
        ssize_t n = write((int)fd, data + written, len - written);
        if (n <= 0) break;
        written += (size_t)n;
    }
}
#endif

/* Binary-safe read: returns a blink_bytes with up to max_bytes read from fd.
   No null-termination, no strlen — b->len is the authoritative size. Uses a
   single read() call matching tcp_read semantics. On error, sets b->len to -1
   so the Blink wrapper can distinguish error from EOF (len == 0). */
BLINK_RT_FN blink_bytes* blink_tcp_read_bytes(int64_t fd, int64_t max_bytes);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_bytes* blink_tcp_read_bytes(int64_t fd, int64_t max_bytes) {
    blink_bytes* b = blink_bytes_new();
    if (max_bytes <= 0) return b;
    blinkrt_bytes_reserve(b, max_bytes);
    ssize_t n = read((int)fd, b->data, (size_t)max_bytes);
    if (n < 0) {
        b->len = -1;
    } else {
        b->len = (int64_t)n;
    }
    return b;
}
#endif

/* Binary-safe write: writes exactly b->len bytes from the buffer, looping on
   partial writes. Returns 0 on full success, -1 on any write error. */
BLINK_RT_FN int64_t blink_tcp_write_bytes(int64_t fd, blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_tcp_write_bytes(int64_t fd, blink_bytes* b) {
    int64_t total = 0;
    while (total < b->len) {
        ssize_t n = write((int)fd, b->data + total, (size_t)(b->len - total));
        if (n <= 0) return -1;
        total += (int64_t)n;
    }
    return 0;
}
#endif

/* Test-only helper: AF_UNIX socketpair encoded as (a << 32) | b. Test code
   unpacks both halves. Avoids pulling in fork/thread machinery just for a
   binary round-trip smoke test. */
BLINK_RT_FN int64_t blinkrt_socketpair_packed(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_socketpair_packed(void) {
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) < 0) return -1;
    return ((int64_t)(uint32_t)fds[0] << 32) | (int64_t)(uint32_t)fds[1];
}
#endif

BLINK_RT_FN void blink_tcp_close(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_tcp_close(int64_t fd) {
    close((int)fd);
}
#endif

BLINK_RT_FN int64_t blink_tcp_connect(const char* host, int64_t port);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_tcp_connect(const char* host, int64_t port) {
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
#endif

BLINK_RT_FN void blink_tcp_set_timeout(int64_t fd, int64_t ms);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_tcp_set_timeout(int64_t fd, int64_t ms) {
    if (ms <= 0) return;
    struct timeval tv;
    tv.tv_sec = (time_t)(ms / 1000);
    tv.tv_usec = (long)((ms % 1000) * 1000);
    setsockopt((int)fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt((int)fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}
#endif

BLINK_RT_FN const char* blink_tcp_read_all(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_tcp_read_all(int64_t fd) {
    int64_t cap = 4096;
    int64_t len = 0;
    char* buf = (char*)blink_alloc(cap);
    while (1) {
        if (len + 1024 > cap) {
            cap *= 2;
            buf = (char*)GC_REALLOC(buf, (size_t)cap);
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

#endif
