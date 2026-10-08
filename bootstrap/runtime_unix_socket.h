#ifndef BLINK_RUNTIME_UNIX_SOCKET_H
#define BLINK_RUNTIME_UNIX_SOCKET_H

#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>

/* sun_path holds about 107 bytes. A longer path must fail here: copied short, it would
   bind or connect at some other path while the caller names this one. */
BLINK_RT_FN int blink_unix_socket_addr(struct sockaddr_un* addr, const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_unix_socket_addr(struct sockaddr_un* addr, const char* path) {
    memset(addr, 0, sizeof(*addr));
    addr->sun_family = AF_UNIX;
    size_t len = strlen(path);
    if (len >= sizeof(addr->sun_path)) return -1;
    memcpy(addr->sun_path, path, len);
    return 0;
}
#endif

/* Where send() has no MSG_NOSIGNAL (macOS), the socket itself must be told not to raise
   SIGPIPE. Set on each fd, since accept() need not pass the option on. */
BLINK_RT_FN void blink_unix_socket_nosigpipe(int fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_unix_socket_nosigpipe(int fd) {
#if !defined(MSG_NOSIGNAL) && defined(SO_NOSIGPIPE)
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
#else
    (void)fd;
#endif
}
#endif

BLINK_RT_FN int64_t blink_unix_socket_listen(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_socket_listen(const char* path) {
    struct sockaddr_un addr;
    if (blink_unix_socket_addr(&addr, path) < 0) {
        fprintf(stderr, "blink: socket path is %zu bytes, longer than the %zu a Unix socket allows: %s\n",
            strlen(path), sizeof(addr.sun_path) - 1, path);
        return -1;
    }
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        fprintf(stderr, "blink: socket() failed\n");
        return -1;
    }
    unlink(path);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "blink: bind(%s) failed\n", path);
        close(fd);
        return -1;
    }
    if (listen(fd, 5) < 0) {
        fprintf(stderr, "blink: listen(%s) failed\n", path);
        close(fd);
        return -1;
    }
    return (int64_t)fd;
}
#endif

BLINK_RT_FN int64_t blink_unix_socket_connect(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_socket_connect(const char* path) {
    struct sockaddr_un addr;
    if (blink_unix_socket_addr(&addr, path) < 0) return -1;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    /* Silent: a client probes for a server that may be gone, and falls back on -1. */
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    blink_unix_socket_nosigpipe(fd);
    return (int64_t)fd;
}
#endif

BLINK_RT_FN int64_t blink_unix_socket_accept(int64_t listen_fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_socket_accept(int64_t listen_fd) {
    int client = accept((int)listen_fd, NULL, NULL);
    if (client < 0) {
        fprintf(stderr, "blink: accept() failed\n");
        return -1;
    }
    blink_unix_socket_nosigpipe(client);
    return (int64_t)client;
}
#endif

BLINK_RT_FN int64_t blink_unix_socket_accept_timeout(int64_t listen_fd, int64_t timeout_ms);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_socket_accept_timeout(int64_t listen_fd, int64_t timeout_ms) {
    struct pollfd pfd;
    pfd.fd = (int)listen_fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int rc = poll(&pfd, 1, (int)timeout_ms);
    if (rc <= 0) return -1;
    int client = accept((int)listen_fd, NULL, NULL);
    if (client < 0) return -1;
    blink_unix_socket_nosigpipe(client);
    return (int64_t)client;
}
#endif

BLINK_RT_FN void blink_unix_socket_close(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_unix_socket_close(int64_t fd) {
    close((int)fd);
}
#endif

/* One line, without its newline, however long. Bytes are peeked first and only those up
   to the newline consumed, so what follows the line stays for the next read. At end of
   input or on an error the line ends where the bytes did; with none read it is empty. */
BLINK_RT_FN const char* blink_socket_read_line(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_socket_read_line(int64_t fd) {
    size_t cap = 8192;
    size_t len = 0;
    char* buf = (char*)malloc(cap);
    if (!buf) return blink_str_from_cstr_gc("");
    /* A pipe or file cannot be peeked, so it is read a byte at a time. */
    int peek = 1;
    for (;;) {
        if (cap - len < 4096) {
            char* grown = (char*)realloc(buf, cap * 2);
            if (!grown) break;
            buf = grown;
            cap *= 2;
        }
        size_t room = cap - len - 1;
        ssize_t n;
        if (peek) {
            n = recv((int)fd, buf + len, room, MSG_PEEK);
            if (n < 0 && errno == ENOTSOCK) { peek = 0; continue; }
        } else {
            n = read((int)fd, buf + len, 1);
        }
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        char* nl = (char*)memchr(buf + len, '\n', (size_t)n);
        size_t take = nl ? (size_t)(nl - (buf + len)) + 1 : (size_t)n;
        if (peek) {
            size_t got = 0;
            while (got < take) {
                ssize_t r = recv((int)fd, buf + len + got, take - got, 0);
                if (r < 0 && errno == EINTR) continue;
                if (r <= 0) break;
                got += (size_t)r;
            }
            if (got < take) nl = NULL;
            take = got;
        }
        len += take;
        if (nl) { len--; break; }
        if (take == 0) break;
    }
    buf[len] = '\0';
    const char* s = blink_str_from_cstr_gc(buf);
    free(buf);
    return s;
}
#endif

/* Writes all of `data`, looping over partial writes. A peer that has closed gives -1, not
   SIGPIPE: a daemon must outlive a client that went away. Returns the bytes written. */
BLINK_RT_FN int64_t blink_socket_write(int64_t fd, const char* data);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_socket_write(int64_t fd, const char* data) {
#ifdef MSG_NOSIGNAL
    int flags = MSG_NOSIGNAL;
#else
    int flags = 0;
#endif
    size_t len = strlen(data);
    size_t written = 0;
    while (written < len) {
        ssize_t n = send((int)fd, data + written, len - written, flags);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        written += (size_t)n;
    }
    return (int64_t)written;
}
#endif

#endif
