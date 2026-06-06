#!/usr/bin/env bash

# This file is part of SQbricks.
#
# Copyright (C) 2022-2026
# CEA (Commissariat a l'energie atomique et aux energies alternatives)
# Universite Paris-Saclay
#
# You can redistribute it and/or modify it under the terms of the GNU
# Lesser General Public License as published by the Free Software
# Foundation, version 2.1.
#
# It is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Lesser General Public License for more details.
#
# See the GNU Lesser General Public License version 2.1
# for more details (enclosed in the file licenses/LGPLv2.1).

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root" || exit 1

export DUNE_BUILD_DIR="${DUNE_BUILD_DIR:-$(pwd)/_build/light}"

manifest_dir="scripts/paths/light"
pairs_file="$manifest_dir/pairs.csv"
transforms_file="$manifest_dir/transforms.csv"
tmp_dir="_tmp/light"

timeout_s="${SQBRICKS_LIGHT_TIMEOUT:-120s}"
memory_kb="${SQBRICKS_LIGHT_MEMORY_KB:-7340032}"
perf_threshold="${SQBRICKS_LIGHT_PERF_THRESHOLD:-1.25}"
min_perf_seconds="${SQBRICKS_LIGHT_MIN_PERF_SECONDS:-0.01}"
min_slowdown_seconds="${SQBRICKS_LIGHT_MIN_SLOWDOWN_SECONDS:-0.05}"
run_count="${SQBRICKS_LIGHT_RUNS:-5}"

suite_filter=""
output=""
baseline=""
save_baseline=""
stable_mode="false"
check_mode="false"
quiet_mode="false"
status_failed=0
perf_failed=0
row_count=0
status_failure_count=0
perf_failure_count=0

declare -A baseline_times
declare -a status_failure_messages
declare -a perf_failure_messages
declare -a row_keys
declare -A row_seen
declare -A row_suite
declare -A row_case
declare -A row_kind
declare -A row_lift
declare -A row_opt
declare -A row_expected
declare -A row_gates
declare -A row_statuses
declare -A row_times
declare -A row_raws
current_round=0

usage() {
	cat <<'USAGE'
Usage:
  ./scripts/benchmarks-light.sh [options]

Options:
  --suite NAME          Run only one suite from the light manifests.
  --output PATH         Also write the CSV result to PATH.
  --baseline PATH       Compare timings with a previous full light CSV result.
  --save-baseline PATH  Save the current full light CSV result for later use.
  --stable              Print only stable status columns, without timings.
  --check               Exit non-zero on status mismatch or performance slowdown.
  --quiet               Do not print the detailed CSV result to the terminal.
  -h, --help            Show this help.

Environment:
  SQBRICKS_LIGHT_TIMEOUT=120s
  SQBRICKS_LIGHT_MEMORY_KB=7340032
  SQBRICKS_LIGHT_PERF_THRESHOLD=1.25
  SQBRICKS_LIGHT_MIN_PERF_SECONDS=0.01
  SQBRICKS_LIGHT_MIN_SLOWDOWN_SECONDS=0.05
  SQBRICKS_LIGHT_RUNS=5
USAGE
}

require_value() {
	local option="$1"
	local value="${2:-}"

	if [[ -z "$value" || "$value" == -* ]]; then
		echo "Missing value after $option" >&2
		exit 1
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--suite)
		require_value "$1" "${2:-}"
		suite_filter="$2"
		shift
		;;
	--output)
		require_value "$1" "${2:-}"
		output="$2"
		shift
		;;
	--baseline)
		require_value "$1" "${2:-}"
		baseline="$2"
		shift
		;;
	--save-baseline)
		require_value "$1" "${2:-}"
		save_baseline="$2"
		shift
		;;
	--stable)
		stable_mode="true"
		;;
	--check)
		check_mode="true"
		;;
	--quiet)
		quiet_mode="true"
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	esac
	shift
done

