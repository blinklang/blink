# layout.bl

`src/layout.bl` is the one place a type id (tid) becomes a physical C answer.
It reads the interned type tree (`ty_pool`) and the type declaration nodes.
It does not read a codegen table, a flat CT code or a type-name string.

## The eight questions

| Function | Answer |
|---|---|
| `c_type_of(tid, position: Position) -> Str` | The C spelling of the tid in that position. Empty when the tid declines. |
| `carrier_tag_of(tid) -> Str` | The segment a carrier name is built from (`int`, `Point`, `Option_int`, `Box_0Int`). |
| `ensure_typedef_for(tid) -> Str` | Emits the guarded typedef for an Option, Result or Tuple (inner carriers first) and answers its C name. Other kinds emit nothing. The only side-effecting question. |
| `child_tid(tid, slot: Slot) -> Int` | A child tid by role: `Inner1`, `Inner2`, `Param(i)`, `Elem(i)`. `-1` when the kind has no such slot. |
| `tid_of_node(node) -> Int ! Diag.Report` | The recorded tid of an AST node. Raises `I0001` and answers `-1` on a node with no type. Never a default. |
| `tid_of_binder(scope, name) -> Int` | The tid bound to a name, walking parent scopes. `-1` when unbound. |
| `nominal_name_of(tid) -> Str` | The bare declared name of a struct or enum. `""` for every structural type. |
| `layout_of(tid, position) -> LayoutRecord` | All of the above in one record. Total, pure, memoised on `(tid, position)`. |

`LayoutRecord` fields: `c_spelling`, `slot_form`, `carrier_tag`, `is_transparent`,
`boxed_selfrec`, `kops_table`, `decline_reason`.

## Position

| Position | Effect on the answer |
|---|---|
| `Local`, `Param`, `Field`, `TupleElem` | The value is held by value. Aggregates are `Inline`; words are `InlineWord`. |
| `Return` | Same as `Local`, except `Void` and `Never` spell `void`. |
| `ContainerSlot` | A List, Map, Set or Channel element. A word stays `InlineWord`; an aggregate becomes `PointerBoxed` (the slot holds a pointer to a heap copy). The spelling is unchanged. |
| `VtableSlot` | A handler vtable entry. An Option over a boxed nominal payload spells `blink_Option_ptr`, because every handler of one effect shares one C signature. |

A word is a scalar, a runtime pointer type, an ordinal enum, a transparent newtype,
an opaque handle or an Option over an opaque handle.

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
  call it after `check_types`, because the pool is rebuilt.
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
  element is named `int` in the tuple tag, because it lowers to a bare `int64_t`.
