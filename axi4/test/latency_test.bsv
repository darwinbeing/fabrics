// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.
package latency_test;
  import FIFOF        :: * ;
  import SpecialFIFOs :: * ;
  import FIFO         :: * ;
  import Vector       :: * ;
  import DefaultValue :: * ;
  import Connectable  :: * ;
  import Semi_FIFOF   :: * ;
  import axi4         :: * ;
  `include "Logger.bsv"

  `define wd_id 4
  `define wd_addr 32
  `define wd_data 64
  `define wd_user 32
  `define nslaves_bits TLog #(`nslaves)
  
  typedef Ifc_axi4_fabric #(`nmasters,
			                      `nslaves,
			                      `wd_id,
			                      `wd_addr,
			                      `wd_data,
			                      `wd_user)  Ifc_fabric_axi4;
  function Bit#(TMax#(`nslaves_bits,1)) fn_mm(Bit#(`wd_addr) wd_addr);
    if (wd_addr >= 'h1000 && wd_addr < 'h2000)
      return 0;
    else if (wd_addr >= 'h2000 && wd_addr < 'h3000)
      return truncate(4'd1);
    else if (wd_addr >= 'h3000 && wd_addr < 'h4000)
      return truncate(4'd2);
    else if (wd_addr >= 'h4000 && wd_addr < 'h5000)
      return truncate(4'd3);
    else
      return truncate(4'd4);
  endfunction:fn_mm
  
  interface Ifc_withXactors;
    interface Vector#(`nmasters, Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user)) m_fifo;
  endinterface

  (*synthesize*)                            
  module mkinst_onlyfabric (Ifc_fabric_axi4);
    Ifc_fabric_axi4 fabric <- mkaxi4_fabric (fn_mm, replicate('1), replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric

  (*synthesize*)                            
  module mkinst_onlyfabric_2 (Ifc_fabric_axi4);
    Ifc_fabric_axi4 fabric <- mkaxi4_fabric_2 (fn_mm, replicate('1), replicate('1));
    return fabric;
  endmodule:mkinst_onlyfabric_2

  (*synthesize*)
  module mkinst_withxactors (Ifc_withXactors);

    Vector #(`nmasters, Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkaxi4_master_xactor(defaultValue));

    Vector #(`nslaves, Ifc_axi4_slave#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_err <- replicateM(mkaxi4_err);

    let fabric <- mkinst_onlyfabric; 

    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_err[i]);
    end

    function Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
  endmodule:mkinst_withxactors

  (*synthesize*)
  module mkinst_withxactors_2 (Ifc_withXactors);

    Vector #(`nmasters, Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user))
        m_xactors <- replicateM(mkaxi4_master_xactor_2);

    Vector #(`nslaves, Ifc_axi4_slave#(`wd_id, `wd_addr, `wd_data, `wd_user))
        s_err <- replicateM(mkaxi4_err_2);

    let fabric <- mkinst_onlyfabric_2; 

    for (Integer i = 0; i<`nmasters; i = i + 1) begin
      mkConnection(fabric.v_from_masters[i],m_xactors[i].axi_side);
    end
    for (Integer i = 0; i<`nslaves; i = i + 1) begin
      mkConnection(fabric.v_to_slaves[i],s_err[i]);
    end

    function Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
      = m_xactors[j].fifo_side;

    interface m_fifo = genWith(f1);
  endmodule:mkinst_withxactors_2


  /*doc:module: */
  module mkTb (Empty);
    let inst1 <- mkinst_withxactors;
    let inst2 <- mkinst_withxactors_2;
    /*doc:reg: */
    Reg#(Bit#(32)) rg_count <- mkReg(0);
    /*doc:rule: */
    rule rl_send_v1_read (rg_count == 0);
      let stime <- $stime;
      AXI4_rd_addr #(`wd_id, `wd_addr, `wd_user) _req = AXI4_rd_addr { arid:0,
                                                                      araddr:'h1000,
                                                                      arlen:0,
                                                                      arsize:0,
                                                                      arburst:0,
                                                                      arlock:0,
                                                                      arcache:0,
                                                                      arprot:0,
                                                                      arqos:0,
                                                                      arregion:0,
                                                                      aruser: stime };
     `logLevel( tb, 1, $format("Sending request: ", fshow_axi4_rd_addr(_req)))
      inst1.m_fifo[0].i_rd_addr.enq(_req);
      rg_count <= rg_count + 1;
    endrule
    /*doc:rule: */
    rule rl_get_v1_read (rg_count == 1);
      let _resp <- pop_o(inst1.m_fifo[0].o_rd_data);
      `logLevel( tb, 1, $format("Received Response: ",fshow_axi4_rd_data(_resp)))
      let stime <- $stime;
      let diff_time = stime - _resp.ruser;
      `logLevel( tb, 0, $format("Total cycles for V1 a single read op: %5d",diff_time/10))
      rg_count <= rg_count + 1;
    endrule
    rule rl_send_v1_write (rg_count == 2);
      let stime <- $stime;
      AXI4_wr_addr #(`wd_id, `wd_addr, `wd_user) _req = AXI4_wr_addr { awid:0,
                                                                       awaddr:'h2000,
                                                                       awlen:0,
                                                                       awsize:0,
                                                                       awburst:0,
                                                                       awlock:0,
                                                                       awcache:0,
                                                                       awprot:0,
                                                                       awqos:0,
                                                                       awregion:0,
                                                                       awuser:stime};
      AXI4_wr_data #(`wd_data, `wd_user) _w_req = AXI4_wr_data {wdata:'hdeadbeef,
                                                                wstrb:'1,
                                                                wlast:True,
                                                                wuser:stime};
     `logLevel( tb, 1, $format("Sending request: ", fshow_axi4_wr_addr(_req)))
      inst1.m_fifo[0].i_wr_addr.enq(_req);
      inst1.m_fifo[0].i_wr_data.enq(_w_req);
      rg_count <= rg_count + 1;
    endrule
    /*doc:rule: */
    rule rl_get_v1_write (rg_count == 3);
      let _resp <- pop_o(inst1.m_fifo[0].o_wr_resp);
      `logLevel( tb, 1, $format("Received Response: ",fshow_axi4_wr_resp(_resp)))
      let stime <- $stime;
      let diff_time = stime - _resp.buser;
      `logLevel( tb, 0, $format("Total cycles for V1 a single write op: %5d",diff_time/10))
      rg_count <= rg_count + 1;
    endrule
    rule rl_second_transaction (rg_count == 4);
      let stime <- $stime;
      AXI4_rd_addr #(`wd_id, `wd_addr, `wd_user) _req = AXI4_rd_addr { arid:0,
                                                                      araddr:'h1000,
                                                                      arlen:0,
                                                                      arsize:0,
                                                                      arburst:0,
                                                                      arlock:0,
                                                                      arcache:0,
                                                                      arprot:0,
                                                                      arqos:0,
                                                                      arregion:0,
                                                                      aruser: stime };
     `logLevel( tb, 1, $format("Sending request: ", fshow_axi4_rd_addr(_req)))
      inst2.m_fifo[0].i_rd_addr.enq(_req);
      rg_count <= rg_count + 1;
    endrule
    /*doc:rule: */
    rule rl_end_second (rg_count == 5);
      let _resp <- pop_o(inst2.m_fifo[0].o_rd_data);
      `logLevel( tb, 1, $format("Received Response: ",fshow_axi4_rd_data(_resp)))
      let stime <- $stime;
      let diff_time = stime - _resp.ruser;
      `logLevel( tb, 0, $format("Total cycles for V2 a single read op: %5d",diff_time/10))
      $finish(0);
      rg_count <= rg_count + 1;
    endrule
  endmodule:mkTb
endpackage

