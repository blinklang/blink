#ifndef BLINK_RUNTIME_CORE_H
#define BLINK_RUNTIME_CORE_H

#if !defined(_POSIX_C_SOURCE) && !defined(_GNU_SOURCE) && !defined(__APPLE__)
#define _POSIX_C_SOURCE 200809L
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#ifndef _WIN32
#include <sys/wait.h>
#endif
#include <dirent.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/time.h>
#define GC_THREADS
#include <gc.h>

#ifdef __GNUC__
#define BLINK_UNUSED __attribute__((unused))
#else
#define BLINK_UNUSED
#endif

#define BLINK_ARENA_DEFAULT_CHUNK_SIZE ((int64_t)(64 * 1024))
#define BLINK_ARENA_ALIGN ((int64_t)16)

typedef struct blink_arena_chunk {
    struct blink_arena_chunk* next;
    int64_t capacity;
    int64_t used;
    /* _Alignas keeps data[] at a BLINK_ARENA_ALIGN boundary; without it the
       24-byte header on 64-bit lands data[] at 8-aligned, violating the
       per-allocation alignment contract used by blink_arena_alloc. */
    _Alignas(16) char data[];
} blink_arena_chunk;

typedef struct blink_arena_t {
    blink_arena_chunk* head;
    int64_t default_chunk_size;
} blink_arena_t;

static __thread blink_arena_t* __blink_current_arena = NULL;

BLINK_UNUSED static blink_arena_chunk* blink_arena_chunk_new(int64_t capacity) {
    blink_arena_chunk* c = (blink_arena_chunk*)GC_MALLOC_ATOMIC(sizeof(blink_arena_chunk) + (size_t)capacity);
    if (!c) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    c->next = NULL;
    c->capacity = capacity;
    c->used = 0;
    return c;
}

BLINK_UNUSED static blink_arena_t* blink_arena_create(int64_t chunk_size) {
    blink_arena_t* a = (blink_arena_t*)GC_MALLOC(sizeof(blink_arena_t));
    if (!a) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    a->default_chunk_size = chunk_size > 0 ? chunk_size : BLINK_ARENA_DEFAULT_CHUNK_SIZE;
    a->head = blink_arena_chunk_new(a->default_chunk_size);
    return a;
}

BLINK_UNUSED static void blink_arena_destroy(blink_arena_t* a) {
    if (!a) return;
    blink_arena_chunk* c = a->head;
    while (c) {
        blink_arena_chunk* next = c->next;
        GC_FREE(c);
        c = next;
    }
    a->head = NULL;
    GC_FREE(a);
}

BLINK_UNUSED static void* blink_arena_alloc(blink_arena_t* a, int64_t size) {
    if (size <= 0) size = 1;
    int64_t aligned = (size + BLINK_ARENA_ALIGN - 1) & ~(BLINK_ARENA_ALIGN - 1);
    blink_arena_chunk* head = a->head;
    if (aligned > a->default_chunk_size) {
        /* Splice the dedicated chunk *after* head so head's remaining free
           space stays reachable for subsequent small allocations. */
        blink_arena_chunk* big = blink_arena_chunk_new(aligned);
        big->used = aligned;
        if (head) {
            big->next = head->next;
            head->next = big;
        } else {
            a->head = big;
        }
        memset(big->data, 0, (size_t)aligned);
        return big->data;
    }
    if (!head || head->used + aligned > head->capacity) {
        blink_arena_chunk* fresh = blink_arena_chunk_new(a->default_chunk_size);
        fresh->next = head;
        a->head = fresh;
        head = fresh;
    }
    void* p = head->data + head->used;
    head->used += aligned;
    memset(p, 0, (size_t)aligned);
    return p;
}

/* Arena memory is never GC-scanned, so the atomic distinction is meaningless
   here. Kept for API symmetry with GC_MALLOC / GC_MALLOC_ATOMIC. */
BLINK_UNUSED static void* blink_arena_alloc_atomic(blink_arena_t* a, int64_t size) {
    return blink_arena_alloc(a, size);
}

BLINK_UNUSED static void* blink_alloc(int64_t size) {
    blink_arena_t* a = __blink_current_arena;
    if (a != NULL) return blink_arena_alloc(a, size);
    void* p = GC_MALLOC((size_t)size);
    if (!p) {
        fprintf(stderr, "blink: out of memory\n");
        exit(1);
    }
    return p;
}

BLINK_UNUSED static char* blink_strdup(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char* p = (char*)GC_MALLOC_ATOMIC(len);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    memcpy(p, s, len);
    return p;
}

/* Promotion allocation: target==NULL means GC heap; else allocate in target
   arena. Bypasses __blink_current_arena because during promotion the TLS may
   still reference the inner (dying) arena. */
BLINK_UNUSED static void* blink_promote_alloc(blink_arena_t* target, int64_t size) {
    if (target != NULL) return blink_arena_alloc(target, size);
    void* p = GC_MALLOC((size_t)size);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    return p;
}

BLINK_UNUSED static void* blink_promote_alloc_atomic(blink_arena_t* target, int64_t size) {
    if (target != NULL) return blink_arena_alloc(target, size);
    void* p = GC_MALLOC_ATOMIC((size_t)size);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    return p;
}

BLINK_UNUSED static const char* blink_promote_str(blink_arena_t* target, const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char* p = (char*)blink_promote_alloc_atomic(target, (int64_t)len);
    memcpy(p, s, len);
    return p;
}

