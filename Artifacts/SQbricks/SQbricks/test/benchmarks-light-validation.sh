#!/usr/bin/env bash

# Validate the benchmark runner itself with a deterministic fake SQbricks CLI.
# No real quantum verification is needed for these control-flow scenarios.
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
baseline_header="Suite;Case;Kind;Tool;Version;Lift;Opt;ExpectedStatus;ActualStatus;StatusMatch;CH;CS;CZ;CCZ;CCX;CU1;Gates;TimeSeconds;BaselineSeconds;Ratio;PerfStatus;Raw;DefinitionHash"
valid_baseline_time="1.000000"
valid_baseline_raw="rounds=3 status=EQ times=[1.000000,1.000000,1.000000] median=1.000000"
placeholder_hash="0000000000000000000000000000000000000000000000000000000000000000"

# Remove all isolated fixtures created by this validation script.
cleanup() {
	rm -rf "$work_dir"
}
trap cleanup EXIT

# Create the smallest repository layout understood by benchmarks-light.sh.
# The fake dune executable returns deterministic gate counts and SQV outputs.
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
	printf '0;0;0;0;0;0;1\n'
	;;
*" -sqv "*)
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

# Start a synthetic full baseline CSV.
write_baseline_header() {
	local path="$1"

	printf '%s\n' "$baseline_header" >"$path"
}

# Reproduce the production definition hash for the fixture's single case.
# Keeping this calculation in the test lets it detect accidental format changes.
fixture_definition_hash() {
	local fixture="$1"
	local suite
	local case_name
	local kind
	local expected_seq
	local expected_par
	local track_performance
	local path1
	local path2
	local path1_hash
	local path2_hash
	local digest

	IFS=';' read -r suite case_name kind expected_seq expected_par track_performance path1 path2 < <(
		sed -n '2p' "$fixture/scripts/paths/light/pairs.csv"
	)
	path1_hash="$(sha256sum -- "$fixture/$path1")"
	path1_hash="${path1_hash%% *}"
	path2_hash="$(sha256sum -- "$fixture/$path2")"
	path2_hash="${path2_hash%% *}"
	digest="$(
		printf '%s\n' \
			"schema=1" \
			"source=pair" \
			"suite=$suite" \
			"case=$case_name" \
			"kind=$kind" \
			"opt=Sequence" \
			"expected=$expected_seq" \
			"track_performance=$track_performance" \
			"path1=$path1" \
			"path1_sha256=$path1_hash" \
			"path2=$path2" \
			"path2_sha256=$path2_hash" \
			"runs=$fixture_runs" \
			"timeout=$fixture_timeout" \
			"memory_kb=$fixture_memory_kb" |
			sha256sum
	)"
	printf "%s" "${digest%% *}"
}

# Append the fixture's tracked Sequence row to a synthetic baseline.
write_baseline_row() {
	local fixture="$1"
	local path="$2"
	local time="$3"
	local raw="$4"
	local definition_hash="${5-$(fixture_definition_hash "$fixture")}"
	local expected="${6:-EQ}"

	printf 'perf;case;unit;SQbricks;2025;standalone;Sequence;%s;%s;OK;0;0;0;0;0;0;1;%s;;;NA;%s;%s\n' \
		"$expected" "$expected" "$time" "$raw" "$definition_hash" >>"$path"
}

# Append an unrelated row used only by coverage tests.
write_untracked_baseline_row() {
	local path="$1"
	local suite="$2"
	local case_name="$3"
	local kind="$4"
	local opt="$5"

	printf '%s;%s;%s;SQbricks;2025;standalone;%s;NC;NC;OK;0;0;0;0;0;0;1;;;;NOT_TRACKED;rounds=3 status=NC times=[] median=NA;%s\n' \
		"$suite" "$case_name" "$kind" "$opt" "$placeholder_hash" >>"$path"
}

# Write a complete valid baseline matching the fixture's current manifest.
write_valid_baseline() {
	local fixture="$1"
	local path="$2"
	local expected
	local definition_hash
	local raw

	IFS=';' read -r _ _ _ expected _ _ _ _ < <(
		sed -n '2p' "$fixture/scripts/paths/light/pairs.csv"
	)
	definition_hash="$(fixture_definition_hash "$fixture")"
	raw="${valid_baseline_raw/status=EQ/status=$expected}"
	write_baseline_header "$path"
	write_baseline_row "$fixture" "$path" "$valid_baseline_time" "$raw" \
		"$definition_hash" "$expected"
}

# Run the real shell runner inside a fixture and capture its combined output.
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

# Invoke check mode with a synthetic baseline supplied by the test.
run_check() {
	local fixture="$1"
	local outputs="$2"
	shift 2

	run_fixture_command "$fixture" "$outputs" --check --quiet "$@"
}

