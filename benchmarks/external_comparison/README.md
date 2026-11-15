# PROTOTYPE — external comparison: SQbricks vs Qiskit Aer vs myQLM CLinalg

Prototype benchmark comparing SQbricks' **exact** symbolic pipeline
(parse → execute → reduce → expand → group_exact) against statevector-class
simulators on the same noiseless, measurement-free OpenQASM 2.0 circuits.
`group_exact` is not modified by this comparison; its result is what gets
exported. The approximate `Simulation.group` is not part of the measured
pipeline.

## Conventions

- **Same input files**: every engine reads the same `circuits/*.qasm`.
- **Qubit order**: qubit `i` is bit `i` of the state index (little-endian),
  the Qiskit convention; `check_agreement.py` also reports a bit-reversed
  variant to detect an endianness mistake.
- **Same requested result**: final-state amplitudes, global phase kept (no
  phase alignment anywhere). SQbricks amplitudes come from `group_exact`,
  converted to floats by `Simulation.exact_to_complex` **only** for the
  numeric cross-check.
- **Agreement check**: max |amplitude difference| against Qiskit Aer
  `statevector`, tolerance `--tol` (default 1e-9), dimension `2^n` taken
  from the case name. Expected amplitude producers: `sqbricks/group_exact`,
  `qiskit/statevector`, `qiskit/matrix_product_state`, `myqlm/clinalg`.
  `qiskit/stabilizer` (Clifford circuits only) produces probabilities, not
  amplitudes: it is timed separately and excluded from the amplitude check.
  Missing references, missing engines, and `error,`/`unavailable,` lines
  make the run INCOMPLETE and exit non-zero — a partial run never prints
  ALL PASS. This is a numerical cross-check only, not a validation of
  symbolic exactness.
- **Circuit families** (`gen_circuits.py`, deterministic, fixed seed):
  `ghz` and `indh` (Clifford), `interf` (repeated H on one qubit: symbolic
  interference, the case expected to stress SQbricks' 2^m expansion and
  published as an unfavorable case), `mixed` (seeded H/S/T/CX).

## Measurement protocol

- **Timing convention** (harmonized across engines): circuit reading,
  preparation and result computation are inside the timed region; printing
  amplitudes and the numeric validation are outside it; Python imports
  happen before the clock starts. Per-step times are kept.
- Smoke test on `ghz_02` first: every amplitude-producing adapter must emit
  `amp,` lines, otherwise the series is aborted.
- Per circuit and per method, `RUNS=3` **separate processes**, sequential,
  pinned to one CPU via `taskset -c 0` when available, `OMP_NUM_THREADS=1`,
  under `timeout 120` and `ulimit -v 8388608` (8 GiB virtual; OCaml 5 needs a
  generous virtual limit). Peak memory is per process: `VmHWM` from
  `/proc/self/status` for the OCaml runner, `ru_maxrss` for Python.
- Amplitudes are verified **per run** by `check_agreement.py` (runs are
  never merged), against the `qiskit/statevector` run of the same
  repetition, over the full dimension `2^n`, non-finite amplitudes
  rejected, global phase kept. Missing runs, non-ok statuses, `error,` /
  `unavailable,` lines make the check INCOMPLETE (exit non-zero); a partial
  run never prints ALL PASS. `qiskit/stabilizer` stays out of the amplitude
  comparison.
- `results/summary.csv`: per (engine, case, tag) the run status
  (ok / error(rc) / timeout / missing) and median/min/max of each phase
  time plus peak RSS (max across runs). SQbricks phases: parse, execute,
  reduce, expand, expand_direct, group_exact, total, plus
  `paths_agree` (do `expand` and `expand_direct` produce the same paths).
- `results/versions.txt`: date, host, nproc, pinning, OCaml/dune/zarith,
  Python, qiskit/qiskit-aer/myqlm versions.
- SQbricks runs both `expand` (reference, unchanged) and the experimental
  `expand_direct`; `--direct` (env `SQB_ARGS="--direct"`) makes the exact
  grouping run on the `expand_direct` paths.

## Run

```bash
# in the project container, with qiskit, qiskit-aer and myqlm installed
# reference run, kept before any optimization:
RESULTS_DIR=benchmarks/external_comparison/results_reference \
  bash benchmarks/external_comparison/run_all.sh
# later, with the experimental expansion:
SQB_ARGS="--direct" bash benchmarks/external_comparison/run_all.sh
# outputs: $RESULTS_DIR/{versions.txt,statuses.csv,summary.csv,agreement.txt}
#          and $RESULTS_DIR/raw/<engine>/<case>__<tag>__run<k>.txt
```

Requires `pip install qiskit-aer myqlm` in addition to the image's qiskit;
missing packages are reported as `unavailable,...` lines and make the
agreement check INCOMPLETE.

## Known limitations

- Synthetic families only; SQbricks' expansion cost is 2^m in the number of
  path variables before reduction, so `interf` may hit the timeout at large
  sizes — reported as a status, not hidden.
- The myQLM result API differs across versions; `run_myqlm.py` tries the
  documented `qat.qpus.CLinalg` + `submit` path first, then legacy imports,
  and records the working accessor in an `api_used,` line.
- Grouping-only timings for SQbricks; not the total cost of equivalence
  checking.
