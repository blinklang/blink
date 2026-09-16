# ir.bl

`src/ir.bl` is the typed lowered IR between monomorphisation and the C printer.
It is a tree, not SSA. Lowering builds it; the printer walks it. Nothing else
reads or writes it.

Every value node carries the `tid` of the value it produces and the C spelling
that `layout_of` gave that tid. The printer never asks a type question: it
never imports typecheck, layout, mono or ast, never branches on a TyKind and
never computes a C type spelling. Its only type-shaped input is `SlotForm`,
which says how a value is held, not what it is.

`ir.bl` contains no C spelling. Every `c_spelling` comes from `layout_of` and every
`c_name` comes from `cname` (or is a literal, an operator, a field name or a
runtime symbol the lowering already holds). The constructors take both as
parameters and store them.

## The node

```
IrNode {
    kind: IrKind
    tid: Int            // the tid of the value produced; 0 on a statement
    span: Int           // the AST node the IR node came from, for diagnostics
    c_spelling: Str     // layout_of(tid).c_spelling; the declared type on a Let
    c_name: Str         // the C token the kind prints verbatim (see the table)
    slot_form: SlotForm // Inline, PointerBoxed or InlineWord
    must_materialize: Int
    kids: List[Int]
}
```

Nodes live in one arena, a private list of records. A constructor returns a
node id. Ids are dense and stable until `ir_reset()`. A constructor copies
the kid list it receives, so a later change to the caller's list does not
reach the node. `ir_node(id)` copies a node out as a record, and `ir_kind`, `ir_tid`, `ir_span`, `ir_c_spelling`,
`ir_c_name`, `ir_slot_form`, `ir_must_materialize`, `ir_kids`, `ir_kid_count`
and `ir_kid` read one field. `ir_mark_materialize(id)` is the only mutation
after construction.

`ir_new(kind, tid, span, c_spelling, c_name, slot_form, kids)` is the raw
constructor. Tests use it to build shapes the verifier must reject. Lowering
uses the per-kind constructors below.

## Values and statements

A **value** node produces a C expression. It has a tid and a c_spelling. It
prints inline into its parent unless `must_materialize` is set.

A **statement** node produces C statements. Its tid is -1 (tid 0 is the first
interned type, `Int`) and its c_spelling is
empty, except `Let`, which holds the declared type. A statement has one owner:
the verifier rejects a statement reached twice even when it is flagged.

25 kinds are values. 15 kinds are statements.

## Inline rule

A value node prints inline unless `must_materialize` is set. Lowering sets the
flag for an effectful node and for a node the tree reaches twice, and for
nothing else. This keeps the nested expression shape that gcc -O2 already
optimises well. The flag is a hint to the printer about *where* a value is
computed; it does not change what the tree means.

`If`, `Switch` and `Block` are statements only. A value-position `if` or
`match` lowers to `Let` with no initialiser, followed by `Assign` inside each
arm, followed by a `VarRef`.

## The 41 kinds

The tables list kids in order. `n` is the kid count. A kid marked *value* must be
a value node; *stmt* any statement; *Block* the `Block` kind; *Const* the
`Const` kind; *lvalue* one of `VarRef`, `GlobalRef`, `FieldGet`, `Unbox`,
`CarrierUnwrap`.

### Values

