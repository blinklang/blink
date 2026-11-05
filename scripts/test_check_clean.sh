#!/bin/bash
# Proves scripts/check_clean.sh goes red on each broken promise, accepts only
# what it should, and exits 2 when it cannot judge; and that
# scripts/check_clean_shrink.sh fails when the list grows. The row runs against
# a fake blink that reads each program's own first line for what to do, so this
# takes seconds and never touches build/.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0
script="$(pwd)/scripts/check_clean.sh"

# A program's first line is
# `// check=<rc> build=<rc> binary=<0|1|2> need=<path> hang=<0|1> say=<text>`.
# It keeps what real blink does with the row's setup: `need` is a path that the
# build resolves against its cwd, and an absolute entry path makes the verdict
# depend on where the checkout lives. A setting that the row must set or clear
# stops the fake with an ICE, so each row below also proves the setup.
cat > "$WORK/blink" <<'FAKE'
#!/bin/bash
cmd=$1; shift
out=""
if [ "$cmd" = build ]; then [ "$1" = -o ] && { out=$2; shift 2; }; fi
bad=""
for v in BLINK_ROOT BLINK_COMPILER_ARCHIVE BLINK_PER_MODULE BLINK_ONLY_MODULE; do
    [ -n "${!v+x}" ] && bad="$v is set"
done
[ "${BLINK_JOBS:-}" = 1 ] || bad="BLINK_JOBS is ${BLINK_JOBS:-unset}"
[ -n "${GC_MARKERS:-}" ] || bad="GC_MARKERS is unset"
case "$1" in /*) bad="absolute entry path" ;; esac
if [ -n "$bad" ]; then
    echo "internal compiler error[FakeSetup]: $bad" >&2
    exit 101
fi
head=$(head -n 1 "$1")
get() { sed -n "s/.*$1=\([^ ]*\).*/\1/p" <<< "$head"; }
say=$(sed -n 's/.* say=//p' <<< "$head")
if [ "$cmd" = check ]; then exit "$(get check)"; fi
if [ "$(get hang)" = 1 ]; then
    [ -z "${FAKE_PIDS:-}" ] || echo "$$" >> "$FAKE_PIDS"
    exec sleep 30
fi
need=$(get need)
if [ -n "$need" ] && [ ! -e "$need" ]; then
    echo "error[NativeDependencyBuildFailed]: $need: No such file or directory" >&2
    exit 1
fi
[ -n "$say" ] && printf '%b\n' "$say" >&2
if [ "$(get binary)" = 1 ]; then : > "$out"; chmod +x "$out"; fi
if [ "$(get binary)" = 2 ]; then : > "$out"; chmod -x "$out"; fi
exit "$(get build)"
FAKE
chmod +x "$WORK/blink"

T="$WORK/tree"
reset() {
    rm -rf "$T"
    mkdir -p "$T/tests/check_clean" "$T/examples" "$T/scripts"
    : > "$T/scripts/check_clean_known_failures.txt"
    prog ok check=0 build=0 binary=1
}
prog() { n=$1; shift; printf '// %s\nfn main() { }\n' "$*" > "$T/tests/check_clean/$n.bl"; }
list() { printf '%s\n' "$1" >> "$T/scripts/check_clean_known_failures.txt"; }
ICE='say=internal compiler error[NoTypeForNode]: node 1'

expect() {
    want=$1; label=$2; shift 2
    out=$(CHECK_CLEAN_ROOT="$T" CHECK_CLEAN_BLINK="$WORK/blink" "$script" 2>&1)
    rc=$?
    ok=1
    [ "$rc" = "$want" ] || ok=0
    for pat in "$@"; do grep -qF -- "$pat" <<< "$out" || ok=0; done
    if [ "$ok" = 1 ]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label (want exit $want, got $rc)"
        sed 's/^/    /' <<< "$out"
        fail=1
    fi
}

reset
expect 0 "a program that builds is green" "check-clean: ok (1 judged: 1 built"

reset; prog ice check=0 build=101 binary=0 "$ICE"
expect 1 "a new program that ICEs goes red" "RED tests/check_clean/ice.bl" "NoTypeForNode"

reset; prog cfail check=0 build=101 binary=0 'say=internal compiler error[GeneratedCDidNotCompile]: x'
expect 1 "a new C failure goes red" "RED tests/check_clean/cfail.bl" "GeneratedCDidNotCompile"

