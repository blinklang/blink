/* Stub for cross-compilation with zig cc (missing from zig's macOS sysroot) */
#ifndef _MACH_O_GETSECT_H_
#define _MACH_O_GETSECT_H_
#include <stdint.h>
#include <stddef.h>
#include <mach-o/loader.h>

static inline uint8_t *getsectiondata(
    const struct mach_header_64 *mhp, const char *segname,
    const char *sectname, unsigned long *size) {
    if (size) *size = 0;
    return NULL;
}

static inline const struct section_64 *getsectbynamefromheader_64(
    const struct mach_header_64 *mhp, const char *segname,
    const char *sectname) {
    return NULL;
}

static inline const struct section *getsectbynamefromheader(
    const struct mach_header *mhp, const char *segname,
    const char *sectname) {
    return NULL;
}
#endif
