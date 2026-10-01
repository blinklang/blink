[< All Decisions](../DECISIONS.md)

# Scalar → Str — Design Rationale

Resolves gap: "Int.to_str: typecheck answers Str but no spec section grants it". `src/typecheck.bl` accepted `to_str` and `to_string` on `Int` and `to_string` on `Float`, but no spec section granted them, and the §2 examples called `.to_str()` on `Int` values.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Each proposal is quoted verbatim.

##### Systems

> Spec gap t0kkq9 (`Int.to_str`), Systems seat, Phase A.
>
> **Checked in the code**
> - `src/typecheck.bl:5266` accepts `to_str` and `to_string` on `Int`. The `Float` row accepts only `to_string`.
> - `src/cg_call.bl:5213` (`cc_num_intrinsic`) sends `Int.to_string` and `Int.display` to the same callee, `std_num:int_to_str`. It has no `to_str` row.
> - `lib/std/num.bl:2` builds `int_to_str` with a StringBuilder: `sb.write("{n}")`, then `sb.to_str()`. That makes a builder, formats into it, then copies the bytes out. That is two heap allocations to format one integer.
>
> The machine sees the same thing whatever the method is called. The only cost question is whether each spelling reaches one direct, monomorphic call with no extra copy.
>
> ---
>
> ### Proposal A (preferred): one named method `to_str` on the scalar Display types, and remove `to_string`
>
> Give `Int`, `Float` and `Bool` a `to_str() -> Str` method, worded the same way the spec already words `Char`:
>
> ```blink
> let n = 42
> let s = n.to_str()                         // "42"
> let f = 2.5.to_str()                       // same text as "{f}"
> let ok = true.to_str()                     // "true"
> let widths = [1, 22, 333].map(fn(x) { x.to_str().len() })
> ```
>
> Rule: `x.to_str()` returns the same text as `x.display()` and `"{x}"`. It is a named method for discoverability, the same way `to_int`/`to_float` sit over `From`.
>
> - **Cost:** `to_str` and `display` go to one callee, so they cannot drift apart in output or speed. It is a static call with no vtable and no trait lookup. Because the spec defines `to_str` as "same text as `display`", the compiler may use a direct itoa into an exact-sized Str in place of today's builder round-trip. That saves one copy and one allocation per call. It is an implementation fix (the Str contract does not change), but tie it to this work.
> - **One spelling:** `to_string` is not in the spec. Keeping it next to `to_str` gives two names for one call. For an AI-first language that means a coin toss for every generated call site. `to_str` already appears in five places in the spec (StringBuilder, Bytes, Ptr[U8], Str-backed enums, Uuid), plus Char and the §2 examples. `to_string` appears in none.
> - **Return shape:** `Bytes.to_str` returns `Result` and `Ptr[U8].to_str` returns `Option`, but scalar formatting cannot fail. So a plain `Str` follows the same rule the spec already uses for `Option`: a carrier only where it is earned.
> - **Display stays sealed:** `to_str` is a method on four built-in types, not on the `Display` trait. A user type still uses `display()`. Generic code uses `T: Display` and `.display()`, so monomorphization is the same as today.
> - **Cross-language:** Rust has both `to_string()` (blanket over `Display`) and `format!`, and pays for it with one allocation path through the `fmt` machinery. Go splits it between `strconv.Itoa` (fast) and `fmt.Sprint` (reflective). Zig has only `std.fmt` into a caller buffer. A non-generic `to_str` with a direct itoa matches Go's fast path without a separate package.
>
> **Spec change:**
> - Add a §3c.3 "Scalar → Str" subsection with a table for Int, Float and Bool, parallel to "Char → Str". State the rule that output equals `display()`.
> - Add one line to the Display intrinsic seam (§3 ~3387) saying the four non-Str scalars also have `to_str`.
> - The §2 examples at 02_syntax.md:1362, 1376 and 1391 then become correct with no edits.
>
> **Migration, in three steps (add, migrate, remove):**
> 1. Add the `to_str` rows to `cc_num_intrinsic` for Int, Float and Bool, and add `to_str` to the Float and Bool typecheck rows.
> 2. Change the ~56 `to_string` call sites to `to_str`.
> 3. Remove the `to_string` rows. A call to `.to_string()` on a scalar then gets a diagnostic: "no method `to_string`; use `to_str()`".
>
> ### Proposal B: drop `to_str` and `to_string`, and keep only `display()` and interpolation
>
> ```blink
> let s = n.display()
> let t = "{n}"
> ```
>
> - **Cost:** the same machine code, and one fewer method name.
> - **Against:** `Char.to_str` stays, so `c.to_str()` works and `n.to_str()` does not. That is a rule about which scalar you hold, and an LLM will get it wrong. It also means rewriting three §2 examples and ~56 call sites to a longer spelling, for no runtime gain.
>
> ### Proposal C: keep both `to_str` and `to_string`
>
> This is rejected. It gives two spellings with nothing in the spec to choose between them. Its one benefit is source compatibility with code the spec never allowed.
>
> ---
>
> **Diagnostics (A):** removing the `to_string` rows needs a "did you mean `to_str`" note so the change does not leave a bare "no method".
>
> Headline: Proposal A. Add `to_str() -> Str` to Int, Float and Bool as named sugar that outputs the same text as `display()` and lowers to one direct call. Remove the unspecced `to_string` in three steps.

##### Web/Scripting

