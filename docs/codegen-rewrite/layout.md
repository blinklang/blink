# layout.bl

`src/layout.bl` is the one place a type id (tid) becomes a physical C answer.
It reads the interned type tree (`ty_pool`) and the type declaration nodes.
It does not read a codegen table, a flat CT code or a type-name string.

It decides storage only. It spells no C symbol name of its own: every nominal C name,
carrier tag, typedef guard, handler vtable name and kops table name comes from
`cname.bl` (`c_typedef_name`, `c_type_decl_name`, `c_seg_inner`, `c_vtable_type_name`,
`c_kops_table_name`, `td_guard_*`). The C spellings of the fixed runtime kinds
(`int64_t`, `blink_list*`, ...) are layout facts and stay here. A name cname refuses
(an `ICE_SEG_*` sentinel) is a decline in `layout_of`; a refused carrier tag is an
empty `carrier_tag`. The import edge is one way: layout imports cname, cname never
imports layout or an emitter. `scripts/lint_import_dag.sh` asserts both.

## The eight questions

| Function | Answer |
|---|---|
| `c_type_of(tid, position: Position) -> Str` | The C spelling of the tid in that position. Empty when the tid declines. |
| `carrier_tag_of(tid) -> Str` | The segment a carrier name is built from (`int`, `Point`, `Option_int`, `Box_0Int`). |
| `ensure_typedef_for(tid) -> Str` | Emits the guarded typedef for an Option, Result or Tuple (inner carriers first) and answers its C name. Other kinds emit nothing. The only side-effecting question. |
| `child_tid(tid, slot: Slot) -> Int` | A child tid by role: `Inner1`, `Inner2`, `Param(i)`, `Elem(i)`. `-1` when the kind has no such slot. |
| `tid_of_node(node) -> Int ! Diag.Report` | The recorded tid of an AST node. Raises `I0001` and answers `-1` on a node with no type. Never a default. |
| `tid_of_binder(scope, name) -> Int` | The tid bound to a name, walking parent scopes. `-1` when unbound. |
| `nominal_name_of(tid) -> Str` | The declared name of a struct or enum, read from its declaration node. `""` for every structural type and when the declaration is missing or ambiguous. |
| `format_spec_of(tid) -> Str` | The printf conversion an interpolation hole or derived Debug uses for a value of the tid (`%lld`, `%llu`, `%g`, `%s`). `""` for a kind no conversion prints, which the caller renders through Display. A transparent newtype prints as its integer unless the program gives it a Display impl: then it answers `""`, so the hole calls that impl instead of printing the raw word. |
| `varargs_spelling(tid) -> Str` | The promoted width a value takes across C varargs (`long long`, `unsigned long long`). `""` when C already promotes it. |
| `layout_of(tid, position) -> LayoutRecord` | All of the above in one record. Total, pure, memoised on `(tid, position)`. |
| `field_layout_of(owner_decl, field_tid) -> LayoutRecord` | A field in its owner. See "Self-recursive fields". |
| `address_layout_of(tid, position) -> LayoutRecord` | The address of a value held at `position`: one `InlineWord` spelled as the value's spelling with one more `*` (`int64_t*`, `blink_Point*`, `double**` for a boxed container element). No carrier tag, no key table, no slot word. Declines with the value's reason, and by name for a void-like value, which is not a place. |
| `pointer_spelling(pointee: Str) -> Str` | The one place the C pointer star is written. `lo_spell_ptr`, `address_layout_of` and the verifier's address rule all read it. |
| `fn_pointer_spelling_of(tid, node) -> Str ! Diag.Report` | The C function-pointer type a closure's `fn_ptr` is cast to before a call: the result at `Return`, then `closure_self_spelling()`, then each parameter at `Param`, in declaration order (`int64_t(*)(const blink_closure*, int64_t)`). The one question that spells a whole Fn tid; `child_tid` reads its slots one at a time. A tid that is not a Fn, or a parameter or result whose layout declines (unbound metavar, free type variable), is `I0001` at `node` and answers `""`. |
| `closure_self_spelling() -> Str` | The receiver word every closure thunk takes first (`const blink_closure*`). The cast above and the thunk definition must agree on it. |

`LayoutRecord` fields: `c_spelling`, `slot_form`, `carrier_tag`, `is_transparent`,
`kops_table`, `kops_inline_key`, `slot_word`, `decline_reason`.

Layout writes the star nowhere else, and no other module writes it at all: a lowering that takes
`&x` asks `address_layout_of` for the node's spelling instead of reusing `x`'s.

`kops_inline_key` is the runtime's storage choice for a key that has a table: `true`
when the key's own bytes sit in the map or set slot (a word-sized key: scalar,
ordinal enum, transparent newtype), `false` when the slot holds a pointer to a heap
copy (struct, data enum, tuple). `Str` is `false`: `blink_kops_str` reads the slot's
pointer as the string itself. A key without a table answers `false`.

## Self-recursive fields

