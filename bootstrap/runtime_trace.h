#ifndef BLINK_RUNTIME_TRACE_H
#define BLINK_RUNTIME_TRACE_H

#include <pthread.h>
#include <signal.h>

#define BLINK_TRACE_MAX_VALUE_LEN 200

/* One filter of BLINK_TRACE: its key and the values that compose with OR. The value has no
   limit on its items or their length, so the filter holds them on the heap. */
typedef struct {
    char* key;
    char** values;
    int count;
} blink_trace_filter;

typedef struct {
    int active;
    int depth;
    struct timespec start;
    blink_trace_filter* filters;
    int filter_count;
    int event_enter;
    int event_exit;
    int event_effect;
    int event_state;
    int event_note;
    /* Set when the stream of the trace closes; the program writes no more events (§8.15.13). */
    int closed;
} blink_trace_state;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_trace_state __blink_trace = {0};
  #else
    extern blink_trace_state __blink_trace;
  #endif
#else
static blink_trace_state __blink_trace = {0};
#endif

/* The state of one event write, which blink_trace_write_begin saves and
   blink_trace_write_end restores. */
typedef struct {
    sigset_t old_mask;
    int pipe_was_pending;
    int had_error;
} blink_trace_write_guard;

/* Starts the write of one event: takes the stderr lock and blocks SIGPIPE for this thread, so
   a closed stream ends the trace and not the program (§8.15.13). Gives 0, with no lock held,
   when the stream closed before. */
BLINK_RT_FN int blink_trace_write_begin(blink_trace_write_guard* g);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_write_begin(blink_trace_write_guard* g) {
    flockfile(stderr);
    if (__blink_trace.closed) {
        funlockfile(stderr);
        return 0;
    }
    sigset_t pipe_set, pending;
    sigemptyset(&pipe_set);
    sigaddset(&pipe_set, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &pipe_set, &g->old_mask);
    sigpending(&pending);
    g->pipe_was_pending = sigismember(&pending, SIGPIPE);
    g->had_error = ferror(stderr);
    return 1;
}
#endif

/* Ends the write of one event. A write that failed closes the trace, as the stream lost the
   event text. The SIGPIPE of that write is consumed and the error flag is cleared, so the next
   write of the program to stderr sees the stream as it would with no trace. A SIGPIPE or an
   error that was there before the event belongs to the program, so it stays. */
BLINK_RT_FN void blink_trace_write_end(blink_trace_write_guard* g);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_write_end(blink_trace_write_guard* g) {
    sigset_t pipe_set, pending;
    sigemptyset(&pipe_set);
    sigaddset(&pipe_set, SIGPIPE);
    sigpending(&pending);
    int raised_pipe = !g->pipe_was_pending && sigismember(&pending, SIGPIPE);
    int raised_error = !g->had_error && ferror(stderr);
    if (raised_pipe || raised_error) __blink_trace.closed = 1;
    if (raised_error) clearerr(stderr);
    if (raised_pipe) {
        int got;
        sigwait(&pipe_set, &got);
    }
    pthread_sigmask(SIG_SETMASK, &g->old_mask, NULL);
    funlockfile(stderr);
}
#endif

/* One traced call on this thread's stack: when it began, and whether the filters chose its
   enter and exit events. The exit reads both, so the two events of one call always pair.
   Depth is the call stack depth of a thread, so the stack is per thread. The exit event
   prints when the call is popped, after the cleanups of its scopes, so it keeps the names
   and the return text until then. */
typedef struct {
    int64_t enter_ts;
    int matched;
    const char* fn;
    const char* module;
    char* exit_value;
    int exit_kept;
} blink_trace_frame;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    __thread blink_trace_frame* __blink_trace_frames = NULL;
    __thread int64_t __blink_trace_frame_cap = 0;
    __thread int64_t __blink_trace_frame_top = 0;
    __thread int64_t __blink_trace_mute_count = 0;
  #else
    extern __thread blink_trace_frame* __blink_trace_frames;
    extern __thread int64_t __blink_trace_frame_cap;
    extern __thread int64_t __blink_trace_frame_top;
    extern __thread int64_t __blink_trace_mute_count;
  #endif
#else
BLINK_UNUSED static __thread blink_trace_frame* __blink_trace_frames = NULL;
BLINK_UNUSED static __thread int64_t __blink_trace_frame_cap = 0;
BLINK_UNUSED static __thread int64_t __blink_trace_frame_top = 0;
BLINK_UNUSED static __thread int64_t __blink_trace_mute_count = 0;
#endif

