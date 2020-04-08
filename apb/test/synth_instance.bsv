// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: 

*/
package synth_instance;
import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import Connectable  :: * ;

import APB_Fabric   :: * ;
import APB_Types    :: * ;
import Semi_FIFOF   :: * ;

`include "Logger.bsv"

`define wd_addr 32
`define wd_data 32
`define wd_user 32
(*synthesize*)
module mkinst_onlyfabric(APB_Fabric_IFC#(`wd_addr, `wd_data, `wd_user,  `nslaves ));
  let ifc();
  mkAPB_Fabric #(fn_mm) _temp(ifc);
  return (ifc);
endmodule:mkinst_onlyfabric


function Bit#(`nslaves) fn_mm (Bit#(32) addr);
  if (addr < 'h1000 )
    return truncate(5'b00001);
  else if (addr >= 'h1000 && addr < 'h2000)
    return truncate(5'b00010);
  else if (addr >= 'h2000 && addr < 'h3000)
    return truncate(5'b00100);
  else if (addr >= 'h3000 && addr < 'h4000)
    return truncate(5'b01000);
  else
    return truncate(5'b10000);
endfunction: fn_mm

interface Ifc_withXactors;
  interface APB_Server_IFC #(`wd_addr, `wd_data, `wd_user) m_fifo;
  interface Vector#(`nslaves,  APB_Client_IFC #(`wd_addr, `wd_data, `wd_user)) s_fifo;
endinterface:Ifc_withXactors

  (*synthesize*)
  module mkinst_withxactors (Ifc_withXactors);

    APB_Master_Xactor_IFC #(`wd_addr, `wd_data, `wd_user) m_xactor <- mkAPB_Master_Xactor;

    Vector #(`nslaves, APB_Slave_Xactor_IFC#(`wd_addr, `wd_data, `wd_user))
        s_xactors <- replicateM(mkAPB_Slave_Xactor);

    let fabric <- mkinst_onlyfabric;

    mkConnection(fabric.from_master,m_xactor.apb_side);
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_xactors[i].apb_side);
    end

    function APB_Client_IFC#(`wd_addr, `wd_data, `wd_user) f2 (Integer j)
      = s_xactors[j].fifo_side;

    interface m_fifo = m_xactor.fifo_side;
    interface s_fifo = genWith(f2);
  endmodule:mkinst_withxactors
endpackage:synth_instance

