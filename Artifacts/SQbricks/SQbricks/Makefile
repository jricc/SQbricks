# This file is part of SQbricks.
#
# Copyright (C) 2022-2026
# CEA (Commissariat à l'énergie atomique et aux énergies alternatives)
# Université Paris-Saclay
#
# you can redistribute it and/or modify it under the terms of the GNU
# Lesser General Public License as published by the Free Software
# Foundation, version 2.1.
#
# It is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# See the GNU Lesser General Public License version 2.1
# for more details (enclosed in the file licenses/LGPLv2.1).

.PHONY: all benchmark sanity sanity-unit sanity-hybrid sanity-partial benchmarks \
        benchmark-sqbricks benchmarks-sqbricks \
        regression-light regression-light-baseline regression-light-check \
        benchmark-regression-large benchmark-regression-large-baseline \
        benchmark-regression-large-check regression-large \
        regression-large-baseline regression-large-check \
        owm tele unit-vs-hybrid qiskit-hybrid owm-vs-qiskit owm-vs-tele veriqc \
        tests tests_prim tests_qiskit tests_mbqc tests_unit tests_regression_light \
        build container start fig6 fig7 examples \
				doc clean_doc

DATE := $(shell date +%Y-%m)
DATE_FILE := $(shell date +%Y-%m-%d)
RESULT_FOLDER := benchmarks/result/$(DATE)
LOG_FOLDER := test/logs/$(DATE)
LIGHT_BASELINE ?= benchmarks/baseline/light.csv
LIGHT_RESULT ?= benchmarks/result/light_$(DATE_FILE).csv
LIGHT_RUNS ?= 3
LONG_TYPES ?= sanity-unit sanity-hybrid sanity-partial unit-vs-hybrid veriqc qiskit-hybrid owm tele owm-vs-tele owm-vs-qiskit
LONG_PROGRESS ?= auto
LARGE_TYPES ?= sanity-unit sanity-hybrid sanity-partial unit-vs-hybrid veriqc qiskit-hybrid owm tele owm-vs-tele owm-vs-qiskit
LARGE_PATH_DIR ?= scripts/paths/regression-large
LARGE_BASELINE_DIR ?= benchmarks/baseline/regression-large
LARGE_PROGRESS ?= auto
LARGE_PERF_THRESHOLD ?= 1.25
LARGE_MIN_SLOWDOWN_SECONDS ?= 5
MAKEFLAGS += --no-print-directory

# Documentation generation
DOC_DIR := $(shell pwd)/doc/doc-$(DATE_FILE)

