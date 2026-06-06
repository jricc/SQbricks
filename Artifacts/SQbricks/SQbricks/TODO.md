# TODO

## Next

- [x] Regenerate the local light baseline.
- [x] Run the light non-regression check successfully.
- [ ] Consolidate `scripts/benchmarks-light.sh` in quality mode.
- [ ] Review and validate the consolidated light benchmark.
- [ ] Design an intermediate benchmark with a representative sample of larger
  circuits.

## Notes

- The light baseline is local to the machine and is not versioned.
- The manifest remains the functional oracle.
- The light check currently uses five complete rounds and median timings.
- The last successful check covered 29 rows with no detected regression.
