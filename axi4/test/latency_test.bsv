/* 
Copyright (c) 2018, IIT Madras All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions
  and the following disclaimer.  
* Redistributions in binary form must reproduce the above copyright notice, this list of 
  conditions and the following disclaimer in the documentation and/or other materials provided 
  with the distribution.  
* Neither the name of IIT Madras  nor the names of its contributors may be used to endorse or 
  promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT 
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--------------------------------------------------------------------------------------------------

Author: <author-name>
Email id: <author-email>
Details:

--------------------------------------------------------------------------------------------------
*/
package latency_test;
  import FIFOF        :: * ;
  import SpecialFIFOs :: * ;
  import FIFO         :: * ;
  import Vector       :: * ;
  import DefaultValue :: * ;
  import Connectable  :: * ;
  import AXI4_Fabric  :: * ;
  import AXI4_Types   :: * ;
  import Semi_FIFOF   :: * ;
  `include "Logger.bsv"

  `define wd_id 4
  `define wd_addr 32
  `define wd_data 64
  `define wd_user 32
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
  endinterface

  (*synthesize*)                            
  module mkinst_onlyfabric (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkAXI4_Fabric (fn_mm, replicate('1), replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric

  (*synthesize*)                            
  module mkinst_onlyfabric_2 (Fabric_AXI4_IFC);
    Fabric_AXI4_IFC fabric <- mkAXI4_Fabric_2 (fn_mm, replicate('1), replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric_2

  (*synthesize*)
  module mkinst_withxactors (Ifc_withXactors);

    Vector #(`nmasters, AXI4_Master_Xactor_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkAXI4_Master_Xactor(defaultValue));

    Vector #(`nslaves, AXI4_Slave_IFC#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_err <- replicateM(mkAXI4_Err);

    let fabric <- mkinst_onlyfabric; 

    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_err[i]);
    end

    function AXI4_Server_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
  endmodule:mkinst_withxactors

  (*synthesize*)
  module mkinst_withxactors_2 (Ifc_withXactors);

    Vector #(`nmasters, AXI4_Master_Xactor_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkAXI4_Master_Xactor_2);

    Vector #(`nslaves, AXI4_Slave_IFC#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_err <- replicateM(mkAXI4_Err_2);

    let fabric <- mkinst_onlyfabric_2; 

    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_err[i]);
    end

    function AXI4_Server_IFC #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
  endmodule:mkinst_withxactors_2


  /*doc:module: */
  module mkTb (Empty);
    let inst1 <- mkinst_withxactors;
    let inst2 <- mkinst_withxactors_2;
    /*doc:reg: */
    Reg#(Bit#(32)) rg_count <- mkReg(0);
    /*doc:rule: */
    rule rl_send_v1_read (rg_count == 0);
      let stime <- $stime;
      AXI4_Rd_Addr #(`wd_id, `wd_addr, `wd_user) _req = AXI4_Rd_Addr { arid:0,
                                                                      araddr:'h1000,
                                                                      arlen:0,
                                                                      arsize:0,
                                                                      arburst:0,
                                                                      arlock:0,
                                                                      arcache:0,
                                                                      arprot:0,
                                                                      arqos:0,
                                                                      arregion:0,
                                                                      aruser: stime };
     `logLevel( tb, 1, $format("Sending request: ", fshow_Rd_Addr(_req)))
      inst1.m_fifo[0].i_rd_addr.enq(_req);
      rg_count <= rg_count + 1;
    endrule
    /*doc:rule: */
    rule rl_get_v1_read (rg_count == 1);
      let _resp <- pop_o(inst1.m_fifo[0].o_rd_data);
      `logLevel( tb, 1, $format("Received Response: ",fshow_Rd_Data(_resp)))
      let stime <- $stime;
      let diff_time = stime - _resp.ruser;
      `logLevel( tb, 0, $format("Total cycles for V1 a single read op: %5d",diff_time/10))
      rg_count <= rg_count + 1;
    endrule
    rule rl_send_v1_write (rg_count == 2);
      let stime <- $stime;
      AXI4_Wr_Addr #(`wd_id, `wd_addr, `wd_user) _req = AXI4_Wr_Addr { awid:0,
                                                                       awaddr:'h2000,
                                                                       awlen:0,
                                                                       awsize:0,
                                                                       awburst:0,
                                                                       awlock:0,
                                                                       awcache:0,
                                                                       awprot:0,
                                                                       awqos:0,
                                                                       awregion:0,
                                                                       awuser:stime};
      AXI4_Wr_Data #(`wd_data, `wd_user) _w_req = AXI4_Wr_Data {wdata:'hdeadbeef,
                                                                wstrb:'1,
                                                                wlast:True,
                                                                wuser:stime};
     `logLevel( tb, 1, $format("Sending request: ", fshow_Wr_Addr(_req)))
      inst1.m_fifo[0].i_wr_addr.enq(_req);
      inst1.m_fifo[0].i_wr_data.enq(_w_req);
      rg_count <= rg_count + 1;
    endrule
    /*doc:rule: */
    rule rl_get_v1_write (rg_count == 3);
      let _resp <- pop_o(inst1.m_fifo[0].o_wr_resp);
      `logLevel( tb, 1, $format("Received Response: ",fshow_Wr_Resp(_resp)))
      let stime <- $stime;
      let diff_time = stime - _resp.buser;
      `logLevel( tb, 0, $format("Total cycles for V1 a single write op: %5d",diff_time/10))
      rg_count <= rg_count + 1;
    endrule
    rule rl_second_transaction (rg_count == 4);
      let stime <- $stime;
      AXI4_Rd_Addr #(`wd_id, `wd_addr, `wd_user) _req = AXI4_Rd_Addr { arid:0,
                                                                      araddr:'h1000,
                                                                      arlen:0,
                                                                      arsize:0,
                                                                      arburst:0,
                                                                      arlock:0,
                                                                      arcache:0,
                                                                      arprot:0,
                                                                      arqos:0,
                                                                      arregion:0,
                                                                      aruser: stime };
     `logLevel( tb, 1, $format("Sending request: ", fshow_Rd_Addr(_req)))
      inst2.m_fifo[0].i_rd_addr.enq(_req);
      rg_count <= rg_count + 1;
    endrule
    /*doc:rule: */
    rule rl_end_second (rg_count == 5);
      let _resp <- pop_o(inst2.m_fifo[0].o_rd_data);
      `logLevel( tb, 1, $format("Received Response: ",fshow_Rd_Data(_resp)))
      let stime <- $stime;
      let diff_time = stime - _resp.ruser;
      `logLevel( tb, 0, $format("Total cycles for V2 a single read op: %5d",diff_time/10))
      $finish(0);
      rg_count <= rg_count + 1;
    endrule
  endmodule:mkTb
endpackage

