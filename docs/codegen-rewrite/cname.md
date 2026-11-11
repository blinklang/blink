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
- Three facts come from neither the node nor the tid. Two are marks the owner sets
  on the declaration and cname reads back:
  - `cname_mark_runtime_owned(td)`: the type's C typedef lives in `runtime.h`.
  - `cname_mark_transparent_newtype(td)`: the type lowers to a bare `int64_t`.
- `cname_reset()` clears those two marks, and nothing else.
- The third is the set of declared user effect handles, which typecheck owns and
  clears per program. `effect_root_of` asks `is_user_effect_handle_name` whether a
  Handler tid's root was declared, so `c_vtable_type_name`, `c_ev_field_name` and
  `c_effect_default_op_name` all answer through it. A root that is neither builtin
  nor declared is `ICE_SEG_UNHANDLED_KIND`. Because the set lives in typecheck,
  `cname_reset()` does not clear it: a cname test that wants a user effect must
  reach a typecheck that declared one.

## The escape

A C symbol joins its parts with `_`, and a user name may hold `_`, so a bare join is not
one to one: trait `Tr` of module `x` and trait `Tr_x` would spell one symbol. Every
user name part of a symbol goes through `tc_sym_escape` (typecheck.bl), which writes
`_` as `_1`. After the escape, `_` followed by a digit is a marker:

- `_0` opens a mono argument, or the source type of a `From` or `TryFrom` method.
- `_1` is an escaped `_`.
- `_2` opens the module of a trait that more than one module declares. In an impl
  method stem it also opens the module of a receiver type that has the name of a
  compiler-known type (`type Bytes` in `alpha` -> receiver `Bytes_2alpha`), so the
  user type and the builtin get different symbols.

A name with no `_` keeps its spelling. A module key is escaped like a name. These parts
stay verbatim: the `blink_{name}` symbol of an `@ffi` function whose foreign symbol is
that name, a runtime export, `main`, builtin effect vtables, carrier tags and the
init-globals names.

## Class digits

Every global that cname makes from a Blink name is `blink_`, one class digit, then the
payload. The runtime's own globals are `blink_` and a letter, and a Blink identifier
never starts with a digit. So no compiler name is a runtime name, no two classes make one
string, and no Blink name has to avoid a list of runtime names.
`tests/test_no_runtime_name_takes_a_class_digit.bl` fails when a runtime header or
archive name takes the form.

| Digit | Class | Form |
|---|---|---|
| 2 | function, global, mono fn of the program's own module | `blink_2{name}[_0{arg}...]` |
| 3 | the same, of a named module | `blink_3{module}_{name}[_0{arg}...]` |
| 4 | type of the program's own module | `blink_4{Name}[_0{arg}...]` |
| 5 | type of a named module | `blink_5{module}_{Name}[_0{arg}...]` |
| 6 | impl method written in the program's own module | `blink_6{Type}_{Trait}_{method}[_0{arg}...]` |
| 7 | impl method written in a named module | `blink_7{module}_{Type}_{Trait}_{method}[_0{arg}...]` |
| 8 | derived method | `blink_8{type tag}_{method}` |
| 9 | helper keyed on a type or a user effect | `blink_9{word}_{segment}`; `blink_9ue_{E root}_vtable`, `blink_9ue_{E root}_default_{op}` |

Every part is escaped, so it holds no `_` that is not followed by `1`. A type helper's
word (`promote`, `gclayout`, `rangedebug`, `rangeclone`, `eq`, `promoteclosure`,
`captureword`, `capturecell`) holds no `_`, so the word ends at the first one.

A declared type's segment starts with its class digit too (`4Point`, `5mymod_Ngx`), so no
type can spell a builtin's segment (`int`, `List`, `Option_str`) inside a carrier or a mono
name. A handler's or a template context's effect path leads with its part count
(`Handler2_A_B` is `A.B`), so the path ends where a reader can tell.

`tc_impl_method_stem` and `tc_impl_conv_stem` in typecheck.bl give both the signature
key of an impl method and the stem of its C symbol. Only the C stem spells a conversion's
source, with `seg_at` at TOP position. The signature key holds the impl node id in the
source slot: every reader of the key has the impl, and a second spelling of the source
could name an alias, or a source with binders, apart from the symbol.

A From or TryFrom impl with binders (`impl[T] From[List[T]] for Box[T]`) has one C
function per instance. `c_poly_method_name` spells the source with the instance's binders
filled in, then the binders as mono arguments, so From[List[T]] and From[Option[T]] on one
Box[T] stay apart.

## Name forms

