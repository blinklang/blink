#ifndef PACT_RUNTIME_CORE_H
#define PACT_RUNTIME_CORE_H

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

#ifdef __GNUC__
#define PACT_UNUSED __attribute__((unused))
#else
#define PACT_UNUSED
#endif

PACT_UNUSED static const char* pact_int_to_str(int64_t n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)n);
    return strdup(buf);
}

PACT_UNUSED static const char* pact_float_to_str(double d) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%g", d);
    return strdup(buf);
}

PACT_UNUSED static void* pact_alloc(int64_t size) {
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

PACT_UNUSED static pact_list* pact_list_new(void) {
    pact_list* l = (pact_list*)pact_alloc(sizeof(pact_list));
    l->cap = 8;
    l->len = 0;
    l->items = (void**)pact_alloc(sizeof(void*) * l->cap);
    return l;
}

PACT_UNUSED static void pact_list_push(pact_list* l, void* item) {
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

PACT_UNUSED static void* pact_list_get(const pact_list* l, int64_t index) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "pact: list index out of bounds: idx=%lld len=%lld\n", (long long)index, (long long)l->len);
        exit(1);
    }
    return l->items[index];
}

PACT_UNUSED static int pact_list_in_bounds(const pact_list* l, int64_t index) {
    return (index >= 0 && index < l->len);
}

PACT_UNUSED static int64_t pact_list_len(const pact_list* l) {
    return l->len;
}