if [[ "$stable_mode" == "true" && -n "$save_baseline" ]]; then
	echo "--save-baseline requires the full output, without --stable" >&2
	exit 1
fi

if [[ ! "$run_count" =~ ^[1-9][0-9]*$ ]]; then
	echo "SQBRICKS_LIGHT_RUNS must be a positive integer." >&2
	exit 1
fi

if [[ ! -f "$pairs_file" ]]; then
	echo "Missing manifest: $pairs_file" >&2
	exit 1
fi

if [[ ! -f "$transforms_file" ]]; then
	echo "Missing manifest: $transforms_file" >&2
	exit 1
fi

mkdir -p "$tmp_dir"

trim() {
	local value="$1"
	value="${value//$'\r'/}"
	printf "%s" "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

clean_csv() {
	printf "%s" "$1" | tr '\n' ' ' | sed 's/;/,/g;s/[[:space:]][[:space:]]*/ /g;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

is_number() {
	[[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

normalize_number() {
	local value
	value="$(trim "$1")"
	value="${value/,/.}"
	printf "%s" "$value"
}

median_numbers() {
	printf "%s\n" "$@" | sort -n | awk '
		{ values[NR] = $1 }
		END {
			if (NR == 0) {
				exit 1
			}
			if (NR % 2 == 1) {
				printf "%.6f", values[int((NR + 1) / 2)]
			} else {
				printf "%.6f", (values[NR / 2] + values[(NR / 2) + 1]) / 2
			}
		}'
}

list_or_empty() {
	local value
	value="$(trim "$1")"
	if [[ -z "$value" ]]; then
		printf "[]"
	else
		printf "%s" "$value"
	fi
}

safe_name() {
	printf "%s" "$1" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

combined_raw() {
	local stdout="$1"
	local stderr="$2"

	if [[ -n "$stdout" && -n "$stderr" ]]; then
		printf "%s %s" "$stdout" "$stderr"
	else
		printf "%s%s" "$stdout" "$stderr"
	fi
}

run_with_limits() {
	if [[ -n "$memory_kb" && "$memory_kb" != "0" ]]; then
		(
			ulimit -v "$memory_kb" 2>/dev/null || true
			timeout "$timeout_s" "$@"
		)
	else
		timeout "$timeout_s" "$@"
	fi
}

run_command() {
	local stdout_file
	local stderr_file

	stdout_file="$(mktemp "$tmp_dir/stdout.XXXXXX")" || exit 1
	stderr_file="$(mktemp "$tmp_dir/stderr.XXXXXX")" || exit 1

	if run_with_limits "$@" >"$stdout_file" 2>"$stderr_file"; then
		cmd_code=0
	else
		cmd_code=$?
	fi

	cmd_stdout="$(<"$stdout_file")"
	cmd_stderr="$(<"$stderr_file")"
	rm -f "$stdout_file" "$stderr_file"

	return "$cmd_code"
}

normalize_success() {
	local raw
	raw="$(trim "$1")"

	if [[ "$raw" =~ ^[0-9]+([,.][0-9]+)?$ ]]; then
		printf "EQ"
	elif [[ "$raw" == "NE" || "$raw" == *NotEquiv* || "$raw" == *"Not equivalent"* ]]; then
		printf "NE"
	elif [[ "$raw" == "NC" || "$raw" == *Inconclusive* || "$raw" == *Entanglement* ]]; then
		printf "NC"
	elif [[ "$raw" == "EQ" || "$raw" == *Equivalent* ]]; then
		printf "EQ"
	else
		printf "NC"
	fi
}

normalize_failure() {
	local code="$1"
	local raw="$2"

	if [[ "$code" -eq 124 ]]; then
		printf "TIMEOUT"
	elif [[ "$raw" == *"one of the two circuits mustn't have init"* ]]; then
		printf "NC"
	elif [[ "$raw" == *OutOfMemory* || "$raw" == *"allocation failure"* || "$code" -eq 137 ]]; then
		printf "OOM"
	elif [[ "$raw" == *MenhirBasics.Error* || "$raw" == *Parser_OpenQASM* || "$raw" == *parse* || "$raw" == *Parse* || "$raw" == *lexer* || "$raw" == *syntax* || "$raw" == *Syntax* ]]; then
		printf "PARSE_ERROR"
	else
		printf "CRASH"
	fi
}

time_from_stdout() {
	local value
	value="$(normalize_number "$1")"

	if is_number "$value"; then
		printf "%s" "$value"
	fi
}

load_baseline() {
	local suite
	local case_name
	local kind
	local tool
	local version
	local lift
	local opt
	local expected
	local actual
	local match
	local ch
	local cs
	local cz
	local ccz
	local ccx
	local cu1
	local gates
	local time
	local rest

	if [[ -z "$baseline" ]]; then
		return
	fi

	if [[ ! -f "$baseline" ]]; then
		echo "Missing baseline: $baseline" >&2
		exit 1
	fi

	while IFS=';' read -r suite case_name kind tool version lift opt expected actual match ch cs cz ccz ccx cu1 gates time rest || [[ -n "$suite" ]]; do
		if [[ "$suite" == "Suite" || -z "$(trim "$suite")" ]]; then
			continue
		fi

		time="$(normalize_number "$time")"
		if is_number "$time"; then
			baseline_times["$suite|$case_name|$kind|$opt"]="$time"
		fi
	done <"$baseline"
}

perf_info() {
	local key="$1"
	local actual_time="$2"

	baseline_seconds="${baseline_times[$key]:-}"
	ratio=""
	slowdown_seconds=""
	perf_status="NA"

	if is_number "$actual_time" && is_number "$baseline_seconds" && [[ "$baseline_seconds" != "0" && "$baseline_seconds" != "0.0" ]]; then
		if awk -v actual="$actual_time" -v base="$baseline_seconds" -v min="$min_perf_seconds" \
			'BEGIN { exit !(actual < min && base < min) }'; then
			perf_status="TOO_FAST"
			return
		fi
		ratio="$(awk -v actual="$actual_time" -v base="$baseline_seconds" 'BEGIN { printf "%.6f", actual / base }')"
		slowdown_seconds="$(awk -v actual="$actual_time" -v base="$baseline_seconds" 'BEGIN { printf "%.6f", actual - base }')"
		perf_status="$(awk \
			-v ratio="$ratio" \
			-v threshold="$perf_threshold" \
			-v slowdown="$slowdown_seconds" \
			-v min_slowdown="$min_slowdown_seconds" \
			'BEGIN {
				if (ratio > threshold && slowdown > min_slowdown) print "SLOWER";
				else if (ratio < 1 / threshold) print "FASTER";
				else print "OK"
			}')"
	fi
}

emit_header() {
	if [[ "$stable_mode" == "true" ]]; then
		echo "Suite;Case;Kind;Opt;ExpectedStatus;ActualStatus;StatusMatch"
	else
		echo "Suite;Case;Kind;Tool;Version;Lift;Opt;ExpectedStatus;ActualStatus;StatusMatch;CH;CS;CZ;CCZ;CCX;CU1;Gates;TimeSeconds;BaselineSeconds;Ratio;PerfStatus;Raw"
	fi
}

emit_row() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local lift="$4"
	local opt="$5"
	local expected="$6"
	local actual="$7"
	local gate_counts="$8"
	local time_seconds="$9"
	local raw="${10}"
	local key="$suite|$case_name|$kind|$opt"

	if [[ -z "${row_seen[$key]:-}" ]]; then
		row_seen["$key"]="true"
		row_keys+=("$key")
		row_suite["$key"]="$suite"
		row_case["$key"]="$case_name"
		row_kind["$key"]="$kind"
		row_lift["$key"]="$lift"
		row_opt["$key"]="$opt"
		row_expected["$key"]="$expected"
		row_gates["$key"]="$gate_counts"
		row_statuses["$key"]=""
		row_times["$key"]=""
		row_raws["$key"]=""
	fi

	if [[ -n "${row_statuses[$key]}" ]]; then
		row_statuses["$key"]+=","
	fi
	row_statuses["$key"]+="$actual"

	if [[ -n "$time_seconds" ]]; then
		if [[ -n "${row_times[$key]}" ]]; then
			row_times["$key"]+=","
		fi
		row_times["$key"]+="$time_seconds"
	fi

	if [[ -n "${row_raws[$key]}" ]]; then
		row_raws["$key"]+=" | "
	fi
	row_raws["$key"]+="round${current_round}:status=${actual},time=${time_seconds:-NA},raw=$(clean_csv "$raw")"
}

emit_final_row() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local lift="$4"
	local opt="$5"
	local expected="$6"
	local actual="$7"
	local gate_counts="$8"
	local time_seconds="$9"
	local raw="${10}"
	local match="OK"
	local key
	local raw_clean

	row_count=$((row_count + 1))

	if [[ "$expected" != "$actual" ]]; then
		match="FAIL"
		status_failed=1
		status_failure_count=$((status_failure_count + 1))
		status_failure_messages+=("$suite/$case_name $kind $opt: expected $expected, got $actual")
	fi

	if [[ "$stable_mode" == "true" ]]; then
		printf "%s;%s;%s;%s;%s;%s;%s\n" \
			"$suite" "$case_name" "$kind" "$opt" "$expected" "$actual" "$match"
		return
	fi

	key="$suite|$case_name|$kind|$opt"
	perf_info "$key" "$time_seconds"
	if [[ "$perf_status" == "SLOWER" ]]; then
		perf_failed=1
		perf_failure_count=$((perf_failure_count + 1))
		perf_failure_messages+=("$suite/$case_name $kind $opt: ${time_seconds}s vs ${baseline_seconds}s baseline, +${slowdown_seconds}s and ratio $ratio")
	fi

	raw_clean="$(clean_csv "$raw")"
	printf "%s;%s;%s;SQbricks;2025;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s\n" \
		"$suite" "$case_name" "$kind" "$lift" "$opt" "$expected" "$actual" "$match" \
		"$gate_counts" "$time_seconds" "$baseline_seconds" "$ratio" "$perf_status" "$raw_clean"
}

emit_results() {
	local key
	local actual
	local time_seconds
	local raw
	local status
	local statuses=()
	local times=()

	emit_header

	for key in "${row_keys[@]}"; do
		IFS=',' read -r -a statuses <<<"${row_statuses[$key]}"
		actual="${statuses[0]}"
		for status in "${statuses[@]}"; do
			if [[ "$status" != "$actual" ]]; then
				actual="FLAKY"
				break
			fi
		done

		time_seconds=""
		if [[ "$actual" != "FLAKY" && -n "${row_times[$key]}" ]]; then
			IFS=',' read -r -a times <<<"${row_times[$key]}"
			time_seconds="$(median_numbers "${times[@]}")"
		fi

		if [[ "$actual" == "FLAKY" ]]; then
			raw="rounds=$run_count statuses=[${row_statuses[$key]}] details=[${row_raws[$key]}]"
		else
			raw="rounds=$run_count status=$actual times=[${row_times[$key]}] median=${time_seconds:-NA}"
		fi

		emit_final_row \
			"${row_suite[$key]}" \
			"${row_case[$key]}" \
			"${row_kind[$key]}" \
			"${row_lift[$key]}" \
			"${row_opt[$key]}" \
			"${row_expected[$key]}" \
			"$actual" \
			"${row_gates[$key]}" \
			"$time_seconds" \
			"$raw"
	done
}

emit_failure_modes() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local lift="$4"
	local expected_seq="$5"
	local expected_par="$6"
	local actual="$7"
	local raw="$8"
	local empty_gates=";;;;;;"

	if [[ "$expected_seq" != "-" ]]; then
		emit_row "$suite" "$case_name" "$kind" "$lift" "Sequence" "$expected_seq" "$actual" "$empty_gates" "" "$raw"
	fi

	if [[ "$expected_par" != "-" ]]; then
		emit_row "$suite" "$case_name" "$kind" "$lift" "Parallel" "$expected_par" "$actual" "$empty_gates" "" "$raw"
	fi
}

ensure_input() {
	local path="$1"

	if [[ ! -f "$path" ]]; then
		echo "Missing benchmark input: $path" >&2
		exit 1
	fi
}

convert_to_unitary() {
	local source="$1"
	local target="$2"
	local raw

	if run_command dune exec -- ./bin/main.exe -sql u "$source" "$target"; then
		conversion_stdout="$cmd_stdout"
		return 0
	fi

	raw="$(combined_raw "$cmd_stdout" "$cmd_stderr")"
	failure_status="$(normalize_failure "$cmd_code" "$raw")"
	failure_raw="$raw"
	return 1
}

run_transform() {
	local transform="$1"
	local source="$2"
	local target="$3"
	local raw

	if run_command dune exec -- ./bin/main.exe "-qasm_to_$transform" "$source" "$target" "false"; then
		transform_stdout="$cmd_stdout"
		return 0
	fi

	raw="$(combined_raw "$cmd_stdout" "$cmd_stderr")"
	failure_status="$(normalize_failure "$cmd_code" "$raw")"
	failure_raw="$raw"
	return 1
}

split_transform_lists() {
	local result="$1"

	transform_inputs="$(list_or_empty "${result%%,*}")"
	transform_outputs="$(list_or_empty "${result##*,}")"
}

get_gates() {
	local path1="$1"
	local path2="$2"
	local value

	if run_command dune exec -- ./bin/main.exe -nb_gates_csv "$path1" "$path2"; then
		value="$(trim "$cmd_stdout")"
		if [[ "$value" == *";"* ]]; then
			printf "%s" "$value"
			return
		fi
	fi

	printf ";;;;;;"
}

run_sqv_result() {
	local algo="$1"
	local path1="$2"
	local path2="$3"
	local inputs1="$4"
	local inputs2="$5"
	local outputs1="$6"
	local outputs2="$7"
	local meas1="$8"
	local meas2="$9"
	local raw

	if run_command dune exec -- ./bin/main.exe -sqv "$algo" s \
		"$path1" "$path2" \
		"$inputs1" "$inputs2" "$outputs1" "$outputs2" \
		"$meas1" "$meas2" false; then
		actual_status="$(normalize_success "$cmd_stdout")"
		time_seconds="$(time_from_stdout "$cmd_stdout")"
		raw="$(combined_raw "$cmd_stdout" "$cmd_stderr")"
		raw_text="$raw"
		return
	fi

	raw="$(combined_raw "$cmd_stdout" "$cmd_stderr")"
	actual_status="$(normalize_failure "$cmd_code" "$raw")"
	time_seconds=""
	raw_text="$raw"
}

run_case_modes() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local lift="$4"
	local expected_seq="$5"
	local expected_par="$6"
	local path1="$7"
	local path2="$8"
	local inputs1="$9"
	local inputs2="${10}"
	local outputs1="${11}"
	local outputs2="${12}"
	local meas1="${13}"
	local meas2="${14}"
	local gate_counts

	gate_counts="$(get_gates "$path1" "$path2")"

	if [[ "$expected_seq" != "-" ]]; then
		run_sqv_result seq "$path1" "$path2" "$inputs1" "$inputs2" "$outputs1" "$outputs2" "$meas1" "$meas2"
		emit_row "$suite" "$case_name" "$kind" "$lift" "Sequence" "$expected_seq" "$actual_status" "$gate_counts" "$time_seconds" "$raw_text"
	fi

	if [[ "$expected_par" != "-" ]]; then
		run_sqv_result par "$path1" "$path2" "$inputs1" "$inputs2" "$outputs1" "$outputs2" "$meas1" "$meas2"
		emit_row "$suite" "$case_name" "$kind" "$lift" "Parallel" "$expected_par" "$actual_status" "$gate_counts" "$time_seconds" "$raw_text"
	fi
}

run_pair_case() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local expected_seq="$4"
	local expected_par="$5"
	local path1="$6"
	local path2="$7"
	local case_safe
	local unit1
	local unit2

	ensure_input "$path1"
	ensure_input "$path2"
	case_safe="$(safe_name "$suite-$case_name")"

	case "$kind" in
	unit)
		run_case_modes "$suite" "$case_name" "$kind" "standalone" "$expected_seq" "$expected_par" \
			"$path1" "$path2" "[]" "[]" "[]" "[]" "[]" "[]"
		;;
	lift)
		unit1="$tmp_dir/${case_safe}_1_unitary.qasm"
		unit2="$tmp_dir/${case_safe}_2_unitary.qasm"
		if ! convert_to_unitary "$path1" "$unit1" || ! convert_to_unitary "$path2" "$unit2"; then
			emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
			return
		fi
		run_case_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" \
			"$unit1" "$unit2" "[]" "[]" "[]" "[]" "[]" "[]"
		;;
	*)
		echo "Unknown pair kind: $kind" >&2
		exit 1
		;;
	esac
}

