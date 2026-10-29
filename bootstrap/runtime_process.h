#ifndef BLINK_RUNTIME_PROCESS_H
#define BLINK_RUNTIME_PROCESS_H

#ifndef _WIN32
#include <sys/wait.h>
#include <signal.h>
#include <poll.h>
#endif

/* LimitKind and ChildEnd as lib/std/process.bl declares them. They are runtime-owned
 * (src/layout.bl), so codegen spells them as these names and skips its own typedefs; the
 * shape, tag values and enumerator names here must match what it would emit. */
#ifndef BLINK_TD_blink_LimitKind
#define BLINK_TD_blink_LimitKind
typedef enum { blink_LimitKind_Timeout, blink_LimitKind_Memory, blink_LimitKind_Processes } blink_LimitKind;
#endif
#ifndef BLINK_TD_blink_ChildEnd
#define BLINK_TD_blink_ChildEnd
typedef struct blink_ChildEnd {
    int32_t tag;
    union {
        struct {
            int64_t _0;
        } Exited;
        struct {
            int64_t _0;
        } Signaled;
        struct {
            blink_LimitKind _0;
        } Limit;
    } data;
} blink_ChildEnd;
#endif
#ifndef blink_ChildEnd_Exited_TAG
#define blink_ChildEnd_Exited_TAG 0
#endif
#ifndef blink_ChildEnd_Signaled_TAG
#define blink_ChildEnd_Signaled_TAG 1
#endif
#ifndef blink_ChildEnd_Limit_TAG
#define blink_ChildEnd_Limit_TAG 2
#endif

typedef struct {
    const char* out;
    const char* err_out;
    blink_ChildEnd end;
} blink_ProcessResult;

static inline blink_ChildEnd blink_child_end_exited(int64_t code) {
    blink_ChildEnd e;
    memset(&e, 0, sizeof(e));
    e.tag = blink_ChildEnd_Exited_TAG;
    e.data.Exited._0 = code;
    return e;
}

static inline blink_ChildEnd blink_child_end_signaled(int64_t sig) {
    blink_ChildEnd e;
    memset(&e, 0, sizeof(e));
    e.tag = blink_ChildEnd_Signaled_TAG;
    e.data.Signaled._0 = sig;
    return e;
}

/* The end of a result that names no child that ended: a spawn that failed, a wait that
 * failed, or a handle whose result is gone. The old free functions still answer these
 * paths with a result; the spec makes each of them an Err, not an end. */
static inline blink_ChildEnd blink_child_end_none(void) {
    return blink_child_end_exited(-1);
}

static inline void blink_process_result_set_status(blink_ProcessResult* r, int status) {
    if (WIFEXITED(status)) {
        r->end = blink_child_end_exited((int64_t)WEXITSTATUS(status));
    } else if (WIFSIGNALED(status)) {
        r->end = blink_child_end_signaled((int64_t)WTERMSIG(status));
    } else {
        r->end = blink_child_end_none();
    }
}

static inline blink_ProcessResult blink_process_result_none(const char* err_out) {
    blink_ProcessResult r = { BLINK_STR_EMPTY, err_out, blink_child_end_none() };
    return r;
}

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
    blink_ProcessResult result = blink_process_result_none(BLINK_STR_EMPTY);
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
    int status = 0;
    int wrc;
    while ((wrc = waitpid(pid, &status, 0)) < 0) {
        if (errno != EINTR) break;
    }
    sigaction(SIGINT, &sa_int_old, NULL);
    blink_child_pid = 0;
    if (wrc >= 0) blink_process_result_set_status(&result, status);
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
 * A waited slot keeps its result while the results kept in all waited slots total
 * at most BLINK_PID_KEPT_BYTES; past that the oldest are dropped, though the newest
 * is always kept. A spawn takes a never-used slot first, then the slot waited
 * longest ago. Each claim and each drop bumps the slot's gen, so a handle whose
 * result was dropped or whose slot was reused names no child: its wait gives an
 * error result and its kill gives -1, never the later child's.
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
    int64_t kept_bytes;
    blink_ProcessResult cached;
} blink_pid_slot;