reset; prog killed check=0 build=137 binary=0
expect 1 "a build killed by a signal goes red" "RED tests/check_clean/killed.bl" "build exit 137"

reset; prog nobin check=0 build=0 binary=0
expect 1 "build exit 0 with no binary goes red" "RED tests/check_clean/nobin.bl" "no executable output"

reset; prog noexec check=0 build=0 binary=2
expect 1 "build exit 0 with an output that does not execute goes red" "RED tests/check_clean/noexec.bl" "no executable output"

reset; prog other check=0 build=1 binary=0 'say=error[TypeError]: only build sees this'
expect 1 "a stop that §6.7.3 does not list goes red under its own label" \
    "RED tests/check_clean/other.bl: check passed, then a stop that" "TypeError"

reset; prog silent check=0 build=1 binary=0
expect 1 "build exit 1 that names no error goes red" "RED tests/check_clean/silent.bl"

reset; prog mixed check=0 build=1 binary=0 'say=error[LinkFailed]: x\nerror[TypeError]: y'
expect 1 "an outside cause beside any other error goes red" "RED tests/check_clean/mixed.bl"

for name in ForeignHeaderNotFound ForeignConstInvalid LinkFailed NativeDependencyBuildFailed; do
    reset; prog out check=0 build=1 binary=0 "say=error[$name]: x"
    printf '@ffi\n' >> "$T/tests/check_clean/out.bl"
    expect 0 "outside cause $name is not red" "outside cause tests/check_clean/out.bl: $name"
    reset; prog noc check=0 build=1 binary=0 "say=error[$name]: x"
    expect 1 "$name in a program with no C side goes red" \
        "RED tests/check_clean/noc.bl: check passed, then a stop that"
done

reset; prog stale check=0 build=1 binary=0 "say=error[LinkFailed]: x"
printf '@ffi\n' >> "$T/tests/check_clean/stale.bl"
list "tests/check_clean/stale.bl ICE X: y"
expect 1 "a listed program whose stop is now an outside cause goes red" "RED tests/check_clean/stale.bl: on the list but"

reset; mkdir -p "$T/tests/check_clean/nat/src"
printf '// check=0 build=1 binary=0 say=error[NativeDependencyBuildFailed]: x\nfn main() { }\n' > "$T/tests/check_clean/nat/src/main.bl"
printf '[native-dependencies]\n' > "$T/tests/check_clean/nat/blink.toml"
expect 0 "a package with a native dependency in its manifest has a C side" "outside cause tests/check_clean/nat/src/main.bl"

reset; mkdir -p "$T/tests/check_clean/ven/src" "$T/tests/check_clean/ven/vendor"
printf '// check=0 build=0 binary=1 need=vendor/z.c\nfn main() { }\n' > "$T/tests/check_clean/ven/src/main.bl"
: > "$T/tests/check_clean/ven/vendor/z.c"
printf '[native-dependencies]\n' > "$T/tests/check_clean/ven/blink.toml"
expect 0 "a package builds from its own root, so a vendored path resolves" "check-clean: ok (2 judged: 2 built"

reset; prog ffiword check=0 build=1 binary=0 "say=error[LinkFailed]: x"
printf '// no @ffi here\n' >> "$T/tests/check_clean/ffiword.bl"
expect 1 "a comment that names @ffi gives no C side" "RED tests/check_clean/ffiword.bl: check passed, then a stop that"

reset; mkdir -p "$T/tests/check_clean/natword/src"
printf '// check=0 build=1 binary=0 say=error[NativeDependencyBuildFailed]: x\nfn main() { }\n' > "$T/tests/check_clean/natword/src/main.bl"
printf '# no native-dependencies here\n' > "$T/tests/check_clean/natword/blink.toml"
expect 1 "a manifest comment that names native-dependencies gives no C side" "RED tests/check_clean/natword/src/main.bl"

for sym in main blink_foo; do
    reset; prog nomain check=0 build=1 binary=0 "say=error[LinkFailed]: undefined reference to \`$sym'"
    printf '@ffi\n' >> "$T/tests/check_clean/nomain.bl"
    expect 1 "a link failure on $sym is not an outside cause, with a C side or not" "RED tests/check_clean/nomain.bl"
done

