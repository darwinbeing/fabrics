CHANGELOG
=========

This project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`_.

[1.1.1] - 2020-04-27
--------------------

- removing dtc dependency check from manager.sh

[1.1.0] - 2020-04-23
--------------------

- using yaml files to configure instances.
- using cog to generate instance files and thereby verilog.
- use same memory map function return type in apb as axi
- round-robin logic in axi4/axi4lite updated. We now maintain a tiney register per slave to track
its priority. This removes the restriction of having only max 5 masters on the crossbars.
- remove README in axi4/test and axi4_lite/test folders
- new targets in Makefile for generating bsv instance files through cogapp
- suppressed warnings during Bluespec compilation
- adding test-config.py to automate generation of legal parameters of various ips.
- moving docs from ip-datasheets to fabrics
 

[1.0.1] - 2020-04-19
--------------------

- changed types to small caps
- renamed axil_side to axi4l_side and axi_side to axi4_side
- fixed typos in readme


[1.0.0] - 2020-04-16
--------------------

- Initial stable release
