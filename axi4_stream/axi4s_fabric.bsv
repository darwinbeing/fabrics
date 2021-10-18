// Copyright (c) 2013-2019 Bluespec, Inc. see LICENSE.bluespec for details.
// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package axi4s_fabric;

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
import axi4s_types :: *;

`include "Logger.bsv"

// ----------------------------------------------------------------
// The interface for the fabric module

interface Ifc_axi4s_fabric #(numeric type tn_num_masters,
			                      numeric type tn_num_slaves,
			                      numeric type wd_tdest,
				 	      numeric type wd_data,
				 	      numeric type wd_tuser,
					      numeric type wd_tid);
   // From masters
   (*prefix="frm_master"*)
   interface Vector #(tn_num_masters, Ifc_axi4s_slave #( wd_tdest,wd_tdata, wd_tuser,wd_tid))  
                                                                                    v_from_masters;

   // To slaves
   (*prefix="to_slave"*)
   interface Vector #(tn_num_slaves,  Ifc_axi4s_master #( wd_tdest,wd_tdata, wd_tuser,wd_tid)) 
                                                                                    v_to_slaves;
endinterface:Ifc_axi4s_fabric

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
// The function parameter is an address-decode function, which

// the reason for having two memory map functions is to avoid creating redundant connections on the
// for read-only and write-only devices. The connections could have been avoided using a simple
// read and write mask, but then a non-existent connection should end up at the err-slave which
// would not be possible by using masks. 
module mkaxi4s_fabric #(
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_rd_memory_map (Bit #(wd_tdest) addr), 
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_wr_memory_map (Bit #(wd_tdest) addr),
    parameter Bit#(tn_num_slaves)  read_slave,
    parameter Bit#(tn_num_slaves)  write_slave,
    parameter Bit#(tn_num_masters) fixed_priority_rd,
    parameter Bit#(tn_num_masters) fixed_priority_wr
    )
		(Ifc_axi4s_fabric #(tn_num_masters, tn_num_slaves, wd_tdest,wd_tdata, wd_tuser,wd_tid))

  provisos ( Max #(TLog #(tn_num_masters) , 1, log_nm),
             Max #(TLog #(tn_num_slaves)  , 1 ,log_ns) 
           );

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  // Transactors facing masters
  Vector #(tn_num_masters, Ifc_axi4s_slave_xactor  #( wd_tdest,wd_tdata, wd_tuser,wd_tid))
  xactors_from_masters <- replicateM (mkaxi4s_slave_xactor(defaultValue));

  // Transactors facing slaves
  Vector #(tn_num_slaves,  Ifc_axi4s_master_xactor #( wd_tdest,wd_tdata, wd_tuser,wd_tid))
  xactors_to_slaves <- replicateM (mkaxi4s_master_xactor(defaultValue));


  // ----------------
  // Write-transaction book-keeping

  // On an mi->sj write-transaction, this fifo records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                 v_f_wr_sjs <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records mi for slave sj
  Vector #(tn_num_slaves,  FIFOF #(Bit #(log_nm))) v_f_wr_mis  <- replicateM (mkSizedFIFOF (8));

  // ----------------
  // Read-transaction book-keeping

  // On an mi->sj read-transaction, records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                     v_f_rd_sjs <- replicateM (mkSizedFIFOF (8));
  // On an mi->sj read-transaction, records (mi,arlen) for slave sj
  Vector #(tn_num_slaves, FIFOF #(Bit #(log_nm)))    v_f_rd_mis <- replicateM (mkSizedFIFOF (8));

  /*doc:reg: round robin counter for read requests*/
  Vector #(tn_num_slaves, Reg#(Bit#(TLog#(tn_num_masters)))) rg_rd_master_select
                                                              <- replicateM(mkReg(0));

  /*doc:vec: vector of wires indicating which slave is a read-master trying to lock*/
  Vector#(tn_num_masters, Wire#(Bit#(tn_num_slaves))) wr_master_rd_reqs <- replicateM(mkDWire(0));
  /*doc:vec: a matrix of wires indicating which read-master has been granted permission to access which
   * slave */
  Vector#(tn_num_slaves , Vector#(tn_num_masters, Wire#(Bool))) wr_rd_grant 
                                                        <- replicateM(replicateM(mkDWire(True)));
  /*doc:reg: round robin counter for write-requests*/
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
    let addr       = xactors_from_masters [mi].fifo_side.o_stream.first.tdest;
    let slave_num  = fn_wr_memory_map (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_wr_for_sj



  for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin
    /*doc:rule: this rule will update a vector for each master making a write-request to indicate
     * which slave is being targetted*/
    rule rl_capture_wr_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_stream.first.tdest;
      _t[fn_wr_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_wr_addr.notEmpty) begin
        wr_master_wr_reqs[mi]    <= _t;
      end
    endrule:rl_capture_wr_slave_contention
  end

  
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


  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj) && wr_wr_grant[sj][mi] && 
    	                                    write_slave[sj] == 1 );
    	  // Move the AW transaction
        Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid) d <- pop_o (xactors_from_masters [mi].fifo_side.o_stream);
    	  xactors_to_slaves [sj].fifo_side.i_stream.enq (d);								/////// check
    
    	  // Book-keeping
    	  v_f_wr_mis        [sj].enq (fromInteger (mi));
    	  v_f_wr_sjs        [mi].enq (fromInteger (sj));
	      
	      if (&fixed_priority_wr == 0) begin
  	      if (mi == num_masters - 1)
	          rg_wr_master_select[sj] <= 0;
	        else
	          rg_wr_master_select[sj] <= fromInteger(mi+1);
	      end
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
        `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
        `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (d) ))
    	endrule:rl_wr_xaction_master_to_slave



  // ----------------------------------------------------------------
  // INTERFACE

  function Ifc_axi4s_slave  #( wd_tdest,wd_tdata, wd_tuser,wd_tid) f1 (Integer j)
     = xactors_from_masters [j].axi4s_side;
  function Ifc_axi4s_master #( wd_tdest,wd_tdata, wd_tuser,wd_tid) f2 (Integer j)
     = xactors_to_slaves    [j].axi4s_side;

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule:mkaxi4s_fabric

module mkaxi4s_fabric_2 #(
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_rd_memory_map (Bit #(wd_tdest) addr), 
    function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_wr_memory_map (Bit #(wd_tdest) addr),
    parameter Bit#(tn_num_slaves)  read_slave,
    parameter Bit#(tn_num_slaves)  write_slave,
    parameter Bit#(tn_num_masters) fixed_priority_rd,
    parameter Bit#(tn_num_masters) fixed_priority_wr
    )
		(Ifc_axi4s_fabric #(tn_num_masters, tn_num_slaves,  wd_tdest,wd_tdata, wd_tuser,wd_tid))

  provisos ( Max #(TLog #(tn_num_masters) , 1, log_nm),
             Max #(TLog #(tn_num_slaves)  , 1 ,log_ns) 
           );

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  // Transactors facing masters
  Vector #(tn_num_masters, Ifc_axi4s_slave_xactor  #( wd_tdest,wd_tdata, wd_tuser,wd_tid))
      xactors_from_masters <- replicateM (mkaxi4s_slave_xactor_2);

  // Transactors facing slaves
  Vector #(tn_num_slaves,  Ifc_axi4s_master_xactor #( wd_tdest,wd_tdata, wd_tuser,wd_tid))
      xactors_to_slaves <- replicateM (mkaxi4s_master_xactor_2);


  // ----------------
  // Write-transaction book-keeping

  // On an mi->sj write-transaction, this fifo records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns))) 
                                                 v_f_wr_sjs <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records mi for slave sj
  Vector #(tn_num_slaves,  FIFOF #(Bit #(log_nm))) v_f_wr_mis  <- replicateM (mkSizedFIFOF (8));



  /*doc:reg: round robin counter for write-requests*/
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
    let addr       = xactors_from_masters [mi].fifo_side.o_stream.first.tdest;
    let slave_num  = fn_wr_memory_map (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_wr_for_sj


  for (Integer mi = 0; mi< num_masters; mi = mi + 1) begin

    /*doc:rule: this rule will update a vector for each master making a write-request to indicate
     * which slave is being targetted*/
    rule rl_capture_wr_slave_contention;
      Bit#(tn_num_slaves) _t = 0;
      let addr                   = xactors_from_masters [mi].fifo_side.o_stream.first.tdest;
      _t[fn_wr_memory_map(addr)] = 1;
      if(xactors_from_masters [mi].fifo_side.o_wr_addr.notEmpty) begin
        wr_master_wr_reqs[mi]    <= _t;
      end
    endrule:rl_capture_wr_slave_contention
  end
  
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



  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj) && wr_wr_grant[sj][mi]
    	                                   && write_slave[sj] == 1);
    	  // Move the AW transaction
        Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid) d <- pop_o (xactors_from_masters [mi].fifo_side.o_stream);
    	  xactors_to_slaves [sj].fifo_side.i_stream.enq (d);
    
    	  // Book-keeping
    	  v_f_wr_mis        [sj].enq (fromInteger (mi));
    	  v_f_wr_sjs        [mi].enq (fromInteger (sj));
	      
	      if (&fixed_priority_wr == 0) begin
  	      if (mi == num_masters - 1)
	          rg_wr_master_select[sj] <= 0;
	        else
	          rg_wr_master_select[sj] <= fromInteger(mi+1);
	      end
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
        `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
    	  `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (d) ))
    	endrule:rl_wr_xaction_master_to_slave




  // ----------------------------------------------------------------
  // INTERFACE

  function Ifc_axi4s_slave  #( wd_tdest,wd_tdata, wd_tuser,wd_tid) f1 (Integer j)
     = xactors_from_masters [j].axi4s_side;
  function Ifc_axi4s_master #( wd_tdest,wd_tdata, wd_tuser,wd_tid) f2 (Integer j)
     = xactors_to_slaves    [j].axi4s_side;

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule:mkaxi4s_fabric_2
// ----------------------------------------------------------------

endpackage: axi4s_fabric
