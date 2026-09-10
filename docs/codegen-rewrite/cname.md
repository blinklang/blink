# cname.bl: the C symbol name producer

`src/cname.bl` is the one module that spells a C symbol name. Every other module
asks it and never builds a name from parts.

## Rules

- Input is a declaration node id or a type id (tid). No function reads a type name
  string to decide a shape, and no function reads a `CT_` constant.
- The module of a symbol is `node_source_module(decl)`. In a single-file build the
  program's own module is `""`; in a package build it is `"__main__"`. Both spell no
  module prefix.
- A speller that cannot name a type returns an `ICE_SEG_*` sentinel from
  `diagnostics.bl`. It never puts a sentinel inside a longer name, so
  `diag_is_ice_seg` still finds it.
- A segment for an unsubstituted type parameter is `<tv>`. A name producer
  (`mono_stem`, `c_typedef_name`) refuses it with `ICE_SEG_UNSOLVED_TYPEVAR`; the
  caller substitutes first.
- An instance tid names its base by bare name only. When two modules declared that
  bare name, `tc_tid_decl_node` answers `DECL_NODE_AMBIGUOUS` and cname fails closed
  with `ICE_SEG_AMBIGUOUS_DECL`.
- Two facts come from neither the node nor the tid. The owner marks the declaration
  and cname reads the mark:
  - `cname_mark_runtime_owned(td)`: the type's C typedef lives in `runtime.h`.
  - `cname_mark_transparent_newtype(td)`: the type lowers to a bare `int64_t`.
- `cname_reset()` clears both marks.

## Name forms

| Form | Function | Inputs | Example |
|---|---|---|---|
| Function | `c_fn_decl_name(fn)` | fn decl node | `helper` in main -> `blink_u_helper`; `main` -> `blink_main`; `@ffi` `getpid` -> `blink_getpid`; `ping` in `mymod` -> `blink_mymod_ping` |
| Global let | `c_global_name(let)` | let node | `counter` -> `counter` (every module) |
| Mono fn instance | `c_mono_fn_name(fn, args_tid)` | fn decl node, interned tuple tid of the type args | `identity[Box[Int]]` -> `blink_identity_0Box_10Int`; `wrap[Ngx]` from `mymod` -> `blink_wrap_0Ngx` |
| Type | `c_type_decl_name(td)` | type decl node | `Point` -> `blink_Point`; `Ngx` in `mymod` -> `blink_mymod_Ngx`; opaque `@ffi.opaque(name: "FILE")` -> `FILE*`; marked runtime-owned `ConversionError` -> `blink_ConversionError` |
| Type tag | `c_type_decl_tag(td)` | type decl node | `Ngx` in `mymod` -> `mymod_Ngx`; opaque `CFile` -> `CFile` |
| Mono type instance | `c_mono_type_c_name(tid)` | struct or enum instance tid | `Box[Option[Int]]` -> `blink_Box_0Option_1int`; `Box2[Int]` in `mymod` -> `blink_mymod_1Box2_0Int` |
| Typedef | `c_typedef_name(tid)` | struct, enum, Option, Result or tuple tid | `Option[Int]` -> `blink_Option_int`; `Result[Void, Str]` -> `blink_Result_void_str`; `(Int, Str)` -> `blink_Tuple2_int_str` |
| Variant tag macro | `c_variant_tag_macro(td, v)` / `c_mono_variant_tag_macro(tid, v)` | type decl node or instance tid, variant node | `Shape.Circle` -> `blink_Shape_Circle_TAG`; `Tree[Int].Leaf` -> `blink_Tree_0Int_Leaf_TAG` |
| Derived method | `c_derive_method_name(td, m)` | type decl node, method | `Point` `eq` -> `blink_Point_eq` |
| Impl method | `c_impl_method_name(im, m)` / `_q(im, trait, m)` | impl node, method | `impl Greet for Point` `greet` -> `blink_Point_Greet_greet`; `impl From[Int] for Point` `from` -> `blink_Point_from_Int`; in `mymod` -> `blink_mymod_Ngx_Greet2_greet2` |
| Display dispatcher | `c_display_dispatch_name(im)` | impl node | `blink_Point_Display_display` |
| Segment | `c_seg_top(tid)` / `c_seg_inner(tid)` | tid | `Int` -> `Int` / `int`; `Float` -> `Float` / `double`; `Map[K, V]` -> `Map` / `map`; `Point` -> `Point` / `Point`; `Ngx` in `mymod` -> `Ngx` / `mymod_Ngx`; fn type -> ICE / `closure` |
| Typedef guard | `td_guard_name(c)`, `td_guard_open_lines(c)`, `td_guard_close_line()` | C name | `BLINK_TD_blink_Point`, `#ifndef ...` + `#define ...`, `#endif` |

## Mono stem

One private function, `mono_stem(base, args_start, args_count)`, builds every mono
name. It reads the type arguments from `ty_param_list`, spells each at TOP position,
escapes `_` as `_1` in every segment, and joins with `_0`. A fn instance and a
struct or enum instance both go through it.

## Segment positions

- TOP: the type is a mono argument. Scalars are Pascal (`Int`, `Str`, `Float`). A
  bare struct is its bare name with no module. An instance is its mono stem.
- INNER: the type sits inside a carrier or tuple. Scalars are the runtime tag
  (`int`, `str`, `double`, `list`, `map`, `closure`). A bare struct is its full tag
  with module. An instance is its mono stem.
- A tuple element whose declaration is marked transparent spells `int`. Option and
  Result keep the nominal tag.

## What the tid alone cannot spell

A tid names a type; it does not name a function, an impl block or a global, and it
does not carry a module or an `@ffi.opaque` C name. Those forms take the declaration
node. A struct or enum tid reaches its declaration through `tc_tid_decl_node`.

## Tests

`tests/test_cname_*.bl` hold one golden per name form. They share
`src/cname_test_helpers.bl`: it compiles a probe source in-process, then finds
declaration nodes by kind, name and module, and type ids by their source spelling.