reset; prog plain check=0 build=1 binary=0 'say=error[LinkFailed]: x\nerror: the output dir is gone'
printf '@ffi\n' >> "$T/tests/check_clean/plain.bl"
expect 1 "a plain error line beside an outside cause goes red" "RED tests/check_clean/plain.bl"

reset; prog rej check=1 build=101 binary=0
expect 0 "a program check rejects is not judged, and the row names it" "not judged, check rejects: rej.bl"

reset; prog crash check=101 build=0 binary=1
expect 1 "a check that does not run clean goes red" "RED tests/check_clean/crash.bl: the check did not run clean"

reset; prog known check=0 build=101 binary=0 "$ICE"
list "tests/check_clean/known.bl ICE NoTypeForNode: x"
expect 0 "a listed failure stays green" "1 listed"

reset; prog known check=0 build=1 binary=0 "say=error[LinkFailed]: x"
list "tests/check_clean/known.bl LinkFailed: x"
expect 0 "a listed error stays green" "1 listed"

reset; prog known check=0 build=101 binary=0 'say=internal compiler error[LayoutDeclined]: y'
list "tests/check_clean/known.bl ICE NoTypeForNode: x"
expect 1 "a listed program with another ICE goes red" "RED tests/check_clean/known.bl: on the list for ICE NoTypeForNode, but now" "LayoutDeclined"

reset; prog known check=0 build=1 binary=0 'say=error[NoTypeForNode]: y'
list "tests/check_clean/known.bl ICE NoTypeForNode: x"
expect 1 "a listed ICE that is now an error of the same name goes red" "RED tests/check_clean/known.bl: on the list for"

reset; prog known check=0 build=137 binary=0 "$ICE"
list "tests/check_clean/known.bl ICE NoTypeForNode: x"
expect 1 "a listed program killed by a signal goes red" "RED tests/check_clean/known.bl: on the list for" "build exit 137"

reset; prog known check=0 build=0 binary=0
list "tests/check_clean/known.bl ICE NoTypeForNode: x"
expect 1 "a listed program with exit 0 and no binary goes red" "RED tests/check_clean/known.bl: on the list for" "no executable output"

reset; prog known check=0 build=0 binary=0 hang=1
list "tests/check_clean/known.bl ICE NoTypeForNode: x"
CHECK_CLEAN_BUILD_LIMIT=1 expect 1 "a listed program past the time limit goes red" "RED tests/check_clean/known.bl: on the list for" "build exit 124"

reset; prog hang check=0 build=0 binary=1 hang=1
CHECK_CLEAN_BUILD_LIMIT=1 expect 1 "a build past the time limit goes red" "RED tests/check_clean/hang.bl" "build exit 124"

reset
BLINK_ROOT=x BLINK_COMPILER_ARCHIVE=x BLINK_PER_MODULE=1 BLINK_ONLY_MODULE=x BLINK_JOBS=64 GC_MARKERS= \
    expect 0 "a caller's compiler settings do not reach the row" "check-clean: ok (1 judged: 1 built"

# A signal ends the sweep at once, as a failfast sibling in the gate needs. TERM,
# as a shell's background job ignores INT and cannot trap it.
reset; prog hang check=0 build=0 binary=1 hang=1
mkdir "$WORK/tmp"; : > "$WORK/pids"
TMPDIR="$WORK/tmp" FAKE_PIDS="$WORK/pids" CHECK_CLEAN_ROOT="$T" CHECK_CLEAN_BLINK="$WORK/blink" "$script" > /dev/null 2>&1 &
row=$!
for _ in $(seq 1 100); do [ -s "$WORK/pids" ] && break; sleep 0.1; done
kill -TERM "$row"
wait "$row"; rc=$?
# The KILLed worker's parent dies with it, so the user's systemd reaps it, and a
# busy systemd reaps late. kill -0 still finds a zombie, but a zombie does not
# run. A worker that the KILL reached may still be in its exit, so this waits
# for that a short time.
alive() {
    local st
    st=$(ps -o stat= -p "$1" 2> /dev/null) && [ "${st#Z}" = "$st" ]
}
worker=$(cat "$WORK/pids")
for _ in $(seq 1 20); do alive "$worker" || break; sleep 0.1; done
if [ "$rc" = 143 ] && [ -n "$worker" ] && ! alive "$worker" && [ -z "$(ls -A "$WORK/tmp")" ]; then
    echo "PASS: a signal stops the sweep's workers and removes its temp dir"
