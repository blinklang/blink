#ifndef PACT_RUNTIME_HTTP_H
#define PACT_RUNTIME_HTTP_H

#include <sys/socket.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <strings.h>

PACT_UNUSED static int pact_http_parse_url(const char* url,
                               char* host, int host_sz,
                               char* port, int port_sz,
                               char* path, int path_sz) {
    const char* p = url;
    if (strncmp(p, "http://", 7) == 0) {
        p += 7;
    } else if (strncmp(p, "https://", 8) == 0) {
        return -2; /* TLS not supported */
    }
    /* host[:port]/path */
    const char* slash = strchr(p, '/');
    const char* colon = strchr(p, ':');
    if (colon && (!slash || colon < slash)) {
        int hlen = (int)(colon - p);
        if (hlen >= host_sz) hlen = host_sz - 1;
        memcpy(host, p, (size_t)hlen);
        host[hlen] = '\0';
        const char* port_start = colon + 1;
        int plen = slash ? (int)(slash - port_start) : (int)strlen(port_start);
        if (plen >= port_sz) plen = port_sz - 1;
        memcpy(port, port_start, (size_t)plen);
        port[plen] = '\0';
    } else {
        int hlen = slash ? (int)(slash - p) : (int)strlen(p);
        if (hlen >= host_sz) hlen = host_sz - 1;
        memcpy(host, p, (size_t)hlen);
        host[hlen] = '\0';
        strncpy(port, "80", (size_t)port_sz);
        port[port_sz - 1] = '\0';
    }
    if (slash) {
        strncpy(path, slash, (size_t)path_sz);
        path[path_sz - 1] = '\0';
    } else {
        strncpy(path, "/", (size_t)path_sz);
        path[path_sz - 1] = '\0';
    }
    return 0;
}

