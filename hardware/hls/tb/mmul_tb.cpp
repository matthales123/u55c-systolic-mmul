#include "mmul.hpp"

#include <cstdlib>
#include <iostream>
#include <vector>

static void reference_mmul(const std::vector<ap_uint<32>>& a,
                           const std::vector<ap_uint<32>>& b,
                           std::vector<ap_uint<32>>& c,
                           const unsigned int dim) {
  for (unsigned int i = 0; i < dim; ++i) {
    for (unsigned int j = 0; j < dim; ++j) {
      ap_uint<64> acc = 0;
      for (unsigned int k = 0; k < dim; ++k) {
        acc += static_cast<ap_uint<64>>(a[i * dim + k]) *
               static_cast<ap_uint<64>>(b[k * dim + j]);
      }
      c[i * dim + j] = static_cast<ap_uint<32>>(acc);
    }
  }
}

int main() {
  constexpr unsigned int dim = 4;
  constexpr unsigned int elems = dim * dim;

  std::vector<ap_uint<32>> a(elems);
  std::vector<ap_uint<32>> b(elems);
  std::vector<ap_uint<32>> c(elems);
  std::vector<ap_uint<32>> expected(elems);

  for (unsigned int i = 0; i < elems; ++i) {
    a[i] = (i % 7) + 1;
    b[i] = (i % 5) + 2;
  }

  mmul(a.data(), b.data(), c.data(), dim);
  reference_mmul(a, b, expected, dim);

  for (unsigned int i = 0; i < elems; ++i) {
    if (c[i] != expected[i]) {
      std::cerr << "Mismatch at i=" << i << ": got " << c[i]
                << " expected " << expected[i] << '\n';
      return EXIT_FAILURE;
    }
  }

  std::cout << "mmul_tb PASS\n";
  return EXIT_SUCCESS;
}
