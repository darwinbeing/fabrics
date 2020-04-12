// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 08 April 2020 05:00:26 PM IST

*/
package latency_test_axi2axil;

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
import axi2axil      :: * ;
import axi4         :: * ;
import axi4l          :: * ;

`define axi_addr 32
`define axi_data 32
`define axi_id   4
`define axil_addr 32
`define axil_data 16
`define user     32
`define nslaves  1
`define bram_index 16

(*synthesize*)
module mkinst_bridge (Ifc_axi2axil #(`axi_id, `axi_addr, `axi_data, `axil_addr, `axil_data, `user));
  let ifc();
  mkaxi2axil _temp(ifc);
  return ifc;  
endmodule:mkinst_bridge

(*synthesize*)
module mkinst_axilfabric(Ifc_axi4l_fabric #(1, `nslaves, `axil_addr, `axil_data, `user));
  let ifc();
  mkaxi4l_fabric #(fn_mm, unpack('1), unpack('1)) _temp(ifc);
  return (ifc);
endmodule:mkinst_axilfabric

interface Ifc_bram_axi4lite#(numeric type addr_width, 
                              numeric type data_width, 
                              numeric type user_width,
                              numeric type index_size);
  interface Ifc_axi4l_slave#(addr_width, data_width, user_width) slave;
endinterface

interface UserInterface#(numeric type addr_width,  numeric type data_width, numeric type index_size);
  method Action read_request (Bit#(addr_width) addr);
  method Action write_request (Tuple3#(Bit#(addr_width), Bit#(data_width),
                                                                Bit#(TDiv#(data_width, 8))) req);
  method ActionValue#(Tuple2#(Bool, Bit#(data_width))) read_response;
  method ActionValue#(Bool) write_response;
endinterface

// to make is synthesizable replace addr_width with Physical Address width
// data_width with data lane width
module mkbram#(parameter Integer slave_base, parameter String readfile,
                                              parameter String modulename )
    (UserInterface#(addr_width, data_width, index_size))
    provisos(
      Mul#(TDiv#(data_width, TDiv#(data_width, 8)), TDiv#(data_width, 8),data_width)  );

  Integer byte_offset = valueOf(TLog#(TDiv#(data_width, 8)));
	// we create 2 32-bit BRAMs since the xilinx tool is easily able to map them to BRAM32BE cells
	// which makes it easy to use data2mem for updating the bit file.

  BRAM_DUAL_PORT_BE#(Bit#(TSub#(index_size, TLog#(TDiv#(data_width, 8)))), Bit#(data_width),
                                                                  TDiv#(data_width,8)) dmemMSB <-
        mkBRAMCore2BELoad(valueOf(TExp#(TSub#(index_size, TLog#(TDiv#(data_width, 8))))), False,
                          readfile, False);

  Reg#(Bool) read_request_sent[2] <-mkCReg(2,False);

  // A write request to memory. Single cycle operation.
  // This model assumes that the master sends the data strb aligned for the data_width bytes.
  // Eg. : is size is HWord at address 0x2 then the wstrb for 64-bit data_width is: 'b00001100
  // And the data on the write channel is assumed to be duplicated.
  method Action write_request (Tuple3#(Bit#(addr_width), Bit#(data_width),
                                                                Bit#(TDiv#(data_width, 8))) req);
    let {addr, data, strb}=req;
		Bit#(TSub#(index_size,TLog#(TDiv#(data_width, 8)))) index_address=
		                          (addr - fromInteger(slave_base))[valueOf(index_size)-1:byte_offset];
		dmemMSB.b.put(strb,index_address,truncateLSB(data));
    `logLevel( bram, 0, $format("",modulename,": Recieved Write Request for Address: %h Index: %h\
 Data: %h wrstrb: %h", addr, index_address, data, strb))
	endmethod

  // The write response will always be an error.
  method ActionValue#(Bool) write_response;
    return False;
  endmethod

  // capture a read_request and latch the address on a BRAM.
  method Action read_request (Bit#(addr_width) addr);
		Bit#(TSub#(index_size,TLog#(TDiv#(data_width, 8)))) index_address=
		                          (addr - fromInteger(slave_base))[valueOf(index_size)-1:byte_offset];
    dmemMSB.a.put(0, index_address, ?);
    read_request_sent[1]<= True;
    `logLevel( bram, 0, $format("",modulename,": Recieved Read Request for Address: %h Index: %h",
                                                                          addr, index_address))
	endmethod

  // respond with data from the BRAM.
  method ActionValue#(Tuple2#(Bool, Bit#(data_width))) read_response if(read_request_sent[0]);
    read_request_sent[0]<=False;
    return tuple2(False, dmemMSB.a.read());
  endmethod
endmodule

module mkbram_axi4lite#(parameter Integer slave_base, parameter String readfile,
       parameter String modulename )
      (Ifc_bram_axi4lite#(addr_width, data_width, user_width, index_size))
    provisos(
      Mul#(TDiv#(data_width, TDiv#(data_width, 8)), TDiv#(data_width, 8),data_width)  );
  UserInterface#(addr_width, data_width, index_size) dut <- mkbram(slave_base, readfile,
                                                                                      modulename);
  Ifc_axi4l_slave_xactor #(addr_width, data_width, user_width)  s_xactor <- 
                                                        mkaxi4l_slave_xactor(defaultValue);
  Integer byte_offset = valueOf(TDiv#(data_width, 32));
  Reg#(Bit#(TAdd#(1, TDiv#(data_width, 32)))) rg_offset <-mkReg(0);
  // If the request is single then simple send ERR. If it is a burst write request then change
  // state to Burst and do not send response.
  rule write_request_address_channel;
    let aw <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let w  <- pop_o (s_xactor.fifo_side.o_wr_data);
    let b = Axi4l_wr_resp {bresp: axi4l_resp_okay, buser: aw.awuser};
    dut.write_request(tuple3(aw.awaddr, w.wdata, w.wstrb));
  	s_xactor.fifo_side.i_wr_resp.enq (b);
  endrule
  // read first request and send it to the dut. If it is a burst request then change state to
  // Burst. capture the request type and keep track of counter.
  rule read_request_first;
	  let ar<- pop_o(s_xactor.fifo_side.o_rd_addr);
    dut.read_request(ar.araddr);
    rg_offset<= ar.araddr[byte_offset:0];
  endrule
  // get data from the memory. shift,  truncate, duplicate based on the size and offset.
  rule read_response;
    let {err, data0}<-dut.read_response;
    Axi4l_rd_data#(data_width, user_width) r = Axi4l_rd_data {rresp: axi4l_resp_okay, rdata: data0 ,
      ruser: 0};
    `logLevel( bram, 1, $format("",modulename,": Responding Read Request with Data: %h ",data0))
    s_xactor.fifo_side.i_rd_data.enq(r);
  endrule
  interface slave = s_xactor.axil_side;
endmodule

typedef AXI4_rd_addr #(`axi_id, `axi_addr, `user) ARReq;
typedef AXI4_wr_addr #(`axi_id, `axi_addr, `user) AWReq;
typedef AXI4_wr_data #(`axi_data, `user)          AWDReq;

function Bit#(TMax#(TLog#(`nslaves),1)) fn_mm (Bit#(32) addr);
  return 0;
endfunction: fn_mm

module mkTb(Empty);
  
  let axil_fabric <- mkinst_axilfabric;
  Ifc_bram_axi4lite#(`axil_addr, `axil_data, `user, `bram_index) bram_axil 
                                        <- mkbram_axi4lite('h1000, "test.mem","BRAM");
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;
  Reg#(int) iter1 <- mkRegU;
  Reg#(Bit#(`axi_data)) rg_axi_data <- mkReg('haaaaaaaa);
  Ifc_axi4_master_xactor #(`axi_id, `axi_addr, `axi_data, `user) 
      axi_xactor <- mkaxi4_master_xactor(defaultValue);

  mkConnection(axi_xactor.axi_side, axil_fabric.v_from_masters[0]);
  mkConnection(axil_fabric.v_to_slaves[0], bram_axil.slave);
  
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
  
endpackage:latency_test_axi2axil