else
    echo "FAIL: a signal stops the sweep (exit $rc, pids $worker, state $(ps -o stat= -p "$worker" 2> /dev/null), temp: $(ls -A "$WORK/tmp"))"
    fail=1
fi

reset; prog fixed check=0 build=0 binary=1
list "tests/check_clean/fixed.bl ICE NoTypeForNode: x"
expect 1 "a listed program that builds goes red until its line leaves" "RED tests/check_clean/fixed.bl: on the list but it builds now"

reset; prog nowrej check=1 build=0 binary=0
list "tests/check_clean/nowrej.bl ICE NoTypeForNode: x"
expect 1 "a listed program that check rejects goes red" "RED tests/check_clean/nowrej.bl: on the list but check rejects it now"

reset
list "tests/check_clean/gone.bl ICE NoTypeForNode: x"
expect 1 "a listed file that is gone goes red" "RED tests/check_clean/gone.bl: on the list but the row does not sweep it"

reset; prog known check=0 build=101 binary=0 "$ICE"; list "tests/check_clean/known.bl"
expect 2 "a list line with no reason is malformed" "no reason"

reset; prog known check=0 build=101 binary=0 "$ICE"; list "tests/check_clean/known.bl ICE A: a"; list "tests/check_clean/known.bl ICE A: b"
expect 2 "a path listed twice is malformed" "listed twice"

reset; prog known check=0 build=101 binary=0 "$ICE"; list "tests/check_clean/known.bl fails somehow"
expect 2 "a list line with no stop name is malformed" "no stop name"

reset; rm "$T/scripts/check_clean_known_failures.txt"
expect 2 "a missing list stops the row" "no known-failure list"

reset; rm "$T/tests/check_clean/ok.bl"; prog rej check=1 build=0 binary=0
expect 2 "a sweep that judges nothing does not pass" "judged nothing"

reset; mkdir "$T/tests/check_clean/pkg"
expect 2 "a package with no entry file stops the row" "has no src/main.bl"

reset; mkdir -p "$T/tests/check_clean/pkg/src"
printf '// check=0 build=101 binary=0 %s\n' "$ICE" > "$T/tests/check_clean/pkg/src/main.bl"
expect 1 "the row sweeps a package" "RED tests/check_clean/pkg/src/main.bl"

reset; printf '// check=0 build=101 binary=0 %s\n' "$ICE" > "$T/examples/e.bl"
expect 1 "the row sweeps examples" "RED examples/e.bl"

out=$(CHECK_CLEAN_ROOT="$T" CHECK_CLEAN_BLINK="$WORK/none" "$script" 2>&1); rc=$?
if [ "$rc" = 2 ]; then echo "PASS: no compiler stops the row"; else echo "FAIL: no compiler: exit $rc"; echo "$out"; fail=1; fi

# The shrink check runs as an unmodified copy in a throwaway repo.
R="$WORK/repo"
L=scripts/check_clean_known_failures.txt
new_repo() {
    rm -rf "$R"
    mkdir -p "$R/scripts" "$R/p"
    cp scripts/check_clean_shrink.sh "$R/scripts/"
    (
        cd "$R" && git init -q -b main . && git config user.email t@t && git config user.name t
        touch p/a.bl p/b.bl p/c.bl
        printf 'p/a.bl x\np/b.bl y\n' > "$L"
        git commit -q --allow-empty -m root
        git add -A && git commit -qm base && git checkout -qb work
    )
}
shrink_expect() {
    want=$1; label=$2; pat=$3
    out=$(cd "$R" && env -u CHECK_CLEAN_BASE_REF ./scripts/check_clean_shrink.sh 2>&1)
    rc=$?
    if [ "$rc" = "$want" ] && grep -qF -- "$pat" <<< "$out"; then
        echo "PASS: $label"
    else
        echo "FAIL: $label (want exit $want, got $rc)"
        sed 's/^/    /' <<< "$out"
        fail=1
    fi
}
commit_all() { (cd "$R" && git add -A && git commit -qm "$1"); }

new_repo
shrink_expect 0 "no change to the list is green" "check-clean-shrink: ok (HEAD^..HEAD"

new_repo; (cd "$R" && printf 'p/a.bl x\np/b.bl y\np/c.bl z\n' > "$L"); commit_all add
shrink_expect 1 "a commit that adds an entry goes red, compared to main" "main..HEAD"

