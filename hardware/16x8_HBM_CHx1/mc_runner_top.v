/*
* mc_runner_top.v
*
*/

`include "bsg_defines.v"
`include "bsg_axi_bus_pkg.vh"

module mc_runner_top
  import cl_manycore_pkg::*;
  import bsg_cache_pkg::*;
#(
  parameter num_axi4_p = 1
  , parameter mc_to_io_cdc_p = 0
  , parameter mc_to_mem_cdc_p = 0
  , parameter axi_id_width_p = "inv"
  , parameter axi_addr_width_p = "inv"
  , parameter axi_data_width_p = "inv"
  , parameter async_fifo_els_p = 16
  , localparam axil_mosi_bus_width_lp = `bsg_axil_mosi_bus_width(1)
  , localparam axil_miso_bus_width_lp = `bsg_axil_miso_bus_width(1)
  , localparam axi4_mosi_bus_width_lp = `bsg_axi4_mosi_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
  , localparam axi4_miso_bus_width_lp = `bsg_axi4_miso_bus_width(1, axi_id_width_p, axi_addr_width_p, axi_data_width_p)
) (
  input                                                           clk_core_i
  ,input                                                           reset_core_i
  ,input                                                           clk_io_i
  ,input                                                           reset_io_i
  ,input  [            num_axi4_p-1:0]                             clk_mem_i
  ,input  [            num_axi4_p-1:0]                             reset_mem_i
  // AXI Lite Master Interface connections
  ,input  [axil_mosi_bus_width_lp-1:0]                             s_axil_bus_i
  ,output [axil_miso_bus_width_lp-1:0]                             s_axil_bus_o
  // AXI Memory Mapped interface out
  ,output [            num_axi4_p-1:0][axi4_mosi_bus_width_lp-1:0] m_axi4_bus_o
  ,input  [            num_axi4_p-1:0][axi4_miso_bus_width_lp-1:0] m_axi4_bus_i
);


  // -------------------------------------------------
  // AXI-Lite casting
  // -------------------------------------------------
  `declare_bsg_axil_bus_s(1, bsg_axil_mosi_bus_s, bsg_axil_miso_bus_s);
  bsg_axil_mosi_bus_s m_axil_lo_cast;
  bsg_axil_miso_bus_s m_axil_li_cast;

  assign m_axil_lo_cast = s_axil_bus_i;
  assign s_axil_bus_o   = m_axil_li_cast;


  // -------------------------------------------------
  // manycore signals
  // -------------------------------------------------
  `declare_bsg_manycore_link_sif_s(addr_width_p, data_width_p, x_cord_width_p, y_cord_width_p, load_id_width_p);

  // -----------------------------------------------------------
  bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_li;
  bsg_manycore_link_sif_s [num_cache_p-1:0] cache_link_sif_lo;

  // after cdc
  bsg_manycore_link_sif_s [num_cache_p-1:0] mem_link_sif_li;
  bsg_manycore_link_sif_s [num_cache_p-1:0] mem_link_sif_lo;


  // -----------------------------------------------------------
  bsg_manycore_link_sif_s loader_link_sif_lo;
  bsg_manycore_link_sif_s loader_link_sif_li;
  // after cdc
  bsg_manycore_link_sif_s mcl_link_sif_li;
  bsg_manycore_link_sif_s mcl_link_sif_lo;

  logic [num_cache_p-1:0][x_cord_width_p-1:0] cache_x_lo;
  logic [num_cache_p-1:0][y_cord_width_p-1:0] cache_y_lo;

  // manycore wrapper
  //
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
    .clk_i(clk_core_i)
    ,.reset_i(reset_core_i)

    ,.cache_link_sif_i(cache_link_sif_li)
    ,.cache_link_sif_o(cache_link_sif_lo)

    ,.cache_x_o(cache_x_lo)
    ,.cache_y_o(cache_y_lo)

    ,.loader_link_sif_i(loader_link_sif_li)
    ,.loader_link_sif_o(loader_link_sif_lo)
  );


  // manycore to axil host link clock domain crossing
  //
  if (mc_to_io_cdc_p == 1) begin : mc_cdc_io

    bsg_manycore_link_sif_s io_async_link_sif_li;
    bsg_manycore_link_sif_s io_async_link_sif_lo;

    assign mcl_link_sif_li = io_async_link_sif_lo;
    assign io_async_link_sif_li = mcl_link_sif_lo;

    bsg_manycore_link_sif_async_buffer #(
      .addr_width_p   (addr_width_p    ),
      .data_width_p   (data_width_p    ),
      .x_cord_width_p (x_cord_width_p  ),
      .y_cord_width_p (y_cord_width_p  ),
      .load_id_width_p(load_id_width_p ),
      .fifo_els_p     (async_fifo_els_p)
    ) async_buf (
      // core side
      .L_clk_i     (clk_core_i          ),
      .L_reset_i   (reset_core_i        ),
      .L_link_sif_i(loader_link_sif_lo  ),
      .L_link_sif_o(loader_link_sif_li  ),

      // AXI-L side
      .R_clk_i     (clk_io_i            ),
      .R_reset_i   (reset_io_i          ),
      .R_link_sif_i(io_async_link_sif_li),
      .R_link_sif_o(io_async_link_sif_lo)
    );

  end : mc_cdc_io
  else begin : mc_to_io

    assign mcl_link_sif_li   = loader_link_sif_lo;
    assign loader_link_sif_li = mcl_link_sif_lo;

  end

  localparam caches_per_axi4_lp = num_cache_p/num_axi4_p;

  //synopsys translate_off
  initial begin
    assert(num_axi4_p * caches_per_axi4_lp == num_cache_p)
      else $fatal(0, "[%m] num_cache_p must be multiple of  num_axi4_p!\n");
  end
  //synopsys translate_on

  // manycore to axi4 memory clock domain crossing
  //
  if (mc_to_mem_cdc_p == 1) begin : mc_cdc_mem

    bsg_manycore_link_sif_s [num_cache_p-1:0] cache_async_link_sif_li;
    bsg_manycore_link_sif_s [num_cache_p-1:0] cache_async_link_sif_lo;

    for (genvar i = 0; i < num_cache_p; i++) begin : io_async_buf

      bsg_manycore_link_sif_async_buffer #(
        .addr_width_p   (addr_width_p    ),
        .data_width_p   (data_width_p    ),
        .x_cord_width_p (x_cord_width_p  ),
        .y_cord_width_p (y_cord_width_p  ),
        .load_id_width_p(load_id_width_p ),
        .fifo_els_p     (async_fifo_els_p)
      ) async_buf (
        // core side
        .L_clk_i     (clk_core_i                       ),
        .L_reset_i   (reset_core_i                     ),
        .L_link_sif_i(cache_link_sif_lo[i]             ),
        .L_link_sif_o(cache_link_sif_li[i]             ),

        // AXI-L side
        .R_clk_i     (clk_mem_i[i*caches_per_axi4_lp]  ),
        .R_reset_i   (reset_mem_i[i*caches_per_axi4_lp]),
        .R_link_sif_i(cache_async_link_sif_li[i]       ),
        .R_link_sif_o(cache_async_link_sif_lo[i]       )
      );

      assign mem_link_sif_li[i]         = cache_async_link_sif_lo[i];
      assign cache_async_link_sif_li[i] = mem_link_sif_lo[i];

    end : io_async_buf
  end : mc_cdc_mem
  else begin : mc_to_mem

    assign mem_link_sif_li   = cache_link_sif_lo;
    assign cache_link_sif_li = mem_link_sif_lo;

  end : mc_to_mem


  // Configurable Memory System
  //
  localparam byte_offset_width_lp = `BSG_SAFE_CLOG2(data_width_p>>3)     ;
  localparam cache_addr_width_lp  = (addr_width_p-1+byte_offset_width_lp);
  `declare_bsg_cache_dma_pkt_s(cache_addr_width_lp);

  mc_memory_hierarchy #(
    .data_width_p     (data_width_p      ),
    .addr_width_p     (addr_width_p      ),
    .x_cord_width_p   (x_cord_width_p    ),
    .y_cord_width_p   (y_cord_width_p    ),
    .load_id_width_p  (load_id_width_p   ),
    .num_cache_p      (num_cache_p       ),
    .num_axi4_p       (num_axi4_p        ),
    .caches_per_axi4_p(caches_per_axi4_lp),
    .axi_id_width_p   (axi_id_width_p    ),
    .axi_addr_width_p (axi_addr_width_p  ),
    .axi_data_width_p (axi_data_width_p  ),
    .ihash_enable_p   (0)
  ) mem_sys (
    .clks_i      (clk_mem_i      ),
    .resets_i    (reset_mem_i    ),
    .link_sif_i  (mem_link_sif_li),
    .link_sif_o  (mem_link_sif_lo),
    .m_axi4_bus_o(m_axi4_bus_o   ),
    .m_axi4_bus_i(m_axi4_bus_i   )
  );

  // manycore link old

 logic [x_cord_width_p-1:0] mcl_x_cord_lp = '0;
 logic [y_cord_width_p-1:0] mcl_y_cord_lp = '0;

 logic                      print_stat_v_lo;
 logic [data_width_p-1:0]   print_stat_tag_lo;

