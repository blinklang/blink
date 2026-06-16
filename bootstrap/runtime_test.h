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
} blink_test_entry;

BLINK_UNUSED static jmp_buf __blink_test_jmp;
/* __blink_test_failed and __blink_test_skipped must be shared across TUs
 * because for_each (monomorphized into the stdlib monolith TU) polls them
 * via the @ffi accessors below — the runner that writes them lives in the
 * user TU. Other __blink_test_* state stays per-TU since only the user TU
 * touches it. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    int __blink_test_failed = 0;
  #else
    extern int __blink_test_failed;
  #endif
#else
BLINK_UNUSED static int __blink_test_failed;
#endif
BLINK_UNUSED static char __blink_test_fail_msg[512];
BLINK_UNUSED static int __blink_test_fail_line;
/* assert_eq separate expected/actual rendering (spec §8.10): expected = the
 * RHS argument, actual = the LHS argument. Non-empty only when the failure
 * came through __blink_assert_fail_eq; plain assert(...) leaves them empty. */
BLINK_UNUSED static char __blink_test_fail_expected[256];
BLINK_UNUSED static char __blink_test_fail_actual[256];
/* Power-assert introspection. When non-empty, these supplement the legacy
 * fail_msg with structured assertion text, sub-expression values, and a
 * span. The runner uses them for human and JSON output. */
BLINK_UNUSED static char __blink_test_fail_assertion[256];
#define BLINK_PA_INTRO_BUF_SIZE 1024
BLINK_UNUSED static char __blink_test_fail_intro[BLINK_PA_INTRO_BUF_SIZE];
BLINK_UNUSED static char __blink_test_fail_file[256];
BLINK_UNUSED static int __blink_test_fail_col;
BLINK_UNUSED static char __blink_test_fail_user_msg[256];
/* Cause discriminator for NDJSON output. Default "assertion"; set to
 * "propagated_error" by __blink_test_set_propagate for spec §2.20
 * test-body `?` propagation. Reset at the start of each test iteration. */
BLINK_UNUSED static const char* __blink_test_fail_cause = "assertion";
BLINK_UNUSED static char __blink_test_fail_error_type[128];
BLINK_UNUSED static char __blink_test_fail_error_message[512];
/* Active for_each case label. Set by std.testing.for_each before invoking
 * each case body; cleared after a case returns successfully. On unwind via
 * __blink_assert_fail*, the buffer retains the failing case label so the
 * runner can emit it in the JSON "case" field. */
BLINK_UNUSED static char __blink_test_case_label[256];

/* Skip state. Propagated via Result-sentinel (set globals + plain `return`)
 * so __attribute__((cleanup)) destructors fire for in-scope `with` blocks.
 * `__blink_test_skipped` is shared across TUs (see comment on
 * `__blink_test_failed` above). The reason is user-TU-only. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    int __blink_test_skipped = 0;
  #else
    extern int __blink_test_skipped;
  #endif
#else
BLINK_UNUSED static int __blink_test_skipped;
#endif
BLINK_UNUSED static char __blink_test_skip_reason[256];

BLINK_UNUSED static void __blink_assert_fail(const char* msg, int line) {
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
    longjmp(__blink_test_jmp, 1);
}

#define BLINK_COPY_OR_EMPTY(dst, src) do { \
    if (src) { \
        strncpy((dst), (src), sizeof(dst) - 1); \
        (dst)[sizeof(dst) - 1] = '\0'; \
    } else { \
        (dst)[0] = '\0'; \
    } \
} while (0)

BLINK_UNUSED static void blink_set_case_label(const char* s) {
    BLINK_COPY_OR_EMPTY(__blink_test_case_label, s);
}

/* assert_eq failure: like __blink_assert_fail but also records the separately
 * rendered expected (RHS) and actual (LHS) operands for spec §8.10 JSON. */
BLINK_UNUSED static void __blink_assert_fail_eq(const char* msg,
                                                const char* expected,
                                                const char* actual,
                                                int line) {
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
    longjmp(__blink_test_jmp, 1);
}

BLINK_UNUSED static void __blink_assert_fail_intro(const char* assertion,
                                                    const char* intro,
                                                    const char* file,
                                                    int line, int col,
                                                    const char* user_msg) {
    __blink_test_failed = 1;
    if (assertion && assertion[0]) {
        snprintf(__blink_test_fail_msg, sizeof(__blink_test_fail_msg),
                 "assertion failed: %s", assertion);
    } else {
        snprintf(__blink_test_fail_msg, sizeof(__blink_test_fail_msg),
                 "assertion failed");
    }
    __blink_test_fail_line = line;
    __blink_test_fail_col = col;
    BLINK_COPY_OR_EMPTY(__blink_test_fail_assertion, assertion);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_intro, intro);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_file, file);
    BLINK_COPY_OR_EMPTY(__blink_test_fail_user_msg, user_msg);
    __blink_test_fail_expected[0] = '\0';
    __blink_test_fail_actual[0] = '\0';
    longjmp(__blink_test_jmp, 1);
}

