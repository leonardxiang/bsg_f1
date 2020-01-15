/**
 *  qmc_group_wrapper.v
 */

module qmc_group_wrapper
  import bsg_manycore_pkg::*;
  import bsg_noc_pkg::*;
#(
  parameter num_tiles_x_p = "inv"
  , parameter num_tiles_y_p = "inv"
  , parameter data_width_p = "inv"
  , parameter addr_width_p = "inv"
  , localparam x_cord_width_lp =`BSG_SAFE_CLOG2(num_tiles_x_p)
  , localparam y_cord_width_lp =`BSG_SAFE_CLOG2(num_tiles_y_p+2)
  , localparam link_sif_width_lp =
  `bsg_manycore_link_sif_width(addr_width_p,data_width_p,x_cord_width_lp,y_cord_width_lp)

  // processor
  , parameter dmem_size_p = "inv"
  , parameter icache_entries_p = "inv"
  , parameter icache_tag_width_p = "inv"
  , parameter epa_byte_addr_width_p = "inv"

  , parameter num_cache_p = "inv"
  , parameter vcache_size_p = "inv"
  , parameter vcache_block_size_in_words_p = "inv"
  , parameter vcache_sets_p = "inv"
  , parameter dram_ch_addr_width_p = "inv"

  , parameter branch_trace_en_p = "inv"
) (
  input                                                       clk_i
  ,input                                                       reset_i
  ,input        [      num_cache_p-1:0][link_sif_width_lp-1:0] cache_link_sif_i
  ,output logic [      num_cache_p-1:0][link_sif_width_lp-1:0] cache_link_sif_o
  ,output logic [      num_cache_p-1:0][  x_cord_width_lp-1:0] cache_x_o
  ,output logic [      num_cache_p-1:0][  y_cord_width_lp-1:0] cache_y_o
  ,input        [link_sif_width_lp-1:0]                        loader_link_sif_i
  ,output logic [link_sif_width_lp-1:0]                        loader_link_sif_o
);

  // for heterogeneous, this is a vector of num_tiles_x_p*num_tiles_y_p bytes;
  // each byte contains the type of core being instantiated
  // type 0: the standard node
  // type 9: qmc tile
  localparam qmc_tile_type_lp = 9;

  // enable debugging
  localparam debug_p = 0;

  // tile array
  localparam net_node_y_lp = num_tiles_y_p + 1;
  localparam int hetero_type_vec_p [0:net_node_y_lp-1][0:num_tiles_x_p-1]  =
  '{default:9};

  // this control how many extra IO rows are addressable in
  // the network outside of the manycore array
  localparam extra_io_rows_p = 1;

  // The number of registers between the reset_i port and the reset sinks
  // Must be >= 1
  localparam reset_depth_p = 3;

  // Suppose the first channel is connected to column 0
  localparam dram_ch_start_col_p  = 0;

  // The IO router row index, do not change in current qmc group setup!
  localparam IO_row_idx_p = 0;

  localparam dirs_lp = 4;

  parameter stub_p = {dirs_lp{1'b0}};             // {s,n,e,w}
  parameter repeater_output_p = {dirs_lp{1'b0}};  // {s,n,e,w}

  // manycore
  //
  `declare_bsg_manycore_link_sif_s(addr_width_p,data_width_p,x_cord_width_lp,y_cord_width_lp);

  bsg_manycore_link_sif_s [E:W][net_node_y_lp-1:0] hor_link_sif_li;
  bsg_manycore_link_sif_s [E:W][net_node_y_lp-1:0] hor_link_sif_lo;
  bsg_manycore_link_sif_s [S:N][num_tiles_x_p-1:0] ver_link_sif_li;
  bsg_manycore_link_sif_s [S:N][num_tiles_x_p-1:0] ver_link_sif_lo;

  bsg_manycore_link_sif_s [num_tiles_x_p-1:0] io_link_sif_li;
  bsg_manycore_link_sif_s [num_tiles_x_p-1:0] io_link_sif_lo;

