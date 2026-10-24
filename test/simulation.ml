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
    (fun (path : Simulation.expanded_path) ->
      let open Simulation in
      path.basis_state = expected_state && Q.equal path.phase expected_phase)
    paths

(* Counts the expanded paths leading to a basis state with a given phase.
   Two paths to the same state with phases 0 and 1/2 contribute opposite
   signs and cancel; equal phases reinforce. For example, in the
   interference test below, |100> has one path with phase 0 and one with
   phase 1/2. *)
let count_expanded_paths (paths : Simulation.expanded_path list)
    (expected_state : bool array) (expected_phase : Q.t) : int =
  List.fold_left
    (fun count (path : Simulation.expanded_path) ->
      let open Simulation in
      if
        path.basis_state = expected_state
        && Q.equal path.phase expected_phase
      then count + 1
      else count)
    0 paths

(* Finds the summed amplitude of a basis state in a grouped path list.
   Returns [None] when no path leads to the state. The type annotation
   disambiguates the [basis_state] and [amplitude] labels, shared with
   [expanded_path] and [exact_grouped_path]. *)
let amplitude_of (paths : Simulation.grouped_path list)
    (basis_state : bool array) : Complex.t option =
  List.find_map
    (fun (path : Simulation.grouped_path) ->
      if path.basis_state = basis_state then Some path.amplitude else None)
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

(* --- Interference test --- *)

(* H on q0, H on q1, CX q0 q1, H on q0, CX q1 q2 on |000>.
   The reduced path sum keeps three path variables: the ket is
   [|y2; y0++y1; y0++y1>] and the phase is 1/2*y0*y2. Expansion gives
   eight paths, two per basis state. |100> and |111> receive opposite
   phases (0 and 1/2) and cancel; |000> and |011> reinforce, giving
   (|000>+|011>)/sqrt(2). H;H on one qubit would not do: the reducer's
   HH rule already cancels it to |0> with no path variable. *)
let test_expand_interference () =
  let circuit = Program.Macros.(h 0 -- h 1 -- cx 0 1 -- h 0 -- cx 1 2) in
  match Simulation.execute ~input:[| false; false; false |] circuit with
  | Error _ -> Alcotest.fail "interference circuit must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ ->
          Alcotest.fail "expand must succeed for the interference circuit"
      | Ok paths ->
          Alcotest.check Alcotest.int "eight paths" 8 (List.length paths);
          (* |000> and |011>: two paths each, both with phase 0, so the
             contributions add up to probability 1/2 each. *)
          Alcotest.check Alcotest.int "two phase-0 paths to |000>" 2
            (count_expanded_paths paths [| false; false; false |] Q.zero);
          Alcotest.check Alcotest.int "two phase-0 paths to |011>" 2
            (count_expanded_paths paths [| false; true; true |] Q.zero);
          (* |100> and |111>: two paths each with phases 0 and 1/2, so the
             contributions cancel and the probability is 0. *)
          Alcotest.check Alcotest.int "one phase-0 path to |100>" 1
            (count_expanded_paths paths [| true; false; false |] Q.zero);
          Alcotest.check Alcotest.int "one phase-1/2 path to |100>" 1
            (count_expanded_paths paths [| true; false; false |]
               (Q.of_ints 1 2));
          Alcotest.check Alcotest.int "one phase-0 path to |111>" 1
            (count_expanded_paths paths [| true; true; true |] Q.zero);
          Alcotest.check Alcotest.int "one phase-1/2 path to |111>" 1
            (count_expanded_paths paths [| true; true; true |]
               (Q.of_ints 1 2)))

(* --- Grouping and interference --- *)

(* Groups the expansion of a path sum into one amplitude per basis state.
   [state] is the reduced path sum, [paths] its expansion; the number of
   path variables fixes the per-path normalization 1/2^(m/2). *)
let group_paths (state : Path_sum.t) (paths : Simulation.expanded_path list) :
    Simulation.grouped_path list =
  Simulation.group ~path_var_count:(List.length state.path_var) paths

