// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 08 April 2020 02:24:19 PM IST
*/
/*doc:overview:

This module implements a bridge/adapter which can be used to convert AXI-4 transactions into APB 
(a.k.a APB4, a.k.a APBv2.0) transactions. This bridges acts as a slave on the AXI4 
interface and as a master on an ABP interface. Both the protocols are little endian.
The bridge is parameterized to handle different address and data sizes of either
side with the following contraints:

1. The AXI4 address size must be greater than or equal to the APB address size.
2. The AXI4 data size must be greater than of equal to the APB data size.
3. The AXI4 data and APB data should both be byte-multiples

The bridge also supports spliting of read/write bursts from the AXI4 side to individual requests on
the APB cluster.

A Connectable instance is also provided which can directly connect an AXI4 master interface to a
APB-slave interface.


Working Principle
-----------------

Since the APB is a single channel bus and the AXI4 has separate read and write channels, the read
requests from the AXI4 are given priority over the write requests occurring in the same cycle. At
any point of time only a single requests (burst read or burst write) are served, and the next
request is picked up only when the APB has responded to all the bursts from the previous requests.

Differing Address sizes
^^^^^^^^^^^^^^^^^^^^^^^

When the AXI4 and APB address sizes are different, then the lower bits of the AXI4 addresses are
used on the APB side. 

Differing Data sizes
^^^^^^^^^^^^^^^^^^^^

When the AXI4 and APB data sizes are different, each single beat of the AXI4 request (read or write)
is split into multiple smaller child bursts (sent as individual APB requests) which matches 
APB data size. A beat is complete only when its corresponding child-bursts are over. The next
single-beat address is generated based on the burst-mode request and the burst size. Thus, the
bridge can support all AXI4 burst-modes: incr, fixed and wrap.

When instantiated with same data-sizes, the child-burst logic is ommitted.

Error mapping
^^^^^^^^^^^^^

The APB PSLVERR is mapped to the AXI4 SLVERR.

.. note::
  Currently the bridge works for the same clock on either side. Multiple clock domain support will
  available in future versions

*/
package axi2apb ;

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

import axi4         :: * ;
import apb          :: * ;

