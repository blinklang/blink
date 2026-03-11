#ifndef PACT_RUNTIME_UNIX_SOCKET_H
#define PACT_RUNTIME_UNIX_SOCKET_H

#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>

PACT_UNUSED static int64_t pact_unix_socket_listen(const char* path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        fprintf(stderr, "pact: socket() failed\n");
        return -1;
    }
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    unlink(path);
    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "pact: bind(%s) failed\n", path);
        close(fd);
        return -1;
    }
    if (listen(fd, 5) < 0) {
        fprintf(stderr, "pact: listen(%s) failed\n", path);
        close(fd);
        return -1;
    }
    return (int64_t)fd;
}

PACT_UNUSED static int64_t pact_unix_socket_connect(const char* path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        fprintf(stderr, "pact: socket() failed\n");
        return -1;
    }
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "pact: connect(%s) failed\n", path);
        close(fd);
        return -1;
    }
    return (int64_t)fd;
}

PACT_UNUSED static int64_t pact_unix_socket_accept(int64_t listen_fd) {
    int client = accept((int)listen_fd, NULL, NULL);
    if (client < 0) {
        fprintf(stderr, "pact: accept() failed\n");
        return -1;
    }
    return (int64_t)client;
}

PACT_UNUSED static int64_t pact_unix_socket_accept_timeout(int64_t listen_fd, int64_t timeout_ms) {
    struct pollfd pfd;
    pfd.fd = (int)listen_fd;
    pfd.events = POLLIN;
    pfd.revents = 0;
    int rc = poll(&pfd, 1, (int)timeout_ms);
    if (rc <= 0) return -1;
    int client = accept((int)listen_fd, NULL, NULL);
    if (client < 0) return -1;
    return (int64_t)client;
}

PACT_UNUSED static void pact_unix_socket_close(int64_t fd) {
    close((int)fd);
}

PACT_UNUSED static const char* pact_socket_read_line(int64_t fd) {
    char buf[4096];
    int64_t pos = 0;
    while (pos < (int64_t)(sizeof(buf) - 1)) {
        char ch;
        ssize_t n = read((int)fd, &ch, 1);
        if (n <= 0) break;
        if (ch == '\n') break;
        buf[pos++] = ch;
    }
    buf[pos] = '\0';
    return strdup(buf);
}

PACT_UNUSED static void pact_socket_write(int64_t fd, const char* data) {
    size_t len = strlen(data);
    size_t written = 0;
    while (written < len) {
        ssize_t n = write((int)fd, data + written, len - written);
        if (n <= 0) break;
        written += (size_t)n;
    }
}

#endif
