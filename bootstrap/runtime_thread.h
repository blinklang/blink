#ifndef BLINK_RUNTIME_THREAD_H
#define BLINK_RUNTIME_THREAD_H

#include <pthread.h>

/* ── Task queue for thread pool ─────────────────────────────────────── */

typedef struct blink_task {
    void (*fn)(void*);
    void* arg;
    struct blink_task* next;
} blink_task;

typedef struct {
    pthread_t* threads;
    int thread_count;
    blink_task* queue_head;
    blink_task* queue_tail;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int shutdown;
} blink_threadpool;

/* ── Handle[T]: async result ────────────────────────────────────────── */

#define BLINK_HANDLE_RUNNING  0
#define BLINK_HANDLE_DONE     1

typedef struct {
    pthread_t thread;
    void* result;
    int status;
    pthread_mutex_t mutex;
    pthread_cond_t cond;
} blink_handle;

/* ── Channel[T]: bounded ring buffer for send/recv ──────────────────── */

typedef struct {
    void** buffer;
    /* The sized entry points keep each element inline here, elem_size bytes a slot, so
       "closed and empty" travels in recv's return value and no bit pattern of an element
       can be read as it. */
    char* slots;
    int64_t elem_size;
    int64_t capacity;
    int64_t head;
    int64_t tail;
    int64_t count;
    int closed;
    pthread_mutex_t mutex;
    pthread_cond_t send_cond;
    pthread_cond_t recv_cond;
} blink_channel;

