#include "u55c_framework/csv_logger.hpp"

#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace u55c_framework {
namespace {

const char* kCsvHeader =
    "timestamp_utc,mode,kernel,control_path,scheduler_mode,device,elements,iteration,verify_ok,h2d_ms,kernel_ms,d2h_ms,total_ms,throughput_gbps,tile_m,tile_n,tile_k,kernel_invocations,tile_count,est_load_cycles,est_compute_cycles,est_store_cycles,est_total_cycles,bytes_h2d,bytes_d2h";

std::string escape_csv(std::string value) {
  bool needs_quotes = false;
  for (const char ch : value) {
    if (ch == ',' || ch == '"' || ch == '\n') {
      needs_quotes = true;
      break;
    }
  }

  if (!needs_quotes) {
    return value;
  }

  std::string escaped;
  escaped.reserve(value.size() + 2);
  escaped.push_back('"');
  for (const char ch : value) {
    if (ch == '"') {
      escaped.push_back('"');
    }
    escaped.push_back(ch);
  }
  escaped.push_back('"');
  return escaped;
}

void write_header(std::ofstream& out) {
  out << kCsvHeader << '\n';
}

void write_row(std::ofstream& out, const BenchmarkRow& row) {
  out
      << escape_csv(row.timestamp_utc) << ','
      << escape_csv(row.mode) << ','
      << escape_csv(row.kernel) << ','
      << escape_csv(row.control_path) << ','
      << escape_csv(row.scheduler_mode) << ','
      << row.device_index << ','
      << row.elements << ','
      << row.iteration << ','
      << (row.verify_ok ? 1 : 0) << ','
      << row.h2d_ms << ','
      << row.kernel_ms << ','
      << row.d2h_ms << ','
      << row.total_ms << ','
      << row.throughput_gbps << ','
      << row.tile_m << ','
      << row.tile_n << ','
      << row.tile_k << ','
      << row.kernel_invocations << ','
      << row.tile_count << ','
      << row.est_load_cycles << ','
      << row.est_compute_cycles << ','
      << row.est_store_cycles << ','
      << row.est_total_cycles << ','
      << row.bytes_h2d << ','
      << row.bytes_d2h << '\n';
}

}  // namespace

void append_rows_csv(const std::string& path, const std::vector<BenchmarkRow>& rows) {
  if (rows.empty()) {
    return;
  }

  const std::filesystem::path csv_path(path);
  const auto parent = csv_path.parent_path();
  if (!parent.empty()) {
    std::filesystem::create_directories(parent);
  }

  bool rewrite_file = false;
  bool write_header_line = false;
  if (!std::filesystem::exists(csv_path) || std::filesystem::file_size(csv_path) == 0) {
    write_header_line = true;
  } else {
    std::ifstream in(path);
    std::string header;
    std::getline(in, header);
    if (header != kCsvHeader) {
      rewrite_file = true;
      write_header_line = true;
    }
  }

  std::ofstream out(path, rewrite_file ? std::ios::trunc : std::ios::app);
  if (!out) {
    throw std::runtime_error("failed to open CSV file: " + path);
  }

  if (write_header_line) {
    write_header(out);
  }

  for (const auto& row : rows) {
    write_row(out, row);
  }
}

}  // namespace u55c_framework
