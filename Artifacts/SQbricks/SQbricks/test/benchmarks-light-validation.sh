#!/usr/bin/env bash

# Validate the light benchmark runner with a deterministic fake SQbricks CLI.
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/benchmarks-light-validation.XXXXXX")" || exit 1
fixture_runs=3
fixture_timeout="120s"
fixture_memory_kb=7340032
failure_count=0
run_status=0
run_output=""
baseline_header="Suite;Case;Kind;Tool;Version;Lift;Opt;ExpectedStatus;ActualStatus;StatusMatch;CH;CS;CZ;CCZ;CCX;CU1;Gates;TimeSeconds;BaselineSeconds;Ratio;PerfStatus;Raw"
valid_baseline_time="1.000000"
valid_baseline_raw="rounds=3 status=EQ times=[1.000000,1.000000,1.000000] median=1.000000"

cleanup() {
	rm -rf "$work_dir"
}
trap cleanup EXIT

# Build a minimal temporary repository around the real benchmark runner. The
# fake `dune` below makes the tests deterministic and records SQV invocations.
new_fixture() {
	local fixture

	fixture="$(mktemp -d "$work_dir/fixture.XXXXXX")" || exit 1

	mkdir -p \
		"$fixture/scripts/paths/light" \
		"$fixture/benchmarks" \
		"$fixture/bin"
	cp "$repo_root/scripts/benchmarks-light.sh" "$fixture/scripts/benchmarks-light.sh"
	chmod +x "$fixture/scripts/benchmarks-light.sh"

	cat >"$fixture/scripts/paths/light/pairs.csv" <<'EOF'
Suite;Case;Kind;ExpectedSequence;ExpectedParallel;TrackPerformance;Path1;Path2
perf;case;unit;EQ;-;yes;benchmarks/a.qasm;benchmarks/b.qasm
EOF

	cat >"$fixture/scripts/paths/light/transforms.csv" <<'EOF'
Suite;Case;Kind;ExpectedSequence;ExpectedParallel;TrackPerformance;Path
EOF

	: >"$fixture/benchmarks/a.qasm"
	: >"$fixture/benchmarks/b.qasm"

	cat >"$fixture/bin/dune" <<'EOF'
#!/usr/bin/env bash

set -u

case " $* " in
*" -nb_gates_csv "*)
	# Gate counting is not under test here; return a stable CSV fragment.
	printf '0;0;0;0;0;0;1\n'
	;;
*" -sqv "*)
	# Each SQV call consumes one configured fake output and increments a counter.
	count=0
	if [[ -f "$FAKE_COUNTER" ]]; then
		read -r count <"$FAKE_COUNTER"
	fi
	count=$((count + 1))
	printf '%s\n' "$count" >"$FAKE_COUNTER"

	IFS=',' read -r -a outputs <<<"${FAKE_SQV_OUTPUTS:-1.0,1.0,1.0}"
	output="${outputs[$((count - 1))]-EQ}"
	if [[ "$output" == "__EMPTY__" ]]; then
		output=""
	fi
	printf '%s\n' "$output"
	;;
*)
	printf 'Unexpected fake dune invocation: %s\n' "$*" >&2
	exit 99
	;;
esac
EOF
	chmod +x "$fixture/bin/dune"

	printf '%s' "$fixture"
}

# Baseline helpers write only the one synthetic row used by the fixture.
write_baseline_header() {
	local path="$1"

	printf '%s\n' "$baseline_header" >"$path"
}

write_baseline_row() {
	local path="$1"
	local time="$2"
	local raw="$3"
	local expected="${4:-EQ}"

	printf 'perf;case;unit;SQbricks;2025;standalone;Sequence;%s;%s;OK;0;0;0;0;0;0;1;%s;;;NA;%s\n' \
		"$expected" "$expected" "$time" "$raw" >>"$path"
}

write_valid_baseline() {
	local fixture="$1"
	local path="$2"
	local expected
	local raw

	IFS=';' read -r _ _ _ expected _ _ _ _ < <(
		sed -n '2p' "$fixture/scripts/paths/light/pairs.csv"
	)
	raw="${valid_baseline_raw/status=EQ/status=$expected}"
	write_baseline_header "$path" &&
		write_baseline_row "$path" "$valid_baseline_time" "$raw" "$expected"
}

