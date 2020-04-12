###################
Module: axi2apb
###################

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



Library Imports
----------------


 - **Prelude Library Imports**:

   * FIFOF
   * Vector
   * SpecialFIFOs
   * FIFOF
   * DefaultValue
   * ConfigReg
   * Connectable
   * BUtils
   * Assert
   * Memory

 - **Porject Library Imports**:

   * axi4
   * apb
   * Semi_FIFOF

Register Instances
--------------------
* `rg_rd_request <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L128>`_

   - **Data Type**: ``AXI4_rd_addr #(axi_id, axi_addr, user)``
   - **Reset Value**: ``unpack(0)``
   - **Description**:  dictates the state that the bridge is currently in */  ConfigReg#(Axi2ApbBridgeState)                        rg_state       <- mkConfigReg(Idle);  /*doc:reg: captures the initial read request from the axi read-channel

* `rg_req_beat <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L131>`_

   - **Data Type**: ``Bit#(8)``
   - **Reset Value**: ``0``
   - **Description**:  this register holds the count of the read requests to be sent to the APB

* `rg_resp_beat <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L135>`_

   - **Data Type**: ``Bit#(8)``
   - **Reset Value**: ``0``
   - **Description**:  this register increments everytime a read-response from the APB is received. Since we  * can send requests independently of the response, two counters are required.

* `rg_child_burst <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L141>`_

   - **Data Type**: ``Bit#(8)``
   - **Reset Value**: ``0``
   - **Description**:  this register holds the amount of requests required per axi-beat if the apb-data size   * is less than the apb-data size. If the size satisfies then this register is set 0.    * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register    * is useless

* `rg_child_req_count <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L146>`_

   - **Data Type**: ``Bit#(8)``
   - **Reset Value**: ``0``
   - **Description**:  holds the current byte-requests sent to the apb-side for the current axi-beat.   * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register    * is useless

* `rg_child_res_count <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L151>`_

   - **Data Type**: ``Bit#(8)``
   - **Reset Value**: ``0``
   - **Description**:  holds the current byte-responses received from the apb-side for the current axi-beat.   * When the axi-data and apb-data sizes are the same, i.e. v_bytes_ratio is 1, this register    * is useless

* `rg_accum_data <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L155>`_

   - **Data Type**: ``Bit#(axi_data)``
   - **Reset Value**: ``0``
   - **Description**:  this register is used to accumulate child responses for a single axi-beat and send it   * as a single axi-response. In case of write-requests this register holds the data to be sent.

* `rg_accum_mask <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L159>`_

   - **Data Type**: ``Bit#(axi_bytes)``
   - **Reset Value**: ``0``
   - **Description**:  a mask register used to indicate which bytes of the rg_accum_data need to be updated   * with the current response from the APB

* `rg_wr_request <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L162>`_

   - **Data Type**: ``AXI4_wr_addr #(axi_id, axi_addr, user)``
   - **Reset Value**: ``unpack(0)``
   - **Description**:  captures the initial read request from the axi write address-channel

* `rg_wd_request <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L164>`_

   - **Data Type**: ``AXI4_wr_data #(axi_data, user)``
   - **Reset Value**: ``unpack(0)``
   - **Description**:  captures the initial read request from the axi write data

* `rg_accum_err <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L166>`_

   - **Data Type**: ``Bool``
   - **Reset Value**: ``False``
   - **Description**: 

