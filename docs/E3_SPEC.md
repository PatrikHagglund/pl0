# e3 Language Specification

## Overview

e3 extends e2 with:
- **Booleans** (`true`, `false`, `&&`, `||`, `!`)
- **Callables** (closures via `(params) -> expr`)
- **Case expressions** (in addition to case statements)
- **Function application** via juxtaposition

## Syntax

### Grammar (PEG)

```peg
program         = _ statement*
statement       = binding / case_stmt / loop_stmt / break_stmt / print_stmt / block / expression

block           = "{" _ (statement ";"? _)* "}" _
loop_stmt       = "loop" _ statement
break_stmt      = "break" _
print_stmt      = "print" _ expression
case_stmt       = "case" _ "{" _ stmt_arm+ "}" _
stmt_arm        = or_expr "->" _ statement

binding         = ident _ ":=" _ expression
                / ident _ ":"

expression      = case_expr / or_expr
case_expr       = "case" _ "{" _ expr_arm+ "}" _
expr_arm        = or_expr "->" _ or_expr ","? _

or_expr         = and_expr ("||" _ and_expr)*
and_expr        = not_expr ("&&" _ not_expr)*
not_expr        = "!" _ cmp_expr / cmp_expr

cmp_expr        = sum_expr (relop sum_expr)?
relop           = ("==" / "!=" / "<=" / ">=" / "<" / ">") _

sum_expr        = product (("+" / "-") _ product)*
product         = unary (("*" / "/" / "%") _ unary)*
unary           = "-" _ apply_expr / apply_expr

apply_expr      = atom (hs atom)*
atom            = int_lit / bool_lit / func_lit / ident / "(" _ expression ")" _ / block

int_lit         = digit+ _
bool_lit        = ("true" / "false") !idchar _
func_lit        = "(" _ params? ")" _ "->" _ expression
params          = ident _ ("," _ ident _)* ","? _

keyword         = ("case" / "loop" / "break" / "true" / "false" / "print") !idchar
ident           = !keyword letter idchar* _
idchar          = [a-zA-Z0-9_]
letter          = [a-zA-Z]
digit           = [0-9]

_               = ([ \t\n\r] / comment)*
__              = [ \t]+
comment         = "//" [^\n]* / "/*" (!"*/" .)* "*/"
```

## Types

| Type | Values | Operations |
|------|--------|------------|
| ℤ (integers) | ..., -1, 0, 1, ... | `+` `-` `*` `/` `%` |
| 𝔹 (booleans) | `true`, `false` | `&&` `\|\|` `!` |
| () → T (callables) | closures | application via juxtaposition |

Type bridge: relational operators `==` `!=` `<` `>` `<=` `>=` map ℤ × ℤ → 𝔹

## Semantics

### Callables

**Definition**: `(x, y) -> expr` creates a closure capturing the current environment.

**Application**: `f x` applies function `f` to argument `x`. Multi-argument: `f x y` is `(f x) y` (left-associative).

**Currying**: `(x, y) -> x + y` applied to one argument returns a closure awaiting the second.

### Case Expressions

```e3
result := case {
  x < 0  -> -1,
  x == 0 -> 0,
  true   -> 1
}
```

Evaluates arms top-to-bottom; returns value of first arm whose condition is truthy.

### Boolean Operations

- `&&` and `||` are short-circuiting
- `!` negates a boolean
- Integers in boolean context: 0 is falsy, non-zero is truthy

## Examples

### Higher-Order Function

```e3
twice := (f, x) -> f (f x)
inc := (n) -> n + 1
print twice inc 5  // 7
```

### Factorial

```e3
result := 1
n := arg1
loop {
  case { n == 0 -> break }
  result := result * n
  n := n - 1
}
print result
```

## Known Limitations

- No recursive closures (closure cannot reference itself by name)
