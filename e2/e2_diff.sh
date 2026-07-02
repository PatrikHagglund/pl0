#!/bin/bash
# Differential fuzzing driver for e2 (see docs/FUZZING.md)
#
# Generates random e2 programs with efuzz (level 2) and runs each on e2peg
# and e3peg (e2 -> e3 is a true superset; e4peg is excluded because its
# case statement requires a scrutinee, see DESIGN.md "Superset deviations").
# Compares both outputs against the generator's co-evaluated expected output.
set -u

EFUZZ="$1"
E2PEG="$2"
E3PEG="$3"
shift 3

COUNT=20
SEED0=1
SIZE=20
MUTATE=0
if [ "${1:-}" = "--" ]; then
    shift
    COUNT=${1:-20}
    SEED0=${2:-1}
    SIZE=${3:-20}
    MUTATE=${4:-0}
fi

OUTDIR="${TEST_UNDECLARED_OUTPUTS_DIR:-${BUILD_WORKING_DIRECTORY:-$PWD}}/fuzz-failures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# Interpreters may print headers or errors; program output lines are integers.
run_filtered() {
    timeout 10 "$@" 2>/dev/null | grep -E '^-?[0-9]+$'
    return 0
}

for ((seed = SEED0; seed < SEED0 + COUNT; seed++)); do
    prog="$TMP/prog.e2"
    if ! timeout 30 "$EFUZZ" "$seed" "$SIZE" 2 "$MUTATE" > "$prog"; then
        echo "FAIL seed=$seed: generator error"
        fail=$((fail + 1))
        continue
    fi
    expected=$(sed -n 's|^// expect: ||p' "$prog")

    run_filtered "$E2PEG" "$prog" > "$TMP/out_e2peg"
    run_filtered "$E3PEG" "$prog" > "$TMP/out_e3peg"

    mismatches=""
    for name in e2peg e3peg; do
        if [ "$(cat "$TMP/out_$name")" != "$expected" ]; then
            mismatches="$mismatches $name"
        fi
    done

    # Enforce-mode oracle (bidirectional): the generator's co-evaluation
    # marks whether an erroneous construct fires (// violations: comment).
    # Clean programs must run under --enforce without tripping a violation;
    # div0 programs must make --enforce halt with "Violation (div0)".
    viol=$(sed -n 's|^// violations: ||p' "$prog")
    enforce_raw=$(timeout 10 "$E3PEG" --enforce "$prog" 2>/dev/null)
    if [ "$viol" = "none" ]; then
        if echo "$enforce_raw" | grep -q "^Violation"; then
            mismatches="$mismatches e3peg-enforce(spurious-violation)"
        elif [ "$(echo "$enforce_raw" | grep -E '^-?[0-9]+$')" != "$expected" ]; then
            mismatches="$mismatches e3peg-enforce"
        fi
    else
        if ! echo "$enforce_raw" | grep -q "^Violation ($viol)"; then
            mismatches="$mismatches e3peg-enforce(missed-$viol)"
        fi
    fi

    if [ -z "$mismatches" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL seed=$seed:$mismatches"
        fail=$((fail + 1))
        mkdir -p "$OUTDIR"
        cp "$prog" "$OUTDIR/e2_seed_$seed.e2"
        for name in e2peg e3peg; do
            cp "$TMP/out_$name" "$OUTDIR/e2_seed_${seed}_$name.out"
        done
        echo "  program and outputs saved to $OUTDIR/e2_seed_$seed*"
    fi
done

echo ""
echo "efuzz e2 diff: $pass passed, $fail failed (seeds $SEED0..$((SEED0 + COUNT - 1)), size $SIZE)"
[ $fail -eq 0 ]
