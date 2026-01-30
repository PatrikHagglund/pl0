# E3 PEG Interpreter Issues

## Status: Work in Progress

The e3 PEG interpreter (`src/e3peg.koka`) has a critical bug that prevents correct handling of multiple variable/function definitions.

## Symptom

When multiple variables or functions are defined, all lookups return the last defined value:

```e3
f := 100
g := 5
print f   // Expected: 100, Actual: 5
print g   // Expected: 5, Actual: 5
```

Similarly for functions:
```e3
f := (x) -> x
g := (y) -> y + 1
print f 3   // Expected: 3, Actual: 4 (uses g's body)
```

## Root Cause

The `$0` metavariable in PEG semantic actions returns an empty string instead of the matched text.

In the grammar:
```peg
ident = !keyword letter idchar* { Ident($0) }
```

The `$0` should contain the matched identifier text (e.g., "f"), but it's empty. This causes all identifiers to be stored under the empty key `""` in the environment, so the last assignment overwrites all previous ones.

## Technical Details

The issue is in `src/peg.koka` in the `PAction` handler:

```koka
PAction(p1, iact) ->
  val (s1, caps, result) = peg-exec-match-with-caps(g, acts, def, p1, s)
  val txt = s.string.first(s.count - s1.count).string
  // txt is empty when it should contain matched text
```

The computation `s.string.first(s.count - s1.count).string` appears to return empty for certain patterns. This may be related to how `sslice` handles the `string` and `first` methods.

### Attempted Fixes

1. **Using `s.take(n)` instead of `s.string.first(n)`** - Same result
2. **Explicit captures (`txt:ident_text`)** - Captures also empty
3. **Separate rules for identifier text** - Still empty

### Why e2peg Works

The e2 interpreter doesn't have function application via juxtaposition, so it uses:
```peg
ident = !keyword letter idchar* _ { Ident($0) }
```

The trailing `_` (whitespace) somehow makes `$0` work correctly. However, adding trailing `_` to e3's `ident` rule breaks the `apply_expr` rule which needs to detect horizontal space between function and argument.

## Workarounds Considered

1. **Add trailing `_` to ident** - Breaks function application parsing
2. **Use captures instead of `$0`** - Captures are also empty
3. **Parse identifier text in action handler** - Would require access to original input position

## Next Steps

1. **Debug PEG parser `$0` handling**: Add instrumentation to understand why `s.string.first(n)` returns empty
   - Check if `s.count - s1.count` is 0
   - Check if `s.string` returns expected content for `sslice`

2. **Review Koka `sslice` semantics**: Verify that `sslice.string` returns slice content vs underlying string

3. **Consider alternative approaches**:
   - Pass matched text through a different mechanism
   - Store input position and extract text in action handler
   - Use a two-phase approach (parse tree then interpret)

4. **Test fix in isolation**: Create minimal test case for PEG parser `$0` behavior

## Files Involved

- `src/peg.koka` - PEG parser, `PAction` handler (line ~676)
- `src/e3peg.koka` - E3 interpreter
- `src/e3eval.peg` - E3 grammar

## Impact

- E3 interpreter is non-functional for programs with multiple definitions
- Single-definition programs work correctly
- Does not affect e0, e1, e2 interpreters (they don't use `apply_expr`)
