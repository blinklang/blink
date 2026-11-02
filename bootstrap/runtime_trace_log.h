#ifndef BLINK_RUNTIME_TRACE_LOG_H
#define BLINK_RUNTIME_TRACE_LOG_H

/* `trace.log` reads a Blink Str, so it comes after runtime_core.h; it also reads the
   --trace state and its item parser from runtime_trace.h, which stays free of core. */

/* The channels BLINK_TRACE_CHANNELS turns on for `trace.log` (§8.15.7). The program reads the
   var once, at start, so a later set_var changes nothing; threads only read it after that. */
typedef struct {
    int all;
    char** names;
    size_t* lens;
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
        char** grown = (char**)realloc(__blink_trace_channels.names, (size_t)*cap * sizeof(char*));
        if (!grown) { fputs("error: out of memory reading BLINK_TRACE_CHANNELS\n", stderr); exit(2); }
        __blink_trace_channels.names = grown;
        size_t* lens = (size_t*)realloc(__blink_trace_channels.lens, (size_t)*cap * sizeof(size_t));
        if (!lens) { fputs("error: out of memory reading BLINK_TRACE_CHANNELS\n", stderr); exit(2); }
        __blink_trace_channels.lens = lens;
    }
    __blink_trace_channels.lens[__blink_trace_channels.count] = strlen(item);
    __blink_trace_channels.names[__blink_trace_channels.count++] = item;
}
#endif

/* The items split on `,` only, unlike BLINK_TRACE, and `all` in any place turns on every
   channel. No value is an error. */
BLINK_RT_FN void blink_trace_channels_init(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_channels_init(void) {
    for (int i = 0; i < __blink_trace_channels.count; i++) free(__blink_trace_channels.names[i]);
    free(__blink_trace_channels.names);
    free(__blink_trace_channels.lens);
    __blink_trace_channels.names = NULL;
    __blink_trace_channels.lens = NULL;
    __blink_trace_channels.count = 0;
    __blink_trace_channels.all = 0;
    const char* env = getenv("BLINK_TRACE_CHANNELS");
    if (!env) return;
    int cap = 0;
    blink_trace_each_item(env, ',', "BLINK_TRACE_CHANNELS", blink_trace_take_channel, &cap);
}
#endif

/* A Blink Str may hold a NUL, so a channel compares by its length, not by strcmp; init keeps
   each name's length, as this runs on every trace.log call. */
BLINK_RT_FN int blink_trace_channel_on(const char* ch);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_trace_channel_on(const char* ch) {
    if (__blink_trace_channels.all) return 1;
    size_t n = (size_t)blink_str_len(ch);
    for (int i = 0; i < __blink_trace_channels.count; i++) {
        if (__blink_trace_channels.lens[i] == n && memcmp(__blink_trace_channels.names[i], ch, n) == 0) return 1;
    }
    return 0;
}
#endif

/* One write of the whole line, so a line of one thread never splits around a line of
   another. Under --trace each stderr line must be JSON, so the text line is not written. */
BLINK_RT_FN void blink_trace_note(const char* ch, const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_trace_note(const char* ch, const char* msg) {
    if (__blink_trace.active) return;
    static const char head[] = "[trace:";
    static const char mid[] = "] ";
    size_t hn = sizeof(head) - 1, mn = sizeof(mid) - 1;
    size_t cn = (size_t)blink_str_len(ch), sn = (size_t)blink_str_len(msg);
    size_t total = hn + cn + mn + sn + 1;
    char small[512];
    char* buf = total <= sizeof(small) ? small : (char*)malloc(total);
    if (!buf) { fputs("error: out of memory writing a trace line\n", stderr); exit(2); }
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
