#ifndef BLINK_RUNTIME_TEST_H
#define BLINK_RUNTIME_TEST_H

#include <setjmp.h>
#include <time.h>

typedef struct {
    const char* name;
    void (*fn)(void);
    const char* file;
    int line;
    int skip;
    const char** tags;
    int tag_count;
    int expected_fail;
    const char* xfail_reason;
} blink_test_entry;

/* Per-test state. The runner sets the per-test frame, but an assert, a skip or a
 * for_each case can run in any unit linked into the binary: the stdlib archive, a
 * compiler archive, another module's unit. So the state is one set per binary,
 * defined by the unit that defines the runtime storage. It is also one set per
 * thread, as the panic catch state is: an assert on a spawned task must never
 * write the runner's record or jump into its frame on another thread's stack. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    #define BLINK_TEST_STORAGE __thread
  #else
    #define BLINK_TEST_STORAGE extern __thread
  #endif
#else
  #define BLINK_TEST_STORAGE BLINK_UNUSED static __thread
#endif

BLINK_TEST_STORAGE jmp_buf __blink_test_jmp;
BLINK_TEST_STORAGE int __blink_test_failed;
BLINK_TEST_STORAGE char __blink_test_fail_msg[512];
BLINK_TEST_STORAGE int __blink_test_fail_line;
/* assert_eq separate expected/actual rendering (spec §8.10): expected = the
 * RHS argument, actual = the LHS argument. Non-empty only when the failure
 * came through __blink_assert_fail_eq; plain assert(...) leaves them empty. */
BLINK_TEST_STORAGE char __blink_test_fail_expected[256];
BLINK_TEST_STORAGE char __blink_test_fail_actual[256];
/* Power-assert introspection. When non-empty, these supplement the legacy
 * fail_msg with structured assertion text, sub-expression values, and a
 * span. The runner uses them for human and JSON output. */
BLINK_TEST_STORAGE char __blink_test_fail_assertion[256];
#define BLINK_PA_INTRO_BUF_SIZE 1024
BLINK_TEST_STORAGE char __blink_test_fail_intro[BLINK_PA_INTRO_BUF_SIZE];
BLINK_TEST_STORAGE char __blink_test_fail_file[256];
BLINK_TEST_STORAGE int __blink_test_fail_col;
BLINK_TEST_STORAGE char __blink_test_fail_user_msg[256];
/* Cause discriminator for NDJSON output: "assertion", or "propagated_error"
 * from __blink_test_set_propagate for spec §2.20 test-body `?` propagation.
 * The runner sets it at the start of each test, before anything reads it. */
BLINK_TEST_STORAGE const char* __blink_test_fail_cause;
BLINK_TEST_STORAGE char __blink_test_fail_error_type[128];
BLINK_TEST_STORAGE char __blink_test_fail_error_message[512];
/* Label of the for_each case that is running. After the loop it holds the
 * label of the case whose failure the test reports, so the runner can emit it
 * in the JSON "case" field, and is empty when no case failed. */
BLINK_TEST_STORAGE char __blink_test_case_label[256];
/* Cleanup depth at the frame __blink_test_jmp points to. An assertion failure
 * runs the armed `with` cleanups above it before the longjmp, while their
 * guards are still on the stack. */
BLINK_TEST_STORAGE size_t __blink_test_jmp_mark;

/* One record per for_each case that ran, written by blink_test_run_case.
 * Accumulate-then-emit, mirroring __blink_cleanup_warnings.
 * The records sit behind a pointer the runner allocates on its own thread, so
 * every other thread pays one pointer of thread-local storage and records
 * nothing. The array starts at BLINK_TEST_CASE_INITIAL entries and doubles
 * each time the count reaches a power of two past that, so every case that
 * ran keeps its record and no separate capacity is stored. Reset per test. */
#define BLINK_TEST_CASE_INITIAL 16
#define BLINK_TEST_CASE_PASSED 0
#define BLINK_TEST_CASE_FAILED 1
#define BLINK_TEST_CASE_SKIPPED 2
#define BLINK_TEST_CASE_PANICKED 3
typedef struct {
    char label[256];
    int status; /* one of BLINK_TEST_CASE_* */
    char* message; /* the panic message of a panicked case, else NULL */
} blink_test_case_record;
BLINK_TEST_STORAGE blink_test_case_record* __blink_test_case_records;
BLINK_TEST_STORAGE int __blink_test_case_record_count;
/* for_each cases that skipped: the test is skipped only when every case it
 * ran skipped. Reset per test. */
BLINK_TEST_STORAGE int __blink_test_case_skip_count;

/* Skip state. Propagated via Result-sentinel (set globals + plain `return`)
 * so __attribute__((cleanup)) destructors fire for in-scope `with` blocks. */
BLINK_TEST_STORAGE int __blink_test_skipped;
BLINK_TEST_STORAGE char __blink_test_skip_reason[256];

/* Units read only these declarations, and one unit holds the bodies, so an -O0 unit does
 * not compile a copy of each one. */
BLINK_RT_FN void __blink_assert_fail(const char* msg, int line);
BLINK_RT_FN void __blink_assert_fail_eq(const char* msg, const char* expected, const char* actual, int line);
BLINK_RT_FN void __blink_assert_fail_intro(const char* assertion, const char* intro, const char* file, int line, int col, const char* user_msg);
BLINK_RT_FN void __blink_test_set_propagate(const char* message, const char* error_type, const char* file, int line, int col);
BLINK_RT_FN void __blink_test_set_skipped(const char* reason);
BLINK_RT_FN void __blink_assert_panics_returned(const char* file, int line, int col);
BLINK_RT_FN void __blink_assert_panics_mismatch(const char* expected, const char* actual, const char* file, int line, int col);
BLINK_RT_FN void blink_test_run_case(const char* label, const char* duplicate, blink_closure* body);
BLINK_RT_FN void blink_test_run(const blink_test_entry* tests, int count, int argc, const char** argv);