PACT_UNUSED static void pact_list_set(pact_list* l, int64_t index, void* item) {
    if (index < 0 || index >= l->len) {
        fprintf(stderr, "pact: list set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    l->items[index] = item;
}

PACT_UNUSED static void* pact_list_pop(pact_list* l) {
    if (l->len <= 0) {
        fprintf(stderr, "pact: list pop on empty list\n");
        exit(1);
    }
    l->len--;
    return l->items[l->len];
}

PACT_UNUSED static void pact_list_free(pact_list* l) {
    if (l) {
        free(l->items);
        free(l);
    }
}

/* ── Hash map (string-keyed) ────────────────────────────────────────── */

PACT_UNUSED static int pact_str_eq(const char* a, const char* b);

PACT_UNUSED static uint64_t pact_map_hash(const char* key) {
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

PACT_UNUSED static pact_map* pact_map_new(void) {
    pact_map* m = (pact_map*)pact_alloc(sizeof(pact_map));
    m->cap = 16;
    m->len = 0;
    m->keys = (const char**)pact_alloc(sizeof(const char*) * (size_t)m->cap);
    m->values = (void**)pact_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)pact_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    return m;
}

PACT_UNUSED static void pact_map_grow(pact_map* m) {
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

PACT_UNUSED static void pact_map_set(pact_map* m, const char* key, void* value) {
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

PACT_UNUSED static void* pact_map_get(const pact_map* m, const char* key) {
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

PACT_UNUSED static int64_t pact_map_has(const pact_map* m, const char* key) {
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

PACT_UNUSED static int64_t pact_map_remove(pact_map* m, const char* key) {
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

PACT_UNUSED static int64_t pact_map_len(const pact_map* m) {
    return m->len;
}

PACT_UNUSED static pact_list* pact_map_keys(const pact_map* m) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            pact_list_push(result, (void*)m->keys[i]);
        }
    }
    return result;
}

PACT_UNUSED static pact_list* pact_map_values(const pact_map* m) {
    pact_list* result = pact_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) {
            pact_list_push(result, m->values[i]);
        }
    }
    return result;
}

PACT_UNUSED static void pact_map_free(pact_map* m) {
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

PACT_UNUSED static pact_bytes* pact_bytes_new(void) {
    pact_bytes* b = (pact_bytes*)pact_alloc(sizeof(pact_bytes));
    b->cap = 16;
    b->len = 0;
    b->data = (uint8_t*)pact_alloc((size_t)b->cap);
    return b;
}

PACT_UNUSED static void pact_bytes_push(pact_bytes* b, int64_t byte) {
    if (b->len >= b->cap) {
        b->cap *= 2;
        b->data = (uint8_t*)realloc(b->data, (size_t)b->cap);
        if (!b->data) { fprintf(stderr, "pact: out of memory\n"); exit(1); }
    }
    b->data[b->len++] = (uint8_t)(byte & 0xFF);
}

PACT_UNUSED static int64_t pact_bytes_get(const pact_bytes* b, int64_t index) {
    if (index < 0 || index >= b->len) return -1;
    return (int64_t)b->data[index];
}

PACT_UNUSED static void pact_bytes_set(pact_bytes* b, int64_t index, int64_t byte) {
    if (index < 0 || index >= b->len) {
        fprintf(stderr, "pact: bytes set index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    b->data[index] = (uint8_t)(byte & 0xFF);
}

PACT_UNUSED static int64_t pact_bytes_len(const pact_bytes* b) {
    return b->len;
}

PACT_UNUSED static int64_t pact_bytes_is_empty(const pact_bytes* b) {
    return b->len == 0;
}

PACT_UNUSED static pact_bytes* pact_bytes_concat(const pact_bytes* a, const pact_bytes* b) {
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

PACT_UNUSED static pact_bytes* pact_bytes_slice(const pact_bytes* b, int64_t start, int64_t end) {
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

PACT_UNUSED static int pact_bytes_to_str_checked(const pact_bytes* b, const char** out) {
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

PACT_UNUSED static const char* pact_bytes_to_hex(const pact_bytes* b) {
    char* hex = (char*)pact_alloc(b->len * 2 + 1);
    for (int64_t i = 0; i < b->len; i++) {
        sprintf(hex + i * 2, "%02x", b->data[i]);
    }
    hex[b->len * 2] = '\0';
    return hex;
}

PACT_UNUSED static pact_bytes* pact_bytes_from_str(const char* s) {
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

/* ── StringBuilder ──────────────────────────────────────────────────── */

typedef struct {
    char* data;
    int64_t len;
    int64_t cap;
} pact_sb;

PACT_UNUSED static pact_sb* pact_sb_new(void) {
    pact_sb* sb = (pact_sb*)pact_alloc(sizeof(pact_sb));
    sb->cap = 64;
    sb->len = 0;
    sb->data = (char*)pact_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}

PACT_UNUSED static pact_sb* pact_sb_with_capacity(int64_t cap) {
    if (cap < 16) cap = 16;
    pact_sb* sb = (pact_sb*)pact_alloc(sizeof(pact_sb));
    sb->cap = cap;
    sb->len = 0;
    sb->data = (char*)pact_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}

PACT_UNUSED static void pact_sb_write_n(pact_sb* sb, const char* s, int64_t slen) {
    if (slen == 0) return;
    int64_t needed = sb->len + slen + 1;
    if (needed > sb->cap) {
        int64_t new_cap = sb->cap * 2;
        while (new_cap < needed) new_cap *= 2;
        sb->cap = new_cap;
        sb->data = (char*)realloc(sb->data, (size_t)sb->cap);
        if (!sb->data) { fprintf(stderr, "pact: out of memory\n"); exit(1); }
    }
    memcpy(sb->data + sb->len, s, (size_t)slen);
    sb->len += slen;
    sb->data[sb->len] = '\0';
}

PACT_UNUSED static void pact_sb_write(pact_sb* sb, const char* s) {
    pact_sb_write_n(sb, s, (int64_t)strlen(s));
}

PACT_UNUSED static void pact_sb_write_char(pact_sb* sb, const char* ch) {
    pact_sb_write(sb, ch);
}

PACT_UNUSED static void pact_sb_write_int(pact_sb* sb, int64_t val) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)val);
    pact_sb_write_n(sb, buf, (int64_t)len);
}

PACT_UNUSED static void pact_sb_write_float(pact_sb* sb, double val) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%g", val);
    pact_sb_write_n(sb, buf, (int64_t)len);
}

PACT_UNUSED static void pact_sb_write_bool(pact_sb* sb, int val) {
    pact_sb_write(sb, val ? "true" : "false");
}

PACT_UNUSED static const char* pact_sb_to_str(const pact_sb* sb) {
    return strdup(sb->data);
}

PACT_UNUSED static int64_t pact_sb_len(const pact_sb* sb) {
    return sb->len;
}

PACT_UNUSED static int64_t pact_sb_capacity(const pact_sb* sb) {
    return sb->cap;
}

PACT_UNUSED static void pact_sb_clear(pact_sb* sb) {
    sb->len = 0;
    sb->data[0] = '\0';
}

PACT_UNUSED static int pact_sb_is_empty(const pact_sb* sb) {
    return sb->len == 0;
}

/* ── String operations ──────────────────────────────────────────────── */

PACT_UNUSED static int64_t pact_str_len(const char* s) {
    return (int64_t)strlen(s);
}

PACT_UNUSED static int64_t pact_str_char_at(const char* s, int64_t i) {
    return (int64_t)(unsigned char)s[i];
}

PACT_UNUSED static const char* pact_str_substr(const char* s, int64_t start, int64_t len) {
    char* buf = (char*)pact_alloc(len + 1);
    memcpy(buf, s + start, (size_t)len);
    buf[len] = '\0';
    return buf;
}

PACT_UNUSED static const char* pact_str_from_char_code(int64_t code) {
    char* buf = (char*)pact_alloc(2);
    buf[0] = (char)code;
    buf[1] = '\0';
    return buf;
}

PACT_UNUSED static const char* pact_str_concat(const char* a, const char* b) {
    int64_t la = pact_str_len(a);
    int64_t lb = pact_str_len(b);
    char* buf = (char*)pact_alloc(la + lb + 1);
    memcpy(buf, a, (size_t)la);
    memcpy(buf + la, b, (size_t)lb);
    buf[la + lb] = '\0';
    return buf;
}

PACT_UNUSED static int pact_str_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}

PACT_UNUSED static int pact_str_contains(const char* s, const char* needle) {
    return strstr(s, needle) != NULL;
}

PACT_UNUSED static int pact_str_starts_with(const char* s, const char* prefix) {
    size_t plen = strlen(prefix);
    return strncmp(s, prefix, plen) == 0;
}

PACT_UNUSED static int pact_str_ends_with(const char* s, const char* suffix) {
    size_t slen = strlen(s);
    size_t sufflen = strlen(suffix);
    if (sufflen > slen) return 0;
    return memcmp(s + slen - sufflen, suffix, sufflen) == 0;
}

PACT_UNUSED static const char* pact_str_slice(const char* s, int64_t start, int64_t end) {
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

PACT_UNUSED static int64_t pact_parse_int(const char* s) {
    return (int64_t)atoll(s);
}

PACT_UNUSED static pact_list* pact_str_split(const char* s, const char* delim) {
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

PACT_UNUSED static const char* pact_str_join(const pact_list* parts, const char* delim) {
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

PACT_UNUSED static const char* pact_str_trim(const char* s) {
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

PACT_UNUSED static const char* pact_str_to_upper(const char* s) {
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

PACT_UNUSED static const char* pact_str_to_lower(const char* s) {
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

PACT_UNUSED static const char* pact_str_replace(const char* s, const char* needle, const char* repl) {
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

PACT_UNUSED static int64_t pact_str_index_of(const char* s, const char* needle) {
    if (!s || !needle) return -1;
    const char* found = strstr(s, needle);
    if (!found) return -1;
    return (int64_t)(found - s);
}

PACT_UNUSED static pact_list* pact_str_lines(const char* s) {
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

PACT_UNUSED static double pact_parse_float(const char* s) {
    return atof(s ? s : "0");
}

/* ── File I/O ───────────────────────────────────────────────────────── */

PACT_UNUSED static const char* pact_read_file(const char* path) {
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

PACT_UNUSED static void pact_write_file(const char* path, const char* content) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "pact: cannot open file for writing: %s\n", path);
        exit(1);
    }
    size_t len = strlen(content);
    fwrite(content, 1, len, f);
    fclose(f);
}

PACT_UNUSED static int pact_g_argc = 0;
PACT_UNUSED static const char** pact_g_argv = NULL;

PACT_UNUSED static int64_t pact_arg_count(void) {
    return (int64_t)pact_g_argc;
}

PACT_UNUSED static const char* pact_get_arg(int64_t index) {
    if (index < 0 || index >= pact_g_argc) {
        fprintf(stderr, "pact: arg index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    return pact_g_argv[index];
}

PACT_UNUSED static int64_t pact_file_exists(const char* path) {
    return access(path, F_OK) == 0 ? 1 : 0;
}

PACT_UNUSED static int64_t pact_is_dir(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
}

PACT_UNUSED static pact_list* pact_list_dir(const char* path) {
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

PACT_UNUSED static int64_t pact_file_mtime(const char* path) {
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

PACT_UNUSED static int64_t pact_getpid(void) {
    return (int64_t)getpid();
}

PACT_UNUSED static void pact_exit(int64_t code) { exit((int)code); }

PACT_UNUSED static int64_t pact_shell_exec(const char* command) {
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

PACT_UNUSED static pact_closure* pact_closure_new(void* fn_ptr, void** captures, int64_t capture_count) {
    pact_closure* c = (pact_closure*)pact_alloc(sizeof(pact_closure));
    c->fn_ptr = fn_ptr;
    c->captures = captures;
    c->capture_count = capture_count;
    return c;
}

PACT_UNUSED static void* pact_closure_get_fn(const pact_closure* c) {
    return c->fn_ptr;
}

PACT_UNUSED static void* pact_closure_get_capture(const pact_closure* c, int64_t index) {
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

PACT_UNUSED static void pact_io_default_print(const char* msg) {
    printf("%s\n", msg);
}

PACT_UNUSED static void pact_io_default_log(const char* msg) {
    fprintf(stderr, "[LOG] %s\n", msg);
}

PACT_UNUSED static pact_io_vtable pact_io_vtable_default = {
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

PACT_UNUSED static const char* pact_fs_default_read(const char* path) {
    return pact_read_file(path);
}

PACT_UNUSED static int pact_fs_default_write(const char* path, const char* content) {
    pact_write_file(path, content);
    return 0;
}

PACT_UNUSED static int pact_fs_default_delete(const char* path) {
    return remove(path);
}

PACT_UNUSED static int pact_fs_default_watch(const char* path, void (*callback)(const char*)) {
    (void)path; (void)callback;
    fprintf(stderr, "pact: fs.watch not implemented\n");
    return -1;
}

PACT_UNUSED static pact_fs_vtable pact_fs_vtable_default = {
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

PACT_UNUSED static int pact_net_default_connect(const char* url) {
    (void)url;
    fprintf(stderr, "pact: net.connect not implemented\n");
    return -1;
}

PACT_UNUSED static int pact_net_default_listen(const char* addr, int port) {
    (void)addr; (void)port;
    fprintf(stderr, "pact: net.listen not implemented\n");
    return -1;
}

PACT_UNUSED static const char* pact_net_default_dns(const char* hostname) {
    (void)hostname;
    fprintf(stderr, "pact: net.dns not implemented\n");
    return NULL;
}

PACT_UNUSED static pact_net_vtable pact_net_vtable_default = {
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

PACT_UNUSED static const char* pact_db_default_read(const char* query) {
    (void)query;
    fprintf(stderr, "pact: db.read not implemented\n");
    return NULL;
}

PACT_UNUSED static int pact_db_default_write(const char* query) {
    (void)query;
    fprintf(stderr, "pact: db.write not implemented\n");
    return -1;
}

PACT_UNUSED static int pact_db_default_admin(const char* query) {
    (void)query;
    fprintf(stderr, "pact: db.admin not implemented\n");
    return -1;
}

PACT_UNUSED static pact_db_vtable pact_db_vtable_default = {
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

PACT_UNUSED static const char* pact_crypto_default_hash(const char* data) {
    (void)data;
    fprintf(stderr, "pact: crypto.hash not implemented\n");
    return NULL;
}

PACT_UNUSED static const char* pact_crypto_default_sign(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "pact: crypto.sign not implemented\n");
    return NULL;
}

PACT_UNUSED static const char* pact_crypto_default_encrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "pact: crypto.encrypt not implemented\n");
    return NULL;
}

PACT_UNUSED static const char* pact_crypto_default_decrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "pact: crypto.decrypt not implemented\n");
    return NULL;
}

PACT_UNUSED static pact_crypto_vtable pact_crypto_vtable_default = {
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

PACT_UNUSED static int pact_rand_seeded = 0;

PACT_UNUSED static void pact_rand_ensure_seed(void) {
    if (!pact_rand_seeded) {
        srand((unsigned)42);
        pact_rand_seeded = 1;
    }
}

PACT_UNUSED static int64_t pact_rand_default_int(int64_t min, int64_t max) {
    pact_rand_ensure_seed();
    if (min >= max) return min;
    return min + (int64_t)(rand() % (int)(max - min));
}

PACT_UNUSED static double pact_rand_default_float(void) {
    pact_rand_ensure_seed();
    return (double)rand() / (double)RAND_MAX;
}

PACT_UNUSED static void pact_rand_default_bytes(void* buf, int64_t len) {
    pact_rand_ensure_seed();
    unsigned char* p = (unsigned char*)buf;
    for (int64_t i = 0; i < len; i++) {
        p[i] = (unsigned char)(rand() & 0xFF);
    }
}

PACT_UNUSED static pact_rand_vtable pact_rand_vtable_default = {
    pact_rand_default_int,
    pact_rand_default_float,
    pact_rand_default_bytes
};

/* ── Duration / Instant value types ─────────────────────────────────── */

typedef struct { int64_t nanos; } pact_duration;
typedef struct { int64_t nanos; } pact_instant;

PACT_UNUSED static pact_duration pact_duration_nanos(int64_t n)   { return (pact_duration){.nanos = n}; }
PACT_UNUSED static pact_duration pact_duration_ms(int64_t ms)     { return (pact_duration){.nanos = ms * 1000000LL}; }
PACT_UNUSED static pact_duration pact_duration_seconds(int64_t s) { return (pact_duration){.nanos = s * 1000000000LL}; }
PACT_UNUSED static pact_duration pact_duration_minutes(int64_t m) { return (pact_duration){.nanos = m * 60LL * 1000000000LL}; }
PACT_UNUSED static pact_duration pact_duration_hours(int64_t h)   { return (pact_duration){.nanos = h * 3600LL * 1000000000LL}; }

PACT_UNUSED static int64_t pact_duration_to_nanos(pact_duration d)   { return d.nanos; }
PACT_UNUSED static int64_t pact_duration_to_ms(pact_duration d)      { return d.nanos / 1000000LL; }
PACT_UNUSED static int64_t pact_duration_to_seconds(pact_duration d) { return d.nanos / 1000000000LL; }

PACT_UNUSED static pact_duration pact_duration_add(pact_duration a, pact_duration b) { return (pact_duration){.nanos = a.nanos + b.nanos}; }
PACT_UNUSED static pact_duration pact_duration_sub(pact_duration a, pact_duration b) { return (pact_duration){.nanos = a.nanos - b.nanos}; }
PACT_UNUSED static pact_duration pact_duration_scale(pact_duration d, int64_t factor) { return (pact_duration){.nanos = d.nanos * factor}; }

PACT_UNUSED static int64_t pact_duration_is_zero(pact_duration d) { return d.nanos == 0 ? 1 : 0; }

PACT_UNUSED static int64_t pact_instant_to_unix_secs(pact_instant i) { return i.nanos / 1000000000LL; }
PACT_UNUSED static int64_t pact_instant_to_unix_ms(pact_instant i)   { return i.nanos / 1000000LL; }

PACT_UNUSED static const char* pact_instant_to_rfc3339(pact_instant i) {
    time_t epoch_secs = (time_t)(i.nanos / 1000000000LL);
    struct tm utc;
    gmtime_r(&epoch_secs, &utc);
    char* buf = (char*)pact_alloc(32);
    snprintf(buf, 32, "%04d-%02d-%02dT%02d:%02d:%02dZ",
             utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday,
             utc.tm_hour, utc.tm_min, utc.tm_sec);
    return buf;
}

PACT_UNUSED static pact_instant pact_instant_add(pact_instant i, pact_duration d) { return (pact_instant){.nanos = i.nanos + d.nanos}; }
PACT_UNUSED static pact_duration pact_instant_since(pact_instant later, pact_instant earlier) { return (pact_duration){.nanos = later.nanos - earlier.nanos}; }

PACT_UNUSED static pact_duration pact_instant_elapsed(pact_instant then) {
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

PACT_UNUSED static pact_instant pact_time_default_read(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (pact_instant){.nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec};
}

PACT_UNUSED static void pact_time_default_sleep(pact_duration d) {
    int64_t ns = d.nanos;
    struct timespec ts;
    ts.tv_sec  = (time_t)(ns / 1000000000LL);
    ts.tv_nsec = (long)(ns % 1000000000LL);
    nanosleep(&ts, NULL);
}

PACT_UNUSED static pact_time_vtable pact_time_vtable_default = {
    pact_time_default_read,
    pact_time_default_sleep
};

PACT_UNUSED static int64_t pact_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}

/* ── Env ────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* name);
    int         (*write)(const char* name, const char* value);
} pact_env_vtable;

PACT_UNUSED static const char* pact_env_default_read(const char* name) {
    const char* v = getenv(name);
    return v ? strdup(v) : NULL;
}

PACT_UNUSED static int pact_env_default_write(const char* name, const char* value) {
    return setenv(name, value, 1);
}

PACT_UNUSED static pact_env_vtable pact_env_vtable_default = {
    pact_env_default_read,
    pact_env_default_write
};

/* ── Process ────────────────────────────────────────────────────────── */
typedef struct {
    int64_t (*spawn)(const char* command);
    int     (*signal)(int64_t pid, int sig);
} pact_process_vtable;

PACT_UNUSED static int64_t pact_process_default_spawn(const char* command) {
    (void)command;
    fprintf(stderr, "pact: process.spawn not implemented\n");
    return -1;
}

PACT_UNUSED static int pact_process_default_signal(int64_t pid, int sig) {
    (void)pid; (void)sig;
    fprintf(stderr, "pact: process.signal not implemented\n");
    return -1;
}

PACT_UNUSED static pact_process_vtable pact_process_vtable_default = {
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

PACT_UNUSED static pact_ctx pact_ctx_default(void) {
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

/* ── JSON helpers ────────────────────────────────────────────────── */

PACT_UNUSED static const char* pact_json_escape_str(const char* s) {
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

/* ── Debug assert ───────────────────────────────────────────────────── */

PACT_UNUSED static void __pact_debug_assert_fail(const char* file, int line, const char* fn, const char* cond, const char* msg) {
    fprintf(stderr, "DEBUG ASSERT FAILED: %s\n", msg);
    fprintf(stderr, "  condition: %s\n", cond);
    fprintf(stderr, "  location: %s:%d in %s\n", file, line, fn);
    exit(1);
}

/* ── FFI scope helpers ─────────────────────────────────────────────── */

PACT_UNUSED static pact_list* pact_ffi_scope_new(void) {
    return pact_list_new();
}

PACT_UNUSED static void* pact_ffi_scope_track(pact_list* scope, void* ptr) {
    pact_list_push(scope, ptr);
    return ptr;
}

PACT_UNUSED static void* pact_ffi_scope_take(pact_list* scope, void* ptr) {
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

PACT_UNUSED static void pact_ffi_scope_cleanup(pact_list* scope) {
    for (int64_t i = 0; i < scope->len; i++) {
        free(scope->items[i]);
    }
    free(scope->items);
    free(scope);
}

#endif
