// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala
Email id: neelgala@incoresemi.com
Details:

*/
package latency_test;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import Connectable  :: * ;
import GetPut       :: * ;
import BRAMCore     :: * ;
import StmtFSM      :: * ;
import DReg         :: * ;

import APB_Fabric   :: * ;
import APB_Types    :: * ;
import Semi_FIFOF   :: * ;

`include "Logger.bsv"

`define wd_addr 32
`define wd_data 32
`define wd_user 32
`define nslaves 5

`define bram_index 15

function Bit#(`nslaves) fn_mm (Bit#(32) addr);
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
endfunction: fn_mm

(*synthesize*)
module mkinst_fabric(APB_Fabric_IFC#(`wd_addr, `wd_data, `wd_user,  `nslaves ));
  let ifc();
  mkAPB_Fabric #(fn_mm) _temp(ifc);
  return (ifc);
endmodule:mkinst_fabric

// dummy bram module to connect as a slave on the APB
module mkBRAM_APB #(parameter Integer slave_base)
                   (APB_Slave_IFC #(`wd_addr, `wd_data, `wd_user));

  let ignore_bits = valueOf(TLog#(TDiv#(`wd_data,8)));
  BRAM_PORT_BE#(Bit#(`bram_index), Bit#(`wd_data), TDiv#(`wd_data,8)) dmem <-
      mkBRAMCore1BELoad(valueOf(TExp#(`bram_index)), False, "test.mem", False);

  APB_Slave_Xactor #(`wd_addr, `wd_data, `wd_user) s_xactor <- mkAPB_Slave_Xactor;
  Reg#(Bool) rg_read_cycle <- mkDReg(False);
  Reg#(Bit#(`wd_user)) rg_rd_user <- mkReg(0);
  /*doc:rule: */
  rule rl_read_request (!rg_read_cycle);
    let req <- pop_o( s_xactor.fifo_side.o_request);
    Bit#(`bram_index) index = truncate(req.paddr >> ignore_bits);
    rg_rd_user <= req.puser;
    `logLevel( bram, 1, $format("BRAM: base:%h index:%d Req:",slave_base, index, fshow_APB_Req(req)))
    if ( req.pwrite ) begin // write operation
      dmem.put(req.pstrb, index, req.pwdata);
      APB_Response#(`wd_data, `wd_user) resp = 
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
    APB_Response#(`wd_data, `wd_user) resp = 
          APB_Response{ pslverr: False, prdata: data, puser:rg_rd_user};
    s_xactor.fifo_side.i_response.enq(resp);
    `logLevel( bram, 1, $format("BRAM: Res:",fshow_APB_Resp(resp)))
  endrule
  return s_xactor.apb_side;
endmodule:mkBRAM_APB

// testbench
module mkTb(Empty);
  // instantiate the fabric
  let fabric <- mkinst_fabric;

  // instantiate a master transactor
  APB_Master_Xactor#( `wd_addr, `wd_data, `wd_user) master <- mkAPB_Master_Xactor;

  // instantiate brams as slaves
  Vector#(TSub#(`nslaves,1), APB_Slave_IFC# (`wd_addr, `wd_data, `wd_user)) bram_slaves;
  for (Integer i = 0; i<`nslaves - 1; i = i + 1) begin
    bram_slaves[i] <- mkBRAM_APB(i*'h1000);
  end

  // extra slave to act as error slave
  APB_Slave_IFC #(`wd_addr, `wd_data, `wd_user) err_slave <- mkAPB_Err;

  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);

  // connect master
  mkConnection(fabric.from_master, master.apb_side);

  // connect brams
  for (Integer i = 0; i<`nslaves-1; i = i + 1) begin
    mkConnection(fabric.v_to_slaves[i], bram_slaves[i]);
  end

  // connect error slave
  mkConnection(fabric.v_to_slaves[`nslaves-1], err_slave);
  Reg#(int) iter <- mkRegU;
  Reg#(APB_Request #(`wd_addr, `wd_data, `wd_user)) rg_requests <- mkReg(unpack(0));

  APB_Request #(`wd_addr, `wd_data, `wd_user) req = APB_Request {paddr : 'h1500,
                                                                 prot  : 0,
                                                                 pwrite: False,
                                                                 pwdata: 'hdeadbeef,
                                                                 pstrb : '1,
                                                                 puser : 0 };
  Stmt requests = (
    par
      seq
        action
          let stime <- $stime;
          let request = APB_Request {paddr:'h2500, pwdata: 'hbabe, pwrite: True, pstrb:'1, puser:stime};
          master.fifo_side.i_request.enq(request);
          $display("[%10d]\tSending Write Req",$time);
        endaction
        delay(3);
        action
          let stime <- $stime;
          let request = APB_Request {paddr:'h1500, pwdata: 'hbabe, pwrite: False, pstrb:'1, puser:stime};
          master.fifo_side.i_request.enq(request);
          $display("[%10d]\tSending Read Req",$time);
        endaction
        action
          let stime <- $stime;
          let request = APB_Request {paddr:'h1600, pwdata: 'hbabe, pwrite: False, pstrb:'1, puser:stime};
          master.fifo_side.i_request.enq(request);
          $display("[%10d]\tSending Read Req",$time);
        endaction
        action
          let stime <- $stime;
          let request = APB_Request {paddr:'h1600, pwdata: 'hbabe, pwrite: True, pstrb:'1, puser:stime};
          master.fifo_side.i_request.enq(request);
          $display("[%10d]\tSending Write Req",$time);
        endaction
        delay(100);
        action
          let stime <- $stime;
          let request = APB_Request {paddr:'h1300, pwdata: 'hbabe, pwrite: False, pstrb:'1, puser:stime};
          master.fifo_side.i_request.enq(request);
          $display("[%10d]\tSending Read Req",$time);
        endaction
      endseq
      par
        for(iter <= 1; iter <= 5; iter <= iter + 1)
          action
            await (master.fifo_side.o_response.notEmpty);
            let resp = master.fifo_side.o_response.first;
            master.fifo_side.o_response.deq;
            let stime <- $stime;
            let diff_time = stime - resp.puser;
            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow_APB_Resp(resp));
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