/* Also the radix of a handle, gen * BLINK_PID_TABLE_CAP + index. A slot's gen grows once
 * per claim and once per drop, at most twice per spawn, so with this bound a handle
 * stays below 2^63 for the first 2^50 spawns into that slot. */
#define BLINK_PID_TABLE_CAP 4096
_Static_assert(BLINK_PID_TABLE_CAP > 0 && BLINK_PID_TABLE_CAP <= (1 << 16),
               "a pid handle keeps gen * BLINK_PID_TABLE_CAP below 2^63");

#define BLINK_PID_KEPT_BYTES (1 << 20)

/* blink_pid_waited is a ring of waited (free) slot indices, oldest wait first. Its first
 * blink_pid_waited_dropped entries have dropped their results; the rest keep
 * blink_pid_kept_bytes in all. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
    int64_t blink_pid_table_len = 0;
    int64_t blink_pid_waited[BLINK_PID_TABLE_CAP];
    int64_t blink_pid_waited_head = 0;
    int64_t blink_pid_waited_len = 0;
    int64_t blink_pid_waited_dropped = 0;
    int64_t blink_pid_kept_bytes = 0;
    pthread_mutex_t blink_pid_table_mu = PTHREAD_MUTEX_INITIALIZER;
  #else
    extern blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
    extern int64_t blink_pid_table_len;
    extern int64_t blink_pid_waited[BLINK_PID_TABLE_CAP];
    extern int64_t blink_pid_waited_head;
    extern int64_t blink_pid_waited_len;
    extern int64_t blink_pid_waited_dropped;
    extern int64_t blink_pid_kept_bytes;
    extern pthread_mutex_t blink_pid_table_mu;
  #endif
#else
static blink_pid_slot blink_pid_table[BLINK_PID_TABLE_CAP];
static int64_t blink_pid_table_len = 0;
static int64_t blink_pid_waited[BLINK_PID_TABLE_CAP];
static int64_t blink_pid_waited_head = 0;
static int64_t blink_pid_waited_len = 0;
static int64_t blink_pid_waited_dropped = 0;
static int64_t blink_pid_kept_bytes = 0;
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
        if (blink_pid_waited_dropped > 0) {
            blink_pid_waited_dropped--;
        } else {
            blink_pid_kept_bytes -= blink_pid_table[i].kept_bytes;
        }
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
        slot->cached.end = blink_child_end_none();
        slot->kept_bytes = 0;
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

/* Caller holds blink_pid_table_mu. Frees a reaped slot for reuse and keeps its result
 * until the kept-bytes bound drops it. A second free of one slot does nothing. */
static void blink_pid_slot_free_locked(blink_pid_slot* slot) {
    if (slot->free) return;
    slot->free = 1;
    int64_t tail = (blink_pid_waited_head + blink_pid_waited_len) % BLINK_PID_TABLE_CAP;
    blink_pid_waited[tail] = slot - blink_pid_table;
    blink_pid_waited_len++;
    slot->kept_bytes = blink_str_len(slot->cached.out) + blink_str_len(slot->cached.err_out);
    blink_pid_kept_bytes += slot->kept_bytes;
    /* Kept results stay reachable from this static table, so without a bound a
     * program that spawns many children with large output keeps them all. */
    while (blink_pid_kept_bytes > BLINK_PID_KEPT_BYTES
           && blink_pid_waited_len - blink_pid_waited_dropped > 1) {
        int64_t at = (blink_pid_waited_head + blink_pid_waited_dropped) % BLINK_PID_TABLE_CAP;
        blink_pid_slot* old = &blink_pid_table[blink_pid_waited[at]];
        blink_pid_kept_bytes -= old->kept_bytes;
        old->kept_bytes = 0;
        old->cached.out = BLINK_STR_EMPTY;
        old->cached.err_out = BLINK_STR_EMPTY;
        old->gen++;
        blink_pid_waited_dropped++;
    }
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
        /* The child reads the null device, never the parent's input (spec: process.spawn),
           so it exits rather than run with the parent's stdin. */
        int dn = open("/dev/null", O_RDONLY);
        if (dn < 0 || dup2(dn, STDIN_FILENO) < 0) _exit(127);
        if (dn != STDIN_FILENO) close(dn);
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
        return blink_process_result_none(blink_str_from_cstr_gc("invalid pid handle"));
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
        blink_ProcessResult waited = blink_process_result_none(err);
        waited.out = out;
        if (slot->pid > 0) {
            int status = 0;
            int rc;
            while ((rc = waitpid(slot->pid, &status, 0)) < 0) {
                if (errno != EINTR) break;
            }
            if (rc >= 0) blink_process_result_set_status(&waited, status);
        }
        pthread_mutex_lock(&blink_pid_table_mu);
        slot->cached = waited;
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
        return blink_process_result_none(blink_str_from_cstr_gc("invalid pid handle"));
    }
    blink_ProcessResult result = slot->cached;
    blink_pid_slot_free_locked(slot);
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

