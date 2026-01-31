# Koka Incremental Compilation Cache Issue

## Summary

During investigation of an apparent "nested loop break bug" in the e3 interpreter, we discovered that the actual cause was stale artifacts in Koka's incremental compilation cache (`.koka/` directory). The interpreter was behaving incorrectly due to cached compilation artifacts that didn't reflect the current source code.

## Symptoms

- Certain programs would hang indefinitely (appearing as infinite loops)
- The same source code would sometimes work and sometimes fail
- Adding debug `println` statements would "fix" the bug (by forcing recompilation)
- Behavior was inconsistent across runs

## Root Cause

Koka uses incremental compilation with cached artifacts stored in `.koka/v3.2.2/gcc-{debug,drelease}-*/`. When source files change, Koka should detect this and recompile, but in some cases:

1. The cache may not properly invalidate when dependencies change
2. Interface files (`.kki`) may become stale
3. The build warning "interface src/peg found but no corresponding source module" suggests module resolution issues

## Evidence

1. Programs that hung would work correctly after:
   - Adding any `println` statement (forces recompilation)
   - Deleting `.koka/` directory
   - Running `koka --compile` on dependencies first

2. The build consistently shows:
   ```
   (1, 0): build warning: interface src/peg found but no corresponding source module
   ```
   This warning indicates potential cache/module resolution issues.

## Recommendations

### Immediate Mitigations

1. **Clean builds for testing**: Add `rm -rf .koka/` before critical test runs
2. **Explicit dependency compilation**: Always run `koka --compile src/peg.koka` before compiling dependent modules
3. **Makefile updates**: Consider adding cache-clearing targets or dependencies

### Investigation Steps

1. **Reproduce reliably**: 
   - Save the exact `.koka/` directory state when bug occurs
   - Compare with working state using `diff -r`

2. **Check file timestamps**:
   ```bash
   find .koka -name "*.kki" -newer src/e3peg.koka
   ```

3. **Monitor cache behavior**:
   - Add verbose logging to track when Koka decides to recompile vs use cache
   - Check if `--rebuild` flag exists and helps

4. **Report to Koka maintainers**:
   - The "interface found but no corresponding source module" warning
   - Steps to reproduce the stale cache issue
   - Koka version: v3.2.2

### Makefile Improvements

Consider adding:
```makefile
clean-koka:
	rm -rf .koka/

# Add as dependency to critical targets
src/e3peg: clean-koka src/e3peg.koka ...
```

Or a less aggressive approach:
```makefile
# Force recompile of PEG module before dependents
src/e3peg: src/peg.koka src/e3peg.koka
	$(KOKA) --compile src/peg.koka
	$(KOKA) -o $@ src/e3peg.koka
```

## Impact

This issue caused significant debugging time investigating a non-existent bug. The e3 interpreter's nested loop handling is actually correct - the apparent bug was entirely due to stale cached artifacts.

## Date

2026-01-31