BLINK_RT_FN int64_t blink_trace_ts_us(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_trace_ts_us(void) {
    struct timespec now;
#ifdef __APPLE__
    clock_gettime(CLOCK_MONOTONIC, &now);
#else
    clock_gettime(CLOCK_MONOTONIC, &now);
#endif
    int64_t sec_diff = (int64_t)(now.tv_sec - __blink_trace.start.tv_sec);
    int64_t nsec_diff = (int64_t)(now.tv_nsec - __blink_trace.start.tv_nsec);
    return sec_diff * 1000000 + nsec_diff / 1000;
}
#endif

/* The edit distance of a and b in bytes, for the did-you-mean of a bad filter. */
BLINK_RT_FN size_t blink_trace_edit_distance(const char* a, const char* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN size_t blink_trace_edit_distance(const char* a, const char* b) {
    size_t alen = strlen(a), blen = strlen(b);
    if (alen == 0) return blen;
    if (blen == 0) return alen;
    size_t* prev = (size_t*)malloc((blen + 1) * sizeof(size_t));
    size_t* curr = (size_t*)malloc((blen + 1) * sizeof(size_t));
    if (!prev || !curr) { free(prev); free(curr); return (size_t)-1; }
    for (size_t j = 0; j <= blen; j++) prev[j] = j;
    for (size_t i = 0; i < alen; i++) {
        curr[0] = i + 1;
        for (size_t k = 0; k < blen; k++) {
            size_t best = prev[k + 1] + 1;
            size_t ins = curr[k] + 1;
            size_t sub = prev[k] + (a[i] == b[k] ? 0 : 1);
            if (ins < best) best = ins;
            if (sub < best) best = sub;
            curr[k + 1] = best;
        }
        size_t* t = prev; prev = curr; curr = t;
    }
    size_t d = prev[blen];
    free(prev);
    free(curr);
    return d;
}
#endif

/* A bad filter list (§8.15.12): the text names the source and the whole value, then the
   reason, which is `before`, `name` in backticks and `after`. With `known`, the nearest known
   word within max(1, len / 3) edits follows as a did-you-mean; a tie goes to the first word.
   trace_filter_error in src/trace_filter.bl gives the same reason for the same value. */
BLINK_RT_FN void blink_trace_reject(const char* value, const char* before, const char* name,
    const char* after, const char* const* known, int nknown);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_reject(const char* value, const char* before, const char* name,
    const char* after, const char* const* known, int nknown) {
    fprintf(stderr, "error: bad BLINK_TRACE value \"%s\": %s", value, before);
    if (name) fprintf(stderr, "`%s`", name);
    fputs(after, stderr);
    if (name && known) {
        const char* best = NULL;
        size_t best_dist = 0;
        for (int i = 0; i < nknown; i++) {
            size_t d = blink_trace_edit_distance(name, known[i]);
            if (!best || d < best_dist) { best = known[i]; best_dist = d; }
        }
        size_t threshold = strlen(name) / 3;
        if (threshold < 1) threshold = 1;
        if (best && best_dist <= threshold) fprintf(stderr, "; did you mean `%s`?", best);
    }
    fputs("\n", stderr);
    exit(2);
}
#endif

/* The trace code cannot go on without the memory it asked for. The words name the work, such
   as "reading" "BLINK_TRACE", so the message says which env var or line ran out. */
BLINK_RT_FN void blink_trace_oom(const char* verb, const char* what);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_oom(const char* verb, const char* what) {
    fprintf(stderr, "error: out of memory %s %s\n", verb, what);
    exit(2);
}
#endif

/* A copy of s[0..n) with ASCII space and tab cut from its two ends, or NULL when that is
   empty. Out of memory names `var`, the env var whose item this is. */
BLINK_RT_FN char* blink_trace_trim_dup_for(const char* s, size_t n, const char* var);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN char* blink_trace_trim_dup_for(const char* s, size_t n, const char* var) {
    while (n > 0 && (*s == ' ' || *s == '\t')) { s++; n--; }
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t')) n--;
    if (n == 0) return NULL;
    char* out = (char*)malloc(n + 1);
    if (!out) blink_trace_oom("reading", var);
    memcpy(out, s, n);
    out[n] = '\0';
    return out;
}
#endif

/* The one item rule of §8.15.5 for every list a trace env var holds: split `v` on `sep`, trim
   each item, skip an empty one, and hand the rest to `take`, which owns the copy. */
BLINK_RT_FN void blink_trace_each_item(const char* v, char sep, const char* var,
    void (*take)(char* item, void* ctx), void* ctx);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_each_item(const char* v, char sep, const char* var,
    void (*take)(char* item, void* ctx), void* ctx) {
    const char* p = v;
    for (;;) {
        const char* end = strchr(p, sep);
        size_t n = end ? (size_t)(end - p) : strlen(p);
        char* item = blink_trace_trim_dup_for(p, n, var);
        if (item) take(item, ctx);
        if (!end) break;
        p = end + 1;
    }
}
#endif

BLINK_RT_FN int blink_trace_is_event_type(const char* v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_is_event_type(const char* v) {
    return strcmp(v, "enter") == 0 || strcmp(v, "exit") == 0 || strcmp(v, "state") == 0
        || strcmp(v, "effect") == 0 || strcmp(v, "note") == 0;
}
#endif

/* Why v is not a depth: value, or NULL. The value is ASCII digits only and fits in Int
   (§8.15.5); a sign is not a digit, and leading zeros are digits. */
BLINK_RT_FN const char* blink_trace_depth_error(const char* v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_trace_depth_error(const char* v) {
    int64_t n = 0;
    int big = 0;
    for (const char* p = v; *p; p++) {
        if (*p < '0' || *p > '9') return "depth takes digits only";
        int d = *p - '0';
        if (n > (INT64_MAX - d) / 10) big = 1;
        else n = n * 10 + d;
    }
    return big ? "depth takes digits only, and the number must fit in Int" : NULL;
}
#endif

BLINK_UNUSED static const char* const blink_trace_filter_keys[] = { "fn", "module", "depth", "event", "effect", "state" };
BLINK_UNUSED static const char* const blink_trace_event_types[] = { "enter", "exit", "state", "effect", "note" };

/* The filter one `key:v+v` item of BLINK_TRACE fills, the item, and the whole value, for its
   errors. */
typedef struct {
    blink_trace_filter* f;
    int cap;
    const char* item;
    const char* value;
} blink_trace_value_ctx;

/* Checks one `+` value of a BLINK_TRACE item and adds it to the item's filter. */
BLINK_RT_FN void blink_trace_take_value(char* v, void* ctx);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_take_value(char* v, void* ctx) {
    blink_trace_value_ctx* c = (blink_trace_value_ctx*)ctx;
    const char* key = c->f->key;
    if (strcmp(key, "event") == 0 && !blink_trace_is_event_type(v)) {
        blink_trace_reject(c->value, "unknown event type ", v, "", blink_trace_event_types, 5);
    }
    if (c->f->count == c->cap) {
        c->cap = c->cap ? c->cap * 2 : 4;
        char** grown = (char**)realloc(c->f->values, (size_t)c->cap * sizeof(char*));
        if (!grown) blink_trace_oom("reading", "BLINK_TRACE");
        c->f->values = grown;
    }
    c->f->values[c->f->count++] = v;
}
#endif

/* Reads one trimmed `,` item of the BLINK_TRACE value `value` into a filter, or exits on a
   bad one. `all` adds no filter; blink_trace_read_filters checks where it may stand. */
BLINK_RT_FN void blink_trace_parse_item_of(const char* item, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_parse_item_of(const char* item, const char* value) {
    if (strcmp(item, "all") == 0) return;
    const char* colon = strchr(item, ':');
    if (!colon) blink_trace_reject(value, "a filter is `key:value`, not ", item, "", NULL, 0);
    size_t klen = (size_t)(colon - item);
    char* key = (char*)malloc(klen + 1);
    if (!key) blink_trace_oom("reading", "BLINK_TRACE");
    memcpy(key, item, klen);
    key[klen] = '\0';
    if (strcmp(key, "fn") != 0 && strcmp(key, "module") != 0 && strcmp(key, "depth") != 0
        && strcmp(key, "event") != 0 && strcmp(key, "effect") != 0 && strcmp(key, "state") != 0) {
        blink_trace_reject(value, "unknown key ", key, "", blink_trace_filter_keys, 6);
    }
    blink_trace_filter f = { key, NULL, 0 };
    blink_trace_value_ctx ctx = { &f, 0, item, value };
    if (strcmp(key, "depth") == 0) {
        /* The depth: rule is "digits and nothing else", so a `+` in its value is a bad digit. */
        char* v = blink_trace_trim_dup_for(colon + 1, strlen(colon + 1), "BLINK_TRACE");
        if (v) {
            const char* why = blink_trace_depth_error(v);
            if (why) blink_trace_reject(value, why, NULL, "", NULL, 0);
            blink_trace_take_value(v, &ctx);
        }
    } else {
        blink_trace_each_item(colon + 1, '+', "BLINK_TRACE", blink_trace_take_value, &ctx);
    }
    if (f.count == 0) blink_trace_reject(value, "the key ", key, " has no value", NULL, 0);
    /* The items of `,` all must match (§8.15.5), so a second `event:` item narrows the set. */
    if (strcmp(key, "event") == 0) {
        int enter = 0, exit_ = 0, effect = 0, state = 0, note = 0;
        for (int i = 0; i < f.count; i++) {
            if (strcmp(f.values[i], "enter") == 0) enter = 1;
            if (strcmp(f.values[i], "exit") == 0) exit_ = 1;
            if (strcmp(f.values[i], "effect") == 0) effect = 1;
            if (strcmp(f.values[i], "state") == 0) state = 1;
            if (strcmp(f.values[i], "note") == 0) note = 1;
        }
        __blink_trace.event_enter &= enter;
        __blink_trace.event_exit &= exit_;
        __blink_trace.event_effect &= effect;
        __blink_trace.event_state &= state;
        __blink_trace.event_note &= note;
    }
    blink_trace_filter* grown = (blink_trace_filter*)realloc(__blink_trace.filters,
        (size_t)(__blink_trace.filter_count + 1) * sizeof(blink_trace_filter));
    if (!grown) blink_trace_oom("reading", "BLINK_TRACE");
    __blink_trace.filters = grown;
    __blink_trace.filters[__blink_trace.filter_count++] = f;
}
#endif

BLINK_RT_FN void blink_trace_parse_item(const char* item);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_parse_item(const char* item) {
    blink_trace_parse_item_of(item, item);
}
#endif

/* Reads one `,` item of BLINK_TRACE into a filter, then frees the copy. ctx is the value. */
BLINK_RT_FN void blink_trace_take_filter(char* item, void* ctx);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_take_filter(char* item, void* ctx) {
    blink_trace_parse_item_of(item, (const char*)ctx);
    free(item);
}
#endif

/* Counts the `,` items of a value: [0] the items `all`, [1] the others. */
BLINK_RT_FN void blink_trace_count_item(char* item, void* ctx);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_count_item(char* item, void* ctx) {
    int* counts = (int*)ctx;
    counts[strcmp(item, "all") == 0 ? 0 : 1]++;
    free(item);
}
#endif

/* Reads the `,` items of a BLINK_TRACE value (§8.15.5); exits on a bad one (§8.15.12). The
   items are checked in order first, and `all` beside another item after them, as the check
   of `blink run` does. A list with no items adds no filter, so it selects every event. */
BLINK_RT_FN void blink_trace_read_filters(const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_read_filters(const char* value) {
    int counts[2] = { 0, 0 };
    blink_trace_each_item(value, ',', "BLINK_TRACE", blink_trace_count_item, counts);
    blink_trace_each_item(value, ',', "BLINK_TRACE", blink_trace_take_filter, (void*)value);
    if (counts[0] > 0 && counts[1] > 0) {
        blink_trace_reject(value, "`all` cannot be used with another filter", NULL, "", NULL, 0);
    }
}
#endif

BLINK_RT_FN void blink_trace_parse_filters(const char* filter_str);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_parse_filters(const char* filter_str) {
    blink_trace_read_filters(filter_str);
}
#endif

/* A traced binary reads BLINK_TRACE and nothing else, so its argv stays the program's own
   (§8.15.13). The parameters stay because the code of an older compiler passes them. */
BLINK_RT_FN void blink_trace_init(int argc, char** argv);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_init(int argc, char** argv) {
    (void)argc; (void)argv;
    for (int i = 0; i < __blink_trace.filter_count; i++) {
        free(__blink_trace.filters[i].key);
        for (int j = 0; j < __blink_trace.filters[i].count; j++) free(__blink_trace.filters[i].values[j]);
        free(__blink_trace.filters[i].values);
    }
    free(__blink_trace.filters);
    __blink_trace.filters = NULL;
    __blink_trace.active = 0;
    __blink_trace.depth = 0;
    __blink_trace.filter_count = 0;
    __blink_trace.event_enter = 1;
    __blink_trace.event_exit = 1;
    __blink_trace.event_effect = 1;
    __blink_trace.event_state = 1;
    __blink_trace.event_note = 1;
#ifndef BLINK_NO_TRACE_INIT
    /* No value turns tracing off: unset, empty text and a list with no items all trace
       every event (§8.15.13). */
    const char* env = getenv("BLINK_TRACE");
    __blink_trace.active = 1;
    clock_gettime(CLOCK_MONOTONIC, &__blink_trace.start);
    if (env) blink_trace_read_filters(env);
#endif
}
#endif

/* Whether a `fn:` value names the frame: the whole name, or its last whole dot segments. */
BLINK_RT_FN int blink_trace_fn_named(const char* fn, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_fn_named(const char* fn, const char* value) {
    size_t n = strlen(fn);
    size_t v = strlen(value);
    if (v > n) return 0;
    if (strcmp(fn + (n - v), value) != 0) return 0;
    return v == n || fn[n - v - 1] == '.';
}
#endif

BLINK_RT_FN int blink_trace_match(const char* fn, const char* module, int depth);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_match(const char* fn, const char* module, int depth) {
    if (!__blink_trace.active) return 0;
    for (int i = 0; i < __blink_trace.filter_count; i++) {
        blink_trace_filter* f = &__blink_trace.filters[i];
        if (strcmp(f->key, "fn") == 0) {
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if (blink_trace_fn_named(fn, f->values[j])) { matched = 1; break; }
            }
            if (!matched) return 0;
        } else if (strcmp(f->key, "module") == 0) {
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if (strcmp(module, f->values[j]) == 0) { matched = 1; break; }
            }
            if (!matched) return 0;
        } else if (strcmp(f->key, "depth") == 0) {
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if ((long long)depth <= strtoll(f->values[j], NULL, 10)) { matched = 1; break; }
            }
            if (!matched) return 0;
        }
    }
    return 1;
}
#endif

BLINK_RT_FN int blink_trace_match_effect(const char* fn, const char* module, int depth, const char* effect);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_match_effect(const char* fn, const char* module, int depth, const char* effect) {
    if (!blink_trace_match(fn, module, depth)) return 0;
    for (int i = 0; i < __blink_trace.filter_count; i++) {
        blink_trace_filter* f = &__blink_trace.filters[i];
        if (strcmp(f->key, "effect") == 0) {
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if (strcmp(effect, f->values[j]) == 0) { matched = 1; break; }
            }
            if (!matched) return 0;
        }
    }
    return 1;
}
#endif

BLINK_RT_FN int blink_trace_match_state(const char* fn, const char* module, int depth, const char* var);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_match_state(const char* fn, const char* module, int depth, const char* var) {
    if (!blink_trace_match(fn, module, depth)) return 0;
    for (int i = 0; i < __blink_trace.filter_count; i++) {
        blink_trace_filter* f = &__blink_trace.filters[i];
        if (strcmp(f->key, "state") == 0) {
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if (strcmp(var, f->values[j]) == 0) { matched = 1; break; }
            }
            if (!matched) return 0;
        }
    }
    return 1;
}
#endif

BLINK_RT_FN void blink_trace_write_escaped(FILE* out, const char* s, int max_len);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_write_escaped(FILE* out, const char* s, int max_len) {
    int written = 0;
    while (*s && written < max_len) {
        switch (*s) {
            case '"':  fputs("\\\"", out); written += 2; break;
            case '\\': fputs("\\\\", out); written += 2; break;
            case '\n': fputs("\\n", out); written += 2; break;
            case '\r': fputs("\\r", out); written += 2; break;
            case '\t': fputs("\\t", out); written += 2; break;
            default:   fputc(*s, out); written++; break;
        }
        s++;
    }
    if (*s && written >= max_len) {
        /* signal truncation — caller adds truncated field */
    }
}
#endif

BLINK_RT_FN int blink_trace_str_truncated(const char* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_str_truncated(const char* s) {
    int len = 0;
    while (s[len]) { len++; if (len > BLINK_TRACE_MAX_VALUE_LEN) return 1; }
    return 0;
}
#endif

BLINK_RT_FN void blink_trace_enter(const char* fn, const char* module, int depth,
    const char* file, int line, int col, const char* args_json);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_enter(const char* fn, const char* module, int depth,
    const char* file, int line, int col, const char* args_json) {
    if (!__blink_trace.event_enter) return;
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    int64_t ts = blink_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"enter\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"span\":{\"file\":\"%s\",\"line\":%d,\"col\":%d}",
        (long long)ts, fn, module, depth, file, line, col);
    if (args_json && *args_json) {
        fprintf(stderr, ",\"args\":{%s}", args_json);
    }
    fprintf(stderr, "}\n");
    fflush(stderr);
    blink_trace_write_end(&g);
}
#endif

BLINK_RT_FN void blink_trace_exit(const char* fn, const char* module, int depth,
    int64_t enter_ts, const char* ret_str);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_exit(const char* fn, const char* module, int depth,
    int64_t enter_ts, const char* ret_str) {
    if (!__blink_trace.event_exit) return;
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    int64_t ts = blink_trace_ts_us();
    int64_t duration = ts - enter_ts;
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"exit\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"duration_us\":%lld,\"return\":\"",
        (long long)ts, fn, module, depth, (long long)duration);
    if (ret_str) {
        blink_trace_write_escaped(stderr, ret_str, BLINK_TRACE_MAX_VALUE_LEN);
    } else {
        fputs("()", stderr);
    }
    fputs("\"", stderr);
    if (ret_str && blink_trace_str_truncated(ret_str)) {
        fputs(",\"truncated\":true", stderr);
    }
    fputs("}\n", stderr);
    fflush(stderr);
    blink_trace_write_end(&g);
}
#endif

BLINK_RT_FN void blink_trace_state_event(const char* fn, const char* module, int depth,
    const char* var, const char* op, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_state_event(const char* fn, const char* module, int depth,
    const char* var, const char* op, const char* value) {
    if (!__blink_trace.event_state) return;
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    int64_t ts = blink_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"state\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"var\":\"%s\",\"op\":\"%s\",\"value\":\"",
        (long long)ts, fn, module, depth, var, op);
    if (value) {
        blink_trace_write_escaped(stderr, value, BLINK_TRACE_MAX_VALUE_LEN);
    }
    fputs("\"", stderr);
    if (value && blink_trace_str_truncated(value)) {
        fputs(",\"truncated\":true", stderr);
    }
    fputs("}\n", stderr);
    fflush(stderr);
    blink_trace_write_end(&g);
}
#endif

BLINK_RT_FN void blink_trace_effect(const char* fn, const char* module, int depth,
    const char* effect, const char* op, const char* args_json);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_effect(const char* fn, const char* module, int depth,
    const char* effect, const char* op, const char* args_json) {
    if (!__blink_trace.event_effect) return;
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    int64_t ts = blink_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"effect\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"effect\":\"%s\",\"op\":\"%s\"",
        (long long)ts, fn, module, depth, effect, op);
    if (args_json && *args_json) {
        fprintf(stderr, ",\"args\":{%s}", args_json);
    }
    fputs("}\n", stderr);
    fflush(stderr);
    blink_trace_write_end(&g);
}
#endif

