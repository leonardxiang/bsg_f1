/*
* qcl_meshnode_subgroup.v
*
* consists of many FPGA boards as a subgroup
* Each group is controlled by one Vanilla Core in the measure node
*/

module qcl_meshnode_subgroup
  import qmc_runner_pkg::*;
  import qcl_node_pkg::*;
  import bsg_manycore_pkg::*;
  import qcl_network_pkg::*;
  import bsg_noc_pkg::*;
  import bsg_vanilla_pkg::*;
  #(
  // network
  parameter dirs_p = "inv"
  , parameter x_cord_width_p = "inv"
  , parameter y_cord_width_p = "inv"
  , parameter data_width_p = "inv"
  , parameter addr_width_p = "inv"
  , localparam link_sif_width_lp =
  `bsg_manycore_link_sif_width(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p)

  // processor
  , parameter dmem_size_p = "inv"
  , parameter icache_tag_width_p = "inv"
  , parameter icache_entries_p = "inv"
  , parameter epa_byte_addr_width_p = "inv"
  //
  , parameter num_tiles_x_p ="inv"
  , parameter vcache_size_p = "inv"
  , parameter vcache_block_size_in_words_p="inv"
  , parameter vcache_sets_p = "inv"
  , parameter dram_ch_addr_width_p = "inv"
  , parameter dram_ch_start_col_p = 0

  , parameter debug_p = 1
  , parameter branch_trace_en_p = 0
  ) (
  // system clock
  input                                                 clk_i
  ,input                                                 reset_i
  ,input  [link_sif_width_lp-1:0]                        link_aux_i
  ,output [link_sif_width_lp-1:0]                        link_aux_o
  ,input  [           dirs_p-1:0][link_sif_width_lp-1:0] link_sif_i
  ,output [           dirs_p-1:0][link_sif_width_lp-1:0] link_sif_o
  ,input  [   x_cord_width_p-1:0]                        my_x_i
  ,input  [   y_cord_width_p-1:0]                        my_y_i
  );

  // // For now, only instantiate one measure node

  qcl_link_s [dirs_p-1:0] board_link_li;
  qcl_link_s [dirs_p-1:0] board_link_lo;

  assign board_link_li = '0;

  // a qcl group is a node in the mesh network
  //
  `declare_bsg_manycore_link_sif_s(addr_width_p,data_width_p,x_cord_width_p,y_cord_width_p);

  logic [dirs_p-1:0][link_sif_width_lp-1:0] qg_link_sif_li;
  logic [dirs_p-1:0][link_sif_width_lp-1:0] qg_link_sif_lo;


  // TODO: change legacy router to wormhole like router

  logic [link_sif_width_lp-1:0] proc_link_sif_li;
  logic [link_sif_width_lp-1:0] proc_link_sif_lo;

  wire [$clog2(max_proc_nodes_gp)-1:0] brd_id_li = '0;

  qmc_runner_top #(
    .proc_enable_p               (1                           ),
    .brd_id_width_p              ($clog2(max_proc_nodes_gp)   ),
    .brd_link_els_p              (1                           ),

    .dirs_p                      (dirs_p                      ),
    .x_cord_width_p              (x_cord_width_p              ),
    .y_cord_width_p              (y_cord_width_p              ),
    .data_width_p                (data_width_p                ),
    .addr_width_p                (addr_width_p                ),

    .dmem_size_p                 (dmem_size_p                 ),
    .icache_tag_width_p          (icache_tag_width_p          ),
    .icache_entries_p            (icache_entries_p            ),
    .epa_byte_addr_width_p       (epa_byte_addr_width_p       ),

    .num_tiles_x_p               (num_tiles_x_p               ),
    .vcache_size_p               (vcache_size_p               ),
    .vcache_block_size_in_words_p(vcache_block_size_in_words_p),
    .vcache_sets_p               (vcache_sets_p               ),
    .dram_ch_addr_width_p        (dram_ch_addr_width_p        ),
    .dram_ch_start_col_p         (dram_ch_start_col_p         ),

    .debug_p                     (debug_p                     ),
    .branch_trace_en_p           (branch_trace_en_p           )
  ) runer (
    .clk_i       (clk_i        ),
    .reset_i     (reset_i      ),
    .board_link_i(board_link_li),
    .board_link_o(board_link_lo),
    .brd_id_i    (brd_id_li    ),

    .link_aux_i  (link_aux_i   ),
    .link_aux_o  (link_aux_o   ),
    .link_sif_i  (link_sif_i   ),
    .link_sif_o  (link_sif_o   ),
    .my_x_i      (my_x_i       ),
    .my_y_i      (my_y_i       )
  );

  endmodule
