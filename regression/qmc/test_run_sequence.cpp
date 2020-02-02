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

#include "../../libraries/bsg_manycore.h"
#include <bsg_manycore_npa.h>
#include <bsg_manycore_printing.h>
// #include <cinttypes.h>
// #include <type_traits>
#include "test_run_sequence.hpp"

#define TEST_NAME "test_run_sequence"
#define WORD_SIZE 4

int test_run_sequence () {
        hb_mc_manycore_t manycore = {0}, *mc = &manycore;
        int err, r = HB_MC_FAIL;


        /********/
        /* INIT */
        /********/
        err = hb_mc_manycore_init(mc, TEST_NAME, 0);
        if (err != HB_MC_SUCCESS) {
                bsg_pr_err("%s: failed to initialize manycore: %s\n",
                           __func__, hb_mc_strerror(err));
                return HB_MC_FAIL;
        }


        /**************************/
        /* Writing to QMC NODE CSR*/
        /**************************/
        uint32_t csr_data[QCL_CSR_BYTES/WORD_SIZE] = {};

        csr_data[0] = 0x00000103;  // auto start mode
        csr_data[(QCL_CSR_BYTES-1)/WORD_SIZE] = 0xFFFFFFFF;

        csr_data[3] = 0x00000000;
        csr_data[4] = 0x00001000;  // 4us
        hb_mc_npa_t npa = { .x = 0, .y = 1, .epa = QCL_CSR_BASE };

        bsg_pr_test_info("Writing to DMEM\n");
        for (int i = 0; i < sizeof(csr_data)/WORD_SIZE; i++) {
            printf("%x\n", 0xFF&(csr_data[i]>>0*8));
            printf("%x\n", 0xFF&(csr_data[i]>>1*8));
            printf("%x\n", 0xFF&(csr_data[i]>>2*8));
            printf("%x\n", 0xFF&(csr_data[i]>>3*8));
        }
        err = hb_mc_manycore_write_mem(mc, &npa, &csr_data, sizeof(csr_data));
        if (err != HB_MC_SUCCESS) {
                bsg_pr_err("%s: failed to write to manycore DMEM: %s\n",
                           __func__,
                           hb_mc_strerror(err));
                goto cleanup;
        }

        // delay by writing null packets
        csr_data[0] = 0;
        for (int i = 0; i < 100; i++) {
            err = hb_mc_manycore_write_mem(mc, &npa, &csr_data, sizeof(csr_data));
            if (err != HB_MC_SUCCESS) {
                    bsg_pr_err("%s: failed to write to manycore DMEM: %s\n",
                               __func__,
                               hb_mc_strerror(err));
                    goto cleanup;
            }
            bsg_pr_test_info("Write No. %d successful\n", i);
        }
        r = err;

         /**************************/
         /* Read from QMC NODE CSR */
         /**************************/
        // uint32_t read_data;
        // err = hb_mc_manycore_read_mem(mc, &npa, &read_data, sizeof(read_data));
        // if (err != HB_MC_SUCCESS) {
        //         bsg_pr_err("%s: failed to read from manycore DMEM: %s\n",
        //                    __func__,
        //                    hb_mc_strerror(err));
        //         goto cleanup;
        // }

        // bsg_pr_test_info("Completed read\n");
        // if (read_data == csr_data) {
        //         bsg_pr_test_info("Read back data written: 0x%08" PRIx32 "\n",
        //                          read_data);
        // } else {
        //         bsg_pr_test_info("Data mismatch: read 0x%08" PRIx32 ", wrote 0x%08" PRIx32 "\n",
        //                          read_data, csr_data);
        // }
        // r = (read_data == csr_data ? HB_MC_SUCCESS : HB_MC_FAIL);

        /*******/
        /* END */
        /*******/
cleanup:
        hb_mc_manycore_exit(mc);
        return r;
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
        bsg_pr_test_info(TEST_NAME " Regression Test (COSIMULATION)\n");
        int rc = test_run_sequence();
        *exit_code = rc;
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return;
}
#else
int main(int argc, char ** argv) {
        bsg_pr_test_info(TEST_NAME " Regression Test (F1)\n");
        int rc = test_run_sequence();
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return rc;
}
#endif