# Run the real script from inside the fixture. PATH is scoped to this command
# substitution, so only this execution sees the fake `dune` first.
run_fixture_command() {
	local fixture="$1"
	local outputs="$2"
	shift 2

	if run_output="$(
		cd "$fixture" &&
			PATH="$fixture/bin:$PATH" \
				FAKE_COUNTER="$fixture/sqv-count" \
				FAKE_SQV_OUTPUTS="$outputs" \
				SQBRICKS_LIGHT_RUNS="$fixture_runs" \
				SQBRICKS_LIGHT_TIMEOUT="${TEST_LIGHT_TIMEOUT:-$fixture_timeout}" \
				SQBRICKS_LIGHT_MEMORY_KB="$fixture_memory_kb" \
				SQBRICKS_LIGHT_PROGRESS=never \
				./scripts/benchmarks-light.sh "$@" 2>&1
	)"; then
		run_status=0
	else
		run_status=$?
	fi
}

# Convenience wrappers for the two public modes validated here.
run_check() {
	local fixture="$1"
	local outputs="$2"
	shift 2

	run_fixture_command "$fixture" "$outputs" --check --quiet "$@"
}

run_baseline() {
	local fixture="$1"
	local outputs="$2"
	local baseline="$3"

	run_fixture_command "$fixture" "$outputs" --save-baseline "$baseline" --quiet
}

# Assertion helpers keep individual tests focused on the contract being checked.
assert_failed_with() {
	local expected="$1"

	if [[ "$run_status" -eq 0 ]]; then
		printf 'expected failure, got success\n'
		printf '%s\n' "$run_output"
		return 1
	fi
	if [[ "$run_output" != *"$expected"* ]]; then
		printf 'missing diagnostic: %s\n' "$expected"
		printf '%s\n' "$run_output"
		return 1
	fi
	return 0
}

assert_succeeded_with() {
	local expected="$1"

	if [[ "$run_status" -ne 0 ]]; then
		printf 'expected success, got exit %d\n' "$run_status"
		printf '%s\n' "$run_output"
		return 1
	fi
	if [[ "$run_output" != *"$expected"* ]]; then
		printf 'missing success message: %s\n' "$expected"
		printf '%s\n' "$run_output"
		return 1
	fi
	return 0
}

assert_no_sqv_run() {
	local fixture="$1"

	if [[ -f "$fixture/sqv-count" ]]; then
		printf 'SQbricks verification ran before validation failed\n'
		return 1
	fi
	return 0
}

assert_sqv_runs() {
	local fixture="$1"
	local expected="$2"
	local actual=0

	if [[ -f "$fixture/sqv-count" ]]; then
		read -r actual <"$fixture/sqv-count"
	fi
	if [[ "$actual" -ne "$expected" ]]; then
		printf 'expected %d SQbricks runs, got %d\n' "$expected" "$actual"
		return 1
	fi
	return 0
}

assert_file_content() {
	local path="$1"
	local expected="$2"
	local actual

	if [[ ! -f "$path" ]]; then
		printf 'missing file: %s\n' "$path"
		return 1
	fi
	actual="$(<"$path")"
	if [[ "$actual" != "$expected" ]]; then
		printf 'unexpected content in %s\n' "$path"
		printf 'expected: %s\n' "$expected"
		printf 'actual: %s\n' "$actual"
		return 1
	fi
	return 0
}

# Check-mode preflight failures must happen before any SQV invocation.
test_check_requires_baseline() {
	local fixture

	fixture="$(new_fixture)"
	run_check "$fixture" "1.0,1.0,1.0"

	assert_failed_with "--check requires --baseline" &&
		assert_no_sqv_run "$fixture"
}

test_check_rejects_stable_output() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "1.0,1.0,1.0" --stable --baseline "$baseline"

	assert_failed_with "--check requires the full output, without --stable" &&
		assert_no_sqv_run "$fixture"
}

test_missing_baseline_key() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with "Missing baseline timing for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_invalid_baseline_time() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	write_baseline_row "$baseline" "0" "$valid_baseline_raw"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with "Invalid baseline timing for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_baseline_sample_count_must_match() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	write_baseline_row "$baseline" "$valid_baseline_time" \
		"rounds=2 status=EQ times=[1.000000,1.000000] median=1.000000"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Baseline sample count mismatch for perf/case unit Sequence: expected 3, got 2" &&
		assert_no_sqv_run "$fixture"
}

# Runtime checks validate status aggregation, timing completeness, and slowdown
# thresholds once the fake SQV command is allowed to run.
test_complete_performance_data_succeeds() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "1.0,1.1,0.9" --baseline "$baseline"

	assert_succeeded_with "Light regression check OK" &&
		assert_sqv_runs "$fixture" 3
}