(* Group X on |0>: one path, so one entry |1> with amplitude 1. *)
let test_group_x_on_zero () =
  match Simulation.execute ~input:[| false |] (Program.Macros.x 0) with
  | Error _ -> Alcotest.fail "X on |0> must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for X on |0>"
      | Ok paths ->
          let grouped = group_paths state paths in
          Alcotest.check Alcotest.int "one basis state" 1
            (List.length grouped);
          (match amplitude_of grouped [| true |] with
          | None -> Alcotest.fail "grouped paths must contain |1>"
          | Some amplitude ->
              Alcotest.check (Alcotest.float 1e-9) "amplitude of |1> is 1" 1.
                (amplitude.Complex.re);
              Alcotest.check (Alcotest.float 1e-9) "imaginary part is 0" 0.
                (amplitude.Complex.im)))

(* Group H on |0>: two paths to distinct states, each amplitude 1/sqrt(2). *)
let test_group_h_on_zero () =
  match Simulation.execute ~input:[| false |] (Program.Macros.h 0) with
  | Error _ -> Alcotest.fail "H on |0> must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed for H on |0>"
      | Ok paths ->
          let grouped = group_paths state paths in
          Alcotest.check Alcotest.int "two basis states" 2
            (List.length grouped);
          let inv_sqrt2 = 1. /. Float.sqrt 2. in
          (match amplitude_of grouped [| false |] with
          | None -> Alcotest.fail "grouped paths must contain |0>"
          | Some amplitude ->
              Alcotest.check (Alcotest.float 1e-9) "amplitude of |0>" inv_sqrt2
                (amplitude.Complex.re));
          (match amplitude_of grouped [| true |] with
          | None -> Alcotest.fail "grouped paths must contain |1>"
          | Some amplitude ->
              Alcotest.check (Alcotest.float 1e-9) "amplitude of |1>" inv_sqrt2
                (amplitude.Complex.re)))

(* Group the interference circuit: two paths per basis state. |100> and
   |111> cancel (destructive interference, amplitude 0); |000> and |011>
   reinforce (constructive interference, amplitude 1/sqrt(2)). *)
let test_group_interference () =
  let circuit = Program.Macros.(h 0 -- h 1 -- cx 0 1 -- h 0 -- cx 1 2) in
  match Simulation.execute ~input:[| false; false; false |] circuit with
  | Error _ -> Alcotest.fail "interference circuit must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ ->
          Alcotest.fail "expand must succeed for the interference circuit"
      | Ok paths ->
          let grouped = group_paths state paths in
          Alcotest.check Alcotest.int "four basis states" 4
            (List.length grouped);
          let inv_sqrt2 = 1. /. Float.sqrt 2. in
          let check_amplitude basis_state expected =
            match amplitude_of grouped basis_state with
            | None ->
                Alcotest.fail "grouped paths must contain the basis state"
            | Some amplitude ->
                Alcotest.check (Alcotest.float 1e-9) "amplitude real part"
                  expected (amplitude.Complex.re);
                Alcotest.check (Alcotest.float 1e-9) "amplitude imaginary part"
                  0. (amplitude.Complex.im)
          in
          check_amplitude [| false; false; false |] inv_sqrt2;
          check_amplitude [| false; true; true |] inv_sqrt2;
          check_amplitude [| true; false; false |] 0.;
          check_amplitude [| true; true; true |] 0.)

(* Group H then S on |0>: the first test with a complex amplitude.
   S = U1(1/4) adds phase 1/4*y0 to the path variable of H, so the path
   to |1> gets amplitude i/sqrt(2): S.H|0> = (|0> + i|1>)/sqrt(2). The
   reducer is blocked (Omega needs the path variable absent from the ket,
   Case needs two path variables), so the reduced path sum keeps one path
   variable: ket |y0>, phase 1/4*y0. *)