Whether a variant field is boxed because it reaches its own enum is a relation between
the owner and the field, not a fact about the field's tid: `Tree[Int]` is boxed inside
`Tree` and held by value inside `Holder { t: Tree[Int] }`. So it is not a
`LayoutRecord` field. `field_layout_of(owner_decl, field_tid)` answers it:

- The field is the owner itself (bare or any instance of it), or a tuple that reaches
  the owner at any depth: `PointerBoxed`, spelled `int64_t`. The owner's C typedef is
  incomplete while its own members are declared, so the member is an opaque word that
  holds the heap pointer.
- The field's declaration is ambiguous (`DECL_NODE_AMBIGUOUS`): a decline.
- Anything else: `layout_of(field_tid, Position.Field)`.

The comparison is on declaration nodes through `tc_tid_decl_node`, never on a name.

## Position

| Position | Effect on the answer |
|---|---|
| `Local`, `Param`, `Field`, `TupleElem` | The value is held by value. Aggregates are `Inline`; words are `InlineWord`. |
| `Return` | Same as `Local`, except `Void` and `Never` spell `void`. |
| `ContainerSlot` | A List, Map, Set or Channel element. The slot is a `void*`. A word stays `InlineWord` with its own spelling, except `Float`: a `double` is not punned through the word. `Float` and every aggregate become `PointerBoxed` and spell the pointer type (`double*`, `blink_Point*`) the reader casts the slot to and dereferences. |
| `VtableSlot` | A handler vtable entry. An Option over a boxed nominal payload spells `blink_Option_ptr`, because every handler of one effect shares one C signature. |

A word is a scalar, a runtime pointer type, an ordinal enum, a transparent newtype,
an opaque handle or an Option over an opaque handle.

`Bool` is a C `int` in every position. That is the width the runtime's Bool entry
points take and return and the width every emitted field, parameter and return has
always had. The key table a Bool-keyed map or set uses must copy and hash that same
width; a table that declares another width reads part of the key. Today the runtime's
`blink_kops_bool` declares one byte, so it reads the low byte of the `int` and is
right only on a little-endian target. The fix is on the runtime side, not here.

## Decline contract

`layout_of` never guesses. It declines (non-empty `decline_reason`, empty
`c_spelling`) when the tid is:

- `Unknown`, or a metavar that is still unbound;
- a free type variable;
- a generic struct or enum base that was not monomorphised;
- an Option, Result, Tuple or instance whose child declines;
- an instance whose argument is a closure, template or ffi scope (no mono stem grammar);
- an instance whose argument holds an undetermined type at any depth, even under a
  pointer container (the mono stem needs every segment).

A pointer container (List, Map, Set, Channel, Handle, Ptr, Fn) is one runtime type
whatever its child, so it does not decline. Its child declines on its own when asked.

The caller that needs a spelling turns a decline into `I0001`.

## Side effects and state

- `layout_memo` caches `layout_of` answers. `layout_reset()` clears every table;
  call it after `check_types`, because the pool is rebuilt. It also calls
  `cname_reset()` and re-marks the two declaration facts cname reads
  (`cname_mark_transparent_newtype`, `cname_mark_runtime_owned`). Until an annotation
  or typecheck owns those facts, this marking pass is their interim owner and the only
  place a type is known by its name (`Errno` with one `Int` variant; `ConversionError`
  and `ProcessResult`).
- `ensure_typedef_for` appends to an append-only buffer. Each block is wrapped in
  `#ifndef BLINK_TD_<name>` / `#define` / `#endif`. `layout_take_typedefs()` drains
  the buffer in emit order.
- Binder scopes: `binder_scope_push() -> Int`, `binder_scope_pop()`,
  `bind_binder(scope, name, tid)`. Typecheck scopes are transient, so the codegen
  driver records binders here for `tid_of_binder`.

## Aliases

A transparent alias (`type Port = Int`) has no C identity. Every question resolves
the alias to its underlying type first, so `Port` spells `int64_t`, tags `int` and
has no nominal name.

## Typedef shapes

- Option: `typedef struct { int tag; <inner> value; } blink_Option_<tag>;`.
  A struct, data enum, instance, carrier or tuple payload is `<inner>*`.
  A `Ptr` or `Handler` payload is `void*`, so one `blink_Option_ptr` serves every
  pointee and one `blink_Option_handler` every effect.
  An Option over an opaque handle emits nothing: the bare pointer is the Option.
- Result: `typedef struct { int tag; union { <ok> ok; <err> err; }; } blink_Result_<a>_<b>;`.
  `ok` is by value. A struct (not enum) `err` is `<err>*`. `Void` is `int64_t`.
  `blink_Result_str_str` comes from the runtime header and is not re-emitted.
- Tuple: one field per element, by value, `Void` as `int64_t`. A transparent newtype
  element is named `int` in the tuple tag, because it lowers to a bare `int64_t`
  (cname reads the transparent mark for that).
