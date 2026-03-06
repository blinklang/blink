#ifndef PACT_RUNTIME_H
#define PACT_RUNTIME_H

#if !defined(_POSIX_C_SOURCE) && !defined(_GNU_SOURCE) && !defined(__APPLE__)
#define _POSIX_C_SOURCE 200809L
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <setjmp.h>
#include <unistd.h>
#include <pthread.h>
#ifndef _WIN32
#include <sys/wait.h>
#endif
#include <dirent.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/time.h>
#include <strings.h>

static const char* pact_int_to_str(int64_t n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)n);
    return strdup(buf);
}

static const char* pact_float_to_str(double d) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%g", d);
    return strdup(buf);
}

static void* pact_alloc(int64_t size) {
    void* p = malloc((size_t)size);
    if (!p) {
        fprintf(stderr, "pact: out of memory\n");
        exit(1);
    }
    return p;
}

typedef struct {
    void** items;
    int64_t len;
    int64_t cap;
} pact_list;

static pact_list* pact_list_new(void) {
    pact_list* l = (pact_list*)pact_alloc(sizeof(pact_list));
    l->cap = 8;
    l->len = 0;
    l->items = (void**)pact_alloc(sizeof(void*) * l->cap);
    return l;
}

static void pact_list_push(pact_list* l, void* item) {
    if (l->len >= l->cap) {
        l->cap *= 2;
        l->items = (void**)realloc(l->items, sizeof(void*) * (size_t)l->cap);
        if (!l->items) {
            fprintf(stderr, "pact: out of memory\n");
            exit(1);
        }
    }
    l->items[l->len++] = item;
}

static void* pact_list_get(const pact_list* l, int64_t index) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "pact: list index out of bounds: idx=%lld len=%lld\n", (long long)index, (long long)l->len);
        exit(1);
    }
    return l->items[index];
}

static int pact_list_in_bounds(const pact_list* l, int64_t index) {
    return (index >= 0 && index < l->len);
}

static int64_t pact_list_len(const pact_list* l) {
    return l->len;
}

static void pact_list_set(pact_list* l, int64_t index, void* item) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "pact: list set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    l->items[index] = item;
}

static void* pact_list_pop(pact_list* l) {
    if (l->len <= 0) {
        fprintf(stderr, "pact: list pop on empty list\n");
        exit(1);
    }
    l->len--;
    return l->items[l->len];
}

static void pact_list_free(pact_list* l) {
    if (l) {
        free(l->items);
        free(l);
    }
}

/* ── Hash map (string-keyed) ────────────────────────────────────────── */

static int pact_str_eq(const char* a, const char* b);

static uint64_t pact_map_hash(const char* key) {
    uint64_t h = 14695981039346656037ULL;
    for (const char* p = key; *p; p++) {
        h ^= (uint64_t)(unsigned char)*p;
        h *= 1099511628211ULL;
    }
    return h;
}

typedef struct {
    const char** keys;
    void** values;
    uint8_t* states;   /* 0=empty, 1=occupied, 2=tombstone */
    int64_t len;
    int64_t cap;
} pact_map;

static pact_map* pact_map_new(void) {
    pact_map* m = (pact_map*)pact_alloc(sizeof(pact_map));
    m->cap = 16;
    m->len = 0;
    m->keys = (const char**)pact_alloc(sizeof(const char*) * (size_t)m->cap);
    m->values = (void**)pact_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)pact_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    return m;
}

static void pact_map_grow(pact_map* m) {
    int64_t old_cap = m->cap;
    const char** old_keys = m->keys;
    void** old_values = m->values;
    uint8_t* old_states = m->states;
    m->cap = old_cap * 2;
    m->keys = (const char**)pact_alloc(sizeof(const char*) * (size_t)m->cap);
    m->values = (void**)pact_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)pact_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    m->len = 0;
    for (int64_t i = 0; i < old_cap; i++) {
        if (old_states[i] == 1) {
            uint64_t h = pact_map_hash(old_keys[i]);
            int64_t idx = (int64_t)(h % (uint64_t)m->cap);
            while (m->states[idx] != 0) {
                idx = (idx + 1) % m->cap;
            }
            m->keys[idx] = old_keys[i];
            m->values[idx] = old_values[i];
            m->states[idx] = 1;
            m->len++;
        }
    }
    free(old_keys);
    free(old_values);
    free(old_states);
}

static void pact_map_set(pact_map* m, const char* key, void* value) {
    if (m->len * 10 >= m->cap * 7) {
        pact_map_grow(m);
    }
    uint64_t h = pact_map_hash(key);
    int64_t idx = (int64_t)(h % (uint64_t)m->cap);
    int64_t first_tombstone = -1;
    while (1) {
        if (m->states[idx] == 0) {
            int64_t ins = (first_tombstone >= 0) ? first_tombstone : idx;
            m->keys[ins] = key;
            m->values[ins] = value;
            m->states[ins] = 1;
            m->len++;
            return;
        }
        if (m->states[idx] == 2) {
            if (first_tombstone < 0) first_tombstone = idx;
        } else if (pact_str_eq(m->keys[idx], key)) {
            m->values[idx] = value;
            return;
        }
        idx = (idx + 1) % m->cap;
    }
}

static void* pact_map_get(const pact_map* m, const char* key) {
    uint64_t h = pact_map_hash(key);
    int64_t idx = (int64_t)(h % (uint64_t)m->cap);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1 && pact_str_eq(m->keys[idx], key)) {
            return m->values[idx];
        }
        idx = (idx + 1) % m->cap;
    }
    return NULL;
}

static int64_t pact_map_has(const pact_map* m, const char* key) {
    uint64_t h = pact_map_hash(key);
    int64_t idx = (int64_t)(h % (uint64_t)m->cap);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1 && pact_str_eq(m->keys[idx], key)) {
            return 1;
        }
        idx = (idx + 1) % m->cap;
    }
    return 0;
}

static int64_t pact_map_remove(pact_map* m, const char* key) {
    uint64_t h = pact_map_hash(key);
    int64_t idx = (int64_t)(h % (uint64_t)m->cap);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1 && pact_str_eq(m->keys[idx], key)) {
            m->states[idx] = 2;
            m->len--;
            return 1;
        }
        idx = (idx + 1) % m->cap;
    }
    return 0;
}

static int64_t pact_map_len(const pact_map* m) {
    return m->len;
}

static pact_list* pact_map_keys(const pact_map* m) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            pact_list_push(result, (void*)m->keys[i]);
        }
    }
    return result;
}

static pact_list* pact_map_values(const pact_map* m) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            pact_list_push(result, m->values[i]);
        }
    }
    return result;
}

static void pact_map_free(pact_map* m) {
    if (m) {
        free(m->keys);
        free(m->values);
        free(m->states);
        free(m);
    }
}

/* ── Byte buffer ────────────────────────────────────────────────────── */

typedef struct {
    uint8_t* data;
    int64_t len;
    int64_t cap;
} pact_bytes;

