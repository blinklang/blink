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
} pact_test_entry;

BLINK_UNUSED static jmp_buf __pact_test_jmp;
BLINK_UNUSED static int __pact_test_failed;
BLINK_UNUSED static char __pact_test_fail_msg[512];
BLINK_UNUSED static int __pact_test_fail_line;

BLINK_UNUSED static void __pact_assert_fail(const char* msg, int line) {
    __pact_test_failed = 1;
    if (msg) {
        strncpy(__pact_test_fail_msg, msg, sizeof(__pact_test_fail_msg) - 1);
        __pact_test_fail_msg[sizeof(__pact_test_fail_msg) - 1] = '\0';
    } else {
        __pact_test_fail_msg[0] = '\0';
    }
    __pact_test_fail_line = line;
    longjmp(__pact_test_jmp, 1);
}

BLINK_UNUSED static int __pact_test_has_tag(const pact_test_entry* test, const char* tag) {
    for (int t = 0; t < test->tag_count; t++) {
        if (strcmp(test->tags[t], tag) == 0) return 1;
    }
    return 0;
}

BLINK_UNUSED static void __pact_test_print_tags_json(const pact_test_entry* test) {
    printf(",\"tags\":[");
    for (int t = 0; t < test->tag_count; t++) {
        if (t > 0) printf(",");
        printf("\"%s\"", test->tags[t]);
    }
    printf("]");
}

BLINK_UNUSED static void pact_test_run(const pact_test_entry* tests, int count, int argc, const char** argv) {
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
        if (tags_filter && !__pact_test_has_tag(&tests[i], tags_filter)) continue;
        if (tests[i].skip) { skip++; total++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"skipped\"", tests[i].name);
                __pact_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[33mskipped\033[0m\n", tests[i].name);
            }
            continue;
        }
        total++;
        __pact_test_failed = 0;
        __pact_test_fail_msg[0] = '\0';
        __pact_test_fail_line = 0;
        if (setjmp(__pact_test_jmp) == 0) {
            tests[i].fn();
        }
        if (__pact_test_failed) {
            fail++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"fail\",\"line\":%d,\"message\":\"%s\"",
                       tests[i].name, __pact_test_fail_line, __pact_test_fail_msg);
                __pact_test_print_tags_json(&tests[i]);
                printf("}");
            } else {
                printf("test %s ... \033[31mFAIL\033[0m\n", tests[i].name);
                if (__pact_test_fail_msg[0]) {
                    fprintf(stderr, "  %s (line %d)\n", __pact_test_fail_msg, __pact_test_fail_line);
                }
            }
        } else {
            pass++;
            if (json_output) {
                if (total > 1) printf(",");
                printf("{\"name\":\"%s\",\"status\":\"pass\"", tests[i].name);
                __pact_test_print_tags_json(&tests[i]);
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
