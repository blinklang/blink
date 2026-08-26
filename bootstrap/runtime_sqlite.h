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

BLINK_RT_FN sqlite3* blink_sqlite3_open(const char* path) {
    sqlite3* db = NULL;
    int rc = sqlite3_open(path, &db);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    return db;
}

BLINK_RT_FN int64_t blink_sqlite3_exec(sqlite3* db, const char* sql,
                                  int (*callback)(void*, int, char**, char**),
                                  void* arg, const char** errmsg) {
    char* err = NULL;
    int rc = sqlite3_exec(db, sql, callback, arg, &err);
    if (errmsg) {
        *errmsg = err ? blink_strdup(err) : NULL;
    }
    if (err) sqlite3_free(err);
    return (int64_t)rc;
}

BLINK_RT_FN int blink_sqlite3_query_cb(void* ud, int ncols, char** values, char** names) {
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

BLINK_RT_FN blink_sqlite3_result* blink_sqlite3_query(sqlite3* db, const char* sql) {
    blink_sqlite3_result* res = (blink_sqlite3_result*)blink_alloc(sizeof(blink_sqlite3_result));
    res->rows = blink_list_new();
    res->columns = blink_list_new();
    res->num_rows = 0;
    res->num_cols = 0;
    res->rc = 0;
    char* err = NULL;
    int rc = sqlite3_exec(db, sql, blink_sqlite3_query_cb, res, &err);
    res->rc = (int64_t)rc;
    if (err) sqlite3_free(err);
    return res;
}

BLINK_RT_FN sqlite3_stmt* blink_sqlite3_prepare(sqlite3* db, const char* sql) {
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return NULL;
    }
    return stmt;
}

BLINK_RT_FN int64_t blink_sqlite3_bind_int(sqlite3_stmt* stmt, int64_t idx, int64_t val) {
    return (int64_t)sqlite3_bind_int64(stmt, (int)idx, (sqlite3_int64)val);
}

BLINK_RT_FN int64_t blink_sqlite3_bind_text(sqlite3_stmt* stmt, int64_t idx, const char* val) {
    return (int64_t)sqlite3_bind_text(stmt, (int)idx, val, -1, SQLITE_TRANSIENT);
}

BLINK_RT_FN int64_t blink_sqlite3_step(sqlite3_stmt* stmt) {
    return (int64_t)sqlite3_step(stmt);
}

BLINK_RT_FN int64_t blink_sqlite3_column_int(sqlite3_stmt* stmt, int64_t col) {
    return (int64_t)sqlite3_column_int64(stmt, (int)col);
}

BLINK_RT_FN const char* blink_sqlite3_column_text(sqlite3_stmt* stmt, int64_t col) {
    const unsigned char* text = sqlite3_column_text(stmt, (int)col);
    if (!text) return blink_strdup("");
    return blink_strdup((const char*)text);
}

BLINK_RT_FN int64_t blink_sqlite3_reset(sqlite3_stmt* stmt) {
    return (int64_t)sqlite3_reset(stmt);
}

BLINK_RT_FN int64_t blink_sqlite3_finalize(sqlite3_stmt* stmt) {
    return (int64_t)sqlite3_finalize(stmt);
}

BLINK_RT_FN int64_t blink_sqlite3_bind_double(sqlite3_stmt* stmt, int64_t idx, double val) {
    return (int64_t)sqlite3_bind_double(stmt, (int)idx, val);
}

BLINK_RT_FN int64_t blink_sqlite3_column_count(sqlite3_stmt* stmt) {
    return (int64_t)sqlite3_column_count(stmt);
}

BLINK_RT_FN const char* blink_sqlite3_column_name_str(sqlite3_stmt* stmt, int64_t idx) {
    const char* name = sqlite3_column_name(stmt, (int)idx);
    return name ? blink_strdup(name) : blink_strdup("");
}

BLINK_RT_FN int64_t blink_sqlite3_last_insert_rowid(sqlite3* db) {
    return (int64_t)sqlite3_last_insert_rowid(db);
}

BLINK_RT_FN int64_t blink_sqlite3_close(sqlite3* db) {
    return (int64_t)sqlite3_close(db);
}

BLINK_RT_FN const char* blink_sqlite3_errmsg(sqlite3* db) {
    const char* msg = sqlite3_errmsg(db);
    return msg ? blink_strdup(msg) : blink_strdup("");
}

BLINK_RT_FN int64_t blink_sqlite3_begin(sqlite3* db) {
    return (int64_t)sqlite3_exec(db, "BEGIN", NULL, NULL, NULL);
}

BLINK_RT_FN int64_t blink_sqlite3_commit(sqlite3* db) {
    return (int64_t)sqlite3_exec(db, "COMMIT", NULL, NULL, NULL);
}

BLINK_RT_FN int64_t blink_sqlite3_rollback(sqlite3* db) {
    return (int64_t)sqlite3_exec(db, "ROLLBACK", NULL, NULL, NULL);
}

BLINK_RT_FN int64_t blink_sqlite3_result_rc(blink_sqlite3_result* res) {
    return res->rc;
}

BLINK_RT_FN int64_t blink_sqlite3_exec_void(sqlite3* db, const char* sql) {
    char* err = NULL;
    int rc = sqlite3_exec(db, sql, NULL, NULL, &err);
    if (err) sqlite3_free(err);
    return (int64_t)rc;
}

BLINK_RT_FN int64_t blink_sqlite3_execute(sqlite3* db, const char* sql) {
    int64_t rc = blink_sqlite3_exec_void(db, sql);
    if (rc != SQLITE_OK) return -1;
    return (int64_t)sqlite3_last_insert_rowid(db);
}

BLINK_RT_FN int64_t blink_sqlite3_result_num_rows(blink_sqlite3_result* res) {
    return res->num_rows;
}

BLINK_RT_FN int64_t blink_sqlite3_result_num_cols(blink_sqlite3_result* res) {
    return res->num_cols;
}

BLINK_RT_FN const char* blink_sqlite3_result_column_name(blink_sqlite3_result* res, int64_t idx) {
    if (idx < 0 || idx >= res->num_cols) return "";
    return (const char*)blink_list_get(res->columns, idx);
}

BLINK_RT_FN const char* blink_sqlite3_result_cell(blink_sqlite3_result* res, int64_t row, int64_t col) {
    if (row < 0 || row >= res->num_rows) return "";
    blink_list* row_data = (blink_list*)blink_list_get(res->rows, row);
    if (col < 0 || col >= blink_list_len(row_data)) return "";
    return (const char*)blink_list_get(row_data, col);
}

BLINK_RT_FN void blink_sqlite3_result_free(blink_sqlite3_result* res) {
    (void)res; /* GC-managed — blink_alloc uses GC_MALLOC, no manual free needed */
}

#endif /* BLINK_USE_SQLITE */

#endif /* BLINK_RUNTIME_SQLITE_H */