/* ── Child box: the Result surface of std.process ─────────────────────
 * process.run/spawn/wait/signal/exec (sections/04_effects.md §4.4.8) report each failure
 * as an errno, which lib/std/process.bl turns into Err(ProcessError). The entry points
 * above keep their sentinel results for the free fns until those are removed.
 *
 * A Child is a pointer to one of these boxes, so every copy of a Child sees the one
 * wait: the box keeps the result of the first wait, and a later wait returns it again.
 * cmd is the program the box was made for, so an error on a later op can name it.
 * err is the errno of the op that made or last used the box, 0 when it succeeded.
 * handle is the pid table handle of a spawned child, -1 for a run. */
typedef struct {
    pthread_mutex_t mu;
    const char* cmd;
    int64_t handle;
    int64_t err;
    int64_t waited;
    blink_ProcessResult result;
} blink_child_box;

#if defined(__linux__)
/* glibc declares pipe2 only past _GNU_SOURCE, which runtime_core.h does not set. */
int pipe2(int pipefd[2], int flags);
#endif

#ifndef BLINK_RUNTIME_DECLS_ONLY
/* Every pipe of a child op is close-on-exec, so a child that another thread forks at the
 * same time does not keep this child's pipes open: a read end then sees EOF only when its
 * own child closes it. The child moves each one onto 0/1/2 with blink_child_move_fd, which
 * clears the flag on the copy it keeps. */
static int blink_child_pipe(int fds[2]) {
#if defined(__linux__)
    return pipe2(fds, O_CLOEXEC);
#else
    if (pipe(fds) < 0) return -1;
    fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    return 0;
#endif
}

static void blink_child_close_pair(int fds[2]) {
    if (fds[0] >= 0) close(fds[0]);
    if (fds[1] >= 0) close(fds[1]);
    fds[0] = -1;
    fds[1] = -1;
}

static blink_child_box* blink_child_box_new(const char* cmd) {
    blink_child_box* b = (blink_child_box*)blink_alloc(sizeof(blink_child_box));
    pthread_mutex_init(&b->mu, NULL);
    b->cmd = cmd;
    b->handle = -1;
    b->err = 0;
    b->waited = 0;
    b->result = blink_process_result_none(BLINK_STR_EMPTY);
    return b;
}

/* A C string stops at its first NUL, so a NUL inside cmd or an arg would reach the child
 * as a shorter string than the caller wrote. */
static int blink_child_strings_ok(const char* cmd, const blink_list* args) {
    if (memchr(cmd, 0, (size_t)blink_str_len(cmd)) != NULL) return 0;
    int64_t n = args ? args->len : 0;
    for (int64_t i = 0; i < n; i++) {
        const char* a = (const char*)args->items[i];
        if (memchr(a, 0, (size_t)blink_str_len(a)) != NULL) return 0;
    }
    return 1;
}

/* dup2 onto the same fd does nothing, so it would leave a close-on-exec pipe that a parent
 * with fd 0 or 1 closed got back on that fd to close at exec. */