axil_to_mcl #(
  .num_mcl_p        (1                ),
  .num_tiles_x_p    (num_tiles_x_p    ),
  .num_tiles_y_p    (num_tiles_y_p    ),
  .addr_width_p     (addr_width_p     ),
  .data_width_p     (data_width_p     ),
  .x_cord_width_p   (x_cord_width_p   ),
  .y_cord_width_p   (y_cord_width_p   ),
  .load_id_width_p  (load_id_width_p  ),
  .max_out_credits_p(max_out_credits_p)
) axil_to_mcl_inst (
  .clk_i             (clk_io_i              ),
  .reset_i           (reset_io_i            ),

  // axil slave interface
  .s_axil_mcl_awvalid(m_axil_lo_cast.awvalid),
  .s_axil_mcl_awaddr (m_axil_lo_cast.awaddr ),
  .s_axil_mcl_awready(m_axil_li_cast.awready),
  .s_axil_mcl_wvalid (m_axil_lo_cast.wvalid ),
  .s_axil_mcl_wdata  (m_axil_lo_cast.wdata  ),
  .s_axil_mcl_wstrb  (m_axil_lo_cast.wstrb  ),
  .s_axil_mcl_wready (m_axil_li_cast.wready ),
  .s_axil_mcl_bresp  (m_axil_li_cast.bresp  ),
  .s_axil_mcl_bvalid (m_axil_li_cast.bvalid ),
  .s_axil_mcl_bready (m_axil_lo_cast.bready ),
  .s_axil_mcl_araddr (m_axil_lo_cast.araddr ),
  .s_axil_mcl_arvalid(m_axil_lo_cast.arvalid),
  .s_axil_mcl_arready(m_axil_li_cast.arready),
  .s_axil_mcl_rdata  (m_axil_li_cast.rdata  ),
  .s_axil_mcl_rresp  (m_axil_li_cast.rresp  ),
  .s_axil_mcl_rvalid (m_axil_li_cast.rvalid ),
  .s_axil_mcl_rready (m_axil_lo_cast.rready ),

  // manycore link
  .link_sif_i        (mcl_link_sif_li       ),
  .link_sif_o        (mcl_link_sif_lo       ),
  .my_x_i            (mcl_x_cord_lp         ),
  .my_y_i            (mcl_y_cord_lp         ),

  .print_stat_v_o    (print_stat_v_lo       ),
  .print_stat_tag_o  (print_stat_tag_lo     )
);


endmodule
