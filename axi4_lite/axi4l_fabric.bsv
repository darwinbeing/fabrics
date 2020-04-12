// Copyright (c) 2013-2019 Bluespec, Inc. see LICENSE.bluespec for details.
// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package axi4l_fabric;

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
import axi4l_types :: *;

`include "Logger.bsv"

// ----------------------------------------------------------------
// The interface for the fabric module

interface Ifc_axi4l_fabric #(numeric type tn_num_masters,
			                      numeric type tn_num_slaves,
			                      numeric type wd_addr,
			                      numeric type wd_data,
			                      numeric type wd_user);
   // From masters
   interface Vector #(tn_num_masters, Ifc_axi4l_slave #( wd_addr, wd_data, wd_user))  
                                                                                    v_from_masters;

   // To slaves
   interface Vector #(tn_num_slaves,  Ifc_axi4l_master #( wd_addr, wd_data, wd_user)) 
                                                                                    v_to_slaves;
endinterface:Ifc_axi4l_fabric

// ----------------------------------------------------------------
// The Fabric module
// The function parameter is an address-decode function, which
// returns (True,  slave-port-num)  if address is mapped to slave-port-num
//         (False, ?)               if address is unmapped to any slave port

module mkaxi4l_fabric #(
  function Bit #(TMax#(TLog #(tn_num_slaves), 1)) fn_addr_to_slave_num (Bit #(wd_addr) addr), 
    parameter Vector#(tn_num_masters, Bit#(tn_num_slaves)) wr_mask , 
    parameter Vector#(tn_num_masters, Bit#(tn_num_slaves)) rd_mask )
		(Ifc_axi4l_fabric #(tn_num_masters, tn_num_slaves,  wd_addr, wd_data, wd_user))

  provisos ( Max #(TLog #(tn_num_masters) , 1, log_nm),
             Max #(TLog #(tn_num_slaves)  , 1 ,log_ns) 
           );

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  // Transactors facing masters
  Vector #(tn_num_masters, Ifc_axi4l_slave_xactor  #( wd_addr, wd_data, wd_user))
  xactors_from_masters <- replicateM (mkaxi4l_slave_xactor(defaultValue));

  // Transactors facing slaves
  Vector #(tn_num_slaves,  Ifc_axi4l_master_xactor #( wd_addr, wd_data, wd_user))
  xactors_to_slaves <- replicateM (mkaxi4l_master_xactor(defaultValue));


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

  // ----------------------------------------------------------------
  // BEHAVIOR

  // ----------------------------------------------------------------
  // Predicates to check if master I has transaction for slave J

  function Bool fv_mi_has_wr_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
    let slave_num  = fn_addr_to_slave_num (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_wr_for_sj

  function Bool fv_mi_has_rd_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
    let slave_num  = fn_addr_to_slave_num (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_rd_for_sj

  // ================================================================
  // Wr requests (AW, W and B channels)

  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj) && wr_mask[mi][sj] == 1);
    	  // Move the AW transaction
    	  Axi4l_wr_addr #(wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_addr);
        Axi4l_wr_data #(wd_data) d <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_data);
    	  xactors_to_slaves [sj].fifo_side.i_wr_addr.enq (a);
    	  xactors_to_slaves [sj].fifo_side.i_wr_data.enq (d);
    
    	  // Book-keeping
    	  v_f_wr_mis        [sj].enq (fromInteger (mi));
    	  v_f_wr_sjs        [mi].enq (fromInteger (sj));
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
        `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
    	  `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (a) ))
    	endrule:rl_wr_xaction_master_to_slave

  // Wr responses from slaves to masters (B channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_resp_slave_to_master (   (v_f_wr_mis [sj].first == fromInteger (mi)) &&
	 	                             		      (v_f_wr_sjs [mi].first == fromInteger (sj))
	 	                             		      && wr_mask[mi][sj] == 1);
	      v_f_wr_mis [sj].deq;
	      v_f_wr_sjs [mi].deq;
	      Axi4l_wr_resp #( wd_user) b <- pop_o (xactors_to_slaves [sj].fifo_side.o_wr_resp);

	      xactors_from_masters [mi].fifo_side.i_wr_resp.enq (b);
        `logLevel( fabric, 0, $format("FABRIC: WRB: slave[%2d] -> master[%2d]",sj, mi))
        `logLevel( fabric, 0, $format("FABRIC: WRB: ", fshow(b)))
	    endrule:rl_wr_resp_slave_to_master

  // ================================================================
  // Rd requests (AR and R channels)

  // Rd requests to legal slaves (AR channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
      rule rl_rd_xaction_master_to_slave (fv_mi_has_rd_for_sj (mi, sj) && rd_mask[mi][sj] == 1 );
	      
	      Axi4l_rd_addr #(wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].fifo_side.o_rd_addr);

	      xactors_to_slaves [sj].fifo_side.i_rd_addr.enq (a);

	      v_f_rd_mis [sj].enq (fromInteger (mi));
	      v_f_rd_sjs [mi].enq (fromInteger (sj));
	      `logLevel( fabric, 0, $format("FABRIC: RDA: master[%2d] -> slave[%2d]",mi, sj))
	      `logLevel( fabric, 0, $format("FABRIC: RDA: ", fshow(a)))
	    endrule: rl_rd_xaction_master_to_slave

  // Rd responses from slaves to masters (R channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)

	    rule rl_rd_resp_slave_to_master (v_f_rd_mis [sj].first == fromInteger (mi) &&
	 			                              (v_f_rd_sjs [mi].first == fromInteger (sj))
	 			                              && rd_mask[mi][sj] == 1 );

	      Axi4l_rd_data #( wd_data, wd_user) 
	          r <- pop_o (xactors_to_slaves [sj].fifo_side.o_rd_data);
	      v_f_rd_mis [sj].deq;
	      v_f_rd_sjs [mi].deq;
        xactors_from_masters [mi].fifo_side.i_rd_data.enq (r);
	      `logLevel( fabric, 0, $format("FABRIC: RDR: slave[%2d] -> master[%2d]", sj, mi))
	      `logLevel( fabric, 0, $format("FABRIC: RDR: ", fshow(r) ))

	    endrule:rl_rd_resp_slave_to_master

  // ----------------------------------------------------------------
  // INTERFACE

  function Ifc_axi4l_slave  #( wd_addr, wd_data, wd_user) f1 (Integer j)
     = xactors_from_masters [j].axil_side;
  function Ifc_axi4l_master #( wd_addr, wd_data, wd_user) f2 (Integer j)
     = xactors_to_slaves    [j].axil_side;

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule:mkaxi4l_fabric

module mkaxi4l_fabric_2 #(
    function Bit #(TLog #(tn_num_slaves)) fn_addr_to_slave_num (Bit #(wd_addr) addr), 
    parameter Vector#(tn_num_masters, Bit#(tn_num_slaves)) wr_mask , 
    parameter Vector#(tn_num_masters, Bit#(tn_num_slaves)) rd_mask )
		(Ifc_axi4l_fabric #(tn_num_masters, tn_num_slaves,  wd_addr, wd_data, wd_user))

  provisos ( Max #(TLog #(tn_num_masters) , 1, log_nm),
             Max #(TLog #(tn_num_slaves)  , 1 ,log_ns) 
           );

  Integer num_masters = valueOf (tn_num_masters);
  Integer num_slaves  = valueOf (tn_num_slaves);

  // Transactors facing masters
  Vector #(tn_num_masters, Ifc_axi4l_slave_xactor  #( wd_addr, wd_data, wd_user))
  xactors_from_masters <- replicateM (mkaxi4l_slave_xactor_2);

  // Transactors facing slaves
  Vector #(tn_num_slaves,  Ifc_axi4l_master_xactor #( wd_addr, wd_data, wd_user))
  xactors_to_slaves <- replicateM (mkaxi4l_master_xactor_2);


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

  // ----------------------------------------------------------------
  // BEHAVIOR

  // ----------------------------------------------------------------
  // Predicates to check if master I has transaction for slave J

  function Bool fv_mi_has_wr_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_wr_addr.first.awaddr;
    let slave_num  = fn_addr_to_slave_num (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_wr_for_sj

  function Bool fv_mi_has_rd_for_sj (Integer mi, Integer sj);
    let addr       = xactors_from_masters [mi].fifo_side.o_rd_addr.first.araddr;
    let slave_num  = fn_addr_to_slave_num (addr);
    return (slave_num == fromInteger (sj));
  endfunction:fv_mi_has_rd_for_sj

  // ================================================================
  // Wr requests (AW, W and B channels)

  // Wr requests to legal slaves (AW channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_xaction_master_to_slave (fv_mi_has_wr_for_sj (mi, sj) && wr_mask[mi][sj] == 1);
    	  // Move the AW transaction
    	  Axi4l_wr_addr #(wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_addr);
        Axi4l_wr_data #(wd_data) d <- pop_o (xactors_from_masters [mi].fifo_side.o_wr_data);
    	  xactors_to_slaves [sj].fifo_side.i_wr_addr.enq (a);
    	  xactors_to_slaves [sj].fifo_side.i_wr_data.enq (d);
    
    	  // Book-keeping
    	  v_f_wr_mis        [sj].enq (fromInteger (mi));
    	  v_f_wr_sjs        [mi].enq (fromInteger (sj));
   
        `logLevel( fabric, 0, $format("FABRIC: WRA: master[%2d] -> slave[%2d]", mi, sj))
        `logLevel( fabric, 0, $format("FABRIC: WRD: master[%2d] -> slave[%2d]", mi, sj))
    	  `logLevel( fabric, 0, $format("FABRIC: WRA: ",fshow (a) ))
    	endrule:rl_wr_xaction_master_to_slave

  // Wr responses from slaves to masters (B channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
    	rule rl_wr_resp_slave_to_master (   (v_f_wr_mis [sj].first == fromInteger (mi)) &&
	 	                             		      (v_f_wr_sjs [mi].first == fromInteger (sj))
	 	                             		      && wr_mask[mi][sj] == 1);
	      v_f_wr_mis [sj].deq;
	      v_f_wr_sjs [mi].deq;
	      Axi4l_wr_resp #( wd_user) b <- pop_o (xactors_to_slaves [sj].fifo_side.o_wr_resp);

	      xactors_from_masters [mi].fifo_side.i_wr_resp.enq (b);
        `logLevel( fabric, 0, $format("FABRIC: WRB: slave[%2d] -> master[%2d]",sj, mi))
        `logLevel( fabric, 0, $format("FABRIC: WRB: ", fshow(b)))
	    endrule:rl_wr_resp_slave_to_master

  // ================================================================
  // Rd requests (AR and R channels)

  // Rd requests to legal slaves (AR channel)
  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)
      rule rl_rd_xaction_master_to_slave (fv_mi_has_rd_for_sj (mi, sj) && rd_mask[mi][sj] == 1 );
	      
	      Axi4l_rd_addr #(wd_addr, wd_user) a <- pop_o (xactors_from_masters [mi].fifo_side.o_rd_addr);

	      xactors_to_slaves [sj].fifo_side.i_rd_addr.enq (a);

	      v_f_rd_mis [sj].enq (fromInteger (mi));
	      v_f_rd_sjs [mi].enq (fromInteger (sj));
	      `logLevel( fabric, 0, $format("FABRIC: RDA: master[%2d] -> slave[%2d]",mi, sj))
	      `logLevel( fabric, 0, $format("FABRIC: RDA: ", fshow(a)))
	    endrule: rl_rd_xaction_master_to_slave

  // Rd responses from slaves to masters (R channel)

  for (Integer mi = 0; mi < num_masters; mi = mi + 1)
    for (Integer sj = 0; sj < num_slaves; sj = sj + 1)

	    rule rl_rd_resp_slave_to_master (v_f_rd_mis [sj].first == fromInteger (mi) &&
	 			                              (v_f_rd_sjs [mi].first == fromInteger (sj))
	 			                              && rd_mask[mi][sj] == 1 );

	      Axi4l_rd_data #( wd_data, wd_user) 
	          r <- pop_o (xactors_to_slaves [sj].fifo_side.o_rd_data);
	      v_f_rd_mis [sj].deq;
	      v_f_rd_sjs [mi].deq;
        xactors_from_masters [mi].fifo_side.i_rd_data.enq (r);
	      `logLevel( fabric, 0, $format("FABRIC: RDR: slave[%2d] -> master[%2d]", sj, mi))
	      `logLevel( fabric, 0, $format("FABRIC: RDR: ", fshow(r) ))

	    endrule:rl_rd_resp_slave_to_master

  // ----------------------------------------------------------------
  // INTERFACE

  function Ifc_axi4l_slave  #( wd_addr, wd_data, wd_user) f1 (Integer j)
     = xactors_from_masters [j].axil_side;
  function Ifc_axi4l_master #( wd_addr, wd_data, wd_user) f2 (Integer j)
     = xactors_to_slaves    [j].axil_side;

  interface v_from_masters = genWith (f1);
  interface v_to_slaves    = genWith (f2);
endmodule:mkaxi4l_fabric_2
// ----------------------------------------------------------------

endpackage: axi4l_fabric
