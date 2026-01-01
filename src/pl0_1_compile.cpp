// PL/0 Level 1 Compiler - C++ and LLVM IR backends
#include "pl0_1.hpp"
#include <unordered_set>
#include <cstring>

auto collect_vars(std::vector<StmtPtr>& prog) {
    std::unordered_set<std::string> vars;
    auto go = [&](auto&& go, Stmt* s) -> void {
        if (auto* d = dynamic_cast<DeclStmt*>(s)) vars.insert(d->name);
        else if (auto* a = dynamic_cast<AssignStmt*>(s)) vars.insert(a->name);
        else if (auto* b = dynamic_cast<BlockStmt*>(s))
            for (auto& x : b->stmts) go(go, x.get());
        else if (auto* l = dynamic_cast<LoopStmt*>(s)) go(go, l->body.get());
    };
    for (auto& s : prog) go(go, s.get());
    vars.erase("arg1"); vars.erase("arg2");
    return vars;
}

struct CppGen {
    int lbl = 0;
    std::vector<int> ex;

    void e(Expr* x) {
        if (auto* n = dynamic_cast<NumberExpr*>(x)) std::print("Int({})", n->val);
        else if (auto* v = dynamic_cast<VarExpr*>(x)) std::print("{}", v->name);
        else if (auto* u = dynamic_cast<NegExpr*>(x)) { std::print("-("); e(u->e.get()); std::print(")"); }
        else if (auto* b = dynamic_cast<BinExpr*>(x)) {
            std::print("("); e(b->l.get()); std::print(" {} ", b->op); e(b->r.get()); std::print(")");
        }
    }

    void s(Stmt* x, int d = 1) {
        auto ind = [d]{ for (int i = 0; i < d; i++) std::print("  "); };
        if (auto* a = dynamic_cast<AssignStmt*>(x)) {
            ind(); std::print("{} = ", a->name); e(a->e.get()); std::println(";");
        }
        else if (auto* b = dynamic_cast<BlockStmt*>(x))
            for (auto& t : b->stmts) s(t.get(), d);
        else if (auto* l = dynamic_cast<LoopStmt*>(x)) {
            ex.push_back(lbl++);
            ind(); std::println("for(;;) {{");
            s(l->body.get(), d + 1);
            ind(); std::println("}} L{}:;", ex.back());
            ex.pop_back();
        }
        else if (auto* b = dynamic_cast<BreakIfzStmt*>(x)) {
            ind(); std::print("if ("); e(b->cond.get()); std::println(" == 0) goto L{};", ex.back());
        }
        else if (auto* p = dynamic_cast<PrintStmt*>(x)) {
            ind();
            if constexpr (INT_BITS > 0 && INT_BITS <= 128) {
                std::print("std::println(\"{{}}\", to_string("); e(p->e.get()); std::println("));");
            } else {
                std::print("std::println(\"{{}}\", ("); e(p->e.get()); std::println(").str());");
            }
        }
    }

    void gen(std::vector<StmtPtr>& prog) {
        std::println("#include <print>\n#include <boost/multiprecision/cpp_int.hpp>");
        if constexpr (INT_BITS == 0)
            std::println("using Int = boost::multiprecision::cpp_int;");
        else if constexpr (INT_BITS <= 128) {
            std::println("using Int = __int128;");
            std::println("std::string to_string(Int v) {{");
            std::println("  if (!v) return \"0\"; std::string s; bool n = v < 0; if (n) v = -v;");
            std::println("  while (v) {{ s = char('0' + v % 10) + s; v /= 10; }} return n ? \"-\" + s : s; }}");
        } else {
            std::println("using Int = boost::multiprecision::number<boost::multiprecision::cpp_int_backend<");
            std::println("  {0}, {0}, boost::multiprecision::signed_magnitude, boost::multiprecision::unchecked, void>>;", INT_BITS);
        }
        std::println("int main(int argc, char** argv) {{");
        for (auto& v : collect_vars(prog)) std::println("  Int {} = 0;", v);
        if constexpr (INT_BITS > 0 && INT_BITS <= 128) {
            std::println("  Int arg1 = argc > 1 ? std::atoll(argv[1]) : 0;");
            std::println("  Int arg2 = argc > 2 ? std::atoll(argv[2]) : 0;");
        } else {
            std::println("  Int arg1 = argc > 1 ? Int(argv[1]) : Int(0);");
            std::println("  Int arg2 = argc > 2 ? Int(argv[2]) : Int(0);");
        }
        for (auto& x : prog) s(x.get());
        std::println("}}");
    }
};

struct LlvmGen {
    int t = 0, lbl = 0;
    std::vector<int> ex;
    std::string I = std::format("i{}", INT_BITS);

