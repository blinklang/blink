#ifndef PACT_RUNTIME_PROCESS_H
#define PACT_RUNTIME_PROCESS_H

#ifndef _WIN32
#include <sys/wait.h>
#endif

typedef struct {
    const char* out;
    const char* err_out;
    int64_t exit_code;
} pact_ProcessResult;

PACT_UNUSED static void pact_process_exec(const char* cmd, const pact_list* args) {
    int64_t argc = args ? args->len : 0;
    char** argv = (char**)pact_alloc(sizeof(char*) * (int64_t)(argc + 2));
    argv[0] = (char*)cmd;
    for (int64_t i = 0; i < argc; i++) {
        argv[i + 1] = (char*)args->items[i];
    }
    argv[argc + 1] = NULL;
    execvp(cmd, argv);
    perror("execvp");
    _exit(127);
}

PACT_UNUSED static pact_ProcessResult pact_process_run(const char* cmd, const pact_list* args) {
    pact_ProcessResult result = { "", "", -1 };
    int stdout_pipe[2], stderr_pipe[2];
    if (pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        result.err_out = strdup("pipe() failed");
        return result;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(stdout_pipe[0]); close(stdout_pipe[1]);
        close(stderr_pipe[0]); close(stderr_pipe[1]);
        result.err_out = strdup("fork() failed");
        return result;
    }
    if (pid == 0) {
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[1]);
        close(stderr_pipe[1]);
        int64_t argc = args ? args->len : 0;
        char** argv = (char**)pact_alloc(sizeof(char*) * (int64_t)(argc + 2));
        argv[0] = (char*)cmd;
        for (int64_t i = 0; i < argc; i++) {
            argv[i + 1] = (char*)args->items[i];
        }
        argv[argc + 1] = NULL;
        execvp(cmd, argv);
        _exit(127);
    }
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);
    int64_t out_cap = 4096, out_len = 0;
    char* out_buf = (char*)pact_alloc(out_cap);
    while (1) {
        if (out_len + 1024 > out_cap) { out_cap *= 2; out_buf = (char*)realloc(out_buf, (size_t)out_cap); }
        ssize_t n = read(stdout_pipe[0], out_buf + out_len, (size_t)(out_cap - out_len - 1));
        if (n <= 0) break;
        out_len += n;
    }
    out_buf[out_len] = '\0';
    close(stdout_pipe[0]);
    int64_t err_cap = 4096, err_len = 0;
    char* err_buf = (char*)pact_alloc(err_cap);
    while (1) {
        if (err_len + 1024 > err_cap) { err_cap *= 2; err_buf = (char*)realloc(err_buf, (size_t)err_cap); }
        ssize_t n = read(stderr_pipe[0], err_buf + err_len, (size_t)(err_cap - err_len - 1));
        if (n <= 0) break;
        err_len += n;
    }
    err_buf[err_len] = '\0';
    close(stderr_pipe[0]);
    int status;
    waitpid(pid, &status, 0);
    result.out = out_buf;
    result.err_out = err_buf;
    if (WIFEXITED(status)) {
        result.exit_code = (int64_t)WEXITSTATUS(status);
    } else {
        result.exit_code = -1;
    }
    return result;
}

#endif
