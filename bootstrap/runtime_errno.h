#ifndef BLINK_RUNTIME_ERRNO_H
#define BLINK_RUNTIME_ERRNO_H

// Vendored shim for strerror(3). The C prototype returns `char*`, which is a
// third type distinct from both `int8_t*` and `uint8_t*` under gcc — so no @ffi
// binding of the raw `strerror` symbol can avoid a conflicting-types error once
// <string.h> is in scope. Wrapping it here keeps the char* entirely on the C
// side and hands Blink a `const char*` (an owned GC copy). std.fs binds this
// symbol via @ffi to render FsError's Display message.
//
// strerror_r (not strerror) because the runtime ships threads: strerror shares
// one process-wide buffer, so a concurrent call could overwrite it mid-copy.
// glibc with _GNU_SOURCE selects the GNU variant (returns a pointer that may or
// may not be the buffer); _POSIX_C_SOURCE alone, and macOS, select the XSI
// variant (int return, always fills the buffer) — both are handled.
//
// Declaration is unconditional; the body is guarded by BLINK_RUNTIME_DECLS_ONLY
// so the archive monolith holds the one definition and every other TU sees only
// the declaration (the same split runtime_core.h uses for blink_strdup).
#include <string.h>

BLINK_RT_FN const char* blink_strerror(int64_t code);
#ifndef BLINK_RUNTIME_DECLS_ONLY
BLINK_RT_FN const char* blink_strerror(int64_t code) {
    char buf[256];
    buf[0] = '\0';
#if defined(_GNU_SOURCE) && !defined(__APPLE__)
    const char* msg = strerror_r((int)code, buf, sizeof(buf));
    return blink_strdup(msg ? msg : "unknown error");
#else
    if (strerror_r((int)code, buf, sizeof(buf)) != 0) {
        return blink_strdup("unknown error");
    }
    return blink_strdup(buf);
#endif
}
#endif

#endif
