#!/usr/bin/env python3
"""PROTOTYPE circuit generator for the SQbricks external comparison.

Writes OpenQASM 2.0 files into circuits/ and a manifest.csv (file,clifford):
  - ghz_N:   H on q0 then CX q0->qi  (Clifford)
  - indh_N:  one H per qubit         (Clifford)
  - interf_N: N Hadamards on q0 plus one H per other qubit (path-sum
    interference; symbolically reducible)
  - mixed_N: seeded random H/S/T/CX circuit, fixed seed for reproducibility
Sizes stay small enough for exact statevector simulation; the repeated-H
family is the one expected to stress SQbricks' 2^m expansion (published as
an unfavorable case, not hidden).
"""
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "circuits")


def qasm(n, gates):
    lines = ["OPENQASM 2.0;", 'include "qelib1.inc";', f"qreg q[{n}];"]
    lines += gates
    return "\n".join(lines) + "\n"


def ghz(n):
    return qasm(n, ["h q[0];"] + [f"cx q[0],q[{i}];" for i in range(1, n)])


def indh(n):
    return qasm(n, [f"h q[{i}];" for i in range(n)])


def interf(n):
    return qasm(n, ["h q[0];"] * n + [f"h q[{i}];" for i in range(1, n)])


def mixed(n, seed):
    rng = random.Random(seed)
    gates = []
    for _ in range(3 * n):
        r = rng.random()
        if r < 0.5:
            gates.append(f"h q[{rng.randrange(n)}];")
        elif r < 0.7:
            gates.append(f"s q[{rng.randrange(n)}];")
        elif r < 0.9:
            gates.append(f"t q[{rng.randrange(n)}];")
        else:
            c = rng.randrange(n)
            t = rng.randrange(n)
            if c != t:
                gates.append(f"cx q[{c}],q[{t}];")
    return qasm(n, gates)


FAMILIES = [
    ("ghz", [2, 4, 6, 8, 10, 12], ghz, True),
    ("indh", [2, 4, 6, 8, 10, 12], indh, True),
    ("interf", [2, 4, 6, 8, 10], interf, False),
    ("mixed", [4, 6, 8, 10, 12], lambda n: mixed(n, seed=20261114), False),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = []
    for name, sizes, gen, clifford in FAMILIES:
        for n in sizes:
            fname = f"{name}_{n:02d}.qasm"
            with open(os.path.join(OUT, fname), "w") as f:
                f.write(gen(n))
            manifest.append((fname, clifford))
    with open(os.path.join(HERE, "manifest.csv"), "w") as f:
        f.write("file,clifford\n")
        for fname, clifford in manifest:
            f.write(f"{fname},{'yes' if clifford else 'no'}\n")
    print(f"wrote {len(manifest)} circuits to {OUT}")


if __name__ == "__main__":
    main()
