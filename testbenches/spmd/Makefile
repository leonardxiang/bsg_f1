# Copyright (c) 2019, University of Washington All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
# 
# Redistributions of source code must retain the above copyright notice, this list
# of conditions and the following disclaimer.
# 
# Redistributions in binary form must reproduce the above copyright notice, this
# list of conditions and the following disclaimer in the documentation and/or
# other materials provided with the distribution.
# 
# Neither the name of the copyright holder nor the names of its contributors may
# be used to endorse or promote products derived from this software without
# specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# This (rather sparse) Makefile is responsible for building and
# running regression tests in cosimulation.  Run `make help` to see the
# available targets. (The target `help` is defined in compilation.mk)

# environment.mk verifies the build environment and sets the following
# makefile variables:
#
# TESTBENCH_PATH: The path to the testbench directory in the bsg_f1 repository
# LIBRAIRES_PATH: The path to the libraries directory in the bsg_f1 repository
# HARDARE_PATH: The path to the hardware directory in the bsg_f1 repository
# BASEJUMP_STL_DIR: Path to a clone of BaseJump STL
# BSG_MANYCORE_DIR: Path to a clone of BSG Manycore
# CL_DIR: Path to the directory of this AWS F1 Project
include ../../environment.mk

# The following variables are set by $(CL_DIR)/hdk.mk
#
# HDK_SHELL_DESIGN_DIR: Path to the directory containing all the AWS "shell" IP
# AWS_FPGA_REPO_DIR: Path to the clone of the aws-fpga repo
# HDK_COMMON_DIR: Path to HDK 'common' directory w/ libraries for cosimluation.
# SDK_DIR: Path to the SDK directory in the aws-fpga repo
include $(CL_DIR)/hdk.mk

# tests.mk defines all of the regression tests (and the source path)
# for this sub-directory.
include $(REGRESSION_PATH)/spmd/tests.mk

# The HDK Makefile must come before compilation.mk to override AWS' (broken) clean
# HDK_COMMON_DIR is set by running `source hdk_setup.sh` from the aws-fpga repository
include $(HDK_COMMON_DIR)/verif/tb/scripts/Makefile.common.inc

# EXEC_PATH defines this directory, where the tests are actually
# executed. REGRESSION_TESTS_TYPE is defined by tests.mk in each regression
# sub-directory.
EXEC_PATH=$(TESTBENCH_PATH)/$(REGRESSION_TESTS_TYPE)

# cosimulation.mk defines all of the re-used rules for cosimulation. 
# (e.g. regression, clean, help, etc)
include $(TESTBENCH_PATH)/cosimulation.mk

# rules.mk defines rules for building RISC-V binaries associated with
# the tests in this sub-directory. rules.mk must come after
# compilation.mk so that <test_name>.rule and <test_name>.clean are
# not overwritten.
include $(REGRESSION_PATH)/$(REGRESSION_TESTS_TYPE)/rules.mk

# All SPMD programs require two arguments: The path to the RISC-V Binary loaded onto the manycore
# (TEST_PATH), and the test name (TEST_NAME). SPMD_PATH is defined for convenience
SPMD_PATH=$(BSG_MANYCORE_DIR)/software/spmd
$(EXEC_PATH)/%.log: TEST_PATH=$(SPMD_PATH)/$(subst test_,,$(TEST_NAME))/main.riscv
$(EXEC_PATH)/%.log: TEST_NAME=$(subst .log,,$(notdir $@))

# The rule below defines how to run test_loader for SPMD tests. The loader
# requires two arguments:
$(EXEC_PATH)/%.log: $(EXEC_PATH)/test_loader %.rule
	$< 2>&1 +ntb_random_seed_automatic +vpdfile+$(@:.log=.vpd) $(SIM_ARGS) \
		+c_args="$(TEST_PATH) $(TEST_NAME)" | tee $@

# The rule below defines how to run SPMD tests that do not use
# test_loader. The output .vpd file will be named <test_name>.vpd. To
# generate a trace file, run `make <test_name>.vanilla.log`
INDEPENDENT_LOGS=$(foreach tgt, $(INDEPENDENT_TESTS), $(EXEC_PATH)/$(tgt).log)
$(INDEPENDENT_LOGS): $(EXEC_PATH)/%.log: $(EXEC_PATH)/% %.rule
	$< 2>&1 +ntb_random_seed_automatic +vpdfile+$(@:.log=.vpd) $(SIM_ARGS) \
		+c_args="$(TEST_PATH) $(TEST_NAME)" | tee $@

# dve.mk defines the dve targets
include $(TESTBENCH_PATH)/dve.mk
