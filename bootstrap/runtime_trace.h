#ifndef BLINK_RUNTIME_TRACE_H
#define BLINK_RUNTIME_TRACE_H

#define BLINK_TRACE_MAX_FILTERS 16
#define BLINK_TRACE_MAX_OR_VALUES 8
#define BLINK_TRACE_MAX_VALUE_LEN 200

typedef struct {
    char key[32];
    char values[BLINK_TRACE_MAX_OR_VALUES][128];
    int count;
} blink_trace_filter;

typedef struct {
    int active;
    int depth;
    struct timespec start;
    blink_trace_filter filters[BLINK_TRACE_MAX_FILTERS];
    int filter_count;
    int event_enter;
    int event_exit;
    int event_effect;
    int event_state;
    int event_limit;
    int event_count;
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

/* One traced call on this thread's stack: when it began, and whether the filters chose its
   enter and exit events. The exit reads both, so the two events of one call always pair.
   Depth is the call stack depth of a thread, so the stack is per thread. */
typedef struct {
    int64_t enter_ts;
    int matched;
} blink_trace_frame;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    __thread blink_trace_frame* __blink_trace_frames = NULL;
    __thread int64_t __blink_trace_frame_cap = 0;
    __thread int64_t __blink_trace_frame_top = 0;
  #else
    extern __thread blink_trace_frame* __blink_trace_frames;
    extern __thread int64_t __blink_trace_frame_cap;
    extern __thread int64_t __blink_trace_frame_top;
  #endif
#else
BLINK_UNUSED static __thread blink_trace_frame* __blink_trace_frames = NULL;
BLINK_UNUSED static __thread int64_t __blink_trace_frame_cap = 0;
BLINK_UNUSED static __thread int64_t __blink_trace_frame_top = 0;
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

BLINK_RT_FN void blink_trace_parse_filters(const char* filter_str);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_parse_filters(const char* filter_str) {
    if (!filter_str || !*filter_str) return;
    __blink_trace.event_enter = 1;
    __blink_trace.event_exit = 1;
    const char* p = filter_str;
    while (*p && __blink_trace.filter_count < BLINK_TRACE_MAX_FILTERS) {
        blink_trace_filter* f = &__blink_trace.filters[__blink_trace.filter_count];
        const char* colon = p;
        while (*colon && *colon != ':' && *colon != ',') colon++;
        if (*colon != ':') break;
        int klen = (int)(colon - p);
        if (klen >= 32) klen = 31;
        memcpy(f->key, p, klen);
        f->key[klen] = '\0';
        p = colon + 1;
        f->count = 0;
        while (f->count < BLINK_TRACE_MAX_OR_VALUES) {
            const char* end = p;
            while (*end && *end != '+' && *end != ',') end++;
            int vlen = (int)(end - p);
            if (vlen >= 128) vlen = 127;
            memcpy(f->values[f->count], p, vlen);
            f->values[f->count][vlen] = '\0';
            f->count++;
            if (*end == '+') { p = end + 1; continue; }
            p = (*end == ',') ? end + 1 : end;
            break;
        }
        if (strcmp(f->key, "event") == 0) {
            __blink_trace.event_enter = 0;
            __blink_trace.event_exit = 0;
            __blink_trace.event_effect = 0;
            __blink_trace.event_state = 0;
            for (int i = 0; i < f->count; i++) {
                if (strcmp(f->values[i], "enter") == 0) __blink_trace.event_enter = 1;
                if (strcmp(f->values[i], "exit") == 0) __blink_trace.event_exit = 1;
                if (strcmp(f->values[i], "effect") == 0) __blink_trace.event_effect = 1;
                if (strcmp(f->values[i], "state") == 0) __blink_trace.event_state = 1;
            }
            continue;
        }
        __blink_trace.filter_count++;
    }
}
#endif

BLINK_RT_FN void blink_trace_init(int argc, char** argv);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_init(int argc, char** argv) {
    __blink_trace.active = 0;
    __blink_trace.depth = 0;
    __blink_trace.filter_count = 0;
    __blink_trace.event_enter = 1;
    __blink_trace.event_exit = 1;
    __blink_trace.event_effect = 1;
    __blink_trace.event_state = 1;
    __blink_trace.event_limit = 0;
    __blink_trace.event_count = 0;
#ifndef BLINK_NO_TRACE_INIT
    const char* filter_str = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--trace") == 0) {
            __blink_trace.active = 1;
        } else if (strncmp(argv[i], "--trace=", 8) == 0) {
            __blink_trace.active = 1;
            filter_str = argv[i] + 8;
        } else if (strcmp(argv[i], "--trace-limit") == 0 && i + 1 < argc) {
            __blink_trace.event_limit = atoi(argv[++i]);
        } else if (strncmp(argv[i], "--trace-limit=", 14) == 0) {
            __blink_trace.event_limit = atoi(argv[i] + 14);
        }
    }
    if (!__blink_trace.active) {
        const char* env = getenv("BLINK_TRACE");
        if (env && *env) {
            __blink_trace.active = 1;
            filter_str = (strcmp(env, "1") == 0) ? NULL : env;
        }
    }
    if (!__blink_trace.event_limit) {
        const char* limit_env = getenv("BLINK_TRACE_LIMIT");
        if (limit_env && *limit_env) {
            __blink_trace.event_limit = atoi(limit_env);
        }
    }
    if (__blink_trace.active) {
        clock_gettime(CLOCK_MONOTONIC, &__blink_trace.start);
        if (filter_str) blink_trace_parse_filters(filter_str);
    }
