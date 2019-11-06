/**
*  axi4_data_width_converter.v
*
*/

`include "bsg_axi_bus_pkg.vh"

module axi4_data_width_converter #(
  parameter id_width_p = "inv"
  , parameter addr_width_p = "inv"
  , parameter s_data_width_p = "inv"
  , parameter m_data_width_p = "inv"
  , parameter device_family = "inv"
  , localparam axi4_si_bus_width_lp = `bsg_axi4_mosi_bus_width(1, id_width_p, addr_width_p, s_data_width_p)
  , localparam axi4_so_bus_width_lp = `bsg_axi4_miso_bus_width(1, id_width_p, addr_width_p, s_data_width_p)
  , localparam axi4_mo_bus_width_lp = `bsg_axi4_mosi_bus_width(1, id_width_p, addr_width_p, m_data_width_p)
  , localparam axi4_mi_bus_width_lp = `bsg_axi4_miso_bus_width(1, id_width_p, addr_width_p, m_data_width_p)
) (
  input                             clk_i
  ,input                             reset_i
  ,input  [axi4_si_bus_width_lp-1:0] s_axi4_i
  ,output [axi4_so_bus_width_lp-1:0] s_axi4_o
  ,output [axi4_mo_bus_width_lp-1:0] m_axi4_o
  ,input  [axi4_mi_bus_width_lp-1:0] m_axi4_i
);

  `declare_bsg_axi4_bus_s(1, id_width_p, addr_width_p, s_data_width_p, bsg_axi4_si_bus_s, bsg_axi4_so_bus_s);
  `declare_bsg_axi4_bus_s(1, id_width_p, addr_width_p, m_data_width_p, bsg_axi4_mo_bus_s, bsg_axi4_mi_bus_s);

  bsg_axi4_si_bus_s s_axi4_li_cast;
  bsg_axi4_so_bus_s s_axi4_lo_cast;
  bsg_axi4_mo_bus_s m_axi4_lo_cast;
  bsg_axi4_mi_bus_s m_axi4_li_cast;

  assign s_axi4_li_cast = s_axi4_i;
  assign s_axi4_o = s_axi4_lo_cast;
  assign m_axi4_o = m_axi4_lo_cast;
  assign m_axi4_li_cast = m_axi4_i;

axi_dwidth_converter_v2_1_19_top #(
  .C_FAMILY            (device_family ),
  .C_AXI_PROTOCOL      (0             ),
  .C_S_AXI_ID_WIDTH    (id_width_p    ),
  .C_SUPPORTS_ID       (1             ),
  .C_AXI_ADDR_WIDTH    (addr_width_p  ),
  .C_S_AXI_DATA_WIDTH  (s_data_width_p),
  .C_M_AXI_DATA_WIDTH  (m_data_width_p),
  .C_AXI_SUPPORTS_WRITE(1             ),
  .C_AXI_SUPPORTS_READ (1             ),
  .C_FIFO_MODE         (0             ),
  .C_S_AXI_ACLK_RATIO  (1             ),
  .C_M_AXI_ACLK_RATIO  (2             ), // TODO: Does this change?
  .C_AXI_IS_ACLK_ASYNC (0             ),
  .C_MAX_SPLIT_BEATS   (16            ),
  .C_PACKING_LEVEL     (1             ),
  .C_SYNCHRONIZER_STAGE(3             )
) inst (
  .s_axi_aclk    (clk_i                  ),
  .s_axi_aresetn (~reset_i               ),

  .s_axi_awid    (s_axi4_li_cast.awid    ), //
  .s_axi_awaddr  (s_axi4_li_cast.awaddr  ),
  .s_axi_awlen   (s_axi4_li_cast.awlen   ),
  .s_axi_awsize  (s_axi4_li_cast.awsize  ),
  .s_axi_awburst (s_axi4_li_cast.awburst ),
  .s_axi_awlock  (s_axi4_li_cast.awlock  ),
  .s_axi_awcache (s_axi4_li_cast.awcache ),
  .s_axi_awprot  (s_axi4_li_cast.awprot  ),
  .s_axi_awregion(s_axi4_li_cast.awregion),
  .s_axi_awqos   (s_axi4_li_cast.awqos   ),
  .s_axi_awvalid (s_axi4_li_cast.awvalid ),
  .s_axi_awready (s_axi4_lo_cast.awready ),

  .s_axi_wdata   (s_axi4_li_cast.wdata   ),
  .s_axi_wstrb   (s_axi4_li_cast.wstrb   ),
  .s_axi_wlast   (s_axi4_li_cast.wlast   ),
  .s_axi_wvalid  (s_axi4_li_cast.wvalid  ),
  .s_axi_wready  (s_axi4_lo_cast.wready  ),

  .s_axi_bid     (s_axi4_lo_cast.bid     ),
  .s_axi_bresp   (s_axi4_lo_cast.bresp   ),
  .s_axi_bvalid  (s_axi4_lo_cast.bvalid  ),
  .s_axi_bready  (s_axi4_li_cast.bready  ),

  .s_axi_arid    (s_axi4_li_cast.arid    ), //
  .s_axi_araddr  (s_axi4_li_cast.araddr  ),
  .s_axi_arlen   (s_axi4_li_cast.arlen   ),
  .s_axi_arsize  (s_axi4_li_cast.arsize  ),
  .s_axi_arburst (s_axi4_li_cast.arburst ),
  .s_axi_arlock  (s_axi4_li_cast.arlock  ),
  .s_axi_arcache (s_axi4_li_cast.arcache ),
  .s_axi_arprot  (s_axi4_li_cast.arprot  ),
  .s_axi_arregion(s_axi4_li_cast.arregion),
  .s_axi_arqos   (s_axi4_li_cast.arqos   ),
  .s_axi_arvalid (s_axi4_li_cast.arvalid ),
  .s_axi_arready (s_axi4_lo_cast.arready ),

  .s_axi_rid     (s_axi4_lo_cast.rid     ),
  .s_axi_rdata   (s_axi4_lo_cast.rdata   ),
  .s_axi_rresp   (s_axi4_lo_cast.rresp   ),
  .s_axi_rlast   (s_axi4_lo_cast.rlast   ),
  .s_axi_rvalid  (s_axi4_lo_cast.rvalid  ),
  .s_axi_rready  (s_axi4_li_cast.rready  ),

  .m_axi_aclk    (1'H0                   ), //
  .m_axi_aresetn (1'H0                   ), //

  .m_axi_awaddr  (m_axi4_lo_cast.awaddr  ),
  .m_axi_awlen   (m_axi4_lo_cast.awlen   ),
  .m_axi_awsize  (m_axi4_lo_cast.awsize  ),
  .m_axi_awburst (m_axi4_lo_cast.awburst ),
  .m_axi_awlock  (m_axi4_lo_cast.awlock  ),
  .m_axi_awcache (m_axi4_lo_cast.awcache ),
  .m_axi_awprot  (m_axi4_lo_cast.awprot  ),
  .m_axi_awregion(m_axi4_lo_cast.awregion),
  .m_axi_awqos   (m_axi4_lo_cast.awqos   ),
  .m_axi_awvalid (m_axi4_lo_cast.awvalid ),
  .m_axi_awready (m_axi4_li_cast.awready ),
  .m_axi_wdata   (m_axi4_lo_cast.wdata   ),
  .m_axi_wstrb   (m_axi4_lo_cast.wstrb   ),
  .m_axi_wlast   (m_axi4_lo_cast.wlast   ),
  .m_axi_wvalid  (m_axi4_lo_cast.wvalid  ),
  .m_axi_wready  (m_axi4_li_cast.wready  ),

  .m_axi_bresp   (m_axi4_li_cast.bresp   ),
  .m_axi_bvalid  (m_axi4_li_cast.bvalid  ),
  .m_axi_bready  (m_axi4_lo_cast.bready  ),

  .m_axi_araddr  (m_axi4_lo_cast.araddr  ),
  .m_axi_arlen   (m_axi4_lo_cast.arlen   ),
  .m_axi_arsize  (m_axi4_lo_cast.arsize  ),
  .m_axi_arburst (m_axi4_lo_cast.arburst ),
  .m_axi_arlock  (m_axi4_lo_cast.arlock  ),
  .m_axi_arcache (m_axi4_lo_cast.arcache ),
  .m_axi_arprot  (m_axi4_lo_cast.arprot  ),
  .m_axi_arregion(m_axi4_lo_cast.arregion),
  .m_axi_arqos   (m_axi4_lo_cast.arqos   ),
  .m_axi_arvalid (m_axi4_lo_cast.arvalid ),
  .m_axi_arready (m_axi4_li_cast.arready ),

  .m_axi_rdata   (m_axi4_li_cast.rdata   ),
  .m_axi_rresp   (m_axi4_li_cast.rresp   ),
  .m_axi_rlast   (m_axi4_li_cast.rlast   ),
  .m_axi_rvalid  (m_axi4_li_cast.rvalid  ),
  .m_axi_rready  (m_axi4_lo_cast.rready  )
);

  assign m_axi4_lo_cast.awid = '0;
  assign m_axi4_lo_cast.arid = '0;

endmodule : axi4_data_width_converter
