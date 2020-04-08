// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 08 April 2020 05:00:26 PM IST

*/
package latency_test;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import DefaultValue :: * ;
import BRAMCore     :: * ;
import DReg         :: * ;
import Connectable  :: * ;
import StmtFSM      :: * ;

`include "Logger.bsv"

import APB_Types    :: * ;
import APB_Fabric   :: * ;
import AXI4_Types   :: * ;
import AXI4_Fabric  :: * ;
import Semi_FIFOF   :: * ;
import axi2apb      :: * ;

`define axi_addr 32
`define axi_data 32
`define axi_id   4
`define apb_addr 32
`define apb_data 32
`define user     32
`define nslaves  1
`define bram_index 15

function Bit#(`nslaves) fn_mm (Bit#(32) addr);
  return 'b1;
endfunction: fn_mm
(*synthesize*)
module mkinst_bridge (Axi2Apb_IFC #(`axi_id, `axi_addr, `axi_data, `apb_addr, `apb_data, `user));
  let ifc();
  mkAxi2Apb _temp(ifc);
  return ifc;  
endmodule:mkinst_bridge

(*synthesize*)
module mkinst_apbfabric(APB_Fabric_IFC #(`apb_addr, `apb_data, `user, `nslaves ));
  let ifc();
  mkAPB_Fabric #(fn_mm) _temp(ifc);
  return (ifc);
endmodule:mkinst_apbfabric

// dummy bram module to connect as a slave on the APB
module mkBRAM_APB #(parameter Integer slave_base)
                   (APB_Slave_IFC #(`apb_addr, `apb_data, `user));

  let ignore_bits = valueOf(TLog#(TDiv#(`apb_data,8)));
  BRAM_PORT_BE#(Bit#(`bram_index), Bit#(`apb_data), TDiv#(`apb_data,8)) dmem <-
      mkBRAMCore1BELoad(valueOf(TExp#(`bram_index)), False, "test.mem", False);

  APB_Slave_Xactor_IFC #(`apb_addr, `apb_data, `user) s_xactor <- mkAPB_Slave_Xactor;
  Reg#(Bool) rg_read_cycle <- mkDReg(False);
  Reg#(Bit#(`user)) rg_rd_user <- mkReg(0);
  /*doc:rule: */
  rule rl_read_request (!rg_read_cycle);
    let req <- pop_o( s_xactor.fifo_side.o_request);
    Bit#(`bram_index) index = truncate(req.paddr >> ignore_bits);
    rg_rd_user <= req.puser;
    `logLevel( bram, 1, $format("BRAM: base:%h index:%d Req:",slave_base, index, fshow_APB_Req(req)))
    if ( req.pwrite ) begin // write operation
      dmem.put(req.pstrb, index, req.pwdata);
      APB_Response#(`apb_data, `user) resp = 
          APB_Response{ pslverr: False, prdata: ?, puser:req.puser};
      s_xactor.fifo_side.i_response.enq(resp);
      `logLevel( bram, 1, $format("BRAM: Res:",fshow_APB_Resp(resp)))
    end
    else begin
      dmem.put(0,index, ?);
      rg_read_cycle <= True;
    end
  endrule:rl_read_request

  /*doc:rule: */
  rule rl_read_cycle (rg_read_cycle);
    let data = dmem.read();
    APB_Response#(`apb_data, `user) resp = 
          APB_Response{ pslverr: False, prdata: data, puser:rg_rd_user};
    s_xactor.fifo_side.i_response.enq(resp);
    `logLevel( bram, 1, $format("BRAM: Res:",fshow_APB_Resp(resp)))
  endrule
  return s_xactor.apb_side;
endmodule:mkBRAM_APB

typedef AXI4_Rd_Addr# (`axi_id, `axi_addr, `user) ARReq;

module mkTb(Empty);
  
  let apb_fabric <- mkinst_apbfabric;
  let bram_apb <- mkBRAM_APB('h1000);
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;
  AXI4_Master_Xactor_IFC #(`axi_id, `axi_addr, `axi_data, `user) 
      axi_xactor <- mkAXI4_Master_Xactor(defaultValue);

  mkConnection(axi_xactor.axi_side, apb_fabric.from_master);
  mkConnection(apb_fabric.v_to_slaves[0], bram_apb);
  
  Stmt requests = (
    par
      seq
        action
          let stime <- $stime;
          ARReq request = AXI4_Rd_Addr {araddr:'h1004, arlen:7, arsize:2, arburst:axburst_wrap};
          axi_xactor.fifo_side.i_rd_addr.enq(request);
          $display("[%10d]\tSending Req",$time, fshow_Rd_Addr(request));
        endaction
      endseq
      par
        for(iter <= 1; iter <= 8; iter <= iter + 1)
          action
            await (axi_xactor.fifo_side.o_rd_data.notEmpty);
            let resp = axi_xactor.fifo_side.o_rd_data.first;
            axi_xactor.fifo_side.o_rd_data.deq;
            let stime <- $stime;
            let diff_time = stime - resp.ruser;
            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow_Rd_Data(resp));
          endaction
      endpar
    endpar
  );

  FSM test <- mkFSM(requests);

  /*doc:rule: */
  rule rl_initiate(rg_count == 0);
    rg_count <= rg_count + 1;
    test.start;
  endrule:rl_initiate

  /*doc:rule: */
  rule rl_terminate (rg_count != 0 && test.done);
    $finish(0);
  endrule
  
endmodule:mkTb
  
endpackage:latency_test

