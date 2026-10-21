[< All Decisions](../DECISIONS.md)

# Removed Function Forms and Collection Adapters — Design Rationale

Spec ticket: prelude free functions duplicate methods. The stdlib exported free-function forms (`list_*`, `map_*`, `str_*`, `num.*`, `json_escape_str`) beside the methods that §3.2 *Stdlib API surface: methods only* makes the one form. The panel decided what replaces each name, which adapters `List` and `Map` gain, and the effect rules for those adapters.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim.

#### Phase A — Independent proposals

##### Systems

Skippy here. Fine, monkeys. Here is a proposal from the only seat that asks what the CPU actually runs.

###### Systems: Proposal S1, methods are the only public surface; the free functions become private backing code

**Core claim.** A free function and its method twin compile to the same C call. `s.trim()` goes through the sealed StrOps impl to one direct, monomorphized call, with no vtable and no wrapper. So the duplicates buy users no performance at all. What they do cost is two names for one operation, plus one name that hides a correctness bug. `num.parse_int("12x")` returns `12`, and `""` returns `0`. That is C's `atoi`, and it is the bug class that `strtol` with an `endptr` check exists to fix. A systems language that ships `atoi` under the same name as its checked parser has handed users a loaded gun.

**Rule.** §3.2 already says "No function form of a built-in method exists." The library breaks it. Enforce it:

1. Every `std.list` / `std.str` / `std.map` / `std.num` function in the brief that duplicates a method loses `pub`. Each one stays as the private body a method lowers to, so codegen does not change and the runtime cost is zero.
2. A call to a removed name gives E0504 and names the replacement method, using the §4.4 *Removed free functions* mechanism. As there, the compiler checks the table only after normal lookup fails, so a user `fn parse_int` still wins (tests/test_local_fn_named_like_prelude_fn.bl stays green).
3. Fill in the method gaps instead of keeping free functions for them:
   - **List**: the §3.2.2 ListOps table must list the eager adapters that §3c (03c_protocols.md:11) already promises: `map`, `filter`, `fold`, `any`, `all`, `find`, `flat_map`, `for_each`, `enumerate`, `zip`, `skip`. Each stays eager and returns a `List`, with no iterator allocation. That is "collection in, collection out", and it is what the hardware sees today.
   - **Map**: §3c:11 names Map as a collection with eager adapters, but MapOps has none. Add `filter(fn(K, V) -> Bool) -> Map[K, V]`, `map_values(fn(K, V) -> U) -> Map[K, U]`, `fold`, `for_each`, and `merge(other) -> Map[K, V]`, where entries in `other` win on key conflict and the order follows §insertion-order.
   - **`str_from_code_point`**: delete it. Its replacement is `Char.from_code_point(n)?.to_str()`, which is checked. The current function makes a Str from a surrogate or from an out-of-range number, which is invalid UTF-8 in memory. That is a soundness hole, not just a style problem.
   - **`json_escape_str`**: this is not a twin. It is the target that `derive(Serialize)` codegen calls (src/cg_derive.bl:1850, 1945). Keep it in `lib/std/json.bl`, out of the user API. Codegen may call items that users cannot name.

```blink
import std.map

fn main() {
    let n = "12x".parse_int()            // Err(ConversionError) -- never a silent 12
    let words = " a,b ".trim().split(",")
    let lens = words.map(fn(w) { w.len() })          // eager, List[Int]
    let m: Map[Str, Int] = Map()
    let big = m.filter(fn(k, v) { v > 10 })          // eager, Map[Str, Int]
    let total = m.fold(0, fn(acc, k, v) { acc + v })
    // num.parse_int(s)  -> E0504: removed; use `s.parse_int()` (returns Result)
}
```

**Tradeoffs:**
- Plus: one name per operation, so codegen and inlining work goes into one path. The ops traits stay the sealed dispatch surface, so the compiler is free to intrinsify `trim` or `split` later without any user-visible name pinning down the C shape.
- Plus: the lossy `parse_int` stops being callable. src/lsp.bl:25 and lib/std/http_client.bl:165 must handle the `Result`. Good: an HTTP status or port parsed as `0` from bad input is a real bug today, not a theory.
- Minus: Map grows five methods. That is the honest price of §3c:11's promise. The other choice is to collect into `List[(K, V)]` and rebuild the Map, which allocates twice. That is worse.
- Minus: self-hosting churn. src calls six of these names, so this needs the full 3-step dance (add methods → migrate src → drop `pub`), with a regen at each step. It is mechanical work, so no reason to block on it.

**Cross-language:** Rust has no `str_trim(s)`, only `s.trim()`. Its `str::parse::<i32>` returns a `Result`, and nobody misses `atoi`. Go has free `strings.TrimSpace` because it lacks methods on builtins, which Blink does not. Zig's `std.fmt.parseInt` returns an error union. All three agree that a lossy parse is never the default.

**Spec text:**
- §3.2 (03_types.md:113): after "No function form of a built-in method exists", add: "The standard library does not export one either. A removed free-function name is diagnosed as in §4.4."
- §3.2.2 ListOps table: add the eager adapters `map`, `filter`, `fold`, `any`, `all`, `find`, `flat_map`, `for_each`, `enumerate`, `zip`, `skip`. MapOps table: add `filter(fn(K, V) -> Bool) -> Map[K, V]`, `map_values(fn(K, V) -> U) -> Map[K, U]`, `fold`, `for_each`, `merge(other) -> Map[K, V]` (entries in `other` win on key conflict; order follows the insertion-order rule).
- §4.4: extend the *Removed free functions* table with every name in the brief's list except `json_escape_str`, each mapped to its method, or to `Char.from_code_point(n)?.to_str()` for `str_from_code_point`.
- §3.2.1:367: add "No lossy parse function exists in the standard library."

##### Web/Scripting

###### Position
Two spellings for one job is the classic Stack Overflow generator ("`list_map` or `.map`? Which is faster? Why does `parse_int("12x")` give 12?"). §3.2 already settled this 4-1: methods only. These `pub fn`s are leftovers that break that rule. Delete them. Where no method twin exists, add the method; don't keep the free function.

###### Proposal 1: Remove every duplicate, with a removed-name table (like §4.4)
Remove all 39 names in std.list, std.str, std.map and std.num. The worst trap is `num.parse_int`: same name, different contract, and it fails silently. A JS dev who has been burned by `parseInt("12x") === 12` knows that bug well. We should not ship it on purpose.

```blink
// before
import std.num
let n = num.parse_int(input)          // "12x" -> 12, "" -> 0. Silent.

// after: one way
let n = input.parse_int()?            // Err(ConversionError) on bad text
let s = "{n}"                         // not int_to_str(n)
let parts = line.trim().split(",")    // not str_split(str_trim(line), ",")
```

A call to a removed name gives E0504 with a fix that names the method. That gives users and LLMs a clear migration path.

**Spec text:** in §3.2 after "No function form of a built-in method exists", add a paragraph **Removed std free functions** with a table that works like §4.4's, mapping each name to its replacement. For example: `list_map(xs, f)` → `xs.map(f)`, `str_trim(s)` → `s.trim()`, `int_to_str(n)` → `"{n}"` / `n.display()`, `parse_int(s)` → `s.parse_int()` (returns `Result`; the old one did not fail). Add one sentence: "The compiler checks the table only when name lookup fails; a user `fn parse_int` still wins."

###### Proposal 2: Fill the method gaps people expect
Removal only works if the 90% case still has an obvious spelling.

- **ListOps (§3.2.2 table):** add eager `map`, `filter`, `fold`, `any`, `all`, `find`, `for_each`, `flat_map`, `enumerate`, `zip`, `skip`. §3c line 11/23 already promises "collection method in, collection out", and the ListOps table does not show it. JS, Kotlin and Swift users write `xs.map(f)` without thinking. Nobody writes `xs.iter().map(f).collect()` for a one-off. The lazy `Iterator` stays for chains.
  ```blink
  let names = users.filter(fn(u) { u.active }).map(fn(u) { u.name })
  ```
- **MapOps:** add `filter`, `map_values`, `merge`, `for_each`, `fold`. These follow Kotlin's `filter`/`mapValues`/`plus` and JS `Object.entries` habits.
  ```blink
  let adults = ages.filter(fn(k, v) { v >= 18 })
  let merged = defaults.merge(overrides)   // right side wins
  ```
- **Str:** `str_from_code_point(c)` → static constructor `Str.from_code_point(c)`, as §3.2 already does for constructors. `str_char_at_opt`, `str_cp_index_of` and `str_byte_index_of` either map to existing `.get`/`.index_of` methods or are internal helpers. If no method covers one, make it private, not public.
- **`json_escape_str`:** this is not an operation on a built-in type. It is JSON encoding. Move it to `std.json` (`json.escape(s)`) or make it private. A module function is fine here because §3.2 governs built-in type APIs, not domain modules.

**Tradeoff:** the ListOps/MapOps tables get bigger. That is fine. Autocomplete on `.` is how scripting devs find APIs. A free function in a module they never imported is invisible to them.

###### Proposal 3: Order of work (not spec, but it must be said)
src/ calls `list_map`, `str_join`, `float_to_str`, `int_to_str`, `str_trim`, `str_to_lower`, and the lossy `parse_int` (src/lsp.bl:25, lib/std/http_client.bl:165). Those last two are probably real bugs, because they silently accept garbage. Do the 3-step self-host dance: add the methods, migrate src/lib/tests, then remove the names and add the table.

###### Rejected alternative
"Keep both, declare methods canonical." No. Python's `len(x)` vs `x.__len__()` shows that two forms means people ask forever which one is idiomatic. LLMs trained on this repo will also emit both. A "canonical" label in the spec does not stop that.

###### Vote I'd cast
Proposals 1 and 2 together. If the panel won't add Map methods, I would still remove the list/str/num duplicates now and keep `map_*` as a temporary exception with a dated removal note.

##### PLT

**PLT panelist: Phase A proposal**

The rule already exists. §3.2 says "No function form of a built-in method exists," and that passed 4-1. These 33 `pub fn`s break that rule, so this is not a new design question. The real spec gap is narrower: §3c promises eager collection adapters ("`list.map(f)` walks the list now") but never lists them. That missing list is why the free functions still exist.

**P1: The lossy `parse_int` is a soundness bug, so remove it first.**

`num.parse_int : Str -> Int` is total. `Str.parse_int : Str -> Result[Int, ConversionError]` is partial. They have the same name and different contracts. The total version hides a failure: `"12x"` gives 12 and `""` gives 0. In type terms it is a wrong total function that sits in for a partial one. Two of our own callers use it today (`src/lsp.bl:25`, `lib/std/http_client.bl:165`), and those are latent bugs. `parse_float` has the same flaw.

```blink
let port = "80x".parse_int()?      // Err(ConversionError), the only form
```

**P2: Remove every function that has a method twin, and keep a removed-names table.**

Do this with the 3-step dance. Copy the §4.4 mechanism: the names are gone, an E0504 fix-it names the replacement, and the compiler checks the table only after name lookup fails. That keeps a user's own `fn parse_int` working (tests/test_local_fn_named_like_prelude_fn.bl). Every name goes, including the internal FFI bridges. They become non-`pub` (§3c:844 already says the bridges are not public API).

Spec text, new paragraph after §3.2 *Stdlib API surface*:

> **Removed method twins.** Earlier std versions exported free functions that duplicated methods. They are not part of Blink. A call gives E0504 with the fix below. The compiler keeps this table for good and checks it only when name lookup fails.

