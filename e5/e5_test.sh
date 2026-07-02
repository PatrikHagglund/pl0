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

E5="$1"
EXAMPLES="$2"

TMP=$(mktemp --suffix=.e5)

# Inherited from e4: arithmetic, booleans, arrays, patterns, closures
echo 'print (2 + 3) * 4' > "$TMP"
check "paren_grouping" "$E5 $TMP" "20"

echo -e 'arr := (10; 20; 30;)\nprint arr.1' > "$TMP"
check "array_index" "$E5 $TMP" "20"

echo -e 'f := \\x -> x + 1\nprint f 5' > "$TMP"
check "closure" "$E5 $TMP" "6"

# Records
echo -e 'p := {x: 3, y: 4}\nprint p.x\nprint p.y' > "$TMP"
check "record_fields" "$E5 $TMP" "3 4"

echo 'print {x: 1, y: {z: 2}}' > "$TMP"
check "record_print_nested" "$E5 $TMP" "{x: 1, y: {z: 2}}"

# Record field assignment (functional update)
echo -e 'r := {x: 1, y: 2}\nr.x := 9\nprint r' > "$TMP"
check "record_field_set" "$E5 $TMP" "{x: 9, y: 2}"

# Value semantics: updating r does not affect an earlier copy s
echo -e 'r := {x: 1, y: 2}\ns := r\nr.x := 9\nprint s' > "$TMP"
check "record_set_value_semantics" "$E5 $TMP" "{x: 1, y: 2}"

# Nested record field assignment
echo -e 'r := {a: {b: 1}}\nr.a.b := 8\nprint r' > "$TMP"
check "record_set_nested" "$E5 $TMP" "{a: {b: 8}}"

# Mixed paths: record inside array, array inside record
echo -e 'a := ({x: 1}; {x: 2};)\na.1.x := 99\nprint a' > "$TMP"
check "record_in_array_set" "$E5 $TMP" "({x: 1}; {x: 99};)"

echo -e 'r := {xs: (1; 2; 3;)}\nr.xs (0) := 7\nprint r' > "$TMP"
check "array_in_record_set" "$E5 $TMP" "{xs: (7; 2; 3;)}"

# Array element assignment carried in from e4
echo -e 'a := (1; 2; 3;)\na.0 := 9\nprint a' > "$TMP"
check "array_set_at_e5" "$E5 $TMP" "(9; 2; 3;)"

# Assigning to a missing field is a type error (halts)
echo -e 'r := {x: 1}\nr.y := 9\nprint r' > "$TMP"
out=$(timeout $TIMEOUT "$E5" "$TMP" 2>&1)
if echo "$out" | grep -qF "Type error: no field 'y' in record assignment"; then
    echo "PASS record_set_missing_field"
    pass=$((pass+1))
else
    echo "FAIL record_set_missing_field"
    fail=$((fail+1))
fi

echo -e 'p := {x: 3, y: 4}\nprint case p { {x: a, y: b} -> a + b, _ -> 0 }' > "$TMP"
check "record_pattern" "$E5 $TMP" "7"

# Width subtyping: listed fields must match, extra fields allowed
echo -e 'p := {tag: 2, x: 9, y: 4}\nprint case p { {tag: 2, x: xv} -> xv, _ -> 0 }' > "$TMP"
check "record_pattern_subset" "$E5 $TMP" "9"

echo -e 'p := {x: 3}\nprint case p { {y: a} -> a, _ -> 99 }' > "$TMP"
check "record_pattern_missing_field" "$E5 $TMP" "99"

# Unit
echo -e 'u := ()\nprint u\nprint case u { () -> 1, _ -> 0 }' > "$TMP"
check "unit" "$E5 $TMP" "() 1"

# Type errors
echo -e 'p := {x: 1}\nprint p.zz\nprint 7' > "$TMP"
out=$(timeout $TIMEOUT "$E5" "$TMP" 2>&1)
if echo "$out" | grep -qF "Type error: no field 'zz' in record"; then
    echo "PASS missing_field_type_error"
    pass=$((pass+1))
else
    echo "FAIL missing_field_type_error"
    fail=$((fail+1))
fi

echo -e 'print {x: 1} == 3' > "$TMP"
out=$(timeout $TIMEOUT "$E5" "$TMP" 2>&1)
if echo "$out" | grep -qF "Type error: '==' on record and int"; then
    echo "PASS record_eq_type_error"
    pass=$((pass+1))
else
    echo "FAIL record_eq_type_error"
    fail=$((fail+1))
fi

# Example file
check "example_e5" "$E5 $EXAMPLES/example.e5" "0 0 () 30 0 {tag: 0, val: 0}"

rm -f "$TMP"

echo ""
echo "Results: $pass passed, $fail failed"
[ $fail -eq 0 ]
