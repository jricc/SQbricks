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

# A slowdown is reported only when both the relative and absolute limits fail.
perf_threshold="${SQBRICKS_LIGHT_PERF_THRESHOLD:-1.25}"
min_perf_seconds="${SQBRICKS_LIGHT_MIN_PERF_SECONDS:-0.01}"
min_slowdown_seconds="${SQBRICKS_LIGHT_MIN_SLOWDOWN_SECONDS:-0.05}"
run_count="${SQBRICKS_LIGHT_RUNS:-3}"
progress_mode="${SQBRICKS_LIGHT_PROGRESS:-auto}"

suite_filter=""
output=""
baseline=""
save_baseline=""
stable_mode="false"
check_mode="false"
quiet_mode="false"
row_count=0
status_failure_count=0
perf_failure_count=0
perf_data_failure_count=0
performance_row_count=0
verifications_per_round=0
progress_enabled="false"
progress_current=0
progress_total=0
progress_line_open="false"
definition_schema="1"

# Baseline data, indexed by "suite|case|kind|mode".
declare -A baseline_times
declare -A baseline_rows
declare -A baseline_raws
declare -A baseline_definition_hashes

# Current manifest definition, built before any benchmark is executed.
declare -A manifest_rows
declare -A manifest_definition_hashes
declare -A tracked_performance

# Human-readable diagnostics accumulated for the final summary.
declare -a status_failure_messages
declare -a perf_failure_messages
declare -a perf_data_failure_messages

# Results accumulated across rounds before one final CSV row is emitted.
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
  --check               Require a valid baseline and exit non-zero on regression
                        or incomplete tracked performance data.
  --quiet               Do not print the detailed CSV result to the terminal.
  -h, --help            Show this help.

Environment:
  SQBRICKS_LIGHT_TIMEOUT=120s
  SQBRICKS_LIGHT_MEMORY_KB=7340032
  SQBRICKS_LIGHT_PERF_THRESHOLD=1.25
  SQBRICKS_LIGHT_MIN_PERF_SECONDS=0.01
  SQBRICKS_LIGHT_MIN_SLOWDOWN_SECONDS=0.05
  SQBRICKS_LIGHT_RUNS=3
  SQBRICKS_LIGHT_PROGRESS=auto
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

if [[ "$stable_mode" == "true" && "$check_mode" == "true" ]]; then
	echo "--check requires the full output, without --stable" >&2
	exit 1
fi

if [[ "$check_mode" == "true" && -z "$baseline" ]]; then
	echo "--check requires --baseline" >&2
	exit 1
fi

if [[ ! "$run_count" =~ ^[1-9][0-9]*$ ]]; then
	echo "SQBRICKS_LIGHT_RUNS must be a positive integer." >&2
	exit 1
fi

case "$progress_mode" in
auto | always | never) ;;
*)
	echo "SQBRICKS_LIGHT_PROGRESS must be auto, always, or never." >&2
	exit 1
	;;
esac

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

# Timings must be strictly positive: zero usually means missing or malformed data.
is_positive_number() {
	is_number "$1" && awk -v value="$1" 'BEGIN { exit !(value > 0) }'
}

normalize_number() {
	local value
	value="$(trim "$1")"
	value="${value/,/.}"
	printf "%s" "$value"
}

# Hash an input file so that changing a circuit invalidates the local baseline.
file_content_hash() {
	local path="$1"
	local digest

	ensure_input "$path"
	if ! digest="$(sha256sum -- "$path")"; then
		echo "Failed to hash benchmark input: $path" >&2
		return 1
	fi
	printf "%s" "${digest%% *}"
}

# Build the stable identity of one Sequence or Parallel verification.
# The SQbricks binary is intentionally absent: its changes are what we measure.
benchmark_definition_hash() {
	local source_type="$1"
	local suite="$2"
	local case_name="$3"
	local kind="$4"
	local opt="$5"
	local expected="$6"
	local track_performance="$7"
	local path1="$8"
	local path2="$9"
	local path1_hash
	local path2_hash="-"
	local digest

	path1_hash="$(file_content_hash "$path1")" || return 1
	if [[ -n "$path2" ]]; then
		path2_hash="$(file_content_hash "$path2")" || return 1
	fi

	digest="$(
		printf '%s\n' \
			"schema=$definition_schema" \
			"source=$source_type" \
			"suite=$suite" \
			"case=$case_name" \
			"kind=$kind" \
			"opt=$opt" \
			"expected=$expected" \
			"track_performance=$track_performance" \
			"path1=$path1" \
			"path1_sha256=$path1_hash" \
			"path2=$path2" \
			"path2_sha256=$path2_hash" \
			"runs=$run_count" \
			"timeout=$timeout_s" \
			"memory_kb=$memory_kb" |
			sha256sum
	)" || {
		echo "Failed to hash benchmark definition: $suite/$case_name $kind $opt" >&2
		return 1
	}
	printf "%s" "${digest%% *}"
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

