#!/bin/bash
set -e

pass=0
fail=0

check() {
    name="$1"
    cmd="$2"
    expected="$3"
    
    actual=$(eval "$cmd" 2>&1 | grep -E "^-?[0-9]+$") || { echo "FAIL $name (error)"; fail=$((fail+1)); return; }
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

E1="$1"
E1_COMPILE="$2"
E0_EXAMPLES="$3"
EXAMPLES="$4"

# Test interpreter
check "example_e0 interp" "$E1 $E0_EXAMPLES/example.e0" "$(printf '7\n1\n8')"
check "factorial interp" "$E1 $EXAMPLES/factorial.e1 1 5" "120"
check "collatz interp" "$E1 $EXAMPLES/collatz.e1 5" "$(printf '5\n16\n8\n4\n2\n1')"
check "gcd interp" "$E1 $EXAMPLES/gcd.e1 48 18" "6"

echo ""
echo "Results: $pass passed, $fail failed"
[ $fail -eq 0 ]
