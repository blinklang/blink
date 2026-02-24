# Friction Log

AI + human friction encountered while building the Pact compiler. Captures pain points, ambiguities, and surprises for future spec revision.

Format: append new entries at the bottom.

Categories: `syntax` | `types` | `codegen` | `ergonomics` | `ambiguity` | `tooling` | `spec-gap`
Severity: `papercut` | `annoying` | `blocking`
Source: `ai` (Claude) | `human` | `both`

---

### 2026-02-07 — Sublist API is a silent corruption footgun
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing `merge_programs()` for multi-file imports
- **Description:** The sublist system (`new_sublist` / `sublist_push` / `finalize_sublist`) uses a shared `sl_items` array. If you create multiple sublists upfront and then interleave pushes to them, all sublists get the same `sl_start` and `finalize_sublist` computes wrong lengths. There's no error — you just get silently corrupted data that crashes later in `generate()` with an opaque "list index out of bounds: -1". Had to restructure to collect into Pact `List[Int]` temporaries first, then build each sublist sequentially (create → fill → finalize, one at a time). The API shape invites the wrong usage pattern. Consider: (a) making `new_sublist` set `sl_start` at finalize-time instead of creation-time, or (b) adding a runtime check that no other sublist is "open" when pushing.
- **Update 2026-02-08:** This bug resurfaced in the pattern parser — struct/tuple/enum/or-pattern parsing all called `parse_pattern()` inside open sublists, causing silent corruption (pact-203). Fixed all pattern sublist sites to use the collect-then-build pattern. The API footgun remains; all current call sites are now safe.

### 2026-02-07 — Module-level `let mut` redeclaration semantics are confusing
- **Category:** `ambiguity`
- **Severity:** `papercut` → **resolved**
- **Source:** `ai`
- **Context:** Understanding how parser and codegen share the `np_*` node pool arrays in the amalgamated compiler
- **Description:** The amalgamated `pactc.pact` has duplicate `let mut np_kind: List[Int] = []` declarations (one from parser section, one from codegen section). The codegen deduplicates these to a single C variable, and only the first initialization runs. This works but is confusing — nothing in the spec or the code makes it obvious that the second declaration is a no-op rather than creating a new binding. This is an artifact of the amalgamation process, but it exposed a spec gap: what *should* happen when a module-level `let` name is declared twice? Error? Shadow? Merge? The spec should clarify.
- **Resolution (2026-02-14):** Panel vote 5-0 unanimous on all 3 questions: duplicate module-level `let` = compile error (E1004), `pub let mut` forbidden (E1006), function-local shadowing allowed but module-level not. See §2.12.1, DECISIONS.md.

### 2026-02-07 — Import system defeats `pub` visibility by requiring everything be `pub`
- **Category:** `spec-gap`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Splitting pactc.pact into 6 multi-file modules using the import system
- **Description:** The import system only brings `pub`-marked items into the merged program. But when an imported `pub fn` references module-internal helpers (non-pub functions, constants), those helpers are missing from the merged C output — the codegen emits calls to undeclared symbols. The fix was making *everything* `pub` in every module, which defeats the purpose of `pub` entirely. Root cause: the import mechanism operates at the AST declaration level (filtering which top-level nodes to include), but function bodies contain unresolved references to their module's internal symbols. Either: (a) the import system needs to transitively include non-pub items that pub items depend on, (b) codegen needs to emit all items from a module when any item from it is imported, or (c) the compilation model should change so each module is compiled to C independently and linked, rather than merging ASTs.

### 2026-02-08 — Closure const-qualifier warnings flood every call site
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing HOF support (pact-222) and immutable captures (pact-218)
- **Description:** Closures are emitted as `const pact_closure*` variables (since the binding is immutable `let`), but calling through `fn_ptr` requires casting and passing `self` as the first argument — which expects `pact_closure*` (non-const). Every single closure call site generates a `-Wdiscarded-qualifiers` warning. Similarly, `pact_list_len`/`pact_list_get` in runtime.h don't accept `const pact_list*`, so any list stored as `const` triggers the same warning. The bootstrap output has dozens of these. Fix options: (a) make runtime.h functions accept `const` pointers where they don't mutate, (b) emit closures as non-const `pact_closure*`, (c) generate explicit casts at call sites to suppress warnings.

