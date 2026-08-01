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

## Provenance and references

SQbricks was initially developed in the
[Qbricks repository](https://github.com/Qbricks/qbricks.github.io), under
`Artifacts/SQbricks/SQbricks`. This repository places SQbricks at its root
while preserving the history of the subproject, its copyright notices, and its
LGPL 2.1 license.

The main scientific references are:

- Jérome Ricciardi, Sébastien Bardin, Christophe Chareton, and Benoît Valiron,
  [*Quantum Circuit Equivalence Checking: A Tractable Bridge From Unitary to
  Hybrid Circuits*](https://arxiv.org/abs/2511.22523), arXiv:2511.22523, 2025;
- Jérome Ricciardi,
  [*Practical verification of quantum circuit
  transformations*](https://theses.hal.science/tel-05681895v1/document),
  doctoral thesis, 2026.

The inspection prototype uses Quantikz2 for LaTeX circuit diagrams. Its
reference is Alastair Kay,
[*Tutorial on the Quantikz Package*](https://arxiv.org/abs/1809.03842),
arXiv:1809.03842. [`CITATION.cff`](../CITATION.cff) provides SQbricks citation
metadata.

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
- `SQBRICKS_LONG_MEMORY_KB`, defaulting to `6291456`.

If one mode in an ordered series reaches `TO` or `OutOfMemory`, that mode is no
longer executed for larger cases in the same series. The runner writes
`SKIP_AFTER_RESOURCE_FAILURE` for that mode but continues to execute the other
one. A conversion resource failure stops both modes. A series is identified by
the benchmark type, source directory, and name family. For example, a failure
on `benchmarks/Feynman/grover_5.qasm` does not skip
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
- for size-ordered families with a known resource frontier, the selection keeps
  two stable cases, the first `TO` or `OutOfMemory` case, and the immediately
  larger case as a fallback;
- the runner writes result CSV files;
- baselines are stored per family in `benchmarks/baseline/regression-large/`;
- the check is separate from the light benchmark. It fails when a baseline row
  disappears, when functional capability is lost, or when a measured time
  exceeds both configured relative and absolute thresholds;
- a functional improvement is reported but does not fail the check.

The fourth case in a series is normally skipped by the cutoff. It is executed
when the frontier case completes during a later run. This margin preserves
functional coverage when the frontier fluctuates, but it does not reduce timing
noise.

The Feynman file `benchmarks/Feynman/grover_5.qasm` keeps its original name and
provenance on disk. The runner nevertheless uses `grover_5_feynman` as its CSV
program name so it does not create the same key as VeriQbench's circuit also
named `grover_5`.
## OpenQASM parser

The OpenQASM parser translates circuits to `Program.t`, which uses flat integer
indices for qubits and classical bits. OpenQASM, on the other hand, allows
several named registers, for example:

```qasm
qreg q[1];
qreg r[1];
qreg s[2];
```

The parser flattens these registers by assigning each one a global offset:

| Register | Offset | Size | SQbricks indices |
| --- | --- | --- | --- |
| `q` | `0` | `1` | `q[0] -> 0` |
| `r` | `1` | `1` | `r[0] -> 1` |
| `s` | `2` | `2` | `s[0] -> 2`, `s[1] -> 3` |

The same rule is used for classical registers declared with `creg`. The
`qreg_offsets` and `creg_offsets` tables therefore store, for each register
name, the pair `(offset, size)`.

The helpers added in `Parser_OpenQASM.mly` each have a narrow role:

- `reset_registers` clears the register tables at the beginning of parsing, so
  one QASM file cannot reuse declarations from the previous file;
- `declare_register` records a `qreg` or `creg` declaration, reserves a
  consecutive slice of indices, then advances the next available offset;
- `register_info` returns the `(offset, size)` pair of a register;
- `register_offset` returns only its offset;
- `register_index` translates `name[index]` to `offset + index`.

For an OpenQASM condition `if (c == n)`, the parser keeps both the offset and
the size of `c`. Bit `c[0]` is the least significant bit of `n`.
`Parser_help.classical_condition_bits` then separates bits expected to be `0`
from bits expected to be `1`, and `Program.Macros.itl2` builds the exact
condition by temporarily negating the bits expected to be `0`.

For example, after `creg prefix[1]; creg c[2];`, register `c` occupies flat
indices `1` and `2`. The condition `if (c == 2)` uses the binary value `10`:
flat bit `1` must be `0` and flat bit `2` must be `1`. It therefore becomes
`itl2 [1] [2] program`. A cell such as `c[1]` remains accepted for compatibility
and is treated as a one-bit register.

A value that does not fit in the declared size is rejected explicitly. An
integer literal too large for SQbricks' integer representation is also rejected
with a message containing that literal. If a multi-bit conditional body expands
to several instructions, its later deferred-measurement translation may still
return `UnsupportedConditionalProgram`; the parser nevertheless preserves the
exact condition instead of silently producing a different circuit.

For compatibility with existing QASM libraries, SQbricks also accepts some
malformed registers instead of stopping immediately. For example,
`qreg q[0]; h q[0];` and `qreg q[1]; h q[1];` are reported with a warning on
`stderr`, then translated with the flat `offset + index` index. This behavior is
an input tolerance: the circuit is still malformed, but SQbricks tries to process
it so external benchmark sets do not have to be altered.

`include "...";` statements are accepted for compatibility with common
OpenQASM files, but SQbricks does not load the included file at this stage. The
supported gates are the ones hard-coded in the lexer and parser. If an unknown
gate really depends on an included file, it remains unsupported.

The `OPENQASM 3.0;` header is tolerated for some benchmark files that in
practice use the legacy subset described above. This does not mean that the
parser supports OpenQASM 3 in general.

`barrier ...;` statements are treated as OpenQASM no-ops: the lexer skips only
up to the next `;`, then resumes parsing. This is different from a `//`
comment, which skips everything up to the end of the line.

Angle conversion for `pi/den` uses `Parser_help.den_to_k`. This function checks
that `den` is a power of two and returns the exponent expected by SQbricks'
`2*pi/2^k` representation. Zarith integers are compared with `Z.equal`, meaning
by mathematical value, not by memory identity.

The file entry points `Parser_get.GetProg.to_prog` and
`Parser_get.GetPs.to_ps` delegate reading to `parse_file`. This function opens
the channel, creates the lexing buffer, then runs the parser inside
`Fun.protect`. Its `finally` block calls `close_in_noerr` after both success and
an exception. The `noerr` suffix matters: a secondary closing error must not
hide the original parser error.

During OpenQASM export, `one_creg=true` changes only the classical-bit layout:
the result still contains the `qreg`, one `creg c[wc]`, and all circuit
instructions. An application with several targets is split into single-target
applications, which are then validated individually. An unsupported gate and
control combination is rejected explicitly instead of recursively restarting
the same conversion. Symbolic execution accepts multi-controlled `H` gates,
but their OpenQASM decomposition remains roadmap work.

### Decomposition of the three-controlled X gate

`Program.Macros.c3xdecomp` decomposes an `X` gate with three controls into
gates already supported by OWM and by the OpenQASM exporter:

```ocaml
let c3xdecomp co1 co2 co3 ta =
  let controlled_controlled_v s control1 control2 target =
    h target -- ccu1 ~s 2 control1 control2 target -- h target
  in
  controlled_controlled_v 1 co2 co3 ta
  -- ccx co1 co2 co3
  -- controlled_controlled_v (-1) co2 co3 ta
  -- ccx co1 co2 co3
  -- controlled_controlled_v 1 co1 co2 ta
```

Assume that the four qubits are distinct. Let

$$
a=\texttt{co1},\qquad
b=\texttt{co2},\qquad
c=\texttt{co3},\qquad
t=\texttt{ta}.
$$

The `--` operator denotes sequential execution from left to right.

#### Constructing the square root of X

In SQbricks, `ccu1 2` conditionally applies the gate

$$
S=
\begin{pmatrix}
1&0\\
0&i
\end{pmatrix}.
$$

Therefore,

```ocaml
h target -- ccu1 2 control1 control2 target -- h target
```

applies the gate

$$
V=HSH
$$

to `target` when both controls are $1$, and the identity $HH=I$
otherwise. Similarly, `~s:(-1)` applies

$$
V^\dagger=HS^\dagger H.
$$

Since $H^2=I$, $S^2=Z$, and $HZH=X$, it follows exactly that

$$
V^2=(HSH)(HSH)=HS^2H=HZH=X.
$$

This equality introduces no additional global phase.

#### Action of the decomposition

The generated sequence can be written as

$$
CCV_{b,c\rightarrow t}\;;
CCX_{a,b\rightarrow c}\;;
CCV^\dagger_{b,c\rightarrow t}\;;
CCX_{a,b\rightarrow c}\;;
CCV_{a,b\rightarrow t}.
$$

Consider a computational-basis state for the controls and an arbitrary target
state:

$$
|a,b,c\rangle|\psi\rangle_t,
\qquad a,b,c\in\{0,1\}.
$$

The first $CCV$ applies $V^{bc}$ to the target. The first $CCX$
temporarily changes the third control to

$$
c'=c\oplus ab.
$$

The following $CCV^\dagger$ then applies $V^{-bc'}$. The second $CCX$
restores the third control because

$$
(c\oplus ab)\oplus ab=c.
$$

Finally, the last $CCV$ applies $V^{ab}$. Since all target operations are
powers of $V$, their composition is

$$
V^E,
\qquad E=bc-b(c\oplus ab)+ab.
$$

For bits, the identity

$$
x\oplus y=x+y-2xy
$$

gives

$$
\begin{aligned}
b(c\oplus ab)
  &=b(c+ab-2abc)\\
  &=bc+ab-2abc.
\end{aligned}
$$

Therefore,

$$
E=bc-(bc+ab-2abc)+ab=2abc.
$$

The total action on the target is thus

$$
V^{2abc}=(V^2)^{abc}=X^{abc}.
$$

Consequently,

$$
|a,b,c\rangle|\psi\rangle_t
\longmapsto
|a,b,c\rangle X^{abc}|\psi\rangle_t.
$$

The target receives $X$ if and only if all three controls are $1$. The
controls are restored at the end of the sequence. Equality on computational
basis states implies equality on every state by linearity: the decomposition
implements an exact $C^3X$ gate without an ancillary qubit or a global phase.

This construction is the $n=4$, $U=X$ instance of Lemma 7.5 in
[Barenco et al., *Elementary gates for quantum computation*](https://arxiv.org/pdf/quant-ph/9503016#page=21),
which sets $V^2=U$. Lemma 6.1 gives the underlying elementary argument for
two controls. The unit tests directly compare `c3xdecomp` with the
multi-controlled semantics of `Program.Apply`, using contiguous, sparse,
non-ordered indices at both ends of the register. An additional OWM test checks
the transformation without going through OpenQASM.

## Deferred measurement translation

`To_deferred_measurement.to_deferred_measurements_result` translates a hybrid
program into a program without intermediate measurements. It returns:

- the translated program;
- the list of initialized qubits;
- the list of measured qubits;
- or a typed error when the translation is unsupported.

`to_deferred_measurements` remains the historical wrapper: it calls the typed
version and raises `Failure` on errors, to preserve compatibility with older
callers.

The translation keeps three important pieces of state:

- `bit_to_qubit` records which qubit currently carries the classical value of a
  bit. This table may be overwritten when the same classical bit is reused;
- `meas` records every qubit that has been measured. This list must not be
  inferred from `bit_to_qubit`, because reusing a classical bit would erase the
  information about a previous measurement;
- `used_qubits` records qubits already used by a gate, a measurement, or a
  translated correction.

Reusing a classical bit is therefore accepted. For example, if `c0` receives the
measurement of `q0` and later the measurement of `q1`, later controls on `c0`
depend on the latest measurement stored in that bit. Both measured qubits still
remain in `meas`.

Classical corrections are translated into quantum controls. For example:

```text
measure q0 -> c0;
if c0 then x q2;
measure q1 -> c0;
if c0 then x q2;
```

conceptually becomes:

```text
cx q0 q2;
cx q1 q2;
```

The second `measure` overwrites the classical bit `c0`, but it does not undo the
effect already applied to `q2`.

`InitQ` is treated as the initialization of a fresh qubit. This form is needed
by MBQC/OWM translations, which introduce ancillas while constructing the
program. For example:

```text
iq0 1; h 1; iq0 2; h 2
```

is accepted, because `q2` has not been used yet when it is initialized. In
contrast, dynamic reset of an already used qubit is not supported yet:

```text
x 0; iq0 0
```

returns `ResetOfUsedQubitUnsupported 0`.

The currently exposed typed errors are:

- `InvalidClassicalBit`, for a classical bit outside the computed width;
- `InvalidQubitIndex`, for a qubit outside the computed width;
- `ClassicalControlWithoutMeasurement`, when a classical control has no stored
  measurement result;
- `MeasuredQubitUsedAfterMeasurement`, when a gate reuses a qubit that has
  already been measured;
- `ResetOfUsedQubitUnsupported`, when `InitQ` targets a qubit that was already
  used;
- `UnsupportedConditionalProgram`, for a conditional shape that is not
  translated.

True dynamic OpenQASM `reset` and the general `discard` / qubit-reuse model
remain roadmap items. The validated behavior here is conservative: SQbricks
accepts fresh ancillas, but does not yet claim to correctly reset an already
active qubit.

## Equiv audit

The targeted audit of the reduction-to-equivalence pipeline started with
parameter preparation in `lib/equiv.ml`.

### Evolution of `Entanglement1` results

`Entanglement1` is an inconclusive result from the separability check. After
reducing the first circuit, it means that variables from the observed outputs
are not separable from variables belonging to discarded qubits. SQbricks
therefore does not project those qubits and stops the proof; this result does
not mean that the circuits are non-equivalent.

The long results from June 22 to June 25, 2026 predate commit `e6700a6`, which
extends variable replacement in kets. Replaying the cases on the intermediate
commits and then removing each change separately isolated the cause of the
observed improvements: substitution now descends into `Qubit.Prod`
expressions, whereas it previously traversed only `Qubit.SumMod2` expressions.

Without this recursive branch, a variable to replace that occurs inside a
product remains in the reduced ket. The separability check may then still
observe that variable in both the outputs and discarded qubits and return
`Entanglement1`. Substitution under `Qubit.Prod` allows reduction to eliminate
this residual dependency.

This correction gives timed equivalence results for both Sequence and Parallel
on `owm/grover_3`, a timed Sequence equivalence for `owm/grover_5`, and
`SubCircuitInconclusive` for its Parallel check. It also gives a timed
equivalence for `owm-vs-tele/grover_3` and changes the Sequence and Parallel
checks of `owm-vs-qiskit/shor_n5_ancillas` to a timed equivalence and
`SubCircuitInconclusive`, respectively.

Removing only this branch from `e6700a6` restores `Entanglement1` in every one
of these modes. Conversely, adding only this branch to `3d002fc` reproduces all
the improvements. It is therefore necessary and sufficient for these cases.
The changes that avoid mutating shared kets remain safety fixes. Neither these
changes nor the additional call to `Qubit.simplify` are required for these
specific results.

The later bijective path-variable renaming completes this result. On July 20,
2026, the light benchmark returns `EQ` in all three rounds of
`owm/grover_5 Parallel`, where the manifest still expected `NC`. The functional
manifest now expects `EQ` for this case; it remains excluded from performance
tracking because its row has `TrackPerformance = no`.

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

The `HH` rule atomically removes the two path variables matched by its pattern.
The factor produced by destructive interference then exactly compensates for
the two removed normalization factors. An unused path variable cannot be
removed on its own, so `Elim` is no longer applied as an independent reduction
after `HH` or after variable-replacement factorization.

Every path variable remains a possible candidate for the role of `y0`.
However, `hh_aux` can succeed only if the phase contains the term
`1/2*y0*yi`, where `yi` is another path variable. The internal
`path_variables_with_possible_yi` function extracts variables with this
necessary witness in one traversal, then `HH.hh` tries only those variables in
`path_var` order. After a successful reduction, the phase has changed, so the
list is recomputed. This prefilter therefore changes neither the mathematical
pattern, the reduction order, nor error handling for zero-width path sums.

On `owm/gf2^9mult_89_413`, the initial profile counted 3,596 `hh_aux` calls for
4 `HH.hh` calls in Sequence, versus 1,798 for 3 in Parallel. An A/B/A
measurement on the same machine gives a Sequence/Parallel ratio of `2.045` on
`main`, versus `1.720` and `1.715` with the prefilter. This ratio shows an
approximately 16% reduction in Sequence-specific cost despite variation in the
machine's overall speed. The unit test also keeps an absent path variable placed
before a valid HH pair while still reducing that pair.

`Rules.Variable_replacement.variable_replacement` accepts a ket component only
when it has the form `y xor Q`, where `y` is a declared path variable that does
not occur in `Q`, the phase, or another ket component. `Q` may contain a product
independent of `y`, for example `y0 xor x0*x1`. In contrast,
`x0 xor y0*y1` has no direct candidate, and `y0 xor y0*y1` is rejected because
`Q` depends on `y0`.

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
- the effective angle of `GP` and `U1` must be dyadic.

A violation of these constraints returns `ErrorInvalidProgram`. A global phase
`GP` is a special case: it may carry targets, possibly with controls. These
targets are validated as indices, but they do not affect symbolic execution. If
`GP` carries both controls and targets, these lists must remain disjoint as for
other gates.

`Program.execution_result` computes the effective angle `s / 2^k`, then
normalizes dyadic angles modulo one into the interval `[0, 1)`. Negative
coefficients and negative exponents therefore remain valid: `-1/4` becomes
`3/4`, `5/4` becomes `1/4`, and an integer angle becomes `0`, the identity. A
non-dyadic angle returns `NonDyadicRotationAngle`, which `Equiv` converts to
`ErrorInvalidProgram`.

The stored `Program.t` is not rewritten: normalization happens only during
symbolic execution. `Program.String.pretty` therefore keeps a generic form for
`GP` and `U1` when the exponent is negative, without raising during display.
The historical `Program.Macros` helpers still reject `k < 0` before constructing
the `Program.t`.

In `Poly.Monome.simplify`, rational factors are multiplied exactly before a
negative phase coefficient is normalized modulo one. For example,
`(-5/4)*(1/2)` is first computed as `-5/8`, then normalized to `3/8` with the
Euclidean remainder. Normalizing `-5/4` before the multiplication could change
the phase because congruence modulo one is not preserved by arbitrary rational
multiplication. The same rule applies when recursive simplification removes an
identity and exposes another scalar factor. For example,
`(-9/4)*(1*(1/2))` first becomes `-9/8`, then `7/8` modulo one; the `-9/4`
factor must not be normalized before the identity is removed.

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

`Path_sum.Ket.equal_result` structurally compares corresponding output
expressions. For a ket of width `wq`, indices below `wq` are input variables and
retain their index; indices greater than or equal to `wq` are path variables
and may be renamed. The first occurrence of a pair builds a direct map from the
first ket to the second and its inverse map. Later occurrences must respect
both maps: one source cannot have two images, and two sources cannot share one
image.

For example, for two kets of width 2, comparing
`|x0 xor v2, x1 xor v3>` with `|x0 xor v4, x1 xor v2>` builds
`{2 -> 4; 3 -> 2}` and `{2 -> 3; 4 -> 2}`. `Path_sum.equal_result` then reuses
the same bijection to compare phases. A phase-variable pair absent from both
maps was not constrained by the ket and remains compared by relative path
index. A pair present in only one map is instead reported as
`IncompletePhasePathVariableMap`.

Without explicit output lists, `Path_sum.equal_result` compares the complete
kets and returns `Ok false` when their widths differ. With two explicit output
lists of equal length and valid indices, the complete ket widths may differ:
only the selected components are compared.
In the sequential algorithm, the decision that separates zero phase, global
phase, and conditional phase also uses `Poly.equal_result`, so a malformed
comparison is reported as `ErrorMalformedPathSum`.
Separability checks also validate the ket width and output indices before
extracting variables; inconsistent data is reported as `ErrorInvalidQubitIndex`.
Internal permutation preparation uses `Program.Macros.apply_swap_result` from
`Equiv`, so inconsistent list lengths or placement options do not escape as
`failwith`.
The first list gives source positions and the second gives destinations: the
logical value on `sources[i]` must finish on `destinations[i]`. When both lists
overlap, the current positions of sources that still need to move are updated
after every swap. Therefore `[0;1] -> [1;2]` emits `swap 0 1` followed by
`swap 0 2`, transforming `|x0,x1,x2>` into `|x2,x0,x1>`.

In `Equiv.seq`, the first circuit outputs move from `outputs1` to `outputs2`.
After executing the inverse of the second circuit, values are instead located
on `inputs2`, so they move from `inputs2` to `inputs1`. This orientation is
irrelevant for one isolated swap, but not for a cyclic permutation composed of
several swaps.

`Equiv.check_observable_measurement` also compares circuits through the logical
correspondence defined by positions in their normalized output lists. For each
position, it compares whether the corresponding output is measured; it does
not compare physical indices directly. For example, `outputs1 = [1]`,
`outputs2 = [0]`, `meas1 = [1]`, and `meas2 = [0]` describe one logical output
measured in both circuits and are compatible. If `meas2 = []`, the function
reports a difference instead. Measurements of qubits outside the observable
outputs remain ignored. Automatic `-sq` mode is unchanged: it derives the
unmeasured outputs before the call, then does not pass measurement lists to
`Equiv`.

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

### Path-variable change

This section follows Definitions 2.3.2 to 2.3.4 of Jérôme Ricciardi's thesis,
*Practical verification of quantum circuit transformations*
([HAL tel-05681895](https://theses.hal.science/tel-05681895)). This thesis is
the theoretical foundation of SQbricks and is the reference for the notation
and proofs below.

*Status: this formalization still requires mathematical review.*

#### Definition (change of one path variable)

Consider the following path sum in algebraic form:

```text
P = <y, p(x, y), f(x, y)>
y = (y0, ..., y_(m-1))
```

Fix an index `k < m` and a Boolean polynomial `Q(x, y_except_k)` that does not
depend on `yk`. For an input `x`, define the function
`tau_(k,Q,x) : F_2^m -> F_2^m` by:

```text
tau_(k,Q,x)(y)_i = yi                              if i != k
tau_(k,Q,x)(y)_i = yk xor Q(x, y_except_k)         if i = k
```

The associated path-variable change is:

```text
P^(k,Q) = <y,
           p(x, tau_(k,Q,x)(y)),
           f(x, tau_(k,Q,x)(y))>
```

The substitution in the output signature `f` is Boolean. In the phase `p`, it
uses the Boolean-to-arithmetic polynomial transformation from Definition
2.3.2. Writing this transformation as `lift`:

```text
lift(a xor b) = lift(a) + lift(b) - 2 lift(a) lift(b)
```

This distinction is necessary: directly replacing `yk` with an arithmetic
sum would lose the correction terms introduced by XOR.

When the phase coefficient is `1/2`, these correction terms are integer phases
and vanish modulo one. For example:

```text
1/2 (a xor b)
  = 1/2 a + 1/2 b - ab
  ≡ 1/2 a + 1/2 b                    (mod 1)
```

In this case, `coef_lift (1/2) = 0`, and `Poly.lift` returns the original
polynomial directly instead of rebuilding it recursively. Empty and
single-monomial polynomials are also returned directly because no cross term
can arise. In the instrumented Sequence profile for `tele/grover_17`, this
fast path reduced time in `Poly.lift` from `11.00 s` to `0.01 s`, and total
time from `36.08 s` to `21.47 s`.

Write `P' ≡ P` when the two path sums are semantically equivalent, that is,
when:

```text
for every input x, V(P')(x) = V(P)(x)
```

#### Correctness lemma for the variable change

If `Q` does not depend on `yk`, then the variable change produces a
semantically equivalent path sum:

```text
P^(k,Q) ≡ P
```

**Proof.** Fix an input `x`. Since `Q` does not depend on `yk`, the map
`tau = tau_(k,Q,x)` is an involution. Its coordinates other than `k` are
unchanged, and:

```text
tau(tau(y))_k
  = (yk xor Q(x, y_except_k)) xor Q(x, y_except_k)
  = yk
```

Therefore, `tau` is a bijection of `F_2^m`. Using Definition 2.3.4 of
concretization and then the reindexing `z = tau(y)`, we obtain:

```text
V(P^(k,Q))(x)
  = 2^(-m/2) sum_(y in F_2^m)
      exp(2 pi i p(x, tau(y))) |f(x, tau(y))>

  = 2^(-m/2) sum_(z in F_2^m)
      exp(2 pi i p(x, z)) |f(x, z)>

  = V(P)(x)
```

The equality holds for every input, so the two path sums concretize the same
linear map. This is a semantic equality of concretizations, not necessarily a
syntactic equality of the OCaml structures or the path-variable renaming
relation. This proves the lemma.

#### Corollary for correct isolation of a path variable

If an output component satisfies:

```text
f_j(x, y) = yk xor Q(x, y_except_k)
```

then:

```text
f_j^(k,Q)(x, y) = yk
P^(k,Q) ≡ P
```

**Proof.** Coordinates other than `k` are not modified by `tau`. Independence
of `Q` from `yk` therefore gives:

```text
f_j(x, tau(y))
  = (yk xor Q) xor Q
  = yk
```

Preservation of concretization follows from the lemma, which proves the
corollary.

The lemma allows any Boolean polynomial `Q` independent of `yk`. To fix the
`owm-vs-qiskit/dqc_teleportation` case without generalizing prematurely,
`Rules.Variable_replacement.replace_not_path_var_by_var` only recognizes an
affine form built from input variables:

```text
Q(x) = c xor (xor_(i in I) xi), with c in F_2
```

This includes, for example, `1`, `x0`, `x0 xor x2`, and `1 xor x0 xor x2`;
`Q = 0` is the identity and requires no rewrite. Products such as `x0 x1` and
shifts that contain another path variable remain outside this implementation.
This restriction is an implementation decision, not a condition of the lemma.

A recognized substitution is applied to the whole phase and the whole ket,
not only to the component in which it was detected. On each call, the function
applies at most one change, and only when it increases the number of output
components exactly equal to the path variable. It therefore does not perform a
change that would merely move the same expression to another component.

Two examples define the results expected by the tests:

**Example 1: `owm-vs-qiskit/dqc_teleportation`.**

```text
P = <(y0, y1),
     1/2 x1 y0 + 1/2 x2 y1,
     (y0, x0 xor x1 xor y1, x0 xor x1)>

Change: y1 <- y1 xor x0 xor x1

P' = <(y0, y1),
      1/2 x0 x2 + 1/2 x1 x2 + 1/2 x1 y0 + 1/2 x2 y1,
      (y0, y1, x0 xor x1)>
```

The phase of `P'` is simplified modulo polynomials with integer coefficients.

**Example 2: simplification with a `1/4` phase coefficient.**

```text
P = <y0,
     1/4 x0 + 1/4 y0 + 1/2 x0 y0,
     (x0 xor y0)>

Change: y0 <- y0 xor x0

P' = <y0, 1/4 y0, (y0)>
```

In the phase of `P`, the coefficient `+1/2` is equivalent to `-1/2` modulo an
integer coefficient. This example checks that the substitution uses the `1/4`
coefficient from its context: both the phase and the ket are simplified.

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

`Qubit.extract_var` and `Qubit.extract_path_var` recursively traverse products
and sums modulo two with an accumulator. The `Zero` and `One` constants add no
variable, but preserve variables already collected from another branch of the
expression.

`ListBis.remove` removes every requested occurrence with the supplied equality
function while preserving the relative order of all other elements. When the
value is absent, the list therefore also keeps its original order.

`ListBis.check_bounds lower upper list` returns `true` when every value
satisfies `lower <= value < upper`. The lower bound is included, the upper bound
is excluded, and the empty list is valid. `extract_upper_bound_list` and
`extract_lower_bound_list` respectively filter values greater than or equal to
the bound and values strictly below it, without changing their relative order.

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

For a declared width `w`, each constructor now returns a ket with exactly `w`
components, ordered by physical wire index. Wires that are not involved in the
gate keep their input variable. For example, `x_result 1 3` represents the ket
`|x0, 1 xor x1, x2>`. When a gate creates path variables, their indices start at
`w`, after the circuit input variables.

Wires selected by a controlled gate must also be distinct. A two-wire gate
whose control is also its target, or a three-wire gate whose roles reuse an
index, returns `Error OverlappingGateWires`. All indices are validated before
this overlap check, so `Error TargetIndexOutOfWidth` takes precedence when a
wire is outside the declared width. Untyped wrappers turn an overlap into an
explicit failure message.

The validated typed constructors are:

- single-target gates: `h_result`, `x_result`, `u1_result`, `z_result`,
  `s_result`, `t_result`, `zinv_result`, `sinv_result`, `tinv_result`,
  `rz_result`, `rx_result`, `ry_result`;
- controlled gates: `ch_result`, `cx_result`, `crz_result`, `cz_result`,
  `cs_result`, `ct_result`;
- double-controlled gates: `ccx_result`, `ccz_result`.

For `u1_result`, `rz_result`, `rx_result`, and `ry_result`, the coefficient `s`
is an integer. An exponent `k < 0` therefore gives the exact identity: the phase
is zero, the target remains unchanged, and no path variable is introduced.
`u1_result` is also the identity for `k = 0`. This case is distinct from a
coefficient `s < 0`, which remains a valid negative angle. The tests cover all
four constructors and specifically check that `rx_result` and `ry_result`
return `path_var = []`.

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
- `circuit-left.tex`, `circuit-right.tex`, `circuits.tex`, and
  `circuits.pdf`: prototype Quantikz2 circuit export when circuits are small
  enough;
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

Circuit export is intentionally limited. It reads simple OpenQASM 2 circuits,
produces Quantikz2 LaTeX, and skips the drawing when the number of qubits or
gates exceeds `SQBRICKS_INSPECT_CIRCUIT_MAX_QUBITS` or
`SQBRICKS_INSPECT_CIRCUIT_MAX_GATES`. This keeps inspection PDFs readable and
avoids overloading LaTeX.
Wide circuits are split into several Quantikz2 blocks in a landscape document.
The maximum number of columns per block is controlled by
`SQBRICKS_INSPECT_CIRCUIT_WRAP_GATES`, with a default value of `12`.
Classical bits written by simple `measure q[i] -> c[j]` operations are drawn
as classical wires and connected to their measurement.
Custom gate definitions are not expanded; the script ignores their bodies and
simplifies calls it cannot draw precisely.
The Docker image installs the current Quantikz2 TikZ library from CTAN in a
final layer.

The planned next step for this phase is a graphical interface to load two QASM
files, edit metadata, choose auto/manual mode, run SQV, and browse generated
artifacts.
