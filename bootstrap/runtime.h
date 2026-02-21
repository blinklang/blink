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

#endif