### 2026-02-09 — Calling an undefined function produces no error
- **Category:** `spec-gap`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing closure capture helpers; `capture_cast_expr` called `int_to_string()` which doesn't exist
- **Description:** The compiler has no notion of "defined functions" at compile time. If you call a function that was never declared, the compiler happily emits a C call to it — you only discover the mistake when `gcc` reports an implicit function declaration. This applies to all function calls, not just built-ins. A Pact program with `foo_bar_baz()` will compile to C without complaint. The spec assumes functions are checked, but there's no symbol table or name resolution pass. Fix: add a name resolution phase that checks all function calls against known declarations (top-level `fn`, imported names, built-ins) before codegen. This would catch typos, missing imports, and nonexistent functions at the Pact level instead of deferring to C.

### 2026-02-09 — Method call fallback silently generates invalid C identifiers
- **Category:** `spec-gap`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing Into trait; `x.into()` generated `x_into()` as a C function call
- **Description:** When `emit_method_call` encounters a method it doesn't recognize (not a built-in, not a known trait impl), it falls through to a generic handler that concatenates `{obj}_{method}({args})`. So `x.into()` becomes `x_into(x)`, `foo.whatever()` becomes `foo_whatever(foo)` — no error, no warning, just nonsense C code. The return type defaults to `CT_VOID`, so variables assigned from these calls get declared as `const void y`, which is also invalid C. The fallback should either (a) emit an error for unresolved methods, or (b) at minimum not silently produce garbage. This is the method-call equivalent of the undefined function problem above — the compiler trusts that all names resolve and defers validation to `gcc`.

### 2026-02-09 — Generic list element types not propagated through function returns
- **Category:** `types`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing mutable captures (pact-219) and effect system handles
- **Description:** When a function returns `List[Str]`, the codegen registers the return as `CT_LIST` but drops the element type parameter. So `let caps = analyze_captures(...)` followed by `caps.get(i)` generates `(int64_t)(intptr_t)pact_list_get(caps, i)` — treating strings as integers. The fix required adding `fn_ret_list_names`/`fn_ret_list_elem` parallel registries and propagating element types through call expressions and let bindings. This is a recurring pattern: the CT_* type system has no way to express parameterized types (`List[Str]`, `Option[Int]`, `Result[Int, Str]`). Each one needed its own ad-hoc parallel registry. A proper type representation (even just a struct with a CT code + inner types) would eliminate the entire class of bugs.

### 2026-02-09 — Result/Option return types silently compiled to `void`
- **Category:** `codegen`
- **Severity:** `blocking`
- **Source:** `ai`
- **Context:** Implementing `?` and `??` operators (pact-161)
- **Description:** `c_type_str()` has no case for `CT_RESULT` or `CT_OPTION`, defaulting to `"void"`. Functions declared as `fn foo() -> Result[Int, Str]` got C return type `void`, making `?` and `??` unusable. Additionally, the parser stored only `"Result"` as the return type string, discarding the type parameters `[Int, Str]`. Had to add `np_type_ann` storage on FnDef nodes and `resolve_ret_type_from_ann()` to reconstruct the full C type. Root cause is the same as the list element type issue: CT_* integers can't represent parameterized types, so every generic type needs special-case plumbing. Consider promoting to GAPS since this pattern will recur for every new generic type.