new_repo; (cd "$R" && printf 'p/a.bl x\np/c.bl z\n' > "$L"); commit_all swap
shrink_expect 1 "a swap of one entry for another goes red" "adds p/c.bl"

new_repo; (cd "$R" && printf 'p/a.bl x\n' > "$L"); commit_all drop
shrink_expect 0 "a commit that takes an entry off is green" "check-clean-shrink: ok"

new_repo; (cd "$R" && printf 'p/a.bl x\n' > "$L" && rm p/b.bl); commit_all "drop and delete"
shrink_expect 1 "taking an entry off by deleting its program goes red" "deletes its program"

new_repo; (cd "$R" && printf 'p/a.bl x\np/b.bl changed reason\n' > "$L"); commit_all reword
shrink_expect 0 "a new reason on the same path is green" "check-clean-shrink: ok"

new_repo; (cd "$R" && printf 'p/a.bl x\np/b.bl y\np/c.bl z\n' > "$L"); commit_all add; (cd "$R" && printf 'p/a.bl x\np/b.bl y\n' > "$L"); commit_all undo
shrink_expect 1 "an entry that a later commit takes off still fails its own commit" "adds p/c.bl"

new_repo; (cd "$R" && printf 'p/a.bl x\np/b.bl y\np/c.bl z\n' > "$L")
shrink_expect 1 "an uncommitted added entry goes red" "the working tree adds p/c.bl"

new_repo; (cd "$R" && rm "$L"); commit_all "delete list"
shrink_expect 1 "a commit that deletes the list goes red" "deletes the list"

new_repo; (cd "$R" && rm "$L"); commit_all "delete list"; (cd "$R" && printf 'p/c.bl z\n' > "$L"); commit_all "again"
shrink_expect 1 "adding the list again goes red" "adds the list again"

new_repo; (cd "$R" && git checkout -q main && git branch -qD work && git branch -q trunk && git checkout -q trunk && git branch -qD main)
shrink_expect 2 "a base ref that does not resolve goes red" "does not resolve"

rm -rf "$R"; mkdir -p "$R/scripts"; cp scripts/check_clean_shrink.sh "$R/scripts/"
(cd "$R" && git init -q -b main . && git config user.email t@t && git config user.name t && git add -A && git commit -qm only)
shrink_expect 2 "HEAD on the base with no parent goes red" "has no parent"

# The commit that first adds the list has no parent list to compare.
rm -rf "$R"; mkdir -p "$R/scripts" "$R/p"; cp scripts/check_clean_shrink.sh "$R/scripts/"
(cd "$R" && git init -q -b main . && git config user.email t@t && git config user.name t && git add -A && git commit -qm base && git checkout -qb work && touch p/a.bl && printf 'p/a.bl x\n' > "$L" && git add -A && git commit -qm seed)
shrink_expect 0 "the commit that first adds the list is exempt" "check-clean-shrink: ok"

# On the base, as in the main gate after a land, the tip commit is still judged.
new_repo; (cd "$R" && git checkout -q main && printf 'p/a.bl x\np/b.bl y\np/c.bl z\n' > "$L" && git add -A && git commit -qm "on main")
shrink_expect 1 "on the base branch the range is the tip commit" "adds p/c.bl"

# A land brings a stack with no merge commit, so each commit not pushed counts.
new_repo; (cd "$R" && git checkout -q main && git update-ref refs/remotes/origin/main HEAD \
    && git config remote.origin.url . && git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' && git branch -q -u origin/main main \
    && printf 'p/a.bl x\np/b.bl y\np/c.bl z\n' > "$L" && git add -A && git commit -qm "stack adds" && git commit -q --allow-empty -m tip)
shrink_expect 1 "on the base, a commit below the tip that is not pushed goes red" "adds p/c.bl"

new_repo; rm -rf "$R.shallow"; git clone -q --depth 1 "file://$R" "$R.shallow" 2> /dev/null
out=$(cd "$R.shallow" && git branch -q main 2> /dev/null; env -u CHECK_CLEAN_BASE_REF ./scripts/check_clean_shrink.sh 2>&1); rc=$?
if [ "$rc" = 2 ] && grep -qF "shallow clone" <<< "$out"; then
    echo "PASS: a shallow clone stops the shrink check"
else
    echo "FAIL: a shallow clone (exit $rc): $out"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "test_check_clean: FAIL"
    exit 1
fi
echo "test_check_clean: ok"
