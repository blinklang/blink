# How the build spells the C type of an `@ffi.struct`

## Problem

A C header can name a struct by a tag (`struct pollfd`), by a typedef name (`div_t`), or by
both. The `name:` of an `@ffi.struct` gives only the name. The generated C must use the
spelling that the header declares, because `struct div_t` names no type on any libc.

## What the generated C does

When `name:` is a C identifier, the generated C spells the original type as the macro
`BLINK_FFI_STRUCT_<name>`. Each unit defines the macro after its foreign includes, but only if
the compile did not define it:

```c
#ifndef BLINK_FFI_STRUCT_div_t
#define BLINK_FFI_STRUCT_div_t struct div_t
#endif
```

When `name:` is not a C identifier, the generated C writes `struct <name>` and has no macro.

## What the build does

Before it compiles the units of a program, `blink build` and `blink run` ask the C compiler of
each target about the program's mirrors (`ffi_struct_defines` in `src/cli.bl`). The probe file
has two lines for each name: one that uses `struct <name>` and one that uses `<name>` as a type.

- The tag line compiles: the build keeps the default spelling. If the typedef line also
  compiles, the tag wins.
- Only the typedef line compiles: the build adds `-DBLINK_FFI_STRUCT_<name>=<name>` to the
  compile of each unit.
- No line compiles: the build keeps the default spelling, and the unit compile reports the
  error.

The probe reads English diagnostics, so it runs with `LC_ALL=C`. Each tag name gives one error
on its typedef line. clang, and so zig cc for each cross target, stops after 20 errors by
default, so the probe adds `-ferror-limit=0` for those compilers. gcc has no such limit and
refuses the flag. If the output still says that the compiler stopped, the build reads no
verdict and keeps the default spelling.

The `-D` flags are part of the include flags. The object-cache keys of both build paths and the
PCH key hash them, so an object compiled with one spelling is not used for the other.

## Limits

- `blink build --emit c` and a compile by hand with `blinkc` and `cc` get no probe. The C they
  get spells each mirror as `struct <name>`. To compile it for a typedef-only name, add
  `-DBLINK_FFI_STRUCT_<name>=<name>`.
- The std archive compiles with no probe. A `lib/std` mirror must name a struct tag.
- The probe sees only the mirrors of the program that it builds.
- The probe reads the headers of the program's own foreign declarations, but not `runtime.h`
  and the system headers that it includes. It sets `_POSIX_C_SOURCE` itself. A header that
  needs one of those system headers first, or that declares a type only under another feature
  macro such as `_GNU_SOURCE`, can get a different verdict in the probe. The constant probe has
  the same limit.
