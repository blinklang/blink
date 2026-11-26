#ifndef BLINK_RUNTIME_SQLITE_H
#define BLINK_RUNTIME_SQLITE_H

#ifdef BLINK_USE_SQLITE
#include <sqlite3.h>

/* The stdlib archive leaves out sqlite's modules, so no archive holds these shims and the
 * program defines them itself. A program links exactly one copy: the entry unit defines
 * them, and every other unit of a per-module build reads only the prototypes. */

/* Blink holds a pointer to one of these boxes, never the bare sqlite3* or sqlite3_stmt*.
 * Close and finalize clear the field and leave the GC-owned box alive, so every copy of a
 * handle sees the closed state and no shim reaches freed sqlite memory. */
typedef struct blink_sqlite3_stmt blink_sqlite3_stmt;

/* open lists every statement of the connection that is not finalized yet, so close can
 * finalize them all (sections/04_effects.md §4.4.10, *Release*). A Stmt can reach a
 * spawned task, so mu guards db and the list: the sqlite db mutex cannot, as close frees
 * it. mu lives as long as the box and is never destroyed. */
typedef struct {
    sqlite3* db;           /* NULL once closed */
    pthread_mutex_t mu;
    blink_sqlite3_stmt* open;
} blink_sqlite3_conn;

struct blink_sqlite3_stmt {
    sqlite3_stmt* stmt;    /* NULL once finalized */
    blink_sqlite3_conn* conn;
    blink_sqlite3_stmt* prev_open;
    blink_sqlite3_stmt* next_open;
};

static inline sqlite3* blink_sqlite3_conn_db(blink_sqlite3_conn* c) {
    return c ? c->db : NULL;
}

/* A statement of a closed connection is refused too: sqlite3_close_v2 leaves the database
 * a zombie that only finalize may touch. */
static inline sqlite3_stmt* blink_sqlite3_live_stmt(blink_sqlite3_stmt* s) {
    if (!s || !s->stmt || !blink_sqlite3_conn_db(s->conn)) return NULL;
    return s->stmt;
}

/* Takes s off the open list of c. The caller holds c->mu. */
static inline void blink_sqlite3_unlink_locked(blink_sqlite3_conn* c, blink_sqlite3_stmt* s) {
    if (s->prev_open) s->prev_open->next_open = s->next_open;
    else if (c->open == s) c->open = s->next_open;
    if (s->next_open) s->next_open->prev_open = s->prev_open;
    s->prev_open = NULL;
    s->next_open = NULL;
}

/* Result struct for blink_sqlite3_query convenience wrapper */
typedef struct {
    blink_list* rows;      /* List of blink_list* (each row is a list of strings) */
    blink_list* columns;   /* List of column name strings */
    int64_t num_rows;
    int64_t num_cols;
    int64_t rc;            /* sqlite3 return code (0 = SQLITE_OK) */
} blink_sqlite3_result;

BLINK_RT_FN blink_sqlite3_conn* blink_sqlite3_open(const char* path);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN blink_sqlite3_conn* blink_sqlite3_open(const char* path) {
    sqlite3* db = NULL;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    /* The boxes outlive any `with arena` they were made in, as the handler keeps them. */
    blink_sqlite3_conn* c = (blink_sqlite3_conn*)blink_alloc_shared(sizeof(blink_sqlite3_conn));
    c->db = db;
    pthread_mutex_init(&c->mu, NULL);
    c->open = NULL;
    return c;
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_exec(blink_sqlite3_conn* c, const char* sql,
                                  int (*callback)(void*, int, char**, char**),
                                  void* arg, const char** errmsg);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_exec(blink_sqlite3_conn* c, const char* sql,
                                  int (*callback)(void*, int, char**, char**),
                                  void* arg, const char** errmsg) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) {
        if (errmsg) *errmsg = blink_str_from_cstr_gc("connection is closed");
        return SQLITE_MISUSE;
    }
    char* err = NULL;
    int rc = sqlite3_exec(db, sql, callback, arg, &err);
    if (errmsg) {
        *errmsg = err ? blink_str_from_cstr_gc(err) : NULL;
    }
    if (err) sqlite3_free(err);
    return (int64_t)rc;
}
#endif

