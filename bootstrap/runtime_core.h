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

BLINK_UNUSED static void* pact_alloc(int64_t size) {
    void* p = GC_MALLOC((size_t)size);
    if (!p) {
        fprintf(stderr, "blink: out of memory\n");
        exit(1);
    }
    return p;
}

BLINK_UNUSED static char* pact_strdup(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char* p = (char*)GC_MALLOC_ATOMIC(len);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    memcpy(p, s, len);
    return p;
}

typedef struct {
    void** items;
    int64_t len;
    int64_t cap;
} pact_list;

BLINK_UNUSED static pact_list* pact_list_new(void) {
    pact_list* l = (pact_list*)pact_alloc(sizeof(pact_list));
    l->cap = 8;
    l->len = 0;
    l->items = (void**)pact_alloc(sizeof(void*) * l->cap);
    return l;
}

BLINK_UNUSED static void pact_list_push(pact_list* l, void* item) {
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

BLINK_UNUSED static void* pact_list_get(const pact_list* l, int64_t index) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "blink: list index out of bounds: idx=%lld len=%lld\n", (long long)index, (long long)l->len);
        exit(1);
    }
    return l->items[index];
}

BLINK_UNUSED static int pact_list_in_bounds(const pact_list* l, int64_t index) {
    return (index >= 0 && index < l->len);
}

BLINK_UNUSED static int64_t pact_list_len(const pact_list* l) {
    return l->len;
}

BLINK_UNUSED static void pact_list_set(pact_list* l, int64_t index, void* item) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "blink: list set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    l->items[index] = item;
}

BLINK_UNUSED static void* pact_list_pop(pact_list* l) {
    if (l->len <= 0) {
        fprintf(stderr, "blink: list pop on empty list\n");
        exit(1);
    }
    l->len--;
    return l->items[l->len];
}

BLINK_UNUSED static void pact_list_free(pact_list* l) {
    if (l) {
        GC_FREE(l->items);
        GC_FREE(l);
    }
}

BLINK_UNUSED static void pact_list_clear(pact_list* l) {
    l->len = 0;
}

BLINK_UNUSED static pact_list* pact_list_concat(pact_list* a, pact_list* b) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < a->len; i++) pact_list_push(result, a->items[i]);
    for (int64_t i = 0; i < b->len; i++) pact_list_push(result, b->items[i]);
    return result;
}

BLINK_UNUSED static pact_list* pact_list_slice(pact_list* l, int64_t start, int64_t end) {
    pact_list* result = pact_list_new();
    if (start < 0) start = 0;
    if (end > l->len) end = l->len;
    for (int64_t i = start; i < end; i++) pact_list_push(result, l->items[i]);
    return result;
}

/* ── Hash map (string-keyed) ────────────────────────────────────────── */

BLINK_UNUSED static int pact_str_eq(const char* a, const char* b);

BLINK_UNUSED static uint64_t pact_map_hash(const char* key) {
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

BLINK_UNUSED static pact_map* pact_map_new(void) {
    pact_map* m = (pact_map*)pact_alloc(sizeof(pact_map));
    m->cap = 16;
    m->len = 0;
    m->keys = (const char**)pact_alloc(sizeof(const char*) * (size_t)m->cap);
    m->values = (void**)pact_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)pact_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    return m;
}

BLINK_UNUSED static void pact_map_grow(pact_map* m) {
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
    GC_FREE(old_keys);
    GC_FREE(old_values);
    GC_FREE(old_states);
}

BLINK_UNUSED static void pact_map_set(pact_map* m, const char* key, void* value) {
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

BLINK_UNUSED static void* pact_map_get(const pact_map* m, const char* key) {
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

BLINK_UNUSED static int64_t pact_map_has(const pact_map* m, const char* key) {
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

BLINK_UNUSED static int64_t pact_map_remove(pact_map* m, const char* key) {
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

BLINK_UNUSED static int64_t pact_map_len(const pact_map* m) {
    return m->len;
}

BLINK_UNUSED static pact_list* pact_map_keys(const pact_map* m) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            pact_list_push(result, (void*)m->keys[i]);
        }
    }
    return result;
}

BLINK_UNUSED static pact_list* pact_map_values(const pact_map* m) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            pact_list_push(result, m->values[i]);
        }
    }
    return result;
}

