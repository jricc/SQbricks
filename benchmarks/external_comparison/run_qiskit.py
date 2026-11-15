#!/usr/bin/env python3
"""PROTOTYPE: run one QASM circuit with one Qiskit Aer method.

Usage: run_qiskit.py <case> <file.qasm> <method>
  method in {statevector, matrix_product_state, stabilizer}
Output lines (parsed by summarize.py / check_agreement.py):
  version,python|qiskit|qiskit_aer,<v>
  phase_ms,<case>,parse,<ms> | run_<method>,<ms> | total,<ms>
  amp,<case>/<method>,<index>,<re>,<im>   only when |amp| > 1e-12
  peak_rss_mb,<case>,<mb>                 process peak RSS (ru_maxrss, kB/1024)
  unavailable,... / error,...             if something failed
For amplitude-producing methods the circuit gets save_statevector() so that
result.get_statevector() is available. stabilizer yields probabilities, so
it is timed but prints no amplitudes. Qubit 0 is the least significant bit
of the state index (Qiskit convention, same as the SQbricks runner).
"""
import platform
import resource
import sys
import time


def main():
    case, path, method = sys.argv[1], sys.argv[2], sys.argv[3]
    print(f"version,python,{platform.python_version()}")
    try:
        import qiskit
        from qiskit import qasm2
    except ImportError:
        print("unavailable,qiskit,pip install qiskit")
        return
    print(f"version,qiskit,{qiskit.__version__}")
    try:
        import qiskit_aer
        from qiskit_aer import AerSimulator
    except ImportError:
        print("unavailable,qiskit_aer,pip install qiskit-aer")
        return
    print(f"version,qiskit_aer,{qiskit_aer.__version__}")

    # Timing convention (shared with the SQbricks runner): circuit reading,
    # preparation and result computation are inside the timed region;
    # printing amplitudes and the numeric validation are outside it.
    # Python imports happen before t0.
    t0 = time.perf_counter()
    circ = qasm2.load(path)
    if method != "stabilizer":
        circ.save_statevector()
    t1 = time.perf_counter()
    print(f"phase_ms,{case},parse,{(t1 - t0) * 1000.0:.6f}")

    ta = time.perf_counter()
    sim = AerSimulator(method=method)
    result = sim.run(circ).result()
    data = None
    if method != "stabilizer":
        try:
            sv = result.get_statevector()
        except Exception:
            sv = result.data(0)["statevector"]
        data = sv.data if hasattr(sv, "data") else sv
    tb = time.perf_counter()
    print(f"phase_ms,{case},run_{method},{(tb - ta) * 1000.0:.6f}")
    tc = time.perf_counter()
    print(f"phase_ms,{case},total,{(tc - t0) * 1000.0:.6f}")

    # Outside the timed region: export of the amplitudes.
    if data is not None:
        for i, a in enumerate(data):
            if abs(a) > 1e-12:
                print(f"amp,{case}/{method},{i},{a.real:.17g},{a.imag:.17g}")
    rss_kb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss  # kB on Linux
    print(f"peak_rss_mb,{case},{rss_kb / 1024.0:.1f}")


if __name__ == "__main__":
    main()
