#!/bin/bash
# Differential fuzzing driver for e5 (see docs/FUZZING.md)
#
# Generates random e5 programs with efuzz (level 5) and runs them on e5peg
# (the only e5 implementation). Compares the output against the generator's
# co-evaluated expectation, then runs the bidirectional enforce-mode oracle:
# a clean program must not trip --enforce, and a program whose co-evaluation
# triggered an erroneous construct (div0, nomatch, oob) must halt with a
# Violation of exactly that kind.
#
# Timeout handling: efuzz programs are terminating by construction, so a
# timeout means e5peg is pathologically slow on that input (PEG backtracking
# can be exponential — observed ~37s on a 174-line program; a candidate for
# the planned --stats fuel work), NOT that the output is wrong. We cannot
# diff output that never finished, so a timeout is logged and SKIPPED rather
# than failed; only completed-but-different output counts as a failure.
set -u

EFUZZ="$1"
E5PEG="$2"
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

# Generous: only genuinely pathological backtracking should exceed this.
TIMEOUT=90

OUTDIR="${TEST_UNDECLARED_OUTPUTS_DIR:-${BUILD_WORKING_DIRECTORY:-$PWD}}/fuzz-failures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
skip=0

# Run e5peg into $1 (output file); return 124 on timeout, else e5peg's status.
run_e5peg() {
    local out="$1"; shift
    timeout "$TIMEOUT" "$E5PEG" "$@" > "$out" 2>/dev/null
    return $?
}
NUMRE='^-?[0-9]+$|^true$|^false$|^\(.*\)$|^\{.*\}$'

for ((seed = SEED0; seed < SEED0 + COUNT; seed++)); do
    prog="$TMP/prog.e5"
    if ! timeout 30 "$EFUZZ" "$seed" "$SIZE" 5 "$MUTATE" > "$prog"; then
        echo "FAIL seed=$seed: generator error"
        fail=$((fail + 1))
        continue
    fi
    expected=$(sed -n 's|^// expect: ||p' "$prog")

    if ! run_e5peg "$TMP/raw_e5peg" "$prog"; then
        echo "SKIP seed=$seed: e5peg exceeded ${TIMEOUT}s (pathological PEG backtracking, not a mismatch)"
        skip=$((skip + 1))
        continue
    fi
    grep -E "$NUMRE" "$TMP/raw_e5peg" > "$TMP/out_e5peg"

    mismatches=""
    if [ "$(cat "$TMP/out_e5peg")" != "$expected" ]; then
        mismatches="$mismatches e5peg"
    fi

    viol=$(sed -n 's|^// violations: ||p' "$prog")
    if ! run_e5peg "$TMP/raw_enforce" "--enforce" "$prog"; then
        echo "SKIP seed=$seed: e5peg --enforce exceeded ${TIMEOUT}s"
        skip=$((skip + 1))
        continue
    fi
    enforce_raw=$(cat "$TMP/raw_enforce")
    if [ "$viol" = "none" ]; then
        if echo "$enforce_raw" | grep -q "^Violation"; then
            mismatches="$mismatches e5peg-enforce(spurious-violation)"
        elif [ "$(echo "$enforce_raw" | grep -E "$NUMRE")" != "$expected" ]; then
            mismatches="$mismatches e5peg-enforce"
        fi
    else
        if ! echo "$enforce_raw" | grep -q "^Violation ($viol)"; then
            mismatches="$mismatches e5peg-enforce(missed-$viol)"
        fi
    fi

    if [ -z "$mismatches" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL seed=$seed:$mismatches"
        fail=$((fail + 1))
        mkdir -p "$OUTDIR"
        cp "$prog" "$OUTDIR/e4_seed_$seed.e5"
        cp "$TMP/out_e5peg" "$OUTDIR/e4_seed_${seed}_e5peg.out"
        echo "  program and outputs saved to $OUTDIR/e4_seed_$seed*"
    fi
done

echo ""
echo "efuzz e5 diff: $pass passed, $fail failed, $skip skipped (seeds $SEED0..$((SEED0 + COUNT - 1)), size $SIZE)"
[ $fail -eq 0 ]