/* That unit is the one that defines the runtime storage, except in the stdlib archive: it
 * compiles them in a member of their own, in parallel with its monolith. */
#ifndef BLINK_RUNTIME_DECLS_ONLY
#ifndef BLINK_RUNTIME_TEST_BODIES_APART
#define BLINK_RUNTIME_TEST_BODIES 1
#endif
#endif
#ifdef BLINK_RUNTIME_TEST_BODIES_UNIT
#define BLINK_RUNTIME_TEST_BODIES 1
#endif

#ifdef BLINK_RUNTIME_TEST_BODIES

/* Spec §2.20: an assertion failure panics. Outside a test run there is no
 * per-test frame to longjmp to, so the failure is an uncaught panic. The
 * runner's panic hook is the marker for a test run. Renders the recorded
 * failure the way the runner's human output does. */
BLINK_UNUSED static void __blink_assert_fail_uncaught(void) {
    char buf[BLINK_PA_INTRO_BUF_SIZE + 2048];
    size_t n = 0;
    if (__blink_test_fail_assertion[0]) {
        n += snprintf(buf + n, sizeof(buf) - n, "assertion failed: %s", __blink_test_fail_assertion);
        if (__blink_test_fail_user_msg[0] && n < sizeof(buf)) {
            n += snprintf(buf + n, sizeof(buf) - n, "\n    message: %s", __blink_test_fail_user_msg);
        }
        if (__blink_test_fail_intro[0] && n < sizeof(buf)) {
            n += snprintf(buf + n, sizeof(buf) - n, "\n%s", __blink_test_fail_intro);
        }
        if (n < sizeof(buf)) {
            if (__blink_test_fail_file[0]) {
                snprintf(buf + n, sizeof(buf) - n, "\n  --> %s:%d:%d", __blink_test_fail_file,
                         __blink_test_fail_line, __blink_test_fail_col);
            } else {
                snprintf(buf + n, sizeof(buf) - n, "\n  (line %d)", __blink_test_fail_line);
            }
        }
    } else {
        snprintf(buf, sizeof(buf), "%s (line %d)", __blink_test_fail_msg, __blink_test_fail_line);
    }
    __blink_panic_dispatch(buf);
}

/* Unwind an assertion failure to the frame __blink_test_jmp points to: the
 * per-test frame or a for_each case frame. */
BLINK_UNUSED static void __blink_test_unwind(void) {
    __blink_cleanup_run_to(__blink_test_jmp_mark);
    longjmp(__blink_test_jmp, 1);
}

/* A test reports its first failure. An assertion that fails in a `with`
 * cleanup while an earlier failure or a panic unwinds is a secondary, kept as
 * a cleanup warning the way a panic there is (E0824); any later failure only
 * unwinds. Returns when this failure is the first, so the caller records it. */
BLINK_UNUSED static void __blink_test_fail_unless_first(const char* msg) {
    if (__blink_panic_test_hook == NULL) return;
    if (__blink_in_cleanup_drain) __blink_panic_dispatch(msg ? msg : "assertion failed");
    if (__blink_test_failed) __blink_test_unwind();
}

BLINK_RT_FN void __blink_assert_fail(const char* msg, int line) {
    __blink_test_fail_unless_first(msg);
    __blink_test_failed = 1;
    if (msg) {
        strncpy(__blink_test_fail_msg, msg, sizeof(__blink_test_fail_msg) - 1);
        __blink_test_fail_msg[sizeof(__blink_test_fail_msg) - 1] = '\0';
    } else {
        __blink_test_fail_msg[0] = '\0';
    }
    __blink_test_fail_line = line;
    __blink_test_fail_assertion[0] = '\0';
    __blink_test_fail_intro[0] = '\0';
    __blink_test_fail_file[0] = '\0';
    __blink_test_fail_col = 0;
    __blink_test_fail_user_msg[0] = '\0';
    __blink_test_fail_expected[0] = '\0';
    __blink_test_fail_actual[0] = '\0';
    if (__blink_panic_test_hook == NULL) __blink_assert_fail_uncaught();
    __blink_test_unwind();
}

#define BLINK_COPY_OR_EMPTY(dst, src) do { \
    if (src) { \
        strncpy((dst), (src), sizeof(dst) - 1); \
        (dst)[sizeof(dst) - 1] = '\0'; \
    } else { \
        (dst)[0] = '\0'; \
    } \
} while (0)

/* Append a finished for_each case record. status: one of BLINK_TEST_CASE_*.
 * message is the panic message of a panicked case, else NULL. */
BLINK_UNUSED static void blink_record_case(const char* label, int status, const char* message) {
    if (__blink_test_case_records == NULL) return;
    int n = __blink_test_case_record_count;
    if (n >= BLINK_TEST_CASE_INITIAL && (n & (n - 1)) == 0) {
        blink_test_case_record* grown = (blink_test_case_record*)realloc(
            __blink_test_case_records, (size_t)n * 2 * sizeof(blink_test_case_record));
        if (grown == NULL) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
        __blink_test_case_records = grown;
    }
    if (status == BLINK_TEST_CASE_SKIPPED) __blink_test_case_skip_count++;
    blink_test_case_record* r = &__blink_test_case_records[n];
    BLINK_COPY_OR_EMPTY(r->label, label);
    r->status = status;
    r->message = NULL;
    if (message) {
        size_t len = strlen(message) + 1;
        r->message = (char*)malloc(len);
        if (r->message == NULL) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
        memcpy(r->message, message, len);
    }
    __blink_test_case_record_count = n + 1;
}

