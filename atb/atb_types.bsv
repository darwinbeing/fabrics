// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package atb_types;

// ================================================================
// Facilities for ARM ATB, to pass trace data
//  as Master: One that generates Trace Data onto ATB bus
//  as Slave : One that receives Trace Data from ATB bus.

// Ref: ARM document:
//   AMBA 4 ATB Protocol Specification
//   ATBv1.0 and ATBv1.1
//   ARM IHI 0032B (ID040412)
//   Issue B, 28 March 2012

// See export list below

// ================================================================
// Exports

// BSV library imports

import FIFOF       :: *;
import Connectable :: *;
import DefaultValue :: * ;

`include "Logger.bsv"

// ----------------
// BSV additional libs

import Semi_FIFOF :: *;
import EdgeFIFOFs :: *;

// ****************************************************************
// ****************************************************************
// Section: RTL-level interfaces
// ****************************************************************
// ****************************************************************

// ================================================================
// These are the signal-level interfaces for an ATB master.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_atb_master #(numeric type wd_data);

    // Data Channel
    (* always_ready, result="ATDATA" *)  method Bit #(wd_data) m_atdata;                    // out
    (* always_ready, result="ATBYTES" *) method Bit #(TSub#(TLog#(wd_data),3)) m_atbytes;   // out
    (* always_ready, result="ATID" *)    method Bit #(7) m_atid;                            // out

    // Handshake Channel
    (* always_ready, always_enabled, prefix="" *)
    method Action m_atready ((* port="ATREADY" *) Bool  atready);                           // in
    (* always_ready, result="ATVALID" *) method Bool    m_atvalid;                          // out

    // Trigger Channel
    (* always_ready, result="AFREADY" *)  method Bool m_afready;                            // out
    (* always_ready, always_enabled, prefix = "" *)
    method Action m_afvalid ((* port="AFVALID" *) Bool afvalid);                            // in
    (* always_ready, always_enabled, prefix = "" *)
    method Action m_syncreq ((* port="SYNCREQ" *) Bool syncreq );                           // in

endinterface: Ifc_atb_master

// ================================================================
// These are the signal-level interfaces for an ATB slave.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_atb_slave #(numeric type wd_data);
    // Data Channel
    (* always_ready, always_enabled, prefix = "" *)
    method Action m_atvalid ((* port="ATVALID" *) Bool atvalid,                             // in
                (* port="ATID" *)  Bit #(7)       atid,                                     // in
                (* port="ATDATA" *)  Bit #(wd_data) atdata,                                 // in
                (* port="ATBYTES" *)  Bit #(TSub#(TLog#(wd_data),3)) atbytes);              // in
    (* always_ready, result="ATREADY" *) method Bool m_atready;                             // out

    // Trigger Channel
    (* always_ready, always_enabled, prefix = "" *)
    method Action m_afready ((* port="AFREADY" *) Bool afready);                            // in
    (* always_ready, result="AFVALID" *) method Bool m_afvalid;                             // out
    (* always_ready, result="SYNCREQ" *)  method Bool m_syncreq;                            // out

endinterface: Ifc_atb_slave

// ================================================================
// Connecting signal-level interfaces

instance Connectable #(Ifc_atb_master #(wd_data), Ifc_atb_slave  #(wd_data));
    module mkConnection #(Ifc_atb_master #(wd_data) atbm, Ifc_atb_slave  #(wd_data) atbs) (Empty);

        (* fire_when_enabled, no_implicit_conditions *)
        rule rl_signals;
            atbs.m_atvalid (atbm.m_atvalid, atbm.m_atid, atbm.m_atdata, atbm.m_atbytes);
            atbm.m_atready (atbs.m_atready);
            atbs.m_afready (atbm.m_afready);
            atbm.m_afvalid (atbs.m_afvalid);
            atbm.m_syncreq (atbs.m_syncreq);
        endrule:rl_signals

    endmodule:mkConnection
endinstance:Connectable

instance Connectable #(Ifc_atb_slave  #(wd_data), Ifc_atb_master #(wd_data));
    module mkConnection #(Ifc_atb_slave  #(wd_data) atbs, Ifc_atb_master #(wd_data) atbm) (Empty);
        mkConnection(atbm, atbs);
    endmodule:mkConnection
endinstance:Connectable

// ================================================================
// ATB dummy master: never produces requests, never accepts responses

Ifc_atb_master #(wd_data) dummy_atb_master_ifc = interface Ifc_atb_master
        // Data Signals
    method Bool           m_atvalid = False;              // out
    method Bit #(wd_data) m_atdata  = ?;                  // out
    method Bit #(7)       m_atid    = ?;                  // out
    method Bit #(TSub#(TLog#(wd_data),3)) m_atbytes  = ?; // out
    method Action m_atready (Bool atready) = noAction;    // in

    // Flush Signals
    method Bool           m_afready = False;              // out
    method Action m_afvalid (Bool afvalid) = noAction;    // in

    // Synchronization Requests
    method Action m_syncreq (Bool syncreq) = noAction;    // in
endinterface;

// ================================================================
// ATB dummy slave: never accepts requests, never produces responses

Ifc_atb_slave #(wd_data) dummy_atb_slave_ifc = interface Ifc_atb_slave
    // Data Signals
    method Action m_atvalid (Bool           atvalid,
                             Bit #(7)       atid,
                             Bit #(wd_data) atdata,
                             Bit #(TSub#(TLog#(wd_data),3)) atbytes);
          noAction;
    endmethod:m_atvalid

    method Bool m_atready;
      return False;
    endmethod:m_atready

    // Flush Control Signals
    method Action m_afready (Bool   afready);
      noAction;
    endmethod:m_afready

    method Bool m_afvalid;
      return False;
    endmethod:m_afvalid

    method Bool m_syncreq;
       return False;
    endmethod:m_syncreq
  endinterface;

// ****************************************************************
// ****************************************************************
// Section: Higher-level FIFO-like interfaces and transactors
// ****************************************************************
// ****************************************************************

// ================================================================
// Help function: fn_crg_and_rg_to_FIFOF_I
// In the modules below, we use a crg_full and a rg_data to represent a fifo.
// These functions convert these to FIFOF_I and FIFOF_O interfaces.

function FIFOF_I #(t) fn_crg_and_rg_to_FIFOF_I (Reg #(Bool) rg_full, Reg #(t) rg_data);
    return interface FIFOF_I;
        method Action enq (t x) if (! rg_full);
            rg_full <= True;
            rg_data <= x;
        endmethod
        method Bool notFull;
            return (! rg_full);
        endmethod
    endinterface;
endfunction:fn_crg_and_rg_to_FIFOF_I

function FIFOF_O #(t) fn_crg_and_rg_to_FIFOF_O (Reg #(Bool) rg_full, Reg #(t) rg_data);
    return interface FIFOF_O;
        method t first () if (rg_full);
            return rg_data;
        endmethod
        method Action deq () if (rg_full);
            rg_full <= False;
        endmethod
        method notEmpty;
            return rg_full;
        endmethod
    endinterface;
endfunction:fn_crg_and_rg_to_FIFOF_O

// ================================================================
// Higher-level types for payloads (rather than just bits)

typedef struct{
  Integer tr_data_depth;
  } QueueSize ;
instance DefaultValue #(QueueSize);
  defaultValue = QueueSize{ tr_data_depth: 2};
endinstance

// ATB Payload
typedef struct {
    Bit #(wd_data)                  atdata;
    Bit #(7)                        atid;
    Bit #(TSub#(TLog#(wd_data),3))  atbytes;
    } Atb_payload #(numeric type wd_data)
deriving (Bits, FShow);

// ----------------

function Fmt fshow_atb_payload (Atb_payload #(wd_data) x);
   Fmt result = ($format ("{atid: %0h, atbytes: %d, atdata: %h", x.atid, x.atbytes, x.atdata)
         + $format ("}"));
   return result;
endfunction:fshow_atb_payload

// ================================================================
// ATB buffer

// ----------------
// Server-side interface accepts requests and yields responses

interface Ifc_atb_server  #(numeric type wd_data);
    interface FIFOF_I #(Atb_payload #(wd_data)) i_tr_data;
endinterface

// ----------------
// Client-side interface yields requests and accepts responses

interface Ifc_atb_client  #(numeric type wd_data);
    interface FIFOF_O #(Atb_payload #(wd_data)) o_tr_data;
endinterface

// ----------------
// A Buffer has a server-side and a client-side, and a reset

interface Ifc_atb_buffer  #(numeric type wd_data);
    method Action reset;
    interface Ifc_atb_server #(wd_data) server_side;
    interface Ifc_atb_client #(wd_data) client_side;
endinterface

// ----------------------------------------------------------------

module mkatb_buffer (Ifc_atb_buffer #(wd_data));

    FIFOF #(Atb_payload #(wd_data))    f_tr_data <- mkFIFOF;

    method Action reset;
       f_tr_data.clear;
    endmethod

    interface Ifc_atb_server server_side;
       interface i_tr_data = to_FIFOF_I (f_tr_data);
    endinterface

    interface Ifc_atb_client client_side;
       interface o_tr_data = to_FIFOF_O (f_tr_data);
    endinterface
endmodule

module mkatb_buffer_2 (Ifc_atb_buffer #(wd_data));

    FIFOF #(Atb_payload #(wd_data)) f_tr_data <- mkMaster_EdgeFIFOF;
    //FIFOF #(Atb_payload #(wd_data)) f_rd_data <- mkSlave_EdgeFIFOF;

    method Action reset;
       f_tr_data.clear;
    endmethod

    interface Ifc_atb_server server_side;
       interface i_tr_data = to_FIFOF_I (f_tr_data);
    endinterface

    interface Ifc_atb_client client_side;
       interface o_tr_data = to_FIFOF_O (f_tr_data);
    endinterface
endmodule

// ================================================================
// Master transactor interface

interface Ifc_atb_master_xactor #(numeric type wd_data);
    method Action reset;
    interface Ifc_atb_master #(wd_data) atb_side;       // ATB side
    interface Ifc_atb_server #(wd_data) fifo_side;     // Server side
endinterface: Ifc_atb_master_xactor

// ----------------------------------------------------------------
// Master transactor
// This version uses FIFOFs for total decoupling.

module mkatb_master_xactor #(parameter QueueSize sz) (Ifc_atb_master_xactor #(wd_data));

    Bool unguarded = True;
    Bool guarded   = False;

    // These FIFOs are guarded on BSV side, unguarded on AXI side
   FIFOF #(Atb_payload #(wd_data)) f_tr_data <- mkGSizedFIFOF (guarded, unguarded, sz.tr_data_depth);

    // ----------------------------------------------------------------
    // INTERFACE

    method Action reset;
      f_tr_data.clear;
    endmethod

    // ATB side
    interface atb_side = interface Ifc_atb_master;
        // Data Signals
        method Bool           m_atvalid = f_tr_data.notEmpty;
        method Bit #(wd_data) m_atdata  = f_tr_data.first.atdata;
        method Bit #(7)       m_atid    = f_tr_data.first.atid;
        method Bit #(TSub#(TLog#(wd_data),3)) m_atbytes  = f_tr_data.first.atbytes;
        method Action m_atready (Bool atready);
            if (f_tr_data.notEmpty && atready)
                f_tr_data.deq;
        endmethod

        //TODO: FLush and Sync signals

    endinterface;

    interface fifo_side = interface Ifc_atb_server
      interface i_tr_data = to_FIFOF_I (f_tr_data);
    endinterface;

endmodule: mkatb_master_xactor

// ----------------------------------------------------------------
// Master transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.

module mkatb_master_xactor_2 (Ifc_atb_master_xactor #(wd_data));

    // Each crg_full, rg_data pair below represents a 1-element fifo.

    Array #(Reg #(Bool))           crg_tr_data_full <- mkCReg (3, False);
    Reg #(Atb_payload #(wd_data))  rg_tr_addr <- mkRegU;


    // The following CReg port indexes specify the relative scheduling of:
    //     {first,deq,notEmpty}    {enq,notFull}    clear

    // TODO: 'deq/enq/clear = 1/2/0' is unusual, but eliminates a
    // scheduling cycle in Piccolo's DCache.  Normally should be 0/1/2.

    Integer port_deq   = 1;
    Integer port_enq   = 2;
    Integer port_clear = 0;

    // ----------------------------------------------------------------
    // INTERFACE

    method Action reset;
       crg_tr_data_full [port_clear] <= False;
    endmethod

    // ATB side
    interface atb_side = interface Ifc_atb_master;
               // Wr Addr channel
        method Bool           m_atvalid = crg_tr_data_full [port_deq];
        method Bit #(wd_data) m_atdata  = rg_tr_addr.atdata;
        method Bit #(7)       m_atid    = rg_tr_addr.atid;
        method Bit #(TSub#(TLog#(wd_data),3)) m_atbytes  = rg_tr_addr.atbytes;
        method Action m_atready (Bool atready);
            if (crg_tr_data_full [port_deq] && atready)
                crg_tr_data_full [port_deq] <= False;    // deq
        endmethod

        //TODO: Flush and Sync signals
    endinterface;

    // FIFOF side
    interface fifo_side = interface Ifc_atb_server
        interface i_tr_data = fn_crg_and_rg_to_FIFOF_I (crg_tr_data_full [port_enq], rg_tr_addr);
    endinterface;
endmodule: mkatb_master_xactor_2

// ================================================================
// Slave transactor interface

interface Ifc_atb_slave_xactor #(numeric type wd_data);
    method Action reset;
    interface Ifc_atb_slave #(wd_data) atb_side;    // ATB side
    interface Ifc_atb_client #(wd_data) fifo_side;    // FIFOF side
endinterface: Ifc_atb_slave_xactor

// ----------------------------------------------------------------
// Slave transactor
// This version uses FIFOFs for total decoupling.

module mkatb_slave_xactor #(parameter QueueSize sz) (Ifc_atb_slave_xactor #(wd_data));

    Bool unguarded = True;
    Bool guarded   = False;

    // These FIFOs are guarded on BSV side, unguarded on AXI side
    FIFOF #(Atb_payload #(wd_data))   f_tr_data <- mkGSizedFIFOF (unguarded, guarded, sz.tr_data_depth);

    // ----------------------------------------------------------------
    // INTERFACE

    method Action reset;
        f_tr_data.clear;
    endmethod

    // ATB side
    interface atb_side = interface Ifc_atb_slave;
        // Data Signals
        method Action m_atvalid (Bool atvalid, Bit #(7) atid, Bit #(wd_data) atdata,
                                 Bit #(TSub#(TLog#(wd_data),3)) atbytes);
        if (atvalid && f_tr_data.notFull)
          f_tr_data.enq (Atb_payload {atid: atid, atdata: atdata, atbytes: atbytes});
        endmethod

        method Bool m_atready;
            return f_tr_data.notFull;
        endmethod

        //TODO: Flush and Sync signals
    endinterface;

    // FIFOF side
    interface fifo_side = interface Ifc_atb_client
        interface o_tr_data = to_FIFOF_O (f_tr_data);
    endinterface;
endmodule: mkatb_slave_xactor

// ----------------------------------------------------------------
// Slave transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.

module mkatb_slave_xactor_2 (Ifc_atb_slave_xactor #(wd_data));

    // Each crg_full, rg_data pair below represents a 1-element fifo.

    // These FIFOs are guarded on BSV side, unguarded on AXI side
    Array #(Reg #(Bool))           crg_tr_data_full <- mkCReg (3, False);
    Reg #(Atb_payload #(wd_data))  rg_tr_data <- mkRegU;

    // The following CReg port indexes specify the relative scheduling of:
    //     {first,deq,notEmpty}    {enq,notFull}    clear
    Integer port_deq   = 0;
    Integer port_enq   = 1;
    Integer port_clear = 2;

    // ----------------------------------------------------------------
    // INTERFACE

    method Action reset;
       crg_tr_data_full [port_clear] <= False;
    endmethod

    // ATB side
    interface atb_side = interface Ifc_atb_slave;
            // Data Signals
        method Action m_atvalid (Bool atvalid, Bit #(7) atid, Bit #(wd_data) atdata,
                                 Bit #(TSub#(TLog#(wd_data),3)) atbytes);
            if (atvalid && (! crg_tr_data_full [port_enq])) begin
                crg_tr_data_full [port_enq] <= True;    // enq
                rg_tr_data <= Atb_payload {atid   : atid,
                                           atdata : atdata,
                                           atbytes: atbytes };
            end
        endmethod

        method Bool m_atready;
            return (! crg_tr_data_full [port_enq]);
        endmethod

        //TODO: Flush and Sync signals
    endinterface;

    // FIFOF side
    interface fifo_side = interface Ifc_atb_client
      interface o_tr_data = fn_crg_and_rg_to_FIFOF_O (crg_tr_data_full [port_deq], rg_tr_data);
    endinterface;
endmodule: mkatb_slave_xactor_2

// ============================NO ERROR RESPONSES FOR ATB ======================

endpackage:atb_types
