/**
*  bsg_bladerunner_wrapper.v
*
*  top level wrapper for the bsg bladerunner design (equivalent to bsg_f1/cl_manycore.sv)
*/

// header file from bsg_f1
//`include "cl_manycore_pkg.v"
`include "bsg_bladerunner_rom_pkg.vh"
//`include "bsg_bladerunner_mem_cfg_pkg.v"

module bsg_bladerunner_wrapper
  import cl_manycore_pkg::*;
  import bsg_bladerunner_rom_pkg::*;
  import bsg_bladerunner_mem_cfg_pkg::*;
#(
  parameter num_axi_slot_p = 1
  , localparam axil_mosi_bus_width_lp = `bsg_axil_mosi_bus_width(1)
  , localparam axil_miso_bus_width_lp = `bsg_axil_miso_bus_width(1)
  , localparam axi4_mosi_bus_width_lp = `bsg_axi4_mosi_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
  , localparam axi4_miso_bus_width_lp = `bsg_axi4_miso_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
) (
  // System IO signals
  input                                                           clk_i
  ,input                                                           reset_i
  ,input                                                           clk2_i
  ,input                                                           reset2_i
  // AXI Lite Master Interface connections
  ,input  [axil_mosi_bus_width_lp-1:0]                             s_axil_bus_i
  ,output [axil_miso_bus_width_lp-1:0]                             s_axil_bus_o
  // AXI Memory Mapped interface out
  ,input  [        num_axi_slot_p-1:0][axi4_mosi_bus_width_lp-1:0] m_axi4_bus_o
  ,output [        num_axi_slot_p-1:0][axi4_miso_bus_width_lp-1:0] m_axi4_bus_i
);

  `include "cl_manycore_defines.vh"
  `include "bsg_manycore_packet.vh"

  `include "bsg_axi_bus_pkg.vh"

  (* dont_touch = "true" *) logic core_resetn;
  lib_pipe #(.WIDTH(1), .STAGES(4)) MC_RST_N (
    .clk    (clk_i          ),
    .rst_n  (1'b1           ),
    .in_bus (~reset_i       ),
    .out_bus(core_resetn)
  );

  wire core_clk = clk_i;
  wire core_reset = ~core_resetn;

  wire clk_main_a0 = clk2_i;
  wire rst_main_n_sync = ~reset2_i;

// -------------------------------------------------
// AXI-Lite register
// -------------------------------------------------
  `declare_bsg_axil_bus_s(1, bsg_axil_mosi_bus_s, bsg_axil_miso_bus_s);
  bsg_axil_mosi_bus_s m_axil_bus_lo_cast;
  bsg_axil_miso_bus_s m_axil_bus_li_cast;

  assign m_axil_bus_lo_cast = s_axil_bus_i;
  assign s_axil_bus_o       = m_axil_bus_li_cast;


  // manycore wrapper signals
  `declare_bsg_manycore_link_sif_s(addr_width_p, data_width_p, x_cord_width_p, y_cord_width_p, load_id_width_p);

  bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_li;
  bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_lo;

  logic [num_cache_p-1:0][x_cord_width_p-1:0] cache_x_lo;
  logic [num_cache_p-1:0][y_cord_width_p-1:0] cache_y_lo;

  bsg_manycore_link_sif_s loader_link_sif_lo;
  bsg_manycore_link_sif_s loader_link_sif_li;

  bsg_manycore_wrapper #(
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
  ) manycore_wrapper (
    .clk_i(core_clk)
    ,.reset_i(core_reset)

    ,.cache_link_sif_i(cache_link_sif_li)
    ,.cache_link_sif_o(cache_link_sif_lo)

    ,.cache_x_o(cache_x_lo)
    ,.cache_y_o(cache_y_lo)

    ,.loader_link_sif_i(loader_link_sif_li)
    ,.loader_link_sif_o(loader_link_sif_lo)
  );


  `declare_bsg_axi4_bus_s(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p,
                          bsg_axi4_mosi_bus_s, bsg_axi4_miso_bus_s);

  bsg_axi4_mosi_bus_s [num_axi_slot_p-1:0] axi4_mosi_cols_lo;
  bsg_axi4_miso_bus_s [num_axi_slot_p-1:0] axi4_miso_cols_li;

  assign m_axi4_bus_o      = axi4_mosi_cols_lo;
  assign axi4_miso_cols_li = m_axi4_bus_i;

  ////////////////////////////////
  // Configurable Memory System //
  ////////////////////////////////
  localparam byte_offset_width_lp=`BSG_SAFE_CLOG2(data_width_p>>3);
  localparam cache_addr_width_lp=(addr_width_p-1+byte_offset_width_lp);

   // LEVEL 1
  if (mem_cfg_p == e_infinite_mem) begin
    // // each column has a nonsynth infinite memory
    // for (genvar i = 0; i < num_tiles_x_p; i++) begin
    //   bsg_nonsynth_mem_infinite #(
    //     .data_width_p(data_width_p)
    //     ,.addr_width_p(addr_width_p)
    //     ,.x_cord_width_p(x_cord_width_p)
    //     ,.y_cord_width_p(y_cord_width_p)
    //     ,.load_id_width_p(load_id_width_p)
    //   ) mem_infty (
    //     .clk_i(core_clk)
    //     ,.reset_i(core_reset)
    //     // memory systems link from bsg_manycore_wrapper
    //     ,.link_sif_i(cache_link_sif_lo[i])
    //     ,.link_sif_o(cache_link_sif_li[i])
    //     // coordinates for memory system are determined by bsg_manycore_wrapper
    //     ,.my_x_i(cache_x_lo[i])
    //     ,.my_y_i(cache_y_lo[i])
    //   );
    // end

    // bind bsg_nonsynth_mem_infinite infinite_mem_profiler #(
    //   .data_width_p(data_width_p)
    //   ,.x_cord_width_p(x_cord_width_p)
    //   ,.y_cord_width_p(y_cord_width_p)
    // ) infinite_mem_prof (
    //   .*
    //   ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
    //   ,.print_stat_v_i($root.tb.card.fpga.CL.print_stat_v_lo)
    //   ,.print_stat_tag_i($root.tb.card.fpga.CL.print_stat_tag_lo)
    // );

    $fatal(0, "Not supported memcf!g\n");

  end
  else if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram ||
           mem_cfg_p == e_vcache_blocking_axi4_f1_model ||
           mem_cfg_p == e_vcache_blocking_axi4_xbar_dram ||
           mem_cfg_p == e_vcache_blocking_axi4_xbar_model ||
           mem_cfg_p == e_vcache_blocking_axi4_bram ||
           mem_cfg_p == e_vcache_blocking_axi4_hbm) begin: lv1_vcache

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

    // bind bsg_cache vcache_profiler #(
    //   .data_width_p(data_width_p)
    // ) vcache_prof (
    //   .*
    //   ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
    //   ,.print_stat_v_i($root.tb.card.fpga.CL.print_stat_v_lo)
    //   ,.print_stat_tag_i($root.tb.card.fpga.CL.print_stat_tag_lo)
    // );

  end // block: lv1_vcache

  // LEVEL 2
  //
  if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram ||
      mem_cfg_p == e_vcache_blocking_axi4_f1_model ||
      mem_cfg_p == e_vcache_blocking_axi4_bram) begin: lv2_axi4_one

    bsg_cache_to_axi #(
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

      ,.axi_awid_o(axi4_mosi_cols_lo[0].awid)
      ,.axi_awaddr_o(axi4_mosi_cols_lo[0].awaddr)
      ,.axi_awlen_o(axi4_mosi_cols_lo[0].awlen)
      ,.axi_awsize_o(axi4_mosi_cols_lo[0].awsize)
      ,.axi_awburst_o(axi4_mosi_cols_lo[0].awburst)
      ,.axi_awcache_o(axi4_mosi_cols_lo[0].awcache)
      ,.axi_awprot_o(axi4_mosi_cols_lo[0].awprot)
      ,.axi_awlock_o(axi4_mosi_cols_lo[0].awlock)
      ,.axi_awvalid_o(axi4_mosi_cols_lo[0].awvalid)
      ,.axi_awready_i(axi4_miso_cols_li[0].awready)

      ,.axi_wdata_o(axi4_mosi_cols_lo[0].wdata)
      ,.axi_wstrb_o(axi4_mosi_cols_lo[0].wstrb)
      ,.axi_wlast_o(axi4_mosi_cols_lo[0].wlast)
      ,.axi_wvalid_o(axi4_mosi_cols_lo[0].wvalid)
      ,.axi_wready_i(axi4_miso_cols_li[0].wready)

      ,.axi_bid_i(axi4_miso_cols_li[0].bid)
      ,.axi_bresp_i(axi4_miso_cols_li[0].bresp)
      ,.axi_bvalid_i(axi4_miso_cols_li[0].bvalid)
      ,.axi_bready_o(axi4_mosi_cols_lo[0].bready)

      ,.axi_arid_o(axi4_mosi_cols_lo[0].arid)
      ,.axi_araddr_o(axi4_mosi_cols_lo[0].araddr)
      ,.axi_arlen_o(axi4_mosi_cols_lo[0].arlen)
      ,.axi_arsize_o(axi4_mosi_cols_lo[0].arsize)
      ,.axi_arburst_o(axi4_mosi_cols_lo[0].arburst)
      ,.axi_arcache_o(axi4_mosi_cols_lo[0].arcache)
      ,.axi_arprot_o(axi4_mosi_cols_lo[0].arprot)
      ,.axi_arlock_o(axi4_mosi_cols_lo[0].arlock)
      ,.axi_arvalid_o(axi4_mosi_cols_lo[0].arvalid)
      ,.axi_arready_i(axi4_miso_cols_li[0].arready)

      ,.axi_rid_i(axi4_miso_cols_li[0].rid)
      ,.axi_rdata_i(axi4_miso_cols_li[0].rdata)
      ,.axi_rresp_i(axi4_miso_cols_li[0].rresp)
      ,.axi_rlast_i(axi4_miso_cols_li[0].rlast)
      ,.axi_rvalid_i(axi4_miso_cols_li[0].rvalid)
      ,.axi_rready_o(axi4_mosi_cols_lo[0].rready)
    );

    assign axi4_mosi_cols_lo[0].awregion = 4'b0;
    assign axi4_mosi_cols_lo[0].awqos    = 4'b0;

    assign axi4_mosi_cols_lo[0].arregion = 4'b0;
    assign axi4_mosi_cols_lo[0].arqos    = 4'b0;

    //synopsys translate_off
    initial begin
      assert(num_axi_slot_p == 1)
        else $fatal(0, "Do not support num_axi_slot_p > 1 in this memory configuration!\n");
    end
    // synopsys translate_on

  end : lv2_axi4_one

  else if (mem_cfg_p == e_vcache_blocking_axi4_xbar_dram ||
           mem_cfg_p == e_vcache_blocking_axi4_xbar_model ||
           mem_cfg_p == e_vcache_blocking_axi4_hbm ) begin : lv2_axi4_els

    for(genvar i = 0; i < num_tiles_x_p; i++) begin : col_link

      bsg_cache_to_axi #(
        .addr_width_p         (cache_addr_width_lp  ),
        .block_size_in_words_p(block_size_in_words_p),
        .data_width_p         (data_width_p         ),
        .num_cache_p          (1                    ),

        .axi_id_width_p       (axi_id_width_p       ),
        .axi_addr_width_p     (axi_addr_width_p     ),
        .axi_data_width_p     (axi_data_width_p     ),
        .axi_burst_len_p      (axi_burst_len_p      )
      ) cache_to_axi (
        .clk_i           (core_clk                       ),
        .reset_i         (core_reset                     ),

        .dma_pkt_i       (lv1_vcache.dma_pkt[i]          ),
        .dma_pkt_v_i     (lv1_vcache.dma_pkt_v_lo[i]     ),
        .dma_pkt_yumi_o  (lv1_vcache.dma_pkt_yumi_li[i]  ),

        .dma_data_o      (lv1_vcache.dma_data_li[i]      ),
        .dma_data_v_o    (lv1_vcache.dma_data_v_li[i]    ),
        .dma_data_ready_i(lv1_vcache.dma_data_ready_lo[i]),

        .dma_data_i      (lv1_vcache.dma_data_lo[i]      ),
        .dma_data_v_i    (lv1_vcache.dma_data_v_lo[i]    ),
        .dma_data_yumi_o (lv1_vcache.dma_data_yumi_li[i] ),

        .axi_awid_o      (axi4_mosi_cols_lo[i].awid      ),
        .axi_awaddr_o    (axi4_mosi_cols_lo[i].awaddr    ),
        .axi_awlen_o     (axi4_mosi_cols_lo[i].awlen     ),
        .axi_awsize_o    (axi4_mosi_cols_lo[i].awsize    ),
        .axi_awburst_o   (axi4_mosi_cols_lo[i].awburst   ),
        .axi_awcache_o   (axi4_mosi_cols_lo[i].awcache   ),
        .axi_awprot_o    (axi4_mosi_cols_lo[i].awprot    ),
        .axi_awlock_o    (axi4_mosi_cols_lo[i].awlock    ),
        .axi_awvalid_o   (axi4_mosi_cols_lo[i].awvalid   ),
        .axi_awready_i   (axi4_miso_cols_li[i].awready   ),

        .axi_wdata_o     (axi4_mosi_cols_lo[i].wdata     ),
        .axi_wstrb_o     (axi4_mosi_cols_lo[i].wstrb     ),
        .axi_wlast_o     (axi4_mosi_cols_lo[i].wlast     ),
        .axi_wvalid_o    (axi4_mosi_cols_lo[i].wvalid    ),
        .axi_wready_i    (axi4_miso_cols_li[i].wready    ),

        .axi_bid_i       (axi4_miso_cols_li[i].bid       ),
        .axi_bresp_i     (axi4_miso_cols_li[i].bresp     ),
        .axi_bvalid_i    (axi4_miso_cols_li[i].bvalid    ),
        .axi_bready_o    (axi4_mosi_cols_lo[i].bready    ),

        .axi_arid_o      (axi4_mosi_cols_lo[i].arid      ),
        .axi_araddr_o    (axi4_mosi_cols_lo[i].araddr    ),
        .axi_arlen_o     (axi4_mosi_cols_lo[i].arlen     ),
        .axi_arsize_o    (axi4_mosi_cols_lo[i].arsize    ),
        .axi_arburst_o   (axi4_mosi_cols_lo[i].arburst   ),
        .axi_arcache_o   (axi4_mosi_cols_lo[i].arcache   ),
        .axi_arprot_o    (axi4_mosi_cols_lo[i].arprot    ),
        .axi_arlock_o    (axi4_mosi_cols_lo[i].arlock    ),
        .axi_arvalid_o   (axi4_mosi_cols_lo[i].arvalid   ),
        .axi_arready_i   (axi4_miso_cols_li[i].arready   ),

        .axi_rid_i       (axi4_miso_cols_li[i].rid       ),
        .axi_rdata_i     (axi4_miso_cols_li[i].rdata     ),
        .axi_rresp_i     (axi4_miso_cols_li[i].rresp     ),
        .axi_rlast_i     (axi4_miso_cols_li[i].rlast     ),
        .axi_rvalid_i    (axi4_miso_cols_li[i].rvalid    ),
        .axi_rready_o    (axi4_mosi_cols_lo[i].rready    )
      );

      assign axi4_mosi_cols_lo[i].awregion = 4'b0;
      assign axi4_mosi_cols_lo[i].awqos    = 4'b0;

      assign axi4_mosi_cols_lo[i].arregion = 4'b0;
      assign axi4_mosi_cols_lo[i].arqos    = 4'b0;

    end : col_link

  end // block: lv2_axi4_els



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
      ,.s_axil_mcl_awvalid(m_axil_bus_lo_cast.awvalid)
      ,.s_axil_mcl_awaddr (m_axil_bus_lo_cast.awaddr )
      ,.s_axil_mcl_awready(m_axil_bus_li_cast.awready)
      ,.s_axil_mcl_wvalid (m_axil_bus_lo_cast.wvalid )
      ,.s_axil_mcl_wdata  (m_axil_bus_lo_cast.wdata  )
      ,.s_axil_mcl_wstrb  (m_axil_bus_lo_cast.wstrb  )
      ,.s_axil_mcl_wready (m_axil_bus_li_cast.wready )
      ,.s_axil_mcl_bresp  (m_axil_bus_li_cast.bresp  )
      ,.s_axil_mcl_bvalid (m_axil_bus_li_cast.bvalid )
      ,.s_axil_mcl_bready (m_axil_bus_lo_cast.bready )
      ,.s_axil_mcl_araddr (m_axil_bus_lo_cast.araddr )
      ,.s_axil_mcl_arvalid(m_axil_bus_lo_cast.arvalid)
      ,.s_axil_mcl_arready(m_axil_bus_li_cast.arready)
      ,.s_axil_mcl_rdata  (m_axil_bus_li_cast.rdata  )
      ,.s_axil_mcl_rresp  (m_axil_bus_li_cast.rresp  )
      ,.s_axil_mcl_rvalid (m_axil_bus_li_cast.rvalid )
      ,.s_axil_mcl_rready (m_axil_bus_lo_cast.rready )

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


endmodule : bsg_bladerunner_wrapper
