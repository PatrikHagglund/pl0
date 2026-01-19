// LLVM runtime: extern "C" wrappers around pl0_1_bigint.hpp
// Compile to .ll for linking with generated LLVM IR
#include "pl0_1_bigint.hpp"

using namespace bigint;
using BigInt = Raw;
using BiSize = Size;

extern "C" {

void bi_init(BigInt* out, SLimb v) { init(out, v); }
void bi_copy(BigInt* dst, const BigInt* src) { copy(dst, src); }
BiSize bi_add_size(const BigInt* a, const BigInt* b) { return add_size(a, b); }
BiSize bi_sub_size(const BigInt* a, const BigInt* b) { return sub_size(a, b); }
BiSize bi_neg_size(const BigInt* a) { return a->size; }
BiSize bi_size(const BigInt* a) { return a->size; }
void bi_add(BigInt* out, const BigInt* a, const BigInt* b) { add(out, a, b); }
void bi_sub(BigInt* out, const BigInt* a, const BigInt* b) { sub(out, a, b); }
void bi_neg(BigInt* out, const BigInt* a) { neg(out, a); }
bool bi_is_zero(const BigInt* a) { return is_zero(a); }
void bi_print(const BigInt* v) { print(v); }
void bi_from_str(BigInt* out, const char* s) { from_str(out, s); }
BiSize bi_buf_size(BiSize limbs) { return Raw::buf_size(limbs); }

void bi_assign(BigInt** var_ptr, BiSize* cap_ptr, const BigInt* value) {
    BiSize needed = bi_buf_size(value->size);
    BiSize cap = *cap_ptr;
    BigInt* var = *var_ptr;
    if (needed > cap) {
        BiSize newcap = cap * 2 > needed ? cap * 2 : needed;
        var = static_cast<BigInt*>(std::realloc(var, newcap));
        *var_ptr = var;
        *cap_ptr = newcap;
    }
    copy(var, value);
}

void bi_var_init(BigInt** var_ptr, BiSize* cap_ptr) {
    auto* p = static_cast<BigInt*>(std::malloc(sizeof(BigInt)));
    *var_ptr = p;
    *cap_ptr = sizeof(BigInt);
    p->size = 0;
    p->neg = false;
}

void bi_arg_init(BigInt** var_ptr, BiSize* cap_ptr, int argc, char** argv, int idx) {
    *var_ptr = nullptr;
    *cap_ptr = 0;
    if (idx < argc) {
        BiSize limbs_needed = std::strlen(argv[idx]) / 19 + 2;
        auto* buf = static_cast<char*>(std::malloc(Raw::buf_size(limbs_needed)));
        auto* tmp = reinterpret_cast<BigInt*>(buf);
        from_str(tmp, argv[idx]);
        bi_assign(var_ptr, cap_ptr, tmp);
        std::free(buf);
    } else {
        bi_var_init(var_ptr, cap_ptr);
    }
}

}