static pact_bytes* pact_bytes_new(void) {
    pact_bytes* b = (pact_bytes*)pact_alloc(sizeof(pact_bytes));
    b->cap = 16;
    b->len = 0;
    b->data = (uint8_t*)pact_alloc((size_t)b->cap);
    return b;
}

static void pact_bytes_push(pact_bytes* b, int64_t byte) {
    if (b->len >= b->cap) {
        b->cap *= 2;
        b->data = (uint8_t*)realloc(b->data, (size_t)b->cap);
        if (!b->data) { fprintf(stderr, "pact: out of memory\n"); exit(1); }
    }
    b->data[b->len++] = (uint8_t)(byte & 0xFF);
}

static int64_t pact_bytes_get(const pact_bytes* b, int64_t index) {
    if (index < 0 || index >= b->len) return -1;
    return (int64_t)b->data[index];
}

static void pact_bytes_set(pact_bytes* b, int64_t index, int64_t byte) {
    if (index < 0 || index >= b->len) {
        fprintf(stderr, "pact: bytes set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    b->data[index] = (uint8_t)(byte & 0xFF);
}

static int64_t pact_bytes_len(const pact_bytes* b) {
    return b->len;
}

static int64_t pact_bytes_is_empty(const pact_bytes* b) {
    return b->len == 0;
}

static pact_bytes* pact_bytes_concat(const pact_bytes* a, const pact_bytes* b) {
    pact_bytes* r = pact_bytes_new();
    int64_t total = a->len + b->len;
    if (total > r->cap) {
        r->cap = total;
        r->data = (uint8_t*)realloc(r->data, (size_t)r->cap);
    }
    if (a->len > 0) memcpy(r->data, a->data, (size_t)a->len);
    if (b->len > 0) memcpy(r->data + a->len, b->data, (size_t)b->len);
    r->len = total;
    return r;
}

static pact_bytes* pact_bytes_slice(const pact_bytes* b, int64_t start, int64_t end) {
    if (start < 0) start = 0;
    if (end > b->len) end = b->len;
    if (start > end) start = end;
    pact_bytes* r = pact_bytes_new();
    int64_t slen = end - start;
    if (slen > 0) {
        if (slen > r->cap) {
            r->cap = slen;
            r->data = (uint8_t*)realloc(r->data, (size_t)r->cap);
        }
        memcpy(r->data, b->data + start, (size_t)slen);
        r->len = slen;
    }
    return r;
}

static int pact_bytes_to_str_checked(const pact_bytes* b, const char** out) {
    int64_t i = 0;
    while (i < b->len) {
        uint8_t c = b->data[i];
        int64_t seq_len;
        if (c < 0x80) { seq_len = 1; }
        else if ((c & 0xE0) == 0xC0) { seq_len = 2; }
        else if ((c & 0xF0) == 0xE0) { seq_len = 3; }
        else if ((c & 0xF8) == 0xF0) { seq_len = 4; }
        else { *out = "invalid UTF-8: unexpected continuation byte"; return 0; }
        if (i + seq_len > b->len) { *out = "invalid UTF-8: truncated sequence"; return 0; }
        for (int64_t j = 1; j < seq_len; j++) {
            if ((b->data[i + j] & 0xC0) != 0x80) { *out = "invalid UTF-8: bad continuation byte"; return 0; }
        }
        i += seq_len;
    }
    char* s = (char*)pact_alloc(b->len + 1);
    memcpy(s, b->data, (size_t)b->len);
    s[b->len] = '\0';
    *out = s;
    return 1;
}

static const char* pact_bytes_to_hex(const pact_bytes* b) {
    char* hex = (char*)pact_alloc(b->len * 2 + 1);
    for (int64_t i = 0; i < b->len; i++) {
        sprintf(hex + i * 2, "%02x", b->data[i]);
    }
    hex[b->len * 2] = '\0';
    return hex;
}

static pact_bytes* pact_bytes_from_str(const char* s) {
    pact_bytes* b = pact_bytes_new();
    int64_t slen = (int64_t)strlen(s);
    if (slen > b->cap) {
        b->cap = slen;
        b->data = (uint8_t*)realloc(b->data, (size_t)b->cap);
    }
    memcpy(b->data, s, (size_t)slen);
    b->len = slen;
    return b;
}

static int64_t pact_str_len(const char* s) {
    return (int64_t)strlen(s);
}

static int64_t pact_str_char_at(const char* s, int64_t i) {
    return (int64_t)(unsigned char)s[i];
}

static const char* pact_str_substr(const char* s, int64_t start, int64_t len) {
    char* buf = (char*)pact_alloc(len + 1);
    memcpy(buf, s + start, (size_t)len);
    buf[len] = '\0';
    return buf;
}

static const char* pact_str_from_char_code(int64_t code) {
    char* buf = (char*)pact_alloc(2);
    buf[0] = (char)code;
    buf[1] = '\0';
    return buf;
}

static const char* pact_str_concat(const char* a, const char* b) {
    int64_t la = pact_str_len(a);
    int64_t lb = pact_str_len(b);
    char* buf = (char*)pact_alloc(la + lb + 1);
    memcpy(buf, a, (size_t)la);
    memcpy(buf + la, b, (size_t)lb);
    buf[la + lb] = '\0';
    return buf;
}

static int pact_str_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}

static int pact_str_contains(const char* s, const char* needle) {
    return strstr(s, needle) != NULL;
}

static int pact_str_starts_with(const char* s, const char* prefix) {
    size_t plen = strlen(prefix);
    return strncmp(s, prefix, plen) == 0;
}

static int pact_str_ends_with(const char* s, const char* suffix) {
    size_t slen = strlen(s);
    size_t sufflen = strlen(suffix);
    if (sufflen > slen) return 0;
    return memcmp(s + slen - sufflen, suffix, sufflen) == 0;
}

static const char* pact_read_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "pact: cannot open file: %s\n", path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)pact_alloc(size + 1);
    fread(buf, 1, (size_t)size, f);
    buf[size] = '\0';
    fclose(f);
    return buf;
}

static void pact_write_file(const char* path, const char* content) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "pact: cannot open file for writing: %s\n", path);
        exit(1);
    }
    size_t len = strlen(content);
    fwrite(content, 1, len, f);
    fclose(f);
}

static int pact_g_argc = 0;
static const char** pact_g_argv = NULL;

static int64_t pact_arg_count(void) {
    return (int64_t)pact_g_argc;
}

static const char* pact_get_arg(int64_t index) {
    if (index < 0 || index >= pact_g_argc) {
        fprintf(stderr, "pact: arg index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    return pact_g_argv[index];
}

static int64_t pact_file_exists(const char* path) {
    return access(path, F_OK) == 0 ? 1 : 0;
}

static int64_t pact_is_dir(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
}

static pact_list* pact_list_dir(const char* path) {
    pact_list* result = pact_list_new();
    DIR* d = opendir(path);
    if (!d) return result;
    struct dirent* entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.' && (entry->d_name[1] == '\0' ||
            (entry->d_name[1] == '.' && entry->d_name[2] == '\0'))) continue;
        pact_list_push(result, (void*)strdup(entry->d_name));
    }
    closedir(d);
    return result;
}

