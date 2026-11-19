/* A --debug len() that finds a wrong recorded codepoint count is a runtime fault with no
   Blink site: __blink_fatal, exit 101. No assert_panics frame and no panic hook may take it.
   No Blink program can build such a Str without a foreign write to its bytes, and a Str
   never crosses to C, so this test builds the Str in C.

   With no argument it runs itself once per case and checks each exit code and output. With a
   case name it runs that case:
     wrong-catch, wrong-hook   6 codepoints recorded, 5 held: the full walk finds it.
     low-catch, low-hook       0 recorded in 5000 ASCII bytes, past the walk limit.
     right-catch               the right count returns it.
     panic-catch, panic-hook   a panic, which the same frame or hook takes, so the two
                               fatal rows do not pass because the catch was never armed.
   A -catch case runs in an armed assert_panics frame, a -hook case with a panic hook. */

#include "runtime.h"
#include <sys/wait.h>
#include <unistd.h>

static void hook(const char* msg) {
    (void)msg;
    fprintf(stderr, "the hook ran\n");
    exit(70);
}

static char* wrong_count(void) {
    char* s = blink_str_alloc(6);
    memcpy(s, "abcdef", 6);
    blink_str_set_cps(s, 6);
    s[0] = (char)0x80;
    return s;
}

static char* low_count(void) {
    char* s = blink_str_alloc(5000);
    blink_str_set_cps(s, 0);
    memset(s, 'a', 5000);
    return s;
}

static char* right_count(void) {
    char* s = blink_str_alloc(7);
    memcpy(s, "h\xc3\xa9llo!", 7);
    blink_str_set_cps(s, 6);
    return s;
}

static void run(const char* what) {
    if (strncmp(what, "wrong", 5) == 0) {
        printf("%lld\n", (long long)blink_str_cp_len(wrong_count()));
    } else if (strncmp(what, "low", 3) == 0) {
        printf("%lld\n", (long long)blink_str_cp_len(low_count()));
    } else if (strncmp(what, "right", 5) == 0) {
        printf("%lld\n", (long long)blink_str_cp_len(right_count()));
    } else if (strncmp(what, "panic", 5) == 0) {
        __blink_panic_dispatch("a Blink panic");
    } else {
        fprintf(stderr, "unknown case %s\n", what);
        exit(2);
    }
}

/* Runs `self case`, and returns its exit code with its stdout and stderr in `out`. */
static int run_case(const char* self, const char* c, char* out, size_t cap) {
    int fds[2];
    if (pipe(fds) != 0) { perror("pipe"); exit(2); }
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); exit(2); }
    if (pid == 0) {
        dup2(fds[1], 1);
        dup2(fds[1], 2);
        close(fds[0]);
        close(fds[1]);
        execl(self, self, c, (char*)NULL);
        _exit(127);
    }
    close(fds[1]);
    size_t got = 0;
    ssize_t r;
    while (got + 1 < cap && (r = read(fds[0], out + got, cap - 1 - got)) > 0) got += (size_t)r;
    out[got] = '\0';
    close(fds[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

static int expect(const char* self, const char* c, int want_rc, const char* want_out) {
    char out[4096];
    int rc = run_case(self, c, out, sizeof out);
    if (rc != want_rc || strstr(out, want_out) == NULL) {
        fprintf(stderr, "FAIL %s: want exit %d with \"%s\", got exit %d:\n%s\n", c, want_rc, want_out, rc, out);
        return 1;
    }
    printf("PASS %s\n", c);
    return 0;
}

static int run_all(const char* self) {
    const char* wrong = "blink: internal error: a Str records 6 codepoints but holds 5";
    const char* low = "blink: internal error: a Str records 0 codepoints in 5000 bytes";
    int bad = 0;
    bad += expect(self, "wrong-catch", 101, wrong);
    bad += expect(self, "wrong-hook", 101, wrong);
    bad += expect(self, "low-catch", 101, low);
    bad += expect(self, "low-hook", 101, low);
    bad += expect(self, "right-catch", 0, "6\nreturned");
    bad += expect(self, "panic-catch", 0, "the catch took: a Blink panic");
    bad += expect(self, "panic-hook", 70, "the hook ran");
    return bad == 0 ? 0 : 1;
}

int main(int argc, char** argv) {
    if (argc == 1) return run_all(argv[0]);
    if (argc != 2) {
        fprintf(stderr, "usage: %s [case]\n", argv[0]);
        return 2;
    }
    const char* c = argv[1];
    size_t n = strlen(c);
    if (n > 5 && strcmp(c + n - 5, "-hook") == 0) {
        __blink_panic_test_hook = hook;
        run(c);
        printf("returned\n");
        return 0;
    }
    if (n > 6 && strcmp(c + n - 6, "-catch") == 0) {
        __blink_panic_frame f;
        __blink_panic_frame_enter(&f);
        if (setjmp(__blink_panic_jmp) != 0) {
            fprintf(stderr, "the catch took: %s\n", __blink_panic_msg);
            __blink_panic_frame_leave(&f);
            return 0;
        }
        run(c);
        __blink_panic_frame_leave(&f);
        printf("returned\n");
        return 0;
    }
    fprintf(stderr, "unknown case %s\n", c);
    return 2;
}
