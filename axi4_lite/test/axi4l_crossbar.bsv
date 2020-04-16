// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package axi4l_crossbar;

  import Vector       :: * ;
  import DefaultValue :: * ;
  import Connectable  :: * ;
  import GetPut       :: * ;
  import axi4l         :: * ;
  
  // --------- change the following parameters ----------//
  `define wd_addr             32
  `define wd_data             64
  `define wd_user             0
  `define tn_num_masters      1
  `define tn_num_slaves       1
  `define fixed_priority_rd   0
  `define fixed_priority_wr   0
  `define write_slave         1
  `define read_slave          1
  // ---------------------------------------------------//

  `define tn_num_slaves_bits TLog #(`tn_num_slaves)
  
  typedef Ifc_axi4l_fabric #(`tn_num_masters, `tn_num_slaves, `wd_addr, `wd_data, `wd_user)  Fabric_AXI4_IFC;

  //----------------------change the following memory map for read-channel  -------------------- //
  function Bit#(TMax#(`tn_num_slaves_bits,1)) fn_rd_memory_map(Bit#(`wd_addr) wd_addr);
    if (wd_addr >= 'h1000 && wd_addr < 'h2000)
      return 0;
    else if (wd_addr >= 'h2000 && wd_addr < 'h3000)
      return truncate(4'd1);
    else if (wd_addr >= 'h3000 && wd_addr < 'h4000)
      return truncate(4'd2);
    else if (wd_addr >= 'h4000 && wd_addr < 'h5000)
      return truncate(4'd3);
    else
      return truncate(4'd4);
  endfunction:fn_rd_memory_map
  // -------------------------------------------------------------------------------------------//

  //----------------------change the following memory map for write-channel  -------------------- //
  function Bit#(TMax#(`tn_num_slaves_bits,1)) fn_wr_memory_map(Bit#(`wd_addr) wd_addr);
    if (wd_addr >= 'h1000 && wd_addr < 'h2000)
      return 0;
    else if (wd_addr >= 'h2000 && wd_addr < 'h3000)
      return truncate(4'd1);
    else if (wd_addr >= 'h3000 && wd_addr < 'h4000)
      return truncate(4'd2);
    else if (wd_addr >= 'h4000 && wd_addr < 'h5000)
      return truncate(4'd3);
    else
      return truncate(4'd4);
  endfunction:fn_wr_memory_map
  // -------------------------------------------------------------------------------------------//

  (*synthesize, clock_prefix = "ACLK", reset_prefix="ARESETN"*)
  module mkaxi4l_crossbar (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkaxi4l_fabric (fn_rd_memory_map, fn_wr_memory_map, `read_slave,
                                            `write_slave, `fixed_priority_rd, `fixed_priority_wr);
    return fabric;
  endmodule:mkaxi4l_crossbar

  (*synthesize, clock_prefix = "ACLK", reset_prefix="ARESETN"*)
  module mkaxi4l_crossbar_2 (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkaxi4l_fabric_2 (fn_rd_memory_map, fn_wr_memory_map, `read_slave,
                                            `write_slave, `fixed_priority_rd, `fixed_priority_wr);
    return fabric;
  endmodule:mkaxi4l_crossbar_2

endpackage:axi4l_crossbar
