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

(* Checks the complete four-path expansion of HH on |0>, before reduction.
   At m=2, |0> gets (1+1)/2=1 and |1> gets (1-1)/2=0.
   Separate arrays check grouping by value; the zero-amplitude state is omitted. *)
let test_group_exact_hh_on_zero () =
  let paths : Simulation.expanded_path list =
    [
      { basis_state = [| false |]; phase = Q.zero }; (* y1=0, y2=0 *)
      { basis_state = [| true |]; phase = Q.zero }; (* y1=0, y2=1 *)
      { basis_state = [| false |]; phase = Q.zero }; (* y1=1, y2=0 *)
      { basis_state = [| true |]; phase = Q.make Z.one (Z.of_int 2) };
      (* y1=1, y2=1 *)
    ]
  in
  match Simulation.group_exact ~path_var_count:2 paths with
  | Ok [ grouped_path ] ->
      Alcotest.check (Alcotest.array Alcotest.bool) "only |0> remains"
        [| false |] grouped_path.basis_state;
      Alcotest.check Alcotest.string "exact amplitude: (1+1)/2"
        "k=1; s=1; coeffs=[0:2]"
        (Simulation.exact_to_string grouped_path.amplitude)
  | Ok _ -> Alcotest.fail "HH must keep only |0> and omit the cancelled |1>"
  | Error _ -> Alcotest.fail "exact grouping must succeed for complete HH paths"

(* Checks the complete two-path expansion of H on |0>, with m=1.
   Each state gets 1/sqrt(2) = (zeta_3 - zeta_3^3)/2.
   The two coefficients encode normalization, although each state has one path. *)
let test_group_exact_h_on_zero () =
  let paths : Simulation.expanded_path list =
    [
      { basis_state = [| false |]; phase = Q.zero };
      { basis_state = [| true |]; phase = Q.zero };
    ]
  in
  match Simulation.group_exact ~path_var_count:1 paths with
  | Ok [ zero_state; one_state ] ->
      Alcotest.check (Alcotest.array Alcotest.bool) "first state is |0>"
        [| false |] zero_state.basis_state;
      Alcotest.check (Alcotest.array Alcotest.bool) "second state is |1>"
        [| true |] one_state.basis_state;
      Alcotest.check Alcotest.string "amplitude of |0>: 1/sqrt(2)"
        "k=3; s=1; coeffs=[1:1; 3:-1]"
        (Simulation.exact_to_string zero_state.amplitude);
      Alcotest.check Alcotest.string "amplitude of |1>: 1/sqrt(2)"
        "k=3; s=1; coeffs=[1:1; 3:-1]"
        (Simulation.exact_to_string one_state.amplitude)
  | Ok _ -> Alcotest.fail "H must produce exactly the states |0> and |1>"
  | Error _ -> Alcotest.fail "exact grouping must succeed for complete H paths"

(* Checks the complete two-path expansion of H on |1>, with m=1.
   The half-turn phase negates both coefficients of the normalization for |1>.
   Opposite amplitudes belong to different states and must not cancel. *)
let test_group_exact_h_on_one () =
  let paths : Simulation.expanded_path list =
    [
      { basis_state = [| false |]; phase = Q.zero };
      { basis_state = [| true |]; phase = Q.make Z.one (Z.of_int 2) };
    ]
  in
  match Simulation.group_exact ~path_var_count:1 paths with
  | Ok [ zero_state; one_state ] ->
      Alcotest.check (Alcotest.array Alcotest.bool) "first state is |0>"
        [| false |] zero_state.basis_state;
      Alcotest.check (Alcotest.array Alcotest.bool) "second state is |1>"
        [| true |] one_state.basis_state;
      Alcotest.check Alcotest.string "amplitude of |0>: 1/sqrt(2)"
        "k=3; s=1; coeffs=[1:1; 3:-1]"
        (Simulation.exact_to_string zero_state.amplitude);
      Alcotest.check Alcotest.string "amplitude of |1>: -1/sqrt(2)"
        "k=3; s=1; coeffs=[1:-1; 3:1]"
        (Simulation.exact_to_string one_state.amplitude)
  | Ok _ -> Alcotest.fail "H must produce exactly the states |0> and |1>"
  | Error _ -> Alcotest.fail "exact grouping must succeed for complete H paths"

(* Runs accepted tests awaiting implementation only through this executable.
   Example: dune build @simulation-exact-pending; failures are expected for now. *)
let () =
  Alcotest.run "SQbricks exact simulation - pending implementation"
    [
      ( "Exact grouping",
        [
          Alcotest.test_case "HH on |0>, complete paths without reduction" `Quick
            test_group_exact_hh_on_zero;
          Alcotest.test_case "H on |0>, odd normalization and two output states"
            `Quick test_group_exact_h_on_zero;
          Alcotest.test_case "H on |1>, odd normalization and opposite signs"
            `Quick test_group_exact_h_on_one;
        ] );
    ]
