# TODO

## Next

- [ ] Create or switch to a dedicated branch before continuing the Equiv
  corrections.
- [ ] Finish the remaining phase 3 audit targets: parser, AST, deferred
  measurement, and path-sum generation.
- [ ] Fix the `Equiv.parallel` behavior behind
  `owm-vs-qiskit/dqc_teleportation`, where `Parallel` now returns
  `SubCircuitInconclusive` instead of a timed equivalence result.
- [ ] Start phase 4 bug fixes one issue at a time, with focused regression
  tests before or with each fix.

## Done

- [x] Reject missing baselines and incomplete performance samples in light
  check mode.
- [x] Refuse to write an invalid light baseline and replace valid baselines
  atomically.
- [x] Treat unrecognized or empty successful SQbricks output as
  `UNEXPECTED_OUTPUT`.
- [x] Consolidate `scripts/benchmarks-light.sh` in quality mode.
- [x] Simplify the light benchmark around functional status and tracked
  performance checks.
- [x] Review and validate the light benchmark entry points in `Makefile`.
- [x] Create the incremental SQbricks technical documentation in French and
  English.
- [x] Require both documentation versions to be updated after each function
  validated in quality mode.
- [x] Review the simplified light benchmark at workflow level.
- [x] Regenerate the local light baseline with the new three-round performance
  cases.
- [x] Run the light non-regression check successfully in a complete SQbricks
  development environment.
- [x] Complete roadmap phase 1: minimal regression benchmark.
- [x] Add long SQbricks-only benchmarks without external verification tools.
- [x] Make the light performance check less sensitive to local load spikes by
  using the best observed timing across three rounds.
- [x] Start the large regression path selection separately from the light
  runner.
- [x] Start the Equiv audit by replacing some uncontrolled parameter mismatch
  failures with explicit equivalence results.
- [x] Stop ordered long benchmark series after timeout or memory failure while
  keeping other series running.
- [x] Add baseline/check behavior to the selected large regression workflow.
- [x] Rerun and inspect the long SQbricks-only benchmark with ordered-series
  cutoff.
- [x] Complete roadmap phase 2: safe long benchmark runner.
- [x] Audit the phase 3 reduction target.
- [x] Audit the phase 3 equivalence-checking target.
- [x] Audit the phase 3 separation target.
- [x] Audit the phase 3 projection target.
- [x] Audit the phase 3 benchmark-scripts target.
- [x] Keep the reduction entry-point names short after validating the typed
  reduction results.
- [x] Route Equiv initial-state construction through
  `Path_sum.ofSize_init_result` so invalid initialization data becomes
  `ErrorInvalidQubitIndex`.
- [x] Route observable-qubit comparison in
  `Equiv.compare_inputs_with_identity` through `Qubit.equal_result` so malformed
  comparison metadata becomes
  `ErrorMalformedPathSum`.
- [x] Reject non-unitary `Program` constructs such as `InitQ` during Equiv
  parameter preparation before symbolic execution.
- [x] Reject malformed unitary gate applications in Equiv parameter preparation
  with `ErrorInvalidProgram`.
- [x] Reject empty targets for gates that need one in Equiv parameter
  preparation with `ErrorInvalidProgram`.
- [x] Keep `GP` targets valid in Equiv parameter preparation because they do
  not affect symbolic execution.
- [x] Reject controlled `GP` applications whose targets overlap controls, so
  their well-formedness constraints match other controlled gates.
- [x] Document the well-formed circuit constraints enforced by Equiv.
- [x] Keep malformed `GP/U1` programs printable so Equiv diagnostics can report
  `ErrorInvalidProgram`.
- [x] Route the sequential phase classification through `Poly.equal_result` so
  malformed phase comparisons become `ErrorMalformedPathSum`.
- [x] Route path-sum phase comparison through `Poly.equal_result` so malformed
  phase metadata is not reported as plain inequality.
- [x] Make Equiv separability checks validate ket width and output indices
  before extracting variables.
- [x] Add `Program.Macros.apply_swap_result` and use it from Equiv so swap
  preparation errors do not escape as `failwith`.
- [x] Add `Program.inverse_result` and use it from Equiv so non-reversible
  programs are reported explicitly.

## Notes

- The light baseline is stored in `benchmarks/baseline/light.csv`.
- The manifest remains the functional oracle.
- The light check uses three complete rounds and best-observed timings.
- The light runner default timeout is `240s`.
- The technical documentation is maintained in `doc/SQbricks.md` and
  `doc/SQbricks.en.md`.
- The light baseline no longer stores a benchmark definition hash. If the
  manifest changes intentionally, regenerate the local baseline.
- Performance is tracked on multiple complementary cases per supported task
  family, selected from `benchmarks/result/benchmarks_Thesis.ods`; smaller cases
  remain functional status checks.
- The long SQbricks-only benchmark reuses the historical path files, including
  `qiskit-hybrid` and `owm-vs-qiskit`; it does not run external verification
  tools.
- The long runner writes `SKIP_AFTER_RESOURCE_FAILURE` for larger cases in an
  ordered source-scoped series after `TO` or `OutOfMemory`.
- SQbricks-only benchmark levels are now split into light, selected large
  regression, and full long benchmark.
- Vigilance: `Path_sum.equal_result` now has defensive phase-comparison errors
  (`IncompatiblePhaseWidths`, `IncompletePhasePathVariableMap`). They are
  propagated to Equiv, but they are not directly covered by a natural
  `Path_sum.equal_result` test yet because the current ket comparison does not
  expose the incomplete phase-mapping situation.
- The global benchmark audit compared the long SQbricks-only runner with
  `scripts/benchmarks.sh`, checked manifests, CSV shapes, Makefile entry
  points, and light runner validation tests.
- The large regression selection is in `scripts/paths/regression-large/`.
  It now has per-family baselines in `benchmarks/baseline/regression-large/`
  and check targets separate from the light benchmark.
- Size-ordered families in the large regression keep up to the three largest
  representatives, plus isolated watchlist cases.
- The current Equiv cleanup introduces typed reduction failures so malformed
  path sums are not confused with rules that simply do not apply. The reduction
  pipeline now uses typed results directly, including the public reduction
  entry point.
- Watch the behavior change in `Path_sum.substitute_result`: target path
  variables are now protected. This is intended, but it may expose a bug if an
  external caller relied on the old `except_path_var=true` behavior still
  substituting inside `phase` or `ket`.
- Watch the stricter `Ket.path_var_order_result` behavior: a ket containing
  path variables while the declared path-variable count is zero now reports
  malformed metadata instead of silently returning empty ordering arrays.
- Watch the recent direct `Poly.t` construction in tests: replacing local
  `to_poly` uses with `+++ Poly.empty` should be equivalent, but it may expose a
  hidden ordering or duplicate-insertion assumption in polynomial tests.
- Watch the new typed `Path_sum_library` gate constructors: the non-typed
  wrappers should preserve the old path sums and failure order, but this broad
  mechanical pass may expose a mismatch in one gate formula or target-index
  validation path.
