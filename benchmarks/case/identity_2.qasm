OPENQASM 2.0;
include "qelib1.inc";
qreg q[2];

// X squared is identity; using wire 1 preserves inferred width two.
x q[1];
x q[1];
