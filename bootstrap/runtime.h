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
#include <unistd.h>

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
        fprintf(stderr, "pact: list index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    return l->items[index];
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

static void* pact_closure_get_fn(pact_closure* c) {
    return c->fn_ptr;
}

static void* pact_closure_get_capture(pact_closure* c, int64_t index) {
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

/* ── Time ───────────────────────────────────────────────────────────── */
typedef struct {
    int64_t (*read)(void);
    void    (*sleep)(int64_t ms);
} pact_time_vtable;

static int64_t pact_time_default_read(void) {
    /* seconds since epoch — good enough for bootstrap */
    return (int64_t)time(NULL);
}

static void pact_time_default_sleep(int64_t ms) {
    struct timespec ts;
    ts.tv_sec  = (time_t)(ms / 1000);
    ts.tv_nsec = (long)((ms % 1000) * 1000000L);
    nanosleep(&ts, NULL);
}

static pact_time_vtable pact_time_vtable_default = {
    pact_time_default_read,
    pact_time_default_sleep
};

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

#endif
