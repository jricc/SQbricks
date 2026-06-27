# TODO

## Next

- [ ] Regenerate the local light baseline after the switch from median timing
  to best-observed timing.
- [ ] Run `make regression-light-check` and validate the new result.
- [ ] Finish the large regression workflow: review the selected paths, add
  baseline/check behavior, then run baseline and check.
- [ ] Rerun the long SQbricks-only benchmark with ordered-series cutoff and
  inspect the skipped rows.
- [ ] Create or switch to a dedicated branch before continuing the Equiv
  corrections.
- [ ] Continue the targeted reduction-to-equivalence audit, one issue at a
  time.
- [ ] Remove the old untyped `Rules.HH.hh`,
  `Rules.Variable_replacement.variable_replacement`, and
  `Rules.Variable_replacement.poly_normalized` entry points once the typed
  reduction results are validated, before merging.

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
- [x] Add long SQbricks-only benchmarks without external verification tools.
- [x] Make the light performance check less sensitive to local load spikes by
  using the best observed timing across three rounds.
- [x] Start the large regression path selection separately from the light
  runner.
- [x] Start the Equiv audit by replacing some uncontrolled parameter mismatch
  failures with explicit equivalence results.
- [x] Stop ordered long benchmark series after timeout or memory failure while
  keeping other series running.

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
- No intermediate benchmark is planned: it would mostly duplicate the light and
  long benchmark roles.
- The global benchmark audit compared the long SQbricks-only runner with
  `scripts/benchmarks.sh`, checked manifests, CSV shapes, Makefile entry
  points, and light runner validation tests.
- The large regression selection is in `scripts/paths/regression-large/`.
  It is prepared for run-only CSV generation; baseline/check behavior is still
  pending.
- The current Equiv cleanup introduces typed reduction failures so malformed
  path sums are not confused with rules that simply do not apply. The old
  untyped `Rules.HH.hh`, `Rules.Variable_replacement.variable_replacement`,
  and `Rules.Variable_replacement.poly_normalized` entry points still have to be
  removed after validation.
