.. _axil2apb_bridge:

#######################
AXI4-Lite to APB Bridge
#######################

An AXI4-Lite master device can be configured to work on an APB cluster as a master using the ``Axil2Apb``
bridge. This module implements a bridge/adapter which can be used to convert AXI4-Lite transactions into APB 
(a.k.a APB4, a.k.a APBv2.0) transactions. This bridge acts as a slave on the AXI4-Lite 
interface and as a master on an APB interface. Both the protocols are little endian.
The bridge is parameterized to handle different address and data sizes of either
side with the following contraints:

1. The AXI4-Lite address size must be greater than or equal to the APB address size.
2. The AXI4-Lite data size must be greater than of equal to the APB data size.
3. The AXI4-Lite data and APB data should both be byte-multiples

The bridge also supports spliting of read/write bursts from the AXI4-Lite side to individual requests on
the APB cluster.

A Connectable instance is also provided which can directly connect an AXI4-Lite master interface to a
APB-slave interface.

The verilog RTL will have a AXI4-Lite slave interface which should be connected to a AXI4-Lite master device
and will have an APB master interface on the other side which should be connected to an APB slave
cluster.

Parameters
==========

The bridge interface has the following parameters:

.. tabularcolumns:: |l|L|

.. _axil2apb_bridge_params:

.. table:: AXI4-Lite to APB Bridge Interface Parameters

  ==================  ===========
  Parameter Name      Description
  ------------------  -----------
  ``axi_addr``        size of the address fields on the read and write channels of the AXI4-Lite interface
  ``axi_data``        size of the data fields on the read-response and write-data channels of the AXI4-Lite
                      interface
  ``apb_addr``        size of the address field on the APB interface
  ``apd_data``        size of the read and write data fields on the APB interface
  ``user``            size of the user field on both the AXI and the APB sides.
  ==================  ===========

Micro Architecture
==================

Since the APB is a single channel bus and the AXI4-Lite has separate read and write channels, the read
requests from the AXI4-Lite are given priority over the write requests occurring in the same cycle.

Differing Address sizes
-----------------------

When the AXI4-Lite and APB address sizes are different, then the lower bits of the AXI4-Lite addresses are
used on the APB side. 

Differing Data sizes
--------------------

When the AXI4-Lite and APB data sizes are different, each of the AXI4-Lite request (read or write)
is split into multiple smaller child bursts (sent as individual APB requests) which matches 
APB data size. A transaction is complete only when its corresponding child-bursts are over. 

When instantiated with same data-sizes, the child-burst logic is ommitted.

Error mapping
-------------

The APB PSLVERR is mapped to the AXI4-Lite SLVERR.

Using the AXI4-Lite to APB Bridge
=================================

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
   is used for configuring the crossbar. Please refer to :numref:`axil2apb_bridge_params` 
   for information on the parameters used in the yaml file. 
   
3. **Generate Verilog**: use the following command with required settings to
   generate verilog for synthesis/simulation:

   .. code:: bash

     make TOP_FILE=axil2apb_bridge.bsv TOP_MODULE=mkaxil2apb_bridge generate_instances
   
   The generated verilog file is available in: ``build/hw/verilog/mkaxil2apb_bridge.v``

5. **Interface signals**: in the generated verilog, all the AXI4-Lite signals start with the prefix
   ``AXI4L_`` and the APB signals start with the prefix ``APB_``. Since the IP is a
   synchronous IP, the same clock and reset (active-low) signals (``CLK`` and ``RST_N``) are used by 
   all channles across all devices.

6. **Simulation**: The top module for simulation is ``mkaxil2apb_bridge``. Please follow the steps
   mentioned in :numref:`verilog_sim_env` when compiling the top-module for simulation

Verilog Signals
---------------

:numref:`verilog_names_axil2apb` describes the signals in the generated verilog for the following configuration 

.. code:: bash

    axi_addr:  32
    axi_data:  32
    apb_addr:  24
    apb_data:  16
    user    :  0

.. _verilog_names_axil2apb:

.. table:: AXI4-Lite to APB bridge interface signals in from verilog

  ==============================  =========  ==========  ======================== 
  Signal Names                    Direction  Size(Bits)  Description          
  ------------------------------  ---------  ----------  ------------------------ 
  CLK                             Input      1           clock for all channels 
  RST\_N                          Input      1           an active low reset    
  AXI4L_AWREADY                   Output     1           signal sent to axi4 master 
  AXI4L_WREADY                    Output     1           signal sent to axi4 master
  AXI4L_BVALID                    Output     1           signal sent to axi4 master
  AXI4L_BRESP                     Output     2           signal sent to axi4 master
  AXI4L_ARREADY                   Output     1           signal sent to axi4 master
  AXI4L_RVALID                    Output     1           signal sent to axi4 master
  AXI4L_RDATA                     Output     32          signal sent to axi4 master
  AXI4L_RRESP                     Output     2           signal sent to axi4 master
  APB_PADDR                       Output     24          signal sent to apb slaves
  APB_PROT                        Output     3           signal sent to apb slaves 
  APB_PENABLE                     Output     1           signal sent to apb slaves  
  APB_PWRITE                      Output     1           signal sent to apb slaves 
  APB_PWDATA                      Output     16          signal sent to apb slaves
  APB_PSTRB                       Output     2           signal sent to apb slaves 
  APB_PSEL                        Output     1           signal sent to apb slaves
  AXI4L_AWVALID                   Input      1           signal driven by axi4 master
  AXI4L_AWADDR                    Input      32          signal driven by axi4 master
  AXI4L_AWPROT                    Input      3           signal driven by axi4 master
  AXI4L_WVALID                    Input      1           signal driven by axi4 master
  AXI4L_WDATA                     Input      32          signal driven by axi4 master
  AXI4L_WSTRB                     Input      4           signal driven by axi4 master
  AXI4L_BREADY                    Input      1           signal driven by axi4 master
  AXI4L_ARVALID                   Input      1           signal driven by axi4 master
  AXI4L_ARADDR                    Input      32          signal driven by axi4 master
  AXI4L_ARPROT                    Input      3           signal driven by axi4 master
  AXI4L_RREADY                    Input      1           signal driven by axi4 master
  APB_PREADY                      Input      1           signal driven by the apb slaves
  APB_PRDATA                      Input      16          signal driven by the apb slaves
  APB_PSLVERR                     Input      1           signal driven by the apb slaves
  ==============================  =========  ==========  ======================== 