static int blink_child_move_fd(int from, int to) {
    if (from == to) return fcntl(to, F_SETFD, 0);
    return dup2(from, to) < 0 ? -1 : 0;
}

/* Runs in the forked child, so it only calls async-signal-safe functions: the argv was
 * built before the fork. stdin_fd < 0 means the null device. If the exec fails, the errno
 * goes to the parent through err_fd and the child exits without running atexit hooks. */
static void blink_child_exec_or_report(char** argv, int stdin_fd, int out_fd, int err_fd, int report_fd) {
    int e = 0;
    int in = stdin_fd;
    if (in < 0) {
        in = open("/dev/null", O_RDONLY);
        if (in < 0) e = errno;
    }
    if (e == 0 && blink_child_move_fd(in, STDIN_FILENO) < 0) e = errno;
    if (stdin_fd < 0 && in > STDERR_FILENO) close(in);
    if (e == 0 && blink_child_move_fd(out_fd, STDOUT_FILENO) < 0) e = errno;
    if (e == 0 && blink_child_move_fd(err_fd, STDERR_FILENO) < 0) e = errno;
    if (e == 0) {
        execvp(argv[0], argv);
        e = errno;
    }
    ssize_t w;
    do { w = write(report_fd, &e, sizeof(e)); } while (w < 0 && errno == EINTR);
    _exit(127);
}

/* The parent's side of the report pipe: 0 once the child's exec succeeded (its copy of
 * the close-on-exec write end closed with no bytes), else the errno the child sent. A read
 * that fails or stops part way leaves the exec unknown, so it counts as a failure and the
 * caller reaps the child. */
static int blink_child_read_report(int report_fd) {
    int e = 0;
    int read_err = 0;
    ssize_t got = 0;
    while (got < (ssize_t)sizeof(e)) {
        ssize_t n = read(report_fd, (char*)&e + got, sizeof(e) - (size_t)got);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) read_err = errno;
        if (n <= 0) break;
        got += n;
    }
    close(report_fd);
    if (read_err != 0) return read_err;
    if (got == 0) return 0;
    if (got < (ssize_t)sizeof(e)) return EIO;
    return e != 0 ? e : EIO;
}

/* Forks a child on the given pipes and returns 0 with *pid_out set once it has exec'd,
 * or the errno of the fork or the exec. A child whose exec failed is reaped here. */
static int blink_child_fork_exec(char** argv, int stdin_fd, int out_fd, int err_fd, pid_t* pid_out) {
    int report[2] = {-1, -1};
    if (blink_child_pipe(report) < 0) return errno;
    pid_t pid = fork();
    if (pid < 0) {
        int e = errno;
        blink_child_close_pair(report);
        return e;
    }
    if (pid == 0) {
        close(report[0]);
        blink_child_exec_or_report(argv, stdin_fd, out_fd, err_fd, report[1]);
    }
    close(report[1]);
    int e = blink_child_read_report(report[0]);
    if (e != 0) {
        /* A child whose report could not be read may have exec'd and run on; the op
         * reports Err, so it must not leave that program running. */
        kill(pid, SIGKILL);
        int status;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        return e;
    }
    *pid_out = pid;
    return 0;
}

/* Writes in_data to in_fd while it drains out_fd and err_fd, all in one poll loop, so a
 * child that writes before it has read all its input cannot block the parent, nor the
 * parent the child. in_fd is closed once all is written or the child closed its end; a
 * child that exits without reading its input is not an error. SIGPIPE is blocked in this
 * thread for the loop and a SIGPIPE the loop raised is taken back, so no other thread's
 * signal disposition changes. */
