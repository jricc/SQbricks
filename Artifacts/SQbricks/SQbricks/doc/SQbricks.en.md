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
selected large regression checks a more expensive but still controlled sample.
The long SQbricks-only benchmark reuses the historical families from
`scripts/benchmarks.sh`, but keeps only SQbricks verification rows in the
generated CSV files.

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
| `make regression-large-baseline` | Produce the selected baselines, one file per family. |
| `make regression-large-check` | Rerun the selection and compare results with those baselines. |

Current status:

- path selections exist for every long benchmark family;
- for size-ordered families, the selection keeps up to the three largest
  representatives so the check does not depend on a single case that may reach
  `TO` or `OutOfMemory` depending on the run;
- the runner writes result CSV files;
- baselines are stored per family in `benchmarks/baseline/regression-large/`;
- the check is separate from the light benchmark. It fails when a baseline row
  disappears, when functional capability is lost, or when a measured time
  exceeds both configured relative and absolute thresholds;
- a functional improvement is reported but does not fail the check.

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

The current migration concerns reduction errors. A rule may simply not apply to
a valid path sum, but it may also receive a malformed path sum. These two
situations should not have the same return value. The code therefore introduces
a typed reduction result, for example `Ok path_sum` or
`Error (MalformedPathSum message)`, then propagates it up to the public Equiv
result as `ErrorMalformedPathSum`.

The `HH` rule is the first case handled. `Variable_replacement` follows the
same model for its main replacement step with
`Rules.Variable_replacement.variable_replacement` and for normalization
with `Rules.Variable_replacement.poly_normalized`. After validation, these entry
points keep short names but return typed results directly. The reduction
pipeline and tests therefore propagate `MalformedPathSum` explicitly instead of
going through an untyped wrapper. `Reduction_algorithm.reduction_algorithm`
follows the same principle.

In `Equiv`, initial state construction now goes through
`Path_sum.ofSize_init_result`. An invalid width or initialization index is
converted to `ErrorInvalidQubitIndex`, avoiding an escaping `invalid_arg` during
verification.

Observable-qubit comparison in `compare_inputs_with_identity` now goes through
`Qubit.equal_result`. A comparison error means malformed path-sum metadata and
is returned as `ErrorMalformedPathSum`; `Ok true` and `Ok false` keep the
previous equivalence behavior.

Parameter preparation now explicitly checks `Program.unitary`. A hybrid or
non-unitary program, for example a circuit containing `InitQ`, returns
`ErrorCircuitNotUnitary` before symbolic execution.

### Well-formed circuits for Equiv

Before symbolic execution, `Equiv` distinguishes three families of problems:
invalid equivalence parameters, non-unitary circuits, and malformed unitary
programs.

Input, output, and measurement lists must refer to existing qubits.
Incompatible input/output lengths return `NotEquivDiffInputs`,
`NotEquivDiffOutputs`, or `NotEquivDiffInputsOutputs`. An out-of-bounds index
returns `ErrorInvalidQubitIndex`.

A circuit passed to the equivalence checker must be unitary according to
`Program.unitary`. Hybrid or classical constructors such as `Measure`, `InitQ`,
`It`, and `Not` return `ErrorCircuitNotUnitary` before symbolic execution.

Unitary gate applications must then be well formed:

- control and target indices must be inside the circuit width;
- a target gate such as `H`, `X`, or `U1` must have at least one target;
- for these gates, a control must not also be a target;
- the exponent of `GP` and `U1` must be non-negative.

A violation of these constraints returns `ErrorInvalidProgram`. A global phase
`GP` is a special case: it may carry targets, possibly with controls. These
targets are validated as indices, but they do not affect symbolic execution. If
`GP` carries both controls and targets, these lists must remain disjoint as for
other gates.

Malformed programs remain printable for diagnostics:
`Program.String.pretty` uses a generic form for `GP` and `U1` when the exponent
is negative, instead of raising during display.

Symbolic comparison now follows the same principle. The functions
`Qubit.equal_result`, `Poly.Monome.equal_result`, `Poly.equal_result`,
`Path_sum.Ket.equal_result`, and `Path_sum.equal_result` distinguish a real
equality answer (`Ok true` or `Ok false`) from a malformed comparison. The
currently typed cases are incompatible widths, incomplete path-variable maps,
output lists with different lengths, and invalid output indices. The old
`equal` functions remain compatibility wrappers that return `false` on typed
errors. Unit tests cover each observable return possibility for these typed
results.
`Path_sum.equal_result` also propagates typed phase-comparison errors instead of
converting them to plain inequality.
In the sequential algorithm, the decision that separates zero phase, global
phase, and conditional phase also uses `Poly.equal_result`, so a malformed
comparison is reported as `ErrorMalformedPathSum`.
Separability checks also validate the ket width and output indices before
extracting variables; inconsistent data is reported as `ErrorInvalidQubitIndex`.
Internal permutation preparation uses `Program.Macros.apply_swap_result` from
`Equiv`, so inconsistent list lengths or placement options do not escape as
`failwith`.
Internal inversion also uses `Program.inverse_result`: a non-reversible
subprogram is reported explicitly, then converted by `Equiv` to
`ErrorCircuitNotUnitary`.

