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

/**
 * test_vcache_stride
 *
 *
 */
#include "test_vcache_stride.h"

#define SETS 64
#define WAYS 8
#define BLOCK_SIZE 16*4

#define STRIDE_SIZE SETS*BLOCK_SIZE
#define DRAM_BASE 0x0000
#define NUM_STRIDES (WAYS*2)
#define NUM_DRAMS 16

int test_vcache_stride() {
        int rc;
        hb_mc_manycore_t mc = HB_MC_MANYCORE_INIT;
        const hb_mc_config_t *config;
        hb_mc_dimension_t dim;
        hb_mc_coordinate_t host, dest;
        hb_mc_idx_t host_x, host_y, dim_x, dim_y;
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

        /* To increase the number of DRAM banks tested, increase ndrams (must be
         * less than dim_x) and add the X coordinates to dim_x */
        int dram = 0, ndrams = NUM_DRAMS;
        hb_mc_idx_t dram_coord_y = hb_mc_config_get_dram_y(config);
        hb_mc_idx_t dram_coord_x = -1;
        hb_mc_epa_t epa;
        hb_mc_npa_t npa;
        int xidx, stride;
        uint32_t gold  [NUM_DRAMS][NUM_STRIDES] = {0};
        uint32_t result[NUM_DRAMS][NUM_STRIDES] = {0};
        uint32_t val;

        hb_mc_request_packet_t req;
        hb_mc_response_packet_t res;

        for (dram = 0; dram < ndrams; ++dram){
            for (stride = 0; stride < NUM_STRIDES; ++stride) {
                    gold[dram][stride] = rand();
            }
        }

        for (dram = 0; dram < ndrams; ++dram){
                dram_coord_x = dram;
                bsg_pr_test_info("Testing DRAM/Cache Interface Write at (%d, %d).\n", dram_coord_x, dram_coord_y);

                // for (stride = 0; stride < NUM_STRIDES; ++stride) {
                //         gold[stride] = rand();
                // }

                for (stride = 0; stride < NUM_STRIDES; ++stride) {
                        epa = DRAM_BASE + stride * STRIDE_SIZE;
                        dest = hb_mc_coordinate(dram_coord_x, dram_coord_y);
                        npa = hb_mc_epa_to_npa(dest, epa);
                        val = gold[dram][stride];

                        bsg_pr_test_info("%s -- Writing value %lu to 0x%x @ (%d, %d)\n",
                                        __func__, val, epa, dram_coord_x, dram_coord_y);
                        rc = hb_mc_manycore_write32(&mc, &npa, val);
                        if(rc != HB_MC_SUCCESS) {
                                bsg_pr_test_err("%s -- hb_mc_write32 failed on interation %d!\n", __func__, stride);
                                return HB_MC_FAIL;
                        }
                        val = ~val;
                }
        }
        for (dram = 0; dram < ndrams; ++dram){
                dram_coord_x = dram;
                bsg_pr_test_info("Testing DRAM/Cache Interface Read at (%d, %d).\n", dram_coord_x, dram_coord_y);
                for (stride = 0; stride < NUM_STRIDES; ++stride) {
                        epa = DRAM_BASE + stride * STRIDE_SIZE;
                        dest = hb_mc_coordinate(dram_coord_x, dram_coord_y);
                        npa = hb_mc_epa_to_npa(dest, epa);
                        rc = hb_mc_manycore_read32(&mc, &npa, &val);
                        if(rc != HB_MC_SUCCESS) {
                                bsg_pr_test_err("%s -- hb_mc_read32 failed on iteration %d!\n", __func__, stride);
                                return HB_MC_FAIL;
                        }
                        bsg_pr_test_info("%s -- Read value %lu from 0x%x @ (%d, %d)\n",
                                        __func__, val, epa, dram_coord_x, dram_coord_y);
                        result[dram][stride] = val;
                }
                for (stride = 0; stride < NUM_STRIDES; ++stride) {
                        if(result[dram][stride] != gold[dram][stride]){
                                bsg_pr_test_err("%s -- Index %d: Result, %lu, did not match expected, %lu!\n",
                                                __func__, stride, result[dram][stride], gold[dram][stride]);
                                return HB_MC_FAIL;
                        }
                }
                bsg_pr_test_info("%s -- %d Strides Passed\n", __func__, stride);
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
        bsg_pr_test_info("test_vcache_stride Regression Test (COSIMULATION)\n");
        int rc = test_vcache_stride();
        *exit_code = rc;
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return;
}
#else
int main(int argc, char ** argv) {
        bsg_pr_test_info("test_vcache_stride Regression Test (F1)\n");
        int rc = test_vcache_stride();
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return rc;
}
#endif