/* `arena.promote` and `arena.promote.capture` are not trace events (§8.15.2 lists the event
   types), so these write nothing. They stay because the runtime and the code of an older
   compiler call them. */
BLINK_RT_FN void blink_trace_arena_capture(const char* op, int64_t slot, const char* name);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_arena_capture(const char* op, int64_t slot, const char* name) {
    (void)op; (void)slot; (void)name;
}
#endif

BLINK_RT_FN void blink_trace_arena_promote(const char* fn, const char* module, int depth,
    const char* phase, const char* target, const char* desc,
    const char* file, int line, int col);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_arena_promote(const char* fn, const char* module, int depth,
    const char* phase, const char* target, const char* desc,
    const char* file, int line, int col) {
    (void)fn; (void)module; (void)depth; (void)phase; (void)target; (void)desc;
    (void)file; (void)line; (void)col;
}
#endif

/* The two ends of one promotion, as the code of an older compiler calls them. "begin" runs inside the block,
   where `target` is the arena it was entered from. "end" runs after the block closed,
   where that arena is current again. */
BLINK_RT_FN void blink_trace_arena_promote_begin(const char* fn, const char* module,
    blink_arena_t* target, const char* file, int64_t line, int64_t col);
BLINK_RT_FN void blink_trace_arena_promote_end(const char* fn, const char* module,
    const char* desc, const char* file, int64_t line, int64_t col);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_arena_promote_begin(const char* fn, const char* module,
    blink_arena_t* target, const char* file, int64_t line, int64_t col) {
    blink_trace_arena_promote(fn, module, __blink_trace.depth, "begin",
        target ? "outer arena" : "GC heap", "", file, (int)line, (int)col);
}
BLINK_RT_FN void blink_trace_arena_promote_end(const char* fn, const char* module,
    const char* desc, const char* file, int64_t line, int64_t col) {
    blink_trace_arena_promote(fn, module, __blink_trace.depth, "end",
        __blink_current_arena ? "outer arena" : "GC heap", desc, file, (int)line, (int)col);
}
#endif

