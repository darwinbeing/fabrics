.. _axi2axil_bridge:

########################
AXI4 to AXI4-Lite Bridge
########################

An AXI4 master device can be configured to work on an AXI4-Lite cluster as a master using the ``Axi2Axil``
bridge. This module implements a bridge/adapter which can be used to convert AXI-4 transactions into AXI4-Lite 
transactions. This bridge acts as a slave on the AXI4 
interface and as a master on an AXI4-Lite interface. Both the protocols are little endian.
The bridge is parameterized to handle different address and data sizes of either
side with the following contraints:

1. The AXI4 address size must be greater than or equal to the AXI4-Lite address size.
2. The AXI4 data size must be greater than of equal to the AXI4-Lite data size.
3. The AXI4 data and AXI4-Lite data should both be byte-multiples

The bridge also supports spliting of read/write bursts from the AXI4 side to individual requests on
the AXI4-Lite cluster.

A Connectable instance is also provided which can directly connect an AXI4 master interface to a
AXI4-Lite-slave interface.

The verilog RTL will have a AXI4 slave interface which should be connected to a AXI4 master device
and will have an AXI4-Lite master interface on the other side which should be connected to an AXI4-Lite slave
cluster.

Parameters
==========

The bridge interface has the following parameters:

.. tabularcolumns:: |l|L|

.. _axi2axil_bridge_params:

.. table:: AXI4 to AXI4-Lite Bridge Interface Parameters

  ==================  ===========
  Parameter Name      Description
  ------------------  -----------
  ``axi_id``          size of the id fields on the AXI4 interface
  ``axi_addr``        size of the address fields on the read and write channels of the AXI4 interface
  ``axi_data``        size of the data fields on the read-response and write-data channels of the AXI4
                      interface
  ``axil_addr``       size of the address field on the AXI4-Lite interface
  ``axil_data``       size of the read and write data fields on the AXI4-Lite interface
  ``user``            size of the user field on both the AXI and the AXI4-Lite sides.
  ==================  ===========

Micro Architecture
==================

The bridges convert single beat or multi-beat requests on the AXI4 channels to
single-beat requests on the respective AXI4-Lite channels. Thus, per channel
(read or write) there is only once outstanding transaction active at a time.

The transaction ID (awid or arid) received is stored in the
conversion bridge, and retrieved during response transfers as BID or RID.

Differing Address sizes
-----------------------

When the AXI4 and AXI4-Lite address sizes are different, then the lower bits of the AXI4 addresses are
used on the AXI4-Lite side. 

Differing Data sizes
--------------------

When the AXI4 and AXI4-Lite data sizes are different, each single beat of the AXI4 request (read or write)
is split into multiple smaller child bursts (sent as individual AXI4-Lite requests) which matches 
AXI4-Lite data size. A beat is complete only when its corresponding child-bursts are over. The next
single-beat address is generated based on the burst-mode request and the burst size. Thus, the
bridge can support all AXI4 burst-modes: incr, fixed and wrap.

When instantiated with same data-sizes, the child-burst logic is ommitted.

Error mapping
-------------

When the data-sizes are the same the AXI4-Lite errors simple propagated to the AXI4 side without 
any changes. However, when the data sizes differ, a single beat from the AXI4
can cause multiple SLVERR and DECERR on the AXI4-Lite side, in which case the
AXI4 is responded with SLVERR i.e. SLVERR is a sticky error.


Using the AXI4 to AXI4-Lite Bridge
===================================

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
   
   The yaml file: ``axi2axil_bridge_config.yaml`` 
   is used for configuring the crossbar. Please refer to :numref:`axi2axil_bridge_params` 
   for information on the parameters used in the yaml file. 
   
4. **Generate Verilog**: use the following command with required settings to
   generate verilog for synthesis/simulation:

   .. code:: bash

     make TOP_FILE=axi2axil_bridge.bsv TOP_MODULE=mkaxi2axil_bridge generate_instances
   
   The generated verilog file is available in: ``build/hw/verilog/mkaxi2axil_bridge.v``

5. **Interface signals**: in the generated verilog, all the AXI4 signals start with the prefix
   ``AXI4_`` and the AXI4-Lite signals start with the prefix ``AXI4-Lite_``. Since the IP is a
   synchronous IP, the same clock and reset (active-low) signals (``CLK`` and ``RST_N``) are used by 
   all channles across all devices.

6. **Simulation**: The top module for simulation is ``mkaxi2axil_bridge``. Please follow the steps
   mentioned in :numref:`verilog_sim_env` when compiling the top-module for simulation

Verilog Signals
---------------

:numref:`verilog_names_axi2axil` describes the signals in the generated verilog for the following configuration 

.. code:: yaml

    axi_id: 4
    axi_addr:  32
    axi_data:  32
    axil_addr:  24
    axil_data:  16
    user    :  0

.. _verilog_names_axi2axil:

.. table:: AXI4 to AXI4-Lite bridge interface signals in from verilog

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
  AXI4L_AWVALID                   Output     1           signal sent to axi4lite slaves   
  AXI4L_AWADDR                    Output     24          signal sent to axi4lite slaves 
  AXI4L_AWPROT                    Output     3           signal sent to axi4lite slaves  
  AXI4L_WVALID                    Output     1           signal sent to axi4lite slaves 
  AXI4L_WDATA                     Output     16          signal sent to axi4lite slaves
  AXI4L_WSTRB                     Output     2           signal sent to axi4lite slaves 
  AXI4L_BREADY                    Output     1           signal sent to axi4lite slaves
  AXI4L_ARVALID                   Output     1           signal sent to axi4lite slaves    
  AXI4L_ARADDR                    Output     24          signal sent to axi4lite slaves 
  AXI4L_ARPROT                    Output     3           signal sent to axi4lite slaves  
  AXI4L_RREADY                    Output     1           signal sent to axi4lite slaves 
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
  AXI4L_AWREADY                   Input      1           signal driven by the axi4lite slaves 
  AXI4L_WREADY                    Input      1           signal driven by the axi4lite slaves
  AXI4L_BVALID                    Input      1           signal driven by the axi4lite slaves
  AXI4L_BRESP                     Input      2           signal driven by the axi4lite slaves  
  AXI4L_ARREADY                   Input      1           signal driven by the axi4lite slaves
  AXI4L_RVALID                    Input      1           signal driven by the axi4lite slaves
  AXI4L_RRESP                     Input      2           signal driven by the axi4lite slaves 
  AXI4L_RDATA                     Input      16          signal driven by the axi4lite slaves
  ==============================  =========  ==========  ======================== 
  
  
