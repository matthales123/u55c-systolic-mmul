#include "u55c_framework/runner.hpp"

#include "u55c_framework/buffer_manager.hpp"
#include "u55c_framework/profiler.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <limits>
#include <optional>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#if defined(U55C_ENABLE_XRT)
#include <xrt/experimental/xrt_xclbin.h>
#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>
#endif

namespace u55c_framework {
namespace {

constexpr std::uint32_t kCmdMagic = 0x55434D44u;  // "UCMD"
constexpr std::uint32_t kCmdWords = 16;
constexpr std::uint32_t kStatsWords = 16;
constexpr std::uint32_t kMaxTileRuntime = 32;

constexpr std::uint32_t kCmdFlagEnable = 1u << 0;
constexpr std::uint32_t kCmdFlagAccumulate = 1u << 1;
constexpr std::uint32_t kCmdFlagHostTiled = 1u << 2;

enum CmdWord : std::uint32_t {
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

enum StatWord : std::uint32_t {
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

struct CounterTotals {
  std::uint64_t kernel_invocations = 0;
  std::uint64_t tile_count = 0;
  std::uint64_t est_load_cycles = 0;
  std::uint64_t est_compute_cycles = 0;
  std::uint64_t est_store_cycles = 0;
  std::uint64_t est_total_cycles = 0;
  std::uint64_t bytes_h2d = 0;
  std::uint64_t bytes_d2h = 0;
};

std::uint32_t sanitize_tile(const std::uint32_t tile) {
  return std::max(1u, std::min(tile, kMaxTileRuntime));
}

std::uint32_t ceil_div_u32(const std::uint32_t a, const std::uint32_t b) {
  return (a + b - 1) / b;
}

std::string utc_now_iso8601() {
  const std::time_t now = std::time(nullptr);
  std::tm tm_utc{};
#if defined(_WIN32)
  gmtime_s(&tm_utc, &now);
#else
  gmtime_r(&now, &tm_utc);
#endif

  std::ostringstream oss;
  oss << std::put_time(&tm_utc, "%Y-%m-%dT%H:%M:%SZ");
  return oss.str();
}

double throughput_gbps(const std::size_t elements, const double total_ms) {
  if (total_ms <= 0.0) {
    return 0.0;
  }

  const double bytes_moved = static_cast<double>(elements) * sizeof(std::uint32_t) * 3.0;
  const double bits_moved = bytes_moved * 8.0;
  return bits_moved / (total_ms * 1.0e6);
}

bool is_matrix_kernel(const std::string& kernel_name) {
  return kernel_name.find("mmul") != std::string::npos ||
         kernel_name.find("gemm") != std::string::npos;
}

std::uint32_t validated_dim_from_elements(const std::size_t elements) {
  const auto dim = static_cast<std::uint32_t>(
      std::llround(std::sqrt(static_cast<long double>(elements))));
  if (static_cast<std::size_t>(dim) * static_cast<std::size_t>(dim) != elements) {
    throw std::runtime_error(
        "matrix workload requires --elements to be a perfect square (dim*dim)");
  }
  return dim;
}

struct MatrixFileData {
  std::uint32_t rows = 0;
  std::uint32_t cols = 0;
  std::vector<std::uint32_t> values;
};

struct MatrixPreparedInputs {
  std::uint32_t m = 0;
  std::uint32_t k = 0;
  std::uint32_t n = 0;
  std::uint32_t padded_dim = 0;
  std::vector<std::uint32_t> padded_a;
  std::vector<std::uint32_t> padded_b;
  std::vector<std::uint32_t> expected;
};

std::uint32_t parse_matrix_cell_to_u32(const std::string& token,
                                       const std::string& file_path,
                                       const std::uint32_t row,
                                       const std::uint32_t col) {
  try {
    const auto value = std::stoll(token);
    return static_cast<std::uint32_t>(static_cast<std::int64_t>(value));
  } catch (const std::exception&) {
    try {
      const auto value = std::stod(token);
      if (std::floor(value) != value) {
        throw std::runtime_error("");
      }
      return static_cast<std::uint32_t>(static_cast<std::int64_t>(value));
    } catch (const std::exception&) {
      std::ostringstream oss;
      oss << "invalid matrix value '" << token << "' at " << file_path << ":" << row << ":" << col
          << " (FPGA benchmark expects integer-valued matrices)";
      throw std::runtime_error(oss.str());
    }
  }
}

MatrixFileData load_matrix_csv(const std::string& path, const std::string& label) {
  std::ifstream in(path);
  if (!in) {
    throw std::runtime_error("unable to open " + label + " file: " + path);
  }

  MatrixFileData out;
  std::string line;
  std::uint32_t row_idx = 0;
  while (std::getline(in, line)) {
    std::string normalized = line;
    for (char& ch : normalized) {
      if (ch == ',' || ch == ';' || ch == '\t') {
        ch = ' ';
      }
    }

    std::istringstream iss(normalized);
    std::vector<std::string> tokens;
    std::string token;
    while (iss >> token) {
      tokens.push_back(token);
    }
    if (tokens.empty()) {
      continue;
    }

    const auto cols = static_cast<std::uint32_t>(tokens.size());
    if (out.cols == 0) {
      out.cols = cols;
    } else if (cols != out.cols) {
      std::ostringstream oss;
      oss << label << " matrix is not rectangular: row " << row_idx << " has " << cols
          << " columns, expected " << out.cols;
      throw std::runtime_error(oss.str());
    }

    for (std::uint32_t col = 0; col < cols; ++col) {
      out.values.push_back(parse_matrix_cell_to_u32(tokens[col], path, row_idx, col));
    }
    row_idx += 1;
  }

  out.rows = row_idx;
  if (out.rows == 0 || out.cols == 0) {
    throw std::runtime_error(label + " matrix file is empty: " + path);
  }

  return out;
}

MatrixPreparedInputs prepare_matrix_inputs_from_files(const std::string& matrix_a_path,
                                                      const std::string& matrix_b_path,
                                                      const std::uint32_t target_dim) {
  const auto a = load_matrix_csv(matrix_a_path, "A");
  const auto b = load_matrix_csv(matrix_b_path, "B");
  if (a.cols != b.rows) {
    std::ostringstream oss;
    oss << "matrix shape mismatch from files: A is " << a.rows << "x" << a.cols << ", B is " << b.rows
        << "x" << b.cols << " (need A.cols == B.rows)";
    throw std::runtime_error(oss.str());
  }

  const auto required_dim = std::max({a.rows, a.cols, b.cols});
  if (target_dim < required_dim) {
    std::ostringstream oss;
    oss << "configured FPGA dim " << target_dim << " is too small for matrix files (need >= "
        << required_dim << " for A=" << a.rows << "x" << a.cols << ", B=" << b.rows << "x" << b.cols
        << ")";
    throw std::runtime_error(oss.str());
  }

  MatrixPreparedInputs out;
  out.m = a.rows;
  out.k = a.cols;
  out.n = b.cols;
  out.padded_dim = target_dim;

  const auto elements = static_cast<std::size_t>(target_dim) * static_cast<std::size_t>(target_dim);
  out.padded_a.assign(elements, 0u);
  out.padded_b.assign(elements, 0u);
  out.expected.assign(elements, 0u);

  for (std::uint32_t r = 0; r < a.rows; ++r) {
    for (std::uint32_t c = 0; c < a.cols; ++c) {
      out.padded_a[static_cast<std::size_t>(r) * target_dim + c] =
          a.values[static_cast<std::size_t>(r) * a.cols + c];
    }
  }
  for (std::uint32_t r = 0; r < b.rows; ++r) {
    for (std::uint32_t c = 0; c < b.cols; ++c) {
      out.padded_b[static_cast<std::size_t>(r) * target_dim + c] =
          b.values[static_cast<std::size_t>(r) * b.cols + c];
    }
  }

  for (std::uint32_t i = 0; i < target_dim; ++i) {
    for (std::uint32_t j = 0; j < target_dim; ++j) {
      std::uint64_t acc = 0;
      for (std::uint32_t k = 0; k < target_dim; ++k) {
        acc += static_cast<std::uint64_t>(
                   out.padded_a[static_cast<std::size_t>(i) * target_dim + k]) *
               static_cast<std::uint64_t>(
                   out.padded_b[static_cast<std::size_t>(k) * target_dim + j]);
      }
      out.expected[static_cast<std::size_t>(i) * target_dim + j] = static_cast<std::uint32_t>(acc);
    }
  }

  return out;
}

void fill_vector_inputs(std::uint32_t* a,
                        std::uint32_t* b,
                        std::vector<std::uint32_t>& expected,
                        const std::size_t elements,
                        const std::uint32_t seed,
                        const std::size_t iteration) {
  std::mt19937 rng(seed + static_cast<std::uint32_t>(iteration));
  std::uniform_int_distribution<std::uint32_t> dist(0u, 0x00FFFFFFu);

  for (std::size_t i = 0; i < elements; ++i) {
    const auto va = dist(rng);
    const auto vb = dist(rng);
    a[i] = va;
    b[i] = vb;
    expected[i] = va + vb;
  }
}

void fill_matrix_inputs(std::uint32_t* a,
                        std::uint32_t* b,
                        std::vector<std::uint32_t>& expected,
                        const std::size_t elements,
                        const std::uint32_t dim,
                        const std::uint32_t seed,
                        const std::size_t iteration) {
  std::mt19937 rng(seed + static_cast<std::uint32_t>(iteration));
  std::uniform_int_distribution<std::uint32_t> dist(0u, 255u);

  for (std::size_t i = 0; i < elements; ++i) {
    a[i] = dist(rng);
    b[i] = dist(rng);
  }

  for (std::uint32_t i = 0; i < dim; ++i) {
    for (std::uint32_t j = 0; j < dim; ++j) {
      std::uint64_t acc = 0;
      for (std::uint32_t k = 0; k < dim; ++k) {
        acc += static_cast<std::uint64_t>(a[i * dim + k]) *
               static_cast<std::uint64_t>(b[k * dim + j]);
      }
      expected[i * dim + j] = static_cast<std::uint32_t>(acc);
    }
  }
}

bool verify_outputs(const std::vector<std::uint32_t>& expected,
                    const std::uint32_t* out,
                    const std::size_t elements) {
  for (std::size_t i = 0; i < elements; ++i) {
    if (out[i] != expected[i]) {
      return false;
    }
  }
  return true;
}

BenchmarkRow base_row(const BenchmarkConfig& cfg, const std::size_t iteration) {
  BenchmarkRow row;
  row.timestamp_utc = utc_now_iso8601();
  row.mode = run_mode_string(cfg.mode);
  row.kernel = cfg.kernel_name;
  row.control_path = control_path_string(cfg.control);
  row.scheduler_mode = scheduler_mode_string(cfg.scheduler);
  row.device_index = cfg.device_index;
  row.elements = cfg.elements;
  row.iteration = iteration;
  row.verify_ok = false;
  row.tile_m = sanitize_tile(cfg.tile_m);
  row.tile_n = sanitize_tile(cfg.tile_n);
  row.tile_k = sanitize_tile(cfg.tile_k);
  return row;
}

CounterTotals estimate_descriptor_counters(const std::uint32_t m,
                                           const std::uint32_t n,
                                           const std::uint32_t k,
                                           const std::uint32_t tile_m,
                                           const std::uint32_t tile_n,
                                           const std::uint32_t tile_k,
                                           const bool host_tiled) {
  CounterTotals totals;
  const std::uint32_t tm = sanitize_tile(tile_m);
  const std::uint32_t tn = sanitize_tile(tile_n);
  const std::uint32_t tk = sanitize_tile(tile_k);

  const auto row_tiles = ceil_div_u32(m, tm);
  const auto col_tiles = ceil_div_u32(n, tn);
  const auto k_tiles = ceil_div_u32(k, tk);

  if (host_tiled) {
    totals.kernel_invocations = static_cast<std::uint64_t>(row_tiles) * col_tiles * k_tiles;
  } else {
    totals.kernel_invocations = 1;
  }

  for (std::uint32_t row0 = 0; row0 < m; row0 += tm) {
    const auto rows = std::min(tm, m - row0);
    for (std::uint32_t col0 = 0; col0 < n; col0 += tn) {
      const auto cols = std::min(tn, n - col0);

      if (!host_tiled) {
        // Kernel-tiled mode accumulates across k inside one kernel call.
        for (std::uint32_t k0 = 0; k0 < k; k0 += tk) {
          const auto kspan = std::min(tk, k - k0);
          totals.tile_count += 1;
          totals.est_load_cycles += static_cast<std::uint64_t>(rows) * kspan +
                                    static_cast<std::uint64_t>(kspan) * cols;
          totals.est_compute_cycles += static_cast<std::uint64_t>(rows) * cols * kspan;
        }
        totals.est_store_cycles += static_cast<std::uint64_t>(rows) * cols;
      } else {
        // Host-tiled mode dispatches one k-chunk per kernel call.
        for (std::uint32_t k0 = 0; k0 < k; k0 += tk) {
          const auto kspan = std::min(tk, k - k0);
          totals.tile_count += 1;
          totals.est_load_cycles += static_cast<std::uint64_t>(rows) * kspan +
                                    static_cast<std::uint64_t>(kspan) * cols;
          totals.est_compute_cycles += static_cast<std::uint64_t>(rows) * cols * kspan;
          totals.est_store_cycles += static_cast<std::uint64_t>(rows) * cols;
        }
      }
    }
  }

  totals.est_total_cycles =
      totals.est_load_cycles + totals.est_compute_cycles + totals.est_store_cycles;
  return totals;
}

std::vector<BenchmarkRow> run_dry_run(const BenchmarkConfig& cfg) {
  std::vector<BenchmarkRow> rows;
  rows.reserve(cfg.iterations);

  std::vector<std::uint32_t> host_a(cfg.elements);
  std::vector<std::uint32_t> host_b(cfg.elements);
  std::vector<std::uint32_t> expected(cfg.elements);
  std::vector<std::uint32_t> dev_a(cfg.elements);
  std::vector<std::uint32_t> dev_b(cfg.elements);
  std::vector<std::uint32_t> dev_out(cfg.elements);
  std::vector<std::uint32_t> host_out(cfg.elements);
  const bool matrix_mode = is_matrix_kernel(cfg.kernel_name);
  const auto dim = matrix_mode ? validated_dim_from_elements(cfg.elements) : 0u;
  const bool use_matrix_files =
      matrix_mode && !cfg.matrix_a_path.empty() && !cfg.matrix_b_path.empty();
  const std::optional<MatrixPreparedInputs> matrix_file_inputs =
      use_matrix_files ? std::make_optional(
                             prepare_matrix_inputs_from_files(cfg.matrix_a_path, cfg.matrix_b_path, dim))
                       : std::nullopt;
  const auto bytes = static_cast<std::uint64_t>(cfg.elements * sizeof(std::uint32_t));

  for (std::size_t iteration = 0; iteration < cfg.iterations; ++iteration) {
    auto row = base_row(cfg, iteration);
    const std::vector<std::uint32_t>* expected_ref = &expected;
    if (matrix_mode) {
      if (matrix_file_inputs.has_value()) {
        std::copy(
            matrix_file_inputs->padded_a.begin(), matrix_file_inputs->padded_a.end(), host_a.begin());
        std::copy(
            matrix_file_inputs->padded_b.begin(), matrix_file_inputs->padded_b.end(), host_b.begin());
        expected_ref = &matrix_file_inputs->expected;
      } else {
        fill_matrix_inputs(
            host_a.data(), host_b.data(), expected, cfg.elements, dim, cfg.seed, iteration);
      }
    } else {
      fill_vector_inputs(host_a.data(), host_b.data(), expected, cfg.elements, cfg.seed, iteration);
    }

    const auto t_total_start = Clock::now();

    const auto t_h2d_start = Clock::now();
    std::copy(host_a.begin(), host_a.end(), dev_a.begin());
    std::copy(host_b.begin(), host_b.end(), dev_b.begin());
    const auto t_h2d_end = Clock::now();

    const auto t_kernel_start = Clock::now();
    if (matrix_mode) {
      for (std::uint32_t i = 0; i < dim; ++i) {
        for (std::uint32_t j = 0; j < dim; ++j) {
          std::uint64_t acc = 0;
          for (std::uint32_t k = 0; k < dim; ++k) {
            acc += static_cast<std::uint64_t>(dev_a[i * dim + k]) *
                   static_cast<std::uint64_t>(dev_b[k * dim + j]);
          }
          dev_out[i * dim + j] = static_cast<std::uint32_t>(acc);
        }
      }
    } else {
      for (std::size_t i = 0; i < cfg.elements; ++i) {
        dev_out[i] = dev_a[i] + dev_b[i];
      }
    }
    const auto t_kernel_end = Clock::now();

    const auto t_d2h_start = Clock::now();
    std::copy(dev_out.begin(), dev_out.end(), host_out.begin());
    const auto t_d2h_end = Clock::now();

    const bool verify_ok = !cfg.verify || verify_outputs(*expected_ref, host_out.data(), cfg.elements);
    const auto t_total_end = Clock::now();

    row.h2d_ms = elapsed_ms(t_h2d_start, t_h2d_end);
    row.kernel_ms = elapsed_ms(t_kernel_start, t_kernel_end);
    row.d2h_ms = elapsed_ms(t_d2h_start, t_d2h_end);
    row.total_ms = elapsed_ms(t_total_start, t_total_end);
    row.verify_ok = verify_ok;
    row.throughput_gbps = throughput_gbps(cfg.elements, row.total_ms);

    if (cfg.control == ControlPath::Descriptor && matrix_mode) {
      const auto est = estimate_descriptor_counters(
          dim, dim, dim, row.tile_m, row.tile_n, row.tile_k, cfg.scheduler == SchedulerMode::HostTiled);
      row.kernel_invocations = est.kernel_invocations;
      row.tile_count = est.tile_count;
      row.est_load_cycles = est.est_load_cycles;
      row.est_compute_cycles = est.est_compute_cycles;
      row.est_store_cycles = est.est_store_cycles;
      row.est_total_cycles = est.est_total_cycles;
      row.bytes_h2d = (bytes * 2) + (row.kernel_invocations * (kCmdWords * sizeof(std::uint32_t))) +
                      (row.kernel_invocations * (kStatsWords * sizeof(std::uint64_t)));
      row.bytes_d2h = bytes + (row.kernel_invocations * (kStatsWords * sizeof(std::uint64_t)));
    } else {
      row.kernel_invocations = 1;
      row.tile_count = 1;
      row.bytes_h2d = bytes * 2;
      row.bytes_d2h = bytes;
    }

    rows.push_back(row);
  }

  return rows;
}

#if defined(U55C_ENABLE_XRT)
class DescriptorBuffers {
 public:
  DescriptorBuffers(const xrt::device& device, const xrt::kernel& kernel)
      : cmd_bo_(device, kCmdWords * sizeof(std::uint32_t), kernel.group_id(3)),
        stats_bo_(device, kStatsWords * sizeof(std::uint64_t), kernel.group_id(4)),
        cmd_ptr_(cmd_bo_.map<std::uint32_t*>()),
        stats_ptr_(stats_bo_.map<std::uint64_t*>()) {
    clear_all();
  }

