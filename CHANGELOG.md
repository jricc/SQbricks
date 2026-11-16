# Changelog

This file records the user-visible changes in SQbricks releases.

## [0.2.1] - 2026-11-15

### Fixed

- Follow indirect phase dependencies when checking separation of observed and
  discarded outputs. Separation and partial comparison now share the same
  phase partition, and comparison preserves the full phases when independence
  is not established. Global-phase comparison ignores only constant terms.
- Run the development container as the host user so the bind-mounted worktree
  is writable (`container.sh`). With a rootless Docker daemon the container
  user is root, which is the host user there; with a rootful daemon it is the
  host UID/GID. This fixes `make tests` failing with `Permission denied` on
  `/sqbricks/_build` when the host UID differs from the image user `opam`.

### Validation and known limitations

- The recorded post-integration validation includes 1,595 passing tests and a
  passing light check with 50 functional rows and 14 tracked performance rows.
- The large comparison completed all ten families; eight passed. A targeted
  A-B-B-A control did not reproduce the two large teleportation slowdowns and
  reproduced both OWM Sequence resource failures with and without the fix.
  These controls do not establish a global performance gain or a fully passing
  large campaign.
- The large runner labels exit code 137 as out-of-memory without establishing
  the cause of SIGKILL. Targeted measurements strongly suggest that the two
  OWM Sequence failures reach the CPU limit; their exact kill cause remains
  unconfirmed. Existing CSV statuses are preserved.
- Direct path-sum comparison does not itself certify separation. The internal
  phase-partition helper assumes that observed and discarded registers cover
  all output wires; the equivalence pipeline supplies complementary lists.

## [0.2.0] - 2026-10-10

### Added

- Integrate Amy's Omega and Case rules into path-sum reduction. Case runs
  after HH; Omega runs after the other reductions stabilize. A successful
  application restarts the reduction pipeline.
- Add direct and circuit-level tests for the new rules, including exact phase
  preservation, independent contexts, and unsupported matching forms.
- Add a Case capability example to the light regression benchmark.

### Fixed

- Correct the controlled-Hadamard decomposition used by circuit transformations.
- Reject malformed path-variable metadata before Case matching and handle
  unsuccessful factorization conservatively.
- Extend Case integration coverage to reversed and spaced wire indices.

### Performance

- Reduce redundant work in Case matching and in qubit-to-polynomial conversion.
  Performance remains workload- and machine-dependent; no global speedup is
  claimed.

### Validation and known limitations

- The recorded validation of the combined HH, Case, and Omega pipeline includes
  1,595 passing tests and a passing light check with 50 functional rows and
  14 tracked performance rows.
- The selected large campaign completed all ten families. Nine passed; `tele`
  reported two Sequence out-of-memory results under the 6 GiB limit:
  `grover_5_feynman` and `gf2^64mult_4285_20669`. Both were reproduced without
  Case and remain resource limitations of the reference environment.
- Rule matchers remain conservative; an inconclusive result does not establish
  non-equivalence. SQbricks remains a research prototype.

## [0.1.1] - 2026-08-30

SQbricks 0.1.1 keeps the public interfaces and reduction semantics of 0.1.0
while reducing repeated work in path-sum reduction.

### Performance

- Analyze HH candidates in one traversal of the phase and partition a matched
  phase once before substitution.
- Reuse an existing path-variable name for eligible variable replacements,
  avoiding an unnecessary whole-path-sum renaming step.

### Reliability

- Add focused tests for HH candidate order, repeated candidate pairs,
  unauthorized coefficients, and preservation of phase terms independent of
  the substituted variable.
- Extend light regression coverage with teleportation adder and Grover cases.
- Update selected large regression baselines after validated functional
  improvements.

### Known limitations

- Performance remains dependent on the workload and reference machine. This
  release does not claim a global speedup.

## [0.1.0] - 2026-08-08

SQbricks 0.1.0 is the first release of the focused SQbricks repository. It is
a research prototype for checking equivalence between unitary and hybrid
quantum circuits.

### Added

- Deferred-measurement transformations producing IUM circuits or their
  unitary part.
- Sequence and Parallel path-sum equivalence-checking algorithms.
- Support for partial equivalence with inputs, outputs, measurements, and
  discarded qubits.
- OpenQASM 2 parsing and export for the supported SQbricks circuit subset.
- Light, selected large, and long SQbricks-only benchmark workflows with
  explicit statuses, progress reporting, timeouts, and memory limits.
- A prototype inspection workflow with text, LaTeX, PDF, Quantikz2, and
  path-sum artifacts.

### Reliability

- Added typed errors and validation across equivalence preparation, symbolic
  execution, path-sum reduction, parsing, and deferred measurement.
- Fixed register indexing, whole-register classical conditions, overlapping
  wire permutations, observable-output correspondence, and path-variable
  renaming.
- Added regression coverage for unitary, hybrid, parser, reduction, and
  benchmark-runner behavior.
- Added explicit lowering of three-controlled X gates for OWM and OpenQASM
  export.

### Known limitations

- This release is a research prototype, not a complete OpenQASM implementation
  or a production verification service.
- OpenQASM `include` directives are accepted as compatibility no-ops; external
  gate libraries are not loaded.
- OpenQASM export rejects Hadamard gates with more than the currently supported
  number of controls.
- The inspection workflow is a CLI prototype; the planned graphical interface
  is not included.
- Benchmark baselines depend on the local machine. Some selected large
  Sequence cases remain close to timeout or memory limits.
- The post-HH large benchmark is not conclusive enough to support a global
  performance-improvement claim. Performance changes must be reported only for
  the individually measured cases.
