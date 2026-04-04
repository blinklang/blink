#ifndef BLINK_RUNTIME_SQLITE_H
#define BLINK_RUNTIME_SQLITE_H

#ifdef BLINK_USE_SQLITE
#include <sqlite3.h>

/* Result struct for blink_sqlite3_query convenience wrapper */
typedef struct {
    blink_list* rows;      /* List of blink_list* (each row is a list of strings) */
    blink_list* columns;   /* List of column name strings */
    int64_t num_rows;
    int64_t num_cols;
    int64_t rc;            /* sqlite3 return code (0 = SQLITE_OK) */
} blink_sqlite3_result;

BLINK_UNUSED static void* blink_sqlite3_open(const char* path) {
    sqlite3* db = NULL;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    return (void*)db;
}

BLINK_UNUSED static int64_t blink_sqlite3_exec(void* db, const char* sql,
                                  int (*callback)(void*, int, char**, char**),
                                  void* arg, const char** errmsg) {
    char* err = NULL;
    int rc = sqlite3_exec((sqlite3*)db, sql, callback, arg, &err);
    if (errmsg) {
        *errmsg = err ? blink_strdup(err) : NULL;
    }
    if (err) sqlite3_free(err);
    return (int64_t)rc;
}

BLINK_UNUSED static int blink_sqlite3_query_cb(void* ud, int ncols, char** values, char** names) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)ud;
    if (res->num_rows == 0) {
        for (int i = 0; i < ncols; i++) {
            blink_list_push(res->columns, (void*)blink_strdup(names[i]));
        }
        res->num_cols = (int64_t)ncols;
    }
    blink_list* row = blink_list_new();
    for (int i = 0; i < ncols; i++) {
        blink_list_push(row, (void*)blink_strdup(values[i] ? values[i] : ""));
    }
    blink_list_push(res->rows, (void*)row);
    res->num_rows++;
    return 0;
}

BLINK_UNUSED static void* blink_sqlite3_query(void* db, const char* sql) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)blink_alloc(sizeof(blink_sqlite3_result));
    res->rows = blink_list_new();
    res->columns = blink_list_new();
    res->num_rows = 0;
    res->num_cols = 0;
    res->rc = 0;
    char* err = NULL;
    int rc = sqlite3_exec((sqlite3*)db, sql, blink_sqlite3_query_cb, res, &err);
    res->rc = (int64_t)rc;
    if (err) sqlite3_free(err);
    return res;
}

BLINK_UNUSED static void* blink_sqlite3_prepare(void* db, const char* sql) {
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2((sqlite3*)db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return NULL;
    }
    return (void*)stmt;
}

BLINK_UNUSED static int64_t blink_sqlite3_bind_int(void* stmt, int64_t idx, int64_t val) {
    return (int64_t)sqlite3_bind_int64((sqlite3_stmt*)stmt, (int)idx, (sqlite3_int64)val);
}

BLINK_UNUSED static int64_t blink_sqlite3_bind_text(void* stmt, int64_t idx, const char* val) {
    return (int64_t)sqlite3_bind_text((sqlite3_stmt*)stmt, (int)idx, val, -1, SQLITE_TRANSIENT);
}

BLINK_UNUSED static int64_t blink_sqlite3_step(void* stmt) {
    return (int64_t)sqlite3_step((sqlite3_stmt*)stmt);
}

BLINK_UNUSED static int64_t blink_sqlite3_column_int(void* stmt, int64_t col) {
    return (int64_t)sqlite3_column_int64((sqlite3_stmt*)stmt, (int)col);
}

BLINK_UNUSED static const char* blink_sqlite3_column_text(void* stmt, int64_t col) {
    const unsigned char* text = sqlite3_column_text((sqlite3_stmt*)stmt, (int)col);
    if (!text) return blink_strdup("");
    return blink_strdup((const char*)text);
}

BLINK_UNUSED static int64_t blink_sqlite3_reset(void* stmt) {
    return (int64_t)sqlite3_reset((sqlite3_stmt*)stmt);
}

BLINK_UNUSED static int64_t blink_sqlite3_finalize(void* stmt) {
    return (int64_t)sqlite3_finalize((sqlite3_stmt*)stmt);
}

BLINK_UNUSED static int64_t blink_sqlite3_close(void* db) {
    return (int64_t)sqlite3_close((sqlite3*)db);
}

BLINK_UNUSED static const char* blink_sqlite3_errmsg(void* db) {
    const char* msg = sqlite3_errmsg((sqlite3*)db);
    return msg ? blink_strdup(msg) : blink_strdup("");
}

BLINK_UNUSED static int64_t blink_sqlite3_begin(void* db) {
    return (int64_t)sqlite3_exec((sqlite3*)db, "BEGIN", NULL, NULL, NULL);
}

BLINK_UNUSED static int64_t blink_sqlite3_commit(void* db) {
    return (int64_t)sqlite3_exec((sqlite3*)db, "COMMIT", NULL, NULL, NULL);
}

BLINK_UNUSED static int64_t blink_sqlite3_rollback(void* db) {
    return (int64_t)sqlite3_exec((sqlite3*)db, "ROLLBACK", NULL, NULL, NULL);
}

int64_t blink_sqlite3_result_rc(blink_handle* r) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)r;
    return res->rc;
}

BLINK_UNUSED static int64_t blink_sqlite3_exec_void(void* db, const char* sql) {
    char* err = NULL;
    int rc = sqlite3_exec((sqlite3*)db, sql, NULL, NULL, &err);
    if (err) sqlite3_free(err);
    return (int64_t)rc;
}

BLINK_UNUSED static int64_t blink_sqlite3_execute(void* db, const char* sql) {
    int64_t rc = blink_sqlite3_exec_void(db, sql);
    if (rc != SQLITE_OK) return -1;
    return (int64_t)sqlite3_last_insert_rowid((sqlite3*)db);
}

BLINK_UNUSED static int64_t blink_sqlite3_result_num_rows(void* r) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)r;
    return res->num_rows;
}

BLINK_UNUSED static int64_t blink_sqlite3_result_num_cols(void* r) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)r;
    return res->num_cols;
}

BLINK_UNUSED static const char* blink_sqlite3_result_column_name(void* r, int64_t idx) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)r;
    if (idx < 0 || idx >= res->num_cols) return "";
    return (const char*)blink_list_get(res->columns, idx);
}

BLINK_UNUSED static const char* blink_sqlite3_result_cell(void* r, int64_t row, int64_t col) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)r;
    if (row < 0 || row >= res->num_rows) return "";
    blink_list* row_data = (blink_list*)blink_list_get(res->rows, row);
    if (col < 0 || col >= blink_list_len(row_data)) return "";
    return (const char*)blink_list_get(row_data, col);
}

BLINK_UNUSED static void blink_sqlite3_result_free(void* r) {
    (void)r; /* GC-managed — blink_alloc uses GC_MALLOC, no manual free needed */
}

#endif /* BLINK_USE_SQLITE */

#endif /* BLINK_RUNTIME_SQLITE_H */
