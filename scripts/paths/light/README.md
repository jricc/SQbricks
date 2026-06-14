# Light benchmark manifests

These manifests define the SQbricks-only light benchmark run by
`scripts/benchmarks-light.sh`.

`pairs.csv` contains direct comparisons:

```text
Suite;Case;Kind;ExpectedSequence;ExpectedParallel;TrackPerformance;Path1;Path2
```

`transforms.csv` contains one-input transformation checks:

```text
Suite;Case;Kind;ExpectedSequence;ExpectedParallel;TrackPerformance;Path
```

Supported kinds are:

- `unit`: compare two unitary circuits directly.
- `lift`: lift both inputs with `-sql u`, then compare the lifted circuits.
- `owm`: compare an OWM transformation against the source unitary circuit.
- `tele`: compare a teleportation transformation against the source unitary circuit.
- `owm_vs_tele`: compare OWM and teleportation transformations of the same source.

Expected statuses are `EQ`, `NE`, `NC`, `TIMEOUT`, `OOM`, `CRASH`, and
`PARSE_ERROR`. Use `-` in an expected-status column when that verification mode
does not apply to the row.

When SQbricks exits successfully but its output is empty or does not match any
known result, the runner reports `UNEXPECTED_OUTPUT`. This diagnostic always
fails the functional check and baseline generation; it cannot be accepted by a
manifest and is never converted to `NC`.

`TrackPerformance` is `yes` for the longer cases used to detect performance
regressions in their task family. The light benchmark tracks multiple
complementary cases per supported family. Rows marked `no` still check their
expected status, but their timings are not compared with the baseline.

## Performance data

Check mode requires a baseline. Before running any verification, every tracked
case must have a positive baseline time and exactly the configured number of
timing samples. The baseline round count must also match
`SQBRICKS_LIGHT_RUNS`.

After execution, every tracked case must again have one positive timing sample
per round. Missing or invalid samples make the check fail with
`PerfStatus=INCOMPLETE`; no slowdown ratio is calculated for that row.

## Benchmark definitions

Every full CSV row contains a `DefinitionHash`. It binds that verification to:

- its suite, case, kind, mode, expected status, and `TrackPerformance` value;
- the paths and SHA-256 contents of its input circuit files;
- `SQBRICKS_LIGHT_RUNS`, `SQBRICKS_LIGHT_TIMEOUT`, and
  `SQBRICKS_LIGHT_MEMORY_KB`;
- the benchmark-definition schema used by the runner.

Check mode compares these hashes before running SQbricks. A missing hash means
the baseline uses an older format. A different hash means an input, manifest
entry, or execution setting changed. Both cases require an intentional local
baseline regeneration.

The SQbricks executable and performance thresholds are deliberately excluded.
Code changes are what the benchmark measures, while thresholds only decide how
the resulting timings are classified.

## Coverage

The baseline also records the previous set of benchmark verifications. Check
mode fails before execution when a baseline verification is no longer present
in the manifests. Removing only one mode from a case, such as `Parallel`, is
treated as removing a verification.

New manifest rows are allowed. When `--suite` is used, coverage is compared only
for the selected suite. Regenerate the local baseline only after an intentional
manifest removal has been reviewed.

## Baseline writes

`--save-baseline` validates the complete run before replacing the baseline. All
statuses must match the manifest, no row may be flaky, and every tracked case
must contain one positive timing sample per round.

The validated CSV is first copied to a temporary file in the baseline
directory, then renamed over the target. An invalid run or an I/O error leaves
the previous baseline unchanged and returns a non-zero exit status.

## Progress

The runner displays progress on standard error when it is attached to an
interactive terminal. The total includes all selected Sequence and Parallel
checks across every round.

Set `SQBRICKS_LIGHT_PROGRESS` to control the display:

- `auto` enables it only in an interactive terminal. This is the default.
- `always` forces it.
- `never` disables it.
