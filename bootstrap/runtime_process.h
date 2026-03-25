#ifndef BLINK_RUNTIME_PROCESS_H
#define BLINK_RUNTIME_PROCESS_H

#ifndef _WIN32
#include <sys/wait.h>
#include <signal.h>
#endif

typedef struct {
    const char* out;
    const char* err_out;
    int64_t exit_code;
} pact_ProcessResult;

static volatile pid_t pact_child_pid = 0;
static volatile sig_atomic_t pact_got_sigint = 0;

static void pact_sigint_handler(int sig) {
    (void)sig;
    pact_got_sigint = 1;
    pid_t p = pact_child_pid;
    if (p > 0) kill(p, SIGINT);
}

static char** pact_process_build_argv(const char* cmd, const pact_list* args) {
    int64_t argc = args ? args->len : 0;
    char** argv = (char**)pact_alloc(sizeof(char*) * (int64_t)(argc + 2));
    argv[0] = (char*)cmd;
    for (int64_t i = 0; i < argc; i++) {
        argv[i + 1] = (char*)args->items[i];
    }
    argv[argc + 1] = NULL;
    return argv;
}

static char* pact_read_fd_to_string(int fd) {
    int64_t cap = 4096, len = 0;
    char* buf = (char*)pact_alloc(cap);
    while (1) {
        if (len + 1024 > cap) { cap *= 2; buf = (char*)GC_REALLOC(buf, (size_t)cap); }
        ssize_t n = read(fd, buf + len, (size_t)(cap - len - 1));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        len += n;
    }
    buf[len] = '\0';
    close(fd);
    return buf;
}

BLINK_UNUSED static void pact_process_exec(const char* cmd, const pact_list* args) {
    char** argv = pact_process_build_argv(cmd, args);
    execvp(cmd, argv);
    perror("execvp");
    _exit(127);
}

// Note: writes all stdin before reading stdout/stderr. May deadlock if
// stdin + stdout together exceed pipe buffer (~64KB). Fine for small payloads.
BLINK_UNUSED static pact_ProcessResult pact_process_run_with_stdin(const char* cmd, const pact_list* args, const char* stdin_data) {
    pact_ProcessResult result = { "", "", -1 };
    int stdin_pipe[2] = {-1, -1}, stdout_pipe[2] = {-1, -1}, stderr_pipe[2] = {-1, -1};
    if (pipe(stdin_pipe) < 0 || pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
        if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
        result.err_out = pact_strdup("pipe() failed");
        return result;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(stdin_pipe[0]); close(stdin_pipe[1]);
        close(stdout_pipe[0]); close(stdout_pipe[1]);
        close(stderr_pipe[0]); close(stderr_pipe[1]);
        result.err_out = pact_strdup("fork() failed");
        return result;
    }
    if (pid == 0) {
        close(stdin_pipe[1]);
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        dup2(stdin_pipe[0], STDIN_FILENO);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdin_pipe[0]);
        close(stdout_pipe[1]);
        close(stderr_pipe[1]);
        char** argv = pact_process_build_argv(cmd, args);
        execvp(cmd, argv);
        _exit(127);
    }
    close(stdin_pipe[0]);
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);
    if (stdin_data) {
        struct sigaction sa_old, sa_new;
        memset(&sa_new, 0, sizeof(sa_new));
        sa_new.sa_handler = SIG_IGN;
        sigaction(SIGPIPE, &sa_new, &sa_old);
        size_t len = strlen(stdin_data);
        size_t written = 0;
        while (written < len) {
            ssize_t n = write(stdin_pipe[1], stdin_data + written, len - written);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) break;
            written += (size_t)n;
        }
        sigaction(SIGPIPE, &sa_old, NULL);
    }
    close(stdin_pipe[1]);
    result.out = pact_read_fd_to_string(stdout_pipe[0]);
    result.err_out = pact_read_fd_to_string(stderr_pipe[0]);
    pact_child_pid = pid;
    pact_got_sigint = 0;
    struct sigaction sa_int_old, sa_int_new;
    memset(&sa_int_new, 0, sizeof(sa_int_new));
    sa_int_new.sa_handler = pact_sigint_handler;
    sa_int_new.sa_flags = SA_RESTART;
    sigaction(SIGINT, &sa_int_new, &sa_int_old);
    int status;
    waitpid(pid, &status, 0);
    sigaction(SIGINT, &sa_int_old, NULL);
    pact_child_pid = 0;
    if (WIFEXITED(status)) {
        result.exit_code = (int64_t)WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.exit_code = 128 + (int64_t)WTERMSIG(status);
    } else {
        result.exit_code = -1;
    }
    if (pact_got_sigint) {
        raise(SIGINT);
    }
    return result;
}

BLINK_UNUSED static pact_ProcessResult pact_process_run(const char* cmd, const pact_list* args) {
    return pact_process_run_with_stdin(cmd, args, NULL);
}

#endif
