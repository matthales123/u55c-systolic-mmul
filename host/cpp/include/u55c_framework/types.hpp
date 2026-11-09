#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace u55c_framework {

enum class RunMode {
  DryRun,
  Hardware,
};

enum class ControlPath {
  Legacy,
  Descriptor,
};

enum class SchedulerMode {
  KernelTiled,
  HostTiled,
};

struct BenchmarkConfig {
  RunMode mode = RunMode::DryRun;
  ControlPath control = ControlPath::Legacy;
  SchedulerMode scheduler = SchedulerMode::KernelTiled;
  std::string xclbin_path;
  std::string kernel_name = "mmul";
  std::string matrix_a_path;
  std::string matrix_b_path;
  std::uint32_t device_index = 0;
  std::size_t elements = 1 << 20;
  std::size_t iterations = 10;
  bool verify = true;
  std::uint32_t seed = 1;
  std::uint32_t tile_m = 16;
  std::uint32_t tile_n = 16;
  std::uint32_t tile_k = 16;
};

struct BenchmarkRow {
  std::string timestamp_utc;
  std::string mode;
  std::string kernel;
  std::string control_path;
  std::string scheduler_mode;
  std::uint32_t device_index = 0;
  std::size_t elements = 0;
  std::size_t iteration = 0;
  bool verify_ok = false;
  double h2d_ms = 0.0;
  double kernel_ms = 0.0;
  double d2h_ms = 0.0;
  double total_ms = 0.0;
  double throughput_gbps = 0.0;
  std::uint32_t tile_m = 0;
  std::uint32_t tile_n = 0;
  std::uint32_t tile_k = 0;
  std::uint64_t kernel_invocations = 0;
  std::uint64_t tile_count = 0;
  std::uint64_t est_load_cycles = 0;
  std::uint64_t est_compute_cycles = 0;
  std::uint64_t est_store_cycles = 0;
  std::uint64_t est_total_cycles = 0;
  std::uint64_t bytes_h2d = 0;
  std::uint64_t bytes_d2h = 0;
};

const char* run_mode_string(RunMode mode);
const char* control_path_string(ControlPath control);
const char* scheduler_mode_string(SchedulerMode scheduler);

}  // namespace u55c_framework
