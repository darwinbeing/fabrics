// Copyright (c) 2013-2019 Bluespec, Inc. see LICENSE.bluespec for details.
// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package axi4_fabric;

// ----------------------------------------------------------------
// This package defines a fabric connecting CPUs, Memories and DMAs
// and other IP blocks.

// ----------------------------------------------------------------
// Bluespec library imports

import Vector       :: *;
import FIFOF        :: *;
import SpecialFIFOs :: *;
import ConfigReg    :: *;
import DefaultValue :: * ;

// ----------------------------------------------------------------
// Project imports

import Semi_FIFOF :: *;
import axi4_types :: *;

`include "Logger.bsv"

// ----------------------------------------------------------------
// The interface for the fabric module

interface Ifc_axi4_fabric #(numeric type tn_num_masters,
			                      numeric type tn_num_slaves,
			                      numeric type wd_id,
			                      numeric type wd_addr,
			                      numeric type wd_data,
			                      numeric type wd_user);
   // From masters
   (*prefix="frm_master"*)
   interface Vector #(tn_num_masters, Ifc_axi4_slave #(wd_id, wd_addr, wd_data, wd_user))  
                                                                                    v_from_masters;

   // To slaves
   (*prefix="to_slave"*)
   interface Vector #(tn_num_slaves,  Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user)) 
                                                                                    v_to_slaves;
endinterface:Ifc_axi4_fabric


function Vector#(n, Bool) fn_rr_arbiter(Vector#(n, Bool) requests, Bit#(TLog#(n)) lowpriority);
   let nports = valueOf(n);
   
   function f(bspg,b);
      match {.bs, .p, .going} = bspg;
      if (going) begin
	 if (b) return tuple3(1 << p, ?, False);
	 else   return tuple3(0, (p == fromInteger(nports-1) ? 0 : p+1), True);
      end
      else return tuple3(bs, ?, False);
   endfunction
   
   match {.bits, .*, .* } = foldl(f, tuple3(?, lowpriority, True), reverse(rotateBy(reverse(requests), unpack(lowpriority))));
   return unpack(bits);
endfunction
// ----------------------------------------------------------------
// The Fabric module

// the reason for having two memory map functions is to avoid creating redundant connections on the
// for read-only and write-only devices. The connections could have been avoided using a simple
// read and write mask, but then a non-existent connection should end up at the err-slave which
// would not be possible bu using masks. 
module mkaxi4_fabric #(
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_rd_memory_map (Bit #(wd_addr) addr), 
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_wr_memory_map (Bit #(wd_addr) addr),
    parameter Bit#(tn_num_slaves)  read_slave,
    parameter Bit#(tn_num_slaves)  write_slave,
    parameter Bit#(tn_num_masters) fixed_priority_rd,
    parameter Bit#(tn_num_masters) fixed_priority_wr
    )
		(Ifc_axi4_fabric #(tn_num_masters, tn_num_slaves, wd_id, wd_addr, wd_data, wd_user))

  provisos ( Max #(TLog #(tn_num_masters) , 1, log_nm),
             Max #(TLog #(tn_num_slaves)  , 1 ,log_ns) 
           );

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  // Transactors facing masters
  Vector #(tn_num_masters, Ifc_axi4_slave_xactor  #(wd_id, wd_addr, wd_data, wd_user))
  xactors_from_masters <- replicateM (mkaxi4_slave_xactor(defaultValue));

  // Transactors facing slaves
  Vector #(tn_num_slaves,  Ifc_axi4_master_xactor #(wd_id, wd_addr, wd_data, wd_user))
  xactors_to_slaves <- replicateM (mkaxi4_master_xactor(defaultValue));


  // ----------------
  // Write-transaction book-keeping

  // On an mi->sj write-transaction, this fifo records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                 f_s_wr_route_info <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records mi for slave sj
  Vector #(tn_num_slaves,  FIFOF #(Bit #(log_nm))) f_m_wr_route_info  <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records a task (sj) for W channel
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
      f_s_wd_route_info <- replicateM (mkSizedBypassFIFOF(2));
  Vector #(tn_num_slaves, FIFOF #(Bit #(log_nm))) 
      f_m_wd_route_info <- replicateM (mkSizedBypassFIFOF(2));

  // ----------------
  // Read-transaction book-keeping

  // On an mi->sj read-transaction, records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                     f_s_rd_route_info <- replicateM (mkSizedFIFOF (8));
  // On an mi->sj read-transaction, records (mi,arlen) for slave sj
  Vector #(tn_num_slaves, FIFOF #(Bit #(log_nm)))    f_m_rd_route_info <- replicateM (mkSizedFIFOF (8));

  /*doc:reg: round robin counter for read requests*/
  Vector #(tn_num_slaves, Reg#(Bit#(TLog#(tn_num_masters)))) rg_rd_master_select
                                                              <- replicateM(mkReg(0));

  /*doc:vec: vector of wires indicating which slave is a read-master trying to lock*/
  Vector#(tn_num_masters, Wire#(Bit#(tn_num_slaves))) wr_master_rd_reqs <- replicateM(mkDWire(0));
  /*doc:vec: a matrix of wires indicating which read-master has been granted permission to access which
   * slave */
  Vector#(tn_num_slaves , Vector#(tn_num_masters, Wire#(Bool))) wr_rd_grant 
                                                        <- replicateM(replicateM(mkDWire(True)));
  /*doc:reg: round robin counter for read requests*/
  Vector #(tn_num_slaves, Reg#(Bit#(TLog#(tn_num_masters)))) rg_wr_master_select
                                                              <- replicateM(mkReg(0));

  /*doc:vec: vector of wires indicating which slave is a write-master trying to lock*/
  Vector#(tn_num_masters, Wire#(Bit#(tn_num_slaves))) wr_master_wr_reqs <- replicateM(mkDWire(0));
  /*doc:vec: a matrix of wires indicating which write-master has been granted permission to access which
   * slave */
  Vector#(tn_num_slaves , Vector#(tn_num_masters, Wire#(Bool))) wr_wr_grant 
                                                        <- replicateM(replicateM(mkDWire(True)));
  // ----------------------------------------------------------------
  // BEHAVIOR

  // ----------------------------------------------------------------
  // Predicates to check if master I has transaction for slave J

  function Bool fv_mi_has_wr_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
    let slave_num  = fn_wr_memory_map (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_wr_for_sj

  function Bool fv_mi_has_rd_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
    let slave_num  = fn_rd_memory_map (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_rd_for_sj

  for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
    /*doc:rule: this rule will update a vector for each master making a read-request to indicate
     * which slave is being targetted*/
    rule rl_capture_rd_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
      _t[fn_rd_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_rd_addr.notEmpty) begin
        wr_master_rd_reqs[mi]    <= _t;
      end
    endrule:rl_capture_rd_slave_contention
    /*doc:rule: this rule will update a vector for each master making a write-request to indicate
     * which slave is being targetted*/
    rule rl_capture_wr_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
      _t[fn_wr_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_wr_addr.notEmpty) begin
        wr_master_wr_reqs[mi]    <= _t;
      end
    endrule:rl_capture_wr_slave_contention
  end

  /*doc:rule: This rule will resolve read contentions per slave using a round-robin arbitration policy*/
  rule rl_rd_round_robin_arbiter (&fixed_priority_rd == 0);
    Vector#(tn_num_masters, Vector#(tn_num_slaves,Bool)) _t = unpack(0);
    for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
      _t[mi] = unpack(wr_master_rd_reqs[mi]);
    end
    let trans = transpose(_t);
    for (Integer i = 0; i< num_slaves; i = i + 1) begin
      let _n = fn_rr_arbiter(trans[i], rg_rd_master_select[i]);
      for (Integer j = 0; j< num_masters; j = j + 1) begin
        wr_rd_grant[i][j] <= _n[j] || unpack(fixed_priority_rd[j]);
      end
    end
  endrule:rl_rd_round_robin_arbiter
  
  /*doc:rule: This rule will resolve write contentions per slave using a round-robin arbitration policy*/
  rule rl_wr_round_robin_arbiter (&fixed_priority_wr == 0);
    Vector#(tn_num_masters, Vector#(tn_num_slaves,Bool)) _t = unpack(0);
    for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
      _t[mi] = unpack(wr_master_wr_reqs[mi]);
    end
    let trans = transpose(_t);
    for (Integer i = 0; i< num_slaves; i = i + 1) begin
      let _n = fn_rr_arbiter(trans[i], rg_wr_master_select[i]);
      for (Integer j = 0; j< num_masters; j = j + 1) begin
        wr_wr_grant[i][j] <= _n[j] || unpack(fixed_priority_wr[j]);
      end
    end
  endrule:rl_wr_round_robin_arbiter

  // ================================================================
  // Wr requests (AW, W and B channels)

  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves ; sj = sj + 1)
    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj) && wr_wr_grant[sj][mi] && 
    	                                    write_slave[sj] == 1 );
    	  // Move the AW transaction
    	  Axi4_wr_addr #(wd_id, wd_addr, wd_user) 
    	      a <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_addr);
    	  xactors_to_slaves [sj].fifo_side.i_wr_addr.enq (a);
    
    	  // Enqueue a task for the W channel
    	  f_s_wd_route_info   [mi].enq (fromInteger (sj));
    	  f_m_wd_route_info   [sj].enq (fromInteger (mi));
    
    	  // Book-keeping
    	  f_m_wr_route_info        [sj].enq (fromInteger (mi));
    	  f_s_wr_route_info        [mi].enq (fromInteger (sj));
	      if (&fixed_priority_wr == 0) begin
  	      if (mi == num_masters - 1)
	          rg_wr_master_select[sj] <= 0;
	        else
	          rg_wr_master_select[sj] <= fromInteger(mi+1);
	      end
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
    	  `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (a) ))
    	endrule:rl_wr_xaction_master_to_slave

  // Wr data (W channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    // Handle W channel burst
    // Note: awlen is encoded as 0..255 for burst lengths of 1..256
    rule rl_wr_xaction_master_to_slave_data (   f_s_wd_route_info [mi].first == fromInteger(sj) 
                                              && f_m_wd_route_info [sj].first == fromInteger(mi)
                                              && write_slave[sj] == 1 );
      
      Axi4_wr_data #(wd_data, wd_user) d <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_data);

      // If sj is a legal slave, send it the data beat, else drop it.
      xactors_to_slaves [sj].fifo_side.i_wr_data.enq (d);
      `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
    	`logLevel( fabric, 0, $format("FABRIC: WRD: ",fshow (d) ))
      
      if ( d.wlast ) begin
        // End of burst
        f_s_wd_route_info [mi].deq;
        f_m_wd_route_info [sj].deq;
      end
   endrule:rl_wr_xaction_master_to_slave_data

  // Wr responses from slaves to masters (B channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves ; sj = sj + 1)
    	rule rl_wr_resp_slave_to_master (   (f_m_wr_route_info [sj].first == fromInteger (mi)) &&
                                  	 	    (f_s_wr_route_info [mi].first == fromInteger (sj)) && write_slave[sj] == 1 );
	      f_m_wr_route_info [sj].deq;
	      f_s_wr_route_info [mi].deq;
	      Axi4_wr_resp #(wd_id, wd_user) b <- pop_o (xactors_to_slaves [sj].fifo_side.o_wr_resp);

	      xactors_from_masters [mi].fifo_side.i_wr_resp.enq (b);
        `logLevel( fabric, 0, $format("FABRIC: WRB: slave[%2d] -> master[%2d]",sj, mi))
        `logLevel( fabric, 0, $format("FABRIC: WRB: ", fshow(b)))
	    endrule:rl_wr_resp_slave_to_master

  // ================================================================
  // Rd requests (AR and R channels)

  // Rd requests to legal slaves (AR channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves ; sj = sj + 1)
      rule rl_rd_xaction_master_to_slave (fv_mi_has_rd_for_sj (mi, sj) && wr_rd_grant[sj][mi] && read_slave[sj] == 1 );
	      
	      Axi4_rd_addr #(wd_id, wd_addr, wd_user) 
	          a <- pop_o (xactors_from_masters [mi].fifo_side.o_rd_addr);
	      xactors_to_slaves [sj].fifo_side.i_rd_addr.enq (a);
	      f_m_rd_route_info [sj].enq (fromInteger (mi));
	      f_s_rd_route_info [mi].enq (fromInteger (sj));
	      `logLevel( fabric, 0, $format("FABRIC: RDA: master[%2d] -> slave[%2d]",mi, sj))
	      `logLevel( fabric, 0, $format("FABRIC: RDA: ", fshow(a)))
	      if (&fixed_priority_rd == 0) begin
  	      if (mi == num_masters - 1)
	          rg_rd_master_select[sj] <= 0;
	        else
	          rg_rd_master_select[sj] <= fromInteger(mi+1);
	      end
	    endrule: rl_rd_xaction_master_to_slave

  // Rd responses from slaves to masters (R channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)

	    rule rl_rd_resp_slave_to_master (f_m_rd_route_info [sj].first == fromInteger (mi) &&
                              	 			(f_s_rd_route_info [mi].first == fromInteger (sj)) && read_slave[sj] == 1  );

	      Axi4_rd_data #(wd_id, wd_data, wd_user) 
	          r <- pop_o (xactors_to_slaves [sj].fifo_side.o_rd_data);

	      if ( r.rlast ) begin
	        // Final beat of burst
	        f_m_rd_route_info [sj].deq;
	        f_s_rd_route_info [mi].deq;
        end
        xactors_from_masters [mi].fifo_side.i_rd_data.enq (r);
	      `logLevel( fabric, 0, $format("FABRIC: RDR: slave[%2d] -> master[%2d]", sj, mi))
	      `logLevel( fabric, 0, $format("FABRIC: RDR: ", fshow(r) ))

	    endrule:rl_rd_resp_slave_to_master

  // ----------------------------------------------------------------
  // INTERFACE

  function Ifc_axi4_slave  #(wd_id, wd_addr, wd_data, wd_user) f1 (Integer j)
     = xactors_from_masters [j].axi4_side;
  function Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user) f2 (Integer j)
     = xactors_to_slaves    [j].axi4_side;

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule

