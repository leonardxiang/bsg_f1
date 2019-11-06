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

  `include "bsg_axi_bus_pkg.vh"

  `declare_bsg_axil_bus_s(1, bsg_axil_mosi_bus_s, bsg_axil_miso_bus_s);
  bsg_axil_mosi_bus_s s_axil_mc_li;
  bsg_axil_miso_bus_s s_axil_mc_lo;

  assign s_axil_mc_li.awaddr  = m_axil_ocl_awaddr;
  assign s_axil_mc_li.awvalid = m_axil_ocl_awvalid;
  assign m_axil_ocl_awready   = s_axil_mc_lo.awready;
  assign s_axil_mc_li.wdata   = m_axil_ocl_wdata;
  assign s_axil_mc_li.wstrb   = m_axil_ocl_wstrb;
  assign s_axil_mc_li.wvalid  = m_axil_ocl_wvalid;
  assign m_axil_ocl_wready    = s_axil_mc_lo.wready;
  assign m_axil_ocl_bresp     = s_axil_mc_lo.bresp ;
  assign m_axil_ocl_bvalid    = s_axil_mc_lo.bvalid;
  assign s_axil_mc_li.bready  = m_axil_ocl_bready;
  assign s_axil_mc_li.araddr  = m_axil_ocl_araddr;
  assign s_axil_mc_li.arvalid = m_axil_ocl_arvalid;
  assign m_axil_ocl_arready   = s_axil_mc_lo.arready;
  assign m_axil_ocl_rdata     = s_axil_mc_lo.rdata ;
  assign m_axil_ocl_rresp     = s_axil_mc_lo.rresp ;
  assign m_axil_ocl_rvalid    = s_axil_mc_lo.rvalid;
  assign s_axil_mc_li.rready  = m_axil_ocl_rready;

  localparam axi_dram_data_width_lp = 512;

  // axi4 interface
  `declare_bsg_axi4_bus_s(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p,
                          bsg_axi4_mosi_bus_s, bsg_axi4_miso_bus_s);

  bsg_axi4_mosi_bus_s m_axi4_cdc_lo, m_axi4_mem_lo;
  bsg_axi4_miso_bus_s m_axi4_cdc_li, m_axi4_mem_li;

  `declare_bsg_axi4_bus_s(1, axi_id_width_p, axi_addr_width_p, axi_dram_data_width_lp,
                          bsg_axi4_dram_si_bus_s, bsg_axi4_dram_so_bus_s);

  bsg_axi4_dram_si_bus_s s_axi4_dram_li;
  bsg_axi4_dram_so_bus_s s_axi4_dram_lo;

  `declare_bsg_axi4_bus_s(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p/2,
                          bsg_axi4_h_mosi_bus_s, bsg_axi4_h_miso_bus_s);

  //--------------------------------------------
  // AXI4 Manycore System
  //---------------------------------------------
  assign cl_sh_ddr_awid         = s_axi4_dram_li.awid;
  assign cl_sh_ddr_awaddr       = s_axi4_dram_li.awaddr;
  assign cl_sh_ddr_awlen        = s_axi4_dram_li.awlen;
  assign cl_sh_ddr_awsize       = s_axi4_dram_li.awsize;
  assign cl_sh_ddr_awburst      = s_axi4_dram_li.awburst;
  assign cl_sh_ddr_awlock       = s_axi4_dram_li.awlock;
  assign cl_sh_ddr_awcache      = s_axi4_dram_li.awcache;
  assign cl_sh_ddr_awprot       = s_axi4_dram_li.awprot;
  assign cl_sh_ddr_awregion     = s_axi4_dram_li.awregion;
  assign cl_sh_ddr_awqos        = s_axi4_dram_li.awqos;
  assign cl_sh_ddr_awvalid      = s_axi4_dram_li.awvalid;
  assign s_axi4_dram_lo.awready = sh_cl_ddr_awready;

  assign cl_sh_ddr_wdata       = s_axi4_dram_li.wdata;
  assign cl_sh_ddr_wstrb       = s_axi4_dram_li.wstrb;
  assign cl_sh_ddr_wlast       = s_axi4_dram_li.wlast;
  assign cl_sh_ddr_wvalid      = s_axi4_dram_li.wvalid;
  assign s_axi4_dram_lo.wready = sh_cl_ddr_wready;

  assign s_axi4_dram_lo.bid    = sh_cl_ddr_bid;
  assign s_axi4_dram_lo.bresp  = sh_cl_ddr_bresp;
  assign s_axi4_dram_lo.bvalid = sh_cl_ddr_bvalid;
  assign cl_sh_ddr_bready      = s_axi4_dram_li.bready;

  assign cl_sh_ddr_arid         = s_axi4_dram_li.arid;
  assign cl_sh_ddr_araddr       = s_axi4_dram_li.araddr;
  assign cl_sh_ddr_arlen        = s_axi4_dram_li.arlen;
  assign cl_sh_ddr_arsize       = s_axi4_dram_li.arsize;
  assign cl_sh_ddr_arburst      = s_axi4_dram_li.arburst;
  assign cl_sh_ddr_arlock       = s_axi4_dram_li.arlock;
  assign cl_sh_ddr_arcache      = s_axi4_dram_li.arcache;
  assign cl_sh_ddr_arprot       = s_axi4_dram_li.arprot;
  assign cl_sh_ddr_arregion     = s_axi4_dram_li.arregion;
  assign cl_sh_ddr_arqos        = s_axi4_dram_li.arqos;
  assign cl_sh_ddr_arvalid      = s_axi4_dram_li.arvalid;
  assign s_axi4_dram_lo.arready = sh_cl_ddr_arready;

  assign s_axi4_dram_lo.rid    = sh_cl_ddr_rid;
  assign s_axi4_dram_lo.rdata  = sh_cl_ddr_rdata;
  assign s_axi4_dram_lo.rresp  = sh_cl_ddr_rresp;
  assign s_axi4_dram_lo.rlast  = sh_cl_ddr_rlast;
  assign s_axi4_dram_lo.rvalid = sh_cl_ddr_rvalid;
  assign cl_sh_ddr_rready      = s_axi4_dram_li.rready;


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


  // bladerunner wrapper
  localparam num_axi_slot_lp = (mem_cfg_p == e_vcache_blocking_axi4_xbar_dram ||
                                mem_cfg_p == e_vcache_blocking_axi4_xbar_model ||
                                mem_cfg_p == e_vcache_blocking_axi4_hbm) ?
                                num_tiles_x_p : 1;

  bsg_axi4_mosi_bus_s [num_axi_slot_lp-1:0] mc_axi4_cache_lo;
  bsg_axi4_miso_bus_s [num_axi_slot_lp-1:0] mc_axi4_cache_li;

  // hb_manycore
  bsg_bladerunner_wrapper #(.num_axi_slot_p(num_axi_slot_lp)) hb_mc_wrapper (
    .clk_i       (core_clk        ),
    .reset_i     (core_reset      ),
    .clk2_i      (clk_main_a0     ),
    .reset2_i    (~rst_main_n_sync),
    // AXI-Lite
    .s_axil_bus_i(s_axil_mc_li    ),
    .s_axil_bus_o(s_axil_mc_lo    ),
    // AXI4 Master
    .m_axi4_bus_o(mc_axi4_cache_lo),
    .m_axi4_bus_i(mc_axi4_cache_li)
  );


  // LEVEL 3
  //
  // Attach cache to output DRAM
  if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram ||
      mem_cfg_p == e_vcache_blocking_axi4_f1_model) begin : lv3_axi4_c

    assign m_axi4_mem_lo = mc_axi4_cache_lo[0];
    assign mc_axi4_cache_li[0] = m_axi4_mem_li;

  end : lv3_axi4_c

  // Attach cache to xbar axi4 interface
  else if (mem_cfg_p == e_vcache_blocking_axi4_xbar_dram ||
           mem_cfg_p == e_vcache_blocking_axi4_xbar_model ||
           mem_cfg_p == e_vcache_blocking_axi4_hbm) begin : lv3_xbar_c

    bsg_axi4_mosi_bus_s [num_axi_slot_lp-1:0] mc_axi4_cols_lo;
    bsg_axi4_miso_bus_s [num_axi_slot_lp-1:0] mc_axi4_cols_li;

    // 1.0 BYPASS mc axi4
    assign mc_axi4_cols_lo = mc_axi4_cache_lo;
    assign mc_axi4_cache_li = mc_axi4_cols_li;

    // 2.0 mc data pipeline

    // bsg_axi4_mosi_bus_s [num_axi_slot_lp-1:0] s_axi4_dw_dn_li, m_axi4_dw_up_lo;
    // bsg_axi4_miso_bus_s [num_axi_slot_lp-1:0] s_axi4_dw_dn_lo, m_axi4_dw_up_li;

    // for (genvar i = 0; i < num_axi_slot_lp; i++) begin : axi_data_pip

    //   assign m_axi4_dw_up_lo[i] = s_axi4_dw_dn_li[i];
    //   assign s_axi4_dw_dn_lo[i] = m_axi4_dw_up_li[i];

    //   axi4_data_width_converter #(
    //     .id_width_p    (axi_id_width_p    ),
    //     .addr_width_p  (axi_addr_width_p  ),
    //     .s_data_width_p(axi_data_width_p  ),
    //     .m_data_width_p(axi_data_width_p*2),
    //     .device_family ("virtexuplus"     )
    //   ) dw_cvt_dn (
    //     .clk_i   (core_clk            ),
    //     .reset_i (core_reset          ),
    //     .s_axi4_i(mc_axi4_cache_lo[i]   ),
    //     .s_axi4_o(mc_axi4_cache_li[i]   ),
    //     .m_axi4_o(m_axi4_dw_up_lo[i]),
    //     .m_axi4_i(m_axi4_dw_up_li[i])
    //   );

    //   axi4_register_slice #(
    //     .id_width_p   (axi_id_width_p    ),
    //     .addr_width_p (axi_addr_width_p  ),
    //     .data_width_p (axi_data_width_p*2),
    //     .device_family("virtexuplus"     )
    //   ) axi4_reg_buf (
    //     .clk_i   (core_clk            ),
    //     .reset_i (core_reset          ),
    //     .s_axi4_i(m_axi4_dw_up_lo[i]),
    //     .s_axi4_o(m_axi4_dw_up_li[i]),
    //     .m_axi4_o(s_axi4_dw_dn_li[i]),
    //     .m_axi4_i(s_axi4_dw_dn_lo[i])
    //   );

    //   axi4_data_width_converter #(
    //     .id_width_p    (axi_id_width_p    ),
    //     .addr_width_p  (axi_addr_width_p  ),
    //     .s_data_width_p(axi_data_width_p*2),
    //     .m_data_width_p(axi_data_width_p  ),
    //     .device_family ("virtexuplus"     )
    //   ) dw_cvt_up (
    //     .clk_i   (core_clk            ),
    //     .reset_i (core_reset          ),
    //     .s_axi4_i(s_axi4_dw_dn_li[i]),
    //     .s_axi4_o(s_axi4_dw_dn_lo[i]),
    //     .m_axi4_o(mc_axi4_cols_lo[i]   ),
    //     .m_axi4_i(mc_axi4_cols_li[i]   )
    //   );

    // end : axi_data_pip

    axi4_mux #(
      .slot_num_p  (num_axi_slot_lp ),
      .id_width_p  (axi_id_width_p  ),
      .addr_width_p(axi_addr_width_p),
      .data_width_p(axi_data_width_p)
    ) axi4_xbar_mux (
      .clk_i       (core_clk       ),
      .reset_i     (core_reset     ),
      .s_axi4_par_i(mc_axi4_cols_lo),
      .s_axi4_par_o(mc_axi4_cols_li),
      .m_axi4_ser_o(m_axi4_mem_lo  ),
      .m_axi4_ser_i(m_axi4_mem_li  )
    );

  end : lv3_xbar_c

  bsg_axi4_mosi_bus_s m_axi4_cdc_lo;
  bsg_axi4_miso_bus_s m_axi4_cdc_li;

`ifdef COSIM

  axi4_clock_converter #(
    .id_width_p        (axi_id_width_p                       ),
    .addr_width_p      (axi_addr_width_p                     ),
    .data_width_p      (axi_data_width_p                     ),
    .device_family     ("virtexuplus"                        ),
    .s_axi_aclk_ratio_p(1                                    ),
    .m_axi_aclk_ratio_p(lc_core_clk_period_p/lc_clk_main_a0_p),
    .is_aclk_async_p   (1                                    )
  ) axi4_clk_cvt (
    .clk_src_i   (core_clk     ),
    .reset_src_i (core_reset   ),
    .clk_dst_i   (clk_main_a0  ),
    .reset_dst_i (~rst_main_n  ),
    .s_axi4_src_i(m_axi4_mem_lo),
    .s_axi4_src_o(m_axi4_mem_li),
    .m_axi4_dst_o(m_axi4_cdc_lo),
    .m_axi4_dst_i(m_axi4_cdc_li)
  );

