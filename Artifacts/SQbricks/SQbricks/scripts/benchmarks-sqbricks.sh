#!/usr/bin/env bash

# This file is part of SQbricks.
#
# Copyright (C) 2022-2026
# CEA (Commissariat a l'energie atomique et aux energies alternatives)
# Universite Paris-Saclay
#
# you can redistribute it and/or modify it under the terms of the GNU
# Lesser General Public License as published by the Free Software
# Foundation, version 2.1.
#
# It is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# See the GNU Lesser General Public License version 2.1
# for more details (enclosed in the file licenses/LGPLv2.1).

set -u

debug="${SQBRICKS_LONG_DEBUG:-false}"
version="${1:-}"
timeout_s="${SQBRICKS_LONG_TIMEOUT:-600s}"
memory_kb="${SQBRICKS_LONG_MEMORY_KB:-7340032}"
progress_mode="${SQBRICKS_LONG_PROGRESS:-auto}"

if [[ -z "$version" ]]; then
	echo "Usage: $0 <sanity-unit|sanity-hybrid|sanity-partial|unit-vs-hybrid|veriqc|qiskit-hybrid|owm|tele|owm-vs-tele|owm-vs-qiskit>" >&2
	exit 1
fi

case "$version" in
sanity-unit | sanity-hybrid | sanity-partial | unit-vs-hybrid | veriqc | qiskit-hybrid | owm | tele | owm-vs-tele | owm-vs-qiskit) ;;
*)
	echo "Unknown SQbricks benchmark version: $version" >&2
	exit 1
	;;
esac

export DUNE_BUILD_DIR="${DUNE_BUILD_DIR:-$(pwd)/_build/sqbricks-long/$version}"

tmp_dir="_tmp/sqbricks-long/$version"
path_file="scripts/paths/paths_${version}.txt"
case_index=0
progress_enabled="false"
progress_current=0
progress_total=0
progress_line_open="false"
cmd_stdout=""
cmd_stderr=""
cmd_status=0

if [[ ! -f "$path_file" ]]; then
	echo "Missing path file: $path_file" >&2
	exit 1
fi

case "$progress_mode" in
auto | always | never) ;;
*)
	echo "SQBRICKS_LONG_PROGRESS must be auto, always, or never." >&2
	exit 1
	;;
esac

mkdir -p "$tmp_dir"

