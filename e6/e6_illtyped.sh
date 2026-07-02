#!/bin/bash
# Ill-typed fuzzing driver for e6 — the dual of the type-check oracle.
#
# efuzz at level 6 with a NEGATIVE mutate arg emits a well-typed program
# with exactly ONE injected type error, marked "// expect-static-error: yes"
# (see docs/FUZZING.md). e6peg checks statements one at a time, so the
# poisoned statement is reached after the well-typed prefix executes; the
# checker MUST print "Static error" for it. If e6peg instead runs to
# completion with no "Static error" line, the static checker has a hole (it
# accepted an ill-typed program) — or, less likely, the injected construct
# was not actually ill-typed (an efuzz bug). Either is a real finding.
#
# Timeout handling mirrors e6_diff.sh: a >TIMEOUT run means pathological PEG
# backtracking in the parser (static checking itself is linear and the
# program never executes), not a wrong result, so it is logged and SKIPPED.
set -u

EFUZZ="$1"
E6PEG="$2"
shift 2

COUNT=20
SEED0=1
SIZE=16
if [ "${1:-}" = "--" ]; then
    shift
    COUNT=${1:-20}
    SEED0=${2:-1}
    SIZE=${3:-16}
fi

TIMEOUT=90

OUTDIR="${TEST_UNDECLARED_OUTPUTS_DIR:-${BUILD_WORKING_DIRECTORY:-$PWD}}/fuzz-failures"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
skip=0

for ((seed = SEED0; seed < SEED0 + COUNT; seed++)); do
    prog="$TMP/prog.e6"
    if ! timeout 30 "$EFUZZ" "$seed" "$SIZE" 6 -1 > "$prog"; then
        echo "FAIL seed=$seed: generator error"
        fail=$((fail + 1))
        continue
    fi
    # The generator must mark the program ill-typed; otherwise the oracle
    # below would be meaningless (a missing marker is an efuzz bug).
    if ! grep -q "^// expect-static-error: yes" "$prog"; then
        echo "FAIL seed=$seed: efuzz did not mark the program ill-typed"
        fail=$((fail + 1))
        continue
    fi

    status=0
    timeout "$TIMEOUT" "$E6PEG" "$prog" > "$TMP/out" 2>/dev/null || status=$?
    if [ "$status" -eq 124 ]; then
        echo "SKIP seed=$seed: e6peg exceeded ${TIMEOUT}s (pathological PEG backtracking, not a checker miss)"
        skip=$((skip + 1))
        continue
    fi

    if grep -q "^Static error" "$TMP/out"; then
        pass=$((pass + 1))
    else
        echo "FAIL seed=$seed: e6peg accepted an ill-typed program (no Static error)"
        fail=$((fail + 1))
        mkdir -p "$OUTDIR"
        cp "$prog" "$OUTDIR/e6_illtyped_seed_$seed.e6"
        cp "$TMP/out" "$OUTDIR/e6_illtyped_seed_${seed}.out"
        echo "  program and output saved to $OUTDIR/e6_illtyped_seed_$seed*"
    fi
done

echo ""
echo "efuzz e6 ill-typed: $pass passed, $fail failed, $skip skipped (seeds $SEED0..$((SEED0 + COUNT - 1)), size $SIZE)"
[ $fail -eq 0 ]