typedef struct {
    void** items;
    int64_t len;
    int64_t cap;
} blink_list;

BLINK_UNUSED static blink_list* blink_list_new(void) {
    blink_list* l = (blink_list*)blink_alloc(sizeof(blink_list));
    l->cap = 8;
    l->len = 0;
    l->items = (void**)blink_alloc(sizeof(void*) * l->cap);
    return l;
}

BLINK_UNUSED static void blink_list_push(blink_list* l, void* item) {
    if (l->len >= l->cap) {
        l->cap *= 2;
        l->items = (void**)GC_REALLOC(l->items, sizeof(void*) * (size_t)l->cap);
        if (!l->items) {
            fprintf(stderr, "blink: out of memory\n");
            exit(1);
        }
    }
    l->items[l->len++] = item;
}

BLINK_UNUSED static void* blink_list_get(const blink_list* l, int64_t index) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "blink: list index out of bounds: idx=%lld len=%lld\n", (long long)index, (long long)l->len);
        exit(1);
    }
    return l->items[index];
}

BLINK_UNUSED static int blink_list_in_bounds(const blink_list* l, int64_t index) {
    return (index >= 0 && index < l->len);
}

BLINK_UNUSED static int64_t blink_list_len(const blink_list* l) {
    return l->len;
}

BLINK_UNUSED static void blink_list_set(blink_list* l, int64_t index, void* item) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "blink: list set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    l->items[index] = item;
}

BLINK_UNUSED static void* blink_list_pop(blink_list* l) {
    if (l->len <= 0) {
        fprintf(stderr, "blink: list pop on empty list\n");
        exit(1);
    }
    l->len--;
    return l->items[l->len];
}

BLINK_UNUSED static void blink_list_free(blink_list* l) {
    if (l) {
        GC_FREE(l->items);
        GC_FREE(l);
    }
}

BLINK_UNUSED static void blink_list_clear(blink_list* l) {
    l->len = 0;
}

BLINK_UNUSED static blink_list* blink_list_concat(blink_list* a, blink_list* b) {
    blink_list* result = blink_list_new();
    for (int64_t i = 0; i < a->len; i++) blink_list_push(result, a->items[i]);
    for (int64_t i = 0; i < b->len; i++) blink_list_push(result, b->items[i]);
    return result;
}

BLINK_UNUSED static void blink_list_extend(blink_list* dst, blink_list* src) {
    for (int64_t i = 0; i < src->len; i++) blink_list_push(dst, src->items[i]);
}

BLINK_UNUSED static blink_list* blink_list_slice(blink_list* l, int64_t start, int64_t end) {
    blink_list* result = blink_list_new();
    if (start < 0) start = 0;
    if (end > l->len) end = l->len;
    for (int64_t i = start; i < end; i++) blink_list_push(result, l->items[i]);
    return result;
}

/* ── Template (decomposed interpolation for injection safety) ───────── */

#define BLINK_TPL_INT    0
#define BLINK_TPL_FLOAT  1
#define BLINK_TPL_BOOL   2
#define BLINK_TPL_STR    3

typedef struct {
    blink_list* parts;     /* List of const char* — literal segments */
    blink_list* values;    /* List of void* — interpolated values */
    blink_list* types;     /* List of (void*)(intptr_t)BLINK_TPL_* — type tags */
    int64_t count;         /* Number of interpolated values */
} blink_template;

BLINK_UNUSED static blink_template* blink_template_new(int64_t num_values) {
    blink_template* t = (blink_template*)blink_alloc(sizeof(blink_template));
    t->parts = blink_list_new();
    t->values = (num_values > 0) ? blink_list_new() : NULL;
    t->types = (num_values > 0) ? blink_list_new() : NULL;
    t->count = num_values;
    return t;
}

/* ── Hash map (string-keyed) ────────────────────────────────────────── */

BLINK_UNUSED static int blink_str_eq(const char* a, const char* b);

BLINK_UNUSED static uint64_t blink_map_hash(const char* key) {
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
} blink_map;

BLINK_UNUSED static blink_map* blink_map_new(void) {
    blink_map* m = (blink_map*)blink_alloc(sizeof(blink_map));
    m->cap = 16;
    m->len = 0;
    m->keys = (const char**)blink_alloc(sizeof(const char*) * (size_t)m->cap);
    m->values = (void**)blink_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    return m;
}

BLINK_UNUSED static void blink_map_grow(blink_map* m) {
    int64_t old_cap = m->cap;
    const char** old_keys = m->keys;
    void** old_values = m->values;
    uint8_t* old_states = m->states;
    m->cap = old_cap * 2;
    m->keys = (const char**)blink_alloc(sizeof(const char*) * (size_t)m->cap);
    m->values = (void**)blink_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    m->len = 0;
    for (int64_t i = 0; i < old_cap; i++) {
        if (old_states[i] == 1) {
            uint64_t h = blink_map_hash(old_keys[i]);
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
    GC_FREE(old_keys);
    GC_FREE(old_values);
    GC_FREE(old_states);
}

BLINK_UNUSED static void blink_map_set(blink_map* m, const char* key, void* value) {
    if (m->len * 10 >= m->cap * 7) {
        blink_map_grow(m);
    }
    uint64_t h = blink_map_hash(key);
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
        } else if (blink_str_eq(m->keys[idx], key)) {
            m->values[idx] = value;
            return;
        }
        idx = (idx + 1) % m->cap;
    }
}