run_transform_case() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local expected_seq="$4"
	local expected_par="$5"
	local path="$6"
	local case_safe
	local original_unitary
	local transformed
	local transformed_unitary
	local inputs
	local outputs
	local meas

	ensure_input "$path"
	case_safe="$(safe_name "$suite-$case_name")"
	original_unitary="$tmp_dir/${case_safe}_original_unitary.qasm"
	transformed="$tmp_dir/${case_safe}_${kind}.qasm"
	transformed_unitary="$tmp_dir/${case_safe}_${kind}_unitary.qasm"

	if ! convert_to_unitary "$path" "$original_unitary"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi

	if ! run_transform "$kind" "$original_unitary" "$transformed"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi
	split_transform_lists "$transform_stdout"
	inputs="$transform_inputs"
	outputs="$transform_outputs"

	if ! convert_to_unitary "$transformed" "$transformed_unitary"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi
	meas="$(list_or_empty "$conversion_stdout")"

	run_case_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" \
		"$transformed_unitary" "$original_unitary" "$inputs" "[]" "$outputs" "[]" "$meas" "[]"
}

run_owm_vs_tele_case() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local expected_seq="$4"
	local expected_par="$5"
	local path="$6"
	local case_safe
	local original_unitary
	local owm_path
	local tele_path
	local owm_unitary
	local tele_unitary
	local owm_inputs
	local owm_outputs
	local tele_inputs
	local tele_outputs
	local owm_meas
	local tele_meas

	ensure_input "$path"
	case_safe="$(safe_name "$suite-$case_name")"
	original_unitary="$tmp_dir/${case_safe}_original_unitary.qasm"
	owm_path="$tmp_dir/${case_safe}_owm.qasm"
	tele_path="$tmp_dir/${case_safe}_tele.qasm"
	owm_unitary="$tmp_dir/${case_safe}_owm_unitary.qasm"
	tele_unitary="$tmp_dir/${case_safe}_tele_unitary.qasm"

	if ! convert_to_unitary "$path" "$original_unitary"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi

	if ! run_transform owm "$original_unitary" "$owm_path"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi
	split_transform_lists "$transform_stdout"
	owm_inputs="$transform_inputs"
	owm_outputs="$transform_outputs"

	if ! run_transform tele "$original_unitary" "$tele_path"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi
	split_transform_lists "$transform_stdout"
	tele_inputs="$transform_inputs"
	tele_outputs="$transform_outputs"

	if ! convert_to_unitary "$owm_path" "$owm_unitary"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi
	owm_meas="$(list_or_empty "$conversion_stdout")"

	if ! convert_to_unitary "$tele_path" "$tele_unitary"; then
		emit_failure_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" "$failure_status" "$failure_raw"
		return
	fi
	tele_meas="$(list_or_empty "$conversion_stdout")"

	run_case_modes "$suite" "$case_name" "$kind" "lifting" "$expected_seq" "$expected_par" \
		"$owm_unitary" "$tele_unitary" "$owm_inputs" "$tele_inputs" "$owm_outputs" "$tele_outputs" "$owm_meas" "$tele_meas"
}

