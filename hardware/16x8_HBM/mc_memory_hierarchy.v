/**
*  mc_memory_hierarchy.v
*
*/

`include "bsg_axi_bus_pkg.vh"

module mc_memory_hierarchy
  import cl_manycore_pkg::*;
  import bsg_manycore_pkg::*;
  import bsg_bladerunner_mem_cfg_pkg::*;
#(
  parameter data_width_p = "inv"
  , parameter addr_width_p = "inv"
  , parameter x_cord_width_p = "inv"
  , parameter y_cord_width_p = "inv"
  , parameter load_id_width_p = "inv"
  // cache
  , parameter num_axi4_p = "inv"
  , parameter num_tiles_x_p = "inv"
  // AXI4
  , parameter axi_id_width_p = "inv"
  , parameter axi_addr_width_p = "inv"
  , parameter axi_data_width_p = "inv"
  // inverse hashed
  , parameter ihash_enable_p = 0
  , localparam link_sif_width_lp =
  `bsg_manycore_link_sif_width(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p,load_id_width_p)
  , localparam axi4_mosi_bus_width_lp =
  `bsg_axi4_mosi_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
  , localparam axi4_miso_bus_width_lp =
  `bsg_axi4_miso_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
) (
  input  [   num_axi4_p-1:0]                             clks_i
  ,input  [   num_axi4_p-1:0]                             resets_i
  // manycore side
  ,input  [num_tiles_x_p-1:0][     link_sif_width_lp-1:0] link_sif_i
  ,output [num_tiles_x_p-1:0][     link_sif_width_lp-1:0] link_sif_o
  ,input  [num_tiles_x_p-1:0][        x_cord_width_p-1:0] cache_x_li
  ,input  [num_tiles_x_p-1:0][        y_cord_width_p-1:0] cache_y_li  // the signal here is only used for debugging
  // AXI Memory Mapped interface out
  ,output [   num_axi4_p-1:0][axi4_mosi_bus_width_lp-1:0] m_axi4_bus_o
  ,input  [   num_axi4_p-1:0][axi4_miso_bus_width_lp-1:0] m_axi4_bus_i
);

  // set default clock and reset, clocks for memory channels can be different though
  //
  wire clk_i = clks_i[0];
  wire reset_i = resets_i[0];

  // -------------------------------------------------
  // manycore packet casting
  // -------------------------------------------------
  `declare_bsg_manycore_link_sif_s(addr_width_p, data_width_p, x_cord_width_p, y_cord_width_p, load_id_width_p);

  bsg_manycore_link_sif_s [num_tiles_x_p-1:0] cache_link_sif_li;
  bsg_manycore_link_sif_s [num_tiles_x_p-1:0] cache_link_sif_lo;

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

  localparam dram_size_in_words_p=2**29;  // 2GB in total

  // 1
  localparam byte_offset_width_lp = `BSG_SAFE_CLOG2(data_width_p>>3);
  // 2
  localparam word_offset_width_lp = `BSG_SAFE_CLOG2(block_size_in_words_p);
  // 3
  localparam block_index_width_lp  = `BSG_SAFE_CLOG2(dram_size_in_words_p)-word_offset_width_lp     ;
  localparam hashed_index_width_lp = $clog2((2**block_index_width_lp+num_tiles_x_p-1)/num_tiles_x_p);

  // cache address, 28-1+2=9 (512MB)
  localparam cache_axi_addr_width_lp = (addr_width_p-1+byte_offset_width_lp)            ;
  localparam dma_pkt_width_lp        = `bsg_cache_dma_pkt_width(cache_axi_addr_width_lp);

  // cache and axi parameters
  localparam caches_per_axi_p = num_tiles_x_p/num_axi4_p;
  // 5
  localparam axi_chan_width_lp = `BSG_SAFE_CLOG2(num_axi4_p);

  for (genvar i = 0; i < num_axi4_p; i++) begin : mem_ch

    logic [         hashed_index_width_lp-1:0] wr_index_per_channel;
    logic [`BSG_SAFE_CLOG2(num_tiles_x_p)-1:0] wr_channel_li       ;
    logic [          block_index_width_lp-1:0] wr_block_index_lo   ;

    logic [         hashed_index_width_lp-1:0] rd_index_per_channel;
    logic [`BSG_SAFE_CLOG2(num_tiles_x_p)-1:0] rd_channel_li       ;
    logic [          block_index_width_lp-1:0] rd_block_index_lo   ;

    // add msb(channel tags) to each axi address, such that for 16 columns design:
    // 4 axi channels x 4 caches, cache has 64 sets, 16 words per block
    // ORIGINAL ADDRESS
    //        30:29|     28:27|      26:12|       11:6|        5:2|
    // ------------------------------------------------------------
    // |channel tag|cache bank|cacheln tag|block index|word offset|
    // ------------------------------------------------------------
    // HASHED ADDRESS
    //        30:16|      15:10|       9:8|        7:6|        5:2|
    // ------------------------------------------------------------
    // |cacheln tag|block index|channel tag|cache bank|word offset|
    // ------------------------------------------------------------

    // e.g. cache has 64 sets, 16 words per block

    // EVA ADDRESS
    // ______________________________________________________________
    // |      30:16|      15:10|         9:6|        5:2|        1:0|
    // --------------------------------------------------------------
    // |cacheln tag|block index|hbm channels|word offset|byte offset|
    // --------------------------------------------------------------

    // HASHED EPA ADDRESS, NPA
    // ______________________________________________________________________
    // |       30:27|      26:12|       11:6|        5:2|        1:0| x cord|
    // --------------------------------------------------------------~~~~~~~~
    // |zero padding|cacheln tag|block index|word offset|byte offset|hbm chs|
    // --------------------------------------------------------------~~~~~~~~

    // HBM AXI ADDRESS
    // _________________________________________________________________
    // |       31:28|27|      26:12|       11:6|        5:2|        1:0|
    // -----------------------------------------------------------------
    // |hbm channels| 0|cacheln tag|block index|word offset|byte offset|
    // -----------------------------------------------------------------


    always_comb begin

      if (caches_per_axi_p == 1) begin
        wr_channel_li = axi_chan_width_lp'(i);
        rd_channel_li = axi_chan_width_lp'(i);
      end
      else if (num_axi4_p == 1) begin
        // channel is num of tiles x
        wr_channel_li = cache_axi4_lo[i].awaddr[0][cache_axi_addr_width_lp+:`BSG_SAFE_CLOG2(num_tiles_x_p)];
        rd_channel_li = cache_axi4_lo[i].araddr[0][cache_axi_addr_width_lp+:`BSG_SAFE_CLOG2(num_tiles_x_p)];
      end
      else begin
        wr_channel_li = {
          axi_chan_width_lp'(i),
          cache_axi4_lo[i].awaddr[0][cache_axi_addr_width_lp+:`BSG_SAFE_CLOG2(caches_per_axi_p)]
        };
        rd_channel_li = {
          axi_chan_width_lp'(i),
          cache_axi4_lo[i].araddr[0][cache_axi_addr_width_lp+:`BSG_SAFE_CLOG2(caches_per_axi_p)]
        };
      end

      wr_index_per_channel = cache_axi4_lo[i].awaddr[0][byte_offset_width_lp+word_offset_width_lp+:hashed_index_width_lp];
      rd_index_per_channel = cache_axi4_lo[i].araddr[0][byte_offset_width_lp+word_offset_width_lp+:hashed_index_width_lp];

    end

    if (ihash_enable_p == 1) begin : inv_hs
      // axi write address inverse hashing
      hash_function_reverse #(
        .width_p(block_index_width_lp),
        .banks_p(num_tiles_x_p       )
      ) hash_bank_wr (
        .index_i(wr_index_per_channel),
        .bank_i (wr_channel_li       ),
        .o      (wr_block_index_lo   )
      );

      // axi read address inverse hashing
      hash_function_reverse #(
        .width_p(block_index_width_lp),
        .banks_p(num_tiles_x_p       )
      ) hash_bank_rd (
        .index_i(rd_index_per_channel),
        .bank_i (rd_channel_li       ),
        .o      (rd_block_index_lo   )
      );
    end  // inv_hs
    else begin : mc_hash_unchanged

      assign wr_block_index_lo = {wr_channel_li, wr_index_per_channel};
      assign rd_block_index_lo = {rd_channel_li, rd_index_per_channel};

    end  // mc_hash

    always_comb begin
      // axi4 fwd
      m_axi4_lo_cast[i] = cache_axi4_lo[i];
      // axi4 rcv
      cache_axi4_li[i] = m_axi4_li_cast[i];

      m_axi4_lo_cast[i].awaddr = {
        {(axi_addr_width_p-block_index_width_lp-word_offset_width_lp-byte_offset_width_lp){1'b0}},
        wr_block_index_lo,
        cache_axi4_lo[i].awaddr[0][0+:byte_offset_width_lp+word_offset_width_lp]
      };

      m_axi4_lo_cast[i].araddr = {
        {(axi_addr_width_p-block_index_width_lp-word_offset_width_lp-byte_offset_width_lp){1'b0}},
        rd_block_index_lo,
        cache_axi4_lo[i].araddr[0][0+:byte_offset_width_lp+word_offset_width_lp]
      };
    end

  end  // mem_ch

  ////////////////////////////////
  // Configurable Memory System //
  ////////////////////////////////

  if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram
    || mem_cfg_p ==e_vcache_blocking_axi4_f1_model
    || mem_cfg_p == e_vcache_non_blocking_axi4_f1_dram
    || mem_cfg_p ==  e_vcache_non_blocking_axi4_f1_model
    || mem_cfg_p == e_vcache_blocking_axi4_hbm
    || mem_cfg_p == e_vcache_non_blocking_axi4_hbm) begin: lv1_dma

    logic [num_tiles_x_p-1:0][dma_pkt_width_lp-1:0] dma_pkt        ;
    logic [num_tiles_x_p-1:0]                       dma_pkt_v_lo   ;
    logic [num_tiles_x_p-1:0]                       dma_pkt_yumi_li;

    logic [num_tiles_x_p-1:0][data_width_p-1:0] dma_data_li      ;
    logic [num_tiles_x_p-1:0]                   dma_data_v_li    ;
    logic [num_tiles_x_p-1:0]                   dma_data_ready_lo;

    logic [num_tiles_x_p-1:0][data_width_p-1:0] dma_data_lo     ;
    logic [num_tiles_x_p-1:0]                   dma_data_v_lo   ;
    logic [num_tiles_x_p-1:0]                   dma_data_yumi_li;

  end

  // =================================================
  // LEVEL 1
  // =================================================

  if (mem_cfg_p == e_infinite_mem) begin : lv1_inf

    // each column has a nonsynth infinite memory
    for (genvar i = 0; i < num_tiles_x_p; i++) begin
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
        ,.my_x_i(cache_x_li[i])
        ,.my_y_i(cache_y_li[i])
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

  else if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram ||
           mem_cfg_p == e_vcache_blocking_axi4_f1_model ||
           mem_cfg_p == e_vcache_blocking_axi4_hbm) begin : lv1_vcache

    for (genvar i = 0; i < num_tiles_x_p; i++) begin : vcache
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
        .clk_i(clks_i[i/caches_per_axi_p])
        ,.reset_i(resets_i[i/caches_per_axi_p])
        // memory systems link from bsg_manycore_wrapper
        ,.link_sif_i(cache_link_sif_li[i])
        ,.link_sif_o(cache_link_sif_lo[i])
        // coordinates for memory system are determined by bsg_manycore_wrapper
        ,.my_x_i(cache_x_li[i])
        ,.my_y_i(cache_y_li[i])

        ,.dma_pkt_o(lv1_dma.dma_pkt[i])
        ,.dma_pkt_v_o(lv1_dma.dma_pkt_v_lo[i])
        ,.dma_pkt_yumi_i(lv1_dma.dma_pkt_yumi_li[i])

        ,.dma_data_i(lv1_dma.dma_data_li[i])
        ,.dma_data_v_i(lv1_dma.dma_data_v_li[i])
        ,.dma_data_ready_o(lv1_dma.dma_data_ready_lo[i])

        ,.dma_data_o(lv1_dma.dma_data_lo[i])
        ,.dma_data_v_o(lv1_dma.dma_data_v_lo[i])
        ,.dma_data_yumi_i(lv1_dma.dma_data_yumi_li[i])
      );
    end //  vcache

    // synopsys translate off
    bind bsg_cache vcache_profiler #(
      .data_width_p(data_width_p)
      ,.addr_width_p(addr_width_p)
    ) vcache_prof (
      .*
      ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
      ,.print_stat_v_i($root.tb.card.fpga.CL.mc_top.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.mc_top.print_stat_tag_lo)
    );
    // synopsys translate on


  end  // block lv1_vcache
  else if (mem_cfg_p == e_vcache_non_blocking_axi4_f1_dram ||
           mem_cfg_p == e_vcache_non_blocking_axi4_f1_model ||
           mem_cfg_p == e_vcache_non_blocking_axi4_hbm) begin : lv1_vcache_nb

    for (genvar i = 0; i < num_tiles_x_p; i++) begin: vcache
      bsg_manycore_vcache_non_blocking #(
        .data_width_p(data_width_p)
        ,.addr_width_p(addr_width_p)
        ,.block_size_in_words_p(block_size_in_words_p)
        ,.sets_p(sets_p)
        ,.ways_p(ways_p)

        ,.miss_fifo_els_p(miss_fifo_els_p)
        ,.x_cord_width_p(x_cord_width_p)
        ,.y_cord_width_p(y_cord_width_p)
        ,.load_id_width_p(load_id_width_p)
      ) vcache_nb (
        .clk_i(clks_i[i/caches_per_axi_p])
        ,.reset_i(resets_i[i/caches_per_axi_p])

        ,.link_sif_i(cache_link_sif_li[i])
        ,.link_sif_o(cache_link_sif_lo[i])

        ,.dma_pkt_o(lv1_dma.dma_pkt[i])
        ,.dma_pkt_v_o(lv1_dma.dma_pkt_v_lo[i])
        ,.dma_pkt_yumi_i(lv1_dma.dma_pkt_yumi_li[i])

        ,.dma_data_i(lv1_dma.dma_data_li[i])
        ,.dma_data_v_i(lv1_dma.dma_data_v_li[i])
        ,.dma_data_ready_o(lv1_dma.dma_data_ready_lo[i])

        ,.dma_data_o(lv1_dma.dma_data_lo[i])
        ,.dma_data_v_o(lv1_dma.dma_data_v_lo[i])
        ,.dma_data_yumi_i(lv1_dma.dma_data_yumi_li[i])
      );
    end

    // synopsys translate off
    bind bsg_cache_non_blocking vcache_non_blocking_profiler #(
      .data_width_p(data_width_p)
      ,.addr_width_p(addr_width_p)
      ,.sets_p(sets_p)
      ,.ways_p(ways_p)
      ,.id_width_p(id_width_p)
      ,.block_size_in_words_p(block_size_in_words_p)
    ) vcache_prof (
      .clk_i(clk_i)
      ,.reset_i(reset_i)

      ,.tl_data_mem_pkt_i(tl_data_mem_pkt_lo)
      ,.tl_data_mem_pkt_v_i(tl_data_mem_pkt_v_lo)
      ,.tl_data_mem_pkt_ready_i(tl_data_mem_pkt_ready_li)

      ,.mhu_idle_i(mhu_idle)

      ,.mhu_data_mem_pkt_i(mhu_data_mem_pkt_lo)
      ,.mhu_data_mem_pkt_v_i(mhu_data_mem_pkt_v_lo)
      ,.mhu_data_mem_pkt_yumi_i(mhu_data_mem_pkt_yumi_li)

      ,.miss_fifo_data_i(miss_fifo_data_li)
      ,.miss_fifo_v_i(miss_fifo_v_li)
      ,.miss_fifo_ready_i(miss_fifo_ready_lo)

      ,.dma_pkt_i(dma_pkt_o)
      ,.dma_pkt_v_i(dma_pkt_v_o)
      ,.dma_pkt_yumi_i(dma_pkt_yumi_i)

      ,.global_ctr_i($root.tb.card.fpga.CL.global_ctr)
      ,.print_stat_v_i($root.tb.card.fpga.CL.mc_top.print_stat_v_lo)
      ,.print_stat_tag_i($root.tb.card.fpga.CL.mc_top.print_stat_tag_lo)
    );
    // synopsys translate on

  end  // lv1_vcache_non_blocking

  // =================================================
  // LEVEL 2
  // =================================================

  if (mem_cfg_p == e_vcache_blocking_axi4_f1_dram ||
      mem_cfg_p == e_vcache_blocking_axi4_f1_model ||
      mem_cfg_p == e_vcache_non_blocking_axi4_f1_dram ||
      mem_cfg_p == e_vcache_non_blocking_axi4_f1_model ||
      mem_cfg_p == e_vcache_blocking_axi4_hbm ||
      mem_cfg_p == e_vcache_non_blocking_axi4_hbm) begin : lv2_4_axi4

    for (genvar i = 0; i < num_axi4_p; i++) begin : cache_to_axi

      bsg_cache_to_axi #(
        .addr_width_p         (cache_axi_addr_width_lp  ),
        .block_size_in_words_p(block_size_in_words_p),
        .data_width_p         (data_width_p         ),
        .num_cache_p          (caches_per_axi_p    ),

        .axi_id_width_p       (axi_id_width_p       ),
        .axi_addr_width_p     (axi_addr_width_p     ),
        .axi_data_width_p     (axi_data_width_p     ),
        .axi_burst_len_p      (axi_burst_len_p      )
      ) cache_to_axi (
        .clk_i           (clks_i[i]                 ),
        .reset_i         (resets_i[i]               ),

        .dma_pkt_i       (lv1_dma.dma_pkt[i]          ),
        .dma_pkt_v_i     (lv1_dma.dma_pkt_v_lo[i]     ),
        .dma_pkt_yumi_o  (lv1_dma.dma_pkt_yumi_li[i]  ),

        .dma_data_o      (lv1_dma.dma_data_li[i]      ),
        .dma_data_v_o    (lv1_dma.dma_data_v_li[i]    ),
        .dma_data_ready_i(lv1_dma.dma_data_ready_lo[i]),

        .dma_data_i      (lv1_dma.dma_data_lo[i]      ),
        .dma_data_v_i    (lv1_dma.dma_data_v_lo[i]    ),
        .dma_data_yumi_o (lv1_dma.dma_data_yumi_li[i] ),

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