BLINK_UNUSED static void* blink_map_get(const blink_map* m, const char* key) {
    uint64_t h = blink_map_hash(key);
    int64_t idx = (int64_t)(h % (uint64_t)m->cap);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1 && blink_str_eq(m->keys[idx], key)) {
            return m->values[idx];
        }
        idx = (idx + 1) % m->cap;
    }
    return NULL;
}

BLINK_UNUSED static int64_t blink_map_has(const blink_map* m, const char* key) {
    uint64_t h = blink_map_hash(key);
    int64_t idx = (int64_t)(h % (uint64_t)m->cap);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1 && blink_str_eq(m->keys[idx], key)) {
            return 1;
        }
        idx = (idx + 1) % m->cap;
    }
    return 0;
}

BLINK_UNUSED static int64_t blink_map_remove(blink_map* m, const char* key) {
    uint64_t h = blink_map_hash(key);
    int64_t idx = (int64_t)(h % (uint64_t)m->cap);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1 && blink_str_eq(m->keys[idx], key)) {
            m->states[idx] = 2;
            m->len--;
            return 1;
        }
        idx = (idx + 1) % m->cap;
    }
    return 0;
}

BLINK_UNUSED static int64_t blink_map_len(const blink_map* m) {
    return m->len;
}

BLINK_UNUSED static blink_list* blink_map_keys(const blink_map* m) {
    blink_list* result = blink_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            blink_list_push(result, (void*)m->keys[i]);
        }
    }
    return result;
}

BLINK_UNUSED static blink_list* blink_map_values(const blink_map* m) {
    blink_list* result = blink_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            blink_list_push(result, m->values[i]);
        }
    }
    return result;
}

BLINK_UNUSED static void blink_map_free(blink_map* m) {
    if (m) {
        GC_FREE(m->keys);
        GC_FREE(m->values);
        GC_FREE(m->states);
        GC_FREE(m);
    }
}

BLINK_UNUSED static void blink_map_clear(blink_map* m) {
    m->len = 0;
    memset(m->states, 0, sizeof(uint8_t) * (size_t)m->cap);
}

/* ── Hash set (string-keyed) ─────────────────────────────────────────── */

typedef struct {
    const char** items;
    uint8_t* states;   /* 0=empty, 1=occupied, 2=tombstone */
    int64_t len;
    int64_t cap;
} blink_set;

BLINK_UNUSED static const char* blink_int_to_key(int64_t val) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)val);
    size_t len = strlen(buf);
    char* s = (char*)blink_alloc(len + 1);
    memcpy(s, buf, len + 1);
    return s;
}

BLINK_UNUSED static blink_set* blink_set_new(void) {
    blink_set* s = (blink_set*)blink_alloc(sizeof(blink_set));
    s->cap = 16;
    s->len = 0;
    s->items = (const char**)blink_alloc(sizeof(const char*) * (size_t)s->cap);
    s->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)s->cap);
    memset(s->states, 0, (size_t)s->cap);
    return s;
}

BLINK_UNUSED static void blink_set_grow(blink_set* s) {
    int64_t old_cap = s->cap;
    const char** old_items = s->items;
    uint8_t* old_states = s->states;
    s->cap = old_cap * 2;
    s->items = (const char**)blink_alloc(sizeof(const char*) * (size_t)s->cap);
    s->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)s->cap);
    memset(s->states, 0, (size_t)s->cap);
    s->len = 0;
    for (int64_t i = 0; i < old_cap; i++) {
        if (old_states[i] == 1) {
            uint64_t h = blink_map_hash(old_items[i]);
            int64_t idx = (int64_t)(h % (uint64_t)s->cap);
            while (s->states[idx] != 0) {
                idx = (idx + 1) % s->cap;
            }
            s->items[idx] = old_items[i];
            s->states[idx] = 1;
            s->len++;
        }
    }
    GC_FREE(old_items);
    GC_FREE(old_states);
}

BLINK_UNUSED static int64_t blink_set_insert(blink_set* s, const char* item) {
    if (s->len * 10 >= s->cap * 7) {
        blink_set_grow(s);
    }
    uint64_t h = blink_map_hash(item);
    int64_t idx = (int64_t)(h % (uint64_t)s->cap);
    int64_t first_tombstone = -1;
    while (1) {
        if (s->states[idx] == 0) {
            int64_t ins = (first_tombstone >= 0) ? first_tombstone : idx;
            s->items[ins] = item;
            s->states[ins] = 1;
            s->len++;
            return 1;
        }
        if (s->states[idx] == 2) {
            if (first_tombstone < 0) first_tombstone = idx;
        } else if (blink_str_eq(s->items[idx], item)) {
            return 0;
        }
        idx = (idx + 1) % s->cap;
    }
}

BLINK_UNUSED static int64_t blink_set_contains(const blink_set* s, const char* item) {
    uint64_t h = blink_map_hash(item);
    int64_t idx = (int64_t)(h % (uint64_t)s->cap);
    while (s->states[idx] != 0) {
        if (s->states[idx] == 1 && blink_str_eq(s->items[idx], item)) {
            return 1;
        }
        idx = (idx + 1) % s->cap;
    }
    return 0;
}