static void blink_child_pump(int in_fd, const char* in_data, int64_t in_len,
                             int out_fd, int err_fd, char** out, char** err) {
    sigset_t pipe_set, old_mask, pending;
    sigemptyset(&pipe_set);
    sigaddset(&pipe_set, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &pipe_set, &old_mask);
    sigpending(&pending);
    int pipe_was_pending = sigismember(&pending, SIGPIPE);
    int raised_pipe = 0;

    int open_in = in_fd >= 0, open_out = out_fd >= 0, open_err = err_fd >= 0;
    int64_t written = 0;
    if (open_in && in_len == 0) { close(in_fd); open_in = 0; }
    if (open_in) {
        int fl = fcntl(in_fd, F_GETFL);
        if (fl >= 0) fcntl(in_fd, F_SETFL, fl | O_NONBLOCK);
    }
    int64_t cap_o = 4096, len_o = 0, cap_e = 4096, len_e = 0;
    char* buf_o = (char*)blink_alloc_atomic(cap_o);
    char* buf_e = (char*)blink_alloc_atomic(cap_e);
    while (open_in || open_out || open_err) {
        struct pollfd pfds[3];
        int n = 0;
        struct pollfd* p_in = NULL;
        struct pollfd* p_out = NULL;
        struct pollfd* p_err = NULL;
        if (open_in) { pfds[n].fd = in_fd; pfds[n].events = POLLOUT; pfds[n].revents = 0; p_in = &pfds[n]; n++; }
        if (open_out) { pfds[n].fd = out_fd; pfds[n].events = POLLIN; pfds[n].revents = 0; p_out = &pfds[n]; n++; }
        if (open_err) { pfds[n].fd = err_fd; pfds[n].events = POLLIN; pfds[n].revents = 0; p_err = &pfds[n]; n++; }
        int pr = poll(pfds, (nfds_t)n, -1);
        if (pr < 0) { if (errno == EINTR) continue; break; }
        if (p_in && (p_in->revents & (POLLOUT | POLLERR | POLLHUP))) {
            ssize_t w = write(in_fd, in_data + written, (size_t)(in_len - written));
            if (w > 0) written += w;
            if (w < 0 && errno == EPIPE) raised_pipe = 1;
            if ((w < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK)
                || written >= in_len) {
                close(in_fd);
                open_in = 0;
            }
        }
        blink_pump_fd(out_fd, &open_out, p_out, &buf_o, &cap_o, &len_o);
        blink_pump_fd(err_fd, &open_err, p_err, &buf_e, &cap_e, &len_e);
    }
    if (open_in) close(in_fd);
    if (open_out) close(out_fd);
    if (open_err) close(err_fd);
    *out = (char*)blink_str_from_bytes(buf_o, len_o);
    *err = (char*)blink_str_from_bytes(buf_e, len_e);

    if (raised_pipe && !pipe_was_pending) {
        sigpending(&pending);
        if (sigismember(&pending, SIGPIPE)) {
            int got;
            sigwait(&pipe_set, &got);
        }
    }
    pthread_sigmask(SIG_SETMASK, &old_mask, NULL);
}

/* waitpid that retries on EINTR. Returns 0 and the status, or the errno. */
static int blink_child_waitpid(pid_t pid, int* status) {
    while (waitpid(pid, status, 0) < 0) {
        if (errno != EINTR) return errno;
    }
    return 0;
}
#endif

/* process.run: the box holds the result, or err when no result came. has_stdin 0 gives
 * the child the null device for its input. */
