#!/bin/bash
# PROTOTYPE: external comparison SQbricks vs Qiskit Aer vs myQLM CLinalg.
#
# Usage:  bash benchmarks/external_comparison/run_all.sh
# Run inside the project container (dune; python3 with qiskit, qiskit-aer and
# myqlm installed). Protocol: smoke test on one tiny circuit first (aborts if
# an adapter produces no amplitudes); then, per circuit and per method, RUNS
# separate processes, sequentially, pinned to one CPU when taskset exists,
# with OMP_NUM_THREADS=1, under `timeout 120` and `ulimit -v 8388608`.
# Outputs: results/{versions.txt,statuses.csv,summary.csv,agreement.txt}
#          and results/raw/<engine>/<case>__<tag>__run<k>.txt
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"
RUNS=3
TIMEOUT_S=120
MEM_KB=$((8 * 1024 * 1024))
# Output directory: override with RESULTS_DIR to keep a reference run, e.g.
#   RESULTS_DIR=benchmarks/external_comparison/results_reference bash .../run_all.sh
RES="${RESULTS_DIR:-$HERE/results}"
# Extra args for the SQbricks runner, e.g. SQB_ARGS="--direct" to run the
# exact chain on expand_direct paths instead of expand paths.
SQB_ARGS="${SQB_ARGS:-}"

mkdir -p "$RES" "$HERE/circuits"
rm -rf "$RES/raw" "$RES/statuses.csv" "$RES/summary.csv" "$RES/agreement.txt"
mkdir -p "$RES/raw"

if command -v taskset > /dev/null 2>&1; then
  PIN=(taskset -c 0)
else
  PIN=()
fi
export OMP_NUM_THREADS=1

{
  echo "date_utc: $(date -u +%FT%TZ)"
  echo "host: $(uname -a)"
  echo "nproc: $(nproc 2>/dev/null || echo '?')"
  echo "pinning: ${PIN[*]:-none (sequential runs, OMP_NUM_THREADS=1)}"
  echo "omp_num_threads: $OMP_NUM_THREADS"
  echo "runs_per_case: $RUNS  timeout_s: $TIMEOUT_S  ulimit_v_kb: $MEM_KB"
  ocaml -version
  dune --version
  opam list 2>/dev/null | grep -iE "zarith|sqbricks" || true
  python3 -V
  pip list 2>/dev/null | grep -iE "qiskit|myqlm|qat" || true
} > "$RES/versions.txt" 2>&1
echo "engine,case,tag,run,status" > "$RES/statuses.csv"

python3 "$HERE/gen_circuits.py"
dune build ./test/simulation_external_bench.exe || exit 1
SQB="$ROOT/_build/default/test/simulation_external_bench.exe"

run_one() { # engine case tag command...
  local engine="$1" case="$2" tag="$3" run="$4"; shift 4
  local out="$RES/raw/$engine/${case}__${tag}__run${run}.txt"
  mkdir -p "$RES/raw/$engine"
  local rc=0
  timeout "$TIMEOUT_S" "${PIN[@]}" bash -c "ulimit -v $MEM_KB 2>/dev/null; exec $*" > "$out" 2>&1 || rc=$?
  local st=ok
  [ "$rc" -eq 124 ] && st=timeout
  [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && st="error($rc)"
  echo "$engine,$case,$tag,run$run,$st" >> "$RES/statuses.csv"
}

# Smoke test on one tiny circuit: every amplitude-producing adapter must
# emit at least one amp line, otherwise the whole series is not comparable.
smoke_case="ghz_02"
smoke_qasm="$HERE/circuits/${smoke_case}.qasm"
ok=1
"$SQB" "$smoke_qasm" | grep -q "^amp," || { echo "SMOKE FAIL: sqbricks"; ok=0; }
python3 "$HERE/run_qiskit.py" "$smoke_case" "$smoke_qasm" statevector | grep -q "^amp," || { echo "SMOKE FAIL: qiskit statevector"; ok=0; }
python3 "$HERE/run_qiskit.py" "$smoke_case" "$smoke_qasm" matrix_product_state | grep -q "^amp," || { echo "SMOKE FAIL: qiskit mps"; ok=0; }
python3 "$HERE/run_myqlm.py" "$smoke_case" "$smoke_qasm" | grep -q "^amp," || { echo "SMOKE FAIL: myqlm clininalg"; ok=0; }
[ "$ok" -eq 1 ] || { echo "smoke test failed; fix the adapters before the full series"; exit 1; }
echo "smoke test OK"

while IFS=, read -r file clifford; do
  [ "$file" = "file" ] && continue
  case_name="${file%.qasm}"
  qasm="$HERE/circuits/$file"
  echo "== $case_name"
  for run in $(seq 1 "$RUNS"); do
    run_one sqbricks "$case_name" group_exact "$run" "\"$SQB\" $SQB_ARGS \"$qasm\""
    run_one qiskit "$case_name" statevector "$run" "python3 \"$HERE/run_qiskit.py\" \"$case_name\" \"$qasm\" statevector"
    run_one qiskit "$case_name" matrix_product_state "$run" "python3 \"$HERE/run_qiskit.py\" \"$case_name\" \"$qasm\" matrix_product_state"
    if [ "$clifford" = "yes" ]; then
      run_one qiskit "$case_name" stabilizer "$run" "python3 \"$HERE/run_qiskit.py\" \"$case_name\" \"$qasm\" stabilizer"
    fi
    run_one myqlm "$case_name" clininalg "$run" "python3 \"$HERE/run_myqlm.py\" \"$case_name\" \"$qasm\""
  done
done < "$HERE/manifest.csv"

python3 "$HERE/summarize.py" "$RES" > "$RES/summary.csv"
python3 "$HERE/check_agreement.py" "$RES/raw" --tol 1e-9 > "$RES/agreement.txt"
echo "done: see $RES/{versions.txt,statuses.csv,summary.csv,agreement.txt}"
