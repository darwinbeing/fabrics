package axi4_template;
  import AXI4_Types  :: *;
  import AXI4_Fabric :: *;
  
  //import Fabric_Defs :: *;    // for Wd_Addr, Wd_Data, Wd_User

  `define Num_Masters 3
  `define Num_Slaves 5
  `define Wd_Id 3
  `define Wd_Addr 32
  `define Wd_Data 64
  `define Wd_User 0
  `define Num_Slaves_bits TLog#(`Num_Slaves)
  
  typedef AXI4_Fabric_IFC #(`Num_Masters,
			                      `Num_Slaves,
			                      `Wd_Id,
			                      `Wd_Addr,
			                      `Wd_Data,
			                      `Wd_User)  Fabric_AXI4_IFC;

  (*synthesize*)                            
  module mkFabric_AXI4(Fabric_AXI4_IFC);

    function Tuple2#(Bool, Bit#(`Num_Slaves_bits)) fn_addr_to_slave_num(Bit#(`Wd_Addr) wd_addr);
      Bool matched_yet= False;
      Bit#(`Num_Slaves_bits) lv_slave_num= `Num_Slaves -1;

      for(Bit#(`Num_Slaves_bits) i=0; i<`Num_Slaves-1; i=i+1) begin
        Bit#(TSub#(`Wd_Addr,8)) lv_i= zeroExtend(i);
        if(wd_addr < {lv_i, 8'd0} && !matched_yet) begin
          matched_yet= True;
          lv_slave_num= i;
        end
      end

      return tuple2(matched_yet, lv_slave_num);
    endfunction

    AXI4_Fabric_IFC #(`Num_Masters, `Num_Slaves, `Wd_Id, `Wd_Addr, `Wd_Data, `Wd_User)
      fabric <- mkAXI4_Fabric (fn_addr_to_slave_num);

   return fabric;

  endmodule
endpackage