`else

  assign m_axi4_cdc_lo = m_axi4_mem_lo;
  assign m_axi4_mem_li = m_axi4_cdc_li;

`endif

  if (axi_dram_data_width_lp != axi_data_width_p) begin : dram_dw_cvt

    axi4_data_width_converter #(
      .id_width_p    (axi_id_width_p        ),
      .addr_width_p  (axi_addr_width_p      ),
      .s_data_width_p(axi_data_width_p      ),
      .m_data_width_p(axi_dram_data_width_lp),
      .device_family ("virtexuplus"         )
    ) dw_cvt_dram (
      .clk_i   (clk_main_a0   ),
      .reset_i (~rst_main_n   ),
      .s_axi4_i(m_axi4_cdc_lo ),
      .s_axi4_o(m_axi4_cdc_li ),
      .m_axi4_o(s_axi4_dram_li),
      .m_axi4_i(s_axi4_dram_lo)
    );

  end : dram_dw_cvt

  else begin

    assign s_axi4_dram_li = m_axi4_cdc_lo;
    assign m_axi4_cdc_li = s_axi4_dram_lo;

  end

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
      ,.print_stat_v_i($root.tb.card.fpga.CL.hb_mc_wrapper.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.hb_mc_wrapper.print_stat_tag_lo)
      ,.trace_en_i($root.tb.card.fpga.CL.trace_en)
      );

   // synopsys translate on

endmodule
