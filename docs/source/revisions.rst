Revisions
=========

**Version [1.1.0]**
^^^^^^^^^^^^^^^^^^^
  - Doc updates (23 April 2020)

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

  