import Semi_FIFOF   :: * ;
`include "Logger.bsv"

typedef enum {Idle, ReadResp, WriteResp} Axi2ApbBridgeState deriving (Bits, FShow, Eq);

interface Ifc_axi2apb #(  numeric type axi_id, 
                          numeric type axi_addr,
                          numeric type axi_data,
                          numeric type apb_addr,
                          numeric type apb_data,
                          numeric type user );
  (*prefix=""*)
  interface Ifc_axi4_slave #(axi_id, axi_addr, axi_data, user) axi_side;
  (*prefix=""*)
  interface Ifc_apb_master #(apb_addr, apb_data, user)         apb_side;
endinterface:Ifc_axi2apb

(*preempts="rl_read_frm_axi, rl_write_frm_axi"*)
module mkaxi2apb(Ifc_axi2apb#(axi_id, axi_addr, axi_data, apb_addr, apb_data, user))
  provisos (Add#(apb_addr, _a, axi_addr), // AXI address cannot be smaller in size than APB
            Add#(apb_data, _b, axi_data),  // both data buses have to be the same
            Div#(axi_data, 8, axi_bytes),
            Mul#(axi_bytes, 8, axi_data),
            Div#(apb_data, 8, apb_bytes),
            Mul#(apb_bytes, 8, apb_data),
            Log#(apb_bytes, lg_apb_bytes),
            Div#(axi_data, apb_data, child_count),
            Add#(d__, apb_bytes, axi_bytes),

            Add#(a__, TDiv#(apb_data, 8), TDiv#(axi_data, 8)), // strbs are also smaller
            Add#(b__, 8, axi_addr),
            Mul#(apb_data, c__, axi_data) // Apb is a byte multiple of axi_data
           );

  let v_axi_data = valueOf(axi_data);
  let v_apb_data = valueOf(apb_data);
  let v_child_count = valueOf(child_count);
  let v_apb_bytes = valueOf(apb_bytes);
  let v_axi_bytes = valueOf(axi_bytes);
  let v_bytes_ratio = valueOf(TDiv#(axi_bytes, apb_bytes));
  let v_lg_apb_bytes = valueOf(lg_apb_bytes);
  // -------------------------------------------------------------------------------------------- //
  // instantiate the transactors

  Ifc_apb_master_xactor#( apb_addr, apb_data, user)         apb_xactor <- mkapb_master_xactor;
  Ifc_axi4_slave_xactor#( axi_id, axi_addr, axi_data, user) axi_xactor <- mkaxi4_slave_xactor(defaultValue);
  // -------------------------------------------------------------------------------------------- //

  /*doc:reg: dictates the state that the bridge is currently in */
  ConfigReg#(Axi2ApbBridgeState)                        rg_state       <- mkConfigReg(Idle);

  /*doc:reg: captures the initial read request from the axi read-channel*/
  Reg#(AXI4_rd_addr #(axi_id, axi_addr, user))          rg_rd_request  <- mkReg(unpack(0));

  /*doc:reg: this register holds the count of the read requests to be sent to the APB*/
  Reg#(Bit#(8))                                         rg_req_beat <- mkReg(0);

  /*doc:reg: this register increments everytime a read-response from the APB is received. Since we
  * can send requests independently of the response, two counters are required.*/
  Reg#(Bit#(8))                                         rg_resp_beat <- mkReg(0);

  /*doc:reg: this register holds the amount of requests required per axi-beat if the apb-data size
   * is less than the apb-data size. If the size satisfies then this register is set 0. 
   * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_burst <- mkReg(0);

  /*doc:reg: holds the current byte-requests sent to the apb-side for the current axi-beat.
   * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_req_count <- mkReg(0);

  /*doc:reg: holds the current byte-responses received from the apb-side for the current axi-beat.
   * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_res_count <- mkReg(0);

  /*doc:reg: this register is used to accumulate child responses for a single axi-beat and send it
   * as a single axi-response. In case of write-requests this register holds the data to be sent.*/
  Reg#(Bit#(axi_data))                                  rg_accum_data  <- mkReg(0);
  
  /*doc:reg: a mask register used to indicate which bytes of the rg_accum_data need to be updated
   * with the current response from the APB*/
  Reg#(Bit#(axi_bytes))                                 rg_accum_mask  <- mkReg(0);

  /*doc:reg: captures the initial read request from the axi write address-channel*/
  Reg#(AXI4_wr_addr #(axi_id, axi_addr, user))          rg_wr_request  <- mkReg(unpack(0));
  /*doc:reg: captures the initial read request from the axi write data*/
  Reg#(AXI4_wr_data #(axi_data, user))                  rg_wd_request  <- mkReg(unpack(0));
  /*doc:reg: */
  Reg#(Bool)                                            rg_accum_err   <- mkReg(False);

  /*doc:rule: this rule pops the read request from axi and initiates a request on the APB. This rule
  will also account for the apb-data size being smaller than the request size. In such a case,
  each axi-level beat is split into further child-bursts. The size of the single beat request in
  terms of bytes is stored in the register rg_child_burst. We set the apb-data size in terms of
  bytes in the register rg_child_req_count. This will be used to count the number of child-bursts
  to be sent per axi-beat. Also this register is also used to calculate the address of individual
  child-bursts. When the request-size per axi-beat is more than the apb-data size, then the burst
  count provided by arlen is incremented by 1 and stored in rg_req_beat. This is because,
  child-burst erquests are sent through the same rule and setting it to 0 would prevent that rule
  from the firing. */
  rule rl_read_frm_axi (rg_state == Idle);
    let axi_req <- pop_o(axi_xactor.fifo_side.o_rd_addr);
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(axi_req.araddr),
                                                                    prot  : axi_req.arprot,
                                                                    pwrite: False,
                                                                    pwdata: ?,
                                                                    pstrb : 0,
                                                                    puser : axi_req.aruser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    rg_rd_request    <= axi_req;
    rg_state         <= ReadResp;
    `logLevel( bridge, 0, $format("Axi2Apb: AXI4-Read:",fshow_axi4_rd_addr(axi_req)))
    `logLevel( bridge, 0, $format("Axi2Apb: APB-Req  :",fshow_apb_req(apb_request)))
    if (v_bytes_ratio > 1 ) begin
      Bit#(8) request_size = ('b1) << axi_req.arsize;
      Bit#(apb_bytes) mask = '1;
      if(request_size > fromInteger(v_apb_bytes)) begin
        rg_req_beat   <= axi_req.arlen + 1;
        rg_resp_beat   <= axi_req.arlen + 1;
        rg_child_burst <= request_size ;
        rg_child_res_count <= fromInteger(v_apb_bytes);
        rg_child_req_count <= fromInteger(v_apb_bytes);
        rg_accum_mask  <= zeroExtend(mask);
      end
      else begin
        rg_req_beat   <= axi_req.arlen;
        rg_resp_beat   <= axi_req.arlen + 1;
        rg_child_burst <= 0;
        rg_child_req_count <= 0;
        rg_child_res_count <= 0;
        rg_accum_mask <= '1;
      end
    end
    else begin
      rg_req_beat   <= axi_req.arlen;
      rg_resp_beat   <= axi_req.arlen + 1;
      rg_accum_mask <= '1;
    end
  endrule:rl_read_frm_axi
  
  /*doc:rule: this rule will generate new addresses based on burst-mode and lenght and send read 
  requests to the APB. This rule will generate subsequent requests to the apb for a burst request
  from the axi. If the request-size is greater than the apb-data size, then child-bursts for each
  axi-beat is also sent through this rule. In case of the child-bursts, the new childburst address
  is derived by adding the rg_child_req_count to the current beat-address. The beat-address itself
  is generated using the axi-address generator function. When the register rg_child_req_count
  reaches the necessary byte-count then axi-beat count is incremented.*/
  rule rl_send_rd_burst_req(rg_state == ReadResp && rg_req_beat !=0);
    Bit#(axi_addr) new_address = truncate(fn_axi4burst_addr(rg_rd_request.arlen, 
                                                            rg_rd_request.arsize, 
                                                            rg_rd_request.arburst,
                                                            rg_rd_request.araddr));
    if(v_bytes_ratio > 1 && rg_child_req_count != rg_child_burst )begin
      new_address = rg_rd_request.araddr + zeroExtend(rg_child_req_count); 
      rg_child_req_count <= rg_child_req_count + fromInteger(v_apb_bytes);
    end
    else begin
      let next_req = rg_rd_request;
      next_req.araddr = new_address;
      rg_rd_request <= next_req;
      if(v_bytes_ratio > 1 && rg_child_burst != 0)
        rg_child_req_count <= fromInteger(v_apb_bytes);
    end
    if (v_bytes_ratio > 1)begin
      if (rg_child_req_count == (rg_child_burst - fromInteger(v_apb_bytes)) || (rg_child_burst == 0))
        rg_req_beat <= rg_req_beat - 1;
    end
    else
      rg_req_beat <= rg_req_beat - 1;
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(new_address),
                                                                    prot  : rg_rd_request.arprot,
                                                                    pwrite: False,
                                                                    pwdata: ?,
                                                                    pstrb : 0,
                                                                    puser : rg_rd_request.aruser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    `logLevel( bridge, 0, $format("Axi2Apb: AXI4-RdBurst Addr:%h Count:%d",new_address,
        rg_req_beat))
    `logLevel( bridge, 0, $format("Axi2Apb: New APB-Req  :",fshow_apb_req(apb_request)))
    `logLevel( bridge, 0, $format("Axi2Apb: Child:%d ChildReq:%d",rg_child_burst,
    rg_child_req_count))
  endrule:rl_send_rd_burst_req

  /*doc:rule: collects read responses from APB and send to AXI. When the apb-data is smaller than
  * the request-size, then the responses from the APB are collated together in a temp register:
  * rg_accum_data. This register is updated with the APB response using a byte mask which is 
  * also maintained as a temp register : rg_accum_mask. The axi-beat response count is incremented
  * each time the required number of child-bursts are complete. Note, here the response beat counter
  * starts with arlen + 1 and terminates on reaching 1 as compared to the request beat counter which
  * starts at arlen. This is because, when a new request is taken that is passed on to the APB in
  * the same cycle, thus one beat count less as compared to response*/
  rule rl_read_response_to_axi(rg_state == ReadResp && rg_resp_beat != 0);
    
    let apb_response <- pop_o(apb_xactor.fifo_side.o_response);
    Bit#(apb_data) _data = apb_response.prdata;
    Bit#(axi_data) _resp_data = duplicate(_data);
    if (v_bytes_ratio > 1) begin
      _resp_data = updateDataWithMask(rg_accum_data, _resp_data, rg_accum_mask);
      rg_accum_data <= _resp_data;
      rg_accum_mask <= rotateBitsBy(rg_accum_mask, fromInteger(v_apb_bytes));
    end
    AXI4_rd_data #(axi_id, axi_data, user) axi_response = AXI4_rd_data {rid: rg_rd_request.arid,
                                     rdata: _resp_data,
                                     rresp: apb_response.pslverr?axi4_resp_slverr:axi4_resp_okay,
                                     ruser: apb_response.puser,
                                     rlast: rg_resp_beat == 1 };

    if(v_bytes_ratio > 1 && rg_child_res_count != rg_child_burst && rg_child_burst != 0) begin
      `logLevel( bridge, 0, $format("Axi2Apb: Accumulate"))
      rg_child_res_count <= rg_child_res_count + fromInteger(v_apb_bytes);
    end
    else begin
      rg_resp_beat <= rg_resp_beat - 1;
      axi_xactor.fifo_side.i_rd_data.enq(axi_response);
      `logLevel( bridge, 0, $format("Axi2Apb: AXI-RdResp:",fshow_axi4_rd_data(axi_response)))
      if(v_bytes_ratio > 1 && rg_child_burst != 0)
        rg_child_res_count <= fromInteger(v_apb_bytes);
    end

    if(rg_resp_beat == 1 && (rg_child_res_count == rg_child_burst || rg_child_burst == 0)) begin
      rg_state <= Idle;
    end
    `logLevel( bridge, 0, $format("Axi2Apb: APB-Resp: Count:%2d",rg_resp_beat, fshow_apb_resp(apb_response)))
    `logLevel( bridge, 0, $format("Axi2Apb: Child:%d ChildRes:%d Mask:%b Accum:%h",rg_child_burst,
      rg_child_res_count, rg_accum_mask, rg_accum_data))
  endrule:rl_read_response_to_axi
  
  /*doc:rule: this rule pops the read request from axi and initiates a request on the APB. This rule
  * works exactly similar to rule working of rl_read_frm_axi*/
  rule rl_write_frm_axi (rg_state == Idle);
    let axi_req  <- pop_o(axi_xactor.fifo_side.o_wr_addr);
    let axi_wreq = axi_xactor.fifo_side.o_wr_data.first;
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(axi_req.awaddr),
                                                                    prot  : axi_req.awprot,
                                                                    pwrite: True,
                                                                    pwdata: truncate(axi_wreq.wdata),
                                                                    pstrb : truncate(axi_wreq.wstrb),
                                                                    puser : axi_req.awuser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    rg_wr_request    <= axi_req;
    rg_wd_request    <= axi_wreq;
    rg_state         <= WriteResp;
    rg_accum_err     <= False;
    if (v_bytes_ratio > 1 ) begin
      Bit#(8) request_size = ('b1) << axi_req.awsize;
      Bit#(apb_bytes) mask = '1;
      if(request_size > fromInteger(v_apb_bytes)) begin
        rg_req_beat   <= axi_req.awlen + 1;
        rg_resp_beat   <= axi_req.awlen + 1;
        rg_child_burst <= request_size ;
        rg_child_res_count <= fromInteger(v_apb_bytes);
        rg_child_req_count <= fromInteger(v_apb_bytes);
        rg_accum_mask  <= zeroExtend(mask);
      end
      else begin
        rg_req_beat   <= axi_req.awlen;
        rg_resp_beat   <= axi_req.awlen + 1;
        rg_child_burst <= 0;
        rg_child_req_count <= 0;
        rg_child_res_count <= 0;
        rg_accum_mask <= '1;
        axi_xactor.fifo_side.o_wr_data.deq;
      end
    end
    else begin
      rg_req_beat   <= axi_req.awlen;
      rg_resp_beat   <= axi_req.awlen + 1;
      rg_accum_mask <= '1;
        axi_xactor.fifo_side.o_wr_data.deq;
    end
    `logLevel( bridge, 0, $format("Axi2Apb: AXI4-Write:",fshow_axi4_wr_addr(axi_req)))
    `logLevel( bridge, 0, $format("Axi2Apb: APB-Req  :",fshow_apb_req(apb_request)))
  endrule:rl_write_frm_axi
  
  /*doc:rule: this rule will generate new addresses based on burst-mode and lenght and send write
  requests to the APB. This rule behaves exactly like rl_send_rd_burst_req.*/
  rule rl_send_wr_burst_req(rg_state == WriteResp && rg_req_beat !=0);
    let axi_wreq = axi_xactor.fifo_side.o_wr_data.first;
    Bit#(axi_data) _write_data = axi_wreq.wdata;
    Bit#(TDiv#(axi_data,8)) _wstrb = axi_wreq.wstrb;
    let new_address = fn_axi4burst_addr(rg_wr_request.awlen, 
                                        rg_wr_request.awsize, 
                                        rg_wr_request.awburst,
                                        rg_wr_request.awaddr);
    if(v_bytes_ratio > 1 && rg_child_req_count != rg_child_burst )begin
      new_address = rg_wr_request.awaddr + zeroExtend(rg_child_req_count); 
      rg_child_req_count <= rg_child_req_count + fromInteger(v_apb_bytes);
      Bit#(TAdd#(TLog#(apb_data),8)) shift = {rg_child_req_count,'d0};
      _write_data = _write_data >> shift;
      _wstrb = _wstrb >> rg_child_req_count;
    end
    else begin
      let next_req = rg_wr_request;
      next_req.awaddr = new_address;
      rg_wr_request <= next_req;
      if(v_bytes_ratio > 1 && rg_child_burst != 0)
        rg_child_req_count <= fromInteger(v_apb_bytes);
    end
    if (v_bytes_ratio > 1)begin
      if (rg_child_req_count == (rg_child_burst - fromInteger(v_apb_bytes)) || (rg_child_burst == 0)) begin
        rg_req_beat <= rg_req_beat - 1;
        axi_xactor.fifo_side.o_wr_data.deq;
        `logLevel( bridge, 0, $format("Axi2Apb: AXI4-Wr Poping Wd Request:",
            fshow_axi4_wr_data(axi_wreq)))
      end
    end
    else begin
      rg_req_beat <= rg_req_beat - 1;
      axi_xactor.fifo_side.o_wr_data.deq;
      `logLevel( bridge, 0, $format("Axi2Apb: AXI4-Wr Poping Wd Request:",fshow_axi4_wr_data(axi_wreq)))
    end
    APB_request #(apb_addr, apb_data, user) apb_request = APB_request {
                                                                    paddr : truncate(new_address),
                                                                    prot  : rg_wr_request.awprot,
                                                                    pwrite: True,
                                                                    pwdata: truncate(_write_data),
                                                                    pstrb : truncate(_wstrb),
                                                                    puser : rg_wr_request.awuser};
    apb_xactor.fifo_side.i_request.enq(apb_request);
    `logLevel( bridge, 0, $format("Axi2Apb: New AXI4-Write Count:%d:",rg_req_beat,
        fshow_axi4_wr_data(axi_wreq)))
    `logLevel( bridge, 0, $format("Axi2Apb: APB-Req  :",fshow_apb_req(apb_request)))
    `logLevel( bridge, 0, $format("Axi2Apb: Child:%d ChildReq:%d",rg_child_burst,
    rg_child_req_count))
  endrule:rl_send_wr_burst_req

  /*doc:rule: collects read responses from APB and send to AXI. This rule behaves similar to
  * rl_read_response_to_axi except for the fact that the response is sent only at the end of
  * completion of all beats*/
  rule rl_write_response_to_axi(rg_state == WriteResp && rg_resp_beat != 0);
    
    let apb_response <- pop_o(apb_xactor.fifo_side.o_response);
    rg_accum_err <= rg_accum_err || apb_response.pslverr;
    let axi_response = AXI4_wr_resp {bid: rg_wr_request.awid,
                                     bresp: rg_accum_err || apb_response.pslverr ?axi4_resp_slverr:axi4_resp_okay,
                                     buser: apb_response.puser};
    if(v_bytes_ratio > 1 && rg_child_res_count != rg_child_burst && rg_child_burst != 0) begin
      `logLevel( bridge, 0, $format("Axi2Apb: Accumulate"))
      rg_child_res_count <= rg_child_res_count + fromInteger(v_apb_bytes);
    end
    else begin
      rg_resp_beat <= rg_resp_beat - 1;
      if(v_bytes_ratio > 1 && rg_child_burst != 0)
        rg_child_res_count <= fromInteger(v_apb_bytes);
    end
    if(rg_resp_beat == 1 && (rg_child_res_count == rg_child_burst || rg_child_burst == 0) ) begin
      axi_xactor.fifo_side.i_wr_resp.enq(axi_response);
      rg_state <= Idle;
    end
    `logLevel( bridge, 0, $format("Axi2Apb: APB-Resp: Count:%2d",rg_resp_beat, fshow_apb_resp(apb_response)))
  endrule:rl_write_response_to_axi

  interface axi_side = axi_xactor.axi_side;
  interface apb_side = apb_xactor.apb_side;

endmodule:mkaxi2apb


instance Connectable #(Ifc_axi4_master #(axi_id, axi_addr, axi_data, user), 
    Ifc_apb_slave #(apb_addr, apb_data, user))
  provisos (Add#(apb_addr, _a, axi_addr), // AXI address cannot be smaller in size than APB
            Add#(apb_data, _b, axi_data),  // both data buses have to be the same
            Div#(axi_data, 8, axi_bytes),
            Mul#(axi_bytes, 8, axi_data),
            Div#(apb_data, 8, apb_bytes),
            Mul#(apb_bytes, 8, apb_data),
            Log#(apb_bytes, lg_apb_bytes),
            Div#(axi_data, apb_data, child_count),
            Add#(d__, apb_bytes, axi_bytes),

            Add#(a__, TDiv#(apb_data, 8), TDiv#(axi_data, 8)), // strbs are also smaller
            Add#(b__, 8, axi_addr),
            Mul#(apb_data, c__, axi_data) // Apb is a byte multiple of axi_data
          );
  module mkConnection #(Ifc_axi4_master #(axi_id, axi_addr, axi_data, user) axi_side,
                       Ifc_apb_slave #(apb_addr, apb_data, user)         apb_side)
                       (Empty);
    Ifc_axi2apb #(axi_id, axi_addr, axi_data, apb_addr, apb_data, user) bridge <- mkaxi2apb;
    mkConnection(axi_side, bridge.axi_side);
    mkConnection(apb_side, bridge.apb_side);
  endmodule:mkConnection
endinstance:Connectable

instance Connectable #(Ifc_apb_slave #(apb_addr, apb_data, user),
      Ifc_axi4_master #(axi_id, axi_addr, axi_data, user) )
  provisos (Add#(apb_addr, _a, axi_addr), // AXI address cannot be smaller in size than APB
            Add#(apb_data, _b, axi_data),  // both data buses have to be the same
            Div#(axi_data, 8, axi_bytes),
            Mul#(axi_bytes, 8, axi_data),
            Div#(apb_data, 8, apb_bytes),
            Mul#(apb_bytes, 8, apb_data),
            Log#(apb_bytes, lg_apb_bytes),
            Div#(axi_data, apb_data, child_count),
            Add#(d__, apb_bytes, axi_bytes),

            Add#(a__, TDiv#(apb_data, 8), TDiv#(axi_data, 8)), // strbs are also smaller
            Add#(b__, 8, axi_addr),
            Mul#(apb_data, c__, axi_data) // Apb is a byte multiple of axi_data
          );
  module mkConnection #(Ifc_apb_slave #(apb_addr, apb_data, user)         apb_side,
                        Ifc_axi4_master #(axi_id, axi_addr, axi_data, user) axi_side )
                       (Empty);
    mkConnection(axi_side, apb_side);
  endmodule:mkConnection
endinstance:Connectable

endpackage: axi2apb