BLINK_RT_FN blink_child_box* blink_child_run(const char* cmd, const blink_list* args, int64_t has_stdin, const char* stdin_data);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_child_box* blink_child_run(const char* cmd, const blink_list* args, int64_t has_stdin, const char* stdin_data) {
    blink_child_box* box = blink_child_box_new(cmd);
    if (!blink_child_strings_ok(cmd, args)) { box->err = EINVAL; return box; }
    char** argv = blink_process_build_argv(cmd, args);
    int in_pipe[2] = {-1, -1}, out_pipe[2] = {-1, -1}, err_pipe[2] = {-1, -1};
    if ((has_stdin && blink_child_pipe(in_pipe) < 0) || blink_child_pipe(out_pipe) < 0
        || blink_child_pipe(err_pipe) < 0) {
        box->err = errno;
        blink_child_close_pair(in_pipe);
        blink_child_close_pair(out_pipe);
        blink_child_close_pair(err_pipe);
        return box;
    }
    pid_t pid = -1;
    int e = blink_child_fork_exec(argv, in_pipe[0], out_pipe[1], err_pipe[1], &pid);
    if (in_pipe[0] >= 0) close(in_pipe[0]);
    close(out_pipe[1]);
    close(err_pipe[1]);
    if (e != 0) {
        if (in_pipe[1] >= 0) close(in_pipe[1]);
        close(out_pipe[0]);
        close(err_pipe[0]);
        box->err = e;
        return box;
    }
    char* out = (char*)"";
    char* err = (char*)"";
    blink_child_pump(in_pipe[1], stdin_data, has_stdin ? blink_str_len(stdin_data) : 0,
                     out_pipe[0], err_pipe[0], &out, &err);
    /* As blink_process_run_with_stdin: a Ctrl-C while the child runs reaches it, and the
     * parent takes it once the child is reaped. */
    blink_child_pid = pid;
    blink_got_sigint = 0;
    struct sigaction sa_int_old, sa_int_new;
    memset(&sa_int_new, 0, sizeof(sa_int_new));
    sa_int_new.sa_handler = blink_sigint_handler;
    sa_int_new.sa_flags = SA_RESTART;
    sigaction(SIGINT, &sa_int_new, &sa_int_old);
    int status = 0;
    int we = blink_child_waitpid(pid, &status);
    sigaction(SIGINT, &sa_int_old, NULL);
    blink_child_pid = 0;
    if (we != 0) {
        box->err = we;
    } else {
        box->result.out = out;
        box->result.err_out = err;
        blink_process_result_set_status(&box->result, status);
        box->waited = 1;
    }
    if (blink_got_sigint) raise(SIGINT);
    return box;
}
#endif

/* process.spawn: err is EAGAIN when the pid table has no free slot, else the errno of the
 * pipe, fork or exec. A slot is taken only for a child that exec'd. */
BLINK_RT_FN blink_child_box* blink_child_spawn(const char* cmd, const blink_list* args);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_child_box* blink_child_spawn(const char* cmd, const blink_list* args) {
    blink_child_box* box = blink_child_box_new(cmd);
    if (!blink_child_strings_ok(cmd, args)) { box->err = EINVAL; return box; }
    char** argv = blink_process_build_argv(cmd, args);
    int64_t h = blink_pid_table_alloc();
    if (h < 0) { box->err = EAGAIN; return box; }
    blink_pid_slot* slot = &blink_pid_table[h % BLINK_PID_TABLE_CAP];
    int out_pipe[2] = {-1, -1}, err_pipe[2] = {-1, -1};
    int e = 0;
    pid_t pid = -1;
    if (blink_child_pipe(out_pipe) < 0 || blink_child_pipe(err_pipe) < 0) {
        e = errno;
        blink_child_close_pair(out_pipe);
        blink_child_close_pair(err_pipe);
    } else {
        e = blink_child_fork_exec(argv, -1, out_pipe[1], err_pipe[1], &pid);
        close(out_pipe[1]);
        close(err_pipe[1]);
        if (e != 0) {
            close(out_pipe[0]);
            close(err_pipe[0]);
        }
    }
    if (e != 0) {
        pthread_mutex_lock(&blink_pid_table_mu);
        slot->reaped = 1;
        blink_pid_slot_free_locked(slot);
        pthread_mutex_unlock(&blink_pid_table_mu);
        box->err = e;
        return box;
    }
    pthread_mutex_lock(&blink_pid_table_mu);
    slot->pid = pid;
    slot->out_fd = out_pipe[0];
    slot->err_fd = err_pipe[0];
    pthread_mutex_unlock(&blink_pid_table_mu);
    box->handle = h;
    return box;
}
#endif

/* process.wait: 0 once the box holds the result, else the errno; ECHILD when the box
 * names no child the table still has. Waits on one box run one at a time, so the second
 * returns the first's result. The child is reaped under the table lock, after a wait that
 * leaves it a zombie: until then its pid stays its own, so a signal sent before the reap
 * cannot reach a later process that the OS gave the same pid. */
