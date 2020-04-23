.. _axi2apb_bridge:

##################
AXI4 to APB Bridge
##################

An AXI4 master device can be configured to work on an APB cluster as a master using the ``Axi2Apb``
bridge. This module implements a bridge/adapter which can be used to convert AXI-4 transactions into APB 
(a.k.a APB4, a.k.a APBv2.0) transactions. This bridge acts as a slave on the AXI4 
interface and as a master on an APB interface. Both the protocols are little endian.
The bridge is parameterized to handle different address and data sizes of either
side with the following contraints:

1. The AXI4 address size must be greater than or equal to the APB address size.
2. The AXI4 data size must be greater than of equal to the APB data size.
3. The AXI4 data and APB data should both be byte-multiples

The bridge also supports spliting of read/write bursts from the AXI4 side to individual requests on
the APB cluster.

A Connectable instance is also provided which can directly connect an AXI4 master interface to a
APB-slave interface.

The verilog RTL will have a AXI4 slave interface which should be connected to a AXI4 master device
and will have an APB master interface on the other side which should be connected to an APB slave
cluster.

Parameters
==========

The bridge interface has the following parameters:

.. tabularcolumns:: |l|L|

.. _axi2apb_bridge_params:

.. table:: AXI4 to APB Bridge Interface Parameters

  ==================  ===========
  Parameter Name      Description
  ------------------  -----------
  ``axi_id``          size of the id fields on the AXI4 interface
  ``axi_addr``        size of the address fields on the read and write channels of the AXI4 interface
  ``axi_data``        size of the data fields on the read-response and write-data channels of the AXI4
                      interface
  ``apb_addr``        size of the address field on the APB interface
  ``apd_data``        size of the read and write data fields on the APB interface
  ``user``            size of the user field on both the AXI and the APB sides.
  ==================  ===========

Micro Architecture
==================

Since the APB is a single channel bus and the AXI4 has separate read and write channels, the read
requests from the AXI4 are given priority over the write requests occurring in the same cycle. At
any point of time only a single requests (burst read or burst write) are served, and the next
request is picked up only when the APB has responded to all the bursts from the previous requests.

The transaction ID (awid or arid) received is stored in the
conversion bridge, and retrieved during response transfers as BID or RID.

Differing Address sizes
-----------------------

When the AXI4 and APB address sizes are different, then the lower bits of the AXI4 addresses are
used on the APB side. 

Differing Data sizes
--------------------

When the AXI4 and APB data sizes are different, each single beat of the AXI4 request (read or write)
is split into multiple smaller child bursts (sent as individual APB requests) which matches 
APB data size. A beat is complete only when its corresponding child-bursts are over. The next
single-beat address is generated based on the burst-mode request and the burst size. Thus, the
bridge can support all AXI4 burst-modes: incr, fixed and wrap.

When instantiated with same data-sizes, the child-burst logic is ommitted.

Error mapping
-------------

The APB PSLVERR is mapped to the AXI4 SLVERR.

Using the AXI4 to APB Bridge
============================

The IP is designed in BSV and available at: https://gitlab.com/incoresemi/blocks/fabrics
The following steps demonstrate on how to configure and generate verilog RTL of
the cross-bar IP. 

.. note:: The user is expected to have the downloaded and installed 
  open-source bluespec compiler available at: https://github.com/BSVLang/Main

Configuration and Generation
----------------------------

1. **Setup**:

   The IP uses the python based `cogapp tool <https://nedbatchelder.com/code/cog/>`_ to generate bsv files with cofigured instances. 
   Steps to install the required tools to generate the configured IP in verilog RTL can be found 
   in `Appendix <appendix.html>`_. Python virtual environment needs to be activated before 
   proceeding to the following steps.

2. **Clone the repo**:

   .. code:: bash
   
      git clone https://gitlab.com/incoresemi/blocks/fabrics.git
      ./manager.sh update_deps
      cd bridges/test

3. **Configure Design**: 
   
   The yaml file: ``axi2apb_bridge_config.yaml`` 
   is used for configuring the crossbar. Please refer to :numref:`axi2apb_bridge_params` 
   for information on the parameters used in the yaml file. 
   
4. **Generate Verilog**: use the following command with required settings to
   generate verilog for synthesis/simulation:

   .. code:: bash

     make TOP_FILE=axi2apb_bridge.bsv TOP_MODULE=mkaxi2apb_bridge generate_instances
   
   The generated verilog file is available in: ``build/hw/verilog/mkaxi2apb_bridge.v``

