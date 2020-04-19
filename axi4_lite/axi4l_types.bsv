// Copyright (c) 2013-2019 Bluespec, Inc. see LICENSE.bluespec for details.
// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package axi4l_types;

// ================================================================
// Facilities for ARM AXI4-Lite, consisting of 5 independent channels:
//	Write Address, Write Data, Write Response, Read Address and Read Data

// Ref: ARM document:
//	 AMBA AXI and ACE Protocol Specification
//	 AXI3, AXI4, and AXI4-Lite
//	 ACE and ACE-Lite
//	 ARM IHI 0022E (ID022613)
//	 Issue E, 22 Feb 2013

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

// AxSIZE
typedef Bit #(3)  Axi4l_size;

Axi4l_size  axilsize_1   = 3'b_000;
Axi4l_size  axilsize_2   = 3'b_001;
Axi4l_size  axilsize_4   = 3'b_010;
Axi4l_size  axilsize_8   = 3'b_011;
Axi4l_size  axilsize_16  = 3'b_100;
Axi4l_size  axilsize_32  = 3'b_101;
Axi4l_size  axilsize_64  = 3'b_110;
Axi4l_size  axilsize_128 = 3'b_111;

typedef Bit #(2)  Axi4l_resp;

Axi4l_resp  axi4l_resp_okay   = 2'b_00;
Axi4l_resp  axi4l_resp_exokay = 2'b_01;
Axi4l_resp  axi4l_resp_slverr = 2'b_10;
Axi4l_resp  axi4l_resp_decerr = 2'b_11;
// ****************************************************************
// ****************************************************************
// Section: RTL-level interfaces
// ****************************************************************
// ****************************************************************

