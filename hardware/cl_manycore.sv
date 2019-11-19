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
 *  cl_manycore.v
 */

`include "bsg_bladerunner_rom_pkg.vh"

module cl_manycore
  import cl_manycore_pkg::*;
   import bsg_bladerunner_rom_pkg::*;
   import bsg_bladerunner_mem_cfg_pkg::*;
   (
`include "cl_ports.vh"
    );

   // For some silly reason, you need to leave this up here...
   logic rst_main_n_sync;

`include "bsg_defines.v"
`include "bsg_manycore_packet.vh"
`include "cl_id_defines.vh"
`include "cl_manycore_defines.vh"

   //--------------------------------------------
   // Start with Tie-Off of Unused Interfaces
   //---------------------------------------------
   // The developer should use the next set of `include to properly tie-off any
   // unused interface The list is put in the top of the module to avoid cases
   // where developer may forget to remove it from the end of the file

`include "unused_flr_template.inc"
`include "unused_ddr_a_b_d_template.inc"
   //`include "unused_ddr_c_template.inc"
`include "unused_pcim_template.inc"
`include "unused_dma_pcis_template.inc"
`include "unused_cl_sda_template.inc"
`include "unused_sh_bar1_template.inc"
`include "unused_apppf_irq_template.inc"

   localparam lc_clk_main_a0_p = 8000; // 8000 is 125 MHz
   
   //-------------------------------------------------
   // Wires
   //-------------------------------------------------
   logic pre_sync_rst_n;

   logic [15:0] vled_q;
   logic [15:0] pre_cl_sh_status_vled;
   logic [15:0] sh_cl_status_vdip_q;
   logic [15:0] sh_cl_status_vdip_q2;

   //-------------------------------------------------
   // PCI ID Values
   //-------------------------------------------------
   assign cl_sh_id0[31:0] = `CL_SH_ID0;
   assign cl_sh_id1[31:0] = `CL_SH_ID1;

   //-------------------------------------------------
   // Reset Synchronization
   //-------------------------------------------------

   always_ff @(negedge rst_main_n or posedge clk_main_a0)
     if (!rst_main_n)
       begin
          pre_sync_rst_n  <= 0;
          rst_main_n_sync <= 0;
       end
     else
       begin
          pre_sync_rst_n  <= 1;
          rst_main_n_sync <= pre_sync_rst_n;
       end

   //-------------------------------------------------
   // Virtual LED Register
   //-------------------------------------------------
   // Flop/synchronize interface signals
   always_ff @(posedge clk_main_a0)
     if (!rst_main_n_sync) begin
        sh_cl_status_vdip_q[15:0]  <= 16'h0000;
        sh_cl_status_vdip_q2[15:0] <= 16'h0000;
        cl_sh_status_vled[15:0]    <= 16'h0000;
     end
     else begin
        sh_cl_status_vdip_q[15:0]  <= sh_cl_status_vdip[15:0];
        sh_cl_status_vdip_q2[15:0] <= sh_cl_status_vdip_q[15:0];
        cl_sh_status_vled[15:0]    <= pre_cl_sh_status_vled[15:0];
     end

   // The register contains 16 read-only bits corresponding to 16 LED's.
   // The same LED values can be read from the CL to Shell interface
   // by using the linux FPGA tool: $ fpga-get-virtual-led -S 0
   always_ff @(posedge clk_main_a0)
     if (!rst_main_n_sync) begin
        vled_q[15:0] <= 16'h0000;
     end
     else begin
        vled_q[15:0] <= 16'hbeef;
     end

   assign pre_cl_sh_status_vled[15:0] = vled_q[15:0];
   assign cl_sh_status0[31:0] = 32'h0;
   assign cl_sh_status1[31:0] = 32'h0;

   //-------------------------------------------------
   // Post-Pipeline-Register OCL AXI-L Signals
   //-------------------------------------------------
   logic        m_axil_ocl_awvalid;
   logic [31:0] m_axil_ocl_awaddr;
   logic        m_axil_ocl_awready;

   logic        m_axil_ocl_wvalid;
   logic [31:0] m_axil_ocl_wdata;
   logic [ 3:0] m_axil_ocl_wstrb;
   logic        m_axil_ocl_wready;

   logic        m_axil_ocl_bvalid;
   logic [ 1:0] m_axil_ocl_bresp;
   logic        m_axil_ocl_bready;

   logic        m_axil_ocl_arvalid;
   logic [31:0] m_axil_ocl_araddr;
   logic        m_axil_ocl_arready;

   logic        m_axil_ocl_rvalid;
   logic [31:0] m_axil_ocl_rdata;
   logic [ 1:0] m_axil_ocl_rresp;
   logic        m_axil_ocl_rready;

   //--------------------------------------------
   // AXI4 signals for the Manycore
   //---------------------------------------------
   logic [5:0]  m_axi4_manycore_awid;
   logic [63:0] m_axi4_manycore_awaddr;
   logic [7:0]  m_axi4_manycore_awlen;
   logic [2:0]  m_axi4_manycore_awsize;
   logic [1:0]  m_axi4_manycore_awburst;
   logic [0:0]  m_axi4_manycore_awlock;
   logic [3:0]  m_axi4_manycore_awcache;
   logic [2:0]  m_axi4_manycore_awprot;
   logic [3:0]  m_axi4_manycore_awregion;
   logic [3:0]  m_axi4_manycore_awqos;
   logic        m_axi4_manycore_awvalid;
   logic        m_axi4_manycore_awready;

   logic [511:0] m_axi4_manycore_wdata;
   logic [63:0]  m_axi4_manycore_wstrb;
   logic         m_axi4_manycore_wlast;
   logic         m_axi4_manycore_wvalid;
   logic         m_axi4_manycore_wready;

   logic [5:0]   m_axi4_manycore_bid;
   logic [1:0]   m_axi4_manycore_bresp;
   logic         m_axi4_manycore_bvalid;
   logic         m_axi4_manycore_bready;

   logic [5:0]   m_axi4_manycore_arid;
   logic [63:0]  m_axi4_manycore_araddr;
   logic [7:0]   m_axi4_manycore_arlen;
   logic [2:0]   m_axi4_manycore_arsize;
   logic [1:0]   m_axi4_manycore_arburst;
   logic [0:0]   m_axi4_manycore_arlock;
   logic [3:0]   m_axi4_manycore_arcache;
   logic [2:0]   m_axi4_manycore_arprot;
   logic [3:0]   m_axi4_manycore_arregion;
   logic [3:0]   m_axi4_manycore_arqos;
   logic         m_axi4_manycore_arvalid;
   logic         m_axi4_manycore_arready;

   logic [5:0]   m_axi4_manycore_rid;
   logic [511:0] m_axi4_manycore_rdata;
   logic [1:0]   m_axi4_manycore_rresp;
   logic         m_axi4_manycore_rlast;
   logic         m_axi4_manycore_rvalid;
   logic         m_axi4_manycore_rready;


   //--------------------------------------------
   // AXI-Lite OCL System
   //---------------------------------------------
   axi_register_slice_light 
     AXIL_OCL_REG_SLC 
       (
        .aclk          (clk_main_a0),
        .aresetn       (rst_main_n_sync),
        .s_axi_awaddr  (sh_ocl_awaddr),
        .s_axi_awprot  (3'h0),
        .s_axi_awvalid (sh_ocl_awvalid),
        .s_axi_awready (ocl_sh_awready),
        .s_axi_wdata   (sh_ocl_wdata),
        .s_axi_wstrb   (sh_ocl_wstrb),
        .s_axi_wvalid  (sh_ocl_wvalid),
        .s_axi_wready  (ocl_sh_wready),
        .s_axi_bresp   (ocl_sh_bresp),
        .s_axi_bvalid  (ocl_sh_bvalid),
        .s_axi_bready  (sh_ocl_bready),
        .s_axi_araddr  (sh_ocl_araddr),
        .s_axi_arvalid (sh_ocl_arvalid),
        .s_axi_arready (ocl_sh_arready),
        .s_axi_rdata   (ocl_sh_rdata),
        .s_axi_rresp   (ocl_sh_rresp),
        .s_axi_rvalid  (ocl_sh_rvalid),
        .s_axi_rready  (sh_ocl_rready),
        .m_axi_awaddr  (m_axil_ocl_awaddr),
        .m_axi_awprot  (),
        .m_axi_awvalid (m_axil_ocl_awvalid),
        .m_axi_awready (m_axil_ocl_awready),
        .m_axi_wdata   (m_axil_ocl_wdata),
        .m_axi_wstrb   (m_axil_ocl_wstrb),
        .m_axi_wvalid  (m_axil_ocl_wvalid),
        .m_axi_wready  (m_axil_ocl_wready),
        .m_axi_bresp   (m_axil_ocl_bresp),
        .m_axi_bvalid  (m_axil_ocl_bvalid),
        .m_axi_bready  (m_axil_ocl_bready),
        .m_axi_araddr  (m_axil_ocl_araddr),
        .m_axi_arvalid (m_axil_ocl_arvalid),
        .m_axi_arready (m_axil_ocl_arready),
        .m_axi_rdata   (m_axil_ocl_rdata),
        .m_axi_rresp   (m_axil_ocl_rresp),
        .m_axi_rvalid  (m_axil_ocl_rvalid),
        .m_axi_rready  (m_axil_ocl_rready)
        );

   // manycore wrapper



`ifdef COSIM

   logic         ns_core_clk;
   parameter lc_core_clk_period_p =400000;
   
   bsg_nonsynth_clock_gen 
     #(
       .cycle_time_p(lc_core_clk_period_p)
       ) 
   core_clk_gen 
     (
      .o(ns_core_clk)
      );

