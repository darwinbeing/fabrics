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
import StmtFSM      :: * ;
import BUtils       :: * ;
`include "Logger.bsv"

`define wd_id 4
`define wd_addr 32
`define wd_data 512
`define wd_user 32
`define tn_num_masters 2
`define tn_num_slaves  2
`define fixed_priority_rd  'b00
`define fixed_priority_wr  'b00
`define tn_num_slaves_bits TLog #(`tn_num_slaves)

typedef Ifc_axi4_fabric #(`tn_num_masters,
		                      `tn_num_slaves,
		                      `wd_id,
		                      `wd_addr,
		                      `wd_data,
		                      `wd_user)  Ifc_fabric_axi4;
function Bit#(TMax#(`tn_num_slaves_bits,1)) fn_rd_memory_map(Bit#(`wd_addr) wd_addr);
  if (wd_addr >= 'h1000 && wd_addr <= 'h2000)
    return 0;
  else
    return truncate(4'd1);
endfunction:fn_rd_memory_map
function Bit#(TMax#(`tn_num_slaves_bits,1)) fn_wr_memory_map(Bit#(`wd_addr) wd_addr);
  return truncate(4'd1);
endfunction:fn_wr_memory_map

interface Ifc_withXactors;
  interface Vector#(`tn_num_masters, Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user)) m_fifo;
endinterface

(*synthesize*)                            
module mkinst_onlyfabric (Ifc_fabric_axi4);
  Ifc_fabric_axi4 fabric <- mkaxi4_fabric (fn_rd_memory_map, fn_wr_memory_map, '1, '1,
                                            `fixed_priority_rd, `fixed_priority_wr);
  return fabric;
endmodule:mkinst_onlyfabric

(*synthesize*)
module mkinst_withxactors (Ifc_withXactors);

  Vector #(`tn_num_masters, Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user))
      vip_master <- replicateM(mkaxi4_master_xactor(defaultValue));

  Vector #(`tn_num_slaves, Ifc_axi4_slave#(`wd_id, `wd_addr, `wd_data, `wd_user))
      vip_slave <- replicateM(mkaxi4_err);

  let fabric <- mkinst_onlyfabric; 

  for (Integer i = 0; i<`tn_num_masters; i = i + 1) begin
    mkConnection(fabric.v_from_masters[i],vip_master[i].axi4_side);
  end
  for (Integer i = 0; i<`tn_num_slaves; i = i + 1) begin
    mkConnection(fabric.v_to_slaves[i],vip_slave[i]);
  end

  function Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
    = vip_master[j].fifo_side;

  interface m_fifo = genWith(f1);
endmodule:mkinst_withxactors

(*synthesize*)                            
module mkinst_onlyfabric_2 (Ifc_fabric_axi4);
  Ifc_fabric_axi4 fabric <- mkaxi4_fabric_2 (fn_rd_memory_map, fn_wr_memory_map, '1, '1,
                                            `fixed_priority_rd, `fixed_priority_wr);
  return fabric;
endmodule:mkinst_onlyfabric_2


(*synthesize*)
module mkinst_withxactors_2 (Ifc_withXactors);

  Vector #(`tn_num_masters, Ifc_axi4_master_xactor #(`wd_id, `wd_addr, `wd_data, `wd_user))
      m_xactors <- replicateM(mkaxi4_master_xactor_2);

  Vector #(`tn_num_slaves, Ifc_axi4_slave#(`wd_id, `wd_addr, `wd_data, `wd_user))
      s_err <- replicateM(mkaxi4_err_2);

  let fabric <- mkinst_onlyfabric_2; 

  for (Integer i = 0; i<`tn_num_masters; i = i + 1) begin
    mkConnection(fabric.v_from_masters[i],m_xactors[i].axi4_side);
  end
  for (Integer i = 0; i<`tn_num_slaves; i = i + 1) begin
    mkConnection(fabric.v_to_slaves[i],s_err[i]);
  end

  function Ifc_axi4_server #(`wd_id, `wd_addr, `wd_data, `wd_user) f1 (Integer j)
    = m_xactors[j].fifo_side;

  interface m_fifo = genWith(f1);
endmodule:mkinst_withxactors_2

typedef Axi4_rd_addr #(`wd_id, `wd_addr, `wd_user) ARReq;
typedef Axi4_wr_addr #(`wd_id, `wd_addr, `wd_user) AWReq;
typedef Axi4_wr_data #(`wd_data, `wd_user)          AWDReq;

  
module mkTb(Empty);
  
  let inst1 <- mkinst_withxactors;
  /*doc:reg: */
  Reg#(Bit#(32)) rg_count <- mkReg(0);
  Reg#(int) iter <- mkRegU;
  Reg#(int) iter1 <- mkRegU;
  Reg#(Bit#(`wd_data)) rg_axi_data <- mkReg('haaaaaaaa);

  Stmt check1 = (
  par
    seq
      action
        AWReq request = Axi4_wr_addr {awaddr:'hFFFFFFFF, awlen:0, awsize:0, awburst:0, awid:5, awuser:1};
        AWDReq requestd = Axi4_wr_data {wdata: duplicate(32'hdeadbeef), wlast:True, wstrb:'h80000000_00000000};
        inst1.m_fifo[0].i_wr_addr.enq(request);
        inst1.m_fifo[0].i_wr_data.enq(requestd);
      endaction
      delay(10);
      action
        AWReq request = Axi4_wr_addr {awaddr:'hFFFFFFFC, awlen:3, awsize:0, awburst:0, awid:6, awuser:1};
        inst1.m_fifo[0].i_wr_addr.enq(request);
      endaction
      delay(20);
      for(iter1 <= 1; iter1 <= 4; iter1 <= iter1 + 1)
        action
          AWDReq req = Axi4_wr_data{wdata:rg_axi_data, wstrb:'h80000000_00000000, wlast: iter1 == 4};
          inst1.m_fifo[0].i_wr_data.enq(req);
          $display("[%10d]\tSending WrD Req",$time, fshow_axi4_wr_data(req));
          rg_axi_data <= rg_axi_data + '1;
        endaction
      delay(50);
      for(iter1 <= 1; iter1 <= 4; iter1 <= iter1 + 1)
        action
          AWDReq req = Axi4_wr_data{wdata:rg_axi_data, wstrb:'h80000000_00000000, wlast: iter1 == 4};
          inst1.m_fifo[0].i_wr_data.enq(req);
          $display("[%10d]\tSending WrD Req",$time, fshow_axi4_wr_data(req));
          rg_axi_data <= rg_axi_data + '1;
        endaction
      action
        AWReq request = Axi4_wr_addr {awaddr:'hFFFFFFF0, awlen:3, awsize:0, awburst:0, awid:7, awuser:1};
        inst1.m_fifo[0].i_wr_addr.enq(request);
      endaction
      delay(100);
    endseq
    for(iter <= 1; iter <= 2; iter <= iter + 1)
      action
        await (inst1.m_fifo[0].o_wr_resp.notEmpty);
        let resp = inst1.m_fifo[0].o_wr_resp.first;
        inst1.m_fifo[0].o_wr_resp.deq;
        $display("[%10d]\tRevieved Resp:",$time, fshow(resp));
      endaction
  endpar
  );
  
//  Stmt requests = (
//    par
//      seq
//        action
//          let stime <- $stime;
//          ARReq request = Axi4_rd_addr {araddr:'h1000, arlen:7, arsize:2, arburst:axburst_incr};
//          inst1.m_fifo[0].i_rd_addr.enq(request);
//          $display("[%10d]\tSending Rd Req",$time, fshow_axi4_rd_addr(request));
//        endaction
//        action
//          let stime <- $stime;
//          AWReq request = Axi4_wr_addr {awaddr:'h1000, awlen:7, awsize:2, awburst:axburst_incr};
//          inst1.m_fifo[0].i_wr_addr.enq(request);
//          $display("[%10d]\tSending Wr Req",$time, fshow_axi4_wr_addr(request));
//        endaction
//        for(iter1 <= 1; iter1 <= 8; iter1 <= iter1 + 1)
//          action
//            AWDReq req = Axi4_wr_data{wdata:rg_axi_data, wstrb:'1, wlast: iter1 == 8};
//            inst1.m_fifo[0].i_wr_data.enq(req);
//            $display("[%10d]\tSending WrD Req",$time, fshow_axi4_wr_data(req));
//            rg_axi_data <= rg_axi_data + 'h11111111;
//          endaction
//      endseq
//      seq
//        for(iter <= 1; iter <= 8; iter <= iter + 1)
//          action
//            await (inst1.m_fifo[0].o_rd_data.notEmpty);
//            let resp = inst1.m_fifo[0].o_rd_data.first;
//            inst1.m_fifo[0].o_rd_data.deq;
//            let stime <- $stime;
//            let diff_time = stime - resp.ruser;
//            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow(resp));
//          endaction
//        for(iter <= 1; iter <= 1; iter <= iter + 1)
//          action
//            await (inst1.m_fifo[0].o_wr_resp.notEmpty);
//            let resp = inst1.m_fifo[0].o_wr_resp.first;
//            inst1.m_fifo[0].o_wr_resp.deq;
//            let stime <- $stime;
//            let diff_time = stime - resp.buser;
//            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow(resp));
//          endaction
//      endseq
//    endpar
//  );
//  Stmt priority_check = (
//    par
//      seq
//        action
//          let stime <- $stime;
//          ARReq request = Axi4_rd_addr {araddr:'h000, arlen:0, arsize:2, arburst:axburst_incr};
//          for (Integer i = 0; i<`tn_num_masters; i = i + 1) begin
//            request.araddr = request.araddr + 'h100;
//            inst1.m_fifo[i].i_rd_addr.enq(request);
//            $display("[%10d]\tSending Rd Req [%d]",$time, i, fshow_axi4_rd_addr(request));
//          end
//        endaction
//        action
//          let stime <- $stime;
//          ARReq request = Axi4_rd_addr {araddr:'h1500, arlen:0, arsize:2, arburst:axburst_incr};
//          for (Integer i = 0; i<`tn_num_masters; i = i + 1) begin
//            request.araddr = request.araddr + 'h100;
//            inst1.m_fifo[i].i_rd_addr.enq(request);
//            $display("[%10d]\tSending Rd Req [%d]",$time, i, fshow_axi4_rd_addr(request));
//          end
//        endaction
//      endseq
//      par
//        for(iter <= 1; iter <= 2; iter <= iter + 1)
//          action
//            await (inst1.m_fifo[0].o_rd_data.notEmpty);
//            let resp = inst1.m_fifo[0].o_rd_data.first;
//            inst1.m_fifo[0].o_rd_data.deq;
//            let stime <- $stime;
//            let diff_time = stime - resp.ruser;
//            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow(resp));
//          endaction
//        for(iter1 <= 1; iter1 <= 2; iter1 <= iter1 + 1)
//          action
//            await (inst1.m_fifo[1].o_rd_data.notEmpty);
//            let resp = inst1.m_fifo[1].o_rd_data.first;
//            inst1.m_fifo[1].o_rd_data.deq;
//            let stime <- $stime;
//            let diff_time = stime - resp.ruser;
//            $display("[%10d]\tCyc:%5d Revieved Resp:",$time, diff_time/10, fshow(resp));
//          endaction
//      endpar
//    endpar
//  );

  mkAutoFSM(seq
    check1;
    /*requests;
    priority_check;*/
    $finish(0);
  endseq);
  
endmodule:mkTb

endpackage

