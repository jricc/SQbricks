#!/usr/bin/env python3
"""PROTOTYPE debug probe v3: pin down the installed myQLM/qat API.

Run inside the container:
    python3 benchmarks/external_comparison/probe_myqlm.py
Tests: AQASM parsing entry points, Program with call-style gates, CLinalg
submit + sample iteration. Paste the output when reporting.
"""
import numpy as np

QASM = """OPENQASM 2.0;
include "qelib1.inc";
qreg q[2];
h q[0];
cx q[0],q[1];
"""


def main():
    import qat.lang as ql
    import qat.qpus as qp

    print("AQASM names:", [a for a in dir(ql.AQASM) if not a.startswith("_")])
    print("parser names:", [a for a in dir(ql.parser) if not a.startswith("_")])

    # --- candidate 1: parse the QASM text directly ---
    prog = None
    how = None
    for expr in (
        "ql.AQASM.qasm_parser",
        "ql.AQASM.parse",
        "ql.parser.qasm_parser",
    ):
        try:
            fn = eval(expr)
            if callable(fn):
                prog = fn(QASM) if "qasm" in expr else None
                if prog is not None:
                    how = expr
                    break
        except Exception as e:
            print(f"{expr} failed: {e!r}")
    # candidate 1b: AQASM parser object
    if prog is None:
        try:
            from qat.lang.AQASM import Parser

            p = Parser()
            prog = p.parse(QASM) if hasattr(p, "parse") else None
            if prog is not None:
                how = "qat.lang.AQASM.Parser().parse"
        except Exception as e:
            print("AQASM.Parser failed:", repr(e))

    # --- candidate 2: Program with call-style gates ---
    if prog is None:
        try:
            from qat.lang import CNOT, H, Program

            p = Program()
            qb = p.qalloc(2)
            H(qb[0])
            CNOT(qb[0], qb[1])
            prog, how = p, "qat.lang.Program + qalloc + H(qb[0]) call-style"
        except Exception as e:
            print("Program call-style failed:", repr(e))

    if prog is None:
        print("PROBE: no program construction worked")
        return
    print("program via:", how, "| type:", type(prog).__name__)

    circ = prog.to_circ() if hasattr(prog, "to_circ") else prog
    job = circ.to_job()
    qpu = qp.CLinalg()
    res = qpu.submit(job)
    print("submit returned:", type(res).__name__)
    samples = list(res)
    print(f"iterable result: {len(samples)} samples")
    s0 = samples[0]
    print("Sample attrs:", [a for a in dir(type(s0)) if not a.startswith("_")])
    st = s0.state
    print("state repr:", repr(st), "| type:", type(st).__name__,
          "| isinstance int:", isinstance(st, int))
    print("state attrs:", [a for a in dir(st) if not a.startswith("_")])
    for attr in ("value", "int", "to_int"):
        if hasattr(st, attr):
            v = getattr(st, attr)
            v = v() if callable(v) else v
            print(f"state.{attr} ->", repr(v))
    for s in samples[:6]:
        print("  sample:", repr(s.state), "amplitude:", s.amplitude)

    # endianness test: X on qubit 0 of a 2-qubit register
    from qat.lang import X

    p2 = ql.Program()
    qb2 = p2.qalloc(2)
    X(qb2[0])
    res2 = qp.CLinalg().submit(p2.to_circ().to_job())
    for s in res2:
        print("X-on-q0 sample:", repr(s.state), "amplitude:", s.amplitude)
    print("(if state is |01> -> index 1 -> qubit0 = LSB, little-endian like Qiskit;"
          " if |10> -> index 2 -> qubit0 = MSB)")
    print("PROBE OK via sample iteration")


if __name__ == "__main__":
    main()
