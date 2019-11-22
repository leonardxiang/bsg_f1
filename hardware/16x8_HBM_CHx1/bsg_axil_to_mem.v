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

/*
* axil_config.sv
*
*/

// Note: address[31:0] = {(32-base_addr_wdith_p)'X, base_addr_wdith_p-mem_addr_width_p'h???, mem_addr_width_p'h???}

`include "bsg_axi_bus_pkg.vh"

module bsg_axil_to_mem #(
  parameter mem_addr_width_p = "inv"
  ,parameter base_addr_wdith_p = "inv"
  ,parameter axil_base_addr_p = "inv" // 32'hxxxx_xxxx
  ,parameter axil_mosi_bus_width_lp = `bsg_axil_mosi_bus_width(1)
  ,parameter axil_miso_bus_width_lp = `bsg_axil_miso_bus_width(1)
) (
  input                               clk_i
  ,input                               reset_i
  ,input  [axil_mosi_bus_width_lp-1:0] s_axil_bus_i
  ,output [axil_miso_bus_width_lp-1:0] s_axil_bus_o
  ,output [      mem_addr_width_p-1:0] addr_o
  ,output                              wen_o
  ,output                              ren_o
  ,output [                      31:0] data_o
  ,input  [                      31:0] data_i
  ,output                              done_o
);

// synopsys translate_off
initial begin
  assert (mem_addr_width_p <= base_addr_wdith_p)
    else $fatal(0, "## [%m]: config address width should not exceed axil base address width!\n");

  assert (base_addr_wdith_p < 32)
    else $fatal(0, "## [%m]: axil base address should not exceed 32!\n")
end
// synopsys translate_on

`declare_bsg_axil_bus_s(1, bsg_axil_mosi_bus_s, bsg_axil_miso_bus_s);
bsg_axil_mosi_bus_s s_axil_bus_i_cast;
bsg_axil_miso_bus_s s_axil_bus_o_cast;

assign s_axil_bus_i_cast = s_axil_bus_i;
assign s_axil_bus_o = s_axil_bus_o_cast;

// ----------------
// axil signals
// ----------------
// axil write
logic [31:0] axil_awaddr_li;
logic [31:0] axil_wdata_li;
logic axil_awvalid_li;
logic axil_wvalid_li;

// axil read
logic [31:0] axil_araddr_li;
logic axil_arvalid_li;
logic axil_rready_li;

logic [31:0] axil_rdata_lo;
logic axil_arready_lo;
logic axil_rvalid_lo;

logic axil_awready_lo;
logic axil_wready_lo;

// axil bus
logic axil_bready_li
logic axil_bvalid_lo;

assign axil_awaddr_li  = s_axil_bus_i_cast.awaddr;
assign axil_wdata_li   = s_axil_bus_i_cast.wdata;
assign axil_awvalid_li = s_axil_bus_i_cast.awvalid;
assign axil_wvalid_li  = s_axil_bus_i_cast.wvalid;

assign s_axil_bus_o_cast.awready = axil_awready_lo;
assign s_axil_bus_o_cast.wready  = axil_wready_lo;

assign axil_araddr_li  = s_axil_bus_i_cast.araddr;
assign axil_arvalid_li = s_axil_bus_i_cast.arvalid;
assign axil_rready_li  = s_axil_bus_i_cast.rready;

assign s_axil_bus_o_cast.rdata   = axil_rdata_lo;
assign s_axil_bus_o_cast.arready = axil_arready_lo;
assign s_axil_bus_o_cast.rvalid  = axil_rvalid_lo;
assign s_axil_bus_o_cast.rresp   = 2'b00;

assign axil_bready_li = s_axil_bus_i_cast.bready;
assign s_axil_bus_o_cast.bvalid = axil_bvalid_lo;
assign s_axil_bus_o_cast.bresp = 2'b00;


// control from reg config stage
//
logic cfg_done_o  ; // data transfer finish signal

// axil config interface
typedef enum logic[2:0] {
   E_AXIL_IDLE = 0,
   E_AXIL_ADDR = 1,
   E_AXIL_DATA = 2,
   E_AXIL_RESP = 3
   } axil_state_e;

axil_state_e axil_state_r, axil_state_n;


// -------------
// control logic
// -------------
always_comb begin
  axil_state_n = axil_state_r;
  case (axil_state_r)

    E_AXIL_IDLE : begin
      if (axil_awvalid_li & axil_awready_lo)
        axil_state_n = E_AXIL_ADDR;
      else if (axil_arvalid_li & axil_arready_lo)
        axil_state_n = E_AXIL_DATA;
      else
        axil_state_n = E_AXIL_IDLE;
    end

    E_AXIL_ADDR : begin
      axil_state_n = E_AXIL_DATA;
    end

    E_AXIL_DATA : begin
      if (cfg_done_o)
        axil_state_n = E_AXIL_RESP;
      else
        axil_state_n = E_AXIL_DATA;
    end

    E_AXIL_RESP : begin
      if (axil_b_r_ready)
        axil_state_n = E_AXIL_IDLE;
      else
        axil_state_n = E_AXIL_RESP;
    end
    default : axil_state_n = E_AXIL_IDLE;
  endcase
end

// state machine
always_ff @(posedge clk_i) begin
  if (reset_i)
    axil_state_r <= E_AXIL_IDLE;
  else
    axil_state_r <= axil_state_n;