BLINK_RT_FN int blink_sqlite3_query_cb(void* ud, int ncols, char** values, char** names);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int blink_sqlite3_query_cb(void* ud, int ncols, char** values, char** names) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)ud;
    if (res->num_rows == 0) {
        for (int i = 0; i < ncols; i++) {
            blink_list_push(res->columns, (void*)blink_str_from_cstr_gc(names[i]));
        }
        res->num_cols = (int64_t)ncols;
    }
    blink_list* row = blink_list_new();
    for (int i = 0; i < ncols; i++) {
        blink_list_push(row, (void*)blink_str_from_cstr_gc(values[i] ? values[i] : ""));
    }
    blink_list_push(res->rows, (void*)row);
    res->num_rows++;
    return 0;
}
#endif

BLINK_RT_FN blink_sqlite3_result* blink_sqlite3_query(blink_sqlite3_conn* c, const char* sql);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN blink_sqlite3_result* blink_sqlite3_query(blink_sqlite3_conn* c, const char* sql) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)blink_alloc(sizeof(blink_sqlite3_result));
    res->rows = blink_list_new();
    res->columns = blink_list_new();
    res->num_rows = 0;
    res->num_cols = 0;
    res->rc = 0;
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) {
        res->rc = SQLITE_MISUSE;
        return res;
    }
    char* err = NULL;
    int rc = sqlite3_exec(db, sql, blink_sqlite3_query_cb, res, &err);
    res->rc = (int64_t)rc;
    if (err) sqlite3_free(err);
    return res;
}
#endif

BLINK_RT_FN blink_sqlite3_stmt* blink_sqlite3_prepare(blink_sqlite3_conn* c, const char* sql);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN blink_sqlite3_stmt* blink_sqlite3_prepare(blink_sqlite3_conn* c, const char* sql) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) return NULL;
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return NULL;
    }
    blink_sqlite3_stmt* s = (blink_sqlite3_stmt*)blink_alloc_shared(sizeof(blink_sqlite3_stmt));
    s->stmt = stmt;
    s->conn = c;
    s->prev_open = NULL;
    s->next_open = NULL;
    /* SQL with no statement in it prepares a NULL stmt, which has nothing to finalize. */
    if (!stmt) return s;
    pthread_mutex_lock(&c->mu);
    if (!c->db) {
        /* A close on another thread ran since the check above; it swept the list already. */
        pthread_mutex_unlock(&c->mu);
        sqlite3_finalize(stmt);
        return NULL;
    }
    s->next_open = c->open;
    if (c->open) c->open->prev_open = s;
    c->open = s;
    pthread_mutex_unlock(&c->mu);
    return s;
}
#endif

/* The Stmt token of a statement this connection prepared: its owner is the connection. */
BLINK_RT_FN blink_db_stmt* blink_sqlite3_stmt_token(blink_sqlite3_stmt* s);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN blink_db_stmt* blink_sqlite3_stmt_token(blink_sqlite3_stmt* s) {
    return blink_db_stmt_new(s ? (void*)s->conn : NULL, (void*)s, 0);
}
#endif

/* The statement behind t when connection c made it, else NULL: the owner check. */
BLINK_RT_FN blink_sqlite3_stmt* blink_sqlite3_stmt_of(blink_sqlite3_conn* c, blink_db_stmt* t);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN blink_sqlite3_stmt* blink_sqlite3_stmt_of(blink_sqlite3_conn* c, blink_db_stmt* t) {
    return (blink_sqlite3_stmt*)blink_db_stmt_impl_for(t, (void*)c);
}
#endif

/* The checks of sections/04_effects.md §4.4.10 on a Stmt that reaches connection c, in
 * order: 1 when c did not make it, 2 when c is closed, 3 when it is finalized, else 0.
 * Close finalizes every statement, so the closed check comes before the finalized one. */
