
include Makefile.inc

BUILD:=./build
BSVBUILDDIR:=$(BUILD)/hw/intermediate
BSVOUTDIR:=./bin/
VERILOGDIR:=$(BUILD)/hw/verilog
define_macros:= -D simulate -D ASSERT=True -D nmasters=$(MASTERS) -D nslaves=$(SLAVES) -D simulate

# ---------- bluespec related settings -----------------------
BSVINCDIR:= ./:%/Libraries:$(INCDIR)
BSC_DIR:=$(shell which bsc)
BSC_VDIR:=$(subst bin/bsc,bin/,${BSC_DIR})../lib/Verilog
BSCCMD:=bsc -u -verilog -elab -vdir $(VERILOGDIR) -bdir $(BSVBUILDDIR) -info-dir $(BSVBUILDDIR) \
	+RTS -K40000M -RTS -check-assert  -keep-fires -opt-undetermined-vals -remove-false-rules \
	-remove-empty-rules -remove-starved-rules -remove-dollar -unspecified-to X -show-schedule \
	-steps-warn-interval 500000 -show-module-use $(define_macros)
# -------------------------------------------------------------

# ---------- verilator related settings -----------------------
VERILATOR_FLAGS:= -O3 -LDFLAGS "-static" --x-assign fast  --x-initial fast --noassert \
	sim_main.cpp --bbox-sys -Wno-STMTDLY  -Wno-UNOPTFLAT -Wno-WIDTH -Wno-lint -Wno-COMBDLY \
	-Wno-INITIALDLY  --autoflush   --threads 1 -DBSV_RESET_FIFO_HEAD  -DBSV_RESET_FIFO_ARRAY \
	--output-split 20000  --output-split-ctrace 10000 --trace
VERILATOR_SPEED:=OPT_SLOW="-O3" OPT_FAST="-O3"
# -------------------------------------------------------------

default: generate_verilog link_verilator simulate

.PHONY: link_verilator
link_verilator: ## Generate simulation executable using Verilator
	@echo "Linking $(TOP_MODULE) using verilator"
	@mkdir -p $(BSVOUTDIR) obj_dir
	@echo "#define TOPMODULE V$(TOP_MODULE)" > sim_main.h
	@echo '#include "V$(TOP_MODULE).h"' >> sim_main.h
	verilator $(VERILATOR_FLAGS) --cc $(TOP_MODULE).v -y $(VERILOGDIR) \
		-y $(BSC_VDIR) -y common_verilog --exe
	@ln -f -s ../test_soc/sim_main.cpp obj_dir/sim_main.cpp
	@ln -f -s ../sim_main.h obj_dir/sim_main.h
	make $(VERILATOR_SPEED) VM_PARALLEL_BUILDS=1 -j4 -C obj_dir -f V$(TOP_MODULE).mk
	@cp obj_dir/V$(TOP_MODULE) $(BSVOUTDIR)/out

.PHONY: generate_verilog 
generate_verilog:
	@echo Compiling $(TOP_MODULE) in verilog ...
	@mkdir -p $(BSVBUILDDIR); 
	@mkdir -p $(VERILOGDIR); 
	$(BSCCMD) -p $(BSVINCDIR) -g $(TOP_MODULE) $(TOP_DIR)/$(TOP_FILE)  || (echo "BSC COMPILE ERROR"; exit 1)

.PHONY: simulate
simulate:
	@echo Simulating $(TOP_MODULE)
	@./bin/out +fullverbose 
	@echo Simulation Done

.PHONY: clean
clean:
	rm -rf $(BUILD) $(BSVOUTDIR) *.jou *.log obj_dir sim_main.h
