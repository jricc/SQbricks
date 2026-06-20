# TODO

## Next

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
- [ ] Review the simplified light benchmark at workflow level.
- [ ] Regenerate the local light baseline with the new three-round performance
  cases.
- [ ] Run the light non-regression check successfully.
- [ ] Design an intermediate benchmark with a representative sample of larger
  circuits.
- [x] Add long SQbricks-only benchmarks without external verification tools.

## Notes

- The light baseline is local to the machine and is not versioned.
- The manifest remains the functional oracle.
- The light check uses three complete rounds and median timings.
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