    std::string e(Expr* x) {
        if (auto* n = dynamic_cast<NumberExpr*>(x)) return std::to_string(n->val);
        if (auto* v = dynamic_cast<VarExpr*>(x)) {
            auto r = std::format("%t{}", t++);
            std::println("  {} = load {}, ptr %{}", r, I, v->name);
            return r;
        }
        if (auto* u = dynamic_cast<NegExpr*>(x)) {
            auto r = std::format("%t{}", t++);
            std::println("  {} = sub {} 0, {}", r, I, e(u->e.get()));
            return r;
        }
        if (auto* b = dynamic_cast<BinExpr*>(x)) {
            auto l = e(b->l.get()), r = e(b->r.get()), o = std::format("%t{}", t++);
            std::println("  {} = {} {} {}, {}", o, b->op == '+' ? "add" : "sub", I, l, r);
            return o;
        }
        return "0";
    }

    void s(Stmt* x) {
        if (auto* a = dynamic_cast<AssignStmt*>(x))
            std::println("  store {} {}, ptr %{}", I, e(a->e.get()), a->name);
        else if (auto* b = dynamic_cast<BlockStmt*>(x))
            for (auto& y : b->stmts) s(y.get());
        else if (auto* l = dynamic_cast<LoopStmt*>(x)) {
            int h = lbl++, z = lbl++;
            ex.push_back(z);
            std::println("  br label %L{}\nL{}:", h, h);
            s(l->body.get());
            std::println("  br label %L{}\nL{}:", h, z);
            ex.pop_back();
        }
        else if (auto* b = dynamic_cast<BreakIfzStmt*>(x)) {
            auto c = e(b->cond.get()), r = std::format("%t{}", t++);
            int n = lbl++;
            std::println("  {} = icmp eq {} {}, 0", r, I, c);
            std::println("  br i1 {}, label %L{}, label %L{}\nL{}:", r, ex.back(), n, n);
        }
        else if (auto* p = dynamic_cast<PrintStmt*>(x))
            std::println("  call void @print_int({} {})", I, e(p->e.get()));
    }

    void gen(std::vector<StmtPtr>& prog) {
        auto ret = INT_BITS <= 32 ? "  %v = trunc i64 %v64 to i32\n  ret i32 %v"
                 : INT_BITS <= 64 ? "  ret i64 %v64"
                 : std::format("  %v = sext i64 %v64 to {0}\n  ret {0} %v", I);
        auto dig = INT_BITS <= 32 ? "  %c = add i32 %rem, 48"
                 : std::format("  %d = trunc {} %rem to i32\n  %c = add i32 %d, 48", I);
        std::println(R"(declare i32 @putchar(i32)
declare i64 @strtol(ptr, ptr, i32)

define void @print_int_rec({0} %v) {{
  %z = icmp eq {0} %v, 0
  br i1 %z, label %done, label %print
print:
  %div = sdiv {0} %v, 10
  %rem = srem {0} %v, 10
  call void @print_int_rec({0} %div)
{2}
  call i32 @putchar(i32 %c)
  br label %done
done:
  ret void
}}

define void @print_int({0} %v) {{
  %z = icmp eq {0} %v, 0
  br i1 %z, label %zero, label %nonzero
zero:
  call i32 @putchar(i32 48)
  br label %done
nonzero:
  call void @print_int_rec({0} %v)
  br label %done
done:
  call i32 @putchar(i32 10)
  ret void
}}

define {0} @parse_arg(i32 %argc, ptr %argv, i32 %idx) {{
  %has = icmp sgt i32 %argc, %idx
  br i1 %has, label %read, label %default
read:
  %i = sext i32 %idx to i64
  %p = getelementptr ptr, ptr %argv, i64 %i
  %s = load ptr, ptr %p
  %v64 = call i64 @strtol(ptr %s, ptr null, i32 10)
{1}
default:
  ret {0} 0
}}

define i32 @main(i32 %argc, ptr %argv) {{
entry:)", I, ret, dig);
        for (auto& v : collect_vars(prog))
            std::println("  %{} = alloca {}\n  store {} 0, ptr %{}", v, I, I, v);
        std::println("  %arg1 = alloca {0}\n  %a1 = call {0} @parse_arg(i32 %argc, ptr %argv, i32 1)\n  store {0} %a1, ptr %arg1", I);
        std::println("  %arg2 = alloca {0}\n  %a2 = call {0} @parse_arg(i32 %argc, ptr %argv, i32 2)\n  store {0} %a2, ptr %arg2", I);
        for (auto& x : prog) s(x.get());
        std::println("  ret i32 0\n}}");
    }
};

int main(int argc, char** argv) {
    bool llvm = false;
    const char* file = nullptr;
    for (int i = 1; i < argc; i++)
        if (!strcmp(argv[i], "--llvm")) llvm = true; else file = argv[i];
    if (!file) { std::println(stderr, "Usage: {} [--llvm] <file>", argv[0]); return 1; }
    auto prog = parse_program(read_file(file));
    if (!prog) { std::println(stderr, "Error: {}", prog.error()); return 1; }
    if (llvm) {
        if constexpr (INT_BITS == 0) { std::println(stderr, "Error: LLVM needs INT_BITS > 0"); return 1; }
        else LlvmGen{}.gen(*prog);
    } else CppGen{}.gen(*prog);
}
