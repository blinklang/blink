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
    int64_t capacity;
    int64_t head;
    int64_t tail;
    int64_t count;
    int closed;
    pthread_mutex_t mutex;
    pthread_cond_t send_cond;
    pthread_cond_t recv_cond;
} blink_channel;

BLINK_UNUSED static void* blink_threadpool_worker(void* arg) {
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

BLINK_UNUSED static blink_threadpool* blink_threadpool_init(int thread_count) {
    if (thread_count <= 0) {
        thread_count = 4;
    }
    blink_threadpool* pool = (blink_threadpool*)blink_alloc(sizeof(blink_threadpool));
    pool->thread_count = thread_count;
    pool->queue_head = NULL;
    pool->queue_tail = NULL;
    pool->shutdown = 0;
    pthread_mutex_init(&pool->mutex, NULL);
    pthread_cond_init(&pool->cond, NULL);
    pool->threads = (pthread_t*)blink_alloc(sizeof(pthread_t) * thread_count);
    for (int i = 0; i < thread_count; i++) {
        pthread_create(&pool->threads[i], NULL, blink_threadpool_worker, pool);
    }
    return pool;
}

BLINK_UNUSED static void blink_threadpool_submit(blink_threadpool* pool, void (*fn)(void*), void* arg) {
    blink_task* task = (blink_task*)blink_alloc(sizeof(blink_task));
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

BLINK_UNUSED static void blink_threadpool_shutdown(blink_threadpool* pool) {
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

/* ── Handle operations ──────────────────────────────────────────────── */

BLINK_UNUSED static blink_handle* blink_handle_new(void) {
    blink_handle* h = (blink_handle*)blink_alloc(sizeof(blink_handle));
    memset(&h->thread, 0, sizeof(pthread_t));
    h->result = NULL;
    h->status = BLINK_HANDLE_RUNNING;
    pthread_mutex_init(&h->mutex, NULL);
    pthread_cond_init(&h->cond, NULL);
    return h;
}

BLINK_UNUSED static void blink_handle_set_result(blink_handle* h, void* result) {
    pthread_mutex_lock(&h->mutex);
    h->result = result;
    h->status = BLINK_HANDLE_DONE;
    pthread_cond_broadcast(&h->cond);
    pthread_mutex_unlock(&h->mutex);
}

BLINK_UNUSED static void* blink_handle_await(blink_handle* h) {
    pthread_mutex_lock(&h->mutex);
    while (h->status == BLINK_HANDLE_RUNNING) {
        pthread_cond_wait(&h->cond, &h->mutex);
    }
    void* result = h->result;
    pthread_mutex_unlock(&h->mutex);
    return result;
}

/* ── Channel operations ─────────────────────────────────────────────── */

BLINK_UNUSED static blink_channel* blink_channel_new(int64_t capacity) {
    if (capacity <= 0) capacity = 16;
    blink_channel* ch = (blink_channel*)blink_alloc(sizeof(blink_channel));
    ch->buffer = (void**)blink_alloc(sizeof(void*) * (size_t)capacity);
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

BLINK_UNUSED static int blink_channel_send(blink_channel* ch, void* value) {
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

BLINK_UNUSED static void* blink_channel_recv(blink_channel* ch) {
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

BLINK_UNUSED static void blink_channel_close(blink_channel* ch) {
    pthread_mutex_lock(&ch->mutex);
    ch->closed = 1;
    pthread_cond_broadcast(&ch->send_cond);
    pthread_cond_broadcast(&ch->recv_cond);
    pthread_mutex_unlock(&ch->mutex);
}

#endif
