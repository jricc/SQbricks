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
- [ ] Review and validate the consolidated light benchmark function by
  function.
- [ ] Regenerate the local light baseline with the new three-round performance
  cases.
- [ ] Run the light non-regression check successfully.
- [ ] Design an intermediate benchmark with a representative sample of larger
  circuits.

## Notes

- The light baseline is local to the machine and is not versioned.
- The manifest remains the functional oracle.
- The light check uses three complete rounds and median timings.
- Performance is tracked on multiple complementary cases per supported task
  family, selected from `benchmarks/result/benchmarks_Thesis.ods`; smaller cases
  remain functional status checks.
