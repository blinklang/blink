#!/bin/bash
# Proves scripts/check_spec_refs.sh goes red on each kind of bad ref it exists
# to catch, stays green on the forms a good ref takes, and exits 2 (not 0)
# when it cannot read its inputs. Runs the script against a canned tree in a
# temp directory, so it never reads the real spec.
set -u
cd "$(dirname "$0")/.."
script="$PWD/scripts/check_spec_refs.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

# reset: a small tree where every ref resolves.
reset() {
    rm -rf "$WORK/t"
    mkdir -p "$WORK/t/sections"
    cat > "$WORK/t/sections/01_a.md" <<'EOF'
## 1. One

### 1.1 Sub

Text that cites §1.2, §1.2.1 and section 1.1.

#### Unnumbered

#### 1.1.1 Deep

### 1.2 Two

### 1.2.1 Same level as its parent

```
## 9.9 Not a heading inside a fence
```

~~~
# 9.8 Nor in a tilde fence, though it cites §1.1
~~~
EOF
    cat > "$WORK/t/sections/03b_b.md" <<'EOF'
## 3b. Letters

### 3b.1 First

#### §3b.1.1 Sign-led heading

Cites §3b, §3b.1's text, (§3b.1.1). And §1.1. Then §1.2.
EOF
    cat > "$WORK/t/ERROR_CATALOG.md" <<'EOF'
# Catalog

| Range | Category |
|-------|----------|
| E0xxx | Types |

| Code | Name | Implementation |
|------|------|----------------|
| E0001 | Alpha | here |

| Name | Code | One-line |
|------|------|----------|
| SomeIce | I0001 | no spec ref column |

| Name | Code | Retired because | Replaced by |
|------|------|-----------------|-------------|
| Old | E0003 | gone, see §1.1 | Alpha (E0001) |
| Older | — | no code | None |

| Name | Code | One-line | Category | Spec ref |
|------|------|----------|----------|----------|
| Alpha | E0001 | an `a \| b` pipe stays in its cell | Cat | §1.1 |
| Beta | E0002 | two refs | Cat | §1.2.1, §3b.1 |
| Gamma | W0001 | no ref yet | Cat |  |
EOF
    echo 'See §1.1.' > "$WORK/t/llms.md"
    echo 'See §3b.1.1.' > "$WORK/t/llms-full.md"
}

# expect <exit> "<label>" [<text the output must hold> ...]
expect() {
    want="$1"; label="$2"; shift 2
    out=$(SPEC_REFS_ROOT="$WORK/t" "$script" 2>&1)
    rc=$?
    ok=1
    [ "$rc" = "$want" ] || ok=0
    for needle in "$@"; do
        grep -qF -- "$needle" <<< "$out" || ok=0
    done
    if [ "$ok" = 1 ]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label (want exit $want, got $rc)"
        sed 's/^/    /' <<< "$out"
        fail=1
    fi
}

# append <file> <text>: add one line to a file of the canned tree.
append() {
    printf '%s\n' "$2" >> "$WORK/t/$1"
}

reset
expect 0 "a tree where every ref resolves passes" "spec-refs: ok"

reset; append sections/01_a.md 'Cites §1.3 here.'
expect 1 "a ref to no heading goes red and names its site" \
    "sections/01_a.md:22 §1.3 -> no numbered heading has this number" "spec-refs: FAIL 1"

reset; append sections/01_a.md 'Fenced refs count too:'; append sections/01_a.md '```'
append sections/01_a.md 'x // §7.7'; append sections/01_a.md '```'
expect 1 "a ref inside a fenced block still counts" "§7.7 -> no numbered heading"

reset; append sections/01_a.md 'A heading cites §9.9 from a fence.'
expect 1 "a heading inside a fence defines no number" "§9.9 -> no numbered heading"

reset; append sections/01_a.md 'As section 4.2 says.'
expect 1 "a prose Section ref to no heading goes red" "section 4.2 -> no numbered heading"

reset; append sections/01_a.md 'Per Sections 1.4 and on.'
expect 1 "a plural prose Sections ref is read too" "Sections 1.4 -> no numbered heading"

reset; append ERROR_CATALOG.md '| Delta | E0004 | bad ref | Cat | §2.1 |'
expect 1 "a catalog spec-ref to no heading goes red" "ERROR_CATALOG.md:25 §2.1 -> no numbered heading"

reset; sed -i 's/^| E0001 | Alpha | here |$/| E0001 | Alfa | here |/' "$WORK/t/ERROR_CATALOG.md"
expect 1 "an implemented-codes row whose name drifted goes red" \
    "ERROR_CATALOG.md:9 E0001 -> named Alfa here, Alpha at ERROR_CATALOG.md:22"

reset; sed -i 's/^| E0001 | Alpha | here |$/| E0099 | Alpha | here |/' "$WORK/t/ERROR_CATALOG.md"
expect 1 "an implemented-codes row with no defining row goes red" \
    "ERROR_CATALOG.md:9 E0099 -> no defining table has this code"