BLINK_UNUSED static void pact_map_free(pact_map* m) {
    if (m) {
        GC_FREE(m->keys);
        GC_FREE(m->values);
        GC_FREE(m->states);
        GC_FREE(m);
    }
}

BLINK_UNUSED static void pact_map_clear(pact_map* m) {
    m->len = 0;
    memset(m->states, 0, sizeof(uint8_t) * (size_t)m->cap);
}

/* ── Hash set (string-keyed) ─────────────────────────────────────────── */

typedef struct {
    const char** items;
    uint8_t* states;   /* 0=empty, 1=occupied, 2=tombstone */
    int64_t len;
    int64_t cap;
} pact_set;

BLINK_UNUSED static const char* pact_int_to_key(int64_t val) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)val);
    size_t len = strlen(buf);
    char* s = (char*)pact_alloc(len + 1);
    memcpy(s, buf, len + 1);
    return s;
}

BLINK_UNUSED static pact_set* pact_set_new(void) {
    pact_set* s = (pact_set*)pact_alloc(sizeof(pact_set));
    s->cap = 16;
    s->len = 0;
    s->items = (const char**)pact_alloc(sizeof(const char*) * (size_t)s->cap);
    s->states = (uint8_t*)pact_alloc(sizeof(uint8_t) * (size_t)s->cap);
    memset(s->states, 0, (size_t)s->cap);
    return s;
}

BLINK_UNUSED static void pact_set_grow(pact_set* s) {
    int64_t old_cap = s->cap;
    const char** old_items = s->items;
    uint8_t* old_states = s->states;
    s->cap = old_cap * 2;
    s->items = (const char**)pact_alloc(sizeof(const char*) * (size_t)s->cap);
    s->states = (uint8_t*)pact_alloc(sizeof(uint8_t) * (size_t)s->cap);
    memset(s->states, 0, (size_t)s->cap);
    s->len = 0;
    for (int64_t i = 0; i < old_cap; i++) {
        if (old_states[i] == 1) {
            uint64_t h = pact_map_hash(old_items[i]);
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

BLINK_UNUSED static int64_t pact_set_insert(pact_set* s, const char* item) {
    if (s->len * 10 >= s->cap * 7) {
        pact_set_grow(s);
    }
    uint64_t h = pact_map_hash(item);
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
        } else if (pact_str_eq(s->items[idx], item)) {
            return 0;
        }
        idx = (idx + 1) % s->cap;
    }
}

BLINK_UNUSED static int64_t pact_set_contains(const pact_set* s, const char* item) {
    uint64_t h = pact_map_hash(item);
    int64_t idx = (int64_t)(h % (uint64_t)s->cap);
    while (s->states[idx] != 0) {
        if (s->states[idx] == 1 && pact_str_eq(s->items[idx], item)) {
            return 1;
        }
        idx = (idx + 1) % s->cap;
    }
    return 0;
}

BLINK_UNUSED static int64_t pact_set_remove(pact_set* s, const char* item) {
    uint64_t h = pact_map_hash(item);
    int64_t idx = (int64_t)(h % (uint64_t)s->cap);
    while (s->states[idx] != 0) {
        if (s->states[idx] == 1 && pact_str_eq(s->items[idx], item)) {
            s->states[idx] = 2;
            s->len--;
            return 1;
        }
        idx = (idx + 1) % s->cap;
    }
    return 0;
}

BLINK_UNUSED static int64_t pact_set_len(const pact_set* s) {
    return s->len;
}

BLINK_UNUSED static pact_set* pact_set_union(const pact_set* a, const pact_set* b) {
    pact_set* result = pact_set_new();
    for (int64_t i = 0; i < a->cap; i++) {
        if (a->states[i] == 1) {
            pact_set_insert(result, a->items[i]);
        }
    }
    for (int64_t i = 0; i < b->cap; i++) {
        if (b->states[i] == 1) {
            pact_set_insert(result, b->items[i]);
        }
    }
    return result;
}

BLINK_UNUSED static pact_list* pact_set_to_list(const pact_set* s) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < s->cap; i++) {
        if (s->states[i] == 1) {
            pact_list_push(result, (void*)s->items[i]);
        }
    }
    return result;
}