/* The events of a traced function. Codegen calls blink_trace_fn_enter first in the body, and
   a cleanup local of the body calls blink_trace_fn_close as the body returns, so the stack
   moves for each traced call, whether or not its events print. Each gate answers whether its event prints, and codegen renders the
   values of an event only then. */

/* Whether one event passes the filters. An event with no effect type answers no to an
   `effect:` filter, and one with no variable answers no to a `state:` filter. */
BLINK_RT_FN int blink_trace_match_event(const char* fn, const char* module, int64_t depth,
    const char* effect, const char* var);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_match_event(const char* fn, const char* module, int64_t depth,
    const char* effect, const char* var) {
    if (__blink_trace_mute_count > 0) return 0;
    if (!blink_trace_match(fn, module, (int)depth)) return 0;
    for (int i = 0; i < __blink_trace.filter_count; i++) {
        blink_trace_filter* f = &__blink_trace.filters[i];
        const char* have = NULL;
        if (strcmp(f->key, "effect") == 0) have = effect;
        else if (strcmp(f->key, "state") == 0) have = var;
        else continue;
        if (!have) return 0;
        int matched = 0;
        for (int j = 0; j < f->count; j++) {
            if (strcmp(have, f->values[j]) == 0) { matched = 1; break; }
        }
        if (!matched) return 0;
    }
    return 1;
}
#endif

