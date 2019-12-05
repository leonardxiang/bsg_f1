/**
*  axil_demux.v
*
*/

`include "bsg_axi_bus_pkg.vh"

module axil_demux #(
  parameter num_axil_p = "inv"
  , parameter axil_base_addr_p = (num_axil_p*64)'(0)
  , parameter device_family = "virtexuplus"
  , parameter axil_base_addr_width_p = 12  // normally, we do not change
  , localparam axil_mosi_bus_width_lp = `bsg_axil_mosi_bus_width(1)
  , localparam axil_miso_bus_width_lp = `bsg_axil_miso_bus_width(1)
) (
  input                                                           clk_i
  ,input                                                           reset_i
  ,input  [axil_mosi_bus_width_lp-1:0]                             s_axil_ser_i
  ,output [axil_miso_bus_width_lp-1:0]                             s_axil_ser_o
  ,output [            num_axil_p-1:0][axil_mosi_bus_width_lp-1:0] m_axil_par_o
  ,input  [            num_axil_p-1:0][axil_miso_bus_width_lp-1:0] m_axil_par_i
);

  // synopsys translate_off
  initial begin
    assert (num_axil_p <= 16)
      else begin
        $error("## axil mux master slot can not exceed 16!");
        $finish();
      end
  end
  // synopsys translate_on

  `declare_bsg_axil_bus_s(1, bsg_axil_mosi_bus_s, bsg_axil_miso_bus_s);
  bsg_axil_mosi_bus_s s_axil_bus_li_cast;
  bsg_axil_miso_bus_s s_axil_bus_lo_cast;

  assign s_axil_bus_li_cast = s_axil_ser_i;
  assign s_axil_ser_o       = s_axil_bus_lo_cast;

  bsg_axil_mosi_bus_s [num_axil_p-1:0] m_axil_par_lo_cast;
  bsg_axil_miso_bus_s [num_axil_p-1:0] m_axil_par_li_cast;

  assign m_axil_par_o = m_axil_par_lo_cast;
  assign m_axil_par_li_cast = m_axil_par_i;

  `declare_bsg_axil_bus_s(num_axil_p, bsg_axil_mo_buses_s, bsg_axil_mi_buses_s);
  bsg_axil_mo_buses_s m_axil_lo_cast;
  bsg_axil_mi_buses_s m_axil_li_cast;

  for (genvar i=0; i<num_axil_p; i=i+1) begin : axil_trans
    always_comb begin: axil_bus_assignment
      m_axil_par_lo_cast[i] = {
        m_axil_lo_cast.awaddr[32*i+:32]
        ,m_axil_lo_cast.awvalid[i]
        ,m_axil_lo_cast.wdata[32*i+:32]
        ,m_axil_lo_cast.wstrb[4*i+:4]
        ,m_axil_lo_cast.wvalid[i]
        ,m_axil_lo_cast.bready[i]
        ,m_axil_lo_cast.araddr[32*i+:32]
        ,m_axil_lo_cast.arvalid[i]
        ,m_axil_lo_cast.rready[i]
      };

      {
        m_axil_li_cast.awready[i]
        ,m_axil_li_cast.wready[i]
        ,m_axil_li_cast.bresp[2*i+:2]
        ,m_axil_li_cast.bvalid[i]
        ,m_axil_li_cast.arready[i]
        ,m_axil_li_cast.rdata[32*i+:32]
        ,m_axil_li_cast.rresp[2*i+:2]
        ,m_axil_li_cast.rvalid[i]
      } = m_axil_par_li_cast[i];
    end
  end

  localparam C_NUM_MASTER_SLOTS         = num_axil_p                                       ;
  localparam C_M_AXI_BASE_ADDR          = axil_base_addr_p                                 ;
  localparam C_M_AXI_ADDR_WIDTH         = {C_NUM_MASTER_SLOTS{32'(axil_base_addr_width_p)}};
  localparam C_M_AXI_WRITE_CONNECTIVITY = {C_NUM_MASTER_SLOTS{32'h0000_0001}}              ;
  localparam C_M_AXI_READ_CONNECTIVITY  = {C_NUM_MASTER_SLOTS{32'h0000_0001}}              ;
  localparam C_M_AXI_WRITE_ISSUING      = {C_NUM_MASTER_SLOTS{32'h0000_0001}}              ;
  localparam C_M_AXI_READ_ISSUING       = {C_NUM_MASTER_SLOTS{32'h0000_0001}}              ;

  axi_crossbar_v2_1_20_axi_crossbar #(
    .C_FAMILY                   (device_family             ),
    .C_NUM_SLAVE_SLOTS          (1                         ),
    .C_NUM_MASTER_SLOTS         (C_NUM_MASTER_SLOTS        ),
    .C_AXI_ID_WIDTH             (1                         ),
    .C_AXI_ADDR_WIDTH           (32                        ),
    .C_AXI_DATA_WIDTH           (32                        ),
    .C_AXI_PROTOCOL             (2                         ),
    .C_NUM_ADDR_RANGES          (1                         ),
    .C_M_AXI_BASE_ADDR          (C_M_AXI_BASE_ADDR         ),
    .C_M_AXI_ADDR_WIDTH         (C_M_AXI_ADDR_WIDTH        ),
    .C_S_AXI_BASE_ID            (32'H00000000              ),
    .C_S_AXI_THREAD_ID_WIDTH    (32'H00000000              ),
    .C_AXI_SUPPORTS_USER_SIGNALS(0                         ),
    .C_AXI_AWUSER_WIDTH         (1                         ),
    .C_AXI_ARUSER_WIDTH         (1                         ),
    .C_AXI_WUSER_WIDTH          (1                         ),
    .C_AXI_RUSER_WIDTH          (1                         ),
    .C_AXI_BUSER_WIDTH          (1                         ),
    .C_M_AXI_WRITE_CONNECTIVITY (C_M_AXI_WRITE_CONNECTIVITY),
    .C_M_AXI_READ_CONNECTIVITY  (C_M_AXI_READ_CONNECTIVITY ),
    .C_R_REGISTER               (1                         ),
    .C_S_AXI_SINGLE_THREAD      (32'H00000001              ),
    .C_S_AXI_WRITE_ACCEPTANCE   (32'H00000001              ),
    .C_S_AXI_READ_ACCEPTANCE    (32'H00000001              ),
    .C_M_AXI_WRITE_ISSUING      (C_M_AXI_WRITE_ISSUING     ),
    .C_M_AXI_READ_ISSUING       (C_M_AXI_READ_ISSUING      ),
    .C_S_AXI_ARB_PRIORITY       (32'H00000000              ),
    .C_M_AXI_SECURE             (32'h00000000              ),
    .C_CONNECTIVITY_MODE        (0                         )
  ) axil_crossbar_mux (
    .aclk          (clk_i                     ),
    .aresetn       (~reset_i                  ),
    .s_axi_awid    (1'H0                      ),
    .s_axi_awaddr  (s_axil_bus_li_cast.awaddr ),
    .s_axi_awlen   (8'H00                     ),
    .s_axi_awsize  (3'H0                      ),
    .s_axi_awburst (2'H0                      ),
    .s_axi_awlock  (1'H0                      ),
    .s_axi_awcache (4'H0                      ),
    .s_axi_awprot  (3'H0                      ),
    .s_axi_awqos   (4'H0                      ),
    .s_axi_awuser  (1'H0                      ),
    .s_axi_awvalid (s_axil_bus_li_cast.awvalid),
    .s_axi_awready (s_axil_bus_lo_cast.awready),
    .s_axi_wid     (1'H0                      ),
    .s_axi_wdata   (s_axil_bus_li_cast.wdata  ),
    .s_axi_wstrb   (s_axil_bus_li_cast.wstrb  ),
    .s_axi_wlast   (1'H1                      ),
    .s_axi_wuser   (1'H0                      ),
    .s_axi_wvalid  (s_axil_bus_li_cast.wvalid ),
    .s_axi_wready  (s_axil_bus_lo_cast.wready ),
    .s_axi_bid     (                          ),
    .s_axi_bresp   (s_axil_bus_lo_cast.bresp  ),
    .s_axi_buser   (                          ),
    .s_axi_bvalid  (s_axil_bus_lo_cast.bvalid ),
    .s_axi_bready  (s_axil_bus_li_cast.bready ),
    .s_axi_arid    (1'H0                      ),
    .s_axi_araddr  (s_axil_bus_li_cast.araddr ),
    .s_axi_arlen   (8'H00                     ),
    .s_axi_arsize  (3'H0                      ),
    .s_axi_arburst (2'H0                      ),
    .s_axi_arlock  (1'H0                      ),
    .s_axi_arcache (4'H0                      ),
    .s_axi_arprot  (3'H0                      ),
    .s_axi_arqos   (4'H0                      ),
    .s_axi_aruser  (1'H0                      ),
    .s_axi_arvalid (s_axil_bus_li_cast.arvalid),
    .s_axi_arready (s_axil_bus_lo_cast.arready),
    .s_axi_rid     (                          ),
    .s_axi_rdata   (s_axil_bus_lo_cast.rdata  ),
    .s_axi_rresp   (s_axil_bus_lo_cast.rresp  ),
    .s_axi_rlast   (                          ),
    .s_axi_ruser   (                          ),
    .s_axi_rvalid  (s_axil_bus_lo_cast.rvalid ),
    .s_axi_rready  (s_axil_bus_li_cast.rready ),
    .m_axi_awid    (                          ),
    .m_axi_awaddr  (m_axil_lo_cast.awaddr     ),
    .m_axi_awlen   (                          ),
    .m_axi_awsize  (                          ),
    .m_axi_awburst (                          ),
    .m_axi_awlock  (                          ),
    .m_axi_awcache (                          ),
    .m_axi_awprot  (                          ),
    .m_axi_awregion(                          ),
    .m_axi_awqos   (                          ),
    .m_axi_awuser  (                          ),
    .m_axi_awvalid (m_axil_lo_cast.awvalid    ),
    .m_axi_awready (m_axil_li_cast.awready    ),
    .m_axi_wid     (                          ),
    .m_axi_wdata   (m_axil_lo_cast.wdata      ),
    .m_axi_wstrb   (m_axil_lo_cast.wstrb      ),
    .m_axi_wlast   (                          ),
    .m_axi_wuser   (                          ),
    .m_axi_wvalid  (m_axil_lo_cast.wvalid     ),
    .m_axi_wready  (m_axil_li_cast.wready     ),
    .m_axi_bid     ({C_NUM_MASTER_SLOTS{1'b0}}),
    .m_axi_bresp   (m_axil_li_cast.bresp      ),
    .m_axi_buser   ({C_NUM_MASTER_SLOTS{1'b0}}),
    .m_axi_bvalid  (m_axil_li_cast.bvalid     ),
    .m_axi_bready  (m_axil_lo_cast.bready     ),
    .m_axi_arid    (                          ),
    .m_axi_araddr  (m_axil_lo_cast.araddr     ),
    .m_axi_arlen   (                          ),
    .m_axi_arsize  (                          ),
    .m_axi_arburst (                          ),
    .m_axi_arlock  (                          ),
    .m_axi_arcache (                          ),
    .m_axi_arprot  (                          ),
    .m_axi_arregion(                          ),
    .m_axi_arqos   (                          ),
    .m_axi_aruser  (                          ),
    .m_axi_arvalid (m_axil_lo_cast.arvalid    ),
    .m_axi_arready (m_axil_li_cast.arready    ),
    .m_axi_rid     ({C_NUM_MASTER_SLOTS{1'b0}}),
    .m_axi_rdata   (m_axil_li_cast.rdata      ),
    .m_axi_rresp   (m_axil_li_cast.rresp      ),
    .m_axi_rlast   ({C_NUM_MASTER_SLOTS{1'b1}}),
    .m_axi_ruser   ({C_NUM_MASTER_SLOTS{1'b0}}),
    .m_axi_rvalid  (m_axil_li_cast.rvalid     ),
    .m_axi_rready  (m_axil_lo_cast.rready     )
  );

endmodule
