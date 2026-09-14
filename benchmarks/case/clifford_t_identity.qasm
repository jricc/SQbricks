OPENQASM 2.0;
include "qelib1.inc";
qreg q[2];

// Two copies of X ; T-dagger ; corrected CH decomposition ; X ; T ; CX.
// Gates are written in execution order, matching case_clifford_t_identity.
x q[0];
tdg q[1];
s q[1];
h q[1];
t q[1];
h q[1];
sdg q[1];
cx q[0],q[1];
s q[1];
h q[1];
tdg q[1];
h q[1];
sdg q[1];
cx q[0],q[1];
h q[1];
cx q[0],q[1];
h q[1];
x q[0];
t q[1];
cx q[0],q[1];

// Second copy.
x q[0];
tdg q[1];
s q[1];
h q[1];
t q[1];
h q[1];
sdg q[1];
cx q[0],q[1];
s q[1];
h q[1];
tdg q[1];
h q[1];
sdg q[1];
cx q[0],q[1];
h q[1];
cx q[0],q[1];
h q[1];
x q[0];
t q[1];
cx q[0],q[1];
