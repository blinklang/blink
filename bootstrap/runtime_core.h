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
#include <setjmp.h>
#include <stdarg.h>
#define GC_THREADS
#include <gc.h>

#ifdef __GNUC__
#define BLINK_UNUSED __attribute__((unused))
#else
#define BLINK_UNUSED
#endif

/* Linkage for runtime helper functions.
 * - Plain build (single-TU): per-TU `static`, --gc-sections strips unused.
 * - Archive monolith: external definitions (one set, linked by all TUs).
 * - Archive header / user TU under archive: declarations only; bodies
 *   guarded by BLINK_RUNTIME_DECLS_ONLY further down. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #define BLINK_RT_FN
  #if !defined(BLINK_RUNTIME_STORAGE_DEFINE)
    #define BLINK_RUNTIME_DECLS_ONLY 1
  #endif
#else
  #define BLINK_RT_FN BLINK_UNUSED static
#endif

#define BLINK_ARENA_DEFAULT_CHUNK_SIZE ((int64_t)(64 * 1024))
#define BLINK_ARENA_ALIGN ((int64_t)16)

/* The header must be GC-scanned (GC_MALLOC) so bdwgc follows `next` and
   `data` during mark. Packing header+payload into one GC_MALLOC_ATOMIC
   allocation — as the original layout did — hides the intra-chunk `next`
   pointer from the scanner, and any collection that fires mid-arena reclaims
   non-head chunks behind the arena's back. Teardown then GC_FREEs
   already-freed large blocks (k6s1nc). The payload stays atomic so user
   bytes don't falsely retain unrelated GC objects. */
typedef struct blink_arena_chunk {
    struct blink_arena_chunk* next;
    char* data;
    int64_t capacity;
    int64_t used;
} blink_arena_chunk;

typedef struct blink_arena_t {
    blink_arena_chunk* head;
    int64_t default_chunk_size;
} blink_arena_t;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    __thread blink_arena_t* __blink_current_arena = NULL;
    uint64_t blink_map_seed = 0;
  #else
    extern __thread blink_arena_t* __blink_current_arena;
    extern uint64_t blink_map_seed;
  #endif
#else
static __thread blink_arena_t* __blink_current_arena = NULL;
static uint64_t blink_map_seed = 0;
#endif

/* ── assert_panics infrastructure (spec §2.20, decisions/assert-panics-semantics.md) ──
 *
 * `assert_panics { ... }` arms a thread-local catch frame. Inside an armed
 * frame, panic sites longjmp to the frame's setjmp landing pad instead of
 * `fprintf; exit(1)`. The state is per-test / thread-local (normative): an
 * armed assert_panics in one task must never catch a sibling task's panic.
 *
 * Cleanup-on-caught-panic: C `__attribute__((cleanup))` does NOT run on
 * `longjmp` (longjmp abandons intervening automatic storage without
 * unwinding). So `with`/`Closeable` resources opened inside an armed body
 * also push a manual cleanup entry; the dispatch runs those entries (with
 * ok=false) BEFORE longjmping. On the non-panic path the ordinary
 * attribute-cleanup runs and pops its own entry (the `done` flag prevents
 * a double exit). This is the actual mechanism behind §2.20's
 * "rolls back on the expected panic" guarantee. */
#define BLINK_PANIC_MSG_SIZE 1024
#define BLINK_PANIC_CLEANUP_MAX 256
/* Secondary cleanup-panic (E0824) buffer. A cleanup body (BlockHandler.exit /
 * Closeable.close) that itself panics during an armed unwind has its message
 * captured here instead of re-entering dispatch; the test runner drains these
 * into the per-test record's `cleanup_warnings[]`. Cap is conservative and
 * drop-past-cap is silent, mirroring the cleanup-stack convention. */
#define BLINK_CLEANUP_WARN_MAX 16
#define BLINK_CLEANUP_WARN_MSG_SIZE 1024

typedef struct {
    void* state;                    /* points at the per-type bh/cl state struct */
    void (*run)(void* state, int ok); /* per-type thunk → <Type>_exit / <Type>_close */
    int* done;                      /* set to 1 once run, by whichever path runs first */
} __blink_panic_cleanup_entry;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    __thread int __blink_panic_armed = 0;
    __thread jmp_buf __blink_panic_jmp;
    __thread char __blink_panic_msg[BLINK_PANIC_MSG_SIZE] = {0};
    __thread __blink_panic_cleanup_entry __blink_panic_cleanup_stack[BLINK_PANIC_CLEANUP_MAX];
    __thread size_t __blink_panic_cleanup_top = 0;
    __thread size_t __blink_panic_cleanup_mark = 0;
    __thread int __blink_in_cleanup_drain = 0;
    __thread jmp_buf __blink_cleanup_thunk_jmp;
    __thread char __blink_cleanup_warnings[BLINK_CLEANUP_WARN_MAX][BLINK_CLEANUP_WARN_MSG_SIZE];
    __thread int __blink_cleanup_warning_count = 0;
    __thread void (*__blink_panic_test_hook)(const char* msg) = NULL;
  #else
    extern __thread int __blink_panic_armed;
    extern __thread jmp_buf __blink_panic_jmp;
    extern __thread char __blink_panic_msg[BLINK_PANIC_MSG_SIZE];
    extern __thread __blink_panic_cleanup_entry __blink_panic_cleanup_stack[BLINK_PANIC_CLEANUP_MAX];
    extern __thread size_t __blink_panic_cleanup_top;
    extern __thread size_t __blink_panic_cleanup_mark;
    extern __thread int __blink_in_cleanup_drain;
    extern __thread jmp_buf __blink_cleanup_thunk_jmp;
    extern __thread char __blink_cleanup_warnings[BLINK_CLEANUP_WARN_MAX][BLINK_CLEANUP_WARN_MSG_SIZE];
    extern __thread int __blink_cleanup_warning_count;
    extern __thread void (*__blink_panic_test_hook)(const char* msg);
  #endif
#else
static __thread int __blink_panic_armed = 0;
static __thread jmp_buf __blink_panic_jmp;
static __thread char __blink_panic_msg[BLINK_PANIC_MSG_SIZE] = {0};
static __thread __blink_panic_cleanup_entry __blink_panic_cleanup_stack[BLINK_PANIC_CLEANUP_MAX];
static __thread size_t __blink_panic_cleanup_top = 0;
static __thread size_t __blink_panic_cleanup_mark = 0;
static __thread int __blink_in_cleanup_drain = 0;
static __thread jmp_buf __blink_cleanup_thunk_jmp;
static __thread char __blink_cleanup_warnings[BLINK_CLEANUP_WARN_MAX][BLINK_CLEANUP_WARN_MSG_SIZE];
static __thread int __blink_cleanup_warning_count = 0;
static __thread void (*__blink_panic_test_hook)(const char* msg) = NULL;
#endif

