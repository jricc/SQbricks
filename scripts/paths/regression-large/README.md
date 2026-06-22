# Large regression path selection

This directory contains the first large-regression candidate set.

It is intentionally separate from `scripts/paths/light`: the light regression
runner stays small and stable, while this selection reuses the SQbricks-only
long benchmark runner with a shorter path list.

Selection rule:

- keep every long benchmark type;
- for sized families, keep the largest representative present in the long path
  list;
- keep isolated circuits that do not belong to a clear sized family;
- keep explicit watchlist cases that are useful to detect future improvements,
  such as `adder_8` for OWM.

The initial Makefile targets run these selected cases and write one CSV file per
benchmark type. Baseline/check logic will be added after this selection is
reviewed and validated.

Current status:

- path selection files exist for every long benchmark type;
- `make benchmark-regression-large TYPE=<type>` runs one selected family;
- `make regression-large` runs all selected families;
- baseline/check behavior is not implemented yet.

The selected large regression uses the same ordered-series cutoff as the long
SQbricks-only benchmark: after `TO` or `OutOfMemory`, larger cases in that same
series are emitted as `SKIP_AFTER_RESOURCE_FAILURE`.

Before turning this into a non-regression check, validate the selected paths
against fresh long benchmark results and decide which rows should be tracked for
performance.