BLINK_RT_FN int64_t blink_sqlite3_stmt_check(blink_sqlite3_conn* c, blink_db_stmt* t);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_stmt_check(blink_sqlite3_conn* c, blink_db_stmt* t) {
    blink_sqlite3_stmt* s = blink_sqlite3_stmt_of(c, t);
    if (!s) return 1;
    if (!blink_sqlite3_conn_db(c)) return 2;
    if (!s->stmt) return 3;
    return 0;
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_bind_int(blink_sqlite3_stmt* s, int64_t idx, int64_t val);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_bind_int(blink_sqlite3_stmt* s, int64_t idx, int64_t val) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return SQLITE_MISUSE;
    return (int64_t)sqlite3_bind_int64(stmt, (int)idx, (sqlite3_int64)val);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_bind_text(blink_sqlite3_stmt* s, int64_t idx, const char* val);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_bind_text(blink_sqlite3_stmt* s, int64_t idx, const char* val) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return SQLITE_MISUSE;
    return (int64_t)sqlite3_bind_text(stmt, (int)idx, val, -1, SQLITE_TRANSIENT);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_step(blink_sqlite3_stmt* s);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_step(blink_sqlite3_stmt* s) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return SQLITE_MISUSE;
    return (int64_t)sqlite3_step(stmt);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_column_int(blink_sqlite3_stmt* s, int64_t col);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_column_int(blink_sqlite3_stmt* s, int64_t col) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return 0;
    return (int64_t)sqlite3_column_int64(stmt, (int)col);
}
#endif

BLINK_RT_FN const char* blink_sqlite3_column_text(blink_sqlite3_stmt* s, int64_t col);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN const char* blink_sqlite3_column_text(blink_sqlite3_stmt* s, int64_t col) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return blink_str_from_cstr_gc("");
    const unsigned char* text = sqlite3_column_text(stmt, (int)col);
    if (!text) return blink_str_from_cstr_gc("");
    return blink_str_from_cstr_gc((const char*)text);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_reset(blink_sqlite3_stmt* s);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_reset(blink_sqlite3_stmt* s) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return SQLITE_MISUSE;
    return (int64_t)sqlite3_reset(stmt);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_finalize(blink_sqlite3_stmt* s);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
/* A second finalize is a no-op. The finalize itself runs outside mu: the database stays a
 * zombie until its last statement goes, so stmt is valid until then. */
BLINK_RT_FN int64_t blink_sqlite3_finalize(blink_sqlite3_stmt* s) {
    if (!s || !s->conn) return SQLITE_OK;
    blink_sqlite3_conn* c = s->conn;
    pthread_mutex_lock(&c->mu);
    sqlite3_stmt* stmt = s->stmt;
    s->stmt = NULL;
    if (stmt) blink_sqlite3_unlink_locked(c, s);
    pthread_mutex_unlock(&c->mu);
    if (!stmt) return SQLITE_OK;
    return (int64_t)sqlite3_finalize(stmt);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_bind_double(blink_sqlite3_stmt* s, int64_t idx, double val);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_bind_double(blink_sqlite3_stmt* s, int64_t idx, double val) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return SQLITE_MISUSE;
    return (int64_t)sqlite3_bind_double(stmt, (int)idx, val);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_column_count(blink_sqlite3_stmt* s);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_column_count(blink_sqlite3_stmt* s) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return 0;
    return (int64_t)sqlite3_column_count(stmt);
}
#endif

BLINK_RT_FN const char* blink_sqlite3_column_name_str(blink_sqlite3_stmt* s, int64_t idx);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN const char* blink_sqlite3_column_name_str(blink_sqlite3_stmt* s, int64_t idx) {
    sqlite3_stmt* stmt = blink_sqlite3_live_stmt(s);
    if (!stmt) return blink_str_from_cstr_gc("");
    const char* name = sqlite3_column_name(stmt, (int)idx);
    return name ? blink_str_from_cstr_gc(name) : blink_str_from_cstr_gc("");
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_last_insert_rowid(blink_sqlite3_conn* c);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_last_insert_rowid(blink_sqlite3_conn* c) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) return 0;
    return (int64_t)sqlite3_last_insert_rowid(db);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_close(blink_sqlite3_conn* c);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
/* A second close is a no-op. Close finalizes every statement still open first, so the
 * database really closes and its locks go. close_v2 also frees a statement prepared
 * outside these boxes. */
