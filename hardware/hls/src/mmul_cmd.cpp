#include <ap_int.h>

namespace {

constexpr unsigned int kTileMax = 32;
constexpr unsigned int kCmdMagic = 0x55434D44u;  // "UCMD"
constexpr unsigned int kStatsWords = 16;

constexpr unsigned int kCmdFlagEnable = 1u << 0;
constexpr unsigned int kCmdFlagAccumulate = 1u << 1;

enum CmdWord : unsigned int {
  CMD_MAGIC = 0,
  CMD_FLAGS = 1,
  CMD_M = 2,
  CMD_N = 3,
  CMD_K = 4,
  CMD_LDA = 5,
  CMD_LDB = 6,
  CMD_LDC = 7,
  CMD_A_OFFSET_WORDS = 8,
  CMD_B_OFFSET_WORDS = 9,
  CMD_C_OFFSET_WORDS = 10,
  CMD_TILE_M = 11,
  CMD_TILE_N = 12,
  CMD_TILE_K = 13,
};

enum StatWord : unsigned int {
  ST_STATUS = 0,
  ST_TILE_COUNT = 1,
  ST_LOAD_CYCLES = 2,
  ST_COMPUTE_CYCLES = 3,
  ST_STORE_CYCLES = 4,
  ST_TOTAL_CYCLES = 5,
  ST_BYTES_A = 6,
  ST_BYTES_B = 7,
  ST_BYTES_C = 8,
};

using data_t = ap_uint<32>;
using acc_t = ap_uint<64>;

unsigned int clamp_u32(const unsigned int value,
                       const unsigned int lo,
                       const unsigned int hi) {
#pragma HLS INLINE
  if (value < lo) {
    return lo;
  }
  if (value > hi) {
    return hi;
  }
  return value;
}

unsigned int min_u32(const unsigned int a, const unsigned int b) {
#pragma HLS INLINE
  return (a < b) ? a : b;
}

void clear_c_tile(acc_t c_tile[kTileMax][kTileMax], const unsigned int rows, const unsigned int cols) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int j = 0; j < cols; ++j) {
#pragma HLS PIPELINE II = 1
      c_tile[i][j] = 0;
    }
  }
}

void load_c_tile(const data_t* c,
                 acc_t c_tile[kTileMax][kTileMax],
                 const unsigned int c_offset_words,
                 const unsigned int ldc,
                 const unsigned int row0,
                 const unsigned int col0,
                 const unsigned int rows,
                 const unsigned int cols) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int j = 0; j < cols; ++j) {
#pragma HLS PIPELINE II = 1
      const unsigned int idx = c_offset_words + ((row0 + i) * ldc) + (col0 + j);
      c_tile[i][j] = c[idx];
    }
  }
}

void load_a_tile(const data_t* a,
                 data_t a_tile[kTileMax][kTileMax],
                 const unsigned int a_offset_words,
                 const unsigned int lda,
                 const unsigned int row0,
                 const unsigned int k0,
                 const unsigned int rows,
                 const unsigned int kspan) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int k = 0; k < kspan; ++k) {
#pragma HLS PIPELINE II = 1
      const unsigned int idx = a_offset_words + ((row0 + i) * lda) + (k0 + k);
      a_tile[i][k] = a[idx];
    }
  }
}

void load_b_tile(const data_t* b,
                 data_t b_tile[kTileMax][kTileMax],
                 const unsigned int b_offset_words,
                 const unsigned int ldb,
                 const unsigned int k0,
                 const unsigned int col0,
                 const unsigned int kspan,
                 const unsigned int cols) {
#pragma HLS INLINE
  for (unsigned int k = 0; k < kspan; ++k) {
    for (unsigned int j = 0; j < cols; ++j) {
#pragma HLS PIPELINE II = 1
      const unsigned int idx = b_offset_words + ((k0 + k) * ldb) + (col0 + j);
      b_tile[k][j] = b[idx];
    }
  }
}