BLINK_UNUSED static void pact_set_free(pact_set* s) {
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
} pact_bytes;

BLINK_UNUSED static pact_bytes* pact_bytes_new(void) {
    pact_bytes* b = (pact_bytes*)pact_alloc(sizeof(pact_bytes));
    b->cap = 16;
    b->len = 0;
    b->data = (uint8_t*)pact_alloc((size_t)b->cap);
    return b;
}

BLINK_UNUSED static void pact_bytes_push(pact_bytes* b, int64_t byte) {
    if (b->len >= b->cap) {
        b->cap *= 2;
        b->data = (uint8_t*)GC_REALLOC(b->data, (size_t)b->cap);
        if (!b->data) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    }
    b->data[b->len++] = (uint8_t)(byte & 0xFF);
}

BLINK_UNUSED static int64_t pact_bytes_get(const pact_bytes* b, int64_t index) {
    if (index < 0 || index >= b->len) return -1;
    return (int64_t)b->data[index];
}

BLINK_UNUSED static void pact_bytes_set(pact_bytes* b, int64_t index, int64_t byte) {
    if (index < 0 || index >= b->len) {
        fprintf(stderr, "blink: bytes set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    b->data[index] = (uint8_t)(byte & 0xFF);
}

BLINK_UNUSED static int64_t pact_bytes_len(const pact_bytes* b) {
    return b->len;
}

BLINK_UNUSED static int64_t pact_bytes_is_empty(const pact_bytes* b) {
    return b->len == 0;
}

BLINK_UNUSED static pact_bytes* pact_bytes_concat(const pact_bytes* a, const pact_bytes* b) {
    pact_bytes* r = pact_bytes_new();
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

BLINK_UNUSED static pact_bytes* pact_bytes_slice(const pact_bytes* b, int64_t start, int64_t end) {
    if (start < 0) start = 0;
    if (end > b->len) end = b->len;
    if (start > end) start = end;
    pact_bytes* r = pact_bytes_new();
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

BLINK_UNUSED static int pact_bytes_to_str_checked(const pact_bytes* b, const char** out) {
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

BLINK_UNUSED static const char* pact_bytes_to_hex(const pact_bytes* b) {
    char* hex = (char*)pact_alloc(b->len * 2 + 1);
    for (int64_t i = 0; i < b->len; i++) {
        sprintf(hex + i * 2, "%02x", b->data[i]);
    }
    hex[b->len * 2] = '\0';
    return hex;
}

BLINK_UNUSED static pact_bytes* pact_bytes_from_str(const char* s) {
    pact_bytes* b = pact_bytes_new();
    int64_t slen = (int64_t)strlen(s);
    if (slen > b->cap) {
        b->cap = slen;
        b->data = (uint8_t*)GC_REALLOC(b->data, (size_t)b->cap);
    }
    memcpy(b->data, s, (size_t)slen);
    b->len = slen;
    return b;
}

BLINK_UNUSED static void pact_bytes_free(pact_bytes* b) {
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
} pact_sb;

BLINK_UNUSED static pact_sb* pact_sb_new(void) {
    pact_sb* sb = (pact_sb*)pact_alloc(sizeof(pact_sb));
    sb->cap = 64;
    sb->len = 0;
    sb->data = (char*)pact_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}

BLINK_UNUSED static pact_sb* pact_sb_with_capacity(int64_t cap) {
    if (cap < 16) cap = 16;
    pact_sb* sb = (pact_sb*)pact_alloc(sizeof(pact_sb));
    sb->cap = cap;
    sb->len = 0;
    sb->data = (char*)pact_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}

BLINK_UNUSED static void pact_sb_write_n(pact_sb* sb, const char* s, int64_t slen) {
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

BLINK_UNUSED static void pact_sb_write(pact_sb* sb, const char* s) {
    pact_sb_write_n(sb, s, (int64_t)strlen(s));
}

BLINK_UNUSED static void pact_sb_write_char(pact_sb* sb, const char* ch) {
    pact_sb_write(sb, ch);
}

BLINK_UNUSED static void pact_sb_write_int(pact_sb* sb, int64_t val) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)val);
    pact_sb_write_n(sb, buf, (int64_t)len);
}

BLINK_UNUSED static void pact_sb_write_float(pact_sb* sb, double val) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%g", val);
    pact_sb_write_n(sb, buf, (int64_t)len);
}

BLINK_UNUSED static void pact_sb_write_bool(pact_sb* sb, int val) {
    pact_sb_write(sb, val ? "true" : "false");
}

BLINK_UNUSED static const char* pact_sb_to_str(const pact_sb* sb) {
    return pact_strdup(sb->data);
}

BLINK_UNUSED static int64_t pact_sb_len(const pact_sb* sb) {
    return sb->len;
}

BLINK_UNUSED static int64_t pact_sb_capacity(const pact_sb* sb) {
    return sb->cap;
}

BLINK_UNUSED static void pact_sb_clear(pact_sb* sb) {
    sb->len = 0;
    sb->data[0] = '\0';
}

BLINK_UNUSED static int pact_sb_is_empty(const pact_sb* sb) {
    return sb->len == 0;
}

BLINK_UNUSED static void pact_sb_free(pact_sb* sb) {
    if (sb) {
        GC_FREE(sb->data);
        GC_FREE(sb);
    }
}

/* ── String operations ──────────────────────────────────────────────── */

BLINK_UNUSED static int64_t pact_str_len(const char* s) {
    return (int64_t)strlen(s);
}

BLINK_UNUSED static int64_t pact_str_char_at(const char* s, int64_t i) {
    return (int64_t)(unsigned char)s[i];
}

BLINK_UNUSED static const char* pact_str_substr(const char* s, int64_t start, int64_t len) {
    char* buf = (char*)pact_alloc(len + 1);
    memcpy(buf, s + start, (size_t)len);
    buf[len] = '\0';
    return buf;
}

BLINK_UNUSED static const char* pact_str_from_char_code(int64_t code) {
    char* buf;
    if (code < 0x80) {
        buf = (char*)pact_alloc(2);
        buf[0] = (char)code;
        buf[1] = '\0';
    } else if (code < 0x800) {
        buf = (char*)pact_alloc(3);
        buf[0] = (char)(0xC0 | (code >> 6));
        buf[1] = (char)(0x80 | (code & 0x3F));
        buf[2] = '\0';
    } else if (code < 0x10000) {
        buf = (char*)pact_alloc(4);
        buf[0] = (char)(0xE0 | (code >> 12));
        buf[1] = (char)(0x80 | ((code >> 6) & 0x3F));
        buf[2] = (char)(0x80 | (code & 0x3F));
        buf[3] = '\0';
    } else if (code <= 0x10FFFF) {
        buf = (char*)pact_alloc(5);
        buf[0] = (char)(0xF0 | (code >> 18));
        buf[1] = (char)(0x80 | ((code >> 12) & 0x3F));
        buf[2] = (char)(0x80 | ((code >> 6) & 0x3F));
        buf[3] = (char)(0x80 | (code & 0x3F));
        buf[4] = '\0';
    } else {
        buf = (char*)pact_alloc(2);
        buf[0] = '?';
        buf[1] = '\0';
    }
    return buf;
}

BLINK_UNUSED static const char* pact_str_concat(const char* a, const char* b) {
    int64_t la = pact_str_len(a);
    int64_t lb = pact_str_len(b);
    char* buf = (char*)pact_alloc(la + lb + 1);
    memcpy(buf, a, (size_t)la);
    memcpy(buf + la, b, (size_t)lb);
    buf[la + lb] = '\0';
    return buf;
}

BLINK_UNUSED static int pact_str_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}

BLINK_UNUSED static int pact_str_contains(const char* s, const char* needle) {
    return strstr(s, needle) != NULL;
}

BLINK_UNUSED static int pact_str_starts_with(const char* s, const char* prefix) {
    size_t plen = strlen(prefix);
    return strncmp(s, prefix, plen) == 0;
}

BLINK_UNUSED static int pact_str_ends_with(const char* s, const char* suffix) {
    size_t slen = strlen(s);
    size_t sufflen = strlen(suffix);
    if (sufflen > slen) return 0;
    return memcmp(s + slen - sufflen, suffix, sufflen) == 0;
}

BLINK_UNUSED static const char* pact_str_slice(const char* s, int64_t start, int64_t end) {
    int64_t slen = (int64_t)strlen(s);
    if (start < 0) start = 0;
    if (end > slen) end = slen;
    if (start >= end) return pact_strdup("");
    int64_t rlen = end - start;
    char* buf = (char*)pact_alloc(rlen + 1);
    memcpy(buf, s + start, (size_t)rlen);
    buf[rlen] = '\0';
    return buf;
}

BLINK_UNUSED static int64_t pact_str_index_of(const char* s, const char* needle) {
    if (!s || !needle) return -1;
    const char* found = strstr(s, needle);
    if (!found) return -1;
    return (int64_t)(found - s);
}

/* ── File I/O ───────────────────────────────────────────────────────── */

BLINK_UNUSED static const char* pact_read_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "blink: cannot open file: %s\n", path);
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

