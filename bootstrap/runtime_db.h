#ifndef BLINK_RUNTIME_DB_H
#define BLINK_RUNTIME_DB_H

/* A Stmt is a token that a DB handler makes (sections/04_effects.md §4.4.10). Blink code
 * reads no field of it. serial is unique per token, and Eq and Hash compare it, so a copy
 * is equal to its token and two tokens are never equal. owner is the connection whose
 * handler made it, and NULL for a token from Stmt.new, so no such token can pass the
 * owner check of a real connection. */
typedef struct {
    int64_t serial;
    void* owner;
    void* impl;
} blink_db_stmt;

BLINK_RT_FN blink_db_stmt* blink_db_stmt_new(void* owner, void* impl);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_db_stmt* blink_db_stmt_new(void* owner, void* impl) {
    /* A program has one definition of this fn (static in a one-unit build, extern from the
       storage unit in a many-unit build), so the counter is one per program. The atomic add
       keeps two threads from taking the same serial. */
    static int64_t next_serial = 0;
    /* A token outlives any `with arena` it was made in, as the statement behind it does. */
    blink_db_stmt* t = (blink_db_stmt*)blink_alloc_shared(sizeof(blink_db_stmt));
    t->serial = __atomic_add_fetch(&next_serial, 1, __ATOMIC_RELAXED);
    t->owner = owner;
    t->impl = impl;
    return t;
}
#endif

BLINK_RT_FN blink_db_stmt* blink_db_stmt_fresh(void);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN blink_db_stmt* blink_db_stmt_fresh(void) {
    return blink_db_stmt_new(NULL, NULL);
}
#endif

BLINK_RT_FN int64_t blink_db_stmt_serial(blink_db_stmt* t);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN int64_t blink_db_stmt_serial(blink_db_stmt* t) {
    return t->serial;
}
#endif

/* Mixed with the process hash seed like an Int key (blink_kops_hash_i64), so a hash value
   gives back no serial and differs between processes (sections/03_types.md §3.6). */
BLINK_RT_FN uint64_t blink_db_stmt_hash(blink_db_stmt* t);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN uint64_t blink_db_stmt_hash(blink_db_stmt* t) {
    return blink_kops_mix_u64(blink_map_seed ^ (uint64_t)t->serial);
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
