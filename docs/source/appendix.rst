.. _appendix:

###########
Appendix
###########

* `Open Bluespec Compiler <https://github.com/B-Lang-org/bsc>`__ can be cloned and installed by following the steps in the repository. 
* For design simulation, please install `Verilator <https://www.veripool.org/projects/verilator/wiki/Installing>`__
* InCore python utilities require Python 3.7.0. Detailed instructions for the same is provided below.


Install Python Dependencies
===========================

All python utilities require ``pip`` and ``python`` (>=3.7) to be available on your system. If you have issues installing, either of these, directly on your system we suggest using a virtual environment like `pyenv` to make things easy.


First Install the required libraries/dependencies:

.. code-block:: bash

    $ sudo apt-get install -y make build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
        xz-utils tk-dev libffi-dev liblzma-dev python-openssl git

Next, install `pyenv`

.. code-block:: bash

  $ curl -L https://raw.githubusercontent.com/yyuu/pyenv-installer/master/bin/pyenv-installer | bash

Add the following to your `.bashrc` with appropriate changes to username:

.. code-block:: bash

  export PATH="/home/<username>/.pyenv/bin:$PATH"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"

Open a new terminal and create a new python virtual environment:

.. code-block:: bash

  $ pyenv install 3.7.0
  $ pyenv virtualenv 3.7.0 myenv

Now you can activate this environment in any other terminal :

.. code-block:: bash

  $ pyenv activate myenv
  $ python --version

Project specific packages can be installed as below:

.. code-block:: bash

  $ pip install cogapp


.. _verilog_sim_env:

Verilog Simulation
===================

Copmile time Macros
--------------------

The macros ``BSV_RESET_FIFO_HEAD`` and  ``BSV_RESET_FIFO_ARRAY`` have
to be enabled during compilation of the verilog sources (for simulation or synthesis)
via the defines routine of the respective simulator.

For example, with QuestaSim it would look like the following:

.. code:: bash

  vsim ... +define+BSV_RESET_FIFO_HEAD +define+BSV_RESET_FIFO_ARRAY ...

For vcs or verilator it sould look like the following:

.. code:: bash

   verilator ... -DBSV_RESET_FIFO_HEAD -DBSV_RESET_FIFO_ARRAY ...
   vcs ... -DBSV_RESET_FIFO_HEAD -DBSV_RESET_FIFO_ARRAY ...

Include Directories
-------------------

The BSV designs might use some components available from bluespec's prec-ompiled verilog module libraries.
When an IP's BSV source code is compiled, only the design's verilog is available in the ``build/hw/verilog``
and the pre-compiled module libraries (in verilog RTL format) have to be either copied manually or
pointed to during verilog compilation.

If you have installed the open-source bluespec compiler, run the following command:

.. code:: bash

   $ which bsc
   >> </installation-path>/bin/bsc

The pre-compiled libraries will therefore be available in ``</installation-path>/lib/Verilog``.
The user can set this as the ``-y`` arguments to all simulators and thus avoid manually copying the
pre-compiled verilog libraries.