BLINK_RT_FN size_t __blink_cleanup_depth(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN size_t __blink_cleanup_depth(void) { return __blink_panic_cleanup_top; }
#endif

/* Push a cleanup entry. Only called from emitted with/Closeable setup when
 * __blink_panic_armed is nonzero. Silently drops past the cap (the cap is far
 * beyond any real test's nesting; overflow would only under-clean on a
 * pathological body and never corrupts memory). */
BLINK_RT_FN void __blink_cleanup_push(void* state, void (*run)(void*, int), int* done);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_cleanup_push(void* state, void (*run)(void*, int), int* done) {
    if (__blink_panic_cleanup_top >= BLINK_PANIC_CLEANUP_MAX) { return; }
    __blink_panic_cleanup_stack[__blink_panic_cleanup_top].state = state;
    __blink_panic_cleanup_stack[__blink_panic_cleanup_top].run = run;
    __blink_panic_cleanup_stack[__blink_panic_cleanup_top].done = done;
    __blink_panic_cleanup_top++;
}
#endif

/* Pop the top entry if it belongs to `state` (the normal-exit path: the
 * attribute-cleanup fires in LIFO order, so its entry is at the top). No-op
 * if dispatch already truncated past it. */
BLINK_RT_FN void __blink_cleanup_pop(void* state);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_cleanup_pop(void* state) {
    if (__blink_panic_cleanup_top > 0 &&
        __blink_panic_cleanup_stack[__blink_panic_cleanup_top - 1].state == state) {
        __blink_panic_cleanup_top--;
    }
}
#endif

/* Run cleanup entries from the top down to `mark` (exclusive), each with
 * ok=0, then truncate. Sets each entry's `done` flag so the abandoned
 * attribute-cleanup (if it ever runs) won't double-exit. */
BLINK_RT_FN void __blink_cleanup_run_to(size_t mark);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_cleanup_run_to(size_t mark) {
    /* Mark the drain so a panic raised by a cleanup thunk (E0824) is captured
     * as a secondary warning and unwinds back here instead of re-entering the
     * armed assert_panics frame (see __blink_panic_dispatch). Save/restore the
     * flag and the per-thunk recovery buffer for nesting: a thunk may open its
     * own non-armed `with` whose own dispatch re-enters this drain. */
    int __prev_in_drain = __blink_in_cleanup_drain;
    jmp_buf __prev_thunk_jmp;
    memcpy(__prev_thunk_jmp, __blink_cleanup_thunk_jmp, sizeof(jmp_buf));
    __blink_in_cleanup_drain = 1;
    while (__blink_panic_cleanup_top > mark) {
        __blink_panic_cleanup_top--;
        __blink_panic_cleanup_entry* e = &__blink_panic_cleanup_stack[__blink_panic_cleanup_top];
        if (e->done && *e->done) { continue; }
        /* The per-type thunk owns the `done` flag: it sets done=1 then runs
         * exit/close exactly once. Do NOT pre-set done here, or the thunk
         * sees it already set and skips the cleanup it was pushed to run.
         *
         * Set a recovery point BEFORE invoking the thunk: if its exit/close
         * body panics, dispatch longjmps back here (returning nonzero) rather
         * than RETURNING into the panicking thunk — a bare return would let the
         * thunk run its post-panic fall-through, and runtime panic-callers
         * (blink_list_get/_set/_pop, bytes set, arg index) execute their
         * unsafe OOB access right after dispatch. The longjmp abandons that
         * frame; `done` was already set, so we never re-run it; the loop then
         * proceeds to the next handler (continue-drain). */
        if (e->run) {
            if (setjmp(__blink_cleanup_thunk_jmp) == 0) {
                e->run(e->state, 0);
            }
        }
    }
    __blink_in_cleanup_drain = __prev_in_drain;
    memcpy(__blink_cleanup_thunk_jmp, __prev_thunk_jmp, sizeof(jmp_buf));
}
#endif

/* Append a cleanup-panic message to the E0824 secondary-warning buffer. Drops
 * silently past the cap (mirrors the cleanup-stack drop-past-cap convention);
 * the count keeps incrementing so the runner can report how many were lost. */
BLINK_RT_FN void __blink_cleanup_warn_push(const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_cleanup_warn_push(const char* msg) {
    if (__blink_cleanup_warning_count < BLINK_CLEANUP_WARN_MAX) {
        snprintf(__blink_cleanup_warnings[__blink_cleanup_warning_count],
                 BLINK_CLEANUP_WARN_MSG_SIZE, "%s", msg ? msg : "");
    }
    __blink_cleanup_warning_count++;
}
#endif

/* Shared panic dispatch. If a cleanup thunk is currently draining (E0824): the
 * original panic is already load-bearing, so capture this secondary message as
 * a warning and longjmp back to the per-thunk recovery point in
 * __blink_cleanup_run_to — NOT a bare return. The longjmp abandons the
 * panicking exit/close frame (so its unsafe post-panic fall-through never
 * runs), and the drain loop then continues to the next handler (continue-drain).
 * `assert_panics` can only appear directly in a `test {}` body, so a cleanup
 * thunk can never open a nested armed frame — the drain branch never steals a
 * panic that an inner assert_panics should have caught. Else if armed: capture
 * the message, run in-body cleanup down to the armed frame's mark, then longjmp
 * into assert_panics. Else if a test-hook is installed (zs3w3y): the test
 * runner registered it to record the failure and longjmp back to its per-test
 * frame so an uncaught panic fails one test instead of killing the whole binary.
 * If none of those: terminate the process exactly as the historic inline panic
 * did. */
BLINK_RT_FN void __blink_panic_dispatch(const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_panic_dispatch(const char* msg) {
    if (__builtin_expect(__blink_in_cleanup_drain, 0)) {
        __blink_cleanup_warn_push(msg);
        longjmp(__blink_cleanup_thunk_jmp, 1);
    }
    if (__builtin_expect(__blink_panic_armed, 0)) {
        snprintf(__blink_panic_msg, BLINK_PANIC_MSG_SIZE, "%s", msg ? msg : "");
        __blink_cleanup_run_to(__blink_panic_cleanup_mark);
        longjmp(__blink_panic_jmp, 1);
    }
    if (__builtin_expect(__blink_panic_test_hook != NULL, 0)) {
        __blink_panic_test_hook(msg);   /* zs3w3y: records failure + longjmps; never returns */
    }
    fprintf(stderr, "%s\n", msg ? msg : "panic");
    exit(1);
}
#endif

BLINK_RT_FN void __blink_panic_dispatchf(const char* fmt, ...);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_panic_dispatchf(const char* fmt, ...) {
    char __buf[BLINK_PANIC_MSG_SIZE];
    va_list __ap;
    va_start(__ap, fmt);
    vsnprintf(__buf, BLINK_PANIC_MSG_SIZE, fmt, __ap);
    va_end(__ap);
    __blink_panic_dispatch(__buf);
}
#endif

BLINK_RT_FN blink_arena_chunk* blink_arena_chunk_new(int64_t capacity);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_arena_chunk* blink_arena_chunk_new(int64_t capacity) {
    blink_arena_chunk* c = (blink_arena_chunk*)GC_MALLOC(sizeof(blink_arena_chunk));
    if (!c) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    /* Pad by BLINK_ARENA_ALIGN so we can re-align the payload start: bdwgc
       guarantees granule alignment (8 on 32-bit, 16 on 64-bit), and callers
       need a 16-byte boundary for their allocations. Payload must be scanned
       (not atomic): arena-resident structs can hold pointers into the GC
       heap (e.g. `Str` fields produced by interpolation), and those
       pointers need to stay reachable until arena teardown. */
    char* raw = (char*)GC_MALLOC((size_t)capacity + BLINK_ARENA_ALIGN);
    if (!raw) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    uintptr_t aligned = ((uintptr_t)raw + BLINK_ARENA_ALIGN - 1)
                        & ~(uintptr_t)(BLINK_ARENA_ALIGN - 1);
    c->next = NULL;
    c->data = (char*)aligned;
    c->capacity = capacity;
    c->used = 0;
    return c;
}
#endif

BLINK_RT_FN blink_arena_t* blink_arena_create(int64_t chunk_size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_arena_t* blink_arena_create(int64_t chunk_size) {
    blink_arena_t* a = (blink_arena_t*)GC_MALLOC(sizeof(blink_arena_t));
    if (!a) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    a->default_chunk_size = chunk_size > 0 ? chunk_size : BLINK_ARENA_DEFAULT_CHUNK_SIZE;
    a->head = blink_arena_chunk_new(a->default_chunk_size);
    return a;
}
#endif

BLINK_RT_FN void blink_arena_destroy(blink_arena_t* a);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_arena_destroy(blink_arena_t* a) {
    if (!a) return;
    blink_arena_chunk* c = a->head;
    while (c) {
        blink_arena_chunk* next = c->next;
        GC_FREE(c->data);
        GC_FREE(c);
        c = next;
    }
    a->head = NULL;
    GC_FREE(a);
}
#endif

/* Exposed as `std.arena.bytes_used()`. Sums logical bump-allocated bytes
   (including alignment padding) across chunks of the active arena. */
BLINK_RT_FN int64_t blink_arena_bytes_used(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_arena_bytes_used(void) {
    blink_arena_t* a = __blink_current_arena;
    if (a == NULL) return 0;
    int64_t total = 0;
    blink_arena_chunk* c = a->head;
    while (c != NULL) {
        total += c->used;
        c = c->next;
    }
    return total;
}
#endif

BLINK_RT_FN void* blink_arena_alloc(blink_arena_t* a, int64_t size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_arena_alloc(blink_arena_t* a, int64_t size) {
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
#endif

/* Arena memory is never GC-scanned, so the atomic distinction is meaningless
   here. Kept for API symmetry with GC_MALLOC / GC_MALLOC_ATOMIC. */
BLINK_RT_FN void* blink_arena_alloc_atomic(blink_arena_t* a, int64_t size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_arena_alloc_atomic(blink_arena_t* a, int64_t size) {
    return blink_arena_alloc(a, size);
}
#endif

BLINK_RT_FN void* blink_alloc(int64_t size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_alloc(int64_t size) {
    blink_arena_t* a = __blink_current_arena;
    if (a != NULL) return blink_arena_alloc(a, size);
    void* p = GC_MALLOC((size_t)size);
    if (!p) {
        fprintf(stderr, "blink: out of memory\n");
        exit(1);
    }
    return p;
}
#endif

/* Arena-aware realloc. When a `with arena` block is active, GC_REALLOC on
   an interior pointer into a GC_MALLOC_ATOMIC arena chunk will free the
   whole chunk out from under us and crash on arena destroy. Allocate fresh
   inside the arena and copy instead; the old buffer is reclaimed wholesale
   on arena tear-down. Outside an arena, fall back to GC_REALLOC. */
BLINK_RT_FN void* blink_realloc(void* ptr, int64_t old_size, int64_t new_size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_realloc(void* ptr, int64_t old_size, int64_t new_size) {
    blink_arena_t* a = __blink_current_arena;
    if (a != NULL) {
        void* np = blink_arena_alloc(a, new_size);
        if (ptr && old_size > 0) {
            int64_t copy = old_size < new_size ? old_size : new_size;
            memcpy(np, ptr, (size_t)copy);
        }
        return np;
    }
    void* p = GC_REALLOC(ptr, (size_t)new_size);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    return p;
}
#endif

BLINK_RT_FN char* blink_strdup(const char* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN char* blink_strdup(const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char* p = (char*)GC_MALLOC_ATOMIC(len);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    memcpy(p, s, len);
    return p;
}
#endif

/* Promotion allocation: target==NULL means GC heap; else allocate in target
   arena. Bypasses __blink_current_arena because during promotion the TLS may
   still reference the inner (dying) arena. */
BLINK_RT_FN void* blink_promote_alloc(blink_arena_t* target, int64_t size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_promote_alloc(blink_arena_t* target, int64_t size) {
    if (target != NULL) return blink_arena_alloc(target, size);
    void* p = GC_MALLOC((size_t)size);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    return p;
}
#endif

BLINK_RT_FN void* blink_promote_alloc_atomic(blink_arena_t* target, int64_t size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_promote_alloc_atomic(blink_arena_t* target, int64_t size) {
    if (target != NULL) return blink_arena_alloc(target, size);
    void* p = GC_MALLOC_ATOMIC((size_t)size);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    return p;
}
#endif

BLINK_RT_FN const char* blink_promote_str(blink_arena_t* target, const char* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_promote_str(blink_arena_t* target, const char* s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char* p = (char*)blink_promote_alloc_atomic(target, (int64_t)len);
    memcpy(p, s, len);
    return p;
}
#endif

typedef struct {
    void** items;
    int64_t len;
    int64_t cap;
} blink_list;

BLINK_RT_FN blink_list* blink_list_new(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_list_new(void) {
    blink_list* l = (blink_list*)blink_alloc(sizeof(blink_list));
    l->cap = 8;
    l->len = 0;
    l->items = (void**)blink_alloc(sizeof(void*) * l->cap);
    return l;
}
#endif

BLINK_RT_FN void blink_list_push(blink_list* l, void* item);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_list_push(blink_list* l, void* item) {
    if (l->len >= l->cap) {
        int64_t old_cap = l->cap;
        l->cap *= 2;
        l->items = (void**)blink_realloc(l->items,
            sizeof(void*) * (size_t)old_cap,
            sizeof(void*) * (size_t)l->cap);
    }
    l->items[l->len++] = item;
}
#endif

BLINK_RT_FN void* blink_list_get(const blink_list* l, int64_t index);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_list_get(const blink_list* l, int64_t index) {
    if (index < 0 || index >= l->len) {
        __blink_panic_dispatchf("blink: list index out of bounds: idx=%lld len=%lld", (long long)index, (long long)l->len);
    }
    return l->items[index];
}
#endif

BLINK_RT_FN int blink_list_in_bounds(const blink_list* l, int64_t index);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_list_in_bounds(const blink_list* l, int64_t index) {
    return (index >= 0 && index < l->len);
}
#endif

BLINK_RT_FN int64_t blink_list_len(const blink_list* l);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_list_len(const blink_list* l) {
    return l->len;
}
#endif

BLINK_RT_FN void blink_list_set(blink_list* l, int64_t index, void* item);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_list_set(blink_list* l, int64_t index, void* item) {
    if (index < 0 || index >= l->len) {
        __blink_panic_dispatchf("blink: list set index out of bounds: %lld", (long long)index);
    }
    l->items[index] = item;
}
#endif

BLINK_RT_FN void* blink_list_pop(blink_list* l);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_list_pop(blink_list* l) {
    if (l->len <= 0) {
        __blink_panic_dispatch("blink: list pop on empty list");
    }
    l->len--;
    return l->items[l->len];
}
#endif

BLINK_RT_FN void blink_list_free(blink_list* l);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_list_free(blink_list* l) {
    if (l) {
        GC_FREE(l->items);
        GC_FREE(l);
    }
}
#endif

BLINK_RT_FN void blink_list_clear(blink_list* l);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_list_clear(blink_list* l) {
    l->len = 0;
}
#endif

BLINK_RT_FN blink_list* blink_list_concat(blink_list* a, blink_list* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_list_concat(blink_list* a, blink_list* b) {
    blink_list* result = blink_list_new();
    for (int64_t i = 0; i < a->len; i++) blink_list_push(result, a->items[i]);
    for (int64_t i = 0; i < b->len; i++) blink_list_push(result, b->items[i]);
    return result;
}
#endif

BLINK_RT_FN void blink_list_extend(blink_list* dst, blink_list* src);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_list_extend(blink_list* dst, blink_list* src) {
    for (int64_t i = 0; i < src->len; i++) blink_list_push(dst, src->items[i]);
}
#endif

BLINK_RT_FN blink_list* blink_list_slice(blink_list* l, int64_t start, int64_t end);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_list_slice(blink_list* l, int64_t start, int64_t end) {
    blink_list* result = blink_list_new();
    if (start < 0) start = 0;
    if (end > l->len) end = l->len;
    for (int64_t i = start; i < end; i++) blink_list_push(result, l->items[i]);
    return result;
}
#endif

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

BLINK_RT_FN blink_template* blink_template_new(int64_t num_values);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_template* blink_template_new(int64_t num_values) {
    blink_template* t = (blink_template*)blink_alloc(sizeof(blink_template));
    t->parts = blink_list_new();
    t->values = (num_values > 0) ? blink_list_new() : NULL;
    t->types = (num_values > 0) ? blink_list_new() : NULL;
    t->count = num_values;
    return t;
}
#endif

/* ── Hash map (string-keyed) ────────────────────────────────────────── */

BLINK_RT_FN int blink_str_eq(const char* a, const char* b);

BLINK_RT_FN uint64_t blink_map_hash(const char* key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN uint64_t blink_map_hash(const char* key) {
    uint64_t h = 14695981039346656037ULL;
    for (const char* p = key; *p; p++) {
        h ^= (uint64_t)(unsigned char)*p;
        h *= 1099511628211ULL;
    }
    return h;
}
#endif

/* ── Generic hash map (kops vtable) ──────────────────────────────────── */
/* See decisions/map-runtime-architecture.md. One runtime, per-K kops table. */

typedef struct {
    uint64_t (*hash)(const void* k);
    int      (*eq)  (const void* a, const void* b);
    size_t   key_size;     /* size of K in bytes (used when inline_key=1) */
    uint8_t  inline_key;   /* 1 = bytes stored inline in slot; 0 = pointer slot */
} blink_kops;

/* cap is always a power of two; the probe loop wraps with `& (cap-1)`. */
typedef struct {
    void* keys;            /* cap * (inline_key ? key_size : sizeof(void*)) bytes */
    void** values;
    uint8_t* states;       /* 0=empty, 1=occupied, 2=tombstone */
    int64_t len;
    int64_t cap;
    const blink_kops* kops;
} blink_map;

/* `static inline` so the compiler can fold the kops->inline_key branch
   and stride computation into the probe-loop callsites. */
static inline size_t blink_kops_stride(const blink_kops* k) {
    return k->inline_key ? k->key_size : sizeof(void*);
}

static inline const void* blink_map_key_slot(const blink_map* m, int64_t i, size_t stride) {
    void* slot = (void*)((char*)m->keys + (size_t)i * stride);
    return m->kops->inline_key ? (const void*)slot : *(const void**)slot;
}

BLINK_RT_FN blink_map* blink_map_new(const blink_kops* kops);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_map* blink_map_new(const blink_kops* kops) {
    blink_map* m = (blink_map*)blink_alloc(sizeof(blink_map));
    m->cap = 16;
    m->len = 0;
    m->kops = kops;
    size_t stride = blink_kops_stride(kops);
    m->keys = blink_alloc((int64_t)(stride * (size_t)m->cap));
    m->values = (void**)blink_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    return m;
}
#endif

BLINK_RT_FN void blink_map_grow(blink_map* m);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_map_grow(blink_map* m) {
    /* cap is always a power of two: initial cap is 16, this is the only
       mutator, and it doubles. The probe paths replace `% cap` with
       `& (cap - 1)` — break the pow2 invariant and lookups silently corrupt. */
    const blink_kops* k = m->kops;
    int64_t old_cap = m->cap;
    void* old_keys = m->keys;
    void** old_values = m->values;
    uint8_t* old_states = m->states;
    size_t stride = blink_kops_stride(k);
    m->cap = old_cap * 2;
    int64_t mask = m->cap - 1;
    m->keys = blink_alloc((int64_t)(stride * (size_t)m->cap));
    m->values = (void**)blink_alloc(sizeof(void*) * (size_t)m->cap);
    m->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)m->cap);
    memset(m->states, 0, (size_t)m->cap);
    m->len = 0;
    for (int64_t i = 0; i < old_cap; i++) {
        if (old_states[i] != 1) continue;
        void* old_slot = (void*)((char*)old_keys + (size_t)i * stride);
        const void* kptr = k->inline_key ? (const void*)old_slot : *(const void**)old_slot;
        uint64_t h = k->hash(kptr);
        int64_t idx = (int64_t)(h & (uint64_t)mask);
        while (m->states[idx] != 0) idx = (idx + 1) & mask;
        void* new_slot = (void*)((char*)m->keys + (size_t)idx * stride);
        memcpy(new_slot, old_slot, stride);
        m->values[idx] = old_values[i];
        m->states[idx] = 1;
        m->len++;
    }
    if (__blink_current_arena == NULL) {
        GC_FREE(old_keys);
        GC_FREE(old_values);
        GC_FREE(old_states);
    }
}
#endif

BLINK_RT_FN void blink_map_set(blink_map* m, const void* key, void* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_map_set(blink_map* m, const void* key, void* value) {
    if (m->len * 10 >= m->cap * 7) blink_map_grow(m);
    const blink_kops* k = m->kops;
    size_t stride = blink_kops_stride(k);
    int64_t mask = m->cap - 1;
    uint64_t h = k->hash(key);
    int64_t idx = (int64_t)(h & (uint64_t)mask);
    int64_t first_tombstone = -1;
    while (1) {
        if (m->states[idx] == 0) {
            int64_t ins = (first_tombstone >= 0) ? first_tombstone : idx;
            void* slot = (void*)((char*)m->keys + (size_t)ins * stride);
            if (k->inline_key) {
                memcpy(slot, key, k->key_size);
            } else {
                *(const void**)slot = key;
            }
            m->values[ins] = value;
            m->states[ins] = 1;
            m->len++;
            return;
        }
        if (m->states[idx] == 2) {
            if (first_tombstone < 0) first_tombstone = idx;
        } else {
            const void* existing = blink_map_key_slot(m, idx, stride);
            if (k->eq(existing, key)) {
                m->values[idx] = value;
                return;
            }
        }
        idx = (idx + 1) & mask;
    }
}
#endif

BLINK_RT_FN void* blink_map_get(const blink_map* m, const void* key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_map_get(const blink_map* m, const void* key) {
    const blink_kops* k = m->kops;
    size_t stride = blink_kops_stride(k);
    int64_t mask = m->cap - 1;
    uint64_t h = k->hash(key);
    int64_t idx = (int64_t)(h & (uint64_t)mask);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1) {
            const void* existing = blink_map_key_slot(m, idx, stride);
            if (k->eq(existing, key)) return m->values[idx];
        }
        idx = (idx + 1) & mask;
    }
    return NULL;
}
#endif

BLINK_RT_FN int64_t blink_map_has(const blink_map* m, const void* key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_map_has(const blink_map* m, const void* key) {
    const blink_kops* k = m->kops;
    size_t stride = blink_kops_stride(k);
    int64_t mask = m->cap - 1;
    uint64_t h = k->hash(key);
    int64_t idx = (int64_t)(h & (uint64_t)mask);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1) {
            const void* existing = blink_map_key_slot(m, idx, stride);
            if (k->eq(existing, key)) return 1;
        }
        idx = (idx + 1) & mask;
    }
    return 0;
}
#endif

BLINK_RT_FN int64_t blink_map_remove(blink_map* m, const void* key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_map_remove(blink_map* m, const void* key) {
    const blink_kops* k = m->kops;
    size_t stride = blink_kops_stride(k);
    int64_t mask = m->cap - 1;
    uint64_t h = k->hash(key);
    int64_t idx = (int64_t)(h & (uint64_t)mask);
    while (m->states[idx] != 0) {
        if (m->states[idx] == 1) {
            const void* existing = blink_map_key_slot(m, idx, stride);
            if (k->eq(existing, key)) {
                m->states[idx] = 2;
                m->len--;
                return 1;
            }
        }
        idx = (idx + 1) & mask;
    }
    return 0;
}
#endif

BLINK_RT_FN int64_t blink_map_len(const blink_map* m);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_map_len(const blink_map* m) { return m->len; }
#endif

BLINK_RT_FN void blink_map_clear(blink_map* m);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_map_clear(blink_map* m) {
    m->len = 0;
    memset(m->states, 0, sizeof(uint8_t) * (size_t)m->cap);
}
#endif

/* For inline keys, allocates one bulk buffer sized `len * key_size` and pushes
   pointers into it (avoids N small allocations on large maps). For pointer keys,
   pushes the stored pointer directly. Caller must know K to interpret. */
BLINK_RT_FN blink_list* blink_map_keys(const blink_map* m);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_map_keys(const blink_map* m) {
    blink_list* result = blink_list_new();
    const blink_kops* k = m->kops;
    size_t stride = blink_kops_stride(k);
    /* Inline keys that fit in a pointer slot (Int, Bool, Char, etc.) are
       packed into the List's void* element directly — matches how List[Int]
       already stores small ints, so `ks.get(i)` recovers via (intptr_t)elem.
       Larger inline keys spill to a bulk buffer with stored pointers. */
    if (k->inline_key && k->key_size <= sizeof(void*)) {
        for (int64_t i = 0; i < m->cap; i++) {
            if (m->states[i] != 1) continue;
            void* slot = (void*)((char*)m->keys + (size_t)i * stride);
            uintptr_t packed = 0;
            memcpy(&packed, slot, k->key_size);
            blink_list_push(result, (void*)packed);
        }
    } else if (k->inline_key && m->len > 0) {
        char* buf = (char*)blink_alloc((int64_t)((size_t)m->len * k->key_size));
        size_t out = 0;
        for (int64_t i = 0; i < m->cap; i++) {
            if (m->states[i] != 1) continue;
            void* slot = (void*)((char*)m->keys + (size_t)i * stride);
            char* dst = buf + out * k->key_size;
            memcpy(dst, slot, k->key_size);
            blink_list_push(result, (void*)dst);
            out++;
        }
    } else {
        for (int64_t i = 0; i < m->cap; i++) {
            if (m->states[i] != 1) continue;
            void* slot = (void*)((char*)m->keys + (size_t)i * stride);
            blink_list_push(result, *(void**)slot);
        }
    }
    return result;
}
#endif

BLINK_RT_FN blink_list* blink_map_values(const blink_map* m);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_map_values(const blink_map* m) {
    blink_list* result = blink_list_new();
    for (int64_t i = 0; i < m->cap; i++) {
        if (m->states[i] == 1) blink_list_push(result, m->values[i]);
    }
    return result;
}
#endif

/* ── Built-in kops tables ────────────────────────────────────────────── */

/* Seeded FNV-1a 64-bit offset basis. Used by @derive(Hash) emitters and by
   any user code that wants the same seed-mixing contract as built-in keys. */
#define BLINK_HASH_INIT (blink_map_seed ^ 0xcbf29ce484222325ULL)

BLINK_RT_FN void blink_map_set_seed(uint64_t s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_map_set_seed(uint64_t s) { blink_map_seed = s; }
#endif

/* Default-seed initialization. `deterministic` non-zero pins seed=0; otherwise
   the seed is drawn from BLINK_MAP_SEED if set, else time^pid. Called once
   from generated main() before any user code runs. */
BLINK_RT_FN void blink_map_init_seed(int deterministic);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_map_init_seed(int deterministic) {
    if (deterministic) { blink_map_seed = 0; return; }
    const char* env_s = getenv("BLINK_MAP_SEED");
    if (env_s && *env_s) {
        blink_map_seed = (uint64_t)strtoull(env_s, NULL, 10);
        return;
    }
    blink_map_seed = (uint64_t)time(NULL) ^ ((uint64_t)getpid() << 16);
}
#endif

BLINK_RT_FN uint64_t blink_kops_hash_str(const void* k);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN uint64_t blink_kops_hash_str(const void* k) {
    return blink_map_hash((const char*)k) ^ blink_map_seed;
}
#endif

BLINK_RT_FN int blink_kops_eq_str(const void* a, const void* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_kops_eq_str(const void* a, const void* b) {
    return blink_str_eq((const char*)a, (const char*)b);
}
#endif

/* splitmix64 finalizer — shared body for all integer widths. */
BLINK_RT_FN uint64_t blink_kops_mix_u64(uint64_t x);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN uint64_t blink_kops_mix_u64(uint64_t x) {
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27;
    x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x;
}
#endif

#ifndef BLINK_RUNTIME_DECLS_ONLY
static uint64_t blink_kops_hash_i64(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)*(const int64_t*)k); }
static int      blink_kops_eq_i64  (const void* a, const void* b) { return *(const int64_t*)a == *(const int64_t*)b; }
static uint64_t blink_kops_hash_u64(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ *(const uint64_t*)k); }
static int      blink_kops_eq_u64  (const void* a, const void* b) { return *(const uint64_t*)a == *(const uint64_t*)b; }
static uint64_t blink_kops_hash_i32(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)(int64_t)*(const int32_t*)k); }
static int      blink_kops_eq_i32  (const void* a, const void* b) { return *(const int32_t*)a == *(const int32_t*)b; }
static uint64_t blink_kops_hash_u32(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)*(const uint32_t*)k); }
static int      blink_kops_eq_u32  (const void* a, const void* b) { return *(const uint32_t*)a == *(const uint32_t*)b; }
static uint64_t blink_kops_hash_i16(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)(int64_t)*(const int16_t*)k); }
static int      blink_kops_eq_i16  (const void* a, const void* b) { return *(const int16_t*)a == *(const int16_t*)b; }
static uint64_t blink_kops_hash_u16(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)*(const uint16_t*)k); }
static int      blink_kops_eq_u16  (const void* a, const void* b) { return *(const uint16_t*)a == *(const uint16_t*)b; }
static uint64_t blink_kops_hash_i8 (const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)(int64_t)*(const int8_t*)k); }
static int      blink_kops_eq_i8   (const void* a, const void* b) { return *(const int8_t*)a == *(const int8_t*)b; }
static uint64_t blink_kops_hash_u8 (const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)*(const uint8_t*)k); }
static int      blink_kops_eq_u8   (const void* a, const void* b) { return *(const uint8_t*)a == *(const uint8_t*)b; }
static uint64_t blink_kops_hash_bool(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (*(const uint8_t*)k ? 1u : 0u)); }
static int      blink_kops_eq_bool (const void* a, const void* b) { return (*(const uint8_t*)a != 0) == (*(const uint8_t*)b != 0); }
/* Char is U32 in Blink (codepoint). */
static uint64_t blink_kops_hash_char(const void* k) { return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)*(const uint32_t*)k); }
static int      blink_kops_eq_char (const void* a, const void* b) { return *(const uint32_t*)a == *(const uint32_t*)b; }
#endif

