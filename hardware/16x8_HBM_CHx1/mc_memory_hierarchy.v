/**
*  mc_memory_hierarchy.v
*
*/

`include "bsg_axi_bus_pkg.vh"

module mc_memory_hierarchy
  import cl_manycore_pkg::*;
  import bsg_bladerunner_mem_cfg_pkg::*;
#(
  parameter data_width_p = "inv"
  , parameter addr_width_p = "inv"
  , parameter x_cord_width_p = "inv"
  , parameter y_cord_width_p = "inv"
  , parameter load_id_width_p = "inv"
  // cache
  , parameter num_cache_p = "inv"
  , parameter num_axi4_p = "inv"
  , parameter caches_per_axi4_p = num_cache_p/num_axi4_p
  // AXI4
  , parameter axi_id_width_p = "inv"
  , parameter axi_addr_width_p = "inv"
  , parameter axi_data_width_p = "inv"
  , localparam ch_addr_width_lp = $clog2(((1 << 31)/num_axi4_p))
  , localparam link_sif_width_lp =
  `bsg_manycore_link_sif_width(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p,load_id_width_p)
  , localparam axi4_mosi_bus_width_lp =
  `bsg_axi4_mosi_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
  , localparam axi4_miso_bus_width_lp =
  `bsg_axi4_miso_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
) (
  input  [ num_axi4_p-1:0]                             clks_i
  ,input  [ num_axi4_p-1:0]                             resets_i
  // manycore side
  ,input  [num_cache_p-1:0][     link_sif_width_lp-1:0] link_sif_i
  ,output [num_cache_p-1:0][     link_sif_width_lp-1:0] link_sif_o
  // AXI Memory Mapped interface out
  ,output [ num_axi4_p-1:0][axi4_mosi_bus_width_lp-1:0] m_axi4_bus_o
  ,input  [ num_axi4_p-1:0][axi4_miso_bus_width_lp-1:0] m_axi4_bus_i
);


  // -------------------------------------------------
  // manycore packet casting
  // -------------------------------------------------
  `declare_bsg_manycore_link_sif_s(addr_width_p, data_width_p, x_cord_width_p, y_cord_width_p, load_id_width_p);

  bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_li;
  bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_lo;

  assign cache_link_sif_li = link_sif_i;
  assign link_sif_o = cache_link_sif_lo;


  // -------------------------------------------------
  // AXI4 casting
  // -------------------------------------------------
  `declare_bsg_axi4_bus_s(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p, bsg_axi4_mosi_bus_s, bsg_axi4_miso_bus_s);

  bsg_axi4_mosi_bus_s [num_axi4_p-1:0] cache_axi4_lo;
  bsg_axi4_miso_bus_s [num_axi4_p-1:0] cache_axi4_li;

  bsg_axi4_mosi_bus_s [num_axi4_p-1:0] m_axi4_lo_cast;
  bsg_axi4_miso_bus_s [num_axi4_p-1:0] m_axi4_li_cast;

  assign m_axi4_bus_o = m_axi4_lo_cast;
  assign m_axi4_li_cast = m_axi4_bus_i;

  for (genvar i = 0; i < num_axi4_p; i++) begin : mem_ch
    always_comb begin
      m_axi4_lo_cast[i] = cache_axi4_lo[i];
      m_axi4_lo_cast[i].awaddr = cache_axi4_lo[i].awaddr | (i << ch_addr_width_lp);
      m_axi4_lo_cast[i].araddr = cache_axi4_lo[i].araddr | (i << ch_addr_width_lp);
      cache_axi4_li[i] = m_axi4_li_cast[i];
    end
  end : mem_ch

  localparam byte_offset_width_lp = `BSG_SAFE_CLOG2(data_width_p>>3)             ;
  localparam cache_addr_width_lp  = (addr_width_p-1+byte_offset_width_lp)        ;
  localparam dma_pkt_width_lp     = `bsg_cache_dma_pkt_width(cache_addr_width_lp);

  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0][dma_pkt_width_lp-1:0] cache_dma_pkt        ;
  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0]                       cache_dma_pkt_v_lo   ;
  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0]                       cache_dma_pkt_yumi_li;

  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0][data_width_p-1:0] cache_dma_data_li      ;
  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0]                   cache_dma_data_v_li    ;
  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0]                   cache_dma_data_ready_lo;

  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0][data_width_p-1:0] cache_dma_data_lo     ;
  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0]                   cache_dma_data_v_lo   ;
  logic [num_axi4_p-1:0][caches_per_axi4_p-1:0]                   cache_dma_data_yumi_li;

  // =================================================
  // LEVEL 1
  // =================================================

  if (mem_cfg_p == e_infinite_mem) begin : lv1_inf

    wire clk_i = clks_i;
    wire reset_i = resets_i;

    // each column has a nonsynth infinite memory
    for (genvar i = 0; i < num_cache_p; i++) begin
      bsg_nonsynth_mem_infinite #(
        .data_width_p(data_width_p)
        ,.addr_width_p(addr_width_p)
        ,.x_cord_width_p(x_cord_width_p)
        ,.y_cord_width_p(y_cord_width_p)
        ,.load_id_width_p(load_id_width_p)
      ) mem_infty (
        .clk_i(clk_i)
        ,.reset_i(reset_i)
        // memory systems link from bsg_manycore_wrapper
        ,.link_sif_i(cache_link_sif_li[i])
        ,.link_sif_o(cache_link_sif_lo[i])
        // coordinates for memory system are determined by bsg_manycore_wrapper
        ,.my_x_i(cache_x_lo[i])
        ,.my_y_i(cache_y_lo[i])
      );
    end

    assign cache_axi4_lo = '0;

    bind bsg_nonsynth_mem_infinite infinite_mem_profiler #(
      .data_width_p(data_width_p)
      ,.x_cord_width_p(x_cord_width_p)
      ,.y_cord_width_p(y_cord_width_p)
    ) infinite_mem_prof (
      .*
      ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
      ,.print_stat_v_i($root.tb.card.fpga.CL.mc_top.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.mc_top.print_stat_tag_lo)
    );

  end : lv1_inf

  else if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram || mem_cfg_p == e_vcache_blocking_axi4_f1_model) begin : lv1_vcache

    logic [num_cache_p-1:0][dma_pkt_width_lp-1:0] dma_pkt        ;
    logic [num_cache_p-1:0]                       dma_pkt_v_lo   ;
    logic [num_cache_p-1:0]                       dma_pkt_yumi_li;

    logic [num_cache_p-1:0][data_width_p-1:0] dma_data_li      ;
    logic [num_cache_p-1:0]                   dma_data_v_li    ;
    logic [num_cache_p-1:0]                   dma_data_ready_lo;

    logic [num_cache_p-1:0][data_width_p-1:0] dma_data_lo     ;
    logic [num_cache_p-1:0]                   dma_data_v_lo   ;
    logic [num_cache_p-1:0]                   dma_data_yumi_li;

    for (genvar i = 0; i < num_cache_p; i++) begin : vcache
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
        .clk_i(clks_i[i/caches_per_axi4_p])
        ,.reset_i(resets_i[i/caches_per_axi4_p])
        // memory systems link from bsg_manycore_wrapper
        ,.link_sif_i(cache_link_sif_li[i])
        ,.link_sif_o(cache_link_sif_lo[i])
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
    end : vcache

    assign cache_dma_pkt = dma_pkt;
    assign cache_dma_pkt_v_lo = dma_pkt_v_lo;
    assign dma_pkt_yumi_li = cache_dma_pkt_yumi_li;
    assign dma_data_li = cache_dma_data_li;
    assign dma_data_v_li = cache_dma_data_v_li;
    assign cache_dma_data_ready_lo = dma_data_ready_lo;
    assign cache_dma_data_lo = dma_data_lo;
    assign cache_dma_data_v_lo = dma_data_v_lo;
    assign dma_data_yumi_li = cache_dma_data_yumi_li;

  `ifdef COSIM
    bind bsg_cache vcache_profiler #(
      .data_width_p(data_width_p)
    ) vcache_prof (
      .*
      ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
      ,.print_stat_v_i($root.tb.card.fpga.CL.mc_top.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.mc_top.print_stat_tag_lo)
    );
  `endif

  end : lv1_vcache


  // =================================================
  // LEVEL 2
  // =================================================

  if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram || mem_cfg_p == e_vcache_blocking_axi4_f1_model) begin : lv2_4_axi4

    for (genvar i = 0; i < num_axi4_p; i++) begin : cache_to_axi

      bsg_cache_to_axi #(
        .addr_width_p         (cache_addr_width_lp  ),
        .block_size_in_words_p(block_size_in_words_p),
        .data_width_p         (data_width_p         ),
        .num_cache_p          (caches_per_axi4_p    ),

        .axi_id_width_p       (axi_id_width_p       ),
        .axi_addr_width_p     (axi_addr_width_p     ),
        .axi_data_width_p     (axi_data_width_p     ),
        .axi_burst_len_p      (axi_burst_len_p      )
      ) cache_to_axi (
        .clk_i           (clks_i[i]                 ),
        .reset_i         (resets_i[i]               ),

        .dma_pkt_i       (cache_dma_pkt[i]          ),
        .dma_pkt_v_i     (cache_dma_pkt_v_lo[i]     ),
        .dma_pkt_yumi_o  (cache_dma_pkt_yumi_li[i]  ),

        .dma_data_o      (cache_dma_data_li[i]      ),
        .dma_data_v_o    (cache_dma_data_v_li[i]    ),
        .dma_data_ready_i(cache_dma_data_ready_lo[i]),

        .dma_data_i      (cache_dma_data_lo[i]      ),
        .dma_data_v_i    (cache_dma_data_v_lo[i]    ),
        .dma_data_yumi_o (cache_dma_data_yumi_li[i] ),

        .axi_awid_o      (cache_axi4_lo[i].awid   ),
        .axi_awaddr_o    (cache_axi4_lo[i].awaddr ),
        .axi_awlen_o     (cache_axi4_lo[i].awlen  ),
        .axi_awsize_o    (cache_axi4_lo[i].awsize ),
        .axi_awburst_o   (cache_axi4_lo[i].awburst),
        .axi_awcache_o   (cache_axi4_lo[i].awcache),
        .axi_awprot_o    (cache_axi4_lo[i].awprot ),
        .axi_awlock_o    (cache_axi4_lo[i].awlock ),
        .axi_awvalid_o   (cache_axi4_lo[i].awvalid),
        .axi_awready_i   (cache_axi4_li[i].awready),

        .axi_wdata_o     (cache_axi4_lo[i].wdata  ),
        .axi_wstrb_o     (cache_axi4_lo[i].wstrb  ),
        .axi_wlast_o     (cache_axi4_lo[i].wlast  ),
        .axi_wvalid_o    (cache_axi4_lo[i].wvalid ),
        .axi_wready_i    (cache_axi4_li[i].wready ),

        .axi_bid_i       (cache_axi4_li[i].bid    ),
        .axi_bresp_i     (cache_axi4_li[i].bresp  ),
        .axi_bvalid_i    (cache_axi4_li[i].bvalid ),
        .axi_bready_o    (cache_axi4_lo[i].bready ),

        .axi_arid_o      (cache_axi4_lo[i].arid   ),
        .axi_araddr_o    (cache_axi4_lo[i].araddr ),
        .axi_arlen_o     (cache_axi4_lo[i].arlen  ),
        .axi_arsize_o    (cache_axi4_lo[i].arsize ),
        .axi_arburst_o   (cache_axi4_lo[i].arburst),
        .axi_arcache_o   (cache_axi4_lo[i].arcache),
        .axi_arprot_o    (cache_axi4_lo[i].arprot ),
        .axi_arlock_o    (cache_axi4_lo[i].arlock ),
        .axi_arvalid_o   (cache_axi4_lo[i].arvalid),
        .axi_arready_i   (cache_axi4_li[i].arready),

        .axi_rid_i       (cache_axi4_li[i].rid    ),
        .axi_rdata_i     (cache_axi4_li[i].rdata  ),
        .axi_rresp_i     (cache_axi4_li[i].rresp  ),
        .axi_rlast_i     (cache_axi4_li[i].rlast  ),
        .axi_rvalid_i    (cache_axi4_li[i].rvalid ),
        .axi_rready_o    (cache_axi4_lo[i].rready )
      );

      assign cache_axi4_lo[i].awregion = 4'b0;
      assign cache_axi4_lo[i].awqos    = 4'b0;

      assign cache_axi4_lo[i].arregion = 4'b0;
      assign cache_axi4_lo[i].arqos    = 4'b0;
    end

  end // block: lv2_axi4_x4

endmodule : mc_memory_hierarchy
