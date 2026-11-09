#pragma once

#include <ap_int.h>

extern "C" {
void mmul(const ap_uint<32>* a,
          const ap_uint<32>* b,
          ap_uint<32>* c,
          unsigned int dim);
}
