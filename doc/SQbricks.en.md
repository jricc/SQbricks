# SQbricks: technical documentation

[Français](SQbricks.md) | [English](SQbricks.en.md)

## Purpose

This document complements the `README.md`. The README provides a quick entry
point into the project; this document progressively explains the technical
choices we validate during the work.

The first current topic is the light non-regression benchmark. Its goal is
deliberately limited:

- verify that manifest cases still produce the expected status;
- verify that performance-tracked cases do not become clearly slower than
  their local baseline;
- remain readable;
- run in a reasonable time, ideally less than 30 minutes.

## SQbricks overview

SQbricks is a research prototype for verification of hybrid quantum circuits.
A hybrid circuit may combine quantum operations, measurements, and classical
control.

The project contains two main capabilities:

- SQbricks-Lift transforms hybrid circuits to isolate a unitary part;
- SQbricks-Verif compares two unitary circuits and attempts to establish their
  equivalence.

The light benchmark is a short guardrail before running longer campaigns. The
long SQbricks-only benchmark reuses the historical families from
`scripts/benchmarks.sh`, but keeps only SQbricks verification rows in the
generated CSV files.

There is no intermediate benchmark planned for now. It would mostly duplicate
the role of the light benchmark and the long benchmark.

## Light benchmark commands

The entry points are in the `Makefile`:

| Command | Purpose |
| --- | --- |
| `make regression-light` | Run the light benchmark and write a result CSV. |
| `make regression-light-baseline` | Produce the local baseline for the machine. |
| `make regression-light-check` | Compare a new run with that baseline. |
| `make tests_regression_light` | Validate runner behavior with a fake SQbricks. |

The baseline is local to the machine. It must not be versioned.

Progress is printed to `stderr` when it is attached to an interactive terminal.
The bar rewrites a single line and truncates the label if the terminal is too
narrow, to avoid automatic line wrapping. `SQBRICKS_LIGHT_PROGRESS=never`
disables this display.

## Manifests

The benchmark is driven by two files:

| File | Purpose |
| --- | --- |
| `scripts/paths/light/pairs.csv` | Direct comparisons between two circuits. |
| `scripts/paths/light/transforms.csv` | Cases where the runner transforms a circuit before comparison. |

Each row describes:

- the suite and case name;
- the case kind (`unit`, `lift`, `owm`, `tele`, `owm_vs_tele`);
- the expected status in `Sequence` and `Parallel`;
- whether performance is tracked;
- the QASM path or paths.

The `-` value disables a mode. For example, if `ExpectedParallel` is `-`,
`Parallel` is not executed for that case.

## Statuses

The main expected statuses are:

| Status | Meaning |
| --- | --- |
| `EQ` | equivalence proved |
| `NE` | non-equivalence detected |
| `NC` | inconclusive |
| `TIMEOUT` | time limit reached |
| `OOM` | memory limit reached |
| `CRASH` | unexpected failure |
| `PARSE_ERROR` | parsing error |

If SQbricks succeeds but returns an empty or unknown output, the runner reports
`UNEXPECTED_OUTPUT`. This status always fails: it prevents an unrecognized
output from being treated as an acceptable result.

## Baseline and check

`make regression-light-baseline` runs the benchmark and writes a full CSV.
`make regression-light-check` runs it again and compares the results with that
CSV.

The check verifies two things.

First, every executed row must keep its expected status. A different status is
a functional regression.

Second, rows where `TrackPerformance` is `yes` must have:

- a baseline row;
- a positive baseline time;
- exactly one timing sample per round;
- the same round count as the current run.

After execution, the runner also requires one valid timing per round for those
rows. It then keeps the best observed time and compares it with the baseline.
This avoids failing the check because of a local machine-load spike when one
representative round stayed close to the baseline.

A slowdown fails only when two thresholds are exceeded:

- the ratio is greater than `SQBRICKS_LIGHT_PERF_THRESHOLD`;
- the absolute slowdown is greater than
  `SQBRICKS_LIGHT_MIN_SLOWDOWN_SECONDS`.

This double condition avoids reporting noise too easily on very short cases.

## CSV output

The full CSV contains the columns useful for human reading and for check mode:

```text
Suite;Case;Kind;Tool;Version;Lift;Opt;ExpectedStatus;ActualStatus;StatusMatch;CH;CS;CZ;CCZ;CCX;CU1;Gates;TimeSeconds;BaselineSeconds;Ratio;PerfStatus;Raw
```

The `Raw` field contains round details, for example:

```text
rounds=3 status=EQ times=[1.000000,1.100000,0.900000] best=0.900000
```

The runner no longer tries to prove that the baseline exactly matches the QASM
file contents or a full previous manifest definition. If the manifest changes
intentionally, the baseline must be regenerated locally.

## Runner validation tests

