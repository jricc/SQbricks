(**************************************************************************)
(*  This file is part of SQbricks.                                        *)
(*                                                                        *)
(*  Copyright (C) 2022-2026                                               *)
(*  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  *)
(*  Université Paris-Saclay                                               *)
(*                                                                        *)
(*  you can redistribute it and/or modify it under the terms of the GNU   *)
(*  Lesser General Public License as published by the Free Software       *)
(*  Foundation, version 2.1.                                              *)
(*                                                                        *)
(*  It is distributed in the hope that it will be useful,                 *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *)
(*  GNU Lesser General Public License for more details.                   *)
(*                                                                        *)
(*  See the GNU Lesser General Public License version 2.1                 *)
(*  for more details (enclosed in the file licenses/LGPLv2.1).            *)
(*                                                                        *)
(**************************************************************************)

open Alcotest
open Printf
open SQbricks
module PSS = Path_sum.String
module QS = Qubit.String
module PS = Poly.String
module Ket = Path_sum.Ket
module KS = Ket.String
open Common
module ProgS = Program.String
include Program.Macros
include Rational
module Monome = Poly.Monome
open Parser_get.GetProg

let ( -- ) p1 p2 : Program.t = Program.Sequence (p1, p2)

let test_prog_equiv ?(debug = true) ?(not_equiv = false)
    ?(algo = Equiv.Sequence) ?(equivalence = Equiv.SubCircuit) ?(inputs1 = [])
    ?(inputs2 = []) ?(outputs1 = []) ?(outputs2 = []) ?(meas1 = [])
    ?(meas2 = []) (p1 : Program.t) (p2 : Program.t) () =
  let greeting =
    Equiv.sqv_simple ~debug ~not_equiv ~algo ~equivalence ~inputs1
      ~inputs2 ~outputs1 ~outputs2 ~meas1 ~meas2 p1 p2
  in
  let expected = true in
  check bool
    (sprintf "Test.test_prog_equiv\np1 =\n%s\np2 =\n%s\n" (ProgS.pretty p1)
       (ProgS.pretty p2))
    expected greeting

let test_sqv_result ?(debug = true) ?(algo = Equiv.Sequence)
    ?(equivalence = Equiv.SubCircuit) ?(inputs1 = []) ?(inputs2 = [])
    ?(outputs1 = []) ?(outputs2 = []) ?(meas1 = []) ?(meas2 = [])
    (expected : Equiv.result) (p1 : Program.t) (p2 : Program.t) () =
  let greeting =
    Equiv.sqv ~debug ~algo ~equivalence ~inputs1 ~inputs2 ~outputs1 ~outputs2
      ~meas1 ~meas2 p1 p2
  in
  check string
    (sprintf "Test.test_sqv_result\np1 =\n%s\np2 =\n%s\n"
       (ProgS.pretty p1) (ProgS.pretty p2))
    (Equiv.result_to_string expected)
    (Equiv.result_to_string greeting)

let test_apply_swap_result_returns_swapped_program () =
  (* Different target orders require one explicit swap after the program. *)
  let input = h 0 in
  let expected_output = h 0 -- swap 0 1 in
  match apply_swap_result input [ 0 ] [ 1 ] with
  | Ok output ->
      check string "swapped program" (ProgS.exact expected_output)
        (ProgS.exact output)
  | Error _ -> check bool "swapped program expected" true false

let test_apply_swap_result_reports_invalid_place () =
  (* Only before/after insertion is supported. *)
  match apply_swap_result ~place:"middle" (h 0) [ 0 ] [ 1 ] with
  | Error InvalidSwapPlace -> check bool "invalid place" true true
  | Ok _ | Error DifferentSwapLengths ->
      check bool "invalid place expected" true false

let test_apply_swap_result_reports_different_lengths () =
  (* The two target lists describe a pairwise permutation and must align. *)
  match apply_swap_result (h 0) [ 0 ] [ 1; 2 ] with
  | Error DifferentSwapLengths -> check bool "different lengths" true true
  | Ok _ | Error InvalidSwapPlace ->
      check bool "different lengths expected" true false

let test_inverse_result_returns_inverse_program () =
  (* Inversion reverses the sequence and negates phase-like gates. *)
  let input = h 0 -- u1 1 0 in
  let expected_output = u1 ~s:(-1) 1 0 -- h 0 in
  match Program.inverse_result input with
  | Ok output ->
      check string "inverse program" (ProgS.exact expected_output)
        (ProgS.exact output)
  | Error _ -> check bool "inverse program expected" true false

let test_inverse_result_reports_non_reversible_program () =
  (* Hybrid operations are not reversible unitary programs. *)
  match Program.inverse_result (iq0 0) with
  | Error (Program.NonReversibleProgram _) ->
      check bool "non reversible program" true true
  | Ok _ -> check bool "non reversible program expected" true false

let test_widths_returns_classical_and_quantum_extents () =
  (* Widths are max-index extents, not a full Program.t well-formedness check. *)
  let empty_wc, empty_wq = Program.widths Program.E in
  let wc, wq = Program.widths (h 2 -- m 2 3 -- notC 4) in
  check int "empty classical width" 0 empty_wc;
  check int "empty quantum width" 0 empty_wq;
  check int "classical width" 5 wc;
  check int "quantum width" 3 wq

let test_nb_gate_decomposition_counts_ccz_in_total () =
  (* CCZ is both a specialized gate category and one physical gate in total. *)
  let _, _, _, nb_ccz, _, _, nb_total =
    Program.nb_gate_and_gates_decomposition (ccz 0 1 2)
  in
  check int "ccz count" 1 nb_ccz;
  check int "total gate count" 1 nb_total

let test_execution_ignores_global_phase_targets () =
  (* GP is targetless; a target list is tolerated but does not affect execution. *)
  match
    ( Program.execution_result (gp 1),
      Program.execution_result (Program.Apply (Gates.GP (Q.of_int 1, 1), [], [ 0 ]))
    )
  with
  | Ok without_target, Ok with_target ->
      check string "global phase target ignored" (PSS.exact without_target)
        (PSS.exact with_target)
  | _ -> check bool "global phase target accepted" true false

let test_execution_result_reports_empty_gate_targets () =
  (* H/X/U1 are target gates; only GP is targetless. *)
  let check_rejected name program =
    match Program.execution_result program with
    | Error (Program.EmptyTargetList _) -> check bool name true true
    | _ -> check bool name true false
  in
  check_rejected "h empty target" (Program.Apply (Gates.H, [], []));
  check_rejected "x empty target" (Program.Apply (Gates.X, [], []));
  check_rejected "u1 empty target"
    (Program.Apply (Gates.U1 (Q.of_int 1, 1), [], []))

let test_execution_result_reports_other_errors () =
  (* execution_result classifies the other direct execution failures explicitly. *)
  let check_invalid_gate () =
    match Program.execution_result (cx 0 0) with
    | Error (Program.InvalidGateApplication _) ->
        check bool "invalid gate application" true true
    | _ -> check bool "invalid gate application" true false
  in
  let check_hybrid_program () =
    match Program.execution_result (iq0 0) with
    | Error (Program.HybridProgram _) -> check bool "hybrid program" true true
    | _ -> check bool "hybrid program" true false
  in
  let check_negative_rotation () =
    match
      Program.execution_result (Program.Apply (Gates.U1 (Q.of_int 1, -1), [], [ 0 ]))
    with
    | Error (Program.NegativeRotationExponent _) ->
        check bool "negative rotation exponent" true true
    | _ -> check bool "negative rotation exponent" true false
  in
  let check_non_dyadic_rotation () =
    let angle = Q.make (Z.of_int 1) (Z.of_int 3) in
    let check_rejected name program =
      match Program.execution_result program with
      | Error (Program.NonDyadicRotationAngle _) -> check bool name true true
      | _ -> check bool name true false
    in
    check_rejected "non-dyadic u1 angle"
      (Program.Apply (Gates.U1 (angle, 0), [], [ 0 ]));
    check_rejected "non-dyadic global phase angle"
      (Program.Apply (Gates.GP (angle, 0), [], []))
  in
  let check_negative_angle () =
    match
      Program.execution_result
        (Program.Apply (Gates.U1 (Q.minus_one, 2), [], [ 0 ]))
    with
    | Ok _ -> check bool "negative dyadic angle" true true
    | Error _ -> check bool "negative dyadic angle" true false
  in
  let check_input_state_too_small () =
    match Program.execution_result ~input_state:(Path_sum.ofSize 1) (h 1) with
    | Error (Program.InputStateTooSmall (2, 1)) ->
        check bool "input state too small" true true
    | _ -> check bool "input state too small" true false
  in
  check_invalid_gate ();
  check_hybrid_program ();
  check_negative_rotation ();
  check_non_dyadic_rotation ();
  check_negative_angle ();
  check_input_state_too_small ()

let test_unitary_is_only_a_hybrid_syntax_check () =
  (* Program.unitary does not validate malformed gate applications. *)
  check bool "hybrid operation rejected" false (Program.unitary (iq0 0));
  check bool "malformed unitary-shaped gate accepted" true
    (Program.unitary (Program.Apply (Gates.H, [], [])))

