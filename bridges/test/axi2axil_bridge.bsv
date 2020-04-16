// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 15 April 2020 05:00:01 PM IST

*/
package axi2axil_bridge;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import axi4         :: * ;
import axi4l        :: * ;
import axi2axil     :: * ;
`include "Logger.bsv"

// --------- change the following parameters ----------//
`define axi_id     4
`define axi_addr   32
`define axi_data   32
`define axil_addr  24
`define axil_data  16
`define user       0
// ---------------------------------------------------//

(*synthesize*)
module mkaxi2axil_bridge(Ifc_axi2axil#(`axi_id, `axi_addr, `axi_data, `axil_addr, `axil_data, `user));
  let ifc();
  mkaxi2axil _temp(ifc);
  return ifc();
endmodule:mkaxi2axil_bridge

endpackage:axi2axil_bridge
