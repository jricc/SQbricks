#!/usr/bin/env python3
"""PROTOTYPE: numeric agreement of final-state amplitudes across engines.

Reads results/raw/<engine>/<case>__<tag>__run<k>.txt and results/statuses.csv.
For every case (from manifest.csv) and every run k separately -- results are
never merged across runs -- the amplitudes of each expected engine are
compared against the qiskit/statevector run k reference: max absolute
difference over the full dimension 2^n (n parsed from the case name), with
the global phase kept and no phase alignment. Non-finite amplitudes are
rejected. qiskit/stabilizer produces no amplitudes and stays out of this
check. Any missing reference, missing engine run, non-ok status, error or
unavailable line makes the run INCOMPLETE and exits non-zero: a partial run
never prints ALL PASS.

This is a numerical cross-check only; it is not a validation of the symbolic
exactness of SQbricks.
"""
import argparse
import csv
import glob
import math
import os
from collections import defaultdict

EXPECTED_AMP_ENGINES = [
    "sqbricks/group_exact",
    "qiskit/statevector",
    "qiskit/matrix_product_state",
    "myqlm/clinalg",
]
REFERENCE = "qiskit/statevector"


def collect(raw_dir):
    # (case, engine_method, run) -> {index: complex}
    amps = defaultdict(dict)
    problems = defaultdict(list)  # (case, run) -> [lines]
    for path in glob.glob(os.path.join(raw_dir, "*", "*.txt")):
        engine = os.path.basename(os.path.dirname(path))
        base = os.path.splitext(os.path.basename(path))[0]  # case__tag__runK
        _, _, run = base.rpartition("__")  # case names contain underscores
        with open(path) as f:
            for line in f:
                parts = line.strip().split(",")
                if len(parts) == 5 and parts[0] == "amp":
                    # parts[1] is "<case>/<method>"; the case comes from the
                    # line itself, not from the file name.
                    case, _, method = parts[1].partition("/")
                    amps[(case, f"{engine}/{method}", run)][int(parts[2])] = complex(
                        float(parts[3]), float(parts[4])
                    )
                elif parts[0] in ("error", "unavailable"):
                    problems[(parts[1], run)].append(line.strip())
    return amps, problems


def case_dim(case):
    return 1 << int(case.rsplit("_", 1)[1])


def max_diff(ref, other, dim):
    worst = 0.0
    for i in range(dim):
        worst = max(worst, abs(ref.get(i, 0j) - other.get(i, 0j)))
    return worst


def max_diff_bit_reversed(ref, other, dim):
    nbits = dim.bit_length() - 1
    worst = 0.0
    for i in range(dim):
        j = int(f"{i:0{nbits}b}"[::-1], 2) if dim > 1 else 0
        worst = max(worst, abs(ref.get(i, 0j) - other.get(j, 0j)))
    return worst


def finite(vec):
    return all(math.isfinite(a.real) and math.isfinite(a.imag) for a in vec.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_dir")
    ap.add_argument("--tol", type=float, default=1e-9)
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--manifest", default=os.path.join(here, "manifest.csv"))
    ap.add_argument("--statuses", default=None)
    args = ap.parse_args()
    amps, problems = collect(args.raw_dir)
    statuses_path = args.statuses or os.path.join(
        os.path.dirname(args.raw_dir.rstrip("/")), "statuses.csv"
    )

    with open(args.manifest) as f:
        next(f)
        cases = {
            line.split(",")[0].removesuffix(".qasm"): line.split(",")[1].strip() == "yes"
            for line in f
            if line.strip()
        }

    statuses = {}
    expected = set()
    if os.path.exists(statuses_path):
        with open(statuses_path) as f:
            for row in csv.DictReader(f):
                key = (row["engine"], row["case"], row["tag"], row["run"])
                statuses[key] = row["status"]
                expected.add(key)

    failures = 0
    comparisons = 0
    print(f"tolerance: {args.tol:g} (max abs amplitude difference, global phase kept)")
    print(f"reference: {REFERENCE}, per run; dimension = 2^n from the case name")
    for case, clifford in sorted(cases.items()):
        dim = case_dim(case)
        tags = [
            ("sqbricks", "group_exact"),
            ("qiskit", "statevector"),
            ("qiskit", "matrix_product_state"),
            ("myqlm", "clinalg"),
        ]
        if clifford:
            tags.append(("qiskit", "stabilizer"))  # timed only, no amplitudes
        runs = sorted({k[3] for k in expected if k[1] == case})
        print(f"case {case} (dim={dim}, runs={runs}):")
        if not runs:
            print("  MISSING all runs in statuses.csv -> INCOMPLETE")
            failures += 1
            continue
        for key, st in sorted(statuses.items()):
            if key[1] == case and st != "ok":
                print(f"  STATUS {key} -> {st}")
                failures += 1
        for run in runs:
            for p in problems.get((case, run), []):
                print(f"  PROBLEM run {run}: {p}")
                failures += 1
            ref = amps.get((case, REFERENCE, run))
            if ref is None:
                print(f"  run {run}: MISSING reference {REFERENCE} -> INCOMPLETE")
                failures += 1
                continue
            if not finite(ref):
                print(f"  run {run}: non-finite reference amplitude -> FAIL")
                failures += 1
                continue
            for engine, tag in tags:
                engine_method = f"{engine}/{tag}"
                if engine_method in (REFERENCE, "qiskit/stabilizer"):
                    continue  # stabilizer: timed only, no amplitudes
                vec = amps.get((case, engine_method, run))
                if vec is None:
                    print(f"  run {run}: {engine_method:28s} MISSING -> INCOMPLETE")
                    failures += 1
                    continue
                comparisons += 1
                if not finite(vec):
                    print(f"  run {run}: {engine_method:28s} non-finite -> FAIL")
                    failures += 1
                    continue
                d = max_diff(ref, vec, dim)
                dr = max_diff_bit_reversed(ref, vec, dim)
                status = "PASS" if d <= args.tol else "FAIL"
                if d > args.tol:
                    failures += 1
                note = f" (bit-reversed: {dr:.3g})" if dr < d else ""
                print(
                    f"  run {run}: {engine_method:28s} max|diff|={d:.3g} {status}{note}"
                )
    if failures == 0 and comparisons > 0:
        print(f"ALL PASS (complete: {comparisons} comparisons, tol={args.tol:g})")
        return 0
    print(
        f"INCOMPLETE OR FAILED: {failures} problem(s), {comparisons} comparison(s), tol={args.tol:g}"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
