#ifndef BLINK_RUNTIME_TRACE_H
#define BLINK_RUNTIME_TRACE_H

#define BLINK_TRACE_MAX_FILTERS 16
#define BLINK_TRACE_MAX_OR_VALUES 8
#define BLINK_TRACE_MAX_VALUE_LEN 200

typedef struct {
    char key[32];
    char values[BLINK_TRACE_MAX_OR_VALUES][128];
    int count;
} pact_trace_filter;

typedef struct {
    int active;
    int depth;
    struct timespec start;
    pact_trace_filter filters[BLINK_TRACE_MAX_FILTERS];
    int filter_count;
    int event_enter;
    int event_exit;
    int event_effect;
    int event_state;
    int event_limit;
    int event_count;
} pact_trace_state;

static pact_trace_state __pact_trace = {0};

BLINK_UNUSED static int64_t pact_trace_ts_us(void) {
    struct timespec now;
#ifdef __APPLE__
    clock_gettime(CLOCK_MONOTONIC, &now);
#else
    clock_gettime(CLOCK_MONOTONIC, &now);
#endif
    int64_t sec_diff = (int64_t)(now.tv_sec - __pact_trace.start.tv_sec);
    int64_t nsec_diff = (int64_t)(now.tv_nsec - __pact_trace.start.tv_nsec);
    return sec_diff * 1000000 + nsec_diff / 1000;
}

BLINK_UNUSED static void pact_trace_parse_filters(const char* filter_str) {
    if (!filter_str || !*filter_str) return;
    __pact_trace.event_enter = 1;
    __pact_trace.event_exit = 1;
    const char* p = filter_str;
    while (*p && __pact_trace.filter_count < BLINK_TRACE_MAX_FILTERS) {
        pact_trace_filter* f = &__pact_trace.filters[__pact_trace.filter_count];
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
            __pact_trace.event_enter = 0;
            __pact_trace.event_exit = 0;
            __pact_trace.event_effect = 0;
            __pact_trace.event_state = 0;
            for (int i = 0; i < f->count; i++) {
                if (strcmp(f->values[i], "enter") == 0) __pact_trace.event_enter = 1;
                if (strcmp(f->values[i], "exit") == 0) __pact_trace.event_exit = 1;
                if (strcmp(f->values[i], "effect") == 0) __pact_trace.event_effect = 1;
                if (strcmp(f->values[i], "state") == 0) __pact_trace.event_state = 1;
            }
            continue;
        }
        __pact_trace.filter_count++;
    }
}

BLINK_UNUSED static void pact_trace_init(int argc, char** argv) {
    __pact_trace.active = 0;
    __pact_trace.depth = 0;
    __pact_trace.filter_count = 0;
    __pact_trace.event_enter = 1;
    __pact_trace.event_exit = 1;
    __pact_trace.event_effect = 1;
    __pact_trace.event_state = 1;
    __pact_trace.event_limit = 0;
    __pact_trace.event_count = 0;
#ifndef BLINK_NO_TRACE_INIT
    const char* filter_str = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--trace") == 0) {
            __pact_trace.active = 1;
        } else if (strncmp(argv[i], "--trace=", 8) == 0) {
            __pact_trace.active = 1;
            filter_str = argv[i] + 8;
        } else if (strcmp(argv[i], "--trace-limit") == 0 && i + 1 < argc) {
            __pact_trace.event_limit = atoi(argv[++i]);
        } else if (strncmp(argv[i], "--trace-limit=", 14) == 0) {
            __pact_trace.event_limit = atoi(argv[i] + 14);
        }
    }
    if (!__pact_trace.active) {
        const char* env = getenv("BLINK_TRACE");
        if (env && *env) {
            __pact_trace.active = 1;
            filter_str = (strcmp(env, "1") == 0) ? NULL : env;
        }
    }
    if (!__pact_trace.event_limit) {
        const char* limit_env = getenv("BLINK_TRACE_LIMIT");
        if (limit_env && *limit_env) {
            __pact_trace.event_limit = atoi(limit_env);
        }
    }
    if (__pact_trace.active) {
        clock_gettime(CLOCK_MONOTONIC, &__pact_trace.start);
        if (filter_str) pact_trace_parse_filters(filter_str);
    }
#else
    (void)argc; (void)argv;
#endif
}