| Removed | Replacement |
|---|---|
| `str_trim(s)` etc. | `s.trim()`, `.trim_left()`, `.trim_right()`, `.to_upper()`, `.to_lower()`, `.split(d)`, `.replace(a,b)`, `.lines()` |
| `str_join(xs, d)` | `xs.join(d)` |
| `str_char_at_opt(s,i)`, `str_byte_index_of` | `s.char_at(i)`, `s.byte_index_of(n, from)` |
| `str_from_code_point(n)` | `Char.from_code_point(n)` then `"{c}"` |
| `int_to_str(n)`, `float_to_str(x)` | `"{n}"` / `n.display()` |
| `parse_int(s)`, `parse_float(s)` | `s.parse_int()`, `s.parse_float()`. **Note: the replacement returns `Result`.** |
| `list_*`, `map_*` | the methods in P3 |

`json_escape_str` is not a method twin. It is a domain function. It moves to `std.json` as `json.escape(s)`. §3.2 does not forbid that, because the rule covers function forms of methods, not every free function.

**P3: List the eager adapter surface in the spec, with typing rules.**

This closes the twin gap for `list_*` and `map_*`. Add to §3.2.2 ListOps:

```blink
fn map[U](self, f: fn(T) -> U) -> List[U]
fn filter(self, p: fn(T) -> Bool) -> List[T]
fn flat_map[U](self, f: fn(T) -> List[U]) -> List[U]
fn fold[U](self, init: U, f: fn(U, T) -> U) -> U
fn any(self, p: fn(T) -> Bool) -> Bool
fn all(self, p: fn(T) -> Bool) -> Bool
fn find(self, p: fn(T) -> Bool) -> Option[T]
fn for_each(self, f: fn(T))
fn enumerate(self) -> List[(Int, T)]
fn zip[U](self, other: List[U]) -> List[(T, U)]
fn skip(self, n: Int) -> List[T]
```

Add to MapOps:

```blink
fn filter(self, p: fn(K, V) -> Bool) -> Map[K, V]
fn map_values[U](self, f: fn(K, V) -> U) -> Map[K, U]
fn fold[U](self, init: U, f: fn(U, K, V) -> U) -> U
fn for_each(self, f: fn(K, V))
fn union(self, other: Map[K, V]) -> Map[K, V]   // right-biased on value; order per §3.2 Map order
```

`Map.union` mirrors `Set.union`, and §3.2's ordering bullets already name `a.union(b)` for `Map`. It is right-biased on the value, which is what `map_merge` does today (lib/std/map.bl:81). The spec must state that bias. Leaving it out of a typing rule invites a silent behavior change.

**Effect rule:** each eager adapter is effect-transparent. The call's row is the row of `f`. This is cleaner than the lazy case. In `it.map(f)` the effect of `f` runs at the consuming call, not at `.map`, and §3c should say so. Eager adapters have no such deferral, which is one more reason to prefer them for the common case.

**Tradeoffs:**
- More methods on ListOps/MapOps means a larger sealed surface. But each one is a homomorphism that §3c already promises. We list it; we don't invent it.
- The `parse_int` fix-it changes the result type, so mechanical migration breaks at the type level. That's good: the type error is the audit.
- Migrating src costs regens: list_map, str_join, int/float_to_str, str_trim, str_to_lower.

**Cross-language:** OCaml keeps `List.map` because it has no methods. Its module *is* the API, so there is only one form. Haskell's `Data.Map.union` is left-biased, and that bias is part of the documented contract. Rust removed `str::trim`-style free functions before 1.0 for the same one-form reason. Koka resolves `xs.map(f)` to `map(xs, f)` with a single definition, which shows the duplication is a surface problem, not a semantic need.

**Vote:** P1 + P2 + P3 together. I reject "state which form is canonical" while both stay public. Two public names with one being "canonical" is exactly the decision point that Principle 2 and the 4-1 vote ruled out.

##### DevOps

DevOps/Tooling Phase A: remove the twins outright, and use a permanent lookup-failure table with fix-its (follow §4.4). Do not use @deprecated.

The spec already decided this. §3.2 says "methods only" (4-1), and §3c says the bridge functions "are internal". The bug is that lib/std still exports them as `pub`. So this is not a new rule. It is enforcement plus a migration path. My concern is what the user sees when the name stops resolving.

**P1. Delete every free function that has a method twin, and keep a "Removed free functions" table in §3.2.**

```blink
import std.list.{list_map}        // error E0504 at the import: `list_map` is not exported by std.list
let ys = list_map(xs, fn(x) { x * 2 })
// help: use the method `xs.map(fn(x) { x * 2 })` (§3.2)   [machine-applicable]

let n = num.parse_int(s)
// error E0504: `num.parse_int` was removed
// help: use `s.parse_int()`, which returns Result[Int, ConversionError]
// note: the old function returned 0 or a prefix for bad text; this fix is NOT automatic
```

Tooling rules:
- The compiler consults the table only when name lookup fails. That covers a bare call, a qualified call (`num.int_to_str`) and a selective import item. A user `fn parse_int` still wins (tests/test_local_fn_named_like_prelude_fn.bl already proves this).
- Each row has a fix class. `replace` means a pure rewrite of receiver and arguments that `blink fix` applies: list_map/filter/fold/any/all/find/for_each/flat_map/enumerate/zip/skip, str_trim*/to_upper/to_lower/split/replace/lines/join, int_to_str and float_to_str → `"{n}"`. `manual` means a contract change that the diagnostic explains but `blink fix` does NOT apply: parse_int and parse_float (Int → Result). A silent auto-rewrite there turns `"12x"→12` into a type error at best, and at worst into a `?` that the tool inserts and the user never reviews. Never.
- The LSP stops offering these names at once, because they are no longer exported. This is the main win. Today `num.` autocompletes the lossy `parse_int` next to the correct method, and LLMs copy whichever name they see first.

Why not `@deprecated` (§8.16)? It is keyed to editions and needs a 2-edition window. Blink is 0.x and has no edition to name in `since`. A W2000 deprecation also keeps the names in completion lists for years. The table costs one diagnostic row per name and keeps for good, as in §4.4.

**P2. Re-home the six names that have no twin. Do not keep them as free functions.**

| Old | New | Reason |
|---|---|---|
| `str_from_code_point(n)` | `Char.from_code_point(n)?` then `"{c}"` | already in the spec (§3c.3); `manual` fix, because it now fails on bad input |
| `str_char_at_opt`, `str_cp_index_of`, `str_byte_index_of` | `.char_at`, `.index_of`, `.byte_index_of` | twins exist in §3.2.1; `replace` |
| `map_for_each` | `for (k, v) in m { }` | `manual`, because a closure body becomes a loop body (the fix is safe only when the closure has no `return`) |
| `map_fold` | `m.entries().iter().fold(init, fn(acc, (k, v)) { })` | `manual` |
| `map_filter`, `map_map_values`, `map_merge` | add eager `MapOps.filter`, `.map_values`, `.merge` | §3c already says "collection method in, collection out" for List. Map has no way to collect back to a Map, so without these the user has no non-loop path. `m.` completion should show them. |
| `json_escape_str` | `json.escape(s)` in std.json | not a built-in-type operation, so a module function is legal under §3.2 |

If the panel rejects the three new MapOps methods, `map_filter` and its siblings get a `manual` row that points to a `for` loop. I can live with that, but I vote for the methods.

**P3. Rollout.** The self-host dance: add the methods → migrate src/ (list_map, str_join, float_to_str, int_to_str, str_trim, str_to_lower, and the lossy parse_int in src/lsp.bl:25 and lib/std/http_client.bl:165, which are latent bugs; audit both) → delete the pub fns, with tests/ migrated by `blink fix`. That is a good dogfood of the fix-it path. If the bridge code is still needed internally, it becomes non-pub or `@ffi`-internal.

**Spec text**
- §3.2 (03_types.md:113): after "No function form of a built-in method exists." add: "This includes std modules: std.str, std.list, std.map and std.num export no free function that duplicates a method. **Removed free functions.** A call or import of a name in the table below gives E0504 with a fix that names the method. Fixes marked *manual* change the result type, and `blink fix` does not apply them. The compiler consults the table only when lookup fails." Then the table.
- §3.2.2 MapOps table: add `filter`, `map_values`, `merge` (if P2 passes).
- §3.2.1:367: no change. It already says parse_int is a method only.

Cross-language: Go's `go fix` and rust-analyzer's "replace with method call" assists both split safe rewrites from manual ones. TypeScript's `@deprecated` strikethrough shows what happens when a deprecated name stays in completion lists for years: people keep using it.

##### AI/ML

**AI/ML panelist, Phase A proposal**

Ugh. Twenty-odd free functions that shadow methods, and one of them silently returns `12` for `"12x"`. Even you monkeys can see the problem. I can, magnificently.

**The cost for code generation.** Every duplicate pair is one more decision for a model. An LLM trained on this repo sees `num.parse_int(s)` in src/lsp.bl and `s.parse_int()?` in the spec. It learns two forms. Then it uses the wrong one in a path that handles user input. That `parse_int` case is the worst kind of duplicate: the same name with a different contract. It never fails and gives no error, so the test passes and production sees a quiet 0. §3.2 already says "No function form of a built-in method exists." The library breaks the spec. Make the library obey.

###### Proposal 1: remove every free function that has a method twin

Remove these after the 3-step dance:

| Remove | Use instead |
|---|---|
| `num.parse_int`, `num.parse_float` | `s.parse_int()?`, `s.parse_float()?` |
| `num.int_to_str`, `num.float_to_str` | `"{n}"` or `n.display()` |
| `str_trim/_left/_right`, `str_to_upper/_lower`, `str_split`, `str_replace`, `str_lines` | the StrOps methods |
| `str_join` | `parts.join(sep)` |
| `str_char_at_opt`, `str_cp_index_of`, `str_byte_index_of` | `.char_at`, `.index_of`, `.byte_index_of` |
| `str_from_code_point` | `Char.from_code_point(n)?` (it returns `Result`, so the error is visible) |
| `list_map/filter/fold/any/all/for_each/find/flat_map/enumerate/zip/skip/sort/sort_by/slice` | eager List methods (§3c rule), or `.into_iter()…` |

```blink
// before: two forms, one of them lossy
let port = num.parse_int(raw)            // "80x" -> 80, "" -> 0
// after: one form
let port = raw.parse_int()?              // Err(ConversionError) on bad text
```

Add each removed name to a §4.4-style *Removed free functions* table. That gives E0504 with a fix line that names the method. This matters a lot for AI: a model with stale training data writes `list_map(xs, f)`, the compiler names `xs.map(f)`, and the model self-corrects in one turn. A user `fn parse_int` still wins, because the table is consulted only when lookup fails (the rule we already have).

###### Proposal 2: fill the Map gap so removal does not take away function

