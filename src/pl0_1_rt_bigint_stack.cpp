// Stack-based bigint runtime for PL/0
// All buffers allocated via alloca (no heap).
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <span>

struct BigInt {
    uint32_t size;  // number of limbs in use
    bool neg;       // true if negative
    uint64_t limbs[];
};

namespace {

auto limbs_of(const BigInt* b) { return std::span{b->limbs, b->size}; }

int cmp_mag(const BigInt* a, const BigInt* b) {
    if (a->size != b->size) return a->size > b->size ? 1 : -1;
    for (uint32_t i = a->size; i-- > 0; )
        if (a->limbs[i] != b->limbs[i]) return a->limbs[i] > b->limbs[i] ? 1 : -1;
    return 0;
}

void add_mag(BigInt* out, const BigInt* a, const BigInt* b) {
    auto n = std::max(a->size, b->size);
    uint64_t carry = 0;
    for (uint32_t i = 0; i < n; i++) {
        auto av = i < a->size ? a->limbs[i] : 0UL;
        auto bv = i < b->size ? b->limbs[i] : 0UL;
        auto sum = static_cast<__uint128_t>(av) + bv + carry;
        out->limbs[i] = static_cast<uint64_t>(sum);
        carry = sum >> 64;
    }
    out->size = carry ? (out->limbs[n] = carry, n + 1) : n;
}

void sub_mag(BigInt* out, const BigInt* a, const BigInt* b) {
    auto n = a->size;
    uint64_t borrow = 0;
    for (uint32_t i = 0; i < n; i++) {
        auto av = a->limbs[i];
        auto bv = i < b->size ? b->limbs[i] : 0UL;
        out->limbs[i] = av - bv - borrow;
        borrow = av < bv + borrow;
    }
    while (n > 0 && out->limbs[n-1] == 0) n--;
    out->size = n;
}

} // namespace

extern "C" {

void bi_init(BigInt* out, int64_t v) {
    out->neg = v < 0;
    auto uv = static_cast<uint64_t>(v < 0 ? -v : v);
    out->size = uv ? (out->limbs[0] = uv, 1) : 0;
}

void bi_copy(BigInt* dst, const BigInt* src) {
    dst->size = src->size;
    dst->neg = src->neg;
    std::ranges::copy(limbs_of(src), dst->limbs);
}

uint32_t bi_add_size(const BigInt* a, const BigInt* b) {
    return std::max(a->size, b->size) + 1;
}
uint32_t bi_sub_size(const BigInt* a, const BigInt* b) {
    return std::max(a->size, b->size) + 1;
}
uint32_t bi_neg_size(const BigInt* a) { return a->size; }
uint32_t bi_size(const BigInt* a) { return a->size; }

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

int32_t bi_is_zero(const BigInt* a) { return a->size == 0; }

void bi_print(const BigInt* v) {
    if (v->size == 0) { puts("0"); return; }
    uint64_t tmp[256];
    uint32_t n = v->size;
    std::ranges::copy(limbs_of(v), tmp);
    char buf[1024];
    int pos = 0;
    while (n > 0) {
        __uint128_t rem = 0;
        for (uint32_t i = n; i-- > 0; ) {
            auto cur = (rem << 64) | tmp[i];
            tmp[i] = cur / 10;
            rem = cur % 10;
        }
        buf[pos++] = '0' + rem;
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
        uint64_t carry = *s++ - '0';
        for (uint32_t i = 0; i < out->size; i++) {
            auto p = static_cast<__uint128_t>(out->limbs[i]) * 10 + carry;
            out->limbs[i] = static_cast<uint64_t>(p);
            carry = p >> 64;
        }
        if (carry) out->limbs[out->size++] = carry;
    }
    if (out->size == 0) out->neg = false;
}

uint32_t bi_buf_size(uint32_t limbs) {
    return sizeof(BigInt) + limbs * sizeof(uint64_t);
}

}