`endif


   logic         core_clk;
   logic         core_reset;

`ifdef COSIM
   // This clock mux switches between the "fast" IO Clock and the Slow
   // Unsynthesizable "Core Clk". The assign logic below introduces
   // order-of-evaluation issues that can cause spurrious negedges
   // because the simulator doesn't know what order to evaluate clocks
   // in during a clock switch. See the following datasheet for more
   // information:
   // www.xilinx.com/support/documentation/sw_manuals/xilinx2019_1/ug974-vivado-ultrascale-libraries.pdf
   BUFGMUX 
     #(
       .CLK_SEL_TYPE("ASYNC") // SYNC, ASYNC
       )
   BUFGMUX_inst 
     (
      .O(core_clk), // 1-bit output: Clock output
      .I0(clk_main_a0), // 1-bit input: Clock input (S=0)
      .I1(ns_core_clk), // 1-bit input: Clock input (S=1)
      .S(sh_cl_status_vdip_q2[0]) // 1-bit input: Clock select
      );
   
   // THIS IS AN UNSAFE CLOCK CROSSING. It is only guaranteed to work
   // because 1. We're in cosimulation, and 2. we don't have ongoing
   // transfers at the start or end of simulation. This means that
   // core_clk, and clk_main_a0 *are the same signal* (See BUFGMUX
   // above).
   assign core_reset = ~rst_main_n_sync; 
`else
   assign core_clk = clk_main_a0;
   assign core_reset = ~rst_main_n_sync;
`endif


   `declare_bsg_manycore_link_sif_s(addr_width_p, data_width_p, x_cord_width_p, y_cord_width_p, load_id_width_p);

   bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_li;
   bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_lo;

   logic [num_cache_p-1:0][x_cord_width_p-1:0] cache_x_lo;
   logic [num_cache_p-1:0][y_cord_width_p-1:0] cache_y_lo;

   bsg_manycore_link_sif_s loader_link_sif_li;
   bsg_manycore_link_sif_s loader_link_sif_lo;


   bsg_manycore_wrapper 
     #(
       .addr_width_p(addr_width_p)
       ,.data_width_p(data_width_p)
       ,.num_tiles_x_p(num_tiles_x_p)
       ,.num_tiles_y_p(num_tiles_y_p)
       ,.dmem_size_p(dmem_size_p)
       ,.icache_entries_p(icache_entries_p)
       ,.icache_tag_width_p(icache_tag_width_p)
       ,.epa_byte_addr_width_p(epa_byte_addr_width_p)
       ,.dram_ch_addr_width_p(dram_ch_addr_width_p)
       ,.load_id_width_p(load_id_width_p)
       ,.num_cache_p(num_cache_p)
       ,.vcache_size_p(vcache_size_p)
       ,.vcache_block_size_in_words_p(block_size_in_words_p)
       ,.vcache_sets_p(sets_p)
       ,.branch_trace_en_p(branch_trace_en_p)
       ) 
   manycore_wrapper 
     (
      .clk_i(core_clk)
      ,.reset_i(core_reset)

      ,.cache_link_sif_i(cache_link_sif_li)
      ,.cache_link_sif_o(cache_link_sif_lo)

      ,.cache_x_o(cache_x_lo)
      ,.cache_y_o(cache_y_lo)

      ,.loader_link_sif_i(loader_link_sif_li)
      ,.loader_link_sif_o(loader_link_sif_lo)
      );

`ifdef COSIM

   bsg_manycore_link_sif_s async_link_sif_li;
   bsg_manycore_link_sif_s async_link_sif_lo;

   bsg_manycore_link_sif_async_buffer #(
                                        .addr_width_p(addr_width_p)
                                        ,.data_width_p(data_width_p)
                                        ,.x_cord_width_p(x_cord_width_p)
                                        ,.y_cord_width_p(y_cord_width_p)
                                        ,.load_id_width_p(load_id_width_p)
                                        ,.fifo_els_p(16)
                                        ) async_buf (

                                                     // core side
                                                     .L_clk_i(core_clk)
                                                     ,.L_reset_i(core_reset)
                                                     ,.L_link_sif_i(loader_link_sif_lo)
                                                     ,.L_link_sif_o(loader_link_sif_li)

                                                     // AXI-L side
                                                     ,.R_clk_i(clk_main_a0)
                                                     ,.R_reset_i(~rst_main_n_sync)
                                                     ,.R_link_sif_i(async_link_sif_li)
                                                     ,.R_link_sif_o(async_link_sif_lo)
                                                     );