BLINK_UNUSED static void __blink_test_case_records_reset(void) {
    for (int w = 0; w < __blink_test_case_record_count; w++) {
        free(__blink_test_case_records[w].message);
    }
    __blink_test_case_record_count = 0;
    __blink_test_case_skip_count = 0;
}

/* assert_eq failure: like __blink_assert_fail but also records the separately
 * rendered expected (RHS) and actual (LHS) operands for spec §8.10 JSON. */
BLINK_RT_FN void __blink_assert_fail_eq(const char* msg,
                                        const char* expected,
                                        const char* actual,
                                        int line) {
    __blink_test_fail_unless_first(msg);
    __blink_test_failed = 1;
    BLINK_COPY_OR_EMPTY(__blink_test_fail_msg, msg);
    __blink_test_fail_line = line;
    __blink_test_fail_assertion[0] = '\0';
    __blink_test_fail_intro[0] = '\0';
    __blink_test_fail_file[0] = '\0';
    __blink_test_fail_col = 0;
    __blink_test_fail_user_msg[0] = '\0';
    BLINK_COPY_OR_EMPTY(__blink_test_fail_expected, expected);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_actual, actual);
    if (__blink_panic_test_hook == NULL) __blink_assert_fail_uncaught();
    __blink_test_unwind();
}

BLINK_RT_FN void __blink_assert_fail_intro(const char* assertion,
                                           const char* intro,
                                           const char* file,
                                           int line, int col,
                                           const char* user_msg) {
    char msg[sizeof(__blink_test_fail_msg)];
    if (assertion && assertion[0]) {
        snprintf(msg, sizeof(msg), "assertion failed: %s", assertion);
    } else {
        snprintf(msg, sizeof(msg), "assertion failed");
    }
    __blink_test_fail_unless_first(msg);
    __blink_test_failed = 1;
    memcpy(__blink_test_fail_msg, msg, sizeof(msg));
    __blink_test_fail_line = line;
    __blink_test_fail_col = col;
    BLINK_COPY_OR_EMPTY(__blink_test_fail_assertion, assertion);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_intro, intro);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_file, file);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_user_msg, user_msg);
    __blink_test_fail_expected[0] = '\0';
    __blink_test_fail_actual[0] = '\0';
    if (__blink_panic_test_hook == NULL) __blink_assert_fail_uncaught();
    __blink_test_unwind();
}

/* Spec §2.20: ?-in-test propagation. No longjmp — caller emits `return;`
 * so cleanup destructors run for in-scope `with` bindings. */
BLINK_RT_FN void __blink_test_set_propagate(const char* message,
                                            const char* error_type,
                                            const char* file,
                                            int line, int col) {
    if (__blink_test_failed) return;
    __blink_test_failed = 1;
    __blink_test_fail_cause = "propagated_error";
    BLINK_COPY_OR_EMPTY(__blink_test_fail_error_message, message);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_error_type, error_type);
    snprintf(__blink_test_fail_msg, sizeof(__blink_test_fail_msg),
             "propagated %s: %s",
             (error_type && error_type[0]) ? error_type : "error",
             (message && message[0]) ? message : "");
    __blink_test_fail_line = line;
    __blink_test_fail_col = col;
    BLINK_COPY_OR_EMPTY(__blink_test_fail_file, file);
    __blink_test_fail_assertion[0] = '\0';
    __blink_test_fail_intro[0] = '\0';
    __blink_test_fail_user_msg[0] = '\0';
    __blink_test_fail_expected[0] = '\0';
    __blink_test_fail_actual[0] = '\0';
}

/* No longjmp — caller emits `return;` so cleanup destructors run. A skip
 * after the test already failed ends the test but keeps the failure. */
BLINK_RT_FN void __blink_test_set_skipped(const char* reason) {
    if (__blink_test_failed) return;
    __blink_test_skipped = 1;
    BLINK_COPY_OR_EMPTY(__blink_test_skip_reason, reason);
}

/* Spec §2.20 — assert_panics failures. Both reuse __blink_assert_fail_intro,
 * so they land in the existing __blink_test_fail_* record + JSON/human render
 * with zero new runner code, and longjmp to the per-test runner frame. */

/* E0831 — the block returned normally instead of panicking. */
BLINK_RT_FN void __blink_assert_panics_returned(const char* file, int line, int col) {
    __blink_assert_fail_intro(
        "assert_panics: expected the block to panic, but it returned normally",
        "", file, line, col, "");
}

/* E0832 — the block panicked but the message lacked the matching substring.
 * Renders the expected substring + the FULL actual panic message + origin. */
BLINK_RT_FN void __blink_assert_panics_mismatch(const char* expected,
                                                const char* actual,
                                                const char* file,
                                                int line, int col) {
    char __intro[BLINK_PA_INTRO_BUF_SIZE];
    snprintf(__intro, sizeof(__intro),
             "  expected panic message to contain: %s\n  actual panic message: %s",
             expected ? expected : "",
             actual ? actual : "");
    __blink_assert_fail_intro(
        "assert_panics: panic message did not contain the expected substring",
        __intro, file, line, col, "");
}