#else
    (void)argc; (void)argv;
#endif
}
#endif

BLINK_RT_FN int blink_trace_match(const char* fn, const char* module, int depth);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_match(const char* fn, const char* module, int depth) {
    if (!__blink_trace.active) return 0;
    if (__blink_trace.filter_count == 0) return 1;
    for (int i = 0; i < __blink_trace.filter_count; i++) {
        blink_trace_filter* f = &__blink_trace.filters[i];
        if (strcmp(f->key, "fn") == 0) {
            const char* dot = strrchr(fn, '.');
            const char* short_name = dot ? dot + 1 : fn;
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if (strcmp(fn, f->values[j]) == 0 || strcmp(short_name, f->values[j]) == 0) {
                    matched = 1; break;
                }
            }
            if (!matched) return 0;
        } else if (strcmp(f->key, "module") == 0) {
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if (strcmp(module, f->values[j]) == 0) { matched = 1; break; }
            }
            if (!matched) return 0;
        } else if (strcmp(f->key, "depth") == 0) {
            int max_depth = atoi(f->values[0]);
            if (depth > max_depth) return 0;
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
    if (__blink_trace.event_limit > 0 && __blink_trace.event_count >= __blink_trace.event_limit) return;
    __blink_trace.event_count++;
    int64_t ts = blink_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"enter\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"span\":{\"file\":\"%s\",\"line\":%d,\"col\":%d}",
        (long long)ts, fn, module, depth, file, line, col);
    if (args_json && *args_json) {
        fprintf(stderr, ",\"args\":{%s}", args_json);
    }
    fprintf(stderr, "}\n");
    fflush(stderr);
}
#endif

BLINK_RT_FN void blink_trace_exit(const char* fn, const char* module, int depth,
    int64_t enter_ts, const char* ret_str);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_exit(const char* fn, const char* module, int depth,
    int64_t enter_ts, const char* ret_str) {
    if (!__blink_trace.event_exit) return;
    if (__blink_trace.event_limit > 0 && __blink_trace.event_count >= __blink_trace.event_limit) return;
    __blink_trace.event_count++;
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
}
#endif

BLINK_RT_FN void blink_trace_state_event(const char* fn, const char* module, int depth,
    const char* var, const char* op, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_state_event(const char* fn, const char* module, int depth,
    const char* var, const char* op, const char* value) {
    if (!__blink_trace.event_state) return;
    if (__blink_trace.event_limit > 0 && __blink_trace.event_count >= __blink_trace.event_limit) return;
    __blink_trace.event_count++;
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
}
#endif

BLINK_RT_FN void blink_trace_effect(const char* fn, const char* module, int depth,
    const char* effect, const char* op, const char* args_json);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_effect(const char* fn, const char* module, int depth,
    const char* effect, const char* op, const char* args_json) {
    if (!__blink_trace.event_effect) return;
    if (__blink_trace.event_limit > 0 && __blink_trace.event_count >= __blink_trace.event_limit) return;
    __blink_trace.event_count++;
    int64_t ts = blink_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"effect\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"effect\":\"%s\",\"op\":\"%s\"",
        (long long)ts, fn, module, depth, effect, op);
    if (args_json && *args_json) {
        fprintf(stderr, ",\"args\":{%s}", args_json);
    }
    fputs("}\n", stderr);
    fflush(stderr);
}
#endif

// Emitted by the runtime for each capture of a closure promoted out of `with arena`,
// between the begin and end events of that promotion, which carry the fn and span.
// `op` says how the capture moved: "cell" (a `let mut` cell copied), "walk" (the value
// copied by its walker), "word" (kept as is) or "refused" (no walker; a panic follows).
BLINK_RT_FN void blink_trace_arena_capture(const char* op, int64_t slot, const char* name);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_arena_capture(const char* op, int64_t slot, const char* name) {
    if (!__blink_trace.active) return;
    if (__blink_trace.event_limit > 0 && __blink_trace.event_count >= __blink_trace.event_limit) return;
    __blink_trace.event_count++;
    int64_t ts = blink_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"arena.promote.capture\",\"depth\":%d,"
        "\"op\":\"%s\",\"slot\":%lld,\"capture\":\"%s\"}\n",
        (long long)ts, __blink_trace.depth, op, (long long)slot, name ? name : "");
    fflush(stderr);
}
#endif