// ================================================================
// These are the signal-level interfaces for an AXI4-Lite master.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_axi4l_master #( numeric type wd_addr,
				                      numeric type wd_data,
				                      numeric type wd_user);
	// Wr Addr channel
	(* always_ready, result="AWVALID" *) method Bool           m_awvalid;    // out
	(* always_ready, result="AWADDR" *)  method Bit #(wd_addr) m_awaddr;     // out
	(* always_ready, result="AWPROT" *)  method Bit #(3)       m_awprot;     // out
	(* always_ready, result="AWUSER" *)  method Bit #(wd_user) m_awuser;     // out
	(* always_ready, always_enabled, prefix="" *)
	method Action m_awready ((* port="AWREADY" *) Bool awready);    // in

	// Wr Data channel
	(* always_ready, result="WVALID" *)  method Bool                      m_wvalid;    // out
	(* always_ready, result="WDATA" *)   method Bit #(wd_data)            m_wdata;     // out
	(* always_ready, result="WSTRB" *)   method Bit #(TDiv #(wd_data, 8)) m_wstrb;     // out
	(* always_ready, always_enabled, prefix = "" *)
	method Action m_wready ((* port="WREADY" *)  Bool wready);      // in

	// Wr Response channel
	(* always_ready, always_enabled, prefix = "" *)
	method Action m_bvalid ((* port="BVALID" *)  Bool           bvalid,    // in
			   (* port="BRESP"  *)  Bit #(2)       bresp,     // in
			   (* port="BUSER"  *)  Bit #(wd_user) buser);    // in
	(* always_ready, prefix = "", result="BREADY" *)
	method Bool m_bready;                                            // out

	// Rd Addr channel
	(* always_ready, result="ARVALID", prefix = "" *)
	method Bool            m_arvalid;                               // out
	(* always_ready, result="ARADDR" *)  method Bit #(wd_addr)  m_araddr;    // out
	(* always_ready, result="ARPROT" *)  method Bit #(3)        m_arprot;    // out
	(* always_ready, result="ARUSER" *)  method Bit #(wd_user)  m_aruser;    // out
	(* always_ready, always_enabled, prefix="" *)
	method Action m_arready ((* port="ARREADY" *) Bool arready);    // in

	// Rd Data channel
	(* always_ready, always_enabled, prefix = "" *)
	method Action m_rvalid ((* port="RVALID" *) Bool           rvalid,    // in
			   (* port="RRESP" *)  Bit #(2)       rresp,     // in
			   (* port="RDATA" *)  Bit #(wd_data) rdata,     // in
			   (* port="RUSER" *)  Bit #(wd_user) ruser);    // in
	(* always_ready, result="RREADY" *)
	method Bool m_rready;                                                 // out
endinterface: Ifc_axi4l_master

// ================================================================
// These are the signal-level interfaces for an AXI4-Lite slave.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_axi4l_slave #(numeric type wd_addr,
				                    numeric type wd_data,
				                    numeric type wd_user);
	// Wr Addr channel
	(* always_ready, always_enabled, prefix = "" *)
	method Action m_awvalid ((* port="AWVALID" *) Bool           awvalid,    // in
			    (* port="AWADDR" *)  Bit #(wd_addr) awaddr,     // in
			    (* port="AWPROT" *)  Bit #(3)       awprot,     // in
			    (* port="AWUSER" *)  Bit #(wd_user) awuser);    // in
	(* always_ready, result="AWREADY" *)
	method Bool m_awready;                                                   // out

	// Wr Data channel
	(* always_ready, always_enabled, prefix = "" *)
	method Action m_wvalid ((* port="WVALID" *) Bool                     wvalid,    // in
			   (* port="WDATA" *)  Bit #(wd_data)           wdata,     // in
			   (* port="WSTRB" *)  Bit #(TDiv #(wd_data,8)) wstrb);    // in
	(* always_ready, result="WREADY" *)
	method Bool m_wready;                                                           // out

	// Wr Response channel
	(* always_ready, result="BVALID" *)  method Bool           m_bvalid;    // out
	(* always_ready, result="BRESP" *)   method Bit #(2)       m_bresp;     // out
	(* always_ready, result="BUSER" *)   method Bit #(wd_user) m_buser;     // out
	(* always_ready, always_enabled, prefix="" *)
	method Action m_bready  ((* port="BREADY" *)   Bool bready);    // in

	// Rd Addr channel
	(* always_ready, always_enabled, prefix = "" *)
	method Action m_arvalid ((* port="ARVALID" *) Bool           arvalid,    // in
			    (* port="ARADDR" *)  Bit #(wd_addr) araddr,     // in
			    (* port="ARPROT" *)  Bit #(3)       arprot,     // in
			    (* port="ARUSER" *)  Bit #(wd_user) aruser);    // in
	(* always_ready, result="ARREADY" *)
	method Bool m_arready;                                                   // out

	// Rd Data channel
	(* always_ready, result="RVALID" *)  method Bool           m_rvalid;    // out
	(* always_ready, result="RRESP" *)   method Bit #(2)       m_rresp;     // out
	(* always_ready, result="RDATA" *)   method Bit #(wd_data) m_rdata;     // out
	(* always_ready, result="RUSER" *)   method Bit #(wd_user) m_ruser;     // out
	(* always_ready, always_enabled, prefix="" *)
	method Action m_rready  ((* port="RREADY" *)   Bool rready);    // in
endinterface: Ifc_axi4l_slave

// ================================================================
// Connecting signal-level interfaces

instance Connectable #(Ifc_axi4l_master #(wd_addr, wd_data, wd_user),
		                   Ifc_axi4l_slave  #(wd_addr, wd_data, wd_user));

	module mkConnection #(Ifc_axi4l_master #(wd_addr, wd_data, wd_user) axim,
	               			 Ifc_axi4l_slave  #(wd_addr, wd_data, wd_user) axis)
		                    (Empty);

		(* fire_when_enabled, no_implicit_conditions *)
		rule rl_wr_addr_channel;
			axis.m_awvalid (axim.m_awvalid, axim.m_awaddr, axim.m_awprot, axim.m_awuser);
			axim.m_awready (axis.m_awready);
		endrule:rl_wr_addr_channel

		(* fire_when_enabled, no_implicit_conditions *)
		rule rl_wr_data_channel;
			axis.m_wvalid (axim.m_wvalid, axim.m_wdata, axim.m_wstrb);
			axim.m_wready (axis.m_wready);
		endrule:rl_wr_data_channel

		(* fire_when_enabled, no_implicit_conditions *)
		rule rl_wr_response_channel;
			axim.m_bvalid (axis.m_bvalid, axis.m_bresp, axis.m_buser);
			axis.m_bready (axim.m_bready);
		endrule:rl_wr_response_channel

		(* fire_when_enabled, no_implicit_conditions *)
		rule rl_rd_addr_channel;
			axis.m_arvalid (axim.m_arvalid, axim.m_araddr, axim.m_arprot, axim.m_aruser);
			axim.m_arready (axis.m_arready);
		endrule:rl_rd_addr_channel

		(* fire_when_enabled, no_implicit_conditions *)
		rule rl_rd_data_channel;
			axim.m_rvalid (axis.m_rvalid, axis.m_rresp, axis.m_rdata, axis.m_ruser);
			axis.m_rready (axim.m_rready);
	  endrule:rl_rd_data_channel
	endmodule:mkConnection
endinstance:Connectable
instance Connectable #(Ifc_axi4l_slave  #(wd_addr, wd_data, wd_user),
		                   Ifc_axi4l_master #(wd_addr, wd_data, wd_user));
	module mkConnection #(Ifc_axi4l_slave  #(wd_addr, wd_data, wd_user) axis,
	               			  Ifc_axi4l_master #(wd_addr, wd_data, wd_user) axim)
		                    (Empty);
		mkConnection(axim, axis);
	endmodule:mkConnection
endinstance:Connectable

// ================================================================
// AXI4-Lite dummy master: never produces requests, never accepts responses

Ifc_axi4l_master #(wd_addr, wd_data, wd_user)
	 dummy_axi4l_master_ifc = interface Ifc_axi4l_master
				    // Wr Addr channel
			method Bool           m_awvalid = False;              // out
			method Bit #(wd_addr) m_awaddr  = ?;                  // out
			method Bit #(3)       m_awprot  = ?;                  // out
			method Bit #(wd_user) m_awuser  = ?;                  // out
			method Action m_awready (Bool awready) = noAction;    // in

			// Wr Data channel
			method Bool                      m_wvalid = False;    // out
			method Bit #(wd_data)            m_wdata = ?;         // out
			method Bit #(TDiv #(wd_data, 8)) m_wstrb = ?;         // out
			method Action m_wready (Bool wready) = noAction;      // in

			// Wr Response channel
			method Action m_bvalid (Bool           bvalid,    // in
			                        Bit #(2)       bresp,     // in
			                        Bit #(wd_user) buser);    // in
			  noAction;
			endmethod:m_bvalid
			method Bool m_bready = False;                     // out

			// Rd Addr channel
			method Bool            m_arvalid = False;             // out
			method Bit #(wd_addr)  m_araddr  = ?;                 // out
			method Bit #(3)        m_arprot  = ?;                 // out
			method Bit #(wd_user)  m_aruser  = ?;                 // out
			method Action m_arready (Bool arready) = noAction;    // in

			// Rd Data channel
			method Action m_rvalid (Bool           rvalid,    // in
			                        Bit #(2)       rresp,     // in
			                        Bit #(wd_data) rdata,     // in
			                        Bit #(wd_user) ruser);    // in
			  noAction;
			endmethod:m_rvalid
			method Bool m_rready = False;                     // out
		endinterface;

// ================================================================
// AXI4-Lite dummy slave: never accepts requests, never produces responses

Ifc_axi4l_slave #(wd_addr, wd_data, wd_user)
	dummy_axi4l_slave_ifc = interface Ifc_axi4l_slave 
			// Wr Addr channel
    method Action m_awvalid (Bool           awvalid,
				                     Bit #(wd_addr) awaddr,
				                     Bit #(3)       awprot,
				                     Bit #(wd_user) awuser);
		  noAction;
		endmethod:m_awvalid

		method Bool m_awready;
		  return False;
		endmethod:m_awready

		// Wr Data channel
		method Action m_wvalid (Bool                     wvalid,
				                    Bit #(wd_data)           wdata,
				                    Bit #(TDiv #(wd_data,8)) wstrb);
		  noAction;
		endmethod:m_wvalid

		method Bool m_wready;
		  return False;
		endmethod:m_wready

		// Wr Response channel
		method Bool m_bvalid;
		  return False;
		endmethod:m_bvalid

		method Bit #(2) m_bresp;
		  return 0;
		endmethod:m_bresp

		method Bit #(wd_user) m_buser;
		  return ?;
		endmethod:m_buser

		method Action m_bready  (Bool bready);
		  noAction;
		endmethod:m_bready

		// Rd Addr channel
		method Action m_arvalid (Bool           arvalid,
				                     Bit #(wd_addr) araddr,
				                     Bit #(3)       arprot,
				                     Bit #(wd_user) aruser);
		  noAction;
		endmethod:m_arvalid

		method Bool m_arready;
	   return False;
		endmethod:m_arready

		// Rd Data channel
		method Bool m_rvalid;
	   return False;
		endmethod:m_rvalid

		method Bit #(2) m_rresp;
	   return 0;
		endmethod:m_rresp

		method Bit #(wd_data) m_rdata;
	   return 0;
		endmethod:m_rdata

		method Bit #(wd_user) m_ruser;
	   return ?;
		endmethod:m_ruser

		method Action m_rready  (Bool rready);
	   noAction;
		endmethod:m_rready
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
// Write Address channel

typedef struct {
	Bit #(wd_addr)  awaddr;
	Bit #(3)        awprot;
	Bit #(wd_user)  awuser;
	} Axi4l_wr_addr #(numeric type wd_addr, numeric type wd_user)
deriving (Bits, FShow);

// Write Data channel

typedef struct {
	Bit #(wd_data)             wdata;
	Bit #(TDiv #(wd_data, 8))  wstrb;
	} Axi4l_wr_data #(numeric type wd_data)
deriving (Bits, FShow);

// Write Response channel

typedef struct {
	Axi4l_resp  bresp;
	Bit #(wd_user)  buser;
	} Axi4l_wr_resp #(numeric type wd_user)
deriving (Bits, FShow);

// Read Address channel

typedef struct {
	Bit #(wd_addr)  araddr;
	Bit #(3)        arprot;
	Bit #(wd_user)  aruser;
	} Axi4l_rd_addr #(numeric type wd_addr, numeric type wd_user)
deriving (Bits, FShow);

// Read Data channel

typedef struct {
	Axi4l_resp  rresp;
	Bit #(wd_data)  rdata;
	Bit #(wd_user)  ruser;
	} Axi4l_rd_data #(numeric type wd_data, numeric type wd_user)
deriving (Bits, FShow);

function Fmt fshow_axi4l_size (Axi4l_size  size);
   Fmt result = ?;
   if      (size == axilsize_1)   result = $format ("sz1");
   else if (size == axilsize_2)   result = $format ("sz2");
   else if (size == axilsize_4)   result = $format ("sz4");
   else if (size == axilsize_8)   result = $format ("sz8");
   else if (size == axilsize_16)  result = $format ("sz16");
   else if (size == axilsize_32)  result = $format ("sz32");
   else if (size == axilsize_64)  result = $format ("sz64");
   else if (size == axilsize_128) result = $format ("sz128");
   return result;
endfunction:fshow_axi4l_size

function Fmt fshow_axi4l_resp (Axi4l_resp  resp);
   Fmt result = ?;
   if      (resp == axi4l_resp_okay)    result = $format ("okay");
   else if (resp == axi4l_resp_exokay)  result = $format ("exokay");
   else if (resp == axi4l_resp_slverr)  result = $format ("slverr");
   else if (resp == axi4l_resp_decerr)  result = $format ("decerr");
   return result;
endfunction:fshow_axi4l_resp

// ----------------

function Fmt fshow_axi4l_wr_addr (Axi4l_wr_addr #(wd_addr, wd_user) x);
   Fmt result = ($format ("{awaddr:%0h,", x.awaddr)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4l_wr_addr

function Fmt fshow_axi4l_wr_data (Axi4l_wr_data #(wd_data) x);
   let result = ($format ("{wdata:%0h,wstrb:%0h", x.wdata, x.wstrb)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4l_wr_data

function Fmt fshow_axi4l_wr_resp (Axi4l_wr_resp #(wd_user) x);
   Fmt result = ($format ("{bresp:")
		 + fshow_axi4l_resp (x.bresp)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4l_wr_resp

function Fmt fshow_axi4l_rd_addr (Axi4l_rd_addr #(wd_addr, wd_user) x);
   Fmt result = ($format ("{araddr:%0h", x.araddr)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4l_rd_addr

function Fmt fshow_axi4l_rd_data (Axi4l_rd_data #(wd_data, wd_user) x);
   Fmt result = ($format ("{rresp:")
		 + fshow_axi4l_resp (x.rresp)
		 + $format (",rdata:%0h", x.rdata)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4l_rd_data
// ================================================================
// AXI4-Lite buffer

// ----------------
// Server-side interface accepts requests and yields responses

interface Ifc_axi4l_server  #(numeric type wd_addr,
			                        numeric type wd_data,
			                        numeric type wd_user);

	interface FIFOF_I #(Axi4l_wr_addr #(wd_addr, wd_user)) i_wr_addr;
	interface FIFOF_I #(Axi4l_wr_data #(wd_data))          i_wr_data;
	interface FIFOF_O #(Axi4l_wr_resp #(wd_user))          o_wr_resp;

	interface FIFOF_I #(Axi4l_rd_addr #(wd_addr, wd_user)) i_rd_addr;
	interface FIFOF_O #(Axi4l_rd_data #(wd_data, wd_user)) o_rd_data;
endinterface

// ----------------
// Client-side interface yields requests and accepts responses

interface Ifc_axi4l_client  #(numeric type wd_addr,
			      numeric type wd_data,
			      numeric type wd_user);

	interface FIFOF_O #(Axi4l_wr_addr #(wd_addr, wd_user)) o_wr_addr;
	interface FIFOF_O #(Axi4l_wr_data #(wd_data))          o_wr_data;
	interface FIFOF_I #(Axi4l_wr_resp #(wd_user))          i_wr_resp;

	interface FIFOF_O #(Axi4l_rd_addr #(wd_addr, wd_user)) o_rd_addr;
	interface FIFOF_I #(Axi4l_rd_data #(wd_data, wd_user)) i_rd_data;
endinterface

// ----------------
// A Buffer has a server-side and a client-side, and a reset

interface Ifc_axi4l_buffer  #(numeric type wd_addr,
			      numeric type wd_data,
			      numeric type wd_user);
	method Action reset;
	interface Ifc_axi4l_server #(wd_addr, wd_data, wd_user) server_side;
	interface Ifc_axi4l_client #(wd_addr, wd_data, wd_user) client_side;
endinterface

// ----------------------------------------------------------------

module mkaxi4l_buffer (Ifc_axi4l_buffer #(wd_addr, wd_data, wd_user));

	FIFOF #(Axi4l_wr_addr #(wd_addr, wd_user)) f_wr_addr <- mkFIFOF;
	FIFOF #(Axi4l_wr_data #(wd_data))          f_wr_data <- mkFIFOF;
	FIFOF #(Axi4l_wr_resp #(wd_user))          f_wr_resp <- mkFIFOF;

	FIFOF #(Axi4l_rd_addr #(wd_addr, wd_user)) f_rd_addr <- mkFIFOF;
	FIFOF #(Axi4l_rd_data #(wd_data, wd_user)) f_rd_data <- mkFIFOF;

	method Action reset;
	   f_wr_addr.clear;
	   f_wr_data.clear;
	   f_wr_resp.clear;

	   f_rd_addr.clear;
	   f_rd_data.clear;
	endmethod

	interface Ifc_axi4l_server server_side;
	   interface i_wr_addr = to_FIFOF_I (f_wr_addr);
	   interface i_wr_data = to_FIFOF_I (f_wr_data);
	   interface o_wr_resp = to_FIFOF_O (f_wr_resp);

	   interface i_rd_addr = to_FIFOF_I (f_rd_addr);
	   interface o_rd_data = to_FIFOF_O (f_rd_data);
	endinterface

	interface Ifc_axi4l_client client_side;
	   interface o_wr_addr = to_FIFOF_O (f_wr_addr);
	   interface o_wr_data = to_FIFOF_O (f_wr_data);
	   interface i_wr_resp = to_FIFOF_I (f_wr_resp);

	   interface o_rd_addr = to_FIFOF_O (f_rd_addr);
	   interface i_rd_data = to_FIFOF_I (f_rd_data);
	endinterface
endmodule

module mkaxi4l_buffer_2 (Ifc_axi4l_buffer #(wd_addr, wd_data, wd_user));

	FIFOF #(Axi4l_wr_addr #(wd_addr, wd_user)) f_wr_addr <- mkMaster_EdgeFIFOF;
	FIFOF #(Axi4l_wr_data #(wd_data))          f_wr_data <- mkMaster_EdgeFIFOF;
	FIFOF #(Axi4l_wr_resp #(wd_user))          f_wr_resp <- mkSlave_EdgeFIFOF;

	FIFOF #(Axi4l_rd_addr #(wd_addr, wd_user)) f_rd_addr <- mkMaster_EdgeFIFOF;
	FIFOF #(Axi4l_rd_data #(wd_data, wd_user)) f_rd_data <- mkSlave_EdgeFIFOF;

	method Action reset;
	   f_wr_addr.clear;
	   f_wr_data.clear;
	   f_wr_resp.clear;

	   f_rd_addr.clear;
	   f_rd_data.clear;
	endmethod

	interface Ifc_axi4l_server server_side;
	   interface i_wr_addr = to_FIFOF_I (f_wr_addr);
	   interface i_wr_data = to_FIFOF_I (f_wr_data);
	   interface o_wr_resp = to_FIFOF_O (f_wr_resp);

	   interface i_rd_addr = to_FIFOF_I (f_rd_addr);
	   interface o_rd_data = to_FIFOF_O (f_rd_data);
	endinterface

	interface Ifc_axi4l_client client_side;
	   interface o_wr_addr = to_FIFOF_O (f_wr_addr);
	   interface o_wr_data = to_FIFOF_O (f_wr_data);
	   interface i_wr_resp = to_FIFOF_I (f_wr_resp);

	   interface o_rd_addr = to_FIFOF_O (f_rd_addr);
	   interface i_rd_data = to_FIFOF_I (f_rd_data);
	endinterface
endmodule

// ================================================================
// Master transactor interface

interface Ifc_axi4l_master_xactor #(numeric type wd_addr,
					numeric type wd_data,
					numeric type wd_user);
	method Action reset;

	// AXI side
	interface Ifc_axi4l_master #(wd_addr, wd_data, wd_user) axi4l_side;

  // Server side
  interface Ifc_axi4l_server #(wd_addr, wd_data, wd_user)  fifo_side;
endinterface: Ifc_axi4l_master_xactor

// ----------------------------------------------------------------
// Master transactor
// This version uses FIFOFs for total decoupling.

module mkaxi4l_master_xactor #(parameter QueueSize sz)
                              (Ifc_axi4l_master_xactor #(wd_addr, wd_data, wd_user));

	Bool unguarded = True;
	Bool guarded   = False;

	// These FIFOs are guarded on BSV side, unguarded on AXI side
	FIFOF #(Axi4l_wr_addr #(wd_addr, wd_user)) f_wr_addr <- mkGSizedFIFOF (guarded, unguarded, sz.wr_req_depth);
	FIFOF #(Axi4l_wr_data #(wd_data))          f_wr_data <- mkGSizedFIFOF (guarded, unguarded, sz.wr_req_depth);
	FIFOF #(Axi4l_wr_resp #(wd_user))          f_wr_resp <- mkGSizedFIFOF (unguarded, guarded, sz.wr_resp_depth);

	FIFOF #(Axi4l_rd_addr #(wd_addr, wd_user)) f_rd_addr <- mkGSizedFIFOF (guarded, unguarded, sz.rd_req_depth);
	FIFOF #(Axi4l_rd_data #(wd_data, wd_user)) f_rd_data <- mkGSizedFIFOF (unguarded, guarded, sz.rd_resp_depth);

	// ----------------------------------------------------------------
	// INTERFACE

	method Action reset;
	  f_wr_addr.clear;
	  f_wr_data.clear;
	  f_wr_resp.clear;
	  f_rd_addr.clear;
	  f_rd_data.clear;
	endmethod

	// AXI side
	interface axi4l_side = interface Ifc_axi4l_master;
		// Wr Addr channel
		method Bool           m_awvalid = f_wr_addr.notEmpty;
		method Bit #(wd_addr) m_awaddr  = f_wr_addr.first.awaddr;
		method Bit #(3)       m_awprot  = f_wr_addr.first.awprot;
		method Bit #(wd_user) m_awuser  = f_wr_addr.first.awuser;
		method Action m_awready (Bool awready);
		  if (f_wr_addr.notEmpty && awready) f_wr_addr.deq;
		endmethod

		// Wr Data channel
		method Bool                       m_wvalid = f_wr_data.notEmpty;
		method Bit #(wd_data)             m_wdata  = f_wr_data.first.wdata;
		method Bit #(TDiv #(wd_data, 8))  m_wstrb  = f_wr_data.first.wstrb;
		method Action m_wready (Bool wready);
		  if (f_wr_data.notEmpty && wready) f_wr_data.deq;
		endmethod

		// Wr Response channel
		method Action m_bvalid (Bool bvalid, Bit #(2) bresp, Bit #(wd_user) buser);
		  if (bvalid && f_wr_resp.notFull)
		    f_wr_resp.enq (Axi4l_wr_resp {bresp: unpack (bresp), buser: buser});
		endmethod

		method Bool m_bready;
		  return f_wr_resp.notFull;
		endmethod

		// Rd Addr channel
		method Bool           m_arvalid = f_rd_addr.notEmpty;
		method Bit #(wd_addr) m_araddr  = f_rd_addr.first.araddr;
		method Bit #(3)       m_arprot  = f_rd_addr.first.arprot;
		method Bit #(wd_user) m_aruser  = f_rd_addr.first.aruser;
		method Action m_arready (Bool arready);
		  if (f_rd_addr.notEmpty && arready) f_rd_addr.deq;
		endmethod

		// Rd Data channel
		method Action m_rvalid (Bool           rvalid,
		 	                      Bit #(2)       rresp,
		 	                      Bit #(wd_data) rdata,
		 	                      Bit #(wd_user) ruser);
		  if (rvalid && f_rd_data.notFull)
		    f_rd_data.enq (Axi4l_rd_data {rresp: unpack (rresp),
		 	                         		    rdata: rdata,
		 	                       			    ruser: ruser});
		endmethod

		method Bool m_rready;
	    return f_rd_data.notFull;
		endmethod

	endinterface;

	interface fifo_side = interface Ifc_axi4l_server
	  interface i_wr_addr = to_FIFOF_I (f_wr_addr);
	  interface i_wr_data = to_FIFOF_I (f_wr_data);
	  interface o_wr_resp = to_FIFOF_O (f_wr_resp);

	  interface i_rd_addr = to_FIFOF_I (f_rd_addr);
	  interface o_rd_data = to_FIFOF_O (f_rd_data);
  endinterface;
endmodule: mkaxi4l_master_xactor

// ----------------------------------------------------------------
// Master transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.

module mkaxi4l_master_xactor_2 (Ifc_axi4l_master_xactor #(wd_addr, wd_data, wd_user));

	// Each crg_full, rg_data pair below represents a 1-element fifo.

	Array #(Reg #(Bool))                          crg_wr_addr_full <- mkCReg (3, False);
	Reg #(Axi4l_wr_addr #(wd_addr, wd_user))  rg_wr_addr <- mkRegU;

	Array #(Reg #(Bool))                          crg_wr_data_full <- mkCReg (3, False);
	Reg #(Axi4l_wr_data #(wd_data))           rg_wr_data <- mkRegU;

	Array #(Reg #(Bool))                          crg_wr_resp_full <- mkCReg (3, False);
	Reg #(Axi4l_wr_resp #(wd_user))           rg_wr_resp <- mkRegU;

	Array #(Reg #(Bool))                          crg_rd_addr_full <- mkCReg (3, False);
	Reg #(Axi4l_rd_addr #(wd_addr, wd_user))  rg_rd_addr <- mkRegU;

	Array #(Reg #(Bool))                          crg_rd_data_full <- mkCReg (3, False);
	Reg #(Axi4l_rd_data #(wd_data, wd_user))  rg_rd_data <- mkRegU;

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
	   crg_wr_addr_full [port_clear] <= False;
	   crg_wr_data_full [port_clear] <= False;
	   crg_wr_resp_full [port_clear] <= False;
	   crg_rd_addr_full [port_clear] <= False;
	   crg_rd_data_full [port_clear] <= False;
	endmethod

	// AXI side
	interface axi4l_side = interface Ifc_axi4l_master;
			   // Wr Addr channel
			   method Bool           m_awvalid = crg_wr_addr_full [port_deq];
			   method Bit #(wd_addr) m_awaddr  = rg_wr_addr.awaddr;
			   method Bit #(3)       m_awprot  = rg_wr_addr.awprot;
			   method Bit #(wd_user) m_awuser  = rg_wr_addr.awuser;
			   method Action m_awready (Bool awready);
			      if (crg_wr_addr_full [port_deq] && awready)
				 crg_wr_addr_full [port_deq] <= False;    // deq
			   endmethod

			   // Wr Data channel
			   method Bool                       m_wvalid = crg_wr_data_full [port_deq];
			   method Bit #(wd_data)             m_wdata  = rg_wr_data.wdata;
			   method Bit #(TDiv #(wd_data, 8))  m_wstrb  = rg_wr_data.wstrb;
			   method Action m_wready (Bool wready);
			      if (crg_wr_data_full [port_deq] && wready)
				 crg_wr_data_full [port_deq] <= False;
			   endmethod

			   // Wr Response channel
			   method Action m_bvalid (Bool bvalid, Bit #(2) bresp, Bit #(wd_user) buser);
			      if (bvalid && (! (crg_wr_resp_full [port_enq]))) begin
				 crg_wr_resp_full [port_enq] <= True;
				 rg_wr_resp <= Axi4l_wr_resp {bresp: unpack (bresp),
								  buser: buser};
			      end
			   endmethod

			   method Bool m_bready;
			      return (! (crg_wr_resp_full [port_enq]));
			   endmethod

			   // Rd Addr channel
			   method Bool           m_arvalid = crg_rd_addr_full [port_deq];
			   method Bit #(wd_addr) m_araddr  = rg_rd_addr.araddr;
			   method Bit #(3)       m_arprot  = rg_rd_addr.arprot;
			   method Bit #(wd_user) m_aruser  = rg_rd_addr.aruser;
			   method Action m_arready (Bool arready);
			      if (crg_rd_addr_full [port_deq] && arready)
				 crg_rd_addr_full [port_deq] <= False;    // deq
			   endmethod

			   // Rd Data channel
			   method Action m_rvalid (Bool           rvalid,
						   Bit #(2)       rresp,
						   Bit #(wd_data) rdata,
						   Bit #(wd_user) ruser);
			      if (rvalid && (! (crg_rd_data_full [port_enq])))
				 crg_rd_data_full [port_enq] <= True;
				 rg_rd_data <= (Axi4l_rd_data {rresp: unpack (rresp),
								   rdata: rdata,
								   ruser: ruser});
			   endmethod

			   method Bool m_rready;
			      return (! (crg_rd_data_full [port_enq]));
			   endmethod

			endinterface;

	// FIFOF side
	interface fifo_side = interface Ifc_axi4l_server
	  interface i_wr_addr = fn_crg_and_rg_to_FIFOF_I (crg_wr_addr_full [port_enq], rg_wr_addr);
	  interface i_wr_data = fn_crg_and_rg_to_FIFOF_I (crg_wr_data_full [port_enq], rg_wr_data);
	  interface o_wr_resp = fn_crg_and_rg_to_FIFOF_O (crg_wr_resp_full [port_deq], rg_wr_resp);

	  interface i_rd_addr = fn_crg_and_rg_to_FIFOF_I (crg_rd_addr_full [port_enq], rg_rd_addr);
	  interface o_rd_data = fn_crg_and_rg_to_FIFOF_O (crg_rd_data_full [port_deq], rg_rd_data);
  endinterface;
endmodule: mkaxi4l_master_xactor_2

// ================================================================
// Slave transactor interface

interface Ifc_axi4l_slave_xactor #(numeric type wd_addr,
				       numeric type wd_data,
				       numeric type wd_user);
	method Action reset;

	// AXI side
	interface Ifc_axi4l_slave #(wd_addr, wd_data, wd_user) axi4l_side;

	// FIFOF side
  interface Ifc_axi4l_client #(wd_addr, wd_data, wd_user) fifo_side;
endinterface: Ifc_axi4l_slave_xactor

// ----------------------------------------------------------------
// Slave transactor
// This version uses FIFOFs for total decoupling.

module mkaxi4l_slave_xactor #(parameter QueueSize sz)
                             (Ifc_axi4l_slave_xactor #(wd_addr, wd_data, wd_user));

	Bool unguarded = True;
	Bool guarded   = False;

	// These FIFOs are guarded on BSV side, unguarded on AXI side
	FIFOF #(Axi4l_wr_addr #(wd_addr, wd_user)) f_wr_addr <- mkGSizedFIFOF (unguarded, guarded, sz.wr_req_depth);
	FIFOF #(Axi4l_wr_data #(wd_data))          f_wr_data <- mkGSizedFIFOF (unguarded, guarded, sz.wr_req_depth);
	FIFOF #(Axi4l_wr_resp #(wd_user))          f_wr_resp <- mkGSizedFIFOF (guarded, unguarded, sz.wr_resp_depth);

	FIFOF #(Axi4l_rd_addr #(wd_addr, wd_user)) f_rd_addr <- mkGSizedFIFOF (unguarded, guarded, sz.rd_req_depth);
	FIFOF #(Axi4l_rd_data #(wd_data, wd_user)) f_rd_data <- mkGSizedFIFOF (guarded, unguarded, sz.rd_resp_depth);

	// ----------------------------------------------------------------
	// INTERFACE

	method Action reset;
	  f_wr_addr.clear;
	  f_wr_data.clear;
	  f_wr_resp.clear;
	  f_rd_addr.clear;
	  f_rd_data.clear;
	endmethod

	// AXI side
	interface axi4l_side = interface Ifc_axi4l_slave;
	  // Wr Addr channel
	  method Action m_awvalid (Bool           awvalid,
	   	                       Bit #(wd_addr) awaddr,
	   	                       Bit #(3)       awprot,
	   	                       Bit #(wd_user) awuser);
	    if (awvalid && f_wr_addr.notFull)
	      f_wr_addr.enq (Axi4l_wr_addr {awaddr: awaddr,
	   			                            awprot: awprot,
	   			                            awuser: awuser});
	  endmethod

	  method Bool m_awready;
      return f_wr_addr.notFull;
	  endmethod

	  // Wr Data channel
	  method Action m_wvalid (Bool                      wvalid,
	   	                      Bit #(wd_data)            wdata,
	   	                      Bit #(TDiv #(wd_data, 8)) wstrb);
	    if (wvalid && f_wr_data.notFull)
	      f_wr_data.enq (Axi4l_wr_data {wdata: wdata, wstrb: wstrb});
	  endmethod

	  method Bool m_wready;
	    return f_wr_data.notFull;
	  endmethod

	  // Wr Response channel
	  method Bool           m_bvalid = f_wr_resp.notEmpty;
	  method Bit #(2)       m_bresp  = pack (f_wr_resp.first.bresp);
	  method Bit #(wd_user) m_buser  = f_wr_resp.first.buser;
	  method Action m_bready (Bool bready);
	    if (bready && f_wr_resp.notEmpty)
	      f_wr_resp.deq;
	  endmethod

	  // Rd Addr channel
	  method Action m_arvalid (Bool           arvalid,
	   	                       Bit #(wd_addr) araddr,
	   	                       Bit #(3)       arprot,
	   	                       Bit #(wd_user) aruser);
	    if (arvalid && f_rd_addr.notFull)
	      f_rd_addr.enq (Axi4l_rd_addr {araddr: araddr,
	   		                         	    arprot: arprot,
   	   			                          aruser: aruser});
	  endmethod

	  method Bool m_arready;
      return f_rd_addr.notFull;
	  endmethod

	  // Rd Data channel
	  method Bool           m_rvalid = f_rd_data.notEmpty;
	  method Bit #(2)       m_rresp  = pack (f_rd_data.first.rresp);
	  method Bit #(wd_data) m_rdata  = f_rd_data.first.rdata;
	  method Bit #(wd_user) m_ruser  = f_rd_data.first.ruser;
	  method Action m_rready (Bool rready);
	    if (rready && f_rd_data.notEmpty)
	      f_rd_data.deq;
	  endmethod
	endinterface;

	// FIFOF side
	interface fifo_side = interface Ifc_axi4l_client
	  interface o_wr_addr = to_FIFOF_O (f_wr_addr);
	  interface o_wr_data = to_FIFOF_O (f_wr_data);
	  interface i_wr_resp = to_FIFOF_I (f_wr_resp);

	  interface o_rd_addr = to_FIFOF_O (f_rd_addr);
	  interface i_rd_data = to_FIFOF_I (f_rd_data);
	endinterface;
endmodule: mkaxi4l_slave_xactor

// ----------------------------------------------------------------
// Slave transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.

module mkaxi4l_slave_xactor_2 (Ifc_axi4l_slave_xactor #(wd_addr, wd_data, wd_user));

	// Each crg_full, rg_data pair below represents a 1-element fifo.

	// These FIFOs are guarded on BSV side, unguarded on AXI side
	Array #(Reg #(Bool))                          crg_wr_addr_full <- mkCReg (3, False);
	Reg #(Axi4l_wr_addr #(wd_addr, wd_user))  rg_wr_addr <- mkRegU;

	Array #(Reg #(Bool))                          crg_wr_data_full <- mkCReg (3, False);
	Reg #(Axi4l_wr_data #(wd_data))           rg_wr_data <- mkRegU;

	Array #(Reg #(Bool))                          crg_wr_resp_full <- mkCReg (3, False);
	Reg #(Axi4l_wr_resp #(wd_user))           rg_wr_resp <- mkRegU;

	Array #(Reg #(Bool))                          crg_rd_addr_full <- mkCReg (3, False);
	Reg #(Axi4l_rd_addr #(wd_addr, wd_user))  rg_rd_addr <- mkRegU;

	Array #(Reg #(Bool))                          crg_rd_data_full <- mkCReg (3, False);
	Reg #(Axi4l_rd_data #(wd_data, wd_user))  rg_rd_data <- mkRegU;

	// The following CReg port indexes specify the relative scheduling of:
	//     {first,deq,notEmpty}    {enq,notFull}    clear
	Integer port_deq   = 0;
	Integer port_enq   = 1;
	Integer port_clear = 2;

	// ----------------------------------------------------------------
	// INTERFACE

	method Action reset;
	   crg_wr_addr_full [port_clear] <= False;
	   crg_wr_data_full [port_clear] <= False;
	   crg_wr_resp_full [port_clear] <= False;
	   crg_rd_addr_full [port_clear] <= False;
	   crg_rd_data_full [port_clear] <= False;
	endmethod

	// AXI side
	interface axi4l_side = interface Ifc_axi4l_slave;
			   // Wr Addr channel
			   method Action m_awvalid (Bool           awvalid,
						    Bit #(wd_addr) awaddr,
						    Bit #(3)       awprot,
						    Bit #(wd_user) awuser);
			      if (awvalid && (! crg_wr_addr_full [port_enq])) begin
				 crg_wr_addr_full [port_enq] <= True;    // enq
				 rg_wr_addr <= Axi4l_wr_addr {awaddr: awaddr,
								  awprot: awprot,
								  awuser: awuser};
			      end
			   endmethod

			   method Bool m_awready;
			      return (! crg_wr_addr_full [port_enq]);
			   endmethod

			   // Wr Data channel
			   method Action m_wvalid (Bool                      wvalid,
						   Bit #(wd_data)            wdata,
						   Bit #(TDiv #(wd_data, 8)) wstrb);
			      if (wvalid && (! crg_wr_data_full [port_enq])) begin
				 crg_wr_data_full [port_enq] <= True;    // enq
				 rg_wr_data <= Axi4l_wr_data {wdata: wdata, wstrb: wstrb};
			      end
			   endmethod

			   method Bool m_wready;
			      return (! crg_wr_data_full [port_enq]);
			   endmethod

			   // Wr Response channel
			   method Bool           m_bvalid = crg_wr_resp_full [port_deq];
			   method Bit #(2)       m_bresp  = pack (rg_wr_resp.bresp);
			   method Bit #(wd_user) m_buser  = rg_wr_resp.buser;
			   method Action m_bready (Bool bready);
			      if (bready && crg_wr_resp_full [port_deq])
				 crg_wr_resp_full [port_deq] <= False;    // deq
			   endmethod

			   // Rd Addr channel
			   method Action m_arvalid (Bool           arvalid,
						    Bit #(wd_addr) araddr,
						    Bit #(3)       arprot,
						    Bit #(wd_user) aruser);
			      if (arvalid && (! crg_rd_addr_full [port_enq])) begin
				 crg_rd_addr_full [port_enq] <= True;    // enq
				 rg_rd_addr <= Axi4l_rd_addr {araddr: araddr,
								  arprot: arprot,
								  aruser: aruser};
			      end
			   endmethod

			   method Bool m_arready;
			      return (! crg_rd_addr_full [port_enq]);
			   endmethod

			   // Rd Data channel
			   method Bool           m_rvalid = crg_rd_data_full [port_deq];
			   method Bit #(2)       m_rresp  = pack (rg_rd_data.rresp);
			   method Bit #(wd_data) m_rdata  = rg_rd_data.rdata;
			   method Bit #(wd_user) m_ruser  = rg_rd_data.ruser;
			   method Action m_rready (Bool rready);
			      if (rready && crg_rd_data_full [port_deq])
				 crg_rd_data_full [port_deq] <= False;    // deq
			   endmethod
			endinterface;

	// FIFOF side
	interface fifo_side = interface Ifc_axi4l_client
	  interface o_wr_addr = fn_crg_and_rg_to_FIFOF_O (crg_wr_addr_full [port_deq], rg_wr_addr);
	  interface o_wr_data = fn_crg_and_rg_to_FIFOF_O (crg_wr_data_full [port_deq], rg_wr_data);
	  interface i_wr_resp = fn_crg_and_rg_to_FIFOF_I (crg_wr_resp_full [port_enq], rg_wr_resp);

	  interface o_rd_addr = fn_crg_and_rg_to_FIFOF_O (crg_rd_addr_full [port_deq], rg_rd_addr);
	  interface i_rd_data = fn_crg_and_rg_to_FIFOF_I (crg_rd_data_full [port_enq], rg_rd_data);
	endinterface;
endmodule: mkaxi4l_slave_xactor_2

// ================================================================

module mkaxi4l_err_2(Ifc_axi4l_slave #(wd_addr, wd_data, wd_user));

  Ifc_axi4l_slave_xactor #(wd_addr, wd_data, wd_user) s_xactor <- mkaxi4l_slave_xactor_2();

  rule rl_receive_read_request;
    
    let ar                <- pop_o (s_xactor.fifo_side.o_rd_addr);
    Axi4l_rd_data #(wd_data, wd_user) r = Axi4l_rd_data {
                                                  rresp : axi4l_resp_decerr, 
                                                  rdata : ? , 
                                                  ruser : ar.aruser};
    s_xactor.fifo_side.i_rd_data.enq(r);
  endrule:rl_receive_read_request

  rule rl_receive_write_request;
    
    let aw  <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let w   <- pop_o (s_xactor.fifo_side.o_wr_data);
	  let b   = Axi4l_wr_resp {bresp : axi4l_resp_decerr, buser : aw.awuser};

    s_xactor.fifo_side.i_wr_resp.enq (b);
  endrule:rl_receive_write_request

  return s_xactor.axi4l_side;

endmodule:mkaxi4l_err_2

module mkaxi4l_err(Ifc_axi4l_slave #(wd_addr, wd_data, wd_user));

  Ifc_axi4l_slave_xactor #(wd_addr, wd_data, wd_user) 
      s_xactor <- mkaxi4l_slave_xactor(defaultValue);

  rule rl_receive_read_request;
    
    let ar                <- pop_o (s_xactor.fifo_side.o_rd_addr);
    Axi4l_rd_data #(wd_data, wd_user) r = Axi4l_rd_data {
                                                  rresp : axi4l_resp_decerr, 
                                                  rdata : ? , 
                                                  ruser : ar.aruser};
    s_xactor.fifo_side.i_rd_data.enq(r);
	  `logLevel( err_slave, 0, $format("ErrSlave: sending read response: ",fshow_axi4l_rd_data(r)))
  endrule:rl_receive_read_request

  rule rl_receive_write_request;
    
    let aw  <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let w   <- pop_o (s_xactor.fifo_side.o_wr_data);
	  let b   = Axi4l_wr_resp {bresp : axi4l_resp_decerr, buser : aw.awuser};
    s_xactor.fifo_side.i_wr_resp.enq (b);
	  `logLevel( err_slave, 0, $format("ErrSlave: sending write response: ",fshow_axi4l_wr_resp(b)))
  endrule:rl_receive_write_request

  return s_xactor.axi4l_side;

endmodule:mkaxi4l_err
endpackage:axi4l_types
