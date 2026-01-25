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
ident   = !keyword letter idchar* _ { Ident($0) }
binding = id:ident ":=" e:expression { Assign($id, $e) }
        / id:ident ":" { Decl($id) }
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

Grammar with inline actions (`pl0_1.peg`):
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
- Memoization available via `*-memo` functions
- Inline actions evaluated during `peg-exec*` calls
- Named captures collected from sequences for inline actions
