##########
Test Infra
##########

Generating Verilog
==================

The `synth_instance.bsv` contains 4 synthesizable modules:

  - ``mkinst_onlyfabric`` : contains axi-protocol interfaces and only the cross-bar fabric which uses
    FIFO based transactors internally.
  - `mkinst_onlyfabric_2`` : contains axi-protocol interfaces and only the cross-bar fabric which uses
    CReg based transactors internally.
  - ``mkinst_withxactors`` : constains fifo-side interfaces of master/slave transactors which are
    connected through a cross-bar fabric. All transactors are FIFO based.
  - ``mkinst_withxactors_2`` : constains fifo-side interfaces of master/slave transactors which are
    connected through a cross-bar fabric. All transactors are CReg based.

The number of masters and slaves in each of the above modules is configurable and can be set at
compile time by either changing the variables: ``MASTERS`` and ``SLAVES`` in the Makefile.inc file
or setting them during the make command.

Command to generate verilog
---------------------------

.. code-block:: bash

   make generate_verilog
            OR
   make MASTERS=1 SLAVES=3 generate_verilog