trim() {
	local value="$1"
	value="${value//$'\r'/}"
	printf "%s" "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

csv_time() {
	printf "%s" "$1" | sed 's/\./,/'
}

status_from_failure() {
	local status="$1"
	local stderr="$2"

	if [[ "$status" -eq 124 ]]; then
		printf "TO"
	elif [[ "$status" -eq 137 || "$stderr" == *"allocation failure during minor GC"* || "$stderr" == *"Out_of_memory"* ]]; then
		printf "OutOfMemory"
	else
		printf "Err%s" "$status"
	fi
}

run_sqbricks_command() {
	local stdout_file
	local stderr_file

	stdout_file="$(mktemp "$tmp_dir/stdout.XXXXXX")" || exit 1
	stderr_file="$(mktemp "$tmp_dir/stderr.XXXXXX")" || exit 1

	if [[ "$debug" == "true" ]]; then
		echo "dune exec -- ./bin/main.exe $*" >&2
	fi

	if command -v timeout >/dev/null 2>&1; then
		timeout "$timeout_s" bash -c 'ulimit -v "$1"; shift; exec "$@"' \
			_ "$memory_kb" dune exec -- ./bin/main.exe "$@" \
			>"$stdout_file" 2>"$stderr_file"
	else
		bash -c 'ulimit -v "$1"; shift; exec "$@"' \
			_ "$memory_kb" dune exec -- ./bin/main.exe "$@" \
			>"$stdout_file" 2>"$stderr_file"
	fi

	cmd_status=$?
	cmd_stdout="$(cat "$stdout_file")"
	cmd_stderr="$(cat "$stderr_file")"
	rm -f "$stdout_file" "$stderr_file"

	return "$cmd_status"
}

run_qiskit_transform() {
	local input="$1"
	local output="$2"
	local stdout_file
	local stderr_file

	stdout_file="$(mktemp "$tmp_dir/stdout.XXXXXX")" || exit 1
	stderr_file="$(mktemp "$tmp_dir/stderr.XXXXXX")" || exit 1

	if [[ "$debug" == "true" ]]; then
		echo "python3 scripts/qiskit-tr.py $input $output" >&2
	fi

	if command -v timeout >/dev/null 2>&1; then
		timeout "$timeout_s" bash -c 'ulimit -v "$1"; shift; exec "$@"' \
			_ "$memory_kb" python3 scripts/qiskit-tr.py "$input" "$output" \
			>"$stdout_file" 2>"$stderr_file"
	else
		bash -c 'ulimit -v "$1"; shift; exec "$@"' \
			_ "$memory_kb" python3 scripts/qiskit-tr.py "$input" "$output" \
			>"$stdout_file" 2>"$stderr_file"
	fi

	cmd_status=$?
	cmd_stdout="$(cat "$stdout_file")"
	cmd_stderr="$(cat "$stderr_file")"
	rm -f "$stdout_file" "$stderr_file"

	return "$cmd_status"
}

gate_count() {
	local path1="$1"
	local path2="$2"

	if run_sqbricks_command -nb_gates_csv "$path1" "$path2"; then
		trim "$cmd_stdout"
	else
		printf ";;;;;;"
	fi
}

run_sql() {
	local mode="$1"
	local input="$2"
	local output="$3"

	run_sqbricks_command -sql "$mode" "$input" "$output"
}

run_transform() {
	local kind="$1"
	local input="$2"
	local output="$3"

	run_sqbricks_command "-qasm_to_${kind}" "$input" "$output" "false"
}

split_transform_output() {
	local value="$1"
	local __inputs="$2"
	local __outputs="$3"
	local inputs
	local outputs

	inputs="${value%%,*}"
	outputs="${value##*,}"
	printf -v "$__inputs" "%s" "$(trim "$inputs")"
	printf -v "$__outputs" "%s" "$(trim "$outputs")"
}

emit_conversion_error() {
	local name="$1"
	local lift="$2"

	echo "$name;SQbricks;2025;$lift;Conversion;;;;;;;;ErrConv"
}

run_equiv_sqbricks() {
	local nb_gate="$1"
	local name="$2"
	local path1="$3"
	local path2="$4"
	local lift="$5"
	local inputs1="${6:-}"
	local inputs2="${7:-}"
	local outputs1="${8:-}"
	local outputs2="${9:-}"
	local meas1="${10:-}"
	local meas2="${11:-}"

	run_equiv_mode() {
		local algo="$1"
		local label="$2"
		local result

		if run_sqbricks_command -sqv "$algo" s \
			"$path1" "$path2" \
			"$inputs1" "$inputs2" "$outputs1" "$outputs2" \
			"$meas1" "$meas2"; then
			result="$(csv_time "$(trim "$cmd_stdout")")"
		else
			result="$(status_from_failure "$cmd_status" "$cmd_stderr")"
		fi

		echo "$name;SQbricks;2025;$lift;$label;$nb_gate;$result"
	}

	if [[ "$version" != "owm-vs-tele" ]]; then
		run_equiv_mode seq "Sequence"
	fi
	run_equiv_mode par "Parallel"
}

test_unit() {
	local path1="$1"
	local path2="$2"
	local name="$3"
	local nb_gate

	nb_gate="$(gate_count "$path1" "$path2")"
	run_equiv_sqbricks "$nb_gate" "$name" "$path1" "$path2" "standalone"
}

test_lifted_pair() {
	local path1="$1"
	local path2="$2"
	local path1_unitary="$3"
	local path2_unitary="$4"
	local name="$5"
	local nb_gate

	if run_sql u "$path1" "$path1_unitary" &&
		run_sql u "$path2" "$path2_unitary"; then
		nb_gate="$(gate_count "$path1_unitary" "$path2_unitary")"
		run_equiv_sqbricks "$nb_gate" "$name" "$path1_unitary" "$path2_unitary" "lifting"
	else
		emit_conversion_error "$name" "lifting"
	fi
}

test_qiskit_hybrid() {
	local path_original="$1"
	local path_optimized="$2"
	local path_original_unitary="$3"
	local path_optimized_unitary="$4"
	local name="$5"

	if run_qiskit_transform "$path_original" "$path_optimized"; then
		test_lifted_pair "$path_original" "$path_optimized" \
			"$path_original_unitary" "$path_optimized_unitary" "$name"
	else
		emit_conversion_error "$name" "lifting"
	fi
}

test_transformed_against_unitary() {
	local kind="$1"
	local path_original="$2"
	local path_original_unitary="$3"
	local path_transformed="$4"
	local path_transformed_ium="$5"
	local name="$6"
	local transform_output
	local inputs
	local outputs
	local meas1
	local nb_gate

	if run_sql u "$path_original" "$path_original_unitary" &&
		run_transform "$kind" "$path_original_unitary" "$path_transformed"; then
		transform_output="$(trim "$cmd_stdout")"
		if run_sql u "$path_transformed" "$path_transformed_ium"; then
			meas1="$(trim "$cmd_stdout")"
			split_transform_output "$transform_output" inputs outputs
			nb_gate="$(gate_count "$path_transformed_ium" "$path_original_unitary")"
			run_equiv_sqbricks "$nb_gate" "$name" \
				"$path_transformed_ium" "$path_original_unitary" "lifting" \
				"$inputs" "[]" "$outputs" "[]" "$meas1" "[]"
		else
			emit_conversion_error "$name" "lifting"
		fi
	else
		emit_conversion_error "$name" "lifting"
	fi
}

test_owm_vs_tele() {
	local path_original="$1"
	local path_original_unitary="$2"
	local path_owm="$3"
	local path_owm_ium="$4"
	local path_tele="$5"
	local path_tele_ium="$6"
	local name="$7"
	local output_owm
	local output_tele
	local inputs1
	local inputs2
	local outputs1
	local outputs2
	local meas1
	local meas2
	local nb_gate

	if run_sql u "$path_original" "$path_original_unitary" &&
		run_transform owm "$path_original_unitary" "$path_owm"; then
		output_owm="$(trim "$cmd_stdout")"
		if run_transform tele "$path_original_unitary" "$path_tele"; then
			output_tele="$(trim "$cmd_stdout")"
			if run_sql u "$path_owm" "$path_owm_ium"; then
				meas1="$(trim "$cmd_stdout")"
				if run_sql u "$path_tele" "$path_tele_ium"; then
					meas2="$(trim "$cmd_stdout")"
					split_transform_output "$output_owm" inputs1 outputs1
					split_transform_output "$output_tele" inputs2 outputs2
					nb_gate="$(gate_count "$path_owm_ium" "$path_tele_ium")"
					run_equiv_sqbricks "$nb_gate" "$name" \
						"$path_owm_ium" "$path_tele_ium" "lifting" \
						"$inputs1" "$inputs2" "$outputs1" "$outputs2" "$meas1" "$meas2"
				else
					emit_conversion_error "$name" "lifting"
				fi
			else
				emit_conversion_error "$name" "lifting"
			fi
		else
			emit_conversion_error "$name" "lifting"
		fi
	else
		emit_conversion_error "$name" "lifting"
	fi
}

test_owm_vs_qiskit() {
	local path_original="$1"
	local path_original_unitary="$2"
	local path_optimized="$3"
	local path_optimized_ium="$4"
	local path_owm="$5"
	local path_owm_ium="$6"
	local name="$7"
	local output_owm
	local inputs1
	local outputs1
	local meas1
	local nb_gate

	if run_qiskit_transform "$path_original" "$path_optimized" &&
		run_sql u "$path_original" "$path_original_unitary" &&
		run_transform owm "$path_original_unitary" "$path_owm"; then
		output_owm="$(trim "$cmd_stdout")"
		if run_sql u "$path_optimized" "$path_optimized_ium" &&
			run_sql u "$path_owm" "$path_owm_ium"; then
			meas1="$(trim "$cmd_stdout")"
			split_transform_output "$output_owm" inputs1 outputs1
			nb_gate="$(gate_count "$path_owm_ium" "$path_optimized_ium")"
			run_equiv_sqbricks "$nb_gate" "$name" \
				"$path_owm_ium" "$path_optimized_ium" "lifting" \
				"$inputs1" "" "$outputs1" "" "$meas1" ""
		else
			emit_conversion_error "$name" "lifting"
		fi
	else
		emit_conversion_error "$name" "lifting"
	fi
}

prepare_paths() {
	local path_original="$1"

	filename="$(basename -- "$path_original")"
	filename_no_ext="${filename%.qasm}"

	case "$version" in
	sanity-unit | sanity-hybrid | sanity-partial | unit-vs-hybrid | veriqc)
		IFS=';' read -r path1 path2 _ <<<"$path_original"
		filename1="$(basename -- "$path1")"
		filename2="$(basename -- "$path2")"
		filename1_no_ext="${filename1%.qasm}"
		filename2_no_ext="${filename2%.qasm}"
		path1_unitary="$tmp_dir/${filename1_no_ext}_unitary.qasm"
		path2_unitary="$tmp_dir/${filename2_no_ext}_unitary.qasm"
		;;
	qiskit-hybrid)
		path_optimized="$tmp_dir/${filename_no_ext}_optimize.qasm"
		path_original_unitary="$tmp_dir/${filename_no_ext}_unitary.qasm"
		path_optimized_unitary="$tmp_dir/${filename_no_ext}_optimize_unitary.qasm"
		;;
	owm | tele)
		path_original_unitary="$tmp_dir/${filename_no_ext}_${version}_original_unitary.qasm"
		path_by_meas="$tmp_dir/${filename_no_ext}_${version}_by_meas.qasm"
		path_by_meas_ium="$tmp_dir/${filename_no_ext}_${version}_by_meas_ium.qasm"
		;;
	owm-vs-tele)
		path_original_unitary="$tmp_dir/${filename_no_ext}_original_unitary.qasm"
		path_owm="$tmp_dir/${filename_no_ext}_${version}_owm.qasm"
		path_owm_ium="$tmp_dir/${filename_no_ext}_${version}_owm_ium.qasm"
		path_tele="$tmp_dir/${filename_no_ext}_${version}_tele.qasm"
		path_tele_ium="$tmp_dir/${filename_no_ext}_${version}_tele_ium.qasm"
		;;
	owm-vs-qiskit)
		path_original_unitary="$tmp_dir/${filename_no_ext}_original_unitary.qasm"
		path_optimized="$tmp_dir/${filename_no_ext}_optimize.qasm"
		path_optimized_ium="$tmp_dir/${filename_no_ext}_optimize_ium.qasm"
		path_owm="$tmp_dir/${filename_no_ext}_${version}_owm.qasm"
		path_owm_ium="$tmp_dir/${filename_no_ext}_${version}_owm_ium.qasm"
		;;
	esac
}

