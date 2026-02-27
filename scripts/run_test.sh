#!/bin/sh
# Run a single test file: compile with pact, then execute and check output
f="$1"
pact="$2"
build_dir="$3"
name=$(basename "$f" .pact)
if ! "$pact" build "$f" 2>/dev/null; then
  echo "FAIL (build) ${name}"
  exit 1
fi
if output=$("${build_dir}/${name}" 2>&1); then
  if echo "$output" | grep -q "FAIL"; then
    echo "FAIL (assert) ${name}"
    exit 1
  else
    echo "PASS ${name}"
  fi
else
  echo "FAIL (crash) ${name}"
  exit 1
fi
