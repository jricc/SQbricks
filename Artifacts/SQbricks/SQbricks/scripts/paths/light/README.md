# Light benchmark manifests

These manifests define the SQbricks-only light benchmark run by
`scripts/benchmarks-light.sh`.

`pairs.csv` contains direct comparisons:

```text
Suite;Case;Kind;ExpectedSequence;ExpectedParallel;Path1;Path2
```

`transforms.csv` contains one-input transformation checks:

```text
Suite;Case;Kind;ExpectedSequence;ExpectedParallel;Path
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