render_progress() {
	local label="$1"
	local bar_width=30
	local percent
	local filled
	local pending_width
	local complete
	local pending
	local bar

	if [[ "$progress_enabled" != "true" || "$progress_total" -eq 0 ]]; then
		return
	fi

	percent=$((progress_current * 100 / progress_total))
	filled=$((progress_current * bar_width / progress_total))
	pending_width=$((bar_width - filled))
	printf -v complete "%*s" "$filled" ""
	printf -v pending "%*s" "$pending_width" ""
	bar="${complete// /#}${pending// /-}"

	printf "\rSQbricks long %-14s [%s] %3d%% %d/%d - %.48s\033[K" \
		"$version" "$bar" "$percent" "$progress_current" "$progress_total" "$label" >&2
	progress_line_open="true"
}

begin_progress_case() {
	local name="$1"

	progress_current=$((case_index - 1))
	render_progress "$name"
}

finish_progress_case() {
	local name="$1"

	progress_current="$case_index"
	render_progress "$name"
}

finish_progress() {
	if [[ "$progress_line_open" == "true" ]]; then
		printf "\n" >&2
		progress_line_open="false"
	fi
}

configure_progress() {
	progress_total="$total_cases"
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

case "$version" in
qiskit-hybrid | owm | tele | owm-vs-tele | owm-vs-qiskit)
	echo "Program;Tool;Version;Lift;Opt;CH;CS;CZ;CCZ;CCX;CU1;Gates;Time"
	;;
