// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package axi4_xactors;

  import Vector       :: * ;
  import DefaultValue :: * ;
  import Connectable  :: * ;
  import GetPut       :: * ;
  import axi4         :: * ;
  
  // --------- change the following parameters ----------//
  `define wd_id               4
  `define wd_addr             32
  `define wd_data             64
  `define wd_user             0
  `define tn_num_masters      1
  `define tn_num_slaves       1
  `define fixed_priority_rd  'b1
  `define fixed_priority_wr  'b1
  // ---------------------------------------------------//
  `define tn_num_slaves_bits TLog #(`tn_num_slaves)
  
  typedef Ifc_axi4_fabric #(`tn_num_masters,
			                      `tn_num_slaves,
			                      `wd_id,
			                      `wd_addr,
			                      `wd_data,
			                      `wd_user)  Fabric_AXI4_IFC;

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

  (*synthesize*)
  module mkaxi4_masterxactor(Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user));
    let ifc();
    mkaxi4_master_xactor#(defaultValue) _temp(ifc);
    return ifc;
  endmodule
  
  (*synthesize*)
  module mkaxi4_slavexactor(Ifc_axi4_slave_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user));
    let ifc();
    mkaxi4_slave_xactor#(defaultValue) _temp(ifc);
    return ifc;
  endmodule
  
  (*synthesize*)
  module mkaxi4_masterxactor_2(Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user));
    let ifc();
    mkaxi4_master_xactor_2 _temp(ifc);
    return ifc;
  endmodule
  
  (*synthesize*)
  module mkaxi4_slavexactor_2(Ifc_axi4_slave_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user));
    let ifc();
    mkaxi4_slave_xactor_2 _temp(ifc);
    return ifc;
  endmodule

  interface Ifc_withXactors;
    interface Vector#(`tn_num_masters, Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user)) m_fifo;
    interface Vector#(`tn_num_slaves,  Ifc_axi4_client #(`wd_id, `wd_addr, `wd_data, `wd_user)) s_fifo;
  endinterface

  (*synthesize*)
  module mkaxi4_xactorcrossbar (Ifc_withXactors);

    Vector #(`tn_num_masters, Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkaxi4_masterxactor);

    Vector #(`tn_num_slaves, Ifc_axi4_slave_xactor#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_xactors <- replicateM(mkaxi4_slavexactor);

    Fabric_AXI4_IFC fabric <- mkaxi4_fabric (fn_rd_memory_map, fn_wr_memory_map,
                                            `fixed_priority_rd, `fixed_priority_wr);

    for (Integer i = 0; i<`tn_num_masters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi4_side);
    end
    for (Integer i = 0; i<`tn_num_slaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_xactors[i].axi4_side);
    end

    function Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;
    function Ifc_axi4_client #(`wd_id, `wd_addr, `wd_data, `wd_user) f2 (Integer j)
      = s_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
    interface s_fifo = genWith(f2);
  endmodule:mkaxi4_xactorcrossbar
  
  (*synthesize*)
  module mkaxi4_xactorcrossbar_2 (Ifc_withXactors);

    Vector #(`tn_num_masters, Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkaxi4_masterxactor_2);

    Vector #(`tn_num_slaves, Ifc_axi4_slave_xactor#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_xactors <- replicateM(mkaxi4_slavexactor_2);

    Fabric_AXI4_IFC fabric <- mkaxi4_fabric (fn_rd_memory_map, fn_wr_memory_map,
                                            `fixed_priority_rd, `fixed_priority_wr);

    for (Integer i = 0; i<`tn_num_masters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi4_side);
    end
    for (Integer i = 0; i<`tn_num_slaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_xactors[i].axi4_side);
    end

    function Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;
    function Ifc_axi4_client #(`wd_id, `wd_addr, `wd_data, `wd_user) f2 (Integer j)
      = s_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
    interface s_fifo = genWith(f2);
  endmodule:mkaxi4_xactorcrossbar_2


endpackage:axi4_xactors