# Redraw one terminal line; CSV output remains separate and quiet.
render_progress() {
	local label="$1"
	local bar_width=30
	local percent
	local filled
	local pending_width
	local complete
	local pending
	local bar
	local displayed_round="$current_round"

	if [[ "$progress_enabled" != "true" || "$progress_total" -eq 0 ]]; then
		return
	fi

	if [[ "$displayed_round" -eq 0 ]]; then
		displayed_round=1
	fi

	percent=$((progress_current * 100 / progress_total))
	filled=$((progress_current * bar_width / progress_total))
	pending_width=$((bar_width - filled))
	printf -v complete "%*s" "$filled" ""
	printf -v pending "%*s" "$pending_width" ""
	bar="${complete// /#}${pending// /-}"

	printf "\rLight regression [%s] %3d%% %d/%d round %d/%d - %.48s\033[K" \
		"$bar" "$percent" "$progress_current" "$progress_total" \
		"$displayed_round" "$run_count" "$label" >&2
	progress_line_open="true"
}

# One progress step corresponds to one completed SQbricks verification.
advance_progress() {
	local suite="$1"
	local case_name="$2"
	local kind="$3"
	local opt="$4"

	progress_current=$((progress_current + 1))
	render_progress "$suite/$case_name $kind $opt"
}

# End the carriage-return based progress line before printing diagnostics.
finish_progress() {
	if [[ "$progress_line_open" == "true" ]]; then
		printf "\n" >&2
		progress_line_open="false"
	fi
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
		# A successful process with an unknown answer is not evidence of NC.
		printf "UNEXPECTED_OUTPUT"
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

# Read only the baseline fields needed by the preflight checks and comparison.
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
	local previous_baseline
	local previous_ratio
	local previous_perf_status
	local raw
	local definition_hash
	local key

	if [[ -z "$baseline" ]]; then
		return
	fi

	if [[ ! -f "$baseline" ]]; then
		echo "Missing baseline: $baseline" >&2
		exit 1
	fi

	while IFS=';' read -r suite case_name kind tool version lift opt expected actual match ch cs cz ccz ccx cu1 gates time previous_baseline previous_ratio previous_perf_status raw definition_hash || [[ -n "$suite" ]]; do
		if [[ "$suite" == "Suite" || -z "$(trim "$suite")" ]]; then
			continue
		fi

		key="$suite|$case_name|$kind|$opt"
		if [[ -n "${baseline_rows[$key]:-}" ]]; then
			echo "Duplicate baseline verification: $(benchmark_key_label "$key")" >&2
			exit 1
		fi
		baseline_rows["$key"]="true"
		baseline_raws["$key"]="$raw"
		baseline_definition_hashes["$key"]="$definition_hash"
		time="$(normalize_number "$time")"
		if is_number "$time"; then
			baseline_times["$key"]="$time"
		fi
	done <"$baseline"
}

# Count and validate the timing samples stored in a row's Raw field.
sample_count_from_raw() {
	local raw="$1"
	local samples_text
	local sample
	local samples=()

	if [[ "$raw" != *"times=["*"]"* ]]; then
		printf "0"
		return
	fi

	samples_text="${raw#*times=[}"
	samples_text="${samples_text%%]*}"
	if [[ -z "$samples_text" ]]; then
		printf "0"
		return
	fi

	IFS=',' read -r -a samples <<<"$samples_text"
	for sample in "${samples[@]}"; do
		sample="$(normalize_number "$sample")"
		if ! is_positive_number "$sample"; then
			printf "invalid"
			return
		fi
	done

	printf "%d" "${#samples[@]}"
}

# Read the number of rounds recorded in a row's Raw field.
round_count_from_raw() {
	local raw="$1"
	local round_text

	if [[ "$raw" != *"rounds="* ]]; then
		printf "missing"
		return
	fi

	round_text="${raw#*rounds=}"
	round_text="${round_text%% *}"
	if [[ "$round_text" =~ ^[1-9][0-9]*$ ]]; then
		printf "%s" "$round_text"
	else
		printf "invalid"
	fi
}