# Invoke baseline generation while preserving the previous file on failure.
run_baseline() {
	local fixture="$1"
	local outputs="$2"
	local baseline="$3"

	run_fixture_command "$fixture" "$outputs" --save-baseline "$baseline" --quiet
}

# Assertions print their own diagnostics so each test function stays compact.
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
}

# Preflight failures must occur before the fake SQV command is reached.
assert_no_sqv_run() {
	local fixture="$1"

	if [[ -f "$fixture/sqv-count" ]]; then
		printf 'SQbricks verification ran before validation failed\n'
		return 1
	fi
}

# Runtime validations also verify that every configured round was executed.
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
}

# Baseline-write tests use a marker to prove that failures preserve old data.
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
}

# Baseline preflight validation: all of these failures must happen before SQV.
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

test_unknown_suite_fails() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "1.0,1.0,1.0" --suite missing --baseline "$baseline"

	assert_failed_with "No benchmark verification found for suite: missing" &&
		assert_no_sqv_run "$fixture"
}

test_duplicate_manifest_key_fails() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	sed -n '2p' "$fixture/scripts/paths/light/pairs.csv" >> \
		"$fixture/scripts/paths/light/pairs.csv"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with "Duplicate benchmark verification: perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_duplicate_baseline_key_fails() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	sed -n '2p' "$baseline" >>"$baseline"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with "Duplicate baseline verification: perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_missing_definition_hash() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	write_baseline_row "$fixture" "$baseline" "$valid_baseline_time" \
		"$valid_baseline_raw" ""
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Missing benchmark definition hash for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_changed_input_content() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	printf 'changed circuit\n' >"$fixture/benchmarks/a.qasm"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Benchmark definition changed for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_changed_manifest_path() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	cp "$fixture/benchmarks/a.qasm" "$fixture/benchmarks/c.qasm"
	sed -i 's|benchmarks/a.qasm|benchmarks/c.qasm|' \
		"$fixture/scripts/paths/light/pairs.csv"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Benchmark definition changed for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_changed_execution_configuration() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	TEST_LIGHT_TIMEOUT=121s \
		run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Benchmark definition changed for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_invalid_baseline_time() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	write_baseline_row "$fixture" "$baseline" "not-a-number" \
		"$valid_baseline_raw"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with "Invalid baseline timing for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_zero_baseline_time() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	write_baseline_row "$fixture" "$baseline" "0" "$valid_baseline_raw"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with "Invalid baseline timing for perf/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_baseline_round_count_must_match() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_baseline_header "$baseline"
	write_baseline_row "$fixture" "$baseline" "$valid_baseline_time" \
		"rounds=2 status=EQ times=[1.000000,1.000000] median=1.000000"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Baseline sample count mismatch for perf/case unit Sequence: expected 3, got 2" &&
		assert_no_sqv_run "$fixture"
}

# Runtime validation: these cases exercise aggregation across all three rounds.
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
	write_baseline_row "$fixture" "$baseline" "0.100000" "$raw"
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

test_empty_success_output_fails_check() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	sed -i 's/;EQ;-;yes;/;NC;-;yes;/' "$fixture/scripts/paths/light/pairs.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "__EMPTY__,__EMPTY__,__EMPTY__" --baseline "$baseline"

	assert_failed_with \
		"perf/case unit Sequence: expected NC, got UNEXPECTED_OUTPUT" &&
		assert_sqv_runs "$fixture" 3
}

test_unexpected_output_cannot_be_expected() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	sed -i 's/;EQ;-;yes;/;UNEXPECTED_OUTPUT;-;yes;/' "$fixture/scripts/paths/light/pairs.csv"
	write_valid_baseline "$fixture" "$baseline"
	run_check "$fixture" "mystery,mystery,mystery" --baseline "$baseline"

	assert_failed_with \
		"perf/case unit Sequence: expected UNEXPECTED_OUTPUT, got UNEXPECTED_OUTPUT" &&
		assert_sqv_runs "$fixture" 3
}

# Coverage validation compares the selected manifest keys with baseline keys.
test_removed_manifest_case_fails() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	write_untracked_baseline_row "$baseline" "removed" "case" "unit" "Sequence"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Baseline contains removed benchmark verification: removed/case unit Sequence" &&
		assert_no_sqv_run "$fixture"
}

test_removed_manifest_mode_fails() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	write_untracked_baseline_row "$baseline" "perf" "case" "unit" "Parallel"
	run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"

	assert_failed_with \
		"Baseline contains removed benchmark verification: perf/case unit Parallel" &&
		assert_no_sqv_run "$fixture"
}

test_suite_filter_ignores_other_baseline_suites() {
	local fixture
	local baseline

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	write_valid_baseline "$fixture" "$baseline"
	write_untracked_baseline_row "$baseline" "other" "case" "unit" "Sequence"
	run_check "$fixture" "1.0,1.0,1.0" --suite perf --baseline "$baseline"

	assert_succeeded_with "Light regression check OK" &&
		assert_sqv_runs "$fixture" 3
}

