// LLVM runtime: extern "C" wrappers around pl0_1_bigint.hpp
// Compile to .ll for linking with generated LLVM IR
#include "pl0_1_bigint.hpp"

using namespace bigint;

extern "C" {

void bi_init(Raw* out, SLimb v) { init(*out, v); }
void bi_copy(Raw* dst, const Raw* src) { copy(*dst, *src); }
Size bi_add_size(const Raw* a, const Raw* b) { return add_size(*a, *b); }
Size bi_sub_size(const Raw* a, const Raw* b) { return sub_size(*a, *b); }
Size bi_neg_size(const Raw* a) { return a->size; }
Size bi_size(const Raw* a) { return a->size; }
void bi_add(Raw* out, const Raw* a, const Raw* b) { add(*out, *a, *b); }
void bi_sub(Raw* out, const Raw* a, const Raw* b) { sub(*out, *a, *b); }
void bi_neg(Raw* out, const Raw* a) { neg(*out, *a); }
bool bi_is_zero(const Raw* a) { return is_zero(*a); }
void bi_print(const Raw* v) { print(*v); }
void bi_from_str(Raw* out, const char* s) { from_str(*out, s); }
Size bi_buf_size(Size limbs) { return Raw::buf_size(limbs); }

void bi_var_init(Raw** var_ptr, Size* cap_ptr) {
    auto v = var_init();
    *var_ptr = v.ptr;
    *cap_ptr = v.cap;
}
void bi_assign(Raw** var_ptr, Size* cap_ptr, const Raw* value) {
    Var v{*var_ptr, *cap_ptr};
    assign(v, *value);
    *var_ptr = v.ptr;
    *cap_ptr = v.cap;
}
void bi_arg_init(Raw** var_ptr, Size* cap_ptr, int argc, char** argv, int idx) {
    auto v = arg_init(argc, argv, idx);
    *var_ptr = v.ptr;
    *cap_ptr = v.cap;
}

}
