# cg_print.bl and cg_emit.bl

`src/cg_print.bl` is the C printer. It walks the IR from `src/ir.bl` and writes C
text through `src/cg_emit.bl`. `cg_emit.bl` owns the text buffer and the fixed C
forms of the ABI. Nothing else in the compiler writes C.

## What the printer owns

The printer decides:

- C syntax for each IR kind, and the parentheses around each value.
- The order of statements inside a block.
- Temporary names, and where a temporary is declared.
- Whether a value prints inline or binds a temporary first.
- The brace shape of `if`, `while`, a match chain and a scope block.

The printer does not decide:

- Any C type spelling. Every spelling comes from `layout_of` and sits on the node.
- Any C symbol or field name. Every name comes from `cname` or from lowering and sits
  on the node.
- Whether a value sits inline or behind a pointer. The `ir_held_by_pointer` accessor
  reads the node's slot form and answers.

The printer asks no type question. It imports only `cg_emit`, `ir` and `diagnostics`:
no typecheck, layout, mono, ast or cname module. It branches on no `TyKind` and
reads no type pool. Its only type-shaped input is one Bool from `ir`: does a value
sit behind a pointer. The driver passes each typedef guard name in as a string, so
the printer never calls `cname`. The script `scripts/lint_print_imports.sh` holds
both files to this rule.

`cg_emit.bl` has three mutable globals: the line buffer, the indent depth and the
temporary counter. They are the whole mutable state of emission. `cg_print.bl` adds
one private map from a node id to the name of its temporary.

## The inline rule

A value node prints inline into its parent as one C expression unless its
`must_materialize` flag is set. The printer binds a flagged node to a temporary once.
It writes the binding statement before the statement that consumes the node, in the
block that consumes it. Every later reach of the same node prints the temporary name.

The rule holds inside one block. A flagged node that two blocks reach, for example an
`if` arm and the statement after the `if`, would bind inside the arm where C cannot see
it later. Lowering must put such a value in a `Let` of its own; the verifier does not
check this yet.

When one C form joins several values, the printer binds each value in its own `let`
in source order before it joins the text. The holes of one interpolated string give no
promise about their evaluation order, so `f() + g()` binds `f` before `g` this way.
An lvalue always prints in place, even when a read of the same node bound a
temporary: a store into the temporary would land in a copy.

An expression statement follows the same rule. A flagged non-void value binds its
temporary and then prints `(void)_tN;`, so a later reach of the same node reuses the
temporary. A void value prints bare, because nothing can reach it again.

Lowering sets the flag for two shapes only: a node with an effect, and a node the
tree reaches more than once. The IR verifier rejects a shared node with no flag. So
the C keeps the nested expression shape that `gcc -O2` already handles well, and no
value is evaluated twice.

Three kinds always bind a temporary, because their C form needs more than one
statement: `Box` (allocate, then store), `ContainerNew` (construct, then append each
element) and `ClosureNew` with captures (fill the capture array, then construct).

An `ExprStmt` never binds a temporary for its own value. It evaluates the value once
and drops it.

An lvalue (the target of `Assign`, the object of `FieldSet`) prints in place. A
temporary would receive the store instead of the variable.

Temporary numbering restarts at zero in each function.

## ABI conventions

The forms below are the ones the archive in `build/gen0` was built against. Each
row names the helper in `cg_emit.bl` or the kind in `cg_print.bl` that writes it.

