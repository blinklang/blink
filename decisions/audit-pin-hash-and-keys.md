[< All Decisions](../DECISIONS.md)

# Audit pin hash and keys — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) answered four questions about `audits.toml` pins: what the `ast1` hash covers (Q1); whether the hash sees the imports an item uses (N); how a pin key is spelled, in a module and in a file with no module name (Q2); and what `blink audit pin` scans and refuses. Quotes are the panelists' own words. A mark `[...]` shows text left out: a ticket id, a source line number, or a part that does not bear on the question.

#### Phase A — Independent proposals

All six proposals took a fail-closed rule: when a choice is open, a pin that goes stale too often is better than a pin that stays fresh over changed code.

**Systems:**

> Rule I used everywhere: when unsure, fail closed. A spurious re-pin costs one command. A missed one leaves a claim false with no signal.

> Hash a canonical serialization of the PARSED tree, with names as written, before the checker renames nodes. Never hash internal node layout. "ast1" is the version tag of that serialization. A compiler change that alters the serialization must bump it to ast2, and an ast1 pin then reads as stale (fail closed), never as a silent match.

**PLT:**

> a pin can fail two ways. Fail-closed: the pin goes stale when the claim still holds. That costs one visible re-pin. Fail-open: the pin stays valid when the claim went false. That is unsound. Every choice below takes fail-closed when it must pick one.

> (b) is an allow-list, and it fails open. The day the language adds an annotation that changes binding or checking (a calling convention, a link name, a new @verify mode), every existing pin silently ignores it until someone grows the list. [...] With (a), a new annotation is covered from day one.

> Change `import a.{check}` to `import b.{check}` in the file, and `check(x)` inside the audited fn now calls other code with zero change to the fn's text. That is fail-open.

**Web/scripting:**

> Why a deny-list, not an allow-list (b): a new annotation lands in the hash by default. Fail-safe; nobody must remember to update a list when a binding-relevant annotation ships.

**DevOps/tooling:**

> Required side rule: the hash sorts annotations into a fixed order before hashing. `blink fmt` reorders annotations (it moves `@perf` after `@where`), and the spec promises that fmt never makes a pin stale.

**AI/ML:**

> an agent never derives a pin key by hand. It copies the key from a compiler note (the stale-pin note already prints `blink audit pin RPT-002 report.fetch_table`). So the key must be (1) printed verbatim in every audit note and in `blink audit` output, (2) safe to paste into a shell, (3) safe as a TOML key, and (4) only as a fallback, derivable from source by one rule.

#### Phase B — Debate highlights

The debate narrowed the options. Three facts from the spec ended two arguments. The annotation table in §11.1 marks `@trusted` as not repeating, so an item carries at most one record and "put K in the hash" and "put the `@trusted` tag in the hash" give the same pins today. The canonical annotation order of §11.1 already exists, so one table can serve `blink fmt` and the hash. PLT then moved from resolved names to a syntactic rule for imports:

**PLT:**

> the hash also covers each `import` declaration of the file, as written, that binds a free name or a qualifier used in the fn. Swap `import a.{check}` for `import b.{check}` and the pin goes stale. Add an unrelated import and nothing changes. It works on the PARSED tree, before the checker renames nodes, which matches sys's constraint. What stays outside the pin (and goes in the one "not covered" paragraph, with sys's ffi struct layout flag and alias right-hand sides): a same-name definition in another @module-merged file, and method dispatch by type.

> Q2-test: `report.test "..."`, with the DECODED name and one fixed escape set (F1 compares decoded values, so the key must too).

> Q2-dup: agree with devops. Refuse, exit 1, list both sites, never pick one.

> I support the sub-table writer. One line per pin means the diff shows exactly which pin moved beside an unchanged claim, which is the review-visibility goal in the spec. My preference is ALWAYS `[K.pins]`: one rule, and the diff stays stable when a record grows from 1 pin to 2.

> Q4a: I yield to Q4a-1 (exit 1, write nothing, help: delete the record if it is no longer needed). With Q4b's "set to exactly the current carriers", exit 0 would silently drop every pin of the record. Refusing is the better guard.

> Skipping build/ and dot dirs in the bulk scan is sound IF Q4b-kept holds (no unscanned pin is dropped) AND the explicit fn form can pin a fixture (the repair exists).

#### Phase C — Final vote