  void clear_all() {
    std::fill(cmd_ptr_, cmd_ptr_ + kCmdWords, 0u);
    std::fill(stats_ptr_, stats_ptr_ + kStatsWords, 0ull);
  }

  void clear_stats() {
    std::fill(stats_ptr_, stats_ptr_ + kStatsWords, 0ull);
  }

  std::uint32_t* cmd() {
    return cmd_ptr_;
  }

  const std::uint64_t* stats() const {
    return stats_ptr_;
  }

  void sync_cmd_to_device() {
    cmd_bo_.sync(XCL_BO_SYNC_BO_TO_DEVICE);
  }

  void sync_stats_to_device() {
    stats_bo_.sync(XCL_BO_SYNC_BO_TO_DEVICE);
  }

  void sync_stats_from_device() {
    stats_bo_.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
  }

  xrt::bo& cmd_bo() {
    return cmd_bo_;
  }

  xrt::bo& stats_bo() {
    return stats_bo_;
  }

 private:
  xrt::bo cmd_bo_;
  xrt::bo stats_bo_;
  std::uint32_t* cmd_ptr_ = nullptr;
  std::uint64_t* stats_ptr_ = nullptr;
};

void fill_descriptor(std::uint32_t* cmd_words,
                     const std::uint32_t flags,
                     const std::uint32_t m,
                     const std::uint32_t n,
                     const std::uint32_t k,
                     const std::uint32_t lda,
                     const std::uint32_t ldb,
                     const std::uint32_t ldc,
                     const std::uint32_t a_offset_words,
                     const std::uint32_t b_offset_words,
                     const std::uint32_t c_offset_words,
                     const std::uint32_t tile_m,
                     const std::uint32_t tile_n,
                     const std::uint32_t tile_k) {
  std::fill(cmd_words, cmd_words + kCmdWords, 0u);
  cmd_words[CMD_MAGIC] = kCmdMagic;
  cmd_words[CMD_FLAGS] = flags;
  cmd_words[CMD_M] = m;
  cmd_words[CMD_N] = n;
  cmd_words[CMD_K] = k;
  cmd_words[CMD_LDA] = lda;
  cmd_words[CMD_LDB] = ldb;
  cmd_words[CMD_LDC] = ldc;
  cmd_words[CMD_A_OFFSET_WORDS] = a_offset_words;
  cmd_words[CMD_B_OFFSET_WORDS] = b_offset_words;
  cmd_words[CMD_C_OFFSET_WORDS] = c_offset_words;
  cmd_words[CMD_TILE_M] = sanitize_tile(tile_m);
  cmd_words[CMD_TILE_N] = sanitize_tile(tile_n);
  cmd_words[CMD_TILE_K] = sanitize_tile(tile_k);
}

void accumulate_stats(CounterTotals& totals, const std::uint64_t* stats_words) {
  totals.tile_count += stats_words[ST_TILE_COUNT];
  totals.est_load_cycles += stats_words[ST_LOAD_CYCLES];
  totals.est_compute_cycles += stats_words[ST_COMPUTE_CYCLES];
  totals.est_store_cycles += stats_words[ST_STORE_CYCLES];
  totals.est_total_cycles += stats_words[ST_TOTAL_CYCLES];
}

std::vector<BenchmarkRow> run_hardware(const BenchmarkConfig& cfg) {
  if (cfg.xclbin_path.empty()) {
    throw std::runtime_error("hardware mode requires --xclbin <path>");
  }

  if (cfg.elements > static_cast<std::size_t>(std::numeric_limits<std::uint32_t>::max())) {
    throw std::runtime_error("elements exceeds kernel arg width (uint32)");
  }

  std::vector<BenchmarkRow> rows;
  rows.reserve(cfg.iterations);

  const std::size_t bytes = cfg.elements * sizeof(std::uint32_t);
  const bool matrix_mode = is_matrix_kernel(cfg.kernel_name);
  const auto dim = matrix_mode ? validated_dim_from_elements(cfg.elements) : 0u;
  const bool use_matrix_files =
      matrix_mode && !cfg.matrix_a_path.empty() && !cfg.matrix_b_path.empty();
  const std::optional<MatrixPreparedInputs> matrix_file_inputs =
      use_matrix_files ? std::make_optional(
                             prepare_matrix_inputs_from_files(cfg.matrix_a_path, cfg.matrix_b_path, dim))
                       : std::nullopt;

  xrt::device device(cfg.device_index);
  auto uuid = device.load_xclbin(cfg.xclbin_path);
  xrt::kernel kernel(device, uuid, cfg.kernel_name);
  BufferManager buffers(device, kernel, bytes);

  std::vector<std::uint32_t> expected(cfg.elements);

  for (std::size_t iteration = 0; iteration < cfg.iterations; ++iteration) {
    auto row = base_row(cfg, iteration);
    const std::vector<std::uint32_t>* expected_ref = &expected;

    if (matrix_mode) {
      if (matrix_file_inputs.has_value()) {
        std::copy(matrix_file_inputs->padded_a.begin(),
                  matrix_file_inputs->padded_a.end(),
                  buffers.input_a());
        std::copy(matrix_file_inputs->padded_b.begin(),
                  matrix_file_inputs->padded_b.end(),
                  buffers.input_b());
        expected_ref = &matrix_file_inputs->expected;
      } else {
        fill_matrix_inputs(
            buffers.input_a(), buffers.input_b(), expected, cfg.elements, dim, cfg.seed, iteration);
      }
    } else {
      fill_vector_inputs(
          buffers.input_a(), buffers.input_b(), expected, cfg.elements, cfg.seed, iteration);
    }

    const auto t_total_start = Clock::now();

    const auto t_h2d_start = Clock::now();
    buffers.sync_inputs_to_device();
    const auto t_h2d_end = Clock::now();

    CounterTotals totals;

    const auto t_kernel_start = Clock::now();
    if (cfg.control == ControlPath::Descriptor) {
      if (!matrix_mode) {
        throw std::runtime_error("descriptor control path currently supports matrix kernels only");
      }

      DescriptorBuffers descriptor(device, kernel);
      descriptor.clear_all();

      if (cfg.scheduler == SchedulerMode::KernelTiled) {
        fill_descriptor(descriptor.cmd(),
                        kCmdFlagEnable,
                        dim,
                        dim,
                        dim,
                        dim,
                        dim,
                        dim,
                        0,
                        0,
                        0,
                        row.tile_m,
                        row.tile_n,
                        row.tile_k);
        descriptor.clear_stats();
        descriptor.sync_cmd_to_device();
        descriptor.sync_stats_to_device();

        auto run = kernel(buffers.input_a_bo(),
                          buffers.input_b_bo(),
                          buffers.output_bo(),
                          descriptor.cmd_bo(),
                          descriptor.stats_bo(),
                          dim);
        run.wait();
        descriptor.sync_stats_from_device();

        totals.kernel_invocations = 1;
        totals.bytes_h2d = (bytes * 2) + (kCmdWords * sizeof(std::uint32_t)) +
                           (kStatsWords * sizeof(std::uint64_t));
        totals.bytes_d2h = bytes + (kStatsWords * sizeof(std::uint64_t));
        accumulate_stats(totals, descriptor.stats());
      } else {
        for (std::uint32_t row0 = 0; row0 < dim; row0 += row.tile_m) {
          const auto rows_span = std::min(row.tile_m, dim - row0);
          for (std::uint32_t col0 = 0; col0 < dim; col0 += row.tile_n) {
            const auto cols_span = std::min(row.tile_n, dim - col0);
            bool accumulate = false;
            for (std::uint32_t k0 = 0; k0 < dim; k0 += row.tile_k) {
              const auto k_span = std::min(row.tile_k, dim - k0);
              const auto flags = static_cast<std::uint32_t>(
                  kCmdFlagEnable | kCmdFlagHostTiled | (accumulate ? kCmdFlagAccumulate : 0u));
              fill_descriptor(descriptor.cmd(),
                              flags,
                              rows_span,
                              cols_span,
                              k_span,
                              dim,
                              dim,
                              dim,
                              row0 * dim + k0,
                              k0 * dim + col0,
                              row0 * dim + col0,
                              rows_span,
                              cols_span,
                              k_span);
              descriptor.clear_stats();
              descriptor.sync_cmd_to_device();
              descriptor.sync_stats_to_device();

              auto run = kernel(buffers.input_a_bo(),
                                buffers.input_b_bo(),
                                buffers.output_bo(),
                                descriptor.cmd_bo(),
                                descriptor.stats_bo(),
                                dim);
              run.wait();
              descriptor.sync_stats_from_device();

              totals.kernel_invocations += 1;
              totals.bytes_h2d += (kCmdWords * sizeof(std::uint32_t)) +
                                  (kStatsWords * sizeof(std::uint64_t));
              totals.bytes_d2h += (kStatsWords * sizeof(std::uint64_t));
              accumulate_stats(totals, descriptor.stats());
              accumulate = true;
            }
          }
        }
        totals.bytes_h2d += bytes * 2;
        totals.bytes_d2h += bytes;
      }
    } else {
      auto run = matrix_mode
                     ? kernel(buffers.input_a_bo(),
                              buffers.input_b_bo(),
                              buffers.output_bo(),
                              dim)
                     : kernel(buffers.input_a_bo(),
                              buffers.input_b_bo(),
                              buffers.output_bo(),
                              static_cast<std::uint32_t>(cfg.elements));
      run.wait();

      totals.kernel_invocations = 1;
      totals.tile_count = 1;
      totals.bytes_h2d = bytes * 2;
      totals.bytes_d2h = bytes;
    }
    const auto t_kernel_end = Clock::now();

    const auto t_d2h_start = Clock::now();
    buffers.sync_output_from_device();
    const auto t_d2h_end = Clock::now();

    const bool verify_ok = !cfg.verify || verify_outputs(*expected_ref, buffers.output(), cfg.elements);
    const auto t_total_end = Clock::now();

    row.h2d_ms = elapsed_ms(t_h2d_start, t_h2d_end);
    row.kernel_ms = elapsed_ms(t_kernel_start, t_kernel_end);
    row.d2h_ms = elapsed_ms(t_d2h_start, t_d2h_end);
    row.total_ms = elapsed_ms(t_total_start, t_total_end);
    row.verify_ok = verify_ok;
    row.throughput_gbps = throughput_gbps(cfg.elements, row.total_ms);

    row.kernel_invocations = totals.kernel_invocations;
    row.tile_count = totals.tile_count;
    row.est_load_cycles = totals.est_load_cycles;
    row.est_compute_cycles = totals.est_compute_cycles;
    row.est_store_cycles = totals.est_store_cycles;
    row.est_total_cycles = totals.est_total_cycles;
    row.bytes_h2d = totals.bytes_h2d;
    row.bytes_d2h = totals.bytes_d2h;

    rows.push_back(row);
  }

  return rows;
}
#endif

}  // namespace

const char* run_mode_string(const RunMode mode) {
  switch (mode) {
    case RunMode::DryRun:
      return "dry-run";
    case RunMode::Hardware:
      return "hw";
    default:
      return "unknown";
  }
}

const char* control_path_string(const ControlPath control) {
  switch (control) {
    case ControlPath::Legacy:
      return "legacy";
    case ControlPath::Descriptor:
      return "descriptor";
    default:
      return "unknown";
  }
}

const char* scheduler_mode_string(const SchedulerMode scheduler) {
  switch (scheduler) {
    case SchedulerMode::KernelTiled:
      return "kernel-tiled";
    case SchedulerMode::HostTiled:
      return "host-tiled";
    default:
      return "unknown";
  }
}

std::vector<BenchmarkRow> run_benchmark(const BenchmarkConfig& cfg) {
  if (cfg.elements == 0) {
    throw std::runtime_error("elements must be > 0");
  }
  if (cfg.iterations == 0) {
    throw std::runtime_error("iterations must be > 0");
  }

  switch (cfg.mode) {
    case RunMode::DryRun:
      return run_dry_run(cfg);
    case RunMode::Hardware:
#if defined(U55C_ENABLE_XRT)
      return run_hardware(cfg);
#else
      throw std::runtime_error(
          "hardware mode requested, but this binary was built without XRT support");
#endif
    default:
      throw std::runtime_error("unsupported run mode");
  }
}

}  // namespace u55c_framework
