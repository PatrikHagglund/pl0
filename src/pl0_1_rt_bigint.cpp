/*
 Runtime design summary:

 - Temporaries: allocated on the stack (alloca) and reclaimed with llvm.stacksave/llvm.stackrestore.
   This keeps most bigint work allocation-free and fast.

 - Variables (program-level named variables): represented by (ptr, cap) pairs. Initially ptr=null, cap=0.
   The bi_assign() function handles all allocation and reallocation using realloc().

 - Assignment via bi_assign(ptr*, cap*, value):
   - If needed > cap: use realloc() with doubling strategy (newcap = max(cap*2, needed))
   - realloc(NULL, size) acts like malloc(size) for initial allocation
   - Copies value data via bi_copy()
   - Updates ptr and cap through the pointers

 - Initialization helpers (simplify generated LLVM IR):
   - bi_var_init(ptr*, cap*): initialize variable to 0
   - bi_arg_init(ptr*, cap*, argc, argv, idx): initialize from argv[idx], or 0 if idx >= argc

 - This design centralizes all memory management in bi_assign(), simplifying the generated LLVM IR
   and enabling realloc() to potentially extend buffers in-place without copying.

 - Important: Do not change the stack/heap split. Temporaries remain stack-allocated; only
   variable assignments (via bi_assign) may cause heap allocations.
*/
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <span>

// --- Limb abstraction (change these to switch limb size) ---
// To use 128-bit limbs: Limb=__uint128_t, SLimb=__int128_t, DLimb=unsigned _BitInt(256), LimbBits=128
// Note: _BitInt requires C++23/clang; LLVM JIT (lli) crashes on _BitInt as of LLVM 21.
using Limb = uint64_t;
using SLimb = int64_t;
using DLimb = __uint128_t;
constexpr int LimbBits = 64;
constexpr Limb Limb0 = 0;

// --- BigInt types ---
using BiSize = uint32_t;

struct BigInt {
    BiSize size;
    bool neg;
    Limb limbs[];
};

namespace {

auto limbs_of(const BigInt* b) { return std::span{b->limbs, b->size}; }

int cmp_mag(const BigInt* a, const BigInt* b) {
    int r = 0;
    if (a->size != b->size)
        r = a->size > b->size ? 1 : -1;
    else
        for (BiSize i = a->size; i-- > 0; )
            if (a->limbs[i] != b->limbs[i]) { r = a->limbs[i] > b->limbs[i] ? 1 : -1; break; }
    [[assume(r >= -1 && r <= 1)]];
    return r;
}

void add_mag(BigInt* out, const BigInt* a, const BigInt* b) {
    auto n = std::max(a->size, b->size);
    Limb carry = 0;
    for (BiSize i = 0; i < n; i++) {
        auto av = i < a->size ? a->limbs[i] : Limb0;
        auto bv = i < b->size ? b->limbs[i] : Limb0;
        auto sum = static_cast<DLimb>(av) + bv + carry;
        out->limbs[i] = static_cast<Limb>(sum);
        carry = static_cast<Limb>(sum >> LimbBits);
    }
    out->size = carry ? (out->limbs[n] = carry, n + 1) : n;
}

void sub_mag(BigInt* out, const BigInt* a, const BigInt* b) {
    auto n = a->size;
    Limb borrow = 0;
    for (BiSize i = 0; i < n; i++) {
        auto av = a->limbs[i];
        auto bv = i < b->size ? b->limbs[i] : Limb0;
        out->limbs[i] = av - bv - borrow;
        borrow = av < bv + borrow;
    }
    while (n > 0 && out->limbs[n-1] == 0) n--;
    out->size = n;
}

} // namespace