Rule Instances
--------------------
* `rl_read_frm_axi <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L178>`_

   - **Description**: this rule pops the read request from axi and initiates a request on the APB. This rule  will also account for the apb-data size being smaller than the request size. In such a case,  each axi-level beat is split into further child-bursts. The size of the single beat request in  terms of bytes is stored in the register rg_child_burst. We set the apb-data size in terms of  bytes in the register rg_child_req_count. This will be used to count the number of child-bursts  to be sent per axi-beat. Also this register is also used to calculate the address of individual  child-bursts. When the request-size per axi-beat is more than the apb-data size, then the burst  count provided by arlen is incremented by 1 and stored in rg_req_beat. This is because,  child-burst erquests are sent through the same rule and setting it to 0 would prevent that rule  from the firing. 
   - **Blocking Rules/Methods**: (none)
 
   - **Predicate**:

     .. code-block:: 

           axi_xactor_f_rd_addr.i_notEmpty &&
      	   (! apb_xactor_ff_request_rv.port0__read[86]) &&
      	   (rg_state.read == 2'd0)
      


* `rl_send_rd_burst_req <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L226>`_

   - **Description**: this rule will generate new addresses based on burst-mode and lenght and send read   requests to the APB. This rule will generate subsequent requests to the apb for a burst request  from the axi. If the request-size is greater than the apb-data size, then child-bursts for each  axi-beat is also sent through this rule. In case of the child-bursts, the new childburst address  is derived by adding the rg_child_req_count to the current beat-address. The beat-address itself  is generated using the axi-address generator function. When the register rg_child_req_count  reaches the necessary byte-count then axi-beat count is incremented.
   - **Blocking Rules/Methods**: (none)
 
   - **Predicate**:

     .. code-block:: 

           (! apb_xactor_ff_request_rv.port0__read[86]) &&
      	   (rg_state.read == 2'd1) && (! (rg_req_beat == 8'd0))
      


* `rl_read_response_to_axi <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L271>`_

   - **Description**: collects read responses from APB and send to AXI. When the apb-data is smaller than  * the request-size, then the responses from the APB are collated together in a temp register:  * rg_accum_data. This register is updated with the APB response using a byte mask which is   * also maintained as a temp register : rg_accum_mask. The axi-beat response count is incremented  * each time the required number of child-bursts are complete. Note, here the response beat counter  * starts with arlen + 1 and terminates on reaching 1 as compared to the request beat counter which  * starts at arlen. This is because, when a new request is taken that is passed on to the APB in  * the same cycle, thus one beat count less as compared to response
   - **Blocking Rules/Methods**: (none)
 
   - **Predicate**:

     .. code-block:: 

           apb_xactor_ff_response.i_notEmpty &&
      	   axi_xactor_f_rd_data.i_notFull &&
      	   (rg_state.read == 2'd1) && (! (rg_resp_beat == 8'd0))
      


* `rl_write_frm_axi <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L309>`_

   - **Description**: this rule pops the read request from axi and initiates a request on the APB. This rule  * works exactly similar to rule working of rl_read_frm_axi
   - **Blocking Rules/Methods**: rl_read_frm_axi
 
   - **Predicate**:

     .. code-block:: 

           (! apb_xactor_ff_request_rv.port0__read[86]) &&
      	   axi_xactor_f_wr_addr.i_notEmpty &&
      	   axi_xactor_f_wr_data.i_notEmpty &&
      	   (rg_state.read == 2'd0)
      


* `rl_send_wr_burst_req <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L357>`_

   - **Description**: this rule will generate new addresses based on burst-mode and lenght and send write  requests to the APB. This rule behaves exactly like rl_send_rd_burst_req.
   - **Blocking Rules/Methods**: (none)
 
   - **Predicate**:

     .. code-block:: 

           (! apb_xactor_ff_request_rv.port0__read[86]) &&
      	   axi_xactor_f_wr_data.i_notEmpty &&
      	   (rg_state.read == 2'd2) && (! (rg_req_beat == 8'd0))
      


* `rl_write_response_to_axi <https://gitlab.com/incoresemi/uncore/fabrics/-/blob/master/bridges/axi2apb.bsv#L410>`_

   - **Description**: collects read responses from APB and send to AXI. This rule behaves similar to  * rl_read_response_to_axi except for the fact that the response is sent only at the end of  * completion of all beats
   - **Blocking Rules/Methods**: (none)
 
   - **Predicate**:

     .. code-block:: 

           apb_xactor_ff_response.i_notEmpty &&
      	   axi_xactor_f_wr_resp.i_notFull &&
      	   (rg_state.read == 2'd2) && (! (rg_resp_beat == 8'd0))
      

