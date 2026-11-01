#ifndef BLINK_RUNTIME_UNIX_SOCKET_H
#define BLINK_RUNTIME_UNIX_SOCKET_H

#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <fcntl.h>
#include <limits.h>

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

/* The uid of the process at the other end of the Unix socket fd, from the kernel. -1 when
   the call fails (fd is no live socket), which a caller must take as a refusal. -2 where this
   platform has no such call; that is decided before fd is looked at, so a call on -1 tells
   whether the check is supported here. The platform macros of the target choose the call, so
   no arch table or file read is needed.
   Linux: glibc gives SO_PEERCRED and struct ucred only past _POSIX_C_SOURCE, which
   runtime_core.h may set alone, so SO_PEERCRED comes from the kernel header, which has the
   value for each arch, and a struct of the same fixed layout (pid, uid, gid) stands in for
   struct ucred. macOS and the BSDs hide getpeereid under _POSIX_C_SOURCE, so it is declared
   here as their headers do. */
#if defined(__linux__) && !defined(SO_PEERCRED)
#include <asm/socket.h>
#endif
#if !defined(__linux__) && (defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) \
    || defined(__NetBSD__) || defined(__DragonFly__))
#define BLINK_PEER_UID_GETPEEREID 1
int getpeereid(int, uid_t*, gid_t*);
#endif

