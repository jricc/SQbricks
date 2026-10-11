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

open SQbricks

(* Establishes concrete execution before any path enumeration.
   Input: X on the one-qubit basis state |0>.
   Expected: |1>, with zero phase and no path variables. *)
let test_x_on_zero () =
  match Simulation.execute ~input:[| false |] (Program.Macros.x 0) with
  | Error (Simulation.ExecutionError _) ->
      Alcotest.fail "X on |0> must execute successfully"
  | Error (Simulation.ReductionError _) ->
      Alcotest.fail "The path sum for X on |0> must reduce successfully"
  | Ok state ->
      Printf.printf "%s\n%!" (Path_sum.String.exact state);
      Alcotest.check Alcotest.int "one output qubit" 1
        (Array.length state.ket);
      Alcotest.check Alcotest.bool "zero phase" true
        (Poly.equal ~global_phase:false ~wq1:1 ~wq2:1 Poly.zero state.phase);
      Alcotest.check Alcotest.bool "output is |1>" true
        (Qubit.equal ~wq1:1 ~wq2:1 Qubit.One state.ket.(0));
      Alcotest.check (Alcotest.list Alcotest.int) "no path variables" []
        state.path_var

(* Checks that concrete execution retains a coherent superposition.
   Input: H on |0>. Expected: (|0> + |1>) / sqrt(2), represented by
   zero phase, ket |y0> and one path variable. Its count gives the
   normalization 1/sqrt(2); both paths have the same phase. *)
let test_h_on_zero () =
  match Simulation.execute ~input:[| false |] (Program.Macros.h 0) with
  | Error (Simulation.ExecutionError _) ->
      Alcotest.fail "H on |0> must execute successfully"
  | Error (Simulation.ReductionError _) ->
      Alcotest.fail "The path sum for H on |0> must reduce successfully"
  | Ok state ->
      Printf.printf "%s\n%!" (Path_sum.String.exact state);
      Alcotest.check Alcotest.int "one output qubit" 1
        (Array.length state.ket);
      Alcotest.check Alcotest.bool "zero phase" true
        (Poly.equal ~global_phase:false ~wq1:1 ~wq2:1 Poly.zero state.phase);
      (* Use the actual path index: renaming must not change this test. *)
      (match state.path_var with
      | [ path_variable ] ->
          Alcotest.check Alcotest.bool "output is the remaining path variable"
            true
            (Qubit.equal ~wq1:1 ~wq2:1 (Qubit.Var path_variable) state.ket.(0))
      | _ -> Alcotest.fail "H on |0> must retain exactly one path variable")

(* --- Tests for path expansion --- *)

(* Checks that an expanded path list contains a given (state, phase) pair.
   Uses structural equality on bool arrays, which is the intended comparison
   for concrete basis states. *)
let has_expanded_path (paths : Simulation.expanded_path list)
    (expected_state : bool array) (expected_phase : Q.t) : bool =
  List.exists
    (fun path ->
      let open Simulation in
      path.basis_state = expected_state && Q.equal path.phase expected_phase)
    paths

(* Expand X on |0>: no path variables, one path to |1> with zero phase. *)
let test_expand_x_on_zero () =
  match Simulation.execute ~input:[| false |] (Program.Macros.x 0) with
  | Error _ -> Alcotest.fail "X on |0> must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for X on |0>"
      | Ok paths ->
          Alcotest.check Alcotest.int "one path" 1 (List.length paths);
          Alcotest.check Alcotest.bool "path to |1> with phase 0" true
            (has_expanded_path paths [| true |] Q.zero))

(* Expand H on |0>: two paths, |0> and |1>, both with zero phase.
   Each path contributes amplitude 1/sqrt(2); grouping gives (|0>+|1>)/sqrt(2). *)
let test_expand_h_on_zero () =
  match Simulation.execute ~input:[| false |] (Program.Macros.h 0) with
  | Error _ -> Alcotest.fail "H on |0> must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for H on |0>"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |0> with phase 0" true
            (has_expanded_path paths [| false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |1> with phase 0" true
            (has_expanded_path paths [| true |] Q.zero))

(* Expand H on |1>: two paths. |0> has phase 0, |1> has phase 1/2
   (the minus sign: e^(2πi·1/2) = -1). Grouping gives (|0>-|1>)/sqrt(2). *)
let test_expand_h_on_one () =
  match Simulation.execute ~input:[| true |] (Program.Macros.h 0) with
  | Error _ -> Alcotest.fail "H on |1> must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for H on |1>"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |0> with phase 0" true
            (has_expanded_path paths [| false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |1> with phase 1/2" true
            (has_expanded_path paths [| true |] (Q.of_ints 1 2)))

(* --- Multi-qubit expansion tests --- *)

(* X on qubit 0 of a 2-qubit register: |00> -> |10>. *)
let test_expand_x_q0_two_qubits () =
  match
    Simulation.execute ~input:[| false; false |] (Program.Macros.x 0)
  with
  | Error _ -> Alcotest.fail "X on q0 must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for X on q0"
      | Ok paths ->
          Alcotest.check Alcotest.int "one path" 1 (List.length paths);
          Alcotest.check Alcotest.bool "path to |10> with phase 0" true
            (has_expanded_path paths [| true; false |] Q.zero))

(* X on qubit 1 of a 2-qubit register: |00> -> |01>. *)
let test_expand_x_q1_two_qubits () =
  match
    Simulation.execute ~input:[| false; false |] (Program.Macros.x 1)
  with
  | Error _ -> Alcotest.fail "X on q1 must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for X on q1"
      | Ok paths ->
          Alcotest.check Alcotest.int "one path" 1 (List.length paths);
          Alcotest.check Alcotest.bool "path to |01> with phase 0" true
            (has_expanded_path paths [| false; true |] Q.zero))