BLINK_UNUSED static int64_t blink_set_remove(blink_set* s, const char* item) {
    uint64_t h = blink_map_hash(item);
    int64_t idx = (int64_t)(h % (uint64_t)s->cap);
    while (s->states[idx] != 0) {
        if (s->states[idx] == 1 && blink_str_eq(s->items[idx], item)) {
            s->states[idx] = 2;
            s->len--;
            return 1;
        }
        idx = (idx + 1) % s->cap;
    }
    return 0;
}

BLINK_UNUSED static int64_t blink_set_len(const blink_set* s) {
    return s->len;
}

BLINK_UNUSED static blink_set* blink_set_union(const blink_set* a, const blink_set* b) {
    blink_set* result = blink_set_new();
    for (int64_t i = 0; i < a->cap; i++) {
        if (a->states[i] == 1) {
            blink_set_insert(result, a->items[i]);
        }
    }
    for (int64_t i = 0; i < b->cap; i++) {
        if (b->states[i] == 1) {
            blink_set_insert(result, b->items[i]);
        }
    }
    return result;
}

BLINK_UNUSED static blink_list* blink_set_to_list(const blink_set* s) {
    blink_list* result = blink_list_new();
    for (int64_t i = 0; i < s->cap; i++) {
        if (s->states[i] == 1) {
            blink_list_push(result, (void*)s->items[i]);
        }
    }
    return result;
}

BLINK_UNUSED static void blink_set_free(blink_set* s) {
    if (s) {
        GC_FREE(s->items);
        GC_FREE(s->states);
        GC_FREE(s);
    }
}

/* ── Byte buffer ────────────────────────────────────────────────────── */

typedef struct {
    uint8_t* data;
    int64_t len;
    int64_t cap;
} blink_bytes;

BLINK_UNUSED static blink_bytes* blink_bytes_new(void) {
    blink_bytes* b = (blink_bytes*)blink_alloc(sizeof(blink_bytes));
    b->cap = 16;
    b->len = 0;
    b->data = (uint8_t*)blink_alloc((size_t)b->cap);
    return b;
}

BLINK_UNUSED static void blink_bytes_push(blink_bytes* b, int64_t byte) {
    if (b->len >= b->cap) {
        b->cap *= 2;
        b->data = (uint8_t*)GC_REALLOC(b->data, (size_t)b->cap);
        if (!b->data) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    }
    b->data[b->len++] = (uint8_t)(byte & 0xFF);
}

BLINK_UNUSED static int64_t blink_bytes_get(const blink_bytes* b, int64_t index) {
    if (index < 0 || index >= b->len) return -1;
    return (int64_t)b->data[index];
}

BLINK_UNUSED static void blink_bytes_set(blink_bytes* b, int64_t index, int64_t byte) {
    if (index < 0 || index >= b->len) {
        fprintf(stderr, "blink: bytes set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    b->data[index] = (uint8_t)(byte & 0xFF);
}

BLINK_UNUSED static int64_t blink_bytes_len(const blink_bytes* b) {
    return b->len;
}

BLINK_UNUSED static int64_t blink_bytes_is_empty(const blink_bytes* b) {
    return b->len == 0;
}

BLINK_UNUSED static blink_bytes* blink_bytes_concat(const blink_bytes* a, const blink_bytes* b) {
    blink_bytes* r = blink_bytes_new();
    int64_t total = a->len + b->len;
    if (total > r->cap) {
        r->cap = total;
        r->data = (uint8_t*)GC_REALLOC(r->data, (size_t)r->cap);
    }
    if (a->len > 0) memcpy(r->data, a->data, (size_t)a->len);
    if (b->len > 0) memcpy(r->data + a->len, b->data, (size_t)b->len);
    r->len = total;
    return r;
}

BLINK_UNUSED static blink_bytes* blink_bytes_slice(const blink_bytes* b, int64_t start, int64_t end) {
    if (start < 0) start = 0;
    if (end > b->len) end = b->len;
    if (start > end) start = end;
    blink_bytes* r = blink_bytes_new();
    int64_t slen = end - start;
    if (slen > 0) {
        if (slen > r->cap) {
            r->cap = slen;
            r->data = (uint8_t*)GC_REALLOC(r->data, (size_t)r->cap);
        }
        memcpy(r->data, b->data + start, (size_t)slen);
        r->len = slen;
    }
    return r;
}

BLINK_UNUSED static int blink_bytes_to_str_checked(const blink_bytes* b, const char** out) {
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
    char* s = (char*)blink_alloc(b->len + 1);
    memcpy(s, b->data, (size_t)b->len);
    s[b->len] = '\0';
    *out = s;
    return 1;
}

BLINK_UNUSED static const char* blink_bytes_to_hex(const blink_bytes* b) {
    char* hex = (char*)blink_alloc(b->len * 2 + 1);
    for (int64_t i = 0; i < b->len; i++) {
        sprintf(hex + i * 2, "%02x", b->data[i]);
    }
    hex[b->len * 2] = '\0';
    return hex;
}

BLINK_UNUSED static blink_bytes* blink_bytes_from_str(const char* s) {
    blink_bytes* b = blink_bytes_new();
    int64_t slen = (int64_t)strlen(s);
    if (slen > b->cap) {
        b->cap = slen;
        b->data = (uint8_t*)GC_REALLOC(b->data, (size_t)b->cap);
    }
    memcpy(b->data, s, (size_t)slen);
    b->len = slen;
    return b;
}

BLINK_UNUSED static void blink_bytes_free(blink_bytes* b) {
    if (b) {
        GC_FREE(b->data);
        GC_FREE(b);
    }
}

/* ── StringBuilder ──────────────────────────────────────────────────── */

typedef struct {
    char* data;
    int64_t len;
    int64_t cap;
} blink_sb;

BLINK_UNUSED static blink_sb* blink_sb_new(void) {
    blink_sb* sb = (blink_sb*)blink_alloc(sizeof(blink_sb));
    sb->cap = 64;
    sb->len = 0;
    sb->data = (char*)blink_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}

BLINK_UNUSED static blink_sb* blink_sb_with_capacity(int64_t cap) {
    if (cap < 16) cap = 16;
    blink_sb* sb = (blink_sb*)blink_alloc(sizeof(blink_sb));
    sb->cap = cap;
    sb->len = 0;
    sb->data = (char*)blink_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}

BLINK_UNUSED static void blink_sb_write_n(blink_sb* sb, const char* s, int64_t slen) {
    if (slen == 0) return;
    int64_t needed = sb->len + slen + 1;
    if (needed > sb->cap) {
        int64_t new_cap = sb->cap * 2;
        while (new_cap < needed) new_cap *= 2;
        sb->cap = new_cap;
        sb->data = (char*)GC_REALLOC(sb->data, (size_t)sb->cap);
        if (!sb->data) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    }
    memcpy(sb->data + sb->len, s, (size_t)slen);
    sb->len += slen;
    sb->data[sb->len] = '\0';
}

BLINK_UNUSED static void blink_sb_write(blink_sb* sb, const char* s) {
    blink_sb_write_n(sb, s, (int64_t)strlen(s));
}

BLINK_UNUSED static void blink_sb_write_char(blink_sb* sb, const char* ch) {
    blink_sb_write(sb, ch);
}

BLINK_UNUSED static void blink_sb_write_int(blink_sb* sb, int64_t val) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)val);
    blink_sb_write_n(sb, buf, (int64_t)len);
}