/* Built-in kops tables — storage follows the same archive/extern pattern as
   __blink_current_arena. Single-TU build (no archive): per-TU `static`. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    #define BLINK_KOPS_STORAGE
  #else
    #define BLINK_KOPS_STORAGE extern
  #endif
#else
  #define BLINK_KOPS_STORAGE BLINK_UNUSED static
#endif

#if defined(BLINK_USE_EXTERN_RUNTIME_STORAGE) && !defined(BLINK_RUNTIME_STORAGE_DEFINE)
BLINK_KOPS_STORAGE const blink_kops blink_kops_str;
BLINK_KOPS_STORAGE const blink_kops blink_kops_i64;
BLINK_KOPS_STORAGE const blink_kops blink_kops_u64;
BLINK_KOPS_STORAGE const blink_kops blink_kops_i32;
BLINK_KOPS_STORAGE const blink_kops blink_kops_u32;
BLINK_KOPS_STORAGE const blink_kops blink_kops_i16;
BLINK_KOPS_STORAGE const blink_kops blink_kops_u16;
BLINK_KOPS_STORAGE const blink_kops blink_kops_i8;
BLINK_KOPS_STORAGE const blink_kops blink_kops_u8;
BLINK_KOPS_STORAGE const blink_kops blink_kops_bool;
BLINK_KOPS_STORAGE const blink_kops blink_kops_char;
#else
BLINK_KOPS_STORAGE const blink_kops blink_kops_str  = { blink_kops_hash_str, blink_kops_eq_str, sizeof(void*), 0 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_i64  = { blink_kops_hash_i64, blink_kops_eq_i64, sizeof(int64_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_u64  = { blink_kops_hash_u64, blink_kops_eq_u64, sizeof(uint64_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_i32  = { blink_kops_hash_i32, blink_kops_eq_i32, sizeof(int32_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_u32  = { blink_kops_hash_u32, blink_kops_eq_u32, sizeof(uint32_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_i16  = { blink_kops_hash_i16, blink_kops_eq_i16, sizeof(int16_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_u16  = { blink_kops_hash_u16, blink_kops_eq_u16, sizeof(uint16_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_i8   = { blink_kops_hash_i8,  blink_kops_eq_i8,  sizeof(int8_t),  1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_u8   = { blink_kops_hash_u8,  blink_kops_eq_u8,  sizeof(uint8_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_bool = { blink_kops_hash_bool,blink_kops_eq_bool,sizeof(uint8_t), 1 };
BLINK_KOPS_STORAGE const blink_kops blink_kops_char = { blink_kops_hash_char,blink_kops_eq_char,sizeof(uint32_t), 1 };
#endif

/* ── Hash set (kops vtable) ──────────────────────────────────────────── */
/* Set is Map minus the values array (decisions/set-type-implementation.md).
   Same per-element kops table as blink_map: Str routes through &blink_kops_str
   (inline_key=0, pointer slots); Int/Char/sized-ints/bool store bytes inline. */