> Web/Scripting Phase A report on t0kkq9 (Int.to_str): I propose granting to_str() to every Display scalar and retiring to_string.
>
> **What decides this for me.** Three spellings already ship for "number to string": `display()` in the spec, `to_str()` in the spec's own §2 examples (02_syntax.md:1362, :1376, :1391) and the typecheck row, and `to_string()` in ~56 call sites plus our own compiler help text. E0312's explain text (src/diagnostics.bl:978) tells users `let s = i.to_string()  // any Display value to Str`, and E0512's example uses `Ok(n.to_string())`. If our compiler and spec each teach a different spelling, so will an LLM trained on them. Pick one named spelling and make every surface agree.
>
> **Proposal A (preferred): `to_str()` on every compiler-provided Display scalar. Drop `to_string`.**
>
> ```blink
> let n = 42
> let s = n.to_str()            // "42"
> let f = 2.5.to_str()          // "2.5"
> let b = true.to_str()         // "true"
> let c = 'A'.to_str()          // "A" (already in spec)
> let label = "port {n}"        // embedding: use interpolation
>
> let ports = [80, 443].map(fn(p) { p.to_str() })
> ```
>
> The rule in one sentence: on `Int`, `Float`, `Bool` and `Char`, `x.to_str()` returns exactly `x.display()`. This is the same as the Char text: "Both produce identical output; the choice is contextual, not semantic." No other type gets it, and it is not a Display trait method, so the Q1 closure on `display` stands. User types keep `display()` only.
>
> `to_string` becomes a rejected spelling with a fix-it: `x.to_string()` → "no method `to_string` on Int; use `x.to_str()` or `\"{x}\"`". Every Kotlin, Java and JS (`toString`) migrant hits that once and gets the answer in the error. They do not need Stack Overflow.
>
> Tradeoffs:
> - (+) A JS or Python dev guesses `n.to_str()` within 5 minutes: it is `toString`/`str(n)` with Blink's `Str` noun. It also matches `to_int`/`to_float`, so a reader who knows the family can guess it.
> - (+) The §2 examples stay as written. Typecheck stays, minus the `to_string` row. Codegen adds one arm, routed to `int_to_str`/`float_to_str` like `display`.
> - (+) Int→Str in decimal is a real conversion that round-trips through `parse_int`, so it is not just a render. That answers PLT's Q1 objection for this case.
> - (−) Two spellings on scalars (`to_str`, `display`). Char already has both, so this extends a rule we already have instead of adding a new one.
> - (−) We migrate 56 call sites and fix two diagnostics' explain text.
> - Open: should Float.to_str promise shortest round-trip output? I say yes, but that is the systems seat's call.
>
> **Spec text.** In 03c_protocols.md, add "Scalar → Str" next to "Char → Str": a table for Int, Float, Bool and Char with `.to_str()` and the same identical-output rule. In 03_types.md at the Display intrinsic seam (~3387), add one line: "These scalars also expose `to_str()`, equal to `display()`; see §3c." State that `to_string` is not a Blink method and name the diagnostic.
>
> **Proposal B (fallback): `display()` only. Drop both rows.** Rewrite §2 to `p.display()` and give `to_str` and `to_string` on scalars a fix-it pointing to `display()`. Each concept gets one spelling, but Char keeps `to_str` and Int does not. That is the kind of rule that causes "why does `'a'.to_str()` work but `5.to_str()` doesn't?" questions. Every migrant hits the error, and `n.display()` reads like printing to a screen.
>
> **Rejected: keep `to_string`.** It is Kotlin's and Rust's spelling but not Blink's: Blink names the type `Str`, and `to_X` targets the type name. Shipping it makes three spellings.
>
> **Cross-language notes.** Kotlin and Java ship one method (`toString()`) and it works everywhere, which is the familiarity argument. Rust ships both `to_string()` and `format!`, and "which one do I use?" is a long-running Stack Overflow question. The cause is that the two differ subtly. Ours do not, by rule. Python's `str(n)` versus f-strings has the same contextual split as our `to_str()` versus `"{n}"`.
>
> Headline: Proposal A. `to_str()` on Int, Float, Bool and Char equals `display()`. Drop `to_string` with a fix-it, and fix our own diagnostics that teach it.

##### PLT

> PLT Phase A report (t0kkq9, Int.to_str): I prefer Proposal A, which drops Int.to_str and Int.to_string and makes display() the only way to render a scalar as a Str.
>
> ## The typing question first
> In the spec, `to_X` has exactly one principled reading. §3c.3 says "named methods are sugar over the trait impls — one source of truth". So `x.to_T()` should mean `T.from(x)` (`-> T`) or `T.try_from(x)` (`-> Result[T, _]`). Char.to_str fits: it is `From[Char] for Str`. Bytes.to_str fits too, since `-> Result` is the TryFrom shape. Ptr[U8].to_str, StringBuilder.to_str, Str-backed enum to_str and Uuid.to_str do NOT fit. They are one name spread over unrelated types with different return types (`Str`, `Option[Str]`, `Result[Str, _]`). No single typing rule covers them, and no generic `T: ToStr` could exist. Display does have a uniform rule: `display : ∀T. T: Display ⇒ T -> Str`. Adding Int.to_str grows the unprincipled overloading. Adding it as `From[Int] for Str` is principled, but it has a large side effect. `Into` is auto-derived, so every `T: Into[Str]` bound would then accept Int. That turns rendering into conversion.
>
> ## Proposal A (preferred): display() is the only scalar-to-Str surface
> - Remove the `to_str`/`to_string` rows for Int (typecheck.bl:5266) and `to_string` for Float. Remove the `to_string` arms in cc_num_intrinsic, after migrating call sites (3-step dance).
> - §2 examples become:
> ```blink
> assert_eq(n.display().len(), 1, label)
> let s = p.display()
> let back = parse_port(p.display())?
> ```
> - Add a "did you mean" note to the unknown-method diagnostic: `Int has no method to_str; use n.display() or "{n}"`. This matters for AI-first: LLMs will emit to_string/to_str from Rust/Java/JS habits.
> - Spec text, §3.x Display intrinsic seam: "For the five built-in Display types, `x.display()` is the way to get a standalone `Str`. They have no `to_str`/`to_string`. `to_X` names a `From`/`TryFrom` conversion (§3c.3), and rendering is not a conversion." Add a sentence to §3c.3 that excludes Int→Str from the conversion table on purpose.
> - Tradeoff: the word `display` is less familiar. But the user already picked it 4-2 for exactly this job. A second spelling for the same function, with no stated law tying them together, is two sources of truth.
> - Cross-language: Rust has no `From<i32> for String`. You get `to_string` only through the blanket `impl<T: Display> ToString for T`, which is the same thing as our sealed `display`. Haskell keeps `show` separate from conversion classes. OCaml's `string_of_int` is a named function, not a conversion.
>
> ## Proposal B (if the panel wants Int.to_str): admit it only under a stated law
> Admit `From[T] for Str` (and so `.to_str()`) only for a T that has a canonical, locale-free encoding with a parse inverse:
> - Law 1 (coherence): `x.to_str() == x.display()`
> - Law 2 (round trip): `T.try_from(x.to_str()) == Ok(x)`. This mirrors the Str-backed enum law `T.from_str(x.to_str()) == Some(x)`.
> ```blink
> let s = 42.to_str()          // "42", sugar for Str.from(42)
> let n = Int.try_from(s)?     // Ok(42)
> ```
> - Int passes. Char passes. Float fails Law 2 (NaN != NaN, and -0.0 vs 0.0 are hard to tell apart in Str), so Float gets no to_str. Bool passes only if `TryFrom[Str] for Bool` is also specified.
> - `to_string` is dropped in both proposals. It appears nowhere in the spec, and no other `_string` name exists.
> - Tradeoff: matches what LLMs expect and the existing §2 examples. Cost: `Into[Str]` bounds widen, the Display output is frozen as a conversion contract, and Float/Int behave differently, which needs one more rule to explain.
>
> ## Effects
> No interaction with the effect system. Both surfaces are pure, and Display.fmt is pure over a local StringBuilder.
>
> Headline: Proposal A. Drop Int.to_str/to_string and Float.to_string, rewrite the §2 examples to `.display()`, and keep `to_X` strictly as From/TryFrom sugar. If the panel overrules this, only Proposal B is acceptable, never a bare alias with no stated law.