| Kind | Constructor | Kids | c_name | slot_form |
|---|---|---|---|---|
| `Const` | `ir_const(tid, span, c_spelling, literal)` | none | the C literal text | `InlineWord` |
| `VarRef` | `ir_var_ref(tid, span, c_spelling, c_name, slot_form)` | none | the local's C identifier | caller |
| `GlobalRef` | `ir_global_ref(tid, span, c_spelling, c_name, slot_form)` | none | the global's C identifier | caller |
| `Unary` | `ir_unary(tid, span, c_spelling, op, operand)` | `[operand: value]` | the C operator; for `&` the spelling is `address_layout_of(...).c_spelling`, the operand's spelling plus `*` | `InlineWord` |
| `Binary` | `ir_binary(tid, span, c_spelling, op, lhs, rhs)` | `[lhs: value, rhs: value]` | the C operator | `InlineWord` |
| `Cast` | `ir_cast(tid, span, c_spelling, expr)` | `[expr: value]` | empty; c_spelling is the target type | `InlineWord` |
| `FieldGet` | `ir_field_get(tid, span, c_spelling, field, slot_form, obj)` | `[obj: value]` | the C field name | caller |
| `StructNew` | `ir_struct_new(tid, span, c_spelling, fields)` | `[field_0 .. field_n-1: value]` in declaration order | empty | `Inline` |
| `TupleNew` | `ir_tuple_new(tid, span, c_spelling, elems)` | `[elem_0 .. : value]` | empty | `Inline` |
| `ContainerNew` | `ir_container_new(tid, span, c_spelling, ctor_symbol, elems)` | `[elem_0 .. : value]` (Map: key, value, key, value ...); an element may be a `ContainerSpread` | the runtime constructor symbol | `InlineWord` |
| `ContainerSpread` | `ir_container_spread(tid, span, c_spelling, extend_symbol, source)` | `[source: value]` | the runtime copy symbol (`blink_list_extend`) | `InlineWord` |
| `Box` | `ir_box(tid, span, c_spelling, pointee_spelling, value)` | `[value: value]` | the pointee C type, the `sizeof` operand | `PointerBoxed` |
| `Unbox` | `ir_unbox(tid, span, c_spelling, slot_form, ptr)` | `[ptr: value]` | empty | caller |
| `CarrierWrap` | `ir_carrier_wrap(tid, span, c_spelling, member, tag, payload)` | `[tag: Const]` or `[tag: Const, payload: value]` | the payload member: `value`, `ok`, `err`; empty for None | `Inline` |
| `CarrierUnwrap` | `ir_carrier_unwrap(tid, span, c_spelling, member, slot_form, carrier)` | `[carrier: value]` | the member read | caller |
| `CarrierTag` | `ir_carrier_tag(tid, span, c_spelling, carrier)` | `[carrier: value]` | empty | `InlineWord` |
| `CallDirect` | `ir_call_direct(tid, span, c_spelling, symbol, slot_form, args)` | `[arg_0 .. : value]` | the C function symbol | caller |
| `CallIndirect` | `ir_call_indirect(tid, span, c_spelling, slot_form, callee, args)` | `[callee: value, arg_0 .. : value]` | empty | caller |
| `CallClosure` | `ir_call_closure(tid, span, c_spelling, fn_type, slot_form, closure, args)` | `[closure: value, arg_0 .. : value]` | the C function-pointer type the `fn_ptr` is cast to | caller |
| `CallVirtual` | `ir_call_virtual(tid, span, c_spelling, slot, slot_form, receiver, args)` | `[receiver: value, arg_0 .. : value]` | the vtable slot name | caller |
| `CallRuntime` | `ir_call_runtime(tid, span, c_spelling, symbol, slot_form, args)` | `[arg_0 .. : value]` | a `blink_*` runtime symbol | caller |
| `ClosureNew` | `ir_closure_new(tid, span, c_spelling, fn_symbol, captures)` | `[capture_0 .. : value]` | the lifted function's C symbol | `InlineWord` |
| `EvidenceVector` | `ir_evidence_vector(span, c_spelling, c_name, slot_form)` | none | `__ev` (PointerBoxed param) or `__blink_ev` (Inline global) | caller |
| `EvidenceAddress` | `ir_evidence_address(span, vector)` | `[vector: EvidenceVector held inline]` | empty; the vector owns the name | `InlineWord` |
| `EffectPerform` | `ir_effect_perform(tid, span, c_spelling, slot, slot_form, slot_read, args)` | `[slot_read: FieldGet over an EvidenceVector, held by pointer; arg_0 .. : value]` | the handler vtable slot | caller |

`ContainerSpread` is `[..xs, y]`: it copies every element of its source into the
container being built. It is legal only as a direct kid of `ContainerNew`, so the
destination it extends is the container the printer is building and no node
has to name it. Its tid and c_spelling are the source container's. The printer
writes it as `<extend_symbol>(<tmp>, <source>)` in place of the append for that
kid; a `ContainerSpread` reached anywhere else is a misplaced-kind ICE.

`EvidenceAddress` is what a call to an effectful function passes for the vector
parameter when the caller holds the global instance inline rather than a vector
parameter of its own. The printer writes it as `(&__blink_ev)`.

