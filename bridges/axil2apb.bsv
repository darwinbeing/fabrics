// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 08 April 2020 02:24:19 PM IST
*/
/*doc:overview:

This module implements a bridge/adapter which can be used to convert AXI4-Lite transactions into APB 
(a.k.a APB4, a.k.a APBv2.0) transactions. This bridges acts as a slave on the AXI4-Lite
interface and as a master on an ABP interface. Both the protocols are little endian.
The bridge is parameterized to handle different address and data sizes of either
side with the following contraints:

1. The AXI4-Lite address size must be greater than or equal to the APB address size.
2. The AXI4-Lite data size must be greater than of equal to the APB data size.
3. The AXI4-Lite data and APB data should both be byte-multiples

The bridge also supports spliting of read/write bursts from the AXI4-Lite side to individual requests on
the APB cluster.

A Connectable instance is also provided which can directly connect an AXI4-Lite master interface to a
APB-slave interface.


Working Principle
-----------------

Since the APB is a single channel bus and the AXI4-Lite has separate read and write channels, the read
requests from the AXI4-Lite are given priority over the write requests occurring in the same cycle. At
any point of time only a single requests (burst read or burst write) are served, and the next
request is picked up only when the APB has responded to all the bursts from the previous requests.

Differing Address sizes
^^^^^^^^^^^^^^^^^^^^^^^

When the AXI4-Lite and APB address sizes are different, then the lower bits of the AXI4-Lite addresses are
used on the APB side. 

Differing Data sizes
^^^^^^^^^^^^^^^^^^^^

When the AXI4-Lite and APB data sizes are different, each transaction of the AXI4-Lite request (read or write)
is split into multiple smaller child bursts (sent as individual APB requests) which matches 
APB data size. A transaction is complete only when its corresponding child-bursts are over. 
When instantiated with same data-sizes, the child-burst logic is ommitted.

Error mapping
^^^^^^^^^^^^^

The APB PSLVERR is mapped to the AXI4-Lite SLVERR.

.. note::
  Currently the bridge works for the same clock on either side. Multiple clock domain support will
  available in future versions

*/
package axil2apb ;

import FIFOF        :: * ;
import Vector       :: * ;
import SpecialFIFOs :: * ;
import FIFOF        :: * ;
import DefaultValue :: * ;
import ConfigReg    :: * ;
import Connectable  :: * ;
import BUtils       :: * ;
import Assert       :: * ;
import Memory       :: * ;

import axi4l         :: * ;
import apb          :: * ;

