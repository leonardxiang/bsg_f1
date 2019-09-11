SPMD_SRC_PATH = $(BSG_MANYCORE_DIR)/software/spmd/
CUDALITE_SRC_PATH = $(SPMD_SRC_PATH)/bsg_cuda_lite_runtime/

.PHONY: help

help:
	@echo "To make a specific test run: make <testname> and then execute the resulting binary"

$(USER_RULES): test_%.rule: $(CUDALITE_SRC_PATH)/%/main.riscv

$(USER_CLEAN_RULES):
	CL_DIR=$(CL_DIR) \
	BSG_MANYCORE_DIR=$(BSG_MANYCORE_DIR) \
	BASEJUMP_STL_DIR=$(BASEJUMP_STL_DIR) \
	BSG_IP_CORES_DIR=$(BASEJUMP_STL_DIR) \
	IGNORE_CADENV=1 \
	BSG_MACHINE_PATH=$(BSG_MACHINE_PATH) \
	$(MAKE) -C $(CUDALITE_SRC_PATH)/$(subst .clean,,$(subst test_,,$@)) clean

$(CUDALITE_SRC_PATH)/%/main.riscv: $(CL_DIR)/Makefile.machine.include
	CL_DIR=$(CL_DIR) \
	BSG_MANYCORE_DIR=$(BSG_MANYCORE_DIR) \
	BASEJUMP_STL_DIR=$(BASEJUMP_STL_DIR) \
	BSG_IP_CORES_DIR=$(BASEJUMP_STL_DIR) \
	IGNORE_CADENV=1 \
	BSG_MACHINE_PATH=$(BSG_MACHINE_PATH) \
	bsg_tiles_X=$(TILE_GROUP_DIM_X) \
	bsg_tiles_Y=$(TILE_GROUP_DIM_Y) \
	$(MAKE) -C $(dir $@) clean $(notdir $@)