let test_group_h_s_on_zero () =
  let circuit = Program.Macros.(h 0 -- ss 0) in
  match Simulation.execute ~input:[| false |] circuit with
  | Error _ -> Alcotest.fail "H then S on |0> must execute successfully"
  | Ok state -> (
      match state.path_var with
      | [ path_variable ] ->
          (* Use the actual path index: renaming must not change this test. *)
          Alcotest.check Alcotest.bool "output is the remaining path variable"
            true
            (Qubit.equal ~wq1:1 ~wq2:1 (Qubit.Var path_variable) state.ket.(0));
          let expected_phase =
            Poly.to_poly
              (Poly.Monome.Prod
                 ( Poly.Monome.Scal (Q.of_ints 1 4),
                   Poly.Monome.Qubit (Qubit.Var path_variable) ))
          in
          Alcotest.check Alcotest.bool "phase is 1/4*y0" true
            (Poly.equal ~global_phase:false ~wq1:1 ~wq2:1 expected_phase
               state.phase);
          (* Parenthesized so the trailing [_] case binds to the path_var
             match below, not to this inner match. *)
          (match Simulation.expand state with
          | Error _ ->
              Alcotest.fail "expand must succeed for H then S on |0>"
          | Ok paths ->
              Alcotest.check Alcotest.int "two paths" 2 (List.length paths);
              Alcotest.check Alcotest.bool "path to |0> with phase 0" true
                (has_expanded_path paths [| false |] Q.zero);
              Alcotest.check Alcotest.bool "path to |1> with phase 1/4" true
                (has_expanded_path paths [| true |] (Q.of_ints 1 4));
              let grouped = group_paths state paths in
              Alcotest.check Alcotest.int "two basis states" 2
                (List.length grouped);
              let inv_sqrt2 = 1. /. Float.sqrt 2. in
              (match amplitude_of grouped [| false |] with
              | None -> Alcotest.fail "grouped paths must contain |0>"
              | Some amplitude ->
                  Alcotest.check (Alcotest.float 1e-9)
                    "amplitude of |0> is real" inv_sqrt2
                    (amplitude.Complex.re);
                  Alcotest.check (Alcotest.float 1e-9)
                    "imaginary part of |0> is 0" 0. (amplitude.Complex.im);
                  Alcotest.check (Alcotest.float 1e-9)
                    "probability of |0> is 1/2" 0.5
                    (Complex.norm2 amplitude));
              (match amplitude_of grouped [| true |] with
              | None -> Alcotest.fail "grouped paths must contain |1>"
              | Some amplitude ->
                  Alcotest.check (Alcotest.float 1e-9) "real part of |1> is 0"
                    0. (amplitude.Complex.re);
                  Alcotest.check (Alcotest.float 1e-9)
                    "amplitude of |1> is i/sqrt(2)" inv_sqrt2
                    (amplitude.Complex.im);
                  Alcotest.check (Alcotest.float 1e-9)
                    "probability of |1> is 1/2" 0.5
                    (Complex.norm2 amplitude)))
      | _ ->
          Alcotest.fail "H then S on |0> must retain exactly one path variable")

(* Probabilities of the interference circuit: the squared moduli of the
   grouped amplitudes are 1/2, 1/2, 0 and 0, and sum to 1. These are the
   values displayed by the -simulate_group command. *)
let test_probabilities_interference () =
  let circuit = Program.Macros.(h 0 -- h 1 -- cx 0 1 -- h 0 -- cx 1 2) in
  match Simulation.execute ~input:[| false; false; false |] circuit with
  | Error _ -> Alcotest.fail "interference circuit must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ ->
          Alcotest.fail "expand must succeed for the interference circuit"
      | Ok paths ->
          let grouped = group_paths state paths in
          let probability_of basis_state =
            match amplitude_of grouped basis_state with
            | None -> Alcotest.fail "grouped paths must contain the basis state"
            | Some amplitude -> Complex.norm2 amplitude
          in
          Alcotest.check (Alcotest.float 1e-9) "probability of |000> is 1/2"
            0.5 (probability_of [| false; false; false |]);
          Alcotest.check (Alcotest.float 1e-9) "probability of |011> is 1/2"
            0.5 (probability_of [| false; true; true |]);
          Alcotest.check (Alcotest.float 1e-9) "probability of |100> is 0"
            0. (probability_of [| true; false; false |]);
          Alcotest.check (Alcotest.float 1e-9) "probability of |111> is 0"
            0. (probability_of [| true; true; true |]);
          let total =
            List.fold_left
              (fun acc (path : Simulation.grouped_path) ->
                acc +. Complex.norm2 path.amplitude)
              0. grouped
          in
          Alcotest.check (Alcotest.float 1e-9) "probabilities sum to 1" 1.
            total)

(* --- Exact grouping (group_exact, exact_is_zero, exact_equal) --- *)

(* Builds a synthetic expanded path. [expanded_path] is a public record, so
   the exact-grouping tests feed [group_exact] directly, without running a
   circuit. *)
