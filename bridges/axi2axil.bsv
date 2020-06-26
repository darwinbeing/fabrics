// see LICENSE.incore for more details on licensing terms
/*
Author: Neel Gala, neelgala@incoresemi.com
Created on: Wednesday 08 April 2020 02:24:19 PM IST
*/
/*doc:overview:

This module implements a bridge/adapter which can be used to convert AXI-4 transactions into AXI4L 
(a.k.a AXI4L4, a.k.a AXI4Lv2.0) transactions. This bridges acts as a slave on the AXI4 
interface and as a master on an ABP interface. Both the protocols are little endian.
The bridge is parameterized to handle different address and data sizes of either
side with the following contraints:

1. The AXI4 address size must be greater than or equal to the AXI4L address size.
2. The AXI4 data size must be greater than of equal to the AXI4L data size.
3. The AXI4 data and AXI4L data should both be byte-multiples

The bridge also supports spliting of read/write bursts from the AXI4 side to individual requests on
the AXI4L cluster.

A Connectable instance is also provided which can directly connect an AXI4 master interface to a
AXI4L-slave interface.


Working Principle
-----------------

Since the AXI4L is a single channel bus and the AXI4 has separate read and write channels, the read
requests from the AXI4 are given priority over the write requests occurring in the same cycle. At
any point of time only a single requests (burst read or burst write) are served, and the next
request is picked up only when the AXI4L has responded to all the bursts from the previous requests.

Differing Address sizes
^^^^^^^^^^^^^^^^^^^^^^^

When the AXI4 and AXI4L address sizes are different, then the lower bits of the AXI4 addresses are
used on the AXI4L side. 

Differing Data sizes
^^^^^^^^^^^^^^^^^^^^

When the AXI4 and AXI4L data sizes are different, each single beat of the AXI4 request (read or write)
is split into multiple smaller child bursts (sent as individual AXI4L requests) which matches 
AXI4L data size. A beat is complete only when its corresponding child-bursts are over. The next
single-beat address is generated based on the burst-mode request and the burst size. Thus, the
bridge can support all AXI4 burst-modes: incr, fixed and wrap.

When instantiated with same data-sizes, the child-burst logic is ommitted.

Error mapping
^^^^^^^^^^^^^

The AXI4L PSLVERR is mapped to the AXI4 SLVERR.

.. note::
  Currently the bridge works for the same clock on either side. Multiple clock domain support will
  available in future versions

*/
package axi2axil ;

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
import axi4l        :: * ;