BLINK_UNUSED static void pact_write_file(const char* path, const char* content) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "blink: cannot open file for writing: %s\n", path);
        exit(1);
    }
    size_t len = strlen(content);
    fwrite(content, 1, len, f);
    fclose(f);
}

BLINK_UNUSED static int pact_g_argc = 0;
BLINK_UNUSED static const char** pact_g_argv = NULL;

BLINK_UNUSED static int64_t pact_arg_count(void) {
    return (int64_t)pact_g_argc;
}

BLINK_UNUSED static const char* pact_get_arg(int64_t index) {
    if (index < 0 || index >= pact_g_argc) {
        fprintf(stderr, "blink: arg index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    return pact_g_argv[index];
}

BLINK_UNUSED static int64_t pact_file_exists(const char* path) {
    return access(path, F_OK) == 0 ? 1 : 0;
}

BLINK_UNUSED static int64_t pact_is_dir(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
}

BLINK_UNUSED static pact_list* pact_list_dir(const char* path) {
    pact_list* result = pact_list_new();
    DIR* d = opendir(path);
    if (!d) return result;
    struct dirent* entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.' && (entry->d_name[1] == '\0' ||
            (entry->d_name[1] == '.' && entry->d_name[2] == '\0'))) continue;
        pact_list_push(result, (void*)pact_strdup(entry->d_name));
    }
    closedir(d);
    return result;
}