end

// data from reg config stage
logic [31:0] r_data_li;
logic [31:0] r_addr_li;
logic [31:0] w_addr_li;

logic [ mem_addr_width_p-1:0] mem_addr_r_lo ;
logic [31:0] mem_data_r_lo;

logic wen_r0;
logic ren_r0;
logic wen_r_lo;
logic ren_r_lo;

logic done_r_lo;

assign data_o = mem_data_r_lo;
assign addr_o = mem_addr_r_lo;
assign r_data_li = data_i;
assign wen_o = wen_r_lo;
assign ren_o = ren_r_lo;

assign done_o = done_r_lo;



// write select
//
logic is_wr_not_rd;
always_ff @(posedge clk_i) begin
  if (reset_i)
    is_wr_not_rd <= 1'b0;
  else if (axil_state_r==E_AXIL_IDLE)
    is_wr_not_rd <= axil_awvalid_li;
end

// address select
//
always_ff @(posedge clk_i) begin
  if (reset_i)
    {r_addr_li, w_addr_li} <= 64'd0;
  else if ((axil_state_r == E_AXIL_IDLE) && axil_awvalid_li)
    w_addr_li <= axil_awaddr_li;
  else if ((axil_state_r == E_AXIL_IDLE) && axil_arvalid_li)
    r_addr_li <= axil_araddr_li;
end

wire [31:0] axil_addr_li = is_wr_not_rd ? w_addr_li : r_addr_li;

wire addr_hit_v = (axil_addr_li[axil_base_addr_width_p+:4] == axil_base_addr_p[axil_base_addr_width_p+:4]);

// flop mem address
logic [mem_addr_width_p-1:0] mem_addr_r_lo;
always_ff @(posedge clk_i) begin
  if (reset_i)
    mem_addr_r_lo <= '0;
  else
    mem_addr_r_lo <= axil_addr_li[mem_addr_width_p-1:0];
end

// -------------
// DATA PATH
// -------------
logic [31:0] w_data_r0;



// write data
always_ff @(posedge clk_i)
   if (reset_i)
     w_data_r0 <= '0;
   else
     w_data_r0 <= axil_wdata_li;

// read data
always_ff @(posedge clk_i)
  if (reset_i)
    axil_rdata_lo <= 0;
  else if (cfg_done_o)
    axil_rdata_lo <= addr_hit_v ? r_data_li : 32'hdead_beef;


always_ff @(posedge clk_i) begin
  if (wen_r0||ren_r0) begin
    mem_addr_r_lo  <= mem_addr_r_lo;
    mem_data_r_lo <= w_data_r0;
  end
end


// -------------
// data path
// -------------
assign axil_rvalid_lo = (axil_state_r==E_AXIL_RESP) && !is_wr_not_rd;
assign axil_bvalid_lo = (axil_state_r==E_AXIL_RESP) && is_wr_not_rd;

wire axil_b_r_ready = (is_wr_not_rd) ? axil_bready_li : axil_rready_li;

// write ready
always_ff @(posedge clk_i) begin
  if (reset_i) begin
    axil_awready_lo <= 0;
    axil_wready_lo  <= 0;
    axil_arready_lo <= 0;
  end
  else begin
    // CHECK: we assume that awvalid signal will never be deasserted during the E_AXIL_ADDR cycle
    axil_awready_lo <= (axil_state_r == E_AXIL_IDLE) && (axil_awvalid_li);
    axil_wready_lo  <= ((axil_state_r == E_AXIL_DATA) && (cfg_done_o)) && is_wr_not_rd;
    axil_arready_lo <= ((axil_state_r == E_AXIL_DATA) && (cfg_done_o)) && ~is_wr_not_rd;
  end
end





// -------------
// control logic
// -------------


// cfg data valid (read is always valid in REGISTER MODULE)
wire mem_en = (is_wr_not_rd) ? axil_wvalid_li : 1'b1;

logic in_accessing;
always_ff @(posedge clk_i) begin
  if (reset_i) begin
    wen_r0 <= 0;
    ren_r0 <= 0;
  end
  else begin
    wen_r0 <= addr_hit_v ? ((axil_state_r==E_AXIL_DATA) & mem_en & is_wr_not_rd & !in_accessing) : 1'b0;
    ren_r0 <= addr_hit_v ? ((axil_state_r==E_AXIL_DATA) & mem_en & !is_wr_not_rd & !in_accessing) : 1'b0;
  end
end

always_ff @(posedge clk_i)
  if (axil_state_r==E_AXIL_IDLE) begin
    in_accessing <= 0;
  end
  else if (wen_r0 || ren_r0) begin
    in_accessing <= 1;
  end

always @(posedge clk_i)
   if (reset_i) begin
      wen_r_lo <= 0;
      ren_r_lo <= 0;
   end
   else begin
      wen_r_lo <= wen_r0 || (wen_r_lo && !done_r_lo);
      ren_r_lo <= ren_r0 || (ren_r_lo && !done_r_lo);
   end

always_ff @(posedge clk_i)
   if (reset_i)
      done_r_lo <= 0;
   else
      done_r_lo <= ((wen_r_lo||ren_r_lo) && !done_r_lo);

assign cfg_done_o = addr_hit_v ? done_r_lo : 1'b1;


endmodule
