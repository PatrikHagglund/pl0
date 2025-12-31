// PL/0 Level 1 Interpreter (C++23)
#include "pl0_1.hpp"
#include <unordered_map>

using Int = __int128;
using Env = std::unordered_map<std::string, Int>;

Int eval(Expr* e, Env& env) {
    if (auto* n = dynamic_cast<NumberExpr*>(e)) return n->val;
    if (auto* v = dynamic_cast<VarExpr*>(e)) return env[v->name];
    if (auto* u = dynamic_cast<NegExpr*>(e)) return -eval(u->e.get(), env);
    if (auto* b = dynamic_cast<BinExpr*>(e)) {
        Int l = eval(b->l.get(), env), r = eval(b->r.get(), env);
        return b->op == '+' ? l + r : l - r;
    }
    return 0;
}

struct Break {};

void exec(Stmt* s, Env& env) {
    if (auto* d = dynamic_cast<DeclStmt*>(s)) env.try_emplace(d->name, 0);
    else if (auto* a = dynamic_cast<AssignStmt*>(s)) env[a->name] = eval(a->e.get(), env);
    else if (auto* b = dynamic_cast<BlockStmt*>(s)) for (auto& st : b->stmts) exec(st.get(), env);
    else if (auto* l = dynamic_cast<LoopStmt*>(s)) {
        try { while (true) exec(l->body.get(), env); } catch (Break) {}
    }
    else if (auto* b = dynamic_cast<BreakIfzStmt*>(s)) { if (eval(b->cond.get(), env) == 0) throw Break{}; }
    else if (auto* pr = dynamic_cast<PrintStmt*>(s)) {
        Int v = eval(pr->e.get(), env);
        if (v == 0) { std::println("0"); return; }
        char buf[50]; char* ptr = buf + 49; *ptr = 0;
        bool neg = v < 0; if (neg) v = -v;
        do { *--ptr = '0' + v % 10; v /= 10; } while (v);
        if (neg) *--ptr = '-';
        std::println("{}", ptr);
    }
}

int main(int argc, char** argv) {
    if (argc < 2) { std::println(stderr, "Usage: {} <file> [arg1] [arg2]", argv[0]); return 1; }
    std::string src = read_file(argv[1]);

    auto prog = parse_program(src);
    if (!prog) { std::println(stderr, "Error: {}", prog.error()); return 1; }

    Env env;
    env["arg1"] = argc > 2 ? std::atoll(argv[2]) : 0;
    env["arg2"] = argc > 3 ? std::atoll(argv[3]) : 0;

    for (auto& s : *prog) {
        try { exec(s.get(), env); }
        catch (Break) { std::println(stderr, "Error: break_ifz outside loop"); break; }
    }
}