/* The cause a panic records. It is never printed: a panic is the status
 * `panicked`, which has no cause (spec §8.10, Panicked records). */
#define BLINK_TEST_CAUSE_PANIC "panic"
/* The cause an assertion failure leaves in place: assertions do not set it. */
#define BLINK_TEST_CAUSE_ASSERTION "assertion"

BLINK_UNUSED static int __blink_test_cause_is_panic(const char* cause) {
    return cause && strcmp(cause, BLINK_TEST_CAUSE_PANIC) == 0;
}

BLINK_UNUSED static int __blink_test_is_panicked(void) {
    return __blink_test_failed && __blink_test_cause_is_panic(__blink_test_fail_cause);
}

/* Record a panic that escaped a test body or a for_each case, unless the
 * test already failed. The runtime knows only the message, not where the
 * panic fired, so the record keeps no line. */
BLINK_UNUSED static void __blink_test_note_panic(const char* msg) {
    if (__blink_test_failed) return;
    __blink_test_failed = 1;
    __blink_test_fail_cause = BLINK_TEST_CAUSE_PANIC;
    BLINK_COPY_OR_EMPTY(__blink_test_fail_msg, msg);
    __blink_test_fail_error_message[0] = '\0';
    __blink_test_fail_error_type[0] = '\0';
    __blink_test_fail_line = 0;
    __blink_test_fail_assertion[0] = '\0';
    __blink_test_fail_intro[0] = '\0';
    __blink_test_fail_file[0] = '\0';
    __blink_test_fail_col = 0;
    __blink_test_fail_user_msg[0] = '\0';
    __blink_test_fail_expected[0] = '\0';
    __blink_test_fail_actual[0] = '\0';
}

/* Installed as __blink_panic_test_hook by blink_test_run. An uncaught panic in
 * a test body lands here instead of terminating the binary: record it and
 * longjmp to the per-test frame so the runner reports PANIC and continues with
 * the next test. */
BLINK_UNUSED static void __blink_test_panic_handler(const char* msg) {
    __blink_test_note_panic(msg);
    longjmp(__blink_test_jmp, 1);
}

/* The failure record of a test, saved while a for_each case runs, so the test
 * reports the first case that failed. */
typedef struct {
    const char* cause;
    int line;
    int col;
    char msg[sizeof(__blink_test_fail_msg)];
    char expected[sizeof(__blink_test_fail_expected)];
    char actual[sizeof(__blink_test_fail_actual)];
    char assertion[sizeof(__blink_test_fail_assertion)];
    char intro[sizeof(__blink_test_fail_intro)];
    char file[sizeof(__blink_test_fail_file)];
    char user_msg[sizeof(__blink_test_fail_user_msg)];
    char error_type[sizeof(__blink_test_fail_error_type)];
    char error_message[sizeof(__blink_test_fail_error_message)];
    char case_label[sizeof(__blink_test_case_label)];
} blink_test_fail_record;

BLINK_UNUSED static void __blink_test_fail_record_save(blink_test_fail_record* r) {
    r->cause = __blink_test_fail_cause;
    r->line = __blink_test_fail_line;
    r->col = __blink_test_fail_col;
    memcpy(r->msg, __blink_test_fail_msg, sizeof(r->msg));
    memcpy(r->expected, __blink_test_fail_expected, sizeof(r->expected));
    memcpy(r->actual, __blink_test_fail_actual, sizeof(r->actual));
    memcpy(r->assertion, __blink_test_fail_assertion, sizeof(r->assertion));
    memcpy(r->intro, __blink_test_fail_intro, sizeof(r->intro));
    memcpy(r->file, __blink_test_fail_file, sizeof(r->file));
    memcpy(r->user_msg, __blink_test_fail_user_msg, sizeof(r->user_msg));
    memcpy(r->error_type, __blink_test_fail_error_type, sizeof(r->error_type));
    memcpy(r->error_message, __blink_test_fail_error_message, sizeof(r->error_message));
    memcpy(r->case_label, __blink_test_case_label, sizeof(r->case_label));
}

BLINK_UNUSED static void __blink_test_fail_record_restore(const blink_test_fail_record* r) {
    __blink_test_fail_cause = r->cause;
    __blink_test_fail_line = r->line;
    __blink_test_fail_col = r->col;
    memcpy(__blink_test_fail_msg, r->msg, sizeof(r->msg));
    memcpy(__blink_test_fail_expected, r->expected, sizeof(r->expected));
    memcpy(__blink_test_fail_actual, r->actual, sizeof(r->actual));
    memcpy(__blink_test_fail_assertion, r->assertion, sizeof(r->assertion));
    memcpy(__blink_test_fail_intro, r->intro, sizeof(r->intro));
    memcpy(__blink_test_fail_file, r->file, sizeof(r->file));
    memcpy(__blink_test_fail_user_msg, r->user_msg, sizeof(r->user_msg));
    memcpy(__blink_test_fail_error_type, r->error_type, sizeof(r->error_type));
    memcpy(__blink_test_fail_error_message, r->error_message, sizeof(r->error_message));
    memcpy(__blink_test_case_label, r->case_label, sizeof(r->case_label));
}

