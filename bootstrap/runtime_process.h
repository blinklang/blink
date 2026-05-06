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
} blink_ProcessResult;

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    volatile pid_t blink_child_pid = 0;
    volatile sig_atomic_t blink_got_sigint = 0;
  #else
    extern volatile pid_t blink_child_pid;
    extern volatile sig_atomic_t blink_got_sigint;
  #endif
#else
static volatile pid_t blink_child_pid = 0;
static volatile sig_atomic_t blink_got_sigint = 0;
#endif

static void blink_sigint_handler(int sig) {
    (void)sig;
    blink_got_sigint = 1;
    pid_t p = blink_child_pid;
    if (p > 0) kill(p, SIGINT);
}

static char** blink_process_build_argv(const char* cmd, const blink_list* args) {
    int64_t argc = args ? args->len : 0;
    char** argv = (char**)blink_alloc(sizeof(char*) * (int64_t)(argc + 2));
    argv[0] = (char*)cmd;
    for (int64_t i = 0; i < argc; i++) {
        argv[i + 1] = (char*)args->items[i];
    }
    argv[argc + 1] = NULL;
    return argv;
}

static char* blink_read_fd_to_string(int fd) {
    int64_t cap = 4096, len = 0;
    char* buf = (char*)blink_alloc(cap);
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

BLINK_RT_FN void blink_process_exec(const char* cmd, const blink_list* args);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_process_exec(const char* cmd, const blink_list* args) {
    char** argv = blink_process_build_argv(cmd, args);
    execvp(cmd, argv);
    perror("execvp");
    _exit(127);
}
#endif

// Note: writes all stdin before reading stdout/stderr. May deadlock if
// stdin + stdout together exceed pipe buffer (~64KB). Fine for small payloads.
BLINK_RT_FN blink_ProcessResult blink_process_run_with_stdin(const char* cmd, const blink_list* args, const char* stdin_data);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_ProcessResult blink_process_run_with_stdin(const char* cmd, const blink_list* args, const char* stdin_data) {
    blink_ProcessResult result = { "", "", -1 };
    int stdin_pipe[2] = {-1, -1}, stdout_pipe[2] = {-1, -1}, stderr_pipe[2] = {-1, -1};
    if (pipe(stdin_pipe) < 0 || pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
        if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
        result.err_out = blink_strdup("pipe() failed");
        return result;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(stdin_pipe[0]); close(stdin_pipe[1]);
        close(stdout_pipe[0]); close(stdout_pipe[1]);
        close(stderr_pipe[0]); close(stderr_pipe[1]);
        result.err_out = blink_strdup("fork() failed");
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
        char** argv = blink_process_build_argv(cmd, args);
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
    result.out = blink_read_fd_to_string(stdout_pipe[0]);
    result.err_out = blink_read_fd_to_string(stderr_pipe[0]);
    blink_child_pid = pid;
    blink_got_sigint = 0;
    struct sigaction sa_int_old, sa_int_new;
    memset(&sa_int_new, 0, sizeof(sa_int_new));
    sa_int_new.sa_handler = blink_sigint_handler;
    sa_int_new.sa_flags = SA_RESTART;
    sigaction(SIGINT, &sa_int_new, &sa_int_old);
    int status;
    waitpid(pid, &status, 0);
    sigaction(SIGINT, &sa_int_old, NULL);
    blink_child_pid = 0;
    if (WIFEXITED(status)) {
        result.exit_code = (int64_t)WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result.exit_code = 128 + (int64_t)WTERMSIG(status);
    } else {
        result.exit_code = -1;
    }
    if (blink_got_sigint) {
        raise(SIGINT);
    }
    return result;
}
#endif

BLINK_RT_FN blink_ProcessResult blink_process_run(const char* cmd, const blink_list* args);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_ProcessResult blink_process_run(const char* cmd, const blink_list* args) {
    return blink_process_run_with_stdin(cmd, args, NULL);
}
#endif

/* ── Non-blocking spawn + pid handles ─────────────────────────────────
 * Used by lib/std/process and cmd_test for signal propagation.
 *
 * blink_process_spawn returns an int64 handle (an index into a static
 * table). The handle owns the OS pid plus stdout/stderr read fds.
 * blink_process_pid_wait drains the pipes, reaps the child, and caches
 * the ProcessResult so a second wait is idempotent.
 * blink_process_pid_kill / send_signal forward the signal to the live
 * child by handle. Returns 0 on success, -1 if the pid is invalid or
 * already reaped.
 */
typedef struct {
    pid_t pid;
    int out_fd;
    int err_fd;
    int reaped;
    blink_ProcessResult cached;
} blink_pid_slot;

#define BLINK_PID_TABLE_CAP 4096

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
    int64_t blink_pid_table_len = 0;
    pthread_mutex_t blink_pid_table_mu = PTHREAD_MUTEX_INITIALIZER;
  #else
    extern blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
    extern int64_t blink_pid_table_len;
    extern pthread_mutex_t blink_pid_table_mu;
  #endif
#else
static blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
static int64_t blink_pid_table_len = 0;
static pthread_mutex_t blink_pid_table_mu = PTHREAD_MUTEX_INITIALIZER;
#endif

static int64_t blink_pid_table_alloc(void) {
    pthread_mutex_lock(&blink_pid_table_mu);
    /* Recycle reaped slots before growing — keeps long-running parents
     * (cmd_test orchestrates 720+ spawns) from exhausting the table. */
    for (int64_t i = 0; i < blink_pid_table_len; i++) {
        if (blink_pid_table[i].reaped && blink_pid_table[i].out_fd < 0 && blink_pid_table[i].err_fd < 0) {
            pthread_mutex_unlock(&blink_pid_table_mu);
            return i;
        }
    }
    if (blink_pid_table_len >= BLINK_PID_TABLE_CAP) {
        pthread_mutex_unlock(&blink_pid_table_mu);
        return -1;
    }
    int64_t h = blink_pid_table_len++;
    pthread_mutex_unlock(&blink_pid_table_mu);
    return h;
}

static blink_pid_slot* blink_pid_table_get(int64_t h) {
    if (h < 0 || h >= blink_pid_table_len) return NULL;
    return &blink_pid_table[h];
}

BLINK_RT_FN int64_t blink_process_spawn(const char* cmd, const blink_list* args);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_process_spawn(const char* cmd, const blink_list* args) {
    int64_t h = blink_pid_table_alloc();
    if (h < 0) return -1;
    blink_pid_slot* slot = &blink_pid_table[h];
    slot->pid = -1;
    slot->out_fd = -1;
    slot->err_fd = -1;
    slot->reaped = 0;
    slot->cached.out = "";
    slot->cached.err_out = "";
    slot->cached.exit_code = -1;

    int out_pipe[2] = {-1, -1}, err_pipe[2] = {-1, -1};
    if (pipe(out_pipe) < 0 || pipe(err_pipe) < 0) {
        if (out_pipe[0] >= 0) { close(out_pipe[0]); close(out_pipe[1]); }
        slot->reaped = 1;
        slot->cached.err_out = blink_strdup("pipe() failed");
        return h;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(out_pipe[0]); close(out_pipe[1]);
        close(err_pipe[0]); close(err_pipe[1]);
        slot->reaped = 1;
        slot->cached.err_out = blink_strdup("fork() failed");
        return h;
    }
    if (pid == 0) {
        close(out_pipe[0]);
        close(err_pipe[0]);
        dup2(out_pipe[1], STDOUT_FILENO);
        dup2(err_pipe[1], STDERR_FILENO);
        close(out_pipe[1]);
        close(err_pipe[1]);
        char** argv = blink_process_build_argv(cmd, args);
        execvp(cmd, argv);
        _exit(127);
    }
    close(out_pipe[1]);
    close(err_pipe[1]);
    slot->pid = pid;
    slot->out_fd = out_pipe[0];
    slot->err_fd = err_pipe[0];
    return h;
}
#endif

BLINK_RT_FN blink_ProcessResult blink_process_pid_wait(int64_t handle);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_ProcessResult blink_process_pid_wait(int64_t handle) {
    blink_pid_slot* slot = blink_pid_table_get(handle);
    if (!slot) {
        blink_ProcessResult r = { "", blink_strdup("invalid pid handle"), -1 };
        return r;
    }
    if (slot->reaped) return slot->cached;

    char* out = slot->out_fd >= 0 ? blink_read_fd_to_string(slot->out_fd) : (char*)"";
    char* err = slot->err_fd >= 0 ? blink_read_fd_to_string(slot->err_fd) : (char*)"";
    slot->out_fd = -1;
    slot->err_fd = -1;
    int status = 0;
    int64_t exit_code = -1;
    if (slot->pid > 0) {
        while (waitpid(slot->pid, &status, 0) < 0) {
            if (errno != EINTR) break;
        }
        if (WIFEXITED(status)) {
            exit_code = (int64_t)WEXITSTATUS(status);
        } else if (WIFSIGNALED(status)) {
            exit_code = 128 + (int64_t)WTERMSIG(status);
        }
    }
    slot->cached.out = out;
    slot->cached.err_out = err;
    slot->cached.exit_code = exit_code;
    slot->reaped = 1;
    return slot->cached;
}
#endif

static int64_t blink_pid_dispatch_signal(int64_t handle, int sig) {
    blink_pid_slot* slot = blink_pid_table_get(handle);
    if (!slot || slot->reaped || slot->pid <= 0) return -1;
    if (kill(slot->pid, sig) < 0) return -1;
    return 0;
}

// kill() with sig=0 is the POSIX existence check; we override that to SIGKILL
// so callers don't need a separate "force-kill" entry point.
BLINK_RT_FN int64_t blink_process_pid_kill(int64_t handle, int64_t sig);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_process_pid_kill(int64_t handle, int64_t sig) {
    return blink_pid_dispatch_signal(handle, sig == 0 ? SIGKILL : (int)sig);
}
#endif

BLINK_RT_FN int64_t blink_process_pid_send_signal(int64_t handle, int64_t sig);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_process_pid_send_signal(int64_t handle, int64_t sig) {
    return blink_pid_dispatch_signal(handle, (int)sig);
}
#endif

/* ── Signal forwarding to live spawned children ───────────────────────
 * Installs a SIGINT/SIGTERM handler that walks the pid handle table
 * and forwards SIGTERM to every live (non-reaped) child, then re-raises
 * the signal to the default handler so the parent unwinds normally.
 * Idempotent: safe to call more than once.
 */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    volatile sig_atomic_t blink_process_signal_installed = 0;
  #else
    extern volatile sig_atomic_t blink_process_signal_installed;
  #endif
#else
static volatile sig_atomic_t blink_process_signal_installed = 0;
#endif

static void blink_process_forward_signal(int sig) {
    /* Async-signal-safe: only kill() and write() to a known table.
     * Cannot acquire a mutex here, so accept the small race where a
     * brand-new spawn between the snapshot and the kill is missed.
     */
    int64_t n = blink_pid_table_len;
    for (int64_t i = 0; i < n; i++) {
        blink_pid_slot* slot = &blink_pid_table[i];
        if (!slot->reaped && slot->pid > 0) {
            kill(slot->pid, SIGTERM);
        }
    }
    /* Re-raise via default handler so the parent dies. */
    struct sigaction dfl;
    memset(&dfl, 0, sizeof(dfl));
    dfl.sa_handler = SIG_DFL;
    sigaction(sig, &dfl, NULL);
    raise(sig);
}

BLINK_RT_FN void blink_process_install_signal_forwarding(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_process_install_signal_forwarding(void) {
    if (blink_process_signal_installed) return;
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = blink_process_forward_signal;
    sa.sa_flags = SA_RESTART;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    blink_process_signal_installed = 1;
}
#endif

/*
 * Undefine POSIX signal macros after the runtime body is parsed so
 * Blink code further down (e.g. `pub let SIGTERM = 15` from
 * lib/std/process.bl) can declare these names without the preprocessor
 * expanding the LHS to a numeric literal. The runtime functions above
 * have already been compiled with the real macro values.
 */
#undef SIGHUP
#undef SIGINT
#undef SIGQUIT
#undef SIGILL
#undef SIGTRAP
#undef SIGABRT
#undef SIGBUS
#undef SIGFPE
#undef SIGKILL
#undef SIGUSR1
#undef SIGSEGV
#undef SIGUSR2
#undef SIGPIPE
#undef SIGALRM
#undef SIGTERM
#undef SIGCHLD
#undef SIGCONT
#undef SIGSTOP
#undef SIGTSTP
#undef SIGTTIN
#undef SIGTTOU
#undef SIGURG
#undef SIGXCPU
#undef SIGXFSZ
#undef SIGVTALRM
#undef SIGPROF
#undef SIGWINCH
#undef SIGIO
#undef SIGSYS

#endif