# Turn the internal associative-array key into a readable diagnostic label.
benchmark_key_label() {
	local key="$1"
	local suite
	local case_name
	local kind
	local opt

	IFS='|' read -r suite case_name kind opt <<<"$key"
	printf "%s/%s %s %s" "$suite" "$case_name" "$kind" "$opt"
}

# Stop before running SQbricks and print every problem found by one validation.
fail_preflight() {
	local summary="$1"
	shift

	finish_progress
	echo "Light regression check FAILED: $summary" >&2
	printf "  - %s\n" "$@" >&2
	exit 1
}

# Reject baseline rows whose case or execution mode disappeared from a manifest.
validate_manifest_coverage() {
	local key
	local suite
	local case_name
	local kind
	local opt
	local failure_messages=()

	if [[ "$check_mode" != "true" ]]; then
		return
	fi

	for key in "${!baseline_rows[@]}"; do
		IFS='|' read -r suite case_name kind opt <<<"$key"
		if ! suite_is_selected "$suite"; then
			continue
		fi
		if [[ -z "${manifest_rows[$key]:-}" ]]; then
			failure_messages+=("Baseline contains removed benchmark verification: $(benchmark_key_label "$key")")
		fi
	done

	if [[ "${#failure_messages[@]}" -gt 0 ]]; then
		fail_preflight "benchmark coverage changed." "${failure_messages[@]}"
	fi
}

# Reject a baseline produced from different manifests, inputs, or run settings.
validate_baseline_definitions() {
	local key
	local label
	local baseline_hash
	local current_hash
	local failure_messages=()

	if [[ "$check_mode" != "true" ]]; then
		return
	fi

	for key in "${!manifest_rows[@]}"; do
		if [[ -z "${baseline_rows[$key]:-}" ]]; then
			continue
		fi

		label="$(benchmark_key_label "$key")"
		baseline_hash="${baseline_definition_hashes[$key]:-}"
		current_hash="${manifest_definition_hashes[$key]:-}"
		if [[ -z "$baseline_hash" ]]; then
			failure_messages+=("Missing benchmark definition hash for $label; regenerate the local baseline")
		elif [[ "$baseline_hash" != "$current_hash" ]]; then
			failure_messages+=("Benchmark definition changed for $label; regenerate the local baseline")
		fi
	done

	if [[ "${#failure_messages[@]}" -gt 0 ]]; then
		fail_preflight "benchmark definition changed." "${failure_messages[@]}"
	fi
}

# Ensure every performance row has a usable timing for every configured round.
validate_baseline_performance_data() {
	local key
	local label
	local sample_count
	local baseline_round_count
	local failure_messages=()

	if [[ "$check_mode" != "true" ]]; then
		return
	fi

	for key in "${!tracked_performance[@]}"; do
		label="$(benchmark_key_label "$key")"

		if [[ -z "${baseline_rows[$key]:-}" ]]; then
			failure_messages+=("Missing baseline timing for $label")
			continue
		fi

		if ! is_positive_number "${baseline_times[$key]:-}"; then
			failure_messages+=("Invalid baseline timing for $label")
			continue
		fi

		sample_count="$(sample_count_from_raw "${baseline_raws[$key]:-}")"
		if [[ "$sample_count" == "invalid" ]]; then
			failure_messages+=("Invalid baseline timing samples for $label")
			continue
		fi
		if [[ "$sample_count" -ne "$run_count" ]]; then
			failure_messages+=("Baseline sample count mismatch for $label: expected $run_count, got $sample_count")
			continue
		fi

		baseline_round_count="$(round_count_from_raw "${baseline_raws[$key]:-}")"
		if [[ "$baseline_round_count" == "missing" || "$baseline_round_count" == "invalid" ]]; then
			failure_messages+=("Invalid baseline round count for $label")
			continue
		fi
		if [[ "$baseline_round_count" -ne "$run_count" ]]; then
			failure_messages+=("Baseline round count mismatch for $label: expected $run_count, got $baseline_round_count")
		fi
	done

	if [[ "${#failure_messages[@]}" -gt 0 ]]; then
		fail_preflight "invalid baseline performance data." "${failure_messages[@]}"
	fi
}