##### DevOps

> DevOps/Tooling Phase A: drop Int.to_str and Int.to_string, and add a machine-applicable rename diagnostic that points at `.display()`.
>
> ## What the tools see today
> - typecheck.bl:5266 accepts `to_str`/`to_string` on Int, but cg_call refuses `to_str` by name. So `5.to_str()` passes `blink check` and the LSP, then fails in the build. That is the worst place for an error: the editor is green and the build breaks.
> - In the corpus, `.to_str()` returns `Str` on Int/Char/StringBuilder/enum/Uuid, `Result[Str, ConversionError]` on Bytes, and `Option[Str]` on Ptr[U8]. Hover and completion cannot give one meaning for `.to_str()`. `display()` always returns `Str`, and E0523 covers it.
> - The near-miss suggester (tc_suggest_method, threshold len/3) gives no help for `to_str` on a type without it: "to_str"→"to_int" is distance 3. So without a dedicated arm the user sees `unresolved method` with no help. Precedents for a dedicated arm exist: `tc_list_rename_help`, the `display` arm in tc_unresolved_method_help, and §5 `fix.edits`.
>
> ## Proposal A (preferred): one spelling, a diagnostic that teaches it
> Remove `to_str`/`to_string` from the Int row and `to_string` from the Float row. Add a rename arm for scalar Display receivers (Int, Float, Bool, sized ints):
>
> ```
> error[UnresolvedMethod] (E0505): unresolved method `.to_string` on type Int
>   --> src/net_tcp.bl:41:22
>    |
> 41 |     let s = port.to_string()
>    |                  ^^^^^^^^^
>    = help: a number becomes a `Str` with `.display()`, or `"{port}"` inside a larger string
>    fix: replace `.to_string()` with `.display()`   [machine-applicable]
> ```
>
> The fix is safe to apply without review because the type and output are the same (§3.1 rule 1: the repair exists and keeps the construct). An LLM trained on Rust/Java/Python priors (`to_string`, `str()`, `toString`) gets one round-trip and then the correct form. The ~56 `.to_string()` sites and the three §2 examples migrate by applying the fix-edits, and nothing is left to judgment.
>
> ```blink
> fn main() {
>     let n = 5
>     let s = n.display()
>     io.println("port {n}")
>     assert_eq(s.len(), 1)
> }
> ```
>
> Spec change: §2 lines 1362/1376/1391 become `n.display()`/`p.display()`. §3 Display intrinsic seam adds one paragraph: "Scalars have no `to_str`/`to_string`; `display()` is the named form. `to_str` names a conversion (§3c), and its return shape depends on the source type." §5 diagnostics adds the rename help to the E0505 table.
>
> LSP: completion on `n.` lists `display` once and no near-duplicate rows. Formatter: no impact.
>
> Cross-language: Go has one path (`strconv.Itoa`/`fmt`) and vet points users to it. Rust lets `to_string` come from Display and has no second spelling. TS/JS `toString` vs `String(x)` vs template strings is the counterexample of three spellings.
>
> ## Proposal B (fallback): grant Int.to_str as sugar over Display
> If the panel favors the Char precedent (`c.to_str()`): add `to_str() -> Str` to Int/Float/Bool, defined as equal to `display()`, and wire the codegen arm to `std_num:int_to_str`. `to_string` must still go, with the same machine-applicable rename (`.to_string()` → `.to_str()`). Cost: two completion rows with the same meaning, and a "which one?" lint question that someone will file. Note that Char.to_str sits on `From[Char] for Str` (a conversion). Int has no `From[Int] for Str`, so B is formatting dressed as conversion and it blurs the §3c `to_X` family.
>
> ## Non-option
> Keeping the status quo (typecheck accepts, codegen refuses) is a spec violation in the diagnostic surface, and whichever proposal wins must remove it. Whatever the panel picks, check and build must agree. Also add a typecheck test that `5.to_string()` reports E0505 with the fix-edit.
>
> Headline: Proposal A. Remove Int.to_str/to_string and Float.to_string from typecheck, rewrite the §2 examples to `.display()`, and add a machine-applicable E0505 rename help (`.to_str()`/`.to_string()` → `.display()`) for scalar receivers.

##### AI/ML