reset; append ERROR_CATALOG.md ''; append ERROR_CATALOG.md '| Foo | Bar |'; append ERROR_CATALOG.md '|---|---|'
expect 2 "a table header of no known kind cannot be read" \
    "ERROR_CATALOG.md:26 -> a table header the gate does not know: Foo | Bar"

reset; append llms.md 'and §5'
expect 1 "llms.md is gated" "llms.md:2 §5 -> no numbered heading"

reset; append llms-full.md 'and §5'
expect 1 "llms-full.md is gated" "llms-full.md:2 §5 -> no numbered heading"

reset; append sections/01_a.md 'See §07:163.'
expect 1 "a file coordinate with a leading zero goes red" "§07:163 -> a file:line coordinate"

reset; append sections/01_a.md 'See §1.1:20.'
expect 1 "a ref with a line tail goes red" "§1.1:20 -> a file:line coordinate"

reset; append sections/01_a.md 'See §1.1-1.2.'
expect 1 "a range goes red" "§1.1-1.2 -> a range"

reset; append sections/01_a.md 'See §1.1–§1.2.'
expect 1 "a range with an en dash goes red" "-> a range"

reset; append sections/01_a.md 'See §1.x for more.'
expect 1 "a placeholder goes red, never resolves as its head" "§1.x -> not a section number"

reset; append sections/01_a.md 'See §1.1a here.'
expect 1 "a number run into a letter goes red" "§1.1a -> not a section number"

reset; append sections/01_a.md 'See § 1.1 here.'
expect 1 "a space after the sign goes red" "§ 1.1 -> no space between"

reset; append sections/01_a.md '`§` alone in code is not a ref.'
expect 0 "a bare sign with no number is not a ref"

reset; append sections/01_a.md 'See §1.1. Then §1.2: and §1.2.1, then (§3b.1). And §1.1-style text.'
expect 0 "punctuation after a ref is not part of it"

reset; append sections/03b_b.md '### 3b.2.1 Orphan'
expect 1 "an orphan subsection whose parent number is absent goes red" \
    "sections/03b_b.md:8 3b.2.1 -> the heading sits under 3b.1, not under its parent 3b.2" "spec-refs: FAIL"

reset; append sections/01_a.md '#### 1.1.2 Out of place'
expect 1 "a subsection inside the wrong parent goes red" \
    "sections/01_a.md:22 1.1.2 -> the heading sits under 1.2, not under its parent 1.1"

reset; append sections/03b_b.md '### 1.1 Again'
expect 1 "a number defined twice goes red" "sections/03b_b.md:8 1.1 -> also defined at sections/01_a.md:3"

reset; append ERROR_CATALOG.md '| Delta | E0001 | dup | Cat | §1.1 |'
expect 1 "a code used twice in the catalog goes red" "ERROR_CATALOG.md:25 E0001 -> code also at ERROR_CATALOG.md:22"

reset; append ERROR_CATALOG.md '| Alpha | E0009 | dup | Cat | §1.1 |'
expect 1 "a name used twice in the catalog goes red" "ERROR_CATALOG.md:25 Alpha -> name also at ERROR_CATALOG.md:22"

reset; append ERROR_CATALOG.md '| Gone | E0003 | x | Cat | §1.1 |'
expect 1 "a code in a live and a retired table collides" "ERROR_CATALOG.md:25 E0003 -> code also at ERROR_CATALOG.md:17"

reset; append ERROR_CATALOG.md '| Delta | E0004 | x | Cat | see 1.1 |'
expect 1 "a spec-ref cell that is not a list of refs goes red" \
    "ERROR_CATALOG.md:25 -> the Spec ref cell is not a comma-separated list of § refs: see 1.1"

reset; sed -i 's/an `a \\| b` pipe/an `a | b` pipe/' "$WORK/t/ERROR_CATALOG.md"
expect 2 "a catalog row with the wrong cell count cannot be read" \
    "ERROR_CATALOG.md:22 -> the row has 6 cells, its table header has 5"

reset; rm "$WORK/t/llms.md"
expect 2 "a missing gated file cannot be read" "llms.md"

reset; rm "$WORK/t/sections/"*.md
expect 2 "a tree with no spec files cannot be read" "no sections/*.md"

reset; printf 'no headings\n' > "$WORK/t/sections/01_a.md"; rm "$WORK/t/sections/03b_b.md"
expect 2 "spec files with no numbered heading cannot be read" "no numbered heading in sections"

reset; printf '# Catalog\n\nno tables\n' > "$WORK/t/ERROR_CATALOG.md"
expect 2 "a catalog with no Spec ref table cannot be read" "Spec ref"

reset; append sections/01_a.md 'One §8.1 and §8.2 here.'; append llms.md '§8.3'
expect 1 "every broken ref prints, and the count adds up" "§8.1 ->" "§8.2 ->" "§8.3 ->" "spec-refs: FAIL 3"