void compute_tile(const data_t a_tile[kTileMax][kTileMax],
                  const data_t b_tile[kTileMax][kTileMax],
                  acc_t c_tile[kTileMax][kTileMax],
                  const unsigned int rows,
                  const unsigned int cols,
                  const unsigned int kspan) {
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
                  const acc_t c_tile[kTileMax][kTileMax],
                  const unsigned int c_offset_words,
                  const unsigned int ldc,
                  const unsigned int row0,
                  const unsigned int col0,
                  const unsigned int rows,
                  const unsigned int cols) {
#pragma HLS INLINE
  for (unsigned int i = 0; i < rows; ++i) {
    for (unsigned int j = 0; j < cols; ++j) {
#pragma HLS PIPELINE II = 1
      const unsigned int idx = c_offset_words + ((row0 + i) * ldc) + (col0 + j);
      c[idx] = static_cast<data_t>(c_tile[i][j]);
    }
  }
}

}  // namespace

extern "C" {
void mmul_cmd(const data_t* a,
              const data_t* b,
              data_t* c,
              const ap_uint<32>* cmd,
              ap_uint<64>* stats,
              const unsigned int dim_fallback) {
#pragma HLS INTERFACE m_axi port = a offset = slave bundle = gmem0
#pragma HLS INTERFACE m_axi port = b offset = slave bundle = gmem1
#pragma HLS INTERFACE m_axi port = c offset = slave bundle = gmem2
#pragma HLS INTERFACE m_axi port = cmd offset = slave bundle = gmem3
#pragma HLS INTERFACE m_axi port = stats offset = slave bundle = gmem4
#pragma HLS INTERFACE s_axilite port = a bundle = control
#pragma HLS INTERFACE s_axilite port = b bundle = control
#pragma HLS INTERFACE s_axilite port = c bundle = control
#pragma HLS INTERFACE s_axilite port = cmd bundle = control
#pragma HLS INTERFACE s_axilite port = stats bundle = control
#pragma HLS INTERFACE s_axilite port = dim_fallback bundle = control
#pragma HLS INTERFACE s_axilite port = return bundle = control

  unsigned int m = dim_fallback;
  unsigned int n = dim_fallback;
  unsigned int k_total = dim_fallback;
  unsigned int lda = dim_fallback;
  unsigned int ldb = dim_fallback;
  unsigned int ldc = dim_fallback;
  unsigned int a_offset_words = 0;
  unsigned int b_offset_words = 0;
  unsigned int c_offset_words = 0;
  unsigned int tile_m = 16;
  unsigned int tile_n = 16;
  unsigned int tile_k = 16;
  unsigned int flags = 0;

  if (cmd != nullptr && cmd[CMD_MAGIC] == kCmdMagic && (cmd[CMD_FLAGS] & kCmdFlagEnable)) {
    flags = static_cast<unsigned int>(cmd[CMD_FLAGS]);
    m = static_cast<unsigned int>(cmd[CMD_M]);
    n = static_cast<unsigned int>(cmd[CMD_N]);
    k_total = static_cast<unsigned int>(cmd[CMD_K]);
    lda = static_cast<unsigned int>(cmd[CMD_LDA]);
    ldb = static_cast<unsigned int>(cmd[CMD_LDB]);
    ldc = static_cast<unsigned int>(cmd[CMD_LDC]);
    a_offset_words = static_cast<unsigned int>(cmd[CMD_A_OFFSET_WORDS]);
    b_offset_words = static_cast<unsigned int>(cmd[CMD_B_OFFSET_WORDS]);
    c_offset_words = static_cast<unsigned int>(cmd[CMD_C_OFFSET_WORDS]);
    tile_m = static_cast<unsigned int>(cmd[CMD_TILE_M]);
    tile_n = static_cast<unsigned int>(cmd[CMD_TILE_N]);
    tile_k = static_cast<unsigned int>(cmd[CMD_TILE_K]);
  }

  m = clamp_u32(m, 1, 4096);
  n = clamp_u32(n, 1, 4096);
  k_total = clamp_u32(k_total, 1, 4096);
  lda = clamp_u32(lda, 1, 4096);
  ldb = clamp_u32(ldb, 1, 4096);
  ldc = clamp_u32(ldc, 1, 4096);
  tile_m = clamp_u32(tile_m, 1, kTileMax);
  tile_n = clamp_u32(tile_n, 1, kTileMax);
  tile_k = clamp_u32(tile_k, 1, kTileMax);

  const bool accumulate_c = (flags & kCmdFlagAccumulate) != 0;

  data_t a_tile[kTileMax][kTileMax];
  data_t b_tile[kTileMax][kTileMax];
  acc_t c_tile[kTileMax][kTileMax];

#pragma HLS BIND_STORAGE variable = a_tile type = ram_t2p impl = bram
#pragma HLS BIND_STORAGE variable = b_tile type = ram_t2p impl = bram
#pragma HLS ARRAY_PARTITION variable = a_tile dim = 2 cyclic factor = 8
#pragma HLS ARRAY_PARTITION variable = b_tile dim = 1 cyclic factor = 8

  ap_uint<64> tile_count = 0;
  ap_uint<64> load_cycles = 0;
  ap_uint<64> compute_cycles = 0;
  ap_uint<64> store_cycles = 0;
  ap_uint<64> bytes_a = 0;
  ap_uint<64> bytes_b = 0;
  ap_uint<64> bytes_c = 0;

  for (unsigned int row0 = 0; row0 < m; row0 += tile_m) {
    const unsigned int rows = min_u32(tile_m, m - row0);
    for (unsigned int col0 = 0; col0 < n; col0 += tile_n) {
      const unsigned int cols = min_u32(tile_n, n - col0);

      if (accumulate_c) {
        load_c_tile(c, c_tile, c_offset_words, ldc, row0, col0, rows, cols);
        load_cycles += static_cast<ap_uint<64>>(rows) * cols;
        bytes_c += static_cast<ap_uint<64>>(rows) * cols * 4;
      } else {
        clear_c_tile(c_tile, rows, cols);
      }

      for (unsigned int k0 = 0; k0 < k_total; k0 += tile_k) {
        const unsigned int kspan = min_u32(tile_k, k_total - k0);
        load_a_tile(a, a_tile, a_offset_words, lda, row0, k0, rows, kspan);
        load_b_tile(b, b_tile, b_offset_words, ldb, k0, col0, kspan, cols);
        compute_tile(a_tile, b_tile, c_tile, rows, cols, kspan);

        tile_count += 1;
        load_cycles += static_cast<ap_uint<64>>(rows) * kspan;
        load_cycles += static_cast<ap_uint<64>>(kspan) * cols;
        compute_cycles += static_cast<ap_uint<64>>(rows) * cols * kspan;
        bytes_a += static_cast<ap_uint<64>>(rows) * kspan * 4;
        bytes_b += static_cast<ap_uint<64>>(kspan) * cols * 4;
      }

      store_c_tile(c, c_tile, c_offset_words, ldc, row0, col0, rows, cols);
      store_cycles += static_cast<ap_uint<64>>(rows) * cols;
      bytes_c += static_cast<ap_uint<64>>(rows) * cols * 4;
    }
  }

  if (stats != nullptr) {
    for (unsigned int i = 0; i < kStatsWords; ++i) {
#pragma HLS PIPELINE II = 1
      stats[i] = 0;
    }
    stats[ST_STATUS] = 0;
    stats[ST_TILE_COUNT] = tile_count;
    stats[ST_LOAD_CYCLES] = load_cycles;
    stats[ST_COMPUTE_CYCLES] = compute_cycles;
    stats[ST_STORE_CYCLES] = store_cycles;
    stats[ST_TOTAL_CYCLES] = load_cycles + compute_cycles + store_cycles;
    stats[ST_BYTES_A] = bytes_a;
    stats[ST_BYTES_B] = bytes_b;
    stats[ST_BYTES_C] = bytes_c;
  }
}
}
