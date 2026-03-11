#ifndef PACT_RUNTIME_TCP_H
#define PACT_RUNTIME_TCP_H

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

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

#endif