/* Run one for_each case in its own catch frame and record it (spec §8.10.2).
 * The frame is the one assert_panics opens, so `with` cleanups push while the
 * case runs and a panic drains them to the case's mark. A second frame on
 * __blink_test_jmp catches assertion failures, which unwind there and never
 * reach panic dispatch. A non-empty `duplicate` is the message of a repeated
 * label: the case panics with it before its body runs. The test takes the
 * failure record of its most severe case, panicked over failed, and the first
 * such case when two tie; it keeps its own skip state, and the runner decides
 * whether every case skipped. Outside a test run there is no
 * test to record into, so the case runs as plain code and a failure ends the
 * program. */
BLINK_RT_FN void blink_test_run_case(const char* label, const char* duplicate, blink_closure* body) {
    if (__blink_panic_test_hook == NULL) {
        if (duplicate && duplicate[0]) { __blink_panic_dispatch(duplicate); }
        ((void (*)(const blink_closure*))body->fn_ptr)(body);
        return;
    }
    int prev_failed = __blink_test_failed;
    int prev_skipped = __blink_test_skipped;
    blink_test_fail_record prev_record;
    __blink_test_fail_record_save(&prev_record);
    char prev_reason[sizeof(__blink_test_skip_reason)];
    memcpy(prev_reason, __blink_test_skip_reason, sizeof(prev_reason));
    jmp_buf prev_jmp;
    memcpy(prev_jmp, __blink_test_jmp, sizeof(jmp_buf));
    size_t prev_jmp_mark = __blink_test_jmp_mark;
    int prev_armed = __blink_panic_armed;
    size_t prev_top = __blink_panic_cleanup_top;

    __blink_panic_frame frame;
    __blink_panic_frame_enter(&frame);
    __blink_test_jmp_mark = __blink_panic_cleanup_top;
    __blink_test_failed = 0;
    __blink_test_skipped = 0;
    /* A case after a panicked one must not read that panic's cause as its own. */
    __blink_test_fail_cause = BLINK_TEST_CAUSE_ASSERTION;
    BLINK_COPY_OR_EMPTY(__blink_test_case_label, label);
    int status;
    if (setjmp(__blink_panic_jmp) != 0) {
        __blink_test_note_panic(__blink_panic_msg);
        status = __blink_test_is_panicked() ? BLINK_TEST_CASE_PANICKED : BLINK_TEST_CASE_FAILED;
    } else if (setjmp(__blink_test_jmp) != 0) {
        status = __blink_test_is_panicked() ? BLINK_TEST_CASE_PANICKED : BLINK_TEST_CASE_FAILED;
    } else {
        if (duplicate && duplicate[0]) { __blink_panic_dispatch(duplicate); }
        ((void (*)(const blink_closure*))body->fn_ptr)(body);
        status = __blink_test_is_panicked() ? BLINK_TEST_CASE_PANICKED
               : __blink_test_failed ? BLINK_TEST_CASE_FAILED
               : __blink_test_skipped ? BLINK_TEST_CASE_SKIPPED
               : BLINK_TEST_CASE_PASSED;
    }

    /* An assertion that fails inside a nested assert_panics unwinds past that
     * frame's leave, so the catch state is put back by value, not by count. */
    __blink_panic_frame_leave(&frame);
    __blink_panic_armed = prev_armed;
    __blink_panic_cleanup_top = prev_top;
    memcpy(__blink_test_jmp, prev_jmp, sizeof(jmp_buf));
    __blink_test_jmp_mark = prev_jmp_mark;

    /* Severity: panicked 2, failed 1, otherwise 0 (spec §8.10.2). */
    int case_severity = status == BLINK_TEST_CASE_PANICKED ? 2 : status == BLINK_TEST_CASE_FAILED ? 1 : 0;
    int prev_severity = !prev_failed ? 0 : __blink_test_cause_is_panic(prev_record.cause) ? 2 : 1;
    const char* panic_message = status == BLINK_TEST_CASE_PANICKED ? __blink_test_fail_msg : NULL;
    blink_record_case(label, status, panic_message);
    if (case_severity > prev_severity) {
        __blink_test_failed = 1;
    } else {
        __blink_test_failed = prev_failed;
        __blink_test_fail_record_restore(&prev_record);
    }
    __blink_test_skipped = prev_skipped;
    if (status != BLINK_TEST_CASE_SKIPPED || prev_reason[0]) {
        memcpy(__blink_test_skip_reason, prev_reason, sizeof(prev_reason));
    }
}

/* JSON-escape a string into a static buffer. Each call overwrites the previous
 * result, so callers must consume the output before invoking again. */
BLINK_UNUSED static char __blink_test_json_buf[2048];
BLINK_UNUSED static const char* __blink_test_json_escape(const char* s) {
    if (!s) { __blink_test_json_buf[0] = '\0'; return __blink_test_json_buf; }
    size_t o = 0; size_t cap = sizeof(__blink_test_json_buf) - 1;
    for (size_t i = 0; s[i] && o + 6 < cap; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == '"' || c == '\\') {
            __blink_test_json_buf[o++] = '\\';
            __blink_test_json_buf[o++] = (char)c;
        } else if (c == '\n') {
            __blink_test_json_buf[o++] = '\\'; __blink_test_json_buf[o++] = 'n';
        } else if (c == '\r') {
            __blink_test_json_buf[o++] = '\\'; __blink_test_json_buf[o++] = 'r';
        } else if (c == '\t') {
            __blink_test_json_buf[o++] = '\\'; __blink_test_json_buf[o++] = 't';
        } else if (c < 0x20) {
            o += (size_t)snprintf(__blink_test_json_buf + o, cap - o, "\\u%04x", c);
        } else {
            __blink_test_json_buf[o++] = (char)c;
        }
    }
    __blink_test_json_buf[o] = '\0';
    return __blink_test_json_buf;
}

