# Large regression path selection

This directory contains the first large-regression candidate set.

It is intentionally separate from `scripts/paths/light`: the light regression
runner stays small and stable, while this selection reuses the SQbricks-only
long benchmark runner with a shorter path list.

Selection rule:

- keep every long benchmark type;
- for sized families, keep two representatives that complete without resource
  exhaustion and then the first known `TO` or `OutOfMemory` representative,
  when such a frontier is known from the long benchmark results;
- keep isolated circuits that do not belong to a clear sized family;
- keep explicit watchlist cases that are useful to detect future improvements,
  such as `adder_8` for OWM.

The Makefile targets run these selected cases and write one CSV file per
benchmark type. Baseline/check logic is separate from the light benchmark and
stores one baseline file per selected family.

Current status:

- path selection files exist for every long benchmark type;
- `make benchmark-regression-large TYPE=<type>` runs one selected family;
- `make regression-large` runs all selected families;
- `make regression-large-baseline` writes baselines to
  `benchmarks/baseline/regression-large/`;
- `make regression-large-check` reruns the selection and compares current CSV
  files with those baselines.

The selected large regression uses the same ordered-series cutoff as the long
SQbricks-only benchmark: after `TO` or `OutOfMemory`, larger cases in that same
series are emitted as `SKIP_AFTER_RESOURCE_FAILURE`. Series are scoped by source
directory as well as by name family.

The check compares every row key against the baseline. A timed baseline row must
remain timed, and timed rows are checked for slowdown. Rows that improve from a
non-timed status to a timed result are reported as improvements and do not fail
the check.