let synthetic_path (basis_state : bool array) (phase : Q.t) :
    Simulation.expanded_path =
  { basis_state = basis_state; phase = phase }

(* Executes [circuit] on [input], expands its path sum and groups it
   exactly. *)
let exact_group_of_circuit ?max_root_exponent (input : bool array)
    (circuit : Program.t) :
    (Simulation.exact_grouped_path list, Simulation.exact_error) result =
  match Simulation.execute ~input circuit with
  | Error _ -> Alcotest.fail "circuit must execute successfully"
  | Ok state -> (
      match Simulation.expand state with
      | Error _ -> Alcotest.fail "expand must succeed"
      | Ok paths ->
          Simulation.group_exact ?max_root_exponent
            ~path_var_count:(List.length state.path_var) paths)

(* Asserts that [group_exact] succeeds and returns its grouped paths. *)
let must_group_exact ?max_root_exponent ~(path_var_count : int)
    (paths : Simulation.expanded_path list) :
    Simulation.exact_grouped_path list =
  match Simulation.group_exact ?max_root_exponent ~path_var_count paths with
  | Ok grouped -> grouped
  | Error Simulation.PhaseNotDyadic ->
      Alcotest.fail "group_exact: unexpected non-dyadic phase"
  | Error Simulation.RootExponentTooLarge ->
      Alcotest.fail "group_exact: unexpected root exponent overflow"

(* Finds the exact amplitude of a basis state in an exact grouping.
   Returns [None] when no path leads to the state. *)
let exact_amplitude_of (grouped : Simulation.exact_grouped_path list)
    (basis_state : bool array) : Simulation.exact_amplitude option =
  List.find_map
    (fun (path : Simulation.exact_grouped_path) ->
      let open Simulation in
      if path.basis_state = basis_state then Some path.amplitude else None)
    grouped

(* Asserts that the exact grouping contains [basis_state] and returns its
   amplitude. *)
let must_exact_amplitude (grouped : Simulation.exact_grouped_path list)
    (basis_state : bool array) : Simulation.exact_amplitude =
  match exact_amplitude_of grouped basis_state with
  | Some amplitude -> amplitude
  | None -> Alcotest.fail "grouped paths must contain the basis state"

(* The exact amplitude of a single synthetic path with the given phase. *)
let synthetic_amplitude (phase : Q.t) : Simulation.exact_amplitude =
  must_exact_amplitude
    (must_group_exact ~path_var_count:0 [ synthetic_path [| false |] phase ])
    [| false |]

(* X on |0>: m = 0, null phase, amplitude 1. *)
let test_group_exact_x_on_zero () =
  match exact_group_of_circuit [| false |] (Program.Macros.x 0) with
  | Error _ -> Alcotest.fail "group_exact must succeed for X on |0>"
  | Ok grouped ->
      Alcotest.check Alcotest.int "one basis state" 1 (List.length grouped);
      let amp = must_exact_amplitude grouped [| true |] in
      Alcotest.check Alcotest.bool "amplitude of |1> is 1" true
        (Simulation.exact_equal amp (synthetic_amplitude Q.zero));
      Alcotest.check Alcotest.bool "amplitude of |1> is not zero" false
        (Simulation.exact_is_zero amp)

(* S on |1>: m = 0, phase 1/4, amplitude i = e^(2πi·1/4). *)
let test_group_exact_s_on_one () =
  match exact_group_of_circuit [| true |] (Program.Macros.ss 0) with
  | Error _ -> Alcotest.fail "group_exact must succeed for S on |1>"
  | Ok grouped ->
      Alcotest.check Alcotest.int "one basis state" 1 (List.length grouped);
      let amp = must_exact_amplitude grouped [| true |] in
      Alcotest.check Alcotest.bool "amplitude of |1> is i" true
        (Simulation.exact_equal amp (synthetic_amplitude (Q.of_ints 1 4)));
      Alcotest.check Alcotest.bool "amplitude of |1> is not 1" false
        (Simulation.exact_equal amp (synthetic_amplitude Q.zero))

(* H on |0>: m = 1 (odd normalization). Both paths have phase 0, so each
   amplitude is 1/sqrt(2) = 2^(-1) * sqrt(2) with sqrt(2) = zeta_8 +
   zeta_8^(-1). The same value is built with even m = 2 and phases 1/8 and
   7/8: 2^(-1) * (zeta_8 + zeta_8^7) = 2^(-1) * sqrt(2). *)