> Two of the five Display intrinsics have no `to_str` today, and Float has no `to_str` at all. If one of them gets a `to_str`, the rest will look like they should too.
>
> **Proposal A (preferred): one rendering verb, `to_str` used only for conversions, and a guiding diagnostic**
>
> Remove `to_str` and `to_string` from the `Int` row (typecheck.bl:5266), and remove `to_string` from the `Float` row (:5272). An LLM then has two forms to choose from:
>
> ```blink
> fn label(port: Int) -> Str {
>     "port {port}"                 // embedded in a larger Str
> }
>
> fn ports(xs: List[Int]) -> List[Str] {
>     xs.map(fn(p) { p.display() }).collect()   // standalone Str value
> }
>
> test "port round-trips" {
>     prop_check(fn(p: Int) {
>         let back = parse_port(p.display())?
>         assert_eq(back, p)
>     })
> }
> ```
>
> Calling `to_str`, `to_string`, `toString` or `str` on `Int`, `Float` or `Bool` gives a dedicated error that names the fix:
>
> ```
> error[E0xxx]: Int has no method `to_string`
>   = help: use `n.display()` for a Str value, or "{n}" to embed it
> ```
>
> Tradeoffs from the AI/ML seat:
> - **Fewer choices to make.** With A, an LLM picks `display()` or interpolation, and the spec already says when to use each. With B below it must also pick `to_str` or `display`, and nothing in the meaning tells them apart.
> - **`to_str` keeps a type you can predict.** Today `to_str` on a `Bytes` returns `Result`, on a `Ptr[U8]` returns `Option`, and on `Char`, `StringBuilder` and Str-backed enums it returns `Str`. Every one of these is a From/TryFrom conversion, a decode or a copy. None of them renders a value. A rule an LLM can learn from the spec alone: "`to_X` converts and `display` renders." Putting `Int.to_str` on the same surface as `display` breaks that rule.
> - **Recovering from errors.** Training data will push LLMs to write `.to_string()` (Rust, Kotlin, JS) or `.to_str()`. One precise diagnostic fixes that in one turn. A second silent synonym fixes nothing, because the next file still mixes both spellings.
> - **Tokens.** `p.display()` and `p.to_str()` cost about the same, and `"{p}"` is cheaper than either. A loses nothing on cost.
> - **Why `Char` differs.** `Char → Str` is a lossless encoding with a real `From[Char] for Str` behind it. `Int → Str` has no `From` impl, so `to_str` would be sugar over nothing.
>
> Spec change:
> - In §3 (Display intrinsic seam, around 03_types.md:3387), add one paragraph: "To get a standalone `Str` from a scalar, call `.display()`. Scalars have no `to_str`/`to_string`. The `to_X` family is reserved for From/TryFrom conversions (§3c.3)."
> - Rewrite the three §2 examples (02_syntax.md:1362, 1376, 1391) to use `.display()`.
> - Add the diagnostic to the errors section, with the full list of spellings it catches.
> - Migrate the ~56 `.to_string()` call sites mechanically. Before deleting the rows, run the typecheck for a short period with the diagnostic as a warning, so we can count every site.
>
> Cross-language: Swift has one rendering path, `String(describing:)`. Rust ships both `ToString::to_string` and `format!`, and the overlap between them is a well-known source of confusion. Python's `str(x)` works because it is the only way.
>
> **Proposal B (fallback): make `to_str` official on all scalar Display intrinsics, as an alias of `display()`**
>
> ```blink
> let s = 5.to_str()        // == 5.display() == "{5}"
> let f = 2.5.to_str()      // Float gets it too, so there are no gaps
> ```
>
> This matches the `Char` precedent and the spec examples already written. It also needs a stated rule that `to_str` and `display` must never diverge, and that `to_string` gets the error from A. But it lets the decided `display` name back in through a side door. It adds a decision point that carries no meaning, and it weakens the "`to_X` = conversion" rule. If B is chosen, it must cover all five intrinsics (Int, Float, Bool, Str, Char). An alias on only some of them is the worst outcome for generation, because the LLM must learn exceptions one by one.
>
> **Rejected: keep the status quo, or add `to_string` alone.** `to_string` appears nowhere in the spec, so an LLM working from the spec cannot find it. And `Float` having `to_string` but not `to_str` is exactly the kind of gap that makes a model hallucinate.
>
> Headline: Proposal A. Remove `to_str` and `to_string` from `Int`, and `to_string` from `Float`. Rendering is `display()` or `"{x}"`, `to_X` stays reserved for From/TryFrom conversions, and a diagnostic points every misspelling to `.display()`.

##### Minimalism

> **Seat: Minimalism. Phase A proposals for t0kkq9 (`Int.to_str`)**
>
> **Starting point.** The spec already gives `Int` one way to make a `Str`, `display()`, plus interpolation `"{n}"`. Two compiler spellings have no spec grant: `to_str` (typecheck accepts it, codegen has never emitted it) and `to_string` (codegen emits it, 56 call sites, no section anywhere). The gap is two unspecced aliases of a method that already exists. Adding a section would add two more names to a closed, decided surface.
>
> ---
>
> **Proposal M1 (preferred): drop both, keep `display()` as the only named method**
>
> ```blink
> fn port_label(p: Int) -> Str {
>     p.display()
> }
>
> let n = 42
> let s = "{n}"
> let width = n.display().len()
> let names = ids.map(fn(i) { "user-{i}" })
> ```
>
> - **Typecheck.** Remove `to_str` and `to_string` from the `Int` row and `to_string` from the `Float` row (`src/typecheck.bl:5266`, `:5272`).
> - **Diagnostic.** Add a targeted fix-it for any builtin scalar: `` `Int` has no method `to_str`; use `n.display()` or `"{n}"` ``. Do the same for `to_string`. This covers the AI-first concern: a model that guesses the Rust or Java name gets the right answer from one error, and the spec does not grow.
> - **Migration.** Mechanical rewrite of about 56 `.to_string()` sites to `.display()`. Rewrite the §2 examples at `02_syntax.md:1362`, `:1376` and `:1391`. `lib/std/num.bl` `int_to_str` stays as the codegen target behind `display`.
> - **Spec text.** In §3 (Display intrinsic seam, ~3387), add one sentence: "Builtin scalars convert to `Str` only through `Display`: `x.display()` or interpolation. They have no `to_str` or `to_string` method."
>
> **Tradeoffs**
> - Each spelling multiplies the surface: LSP lists, docs, LLM training signal, and a "which one?" decision at every call site. Three names for one operation is how a language starts down the C++ path.
> - The Display panel already ruled that rendering is not a `to_X` conversion. Q1 chose `display` over `to_str`/`to_string` because `to_X` means a structural cast (decisions/display-trait-shape.md:66). `Int.to_str` would bring that rejected name back through a side door, on the very type the trait exists to render. Q1 is closed, so this deliberation should not reopen it by back-filling an alias.
> - **Cost:** sys and web lost Q1 for `to_str` and will see M1 as rubbing it in. Migrants reach for `.toString()`. The fix-it diagnostic is the answer to that, not a second name.
>
> **What about `Char.to_str`?** I accept it as decided, and it is not precedent for `Int`. It sits on `From[Char] for Str`, a real conversion: one codepoint becomes a one-codepoint string. `Int` → `Str` has no `From` impl, and adding `From[Int] for Str` would make `From` carry rendering. That is the conflation PLT warned against. Str-backed enum `to_str` returns a stored literal, which is also a conversion.
>
> **Cross-language.** Go has no `int.String()`; it uses `strconv.Itoa` and `fmt`. Rust ships both `to_string` and `Display::fmt` and is the textbook case of the confusion. Lua has `tostring` and nothing else.
>
> ---
>
> **Proposal M2 (fallback, only if the panel insists on a `to_X` name)**
>
> Spec `to_str` on `Int`, `Float` and `Bool` together, defined as exactly `display()`. Reject `to_string` everywhere and migrate its 56 sites to `.to_str()`.
>
> ```blink
> let s = 5.to_str()          // same as 5.display()
> let f = 2.5.to_str()
> ```
>
> - **Spec text.** In §3c.3, add: "`to_str()` on builtin scalars is sugar for `display()`. Output is identical." Add a codegen arm aliasing it to `display`.
> - **Cost:** two names for one operation, permanently, on the five most-used types. Partial coverage (`Int` only, `Float` with `to_string` only, as today) is the worst outcome. If M2 passes, it must be uniform across scalars.
>
> ---
>
> **Rejected outright: specifying `to_string`.** No section supports it, it matches no Blink naming pattern (`to_str` follows the `Str` type name), and it exists only because codegen grew it. Its call-site count reflects drift, not demand.
>
> **Vote intent.** M1. I will accept M2 only if it is uniform across scalars and kills `to_string`. I vote against any outcome that specifies both `to_str` and `to_string`.
>
> Headline: Drop `Int.to_str`/`Int.to_string` and `Float.to_string`, keep `display()` plus interpolation as the only scalar-to-`Str` surface, add a fix-it diagnostic, and rewrite the §2 examples and about 56 call sites. Fallback: uniform scalar `to_str` as sugar for `display()`, never `to_string`.