// Emitted by codegen at the closing `}` of a `with arena { expr }` block.
// `phase` is "begin" (pre-promotion, inner arena still live) or "end"
// (post-promotion, inner arena destroyed). `target` is the human-readable
// promotion target — either "outer arena" or "GC heap". `desc` is the
// promoted tail's type descriptor (e.g. "P:Int", "S:MyStruct", "C:<hash>").
BLINK_RT_FN void blink_trace_arena_promote(const char* fn, const char* module, int depth,
    const char* phase, const char* target, const char* desc,
    const char* file, int line, int col);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_arena_promote(const char* fn, const char* module, int depth,
    const char* phase, const char* target, const char* desc,
    const char* file, int line, int col) {
    if (!__blink_trace.active) return;
    if (__blink_trace.event_limit > 0 && __blink_trace.event_count >= __blink_trace.event_limit) return;
    __blink_trace.event_count++;
    int64_t ts = blink_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"arena.promote\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"phase\":\"%s\",\"target\":\"%s\",\"desc\":\"%s\","
        "\"span\":{\"file\":\"%s\",\"line\":%d,\"col\":%d}}\n",
        (long long)ts, fn, module, depth, phase, target ? target : "",
        desc ? desc : "", file ? file : "", line, col);
    fflush(stderr);
}
#endif

/* The two ends of one promotion, as codegen calls them. "begin" runs inside the block,
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

/* The events of a traced function. Codegen calls blink_trace_fn_enter first in the body and
   blink_trace_fn_leave at each exit, so the stack moves for each traced call, whether or not
   its events print. Each gate answers whether its event prints, and codegen renders the
   values of an event only then. */

/* Whether one event passes the filters. An event with no effect type answers no to an
   `effect:` filter, and one with no variable answers no to a `state:` filter. */
BLINK_RT_FN int blink_trace_match_event(const char* fn, const char* module, int64_t depth,
    const char* effect, const char* var);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_match_event(const char* fn, const char* module, int64_t depth,
    const char* effect, const char* var) {
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

BLINK_RT_FN int blink_trace_under_limit(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_under_limit(void) {
    return __blink_trace.event_limit <= 0 || __blink_trace.event_count < __blink_trace.event_limit;
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
    __blink_trace.event_count++;
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

/* Pushes the call and answers whether its enter event prints. */
BLINK_RT_FN int blink_trace_fn_enter(const char* fn, const char* module);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_fn_enter(const char* fn, const char* module) {
    if (!__blink_trace.active) return 0;
    int64_t depth = __blink_trace_frame_top++;
    if (depth >= __blink_trace_frame_cap) {
        int64_t cap = __blink_trace_frame_cap ? __blink_trace_frame_cap * 2 : 64;
        blink_trace_frame* grown = (blink_trace_frame*)realloc(__blink_trace_frames,
            (size_t)cap * sizeof(blink_trace_frame));
        /* With no room the call still counts for depth; it prints no enter and no exit. */
        if (!grown) return 0;
        __blink_trace_frames = grown;
        __blink_trace_frame_cap = cap;
    }
    int matched = blink_trace_match_event(fn, module, depth, NULL, NULL);
    __blink_trace_frames[depth].matched = matched;
    __blink_trace_frames[depth].enter_ts = blink_trace_ts_us();
    return matched && __blink_trace.event_enter && blink_trace_under_limit();
}
#endif

/* The enter event, after its gate. The variadic part is n pairs of (name, value) C strings. */
BLINK_RT_FN void blink_trace_enter_event(const char* fn, const char* module, const char* file,
    int64_t line, int64_t col, int64_t n, ...);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_enter_event(const char* fn, const char* module, const char* file,
    int64_t line, int64_t col, int64_t n, ...) {
    flockfile(stderr);
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
    funlockfile(stderr);
}
#endif

/* Whether the exit event of the innermost traced call prints. */
BLINK_RT_FN int blink_trace_on_exit(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_on_exit(void) {
    if (!__blink_trace.active || !__blink_trace.event_exit) return 0;
    int64_t depth = __blink_trace_frame_top - 1;
    if (depth < 0 || depth >= __blink_trace_frame_cap) return 0;
    return __blink_trace_frames[depth].matched && blink_trace_under_limit();
}
#endif

/* The exit event, after its gate. A NULL value is the exit of a function with no result. */
BLINK_RT_FN void blink_trace_exit_event(const char* fn, const char* module, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_exit_event(const char* fn, const char* module, const char* value) {
    int64_t depth = blink_trace_frame_depth();
    int64_t duration = blink_trace_ts_us() - __blink_trace_frames[depth].enter_ts;
    flockfile(stderr);
    blink_trace_put_head("exit", fn, module, depth);
    fprintf(stderr, ",\"duration_us\":%lld,\"return\":\"", (long long)duration);
    int truncated = blink_trace_put_json(stderr, value ? value : "()", BLINK_TRACE_MAX_VALUE_LEN);
    fputs("\"", stderr);
    blink_trace_put_tail(truncated);
    funlockfile(stderr);
}
#endif

/* Pops the call, at each exit of a traced function. */
BLINK_RT_FN void blink_trace_fn_leave(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_fn_leave(void) {
    if (__blink_trace.active && __blink_trace_frame_top > 0) __blink_trace_frame_top--;
}
#endif

#endif /* BLINK_RUNTIME_TRACE_H */
