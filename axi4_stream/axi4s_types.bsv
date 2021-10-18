/*
Copyright (c) 2021, IIT Madras
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

*  Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
*  Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
*  Neither the name of IIT Madras  nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
*/
// Copyright (c) 2013-19 Bluespec, Inc.  All Rights Reserved

package axi4s_types;

// ================================================================
// Facilities for ARM AXI4-Stream

// Ref: ARM document:
//	 AMBA AXI and ACE Protocol Specification
//	 AXI4 Stream Interface

// See export list below

// ================================================================
// Exports

// BSV library imports

import FIFOF       :: *;
import Connectable :: *;
import DefaultValue :: *;

`include "Logger.bsv"

// ----------------
// BSV additional libs

import Semi_FIFOF :: *;
import EdgeFIFOFs :: *;

typedef Bit #(3)  Axi4s_size;

Axi4s_size  axissize_1   = 3'b_000;
Axi4s_size  axissize_2   = 3'b_001;
Axi4s_size  axissize_4   = 3'b_010;
Axi4s_size  axissize_8   = 3'b_011;
Axi4s_size  axissize_16  = 3'b_100;
Axi4s_size  axissize_32  = 3'b_101;
Axi4s_size  axissize_64  = 3'b_110;
Axi4s_size  axissize_128 = 3'b_111;


// ****************************************************************
// ****************************************************************
// Section: RTL-level interfaces
// ****************************************************************
// ****************************************************************

// ================================================================
// These are the signal-level interfaces for an AXI4-Stream master.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_axi4s_master#(numeric type wd_tdest,
				 numeric type wd_data,
				 numeric type wd_tuser,
				numeric type wd_tid);

   (* always_ready, result="TVALID" *) method Bool           m_tvalid;                                // out
   (* always_ready, result="TDATA" *)  method Bit #(8*wd_tdata) m_tdata;                                 // out
   (* always_ready, result="TSTRB" *)  method Bit #(wd_tdata) m_tstrb;                                 // out
   (* always_ready, result="TKEEP" *)  method Bit #(wd_tdata)       m_tkeep;                                 // out
   (* always_ready, result="TLAST" *)   method Bool       m_tlast;		                             // out
   (* always_ready, result="TID" *)  method Bit#(wd_tid)        m_tid;			                          // out
   (* always_ready, result="TDEST" *) method Bit #(wd_tdest)       m_tdest;			                       // out
   (* always_ready, result="TUSER" *) method Bit #(wd_tuser)          m_tuser;			                          // out

   (* always_ready, always_enabled , prefix="" *)   method Action m_tready ((* port="TREADY" *) Bool tready);    // in

endinterface: Ifc_axi4s_master

// ================================================================
// These are the signal-level interfaces for an AXI4-Stream slave.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_axi4s_slave #(numeric type wd_tdest,
				 numeric type wd_data,
				 numeric type wd_tuser,
				numeric type wd_tid);
   
   method Bool m_tready;                                                   // out


   (* always_ready, always_enabled , prefix=""*)
   method Action m_tvalid ((* port="TVALID" *) Bool                     tvalid,    // in
			   (* port="TDATA" *)  Bit #(wd_tdata)           tdata,     // in
			   (* port="TSTRB" *)  Bit #(wd_tdata) tstrb,    // in
			   (* port="TKEEP" *)  Bit #(wd_tdata) tkeep,    // in
			   (* port="TLAST" *)  Bool  tlast,
			   (* port="TID" *) Bit#(wd_tid) tid,            // in
			   (* port="TDEST" *)  Bit #(wd_tdata) tdest,    // in
			   (* port="TUSER" *)  Bit #(wd_tuser) tuser);   // in

endinterface: Ifc_axi4s_slave



// ================================================================
// Connecting signal-level interfaces


instance Connectable #(Ifc_axi4s_master #(wd_tdest,wd_tdata, wd_tuser,wd_tid),
		       Ifc_axi4s_slave  #(wd_tdest,wd_tdata, wd_tuser,wd_tid));

   module mkConnection #(Ifc_axi4s_master #(wd_tdest,wd_tdata, wd_tuser,wd_tid) axim,
			 Ifc_axi4s_slave  #(wd_tdest,wd_tdata, wd_tuser,wd_tid) axis)
		       (Empty);

      (* fire_when_enabled, no_implicit_conditions *)
      rule rl_connect;
	 axis.m_tvalid (axim.m_tvalid, axim.m_tdata, axim.m_tstrb, axim.m_tkeep, axim.m_tlast, axim.m_tid, axim.m_tdest, axim.m_tuser);
	 axim.m_tready (axis.m_tready);
      endrule

   endmodule
endinstance: Connectable

// Incase the slave is mentioned first while calling the mkConnection module

instance Connectable #(Ifc_axi4s_slave  #(wd_tdest,wd_tdata, wd_tuser,wd_tid), Ifc_axi4s_master #(wd_tdest,wd_tdata, wd_tuser,wd_tid));

   module mkConnection #(Ifc_axi4s_slave  #(wd_tdest,wd_tdata, wd_tuser,wd_tid) axis, Ifc_axi4s_master #(wd_tdest,wd_tdata, wd_tuser,wd_tid) axim)
		       (Empty);

	mkConnection(axim,axis);	
	
   endmodule
endinstance: Connectable




// ================================================================
// AXI4-Stream dummy master: never accepts response, never produces requests

Ifc_axi4s_master #(wd_tdest,wd_tdata, wd_tuser,wd_tid)
   dummy_axi4s_master_ifc = interface Ifc_axi4s_master; 
				  
   			    	method Bool m_tvalid = False;                                // out
   				method Bit #(8*wd_tdata) m_tdata = ?;                                 // out
   				method Bit #(wd_tdata) m_tstrb = ?;                                 // out
   				method Bit #(wd_tdata) m_tkeep = ?;                                 // out
   				method Bool m_tlast = ?;		                             // out
   				method Bit#(wd_tid) m_tid = ?;			                          // out
   				method Bit #(wd_tdest) m_tdest = ?;			                       // out
   				method Bit #(wd_tuser) m_tuser = ?;			                          // out

   				method Action m_tready (Bool tready);    // in
					noAction;
				endmethod

			       endinterface;


// ================================================================
// AXI4-Stream dummy slave: never accepts requests, never produces responses

Ifc_axi4s_slave #(wd_tdest,wd_tdata, wd_tuser,wd_tid)
   dummy_axi4s_slave_ifc = interface Ifc_axi4s_slave; 
				  
			   method Action m_tvalid (Bool           tvalid,
						   Bit #(wd_data) tdata,
							Bit#(wd_data) tstrb,
						   Bit #(wd_tdata) tkeep,
						   Bool tlast,
							Bit #(wd_tid) tid,
							Bit #(wd_tdata) tdest,
							Bit #(wd_tuser) tuser);
				     noAction;
				  endmethod

				  method Bool m_tready;
				     return False;
				  endmethod

			       endinterface;



// ****************************************************************
// ****************************************************************
// Section: Higher-level FIFO-like interfaces and transactors
// ****************************************************************
// ****************************************************************
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
// ================================================================

typedef struct{
  Integer wr_req_depth;
  Integer rd_req_depth;
  Integer wr_resp_depth;
  Integer rd_resp_depth;
  } QueueSize ;
instance DefaultValue #(QueueSize);
  defaultValue = QueueSize{ wr_req_depth:  2, 
                            wr_resp_depth: 2, 
                            rd_req_depth:  2, 
                            rd_resp_depth: 2};
endinstance


// AXI4 Stream structure for the FIFOs
typedef struct {

	method Bit #(8*wd_tdata) m_tdata;                                 // out
	method Bit #(wd_tdata) m_tstrb;                                 // out
	method Bit #(wd_tdata)       m_tkeep;                                 // out
	method Bool       m_tlast;		                             // out
	method Bit#(wd_tid)        m_tid;			                          // out
	method Bit #(wd_tdest)       m_tdest;			                       // out
	method Bit #(wd_tuser)          m_tuser;			                          // out

   } Axi4s #(numeric type wd_tdata,numeric type wd_tid,numeric type wd_tdest,numeric type wd_tuser)
deriving (Bits, FShow);


function Fmt fshow_axi4s_size (Axi4s_size  size);
   Fmt result = ?;
   if      (size == axissize_1)   result = $format ("sz1");
   else if (size == axissize_2)   result = $format ("sz2");
   else if (size == axissize_4)   result = $format ("sz4");
   else if (size == axissize_8)   result = $format ("sz8");
   else if (size == axissize_16)  result = $format ("sz16");
   else if (size == axissize_32)  result = $format ("sz32");
   else if (size == axissize_64)  result = $format ("sz64");
   else if (size == axissize_128) result = $format ("sz128");
   return result;
endfunction:fshow_axi4l_size



function Fmt fshow_axi4s (Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid) x);
   let result = ($format ("{tdata:%0h,tstrb:%0h,tkeep:%0h,tid:%0h,tdest:%0h,", x.tdata, x.tstrb,x.tkeep,x.tid,x.tdest)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4s


// ================================================================
// AXI4-Stream buffer

// ----------------
// Server-side interface accepts requests and yields responses

interface Ifc_axi4s_server  #(numeric type wd_tdata,numeric type wd_tid,numeric type wd_tdest,numeric type wd_tuser);

	interface FIFOF_I #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))          i_stream;

endinterface

// ----------------
// Client-side interface yields requests and accepts responses

interface Ifc_axi4s_client  #(numeric type wd_tdata,numeric type wd_tid,numeric type wd_tdest,numeric type wd_tuser);

	interface FIFOF_O #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))          o_stream;


endinterface

// ----------------
// A Buffer has a server-side and a client-side, and a reset

interface Ifc_axi4s_buffer  #(numeric type wd_tdata,numeric type wd_tid,numeric type wd_tdest,numeric type wd_tuser);

	method Action reset;
	interface Ifc_axi4s_server #(wd_tdest,wd_tdata, wd_tuser,wd_tid) server_side;
	interface Ifc_axi4s_client #(wd_tdest,wd_tdata, wd_tuser,wd_tid) client_side;

endinterface

// ----------------------------------------------------------------

module mkaxi4s_buffer (Ifc_axi4s_buffer #(wd_tdest,wd_tdata, wd_tuser,wd_tid));

	FIFOF #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))          f_stream <- mkFIFOF;

	method Action reset;
	
		f_stream.clear;

	endmethod

	interface Ifc_axi4s_server server_side;
	   interface i_stream = to_FIFOF_I (f_stream);
	endinterface

	interface Ifc_axi4s_client client_side;
	   interface o_stream = to_FIFOF_O (f_stream);
	endinterface
endmodule


module mkaxi4s_buffer_2 (Ifc_axi4s_buffer #(wd_tdest,wd_tdata, wd_tuser,wd_tid));

	FIFOF #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))          f_stream <- mkMaster_EdgeFIFOF;

	method Action reset;
	
		f_stream.clear;

	endmethod

	interface Ifc_axi4s_server server_side;
	   interface i_stream = to_FIFOF_I (f_stream);
	endinterface

	interface Ifc_axi4s_client client_side;
	   interface o_stream = to_FIFOF_O (f_stream);
	endinterface
endmodule



// ================================================================
// Master transactor interface

interface Ifc_axi4s_master_xactor #(numeric type wd_tdest,
				 numeric type wd_data,
				 numeric type wd_tuser,
				numeric type wd_tid);
   method Action reset;

   // AXI side
   interface Ifc_axi4s_master #(wd_tdest,wd_tdata, wd_tuser,wd_tid) axi4s_side;

   // Server side
   interface Ifc_axi4s_server #(wd_tdest,wd_tdata, wd_tuser,wd_tid) fifo_side;

endinterface: Ifc_axi4s_master_xactor

// ----------------------------------------------------------------
// Master transactor -- this version uses FIFOs for total decoupling

module mkaxi4s_master_xactor #(parameter QueueSize sz) (Ifc_axi4s_master_xactor #(wd_tdest,wd_tdata, wd_tuser,wd_tid));

   Bool unguarded = True;
   Bool guarded   = False;

   // These FIFOs are guarded on BSV side, unguarded on AXI side
   FIFOF #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))   f_stream <- mkGSizedFIFOF (guarded, unguarded,sz.wr_req_depth);

   // ----------------------------------------------------------------
   // INTERFACE

   method Action reset;
      f_stream.clear;
   endmethod

   interface axi4s_side = interface Ifc_axi4s_master;

			method Bool           m_tvalid = f_stream.notEmpty;                                // out
			method Bit #(8*wd_tdata) m_tdata = f_stream.first.tdata;                                 // out
			method Bit #(wd_tdata) m_tstrb = f_stream.first.tstrb;                                 // out
			method Bit #(wd_tdata)       m_tkeep = f_stream.first.tkeep;                                 // out
			method Bool       m_tlast = f_stream.first.tlast;		                             // out
			method Bit#(wd_tid)        m_tid = f_stream.first.tid;			                          // out
			method Bit #(wd_tdest)       m_tdest = f_stream.first.tdest;			                       // out
			method Bit #(wd_tuser)          m_tuser = f_stream.first.tuser;			                          // out

			method Action m_tready (Bool tready);    // in
				if (f_stream.notEmpty && tready)        // Checks if f_stream is not empty (if tvalid) and if tready is asserted
					f_stream.deq;    		// Dequeue FIFO
			endmethod
		    endinterface;

   // FIFOF side
   interface fifo_side = interface Ifc_axi4s_server;
	   interface i_stream = to_FIFOF_I (f_stream);
   endinterface;

endmodule: mkaxi4s_master_xactor


// ----------------------------------------------------------------
// Master transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.


module mkaxi4s_master_xactor_2 (Ifc_axi4s_master_xactor #(wd_tdest,wd_tdata, wd_tuser,wd_tid));


        // Each crg_full, rg_data pair below represents a 1-element fifo.

        Array #(Reg #(Bool))      crg_axi4s_full <- mkCReg (3, False); 
        Reg #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))           rg_axi4s <- mkRegU;

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
	   crg_axi4s_full [port_clear] <= False;
       endmethod

   interface axi4s_side = interface Ifc_axi4s_master;

			method Bool           m_tvalid  crg_axi4s_full [port_deq];                                // out
			method Bit #(8*wd_tdata) m_tdata = rg_axi4s.tdata;                                 // out
			method Bit #(wd_tdata) m_tstrb = rg_axi4s.tstrb;                                 // out
			method Bit #(wd_tdata)       m_tkeep = rg_axi4s.tkeep;                                 // out
			method Bool       m_tlast = rg_axi4s.tlast;		                             // out
			method Bit#(wd_tid)        m_tid = rg_axi4s.tid;			                          // out
			method Bit #(wd_tdest)       m_tdest = rg_axi4s.tdest;			                       // out
			method Bit #(wd_tuser)          m_tuser = rg_axi4s.tuser;			                          // out

			method Action m_tready (Bool tready);    // in
				if (crg_axi4s_full [port_deq] && tready)        
					crg_axi4s_full [port_deq] <= False;    		// Dequeue
			endmethod
		    endinterface;

   // FIFOF side
   interface fifo_side = interface Ifc_axi4s_server;
	   interface i_stream = fn_crg_and_rg_to_FIFOF_I (crg_axi4s_full [port_enq], rg_axi4s);
   endinterface;

endmodule: mkaxi4s_master_xactor_2





// ================================================================
// Slave transactor interface

interface Ifc_axi4s_slave_xactor #(numeric type wd_tdest,
				 numeric type wd_data,
				 numeric type wd_tuser,
				numeric type wd_tid);
   method Action reset;

   // AXI side
   interface Ifc_axi4s_slave #(wd_tdest,wd_tdata, wd_tuser,wd_tid) axi_side;

   // FIFOF side
   interface Ifc_axi4s_client #(wd_tdest,wd_tdata, wd_tuser,wd_tid) o_stream;
	   interface o_stream = to_FIFOF_O (f_stream);
   endinterface

endinterface: Ifc_axi4s_slave_xactor

// ----------------------------------------------------------------
// Slave transactor

module mkaxi4s_slave_xactor #(parameter QueueSize sz) (Ifc_axi4s_slave_xactor #(wd_tdest,wd_tdata, wd_tuser,wd_tid));

   Bool unguarded = True;
   Bool guarded   = False;

   // These FIFOs are guarded on BSV side, unguarded on AXI side
   FIFOF #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))          f_stream <- mkGSizedFIFOF (unguarded, guarded,sz.wr_req_depth);

   // ----------------------------------------------------------------
   // INTERFACE

   method Action reset;
      f_stream.clear;
   endmethod

   // AXI side

   interface axi_side = interface Ifc_axi4s_slave; 
				  
			   method Action m_tvalid (Bool           tvalid,
						   Bit #(wd_data) tdata,
							Bit#(wd_data) tstrb,
						   Bit #(wd_tdata) tkeep,
						   Bool tlast,
							Bit #(wd_tid) tid,
							Bit #(wd_tdata) tdest,
							Bit #(wd_tuser) tuser);
				     if (tvalid && f_stream.notFull)
					f_stream.enq (AXI4_Stream {tdata : tdata, tstrb : tstrb, tkeep : tkeep, tlast : tlast, tid: tid, tdest : tdest, tuser : tuser});
				  endmethod

				  method Bool m_tready;
				     return f_stream.notFull;
				  endmethod

			       endinterface;

   // FIFOF side
   interface o_stream = interface Ifc_axi4s_client
				interface to_FIFOF_O (f_stream);
			endinterface;

endmodule: mkaxi4s_slave_xactor

// ================================================================

// ----------------------------------------------------------------
// Slave transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.

module mkaxi4s_slave_xactor_2 (Ifc_axi4s_slave_xactor #(wd_tdest,wd_tdata, wd_tuser,wd_tid));

        // Each crg_full, rg_data pair below represents a 1-element fifo.

        Array #(Reg #(Bool))      crg_axi4s_full <- mkCReg (3, False); 
        Reg #(Axi4s #(wd_tdest,wd_tdata, wd_tuser,wd_tid))           rg_axi4s <- mkRegU;

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
		crg_axi4s_full[port_clear] <= False;
	endmethod

	// AXI side

	interface axi_side = interface Ifc_axi4s_slave; 
				  
			   method Action m_tvalid (Bool           tvalid,
						   Bit #(wd_data) tdata,
							Bit#(wd_data) tstrb,
						   Bit #(wd_tdata) tkeep,
						   Bool tlast,
							Bit #(wd_tid) tid,
							Bit #(wd_tdata) tdest,
							Bit #(wd_tuser) tuser);
				     if (tvalid && (!crg_axi4s_full[enq])) begin
					crg_axi4s_full[port_enq] <= True;
					rg_axi4s <= Axi4s {tdata : tdata, tstrb : tstrb, tkeep : tkeep, tlast : tlast, tid: tid, tdest : tdest, tuser : tuser};
					end
		           endmethod

				  method Bool m_tready;
				     return (!crg_axi4s_full[enq]);
				  endmethod

			       endinterface;

   // FIFOF side
   interface o_stream = interface Ifc_axi4s_client
				interface f_stream = fn_crg_and_rg_to_FIFOF_O (crg_axi4s_full [port_enq], rg_axi4s);
			endinterface;

endmodule: mkaxi4s_slave_xactor_2

endpackage : axi4s_types