Initial path-sum construction follows the same model with
`Path_sum.ofSize_init_result`. The function builds the initial state of width
`width`, sets the qubits listed in `inits_0` to `Zero`, then renumbers the other
qubits as input variables `Var 0`, `Var 1`, etc. It returns
`Error InvalidWidth` when the width is negative and `Error InvalidInitIndex`
when an index from `inits_0` is outside `[0, width)`. The validated tests cover
the cases with no initialization, with one or several initialized qubits, zero
width, and both typed errors.

Path-sum substitution is typed with `Path_sum.substitute_result`. It substitutes
only free variables in the phase and ket. A variable declared in `path_var` is a
bound summation variable: it cannot be substituted like a free variable. If the
target is a path variable, the function returns
`Error CannotSubstitutePathVariable`; with `except_path_var=true`, it protects
that variable and returns the path sum unchanged. The old
`Path_sum.substitute` remains a compatibility wrapper.

Path-variable ordering is typed with `Path_sum.Ket.path_var_order_result`. It
reconstructs the temporary and final order of path variables present in a ket.
It returns `Error InvalidPathVariableCount` when the declared path-variable
count is negative and `Error InvalidPathVariableIndex` when the ket contains a
path variable outside the declared interval. This behavior is stricter than the
old one: a ket that contains path variables while the declared count is zero is
now reported as malformed.

Several local operations on qubits, monomials, and polynomials now also have a
typed return:

- `Qubit.remove_result` distinguishes an effective removal, an absent variable,
  and the non-isolatable `CannotRemoveFromSum` case;
- `Poly.Monome.remove_result` propagates this case as
  `CannotRemoveQubitSum`;
- `Poly.Monome.of_qubit_to_result` explicitly rejects `SumMod2` with
  `CannotConvertSumMod2`;
- `Poly.Monome.to_qubit_result` reports scalars that do not directly represent
  a qubit with `CannotConvertScalarToQubit`;
- `Poly.to_qubit_result` and `Poly.of_qubit_result` type conversions between
  polynomials and qubits, including unformatted modulo-2 sums;
- `Poly.of_qubit_2_pi_result` uses the same formatting contract as
  `Poly.of_qubit_result`, but applies the shortcut for the `2*pi` case.

The old wrappers remain in place during the migration. They preserve historical
behavior, often still raising `Failure` or returning `None`, but the new tests
target the `*_result` versions.

Polynomial algebra now exposes `Poly.distribution_result`. This function
distributes a monomial over a polynomial and returns
`Error UnformattedDistributionMonome` when a monomial from the right polynomial
has a scalar on the right (`Prod (_, Scal _)`). This case previously raised in
`Poly.distribution`. The untyped wrapper remains available for compatibility.

The gate constructors in `Path_sum.Path_sum_library` now have public typed
versions. Their common contract is simple: a target, control, or secondary
control outside the declared width returns `Error TargetIndexOutOfWidth`. The
old constructors remain compatibility wrappers that preserve the historical
failure message.

The validated typed constructors are:

- single-target gates: `h_result`, `x_result`, `u1_result`, `z_result`,
  `s_result`, `t_result`, `zinv_result`, `sinv_result`, `tinv_result`,
  `rz_result`, `rx_result`, `ry_result`;
- controlled gates: `ch_result`, `cx_result`, `crz_result`, `cz_result`,
  `cs_result`, `ct_result`;
- double-controlled gates: `ccx_result`, `ccz_result`.

The internal helpers that depended on index validation were also typed,
including `normalisation_factor`, `q2`, and `ccrz`. They
are not exposed in the public interface, but they let the public typed
constructors propagate the error instead of triggering an uncontrolled failure.

## Inspection prototype

The phase 9 inspection prototype is provided by
`scripts/inspect-sqbricks.sh`. It does not change the OCaml core: it orchestrates
existing SQbricks commands to make a comparison easier to inspect.

The script takes two QASM files and has two modes:

- `--mode auto` calls the automatic SQbricks workflow with `-sq`;
- `--mode manual` calls `-sqv` with explicit metadata (`inputs`, `outputs`,
  `meas`, algorithm, and equivalence relation).

SQV is run with `verbose=true` because this script is meant for inspection, not
compact measurement output. The full trace is kept in `sqv.stdout`. The script
also extracts final path-sums from this trace. This extraction therefore still
depends on the current debug text format; it is not a stable OCaml interface.

By default, results are written to `_tmp/inspection/<timestamp>/`. Important
files are:

- `report.txt`: human-readable execution summary;
- `commands.sh`: replayable commands;
- `sqv.stdout` and `sqv.stderr`: full SQV trace;
- `pathsum-left.stdout` and `pathsum-right.stdout`: path-sums for the two
  inputs;
- `final-path-sums.txt`: final path-sums extracted from SQV;
- `pathsum-left.tex`, `pathsum-right.tex`, `final-path-sums.tex`, and
  `path-sums.tex`: prototype LaTeX export;
- `path-sums.pdf`: compiled PDF when `pdflatex` is available.

The LaTeX export separates each path-sum into three parts:

- `p`, shown as a two-column table of numbered monomials;
- `f`, shown as a table of output components numbered by qubit;
- `Y`, shown separately for path variables.

Very large path-sums can be skipped from LaTeX export to avoid overloading
LaTeX. The threshold is controlled by `SQBRICKS_INSPECT_LATEX_MAX_CHARS` and
defaults to `30000` characters.

The planned next step for this phase is a graphical interface to load two QASM
files, edit metadata, choose auto/manual mode, run SQV, and browse generated
artifacts.