| Form | Function | Inputs | Example |
|---|---|---|---|
| Function | `c_fn_decl_name(fn)` | fn decl node | `helper` in main -> `blink_2helper`; `main` -> `blink_main`; `@ffi("blink_getpid") fn getpid` -> `blink_getpid`; `@ffi("getpid") fn getpid` -> wrapper `blink_2getpid`; `ping` in `mymod` -> `blink_3mymod_ping` |
| Global let | `c_global_name(let)` | let node | `counter` in main -> `blink_2counter`; `mod_counter` in `mymod` -> `blink_3mymod_mod_1counter` |
| Mono fn instance | `c_mono_fn_name(fn, args_tid)` | fn decl node, interned tuple tid of the type args | `identity[Box[Int]]` -> `blink_2identity_04Box_10Int`; `my_fn[Int]` -> `blink_2my_1fn_0Int`; `wrap[Ngx]` from `mymod` -> `blink_3mymod_wrap_05mymod_1Ngx` |
| Type | `c_type_decl_name(td)` | type decl node | `Point` -> `blink_4Point`; `Ngx` in `mymod` -> `blink_5mymod_Ngx`; opaque `@ffi.opaque(name: "FILE")` -> `FILE*`; marked runtime-owned `ConversionError` -> `blink_ConversionError` |
| Type tag | `c_type_decl_tag(td)` | type decl node | `Ngx` in `mymod` -> `5mymod_Ngx`; opaque `CFile` -> `4CFile` |
| Mono type instance | `c_mono_type_c_name(tid)` | struct or enum instance tid | `Box[Option[Int]]` -> `blink_4Box_0Option_1int`; `Box2[Int]` in `mymod` -> `blink_5mymod_Box2_0Int`; `My_Box[Int]` -> `blink_4My_1Box_0Int` |
| Typedef | `c_typedef_name(tid)` | struct, enum, Option, Result or tuple tid | `Option[Int]` -> `blink_Option_int`; `Result[Void, Str]` -> `blink_Result_void_str`; `(Int, Str)` -> `blink_Tuple2_int_str` |
| Variant tag macro | `c_variant_tag_macro(td, v)` / `c_mono_variant_tag_macro(tid, v)` | type decl node or instance tid, variant node | `Shape.Circle` -> `blink_4Shape_Circle_TAG`; `Tree[Int].Leaf` -> `blink_4Tree_0Int_Leaf_TAG` |
| Derived method | `c_derive_method_name(td, m)` | type decl node, method | `Point` `eq` -> `blink_84Point_eq`; `User` `to_json` -> `blink_84User_to_1json` |
| Type helper | `c_promote_walker_name(tid)`, `c_values_eq_name(tid)`, ... | tid | `List[Int]` promote -> `blink_9promote_List_int`; `(Int, Str)` eq -> `blink_9eq_Tuple2_int_str` |
| Impl method | `c_impl_method_name(im, m)` / `_q(im, trait, m)` | impl node, method | `impl Greet for Point` `greet` -> `blink_6Point_Greet_greet`; `impl From[Int] for Point` `from` -> `blink_6Point_From_from_0Int`; `impl TryFrom[Int] for Char` -> `blink_7std_1char_Char_TryFrom_try_1from_0Int`; in `mymod` -> `blink_7mymod_Ngx_Greet2_greet2`; a trait `Tr` that modules `a` and `b` both declare -> `blink_6Point_Tr_2a_go` |
| Poly impl method instance | `c_poly_method_name(im, m, args_tid, source_tid)` | impl node, method, interned tuple tid of the impl binders, source tid with them filled in (-1 unless From or TryFrom) | `impl[T] From[List[T]] for Box[T]` at `Int` -> `blink_6Box_From_from_0List_1int_0Int` |
| Display dispatcher | `c_display_dispatch_name(im)` | impl node | `blink_6Point_Display_display` |
| Segment | `c_seg_top(tid)` / `c_seg_inner(tid)` | tid | `Int` -> `Int` / `int`; `Float` -> `Float` / `double`; `Map[K, V]` -> `Map` / `map`; `Point` -> `4Point` / `4Point`; `Ngx` in `mymod` -> `5mymod_Ngx` / `5mymod_Ngx`; fn type -> ICE / `closure` |
| Kops table | `c_kops_table_name(tid)` | key tid | `Int` -> `blink_kops_i64`; `Str` -> `blink_kops_str`; struct, enum or tuple -> `kops_` + typedef name (`Key` -> `kops_blink_4Key`, `(Int, Str)` -> `kops_blink_Tuple2_int_str`); opaque handle -> ICE segment, its C name is a pointer |
| Typedef guard | `td_guard_name(c)`, `td_guard_open_lines(c)`, `td_guard_close_line()` | C name | `BLINK_TD_blink_4Point`, `#ifndef ...` + `#define ...`, `#endif` |

## Mono stem

One private function, `mono_stem(base, args_start, args_count)`, builds every mono
name. It reads the type arguments from `ty_param_list`, spells each at TOP position,
escapes `_` as `_1` in every segment, and joins with `_0`. A fn instance and a struct or
enum instance both go through it.

The base is a symbol stem that already escaped its parts, so mono_stem does not escape it
again: `my_fn[Int]` -> `blink_2my_1fn_0Int`. No base holds `_0`, so the first `_0` opens
the arguments.

## Segment positions

- TOP: the type is a mono argument. Scalars are Pascal (`Int`, `Str`, `Float`). A
  bare struct is its full tag (`4Point`, `5mymod_Ngx`). An instance is its mono stem.
- INNER: the type sits inside a carrier or tuple. Scalars are the runtime tag
  (`int`, `str`, `double`, `list`, `map`, `closure`). A bare struct is its full tag,
  as at TOP. An instance is its mono stem.
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