It is a kind of its own rather than a `Unary` `&` over an `EvidenceVector`. The
vector has no Blink type, and nor has its address, so a `Unary` holding it would
be a value node with tid -1: the verifier would have to exempt it by sniffing the
operator string and the operand's kind, and an untyped value node would survive
in the IR under a kind whose every other use is typed. A kind carries the
exemption instead, where it is one named rule the verifier reads off the kind
rather than a rule that reads a c_name string to decide whether a tid is
required.

The operand is a kid rather than nothing, so `c_spelling` is the pointer form of
the operand's spelling under the same rule that holds a `Unary` `&`, and `cname`
stays the one producer of both the vector's type name and its C name: ir.bl never
has to know either. The operand must be held inline, because a vector parameter
is already the address of a vector and its address would be a `blink_ev**`.

`Box.c_spelling` is the pointer type the node produces. `Box.c_name` is the
pointee type; the printer uses it as the `sizeof` operand for the heap copy.

`CarrierWrap` carries its tag as a `Const` kid so the printer writes
`{.tag = <kid 0>, .<member> = <kid 1>}` with no knowledge of which carrier it
is. A `CarrierWrap` with one kid prints only the tag designator. With two kids
its `c_name` must name the member.

A call that returns `Void` still has a tid (the tid of `Void`) and the
spelling `void`. Its parent is an `ExprStmt`.

### Statements

| Kind | Constructor | Kids | c_name |
|---|---|---|---|
| `FieldSet` | `ir_field_set(span, field, obj, value)` | `[obj: value, value: value]` | the C field name |
| `HandlerInstall` | `ir_handler_install(span, ev_field, handler_value, body)` | `[handler: value, body: Block]` | the `__ev` field the handler is stored in |
| `Let` | `ir_let(tid, span, c_spelling, c_name, slot_form, init)` | `[]` or `[init: value]` | the local's C identifier |
| `Assign` | `ir_assign(span, target, value)` | `[target: lvalue, value: value]` | empty |
| `ExprStmt` | `ir_expr_stmt(span, expr)` | `[expr: value]` | empty |
| `Return` | `ir_return(span, value)` | `[]` or `[value: value]` | empty |
| `If` | `ir_if(span, cond, then_block, else_block)` | `[cond: value, then: Block]` or `[cond, then, else: Block]` | empty |
| `Loop` | `ir_loop(span, body)` | `[body: Block]` | empty |
| `Break` | `ir_break(span)` | none | empty |
| `Continue` | `ir_continue(span)` | none | empty |
| `Block` | `ir_block(span, stmts)` | `[stmt_0 .. : stmt]` | empty |
| `Switch` | `ir_switch(span, scrutinee, cases, default_block)` | `[scrutinee: value, (label: Const, body: Block)*, default: Block?]` | empty |
| `WithScope` | `ir_with_scope(span, cleanup_symbol, resource, body)` | `[body: Block]` or `[resource: value, body: Block]` | the resource's exit symbol (close, exit or blink_ffi_scope_cleanup), from which the printer spells the guard family; empty for a plain arena scope |
| `Panic` | `ir_panic(span, message)` | `[message: value]` | empty |
| `Unreachable` | `ir_unreachable(span)` | none | empty |

`Let` is the one statement that takes a tid and a c_spelling: it declares the
local's type. `init < 0` declares without initialising.

`Switch` is the only match target. After the scrutinee, an even number of kids
is all `(label, body)` pairs; an odd number ends with the default `Block`.
`Loop` is an infinite loop; `while` lowers to `Loop` over `If cond {} else
{Break}`.

A negative id passed for an optional kid (`payload`, `init`, `value`,
`else_block`, `default_block`, `resource`) means "absent".

## Verifier

`ir_verify(root) -> List[Str]` returns an empty list on a well-formed tree.
Each message about a node begins `node <id> (<Kind>): `; the root message
begins `root <r>: `. It rejects:

