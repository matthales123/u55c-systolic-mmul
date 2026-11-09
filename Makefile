SHELL := /usr/bin/env bash

.PHONY: bootstrap check host correctness bench plot hls_xclbin rtl_project

bootstrap:
	./scripts/bootstrap_deps.sh

check:
	./scripts/check_setup.sh

host:
	./scripts/build_host.sh

correctness:
	./scripts/run_correctness.sh

bench:
	./scripts/run_benchmark_sweep.sh

plot:
	python3 host/python/plot_results.py --csv $${CSV:-results/benchmark_latest.csv} --out $${OUT:-results/benchmark_latest.png}

hls_xclbin:
	$(MAKE) -C hardware/hls xclbin \
		PLATFORM=$${U55C_PLATFORM:-xilinx_u55c_gen3x16_xdma_3_202210_1} \
		TARGET=$${TARGET:-hw} \
		KERNEL_NAME=$${U55C_KERNEL_NAME:-mmul} \
		ENABLE_EXPLICIT_HBM_MAP=$${U55C_ENABLE_EXPLICIT_HBM_MAP:-1} \
		HBM_BANK_A=$${U55C_HBM_BANK_A:-HBM[0]} \
		HBM_BANK_B=$${U55C_HBM_BANK_B:-HBM[1]} \
		HBM_BANK_C=$${U55C_HBM_BANK_C:-HBM[2]}

rtl_project:
	./hardware/rtl/run_vivado.sh

# Shared verification flow; stage artifacts stay under results/verification/.
FPGA_FLOW ?= ../fpga-verification-tools/verification/flow.py
SEEDS ?= 381,7331
.PHONY: verify verify_uvm verify_formal verify_axi verification_doctor
verify:
	python3 $(FPGA_FLOW) run --project . --profile verify --seeds $(SEEDS)

verify_uvm:
	python3 $(FPGA_FLOW) run --project . --profile uvm --seeds $(SEEDS)

verify_formal:
	python3 $(FPGA_FLOW) run --project . --profile formal --seeds $(SEEDS)

verify_axi:
	python3 $(FPGA_FLOW) run --project . --profile axi --seeds $(SEEDS)

verification_doctor:
	python3 $(FPGA_FLOW) doctor --project .
