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
open Common.Rational

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
   Here zeta_3 = exp(2*pi*i/8) has order 8; the subscript denotes k=3.
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

(* Exact coordinate convention used by these accepted examples:
   root = exp(2*pi*i / 2^k), s = ceil(m/2), without scale simplification.
   Choose the smallest common k >= 1 for phases modulo 1; odd m also needs k >= 3.
   Omit zero coefficients and zero-amplitude states; sort states lexicographically.
   Error cases await an agreed typed contract. *)

(* Checks complete grouped coordinates, including multiplicity and output order.
   For example, amplitude 1/2 on |00> is ([|false; false|], "k=1; s=1; coeffs=[0:1]").
   Do not sort or filter the observed result: those are grouping responsibilities. *)
let check_exact_groups ~path_var_count
    (paths : Simulation.expanded_path list)
    (expected_groups : (bool array * string) list) =
  match Simulation.group_exact ~path_var_count paths with
  | Error _ -> Alcotest.fail "exact grouping must succeed for these complete paths"
  | Ok grouped_paths ->
      let observed_groups =
        List.map
          (fun (grouped_path : Simulation.exact_grouped_path) ->
            ( grouped_path.basis_state,
              Simulation.exact_to_string grouped_path.amplitude ))
          grouped_paths
      in
      Alcotest.check
        (Alcotest.list
           (Alcotest.pair (Alcotest.array Alcotest.bool) Alcotest.string))
        "ordered states and exact coordinates" expected_groups observed_groups

