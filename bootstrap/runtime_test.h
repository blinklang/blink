#ifndef BLINK_RUNTIME_TEST_H
#define BLINK_RUNTIME_TEST_H

#include <setjmp.h>

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
BLINK_UNUSED static int __blink_test_failed;
BLINK_UNUSED static char __blink_test_fail_msg[512];
BLINK_UNUSED static int __blink_test_fail_line;
/* Power-assert introspection. When non-empty, these supplement the legacy
 * fail_msg with structured assertion text, sub-expression values, and a
 * span. The runner uses them for human and JSON output. */
BLINK_UNUSED static char __blink_test_fail_assertion[256];
#define BLINK_PA_INTRO_BUF_SIZE 1024
BLINK_UNUSED static char __blink_test_fail_intro[BLINK_PA_INTRO_BUF_SIZE];
BLINK_UNUSED static char __blink_test_fail_file[256];
BLINK_UNUSED static int __blink_test_fail_col;
BLINK_UNUSED static char __blink_test_fail_user_msg[256];
/* Active for_each case label. Set by std.testing.for_each before invoking
 * each case body; cleared after a case returns successfully. On unwind via
 * __blink_assert_fail*, the buffer retains the failing case label so the
 * runner can emit it in the JSON "case" field. */
BLINK_UNUSED static char __blink_test_case_label[256];

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
    longjmp(__blink_test_jmp, 1);
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

    if (json_output) printf("{\"tests\":[");

    for (int i = 0; i < count; i++) {
        if (filter && !strstr(tests[i].name, filter)) continue;
        if (tags_filter && !__blink_test_has_tag(&tests[i], tags_filter)) continue;
        if (tests[i].skip) { skip++; total++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"skipped\"", tests[i].name);
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
        __blink_test_case_label[0] = '\0';
        if (setjmp(__blink_test_jmp) == 0) {
            tests[i].fn();
        }
        if (__blink_test_failed) {
            fail++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"fail\",\"line\":%d",
                       tests[i].name, __blink_test_fail_line);
                if (__blink_test_case_label[0]) {
                    printf(",\"case\":\"%s\"", __blink_test_json_escape(__blink_test_case_label));
                }
                printf(",\"message\":\"%s\"", __blink_test_json_escape(__blink_test_fail_msg));
                if (__blink_test_fail_assertion[0]) {
                    printf(",\"assertion\":\"%s\"", __blink_test_json_escape(__blink_test_fail_assertion));
                }
                if (__blink_test_fail_intro[0]) {
                    printf(",\"introspection\":\"%s\"", __blink_test_json_escape(__blink_test_fail_intro));
                }
                if (__blink_test_fail_user_msg[0]) {
                    printf(",\"user_message\":\"%s\"", __blink_test_json_escape(__blink_test_fail_user_msg));
                }
                if (__blink_test_fail_file[0]) {
                    printf(",\"span\":{\"file\":\"%s\",\"line\":%d,\"col\":%d}",
                           __blink_test_json_escape(__blink_test_fail_file),
                           __blink_test_fail_line, __blink_test_fail_col);
                }
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
                __blink_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[32mok\033[0m\n", tests[i].name);
            }
        }
    }

    if (json_output) {
        printf("],\"summary\":{\"total\":%d,\"passed\":%d,\"failed\":%d,\"skipped\":%d}}\n", total, pass, fail, skip);
    } else {
        printf("\n%d passed, %d failed", pass, fail);
        if (skip > 0) printf(", %d skipped", skip);
        printf(" (of %d)\n", total);
    }
    if (fail > 0) exit(1);
}

#endif
