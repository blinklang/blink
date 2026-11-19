# One resolution record per node

## Context

The design panel chose an annotated AST by a 5-0 vote (DECISIONS.md):
typecheck decorates nodes with resolution results, and codegen reads the
decorations. Today the decorations exist, but they are eighteen tables (see
[Inventory](#inventory)) with different keys and value types.
Some readers decide the same fact again by spelling, by name, or by a second
solver. A record that stops this must meet three requests:

- **Callee kind.** Typecheck writes, for each call and name, the callee kind and
  the declaration or built-in id. Lowering switches on this record.
  Typecheck, the arity check and lowering read one built-in method table. An
  entry with no lowering then fails a gate. The user does not get an internal
  error.
- **Name meaning.** After the name pass, each name node has a declaration, a local
  binder, a built-in role, or an error that typecheck already reported. One
  verifier enforces this. Declaration ids are the keys, not spellings. The
  receiver role of `a.f(..)` is decided once, in the name pass, and codegen
  reads it.
- **Binder tids.** A table keyed by call or reference node holds the binder tids
  in binder order, impl binders included. Typecheck fills it. At
  finalization, each entry resolves or is E0301. Mono substitutes the binds of
  the instance into the entry, and does not solve again. Callee identity
  (a declaration node) goes in the same record.

This note designs one record that serves the three requests. It names each
slot, the writer, the readers, the phase where a verifier asserts that the
record is complete, and
the internal error when a reader finds a slot empty. It also names the current
code that each slot replaces. It changes no code and no spec text. The open
design choices are in [Questions](#questions).

Line numbers are at commit fc83d455.

## The record

The record has five slots. A node gets only the slots that apply to its kind
(see [Which nodes have a record](#which-nodes-have-a-record)).

| Slot | Holds | Written in | Readable from |
|---|---|---|---|
| `decl` | a declaration node, a local binder node, or a built-in id | name pass, then inference for method calls | end of the name pass for names; end of inference for method calls |
| `role` | the receiver role of `obj` in `obj.f(..)` and `obj.f` | name pass | end of the name pass |
| `kind` | the callee kind of a call or a value reference | inference | end of inference (before the flush) |
| `binds` | binder tids in binder order: fn binders, then impl binders | inference | after the finalization flush |
| `self_target` | the target tid that `Self` names at this node | name pass | end of the name pass |

### Slot `decl`: what the name means

**Holds.** One of:

- a declaration node (fn, let, type, variant, trait, effect, method, op),
- a local binder node (a parameter, a `let`, a pattern binder, a closure
  parameter),
- a built-in id: an entry in the one built-in table (see slot `kind`), for a
  name or a method that no source declaration answers, such as `xs.len()` on
  a `List` or `io.println(..)`.

An error that typecheck already reported is a fourth state. It is not an empty
slot. Readers do not see it, because lowering does not run on a program with
errors.

**Writer.** The name pass (`resolve_names`, `src/typecheck.bl:32019`) for
identifiers, qualified paths and static calls. Inference for method calls on
a value, because the receiver type decides the method.

**Readers.**

- mono: `discover_call` and `discover_module_call` find the callee by this
  slot, and not by name.
- lowering: `lower_ident` (`src/cg_expr.bl:579`), `lower_fn_value`
  (`src/cg_call.bl:2159`), and the call lowering.
- the effect walkers, through `tc_call_facts`.
- import use and E1005, which derive their answers from the record.
- tools (`blink query`, go-to-definition).

**Replaces.**

| Today | Site | Readers today |
|---|---|---|
| `tc_call_decl` / `tc_call_decl_node` | `src/typecheck.bl:25888`, `:25892` | typecheck, mono (6), cg_call (4), cg_eff (2), escape (3), mutation_analysis (2) |
| `tc_global_read_decl` / `tc_global_decl_node` | `src/typecheck.bl:26016`, `:26025` | typecheck, cg_expr, cg_stmt, escape, mutation_analysis |
| `tc_module_global_decl` | `src/typecheck.bl` | typecheck, cg_expr |
| `tc_fn_value_decl_node` | `src/typecheck.bl:26048` | typecheck, mono, cg_expr |
| `tc_local_binder` / `tc_ident_binder_node` | `src/typecheck.bl:26074`, `:26078` | typecheck, escape, mutation_analysis |
| `tc_intrinsic_calls` | `src/typecheck.bl:43413` | typecheck, codegen |
| `tc_call_declared_name` (a name, not a node) | `src/typecheck.bl` | mono, cg_call, cg_stmt, escape, mutation_analysis |
| the binder lookup by name in lowering (`x_is_local`, `binder_c_local_name`) | `src/cg_expr.bl:586`, `:592`, `:641`; `src/cg_stmt.bl:189`; `src/cg_eff.bl:597`, `:1629` | lowering |
| the name fallbacks in mono: `generic_fns.by_name`, `poly_methods.by_name`, `own_generic_methods.by_name` | `src/mono.bl:1059`, `:1138`, `:1168`, `:1350`, `:1364` | mono |
| `nr_resolve_qualified_decl`, which returns -1; `nr_note_call_decl` then records nothing and goes on | `src/typecheck.bl:26414`, `:25998` | name pass |

**Empty slot.** A name or call node that reaches mono or lowering with no
`decl` and no reported error. Today this shows as `NameNotBound`
(`src/cg_expr.bl:617`, I0004) or as a by-name miss in mono.

### Slot `role`: what the receiver is

**Holds.** One value of the `Receiver` enum that is now in
`src/cg_call.bl:6720`: `Value`, `Namespace`, `Module`, `TypeOwner`,
`TraitOwner`, `EffectHandle`, `BuiltinDefault`. The enum moves to typecheck.

**Writer.** The name pass, at the `obj` of each method call and field read.
The receiver-role work sets the order of the rules. It uses the spec order
and the handle rule. This note defines only the slot, its values and its
writer.

**Readers.** `lower_method_call` (`src/cg_call.bl:4091`), its first tests.
mono (`tc_mc_obj_is_value` has 5 reads in `src/mono.bl`). The effect
walkers.

**Replaces.** Two ordered chains of tests that decide the role, each by
spelling:

- codegen: `cc_receiver_role` (`src/cg_call.bl:6739`). Its order is
  `cc_is_free_name`, `tc_mc_obj_is_value`, `tc_call_user_effect`,
  `tc_call_builtin_default`, `tc_namespace_call_reads_module`,
  `is_builtin_namespace`, `is_import_module_name`, `tc_call_trait_head`,
  `tc_names_a_type`, `tc_names_a_trait`, then `Value`.
- typecheck: the same tests, spread over the name pass and inference.
  `is_builtin_namespace` alone has eleven call sites in
  `src/typecheck.bl` (for example `:22906`, `:27196`, `:30620`, `:31175`,
  `:31401`, `:33860`, `:34069`, `:47523`, `:47582`).

This slot also replaces the tables that the codegen chain reads:
`tc_mc_obj_value_marks` (`src/typecheck.bl:176`, read through
`tc_mc_obj_is_value` `:38389`), `tc_call_user_effect` (`:22691`),
`tc_call_builtin_default` (`:23374`), `tc_namespace_call_reads_module`
(`:22722`), `tc_call_trait_head` (`:29847`), `builtin_heads` and
`trait_heads` in `CallFacts` (`:3673`, `:3679`).

**Empty slot.** A method call or field read whose `obj` reaches lowering with
no role.

### Slot `kind`: what kind of callee

**Holds.** The callee kind, and for a built-in callee the id of its entry in
one built-in table. The `CallReach` enum (`src/typecheck.bl:51629`) is the
nearest thing today: `HandleOp`, `UserOp`, `DefaultOp`, `TraitImpl`,
`TraitBound`, `Fn`, `LetValue`, `Variant`, `Value`, `Builtin`,
`BuiltinMethod`, `Derived`, `BuiltinRecvImpl`, `Poison`, `Unknown`.

The built-in table is the one list of built-in methods and calls: its key is
the receiver kind and the method, and each entry has its typecheck answer, its
arity and its lowering. Typecheck writes the entry id into the record.
Lowering reads the id and does not look at the method string.

**Writer.** Inference. The kind of a method call depends on the receiver
type.

**Readers.**

- lowering: the tests of `lower_method_call` after the role tests
  (`src/cg_call.bl:4100`-`:4142`) and `cc_impl_method_call` (`:4144`).
- the two effect walkers, `tc_check_trace_messages`
  (`src/typecheck.bl:44141`) and `tc_check_effect_rows` (`:52623`), which
  read `tc_call_facts` today (`:44302`, `:44432`, `:51795`), before the
  flush.
- arity checks.

**Replaces.**

- the `(kind, method string)` tests of `lower_method_call`: 93 lines of
  `method == "..."` in `src/cg_call.bl`, `cc_intrinsic_callee` (`:6155`) and
  its per-kind tables, `cc_runtime_method` and `cc_runtime_method_arity`
  (`:4596`, `:4614`), `cc_method_not_built` (`:6530`).
- `is_intrinsic_method` (`src/typecheck.bl:51030`). It must be a superset of
  what lowering builds, and nothing checks that.
- `tc_call_facts` (`src/typecheck.bl:51664`), `tc_call_decl_facts` and
  `tc_call_kind_no_decl`. These compute `CallReach` again at each read, and
  `tc_call_kind_no_decl` reads `static_owners` and `builtin_heads` by
  spelling.
- `tc_call_trait`, `tc_call_bound_trait_args`, `tc_call_reaches_user_trait`,
  `tc_call_reaches_trait_method`, `tc_method_value_trait` (`:29836`), as far
  as they say which kind of callee a call reaches.

**Empty slot.** Today: `CALL_ROW_UNKNOWN` I0025
(`tc_report_call_row_unknown`, `src/typecheck.bl:51784`) in the effect
walkers, and `UnresolvedMethodAtCodegen` I0022 (`src/cg_call.bl:237`, `:244`)
or `cc_method_not_built` in lowering. With the record, a built-in table entry
that has no lowering fails a gate, not a user build.

### Slot `binds`: the binder tids

**Holds.** A list of tids in binder order: the binders of the callee fn, then
the binders of its impl. One list for each generic call, each generic static
call through a type head, each method call through an impl with binders, and
each reference to a generic fn or method as a value. Explicit type arguments
(`f[Int](..)`) fill the same list.

A tid in the list can hold a type parameter of the enclosing declaration
(the I0024 rule allows this). The list is keyed by the node, not by the node
and an instance. Mono gets the list for one instance by substituting the
binds of that instance into it.

**Writer.** Inference, at each call it checks. Today this is
`tc_note_generic_call` (`src/typecheck.bl:4182`) for fn binders,
`tc_calls.static_head_binders` (`:3631`, written at `:19915`) for a static
call through a type head, `tc_calls.impl_bound_binds` (`:3636`) for calls
through an impl with binders, `tc_generic_fn_value_tid` (`:7115`) for fn
values, and `tc_seed_mint_group` (`:42477`) for explicit type arguments.

**Readers.** mono: `instance_for_call` (`src/mono.bl:276`), `binder_args`
(`:694`), `discover_call` (`:1047`), `discover_fn_value` (`:1068`),
`reference_binds` (`:1111`), `discover_module_call` (`:1130`),
`discover_method_call` (`:1439`). The bound judge at finalization
(`tc_check_fn_value_bounds` `:5175`, `tc_ud_flush_calls` `:4926`).

**Replaces.**

- `solve_call_binds` (`src/mono.bl:660`; callers at `:1032`, `:1113`,
  `:1333`, `:1405`, `:1832`) and `unify` (`:614`; callers outside
  `solve_call_binds` at `:1121`, `:1125`, `:1617`). These solve the binders a
  second time from the stamped tids.
- `tc_ret_mint_at` (`src/typecheck.bl:7959`), `tc_ret_mint_start` and
  `tc_ret_mint_tids` (`:212`-`:213`), read by `binder_args`
  (`src/mono.bl:709`).
- `tc_calls.open_tids`. `tc_note_generic_call` (`:4182`) writes it only
  when `tc_boundary_check_active != 0`. `tc_note_void_return` (`:4630`) and
  `tc_note_fn_value` (`:4670`) write it with no such check. The E0301 / Hash
  flush reads it. Inference also reads it in `tc_generic_fn_value_tid`
  (`:7117`), and so do `tc_ud_blame_call_after_error` (`:3866`),
  `tc_check_fn_value_bounds` (`:5177`), `tc_defer_assoc_fn_ref` (`:30866`)
  and `tc_flush_assoc_fn_refs` (`:30886`). `tc_drop_open_calls` (`:5432`)
  drops it before mono.
- `static_head_binders` and `impl_bound_binds`: the impl part of the list
  replaces them. Mono reads `static_head_binders` today
  (`tc_static_head_binders`, `src/mono.bl:1262`). This is one of the places
  where mono already reads a record and does not solve (`binder_args` with
  `tc_ret_mint_at` is another).
- the fn value re-solve in `discover_fn_value`, which reads stamps and not a
  record.

**Empty slot.** Today: `MonoUnsolvedTypeParam` (`src/mono.bl:714`, `:1414`)
and `MonoInstanceNotRegistered` (`src/cg_call.bl:444`, `:941`, `:2356`;
`src/cg_eff.bl:290`), both under I0001.

### Slot `self_target`: what `Self` names

**Holds.** The target tid that `Self` names at a node in an impl body, at the
binders of the impl.

**Writer.** The name pass, in the walk of an impl body.

**Readers.** typecheck after the name pass, mono, lowering
(`tc_head_decl_tid_at`, `src/typecheck.bl:15106`, has one read in
`src/cg_expr.bl`, `:2133`).

**Replaces.** `self_heads` (keyed by the `obj` node) and the `Self` entries in
`static_owners` (keyed by the call node, written at `src/typecheck.bl:15120`),
both in `CallFacts`. A separate request already asks for a table of `Self`
targets keyed by node. This slot is that table.

**Empty slot.** A `Self` head in an impl body that reaches lowering with no
target.

## Which nodes have a record

| Node | `decl` | `role` | `kind` | `binds` | `self_target` |
|---|---|---|---|---|---|
| identifier as a value | yes | | yes when it names a fn | yes when it names a generic fn | |
| identifier in a type, trait, effect or impl head | yes | | | | |
| `Self` in an impl body | | | | | yes |
| qualified path `A.b` | yes | yes | | | |
| call `f(..)` | yes | | yes | yes when generic | |
| method call `o.m(..)` | yes | yes | yes | yes when generic or through an impl with binders | |
| method read `o.m` / `T.m` as a value | yes | yes | yes | yes when generic | |
| pattern head (variant, `Self.V`) | yes | | | | yes when `Self` |

Names in type annotations, trait references, effect references, patterns
and impl heads also need the `decl` slot. Today `tc_call_decl` covers only
calls.

## Assertions

There are two kinds of assertion. Keep them apart.

### Completeness

One verifier runs at the end of typecheck, in `tc_stamp_program`
(`src/typecheck.bl:50967`). This is after the finalization flush
(`tc_flush_program_deferrals`, `:49002`, called at `:48992`). The verifier
walks each node. It checks that each slot that applies to the node kind holds
a value. It runs next to the `NodeCarriesNoType` (I0001, `:50465`) and
`OpenTypeAfterCheck` (I0024, `:50478`) checks in `tc_stamp_assert`
(`:50404`).

- It runs in each build and in `blink check`, not only in the gate.
- It does not run when the program has an error, as `tc_stamp_program` does
  today. A node with a reported error is complete.
- For `binds`, each entry resolves or has an E0301. This is the one bound
  judge at finalization.

### Agreement (temporary)

While the old code is still there, mono and lowering check that the old code
and the record give the same answer:

1. mono: the result of `solve_call_binds`, `unify` and `binder_args` equals
   the `binds` slot after substitution. The callee that mono finds by name
   equals the `decl` slot.
2. lowering: `cc_receiver_role` equals the `role` slot. The test that
   `lower_method_call` takes agrees with the `kind` slot.
3. lowering: `lower_ident` finds the same binder or declaration as the `decl`
   slot.

Each check goes away with the old code it compares. Its first job is to
measure whether the two sides ever disagree.

### Phase where each slot is readable

| Slot | Readable from | Early readers |
|---|---|---|
| `decl` (names) | end of the name pass | inference |
| `role` | end of the name pass | inference, effect walkers |
| `decl` (method calls), `kind` | end of inference for the fn body | the two effect walkers (`tc_check_trace_messages`, `tc_check_effect_rows`), before the flush |
| `binds` | after the finalization flush | mono only |
| `self_target` | end of the name pass | inference |

A read before the slot is readable is a bug in the reader. The note does not
say if the record checks this at run time (see Questions).

## Late writes

### A node inferred two times

Inference can check one node more than once. A later walk mints new
metavariables. Today `tc_note_generic_call` unifies the old group with the
new group (`src/typecheck.bl:4182`). The `binds` slot needs the same rule, or
a rule that replaces the old list. The rule must be the same for all writers
of `binds` (see Questions).

### Nodes that change after typecheck

`desugar_sealed_ops_calls` (`src/typecheck.bl:38411`) runs once, after
typecheck and before mono (`src/check_pipeline.bl:23`). It rewrites
`StrOps.len(s)` into `s.len()`. The node keeps its id. The rewrite sets the
`obj` value mark (`tc_mc_obj_value_marks`), and for an identifier receiver the
name-position mark (`tc_name_position_is_value`, `src/typecheck.bl:38461`). It
checks that the call has no
`decl` (`SealedOpsCallHasDeclaration`, I0009). With the record, the rewrite
must write the `role` slot (`Value`) and keep `kind`. It is the only writer
after typecheck.

Typecheck adds a `NamedArg` node for each default argument that a call does
not write (made at `src/typecheck.bl:9313`; `tc_is_default_fill`, `:9326`,
tests for it). Its value is the
default expression of the callee, one node for all calls. Lowering reads it
in the instance of the callee (`cc_default_fill_instance`,
`src/cg_call.bl:6992`). So the records inside a default expression are like
the records inside a generic body: the callee writes them once, and mono
substitutes. The fill node itself needs a record only if a reader asks for
one (see Questions).

## Inventory

Each per-node table today, and the slot that replaces it.

| Table today | Key | Value | Slot |
|---|---|---|---|
| `tc_call_decl` | call node | decl node | `decl` |
| `tc_global_read_decl` | ident / field / call-through-value node | decl node | `decl` |
| `tc_local_binder` | ident node | binder node | `decl` |
| `tc_intrinsic_calls` | call node | intrinsic number | `kind` |
| `tc_mc_obj_value_marks` | call node | 0 / 1 | `role` |
| `tc_name_position_is_value` | ident node | 0 / 1 | `role` |
| `CallFacts.static_owners` | call node | type name (Str) | `decl`, `self_target` |
| `CallFacts.self_heads` | `obj` node | tid | `self_target` |
| `CallFacts.builtin_heads` | node | (set) | `role` |
| `CallFacts.trait_heads` | node | trait name (Str) | `role`, `decl` |
| `CallFacts.builtin_static_reads` | access node | owner and name (Str) | `decl`, `kind` |
| `CallFacts.static_head_insts` | call node | instance tid | `binds` |
| `CallFacts.static_head_binders` | call node | tid list | `binds` |
| `CallFacts.impl_bound_binds` | call node | `ImplBoundCall` | `binds` |
| `CallFacts.method_values` | node | `MethodValueRef` | `kind`, `binds` |
| `CallFacts.method_reads` | node | `MethodRead` | `kind`, `binds` |
| `tc_calls.open_tids` | group list | tids | `binds` |
| `tc_ret_mint_tids` | (by start) | tids | `binds` |

The tables that hold a name (`static_owners`, `trait_heads`,
`tc_call_declared_name`) hold a declaration node in the record. A built-in
with no declaration holds a built-in id.

## What the record makes possible

- Lowering has no chain of tests for dispatch: it switches on `role` and
  `kind`.
- No built-in spelling takes over a user name: `role` and `decl` come from
  the name pass in spec order, and lowering does not test spelling.
- `solve_call_binds`, `mono.unify`, `tc_ret_mint` and the by-name lookup of
  generic fns go away: mono reads `binds` and `decl`.

## Order of work

1. Write the record (all slots), with the completeness verifier and the
   agreement checks. Do not change a reader in this step.
2. Move the readers onto the record: mono for `binds` and `decl`, lowering
   for `role`, `kind` and `decl`, the effect walkers for `kind`.
3. Delete the old code and the agreement checks: the codegen chain of
   tests, the re-solve, the name fallbacks, the replaced tables.

## Questions

1. **Key and storage.** One `List[Record]` indexed by node id (as
   `tc_node_tid` is), one `Map[Int, Record]`, or one parallel list for each
   slot?
2. **Value of `decl`.** One `Int` with a separate tag (declaration, binder,
   built-in), or an enum with a payload?
3. **Fold or keep.** Do `tc_call_decl`, `tc_global_read_decl` and
   `tc_local_binder` move into `decl` in step 1, or stay and get read through
   the record until step 3?
4. **Is `role` a slot?** Or does a reader derive it from the `decl` of the
   `obj` (a module, a type, a trait, an effect handle)? `Value` and
   `BuiltinDefault` do not have a declaration of their own.
5. **Is `CallReach` the `kind` enum?** Or is `kind` a smaller enum for
   lowering, with the effect walkers keeping `CallReach` derived from it?
6. **The built-in table.** Is the one built-in method table part of this
   work, or a separate step that the `kind` slot waits for? Today there are
   at least three lists: `is_intrinsic_method`, `cc_intrinsic_callee` with its
   per-kind tables, and `cc_runtime_method`.
7. **Re-inference rule for `binds`.** When inference checks a node again:
   unify the new list with the old one (as `tc_note_generic_call` does), or
   replace it?
8. **Always on.** `tc_note_generic_call` writes only when
   `tc_boundary_check_active != 0`. Does the `binds` writer run on each walk,
   and what does it cost in check time?
9. **Typevars in `binds`.** Does an entry inside a generic body hold the
   binder tids of the enclosing declaration, and does mono substitute with
   the instance's binds? Or does mono key by (node, instance)?
10. **Fn values.** `tc_generic_fn_value_tid` mints once for each reference
    node and keeps the result in `open_tids` until the flush. Does a fn value
    get one `binds` list, written once?
11. **Internal error codes.** A new I-code for each slot (the highest today is
    I0025), one new I-code for the record, or reuse of I0001, I0004 and
    I0022?
12. **Phase checks.** Does the record check at run time that a reader does
    not read a slot before it is readable?
13. **Default fills.** Does the `NamedArg` node that typecheck adds for a
    default argument get a record of its own, or do readers go on with
    `tc_is_default_fill`?
14. **Exit from typecheck globals.** Is the record a typecheck global that
    mono and lowering read, or does typecheck hand it to mono as a value?