### 2026-02-10 — Closure const-qualifier warnings compound with every new feature
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Testing HOF, closure captures, and TryFrom after codegen module split (pact-257)
- **Description:** The const-qualifier warning issue (see 2026-02-08 entry) continues to compound. Every new feature that touches closures — HOF `apply`/`apply_twice`, immutable captures, mutable captures — adds another wave of `-Wdiscarded-qualifiers` warnings. The test_hof.c output alone has 16 warnings. The bootstrap output has dozens. This makes it hard to spot *real* warnings in the noise. The underlying issue is unchanged (closures emitted as `const pact_closure*` but called through non-const function pointers), but the volume is now bad enough that it's worth prioritizing a fix. Recommend option (b) from the original entry: emit closures as non-const `pact_closure*`, since closures are heap-allocated and the `const` adds no real safety.

### 2026-02-10 — `?` operator in non-Result functions silently generates invalid C
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Writing TryFrom + `?` operator tests (pact-233)
- **Description:** The `?` operator emits early-return code: `if (__res.tag == 1) return (Result){.tag=1, .err=__res.err}`. If the enclosing function doesn't return `Result` (e.g. `fn main() -> Void`), this generates a C statement that returns a struct from a void function — which only surfaces as a gcc error, not a Pact-level diagnostic. During test development, the test file had to be restructured multiple times to wrap all `?` usage inside `Result`-returning helper functions. The compiler should check that `?` is only used inside functions whose return type is `Result[T, E]` (or `Option[T]` for `??`) and emit a clear error otherwise. This is another instance of the "defer validation to gcc" pattern — the compiler trusts the code is well-formed and emits garbage when it isn't.

### 2026-02-13 — Formatter: all functions must be `pub` for import to work
- **Category:** `tooling`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing the formatter module (pact-305) with `import formatter` from compiler.pact
- **Description:** Same as the 2026-02-07 `pub` visibility entry. All internal helper functions in formatter.pact had to be made `pub` because the import system only brings across `pub` items. Non-pub helpers called by the pub `format()` function were "undefined" in the merged output. This is the exact same issue as before — the import system needs transitive dependency resolution.

### 2026-02-13 — Formatter: comment attachment lossy for file-level and inline comments
- **Category:** `spec-gap`
- **Severity:** `papercut`
- **Source:** `ai`
- **Context:** Implementing comment preservation in the formatter (pact-305)
- **Description:** The parser attaches pending comments to the next AST node via `attach_comments()`, but this has gaps: (1) file-level header comments before the first declaration sometimes end up attached to the wrong node, (2) inline comments within function bodies are not reliably attached to their associated statement (they get attached to the next statement parsed, which may not be the intended one), (3) comments between declarations (e.g. between two functions) can be consumed by `skip_newlines()` and attached to the wrong function. The formatter can only emit comments where the parser stored them. Proper comment preservation would require either (a) storing comment positions relative to source lines and using heuristic reattachment, or (b) a CST (concrete syntax tree) that preserves all whitespace and comments positionally.

### 2026-02-13 — @tags annotation values emitted as pointer addresses instead of strings
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Validating test framework end-to-end (pact-314), creating `test_tags.pact` with `@tags(unit)`, `@tags(slow)`, `@tags(unit, integration)`
- **Description:** The `@tags` annotation is parsed correctly (tag count per test is right), but the tag *values* in the generated C code are pointer addresses instead of string literals. Generated output: `static const char* pact_test_tagged_unit_test_tags[] = {"106281597399504"};` instead of the expected `{"unit"}`. The codegen at `codegen.pact:798` does `tag_arr.concat("\"{tags.get(tgi)}\"")` where `tags` is `List[Str]` from `test_tag_lists: List[List[Str]]`. The `tags.get(tgi)` call appears to return the internal pointer representation of the string rather than the string value when used inside string interpolation within `.concat()`. This means `--test-tags` filtering always returns 0 results since tag strings never match. Tests themselves compile and run fine; only the tag metadata is corrupted.

---