(* U4: T on |1> has one path of phase 1/8, hence amplitude root at k=3. *)
let test_group_exact_eighth_phase () =
  check_exact_groups ~path_var_count:0
    [ { basis_state = [| true |]; phase = 1 /// 8 } ]
    [ ([| true |], "k=3; s=0; coeffs=[1:1]") ]

(* U5: a phase 1/16 on |1> needs a root of order 16, so k=4. *)
let test_group_exact_sixteenth_phase () =
  check_exact_groups ~path_var_count:0
    [ { basis_state = [| true |]; phase = 1 /// 16 } ]
    [ ([| true |], "k=4; s=0; coeffs=[1:1]") ]

(* U9: H then S on |0> gives (|0> + i|1>)/sqrt(2).
   Multiplying (root - root^3)/2 by i gives (root + root^3)/2 at k=3. *)
let test_group_exact_h_s_on_zero () =
  check_exact_groups ~path_var_count:1
    [
      { basis_state = [| false |]; phase = Q.zero };
      { basis_state = [| true |]; phase = 1 /// 4 };
    ]
    [
      ([| false |], "k=3; s=1; coeffs=[1:1; 3:-1]");
      ([| true |], "k=3; s=1; coeffs=[1:1; 3:1]");
    ]

(* U10: H, S, H on |0> gives (1+i)/2 on |0> and (1-i)/2 on |1>.
   All four paths are present; at common k=2, root=i and root^3=-i. *)
let test_group_exact_h_s_h_on_zero () =
  check_exact_groups ~path_var_count:2
    [
      { basis_state = [| false |]; phase = Q.zero };
      { basis_state = [| true |]; phase = Q.zero };
      { basis_state = [| false |]; phase = 1 /// 4 };
      { basis_state = [| true |]; phase = 3 /// 4 };
    ]
    [
      ([| false |], "k=2; s=1; coeffs=[0:1; 1:1]");
      ([| true |], "k=2; s=1; coeffs=[0:1; 1:-1]");
    ]

(* U11: H, T, H on |0> gives (1+root)/2 and (1-root)/2 at k=3.
   The phase 5/8 must reduce to -root rather than remain as exponent 5. *)
let test_group_exact_h_t_h_on_zero () =
  check_exact_groups ~path_var_count:2
    [
      { basis_state = [| false |]; phase = Q.zero };
      { basis_state = [| true |]; phase = Q.zero };
      { basis_state = [| false |]; phase = 1 /// 8 };
      { basis_state = [| true |]; phase = 5 /// 8 };
    ]
    [
      ([| false |], "k=3; s=1; coeffs=[0:1; 1:1]");
      ([| true |], "k=3; s=1; coeffs=[0:1; 1:-1]");
    ]

(* U12: exp(i*pi/4) times HH on |0> retains that global phase.
   The two complex contributions to |1> cancel, leaving only root on |0>. *)
let test_group_exact_hh_with_global_eighth_phase () =
  check_exact_groups ~path_var_count:2
    [
      { basis_state = [| false |]; phase = 1 /// 8 };
      { basis_state = [| true |]; phase = 1 /// 8 };
      { basis_state = [| false |]; phase = 1 /// 8 };
      { basis_state = [| true |]; phase = 5 /// 8 };
    ]
    [ ([| false |], "k=3; s=1; coeffs=[1:2]") ]

(* U13: unreduced HHH on |0> has m=3 and eight paths.
   P=(y1*y2+y2*y3)/2, output=y3; each state's signed sum is 2.
   Keep s=2 and coefficients 2,-2, even though the value is 1/sqrt(2). *)
let test_group_exact_hhh_on_zero () =
  check_exact_groups ~path_var_count:3
    [
      { basis_state = [| false |]; phase = Q.zero }; (* 000 *)
      { basis_state = [| true |]; phase = Q.zero }; (* 001 *)
      { basis_state = [| false |]; phase = Q.zero }; (* 010 *)
      { basis_state = [| true |]; phase = 1 /// 2 }; (* 011 *)
      { basis_state = [| false |]; phase = Q.zero }; (* 100 *)
      { basis_state = [| true |]; phase = Q.zero }; (* 101 *)
      { basis_state = [| false |]; phase = 1 /// 2 }; (* 110 *)
      { basis_state = [| true |]; phase = Q.one }; (* 111 *)
    ]
    [
      ([| false |], "k=3; s=2; coeffs=[1:2; 3:-2]");
      ([| true |], "k=3; s=2; coeffs=[1:2; 3:-2]");
    ]

(* U14: Bell preparation from |00> gives (|00> + |11>)/sqrt(2).
   Two path assignments suffice; the first array element is qubit 0. *)
let test_group_exact_bell () =
  check_exact_groups ~path_var_count:1
    [
      { basis_state = [| false; false |]; phase = Q.zero };
      { basis_state = [| true; true |]; phase = Q.zero };
    ]
    [
      ([| false; false |], "k=3; s=1; coeffs=[1:1; 3:-1]");
      ([| true; true |], "k=3; s=1; coeffs=[1:1; 3:-1]");
    ]

(* U15: independent H gates on |00> produce four states, each of amplitude 1/2.
   This is a complete m=2 expansion with no interference. *)
let test_group_exact_two_independent_h () =
  check_exact_groups ~path_var_count:2
    [
      { basis_state = [| false; false |]; phase = Q.zero };
      { basis_state = [| false; true |]; phase = Q.zero };
      { basis_state = [| true; false |]; phase = Q.zero };
      { basis_state = [| true; true |]; phase = Q.zero };
    ]
    [
      ([| false; false |], "k=1; s=1; coeffs=[0:1]");
      ([| false; true |], "k=1; s=1; coeffs=[0:1]");
      ([| true; false |], "k=1; s=1; coeffs=[0:1]");
      ([| true; true |], "k=1; s=1; coeffs=[0:1]");
    ]

(* U16: the zero-qubit identity has one empty basis state, not zero paths.
   At m=0 its single phase-zero contribution has amplitude 1. *)
let test_group_exact_zero_qubit_identity () =
  check_exact_groups ~path_var_count:0
    [ { basis_state = [||]; phase = Q.zero } ]
    [ ([||], "k=1; s=0; coeffs=[0:1]") ]

(* V1: permute U15's input to 11,01,10,00; require output 00,01,10,11.
   Comparing the unsorted result catches dependence on path insertion order. *)
let test_group_exact_permuted_paths () =
  check_exact_groups ~path_var_count:2
    [
      { basis_state = [| true; true |]; phase = Q.zero };
      { basis_state = [| false; true |]; phase = Q.zero };
      { basis_state = [| true; false |]; phase = Q.zero };
      { basis_state = [| false; false |]; phase = Q.zero };
    ]
    [
      ([| false; false |], "k=1; s=1; coeffs=[0:1]");
      ([| false; true |], "k=1; s=1; coeffs=[0:1]");
      ([| true; false |], "k=1; s=1; coeffs=[0:1]");
      ([| true; true |], "k=1; s=1; coeffs=[0:1]");
    ]

(* V3: phase -1/4 gives -i; its reduced coefficient at k=2 is 1:-1. *)
let test_group_exact_negative_quarter_phase () =
  check_exact_groups ~path_var_count:0
    [ { basis_state = [| true |]; phase = (-1) /// 4 } ]
    [ ([| true |], "k=2; s=0; coeffs=[1:-1]") ]

(* V4: phases 5/4 and -3/4 each give i, like the existing U3 phase 1/4.
   Register the variants separately so both failures remain visible. *)
let test_group_exact_periodic_quarter_phase (phase : Q.t) () =
  check_exact_groups ~path_var_count:0
    [ { basis_state = [| true |]; phase } ]
    [ ([| true |], "k=2; s=0; coeffs=[1:1]") ]

(* V5: phases 1 and -1 each give 1, with minimal k=1 after reduction modulo 1. *)
let test_group_exact_integer_phase (phase : Q.t) () =
  check_exact_groups ~path_var_count:0
    [ { basis_state = [| false |]; phase } ]
    [ ([| false |], "k=1; s=0; coeffs=[0:1]") ]

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
          Alcotest.test_case "U4: phase 1/8" `Quick
            test_group_exact_eighth_phase;
          Alcotest.test_case "U5: phase 1/16" `Quick
            test_group_exact_sixteenth_phase;
          Alcotest.test_case "U9: H then S on |0>" `Quick
            test_group_exact_h_s_on_zero;
          Alcotest.test_case "U10: H then S then H on |0>" `Quick
            test_group_exact_h_s_h_on_zero;
          Alcotest.test_case "U11: H then T then H on |0>" `Quick
            test_group_exact_h_t_h_on_zero;
          Alcotest.test_case "U12: HH with global phase 1/8" `Quick
            test_group_exact_hh_with_global_eighth_phase;
          Alcotest.test_case "U13: HHH on |0>, eight paths" `Quick
            test_group_exact_hhh_on_zero;
          Alcotest.test_case "U14: Bell, two-qubit states" `Quick
            test_group_exact_bell;
          Alcotest.test_case "U15: independent H gates on |00>" `Quick
            test_group_exact_two_independent_h;
          Alcotest.test_case "U16: zero-qubit identity, one path" `Quick
            test_group_exact_zero_qubit_identity;
        ] );
      ( "Exact grouping variants",
        [
          Alcotest.test_case "V1: permuted paths, lexicographic output" `Quick
            test_group_exact_permuted_paths;
          Alcotest.test_case "V3: phase -1/4" `Quick
            test_group_exact_negative_quarter_phase;
          Alcotest.test_case "V4: phase 5/4" `Quick
            (test_group_exact_periodic_quarter_phase (5 /// 4));
          Alcotest.test_case "V4: phase -3/4" `Quick
            (test_group_exact_periodic_quarter_phase ((-3) /// 4));
          Alcotest.test_case "V5: phase 1" `Quick
            (test_group_exact_integer_phase Q.one);
          Alcotest.test_case "V5: phase -1" `Quick
            (test_group_exact_integer_phase ((-1) /// 1));
        ] );
    ]