PACT_UNUSED static int pact_http_request(
    const char* method,
    const char* url,
    const char* body,
    pact_map* headers,
    int64_t timeout_ms,
    int64_t* out_status,
    const char** out_body,
    pact_map** out_headers)
{
    char host[256], port[16], path[2048];
    *out_status = 0;
    *out_body = "";
    *out_headers = NULL;

    int parse_rc = pact_http_parse_url(url, host, 256, port, 16, path, 2048);
    if (parse_rc == -2) {
        *out_body = "HTTPS not supported";
        return -1;
    }
    if (parse_rc != 0) {
        *out_body = "invalid URL";
        return -1;
    }

    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    int gai = getaddrinfo(host, port, &hints, &res);
    if (gai != 0) {
        *out_body = strdup(gai_strerror(gai));
        return -1;
    }

    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(res);
        *out_body = "socket creation failed";
        return -1;
    }

    /* Apply timeout */
    if (timeout_ms > 0) {
        struct timeval tv;
        tv.tv_sec = (time_t)(timeout_ms / 1000);
        tv.tv_usec = (long)((timeout_ms % 1000) * 1000);
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    }

    if (connect(fd, res->ai_addr, res->ai_addrlen) < 0) {
        freeaddrinfo(res);
        close(fd);
        if (errno == ECONNREFUSED) {
            *out_body = "connection refused";
        } else if (errno == ETIMEDOUT) {
            *out_body = "connection timed out";
        } else {
            *out_body = "connection failed";
        }
        return -1;
    }
    freeaddrinfo(res);

    /* Build request */
    int64_t body_len = body ? (int64_t)strlen(body) : 0;
    /* Estimate buffer: method + path + headers + body + slack */
    int64_t est = 512 + body_len;
    if (headers) {
        for (int64_t hi = 0; hi < headers->cap; hi++) {
            if (headers->states[hi] == 1) {
                est += (int64_t)strlen(headers->keys[hi]) + (int64_t)strlen((const char*)headers->values[hi]) + 8;
            }
        }
    }
    char* req_buf = (char*)pact_alloc(est + 1);
    int pos = snprintf(req_buf, (size_t)est, "%s %s HTTP/1.1\r\nHost: %s\r\n", method, path, host);

    int has_content_length = 0;
    int has_connection = 0;
    if (headers) {
        for (int64_t hi = 0; hi < headers->cap; hi++) {
            if (headers->states[hi] == 1) {
                const char* hk = headers->keys[hi];
                const char* hv = (const char*)headers->values[hi];
                pos += snprintf(req_buf + pos, (size_t)(est - pos), "%s: %s\r\n", hk, hv);
                if (strcasecmp(hk, "Content-Length") == 0) has_content_length = 1;
                if (strcasecmp(hk, "Connection") == 0) has_connection = 1;
            }
        }
    }
    if (body_len > 0 && !has_content_length) {
        pos += snprintf(req_buf + pos, (size_t)(est - pos), "Content-Length: %lld\r\n", (long long)body_len);
    }
    if (!has_connection) {
        pos += snprintf(req_buf + pos, (size_t)(est - pos), "Connection: close\r\n");
    }
    pos += snprintf(req_buf + pos, (size_t)(est - pos), "\r\n");
    if (body_len > 0) {
        memcpy(req_buf + pos, body, (size_t)body_len);
        pos += (int)body_len;
    }

    /* Send */
    int64_t sent = 0;
    while (sent < pos) {
        ssize_t n = write(fd, req_buf + sent, (size_t)(pos - sent));
        if (n <= 0) {
            close(fd);
            free(req_buf);
            *out_body = "write failed";
            return -1;
        }
        sent += n;
    }
    free(req_buf);

    /* Read response into dynamic buffer */
    int64_t resp_cap = 4096;
    int64_t resp_len = 0;
    char* resp_buf = (char*)pact_alloc(resp_cap);
    while (1) {
        if (resp_len + 1024 > resp_cap) {
            resp_cap *= 2;
            resp_buf = (char*)realloc(resp_buf, (size_t)resp_cap);
            if (!resp_buf) { close(fd); *out_body = "out of memory"; return -1; }
        }
        ssize_t n = read(fd, resp_buf + resp_len, (size_t)(resp_cap - resp_len - 1));
        if (n <= 0) break;
        resp_len += n;
    }
    close(fd);
    resp_buf[resp_len] = '\0';

    /* Parse status line: HTTP/1.x STATUS REASON\r\n */
    char* hdr_end = strstr(resp_buf, "\r\n\r\n");
    if (!hdr_end) {
        *out_body = "malformed HTTP response";
        free(resp_buf);
        return -1;
    }

    int status_code = 0;
    if (resp_len > 12 && (resp_buf[0] == 'H') && (resp_buf[5] == '/')) {
        status_code = atoi(resp_buf + 9);
    }
    *out_status = (int64_t)status_code;

    /* Parse response headers */
    pact_map* rh = pact_map_new();
    char* line_start = strstr(resp_buf, "\r\n");
    if (line_start) {
        line_start += 2; /* skip status line */
        while (line_start < hdr_end) {
            char* line_end = strstr(line_start, "\r\n");
            if (!line_end || line_end > hdr_end) break;
            char* colon_pos = strchr(line_start, ':');
            if (colon_pos && colon_pos < line_end) {
                int klen = (int)(colon_pos - line_start);
                char* hkey = (char*)pact_alloc(klen + 1);
                memcpy(hkey, line_start, (size_t)klen);
                hkey[klen] = '\0';
                const char* vstart = colon_pos + 1;
                while (vstart < line_end && *vstart == ' ') vstart++;
                int vlen = (int)(line_end - vstart);
                char* hval = (char*)pact_alloc(vlen + 1);
                memcpy(hval, vstart, (size_t)vlen);
                hval[vlen] = '\0';
                pact_map_set(rh, hkey, (void*)hval);
            }
            line_start = line_end + 2;
        }
    }
    *out_headers = rh;

    /* Extract body after \r\n\r\n */
    const char* body_start = hdr_end + 4;
    int64_t body_length = resp_len - (int64_t)(body_start - resp_buf);

    /* Check for chunked transfer encoding */
    const char* te = (const char*)pact_map_get(rh, "Transfer-Encoding");
    if (!te) te = (const char*)pact_map_get(rh, "transfer-encoding");
    if (te && strstr(te, "chunked")) {
        /* Decode chunked body */
        int64_t decoded_cap = body_length + 1;
        char* decoded = (char*)pact_alloc(decoded_cap);
        int64_t decoded_len = 0;
        const char* cp = body_start;
        const char* end = resp_buf + resp_len;
        while (cp < end) {
            /* Read chunk size (hex) */
            long chunk_size = strtol(cp, NULL, 16);
            if (chunk_size <= 0) break;
            /* Skip to data after \r\n */
            const char* data_start = strstr(cp, "\r\n");
            if (!data_start) break;
            data_start += 2;
            if (data_start + chunk_size > end) chunk_size = (long)(end - data_start);
            if (decoded_len + chunk_size + 1 > decoded_cap) {
                decoded_cap = (decoded_len + chunk_size + 1) * 2;
                decoded = (char*)realloc(decoded, (size_t)decoded_cap);
            }
            memcpy(decoded + decoded_len, data_start, (size_t)chunk_size);
            decoded_len += chunk_size;
            cp = data_start + chunk_size;
            if (cp + 2 <= end && cp[0] == '\r' && cp[1] == '\n') cp += 2;
        }
        decoded[decoded_len] = '\0';
        *out_body = decoded;
    } else {
        char* body_copy = (char*)pact_alloc(body_length + 1);
        if (body_length > 0) memcpy(body_copy, body_start, (size_t)body_length);
        body_copy[body_length] = '\0';
        *out_body = body_copy;
    }

    free(resp_buf);
    return 0;
}

#endif
