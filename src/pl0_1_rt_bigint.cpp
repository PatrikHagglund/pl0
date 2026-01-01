#include <boost/multiprecision/cpp_int.hpp>
#include <cstdlib>
using Int = boost::multiprecision::cpp_int;

namespace boost {
  void throw_exception(std::exception const& e, boost::source_location const&) { std::cerr << e.what() << "\n"; std::abort(); }
}

extern "C" {
  void* bi_new(long v) { return new Int(v); }
  void* bi_add(void* a, void* b) { return new Int(*(Int*)a + *(Int*)b); }
  void* bi_sub(void* a, void* b) { return new Int(*(Int*)a - *(Int*)b); }
  void* bi_neg(void* a) { return new Int(-*(Int*)a); }
  int bi_is_zero(void* a) { return *(Int*)a == 0 ? 1 : 0; }
  void bi_print(void* v) { std::cout << *(Int*)v << "\n"; }
  void* bi_from_str(const char* s) { return new Int(s); }
}
