#!/bin/bash
# Differential fuzzing driver for e3 (see docs/FUZZING.md)
#
# Generates random e3 programs with efuzz (level 3) and runs them on e3peg
# (the only e3 implementation; e4peg cannot parse guard-style case, see
# DESIGN.md "Superset deviations"). Compares the output against the
# generator's co-evaluated expectation, then runs the bidirectional
# enforce-mode oracle: a clean program must not trip --enforce, and a
# program whose co-evaluation triggered an erroneous construct must halt
# with a Violation of exactly that kind.
set -u

EFUZZ="$1"
E3PEG="$2"
shift 2

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

# Program output lines: integers and booleans (e3 prints true/false)
run_filtered() {
    timeout 10 "$@" 2>/dev/null | grep -E '^-?[0-9]+$|^true$|^false$'
    return 0
}

for ((seed = SEED0; seed < SEED0 + COUNT; seed++)); do
    prog="$TMP/prog.e3"
    if ! timeout 30 "$EFUZZ" "$seed" "$SIZE" 3 "$MUTATE" > "$prog"; then
        echo "FAIL seed=$seed: generator error"
        fail=$((fail + 1))
        continue
    fi
    expected=$(sed -n 's|^// expect: ||p' "$prog")

    run_filtered "$E3PEG" "$prog" > "$TMP/out_e3peg"

    mismatches=""
    if [ "$(cat "$TMP/out_e3peg")" != "$expected" ]; then
        mismatches="$mismatches e3peg"
    fi

    viol=$(sed -n 's|^// violations: ||p' "$prog")
    enforce_raw=$(timeout 10 "$E3PEG" --enforce "$prog" 2>/dev/null)
    if [ "$viol" = "none" ]; then
        if echo "$enforce_raw" | grep -q "^Violation"; then
            mismatches="$mismatches e3peg-enforce(spurious-violation)"
        elif [ "$(echo "$enforce_raw" | grep -E '^-?[0-9]+$|^true$|^false$')" != "$expected" ]; then
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
        cp "$prog" "$OUTDIR/e3_seed_$seed.e3"
        cp "$TMP/out_e3peg" "$OUTDIR/e3_seed_${seed}_e3peg.out"
        echo "  program and outputs saved to $OUTDIR/e3_seed_$seed*"
    fi
done

echo ""
echo "efuzz e3 diff: $pass passed, $fail failed (seeds $SEED0..$((SEED0 + COUNT - 1)), size $SIZE)"
[ $fail -eq 0 ]
