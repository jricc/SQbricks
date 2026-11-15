#!/usr/bin/env python3
"""PROTOTYPE: aggregate results/raw into summary.csv.

Reads results/raw/<engine>/<case>__<tag>__run<k>.txt plus results/statuses.csv
(engine,case,tag,run,status). For each (engine, case, tag) prints one row per
metric with median/min/max across runs, plus peak_rss_mb (max across runs).
Status is the worst run status (timeout > error > ok); missing runs are
reported as status=missing. Columns:
  engine,case,tag,status,metric,median,min,max
"""
import csv
import glob
import os
import statistics
import sys
from collections import defaultdict


def main(results_dir):
    raw_dir = os.path.join(results_dir, "raw")
    statuses = {}
    status_csv = os.path.join(results_dir, "statuses.csv")
    if os.path.exists(status_csv):
        with open(status_csv) as f:
            for row in csv.DictReader(f):
                statuses[(row["engine"], row["case"], row["tag"], row["run"])] = row["status"]

    groups = defaultdict(list)  # (engine, case, tag) -> [run files]
    for path in sorted(glob.glob(os.path.join(raw_dir, "*", "*.txt"))):
        engine = os.path.basename(os.path.dirname(path))
        base = os.path.splitext(os.path.basename(path))[0]  # case__tag__runK
        case_tag, _, run = base.rpartition("__")
        case, _, tag = case_tag.rpartition("__")  # case names contain "_"
        groups[(engine, case, tag)].append((run, path))

    print("engine,case,tag,status,metric,median,min,max")
    for (engine, case, tag), runs in sorted(groups.items()):
        worst = "ok"
        order = {"ok": 0, "error": 1, "timeout": 2}
        for run, _ in runs:
            st = statuses.get((engine, case, tag, run), "missing")
            if order.get(st, 1) > order.get(worst, 0):
                worst = st
        metrics = defaultdict(list)  # metric -> [values across runs]
        for run, path in runs:
            with open(path) as f:
                for line in f:
                    p = line.strip().split(",")
                    if len(p) == 4 and p[0] == "phase_ms":
                        metrics[p[2]].append(float(p[3]))
                    elif len(p) == 4 and p[0] == "metric":
                        try:
                            metrics[p[2]].append(float(p[3]))
                        except ValueError:
                            metrics[p[2]].append(p[3])  # e.g. expand_variant
                    elif len(p) == 3 and p[0] == "peak_rss_mb":
                        metrics["peak_rss_mb"].append(float(p[2]))
        for metric, values in sorted(metrics.items()):
            if all(isinstance(v, float) for v in values):
                print(
                    f"{engine},{case},{tag},{worst},{metric},"
                    f"{statistics.median(values):g},{min(values):g},{max(values):g}"
                )
            else:
                uniq = "/".join(sorted({str(v) for v in values}))
                print(f"{engine},{case},{tag},{worst},{metric},{uniq},,")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "results")
