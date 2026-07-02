#!/bin/bash
# Differential fuzzing driver for e1 (see docs/FUZZING.md)
#
# Generates random e1 programs with efuzz and runs each on every e1
# implementation. Compares all outputs against the generator's co-evaluated
# expected output. The C++ compiler backend is only checked for emit success
# (compiling its output needs a host C++ compiler); the LLVM backend is
# executed via the hermetic lli JIT.
#
# NOTE: e2/e3/e4 PEG interpreters are not in the matrix: their grammars
# deliberately dropped break_ifz (replaced by case/break), so they cannot
# parse e1 programs with loops. See "Superset deviations" in docs/DESIGN.md.
set -u

EFUZZ="$1"
E1="$2"
E1_KOKA="$3"
E1PEG="$4"
E1_COMPILE="$5"
LLI="$6"
LLVM_LINK="$7"
RT_LL="$8"
BUILTINS="$9"
shift 9

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
    prog="$TMP/prog.e1"
    if ! timeout 30 "$EFUZZ" "$seed" "$SIZE" 1 "$MUTATE" > "$prog"; then
        echo "FAIL seed=$seed: generator error"
        fail=$((fail + 1))
        continue
    fi
    expected=$(sed -n 's|^// expect: ||p' "$prog")

    run_filtered "$E1" "$prog" > "$TMP/out_e1"
    run_filtered "$E1_KOKA" "$prog" > "$TMP/out_e1_koka"
    run_filtered "$E1PEG" "$prog" > "$TMP/out_e1peg"

    mismatches=""

    if "$E1_COMPILE" --llvm "$prog" > "$TMP/prog.ll" 2>/dev/null \
        && "$LLVM_LINK" -S "$RT_LL" "$TMP/prog.ll" -o "$TMP/linked.ll" 2>/dev/null; then
        run_filtered "$LLI" --extra-archive="$BUILTINS" "$TMP/linked.ll" > "$TMP/out_llvmjit"
    else
        mismatches="$mismatches llvmjit(compile-failed)"
        : > "$TMP/out_llvmjit"
    fi

    if ! "$E1_COMPILE" "$prog" > /dev/null 2>&1; then
        mismatches="$mismatches cpp-backend(emit-failed)"
    fi

    for name in e1 e1_koka e1peg llvmjit; do
        if [ "$(cat "$TMP/out_$name")" != "$expected" ]; then
            mismatches="$mismatches $name"
        fi
    done

    if [ -z "$mismatches" ]; then
        pass=$((pass + 1))
    else
        echo "FAIL seed=$seed:$mismatches"
        fail=$((fail + 1))
        mkdir -p "$OUTDIR"
        cp "$prog" "$OUTDIR/seed_$seed.e1"
        for name in e1 e1_koka e1peg llvmjit; do
            cp "$TMP/out_$name" "$OUTDIR/seed_${seed}_$name.out"
        done
        echo "  program and outputs saved to $OUTDIR/seed_$seed*"
    fi
done

echo ""
echo "efuzz e1 diff: $pass passed, $fail failed (seeds $SEED0..$((SEED0 + COUNT - 1)), size $SIZE)"
[ $fail -eq 0 ]
