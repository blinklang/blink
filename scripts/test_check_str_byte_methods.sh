#!/bin/bash
# Proves scripts/check_str_byte_methods.sh catches drift: each case breaks one
# of the four sources in a small fixture and must fail, and the clean fixture
# must pass.
set -u
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

write_clean() {
  cat > "$WORK/spec.md" <<'EOF'
```blink
trait StrOps {
    fn char_at(self, index: Int) -> Option[Char]
    fn byte_len(self) -> Int
    fn byte_at(self, index: Int) -> U8
    fn byte_slice(self, start: Int, end: Int) -> Str
    fn byte_index_of(self, needle: Str, from: Int) -> Option[Int]
}
```

| Method | Signature | Description |
|---|---|---|
| `len` | `fn(self) -> Int` | Codepoint count |
| `byte_len` | `fn(self) -> Int` | Byte count (O(1)) |
| `byte_at` | `fn(self, Int) -> U8` | Raw byte at offset |
| `byte_slice` | `fn(self, Int, Int) -> Str` | Byte-range slice |
| `byte_index_of` | `fn(self, Str, Int) -> Option[Int]` | Byte offset of first match |

The `byte_` methods are exactly the four in this table: `byte_len`, `byte_at`, `byte_slice` and `byte_index_of`. The prefix does not extend to other methods; there is no `byte_split` or `byte_starts_with`.
EOF
  cat > "$WORK/traits.bl" <<'EOF'
pub trait StrOps {
    fn char_at(self, index: Int) -> Option[Char]
    fn byte_len(self) -> Int
    fn byte_at(self, index: Int) -> U8
    fn byte_slice(self, start: Int, end: Int) -> Str
    fn byte_index_of(self, needle: Str, from: Int) -> Option[Int]
}

pub trait BytesOps {
    fn byte_split(self) -> Int
}
EOF
}

# expect <name> <want-exit>; the fixture is already edited for the case.
expect() {
  STR_BYTE_SPEC="$WORK/spec.md" STR_BYTE_TRAITS="$WORK/traits.bl" \
    ./scripts/check_str_byte_methods.sh > "$WORK/out" 2>&1
  got=$?
  if [ "$got" -eq "$2" ]; then
    echo "ok $1"
  else
    echo "FAIL $1: want exit $2, got $got"
    cat "$WORK/out"
    fail=1
  fi
}

write_clean
expect "clean fixture passes (a byte_ fn outside StrOps is ignored)" 0

write_clean
sed -i 's/^}$/    fn byte_split(self, sep: Str) -> List[Str]\n}/' "$WORK/traits.bl"
expect "extra byte_ method in lib StrOps fails" 1

write_clean
sed -i 's/fn byte_at(self, index: Int) -> U8/fn byte_at(self, index: Int) -> Int/' "$WORK/traits.bl"
expect "wrong return type in lib StrOps fails" 1

write_clean
sed -i '/fn byte_index_of/d' "$WORK/traits.bl"
expect "method missing from lib StrOps fails" 1

write_clean
sed -i 's/| `fn(self, Int) -> U8` |/| `fn(self, Int) -> Int` |/' "$WORK/spec.md"
expect "wrong return type in the spec table fails" 1

write_clean
sed -i 's/    fn byte_slice(self, start: Int, end: Int) -> Str/    fn byte_slice(self, start: Int) -> Str/' "$WORK/spec.md"
expect "wrong parameters in the spec trait block fails" 1

write_clean
sed -i 's/`byte_slice` and `byte_index_of`\./`byte_slice`, `byte_index_of` and `byte_split`./' "$WORK/spec.md"
expect "extra name in the spec sentence fails" 1

write_clean
sed -i '/^| `byte_slice`/d' "$WORK/spec.md"
expect "method missing from the spec table fails" 1

write_clean
sed -i 's/^pub trait StrOps {/pub trait StrOpz {/' "$WORK/traits.bl"
expect "no StrOps trait found is a setup error" 2

if [ $fail -ne 0 ]; then
  echo "test_check_str_byte_methods: FAILED"
  exit 1
fi
echo "test_check_str_byte_methods: all cases passed"
