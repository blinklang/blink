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
each target about the mirror names in the C (`ffi_struct_defines` in `src/cli.bl`). A one-unit
build asks its unit C. A per-module build asks the program types header, `blink.types.h`, with
its include guard removed. Each unit includes that header before its own copy of the same block,
so the header's prefix spells each name. That C is the one source for the names and the headers:

- The names are the names of the `#ifndef BLINK_FFI_STRUCT_<name>` lines. A mirror in a
  `lib/std` module that the units compile is in this block, as a mirror of the program is.
- The probe file starts with the preprocessor lines of the unit C before that block. These are
  the lines that the unit compile reads before it spells a name: `runtime.h` or the archive
  header, and the headers of the foreign types. The other lines there are prototypes of Blink
  names, which declare no C type, so the probe drops them.
- After a `#line 1 "__blink_spelling_probe__"` line, the probe has two lines for each name: one
  that uses `struct <name>` and one that uses `<name>` as a type.

The probe compiles with the command and the include flags of the unit compile.

- The tag line compiles: the build keeps the default spelling. If the typedef line also
  compiles, the tag wins.
- Only the typedef line compiles: the build adds `-DBLINK_FFI_STRUCT_<name>=<name>` to the
  compile of each unit.
- No line compiles: the build keeps the default spelling. If the layout check covers the
  mirror, the build stops and reports that the header declares no such name.

A C with no `BLINK_FFI_STRUCT_` block runs no probe. Each build runs at most one probe for
each target. A per-module build does not ask each unit's C: a unit includes the types header,
whose layout asserts fail under the default spelling, and an error in a header gives the layout
check no verdict.

The probe reads English diagnostics, so it runs with `LC_ALL=C`. Each tag name gives one error
on its typedef line. clang, and so zig cc for each cross target, stops after 20 errors by
default, so the probe adds `-ferror-limit=0` for those compilers. gcc has no such limit and
refuses the flag. If the output still says that the compiler stopped, the build reads no
verdict and keeps the default spelling.

The `-D` flags are part of the include flags. The object-cache keys of both build paths and the
PCH key hash them, so an object compiled with one spelling is not used for the other.

## The layout check

The same probe file also checks the layout of each mirror that the unit C names, a mirror in
a `lib/std` module too (`src/ffi_layout_probe.bl`). The build maps each name back to the
`@ffi.struct` declarations that give it. A name that no declaration gives is a compiler bug:
the build stops with an internal error (I0017, exit 101) and runs no probe.

For each mirror, the file defines a struct with the C layout that the units give the mirror:
`struct blink_fs_m<k>`. A mirror held by value gets its own probe
struct first. A `Ptr` field gets one pointer type. Then, for both spellings of the C name, the
file has these lines:

- for each field, one line that compiles only if the C struct has a member of that name, one
  line that compares the offsets and one line that compares the sizes;
- one line that compares the size of the struct.

The size line of a `Bool` field is not in the file. The units spell `Bool` as C `int`, and C's
`bool` is one byte, so that compare would report the units' spelling as an error of the
mirror. `offsetof` refuses a bit-field, so the report of a bit-field member says that the C
struct has no such field, or that the field is a bit-field.

The spelling verdict picks the lines that the build reads. Each failed line maps back to the
mirror, the field and what differs. The build reports one mismatch for each mirror, in this
order: no name, then no field, then the first field with a different offset or size, then the
struct size.

When a mirror differs, the build stops before it compiles a unit. It reports GeneratedCDidNotCompile
(I0017, exit 101) at the `@ffi.struct` line, with the mirror, the C struct, the target and the
field (`report_ffi_struct_mismatches` in `src/cli.bl`). This is the one place that sets the
name, the code and the exit.

The check gives no verdict in these cases, and the units' own `_Static_assert` lines stay as
the backstop:

- the probe cannot spell a field as the units do;
- the compile stopped at an error limit;
- an error is in a header, or on a line of the file that is not a check line.

The probe of the foreign prototype guards (`foreign_decl_probe.bl`) reads the struct block too,
so it compiles with the spelling flags.

## A compile by hand

`blink build --emit c` gives C with no flags. A compile by hand with `blinkc` and `cc` gets the
flags that blink build gives the same C from:

```
blinkc --build-probe-flags <file.c> <cc> [cflags...]
```

It prints the guard flags, then the spelling flags, on one line, in the order of a unit
compile. It asks the same two probes that blink build asks, through the same functions
(`hand_cc_flags`, `guard_run` and `spelling_run` in `src/foreign_decl_probe.bl`). The C file
holds no declarations, so the entry has no layout lines: a compile by hand gets no layout check.

blink build keeps the default spelling when a probe gives no verdict, and the unit compile then
reports the error. A compile by hand has no such sign, so the entry exits 1 and says why in
place of an empty line: it cannot write a probe, the C compiler cannot run, or the compile
stopped before it read the probe's lines. It also refuses a cflag that changes which errors the
compiler writes or how it writes them, such as `-Werror`, `-fmax-errors=` or
`-fdiagnostics-color=always`.

## Limits

- The std archive compiles with no probe. A mirror in a `lib/std` module that the archive holds
  must name a struct tag. If such a mirror named a typedef, each unit's include of the archive
  header would fail its layout assert in a header, and every layout check would give no verdict.
- The probe reads only the headers that the unit reads before the struct block: the headers of
  the mirrors and of the `@ffi.opaque` types. The unit reads the header of a foreign function or
  a foreign constant after the block, so the probe does not read it. A mirror whose name only
  such a header declares keeps `struct <name>`, and the unit compile reports the error. Put the
  header that declares the type in the mirror's `header:`.
