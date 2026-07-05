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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root" || exit 1

usage() {
	cat >&2 <<'EOF'
Usage:
  bash scripts/inspect-sqbricks.sh [options] <left.qasm> <right.qasm>

Modes:
  --mode auto      Use the existing -sq workflow.
  --mode manual    Use -sqv with explicit metadata.

Options:
  --algo seq|par            Equivalence algorithm. Default: par.
  --equiv s|f|g             Equivalence relation. Default: s.
  --inputs1 "[0;1]"         Manual metadata for the first circuit.
  --inputs2 "[0;1]"         Manual metadata for the second circuit.
  --outputs1 "[0]"          Manual metadata for the first circuit.
  --outputs2 "[0]"          Manual metadata for the second circuit.
  --meas1 "[0;1]"           Manual metadata for the first circuit.
  --meas2 "[]"              Manual metadata for the second circuit.
  --out <directory>         Output directory.

Environment:
  SQBRICKS_INSPECT_LATEX_MAX_CHARS
      Maximum source text size for prototype LaTeX export. Default: 30000.
  SQBRICKS_INSPECT_CIRCUIT_MAX_QUBITS
      Maximum qubit count for prototype Quantikz circuit export. Default: 16.
  SQBRICKS_INSPECT_CIRCUIT_MAX_GATES
      Maximum gate count for prototype Quantikz circuit export. Default: 80.

Examples:
  bash scripts/inspect-sqbricks.sh --mode auto a.qasm b.qasm

  bash scripts/inspect-sqbricks.sh --mode manual --algo seq --equiv s \
    --inputs1 "[0;1]" --inputs2 "[0;1]" --outputs1 "[0]" --outputs2 "[0]" \
    --meas1 "[]" --meas2 "[]" a.qasm b.qasm
EOF
}

mode="auto"
algo="par"
equivalence="s"
inputs1="[]"
inputs2="[]"
outputs1="[]"
outputs2="[]"
meas1="[]"
meas2="[]"
out_dir=""
latex_max_chars="${SQBRICKS_INSPECT_LATEX_MAX_CHARS:-30000}"
circuit_max_qubits="${SQBRICKS_INSPECT_CIRCUIT_MAX_QUBITS:-16}"
circuit_max_gates="${SQBRICKS_INSPECT_CIRCUIT_MAX_GATES:-80}"
declare -a qasm_files

while [[ $# -gt 0 ]]; do
	case "$1" in
	--help | -h)
		usage
		exit 0
		;;
	--mode)
		shift
		mode="${1:-}"
		;;
	--algo)
		shift
		algo="${1:-}"
		;;
	--equiv)
		shift
		equivalence="${1:-}"
		;;
	--inputs1)
		shift
		inputs1="${1:-}"
		;;
	--inputs2)
		shift
		inputs2="${1:-}"
		;;
	--outputs1)
		shift
		outputs1="${1:-}"
		;;
	--outputs2)
		shift
		outputs2="${1:-}"
		;;
	--meas1)
		shift
		meas1="${1:-}"
		;;
	--meas2)
		shift
		meas2="${1:-}"
		;;
	--out)
		shift
		out_dir="${1:-}"
		;;
	--*)
		echo "Unknown option: $1" >&2
		usage
		exit 1
		;;
	*)
		qasm_files+=("$1")
		;;
	esac
	shift
done

if [[ "${#qasm_files[@]}" -ne 2 ]]; then
	echo "Expected exactly two QASM files." >&2
	usage
	exit 1
fi

case "$mode" in
auto | manual) ;;
*)
	echo "--mode must be auto or manual." >&2
	exit 1
	;;
esac

case "$algo" in
seq | par) ;;
*)
	echo "--algo must be seq or par." >&2
	exit 1
	;;
esac

case "$equivalence" in
s | f | g) ;;
*)
	echo "--equiv must be s, f, or g." >&2
	exit 1
	;;
esac

case "$latex_max_chars" in
"" | *[!0-9]*)
	echo "SQBRICKS_INSPECT_LATEX_MAX_CHARS must be a non-negative integer." >&2
	exit 1
	;;
esac

case "$circuit_max_qubits" in
"" | *[!0-9]*)
	echo "SQBRICKS_INSPECT_CIRCUIT_MAX_QUBITS must be a non-negative integer." >&2
	exit 1
	;;
esac

case "$circuit_max_gates" in
"" | *[!0-9]*)
	echo "SQBRICKS_INSPECT_CIRCUIT_MAX_GATES must be a non-negative integer." >&2
	exit 1
	;;