BLINK_RT_FN int64_t blink_child_wait(blink_child_box* box);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_child_wait(blink_child_box* box) {
    pthread_mutex_lock(&box->mu);
    if (box->waited) {
        pthread_mutex_unlock(&box->mu);
        return 0;
    }
    pthread_mutex_lock(&blink_pid_table_mu);
    blink_pid_slot* slot = box->handle >= 0 ? blink_pid_table_get_locked(box->handle) : NULL;
    if (slot && (slot->free || slot->reaped || slot->pid <= 0)) slot = NULL;
    pthread_mutex_unlock(&blink_pid_table_mu);
    if (!slot) {
        pthread_mutex_unlock(&box->mu);
        return ECHILD;
    }
    /* Only this box owns the slot, and the slot stays claimed until the free below, so its
     * fds and pid are read without the table lock. */
    char* out = (char*)"";
    char* err = (char*)"";
    blink_child_pump(-1, NULL, 0, slot->out_fd, slot->err_fd, &out, &err);
    slot->out_fd = -1;
    slot->err_fd = -1;
    int e = 0;
    siginfo_t info;
    while (waitid(P_PID, (id_t)slot->pid, &info, WEXITED | WNOWAIT) < 0) {
        if (errno != EINTR) { e = errno; break; }
    }
    int status = 0;
    pthread_mutex_lock(&blink_pid_table_mu);
    if (e == 0) e = blink_child_waitpid(slot->pid, &status);
    slot->reaped = 1;
    slot->cached = blink_process_result_none(BLINK_STR_EMPTY);
    blink_pid_slot_free_locked(slot);
    pthread_mutex_unlock(&blink_pid_table_mu);
    if (e == 0) {
        box->result.out = out;
        box->result.err_out = err;
        blink_process_result_set_status(&box->result, status);
        box->waited = 1;
    }
    /* The slot is free either way, so a later wait on this box gives ECHILD. */
    __atomic_store_n(&box->handle, (int64_t)-1, __ATOMIC_RELEASE);
    box->err = e;
    pthread_mutex_unlock(&box->mu);
    return e;
}
#endif

/* process.signal: 0 or the errno of kill(2); ESRCH once the child was waited or reaped,
 * checked under the table lock, so the pid cannot have passed to another process. */
BLINK_RT_FN int64_t blink_child_signal(blink_child_box* box, int64_t sig);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_child_signal(blink_child_box* box, int64_t sig) {
    if (sig < 0 || sig != (int64_t)(int)sig) return EINVAL;
    int64_t e = ESRCH;
    pthread_mutex_lock(&blink_pid_table_mu);
    int64_t h = __atomic_load_n(&box->handle, __ATOMIC_ACQUIRE);
    blink_pid_slot* slot = h >= 0 ? blink_pid_table_get_locked(h) : NULL;
    if (slot && !slot->free && !slot->reaped && slot->pid > 0) {
        e = kill(slot->pid, (int)sig) == 0 ? 0 : errno;
    }
    pthread_mutex_unlock(&blink_pid_table_mu);
    return e;
}
#endif

/* process.exec: returns only when the exec failed, with its errno. Buffered output is
 * flushed first, as the new program replaces this one's buffers. */
BLINK_RT_FN int64_t blink_child_exec(const char* cmd, const blink_list* args);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_child_exec(const char* cmd, const blink_list* args) {
    if (!blink_child_strings_ok(cmd, args)) return EINVAL;
    char** argv = blink_process_build_argv(cmd, args);
    fflush(stdout);
    fflush(stderr);
    execvp(cmd, argv);
    return errno;
}
#endif