module mkaxi4_fabric_2 #(
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_rd_memory_map (Bit #(wd_addr) addr), 
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_wr_memory_map (Bit #(wd_addr) addr),
    parameter Bit#(tn_num_slaves)  read_slave,
    parameter Bit#(tn_num_slaves)  write_slave,
    parameter Bit#(tn_num_masters) fixed_priority_rd,
    parameter Bit#(tn_num_masters) fixed_priority_wr
    )
		(Ifc_axi4_fabric #(tn_num_masters, tn_num_slaves, wd_id, wd_addr, wd_data, wd_user))

  provisos ( Max #(TLog #(tn_num_masters) , 1, log_nm),
             Max #(TLog #(tn_num_slaves)  , 1 ,log_ns) 
           );

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  // Transactors facing masters
  Vector #(tn_num_masters, Ifc_axi4_slave_xactor  #(wd_id, wd_addr, wd_data, wd_user))
  xactors_from_masters <- replicateM (mkaxi4_slave_xactor_2);

  // Transactors facing slaves
  Vector #(tn_num_slaves,  Ifc_axi4_master_xactor #(wd_id, wd_addr, wd_data, wd_user))
  xactors_to_slaves <- replicateM (mkaxi4_master_xactor_2);


  // ----------------
  // Write-transaction book-keeping

  // On an mi->sj write-transaction, this fifo records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                 f_s_wr_route_info <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records mi for slave sj
  Vector #(tn_num_slaves,  FIFOF #(Bit #(log_nm))) f_m_wr_route_info  <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records a task (sj) for W channel
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
      f_s_wd_route_info <- replicateM (mkSizedBypassFIFOF(2));
  Vector #(tn_num_slaves, FIFOF #(Bit #(log_nm))) 
      f_m_wd_route_info <- replicateM (mkSizedBypassFIFOF(2));

  // ----------------
  // Read-transaction book-keeping

  // On an mi->sj read-transaction, records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                     f_s_rd_route_info <- replicateM (mkSizedFIFOF (8));
  // On an mi->sj read-transaction, records (mi,arlen) for slave sj
  Vector #(tn_num_slaves, FIFOF #(Bit #(log_nm)))    f_m_rd_route_info <- replicateM (mkSizedFIFOF (8));

  /*doc:reg: round robin counter for read requests*/
  Vector #(tn_num_slaves, Reg#(Bit#(TLog#(tn_num_masters)))) rg_rd_master_select
                                                              <- replicateM(mkReg(0));

  /*doc:vec: vector of wires indicating which slave is a read-master trying to lock*/
  Vector#(tn_num_masters, Wire#(Bit#(tn_num_slaves))) wr_master_rd_reqs <- replicateM(mkDWire(0));
  /*doc:vec: a matrix of wires indicating which read-master has been granted permission to access which
   * slave */
  Vector#(tn_num_slaves , Vector#(tn_num_masters, Wire#(Bool))) wr_rd_grant 
                                                        <- replicateM(replicateM(mkDWire(True)));
  /*doc:reg: round robin counter for read requests*/
  Vector #(tn_num_slaves, Reg#(Bit#(TLog#(tn_num_masters)))) rg_wr_master_select
                                                              <- replicateM(mkReg(0));

  /*doc:vec: vector of wires indicating which slave is a write-master trying to lock*/
  Vector#(tn_num_masters, Wire#(Bit#(tn_num_slaves))) wr_master_wr_reqs <- replicateM(mkDWire(0));
  /*doc:vec: a matrix of wires indicating which write-master has been granted permission to access which
   * slave */
  Vector#(tn_num_slaves , Vector#(tn_num_masters, Wire#(Bool))) wr_wr_grant 
                                                        <- replicateM(replicateM(mkDWire(True)));
  // ----------------------------------------------------------------
  // BEHAVIOR

  // ----------------------------------------------------------------
  // Predicates to check if master I has transaction for slave J

  function Bool fv_mi_has_wr_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
    let slave_num  = fn_wr_memory_map(addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_wr_for_sj

  function Bool fv_mi_has_rd_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
    let slave_num  = fn_rd_memory_map(addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_rd_for_sj

  for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
    /*doc:rule: this rule will update a vector for each master making a read-request to indicate
     * which slave is being targetted*/
    rule rl_capture_rd_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
      _t[fn_rd_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_rd_addr.notEmpty) begin
        wr_master_rd_reqs[mi]    <= _t;
      end
    endrule:rl_capture_rd_slave_contention
    /*doc:rule: this rule will update a vector for each master making a write-request to indicate
     * which slave is being targetted*/
    rule rl_capture_wr_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
      _t[fn_wr_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_wr_addr.notEmpty) begin
        wr_master_wr_reqs[mi]    <= _t;
      end
    endrule:rl_capture_wr_slave_contention
  end

  /*doc:rule: This rule will resolve read contentions per slave using a round-robin arbitration policy*/
  rule rl_rd_round_robin_arbiter (&fixed_priority_rd == 1);
    Vector#(tn_num_masters, Vector#(tn_num_slaves,Bool)) _t = unpack(0);
    for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
      _t[mi] = unpack(wr_master_rd_reqs[mi]);
    end
    let trans = transpose(_t);
    for (Integer i = 0; i< num_slaves; i = i + 1) begin
      let _n = fn_rr_arbiter(trans[i], rg_rd_master_select[i]);
      for (Integer j = 0; j< num_masters; j = j + 1) begin
        wr_rd_grant[i][j] <= _n[j] || unpack(fixed_priority_rd[j]);
      end
    end
  endrule:rl_rd_round_robin_arbiter
  
  /*doc:rule: This rule will resolve write contentions per slave using a round-robin arbitration policy*/
  rule rl_wr_round_robin_arbiter (&fixed_priority_wr == 1);
    Vector#(tn_num_masters, Vector#(tn_num_slaves,Bool)) _t = unpack(0);
    for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
      _t[mi] = unpack(wr_master_wr_reqs[mi]);
    end
    let trans = transpose(_t);
    for (Integer i = 0; i< num_slaves; i = i + 1) begin
      let _n = fn_rr_arbiter(trans[i], rg_wr_master_select[i]);
      for (Integer j = 0; j< num_masters; j = j + 1) begin
        wr_wr_grant[i][j] <= _n[j] || unpack(fixed_priority_wr[j]);
      end
    end
  endrule:rl_wr_round_robin_arbiter


  // ================================================================
  // Wr requests (AW, W and B channels)

  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj) && wr_wr_grant[sj][mi] && 
    	                                    write_slave[sj] == 1 );
    	  // Move the AW transaction
    	  Axi4_wr_addr #(wd_id, wd_addr, wd_user) 
    	      a <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_addr);
    	  xactors_to_slaves [sj].fifo_side.i_wr_addr.enq (a);
    
    	  // Enqueue a task for the W channel
    	  f_s_wd_route_info      [mi].enq (fromInteger (sj));
    	  f_m_wd_route_info      [sj].enq (fromInteger (mi));
    
    	  // Book-keeping
    	  f_m_wr_route_info        [sj].enq (fromInteger (mi));
    	  f_s_wr_route_info        [mi].enq (fromInteger (sj));
	      
	      if (&fixed_priority_wr == 0) begin
  	      if (mi == num_masters - 1)
	          rg_wr_master_select[sj] <= 0;
	        else
	          rg_wr_master_select[sj] <= fromInteger(mi+1);
	      end
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
    	  `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (a) ))
    	endrule:rl_wr_xaction_master_to_slave

  // Wr data (W channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    // Handle W channel burst
    // Note: awlen is encoded as 0..255 for burst lengths of 1..256
    rule rl_wr_xaction_master_to_slave_data (   f_s_wd_route_info [mi].first == fromInteger(sj)
                                              && f_m_wd_route_info [sj].first == fromInteger(mi)
                                              && write_slave[sj] == 1 );
      
      Axi4_wr_data #(wd_data, wd_user) d <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_data);

      // If sj is a legal slave, send it the data beat, else drop it.
      xactors_to_slaves [sj].fifo_side.i_wr_data.enq (d);
      `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
    	`logLevel( fabric, 0, $format("FABRIC: WRD: ",fshow (d) ))
      
      if ( d.wlast ) begin
        // End of burst
        f_s_wd_route_info [mi].deq;
        f_m_wd_route_info [sj].deq;
      end
   endrule:rl_wr_xaction_master_to_slave_data

  // Wr responses from slaves to masters (B channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_resp_slave_to_master (   (f_m_wr_route_info [sj].first == fromInteger (mi)) &&
	 	                             		      (f_s_wr_route_info [mi].first == fromInteger (sj)) &&
	 	                             		      write_slave[sj] == 1);
	      f_m_wr_route_info [sj].deq;
	      f_s_wr_route_info [mi].deq;
	      Axi4_wr_resp #(wd_id, wd_user) b <- pop_o (xactors_to_slaves [sj].fifo_side.o_wr_resp);

	      xactors_from_masters [mi].fifo_side.i_wr_resp.enq (b);
        `logLevel( fabric, 0, $format("FABRIC: WRB: slave[%2d] -> master[%2d]",sj, mi))
        `logLevel( fabric, 0, $format("FABRIC: WRB: ", fshow(b)))
	    endrule:rl_wr_resp_slave_to_master

  // ================================================================
  // Rd requests (AR and R channels)

  // Rd requests to legal slaves (AR channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
      rule rl_rd_xaction_master_to_slave (fv_mi_has_rd_for_sj (mi, sj) && wr_rd_grant[sj][mi] && read_slave[sj] == 1 );
	      
	      Axi4_rd_addr #(wd_id, wd_addr, wd_user) 
	          a <- pop_o (xactors_from_masters [mi].fifo_side.o_rd_addr);
	      xactors_to_slaves [sj].fifo_side.i_rd_addr.enq (a);
	      f_m_rd_route_info [sj].enq (fromInteger (mi));
	      f_s_rd_route_info [mi].enq (fromInteger (sj));
	      if (&fixed_priority_rd == 0) begin
  	      if (mi == num_masters - 1)
	          rg_rd_master_select[sj] <= 0;
	        else
	          rg_rd_master_select[sj] <= fromInteger(mi+1);
	      end
	      `logLevel( fabric, 0, $format("FABRIC: RDA: master[%2d] -> slave[%2d]",mi, sj))
	      `logLevel( fabric, 0, $format("FABRIC: RDA: ", fshow(a)))
	    endrule: rl_rd_xaction_master_to_slave

  // Rd responses from slaves to masters (R channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)

	    rule rl_rd_resp_slave_to_master (f_m_rd_route_info [sj].first == fromInteger (mi) &&
	 			                              (f_s_rd_route_info [mi].first == fromInteger (sj))&& 
	 			                               read_slave[sj] == 1);

	      Axi4_rd_data #(wd_id, wd_data, wd_user) 
	          r <- pop_o (xactors_to_slaves [sj].fifo_side.o_rd_data);

	      if ( r.rlast ) begin
	        // Final beat of burst
	        f_m_rd_route_info [sj].deq;
	        f_s_rd_route_info [mi].deq;
        end
        xactors_from_masters [mi].fifo_side.i_rd_data.enq (r);
	      `logLevel( fabric, 0, $format("FABRIC: RDR: slave[%2d] -> master[%2d]", sj, mi))
	      `logLevel( fabric, 0, $format("FABRIC: RDR: ", fshow(r) ))

	    endrule:rl_rd_resp_slave_to_master

  // ----------------------------------------------------------------
  // INTERFACE

  function Ifc_axi4_slave  #(wd_id, wd_addr, wd_data, wd_user) f1 (Integer j)
     = xactors_from_masters [j].axi4_side;
  function Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user) f2 (Integer j)
     = xactors_to_slaves    [j].axi4_side;

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule:mkaxi4_fabric_2
// ----------------------------------------------------------------

// module for adding support for reordering requests

`define n =8; // size of arid list
`define m =8; // depth of each arid fifo

module mkaxi4_fabric_3 #(
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_rd_memory_map (Bit #(wd_addr) addr), 
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_wr_memory_map (Bit #(wd_addr) addr),
    parameter Bit#(tn_num_slaves)  read_slave,
    parameter Bit#(tn_num_slaves)  write_slave,
    parameter Bit#(tn_num_masters) fixed_priority_rd,
    parameter Bit#(tn_num_masters) fixed_priority_wr
    )
		(Ifc_axi4_fabric #(tn_num_masters, tn_num_slaves, wd_id, wd_addr, wd_data, wd_user))

  provisos ( Max #(TLog #(tn_num_masters) , 1, log_nm),
             Max #(TLog #(tn_num_slaves)  , 1 ,log_ns) 
           );

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  // Transactors facing masters
  Vector #(tn_num_masters, Ifc_axi4_slave_xactor  #(wd_id, wd_addr, wd_data, wd_user))
  xactors_from_masters <- replicateM (mkaxi4_slave_xactor_2);

  // Transactors facing slaves
  Vector #(tn_num_slaves,  Ifc_axi4_master_xactor #(wd_id, wd_addr, wd_data, wd_user))
  xactors_to_slaves <- replicateM (mkaxi4_master_xactor_2);
  
  // For interleving the data and reordering the requests 
  
  // read transaction
  // FIFOS to keep the record of slaves which are transacting on same arid
  Vector#(tn_num_masters,Vector#(n,FIFOF #(Bit #(log_ns)))) ff_sids_of_arid <- replicateM(replicateM (mkSizedFIFOF (8)));
  
  // record of currently utilized arids
  Vector#(tn_num_masters,Vector#(n,Reg#(Bit #(wd_id)))) rg_rd_arid_in_flight <- replicateM(replicateM(mkReg(0)));
  
  // record of available space for arids
  Vector#(tn_num_masters,Vector#(n,Reg#(Bit #(TLog #(n))))) rg_rd_free_arids <- replicateM(replicateM(mkReg(0)));

  // ----------------
  // Write-transaction book-keeping

  // On an mi->sj write-transaction, this fifo records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                 f_s_wr_route_info <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records mi for slave sj
  Vector #(tn_num_slaves,  FIFOF #(Bit #(log_nm))) f_m_wr_route_info  <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records a task (sj) for W channel
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
      f_s_wd_route_info <- replicateM (mkSizedBypassFIFOF(2));
  Vector #(tn_num_slaves, FIFOF #(Bit #(log_nm))) 
      f_m_wd_route_info <- replicateM (mkSizedBypassFIFOF(2));

  // ----------------
  // Read-transaction book-keeping

  // On an mi->sj read-transaction, records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns)))   f_s_rd_route_info <- replicateM (mkSizedFIFOF (8));
  
  // On an mi->sj read-transaction, records (mi,arlen) for slave sj
  Vector #(tn_num_slaves, FIFOF #(Bit #(log_nm)))    f_m_rd_route_info <- replicateM (mkSizedFIFOF (8));

  /*doc:reg: round robin counter for read requests*/
  Vector #(tn_num_slaves, Reg#(Bit#(TLog#(tn_num_masters)))) rg_rd_master_select
                                                              <- replicateM(mkReg(0));

  /*doc:vec: vector of wires indicating which slave is a read-master trying to lock*/
  Vector#(tn_num_masters, Wire#(Bit#(tn_num_slaves))) wr_master_rd_reqs <- replicateM(mkDWire(0));
  /*doc:vec: a matrix of wires indicating which read-master has been granted permission to access which
   * slave */
  Vector#(tn_num_slaves , Vector#(tn_num_masters, Wire#(Bool))) wr_rd_grant 
                                                        <- replicateM(replicateM(mkDWire(True)));
  /*doc:reg: round robin counter for read requests*/
  Vector #(tn_num_slaves, Reg#(Bit#(TLog#(tn_num_masters)))) rg_wr_master_select
                                                              <- replicateM(mkReg(0));

  /*doc:vec: vector of wires indicating which slave is a write-master trying to lock*/
  Vector#(tn_num_masters, Wire#(Bit#(tn_num_slaves))) wr_master_wr_reqs <- replicateM(mkDWire(0));
  /*doc:vec: a matrix of wires indicating which write-master has been granted permission to access which
   * slave */
  Vector#(tn_num_slaves , Vector#(tn_num_masters, Wire#(Bool))) wr_wr_grant 
                                                        <- replicateM(replicateM(mkDWire(True)));
  // ----------------------------------------------------------------
  // BEHAVIOR

  // ----------------------------------------------------------------
  // a struct type for returning the arid information from arid list
  typedef struct{
  	Bit#(TMax#(TLog #(n)),1) index;
  	Bool 			  valid;
  } Valid_arid deriving(Bits , FShow);
  
  // function to search the given arid in the list of arids in flight
  function Valid_arid fn_is_arid_inflight(Bit#(wd_id) arid, Integer mi);
    for(Integer i = 0; i < n; i = i + 1) begin
      if(arid == rg_rd_arid_in_flight[mi][i])
        return(Valid_arid {index: fromInteger(i),valid : True});
    end
    return(Valid_arid {index: 0,valid : False});
  endfunction:fn_is_arid_inflight
  
  // ----------------------------------------------------------------
  // Predicates to check if master I has transaction for slave J

  function Bool fv_mi_has_wr_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
    let slave_num  = fn_wr_memory_map(addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_wr_for_sj

  function Bool fv_mi_has_rd_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
    let slave_num  = fn_rd_memory_map(addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_rd_for_sj
  
  for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
    /*doc:rule: this rule will update a vector for each master making a read-request to indicate
     * which slave is being targetted*/
    rule rl_capture_rd_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
      _t[fn_rd_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_rd_addr.notEmpty) begin
        wr_master_rd_reqs[mi]    <= _t;
      end
    endrule:rl_capture_rd_slave_contention
    /*doc:rule: this rule will update a vector for each master making a write-request to indicate
     * which slave is being targetted*/
    rule rl_capture_wr_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
      _t[fn_wr_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_wr_addr.notEmpty) begin
        wr_master_wr_reqs[mi]    <= _t;
      end
    endrule:rl_capture_wr_slave_contention
  end

  /*doc:rule: This rule will resolve read contentions per slave using a round-robin arbitration policy*/
  rule rl_rd_round_robin_arbiter (&fixed_priority_rd == 1);
    Vector#(tn_num_masters, Vector#(tn_num_slaves,Bool)) _t = unpack(0);
    for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
      _t[mi] = unpack(wr_master_rd_reqs[mi]);
    end
    let trans = transpose(_t);
    for (Integer i = 0; i< num_slaves; i = i + 1) begin
      let _n = fn_rr_arbiter(trans[i], rg_rd_master_select[i]);
      for (Integer j = 0; j< num_masters; j = j + 1) begin
        wr_rd_grant[i][j] <= _n[j] || unpack(fixed_priority_rd[j]);
      end
    end
  endrule:rl_rd_round_robin_arbiter
  
  /*doc:rule: This rule will resolve write contentions per slave using a round-robin arbitration policy*/
  rule rl_wr_round_robin_arbiter (&fixed_priority_wr == 1);
    Vector#(tn_num_masters, Vector#(tn_num_slaves,Bool)) _t = unpack(0);
    for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
      _t[mi] = unpack(wr_master_wr_reqs[mi]);
    end
    let trans = transpose(_t);
    for (Integer i = 0; i< num_slaves; i = i + 1) begin
      let _n = fn_rr_arbiter(trans[i], rg_wr_master_select[i]);
      for (Integer j = 0; j< num_masters; j = j + 1) begin
        wr_wr_grant[i][j] <= _n[j] || unpack(fixed_priority_wr[j]);
      end
    end
  endrule:rl_wr_round_robin_arbiter


  // ================================================================
  // Wr requests (AW, W and B channels)

  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj) && wr_wr_grant[sj][mi] && 
    	                                    write_slave[sj] == 1 );
    	  // Move the AW transaction
    	  Axi4_wr_addr #(wd_id, wd_addr, wd_user) 
    	      a <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_addr);
    	  xactors_to_slaves [sj].fifo_side.i_wr_addr.enq (a);
    
    	  // Enqueue a task for the W channel
    	  f_s_wd_route_info      [mi].enq (fromInteger (sj));
    	  f_m_wd_route_info      [sj].enq (fromInteger (mi));
    
    	  // Book-keeping
    	  f_m_wr_route_info        [sj].enq (fromInteger (mi));
    	  f_s_wr_route_info        [mi].enq (fromInteger (sj));
	      
	      if (&fixed_priority_wr == 0) begin
  	      if (mi == num_masters - 1)
	          rg_wr_master_select[sj] <= 0;
	        else
	          rg_wr_master_select[sj] <= fromInteger(mi+1);
	      end
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
    	  `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (a) ))
    	endrule:rl_wr_xaction_master_to_slave

  // Wr data (W channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    // Handle W channel burst
    // Note: awlen is encoded as 0..255 for burst lengths of 1..256
    rule rl_wr_xaction_master_to_slave_data (   f_s_wd_route_info [mi].first == fromInteger(sj)
                                              && f_m_wd_route_info [sj].first == fromInteger(mi)
                                              && write_slave[sj] == 1 );
      
      Axi4_wr_data #(wd_data, wd_user) d <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_data);

      // If sj is a legal slave, send it the data beat, else drop it.
      xactors_to_slaves [sj].fifo_side.i_wr_data.enq (d);
      `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
    	`logLevel( fabric, 0, $format("FABRIC: WRD: ",fshow (d) ))
      
      if ( d.wlast ) begin
        // End of burst
        f_s_wd_route_info [mi].deq;
        f_m_wd_route_info [sj].deq;
      end
   endrule:rl_wr_xaction_master_to_slave_data

  // Wr responses from slaves to masters (B channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_resp_slave_to_master (   (f_m_wr_route_info [sj].first == fromInteger (mi)) &&
	 	                             		      (f_s_wr_route_info [mi].first == fromInteger (sj)) &&
	 	                             		      write_slave[sj] == 1);
	      f_m_wr_route_info [sj].deq;
	      f_s_wr_route_info [mi].deq;
	      Axi4_wr_resp #(wd_id, wd_user) b <- pop_o (xactors_to_slaves [sj].fifo_side.o_wr_resp);

	      xactors_from_masters [mi].fifo_side.i_wr_resp.enq (b);
        `logLevel( fabric, 0, $format("FABRIC: WRB: slave[%2d] -> master[%2d]",sj, mi))
        `logLevel( fabric, 0, $format("FABRIC: WRB: ", fshow(b)))
	    endrule:rl_wr_resp_slave_to_master

  // ================================================================
  // Rd requests (AR and R channels)

  // Rd requests to legal slaves (AR channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
      rule rl_rd_xaction_master_to_slave (fv_mi_has_rd_for_sj (mi, sj) && wr_rd_grant[sj][mi] && read_slave[sj] == 1 );
	   
	      let arid_ = xactors_from_masters [mi].fifo_side.o_wr_addr.first.arid;
	      let is_present = fn_is_arid_inflight(arid_,mi);
	      //proceed for transaction only if arid is legal
	      if(is_present.valid && sids_of_arid[mi][is_present.index].notFull) begin
	           Axi4_rd_addr #(wd_id, wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].fifo_side.o_rd_addr);
	      	   
	      	   ff_sids_of_arid [mi][is_present.index].enq(fromInteger(sj));
	      	   xactors_to_slaves [sj].fifo_side.i_rd_addr.enq (a);
	      	   f_m_rd_route_info [sj].enq (fromInteger (mi));
	      	   f_s_rd_route_info [mi].enq (fromInteger (sj));
	      	   if (&fixed_priority_rd == 0) begin
  	      	   if (mi == num_masters - 1)
	               rg_rd_master_select[sj] <= 0;
	             else
	               rg_rd_master_select[sj] <= fromInteger(mi+1);
	      	   end
	      	   `logLevel( fabric, 0, $format("FABRIC: RDA: master[%2d] -> slave[%2d]",mi, sj))
	      	   `logLevel( fabric, 0, $format("FABRIC: RDA: ", fshow(a)))
	      end
	      // if arid is not present and there is a room for request 
	      if(!is_present.valid) begin
	           Axi4_rd_addr #(wd_id, wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].fifo_side.o_rd_addr);
	      	   
	      	   rg_rd_arid_in_flight[mi][ rg_rd_free_arids[mi][0] ] <= arid_;
	      	   ff_sids_of_arid [mi][ rg_rd_free_arids[mi][0] ].enq(fromInteger(sj));
	      	   xactors_to_slaves [sj].fifo_side.i_rd_addr.enq (a);
	      	   f_m_rd_route_info [sj].enq (fromInteger (mi));
	      	   f_s_rd_route_info [mi].enq (fromInteger (sj));
	      	   if (&fixed_priority_rd == 0) begin
  	      	   if (mi == num_masters - 1)
	               rg_rd_master_select[sj] <= 0;
	             else
	               rg_rd_master_select[sj] <= fromInteger(mi+1);
	      	   end
	      	   `logLevel( fabric, 0, $format("FABRIC: RDA: master[%2d] -> slave[%2d]",mi, sj))
	      	   `logLevel( fabric, 0, $format("FABRIC: RDA: ", fshow(a)))
	      end
	    endrule: rl_rd_xaction_master_to_slave

  // Rd responses from slaves to masters (R channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)

	    rule rl_rd_resp_slave_to_master (f_m_rd_route_info [sj].first == fromInteger (mi) &&
	 			                              (f_s_rd_route_info [mi].first == fromInteger (sj))&& 
	 			                               read_slave[sj] == 1);

	      Axi4_rd_data #(wd_id, wd_data, wd_user) 
	          r <- pop_o (xactors_to_slaves [sj].fifo_side.o_rd_data);

	      if ( r.rlast ) begin
	        // Final beat of burst
	        f_m_rd_route_info [sj].deq;
	        f_s_rd_route_info [mi].deq;
        end
        xactors_from_masters [mi].fifo_side.i_rd_data.enq (r);
	      `logLevel( fabric, 0, $format("FABRIC: RDR: slave[%2d] -> master[%2d]", sj, mi))
	      `logLevel( fabric, 0, $format("FABRIC: RDR: ", fshow(r) ))

	    endrule:rl_rd_resp_slave_to_master

  // ----------------------------------------------------------------
  // INTERFACE

  function Ifc_axi4_slave  #(wd_id, wd_addr, wd_data, wd_user) f1 (Integer j)
     = xactors_from_masters [j].axi4_side;
  function Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user) f2 (Integer j)
     = xactors_to_slaves    [j].axi4_side;

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule:mkaxi4_fabric_2
endpackage: axi4_fabric
