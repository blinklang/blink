#ifndef BLINK_RUNTIME_DB_H
#define BLINK_RUNTIME_DB_H

/* A Stmt is a token that a DB handler makes (sections/04_effects.md §4.4.10). Blink code
 * reads no field of it. owner is the connection whose handler made it, and NULL for a
 * Stmt.mock token, so no mock token can pass the owner check of a real connection. */
typedef struct {
    void* owner;
    void* impl;
    int64_t key;
} blink_db_stmt;

BLINK_RT_FN blink_db_stmt* blink_db_stmt_new(void* owner, void* impl, int64_t key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_db_stmt* blink_db_stmt_new(void* owner, void* impl, int64_t key) {
    /* A token outlives any `with arena` it was made in, as the statement behind it does. */
    blink_db_stmt* t = (blink_db_stmt*)blink_alloc_shared(sizeof(blink_db_stmt));
    t->owner = owner;
    t->impl = impl;
    t->key = key;
    return t;
}
#endif

BLINK_RT_FN blink_db_stmt* blink_db_stmt_mock(int64_t key);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_db_stmt* blink_db_stmt_mock(int64_t key) {
    return blink_db_stmt_new(NULL, NULL, key);
}
#endif

/* The driver part of the token when owner made it, else NULL. */
BLINK_RT_FN void* blink_db_stmt_impl_for(blink_db_stmt* t, void* owner);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN void* blink_db_stmt_impl_for(blink_db_stmt* t, void* owner) {
    if (!t || !owner || t->owner != owner) return NULL;
    return t->impl;
}
#endif

#endif /* BLINK_RUNTIME_DB_H */
