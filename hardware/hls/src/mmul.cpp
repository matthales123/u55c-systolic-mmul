#include "mmul.hpp"

namespace {

constexpr unsigned int kTile = 16;

using data_t = ap_uint<32>;
using acc_t = ap_uint<64>;

void clear_c_tile(acc_t c_tile[kTile][kTile], unsigned int rows, unsigned int cols) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int j = 0; j < cols; ++j) {
#pragma HLS PIPELINE II = 1
      c_tile[i][j] = 0;
    }
  }
}

void load_a_tile(const data_t* a,
                 data_t a_tile[kTile][kTile],
                 unsigned int dim,
                 unsigned int row0,
                 unsigned int k0,
                 unsigned int rows,
                 unsigned int kspan) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int k = 0; k < kspan; ++k) {
#pragma HLS PIPELINE II = 1
      a_tile[i][k] = a[(row0 + i) * dim + (k0 + k)];
    }
  }
}

void load_b_tile(const data_t* b,
                 data_t b_tile[kTile][kTile],
                 unsigned int dim,
                 unsigned int k0,
                 unsigned int col0,
                 unsigned int kspan,
                 unsigned int cols) {
#pragma HLS INLINE
  for (unsigned int k = 0; k < kspan; ++k) {
    for (unsigned int j = 0; j < cols; ++j) {
#pragma HLS PIPELINE II = 1
      b_tile[k][j] = b[(k0 + k) * dim + (col0 + j)];
    }
  }
}

// Compute unit for one C tile. This mirrors the report architecture's
// "compute/systolic core" stage while remaining HLS-friendly.
void compute_tile(const data_t a_tile[kTile][kTile],
                  const data_t b_tile[kTile][kTile],
                  acc_t c_tile[kTile][kTile],
                  unsigned int rows,
                  unsigned int cols,
                  unsigned int kspan) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int j = 0; j < cols; ++j) {
      acc_t sum = c_tile[i][j];
      for (unsigned int k = 0; k < kspan; ++k) {
#pragma HLS PIPELINE II = 1
        sum += static_cast<acc_t>(a_tile[i][k]) * static_cast<acc_t>(b_tile[k][j]);
      }
      c_tile[i][j] = sum;
    }
  }
}

void store_c_tile(data_t* c,
                  const acc_t c_tile[kTile][kTile],
                  unsigned int dim,
                  unsigned int row0,
                  unsigned int col0,
                  unsigned int rows,
                  unsigned int cols) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int j = 0; j < cols; ++j) {
#pragma HLS PIPELINE II = 1
      c[(row0 + i) * dim + (col0 + j)] = static_cast<data_t>(c_tile[i][j]);
    }
  }
}

}  // namespace

extern "C" {
void mmul(const data_t* a,
          const data_t* b,
          data_t* c,
          const unsigned int dim) {
#pragma HLS INTERFACE m_axi port = a offset = slave bundle = gmem0
#pragma HLS INTERFACE m_axi port = b offset = slave bundle = gmem1
#pragma HLS INTERFACE m_axi port = c offset = slave bundle = gmem2
#pragma HLS INTERFACE s_axilite port = a bundle = control
#pragma HLS INTERFACE s_axilite port = b bundle = control
#pragma HLS INTERFACE s_axilite port = c bundle = control
#pragma HLS INTERFACE s_axilite port = dim bundle = control
#pragma HLS INTERFACE s_axilite port = return bundle = control

  if (dim == 0) {
    return;
  }

  data_t a_tile[kTile][kTile];
  data_t b_tile[kTile][kTile];
  acc_t c_tile[kTile][kTile];

#pragma HLS BIND_STORAGE variable = a_tile type = ram_t2p impl = bram
#pragma HLS BIND_STORAGE variable = b_tile type = ram_t2p impl = bram
#pragma HLS ARRAY_PARTITION variable = a_tile dim = 2 cyclic factor = 4
#pragma HLS ARRAY_PARTITION variable = b_tile dim = 1 cyclic factor = 4

  for (unsigned int row0 = 0; row0 < dim; row0 += kTile) {
    const unsigned int rows = ((row0 + kTile) <= dim) ? kTile : (dim - row0);
    for (unsigned int col0 = 0; col0 < dim; col0 += kTile) {
      const unsigned int cols = ((col0 + kTile) <= dim) ? kTile : (dim - col0);

      clear_c_tile(c_tile, rows, cols);

      // Load/compute/store staging: load A/B tiles, run compute tile, then store C tile.
      for (unsigned int k0 = 0; k0 < dim; k0 += kTile) {
        const unsigned int kspan = ((k0 + kTile) <= dim) ? kTile : (dim - k0);
        load_a_tile(a, a_tile, dim, row0, k0, rows, kspan);
        load_b_tile(b, b_tile, dim, k0, col0, kspan, cols);
        compute_tile(a_tile, b_tile, c_tile, rows, cols, kspan);
      }

      store_c_tile(c, c_tile, dim, row0, col0, rows, cols);
    }
  }
}
}