BLINK_RT_FN int64_t blink_sqlite3_close(blink_sqlite3_conn* c) {
    if (!c) return SQLITE_OK;
    pthread_mutex_lock(&c->mu);
    sqlite3* db = c->db;
    c->db = NULL;
    while (db && c->open) {
        blink_sqlite3_stmt* s = c->open;
        sqlite3_stmt* stmt = s->stmt;
        s->stmt = NULL;
        blink_sqlite3_unlink_locked(c, s);
        sqlite3_finalize(stmt);
    }
    pthread_mutex_unlock(&c->mu);
    if (!db) return SQLITE_OK;
    return (int64_t)sqlite3_close_v2(db);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_is_closed(blink_sqlite3_conn* c);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_is_closed(blink_sqlite3_conn* c) {
    return blink_sqlite3_conn_db(c) ? 0 : 1;
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_is_finalized(blink_sqlite3_stmt* s);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_is_finalized(blink_sqlite3_stmt* s) {
    return (s && s->stmt) ? 0 : 1;
}
#endif

BLINK_RT_FN const char* blink_sqlite3_errmsg(blink_sqlite3_conn* c);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN const char* blink_sqlite3_errmsg(blink_sqlite3_conn* c) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) return blink_str_from_cstr_gc("connection is closed");
    const char* msg = sqlite3_errmsg(db);
    return msg ? blink_str_from_cstr_gc(msg) : blink_str_from_cstr_gc("");
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_begin(blink_sqlite3_conn* c);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_begin(blink_sqlite3_conn* c) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) return SQLITE_MISUSE;
    return (int64_t)sqlite3_exec(db, "BEGIN", NULL, NULL, NULL);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_commit(blink_sqlite3_conn* c);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_commit(blink_sqlite3_conn* c) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) return SQLITE_MISUSE;
    return (int64_t)sqlite3_exec(db, "COMMIT", NULL, NULL, NULL);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_rollback(blink_sqlite3_conn* c);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_rollback(blink_sqlite3_conn* c) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) return SQLITE_MISUSE;
    return (int64_t)sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_result_rc(blink_sqlite3_result* res);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_result_rc(blink_sqlite3_result* res) {
    return res->rc;
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_exec_void(blink_sqlite3_conn* c, const char* sql);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_exec_void(blink_sqlite3_conn* c, const char* sql) {
    sqlite3* db = blink_sqlite3_conn_db(c);
    if (!db) return SQLITE_MISUSE;
    char* err = NULL;
    int rc = sqlite3_exec(db, sql, NULL, NULL, &err);
    if (err) sqlite3_free(err);
    return (int64_t)rc;
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_execute(blink_sqlite3_conn* c, const char* sql);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_execute(blink_sqlite3_conn* c, const char* sql) {
    int64_t rc = blink_sqlite3_exec_void(c, sql);
    if (rc != SQLITE_OK) return -1;
    return (int64_t)sqlite3_last_insert_rowid(c->db);
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_result_num_rows(blink_sqlite3_result* res);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_result_num_rows(blink_sqlite3_result* res) {
    return res->num_rows;
}
#endif

BLINK_RT_FN int64_t blink_sqlite3_result_num_cols(blink_sqlite3_result* res);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN int64_t blink_sqlite3_result_num_cols(blink_sqlite3_result* res) {
    return res->num_cols;
}
#endif

BLINK_RT_FN const char* blink_sqlite3_result_column_name(blink_sqlite3_result* res, int64_t idx);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN const char* blink_sqlite3_result_column_name(blink_sqlite3_result* res, int64_t idx) {
    if (idx < 0 || idx >= res->num_cols) return BLINK_STR_EMPTY;
    return (const char*)blink_list_get(res->columns, idx);
}
#endif

BLINK_RT_FN const char* blink_sqlite3_result_cell(blink_sqlite3_result* res, int64_t row, int64_t col);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN const char* blink_sqlite3_result_cell(blink_sqlite3_result* res, int64_t row, int64_t col) {
    if (row < 0 || row >= res->num_rows) return BLINK_STR_EMPTY;
    blink_list* row_data = (blink_list*)blink_list_get(res->rows, row);
    if (col < 0 || col >= blink_list_len(row_data)) return BLINK_STR_EMPTY;
    return (const char*)blink_list_get(row_data, col);
}
#endif

BLINK_RT_FN void blink_sqlite3_result_free(blink_sqlite3_result* res);
#ifndef BLINK_NATIVE_SHIMS_DECLS_ONLY
BLINK_RT_FN void blink_sqlite3_result_free(blink_sqlite3_result* res) {
    (void)res; /* GC-managed — blink_alloc uses GC_MALLOC, no manual free needed */
}
#endif

#endif /* BLINK_USE_SQLITE */

#endif /* BLINK_RUNTIME_SQLITE_H */