**Q1 — what the hash covers.** Q1-K: the prefix, K, then the parse tree of the item with every annotation except the item's own `@trusted(audit: ...)` tag. Q1-A: the same, with the `@trusted` tag in the tree and no K. Result: **Q1-K 5-1** (Systems, PLT, DevOps, AI/ML, minimalism for Q1-K; Web/scripting for Q1-A).

**Systems:**

> The default is fail-closed. Every annotation that can change what binds, runs or is checked is in the hash, and that includes `@allow` and `@perf`, both of which can change the emitted code or what fires in the body. A stale pin after a harmless `@allow` edit costs one re-pin. A fresh pin over a changed binding costs a false claim.

> Concern: people may come to read "stale" as noise after metadata edits and re-pin without reading the claim again. The printed claim and the one-line diff from [the stale-note rule] must carry that weight.

**PLT:**

> K in the hash makes the property I care about hold by construction, not by tool policy. A pin under K matches only a fn that carried K when it was pinned, and a pin copied from K1 into K2 never matches.

> Concern: people may come to read pins that go stale over an @allow edit as noise and re-pin by reflex without reading the claim. Keep the stale note naming what changed short, so the re-pin stays a read, not a reflex.

**AI/ML:**

> Salting K blocks the copy-paste failure an agent is most likely to make, moving a hash from one record into another so that a claim nobody re-read starts to suppress.

**Minimalism:**

> one rule with one principled exclusion: the @trusted tag is the key, not content, and K goes into the hash input. No list has to be kept up to date, so a new annotation is in the hash by default (fail-closed).

**Web/scripting (dissent):**

> The ballot lists Q1-CK under my name, but that is my round-2 position. In [round 2] I moved: [the annotation table] makes "@trusted in the hash" the same rule as the K salt, and plt convinced me that @allow belongs in [...]. That leaves my list at doc comments plus a few metadata annotations, and doc comments are out under every option, so Q1-A is the closest option on this ballot.

> Concern: [...] The note text must say which annotation changed, so a re-pin stays a conscious act.

**DevOps/tooling:**

> Concern: Teams that turn @allow on and off often will see re-pins that look like noise, and they may learn to rubber-stamp every pin diff.

**Q2-file — key of an item in a file with no module name.** F-e: the package-relative path as a Blink string literal, then `.item` (`"tests/db_test.bl".raw_open`). F-a: the path, `::`, then the item (`tests/db_test.bl::make_fixture`). Result in Phase C: F-e 4 (Systems, PLT, AI/ML, minimalism), F-a 2 (DevOps, Web/scripting). The panel took the question to a second round (Phase D).

**Agreed block (6-0).** The vote also settled twelve points with no dissent:

1. Annotations are hashed in the §11.1 row order, source order kept among annotations of one name; others follow, sorted by name. `blink fmt` never stales a pin; a change of the order bumps to `ast2`.
2. Comments, doc comments and the file's `@module` are out. An old or unknown prefix reads as stale, never as an error.
3. Module keys are `<module>.<item>`, with type-scoped and trait-impl method forms.
4. Impl head names are bare when prelude, builtin or declared in the key's module; otherwise qualified by the module path of the binding import.
5. A test key uses the decoded name with one escape set (`\"`, `\\`, `\{`, `\u{..}`).
6. A duplicate key refuses, exit 1, and lists both sites.
7. The writer always writes a `[K.pins]` sub-table, sorted by key; the reader accepts both layouts.
8. `pin K fn` on an item that does not carry K refuses and names the K it carries. A key that names no item refuses with the nearest key.
9. `pin K` with no carrier exits 1 and writes nothing.
10. Bulk pin sets the pins to exactly the current carriers, prints each dropped key, and keeps a key whose file the scan skipped as "kept, not scanned". Exit 0 when nothing changes, 1 on refusal, 2 on a usage error.
11. The scan covers the package tree, stops at a nested `blink.toml`, and skips `build/` and dot directories.
12. A scanned file that fails to parse makes bulk pin refuse. Name and type errors do not.

**DevOps/tooling**, on the order of annotations, in a vote note:

> I would key the sort on the §11.1 table order that fmt already enforces [...], not on the alphabetical name. Either order is fixed and keeps fmt from staling a pin.

#### Phase D — Round 2

Two questions stayed open. N: does the hash see the imports an item uses? Q2-file: F-e or F-a?

**N-I (syntactic import rule): 6-0.**