(* H on qubit 0 of a 2-qubit register: |00> -> (|00> + |10>)/sqrt(2). *)
let test_expand_h_q0_two_qubits () =
  match
    Simulation.execute ~input:[| false; false |] (Program.Macros.h 0)
  with
  | Error _ -> Alcotest.fail "H on q0 must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for H on q0"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |00> with phase 0" true
            (has_expanded_path paths [| false; false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |10> with phase 0" true
            (has_expanded_path paths [| true; false |] Q.zero))

(* H on qubit 1 of a 2-qubit register: |00> -> (|00> + |01>)/sqrt(2). *)
let test_expand_h_q1_two_qubits () =
  match
    Simulation.execute ~input:[| false; false |] (Program.Macros.h 1)
  with
  | Error _ -> Alcotest.fail "H on q1 must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for H on q1"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |00> with phase 0" true
            (has_expanded_path paths [| false; false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |01> with phase 0" true
            (has_expanded_path paths [| false; true |] Q.zero))

(* Bell state: H on q0, CX q0 q1. |00> -> (|00> + |11>)/sqrt(2). *)
let test_expand_bell () =
  let circuit = Program.Macros.(h 0 -- cx 0 1) in
  match Simulation.execute ~input:[| false; false |] circuit with
  | Error _ -> Alcotest.fail "Bell circuit must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for Bell state"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |00> with phase 0" true
            (has_expanded_path paths [| false; false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |11> with phase 0" true
            (has_expanded_path paths [| true; true |] Q.zero))

(* Bell state, reversed: H on q1, CX q1 q0. |00> -> (|00> + |11>)/sqrt(2). *)
let test_expand_bell_reversed () =
  let circuit = Program.Macros.(h 1 -- cx 1 0) in
  match Simulation.execute ~input:[| false; false |] circuit with
  | Error _ -> Alcotest.fail "Bell reversed must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for reversed Bell"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |00> with phase 0" true
            (has_expanded_path paths [| false; false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |11> with phase 0" true
            (has_expanded_path paths [| true; true |] Q.zero))

(* GHZ state (3 qubits): H on q0, CX q0 q1, CX q0 q2.
   |000> -> (|000> + |111>)/sqrt(2). *)
let test_expand_ghz () =
  let circuit = Program.Macros.(h 0 -- cx 0 1 -- cx 0 2) in
  match Simulation.execute ~input:[| false; false; false |] circuit with
  | Error _ -> Alcotest.fail "GHZ circuit must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for GHZ state"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |000> with phase 0" true
            (has_expanded_path paths [| false; false; false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |111> with phase 0" true
            (has_expanded_path paths [| true; true; true |] Q.zero))

(* GHZ state, H on middle qubit: H on q1, CX q1 q0, CX q1 q2.
   |000> -> (|000> + |111>)/sqrt(2). *)
let test_expand_ghz_middle () =
  let circuit = Program.Macros.(h 1 -- cx 1 0 -- cx 1 2) in
  match Simulation.execute ~input:[| false; false; false |] circuit with
  | Error _ -> Alcotest.fail "GHZ middle must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for GHZ middle"
      | Ok paths ->
          Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
          Alcotest.check Alcotest.bool "path to |000> with phase 0" true
            (has_expanded_path paths [| false; false; false |] Q.zero);
          Alcotest.check Alcotest.bool "path to |111> with phase 0" true
            (has_expanded_path paths [| true; true; true |] Q.zero))

(* Keeps the experimental simulation checks in a separate executable. *)
let () =
  Alcotest.run "SQbricks simulation"
    [
      ( "Concrete execution",
        [
          Alcotest.test_case "X maps |0> to |1>" `Quick test_x_on_zero;
          Alcotest.test_case "H maps |0> to |+>" `Quick test_h_on_zero;
        ] );
      ( "Path expansion",
        [
          Alcotest.test_case "expand X on |0>" `Quick test_expand_x_on_zero;
          Alcotest.test_case "expand H on |0>" `Quick test_expand_h_on_zero;
          Alcotest.test_case "expand H on |1>" `Quick test_expand_h_on_one;
        ] );
      ( "Multi-qubit expansion",
        [
          Alcotest.test_case "expand X on q0 (2 qubits)" `Quick
            test_expand_x_q0_two_qubits;
          Alcotest.test_case "expand X on q1 (2 qubits)" `Quick
            test_expand_x_q1_two_qubits;
          Alcotest.test_case "expand H on q0 (2 qubits)" `Quick
            test_expand_h_q0_two_qubits;
          Alcotest.test_case "expand H on q1 (2 qubits)" `Quick
            test_expand_h_q1_two_qubits;
          Alcotest.test_case "expand Bell state" `Quick test_expand_bell;
          Alcotest.test_case "expand Bell reversed" `Quick
            test_expand_bell_reversed;
          Alcotest.test_case "expand GHZ state" `Quick test_expand_ghz;
          Alcotest.test_case "expand GHZ middle" `Quick test_expand_ghz_middle;
        ] );
    ]
