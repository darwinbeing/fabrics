// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala
Email id: neelgala@incoresemi.com
Details:

*/
package APB_Fabric;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
`include "Logger.bsv"

import APB_Types    :: * ;

interface APB_Fabric_IFC #( numeric type wd_addr, 
                            numeric type wd_data, 
                            numeric type wd_user, 
                            numeric type tn_num_slaves );

  interface APB_Slave_IFC #(wd_addr, wd_data, wd_user) from_master;
  interface Vector#(tn_num_slaves, APB_Master_IFC #(wd_addr, wd_data, wd_user)) v_to_slaves;

endinterface:APB_Fabric_IFC

module mkAPB_Fabric #( function Bit#(tn_num_slaves) fn_addr_map (Bit#(wd_addr) addr))
                     (APB_Fabric_IFC #(wd_addr, wd_data, wd_user, tn_num_slaves));
 
  let v_num_slaves = valueOf(tn_num_slaves);
 
  // define wires carrying information from the master
  Wire#(APB_Request #(wd_addr, wd_data, wd_user))   wr_m_request    <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_m_psel       <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_m_penable    <- mkBypassWire;
  /*doc:reg: */
  Wire#(APB_Response #(wd_data, wd_user))           wr_m_response   <- mkBypassWire;
  Wire#(Bool)                                       wr_m_pready     <- mkBypassWire;

  // defining wires carrying information to the slaves
  Vector#(tn_num_slaves, Wire#(APB_Request #(wd_addr, wd_data, wd_user))) 
                                wr_s_request <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(APB_Response #(wd_data, wd_user)))
                                wr_s_response <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(Bool))  wr_s_penable  <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(Bool))  wr_s_psel     <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(Bool))  wr_s_pready   <- replicateM(mkBypassWire);

  let slave_select = fn_addr_map(wr_m_request.paddr);

  for (Integer i = 0; i<v_num_slaves; i = i + 1) begin
    rule rl_select_slave;
      wr_s_request [i] <= wr_m_request;
      wr_s_penable [i] <= wr_m_penable;
      if ( slave_select[i] == 1)
        wr_s_psel[i] <= wr_m_psel;
    endrule:rl_select_slave

    rule rl_select_response (slave_select[i] == 1);
      wr_m_response <= APB_Response {prdata : wr_s_response[i].prdata,
                                    pslverr : wr_s_response[i].pslverr,
                                    puser   : wr_s_response[i].puser };
      wr_m_pready <= wr_s_pready[i];
    endrule:rl_select_response

    /*interface v_to_slaves = interface APB_Slave_IFC
      
      method m_paddr    =  wr_s_request[i].paddr;
      method m_prot     =  wr_s_request[i].prot;
      method m_penable  =  wr_s_penable[i];
      method m_pwrite   =  wr_s_request[i].pwrite;
      method m_pwdata   =  wr_s_request[i].pwdata;
      method m_pstrb    =  wr_s_request[i].pstrb;
      method m_psel     =  wr_s_psel[i];
      method m_puser    =  wr_s_request[i].puser;
    endinterface;*/
  end


  interface from_master = interface APB_Slave_IFC
    method Action s_paddr( Bit#(wd_addr)           paddr,
                           Bit#(3)                 prot,
                           Bool                    penable,
                           Bool                    pwrite,
                           Bit#(wd_data)           pwdata,
                           Bit#(TDiv#(wd_data,8))  pstrb,
                           Bool                    psel ,
                           Bit#(wd_user)           puser   );
      wr_m_request <= APB_Request {paddr  : paddr,       
                                prot   : prot,
                                pwrite : pwrite,
                                pwdata : pwdata,
                                pstrb  : pstrb,
                                puser  : puser   };

      wr_m_psel    <=  psel;
      wr_m_penable <=  penable;
    endmethod
    // outputs from slave
    method s_pready  = wr_m_pready;
    method s_prdata  = wr_m_response.prdata;
    method s_pslverr = wr_m_response.pslverr;
    method s_puser   = wr_m_response.puser;
  endinterface;
endmodule:mkAPB_Fabric

function Bit#(5) fn_is_IO (Bit#(32) addr);
  if (addr < 'h1000 )
    return 'b00001;
  else if (addr >= 'h1000 && addr < 'h2000)
    return 'b00010;
  else if (addr >= 'h2000 && addr < 'h3000)
    return 'b00100;
  else if (addr >= 'h3000 && addr < 'h4000)
    return 'b01000;
  else
    return 'b10000;
endfunction
module mkTb(APB_Fabric_IFC#(32, 64, 0, 5));
  let ifc();
  mkAPB_Fabric #(fn_is_IO) _temp(ifc);
  return (ifc);
endmodule:mkTb


endpackage:APB_Fabric

