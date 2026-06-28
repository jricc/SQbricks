# TODO

## Next

- [ ] Regenerate the local light baseline after the switch from median timing
  to best-observed timing.
- [ ] Run `make regression-light-check` and validate the new result.
- [ ] Generate the selected large regression baseline with
  `make regression-large-baseline`, then run `make regression-large-check`
  with the three-largest-cases-per-family selection.
- [ ] Fix the `Equiv.parallel` behavior behind
  `owm-vs-qiskit/dqc_teleportation`, where `Parallel` now returns
  `SubCircuitInconclusive` instead of a timed equivalence result.
- [ ] Rerun the long SQbricks-only benchmark with ordered-series cutoff and
  inspect the skipped rows.
- [ ] Create or switch to a dedicated branch before continuing the Equiv
  corrections.
- [ ] Continue the targeted reduction-to-equivalence audit, one issue at a
  time.

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
- [x] Add baseline/check behavior to the selected large regression workflow.

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
- The global benchmark audit compared the long SQbricks-only runner with
  `scripts/benchmarks.sh`, checked manifests, CSV shapes, Makefile entry
  points, and light runner validation tests.
- The large regression selection is in `scripts/paths/regression-large/`.
  It now has per-family baselines in `benchmarks/baseline/regression-large/`
  and check targets separate from the light benchmark.
- Size-ordered families in the large regression keep up to the three largest
  representatives, plus isolated watchlist cases.