import Semi_FIFOF   :: * ;
`include "Logger.bsv"

typedef enum {Idle, ReadResp, WriteResp} Axil2ApbBridgeState deriving (Bits, FShow, Eq);

interface Ifc_axil2apb #( numeric type axil_addr,
                          numeric type axil_data,
                          numeric type apb_addr,
                          numeric type apb_data,
                          numeric type user );
  (*prefix="AXI4L"*)
  interface Ifc_axi4l_slave #(axil_addr, axil_data, user) axil_side;
  (*prefix="APB"*)
  interface Ifc_apb_master #(apb_addr, apb_data, user)         apb_side;
endinterface:Ifc_axil2apb

(*preempts="rl_read_frm_axi, rl_write_frm_axi"*)
module mkaxil2apb(Ifc_axil2apb#(axil_addr, axil_data, apb_addr, apb_data, user))
  provisos (Add#(apb_addr, _a, axil_addr), // AXI address cannot be smaller in size than APB
            Add#(apb_data, _b, axil_data),  // both data buses have to be the same
            Div#(axil_data, 8, axil_bytes),
            Mul#(axil_bytes, 8, axil_data),
            Div#(apb_data, 8, apb_bytes),
            Mul#(apb_bytes, 8, apb_data),
            Log#(apb_bytes, lg_apb_bytes),
            Div#(axil_data, apb_data, child_count),
            Add#(d__, apb_bytes, axil_bytes),

            Add#(a__, TDiv#(apb_data, 8), TDiv#(axil_data, 8)), // strbs are also smaller
            Add#(b__, 8, axil_addr),
            Mul#(apb_data, c__, axil_data) // Apb is a byte multiple of axil_data
           );

  let v_axil_data = valueOf(axil_data);
  let v_apb_data = valueOf(apb_data);
  let v_child_count = valueOf(child_count);
  let v_apb_bytes = valueOf(apb_bytes);
  let v_axil_bytes = valueOf(axil_bytes);
  let v_bytes_ratio = valueOf(TDiv#(axil_bytes, apb_bytes));
  let v_lg_apb_bytes = valueOf(lg_apb_bytes);
  // -------------------------------------------------------------------------------------------- //
  // instantiate the transactors

  Ifc_apb_master_xactor#( apb_addr, apb_data, user)         apb_xactor <- mkapb_master_xactor;
  Ifc_axi4l_slave_xactor#( axil_addr, axil_data, user) axil_xactor <- mkaxi4l_slave_xactor(defaultValue);
  // -------------------------------------------------------------------------------------------- //
  
  Bit#(8) lv_child_burst = fromInteger(v_axil_bytes);

  /*doc:reg: dictates the state that the bridge is currently in */
  ConfigReg#(Axil2ApbBridgeState)                 rg_state       <- mkConfigReg(Idle);

  /*doc:reg: captures the initial read request from the axi read-channel*/
  Reg#(Axi4l_rd_addr #(axil_addr, user))         rg_rd_request  <- mkReg(unpack(0));

  /*doc:reg: holds the current byte-requests sent to the apb-side for the current axi-transaction.
   * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                  rg_child_req_count <- mkReg(0);

  /*doc:reg: holds the current byte-responses received from the apb-side for the current axi-transaction.
   * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                  rg_child_res_count <- mkReg(0);

  /*doc:reg: this register is used to accumulate child responses for a single axi-transaction and send it
   * as a single axi-response. In case of write-requests this register holds the data to be sent.*/
  Reg#(Bit#(axil_data))                          rg_accum_data  <- mkReg(0);
  
  /*doc:reg: a mask register used to indicate which bytes of the rg_accum_data need to be updated
   * with the current response from the APB*/
  Reg#(Bit#(axil_bytes))                         rg_accum_mask  <- mkReg(0);

  /*doc:reg: */
  Reg#(Bool)                                     rg_accum_err   <- mkReg(False);
  /*doc:reg: captures the initial read request from the axi write address-channel*/
  Reg#(Axi4l_wr_addr #(axil_addr, user))         rg_wr_request  <- mkReg(unpack(0));
  /*doc:reg: captures the initial read request from the axi write data*/
  Reg#(Axi4l_wr_data #(axil_data))               rg_wd_request  <- mkReg(unpack(0));

  /*doc:rule: this rule pops the read request from axi-lite and initiates a request on the APB. This rule
  will also account for the apb-data size being smaller than the request size. In such a case,
  each axi-transaction is split into further child-bursts. The size of the single transaction request in
  terms of bytes is stored in the variable lv_child_burst. We set the apb-data size in terms of
  bytes in the register rg_child_req_count. This will be used to count the number of child-bursts
  to be sent per axi-transaction. Also this register is also used to calculate the address of individual
  child-bursts. */
  rule rl_read_frm_axi (rg_state == Idle);
    let axil_req <- pop_o(axil_xactor.fifo_side.o_rd_addr);
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(axil_req.araddr),
                                                                    prot  : axil_req.arprot,
                                                                    pwrite: False,
                                                                    pwdata: ?,
                                                                    pstrb : 0,
                                                                    puser : axil_req.aruser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    rg_rd_request    <= axil_req;
    rg_state         <= ReadResp;
    `logLevel( bridge, 0, $format("Axil2Apb: AXI4-Lite-Read:",fshow_axi4l_rd_addr(axil_req)))
    `logLevel( bridge, 0, $format("Axil2Apb: APB-Req  :",fshow_apb_req(apb_request)))
    if (v_bytes_ratio > 1 ) begin
      Bit#(apb_bytes) mask = '1;
      rg_child_res_count <= fromInteger(v_apb_bytes);
      rg_child_req_count <= fromInteger(v_apb_bytes);
      rg_accum_mask  <= zeroExtend(mask);
    end
    else begin
      rg_accum_mask <= '1;
    end
  endrule:rl_read_frm_axi
  
  /*doc:rule: this rule will exist only if the request-size is greater than the apb-data size, then 
  child-bursts for each axi-transaction is sent through this rule. In case of the child-bursts, 
  the new childburst address is derived by adding the rg_child_req_count to the axi-request. 
  When the register rg_child_req_count reaches the necessary byte-count then axi-transaction 
  is completed.*/
  rule rl_send_rd_burst_req(rg_state == ReadResp && lv_child_burst != rg_child_req_count
                            && v_bytes_ratio > 1 );
    Bit#(axil_addr) new_address = rg_rd_request.araddr + zeroExtend(rg_child_req_count); 
    rg_child_req_count <= rg_child_req_count + fromInteger(v_apb_bytes);
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(new_address),
                                                                    prot  : rg_rd_request.arprot,
                                                                    pwrite: False,
                                                                    pwdata: ?,
                                                                    pstrb : 0,
                                                                    puser : rg_rd_request.aruser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    `logLevel( bridge, 0, $format("Axil2Apb: AXI4-Lite-RdBurst Addr:%h",new_address))
    `logLevel( bridge, 0, $format("Axil2Apb: New APB-Req  :",fshow_apb_req(apb_request)))
    `logLevel( bridge, 0, $format("Axil2Apb: Child:%d ChildReq:%d",lv_child_burst,
    rg_child_req_count))
  endrule:rl_send_rd_burst_req

  /*doc:rule: collects read responses from APB and sends to AXI-Lite. When the apb-data is smaller than
  * the request-size, then the responses from the APB are collated together in a temp register:
  * rg_accum_data. This register is updated with the APB response using a byte mask which is 
  * also maintained as a temp register : rg_accum_mask. The axi-transaction response count is 
  * completed when the required number of child-bursts are complete. */
  rule rl_read_response_to_axi(rg_state == ReadResp);
    
    let apb_response <- pop_o(apb_xactor.fifo_side.o_response);
    Bit#(apb_data) _data = apb_response.prdata;
    Bit#(axil_data) _resp_data = duplicate(_data);
    if (v_bytes_ratio > 1) begin
      _resp_data = updateDataWithMask(rg_accum_data, _resp_data, rg_accum_mask);
      rg_accum_data <= _resp_data;
      rg_accum_mask <= rotateBitsBy(rg_accum_mask, fromInteger(v_apb_bytes));
    end
    Axi4l_rd_data #(axil_data, user) axil_response = Axi4l_rd_data {
                                     rdata: _resp_data,
                                     rresp: apb_response.pslverr?axi4l_resp_slverr:axi4l_resp_okay,
                                     ruser: apb_response.puser};

    if(v_bytes_ratio > 1 && rg_child_res_count != lv_child_burst) begin
      `logLevel( bridge, 0, $format("Axil2Apb: Accumulate"))
      rg_child_res_count <= rg_child_res_count + fromInteger(v_apb_bytes);
    end
    else begin
      axil_xactor.fifo_side.i_rd_data.enq(axil_response);
      `logLevel( bridge, 0, $format("Axil2Apb: AXI4-Lite-RdResp:",fshow_axi4l_rd_data(axil_response)))
      rg_state <= Idle;
    end

    `logLevel( bridge, 0, $format("Axil2Apb: APB-Resp: ",fshow_apb_resp(apb_response)))
    `logLevel( bridge, 0, $format("Axil2Apb: Child:%d ChildRes:%d Mask:%b Accum:%h",lv_child_burst,
      rg_child_res_count, rg_accum_mask, rg_accum_data))
  endrule:rl_read_response_to_axi
  
  /*doc:rule: this rule pops the read request from axi and initiates a request on the APB. This rule
  * works exactly similar to rule working of rl_read_frm_axi*/
  rule rl_write_frm_axi (rg_state == Idle);
    let axil_req  <- pop_o(axil_xactor.fifo_side.o_wr_addr);
    let axil_wreq = axil_xactor.fifo_side.o_wr_data.first;
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(axil_req.awaddr),
                                                                    prot  : axil_req.awprot,
                                                                    pwrite: True,
                                                                    pwdata: truncate(axil_wreq.wdata),
                                                                    pstrb : truncate(axil_wreq.wstrb),
                                                                    puser : axil_req.awuser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    rg_wr_request    <= axil_req;
    rg_wd_request    <= axil_wreq;
    rg_state         <= WriteResp;
    rg_accum_err     <= False;
    if (v_bytes_ratio > 1 ) begin
      Bit#(apb_bytes) mask = '1;
      rg_child_res_count <= fromInteger(v_apb_bytes);
      rg_child_req_count <= fromInteger(v_apb_bytes);
      rg_accum_mask  <= zeroExtend(mask);
    end
    else begin
      rg_accum_mask <= '1;
    end
    `logLevel( bridge, 0, $format("Axil2Apb: AXI4-Lite-Write:",fshow_axi4l_wr_addr(axil_req)))
    `logLevel( bridge, 0, $format("Axil2Apb: APB-Req  :",fshow_apb_req(apb_request)))
  endrule:rl_write_frm_axi
  
  /*doc:rule: this rule will generate new addresses based on burst-mode and lenght and send write
  requests to the APB. This rule behaves exactly like rl_send_rd_burst_req.*/
  rule rl_send_wr_burst_req(rg_state == WriteResp && v_bytes_ratio > 1 && 
                            rg_child_req_count != lv_child_burst);
    let axil_wreq = axil_xactor.fifo_side.o_wr_data.first;
    Bit#(axil_data) _write_data = axil_wreq.wdata;
    Bit#(TDiv#(axil_data,8)) _wstrb = axil_wreq.wstrb;
    Bit#(axil_addr) new_address = rg_wr_request.awaddr + zeroExtend(rg_child_req_count); 
    rg_child_req_count <= rg_child_req_count + fromInteger(v_apb_bytes);
    Bit#(TAdd#(3,8)) shift = {rg_child_req_count,'d0};
    _write_data = _write_data >> shift;
    _wstrb = _wstrb >> rg_child_req_count;
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(new_address),
                                                                    prot  : rg_wr_request.awprot,
                                                                    pwrite: True,
                                                                    pwdata: truncate(_write_data),
                                                                    pstrb : truncate(_wstrb),
                                                                    puser : rg_wr_request.awuser};
    if (rg_child_req_count == lv_child_burst) begin
      axil_xactor.fifo_side.o_wr_data.deq;
      `logLevel( bridge, 0, $format("Axil2Apb: AXI4-Lite-Wr Poping Wd Request:",
          fshow_axi4l_wr_data(axil_wreq)))
    end
    else 
      apb_xactor.fifo_side.i_request.enq(apb_request);
    `logLevel( bridge, 0, $format("Axil2Apb: New AXI4-Lite-Write ",fshow_axi4l_wr_data(axil_wreq)))
    `logLevel( bridge, 0, $format("Axil2Apb: APB-Req  :",fshow_apb_req(apb_request)))
    `logLevel( bridge, 0, $format("Axil2Apb: Child:%d ChildReq:%d",lv_child_burst,
    rg_child_req_count))
  endrule:rl_send_wr_burst_req

  /*doc:rule: collects read responses from APB and send to AXI. This rule behaves similar to
  * rl_read_response_to_axi except for the fact that the response is sent only at the end of
  * completion of all beats*/
  rule rl_write_response_to_axi(rg_state == WriteResp);
    
    let apb_response <- pop_o(apb_xactor.fifo_side.o_response);
    rg_accum_err <= rg_accum_err || apb_response.pslverr;
    let axil_response = Axi4l_wr_resp {bresp: rg_accum_err || apb_response.pslverr ?axi4l_resp_slverr:axi4l_resp_okay,
                                       buser: apb_response.puser};
    if(v_bytes_ratio > 1 && rg_child_res_count != lv_child_burst) begin
      `logLevel( bridge, 0, $format("Axil2Apb: Accumulate"))
      rg_child_res_count <= rg_child_res_count + fromInteger(v_apb_bytes);
    end
    else begin
      axil_xactor.fifo_side.i_wr_resp.enq(axil_response);
      rg_state <= Idle;
    end
    `logLevel( bridge, 0, $format("Axil2Apb: APB-Resp:", fshow_apb_resp(apb_response)))
  endrule:rl_write_response_to_axi

  interface axil_side = axil_xactor.axil_side;
  interface apb_side = apb_xactor.apb_side;

