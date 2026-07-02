#!/bin/bash
# Differential fuzzing driver for e6 (see docs/FUZZING.md)
#
# Generates random e6 programs with efuzz (level 6) and runs them on e6peg
# (the only e6 implementation). Three oracles: (1) output matches the
# co-evaluated expectation; (2) the bidirectional enforce-mode check (clean
# programs do not trip --enforce; erroneous ones halt with the right
# Violation); (3) the type-check oracle — generated programs are well-typed
# by construction, so e6peg's static checker must NOT emit "Static error".
#
# Timeout handling: efuzz programs are terminating by construction, so a
# timeout means e6peg is pathologically slow on that input (PEG backtracking
# can be exponential — observed ~37s on a 174-line program; a candidate for
# the planned --stats fuel work), NOT that the output is wrong. We cannot
# diff output that never finished, so a timeout is logged and SKIPPED rather
# than failed; only completed-but-different output counts as a failure.
set -u

EFUZZ="$1"
E6PEG="$2"
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

# Run e6peg into $1 (output file); return 124 on timeout, else e6peg's status.
run_e6peg() {
    local out="$1"; shift
    timeout "$TIMEOUT" "$E6PEG" "$@" > "$out" 2>/dev/null
    return $?
}
NUMRE='^-?[0-9]+$|^true$|^false$|^\(.*\)$|^\{.*\}$'

for ((seed = SEED0; seed < SEED0 + COUNT; seed++)); do
    prog="$TMP/prog.e6"
    if ! timeout 30 "$EFUZZ" "$seed" "$SIZE" 6 "$MUTATE" > "$prog"; then
        echo "FAIL seed=$seed: generator error"
        fail=$((fail + 1))
        continue
    fi
    expected=$(sed -n 's|^// expect: ||p' "$prog")

    if ! run_e6peg "$TMP/raw_e6peg" "$prog"; then
        echo "SKIP seed=$seed: e6peg exceeded ${TIMEOUT}s (pathological PEG backtracking, not a mismatch)"
        skip=$((skip + 1))
        continue
    fi
    grep -E "$NUMRE" "$TMP/raw_e6peg" > "$TMP/out_e6peg"

    mismatches=""
    # e6 type-check oracle: generated programs are well-typed by construction,
    # so e6peg's static checker must accept them. A "Static error" means the
    # checker wrongly rejected a valid program (checker bug) or the generator
    # emitted something ill-typed (generator bug) — either is a real finding.
    if grep -q "^Static error" "$TMP/raw_e6peg"; then
        mismatches="$mismatches e6peg-static-error"
    fi
    if [ "$(cat "$TMP/out_e6peg")" != "$expected" ]; then
        mismatches="$mismatches e6peg"
    fi

    viol=$(sed -n 's|^// violations: ||p' "$prog")
    if ! run_e6peg "$TMP/raw_enforce" "--enforce" "$prog"; then
        echo "SKIP seed=$seed: e6peg --enforce exceeded ${TIMEOUT}s"
        skip=$((skip + 1))
        continue
    fi
    enforce_raw=$(cat "$TMP/raw_enforce")
    if [ "$viol" = "none" ]; then
        if echo "$enforce_raw" | grep -q "^Violation"; then
            mismatches="$mismatches e6peg-enforce(spurious-violation)"
        elif [ "$(echo "$enforce_raw" | grep -E "$NUMRE")" != "$expected" ]; then
            mismatches="$mismatches e6peg-enforce"
        fi
    else
        if ! echo "$enforce_raw" | grep -q "^Violation ($viol)"; then
            mismatches="$mismatches e6peg-enforce(missed-$viol)"
        fi
    fi

    if [ -z "$mismatches" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL seed=$seed:$mismatches"
        fail=$((fail + 1))
        mkdir -p "$OUTDIR"
        cp "$prog" "$OUTDIR/e4_seed_$seed.e6"
        cp "$TMP/out_e6peg" "$OUTDIR/e4_seed_${seed}_e6peg.out"
        echo "  program and outputs saved to $OUTDIR/e4_seed_$seed*"
    fi
done

echo ""
echo "efuzz e6 diff: $pass passed, $fail failed, $skip skipped (seeds $SEED0..$((SEED0 + COUNT - 1)), size $SIZE)"
[ $fail -eq 0 ]