doc:
	@echo "Generating documentation..."
	@dune build @doc
	@rm -rf $(DOC_DIR)  
	@mkdir -p $(DOC_DIR)
	@cp -r _build/default/_doc/_html/* $(DOC_DIR)/
	@echo "Documentation generated in $(DOC_DIR)"
	@if command -v open > /dev/null; then open $(DOC_DIR)/index.html; fi 2>/dev/null || true

clean_doc:
	dune clean

# Tests

tests: tests_prim tests_qiskit tests_mbqc tests_unit tests_verif tests_regression_light

tests_regression_light:
	bash test/benchmarks-light-validation.sh

tests_qiskit:
	@rm -rf $(shell pwd)/_build/qiskit
	@mkdir -p $(shell pwd)/_build
	@mkdir -p $(LOG_FOLDER)
	dune build @qiskit --build-dir $(shell pwd)/_build/qiskit > $(LOG_FOLDER)/qiskit_$(DATE_FILE).log 2>&1

tests_unit:
	@rm -rf $(shell pwd)/_build/unitary
	@mkdir -p $(shell pwd)/_build
	@mkdir -p $(LOG_FOLDER)
	dune build @unitary --build-dir $(shell pwd)/_build/unitary > $(LOG_FOLDER)/unitary_$(DATE_FILE).log 2>&1

tests_prim:
	@rm -rf $(shell pwd)/_build/primitives
	@mkdir -p $(shell pwd)/_build
	@mkdir -p $(LOG_FOLDER)
	dune build @primitives --build-dir $(shell pwd)/_build/primitives > $(LOG_FOLDER)/primitives_$(DATE_FILE).log 2>&1
	
tests_mbqc:
	@rm -rf $(shell pwd)/_build/mbqc
	@mkdir -p $(shell pwd)/_build
	@mkdir -p $(LOG_FOLDER)
	dune build @mbqc --build-dir $(shell pwd)/_build/mbqc > $(LOG_FOLDER)/mbqc_$(DATE_FILE).log 2>&1

tests_verif:
	@rm -rf $(shell pwd)/_build/verif
	@mkdir -p $(shell pwd)/_build
	@mkdir -p $(LOG_FOLDER)
	dune build @verif --build-dir $(shell pwd)/_build/verif > $(LOG_FOLDER)/verif_$(DATE_FILE).log 2>&1


# Benchmark & Sanity check

benchmark:
	@mkdir -p $(RESULT_FOLDER)
	@./scripts/benchmarks.sh $(TYPE) >> $(RESULT_FOLDER)/benchmarks_$(TYPE)_$(DATE_FILE).csv 2>/dev/null || true

# Run one SQbricks-only benchmark family, for example:
#   make benchmark-sqbricks TYPE=owm
benchmark-sqbricks:
	@if [ -z "$(TYPE)" ]; then echo "TYPE is required, for example: make benchmark-sqbricks TYPE=owm"; exit 1; fi
	@mkdir -p $(RESULT_FOLDER) $(shell pwd)/_build/sqbricks-long/$(TYPE)
	@DUNE_BUILD_DIR=$(shell pwd)/_build/sqbricks-long/$(TYPE) dune build
	@DUNE_BUILD_DIR=$(shell pwd)/_build/sqbricks-long/$(TYPE) SQBRICKS_LONG_PROGRESS=$(LONG_PROGRESS) bash scripts/benchmarks-sqbricks.sh $(TYPE) > $(RESULT_FOLDER)/benchmarks_sqbricks_$(TYPE)_$(DATE_FILE).csv
	@echo "SQbricks benchmark $(TYPE) written to $(RESULT_FOLDER)/benchmarks_sqbricks_$(TYPE)_$(DATE_FILE).csv"

# Run the full SQbricks-only benchmark campaign by calling benchmark-sqbricks
# once per family listed in LONG_TYPES.
benchmarks-sqbricks:
	@for type in $(LONG_TYPES); do \
		$(MAKE) TYPE=$$type benchmark-sqbricks || exit $$?; \
	done


sanity: sanity-unit sanity-hybrid sanity-partial

sanity-unit:
	@echo "sanity-unit" 
	@rm -rf $(shell pwd)/_build/sanity-unit 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@$(MAKE) TYPE=sanity-unit benchmark 

sanity-hybrid:
	@echo "sanity-hybrid"
	@rm -rf $(shell pwd)/_build/sanity-hybrid 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@$(MAKE) TYPE=sanity-hybrid benchmark 

sanity-partial:
	@echo "sanity-partial"
	@rm -rf $(shell pwd)/_build/sanity-partial 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@$(MAKE) TYPE=sanity-partial benchmark


benchmarks: tele owm  owm-vs-qiskit owm-vs-tele qiskit-hybrid veriqc unit-vs-hybrid
#      

regression-light:
	@SQBRICKS_LIGHT_RUNS=$(LIGHT_RUNS) ./scripts/benchmarks-light.sh --output $(LIGHT_RESULT) --quiet
	@echo "Light regression benchmark written to $(LIGHT_RESULT) using $(LIGHT_RUNS) round(s)"

regression-light-baseline:
	@SQBRICKS_LIGHT_RUNS=$(LIGHT_RUNS) ./scripts/benchmarks-light.sh --save-baseline $(LIGHT_BASELINE) --quiet
	@echo "Light regression baseline written to $(LIGHT_BASELINE) using $(LIGHT_RUNS) round(s)"

regression-light-check:
	@SQBRICKS_LIGHT_RUNS=$(LIGHT_RUNS) ./scripts/benchmarks-light.sh --baseline $(LIGHT_BASELINE) --check --output $(LIGHT_RESULT) --quiet

# Run one selected large-regression benchmark family without using the light
# runner. The selected paths live in LARGE_PATH_DIR/paths_$(TYPE).txt.
benchmark-regression-large:
	@if [ -z "$(TYPE)" ]; then echo "TYPE is required, for example: make benchmark-regression-large TYPE=owm"; exit 1; fi
	@if [ ! -f "$(LARGE_PATH_DIR)/paths_$(TYPE).txt" ]; then echo "Missing large regression path file: $(LARGE_PATH_DIR)/paths_$(TYPE).txt"; exit 1; fi
	@if [ "$(TYPE)" = "qiskit-hybrid" ] || [ "$(TYPE)" = "owm-vs-qiskit" ]; then python3 -c 'from qiskit import qasm2; from qiskit.circuit import QuantumCircuit; from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager' >/dev/null 2>&1 || { echo "Missing Python dependency: qiskit is required for $(TYPE)."; exit 1; }; fi
	@mkdir -p $(RESULT_FOLDER) $(shell pwd)/_build/regression-large/$(TYPE)
	@DUNE_BUILD_DIR=$(shell pwd)/_build/regression-large/$(TYPE) dune build
	@DUNE_BUILD_DIR=$(shell pwd)/_build/regression-large/$(TYPE) SQBRICKS_LONG_PATH_FILE=$(LARGE_PATH_DIR)/paths_$(TYPE).txt SQBRICKS_LONG_PROGRESS=$(LARGE_PROGRESS) bash scripts/benchmarks-sqbricks.sh $(TYPE) > $(RESULT_FOLDER)/regression_large_$(TYPE)_$(DATE_FILE).csv
	@echo "Large regression benchmark $(TYPE) written to $(RESULT_FOLDER)/regression_large_$(TYPE)_$(DATE_FILE).csv"

benchmark-regression-large-baseline:
	@if [ -z "$(TYPE)" ]; then echo "TYPE is required, for example: make benchmark-regression-large-baseline TYPE=owm"; exit 1; fi
	@if [ ! -f "$(LARGE_PATH_DIR)/paths_$(TYPE).txt" ]; then echo "Missing large regression path file: $(LARGE_PATH_DIR)/paths_$(TYPE).txt"; exit 1; fi
	@if [ "$(TYPE)" = "qiskit-hybrid" ] || [ "$(TYPE)" = "owm-vs-qiskit" ]; then python3 -c 'from qiskit import qasm2; from qiskit.circuit import QuantumCircuit; from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager' >/dev/null 2>&1 || { echo "Missing Python dependency: qiskit is required for $(TYPE)."; exit 1; }; fi
	@mkdir -p $(LARGE_BASELINE_DIR) $(shell pwd)/_build/regression-large/$(TYPE)
	@DUNE_BUILD_DIR=$(shell pwd)/_build/regression-large/$(TYPE) dune build
	@DUNE_BUILD_DIR=$(shell pwd)/_build/regression-large/$(TYPE) SQBRICKS_LONG_PATH_FILE=$(LARGE_PATH_DIR)/paths_$(TYPE).txt SQBRICKS_LONG_PROGRESS=$(LARGE_PROGRESS) bash scripts/benchmarks-sqbricks.sh $(TYPE) > $(LARGE_BASELINE_DIR)/$(TYPE).csv
	@echo "Large regression baseline $(TYPE) written to $(LARGE_BASELINE_DIR)/$(TYPE).csv"

benchmark-regression-large-check:
	@if [ -z "$(TYPE)" ]; then echo "TYPE is required, for example: make benchmark-regression-large-check TYPE=owm"; exit 1; fi
	@if [ ! -f "$(LARGE_PATH_DIR)/paths_$(TYPE).txt" ]; then echo "Missing large regression path file: $(LARGE_PATH_DIR)/paths_$(TYPE).txt"; exit 1; fi
	@if [ ! -f "$(LARGE_BASELINE_DIR)/$(TYPE).csv" ]; then echo "Missing large regression baseline: $(LARGE_BASELINE_DIR)/$(TYPE).csv"; exit 1; fi
	@if [ "$(TYPE)" = "qiskit-hybrid" ] || [ "$(TYPE)" = "owm-vs-qiskit" ]; then python3 -c 'from qiskit import qasm2; from qiskit.circuit import QuantumCircuit; from qiskit.transpiler.preset_passmanagers import generate_preset_pass_manager' >/dev/null 2>&1 || { echo "Missing Python dependency: qiskit is required for $(TYPE)."; exit 1; }; fi
	@mkdir -p $(RESULT_FOLDER) $(shell pwd)/_build/regression-large/$(TYPE)
	@DUNE_BUILD_DIR=$(shell pwd)/_build/regression-large/$(TYPE) dune build
	@DUNE_BUILD_DIR=$(shell pwd)/_build/regression-large/$(TYPE) SQBRICKS_LONG_PATH_FILE=$(LARGE_PATH_DIR)/paths_$(TYPE).txt SQBRICKS_LONG_PROGRESS=$(LARGE_PROGRESS) bash scripts/benchmarks-sqbricks.sh $(TYPE) > $(RESULT_FOLDER)/regression_large_$(TYPE)_$(DATE_FILE).csv
	@SQBRICKS_LARGE_PERF_THRESHOLD=$(LARGE_PERF_THRESHOLD) SQBRICKS_LARGE_MIN_SLOWDOWN_SECONDS=$(LARGE_MIN_SLOWDOWN_SECONDS) bash scripts/check-regression-large.sh $(LARGE_BASELINE_DIR)/$(TYPE).csv $(RESULT_FOLDER)/regression_large_$(TYPE)_$(DATE_FILE).csv $(TYPE)

regression-large:
	@for type in $(LARGE_TYPES); do \
		$(MAKE) TYPE=$$type benchmark-regression-large || exit $$?; \
	done

regression-large-baseline:
	@for type in $(LARGE_TYPES); do \
		$(MAKE) TYPE=$$type benchmark-regression-large-baseline || exit $$?; \
	done

regression-large-check:
	@status=0; failed=""; \
	for type in $(LARGE_TYPES); do \
		if ! $(MAKE) TYPE=$$type benchmark-regression-large-check; then \
			status=1; \
			failed="$$failed $$type"; \
			echo "Large regression check failed for $$type; continuing." >&2; \
		fi; \
	done; \
	if [ $$status -ne 0 ]; then \
		echo "Large regression check completed with failure(s):$$failed" >&2; \
		exit $$status; \
	fi

owm:
	@echo "owm"
	@rm -rf $(shell pwd)/_build/owm 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@dune build --build-dir $(shell pwd)/_build/owm 
	@$(MAKE) TYPE=owm benchmark

tele: 
	@echo "tele"
	@rm -rf $(shell pwd)/_build/tele 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@dune build --build-dir $(shell pwd)/_build/tele 
	@$(MAKE) TYPE=tele benchmark

unit-vs-hybrid: 
	@echo "unit-vs-hybrid"
	@rm -rf $(shell pwd)/_build/unit-vs-hybrid 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@dune build --build-dir $(shell pwd)/_build/unit-vs-hybrid 
	@$(MAKE) TYPE=unit-vs-hybrid benchmark

qiskit-hybrid: 
	@echo "qiskit-hybrid"
	@rm -rf $(shell pwd)/_build/qiskit-hybrid 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@dune build --build-dir $(shell pwd)/_build/qiskit-hybrid
	@$(MAKE) TYPE=qiskit-hybrid benchmark

owm-vs-qiskit: 
	@echo "owm-vs-qiskit"
	@rm -rf $(shell pwd)/_build/owm-vs-qiskit 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@dune build --build-dir $(shell pwd)/_build/owm-vs-qiskit
	@$(MAKE) TYPE=owm-vs-qiskit benchmark

owm-vs-tele: 
	@echo "owm-vs-tele"
	@rm -rf $(shell pwd)/_build/owm-vs-tele 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@dune build --build-dir $(shell pwd)/_build/owm-vs-tele
	@$(MAKE) TYPE=owm-vs-tele benchmark

veriqc: 
	@echo "veriqc"
	@rm -rf $(shell pwd)/_build/veriqc 2>/dev/null || true
	@mkdir -p $(shell pwd)/_build
	@dune build --build-dir $(shell pwd)/_build/veriqc
	@$(MAKE) TYPE=veriqc benchmark


all: benchmarks sanity

# Paper Examples

examples: ex3 ex4

ex3:
	python3 scripts/Example-3.py

ex4:
	python3 scripts/Example-4.py

# Docker Build

build:
	docker build -t sqbricks .

container:
	bash container.sh


## Docker Pull (Alternative to Build)

pull:
	docker pull jricc/sqbricks:latest

container-pull:
	bash container.sh --custom-image

# Container Start

start: container

start1:
	bash container.sh

start2:
	bash container.sh
