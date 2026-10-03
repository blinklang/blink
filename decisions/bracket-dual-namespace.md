[< All Decisions](../DECISIONS.md)

# A Bracket Item Whose Name Is Both a Type and a Value — Design Rationale

§3.4 *Postfix Brackets That Are Not a Type Application* classifies a bracket suffix by its
contents: a value item is E0313, an all-type list is checked for count (E0303), and a well-formed
list with no `(` or `{` after it is E0314. An item is a type when "every name in it resolves to a
type or a type parameter". Module scope has two namespaces (§2.12.1), so `const MAX` and
`type MAX` can both exist. The spec did not say how `MAX` in `xs[MAX]` or `make[MAX]()` resolves
when both bindings are in scope, or when a local `let Max` sits over a module `type Max`.

Blink has no const generics, so a value is never legal in a type-argument list. The answer
therefore decides more than an error code: under some rules `make[MAX]()` compiles, under others
it does not.

**A note on quotation.** Panelist text below is verbatim or an excerpt with attribution. The
single exception is `br` ticket identifiers, which are replaced by a bracketed description. No
panelist text was reworded.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Phase A produced four Q1 options and one variation.
Phase B ran one round, after which all six marked STABLE, READY TO VOTE. Phase C tied 3-3 on Q1
and was 6-0 on the other three questions. Phase D ran one focused round on Q1 and on the order of
the Q3 help lines.

#### Phase A — Independent proposals

- **Systems (P1, innermost scope wins, a tie goes to the value):** "Resolve each bare name in an
  item from the innermost scope outward. At each scope, look in both namespaces. The first scope
  that binds the name decides it... Both at that scope: the name is a **value**." "Names inside a
  type application's arguments (the `MAX` in `List[MAX]`) are in type position." P2 was an
  optional use-site lint; P3, an ambiguity error, was rejected.
- **Web/Scripting (W1, the value always wins):** "When a name in a bracket item resolves in the
  value namespace, the item is a value... The value wins even when the same name also resolves to
  a type or a type parameter." Proposed help: "`MAX` also names a type. To use the type here, give
  it a name that is only a type: type MaxT = MAX then pick[MaxT](...)". Rejected W2 (decide by
  position), W3 (declaration warning) and letter-case rules.
- **PLT (P1, type namespace only):** "Blink has no const generics. No value is ever legal inside a
  type-argument list. So the tie-break does more than pick an error code. It decides whether a
  legal program compiles." "Each name in an item resolves in the **type namespace only**: If the
  type lookup finds a binding, the name is a type. This holds even if a value of that name also
  exists. If the type lookup fails, the item is a value." "a local `let Max` binds in the value
  namespace. It cannot hide a type... Shadowing works within one namespace, never across the two."
- **DevOps (P1, the next token breaks the tie):** "Such an item is a **type** when the brackets
  come directly before `(` or `{`. In all other positions it is a **value**." P2 was a
  declaration-site lint `warning[DualNamespaceBinding]`. Flag: "Take `xs[Foo]` where `Foo` does not
  resolve... E0313 fires together with the unresolved-name error. The E0313 help `xs.get(Foo)`
  still does not compile, so the two diagnostics are not confluent. Possible fix: an unresolved
  item suppresses E0313."
- **AI/ML (P1, N-g):** "A name with a binding in both namespaces is a type only when the brackets
  come directly before `(` or `{` and the head declares one or more type parameters. Otherwise it
  is a value." "without it, `handlers[MAX](req)` would read as type-first and give E0303 'delete
  the list'. That repair is wrong." P2, an ambiguous-item error, ranked second. "I could not
  confirm that a same-module type can be aliased."
- **Minimalism (M1):** "Each name resolves by ordinary scope lookup, innermost scope first (§2.2).
  When one scope binds the name in both namespaces (§2.12.1), the value binding wins." Rejected M2
  (type first), M3 (declaration diagnostic) and M4 (next token).

#### Phase B — Debate highlights

- **Minimalism** moved to T: "I withdraw M1 and support Option T." On the local `let Max` over a
  module `type Max`: "I concede this point to plt."
- **Systems** moved to T: "I change my position to Option T (plt P1) and withdraw S." Proposed
  wording: "Each name in an item resolves in the type namespace only. A value binding of the same
  name, at any scope, does not hide it. If any name in an item does not resolve in either
  namespace, only the unresolved-name error is reported."
- **PLT** held T: "a bracket item must resolve the same way as the same type in an annotation."
  Against S: "Under S, `make[Max]()` becomes E0313, while `let d: List[Max] = make()` on the next
  line still reads `Max` as the type." Against N and N-g: they break "the 6-0 rule 'classified by
  CONTENTS'", and "The same case already exists for `handlers[Int](req)`, and the panel accepted it
  6-0."
- **Web** moved to a merged S+N-g: "a Python or JS developer reads `let Max = 3` then `xs[Max]` as
  'the Max I just made'."
- **DevOps** moved to N-g: "on legal programs it accepts exactly what T accepts."
- **AI/ML** moved to the merged S+N-g: "A `.get(MAX)` help under E0303 is two codes that point to
  two fixes. An LLM applies the first one."
- All six agreed that `xs[List[MAX]]` is a type item (E0303), that the spec adds no diagnostic for
  a name in both namespaces, and that the DevOps flag should be adopted.

#### Phase C — Silent vote

