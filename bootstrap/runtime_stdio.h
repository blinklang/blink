#ifndef BLINK_RUNTIME_STDIO_H
#define BLINK_RUNTIME_STDIO_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <pthread.h>
#include <unistd.h>
#include <poll.h>

/* The one reader of standard input. io.read_bytes, io.read_line and io.read_all all take
   bytes from the front of this buffer, so any mix of calls sees one stream in order. Bytes in
   [start, end) came from fd 0 and are not given out yet; `taken` counts the bytes given out,
   so a panic can say where in the input it stopped. The buffer is libc memory: it outlives
   every arena, and it holds no pointer the GC must see. End of input is not remembered: a
   read that finds the buffer empty asks fd 0 again, as the derived bodies of §4.4.9 would. */
typedef struct {
    uint8_t* data;
    int64_t start;
    int64_t end;
    int64_t cap;
    int64_t taken;
} blink_stdin_reader_t;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_stdin_reader_t blink_stdin_reader = {0};
    pthread_mutex_t blink_stdin_mu = PTHREAD_MUTEX_INITIALIZER;
  #else
    extern blink_stdin_reader_t blink_stdin_reader;
    extern pthread_mutex_t blink_stdin_mu;
  #endif
#else
static blink_stdin_reader_t blink_stdin_reader = {0};
static pthread_mutex_t blink_stdin_mu = PTHREAD_MUTEX_INITIALIZER;
#endif

#define BLINK_STDIN_CHUNK 65536

/* Gives out the next n buffered bytes. A drained buffer starts again at offset 0, and one
   that a large read grew goes back to the system, so a read_all of a big input does not
   hold that memory for the life of the process. */
BLINK_RT_FN void blink_stdin_advance(int64_t n);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_stdin_advance(int64_t n) {
    blink_stdin_reader_t* r = &blink_stdin_reader;
    r->start += n;
    r->taken += n;
    if (r->start < r->end) return;
    r->start = 0;
    r->end = 0;
    if (r->cap > 4 * BLINK_STDIN_CHUNK) {
        free(r->data);
        r->data = NULL;
        r->cap = 0;
    }
}
#endif

/* Reads more of fd 0 onto the end of the buffer. Returns the count read, or 0 at end of
   input. The caller holds blink_stdin_mu; a read failure drops it, then panics and names op. */
BLINK_RT_FN int64_t blink_stdin_fill(const char* op);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_stdin_fill(const char* op) {
    blink_stdin_reader_t* r = &blink_stdin_reader;
    if (r->cap - r->end < BLINK_STDIN_CHUNK && r->start > 0) {
        memmove(r->data, r->data + r->start, (size_t)(r->end - r->start));
        r->end -= r->start;
        r->start = 0;
    }
    if (r->cap - r->end < BLINK_STDIN_CHUNK) {
        int64_t cap = r->cap > 0 ? r->cap : BLINK_STDIN_CHUNK;
        while (cap - r->end < BLINK_STDIN_CHUNK) cap *= 2;
        uint8_t* grown = (uint8_t*)realloc(r->data, (size_t)cap);
        if (!grown) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
        r->data = grown;
        r->cap = cap;
    }
    for (;;) {
        ssize_t got = read(0, r->data + r->end, (size_t)(r->cap - r->end));
        if (got >= 0) {
            r->end += (int64_t)got;
            return (int64_t)got;
        }
        if (errno == EINTR) continue;
        /* A parent can hand over fd 0 set not to block; a read still waits for input. */
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            struct pollfd pfd = { 0, POLLIN, 0 };
            if (poll(&pfd, 1, -1) >= 0 || errno == EINTR) continue;
        }
        int err = errno;
        pthread_mutex_unlock(&blink_stdin_mu);
        __blink_panic_dispatchf("%s: cannot read standard input: %s (errno %d)",
                                op, blink_strerror(err), err);
    }
}
#endif

/* Gives out the next n buffered bytes as a Str, after the UTF-8 check that Bytes.to_str makes,
   then skips `skip` more, and drops blink_stdin_mu. The bytes are taken even when the check
   fails, as the derived bodies take them. The Str is on the GC heap: a line read inside
   `with arena` is not an allocation of that block. */