endmodule:mkaxil2apb

instance Connectable #(Ifc_axi4l_master #(axil_addr, axil_data, user), 
                       Ifc_apb_slave    #(apb_addr, apb_data, user))
  provisos (Add#(apb_addr, _a, axil_addr), // AXI address cannot be smaller in size than APB
            Add#(apb_data, _b, axil_data),  // both data buses have to be the same
            Div#(axil_data, 8, axil_bytes),
            Mul#(axil_bytes, 8, axil_data),
            Div#(apb_data, 8, apb_bytes),
            Mul#(apb_bytes, 8, apb_data),
            Log#(apb_bytes, lg_apb_bytes),
            Div#(axil_data, apb_data, child_count),
            Add#(d__, apb_bytes, axil_bytes),

            Add#(a__, TDiv#(apb_data, 8), TDiv#(axil_data, 8)), // strbs are also smaller
            Add#(b__, 8, axil_addr),
            Mul#(apb_data, c__, axil_data) // Apb is a byte multiple of axil_data
          );
  module mkConnection #(Ifc_axi4l_master #(axil_addr, axil_data, user) axil_side,
                       Ifc_apb_slave #(apb_addr, apb_data, user)         apb_side)
                       (Empty);
    Ifc_axil2apb #(axil_addr, axil_data, apb_addr, apb_data, user) bridge <- mkaxil2apb;
    mkConnection(axil_side, bridge.axil_side);
    mkConnection(apb_side, bridge.apb_side);
  endmodule:mkConnection
