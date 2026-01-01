#!/bin/bash
# Compile PL/0 to LLVM IR, linking runtime if needed
# Usage: pl0-llvm.sh <source.pl0> [output.ll]
set -e
src="$1"
out="${2:-out.ll}"
[ -z "$src" ] && { echo "Usage: $0 <source.pl0> [output.ll]"; exit 1; }

dir="$(dirname "$0")/.."
./pl0_1_compile --llvm "$src" > /tmp/pl0_prog.ll
llvm-link /tmp/pl0_prog.ll "$dir/src/pl0_1_rt_bigint.bc" -S -o "$out" 2>/dev/null || cp /tmp/pl0_prog.ll "$out"
echo "Generated: $out"
