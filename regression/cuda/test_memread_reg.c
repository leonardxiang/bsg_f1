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

#include "test_memread_reg.h"


/*
 * Runs a variety of tests to study the bottlenecks associated with
 * cores reading data from memory locations in the system. The kernel
 * is a loop that looks approximately like this:
 *
 * int  __attribute__ ((noinline)) kernel_memread_reg_base(volatile int *src,
 *                                                        size_t nels, int *res) {
 *        // Load all the data (but drop it on the floor)
 *        for (size_t ei = 0; ei < nels; ++ei) {
 *                src[ei];
 *        }
 *        // Store the last value in the array into res to demonstrate
 *        // that the program executed successfully.
 *        *res = src[nels - 1];
 *        bsg_tile_group_barrier (&r_barrier, &c_barrier);
 *        return 0;
 *}
 *
 * The kernel can be executed on multiple tiles within a tile group,
 * but they will all read from the same pointer.
 */
#define ALLOC_NAME "default_allocator"
// RD_BUFFER_SZ is the number of bytes in the buffer read by the
// kernel.
#define RD_BUFFER_SZ 1024
#define NUM_RUNS 5
// read_t is the type that the kernel will be reading
typedef int read_t;

void bsg_timer(uint64_t *time, uint64_t *duration){
        static uint64_t start_ns = 0;
        uint64_t stop_ns;

#ifdef COSIM
        sv_bsg_time(&stop_ns);
        stop_ns = stop_ns / 1000;
#else
        stop_ns = bsg_utc() * 1000;
#endif
        *duration = stop_ns - start_ns;
        *time = stop_ns;
        start_ns = stop_ns;
}

