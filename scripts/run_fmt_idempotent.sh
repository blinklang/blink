#!/bin/sh
# Idempotency test: format(format(x)) == format(x)
f="$1"
blinkc="$2"
skip_file="$3"
name=$(basename "$f" .bl)
[ -f "$skip_file" ] && grep -qw "$name" "$skip_file" && { echo "SKIP idem_${name}"; exit 0; }
fmt1=$(mktemp "${TMPDIR:-/tmp}/fmt-idem1-XXXXXX")
fmt2=$(mktemp "${TMPDIR:-/tmp}/fmt-idem2-XXXXXX")
# child <command...>: run the command as a capped child (scripts/capped.sh
# --child). Its stderr, with the line capped.sh prints for a cap it hit, goes
# to $child_err; check_limit fails the file when such a line is there, so a
# runaway file fails as itself and names the limit.
child_err=$(mktemp "${TMPDIR:-/tmp}/fmt-child-XXXXXX")
child() { "$(dirname "$0")/capped.sh" --child "$@" 2>>"$child_err"; }
# fail_with <reason>: fail the file, naming the cap a child hit over the reason.
fail_with() {
  limit=$(grep '^capped.sh: the child' "$child_err" | tail -1)
  rm -f "$fmt1" "$fmt2" "$child_err"
  echo "FAIL (${limit:-$1}) ${name}"
  exit 1
}
# A formatter abort on either pass is a formatter bug; only the skip list may
# excuse it.
child "$blinkc" "$f" "$fmt1" --emit blink || fail_with "format"
child "$blinkc" "$fmt1" "$fmt2" --emit blink || fail_with "formatted output does not re-format"
rm -f "$child_err"
if diff -q "$fmt1" "$fmt2" >/dev/null 2>&1; then
  rm -f "$fmt1" "$fmt2"
  echo "PASS idem_${name}"
else
  rm -f "$fmt1" "$fmt2"
  echo "FAIL (idempotent) ${name}"
  exit 1
fi
