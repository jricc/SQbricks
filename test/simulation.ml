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

(* Keeps the experimental simulation checks in a separate executable. *)
let () =
  Alcotest.run "SQbricks simulation"
    [
      ( "Concrete execution",
        [
          Alcotest.test_case "X maps |0> to |1>" `Quick test_x_on_zero;
          Alcotest.test_case "H maps |0> to |+>" `Quick test_h_on_zero;
        ] );
    ]
