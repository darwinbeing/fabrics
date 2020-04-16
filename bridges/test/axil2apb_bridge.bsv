// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 15 April 2020 05:00:01 PM IST

*/
package axil2apb_bridge;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import axi4l        :: * ;
import apb          :: * ;
import axil2apb      :: * ;
`include "Logger.bsv"

// --------- change the following parameters ----------//
`define axil_addr  32
`define axil_data  32
`define apb_addr  24
`define apb_data  16
`define user      0
// ---------------------------------------------------//

(*synthesize*)
module mkaxil2apb_bridge(Ifc_axil2apb#(`axil_addr, `axil_data, `apb_addr, `apb_data, `user));
  let ifc();
  mkaxil2apb _temp(ifc);
  return ifc();
endmodule:mkaxil2apb_bridge

endpackage:axil2apb_bridge