let test_group_exact_h_on_zero_odd_normalization () =
  match exact_group_of_circuit [| false |] (Program.Macros.h 0) with
  | Error _ -> Alcotest.fail "group_exact must succeed for H on |0>"
  | Ok grouped ->
      Alcotest.check Alcotest.int "two basis states" 2 (List.length grouped);
      let amp_zero = must_exact_amplitude grouped [| false |] in
      let amp_one = must_exact_amplitude grouped [| true |] in
      Alcotest.check Alcotest.bool "both amplitudes are equal" true
        (Simulation.exact_equal amp_zero amp_one);
      let even_construction =
        must_exact_amplitude
          (must_group_exact ~path_var_count:2
             [ synthetic_path [| false |] (Q.of_ints 1 8);
               synthetic_path [| false |] (Q.of_ints 7 8) ])
          [| false |]
      in
      Alcotest.check Alcotest.bool "odd normalization gives 1/sqrt(2)" true
        (Simulation.exact_equal amp_zero even_construction)

(* Scale alignment: amplitude 2 built with m = 0 (two paths, phase 0)
   equals amplitude 2 built with m = 2 (four paths, phase 0):
   2 * 2^0 = 4 * 2^(-1). *)
let test_exact_equal_scale_alignment () =
  let amp_two_m0 =
    must_exact_amplitude
      (must_group_exact ~path_var_count:0
         [ synthetic_path [| false |] Q.zero;
           synthetic_path [| false |] Q.zero ])
      [| false |]
  in
  let amp_two_m2 =
    must_exact_amplitude
      (must_group_exact ~path_var_count:2
         [ synthetic_path [| false |] Q.zero;
           synthetic_path [| false |] Q.zero;
           synthetic_path [| false |] Q.zero;
           synthetic_path [| false |] Q.zero ])
      [| false |]
  in
  Alcotest.check Alcotest.bool "2 = 4 * 2^(-1)" true
    (Simulation.exact_equal amp_two_m0 amp_two_m2)

(* Destructive interference: phases 0 and 1/2 to the same state cancel. *)
let test_exact_is_zero () =
  let amp =
    must_exact_amplitude
      (must_group_exact ~path_var_count:0
         [ synthetic_path [| false |] Q.zero;
           synthetic_path [| false |] (Q.of_ints 1 2) ])
      [| false |]
  in
  Alcotest.check Alcotest.bool "1 + (-1) = 0" true
    (Simulation.exact_is_zero amp)

(* exact_equal on synthetic amplitudes: 1 = 1, but 1 <> i and 1 <> 2. *)
let test_exact_equal () =
  Alcotest.check Alcotest.bool "1 = 1" true
    (Simulation.exact_equal (synthetic_amplitude Q.zero)
       (synthetic_amplitude Q.zero));
  Alcotest.check Alcotest.bool "1 <> i" false
    (Simulation.exact_equal (synthetic_amplitude Q.zero)
       (synthetic_amplitude (Q.of_ints 1 4)));
  let amp_two =
    must_exact_amplitude
      (must_group_exact ~path_var_count:0
         [ synthetic_path [| false |] Q.zero;
           synthetic_path [| false |] Q.zero ])
      [| false |]
  in
  Alcotest.check Alcotest.bool "1 <> 2" false
    (Simulation.exact_equal (synthetic_amplitude Q.zero) amp_two)

(* Field alignment: 1 = 1 + i - i, built with m = 0 and the phases [0]
   against [0; 1/4; 3/4]. The left side has k = 1, the right side k = 2;
   exact_equal must align the root exponents before comparing. *)
let test_exact_equal_field_alignment () =
  let amp_one_plus_i_minus_i =
    must_exact_amplitude
      (must_group_exact ~path_var_count:0
         [ synthetic_path [| false |] Q.zero;
           synthetic_path [| false |] (Q.of_ints 1 4);
           synthetic_path [| false |] (Q.of_ints 3 4) ])
      [| false |]
  in
  Alcotest.check Alcotest.bool "1 = 1 + i - i (k = 1 vs k = 2)" true
    (Simulation.exact_equal (synthetic_amplitude Q.zero)
       amp_one_plus_i_minus_i)

