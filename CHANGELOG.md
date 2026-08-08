# Changelog

This file records the user-visible changes in SQbricks releases.

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

## [Unreleased]

### Performance

- Improved HH reduction rule with path-variable prefiltering and removal of redundant simplifications (15-16% speedup on targeted large cases like `owm/gf2^9mult_89_413`).
- Optimized `Poly.lift` for dyadic coefficients (1/4, 1/8) with early truncation, reducing `tele/grover_17` phase lift time from 11s to 0.01s.

### Added

- Exact decomposition of 3-controlled X gates (`Program.Macros.c3xdecomp`) for OWM and OpenQASM export, without ancilla qubits or global phase.