suite_is_selected() {
	local suite="$1"
	[[ -z "$suite_filter" || "$suite_filter" == "$suite" ]]
}

run_pair_manifest() {
	local suite
	local case_name
	local kind
	local expected_seq
	local expected_par
	local path1
	local path2

	while IFS=';' read -r suite case_name kind expected_seq expected_par path1 path2 || [[ -n "$suite" ]]; do
		if [[ "$suite" == "Suite" || -z "$(trim "$suite")" ]]; then
			continue
		fi
		if suite_is_selected "$suite"; then
			run_pair_case "$suite" "$case_name" "$kind" "$expected_seq" "$expected_par" "$path1" "$path2"
		fi
	done <"$pairs_file"
}

run_transform_manifest() {
	local suite
	local case_name
	local kind
	local expected_seq
	local expected_par
	local path

	while IFS=';' read -r suite case_name kind expected_seq expected_par path || [[ -n "$suite" ]]; do
		if [[ "$suite" == "Suite" || -z "$(trim "$suite")" ]]; then
			continue
		fi
		if ! suite_is_selected "$suite"; then
			continue
		fi

		case "$kind" in
		owm | tele)
			run_transform_case "$suite" "$case_name" "$kind" "$expected_seq" "$expected_par" "$path"
			;;
		owm_vs_tele)
			run_owm_vs_tele_case "$suite" "$case_name" "$kind" "$expected_seq" "$expected_par" "$path"
			;;
		*)
			echo "Unknown transform kind: $kind" >&2
			exit 1
			;;
		esac
	done <"$transforms_file"
}

