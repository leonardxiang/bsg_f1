DESIGN_NAME := qmc_runner

VSOURCES := $(filter-out $(HARDWARE_PATH)/$(CL_TOP_MODULE).sv,$(VSOURCES))

# replace the top module
CL_TOP_MODULE = $(DESIGN_NAME)
VSOURCES += $(HARDWARE_PATH)/../machines/$(CL_TOP_MODULE)/$(CL_TOP_MODULE).v

VSOURCES := $(filter-out $(HARDWARE_PATH)/bsg_manycore_wrapper.v,$(VSOURCES))
VSOURCES += $(HARDWARE_PATH)/../machines/$(CL_TOP_MODULE)/qmc_group_wrapper.v

# VSOURCES := $(filter-out $(BSG_MANYCORE_DIR)/v/bsg_manycore_proc_vanilla.v,$(VSOURCES))
VSOURCES += $(HARDWARE_PATH)/../machines/$(CL_TOP_MODULE)/qcl_meshnode_subgroup.v

VSOURCES := $(filter-out $(BSG_MANYCORE_DIR)/v/bsg_manycore_tile.v,$(VSOURCES))

# for rtl simulation
# VSOURCES += $(BASEJUMP_STL_DIR)/bsg_test/bsg_nonsynth_clock_gen.v
# VSOURCES += $(BASEJUMP_STL_DIR)/bsg_test/bsg_nonsynth_reset_gen.v
VSOURCES += $(BASEJUMP_STL_DIR)/bsg_test/bsg_trace_replay.v
VSOURCES += $(QCL_REPO_DIR)/designs/$(DESIGN_NAME)/enet_trace_rom.v
