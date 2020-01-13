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

#include "test_vector_matrix_mul.hpp"

#define ALLOC_NAME "default_allocator"

/*!
 * Runs vector-matrix multiplication on a single tile. This tests uses
 * the software/spmd/bsg_cuda_lite_runtime/vector_matrix_mul/ code in
 * the BSG Manycore git repository.
 */


/*!
 * Host Matrix multiplication code (to compare results)
 */
template <typename TA, typename TB, typename TC>
void matrix_mult (TA *A, TB *B, TC *C, uint64_t M, uint64_t N, uint64_t P) {
        for (uint64_t y = 0; y < M; y ++) {
                for (uint64_t x = 0; x < P; x ++) {
                        auto res = 0;
                        for (uint64_t k = 0; k < N; k++) {
                                res += A[y * N + k] * B[k * P + x];
                        }
                        C[y * P + x] = res;
                }
        }
        return;
}

template <typename T>
T matrix_sse (T *A, T *B, uint64_t M, uint64_t N) {
        T sum = 0;
        for (uint64_t y = 0; y < M; y ++) {
                for (uint64_t x = 0; x < N; x ++) {
                        sum += (A[y * M + x] - B[y * M + x]) * (A[y * M + x] - B[y * M + x]);
                }
        }
        return sum;
}

template <typename T>
void matrix_print(T *A, uint64_t M, uint64_t N) {
        T sum = 0;
        for (uint64_t y = 0; y < M; y ++) {
                for (uint64_t x = 0; x < N; x ++) {
                        std::cout << A[y * M + x] << " ";
                }
                std::cout << '\n';

        }
}