BLINK_UNUSED static int pact_trace_match(const char* fn, const char* module, int depth) {
    if (!__pact_trace.active) return 0;
    if (__pact_trace.filter_count == 0) return 1;
    for (int i = 0; i < __pact_trace.filter_count; i++) {
        pact_trace_filter* f = &__pact_trace.filters[i];
        if (strcmp(f->key, "fn") == 0) {
            int matched = 0;
            for (int j = 0; j < f->count; j++) {
                if (strcmp(fn, f->values[j]) == 0 || strcmp(fn + strlen(fn) - strlen(f->values[j]),
                    f->values[j]) == 0) {
                    const char* short_name = fn;
                    const char* dot = strrchr(fn, '.');
                    if (dot) short_name = dot + 1;
                    if (strcmp(short_name, f->values[j]) == 0 || strcmp(fn, f->values[j]) == 0) {
                        matched = 1; break;
                    }
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

BLINK_UNUSED static int pact_trace_match_effect(const char* fn, const char* module, int depth, const char* effect) {
    if (!pact_trace_match(fn, module, depth)) return 0;
    for (int i = 0; i < __pact_trace.filter_count; i++) {
        pact_trace_filter* f = &__pact_trace.filters[i];
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

BLINK_UNUSED static int pact_trace_match_state(const char* fn, const char* module, int depth, const char* var) {
    if (!pact_trace_match(fn, module, depth)) return 0;
    for (int i = 0; i < __pact_trace.filter_count; i++) {
        pact_trace_filter* f = &__pact_trace.filters[i];
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

BLINK_UNUSED static void pact_trace_write_escaped(FILE* out, const char* s, int max_len) {
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

BLINK_UNUSED static int pact_trace_str_truncated(const char* s) {
    int len = 0;
    while (s[len]) { len++; if (len > BLINK_TRACE_MAX_VALUE_LEN) return 1; }
    return 0;
}

BLINK_UNUSED static void pact_trace_enter(const char* fn, const char* module, int depth,
    const char* file, int line, int col, const char* args_json) {
    if (!__pact_trace.event_enter) return;
    if (__pact_trace.event_limit > 0 && __pact_trace.event_count >= __pact_trace.event_limit) return;
    __pact_trace.event_count++;
    int64_t ts = pact_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"enter\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"span\":{\"file\":\"%s\",\"line\":%d,\"col\":%d}",
        (long long)ts, fn, module, depth, file, line, col);
    if (args_json && *args_json) {
        fprintf(stderr, ",\"args\":{%s}", args_json);
    }
    fprintf(stderr, "}\n");
    fflush(stderr);
}

BLINK_UNUSED static void pact_trace_exit(const char* fn, const char* module, int depth,
    int64_t enter_ts, const char* ret_str) {
    if (!__pact_trace.event_exit) return;
    if (__pact_trace.event_limit > 0 && __pact_trace.event_count >= __pact_trace.event_limit) return;
    __pact_trace.event_count++;
    int64_t ts = pact_trace_ts_us();
    int64_t duration = ts - enter_ts;
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"exit\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"duration_us\":%lld,\"return\":\"",
        (long long)ts, fn, module, depth, (long long)duration);
    if (ret_str) {
        pact_trace_write_escaped(stderr, ret_str, BLINK_TRACE_MAX_VALUE_LEN);
    } else {
        fputs("()", stderr);
    }
    fputs("\"", stderr);
    if (ret_str && pact_trace_str_truncated(ret_str)) {
        fputs(",\"truncated\":true", stderr);
    }
    fputs("}\n", stderr);
    fflush(stderr);
}

BLINK_UNUSED static void pact_trace_state_event(const char* fn, const char* module, int depth,
    const char* var, const char* op, const char* value) {
    if (!__pact_trace.event_state) return;
    if (__pact_trace.event_limit > 0 && __pact_trace.event_count >= __pact_trace.event_limit) return;
    __pact_trace.event_count++;
    int64_t ts = pact_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"state\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"var\":\"%s\",\"op\":\"%s\",\"value\":\"",
        (long long)ts, fn, module, depth, var, op);
    if (value) {
        pact_trace_write_escaped(stderr, value, BLINK_TRACE_MAX_VALUE_LEN);
    }
    fputs("\"", stderr);
    if (value && pact_trace_str_truncated(value)) {
        fputs(",\"truncated\":true", stderr);
    }
    fputs("}\n", stderr);
    fflush(stderr);
}

BLINK_UNUSED static void pact_trace_effect(const char* fn, const char* module, int depth,
    const char* effect, const char* op, const char* args_json) {
    if (!__pact_trace.event_effect) return;
    if (__pact_trace.event_limit > 0 && __pact_trace.event_count >= __pact_trace.event_limit) return;
    __pact_trace.event_count++;
    int64_t ts = pact_trace_ts_us();
    fprintf(stderr, "{\"ts_us\":%lld,\"event\":\"effect\",\"fn\":\"%s\",\"module\":\"%s\",\"depth\":%d,"
        "\"effect\":\"%s\",\"op\":\"%s\"",
        (long long)ts, fn, module, depth, effect, op);
    if (args_json && *args_json) {
        fprintf(stderr, ",\"args\":{%s}", args_json);
    }
    fputs("}\n", stderr);
    fflush(stderr);
}

#endif /* BLINK_RUNTIME_TRACE_H */
