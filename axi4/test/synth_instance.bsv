// see LICENSE for details on licensing

package synth_instance;

  import AXI4_Types   :: * ;
  import AXI4_Fabric  :: * ;
  import Vector       :: * ;
  import DefaultValue :: * ;
  import Connectable  :: * ;
  import GetPut       :: * ;
  
  `define wd_id 4
  `define wd_addr 32
  `define wd_data 64
  `define wd_user 0
  `define nslaves_bits TLog #(`nslaves)
  
  typedef AXI4_Fabric_IFC #(`nmasters,
			                      `nslaves,
			                      `wd_id,
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
    interface Vector#(`nmasters, AXI4_Server_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user)) m_fifo;
    interface Vector#(`nslaves,  AXI4_Client_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user)) s_fifo;
  endinterface
  
  (*synthesize*)                            
  module mkinst_onlyfabric (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkAXI4_Fabric (fn_mm, replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric

  (*synthesize*)                            
  module mkinst_onlyfabric_2 (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkAXI4_Fabric_2 (fn_mm, replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric_2

  (*synthesize*)
  module mkinst_withxactors (Ifc_withXactors);

    Vector #(`nmasters, AXI4_Master_Xactor_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkAXI4_Master_Xactor(defaultValue));

    Vector #(`nslaves, AXI4_Slave_Xactor_IFC#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_xactors <- replicateM(mkAXI4_Slave_Xactor(defaultValue));

    Fabric_AXI4_IFC fabric <- mkAXI4_Fabric (fn_mm, replicate('1));
    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_xactors[i].axi_side);
    end
    function AXI4_Server_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;
    function AXI4_Client_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user) f2 (Integer j)
      = s_xactors[j].fifo_side;
    interface m_fifo = genWith(f1);
    interface s_fifo = genWith(f2);
  endmodule:mkinst_withxactors
  
  (*synthesize*)
  module mkinst_withxactors_2 (Ifc_withXactors);

    Vector #(`nmasters, AXI4_Master_Xactor_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkAXI4_Master_Xactor_2);

    Vector #(`nslaves, AXI4_Slave_Xactor_IFC#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_xactors <- replicateM(mkAXI4_Slave_Xactor_2);

    Fabric_AXI4_IFC fabric <- mkAXI4_Fabric (fn_mm, replicate('1));
    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_xactors[i].axi_side);
    end
    function AXI4_Server_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;
    function AXI4_Client_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user) f2 (Integer j)
      = s_xactors[j].fifo_side;
    interface m_fifo = genWith(f1);
    interface s_fifo = genWith(f2);
  endmodule:mkinst_withxactors_2


endpackage
