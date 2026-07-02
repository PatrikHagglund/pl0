#!/bin/bash
# Run PEG tests and check for failures
set -e
OUTPUT=$(./shared/peg_test_bin 2>&1)
echo "$OUTPUT"
# Check for any failures (✗)
if echo "$OUTPUT" | grep -q "✗"; then
    exit 1
fi
