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

import Semi_FIFOF   :: * ;
import axi2apb      :: * ;
import axi4         :: * ;
import apb          :: * ;

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
module mkinst_bridge (Ifc_axi2apb #(`axi_id, `axi_addr, `axi_data, `apb_addr, `apb_data, `user));
  let ifc();
  mkaxi2apb _temp(ifc);
  return ifc;  
endmodule:mkinst_bridge

(*synthesize*)
module mkinst_apbfabric(Ifc_apb_fabric #(`apb_addr, `apb_data, `user, `nslaves ));
  let ifc();
  mkapb_fabric #(fn_mm) _temp(ifc);
  return (ifc);
endmodule:mkinst_apbfabric

// dummy bram module to connect as a slave on the APB
module mkbram_apb #(parameter Integer slave_base)
                   (Ifc_apb_slave #(`apb_addr, `apb_data, `user));

  let ignore_bits = valueOf(TLog#(TDiv#(`apb_data,8)));
  BRAM_PORT_BE#(Bit#(`bram_index), Bit#(`apb_data), TDiv#(`apb_data,8)) dmem <-
      mkBRAMCore1BELoad(valueOf(TExp#(`bram_index)), False, "test.mem", False);

  Ifc_apb_slave_xactor #(`apb_addr, `apb_data, `user) s_xactor <- mkapb_slave_xactor;
  Reg#(Bool) rg_read_cycle <- mkDReg(False);
  Reg#(Bit#(`user)) rg_rd_user <- mkReg(0);
  /*doc:rule: */
  rule rl_read_request (!rg_read_cycle);
    let req <- pop_o( s_xactor.fifo_side.o_request);
    Bit#(`bram_index) index = truncate(req.paddr >> ignore_bits);
    rg_rd_user <= req.puser;
    `logLevel( bram, 1, $format("BRAM: base:%h index:%d Req:",slave_base, index, fshow_apb_req(req)))
    if ( req.pwrite ) begin // write operation
      dmem.put(req.pstrb, index, req.pwdata);
      APB_response#(`apb_data, `user) resp = 
          APB_response{ pslverr: False, prdata: ?, puser:req.puser};
      s_xactor.fifo_side.i_response.enq(resp);
      `logLevel( bram, 1, $format("BRAM: Res:",fshow_apb_resp(resp)))
    end
    else begin
      dmem.put(0,index, ?);
      rg_read_cycle <= True;
    end
  endrule:rl_read_request

  /*doc:rule: */
  rule rl_read_cycle (rg_read_cycle);
    let data = dmem.read();
    APB_response#(`apb_data, `user) resp = 
          APB_response{ pslverr: False, prdata: data, puser:rg_rd_user};
    s_xactor.fifo_side.i_response.enq(resp);
    `logLevel( bram, 1, $format("BRAM: Res:",fshow_apb_resp(resp)))
  endrule
  return s_xactor.apb_side;
endmodule:mkbram_apb

typedef AXI4_rd_addr #(`axi_id, `axi_addr, `user) ARReq;
typedef AXI4_wr_addr #(`axi_id, `axi_addr, `user) AWReq;
typedef AXI4_wr_data #(`axi_data, `user)          AWDReq;

module mkTb(Empty);
  
  let apb_fabric <- mkinst_apbfabric;
  let bram_apb <- mkbram_apb('h1000);
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;
  Reg#(int) iter1 <- mkRegU;
  Reg#(Bit#(`axi_data)) rg_axi_data <- mkReg('haaaaaaaa);
  Ifc_axi4_master_xactor #(`axi_id, `axi_addr, `axi_data, `user) 
      axi_xactor <- mkaxi4_master_xactor(defaultValue);

  mkConnection(axi_xactor.axi_side, apb_fabric.from_master);
  mkConnection(apb_fabric.v_to_slaves[0], bram_apb);
  
  Stmt requests = (
    par
      seq
        action
          let stime <- $stime;
          ARReq request = AXI4_rd_addr {araddr:'h1000, arlen:7, arsize:2, arburst:axburst_incr};
          axi_xactor.fifo_side.i_rd_addr.enq(request);
          $display("[%10d]\tSending Rd Req",$time, fshow_axi4_rd_addr(request));
        endaction
        action
          let stime <- $stime;
          AWReq request = AXI4_wr_addr {awaddr:'h1000, awlen:7, awsize:2, awburst:axburst_incr};
          axi_xactor.fifo_side.i_wr_addr.enq(request);
          $display("[%10d]\tSending Wr Req",$time, fshow_axi4_wr_addr(request));
        endaction
        for(iter1 <= 1; iter1 <= 8; iter1 <= iter1 + 1)
          action
            AWDReq req = AXI4_wr_data{wdata:rg_axi_data, wstrb:'1, wlast: iter1 == 8};
            axi_xactor.fifo_side.i_wr_data.enq(req);
            $display("[%10d]\tSending WrD Req",$time, fshow_axi4_wr_data(req));
            rg_axi_data <= rg_axi_data + 'h11111111;
          endaction
      endseq
      seq
        for(iter <= 1; iter <= 8; iter <= iter + 1)
          action
            await (axi_xactor.fifo_side.o_rd_data.notEmpty);
            let resp = axi_xactor.fifo_side.o_rd_data.first;
            axi_xactor.fifo_side.o_rd_data.deq;
            let stime <- $stime;
            let diff_time = stime - resp.ruser;
            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow(resp));
          endaction
        for(iter <= 1; iter <= 1; iter <= iter + 1)
          action
            await (axi_xactor.fifo_side.o_wr_resp.notEmpty);
            let resp = axi_xactor.fifo_side.o_wr_resp.first;
            axi_xactor.fifo_side.o_wr_resp.deq;
            let stime <- $stime;
            let diff_time = stime - resp.buser;
            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow(resp));
          endaction
      endseq
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