### 2026-02-14 — `match` is a keyword but no helpful error when used as variable name
- **Category:** `ergonomics`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing CLI add/remove commands (pact-365) — AI agent used `let mut match = 1` as variable
- **Description:** Using the keyword `match` as a variable name causes the compiler to crash with an opaque "list index out of bounds: 4457" error instead of a clear diagnostic. The parser doesn't emit a "expected identifier, got keyword 'match'" error. AI code generators (and humans) are especially likely to use `match` as a variable name since it's a common English word. The compiler should produce a targeted error like "error: 'match' is a keyword and cannot be used as an identifier".

### 2026-02-14 — `get_env` builtin missing, no obvious way to access env vars
- **Category:** `spec-gap`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing lockfile-based import resolution (pact-367) — needed HOME for git cache path
- **Description:** There's no `get_env` builtin for reading environment variables. The stdlib gitdeps module works around this by shelling out (`shell_exec("printf '%s' $HOME > /tmp/_pact_home")` + `read_file`). The codegen registers builtins like `get_arg`, `file_exists`, `path_join`, `shell_exec`, `read_file`, `write_file` — but `get_env` is absent despite `getenv` existing in the C runtime. Should be added as a builtin with `reg_fn("get_env", CT_STRING)` and a case in codegen_expr.

### 2026-02-14 — `\{` in strings trips up formatter round-trip
- **Category:** `tooling`
- **Severity:** `papercut`
- **Source:** `ai`
- **Context:** Formatting stdlib files containing `\{` escape sequences for literal braces
- **Description:** The formatter produces lexer warnings when processing files that contain `\{` escape sequences in strings. Doesn't cause test failures (formatter tests pass) but produces noisy output during CI. The formatter's lexer pass should handle `\{` the same as `\"` and `\\` — as a valid escape that produces a literal character.