/* Writes s as the inside of a JSON string. With max_chars >= 0 it writes at most that many
   characters and answers whether s had more. */
BLINK_RT_FN int blink_trace_put_json(FILE* out, const char* s, int64_t max_chars);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_put_json(FILE* out, const char* s, int64_t max_chars) {
    int64_t chars = 0;
    for (const unsigned char* p = (const unsigned char*)(s ? s : ""); *p; p++) {
        /* A UTF-8 continuation byte is part of the character before it. */
        if ((*p & 0xC0) != 0x80) {
            if (max_chars >= 0 && chars == max_chars) return 1;
            chars++;
        }
        switch (*p) {
            case '"':  fputs("\\\"", out); break;
            case '\\': fputs("\\\\", out); break;
            case '\n': fputs("\\n", out); break;
            case '\r': fputs("\\r", out); break;
            case '\t': fputs("\\t", out); break;
            default:
                if (*p < 0x20) fprintf(out, "\\u%04x", *p);
                else fputc(*p, out);
        }
    }
    return 0;
}
#endif

/* The fields every event starts with. The caller holds the stderr lock. */
BLINK_RT_FN void blink_trace_put_head(const char* event, const char* fn, const char* module,
    int64_t depth);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_put_head(const char* event, const char* fn, const char* module,
    int64_t depth) {
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"%s\",\"fn\":\"", (long long)blink_trace_ts_us(), event);
    blink_trace_put_json(stderr, fn, -1);
    fputs("\",\"module\":\"", stderr);
    blink_trace_put_json(stderr, module, -1);
    fprintf(stderr, "\",\"depth\":%lld", (long long)depth);
}
#endif

