#!/bin/bash
# Delta-debugging reducer for efuzz failures (see docs/FUZZING.md).
#
# Given a failing (seed, size, level, mutate), shrinks the program to a
# minimal subset of top-level body statements that still fails, by greedily
# dropping statements and re-checking. efuzz regenerates the program from the
# seed with a "keep" mask and RE-CO-EVALUATES it, so the // expect: oracle is
# always correct for the reduced program (no stale expectations).
#
# Interestingness (a program "fails") = the interpreter's output differs from
# the program's co-evaluated // expect:, OR the interpreter times out/crashes.
# For self-testing the reducer itself, set REDUCE_GREP=<regex>: a program is
# then "interesting" iff its // expect: output matches the regex (no
# interpreter needed) — used to validate the ddmin loop deterministically.
set -u

EFUZZ="$1"
INTERP="$2"
LEVEL="$3"
shift 3

SEED=1
SIZE=20
MUTATE=0
if [ "${1:-}" = "--" ]; then
    shift
    SEED=${1:-1}
    SIZE=${2:-20}
    MUTATE=${3:-0}
fi

ITIMEOUT=90
NUMRE='^-?[0-9]+$|^true$|^false$|^\(.*\)$'
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Generate the program for a keep mask ("all", "none", or "0,2,5") into $TMP/p.
gen() {
    "$EFUZZ" "$SEED" "$SIZE" "$LEVEL" "$MUTATE" "$1" > "$TMP/p" 2>/dev/null
}

# Is the current $TMP/p program "interesting" (i.e. a failure)?
interesting() {
    if [ -n "${REDUCE_GREP:-}" ]; then
        sed -n 's|^// expect: ||p' "$TMP/p" | grep -qE "$REDUCE_GREP"
        return $?
    fi
    local expected actual rc
    expected=$(sed -n 's|^// expect: ||p' "$TMP/p")
    timeout "$ITIMEOUT" "$INTERP" "$TMP/p" > "$TMP/o" 2>/dev/null
    rc=$?
    [ $rc -eq 124 ] && return 0          # timeout -> interesting
    [ $rc -gt 128 ] && return 0          # crash (signal) -> interesting
    actual=$(grep -E "$NUMRE" "$TMP/o")
    [ "$actual" != "$expected" ]         # value mismatch -> interesting
}

check() {  # gen <mask> then test; returns 0 if interesting
    gen "$1" || return 1
    interesting
}

gen all || { echo "reduce: efuzz failed to generate seed $SEED"; exit 1; }
N=$(sed -n 's|^// stmts: ||p' "$TMP/p")
echo "reduce: seed=$SEED size=$SIZE level=$LEVEL mutate=$MUTATE, $N body statements"

# Build the initial full keep mask "0,1,...,N-1".
if [ "$N" -le 0 ]; then keep="none"; else keep=$(seq -s, 0 $((N - 1))); fi

if ! check "$keep"; then
    echo "reduce: full program is NOT interesting (it passes) — nothing to reduce"
    exit 0
fi

# Greedy minimization: repeatedly try dropping one kept statement; commit any
# drop that preserves interestingness; restart until a full pass drops nothing.
changed=1
while [ $changed -eq 1 ]; do
    changed=0
    IFS=, read -ra idxs <<< "$keep"
    for idx in "${idxs[@]}"; do
        cand=$(echo "$keep" | tr ',' '\n' | grep -vx "$idx" | paste -sd,)
        [ -z "$cand" ] && cand="none"
        if check "$cand"; then
            keep="$cand"
            changed=1
            break
        fi
    done
done

kept_count=$([ "$keep" = "none" ] && echo 0 || echo "$keep" | tr ',' '\n' | grep -c .)
echo "reduce: minimized $N -> $kept_count body statements (keep=$keep)"
echo "=== minimal failing program ==="
gen "$keep"
cat "$TMP/p"