`test/benchmarks-light-validation.sh` tests the runner without starting the
real OCaml program. It creates a minimal fixture and puts a fake `dune` at the
front of `PATH`.

The fake `dune` simulates two calls:

- `-nb_gates_csv`, to return a stable gate count;
- `-sqv`, to return the outputs configured by the test.

The remaining scenarios match the light benchmark contract:

- `--check` requires a baseline;
- `--check` cannot be combined with `--stable`;
- a baseline must contain timings for tracked cases;
- performance samples must be complete;
- a functional regression makes the check fail;
- an unknown SQbricks output makes the check fail;
- a significant slowdown makes the check fail;
- exceeding only one performance threshold is not enough;
- an invalid baseline run does not replace the existing baseline;
- a valid baseline run does replace the existing baseline.

The tests no longer cover detailed definition changes or cases removed from the
manifest. This is intentional: those checks made the benchmark harder to read
than necessary for its current goal.

## Long SQbricks-only benchmark

The long benchmark lives in `scripts/benchmarks-sqbricks.sh`. It is close to the
historical `scripts/benchmarks.sh` benchmark, but it does not call external
verification tools such as QCEC, Feynman, PyZX, or AutoQ. The generated CSV
therefore contains SQbricks rows.

The entry points are:

| Command | Purpose |
| --- | --- |
| `make benchmark-sqbricks TYPE=owm` | Run one family. |
| `make benchmarks-sqbricks` | Run every family listed in `LONG_TYPES`. |

The default families are:

```text
sanity-unit sanity-hybrid sanity-partial unit-vs-hybrid veriqc qiskit-hybrid owm tele owm-vs-tele owm-vs-qiskit
```

The `qiskit-hybrid` and `owm-vs-qiskit` families still use
`scripts/qiskit-tr.py` to generate the transformed circuit, as in the
historical benchmark. Qiskit is used here as a case generator, not as an
external verification result in the final CSV.

Each family writes a separate file:

```text
benchmarks/result/<month>/benchmarks_sqbricks_<TYPE>_<date>.csv
```

Resource limits are applied at the beginning of the script with `ulimit`:

- `SQBRICKS_LONG_TIMEOUT`, defaulting to `600` CPU seconds per process;
- `SQBRICKS_LONG_MEMORY_KB`, defaulting to `7340032`.

If a case from an ordered series reaches `TO` or `OutOfMemory`, larger cases in
the same series are no longer executed. A series is identified by the benchmark
type, the source directory, and the name family. The runner writes a CSV row
with `SKIP_AFTER_RESOURCE_FAILURE` and continues with other series. For example,
a failure on `benchmarks/Feynman/grover_5.qasm` does not skip
`benchmarks/VeriQbench/combinational/grover/grover_*.qasm` cases.

Progress is controlled by `SQBRICKS_LONG_PROGRESS=auto|always|never`. Like the
light progress bar, it is printed to `stderr`, rewrites a single line, and does
not pollute the CSV written to `stdout`.

## Selected large regression

The selected large regression is an intermediate step between the light
benchmark and the complete long benchmark. It does not reuse the light runner:
it reuses the long SQbricks-only runner with shorter path files stored in
`scripts/paths/regression-large/`.

The current entry points are:

| Command | Purpose |
| --- | --- |
| `make benchmark-regression-large TYPE=owm` | Run one selected family. |
| `make regression-large` | Run every selected family listed in `LARGE_TYPES`. |

Current status:

- path selections exist for every long benchmark family;
- the runner writes result CSV files;
- baseline/check mode is not implemented yet;
- the next step is to validate the selection, then add a baseline and check
  workflow separate from the light benchmark.

## Equiv audit

The targeted audit of the reduction-to-equivalence pipeline started with
parameter preparation in `lib/equiv.ml`.

The first validated change avoids some uncontrolled exceptions when input or
output lists are incompatible. These cases now return an explicit equivalence
result:

- input lists with different sizes: `NotEquivDiffInputs`;
- output lists with different sizes: `NotEquivDiffOutputs`;
- incompatible input/output counts: `NotEquivDiffInputsOutputs`;
- non-unitary circuit at this stage: `ErrorCircuitNotUnitary`.

The corresponding unit tests were added to `test/unitary.ml` for both
`Sequence` and `Parallel`. The remaining Equiv corrections should continue on a
dedicated branch after the non-regression benchmarks have been validated.

The next planned change concerns reduction errors. A rule may simply not apply
to a valid path sum, but it may also receive a malformed path sum. These two
situations should not have the same return value. The goal is therefore to
introduce a typed reduction result, for example `Ok path_sum` or
`Error MalformedPathSum`, then propagate it up to the public Equiv result.

The `HH` rule will be the first case handled. During the migration, the old
untyped `Rules.HH.hh` entry point may remain temporarily for compatibility.
Once the typed version is validated and used by the main pipeline, this old
entry point must be removed before merging.