BLINK_RT_FN void* blink_threadpool_worker(void* arg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_threadpool_worker(void* arg) {
    blink_threadpool* pool = (blink_threadpool*)arg;
    while (1) {
        pthread_mutex_lock(&pool->mutex);
        while (!pool->queue_head && !pool->shutdown) {
            pthread_cond_wait(&pool->cond, &pool->mutex);
        }
        if (pool->shutdown && !pool->queue_head) {
            pthread_mutex_unlock(&pool->mutex);
            break;
        }
        blink_task* task = pool->queue_head;
        pool->queue_head = task->next;
        if (!pool->queue_head) {
            pool->queue_tail = NULL;
        }
        pthread_mutex_unlock(&pool->mutex);
        task->fn(task->arg);
        GC_FREE(task);
    }
    return NULL;
}
#endif

BLINK_RT_FN blink_threadpool* blink_threadpool_init(int thread_count);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_threadpool* blink_threadpool_init(int thread_count) {
    if (thread_count <= 0) {
        thread_count = 4;
    }
    blink_threadpool* pool = (blink_threadpool*)blink_alloc_shared(sizeof(blink_threadpool));
    pool->thread_count = thread_count;
    pool->queue_head = NULL;
    pool->queue_tail = NULL;
    pool->shutdown = 0;
    pthread_mutex_init(&pool->mutex, NULL);
    pthread_cond_init(&pool->cond, NULL);
    pool->threads = (pthread_t*)blink_alloc_shared(sizeof(pthread_t) * thread_count);
    for (int i = 0; i < thread_count; i++) {
        pthread_create(&pool->threads[i], NULL, blink_threadpool_worker, pool);
    }
    return pool;
}
#endif

BLINK_RT_FN void blink_threadpool_submit(blink_threadpool* pool, void (*fn)(void*), void* arg);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_threadpool_submit(blink_threadpool* pool, void (*fn)(void*), void* arg) {
    blink_task* task = (blink_task*)blink_alloc_shared(sizeof(blink_task));
    task->fn = fn;
    task->arg = arg;
    task->next = NULL;
    pthread_mutex_lock(&pool->mutex);
    if (pool->queue_tail) {
        pool->queue_tail->next = task;
    } else {
        pool->queue_head = task;
    }
    pool->queue_tail = task;
    pthread_cond_signal(&pool->cond);
    pthread_mutex_unlock(&pool->mutex);
}
#endif

BLINK_RT_FN void blink_threadpool_shutdown(blink_threadpool* pool);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_threadpool_shutdown(blink_threadpool* pool) {
    pthread_mutex_lock(&pool->mutex);
    pool->shutdown = 1;
    pthread_cond_broadcast(&pool->cond);
    pthread_mutex_unlock(&pool->mutex);
    for (int i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }
    pthread_mutex_destroy(&pool->mutex);
    pthread_cond_destroy(&pool->cond);
    GC_FREE(pool->threads);
    GC_FREE(pool);
}
#endif

/* ── Program's one thread pool ──────────────────────────────────────────
   The pool async.spawn submits through. One instance per process: the main
   shim starts it before the program runs and shuts it down after, and
   every spawn site and task wrapper reads this same symbol. */
#ifdef BLINK_USE_EXTERN_RUNTIME_STORAGE
  #ifdef BLINK_RUNTIME_STORAGE_DEFINE
    blink_threadpool* __blink_pool = NULL;
  #else
    extern blink_threadpool* __blink_pool;
  #endif
#else
BLINK_UNUSED static blink_threadpool* __blink_pool = NULL;
#endif

/* ── Handle operations ──────────────────────────────────────────────── */

BLINK_RT_FN blink_handle* blink_handle_new(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_handle* blink_handle_new(void) {
    blink_handle* h = (blink_handle*)blink_alloc_shared(sizeof(blink_handle));
    memset(&h->thread, 0, sizeof(pthread_t));
    h->result = NULL;
    h->status = BLINK_HANDLE_RUNNING;
    pthread_mutex_init(&h->mutex, NULL);
    pthread_cond_init(&h->cond, NULL);
    return h;
}
#endif

BLINK_RT_FN void blink_handle_set_result(blink_handle* h, void* result);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_handle_set_result(blink_handle* h, void* result) {
    pthread_mutex_lock(&h->mutex);
    h->result = result;
    h->status = BLINK_HANDLE_DONE;
    pthread_cond_broadcast(&h->cond);
    pthread_mutex_unlock(&h->mutex);
}
#endif

BLINK_RT_FN void* blink_handle_await(blink_handle* h);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_handle_await(blink_handle* h) {
    pthread_mutex_lock(&h->mutex);
    while (h->status == BLINK_HANDLE_RUNNING) {
        pthread_cond_wait(&h->cond, &h->mutex);
    }
    void* result = h->result;
    pthread_mutex_unlock(&h->mutex);
    return result;
}
#endif

/* ── async.scope exit ───────────────────────────────────────────────── */

/* An async.scope's own handle list, awaited and freed at scope exit: every handle still
 * BLINK_HANDLE_RUNNING is joined, so no spawned task outlives its scope. Handles already
 * done are read straight through by their own .await; awaiting them again is harmless. */
BLINK_RT_FN void blink_async_scope_drain(blink_list* handles);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_async_scope_drain(blink_list* handles) {
    int64_t n = blink_list_len(handles);
    for (int64_t i = 0; i < n; i++) {
        blink_handle* h = (blink_handle*)blink_list_get(handles, i);
        if (h->status == BLINK_HANDLE_RUNNING) {
            blink_handle_await(h);
        }
    }
    blink_list_free(handles);
}
#endif

/* ── Channel operations ─────────────────────────────────────────────── */

BLINK_RT_FN blink_channel* blink_channel_new(int64_t capacity);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_channel* blink_channel_new(int64_t capacity) {
    if (capacity <= 0) capacity = 16;
    blink_channel* ch = (blink_channel*)blink_alloc_shared(sizeof(blink_channel));
    ch->buffer = (void**)blink_alloc_shared(sizeof(void*) * (size_t)capacity);
    ch->capacity = capacity;
    ch->head = 0;
    ch->tail = 0;
    ch->count = 0;
    ch->closed = 0;
    pthread_mutex_init(&ch->mutex, NULL);
    pthread_cond_init(&ch->send_cond, NULL);
    pthread_cond_init(&ch->recv_cond, NULL);
    return ch;
}
#endif

BLINK_RT_FN int blink_channel_send(blink_channel* ch, void* value);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_channel_send(blink_channel* ch, void* value) {
    pthread_mutex_lock(&ch->mutex);
    while (ch->count >= ch->capacity && !ch->closed) {
        pthread_cond_wait(&ch->send_cond, &ch->mutex);
    }
    if (ch->closed) {
        pthread_mutex_unlock(&ch->mutex);
        return -1;
    }
    ch->buffer[ch->tail] = value;
    ch->tail = (ch->tail + 1) % ch->capacity;
    ch->count++;
    pthread_cond_signal(&ch->recv_cond);
    pthread_mutex_unlock(&ch->mutex);
    return 0;
}
#endif

BLINK_RT_FN void* blink_channel_recv(blink_channel* ch);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_channel_recv(blink_channel* ch) {
    pthread_mutex_lock(&ch->mutex);
    while (ch->count == 0 && !ch->closed) {
        pthread_cond_wait(&ch->recv_cond, &ch->mutex);
    }
    if (ch->count == 0 && ch->closed) {
        pthread_mutex_unlock(&ch->mutex);
        return NULL;
    }
    void* value = ch->buffer[ch->head];
    ch->head = (ch->head + 1) % ch->capacity;
    ch->count--;
    pthread_cond_signal(&ch->send_cond);
    pthread_mutex_unlock(&ch->mutex);
    return value;
}
#endif

/* The word entry points above are what a compiler built before the sized ones emits;
   they stay until gen0 emits only the sized ones. */

BLINK_RT_FN blink_channel* blink_channel_new_sized(int64_t capacity, int64_t elem_size);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_channel* blink_channel_new_sized(int64_t capacity, int64_t elem_size) {
    blink_channel* ch = blink_channel_new(capacity);
    ch->elem_size = elem_size;
    /* A zero-sized element still needs a nonzero allocation to stay a valid ring. */
    int64_t slot = elem_size > 0 ? elem_size : 1;
    ch->slots = (char*)blink_alloc_shared(slot * ch->capacity);
    return ch;
}
#endif

/* A send on a closed channel is a bug in the program, so it panics with the text codegen
   wrote at the call site, which names the send's source location. */
BLINK_RT_FN void blink_channel_send_value(blink_channel* ch, const void* value, const char* closed_panic);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_channel_send_value(blink_channel* ch, const void* value, const char* closed_panic) {
    pthread_mutex_lock(&ch->mutex);
    while (ch->count >= ch->capacity && !ch->closed) {
        pthread_cond_wait(&ch->send_cond, &ch->mutex);
    }
    if (ch->closed) {
        pthread_mutex_unlock(&ch->mutex);
        __blink_panic_dispatch(closed_panic);
        return;
    }
    if (ch->elem_size > 0) memcpy(ch->slots + ch->tail * ch->elem_size, value, (size_t)ch->elem_size);
    ch->tail = (ch->tail + 1) % ch->capacity;
    ch->count++;
    pthread_cond_signal(&ch->recv_cond);
    pthread_mutex_unlock(&ch->mutex);
}
#endif

/* 0 only when the channel is closed and drained; otherwise 1, with the next element copied
   to out. */
BLINK_RT_FN int blink_channel_recv_value(blink_channel* ch, void* out);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int blink_channel_recv_value(blink_channel* ch, void* out) {
    pthread_mutex_lock(&ch->mutex);
    while (ch->count == 0 && !ch->closed) {
        pthread_cond_wait(&ch->recv_cond, &ch->mutex);
    }
    if (ch->count == 0) {
        pthread_mutex_unlock(&ch->mutex);
        return 0;
    }
    if (ch->elem_size > 0) memcpy(out, ch->slots + ch->head * ch->elem_size, (size_t)ch->elem_size);
    ch->head = (ch->head + 1) % ch->capacity;
    ch->count--;
    pthread_cond_signal(&ch->send_cond);
    pthread_mutex_unlock(&ch->mutex);
    return 1;
}
#endif

/* A second close does nothing: closed is already set and every waiter already woken. */
BLINK_RT_FN void blink_channel_close(blink_channel* ch);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void blink_channel_close(blink_channel* ch) {
    pthread_mutex_lock(&ch->mutex);
    ch->closed = 1;
    pthread_cond_broadcast(&ch->send_cond);
    pthread_cond_broadcast(&ch->recv_cond);
    pthread_mutex_unlock(&ch->mutex);
}
#endif

#endif
