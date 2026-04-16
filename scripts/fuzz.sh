#!/usr/bin/env bash
set -euo pipefail

COMPILER="${1:?Usage: fuzz.sh <compiler> [iterations] [seed] [timeout] [--ignore-timeouts]}"
ITERATIONS="${2:-500}"
SEED="${3:-$RANDOM}"
TIMEOUT="${4:-5}"
IGNORE_TIMEOUTS=0
if [ "${5:-}" = "--ignore-timeouts" ]; then
    IGNORE_TIMEOUTS=1
fi
CRASH_DIR=".tmp/fuzz_crashes"
INPUT_FILE=".tmp/fuzz_input.bl"

mkdir -p "$CRASH_DIR"

# --- Input generators ---

gen_random_bytes() {
    head -c $((RANDOM % 512 + 1)) /dev/urandom | base64 | head -c $((RANDOM % 256 + 1))
}

gen_token_soup() {
    local keywords=(
        fn let mut const type trait impl if else match for in while loop
        break continue return pub with handler self test import as mod
        effect assert
    )
    local operators=(
        '(' ')' '{' '}' '[' ']' ':' ',' '.' '..' '->' '=>' '@' '#'
        '+' '-' '*' '/' '%' '=' '==' '!=' '<' '>' '<=' '>=' '&&' '||'
        '!' '?' '??' '|>'
    )
    local count=$((RANDOM % 196 + 5))
    local output=""
    for ((j=0; j<count; j++)); do
        local roll=$((RANDOM % 5))
        case $roll in
            0) # keyword
                output+="${keywords[$((RANDOM % ${#keywords[@]}))]}"
                ;;
            1) # operator
                output+="${operators[$((RANDOM % ${#operators[@]}))]}"
                ;;
            2) # random int
                output+="$((RANDOM % 10000))"
                ;;
            3) # random identifier (1-6 lowercase chars)
                local len=$((RANDOM % 6 + 1))
                local ident=""
                for ((k=0; k<len; k++)); do
                    local ch=$((RANDOM % 26 + 97))
                    ident+=$(printf "\\$(printf '%03o' "$ch")")
                done
                output+="$ident"
                ;;
            4) # literal
                local lit_roll=$((RANDOM % 3))
                case $lit_roll in
                    0) output+='"hello"' ;;
                    1) output+="true" ;;
                    2) output+="false" ;;
                esac
                ;;
        esac
        # separator: space or newline
        if ((RANDOM % 5 == 0)); then
            output+=$'\n'
        else
            output+=" "
        fi
    done
    printf '%s' "$output"
}

gen_deep_nesting() {
    local depth=$((RANDOM % 151 + 50))
    local output="fn main() {"
    for ((j=0; j<depth; j++)); do
        output+=" if true {"
    done
    output+=" let x = 1"
    for ((j=0; j<depth; j++)); do
        output+=" }"
    done
    output+=" }"
    printf '%s' "$output"
}

gen_malformed_string() {
    local variant=$((RANDOM % 4))
    case $variant in
        0) # unterminated string
            printf 'fn main() { let x = "hello'
            ;;
        1) # unbalanced interpolation
            printf 'fn main() { let x = "hello {world" }'
            ;;
        2) # bad escape
            printf 'fn main() { let x = "hello\\q" }'
            ;;
        3) # nested unterminated interp
            printf 'fn main() { let x = "a {b {c" }'
            ;;
    esac
}

MUTATION_FILES=()
while IFS= read -r f; do
    size=$(wc -c < "$f")
    if ((size <= 5120)); then
        MUTATION_FILES+=("$f")
    fi
done < <(ls tests/test_*.bl 2>/dev/null)

gen_mutated_program() {
    if [ ${#MUTATION_FILES[@]} -eq 0 ]; then
        gen_token_soup
        return
    fi

    local src="${MUTATION_FILES[$((RANDOM % ${#MUTATION_FILES[@]}))]}"
    local content
    content=$(cat "$src")
    local len=${#content}

    if [ "$len" -eq 0 ]; then
        gen_token_soup
        return
    fi

    local mutations=$((RANDOM % 5 + 1))
    for ((m=0; m<mutations; m++)); do
        len=${#content}
        if [ "$len" -eq 0 ]; then break; fi
        local pos=$((RANDOM % len))
        local op=$((RANDOM % 3))
        case $op in
            0) # delete a byte
                content="${content:0:pos}${content:$((pos+1))}"
                ;;
            1) # insert a random byte
                local byte
                byte=$(printf "\\$(printf '%03o' $((RANDOM % 95 + 32)))")
                content="${content:0:pos}${byte}${content:pos}"
                ;;
            2) # substitute a random byte
                local byte
                byte=$(printf "\\$(printf '%03o' $((RANDOM % 95 + 32)))")
                content="${content:0:pos}${byte}${content:$((pos+1))}"
                ;;
        esac
    done

    printf '%s' "$content"
}

# --- Main loop ---

CRASHES=0

for ((i=1; i<=ITERATIONS; i++)); do
    RANDOM=$((SEED + i))

    roll=$((RANDOM % 100))
    if ((roll < 20)); then
        gen_random_bytes > "$INPUT_FILE"
    elif ((roll < 50)); then
        gen_token_soup > "$INPUT_FILE"
    elif ((roll < 60)); then
        gen_deep_nesting > "$INPUT_FILE"
    elif ((roll < 70)); then
        gen_malformed_string > "$INPUT_FILE"
    else
        gen_mutated_program > "$INPUT_FILE"
    fi

    set +e
    output=$(timeout "${TIMEOUT}s" "$COMPILER" "$INPUT_FILE" /dev/null --check-only 2>&1)
    exit_code=$?
    set -e

    # Classify result
    verdict="OK"
    if [ "$exit_code" -eq 101 ]; then
        verdict="ICE"
    elif [ "$exit_code" -eq 124 ]; then
        verdict="TIMEOUT"
    elif [ "$exit_code" -gt 128 ] 2>/dev/null; then
        verdict="SIGNAL_$((exit_code - 128))"
    elif echo "$output" | grep -q "FATAL" 2>/dev/null; then
        verdict="FATAL"
    fi

    if [ "$verdict" != "OK" ]; then
        if [ "$verdict" = "TIMEOUT" ] && [ "$IGNORE_TIMEOUTS" -eq 1 ]; then
            : # skip timeouts when --ignore-timeouts is set
        else
            cp "$INPUT_FILE" "$CRASH_DIR/crash_${i}.bl"
            echo "CRASH [$verdict] at iteration $i (seed=$SEED)" | tee -a "$CRASH_DIR/crash_log.txt"
            CRASHES=$((CRASHES + 1))
        fi
    fi

    if ((i % 100 == 0)); then
        echo "Progress: $i/$ITERATIONS ($CRASHES crashes)"
    fi
done

echo "Fuzz complete: $ITERATIONS iterations, $CRASHES crashes (seed=$SEED)"
if [ "$CRASHES" -gt 0 ]; then
    echo "Crash inputs saved to $CRASH_DIR/"
    exit 1
fi