esac

left_qasm="${qasm_files[0]}"
right_qasm="${qasm_files[1]}"

if [[ ! -f "$left_qasm" ]]; then
	echo "Missing QASM file: $left_qasm" >&2
	exit 1
fi

if [[ ! -f "$right_qasm" ]]; then
	echo "Missing QASM file: $right_qasm" >&2
	exit 1
fi

if [[ -z "$out_dir" ]]; then
	out_dir="_tmp/inspection/$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$out_dir" || exit 1
commands_file="$out_dir/commands.sh"

{
	printf "#!/usr/bin/env bash\n"
	printf "set -u\n\n"
} >"$commands_file"

write_command() {
	local arg
	for arg in "$@"; do
		printf "%q " "$arg" >>"$commands_file"
	done
	printf "\n" >>"$commands_file"
}

run_and_capture() {
	local name="$1"
	shift
	local stdout_file="$out_dir/$name.stdout"
	local stderr_file="$out_dir/$name.stderr"
	local status_file="$out_dir/$name.status"

	write_command "$@"

	if "$@" >"$stdout_file" 2>"$stderr_file"; then
		printf "0\n" >"$status_file"
		return 0
	fi

	local status=$?
	printf "%s\n" "$status" >"$status_file"
	return "$status"
}

trim_file() {
	local path="$1"
	tr -d '\r' <"$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

is_seconds_value() {
	[[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

extract_equivalence_result() {
	local source_file="$1"

	awk -F'Equiv: ' '
		/^Equiv: / {
			result = $2
			sub(/,.*/, "", result)
			sub(/[[:space:]]+$/, "", result)
			print result
			exit
		}
	' "$source_file"
}

extract_execution_time() {
	local source_file="$1"

	awk '
		/^Execution time = / {
			print $4
			exit
		}
	' "$source_file"
}

equivalence_label() {
	case "$1" in
	s) printf "SubCircuit" ;;
	f) printf "FullCircuit" ;;
	g) printf "GlobalPhase" ;;
	esac
}

extract_final_path_sums() {
	local source_file="$1"
	local target_file="$2"

	awk '
		/^Equiv\.seq, output_state_reduced =$/ {
			capture = "Sequence final path-sum"
			print capture ":"
			next
		}

		/^Equiv\.parallel,$/ {
			parallel_header = 1
			next
		}

		parallel_header == 1 && /^output_path_var_norm1 =$/ {
			capture = "Parallel final path-sum 1"
			parallel_header = 0
			print capture ":"
			next
		}

		parallel_header == 1 && /^output_path_var_norm2 =$/ {
			capture = "Parallel final path-sum 2"
			parallel_header = 0
			print capture ":"
			next
		}

		capture != "" {
			if ($0 == "") {
				print ""
				capture = ""
				next
			}
			print
		}
	' "$source_file" >"$target_file"
}

write_path_sum_latex() {
	local source_file="$1"
	local target_file="$2"
	local char_count

	char_count="$(wc -c <"$source_file")"

	{
		printf "%% Generated by scripts/inspect-sqbricks.sh\n"
		printf "%% Source: %s\n\n" "$source_file"

		if [[ "$char_count" -gt "$latex_max_chars" ]]; then
			printf "\\[\n"
			printf "\\mathrm{Path\\ sum\\ too\\ large\\ for\\ prototype\\ LaTeX\\ export.}\n"
			printf "\\]\n"
			printf "%% Characters: %s\n" "$char_count"
			printf "%% Limit: %s\n" "$latex_max_chars"
			return
		fi

		awk '
			function trim(s) {
				gsub(/\r/, "", s)
				gsub(/^[[:space:]]+/, "", s)
				gsub(/[[:space:]]+$/, "", s)
				return s
			}

			function latex_text(s) {
				gsub(/_/, "\\_", s)
				gsub(/\^/, "\\^{}", s)
				return s
			}

			function latex_vars(s, out, token, var_index) {
				out = ""
				while (match(s, /[xy][0-9]+/)) {
					token = substr(s, RSTART, RLENGTH)
					var_index = substr(token, 2)
					out = out substr(s, 1, RSTART - 1) substr(token, 1, 1) "_{" var_index "}"
					s = substr(s, RSTART + RLENGTH)
				}
				return out s
			}

			function latex_expr(s) {
				s = trim(s)
				sub(/;$/, "", s)
				gsub(/\[/, "", s)
				gsub(/\]/, "", s)
				gsub(/π/, "\\\\pi", s)
				gsub(/[[:space:]]*\*[[:space:]]*/, " \\, \\allowbreak ", s)
				gsub(/\+\+/, " \\\\oplus \\allowbreak ", s)
				gsub(/\./, " \\, \\allowbreak ", s)
				gsub(/[[:space:]]*\+[[:space:]]*/, " + ", s)
				gsub(/[[:space:]]+/, " ", s)
				return latex_vars(s)
			}

			function latex_phase(s) {
				s = trim(s)
				sub(/;$/, "", s)
				sub(/^e\^\{2\.π\.i\./, "", s)
				sub(/\}$/, "", s)
				sub(/^\(/, "", s)
				sub(/\)$/, "", s)
				return latex_expr(s)
			}

			function raw_ket(s) {
				s = trim(s)
				sub(/;$/, "", s)
				sub(/^[[:space:]]*\|/, "", s)
				sub(/>$/, "", s)
				return s
			}

			function latex_path_vars(s) {
				s = trim(s)
				sub(/;$/, "", s)
				if (s == "[]" || s == "") {
					return "\\emptyset"
				}
				gsub(/\[/, "", s)
				gsub(/\]/, "", s)
				gsub(/;/, ", ", s)
				return latex_expr(s)
			}

			function begin_phase_table() {
				print "\\small"
				print "\\begin{longtable}{r p{0.36\\linewidth} r p{0.36\\linewidth}}"
				print "\\multicolumn{4}{l}{\\textbf{p}} \\\\"
			}

			function begin_simple_table(title) {
				print "\\small"
				print "\\begin{longtable}{r p{0.82\\linewidth}}"
				print "\\multicolumn{2}{l}{\\textbf{" title "}} \\\\"
			}

			function end_table() {
				print "\\end{longtable}"
				print ""
			}

			function print_phase_row(left_label, left_expr, right_label, right_expr) {
				if (right_label == "") {
					print "$" left_label "$ & $" left_expr "$ & & \\\\"
				} else {
					print "$" left_label "$ & $" left_expr "$ & $" right_label "$ & $" right_expr "$ \\\\"
				}
			}

			function print_simple_row(label, expr) {
				print "$" label "$ & $" expr "$ \\\\"
			}

			function print_phase_table(line,    phase, n, monomes, i, right_label, right_expr) {
				phase = latex_phase(line)
				begin_phase_table()
				if (phase == "" || phase == "0") {
					print_phase_row("0", "0", "", "")
				} else {
					n = split(phase, monomes, / \+ /)
					for (i = 1; i <= n; i += 2) {
						right_label = ""
						right_expr = ""
						if (i + 1 <= n) {
							right_label = i
							right_expr = trim(monomes[i + 1])
						}
						print_phase_row(i - 1, trim(monomes[i]), right_label, right_expr)
					}
				}
				end_table()
			}

			function print_ket_table(line,    ket, n, qubits, i) {
				ket = raw_ket(line)
				begin_simple_table("f")
				if (ket == "") {
					print_simple_row("0", "\\emptyset")
				} else {
					n = split(ket, qubits, ",")
					for (i = 1; i <= n; i++) {
						print_simple_row(i - 1, latex_expr(qubits[i]))
					}
				}
				end_table()
			}

			function print_path_var_table(line) {
				begin_simple_table("Y")
				print_simple_row("Y", latex_path_vars(line))
				end_table()
			}

			function print_block_label(label) {
				print "\\noindent\\textbf{" latex_text(label) "}\\par"
				print ""
			}

			/^ps =$/ {
				next
			}

			/^[^[:space:]].*path-sum.*:$/ {
				label = $0
				sub(/:$/, "", label)
				print_block_label(label)
				next
			}

			/^[[:space:]]*phase = / {
				line = $0
				sub(/^[[:space:]]*phase = /, "", line)
				print_phase_table(line)
				next
			}

			/^[[:space:]]*ket = / {
				line = $0
				sub(/^[[:space:]]*ket = /, "", line)
				print_ket_table(line)
				next
			}

			/^[[:space:]]*path_var = / {
				line = $0
				sub(/^[[:space:]]*path_var = /, "", line)
				print_path_var_table(line)
				next
			}
		' "$source_file"
	} >"$target_file"
}

write_path_sums_latex_document() {
	local target_file="$1"

	{
		printf "%s\n" "\\documentclass{article}"
		printf "%s\n" "\\usepackage[margin=1in]{geometry}"
		printf "%s\n" "\\usepackage{amsmath,amssymb,longtable}"
		printf "%s\n" "\\begin{document}"
		printf "%s\n" "\\raggedbottom"
		printf "%s\n" "\\setlength{\\tabcolsep}{3pt}"
		printf "%s\n" "\\subsection*{Left circuit}"
		printf "%s\n" "\\input{pathsum-left.tex}"
		printf "%s\n" "\\subsection*{Right circuit}"
		printf "%s\n" "\\input{pathsum-right.tex}"
		printf "%s\n" "\\subsection*{Final path-sums}"
		printf "%s\n" "\\input{final-path-sums.tex}"
		printf "%s\n" "\\end{document}"
	} >"$target_file"
}

write_circuit_latex() {
	local qasm_file="$1"
	local target_file="$2"

	# Small inspection renderer only: it handles simple OpenQASM 2 and does not
	# try to replace a complete QASM parser.
	awk \
		-v qasm_file="$qasm_file" \
		-v max_qubits="$circuit_max_qubits" \
		-v max_gates="$circuit_max_gates" '
		function trim(s) {
			gsub(/\r/, "", s)
			gsub(/^[[:space:]]+/, "", s)
			gsub(/[[:space:]]+$/, "", s)
			return s
		}

		function count_char(s, c, i, n) {
			n = 0
			for (i = 1; i <= length(s); i++) {
				if (substr(s, i, 1) == c) {
					n++
				}
			}
			return n
		}

		function tex_text(s) {
			gsub(/\\/, "\\\\textbackslash{}", s)
			gsub(/_/, "\\\\_", s)
			gsub(/\^/, "\\\\^{}", s)
			return s
		}

		function tex_param(s) {
			s = trim(s)
			gsub(/pi/, "\\\\pi", s)
			gsub(/PI/, "\\\\pi", s)
			gsub(/\*/, "", s)
			return s
		}

		function gate_label(base, params, conditional, label) {
			if (base == "h") label = "H"
			else if (base == "x") label = "X"
			else if (base == "y") label = "Y"
			else if (base == "z") label = "Z"
			else if (base == "s") label = "S"
			else if (base == "sdg" || base == "sinv") label = "S^{\\dagger}"
			else if (base == "t") label = "T"
			else if (base == "tdg" || base == "tinv") label = "T^{\\dagger}"
			else if (base == "u1") label = "U_1"
			else if (base == "u2") label = "U_2"
			else if (base == "u3" || base == "u") label = "U"
			else if (base == "rz") label = "R_z"
			else if (base == "rx") label = "R_x"
			else if (base == "ry") label = "R_y"
			else if (base == "reset") label = "\\lvert0\\rangle"
			else label = "\\mathrm{" tex_text(base) "}"

			if (params != "") {
				label = label "(" tex_param(params) ")"
			}
			if (conditional) {
				label = "\\mathrm{if}\\;" label
			}
			return label
		}

		function qasm_arg_index(arg, name, index_text) {
			arg = trim(arg)
			gsub(/[[:space:]]/, "", arg)
			if (arg !~ /^[A-Za-z_][A-Za-z0-9_]*\[[0-9]+\]$/) {
				return -1
			}
			name = arg
			sub(/\[.*/, "", name)
			index_text = arg
			sub(/^.*\[/, "", index_text)
			sub(/\].*$/, "", index_text)
			if (!(name in qoffset)) {
				return -1
			}
			return qoffset[name] + index_text
		}

		function record_gate(line, conditional, raw, gate_part, arg_text, base, params, n, args, i, idx) {
			raw = line
			sub(/;$/, "", raw)
			gate_part = raw
			sub(/[[:space:]].*$/, "", gate_part)
			arg_text = raw
			sub(/^[^[:space:]]+[[:space:]]*/, "", arg_text)

			base = tolower(gate_part)
			sub(/\(.*/, "", base)
			params = ""
			if (gate_part ~ /\(/) {
				params = gate_part
				sub(/^[^(]*\(/, "", params)
				sub(/\).*$/, "", params)
			}

			gate_count++
			gate_name[gate_count] = base
			gate_params[gate_count] = params
			gate_raw[gate_count] = raw
			gate_conditional[gate_count] = conditional
			gate_arity[gate_count] = 0

			n = split(arg_text, args, ",")
			for (i = 1; i <= n; i++) {
				idx = qasm_arg_index(args[i])
				if (idx >= 0) {
					gate_arity[gate_count]++
					gate_arg[gate_count, gate_arity[gate_count]] = idx
					if (idx > max_seen_qubit) {
						max_seen_qubit = idx
					}
				}
			}

			if (gate_arity[gate_count] == 0) {
				simplified_count++
			}
		}

		function set_single_gate(col, label, target) {
			target = gate_arg[col, 1]
			if (target >= 0) {
				cell[target, col] = "\\gate{" label "}"
			}
		}

		function set_controlled_gate(col, label, control, target) {
			control = gate_arg[col, 1]
			target = gate_arg[col, 2]
			cell[control, col] = "\\ctrl{" target - control "}"
			cell[target, col] = "\\gate{" label "}"
		}

		function render_gate(col, base, label, controlled_base, control1, control2, target) {
			base = gate_name[col]
			label = gate_label(base, gate_params[col], gate_conditional[col])

			if ((base == "cx" || base == "cnot") && gate_arity[col] == 2) {
				control1 = gate_arg[col, 1]
				target = gate_arg[col, 2]
				cell[control1, col] = "\\ctrl{" target - control1 "}"
				cell[target, col] = "\\targ{}"
			} else if (base == "ccx" && gate_arity[col] == 3) {
				control1 = gate_arg[col, 1]
				control2 = gate_arg[col, 2]
				target = gate_arg[col, 3]
				cell[control1, col] = "\\ctrl{" target - control1 "}"
				cell[control2, col] = "\\ctrl{" target - control2 "}"
				cell[target, col] = "\\targ{}"
			} else if (base == "ccz" && gate_arity[col] == 3) {
				control1 = gate_arg[col, 1]
				control2 = gate_arg[col, 2]
				target = gate_arg[col, 3]
				cell[control1, col] = "\\ctrl{" target - control1 "}"
				cell[control2, col] = "\\ctrl{" target - control2 "}"
				cell[target, col] = "\\gate{Z}"
			} else if (base == "swap" && gate_arity[col] == 2) {
				control1 = gate_arg[col, 1]
				target = gate_arg[col, 2]
				cell[control1, col] = "\\swap{" target - control1 "}"
				cell[target, col] = "\\targX{}"
			} else if (base == "measure" && gate_arity[col] == 1) {
				cell[gate_arg[col, 1], col] = "\\meter{}"
			} else if (base ~ /^c/ && gate_arity[col] == 2) {
				controlled_base = base
				sub(/^c/, "", controlled_base)
				label = gate_label(controlled_base, gate_params[col], gate_conditional[col])
				set_controlled_gate(col, label)
			} else if (gate_arity[col] == 1) {
				set_single_gate(col, label)
			} else {
				cell[0, col] = "\\gate{\\mathrm{unsupported}}"
			}
		}

		{
			line = $0
			sub(/\/\/.*/, "", line)
			line = trim(line)
			if (line == "") next
			# Custom gate bodies are definitions, not top-level circuit steps.
			if (definition_depth > 0) {
				if (waiting_definition_brace && line ~ /^\{/) {
					waiting_definition_brace = 0
					next
				}
				definition_depth += count_char(line, "{") - count_char(line, "}")
				if (definition_depth < 0) {
					definition_depth = 0
				}
				next
			}
			if (line ~ /^opaque[[:space:]]/) {
				next
			}
			if (line ~ /^(gate|def)[[:space:]]/) {
				definition_depth += count_char(line, "{") - count_char(line, "}")
				if (definition_depth < 0) {
					definition_depth = 0
				}
				if (definition_depth == 0 && line !~ /\}/) {
					definition_depth = 1
					waiting_definition_brace = 1
				}
				next
			}
			if (line ~ /^OPENQASM/ || line ~ /^include / || line ~ /^creg / || line ~ /^barrier /) next
			if (line ~ /^qreg /) {
				decl = line
				sub(/^qreg[[:space:]]+/, "", decl)
				sub(/;$/, "", decl)
				name = decl
				sub(/\[.*/, "", name)
				size = decl
				sub(/^.*\[/, "", size)
				sub(/\].*$/, "", size)
				if (size ~ /^[0-9]+$/) {
					qoffset[name] = qubit_count
					qubit_count += size
				}
				next
			}
			conditional = 0
			if (line ~ /^measure /) {
				sub(/[[:space:]]*->[[:space:]]*.*/, ";", line)
				sub(/^measure[[:space:]]+/, "measure ", line)
			} else if (line ~ /^if[[:space:]]*\(/) {
				conditional = 1
				sub(/^if[[:space:]]*\([^)]*\)[[:space:]]*/, "", line)
			}
			if (line ~ /;$/) {
				record_gate(line, conditional)
			}
		}

		END {
			if (max_seen_qubit == "") {
				max_seen_qubit = -1
			}

			print "% Generated by scripts/inspect-sqbricks.sh"
			print "% Source: " qasm_file
			print ""

			if (qubit_count == 0 && max_seen_qubit >= 0) {
				qubit_count = max_seen_qubit + 1
			}
			if (qubit_count <= 0) {
				print "\\noindent\\textit{No OpenQASM 2 qreg declaration was found.}"
				exit
			}
			# Large circuits become unreadable in this prototype export.
			if (qubit_count > max_qubits || gate_count > max_gates) {
				print "\\noindent\\textit{Circuit too large for prototype Quantikz export.}"
				print ""
				print "% Qubits: " qubit_count
				print "% Gates: " gate_count
				print "% Qubit limit: " max_qubits
				print "% Gate limit: " max_gates
				exit
			}

			if (simplified_count > 0) {
				print "% Some unsupported operations were simplified in the drawing."
			}

			for (col = 1; col <= gate_count; col++) {
				for (q = 0; q < qubit_count; q++) {
					cell[q, col] = "\\qw"
				}
				render_gate(col)
			}

			print "\\begin{quantikz}[row sep={0.18cm,between origins}, column sep=0.24cm]"
			for (q = 0; q < qubit_count; q++) {
				printf "\\lstick{$q_{%d}$}", q
				for (col = 1; col <= gate_count; col++) {
					printf " & %s", cell[q, col]
				}
				print " & \\qw \\\\"
			}
			print "\\end{quantikz}"
		}
	' "$qasm_file" >"$target_file"
}

write_circuits_latex_document() {
	local target_file="$1"

	{
		printf "%s\n" "\\documentclass{article}"
		printf "%s\n" "\\usepackage[margin=1in]{geometry}"
		printf "%s\n" "\\usepackage{amsmath}"
		printf "%s\n" "\\usepackage{tikz}"
		printf "%s\n" "\\usetikzlibrary{quantikz}"
		printf "%s\n" "\\begin{document}"
		printf "%s\n" "\\subsection*{Left circuit}"
		printf "%s\n" "\\input{circuit-left.tex}"
		printf "%s\n" "\\subsection*{Right circuit}"
		printf "%s\n" "\\input{circuit-right.tex}"
		printf "%s\n" "\\end{document}"
	} >"$target_file"
}

compile_latex_document() {
	local tex_file="$1"
	local log_file="$2"
	local tex_dir
	local tex_base

	tex_dir="$(dirname "$tex_file")"
	tex_base="$(basename "$tex_file")"

	printf "( cd %q && pdflatex -interaction=nonstopmode -halt-on-error %q )\n" \
		"$tex_dir" "$tex_base" >>"$commands_file"

	if ! command -v pdflatex >/dev/null 2>&1; then
		printf "pdflatex not found. PDF generation skipped.\n" >"$log_file"
		return 127
	fi

	(cd "$tex_dir" && pdflatex -interaction=nonstopmode -halt-on-error "$tex_base") \
		>"$log_file" 2>&1
	return $?
}

{
	printf "mode=%s\n" "$mode"
	printf "algo=%s\n" "$algo"
	printf "equiv=%s\n" "$equivalence"
	printf "left_qasm=%s\n" "$left_qasm"
	printf "right_qasm=%s\n" "$right_qasm"
	printf "inputs1=%s\n" "$inputs1"
	printf "inputs2=%s\n" "$inputs2"
	printf "outputs1=%s\n" "$outputs1"
	printf "outputs2=%s\n" "$outputs2"
	printf "meas1=%s\n" "$meas1"
	printf "meas2=%s\n" "$meas2"
	printf "sqv_verbose=true\n"
	printf "latex_max_chars=%s\n" "$latex_max_chars"
	printf "circuit_max_qubits=%s\n" "$circuit_max_qubits"
	printf "circuit_max_gates=%s\n" "$circuit_max_gates"
} >"$out_dir/metadata.txt"

declare -a sqv_command
if [[ "$mode" == "auto" ]]; then
	sqv_command=(
		dune exec -- ./bin/main.exe
		-sq "$algo" "$equivalence" "$left_qasm" "$right_qasm" true
	)
else
	sqv_command=(
		dune exec -- ./bin/main.exe
		-sqv "$algo" "$equivalence" "$left_qasm" "$right_qasm"
		"$inputs1" "$inputs2" "$outputs1" "$outputs2" "$meas1" "$meas2" true
	)
fi

run_and_capture sqv "${sqv_command[@]}"
sqv_status=$?

run_and_capture pathsum-left dune exec -- ./bin/main.exe -qasm_to_ps "$left_qasm"
pathsum_left_status=$?

run_and_capture pathsum-right dune exec -- ./bin/main.exe -qasm_to_ps "$right_qasm"
pathsum_right_status=$?

sqv_output="$(trim_file "$out_dir/sqv.stdout")"
sqv_error="$(trim_file "$out_dir/sqv.stderr")"
sqv_result="$(extract_equivalence_result "$out_dir/sqv.stdout")"
sqv_time="$(extract_execution_time "$out_dir/sqv.stdout")"
report_file="$out_dir/report.txt"
final_path_sums_file="$out_dir/final-path-sums.txt"
pathsum_left_latex="$out_dir/pathsum-left.tex"
pathsum_right_latex="$out_dir/pathsum-right.tex"
final_path_sums_latex="$out_dir/final-path-sums.tex"
path_sums_latex="$out_dir/path-sums.tex"
path_sums_pdf="$out_dir/path-sums.pdf"
path_sums_pdf_log="$out_dir/path-sums-pdf.log"
circuit_left_latex="$out_dir/circuit-left.tex"
circuit_right_latex="$out_dir/circuit-right.tex"
circuits_latex="$out_dir/circuits.tex"
circuits_pdf="$out_dir/circuits.pdf"
circuits_pdf_log="$out_dir/circuits-pdf.log"

if [[ "$sqv_status" -ne 0 ]]; then
	equivalence_result="command failed"
	equivalence_detail="SQbricks exited with status $sqv_status."
elif [[ -n "$sqv_result" ]]; then
	equivalence_result="$sqv_result"
	if [[ -n "$sqv_time" ]]; then
		equivalence_detail="SQbricks returned $sqv_result in ${sqv_time}s."
	else
		equivalence_detail="SQbricks returned $sqv_result."
	fi
elif is_seconds_value "$sqv_output"; then
	equivalence_result="Equivalent"
	equivalence_detail="SQbricks proved equivalence in ${sqv_output}s."
elif [[ -n "$sqv_output" ]]; then
	equivalence_result="$sqv_output"
	equivalence_detail="SQbricks returned a non-timing result."
else
	equivalence_result="no output"
	equivalence_detail="SQbricks exited successfully but did not print a result."
fi

extract_final_path_sums "$out_dir/sqv.stdout" "$final_path_sums_file"
if [[ ! -s "$final_path_sums_file" ]]; then
	printf "No final path-sum section was found in SQbricks verbose output.\n" \
		>"$final_path_sums_file"
fi

write_path_sum_latex "$out_dir/pathsum-left.stdout" "$pathsum_left_latex"
write_path_sum_latex "$out_dir/pathsum-right.stdout" "$pathsum_right_latex"
write_path_sum_latex "$final_path_sums_file" "$final_path_sums_latex"
write_path_sums_latex_document "$path_sums_latex"
compile_latex_document "$path_sums_latex" "$path_sums_pdf_log"
path_sums_pdf_status=$?

write_circuit_latex "$left_qasm" "$circuit_left_latex"
write_circuit_latex "$right_qasm" "$circuit_right_latex"
write_circuits_latex_document "$circuits_latex"
compile_latex_document "$circuits_latex" "$circuits_pdf_log"
circuits_pdf_status=$?

{
	printf "sqv_status=%s\n" "$sqv_status"
	printf "pathsum_left_status=%s\n" "$pathsum_left_status"
	printf "pathsum_right_status=%s\n" "$pathsum_right_status"
	printf "equivalence_result=%s\n" "$equivalence_result"
	printf "final_path_sums=%s\n" "$final_path_sums_file"
	printf "pathsum_left_latex=%s\n" "$pathsum_left_latex"
	printf "pathsum_right_latex=%s\n" "$pathsum_right_latex"
	printf "final_path_sums_latex=%s\n" "$final_path_sums_latex"
	printf "path_sums_latex=%s\n" "$path_sums_latex"
	printf "path_sums_pdf=%s\n" "$path_sums_pdf"
	printf "path_sums_pdf_status=%s\n" "$path_sums_pdf_status"
	printf "path_sums_pdf_log=%s\n" "$path_sums_pdf_log"
	printf "circuit_left_latex=%s\n" "$circuit_left_latex"
	printf "circuit_right_latex=%s\n" "$circuit_right_latex"
	printf "circuits_latex=%s\n" "$circuits_latex"
	printf "circuits_pdf=%s\n" "$circuits_pdf"
	printf "circuits_pdf_status=%s\n" "$circuits_pdf_status"
	printf "circuits_pdf_log=%s\n" "$circuits_pdf_log"
	printf "report=%s\n" "$report_file"
	printf "sqv_stdout=%s\n" "$out_dir/sqv.stdout"
	printf "sqv_stderr=%s\n" "$out_dir/sqv.stderr"
	printf "pathsum_left_stdout=%s\n" "$out_dir/pathsum-left.stdout"
	printf "pathsum_right_stdout=%s\n" "$out_dir/pathsum-right.stdout"
	printf "commands=%s\n" "$commands_file"
} >"$out_dir/summary.txt"

{
	printf "SQbricks inspection report\n"
	printf "\n"
	printf "Mode: %s\n" "$mode"
	printf "Algorithm: %s\n" "$algo"
	printf "Equivalence relation: %s\n" "$(equivalence_label "$equivalence")"
	printf "Left QASM: %s\n" "$left_qasm"
	printf "Right QASM: %s\n" "$right_qasm"
	printf "\n"
	printf "Equivalence result: %s\n" "$equivalence_result"
	printf "Detail: %s\n" "$equivalence_detail"
	printf "Command status: %s\n" "$sqv_status"
	printf "Final path-sums: %s\n" "$final_path_sums_file"
	printf "Final path-sums LaTeX: %s\n" "$final_path_sums_latex"
	printf "Path-sums PDF status: %s\n" "$path_sums_pdf_status"
	printf "Path-sums PDF: %s\n" "$path_sums_pdf"
	printf "Path-sums PDF log: %s\n" "$path_sums_pdf_log"
	printf "Circuits LaTeX: %s\n" "$circuits_latex"
	printf "Circuits PDF status: %s\n" "$circuits_pdf_status"
	printf "Circuits PDF: %s\n" "$circuits_pdf"
	printf "Circuits PDF log: %s\n" "$circuits_pdf_log"
	if [[ -n "$sqv_error" ]]; then
		printf "Command stderr: %s\n" "$sqv_error"
	fi
	printf "\n"
	printf "Generated files:\n"
	printf -- "- Commands: %s\n" "$commands_file"
	printf -- "- Raw SQV stdout: %s\n" "$out_dir/sqv.stdout"
	printf -- "- Raw SQV stderr: %s\n" "$out_dir/sqv.stderr"
	printf -- "- Left path-sum: %s\n" "$out_dir/pathsum-left.stdout"
	printf -- "- Right path-sum: %s\n" "$out_dir/pathsum-right.stdout"
	printf -- "- Final path-sums: %s\n" "$final_path_sums_file"
	printf -- "- Left path-sum LaTeX: %s\n" "$pathsum_left_latex"
	printf -- "- Right path-sum LaTeX: %s\n" "$pathsum_right_latex"
	printf -- "- Final path-sums LaTeX: %s\n" "$final_path_sums_latex"
	printf -- "- Combined path-sums LaTeX: %s\n" "$path_sums_latex"
	printf -- "- Combined path-sums PDF: %s\n" "$path_sums_pdf"
	printf -- "- Combined path-sums PDF log: %s\n" "$path_sums_pdf_log"
	printf -- "- Left circuit LaTeX: %s\n" "$circuit_left_latex"
	printf -- "- Right circuit LaTeX: %s\n" "$circuit_right_latex"
	printf -- "- Combined circuits LaTeX: %s\n" "$circuits_latex"
	printf -- "- Combined circuits PDF: %s\n" "$circuits_pdf"
	printf -- "- Combined circuits PDF log: %s\n" "$circuits_pdf_log"
} >"$report_file"

echo "Inspection written to $out_dir"
echo "Equivalence: $equivalence_result"
echo "Report: $report_file"

if [[ "$sqv_status" -ne 0 ]]; then
	exit "$sqv_status"
fi
if [[ "$pathsum_left_status" -ne 0 ]]; then
	exit "$pathsum_left_status"
fi
if [[ "$pathsum_right_status" -ne 0 ]]; then
	exit "$pathsum_right_status"
fi

exit 0
