// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.
/*
Author: Neel Gala
Email id: neelgala@incoresemi.com
Details:
*/
package APB_Types;

import FIFOF          :: * ;
import Vector         :: * ;
import FIFOF          :: * ;
import SpecialFIFOs   :: * ;
import Connectable    :: * ;
import DefaultValue   :: * ;
import Semi_FIFOF     :: * ;
import EdgeFIFOFs     :: * ;
import DReg           :: * ;

`include "Logger.bsv"


// PROT
typedef Bit #(3)  APB_Prot;

Bit #(1)  apbprot_0_unpriv     = 0;    Bit #(1) apbprot_0_priv       = 1;
Bit #(1)  apbprot_1_secure     = 0;    Bit #(1) apbprot_1_non_secure = 1;
Bit #(1)  apbprot_2_data       = 0;    Bit #(1) apbprot_2_instr      = 1;

typedef enum {IDLE, SETUP, ACCESS} State deriving(Bits, FShow, Eq);

// APB protocol interfaces
// ---------------------------------
interface APB_Master_IFC#(  numeric type wd_addr, 
                            numeric type wd_data,
                            numeric type wd_user );

  // outputs from the master 
  // -------------------------
  (*always_ready, result = "PADDR"  *) method Bit#(wd_addr)           m_paddr;
  (*always_ready, result = "PROT"   *) method Bit#(3)                 m_prot;
  (*always_ready, result = "PENABLE"*) method Bool                    m_penable;
  (*always_ready, result = "PWRITE" *) method Bool                    m_pwrite;
  (*always_ready, result = "PWDATA" *) method Bit#(wd_data)           m_pwdata;
  (*always_ready, result = "PSTRB"  *) method Bit#(TDiv#(wd_data,8))  m_pstrb;
  (*always_ready, result = "PSEL"   *) method Bool                    m_psel;
  (*always_ready, result = "PUSER"  *) method Bit#(wd_user)           m_puser;

  // inputs to the master 
  // -------------------------
  (*always_ready, always_enabled, prefix="" *)
  method Action m_pready ((* port= "PREADY"  *) Bool          pready, 
                          (* port= "PRDATA"  *) Bit#(wd_data) prdata,
                          (* port= "PSLVERR" *) Bool          pslverr,
                          (* port= "PUSER"   *) Bit#(wd_user) puser ) ;

endinterface:APB_Master_IFC

interface APB_Slave_IFC#( numeric type wd_addr, 
                          numeric type wd_data,
                          numeric type wd_user );
  // inputs to the slave
  (*always_ready, always_enabled, prefix="" *)
  method Action s_paddr((* port= "PADDR"   *)   Bit#(wd_addr)           paddr,
                        (* port= "PROT"    *)   Bit#(3)                 prot,
                        (* port= "PENABLE" *)   Bool                    penable,
                        (* port = "PWRITE" *)   Bool                    pwrite,
                        (* port = "PWDATA" *)   Bit#(wd_data)           pwdata,
                        (* port = "PSTRB"  *)   Bit#(TDiv#(wd_data,8))  pstrb,
                        (* port = "PSEL"   *)   Bool                    psel ,
                        (* port = "PUSER"  *)   Bit#(wd_user)           puser );

  // outputs from slave
  (*always_ready, result = "PREADY" *) method Bool                      s_pready;
  (*always_ready, result = "PRDATA" *) method Bit#(wd_data)             s_prdata;
  (*always_ready, result = "PSLVERR"*) method Bool                      s_pslverr;
  (*always_ready, result = "PUSER"  *) method Bit#(wd_user)             s_puser;


endinterface:APB_Slave_IFC
// ---------------------------------

// Request and Response Structures
// ---------------------------------
typedef struct{
  Bit#(wd_addr)           paddr;
  Bit#(3)                 prot;
  Bool                    pwrite;
  Bit#(wd_data)           pwdata;
  Bit#(TDiv#(wd_data,8))  pstrb;
  Bit#(wd_user)           puser;
} APB_Request #(numeric type wd_addr, 
                numeric type wd_data, 
                numeric type wd_user ) deriving(Bits, FShow, Eq);

typedef struct{
  Bit#(wd_data)           prdata;
  Bool                    pslverr;
  Bit#(wd_user)           puser;
} APB_Response #( numeric type wd_data, 
                  numeric type wd_user) deriving(Bits, FShow, Eq);
// ---------------------------------

// FMT functions for better display
// --------------------------------
/*doc:func: */
function Fmt fshow_APB_Write (Bool x);
  Fmt result = ?;
  if (x) result = $format("write");
  else   result = $format("read");
  return result;
endfunction:fshow_APB_Write

/*doc:func: */
function Fmt fshow_APB_Slverr (Bool x);
  Fmt result = ?;
  if (x) result = $format("slverr");
  else   result = $format("okay");
  return result;
endfunction:fshow_APB_Slverr

/*doc:func: */
function Fmt fshow_APB_Req (APB_Request #(wd_addr, wd_data, wd_user) x);
  Fmt result = ($format ("{paddr:%0h,", x.paddr)
		          + $format ("prot:%0d", x.prot)
		          + $format (",")
  		        + fshow_APB_Write (x.pwrite));
  if (x.pwrite)
    result = result + ($format(",data:%h",x.pwdata)+
                       $format(",strb:%b",x.pstrb));

	result = result	 + $format ("}");
  return result;
endfunction:fshow_APB_Req

/*doc:func: */
function Fmt fshow_APB_Resp (APB_Response #(wd_data, wd_user) x);
  Fmt result = $format("{prdata:%h pslverr:}",x.prdata, fshow_APB_Slverr(x.pslverr));
  return result;
endfunction:fshow_APB_Resp
// --------------------------------

// Server and Client side interfaces 
// ---------------------------------
interface APB_Server_IFC #(numeric type wd_addr,
                           numeric type wd_data,
                           numeric type wd_user );

  interface FIFOF_I #(APB_Request #(wd_addr, wd_data, wd_user))  i_request;
  interface FIFOF_O #(APB_Response #(wd_data, wd_user))          o_response;
endinterface:APB_Server_IFC

interface APB_Client_IFC #(numeric type wd_addr,
                           numeric type wd_data,
                           numeric type wd_user );

  interface FIFOF_I #(APB_Response #(wd_data, wd_user))          i_response;
  interface FIFOF_O #(APB_Request  #(wd_addr, wd_data, wd_user)) o_request;
endinterface:APB_Client_IFC
// ---------------------------------

// Xactor interfaces
// --------------------------------
interface APB_Master_Xactor #(  numeric type wd_addr, 
                                numeric type wd_data,
                                numeric type wd_user);

  interface APB_Master_IFC #(wd_addr, wd_data, wd_user) apb_side;
  interface APB_Server_IFC #(wd_addr, wd_data, wd_user) fifo_side;
endinterface:APB_Master_Xactor
  
interface APB_Slave_Xactor #(  numeric type wd_addr, 
                                numeric type wd_data,
                                numeric type wd_user);

  interface APB_Slave_IFC #(wd_addr, wd_data, wd_user) apb_side;
  interface APB_Client_IFC #(wd_addr, wd_data, wd_user) fifo_side;
endinterface:APB_Slave_Xactor
// --------------------------------

module mkAPB_Master_Xactor (APB_Master_Xactor #(wd_addr, wd_data, wd_user));

  /*doc:fifo: this fifo holds the incoming request from the master */
  FIFOF#(APB_Request #(wd_addr, wd_data, wd_user))  ff_request    <- mkBypassFIFOF();
  /*doc:fifo: this fifo holds the response to be sent to the master */
  FIFOF#(APB_Response #(wd_data, wd_user))          ff_response   <- mkLFIFOF();

  /*doc:reg: register to control the current state of transfer */
  Reg#(State)                                       rg_state      <- mkReg(IDLE);
  /*doc:reg: register to hold the request to drive the protocol interface */
  Reg#(APB_Request #(wd_addr, wd_data, wd_user))    rg_request    <- mkReg(unpack(0));
  /*doc:reg: register to drive the psel interface */
  Reg#(Bool)                                        rg_sel        <- mkReg(False);
  /*doc:reg: register to drive the penable interface */
  Reg#(Bool)                                        rg_enable     <- mkReg(False);

  /*doc:wire: */
  Wire#(Bit#(wd_data))                              wr_prdata     <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_pready     <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_pslverr    <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bit#(wd_user))                              wr_puser      <- mkBypassWire;

  /*doc:rule: go from idle state to setup state*/
  rule rl_idle_to_setup (ff_request.notEmpty && rg_state == IDLE );
    let req = ff_request.first;
    ff_request.deq;
    rg_request <= APB_Request { paddr : req.paddr,
                               prot   : req.prot,
                               pwrite : req.pwrite,
                               pwdata : req.pwdata,
                               pstrb  : req.pstrb,
                               puser  : req.puser };
    rg_sel <= True;
    rg_enable <= False;
    rg_state <= SETUP;
  endrule:rl_idle_to_setup

  /*doc:rule: setup state of the transfer*/
  rule rl_setup_state (rg_state == SETUP);
    rg_enable <= True;
    rg_state  <= ACCESS;
  endrule:rl_setup_state

  /*doc:rule: when there is no more pending request go back to idle state*/
  rule rl_access_to_idle (rg_state == ACCESS && wr_pready && !ff_request.notEmpty);
    rg_enable <= False;
    rg_sel    <= False;
    rg_state  <= SETUP;
    ff_response.enq( APB_Response { prdata  : wr_prdata, 
                                    pslverr : wr_pslverr,
                                    puser   : wr_puser } );
  endrule:rl_access_to_idle

  /*doc:rule: when there is pending requests, go to setup state instead of idle*/
  rule rl_access_to_setup (rg_state == ACCESS && wr_pready && ff_request.notEmpty);
    
    let req = ff_request.first;
    ff_request.deq;
    rg_request <= APB_Request { paddr : req.paddr,
                               prot   : req.prot,
                               pwrite : req.pwrite,
                               pwdata : req.pwdata,
                               pstrb  : req.pstrb,
                               puser  : req.puser };
    rg_sel <= True;
    rg_enable <= False;
    ff_response.enq( APB_Response { prdata  : wr_prdata, 
                                    pslverr : wr_pslverr,
                                    puser   : wr_puser } );
    rg_state <= SETUP ;
  endrule:rl_access_to_setup

  interface fifo_side = interface APB_Server_IFC
    interface i_request  = to_FIFOF_I (ff_request);
    interface o_response = to_FIFOF_O (ff_response);
  endinterface;

  interface apb_side = interface APB_Master_IFC
    method m_paddr    =  rg_request.paddr;
    method m_prot     =  rg_request.prot;
    method m_penable  =  rg_enable;
    method m_pwrite   =  rg_request.pwrite;
    method m_pwdata   =  rg_request.pwdata;
    method m_pstrb    =  rg_request.pstrb;
    method m_psel     =  rg_sel;
    method m_puser    =  rg_request.puser;
    method Action m_pready (Bool pready,  Bit#(wd_data) prdata,
                            Bool pslverr, Bit#(wd_user) puser ) ;
      wr_pready   <= pready;
      wr_prdata   <= prdata;
      wr_puser    <= puser;
      wr_pslverr  <= pslverr;
    endmethod
  endinterface;

endmodule:mkAPB_Master_Xactor

module mkAPB_Slave_Xactor (APB_Slave_Xactor #(wd_addr, wd_data, wd_user));
  
  /*doc:fifo: this fifo holds the incoming request from the master */
  FIFOF#(APB_Request #(wd_addr, wd_data, wd_user))  ff_request    <- mkLFIFOF();
  /*doc:fifo: this fifo holds the response to be sent to the master */
  FIFOF#(APB_Response #(wd_data, wd_user))          ff_response   <- mkBypassFIFOF();

  /*doc:reg: */
  Reg#(APB_Response #(wd_data, wd_user))            rg_response   <- mkReg(unpack(0));
  Reg#(Bool)                                        rg_pready     <- mkDReg(False);

  Wire#(APB_Request #(wd_addr, wd_data, wd_user))   wr_request    <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_psel       <- mkBypassWire;
  /*doc:wire: */
  Wire#(Bool)                                       wr_penable    <- mkBypassWire;

  /*doc:reg: */
  Reg#(Bool) rg_wait <- mkReg(False);

  /*doc:rule: rule to capture the request from the master and send to the slave fifo side*/
  rule rl_capture_request (!rg_wait && wr_psel && !wr_penable && ff_request.notFull);
    ff_request.enq(wr_request);
    rg_wait <= True;
  endrule:rl_capture_request

  rule rl_send_response (rg_wait && wr_psel && wr_penable && ff_response.notEmpty);
    let resp = ff_response.first;
    ff_response.deq;
    rg_response <= APB_Response{pslverr: resp.pslverr,
                               prdata  : resp.prdata,
                               puser   : resp.puser };
    rg_pready <= True;
    rg_wait   <= False;
  endrule

  interface fifo_side = interface APB_Client_IFC
    interface i_response = to_FIFOF_I (ff_response);
    interface o_request  = to_FIFOF_O (ff_request);
  endinterface;
  interface apb_side = interface APB_Slave_IFC
    method Action s_paddr( Bit#(wd_addr)           paddr,
                           Bit#(3)                 prot,
                           Bool                    penable,
                           Bool                    pwrite,
                           Bit#(wd_data)           pwdata,
                           Bit#(TDiv#(wd_data,8))  pstrb,
                           Bool                    psel ,
                           Bit#(wd_user)           puser   );
      wr_request <= APB_Request {paddr  : paddr,       
                                prot   : prot,
                                pwrite : pwrite,
                                pwdata : pwdata,
                                pstrb  : pstrb,
                                puser  : puser   };

      wr_psel    <=  psel;
      wr_penable <=  penable;
    endmethod
    // outputs from slave
    method s_pready  = rg_pready;
    method s_prdata  = rg_response.prdata;
    method s_pslverr = rg_response.pslverr;
    method s_puser   = rg_response.puser;
  endinterface;
endmodule:mkAPB_Slave_Xactor

module mkAPB_Err(APB_Slave_IFC #(wd_addr, wd_data, wd_user));
    method Action s_paddr( Bit#(wd_addr)           paddr,
                           Bit#(3)                 prot,
                           Bool                    penable,
                           Bool                    pwrite,
                           Bit#(wd_data)           pwdata,
                           Bit#(TDiv#(wd_data,8))  pstrb,
                           Bool                    psel ,
                           Bit#(wd_user)           puser   );
      noAction;
    endmethod
    // outputs from slave
    method s_pready  = True;
    method s_prdata  = ?;
    method s_pslverr = True;
    method s_puser   = ?;
endmodule:mkAPB_Err

module mkTb(Empty);

endmodule:mkTb

endpackage:APB_Types