§3c says "Collection method in, collection out" and names Map as a collection. But MapOps has no eager adapters, and `collect()` gives only a List. A model will write `m.filter(...)` (Python dict comprehensions, Kotlin `Map.filter`, Rust's iterator habit). Give it what it expects:

```blink
let adults = ages.filter(fn(k, v) { v >= 18 })        // Map[Str, Int]
let labels = ages.map_values(fn(k, v) { "{k}:{v}" })  // Map[Str, Str]
let total  = ages.fold(0, fn(acc, k, v) { acc + v })
let merged = defaults.merge(overrides)                 // right side wins
```

`for (k, v) in m { }` already covers `for_each`. Don't add `Map.for_each`. A loop is one form, and one form is all we need. Remove `map_for_each` with the rest.

Then add `filter`, `map_values`, `fold`, `merge` to the MapOps table in §3.2.2, with insertion order kept (that matches the new Map order rule, d57796dd). Then remove the `map_*` free functions.

###### Proposal 3: `json_escape_str` is not a duplicate. Move it, don't delete it

It is a JSON-domain function, not a Str method, so §3.2 does not apply. Rename it `json.escape(s)` in std.json. A module-qualified call that names its domain is the pattern models learn best.

###### Spec text changes

- **§3.2 (03_types.md:113)**: add: "This rule binds the standard library. No `lib/std` module exports a free function that does the work of a built-in method. A domain function that is not a method of a built-in type (e.g. `json.escape`) stays a module function."
- **§3.2.2**: add rows for the eager List adapters (`map`, `filter`, `fold`, `any`, `all`, `find`, `flat_map`, `enumerate`, `zip`, `skip`). §3c:23 already promises `list.map`, and the table contradicts it. Add the Map rows from Proposal 2.
- **§4.4 or a new §3.2.x "Removed std free functions"**: the table from Proposal 1, E0504 plus a named replacement, kept for good.

###### Tradeoffs

- **For:** one form per operation, which means fewer decision points and fewer tokens per call. The lossy `parse_int` goes away. The spec and the library agree, and that matters because this repo is training data.
- **Against:** four Map methods add surface area. But they fill a gap the §3c rule already implies, so they add no new concept. There is migration cost in src/ and tests/ (the 3-step dance). That is a one-time cost, against the permanent cost of an AI writing the wrong form.
- **Cross-language:** Go learned this the hard way with `strings.Split` and no methods. Python has both `len(x)` and methods, and models still mix `str.join` up. Rust and Kotlin give one method form per operation, and LLMs produce them most accurately.

##### Minimalism

Minimalism Phase A: delete every free-function twin, add no new surface, no new table.

**Framing.** This is not a spec gap. §3.2 (03_types.md:113, vote 4-1) already says "No function form of a built-in method exists." lib/std breaks that rule. The spec needs one sentence of hardening. The real work is stdlib compliance. Do not reopen a settled vote to bless a violation.

**Proposal M1 (primary): remove all 38 `pub fn`s in std.list / std.str / std.map / std.num. Add nothing in their place.**

Each one already has an expression in the spec'd surface:

```blink
// list_map(xs, f)            ->
let ys = xs.map(fn(x) { x * 2 })           // §3c eager map
// list_fold / any / all / find / zip / enumerate / flat_map / skip ->
let total = xs.iter().fold(0, fn(acc, x) { acc + x })
// list_sort / list_sort_by / list_slice -> xs.sort(), xs.sort_by(cmp), xs.slice(a, b)
// str_trim_left / right      -> s.trim_start(), s.trim_end()
// str_char_at_opt / cp_index_of / byte_index_of -> s.char_at(i), s.index_of(n), s.byte_index_of(n, i)
// str_from_code_point(n)     ->
let t = Char.from_code_point(n)?.display()
// int_to_str(n) / float_to_str(f) -> "{n}"
// parse_int(s) (lossy)       ->
let port = s.parse_int()?                  // Result; lossy form dies on purpose
// map_for_each               ->
for (k, v) in m.entries() { log.info("{k}={v}") }
// map_filter / map_map_values ->
let live = Map.from(m.entries().iter().filter(fn(e) { e.1 > 0 }).collect())
// map_merge(a, b)            ->
let out = a.clone()
for (k, v) in b.entries() { out.insert(k, v) }
```

`json_escape_str` is not a Str method twin; it is JSON-domain code. Move it into std.json as a private helper of the encoder (or delete if the encoder already escapes). Never a public std.str name.

Map gets no `.filter` / `.map_values` / `.merge`. YAGNI: entries + iterator + `Map.from` covers it in one line. Add them later only if real user code shows the pain. Go shipped with no map helpers for 13 years and `maps` still has no filter.

**Why not "state which form is canonical"?** That keeps two ways forever and makes every reader, linter and LLM learn both. Principle 2 says one way. "Canonical" plus "tolerated" is the C++ committee pattern: nothing ever leaves.

**Why no §4.4-style permanent removed-names table?** That table exists because effectful names moved to a capability model and the fix needs an effect. Here the compiler already gives E0504 with an import hint. A permanent table of 38 dead names is surface the compiler carries forever for a pre-1.0 language. Cost/benefit fails. If the implementer wants, a one-release migration hint is a tooling chore, not spec.

**`parse_int` danger is the strongest case for deletion.** Same name, different contract (`"12x"` -> 12 vs `Err`). Two names that look alike and act unlike is the worst kind of duplicate. src/lsp.bl:25 and lib/std/http_client.bl:165 use the lossy one today; migrating them to `.parse_int()?` is a correctness fix, not just cleanup.

**Spec text changes.**
1. §3.2 (03_types.md:113), after "No function form of a built-in method exists.": add "This binds the standard library: no `std` module exports a public free function whose job is an operation on a built-in type that a method or an iterator chain already does."
2. §3.2.2 ListOps table (03_types.md:640-670): add the eager `map` row §3c already promises (fixes a table/§3c mismatch; adds no new feature).
3. No other text. No removed-names table.

**Implementation note (not spec):** src uses list_map, str_join, float_to_str, int_to_str, str_trim, str_to_lower. That is a 2-step dance (migrate src -> regen; delete fns -> regen), since the methods already exist. Tests using list_*/map_* get rewritten to methods, not deleted.

**Proposal M2 (fallback, if the panel insists on a deprecation path):** mark all 38 `@deprecated` with the replacement in the message for one minor release, then delete. Still no permanent table, still no new Map methods.

**Cross-language.** Go: one way, no helper zoo. Lua's string library has both `string.upper(s)` and `s:upper()`; years of style-guide noise over a choice nobody needed. Python 2 kept `string.upper()` beside `str.upper()` until 3.0 deleted it; nobody missed it.

Vote intent: M1. Burden of proof sits on anyone who wants to keep a single one of these names.

#### Phase A.5 — Moderator dedupe

###### Phase A.5: deduped option-space (moderator: grouping only, panelist text is in the Phase A replies)

**Shared by all six:** remove every std.list / std.str / std.map / std.num `pub fn` that has a method twin, including the lossy `num.parse_int` / `parse_float`. Harden §3.2:113 with a sentence saying the rule binds the standard library. Migrate src/ and lib/ (including src/lsp.bl:25 and lib/std/http_client.bl:165) with the self-host dance.

###### Q1: Diagnostic for a removed name
- **Q1-A: permanent removed-names table.** E0504 plus a fix that names the replacement. The compiler checks it only after lookup fails. (Web, PLT, DevOps, AI/ML, Sys)
  - Variation, placement: a new paragraph in §3.2 (Web, PLT, DevOps) vs extending the §4.4 table (Sys). AI/ML: either.
  - Variation, DevOps rider: each row has a fix class. `replace` rows are applied by `blink fix`. `manual` rows (parse_int, parse_float, str_from_code_point, map_for_each, map_fold) are explained but never auto-applied.
- **Q1-B: no table.** The current E0504 import hint is enough. A one-release migration hint is a tooling chore, not spec. (Min, M1)
- **Q1-C: `@deprecated` for one minor release, then delete. No permanent table.** (Min, M2 fallback)

###### Q2: What happens to the bodies
- **Q2-A: delete them.** (Web, AI/ML, Min)
- **Q2-B: drop `pub` and keep them as private bodies the methods lower to.** (Sys). PLT and DevOps: the bridges become non-pub if still needed internally.

###### Q3: Eager List adapters in the §3.2.2 ListOps table
- **Q3-A: full set** `map`, `filter`, `fold`, `any`, `all`, `find`, `flat_map`, `for_each`, `enumerate`, `zip`, `skip`. (Web, Sys, PLT with typed signatures). AI/ML lists the same set without `for_each`.
- **Q3-B: add only `map`.** The others go through `.iter()…`. (Min)

###### Q4: Map eager methods in MapOps
- **Q4-A: none.** Use `entries()` + iterator + `Map.from`, or a `for` loop. (Min)
- **Q4-B: `filter`, `map_values`, `merge`.** `map_fold` goes to an entries/iter chain, `map_for_each` to a `for` loop. (DevOps)
- **Q4-C: `filter`, `map_values`, `fold`, `merge`. No `for_each`.** (AI/ML)
- **Q4-D: `filter`, `map_values`, `fold`, `for_each`, plus a right-biased combine.** (Web, Sys: named `merge`; PLT: named `union`, mirroring `Set.union`)
  - Variation, naming: `merge` (Web, Sys, AI/ML, DevOps) vs `union` (PLT).
  - Variation: PLT says the spec must state the right bias. Sys and Web also state "other wins".

###### Q5: `str_from_code_point`
- **Q5-A: remove; replacement `Char.from_code_point(n)?` then `"{c}"` / `.to_str()` / `.display()`.** (Sys, PLT, DevOps, AI/ML, Min)
- **Q5-B: replace with a static constructor `Str.from_code_point(c)`.** (Web)

###### Q6: `json_escape_str`
- **Q6-A: public `json.escape(s)` in std.json.** (PLT, DevOps, AI/ML; Web: this or private)
- **Q6-B: keep in std.json out of the user API, as the target `derive(Serialize)` codegen calls (src/cg_derive.bl:1850, 1945).** (Sys)
- **Q6-C: private helper of the encoder in std.json, or delete.** (Min)

###### Riders (flagged, one proposer each)
- **Sys:** §3.2.1:367 adds "No lossy parse function exists in the standard library."
- **PLT:** eager adapters are effect-transparent: the call's effect row is the row of `f`. For lazy `it.map(f)`, the effect of `f` runs at the consuming call, and §3c should say so.
- **Web:** if Map methods fail, keep `map_*` as a temporary exception with a dated removal note.
- **DevOps:** if Map methods fail, `map_filter` and siblings get a `manual` row that points to a `for` loop.

#### Phase B — Debate

Round 1 broadcast and replies.

##### Systems

Systems, Phase B round 1.

Q1: Q1-A. The table costs nothing at runtime and nothing on the happy path, because the compiler checks it only after lookup fails. Against Q1-B: the current E0504 hint says "add an import", and once the names are gone that hint points at nothing. A diagnostic that sends users to a dead end is worse than no hint. Against Q1-C: a deprecation window keeps the lossy `parse_int` callable for another release, and that function is the actual bug. Placement: I move to a §3.2 paragraph (Web/PLT/DevOps). This is a §3.2 rule, and §4.4 is about effects. Support the DevOps fix-class rider: `parse_int` changes type from Int to Result, so an automatic rewrite would produce code that does not compile or that changes behavior. That has to be `manual`.

Q2: I collapse Q2-A and Q2-B. For the spec they are the same. The spec should say "not exported", and whether a private body survives is a codegen detail (the no-impl-details-in-spec rule). I accept Q2-A's wording, with the note that an implementation may keep a private body a method lowers to.

Q3: Q3-A. Against Q3-B: "go through `.iter()`" is wrong twice. First, the crossing door is `.into_iter()` (§3c:18). Second, it costs more. Eager `list.map(f)` is one loop into a `List.with_capacity(n)`. A lazy `into_iter().filter(p).collect()` builds iterator state for each stage, and `collect` cannot know the size, so it grows the buffer as it goes. §3c:11 already promises eager collection adapters, so the table only records what the spec says. On `for_each`, I accept AI/ML's set without it. A `for` loop compiles to the same code, and Blink does not need two ways to write a loop.

Q4: I move from Q4-D to Q4-C: `filter`, `map_values`, `fold`, `merge`, no `for_each`. That is the same reason as Q3: `for (k, v) in m` allocates nothing and is the one way to loop. Against Q4-A and Q4-B, which drop `fold`: an `entries()` chain allocates a whole `List[(K, V)]` just to reduce it to one value. That is an O(n) allocation that buys nothing. `filter` and `map_values` through entries plus `Map.from` allocate twice. Naming: `merge`, not `union`. `Set.union` is symmetric. A map combine is right-biased, so it is not symmetric, and the name `union` hides that bias. State the bias in the signature row: "entries in `other` win; insertion order of `self`, then new keys of `other`".

Q5: Q5-A. Against Q5-B: `Str.from_code_point` would have to return `Result` too, which gives two fallible constructors around one check. `Char.from_code_point(n)?` is the single checked gate. A Str built from an unchecked code point is invalid UTF-8 in memory. That is the soundness bug, so the gate must stay single.

Q6: I collapse Q6-B into Q6-A. A public `json.escape(s)` is not a method twin, because no method does this, and users who write JSON by hand need it. The only condition is that `derive(Serialize)` codegen calls the same function (src/cg_derive.bl:1850, 1945 get renamed). I oppose Q6-C's "delete", which breaks derive codegen.

Riders:
- Sys (no lossy parse): I keep it.
- PLT (effect transparency): I support it. What the hardware sees has to match the source: the effect of an eager adapter runs at the call, and the effect of a lazy one runs at the consuming call. The spec must say both.
- Web and DevOps fallbacks: I oppose them as moot if Q4-C or Q4-D passes. If Map methods fail, I prefer the DevOps `manual` row. A "temporary exception" with a date never gets removed.

STABLE

##### Web/Scripting

Web/Scripting, Phase B round 1: positions on Q1-Q6 and the riders.

**Q1: A (permanent table), placed as a new paragraph in §3.2.** I also support DevOps's fix-class rider. The `manual` class is right for parse_int/parse_float, because the return type changes from Int to Result. Auto-rewriting that would hide the semantic change, and the semantic change is the whole point. Against Q1-B: today's E0504 hint says "add import list.{list_map}". After removal that hint is wrong, and we have to change the diagnostic anyway. Making it name `.map` costs one table. Against Q1-C: a one-release `@deprecated` window helps only people who upgrade in that window. Code written in the old style (including LLM training data, which never upgrades) keeps showing up forever. §4.4 already set the precedent "keeps the table for good", so follow it. On placement: §4.4's table is about effects and has an Effect column. Putting `str_trim` in it would confuse readers. Use §3.2.

**Q2: collapse A and B.** Neither is spec text. The spec should say only "not part of the public API". Whether a method lowers to a private body is codegen's business. If the panel needs a pick: A, and B where a method body really needs it.

**Q3: A, full set, but I drop `for_each` (moving to AI/ML's list).** Against Q3-B (map only): `filter` is used as often as `map`. A JS or Kotlin dev who writes `xs.map(f)` and then `xs.filter(g)` and gets an error will ask "why does map work and filter doesn't?" That is the exact SO question this ticket exists to kill. Half a set is worse than none or all of it. I drop `for_each` because `for x in xs` is already the one way to run an effect per item, and two spellings for that is the same sin we're removing.

**Q4: moving to C: `filter`, `map_values`, `fold`, `merge`. No `for_each`.** For consistency with Q3, `for (k, v) in m` (03_types.md:5824) is the way. Naming: `merge`. JS (`Object.assign`/spread), Python (`|`, "merge dicts") and Kotlin users all search for "merge". `Set.union` is symmetric and lossless. A right-biased map combine is neither, so calling it `union` hints at a property it lacks. I agree with PLT that the spec must state the bias in one sentence: "on a key in both maps, the value from the argument wins." Against Q4-A: `m.entries().iter().filter(...).collect()` returns a List, not a Map, and there's no `Map.from` in the brief's MapOps, so "filter a dict" turns into a for loop plus a mutable map. That is a 5-minute task that should take 5 seconds.

**Q5: moving to A.** `Char.from_code_point(n)?` already exists (03c_protocols.md:538-543) and correctly returns a Result. My `Str.from_code_point` would be a second spelling. I withdraw it.

**Q6: A, public `json.escape(s)`.** Sys's point actually supports A: derive(Serialize) codegen calls it from user modules, so it has to be reachable from them anyway. "Public but undocumented" is a lie the docs would have to keep telling. Make it a normal, named, documented function in std.json. Against C (private): breaks derive codegen unless we add a visibility hack.

**Riders:**
- Sys, "no lossy parse function in std": support. It's one sentence and it blocks this from coming back.
- PLT, effect transparency: support. Users will ask "why does my mock handler fire later?" with lazy `map`, and the spec should answer that before they ask.
- My own rider (temporary `map_*` exception): withdrawn if Q4-C or Q4-D passes. Otherwise it is my fallback.
- DevOps `manual` row for map_*: support it as a fallback only if Q4 lands on A.

STABLE

##### PLT

PLT, Phase B round 1: positions on Q1-Q6 and riders.

**Q1: A (permanent table), placed as a new paragraph in §3.2.** §4.4 removes names for effect reasons. Mixing in the method-twin removals blurs why each name left. I support the DevOps fix-class rider, and the reason is about types, not tooling. The `parse_int` fix changes `Int` to `Result[Int, ConversionError]`. A rewrite that changes the result type is not a mechanical rewrite, so it must be `manual`.
- Against Q1-B: the current E0504 help says `import list.{list_map}`. After removal that hint points at nothing. Old names also stay in training corpora for good, so a one-release hint ends before the misuse does.
- Against Q1-C: deprecating for one release keeps the lossy `parse_int` callable for that release. A wrong total function should not get a grace period.

**Q2: collapse A and B.** The spec says only "no public name." Whether a private body stays behind a method is a lowering choice, a codegen chore, not spec text.

**Q3: A, minus `for_each` (changed position).** `for_each` is the one adapter that returns `Void`. It is a `for` statement in disguise, so keeping it gives two forms for one operation, which Principle 2 rules out. `fold` stays: it is an expression and needs no `mut` accumulator, which a `for` loop does.
- Against Q3-B: §3c already makes "collection method in, collection out" normative. With only `map`, `xs.filter(p)` must leave through `.into_iter()…collect()` while `xs.map(f)` does not, so the rule holds for one adapter and fails for the rest. That is an arbitrary carve-out, not minimalism. (Note: the spec door is `.into_iter()`, not `.iter()`.)

**Q4: C (`filter`, `map_values`, `fold`, `merge`; no `for_each`), for the same reason as Q3.** On naming I concede to `merge`. Haskell's `Data.Map.union` is left-biased, so `union` would bring the wrong bias with it. `merge` reads as "the other one wins" (Python `|`, JS spread). Condition: the spec text must say "on a duplicate key, the value from `other` wins; key order follows §3.2 Map order." A combine operation whose bias is not stated has no typing contract.
- Against Q4-A: §3c names `Map` as a collection. With no eager methods, the governing rule is false for one of its five named collections. `entries` → iterator → `collect` → `Map.from` crosses the boundary twice for a map-to-map operation.

**Q5: A.** Against Q5-B: `Str.from_code_point` must be partial (`Option[Str]`), so it would repeat `Char.from_code_point`'s validity check under a second name. That is two constructors for one predicate.

**Q6: A, with B as second choice.** The two are compatible: generated `derive(Serialize)` code can call a `pub` function. Escaping a JSON string is total and well defined, and users who build JSON by hand need it. Against C: deleting it breaks derive codegen (src/cg_derive.bl).

**Riders:**
- Sys "no lossy parse function": support strongly. This is the soundness core of the ticket.
- PLT effect rider: keep it. Eager effect = effect of `f`, at the call. For lazy adapters, the effect occurs at the consuming call. Leaving that out of §3c is a real gap in the effect story.
- Web temporary `map_*` exception: oppose. A dated exception to a 4-1 rule is how the duplicates got here.
- DevOps `manual` row for `map_*`: support, but only as the fallback if Q4 fails.

STABLE

##### DevOps

DevOps, Phase B round 1.

**Q1: A. §3.2 paragraph, with the fix-class rider.** Against Q1-B: today's E0504 hint says "add an explicit import, e.g. import list.{list_map}". Once the bodies are gone, that hint points at nothing. A user (or an LLM trained on 0.5x code) then gets a bare "undefined function list_map" with no path forward. The parse_int row matters most of all. A bare E0504 invites the user to write their own `fn parse_int` that copies the lossy one. The row has to say "the method returns Result; the old one returned 0 for bad text." That is spec-level behaviour of E0504 (§4.4 already makes it so), not a tooling chore. Against Q1-C: there is no edition to name, and W2000 keeps the names in completion lists, which is the thing we are trying to stop. The table is data, it costs nothing at runtime, and the compiler consults it only after lookup fails. Placement: §3.2. §4.4's table is justified by the effects rule. Mixing "removed because effectful" with "removed because methods-only" muddles both rationales. The two tables share one mechanism sentence, which is fine. The fix class must be normative, because `blink fix` must never auto-apply a rewrite that changes the type (parse_int → Result).

**Q2: collapse A and B.** Delete the body unless a method lowers to it. If one does, drop `pub` so the body is internal. Users see the same outcome either way: the name is not exported. Which bodies survive is a codegen chore, not spec text.

**Q3: A, without `for_each`.** `xs.` completion must show `map`/`filter`/`fold`, because users and models write `xs.filter(...)` first and a "use .iter()...collect()" error on every such call is friction for nothing. `for_each` on List duplicates a plain `for` loop, and a lint would then have to pick between them. Iterator already has it for chain tails. Minimalism's Q3-B has a cost: every `list_filter` row becomes a two-step `xs.iter().filter(f).collect()` fix instead of a one-token method rewrite.

**Q4: C (`filter`, `map_values`, `fold`, `merge`; no `for_each`).** I am moving from B to C. Once List gets eager `fold`, leaving it off Map is an inconsistency that people will report as a bug. No `for_each`, for the same reason as Q3. Name it `merge`, not `union`. `Set.union` is symmetric and `merge` is right-biased. Sharing the name would hide the asymmetry, and that asymmetry is exactly what the user must know. I support PLT's demand that the spec state the bias: "on duplicate keys, the argument's value wins." Against Q4-A: `Map.from(entries().iter().filter(...).collect())` is a fix-it nobody can apply mechanically and nobody reads.

**Q5: A.** It is a `manual` row, because the result changes from Str to Result. Against Q5-B: `Str.from_code_point` would be a second path beside `Char.from_code_point`, which is the duplication this ticket removes.

**Q6: I am moving to B and C combined: not in the public API, but kept in std.json as a non-public helper that the derive codegen calls.** I withdraw Q6-A on YAGNI grounds. Users who serialize do so through `json.encode`/derive, which already escapes. Nobody has asked for a public `escape`, and we can add it later without breaking anything.

**Riders**
- Sys, "No lossy parse function exists in the standard library": support. One line that closes the class of bug.
- PLT, effect-transparent eager adapters and effect-at-consumer for lazy ones: support. For a lazy chain, the diagnostic must point at the consuming call, with a secondary span on the closure that has the effect. Without the spec sentence, LSP hover would lie about where the effect fires.
- Web, a temporary `map_*` exception: oppose. A dated exception means a second removal later, and twice the migration noise.
- My own rider (a `manual` row pointing to a `for` loop) applies only if Q4 fails. Keep it as the fallback.

STABLE

##### AI/ML

AI/ML Phase B round 1 positions on Q1-Q6 and the riders, ending STABLE.

**Q1: A.** I put it in §3.2, next to the rule it enforces. I support the DevOps fix-class rider.
Against Q1-B: the current E0504 help says "add an explicit import, e.g. import list.{list_map}". That hint sends a model straight to the form we are removing. "No table" leaves a diagnostic that teaches the wrong answer.
Against Q1-C: one minor release is far shorter than the time old training data stays in the wild. Models will write `list_map` for years. A permanent row costs nothing, because the compiler checks it only after lookup fails, and every stale model gets one-turn self-correction.

**Q2: A and B collapse.** The spec should say "no `pub` free function". Whether a private body survives as a lowering target is a codegen detail (no impl details in sections/). I vote for that wording and leave the bodies to implementation.

**Q3: A, and I now include `for_each`.** I am changing my position. My principle: **the eager List adapter names equal the Iterator adapter names that make sense eagerly.** Iterator already has `for_each`. If List lacks it, a model that learned the Iterator surface writes `xs.for_each(f)` and gets an error. Mirroring adds no decision point, because the model learns one name set and uses it in both worlds.
Against Q3-B: `xs.map` works but `xs.filter` does not. That asymmetry fails on the second most common call in every language a model trained on. It adds an exception to learn, and that cost is higher than the methods we save.

**Q4: D, named `merge`, with the right bias stated.** Same mirroring principle: Map gets `filter`, `map_values`, `fold`, `for_each`, `merge`. I drop my no-`for_each` position for consistency with Q3.
On naming: the token models predict is `merge`. PEP 584 calls dict `|` "merge", JS uses `merge`/`Object.assign`, Kotlin has `plus`, and lodash has `merge`. `union` on Set has no collision to resolve, but on Map it hides that one side wins. The spec text should read: "`a.merge(b)`: on a key in both, the value from `b` wins."
Against Q4-A: `Map.from(m.entries().into_iter().filter(...).collect())` costs about 20 tokens against 6. It is also the form models get wrong most often (tuple destructuring in closures).
Against Q4-B: dropping `fold` while List has `fold` brings back an asymmetry.

**Q5: A.** `Str.from_code_point` would be a second door to the same value, and it would hide the `Result`.

**Q6: A and B collapse.** Make `json.escape(s)` public, and let `derive(Serialize)` codegen call it. One public name serves both. Against C: users who write JSON by hand need it, and if we delete it they paste a broken escape function.

**Riders:**
- **Sys (no lossy parse): support.** It is one sentence that kills the worst trap in this ticket.
- **PLT (effect transparency): support.** A model needs to know where `f`'s effects land. "The effect runs at the consuming call" is exactly the sort of fact a model cannot infer without the spec saying it.
- **Web (temporary `map_*` exception): oppose.** A "temporary" public function in this repo becomes permanent training data. If the Map methods fail, take the DevOps fallback instead.
- **DevOps (`manual` row pointing to a `for` loop): support as the fallback only.**

STABLE

##### Minimalism

Minimalism, Phase B round 1.

I checked §3c:11 and decisions/iterator-protocol.md D2. Collection adapters are already settled as eager (5-1, with me as the recorded dissent), and §3c:11 names Map as a collection. Repo code already calls eager `list.filter(...)` (e.g. tests/test_build_and_run_print_a_source_warning_once.bl:29). So a large part of Q3/Q4 brings the ListOps/MapOps tables up to a vote that is already law. It does not add new surface. I lost that vote and do not reopen it here. I move where that fact forces me to.

**Q1 -> Q1-A, with conditions.** Five seats and the §4.4 precedent outweigh my cost argument. The precedent also makes the rows cheap: they cost nothing until a lookup fails. Conditions:
- Placement: a new paragraph in §3.2, not the §4.4 table. §4.4's table exists because of effect Rule 1 ("Rule 1 removes them"). Putting pure functions there blurs why the table exists.
- Oppose the DevOps fix-class rider as spec text. Whether `blink fix` auto-applies a row is tool behaviour. Put it in a tooling chore. In the spec, the `parse_int` row only needs to say the replacement returns `Result`. That says enough.
- Q1-C (my M2) is withdrawn.

**Q2: collapse A and B.** The spec should say nothing about it. "Not public" is the only normative fact. Whether a method lowers to a private body is codegen. One hard line: the lossy `parse_int`/`parse_float` bodies get deleted, not made private. No method should ever lower to them.

**Q3 -> Q3-A minus `for_each`** (AI/ML's set). §3c already promises these, so the table catches up. `for_each` on a List is a second way to write `for x in xs { }`, which is the primary iteration construct (§3c.1 line 1). Principle 2 rules it out. The same holds on Iterator, but that is out of scope.

**Q4 -> Q4-B** (`filter`, `map_values`, `merge`). This moves me from Q4-A. "Collection in, collection out" (§3c:11) makes `m.filter(...) -> Map` the expected form, and `merge` has no one-line equivalent (it needs a mutable loop). Oppose `fold` and `for_each` on Map: `for (k, v) in m` and `m.entries().into_iter().fold(...)` already cover them, so these would be a second way. On naming, `merge` vs `union`: I take `union` if Set has it, since one name per concept across collections. The spec must state that the right side wins on key clash either way.
Flag for the moderator: D2's headline says "Eager collection adapters -> List". That clashes with "collection in, collection out" for Map/Set. Someone must settle what `m.map(...)` returns. That is the sibling ticket or a new friction ticket, not this one.

**Q5 -> Q5-A.** A `Str.from_code_point` would be a second constructor beside `Char.from_code_point(n)?` plus `"{c}"`. It is the same kind of duplicate this ticket removes.

**Q6: collapse B and C** into "not public; it stays in std.json as the target the serializer and derive codegen call". Oppose Q6-A. This ticket removes surface. Adding a public `json.escape` belongs on its own ticket, with a user who asked for it. No one has.

**Riders.**
- Sys "no lossy parse function in std": support. It is one sentence and it blocks the exact bug we are fixing from coming back.
- PLT eager effect transparency: support only if it restates what the `! _` row variable in the signatures already gives. The lazy-iterator effect-timing half: oppose here. It is a real question, but out of scope. File it as friction.
- Web temporary `map_*` exception: oppose. With Q4-B there is nothing left to excuse, and dated exceptions do not get removed.
- DevOps `manual` rows for Map: moot under Q4-B. Oppose as spec text for the same reason as Q1.

Correction to my Phase A examples: the door is `.into_iter()`, not `.iter()`.

STABLE

#### Phase C — Final vote

##### Phase C tally (round 1)
| Item | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|---|---|---|---|---|---|---|---|
| Q1 | A | A | A | A | A | A | A 6-0 |
| Q1-R | NO | NO | NO | YES | YES | NO | NO 4-2 (soft consensus: majority concerns endorse "chore must forbid auto-applying type-changing rows") |
| Q2 | B | B | B | B | B | B | B 6-0 |
| Q3 | A | A | A | A | A | A | A 6-0 |
| Q4 | B | B | B | B | B (corrected from C) | A | B 5-1 |
| Q4-N | merge | merge | merge | merge | merge | union | merge 5-1 |
| Q5 | A | A | A | A | A | A | A 6-0 |
| Q6 | A | A | B | A | A | B | A 4-2 -> Phase D |
| R1 | Y | Y | Y | Y | Y | Y | 6-0 |
| R2 | Y | Y | Y | Y | Y | Y | 6-0 |
| R3 | Y | Y | Y | Y | Y | N | 5-1 |

Concerns of note: merge must state shallow + key order (Sys, Web); bias in MapOps row (Min, DevOps, AI/ML); fold param order (AI/ML); for_each not-found help -> `for` (Sys, PLT, Web, AI/ML, DevOps); D2 vs §3c:11 m.map return type -> friction (PLT, Web, Min); Q6-B needs sanctioned visibility path (PLT, Sys).
Q6 R2: Q6-B 6-0 (R1 4-2 for A)

##### Systems

Systems, Phase C vote.

**Q1: Q1-A.**
Reasoning: The compiler checks the table only after lookup fails, so it costs nothing at runtime or on the happy path. Without it, today's import hint sends users to a name that no longer exists.
Concern: The table only ever grows, and one day it will collide with a name that std adds again for a different reason.

**Q1-R: NO.**
Reasoning: Q1-A already makes each row state when the result type changes. That is the normative fact. Whether `blink fix` applies a row follows from it and is tool behavior. Putting tool behavior into sections/ is an implementation detail in the spec.
Concern: If YES wins, the spec ties `blink fix` semantics to one table, and every new tool has to copy that.

**Q2: Q2-B.**
Reasoning: A private `atoi`-style body is a trap for internal callers. src/lsp.bl:25 and lib/std/http_client.bl:165 already hit it. Every other body can survive as a lowering target, since that is codegen's business. The lossy parsers must go, so that no method or internal path can ever lower to them.
Concern: The impl ticket could treat "delete" as optional and quietly keep the bodies for one internal caller.

**Q3: Q3-A.**
Reasoning: An eager adapter is one loop into a buffer sized up front. That is what the hardware wants, and §3c:11 already promises it. `for_each` compiles to exactly the code `for x in xs` gives, so it adds a second spelling and no capability.
Concern: Iterator keeps `for_each` while List lacks it, so some users will hit an error on `xs.for_each`. The E0504/method-not-found help must point them to `for`.

**Q4: Q4-B (`filter`, `map_values`, `fold`, `merge`).**
Reasoning: Without `fold`, the replacement is `entries()`, which allocates a whole `List[(K, V)]` just to reduce it to one value. That is an O(n) allocation that buys nothing. `for_each` is `for (k, v) in m` again, so it adds no capability.
Concern: Whichever option wins, `merge` must state its order as well as its bias. Without that it stays under-specified.

**Q4-N: `merge`.**
Reasoning: `Set.union` is symmetric and loses nothing. A map combine drops one side's value on a shared key, so it is neither. The name `union` would hide that bias, and Haskell's left-biased `Data.Map.union` shows the trap. Key order should still mirror the §3.2 union order rule: `self`'s order first, then the new keys of `other`.
Concern: With `merge`, people may expect a deep merge of nested maps. The spec must say it is shallow.

**Q5: Q5-A.**
Reasoning: `Char.from_code_point(n)?` is the single checked gate. A Str built from an unchecked code point is invalid UTF-8 in memory, which is a soundness hole. A second constructor would duplicate the check or skip it.
Concern: The `"{c}"` round trip allocates for every character in hot loops. Watch for a perf ticket asking for a `StringBuilder.push_char` path, not a new Str constructor.

**Q6: Q6-A.**
Reasoning: `derive(Serialize)` emits code into user modules, and that code calls the escaper. A non-public target therefore needs a special visibility rule for compiler-emitted calls, which is a hidden rule in the module system. A public `json.escape(s)` compiles identically and needs no exception.
Concern: If Q6-B wins, the impl must not add an ad-hoc "codegen may call private items" bypass without spec text for it.

**R1: YES.**
Reasoning: One sentence keeps the `atoi` bug class out of std for good.

**R2: YES.**
Reasoning: The cost and the effect of an eager adapter happen at the call site. The spec must match what runs.

**R3: YES (in this decision).**
Reasoning: Lazy adapters move both the work and the effect to the consuming call. That is the defining runtime property of the lazy world, and the spec must state it beside the eager half. Splitting the halves leaves an effect story with only half its timing rule.

Concern for the riders: If R3 goes to friction, the §3c text will describe the eager timing but not the lazy one. Readers will then assume the effect runs at `.map()`.

##### Web/Scripting

Web/Scripting, Phase C vote: Q1-A, Q1-R NO, Q2-B, Q3-A, Q4-B, merge, Q5-A, Q6-A, R1 YES, R2 YES, R3 YES.

**Q1: Q1-A.**
Reasoning: today's E0504 hint tells a newcomer to `import list.{list_map}`, which sends them to the form we are deleting. A row that says "use `xs.map(f)`" turns a confusing error into a 5-second fix. That is the whole DX win of this ticket. Rows cost nothing until lookup fails, and §4.4 already set the "keep it for good" precedent.
Concern: the table may grow into a junk drawer that nobody prunes or tests. Each row needs a test that calls the old name and asserts that the fix text names the method.

**Q1-R: NO (I changed this from round 1).**
Reasoning: Q1-A as worded already makes each row state when the result type changes. That is the fact users need, and it decides the fix class by itself (a type change cannot be a blind rewrite). What `blink fix` does with that flag is tool behaviour. Put it in the tooling chore, where it can change without a spec vote. Min's argument convinced me.
Concern: if the chore slips, `blink fix` may auto-rewrite `parse_int(s)` → `s.parse_int()` and leave code that won't compile.

**Q2: Q2-B.**
Reasoning: "not exported" is enough for most bodies. But a private lossy `parse_int` is a trap, because some future method or stdlib author will reach for it. Deleting it costs nothing and fits R1.
Concern: none worth a vote. The impl ticket must just say it.

**Q3: Q3-A.**
Reasoning: JS, Kotlin and Python-comprehension users expect `xs.map` and `xs.filter` side by side. §3c:11 already promises them, so the table catches up. No `for_each`, because `for x in xs` is the one way to loop and two spellings creates the "which is idiomatic?" question.
Concern: a user who learned `it.for_each` on Iterator will try `xs.for_each` and hit an error. The E0504/method-not-found help should suggest `for x in xs`.

**Q4: Q4-B (`filter`, `map_values`, `fold`, `merge`).**
Reasoning: filtering or transforming a dict is a daily scripting task. Without these it turns into a mutable-map loop. `fold` stays for parity with List. If List has it and Map doesn't, users will file that as a bug. No `for_each`, same as Q3.
Concern: users will expect `m.map(f)` next to `map_values`. What that returns (D2 "→ List" vs "collection in, collection out") is still open and should go out as friction.

**Q4-N: `merge`.**
Reasoning: "merge dicts" is what JS/Python/Kotlin devs search for and what models predict. `Set.union` is symmetric. A right-biased map combine is not, and calling it `union` hints at a property it lacks.
Concern: people coming from lodash may assume a deep merge. The spec sentence should say "shallow; the argument's value wins".

**Q5: Q5-A.**
Reasoning: `Char.from_code_point(n)?` already exists and returns a Result. A second Str constructor would be the exact duplication this ticket removes.
Concern: the two-step `Char` then `"{c}"` is slightly less discoverable. The removed-name row must show both steps.

**Q6: Q6-A.**
Reasoning: derive codegen already needs it callable from user modules. "Reachable but secretly not public" is a doc lie and a visibility special case. Hand-rolled JSON escaping is a classic bug, so a documented, correct `json.escape` is a cheap guard.
Concern: it may tempt people to build JSON by string concat instead of `json.encode`. The doc should point to `json.encode` first.

**R1: YES.**
Reasoning: one sentence that stops the `parseInt("12x") === 12` trap from coming back.
Concern: none.

**R2: YES.**
Reasoning: users need to know that a closure with an effect makes the adapter call effectful. That matches their intuition, and the spec should say so.
Concern: none.

**R3: YES.**
Reasoning: "why did my effect fire at `.collect()` and not at `.map()`?" is a certain Stack Overflow question. Answering it in §3c costs one sentence, and splitting it into a separate friction ticket means it gets left out.
Concern: the error span must point at the consuming call and also mark the closure, or users will still be confused.

##### PLT

PLT, Phase C ballot.

**Q1: Q1-A.** A removed name is a closed, finite set with a known replacement, so the diagnostic should be complete over that set. A one-release hint leaves the mapping partial. The "states when the result type changes" clause is the important part: `parse_int` goes from `Int` to `Result[Int, ConversionError]`, and that is a change of contract, not a rename. Concern: a later row may get its type-change flag wrong. It needs a check that the replacement's type matches the type the row states.

**Q1-R: NO (changed from round 1).** Q1-A as written already puts the type-theoretic fact in the spec: each row states whether the result type changes. Whether `blink fix` acts on that fact is tool policy derived from it, so it belongs in a tooling chore. Concern: if the chore never lands, a naive fix may rewrite `parse_int` and leave a `Result` where an `Int` was expected. That gives a type error, which is loud, not silent, so the risk is bounded.

**Q2: Q2-B.** A lossy total function that sits in for a partial one must not survive even as a private lowering target, because a future method could quietly lower to it. Deleting the body makes the R1 invariant hold by construction, not by convention. Concern: the impl ticket may treat "delete" as optional, so it should say so in its acceptance criteria.

**Q3: Q3-A.** Each listed adapter returns a value: a collection, a fold result, or a query answer. That makes it an expression with a typing rule. `for_each` returns `Void` and is the `for` statement under a second name, which breaks Principle 2. Concern: AI/ML's point stands. A model that learned `Iterator.for_each` will try `xs.for_each`. E0504 / E0xxx help must point at `for x in xs`.

**Q4: Q4-B.** `fold` is the catamorphism. It is an expression that needs no `mut` accumulator, and dropping it from Map while List has it makes the eager surface inconsistent across collections. `for_each` is out for the Q3 reason. Concern: Min's flagged D2 conflict ("eager adapters → List" vs "collection in, collection out") is real. Without a ruling, `m.map(...)` has no defined result type. File it as friction.

**Q4-N: `merge`.** Set union is commutative, and the map combine is not, because the right side wins. Reusing the name `union` would suggest a law that does not hold. Concern: none. The bias sentence is in every option.

**Q5: Q5-A.** One partial constructor guards the code-point predicate, and `Str` follows from `Char` by a total map (`"{c}"`). Concern: none of substance.

**Q6: Q6-B (changed from round 1).** Adding a public name later is not a breaking change, and removing one is. Under uncertainty, choose the reversible option. No user has asked for it. Concern: derive codegen in user modules must reach a non-public std.json function. The impl must use a sanctioned visibility path, not a hack.

**R1: YES.** This is the soundness invariant the whole ticket exists for. One sentence rules out the class of bug, not just this one case. Concern: none.

**R2: YES.** An eager adapter is a higher-order function: its row equals the row of `f`, and the effect occurs at the call. Stating this costs one line, and it is what the `! _` row variable means in the signature. Concern: none.

**R3: YES (in this decision).** This is not new semantics. It states when an effect occurs for the lazy twins of the same adapters this decision lists, and leaving it out leaves the effect story for this surface half done. Concern: it may be read as reopening the iterator protocol. The text should be one clarifying sentence in §3c, not a new rule.

##### DevOps

DevOps, Phase C vote.

**Q1: Q1-A.** A diagnostic that names the fix is the whole user-facing payoff of this ticket. Today's E0504 hint ("add import list.{list_map}") becomes a dead end the moment the bodies go. The rows cost nothing until lookup fails, as in §4.4. Concern: the table drifts if someone later adds a std name that collides with a row. The compiler consults the table only after lookup fails, so the new name wins silently, which is correct, but the row should then be pruned.

**Q1-R: YES.** Whether a rewrite changes the result type is a semantic fact about the row, not a tool preference. §8.6 already makes "machine-applicable" part of the normative diagnostic and `blink fix` contract. If the class lives only in a chore, an implementer can make `blink fix` rewrite `num.parse_int(s)` into `s.parse_int()` and produce code that fails to compile or, with an inserted `?`, behaves differently. Concern: Minimalism is right that this sits at the spec/tooling edge, so the §3.2 text should state it as one column, not a paragraph of tool rules.

**Q2: Q2-B.** Only the name is normative, but the lossy bodies are the bug. If one survives as a private body, the next internal caller (as src/lsp.bl:25 did) inherits the 0-on-garbage behaviour. Putting this in the impl ticket is enough; it need not be spec text. Concern: the requirement gets lost if the impl ticket does not quote it word for word.

**Q3: Q3-A.** `xs.` completion should offer the adapters that §3c:11 already promises. `for_each` would be a second loop spelling, and a lint would then have to pick one. Concern: AI/ML's mirroring point is real. A model that writes `xs.for_each(f)` gets E-undefined-method, so that diagnostic should suggest `for x in xs { }`. File that as a tooling chore.

**Q4: Q4-B.** `fold` keeps Map consistent with List, and Sys showed the entries-chain alternative allocates a full List for nothing. No `for_each`, for the same reason as Q3. Concern: the right-bias sentence must appear in the MapOps row itself, not only in prose, or LSP hover will not show it.

**Q4-N: merge.** `Set.union` is symmetric. A right-biased combine under the same name hides the one fact hover text must convey. Every neighbouring ecosystem's users search for "merge". Concern: if Set ever gains a biased combine, the names diverge again.

**Q5: Q5-A.** It is a `manual` row, because the result becomes Result. One checked gate (`Char.from_code_point`) means one diagnostic story. Concern: the fix text must show the full `?` then `"{c}"` form, or users will `.unwrap()` it.

**Q6: Q6-A. I am changing from B/C.** The Web and Sys argument decided it for me. Derive(Serialize) expands into user-module code. If the target is private, go-to-definition, `blink expand`, and error spans inside derived impls point at a name the user cannot write or import. A public, documented `json.escape` keeps the tooling honest, at the cost of one name. Concern: it becomes a std surface we must keep stable, so its doc must pin the exact escape set (control chars, `"`, `\`, and whether `/` is escaped).

**R1: YES.** One sentence that blocks the root bug from coming back. Concern: none worth a line.

**R2: YES.** An LSP hover on `xs.map(f)` must show `f`'s row as the call's row. The spec has to say so. Concern: the sentence may just restate the `! _` row variable, which is harmless.

**R3: YES (in this decision).** Diagnostics for a lazy chain must put the primary span at the consuming call and a secondary span on the effectful closure. Without the spec sentence, the compiler and the LSP may disagree about where the effect fires. Concern: it widens a std-cleanup ticket into §3c effect semantics. Keep the text to one sentence.

##### AI/ML

AI/ML Phase C ballot. Votes per item, with reasoning and concern.

**Q1: Q1-A.**
Reasoning: Models trained on 0.5x code will write `list_map` and `num.parse_int` for years. A row that names the replacement turns each of those calls into a one-turn fix. Stating the result-type change in the row (`Int` becomes `Result`) is the fact a model needs in order to add the `?` and handle the error.
Concern: the rows may say "use `.parse_int()`" without saying that it returns `Result`, so the fix still fails to compile on the first try.

**Q1-R: YES.**
Reasoning: AI agents run `blink fix` in a loop without review. Whether a row is auto-applied is a contract they rely on, so it belongs in the spec and not only in a tool's behaviour. A type-changing rewrite (`parse_int`, `str_from_code_point`) that is applied in silence makes code that does not compile, or that changes behaviour.
Concern: if this passes as NO, a later tooling change could start auto-applying `manual` rows, and nothing in the spec would forbid it.

**Q2: Q2-B.**
Reasoning: I agree the spec should only say "not exported". But the lossy bodies are a trap: a private body can be re-exported by mistake or used as a lowering target. That puts the bad contract back where nobody can see it. Make the deletion an impl-ticket requirement, not spec text.
Concern: none of substance. This only constrains the impl ticket.

**Q3: Q3-A (no `for_each`).**
Reasoning: I move back from my round-1 position. One loop form is one fewer decision point, and that outweighs my mirroring argument. A model that writes `xs.for_each(f)` needs only a good error.
Concern: models will write `xs.for_each` often (JS habit). The unknown-method error on List and Map must suggest `for x in xs { }`, or this becomes friction. Please put that on the impl ticket.

**Q4: Q4-B (`filter`, `map_values`, `fold`, `merge`).** [Ballot line originally read "Q4-C... correction: Q4-B"; a follow-up message confirmed Q4-B.]
Reasoning: Map should match the List set. `fold` is on List, so it must be on Map, or a model writes `m.fold` and fails. `for_each` stays off for the same reason as Q3.
Concern: closures that take `(k, v)` against `fold(init, fn(acc, k, v))` need the spec to give the exact parameter order, or models will guess `(k, v, acc)`.

**Q4-N: `merge`.**
Reasoning: `merge` is the token models predict for a dict combine (Python's PEP 584, JS, lodash). `union` brings Set's symmetric meaning, and Haskell's left bias, which is wrong here.
Concern: the bias sentence gets left out of the MapOps row and lives only in prose. It must be in the row.

**Q5: Q5-A.**
Reasoning: There should be one checked entry point that returns `Result`. Two constructors means two forms to learn.
Concern: the `"{c}"` step should appear in the table row, so a model does not try `c.to_str()` and guess.

**Q6: Q6-A.**
Reasoning: Models generating hand-built JSON (logs, test fixtures) write their own escaper badly, missing control characters and `\u` escapes. A public, documented `json.escape` is one name that ends that. Derive codegen calls the same function, so there is no second path.
Concern: Minimalism and DevOps are right that nobody asked for it. If it loses, nothing breaks, and someone can add it later on demand.

**R1: YES.**
Reasoning: One sentence that blocks the worst trap in this ticket from coming back.

**R2: YES.**
Reasoning: Where an effect happens is not something a model can infer. The spec must say it.

**R3: YES (in this decision).**
Reasoning: The eager and lazy halves are one fact about timing. Splitting them leaves models with half of it, and the lazy half is where they get it wrong ("why did my handler fire late?").
Concern: if this goes to friction, it may sit unresolved while the eager half ships, and the spec stays asymmetric.

##### Minimalism

Minimalism, Phase C ballot.

**Q1: Q1-A.** The §4.4 precedent and five seats carry it. Each row costs nothing until name lookup fails, and it turns 38 dead names into one-step fixes. Stating when the result type changes (`parse_int` -> `Result`) is the one row detail that a user needs. Concern: the table becomes a dumping ground. Every later rename adds rows "for good", and no rule ever prunes it.

**Q1-R: NO.** Whether `blink fix` applies a row on its own is tool behaviour, and the spec should not fix tool policy. The Q1-A clause on result-type changes already tells a reader which rows need a human. Concern: if NO wins, the `blink fix` chore may auto-apply `parse_int` -> `.parse_int()` and leave code that does not typecheck. The chore must state the rule.

**Q2: Q2-B.** "Not exported" alone lets the lossy body live on as a private helper that some method later lowers to. That would bring back the exact silent `"12x"` -> 12 bug through the back door. Put the hard requirement in the impl ticket. It need not be spec text. Concern: if Q2-A wins, nothing stops a later refactor from routing `.parse_int()` through the old lossy body.

**Q3: Q3-A.** These are the table catching up with D2, a settled vote. `for_each` is a second way to write `for x in xs { }`, the primary iteration construct, so Principle 2 rules it out. Concern: if Q3-B wins, two ways to iterate become law, and every style guide and LLM must pick one.

**Q4: Q4-A.** "Collection in, collection out" justifies `filter` and `map_values` returning a Map. `merge` is the one op with no one-line equivalent. `fold` is `m.entries().into_iter().fold(...)`, and `for_each` is `for (k, v) in m`. Both would be second ways. Concern: if Q4-C wins, Map has a `for_each` while List does not (under Q3-A), and that mismatch is a new spec bug.

**Q4-N: `union`.** Set already has `union` (03_types.md:794), and the insertion-order rule at 03_types.md:3203 already defines `a.union(b)` ordering. Reusing it gives one name per concept and an order rule we have already specified. Concern: readers may expect a symmetric union and miss that the argument's value wins. The spec sentence on that bias must sit in the MapOps row itself, not only in prose elsewhere.

**Q5: Q5-A.** `Str.from_code_point` would be a second constructor beside `Char.from_code_point(n)?` plus interpolation. That is the kind of duplicate this ticket exists to remove. Concern: none of substance. The `?` makes the failure case visible, which is better than the old silent function.

**Q6: Q6-B.** This ticket removes surface. A new public `json.escape` needs its own ticket and a user who asked for it, and none has. Concern: if Q6-A wins, a public escape function sets the API before anyone has shown a need or settled its contract (ASCII-only output? `/` escaping?).

**R1: YES.** It is one sentence, and it blocks the exact bug class this ticket fixes from coming back. It costs nothing. Concern: someone later reads it as banning saturating or clamping helpers with clear names. The text should say "silently lossy".

**R2: YES.** It only restates what the `! _` row variable in the signatures already gives, so it adds no new rule. Concern: the text grows past a restatement and starts to define effect timing for cases the signature does not cover.

**R3: NO.** Effect timing for lazy iterators is a real question, but it is not this ticket's question. Settling it in a cleanup vote skips the deliberation it deserves. File it as friction. Concern: if YES wins, a rule on lazy effect timing lands with no panel debate on mock handlers and re-traversal (§3c restartable recipes run `f` again on each traversal).

#### Phase D — Round 2 on Q6 (`json_escape_str`)

Round 1 was 4-2 for Q6-A (public). The moderator surfaced one code fact: derive(Serialize) lowers its call to the escaper straight to IR after typecheck (src/cg_derive.bl, src/cg_call.bl), so no visibility check runs on that path.

##### Debate

###### Systems

Systems, Phase D on Q6: I withdraw my Phase C argument and move to Q6-B.

I checked the code, and my premise was wrong. The derive codegen does not emit a source-level call that goes through name resolution. src/cg_derive.bl:1963 `ser_call_part` uses `cg_call_stdlib_symbol` (src/cg_call.bl:5809), which looks up the declaration by module and name and emits a direct IR call to its C symbol. No visibility check runs on that path. It is the same mechanism every built-in method uses to reach its private FFI bridge, and §3c:844 already makes those bridges internal. So Q6-B needs no new visibility rule and no hack. That removes the reason Web, DevOps and I gave for Q6-A.

DevOps's tooling point (`blink expand`, go-to-definition landing on a name the user cannot write) is real. But it applies equally to every method that lowers to a private bridge, and the spec already accepts that. It is not specific to Q6.

That leaves PLT's argument, which holds. Adding `json.escape` later breaks nothing, and removing it does. Minimalism and DevOps also named a real gap: nobody has settled the contract (whether `/` is escaped, whether output is ASCII-only). A public name with an unsettled escape set is a stability promise we cannot keep yet.

Vote intent: Q6-B. If someone asks for a public escaper, it gets its own ticket that pins the escape set first.

###### Web/Scripting

Web/Scripting, Phase D on Q6: I hold Q6-A.

PLT's reversibility argument counts only one side. Q6-B doesn't avoid adding surface. It moves the surface into the module system as a rule that compiler-emitted code may call private std items. Users never asked for that rule either, it is harder to explain ("why does `blink expand` show a call I can't write?"), and it is harder to take back than one function, because other derives will start using it. One public name is the smaller, more honest change.

Minimalism and DevOps are right that the contract must be pinned. I'll make that a condition of my A vote rather than a reason for B. The doc states the RFC 8259 escape set: `"`, `\`, and U+0000–U+001F (short forms `\n \r \t \b \f`, else `\u00XX`). `/` is not escaped. Non-ASCII passes through as UTF-8. The return value is without the surrounding quotes. That's three lines of doc and it closes the "ASCII-only? `/`?" question.

On "nobody asked": nobody files a ticket for a function they don't know they need. They paste a broken escaper from Stack Overflow, and it misses `\u0001`. The demand shows up as bugs, not tickets. The doc's first line points to `json.encode` so string-concat JSON doesn't become the encouraged path.

Q6-A, with the escape set pinned in its doc.

###### PLT

PLT, Phase D on Q6. I hold Q6-B.

The visibility argument from Sys and Web does not match how derive works. Derive does not expand into source in user modules. src/cg_derive.bl:1850 and :1945 build IR calls directly (`ser_call_part(ser_str_module, "json_escape_str", …)`), and that happens after name resolution and typecheck. Visibility is a static check on source names, so it never sees these calls. No hidden rule exists and none is needed. Derive already calls into std this way. The same mechanism reaches a non-`pub` function in the same way, the same as any compiler-known lowering target (§3c:844 already makes the FFI bridges internal). So Q6-B needs no new spec text and no bypass.

To DevOps: an error span or go-to-definition inside a derived impl lands on the derive attribute, not on a name the user could write. That holds whichever way Q6 goes.

To AI/ML and Web: the hand-built-JSON risk is real. But the sanctioned answer is `json.encode`, and Web's own concern says the doc must send people there first. A public escaper rewards the string-concat pattern we want to steer away from.

On contract, DevOps and Min agree that a public escape needs a pinned escape set: control characters, `/`, whether output is ASCII-only. Nobody has specified one. Publishing a function before its contract is fixed is the unprincipled step. Adding it later is a non-breaking change, so it can come in its own ticket once there is a use case and a settled contract.

###### DevOps

DevOps, Phase D on Q6. I am moving to Q6-B, because a code fact undercuts the main Q6-A argument, including my own.

The fact: derive(Serialize) is not expanded into user-module source. src/cg_derive.bl:1850 and :1945 build lowered IR directly (`ser_call_part(ser_str_module, "json_escape_str", ...)`). That happens after typecheck and name resolution, so module visibility never sees the call. The same code path also calls `num.float_to_str` (:1946), which this decision already removes from the public surface. So the "codegen calls a non-public std function" path already exists and will be used anyway, whatever Q6 decides. Sys's hidden visibility rule and Web's "reachable but secretly not public" do not apply: nothing in the user's module names the function.

My own Phase C reason, that go-to-definition and error spans inside derived impls point at an unwritable name, also falls. Derived impls have no source text for the LSP to navigate. Spans point at the `derive` attribute.

Without that, what is left for Q6-A is AI/ML's and Web's "hand-built JSON is error-prone". That is real, but it is a feature request with no user behind it. PLT's reversibility argument wins: adding `json.escape` later breaks nothing, while removing it would. And Minimalism's open contract questions (ASCII-only? escape `/`?) are exactly what I flagged in my own concern. Nobody should pin that contract inside a cleanup ticket.

Sys's concern still holds and I keep it as a condition: the impl ticket must record that derive lowering targets std internals by IR, so nobody "fixes" it by making the helper `pub`.

###### AI/ML

AI/ML on Q6: a codebase fact weakens the visibility argument for Q6-A, and I now lean Q6-B.

The Sys/Web/DevOps case says derive(Serialize) puts calls into user-module source, so a private target needs a hidden visibility rule. That is not what the compiler does. src/cg_derive.bl:1850 builds the call as lowered IR (`ser_call_part(ser_str_module, "json_escape_str", ...)`), after typecheck. No user-module source exists, and no visibility check runs against it. Today the target is also in std.str, not std.json. So Q6-B needs no bypass and no new spec rule. Moving the helper into std.json as a non-public item is an impl chore.

DevOps's tooling point (go-to-definition and `blink expand` show a name the user cannot import) is real. But a derived impl already shows compiler-generated code. A span that lands on a std-internal helper is normal there (Rust's derive does the same).

That leaves my own reason: models write bad escapers. That is true, but `json.encode` already covers a model that wants a quoted JSON string, and pointing models at the encoder is the better habit. A bare `escape` invites string-concat JSON, which is Web's own concern.

PLT's reversibility argument holds. Adding the name later breaks nothing. Removing it later is a migration and a permanent table row. Its contract is also unsettled (`/`? ASCII-only?), and a model would learn whichever contract ships first.

I expect to vote Q6-B in the final round. One condition: the impl ticket moves the helper to std.json and keeps it non-public.

###### Minimalism

Minimalism on Q6. I hold Q6-B. The visibility argument behind Q6-A rests on a wrong premise about the code.

Fact check: derive(Serialize) does not write source into user modules. src/cg_derive.bl:1850 and :1945 build IR directly (`ser_call_part(ser_str_module, "json_escape_str", ...)`). That runs in codegen, after typecheck. Visibility is a front-end rule, and IR lowering is not subject to it. So Q6-B needs no "codegen may call private items" rule. The compiler already lowers to C symbols the user cannot name (runtime helpers, mono instances). Sys's and Web's "hidden visibility exception" does not exist, and DevOps's "error span on a name the user cannot import" has no source text to point at.

Second fact: lib/std/json.bl:663 already has a private `fn escape_json_str`. Today std has two JSON escapers. Q6-B merges them into one private function, and derive points at it. Q6-A ships a third public name and then has to settle which of the two current contracts it keeps.

On AI/ML's and Web's point that hand-rolled escaping causes bugs: the fix for that is `json.encode(s)`, which already escapes a Str correctly and returns a valid JSON string literal. A public `escape` is a second way to do the same thing, the duplicate this ticket exists to remove. Web's own concern ("may tempt people to build JSON by string concat") argues for B.

PLT has the decisive point. Adding a name later is cheap, and removing one breaks code. Ship B now. If a user ever shows a case `json.encode` cannot serve, open a ticket for A then.

##### Correction from Minimalism

Minimalism correction to my Q6 Phase D reply. Please relay this with it.

I wrote `json.encode(s)` as the spec'd way to escape a Str. That was imprecise. The spec'd form is `json.stringify(JsonValue.Str(s))` (03_types.md:5424, `json.stringify(value: JsonValue) -> Str`), and §3.6 says its output always parses (5312). The lib today still exposes the older index-based `json_encode(idx: Int)`. The argument stands: a correct, spec'd path for escaping a Str as JSON already exists, so a public `json.escape` would be a second way to do it. My other two facts are verified: derive builds IR at cg_derive.bl:1850/1945, and a private `escape_json_str` already exists at json.bl:663.

##### Final Q6 votes and amendments

##### Phase D final Q6 votes (verbatim)

###### Systems
Vote: Q6-B.

Reasoning: The derive(Serialize) codegen emits a direct IR call to the escaper's C symbol after typecheck (src/cg_derive.bl:1963 → src/cg_call.bl:5809). No visibility check runs on that path, and none is needed, so Q6-B adds no hidden rule. The compiled code is the same either way. The choice is only about public surface, so the reversible option wins. Minimalism found a second escaper, the private `escape_json_str` at lib/std/json.bl:663. Q6-B merges the two into one function. Q6-A would ship a public contract that nobody has settled.

Concern: The impl could leave two escapers in place, or someone could later "fix" the IR call by adding `pub`. The impl ticket must merge them into one non-public std.json function and record that derive reaches it through codegen.

###### Web/Scripting
Web/Scripting, final Q6 vote: Q6-B.

Reasoning: my case for A rested on derive needing a "secret visibility" path. The code facts show it doesn't: src/cg_derive.bl builds IR after typecheck, and the same path already reaches `float_to_str`, which we are making non-public anyway. That leaves "hand-rolled escapers are buggy". Minimalism is right that `json.encode(s)` already gives a correct quoted JSON string, so a public `escape` would be a second way to do the job and would push people toward string-concat JSON, which was my own concern. Adding it later breaks nothing.

Concern: the impl must merge the two existing escapers (lib/std/json.bl:663 `escape_json_str` and `json_escape_str`) into one private function with one tested escape set. Otherwise derive and `json.encode` can drift and emit different JSON for the same string.

###### PLT
PLT final vote on Q6: Q6-B.

Reasoning: Derive lowers to IR after name resolution, so visibility is never in play, and Q6-B needs no new rule. Minimalism found that std already has two escapers (lib/std/json.bl:663 `escape_json_str`, private, and std.str `json_escape_str`). Q6-B merges them into one private function. `json.encode(s)` is already the public, total way to escape a string. A public `escape` would be a second form of the same thing, the kind of duplicate this decision removes. Adding the name later breaks nothing, while removing it would.

Concern: when the two private escapers are merged, their contracts may differ (`/`, non-ASCII). The impl ticket must pick one and test that derive output and `json.encode` output stay byte-identical.

###### DevOps
**Vote: Q6-B.**

**Reasoning:** Derive lowers straight to IR after name resolution (src/cg_derive.bl:1850, :1945, via cg_call_stdlib_symbol). A non-public target needs no visibility exception, and a derived impl has no source text where the LSP could show an unwritable name. Web's "hidden rule" has no counterpart in the compiler. That leaves a public escaper as a second path beside `json.encode(s)`, with a contract nobody has settled yet. Minimalism found that std already has two escapers (std.str `json_escape_str` and the private `escape_json_str` at lib/std/json.bl:663). B merges them into one, while A would ship a third, public one. Adding it later is non-breaking. Removing it later costs a table row for good.

**Concern:** The impl ticket must merge the two escapers into one private std.json function and record that derive reaches it through IR, or someone will later "fix" the derive path by making the helper `pub`.

###### AI/ML
AI/ML final Q6 vote: Q6-B.

Reasoning: Derive lowers to IR after typecheck, so a non-public target needs no new visibility rule. That removes the main argument for Q6-A. For code generation, `json.encode(s)` is the one form a model should learn for "make a JSON string". A public `escape` would add a second form and encourage string-concat JSON. Minimalism found a private `escape_json_str` already in lib/std/json.bl:663. Merging the two escapers into one private function leaves one contract and one name for models to see in the training data.

Concern: the impl ticket might merge the two escapers without checking that their escape sets match, and that would quietly change the output of derive(Serialize). Pin the set (RFC 8259, as Web listed) with a test before merging.

###### Minimalism
**Vote:** Q6-B.

**Reasoning:** Derive lowers straight to IR after typecheck (cg_derive.bl:1850/1945 via `cg_call_stdlib_symbol`). It already reaches `num.float_to_str`, which this decision makes non-public, so B needs no new visibility rule. B merges the two escapers (std.str `json_escape_str` and the private json.bl:663 `escape_json_str`) into one non-public function. A adds a public name whose contract nobody has pinned. Adding `json.escape` later breaks nothing, and removing it would.

**Concern:** The digest left out my correction. The spec'd user path is `json.stringify(JsonValue.Str(s))` (03_types.md:5424), not `json.encode(s)`. The decision text must name that form, or the "use the encoder instead" argument several seats gave points at a call that does not exist.

##### Post-correction ballot amendments (verbatim; all votes unchanged Q6-B)

###### PLT
PLT, revised Q6 ballot: my vote stays Q6-B. I am fixing one reference only.

In my Reasoning, replace "`json.encode(s)` is already the public, total way to escape a string" with "`json.stringify(JsonValue.Str(s))` (03_types.md:5424) is already the spec'd, total way to escape a string, and §3.6 guarantees its output parses."

Concern addition: lib today still exposes the older index-based `json_encode`, so the spec'd `json.stringify` path must exist in lib before the private escaper merge counts as done.

###### Systems
Systems: my Q6 vote stays Q6-B. Minimalism's correction does not touch my reasoning. My ballot never relied on `json.encode`, only on the IR call path and on the private `escape_json_str` at lib/std/json.bl:663, and Minimalism has now confirmed both. The correction makes the case for B stronger. `json.stringify(JsonValue.Str(s))` is the spec'd escaping path, so a public `json.escape` would be a second way to do the same thing.

###### DevOps
My Q6 vote does not change: Q6-B. One wording fix to my reasoning: where I wrote `json.encode(s)`, read `json.stringify(JsonValue.Str(s))` (03_types.md:5424), as in Minimalism's correction. The argument stands, because a spec'd path to a correctly escaped Str already exists. Additional concern, for the impl ticket: the lib still exposes the older index-based `json_encode(idx: Int)` rather than the spec'd `stringify`. That is lib/spec drift. I am not asking for a vote on it, but someone should file it as a chore if no ticket exists.

###### AI/ML
AI/ML: my Q6 vote stays Q6-B after Minimalism's correction.

The correction changes the path's name, not the argument. A spec'd, total way to make a JSON string from a Str exists: `json.stringify(JsonValue.Str(s))`. It costs more tokens than a bare `escape(s)`, but it is one form, and models learn one form best. My concern still holds: pin the escape set with a test before merging the two private escapers. One more note: if the impl or llms docs still teach `json.encode` / the index-based `json_encode(idx)`, models will copy that, so the docs should show `json.stringify(JsonValue.Str(s))` as the example.

###### Web/Scripting
Web/Scripting: my Q6 vote is unchanged, Q6-B. Please replace `json.encode(s)` in my reasoning with `json.stringify(JsonValue.Str(s))`.

Reasoning addendum: the corrected path is wordier than I implied, and a JS dev expects `JSON.stringify("x")`. But a correct, spec'd path still exists, and reversibility still decides it. If users trip on the wrapping, the right fix is a later ticket that makes `json.stringify` easier to call with a Str, not a separate public escaper.

Concern (unchanged, plus one): merge the two escapers into one private function. Also, lib today still exposes the older index-based `json_encode(idx: Int)` and not the spec'd `json.stringify`, so that drift should get a chore ticket.

### Final Spec

```blink
// Removed: list_map(xs, f), map_keys(m), num.parse_int(text), str_from_code_point(n), ...
let ys = xs.map(fn(x) { x * 2 })
let total = xs.fold(0, fn(acc, x) { acc + x })
let n = text.parse_int()?               // Result: no silently lossy parse
let c = Char.from_code_point(n)?
let s = "{c}"
let quoted = json.stringify(JsonValue.Str(raw))

let adults = ages.filter(fn(k, v) { v >= 18 })
let merged = base.merge(overrides)       // shallow; overrides wins; base's key order first
```

- **Q1-A (6-0).** §3.2 keeps a permanent *Removed function forms* table. Each row names the replacement and says whether the result changes.
- **Q1-R (NO 4-2, DevOps and AI/ML dissent).** The `blink fix` behaviour is not spec text. The tooling chore must never auto-apply a row whose result changes.
- **Q2-B (6-0).** No std module exports a function form. The lossy `parse_int`/`parse_float` bodies go.
- **Q3-A (6-0).** `ListOps` gains eager `map filter fold any all find flat_map enumerate zip skip`. No `for_each`: use a `for` loop.
- **Q4-B, Q4-N (5-1 each, Minimalism dissent).** `MapOps` gains `filter map_values fold merge`. `merge` is shallow and the argument's value wins.
- **Q5-A (6-0).** `str_from_code_point` goes. Use `Char.from_code_point(n)?` and interpolation.
- **Q6-B (6-0 R2 after 4-2 R1 for A).** `json_escape_str` is not public. It merges with the private escaper in `std.json`. Derive reaches it through lowered IR.
- **R1 (6-0).** No silently lossy parse function exists in the standard library.
- **R2 (6-0).** The effect row of an eager adapter call is the row of `f`.
- **R3 (5-1, Minimalism dissent).** The effect of a lazy adapter closure occurs at the consuming call. v1 lazy closures are pure, so this rule fixes the reserved effect row (§3c).