test_current_timing_samples_must_be_complete() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "1.0,1.1,EQ" --baseline "$baseline"

	assert_failed_with \
		"Incomplete timing samples for perf/case unit Sequence: expected 3, got 2" &&
		assert_sqv_runs "$fixture" 3
}

test_functional_status_mismatch_fails() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "NE,NE,NE" --baseline "$baseline"

	assert_failed_with "perf/case unit Sequence: expected EQ, got NE" &&
		assert_sqv_runs "$fixture" 3
}

test_unknown_success_output_fails_check() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "mystery,mystery,mystery" --baseline "$baseline"

	assert_failed_with \
		"perf/case unit Sequence: expected EQ, got UNEXPECTED_OUTPUT" &&
		assert_sqv_runs "$fixture" 3
}

test_performance_regression_fails() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "1.3,1.3,1.3" --baseline "$baseline"

	assert_failed_with \
		"perf/case unit Sequence: 1.300000s vs 1.000000s baseline, +0.300000s and ratio 1.300000" &&
		assert_sqv_runs "$fixture" 3
}

test_relative_threshold_alone_does_not_fail() {
	local fixture
	local baseline
	local raw="rounds=3 status=EQ times=[0.100000,0.100000,0.100000] median=0.100000"

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	write_baseline_row "$baseline" "0.100000" "$raw"
	run_check "$fixture" "0.13,0.13,0.13" --baseline "$baseline"

	assert_succeeded_with "Light regression check OK" &&
		assert_sqv_runs "$fixture" 3
}

test_absolute_threshold_alone_does_not_fail() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "1.2,1.2,1.2" --baseline "$baseline"

	assert_succeeded_with "Light regression check OK" &&
		assert_sqv_runs "$fixture" 3
}

# Baseline publication must be atomic from the user's point of view: invalid
# results preserve the existing file, valid results replace it.
test_invalid_status_does_not_replace_baseline() {
	local fixture
	local baseline
	local marker="existing baseline"

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	printf '%s\n' "$marker" >"$baseline"
	run_baseline "$fixture" "NE,NE,NE" "$baseline"

	assert_failed_with \
		"Light regression baseline FAILED: 1 status mismatch(es), 1 performance data error(s)." &&
		assert_file_content "$baseline" "$marker"
}

test_valid_baseline_replaces_existing_file() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	printf 'existing baseline\n' >"$baseline"
	run_baseline "$fixture" "1.0,1.1,0.9" "$baseline"

	if [[ "$run_status" -ne 0 ]]; then
		printf 'expected success, got exit %d\n' "$run_status"
		printf '%s\n' "$run_output"
		return 1
	fi
	if ! grep -q '^Suite;Case;Kind;Tool;' "$baseline"; then
		printf 'valid baseline header is missing\n'
		return 1
	fi
	if ! grep -q '^perf;case;unit;SQbricks;2025;standalone;Sequence;EQ;EQ;OK;' "$baseline"; then
		printf 'valid baseline row is missing\n'
		return 1
	fi
	return 0
}

# Tiny TAP-like runner: each shell function is one independent scenario.
run_test() {
	local name="$1"
	local test_function="$2"

	if "$test_function"; then
		printf 'ok - %s\n' "$name"
	else
		printf 'not ok - %s\n' "$name"
		failure_count=$((failure_count + 1))
	fi
}

run_test "check requires a baseline" test_check_requires_baseline
run_test "check rejects stable output" test_check_rejects_stable_output
run_test "tracked key must exist in baseline" test_missing_baseline_key
run_test "baseline timing must be positive" test_invalid_baseline_time
run_test "baseline sample count must match run count" test_baseline_sample_count_must_match

run_test "complete performance data succeeds" test_complete_performance_data_succeeds
run_test "current timing samples must be complete" test_current_timing_samples_must_be_complete
run_test "functional status mismatch fails" test_functional_status_mismatch_fails
run_test "unknown successful output fails check" test_unknown_success_output_fails_check
run_test "performance regression fails" test_performance_regression_fails
run_test "relative threshold alone does not fail" test_relative_threshold_alone_does_not_fail
run_test "absolute threshold alone does not fail" test_absolute_threshold_alone_does_not_fail

run_test "invalid status preserves existing baseline" test_invalid_status_does_not_replace_baseline
run_test "valid baseline replaces existing file" test_valid_baseline_replaces_existing_file

if [[ "$failure_count" -ne 0 ]]; then
	printf '%d test(s) failed\n' "$failure_count"
	exit 1
fi

printf 'All benchmark light validation tests passed\n'