let test_deferred_measurement_reports_not_without_measurement () =
  match To_deferred_measurement.to_deferred_measurements_result (notC 0) with
  | Error (To_deferred_measurement.ClassicalControlWithoutMeasurement 0) ->
      check bool "classical bit without measurement" true true
  | _ -> check bool "classical bit without measurement expected" true false

let test_deferred_measurement_reports_it_without_measurement () =
  match To_deferred_measurement.to_deferred_measurements_result (it 0 (x 1)) with
  | Error (To_deferred_measurement.ClassicalControlWithoutMeasurement 0) ->
      check bool "conditional bit without measurement" true true
  | _ -> check bool "conditional bit without measurement expected" true false

let test_deferred_measurement_reports_invalid_measurement_bit () =
  match To_deferred_measurement.to_deferred_measurements_result (m 0 (-1)) with
  | Error (To_deferred_measurement.InvalidClassicalBit (0, -1)) ->
      check bool "invalid measurement bit" true true
  | _ -> check bool "invalid measurement bit expected" true false

let test_deferred_measurement_translates_simple_condition () =
  match
    To_deferred_measurement.to_deferred_measurements_result
      (m 0 0 -- it 0 (x 1))
  with
  | Ok (program, inits, meas) ->
      check string "deferred program" (ProgS.exact (cx 0 1))
        (ProgS.exact program);
      check string "deferred inits" "[]" (ListBis.string_int inits);
      check string "deferred meas" "[0]" (ListBis.string_int meas)
  | Error _ -> check bool "simple condition expected" true false

let test_deferred_measurement_keeps_all_measured_qubits_unavailable () =
  match
    To_deferred_measurement.to_deferred_measurements_result
      (m 0 0 -- m 1 0 -- x 0)
  with
  | Error
      (To_deferred_measurement.MeasuredQubitUsedAfterMeasurement
        (Program.Apply (Gates.X, [], [ 0 ]))) ->
      check bool "measured qubit remains unavailable" true true
  | _ -> check bool "measured qubit unavailable expected" true false

let test_deferred_measurement_accepts_initial_reset () =
  match To_deferred_measurement.to_deferred_measurements_result (iq0 0 -- x 0) with
  | Ok (program, inits, meas) ->
      check string "initial reset program" (ProgS.exact (x 0))
        (ProgS.exact program);
      check string "initial reset inits" "[0]" (ListBis.string_int inits);
      check string "initial reset meas" "[]" (ListBis.string_int meas)
  | Error _ -> check bool "initial reset expected" true false

let test_deferred_measurement_accepts_fresh_ancilla_after_operation () =
  match
    To_deferred_measurement.to_deferred_measurements_result
      (iq0 1 -- h 1 -- iq0 2 -- h 2)
  with
  | Ok (program, inits, meas) ->
      check string "fresh ancilla program" (ProgS.exact (h 1 -- h 2))
        (ProgS.exact program);
      check string "fresh ancilla inits" "[1;2]"
        (ListBis.string_int (List.sort Int.compare inits));
      check string "fresh ancilla meas" "[]" (ListBis.string_int meas)
  | Error _ -> check bool "fresh ancilla expected" true false

let test_deferred_measurement_rejects_reset_of_used_qubit () =
  match To_deferred_measurement.to_deferred_measurements_result (x 0 -- iq0 0) with
  | Error (To_deferred_measurement.ResetOfUsedQubitUnsupported 0) ->
      check bool "reset of used qubit rejected" true true
  | _ -> check bool "reset of used qubit expected" true false

let test_parser_den_to_k_uses_structural_equality () =
  (* pi / 2^100 is represented internally as 2*pi / 2^101. *)
  let denominator = Z.pow (Z.of_int 2) 100 in
  check int "large power-of-two denominator" 101
    (Parser_help.den_to_k denominator)

let test_parser_barrier_does_not_hide_next_statement () =
  (* OpenQASM barriers are no-ops, not line comments. *)
  let qasm =
    "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nbarrier q[0]; h q[0];\n"
  in
  let lexbuf = Lexing.from_string qasm in
  let parsed = Parser_OpenQASM.program Lexer_OpenQASM.token lexbuf in
  check string "barrier skipped" (ProgS.exact (h 0))
    (ProgS.exact (Program.format parsed))

let test_parser_keeps_distinct_qreg_offsets () =
  (* Named qregs are laid out consecutively in SQbricks indices. *)
  let qasm =
    "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nqreg r[1];\nh r[0];\ncx q[0], r[0];\n"
  in
  let lexbuf = Lexing.from_string qasm in
  let parsed = Parser_OpenQASM.program Lexer_OpenQASM.token lexbuf in
  check string "qreg offsets" (ProgS.exact (h 1 -- cx 0 1))
    (ProgS.exact (Program.format parsed))

let test_parser_accepts_zero_width_qreg_for_compatibility () =
  (* Some QASM libraries contain malformed zero-width qregs; warn and parse. *)
  let qasm =
    "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[0];\nh q[0];\n"
  in
  let lexbuf = Lexing.from_string qasm in
  let parsed = Parser_OpenQASM.program Lexer_OpenQASM.token lexbuf in
  check string "zero-width qreg fallback" (ProgS.exact (h 0))
    (ProgS.exact (Program.format parsed))

let test_parser_accepts_out_of_range_qreg_for_compatibility () =
  (* Out-of-range qreg accesses keep the flat offset+index interpretation. *)
  let qasm =
    "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[1];\nh q[1];\n"
  in
  let lexbuf = Lexing.from_string qasm in
  let parsed = Parser_OpenQASM.program Lexer_OpenQASM.token lexbuf in
  check string "out-of-range qreg fallback" (ProgS.exact (h 1))
    (ProgS.exact (Program.format parsed))

let test_parser_keeps_distinct_creg_offsets () =
  (* Classical registers use the same consecutive-index convention. *)
  let qasm =
    "OPENQASM 2.0;\ninclude \"qelib1.inc\";\nqreg q[2];\ncreg c[1];\ncreg d[1];\nmeasure q[1] -> d[0];\nif (d == 1) x q[0];\n"
  in
  let lexbuf = Lexing.from_string qasm in
  let parsed = Parser_OpenQASM.program Lexer_OpenQASM.token lexbuf in
  check string "creg offsets" (ProgS.exact (m 1 1 -- it 1 (x 0)))
    (ProgS.exact (Program.format parsed))