| Construct | C form | Writer |
|---|---|---|
| User TU prologue | `#define BLINK_USE_EXTERN_RUNTIME_STORAGE 1` then `#include "libblink_std.h"` | `em_prologue` |
| Standalone TU prologue | `#include "runtime.h"`; `BLINK_RUNTIME_STORAGE_DEFINE 1` when the TU owns storage | `em_prologue` |
| Typedef guard | `#ifndef BLINK_TD_<name>` ... `#endif` around one typedef | `em_td_guard_open` and `em_td_guard_close`, guard name from the driver |
| Struct | `typedef struct { T f; ... } <name>;` | `em_struct_typedef_body` |
| Tuple | struct with fields `_0`, `_1`, ... | `em_tuple_typedef_body` |
| Enum, no payload | `typedef enum { A, B } <name>;` | `em_simple_enum_typedef_body` |
| Enum, payload | `{ int tag; union { struct { ... } Variant; ... } data; }` plus a guarded `#define` per tag | `em_tagged_enum_typedef_body`, `em_tag_macro` |
| Option | `{ int tag; T value; }` | `em_option_typedef_body` |
| Result | `{ int tag; union { T ok; E err; }; }`; `blink_Result_str_str` is in runtime.h and is skipped | `em_result_typedef_body` |
| Function | `static RET sym(params, blink_ev* __ev)`; `(void)` when there are no parameters | `fn_signature` |
| Entry | `void blink_main(blink_ev* __ev)` | `print_fn` |
| Effect vtable | `{ RET (*slot)(params); ... void* __userdata_slot; ... }`: all function pointers, then one capture word per op, `void* __userdata;` alone when the effect has no op; a `<vtable>_default` instance in the same order | `em_effect_vtable_typedef_body`, `em_effect_default_vtable` |
| Key operations | `static uint64_t hash_<table>(const void* k)` and `static int eq_<table>(const void*, const void*)` adapters that cast `*(K const*)` into the by-value hash and eq methods, then `const blink_kops <table> = { hash, eq, sizeof(K), inline_key };` in the runtime's member order; `extern const blink_kops <table>;` for a TU that binds a table before or without its definition | `em_kops_table`, `em_kops_table_decl` |
| Effect vector | `blink_ev` with `io fs net crypto rand time env process` first, user effects after; `blink_ev_default()`; `__blink_ev` with the storage class the driver names, or only `extern blink_ev __blink_ev;` | `em_ev_typedef_body`, `em_ev_default_fn` |
| Effect perform | `__ev-><slot>(args)`; slot is `field->fn` | `EffectPerform` |
| Handler install | block with `__blink_ev_restore_t` cleanup guard, the field store, a copy of the vector and `blink_ev* __ev = &copy;` | `HandlerInstall` |
| Arena scope | block with `blink_arena_create`, `__blink_arena_restore_t` cleanup guard and `__blink_current_arena = arena;` | `WithScope`, one kid |
| Resource scope | block with `__blink_rs_state_<exit> guard __attribute__((cleanup(__blink_rs_cleanup_<exit>))) = { .resource = value, .ok = 0, .done = 0 };`, then `if (__blink_panic_armed) { __blink_cleanup_push(&guard, __blink_rs_run_<exit>, &guard.done); }`, the body, and `guard.ok = 1;` | `WithScope`, two kids; `em_resource_guard_open`, `em_resource_guard_ok` |
| Resource guard support | `typedef struct { T resource; int ok; int done; } __blink_rs_state_<exit>;`, a run-once `static void __blink_rs_run_<exit>(void* p, int ok)` that calls `<exit>(st->resource[, ok])`, and `static void __blink_rs_cleanup_<exit>(state*)` that pops the cleanup stack and runs it with the recorded ok; once per TU per exit symbol | `em_resource_guard_support` via `print_resource_guard_support` |
| Restore typedefs | both `__blink_*_restore_t` typedefs and their cleanup functions, once per TU | `em_scope_restore_support` |
| Closure thunk | `static RET __closure_N(const blink_closure* __self, params)` | `closure_thunk_params` |
| Closure new | `blink_closure_new_typed((void*)sym, caps, NULL, n, NULL)` | `ClosureNew` |
| Closure call | `((fn_type)cl->fn_ptr)(cl, args)`; a non-name closure binds first | `CallClosure` |
| Virtual call | `(recv)->slot(args)` | `CallVirtual` |
| Box | `T* p = (T*)blink_alloc(sizeof(T)); *p = v;` | `Box` |
| Unbox | `(*(p))` | `Unbox` |
| Field, carrier member, tag | `obj.f` when the object is inline, `obj->f` when it is pointer boxed | `FieldGet`, `CarrierUnwrap`, `CarrierTag` |
| Carrier wrap | `((T){.tag = t, .member = v})`; `((T){.tag = t})` with no payload | `CarrierWrap` |
| Struct or tuple new | `((T){a, b})`; `((T){0})` when empty | `StructNew`, `TupleNew` |
| Container new | `T c = ctor(); append(c, elems...)`; the append symbol is a table keyed on the constructor symbol | `ContainerNew` |
| Container spread | `extend(c, source);` in the place of the append for that kid, where `extend` is the kid's c_name (`blink_list_extend`) and `c` is the container under construction; a `ContainerSpread` anywhere else is the misplaced-kind ICE | `ContainerSpread` under `ContainerNew` |
| Match | `if (s == a) { } else if (s == b) { } else { }`; a non-name scrutinee binds first | `Switch` |
| Loop | `while (1) { }` | `Loop` |
| Panic | `__blink_panic_dispatch(msg); __builtin_unreachable();` | `Panic` |
| main | `GC_INIT`, `blink_map_init_seed`, argc and argv globals, `__blink_ev = blink_ev_default()`, `blink_trace_init` when the driver asks, stdlib globals in a user TU, then `blink_main(&__blink_ev)` | `em_main_shim` |

A match prints as an if chain, not a C `switch`. A `Break` or `Continue` inside an
arm must reach the enclosing loop, and a C `switch` would capture it.

`ContainerNew` for a map or set carries less than the old codegen did: the IR has no
slot for the key-operations table to pass to the constructor (the table itself is
printable through `em_kops_table`; the ctor slot is what is missing), so the printer
reports it as an `I0003` and writes a marker instead of a call that does not compile.
The gap has a ticket against `ir.bl`.

`ClosureNew` passes its descriptor table and promoter, or `NULL` for an empty slot.
`PromoteCtx` at an arena boundary prints `BLINK_PROMOTE_CTX(target)`, a stack context
for one promotion; in a walker it prints the parameter it names.

`StructNew` prints a positional compound literal, because the IR carries no field
names. The driver must pass the kids in declaration order.

## Misplaced kinds

A statement kind in value position, a value kind in statement position, or a
non-Block where a Block is required, is an internal compiler error with code
`I0003`. The printer reports it through `diag_ice` and writes a marker identifier
into the C so the failure is visible in the output. It never skips the node.

## How to add a kind

1. Add the kind to `ir.bl`: the enum, the constructor, `ir_all_kinds`,
   `ir_kind_name`, `ir_kind_is_value` and the verifier.
2. In `cg_print.bl`, add one arm to `expr_text` (a value kind) or `print_stmt` (a
   statement kind), and one `misplaced` arm to the other match. Both matches are
   exhaustive, so the compiler reports the missing arm.
3. If the kind needs a fixed C form that is not one expression or one statement,
   add a string helper to `cg_emit.bl`. The helper takes strings and reads no node.
4. Add the kind to `value_sample` or `stmt_sample` in
   `tests/test_cg_print_every_kind.bl`, and add its C form to the documented-form
   test.
5. Add a row to the table above.
