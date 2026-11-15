#!/usr/bin/env python3
"""PROTOTYPE: run one QASM circuit with myQLM CLinalg (default C++ simulator).

Usage: run_myqlm.py <case> <file.qasm>
Output lines: same protocol as run_qiskit.py, engine tag "clinalg", plus an
api_used,myqlm,<shape> line.

API (verified against the installed qat by probe_myqlm.py):
  from qat.lang import Program, H, S, T, CNOT
  prog = Program(); qb = prog.qalloc(n); H(qb[0]); CNOT(qb[0], qb[1])
  res = CLinalg().submit(prog.to_circ().to_job())
  for sample in res: index = sample.state.lsb_int; amp = sample.amplitude
The Qiskit-compatible state index uses state.lsb_int (qubit i = bit i of the
index); the probe showed X on qubit 0 displays as |10> (MSB-first) and has
lsb_int = 1, matching Qiskit's little-endian convention. A SAMPLE job on
CLinalg returns the exact amplitude distribution (statevector simulator).
"""
import platform
import re
import resource
import sys
import time


def parse_qasm(path):
    n = None
    gates = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            m = re.match(r"qreg\s+q\[(\d+)\];", line)
            if m:
                n = int(m.group(1))
                continue
            m = re.match(r"(h|s|t)\s+q\[(\d+)\];", line)
            if m:
                gates.append((m.group(1), int(m.group(2)), None))
                continue
            m = re.match(r"cx\s+q\[(\d+)\],\s*q\[(\d+)\];", line)
            if m:
                gates.append(("cx", int(m.group(1)), int(m.group(2))))
    return n, gates


def build_program(n, gates):
    from qat.lang import CNOT, H, Program, S, T

    prog = Program()
    qb = prog.qalloc(n)
    for g, a, b in gates:
        if g == "h":
            H(qb[a])
        elif g == "s":
            S(qb[a])
        elif g == "t":
            T(qb[a])
        elif g == "cx":
            CNOT(qb[a], qb[b])
    return prog


def main():
    case, path = sys.argv[1], sys.argv[2]
    print(f"version,python,{platform.python_version()}")
    try:
        import qat
        from qat.qpus import CLinalg
    except ImportError:
        print("unavailable,myqlm,pip install myqlm")
        return
    print(f"api,myqlm,qat {getattr(qat, '__version__', 'unknown')}")

    t0 = time.perf_counter()
    n, gates = parse_qasm(path)
    prog = build_program(n, gates)
    res = CLinalg().submit(prog.to_circ().to_job())
    samples = list(res)
    t1 = time.perf_counter()
    print(f"phase_ms,{case},run_clinalg,{(t1 - t0) * 1000.0:.6f}")
    print(f"phase_ms,{case},total,{(t1 - t0) * 1000.0:.6f}")
    print("api_used,myqlm,Program.call-style + CLinalg.submit + Sample.lsb_int")
    for s in samples:
        a = complex(s.amplitude)
        if abs(a) > 1e-12:
            index = int(s.state.lsb_int)
            print(f"amp,{case}/clinalg,{index},{a.real:.17g},{a.imag:.17g}")
    rss_kb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss  # kB on Linux
    print(f"peak_rss_mb,{case},{rss_kb / 1024.0:.1f}")


if __name__ == "__main__":
    main()
