// see LICENSE for details on licensing

package AXI4_instance;

  import AXI4_Types  :: *;
  import AXI4_Fabric :: *;
  
  `define Num_Masters 1
  `define Num_Slaves 2
  `define Wd_Id 3
  `define Wd_Addr 32
  `define Wd_Data 64
  `define Wd_User 5
  `define Num_Slaves_bits TLog #(`Num_Slaves)
  
  typedef AXI4_Fabric_IFC #(`Num_Masters,
			                      `Num_Slaves,
			                      `Wd_Id,
			                      `Wd_Addr,
			                      `Wd_Data,
			                      `Wd_User)  Fabric_AXI4_IFC;

    function Bit#(`Num_Slaves_bits) fn_addr_to_slave_num(Bit#(`Wd_Addr) wd_addr);
      if (wd_addr >= 'h1000 && wd_addr < 'h2000)
        return 0;
      /*else if (wd_addr >= 'h2000 && wd_addr < 'h3000)
        return 1;
      else if (wd_addr >= 'h3000 && wd_addr < 'h4000)
        return 2;
      else if (wd_addr >= 'h4000 && wd_addr < 'h5000)
        return 3;*/
      else
        return 1;
    endfunction:fn_addr_to_slave_num

  (*synthesize*)                            
  module mkinstance (Fabric_AXI4_IFC);

      Fabric_AXI4_IFC fabric <- mkAXI4_Fabric (fn_addr_to_slave_num);

   return fabric;

  endmodule:mkinstance
endpackage
