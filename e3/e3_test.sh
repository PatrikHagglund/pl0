#!/bin/bash
set -e

pass=0
fail=0
TIMEOUT=5

check() {
    name="$1"
    cmd="$2"
    expected="$3"
    
    actual=$(timeout $TIMEOUT bash -c "$cmd" 2>&1 | grep -E "^-?[0-9]+$|^true$|^false$" | tr '\n' ' ' | sed 's/ $//') || { echo "FAIL $name (timeout/error)"; fail=$((fail+1)); return; }
    if [ "$actual" = "$expected" ]; then
        echo "PASS $name"
        pass=$((pass+1))
    else
        echo "FAIL $name"
        printf "  expected: %s\n" "$expected"
        printf "  actual: %s\n" "$actual"
        fail=$((fail+1))
    fi
}

run_e3() {
    local code="$1"
    shift
    local tmp=$(mktemp --suffix=.e3)
    echo -e "$code" > "$tmp"
    "$E3" "$tmp" "$@"
    rm -f "$tmp"
}

E3="$1"
EXAMPLES="$2"

# Basic arithmetic
check "factorial" "$E3 $EXAMPLES/factorial.e3 1 5" "120"
check "gcd" "$E3 $EXAMPLES/gcd.e3 48 18" "6"
check "collatz" "$E3 $EXAMPLES/collatz.e3 5" "5 16 8 4 2 1"

# Inline tests using temp files
TMP=$(mktemp --suffix=.e3)

echo 'print 2 + 3 * 4' > "$TMP"
check "basic_arith" "$E3 $TMP" "14"

echo 'print 5 > 3' > "$TMP"
check "comparison" "$E3 $TMP" "true"

echo 'print true && false' > "$TMP"
check "boolean_and" "$E3 $TMP" "false"

echo 'print true || false' > "$TMP"
check "boolean_or" "$E3 $TMP" "true"

echo 'print -5 + 10' > "$TMP"
check "negation" "$E3 $TMP" "5"

echo -e 'x := 5\nprint case { x > 3 -> 1, true -> 0 }' > "$TMP"
check "case_expr" "$E3 $TMP" "1"

echo -e 'x := 2\ncase { x == 1 -> { print 10 } x == 2 -> { print 20 } true -> { print 0 } }' > "$TMP"
check "case_stmt" "$E3 $TMP" "20"

echo -e 'i := 3\nloop { case { i == 0 -> { break } true -> { print i\n i := i - 1 } } }' > "$TMP"
check "loop_break" "$E3 $TMP" "3 2 1"

echo -e 'f := \\x -> x + 1\nprint f 5' > "$TMP"
check "closure" "$E3 $TMP" "6"

echo -e 'add := \\x -> \\y -> x + y\nprint add 3 4' > "$TMP"
check "closure_curry" "$E3 $TMP" "7"

# Type errors: ill-typed operations halt with a message (no silent defaults)
check_type_error() {
    name="$1"
    code="$2"
    expected_err="$3"
    echo -e "$code" > "$TMP"
    out=$(timeout $TIMEOUT "$E3" "$TMP" 2>&1)
    if echo "$out" | grep -qF "$expected_err"; then
        echo "PASS $name"
        pass=$((pass+1))
    else
        echo "FAIL $name"
        printf "  expected error: %s\n" "$expected_err"
        printf "  actual output: %s\n" "$(echo "$out" | tail -2 | tr '\n' ' ')"
        fail=$((fail+1))
    fi
}

check_type_error "bool_in_arith" 'print (3 < 5) + 1' "Type error: '+' on bool and int"
check_type_error "not_on_int" 'print !3' "Type error: '!' on int"
check_type_error "neg_on_bool" 'print -true' "Type error: unary '-' on bool"
check_type_error "apply_non_closure" 'x := 5\nprint x 3' "Type error: applying a non-closure (int)"

echo 'print (1 < 2) == (3 < 4)' > "$TMP"
check "bool_equality" "$E3 $TMP" "true"

# Short-circuit: the right operand (a type error) must not be evaluated
echo 'print false && (1 + true)' > "$TMP"
check "and_short_circuit" "$E3 $TMP" "false"

echo 'print true || (1 + true)' > "$TMP"
check "or_short_circuit" "$E3 $TMP" "true"

echo -e 'x := (3 < 5) + 1\nprint 99' > "$TMP"
check "type_error_halts" "$E3 $TMP" ""

# Erroneous constructs (E3_SPEC.md): fallback / observe / enforce modes
echo -e 'print 1 / 0\nprint xyz\nprint 7' > "$TMP"
check "erroneous_fallback" "$E3 $TMP" "0 0 7"
check "erroneous_enforce" "$E3 --enforce $TMP" ""

out=$(timeout $TIMEOUT "$E3" --erroneous=observe "$TMP" 2>&1)
if echo "$out" | grep -q "Violation (div0): division by zero" \
    && echo "$out" | grep -q "Violation (unbound)" \
    && echo "$out" | grep -q "^7$"; then
    echo "PASS erroneous_observe"
    pass=$((pass+1))
else
    echo "FAIL erroneous_observe"
    fail=$((fail+1))
fi

# Per-kind override: unbound falls back (prints 0), then div0 enforces (halt)
echo -e 'print xyz\nprint 1 / 0\nprint 7' > "$TMP"
check "erroneous_per_kind" "$E3 --erroneous=enforce --erroneous:unbound=fallback $TMP" "0"

rm -f "$TMP"

echo ""
echo "Results: $pass passed, $fail failed"
[ $fail -eq 0 ]
