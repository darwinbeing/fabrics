<div class="title-block" style="text-align: center;" align="center">

# Interconnect IPs
</div>

This repository contains implementations for various bus protocols, fabrics and bridges. All of these
are designed using Bluespec System Verilog (BSV) the compiler for which is open-source and available
here: [BSVLang](https://github.com/BSVLang/Main). 

The generated verilog RTL is completely synthesizable (FPGA proven) and can also be simulated in 
any verilog simulator.

The list of currently avaiable bus implementations:


1. **[AMBA] AXI4 (Advanced eXtensible Interface)** : This is a fully-functional ``M`` master to 
   ``S`` slave AXI-4 cross-bar interconnect. The implementation supports all burst-modes. The
   cross-bar also comes with master and slave transactors which provide a simple fifo-based inteface
   to quick;y integrate with a custom IPs. Area optimized variants are also available.
2. **[AMBA] AXI4-Lite (Advanced eXtensible Interface - Lite)** : This is a fully-functional ``M`` master to 
   ``S`` slave AXI-4 Lite cross-bar interconnect. The cross-bar also comes with master and slave 
   transactors which provide a simple fifo-based inteface to quickly integrate with a custom IPs. 
   Area optimized variants are also available.
3. **[AMBA] APB (Advanced Peripheral Bus)** : This is a complete implementation of a single master
   and ``S`` slave compliant with APB v2.0. 

The list of currently available bridges/adapters to communicate between the above mentioned
protocols are:

1. **AXI4-2-APB** : This bridge translates AXI4 transactions into APB transactions. It functions as a
   slave on the AXI4 interface and as a master on the APB interface. The bridge also handles
   burst requests from the AXI4 side and supports all burst-modes. The bridge can also be used to
   connect interfaces with varying sizes (under certain restrictions)
2. **AXI4Lite-2-APB** : This bridge translates AXI4-Lite transactions into APB transactions. It functions as a
   slave on the AXI4-Lite interface and as a master on the APB interface. The bridge can also be used to
   connect interfaces with varying sizes (under certain restrictions)
3. **AXI4-2-AXI4-Lite** : This bridge translates AXI4 transactions into AXI4-Lite transactions. It functions as a
   slave on the AXI4 interface and as a master on the AXI4-Lite interface. The bridge also handles
   burst requests from the AXI4 side and supports all burst-modes. The bridge can also be used to
   connect interfaces with varying sizes (under certain restrictions)

# [Detailed Documentation PDF](https://gitlab.com/incoresemi/ip-datasheets/-/jobs/artifacts/master/raw/incore-datasheets/interconnect_ip.pdf?job=pdf_gen) 
