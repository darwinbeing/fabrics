// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: 

*/
package apb_xactors;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import Connectable  :: * ;

import apb          :: * ;

import Semi_FIFOF   :: * ;

`include "Logger.bsv"

`define wd_addr            32
`define wd_data            512
`define wd_user            0
`define tn_num_slaves      7
`define tn_num_slaves_bits TLog#(`tn_num_slaves)

function Bit#(TMax#(`tn_num_slaves_bits,1)) fn_addr_map(Bit#(`wd_addr) wd_addr);
  if (wd_addr >= 'h2000 && wd_addr < 'h3000) return 0;
  else if (wd_addr >= 'h4000 && wd_addr < 'h5000) return 2;
  else if (wd_addr >= 'h5000 && wd_addr < 'h6000) return 3;
  else if (wd_addr >= 'h5000 && wd_addr < 'h6000) return 4;
  else if (wd_addr >= 'h5000 && wd_addr < 'h6000) return 6;
  else return 5;
endfunction:fn_addr_map


module mkapb_interconnect(Ifc_apb_fabric#(`wd_addr, `wd_data, `wd_user,  `tn_num_slaves ));
  let ifc();
  mkapb_fabric #(fn_addr_map) _temp(ifc);
  return (ifc);
endmodule:mkapb_interconnect

(*synthesize*)
module mkapb_masterxactor(Ifc_apb_master_xactor #(`wd_addr, `wd_data, `wd_user));
  let ifc();
  mkapb_master_xactor _temp(ifc);
  return ifc;
endmodule:mkapb_masterxactor

(*synthesize*)
module mkapb_slavexactor(Ifc_apb_slave_xactor #(`wd_addr, `wd_data, `wd_user));
  let ifc();
  mkapb_slave_xactor _temp(ifc);
  return ifc;
endmodule:mkapb_slavexactor


interface Ifc_withXactors;
  interface Ifc_apb_server #(`wd_addr, `wd_data, `wd_user) m_fifo;
  interface Vector#(`tn_num_slaves,  Ifc_apb_client #(`wd_addr, `wd_data, `wd_user)) s_fifo;
endinterface:Ifc_withXactors

(*synthesize*)
module mkapb_xactorinterconnect (Ifc_withXactors);

  Ifc_apb_master_xactor #(`wd_addr, `wd_data, `wd_user) m_xactor <- mkapb_master_xactor;

  Vector #(`tn_num_slaves, Ifc_apb_slave_xactor#(`wd_addr, `wd_data, `wd_user))
      s_xactors <- replicateM(mkapb_slave_xactor);

  let fabric <- mkapb_interconnect;

  mkConnection(fabric.frm_master,m_xactor.apb_side);
  for (Integer i = 0; i<`tn_num_slaves; i = i + 1) begin
    mkConnection(fabric.v_to_slaves[i],s_xactors[i].apb_side);
  end

  function Ifc_apb_client#(`wd_addr, `wd_data, `wd_user) f2 (Integer j)
    = s_xactors[j].fifo_side;

  interface m_fifo = m_xactor.fifo_side;
  interface s_fifo = genWith(f2);
endmodule:mkapb_xactorinterconnect

endpackage:apb_xactors



