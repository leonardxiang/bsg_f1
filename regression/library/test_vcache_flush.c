// Copyright (c) 2019, University of Washington All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
// Redistributions of source code must retain the above copyright notice, this list
// of conditions and the following disclaimer.
// 
// Redistributions in binary form must reproduce the above copyright notice, this
// list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
// 
// Neither the name of the copyright holder nor the names of its contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include <bsg_manycore_npa.h>
#include "test_vcache_flush.h"

#define NUM_TESTS 2
// TODO: Make these not hard coded (for example, define them from the Makefile
// as read from the verilog parameters)
#define NUM_SETS 64
#define ASSOCIATIVITY 8
#define CACHE_LINE_SIZE_WORDS 8
#define WORD_SIZE sizeof(uint32_t)
#define CACHE_LINE_SIZE (CACHE_LINE_SIZE_WORDS * WORD_SIZE)
#define ADDR_MASK ((1llu << 32) - 1)

int flush_cache_line(hb_mc_manycore_t *mc, hb_mc_epa_t addr, hb_mc_idx_t x, hb_mc_idx_t y)
{
	int rc;
	hb_mc_npa_t npa;
	hb_mc_epa_t flush_addr;
	hb_mc_coordinate_t dest = hb_mc_coordinate(x,y);
	uint64_t stride;
	uint32_t result;

        for(int i = 1; i <= ASSOCIATIVITY; i++)
        {
		stride = i * NUM_SETS * CACHE_LINE_SIZE;
                flush_addr = (hb_mc_epa_t)(((uint64_t)addr + stride) & ADDR_MASK); 
		npa = hb_mc_epa_to_npa(dest, flush_addr);

		rc = hb_mc_manycore_read32(mc, &npa, &result);
		bsg_pr_test_info("%s -- Sending read command to address 0x%x at tile"
				" (%d, %d).\n", __func__, flush_addr, x, y);
		if(rc != HB_MC_SUCCESS) {
			bsg_pr_test_err("%s -- hb_mc_read32 failed!\n", __func__);
			return HB_MC_FAIL;
		}
        }
        return HB_MC_SUCCESS;
}

int test_address(hb_mc_manycore_t *mc, hb_mc_epa_t addr, uint32_t data, hb_mc_idx_t x, hb_mc_idx_t y) {
	int rc;
	hb_mc_coordinate_t dest = hb_mc_coordinate(x,y);
	hb_mc_npa_t npa;
	uint32_t result;

        bsg_pr_test_info("Testing Address 0x%x at (%d, %d) with data: 0x%x\n",
			addr, x, y, data);

        bsg_pr_test_info("Sending write command to address 0x%x at tile (%d, %d)\n", 
			addr, x, y);

	npa = hb_mc_epa_to_npa(dest, addr);
	rc = hb_mc_manycore_write32(mc, &npa, data);
	if(rc != HB_MC_SUCCESS) {
		bsg_pr_test_err("%s -- hb_mc_write32 failed!\n", __func__);
		return HB_MC_FAIL;
	}
        
        bsg_pr_test_info("%s -- Sending read command to address 0x%x at tile"
			" (%d, %d). (It should be in VCache.)\n", 
			__func__, addr, x, y);
	rc = hb_mc_manycore_read32(mc, &npa, &result);
	if(rc != HB_MC_SUCCESS) {
		bsg_pr_test_err("%s -- hb_mc_read32 failed!\n", __func__);
		return HB_MC_FAIL;
	}

        if(result != data) {
		bsg_pr_test_err("%s -- Incorrect data read from Victim Cache!. "
				"Got %lu, but expected %lu\n", 
				__func__, result, data);
                return HB_MC_FAIL;
        }

        
        bsg_pr_test_info("%s -- Flushing cache line\n", __func__);
	rc = flush_cache_line(mc, addr, x, y);
        if(rc != HB_MC_SUCCESS)
                return HB_MC_FAIL;
        
        bsg_pr_test_info("%s -- Sending read command to address 0x%x at tile"
			" (%d, %d). (It should be in DRAM.)\n", 
			__func__, addr, x, y);
        
	result = ~result;
	rc = hb_mc_manycore_read32(mc, &npa, &result);
	if(rc != HB_MC_SUCCESS) {
		bsg_pr_test_err("%s -- hb_mc_read32 failed!\n", __func__);
		return HB_MC_FAIL;
	}

        if(result != data) {
		bsg_pr_test_err("%s -- Incorrect data read from DRAM!. "
				"Got %lu, but expected %lu\n",
				__func__, result, data);
                return HB_MC_FAIL;
        }

        return HB_MC_SUCCESS;
}

int test_vcache_flush() {
	int rc, i;
	hb_mc_manycore_t mc = HB_MC_MANYCORE_INIT;
	const hb_mc_config_t *config;
	hb_mc_dimension_t dim;
	hb_mc_coordinate_t host, dest;
	hb_mc_idx_t host_x, host_y, dim_x, dim_y;

	uint32_t addr_bitwidth, data;
	hb_mc_epa_t addrs[NUM_TESTS];
	hb_mc_epa_t addr;
	srand(time(0));

	rc = hb_mc_manycore_init(&mc, "manycore@test_vcache_stride", 0);
	if(rc != HB_MC_SUCCESS){
		bsg_pr_test_err("Failed to initialize manycore device!\n");
		return HB_MC_FAIL;
	}

	config = hb_mc_manycore_get_config(&mc);

	host = hb_mc_config_get_host_interface(config);
	host_x = hb_mc_coordinate_get_x(host);
	host_y = hb_mc_coordinate_get_y(host);

	dim = hb_mc_config_get_dimension_network(config);
	dim_x = hb_mc_dimension_get_x(dim);
	dim_y = hb_mc_dimension_get_y(dim);

	int dram = 0, ndrams = 1;
	hb_mc_idx_t dram_coord_y = hb_mc_config_get_dram_y(config);
	hb_mc_idx_t dram_coord_x = -1;
	hb_mc_idx_t dram_xs[dim_x];
	dram_xs[0] = 0;

	addr_bitwidth = hb_mc_config_get_network_bitwidth_addr(config);
        addrs[0] = 0;
        addrs[1] = 1 << (addr_bitwidth-2); // Convert to word-level addr

        data = rand();

	for (dram = 0; dram < ndrams; ++dram){
		dram_coord_x = dram_xs[dram];
		for(i = 0; i < NUM_TESTS; ++i){
			addr = addrs[i];
			rc = test_address(&mc, addr, data, dram_coord_x, dram_coord_y);
		}
		if(rc != HB_MC_SUCCESS)
			return rc;
	}
	return HB_MC_SUCCESS;
}

#ifdef COSIM
void cosim_main(uint32_t *exit_code, char * args) {
	// We aren't passed command line arguments directly so we parse them
	// from *args. args is a string from VCS - to pass a string of arguments
	// to args, pass c_args to VCS as follows: +c_args="<space separated
	// list of args>"
	int argc = get_argc(args);
	char *argv[argc];
	get_argv(args, argc, argv);

#ifdef VCS
	svScope scope;
	scope = svGetScopeFromName("tb");
	svSetScope(scope);
#endif
	bsg_pr_test_info("test_vcache_flush Regression Test (COSIMULATION)\n");
	int rc = test_vcache_flush();
	*exit_code = rc;
	bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
	return;
}
#else
int main(int argc, char ** argv) {
	bsg_pr_test_info("test_vcache_flush Regression Test (F1)\n");
	int rc = test_vcache_flush();
	bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
	return rc;
}
#endif