| Defect | Message tail |
|---|---|
| root id outside the arena | `root <r>: node id out of range (arena holds <n>)` |
| kid id outside the arena | `kid <i> id <k> out of range (arena holds <n>)` |
| a node that contains itself | `cycle, the node contains itself` |
| a value node with tid < 0 | `value node without a tid` |
| an `EvidenceVector` with tid >= 0 | `carries tid <t>, the vector has no Blink type` |
| an `EvidenceAddress` with tid >= 0 | `carries tid <t>, the address of the vector has no Blink type` |
| an empty c_spelling on a value or a `Let` | `empty c_spelling` |
| an empty c_name where the kind prints one | `empty c_name` |
| a `Unary` `&` or an `EvidenceAddress` whose spelling is not the pointer form of its operand's | `address spelled '<s>', the pointer form of its operand's '<o>' is '<o>*'` |
| a `Binary` `&&`/`\|\|` whose right operand binds a statement (see `ir_binds_statement`) | `right operand of '<op>' binds a statement the operator cannot skip` |
| wrong kid count | `expects <n> kids, has <m>`, `expects <lo> or <hi> kids, has <m>`, `expects at least <n> kids, has <m>` |
| statement in a value slot | `kid <i> is a statement where a value is required` |
| value in a statement slot | `kid <i> is a value where a statement is required` |
| non-Block where a Block is required | `kid <i> must be a Block` |
| non-Const Switch label | `kid <i> case label must be a Const` |
| `EffectPerform` kid 0 not a `FieldGet` over an `EvidenceVector` | `kid 0 must read a handler slot of the EvidenceVector, is a <Kind>` |
| `EffectPerform` kid 0 held by value | `handler slot must be held by pointer, a handler is a vtable pointer` |
| `EvidenceAddress` kid 0 not an `EvidenceVector` | `kid 0 must be the EvidenceVector, is a <Kind>` |
| `EvidenceAddress` kid 0 held by pointer | `kid 0 is already held by pointer, a vector parameter is its own address` |
| non-Const CarrierWrap tag | `kid <i> tag must be a Const` |
| non-lvalue Assign target | `kid <i> target must be an lvalue` |
| ContainerSpread not directly under ContainerNew | `ContainerSpread outside a ContainerNew` |
| value reached twice, flag clear | `value reached twice without must_materialize` |
| statement reached twice | `statement reached twice, a statement has one owner` |

The kinds that print a c_name: `Const`, `VarRef`, `GlobalRef`, `Unary`,
`Binary`, `FieldGet`, `FieldSet`, `ContainerNew`, `ContainerSpread`, `Box`, `CarrierUnwrap`,
`CallDirect`, `CallClosure`, `CallVirtual`, `CallRuntime`, `ClosureNew`,
`EvidenceVector`, `EffectPerform`, `HandlerInstall`, `Let`, and `CarrierWrap` with a payload.
`CarrierWrap` without a payload and `WithScope` take a c_name that may be empty.

`ir_binds_statement(id) -> Bool` says whether printing the value at `id` writes a
statement before the expression that reads it: a `Box`, a `ContainerNew` or
`ClosureNew` with elements, a node with `must_materialize` set, or any node above
one of those. C's `&&` and `||` skip the right operand but not a statement bound
for it, so a lowering that finds a binding right operand guards it with a temp and
an `if` instead of building the `Binary`. The left operand always runs, so it may
bind.

## Dump

`ir_dump(root) -> Str` is an s-expression, one node per line, two spaces per
depth:

```
(Kind [#k] tid span SlotForm must_materialize "c_spelling" "c_name"
  kid...)
```

Node ids do not appear, so two arenas holding the same tree dump the same
text. A node reached more than once gets a label `#k` after its kind at its
first occurrence; each later reach prints the bare `#k` in place of the node.
Labels count from 0 in dump order. A kid id outside the arena prints as
`(out-of-range <id>)`; a root id outside the arena dumps as that text alone.
Strings escape `"`, `\` and newline.

`ir_parse(text) -> Int` reads the dump back into fresh nodes and returns the
root id, or -1 on malformed text. A `#k` reference binds to the labelled node,
so sharing survives the round trip. A reference before its label (which only a
cyclic tree dumps) is malformed. A future `--emit ir` flag will print
`ir_dump`; this change does not wire it.

Kind helpers: `ir_all_kinds()`, `ir_kind_name`, `ir_kind_from_name`,
`ir_kind_is_value`.

## Open notes

- `ClosureNew` has no slot for a capture descriptor or promoter symbol beyond
  `fn_symbol`. If the closure ABI needs per-capture promotion the lowering
  must emit it as `CallRuntime` kids first.
- `c_name` carries a different C token per kind (literal, operator, field,
  member, symbol, slot, cast type). The table above is the contract; the
  printer switches on `kind`, never on the string.
- A value-position `if` or `match` costs a `Let` plus one `Assign` per arm.
  gcc -O2 folds this; whether it matches today's C byte for byte is not a gate.