int kernel_vector_matrix_mul (int argc, char **argv) {
        int rc;
        char *bin_path, *test_name;
        struct arguments_path args = {NULL, NULL};

        uint64_t M = 1;
        uint64_t N = 32;
        uint64_t P = 32;

        argp_parse (&argp_path, argc, argv, 0, 0, &args);
        bin_path = args.path;
        test_name = args.name;

        bsg_pr_test_info("Running CUDA Vector-Matrix Multiplication"
                         "on a single tile.\n");

        std::numeric_limits<int> lim;
        std::default_random_engine generator;
        generator.seed(42);
        std::uniform_real_distribution<double> distribution(lim.min(),lim.max());

        /**********************************************************************
         * Allocate random A & B on the host and initialize with random values.
         **********************************************************************/
        double A[M * N];
        double B[N * P];
        double C[M * P];

        int32_t A_32[M * N];
        int32_t B_32[N * P];
        int32_t C_32[M * P];
        int32_t R_32[M * P];

        int16_t A_16[M * N];
        int16_t B_16[N * P];
        int16_t C_16[M * P];
        int16_t R_16[M * P];

        int8_t A_8[M * N];
        int8_t B_8[N * P];
        int8_t C_8[M * P];
        int8_t R_8[M * P];

        float A_f[M * N];
        float B_f[N * P];
        float C_f[M * P];
        float R_f[M * P];

        double res ;
        for (uint64_t i = 0; i < M * N; i++) {
                do{
                        res = distribution(generator);
                }while(!std::isnormal(res) && std::isfinite(res));

                A[i] = res;
                A_32[i] = static_cast<int32_t>(res);
                A_16[i] = static_cast<int16_t>(res);
                A_8[i] = static_cast<int8_t>(res);
                A_f[i] = static_cast<float>(res);
        }

        for (uint64_t i = 0; i < N * P; i++) {
                do{
                        res = distribution(generator);
                }while(!std::isnormal(res) && std::isfinite(res));

                B[i] = res;
                B_32[i] = static_cast<int32_t>(res);
                B_16[i] = static_cast<int16_t>(res);
                B_8[i] = static_cast<int8_t>(res);
                B_f[i] = static_cast<float>(res);
        }

        matrix_mult (A, B, C, M, N, P);
        matrix_mult (A_f, B_f, C_f, M, N, P);
        matrix_mult (A_32, B_32, C_32, M, N, P);
        matrix_mult (A_16, B_16, C_16, M, N, P);
        matrix_mult (A_8, B_8, C_8, M, N, P);


        /**********************************************************************
         * Define path to binary.
         * Initialize device, load binary and unfreeze tiles.
         **********************************************************************/
        hb_mc_device_t device;
        rc = hb_mc_device_init(&device, test_name, 0);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to initialize device.\n");
                return rc;
        }


        rc = hb_mc_device_program_init(&device, bin_path, ALLOC_NAME, 0);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to initialize program.\n");
                return rc;
        }

        /**********************************************************************
         * Allocate memory on the device for A, B and C. Since
         * sizeof(float) == sizeof(int32_t) > sizeof(int16_t) > sizeof(int8_t)
         * I'll just reuse the same buffers for each test
         **********************************************************************/

        eva_t A_device, B_device, C_device;
        // Allocate A[M][N] on the device
        rc = hb_mc_device_malloc(&device, M * N * sizeof(uint32_t), &A_device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to allocate memory on device.\n");
                return rc;
        }

        // Allocate B[N][P] on the device
        rc = hb_mc_device_malloc(&device, N * P * sizeof(uint32_t), &B_device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to allocate memory on device.\n");
                return rc;
        }

        // Allocate C[M][P] on the device
        rc = hb_mc_device_malloc(&device, M * P * sizeof(uint32_t), &C_device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to allocate memory on device.\n");
                return rc;
        }


        /**********************************************************************
         * Copy A & B from host onto device DRAM.
         **********************************************************************/
        void *dst = (void *) ((intptr_t) A_device);
        void *src = (void *) &A_32[0];
        rc = hb_mc_device_memcpy (&device, dst, src, (M * N) * sizeof(uint32_t),
                                  HB_MC_MEMCPY_TO_DEVICE);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to copy memory to device.\n");
                return rc;
        }


        dst = (void *) ((intptr_t) B_device);
        src = (void *) &B_32[0];
        rc = hb_mc_device_memcpy (&device, dst, src, (N * P) * sizeof(uint32_t),
                                  HB_MC_MEMCPY_TO_DEVICE);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to copy memory to device.\n");
                return rc;
        }


        /**********************************************************************
         * Define block_size_x/y: amount of work for each tile group
         * Define tg_dim_x/y: number of tiles in each tile group
         * Calculate grid_dim_x/y: number of tile groups needed based
         * on block_size_x/y
         **********************************************************************/
        uint32_t block_size_x = 4;
        uint32_t block_size_y = 4;

        hb_mc_dimension_t tg_dim = { .x = 2, .y = 2 };
        hb_mc_dimension_t grid_dim = { .x = P / block_size_x, .y = M / block_size_y };

        /**********************************************************************
         * Prepare list of input arguments for kernel.
         **********************************************************************/
        uint32_t cuda_argv[8] = {A_device, B_device, C_device, M, N, P, block_size_y, block_size_x};

        /**********************************************************************
         * Enquque grid of tile groups, pass in grid and tile group
         * dimensions, kernel name, number and list of input arguments
         **********************************************************************/
        rc = hb_mc_kernel_enqueue (&device, grid_dim, tg_dim, "kernel_matrix_mul", 8, cuda_argv);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to initialize grid.\n");
                return rc;
        }


        /**********************************************************************
         * Launch and execute all tile groups on device and wait for
         * all to finish.
         **********************************************************************/
        rc = hb_mc_device_tile_groups_execute(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to execute tile groups.\n");
                return rc;
        }


        /**********************************************************************
         * Copy result matrix back from device DRAM into host memory.
         **********************************************************************/
        src = (void *) ((intptr_t) C_device);
        dst = (void *) &R_32[0];
        rc = hb_mc_device_memcpy (&device, (void *) dst, src, (M * P) * sizeof(uint32_t), HB_MC_MEMCPY_TO_HOST); /* copy C to the host */
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to copy memory from device.\n");
                return rc;
        }

        /**********************************************************************
         * Freeze the tiles and memory manager cleanup.
         **********************************************************************/
        rc = hb_mc_device_finish(&device);
        if (rc != HB_MC_SUCCESS) {
                bsg_pr_err("failed to de-initialize device.\n");
                return rc;
        }

        /**********************************************************************
         * Calculate the expected result matrix using host code and
         * compare the results.
         **********************************************************************/

        float eps, max = 0.1;
        matrix_print(R_32, M, P);
        matrix_print(C_32, M, P);
        int foo = matrix_sse(R_32, C_32, M, P);
        bsg_pr_test_info("%d\n", foo);
        if (foo > max) {
                bsg_pr_err(BSG_RED("Matrix Mismatch.\n"));
                return HB_MC_FAIL;
        }
        bsg_pr_test_info(BSG_GREEN("Matrix Match.\n"));
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
        bsg_pr_test_info("test_matrix_mul Regression Test (COSIMULATION)\n");
        int rc = kernel_vector_matrix_mul(argc, argv);
        *exit_code = rc;
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return;
}
#else
int main(int argc, char ** argv) {
        bsg_pr_test_info("test_matrix_mul Regression Test (F1)\n");
        int rc = kernel_vector_matrix_mul(argc, argv);
        bsg_pr_test_pass_fail(rc == HB_MC_SUCCESS);
        return rc;
}
#endif