BLINK_UNUSED static void blink_sb_write_float(blink_sb* sb, double val) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%g", val);
    blink_sb_write_n(sb, buf, (int64_t)len);
}

BLINK_UNUSED static void blink_sb_write_bool(blink_sb* sb, int val) {
    blink_sb_write(sb, val ? "true" : "false");
}

BLINK_UNUSED static const char* blink_sb_to_str(const blink_sb* sb) {
    return blink_strdup(sb->data);
}

BLINK_UNUSED static int64_t blink_sb_len(const blink_sb* sb) {
    return sb->len;
}

BLINK_UNUSED static int64_t blink_sb_capacity(const blink_sb* sb) {
    return sb->cap;
}

BLINK_UNUSED static void blink_sb_clear(blink_sb* sb) {
    sb->len = 0;
    sb->data[0] = '\0';
}

BLINK_UNUSED static int blink_sb_is_empty(const blink_sb* sb) {
    return sb->len == 0;
}

BLINK_UNUSED static void blink_sb_free(blink_sb* sb) {
    if (sb) {
        GC_FREE(sb->data);
        GC_FREE(sb);
    }
}

/* ── String operations ──────────────────────────────────────────────── */

BLINK_UNUSED static int64_t blink_str_len(const char* s) {
    return (int64_t)strlen(s);
}

BLINK_UNUSED static int64_t blink_str_char_at(const char* s, int64_t i) {
    return (int64_t)(unsigned char)s[i];
}

BLINK_UNUSED static const char* blink_str_substr(const char* s, int64_t start, int64_t len) {
    char* buf = (char*)blink_alloc(len + 1);
    memcpy(buf, s + start, (size_t)len);
    buf[len] = '\0';
    return buf;
}

BLINK_UNUSED static const char* blink_str_from_char_code(int64_t code) {
    char* buf;
    if (code < 0x80) {
        buf = (char*)blink_alloc(2);
        buf[0] = (char)code;
        buf[1] = '\0';
    } else if (code < 0x800) {
        buf = (char*)blink_alloc(3);
        buf[0] = (char)(0xC0 | (code >> 6));
        buf[1] = (char)(0x80 | (code & 0x3F));
        buf[2] = '\0';
    } else if (code < 0x10000) {
        buf = (char*)blink_alloc(4);
        buf[0] = (char)(0xE0 | (code >> 12));
        buf[1] = (char)(0x80 | ((code >> 6) & 0x3F));
        buf[2] = (char)(0x80 | (code & 0x3F));
        buf[3] = '\0';
    } else if (code <= 0x10FFFF) {
        buf = (char*)blink_alloc(5);
        buf[0] = (char)(0xF0 | (code >> 18));
        buf[1] = (char)(0x80 | ((code >> 12) & 0x3F));
        buf[2] = (char)(0x80 | ((code >> 6) & 0x3F));
        buf[3] = (char)(0x80 | (code & 0x3F));
        buf[4] = '\0';
    } else {
        buf = (char*)blink_alloc(2);
        buf[0] = '?';
        buf[1] = '\0';
    }
    return buf;
}

