# PEG Parser Specification

A minimal PEG (Parsing Expression Grammar) interpreter in Koka.

## Grammar File Format

Grammar files (`.peg`) contain rules of the form:

```
name = expression
name = expression  @tag
```

### Action Tags

Rules can have an optional `@tag` suffix that specifies which semantic action to use:

```peg
int_lit = digit+ _  @int
ident   = letter alnum* _  @ident
atom    = int_lit / ident  @atom
```

- If a tag is present, the action is looked up by tag name
- If no tag is present, the action is looked up by rule name
- Tags allow sharing actions between rules or using different action names

**Note:** For rules with multiple alternatives (`/`), the tag must appear after the last alternative:
```peg
// Correct: tag at end of entire rule
binding = ident ":=" expr
        / ident ":"  @binding

// Wrong: tag in middle of rule (will truncate the rule)
binding = ident ":=" expr  @binding
        / ident ":"
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

### Whitespace and Comments

- Whitespace between tokens is ignored
- Comments: `// ...` to end of line

## API

### Types

```koka
type peg           // PEG expression AST
type ptree         // Parse result tree
alias rule         // (name: string, body: peg, tag: maybe<string>)
alias grammar      // list<rule>
```

### Functions

```koka
parse-peg(input: string): grammar
// Parse a .peg file into a grammar

peg-parse(g: grammar, start: string, input: string): maybe<ptree>
// Parse input using grammar, starting at rule 'start'

ptree-text(t: ptree): string
// Get matched text from parse tree node

ptree-children(t: ptree): list<ptree>
// Get child nodes

ptree-find(t: ptree, name: string): list<ptree>
// Find all nodes matching rule name
```

## Parse Tree

Results are returned as `ptree`:

```koka
type ptree
  PNode(rule: string, children: list<ptree>, text: string)
  PLeaf(text: string)
```

- `PNode`: Named rule match with children and matched text
- `PLeaf`: Terminal match (literal, class, any)

## Example

Grammar (`arith.peg`):
```peg
expr   = term (("+" / "-") term)*
term   = factor (("*" / "/") factor)*
factor = [0-9]+ / "(" expr ")"
```

Usage:
```koka
val g = parse-peg(read-text-file("arith.peg".path))
match peg-parse(g, "expr", "1+2*3")
  Just(tree) -> tree.ptree-show
  Nothing -> println("parse failed")
```

## Memoized API

Packrat-style memoization for efficient backtracking:

```koka
alias memo-table  // Cache of (rule, position) → result

memo-new(): memo-table
// Create empty memo table

peg-parse-memo(g: grammar, start: string, input: string): maybe<ptree>
// Parse with fresh memo table (single parse)

peg-parse-partial-memo(g, start, input, memo, orig): (memo-table, maybe<(sslice, ptree)>)
// Parse with persistent memo table (for incremental parsing)
// Returns updated memo table for chaining
```

Usage for incremental parsing:
```koka
var memo := memo-new()
var input := source.slice
val orig = input  // Keep original for position calculation

while { !input.is-empty }
  val (m, result) = peg-parse-partial-memo(g, "statement", input, memo, orig)
  memo := m
  match result
    Just((rest, tree)) -> { process(tree); input := rest }
    Nothing -> break
```

## Semantic Actions API

Execute grammar with callbacks instead of building parse trees:

```koka
// Semantic value type (user-defined, polymorphic)
alias action<s> = (string, string, list<s>) -> s
// Called when rule matches: (action_name, matched_text, child_values) → value
// action_name is the @tag if present, otherwise the rule name

alias actions<s> = list<(string, action<s>)>
// Maps action names (tags or rule names) to actions

peg-exec(g: grammar, acts: actions<s>, def: action<s>, start: string, input: string): maybe<s>
// Parse and execute, return final semantic value

peg-exec-partial(g, acts, def, start, input): maybe<(sslice, s)>
// Partial parse with actions, returns remaining input
```

Usage:
```koka
type semval
  SVExpr(f: (env) -> int)
  SVStmt(f: (env) -> env)
  SVIdent(s: string)

fun act-int-lit(name: string, txt: string, children: list<semval>): semval
  SVExpr(fn(_) txt.trim.parse-int.default(0))

// Actions are looked up by @tag (if present) or rule name
val actions = [("int_lit", act-int-lit), ...]
val default = fn(_, _, cs) match cs { Cons(c, Nil) -> c; _ -> SVList(cs) }

match peg-exec-partial(g, actions, default, "expression", input)
  Just((rest, sv)) -> // sv is the semantic value
  Nothing -> // parse failed
```

## Implementation Notes

- Backtracking via Koka's `peg-fail` effect
- No left-recursion support (will loop infinitely)
- Memoization available via `*-memo` functions (packrat parsing)
- Semantic actions via `peg-exec*` functions (no parse tree built)
- Action tags (`@tag`) allow decoupling rule names from action names
- First rule is typically the start rule
