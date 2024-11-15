## DO NOT MODIFY ANYTHING IN THIS FILE WITHOUT PERMISSION FROM THE INSTRUCTOR OR TAs

# Path to the repository root
REPO_ROOT ?= $(shell git rev-parse --show-toplevel)

# If you have iverilog or verilator installed in a non-standard path,
# you can override these to specify the path to the executable.
IVERILOG ?= iverilog
VERILATOR ?= verilator

# This is a little bit hacky, but sufficient. In order to make sure
# that students can edit the filelist, that make knows about updates
# to that filelist *and* the files themselves, and that pytest can
# read the filelist, we store the listlist in a json file. We then
# read the json file while checking dependencies.
SIM_SOURCES = $(shell python3 $(REPO_ROOT)/util/get_filelist.py)
SIM_SOURCES := $(addprefix $(REPO_ROOT)/,$(SIM_SOURCES))
SIM_TOP = $(shell python3 $(REPO_ROOT)/util/get_top.py)

all: help

# Run both simulators
test: icarus.json verilator.json

verilator.json: filelist.json $(SIM_SOURCES)
	REPO_ROOT=$(REPO_ROOT) SIM=verilator pytest -rA
	mv results.json $@


icarus.json: filelist.json $(SIM_SOURCES)
	REPO_ROOT=$(REPO_ROOT) SIM=icarus pytest -rA
	mv results.json $@

# lint runs the Verilator linter on your code.
lint:
	$(VERILATOR) --lint-only -top $(SIM_TOP) $(SIM_SOURCES)  -Wall

# Remove all compiler outputs
sim-clean:
	rm -rf run
	rm -rf build
	rm -rf lint
	rm -rf __pycache__
	rm -rf .pytest_cache
	rm -rf $(ISIM_LOG) $(ISIM_WAV) $(ISIM_EXE)
	rm -rf $(VSIM_LOG) $(VSIM_WAV) 
	rm -rf obj_dir

# Remove all generated files
extraclean: clean
	rm -f results.json
	rm -f verilator.json
	rm -f icarus.json

.PHONY: help targets-help sim-help sim-vars-help vars-intro-help sim-help intro-vars-help vars-help sim-vars-help lint test all clean extraclean icarus.json verilator.json

sim-help:
	@echo "  test: Run icarus, and then verilator to generate both json files"
	@echo "  icarus.json: Run all tests using the icarus verilog simulator"
	@echo "  verilator.json: Run all tests using the Verilator simulator"
	@echo "  lint: Run the Verilator linter on all source files"
	@echo "  clean: Remove all compiler outputs."
	@echo "  extraclean: Remove all generated files (runs clean)"

vars-intro-help:
	@echo ""
	@echo "  Optional Environment Variables:"

sim-vars-help:

clean: sim-clean
targets-help: sim-help
vars-help: vars-intro-help sim-vars-help

help: targets-help vars-help 