BLINK_UNUSED static const char* blink_str_concat(const char* a, const char* b) {
    int64_t la = blink_str_len(a);
    int64_t lb = blink_str_len(b);
    char* buf = (char*)blink_alloc(la + lb + 1);
    memcpy(buf, a, (size_t)la);
    memcpy(buf + la, b, (size_t)lb);
    buf[la + lb] = '\0';
    return buf;
}

BLINK_UNUSED static int blink_str_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}

BLINK_UNUSED static int blink_str_contains(const char* s, const char* needle) {
    return strstr(s, needle) != NULL;
}

BLINK_UNUSED static int blink_str_starts_with(const char* s, const char* prefix) {
    size_t plen = strlen(prefix);
    return strncmp(s, prefix, plen) == 0;
}

BLINK_UNUSED static int blink_str_ends_with(const char* s, const char* suffix) {
    size_t slen = strlen(s);
    size_t sufflen = strlen(suffix);
    if (sufflen > slen) return 0;
    return memcmp(s + slen - sufflen, suffix, sufflen) == 0;
}

BLINK_UNUSED static const char* blink_str_slice(const char* s, int64_t start, int64_t end) {
    int64_t slen = (int64_t)strlen(s);
    if (start < 0) start = 0;
    if (end > slen) end = slen;
    if (start >= end) return blink_strdup("");
    int64_t rlen = end - start;
    char* buf = (char*)blink_alloc(rlen + 1);
    memcpy(buf, s + start, (size_t)rlen);
    buf[rlen] = '\0';
    return buf;
}

BLINK_UNUSED static int64_t blink_str_index_of(const char* s, const char* needle) {
    if (!s || !needle) return -1;
    const char* found = strstr(s, needle);
    if (!found) return -1;
    return (int64_t)(found - s);
}

/* ── File I/O ───────────────────────────────────────────────────────── */

BLINK_UNUSED static const char* blink_read_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "blink: cannot open file: %s\n", path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)blink_alloc(size + 1);
    fread(buf, 1, (size_t)size, f);
    buf[size] = '\0';
    fclose(f);
    return buf;
}

BLINK_UNUSED static void blink_write_file(const char* path, const char* content) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "blink: cannot open file for writing: %s\n", path);
        exit(1);
    }
    size_t len = strlen(content);
    fwrite(content, 1, len, f);
    fclose(f);
}

BLINK_UNUSED static int blink_g_argc = 0;
BLINK_UNUSED static const char** blink_g_argv = NULL;

BLINK_UNUSED static int64_t blink_arg_count(void) {
    return (int64_t)blink_g_argc;
}

BLINK_UNUSED static const char* blink_get_arg(int64_t index) {
    if (index < 0 || index >= blink_g_argc) {
        fprintf(stderr, "blink: arg index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    return blink_g_argv[index];
}

BLINK_UNUSED static int64_t blink_file_exists(const char* path) {
    return access(path, F_OK) == 0 ? 1 : 0;
}

BLINK_UNUSED static int64_t blink_is_dir(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
}

BLINK_UNUSED static blink_list* blink_list_dir(const char* path) {
    blink_list* result = blink_list_new();
    DIR* d = opendir(path);
    if (!d) return result;
    struct dirent* entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.' && (entry->d_name[1] == '\0' ||
            (entry->d_name[1] == '.' && entry->d_name[2] == '\0'))) continue;
        blink_list_push(result, (void*)blink_strdup(entry->d_name));
    }
    closedir(d);
    return result;
}