// Manycore is stubbed out when running synthesis on the top-level chip
`ifndef SYNTHESIS_TOPLEVEL_STUB

  // synopsys translate_off
  initial begin
    int i,j;
    assert ((num_tiles_x_p > 0) && (net_node_y_lp > 0))
      else $error("num_tiles_x_p and net_node_y_lp must be positive constants");
    $display("## ----------------------------------------------------------------");
    $display("## MANYCORE HETERO TYPE CONFIGUREATIONS");
    $display("## ----------------------------------------------------------------");
    for(i=0; i < net_node_y_lp; i ++) begin
      $write("## ");
      for(j=0; j< num_tiles_x_p; j++) begin
        $write("%0d,", hetero_type_vec_p[i][j]);
      end
      if( i==0 ) begin
        $write(" //Ignored, Set to IO Router");
      end
      $write("\n");
    end
    $display("## ----------------------------------------------------------------");
  end
  // synopsys translate_on

  bsg_manycore_link_sif_s [net_node_y_lp-1:0][num_tiles_x_p-1:0][S:W] link_in;
  bsg_manycore_link_sif_s [net_node_y_lp-1:0][num_tiles_x_p-1:0][S:W] link_out;

  // Pipeline the reset. The bsg_manycore_tile has a single pipeline register
  // on reset already, so we only want to pipeline reset_depth_p-1 times.
  logic [reset_depth_p-1:0][net_node_y_lp-1:0][num_tiles_x_p-1:0] reset_i_r;

  assign reset_i_r[0] = {(net_node_y_lp*num_tiles_x_p){reset_i}};

  for (genvar k = 1; k < reset_depth_p; k++) begin
    always_ff @(posedge clk_i) begin
      reset_i_r[k] <= reset_i_r[k-1];
    end
  end

  // only used in the io row
  bsg_manycore_link_sif_s [net_node_y_lp-1:0][num_tiles_x_p-1:0] link_aux_in ;
  bsg_manycore_link_sif_s [net_node_y_lp-1:0][num_tiles_x_p-1:0] link_aux_out;

  bsg_manycore_link_sif_s [net_node_y_lp-1:0][num_tiles_x_p-1:0][S:W] link_qg_in;
  bsg_manycore_link_sif_s [net_node_y_lp-1:0][num_tiles_x_p-1:0][S:W] link_qg_out;

  for (genvar r = IO_row_idx_p+1; r < net_node_y_lp; r = r+1) begin: y
    for (genvar c = 0; c < num_tiles_x_p; c = c+1) begin: x

      // ======================================================================
      // qmc is implemented as connected FPGA boards
      // ======================================================================
      if (hetero_type_vec_p[r][c] == qmc_tile_type_lp) begin : qmc

        qcl_meshnode_subgroup #(
          .dirs_p                      (dirs_lp                     ),
          .x_cord_width_p              (x_cord_width_lp             ),
          .y_cord_width_p              (y_cord_width_lp             ),
          .data_width_p                (data_width_p                ),
          .addr_width_p                (addr_width_p                ),

          .dmem_size_p                 (dmem_size_p                 ),
          .icache_entries_p            (icache_entries_p            ),
          .icache_tag_width_p          (icache_tag_width_p          ),
          .epa_byte_addr_width_p       (epa_byte_addr_width_p       ),

          .num_tiles_x_p               (num_tiles_x_p               ),
          .vcache_size_p               (vcache_size_p               ),
          .vcache_block_size_in_words_p(vcache_block_size_in_words_p),
          .vcache_sets_p               (vcache_sets_p               ),
          .dram_ch_addr_width_p        (dram_ch_addr_width_p        ),
          .dram_ch_start_col_p         (dram_ch_start_col_p         ),

          .debug_p                     (debug_p                     ),
          .branch_trace_en_p           (branch_trace_en_p           )
        ) qgrp (
          .clk_i     (clk_i                           ),
          .reset_i   (reset_i_r[reset_depth_p-1][r][c]),
          .link_aux_i(link_aux_in[r][c]               ),
          .link_aux_o(link_aux_out[r][c]              ),
          .link_sif_i(link_qg_in[r][c]                ),
          .link_sif_o(link_qg_out[r][c]               ),
          .my_x_i    (x_cord_width_lp'(c)             ),
          .my_y_i    (y_cord_width_lp'(r)             )
        );


        // the N link has different definition, see *A* *B* below:

        if (r == 1) begin : r_01

          // remap the link of the first row, which internally contains io and qg
          // this nx2 sub mesh has node of 4 directions and an aux link

          // **** A *****
          assign link_qg_in[r][c][E:W] = link_in[r][c][E:W];
          assign link_out[r][c][E:W]   = link_qg_out[r][c][E:W];

          // the N link at (1, c) is ramapped
          // N link -> E link at the first row of the 1x2 sub mesh
          assign link_qg_in[r][c][N] = link_in[0][c][E];
          assign link_out[0][c][E]   = link_qg_out[r][c][N];

          assign link_qg_in[r][c][S] = link_in[r][c][S];
          assign link_out[r][c][S]   = link_qg_out[r][c][S];

          if (c == 0) begin : c0

            assign io_link_sif_lo[c] = link_aux_out[r][c];
            assign link_aux_in[r][c] = io_link_sif_li[c];

            // internally, we have W link -> x

          end // c0
          else begin : c_1p

            // AUX link -> W link at the first row of the 1x2 sub mesh
            assign link_out[0][c][W] = link_aux_out[r][c];
            assign link_aux_in[r][c] = link_in[0][c][W];

            // internally, we have io link -> x

          end // c_1p
        end // r_01

        else begin : r_2p

          // links from sub mesh is the same as that from the qg node
          // **** B ****
          // including the N links at (2p, c)
          assign link_out[r][c]   = link_qg_out[r][c];
          assign link_qg_in[r][c] = link_in[r][c];

        end // r2p
      end // qmc


      // ======================================================================
      // manycore is implemented as a chip
      // ======================================================================

      else begin : mc

        logic [link_sif_width_lp-1:0] proc_link_sif_li;
        logic [link_sif_width_lp-1:0] proc_link_sif_lo;

        //-------------------------------------------
        //As the manycore will distribute across large area, it will take long
        //time for the reset signal to propgate. We should register the reset
        //signal in each tile
        logic reset_r;
        always_ff @ (posedge clk_i) begin
          reset_r <= reset_i;
        end

        bsg_manycore_mesh_node #(
          .stub_p           (stub_p           ),
          .x_cord_width_p   (x_cord_width_lp  ),
          .y_cord_width_p   (y_cord_width_lp  ),
          .data_width_p     (data_width_p     ),
          .addr_width_p     (addr_width_p     ),
          .debug_p          (debug_p          ),
          .repeater_output_p(repeater_output_p)  // select buffer for this particular node
        ) rtr (
          .clk_i          (clk_i              ),
          .reset_i        (reset_r            ),
          .links_sif_i    (link_in[r][c]      ),
          .links_sif_o    (link_out[r][c]     ),
          .proc_link_sif_i(proc_link_sif_li   ),
          .proc_link_sif_o(proc_link_sif_lo   ),
          .my_x_i         (x_cord_width_lp'(c)),
          .my_y_i         (y_cord_width_lp'(r))
        );

        bsg_manycore_hetero_socket #(
          .x_cord_width_p              (x_cord_width_lp             ),
          .y_cord_width_p              (y_cord_width_lp             ),
          .data_width_p                (data_width_p                ),
          .addr_width_p                (addr_width_p                ),

          .dmem_size_p                 (dmem_size_p                 ),
          .vcache_size_p               (vcache_size_p               ),
          .icache_entries_p            (icache_entries_p            ),
          .icache_tag_width_p          (icache_tag_width_p          ),
          .epa_byte_addr_width_p       (epa_byte_addr_width_p       ),
          .dram_ch_addr_width_p        (dram_ch_addr_width_p        ),
          .dram_ch_start_col_p         (dram_ch_start_col_p         ),
          .hetero_type_p               (hetero_type_vec_p[r][c]     ),
          .num_tiles_x_p               (num_tiles_x_p               ),
          .vcache_block_size_in_words_p(vcache_block_size_in_words_p),
          .vcache_sets_p               (vcache_sets_p               ),

          .branch_trace_en_p           (branch_trace_en_p           ),

          .debug_p                     (debug_p                     )
        ) proc (
          .clk_i     (clk_i                           ),
          .reset_i   (reset_i_r[reset_depth_p-1][r][c]),

          .link_sif_i(proc_link_sif_lo                ),
          .link_sif_o(proc_link_sif_li                ),

          .my_x_i    (x_cord_width_lp'(c)             ),
          .my_y_i    (y_cord_width_lp'(r)             )
        );

        // if comes to the 1st row, add io at 0 row
        if (r == 1) begin : io

          bsg_manycore_mesh_node #(
            .x_cord_width_p (x_cord_width_lp),
            .y_cord_width_p (y_cord_width_lp),
            .data_width_p   (data_width_p   ),
            .addr_width_p   (addr_width_p   )
          ) io_router (
            .clk_i          (clk_i                           ),
            .reset_i        (reset_i_r[reset_depth_p-1][0][c]),

            .links_sif_i    (link_in [ IO_row_idx_p][ c ]    ),
            .links_sif_o    (link_out[ IO_row_idx_p][ c ]    ),

            .proc_link_sif_i(io_link_sif_li [ c ]            ),
            .proc_link_sif_o(io_link_sif_lo [ c ]            ),

            // tile coordinates
            .my_x_i         (x_cord_width_lp'(c)             ),
            .my_y_i         (y_cord_width_lp'(IO_row_idx_p)  )
          );

        end // io
      end // mc

    end // x
  end // y

  // stitch together all of the tiles into a mesh
  //
  bsg_mesh_stitch #(
    .width_p(link_sif_width_lp),
    .x_max_p(num_tiles_x_p    ),
    .y_max_p(net_node_y_lp    )
  ) link (
    .outs_i(link_out       ),
    .ins_o (link_in        ),
    .hor_i (hor_link_sif_li),
    .hor_o (hor_link_sif_lo),
    .ver_i (ver_link_sif_li),
    .ver_o (ver_link_sif_lo)
  );

`endif

  // connecting link_sif to outside
  //
  //  north[0]: host

  //  south[0] : victim cache 0
  //  south[1] : victim cache 1
  //  ...
  //
  for (genvar i = 0; i < num_cache_p; i++) begin
    assign cache_link_sif_o[i] = ver_link_sif_lo[S][i];
    assign ver_link_sif_li[S][i] = cache_link_sif_i[i];
  end

  // 0,0 for host io
  //
  assign loader_link_sif_o = io_link_sif_lo[0];
  assign io_link_sif_li[0] = loader_link_sif_i;

  // x,y for cache
  //
  for (genvar i = 0; i < num_cache_p; i++) begin
    assign cache_x_o[i] = (x_cord_width_lp)'(i);
    assign cache_y_o[i] = (y_cord_width_lp)'(net_node_y_lp);
  end

  // tie-off
  //
  for (genvar i = 0; i < net_node_y_lp; i++) begin : hor
    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_w (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.link_sif_i(hor_link_sif_lo[W][i])
      ,.link_sif_o(hor_link_sif_li[W][i])
    );

    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_e (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.link_sif_i(hor_link_sif_lo[E][i])
      ,.link_sif_o(hor_link_sif_li[E][i])
    );
  end

  for (genvar i = 0; i < num_tiles_x_p; i++) begin : ver_n
    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_n (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.link_sif_i(ver_link_sif_lo[N][i])
      ,.link_sif_o(ver_link_sif_li[N][i])
    );
  end

  for (genvar i = num_cache_p; i < num_tiles_x_p; i++) begin : cache
    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_s (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.link_sif_i(ver_link_sif_lo[S][i])
      ,.link_sif_o(ver_link_sif_li[S][i])
    );
  end

  for (genvar i = 1; i < num_tiles_x_p; i++) begin : io
    bsg_manycore_link_sif_tieoff #(
      .addr_width_p(addr_width_p)
      ,.data_width_p(data_width_p)
      ,.x_cord_width_p(x_cord_width_lp)
      ,.y_cord_width_p(y_cord_width_lp)
    ) tieoff_io (
      .clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.link_sif_i(io_link_sif_lo[i])
      ,.link_sif_o(io_link_sif_li[i])
    );
  end

endmodule