BLINK_RT_FN const char* blink_stdin_take_text(const char* op, int64_t n, int64_t skip);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_stdin_take_text(const char* op, int64_t n, int64_t skip) {
    blink_stdin_reader_t* r = &blink_stdin_reader;
    const uint8_t* p = r->data + r->start;
    const char* why = NULL;
    int64_t bad = blink_utf8_bad_offset(p, n, &why);
    int64_t at = r->taken;
    const char* s = bad < 0 ? blink_str_from_bytes_gc((const char*)p, n) : NULL;
    blink_stdin_advance(n + skip);
    pthread_mutex_unlock(&blink_stdin_mu);
    if (bad >= 0) {
        __blink_panic_dispatchf("%s: input is not valid UTF-8; read it with io.read_bytes "
                                "(%s at byte %lld of the input)", op, why, (long long)(at + bad));
    }
    return s;
}
#endif

/* Exactly n bytes, or fewer only at end of input; empty at end of input. */
BLINK_RT_FN blink_bytes* blink_stdin_read_bytes(int64_t n);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_bytes* blink_stdin_read_bytes(int64_t n) {
    if (n <= 0) {
        __blink_panic_dispatchf("io.read_bytes: n must be at least 1, got %lld", (long long)n);
    }
    blink_stdin_reader_t* r = &blink_stdin_reader;
    pthread_mutex_lock(&blink_stdin_mu);
    while (r->end - r->start < n && blink_stdin_fill("io.read_bytes") > 0) {}
    int64_t take = r->end - r->start < n ? r->end - r->start : n;
    blink_bytes* b = blink_bytes_new();
    if (take > b->cap) {
        b->data = (uint8_t*)blink_realloc_in(b->owner, b->data, b->cap, take);
        b->cap = take;
    }
    if (take > 0) memcpy(b->data, r->data + r->start, (size_t)take);
    b->len = take;
    blink_stdin_advance(take);
    pthread_mutex_unlock(&blink_stdin_mu);
    return b;
}
#endif

/* The next line without its `\n` or `\r\n`, or NULL at end of input. */
BLINK_RT_FN const char* blink_stdin_read_line(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_stdin_read_line(void) {
    blink_stdin_reader_t* r = &blink_stdin_reader;
    pthread_mutex_lock(&blink_stdin_mu);
    int64_t scanned = 0;
    for (;;) {
        int64_t have = r->end - r->start;
        const uint8_t* nl = have > scanned
            ? (const uint8_t*)memchr(r->data + r->start + scanned, '\n', (size_t)(have - scanned))
            : NULL;
        if (nl) {
            int64_t n = (int64_t)(nl - (r->data + r->start));
            int64_t skip = 1;
            if (n > 0 && r->data[r->start + n - 1] == '\r') { n--; skip = 2; }
            return blink_stdin_take_text("io.read_line", n, skip);
        }
        scanned = have;
        if (blink_stdin_fill("io.read_line") == 0) {
            if (r->end == r->start) {
                pthread_mutex_unlock(&blink_stdin_mu);
                return NULL;
            }
            return blink_stdin_take_text("io.read_line", r->end - r->start, 0);
        }
    }
}
#endif

/* All of the input that is left; empty at end of input. */
BLINK_RT_FN const char* blink_stdin_read_all(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_stdin_read_all(void) {
    pthread_mutex_lock(&blink_stdin_mu);
    while (blink_stdin_fill("io.read_all") > 0) {}
    return blink_stdin_take_text("io.read_all", blink_stdin_reader.end - blink_stdin_reader.start, 0);
}
#endif

/* Write string to stdout with immediate flush */
BLINK_RT_FN void blink_stdout_write(const char* data);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_stdout_write(const char* data) {
    size_t len = strlen(data);
    fwrite(data, 1, len, stdout);
    fflush(stdout);
}
#endif

/* Write bytes to stdout with immediate flush */
BLINK_RT_FN void blink_stdout_write_bytes(blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_stdout_write_bytes(blink_bytes* b) {
    fwrite(b->data, 1, (size_t)b->len, stdout);
    fflush(stdout);
}
#endif

#endif /* BLINK_RUNTIME_STDIO_H */
