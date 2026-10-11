#ifndef BLINK_RUNTIME_PROCESS_H
#define BLINK_RUNTIME_PROCESS_H

#ifndef _WIN32
#include <sys/wait.h>
#include <signal.h>
#include <poll.h>
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

#ifndef BLINK_RUNTIME_DECLS_ONLY
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

/* Read-pump for one fd when poll() reports it ready. Grows `*buf` as needed
 * and appends; on EOF/error closes the fd and clears `*open`. `pfd` is the
 * poll entry for this fd, or NULL when the fd is not being polled (skipped). */
static void blink_pump_fd(int fd, int* open, struct pollfd* pfd, char** buf, int64_t* cap, int64_t* len) {
    if (!*open || pfd == NULL || !(pfd->revents & (POLLIN | POLLHUP | POLLERR))) return;
    if (*len + 1024 > *cap) {
        int64_t old_cap = *cap;
        *cap *= 2;
        *buf = (char*)blink_realloc(*buf, old_cap, *cap);
    }
    ssize_t rc = read(fd, *buf + *len, (size_t)(*cap - *len - 1));
    if (rc < 0 && errno == EINTR) return; /* retry next loop */
    if (rc <= 0) { close(fd); *open = 0; return; }
    *len += rc;
}

/* Drain two child fds (stdout, stderr) CONCURRENTLY into freshly-allocated
 * GC strings. Draining one fd to EOF before touching the other deadlocks
 * when the child fills the second pipe's buffer (~64KB) while we block on
 * the first: the child blocks on write(), so it never closes the first fd,
 * so our read() never sees EOF. poll() lets us read whichever fd has data,
 * so neither pipe can fill. Either fd may be < 0 (skipped, yields ""). Both
 * fds are closed on return. Caller passes back the two NUL-terminated buffers. */
