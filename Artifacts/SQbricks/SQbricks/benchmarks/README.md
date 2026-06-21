# SQbricks benchmarks

SQbricks has two benchmark entry points:

- `scripts/benchmarks-light.sh` runs a short SQbricks-only selection for quick
  performance and status checks.
- `scripts/benchmarks.sh` runs the full benchmark families and can compare
  SQbricks with external tools.

The light benchmark reuses circuits from the existing benchmark directories. It
is not a duplicate of the Alcotest test suite: each row is a small representative
workload selected from the same families as the full benchmark script.

## Light benchmark

Run the full light selection:

```sh
./scripts/benchmarks-light.sh
```

Run one suite:

```sh
./scripts/benchmarks-light.sh --suite owm
./scripts/benchmarks-light.sh --suite unit-vs-hybrid
```

Save a result file:

```sh
./scripts/benchmarks-light.sh --output benchmarks/result/light.csv
```

Save a timing baseline, then compare a later run against it:

```sh
./scripts/benchmarks-light.sh --save-baseline benchmarks/result/light-baseline.csv
./scripts/benchmarks-light.sh --baseline benchmarks/result/light-baseline.csv --check
```

`--check` exits with a non-zero status if an expected status changes, or if a
timing is slower than the configured threshold when a baseline is provided.

For a compact status view:

```sh
./scripts/benchmarks-light.sh --stable
```

## Light benchmark limits

The light runner applies a timeout and an optional virtual-memory limit to each
SQbricks command.

```sh
SQBRICKS_LIGHT_TIMEOUT=120s
SQBRICKS_LIGHT_MEMORY_KB=7340032
SQBRICKS_LIGHT_PERF_THRESHOLD=1.25
```

Set `SQBRICKS_LIGHT_MEMORY_KB=0` to disable the memory limit. The default value
matches the 7 GiB limit used by `scripts/benchmarks.sh`.

## Light manifests

The selected cases are listed in:

- `scripts/paths/light/pairs.csv`
- `scripts/paths/light/transforms.csv`

The files are semicolon-separated, like the benchmark result files. Expected
statuses use the following values:

- `EQ`: equivalence proved.
- `NE`: non-equivalence detected.
- `NC`: inconclusive.
- `TIMEOUT`: timeout.
- `OOM`: memory limit exceeded.
- `CRASH`: unexpected crash.
- `PARSE_ERROR`: parsing failed.

For sequence and parallel columns, `-` means that this verification mode is not
run for that row.

Some lifted partial-equivalence shapes are reported as `NC` when both compared
circuits contain initialisations. This is a known limitation of the current
sequence checker, so the light runner treats the corresponding deterministic
error as inconclusive instead of a runner crash.

## Full benchmark

The full benchmark script keeps the historical suite names:

```sh
./scripts/benchmarks.sh owm
./scripts/benchmarks.sh tele
./scripts/benchmarks.sh unit-vs-hybrid
./scripts/benchmarks.sh veriqc
```

It reads the complete path lists from `scripts/paths/paths_*.txt` and emits the
full CSV rows used for evaluation.