typedef struct {
    void* items;           /* cap * (inline_key ? key_size : sizeof(void*)) bytes */
    uint8_t* states;       /* 0=empty, 1=occupied, 2=tombstone */
    int64_t len;
    int64_t cap;
    const blink_kops* kops;
} blink_set;

static inline const void* blink_set_item_slot(const blink_set* s, int64_t i, size_t stride) {
    void* slot = (void*)((char*)s->items + (size_t)i * stride);
    return s->kops->inline_key ? (const void*)slot : *(const void**)slot;
}

BLINK_RT_FN blink_set* blink_set_new(const blink_kops* kops);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_set* blink_set_new(const blink_kops* kops) {
    blink_set* s = (blink_set*)blink_alloc(sizeof(blink_set));
    s->cap = 16;
    s->len = 0;
    s->kops = kops;
    size_t stride = blink_kops_stride(kops);
    s->items = blink_alloc((int64_t)(stride * (size_t)s->cap));
    s->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)s->cap);
    memset(s->states, 0, (size_t)s->cap);
    return s;
}
#endif

BLINK_RT_FN void blink_set_grow(blink_set* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_set_grow(blink_set* s) {
    /* cap is a power of two (initial 16, only doubled here); probe wraps with
       `& (cap - 1)`. Mirrors blink_map_grow. */
    const blink_kops* k = s->kops;
    int64_t old_cap = s->cap;
    void* old_items = s->items;
    uint8_t* old_states = s->states;
    size_t stride = blink_kops_stride(k);
    s->cap = old_cap * 2;
    int64_t mask = s->cap - 1;
    s->items = blink_alloc((int64_t)(stride * (size_t)s->cap));
    s->states = (uint8_t*)blink_alloc(sizeof(uint8_t) * (size_t)s->cap);
    memset(s->states, 0, (size_t)s->cap);
    s->len = 0;
    for (int64_t i = 0; i < old_cap; i++) {
        if (old_states[i] != 1) continue;
        void* old_slot = (void*)((char*)old_items + (size_t)i * stride);
        const void* kptr = k->inline_key ? (const void*)old_slot : *(const void**)old_slot;
        uint64_t h = k->hash(kptr);
        int64_t idx = (int64_t)(h & (uint64_t)mask);
        while (s->states[idx] != 0) idx = (idx + 1) & mask;
        void* new_slot = (void*)((char*)s->items + (size_t)idx * stride);
        memcpy(new_slot, old_slot, stride);
        s->states[idx] = 1;
        s->len++;
    }
    if (__blink_current_arena == NULL) {
        GC_FREE(old_items);
        GC_FREE(old_states);
    }
}
#endif

BLINK_RT_FN int64_t blink_set_insert(blink_set* s, const void* item);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_set_insert(blink_set* s, const void* item) {
    if (s->len * 10 >= s->cap * 7) blink_set_grow(s);
    const blink_kops* k = s->kops;
    size_t stride = blink_kops_stride(k);
    int64_t mask = s->cap - 1;
    uint64_t h = k->hash(item);
    int64_t idx = (int64_t)(h & (uint64_t)mask);
    int64_t first_tombstone = -1;
    while (1) {
        if (s->states[idx] == 0) {
            int64_t ins = (first_tombstone >= 0) ? first_tombstone : idx;
            void* slot = (void*)((char*)s->items + (size_t)ins * stride);
            if (k->inline_key) {
                memcpy(slot, item, k->key_size);
            } else {
                *(const void**)slot = item;
            }
            s->states[ins] = 1;
            s->len++;
            return 1;
        }
        if (s->states[idx] == 2) {
            if (first_tombstone < 0) first_tombstone = idx;
        } else {
            const void* existing = blink_set_item_slot(s, idx, stride);
            if (k->eq(existing, item)) return 0;
        }
        idx = (idx + 1) & mask;
    }
}
#endif

BLINK_RT_FN int64_t blink_set_contains(const blink_set* s, const void* item);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_set_contains(const blink_set* s, const void* item) {
    const blink_kops* k = s->kops;
    size_t stride = blink_kops_stride(k);
    int64_t mask = s->cap - 1;
    uint64_t h = k->hash(item);
    int64_t idx = (int64_t)(h & (uint64_t)mask);
    while (s->states[idx] != 0) {
        if (s->states[idx] == 1) {
            const void* existing = blink_set_item_slot(s, idx, stride);
            if (k->eq(existing, item)) return 1;
        }
        idx = (idx + 1) & mask;
    }
    return 0;
}
#endif

BLINK_RT_FN int64_t blink_set_remove(blink_set* s, const void* item);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_set_remove(blink_set* s, const void* item) {
    const blink_kops* k = s->kops;
    size_t stride = blink_kops_stride(k);
    int64_t mask = s->cap - 1;
    uint64_t h = k->hash(item);
    int64_t idx = (int64_t)(h & (uint64_t)mask);
    while (s->states[idx] != 0) {
        if (s->states[idx] == 1) {
            const void* existing = blink_set_item_slot(s, idx, stride);
            if (k->eq(existing, item)) {
                s->states[idx] = 2;
                s->len--;
                return 1;
            }
        }
        idx = (idx + 1) & mask;
    }
    return 0;
}
#endif

BLINK_RT_FN int64_t blink_set_len(const blink_set* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_set_len(const blink_set* s) {
    return s->len;
}
#endif

/* Re-inserts every element of `a` then `b` into a fresh set carrying a's kops.
   Both operands must share the same element type (kops); the typechecker
   enforces `union(self, other: Set[T])`. */
BLINK_RT_FN blink_set* blink_set_union(const blink_set* a, const blink_set* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_set* blink_set_union(const blink_set* a, const blink_set* b) {
    blink_set* result = blink_set_new(a->kops);
    size_t stride = blink_kops_stride(a->kops);
    for (int64_t i = 0; i < a->cap; i++) {
        if (a->states[i] == 1) blink_set_insert(result, blink_set_item_slot(a, i, stride));
    }
    size_t bstride = blink_kops_stride(b->kops);
    for (int64_t i = 0; i < b->cap; i++) {
        if (b->states[i] == 1) blink_set_insert(result, blink_set_item_slot(b, i, bstride));
    }
    return result;
}
#endif

/* Element iteration — same inline-key packing contract as blink_map_keys:
   inline keys that fit a pointer slot are packed directly into the List void*;
   larger inline keys spill to a bulk buffer; pointer keys are pushed as-is. */
BLINK_RT_FN blink_list* blink_set_to_list(const blink_set* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_set_to_list(const blink_set* s) {
    blink_list* result = blink_list_new();
    const blink_kops* k = s->kops;
    size_t stride = blink_kops_stride(k);
    if (k->inline_key && k->key_size <= sizeof(void*)) {
        for (int64_t i = 0; i < s->cap; i++) {
            if (s->states[i] != 1) continue;
            void* slot = (void*)((char*)s->items + (size_t)i * stride);
            uintptr_t packed = 0;
            memcpy(&packed, slot, k->key_size);
            blink_list_push(result, (void*)packed);
        }
    } else if (k->inline_key && s->len > 0) {
        char* buf = (char*)blink_alloc((int64_t)((size_t)s->len * k->key_size));
        size_t out = 0;
        for (int64_t i = 0; i < s->cap; i++) {
            if (s->states[i] != 1) continue;
            void* slot = (void*)((char*)s->items + (size_t)i * stride);
            char* dst = buf + out * k->key_size;
            memcpy(dst, slot, k->key_size);
            blink_list_push(result, (void*)dst);
            out++;
        }
    } else {
        for (int64_t i = 0; i < s->cap; i++) {
            if (s->states[i] != 1) continue;
            void* slot = (void*)((char*)s->items + (size_t)i * stride);
            blink_list_push(result, *(void**)slot);
        }
    }
    return result;
}
#endif

BLINK_RT_FN void blink_set_free(blink_set* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_set_free(blink_set* s) {
    if (s) {
        GC_FREE(s->items);
        GC_FREE(s->states);
        GC_FREE(s);
    }
}
#endif

/* Layout-compatible with the codegen-emitted blink_Result_str_str so
   runtime helpers can return it by value. */
typedef struct { int tag; union { const char* ok; const char* err; }; } blink_Result_str_str;

/* ── Byte buffer ────────────────────────────────────────────────────── */

typedef struct {
    uint8_t* data;
    int64_t len;
    int64_t cap;
} blink_bytes;

BLINK_RT_FN blink_bytes* blink_bytes_new(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_bytes* blink_bytes_new(void) {
    blink_bytes* b = (blink_bytes*)blink_alloc(sizeof(blink_bytes));
    b->cap = 16;
    b->len = 0;
    b->data = (uint8_t*)blink_alloc((size_t)b->cap);
    return b;
}
#endif

BLINK_RT_FN void blink_bytes_push(blink_bytes* b, int64_t byte);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_bytes_push(blink_bytes* b, int64_t byte) {
    if (b->len >= b->cap) {
        int64_t old_cap = b->cap;
        b->cap *= 2;
        b->data = (uint8_t*)blink_realloc(b->data, (size_t)old_cap, (size_t)b->cap);
    }
    b->data[b->len++] = (uint8_t)(byte & 0xFF);
}
#endif

BLINK_RT_FN int64_t blink_bytes_get(const blink_bytes* b, int64_t index);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_bytes_get(const blink_bytes* b, int64_t index) {
    if (index < 0 || index >= b->len) return -1;
    return (int64_t)b->data[index];
}
#endif

BLINK_RT_FN void blink_bytes_set(blink_bytes* b, int64_t index, int64_t byte);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_bytes_set(blink_bytes* b, int64_t index, int64_t byte) {
    if (index < 0 || index >= b->len) {
        __blink_panic_dispatchf("blink: bytes set index out of bounds: %lld", (long long)index);
    }
    b->data[index] = (uint8_t)(byte & 0xFF);
}
#endif

BLINK_RT_FN int64_t blink_bytes_len(const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_bytes_len(const blink_bytes* b) {
    return b->len;
}
#endif

BLINK_RT_FN int64_t blink_bytes_is_empty(const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_bytes_is_empty(const blink_bytes* b) {
    return b->len == 0;
}
#endif

/* vfgp72: structural equality / ordering for Bytes (spec §3.6 Eq+Ord).
 * Lexicographic over the byte sequence; the shorter prefix sorts first. */
BLINK_RT_FN int64_t blink_bytes_eq(const blink_bytes* a, const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_bytes_eq(const blink_bytes* a, const blink_bytes* b) {
    if (a == b) { return 1; }
    if (a == NULL || b == NULL) { return 0; }
    if (a->len != b->len) { return 0; }
    if (a->len == 0) { return 1; }
    return memcmp(a->data, b->data, (size_t)a->len) == 0;
}
#endif

BLINK_RT_FN int64_t blink_bytes_cmp(const blink_bytes* a, const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_bytes_cmp(const blink_bytes* a, const blink_bytes* b) {
    if (a == b) { return 0; }
    int64_t alen = (a == NULL) ? 0 : a->len;
    int64_t blen = (b == NULL) ? 0 : b->len;
    int64_t n = (alen < blen) ? alen : blen;
    if (n > 0) {
        int c = memcmp(a->data, b->data, (size_t)n);
        if (c < 0) { return -1; }
        if (c > 0) { return 1; }
    }
    if (alen < blen) { return -1; }
    if (alen > blen) { return 1; }
    return 0;
}
#endif

BLINK_RT_FN blink_bytes* blink_bytes_concat(const blink_bytes* a, const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_bytes* blink_bytes_concat(const blink_bytes* a, const blink_bytes* b) {
    blink_bytes* r = blink_bytes_new();
    int64_t total = a->len + b->len;
    if (total > r->cap) {
        int64_t old_cap = r->cap;
        r->cap = total;
        r->data = (uint8_t*)blink_realloc(r->data, (size_t)old_cap, (size_t)r->cap);
    }
    if (a->len > 0) memcpy(r->data, a->data, (size_t)a->len);
    if (b->len > 0) memcpy(r->data + a->len, b->data, (size_t)b->len);
    r->len = total;
    return r;
}
#endif

BLINK_RT_FN blink_bytes* blink_bytes_slice(const blink_bytes* b, int64_t start, int64_t end);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_bytes* blink_bytes_slice(const blink_bytes* b, int64_t start, int64_t end) {
    if (start < 0) start = 0;
    if (end > b->len) end = b->len;
    if (start > end) start = end;
    blink_bytes* r = blink_bytes_new();
    int64_t slen = end - start;
    if (slen > 0) {
        if (slen > r->cap) {
            int64_t old_cap = r->cap;
            r->cap = slen;
            r->data = (uint8_t*)blink_realloc(r->data, (size_t)old_cap, (size_t)r->cap);
        }
        memcpy(r->data, b->data + start, (size_t)slen);
        r->len = slen;
    }
    return r;
}
#endif

/* Validate UTF-8. Returns NULL on success, or a static error message on failure. */
BLINK_RT_FN const char* blink_bytes_validate_utf8(const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_bytes_validate_utf8(const blink_bytes* b) {
    int64_t i = 0;
    while (i < b->len) {
        uint8_t c = b->data[i];
        int64_t seq_len;
        if (c < 0x80) { seq_len = 1; }
        else if ((c & 0xE0) == 0xC0) { seq_len = 2; }
        else if ((c & 0xF0) == 0xE0) { seq_len = 3; }
        else if ((c & 0xF8) == 0xF0) { seq_len = 4; }
        else { return "invalid UTF-8: unexpected continuation byte"; }
        if (i + seq_len > b->len) { return "invalid UTF-8: truncated sequence"; }
        for (int64_t j = 1; j < seq_len; j++) {
            if ((b->data[i + j] & 0xC0) != 0x80) { return "invalid UTF-8: bad continuation byte"; }
        }
        i += seq_len;
    }
    return NULL;
}
#endif

BLINK_RT_FN blink_Result_str_str blink_bytes_to_str_result(const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_Result_str_str blink_bytes_to_str_result(const blink_bytes* b) {
    blink_Result_str_str r;
    const char* err = blink_bytes_validate_utf8(b);
    if (err != NULL) {
        r.tag = 1;
        r.err = err;
        return r;
    }
    char* s = (char*)blink_alloc(b->len + 1);
    memcpy(s, b->data, (size_t)b->len);
    s[b->len] = '\0';
    r.tag = 0;
    r.ok = s;
    return r;
}
#endif

BLINK_RT_FN const char* blink_bytes_to_hex(const blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_bytes_to_hex(const blink_bytes* b) {
    char* hex = (char*)blink_alloc(b->len * 2 + 1);
    for (int64_t i = 0; i < b->len; i++) {
        sprintf(hex + i * 2, "%02x", b->data[i]);
    }
    hex[b->len * 2] = '\0';
    return hex;
}
#endif

/* Fixed-width int read/write helpers. Callers (Blink wrappers) bounds-check
   before invoking reads, so these are unchecked. Writes grow the buffer
   through the same doubling policy as blink_bytes_push. */

BLINK_RT_FN void blinkrt_bytes_reserve(blink_bytes* b, int64_t extra);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_reserve(blink_bytes* b, int64_t extra) {
    int64_t needed = b->len + extra;
    if (needed <= b->cap) return;
    int64_t old_cap = b->cap;
    int64_t new_cap = b->cap > 0 ? b->cap : 16;
    while (new_cap < needed) new_cap *= 2;
    b->data = (uint8_t*)blink_realloc(b->data, (size_t)old_cap, (size_t)new_cap);
    b->cap = new_cap;
}
#endif

/* ── Reads: big-endian ────────────────────────────────────────────────── */

BLINK_RT_FN int64_t blinkrt_bytes_read_u16_be(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_u16_be(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    return (int64_t)(((uint16_t)p[0] << 8) | (uint16_t)p[1]);
}
#endif

BLINK_RT_FN int64_t blinkrt_bytes_read_u32_be(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_u32_be(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    uint32_t v = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
                 ((uint32_t)p[2] << 8)  | (uint32_t)p[3];
    return (int64_t)v;
}
#endif

BLINK_RT_FN int64_t blinkrt_bytes_read_i32_be(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_i32_be(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    uint32_t v = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
                 ((uint32_t)p[2] << 8)  | (uint32_t)p[3];
    return (int64_t)(int32_t)v;
}
#endif

BLINK_RT_FN int64_t blinkrt_bytes_read_i64_be(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_i64_be(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    uint64_t v = ((uint64_t)p[0] << 56) | ((uint64_t)p[1] << 48) |
                 ((uint64_t)p[2] << 40) | ((uint64_t)p[3] << 32) |
                 ((uint64_t)p[4] << 24) | ((uint64_t)p[5] << 16) |
                 ((uint64_t)p[6] << 8)  | (uint64_t)p[7];
    return (int64_t)v;
}
#endif

/* ── Reads: little-endian ─────────────────────────────────────────────── */

BLINK_RT_FN int64_t blinkrt_bytes_read_u16_le(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_u16_le(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    return (int64_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}
#endif

BLINK_RT_FN int64_t blinkrt_bytes_read_u32_le(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_u32_le(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    uint32_t v = (uint32_t)p[0]         | ((uint32_t)p[1] << 8) |
                 ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    return (int64_t)v;
}
#endif

BLINK_RT_FN int64_t blinkrt_bytes_read_i32_le(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_i32_le(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    uint32_t v = (uint32_t)p[0]         | ((uint32_t)p[1] << 8) |
                 ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    return (int64_t)(int32_t)v;
}
#endif

BLINK_RT_FN int64_t blinkrt_bytes_read_i64_le(blink_bytes* b, int64_t off);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blinkrt_bytes_read_i64_le(blink_bytes* b, int64_t off) {
    const uint8_t* p = b->data + off;
    uint64_t v = (uint64_t)p[0]         | ((uint64_t)p[1] << 8)  |
                 ((uint64_t)p[2] << 16) | ((uint64_t)p[3] << 24) |
                 ((uint64_t)p[4] << 32) | ((uint64_t)p[5] << 40) |
                 ((uint64_t)p[6] << 48) | ((uint64_t)p[7] << 56);
    return (int64_t)v;
}
#endif

/* ── Writes: big-endian ───────────────────────────────────────────────── */

BLINK_RT_FN void blinkrt_bytes_write_u16_be(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_u16_be(blink_bytes* b, int64_t v) {
    blinkrt_bytes_reserve(b, 2);
    uint16_t u = (uint16_t)(v & 0xFFFF);
    b->data[b->len++] = (uint8_t)(u >> 8);
    b->data[b->len++] = (uint8_t)(u & 0xFF);
}
#endif

BLINK_RT_FN void blinkrt_bytes_write_u32_be(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_u32_be(blink_bytes* b, int64_t v) {
    blinkrt_bytes_reserve(b, 4);
    uint32_t u = (uint32_t)(v & 0xFFFFFFFFLL);
    b->data[b->len++] = (uint8_t)(u >> 24);
    b->data[b->len++] = (uint8_t)((u >> 16) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 8) & 0xFF);
    b->data[b->len++] = (uint8_t)(u & 0xFF);
}
#endif

BLINK_RT_FN void blinkrt_bytes_write_i32_be(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_i32_be(blink_bytes* b, int64_t v) {
    blinkrt_bytes_write_u32_be(b, (int64_t)(uint32_t)(int32_t)v);
}
#endif

BLINK_RT_FN void blinkrt_bytes_write_i64_be(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_i64_be(blink_bytes* b, int64_t v) {
    blinkrt_bytes_reserve(b, 8);
    uint64_t u = (uint64_t)v;
    b->data[b->len++] = (uint8_t)(u >> 56);
    b->data[b->len++] = (uint8_t)((u >> 48) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 40) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 32) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 24) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 16) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 8) & 0xFF);
    b->data[b->len++] = (uint8_t)(u & 0xFF);
}
#endif

/* ── Writes: little-endian ────────────────────────────────────────────── */

BLINK_RT_FN void blinkrt_bytes_write_u16_le(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_u16_le(blink_bytes* b, int64_t v) {
    blinkrt_bytes_reserve(b, 2);
    uint16_t u = (uint16_t)(v & 0xFFFF);
    b->data[b->len++] = (uint8_t)(u & 0xFF);
    b->data[b->len++] = (uint8_t)(u >> 8);
}
#endif

BLINK_RT_FN void blinkrt_bytes_write_u32_le(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_u32_le(blink_bytes* b, int64_t v) {
    blinkrt_bytes_reserve(b, 4);
    uint32_t u = (uint32_t)(v & 0xFFFFFFFFLL);
    b->data[b->len++] = (uint8_t)(u & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 8) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 16) & 0xFF);
    b->data[b->len++] = (uint8_t)(u >> 24);
}
#endif

BLINK_RT_FN void blinkrt_bytes_write_i32_le(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_i32_le(blink_bytes* b, int64_t v) {
    blinkrt_bytes_write_u32_le(b, (int64_t)(uint32_t)(int32_t)v);
}
#endif

BLINK_RT_FN void blinkrt_bytes_write_i64_le(blink_bytes* b, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_write_i64_le(blink_bytes* b, int64_t v) {
    blinkrt_bytes_reserve(b, 8);
    uint64_t u = (uint64_t)v;
    b->data[b->len++] = (uint8_t)(u & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 8) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 16) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 24) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 32) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 40) & 0xFF);
    b->data[b->len++] = (uint8_t)((u >> 48) & 0xFF);
    b->data[b->len++] = (uint8_t)(u >> 56);
}
#endif

/* ── In-place sets at offset ──────────────────────────────────────────
   Callers (Blink wrappers) bounds-check off + width <= len before
   invoking, so these are unchecked. Sets write in-place; they do NOT
   grow the buffer (that's what write_*_le/be is for). */

BLINK_RT_FN void blinkrt_bytes_set_u16_be(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_u16_be(blink_bytes* b, int64_t off, int64_t v) {
    uint16_t u = (uint16_t)(v & 0xFFFF);
    uint8_t* p = b->data + off;
    p[0] = (uint8_t)(u >> 8);
    p[1] = (uint8_t)(u & 0xFF);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_u16_le(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_u16_le(blink_bytes* b, int64_t off, int64_t v) {
    uint16_t u = (uint16_t)(v & 0xFFFF);
    uint8_t* p = b->data + off;
    p[0] = (uint8_t)(u & 0xFF);
    p[1] = (uint8_t)(u >> 8);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_i16_be(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_i16_be(blink_bytes* b, int64_t off, int64_t v) {
    blinkrt_bytes_set_u16_be(b, off, (int64_t)(uint16_t)(int16_t)v);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_i16_le(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_i16_le(blink_bytes* b, int64_t off, int64_t v) {
    blinkrt_bytes_set_u16_le(b, off, (int64_t)(uint16_t)(int16_t)v);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_u32_be(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_u32_be(blink_bytes* b, int64_t off, int64_t v) {
    uint32_t u = (uint32_t)(v & 0xFFFFFFFFLL);
    uint8_t* p = b->data + off;
    p[0] = (uint8_t)(u >> 24);
    p[1] = (uint8_t)((u >> 16) & 0xFF);
    p[2] = (uint8_t)((u >> 8) & 0xFF);
    p[3] = (uint8_t)(u & 0xFF);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_u32_le(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_u32_le(blink_bytes* b, int64_t off, int64_t v) {
    uint32_t u = (uint32_t)(v & 0xFFFFFFFFLL);
    uint8_t* p = b->data + off;
    p[0] = (uint8_t)(u & 0xFF);
    p[1] = (uint8_t)((u >> 8) & 0xFF);
    p[2] = (uint8_t)((u >> 16) & 0xFF);
    p[3] = (uint8_t)(u >> 24);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_i32_be(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_i32_be(blink_bytes* b, int64_t off, int64_t v) {
    blinkrt_bytes_set_u32_be(b, off, (int64_t)(uint32_t)(int32_t)v);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_i32_le(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_i32_le(blink_bytes* b, int64_t off, int64_t v) {
    blinkrt_bytes_set_u32_le(b, off, (int64_t)(uint32_t)(int32_t)v);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_u64_be(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_u64_be(blink_bytes* b, int64_t off, int64_t v) {
    uint64_t u = (uint64_t)v;
    uint8_t* p = b->data + off;
    p[0] = (uint8_t)(u >> 56);
    p[1] = (uint8_t)((u >> 48) & 0xFF);
    p[2] = (uint8_t)((u >> 40) & 0xFF);
    p[3] = (uint8_t)((u >> 32) & 0xFF);
    p[4] = (uint8_t)((u >> 24) & 0xFF);
    p[5] = (uint8_t)((u >> 16) & 0xFF);
    p[6] = (uint8_t)((u >> 8) & 0xFF);
    p[7] = (uint8_t)(u & 0xFF);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_u64_le(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_u64_le(blink_bytes* b, int64_t off, int64_t v) {
    uint64_t u = (uint64_t)v;
    uint8_t* p = b->data + off;
    p[0] = (uint8_t)(u & 0xFF);
    p[1] = (uint8_t)((u >> 8) & 0xFF);
    p[2] = (uint8_t)((u >> 16) & 0xFF);
    p[3] = (uint8_t)((u >> 24) & 0xFF);
    p[4] = (uint8_t)((u >> 32) & 0xFF);
    p[5] = (uint8_t)((u >> 40) & 0xFF);
    p[6] = (uint8_t)((u >> 48) & 0xFF);
    p[7] = (uint8_t)(u >> 56);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_i64_be(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_i64_be(blink_bytes* b, int64_t off, int64_t v) {
    blinkrt_bytes_set_u64_be(b, off, v);
}
#endif

BLINK_RT_FN void blinkrt_bytes_set_i64_le(blink_bytes* b, int64_t off, int64_t v);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blinkrt_bytes_set_i64_le(blink_bytes* b, int64_t off, int64_t v) {
    blinkrt_bytes_set_u64_le(b, off, v);
}
#endif

BLINK_RT_FN blink_bytes* blink_bytes_zeroed(int64_t n);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_bytes* blink_bytes_zeroed(int64_t n) {
    if (n < 0) n = 0;
    blink_bytes* b = (blink_bytes*)blink_alloc(sizeof(blink_bytes));
    b->cap = n > 16 ? n : 16;
    b->len = n;
    b->data = (uint8_t*)blink_alloc((size_t)b->cap);
    if (n > 0) memset(b->data, 0, (size_t)n);
    return b;
}
#endif

BLINK_RT_FN blink_bytes* blink_bytes_from_str(const char* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_bytes* blink_bytes_from_str(const char* s) {
    blink_bytes* b = blink_bytes_new();
    int64_t slen = (int64_t)strlen(s);
    if (slen > b->cap) {
        int64_t old_cap = b->cap;
        b->cap = slen;
        b->data = (uint8_t*)blink_realloc(b->data, (size_t)old_cap, (size_t)b->cap);
    }
    memcpy(b->data, s, (size_t)slen);
    b->len = slen;
    return b;
}
#endif

BLINK_RT_FN void blink_bytes_free(blink_bytes* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_bytes_free(blink_bytes* b) {
    if (b) {
        GC_FREE(b->data);
        GC_FREE(b);
    }
}
#endif

/* ── StringBuilder ──────────────────────────────────────────────────── */

typedef struct {
    char* data;
    int64_t len;
    int64_t cap;
} blink_sb;

BLINK_RT_FN blink_sb* blink_sb_new(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_sb* blink_sb_new(void) {
    blink_sb* sb = (blink_sb*)blink_alloc(sizeof(blink_sb));
    sb->cap = 64;
    sb->len = 0;
    sb->data = (char*)blink_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}
#endif

BLINK_RT_FN blink_sb* blink_sb_with_capacity(int64_t cap);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_sb* blink_sb_with_capacity(int64_t cap) {
    if (cap < 16) cap = 16;
    blink_sb* sb = (blink_sb*)blink_alloc(sizeof(blink_sb));
    sb->cap = cap;
    sb->len = 0;
    sb->data = (char*)blink_alloc((size_t)sb->cap);
    sb->data[0] = '\0';
    return sb;
}
#endif

BLINK_RT_FN void blink_sb_write_n(blink_sb* sb, const char* s, int64_t slen);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_write_n(blink_sb* sb, const char* s, int64_t slen) {
    if (slen == 0) return;
    int64_t needed = sb->len + slen + 1;
    if (needed > sb->cap) {
        int64_t old_cap = sb->cap;
        int64_t new_cap = sb->cap * 2;
        while (new_cap < needed) new_cap *= 2;
        sb->cap = new_cap;
        sb->data = (char*)blink_realloc(sb->data, (size_t)old_cap, (size_t)sb->cap);
    }
    memcpy(sb->data + sb->len, s, (size_t)slen);
    sb->len += slen;
    sb->data[sb->len] = '\0';
}
#endif

BLINK_RT_FN void blink_sb_write(blink_sb* sb, const char* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_write(blink_sb* sb, const char* s) {
    blink_sb_write_n(sb, s, (int64_t)strlen(s));
}
#endif

BLINK_RT_FN void blink_sb_write_char(blink_sb* sb, const char* ch);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_write_char(blink_sb* sb, const char* ch) {
    blink_sb_write(sb, ch);
}
#endif

BLINK_RT_FN void blink_sb_write_int(blink_sb* sb, int64_t val);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_write_int(blink_sb* sb, int64_t val) {
    char buf[32];
    int len = snprintf(buf, sizeof(buf), "%lld", (long long)val);
    blink_sb_write_n(sb, buf, (int64_t)len);
}
#endif

BLINK_RT_FN void blink_sb_write_float(blink_sb* sb, double val);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_write_float(blink_sb* sb, double val) {
    char buf[64];
    int len = snprintf(buf, sizeof(buf), "%g", val);
    blink_sb_write_n(sb, buf, (int64_t)len);
}
#endif

BLINK_RT_FN void blink_sb_write_bool(blink_sb* sb, int val);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_write_bool(blink_sb* sb, int val) {
    blink_sb_write(sb, val ? "true" : "false");
}
#endif

BLINK_RT_FN const char* blink_sb_to_str(const blink_sb* sb);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_sb_to_str(const blink_sb* sb) {
    return blink_strdup(sb->data);
}
#endif

BLINK_RT_FN int64_t blink_sb_len(const blink_sb* sb);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_sb_len(const blink_sb* sb) {
    return sb->len;
}
#endif

BLINK_RT_FN int64_t blink_sb_capacity(const blink_sb* sb);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_sb_capacity(const blink_sb* sb) {
    return sb->cap;
}
#endif

BLINK_RT_FN void blink_sb_clear(blink_sb* sb);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_clear(blink_sb* sb) {
    sb->len = 0;
    sb->data[0] = '\0';
}
#endif

BLINK_RT_FN int blink_sb_is_empty(const blink_sb* sb);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_sb_is_empty(const blink_sb* sb) {
    return sb->len == 0;
}
#endif

BLINK_RT_FN void blink_sb_free(blink_sb* sb);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_sb_free(blink_sb* sb) {
    if (sb) {
        GC_FREE(sb->data);
        GC_FREE(sb);
    }
}
#endif

/* ── String operations ──────────────────────────────────────────────── */

BLINK_RT_FN int64_t blink_str_len(const char* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_str_len(const char* s) {
    return (int64_t)strlen(s);
}
#endif

BLINK_RT_FN int64_t blink_str_char_at(const char* s, int64_t i);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_str_char_at(const char* s, int64_t i) {
    return (int64_t)(unsigned char)s[i];
}
#endif

BLINK_RT_FN const char* blink_str_substr(const char* s, int64_t start, int64_t len);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_str_substr(const char* s, int64_t start, int64_t len) {
    char* buf = (char*)blink_alloc(len + 1);
    memcpy(buf, s + start, (size_t)len);
    buf[len] = '\0';
    return buf;
}
#endif

BLINK_RT_FN const char* blink_str_from_char_code(int64_t code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_str_from_char_code(int64_t code) {
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
#endif

BLINK_RT_FN int64_t blink_char_validate_code_point(int64_t code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_char_validate_code_point(int64_t code) {
    if (code < 0 || code > 0x10FFFF) return -1;
    if (code >= 0xD800 && code <= 0xDFFF) return -1;
    return code;
}
#endif

BLINK_RT_FN const char* blink_char_to_str(int64_t code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_char_to_str(int64_t code) {
    return blink_str_from_char_code(code);
}
#endif

/* Debug-form of a Char: the character in single quotes, escaping exactly the
 * ratified Char-literal escape set (\n \r \t \\ \b \f \0 \'); every other scalar
 * (printable ASCII + all non-ASCII) is emitted as its literal UTF-8 char between
 * the quotes. Sole owner of Char quote/escape logic across every @derive(Debug)
 * site. See decisions/char-debug-form.md. A '\u{N}' form for non-printable
 * scalars with no named escape is deferred (task qvan6m); until then such a
 * scalar is emitted as its raw byte(s). */
BLINK_RT_FN const char* blink_char_debug(int64_t code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_char_debug(int64_t code) {
    const char* esc = 0;
    switch (code) {
        case '\n': esc = "\\n"; break;
        case '\r': esc = "\\r"; break;
        case '\t': esc = "\\t"; break;
        case '\\': esc = "\\\\"; break;
        case '\b': esc = "\\b"; break;
        case '\f': esc = "\\f"; break;
        case '\0': esc = "\\0"; break;
        case '\'': esc = "\\'"; break;
        default: break;
    }
    if (esc) {
        char* buf = (char*)blink_alloc(5);
        buf[0] = '\'';
        buf[1] = esc[0];
        buf[2] = esc[1];
        buf[3] = '\'';
        buf[4] = '\0';
        return buf;
    }
    const char* body = blink_str_from_char_code(code);
    int64_t n = 0;
    while (body[n] != '\0') n++;
    char* buf = (char*)blink_alloc(n + 3);
    buf[0] = '\'';
    for (int64_t i = 0; i < n; i++) buf[i + 1] = body[i];
    buf[n + 1] = '\'';
    buf[n + 2] = '\0';
    return buf;
}
#endif

BLINK_RT_FN int64_t blink_char_at_opt_raw(const char* s, int64_t i);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_char_at_opt_raw(const char* s, int64_t i) {
    int64_t slen = blink_str_len(s);
    if (i < 0 || i >= slen) return -1;
    unsigned char c = (unsigned char)s[i];
    if (c < 0x80) return (int64_t)c;
    if ((c & 0xE0) == 0xC0 && i + 1 < slen) {
        int64_t cp = ((int64_t)(c & 0x1F) << 6) | (s[i+1] & 0x3F);
        return cp;
    }
    if ((c & 0xF0) == 0xE0 && i + 2 < slen) {
        int64_t cp = ((int64_t)(c & 0x0F) << 12) | ((int64_t)(s[i+1] & 0x3F) << 6) | (s[i+2] & 0x3F);
        return cp;
    }
    if ((c & 0xF8) == 0xF0 && i + 3 < slen) {
        int64_t cp = ((int64_t)(c & 0x07) << 18) | ((int64_t)(s[i+1] & 0x3F) << 12) | ((int64_t)(s[i+2] & 0x3F) << 6) | (s[i+3] & 0x3F);
        return cp;
    }
    return -1;
}
#endif

BLINK_RT_FN int64_t blink_char_hash(int64_t code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_char_hash(int64_t code) {
    return code * (int64_t)2654435761LL;
}
#endif

BLINK_RT_FN const char* blink_str_concat(const char* a, const char* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_str_concat(const char* a, const char* b) {
    int64_t la = blink_str_len(a);
    int64_t lb = blink_str_len(b);
    char* buf = (char*)blink_alloc(la + lb + 1);
    memcpy(buf, a, (size_t)la);
    memcpy(buf + la, b, (size_t)lb);
    buf[la + lb] = '\0';
    return buf;
}
#endif

BLINK_RT_FN const char* blink_str_format(const char* fmt, ...);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_str_format(const char* fmt, ...) {
    va_list ap; va_start(ap, fmt);
    va_list ap2; va_copy(ap2, ap);
    int needed = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    if (needed < 0) { va_end(ap2); return ""; }
    char* buf = (char*)blink_alloc((int64_t)needed + 1);
    vsnprintf(buf, (size_t)needed + 1, fmt, ap2);
    va_end(ap2);
    return buf;
}
#endif

BLINK_RT_FN int blink_str_eq(const char* a, const char* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_str_eq(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}
#endif

BLINK_RT_FN int blink_str_cmp(const char* a, const char* b);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_str_cmp(const char* a, const char* b) {
    return strcmp(a, b);
}
#endif

BLINK_RT_FN int blink_str_contains(const char* s, const char* needle);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_str_contains(const char* s, const char* needle) {
    return strstr(s, needle) != NULL;
}
#endif

BLINK_RT_FN int blink_str_starts_with(const char* s, const char* prefix);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_str_starts_with(const char* s, const char* prefix) {
    size_t plen = strlen(prefix);
    return strncmp(s, prefix, plen) == 0;
}
#endif

BLINK_RT_FN int blink_str_ends_with(const char* s, const char* suffix);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_str_ends_with(const char* s, const char* suffix) {
    size_t slen = strlen(s);
    size_t sufflen = strlen(suffix);
    if (sufflen > slen) return 0;
    return memcmp(s + slen - sufflen, suffix, sufflen) == 0;
}
#endif

BLINK_RT_FN const char* blink_str_slice(const char* s, int64_t start, int64_t end);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_str_slice(const char* s, int64_t start, int64_t end) {
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
#endif

BLINK_RT_FN int64_t blink_str_index_of(const char* s, const char* needle);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_str_index_of(const char* s, const char* needle) {
    if (!s || !needle) return -1;
    const char* found = strstr(s, needle);
    if (!found) return -1;
    return (int64_t)(found - s);
}
#endif

/* ── File I/O ───────────────────────────────────────────────────────── */

/* ── Filesystem error side-channel ──────────────────────────────────────
   The raw fs syscalls record errno here (0 on success) instead of exiting,
   so a Blink Result[T, FsError] wrapper can turn a failure into Err. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    __thread int64_t blink_fs_errno = 0;
  #else
    extern __thread int64_t blink_fs_errno;
  #endif
#else
BLINK_UNUSED static __thread int64_t blink_fs_errno = 0;
#endif

BLINK_RT_FN int64_t blink_fs_errno_get(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_fs_errno_get(void) {
    return blink_fs_errno;
}
#endif

BLINK_RT_FN const char* blink_read_file(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_read_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        blink_fs_errno = (int64_t)errno;
        return "";
    }
    blink_fs_errno = 0;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)blink_alloc(size + 1);
    fread(buf, 1, (size_t)size, f);
    buf[size] = '\0';
    fclose(f);
    return buf;
}
#endif

BLINK_RT_FN void blink_write_file(const char* path, const char* content);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_write_file(const char* path, const char* content) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        blink_fs_errno = (int64_t)errno;
        return;
    }
    size_t len = strlen(content);
    size_t wrote = fwrite(content, 1, len, f);
    if (wrote != len) {
        int e = errno;
        fclose(f);
        blink_fs_errno = (int64_t)(e != 0 ? e : EIO);
        return;
    }
    if (fclose(f) != 0) {
        blink_fs_errno = (int64_t)errno;
        return;
    }
    blink_fs_errno = 0;
}
#endif

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    int blink_g_argc = 0;
    const char** blink_g_argv = NULL;
  #else
    extern int blink_g_argc;
    extern const char** blink_g_argv;
  #endif
#else
BLINK_UNUSED static int blink_g_argc = 0;
BLINK_UNUSED static const char** blink_g_argv = NULL;
#endif

BLINK_RT_FN int64_t blink_arg_count(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_arg_count(void) {
    return (int64_t)blink_g_argc;
}
#endif

BLINK_RT_FN const char* blink_get_arg(int64_t index);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_get_arg(int64_t index) {
    if (index < 0 || index >= blink_g_argc) {
        __blink_panic_dispatchf("blink: arg index out of bounds: %lld", (long long)index);
    }
    return blink_g_argv[index];
}
#endif

BLINK_RT_FN int64_t blink_file_exists(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_file_exists(const char* path) {
    return access(path, F_OK) == 0 ? 1 : 0;
}
#endif

BLINK_RT_FN int64_t blink_is_dir(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_is_dir(const char* path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode) ? 1 : 0;
}
#endif

BLINK_RT_FN blink_list* blink_list_dir(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_list_dir(const char* path) {
    blink_list* result = blink_list_new();
    DIR* d = opendir(path);
    if (!d) {
        blink_fs_errno = (int64_t)errno;
        return result;
    }
    blink_fs_errno = 0;
    struct dirent* entry;
    while ((entry = readdir(d)) != NULL) {
        if (entry->d_name[0] == '.' && (entry->d_name[1] == '\0' ||
            (entry->d_name[1] == '.' && entry->d_name[2] == '\0'))) continue;
        blink_list_push(result, (void*)blink_strdup(entry->d_name));
    }
    closedir(d);
    return result;
}
#endif

BLINK_RT_FN int64_t blink_file_mtime(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_file_mtime(const char* path) {
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
#endif

/* ── Process info ───────────────────────────────────────────────────── */

BLINK_RT_FN int64_t blink_getpid(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_getpid(void) {
    return (int64_t)getpid();
}
#endif

BLINK_RT_FN void blink_exit(int64_t code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_exit(int64_t code) { exit((int)code); }
#endif

BLINK_RT_FN int64_t blink_shell_exec(const char* command);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_shell_exec(const char* command) {
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
#endif

/* ── Type helpers ───────────────────────────────────────────────────── */

typedef struct {
    const char* message;
    const char* source_type;
    const char* target_type;
} blink_ConversionError;

struct blink_closure_;
typedef struct blink_closure_ blink_closure;
typedef blink_closure* (*blink_closure_promoter_fn)(blink_arena_t*, blink_closure*);

struct blink_closure_ {
    void* fn_ptr;
    void** captures;
    int64_t capture_count;
    const char** capture_descs;
    blink_closure_promoter_fn promoter;
};

BLINK_RT_FN blink_closure* blink_closure_new_typed(void* fn_ptr, void** captures, const char** capture_descs, int64_t capture_count, blink_closure_promoter_fn promoter);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_closure* blink_closure_new_typed(void* fn_ptr, void** captures, const char** capture_descs, int64_t capture_count, blink_closure_promoter_fn promoter) {
    blink_closure* c = (blink_closure*)blink_alloc(sizeof(blink_closure));
    c->fn_ptr = fn_ptr;
    c->captures = captures;
    c->capture_count = capture_count;
    c->capture_descs = capture_descs;
    c->promoter = promoter;
    return c;
}
#endif

BLINK_RT_FN void* blink_closure_get_fn(const blink_closure* c);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_closure_get_fn(const blink_closure* c) {
    return c->fn_ptr;
}
#endif

BLINK_RT_FN void* blink_closure_get_capture(const blink_closure* c, int64_t index);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_closure_get_capture(const blink_closure* c, int64_t index) {
    if (index < 0 || index >= c->capture_count) {
        fprintf(stderr, "blink: closure capture index out of bounds: %lld\n", (long long)index);
        exit(1);
    }
    return c->captures[index];
}
#endif

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
    /* Handler captures, ONE slot per op. A handler expression allocates its own
     * copy of this vtable and stores its captured bindings in the slot of each
     * op it defines — one value directly in the word, several boxed into an
     * emitted caps struct. Per-op (not one shared word) so that an inner partial
     * handler, which copies this vtable and overwrites only its own ops' slots,
     * leaves an inherited op reading the OUTER handler's captures (saf1hh). The
     * slots are LAST so the positional `_default` initializers below stay aligned
     * and leave them NULL. The user-effect vtables codegen emits (`codegen.bl`)
     * carry the same per-op slots; a builtin effect without any is why br wxxg4f
     * could not capture at all. */
    void* __userdata_print;
    void* __userdata_print_no_nl;
    void* __userdata_log;
    void* __userdata_eprint;
    void* __userdata_eprint_no_nl;
} blink_io_vtable;

BLINK_RT_FN void blink_io_default_print(const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_io_default_print(const char* msg) {
    printf("%s\n", msg);
}
#endif

BLINK_RT_FN void blink_io_default_print_no_nl(const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_io_default_print_no_nl(const char* msg) {
    printf("%s", msg);
}
#endif

BLINK_RT_FN void blink_io_default_log(const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_io_default_log(const char* msg) {
    fprintf(stderr, "[LOG] %s\n", msg);
}
#endif

BLINK_RT_FN void blink_io_default_eprint(const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_io_default_eprint(const char* msg) {
    fprintf(stderr, "%s\n", msg);
}
#endif

BLINK_RT_FN void blink_io_default_eprint_no_nl(const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_io_default_eprint_no_nl(const char* msg) {
    fprintf(stderr, "%s", msg);
}
#endif

/* Vtables stay per-TU (not externalized like other globals). They are
 * read-only tables of pointers to externalized runtime helpers, so each
 * TU's copy resolves to the same archive-side functions. User-TU main()
 * takes the address of its own copy when wiring up `__blink_ev`; archive
 * functions never need to share vtable identity. */
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
    /* per-op handler captures — see blink_io_vtable */
    void* __userdata_read;
    void* __userdata_write;
    void* __userdata_delete_file;
    void* __userdata_watch;
} blink_fs_vtable;

BLINK_RT_FN const char* blink_fs_default_read(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_fs_default_read(const char* path) {
    return blink_read_file(path);
}
#endif

BLINK_RT_FN int blink_fs_default_write(const char* path, const char* content);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_fs_default_write(const char* path, const char* content) {
    blink_write_file(path, content);
    return 0;
}
#endif

BLINK_RT_FN int blink_fs_default_delete(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_fs_default_delete(const char* path) {
    return remove(path);
}
#endif

BLINK_RT_FN void blink_fs_remove(const char* path);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_fs_remove(const char* path) {
    if (unlink(path) != 0) {
        blink_fs_errno = (int64_t)errno;
    } else {
        blink_fs_errno = 0;
    }
}
#endif

BLINK_RT_FN int blink_fs_default_watch(const char* path, void (*callback)(const char*));
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_fs_default_watch(const char* path, void (*callback)(const char*)) {
    (void)path; (void)callback;
    fprintf(stderr, "blink: fs.watch not implemented\n");
    return -1;
}
#endif

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
    /* per-op handler captures — see blink_io_vtable */
    void* __userdata_connect;
    void* __userdata_listen;
    void* __userdata_dns;
} blink_net_vtable;

BLINK_RT_FN int blink_net_default_connect(const char* url);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_net_default_connect(const char* url) {
    (void)url;
    fprintf(stderr, "blink: net.connect not implemented\n");
    return -1;
}
#endif

BLINK_RT_FN int blink_net_default_listen(const char* addr, int port);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_net_default_listen(const char* addr, int port) {
    (void)addr; (void)port;
    fprintf(stderr, "blink: net.listen not implemented\n");
    return -1;
}
#endif

BLINK_RT_FN const char* blink_net_default_dns(const char* hostname);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_net_default_dns(const char* hostname) {
    (void)hostname;
    fprintf(stderr, "blink: net.dns not implemented\n");
    return NULL;
}
#endif

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
    /* per-op handler captures — see blink_io_vtable */
    void* __userdata_hash;
    void* __userdata_sign;
    void* __userdata_encrypt;
    void* __userdata_decrypt;
} blink_crypto_vtable;

BLINK_RT_FN const char* blink_crypto_default_hash(const char* data);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_crypto_default_hash(const char* data) {
    (void)data;
    fprintf(stderr, "blink: crypto.hash not implemented\n");
    return NULL;
}
#endif

BLINK_RT_FN const char* blink_crypto_default_sign(const char* data, const char* key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_crypto_default_sign(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.sign not implemented\n");
    return NULL;
}
#endif

BLINK_RT_FN const char* blink_crypto_default_encrypt(const char* data, const char* key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_crypto_default_encrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.encrypt not implemented\n");
    return NULL;
}
#endif

BLINK_RT_FN const char* blink_crypto_default_decrypt(const char* data, const char* key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_crypto_default_decrypt(const char* data, const char* key) {
    (void)data; (void)key;
    fprintf(stderr, "blink: crypto.decrypt not implemented\n");
    return NULL;
}
#endif

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
    /* per-op handler captures — see blink_io_vtable */
    void* __userdata_rand_int;
    void* __userdata_rand_float;
    void* __userdata_rand_bytes;
} blink_rand_vtable;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    int blink_rand_seeded = 0;
  #else
    extern int blink_rand_seeded;
  #endif
#else
BLINK_UNUSED static int blink_rand_seeded = 0;
#endif

BLINK_RT_FN void blink_rand_ensure_seed(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_rand_ensure_seed(void) {
    if (!blink_rand_seeded) {
        srand((unsigned)42);
        blink_rand_seeded = 1;
    }
}
#endif

BLINK_RT_FN int64_t blink_rand_default_int(int64_t min, int64_t max);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_rand_default_int(int64_t min, int64_t max) {
    blink_rand_ensure_seed();
    if (min >= max) return min;
    return min + (int64_t)(rand() % (int)(max - min));
}
#endif

BLINK_RT_FN double blink_rand_default_float(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN double blink_rand_default_float(void) {
    blink_rand_ensure_seed();
    return (double)rand() / (double)RAND_MAX;
}
#endif

BLINK_RT_FN void blink_rand_default_bytes(void* buf, int64_t len);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_rand_default_bytes(void* buf, int64_t len) {
    blink_rand_ensure_seed();
    unsigned char* p = (unsigned char*)buf;
    for (int64_t i = 0; i < len; i++) {
        p[i] = (unsigned char)(rand() & 0xFF);
    }
}
#endif

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

BLINK_RT_FN const char* blink_Instant_to_rfc3339(blink_instant_struct i);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_Instant_to_rfc3339(blink_instant_struct i) {
    time_t epoch_secs = (time_t)(i.nanos / 1000000000LL);
    struct tm utc;
    gmtime_r(&epoch_secs, &utc);
    char* buf = (char*)blink_alloc(64);
    snprintf(buf, 64, "%04d-%02d-%02dT%02d:%02d:%02dZ",
             utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday,
             utc.tm_hour, utc.tm_min, utc.tm_sec);
    return buf;
}
#endif

BLINK_RT_FN blink_duration_struct blink_Instant_elapsed(blink_instant_struct then);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_duration_struct blink_Instant_elapsed(blink_instant_struct then) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t now_nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
    return (blink_duration_struct){.nanos = now_nanos - then.nanos};
}
#endif

/* ── Time ───────────────────────────────────────────────────────────── */
typedef struct {
    blink_instant_struct (*read)(void);
    void                (*sleep)(blink_duration_struct d);
    /* per-op handler captures — see blink_io_vtable */
    void* __userdata_read;
    void* __userdata_sleep;
} blink_time_vtable;

BLINK_RT_FN blink_instant_struct blink_time_default_read(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_instant_struct blink_time_default_read(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (blink_instant_struct){.nanos = (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec};
}
#endif

BLINK_RT_FN void blink_time_default_sleep(blink_duration_struct d);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_time_default_sleep(blink_duration_struct d) {
    int64_t ns = d.nanos;
    struct timespec ts;
    ts.tv_sec  = (time_t)(ns / 1000000000LL);
    ts.tv_nsec = (long)(ns % 1000000000LL);
    nanosleep(&ts, NULL);
}
#endif

BLINK_UNUSED static blink_time_vtable blink_time_vtable_default = {
    blink_time_default_read,
    blink_time_default_sleep
};

BLINK_RT_FN int64_t blink_time_ms(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_time_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + (int64_t)(ts.tv_nsec / 1000000);
}
#endif

/* ── Env ────────────────────────────────────────────────────────────── */
typedef struct {
    const char* (*read)(const char* name);
    int         (*write)(const char* name, const char* value);
    int         (*remove)(const char* name);
    const char* (*cwd)(void);
    void        (*exit_fn)(int code);
    /* per-op handler captures — see blink_io_vtable */
    void* __userdata_read;
    void* __userdata_write;
    void* __userdata_remove;
    void* __userdata_cwd;
    void* __userdata_exit_fn;
} blink_env_vtable;

BLINK_RT_FN const char* blink_env_default_read(const char* name);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_env_default_read(const char* name) {
    const char* v = getenv(name);
    return v ? blink_strdup(v) : NULL;
}
#endif

BLINK_RT_FN int blink_env_default_write(const char* name, const char* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_env_default_write(const char* name, const char* value) {
    return setenv(name, value, 1);
}
#endif

BLINK_RT_FN int blink_env_default_remove(const char* name);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_env_default_remove(const char* name) {
    return unsetenv(name);
}
#endif

BLINK_RT_FN const char* blink_env_default_cwd(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_env_default_cwd(void) {
    char buf[4096];
    char* r = getcwd(buf, sizeof(buf));
    if (!r) { fprintf(stderr, "blink: getcwd failed, falling back to \".\"\n"); }
    return r ? blink_strdup(r) : blink_strdup(".");
}
#endif

BLINK_RT_FN void blink_env_default_exit(int code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_env_default_exit(int code) {
    exit(code);
}
#endif

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
    /* per-op handler captures — see blink_io_vtable */
    void* __userdata_spawn;
    void* __userdata_signal;
} blink_process_vtable;

BLINK_RT_FN int64_t blink_process_default_spawn(const char* command);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_process_default_spawn(const char* command) {
    (void)command;
    fprintf(stderr, "blink: process.spawn not implemented\n");
    return -1;
}
#endif

BLINK_RT_FN int blink_process_default_signal(int64_t pid, int sig);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_process_default_signal(int64_t pid, int sig) {
    (void)pid; (void)sig;
    fprintf(stderr, "blink: process.signal not implemented\n");
    return -1;
}
#endif

BLINK_UNUSED static blink_process_vtable blink_process_vtable_default = {
    blink_process_default_spawn,
    blink_process_default_signal
};

/* ── Debug assert ───────────────────────────────────────────────────── */

BLINK_RT_FN void __blink_debug_assert_fail(const char* file, int line, const char* fn, const char* cond, const char* msg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_debug_assert_fail(const char* file, int line, const char* fn, const char* cond, const char* msg) {
    fprintf(stderr, "DEBUG ASSERT FAILED: %s\n", msg);
    fprintf(stderr, "  condition: %s\n", cond);
    fprintf(stderr, "  location: %s:%d in %s\n", file, line, fn);
    exit(1);
}
#endif

/* ── FFI scope helpers ─────────────────────────────────────────────── */

BLINK_RT_FN blink_list* blink_ffi_scope_new(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_list* blink_ffi_scope_new(void) {
    return blink_list_new();
}
#endif

BLINK_RT_FN void* blink_ffi_scope_track(blink_list* scope, void* ptr);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_ffi_scope_track(blink_list* scope, void* ptr) {
    blink_list_push(scope, ptr);
    return ptr;
}
#endif

/* Scoped C-string copy. Scope-tracked memory is handed to C and must be
   libc-allocated so blink_ffi_scope_cleanup can free() it (a GC copy via
   blink_strdup could not be freed with libc free(), and freeing libc
   memory with GC_FREE is UB). */
BLINK_RT_FN void* blink_ffi_scope_cstr(blink_list* scope, const char* s);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_ffi_scope_cstr(blink_list* scope, const char* s) {
    if (!s) { return blink_ffi_scope_track(scope, NULL); }
    size_t len = strlen(s) + 1;
    char* p = (char*)malloc(len);
    if (!p) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    memcpy(p, s, len);
    return blink_ffi_scope_track(scope, p);
}
#endif

BLINK_RT_FN void* blink_ffi_scope_take(blink_list* scope, void* ptr);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_ffi_scope_take(blink_list* scope, void* ptr) {
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
#endif

BLINK_RT_FN void blink_ffi_scope_cleanup(blink_list* scope);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_ffi_scope_cleanup(blink_list* scope) {
    /* Tracked items are libc-allocated FFI memory (calloc via scope.alloc/
       alloc_n, malloc via blink_ffi_scope_cstr) — free them with libc free().
       GC_FREE here would be UB on non-GC pointers and segfaults. The list
       backing store and the list struct are GC memory; let the collector
       reclaim them (GC_FREE is a no-op hint at best and risks double-handling
       if the list is still reachable). */
    for (int64_t i = 0; i < scope->len; i++) {
        free(scope->items[i]);
    }
    scope->len = 0;
}
#endif

/* Attribute-cleanup state for `with ffi.scope() as scope { ... }`. Cleanup
   must fire on EVERY exit path — fall-through, return, ? early return, and a
   caught panic (longjmp). __attribute__((cleanup)) covers the C control-flow
   exits; the longjmp dispatch (§2.20 cleanup-stack) covers the panic path,
   mirroring the Closeable with-resource machinery. */
typedef struct { blink_list* scope; int done; } __blink_ffi_scope_state;

BLINK_RT_FN void __blink_ffi_scope_run(void* p, int ok);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_ffi_scope_run(void* p, int ok) {
    (void)ok;
    __blink_ffi_scope_state* st = (__blink_ffi_scope_state*)p;
    if (st->done) { return; }
    st->done = 1;
    blink_ffi_scope_cleanup(st->scope);
}
#endif

BLINK_RT_FN void __blink_ffi_scope_attr_cleanup(__blink_ffi_scope_state* st);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void __blink_ffi_scope_attr_cleanup(__blink_ffi_scope_state* st) {
    __blink_cleanup_pop((void*)st);
    __blink_ffi_scope_run((void*)st, 0);
}
#endif

#endif
