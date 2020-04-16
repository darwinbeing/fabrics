// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala
Email id: neelgala@incoresemi.com
Details:

*/
package apb_fabric;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
`include "Logger.bsv"

import apb_types    :: * ;

interface Ifc_apb_fabric #( numeric type wd_addr, 
                            numeric type wd_data, 
                            numeric type wd_user, 
                            numeric type tn_num_slaves );

  interface Ifc_apb_slave #(wd_addr, wd_data, wd_user) frm_master;
  interface Vector#(tn_num_slaves, Ifc_apb_master #(wd_addr, wd_data, wd_user)) v_to_slaves;

endinterface:Ifc_apb_fabric

module mkapb_fabric #( function Bit#(tn_num_slaves) fn_addr_map (Bit#(wd_addr) addr))
                     (Ifc_apb_fabric #(wd_addr, wd_data, wd_user, tn_num_slaves));
 
  let v_num_slaves = valueOf(tn_num_slaves);
 
  // define wires carrying information from the master
  Wire#(APB_request #(wd_addr, wd_data, wd_user))   wr_m_request    <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_m_psel       <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_m_penable    <- mkBypassWire;
  /*doc:reg: */
  Wire#(APB_response #(wd_data, wd_user))           wr_m_response   <- mkBypassWire;
  Wire#(Bool)                                       wr_m_pready     <- mkBypassWire;

  // defining wires carrying information to the slaves
  Vector#(tn_num_slaves, Wire#(APB_request #(wd_addr, wd_data, wd_user))) 
                                wr_s_request <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(APB_response #(wd_data, wd_user)))
                                wr_s_response <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(Bool))  wr_s_penable  <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(Bool))  wr_s_psel     <- replicateM(mkBypassWire);
  Vector#(tn_num_slaves, Wire#(Bool))  wr_s_pready   <- replicateM(mkBypassWire);

  let slave_select = fn_addr_map(wr_m_request.paddr);

  for (Integer i = 0; i<v_num_slaves; i = i + 1) begin
    rule rl_select_slave;
      wr_s_request [i] <= wr_m_request;
      wr_s_penable [i] <= wr_m_penable;
      wr_s_psel[i]     <= (slave_select[i] == 1) && wr_m_psel;
      if(slave_select[i] == 1 && wr_m_psel)
        `logLevel( fabric, 0, $format("APB_F: Selecting slave: %2d",i))
    endrule:rl_select_slave

    rule rl_select_response (slave_select[i] == 1);
      wr_m_response <= APB_response {prdata : wr_s_response[i].prdata,
                                    pslverr : wr_s_response[i].pslverr,
                                    puser   : wr_s_response[i].puser };
      wr_m_pready <= wr_s_pready[i];
      if(wr_s_pready[i])
        `logLevel( fabric, 0, $format("APB_F: Collecting from slave: %2d",i))
    endrule:rl_select_response

  end

  function Ifc_apb_master #(wd_addr, wd_data, wd_user) f1 (Integer i);
    return interface Ifc_apb_master

      method m_paddr    =  wr_s_request[i].paddr;
      method m_prot     =  wr_s_request[i].prot;
      method m_penable  =  wr_s_penable[i];
      method m_pwrite   =  wr_s_request[i].pwrite;
      method m_pwdata   =  wr_s_request[i].pwdata;
      method m_pstrb    =  wr_s_request[i].pstrb;
      method m_psel     =  wr_s_psel[i];
      method m_puser    =  wr_s_request[i].puser;
      method Action m_pready (Bool pready,  Bit#(wd_data) prdata,
                              Bool pslverr, Bit#(wd_user) puser ) ;
        wr_s_pready[i]   <= pready;
        wr_s_response[i] <= APB_response{prdata: prdata,
                                     puser : puser,
                                     pslverr : pslverr};
      endmethod
    endinterface;
  endfunction:f1

  interface v_to_slaves = genWith (f1);

  interface frm_master = interface Ifc_apb_slave
    method Action s_paddr( Bit#(wd_addr)           paddr,
                           Bit#(3)                 prot,
                           Bool                    penable,
                           Bool                    pwrite,
                           Bit#(wd_data)           pwdata,
                           Bit#(TDiv#(wd_data,8))  pstrb,
                           Bool                    psel ,
                           Bit#(wd_user)           puser   );
      wr_m_request <= APB_request {paddr  : paddr,       
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
endmodule:mkapb_fabric

endpackage:apb_fabric