BLINK_UNUSED static int __blink_test_has_tag(const blink_test_entry* test, const char* tag) {
    for (int t = 0; t < test->tag_count; t++) {
        if (strcmp(test->tags[t], tag) == 0) return 1;
    }
    return 0;
}

BLINK_UNUSED static void __blink_test_print_tags_json(const blink_test_entry* test) {
    printf(",\"tags\":[");
    for (int t = 0; t < test->tag_count; t++) {
        if (t > 0) printf(",");
        printf("\"%s\"", test->tags[t]);
    }
    printf("]");
}

/* E0824: emit the secondary cleanup-panic warnings captured during
 * this test's armed unwind as a `cleanup_warnings[]` array. Additive — a
 * cleanup panic does not by itself change pass/fail (the original panic already
 * set the status), so this rides whatever record branch is active. Buffered
 * messages past the cap were dropped at capture time; the count still reflects
 * the true total, so emit a synthetic overflow marker for the lost remainder. */
BLINK_UNUSED static void __blink_test_print_cleanup_warnings_json(void) {
    if (__blink_cleanup_warning_count <= 0) { return; }
    int n = __blink_cleanup_warning_count;
    int shown = n < BLINK_CLEANUP_WARN_MAX ? n : BLINK_CLEANUP_WARN_MAX;
    printf(",\"cleanup_warnings\":[");
    for (int w = 0; w < shown; w++) {
        if (w > 0) printf(",");
        printf("{\"code\":\"E0824\",\"message\":\"%s\"}",
               __blink_test_json_escape(__blink_cleanup_warnings[w]));
    }
    if (n > BLINK_CLEANUP_WARN_MAX) {
        printf(",{\"code\":\"E0824\",\"message\":\"... %d more cleanup panic(s) dropped (buffer cap %d)\"}",
               n - BLINK_CLEANUP_WARN_MAX, BLINK_CLEANUP_WARN_MAX);
    }
    printf("]");
}

/* Human-readable counterpart: one `warning: E0824 ...` line per captured
 * cleanup panic, printed under the test's result line. */
BLINK_UNUSED static void __blink_test_print_cleanup_warnings_human(void) {
    if (__blink_cleanup_warning_count <= 0) { return; }
    int n = __blink_cleanup_warning_count;
    int shown = n < BLINK_CLEANUP_WARN_MAX ? n : BLINK_CLEANUP_WARN_MAX;
    for (int w = 0; w < shown; w++) {
        fprintf(stderr, "  warning: E0824 cleanup panicked during unwind: %s\n",
                __blink_cleanup_warnings[w]);
    }
    if (n > BLINK_CLEANUP_WARN_MAX) {
        fprintf(stderr, "  warning: E0824 ... %d more cleanup panic(s) dropped (buffer cap %d)\n",
                n - BLINK_CLEANUP_WARN_MAX, BLINK_CLEANUP_WARN_MAX);
    }
}

/* Emit the accumulated for_each case records as a `cases[]` array.
 * Comma-prefixed per the field convention so it rides whatever record branch is
 * active. Early-return when no cases ran (plain tests emit no field). Each entry
 * escapes exactly one string per printf — the shared __blink_test_json_escape
 * buffer is overwritten on every call. */
BLINK_UNUSED static void __blink_test_print_case_records_json(void) {
    if (__blink_test_case_record_count <= 0) { return; }
    printf(",\"cases\":[");
    for (int w = 0; w < __blink_test_case_record_count; w++) {
        const blink_test_case_record* r = &__blink_test_case_records[w];
        if (w > 0) printf(",");
        const char* st = r->status == BLINK_TEST_CASE_FAILED ? "failed"
                       : r->status == BLINK_TEST_CASE_SKIPPED ? "skipped"
                       : r->status == BLINK_TEST_CASE_PANICKED ? "panicked"
                       : "passed";
        printf("{\"label\":\"%s\"", __blink_test_json_escape(r->label));
        printf(",\"status\":\"%s\"", st);
        if (r->message) printf(",\"message\":\"%s\"", __blink_test_json_escape(r->message));
        printf("}");
    }
    printf("]");
}