/* ── Unix domain sockets ────────────────────────────────────────────── */

static int64_t pact_unix_socket_listen(const char* path) {
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

static int64_t pact_unix_socket_connect(const char* path) {
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

static int64_t pact_unix_socket_accept(int64_t listen_fd) {
    int client = accept((int)listen_fd, NULL, NULL);
    if (client < 0) {
        fprintf(stderr, "pact: accept() failed\n");
        return -1;
    }
    return (int64_t)client;
}

static int64_t pact_unix_socket_accept_timeout(int64_t listen_fd, int64_t timeout_ms) {
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

static void pact_unix_socket_close(int64_t fd) {
    close((int)fd);
}

static const char* pact_socket_read_line(int64_t fd) {
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

static void pact_socket_write(int64_t fd, const char* data) {
    size_t len = strlen(data);
    size_t written = 0;
    while (written < len) {
        ssize_t n = write((int)fd, data + written, len - written);
        if (n <= 0) break;
        written += (size_t)n;
    }
}

/* ── File stat ──────────────────────────────────────────────────────── */

static int64_t pact_file_mtime(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
#ifdef __APPLE__
    return (int64_t)st.st_mtimespec.tv_sec * 1000 +
           (int64_t)(st.st_mtimespec.tv_nsec / 1000000);
#else
    return (int64_t)st.st_mtim.tv_sec * 1000 +
           (int64_t)(st.st_mtim.tv_nsec / 1000000);
#endif
}

/* ── Process info ───────────────────────────────────────────────────── */

static int64_t pact_getpid(void) {
    return (int64_t)getpid();
}

static void pact_exit(int64_t code) { exit((int)code); }

static const char* pact_path_join(const char* a, const char* b) {
    int64_t la = pact_str_len(a);
    int64_t lb = pact_str_len(b);
    int has_slash = (la > 0 && a[la-1] == '/') ? 1 : 0;
    if (has_slash) {
        return pact_str_concat(a, b);
    }
    char* buf = (char*)pact_alloc(la + 1 + lb + 1);
    memcpy(buf, a, (size_t)la);
    buf[la] = '/';
    memcpy(buf + la + 1, b, (size_t)lb);
    buf[la + 1 + lb] = '\0';
    return buf;
}

static const char* pact_path_dirname(const char* path) {
    int64_t len = pact_str_len(path);
    int64_t i = len - 1;
    while (i >= 0 && path[i] != '/') {
        i--;
    }
    if (i < 0) {
        return strdup(".");
    }
    if (i == 0) {
        return strdup("/");
    }
    return pact_str_substr(path, 0, i);
}

static const char* pact_path_basename(const char* path) {
    int64_t len = pact_str_len(path);
    int64_t i = len - 1;
    while (i >= 0 && path[i] != '/') {
        i--;
    }
    int64_t start = i + 1;
    int64_t blen = len - start;
    char* buf = (char*)pact_alloc(blen + 1);
    memcpy(buf, path + start, (size_t)blen);
    buf[blen] = '\0';
    return buf;
}

static int64_t pact_shell_exec(const char* command) {
    int status = system(command);
#ifdef _WIN32
    return (int64_t)status;
#else
    if (WIFEXITED(status)) {
        return (int64_t)WEXITSTATUS(status);
    }
    return -1;
#endif
}

typedef struct {
    const char* message;
    const char* source_type;
    const char* target_type;
} pact_ConversionError;

typedef struct {
    void* fn_ptr;
    void** captures;
    int64_t capture_count;
} pact_closure;

static pact_closure* pact_closure_new(void* fn_ptr, void** captures, int64_t capture_count) {
    pact_closure* c = (pact_closure*)pact_alloc(sizeof(pact_closure));
    c->fn_ptr = fn_ptr;
    c->captures = captures;
    c->capture_count = capture_count;
    return c;
}

static void* pact_closure_get_fn(const pact_closure* c) {
    return c->fn_ptr;
}

static void* pact_closure_get_capture(const pact_closure* c, int64_t index) {
    if (index < 0 || index >= c->capture_count) {
        fprintf(stderr, "pact: closure capture index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    return c->captures[index];
}

/* ── Effect handler vtables ──────────────────────────────────────────
 *
 * Each built-in effect (IO, FS, Net, DB, Crypto, Rand, Time, Env,
 * Process) gets a vtable struct whose slots correspond to the effect's
 * operations as defined in sections/04_effects.md §4.3.
 *
 * pact_ctx holds one pointer per effect vtable.  Effectful functions
 * receive pact_ctx* as their first parameter so handlers can swap
 * implementations (testing, sandboxing, DI).
 */

/* ── IO ─────────────────────────────────────────────────────────────── */
typedef struct {
    void  (*print)(const char* msg);
    void  (*log)(const char* msg);
} pact_io_vtable;

static void pact_io_default_print(const char* msg) {
    printf("%s\n", msg);
}

static void pact_io_default_log(const char* msg) {
    fprintf(stderr, "[LOG] %s\n", msg);
}

static pact_io_vtable pact_io_vtable_default = {
    pact_io_default_print,
    pact_io_default_log
};

/* ── FS ─────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* path);
    int         (*write)(const char* path, const char* content);
    int         (*delete_file)(const char* path);
    int         (*watch)(const char* path, void (*callback)(const char*));
} pact_fs_vtable;

static const char* pact_fs_default_read(const char* path) {
    return pact_read_file(path);
}

static int pact_fs_default_write(const char* path, const char* content) {
    pact_write_file(path, content);
    return 0;
}

static int pact_fs_default_delete(const char* path) {
    return remove(path);
}

static int pact_fs_default_watch(const char* path, void (*callback)(const char*)) {
    (void)path; (void)callback;
    fprintf(stderr, "pact: fs.watch not implemented\n");
    return -1;
}

static pact_fs_vtable pact_fs_vtable_default = {
    pact_fs_default_read,
    pact_fs_default_write,
    pact_fs_default_delete,
    pact_fs_default_watch
};

/* ── Net ────────────────────────────────────────────────────────────── */
typedef struct {
    int (*connect)(const char* url);
    int (*listen)(const char* addr, int port);
    const char* (*dns)(const char* hostname);
} pact_net_vtable;

static int pact_net_default_connect(const char* url) {
    (void)url;
    fprintf(stderr, "pact: net.connect not implemented\n");
    return -1;
}

static int pact_net_default_listen(const char* addr, int port) {
    (void)addr; (void)port;
    fprintf(stderr, "pact: net.listen not implemented\n");
    return -1;
}

static const char* pact_net_default_dns(const char* hostname) {
    (void)hostname;
    fprintf(stderr, "pact: net.dns not implemented\n");
    return NULL;
}

static pact_net_vtable pact_net_vtable_default = {
    pact_net_default_connect,
    pact_net_default_listen,
    pact_net_default_dns
};

/* ── DB ─────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* query);
    int         (*write)(const char* query);
    int         (*admin)(const char* query);
} pact_db_vtable;

static const char* pact_db_default_read(const char* query) {
    (void)query;
    fprintf(stderr, "pact: db.read not implemented\n");
    return NULL;
}

static int pact_db_default_write(const char* query) {
    (void)query;
    fprintf(stderr, "pact: db.write not implemented\n");
    return -1;
}

static int pact_db_default_admin(const char* query) {
    (void)query;
    fprintf(stderr, "pact: db.admin not implemented\n");
    return -1;
}

static pact_db_vtable pact_db_vtable_default = {
    pact_db_default_read,
    pact_db_default_write,
    pact_db_default_admin
};

/* ── Crypto ─────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*hash)(const char* data);
    const char* (*sign)(const char* data, const char* key);
    const char* (*encrypt)(const char* data, const char* key);
    const char* (*decrypt)(const char* data, const char* key);
} pact_crypto_vtable;

static const char* pact_crypto_default_hash(const char* data) {
    (void)data;
    fprintf(stderr, "pact: crypto.hash not implemented\n");
    return NULL;
}

static const char* pact_crypto_default_sign(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "pact: crypto.sign not implemented\n");
    return NULL;
}

static const char* pact_crypto_default_encrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "pact: crypto.encrypt not implemented\n");
    return NULL;
}

static const char* pact_crypto_default_decrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "pact: crypto.decrypt not implemented\n");
    return NULL;
}

static pact_crypto_vtable pact_crypto_vtable_default = {
    pact_crypto_default_hash,
    pact_crypto_default_sign,
    pact_crypto_default_encrypt,
    pact_crypto_default_decrypt
};

/* ── Rand ───────────────────────────────────────────────────────────── */
typedef struct {
    int64_t (*rand_int)(int64_t min, int64_t max);
    double  (*rand_float)(void);
    void    (*rand_bytes)(void* buf, int64_t len);
} pact_rand_vtable;

static int pact_rand_seeded = 0;

static void pact_rand_ensure_seed(void) {
    if (!pact_rand_seeded) {
        srand((unsigned)42);
        pact_rand_seeded = 1;
    }
}

static int64_t pact_rand_default_int(int64_t min, int64_t max) {
    pact_rand_ensure_seed();
    if (min >= max) return min;
    return min + (int64_t)(rand() % (int)(max - min));
}

static double pact_rand_default_float(void) {
    pact_rand_ensure_seed();
    return (double)rand() / (double)RAND_MAX;
}

static void pact_rand_default_bytes(void* buf, int64_t len) {
    pact_rand_ensure_seed();
    unsigned char* p = (unsigned char*)buf;
    for (int64_t i = 0; i < len; i++) {
        p[i] = (unsigned char)(rand() & 0xFF);
    }
}

static pact_rand_vtable pact_rand_vtable_default = {
    pact_rand_default_int,
    pact_rand_default_float,
    pact_rand_default_bytes
};

/* ── Duration / Instant value types ─────────────────────────────────── */

typedef struct { int64_t nanos; } pact_duration;
typedef struct { int64_t nanos; } pact_instant;

/* Duration constructors */
static pact_duration pact_duration_nanos(int64_t n)   { return (pact_duration){.nanos = n}; }
static pact_duration pact_duration_ms(int64_t ms)     { return (pact_duration){.nanos = ms * 1000000LL}; }
static pact_duration pact_duration_seconds(int64_t s) { return (pact_duration){.nanos = s * 1000000000LL}; }
static pact_duration pact_duration_minutes(int64_t m) { return (pact_duration){.nanos = m * 60LL * 1000000000LL}; }
static pact_duration pact_duration_hours(int64_t h)   { return (pact_duration){.nanos = h * 3600LL * 1000000000LL}; }

/* Duration conversions */
static int64_t pact_duration_to_nanos(pact_duration d)   { return d.nanos; }
static int64_t pact_duration_to_ms(pact_duration d)      { return d.nanos / 1000000LL; }
static int64_t pact_duration_to_seconds(pact_duration d) { return d.nanos / 1000000000LL; }

/* Duration arithmetic */
static pact_duration pact_duration_add(pact_duration a, pact_duration b) { return (pact_duration){.nanos = a.nanos + b.nanos}; }
static pact_duration pact_duration_sub(pact_duration a, pact_duration b) { return (pact_duration){.nanos = a.nanos - b.nanos}; }
static pact_duration pact_duration_scale(pact_duration d, int64_t factor) { return (pact_duration){.nanos = d.nanos * factor}; }

/* Duration query */
static int64_t pact_duration_is_zero(pact_duration d) { return d.nanos == 0 ? 1 : 0; }

/* Instant conversions */
static int64_t pact_instant_to_unix_secs(pact_instant i) { return i.nanos / 1000000000LL; }
static int64_t pact_instant_to_unix_ms(pact_instant i)   { return i.nanos / 1000000LL; }

static const char* pact_instant_to_rfc3339(pact_instant i) {
    time_t epoch_secs = (time_t)(i.nanos / 1000000000LL);
    struct tm utc;
    gmtime_r(&epoch_secs, &utc);
    char* buf = (char*)pact_alloc(32);
    snprintf(buf, 32, "%04d-%02d-%02dT%02d:%02d:%02dZ",
             utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday,
             utc.tm_hour, utc.tm_min, utc.tm_sec);
    return buf;
}

/* Instant arithmetic */
static pact_instant pact_instant_add(pact_instant i, pact_duration d) { return (pact_instant){.nanos = i.nanos + d.nanos}; }
static pact_duration pact_instant_since(pact_instant later, pact_instant earlier) { return (pact_duration){.nanos = later.nanos - earlier.nanos}; }

static pact_duration pact_instant_elapsed(pact_instant then) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t now_nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
    return (pact_duration){.nanos = now_nanos - then.nanos};
}

/* ── Time ───────────────────────────────────────────────────────────── */
typedef struct {
    pact_instant (*read)(void);
    void         (*sleep)(pact_duration d);
} pact_time_vtable;

static pact_instant pact_time_default_read(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (pact_instant){.nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec};
}

static void pact_time_default_sleep(pact_duration d) {
    int64_t ns = d.nanos;
    struct timespec ts;
    ts.tv_sec  = (time_t)(ns / 1000000000LL);
    ts.tv_nsec = (long)(ns % 1000000000LL);
    nanosleep(&ts, NULL);
}

static pact_time_vtable pact_time_vtable_default = {
    pact_time_default_read,
    pact_time_default_sleep
};

static int64_t pact_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

/* ── Env ────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* name);
    int         (*write)(const char* name, const char* value);
} pact_env_vtable;

static const char* pact_env_default_read(const char* name) {
    const char* v = getenv(name);
    return v ? strdup(v) : NULL;
}

static int pact_env_default_write(const char* name, const char* value) {
    return setenv(name, value, 1);
}

static pact_env_vtable pact_env_vtable_default = {
    pact_env_default_read,
    pact_env_default_write
};

/* ── Process ────────────────────────────────────────────────────────── */
typedef struct {
    int64_t (*spawn)(const char* command);
    int     (*signal)(int64_t pid, int sig);
} pact_process_vtable;

static int64_t pact_process_default_spawn(const char* command) {
    (void)command;
    fprintf(stderr, "pact: process.spawn not implemented\n");
    return -1;
}

static int pact_process_default_signal(int64_t pid, int sig) {
    (void)pid; (void)sig;
    fprintf(stderr, "pact: process.signal not implemented\n");
    return -1;
}

static pact_process_vtable pact_process_vtable_default = {
    pact_process_default_spawn,
    pact_process_default_signal
};

/* ── pact_ctx: runtime context carrying all effect vtables ──────────── */
typedef struct {
    pact_io_vtable*      io;
    pact_fs_vtable*      fs;
    pact_net_vtable*     net;
    pact_db_vtable*      db;
    pact_crypto_vtable*  crypto;
    pact_rand_vtable*    rand;
    pact_time_vtable*    time;
    pact_env_vtable*     env;
    pact_process_vtable* process;
} pact_ctx;

static pact_ctx pact_ctx_default(void) {
    pact_ctx ctx;
    ctx.io      = &pact_io_vtable_default;
    ctx.fs      = &pact_fs_vtable_default;
    ctx.net     = &pact_net_vtable_default;
    ctx.db      = &pact_db_vtable_default;
    ctx.crypto  = &pact_crypto_vtable_default;
    ctx.rand    = &pact_rand_vtable_default;
    ctx.time    = &pact_time_vtable_default;
    ctx.env     = &pact_env_vtable_default;
    ctx.process = &pact_process_vtable_default;
    return ctx;
}

/* ── Concurrency: pthreads-based thread pool ───────────────────────── */

typedef struct pact_task {
    void (*fn)(void*);
    void* arg;
    struct pact_task* next;
} pact_task;

typedef struct {
    pthread_t* threads;
    int thread_count;
    pact_task* queue_head;
    pact_task* queue_tail;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int shutdown;
} pact_threadpool;

/* ── Handle[T]: opaque result holder for async.spawn ────────────────── */

#define PACT_HANDLE_RUNNING   0
#define PACT_HANDLE_DONE      1
#define PACT_HANDLE_CANCELLED 2

typedef struct {
    pthread_t thread;
    void* result;
    int status;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
} pact_handle;

/* ── Channel[T]: bounded ring buffer for send/recv ──────────────────── */

typedef struct {
    void** buffer;
    int64_t capacity;
    int64_t head;
    int64_t tail;
    int64_t count;
    int closed;
    pthread_mutex_t mutex;
    pthread_cond_t send_cond;
    pthread_cond_t recv_cond;
} pact_channel;

static void* pact_threadpool_worker(void* arg) {
    pact_threadpool* pool = (pact_threadpool*)arg;
    while (1) {
        pthread_mutex_lock(&pool->mutex);
        while (!pool->queue_head && !pool->shutdown) {
            pthread_cond_wait(&pool->cond, &pool->mutex);
        }
        if (pool->shutdown && !pool->queue_head) {
            pthread_mutex_unlock(&pool->mutex);
            break;
        }
        pact_task* task = pool->queue_head;
        pool->queue_head = task->next;
        if (!pool->queue_head) {
            pool->queue_tail = NULL;
        }
        pthread_mutex_unlock(&pool->mutex);
        task->fn(task->arg);
        free(task);
    }
    return NULL;
}

static pact_threadpool* pact_threadpool_init(int thread_count) {
    if (thread_count <= 0) {
        thread_count = 4;
    }
    pact_threadpool* pool = (pact_threadpool*)pact_alloc(sizeof(pact_threadpool));
    pool->thread_count = thread_count;
    pool->queue_head = NULL;
    pool->queue_tail = NULL;
    pool->shutdown = 0;
    pthread_mutex_init(&pool->mutex, NULL);
    pthread_cond_init(&pool->cond, NULL);
    pool->threads = (pthread_t*)pact_alloc(sizeof(pthread_t) * thread_count);
    for (int i = 0; i < thread_count; i++) {
        pthread_create(&pool->threads[i], NULL, pact_threadpool_worker, pool);
    }
    return pool;
}

static void pact_threadpool_submit(pact_threadpool* pool, void (*fn)(void*), void* arg) {
    pact_task* task = (pact_task*)pact_alloc(sizeof(pact_task));
    task->fn = fn;
    task->arg = arg;
    task->next = NULL;
    pthread_mutex_lock(&pool->mutex);
    if (pool->queue_tail) {
        pool->queue_tail->next = task;
    } else {
        pool->queue_head = task;
    }
    pool->queue_tail = task;
    pthread_cond_signal(&pool->cond);
    pthread_mutex_unlock(&pool->mutex);
}

static void pact_threadpool_shutdown(pact_threadpool* pool) {
    pthread_mutex_lock(&pool->mutex);
    pool->shutdown = 1;
    pthread_cond_broadcast(&pool->cond);
    pthread_mutex_unlock(&pool->mutex);
    for (int i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }
    pthread_mutex_destroy(&pool->mutex);
    pthread_cond_destroy(&pool->cond);
    free(pool->threads);
    free(pool);
}

/* ── Handle operations ──────────────────────────────────────────────── */

static pact_handle* pact_handle_new(void) {
    pact_handle* h = (pact_handle*)pact_alloc(sizeof(pact_handle));
    memset(&h->thread, 0, sizeof(pthread_t));
    h->result = NULL;
    h->status = PACT_HANDLE_RUNNING;
    pthread_mutex_init(&h->mutex, NULL);
    pthread_cond_init(&h->cond, NULL);
    return h;
}

static void pact_handle_set_result(pact_handle* h, void* result) {
    pthread_mutex_lock(&h->mutex);
    h->result = result;
    h->status = PACT_HANDLE_DONE;
    pthread_cond_broadcast(&h->cond);
    pthread_mutex_unlock(&h->mutex);
}

static void* pact_handle_await(pact_handle* h) {
    pthread_mutex_lock(&h->mutex);
    while (h->status == PACT_HANDLE_RUNNING) {
        pthread_cond_wait(&h->cond, &h->mutex);
    }
    void* result = h->result;
    pthread_mutex_unlock(&h->mutex);
    return result;
}

static void pact_handle_cancel(pact_handle* h) {
    pthread_mutex_lock(&h->mutex);
    if (h->status == PACT_HANDLE_RUNNING) {
        h->status = PACT_HANDLE_CANCELLED;
        pthread_cond_broadcast(&h->cond);
    }
    pthread_mutex_unlock(&h->mutex);
}

/* ── Test runner infrastructure ───────────────────────────────────── */

typedef struct {
    const char* name;
    void (*fn)(void);
    const char* file;
    int line;
    int skip;
    const char** tags;
    int tag_count;
} pact_test_entry;

static jmp_buf __pact_test_jmp;
static int __pact_test_failed;
static char __pact_test_fail_msg[512];
static int __pact_test_fail_line;

static void __pact_debug_assert_fail(const char* file, int line, const char* fn, const char* cond, const char* msg) {
    fprintf(stderr, "DEBUG ASSERT FAILED: %s\n", msg);
    fprintf(stderr, "  condition: %s\n", cond);
    fprintf(stderr, "  location: %s:%d in %s\n", file, line, fn);
    exit(1);
}

static void __pact_assert_fail(const char* msg, int line) {
    __pact_test_failed = 1;
    if (msg) {
        strncpy(__pact_test_fail_msg, msg, sizeof(__pact_test_fail_msg) - 1);
        __pact_test_fail_msg[sizeof(__pact_test_fail_msg) - 1] = '\0';
    } else {
        __pact_test_fail_msg[0] = '\0';
    }
    __pact_test_fail_line = line;
    longjmp(__pact_test_jmp, 1);
}

static int __pact_test_has_tag(const pact_test_entry* test, const char* tag) {
    for (int t = 0; t < test->tag_count; t++) {
        if (strcmp(test->tags[t], tag) == 0) return 1;
    }
    return 0;
}

static void __pact_test_print_tags_json(const pact_test_entry* test) {
    printf(",\"tags\":[");
    for (int t = 0; t < test->tag_count; t++) {
        if (t > 0) printf(",");
        printf("\"%s\"", test->tags[t]);
    }
    printf("]");
}

static void pact_test_run(const pact_test_entry* tests, int count, int argc, const char** argv) {
    const char* filter = NULL;
    const char* tags_filter = NULL;
    int json_output = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--test-filter") == 0 && i + 1 < argc) {
            filter = argv[++i];
        } else if (strcmp(argv[i], "--test-tags") == 0 && i + 1 < argc) {
            tags_filter = argv[++i];
        } else if (strcmp(argv[i], "--test-json") == 0) {
            json_output = 1;
        }
    }

    int pass = 0, fail = 0, skip = 0, total = 0;

    if (json_output) printf("{\"tests\":[");

    for (int i = 0; i < count; i++) {
        if (filter && !strstr(tests[i].name, filter)) continue;
        if (tags_filter && !__pact_test_has_tag(&tests[i], tags_filter)) continue;
        if (tests[i].skip) { skip++; total++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"skipped\"", tests[i].name);
                __pact_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[33mskipped\033[0m\n", tests[i].name);
            }
            continue;
        }
        total++;
        __pact_test_failed = 0;
        __pact_test_fail_msg[0] = '\0';
        __pact_test_fail_line = 0;
        if (setjmp(__pact_test_jmp) == 0) {
            tests[i].fn();
        }
        if (__pact_test_failed) {
            fail++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"fail\",\"line\":%d,\"message\":\"%s\"",
                       tests[i].name, __pact_test_fail_line, __pact_test_fail_msg);
                __pact_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[31mFAIL\033[0m\n", tests[i].name);
                if (__pact_test_fail_msg[0]) {
                    fprintf(stderr, "  %s (line %d)\n", __pact_test_fail_msg, __pact_test_fail_line);
                }
            }
        } else {
            pass++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"pass\"", tests[i].name);
                __pact_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[32mok\033[0m\n", tests[i].name);
            }
        }
    }

    if (json_output) {
        printf("],\"summary\":{\"total\":%d,\"passed\":%d,\"failed\":%d,\"skipped\":%d}}\n", total, pass, fail, skip);
    } else {
        printf("\n%d passed, %d failed", pass, fail);
        if (skip > 0) printf(", %d skipped", skip);
        printf(" (of %d)\n", total);
    }
    if (fail > 0) exit(1);
}

/* ── Channel operations ─────────────────────────────────────────────── */

static pact_channel* pact_channel_new(int64_t capacity) {
    if (capacity <= 0) capacity = 16;
    pact_channel* ch = (pact_channel*)pact_alloc(sizeof(pact_channel));
    ch->buffer = (void**)pact_alloc(sizeof(void*) * (size_t)capacity);
    ch->capacity = capacity;
    ch->head = 0;
    ch->tail = 0;
    ch->count = 0;
    ch->closed = 0;
    pthread_mutex_init(&ch->mutex, NULL);
    pthread_cond_init(&ch->send_cond, NULL);
    pthread_cond_init(&ch->recv_cond, NULL);
    return ch;
}

static int pact_channel_send(pact_channel* ch, void* value) {
    pthread_mutex_lock(&ch->mutex);
    while (ch->count >= ch->capacity && !ch->closed) {
        pthread_cond_wait(&ch->send_cond, &ch->mutex);
    }
    if (ch->closed) {
        pthread_mutex_unlock(&ch->mutex);
        return -1;
    }
    ch->buffer[ch->tail] = value;
    ch->tail = (ch->tail + 1) % ch->capacity;
    ch->count++;
    pthread_cond_signal(&ch->recv_cond);
    pthread_mutex_unlock(&ch->mutex);
    return 0;
}

static void* pact_channel_recv(pact_channel* ch) {
    pthread_mutex_lock(&ch->mutex);
    while (ch->count == 0 && !ch->closed) {
        pthread_cond_wait(&ch->recv_cond, &ch->mutex);
    }
    if (ch->count == 0 && ch->closed) {
        pthread_mutex_unlock(&ch->mutex);
        return NULL;
    }
    void* value = ch->buffer[ch->head];
    ch->head = (ch->head + 1) % ch->capacity;
    ch->count--;
    pthread_cond_signal(&ch->send_cond);
    pthread_mutex_unlock(&ch->mutex);
    return value;
}

static void pact_channel_close(pact_channel* ch) {
    pthread_mutex_lock(&ch->mutex);
    ch->closed = 1;
    pthread_cond_broadcast(&ch->send_cond);
    pthread_cond_broadcast(&ch->recv_cond);
    pthread_mutex_unlock(&ch->mutex);
}

/* ── HTTP client (POSIX sockets, HTTP/1.1, no TLS) ─────────────────── */

static int pact_http_parse_url(const char* url,
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

static int pact_http_request(
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

/* ── String utilities: slice and to_int ─────────────────────────────── */

static const char* pact_str_slice(const char* s, int64_t start, int64_t end) {
    int64_t slen = (int64_t)strlen(s);
    if (start < 0) start = 0;
    if (end > slen) end = slen;
    if (start >= end) return strdup("");
    int64_t rlen = end - start;
    char* buf = (char*)pact_alloc(rlen + 1);
    memcpy(buf, s + start, (size_t)rlen);
    buf[rlen] = '\0';
    return buf;
}

static int64_t pact_parse_int(const char* s) {
    return (int64_t)atoll(s);
}

static pact_list* pact_str_split(const char* s, const char* delim) {
    pact_list* result = pact_list_new();
    if (!s || !delim || !*delim) {
        pact_list_push(result, (void*)strdup(s ? s : ""));
        return result;
    }
    int64_t dlen = (int64_t)strlen(delim);
    const char* p = s;
    while (1) {
        const char* found = strstr(p, delim);
        if (!found) {
            pact_list_push(result, (void*)strdup(p));
            break;
        }
        int64_t seg_len = (int64_t)(found - p);
        char* seg = (char*)pact_alloc(seg_len + 1);
        memcpy(seg, p, (size_t)seg_len);
        seg[seg_len] = '\0';
        pact_list_push(result, (void*)seg);
        p = found + dlen;
    }
    return result;
}

static const char* pact_str_join(const pact_list* parts, const char* delim) {
    if (!parts || parts->len == 0) return strdup("");
    int64_t dlen = delim ? (int64_t)strlen(delim) : 0;
    int64_t total = 0;
    for (int64_t i = 0; i < parts->len; i++) {
        total += (int64_t)strlen((const char*)parts->items[i]);
        if (i > 0) total += dlen;
    }
    char* buf = (char*)pact_alloc(total + 1);
    int64_t pos = 0;
    for (int64_t i = 0; i < parts->len; i++) {
        if (i > 0 && dlen > 0) {
            memcpy(buf + pos, delim, (size_t)dlen);
            pos += dlen;
        }
        int64_t slen = (int64_t)strlen((const char*)parts->items[i]);
        memcpy(buf + pos, (const char*)parts->items[i], (size_t)slen);
        pos += slen;
    }
    buf[pos] = '\0';
    return buf;
}

/* ── String utilities: trim, case, replace, index_of, lines ──────── */

static const char* pact_str_trim(const char* s) {
    if (!s) return strdup("");
    const char* start = s;
    while (*start && (*start == ' ' || *start == '\t' || *start == '\n' || *start == '\r')) start++;
    const char* end = s + strlen(s);
    while (end > start && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\n' || end[-1] == '\r')) end--;
    int64_t len = (int64_t)(end - start);
    char* buf = (char*)pact_alloc(len + 1);
    memcpy(buf, start, (size_t)len);
    buf[len] = '\0';
    return buf;
}

static const char* pact_str_to_upper(const char* s) {
    if (!s) return strdup("");
    int64_t len = (int64_t)strlen(s);
    char* buf = (char*)pact_alloc(len + 1);
    for (int64_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        buf[i] = (c >= 'a' && c <= 'z') ? (char)(c - 32) : (char)c;
    }
    buf[len] = '\0';
    return buf;
}

static const char* pact_str_to_lower(const char* s) {
    if (!s) return strdup("");
    int64_t len = (int64_t)strlen(s);
    char* buf = (char*)pact_alloc(len + 1);
    for (int64_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        buf[i] = (c >= 'A' && c <= 'Z') ? (char)(c + 32) : (char)c;
    }
    buf[len] = '\0';
    return buf;
}

static const char* pact_str_replace(const char* s, const char* needle, const char* repl) {
    if (!s || !needle || !*needle) return strdup(s ? s : "");
    if (!repl) repl = "";
    int64_t slen = (int64_t)strlen(s);
    int64_t nlen = (int64_t)strlen(needle);
    int64_t rlen = (int64_t)strlen(repl);
    int64_t count = 0;
    const char* p = s;
    while ((p = strstr(p, needle)) != NULL) { count++; p += nlen; }
    int64_t new_len = slen + count * (rlen - nlen);
    char* buf = (char*)pact_alloc(new_len + 1);
    char* out = buf;
    p = s;
    while (1) {
        const char* found = strstr(p, needle);
        if (!found) { strcpy(out, p); break; }
        int64_t seg = (int64_t)(found - p);
        memcpy(out, p, (size_t)seg);
        out += seg;
        memcpy(out, repl, (size_t)rlen);
        out += rlen;
        p = found + nlen;
    }
    return buf;
}

static int64_t pact_str_index_of(const char* s, const char* needle) {
    if (!s || !needle) return -1;
    const char* found = strstr(s, needle);
    if (!found) return -1;
    return (int64_t)(found - s);
}

static pact_list* pact_str_lines(const char* s) {
    pact_list* result = pact_list_new();
    if (!s || !*s) return result;
    const char* p = s;
    while (*p) {
        const char* eol = p;
        while (*eol && *eol != '\n' && *eol != '\r') eol++;
        int64_t seg_len = (int64_t)(eol - p);
        char* seg = (char*)pact_alloc(seg_len + 1);
        memcpy(seg, p, (size_t)seg_len);
        seg[seg_len] = '\0';
        pact_list_push(result, (void*)seg);
        if (*eol == '\r' && *(eol + 1) == '\n') eol += 2;
        else if (*eol) eol++;
        p = eol;
    }
    return result;
}

static double pact_parse_float(const char* s) {
    return atof(s ? s : "0");
}

/* ── JSON helpers ────────────────────────────────────────────────── */

static const char* pact_json_escape_str(const char* s) {
    if (!s) return "\"null\"";
    int64_t len = (int64_t)strlen(s);
    char* buf = (char*)pact_alloc(len * 2 + 3);
    int64_t j = 0;
    buf[j++] = '"';
    for (int64_t i = 0; i < len; i++) {
        char c = s[i];
        switch (c) {
            case '"':  buf[j++] = '\\'; buf[j++] = '"'; break;
            case '\\': buf[j++] = '\\'; buf[j++] = '\\'; break;
            case '\n': buf[j++] = '\\'; buf[j++] = 'n'; break;
            case '\t': buf[j++] = '\\'; buf[j++] = 't'; break;
            case '\r': buf[j++] = '\\'; buf[j++] = 'r'; break;
            default:   buf[j++] = c; break;
        }
    }
    buf[j++] = '"';
    buf[j] = '\0';
    return buf;
}

/* ── TCP socket functions ───────────────────────────────────────────── */

static int64_t pact_tcp_listen(const char* host, int64_t port) {
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

static int64_t pact_tcp_accept(int64_t listen_fd) {
    int client = accept((int)listen_fd, NULL, NULL);
    return (int64_t)client;
}

static const char* pact_tcp_read(int64_t fd, int64_t max_bytes) {
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

static void pact_tcp_write(int64_t fd, const char* data) {
    size_t len = strlen(data);
    size_t written = 0;
    while (written < len) {
        ssize_t n = write((int)fd, data + written, len - written);
        if (n <= 0) break;
        written += (size_t)n;
    }
}

static void pact_tcp_close(int64_t fd) {
    close((int)fd);
}

/* ── Process: run with stdout/stderr capture ────────────────────────── */

typedef struct {
    const char* out;
    const char* err_out;
    int64_t exit_code;
} pact_ProcessResult;

static void pact_process_exec(const char* cmd, const pact_list* args) {
    int64_t argc = args ? args->len : 0;
    char** argv = (char**)pact_alloc(sizeof(char*) * (int64_t)(argc + 2));
    argv[0] = (char*)cmd;
    for (int64_t i = 0; i < argc; i++) {
        argv[i + 1] = (char*)args->items[i];
    }
    argv[argc + 1] = NULL;
    execvp(cmd, argv);
    perror("execvp");
    _exit(127);
}

static pact_ProcessResult pact_process_run(const char* cmd, const pact_list* args) {
    pact_ProcessResult result = { "", "", -1 };
    int stdout_pipe[2], stderr_pipe[2];
    if (pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        result.err_out = strdup("pipe() failed");
        return result;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(stdout_pipe[0]); close(stdout_pipe[1]);
        close(stderr_pipe[0]); close(stderr_pipe[1]);
        result.err_out = strdup("fork() failed");
        return result;
    }
    if (pid == 0) {
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[1]);
        close(stderr_pipe[1]);
        int64_t argc = args ? args->len : 0;
        char** argv = (char**)pact_alloc(sizeof(char*) * (int64_t)(argc + 2));
        argv[0] = (char*)cmd;
        for (int64_t i = 0; i < argc; i++) {
            argv[i + 1] = (char*)args->items[i];
        }
        argv[argc + 1] = NULL;
        execvp(cmd, argv);
        _exit(127);
    }
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);
    int64_t out_cap = 4096, out_len = 0;
    char* out_buf = (char*)pact_alloc(out_cap);
    while (1) {
        if (out_len + 1024 > out_cap) { out_cap *= 2; out_buf = (char*)realloc(out_buf, (size_t)out_cap); }
        ssize_t n = read(stdout_pipe[0], out_buf + out_len, (size_t)(out_cap - out_len - 1));
        if (n <= 0) break;
        out_len += n;
    }
    out_buf[out_len] = '\0';
    close(stdout_pipe[0]);
    int64_t err_cap = 4096, err_len = 0;
    char* err_buf = (char*)pact_alloc(err_cap);
    while (1) {
        if (err_len + 1024 > err_cap) { err_cap *= 2; err_buf = (char*)realloc(err_buf, (size_t)err_cap); }
        ssize_t n = read(stderr_pipe[0], err_buf + err_len, (size_t)(err_cap - err_len - 1));
        if (n <= 0) break;
        err_len += n;
    }
    err_buf[err_len] = '\0';
    close(stderr_pipe[0]);
    int status;
    waitpid(pid, &status, 0);
    result.out = out_buf;
    result.err_out = err_buf;
    if (WIFEXITED(status)) {
        result.exit_code = (int64_t)WEXITSTATUS(status);
    } else {
        result.exit_code = -1;
    }
    return result;
}


/* ── SQLite3 bindings (conditional) ──────────────────────────────────── */

#ifdef PACT_USE_SQLITE
#include <sqlite3.h>

/* Result struct for pact_sqlite3_query convenience wrapper */
typedef struct {
    pact_list* rows;      /* List of pact_list* (each row is a list of strings) */
    pact_list* columns;   /* List of column name strings */
    int64_t num_rows;
    int64_t num_cols;
} pact_sqlite3_result;

static void* pact_sqlite3_open(const char* path) {
    sqlite3* db = NULL;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    return (void*)db;
}

static int64_t pact_sqlite3_exec(void* db, const char* sql,
                                  int (*callback)(void*, int, char**, char**),
                                  void* arg, const char** errmsg) {
    char* err = NULL;
    int rc = sqlite3_exec((sqlite3*)db, sql, callback, arg, &err);
    if (errmsg) {
        *errmsg = err ? strdup(err) : NULL;
    }
    if (err) sqlite3_free(err);
    return (int64_t)rc;
}

/* Callback used by pact_sqlite3_query to collect rows */
static int pact_sqlite3_query_cb(void* ud, int ncols, char** values, char** names) {
    pact_sqlite3_result* res = (pact_sqlite3_result*)ud;
    if (res->num_rows == 0) {
        for (int i = 0; i < ncols; i++) {
            pact_list_push(res->columns, (void*)strdup(names[i]));
        }
        res->num_cols = (int64_t)ncols;
    }
    pact_list* row = pact_list_new();
    for (int i = 0; i < ncols; i++) {
        pact_list_push(row, (void*)strdup(values[i] ? values[i] : ""));
    }
    pact_list_push(res->rows, (void*)row);
    res->num_rows++;
    return 0;
}

static pact_sqlite3_result* pact_sqlite3_query(void* db, const char* sql) {
    pact_sqlite3_result* res = (pact_sqlite3_result*)pact_alloc(sizeof(pact_sqlite3_result));
    res->rows = pact_list_new();
    res->columns = pact_list_new();
    res->num_rows = 0;
    res->num_cols = 0;
    char* err = NULL;
    int rc = sqlite3_exec((sqlite3*)db, sql, pact_sqlite3_query_cb, res, &err);
    if (rc != SQLITE_OK) {
        if (err) {
            fprintf(stderr, "pact: sqlite3 query error: %s\n", err);
            sqlite3_free(err);
        }
    }
    return res;
}

static void* pact_sqlite3_prepare(void* db, const char* sql) {
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2((sqlite3*)db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return NULL;
    }
    return (void*)stmt;
}

static int64_t pact_sqlite3_bind_int(void* stmt, int64_t idx, int64_t val) {
    return (int64_t)sqlite3_bind_int64((sqlite3_stmt*)stmt, (int)idx, (sqlite3_int64)val);
}

static int64_t pact_sqlite3_bind_text(void* stmt, int64_t idx, const char* val) {
    return (int64_t)sqlite3_bind_text((sqlite3_stmt*)stmt, (int)idx, val, -1, SQLITE_TRANSIENT);
}

static int64_t pact_sqlite3_step(void* stmt) {
    return (int64_t)sqlite3_step((sqlite3_stmt*)stmt);
}

static int64_t pact_sqlite3_column_int(void* stmt, int64_t col) {
    return (int64_t)sqlite3_column_int64((sqlite3_stmt*)stmt, (int)col);
}

static const char* pact_sqlite3_column_text(void* stmt, int64_t col) {
    const unsigned char* text = sqlite3_column_text((sqlite3_stmt*)stmt, (int)col);
    if (!text) return strdup("");
    return strdup((const char*)text);
}

static int64_t pact_sqlite3_reset(void* stmt) {
    return (int64_t)sqlite3_reset((sqlite3_stmt*)stmt);
}

static int64_t pact_sqlite3_finalize(void* stmt) {
    return (int64_t)sqlite3_finalize((sqlite3_stmt*)stmt);
}

static int64_t pact_sqlite3_close(void* db) {
    return (int64_t)sqlite3_close((sqlite3*)db);
}

static const char* pact_sqlite3_errmsg(void* db) {
    const char* msg = sqlite3_errmsg((sqlite3*)db);
    return msg ? strdup(msg) : strdup("");
}

static int64_t pact_sqlite3_begin(void* db) {
    return (int64_t)sqlite3_exec((sqlite3*)db, "BEGIN", NULL, NULL, NULL);
}

static int64_t pact_sqlite3_commit(void* db) {
    return (int64_t)sqlite3_exec((sqlite3*)db, "COMMIT", NULL, NULL, NULL);
}

static int64_t pact_sqlite3_rollback(void* db) {
    return (int64_t)sqlite3_exec((sqlite3*)db, "ROLLBACK", NULL, NULL, NULL);
}

#endif /* PACT_USE_SQLITE */

#endif
