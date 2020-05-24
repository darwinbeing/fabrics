Revisions
=========

[1.1.3]
  - IP updates (1.1.3)

    * added an extra master-transactor side fifo arry for the W channel book-keeping

  - Doc updates (May 27 2020)

    * updated docs extensively to capture the working of the current implementation.

[1.1.2]
  - Doc updates (May 7 2020)

    * remove version from the front page.

  - IP updates (1.1.2)
    
    * explicitly check if the master xactors have pending transactions, for participation in round robin 
      arbitration. This has been applied to axi4 and axi4l fabrics

[1.1.1]
  - IP updates (1.1.1)
    
    * removing dtc dependency check from manager.sh

[1.1.0]
  - Doc updates (April 23 2020)

    * updated steps in all IPs to use a config yaml

  - IP updates (1.1.0)

    * using yaml files to configure instances.
    * using cog to generate instance files and thereby verilog.
    * use same memory map function return type in apb as axi
    * round-robin logic in axi4/axi4lite updated. We now maintain a tiney register per slave to track
      its priority. This removes the restriction of having only max 5 masters on the crossbars.
    * remove README in axi4/test and axi4_lite/test folders
    * new targets in Makefile for generating bsv instance files through cogapp
    * suppressed warnings during Bluespec compilation
    * adding test-config.py to automate generation of legal parameters of various ips.

  
