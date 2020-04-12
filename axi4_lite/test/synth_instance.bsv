// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package synth_instance;

  import Vector       :: * ;
  import DefaultValue :: * ;
  import Connectable  :: * ;
  import GetPut       :: * ;
  import axi4l        :: * ;
  
  `define wd_addr 32
  `define wd_data 64
  `define wd_user 0
  `define nslaves_bits TLog #(`nslaves)
  
  typedef Ifc_axi4l_fabric #(`nmasters,
			                      `nslaves,
			                      `wd_addr,
			                      `wd_data,
			                      `wd_user)  Fabric_AXI4_IFC;

  function Bit#(`nslaves_bits) fn_mm(Bit#(`wd_addr) wd_addr);
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
  endfunction:fn_mm

  interface Ifc_withXactors;
    interface Vector#(`nmasters, Ifc_axi4l_server #(`wd_addr, `wd_data, `wd_user)) m_fifo;
    interface Vector#(`nslaves,  Ifc_axi4l_client #(`wd_addr, `wd_data, `wd_user)) s_fifo;
  endinterface
  
  (*synthesize*)                            
  module mkinst_onlyfabric (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkaxi4l_fabric (fn_mm, replicate('1), replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric

  (*synthesize*)                            
  module mkinst_onlyfabric_2 (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkaxi4l_fabric_2 (fn_mm, replicate('1), replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric_2

  (*synthesize*)
  module mkinst_withxactors (Ifc_withXactors);

    Vector #(`nmasters, Ifc_axi4l_master_xactor #(`wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkaxi4l_master_xactor(defaultValue));

    Vector #(`nslaves, Ifc_axi4l_slave_xactor#(`wd_addr, `wd_data, `wd_user))
        s_xactors <- replicateM(mkaxi4l_slave_xactor(defaultValue));

    Fabric_AXI4_IFC fabric <- mkaxi4l_fabric (fn_mm, replicate('1), replicate('1));

    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axil_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_xactors[i].axil_side);
    end

    function Ifc_axi4l_server #(`wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;
    function Ifc_axi4l_client #(`wd_addr, `wd_data, `wd_user) f2 (Integer j)
      = s_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
    interface s_fifo = genWith(f2);
  endmodule:mkinst_withxactors
  
  (*synthesize*)
  module mkinst_withxactors_2 (Ifc_withXactors);

    Vector #(`nmasters, Ifc_axi4l_master_xactor #(`wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkaxi4l_master_xactor_2);

    Vector #(`nslaves, Ifc_axi4l_slave_xactor#(`wd_addr, `wd_data, `wd_user))
        s_xactors <- replicateM(mkaxi4l_slave_xactor_2);

    Fabric_AXI4_IFC fabric <- mkaxi4l_fabric (fn_mm, replicate('1), replicate('1));

    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axil_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_xactors[i].axil_side);
    end

    function Ifc_axi4l_server #(`wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;
    function Ifc_axi4l_client #(`wd_addr, `wd_data, `wd_user) f2 (Integer j)
      = s_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
    interface s_fifo = genWith(f2);
  endmodule:mkinst_withxactors_2


endpackage
