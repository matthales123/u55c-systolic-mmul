# U55C Systolic Matrix Multiplication

Cornell SysBase RTL adapted to AMD Alveo U55C with an AXI kernel wrapper, checked
host, SystemVerilog/UVM tests and scoped formal checks. An older HLS matrix
multiplication path and its local web interface are also included. They are
distinct implementations; the HLS benchmark is not evidence for SysBase.

## Verified result — November 8, 2026

The original source-tree release completed with **PASS**: UVM seeds **381 and
7331**, AXI wrapper simulation, **15 formal checks** (including expected-failure
controls/replays), and **48 actual U55C runs** across dimensions **1–8**. The
SysBase pilot uses `ARRAY_SIZE=4`, `MAX_DIM=8`, and 32-bit modular arithmetic.
At the 150 MHz target, reported routed setup/hold slack was **+0.003/+0.009 ns**.
Coverage gaps and model assumptions remain: this is neither complete coverage
closure nor a proof of all matrix sizes/arithmetic. Raw evidence stays private.
Each positive UVM seed completed 68 operations and exercised four reset-aborted
operations with zero mismatches, UVM errors or assertion failures.
These are historical results from the original tree, not a claim that every
source-export packaging change has been rerun on hardware.

## Run source verification

Load Vivado 2025.1 for XSim/UVM, then run the project-local drivers directly.
These simulation commands do not require access to the private shared tooling:

```bash
python3 verification/uvm/run.py --output-dir results/uvm-381 --seed 381
python3 verification/uvm/run.py --output-dir results/uvm-7331 --seed 7331
python3 verification/hardware/kernel/simulate.py --output-dir results/axi
```

Use fresh output directories for each run. Results are generated locally and are
excluded from this repository.

The formal harnesses and project-specific formal driver are included as source.
The integrated `make verify`, `make verify_formal`, and `make verification_doctor`
commands additionally require the private `fpga-verification-tools` checkout and
its pinned formal-tool installation. With authorized access, clone it beside this
repository and use `FPGA_FLOW` / `FPGA_TOOLS_ROOT` for another location. The
historical formal results above do not imply that this public checkout includes
that private orchestration/tool-installation layer.

## Build and run hardware

```bash
python3 verification/hardware/kernel/build.py --help
python3 verification/hardware/run.py --help
make host
make hls_xclbin
./scripts/run_webapp_mmul.sh
```

The SysBase physical assessment/release commands require their private,
hash-checked platform evidence bundle and corresponding provenance. That bundle
contains vendor material and is deliberately not published. The public scripts
retain the checks and fail if the evidence is absent; source simulation/formal
verification above does not require this bundle. Recreating platform evidence on
another installation requires a new reviewed policy/provenance, not reused hashes.
`make hls_xclbin` builds the separate HLS path; the web app defaults to port 9890.

Cornell-derived sources retain their original notices. Original course project:
https://github.com/matthales123/ece5745-systolic-matmul

## Requirements

For FPGA builds, install AMD Vitis/Vivado 2025.1, XRT, and the compatible
`xilinx_u55c_gen3x16_xdma_3_202210_1` platform. Source your installation's
`settings64.sh` and XRT setup script before building. Python 3, a C++ compiler,
CMake and Make are required for the host/tooling. Run commands from this repository.
Keep the checkout path free of spaces for Vitis HLS.

The source includes host programs, HDL/HLS, tests and local web tooling. Generated
builds, debugging sessions, reports and results are excluded from this public copy.
Web applications are local development interfaces with hardware controls; public
Internet demo access is a separate future deployment.
