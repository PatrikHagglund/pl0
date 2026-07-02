#!/bin/bash
set -e

pass=0
fail=0
TIMEOUT=10

check() {
    name="$1"
    cmd="$2"
    expected="$3"

    actual=$(timeout $TIMEOUT bash -c "$cmd" 2>&1 | grep -E "^-?[0-9]+$|^true$|^false$|^\(.*\)$|^\{.*\}$" | tr '\n' ' ' | sed 's/ $//') || { echo "FAIL $name (timeout/error)"; fail=$((fail+1)); return; }
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

check_static_error() {
    name="$1"
    code="$2"
    expected_err="$3"
    echo -e "$code" > "$TMP"
    out=$(timeout $TIMEOUT "$E6" "$TMP" 2>&1)
    if echo "$out" | grep -qF "Static error: $expected_err"; then
        echo "PASS $name"
        pass=$((pass+1))
    else
        echo "FAIL $name"
        printf "  expected error: %s\n" "$expected_err"
        printf "  actual: %s\n" "$(echo "$out" | tail -2 | tr '\n' ' ')"
        fail=$((fail+1))
    fi
}

E6="$1"
EXAMPLES="$2"

TMP=$(mktemp --suffix=.e6)

# Well-typed programs run as at e5
echo -e 'type Point = {x: int, y: int}\np : Point = {x: 3, y: 4}\nprint p.x + p.y' > "$TMP"
check "type_alias_record" "$E6 $TMP" "7"

echo -e 'f := \\a: int, b: int -> a + b\nprint f (3) (4)' > "$TMP"
check "typed_lambda_curried" "$E6 $TMP" "7"

echo -e 'g : (int) -> bool = \\n: int -> n > 2\nprint g 5' > "$TMP"
check "func_type_ascription" "$E6 $TMP" "true"

echo -e 'arr : [int] = (1; 2; 3;)\nprint arr.1\nprint case arr { (a; _) -> a, _ -> 0 }' > "$TMP"
check "typed_array_pattern" "$E6 $TMP" "2 1"

echo -e 'u : unit\nprint u' > "$TMP"
check "unit_decl" "$E6 $TMP" "()"

echo -e 'x : int\nprint x' > "$TMP"
check "int_decl_default" "$E6 $TMP" "0"

# lvalue assignment (functional update), well-typed: runs
echo -e 'a : [int] = (1; 2; 3;)\na.0 := 9\nprint a' > "$TMP"
check "lval_array_set" "$E6 $TMP" "(9; 2; 3;)"

echo -e 'r : {x: int, y: int} = {x: 1, y: 2}\nr.x := 9\nprint r' > "$TMP"
check "lval_record_set" "$E6 $TMP" "{x: 9, y: 2}"

echo -e 'r : {a: {b: int}} = {a: {b: 1}}\nr.a.b := 8\nprint r' > "$TMP"
check "lval_nested_set" "$E6 $TMP" "{a: {b: 8}}"

echo -e 'a : [int] = (5; 6; 7;)\ni : int = 2\na (i) := 0\nprint a' > "$TMP"
check "lval_dynamic_index" "$E6 $TMP" "(5; 6; 0;)"

# lvalue assignment, ill-typed: rejected by the static checker
check_static_error "lval_wrong_elem_type" 'a : [int] = (1; 2;)\na.0 := true\nprint a' \
    "assignment to a component of 'a': expected int, got bool"
check_static_error "lval_missing_field" 'r : {x: int} = {x: 1}\nr.y := 9\nprint r' \
    "no field 'y' in {x: int}"
check_static_error "lval_index_non_array" 'x : int = 5\nx.0 := 9\nprint x' \
    "indexing a non-array (int) in assignment"
check_static_error "lval_dyn_index_bool" 'a : [int] = (1; 2;)\nb : bool = true\na (b) := 9\nprint a' \
    "array index: expected int, got bool"
check_static_error "lval_field_on_array" 'a : [int] = (1; 2;)\na.x := 9\nprint a' \
    "field assignment on [int]"

# Statements before a static error still execute; the bad one never does
echo -e 'print 5\nx : int = true\nprint 99' > "$TMP"
out=$(timeout $TIMEOUT "$E6" "$TMP" 2>&1)
if echo "$out" | grep -q "^5$" && echo "$out" | grep -q "Static error" && ! echo "$out" | grep -q "^99$"; then
    echo "PASS error_halts_before_stmt"
    pass=$((pass+1))
else
    echo "FAIL error_halts_before_stmt"
    fail=$((fail+1))
fi

# Static rejections
check_static_error "bad_init" 'x : int = true' "initializer of 'x': expected int, got bool"
check_static_error "cmp_as_int" 'print (1 < 2) + 3' "left operand of '+': expected int, got bool"
check_static_error "unbound_static" 'print zzz' "undeclared variable 'zzz'"
check_static_error "heterogeneous_array" 'a := (1; true;)' "array element: expected int, got bool"
check_static_error "record_width" 'type P = {x: int}\np : P = {x: 1, y: 2}' "initializer of 'p': expected {x: int}, got {x: int, y: int}"
check_static_error "missing_field" 'p := {x: 1}\nprint p.y' "no field 'y' in {x: int}"
check_static_error "reassign_other_type" 'x := 5\nx := true' "assigning bool to 'x' of type int"
check_static_error "case_arm_types" 'print case 5 { 1 -> 10, _ -> false }' "case arms have different types: int and bool"
check_static_error "unknown_type" 'x : Foo = 1' "unknown type 'Foo'"
check_static_error "decl_no_default" 'p : {x: int}' "'p: {x: int}' needs an initializer"

# Example file
check "example_e6" "$E6 $EXAMPLES/example.e6" "0 18"

rm -f "$TMP"

echo ""
echo "Results: $pass passed, $fail failed"
[ $fail -eq 0 ]
