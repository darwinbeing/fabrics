// Copyright (c) 2021 InCore Semiconductors Pvt. Ltd. see LICENSE.incore for details.

package atb_components;

// ----------------------------------------------------------------
// This package mainly contains two ATB components
// as defined in "Understanding Trace" v2.0, by ARM Limited on 14 May 2020
// Trace Link (5.6 and 5.7)
// Trace Sink (5.8 and 5.9)

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
import atb_types :: *;

`include "Logger.bsv"

// ATB Upsizer
// ATB Downsizer
// ATB Funnel
// ATB Replicator
// ATB Trace Buffer
// ATB Async Bridge
// ATB Sync Bridge
// ATB Trace Memory Controller
// ATB TPIU
// ATB Dummy Writer


// ------------------------------------- ---------------------------
// The ATB Dummy Writer module

/*doc:note: Define Nexus-Trace Interface */
interface Ifc_writer#(numeric type wd_data);
    interface Ifc_atb_slave#(wd_data) atbs_port;
endinterface:Ifc_writer

module mkatb_dummy_writer(Ifc_writer#(wd_data));

    Bool unguarded = True;
    Bool guarded   = False;

    // These FIFOs are guarded on BSV side, unguarded on ATB side
    FIFOF #(Atb_payload #(wd_data))   f_tr_data <- mkGSizedFIFOF (unguarded, guarded, 2);

    rule rl_display;
        let tr_rcv = f_tr_data.first;
        $display("%t \tATB with ID %x Enqueued %x bytes \t %x",$time, tr_rcv.atid, tr_rcv.atbytes, tr_rcv.atdata);
        f_tr_data.deq;
    endrule

    // ----------------------------------------------------------------
    // INTERFACE
    interface atbs_port = interface Ifc_atb_slave
        method Action m_atvalid (Bool atvalid, Bit #(7) atid, Bit #(wd_data) atdata,
                                 Bit #(TSub#(TLog#(wd_data),3)) atbytes);
            if (atvalid && f_tr_data.notFull)
                f_tr_data.enq (Atb_payload {atid: atid, atdata: atdata, atbytes: atbytes});
        endmethod

        method Bool m_atready;
            return f_tr_data.notFull;
        endmethod

        method Action m_afready (Bool afready);
          noAction;
        endmethod
        method m_afvalid = ? ;

        method m_syncreq = ? ;
    endinterface;

endmodule

endpackage: atb_components