(* A non-dyadic phase is rejected with a typed error, not an exception:
   the denominator is checked (strictly positive, power of two) before
   Common.Rational.find_k. *)
let test_group_exact_phase_not_dyadic () =
  match
    Simulation.group_exact ~path_var_count:0
      [ synthetic_path [| false |] (Q.of_ints 1 3) ]
  with
  | Error Simulation.PhaseNotDyadic -> ()
  | Error Simulation.RootExponentTooLarge ->
      Alcotest.fail "phase 1/3 must fail with PhaseNotDyadic"
  | Ok _ -> Alcotest.fail "phase 1/3 must be rejected"

(* The root exponent bound is checked before allocation: S on |1> needs
   k = 2 (phase 1/4), so max_root_exponent = 1 rejects it. *)
let test_group_exact_root_exponent_too_large () =
  match
    exact_group_of_circuit ~max_root_exponent:1 [| true |]
      (Program.Macros.ss 0)
  with
  | Error Simulation.RootExponentTooLarge -> ()
  | Error Simulation.PhaseNotDyadic ->
      Alcotest.fail "phase 1/4 is dyadic; expected RootExponentTooLarge"
  | Ok _ -> Alcotest.fail "max_root_exponent = 1 must reject k = 2"

(* Former field size bound: k = 62 used to overflow 1 lsl k. With the
   sparse map there is no array to allocate, so the phase 1/2^62 is
   accepted and gives a non-zero, self-equal amplitude. *)
let test_group_exact_accepts_former_field_size_bound () =
  let den = Z.pow (Z.of_int 2) 62 in
  let amp =
    must_exact_amplitude
      (must_group_exact ~max_root_exponent:62 ~path_var_count:0
         [ synthetic_path [| false |] (Q.make Z.one den) ])
      [| false |]
  in
  Alcotest.check Alcotest.bool "amplitude is not zero" false
    (Simulation.exact_is_zero amp);
  Alcotest.check Alcotest.bool "amplitude equals itself" true
    (Simulation.exact_equal amp amp)

(* Former shift bound: k = Sys.int_size + 1 used to make 1 lsl k
   unspecified. With the sparse map the phase 1/2^(Sys.int_size+1) is
   accepted and gives a non-zero, self-equal amplitude. *)
let test_group_exact_accepts_former_shift_bound () =
  let k = Sys.int_size + 1 in
  let den = Z.pow (Z.of_int 2) k in
  let amp =
    must_exact_amplitude
      (must_group_exact ~max_root_exponent:k ~path_var_count:0
         [ synthetic_path [| false |] (Q.make Z.one den) ])
      [| false |]
  in
  Alcotest.check Alcotest.bool "amplitude is not zero" false
    (Simulation.exact_is_zero amp);
  Alcotest.check Alcotest.bool "amplitude equals itself" true
    (Simulation.exact_equal amp amp)

(* Keys beyond the int range: with k = Sys.int_size + 3, the phase 1/2^k
   stores the key 1, while 1/4 + 1/2^k stores the key 2^(k-2) + 1, which
   exceeds max_int. Both groupings succeed and the amplitudes differ.
   The former dense code rejected this k before any allocation, so this
   test fails cleanly (typed error) before the sparse representation. *)
let test_group_exact_keys_beyond_int () =
  let k = Sys.int_size + 3 in
  let den = Z.pow (Z.of_int 2) k in
  let amp_unit =
    must_exact_amplitude
      (must_group_exact ~max_root_exponent:k ~path_var_count:0
         [ synthetic_path [| false |] (Q.make Z.one den) ])
      [| false |]
  in
  (* 1/4 + 1/2^k = (2^(k-2) + 1) / 2^k; the numerator is odd, so the
     fraction is already reduced. *)
  let num = Z.add (Z.pow (Z.of_int 2) (k - 2)) Z.one in
  let amp_shifted =
    must_exact_amplitude
      (must_group_exact ~max_root_exponent:k ~path_var_count:0
         [ synthetic_path [| false |] (Q.make num den) ])
      [| false |]
  in
  Alcotest.check Alcotest.bool "unit amplitude is not zero" false
    (Simulation.exact_is_zero amp_unit);
  Alcotest.check Alcotest.bool "shifted amplitude is not zero" false
    (Simulation.exact_is_zero amp_shifted);
  Alcotest.check Alcotest.bool "the two amplitudes differ" false
    (Simulation.exact_equal amp_unit amp_shifted)