BLINK_RT_FN void blink_test_run(const blink_test_entry* tests, int count, int argc, const char** argv) {
    const char* filter = NULL;
    const char* tags_filter = NULL;
    int json_output = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--test-filter") == 0 && i + 1 < argc) {
            filter = argv[++i];
        } else if (strcmp(argv[i], "--test-tags") == 0 && i + 1 < argc) {
            tags_filter = argv[++i];
        } else if (strcmp(argv[i], "--test-json") == 0) {
            json_output = 1;
        }
    }

    /* Line-buffer stdout so each per-test line flushes on its trailing
     * newline and survives a later C-level crash (SIGSEGV / _exit / forwarded
     * SIGTERM) that bypasses the atexit flush. Must precede every printf here. */
    setvbuf(stdout, NULL, _IOLBF, 0);

    __blink_panic_test_hook = __blink_test_panic_handler;
    if (__blink_test_case_records == NULL) {
        __blink_test_case_records = (blink_test_case_record*)calloc(BLINK_TEST_CASE_INITIAL, sizeof(blink_test_case_record));
        if (__blink_test_case_records == NULL) { fprintf(stderr, "blink: out of memory\n"); exit(1); }
    }

    int pass = 0, fail = 0, panicked = 0, skip = 0, total = 0;
    double total_ms = 0.0;

    if (json_output) printf("{\"results\":[");

    for (int i = 0; i < count; i++) {
        if (filter && !strstr(tests[i].name, filter)) continue;
        if (tags_filter && !__blink_test_has_tag(&tests[i], tags_filter)) continue;
        if (tests[i].skip) { skip++; total++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"skipped\"", tests[i].name);
                printf(",\"duration_ms\":%g", 0.0);
                __blink_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[33mskipped\033[0m\n", tests[i].name);
            }
            continue;
        }
        total++;
        __blink_test_failed = 0;
        __blink_test_fail_msg[0] = '\0';
        __blink_test_fail_line = 0;
        __blink_test_fail_assertion[0] = '\0';
        __blink_test_fail_intro[0] = '\0';
        __blink_test_fail_file[0] = '\0';
        __blink_test_fail_col = 0;
        __blink_test_fail_user_msg[0] = '\0';
        __blink_test_fail_expected[0] = '\0';
        __blink_test_fail_actual[0] = '\0';
        __blink_test_case_label[0] = '\0';
        __blink_test_jmp_mark = 0;
        __blink_test_case_records_reset();
        __blink_test_fail_cause = BLINK_TEST_CAUSE_ASSERTION;
        __blink_test_fail_error_type[0] = '\0';
        __blink_test_fail_error_message[0] = '\0';
        __blink_test_skipped = 0;
        __blink_test_skip_reason[0] = '\0';
        /* Reset of the assert_panics catch state (spec §2.20): an E0832 message
         * mismatch fails the test from inside its frame and unwinds straight to
         * the per-test frame, skipping the frame's leave, so the armed count and
         * cleanup mark it set are cleared here before the next test runs. */
        __blink_panic_armed = 0;
        __blink_panic_cleanup_top = 0;
        __blink_panic_cleanup_mark = 0;
        /* Reset the E0824 cleanup-panic capture per test: secondary
         * warnings ride a single record and must not leak into the next. */
        __blink_in_cleanup_drain = 0;
        __blink_cleanup_warning_count = 0;
        struct timespec __t0, __t1;
        clock_gettime(CLOCK_MONOTONIC, &__t0);
        if (setjmp(__blink_test_jmp) == 0) {
            tests[i].fn();
        }
        /* A test whose for_each cases all skipped, and that did not fail
         * itself, is skipped with the reason of the first case that skipped. */
        if (!__blink_test_failed && __blink_test_case_record_count > 0
            && __blink_test_case_skip_count == __blink_test_case_record_count) {
            __blink_test_skipped = 1;
        }
        clock_gettime(CLOCK_MONOTONIC, &__t1);
        double dur_ms = (double)(__t1.tv_sec - __t0.tv_sec) * 1000.0
                      + (double)(__t1.tv_nsec - __t0.tv_nsec) / 1000000.0;
        total_ms += dur_ms;
        /* test.failing (§8.10.6): invert observed outcome exactly once
         * for xfail tests. An unexpected pass is synthesized as an assertion
         * failure so it still counts against the suite. */
        int __blink_test_observed_failed = __blink_test_failed;
        if (tests[i].expected_fail && !__blink_test_skipped) {
            if (!__blink_test_observed_failed) {
                __blink_test_failed = 1;
                __blink_test_fail_cause = BLINK_TEST_CAUSE_ASSERTION;
                __blink_test_fail_msg[0] = '\0';
                __blink_test_fail_assertion[0] = '\0';
                __blink_test_fail_expected[0] = '\0';
                __blink_test_fail_actual[0] = '\0';
                __blink_test_fail_intro[0] = '\0';
                __blink_test_fail_user_msg[0] = '\0';
                snprintf(__blink_test_fail_assertion, sizeof(__blink_test_fail_assertion),
                         "expected failure, got pass");
            } else {
                __blink_test_failed = 0;
            }
        }
        if (__blink_test_skipped) {
            skip++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"skipped\"", tests[i].name);
                if (__blink_test_skip_reason[0]) {
                    printf(",\"reason\":\"%s\"", __blink_test_json_escape(__blink_test_skip_reason));
                }
                printf(",\"duration_ms\":%g", dur_ms);
                __blink_test_print_tags_json(&tests[i]);
                __blink_test_print_cleanup_warnings_json();
                __blink_test_print_case_records_json();
                printf("}");
            } else {
                if (__blink_test_skip_reason[0]) {
                    printf("test %s ... \033[33mskipped\033[0m (%s)\n", tests[i].name, __blink_test_skip_reason);
                } else {
                    printf("test %s ... \033[33mskipped\033[0m\n", tests[i].name);
                }
                __blink_test_print_cleanup_warnings_human();
            }
            continue;
        }
        if (__blink_test_is_panicked()) {
            panicked++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"panicked\"", tests[i].name);
                if (__blink_test_case_label[0]) {
                    printf(",\"case\":\"%s\"", __blink_test_json_escape(__blink_test_case_label));
                }
                printf(",\"message\":\"%s\"", __blink_test_json_escape(__blink_test_fail_msg));
                printf(",\"duration_ms\":%g", dur_ms);
                __blink_test_print_tags_json(&tests[i]);
                __blink_test_print_cleanup_warnings_json();
                __blink_test_print_case_records_json();
                printf("}");
            } else {
                if (__blink_test_case_label[0]) {
                    printf("test %s::case[%s] ... \033[31mPANIC\033[0m\n", tests[i].name, __blink_test_case_label);
                } else {
                    printf("test %s ... \033[31mPANIC\033[0m\n", tests[i].name);
                }
                fprintf(stderr, "  %s\n", __blink_test_fail_msg);
                __blink_test_print_cleanup_warnings_human();
            }
        } else if (__blink_test_failed) {
            fail++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"failed\",\"line\":%d",
                       tests[i].name, __blink_test_fail_line);
                printf(",\"cause\":\"%s\"", __blink_test_fail_cause);
                if (__blink_test_case_label[0]) {
                    printf(",\"case\":\"%s\"", __blink_test_json_escape(__blink_test_case_label));
                }
                printf(",\"message\":\"%s\"", __blink_test_json_escape(__blink_test_fail_msg));
                if (__blink_test_fail_assertion[0]) {
                    printf(",\"assertion\":\"%s\"", __blink_test_json_escape(__blink_test_fail_assertion));
                }
                if (__blink_test_fail_expected[0]) {
                    printf(",\"expected\":\"%s\"", __blink_test_json_escape(__blink_test_fail_expected));
                }
                if (__blink_test_fail_actual[0]) {
                    printf(",\"actual\":\"%s\"", __blink_test_json_escape(__blink_test_fail_actual));
                }
                if (__blink_test_fail_intro[0]) {
                    printf(",\"introspection\":\"%s\"", __blink_test_json_escape(__blink_test_fail_intro));
                }
                if (__blink_test_fail_user_msg[0]) {
                    printf(",\"user_message\":\"%s\"", __blink_test_json_escape(__blink_test_fail_user_msg));
                }
                if (__blink_test_fail_error_type[0] || __blink_test_fail_error_message[0]) {
                    printf(",\"error\":{\"message\":\"%s\"",
                           __blink_test_json_escape(__blink_test_fail_error_message));
                    printf(",\"error_type\":\"%s\"}",
                           __blink_test_json_escape(__blink_test_fail_error_type));
                }
                if (__blink_test_fail_file[0]) {
                    printf(",\"span\":{\"file\":\"%s\",\"line\":%d,\"col\":%d}",
                           __blink_test_json_escape(__blink_test_fail_file),
                           __blink_test_fail_line, __blink_test_fail_col);
                }
                printf(",\"duration_ms\":%g", dur_ms);
                __blink_test_print_tags_json(&tests[i]);
                __blink_test_print_cleanup_warnings_json();
                __blink_test_print_case_records_json();
                if (tests[i].expected_fail) {
                    printf(",\"expected_fail\":true");
                    if (tests[i].xfail_reason) {
                        printf(",\"xfail_reason\":\"%s\"", __blink_test_json_escape(tests[i].xfail_reason));
                    }
                }
                printf("}");
            } else {
                if (__blink_test_case_label[0]) {
                    printf("test %s::case[%s] ... \033[31mFAIL\033[0m\n", tests[i].name, __blink_test_case_label);
                } else {
                    printf("test %s ... \033[31mFAIL\033[0m\n", tests[i].name);
                }
                if (__blink_test_fail_assertion[0]) {
                    fprintf(stderr, "  assertion failed: %s\n", __blink_test_fail_assertion);
                    if (__blink_test_fail_user_msg[0]) {
                        fprintf(stderr, "    message: %s\n", __blink_test_fail_user_msg);
                    }
                    if (__blink_test_fail_intro[0]) {
                        fprintf(stderr, "%s\n", __blink_test_fail_intro);
                    }
                    if (__blink_test_fail_file[0]) {
                        fprintf(stderr, "  --> %s:%d:%d\n",
                                __blink_test_fail_file,
                                __blink_test_fail_line,
                                __blink_test_fail_col);
                    } else {
                        fprintf(stderr, "  (line %d)\n", __blink_test_fail_line);
                    }
                } else if (__blink_test_fail_msg[0]) {
                    if (__blink_test_fail_line) {
                        fprintf(stderr, "  %s (line %d)\n", __blink_test_fail_msg, __blink_test_fail_line);
                    } else {
                        fprintf(stderr, "  %s\n", __blink_test_fail_msg);
                    }
                }
                __blink_test_print_cleanup_warnings_human();
            }
        } else {
            pass++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"passed\"", tests[i].name);
                printf(",\"duration_ms\":%g", dur_ms);
                __blink_test_print_tags_json(&tests[i]);
                __blink_test_print_cleanup_warnings_json();
                __blink_test_print_case_records_json();
                if (tests[i].expected_fail) {
                    printf(",\"expected_fail\":true");
                    if (tests[i].xfail_reason) {
                        printf(",\"xfail_reason\":\"%s\"", __blink_test_json_escape(tests[i].xfail_reason));
                    }
                }
                printf("}");
            } else {
                printf("test %s ... \033[32mok\033[0m\n", tests[i].name);
                __blink_test_print_cleanup_warnings_human();
            }
        }
    }

    if (json_output) {
        printf("],\"summary\":{\"total\":%d,\"passed\":%d,\"failed\":%d,\"panicked\":%d,\"skipped\":%d,\"duration_ms\":%g}}\n",
               total, pass, fail, panicked, skip, total_ms);
    } else {
        printf("\n%d passed, %d failed", pass, fail);
        if (panicked > 0) printf(", %d panicked", panicked);
        if (skip > 0) printf(", %d skipped", skip);
        printf(" (of %d)\n", total);
    }
    if (fail + panicked > 0) exit(1);
}

#endif /* BLINK_RUNTIME_TEST_BODIES */

#endif
