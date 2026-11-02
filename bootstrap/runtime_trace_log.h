#ifndef BLINK_RUNTIME_TRACE_LOG_H
#define BLINK_RUNTIME_TRACE_LOG_H

/* `trace.log` reads a Blink Str, so it comes after runtime_core.h; it also reads the
   --trace state and its item parser from runtime_trace.h, which stays free of core. */

/* A Blink Str may hold a NUL, so a channel compares by its length, not by strcmp; each name
   keeps its length, as the compare runs on every trace.log call. */
typedef struct {
    char* name;
    size_t len;
} blink_trace_channel;

/* The channels BLINK_TRACE_CHANNELS turns on for `trace.log` (§8.15.7). The program reads the
   var once, at start, so a later set_var changes nothing; threads only read it after that. */
typedef struct {
    int all;
    blink_trace_channel* items;
    int count;
} blink_trace_channels_state;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_trace_channels_state __blink_trace_channels = {0};
  #else
    extern blink_trace_channels_state __blink_trace_channels;
  #endif
#else
BLINK_UNUSED static blink_trace_channels_state __blink_trace_channels = {0};
#endif

/* Adds one item of BLINK_TRACE_CHANNELS; `ctx` is the capacity of the name list. */
BLINK_RT_FN void blink_trace_take_channel(char* item, void* ctx);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_take_channel(char* item, void* ctx) {
    int* cap = (int*)ctx;
    if (strcmp(item, "all") == 0) {
        __blink_trace_channels.all = 1;
        free(item);
        return;
    }
    if (__blink_trace_channels.count == *cap) {
        *cap = *cap ? *cap * 2 : 4;
        blink_trace_channel* grown = (blink_trace_channel*)realloc(__blink_trace_channels.items,
            (size_t)*cap * sizeof(blink_trace_channel));
        if (!grown) blink_trace_oom("reading", "BLINK_TRACE_CHANNELS");
        __blink_trace_channels.items = grown;
    }
    blink_trace_channel c = { item, strlen(item) };
    __blink_trace_channels.items[__blink_trace_channels.count++] = c;
}
#endif

/* The items split on `,` only, unlike BLINK_TRACE, and `all` in any place turns on every
   channel. No value is an error. */
BLINK_RT_FN void blink_trace_channels_init(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_channels_init(void) {
    for (int i = 0; i < __blink_trace_channels.count; i++) free(__blink_trace_channels.items[i].name);
    free(__blink_trace_channels.items);
    __blink_trace_channels.items = NULL;
    __blink_trace_channels.count = 0;
    __blink_trace_channels.all = 0;
    const char* env = getenv("BLINK_TRACE_CHANNELS");
    if (!env) return;
    int cap = 0;
    blink_trace_each_item(env, ',', "BLINK_TRACE_CHANNELS", blink_trace_take_channel, &cap);
}
#endif

BLINK_RT_FN int blink_trace_channel_on(const char* ch);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_channel_on(const char* ch) {
    if (__blink_trace_channels.all) return 1;
    size_t n = (size_t)blink_str_len(ch);
    for (int i = 0; i < __blink_trace_channels.count; i++) {
        blink_trace_channel c = __blink_trace_channels.items[i];
        if (c.len == n && memcmp(c.name, ch, n) == 0) return 1;
    }
    return 0;
}
#endif

/* The note event goes to the innermost traced call of this thread (§8.15.3), so a call with
   no traced call on the stack writes none. An effect: or state: filter never selects it:
   it has no effect and no variable. */
BLINK_RT_FN void blink_trace_note_event(const char* ch, const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_note_event(const char* ch, const char* msg) {
    if (!__blink_trace.event_note) return;
    int64_t depth = __blink_trace_frame_top - 1;
    if (depth < 0 || depth >= __blink_trace_frame_cap) return;
    blink_trace_frame* f = &__blink_trace_frames[depth];
    if (!f->fn || !blink_trace_match_event(f->fn, f->module, depth, NULL, NULL)) return;
    blink_trace_write_guard g;
    if (!blink_trace_write_begin(&g)) return;
    blink_trace_put_head("note", f->fn, f->module, depth);
    fputs(",\"channel\":\"", stderr);
    blink_trace_put_json(stderr, ch, -1);
    fputs("\",\"msg\":\"", stderr);
    int truncated = blink_trace_put_json(stderr, msg, BLINK_TRACE_MAX_VALUE_LEN);
    fputs("\"", stderr);
    blink_trace_put_tail(truncated);
    blink_trace_write_end(&g);
}
#endif

/* One write of the whole line, so a line of one thread never splits around a line of
   another. Under --trace each stderr line must be JSON, so a note event takes the place of
   the text line. */
BLINK_RT_FN void blink_trace_note(const char* ch, const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_note(const char* ch, const char* msg) {
    if (__blink_trace.active) {
        blink_trace_note_event(ch, msg);
        return;
    }
    static const char head[] = "[trace:";
    static const char mid[] = "] ";
    size_t hn = sizeof(head) - 1, mn = sizeof(mid) - 1;
    size_t cn = (size_t)blink_str_len(ch), sn = (size_t)blink_str_len(msg);
    size_t total = hn + cn + mn + sn + 1;
    char small[512];
    char* buf = total <= sizeof(small) ? small : (char*)malloc(total);
    if (!buf) blink_trace_oom("writing", "a trace line");
    memcpy(buf, head, hn);
    memcpy(buf + hn, ch, cn);
    memcpy(buf + hn + cn, mid, mn);
    memcpy(buf + hn + cn + mn, msg, sn);
    buf[total - 1] = '\n';
    fwrite(buf, 1, total, stderr);
    if (buf != small) free(buf);
}
#endif

#endif /* BLINK_RUNTIME_TRACE_LOG_H */