(* Scale overflow: path_var_count = max_int must not overflow the scale
   (m / 2 + m mod 2 instead of (m + 1) / 2). The grouping succeeds and the
   amplitude is a non-zero, self-equal value. *)
let test_group_exact_scale_no_overflow () =
  match
    Simulation.group_exact ~path_var_count:max_int
      [ synthetic_path [| false |] Q.zero ]
  with
  | Error _ -> Alcotest.fail "max_int path variables must not overflow"
  | Ok grouped ->
      let amp = must_exact_amplitude grouped [| false |] in
      Alcotest.check Alcotest.bool "amplitude is not zero" false
        (Simulation.exact_is_zero amp);
      Alcotest.check Alcotest.bool "amplitude equals itself" true
        (Simulation.exact_equal amp amp)

(* --- Equivalence by instantiation (Equiv.simulation) --- *)

(* First integration test: X vs X on one qubit, full-circuit equivalence.
   Default metadata means full inputs and outputs, a supported
   configuration. X is a permutation: m = 0, null phase, k = 1, s = 0.

   Disabled while Equiv.simulation is a stub; re-enabled with the
   implementation of the simulation-based check. *)
(* let test_simulation_x_x () =
  let result =
    Equiv.simulation ~equivalence:Equiv.FullCircuit
      (Program.Macros.x 0) (Program.Macros.x 0)
  in
  Alcotest.(check string) "X vs X is FullCircuitEquivalent"
    "FullCircuitEquivalent" (Equiv.result_to_string result) *)

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
      ( "Interference",
        [
          Alcotest.test_case "expand circuit with two paths per basis state"
            `Quick test_expand_interference;
        ] );
      ( "Grouping",
        [
          Alcotest.test_case "group X on |0>" `Quick test_group_x_on_zero;
          Alcotest.test_case "group H on |0>" `Quick test_group_h_on_zero;
          Alcotest.test_case "group interference circuit" `Quick
            test_group_interference;
          Alcotest.test_case "group H then S on |0> (complex amplitude)" `Quick
            test_group_h_s_on_zero;
          Alcotest.test_case "probabilities of the interference circuit" `Quick
            test_probabilities_interference;
        ] );
      ( "Exact grouping",
        [
          Alcotest.test_case "group_exact X on |0> (m=0, null phase)" `Quick
            test_group_exact_x_on_zero;
          Alcotest.test_case "group_exact S on |1> (m=0, phase 1/4)" `Quick
            test_group_exact_s_on_one;
          Alcotest.test_case "group_exact H on |0> (odd normalization)" `Quick
            test_group_exact_h_on_zero_odd_normalization;
          Alcotest.test_case "exact_equal aligns scales" `Quick
            test_exact_equal_scale_alignment;
          Alcotest.test_case "exact_is_zero on cancellation" `Quick
            test_exact_is_zero;
          Alcotest.test_case "exact_equal on synthetic amplitudes" `Quick
            test_exact_equal;
          Alcotest.test_case "exact_equal aligns root fields" `Quick
            test_exact_equal_field_alignment;
          Alcotest.test_case "group_exact rejects non-dyadic phase" `Quick
            test_group_exact_phase_not_dyadic;
          Alcotest.test_case "group_exact rejects large root exponent" `Quick
            test_group_exact_root_exponent_too_large;
          Alcotest.test_case "group_exact accepts k = 62 (former field size)"
            `Quick test_group_exact_accepts_former_field_size_bound;
          Alcotest.test_case
            "group_exact accepts k = Sys.int_size + 1 (former shift bound)"
            `Quick test_group_exact_accepts_former_shift_bound;
          Alcotest.test_case "group_exact keys beyond the int range" `Quick
            test_group_exact_keys_beyond_int;
          Alcotest.test_case "group_exact does not overflow the scale" `Quick
            test_group_exact_scale_no_overflow;
        ] );
      (* Disabled while Equiv.simulation is a stub; re-enabled with the
         implementation of the simulation-based check.
      ( "Equiv.simulation",
        [
          Alcotest.test_case "X vs X is FullCircuitEquivalent" `Quick
            test_simulation_x_x;
        ] ); *)
    ]