import Semi_FIFOF   :: * ;
`include "Logger.bsv"

typedef enum {Idle, Response} Axi2AxilBridgeState deriving (Bits, FShow, Eq);

function Axi4l_resp fn_update_error (Axi4l_resp curr_err, Axi4l_resp prev_err);
  case (prev_err)
    axi4l_resp_okay: return curr_err;
    axi4l_resp_exokay: return curr_err;
    axi4l_resp_decerr: if(curr_err == axi4l_resp_slverr) return axi4l_resp_slverr;
                       else return axi4l_resp_decerr;
    axi4l_resp_slverr: return axi4l_resp_slverr;
    default: return axi4l_resp_okay;
  endcase
endfunction:fn_update_error

interface Ifc_axi2axil #( numeric type axi_id, 
                          numeric type axi_addr,
                          numeric type axi_data,
                          numeric type axil_addr,
                          numeric type axil_data,
                          numeric type user );
  (*prefix="AXI4"*)
  interface Ifc_axi4_slave   #(axi_id, axi_addr, axi_data, user)   axi4_side;
  (*prefix="AXI4L"*)
  interface Ifc_axi4l_master #(axil_addr, axil_data, user)         axi4l_side;
endinterface:Ifc_axi2axil

module mkaxi2axil(Ifc_axi2axil#(axi_id, axi_addr, axi_data, axil_addr, axil_data, user))
  provisos (Add#(axil_addr, _a, axi_addr), // AXI address cannot be smaller in size than AXI4L
            Add#(axil_data, _b, axi_data),  // both data buses have to be the same
            Div#(axi_data, 8, axi_bytes),
            Mul#(axi_bytes, 8, axi_data),
            Div#(axil_data, 8, axil_bytes),
            Mul#(axil_bytes, 8, axil_data),
            Log#(axil_bytes, lg_axil_bytes),
            Div#(axi_data, axil_data, child_count),
            Add#(d__, axil_bytes, axi_bytes),
            Log#(axi_bytes, axi_byte_size),

            Add#(a__, TDiv#(axil_data, 8), TDiv#(axi_data, 8)), // strbs are also smaller
            Add#(b__, 8, axi_addr),
            Mul#(axil_data, c__, axi_data), // Apb is a byte multiple of axi_data
            Add#(e__, axi_byte_size, axi_addr),
            Add#(f__, axil_bytes, TDiv#(axi_data, 8))
           );

  let v_axi_data = valueOf(axi_data);
  let v_axil_data = valueOf(axil_data);
  let v_child_count = valueOf(child_count);
  let v_axil_bytes = valueOf(axil_bytes);
  let v_axi_bytes = valueOf(axi_bytes);
  let v_bytes_ratio = valueOf(TDiv#(axi_bytes, axil_bytes));
  let v_lg_axil_bytes = valueOf(lg_axil_bytes);
  // -------------------------------------------------------------------------------------------- //
  // instantiate the transactors

  Ifc_axi4l_master_xactor#( axil_addr, axil_data, user) axil_xactor <- mkaxi4l_master_xactor(defaultValue);
  Ifc_axi4_slave_xactor#( axi_id, axi_addr, axi_data, user) axi_xactor <- mkaxi4_slave_xactor(defaultValue);
  // -------------------------------------------------------------------------------------------- //

  /*doc:reg: dictates the state that the bridge is currently in */
  ConfigReg#(Axi2AxilBridgeState)                       rg_rd_state       <- mkConfigReg(Idle);
  /*doc:reg: captures the initial read request from the axi read-channel*/
  Reg#(Axi4_rd_addr #(axi_id, axi_addr, user))          rg_rd_request  <- mkReg(unpack(0));
  /*doc:reg: this register holds the count of the read requests to be sent to the AXI4L*/
  Reg#(Bit#(8))                                         rg_rd_req_beat <- mkReg(0);
  /*doc:reg: this register increments everytime a read-response from the AXI4L is received. Since we
  * can send requests independently of the response, two counters are required.*/
  Reg#(Bit#(8))                                         rg_rd_resp_beat <- mkReg(0);

  /*doc:reg: dictates the state that the bridge is currently in */
  ConfigReg#(Axi2AxilBridgeState)                       rg_wr_state       <- mkConfigReg(Idle);
  /*doc:reg: captures the initial read request from the axi write address-channel*/
  Reg#(Axi4_wr_addr #(axi_id, axi_addr, user))          rg_wr_request  <- mkReg(unpack(0));
  /*doc:reg: captures the initial read request from the axi write data*/
  Reg#(Axi4_wr_data #(axi_data, user))                  rg_wd_request  <- mkReg(unpack(0));
  /*doc:reg: this register holds the count of the read requests to be sent to the AXI4L*/
  Reg#(Bit#(8))                                         rg_wr_req_beat <- mkReg(0);
  /*doc:reg: this register increments everytime a read-response from the AXI4L is received. Since we
  * can send requests independently of the response, two counters are required.*/
  Reg#(Bit#(8))                                         rg_wr_resp_beat <- mkReg(0);
  /*doc:reg: */
  Reg#(Axi4l_resp)                                      rg_accum_err   <- mkReg(axi4l_resp_okay);

  /*doc:reg: this register holds the amount of requests required per axi-beat if the axil-data size
   * is less than the axil-data size. If the size satisfies then this register is set 0. 
   * When the axi-data and axil-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_rd_burst <- mkReg(0);
  /*doc:reg: this register holds the amount of requests required per axi-beat if the axil-data size
   * is less than the axil-data size. If the size satisfies then this register is set 0. 
   * When the axi-data and axil-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_wr_burst <- mkReg(0);

  /*doc:reg: holds the current byte-requests sent to the axil-side for the current axi-beat.
   * When the axi-data and axil-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_rd_req_count <- mkReg(0);
  /*doc:reg: holds the current byte-requests sent to the axil-side for the current axi-beat.
   * When the axi-data and axil-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_wr_req_count <- mkReg(0);

  /*doc:reg: holds the current byte-responses received from the axil-side for the current axi-beat.
   * When the axi-data and axil-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_rd_res_count <- mkReg(0);
  /*doc:reg: holds the current byte-responses received from the axil-side for the current axi-beat.
   * When the axi-data and axil-data sizes are the same, i.e. v_bytes_ratio is 1, this register 
   * is useless*/
  Reg#(Bit#(8))                                         rg_child_wr_res_count <- mkReg(0);

  /*doc:reg: this register is used to accumulate child responses for a single axi-beat and send it
   * as a single axi-response. In case of write-requests this register holds the data to be sent.*/
  Reg#(Bit#(axi_data))                                  rg_accum_data  <- mkReg(0);
  
  /*doc:reg: a mask register used to indicate which bytes of the rg_accum_data need to be updated
   * with the current response from the AXI4L*/
  Reg#(Bit#(axi_bytes))                                 rg_accum_mask  <- mkReg(0);


  /*doc:rule: this rule pops the read request from axi and initiates a request on the AXI4L. This rule
  will also account for the axil-data size being smaller than the request size. In such a case,
  each axi-level beat is split into further child-bursts. The size of the single beat request in
  terms of bytes is stored in the register rg_child_rd_burst. We set the axil-data size in terms of
  bytes in the register rg_child_rd_req_count. This will be used to count the number of child-bursts
  to be sent per axi-beat. Also this register is also used to calculate the address of individual
  child-bursts. When the request-size per axi-beat is more than the axil-data size, then the burst
  count provided by arlen is incremented by 1 and stored in rg_rd_req_beat. This is because,
  child-burst erquests are sent through the same rule and setting it to 0 would prevent that rule
  from the firing. */
  rule rl_read_frm_axi (rg_rd_state == Idle);
    let axi_req <- pop_o(axi_xactor.fifo_side.o_rd_addr);
    Axi4l_rd_addr #(axil_addr, user) axil_request = Axi4l_rd_addr {
                                                                    araddr : truncate(axi_req.araddr),
                                                                    arprot  : axi_req.arprot,
                                                                    aruser : axi_req.aruser};
    axil_xactor.fifo_side.i_rd_addr.enq(axil_request);
    rg_rd_request    <= axi_req;
    rg_rd_state      <= Response;
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Read:",fshow_axi4_rd_addr(axi_req)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Lite-Read  :",fshow_axi4l_rd_addr(axil_request)))
    if (v_bytes_ratio > 1 ) begin
      Bit#(8) request_size = ('b1) << axi_req.arsize;
      Bit#(axil_bytes) mask = '1;
      if(request_size > fromInteger(v_axil_bytes)) begin
        rg_rd_req_beat   <= axi_req.arlen + 1;
        rg_rd_resp_beat   <= axi_req.arlen + 1;
        rg_child_rd_burst <= request_size ;
        rg_child_rd_res_count <= fromInteger(v_axil_bytes);
        rg_child_rd_req_count <= fromInteger(v_axil_bytes);
        rg_accum_mask  <= zeroExtend(mask);
      end
      else begin
        rg_rd_req_beat   <= axi_req.arlen;
        rg_rd_resp_beat   <= axi_req.arlen + 1;
        rg_child_rd_burst <= 0;
        rg_child_rd_req_count <= 0;
        rg_child_rd_res_count <= 0;
        rg_accum_mask <= '1;
      end
    end
    else begin
      rg_rd_req_beat   <= axi_req.arlen;
      rg_rd_resp_beat   <= axi_req.arlen + 1;
      rg_accum_mask <= '1;
    end
  endrule:rl_read_frm_axi
  
  /*doc:rule: this rule will generate new addresses based on burst-mode and lenght and send read 
  requests to the AXI4L. This rule will generate subsequent requests to the axil for a burst request
  from the axi. If the request-size is greater than the axil-data size, then child-bursts for each
  axi-beat is also sent through this rule. In case of the child-bursts, the new childburst address
  is derived by adding the rg_child_rd_req_count to the current beat-address. The beat-address itself
  is generated using the axi-address generator function. When the register rg_child_rd_req_count
  reaches the necessary byte-count then axi-beat count is incremented.*/
  rule rl_send_rd_burst_req(rg_rd_state == Response && rg_rd_req_beat !=0);
    Bit#(axi_addr) new_address = truncate(fn_axi4burst_addr(rg_rd_request.arlen, 
                                                            rg_rd_request.arsize, 
                                                            rg_rd_request.arburst,
                                                            rg_rd_request.araddr));
    if(v_bytes_ratio > 1 && rg_child_rd_req_count != rg_child_rd_burst )begin
      new_address = rg_rd_request.araddr + zeroExtend(rg_child_rd_req_count); 
      rg_child_rd_req_count <= rg_child_rd_req_count + fromInteger(v_axil_bytes);
    end
    else begin
      let next_req = rg_rd_request;
      next_req.araddr = new_address;
      rg_rd_request <= next_req;
      if(v_bytes_ratio > 1 && rg_child_rd_burst != 0)
        rg_child_rd_req_count <= fromInteger(v_axil_bytes);
    end
    if (v_bytes_ratio > 1)begin
      if (rg_child_rd_req_count == (rg_child_rd_burst - fromInteger(v_axil_bytes)) || (rg_child_rd_burst == 0))
        rg_rd_req_beat <= rg_rd_req_beat - 1;
    end
    else
      rg_rd_req_beat <= rg_rd_req_beat - 1;
    Axi4l_rd_addr #(axil_addr, user) axil_request = Axi4l_rd_addr {
                                                                    araddr : truncate(new_address),
                                                                    arprot : rg_rd_request.arprot,
                                                                    aruser : rg_rd_request.aruser};
    axil_xactor.fifo_side.i_rd_addr.enq(axil_request);
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-RdBurst Addr:%h Count:%d",new_address,
        rg_rd_req_beat))
    `logLevel( bridge, 0, $format("Axi2AxiL: New Axi4-Lite-Read  :",fshow_axi4l_rd_addr(axil_request)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Child:%d ChildReq:%d",rg_child_rd_burst,
    rg_child_rd_req_count))
  endrule:rl_send_rd_burst_req

  /*doc:rule: collects read responses from AXI4L and send to AXI. When the axil-data is smaller than
  * the request-size, then the responses from the AXI4L are collated together in a temp register:
  * rg_accum_data. This register is updated with the AXI4L response using a byte mask which is 
  * also maintained as a temp register : rg_accum_mask. The axi-beat response count is incremented
  * each time the required number of child-bursts are complete. Note, here the response beat counter
  * starts with arlen + 1 and terminates on reaching 1 as compared to the request beat counter which
  * starts at arlen. This is because, when a new request is taken that is passed on to the AXI4L in
  * the same cycle, thus one beat count less as compared to response*/
  rule rl_read_response_to_axi(rg_rd_state == Response && rg_rd_resp_beat != 0);
    
    let axil_response <- pop_o(axil_xactor.fifo_side.o_rd_data);
    Bit#(axil_data) _data = axil_response.rdata;
    Bit#(axi_data)  _resp_data = duplicate(_data);
    if (v_bytes_ratio > 1) begin
      _resp_data = updateDataWithMask(rg_accum_data, _resp_data, rg_accum_mask);
      rg_accum_data <= _resp_data;
      rg_accum_mask <= rotateBitsBy(rg_accum_mask, fromInteger(v_axil_bytes));
    end
    Axi4_rd_data #(axi_id, axi_data, user) axi_response = Axi4_rd_data {rid: rg_rd_request.arid,
                                     rdata: _resp_data,
                                     rresp: pack(axil_response.rresp),
                                     ruser: axil_response.ruser,
                                     rlast: rg_rd_resp_beat == 1 };

    if(v_bytes_ratio > 1 && rg_child_rd_res_count != rg_child_rd_burst && rg_child_rd_burst != 0) begin
      `logLevel( bridge, 0, $format("Axi2AxiL: Accumulate"))
      rg_child_rd_res_count <= rg_child_rd_res_count + fromInteger(v_axil_bytes);
    end
    else begin
      rg_rd_resp_beat <= rg_rd_resp_beat - 1;
      axi_xactor.fifo_side.i_rd_data.enq(axi_response);
      `logLevel( bridge, 0, $format("Axi2AxiL: AXI-RdResp:",fshow_axi4_rd_data(axi_response)))
      if(v_bytes_ratio > 1 && rg_child_rd_burst != 0)
        rg_child_rd_res_count <= fromInteger(v_axil_bytes);
    end

    if(rg_rd_resp_beat == 1 && (rg_child_rd_res_count == rg_child_rd_burst || rg_child_rd_burst == 0)) begin
      rg_rd_state <= Idle;
    end
    `logLevel( bridge, 0, $format("Axi2AxiL: AXI4L-Resp: Count:%2d",rg_rd_resp_beat,
    fshow_axi4l_rd_data(axil_response)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Child:%d ChildRes:%d Mask:%b Accum:%h",rg_child_rd_burst,
      rg_child_rd_res_count, rg_accum_mask, rg_accum_data))
  endrule:rl_read_response_to_axi
  
  /*doc:rule: this rule pops the read request from axi and initiates a request on the AXI4L. This rule
  * works exactly similar to rule working of rl_read_frm_axi*/
  rule rl_write_frm_axi (rg_wr_state == Idle);
    let axi_req  <- pop_o(axi_xactor.fifo_side.o_wr_addr);
    let axi_wreq = axi_xactor.fifo_side.o_wr_data.first;
    Bit#(8) request_size = ('b1) << axi_req.awsize;
    Bit#(axi_byte_size) axi4_byte_access = truncate(axi_req.awaddr);
    Bit#(axi_byte_size) axi4_byte_shift = (v_bytes_ratio > 1 && 
                    request_size <= fromInteger(v_axil_bytes) && 
                    axi4_byte_access > fromInteger(v_axil_bytes-1) )? axi4_byte_access : 0;
    Bit#(axil_bytes) axil_wstrb = truncate(axi_wreq.wstrb >> axi4_byte_shift);
    Bit#(axil_data) axil_data_ = truncate(axi_wreq.wdata >> {axi4_byte_shift, 3'b0});
    Axi4l_wr_addr #(axil_addr, user) axil_req = Axi4l_wr_addr {awaddr : truncate(axi_req.awaddr),
                                                               awprot : axi_req.awprot,
                                                               awuser : axi_req.awuser};
    Axi4l_wr_data #(axil_data) axil_req_data = Axi4l_wr_data {wdata   : axil_data_,
                                                              wstrb   : axil_wstrb};
    axil_xactor.fifo_side.i_wr_addr.enq(axil_req);
    axil_xactor.fifo_side.i_wr_data.enq(axil_req_data);
    rg_wr_request    <= axi_req;
    rg_wd_request    <= axi_wreq;
    rg_wr_state      <= Response;
    rg_accum_err     <= axi4_resp_okay;
    if (v_bytes_ratio > 1 ) begin
      Bit#(axil_bytes) mask = '1;
      if(request_size > fromInteger(v_axil_bytes)) begin
        rg_wr_req_beat   <= axi_req.awlen + 1;
        rg_wr_resp_beat   <= axi_req.awlen + 1;
        rg_child_wr_burst <= request_size ;
        rg_child_wr_res_count <= fromInteger(v_axil_bytes);
        rg_child_wr_req_count <= fromInteger(v_axil_bytes);
      end
      else begin
        rg_wr_req_beat   <= axi_req.awlen;
        rg_wr_resp_beat   <= axi_req.awlen + 1;
        rg_child_wr_burst <= 0;
        rg_child_wr_req_count <= 0;
        rg_child_wr_res_count <= 0;
        axi_xactor.fifo_side.o_wr_data.deq;
      end
    end
    else begin
      rg_wr_req_beat   <= axi_req.awlen;
      rg_wr_resp_beat   <= axi_req.awlen + 1;
      axi_xactor.fifo_side.o_wr_data.deq;
    end
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Write:",fshow_axi4_wr_addr(axi_req)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Write: byte_index:%d",axi4_byte_shift, fshow_axi4_wr_data(axi_wreq)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Lite-Write  :",fshow_axi4l_wr_addr(axil_req)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Lite-Write  :",fshow_axi4l_wr_data(axil_req_data)))
  endrule:rl_write_frm_axi
  
  /*doc:rule: this rule will generate new addresses based on burst-mode and lenght and send write
  requests to the AXI4L. This rule behaves exactly like rl_send_rd_burst_req.*/
  rule rl_send_wr_burst_req(rg_wr_state == Response && rg_wr_req_beat !=0);
    let axi_wreq = axi_xactor.fifo_side.o_wr_data.first;
    Bit#(axi_data) _write_data = axi_wreq.wdata;
    Bit#(TDiv#(axi_data,8)) _wstrb = axi_wreq.wstrb;
    let new_address = fn_axi4burst_addr(rg_wr_request.awlen, 
                                        rg_wr_request.awsize, 
                                        rg_wr_request.awburst,
                                        rg_wr_request.awaddr);
    if(v_bytes_ratio > 1 && rg_child_wr_req_count != rg_child_wr_burst )begin
      new_address = rg_wr_request.awaddr + zeroExtend(rg_child_wr_req_count); 
      rg_child_wr_req_count <= rg_child_wr_req_count + fromInteger(v_axil_bytes);
      Bit#(TAdd#(3,8)) shift = {rg_child_wr_req_count,'d0};
      _write_data = _write_data >> shift;
      _wstrb = _wstrb >> rg_child_wr_req_count;
    end
    else begin
      let next_req = rg_wr_request;
      next_req.awaddr = new_address;
      rg_wr_request <= next_req;
      if(v_bytes_ratio > 1 && rg_child_wr_burst != 0)
        rg_child_wr_req_count <= fromInteger(v_axil_bytes);
    end
    if (v_bytes_ratio > 1)begin
      if (rg_child_wr_req_count == (rg_child_wr_burst - fromInteger(v_axil_bytes)) || (rg_child_wr_burst == 0)) begin
        rg_wr_req_beat <= rg_wr_req_beat - 1;
        axi_xactor.fifo_side.o_wr_data.deq;
        `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Wr Poping Wd Request:",
            fshow_axi4_wr_data(axi_wreq)))
      end
    end
    else begin
      rg_wr_req_beat <= rg_wr_req_beat - 1;
      axi_xactor.fifo_side.o_wr_data.deq;
      `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Wr Poping Wd Request:",fshow_axi4_wr_data(axi_wreq)))
    end
    Axi4l_wr_addr #(axil_addr, user) axil_req = Axi4l_wr_addr {awaddr : truncate(new_address),
                                                               awprot : rg_wr_request.awprot,
                                                               awuser : rg_wr_request.awuser};
    Axi4l_wr_data #(axil_data) axil_req_data = Axi4l_wr_data {wdata   : truncate(_write_data),
                                                              wstrb   : truncate(_wstrb)};
    axil_xactor.fifo_side.i_wr_addr.enq(axil_req);
    axil_xactor.fifo_side.i_wr_data.enq(axil_req_data);
    `logLevel( bridge, 0, $format("Axi2AxiL: New Axi4-Write Count:%d:",rg_wr_req_beat,
        fshow_axi4_wr_data(axi_wreq)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Axi4-Lite-Write  :",fshow_axi4l_wr_addr(axil_req)))
    `logLevel( bridge, 0, $format("Axi2AxiL: Child:%d ChildReq:%d",rg_child_wr_burst,
    rg_child_wr_req_count))
  endrule:rl_send_wr_burst_req

  /*doc:rule: collects read responses from AXI4L and send to AXI. This rule behaves similar to
  * rl_read_response_to_axi except for the fact that the response is sent only at the end of
  * completion of all beats*/
  rule rl_write_response_to_axi(rg_wr_state == Response && rg_wr_resp_beat != 0);
    
    let axil_response <- pop_o(axil_xactor.fifo_side.o_wr_resp);
    let _err  = fn_update_error(axil_response.bresp, rg_accum_err);
    rg_accum_err <= _err;
    let axi_response = Axi4_wr_resp {bresp: pack(_err),
                                     buser: axil_response.buser,
                                     bid  : rg_wr_request.awid };
    if(v_bytes_ratio > 1 && rg_child_wr_res_count != rg_child_wr_burst && rg_child_wr_burst != 0) begin
      `logLevel( bridge, 0, $format("Axi2AxiL: Accumulate"))
      rg_child_wr_res_count <= rg_child_wr_res_count + fromInteger(v_axil_bytes);
    end
    else begin
      rg_wr_resp_beat <= rg_wr_resp_beat - 1;
      if(v_bytes_ratio > 1 && rg_child_wr_burst != 0)
        rg_child_wr_res_count <= fromInteger(v_axil_bytes);
    end
    if(rg_wr_resp_beat == 1 && (rg_child_wr_res_count == rg_child_wr_burst || rg_child_wr_burst == 0) ) begin
      axi_xactor.fifo_side.i_wr_resp.enq(axi_response);
      rg_wr_state <= Idle;
    end
    `logLevel( bridge, 0, $format("Axi2AxiL: AXI4L-Resp: Count:%2d",rg_wr_resp_beat, 
        fshow_axi4l_wr_resp(axil_response)))
  endrule:rl_write_response_to_axi

  interface axi4_side = axi_xactor.axi4_side;
  interface axi4l_side = axil_xactor.axi4l_side;

endmodule:mkaxi2axil


instance Connectable #(Ifc_axi4_master #(axi_id, axi_addr, axi_data, user), 
                       Ifc_axi4l_slave #(axil_addr, axil_data, user))
  provisos (Add#(axil_addr, _a, axi_addr), // AXI address cannot be smaller in size than AXI4L
            Add#(axil_data, _b, axi_data),  // both data buses have to be the same
            Div#(axi_data, 8, axi_bytes),
            Mul#(axi_bytes, 8, axi_data),
            Div#(axil_data, 8, axil_bytes),
            Mul#(axil_bytes, 8, axil_data),
            Log#(axil_bytes, lg_axil_bytes),
            Div#(axi_data, axil_data, child_count),
            Add#(d__, axil_bytes, axi_bytes),

            Add#(a__, TDiv#(axil_data, 8), TDiv#(axi_data, 8)), // strbs are also smaller
            Add#(b__, 8, axi_addr),
            Mul#(axil_data, c__, axi_data), // Apb is a byte multiple of axi_data
            Add#(e__, axil_bytes, TDiv#(axi_data, 8)),
            Add#(f__, TLog#(axi_bytes), axi_addr)
          );
  module mkConnection #(Ifc_axi4_master #(axi_id, axi_addr, axi_data, user) axi4_side,
                       Ifc_axi4l_slave #(axil_addr, axil_data, user)         axi4l_side)
                       (Empty);
    Ifc_axi2axil #(axi_id, axi_addr, axi_data, axil_addr, axil_data, user) bridge <- mkaxi2axil;
    mkConnection(axi4_side, bridge.axi4_side);
    mkConnection(axi4l_side, bridge.axi4l_side);
  endmodule:mkConnection
endinstance:Connectable

instance Connectable #(Ifc_axi4l_slave #(axil_addr, axil_data, user),
                       Ifc_axi4_master #(axi_id, axi_addr, axi_data, user) )
  provisos (Add#(axil_addr, _a, axi_addr), // AXI address cannot be smaller in size than AXI4L
            Add#(axil_data, _b, axi_data),  // both data buses have to be the same
            Div#(axi_data, 8, axi_bytes),
            Mul#(axi_bytes, 8, axi_data),
            Div#(axil_data, 8, axil_bytes),
            Mul#(axil_bytes, 8, axil_data),
            Log#(axil_bytes, lg_axil_bytes),
            Div#(axi_data, axil_data, child_count),
            Add#(d__, axil_bytes, axi_bytes),

            Add#(a__, TDiv#(axil_data, 8), TDiv#(axi_data, 8)), // strbs are also smaller
            Add#(b__, 8, axi_addr),
            Mul#(axil_data, c__, axi_data), // Apb is a byte multiple of axi_data
            Add#(e__, axil_bytes, TDiv#(axi_data, 8)),
            Add#(f__, TLog#(axi_bytes), axi_addr)
          );
  module mkConnection #(Ifc_axi4l_slave #(axil_addr, axil_data, user)         axi4l_side,
                        Ifc_axi4_master #(axi_id, axi_addr, axi_data, user) axi4_side )
                       (Empty);
    mkConnection(axi4_side, axi4l_side);
  endmodule:mkConnection
endinstance:Connectable

endpackage: axi2axil