### 2026-02-14 — `\}` escape not handled by lexer
- **Category:** `syntax`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Writing JSON object literals in strings like `"\{\"name\":\"Alice\"}"`
- **Description:** Lexer handles `\{` (line 830 of lexer.pact) to escape literal braces from string interpolation, but `\}` falls through to unknown-escape handler which outputs `\` and drops the `}`. This produces corrupt C strings. Workaround: `}` doesn't need escaping since the interpolation parser tracks brace depth and `}` in string mode is just a regular character. However, symmetry suggests `\}` should also work as an escape sequence producing a literal `}`.

### 2026-02-14 — `List[Float]` broken in codegen
- **Category:** `codegen`
- **Severity:** `blocking`
- **Source:** `ai`
- **Context:** JSON parser needed `List[Float]` for storing parsed float values
- **Description:** All lists use `void*` internally. `list.push(float_val)` emits `pact_list_push(list, (void*)float_val)` which fails — can't cast `double` to `void*`. Ints work via `(void*)(intptr_t)` cast, strings are already pointers, but floats need boxing (allocate a `double*` and store). The codegen's push handler (codegen_expr.pact ~line 1558) has special cases for INT and struct types but not FLOAT. Workaround: store floats as `List[Str]` and parse on retrieval.

### 2026-02-15 — Parser did not implement dot-continuation from spec §2.7
- **Category:** `syntax`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Formatter wraps long method chains (e.g. `.concat()`) across lines per spec §2.7, but parser didn't support dot-continuation
- **Description:** Spec §2.7 says "A statement continues when the next line starts with a dot: `.method()` chaining." The parser's `parse_postfix()` loop only checked for `.` on the current token without looking past newlines. Formatted code with wrapped `.concat()` chains would crash on re-parse because each `.concat(...)` line was treated as a separate (invalid) statement. Fixed by adding side-effect-free lookahead in `parse_postfix()`: peek past Newline/Comment tokens without consuming them, only call `skip_newlines()` if a Dot actually follows.

### 2026-02-22 — `{}` parsed as map literal but methods don't resolve on it
- **Category:** `ambiguity`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Writing `test_float_boxing.pact` with `let mut prices: Map[Str, Float] = {}`
- **Description:** The parser accepts `{}` and presumably creates some AST node for it, but variables initialized via `{}` don't resolve `.set()` or `.get()` — they hit the UnresolvedMethod fallback (E0505). The spec (§3.2.2) says "Literal syntax (List only)" and shows `Map.new()` as the construction method. So `{}` shouldn't parse as a map literal at all. Two options: (a) make the parser reject `{}` as an expression with a clear error ("use `Map()` to construct an empty map"), or (b) spec + implement `{}` as sugar for `Map.new()` with proper type propagation. The codebase universally uses `Map()` for construction, so option (a) aligns with current practice.

### 2026-02-20 — `handler` keyword as param name crashes parser
- **Category:** `syntax`
- **Severity:** `blocking`
- **Source:** `ai`
- **Context:** HTTP server module used `handler` as a function parameter name (e.g. `fn server_route(srv, method, pattern, handler)`)
- **Description:** `handler` is a keyword (`TokenKind.Handler`). When used as a parameter name, `expect_value(TokenKind.Ident)` detects the error and emits `KeywordAsIdentifier` but continues parsing. The real problem: when `handler` later appears in expression context (e.g. `route_handlers.push(handler)`), `parse_primary()` sees the `Handler` token and dispatches to `parse_handler_expr()`, which expects `handler EffectName { fn... }` syntax. It consumes tokens looking for `}`, eating the rest of the file, then crashes on out-of-bounds token access. Fixed by checking lookahead in `parse_primary()` — only dispatch to `parse_handler_expr()` if the next token is an Ident (the effect name). Otherwise emit `KeywordAsIdentifier` error and treat as a plain identifier. Also added EOF guard to `parse_block()` while loop.

### 2026-02-24 — Formatter drops @derive annotations from type definitions
- **Category:** `tooling`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Implementing `@derive(Serialize, Deserialize)` for JSON codegen (#44)
- **Description:** The formatter does not preserve `@derive(...)` annotations on type definitions. Formatted output loses the annotation entirely, so the formatted code no longer compiles (methods like `to_json()` become undefined). All test files using `@derive` had to be added to `fmt_skip` in the CI script. This is part of a broader issue where the formatter drops all annotations on type definitions.

### 2026-02-24 — `void _if_N` generated for second+ if-statement inside match arm
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Writing tests for `@derive(Deserialize)` — multiple if-statements inside `Ok(v) =>` arm
- **Description:** Inside a match arm, the first `if` statement works correctly, but subsequent `if` statements generate `void _if_N;` temporaries in C (to store the if-expression result), which is invalid C. Workaround: extract logic into a separate function so each function body has at most one if inside the match arm, or restructure to a single if/else chain. Root cause: the if-expression result type inference defaults to `CT_VOID` inside match arm scope.

### 2026-02-24 — `infer_enum_from_node` misidentifies Result-returning method calls as enum constructors
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** `let s = Shape.from_json(...)` where Shape is a data enum and from_json returns Result
- **Description:** `infer_enum_from_node` checks if a MethodCall's object is an enum type name, and if so returns that enum name. This causes `let` bindings of `Type.from_json(...)` (which returns `Result[Type, Str]`) to be registered as enum variables via `var_enums`, which then makes `match s` take the data-enum scrutinee path instead of the Result path. Fixed by clearing `enum_type` when `val_type == CT_RESULT` after expression evaluation.

### 2026-02-24 — Closure param name shadows outer `let mut` — codegen emits wrong variable
- **Category:** `codegen`
- **Severity:** `annoying`
- **Source:** `ai`
- **Context:** Defining closures with a parameter name that matches an outer `let mut` variable (e.g. outer `let mut req = ...` + closure `fn(req: Request) -> Request { ... }`)
- **Description:** When a closure parameter has the same name as an outer mutable variable, the codegen incorrectly treats references to the parameter inside the closure body as captures of the outer mutable cell (`*req_cell`). The generated C dereferences a `void*` pointer instead of using the closure's own parameter. Workaround: use a different parameter name in the closure to avoid shadowing (e.g. `fn(r: Request) -> Request { ... }`). The codegen's capture analysis should check whether a name resolves to a closure parameter before looking at outer scope mutable variables.