extern "C" {

void bi_init(BigInt* out, SLimb v) {
    out->neg = v < 0;
    auto uv = static_cast<Limb>(v < 0 ? -v : v);
    out->size = uv ? (out->limbs[0] = uv, 1) : 0;
}

void bi_copy(BigInt* dst, const BigInt* src) {
    dst->size = src->size;
    dst->neg = src->neg;
    std::ranges::copy(limbs_of(src), dst->limbs);
}

BiSize bi_add_size(const BigInt* a, const BigInt* b) {
    return std::max(a->size, b->size) + 1;
}
BiSize bi_sub_size(const BigInt* a, const BigInt* b) {
    return std::max(a->size, b->size) + 1;
}
BiSize bi_neg_size(const BigInt* a) { return a->size; }
BiSize bi_size(const BigInt* a) { return a->size; }

void bi_add(BigInt* out, const BigInt* a, const BigInt* b) {
    if (a->neg == b->neg) {
        add_mag(out, a, b);
        out->neg = a->neg;
    } else if (cmp_mag(a, b) >= 0) {
        sub_mag(out, a, b);
        out->neg = a->neg;
    } else {
        sub_mag(out, b, a);
        out->neg = b->neg;
    }
    if (out->size == 0) out->neg = false;
}

void bi_sub(BigInt* out, const BigInt* a, const BigInt* b) {
    if (a->neg != b->neg) {
        add_mag(out, a, b);
        out->neg = a->neg;
    } else if (cmp_mag(a, b) >= 0) {
        sub_mag(out, a, b);
        out->neg = a->neg;
    } else {
        sub_mag(out, b, a);
        out->neg = !a->neg;
    }
    if (out->size == 0) out->neg = false;
}

void bi_neg(BigInt* out, const BigInt* a) {
    bi_copy(out, a);
    if (out->size > 0) out->neg = !out->neg;
}

bool bi_is_zero(const BigInt* a) { return a->size == 0; }

void bi_print(const BigInt* v) {
    if (v->size == 0) { puts("0"); return; }
    Limb tmp[256];
    BiSize n = v->size;
    std::ranges::copy(limbs_of(v), tmp);
    char buf[1024];
    int pos = 0;
    while (n > 0) {
        DLimb rem = 0;
        for (BiSize i = n; i-- > 0; ) {
            auto cur = (rem << LimbBits) | tmp[i];
            tmp[i] = static_cast<Limb>(cur / 10);
            rem = cur % 10;
        }
        buf[pos++] = '0' + static_cast<int>(rem);
        while (n > 0 && tmp[n-1] == 0) n--;
    }
    if (v->neg) putchar('-');
    while (pos > 0) putchar(buf[--pos]);
    putchar('\n');
}

void bi_from_str(BigInt* out, const char* s) {
    out->size = 0;
    out->neg = (*s == '-') ? (s++, true) : (*s == '+' ? (s++, false) : false);
    while (*s) {
        Limb carry = *s++ - '0';
        for (BiSize i = 0; i < out->size; i++) {
            auto p = static_cast<DLimb>(out->limbs[i]) * 10 + carry;
            out->limbs[i] = static_cast<Limb>(p);
            carry = static_cast<Limb>(p >> LimbBits);
        }
        if (carry) out->limbs[out->size++] = carry;
    }
    if (out->size == 0) out->neg = false;
}

BiSize bi_buf_size(BiSize limbs) {
    return sizeof(BigInt) + limbs * sizeof(Limb);
}

void bi_assign(BigInt** var_ptr, BiSize* cap_ptr, const BigInt* value) {
    BiSize needed = bi_buf_size(value->size);
    BiSize cap = *cap_ptr;
    BigInt* var = *var_ptr;

    if (needed > cap) {
        // Doubling strategy: newcap = max(cap * 2, needed)
        BiSize newcap = cap * 2;
        if (newcap < needed) newcap = needed;
        // realloc(NULL, size) acts like malloc(size) for initial allocation
        var = static_cast<BigInt*>(std::realloc(var, newcap));
        *var_ptr = var;
        *cap_ptr = newcap;
    }
    bi_copy(var, value);
}

void bi_var_init(BigInt** var_ptr, BiSize* cap_ptr) {
    auto* p = static_cast<BigInt*>(std::malloc(sizeof(BigInt)));
    *var_ptr = p;
    *cap_ptr = sizeof(BigInt);
    p->size = 0;
    p->neg = false;
}

void bi_arg_init(BigInt** var_ptr, BiSize* cap_ptr, int argc, char** argv, int idx) {
    char buf[520];
    auto* tmp = reinterpret_cast<BigInt*>(buf);
    if (idx < argc)
        bi_from_str(tmp, argv[idx]);
    else
        bi_init(tmp, 0);
    *var_ptr = nullptr;
    *cap_ptr = 0;
    bi_assign(var_ptr, cap_ptr, tmp);
}

}