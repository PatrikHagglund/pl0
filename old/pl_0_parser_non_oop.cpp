// PL/0 Minimal Parser — matches pl0_minimal.ebnf

#include <iostream>
#include <string>
#include <vector>
#include <memory>
#include <expected>
#include <unordered_map>

// ---------- Tokens ----------

enum class TokenType {
    NUMBER, IDENT,
    ASSIGN,      // :=
    PLUS, MINUS, STAR, SLASH, PERCENT,
    LPAREN, RPAREN, LBRACE, RBRACE,
    SEMICOLON,
    END_OF_FILE
};

struct Token {
    TokenType type;
    std::string value;
};

// ---------- Lexer ----------

struct Lexer {
    std::string input;
    size_t pos = 0;
};

char peek(const Lexer& l) { return l.pos < l.input.size() ? l.input[l.pos] : '\0'; }
char get(Lexer& l) { return l.pos < l.input.size() ? l.input[l.pos++] : '\0'; }
void skip_ws(Lexer& l) { while (isspace(peek(l))) get(l); }

std::expected<Token, std::string> next_token(Lexer& l) {
    skip_ws(l);
    char c = peek(l);
    if (c == '\0') return Token{TokenType::END_OF_FILE, ""};
    if (isdigit(c)) {
        std::string num;
        while (isdigit(peek(l))) num += get(l);
        return Token{TokenType::NUMBER, num};
    }
    if (isalpha(c)) {
        std::string id;
        while (isalnum(peek(l))) id += get(l);
        return Token{TokenType::IDENT, id};
    }
    get(l);
    switch (c) {
        case ':': if (peek(l) == '=') { get(l); return Token{TokenType::ASSIGN, ":="}; }
                  return std::unexpected("Expected '=' after ':'");
        case '+': return Token{TokenType::PLUS, "+"};
        case '-': return Token{TokenType::MINUS, "-"};
        case '*': return Token{TokenType::STAR, "*"};
        case '/': return Token{TokenType::SLASH, "/"};
        case '%': return Token{TokenType::PERCENT, "%"};
        case '(': return Token{TokenType::LPAREN, "("};
        case ')': return Token{TokenType::RPAREN, ")"};
        case '{': return Token{TokenType::LBRACE, "{"};
        case '}': return Token{TokenType::RBRACE, "}"};
        case ';': return Token{TokenType::SEMICOLON, ";"};
    }
    return std::unexpected("Unknown character: " + std::string(1, c));
}

std::expected<std::vector<Token>, std::string> tokenize(const std::string& input) {
    Lexer l{input};
    std::vector<Token> tokens;
    while (true) {
        auto tok = next_token(l);
        if (!tok) return std::unexpected(tok.error());
        tokens.push_back(*tok);
        if (tok->type == TokenType::END_OF_FILE) break;
    }
    return tokens;
}

// ---------- AST ----------

struct Expr { virtual ~Expr() = default; virtual int eval(std::unordered_map<std::string, int>&) = 0; };
struct Stmt { virtual ~Stmt() = default; virtual void eval(std::unordered_map<std::string, int>&) = 0; };

struct NumberExpr : Expr {
    int val;
    NumberExpr(int v) : val(v) {}
    int eval(std::unordered_map<std::string, int>&) override { return val; }
};

struct VarExpr : Expr {
    std::string name;
    VarExpr(std::string n) : name(std::move(n)) {}
    int eval(std::unordered_map<std::string, int>& env) override { return env[name]; }
};

struct BinExpr : Expr {
    char op;
    std::unique_ptr<Expr> left, right;
    BinExpr(char o, std::unique_ptr<Expr> l, std::unique_ptr<Expr> r) : op(o), left(std::move(l)), right(std::move(r)) {}
    int eval(std::unordered_map<std::string, int>& env) override {
        int l = left->eval(env), r = right->eval(env);
        switch (op) {
            case '+': return l + r;
            case '-': return l - r;
            case '*': return l * r;
            case '/': return l / r;
            case '%': return l % r;
        }
        return 0;
    }
};

