// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 15 April 2020 05:00:01 PM IST

*/
package axi2apb_bridge;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import axi4         :: * ;
import apb          :: * ;
import axi2apb      :: * ;
`include "Logger.bsv"

// --------- change the following parameters ----------//
`define axi_id    4
`define axi_addr  32
`define axi_data  32
`define apb_addr  24
`define apb_data  16
`define user      0
// ---------------------------------------------------//

(*synthesize*)
module mkaxi2apb_bridge(Ifc_axi2apb#(`axi_id, `axi_addr, `axi_data, `apb_addr, `apb_data, `user));
  let ifc();
  mkaxi2apb _temp(ifc);
  return ifc();
endmodule:mkaxi2apb_bridge

endpackage:axi2apb_bridge
