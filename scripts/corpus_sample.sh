#!/usr/bin/env bash
# Compile and run the fixed corpus sample and hold it to the floor the list
# records. The branch gate runs this in place of the full corpus: the sample
# is small enough to run on every commit and wide enough that a producer a
# slice breaks loses at least one whole program.
#
# usage: scripts/corpus_sample.sh [<list file>]
#
# The list defaults to scripts/corpus_sample.txt. It carries its own floor on
# a `# floor: N` line, so the list and the number it must reach move together
# in one commit. Output goes to build/corpus_sample.json, never to the
# corpus_subset.json a `task corpus-only` bucket writes.
set -euo pipefail

list="${1:-scripts/corpus_sample.txt}"

if [ ! -f "$list" ]; then
    echo "corpus-sample: no such list file: $list" >&2
    exit 2
fi

floor=$(sed -n 's/^# *floor: *\([0-9][0-9]*\).*/\1/p' "$list" | head -1)
if [ -z "$floor" ]; then
    echo "corpus-sample: $list records no '# floor: N' line" >&2
    exit 2
fi

out=build/corpus_sample.json
# Exit 1 is a failing file, which the floor below judges; only 2 stops here.
CORPUS_OUT="$out" ./scripts/corpus.sh --only "$list" --no-lint || [ $? -eq 1 ]

passed=$(jq -r .passed "$out")
total=$(jq -r .total "$out")

if [ "$passed" -lt "$floor" ]; then
    echo "corpus-sample: FAIL $passed/$total passed, floor is $floor" >&2
    exit 1
fi

if [ "$passed" -gt "$floor" ]; then
    echo "corpus-sample: ok $passed/$total passed, above the floor of $floor"
    echo "corpus-sample: raise the floor in $list to $passed in this commit"
    exit 0
fi

echo "corpus-sample: ok $passed/$total passed, floor $floor"