`endif

  ////////////////////////////////
  // Configurable Memory System //
  ////////////////////////////////
  localparam byte_offset_width_lp=`BSG_SAFE_CLOG2(data_width_p>>3);
  localparam cache_addr_width_lp=(addr_width_p-1+byte_offset_width_lp);

   // LEVEL 1
  if (mem_cfg_p == e_infinite_mem) begin
    // each column has a nonsynth infinite memory
    for (genvar i = 0; i < num_tiles_x_p; i++) begin
      bsg_nonsynth_mem_infinite #(
        .data_width_p(data_width_p)
        ,.addr_width_p(addr_width_p)
        ,.x_cord_width_p(x_cord_width_p)
        ,.y_cord_width_p(y_cord_width_p)
        ,.load_id_width_p(load_id_width_p)
      ) mem_infty (
        .clk_i(core_clk)
        ,.reset_i(core_reset)
        // memory systems link from bsg_manycore_wrapper
        ,.link_sif_i(cache_link_sif_lo[i])
        ,.link_sif_o(cache_link_sif_li[i])
        // coordinates for memory system are determined by bsg_manycore_wrapper
        ,.my_x_i(cache_x_lo[i])
        ,.my_y_i(cache_y_lo[i])
      );
    end

    bind bsg_nonsynth_mem_infinite infinite_mem_profiler #(
      .data_width_p(data_width_p)
      ,.x_cord_width_p(x_cord_width_p)
      ,.y_cord_width_p(y_cord_width_p)
    ) infinite_mem_prof (
      .*
      ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
      ,.print_stat_v_i($root.tb.card.fpga.CL.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.print_stat_tag_lo)
    );

  end
  else if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram  || 
           mem_cfg_p == e_vcache_blocking_axi4_f1_model ||
	   mem_cfg_p == e_vcache_blocking_axi4_xilinx_hbm_direct_no_ro) begin: lv1_vcache

    import bsg_cache_pkg::*;

    `declare_bsg_cache_dma_pkt_s(cache_addr_width_lp);
    bsg_cache_dma_pkt_s [num_tiles_x_p-1:0] dma_pkt;
    logic [num_tiles_x_p-1:0] dma_pkt_v_lo;
    logic [num_tiles_x_p-1:0] dma_pkt_yumi_li;

    logic [num_tiles_x_p-1:0][data_width_p-1:0] dma_data_li;
    logic [num_tiles_x_p-1:0] dma_data_v_li;
    logic [num_tiles_x_p-1:0] dma_data_ready_lo;

    logic [num_tiles_x_p-1:0][data_width_p-1:0] dma_data_lo;
    logic [num_tiles_x_p-1:0] dma_data_v_lo;
    logic [num_tiles_x_p-1:0] dma_data_yumi_li;

    for (genvar i = 0; i < num_tiles_x_p; i++) begin

      bsg_manycore_vcache_blocking #(
        .data_width_p(data_width_p)
        ,.addr_width_p(addr_width_p)
        ,.block_size_in_words_p(block_size_in_words_p)
        ,.sets_p(sets_p)
        ,.ways_p(ways_p)

        ,.x_cord_width_p(x_cord_width_p)
        ,.y_cord_width_p(y_cord_width_p)
        ,.load_id_width_p(load_id_width_p)
      ) vcache (
        .clk_i(core_clk)
        ,.reset_i(core_reset)
        // memory systems link from bsg_manycore_wrapper
        ,.link_sif_i(cache_link_sif_lo[i])
        ,.link_sif_o(cache_link_sif_li[i])
        // coordinates for memory system are determined by bsg_manycore_wrapper
        ,.my_x_i(cache_x_lo[i])
        ,.my_y_i(cache_y_lo[i])

        ,.dma_pkt_o(dma_pkt[i])
        ,.dma_pkt_v_o(dma_pkt_v_lo[i])
        ,.dma_pkt_yumi_i(dma_pkt_yumi_li[i])

        ,.dma_data_i(dma_data_li[i])
        ,.dma_data_v_i(dma_data_v_li[i])
        ,.dma_data_ready_o(dma_data_ready_lo[i])

        ,.dma_data_o(dma_data_lo[i])
        ,.dma_data_v_o(dma_data_v_lo[i])
        ,.dma_data_yumi_i(dma_data_yumi_li[i])
     );

    end

    bind bsg_cache vcache_profiler #(
      .data_width_p(data_width_p)
    ) vcache_prof (
      .*
      ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
      ,.print_stat_v_i($root.tb.card.fpga.CL.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.print_stat_tag_lo)
    );

  end // block: lv1_vcache

  // LEVEL 2
  //
  if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram  || 
      mem_cfg_p == e_vcache_blocking_axi4_f1_model ||
      mem_cfg_p == e_vcache_blocking_axi4_xilinx_hbm_direct_no_ro) begin: lv2_axi4

    logic [axi_id_width_p-1:0] axi_awid;
    logic [axi_addr_width_p-1:0] axi_awaddr;
    logic [7:0] axi_awlen;
    logic [2:0] axi_awsize;
    logic [1:0] axi_awburst;
    logic [3:0] axi_awcache;
    logic [2:0] axi_awprot;
    logic axi_awlock;
    logic axi_awvalid;
    logic axi_awready;

    logic [axi_data_width_p-1:0] axi_wdata;
    logic [axi_strb_width_p-1:0] axi_wstrb;
    logic axi_wlast;
    logic axi_wvalid;
    logic axi_wready;

    logic [axi_id_width_p-1:0] axi_bid;
    logic [1:0] axi_bresp;
    logic axi_bvalid;
    logic axi_bready;

    logic [axi_id_width_p-1:0] axi_arid;
    logic [axi_addr_width_p-1:0] axi_araddr;
    logic [7:0] axi_arlen;
    logic [2:0] axi_arsize;
    logic [1:0] axi_arburst;
    logic [3:0] axi_arcache;
    logic [2:0] axi_arprot;
    logic axi_arlock;
    logic axi_arvalid;
    logic axi_arready;

    logic [axi_id_width_p-1:0] axi_rid;
    logic [axi_data_width_p-1:0] axi_rdata;
    logic [1:0] axi_rresp;
    logic axi_rlast;
    logic axi_rvalid;
    logic axi_rready;

    bsg_cache_to_axi_hashed #(
      .addr_width_p(cache_addr_width_lp)
      ,.block_size_in_words_p(block_size_in_words_p)
      ,.data_width_p(data_width_p)
      ,.num_cache_p(num_tiles_x_p)

      ,.axi_id_width_p(axi_id_width_p)
      ,.axi_addr_width_p(axi_addr_width_p)
      ,.axi_data_width_p(axi_data_width_p)
      ,.axi_burst_len_p(axi_burst_len_p)
    ) cache_to_axi (
      .clk_i(core_clk)
      ,.reset_i(core_reset)

      ,.dma_pkt_i(lv1_vcache.dma_pkt)
      ,.dma_pkt_v_i(lv1_vcache.dma_pkt_v_lo)
      ,.dma_pkt_yumi_o(lv1_vcache.dma_pkt_yumi_li)

      ,.dma_data_o(lv1_vcache.dma_data_li)
      ,.dma_data_v_o(lv1_vcache.dma_data_v_li)
      ,.dma_data_ready_i(lv1_vcache.dma_data_ready_lo)

      ,.dma_data_i(lv1_vcache.dma_data_lo)
      ,.dma_data_v_i(lv1_vcache.dma_data_v_lo)
      ,.dma_data_yumi_o(lv1_vcache.dma_data_yumi_li)

      ,.axi_awid_o(axi_awid)
      ,.axi_awaddr_o(axi_awaddr)
      ,.axi_awlen_o(axi_awlen)
      ,.axi_awsize_o(axi_awsize)
      ,.axi_awburst_o(axi_awburst)
      ,.axi_awcache_o(axi_awcache)
      ,.axi_awprot_o(axi_awprot)
      ,.axi_awlock_o(axi_awlock)
      ,.axi_awvalid_o(axi_awvalid)
      ,.axi_awready_i(axi_awready)

      ,.axi_wdata_o(axi_wdata)
      ,.axi_wstrb_o(axi_wstrb)
      ,.axi_wlast_o(axi_wlast)
      ,.axi_wvalid_o(axi_wvalid)
      ,.axi_wready_i(axi_wready)

      ,.axi_bid_i(axi_bid)
      ,.axi_bresp_i(axi_bresp)
      ,.axi_bvalid_i(axi_bvalid)
      ,.axi_bready_o(axi_bready)

      ,.axi_arid_o(axi_arid)
      ,.axi_araddr_o(axi_araddr)
      ,.axi_arlen_o(axi_arlen)
      ,.axi_arsize_o(axi_arsize)
      ,.axi_arburst_o(axi_arburst)
      ,.axi_arcache_o(axi_arcache)
      ,.axi_arprot_o(axi_arprot)
      ,.axi_arlock_o(axi_arlock)
      ,.axi_arvalid_o(axi_arvalid)
      ,.axi_arready_i(axi_arready)

      ,.axi_rid_i(axi_rid)
      ,.axi_rdata_i(axi_rdata)
      ,.axi_rresp_i(axi_rresp)
      ,.axi_rlast_i(axi_rlast)
      ,.axi_rvalid_i(axi_rvalid)
      ,.axi_rready_o(axi_rready)
    );

  end // block: lv2_axi4

  // LEVEL 3
  //
  if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram ||
      mem_cfg_p == e_vcache_blocking_axi4_f1_model) begin
   // Attach cache to output DRAM

   // AXI Address Write signals
   assign m_axi4_manycore_awid          = lv2_axi4.axi_awid;
   assign m_axi4_manycore_awaddr        = lv2_axi4.axi_awaddr;
   assign m_axi4_manycore_awvalid       = lv2_axi4.axi_awvalid;
   assign lv2_axi4.axi_awready          = m_axi4_manycore_awready;
   assign m_axi4_manycore_awlen         =  lv2_axi4.axi_awlen;
   assign m_axi4_manycore_awsize        = lv2_axi4.axi_awsize;
   assign m_axi4_manycore_awburst       = lv2_axi4.axi_awburst;
   assign m_axi4_manycore_awcache       = lv2_axi4.axi_awcache;
   assign m_axi4_manycore_awprot        = lv2_axi4.axi_awprot;
   assign m_axi4_manycore_awlock        = lv2_axi4.axi_awlock;
   assign m_axi4_manycore_awregion      = 4'b0;
   assign m_axi4_manycore_awqos         = 4'b0;

   // AXI Write signals
   assign m_axi4_manycore_wdata         = lv2_axi4.axi_wdata;
   assign m_axi4_manycore_wstrb         = lv2_axi4.axi_wstrb;
   assign m_axi4_manycore_wlast         = lv2_axi4.axi_wlast;
   assign m_axi4_manycore_wvalid        = lv2_axi4.axi_wvalid;
   assign lv2_axi4.axi_wready           = m_axi4_manycore_wready;

   // AXI Burst signals
   assign lv2_axi4.axi_bid              = m_axi4_manycore_bid;
   assign lv2_axi4.axi_bresp            = m_axi4_manycore_bresp;
   assign lv2_axi4.axi_bvalid           = m_axi4_manycore_bvalid;
   assign m_axi4_manycore_bready        = lv2_axi4.axi_bready;

   // AXI Address Read signals
   assign m_axi4_manycore_arid          = lv2_axi4.axi_arid;
   assign m_axi4_manycore_araddr        = lv2_axi4.axi_araddr;
   assign m_axi4_manycore_arlen         = lv2_axi4.axi_arlen;
   assign m_axi4_manycore_arsize        = lv2_axi4.axi_arsize;
   assign m_axi4_manycore_arburst       = lv2_axi4.axi_arburst;
   assign m_axi4_manycore_arcache       = lv2_axi4.axi_arcache;
   assign m_axi4_manycore_arprot        = lv2_axi4.axi_arprot;
   assign m_axi4_manycore_arlock        = lv2_axi4.axi_arlock;
   assign m_axi4_manycore_arvalid       = lv2_axi4.axi_arvalid;
   assign lv2_axi4.axi_arready          = m_axi4_manycore_arready;
   assign m_axi4_manycore_arregion      = 4'b0;
   assign m_axi4_manycore_arqos         = 4'b0;

   // AXI Read signals
   assign lv2_axi4.axi_rid              = m_axi4_manycore_rid;
   assign lv2_axi4.axi_rdata            = m_axi4_manycore_rdata;
   assign lv2_axi4.axi_rresp            = m_axi4_manycore_rresp;
   assign lv2_axi4.axi_rlast            = m_axi4_manycore_rlast;
   assign lv2_axi4.axi_rvalid           = m_axi4_manycore_rvalid;
   assign m_axi4_manycore_rready        = lv2_axi4.axi_rready;
  end // if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram)
  else if (mem_cfg_p == e_vcache_blocking_axi4_xilinx_hbm_direct_no_ro) begin
     // Attach cache to a single HBM

     // tie-off one HBM channel
     `define tie_hbm_channel(channel_name)	\
        ,.AXI_``channel_name``_ACLK(core_clk)	\
	,.AXI_``channel_name``_ARESET_N(1'b0)	\
	,.AXI_``channel_name``_ARADDR()		\
	,.AXI_``channel_name``_ARBURST()	\
	,.AXI_``channel_name``_ARID()		\
	,.AXI_``channel_name``_ARLEN()		\
	,.AXI_``channel_name``_ARSIZE()		\
	,.AXI_``channel_name``_ARVALID()	\
	,.AXI_``channel_name``_AWADDR()		\
	,.AXI_``channel_name``_AWBURST()	\
	,.AXI_``channel_name``_AWID()		\
	,.AXI_``channel_name``_AWLEN()		\
	,.AXI_``channel_name``_AWSIZE()		\
	,.AXI_``channel_name``_AWVALID()	\
	,.AXI_``channel_name``_RREADY()		\
	,.AXI_``channel_name``_BREADY()		\
	,.AXI_``channel_name``_WDATA()		\
	,.AXI_``channel_name``_WLAST()		\
	,.AXI_``channel_name``_WSTRB()		\
	,.AXI_``channel_name``_WDATA_PARITY()	\
	,.AXI_``channel_name``_WVALID()		\
	,.AXI_``channel_name``_ARREADY()	\
	,.AXI_``channel_name``_AWREADY()	\
	,.AXI_``channel_name``_RDATA_PARITY()	\
	,.AXI_``channel_name``_RDATA()		\
	,.AXI_``channel_name``_RID()		\
	,.AXI_``channel_name``_RLAST()		\
	,.AXI_``channel_name``_RRESP()		\
	,.AXI_``channel_name``_RVALID()		\
	,.AXI_``channel_name``_WREADY()		\
	,.AXI_``channel_name``_BID()		\
	,.AXI_``channel_name``_BRESP()		\
	,.AXI_``channel_name``_BVALID()

     // reset signals
     logic axi_reset_n;
     logic apb_reset_n;

     initial begin
	axi_reset_n = 1'b1;
	#200ns;
	axi_reset_n = 1'b0;
	#4500ns;
	axi_reset_n = 1'b1;
     end

     assign apb_reset_n = axi_reset_n;

     // nosynth reference clock generator
     // 100MHz

     logic   hbm_ref_clk0;
     logic   hbm_ref_clk1;
     logic   apb_clk0;
     logic   apb_clk1;

     bsg_nonsynth_clock_gen #(
       .cycle_time_p(10000)
     ) hbm_ref_clk_gen (
       .o(hbm_ref_clk0)
     );

     assign hbm_ref_clk1 = hbm_ref_clk0;
     assign apb_clk0 = hbm_ref_clk0;
     assign apb_clk1 = hbm_ref_clk0;

     // axi4 data parity
     logic [(axi_data_width_p>>3)-1:0] axi4_wdata_parity;

     hb_axi_parity  #(
       .axi_data_width_p(axi_data_width_p)
     ) wdata_parity (
       .data_i(lv2_axi4.axi_wdata)
       ,.parity_o(axi4_wdata_parity)
     );

     // instantiate an HBM chip
     hbm_direct_no_ro hbm (
       .HBM_REF_CLK_0	(hbm_ref_clk0)
	,.HBM_REF_CLK_1	(hbm_ref_clk1)

	,.AXI_00_ACLK		(core_clk)
	,.AXI_00_ARESET_N	(axi_reset_n)
	,.AXI_00_ARADDR		(lv2_axi4.axi_araddr)
	,.AXI_00_ARBURST	(lv2_axi4.axi_arburst)
	,.AXI_00_ARID		(lv2_axi4.axi_arid)
	,.AXI_00_ARLEN		(lv2_axi4.axi_arlen[3:0])
	,.AXI_00_ARSIZE		(lv2_axi4.axi_arsize)
	,.AXI_00_ARVALID	(lv2_axi4.axi_arvalid)
	,.AXI_00_AWADDR		(lv2_axi4.axi_awaddr)
	,.AXI_00_AWBURST	(lv2_axi4.axi_awburst)
	,.AXI_00_AWID		(lv2_axi4.axi_awid)
	,.AXI_00_AWLEN		(lv2_axi4.axi_awlen[3:0])
	,.AXI_00_AWSIZE		(lv2_axi4.axi_awsize)
	,.AXI_00_AWVALID	(lv2_axi4.axi_awvalid)
	,.AXI_00_RREADY		(lv2_axi4.axi_rready)
	,.AXI_00_BREADY		(lv2_axi4.axi_bready)
	,.AXI_00_WDATA		(lv2_axi4.axi_wdata)
	,.AXI_00_WLAST		(lv2_axi4.axi_wlast)
	,.AXI_00_WSTRB		(lv2_axi4.axi_wstrb)
	,.AXI_00_WDATA_PARITY	(axi4_wdata_parity)
	,.AXI_00_WVALID		(lv2_axi4.axi_wvalid)

	,.AXI_00_ARREADY	(lv2_axi4.axi_arready)
	,.AXI_00_AWREADY	(lv2_axi4.axi_awready)
	,.AXI_00_RDATA_PARITY	()
	,.AXI_00_RDATA		(lv2_axi4.axi_rdata)
	,.AXI_00_RID		(lv2_axi4.axi_rid)
	,.AXI_00_RLAST		(lv2_axi4.axi_rlast)
	,.AXI_00_RRESP		(lv2_axi4.axi_rresp)
	,.AXI_00_RVALID		(lv2_axi4.axi_rvalid)
	,.AXI_00_WREADY		(lv2_axi4.axi_wready)
	,.AXI_00_BID		(lv2_axi4.axi_bid)
	,.AXI_00_BRESP		(lv2_axi4.axi_bresp)
	,.AXI_00_BVALID		(lv2_axi4.axi_bvalid)

        `tie_hbm_channel(01)
	`tie_hbm_channel(02)
	`tie_hbm_channel(03)
	`tie_hbm_channel(04)
	`tie_hbm_channel(05)
	`tie_hbm_channel(06)
	`tie_hbm_channel(07)
	`tie_hbm_channel(08)
	`tie_hbm_channel(09)
	`tie_hbm_channel(10)
	`tie_hbm_channel(11)
	`tie_hbm_channel(12)
	`tie_hbm_channel(13)
	`tie_hbm_channel(14)
	`tie_hbm_channel(15)
	`tie_hbm_channel(16)
	`tie_hbm_channel(17)
	`tie_hbm_channel(18)
	`tie_hbm_channel(19)
	`tie_hbm_channel(20)
	`tie_hbm_channel(21)
	`tie_hbm_channel(22)
	`tie_hbm_channel(23)
	`tie_hbm_channel(24)
	`tie_hbm_channel(25)
	`tie_hbm_channel(26)
	`tie_hbm_channel(27)
	`tie_hbm_channel(28)
	`tie_hbm_channel(29)
	`tie_hbm_channel(30)
	`tie_hbm_channel(31)

        ,.APB_0_PCLK(apb_clk0)
        ,.APB_0_PRESET_N(apb_reset_n)
        ,.APB_0_PENABLE(1'b1)

	,.APB_1_PCLK(apb_clk1)
        ,.APB_1_PRESET_N(apb_reset_n)
        ,.APB_1_PENABLE(1'b1)
     );

     // assertions
     if (axi_data_width_p !== 256) begin: hbm_bad_axi_data_width
	$fatal("expects axi_data_width_p=%d for %s: found %d",
	       256, mem_cfg_p.name(), axi_data_width_p);
     end
     if (axi_addr_width_p !== 33) begin: hbm_bad_axi_addr_width
	$fatal("expects axi_addr_width_p=%d for %s: found %d",
	       256, mem_cfg_p.name(), axi_addr_width_p);
     end
     if (axi_data_width_p*axi_burst_len_p !== (block_size_in_words_p<<2)<<3)
       begin: hbm_axi_bust_line_size_mismatch
          $fatal("exepect axi_data_width_p*axi_burst_len_p (=%d) == block_size_in_words_p*8*4 (=%d)",
                 axi_data_width_p*axi_burst_len_p, (block_size_in_words_p<<2)<<3);
       end

   `include "unused_ddr_c_template.inc"
  end




`ifdef COSIM
   axi_clock_converter_v2_1_18_axi_clock_converter
     #(.C_FAMILY("virtexuplus"),
       .C_AXI_ID_WIDTH(6),
       .C_AXI_ADDR_WIDTH(64),  // Width of s_axi_awaddr, s_axi_araddr, m_axi_awaddr and
       .C_AXI_DATA_WIDTH(512), // Width of WDATA and RDATA (either side).
       .C_S_AXI_ACLK_RATIO(1), // Clock frequency ratio of SI w.r.t. MI. (Slowest of all clock inputs should have ratio=1.)
       .C_M_AXI_ACLK_RATIO(lc_core_clk_period_p/lc_clk_main_a0_p), 
       // S:M or M:S must be integer ratio.
       // Format: Bit32; Range: >='h00000001.
       .C_AXI_IS_ACLK_ASYNC(1), // Indicates whether S and M clocks are asynchronous.
       // FUTURE FEATURE
       // Format: Bit1. Range = 1'b0.
       .C_AXI_PROTOCOL(0), // Protocol of this SI/MI slot.
       .C_AXI_SUPPORTS_USER_SIGNALS (0),
       .C_AXI_SUPPORTS_WRITE(1),
       .C_AXI_SUPPORTS_READ(1),
       .C_SYNCHRONIZER_STAGE(3)
       )
   axi4_dram_cdc
     (.s_axi_aclk(core_clk),
      .s_axi_aresetn(~core_reset),

      // Slave Interface Write Address Ports
      .s_axi_awid(m_axi4_manycore_awid),
      .s_axi_awaddr(m_axi4_manycore_awaddr),
      .s_axi_awlen(m_axi4_manycore_awlen),
      .s_axi_awsize(m_axi4_manycore_awsize),
      .s_axi_awburst(m_axi4_manycore_awburst),
      .s_axi_awlock(m_axi4_manycore_awlock),
      .s_axi_awcache(m_axi4_manycore_awcache),
      .s_axi_awprot(m_axi4_manycore_awprot),
      .s_axi_awregion(m_axi4_manycore_awregion),
      .s_axi_awqos(m_axi4_manycore_awqos),
      .s_axi_awvalid(m_axi4_manycore_awvalid),
      .s_axi_awready(m_axi4_manycore_awready),

      // Slave Interface Write Data Ports
      .s_axi_wid(m_axi4_manycore_wid),
      .s_axi_wdata(m_axi4_manycore_wdata),
      .s_axi_wstrb(m_axi4_manycore_wstrb),
      .s_axi_wlast(m_axi4_manycore_wlast),
      .s_axi_wvalid(m_axi4_manycore_wvalid),
      .s_axi_wready(m_axi4_manycore_wready),

      // Slave Interface Write Response Ports
      .s_axi_bid(m_axi4_manycore_bid),
      .s_axi_bresp(m_axi4_manycore_bresp),
      .s_axi_bvalid(m_axi4_manycore_bvalid),
      .s_axi_bready(m_axi4_manycore_bready),

      // Slave Interface Read Address Ports
      .s_axi_arid(m_axi4_manycore_arid),
      .s_axi_araddr(m_axi4_manycore_araddr),
      .s_axi_arlen(m_axi4_manycore_arlen),
      .s_axi_arsize(m_axi4_manycore_arsize),
      .s_axi_arburst(m_axi4_manycore_arburst),
      .s_axi_arlock(m_axi4_manycore_arlock),
      .s_axi_arcache(m_axi4_manycore_arcache),
      .s_axi_arprot(m_axi4_manycore_arprot),
      .s_axi_arregion(m_axi4_manycore_arregion),
      .s_axi_arqos(m_axi4_manycore_arqos),
      .s_axi_arvalid(m_axi4_manycore_arvalid),
      .s_axi_arready(m_axi4_manycore_arready),

      // Slave Interface Read Data Ports
      .s_axi_rid(m_axi4_manycore_rid),
      .s_axi_rdata(m_axi4_manycore_rdata),
      .s_axi_rresp(m_axi4_manycore_rresp),
      .s_axi_rlast(m_axi4_manycore_rlast),
      .s_axi_rvalid(m_axi4_manycore_rvalid),
      .s_axi_rready(m_axi4_manycore_rready),

      // Master Interface System Signals
      .m_axi_aclk(clk_main_a0),
      .m_axi_aresetn(rst_main_n),

      // Master Interface Write Address Port
      .m_axi_awid(cl_sh_ddr_awid),
      .m_axi_awaddr(cl_sh_ddr_awaddr),
      .m_axi_awlen(cl_sh_ddr_awlen),
      .m_axi_awsize(cl_sh_ddr_awsize),
      .m_axi_awburst(cl_sh_ddr_awburst),
      .m_axi_awlock(cl_sh_ddr_awlock),
      .m_axi_awcache(cl_sh_ddr_awcache),
      .m_axi_awprot(cl_sh_ddr_awprot),
      .m_axi_awregion(cl_sh_ddr_awregion),
      .m_axi_awqos(cl_sh_ddr_awqos),
      .m_axi_awvalid(cl_sh_ddr_awvalid),
      .m_axi_awready(sh_cl_ddr_awready),

      // Master Interface Write Data Ports
      .m_axi_wdata(cl_sh_ddr_wdata),
      .m_axi_wstrb(cl_sh_ddr_wstrb),
      .m_axi_wlast(cl_sh_ddr_wlast),
      .m_axi_wvalid(cl_sh_ddr_wvalid),
      .m_axi_wready(sh_cl_ddr_wready),

      // Master Interface Write Response Ports
      .m_axi_bid(sh_cl_ddr_bid),
      .m_axi_bresp(sh_cl_ddr_bresp),
      .m_axi_bvalid(sh_cl_ddr_bvalid),
      .m_axi_bready(cl_sh_ddr_bready),

      // Master Interface Read Address Port
      .m_axi_arid(cl_sh_ddr_arid),
      .m_axi_araddr(cl_sh_ddr_araddr),
      .m_axi_arlen(cl_sh_ddr_arlen),
      .m_axi_arsize(cl_sh_ddr_arsize),
      .m_axi_arburst(cl_sh_ddr_arburst),
      .m_axi_arlock(cl_sh_ddr_arlock),
      .m_axi_arcache(cl_sh_ddr_arcache),
      .m_axi_arprot(cl_sh_ddr_arprot),
      .m_axi_arregion(cl_sh_ddr_arregion),
      .m_axi_arqos(cl_sh_ddr_arqos),
      .m_axi_arvalid(cl_sh_ddr_arvalid),
      .m_axi_arready(sh_cl_ddr_arready),

      // Master Interface Read Data Ports
      .m_axi_rid(sh_cl_ddr_rid),
      .m_axi_rdata(sh_cl_ddr_rdata),
      .m_axi_rresp(sh_cl_ddr_rresp),
      .m_axi_rlast(sh_cl_ddr_rlast),
      .m_axi_rvalid(sh_cl_ddr_rvalid),
      .m_axi_rready(cl_sh_ddr_rready));
`else

   //--------------------------------------------
   // AXI4 Manycore System
   //---------------------------------------------
   assign m_axi4_manycore_rid = sh_cl_ddr_rid;
   assign m_axi4_manycore_rdata = sh_cl_ddr_rdata;
   assign m_axi4_manycore_rresp = sh_cl_ddr_rresp;
   assign m_axi4_manycore_rlast = sh_cl_ddr_rlast;
   assign m_axi4_manycore_rvalid = sh_cl_ddr_rvalid;
   assign cl_sh_ddr_rready = m_axi4_manycore_rready;

   assign cl_sh_ddr_awid = m_axi4_manycore_awid;
   assign cl_sh_ddr_awaddr = m_axi4_manycore_awaddr;
   assign cl_sh_ddr_awlen = m_axi4_manycore_awlen;
   assign cl_sh_ddr_awsize = m_axi4_manycore_awsize;
   assign cl_sh_ddr_awburst = m_axi4_manycore_awburst;
   assign cl_sh_ddr_awlock = m_axi4_manycore_awlock;
   assign cl_sh_ddr_awcache = m_axi4_manycore_awcache;
   assign cl_sh_ddr_awprot = m_axi4_manycore_awprot;
   assign cl_sh_ddr_awregion = m_axi4_manycore_awregion;
   assign cl_sh_ddr_awqos = m_axi4_manycore_awqos;
   assign cl_sh_ddr_awvalid = m_axi4_manycore_awvalid;
   assign m_axi4_manycore_awready = sh_cl_ddr_awready;

   assign cl_sh_ddr_wdata = m_axi4_manycore_wdata;
   assign cl_sh_ddr_wstrb = m_axi4_manycore_wstrb;
   assign cl_sh_ddr_wlast = m_axi4_manycore_wlast;
   assign cl_sh_ddr_wvalid = m_axi4_manycore_wvalid;
   assign m_axi4_manycore_wready = sh_cl_ddr_wready;

   assign m_axi4_manycore_bid = sh_cl_ddr_bid;
   assign m_axi4_manycore_bresp = sh_cl_ddr_bresp;
   assign m_axi4_manycore_bvalid = sh_cl_ddr_bvalid;
   assign cl_sh_ddr_bready = m_axi4_manycore_bready;

   assign cl_sh_ddr_arid = m_axi4_manycore_arid;
   assign cl_sh_ddr_araddr = m_axi4_manycore_araddr;
   assign cl_sh_ddr_arlen = m_axi4_manycore_arlen;
   assign cl_sh_ddr_arsize = m_axi4_manycore_arsize;
   assign cl_sh_ddr_arburst = m_axi4_manycore_arburst;
   assign cl_sh_ddr_arlock = m_axi4_manycore_arlock;
   assign cl_sh_ddr_arcache = m_axi4_manycore_arcache;
   assign cl_sh_ddr_arprot = m_axi4_manycore_arprot;
   assign cl_sh_ddr_arregion = m_axi4_manycore_arregion;
   assign cl_sh_ddr_arqos = m_axi4_manycore_arqos;
   assign cl_sh_ddr_arvalid = m_axi4_manycore_arvalid;
   assign m_axi4_manycore_arready = sh_cl_ddr_arready;
`endif

   // manycore link

   logic [x_cord_width_p-1:0] mcl_x_cord_lp = '0;
   logic [y_cord_width_p-1:0] mcl_y_cord_lp = '0;

   logic                      print_stat_v_lo;
   logic [data_width_p-1:0]   print_stat_tag_lo;

   bsg_manycore_link_sif_s axil_link_sif_li;
   bsg_manycore_link_sif_s axil_link_sif_lo;

   axil_to_mcl 
     #(.num_mcl_p        (1                )
       ,.num_tiles_x_p    (num_tiles_x_p    )
       ,.num_tiles_y_p    (num_tiles_y_p    )
       ,.addr_width_p     (addr_width_p     )
       ,.data_width_p     (data_width_p     )
       ,.x_cord_width_p   (x_cord_width_p   )
       ,.y_cord_width_p   (y_cord_width_p   )
       ,.load_id_width_p  (load_id_width_p  )
       ,.max_out_credits_p(max_out_credits_p)
       ) 
   axil_to_mcl_inst 
     (
      .clk_i             (clk_main_a0)
      ,.reset_i           (~rst_main_n_sync)

      // axil slave interface
      ,.s_axil_mcl_awvalid(m_axil_ocl_awvalid)
      ,.s_axil_mcl_awaddr (m_axil_ocl_awaddr )
      ,.s_axil_mcl_awready(m_axil_ocl_awready)
      ,.s_axil_mcl_wvalid (m_axil_ocl_wvalid )
      ,.s_axil_mcl_wdata  (m_axil_ocl_wdata  )
      ,.s_axil_mcl_wstrb  (m_axil_ocl_wstrb  )
      ,.s_axil_mcl_wready (m_axil_ocl_wready )
      ,.s_axil_mcl_bresp  (m_axil_ocl_bresp  )
      ,.s_axil_mcl_bvalid (m_axil_ocl_bvalid )
      ,.s_axil_mcl_bready (m_axil_ocl_bready )
      ,.s_axil_mcl_araddr (m_axil_ocl_araddr )
      ,.s_axil_mcl_arvalid(m_axil_ocl_arvalid)
      ,.s_axil_mcl_arready(m_axil_ocl_arready)
      ,.s_axil_mcl_rdata  (m_axil_ocl_rdata  )
      ,.s_axil_mcl_rresp  (m_axil_ocl_rresp  )
      ,.s_axil_mcl_rvalid (m_axil_ocl_rvalid )
      ,.s_axil_mcl_rready (m_axil_ocl_rready )

      // manycore link
      ,.link_sif_i        (axil_link_sif_li)
      ,.link_sif_o        (axil_link_sif_lo)
      ,.my_x_i            (mcl_x_cord_lp     )
      ,.my_y_i            (mcl_y_cord_lp     )

      ,.print_stat_v_o(print_stat_v_lo)
      ,.print_stat_tag_o(print_stat_tag_lo)
      );

`ifdef COSIM
   assign axil_link_sif_li = async_link_sif_lo;
   assign async_link_sif_li = axil_link_sif_lo;
`else
   assign axil_link_sif_li = loader_link_sif_lo;
   assign loader_link_sif_li = axil_link_sif_lo;
`endif

   //-----------------------------------------------
   // Debug bridge, used if need Virtual JTAG
   //-----------------------------------------------
`ifndef DISABLE_VJTAG_DEBUG

   // Flop for timing global clock counter
   logic [63:0]               sh_cl_glcount0_q;

   always_ff @(posedge clk_main_a0)
     if (!rst_main_n_sync)
       sh_cl_glcount0_q <= 0;
     else
       sh_cl_glcount0_q <= sh_cl_glcount0;


   // Integrated Logic Analyzers (ILA)
   ila_0 CL_ILA_0 
     (
      .clk    (clk_main_a0),
      .probe0 (m_axil_ocl_awvalid)
      ,.probe1 (64'(m_axil_ocl_awaddr))
      ,.probe2 (m_axil_ocl_awready)
      ,.probe3 (m_axil_ocl_arvalid)
      ,.probe4 (64'(m_axil_ocl_araddr))
      ,.probe5 (m_axil_ocl_arready)
      );

   ila_0 CL_ILA_1 
     (
      .clk    (clk_main_a0)
      ,.probe0 (m_axil_ocl_bvalid)
      ,.probe1 (sh_cl_glcount0_q)
      ,.probe2 (m_axil_ocl_bready)
      ,.probe3 (m_axil_ocl_rvalid)
      ,.probe4 ({32'b0,m_axil_ocl_rdata[31:0]})
      ,.probe5 (m_axil_ocl_rready)
      );

   // Debug Bridge
   cl_debug_bridge CL_DEBUG_BRIDGE 
     (
      .clk(clk_main_a0)
      ,.S_BSCAN_drck(drck)
      ,.S_BSCAN_shift(shift)
      ,.S_BSCAN_tdi(tdi)
      ,.S_BSCAN_update(update)
      ,.S_BSCAN_sel(sel)
      ,.S_BSCAN_tdo(tdo)
      ,.S_BSCAN_tms(tms)
      ,.S_BSCAN_tck(tck)
      ,.S_BSCAN_runtest(runtest)
      ,.S_BSCAN_reset(reset)
      ,.S_BSCAN_capture(capture)
      ,.S_BSCAN_bscanid_en(bscanid_en)
      );

`endif //  `ifndef DISABLE_VJTAG_DEBUG

   // synopsys translate off
   int                        status;
   logic                      trace_en;
   initial begin
      assign trace_en = $test$plusargs("trace");
   end

   bind vanilla_core vanilla_core_trace 
     #(
       .x_cord_width_p(x_cord_width_p)
       ,.y_cord_width_p(y_cord_width_p)
       ,.icache_tag_width_p(icache_tag_width_p)
       ,.icache_entries_p(icache_entries_p)
       ,.data_width_p(data_width_p)
       ,.dmem_size_p(dmem_size_p)
       ) 
   vtrace 
     (
      .*
      ,.trace_en_i($root.tb.card.fpga.CL.trace_en)
      );


   // profilers
   //
   logic [31:0] global_ctr;

   bsg_cycle_counter global_cc 
     (
      .clk_i(core_clk)
      ,.reset_i(core_reset)
      ,.ctr_r_o(global_ctr)
      );


   bind vanilla_core vanilla_core_profiler 
     #(
       .x_cord_width_p(x_cord_width_p)
       ,.y_cord_width_p(y_cord_width_p)
       ,.data_width_p(data_width_p)
       ,.dmem_size_p(data_width_p)
       ) 
   vcore_prof
     (
      .*
      ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
      ,.print_stat_v_i($root.tb.card.fpga.CL.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.print_stat_tag_lo)
      ,.trace_en_i($root.tb.card.fpga.CL.trace_en)
      );

   // synopsys translate on

endmodule
