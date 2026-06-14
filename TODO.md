# TODO

## Next

- [x] Reject missing baselines and incomplete performance samples in light
  check mode.
- [x] Detect light benchmark cases or modes removed from the manifests.
- [x] Refuse to write an invalid light baseline and replace valid baselines
  atomically.
- [x] Treat unrecognized or empty successful SQbricks output as
  `UNEXPECTED_OUTPUT`.
- [x] Bind the local baseline to the exact benchmark definition.
- [x] Consolidate `scripts/benchmarks-light.sh` in quality mode.
- [x] Review and validate the light benchmark entry points in `Makefile`.
- [x] Create the incremental SQbricks technical documentation in French and
  English.
- [x] Require both documentation versions to be updated after each function
  validated in quality mode.
- [ ] Review and validate the consolidated light benchmark function by
  function.
- [ ] Continue `test_check_requires_baseline` review with
  `assert_failed_with`, then `assert_no_sqv_run`.
- [ ] Regenerate the local light baseline with the new three-round performance
  cases.
- [ ] Run the light non-regression check successfully.
- [ ] Design an intermediate benchmark with a representative sample of larger
  circuits.
- [ ] Add full benchmarks without external tools.

## Notes

- The light baseline is local to the machine and is not versioned.
- The manifest remains the functional oracle.
- The light check uses three complete rounds and median timings.
- The technical documentation is maintained in `doc/SQbricks.md` and
  `doc/SQbricks.en.md`.
- Performance is tracked on multiple complementary cases per supported task
  family, selected from `benchmarks/result/benchmarks_Thesis.ods`; smaller cases
  remain functional status checks.