# Compare a median timing with its baseline and expose the classification fields.
perf_info() {
	local key="$1"
	local actual_time="$2"

	baseline_seconds="${baseline_times[$key]:-}"
	ratio=""
	slowdown_seconds=""
	perf_status="NA"

	if is_number "$actual_time" && is_number "$baseline_seconds" && [[ "$baseline_seconds" != "0" && "$baseline_seconds" != "0.0" ]]; then
		# Very short measurements are too noisy to support a useful ratio.
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
		echo "Suite;Case;Kind;Tool;Version;Lift;Opt;ExpectedStatus;ActualStatus;StatusMatch;CH;CS;CZ;CCZ;CCX;CU1;Gates;TimeSeconds;BaselineSeconds;Ratio;PerfStatus;Raw;DefinitionHash"
	fi
}

# Store one round in memory; rows are written only after all rounds are complete.
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

	advance_progress "$suite" "$case_name" "$kind" "$opt"
}

# Classify one aggregated row and write its final CSV representation.
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
	local timing_complete="${11}"
	local match="OK"
	local key
	local raw_clean

	row_count=$((row_count + 1))
	key="$suite|$case_name|$kind|$opt"
	if [[ "${tracked_performance[$key]:-no}" == "yes" ]]; then
		performance_row_count=$((performance_row_count + 1))
	fi

	if [[ "$expected" != "$actual" || "$actual" == "UNEXPECTED_OUTPUT" ]]; then
		match="FAIL"
		status_failure_count=$((status_failure_count + 1))
		status_failure_messages+=("$suite/$case_name $kind $opt: expected $expected, got $actual")
	fi

	if [[ "$stable_mode" == "true" ]]; then
		printf "%s;%s;%s;%s;%s;%s;%s\n" \
			"$suite" "$case_name" "$kind" "$opt" "$expected" "$actual" "$match"
		return
	fi

	if [[ "${tracked_performance[$key]:-no}" == "yes" && "$timing_complete" == "true" ]]; then
		perf_info "$key" "$time_seconds"
		if [[ "$perf_status" == "SLOWER" ]]; then
			perf_failure_count=$((perf_failure_count + 1))
			perf_failure_messages+=("$suite/$case_name $kind $opt: ${time_seconds}s vs ${baseline_seconds}s baseline, +${slowdown_seconds}s and ratio $ratio")
		fi
	elif [[ "${tracked_performance[$key]:-no}" == "yes" ]]; then
		baseline_seconds="${baseline_times[$key]:-}"
		ratio=""
		perf_status="INCOMPLETE"
	else
		baseline_seconds=""
		ratio=""
		perf_status="NOT_TRACKED"
	fi

	raw_clean="$(clean_csv "$raw")"
	printf "%s;%s;%s;SQbricks;2025;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s\n" \
		"$suite" "$case_name" "$kind" "$lift" "$opt" "$expected" "$actual" "$match" \
		"$gate_counts" "$time_seconds" "$baseline_seconds" "$ratio" "$perf_status" "$raw_clean" \
		"${manifest_definition_hashes[$key]}"
}

