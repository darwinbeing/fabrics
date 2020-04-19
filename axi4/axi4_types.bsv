// Copyright (c) 2013-2019 Bluespec, Inc. see LICENSE.bluespec for details.
// Copyright (c) 2020 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package axi4_types;

// ----------------------------------------------------------------
// Facilities for ARM AXI4, consisting of 5 independent channels:
//   Write Address, Write Data, Write Response, Read Address and Read Data

// Ref: ARM document:
//    AMBA AXI and ACE Protocol Specification
//    AXI3, AXI4, and AXI4-Lite
//    ACE and ACE-Lite
//    ARM IHI 0022E (ID022613)
//    Issue E, 22 Feb 2013

// ----------------------------------------------------------------
// BSV library imports

import FIFOF       :: *;
import Connectable :: *;
import DefaultValue :: * ;
`include "Logger.bsv"
// ----------------
// BSV additional libs

import Semi_FIFOF :: *;
import EdgeFIFOFs :: *;


// ----------------------------------------------------------------
// Fixed-width AXI4 buses

typedef Bit #(8)  Axi4_Len;

// AxSIZE
typedef Bit #(3)  Axi4_size;

Axi4_size  axsize_1   = 3'b_000;
Axi4_size  axsize_2   = 3'b_001;
Axi4_size  axsize_4   = 3'b_010;
Axi4_size  axsize_8   = 3'b_011;
Axi4_size  axsize_16  = 3'b_100;
Axi4_size  axsize_32  = 3'b_101;
Axi4_size  axsize_64  = 3'b_110;
Axi4_size  axsize_128 = 3'b_111;

// AxBURST
typedef Bit #(2)  Axi4_burst;

Axi4_burst  axburst_fixed = 2'b_00;
Axi4_burst  axburst_incr  = 2'b_01;
Axi4_burst  axburst_wrap  = 2'b_10;

// AxLOCK
typedef Bit #(1)  Axi4_lock;

Axi4_lock  axlock_normal    = 1'b_0;
Axi4_lock  axlock_exclusive = 1'b_1;

// ARCACHE
typedef Bit #(4)  Axi4_cache;

Axi4_cache  arcache_dev_nonbuf           = 'b_0000;
Axi4_cache  arcache_dev_buf              = 'b_0001;

Axi4_cache  arcache_norm_noncache_nonbuf = 'b_0010;
Axi4_cache  arcache_norm_noncache_buf    = 'b_0011;

Axi4_cache  arcache_wthru_no_alloc       = 'b_1010;
Axi4_cache  arcache_wthru_r_alloc        = 'b_1110;
Axi4_cache  arcache_wthru_w_alloc        = 'b_1010;
Axi4_cache  arcache_wthru_r_w_alloc      = 'b_1110;

Axi4_cache  arcache_wback_no_alloc       = 'b_1011;
Axi4_cache  arcache_wback_r_alloc        = 'b_1111;
Axi4_cache  arcache_wback_w_alloc        = 'b_1011;
Axi4_cache  arcache_wback_r_w_alloc      = 'b_1111;

// AWCACHE
Axi4_cache  awcache_dev_nonbuf           = 'b_0000;
Axi4_cache  awcache_dev_buf              = 'b_0001;

Axi4_cache  awcache_norm_noncache_nonbuf = 'b_0010;
Axi4_cache  awcache_norm_noncache_buf    = 'b_0011;

Axi4_cache  awcache_wthru_no_alloc       = 'b_0110;
Axi4_cache  awcache_wthru_r_alloc        = 'b_0110;
Axi4_cache  awcache_wthru_w_alloc        = 'b_1110;
Axi4_cache  awcache_wthru_r_w_alloc      = 'b_1110;

Axi4_cache  awcache_wback_no_alloc       = 'b_0111;
Axi4_cache  awcache_wback_r_alloc        = 'b_0111;
Axi4_cache  awcache_wback_w_alloc        = 'b_1111;
Axi4_cache  awcache_wback_r_w_alloc      = 'b_1111;

// PROT
typedef Bit #(3)  Axi4_Prot;

Bit #(1)  axprot_0_unpriv     = 0;    Bit #(1) axprot_0_priv       = 1;
Bit #(1)  axprot_1_secure     = 0;    Bit #(1) axprot_1_non_secure = 1;
Bit #(1)  axprot_2_data       = 0;    Bit #(1) axprot_2_instr      = 1;

// QoS
typedef Bit #(4)  Axi4_QoS;

// REGION
typedef Bit #(4)  Axi4_Region;

// RESP
typedef Bit #(2)  Axi4_resp;

Axi4_resp  axi4_resp_okay   = 2'b_00;
Axi4_resp  axi4_resp_exokay = 2'b_01;
Axi4_resp  axi4_resp_slverr = 2'b_10;
Axi4_resp  axi4_resp_decerr = 2'b_11;

// ----------------------------------------------------------------
// Function to check address-alignment
function Bool fn_addr_is_aligned (Bit #(wd_addr) addr, Axi4_size size);
   return (    (size == axsize_1)
	   || ((size == axsize_2)   && (addr [0]   == 1'b0))
	   || ((size == axsize_4)   && (addr [1:0] == 2'b0))
	   || ((size == axsize_8)   && (addr [2:0] == 3'b0))
	   || ((size == axsize_16)  && (addr [3:0] == 4'b0))
	   || ((size == axsize_32)  && (addr [4:0] == 5'b0))
	   || ((size == axsize_64)  && (addr [5:0] == 6'b0))
	   || ((size == axsize_128) && (addr [6:0] == 7'b0)));
endfunction:fn_addr_is_aligned

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
function Bit#(awidth) fn_axi4burst_addr(Bit#(8) arlen, Axi4_size arsize, Axi4_burst arburst, 
                                        Bit#(awidth) address );

	// this variable will decide the index above which part of the address should
	// not change in WRAP mode. Bits below this index value be incremented according
	// to the value of arlen and arsize;
	Bit#(3) wrap_size;
	case(arlen)
		3: wrap_size= 2;
		7: wrap_size= 3;
		15: wrap_size=4;
		default:wrap_size=1;
	endcase

  // this is address will directly be used for INCR mode
	Bit#(awidth) new_address=address+(('b1)<<arsize);
	Bit#(awidth) mask;
	mask=('1)<<(zeroExtend(arsize)+wrap_size);	// create a mask for bits which will remain constant in WRAP.
	Bit#(awidth) temp1=address& mask;	  // capture the constant part of the addr in WRAP.
	Bit#(awidth) temp2=new_address& (~mask);//capture the incremental part of the addr in WRAP.

	if(arburst== axburst_fixed) // FIXED
		return address;
	else if(arburst==axburst_incr) // INCR
		return new_address;
	else // WRAP
		return temp1|temp2; // create the new address in the wrap mode by ORing the masked values.
endfunction



// ----------------------------------------------------------------
// These are the signal-level interfaces for an Axi4 master.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_axi4_master #(numeric type wd_id,
			    numeric type wd_addr,
			    numeric type wd_data,
			    numeric type wd_user);
   // ----------------
   // Wr Addr channel
   (* always_ready, result="AWVALID" *)   method Bool           m_awvalid;     // out

   (* always_ready, result="AWID" *)      method Bit #(wd_id)   m_awid;        // out
   (* always_ready, result="AWADDR" *)    method Bit #(wd_addr) m_awaddr;      // out
   (* always_ready, result="AWLEN" *)     method Bit #(8)       m_awlen;       // out
   (* always_ready, result="AWSIZE" *)    method Axi4_size      m_awsize;      // out
   (* always_ready, result="AWBURST" *)   method Bit #(2)       m_awburst;     // out
   (* always_ready, result="AWLOCK" *)    method Bit #(1)       m_awlock;      // out
   (* always_ready, result="AWCACHE" *)   method Bit #(4)       m_awcache;     // out
   (* always_ready, result="AWPROT" *)    method Bit #(3)       m_awprot;      // out
   (* always_ready, result="AWQOS" *)     method Bit #(4)       m_awqos;       // out
   (* always_ready, result="AWREGION" *)  method Bit #(4)       m_awregion;    // out
   (* always_ready, result="AWUSER" *)    method Bit #(wd_user) m_awuser;      // out

   (* always_ready, always_enabled, prefix="" *)
   method Action m_awready ((* port="AWREADY" *) Bool awready);                // in

   // ----------------
   // Wr Data channel
   (* always_ready, result="WVALID" *)  method Bool                      m_wvalid;    // out

   (* always_ready, result="WDATA" *)   method Bit #(wd_data)            m_wdata;     // out
   (* always_ready, result="WSTRB" *)   method Bit #(TDiv #(wd_data, 8)) m_wstrb;     // out
   (* always_ready, result="WLAST" *)   method Bool                      m_wlast;     // out
   (* always_ready, result="WUSER" *)   method Bit #(wd_user)            m_wuser;     // out

   (* always_ready, always_enabled, prefix = "" *)
   method Action m_wready ((* port="WREADY" *)  Bool wready);                         // in

   // ----------------
   // Wr Response channel
   (* always_ready, always_enabled, prefix = "" *)
   method Action m_bvalid ((* port="BVALID" *)  Bool           bvalid,    // in
			   (* port="BID"    *)  Bit #(wd_id)   bid,       // in
			   (* port="BRESP"  *)  Bit #(2)       bresp,     // in
			   (* port="BUSER"  *)  Bit #(wd_user) buser);    // in

   (* always_ready, prefix = "", result="BREADY" *)
   method Bool m_bready;                                                  // out

   // ----------------
   // Rd Addr channel
   (* always_ready, result="ARVALID" *)   method Bool            m_arvalid;     // out

   (* always_ready, result="ARID" *)      method Bit #(wd_id)    m_arid;        // out
   (* always_ready, result="ARADDR" *)    method Bit #(wd_addr)  m_araddr;      // out
   (* always_ready, result="ARLEN" *)     method Bit #(8)        m_arlen;       // out
   (* always_ready, result="ARSIZE" *)    method Axi4_size       m_arsize;      // out
   (* always_ready, result="ARBURST" *)   method Bit #(2)        m_arburst;     // out
   (* always_ready, result="ARLOCK" *)    method Bit #(1)        m_arlock;      // out
   (* always_ready, result="ARCACHE" *)   method Bit #(4)        m_arcache;     // out
   (* always_ready, result="ARPROT" *)    method Bit #(3)        m_arprot;      // out
   (* always_ready, result="ARQOS" *)     method Bit #(4)        m_arqos;       // out
   (* always_ready, result="ARREGION" *)  method Bit #(4)        m_arregion;    // out
   (* always_ready, result="ARUSER" *)    method Bit #(wd_user)  m_aruser;      // out

   (* always_ready, always_enabled, prefix="" *)
   method Action m_arready ((* port="ARREADY" *) Bool arready);    // in

   // ----------------
   // Rd Data channel
   (* always_ready, always_enabled, prefix = "" *)
   method Action m_rvalid ((* port="RVALID" *)  Bool           rvalid,    // in
			   (* port="RID"    *)  Bit #(wd_id)   rid,       // in
			   (* port="RDATA"  *)  Bit #(wd_data) rdata,     // in
			   (* port="RRESP"  *)  Bit #(2)       rresp,     // in
			   (* port="RLAST"  *)  Bool           rlast,     // in
			   (* port="RUSER"  *)  Bit #(wd_user) ruser);    // in

   (* always_ready, result="RREADY" *)
   method Bool m_rready;                                                  // out
endinterface: Ifc_axi4_master

// ----------------------------------------------------------------
// These are the signal-level interfaces for an Axi4-Lite slave.
// The (*..*) attributes ensure that when bsc compiles this to Verilog,
// we get exactly the signals specified in the ARM spec.

interface Ifc_axi4_slave #(numeric type wd_id,
			   numeric type wd_addr,
			   numeric type wd_data,
			   numeric type wd_user);
   // Wr Addr channel
   (* always_ready, always_enabled, prefix = "" *)
   method Action m_awvalid ((* port="AWVALID" *)   Bool            awvalid,     // in
			    (* port="AWID" *)      Bit #(wd_id)    awid,        // in
			    (* port="AWADDR" *)    Bit #(wd_addr)  awaddr,      // in
			    (* port="AWLEN" *)     Bit #(8)        awlen,       // in
			    (* port="AWSIZE" *)    Axi4_size       awsize,      // in
			    (* port="AWBURST" *)   Bit #(2)        awburst,     // in
			    (* port="AWLOCK" *)    Bit #(1)        awlock,      // in
			    (* port="AWCACHE" *)   Bit #(4)        awcache,     // in
			    (* port="AWPROT" *)    Bit #(3)        awprot,      // in
			    (* port="AWQOS" *)     Bit #(4)        awqos,       // in
			    (* port="AWREGION" *)  Bit #(4)        awregion,    // in
			    (* port="AWUSER" *)    Bit #(wd_user)  awuser);     // in
   (* always_ready, result="AWREADY" *)
   method Bool m_awready;                                                       // out

   // Wr Data channel
   (* always_ready, always_enabled, prefix = "" *)
   method Action m_wvalid ((* port="WVALID" *) Bool                      wvalid,    // in
			   (* port="WDATA" *)  Bit #(wd_data)            wdata,     // in
			   (* port="WSTRB" *)  Bit #(TDiv #(wd_data,8))  wstrb,     // in
			   (* port="WLAST" *)  Bool                      wlast,     // in
			   (* port="WUSER" *)  Bit #(wd_user)            wuser);    // in
   (* always_ready, result="WREADY" *)
   method Bool m_wready;                                                           // out

   // Wr Response channel
   (* always_ready, result="BVALID" *)  method Bool            m_bvalid;    // out
   (* always_ready, result="BID" *)     method Bit #(wd_id)    m_bid;       // out
   (* always_ready, result="BRESP" *)   method Bit #(2)        m_bresp;     // out
   (* always_ready, result="BUSER" *)   method Bit #(wd_user)  m_buser;     // out
   (* always_ready, always_enabled, prefix="" *)
   method Action m_bready  ((* port="BREADY" *)   Bool bready);            // in

   // Rd Addr channel
   (* always_ready, always_enabled, prefix = "" *)
   method Action m_arvalid ((* port="ARVALID" *)   Bool            arvalid,     // in
			    (* port="ARID" *)      Bit #(wd_id)    arid,        // in
			    (* port="ARADDR" *)    Bit #(wd_addr)  araddr,      // in
			    (* port="ARLEN" *)     Bit #(8)        arlen,       // in
			    (* port="ARSIZE" *)    Axi4_size       arsize,      // in
			    (* port="ARBURST" *)   Bit #(2)        arburst,     // in
			    (* port="ARLOCK" *)    Bit #(1)        arlock,      // in
			    (* port="ARCACHE" *)   Bit #(4)        arcache,     // in
			    (* port="ARPROT" *)    Bit #(3)        arprot,      // in
			    (* port="ARQOS" *)     Bit #(4)        arqos,       // in
			    (* port="ARREGION" *)  Bit #(4)        arregion,    // in
			    (* port="ARUSER" *)    Bit #(wd_user)  aruser);     // in
   (* always_ready, result="ARREADY" *)
   method Bool m_arready;                                                       // out

   // Rd Data channel
   (* always_ready, result="RVALID" *)  method Bool            m_rvalid;    // out
   (* always_ready, result="RID" *)     method Bit #(wd_id)    m_rid;       // out
   (* always_ready, result="RDATA" *)   method Bit #(wd_data)  m_rdata;     // out
   (* always_ready, result="RRESP" *)   method Bit #(2)        m_rresp;     // out
   (* always_ready, result="RLAST" *)   method Bool            m_rlast;     // out
   (* always_ready, result="RUSER" *)   method Bit #(wd_user)  m_ruser;     // out
   (* always_ready, always_enabled, prefix="" *)
   method Action m_rready  ((* port="RREADY" *)   Bool rready);             // in
endinterface: Ifc_axi4_slave

// ----------------------------------------------------------------
// Connecting signal-level interfaces

instance Connectable #(Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user),
		       Ifc_axi4_slave  #(wd_id, wd_addr, wd_data, wd_user));

   module mkConnection #(Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user) axim,
			 Ifc_axi4_slave  #(wd_id, wd_addr, wd_data, wd_user) axis)
		       (Empty);

      (* fire_when_enabled, no_implicit_conditions *)
      rule rl_wr_addr_channel;
	      axis.m_awvalid (axim.m_awvalid,
	       	axim.m_awid,
	       	axim.m_awaddr,
	       	axim.m_awlen,
	       	axim.m_awsize,
	       	axim.m_awburst,
	       	axim.m_awlock,
	       	axim.m_awcache,
	       	axim.m_awprot,
	       	axim.m_awqos,
	       	axim.m_awregion,
	       	axim.m_awuser);
	      axim.m_awready (axis.m_awready);
      endrule

      (* fire_when_enabled, no_implicit_conditions *)
      rule rl_wr_data_channel;
	      axis.m_wvalid (axim.m_wvalid,
	       	axim.m_wdata,
	       	axim.m_wstrb,
	       	axim.m_wlast,
	       	axim.m_wuser);
	      axim.m_wready (axis.m_wready);
      endrule

      (* fire_when_enabled, no_implicit_conditions *)
      rule rl_wr_response_channel;
	      axim.m_bvalid (axis.m_bvalid,
	       	axis.m_bid,
	       	axis.m_bresp,
	       	axis.m_buser);
	      axis.m_bready (axim.m_bready);
      endrule

      (* fire_when_enabled, no_implicit_conditions *)
      rule rl_rd_addr_channel;
	      axis.m_arvalid (axim.m_arvalid,
	       	axim.m_arid,
	       	axim.m_araddr,
	       	axim.m_arlen,
	       	axim.m_arsize,
	       	axim.m_arburst,
	       	axim.m_arlock,
	       	axim.m_arcache,
	       	axim.m_arprot,
	       	axim.m_arqos,
	       	axim.m_arregion,
	       	axim.m_aruser);
	      axim.m_arready (axis.m_arready);
      endrule

      (* fire_when_enabled, no_implicit_conditions *)
      rule rl_rd_data_channel;
	      axim.m_rvalid (axis.m_rvalid,
	       	axis.m_rid,
	       	axis.m_rdata,
	       	axis.m_rresp,
	       	axis.m_rlast,
	       	axis.m_ruser);
	      axis.m_rready (axim.m_rready);
      endrule
   endmodule: mkConnection
endinstance: Connectable

instance Connectable #(Ifc_axi4_slave  #(wd_id, wd_addr, wd_data, wd_user),
    Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user));

  module mkConnection #(Ifc_axi4_slave  #(wd_id, wd_addr, wd_data, wd_user) axis,
  Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user) axim)(Empty);

    mkConnection(axim, axis);
  endmodule:mkConnection
endinstance:Connectable

// ----------------------------------------------------------------
// Axi4 dummy master: never produces requests, never accepts responses

Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user) ifc_dummy_axi4_master = 
  interface Ifc_axi4_master
		// Wr Addr channel
		method Bool            m_awvalid  = False;              // out
		method Bit #(wd_id)    m_awid     = ?;                  // out
		method Bit #(wd_addr)  m_awaddr   = ?;                  // out
		method Bit #(8)        m_awlen    = ?;                  // out
		method Axi4_size       m_awsize   = ?;                  // out
		method Bit #(2)        m_awburst  = ?;                  // out
		method Bit #(1)        m_awlock   = ?;                  // out
		method Bit #(4)        m_awcache  = ?;                  // out
		method Bit #(3)        m_awprot   = ?;                  // out
		method Bit #(4)        m_awqos    = ?;                  // out
		method Bit #(4)        m_awregion = ?;                  // out
		method Bit #(wd_user)  m_awuser   = ?;                  // out
		method Action m_awready (Bool awready) = noAction;      // in

		// Wr Data channel
		method Bool                       m_wvalid = False;     // out
		method Bit #(wd_data)             m_wdata  = ?;         // out
		method Bit #(TDiv #(wd_data, 8))  m_wstrb  = ?;         // out
		method Bool                       m_wlast  = ?;         // out
		method Bit #(wd_user)             m_wuser  = ?;         // out

		method Action m_wready (Bool wready) = noAction;        // in

		// Wr Response channel
		method Action m_bvalid (Bool            bvalid,    // in
		  Bit #(wd_id)    bid,       // in
		  Bit #(2)        bresp,     // in
		  Bit #(wd_user)  buser);    // in
		  noAction;
    endmethod
		method Bool m_bready = False;                     // out

		// Rd Addr channel
		method Bool            m_arvalid  = False;             // out
		method Bit #(wd_id)    m_arid     = ?;                 // out
		method Bit #(wd_addr)  m_araddr   = ?;                 // out
		method Bit #(8)        m_arlen    = ?;                 // out
		method Axi4_size       m_arsize   = ?;                 // out
		method Bit #(2)        m_arburst  = ?;                 // out
		method Bit #(1)        m_arlock   = ?;                 // out
		method Bit #(4)        m_arcache  = ?;                 // out
		method Bit #(3)        m_arprot   = ?;                 // out
		method Bit #(4)        m_arqos    = ?;                 // out
		method Bit #(4)        m_arregion = ?;                 // out
		method Bit #(wd_user)  m_aruser   = ?;                 // out
		method Action m_arready (Bool arready) = noAction;     // in

		// Rd Data channel
		method Action m_rvalid (Bool            rvalid,    // in
		  Bit #(wd_id)    rid,       // in
		  Bit #(wd_data)  rdata,     // in
		  Bit #(2)        rresp,     // in
		  Bool            rlast,     // in
		  Bit #(wd_user)  ruser);    // in
		  noAction;
		endmethod
		method Bool m_rready = False;                     // out
	endinterface;

// ----------------------------------------------------------------
// Axi4 dummy slave: never accepts requests, never produces responses

Ifc_axi4_slave #(wd_id, wd_addr, wd_data, wd_user) ifc_dummy_axi4_slave = 
  interface Ifc_axi4_slave 
		// Wr Addr channel
		method Action m_awvalid (Bool awvalid,
		              Bit #(wd_id)    awid,
		              Bit #(wd_addr)  awaddr,
		              Bit #(8)        awlen,
		              Axi4_size       awsize,
		              Bit #(2)        awburst,
		              Bit #(1)        awlock,
		              Bit #(4)        awcache,
		              Bit #(3)        awprot,
		              Bit #(4)        awqos,
		              Bit #(4)        awregion,
		              Bit #(wd_user)  awuser);
		  noAction;
		endmethod

		method Bool m_awready;
		  return False;
		endmethod

		// Wr Data channel
	  method Action m_wvalid (Bool wvalid,
		  Bit #(wd_data)             wdata,
		  Bit #(TDiv #(wd_data, 8))  wstrb,
		  Bool                       wlast,
		  Bit #(wd_user)             wuser);
		  noAction;
	  endmethod

	  method Bool m_wready;
		  return False;
	  endmethod

	     // Wr Response channel
	  method Bool m_bvalid;
		  return False;
		endmethod

		method Bit #(wd_id) m_bid;
		  return ?;
		endmethod

		method Bit #(2) m_bresp;
		  return 0;
		endmethod

		method Bit #(wd_user) m_buser;
		  return ?;
		endmethod

		method Action m_bready  (Bool bready);
		  noAction;
		endmethod

		// Rd Addr channel
		method Action m_arvalid (Bool arvalid,
		              Bit #(wd_id)    arid,
		              Bit #(wd_addr)  araddr,
		              Bit #(8)        arlen,
		              Axi4_size       arsize,
		              Bit #(2)        arburst,
		              Bit #(1)        arlock,
		              Bit #(4)        arcache,
		              Bit #(3)        arprot,
		              Bit #(4)        arqos,
		              Bit #(4)        arregion,
		              Bit #(wd_user)  aruser);
		  noAction;
		endmethod

	  method Bool m_arready;
	    return False;
		endmethod

	  // Rd Data channel
	  method Bool m_rvalid;
		  return False;
		endmethod

		method Bit #(wd_id) m_rid;
		  return 0;
		endmethod

		method Bit #(wd_data) m_rdata;
		  return 0;
		endmethod

		method Bit #(2) m_rresp;
		  return 0;
		endmethod

		method Bool  m_rlast;
		  return True;
		endmethod

		method Bit #(wd_user) m_ruser;
		  return ?;
		endmethod

		method Action m_rready  (Bool rready);
		  noAction;
		endmethod
	endinterface;

// ****************************************************************
// ****************************************************************
// Section: Higher-level FIFO-like interfaces and transactors
// ****************************************************************
// ****************************************************************

// ----------------------------------------------------------------
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
endfunction

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
endfunction

// ----------------------------------------------------------------
// Higher-level types for payloads (rather than just bits)

// Write Address channel

typedef struct {
   Bit #(wd_id)    awid;
   Bit #(wd_addr)  awaddr;
   Bit #(8)        awlen;
   Axi4_size       awsize;
   Bit #(2)        awburst;
   Bit #(1)        awlock;
   Bit #(4)        awcache;
   Bit #(3)        awprot;
   Bit #(4)        awqos;
   Bit #(4)        awregion;
   Bit #(wd_user)  awuser;
   } Axi4_wr_addr #(numeric type wd_id,
		                numeric type wd_addr,
		                numeric type wd_user) deriving (Bits, FShow);

// Write Data channel

typedef struct {
   Bit #(wd_data)             wdata;
   Bit #(TDiv #(wd_data, 8))  wstrb;
   Bool                       wlast;
   Bit #(wd_user)             wuser;
   } Axi4_wr_data #(numeric type wd_data,
		                numeric type wd_user) deriving (Bits, FShow);

// Write Response channel

typedef struct {
   Bit #(wd_id)    bid;
   Bit #(2)        bresp;
   Bit #(wd_user)  buser;
   } Axi4_wr_resp #(numeric type wd_id,
		                numeric type wd_user) deriving (Bits, FShow);

// Read Address channel

typedef struct {
   Bit #(wd_id)    arid;
   Bit #(wd_addr)  araddr;
   Bit #(8)        arlen;
   Axi4_size       arsize;
   Bit #(2)        arburst;
   Bit #(1)        arlock;
   Bit #(4)        arcache;
   Bit #(3)        arprot;
   Bit #(4)        arqos;
   Bit #(4)        arregion;
   Bit #(wd_user)  aruser;
   } Axi4_rd_addr #(numeric type wd_id,
		                numeric type wd_addr,
		                numeric type wd_user) deriving (Bits, FShow);

// Read Data channel

typedef struct {
   Bit #(wd_id)    rid;
   Bit #(wd_data)  rdata;
   Bit #(2)        rresp;
   Bool            rlast;
   Bit #(wd_user)  ruser;
   } Axi4_rd_data #(numeric type wd_id,
           		      numeric type wd_data,
         				    numeric type wd_user) deriving (Bits, FShow);

// ----------------------------------------------------------------
// The following are specialized 'fshow' functions for Axi4 bus
// payloads: the most common fields, and more compact.

function Fmt fshow_axi4_size (Axi4_size  size);
   Fmt result = ?;
   if      (size == axsize_1)   result = $format ("sz1");
   else if (size == axsize_2)   result = $format ("sz2");
   else if (size == axsize_4)   result = $format ("sz4");
   else if (size == axsize_8)   result = $format ("sz8");
   else if (size == axsize_16)  result = $format ("sz16");
   else if (size == axsize_32)  result = $format ("sz32");
   else if (size == axsize_64)  result = $format ("sz64");
   else if (size == axsize_128) result = $format ("sz128");
   return result;
endfunction:fshow_axi4_size

function Fmt fshow_axi4_burst (Axi4_burst  burst);
   Fmt result = ?;
   if      (burst == axburst_fixed)  result = $format ("fixed");
   else if (burst == axburst_incr)   result = $format ("incr");
   else if (burst == axburst_wrap)   result = $format ("wrap");
   else                              result = $format ("burst:%0d", burst);
   return result;
endfunction:fshow_axi4_burst

function Fmt fshow_axi4_resp (Axi4_resp  resp);
   Fmt result = ?;
   if      (resp == axi4_resp_okay)    result = $format ("okay");
   else if (resp == axi4_resp_exokay)  result = $format ("exokay");
   else if (resp == axi4_resp_slverr)  result = $format ("slverr");
   else if (resp == axi4_resp_decerr)  result = $format ("decerr");
   return result;
endfunction:fshow_axi4_resp

// ----------------

function Fmt fshow_axi4_wr_addr (Axi4_wr_addr #(wd_id, wd_addr, wd_user) x);
   Fmt result = ($format ("{awaddr:%0h,", x.awaddr)
		 + $format ("awlen:%0d", x.awlen)
		 + $format (",")
		 + fshow_axi4_size (x.awsize)
		 + $format (",")
		 + fshow_axi4_burst (x.awburst)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4_wr_addr

function Fmt fshow_axi4_wr_data (Axi4_wr_data #(wd_data, wd_user) x);
   let result = ($format ("{wdata:%0h,wstrb:%0h", x.wdata, x.wstrb)
		 + (x.wlast ? $format (",wlast") : $format (",.."))
		 + $format ("}"));
   return result;
endfunction:fshow_axi4_wr_data

function Fmt fshow_axi4_wr_resp (Axi4_wr_resp #(wd_id, wd_user) x);
   Fmt result = ($format ("{bresp:")
		 + fshow_axi4_resp (x.bresp)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4_wr_resp

function Fmt fshow_axi4_rd_addr (Axi4_rd_addr #(wd_id, wd_addr, wd_user) x);
   Fmt result = ($format ("{araddr:%0h", x.araddr)
		 + $format (",arlen:%0d", x.arlen)
		 + $format (",")
		 + fshow_axi4_size (x.arsize)
		 + $format (",")
		 + fshow_axi4_burst (x.arburst)
		 + $format ("}"));
   return result;
endfunction:fshow_axi4_rd_addr

function Fmt fshow_axi4_rd_data (Axi4_rd_data #(wd_id, wd_data, wd_user) x);
   Fmt result = ($format ("{rresp:")
		 + fshow_axi4_resp (x.rresp)
		 + $format (",rdata:%0h", x.rdata)
		 + (x.rlast ? $format (",rlast") : $format (",.."))
		 + $format ("}"));
   return result;
endfunction:fshow_axi4_rd_data

// ----------------------------------------------------------------
// Axi4 buffer

// ----------------
// Server-side interface accepts requests and yields responses

interface Ifc_axi4_server  #(numeric type wd_id,
			     numeric type wd_addr,
			     numeric type wd_data,
			     numeric type wd_user);

   interface FIFOF_I #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  i_wr_addr;
   interface FIFOF_I #(Axi4_wr_data #(wd_data, wd_user))         i_wr_data;
   interface FIFOF_O #(Axi4_wr_resp #(wd_id, wd_user))           o_wr_resp;

   interface FIFOF_I #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  i_rd_addr;
   interface FIFOF_O #(Axi4_rd_data #(wd_id, wd_data, wd_user))  o_rd_data;
endinterface:Ifc_axi4_server

// ----------------
// Client-side interface yields requests and accepts responses

interface Ifc_axi4_client  #(numeric type wd_id,
			     numeric type wd_addr,
			     numeric type wd_data,
			     numeric type wd_user);

   interface FIFOF_O #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  o_wr_addr;
   interface FIFOF_O #(Axi4_wr_data #(wd_data, wd_user))         o_wr_data;
   interface FIFOF_I #(Axi4_wr_resp #(wd_id, wd_user))           i_wr_resp;

   interface FIFOF_O #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  o_rd_addr;
   interface FIFOF_I #(Axi4_rd_data #(wd_id, wd_data, wd_user))  i_rd_data;
endinterface:Ifc_axi4_client

// ----------------
// A Buffer has a server-side and a client-side, and a reset

interface Ifc_axi4_buffer  #(numeric type wd_id,
			     numeric type wd_addr,
			     numeric type wd_data,
			     numeric type wd_user);
   method Action reset;
   interface Ifc_axi4_server #(wd_id, wd_addr, wd_data, wd_user) server_side;
   interface Ifc_axi4_client #(wd_id, wd_addr, wd_data, wd_user) client_side;
 endinterface:Ifc_axi4_buffer

// ----------------------------------------------------------------
module mkaxi4_buffer (Ifc_axi4_buffer #(wd_id, wd_addr, wd_data, wd_user));

   FIFOF #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  f_wr_addr <- mkFIFOF;
   FIFOF #(Axi4_wr_data #(wd_data, wd_user))         f_wr_data <- mkFIFOF;
   FIFOF #(Axi4_wr_resp #(wd_id, wd_user))           f_wr_resp <- mkFIFOF;

   FIFOF #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  f_rd_addr <- mkFIFOF;
   FIFOF #(Axi4_rd_data #(wd_id, wd_data, wd_user))  f_rd_data <- mkFIFOF;

   method Action reset;
      f_wr_addr.clear;
      f_wr_data.clear;
      f_wr_resp.clear;

      f_rd_addr.clear;
      f_rd_data.clear;
   endmethod

   interface Ifc_axi4_server server_side;
      interface i_wr_addr = to_FIFOF_I (f_wr_addr);
      interface i_wr_data = to_FIFOF_I (f_wr_data);
      interface o_wr_resp = to_FIFOF_O (f_wr_resp);

      interface i_rd_addr = to_FIFOF_I (f_rd_addr);
      interface o_rd_data = to_FIFOF_O (f_rd_data);
   endinterface

   interface Ifc_axi4_client client_side;
      interface o_wr_addr = to_FIFOF_O (f_wr_addr);
      interface o_wr_data = to_FIFOF_O (f_wr_data);
      interface i_wr_resp = to_FIFOF_I (f_wr_resp);

      interface o_rd_addr = to_FIFOF_O (f_rd_addr);
      interface i_rd_data = to_FIFOF_I (f_rd_data);
   endinterface
endmodule:mkaxi4_buffer

module mkaxi4_buffer_2 (Ifc_axi4_buffer #(wd_id, wd_addr, wd_data, wd_user));

   FIFOF #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  f_wr_addr <- mkMaster_EdgeFIFOF;
   FIFOF #(Axi4_wr_data #(wd_data, wd_user))         f_wr_data <- mkMaster_EdgeFIFOF;
   FIFOF #(Axi4_wr_resp #(wd_id, wd_user))           f_wr_resp <- mkSlave_EdgeFIFOF;

   FIFOF #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  f_rd_addr <- mkMaster_EdgeFIFOF;
   FIFOF #(Axi4_rd_data #(wd_id, wd_data, wd_user))  f_rd_data <- mkSlave_EdgeFIFOF;

   method Action reset;
      f_wr_addr.clear;
      f_wr_data.clear;
      f_wr_resp.clear;

      f_rd_addr.clear;
      f_rd_data.clear;
   endmethod

   interface Ifc_axi4_server server_side;
      interface i_wr_addr = to_FIFOF_I (f_wr_addr);
      interface i_wr_data = to_FIFOF_I (f_wr_data);
      interface o_wr_resp = to_FIFOF_O (f_wr_resp);

      interface i_rd_addr = to_FIFOF_I (f_rd_addr);
      interface o_rd_data = to_FIFOF_O (f_rd_data);
   endinterface

   interface Ifc_axi4_client client_side;
      interface o_wr_addr = to_FIFOF_O (f_wr_addr);
      interface o_wr_data = to_FIFOF_O (f_wr_data);
      interface i_wr_resp = to_FIFOF_I (f_wr_resp);

      interface o_rd_addr = to_FIFOF_O (f_rd_addr);
      interface i_rd_data = to_FIFOF_I (f_rd_data);
   endinterface
endmodule:mkaxi4_buffer_2

// ----------------------------------------------------------------
// Master transactor interface

interface Ifc_axi4_master_xactor #(numeric type wd_id,
				   numeric type wd_addr,
				   numeric type wd_data,
				   numeric type wd_user);
  method Action reset;

  // AXI side
  interface Ifc_axi4_master #(wd_id, wd_addr, wd_data, wd_user)  axi4_side;
 
  // Server side
  interface Ifc_axi4_server #(wd_id, wd_addr, wd_data, wd_user)  fifo_side;

endinterface: Ifc_axi4_master_xactor

// ----------------------------------------------------------------
// Master transactor
// This version uses FIFOFs for total decoupling.

module mkaxi4_master_xactor #( parameter QueueSize sz)
                             (Ifc_axi4_master_xactor #(wd_id, wd_addr, wd_data, wd_user));

  Bool unguarded = True;
  Bool guarded   = False;

  // These FIFOs are guarded on BSV side, unguarded on AXI side
  FIFOF #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  f_wr_addr <- mkGSizedFIFOF (guarded, unguarded, sz.wr_req_depth);
  FIFOF #(Axi4_wr_data #(wd_data, wd_user))         f_wr_data <- mkGSizedFIFOF (guarded, unguarded, sz.wr_req_depth);
  FIFOF #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  f_rd_addr <- mkGSizedFIFOF (guarded, unguarded, sz.rd_req_depth);

  FIFOF #(Axi4_wr_resp #(wd_id, wd_user))           f_wr_resp <- mkGSizedFIFOF (unguarded, guarded, sz.wr_resp_depth);
  FIFOF #(Axi4_rd_data #(wd_id, wd_data, wd_user))  f_rd_data <- mkGSizedFIFOF (unguarded, guarded, sz.rd_resp_depth);

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
  interface axi4_side = interface Ifc_axi4_master;
		// Wr Addr channel
		method Bool            m_awvalid  = f_wr_addr.notEmpty;
		method Bit #(wd_id)    m_awid     = f_wr_addr.first.awid;
		method Bit #(wd_addr)  m_awaddr   = f_wr_addr.first.awaddr;
		method Bit #(8)        m_awlen    = f_wr_addr.first.awlen;
		method Axi4_size       m_awsize   = f_wr_addr.first.awsize;
		method Bit #(2)        m_awburst  = f_wr_addr.first.awburst;
		method Bit #(1)        m_awlock   = f_wr_addr.first.awlock;
		method Bit #(4)        m_awcache  = f_wr_addr.first.awcache;
		method Bit #(3)        m_awprot   = f_wr_addr.first.awprot;
		method Bit #(4)        m_awqos    = f_wr_addr.first.awqos;
		method Bit #(4)        m_awregion = f_wr_addr.first.awregion;
		method Bit #(wd_user)  m_awuser   = f_wr_addr.first.awuser;
		method Action m_awready (Bool awready);
		   if (f_wr_addr.notEmpty && awready) f_wr_addr.deq;
		endmethod

		// Wr Data channel
		method Bool                       m_wvalid = f_wr_data.notEmpty;
		method Bit #(wd_data)             m_wdata  = f_wr_data.first.wdata;
		method Bit #(TDiv #(wd_data, 8))  m_wstrb  = f_wr_data.first.wstrb;
		method Bool                       m_wlast  = f_wr_data.first.wlast;
		method Bit #(wd_user)             m_wuser  = f_wr_data.first.wuser;
		method Action m_wready (Bool wready);
		   if (f_wr_data.notEmpty && wready) f_wr_data.deq;
		endmethod

		// Wr Response channel
		method Action m_bvalid (Bool           bvalid,
		 	                      Bit #(wd_id)   bid,
		 	                      Bit #(2)       bresp,
		 	                      Bit #(wd_user) buser);
		  if (bvalid && f_wr_resp.notFull)
		    f_wr_resp.enq (Axi4_wr_resp { bid:   bid,
		 		                              bresp: bresp,
		 		                              buser: buser});
		endmethod

		method Bool m_bready;
		  return f_wr_resp.notFull;
		endmethod

		// Rd Addr channel
		method Bool            m_arvalid  = f_rd_addr.notEmpty;
		method Bit #(wd_id)    m_arid     = f_rd_addr.first.arid;
		method Bit #(wd_addr)  m_araddr   = f_rd_addr.first.araddr;
		method Bit #(8)        m_arlen    = f_rd_addr.first.arlen;
		method Axi4_size       m_arsize   = f_rd_addr.first.arsize;
		method Bit #(2)        m_arburst  = f_rd_addr.first.arburst;
		method Bit #(1)        m_arlock   = f_rd_addr.first.arlock;
		method Bit #(4)        m_arcache  = f_rd_addr.first.arcache;
		method Bit #(3)        m_arprot   = f_rd_addr.first.arprot;
		method Bit #(4)        m_arqos    = f_rd_addr.first.arqos;
		method Bit #(4)        m_arregion = f_rd_addr.first.arregion;
		method Bit #(wd_user)  m_aruser   = f_rd_addr.first.aruser;

		method Action m_arready (Bool arready);
		  if (f_rd_addr.notEmpty && arready) f_rd_addr.deq;
		endmethod

		// Rd Data channel
		method Action m_rvalid (Bool           rvalid,    // in
					                  Bit #(wd_id)   rid,       // in
					                  Bit #(wd_data) rdata,     // in
					                  Bit #(2)       rresp,     // in
					                  Bool           rlast,     // in
					                  Bit #(wd_user) ruser);    // in
      if (rvalid && f_rd_data.notFull)
			  f_rd_data.enq (Axi4_rd_data {rid  : rid,
						                         rdata: rdata,
						                         rresp: rresp,
						                         rlast: rlast,
						                         ruser: ruser});
		endmethod

		method Bool m_rready;
		  return f_rd_data.notFull;
		endmethod

	endinterface;

   // FIFOF side
  interface fifo_side = interface Ifc_axi4_server
    interface i_wr_addr = to_FIFOF_I (f_wr_addr);
    interface i_wr_data = to_FIFOF_I (f_wr_data);
    interface o_wr_resp = to_FIFOF_O (f_wr_resp);

    interface i_rd_addr = to_FIFOF_I (f_rd_addr);
    interface o_rd_data = to_FIFOF_O (f_rd_data);
  endinterface;
endmodule: mkaxi4_master_xactor

// ----------------------------------------------------------------
// Master transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.

module mkaxi4_master_xactor_2 (Ifc_axi4_master_xactor #(wd_id, wd_addr, wd_data, wd_user));

  // Each crg_full, rg_data pair below represents a 1-element fifo.

  Array #(Reg #(Bool))                            crg_wr_addr_full <- mkCReg (3, False);
  Reg #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  rg_wr_addr <- mkRegU;

  Array #(Reg #(Bool))                            crg_wr_data_full <- mkCReg (3, False);
  Reg #(Axi4_wr_data #(wd_data, wd_user))         rg_wr_data <- mkRegU;

  Array #(Reg #(Bool))                            crg_wr_resp_full <- mkCReg (3, False);
  Reg #(Axi4_wr_resp #(wd_id, wd_user))           rg_wr_resp <- mkRegU;

  Array #(Reg #(Bool))                            crg_rd_addr_full <- mkCReg (3, False);
  Reg #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  rg_rd_addr <- mkRegU;

  Array #(Reg #(Bool))                            crg_rd_data_full <- mkCReg (3, False);
  Reg #(Axi4_rd_data #(wd_id, wd_data, wd_user))  rg_rd_data <- mkRegU;

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
  interface axi4_side = interface Ifc_axi4_master;
	 	// Wr Addr channel
	 	method Bool           m_awvalid  = crg_wr_addr_full [port_deq];
	 	method Bit #(wd_id)   m_awid     = rg_wr_addr.awid;
	 	method Bit #(wd_addr) m_awaddr   = rg_wr_addr.awaddr;
	 	method Bit #(8)       m_awlen    = rg_wr_addr.awlen;
	 	method Axi4_size      m_awsize   = rg_wr_addr.awsize;
	 	method Bit #(2)       m_awburst  = rg_wr_addr.awburst;
	 	method Bit #(1)       m_awlock   = rg_wr_addr.awlock;
	 	method Bit #(4)       m_awcache  = rg_wr_addr.awcache;
	 	method Bit #(3)       m_awprot   = rg_wr_addr.awprot;
	 	method Bit #(4)       m_awqos    = rg_wr_addr.awqos;
	 	method Bit #(4)       m_awregion = rg_wr_addr.awregion;
	 	method Bit #(wd_user) m_awuser   = rg_wr_addr.awuser;
	 	method Action m_awready (Bool awready);
	 	  if (crg_wr_addr_full [port_deq] && awready)
	 	crg_wr_addr_full [port_deq] <= False;    // deq
	 	endmethod

	 	// Wr Data channel
	 	method Bool                       m_wvalid = crg_wr_data_full [port_deq];
	 	method Bit #(wd_data)             m_wdata  = rg_wr_data.wdata;
	 	method Bit #(TDiv #(wd_data, 8))  m_wstrb  = rg_wr_data.wstrb;
	 	method Bool                       m_wlast  = rg_wr_data.wlast;
	 	method Bit #(wd_user)             m_wuser  = rg_wr_data.wuser;
	 	method Action m_wready (Bool wready);
	 	  if (crg_wr_data_full [port_deq] && wready)
	 	    crg_wr_data_full [port_deq] <= False;
	 	endmethod

	 	// Wr Response channel
	 	method Action m_bvalid (Bool            bvalid,
	 	 	                      Bit #(wd_id)    bid,
	 	 	                      Bit #(2)        bresp,
	 	 	                      Bit #(wd_user)  buser);
	 	  if (bvalid && (! (crg_wr_resp_full [port_enq]))) begin
	 	    crg_wr_resp_full [port_enq] <= True;
	 	    rg_wr_resp <= Axi4_wr_resp {bid:   bid,
	 	 		                           bresp: bresp,
	 	 		                           buser: buser};
	 	   end
	 	endmethod

	 	method Bool m_bready;
	 	   return (! (crg_wr_resp_full [port_enq]));
	 	endmethod

	 	// Rd Addr channel
	 	method Bool            m_arvalid = crg_rd_addr_full [port_deq];
	 	method Bit #(wd_id)    m_arid     = rg_rd_addr.arid;
	 	method Bit #(wd_addr)  m_araddr   = rg_rd_addr.araddr;
	 	method Bit #(8)        m_arlen    = rg_rd_addr.arlen;
	 	method Axi4_size       m_arsize   = rg_rd_addr.arsize;
	 	method Bit #(2)        m_arburst  = rg_rd_addr.arburst;
	 	method Bit #(1)        m_arlock   = rg_rd_addr.arlock;
	 	method Bit #(4)        m_arcache  = rg_rd_addr.arcache;
	 	method Bit #(3)        m_arprot   = rg_rd_addr.arprot;
	 	method Bit #(4)        m_arqos    = rg_rd_addr.arqos;
	 	method Bit #(4)        m_arregion = rg_rd_addr.arregion;
	 	method Bit #(wd_user)  m_aruser   = rg_rd_addr.aruser;
	 	method Action m_arready (Bool arready);
	 	  if (crg_rd_addr_full [port_deq] && arready)
	 	    crg_rd_addr_full [port_deq] <= False;    // deq
	 	endmethod

	 	// Rd Data channel
	 	method Action m_rvalid (Bool            rvalid,
	 	 	                      Bit #(wd_id)    rid,
	 	 	                      Bit #(wd_data)  rdata,
	 	 	                      Bit #(2)        rresp,
	 	 	                      Bool            rlast,
	 	 	                      Bit #(wd_user)  ruser);
	 	  if (rvalid && (! (crg_rd_data_full [port_enq]))) begin
	 	    crg_rd_data_full [port_enq] <= True;
	 	    rg_rd_data <= (Axi4_rd_data {rid:   rid,
	 	 		                            rdata: rdata,
	 	 		                            rresp: rresp,
	 	 		                            rlast: rlast,
	 	 		                            ruser: ruser});
	 	 	end
	 	endmethod

	 	method Bool m_rready;
	 	  return (! (crg_rd_data_full [port_enq]));
	 	endmethod

	 	endinterface;

  // FIFOF side
  interface fifo_side = interface Ifc_axi4_server
    interface i_wr_addr = fn_crg_and_rg_to_FIFOF_I (crg_wr_addr_full [port_enq], rg_wr_addr);
    interface i_wr_data = fn_crg_and_rg_to_FIFOF_I (crg_wr_data_full [port_enq], rg_wr_data);
    interface o_wr_resp = fn_crg_and_rg_to_FIFOF_O (crg_wr_resp_full [port_deq], rg_wr_resp);

    interface i_rd_addr = fn_crg_and_rg_to_FIFOF_I (crg_rd_addr_full [port_enq], rg_rd_addr);
    interface o_rd_data = fn_crg_and_rg_to_FIFOF_O (crg_rd_data_full [port_deq], rg_rd_data);
  endinterface;
endmodule: mkaxi4_master_xactor_2

// ================================================================
// Slave transactor interface

interface Ifc_axi4_slave_xactor #(numeric type wd_id,
				  numeric type wd_addr,
				  numeric type wd_data,
				  numeric type wd_user);
   method Action reset;

   // AXI side
   interface Ifc_axi4_slave #(wd_id, wd_addr, wd_data, wd_user) axi4_side;
   interface Ifc_axi4_client #(wd_id, wd_addr, wd_data, wd_user) fifo_side;

endinterface: Ifc_axi4_slave_xactor

// ----------------------------------------------------------------
// Slave transactor
// This version uses FIFOFs for total decoupling.

module mkaxi4_slave_xactor #( parameter QueueSize sz)
                            (Ifc_axi4_slave_xactor #(wd_id, wd_addr, wd_data, wd_user));
  Bool unguarded = True;
  Bool guarded   = False;

  // These FIFOs are guarded on BSV side, unguarded on AXI side
  FIFOF #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  f_wr_addr <- mkGSizedFIFOF (unguarded, guarded, sz.wr_req_depth);
  FIFOF #(Axi4_wr_data #(wd_data, wd_user))         f_wr_data <- mkGSizedFIFOF (unguarded, guarded, sz.wr_req_depth);
  FIFOF #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  f_rd_addr <- mkGSizedFIFOF (unguarded, guarded, sz.rd_req_depth);

  FIFOF #(Axi4_wr_resp #(wd_id, wd_user))           f_wr_resp <- mkGSizedFIFOF (guarded, unguarded, sz.wr_resp_depth);
  FIFOF #(Axi4_rd_data #(wd_id, wd_data, wd_user))  f_rd_data <- mkGSizedFIFOF (guarded, unguarded, sz.rd_resp_depth);

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
  interface axi4_side = interface Ifc_axi4_slave;
	 	// Wr Addr channel
	 	method Action m_awvalid (Bool            awvalid,
	 	 	                       Bit #(wd_id)    awid,
	 	 	                       Bit #(wd_addr)  awaddr,
	 	 	                       Bit #(8)        awlen,
	 	 	                       Axi4_size       awsize,
	 	 	                       Bit #(2)        awburst,
	 	 	                       Bit #(1)        awlock,
	 	 	                       Bit #(4)        awcache,
	 	 	                       Bit #(3)        awprot,
	 	 	                       Bit #(4)        awqos,
	 	 	                       Bit #(4)        awregion,
	 	 	                       Bit #(wd_user)  awuser);
	 	  if (awvalid && f_wr_addr.notFull)
	 	    f_wr_addr.enq (Axi4_wr_addr {awid:     awid,
	 	 		                             awaddr:   awaddr,
	 	 		                             awlen:    awlen,
	 	 		                             awsize:   awsize,
	 	 		                             awburst:  awburst,
	 	 		                             awlock:   awlock,
	 	 		                             awcache:  awcache,
	 	 		                             awprot:   awprot,
	 	 		                             awqos:    awqos,
	 	 		                             awregion: awregion,
	 	 		                             awuser:   awuser});
	 	endmethod

	 	method Bool m_awready;
	 	  return f_wr_addr.notFull;
	 	endmethod

	 	// Wr Data channel
	 	method Action m_wvalid (Bool                       wvalid,
	 	 	                      Bit #(wd_data)             wdata,
	 	 	                      Bit #(TDiv #(wd_data, 8))  wstrb,
	 	 	                      Bool                       wlast,
	 	 	                      Bit #(wd_user)             wuser);
	 	  if (wvalid && f_wr_data.notFull)
	 	    f_wr_data.enq (Axi4_wr_data { wdata: wdata,
	 	 		                              wstrb: wstrb,
	 	 		                              wlast: wlast,
	 	 		                              wuser: wuser});
	 	endmethod

	 	method Bool m_wready;
	 	  return f_wr_data.notFull;
	 	endmethod

	 	// Wr Response channel
	 	method Bool           m_bvalid = f_wr_resp.notEmpty;
	 	method Bit #(wd_id)   m_bid    = f_wr_resp.first.bid;
	 	method Bit #(2)       m_bresp  = f_wr_resp.first.bresp;
	 	method Bit #(wd_user) m_buser  = f_wr_resp.first.buser;
	 	method Action m_bready (Bool bready);
	 	  if (bready && f_wr_resp.notEmpty)
	 	    f_wr_resp.deq;
	 	endmethod

	 	// Rd Addr channel
	 	method Action m_arvalid (Bool            arvalid,
	 	 	                       Bit #(wd_id)    arid,
	 	 	                       Bit #(wd_addr)  araddr,
	 	 	                       Bit #(8)        arlen,
	 	 	                       Axi4_size       arsize,
	 	 	                       Bit #(2)        arburst,
	 	 	                       Bit #(1)        arlock,
	 	 	                       Bit #(4)        arcache,
	 	 	                       Bit #(3)        arprot,
	 	 	                       Bit #(4)        arqos,
	 	 	                       Bit #(4)        arregion,
	 	 	                       Bit #(wd_user)  aruser);
	 	  if (arvalid && f_rd_addr.notFull)
	 	    f_rd_addr.enq (Axi4_rd_addr { arid:     arid,
	 	 		                              araddr:   araddr,
	 	 		                              arlen:    arlen,
	 	 		                              arsize:   arsize,
	 	 		                              arburst:  arburst,
	 	 		                              arlock:   arlock,
	 	 		                              arcache:  arcache,
	 	 		                              arprot:   arprot,
	 	 		                              arqos:    arqos,
	 	 		                              arregion: arregion,
	 	 		                              aruser:   aruser});
	 	endmethod

	 	method Bool m_arready;
	 	  return f_rd_addr.notFull;
	 	endmethod

	 	// Rd Data channel
	 	method Bool           m_rvalid = f_rd_data.notEmpty;
	 	method Bit #(wd_id)   m_rid    = f_rd_data.first.rid;
	 	method Bit #(wd_data) m_rdata  = f_rd_data.first.rdata;
	 	method Bit #(2)       m_rresp  = f_rd_data.first.rresp;
	 	method Bool           m_rlast  = f_rd_data.first.rlast;
	 	method Bit #(wd_user) m_ruser  = f_rd_data.first.ruser;
	 	method Action m_rready (Bool rready);
	 	  if (rready && f_rd_data.notEmpty)
	 	    f_rd_data.deq;
	 	endmethod
	endinterface;

  interface fifo_side = interface Ifc_axi4_client
    // FIFOF side
    interface o_wr_addr = to_FIFOF_O (f_wr_addr);
    interface o_wr_data = to_FIFOF_O (f_wr_data);
    interface i_wr_resp = to_FIFOF_I (f_wr_resp);

    interface o_rd_addr = to_FIFOF_O (f_rd_addr);
    interface i_rd_data = to_FIFOF_I (f_rd_data);
  endinterface;
endmodule: mkaxi4_slave_xactor

// ----------------------------------------------------------------
// Slave transactor
// This version uses crgs and regs instead of FIFOFs.
// This uses 1/2 the resources, but introduces scheduling dependencies.

module mkaxi4_slave_xactor_2 (Ifc_axi4_slave_xactor #(wd_id, wd_addr, wd_data, wd_user));

  // Each crg_full, rg_data pair below represents a 1-element fifo.

  // These FIFOs are guarded on BSV side, unguarded on AXI side
  Array #(Reg #(Bool))                            crg_wr_addr_full <- mkCReg (3, False);
  Reg #(Axi4_wr_addr #(wd_id, wd_addr, wd_user))  rg_wr_addr <- mkRegU;

  Array #(Reg #(Bool))                            crg_wr_data_full <- mkCReg (3, False);
  Reg #(Axi4_wr_data #(wd_data, wd_user))         rg_wr_data <- mkRegU;

  Array #(Reg #(Bool))                            crg_wr_resp_full <- mkCReg (3, False);
  Reg #(Axi4_wr_resp #(wd_id, wd_user))           rg_wr_resp <- mkRegU;

  Array #(Reg #(Bool))                            crg_rd_addr_full <- mkCReg (3, False);
  Reg #(Axi4_rd_addr #(wd_id, wd_addr, wd_user))  rg_rd_addr <- mkRegU;

  Array #(Reg #(Bool))                            crg_rd_data_full <- mkCReg (3, False);
  Reg #(Axi4_rd_data #(wd_id, wd_data, wd_user))  rg_rd_data <- mkRegU;

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
  interface axi4_side = interface Ifc_axi4_slave;
	 	// Wr Addr channel
	 	method Action m_awvalid (Bool            awvalid,
	 	 	                       Bit #(wd_id)    awid,
	 	 	                       Bit #(wd_addr)  awaddr,
	 	 	                       Bit #(8)        awlen,
	 	 	                       Axi4_size       awsize,
	 	 	                       Bit #(2)        awburst,
	 	 	                       Bit #(1)        awlock,
	 	 	                       Bit #(4)        awcache,
	 	 	                       Bit #(3)        awprot,
	 	 	                       Bit #(4)        awqos,
	 	 	                       Bit #(4)        awregion,
	 	 	                       Bit #(wd_user)  awuser);

	 	  if (awvalid && (! crg_wr_addr_full [port_enq])) begin
	 	    crg_wr_addr_full [port_enq] <= True;    // enq
	 	    rg_wr_addr <= Axi4_wr_addr {awid:     awid,
	 	 		                           awaddr:   awaddr,
	 	 		                           awlen:    awlen,
	 	 		                           awsize:   awsize,
	 	 		                           awburst:  awburst,
	 	 		                           awlock:   awlock,
	 	 		                           awcache:  awcache,
	 	 		                           awprot:   awprot,
	 	 		                           awqos:    awqos,
	 	 		                           awregion: awregion,
	 	 		                           awuser:   awuser};
	 	   end
	 	endmethod

	 	method Bool m_awready;
	 	  return (! crg_wr_addr_full [port_enq]);
	 	endmethod

	 	// Wr Data channel
	 	method Action m_wvalid (Bool                       wvalid,
	 	 	                      Bit #(wd_data)             wdata,
	 	 	                      Bit #(TDiv #(wd_data, 8))  wstrb,
	 	 	                      Bool                       wlast,
	 	 	                      Bit #(wd_user)             wuser);
	 	  if (wvalid && (! crg_wr_data_full [port_enq])) begin
	 	    crg_wr_data_full [port_enq] <= True;    // enq
	 	    rg_wr_data <= Axi4_wr_data {wdata: wdata,
	 	 		                           wstrb: wstrb,
	 	 		                           wlast: wlast,
	 	 		                           wuser: wuser};
	 	   end
	 	endmethod

	 	method Bool m_wready;
	 	   return (! crg_wr_data_full [port_enq]);
	 	endmethod

	 	// Wr Response channel
	 	method Bool           m_bvalid = crg_wr_resp_full [port_deq];
	 	method Bit #(wd_id)   m_bid    = rg_wr_resp.bid;
	 	method Bit #(2)       m_bresp  = rg_wr_resp.bresp;
	 	method Bit #(wd_user) m_buser  = rg_wr_resp.buser;
	 	method Action m_bready (Bool bready);
	 	  if (bready && crg_wr_resp_full [port_deq])
	 	    crg_wr_resp_full [port_deq] <= False;    // deq
	 	endmethod

	 	// Rd Addr channel
	 	method Action m_arvalid (Bool            arvalid,
	 	                         Bit #(wd_id)    arid,
	 	 	                       Bit #(wd_addr)  araddr,
	 	 	                       Bit #(8)        arlen,
	 	 	                       Axi4_size       arsize,
	 	 	                       Bit #(2)        arburst,
	 	 	                       Bit #(1)        arlock,
	 	 	                       Bit #(4)        arcache,
	 	                         Bit #(3)        arprot,
	 	 	                       Bit #(4)        arqos,
	 	 	                       Bit #(4)        arregion,
	 	 	                       Bit #(wd_user)  aruser);
      if (arvalid && (! crg_rd_addr_full [port_enq])) begin
	 	    crg_rd_addr_full [port_enq] <= True;    // enq
	 	    rg_rd_addr <= Axi4_rd_addr {arid:     arid,
	 	       		                     araddr:   araddr,
	 	       		                     arlen:    arlen,
	 	       		                     arsize:   arsize,
	 	       		                     arburst:  arburst,
	 	       		                     arlock:   arlock,
	 	       		                     arcache:  arcache,
	 	       		                     arprot:   arprot,
	 	       		                     arqos:    arqos,
	 	       		                     arregion: arregion,
	 	       		                     aruser:   aruser};
	 	  end
	 	endmethod

	 	method Bool m_arready;
	 	  return (! crg_rd_addr_full [port_enq]);
	 	endmethod

	 	// Rd Data channel
	 	method Bool           m_rvalid = crg_rd_data_full [port_deq];
	 	method Bit #(wd_id)   m_rid    = rg_rd_data.rid;
	 	method Bit #(wd_data) m_rdata  = rg_rd_data.rdata;
	 	method Bit #(2)       m_rresp  = rg_rd_data.rresp;
	 	method Bool           m_rlast  = rg_rd_data.rlast;
	 	method Bit #(wd_user) m_ruser  = rg_rd_data.ruser;
	 	method Action m_rready (Bool rready);
	 	  if (rready && crg_rd_data_full [port_deq])
	 	    crg_rd_data_full [port_deq] <= False;    // deq
	 	endmethod
	 	endinterface;

  interface fifo_side = interface Ifc_axi4_client
    // FIFOF side
    interface o_wr_addr = fn_crg_and_rg_to_FIFOF_O (crg_wr_addr_full [port_deq], rg_wr_addr);
    interface o_wr_data = fn_crg_and_rg_to_FIFOF_O (crg_wr_data_full [port_deq], rg_wr_data);
    interface i_wr_resp = fn_crg_and_rg_to_FIFOF_I (crg_wr_resp_full [port_enq], rg_wr_resp);

    interface o_rd_addr = fn_crg_and_rg_to_FIFOF_O (crg_rd_addr_full [port_deq], rg_rd_addr);
    interface i_rd_data = fn_crg_and_rg_to_FIFOF_I (crg_rd_data_full [port_enq], rg_rd_data);
  endinterface;
endmodule: mkaxi4_slave_xactor_2

typedef enum {Idle, Burst} Err_State deriving(Eq, Bits, FShow);
module mkaxi4_err_2(Ifc_axi4_slave #(wd_id, wd_addr, wd_data, wd_user));

  Ifc_axi4_slave_xactor #(wd_id, wd_addr, wd_data, wd_user) s_xactor <- mkaxi4_slave_xactor_2();

  Reg #(Err_State)                       read_state              <- mkReg(Idle);
  Reg #(Err_State)                       write_state             <- mkReg(Idle);

	Reg #(Bit #(8))                        rg_rd_counter           <- mkReg(0);
	Reg #(Bit #(8))                        rg_rd_length            <- mkReg(0);
  Reg #(Bit #(wd_id))                    rg_rd_id                <- mkReg(0);
  Reg #(Bit #(wd_user))                  rg_rd_user              <- mkReg(0);
  Reg #(Axi4_wr_resp	#(wd_id, wd_user)) rg_write_response       <- mkReg(?);

  rule rl_receive_read_request(read_state == Idle);
    
    let ar                <- pop_o (s_xactor.fifo_side.o_rd_addr);
    read_state            <= Burst;

    rg_rd_id              <= ar.arid;
    rg_rd_counter         <= 0;
	  rg_rd_length          <= ar.arlen;
	  rg_rd_user            <= ar.aruser;

  endrule:rl_receive_read_request

  rule rl_send_error_response ( read_state == Burst ) ;
    Axi4_rd_data #(wd_id, wd_data, wd_user) r = Axi4_rd_data {
                                                  rresp : axi4_resp_decerr, 
                                                  rdata : ? , 
                                                  rlast : rg_rd_counter == rg_rd_length, 
                                                  ruser : rg_rd_user, 
                                                  rid   : rg_rd_id};
    if(rg_rd_counter== rg_rd_length)
      read_state <= Idle;
    else
      rg_rd_counter<= rg_rd_counter + 1;

    s_xactor.fifo_side.i_rd_data.enq(r);
  endrule:rl_send_error_response

  rule rl_receive_write_request(write_state == Idle);
    
    let aw  <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let w   <- pop_o (s_xactor.fifo_side.o_wr_data);
	  let b   = Axi4_wr_resp {bresp : axi4_resp_decerr, buser : aw.awuser, bid : aw.awid};

    if( !w.wlast )
      write_state <= Burst;
    else
    	s_xactor.fifo_side.i_wr_resp.enq (b);

    rg_write_response <= b;
  endrule:rl_receive_write_request

  // if the request is a write burst then keeping popping all the data on the data_channel and
  // send a error response on receiving the last data.
  rule rl_write_request_data_channel(write_state == Burst);
    
    let w  <- pop_o (s_xactor.fifo_side.o_wr_data);

    if ( w.wlast ) begin
		  s_xactor.fifo_side.i_wr_resp.enq (rg_write_response);
      write_state <= Idle;
    end

  endrule:rl_write_request_data_channel

  return s_xactor.axi4_side;

endmodule:mkaxi4_err_2

module mkaxi4_err(Ifc_axi4_slave #(wd_id, wd_addr, wd_data, wd_user));

  Ifc_axi4_slave_xactor #(wd_id, wd_addr, wd_data, wd_user) 
      s_xactor <- mkaxi4_slave_xactor(defaultValue);

  Reg #(Err_State)                       read_state              <- mkReg(Idle);
  Reg #(Err_State)                       write_state             <- mkReg(Idle);

	Reg #(Bit #(8))                        rg_rd_counter           <- mkReg(0);
	Reg #(Bit #(8))                        rg_rd_length            <- mkReg(0);
  Reg #(Bit #(wd_id))                    rg_rd_id                <- mkReg(0);
  Reg #(Bit #(wd_user))                  rg_rd_user              <- mkReg(0);
  Reg #(Axi4_wr_resp	#(wd_id, wd_user)) rg_write_response       <- mkReg(?);

  rule rl_receive_read_request(read_state == Idle);
    
    let ar                <- pop_o (s_xactor.fifo_side.o_rd_addr);
    read_state            <= Burst;

    rg_rd_id              <= ar.arid;
    rg_rd_counter         <= 0;
	  rg_rd_length          <= ar.arlen;
	  rg_rd_user            <= ar.aruser;
	  `logLevel( err_slave, 0, $format("ErrSlave: received Read request: ",fshow_axi4_rd_addr(ar)))

  endrule:rl_receive_read_request

  rule rl_send_error_response ( read_state == Burst ) ;
    Axi4_rd_data #(wd_id, wd_data, wd_user) r = Axi4_rd_data {
                                                  rresp : axi4_resp_decerr, 
                                                  rdata : ? , 
                                                  rlast : rg_rd_counter == rg_rd_length, 
                                                  ruser : rg_rd_user, 
                                                  rid   : rg_rd_id};
    if(rg_rd_counter== rg_rd_length)
      read_state <= Idle;
    else
      rg_rd_counter<= rg_rd_counter + 1;

    s_xactor.fifo_side.i_rd_data.enq(r);
	  `logLevel( err_slave, 0, $format("ErrSlave: sending read response: ",fshow_axi4_rd_data(r)))
  endrule:rl_send_error_response

  rule rl_receive_write_request(write_state == Idle);
    
    let aw  <- pop_o (s_xactor.fifo_side.o_wr_addr);
    let w   <- pop_o (s_xactor.fifo_side.o_wr_data);
	  let b   = Axi4_wr_resp {bresp : axi4_resp_decerr, buser : aw.awuser, bid : aw.awid};

    if( !w.wlast )
      write_state <= Burst;
    else begin
    	s_xactor.fifo_side.i_wr_resp.enq (b);
	    `logLevel( err_slave, 0, $format("ErrSlave: sending write response: ",fshow_axi4_wr_resp(b)))
	  end

    rg_write_response <= b;
	  `logLevel( err_slave, 0, $format("ErrSlave: received write request: ",fshow_axi4_wr_addr(aw)))
  endrule:rl_receive_write_request

  // if the request is a write burst then keeping popping all the data on the data_channel and
  // send a error response on receiving the last data.
  rule rl_write_request_data_channel(write_state == Burst);
    
    let w  <- pop_o (s_xactor.fifo_side.o_wr_data);

    if ( w.wlast ) begin
		  s_xactor.fifo_side.i_wr_resp.enq (rg_write_response);
      write_state <= Idle;
	    `logLevel( err_slave, 0, $format("ErrSlave: sending write response: ",fshow_axi4_wr_resp(rg_write_response)))
    end

  endrule:rl_write_request_data_channel

  return s_xactor.axi4_side;

endmodule:mkaxi4_err


// ================================================================

endpackage:axi4_types