run_round() {
	run_pair_manifest
	run_transform_manifest
}

print_check_summary() {
	local detail_path="$output"

	if [[ "$check_mode" != "true" ]]; then
		return
	fi

	if [[ "$status_failed" -eq 0 && "$perf_failed" -eq 0 ]]; then
		echo "Light regression check OK: $row_count rows matched expected statuses; no median slowdown exceeded both thresholds across $run_count round(s)."
	else
		echo "Light regression check FAILED: $status_failure_count status mismatch(es), $perf_failure_count performance regression(s) across $run_count round(s)."

		if [[ "$status_failure_count" -gt 0 ]]; then
			echo "Status mismatches:"
			printf "  - %s\n" "${status_failure_messages[@]}"
		fi

		if [[ "$perf_failure_count" -gt 0 ]]; then
			echo "Performance regressions:"
			printf "  - %s\n" "${perf_failure_messages[@]}"
		fi
	fi

	if [[ -n "$detail_path" ]]; then
		echo "Detailed CSV: $detail_path"
	fi
}

load_baseline

result_file="$(mktemp "$tmp_dir/results.XXXXXX")" || exit 1
trap 'rm -f "$result_file"' EXIT

for ((current_round = 1; current_round <= run_count; current_round++)); do
	run_round
done

emit_results >"$result_file"

if [[ -n "$output" ]]; then
	mkdir -p "$(dirname "$output")"
	cp "$result_file" "$output"
fi

if [[ -n "$save_baseline" ]]; then
	mkdir -p "$(dirname "$save_baseline")"
	cp "$result_file" "$save_baseline"
fi

if [[ "$quiet_mode" != "true" ]]; then
	cat "$result_file"
fi

print_check_summary

if [[ "$check_mode" == "true" && ( "$status_failed" -ne 0 || "$perf_failed" -ne 0 ) ]]; then
	exit 1
fi