# Baseline publication: invalid runs and write errors must preserve the old file.
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

test_flaky_status_does_not_replace_baseline() {
	local fixture
	local baseline
	local marker="existing baseline"

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	printf '%s\n' "$marker" >"$baseline"
	run_baseline "$fixture" "1.0,NE,1.0" "$baseline"

	assert_failed_with \
		"perf/case unit Sequence: expected EQ, got FLAKY" &&
		assert_file_content "$baseline" "$marker"
}

test_unknown_success_output_does_not_replace_baseline() {
	local fixture
	local baseline
	local marker="existing baseline"

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	printf '%s\n' "$marker" >"$baseline"
	run_baseline "$fixture" "mystery,mystery,mystery" "$baseline"

	assert_failed_with \
		"perf/case unit Sequence: expected EQ, got UNEXPECTED_OUTPUT" &&
		assert_file_content "$baseline" "$marker"
}

test_incomplete_timings_do_not_replace_baseline() {
	local fixture
	local baseline
	local marker="existing baseline"

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	printf '%s\n' "$marker" >"$baseline"
	run_baseline "$fixture" "1.0,1.1,EQ" "$baseline"

	assert_failed_with \
		"Incomplete timing samples for perf/case unit Sequence: expected 3, got 2" &&
		assert_file_content "$baseline" "$marker"
}

test_atomic_write_failure_preserves_baseline() {
	local fixture
	local baseline
	local marker="existing baseline"

	fixture="$(new_fixture)"
	baseline="$fixture/baseline.csv"
	printf '%s\n' "$marker" >"$baseline"
	cat >"$fixture/bin/mv" <<'EOF'
#!/usr/bin/env bash
exit 73
EOF
	chmod +x "$fixture/bin/mv"
	run_baseline "$fixture" "1.0,1.1,0.9" "$baseline"

	assert_failed_with "Failed to write baseline atomically: $baseline" &&
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
		printf 'valid baseline did not replace existing file\n'
		return 1
	fi
	if ! grep -q '^perf;case;unit;SQbricks;2025;standalone;Sequence;EQ;EQ;OK;' "$baseline"; then
		printf 'valid baseline row is missing\n'
		return 1
	fi
	if ! grep -Eq ';[[:xdigit:]]{64}$' "$baseline"; then
		printf 'valid baseline definition hash is missing\n'
		return 1
	fi
}

# Execute one named shell test without stopping the remaining scenarios.
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
run_test "unknown suite fails" test_unknown_suite_fails
run_test "duplicate manifest key fails" test_duplicate_manifest_key_fails
run_test "duplicate baseline key fails" test_duplicate_baseline_key_fails
run_test "baseline must contain a definition hash" test_missing_definition_hash
run_test "changed input content invalidates baseline" test_changed_input_content
run_test "changed manifest path invalidates baseline" test_changed_manifest_path
run_test "changed execution configuration invalidates baseline" test_changed_execution_configuration
run_test "baseline timing must be numeric" test_invalid_baseline_time
run_test "baseline timing must be positive" test_zero_baseline_time
run_test "baseline sample count must match run count" test_baseline_round_count_must_match
run_test "current timing samples must be complete" test_current_timing_samples_must_be_complete
run_test "complete performance data succeeds" test_complete_performance_data_succeeds
run_test "performance regression fails" test_performance_regression_fails
run_test "relative threshold alone does not fail" test_relative_threshold_alone_does_not_fail
run_test "absolute threshold alone does not fail" test_absolute_threshold_alone_does_not_fail
run_test "unknown successful output fails check" test_unknown_success_output_fails_check
run_test "empty successful output fails check" test_empty_success_output_fails_check
run_test "unexpected output cannot be expected" test_unexpected_output_cannot_be_expected
run_test "removed manifest case fails" test_removed_manifest_case_fails
run_test "removed manifest mode fails" test_removed_manifest_mode_fails
run_test "suite filter ignores other baseline suites" test_suite_filter_ignores_other_baseline_suites
run_test "invalid status preserves existing baseline" test_invalid_status_does_not_replace_baseline
run_test "flaky status preserves existing baseline" test_flaky_status_does_not_replace_baseline
run_test "unknown successful output preserves existing baseline" test_unknown_success_output_does_not_replace_baseline
run_test "incomplete timings preserve existing baseline" test_incomplete_timings_do_not_replace_baseline
run_test "atomic write failure preserves existing baseline" test_atomic_write_failure_preserves_baseline
run_test "valid baseline replaces existing file" test_valid_baseline_replaces_existing_file

if [[ "$failure_count" -ne 0 ]]; then
	printf '%d test(s) failed\n' "$failure_count"
	exit 1
fi

printf 'All benchmark light validation tests passed\n'