BLINK_UNUSED static int64_t pact_file_mtime(const char* path) {
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

BLINK_UNUSED static int64_t pact_getpid(void) {
    return (int64_t)getpid();
}

BLINK_UNUSED static void pact_exit(int64_t code) { exit((int)code); }

BLINK_UNUSED static int64_t pact_shell_exec(const char* command) {
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
} pact_ConversionError;

typedef struct {
    void* fn_ptr;
    void** captures;
    int64_t capture_count;
} pact_closure;

BLINK_UNUSED static pact_closure* pact_closure_new(void* fn_ptr, void** captures, int64_t capture_count) {
    pact_closure* c = (pact_closure*)pact_alloc(sizeof(pact_closure));
    c->fn_ptr = fn_ptr;
    c->captures = captures;
    c->capture_count = capture_count;
    return c;
}

BLINK_UNUSED static void* pact_closure_get_fn(const pact_closure* c) {
    return c->fn_ptr;
}

BLINK_UNUSED static void* pact_closure_get_capture(const pact_closure* c, int64_t index) {
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
 * pact_ctx holds one pointer per effect vtable.  Effectful functions
 * receive pact_ctx* as their first parameter so handlers can swap
 * implementations (testing, sandboxing, DI).
 */

/* ── IO ─────────────────────────────────────────────────────────────── */
typedef struct {
    void  (*print)(const char* msg);
    void  (*print_no_nl)(const char* msg);
    void  (*log)(const char* msg);
} pact_io_vtable;

BLINK_UNUSED static void pact_io_default_print(const char* msg) {
    printf("%s\n", msg);
}

BLINK_UNUSED static void pact_io_default_print_no_nl(const char* msg) {
    printf("%s", msg);
}

BLINK_UNUSED static void pact_io_default_log(const char* msg) {
    fprintf(stderr, "[LOG] %s\n", msg);
}

BLINK_UNUSED static pact_io_vtable pact_io_vtable_default = {
    pact_io_default_print,
    pact_io_default_print_no_nl,
    pact_io_default_log
};

/* ── FS ─────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* path);
    int         (*write)(const char* path, const char* content);
    int         (*delete_file)(const char* path);
    int         (*watch)(const char* path, void (*callback)(const char*));
} pact_fs_vtable;

BLINK_UNUSED static const char* pact_fs_default_read(const char* path) {
    return pact_read_file(path);
}

BLINK_UNUSED static int pact_fs_default_write(const char* path, const char* content) {
    pact_write_file(path, content);
    return 0;
}

BLINK_UNUSED static int pact_fs_default_delete(const char* path) {
    return remove(path);
}

BLINK_UNUSED static int pact_fs_default_watch(const char* path, void (*callback)(const char*)) {
    (void)path; (void)callback;
    fprintf(stderr, "blink: fs.watch not implemented\n");
    return -1;
}

BLINK_UNUSED static pact_fs_vtable pact_fs_vtable_default = {
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

BLINK_UNUSED static int pact_net_default_connect(const char* url) {
    (void)url;
    fprintf(stderr, "blink: net.connect not implemented\n");
    return -1;
}

BLINK_UNUSED static int pact_net_default_listen(const char* addr, int port) {
    (void)addr; (void)port;
    fprintf(stderr, "blink: net.listen not implemented\n");
    return -1;
}

BLINK_UNUSED static const char* pact_net_default_dns(const char* hostname) {
    (void)hostname;
    fprintf(stderr, "blink: net.dns not implemented\n");
    return NULL;
}

BLINK_UNUSED static pact_net_vtable pact_net_vtable_default = {
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

BLINK_UNUSED static const char* pact_db_default_read(const char* query) {
    (void)query;
    fprintf(stderr, "blink: db.read not implemented\n");
    return NULL;
}

BLINK_UNUSED static int pact_db_default_write(const char* query) {
    (void)query;
    fprintf(stderr, "blink: db.write not implemented\n");
    return -1;
}

BLINK_UNUSED static int pact_db_default_admin(const char* query) {
    (void)query;
    fprintf(stderr, "blink: db.admin not implemented\n");
    return -1;
}

BLINK_UNUSED static pact_db_vtable pact_db_vtable_default = {
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

BLINK_UNUSED static const char* pact_crypto_default_hash(const char* data) {
    (void)data;
    fprintf(stderr, "blink: crypto.hash not implemented\n");
    return NULL;
}

BLINK_UNUSED static const char* pact_crypto_default_sign(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.sign not implemented\n");
    return NULL;
}

BLINK_UNUSED static const char* pact_crypto_default_encrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.encrypt not implemented\n");
    return NULL;
}

BLINK_UNUSED static const char* pact_crypto_default_decrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.decrypt not implemented\n");
    return NULL;
}

BLINK_UNUSED static pact_crypto_vtable pact_crypto_vtable_default = {
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

BLINK_UNUSED static int pact_rand_seeded = 0;

BLINK_UNUSED static void pact_rand_ensure_seed(void) {
    if (!pact_rand_seeded) {
        srand((unsigned)42);
        pact_rand_seeded = 1;
    }
}

BLINK_UNUSED static int64_t pact_rand_default_int(int64_t min, int64_t max) {
    pact_rand_ensure_seed();
    if (min >= max) return min;
    return min + (int64_t)(rand() % (int)(max - min));
}

BLINK_UNUSED static double pact_rand_default_float(void) {
    pact_rand_ensure_seed();
    return (double)rand() / (double)RAND_MAX;
}

BLINK_UNUSED static void pact_rand_default_bytes(void* buf, int64_t len) {
    pact_rand_ensure_seed();
    unsigned char* p = (unsigned char*)buf;
    for (int64_t i = 0; i < len; i++) {
        p[i] = (unsigned char)(rand() & 0xFF);
    }
}

BLINK_UNUSED static pact_rand_vtable pact_rand_vtable_default = {
    pact_rand_default_int,
    pact_rand_default_float,
    pact_rand_default_bytes
};

/* ── Duration / Instant runtime helpers ─────────────────────────────── */
/* pact_Duration / pact_Instant are defined by Pact (lib/std/time.pact).
   runtime_core.h uses _struct variants to avoid duplicate typedef conflicts. */

typedef struct { int64_t nanos; } pact_duration_struct;
typedef struct { int64_t nanos; } pact_instant_struct;

BLINK_UNUSED static const char* pact_Instant_to_rfc3339(pact_instant_struct i) {
    time_t epoch_secs = (time_t)(i.nanos / 1000000000LL);
    struct tm utc;
    gmtime_r(&epoch_secs, &utc);
    char* buf = (char*)pact_alloc(32);
    snprintf(buf, 32, "%04d-%02d-%02dT%02d:%02d:%02dZ",
             utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday,
             utc.tm_hour, utc.tm_min, utc.tm_sec);
    return buf;
}

BLINK_UNUSED static pact_duration_struct pact_Instant_elapsed(pact_instant_struct then) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t now_nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
    return (pact_duration_struct){.nanos = now_nanos - then.nanos};
}

/* ── Time ───────────────────────────────────────────────────────────── */
typedef struct {
    pact_instant_struct (*read)(void);
    void                (*sleep)(pact_duration_struct d);
} pact_time_vtable;

BLINK_UNUSED static pact_instant_struct pact_time_default_read(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (pact_instant_struct){.nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec};
}

BLINK_UNUSED static void pact_time_default_sleep(pact_duration_struct d) {
    int64_t ns = d.nanos;
    struct timespec ts;
    ts.tv_sec  = (time_t)(ns / 1000000000LL);
    ts.tv_nsec = (long)(ns % 1000000000LL);
    nanosleep(&ts, NULL);
}

BLINK_UNUSED static pact_time_vtable pact_time_vtable_default = {
    pact_time_default_read,
    pact_time_default_sleep
};

BLINK_UNUSED static int64_t pact_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

/* ── Env ────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* name);
    int         (*write)(const char* name, const char* value);
} pact_env_vtable;

BLINK_UNUSED static const char* pact_env_default_read(const char* name) {
    const char* v = getenv(name);
    return v ? pact_strdup(v) : NULL;
}

BLINK_UNUSED static int pact_env_default_write(const char* name, const char* value) {
    return setenv(name, value, 1);
}

BLINK_UNUSED static pact_env_vtable pact_env_vtable_default = {
    pact_env_default_read,
    pact_env_default_write
};

/* ── Process ────────────────────────────────────────────────────────── */
typedef struct {
    int64_t (*spawn)(const char* command);
    int     (*signal)(int64_t pid, int sig);
} pact_process_vtable;

BLINK_UNUSED static int64_t pact_process_default_spawn(const char* command) {
    (void)command;
    fprintf(stderr, "blink: process.spawn not implemented\n");
    return -1;
}

BLINK_UNUSED static int pact_process_default_signal(int64_t pid, int sig) {
    (void)pid; (void)sig;
    fprintf(stderr, "blink: process.signal not implemented\n");
    return -1;
}

BLINK_UNUSED static pact_process_vtable pact_process_vtable_default = {
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

BLINK_UNUSED static pact_ctx pact_ctx_default(void) {
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

/* ── Debug assert ───────────────────────────────────────────────────── */

BLINK_UNUSED static void __pact_debug_assert_fail(const char* file, int line, const char* fn, const char* cond, const char* msg) {
    fprintf(stderr, "DEBUG ASSERT FAILED: %s\n", msg);
    fprintf(stderr, "  condition: %s\n", cond);
    fprintf(stderr, "  location: %s:%d in %s\n", file, line, fn);
    exit(1);
}

/* ── FFI scope helpers ─────────────────────────────────────────────── */

BLINK_UNUSED static pact_list* pact_ffi_scope_new(void) {
    return pact_list_new();
}

BLINK_UNUSED static void* pact_ffi_scope_track(pact_list* scope, void* ptr) {
    pact_list_push(scope, ptr);
    return ptr;
}

BLINK_UNUSED static void* pact_ffi_scope_take(pact_list* scope, void* ptr) {
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

BLINK_UNUSED static void pact_ffi_scope_cleanup(pact_list* scope) {
    for (int64_t i = 0; i < scope->len; i++) {
        GC_FREE(scope->items[i]);
    }
    GC_FREE(scope->items);
    GC_FREE(scope);
}

#endif