#### Phase A.5 — Deduped option-space

- **D** — `display()` only for scalars; remove `to_str`/`to_string` from the typecheck rows; fix-it to `.display()`. Preferred by plt, devops, aiml, min; fallback for sys, web.
- **T** — `to_str()` on scalar Display types as a named method whose output equals `display()`; drop `to_string`. Preferred by sys, web; fallback for aiml, min, devops.
- **L** — `From[T] for Str` only for types that meet stated round-trip laws. Proposed by plt as a fallback.

#### Phase B — Debate (round 1, verbatim)

All six panelists sent `STABLE — ready to vote` after round 1.

##### Systems

> Phase B round 1, Systems seat: I am changing my preference from T to D.
>
> **On cost alone, T and D are the same.** Both lower to one direct, monomorphic call to `std_num:int_to_str`, with no vtable and no trait lookup. Since my seat's own measure does not separate them, I should not hold out for T on cost grounds. My Phase A case for T rested on spelling: the three §2 examples and Char's `to_str`. That is a web argument, and web makes it better than I did.
>
> **What moved me:**
> - **PLT and AI/ML:** "`to_X` is sugar over `From`/`TryFrom`" is a typing rule the compiler can enforce. Char's `to_str` passes it because `From[Char] for Str` exists. Int's `to_str` would be a named method backed by no impl. That is a second dispatch path that both typecheck and `cc_num_intrinsic` must keep in step forever.
> - **DevOps:** today `blink check` and the LSP pass `5.to_str()` and the build then fails. Every alias row is one more chance for that split, and D has fewer rows.
> - **Minimalism:** fewer names means fewer typecheck rows and fewer codegen rows. From my seat that counts as a real benefit.
>
> **Against Option L (PLT B):** the `Into[Str]` bounds it widens monomorphize, so it adds no runtime cost. But it freezes `display` output as a conversion contract. It also splits Int and Float on a NaN technicality, which is a rule that exists only to explain an exception.
>
> **For AI/ML's B, if T wins anyway:** I agree it must cover all five intrinsics, not part of them.
>
> **Conditions that hold under any outcome:**
> 1. **The other scalars still have no `display` callee.** The comment at `src/cg_call.bl:5208` says Float, Bool, Str and Char `display` "type-check but nothing here answers them yet". Under D, `display()` is the only named form, so every one of those needs a working callee in the same change. Otherwise D repeats today's "editor passes, build fails" split on four more types.
> 2. **Faster `int_to_str`:** the StringBuilder round-trip in `int_to_str` (two allocations) should become a direct itoa into an exact-sized Str. This is an implementation fix whatever the name. The same applies to Float.
> 3. **Web's question about Float output:** yes, Float `display` output should be specified as the shortest form that round-trips (the Ryu approach), because otherwise output varies by platform. That is a separate spec task about the `Display` contract, not a reason to keep `to_str`, so it should be logged as friction.
> 4. **Removing `to_string`:** I agree with the 6/6 position. Use a machine-applicable fix-it that rewrites `.to_string()` and `.to_str()` on scalar receivers to `.display()` (DevOps' E0505 arm). Also fix the help text in `src/diagnostics.bl:978` (E0312, plus the E0512 example) that teaches `to_string`, as web pointed out.
>
> Position changed: T to D, with conditions 1 and 2 as part of the change.
>
> STABLE — ready to vote

##### Web/Scripting

> Web Phase B r1 (t0kkq9): I still prefer T, but I moved: D is now acceptable to me on three conditions, and I will not block it.
>
> **What moved me: devops.** My case for T was the migrant's first five minutes, meaning the Stack Overflow question "why doesn't `5.to_str()` work?". Devops's machine-applicable E0505 fix-it answers most of that. Someone who writes `.to_string()` gets the exact replacement in the error and in the LSP quick-fix, with no searching. An error you can fix on the spot is a speed bump, not a support thread.
>
> **What I still contest: the "`to_X` converts, `display` renders" rule (aiml, min, plt).** The spec already breaks it. `StringBuilder.to_str` copies a buffer, `Uuid.to_str` renders a canonical form, and `Ptr[U8].to_str` returns `Option`. PLT says so: "no single typing rule covers them." So D does not restore a clean rule. It draws the line at Char vs Int, a distinction a JS dev only sees after reading §3c.3. aiml says partial coverage is "the worst outcome for generation", and D has partial coverage too: `'a'.to_str()` compiles and `5.to_str()` does not. The From story explains it, but only to someone who has read §3c.
>
> **PLT's Option L: I reject it.** `42.to_str()` working while `2.5.to_str()` fails a round-trip law is the exact gotcha my seat exists to prevent. It also widens `Into[Str]` bounds, which nobody asked for.
>
> **aiml on including Str under T:** `s.to_str()` as an identity is harmless, but no one needs it. Int, Float and Bool are enough. Char already has it.
>
> **sys on itoa:** I agree. It is an implementation fix whichever option wins.
>
> **My conditions for D:**
> 1. The fix-it covers `to_str`, `to_string` and `toString` on every scalar receiver, is machine-applicable, and the LSP surfaces it.
> 2. The help text in src/diagnostics.bl that teaches `to_string` gets fixed: the E0312 explain at :978 and the E0512 example. Otherwise our compiler contradicts our spec.
> 3. The §3 seam states the rule in one line, with the Char contrast and its reason: "`'a'.to_str()` exists because `From[Char] for Str`; numbers render with `display()`." The spec has to answer the FAQ before anyone asks it.
>
> Ranking: T > D (with the conditions) >> L > status quo.
>
> STABLE — ready to vote

##### PLT

> PLT Phase B round 1 (t0kkq9): I still hold Option D. I rank L above T as the fallback.
>
> **web: "Int→Str round-trips through parse_int, so it is a real conversion."** That holds for Int. But it is my Option L argument, not an argument for T. Under T, Float and Bool also get `to_str`, with no round-trip law and no `From` behind them. NaN breaks the round trip for Float. Bool has no specified `TryFrom[Str]`. If round-tripping is what makes a scalar `to_str` legitimate, then state the law and give `to_str` only to types that keep it. T gives it to all of them on familiarity alone.
>
> **sys and web: "Char has to_str and Int does not" is a hard rule for an LLM.** Under D the rule is one sentence: a `to_X` method exists exactly when a `From`/`TryFrom` impl to X exists. Its return shape follows from that impl: `Str` for From, `Result` for TryFrom. That predicts Char, Bytes, Str-backed enums and the numeric family. T replaces it with "to_X is a conversion, except on four scalars, where it is rendering". That is the harder exception to learn. aiml's demand that T cover all five intrinsics shows the cost: `Str.to_str()` would be an identity method with no reason to exist.
>
> **sys: "one callee, so they cannot drift."** That is a promise about one compiler. The spec has to make it a law, because no trait ties `to_str` to `Display.fmt`. Under T, `x.to_str() == x.display()` is a second definition that must be kept true by hand. Under D nothing needs keeping true. The direct-itoa saving works the same under D, because the intrinsic seam already lets the compiler supply the scalar `fmt`/`display` body. So sys's cost argument does not favor either name.
>
> **devops** found a strong practical fact: today `5.to_str()` passes check and then fails the build. D fixes this by deleting the row. T fixes it by adding a codegen arm. Both close the gap, but D leaves nothing to keep in sync later. I adopt devops's machine-applicable E0505 fix-edit and aiml's warn-first migration as part of D.
>
> **Fallback ranking:** D, then L, then T. If T wins, it must state `x.to_str() == x.display()` as a spec law and must kill `to_string`. On scope I side with min over aiml: Int, Float and Bool only, because adding Str is absurd.
>
> Position unchanged.
>
> STABLE — ready to vote

##### DevOps

> DevOps/Tooling Phase B r1: my position has not changed. I still prefer Option D (display() only), and T is my fallback.
>
> **web**: Good catch on our own help text. The E0312 explain text (diagnostics.bl:978) and the E0512 example (`Ok(n.to_string())`) teach a spelling that no option keeps. Fixing them must be part of the implementation whatever wins. A compiler that teaches a spelling it then rejects is the worst diagnostic failure we can have. Your "why does `'a'.to_str()` work but `5.to_str()` doesn't?" question is real. Under D the compiler answers it the first time someone hits it: the help line names `.display()`/`"{n}"` and comes with a fix-edit. Under T the same question moves to "to_str or display?", and no error message ever answers that, because both compile.
>
> **sys**: The direct itoa does not depend on the name, so do it under either option. Your argument "Char has it, so an LLM will get it wrong" assumes the LLM gets no feedback. Blink gives structured `fix.edits` (§5). One wrong guess then costs one round-trip, and it becomes fixed, correct source. A synonym costs every reader of every file forever.
>
> **plt (L)**: Reject L. Under L, completion on `n.` shows `to_str` but completion on `f.` (Float) does not. A user then asks why, and the answer is a round-trip law that no diagnostic can explain in one line. L also widens `Into[Str]`, so a bound error can now read "Float does not implement Into[Str]" when the user only wanted to print it. That is a bad error message.
>
> **aiml (warning period)**: OK, but only for `to_string`, since that is the spelling codegen emits today and it has 56 sites. `Int.to_str` has never emitted in a released compiler, so it can become an error now. I would rather not have a warning period at all: the fix-edit is mechanical, so apply it repo-wide in step 2 of the three-step change, and turn the rows into the error in step 3.
>
> **aiml/min (scope if T wins)**: I agree it must be uniform. Every Display intrinsic gets it, or none does. An alias on only some types is a gap in completion.
>
> **Requirement under any option**: `blink check` and the build must agree. Add a typecheck test for each rejected spelling (`5.to_string()`, `2.5.to_str()` under D) that asserts the code and the fix-edit.
>
> STABLE — ready to vote

##### AI/ML

> I still prefer **Option D**. Two smaller points have changed, and I am ready to vote.
>
> **To sys and web on "`'a'.to_str()` works but `5.to_str()` doesn't".** This is the strongest case for T, and I agree it costs an LLM something. But under D there is a rule a model can learn from the spec alone: a type has `x.to_str()` only if it has a From/TryFrom impl into `Str`. That rule is what predicts the return shape. Under T, `.to_str()` returns `Str` on scalars, `Result` on `Bytes` and `Option` on `Ptr[U8]`, and nothing in the spec says why. A model that cannot work out the rule has to memorise the table row by row. Devops made the same point from the LSP side: hover cannot give `.to_str()` one meaning. D also leaves a model only one way to fail, the `to_str`/`to_string` guess on a scalar. The fix-it catches that in one turn.
>
> **To web on E0312/E0512.** This is the most useful new fact in the round. Our own diagnostics teach `to_string`, so a model that reads compiler output learns the wrong spelling no matter which option wins. Fixing that text should be a required part of D or T, not something left for later.
>
> **To plt on Option L.** I reject L for generation. Int gets `to_str`, Float does not, and Bool depends on a TryFrom that nobody has specified yet. That is three types, three answers, and a law the model cannot see at the call site. It is the uneven coverage that min and I both called the worst result.
>
> **To devops.** Your machine-applicable `.to_string()` → `.display()` fix-edit is better than my warning period. It migrates the ~56 sites with no judgment calls and lets us count them by applying it. I drop the warning period. I also support your check/build agreement test.
>
> **To sys on itoa.** This is a good change whatever the name, since `display()` takes the same path. It should not decide the vote.
>
> **Change to my fallback B (= T).** I asked for all five intrinsics. On reflection, `Str.to_str` is an identity call that only adds noise, and `Char` already has the method. I now accept T's scope as Int, Float and Bool, the same as sys, web, min and devops. If T wins, it must also:
> - remove `to_string` with a fix-it, and
> - carry web's Float round-trip promise, so the spec states what `2.5.to_str()` returns.
>
> Position: still D. My fallback T now covers Int, Float and Bool. Every spelling also needs devops' fix-edit and web's correction to the E0312/E0512 help text.
>
> STABLE — ready to vote

##### Minimalism

> **Seat: Minimalism. Phase B round 1. My position has not changed: Option D.**
>
> **To sys and web (the "`'a'.to_str()` works, `5.to_str()` doesn't" argument).** That is the strongest case for T, and it rests on the wrong rule. The rule is not "which scalar you hold". The rule is "`to_X` is sugar over `From`/`TryFrom`" (§3c.3).
> - `Char` has `From[Char] for Str`, so it has `to_str`.
> - `Int` has no such impl, so it does not.
>
> The spec can state that in one sentence and the diagnostic can say it once. T replaces it with "scalars get `to_str` as an alias of `display` that is backed by no trait". That is a new rule, not an extension of the `Char` rule. devops and aiml make the same point.
>
> **To web on round-trip.** You are right that `Int` → `Str` round-trips through `parse_int`, but that argues for PLT's Option L, not T. I oppose L as well:
> - `Into` is auto-derived, so every `Into[Str]` bound would widen to accept `Int`.
> - It fixes `display` output as a conversion contract.
> - It splits `Int` from `Float`, which then needs one more rule to explain.
>
> That is three combinatorial costs to save typing four characters.
>
> **To sys on itoa.** Yes. Do it under any outcome. It does not depend on the method name, so file it as its own chore.
>
> **To web on E0312/E0512.** Agreed. The compiler must not teach `to_string`. Under D, both explain texts change to `.display()`. This belongs in D's migration list.
>
> **To aiml on a warning period.** Not needed. All ~56 sites are in this repo, and `rg` counts them today. The fix-edit can be applied by machine, and the self-hosting add→migrate→remove sequence already gives an ordered rollout. A separate warning phase is process we do not need (YAGNI).
>
> **To web on `Float.to_str` shortest round-trip.** Out of scope. It decides Display output for `Float`, not this name. Open a separate ticket if anyone wants it.
>
> **Scope, if T wins anyway.** Accept T only if it covers `Int`, `Float` and `Bool` together and removes `to_string`. I disagree with aiml's all-five variant: `Str.to_str()` would return its own input, and no one should write it. `Char` already has `to_str` through `From`. Partial coverage, as today, is the worst result.
>
> **Points of agreement everyone shares:**
> - `to_string` gets no spec grant.
> - `blink check` and the build must agree.
> - devops's machine-applicable E0505 fix-edit is the delivery method for whichever option wins.
>
> STABLE — ready to vote

#### Phase C — Final vote

- **Q1: Scalar → Str surface** — **D, 5-1** (Web/Scripting dissent for T)
- **Q2: Migration of the `.to_string()` call sites** — **N (no warning period), 5-1** (Web/Scripting dissent for W)

Ballots are quoted verbatim.

##### Systems

> Sys ballot for t0kkq9 (Int.to_str): Q1 = D, Q2 = N.
>
> Q1 — Vote: D
> Reasoning: T, D and L all compile to the same direct monomorphic call to int_to_str, so runtime cost does not decide this. The difference is how many dispatch rows typecheck and cc_num_intrinsic must keep in agreement. D has the fewest, and "to_X exists only where a From/TryFrom impl exists" is a rule the compiler can check, not a list of exceptions. L freezes display output as a conversion contract and splits Int from Float because of NaN. T adds rows that do nothing but duplicate display.
> Concern: today, display on Float, Bool, Str and Char type-checks but has no codegen callee (src/cg_call.bl:5208). If D lands without those callees, the "editor passes, build fails" split moves from to_str onto display(), the one form we told everyone to use.
>
> Q2 — Vote: N
> Reasoning: to_string was never in the spec, and the fix-edit is machine-applicable with the same type and the same output, so a warning period buys nothing a single repo-wide rewrite does not. A warning release means one more release where both spellings have live codegen rows. That is the dual-path state this decision exists to end. The add, migrate, remove steps already protect the self-host bootstrap.
> Concern: external user code that called .to_string() on a released compiler breaks on upgrade. The error must print the machine-applicable fix (and blink fix should apply it) so the break costs one command.

##### Web/Scripting *(dissent on Q1 and Q2)*

> Web ballot, Phase C (t0kkq9): Q1 = T, Q2 = W.
>
> **Q1 — Vote: T**
> Reasoning: The 90% case is a migrant who writes `n.to_str()` right after writing `'a'.to_str()`. Our spec already writes it that way three times in §2. T makes that just work and pins it to one stated law (`x.to_str() == x.display()`), so the two spellings cannot drift. D's "`to_X` means a From impl" rule is clean on paper. But `StringBuilder`, `Uuid` and `Ptr[U8]` already break it, so a newcomer sees an arbitrary Char/Int split. They do not see a principle.
> Concern: If D wins, the fix-it is the whole user experience. If it is not machine-applicable in the LSP, or if E0312/E0512 still teach `to_string`, every new user hits a dead-end "unresolved method" and asks why `'a'.to_str()` works but `5.to_str()` does not.
>
> **Q2 — Vote: W**
> Reasoning: Released compilers have emitted `Int.to_string` and `Float.to_string`, so code outside this repo uses them. Users did nothing wrong by copying our own diagnostics' advice. A one-release warning that carries the fix-edit costs us almost nothing, and it turns a surprise build break into one apply-all click. Inside this repo, apply the edits in step 2 anyway. The warning period is for users, not for us.
> Concern: The warning period could stretch past one release. Give it a fixed release number in the spec or changelog when it lands.

##### PLT

> PLT Phase C ballot (t0kkq9): Q1 = D, Q2 = N.
>
> **Q1 — Vote: D**
> Reasoning: D keeps one typing rule for `to_X`: the method exists exactly when a `From`/`TryFrom` impl to X exists, and its return shape follows from that impl. So the rule predicts every `to_str` already in the spec. `display : ∀T. T: Display ⇒ T -> Str` stays the only rendering surface, and generic code can use it. T adds a by-hand law, `to_str == display`, with no trait behind it. L is principled but widens every `Into[Str]` bound to accept Int, which turns rendering into conversion.
> Concern: The §3 text must state the `to_X` ⇔ `From`/`TryFrom` rule as normative, not as a note. If it does not, the next scalar surface request reopens this with "Char has it", and the line between conversion and rendering wears away one case at a time.
>
> **Q2 — Vote: N**
> Reasoning: No section grants `to_string`. A warning period would keep, for a whole release, a typecheck rule that no section allows, so `blink check` and the spec would disagree. The fix-edit is safe to apply without review, because the type and output are the same. The add→migrate→remove sequence already makes the change safe inside the repo. A typing rule that "warns but accepts" for an unspecified surface is a second, informal type system.
> Concern: Code outside this repo written against a released compiler that emitted `to_string` will get a hard error with no notice. The release notes must name the fix-edit command so those users can apply it in one step.

##### DevOps

> DevOps/Tooling Phase C ballot: Q1 = D, Q2 = N.
>
> **Q1 — Vote: D**
> Reasoning: Under D, every wrong guess (`to_str`, `to_string`) fails with an error that carries a machine-applicable fix-edit to `.display()`. So the diagnostics teach one correct spelling, and both `blink check` and the build agree on it. Under T, the question "to_str or display?" has no error message to answer it, because both compile. LSP completion and hover would also show two entries that mean the same thing. Under L, completion has a gap between Int and Float that only a round-trip law explains, and it adds `Into[Str]` bound errors that confuse users.
> Concern: The near-miss suggester (threshold len/3) gives no help for `to_str` on a scalar. If the dedicated rename arm is not built, users and LLMs get a bare "unresolved method" with no help. That would make D worse than the status quo. The rename arm and its typecheck test, which asserts the fix-edit, must land in the same change that removes the rows.
>
> **Q2 — Vote: N**
> Reasoning: The rewrite is mechanical and safe: the type and the output are identical. So the add→migrate→remove sequence applies it repo-wide in step 2, and a warning period would only keep a non-spec spelling in the compiler for a release. `Int.to_str` has never emitted in any released compiler, so no user code depends on it. The external users of `to_string` are few, and the error's fix-edit fixes their code in one pass.
> Concern: Step 2 can miss sites that typecheck does not reach in the repo gates, such as stdlib modules no test imports, and those then break at step 3. Before removing the rows, grep `\.to_string\(\)` across lib/, src/ and tests/ and confirm it finds zero sites.

##### AI/ML

> AI/ML Phase C ballot (t0kkq9): Q1 = D, Q2 = N.
>
> Q1 — Vote: D
> Reasoning: D gives an LLM one rule it can learn from the spec alone. `to_X` exists only when a From/TryFrom impl into X exists, so the name also tells you the return shape (Char → Str, Bytes → Result, Ptr[U8] → Option). T makes `.to_str()` mean either a render or a conversion with nothing to tell them apart, so a model has to memorise which type gets which shape. L splits Int, Float and Bool three ways, and you cannot see the law at the call site. Under D a model can make only one mistake, guessing to_str or to_string on a scalar, and the machine-applicable fix-it corrects that in one turn at no extra token cost ("{x}" is the cheapest form anyway).
> Concern: if the fix-it is missing or vague when D lands (a bare "unresolved method" with no help, which is what happens today since to_str→to_int is out of near-miss range), every LLM's first guess fails with no answer. So the diagnostic and its test must ship in the same step that removes the rows.
>
> Q2 — Vote: N
> Reasoning: no section ever specced `to_string`, and the fix-edit is mechanical and keeps the same type and output, so a warning period buys nothing that applying the edit repo-wide does not already give. Every release in which `.to_string()` still compiles adds more code with the wrong spelling to repos that become training data. That is the exact signal this ruling exists to remove. Making it a hard error with a machine-applicable fix gives a model the correction in one turn.
> Concern: users outside this repo may have released code with `.to_string()` (codegen emitted it). Release notes must name the fix-edit command so they can migrate in one step and not one error at a time.

##### Minimalism

> Min (Minimalism) Phase C ballot for t0kkq9: Q1 = D, Q2 = N.
>
> Q1 — Vote: D
> Reasoning: D removes two unspecced names. It adds nothing, and the rule fits in one sentence: "to_X exists exactly when From/TryFrom to X exists". Char.to_str follows from that rule instead of being an exception to it. T adds a second permanent name for one operation on the five most-used types, with no trait behind it. L widens every Into[Str] bound and turns Display output into a conversion contract. Both cost more conceptual surface than they save.
> Concern: If the fix-it diagnostic is weak or missing (no dedicated arm for scalar receivers, so a bare "unresolved method"), LLM and migrant friction lands on users, and sys/web will cite that as grounds to reopen. The E0505 rename arm and its typecheck test must ship in the same change as the row removal.
>
> Q2 — Vote: N
> Reasoning: All ~56 sites are in this repo, rg finds them, and the fix-edit is machine-applicable. The self-hosting add→migrate→remove sequence already orders the rollout. A warning release protects external users we do not have for a surface no released compiler ever emitted. That is process we do not need (YAGNI).
> Concern: Step 2 may miss sites the rg count does not see, such as doc examples in sections/, diagnostics help text, `blink llms` content and lib/pkg. Before step 3, sweep with the typecheck itself (step-3 rows removed in a scratch build), not with rg alone.

#### Phase D

Not triggered: both questions passed 5-1, and the user approved the tally.
### Final Spec

```blink
let n = 42
let s = n.display()                        // "42"
let t = "port {n}"                         // interpolation uses Display
let ports = [80, 443].map(fn(p) { p.display() })
let c = 'a'.to_str()                       // From[Char] for Str: still valid

// 5.to_str()     -> error[E0505]: unresolved method .to_str on type Int
// 5.to_string()  -> error[E0505], fix: replace .to_string() with .display()
```

- `display()` and interpolation are the only ways to turn `Int`, `Float` or `Bool` into a `Str` (§3.6 *Display Format Protocol*).
- On the scalar types, a `to_` method is sugar over a `From` or `TryFrom` impl: `.to_X()` for `From`, `.to_X_checked()` for `TryFrom` (§3c.3). `Char.to_str` stays, because `From[Char] for Str` exists.
- `to_str`/`to_string`/`toString` on `Int`, `Float` or `Bool` is E0505 `UnresolvedMethod`, with a machine-applicable fix that rewrites the call to `.display()`.
- Migration has no warning period. Add the fix → apply it repo-wide → remove the typecheck rows (add → migrate → remove).
- The §2 examples now use `.display()`.