reset; append sections/01_a.md '````'; append sections/01_a.md '```'; append sections/01_a.md '## 9.7 Inside a longer fence'
append sections/01_a.md '```'; append sections/01_a.md '````'; append sections/01_a.md 'Cites §9.7.'
expect 1 "a short fence line inside a longer fence does not close it" "§9.7 -> no numbered heading"

reset; append sections/01_a.md '```'; append sections/01_a.md '```blink'; append sections/01_a.md '## 9.6 Inside a fence'
append sections/01_a.md '```'; append sections/01_a.md 'Cites §9.6.'
expect 1 "a fence line with an info string does not close a fence" "§9.6 -> no numbered heading"

reset; append sections/01_a.md '```'; append sections/01_a.md '## 9.5 Never closed'
expect 2 "a fence that never closes cannot be read" "sections/01_a.md:22 -> a fence opens here and never closes"

reset; printf '```\n%s\n' "$(cat "$WORK/t/ERROR_CATALOG.md")" > "$WORK/t/ERROR_CATALOG.md.new"; mv "$WORK/t/ERROR_CATALOG.md.new" "$WORK/t/ERROR_CATALOG.md"
expect 2 "an unclosed fence cannot hide the catalog tables" "ERROR_CATALOG.md:1 -> a fence opens here and never closes"

reset; append ERROR_CATALOG.md ''; append ERROR_CATALOG.md '```'; append ERROR_CATALOG.md '| Foo | Bar |'
append ERROR_CATALOG.md '|---|---|'; append ERROR_CATALOG.md '```'
expect 0 "a table inside a fence is not a catalog table"

reset; append ERROR_CATALOG.md ''; append ERROR_CATALOG.md '~~~'; append ERROR_CATALOG.md '| Foo | Bar |'
append ERROR_CATALOG.md '~~~'
expect 0 "a table inside a tilde fence is not a catalog table"

reset; append ERROR_CATALOG.md ''; append ERROR_CATALOG.md 'Foo | Bar'; append ERROR_CATALOG.md '----|----'
expect 2 "a table with no leading pipe cannot be read" "ERROR_CATALOG.md:27 -> a table row with no leading |"

reset; append sections/01_a.md '   ### 1.3 Indented'; append sections/01_a.md 'Cites §1.3.'
expect 0 "a heading indented up to three spaces counts"

reset; append sections/01_a.md '####### 1.1.9 Seven signs'; append sections/01_a.md 'Cites §1.1.9.'
expect 1 "a line of seven signs is not a heading" "§1.1.9 -> no numbered heading"

reset; append sections/03b_b.md '### 3b.2 Next'; append sections/03b_b.md '##### 3b.1.1.1 Stale'
expect 1 "a heading cannot nest under a deeper heading of an earlier section" \
    "sections/03b_b.md:9 3b.1.1.1 -> the heading sits under no numbered heading, not under its parent 3b.1.1"

reset; append sections/01_a.md 'See sections 1.1, 1.2 and 9.4.'
expect 1 "each number of a plural prose list is judged" "9.4 -> no numbered heading" "spec-refs: FAIL 1"

reset; append ERROR_CATALOG.md '| Delta | E004 | short code | Cat | §1.1 |'
expect 1 "a defining row whose code cell is not a code goes red" "ERROR_CATALOG.md:25 E004 -> not a diagnostic code"

reset; append ERROR_CATALOG.md '| Delta | E0002a | x | Cat | §1.1 |'; append ERROR_CATALOG.md '| Delta2 | E0002a | x | Cat | §1.1 |'
expect 1 "a lettered code used twice goes red" "ERROR_CATALOG.md:26 E0002a -> code also at ERROR_CATALOG.md:25"

reset; append ERROR_CATALOG.md '| Delta | — | x | Cat | §1.1 |'
expect 1 "a live row with no code goes red" "ERROR_CATALOG.md:25 — -> not a diagnostic code"

reset; sed -i 's/^| Gamma | W0001 | no ref yet | Cat |  |$/&\n\n| Name | Code | One-line | Spec Ref |\n|---|---|---|---|\n| Eta | E0005 | x | §9.9 |/' "$WORK/t/ERROR_CATALOG.md"
expect 2 "a misspelt Spec ref column cannot be read" "ERROR_CATALOG.md:26 -> a Spec ref column spelt Spec Ref"

reset; sed -i 's/^| E0001 | Alpha | here |$/&\n| E0001 | Alpha | again |/' "$WORK/t/ERROR_CATALOG.md"
expect 1 "a code listed twice in the implemented-codes table goes red" "ERROR_CATALOG.md:10 E0001 -> also listed at ERROR_CATALOG.md:9"

reset; append sections/01_a.md '## 07. Zero-led'; append sections/01_a.md '### 7.1 Child'
expect 1 "a heading numbers its parent by text, not by value" "7.1 -> the heading sits under 07, not under its parent 7"

reset; rm "$WORK/t/llms.md"; mkdir "$WORK/t/llms.md"
expect 2 "a gated path that is a directory cannot be read" "cannot read llms.md"

exit "$fail"