let test_prog_equiv_qasm ?(debug = true) ?(algo = Equiv.Sequence)
    ?(not_equiv = false) ?(equivalence = Equiv.SubCircuit) (p1' : string)
    (p2' : string) () =
  let greeting =
    let current_dir = Sys.getcwd () in
    printf "Test.test_prog_equiv_qasm, p1' = %s\n" p1';
    printf "Test.test_prog_equiv_qasm, p2' = %s\n" p2';
    printf "Test.test_prog_equiv_qasm, The file is read from the folder: %s\n"
      current_dir;
    let p1 = Program.format (to_prog p1') in
    let p2 = Program.format (to_prog p2') in
    Equiv.sqv_simple ~debug ~not_equiv ~algo ~equivalence p1 p2
  in
  let expected = true in
  check bool
    (sprintf "Test.test_prog_equiv\np1 =\n%s\np2 =\n%s\n" p1' p2')
    expected greeting

let unitary_global_phase =
  [
    ( "rz 1 <> u1 1",
      `Quick,
      test_prog_equiv ~not_equiv:false ~equivalence:GlobalPhase (rz 1 0)
        (u1 1 0) );
    ( "crz 1 <> cu1 1, conditional phase",
      `Quick,
      test_prog_equiv ~not_equiv:true ~equivalence:GlobalPhase (crz 1 0 1)
        (cu1 1 0 1) );
    ( "crz 1 <> h 1 -- cx 0 1 -- h 1, conditional phase",
      `Quick,
      test_prog_equiv ~not_equiv:true ~equivalence:GlobalPhase (crz 1 0 1)
        (h 1 -- cx 0 1 -- h 1) );
    ( "cu1 1 = h 1 -- cx 0 1 -- h 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (cu1 1 0 1) (h 1 -- cx 0 1 -- h 1)
    );
    ( "h 1 -- cx 0 1 -- h 1 = cu1 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase
        (h 1 -- cx 0 1 -- h 1)
        (cu1 1 0 1) );
    ( "h <> x -- h, conditional phase",
      `Quick,
      test_prog_equiv ~not_equiv:true ~equivalence:GlobalPhase (h 0) (x 0 -- h 0)
    );
    ( "x = gp 2 -- rx 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp 2 -- rx 1 0) (x 0) );
    ("h = h", `Quick, test_prog_equiv ~equivalence:GlobalPhase (h 0) (h 0));
    ( "z = hxh",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (h 0 -- x 0 -- h 0) (zz 0) );
    ( "x = hzh",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (h 0 -- zz 0 -- h 0) (x 0) );
    ( "cz = hcxh",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (h 1 -- cx 0 1 -- h 1) (cz 0 1)
    );
    ( "cz = hcrxh",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (h 1 -- cx 0 1 -- h 1) (cz 0 1)
    );
    ( "cx = hczh",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (h 1 -- cz 0 1 -- h 1) (cx 0 1)
    );
    ( "ccx = ccxoq2",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ccxoq2 0 1 2) (ccx 0 1 2) );
    ( "ccx = ccxoq2",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ccxoq2 3 5 0) (ccx 3 5 0) );
    ("x_qb", `Quick, test_prog_equiv ~equivalence:GlobalPhase (x_qb 0) (x 0));
    ( "ccx_qb",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ccx_qb 0 1 2) (ccx 0 1 2) );
    ( "gp 2 -- gp 2 = gp 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp 2 -- gp 2) (gp 1) );
    ( "gp 5 -- gp 5 = gp 4",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp 5 -- gp 5) (gp 4) );
    ( "gp 4 = gp 5 -- gp 5",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp 4) (gp 5 -- gp 5) );
    ( "gp -4 = gp -5 -- gp -5",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp ~s:(-1) 4)
        (gp ~s:(-1) 5 -- gp ~s:(-1) 5) );
    ( "u1 2 -- u1 2 = rx 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (u1 2 0 -- u1 2 0) (u1 1 0) );
    ( "rx 2 -- rx 2 = rx 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rx 1 0) (rx 2 0 -- rx 2 0) );
    ( "rx 5 -- rx 5 = rx 4",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rx 4 0) (rx 5 0 -- rx 5 0) );
    ( "ry 2 -- ry 2 = ry 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ry 2 0 -- ry 2 0) (ry 1 0) );
    ( "ry 5 -- ry 5 = ry 4",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ry 5 0 -- ry 5 0) (ry 4 0) );
    ( "ry (-3) -- ry (-3) = ry (-2)",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase
        (ry ~s:(-1) 3 0 -- ry ~s:(-1) 3 0)
        (ry ~s:(-1) 2 0) );
    ( "rz 2 -- rz 2 = rz 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rz 2 0 -- rz 2 0) (rz 1 0) );
    ( "rz 2 -- gp 3 -- rz 2 -- gp 3 = rz 1 -- gp 2",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase
        (rz 2 0 -- gp 3 -- rz 2 0 -- gp 3)
        (rz 1 0 -- gp 2) );
    ( "h -- h = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (h 0 -- h 0) id );
    ( "x -- x = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (x 0 -- x 0) id );
    ( "x 0 -- ss 0 -- h 0 = x 0 -- ss 0 -- h 0",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase
        (x 0 -- ss 0 -- h 0)
        (x 0 -- ss 0 -- h 0) );
    ( "y -- y = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (y 0 -- y 0) id );
    ( "z -- z = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (zz 0 -- zz 0) id );
    ( "gp 0 -- gp (0) = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp 0 -- gp 0) id );
    ( "gp 2 -- gp (-2) = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp 2 -- gp ~s:(-1) 2) id );
    ( "gp (-5) -- gp 5 = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp ~s:(-1) 5 -- gp 5) id );
    ( "gp (-7/2^19) -- gp 7/2^19 = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp ~s:(-7) 19 -- gp ~s:7 19) id
    );
    ( "rx 0 -- rx 0 = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rx 0 0 -- rx 0 0) id );
    ( "rx 2 -- rx (-2) = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rx 2 0 -- rx ~s:(-1) 2 0) id );
    ( "rx 17/2^2 -- rx (-17/2^2) = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase
        (rx ~s:17 2 0 -- rx ~s:(-17) 2 0)
        id );
    ( "rz 0 -- rz 0 = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rz 0 0 -- rz 0 0) id );
    ( "rz 2 -- rz (-2) = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rz 2 0 -- rz ~s:(-1) 2 0) id );
    ( "ry 0 -- ry 0 = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ry 0 0 -- ry 0 0) id );
    ( "ry 1 -- ry (-1) = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ry 1 0 -- ry ~s:(-1) 1 0) id );
    ( "ry 2 -- ry (-2) = id",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ry 2 0 -- ry ~s:(-1) 2 0) id );
    ( "ry_not 1 = ry -1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ry ~s:(-1) 1 0)
        (x 0 -- ry 1 0 -- x 0) );
    ( "y = gp 2 -- ry 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (y 0) (gp 2 -- ry 1 0) );
    ( "rx 3 = sinv -- ry 3 -- s",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rx 3 0)
        (sinv 0 -- ry 3 0 -- ss 0) );
    ( "rz (-4) = h -- rx (-4) -- h",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rz ~s:(-1) 4 0)
        (h 0 -- rx ~s:(-1) 4 0 -- h 0) );
    ( "rz (4) = u1(2) -- x -- u1(-2) -- x",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rz 4 0)
        (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "rz (4) = gp (-5) -- u1 4",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rz 4 0) (gp ~s:(-1) 5 -- u1 4 0)
    );
    ( "gp 5 -- rz (4) = u1 4",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (gp 5 -- rz 4 0) (u1 4 0) );
    ( "u1 2 0 -- crz (1) = cu1 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (u1 2 0 -- crz 1 0 1) (cu1 1 0 1)
    );
    ( "crz (4) = u1 (-5) --  cu1 4",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (crz 4 0 1)
        (u1 ~s:(-1) 5 0 -- cu1 4 0 1) );
    ( "rz (4) = u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (rz 4 0)
        (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "u1 (4) = gp 5 -- u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (u1 4 0)
        (gp 5 -- u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "crz (4) =  u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (crz 4 0 1) (crzdecomp 4 0 1) );
    ( "cu1 (4) = u1 (5) -- u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (cu1 4 0 1) (cu1decomp 4 0 1) );
    ( "cu1 (-4) = u1 (-5) -- u1(-5) -- cx -- u1(5) -- cx",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (cu1 ~s:(-1) 4 0 1)
        (cu1decomp ~s:(-1) 4 0 1) );
    ( "cu1 (-1) = cu1decomp (-1)",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (cu1 ~s:(-1) 1 0 1)
        (cu1decomp ~s:(-1) 1 0 1) );
    ( "cu1 (1) = cu1decomp (1)",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (cu1 1 0 1) (cu1decomp 1 0 1) );
    ( "cu1 (0) = cu1decomp (0)",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (cu1 0 0 1) (cu1decomp 0 0 1) );
    ( "ccu1 (1) 0 1 2 = cu1decomp 1 0 1 2",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ccu1 1 0 1 2)
        (ccu1decomp 1 0 1 2) );
    ( "ccu1 (-1) 2 3 0 1 = cu1decomp (-1) 2 3 0 1",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ccu1 ~s:(-1) 2 3 0 1)
        (ccu1decomp ~s:(-1) 2 3 0 1) );
    ( "ry 5 = s -- h -- rz 5 -- h -- sinv",
      `Quick,
      test_prog_equiv ~equivalence:GlobalPhase (ry 5 0)
        (ss 0 -- h 0 -- rz 5 0 -- h 0 -- sinv 0) );
    ( "FALSE angle gf2^32",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true ~equivalence:GlobalPhase
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_angle.qasm" );
    ( "FALSE gate gf2^32",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true ~equivalence:GlobalPhase
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice gf2^32",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true ~equivalence:GlobalPhase
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_indice.qasm" );
    ( "FALSE gate grover_15",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true ~equivalence:GlobalPhase
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice grover_15",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true ~equivalence:GlobalPhase
        "benchmarks/buggy/grover_15_veriqbench_FALSE_indice.qasm"
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm" );
    ( "FALSE angle grover_15",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true ~equivalence:GlobalPhase
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_angle.qasm" );
    ( "FALSE angle grover_5",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true ~equivalence:GlobalPhase
        "benchmarks/VeriQbench/combinational/grover/grover_5.qasm"
        "benchmarks/buggy/grover_5_veriqbench_FALSE_angle.qasm" );
  ]

let unitary =
  [
    ("rz 1 <> u1 1", `Quick, test_prog_equiv ~not_equiv:true (rz 1 0) (u1 1 0));
    ( "crz 1 <> cu1 1",
      `Quick,
      test_prog_equiv ~not_equiv:true (crz 1 0 1) (cu1 1 0 1) );
    ( "crz 1 <> h 1 -- cx 0 1 -- h 1",
      `Quick,
      test_prog_equiv ~not_equiv:true (crz 1 0 1) (h 1 -- cx 0 1 -- h 1) );
    ( "cu1 1 = h 1 -- cx 0 1 -- h 1",
      `Quick,
      test_prog_equiv (cu1 1 0 1) (h 1 -- cx 0 1 -- h 1) );
    ( "h 1 -- cx 0 1 -- h 1 = cu1 1",
      `Quick,
      test_prog_equiv (h 1 -- cx 0 1 -- h 1) (cu1 1 0 1) );
    ("h <> x -- h", `Quick, test_prog_equiv ~not_equiv:true (h 0) (x 0 -- h 0));
    ( "seq diff inputs",
      `Quick,
      test_sqv_result ~inputs1:[ 0 ] ~inputs2:[ 0; 1 ] ~outputs1:[ 0 ]
        ~outputs2:[ 0 ] Equiv.NotEquivDiffInputs (h 0) (h 0) );
    ( "seq diff outputs",
      `Quick,
      test_sqv_result ~outputs1:[ 0 ] ~outputs2:[ 0; 1 ] ~inputs1:[ 0 ]
        ~inputs2:[ 0 ] Equiv.NotEquivDiffOutputs (h 0) (h 0) );
    ( "seq diff inputs outputs",
      `Quick,
      test_sqv_result ~inputs1:[ 0; 1 ] ~inputs2:[ 0; 1 ] ~outputs1:[ 0 ]
        ~outputs2:[ 0 ] Equiv.NotEquivDiffInputsOutputs (h 0) (h 0) );
    ( "seq invalid input index",
      `Quick,
      test_sqv_result ~inputs1:[ -1 ] Equiv.ErrorInvalidQubitIndex (h 0) (h 0)
    );
    ( "seq invalid output index",
      `Quick,
      test_sqv_result ~outputs1:[ 1 ] Equiv.ErrorInvalidQubitIndex (h 0) (h 0)
    );
    ( "seq invalid measurement index",
      `Quick,
      test_sqv_result ~meas1:[ 1 ] Equiv.ErrorInvalidQubitIndex (h 0) (h 0) );
    ( "seq full circuit not implemented",
      `Quick,
      test_sqv_result ~equivalence:Equiv.FullCircuit
        Equiv.ErrorFullCircuitNotImplemented (h 0) (h 0) );
    ( "seq both circuits have inits",
      `Quick,
      test_sqv_result ~inputs1:[ 0 ] ~inputs2:[ 0 ] ~outputs1:[ 0 ]
        ~outputs2:[ 0 ] Equiv.ErrorBothCircuitsHaveInits (h 1) (h 1) );
    ( "seq init is not unitary",
      `Quick,
      test_sqv_result Equiv.ErrorCircuitNotUnitary (iq0 0) (h 0) );
    ( "seq invalid gate application",
      `Quick,
      test_sqv_result Equiv.ErrorInvalidProgram (cx 0 0) (h 0) );
    ( "seq empty gate target",
      `Quick,
      test_sqv_result Equiv.ErrorInvalidProgram
        (Program.Apply (Gates.H, [], []))
        (h 0) );
    ( "seq negative u1 exponent",
      `Quick,
      test_sqv_result Equiv.ErrorInvalidProgram
        (Program.Apply (Gates.U1 (Q.of_int 1, -1), [], [ 0 ]))
        (h 0) );
    ( "seq controlled global phase target overlap is invalid",
      `Quick,
      let controlled_global_phase_with_same_target =
        (Program.Apply (Gates.GP (Q.of_int 1, 1), [ 0 ], [ 0 ]))
      in
      test_sqv_result Equiv.ErrorInvalidProgram
        controlled_global_phase_with_same_target
        (h 0) );
    ( "apply swap result ok",
      `Quick,
      test_apply_swap_result_returns_swapped_program );
    ( "apply swap result invalid place",
      `Quick,
      test_apply_swap_result_reports_invalid_place );
    ( "apply swap result different lengths",
      `Quick,
      test_apply_swap_result_reports_different_lengths );
    ( "inverse result ok",
      `Quick,
      test_inverse_result_returns_inverse_program );
    ( "inverse result non reversible",
      `Quick,
      test_inverse_result_reports_non_reversible_program );
    ( "widths returns classical and quantum extents",
      `Quick,
      test_widths_returns_classical_and_quantum_extents );
    ( "nb_gate_and_gates_decomposition counts ccz in total",
      `Quick,
      test_nb_gate_decomposition_counts_ccz_in_total );
    ( "execution ignores global phase targets",
      `Quick,
      test_execution_ignores_global_phase_targets );
    ( "execution_result reports empty gate targets",
      `Quick,
      test_execution_result_reports_empty_gate_targets );
    ( "execution_result reports other execution errors",
      `Quick,
      test_execution_result_reports_other_errors );
    ( "unitary is only a hybrid syntax check",
      `Quick,
      test_unitary_is_only_a_hybrid_syntax_check );
    ( "deferred measurement reports not without measurement",
      `Quick,
      test_deferred_measurement_reports_not_without_measurement );
    ( "deferred measurement reports it without measurement",
      `Quick,
      test_deferred_measurement_reports_it_without_measurement );
    ( "deferred measurement reports invalid measurement bit",
      `Quick,
      test_deferred_measurement_reports_invalid_measurement_bit );
    ( "deferred measurement translates simple condition",
      `Quick,
      test_deferred_measurement_translates_simple_condition );
    ( "deferred measurement keeps all measured qubits unavailable",
      `Quick,
      test_deferred_measurement_keeps_all_measured_qubits_unavailable );
    ( "deferred measurement accepts initial reset",
      `Quick,
      test_deferred_measurement_accepts_initial_reset );
    ( "deferred measurement accepts fresh ancilla after operation",
      `Quick,
      test_deferred_measurement_accepts_fresh_ancilla_after_operation );
    ( "deferred measurement rejects reset of used qubit",
      `Quick,
      test_deferred_measurement_rejects_reset_of_used_qubit );
    ( "parser denominator uses structural equality",
      `Quick,
      test_parser_den_to_k_uses_structural_equality );
    ( "parser barrier does not hide next statement",
      `Quick,
      test_parser_barrier_does_not_hide_next_statement );
    ( "parser keeps distinct qreg offsets",
      `Quick,
      test_parser_keeps_distinct_qreg_offsets );
    ( "parser accepts zero-width qreg for compatibility",
      `Quick,
      test_parser_accepts_zero_width_qreg_for_compatibility );
    ( "parser accepts out-of-range qreg for compatibility",
      `Quick,
      test_parser_accepts_out_of_range_qreg_for_compatibility );
    ( "parser keeps distinct creg offsets",
      `Quick,
      test_parser_keeps_distinct_creg_offsets );
    ( "seq unit vs hybrid",
      `Quick,
      test_prog_equiv ~not_equiv:true (m 0 0) (h 0) );
    ("x = gp 2 -- rx 1", `Quick, test_prog_equiv (gp 2 -- rx 1 0) (x 0));
    ("h = h", `Quick, test_prog_equiv (h 0) (h 0));
    ("z = hxh", `Quick, test_prog_equiv (h 0 -- x 0 -- h 0) (zz 0));
    ("x = hzh", `Quick, test_prog_equiv (h 0 -- zz 0 -- h 0) (x 0));
    ("cz = hcxh", `Quick, test_prog_equiv (h 1 -- cx 0 1 -- h 1) (cz 0 1));
    ("cz = hcrxh", `Quick, test_prog_equiv (h 1 -- cx 0 1 -- h 1) (cz 0 1));
    ("cx = hczh", `Quick, test_prog_equiv (h 1 -- cz 0 1 -- h 1) (cx 0 1));
    ("ccx = ccxoq2", `Quick, test_prog_equiv (ccxoq2 0 1 2) (ccx 0 1 2));
    ("ccx = ccxoq2", `Quick, test_prog_equiv (ccxoq2 3 5 0) (ccx 3 5 0));
    ("x_qb", `Quick, test_prog_equiv (x_qb 0) (x 0));
    ("ccx_qb", `Quick, test_prog_equiv (ccx_qb 0 1 2) (ccx 0 1 2));
    ("gp 2 -- gp 2 = gp 1", `Quick, test_prog_equiv (gp 2 -- gp 2) (gp 1));
    ("gp 5 -- gp 5 = gp 4", `Quick, test_prog_equiv (gp 5 -- gp 5) (gp 4));
    ("gp 4 = gp 5 -- gp 5", `Quick, test_prog_equiv (gp 4) (gp 5 -- gp 5));
    ( "gp -4 = gp -5 -- gp -5",
      `Quick,
      test_prog_equiv (gp ~s:(-1) 4) (gp ~s:(-1) 5 -- gp ~s:(-1) 5) );
    ("u1 2 -- u1 2 = rx 1", `Quick, test_prog_equiv (u1 2 0 -- u1 2 0) (u1 1 0));
    ("rx 2 -- rx 2 = rx 1", `Quick, test_prog_equiv (rx 1 0) (rx 2 0 -- rx 2 0));
    ("rx 5 -- rx 5 = rx 4", `Quick, test_prog_equiv (rx 4 0) (rx 5 0 -- rx 5 0));
    ("ry 2 -- ry 2 = ry 1", `Quick, test_prog_equiv (ry 2 0 -- ry 2 0) (ry 1 0));
    ("ry 5 -- ry 5 = ry 4", `Quick, test_prog_equiv (ry 5 0 -- ry 5 0) (ry 4 0));
    ( "ry (-3) -- ry (-3) = ry (-2)",
      `Quick,
      test_prog_equiv (ry ~s:(-1) 3 0 -- ry ~s:(-1) 3 0) (ry ~s:(-1) 2 0) );
    ("rz 2 -- rz 2 = rz 1", `Quick, test_prog_equiv (rz 2 0 -- rz 2 0) (rz 1 0));
    ( "rz 2 -- gp 3 -- rz 2 -- gp 3 = rz 1 -- gp 2",
      `Quick,
      test_prog_equiv (rz 2 0 -- gp 3 -- rz 2 0 -- gp 3) (rz 1 0 -- gp 2) );
    ("h -- h = id", `Quick, test_prog_equiv (h 0 -- h 0) id);
    ("x -- x = id", `Quick, test_prog_equiv (x 0 -- x 0) id);
    ( "x 0 -- ss 0 -- h 0 = x 0 -- ss 0 -- h 0",
      `Quick,
      test_prog_equiv (x 0 -- ss 0 -- h 0) (x 0 -- ss 0 -- h 0) );
    ("y -- y = id", `Quick, test_prog_equiv (y 0 -- y 0) id);
    ("z -- z = id", `Quick, test_prog_equiv (zz 0 -- zz 0) id);
    ("gp 0 -- gp (0) = id", `Quick, test_prog_equiv (gp 0 -- gp 0) id);
    ("gp 2 -- gp (-2) = id", `Quick, test_prog_equiv (gp 2 -- gp ~s:(-1) 2) id);
    ("gp (-5) -- gp 5 = id", `Quick, test_prog_equiv (gp ~s:(-1) 5 -- gp 5) id);
    ( "gp (-7/2^19) -- gp 7/2^19 = id",
      `Quick,
      test_prog_equiv (gp ~s:(-7) 19 -- gp ~s:7 19) id );
    ("rx 0 -- rx 0 = id", `Quick, test_prog_equiv (rx 0 0 -- rx 0 0) id);
    ( "rx 2 -- rx (-2) = id",
      `Quick,
      test_prog_equiv (rx 2 0 -- rx ~s:(-1) 2 0) id );
    ( "rx 17/2^2 -- rx (-17/2^2) = id",
      `Quick,
      test_prog_equiv (rx ~s:17 2 0 -- rx ~s:(-17) 2 0) id );
    ("rz 0 -- rz 0 = id", `Quick, test_prog_equiv (rz 0 0 -- rz 0 0) id);
    ( "rz 2 -- rz (-2) = id",
      `Quick,
      test_prog_equiv (rz 2 0 -- rz ~s:(-1) 2 0) id );
    ("ry 0 -- ry 0 = id", `Quick, test_prog_equiv (ry 0 0 -- ry 0 0) id);
    ( "ry 1 -- ry (-1) = id",
      `Quick,
      test_prog_equiv (ry 1 0 -- ry ~s:(-1) 1 0) id );
    ( "ry 2 -- ry (-2) = id",
      `Quick,
      test_prog_equiv (ry 2 0 -- ry ~s:(-1) 2 0) id );
    ( "ry_not 1 = ry -1",
      `Quick,
      test_prog_equiv (ry ~s:(-1) 1 0) (x 0 -- ry 1 0 -- x 0) );
    ("y = gp 2 -- ry 1", `Quick, test_prog_equiv (y 0) (gp 2 -- ry 1 0));
    (* \( S^{-1} Ry(k) S = Rx (k) \) *)
    ( "rx 3 = sinv -- ry 3 -- s",
      `Quick,
      test_prog_equiv (rx 3 0) (sinv 0 -- ry 3 0 -- ss 0) );
    (* \( H Rx(k) H = Rz (k) \) *)
    ( "rz (-4) = h -- rx (-4) -- h",
      `Quick,
      test_prog_equiv (rz ~s:(-1) 4 0) (h 0 -- rx ~s:(-1) 4 0 -- h 0) );
    (* \( Rz(k) = U1(k/2) X U1(-k/2) X \) *)
    ( "rz (4) = u1(2) -- x -- u1(-2) -- x",
      `Quick,
      test_prog_equiv (rz 4 0) (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "rz (4) = gp (-5) -- u1 4",
      `Quick,
      test_prog_equiv (rz 4 0) (gp ~s:(-1) 5 -- u1 4 0) );
    ("gp 5 -- rz (4) = u1 4", `Quick, test_prog_equiv (gp 5 -- rz 4 0) (u1 4 0));
    (* CRZ k co ta = CU1 k co ta -- U1 (-k/2) ta  *)
    ( "u1 2 0 -- crz (1) = cu1 1",
      `Quick,
      test_prog_equiv (u1 2 0 -- crz 1 0 1) (cu1 1 0 1) );
    ( "crz (4) = u1 (-5) --  cu1 4",
      `Quick,
      test_prog_equiv (crz 4 0 1) (u1 ~s:(-1) 5 0 -- cu1 4 0 1) );
    (* \( Rz(k) = U1(k/2) X U1(-k/2) X \) *)
    ( "rz (4) = u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv (rz 4 0) (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "u1 (4) = gp 5 -- u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv (u1 4 0) (gp 5 -- u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0)
    );
    ( "crz (4) =  u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv (crz 4 0 1) (crzdecomp 4 0 1) );
    ( "cu1 (4) = u1 (5) -- u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv (cu1 4 0 1) (cu1decomp 4 0 1) );
    ( "cu1 (-4) = u1 (-5) -- u1(-5) -- cx -- u1(5) -- cx",
      `Quick,
      test_prog_equiv (cu1 ~s:(-1) 4 0 1) (cu1decomp ~s:(-1) 4 0 1) );
    ( "cu1 (-1) = cu1decomp (-1)",
      `Quick,
      test_prog_equiv (cu1 ~s:(-1) 1 0 1) (cu1decomp ~s:(-1) 1 0 1) );
    ( "cu1 (1) = cu1decomp (1)",
      `Quick,
      test_prog_equiv (cu1 1 0 1) (cu1decomp 1 0 1) );
    ( "cu1 (0) = cu1decomp (0)",
      `Quick,
      test_prog_equiv (cu1 0 0 1) (cu1decomp 0 0 1) );
    ( "ccu1 (1) 0 1 2 = cu1decomp 1 0 1 2",
      `Quick,
      test_prog_equiv (ccu1 1 0 1 2) (ccu1decomp 1 0 1 2) );
    ( "ccu1 (-1) 2 3 0 1 = cu1decomp (-1) 2 3 0 1",
      `Quick,
      test_prog_equiv (ccu1 ~s:(-1) 2 3 0 1) (ccu1decomp ~s:(-1) 2 3 0 1) );
    (* \( Ry(k) = S H Rz(k) H S^{-1} \) *)
    ( "ry 5 = s -- h -- rz 5 -- h -- sinv",
      `Quick,
      test_prog_equiv (ry 5 0) (ss 0 -- h 0 -- rz 5 0 -- h 0 -- sinv 0) );
    ( "FALSE angle gf2^32",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_angle.qasm" );
    ( "FALSE gate gf2^32",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice gf2^32",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_indice.qasm" );
    ( "FALSE gate grover_15",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice grover_15",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true
        "benchmarks/buggy/grover_15_veriqbench_FALSE_indice.qasm"
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm" );
    ( "FALSE angle grover_15",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_angle.qasm" );
    ( "FALSE angle grover_5",
      `Slow,
      test_prog_equiv_qasm ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_5.qasm"
        "benchmarks/buggy/grover_5_veriqbench_FALSE_angle.qasm" );
  ]

let unitary_into_feynman =
  [
    ("cz_feynman 0 1", `Quick, test_prog_equiv (cz 0 1) (cz_feynman 0 1));
    ( "cz_feynman 1 2 -- h 3",
      `Quick,
      test_prog_equiv (cz 1 2 -- h 3) (cz_feynman 1 2 -- h 3) );
    ( "cz_feynman 0 3 -- h 3",
      `Quick,
      test_prog_equiv (cz 0 3 -- h 3) (cz_feynman 0 3 -- h 3) );
    ( "FALSE cz_feynman 0 3 -- h 3",
      `Quick,
      test_prog_equiv ~not_equiv:true (cs 0 3 -- h 3) (cz_feynman 0 3 -- h 3) );
    ("cs_feynman 1 0", `Quick, test_prog_equiv (cs 1 0) (cs_feynman 1 0));
    ( "cs_feynman 1 2 -- h 1",
      `Quick,
      test_prog_equiv (cs 1 2 -- h 1) (cs_feynman 1 2 -- h 1) );
    ( "cs_feynman 1 2 -- h 1 -- x 3",
      `Quick,
      test_prog_equiv (cs 1 2 -- h 1 -- x 3) (cs_feynman 1 2 -- h 1 -- x 3) );
    ( "ccx_feynman 0 1 2 -- h 1 -- x 3",
      `Quick,
      test_prog_equiv (ccx 0 1 2 -- h 1 -- x 3) (ccx_feynman 0 1 2 -- h 1 -- x 3)
    );
    ( "ccx_feynman 3 1 5 -- h 1 -- x 6",
      `Quick,
      test_prog_equiv (ccx 3 1 5 -- h 1 -- x 6) (ccx_feynman 3 1 5 -- h 1 -- x 6)
    );
    ( "FALSE ccx_feynman 2 1 5 -- h 1 -- x 6",
      `Quick,
      test_prog_equiv ~not_equiv:true
        (ccx 2 1 5 -- h 1 -- x 6)
        (ccx_feynman 3 1 5 -- h 1 -- x 6) );
    ( "cu1decomp 1 1 2 -- h 1 -- x 3",
      `Quick,
      test_prog_equiv (cu1 1 1 2 -- h 1 -- x 3) (cu1decomp 1 1 2 -- h 1 -- x 3)
    );
    ( "cu1decomp 3 1 5 -- h 1 -- x 6",
      `Quick,
      test_prog_equiv (cu1 3 1 5 -- h 1 -- x 6) (cu1decomp 3 1 5 -- h 1 -- x 6)
    );
    ( "FALSE cu1decomp 3 1 5 -- h 1 -- x 6",
      `Quick,
      test_prog_equiv ~not_equiv:true
        (cu1 3 1 5 -- h 0 -- x 6)
        (cu1decomp 3 1 5 -- h 1 -- x 6) );
  ]

let parallel =
  [
    ( "rz 1 <> u1 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~not_equiv:true (rz 1 0) (u1 1 0) );
    ( "crz 1 <> cu1 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~not_equiv:true (crz 1 0 1) (cu1 1 0 1) );
    ( "crz 1 <> h 1 -- cx 0 1 -- h 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~not_equiv:true (crz 1 0 1)
        (h 1 -- cx 0 1 -- h 1) );
    ( "cu1 1 = h 1 -- cx 0 1 -- h 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (cu1 1 0 1) (h 1 -- cx 0 1 -- h 1) );
    ( "h 1 -- cx 0 1 -- h 1 = cu1 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (h 1 -- cx 0 1 -- h 1) (cu1 1 0 1) );
    ( "h <> x -- h",
      `Quick,
      test_prog_equiv ~algo:Parallel ~not_equiv:true (h 0) (x 0 -- h 0) );
    ( "parallel diff inputs",
      `Quick,
      test_sqv_result ~algo:Parallel ~inputs1:[ 0 ] ~inputs2:[ 0; 1 ]
        ~outputs1:[ 0 ] ~outputs2:[ 0 ] Equiv.NotEquivDiffInputs (h 0)
        (h 0) );
    ( "parallel diff outputs",
      `Quick,
      test_sqv_result ~algo:Parallel ~outputs1:[ 0 ] ~outputs2:[ 0; 1 ]
        ~inputs1:[ 0 ] ~inputs2:[ 0 ] Equiv.NotEquivDiffOutputs (h 0) (h 0) );
    ( "parallel diff inputs outputs",
      `Quick,
      test_sqv_result ~algo:Parallel ~inputs1:[ 0; 1 ] ~inputs2:[ 0; 1 ]
        ~outputs1:[ 0 ] ~outputs2:[ 0 ] Equiv.NotEquivDiffInputsOutputs
        (h 0) (h 0) );
    ( "parallel invalid input index",
      `Quick,
      test_sqv_result ~algo:Parallel ~inputs1:[ -1 ]
        Equiv.ErrorInvalidQubitIndex (h 0) (h 0) );
    ( "parallel invalid output index",
      `Quick,
      test_sqv_result ~algo:Parallel ~outputs1:[ 1 ]
        Equiv.ErrorInvalidQubitIndex (h 0) (h 0) );
    ( "parallel invalid measurement index",
      `Quick,
      test_sqv_result ~algo:Parallel ~meas1:[ 1 ] Equiv.ErrorInvalidQubitIndex
        (h 0) (h 0) );
    ( "parallel full circuit not implemented",
      `Quick,
      test_sqv_result ~algo:Parallel ~equivalence:Equiv.FullCircuit
        Equiv.ErrorFullCircuitNotImplemented (h 0) (h 0) );
    ( "parallel init is not unitary",
      `Quick,
      test_sqv_result ~algo:Parallel Equiv.ErrorCircuitNotUnitary (iq0 0) (h 0)
    );
    ( "parallel invalid gate application",
      `Quick,
      test_sqv_result ~algo:Parallel Equiv.ErrorInvalidProgram (cx 0 0) (h 0)
    );
    ( "parallel global phase target is accepted",
      `Quick,
      let global_phase_with_target =
        (Program.Apply (Gates.GP (Q.of_int 1, 1), [], [ 0 ]))
      in
      test_sqv_result ~algo:Parallel Equiv.SubCircuitEquivalent
        global_phase_with_target global_phase_with_target );
    ( "parallel controlled global phase target is accepted",
      `Quick,
      let controlled_global_phase_with_target =
        (Program.Apply (Gates.GP (Q.of_int 1, 1), [ 0 ], [ 1 ]))
      in
      test_sqv_result ~algo:Parallel Equiv.SubCircuitEquivalent
        controlled_global_phase_with_target controlled_global_phase_with_target );
    ( "parallel controlled global phase target overlap is invalid",
      `Quick,
      let controlled_global_phase_with_same_target =
        (Program.Apply (Gates.GP (Q.of_int 1, 1), [ 0 ], [ 0 ]))
      in
      test_sqv_result ~algo:Parallel Equiv.ErrorInvalidProgram
        controlled_global_phase_with_same_target
        (h 0) );
    ( "parallel negative gp exponent",
      `Quick,
      test_sqv_result ~algo:Parallel Equiv.ErrorInvalidProgram
        (Program.Apply (Gates.GP (Q.of_int 1, -1), [], []))
        (h 0) );
    ( "parallel unit vs hybrid",
      `Quick,
      test_prog_equiv ~algo:Parallel ~not_equiv:true (m 0 0) (h 0) );
    ("z <> id", `Quick, test_prog_equiv ~algo:Parallel ~not_equiv:true (zz 0) E);
    ("t <> id", `Quick, test_prog_equiv ~algo:Parallel ~not_equiv:true (tt 0) E);
    ( "x = gp 2 -- rx 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp 2 -- rx 1 0) (x 0) );
    ("h = h", `Quick, test_prog_equiv ~algo:Parallel (h 0) (h 0));
    ( "z = hxh",
      `Quick,
      test_prog_equiv ~algo:Parallel (h 0 -- x 0 -- h 0) (zz 0) );
    ( "x = hzh",
      `Quick,
      test_prog_equiv ~algo:Parallel (h 0 -- zz 0 -- h 0) (x 0) );
    ( "cz = hcxh",
      `Quick,
      test_prog_equiv ~algo:Parallel (h 1 -- cx 0 1 -- h 1) (cz 0 1) );
    ( "cz = hcrxh",
      `Quick,
      test_prog_equiv ~algo:Parallel (h 1 -- cx 0 1 -- h 1) (cz 0 1) );
    ( "cx = hczh",
      `Quick,
      test_prog_equiv ~algo:Parallel (h 1 -- cz 0 1 -- h 1) (cx 0 1) );
    ( "ccx = ccxoq2",
      `Quick,
      test_prog_equiv ~algo:Parallel (ccxoq2 0 1 2) (ccx 0 1 2) );
    ( "ccx = ccxoq2",
      `Quick,
      test_prog_equiv ~algo:Parallel (ccxoq2 3 5 0) (ccx 3 5 0) );
    ("x_qb", `Quick, test_prog_equiv ~algo:Parallel (x_qb 0) (x 0));
    ("ccx_qb", `Quick, test_prog_equiv ~algo:Parallel (ccx_qb 0 1 2) (ccx 0 1 2));
    ( "gp 2 -- gp 2 = gp 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp 2 -- gp 2) (gp 1) );
    ( "gp 5 -- gp 5 = gp 4",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp 5 -- gp 5) (gp 4) );
    ( "gp 4 = gp 5 -- gp 5",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp 4) (gp 5 -- gp 5) );
    ( "gp -4 = gp -5 -- gp -5",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp ~s:(-1) 4)
        (gp ~s:(-1) 5 -- gp ~s:(-1) 5) );
    ( "u1 2 -- u1 2 = rx 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (u1 2 0 -- u1 2 0) (u1 1 0) );
    ( "rx 2 -- rx 2 = rx 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (rx 1 0) (rx 2 0 -- rx 2 0) );
    ( "rx 5 -- rx 5 = rx 4",
      `Quick,
      test_prog_equiv ~algo:Parallel (rx 4 0) (rx 5 0 -- rx 5 0) );
    ( "ry 2 -- ry 2 = ry 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (ry 2 0 -- ry 2 0) (ry 1 0) );
    ( "ry 5 -- ry 5 = ry 4",
      `Quick,
      test_prog_equiv ~algo:Parallel (ry 5 0 -- ry 5 0) (ry 4 0) );
    ( "ry (-3) -- ry (-3) = ry (-2)",
      `Quick,
      test_prog_equiv ~algo:Parallel
        (ry ~s:(-1) 3 0 -- ry ~s:(-1) 3 0)
        (ry ~s:(-1) 2 0) );
    ( "rz 2 -- rz 2 = rz 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (rz 2 0 -- rz 2 0) (rz 1 0) );
    ( "rz 2 -- gp 3 -- rz 2 -- gp 3 = rz 1 -- gp 2",
      `Quick,
      test_prog_equiv ~algo:Parallel
        (rz 2 0 -- gp 3 -- rz 2 0 -- gp 3)
        (rz 1 0 -- gp 2) );
    ("h -- h = id", `Quick, test_prog_equiv ~algo:Parallel (h 0 -- h 0) id);
    ("x -- x = id", `Quick, test_prog_equiv ~algo:Parallel (x 0 -- x 0) id);
    ( "x 0 -- ss 0 -- h 0 = x 0 -- ss 0 -- h 0",
      `Quick,
      test_prog_equiv ~algo:Parallel (x 0 -- ss 0 -- h 0) (x 0 -- ss 0 -- h 0)
    );
    ("y -- y = id", `Quick, test_prog_equiv ~algo:Parallel (y 0 -- y 0) id);
    ("z -- z = id", `Quick, test_prog_equiv ~algo:Parallel (zz 0 -- zz 0) id);
    ( "gp 0 -- gp (0) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp 0 -- gp 0) id );
    ( "gp 2 -- gp (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp 2 -- gp ~s:(-1) 2) id );
    ( "gp (-5) -- gp 5 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp ~s:(-1) 5 -- gp 5) id );
    ( "gp (-7/2^19) -- gp 7/2^19 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp ~s:(-7) 19 -- gp ~s:7 19) id );
    ( "rx 0 -- rx 0 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (rx 0 0 -- rx 0 0) id );
    ( "rx 2 -- rx (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (rx 2 0 -- rx ~s:(-1) 2 0) id );
    ( "rx 17/2^2 -- rx (-17/2^2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (rx ~s:17 2 0 -- rx ~s:(-17) 2 0) id );
    ( "rz 0 -- rz 0 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (rz 0 0 -- rz 0 0) id );
    ( "rz 2 -- rz (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (rz 2 0 -- rz ~s:(-1) 2 0) id );
    ( "ry 0 -- ry 0 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (ry 0 0 -- ry 0 0) id );
    ( "ry 1 -- ry (-1) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (ry 1 0 -- ry ~s:(-1) 1 0) id );
    ( "ry 2 -- ry (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel (ry 2 0 -- ry ~s:(-1) 2 0) id );
    ( "ry_not 1 = ry -1",
      `Quick,
      test_prog_equiv ~algo:Parallel (ry ~s:(-1) 1 0) (x 0 -- ry 1 0 -- x 0) );
    ( "y = gp 2 -- ry 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (y 0) (gp 2 -- ry 1 0) );
    (* \( S^{-1} Ry(k) S = Rx (k) \) *)
    ( "rx 3 = sinv -- ry 3 -- s",
      `Quick,
      test_prog_equiv ~algo:Parallel (rx 3 0) (sinv 0 -- ry 3 0 -- ss 0) );
    (* \( H Rx(k) H = Rz (k) \) *)
    ( "rz (-4) = h -- rx (-4) -- h",
      `Quick,
      test_prog_equiv ~algo:Parallel (rz ~s:(-1) 4 0)
        (h 0 -- rx ~s:(-1) 4 0 -- h 0) );
    (* \( Rz(k) = U1(k/2) X U1(-k/2) X \) *)
    ( "rz (4) = u1(2) -- x -- u1(-2) -- x",
      `Quick,
      test_prog_equiv ~algo:Parallel (rz 4 0)
        (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "rz (4) = gp (-5) -- u1 4",
      `Quick,
      test_prog_equiv ~algo:Parallel (rz 4 0) (gp ~s:(-1) 5 -- u1 4 0) );
    ( "gp 5 -- rz (4) = u1 4",
      `Quick,
      test_prog_equiv ~algo:Parallel (gp 5 -- rz 4 0) (u1 4 0) );
    (* CRZ k co ta = CU1 k co ta -- U1 (-k/2) ta  *)
    ( "u1 2 0 -- crz (1) = cu1 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (u1 2 0 -- crz 1 0 1) (cu1 1 0 1) );
    ( "crz (4) = u1 (-5) --  cu1 4",
      `Quick,
      test_prog_equiv ~algo:Parallel (crz 4 0 1) (u1 ~s:(-1) 5 0 -- cu1 4 0 1)
    );
    (* \( Rz(k) = U1(k/2) X U1(-k/2) X \) *)
    ( "rz (4) = u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv ~algo:Parallel (rz 4 0)
        (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "u1 (4) = gp 5 -- u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv ~algo:Parallel (u1 4 0)
        (gp 5 -- u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "crz (4) =  u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv ~algo:Parallel (crz 4 0 1) (crzdecomp 4 0 1) );
    ( "cu1 (4) = u1 (5) -- u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv ~algo:Parallel (cu1 4 0 1) (cu1decomp 4 0 1) );
    ( "cu1 (-4) = u1 (-5) -- u1(-5) -- cx -- u1(5) -- cx",
      `Quick,
      test_prog_equiv ~algo:Parallel (cu1 ~s:(-1) 4 0 1)
        (cu1decomp ~s:(-1) 4 0 1) );
    ( "cu1 (-1) = cu1decomp (-1)",
      `Quick,
      test_prog_equiv ~algo:Parallel (cu1 ~s:(-1) 1 0 1)
        (cu1decomp ~s:(-1) 1 0 1) );
    ( "cu1 (1) = cu1decomp (1)",
      `Quick,
      test_prog_equiv ~algo:Parallel (cu1 1 0 1) (cu1decomp 1 0 1) );
    ( "cu1 (0) = cu1decomp (0)",
      `Quick,
      test_prog_equiv ~algo:Parallel (cu1 0 0 1) (cu1decomp 0 0 1) );
    ( "ccu1 (1) 0 1 2 = cu1decomp 1 0 1 2",
      `Quick,
      test_prog_equiv ~algo:Parallel (ccu1 1 0 1 2) (ccu1decomp 1 0 1 2) );
    ( "ccu1 (-1) 2 3 0 1 = cu1decomp (-1) 2 3 0 1",
      `Quick,
      test_prog_equiv ~algo:Parallel (ccu1 ~s:(-1) 2 3 0 1)
        (ccu1decomp ~s:(-1) 2 3 0 1) );
    (* \( Ry(k) = S H Rz(k) H S^{-1} \) *)
    ( "ry 5 = s -- h -- rz 5 -- h -- sinv",
      `Quick,
      test_prog_equiv ~algo:Parallel (ry 5 0)
        (ss 0 -- h 0 -- rz 5 0 -- h 0 -- sinv 0) );
    ( "FALSE angle gf2^32",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_angle.qasm" );
    ( "FALSE gate gf2^32",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice gf2^32",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_indice.qasm" );
    ( "FALSE gate grover_15",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice grover_15",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~not_equiv:true
        "benchmarks/buggy/grover_15_veriqbench_FALSE_indice.qasm"
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm" );
    ( "FALSE angle grover_15",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_angle.qasm" );
    ( "FALSE angle grover_5",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_5.qasm"
        "benchmarks/buggy/grover_5_veriqbench_FALSE_angle.qasm" );
  ]

let parallel_global_phase =
  [
    ( "rz 1 <> u1 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase ~not_equiv:false
        (rz 1 0) (u1 1 0) );
    ( "crz 1 <> cu1 1, conditional phase",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase ~not_equiv:true
        (crz 1 0 1) (cu1 1 0 1) );
    ( "crz 1 <> h 1 -- cx 0 1 -- h 1, conditional phase",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase ~not_equiv:true
        (crz 1 0 1)
        (h 1 -- cx 0 1 -- h 1) );
    ( "cu1 1 = h 1 -- cx 0 1 -- h 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (cu1 1 0 1)
        (h 1 -- cx 0 1 -- h 1) );
    ( "h 1 -- cx 0 1 -- h 1 = cu1 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (h 1 -- cx 0 1 -- h 1)
        (cu1 1 0 1) );
    ( "h <> x -- h",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase ~not_equiv:true
        (h 0)
        (x 0 -- h 0) );
    ( "z <> id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase ~not_equiv:true
        (zz 0) E );
    ( "t <> id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase ~not_equiv:true
        (tt 0) E );
    ( "x = gp 2 -- rx 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (gp 2 -- rx 1 0)
        (x 0) );
    ( "h = h",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (h 0) (h 0) );
    ( "z = hxh",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (h 0 -- x 0 -- h 0)
        (zz 0) );
    ( "x = hzh",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (h 0 -- zz 0 -- h 0)
        (x 0) );
    ( "cz = hcxh",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (h 1 -- cx 0 1 -- h 1)
        (cz 0 1) );
    ( "cz = hcrxh",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (h 1 -- cx 0 1 -- h 1)
        (cz 0 1) );
    ( "cx = hczh",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (h 1 -- cz 0 1 -- h 1)
        (cx 0 1) );
    ( "ccx = ccxoq2",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (ccxoq2 0 1 2)
        (ccx 0 1 2) );
    ( "ccx = ccxoq2",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (ccxoq2 3 5 0)
        (ccx 3 5 0) );
    ( "x_qb",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (x_qb 0) (x 0) );
    ( "ccx_qb",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (ccx_qb 0 1 2)
        (ccx 0 1 2) );
    ( "gp 2 -- gp 2 = gp 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (gp 2 -- gp 2)
        (gp 1) );
    ( "gp 5 -- gp 5 = gp 4",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (gp 5 -- gp 5)
        (gp 4) );
    ( "gp 4 = gp 5 -- gp 5",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (gp 4)
        (gp 5 -- gp 5) );
    ( "gp -4 = gp -5 -- gp -5",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (gp ~s:(-1) 4)
        (gp ~s:(-1) 5 -- gp ~s:(-1) 5) );
    ( "u1 2 -- u1 2 = rx 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (u1 2 0 -- u1 2 0)
        (u1 1 0) );
    ( "rx 2 -- rx 2 = rx 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (rx 1 0)
        (rx 2 0 -- rx 2 0) );
    ( "rx 5 -- rx 5 = rx 4",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (rx 4 0)
        (rx 5 0 -- rx 5 0) );
    ( "ry 2 -- ry 2 = ry 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (ry 2 0 -- ry 2 0)
        (ry 1 0) );
    ( "ry 5 -- ry 5 = ry 4",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (ry 5 0 -- ry 5 0)
        (ry 4 0) );
    ( "ry (-3) -- ry (-3) = ry (-2)",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (ry ~s:(-1) 3 0 -- ry ~s:(-1) 3 0)
        (ry ~s:(-1) 2 0) );
    ( "rz 2 -- rz 2 = rz 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (rz 2 0 -- rz 2 0)
        (rz 1 0) );
    ( "rz 2 -- gp 3 -- rz 2 -- gp 3 = rz 1 -- gp 2",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (rz 2 0 -- gp 3 -- rz 2 0 -- gp 3)
        (rz 1 0 -- gp 2) );
    ( "h -- h = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (h 0 -- h 0) id );
    ( "x -- x = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (x 0 -- x 0) id );
    ( "x 0 -- ss 0 -- h 0 = x 0 -- ss 0 -- h 0",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (x 0 -- ss 0 -- h 0)
        (x 0 -- ss 0 -- h 0) );
    ( "y -- y = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (y 0 -- y 0) id );
    ( "z -- z = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (zz 0 -- zz 0) id
    );
    ( "gp 0 -- gp (0) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (gp 0 -- gp 0) id
    );
    ( "gp 2 -- gp (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (gp 2 -- gp ~s:(-1) 2)
        id );
    ( "gp (-5) -- gp 5 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (gp ~s:(-1) 5 -- gp 5)
        id );
    ( "gp (-7/2^19) -- gp 7/2^19 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (gp ~s:(-7) 19 -- gp ~s:7 19)
        id );
    ( "rx 0 -- rx 0 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (rx 0 0 -- rx 0 0)
        id );
    ( "rx 2 -- rx (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (rx 2 0 -- rx ~s:(-1) 2 0)
        id );
    ( "rx 17/2^2 -- rx (-17/2^2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (rx ~s:17 2 0 -- rx ~s:(-17) 2 0)
        id );
    ( "rz 0 -- rz 0 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (rz 0 0 -- rz 0 0)
        id );
    ( "rz 2 -- rz (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (rz 2 0 -- rz ~s:(-1) 2 0)
        id );
    ( "ry 0 -- ry 0 = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (ry 0 0 -- ry 0 0)
        id );
    ( "ry 1 -- ry (-1) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (ry 1 0 -- ry ~s:(-1) 1 0)
        id );
    ( "ry 2 -- ry (-2) = id",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (ry 2 0 -- ry ~s:(-1) 2 0)
        id );
    ( "ry_not 1 = ry -1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (ry ~s:(-1) 1 0)
        (x 0 -- ry 1 0 -- x 0) );
    ( "y = gp 2 -- ry 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (y 0)
        (gp 2 -- ry 1 0) );
    (* \( S^{-1} Ry(k) S = Rx (k) \) *)
    ( "rx 3 = sinv -- ry 3 -- s",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (rx 3 0)
        (sinv 0 -- ry 3 0 -- ss 0) );
    (* \( H Rx(k) H = Rz (k) \) *)
    ( "rz (-4) = h -- rx (-4) -- h",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (rz ~s:(-1) 4 0)
        (h 0 -- rx ~s:(-1) 4 0 -- h 0) );
    (* \( Rz(k) = U1(k/2) X U1(-k/2) X \) *)
    ( "rz (4) = u1(2) -- x -- u1(-2) -- x",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (rz 4 0)
        (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "rz (4) = gp (-5) -- u1 4",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (rz 4 0)
        (gp ~s:(-1) 5 -- u1 4 0) );
    ( "gp 5 -- rz (4) = u1 4",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (gp 5 -- rz 4 0)
        (u1 4 0) );
    (* CRZ k co ta = CU1 k co ta -- U1 (-k/2) ta  *)
    ( "u1 2 0 -- crz (1) = cu1 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (u1 2 0 -- crz 1 0 1)
        (cu1 1 0 1) );
    ( "crz (4) = u1 (-5) --  cu1 4",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (crz 4 0 1)
        (u1 ~s:(-1) 5 0 -- cu1 4 0 1) );
    (* \( Rz(k) = U1(k/2) X U1(-k/2) X \) *)
    ( "rz (4) = u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (rz 4 0)
        (u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "u1 (4) = gp 5 -- u1(5) -- x -- u1(-5) -- x",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (u1 4 0)
        (gp 5 -- u1 5 0 -- x 0 -- u1 ~s:(-1) 5 0 -- x 0) );
    ( "crz (4) =  u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (crz 4 0 1)
        (crzdecomp 4 0 1) );
    ( "cu1 (4) = u1 (5) -- u1(5) -- cx -- u1(-5) -- cx",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (cu1 4 0 1)
        (cu1decomp 4 0 1) );
    ( "cu1 (-4) = u1 (-5) -- u1(-5) -- cx -- u1(5) -- cx",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (cu1 ~s:(-1) 4 0 1) (cu1decomp ~s:(-1) 4 0 1) );
    ( "cu1 (-1) = cu1decomp (-1)",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (cu1 ~s:(-1) 1 0 1) (cu1decomp ~s:(-1) 1 0 1) );
    ( "cu1 (1) = cu1decomp (1)",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (cu1 1 0 1)
        (cu1decomp 1 0 1) );
    ( "cu1 (0) = cu1decomp (0)",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (cu1 0 0 1)
        (cu1decomp 0 0 1) );
    ( "ccu1 (1) 0 1 2 = cu1decomp 1 0 1 2",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (ccu1 1 0 1 2)
        (ccu1decomp 1 0 1 2) );
    ( "ccu1 (-1) 2 3 0 1 = cu1decomp (-1) 2 3 0 1",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase
        (ccu1 ~s:(-1) 2 3 0 1)
        (ccu1decomp ~s:(-1) 2 3 0 1) );
    (* \( Ry(k) = S H Rz(k) H S^{-1} \) *)
    ( "ry 5 = s -- h -- rz 5 -- h -- sinv",
      `Quick,
      test_prog_equiv ~algo:Parallel ~equivalence:GlobalPhase (ry 5 0)
        (ss 0 -- h 0 -- rz 5 0 -- h 0 -- sinv 0) );
    ( "FALSE angle gf2^32",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~equivalence:GlobalPhase
        ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_angle.qasm" );
    ( "FALSE gate gf2^32",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~equivalence:GlobalPhase
        ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice gf2^32",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~equivalence:GlobalPhase
        ~not_equiv:true
        "benchmarks/VeriQbench/combinational/rev_circuit/gf2^32mult_1117_5213.qasm"
        "benchmarks/buggy/gf2^32_mult_veriqbench_FALSE_indice.qasm" );
    ( "FALSE gate grover_15",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~equivalence:GlobalPhase
        ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_gate.qasm" );
    ( "FALSE indice grover_15",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~equivalence:GlobalPhase
        ~not_equiv:true
        "benchmarks/buggy/grover_15_veriqbench_FALSE_indice.qasm"
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm" );
    ( "FALSE angle grover_15",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~equivalence:GlobalPhase
        ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_15.qasm"
        "benchmarks/buggy/grover_15_veriqbench_FALSE_angle.qasm" );
    ( "FALSE angle grover_5",
      `Slow,
      test_prog_equiv_qasm ~algo:Parallel ~equivalence:GlobalPhase
        ~not_equiv:true
        "benchmarks/VeriQbench/combinational/grover/grover_5.qasm"
        "benchmarks/buggy/grover_5_veriqbench_FALSE_angle.qasm" );
  ]

let () =
  Alcotest.run "Symbolic execution"
    [
      ("Global-Phase-Seq-Unit-Eq", unitary_global_phase);
      ("Sub-Cir-Seq-Unit-Eq", unitary);
      ("Sub-Cir-Seq-Unit-Eq Into Feynman", unitary_into_feynman);
      ("Sub-Cir-Par-Unit-Eq", parallel);
      ("Global-Phase-Par-Unit-Eq", parallel_global_phase);
    ]