BLINK_RT_FN void blink_trace_put_tail(int truncated);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_put_tail(int truncated) {
    if (truncated) fputs(",\"truncated\":true", stderr);
    fputs("}\n", stderr);
    fflush(stderr);
}
#endif

/* The depth of the innermost traced call of this thread. */
BLINK_RT_FN int64_t blink_trace_frame_depth(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_trace_frame_depth(void) {
    return __blink_trace_frame_top > 0 ? __blink_trace_frame_top - 1 : 0;
}
#endif

/* A Display or Debug call that the tracer makes to render a value writes no event (§8.15.9).
   Codegen mutes the thread around each render; a traced call inside it still pushes its
   frame, so the depth of the events after it stays right. */
BLINK_RT_FN void blink_trace_mute(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_mute(void) { __blink_trace_mute_count++; }
#endif

BLINK_RT_FN void blink_trace_unmute(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_unmute(void) { __blink_trace_mute_count--; }
#endif

/* Pushes the call and answers whether its enter event prints. */
BLINK_RT_FN int blink_trace_fn_enter(const char* fn, const char* module);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_fn_enter(const char* fn, const char* module) {
    if (!__blink_trace.active) return 0;
    int64_t depth = __blink_trace_frame_top++;
    if (depth >= __blink_trace_frame_cap) {
        int64_t cap = __blink_trace_frame_cap ? __blink_trace_frame_cap * 2 : 64;
        while (cap <= depth) cap *= 2;
        blink_trace_frame* grown = (blink_trace_frame*)realloc(__blink_trace_frames,
            (size_t)cap * sizeof(blink_trace_frame));
        /* With no room the call still counts for depth; it prints no enter and no exit. */
        if (!grown) return 0;
        /* A call pushed while the stack had no room left its slot unset; the pop reads it. */
        memset(grown + __blink_trace_frame_cap, 0,
            (size_t)(cap - __blink_trace_frame_cap) * sizeof(blink_trace_frame));
        __blink_trace_frames = grown;
        __blink_trace_frame_cap = cap;
    }
    int matched = blink_trace_match_event(fn, module, depth, NULL, NULL);
    __blink_trace_frames[depth].matched = matched;
    __blink_trace_frames[depth].enter_ts = blink_trace_ts_us();
    __blink_trace_frames[depth].fn = fn;
    __blink_trace_frames[depth].module = module;
    __blink_trace_frames[depth].exit_value = NULL;
    __blink_trace_frames[depth].exit_kept = 0;
    return matched && __blink_trace.event_enter;
}
#endif

/* The enter event, after its gate. The variadic part is n pairs of (name, value) C strings. */
BLINK_RT_FN void blink_trace_enter_event(const char* fn, const char* module, const char* file,
    int64_t line, int64_t col, int64_t n, ...);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_enter_event(const char* fn, const char* module, const char* file,
    int64_t line, int64_t col, int64_t n, ...) {
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    blink_trace_put_head("enter", fn, module, blink_trace_frame_depth());
    fputs(",\"span\":{\"file\":\"", stderr);
    blink_trace_put_json(stderr, file, -1);
    fprintf(stderr, "\",\"line\":%lld,\"col\":%lld}", (long long)line, (long long)col);
    int truncated = 0;
    va_list ap;
    va_start(ap, n);
    for (int64_t i = 0; i < n; i++) {
        const char* name = va_arg(ap, const char*);
        const char* value = va_arg(ap, const char*);
        fputs(i == 0 ? ",\"args\":{\"" : ",\"", stderr);
        blink_trace_put_json(stderr, name, -1);
        fputs("\":\"", stderr);
        truncated |= blink_trace_put_json(stderr, value, BLINK_TRACE_MAX_VALUE_LEN);
        fputs("\"", stderr);
    }
    va_end(ap);
    if (n > 0) fputs("}", stderr);
    blink_trace_put_tail(truncated);
    blink_trace_write_end(&g);
}
#endif

/* Whether the exit event of the innermost traced call prints. */
BLINK_RT_FN int blink_trace_on_exit(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_on_exit(void) {
    if (!__blink_trace.active || !__blink_trace.event_exit) return 0;
    int64_t depth = __blink_trace_frame_top - 1;
    if (depth < 0 || depth >= __blink_trace_frame_cap) return 0;
    return __blink_trace_frames[depth].matched;
}
#endif

/* The exit event, after its gate. A NULL value is the exit of a function with no result. */
BLINK_RT_FN void blink_trace_exit_event(const char* fn, const char* module, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_exit_event(const char* fn, const char* module, const char* value) {
    int64_t depth = blink_trace_frame_depth();
    int64_t duration = blink_trace_ts_us() - __blink_trace_frames[depth].enter_ts;
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    blink_trace_put_head("exit", fn, module, depth);
    fprintf(stderr, ",\"duration_us\":%lld,\"return\":\"", (long long)duration);
    int truncated = blink_trace_put_json(stderr, value ? value : "()", BLINK_TRACE_MAX_VALUE_LEN);
    fputs("\"", stderr);
    blink_trace_put_tail(truncated);
    blink_trace_write_end(&g);
}
#endif

/* Whether a state event of the innermost traced call prints. */
BLINK_RT_FN int blink_trace_on_state(const char* fn, const char* module, const char* var);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_on_state(const char* fn, const char* module, const char* var) {
    if (!__blink_trace.active || !__blink_trace.event_state || __blink_trace_frame_top <= 0) return 0;
    return blink_trace_match_event(fn, module, blink_trace_frame_depth(), NULL, var);
}
#endif

/* The state event, after its gate. `value` is the Display text of the whole binding after
   the write. */
BLINK_RT_FN void blink_trace_state_emit(const char* fn, const char* module, const char* var,
    const char* op, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_state_emit(const char* fn, const char* module, const char* var,
    const char* op, const char* value) {
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    blink_trace_put_head("state", fn, module, blink_trace_frame_depth());
    fputs(",\"var\":\"", stderr);
    blink_trace_put_json(stderr, var, -1);
    fputs("\",\"op\":\"", stderr);
    blink_trace_put_json(stderr, op, -1);
    fputs("\",\"value\":\"", stderr);
    int truncated = blink_trace_put_json(stderr, value, BLINK_TRACE_MAX_VALUE_LEN);
    fputs("\"", stderr);
    blink_trace_put_tail(truncated);
    blink_trace_write_end(&g);
}
#endif

/* Whether the tracer runs. Std code asks it before each dispatch in a build with or without
   --trace, so the one cost to a program that is not traced is this read. */
static inline int blink_trace_live(void) { return __blink_trace.active; }

/* Whether `value` names the effect `path`, or a parent of it, by whole dot segments. */
BLINK_RT_FN int blink_trace_path_has(const char* path, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_path_has(const char* path, const char* value) {
    size_t v = strlen(value);
    if (v == 0 || strncmp(path, value, v) != 0) return 0;
    return path[v] == '\0' || path[v] == '.';
}
#endif

/* Whether an `effect:` value selects the effect `path` of `module` (§8.15.5). The value can
   name the module first, but the module alone selects nothing. A built-in effect has the
   module "". */
BLINK_RT_FN int blink_trace_effect_selected(const char* module, const char* path, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_effect_selected(const char* module, const char* path, const char* value) {
    if (blink_trace_path_has(path, value)) return 1;
    size_t m = strlen(module);
    return m > 0 && strncmp(value, module, m) == 0 && value[m] == '.'
        && blink_trace_path_has(path, value + m + 1);
}
#endif

/* Whether the effect event of one dispatch prints. The event goes to the innermost traced
   call of this thread (§8.15.10), so a dispatch with no traced call on the stack writes none. */
BLINK_RT_FN int blink_trace_on_effect(const char* module, const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_on_effect(const char* module, const char* path) {
    if (!__blink_trace.active || !__blink_trace.event_effect || __blink_trace_mute_count > 0) return 0;
    int64_t depth = __blink_trace_frame_top - 1;
    if (depth < 0 || depth >= __blink_trace_frame_cap) return 0;
    blink_trace_frame* f = &__blink_trace_frames[depth];
    if (!f->fn || !blink_trace_match(f->fn, f->module, (int)depth)) return 0;
    for (int i = 0; i < __blink_trace.filter_count; i++) {
        blink_trace_filter* flt = &__blink_trace.filters[i];
        if (strcmp(flt->key, "state") == 0) return 0;
        if (strcmp(flt->key, "effect") != 0) continue;
        int matched = 0;
        for (int j = 0; j < flt->count; j++) {
            if (blink_trace_effect_selected(module, path, flt->values[j])) { matched = 1; break; }
        }
        if (!matched) return 0;
    }
    return 1;
}
#endif

/* The effect event, after its gate. The variadic part is n pairs of (name, value) C strings,
   one for each parameter of the operation. */
BLINK_RT_FN void blink_trace_effect_emit(const char* module, const char* path, const char* op,
    int64_t n, ...);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_effect_emit(const char* module, const char* path, const char* op,
    int64_t n, ...) {
    int64_t depth = blink_trace_frame_depth();
    blink_trace_frame* f = &__blink_trace_frames[depth];
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    blink_trace_put_head("effect", f->fn, f->module, depth);
    fputs(",\"effect\":\"", stderr);
    if (*module) {
        blink_trace_put_json(stderr, module, -1);
        fputs(".", stderr);
    }
    blink_trace_put_json(stderr, path, -1);
    fputs("\",\"op\":\"", stderr);
    blink_trace_put_json(stderr, op, -1);
    fputs("\"", stderr);
    int truncated = 0;
    va_list ap;
    va_start(ap, n);
    for (int64_t i = 0; i < n; i++) {
        const char* name = va_arg(ap, const char*);
        const char* value = va_arg(ap, const char*);
        fputs(i == 0 ? ",\"args\":{\"" : ",\"", stderr);
        blink_trace_put_json(stderr, name, -1);
        fputs("\":\"", stderr);
        truncated |= blink_trace_put_json(stderr, value, BLINK_TRACE_MAX_VALUE_LEN);
        fputs("\"", stderr);
    }
    va_end(ap);
    if (n > 0) fputs("}", stderr);
    blink_trace_put_tail(truncated);
    blink_trace_write_end(&g);
}
#endif

/* Keeps the return text of the innermost traced call, after its exit gate, for the exit
   event. The caller's text may be gone by the time the call is popped, so this copies it. A
   NULL value is the exit of a function with no result. */
BLINK_RT_FN void blink_trace_exit_keep(const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_exit_keep(const char* value) {
    int64_t depth = __blink_trace_frame_top - 1;
    if (depth < 0 || depth >= __blink_trace_frame_cap) return;
    blink_trace_frame* f = &__blink_trace_frames[depth];
    free(f->exit_value);
    f->exit_value = NULL;
    if (value) {
        size_t n = strlen(value) + 1;
        f->exit_value = (char*)malloc(n);
        /* With no room the exit prints no event rather than a wrong value. */
        if (!f->exit_value) return;
        memcpy(f->exit_value, value, n);
    }
    f->exit_kept = 1;
}
#endif

/* The cleanup of a traced body: it runs after the cleanups of the body's inner scopes, so a
   call they make is inside this call. Prints the kept exit event and pops the call. */
BLINK_RT_FN void blink_trace_fn_close(int* unused);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_fn_close(int* unused) {
    (void)unused;
    if (!__blink_trace.active || __blink_trace_frame_top <= 0) return;
    int64_t depth = __blink_trace_frame_top - 1;
    if (depth < __blink_trace_frame_cap) {
        blink_trace_frame* f = &__blink_trace_frames[depth];
        if (f->exit_kept) blink_trace_exit_event(f->fn, f->module, f->exit_value);
        free(f->exit_value);
        f->exit_value = NULL;
        f->exit_kept = 0;
    }
    __blink_trace_frame_top--;
}
#endif

#endif /* BLINK_RUNTIME_TRACE_H */
