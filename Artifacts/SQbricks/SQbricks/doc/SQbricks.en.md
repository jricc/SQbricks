# SQbricks: technical documentation

[Français](SQbricks.md) | [English](SQbricks.en.md)

## Purpose

This document complements the `README.md`. The README provides a quick entry
point into the project; this document progressively explains the technical
choices we validate during the work.

The current topic is the light non-regression benchmark. Its goal is
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

The light benchmark is a short guardrail before running longer campaigns.

## Light benchmark commands

The entry points are in the `Makefile`:

| Command | Purpose |
| --- | --- |
| `make regression-light` | Run the light benchmark and write a result CSV. |
| `make regression-light-baseline` | Produce the local baseline for the machine. |
| `make regression-light-check` | Compare a new run with that baseline. |
| `make tests_regression_light` | Validate runner behavior with a fake SQbricks. |

The baseline is local to the machine. It must not be versioned.

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
rows. It then computes the median and compares it with the baseline.

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
rounds=3 status=EQ times=[1.000000,1.100000,0.900000] median=1.000000
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