# Merge all rounds, reject incomplete timing series, and compute medians.
emit_results() {
	local key
	local actual
	local time_seconds
	local raw
	local status
	local sample
	local sample_count
	local timing_complete
	local statuses=()
	local times=()

	emit_header

	for key in "${row_keys[@]}"; do
		# A status is accepted only when every round returned the same answer.
		IFS=',' read -r -a statuses <<<"${row_statuses[$key]}"
		actual="${statuses[0]}"
		for status in "${statuses[@]}"; do
			if [[ "$status" != "$actual" ]]; then
				actual="FLAKY"
				break
			fi
		done

		time_seconds=""
		timing_complete="true"
		times=()
		if [[ -n "${row_times[$key]}" ]]; then
			IFS=',' read -r -a times <<<"${row_times[$key]}"
		fi
		sample_count=0
		for sample in "${times[@]}"; do
			if is_positive_number "$sample"; then
				sample_count=$((sample_count + 1))
			fi
		done

		# Performance rows need exactly one valid timing from every round.
		if [[ "${tracked_performance[$key]:-no}" == "yes" && "$sample_count" -ne "$run_count" ]]; then
			timing_complete="false"
			perf_data_failure_count=$((perf_data_failure_count + 1))
			perf_data_failure_messages+=(
				"Incomplete timing samples for $(benchmark_key_label "$key"): expected $run_count, got $sample_count"
			)
		fi

		if [[ "$actual" != "FLAKY" && "$sample_count" -gt 0 && "$timing_complete" == "true" ]]; then
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
			"$raw" \
			"$timing_complete"
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

# Validate the performance marker once per manifest row.
validate_track_performance() {
	local suite="$1"
	local case_name="$2"
	local track_performance="$3"

	if [[ "$track_performance" != "yes" && "$track_performance" != "no" ]]; then
		echo "Invalid TrackPerformance value for $suite/$case_name: $track_performance" >&2
		exit 1
	fi
}

# Register one execution mode and compute the definition stored in the CSV.
register_verification() {
	local source_type="$1"
	local suite="$2"
	local case_name="$3"
	local kind="$4"
	local opt="$5"
	local expected="$6"
	local track_performance="$7"
	local path1="$8"
	local path2="$9"
	local key

	if [[ "$expected" == "-" ]]; then
		return
	fi

	key="$suite|$case_name|$kind|$opt"
	if [[ -n "${manifest_rows[$key]:-}" ]]; then
		echo "Duplicate benchmark verification: $(benchmark_key_label "$key")" >&2
		exit 1
	fi
	manifest_rows["$key"]="true"
	manifest_definition_hashes["$key"]="$(benchmark_definition_hash \
		"$source_type" "$suite" "$case_name" "$kind" "$opt" "$expected" \
		"$track_performance" "$path1" "$path2")" || exit 1

	if [[ "$track_performance" == "yes" ]]; then
		tracked_performance["$key"]="yes"
	fi
	verifications_per_round=$((verifications_per_round + 1))
}

# Load direct circuit comparisons from pairs.csv.
load_pair_definitions() {
	local suite
	local case_name
	local kind
	local expected_seq
	local expected_par
	local track_performance
	local path1
	local path2

	while IFS=';' read -r suite case_name kind expected_seq expected_par track_performance path1 path2 || [[ -n "$suite" ]]; do
		if [[ "$suite" == "Suite" || -z "$(trim "$suite")" ]]; then
			continue
		fi
		if ! suite_is_selected "$suite"; then
			continue
		fi
		validate_track_performance "$suite" "$case_name" "$track_performance"
		register_verification "pair" "$suite" "$case_name" "$kind" \
			"Sequence" "$expected_seq" "$track_performance" "$path1" "$path2"
		register_verification "pair" "$suite" "$case_name" "$kind" \
			"Parallel" "$expected_par" "$track_performance" "$path1" "$path2"
	done <"$pairs_file"
}

# Load transformation-based comparisons from transforms.csv.
load_transform_definitions() {
	local suite
	local case_name
	local kind
	local expected_seq
	local expected_par
	local track_performance
	local path

	while IFS=';' read -r suite case_name kind expected_seq expected_par track_performance path || [[ -n "$suite" ]]; do
		if [[ "$suite" == "Suite" || -z "$(trim "$suite")" ]]; then
			continue
		fi
		if ! suite_is_selected "$suite"; then
			continue
		fi
		validate_track_performance "$suite" "$case_name" "$track_performance"
		register_verification "transform" "$suite" "$case_name" "$kind" \
			"Sequence" "$expected_seq" "$track_performance" "$path" ""
		register_verification "transform" "$suite" "$case_name" "$kind" \
			"Parallel" "$expected_par" "$track_performance" "$path" ""
	done <"$transforms_file"
}

# Read all selected definitions before loading or validating the baseline.
load_benchmark_definitions() {
	load_pair_definitions
	load_transform_definitions

	if [[ "$verifications_per_round" -eq 0 ]]; then
		if [[ -n "$suite_filter" ]]; then
			echo "No benchmark verification found for suite: $suite_filter" >&2
		else
			echo "No benchmark verification found in the light manifests." >&2
		fi
		exit 1
	fi
}

# Derive the progress total from the definitions that were actually selected.
configure_progress() {
	progress_total=$((verifications_per_round * run_count))
	case "$progress_mode" in
	always) progress_enabled="true" ;;
	auto)
		if [[ -t 2 ]]; then
			progress_enabled="true"
		fi
		;;
	never) progress_enabled="false" ;;
	esac

	render_progress "starting"
}