/* Spec §2.20: ?-in-test propagation. No longjmp — caller emits `return;`
 * so cleanup destructors run for in-scope `with` bindings. */
BLINK_UNUSED static void __blink_test_set_propagate(const char* message,
                                                    const char* error_type,
                                                    const char* file,
                                                    int line, int col) {
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

/* No longjmp — caller emits `return;` so cleanup destructors run. */
BLINK_UNUSED static void __blink_test_set_skipped(const char* reason) {
    __blink_test_skipped = 1;
    BLINK_COPY_OR_EMPTY(__blink_test_skip_reason, reason);
}

/* Spec §2.20 — assert_panics failures. Both reuse __blink_assert_fail_intro,
 * so they land in the existing __blink_test_fail_* record + JSON/human render
 * with zero new runner code, and longjmp to the per-test runner frame. */

/* E0831 — the block returned normally instead of panicking. */
BLINK_UNUSED static void __blink_assert_panics_returned(const char* file, int line, int col) {
    __blink_assert_fail_intro(
        "assert_panics: expected the block to panic, but it returned normally",
        "", file, line, col, "");
}

/* E0832 — the block panicked but the message lacked the matching substring.
 * Renders the expected substring + the FULL actual panic message + origin. */
BLINK_UNUSED static void __blink_assert_panics_mismatch(const char* expected,
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

/* Polled by std.testing.for_each between case-body iterations so that a
 * failing/skipped case stops the loop instead of running every remaining
 * case under a poisoned global state. int64_t signature matches Blink Int. */
BLINK_UNUSED static int64_t __blink_test_is_failed(void) { return (int64_t)__blink_test_failed; }
BLINK_UNUSED static int64_t __blink_test_is_skipped(void) { return (int64_t)__blink_test_skipped; }

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

BLINK_UNUSED static void blink_test_run(const blink_test_entry* tests, int count, int argc, const char** argv) {
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

    int pass = 0, fail = 0, skip = 0, total = 0;
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
        __blink_test_fail_cause = "assertion";
        __blink_test_fail_error_type[0] = '\0';
        __blink_test_fail_error_message[0] = '\0';
        __blink_test_skipped = 0;
        __blink_test_skip_reason[0] = '\0';
        /* Defensive reset of the assert_panics catch state (spec §2.20): a body
         * that exits via `return`/`break`/`continue` (rather than panicking or
         * falling through) bypasses the block's own armed-- / mark restore, so
         * re-zero here to bound the blast radius to a single test rather than
         * poisoning every subsequent test on this thread. */
        __blink_panic_armed = 0;
        __blink_panic_cleanup_top = 0;
        __blink_panic_cleanup_mark = 0;
        struct timespec __t0, __t1;
        clock_gettime(CLOCK_MONOTONIC, &__t0);
        if (setjmp(__blink_test_jmp) == 0) {
            tests[i].fn();
        }
        clock_gettime(CLOCK_MONOTONIC, &__t1);
        double dur_ms = (double)(__t1.tv_sec - __t0.tv_sec) * 1000.0
                      + (double)(__t1.tv_nsec - __t0.tv_nsec) / 1000000.0;
        total_ms += dur_ms;
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
                printf("}");
            } else {
                if (__blink_test_skip_reason[0]) {
                    printf("test %s ... \033[33mskipped\033[0m (%s)\n", tests[i].name, __blink_test_skip_reason);
                } else {
                    printf("test %s ... \033[33mskipped\033[0m\n", tests[i].name);
                }
            }
            continue;
        }
        if (__blink_test_failed) {
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
                printf("}");
            } else {
                if (__blink_test_case_label[0]) {
                    printf("test %s (case \"%s\") ... \033[31mFAIL\033[0m\n", tests[i].name, __blink_test_case_label);
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
                    fprintf(stderr, "  %s (line %d)\n", __blink_test_fail_msg, __blink_test_fail_line);
                }
            }
        } else {
            pass++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"pass\"", tests[i].name);
                printf(",\"duration_ms\":%g", dur_ms);
                __blink_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[32mok\033[0m\n", tests[i].name);
            }
        }
    }

    if (json_output) {
        printf("],\"summary\":{\"total\":%d,\"passed\":%d,\"failed\":%d,\"skipped\":%d,\"duration_ms\":%g}}\n", total, pass, fail, skip, total_ms);
    } else {
        printf("\n%d passed, %d failed", pass, fail);
        if (skip > 0) printf(", %d skipped", skip);
        printf(" (of %d)\n", total);
    }
    if (fail > 0) exit(1);
}

#endif