static void blink_drain_two_fds(int fd_a, int fd_b, char** out_a, char** out_b) {
    int open_a = fd_a >= 0, open_b = fd_b >= 0;
    int64_t cap_a = 4096, len_a = 0, cap_b = 4096, len_b = 0;
    char* buf_a = open_a ? (char*)blink_alloc_atomic(cap_a) : (char*)"";
    char* buf_b = open_b ? (char*)blink_alloc_atomic(cap_b) : (char*)"";
    while (open_a || open_b) {
        struct pollfd pfds[2];
        int n = 0;
        struct pollfd* pfd_a = NULL;
        struct pollfd* pfd_b = NULL;
        if (open_a) { pfds[n].fd = fd_a; pfds[n].events = POLLIN; pfd_a = &pfds[n]; n++; }
        if (open_b) { pfds[n].fd = fd_b; pfds[n].events = POLLIN; pfd_b = &pfds[n]; n++; }
        int pr = poll(pfds, (nfds_t)n, -1);
        if (pr < 0) { if (errno == EINTR) continue; break; }
        blink_pump_fd(fd_a, &open_a, pfd_a, &buf_a, &cap_a, &len_a);
        blink_pump_fd(fd_b, &open_b, pfd_b, &buf_b, &cap_b, &len_b);
    }
    *out_a = fd_a >= 0 ? (char*)blink_str_from_bytes(buf_a, len_a) : (char*)BLINK_STR_EMPTY;
    *out_b = fd_b >= 0 ? (char*)blink_str_from_bytes(buf_b, len_b) : (char*)BLINK_STR_EMPTY;
}
#endif

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
    blink_ProcessResult result = { BLINK_STR_EMPTY, BLINK_STR_EMPTY, -1 };
    int stdin_pipe[2] = {-1, -1}, stdout_pipe[2] = {-1, -1}, stderr_pipe[2] = {-1, -1};
    if (pipe(stdin_pipe) < 0 || pipe(stdout_pipe) < 0 || pipe(stderr_pipe) < 0) {
        if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
        if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
        result.err_out = blink_str_from_cstr_gc("pipe() failed");
        return result;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(stdin_pipe[0]); close(stdin_pipe[1]);
        close(stdout_pipe[0]); close(stdout_pipe[1]);
        close(stderr_pipe[0]); close(stderr_pipe[1]);
        result.err_out = blink_str_from_cstr_gc("fork() failed");
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
    /* Drain stdout + stderr concurrently — sequential draining deadlocks
     * when the child fills the not-yet-read pipe (see blink_drain_two_fds). */
    char* run_out = (char*)"";
    char* run_err = (char*)"";
    blink_drain_two_fds(stdout_pipe[0], stderr_pipe[0], &run_out, &run_err);
    result.out = run_out;
    result.err_out = run_err;
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
 * blink_process_spawn returns an int64 handle: gen * BLINK_PID_TABLE_CAP + slot index.
 * The slot owns the OS pid plus stdout/stderr read fds.
 * blink_process_pid_wait drains the pipes, reaps the child, and caches
 * the ProcessResult so a second wait is idempotent.
 * A slot is claimed and freed only under blink_pid_table_mu, and it is free
 * only once its owner has waited: two spawns at once must never share one.
 * A waited slot keeps its result. A spawn takes a never-used slot first, then the
 * slot waited longest ago, so a waited handle keeps its result for at least
 * BLINK_PID_TABLE_CAP - 1 - (other children not yet waited at its wait) later
 * spawns. Each claim bumps the slot's gen, so once a slot is reused the old handle
 * names no child: its wait gives an error result and its kill gives -1, never the
 * later child's.
 * blink_process_pid_kill / send_signal forward the signal to the live
 * child by handle. Returns 0 on success, -1 if the pid is invalid or
 * already reaped.
 */
typedef struct {
    pid_t pid;
    int out_fd;
    int err_fd;
    int reaped;
    int free;
    int64_t gen;
    blink_ProcessResult cached;
} blink_pid_slot;

#define BLINK_PID_TABLE_CAP 4096

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
    int64_t blink_pid_table_len = 0;
    int64_t blink_pid_waited[BLINK_PID_TABLE_CAP];
    int64_t blink_pid_waited_head = 0;
    int64_t blink_pid_waited_len = 0;
    pthread_mutex_t blink_pid_table_mu = PTHREAD_MUTEX_INITIALIZER;
  #else
    extern blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
    extern int64_t blink_pid_table_len;
    extern int64_t blink_pid_waited[BLINK_PID_TABLE_CAP];
    extern int64_t blink_pid_waited_head;
    extern int64_t blink_pid_waited_len;
    extern pthread_mutex_t blink_pid_table_mu;
  #endif
#else
static blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
static int64_t blink_pid_table_len = 0;
/* Ring of waited (free) slot indices, oldest wait first. */
static int64_t blink_pid_waited[BLINK_PID_TABLE_CAP];
static int64_t blink_pid_waited_head = 0;
static int64_t blink_pid_waited_len = 0;
static pthread_mutex_t blink_pid_table_mu = PTHREAD_MUTEX_INITIALIZER;
#endif

#ifndef BLINK_RUNTIME_DECLS_ONLY
static int64_t blink_pid_table_alloc(void) {
    pthread_mutex_lock(&blink_pid_table_mu);
    /* A never-used slot first, then the one waited longest ago, so a waited slot keeps
     * its result as long as it can. Reuse keeps long-running parents (cmd_test
     * orchestrates thousands of spawns) from exhausting the table. */
    int64_t i = -1;
    if (blink_pid_table_len < BLINK_PID_TABLE_CAP) {
        i = blink_pid_table_len++;
    } else if (blink_pid_waited_len > 0) {
        i = blink_pid_waited[blink_pid_waited_head];
        blink_pid_waited_head = (blink_pid_waited_head + 1) % BLINK_PID_TABLE_CAP;
        blink_pid_waited_len--;
    }
    int64_t h = -1;
    if (i >= 0) {
        /* Claimed before the unlock, so no other spawn can take it. */
        blink_pid_slot* slot = &blink_pid_table[i];
        slot->gen++;
        slot->free = 0;
        slot->pid = -1;
        slot->out_fd = -1;
        slot->err_fd = -1;
        slot->reaped = 0;
        slot->cached.out = BLINK_STR_EMPTY;
        slot->cached.err_out = BLINK_STR_EMPTY;
        slot->cached.exit_code = -1;
        h = slot->gen * BLINK_PID_TABLE_CAP + i;
    }
    pthread_mutex_unlock(&blink_pid_table_mu);
    return h;
}

/* Caller holds blink_pid_table_mu. NULL when h never named a slot, or names one a later
 * spawn has since taken. */
static blink_pid_slot* blink_pid_table_get_locked(int64_t h) {
    if (h < BLINK_PID_TABLE_CAP) return NULL;
    int64_t i = h % BLINK_PID_TABLE_CAP;
    if (i >= blink_pid_table_len) return NULL;
    blink_pid_slot* slot = &blink_pid_table[i];
    if (slot->gen != h / BLINK_PID_TABLE_CAP) return NULL;
    return slot;
}
#endif

BLINK_RT_FN int64_t blink_process_spawn(const char* cmd, const blink_list* args);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_process_spawn(const char* cmd, const blink_list* args) {
    int64_t h = blink_pid_table_alloc();
    if (h < 0) return -1;
#ifdef BLINK_DEV_PID_CLAIM_DELAY_US
    /* Dev knob: cc -DBLINK_DEV_PID_CLAIM_DELAY_US=<n> sleeps n microseconds after the slot is
     * taken, so a test can make concurrent spawns ask for slots while this one fills its own.
     * A cc define and not an env var, as no binary blink builds should carry it: these bodies
     * live in the std archive, so only a standalone runtime.h build compiled with it has it. */
    {
        long us = (long)(BLINK_DEV_PID_CLAIM_DELAY_US);
        struct timespec ts = { us / 1000000, (us % 1000000) * 1000 };
        nanosleep(&ts, NULL);
    }
#endif
    blink_pid_slot* slot = &blink_pid_table[h % BLINK_PID_TABLE_CAP];

    int out_pipe[2] = {-1, -1}, err_pipe[2] = {-1, -1};
    if (pipe(out_pipe) < 0 || pipe(err_pipe) < 0) {
        if (out_pipe[0] >= 0) { close(out_pipe[0]); close(out_pipe[1]); }
        slot->reaped = 1;
        slot->cached.err_out = blink_str_from_cstr_gc("pipe() failed");
        return h;
    }
    pid_t pid = fork();
    if (pid < 0) {
        close(out_pipe[0]); close(out_pipe[1]);
        close(err_pipe[0]); close(err_pipe[1]);
        slot->reaped = 1;
        slot->cached.err_out = blink_str_from_cstr_gc("fork() failed");
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
    pthread_mutex_lock(&blink_pid_table_mu);
    blink_pid_slot* slot = blink_pid_table_get_locked(handle);
    int reaped = slot ? slot->reaped : 0;
    pthread_mutex_unlock(&blink_pid_table_mu);
    if (!slot) {
        blink_ProcessResult r = { BLINK_STR_EMPTY, blink_str_from_cstr_gc("invalid pid handle"), -1 };
        return r;
    }
    if (!reaped) {
        /* The slot cannot be reused until this wait frees it, so it is read without the lock.
         * Drain stdout + stderr concurrently — sequential draining deadlocks
         * when the child fills the not-yet-read pipe (see blink_drain_two_fds). */
        char* out = (char*)"";
        char* err = (char*)"";
        blink_drain_two_fds(slot->out_fd, slot->err_fd, &out, &err);
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
        pthread_mutex_lock(&blink_pid_table_mu);
        slot->cached.out = out;
        slot->cached.err_out = err;
        slot->cached.exit_code = exit_code;
        slot->reaped = 1;
        pthread_mutex_unlock(&blink_pid_table_mu);
    }
    /* Copied under the lock, as once the slot is free a spawn may refill it. A spawn
     * that failed is reaped from the start, but stays its owner's until this wait. */
    pthread_mutex_lock(&blink_pid_table_mu);
    if (blink_pid_table_get_locked(handle) != slot) {
        /* Another wait on this handle freed the slot while this one drained, and a spawn
         * took it since. */
        pthread_mutex_unlock(&blink_pid_table_mu);
        blink_ProcessResult r = { BLINK_STR_EMPTY, blink_str_from_cstr_gc("invalid pid handle"), -1 };
        return r;
    }
    blink_ProcessResult result = slot->cached;
    if (!slot->free) {
        slot->free = 1;
        int64_t tail = (blink_pid_waited_head + blink_pid_waited_len) % BLINK_PID_TABLE_CAP;
        blink_pid_waited[tail] = slot - blink_pid_table;
        blink_pid_waited_len++;
    }
    pthread_mutex_unlock(&blink_pid_table_mu);
    return result;
}
#endif

#ifndef BLINK_RUNTIME_DECLS_ONLY
static int64_t blink_pid_dispatch_signal(int64_t handle, int sig) {
    /* Under the lock, so the slot cannot pass to a later child between the check and kill(). */
    pthread_mutex_lock(&blink_pid_table_mu);
    blink_pid_slot* slot = blink_pid_table_get_locked(handle);
    int64_t rc = -1;
    if (slot && !slot->reaped && slot->pid > 0 && kill(slot->pid, sig) == 0) rc = 0;
    pthread_mutex_unlock(&blink_pid_table_mu);
    return rc;
}
#endif

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

#ifndef BLINK_RUNTIME_DECLS_ONLY
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
#endif

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