struct AssignStmt : Stmt {
    std::string name;
    std::unique_ptr<Expr> expr;
    AssignStmt(std::string n, std::unique_ptr<Expr> e) : name(std::move(n)), expr(std::move(e)) {}
    void eval(std::unordered_map<std::string, int>& env) override { env[name] = expr->eval(env); }
};

struct BlockStmt : Stmt {
    std::vector<std::unique_ptr<Stmt>> stmts;
    void eval(std::unordered_map<std::string, int>& env) override { for (auto& s : stmts) s->eval(env); }
};

// ---------- Parser ----------

struct Parser {
    std::vector<Token> tokens;
    size_t pos = 0;
    Token current() { return pos < tokens.size() ? tokens[pos] : Token{TokenType::END_OF_FILE, ""}; }
    void advance() { if (pos < tokens.size()) pos++; }
    bool match(TokenType t) { if (current().type == t) { advance(); return true; } return false; }
};

std::expected<std::unique_ptr<Expr>, std::string> parse_expr(Parser&);

std::expected<std::unique_ptr<Expr>, std::string> parse_factor(Parser& p) {
    if (p.current().type == TokenType::NUMBER) {
        int val = std::stoi(p.current().value);
        p.advance();
        return std::make_unique<NumberExpr>(val);
    }
    if (p.current().type == TokenType::IDENT) {
        std::string name = p.current().value;
        p.advance();
        return std::make_unique<VarExpr>(name);
    }
    if (p.match(TokenType::LPAREN)) {
        auto e = parse_expr(p);
        if (!e) return e;
        if (!p.match(TokenType::RPAREN)) return std::unexpected("Expected ')'");
        return e;
    }
    return std::unexpected("Expected factor");
}

std::expected<std::unique_ptr<Expr>, std::string> parse_term(Parser& p) {
    auto left = parse_factor(p);
    if (!left) return left;
    while (p.current().type == TokenType::STAR || p.current().type == TokenType::SLASH || p.current().type == TokenType::PERCENT) {
        char op = p.current().value[0];
        p.advance();
        auto right = parse_factor(p);
        if (!right) return right;
        left = std::make_unique<BinExpr>(op, std::move(*left), std::move(*right));
    }
    return left;
}

std::expected<std::unique_ptr<Expr>, std::string> parse_expr(Parser& p) {
    auto left = parse_term(p);
    if (!left) return left;
    while (p.current().type == TokenType::PLUS || p.current().type == TokenType::MINUS) {
        char op = p.current().value[0];
        p.advance();
        auto right = parse_term(p);
        if (!right) return right;
        left = std::make_unique<BinExpr>(op, std::move(*left), std::move(*right));
    }
    return left;
}

std::expected<std::unique_ptr<Stmt>, std::string> parse_stmt(Parser& p) {
    if (p.current().type == TokenType::IDENT) {
        std::string name = p.current().value;
        p.advance();
        if (!p.match(TokenType::ASSIGN)) return std::unexpected("Expected ':='");
        auto e = parse_expr(p);
        if (!e) return std::unexpected(e.error());
        return std::make_unique<AssignStmt>(name, std::move(*e));
    }
    if (p.match(TokenType::LBRACE)) {
        auto block = std::make_unique<BlockStmt>();
        while (!p.match(TokenType::RBRACE)) {
            auto s = parse_stmt(p);
            if (!s) return s;
            block->stmts.push_back(std::move(*s));
            p.match(TokenType::SEMICOLON);
        }
        return block;
    }
    return std::unexpected("Expected statement");
}

// ---------- Main ----------

int main() {
    std::string input = "{ x := 4; y := x + 2 * 3 }";

    auto tokens = tokenize(input);
    if (!tokens) { std::cerr << "Lexer error: " << tokens.error() << "\n"; return 1; }

    Parser p{*tokens};
    auto stmt = parse_stmt(p);
    if (!stmt) { std::cerr << "Parse error: " << stmt.error() << "\n"; return 1; }

    std::unordered_map<std::string, int> env;
    (*stmt)->eval(env);
    for (const auto& [k, v] : env) std::cout << k << " = " << v << "\n";
}
