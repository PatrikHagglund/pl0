// PL/0 Level 1 Compiler to LLVM IR (C++23)
#include "pl0_1.hpp"
#include <unordered_set>

constexpr const char* INT = "i128";

void collect_vars(Stmt* s, std::unordered_set<std::string>& vars) {
    if (auto* d = dynamic_cast<DeclStmt*>(s)) vars.insert(d->name);
    else if (auto* a = dynamic_cast<AssignStmt*>(s)) vars.insert(a->name);
    else if (auto* b = dynamic_cast<BlockStmt*>(s)) for (auto& st : b->stmts) collect_vars(st.get(), vars);
    else if (auto* l = dynamic_cast<LoopStmt*>(s)) collect_vars(l->body.get(), vars);
}

struct CodeGen {
    int tmp = 0, lbl = 0;
    std::vector<int> exits;

    std::string fresh() { return std::format("%t{}", tmp++); }
    int label() { return lbl++; }

    std::string emit(Expr* e) {
        if (auto* n = dynamic_cast<NumberExpr*>(e)) return std::to_string(n->val);
        if (auto* v = dynamic_cast<VarExpr*>(e)) {
            auto t = fresh();
            std::println("  {} = load {}, ptr %{}", t, INT, v->name);
            return t;
        }
        if (auto* u = dynamic_cast<NegExpr*>(e)) {
            auto v = emit(u->e.get()), t = fresh();
            std::println("  {} = sub {} 0, {}", t, INT, v);
            return t;
        }
        if (auto* b = dynamic_cast<BinExpr*>(e)) {
            auto l = emit(b->l.get()), r = emit(b->r.get()), t = fresh();
            if (b->op == '+') std::println("  {} = add {} {}, {}", t, INT, l, r);
            else std::println("  {} = sub {} {}, {}", t, INT, l, r);
            return t;
        }
        return "0";
    }

    void emit(Stmt* s) {
        if (dynamic_cast<DeclStmt*>(s)) { /* already allocated */ }
        else if (auto* a = dynamic_cast<AssignStmt*>(s)) {
            std::println("  store {} {}, ptr %{}", INT, emit(a->e.get()), a->name);
        }
        else if (auto* b = dynamic_cast<BlockStmt*>(s)) for (auto& st : b->stmts) emit(st.get());
        else if (auto* l = dynamic_cast<LoopStmt*>(s)) {
            int head = label(), exit = label();
            exits.push_back(exit);
            std::println("  br label %L{}\nL{}:", head, head);
            emit(l->body.get());
            std::println("  br label %L{}\nL{}:", head, exit);
            exits.pop_back();
        }
        else if (auto* b = dynamic_cast<BreakIfzStmt*>(s)) {
            if (exits.empty()) { std::println(stderr, "Error: break_ifz outside loop"); return; }
            auto cond = emit(b->cond.get()), cmp = fresh();
            int cont = label();
            std::println("  {} = icmp eq {} {}, 0", cmp, INT, cond);
            std::println("  br i1 {}, label %L{}, label %L{}\nL{}:", cmp, exits.back(), cont, cont);
        }
        else if (auto* p = dynamic_cast<PrintStmt*>(s)) {
            auto v = emit(p->e.get());
            std::println("  call void @print_i128({} {})", INT, v);
        }
    }
};

int main(int argc, char** argv) {
    if (argc < 2) { std::println(stderr, "Usage: {} <file>", argv[0]); return 1; }
    std::string src = read_file(argv[1]);

    auto prog = parse_program(src);
    if (!prog) { std::println(stderr, "Error: {}", prog.error()); return 1; }

    // Emit runtime
    std::println("; PL/0 Level 1 compiled to LLVM IR\n");
    std::print("{}", read_file("src/pl0_1_rt.ll"));

    std::println("define i32 @main(i32 %argc, ptr %argv) {{\nentry:");

    std::unordered_set<std::string> vars;
    for (auto& s : *prog) collect_vars(s.get(), vars);
    vars.erase("arg1");
    vars.erase("arg2");
    for (auto& v : vars) std::println("  %{} = alloca {}\n  store {} 0, ptr %{}", v, INT, INT, v);

    // arg1 and arg2 via parse_arg helper
    std::println("  %arg1 = alloca {}", INT);
    std::println("  %arg1_val = call {} @parse_arg(i32 %argc, ptr %argv, i32 1)", INT);
    std::println("  store {} %arg1_val, ptr %arg1", INT);
    std::println("  %arg2 = alloca {}", INT);
    std::println("  %arg2_val = call {} @parse_arg(i32 %argc, ptr %argv, i32 2)", INT);
    std::println("  store {} %arg2_val, ptr %arg2", INT);

    CodeGen cg;
    for (auto& s : *prog) cg.emit(s.get());

    std::println("  ret i32 0\n}}");
}
