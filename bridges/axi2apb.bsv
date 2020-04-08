// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 08 April 2020 02:24:19 PM IST

*/
package axi2apb ;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import DefaultValue :: * ;
import ConfigReg    :: * ;


import AXI4_Types   :: * ;
import APB_Types    :: * ;
import Semi_FIFOF   :: * ;
`include "Logger.bsv"

typedef enum {Idle, ReadResp, WriteResp} Axi2ApbBridgeState deriving (Bits, FShow, Eq);

interface Axi2Apb_IFC #(  numeric type axi_id, 
                          numeric type axi_addr,
                          numeric type axi_data,
                          numeric type apb_addr,
                          numeric type apb_data,
                          numeric type user );
  (*prefix=""*)
  interface AXI4_Slave_IFC #(axi_id, axi_addr, axi_data, user) axi_side;
  (*prefix=""*)
  interface APB_Master_IFC #(apb_addr, apb_data, user)         apb_side;
endinterface:Axi2Apb_IFC


(*preempts="rl_read_frm_axi, rl_write_frm_axi"*)
module mkAxi2Apb(Axi2Apb_IFC#(axi_id, axi_addr, axi_data, apb_addr, apb_data, user))
  provisos (Add#(apb_addr, _a, axi_addr), // AXI address cannot be smaller in size than APB
            Add#(apb_data,  0, axi_data)  // both data buses have to be the same
           );

  // -------------------------------------------------------------------------------------------- //
  // instantiate the transactors

  APB_Master_Xactor_IFC#( apb_addr, apb_data, user)         apb_xactor <- mkAPB_Master_Xactor;
  AXI4_Slave_Xactor_IFC#( axi_id, axi_addr, axi_data, user) axi_xactor <- mkAXI4_Slave_Xactor(defaultValue);
  // -------------------------------------------------------------------------------------------- //

  /*doc:reg: dictates the state that the bridge is currently in */
  ConfigReg#(Axi2ApbBridgeState)                        rg_state       <- mkConfigReg(Idle);
  /*doc:reg: captures the initial read request from the axi read-channel*/
  Reg#(AXI4_Rd_Addr #(axi_id, axi_addr, user))          rg_rd_request  <- mkReg(unpack(0));
  /*doc:reg: this register holds the count of the read requests to be sent to the APB*/
  Reg#(Bit#(8))                                         rg_rdreq_burst <- mkReg(0);
  /*doc:reg: this register increments everytime a read-response from the APB is received.*/
  Reg#(Bit#(8))                                         rg_rdres_burst <- mkReg(0);

  /*doc:reg: captures the initial read request from the axi write address-channel*/
  Reg#(AXI4_Wr_Addr #(axi_id, axi_addr, user))          rg_wr_request  <- mkReg(unpack(0));
  /*doc:reg: captures the initial read request from the axi write data*/
  Reg#(AXI4_Wr_Data #(axi_data, user))                  rg_wd_request  <- mkReg(unpack(0));
  /*doc:reg: this register holds the count of the write requests to be sent to the APB*/
  Reg#(Bit#(8))                                         rg_wrreq_burst <- mkReg(0);
  /*doc:reg: this register increments everytime a write-response from the APB is received.*/
  Reg#(Bit#(8))                                         rg_wrres_burst <- mkReg(0);

  /*doc:rule: */
  rule rl_display_state;
    `logLevel( bridge, 0, $format("Axi2Apb: State:",fshow(rg_state)))
  endrule:rl_display_state

  /*doc:rule: this rule pops the read request from axi and initiates a request on the APB*/
  rule rl_read_frm_axi (rg_state == Idle);
    let axi_req <- pop_o(axi_xactor.fifo_side.o_rd_addr);
    APB_Request #(apb_addr, apb_data, user) apb_request = APB_Request {
                                                                    paddr : truncate(axi_req.araddr),
                                                                    prot  : axi_req.arprot,
                                                                    pwrite: False,
                                                                    pwdata: ?,
                                                                    pstrb : 0,
                                                                    puser : axi_req.aruser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    rg_rdreq_burst   <= axi_req.arlen;
    rg_rdres_burst   <= 0;
    rg_rd_request    <= axi_req;
    rg_state         <= ReadResp;
    `logLevel( bridge, 0, $format("Axi2Apb: AXI4-Read:",fshow_Rd_Addr(axi_req)))
    `logLevel( bridge, 0, $format("Axi2Apb: APB-Req  :",fshow_APB_Req(apb_request)))
  endrule:rl_read_frm_axi
  
  /*doc:rule: this rule will generate new addresses based on burst-mode and lenght and send read 
  requests to the APB*/
  rule rl_send_rd_burst_req(rg_state == ReadResp && rg_rdreq_burst !=0);
    rg_rdreq_burst <= rg_rdreq_burst - 1;
    let new_address = fn_axi4burst_addr(rg_rd_request.arlen, 
                                        rg_rd_request.arsize, 
                                        rg_rd_request.arburst,
                                        rg_rd_request.araddr);
    APB_Request #(apb_addr, apb_data, user) apb_request = APB_Request {
                                                                    paddr : truncate(new_address),
                                                                    prot  : rg_rd_request.arprot,
                                                                    pwrite: False,
                                                                    pwdata: ?,
                                                                    pstrb : 0,
                                                                    puser : rg_rd_request.aruser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    let next_req = rg_rd_request;
    next_req.araddr = new_address;
    rg_rd_request <= next_req;
    `logLevel( bridge, 0, $format("Axi2Apb: AXI4-RdBurst Addr:%h Count:%d",new_address,
        rg_rdreq_burst))
    `logLevel( bridge, 0, $format("Axi2Apb: New APB-Req  :",fshow_APB_Req(apb_request)))
  endrule:rl_send_rd_burst_req

  /*doc:rule: collects read responses from APB and send to AXI*/
  rule rl_read_response_to_axi(rg_state == ReadResp);
    
    let apb_response <- pop_o(apb_xactor.fifo_side.o_response);
    let axi_response = AXI4_Rd_Data {rid: rg_rd_request.arid,
                                     rdata: apb_response.prdata,
                                     rresp: apb_response.pslverr?axi4_resp_slverr:axi4_resp_okay,
                                     ruser: apb_response.puser,
                                     rlast: rg_rdres_burst == rg_rd_request.arlen};
    axi_xactor.fifo_side.i_rd_data.enq(axi_response);
    if(rg_rdres_burst == rg_rd_request.arlen) begin
      rg_state <= Idle;
      rg_rdres_burst <= 0;
    end
    else
      rg_rdres_burst <= rg_rdres_burst + 1;
    `logLevel( bridge, 0, $format("Axi2Apb: APB-Resp: Count:%2d",rg_rdres_burst, fshow_APB_Resp(apb_response)))
    `logLevel( bridge, 0, $format("Axi2Apb: AXI-RdResp:",fshow_Rd_Data(axi_response)))
  endrule:rl_read_response_to_axi
  
  /*doc:rule: this rule pops the read request from axi and initiates a request on the APB*/
  rule rl_write_frm_axi (rg_state == Idle);
    let axi_req  <- pop_o(axi_xactor.fifo_side.o_wr_addr);
    let axi_wreq <- pop_o(axi_xactor.fifo_side.o_wr_data);
    APB_Request #(apb_addr, apb_data, user) apb_request = APB_Request {
                                                                    paddr : truncate(axi_req.awaddr),
                                                                    prot  : axi_req.awprot,
                                                                    pwrite: True,
                                                                    pwdata: axi_wreq.wdata,
                                                                    pstrb : axi_wreq.wstrb,
                                                                    puser : axi_req.awuser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    rg_wrreq_burst   <= axi_req.awlen;
    rg_wrres_burst   <= 0;
    rg_wr_request    <= axi_req;
    rg_wd_request    <= axi_wreq;
    rg_state         <= WriteResp;
  endrule:rl_write_frm_axi
  
  /*doc:rule: this rule will generate new addresses based on burst-mode and lenght and send write
  requests to the APB*/
  rule rl_send_wr_burst_req(rg_state == WriteResp && rg_wrreq_burst !=0);
    rg_wrreq_burst <= rg_wrreq_burst - 1;
    let axi_wreq <- pop_o(axi_xactor.fifo_side.o_wr_data);
    let new_address = fn_axi4burst_addr(rg_wr_request.awlen, 
                                        rg_wr_request.awsize, 
                                        rg_wr_request.awburst,
                                        rg_wr_request.awaddr);
    APB_Request #(apb_addr, apb_data, user) apb_request = APB_Request {
                                                                    paddr : truncate(new_address),
                                                                    prot  : rg_wr_request.awprot,
                                                                    pwrite: True,
                                                                    pwdata: axi_wreq.wdata,
                                                                    pstrb : axi_wreq.wstrb,
                                                                    puser : rg_wr_request.awuser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    let next_req = rg_rd_request;
    next_req.araddr = new_address;
    rg_rd_request <= next_req;
  endrule:rl_send_wr_burst_req

  /*doc:rule: collects read responses from APB and send to AXI*/
  rule rl_write_response_to_axi(rg_state == WriteResp);
    
    let apb_response <- pop_o(apb_xactor.fifo_side.o_response);
    let axi_response = AXI4_Wr_Resp {bid: rg_wr_request.awid,
                                     bresp: apb_response.pslverr?axi4_resp_slverr:axi4_resp_okay,
                                     buser: apb_response.puser};
    axi_xactor.fifo_side.i_wr_resp.enq(axi_response);
    if(rg_wrres_burst == rg_wr_request.awlen) begin
      rg_state <= Idle;
      rg_wrres_burst <= 0;
    end
    else
      rg_wrres_burst <= rg_wrres_burst + 1;
  endrule:rl_write_response_to_axi

  interface axi_side = axi_xactor.axi_side;
  interface apb_side = apb_xactor.apb_side;

endmodule:mkAxi2Apb

(*synthesize*)
module mkinst_bridge(Axi2Apb_IFC#(4,32,32,32,32,0));
  let ifc();
  mkAxi2Apb _temp(ifc);
  return ifc;
endmodule

endpackage: axi2apb