run_pair_manifest() {
	local suite
	local case_name
	local kind
	local expected_seq
	local expected_par
	local track_performance
	local path1
	local path2

	while IFS=';' read -r suite case_name kind expected_seq expected_par track_performance path1 path2 || [[ -n "$suite" ]]; do
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
	local track_performance
	local path

	while IFS=';' read -r suite case_name kind expected_seq expected_par track_performance path || [[ -n "$suite" ]]; do
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

# Print only the concise verdict; the detailed rows already live in the CSV.
print_check_summary() {
	local detail_path="$output"

	if [[ "$check_mode" != "true" ]]; then
		return
	fi

	if [[ "$status_failure_count" -eq 0 && "$perf_failure_count" -eq 0 && "$perf_data_failure_count" -eq 0 ]]; then
		echo "Light regression check OK: $row_count rows matched expected statuses; no median slowdown exceeded both thresholds in $performance_row_count tracked performance row(s) across $run_count round(s)."
	else
		echo "Light regression check FAILED: $status_failure_count status mismatch(es), $perf_failure_count performance regression(s), $perf_data_failure_count performance data error(s) across $run_count round(s)."

		if [[ "$status_failure_count" -gt 0 ]]; then
			echo "Status mismatches:"
			printf "  - %s\n" "${status_failure_messages[@]}"
		fi

		if [[ "$perf_failure_count" -gt 0 ]]; then
			echo "Performance regressions:"
			printf "  - %s\n" "${perf_failure_messages[@]}"
		fi

		if [[ "$perf_data_failure_count" -gt 0 ]]; then
			echo "Performance data errors:"
			printf "  - %s\n" "${perf_data_failure_messages[@]}"
		fi
	fi

	if [[ -n "$detail_path" ]]; then
		echo "Detailed CSV: $detail_path"
	fi
}

# A baseline is publishable only when statuses and timing series are complete.
validate_baseline_result() {
	if [[ -z "$save_baseline" ]]; then
		return 0
	fi

	if [[ "$status_failure_count" -eq 0 && "$perf_data_failure_count" -eq 0 ]]; then
		return 0
	fi

	echo "Light regression baseline FAILED: $status_failure_count status mismatch(es), $perf_data_failure_count performance data error(s)." >&2

	if [[ "$status_failure_count" -gt 0 ]]; then
		echo "Status mismatches:" >&2
		printf "  - %s\n" "${status_failure_messages[@]}" >&2
	fi

	if [[ "$perf_data_failure_count" -gt 0 ]]; then
		echo "Performance data errors:" >&2
		printf "  - %s\n" "${perf_data_failure_messages[@]}" >&2
	fi

	return 1
}

# Replace a result only after a complete temporary copy exists beside it.
write_file_atomically() {
	local source="$1"
	local target="$2"
	local description="$3"
	local target_dir
	local target_name
	local temporary

	target_dir="$(dirname "$target")"
	target_name="$(basename "$target")"

	if ! mkdir -p "$target_dir"; then
		echo "Failed to create directory for $description: $target_dir" >&2
		return 1
	fi

	temporary="$(mktemp "$target_dir/.${target_name}.XXXXXX")" || {
		echo "Failed to create temporary $description file in $target_dir" >&2
		return 1
	}

	if ! cp "$source" "$temporary"; then
		rm -f "$temporary"
		echo "Failed to prepare $description: $target" >&2
		return 1
	fi

	if ! mv -f "$temporary" "$target"; then
		rm -f "$temporary"
		echo "Failed to write $description atomically: $target" >&2
		return 1
	fi
}

result_file="$(mktemp "$tmp_dir/results.XXXXXX")" || exit 1

# Always remove the temporary CSV and leave the terminal on a clean line.
cleanup() {
	finish_progress
	rm -f "$result_file"
}
trap cleanup EXIT

# Phase 1: describe the selected benchmark and validate its local baseline.
load_benchmark_definitions
configure_progress
load_baseline
validate_manifest_coverage
validate_baseline_definitions
validate_baseline_performance_data

# Phase 2: execute every selected verification once per round.
for ((current_round = 1; current_round <= run_count; current_round++)); do
	run_round
done
finish_progress

# Phase 3: aggregate the rounds, validate the result, then publish files.
if ! emit_results >"$result_file"; then
	echo "Failed to generate light regression CSV." >&2
	exit 1
fi

if ! validate_baseline_result; then
	exit 1
fi

if [[ -n "$output" ]]; then
	if ! write_file_atomically "$result_file" "$output" "result"; then
		exit 1
	fi
fi

if [[ -n "$save_baseline" ]]; then
	if ! write_file_atomically "$result_file" "$save_baseline" "baseline"; then
		exit 1
	fi
fi

if [[ "$quiet_mode" != "true" ]]; then
	cat "$result_file"
fi

print_check_summary

if [[ "$check_mode" == "true" &&
	( "$status_failure_count" -ne 0 ||
		"$perf_failure_count" -ne 0 ||
		"$perf_data_failure_count" -ne 0 ) ]]; then
	exit 1
fi
