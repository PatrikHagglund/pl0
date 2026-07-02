#!/bin/bash
set -e

pass=0
fail=0
TIMEOUT=5

check() {
    name="$1"
    cmd="$2"
    expected="$3"
    
    actual=$(timeout $TIMEOUT bash -c "$cmd" 2>&1 | grep -E "^-?[0-9]+$|^true$|^false$|^\(.*\)$" | tr '\n' ' ' | sed 's/ $//') || { echo "FAIL $name (timeout/error)"; fail=$((fail+1)); return; }
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

E4="$1"
EXAMPLES="$2"

TMP=$(mktemp --suffix=.e4)

# Basic arithmetic (inherited from e3)
echo 'print 2 + 3 * 4' > "$TMP"
check "basic_arith" "$E4 $TMP" "14"

echo 'print 5 > 3' > "$TMP"
check "comparison" "$E4 $TMP" "true"

echo 'print true && false' > "$TMP"
check "boolean_and" "$E4 $TMP" "false"

# Array literals
echo 'print (1; 2; 3;)' > "$TMP"
check "array_literal" "$E4 $TMP" "(1; 2; 3;)"

echo 'print ()' > "$TMP"
check "unit_literal" "$E4 $TMP" "()"

# Array indexing - dot syntax
echo -e 'arr := (10; 20; 30;)\nprint arr.0' > "$TMP"
check "dot_index_0" "$E4 $TMP" "10"

echo -e 'arr := (10; 20; 30;)\nprint arr.1' > "$TMP"
check "dot_index_1" "$E4 $TMP" "20"

echo -e 'arr := (10; 20; 30;)\nprint arr.2' > "$TMP"
check "dot_index_2" "$E4 $TMP" "30"

# Array indexing - juxtaposition
echo -e 'arr := (10; 20; 30;)\ni := 1\nprint arr i' > "$TMP"
check "juxt_index" "$E4 $TMP" "20"

# Out of bounds returns 0
echo -e 'arr := (10; 20; 30;)\nprint arr.99' > "$TMP"
check "oob_index" "$E4 $TMP" "0"

# Array element assignment (functional update)
echo -e 'a := (10; 20; 30;)\na.0 := 99\nprint a' > "$TMP"
check "arr_set_literal" "$E4 $TMP" "(99; 20; 30;)"

echo -e 'a := (10; 20; 30;)\ni := 2\na (i) := 7\nprint a' > "$TMP"
check "arr_set_dynamic" "$E4 $TMP" "(10; 20; 7;)"

# Value semantics: updating a does not affect an earlier copy b
echo -e 'a := (1; 2;)\nb := a\na.0 := 9\nprint b' > "$TMP"
check "arr_set_value_semantics" "$E4 $TMP" "(1; 2;)"

# Nested update via a chained path
echo -e 'a := ((1; 2;); (3; 4;);)\na.0 (1) := 8\nprint a' > "$TMP"
check "arr_set_nested" "$E4 $TMP" "((1; 8;); (3; 4;);)"

# Out-of-bounds assignment is erroneous (kind oob): fallback leaves it unchanged
echo -e 'a := (1; 2;)\na.5 := 9\nprint a\nprint 7' > "$TMP"
check "arr_set_oob_fallback" "$E4 $TMP" "(1; 2;) 7"
check "arr_set_oob_enforce" "$E4 --enforce $TMP" ""

# Assigning into a non-array index is a type error (halts)
echo -e 'x := 5\nx.0 := 9\nprint x' > "$TMP"
out=$(timeout $TIMEOUT "$E4" "$TMP" 2>&1)
if echo "$out" | grep -qF "Type error: indexing int in assignment"; then
    echo "PASS arr_set_type_error"
    pass=$((pass+1))
else
    echo "FAIL arr_set_type_error"
    fail=$((fail+1))
fi

# Pattern matching - wildcard
echo -e 'x := 5\nprint case x { _ -> 42 }' > "$TMP"
check "pat_wildcard" "$E4 $TMP" "42"

# Pattern matching - variable binding
echo -e 'x := 5\nprint case x { n -> n + 1 }' > "$TMP"
check "pat_var" "$E4 $TMP" "6"

# Pattern matching - literal
echo -e 'x := 5\nprint case x { 5 -> 100, _ -> 0 }' > "$TMP"
check "pat_lit_match" "$E4 $TMP" "100"

echo -e 'x := 3\nprint case x { 5 -> 100, _ -> 0 }' > "$TMP"
check "pat_lit_nomatch" "$E4 $TMP" "0"

# Pattern matching - array exact
echo -e 'arr := (1; 2;)\nprint case arr { (a; b;) -> a + b, _ -> 0 }' > "$TMP"
check "pat_array_exact" "$E4 $TMP" "3"

echo -e 'arr := (1; 2; 3;)\nprint case arr { (a; b;) -> a + b, _ -> 0 }' > "$TMP"
check "pat_array_exact_fail" "$E4 $TMP" "0"

# Pattern matching - array prefix (rest)
echo -e 'arr := (1; 2; 3;)\nprint case arr { (h; _) -> h, _ -> 0 }' > "$TMP"
check "pat_array_prefix" "$E4 $TMP" "1"

# Pattern matching - unit
echo -e 'u := ()\nprint case u { () -> 1, _ -> 0 }' > "$TMP"
check "pat_unit" "$E4 $TMP" "1"

# Closures (inherited from e3)
echo -e 'f := \\x -> x + 1\nprint f 5' > "$TMP"
check "closure" "$E4 $TMP" "6"

echo -e 'add := \\x -> \\y -> x + y\nprint add 3 4' > "$TMP"
check "closure_curry" "$E4 $TMP" "7"

# Example file
check "example_e4" "$E4 $EXAMPLES/example.e4" "10"

# Parenthesized expressions are grouping, not 1-element arrays
echo 'print (2 + 3) * 4' > "$TMP"
check "paren_grouping" "$E4 $TMP" "20"

echo 'print (7;)' > "$TMP"
check "one_elem_array" "$E4 $TMP" "(7;)"

# Type errors: ill-typed operations halt with a message (no silent defaults)
echo -e 'arr := (1; 2;)\nprint arr + 1' > "$TMP"
out=$(timeout $TIMEOUT "$E4" "$TMP" 2>&1)
if echo "$out" | grep -qF "Type error: '+' on array and int"; then
    echo "PASS array_in_arith"
    pass=$((pass+1))
else
    echo "FAIL array_in_arith"
    fail=$((fail+1))
fi

echo -e 'x := (3 < 5) + 1\nprint 99' > "$TMP"
check "type_error_halts" "$E4 $TMP" ""

# Erroneous constructs (E3_SPEC.md): out-of-bounds is erroneous (kind oob)
echo -e 'arr := (10; 20;)\nprint arr.5\nprint 7' > "$TMP"
check "oob_fallback" "$E4 $TMP" "0 7"
check "oob_enforce" "$E4 --enforce $TMP" ""

out=$(timeout $TIMEOUT "$E4" --erroneous=observe "$TMP" 2>&1)
if echo "$out" | grep -q "Violation (oob): index 5 out of bounds" \
    && echo "$out" | grep -q "^7$"; then
    echo "PASS oob_observe"
    pass=$((pass+1))
else
    echo "FAIL oob_observe"
    fail=$((fail+1))
fi

rm -f "$TMP"

echo ""
echo "Results: $pass passed, $fail failed"
[ $fail -eq 0 ]
