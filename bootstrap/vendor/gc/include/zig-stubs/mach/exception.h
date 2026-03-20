/* Stub for cross-compilation with zig cc (missing from zig's macOS sysroot) */
#ifndef _MACH_EXCEPTION_H_
#define _MACH_EXCEPTION_H_
#include <stdint.h>
typedef int exception_type_t;
typedef int exception_data_type_t;
typedef int64_t mach_exception_data_type_t;
typedef exception_data_type_t *exception_data_t;
typedef mach_exception_data_type_t *mach_exception_data_t;
#define EXC_BAD_ACCESS 1
#define EXC_BAD_INSTRUCTION 2
#define EXCEPTION_DEFAULT 1
#define MACH_EXCEPTION_CODES 0x80000000
#endif