- **Q1: how a dual-bound name in a bracket item resolves** (3-3, T vs N-g; S+N-g got no votes)
  - **Systems:** T — "The resolver does one lookup per name, in one table, the same as for a type
    annotation. Then `f[Point](x)` and `let p: Point` cannot disagree. N-g and S+N-g put back what
    the 6-0 rule took out." Concern: "For dual `xs[MAX]`, the primary E0303 repair, 'delete the
    list', removes the user's intent."
  - **Web/Scripting:** N-g — "plt's example persuaded me to leave S+N-g... N-g picks the code
    whose repair matches what a JS or Python developer meant: `xs[MAX]` and `handlers[MAX](req)`
    get E0313 with `.get(MAX)`, not E0303 'delete the list'."
  - **PLT:** T — "Inside a type-argument list, a bracket item is in type position, so it must
    resolve the same way as the same name in an annotation." Concern: "the `.get(MAX)` help must
    be required, not optional."
  - **DevOps:** N-g — "N-g and T accept the same set of legal programs, so they differ only in
    diagnostics, which is my domain... A `.get(MAX)` help under E0303 tells the user two different
    fixes in one diagnostic, and tools and LLMs apply the first help."
  - **AI/ML:** N-g — "LLMs apply the first help they see, so the error code itself must point to
    the right fix."
  - **Minimalism:** T — "T is one lookup in one namespace, and the type annotation
    `let d: List[Max]` already uses that lookup, so it adds no mechanism."
- **Q2: a spec diagnostic or lint for a name in both namespaces** (6-0, none)
  - **PLT:** "A type and a value with one name is legal under §2.12.1, and ML and Haskell use it
    often (`data P = P`). A style lint belongs in tooling, not in the spec."
  - **DevOps:** "§2.12.1 made dual binding legal, so a spec-level warning would reopen that
    decision through a lint." Concern: "rename on `MAX` in the LSP must still ask which
    declaration the user means. That needs a ticket outside the spec."
- **Q3: a note and help on a dual-bound item** (6-0, yes; help order split, see Phase D)
  - **PLT:** "the help line must come after the E0303 repair, in a fixed order."
  - **Minimalism:** "The spec should let this help rank first when the head is a value."
  - **Systems:** "The help must offer `.get(...)` only when the head is a value with a `get`
    method."
  - **Web/Scripting:** "It must follow the same receiver-type rule that the existing E0313 help
    uses."
- **Q4: an unresolved name suppresses the bracket codes** (6-0, yes)
  - **Systems:** "Each fix for an unresolved name leads to a different bracket code: declare a type
    and the result is E0303, declare a value and it is E0313."
  - **Minimalism / Systems / DevOps:** the rule must cover a name inside a compound item
    (`xs[List[Foo]]`).
  - **PLT:** "The rule must say 'for that suffix' exactly, so that an unresolved name in one item
    does not suppress errors from other suffixes."

#### Phase D — Round 2 (Q1 and Q3 order)

- **Q1** (5-1 for T, DevOps dissent)
  - **Systems:** T — "N-g also has a cost its supporters did not price. It needs the arity of the
    head when it classifies the item... For a method head such as `obj.m[MAX](x)` or
    `self.items[MAX](x)`, the arity depends on the receiver's type. That breaks the decided rule
    'never by receiver type'." (Moderator fact check: the spec has method heads with type
    arguments, e.g. `scope.alloc[U8]()` for `fn alloc[T](self)`, §7.)
  - **Web/Scripting:** T *(changed from N-g)* — "My test is: 'Would a JS/Python dev understand
    this in 5 minutes?' T passes it in one sentence: 'a bracket item is a type position, the same
    as an annotation.' N-g needs three facts."
  - **PLT:** T — "If T puts `.get(MAX)` first when the head is a value, T gives the same first
    repair as N-g. The remaining difference is the code label: E0303 or E0313. A label is not
    worth a position-dependent resolution rule."
  - **DevOps:** *(dissent)* N-g — "The rule that the panel passed 6-0 already uses both of those
    inputs. Step 3 (E0314) depends on the token after `]`... Step 2 (E0303) depends on the head's
    arity... A help line can fix the repair, but it cannot fix that headline."
  - **AI/ML:** T *(changed from N-g)* — "'a bracket item resolves exactly like a type annotation'
    is one sentence that an LLM can learn and apply with no exceptions." Concern: "the E0303
    headline 'xs takes 0 type arguments' still misreads intent for dual `xs[MAX]`."
  - **Minimalism:** T — "A position rule costs every reader of the spec, and every implementation,
    for good. A help-order rule costs one sentence in one diagnostic."
- **Q3 order** (6-0, `.get` first; PLT changed from "after")
  - **PLT:** "For a value head whose item name also has a value binding, the user's likely intent is
    element access, so that repair must rank first."
  - **Minimalism:** "Deleting the list compiles, but it drops the user's intent. §3.1 asks for the
    repair that keeps meaning, so `.get` must come first."

The user signed off on the tally.

### Final Spec

```blink
type MAX { n: Int }
const MAX = 2

fn make[T]() -> List[T] { [] }

fn main() {
    let xs = [10, 20, 30]
    let a = make[MAX]()        // OK -- `MAX` is the type
    let b: List[MAX] = a       // OK -- the same type
    let c = xs[MAX]            // error[TypeArgArity]: `xs` takes 0 type arguments
                               // note: `MAX` is read as a type here (line 1); it is also a value (line 2)
                               // help: `xs.get(MAX)` returns `Option[Int]`
                               // help: delete the list -- `xs`
}
```

- A name in a bracket item resolves in the type namespace only. A value of the same name, at any
  scope, does not change the result.
- No spec diagnostic or lint for a name in both namespaces.
- For a value head and a bare-name item that also has a value binding, the first `help:` is the
  element read (E0313 receiver rule), the second is "delete the list", and a `note:` names both
  declarations.
- A name in an item that resolves in neither namespace gets only the name-resolution error. E0313,
  E0303 and E0314 are not reported for that suffix, nested names included.
