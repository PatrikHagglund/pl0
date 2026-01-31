# PEG Parser Specification

A minimal PEG (Parsing Expression Grammar) interpreter in Koka.

## Grammar File Format

Grammar files (`.peg`) contain rules of the form:

```
name = expression
name = expression  @tag
name = expression  { inline_action }
```

### Expressions

| Syntax | Name | Semantics |
|--------|------|-----------|
| `"text"` | Literal | Match exact string |
| `.` | Any | Match any single character |
| `[abc]` | Class | Match any character in set |
| `[a-z]` | Range | Match character in range |
| `[^x]` | Negated | Match any character not in set |
| `e1 e2` | Sequence | Match e1 then e2 |
| `e1 / e2` | Choice | Try e1, if fails try e2 |
| `e*` | Star | Match e zero or more times |
| `e+` | Plus | Match e one or more times |
| `e?` | Optional | Match e zero or one time |
| `!e` | Not | Succeed if e fails (no consume) |
| `&e` | And | Succeed if e succeeds (no consume) |
| `(e)` | Group | Grouping |
| `name` | Rule | Reference another rule |
| `n:e` | Capture | Match e, name result as n |

### Whitespace and Comments

- Whitespace between tokens is ignored
- Comments: `// ...` to end of line

## Named Captures

Named captures bind sub-matches to names for use in actions:

```peg
binding = id:ident ":=" e:expression { Assign($id, $e) }
```

The capture name can be referenced as `$name` in inline actions.

## Inline Actions

Inline actions embed semantic expressions directly in the grammar:

```peg
int_lit = digit+ _ { Int($0) }
ident   = !keyword letter idchar* { Ident($0) }
binding = id:ident ":=" e:expression { Assign($id, $e) }
        / id:ident ":" { Decl($id) }
```

### Action Scope

**Inline actions apply to the entire preceding sequence in a choice alternative**, not just the immediately preceding element. This differs from suffix operators (`*`, `+`, `?`) which bind tightly to the preceding atom.

Examples:
```peg
// { Ident($0) } applies to entire sequence: !keyword letter idchar*
// $0 captures full matched text, e.g., "foo"
ident = !keyword letter idchar* { Ident($0) }

// { Add($l, $r) } applies to: l:product "+" _ r:sum_expr
sum_expr = l:product "+" _ r:sum_expr { Add($l, $r) }
         / product

// Each alternative has its own action
binding = id:ident ":=" e:expression { Assign($id, $e) }
        / id:ident ":" { Decl($id) }
```

For explicit grouping, use parentheses:
```peg
// Action applies only to grouped portion
rule = prefix (grouped part) { Action } suffix
```

### Inline Expression Language

| Syntax | Description |
|--------|-------------|
| `$0` | Matched text |
| `$name` | Named capture value |
| `123` | Integer literal |
| `"str"` | String literal |
| `fn(args)` | Function call (lowercase) |
| `Cons(args)` | Constructor (uppercase) |

### Built-in Handlers

The host language provides handlers for inline action results:

- `_text` - `$0` reference
- `_int` / `int` - integer parsing
- `_str` - string value
- `_cons` - constructor with tag name and arguments

Example handler (Koka):
```koka
fun default-action(name, txt, children, caps)
  if name == "_cons" then
    match txt
      "Assign" -> // handle Assign constructor
      "Int" -> // handle Int constructor
      ...
```

## Action Tags

Rules can have an optional `@tag` suffix for action lookup:

```peg
atom = int_lit / ident / "(" _ expression ")" _  @atom
```

- If `@tag` present, action is looked up by tag name
- If no tag, action is looked up by rule name
- Tags allow sharing actions between rules

**Note:** For rules with multiple alternatives, the tag must appear after the last alternative.

## API

### Types

```koka
type peg           // PEG expression AST
type ptree         // Parse result tree
alias rule         // (name, body, tag)
alias grammar      // list<rule>
alias captures<s>  // list<(string, s)> - named captures
alias action<s>    // (name, text, children, captures) -> s
```

### Functions

```koka
parse-peg(input: string): grammar
peg-parse(g, start, input): maybe<ptree>
peg-exec(g, acts, def, start, input): maybe<s>
peg-exec-partial(g, acts, def, start, input): maybe<(sslice, s)>
capture-get(caps, name): maybe<s>
```

## Example

Grammar with inline actions (`e1.peg`):
```peg
int_lit    = digit+ _ { Int($0) }
ident      = !keyword letter idchar* _ { Ident($0) }
binding    = id:ident _ ":=" _ e:expression { Assign($id, $e) }
           / id:ident _ ":" { Decl($id) }
print_stmt = "print" _ e:expression { Print($e) }
loop_stmt  = "loop" _ body:statement { Loop($body) }
```

## Implementation Notes

- Backtracking via Koka's `peg-fail` effect
- No left-recursion support (will loop infinitely)
- Memoization available via `*-memo` functions (parse-tree mode only, not semantic actions)
- Inline actions evaluated during `peg-exec*` calls
- Named captures collected from sequences for inline actions
- Single-element sequences pass through without wrapping (optimization)

### Nested List Handling

When using `*` with inline actions, each iteration's result may be wrapped in lists:
```peg
block = "{" _ (statement ";"? _)* "}" _ { Block }
```

The `(statement ";"? _)` sequence produces an `SVList` per iteration. The Block handler must flatten these nested structures to extract statements. This is inherent to how sequences collect children.

### Performance

The semantic-action interpreter (`peg-exec*`) is ~14% slower than a two-phase parse-then-execute approach. This overhead comes from:
- Creating closures/thunks during parsing
- Nested list wrapping from sequences
- No memoization (memoization is only implemented for parse-tree mode)

For compute-bound programs, this overhead is negligible since parsing happens once at startup.

## Future Considerations

**Fold syntax for repetition**: Currently, actions on `*` wrap all children in a constructor:
```peg
block = "{" _ (statement ";"? _)* "}" _ { Block }
```

A future extension could support explicit fold operations:
```peg
// Hypothetical syntax - not yet implemented
block = "{" _ (statement ";"? _)*<Seq, Empty> "}" _
```
Where `*<cons, nil>` folds with `cons(item, acc)` starting from `nil`, building:
`Seq(stmt1, Seq(stmt2, Seq(stmt3, Empty)))`

This would enable incremental/recursive handling of repetitions without collecting all children first.