int kernel_memread_reg (int argc, char **argv) {
        int rc;
        char *bin_path, *test_name;
        struct arguments_path args = {NULL, NULL};

        argp_parse (&argp_path, argc, argv, 0, 0, &args);
        bin_path = args.path;
        test_name = args.name;

        bsg_pr_test_info("Running CUDA Memory Read Tests.\n");

        srand(time);

        hb_mc_device_t device;

        size_t nels = RD_BUFFER_SZ/(sizeof(read_t));
        read_t src[nels];
        read_t res;
        eva_t src_eva;
        eva_t res_eva;
        uint64_t duration, timer;
        // Initialize device, load binary and unfreeze tiles.
        rc = hb_mc_device_init(&device, test_name, 0);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize device.\n");
                return rc;
        }

        rc = hb_mc_device_program_init(&device, bin_path, ALLOC_NAME, 0);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize program.\n");
                return rc;
        }

        // Allocate a the read buffer on the device
        rc = hb_mc_device_malloc(&device, RD_BUFFER_SZ, &src_eva);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to allocate memory on device.\n");
                return rc;
        }

        // Allocate a the result buffer on the device
        rc = hb_mc_device_malloc(&device, sizeof(read_t), &res_eva);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to allocate memory on device.\n");
                return rc;
        }

        // Fill the host buffer with random values
        for (int i = 0; i < nels; i++) {
                src[i] = rand();
        }

        // Copy from the host onto the device
        rc = hb_mc_device_memcpy (&device, src_eva, (void *) &src[0],
                                  RD_BUFFER_SZ,
                                  HB_MC_MEMCPY_TO_DEVICE);

        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to copy memory to device.\n");
                return rc;
        }


        // Define the X and Y dimensions of the tile group
        hb_mc_dimension_t tg_dim   = { .x = 1, .y = 1 };
        // Calculate grid_dim_x/y (Trivial in this case)
        hb_mc_dimension_t grid_dim = { .x = 1, .y = 1 };

        // Prepare list of input arguments for kernel.
        uint32_t cuda_argv[3] = {(uint32_t) src_eva,
                                 (uint32_t) nels,
                                 (uint32_t) res_eva};

        // Enquque grid of tile groups, pass in grid and tile group
        // dimensions, kernel name, number and list of input arguments
        for(int i = 0; i < NUM_RUNS; ++i){ // TODO: This launches all enqueued jobs simultaneously
                rc = hb_mc_application_init (&device, grid_dim, tg_dim,
                                             "kernel_memread_reg_base",
                                             sizeof(cuda_argv)/sizeof(cuda_argv[0]),
                                             cuda_argv);
        }

        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize grid.\n");
                return rc;
        }

        bsg_timer(&timer, &duration);
        // Launch and execute all tile groups on device and wait for all to finish.
        rc = hb_mc_device_tile_groups_execute(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to execute tile groups.\n");
                return rc;
        }
        bsg_timer(&timer, &duration);
        bsg_pr_info("Current Time is %llu ns\n", timer);
        bsg_pr_info("Kernel Duration over %d iterations was %llu ns (average %llu ns)\n", NUM_RUNS, duration, duration/NUM_RUNS);

        // Enquque grid of tile groups, pass in grid and tile group
        // dimensions, kernel name, number and list of input arguments
        for(int i = 0; i < NUM_RUNS; ++i){
                rc = hb_mc_application_init (&device, grid_dim, tg_dim,
                                             "kernel_memread_reg_2",
                                             sizeof(cuda_argv)/sizeof(cuda_argv[0]),
                                             cuda_argv);
        }
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize grid.\n");
                return rc;
        }

        bsg_timer(&timer, &duration);
        // Launch and execute all tile groups on device and wait for all to finish.
        rc = hb_mc_device_tile_groups_execute(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to execute tile groups.\n");
                return rc;
        }
        bsg_timer(&timer, &duration);
        bsg_pr_info("Current Time is %llu ns\n", timer);
        bsg_pr_info("Kernel Duration over %d iterations was %llu ns (average %llu ns)\n", NUM_RUNS, duration, duration/NUM_RUNS);

        // Enquque grid of tile groups, pass in grid and tile group
        // dimensions, kernel name, number and list of input arguments
        for(int i = 0; i < NUM_RUNS; ++i){
                rc = hb_mc_application_init (&device, grid_dim, tg_dim,
                                             "kernel_memread_reg_4",
                                             sizeof(cuda_argv)/sizeof(cuda_argv[0]),
                                             cuda_argv);
        }
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize grid.\n");
                return rc;
        }

        bsg_timer(&timer, &duration);
        // Launch and execute all tile groups on device and wait for all to finish.
        rc = hb_mc_device_tile_groups_execute(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to execute tile groups.\n");
                return rc;
        }
        bsg_timer(&timer, &duration);
        bsg_pr_info("Current Time is %llu ns\n", timer);
        bsg_pr_info("Kernel Duration over %d iterations was %llu ns (average %llu ns)\n", NUM_RUNS, duration, duration/NUM_RUNS);

        // Enquque grid of tile groups, pass in grid and tile group
        // dimensions, kernel name, number and list of input arguments
        for(int i = 0; i < NUM_RUNS; ++i){
                rc = hb_mc_application_init (&device, grid_dim, tg_dim,
                                             "kernel_memread_reg_8",
                                             sizeof(cuda_argv)/sizeof(cuda_argv[0]),
                                             cuda_argv);
        }
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize grid.\n");
                return rc;
        }

        bsg_timer(&timer, &duration);
        // Launch and execute all tile groups on device and wait for all to finish.
        rc = hb_mc_device_tile_groups_execute(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to execute tile groups.\n");
                return rc;
        }
        bsg_timer(&timer, &duration);
        bsg_pr_info("Current Time is %llu ns\n", timer);
        bsg_pr_info("Kernel Duration over %d iterations was %llu ns (average %llu ns)\n", NUM_RUNS, duration, duration/NUM_RUNS);

        // Enquque grid of tile groups, pass in grid and tile group
        // dimensions, kernel name, number and list of input arguments
        for(int i = 0; i < NUM_RUNS; ++i){
                rc = hb_mc_application_init (&device, grid_dim, tg_dim,
                                             "kernel_memread_reg_16",
                                             sizeof(cuda_argv)/sizeof(cuda_argv[0]),
                                             cuda_argv);
        }
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize grid.\n");
                return rc;
        }

        bsg_timer(&timer, &duration);

        // Launch and execute all tile groups on device and wait for all to finish.
        rc = hb_mc_device_tile_groups_execute(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to execute tile groups.\n");
                return rc;
        }
        bsg_timer(&timer, &duration);
        bsg_pr_info("Current Time is %llu ns\n", timer);
        bsg_pr_info("Kernel Duration over %d iterations was %llu ns (average %llu ns)\n", NUM_RUNS, duration, duration/NUM_RUNS);

        // Enquque grid of tile groups, pass in grid and tile group
        // dimensions, kernel name, number and list of input arguments
        for(int i = 0; i < NUM_RUNS; ++i){
                rc = hb_mc_application_init (&device, grid_dim, tg_dim,
                                             "kernel_memread_reg_32",
                                             sizeof(cuda_argv)/sizeof(cuda_argv[0]),
                                             cuda_argv);
        }
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to initialize grid.\n");
                return rc;
        }

        bsg_timer(&timer, &duration);

        // Launch and execute all tile groups on device and wait for all to finish.
        rc = hb_mc_device_tile_groups_execute(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to execute tile groups.\n");
                return rc;
        }
        bsg_timer(&timer, &duration);
        bsg_pr_info("Current Time is %llu ns\n", timer);
        bsg_pr_info("Kernel Duration over %d iterations was %llu ns (average %llu ns)\n", NUM_RUNS, duration, duration/NUM_RUNS);

        // Copy result from device DRAM into host memory.
        rc = hb_mc_device_memcpy (&device, (void *) &res, res_eva,
                                  sizeof(read_t),
                                  HB_MC_MEMCPY_TO_HOST);

        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to copy memory from device.\n");
                return rc;
        }


        // Freeze the tiles and cleanup the memory manager
        rc = hb_mc_device_finish(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("Failed to de-initialize device.\n");
                return rc;
        }

        // Compare the result
        int mismatch = src[nels-1] != res;

        if (mismatch) {
                bsg_pr_err(BSG_RED("Failure.\n"));
                return HB_MC_FAIL;
        }
        bsg_pr_test_info(BSG_GREEN("Success.\n"));
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
        bsg_pr_test_info("test_memread_reg Regression Test (COSIMULATION)\n");
        int rc = kernel_memread_reg(argc, argv);
        *exit_code = rc;
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return;
}
#else
int main(int argc, char ** argv) {
        bsg_pr_test_info("test_memread_reg Regression Test (F1)\n");
        int rc = kernel_memread_reg(argc, argv);
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return rc;
}
#endif