5. **Interface signals**: in the generated verilog, all the AXI4 signals start with the prefix
   ``AXI4_`` and the APB signals start with the prefix ``APB_``. Since the IP is a
   synchronous IP, the same clock and reset (active-low) signals (``CLK`` and ``RST_N``) are used by 
   all channles across all devices.

6. **Simulation**: The top module for simulation is ``mkaxi2apb_bridge``. Please follow the steps
   mentioned in :numref:`verilog_sim_env` when compiling the top-module for simulation

Verilog Signals
---------------

:numref:`verilog_names_axi2apb` describes the signals in the generated verilog for the following configuration 

.. code:: yaml

    axi_id: 4
    axi_addr:  32
    axi_data:  32
    apb_addr:  24
    apb_data:  16
    user    :  0

.. _verilog_names_axi2apb:

.. table:: AXI4 to APB bridge interface signals in from verilog

  ==============================  =========  ==========  ======================== 
  Signal Names                    Direction  Size(Bits)  Description          
  ------------------------------  ---------  ----------  ------------------------ 
  CLK                             Input      1           clock for all channels 
  RST\_N                          Input      1           an active low reset    
  AXI4_AWREADY                    Output     1           signal sent to axi4 master 
  AXI4_WREADY                     Output     1           signal sent to axi4 master
  AXI4_BVALID                     Output     1           signal sent to axi4 master
  AXI4_BID                        Output     4           signal sent to axi4 master
  AXI4_BRESP                      Output     2           signal sent to axi4 master
  AXI4_ARREADY                    Output     1           signal sent to axi4 master
  AXI4_RVALID                     Output     1           signal sent to axi4 master
  AXI4_RID                        Output     4           signal sent to axi4 master
  AXI4_RDATA                      Output     32          signal sent to axi4 master
  AXI4_RRESP                      Output     2           signal sent to axi4 master
  AXI4_RLAST                      Output     1           signal sent to axi4 master
  APB_PADDR                       Output     24          signal sent to apb slaves
  APB_PROT                        Output     3           signal sent to apb slaves 
  APB_PENABLE                     Output     1           signal sent to apb slaves  
  APB_PWRITE                      Output     1           signal sent to apb slaves 
  APB_PWDATA                      Output     16          signal sent to apb slaves
  APB_PSTRB                       Output     2           signal sent to apb slaves 
  APB_PSEL                        Output     1           signal sent to apb slaves
  AXI4_AWVALID                    Input      1           signal driven by axi4 master
  AXI4_AWID                       Input      4           signal driven by axi4 master
  AXI4_AWADDR                     Input      32          signal driven by axi4 master
  AXI4_AWLEN                      Input      8           signal driven by axi4 master
  AXI4_AWSIZE                     Input      3           signal driven by axi4 master
  AXI4_AWBURST                    Input      2           signal driven by axi4 master
  AXI4_AWLOCK                     Input      1           signal driven by axi4 master
  AXI4_AWCACHE                    Input      4           signal driven by axi4 master
  AXI4_AWPROT                     Input      3           signal driven by axi4 master
  AXI4_AWQOS                      Input      4           signal driven by axi4 master
  AXI4_AWREGION                   Input      4           signal driven by axi4 master
  AXI4_WVALID                     Input      1           signal driven by axi4 master
  AXI4_WDATA                      Input      32          signal driven by axi4 master
  AXI4_WSTRB                      Input      4           signal driven by axi4 master
  AXI4_WLAST                      Input      1           signal driven by axi4 master
  AXI4_BREADY                     Input      1           signal driven by axi4 master
  AXI4_ARVALID                    Input      1           signal driven by axi4 master
  AXI4_ARID                       Input      4           signal driven by axi4 master
  AXI4_ARADDR                     Input      32          signal driven by axi4 master
  AXI4_ARLEN                      Input      8           signal driven by axi4 master
  AXI4_ARSIZE                     Input      3           signal driven by axi4 master
  AXI4_ARBURST                    Input      2           signal driven by axi4 master
  AXI4_ARLOCK                     Input      1           signal driven by axi4 master
  AXI4_ARCACHE                    Input      4           signal driven by axi4 master
  AXI4_ARPROT                     Input      3           signal driven by axi4 master
  AXI4_ARQOS                      Input      4           signal driven by axi4 master
  AXI4_ARREGION                   Input      4           signal driven by axi4 master
  AXI4_RREADY                     Input      1           signal driven by axi4 master
  APB_PREADY                      Input      1           signal driven by the apb slaves
  APB_PRDATA                      Input      16          signal driven by the apb slaves
  APB_PSLVERR                     Input      1           signal driven by the apb slaves
  ==============================  =========  ==========  ======================== 