BLINK_RT_FN int64_t blink_child_box_err(blink_child_box* box);
BLINK_RT_FN const char* blink_child_box_cmd(blink_child_box* box);
BLINK_RT_FN const char* blink_child_box_out(blink_child_box* box);
BLINK_RT_FN const char* blink_child_box_err_out(blink_child_box* box);
BLINK_RT_FN int64_t blink_child_box_end_tag(blink_child_box* box);
BLINK_RT_FN int64_t blink_child_box_end_value(blink_child_box* box);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_child_box_err(blink_child_box* box) { return box->err; }
BLINK_RT_FN const char* blink_child_box_cmd(blink_child_box* box) { return box->cmd; }
BLINK_RT_FN const char* blink_child_box_out(blink_child_box* box) { return box->result.out; }
BLINK_RT_FN const char* blink_child_box_err_out(blink_child_box* box) { return box->result.err_out; }
BLINK_RT_FN int64_t blink_child_box_end_tag(blink_child_box* box) { return (int64_t)box->result.end.tag; }
BLINK_RT_FN int64_t blink_child_box_end_value(blink_child_box* box) {
    switch (box->result.end.tag) {
    case blink_ChildEnd_Exited_TAG: return box->result.end.data.Exited._0;
    case blink_ChildEnd_Signaled_TAG: return box->result.end.data.Signaled._0;
    default: return 0;
    }
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

/* The host's name for signal n, or "SIG<n>" when the host has none (a real-time signal
 * included). A table and not a switch: some hosts give two names one number (SIGPWR is
 * SIGINFO on some), and the first row wins. */
BLINK_RT_FN const char* blink_process_signal_name(int64_t n);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_process_signal_name(int64_t n) {
    static const struct { int num; const char* name; } names[] = {
        { SIGHUP, "SIGHUP" }, { SIGINT, "SIGINT" }, { SIGQUIT, "SIGQUIT" },
        { SIGILL, "SIGILL" }, { SIGTRAP, "SIGTRAP" }, { SIGABRT, "SIGABRT" },
        { SIGBUS, "SIGBUS" }, { SIGFPE, "SIGFPE" }, { SIGKILL, "SIGKILL" },
        { SIGUSR1, "SIGUSR1" }, { SIGSEGV, "SIGSEGV" }, { SIGUSR2, "SIGUSR2" },
        { SIGPIPE, "SIGPIPE" }, { SIGALRM, "SIGALRM" }, { SIGTERM, "SIGTERM" },
        { SIGCHLD, "SIGCHLD" }, { SIGCONT, "SIGCONT" }, { SIGSTOP, "SIGSTOP" },
        { SIGTSTP, "SIGTSTP" }, { SIGTTIN, "SIGTTIN" }, { SIGTTOU, "SIGTTOU" },
        { SIGURG, "SIGURG" }, { SIGXCPU, "SIGXCPU" }, { SIGXFSZ, "SIGXFSZ" },
        { SIGVTALRM, "SIGVTALRM" }, { SIGPROF, "SIGPROF" }, { SIGWINCH, "SIGWINCH" },
        { SIGIO, "SIGIO" }, { SIGSYS, "SIGSYS" },
#ifdef SIGSTKFLT
        { SIGSTKFLT, "SIGSTKFLT" },
#endif
#ifdef SIGPWR
        { SIGPWR, "SIGPWR" },
#endif
#ifdef SIGEMT
        { SIGEMT, "SIGEMT" },
#endif
#ifdef SIGINFO
        { SIGINFO, "SIGINFO" },
#endif
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if ((int64_t)names[i].num == n) return blink_str_from_cstr_gc(names[i].name);
    }
    char buf[32];
    snprintf(buf, sizeof(buf), "SIG%lld", (long long)n);
    return blink_str_from_cstr_gc(buf);
}
#endif

/* The one answer to "can run and spawn apply a limit of this kind here" (blink_LimitKind
 * numbering). process.can_limit and the ENOTSUP check of run and spawn both ask it, so the
 * two never disagree. memory and processes need a delegated cgroup v2, which this runtime
 * does not use yet, so they are never supported; the timeout needs the limits thread. */
BLINK_RT_FN int64_t blink_child_limit_supported(int64_t kind);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_child_limit_supported(int64_t kind) {
    (void)kind;
    return 0;
}
#endif

#endif