endinstance:Connectable

instance Connectable #(Ifc_apb_slave    #(apb_addr, apb_data, user),
                       Ifc_axi4l_master #(axil_addr, axil_data, user) )
  provisos (Add#(apb_addr, _a, axil_addr), // AXI address cannot be smaller in size than APB
            Add#(apb_data, _b, axil_data),  // both data buses have to be the same
            Div#(axil_data, 8, axil_bytes),
            Mul#(axil_bytes, 8, axil_data),
            Div#(apb_data, 8, apb_bytes),
            Mul#(apb_bytes, 8, apb_data),
            Log#(apb_bytes, lg_apb_bytes),
            Div#(axil_data, apb_data, child_count),
            Add#(d__, apb_bytes, axil_bytes),

            Add#(a__, TDiv#(apb_data, 8), TDiv#(axil_data, 8)), // strbs are also smaller
            Add#(b__, 8, axil_addr),
            Mul#(apb_data, c__, axil_data) // Apb is a byte multiple of axil_data
          );
  module mkConnection #(Ifc_apb_slave #(apb_addr, apb_data, user)         apb_side,
                        Ifc_axi4l_master #(axil_addr, axil_data, user) axil_side )
                       (Empty);
    mkConnection(axil_side, apb_side);
  endmodule:mkConnection
endinstance:Connectable

endpackage: axil2apb