*)
	echo "Program1;Program2;Tool;Version;Lift;Opt;CH;CS;CZ;CCZ;CCX;CU1;Gates;Time"
	;;
esac

mapfile -t path_originals < <(grep -v '^[[:space:]]*$' "$path_file")
total_cases="${#path_originals[@]}"
configure_progress

for path_original in "${path_originals[@]}"; do
	case_index=$((case_index + 1))
	prepare_paths "$path_original"

	case "$version" in
	sanity-unit)
		name="$filename1_no_ext;$filename2_no_ext"
		begin_progress_case "$name"
		test_unit "$path1" "$path2" "$name"
		;;
	sanity-hybrid | sanity-partial | unit-vs-hybrid | veriqc)
		name="$filename1_no_ext;$filename2_no_ext"
		begin_progress_case "$name"
		test_lifted_pair "$path1" "$path2" "$path1_unitary" "$path2_unitary" "$name"
		;;
	qiskit-hybrid)
		name="$filename_no_ext"
		begin_progress_case "$name"
		test_qiskit_hybrid "$path_original" "$path_optimized" \
			"$path_original_unitary" "$path_optimized_unitary" "$name"
		;;
	owm | tele)
		name="$filename_no_ext"
		begin_progress_case "$name"
		test_transformed_against_unitary "$version" "$path_original" \
			"$path_original_unitary" "$path_by_meas" "$path_by_meas_ium" "$name"
		;;
	owm-vs-tele)
		name="$filename_no_ext"
		begin_progress_case "$name"
		test_owm_vs_tele "$path_original" "$path_original_unitary" \
			"$path_owm" "$path_owm_ium" "$path_tele" "$path_tele_ium" "$name"
		;;
	owm-vs-qiskit)
		name="$filename_no_ext"
		begin_progress_case "$name"
		test_owm_vs_qiskit "$path_original" "$path_original_unitary" \
			"$path_optimized" "$path_optimized_ium" "$path_owm" "$path_owm_ium" "$name"
		;;
	esac

	finish_progress_case "$name"
	echo ""
done

finish_progress