**Systems:**

> The hash stays a pure function of the parse tree. pin, `blink check`, `blink build` and the LSP compute it the same way, with no dependency on the checker's renames or on the resolver's order across files, and its cost is predictable. It closes the import swap, which is the fail-open case that matters.

**PLT:**

> Blink has no glob imports, so the set of import lines that could bind any free name of the item is a sound over-approximation of its binding environment. Every way N-I can differ from N-R is a spurious stale, which is fail-closed, never a silent false fresh.

> Concern: if Blink ever adds glob or re-export imports, "the import that binds x" stops being syntactic, and that change must revisit this rule (and bump the ast prefix), not quietly approximate it.

**Web/scripting:**

> Pin needs only a parse, so a user can re-pin the fn they just fixed while another file still has an unrelated name error. That is the everyday workflow.

> Concern: users will assume the pin covers a same-name def in another file of the same @module. The "not covered" paragraph must show that case with a short example, not only name it.

**DevOps/tooling:**

> The qualifier should be the import's module path as written (`import x.y.{Show}` gives `pg.(x.y.Show for Conn).show`, an `as` alias gives the aliased path's module), so two imports can never give one key.

**Q2-file: F-e 5-1.** DevOps moved from F-a to F-e. Web/scripting kept F-a.

**DevOps/tooling:**

> Every path F-a refuses is a legal file whose only repair is a rename, and a tool should not force a rename for a key format. F-e refuses only non-UTF-8 paths, and the leading `"` makes the injectivity argument one line. The quoting cost belongs to the writer, and a fixed rule handles it.

**PLT:**

> F-e is injective by the first character, with no separator to forbid: a module key starts with an identifier character and a file key starts with `"`.

**Minimalism:**

> it reuses the one string-literal escape set that test names use, so it needs no separator rule and no refusal rule. It refuses only non-UTF-8 paths, which cannot be a Str anyway. Injectivity rests on the first character alone.

**AI/ML:**

> Concern: nested quotes ('"tests/x.bl".test "a b"') invite errors when an agent retypes a key. Every note, help line and `--json` record must print the key ready to paste, and a key that names no item must suggest the nearest one.

**Web/scripting (dissent):**

> `tests/db_test.bl::make_fixture` is the pytest node-ID shape, so Python devs read it on sight. In the common fn case it needs no inner quotes in TOML, in a diff or in a shell. Refusing a path that holds "::" costs almost nothing, because nobody names test files that way.

All six seats accepted the agreed block as written in Phase D (the last ballot line).

### Final Spec

```blink
import db.{query}            // in the hash: binds `query`
import fmt.{println}         // in the hash: binds `println`
import time                  // out: the fn never uses `time.`

@ffi("sqlite3", "sqlite3_open")
@trusted(audit: "DB-003")
@allow(UnusedParam)
fn raw_open(f: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int ! ()
```

```toml
[DB-003.pins]
'db.sqlite.raw_open' = "ast1:3f9c0a4e1b7d"
'"tests/db_test.bl".test "opens: 12"' = "ast1:77aa01bc9d10"
```

- The pin is `ast1:` plus a hash of the prefix, the record name K, the parse tree of the item without its own `@trusted` tag, and each `import` line of the file, as written, that binds a free name of the item.
- Annotations are hashed in the §11.1 row order. `blink fmt` never stales a pin. A change of that order bumps the prefix to `ast2`.
- A pin does not cover callee bodies, alias right-hand sides, `@ffi` struct layout or method dispatch by type. The spec shows a two-file case.
- A module key is `<module>.<item>`. A key in a file with no `@module` is `"<path>".<item>`. A file key starts with `"` and a module key starts with an identifier character, so the two never collide.
- `blink audit pin K` pins exactly the current carriers of K. `blink audit pin K <key>` pins one item. Both refuse, with exit 1 and no write, on a duplicate key, on a file that fails to parse, and on an item that does not carry K. A bulk pin with no carrier also refuses.
- Every note and help line prints the key shell-quoted. `--json` prints the raw key.

| Question | Result |
|----------|--------|
| Q1: K in the hash, own `@trusted` tag out | 5-1 (Web/scripting wanted the tag in the hash) |
| N: imports as written that bind a used name | 6-0 |
| Q2-file: `"path".item` | 5-1 (Web/scripting wanted `path::item`) |
| Agreed block (twelve points) | 6-0 |
