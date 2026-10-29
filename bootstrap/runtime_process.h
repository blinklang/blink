#ifndef BLINK_RUNTIME_PROCESS_H
#define BLINK_RUNTIME_PROCESS_H

#ifndef _WIN32
#include <sys/wait.h>
#include <signal.h>
#include <poll.h>
#endif
#if defined(__linux__)
#include <sys/prctl.h>
#include <sys/inotify.h>
#include <sys/statfs.h>
#include <sys/syscall.h>
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

static inline blink_ChildEnd blink_child_end_limit(blink_LimitKind kind) {
    blink_ChildEnd e;
    memset(&e, 0, sizeof(e));
    e.tag = blink_ChildEnd_Limit_TAG;
    e.data.Limit._0 = kind;
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
    pthread_mutex_t blink_sigint_mu = PTHREAD_MUTEX_INITIALIZER;
    int blink_sigint_users = 0;
    struct sigaction blink_sigint_saved;
  #else
    extern volatile pid_t blink_child_pid;
    extern volatile sig_atomic_t blink_got_sigint;
    extern pthread_mutex_t blink_sigint_mu;
    extern int blink_sigint_users;
    extern struct sigaction blink_sigint_saved;
  #endif
#else
static volatile pid_t blink_child_pid = 0;
static volatile sig_atomic_t blink_got_sigint = 0;
static pthread_mutex_t blink_sigint_mu = PTHREAD_MUTEX_INITIALIZER;
static int blink_sigint_users = 0;
static struct sigaction blink_sigint_saved;
#endif

#ifndef BLINK_RUNTIME_DECLS_ONLY
static void blink_sigint_handler(int sig) {
    (void)sig;
    blink_got_sigint = 1;
    pid_t p = blink_child_pid;
    if (p > 0) kill(p, SIGINT);
}

/* Runs that wait for a child at the same time share one SIGINT action: the first sets
 * blink_sigint_handler and the last puts back the action from before. With a save and a
 * put-back per run, a run put back a stale action when another run overlapped it, or when
 * the limits thread set its own action meanwhile. */
static void blink_sigint_enter(void) {
    pthread_mutex_lock(&blink_sigint_mu);
    if (blink_sigint_users++ == 0) {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = blink_sigint_handler;
        sa.sa_flags = SA_RESTART;
        sigaction(SIGINT, &sa, &blink_sigint_saved);
    }
    pthread_mutex_unlock(&blink_sigint_mu);
}

static void blink_sigint_leave(void) {
    pthread_mutex_lock(&blink_sigint_mu);
    if (--blink_sigint_users == 0) sigaction(SIGINT, &blink_sigint_saved, NULL);
    pthread_mutex_unlock(&blink_sigint_mu);
}

static int blink_sigaction_is_default(const struct sigaction* sa) {
    return !(sa->sa_flags & SA_SIGINFO) && sa->sa_handler == SIG_DFL;
}

/* Sets handler as the action for sig when the program has left it the default one. For
 * SIGINT while a run waits, that is the action the run puts back. */
static void blink_signal_set_if_default(int sig, void (*handler)(int)) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handler;
    sa.sa_flags = SA_RESTART;
    pthread_mutex_lock(&blink_sigint_mu);
    if (sig == SIGINT && blink_sigint_users > 0) {
        if (blink_sigaction_is_default(&blink_sigint_saved)) blink_sigint_saved = sa;
    } else {
        struct sigaction cur;
        if (sigaction(sig, NULL, &cur) == 0 && blink_sigaction_is_default(&cur)) sigaction(sig, &sa, NULL);
    }
    pthread_mutex_unlock(&blink_sigint_mu);
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
    blink_sigint_enter();
    int status = 0;
    int wrc;
    while ((wrc = waitpid(pid, &status, 0)) < 0) {
        if (errno != EINTR) break;
    }
    blink_sigint_leave();
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
    /* The limits code reaps a limited child at program exit without this slot's reaped. */
    int limited;
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
        slot->limited = 0;
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
struct blink_limit_rec;

typedef struct {
    pthread_mutex_t mu;
    const char* cmd;
    int64_t handle;
    int64_t err;
    int64_t waited;
    blink_ProcessResult result;
    struct blink_limit_rec* lim;
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
    b->lim = NULL;
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

/* The clock of every child deadline, in nanoseconds. Interim choice, the one place for it: a
 * clock that stops while the host is suspended, since a suspended child does not run. On
 * Linux CLOCK_MONOTONIC stops; on macOS it does not, and CLOCK_UPTIME_RAW does. */
static int64_t blink_limits_now(void) {
    struct timespec ts;
#if defined(__APPLE__)
    clock_gettime(CLOCK_UPTIME_RAW, &ts);
#else
    clock_gettime(CLOCK_MONOTONIC, &ts);
#endif
    return (int64_t)ts.tv_sec * 1000000000 + (int64_t)ts.tv_nsec;
}

/* The poll timeout in ms that ends at stop_at (blink_limits_now time), rounded up so the
 * poll does not wake before it; -1, no end, for a stop_at < 0. */
static int blink_limits_poll_ms(int64_t stop_at) {
    if (stop_at < 0) return -1;
    int64_t left = stop_at - blink_limits_now();
    if (left <= 0) return 0;
    int64_t ms = (left + 999999) / 1000000;
    return ms > (1 << 30) ? (1 << 30) : (int)ms;
}

/* Writes in_data to in_fd while it drains out_fd and err_fd, all in one poll loop, so a
 * child that writes before it has read all its input cannot block the parent, nor the
 * parent the child. in_fd is closed once all is written or the child closed its end; a
 * child that exits without reading its input is not an error. SIGPIPE is blocked in this
 * thread for the loop and a SIGPIPE the loop raised is taken back, so no other thread's
 * signal disposition changes. At stop_at (blink_limits_now time; < 0 for never) the loop
 * stops without end of file and keeps what it read. */
/* Past stop_at the loop still takes all that is in the pipes, up to this many bytes, so a
 * wait that comes late keeps what the child wrote before it ended. Two full pipes at the
 * Linux maximum size fit; a grandchild that writes on and on stops the loop here. */
#define BLINK_PUMP_DRAIN_BYTES (2 * 1024 * 1024LL)

static void blink_child_pump(int in_fd, const char* in_data, int64_t in_len,
                             int out_fd, int err_fd, char** out, char** err, int64_t stop_at) {
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
    int last = 0;
    int64_t drain_end = 0;
    while (open_in || open_out || open_err) {
        struct pollfd pfds[3];
        int n = 0;
        struct pollfd* p_in = NULL;
        struct pollfd* p_out = NULL;
        struct pollfd* p_err = NULL;
        if (open_in) { pfds[n].fd = in_fd; pfds[n].events = POLLOUT; pfds[n].revents = 0; p_in = &pfds[n]; n++; }
        if (open_out) { pfds[n].fd = out_fd; pfds[n].events = POLLIN; pfds[n].revents = 0; p_out = &pfds[n]; n++; }
        if (open_err) { pfds[n].fd = err_fd; pfds[n].events = POLLIN; pfds[n].revents = 0; p_err = &pfds[n]; n++; }
        int poll_ms = last ? 0 : blink_limits_poll_ms(stop_at);
        if (poll_ms == 0 && !last) {
            last = 1;
            drain_end = len_o + len_e + BLINK_PUMP_DRAIN_BYTES;
        }
        int pr = poll(pfds, (nfds_t)n, poll_ms);
        if (pr < 0) { if (errno == EINTR) continue; break; }
        if (pr == 0) break;
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
        if (last && len_o + len_e >= drain_end) break;
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

/* ── Child limits (sections/04_effects.md §4.4.8 Child limits) ────────
 * A child with a limit is forked by one long-lived limits thread, which the first such child
 * starts and which never ends. Linux sends the parent-death signal when the thread that
 * forked a child ends, not the process, so a child that a short-lived async task forked
 * itself would get SIGKILL when the task ended. The same thread keeps every deadline: it
 * polls its wake pipe for the time to the next one, signals the group of the child at the
 * deadline, and again after the grace. It never reaps: run and wait do, as for any child.
 *
 * Each limited child has a record. rec->mu orders a group signal against the reap: the
 * thread signals only while the leader is not reaped, so its pid, which is the pgid, is
 * still this child's. Lock order: blink_limits.mu, then rec->mu; blink_pid_table_mu, then
 * rec->mu. Nothing that can exit the program runs under either lock.
 *
 * The spec does not settle every choice here yet. Each such interim choice sits in one
 * place, named as one, so a later answer is a small edit. */

#define BLINK_LIMIT_NEVER INT64_MAX

/* Interim choice: how long past timeout + grace run and wait still read the pipes of a
 * child, so the output that the last signals flushed is kept. */
#define BLINK_LIMIT_EOF_DELAY_NS (200 * 1000000LL)

enum { BLINK_LIMIT_WAITING, BLINK_LIMIT_TERMED, BLINK_LIMIT_KILLED };

#define BLINK_LIMIT_NONE (-1)

typedef struct blink_limit_rec {
    struct blink_limit_rec* next;
    pthread_mutex_t mu;
    pid_t pid;          /* also the pgid */
    int64_t deadline;   /* set before the record is shared, then never changed */
    int64_t grace;      /* likewise */
    int64_t kill_at;
    int stage;
    int limit;          /* the blink_LimitKind that ended the child, or BLINK_LIMIT_NONE; the first wins */
    char* cg;           /* the child's own cgroup (malloc), NULL when it has none */
    int cg_memory;      /* the cgroup holds a memory limit */
    int cg_pids;        /* the cgroup holds a processes limit */
    int cg_killed;      /* cgroup.kill was written: the tree ends */
    int reaped;
    int released;       /* its run or wait is done with it, so the thread frees it */
    int reaped_at_exit; /* the program-exit path reaped it; status is the leader's */
    int exit_gone;      /* the kernel reaped it (SIGCHLD ignored), so no wait finds it */
    int status;
    int exit_live;      /* the program-exit path still waits for its group */
    int64_t exit_kill_at;
} blink_limit_rec;

/* A fork that a run or spawn asks of the limits thread. It lives on the stack of the
 * asking thread, which waits until done is set. */
typedef struct blink_limit_req {
    struct blink_limit_req* next;
    char** argv;
    int stdin_fd, out_fd, err_fd, report_fd;
    sigset_t mask;
    int64_t timeout, grace;
    int64_t memory, processes;  /* -1: no limit */
    blink_limit_rec* rec;
    int err;
    int done;
} blink_limit_req;

typedef struct {
    pthread_mutex_t mu;
    pthread_cond_t served;
    int started;
    int ending;         /* the program-exit path has begun: no fork is served from then on */
    volatile sig_atomic_t pending_sig;
    int wake_rd, wake_wr;
    blink_limit_rec* recs;
    blink_limit_req* reqs;
} blink_limits_state;

#define BLINK_LIMITS_STATE_INIT { PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, 0, 0, 0, -1, -1, NULL, NULL }

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_limits_state blink_limits = BLINK_LIMITS_STATE_INIT;
  #else
    extern blink_limits_state blink_limits;
  #endif
#else
static blink_limits_state blink_limits = BLINK_LIMITS_STATE_INIT;
#endif

/* ── Child cgroups (§4.4.8 Memory and process count need a delegated cgroup v2) ──────────
 * memory and processes need a cgroup v2 that this program owns: its own cgroup D, which it
 * may write, with no process in it that is not this program or one of its descendants. At
 * the first such limit this program moves itself, and every descendant still in D, to the
 * leaf D/blink.self, and turns on the memory and pids controllers for the children of D.
 * Each child with memory or processes then starts in a cgroup of its own,
 * D/blink.child.<pid>.<n>. A child with only a timeout gets no cgroup.
 *
 * Only the limits thread, under blink_limits.mu, moves this program and makes or removes a
 * child cgroup. The check of support runs once, on whichever thread asks first, and never
 * creates or changes a cgroup. */
#if defined(__linux__)
#define BLINK_CG_ROOT "/sys/fs/cgroup"
#define BLINK_CG_PATH 4096
#define BLINK_CG2_SUPER_MAGIC 0x63677270
/* PID_MAX_LIMIT + 1: pids.max takes no number from here up, and no tree can reach it. */
#define BLINK_CG_PIDS_MAX 4194305LL

typedef struct blink_cg_left {
    struct blink_cg_left* next;
    char* path;
} blink_cg_left;

typedef struct {
    pthread_once_t once;
    int memory_ok;
    int pids_ok;
    int move;           /* 0: not moved yet; 1: moved; else the errno of the move, kept */
    int ino_fd;         /* inotify on the event files of each child cgroup; -1 until the first */
    int64_t seq;
    blink_cg_left* left; /* child cgroups that still held a process when their record went */
    char dir[BLINK_CG_PATH];
} blink_cg_state;

#define BLINK_CG_STATE_INIT { PTHREAD_ONCE_INIT, 0, 0, 0, -1, 0, NULL, {0} }

#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_cg_state blink_cg = BLINK_CG_STATE_INIT;
  #else
    extern blink_cg_state blink_cg;
  #endif
#else
static blink_cg_state blink_cg = BLINK_CG_STATE_INIT;
#endif

/* glibc and musl declare syscall only past _GNU_SOURCE or _DEFAULT_SOURCE. */
long syscall(long number, ...);

#ifndef BLINK_RUNTIME_DECLS_ONLY
/* Reads a whole file into a malloc'd NUL-terminated buffer; NULL with errno set. */
static char* blink_cg_slurp(const char* path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return NULL;
    size_t cap = 4096, len = 0;
    char* buf = (char*)malloc(cap);
    while (buf != NULL) {
        if (len + 1 >= cap) {
            char* grown = (char*)realloc(buf, cap * 2);
            if (grown == NULL) { free(buf); buf = NULL; errno = ENOMEM; break; }
            buf = grown;
            cap *= 2;
        }
        ssize_t n = read(fd, buf + len, cap - 1 - len);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { int e = errno; free(buf); buf = NULL; errno = e; break; }
        if (n == 0) { buf[len] = 0; break; }
        len += (size_t)n;
    }
    int e = errno;
    close(fd);
    errno = e;
    return buf;
}

/* 0, or the errno of the open or the write. */
static int blink_cg_write(const char* path, const char* text) {
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return errno;
    size_t len = strlen(text);
    ssize_t w;
    do { w = write(fd, text, len); } while (w < 0 && errno == EINTR);
    int e = w < 0 ? errno : ((size_t)w == len ? 0 : EIO);
    close(fd);
    return e;
}

/* The number on the line "<key> <n>" of a flat-keyed cgroup file; -1 when there is none. */
static int64_t blink_cg_count(const char* cg, const char* file, const char* key) {
    char path[BLINK_CG_PATH];
    if (snprintf(path, sizeof(path), "%s/%s", cg, file) >= (int)sizeof(path)) return -1;
    char* text = blink_cg_slurp(path);
    if (text == NULL) return -1;
    int64_t n = -1;
    size_t klen = strlen(key);
    for (char* line = text; *line != 0;) {
        if (strncmp(line, key, klen) == 0 && line[klen] == ' ') {
            n = (int64_t)strtoll(line + klen + 1, NULL, 10);
            break;
        }
        char* nl = strchr(line, '\n');
        if (nl == NULL) break;
        line = nl + 1;
    }
    free(text);
    return n;
}

static int blink_cg_has_word(const char* text, const char* word) {
    size_t wlen = strlen(word);
    for (const char* p = text; (p = strstr(p, word)) != NULL; p += wlen) {
        int starts = p == text || p[-1] == ' ' || p[-1] == '\n';
        int ends = p[wlen] == 0 || p[wlen] == ' ' || p[wlen] == '\n';
        if (starts && ends) return 1;
    }
    return 0;
}

static int blink_cg_exists(const char* dir, const char* file, int mode) {
    char path[BLINK_CG_PATH];
    if (snprintf(path, sizeof(path), "%s/%s", dir, file) >= (int)sizeof(path)) return 0;
    return access(path, mode) == 0;
}

/* 1 when pid is this program or one of its descendants, 0 when it is not, -1 when it is
 * gone. A process whose parent ended has a new parent, so only a chain that reaches self
 * counts. */
static int blink_cg_is_ours(pid_t pid, pid_t self) {
    for (int depth = 0; depth < 4096; depth++) {
        if (pid == self) return 1;
        if (pid <= 1) return 0;
        char path[64];
        snprintf(path, sizeof(path), "/proc/%d/stat", (int)pid);
        char* stat = blink_cg_slurp(path);
        if (stat == NULL) return depth == 0 ? -1 : 0;
        /* The name in parentheses may hold any byte, so the fields start after the last ')'. */
        char* rp = strrchr(stat, ')');
        char state = 0;
        int ppid = 0;
        int got = rp != NULL ? sscanf(rp + 1, " %c %d", &state, &ppid) : 0;
        free(stat);
        if (got != 2) return 0;
        pid = (pid_t)ppid;
    }
    return 0;
}

/* 1 when every process in cgroup.procs of dir is ours (or gone), else 0. */
static int blink_cg_all_ours(const char* dir) {
    char path[BLINK_CG_PATH];
    if (snprintf(path, sizeof(path), "%s/cgroup.procs", dir) >= (int)sizeof(path)) return 0;
    char* procs = blink_cg_slurp(path);
    if (procs == NULL) return 0;
    pid_t self = getpid();
    int ok = 1;
    for (char* p = procs; ok && *p != 0;) {
        char* end = NULL;
        long pid = strtol(p, &end, 10);
        if (end == p) break;
        if (blink_cg_is_ours((pid_t)pid, self) == 0) ok = 0;
        p = end;
        while (*p == '\n') p++;
    }
    free(procs);
    return ok;
}

/* The one check of support, made once (pthread_once). It only reads. */
static void blink_cg_check(void) {
    char* self_cg = blink_cg_slurp("/proc/self/cgroup");
    if (self_cg == NULL) return;
    /* A cgroup v2 only host gives the one line "0::<path>". */
    char* nl = strchr(self_cg, '\n');
    int one_line = strncmp(self_cg, "0::/", 4) == 0 && nl != NULL && nl[1] == 0;
    if (one_line) *nl = 0;
    char dir[BLINK_CG_PATH];
    /* The root cgroup belongs to the host, never to one program. */
    int fits = one_line && strcmp(self_cg + 3, "/") != 0
        && snprintf(dir, sizeof(dir), "%s%s", BLINK_CG_ROOT, self_cg + 3) < (int)sizeof(dir);
    free(self_cg);
    if (!fits) return;
    struct statfs fs;
    if (statfs(BLINK_CG_ROOT, &fs) != 0 || (unsigned long)fs.f_type != BLINK_CG2_SUPER_MAGIC) return;
    char path[BLINK_CG_PATH];
    snprintf(path, sizeof(path), "%s/cgroup.type", dir);
    char* type = blink_cg_slurp(path);
    int domain = type != NULL && strcmp(type, "domain\n") == 0;
    free(type);
    if (!domain) return;
    if (access(dir, W_OK) != 0 || !blink_cg_exists(dir, "cgroup.procs", W_OK)
        || !blink_cg_exists(dir, "cgroup.subtree_control", W_OK)
        || !blink_cg_exists(dir, "cgroup.kill", F_OK) || !blink_cg_exists(dir, "cgroup.freeze", F_OK)) {
        return;
    }
    if (!blink_cg_all_ours(dir)) return;
    snprintf(path, sizeof(path), "%s/cgroup.controllers", dir);
    char* ctl = blink_cg_slurp(path);
    if (ctl == NULL) return;
    /* memory.swap.max: the kernel counts swap, so the child cannot pass its limit through it.
     * memory.events.local: the kernel tells this cgroup's own limit apart from one below it.
     * pids.events.local: the kernel tells this cgroup's own refused forks apart. */
    blink_cg.memory_ok = blink_cg_has_word(ctl, "memory") && blink_cg_exists(dir, "memory.swap.max", F_OK)
        && blink_cg_exists(dir, "memory.events.local", F_OK);
    blink_cg.pids_ok = blink_cg_has_word(ctl, "pids") && blink_cg_exists(dir, "pids.events.local", F_OK);
    free(ctl);
    memcpy(blink_cg.dir, dir, sizeof(dir));
}

static int blink_cg_supported(int kind) {
    pthread_once(&blink_cg.once, blink_cg_check);
    if (kind == blink_LimitKind_Memory) return blink_cg.memory_ok;
    if (kind == blink_LimitKind_Processes) return blink_cg.pids_ok;
    return 0;
}

/* Moves every process in D to the leaf and turns on the controllers. A fork that lands in D
 * meanwhile makes the controller write fail with EBUSY, so it tries again a bounded number
 * of times. */
static int blink_cg_move_now(void) {
    char leaf[BLINK_CG_PATH], leaf_procs[BLINK_CG_PATH], d_procs[BLINK_CG_PATH], subtree[BLINK_CG_PATH];
    snprintf(leaf, sizeof(leaf), "%s/blink.self", blink_cg.dir);
    snprintf(leaf_procs, sizeof(leaf_procs), "%s/cgroup.procs", leaf);
    snprintf(d_procs, sizeof(d_procs), "%s/cgroup.procs", blink_cg.dir);
    snprintf(subtree, sizeof(subtree), "%s/cgroup.subtree_control", blink_cg.dir);
    if (mkdir(leaf, 0755) != 0 && errno != EEXIST) return errno;
    const char* enable = blink_cg.memory_ok && blink_cg.pids_ok ? "+memory +pids"
        : (blink_cg.memory_ok ? "+memory" : "+pids");
    pid_t self = getpid();
    for (int round = 0; round < 100; round++) {
        /* All or nothing: a process that is not ours, found half way, would leave this
         * program in the leaf with the controllers off. */
        if (!blink_cg_all_ours(blink_cg.dir)) return EBUSY;
        char* procs = blink_cg_slurp(d_procs);
        if (procs == NULL) return errno;
        int moved = 0;
        for (char* p = procs; *p != 0;) {
            char* end = NULL;
            long pid = strtol(p, &end, 10);
            if (end == p) break;
            p = end;
            while (*p == '\n') p++;
            /* Checked again right before the write, as the pid may have passed to a process
             * that is not ours since the check of support. */
            int ours = blink_cg_is_ours((pid_t)pid, self);
            if (ours < 0) continue;
            if (ours == 0) { free(procs); return EBUSY; }
            char num[32];
            snprintf(num, sizeof(num), "%ld", pid);
            int e = blink_cg_write(leaf_procs, num);
            if (e != 0 && e != ESRCH) { free(procs); return e; }
            moved = 1;
        }
        free(procs);
        if (moved) continue;
        int e = blink_cg_write(subtree, enable);
        if (e != EBUSY) return e;
    }
    return EBUSY;
}

/* The move happens once. A failed move is kept, so each later memory or processes limit
 * gives the same errno and the program is not moved half way twice. Caller holds
 * blink_limits.mu. */
static int blink_cg_move_locked(void) {
    if (blink_cg.move == 0) {
        int e = blink_cg_move_now();
        blink_cg.move = e == 0 ? 1 : e;
    }
    return blink_cg.move == 1 ? 0 : blink_cg.move;
}

static int blink_cg_watch(const char* cg, const char* file) {
    char path[BLINK_CG_PATH];
    snprintf(path, sizeof(path), "%s/%s", cg, file);
    return inotify_add_watch(blink_cg.ino_fd, path, IN_MODIFY) < 0 ? errno : 0;
}

/* Makes the cgroup of one child, with its limits set, and opens what the fork needs: the
 * cgroup itself for clone3, and its cgroup.procs for a host with no clone3. -1 is no
 * limit. 0, else the errno, and then no cgroup is left. Caller holds blink_limits.mu. */
static int blink_cg_child_make(int64_t memory, int64_t processes, char** cg_out, int* dir_fd, int* procs_fd) {
    if ((memory >= 0 && !blink_cg_supported(blink_LimitKind_Memory))
        || (processes >= 0 && !blink_cg_supported(blink_LimitKind_Processes))) {
        return ENOTSUP;
    }
    int e = blink_cg_move_locked();
    if (e != 0) return e;
    if (blink_cg.ino_fd < 0) {
        blink_cg.ino_fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
        if (blink_cg.ino_fd < 0) return errno;
    }
    char cg[BLINK_CG_PATH];
    blink_cg.seq++;
    if (snprintf(cg, sizeof(cg), "%s/blink.child.%d.%lld", blink_cg.dir, (int)getpid(),
                 (long long)blink_cg.seq) >= (int)sizeof(cg)) {
        return ENAMETOOLONG;
    }
    if (mkdir(cg, 0755) != 0) return errno;
    char path[BLINK_CG_PATH], num[32];
    if (memory >= 0) {
        snprintf(num, sizeof(num), "%lld", (long long)memory);
        snprintf(path, sizeof(path), "%s/memory.max", cg);
        e = blink_cg_write(path, num);
        snprintf(path, sizeof(path), "%s/memory.swap.max", cg);
        if (e == 0) e = blink_cg_write(path, "0");
        /* The kernel ends the whole tree at the limit, not one process in it. */
        snprintf(path, sizeof(path), "%s/memory.oom.group", cg);
        if (e == 0) e = blink_cg_write(path, "1");
        if (e == 0) e = blink_cg_watch(cg, "memory.events");
    }
    if (e == 0 && processes >= 0) {
        if (processes >= BLINK_CG_PIDS_MAX) snprintf(num, sizeof(num), "max");
        else snprintf(num, sizeof(num), "%lld", (long long)processes);
        snprintf(path, sizeof(path), "%s/pids.max", cg);
        e = blink_cg_write(path, num);
        if (e == 0) e = blink_cg_watch(cg, "pids.events.local");
    }
    if (e == 0) e = blink_cg_watch(cg, "cgroup.events");
    if (e == 0) {
        *dir_fd = open(cg, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (*dir_fd < 0) e = errno;
    }
    if (e == 0) {
        snprintf(path, sizeof(path), "%s/cgroup.procs", cg);
        *procs_fd = open(path, O_WRONLY | O_CLOEXEC);
        if (*procs_fd < 0) {
            e = errno;
            close(*dir_fd);
            *dir_fd = -1;
        }
    }
    char* copy = e == 0 ? (char*)malloc(strlen(cg) + 1) : NULL;
    if (e == 0 && copy == NULL) {
        e = ENOMEM;
        close(*dir_fd);
        close(*procs_fd);
        *dir_fd = *procs_fd = -1;
    }
    if (e != 0) {
        rmdir(cg);
        return e;
    }
    strcpy(copy, cg);
    *cg_out = copy;
    return 0;
}

/* Ends every process in the cgroup of a child. */
static void blink_cg_kill(blink_limit_rec* rec) {
    char path[BLINK_CG_PATH];
    snprintf(path, sizeof(path), "%s/cgroup.kill", rec->cg);
    blink_cg_write(path, "1");
    rec->cg_killed = 1;
}

/* The kernel ended a process of this cgroup at its memory limit. oom alone counts each time
 * the limit was reached; oom_kill alone also counts a kill for the memory of the whole host.
 * The oom is the local one, as memory.events also counts the limit of a cgroup below this
 * one (a limited child that is a Blink program makes its own); the kill is not, as with
 * memory.oom.group the victims may sit in such a cgroup. */
static int blink_cg_memory_hit(const blink_limit_rec* rec) {
    return rec->cg_memory && blink_cg_count(rec->cg, "memory.events.local", "oom") > 0
        && blink_cg_count(rec->cg, "memory.events", "oom_kill") > 0;
}

/* Removes cg, and first each cgroup below it: a child may make its own, as a limited child
 * that is a Blink program does. 0, else the errno of cg, which stays while a process holds
 * it or a cgroup below it. */
static int blink_cg_remove_tree(const char* cg, int depth) {
    DIR* dir = depth < 64 ? opendir(cg) : NULL;
    if (dir != NULL) {
        char path[BLINK_CG_PATH];
        struct dirent* ent;
        while ((ent = readdir(dir)) != NULL) {
            if (ent->d_name[0] == '.') continue;
            struct stat st;
            if (fstatat(dirfd(dir), ent->d_name, &st, 0) != 0 || !S_ISDIR(st.st_mode)) continue;
            if (snprintf(path, sizeof(path), "%s/%s", cg, ent->d_name) >= (int)sizeof(path)) continue;
            blink_cg_remove_tree(path, depth + 1);
        }
        closedir(dir);
    }
    return rmdir(cg) == 0 || errno == ENOENT ? 0 : errno;
}

/* A record whose run or wait is done: its cgroup goes too, or waits in the left list while
 * a process that the cgroup.kill has not ended yet still holds it. Caller holds
 * blink_limits.mu. */
static void blink_cg_release_locked(blink_limit_rec* rec) {
    if (rec->cg == NULL) return;
    if (blink_cg_remove_tree(rec->cg, 0) == 0) {
        free(rec->cg);
    } else {
        blink_cg_left* left = (blink_cg_left*)malloc(sizeof(blink_cg_left));
        if (left == NULL) {
            free(rec->cg);
        } else {
            left->path = rec->cg;
            left->next = blink_cg.left;
            blink_cg.left = left;
        }
    }
    rec->cg = NULL;
}

/* Tries the removal of each left cgroup again; the inotify on its cgroup.events wakes the
 * thread when its last process ends. Caller holds blink_limits.mu. */
static void blink_cg_left_locked(void) {
    blink_cg_left** at = &blink_cg.left;
    while (*at != NULL) {
        blink_cg_left* left = *at;
        if (blink_cg_remove_tree(left->path, 0) == 0) {
            *at = left->next;
            free(left->path);
            free(left);
        } else {
            at = &left->next;
        }
    }
}

/* Sends sig to each process of cg and of each cgroup below it. The caller has frozen the
 * tree, so no listed process ends and passes its pid on before its kill. */
static void blink_cg_signal_tree(const char* cg, int sig, int depth) {
    char path[BLINK_CG_PATH];
    if (snprintf(path, sizeof(path), "%s/cgroup.procs", cg) >= (int)sizeof(path)) return;
    char* procs = blink_cg_slurp(path);
    if (procs != NULL) {
        for (char* p = procs; *p != 0;) {
            char* end = NULL;
            long pid = strtol(p, &end, 10);
            if (end == p) break;
            if (pid > 0) kill((pid_t)pid, sig);
            p = end;
            while (*p == '\n') p++;
        }
        free(procs);
    }
    if (depth >= 64) return;
    DIR* dir = opendir(cg);
    if (dir == NULL) return;
    struct dirent* ent;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        struct stat st;
        if (fstatat(dirfd(dir), ent->d_name, &st, 0) != 0 || !S_ISDIR(st.st_mode)) continue;
        if (snprintf(path, sizeof(path), "%s/%s", cg, ent->d_name) >= (int)sizeof(path)) continue;
        blink_cg_signal_tree(path, sig, depth + 1);
    }
    closedir(dir);
}

/* Sends sig to every process in the cgroup of a child, the ones that left its process group
 * (setsid) too. SIGKILL is cgroup.kill. Another signal goes to each process while the tree is
 * frozen; 0 when the tree did not freeze in time, and then the caller signals the group only,
 * as a pid read from an unfrozen cgroup may name another process by the time of its kill.
 * Caller holds rec->mu. */
static int blink_cg_send(blink_limit_rec* rec, int sig) {
    if (sig == SIGKILL) {
        blink_cg_kill(rec);
        return 1;
    }
    char path[BLINK_CG_PATH];
    snprintf(path, sizeof(path), "%s/cgroup.freeze", rec->cg);
    if (blink_cg_write(path, "1") != 0) return 0;
    int frozen = 0;
    for (int i = 0; i < 200 && !(frozen = blink_cg_count(rec->cg, "cgroup.events", "frozen") == 1); i++) {
        struct timespec ts = { 0, 1000000L };
        nanosleep(&ts, NULL);
    }
    if (frozen) blink_cg_signal_tree(rec->cg, sig, 0);
    blink_cg_write(path, "0");
    return frozen;
}
#endif
#endif

#ifndef BLINK_RUNTIME_DECLS_ONLY
static int64_t blink_limits_add(int64_t a, int64_t b) {
    if (b > 0 && a > BLINK_LIMIT_NEVER - b) return BLINK_LIMIT_NEVER;
    return a + b;
}

/* When run or wait stop reading the pipes of a limited child: timeout + grace + a short
 * delay. Before that they wait for end of file, as for a child with no limit. -1 (never)
 * for a box with no limit. */
static int64_t blink_limits_stop_at(const struct blink_limit_rec* rec) {
    if (rec == NULL) return -1;
    int64_t at = blink_limits_add(blink_limits_add(rec->deadline, rec->grace), BLINK_LIMIT_EOF_DELAY_NS);
    return at == BLINK_LIMIT_NEVER ? -1 : at;
}

/* Async-signal-safe. A full pipe already holds a wake, so EAGAIN loses nothing. */
static void blink_limits_wake(void) {
    int fd = blink_limits.wake_wr;
    if (fd < 0) return;
    int saved = errno;
    char c = 1;
    ssize_t w;
    do { w = write(fd, &c, 1); } while (w < 0 && errno == EINTR);
    errno = saved;
}

/* 1 while the leader of rec runs, else 0 with info set to how it ended. Caller holds
 * rec->mu, and the leader is not reaped. */
static int blink_limits_leader_runs(blink_limit_rec* rec, siginfo_t* info) {
    memset(info, 0, sizeof(*info));
    int r;
    do { r = waitid(P_PID, (id_t)rec->pid, info, WEXITED | WNOHANG | WNOWAIT); } while (r < 0 && errno == EINTR);
    return !(r == 0 && info->si_pid == rec->pid);
}

/* Sends sig to a limited child: to its cgroup when it has one, so a process that left the
 * process group gets it too, else to its process group. SIGKILL goes to both. Caller holds
 * rec->mu, and the leader is not reaped or its group still has a member. */
static void blink_limits_signal_locked(blink_limit_rec* rec, int sig) {
#if defined(__linux__)
    if (rec->cg != NULL && blink_cg_send(rec, sig) && sig != SIGKILL) return;
#endif
    kill(-rec->pid, sig);
}

/* The deadline of a child came. Interim choice, the one place for it: the group gets the
 * signal whenever the leader is not reaped, even when the leader has exited, since the
 * children it started may run on; the limit ended the child only if the leader still ran.
 * A grace of zero is SIGKILL at once, as the spec says. Caller holds rec->mu, and the
 * leader is not reaped. */
static void blink_limits_deadline_locked(blink_limit_rec* rec, int64_t now) {
    siginfo_t info;
    if (blink_limits_leader_runs(rec, &info) && rec->limit == BLINK_LIMIT_NONE) {
        rec->limit = blink_LimitKind_Timeout;
    }
    if (rec->grace == 0) {
        blink_limits_signal_locked(rec, SIGKILL);
        rec->stage = BLINK_LIMIT_KILLED;
    } else {
        blink_limits_signal_locked(rec, SIGTERM);
        rec->kill_at = blink_limits_add(now, rec->grace);
        rec->stage = BLINK_LIMIT_TERMED;
    }
}

#if defined(__linux__)
/* Reads the events of the cgroup of a child. Interim choices, the one place for them: a
 * refused fork ends the tree at once with cgroup.kill, and is Limit(Processes) only while the
 * leader still ran, since a leader that exited on its own was not ended. A memory kill is
 * Limit(Memory) while the leader ran or when that kill ended it; the kernel already ended
 * the tree, and cgroup.kill ends what it spared. When both are seen at once, memory wins.
 * Caller holds rec->mu, and the leader is not reaped. */
static void blink_cg_events_locked(blink_limit_rec* rec) {
    if (rec->cg == NULL || rec->cg_killed) return;
    int memory = blink_cg_memory_hit(rec);
    int processes = !memory && rec->cg_pids && blink_cg_count(rec->cg, "pids.events.local", "max") > 0;
    if (!memory && !processes) return;
    siginfo_t info;
    int runs = blink_limits_leader_runs(rec, &info);
    if (rec->limit == BLINK_LIMIT_NONE) {
        if (memory && (runs || (info.si_code == CLD_KILLED && info.si_status == SIGKILL))) {
            rec->limit = blink_LimitKind_Memory;
        } else if (processes && runs) {
            rec->limit = blink_LimitKind_Processes;
        }
    }
    blink_cg_kill(rec);
}
#endif

/* One pass of the thread over every record: signals what is due, frees what run or wait
 * released, and returns the time of the next thing due. Caller holds blink_limits.mu. */
static int64_t blink_limits_tick_locked(int64_t now) {
    int64_t next = BLINK_LIMIT_NEVER;
    blink_limit_rec** at = &blink_limits.recs;
    while (*at != NULL) {
        blink_limit_rec* rec = *at;
        pthread_mutex_lock(&rec->mu);
        if (rec->released) {
            *at = rec->next;
#if defined(__linux__)
            blink_cg_release_locked(rec);
#endif
            pthread_mutex_unlock(&rec->mu);
            pthread_mutex_destroy(&rec->mu);
            free(rec);
            continue;
        }
        if (!rec->reaped) {
#if defined(__linux__)
            blink_cg_events_locked(rec);
#endif
            if (rec->stage == BLINK_LIMIT_WAITING && now >= rec->deadline) {
                blink_limits_deadline_locked(rec, now);
            }
            if (rec->stage == BLINK_LIMIT_TERMED && now >= rec->kill_at) {
                blink_limits_signal_locked(rec, SIGKILL);
                rec->stage = BLINK_LIMIT_KILLED;
            }
            if (rec->stage == BLINK_LIMIT_WAITING && rec->deadline < next) next = rec->deadline;
            if (rec->stage == BLINK_LIMIT_TERMED && rec->kill_at < next) next = rec->kill_at;
        }
        pthread_mutex_unlock(&rec->mu);
        at = &rec->next;
    }
#if defined(__linux__)
    blink_cg_left_locked();
#endif
    return next;
}

#if defined(__linux__)
/* struct clone_args of linux/sched.h, version 2 (with cgroup), spelled out so no kernel
 * header is needed. */
struct blink_clone_args {
    uint64_t flags, pidfd, child_tid, parent_tid, exit_signal, stack, stack_size, tls;
    uint64_t set_tid, set_tid_size, cgroup;
};
#define BLINK_CLONE_INTO_CGROUP 0x200000000ULL
#ifdef SYS_clone3
#define BLINK_SYS_CLONE3 SYS_clone3
#else
#define BLINK_SYS_CLONE3 435
#endif
#endif

/* fork, or on Linux with cg_fd >= 0 a clone3 that starts the child in that cgroup, so not
 * one instruction of it runs outside. A kernel with no clone3, or a seccomp filter that
 * refuses it with EPERM (some container runtimes), gets a plain fork, and the child moves
 * itself before it does anything else (see blink_limits_fork_locked). */
static pid_t blink_limits_fork(int cg_fd) {
#if defined(__linux__)
    if (cg_fd >= 0) {
        struct blink_clone_args args;
        memset(&args, 0, sizeof(args));
        args.flags = BLINK_CLONE_INTO_CGROUP;
        args.exit_signal = SIGCHLD;
        args.cgroup = (uint64_t)cg_fd;
        long r = syscall(BLINK_SYS_CLONE3, &args, sizeof(args));
        if (r >= 0 || (errno != ENOSYS && errno != EPERM)) return (pid_t)r;
    }
#else
    (void)cg_fd;
#endif
    return fork();
}

/* Runs on the limits thread with blink_limits.mu held. The child leads a new process group
 * and, on Linux, gets SIGKILL when this thread ends, which is when the program ends. It gets
 * back the signal mask of the thread that asked, since the limits thread blocks signals of
 * its own. A child with memory or processes starts in a cgroup of its own. */
static void blink_limits_fork_locked(blink_limit_req* req) {
    blink_limit_rec* rec = (blink_limit_rec*)calloc(1, sizeof(blink_limit_rec));
    if (rec == NULL) { req->err = ENOMEM; return; }
    pthread_mutex_init(&rec->mu, NULL);
    rec->limit = BLINK_LIMIT_NONE;
    int cg_fd = -1, procs_fd = -1;
#if defined(__linux__)
    if (req->memory >= 0 || req->processes >= 0) {
        int e = blink_cg_child_make(req->memory, req->processes, &rec->cg, &cg_fd, &procs_fd);
        if (e != 0) {
            req->err = e;
            pthread_mutex_destroy(&rec->mu);
            free(rec);
            return;
        }
        rec->cg_memory = req->memory >= 0;
        rec->cg_pids = req->processes >= 0;
    }
#else
    if (req->memory >= 0 || req->processes >= 0) {
        req->err = ENOTSUP;
        pthread_mutex_destroy(&rec->mu);
        free(rec);
        return;
    }
#endif
    pid_t parent = getpid();
    pid_t pid = blink_limits_fork(cg_fd);
    if (pid < 0) {
        req->err = errno;
        if (cg_fd >= 0) close(cg_fd);
        if (procs_fd >= 0) close(procs_fd);
        if (rec->cg != NULL) {
            rmdir(rec->cg);
            free(rec->cg);
        }
        pthread_mutex_destroy(&rec->mu);
        free(rec);
        return;
    }
    if (pid == 0) {
        /* After a clone3 the child is in its cgroup already and this write moves nothing;
         * after the fork of a kernel with no clone3 it is the move. */
        if (procs_fd >= 0) {
            ssize_t w;
            do { w = write(procs_fd, "0", 1); } while (w < 0 && errno == EINTR);
            if (w != 1) {
                int e = w < 0 ? errno : EIO;
                do { w = write(req->report_fd, &e, sizeof(e)); } while (w < 0 && errno == EINTR);
                _exit(127);
            }
        }
        setpgid(0, 0);
#if defined(__linux__)
        prctl(PR_SET_PDEATHSIG, SIGKILL);
        /* The program ended before the prctl took hold, so no death signal will come. */
        if (getppid() != parent) {
            int e = ESRCH;
            ssize_t w;
            do { w = write(req->report_fd, &e, sizeof(e)); } while (w < 0 && errno == EINTR);
            _exit(127);
        }
#else
        (void)parent;
#endif
        pthread_sigmask(SIG_SETMASK, &req->mask, NULL);
        blink_child_exec_or_report(req->argv, req->stdin_fd, req->out_fd, req->err_fd, req->report_fd);
    }
    if (cg_fd >= 0) close(cg_fd);
    if (procs_fd >= 0) close(procs_fd);
    /* Both sides set the group, so it is set before either goes on. EACCES once the child
     * has exec'd is fine: the child set it first. */
    setpgid(pid, pid);
    rec->pid = pid;
    rec->deadline = req->timeout < 0 ? BLINK_LIMIT_NEVER : blink_limits_add(blink_limits_now(), req->timeout);
    rec->grace = req->grace;
    rec->kill_at = BLINK_LIMIT_NEVER;
    rec->stage = BLINK_LIMIT_WAITING;
    rec->next = blink_limits.recs;
    blink_limits.recs = rec;
    req->rec = rec;
}

/* The program-exit rule (§4.4.8 A limited child does not outlive this program): each limited
 * child whose leader is not reaped gets the signals of its deadline now, and the exit waits
 * until its group, and its cgroup when it has one, is gone. Interim choice, the one place
 * for it: SIGTERM, then SIGKILL after the child's own grace (at once for a grace of zero,
 * and no later than a SIGKILL that its deadline already set); all groups at once, so the
 * exit waits at most the longest grace. A
 * zombie leader still counts as a member of its group, so the exit reaps it, keeps its
 * status for a run or wait that comes later, and then waits until no process is left with
 * that pgid; a pgid with a live member cannot pass to another process. A child that a run or
 * wait reaped gets nothing, as after the reap its pid may name another process.
 *
 * Caller holds blink_limits.mu, and holds it to the end, so no fork starts while the exit
 * runs and a second caller waits here until the first is done. This never waits on a fork
 * request: a run or spawn that asks for one after ending was set waits forever, which the
 * exit makes moot, and its wait released blink_limits.mu. Each rec->mu holder only reaps a
 * leader that has exited or got SIGKILL, so each lock below is short. */
static void blink_limits_end_locked(void) {
    if (blink_limits.ending) return;
    blink_limits.ending = 1;
    int64_t now = blink_limits_now();
    for (blink_limit_rec* rec = blink_limits.recs; rec != NULL; rec = rec->next) {
        pthread_mutex_lock(&rec->mu);
        if (!rec->reaped) {
            rec->exit_live = 1;
            if (rec->grace == 0 || rec->stage == BLINK_LIMIT_KILLED) {
                blink_limits_signal_locked(rec, SIGKILL);
                rec->exit_kill_at = BLINK_LIMIT_NEVER;
            } else {
                if (rec->stage != BLINK_LIMIT_TERMED) blink_limits_signal_locked(rec, SIGTERM);
                rec->exit_kill_at = blink_limits_add(now, rec->grace);
                if (rec->stage == BLINK_LIMIT_TERMED && rec->kill_at < rec->exit_kill_at) {
                    rec->exit_kill_at = rec->kill_at;
                }
            }
        }
        pthread_mutex_unlock(&rec->mu);
    }
    for (;;) {
        int live = 0;
        now = blink_limits_now();
        for (blink_limit_rec* rec = blink_limits.recs; rec != NULL; rec = rec->next) {
            pthread_mutex_lock(&rec->mu);
            if (rec->exit_live) {
                if (!rec->reaped && !rec->exit_gone) {
                    int st = 0;
                    pid_t wr = waitpid(rec->pid, &st, WNOHANG);
                    if (wr == rec->pid) {
                        rec->reaped = 1;
                        rec->reaped_at_exit = 1;
                        rec->status = st;
                    } else if (wr < 0 && errno == ECHILD) {
                        /* A parent can start this program with SIGCHLD ignored; then the
                         * leader's reap never comes, and only its group is left to end. */
                        rec->exit_gone = 1;
                    }
                }
                if (rec->reaped_at_exit) {
                    /* When this program is PID 1 or a subreaper, the members that the leader
                     * left are its children, and each zombie keeps the group alive until it
                     * is reaped. Only after the leader's reap, so its status is not lost. */
                    int zst = 0;
                    for (;;) {
                        pid_t zr = waitpid(-rec->pid, &zst, WNOHANG);
                        if (zr > 0 || (zr < 0 && errno == EINTR)) continue;
                        break;
                    }
                }
                int group_gone = (rec->reaped_at_exit || rec->exit_gone) && kill(-rec->pid, 0) < 0 && errno == ESRCH;
                int gone = group_gone;
#if defined(__linux__)
                /* A process that left the group (setsid) is still in the cgroup. A cgroup
                 * that cannot be read counts as empty, so the exit cannot hang on it. */
                if (gone && rec->cg != NULL) gone = blink_cg_count(rec->cg, "cgroup.events", "populated") != 1;
#endif
                if (gone) {
                    rec->exit_live = 0;
                } else if (rec->reaped && !rec->reaped_at_exit) {
                    /* A run or wait reaped it meanwhile. */
                    rec->exit_live = 0;
                } else if (now >= rec->exit_kill_at) {
#if defined(__linux__)
                    if (rec->cg != NULL) blink_cg_kill(rec);
#endif
                    /* A group with no member left may pass its pgid to another process. */
                    if (!group_gone) kill(-rec->pid, SIGKILL);
                    rec->exit_kill_at = BLINK_LIMIT_NEVER;
                }
                live |= rec->exit_live;
            }
            pthread_mutex_unlock(&rec->mu);
        }
        if (!live) return;
        struct timespec ts = { 0, 10 * 1000000L };
        nanosleep(&ts, NULL);
    }
}

/* A SIGINT or SIGTERM came while the limits thread ran: the limited children are ended, so
 * the program now ends by that signal, as it would have with no handler. */
static void blink_limits_reraise(int sig) {
    /* Never let go: a run that starts or ends meanwhile would set a handler again, and the
     * raise would then return and end the program with an exit code, not by the signal. */
    pthread_mutex_lock(&blink_sigint_mu);
    struct sigaction dfl;
    memset(&dfl, 0, sizeof(dfl));
    dfl.sa_handler = SIG_DFL;
    sigaction(sig, &dfl, NULL);
    sigset_t one;
    sigemptyset(&one);
    sigaddset(&one, sig);
    pthread_sigmask(SIG_UNBLOCK, &one, NULL);
    raise(sig);
    _exit(128 + sig);
}

static void blink_limits_at_exit(void) {
    pthread_mutex_lock(&blink_limits.mu);
    blink_limits_end_locked();
#if defined(__linux__)
    /* The tick that removes the cgroup of a released record, or of a left one, may not come
     * before the program ends. The record stays: no thread frees it from here on. */
    for (blink_limit_rec* rec = blink_limits.recs; rec != NULL; rec = rec->next) {
        pthread_mutex_lock(&rec->mu);
        if (rec->released) blink_cg_release_locked(rec);
        pthread_mutex_unlock(&rec->mu);
    }
    blink_cg_left_locked();
#endif
    int sig = blink_limits.pending_sig;
    if (sig != 0) blink_limits_reraise(sig);
    pthread_mutex_unlock(&blink_limits.mu);
}

/* Async-signal-safe: the limits thread does the work, as the handler can take no lock. */
static void blink_limits_on_signal(int sig) {
    blink_limits.pending_sig = sig;
    blink_limits_wake();
}

static void* blink_limits_main(void* arg) {
    (void)arg;
    pthread_mutex_lock(&blink_limits.mu);
    for (;;) {
        int sig = blink_limits.pending_sig;
        if (sig != 0) {
            blink_limits_end_locked();
            blink_limits_reraise(sig);
        }
        int served = 0;
        while (!blink_limits.ending && blink_limits.reqs != NULL) {
            blink_limit_req* req = blink_limits.reqs;
            blink_limits.reqs = req->next;
            blink_limits_fork_locked(req);
            req->done = 1;
            served = 1;
        }
        if (served) pthread_cond_broadcast(&blink_limits.served);
        int64_t next = blink_limits_tick_locked(blink_limits_now());
        struct pollfd pfds[2];
        nfds_t nfds = 1;
        pfds[0].fd = blink_limits.wake_rd;
        pfds[0].events = POLLIN;
        pfds[0].revents = 0;
#if defined(__linux__)
        /* An event of a child cgroup: the next pass reads the event files of each. */
        if (blink_cg.ino_fd >= 0) {
            pfds[1].fd = blink_cg.ino_fd;
            pfds[1].events = POLLIN;
            pfds[1].revents = 0;
            nfds = 2;
        }
#endif
        pthread_mutex_unlock(&blink_limits.mu);
        /* EINTR (the collector stops this thread with a signal) or an early wake just
         * means one more pass. */
        poll(pfds, nfds, blink_limits_poll_ms(next == BLINK_LIMIT_NEVER ? -1 : next));
        char drain[4096];
        for (nfds_t i = 0; i < nfds; i++) {
            while (read(pfds[i].fd, drain, sizeof(drain)) > 0) {}
        }
        pthread_mutex_lock(&blink_limits.mu);
    }
    return NULL;
}

/* Caller holds blink_limits.mu. 0 once the thread runs, else the errno that kept it from
 * starting; a later limited run or spawn tries again. The thread blocks the signals that
 * the program means for its main thread, so that this thread never runs their handlers. */
static int blink_limits_start_locked(void) {
    if (blink_limits.started) return 0;
    int wake[2] = {-1, -1};
    if (blink_child_pipe(wake) < 0) return errno;
    for (int i = 0; i < 2; i++) {
        int fl = fcntl(wake[i], F_GETFL);
        if (fl >= 0) fcntl(wake[i], F_SETFL, fl | O_NONBLOCK);
    }
    blink_limits.wake_rd = wake[0];
    blink_limits.wake_wr = wake[1];
#ifdef BLINK_DEV_LIMITS_THREAD_FAIL
    /* Dev knob: cc -DBLINK_DEV_LIMITS_THREAD_FAIL fails every start of the thread as a full
     * thread table would, so a test can see run and spawn report it. */
    int e = EAGAIN;
#else
    sigset_t block, old;
    sigemptyset(&block);
    sigaddset(&block, SIGINT);
    sigaddset(&block, SIGTERM);
    sigaddset(&block, SIGHUP);
    sigaddset(&block, SIGPIPE);
    sigaddset(&block, SIGCHLD);
    pthread_sigmask(SIG_BLOCK, &block, &old);
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t t;
    int e = pthread_create(&t, &attr, blink_limits_main, NULL);
    pthread_attr_destroy(&attr);
    pthread_sigmask(SIG_SETMASK, &old, NULL);
#endif
    if (e != 0) {
        blink_limits.wake_rd = -1;
        blink_limits.wake_wr = -1;
        blink_child_close_pair(wake);
        return e;
    }
    blink_limits.started = 1;
    atexit(blink_limits_at_exit);
    /* A program that set its own action for a signal keeps it. blink_process_forward_signal
     * hands the signal on to this thread itself. */
    blink_signal_set_if_default(SIGINT, blink_limits_on_signal);
    blink_signal_set_if_default(SIGTERM, blink_limits_on_signal);
    return 0;
}

/* Forks a limited child on the given pipes through the limits thread. 0 with *rec_out set
 * once the child has exec'd, else the errno of the thread start, the fork or the exec; a
 * child whose exec failed is reaped here. */
static int blink_limits_fork_exec(char** argv, int stdin_fd, int out_fd, int err_fd, int64_t timeout,
                                  int64_t grace, int64_t memory, int64_t processes, blink_limit_rec** rec_out) {
    int report[2] = {-1, -1};
    if (blink_child_pipe(report) < 0) return errno;
    blink_limit_req req;
    memset(&req, 0, sizeof(req));
    req.argv = argv;
    req.stdin_fd = stdin_fd;
    req.out_fd = out_fd;
    req.err_fd = err_fd;
    req.report_fd = report[1];
    req.timeout = timeout;
    req.grace = grace;
    req.memory = memory;
    req.processes = processes;
    pthread_sigmask(SIG_SETMASK, NULL, &req.mask);
    pthread_mutex_lock(&blink_limits.mu);
    int e = blink_limits_start_locked();
    if (e != 0) {
        pthread_mutex_unlock(&blink_limits.mu);
        blink_child_close_pair(report);
        return e;
    }
    blink_limit_req** tail = &blink_limits.reqs;
    while (*tail != NULL) tail = &(*tail)->next;
    *tail = &req;
    blink_limits_wake();
    while (!req.done) pthread_cond_wait(&blink_limits.served, &blink_limits.mu);
    pthread_mutex_unlock(&blink_limits.mu);
    close(report[1]);
    if (req.err != 0) {
        close(report[0]);
        return req.err;
    }
    blink_limit_rec* rec = req.rec;
    e = blink_child_read_report(report[0]);
    if (e != 0) {
        /* As in blink_child_fork_exec: the op reports Err, so whatever did exec must not
         * run on. */
        pthread_mutex_lock(&rec->mu);
        kill(-rec->pid, SIGKILL);
        int status;
        while (waitpid(rec->pid, &status, 0) < 0 && errno == EINTR) {}
        rec->reaped = 1;
        rec->released = 1;
        pthread_mutex_unlock(&rec->mu);
        blink_limits_wake();
        return e;
    }
    *rec_out = rec;
    return 0;
}

/* Reaps a limited child that a wait has left a zombie, and gives the errno of the reap,
 * its status, and the limit that ended it (BLINK_LIMIT_NONE for none). The record is
 * released: the caller does not use it again. Caller holds no limits lock; wait_err is the
 * errno of that wait. */
static int blink_limits_reap(blink_limit_rec* rec, int wait_err, int* status, int* limit) {
    pthread_mutex_lock(&rec->mu);
    int e = wait_err;
    if (rec->reaped_at_exit) {
        e = 0;
        *status = rec->status;
    } else if (e == 0) {
        e = blink_child_waitpid(rec->pid, status);
    }
#if defined(__linux__)
    /* The limits thread may not have read the memory events yet when the kill reaches the
     * leader first. */
    if (e == 0 && rec->limit == BLINK_LIMIT_NONE && rec->cg != NULL && WIFSIGNALED(*status)
        && WTERMSIG(*status) == SIGKILL && blink_cg_memory_hit(rec)) {
        rec->limit = blink_LimitKind_Memory;
    }
#endif
    rec->reaped = 1;
    *limit = rec->limit;
    rec->released = 1;
    pthread_mutex_unlock(&rec->mu);
    blink_limits_wake();
    return e;
}

/* Waits until the leader of a limited child has exited and leaves it a zombie. The reap
 * then comes under rec->mu; a wait that blocked there would keep the thread from sending
 * the signal it waits for. */
static int blink_limits_wait_exit(pid_t pid) {
    siginfo_t info;
    while (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOWAIT) < 0) {
        if (errno != EINTR) return errno;
    }
    return 0;
}

static void blink_child_box_set_end(blink_child_box* box, int status, int limit) {
    if (limit != BLINK_LIMIT_NONE) {
        box->result.end = blink_child_end_limit((blink_LimitKind)limit);
    } else {
        blink_process_result_set_status(&box->result, status);
    }
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
                     out_pipe[0], err_pipe[0], &out, &err, -1);
    /* As blink_process_run_with_stdin: a Ctrl-C while the child runs reaches it, and the
     * parent takes it once the child is reaped. */
    blink_child_pid = pid;
    blink_got_sigint = 0;
    blink_sigint_enter();
    int status = 0;
    int we = blink_child_waitpid(pid, &status);
    blink_sigint_leave();
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

/* process.run with limits: timeout_ns, memory and processes < 0 are no such limit, and
 * with none it is blink_child_run. The limits thread forks the child, which leads its own
 * process group. Until the deadline the run waits for end of file as blink_child_run does;
 * from then on it reads the pipes until timeout + grace + a short delay at most. A Ctrl-C
 * does not reach the child's group from the terminal; the program-exit rule ends it. */
BLINK_RT_FN blink_child_box* blink_child_run_limited2(const char* cmd, const blink_list* args, int64_t has_stdin,
                                                      const char* stdin_data, int64_t timeout_ns, int64_t grace_ns,
                                                      int64_t memory, int64_t processes);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_child_box* blink_child_run_limited2(const char* cmd, const blink_list* args, int64_t has_stdin,
                                                      const char* stdin_data, int64_t timeout_ns, int64_t grace_ns,
                                                      int64_t memory, int64_t processes) {
    if (timeout_ns < 0 && memory < 0 && processes < 0) return blink_child_run(cmd, args, has_stdin, stdin_data);
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
    blink_limit_rec* rec = NULL;
    int e = blink_limits_fork_exec(argv, in_pipe[0], out_pipe[1], err_pipe[1], timeout_ns, grace_ns, memory,
                                   processes, &rec);
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
                     out_pipe[0], err_pipe[0], &out, &err, blink_limits_stop_at(rec));
    int status = 0;
    int limit = BLINK_LIMIT_NONE;
    int we = blink_limits_reap(rec, blink_limits_wait_exit(rec->pid), &status, &limit);
    if (we != 0) {
        box->err = we;
    } else {
        box->result.out = out;
        box->result.err_out = err;
        blink_child_box_set_end(box, status, limit);
        box->waited = 1;
    }
    return box;
}
#endif

/* process.spawn with limits: < 0 is no such limit, and with none it is blink_child_spawn.
 * As blink_child_run_limited2, the limits thread forks the child; the box keeps its limit
 * record for the wait. */
BLINK_RT_FN blink_child_box* blink_child_spawn_limited2(const char* cmd, const blink_list* args, int64_t timeout_ns,
                                                        int64_t grace_ns, int64_t memory, int64_t processes);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_child_box* blink_child_spawn_limited2(const char* cmd, const blink_list* args, int64_t timeout_ns,
                                                        int64_t grace_ns, int64_t memory, int64_t processes) {
    if (timeout_ns < 0 && memory < 0 && processes < 0) return blink_child_spawn(cmd, args);
    blink_child_box* box = blink_child_box_new(cmd);
    if (!blink_child_strings_ok(cmd, args)) { box->err = EINVAL; return box; }
    char** argv = blink_process_build_argv(cmd, args);
    int64_t h = blink_pid_table_alloc();
    if (h < 0) { box->err = EAGAIN; return box; }
    blink_pid_slot* slot = &blink_pid_table[h % BLINK_PID_TABLE_CAP];
    int out_pipe[2] = {-1, -1}, err_pipe[2] = {-1, -1};
    int e = 0;
    blink_limit_rec* rec = NULL;
    if (blink_child_pipe(out_pipe) < 0 || blink_child_pipe(err_pipe) < 0) {
        e = errno;
        blink_child_close_pair(out_pipe);
        blink_child_close_pair(err_pipe);
    } else {
        e = blink_limits_fork_exec(argv, -1, out_pipe[1], err_pipe[1], timeout_ns, grace_ns, memory, processes, &rec);
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
    slot->pid = rec->pid;
    slot->limited = 1;
    slot->out_fd = out_pipe[0];
    slot->err_fd = err_pipe[0];
    pthread_mutex_unlock(&blink_pid_table_mu);
    box->lim = rec;
    box->handle = h;
    return box;
}
#endif

/* The timeout-only entry points, which a std built before memory and processes calls. */
BLINK_RT_FN blink_child_box* blink_child_run_limited(const char* cmd, const blink_list* args, int64_t has_stdin,
                                                     const char* stdin_data, int64_t timeout_ns, int64_t grace_ns);
BLINK_RT_FN blink_child_box* blink_child_spawn_limited(const char* cmd, const blink_list* args, int64_t timeout_ns,
                                                       int64_t grace_ns);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_child_box* blink_child_run_limited(const char* cmd, const blink_list* args, int64_t has_stdin,
                                                     const char* stdin_data, int64_t timeout_ns, int64_t grace_ns) {
    return blink_child_run_limited2(cmd, args, has_stdin, stdin_data, timeout_ns, grace_ns, -1, -1);
}

BLINK_RT_FN blink_child_box* blink_child_spawn_limited(const char* cmd, const blink_list* args, int64_t timeout_ns,
                                                       int64_t grace_ns) {
    return blink_child_spawn_limited2(cmd, args, timeout_ns, grace_ns, -1, -1);
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
    blink_child_pump(-1, NULL, 0, slot->out_fd, slot->err_fd, &out, &err, blink_limits_stop_at(box->lim));
    slot->out_fd = -1;
    slot->err_fd = -1;
    int e = 0;
    siginfo_t info;
    while (waitid(P_PID, (id_t)slot->pid, &info, WEXITED | WNOWAIT) < 0) {
        if (errno != EINTR) { e = errno; break; }
    }
    int status = 0;
    int limit = BLINK_LIMIT_NONE;
    pthread_mutex_lock(&blink_pid_table_mu);
    if (box->lim != NULL) {
        e = blink_limits_reap(box->lim, e, &status, &limit);
        box->lim = NULL;
    } else if (e == 0) {
        e = blink_child_waitpid(slot->pid, &status);
    }
    slot->reaped = 1;
    slot->cached = blink_process_result_none(BLINK_STR_EMPTY);
    blink_pid_slot_free_locked(slot);
    pthread_mutex_unlock(&blink_pid_table_mu);
    if (e == 0) {
        box->result.out = out;
        box->result.err_out = err;
        blink_child_box_set_end(box, status, limit);
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
        /* The exit path reaps a limited leader under rec->mu alone. */
        blink_limit_rec* rec = box->lim;
        if (rec != NULL) pthread_mutex_lock(&rec->mu);
        if (rec == NULL || !rec->reaped) e = kill(slot->pid, (int)sig) == 0 ? 0 : errno;
        if (rec != NULL) pthread_mutex_unlock(&rec->mu);
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
    case blink_ChildEnd_Limit_TAG: return (int64_t)box->result.end.data.Limit._0;
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
        /* The limits thread ends a limited child's group, and the exit path may have reaped
         * its leader already, so the pid could name another process. */
        if (!slot->reaped && !slot->limited && slot->pid > 0) {
            kill(slot->pid, SIGTERM);
        }
    }
    /* With limited children the limits thread ends them first and then re-raises. */
    if (blink_limits.started) {
        blink_limits_on_signal(sig);
        return;
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
 * two never disagree. memory and processes need a delegated cgroup v2 (blink_cg_check),
 * checked once. The timeout needs only the limits thread, which a POSIX host can always
 * start; when it cannot, run and spawn give that errno. */
BLINK_RT_FN int64_t blink_child_limit_supported(int64_t kind);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_child_limit_supported(int64_t kind) {
    if (kind == blink_LimitKind_Timeout) return 1;
#if defined(__linux__)
    if (kind == blink_LimitKind_Memory || kind == blink_LimitKind_Processes) return blink_cg_supported((int)kind);
#endif
    return 0;
}
#endif

#endif
