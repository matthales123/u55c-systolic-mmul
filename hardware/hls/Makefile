SHELL := /usr/bin/env bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
BUILD_DIR ?= $(ROOT_DIR)/build/hardware/$(TARGET)
PROJECT_NAME ?= $(notdir $(ROOT_DIR))
KERNEL_NAME ?= mmul
TARGET ?= hw
PLATFORM ?= xilinx_u55c_gen3x16_xdma_3_202210_1
SRC := $(ROOT_DIR)/hardware/hls/src/$(KERNEL_NAME).cpp
XO := $(BUILD_DIR)/$(KERNEL_NAME).xo
XCLBIN := $(BUILD_DIR)/$(KERNEL_NAME).xclbin
CONNECTIVITY_CFG := $(BUILD_DIR)/$(KERNEL_NAME)_connectivity.cfg
DASHBOARD_XCLBIN_DIR ?= $(HOME)/.local/share/fpga-dashboard-web/artifacts/xclbin
DASHBOARD_XCLBIN := $(DASHBOARD_XCLBIN_DIR)/$(PROJECT_NAME)_$(KERNEL_NAME)_$(TARGET).xclbin
DASHBOARD_LTX := $(DASHBOARD_XCLBIN:.xclbin=.ltx)
LINK_HOOK_SCRIPT := $(ROOT_DIR)/hardware/hls/scripts/u55c_clk_metadata_adapter_workaround.tcl
LINK_HOOK_ARGS :=
ENABLE_EXPLICIT_HBM_MAP ?= 1
HBM_BANK_A ?= HBM[0]
HBM_BANK_B ?= HBM[1]
HBM_BANK_C ?= HBM[2]
HBM_BANK_CMD ?= HBM[3]
HBM_BANK_STATS ?= HBM[4]
LINK_CFG_ARGS :=

ifeq ($(TARGET),hw)
LINK_HOOK_ARGS += --linkhook.custom "postSysLink,$(LINK_HOOK_SCRIPT)"
endif

ifneq ($(ENABLE_EXPLICIT_HBM_MAP),0)
LINK_CFG_ARGS += --config $(CONNECTIVITY_CFG)
XCLBIN_DEPS := $(XO) $(CONNECTIVITY_CFG)
else
XCLBIN_DEPS := $(XO)
endif

.PHONY: all xo xclbin publish clean

all: xclbin

xo: $(XO)

xclbin: $(XCLBIN)

$(XO): $(SRC)
	@mkdir -p $(BUILD_DIR)
	v++ -c -t $(TARGET) --platform $(PLATFORM) -k $(KERNEL_NAME) $< -o $@

$(CONNECTIVITY_CFG):
	@mkdir -p $(BUILD_DIR)
	@{ \
		echo "[connectivity]"; \
		echo "sp=$(KERNEL_NAME)_1.a:$(HBM_BANK_A)"; \
		echo "sp=$(KERNEL_NAME)_1.b:$(HBM_BANK_B)"; \
		echo "sp=$(KERNEL_NAME)_1.c:$(HBM_BANK_C)"; \
		if [[ "$(KERNEL_NAME)" == "mmul_cmd" ]]; then \
			echo "sp=$(KERNEL_NAME)_1.cmd:$(HBM_BANK_CMD)"; \
			echo "sp=$(KERNEL_NAME)_1.stats:$(HBM_BANK_STATS)"; \
		fi; \
	} > "$@"
	@echo "Generated connectivity map: $@"

$(XCLBIN): $(XCLBIN_DEPS)
	v++ -l -t $(TARGET) --platform $(PLATFORM) $(LINK_HOOK_ARGS) $(LINK_CFG_ARGS) $(XO) -o $@
	@$(MAKE) publish TARGET=$(TARGET) KERNEL_NAME=$(KERNEL_NAME) PLATFORM=$(PLATFORM)

publish:
	@test -f "$(XCLBIN)" || { echo "ERROR: xclbin not found: $(XCLBIN)"; exit 1; }
	@mkdir -p "$(DASHBOARD_XCLBIN_DIR)"
	cp -f "$(XCLBIN)" "$(DASHBOARD_XCLBIN)"
	@if [[ -f "$(BUILD_DIR)/$(KERNEL_NAME).ltx" ]]; then cp -f "$(BUILD_DIR)/$(KERNEL_NAME).ltx" "$(DASHBOARD_LTX)"; fi
	@echo "Published dashboard artifact: $(DASHBOARD_XCLBIN)"

clean:
	rm -rf $(ROOT_DIR)/build/hardware