BLINK_UNUSED static int64_t blink_file_mtime(const char* path) {
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

BLINK_UNUSED static int64_t blink_getpid(void) {
    return (int64_t)getpid();
}

BLINK_UNUSED static void blink_exit(int64_t code) { exit((int)code); }

BLINK_UNUSED static int64_t blink_shell_exec(const char* command) {
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

/* ── Type helpers ───────────────────────────────────────────────────── */

typedef struct {
    const char* message;
    const char* source_type;
    const char* target_type;
} blink_ConversionError;

typedef struct {
    void* fn_ptr;
    void** captures;
    int64_t capture_count;
} blink_closure;

BLINK_UNUSED static blink_closure* blink_closure_new(void* fn_ptr, void** captures, int64_t capture_count) {
    blink_closure* c = (blink_closure*)blink_alloc(sizeof(blink_closure));
    c->fn_ptr = fn_ptr;
    c->captures = captures;
    c->capture_count = capture_count;
    return c;
}

BLINK_UNUSED static void* blink_closure_get_fn(const blink_closure* c) {
    return c->fn_ptr;
}

BLINK_UNUSED static void* blink_closure_get_capture(const blink_closure* c, int64_t index) {
    if (index < 0 || index >= c->capture_count) {
        fprintf(stderr, "blink: closure capture index out of bounds: %lld\n", (long long)index);
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
 * Dispatch is via evidence passing: effectful functions receive
 * blink_ev* as a hidden first parameter so handlers can swap
 * implementations (testing, sandboxing, DI). Codegen resolves each
 * operation call through that evidence struct's vtable pointers.
 */

/* ── IO ─────────────────────────────────────────────────────────────── */
typedef struct {
    void  (*print)(const char* msg);
    void  (*print_no_nl)(const char* msg);
    void  (*log)(const char* msg);
    void  (*eprint)(const char* msg);
    void  (*eprint_no_nl)(const char* msg);
} blink_io_vtable;

BLINK_UNUSED static void blink_io_default_print(const char* msg) {
    printf("%s\n", msg);
}

BLINK_UNUSED static void blink_io_default_print_no_nl(const char* msg) {
    printf("%s", msg);
}

BLINK_UNUSED static void blink_io_default_log(const char* msg) {
    fprintf(stderr, "[LOG] %s\n", msg);
}

BLINK_UNUSED static void blink_io_default_eprint(const char* msg) {
    fprintf(stderr, "%s\n", msg);
}

BLINK_UNUSED static void blink_io_default_eprint_no_nl(const char* msg) {
    fprintf(stderr, "%s", msg);
}

BLINK_UNUSED static blink_io_vtable blink_io_vtable_default = {
    blink_io_default_print,
    blink_io_default_print_no_nl,
    blink_io_default_log,
    blink_io_default_eprint,
    blink_io_default_eprint_no_nl
};

/* ── FS ─────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* path);
    int         (*write)(const char* path, const char* content);
    int         (*delete_file)(const char* path);
    int         (*watch)(const char* path, void (*callback)(const char*));
} blink_fs_vtable;

BLINK_UNUSED static const char* blink_fs_default_read(const char* path) {
    return blink_read_file(path);
}

BLINK_UNUSED static int blink_fs_default_write(const char* path, const char* content) {
    blink_write_file(path, content);
    return 0;
}

BLINK_UNUSED static int blink_fs_default_delete(const char* path) {
    return remove(path);
}

BLINK_UNUSED static int blink_fs_default_watch(const char* path, void (*callback)(const char*)) {
    (void)path; (void)callback;
    fprintf(stderr, "blink: fs.watch not implemented\n");
    return -1;
}

BLINK_UNUSED static blink_fs_vtable blink_fs_vtable_default = {
    blink_fs_default_read,
    blink_fs_default_write,
    blink_fs_default_delete,
    blink_fs_default_watch
};

/* ── Net ────────────────────────────────────────────────────────────── */
typedef struct {
    int (*connect)(const char* url);
    int (*listen)(const char* addr, int port);
    const char* (*dns)(const char* hostname);
} blink_net_vtable;

BLINK_UNUSED static int blink_net_default_connect(const char* url) {
    (void)url;
    fprintf(stderr, "blink: net.connect not implemented\n");
    return -1;
}

BLINK_UNUSED static int blink_net_default_listen(const char* addr, int port) {
    (void)addr; (void)port;
    fprintf(stderr, "blink: net.listen not implemented\n");
    return -1;
}

BLINK_UNUSED static const char* blink_net_default_dns(const char* hostname) {
    (void)hostname;
    fprintf(stderr, "blink: net.dns not implemented\n");
    return NULL;
}

BLINK_UNUSED static blink_net_vtable blink_net_vtable_default = {
    blink_net_default_connect,
    blink_net_default_listen,
    blink_net_default_dns
};

/* ── Crypto ─────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*hash)(const char* data);
    const char* (*sign)(const char* data, const char* key);
    const char* (*encrypt)(const char* data, const char* key);
    const char* (*decrypt)(const char* data, const char* key);
} blink_crypto_vtable;

BLINK_UNUSED static const char* blink_crypto_default_hash(const char* data) {
    (void)data;
    fprintf(stderr, "blink: crypto.hash not implemented\n");
    return NULL;
}

BLINK_UNUSED static const char* blink_crypto_default_sign(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.sign not implemented\n");
    return NULL;
}

BLINK_UNUSED static const char* blink_crypto_default_encrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.encrypt not implemented\n");
    return NULL;
}

BLINK_UNUSED static const char* blink_crypto_default_decrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.decrypt not implemented\n");
    return NULL;
}

BLINK_UNUSED static blink_crypto_vtable blink_crypto_vtable_default = {
    blink_crypto_default_hash,
    blink_crypto_default_sign,
    blink_crypto_default_encrypt,
    blink_crypto_default_decrypt
};

/* ── Rand ───────────────────────────────────────────────────────────── */
typedef struct {
    int64_t (*rand_int)(int64_t min, int64_t max);
    double  (*rand_float)(void);
    void    (*rand_bytes)(void* buf, int64_t len);
} blink_rand_vtable;

BLINK_UNUSED static int blink_rand_seeded = 0;

BLINK_UNUSED static void blink_rand_ensure_seed(void) {
    if (!blink_rand_seeded) {
        srand((unsigned)42);
        blink_rand_seeded = 1;
    }
}

BLINK_UNUSED static int64_t blink_rand_default_int(int64_t min, int64_t max) {
    blink_rand_ensure_seed();
    if (min >= max) return min;
    return min + (int64_t)(rand() % (int)(max - min));
}

BLINK_UNUSED static double blink_rand_default_float(void) {
    blink_rand_ensure_seed();
    return (double)rand() / (double)RAND_MAX;
}

BLINK_UNUSED static void blink_rand_default_bytes(void* buf, int64_t len) {
    blink_rand_ensure_seed();
    unsigned char* p = (unsigned char*)buf;
    for (int64_t i = 0; i < len; i++) {
        p[i] = (unsigned char)(rand() & 0xFF);
    }
}

BLINK_UNUSED static blink_rand_vtable blink_rand_vtable_default = {
    blink_rand_default_int,
    blink_rand_default_float,
    blink_rand_default_bytes
};

/* ── Duration / Instant runtime helpers ─────────────────────────────── */
/* blink_Duration / blink_Instant are defined by Blink (lib/std/time.bl).
   runtime_core.h uses _struct variants to avoid duplicate typedef conflicts. */

typedef struct { int64_t nanos; } blink_duration_struct;
typedef struct { int64_t nanos; } blink_instant_struct;

BLINK_UNUSED static const char* blink_Instant_to_rfc3339(blink_instant_struct i) {
    time_t epoch_secs = (time_t)(i.nanos / 1000000000LL);
    struct tm utc;
    gmtime_r(&epoch_secs, &utc);
    char* buf = (char*)blink_alloc(64);
    snprintf(buf, 64, "%04d-%02d-%02dT%02d:%02d:%02dZ",
             utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday,
             utc.tm_hour, utc.tm_min, utc.tm_sec);
    return buf;
}

BLINK_UNUSED static blink_duration_struct blink_Instant_elapsed(blink_instant_struct then) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t now_nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
    return (blink_duration_struct){.nanos = now_nanos - then.nanos};
}

/* ── Time ───────────────────────────────────────────────────────────── */
typedef struct {
    blink_instant_struct (*read)(void);
    void                (*sleep)(blink_duration_struct d);
} blink_time_vtable;

BLINK_UNUSED static blink_instant_struct blink_time_default_read(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (blink_instant_struct){.nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec};
}

BLINK_UNUSED static void blink_time_default_sleep(blink_duration_struct d) {
    int64_t ns = d.nanos;
    struct timespec ts;
    ts.tv_sec  = (time_t)(ns / 1000000000LL);
    ts.tv_nsec = (long)(ns % 1000000000LL);
    nanosleep(&ts, NULL);
}

BLINK_UNUSED static blink_time_vtable blink_time_vtable_default = {
    blink_time_default_read,
    blink_time_default_sleep
};

BLINK_UNUSED static int64_t blink_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

/* ── Env ────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* name);
    int         (*write)(const char* name, const char* value);
    int         (*remove)(const char* name);
    const char* (*cwd)(void);
    void        (*exit_fn)(int code);
} blink_env_vtable;

BLINK_UNUSED static const char* blink_env_default_read(const char* name) {
    const char* v = getenv(name);
    return v ? blink_strdup(v) : NULL;
}

BLINK_UNUSED static int blink_env_default_write(const char* name, const char* value) {
    return setenv(name, value, 1);
}

BLINK_UNUSED static int blink_env_default_remove(const char* name) {
    return unsetenv(name);
}

BLINK_UNUSED static const char* blink_env_default_cwd(void) {
    char buf[4096];
    char* r = getcwd(buf, sizeof(buf));
    if (!r) { fprintf(stderr, "blink: getcwd failed, falling back to \".\"\n"); }
    return r ? blink_strdup(r) : blink_strdup(".");
}

BLINK_UNUSED static void blink_env_default_exit(int code) {
    exit(code);
}

BLINK_UNUSED static blink_env_vtable blink_env_vtable_default = {
    blink_env_default_read,
    blink_env_default_write,
    blink_env_default_remove,
    blink_env_default_cwd,
    blink_env_default_exit
};

/* ── Process ────────────────────────────────────────────────────────── */
typedef struct {
    int64_t (*spawn)(const char* command);
    int     (*signal)(int64_t pid, int sig);
} blink_process_vtable;

BLINK_UNUSED static int64_t blink_process_default_spawn(const char* command) {
    (void)command;
    fprintf(stderr, "blink: process.spawn not implemented\n");
    return -1;
}

BLINK_UNUSED static int blink_process_default_signal(int64_t pid, int sig) {
    (void)pid; (void)sig;
    fprintf(stderr, "blink: process.signal not implemented\n");
    return -1;
}

BLINK_UNUSED static blink_process_vtable blink_process_vtable_default = {
    blink_process_default_spawn,
    blink_process_default_signal
};

/* ── Debug assert ───────────────────────────────────────────────────── */

BLINK_UNUSED static void __blink_debug_assert_fail(const char* file, int line, const char* fn, const char* cond, const char* msg) {
    fprintf(stderr, "DEBUG ASSERT FAILED: %s\n", msg);
    fprintf(stderr, "  condition: %s\n", cond);
    fprintf(stderr, "  location: %s:%d in %s\n", file, line, fn);
    exit(1);
}

/* ── FFI scope helpers ─────────────────────────────────────────────── */

BLINK_UNUSED static blink_list* blink_ffi_scope_new(void) {
    return blink_list_new();
}

BLINK_UNUSED static void* blink_ffi_scope_track(blink_list* scope, void* ptr) {
    blink_list_push(scope, ptr);
    return ptr;
}

BLINK_UNUSED static void* blink_ffi_scope_take(blink_list* scope, void* ptr) {
    for (int64_t i = 0; i < scope->len; i++) {
        if (scope->items[i] == ptr) {
            for (int64_t j = i; j < scope->len - 1; j++) {
                scope->items[j] = scope->items[j + 1];
            }
            scope->len--;
            return ptr;
        }
    }
    return ptr;
}

BLINK_UNUSED static void blink_ffi_scope_cleanup(blink_list* scope) {
    for (int64_t i = 0; i < scope->len; i++) {
        GC_FREE(scope->items[i]);
    }
    GC_FREE(scope->items);
    GC_FREE(scope);
}

#endif
