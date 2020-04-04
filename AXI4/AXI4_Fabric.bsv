// Copyright (c) 2013-2019 Bluespec, Inc. All Rights Reserved

package AXI4_Fabric;

// ----------------------------------------------------------------
// This package defines a fabric connecting CPUs, Memories and DMAs
// and other IP blocks.

// ----------------------------------------------------------------
// Bluespec library imports

import Vector       :: *;
import FIFOF        :: *;
import SpecialFIFOs :: *;
import ConfigReg    :: *;

// ----------------------------------------------------------------
// Project imports

import Semi_FIFOF :: *;
import AXI4_Types :: *;

`include "Logger.bsv"

// ----------------------------------------------------------------
// The interface for the fabric module

interface AXI4_Fabric_IFC #(numeric type tn_num_masters,
			                      numeric type tn_num_slaves,
			                      numeric type wd_id,
			                      numeric type wd_addr,
			                      numeric type wd_data,
			                      numeric type wd_user);
   method Action reset;
   method Action set_verbosity (Bit #(4) verbosity);

   // From masters
   interface Vector #(tn_num_masters, AXI4_Slave_IFC #(wd_id, wd_addr, wd_data, wd_user))  
                                                                                    v_from_masters;

   // To slaves
   interface Vector #(tn_num_slaves,  AXI4_Master_IFC #(wd_id, wd_addr, wd_data, wd_user)) 
                                                                                    v_to_slaves;
endinterface:AXI4_Fabric_IFC

// ----------------------------------------------------------------
// The Fabric module
// The function parameter is an address-decode function, which
// returns (True,  slave-port-num)  if address is mapped to slave-port-num
//         (False, ?)               if address is unmapped to any slave port

module mkAXI4_Fabric #(function Tuple2 #(Bool, Bit #(TLog #(tn_num_slaves)))
			        fn_addr_to_slave_num (Bit #(wd_addr) addr))
		     (AXI4_Fabric_IFC #(tn_num_masters, tn_num_slaves, wd_id, wd_addr, wd_data, wd_user))

  provisos ( Log #(tn_num_masters, log_nm),
	           Log #(tn_num_slaves,  log_ns),
	           Log #(TAdd #(tn_num_slaves,  1), log_ns_plus_1),
	           Add #(_dummy, TLog #(tn_num_slaves), log_ns_plus_1));

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  Reg #(Bool) rg_reset <- mkReg (True);

  // Transactors facing masters
  Vector #(tn_num_masters, AXI4_Slave_Xactor_IFC  #(wd_id, wd_addr, wd_data, wd_user))
     xactors_from_masters <- replicateM (mkAXI4_Slave_Xactor_2);

  // Transactors facing slaves
  Vector #(tn_num_slaves,  AXI4_Master_Xactor_IFC #(wd_id, wd_addr, wd_data, wd_user))
      xactors_to_slaves <- replicateM (mkAXI4_Master_Xactor_2);

  // ----------------------------------------------------------------
  // Book-keeping to keep track of which master originated a transaction, in
  // order to route corresponding responses back to that master, etc.
  // Legal slaves  are 0..(num_slaves-1)
  // The "illegal" value of 'num_slaves' is used for decode errors (no such slave)
  // Size of SizedFIFOs is estimated: should cover round-trip latency to slave and back.

  // ----------------
  // Write-transaction book-keeping

  // On an mi->sj write-transaction, this fifo records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns_plus_1))) 
                                                 v_f_wr_sjs <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records mi for slave sj
  Vector #(tn_num_slaves,  FIFOF #(Bit #(log_nm))) v_f_wr_mis  <- replicateM (mkSizedFIFOF (8));

  // On an mi->sj write-transaction, this fifo records a task (sj, awlen) for W channel
  Vector #(tn_num_masters, FIFOF #(Tuple2 #(Bit #(log_ns_plus_1), AXI4_Len)))     
                                                 v_f_wd_tasks <- replicateM (mkFIFOF);
  // On a write-transaction to non-exisitent slave, record id and user for error response
  Vector #(tn_num_masters, FIFOF #(Tuple2 #(Bit #(wd_id), Bit #(wd_user))))  
                                                 v_f_wr_err_info <- replicateM (mkSizedFIFOF (8));

  // ----------------
  // Read-transaction book-keeping

  // On an mi->sj read-transaction, records sj for master mi
  Vector #(tn_num_masters, FIFOF #(Bit #(log_ns_plus_1))) 
                                                     v_f_rd_sjs <- replicateM (mkSizedFIFOF (8));
  // On an mi->sj read-transaction, records (mi,arlen) for slave sj
  Vector #(tn_num_slaves, FIFOF #(Tuple2 #(Bit #(log_nm), AXI4_Len)))            
                                                     v_f_rd_mis <- replicateM (mkSizedFIFOF (8));

  // On a read-transaction to non-exisitent slave, record id and user for error response
  Vector #(tn_num_masters, FIFOF #(Tuple3 #(AXI4_Len, Bit #(wd_id), Bit #(wd_user)))) 
                                                 v_f_rd_err_info <- replicateM (mkSizedFIFOF (8));

  // ----------------------------------------------------------------
  // RESET

  rule rl_reset (rg_reset);
	  `logLevel( fabric, 0, $format("rl_reset"))
    for (Integer mi = 0; mi < num_masters; mi = mi + 1) begin
	    xactors_from_masters [mi].reset;
	    v_f_wr_sjs [mi].clear;
	    v_f_wd_tasks [mi].clear;
	    v_f_wr_err_info [mi].clear;
	    v_f_rd_sjs [mi].clear;
	    v_f_rd_err_info [mi].clear;
    end

    for (Integer sj = 0; sj < num_slaves; sj = sj + 1) begin
	    xactors_to_slaves [sj].reset;
	    v_f_wr_mis [sj].clear;
	    v_f_rd_mis [sj].clear;
    end
    rg_reset <= False;
  endrule

  // ----------------------------------------------------------------
  // BEHAVIOR

  // ----------------------------------------------------------------
  // Predicates to check if master I has transaction for slave J

  function Bool fv_mi_has_wr_for_sj (Integer mi, Integer sj);
    let addr = xactors_from_masters [mi].o_wr_addr.first.awaddr;
    match { .legal, .slave_num } = fn_addr_to_slave_num (addr);
    return (legal && (   (num_slaves == 1) || (slave_num == fromInteger (sj))));
  endfunction:fv_mi_has_wr_for_sj

  function Bool fv_mi_has_wr_for_none (Integer mi);
    let addr = xactors_from_masters [mi].o_wr_addr.first.awaddr;
    match { .legal, ._ } = fn_addr_to_slave_num (addr);
    return (! legal);
  endfunction:fv_mi_has_wr_for_none

  function Bool fv_mi_has_rd_for_sj (Integer mi, Integer sj);
    let addr = xactors_from_masters [mi].o_rd_addr.first.araddr;
    match { .legal, .slave_num } = fn_addr_to_slave_num (addr);
    return (legal && (   (num_slaves == 1) || (slave_num == fromInteger (sj))));
  endfunction:fv_mi_has_rd_for_sj

  function Bool fv_mi_has_rd_for_none (Integer mi);
    let addr = xactors_from_masters [mi].o_rd_addr.first.araddr;
    match { .legal, ._ } = fn_addr_to_slave_num (addr);
    return (! legal);
  endfunction:fv_mi_has_rd_for_none

  // ================================================================
  // Wr requests (AW, W and B channels)

  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)

    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj));
    	  // Move the AW transaction
    	  AXI4_Wr_Addr #(wd_id, wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].o_wr_addr);
    	  xactors_to_slaves [sj].i_wr_addr.enq (a);
    
    	  // Enqueue a task for the W channel
    	  v_f_wd_tasks      [mi].enq (tuple2 (fromInteger (sj), a.awlen));
    
    	  // Book-keeping
    	  v_f_wr_mis        [sj].enq (fromInteger (mi));
    	  v_f_wr_sjs        [mi].enq (fromInteger (sj));
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
    	  `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (a) ))
    	  end
    	endrule:rl_wr_xaction_master_to_slave

  // Wr data (W channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)

    // Handle W channel burst
    // Note: awlen is encoded as 0..255 for burst lengths of 1..256
    rule rl_wr_xaction_master_to_slave_data (v_f_wd_tasks [mi].first matches {.sj, .awlen});
      
      AXI4_Wr_Data #(wd_data, wd_user) d <- pop_o (xactors_from_masters [mi].o_wr_data);

      // If sj is a legal slave, send it the data beat, else drop it.
      if (sj < fromInteger (num_slaves))
        xactors_to_slaves [sj].i_wr_data.enq (d);
      `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
    	`logLevel( fabric, 0, $format("FABRIC: WRD: ",fshow (d) ))
      
      if ( d.wlast ) begin
        // End of burst
        v_f_wd_tasks [mi].deq;
      end
      else
        v_rg_wd_beat_count [mi] <= v_rg_wd_beat_count [mi] + 1;
   endrule:rl_wr_xaction_master_to_slave_data

  // Wr responses from slaves to masters (B channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_resp_slave_to_master (   (v_f_wr_mis [sj].first == fromInteger (mi)) &&
	 	                             		      (v_f_wr_sjs [mi].first == fromInteger (sj)));
	      v_f_wr_mis [sj].deq;
	      v_f_wr_sjs [mi].deq;
	      AXI4_Wr_Resp #(wd_id, wd_user) b <- pop_o (xactors_to_slaves [sj].o_wr_resp);

	      xactors_from_masters [mi].i_wr_resp.enq (b);
        `logLevel( fabric, 0, $format("FABRIC: WRB: slave[%2d] -> master[%2d]",sj, mi))
        `logLevel( fabric, 0, $format("FABRIC: WRB: ", fshow(b)))
	    endrule:rl_wr_resp_slave_to_master

  // ================================================================
  // Rd requests (AR and R channels)

  // Rd requests to legal slaves (AR channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
      rule rl_rd_xaction_master_to_slave (fv_mi_has_rd_for_sj (mi, sj));
	      
	      AXI4_Rd_Addr #(wd_id, wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].o_rd_addr);
	      xactors_to_slaves [sj].i_rd_addr.enq (a);
	      v_f_rd_mis [sj].enq (tuple2 (fromInteger (mi), a.arlen));
	      v_f_rd_sjs [mi].enq (fromInteger (sj));
	      `logLevel( fabric, 0, $format("FABRIC: RDA: master[%2d] -> slave[%2d]",mi, sj))
	      `logLevel( fabric, 0, $format("FABRIC: RDA: ", fshow(a)))
	    endrule: rl_rd_xaction_master_to_slave

  // Rd responses from slaves to masters (R channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)

	    rule rl_rd_resp_slave_to_master (v_f_rd_mis [sj].first matches { .mi2, .arlen }
	 			                          &&& (mi2 == fromInteger (mi))
	 			                          &&& (v_f_rd_sjs [mi].first == fromInteger (sj)));

	      AXI4_Rd_Data #(wd_id, wd_data, wd_user) r <- pop_o (xactors_to_slaves [sj].o_rd_data);

	      if ( r.rlast ) begin
	        // Final beat of burst
	        v_f_rd_mis [sj].deq;
	        v_f_rd_sjs [mi].deq;
        end
        xactors_from_masters [mi].i_rd_data.enq (r);
	      `logLevel( fabric, 0, $format("FABRIC: RDR: slave[%2d] -> master[%2d]", sj, mi))
	      `logLevel( fabric, 0, $format("FABRIC: RDR: ", fshow(r) ))

	    endrule:rl_rd_resp_slave_to_master

  // ----------------------------------------------------------------
  // INTERFACE

  function AXI4_Slave_IFC  #(wd_id, wd_addr, wd_data, wd_user) f1 (Integer j)
     = xactors_from_masters [j].axi_side;
  function AXI4_Master_IFC #(wd_id, wd_addr, wd_data, wd_user) f2 (Integer j)
     = xactors_to_slaves    [j].axi_side;

  method Action reset () if (! rg_reset);
     rg_reset <= True;
  endmethod

  method Action set_verbosity (Bit #(4) verbosity);
     cfg_verbosity <= verbosity;
  endmethod

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule

// ----------------------------------------------------------------

endpackage: AXI4_Fabric