BLINK_RT_FN int64_t blink_unix_socket_peer_uid(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_socket_peer_uid(int64_t fd) {
#if defined(__linux__)
    struct { pid_t pid; uid_t uid; gid_t gid; } cred;
    socklen_t len = sizeof(cred);
    if (getsockopt((int)fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) != 0) return -1;
    if (len != sizeof(cred)) return -1;
    return (int64_t)cred.uid;
#elif defined(BLINK_PEER_UID_GETPEEREID)
    uid_t uid;
    gid_t gid;
    if (getpeereid((int)fd, &uid, &gid) != 0) return -1;
    return (int64_t)uid;
#else
    (void)fd;
    return -2;
#endif
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

/* The std.net Unix socket API (sections/04_effects.md §4.4.6). Each call returns -errno on
   failure, so lib/std/net_unix.bl can build NetError.Os(op, code) with the call that
   failed. None prints, and none removes a file: a path that exists fails bind with
   EADDRINUSE. */
#if defined(__linux__)
/* glibc declares accept4 only past _GNU_SOURCE, which runtime_core.h does not set. */
int accept4(int sockfd, struct sockaddr* addr, socklen_t* addrlen, int flags);
#endif

/* Each fd of this API is close-on-exec, so a child that process.spawn starts does not keep
   a copy: the peer then sees end of stream when this process closes the socket. Linux sets
   the flag in the call that makes the fd; elsewhere fcntl sets it after the call. */
BLINK_RT_FN int64_t blink_unix_stream_socket(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_stream_socket(void) {
#if defined(__linux__)
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -(int64_t)errno;
#else
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -(int64_t)errno;
    fcntl(fd, F_SETFD, FD_CLOEXEC);
#endif
    blink_unix_socket_nosigpipe(fd);
    return (int64_t)fd;
}
#endif

/* The sockaddr for a std.net path, or -errno. An empty path names no file: Linux would read
   the zeroed sun_path as an abstract name that any process could share, so it fails with
   ENOENT, as it does on macOS. */
BLINK_RT_FN int64_t blink_unix_path_addr(struct sockaddr_un* addr, const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_path_addr(struct sockaddr_un* addr, const char* path) {
    if (path[0] == '\0') return -(int64_t)ENOENT;
    if (blink_unix_socket_addr(addr, path) < 0) return -(int64_t)ENAMETOOLONG;
    return 0;
}
#endif

BLINK_RT_FN int64_t blink_unix_bind(int64_t fd, const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_bind(int64_t fd, const char* path) {
    struct sockaddr_un addr;
    int64_t rc = blink_unix_path_addr(&addr, path);
    if (rc < 0) return rc;
    if (bind((int)fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) return -(int64_t)errno;
    return 0;
}
#endif

BLINK_RT_FN int64_t blink_unix_listen_fd(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
/* A listener is non-blocking for its whole life, so no accept blocks past the poll that saw
   a client: another thread or process may take that client first, and a blocking accept
   would then wait for the next client, past the wait of accept_timeout. */
BLINK_RT_FN int64_t blink_unix_listen_fd(int64_t fd) {
    if (listen((int)fd, SOMAXCONN) < 0) return -(int64_t)errno;
    int flags = fcntl((int)fd, F_GETFL);
    if (flags < 0 || fcntl((int)fd, F_SETFL, flags | O_NONBLOCK) < 0) return -(int64_t)errno;
    return 0;
}
#endif

/* EINTR is not retried here, and the caller gets Os("connect", EINTR). On Linux an
   interrupted AF_UNIX connect leaves the socket unconnected, but POSIX lets the connect go
   on in the kernel, and there a second connect fails with EALREADY. The runtime's own
   signal handlers set SA_RESTART, so only a handler without it can cause EINTR here. */
BLINK_RT_FN int64_t blink_unix_connect_fd(int64_t fd, const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_connect_fd(int64_t fd, const char* path) {
    struct sockaddr_un addr;
    int64_t rc = blink_unix_path_addr(&addr, path);
    if (rc < 0) return rc;
    if (connect((int)fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) return -(int64_t)errno;
    return 0;
}
#endif

/* One accept on a non-blocking listener: the client fd, or -errno. -EAGAIN means no client
   waits now. The client fd blocks, whatever the listener is: macOS and the BSDs pass
   O_NONBLOCK on from the listener, and Linux does not. */
BLINK_RT_FN int64_t blink_unix_accept_once(int fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_accept_once(int fd) {
    for (;;) {
#if defined(__linux__)
        int client = accept4(fd, NULL, NULL, SOCK_CLOEXEC);
#else
        int client = accept(fd, NULL, NULL);
        if (client >= 0) {
            fcntl(client, F_SETFD, FD_CLOEXEC);
            int flags = fcntl(client, F_GETFL);
            if (flags >= 0) fcntl(client, F_SETFL, flags & ~O_NONBLOCK);
        }
#endif
        if (client >= 0) {
            blink_unix_socket_nosigpipe(client);
            return (int64_t)client;
        }
        if (errno == EINTR) continue;
        /* A client that hung up before the accept is no fault of the listener. */
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == ECONNABORTED) return -(int64_t)EAGAIN;
        return -(int64_t)errno;
    }
}
#endif

BLINK_RT_FN int64_t blink_unix_monotonic_ns(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_monotonic_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000 + (int64_t)ts.tv_nsec;
}
#endif

/* Accept a client within wait_ns, or wait with no limit when wait_ns is -1. Returns the client
   fd, -EAGAIN when no client came in time, or -errno. A wait of 0 tries once and does not
   poll. The wait is rounded up to whole ms, so a wait under 1 ms waits 1 ms and the call never
   waits less than it was asked to. The deadline is on the monotonic clock, so a signal
   (EINTR) makes the poll wait again for the time left, not for all of it. */
BLINK_RT_FN int64_t blink_unix_accept_wait(int64_t fd, int64_t wait_ns);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_accept_wait(int64_t fd, int64_t wait_ns) {
    if (wait_ns < -1) return -(int64_t)EINVAL;
    int64_t start = blink_unix_monotonic_ns();
    int64_t deadline = INT64_MAX;
    if (wait_ns >= 0) {
        int64_t ms = wait_ns / 1000000 + (wait_ns % 1000000 != 0);
        if (ms <= (INT64_MAX - start) / 1000000) deadline = start + ms * 1000000;
    }
    for (;;) {
        int64_t client = blink_unix_accept_once((int)fd);
        if (client != -(int64_t)EAGAIN) return client;
        int timeout_ms = -1;
        if (wait_ns >= 0) {
            int64_t left = deadline - blink_unix_monotonic_ns();
            if (left <= 0) return -(int64_t)EAGAIN;
            int64_t ms = left / 1000000 + (left % 1000000 != 0);
            timeout_ms = ms > INT_MAX ? INT_MAX : (int)ms;
        }
        struct pollfd pfd;
        pfd.fd = (int)fd;
        pfd.events = POLLIN;
        pfd.revents = 0;
        int rc = poll(&pfd, 1, timeout_ms);
        if (rc < 0) {
            if (errno == EINTR) continue;
            return -(int64_t)errno;
        }
        if (pfd.revents & POLLNVAL) return -(int64_t)EBADF;
        if (pfd.revents & POLLERR) {
            int err = 0;
            socklen_t len = sizeof(err);
            if (getsockopt((int)fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0) return -(int64_t)errno;
            return -(int64_t)(err != 0 ? err : EIO);
        }
    }
}
#endif

BLINK_RT_FN int64_t blink_unix_accept_fd(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_accept_fd(int64_t fd) {
    return blink_unix_accept_wait(fd, -1);
}
#endif

/* The uid of the peer of fd, or -errno. On a host with no call for it, -ENOTSUP before fd is
   looked at, so a closed socket gives ENOTSUP there too, as blink_unix_peer_uid_supported
   says. The calls are chosen as for blink_unix_socket_peer_uid above. */
BLINK_RT_FN int64_t blink_unix_peer_uid_supported(void);
BLINK_RT_FN int64_t blink_unix_peer_uid(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_peer_uid_supported(void) {
#if defined(__linux__) || defined(BLINK_PEER_UID_GETPEEREID)
    return 1;
#else
    return 0;
#endif
}
BLINK_RT_FN int64_t blink_unix_peer_uid(int64_t fd) {
#if defined(__linux__)
    struct { pid_t pid; uid_t uid; gid_t gid; } cred;
    socklen_t len = sizeof(cred);
    if (getsockopt((int)fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) != 0) return -(int64_t)errno;
    if (len != sizeof(cred)) return -(int64_t)EINVAL;
    return (int64_t)cred.uid;
#elif defined(BLINK_PEER_UID_GETPEEREID)
    uid_t uid;
    gid_t gid;
    if (getpeereid((int)fd, &uid, &gid) != 0) return -(int64_t)errno;
    return (int64_t)uid;
#else
    (void)fd;
    return -(int64_t)ENOTSUP;
#endif
}
#endif

/* close(2) may report EINTR or EIO, but the fd is gone either way, and the spec gives
   close no Result. */
BLINK_RT_FN void blink_unix_close_fd(int64_t fd);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_unix_close_fd(int64_t fd) {
    close((int)fd);
}
#endif

/* One line without its "\n" or "\r\n". The status of the last call on this thread is
   0 for a line, -1 for end of stream with no bytes left, or the errno. Bytes are peeked
   and only those up to the newline consumed, so what follows the line stays for the next
   call. A last line with no newline is a line; the call after it gives end of stream.
   Out of memory stops the process, as it does for io.read_line: an Err would have to drop
   the bytes already taken from the socket. */
BLINK_RT_FN const char* blink_unix_read_line(int64_t fd);
BLINK_RT_FN int64_t blink_unix_read_line_status(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_UNUSED static __thread int64_t blink_unix_read_line_last;
BLINK_RT_FN const char* blink_unix_read_line(int64_t fd) {
    size_t cap = 8192;
    size_t len = 0;
    char* buf = (char*)malloc(cap);
    if (!buf) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    int64_t status = 0;
    int ended = 0;
    for (;;) {
        if (cap - len < 4096) {
            char* grown = (char*)realloc(buf, cap * 2);
            if (!grown) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
            buf = grown;
            cap *= 2;
        }
        ssize_t n = recv((int)fd, buf + len, cap - len - 1, MSG_PEEK);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { status = errno; break; }
        if (n == 0) break;
        char* nl = (char*)memchr(buf + len, '\n', (size_t)n);
        size_t take = nl ? (size_t)(nl - (buf + len)) + 1 : (size_t)n;
        size_t got = 0;
        while (got < take) {
            ssize_t r = recv((int)fd, buf + len + got, take - got, 0);
            if (r < 0 && errno == EINTR) continue;
            if (r < 0) { status = errno; break; }
            if (r == 0) break;
            got += (size_t)r;
        }
        len += got;
        if (status != 0) break;
        if (got < take) break;
        if (nl) { ended = 1; break; }
    }
    if (status == 0 && !ended && len == 0) status = -1;
    if (ended) {
        len--;
        if (len > 0 && buf[len - 1] == '\r') len--;
    }
    blink_unix_read_line_last = status;
    const char* s = blink_str_from_bytes_gc(buf, (int64_t)len);
    free(buf);
    return s;
}
BLINK_RT_FN int64_t blink_unix_read_line_status(void) {
    return blink_unix_read_line_last;
}
#endif

/* Sends all of `data`, looping over partial sends. A peer that has closed gives -EPIPE,
   not SIGPIPE. Returns 0 or -errno. */
BLINK_RT_FN int64_t blink_unix_write(int64_t fd, const char* data);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_unix_write(int64_t fd, const char* data) {
#ifdef MSG_NOSIGNAL
    int flags = MSG_NOSIGNAL;
#else
    int flags = 0;
#endif
    size_t len = (size_t)blink_str_len(data);
    size_t written = 0;
    while (written < len) {
        ssize_t n = send((int)fd, data + written, len - written, flags);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) return -(int64_t)errno;
        written += (size_t)n;
    }
    return 0;
}
#endif

#endif
