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
module QS = Qubit.String
module PS = Poly.String
open Path_sum
module KS = Ket.String
module PSS = String
module Monome = Poly.Monome
open Common
include Rational
open Program
module ProgS = String
include Macros

type poly = Poly.t
type monome = Monome.t

let to_poly (m : monome) : poly = Poly.to_poly m
let reduce_valid_path_sum ?(debug = false) input =
  match Reduction_algorithm.reduction_algorithm ~debug input with
  | Ok output -> output
  | Error (Rules.MalformedPathSum message) ->
      Alcotest.fail ("unexpected malformed path sum: " ^ message)
let ( ++ ) (q1 : Qubit.t) (q2 : Qubit.t) : Qubit.t = Qubit.SumMod2 (q1, q2)
let zero : Qubit.t = Qubit.Zero
let one : Qubit.t = Qubit.One

(* Insert with duplication *)
let ( +++ ) (m : Monome.t) (p : Poly.t) : Poly.t = Poly.insert m p
let x0 = Qubit.Var 0
let x1 = Qubit.Var 1
let x2 = Qubit.Var 2
let x0x1 = Monome.Qubit (Prod (Var 0, Var 1))
let x0x2 = Monome.Qubit (Prod (Var 0, Var 2))
let x1x2 = Monome.Qubit (Prod (Var 1, Var 2))
let x0x1x2 = Monome.Prod (Qubit x0, x1x2)
let v i = Qubit.Var i

(* let test_normalise_path_var ?(debug = true) ?(outputs1 = []) ?(outputs2 = [])
    (input : Path_sum.t) (expect : Path_sum.t) () =
  if debug then
    printf "Primitives.test_normalise_path_var, expect =\n%s\n\n%!"
      (PSS.pretty expect);
  if debug then
    printf "Primitives.test_normalise_path_var, input =\n%s\n\n%!"
      (PSS.pretty input);
  let input_normalised = Rules.Rename.normalise_path_var ~debug input in
  if debug then
    printf "Primitives.test_normalise_path_var, input_normalised =\n%s\n\n%!"
      (PSS.pretty input_normalised);
  let greet =
    Path_sum.equal ~debug ~outputs1 ~outputs2 input_normalised expect
  in
  let expect = true in
  check bool (sprintf "Primitives.test_normalise_path_var") expect greet *)

let p0 = Poly.zero

let malformed_zero_width_path_sum : Path_sum.t =
  { phase = p0; ket = [||]; path_var = [ 0 ] }

let test_hh_reports_malformed_path_sum () =
  let malformed =
    match Rules.HH.hh ~y0_to_remove:0 malformed_zero_width_path_sum with
    | Error (Rules.MalformedPathSum _) -> true
    | Ok _ -> false
  in
  check bool "malformed path sum" true malformed

let test_reduction_algorithm_reports_malformed_path_sum () =
  let malformed =
    match
      Reduction_algorithm.reduction_algorithm malformed_zero_width_path_sum
    with
    | Error (Rules.MalformedPathSum _) -> true
    | Ok _ -> false
  in
  check bool "malformed path sum" true malformed

let hh =
  [
    ( "hh reports malformed path sum",
      `Quick,
      test_hh_reports_malformed_path_sum );
    ( "reduction_algorithm reports malformed path sum",
      `Quick,
      test_reduction_algorithm_reports_malformed_path_sum );
  ]
(* let out_1_qubit = [ 0 ]
let out_2_qubits = [ 0; 1 ] *)
(* 
let normalise_path_var =
  [
    ( "0, x0 -> 0, x0",
      `Quick,
      test_normalise_path_var ~outputs1:out_1_qubit ~outputs2:out_1_qubit
        { phase = p0; ket = [| v 0 |]; path_var = [] }
        { phase = p0; ket = [| v 0 |]; path_var = [] } );
    ( "x0, x0 -> x0, x0",
      `Quick,
      let x0 = v 0 in
      let p_x0 = to_poly (Qubit x0) in
      test_normalise_path_var ~outputs1:out_1_qubit ~outputs2:out_1_qubit
        { phase = p_x0; ket = [| x0 |]; path_var = [] }
        { phase = p_x0; ket = [| x0 |]; path_var = [] } );
    ( "1/4, 1 -> 1/4, 1",
      `Quick,
      let p = to_poly (Scal div4) in
      test_normalise_path_var ~outputs1:out_1_qubit ~outputs2:out_1_qubit
        { phase = p; ket = [| Qubit.One |]; path_var = [] }
        { phase = p; ket = [| Qubit.One |]; path_var = [] } );
    ( "1/4 x0, x0 -> 1/4 x0, x0",
      `Quick,
      let x0 = v 0 in
      let p = to_poly (Prod (Scal div4, Qubit x0)) in
      test_normalise_path_var ~outputs1:out_1_qubit ~outputs2:out_1_qubit
        { phase = p; ket = [| x0 |]; path_var = [] }
        { phase = p; ket = [| x0 |]; path_var = [] } );
    ( "1/2 y0, y0 -> 1/2 y0, y0",
      `Quick,
      let y0 = v 1 in
      let p = to_poly (Monome.Prod (Scal div2, Qubit y0)) in
      test_normalise_path_var
        { phase = p; ket = [| y0 |]; path_var = [ 1 ] }
        { phase = p; ket = [| y0 |]; path_var = [ 1 ] } );
    ( "0, |x0,x1> -> 0, |x0,x1>",
      `Quick,
      let x0 = v 1 in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p0; ket = [| x0; x1 |]; path_var = [] }
        { phase = p0; ket = [| x0; x1 |]; path_var = [] } );
    ( "0, |x0,y0> -> 0, |x0,y0>",
      `Quick,
      let x0 = v 0 in
      let y0 = v 2 in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p0; ket = [| x0; y0 |]; path_var = [ 2 ] }
        { phase = p0; ket = [| x0; y0 |]; path_var = [ 2 ] } );
    ( "0, |y0,x0> -> 0, |y0,x0>",
      `Quick,
      let x0 = v 0 in
      let y0 = v 2 in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p0; ket = [| y0; x0 |]; path_var = [ 2 ] }
        { phase = p0; ket = [| y0; x0 |]; path_var = [ 2 ] } );
    ( "0, |y0,y1> -> 0, |y0,y1>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p0; ket = [| y0; y1 |]; path_var = [ 2; 3 ] }
        { phase = p0; ket = [| y0; y1 |]; path_var = [ 2; 3 ] } );
    ( "0, |y0,y0> -> 0, |y0,y0>",
      `Quick,
      let y0 = v 2 in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p0; ket = [| y0; y0 |]; path_var = [ 2 ] }
        { phase = p0; ket = [| y0; y0 |]; path_var = [ 2 ] } );
    ( "0, |y1,y0> -> 0, |y0,y1>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p0; ket = [| y1; y0 |]; path_var = [ 2; 3 ] }
        { phase = p0; ket = [| y0; y1 |]; path_var = [ 2; 3 ] } );
    ( "1/2 y0, |y1,y0> -> 1/2 y0, |y0,y1>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      let p = to_poly (Monome.Prod (Scal div2, Qubit y0)) in
      let p' = to_poly (Monome.Prod (Scal div2, Qubit y1)) in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p; ket = [| y1; y0 |]; path_var = [ 2; 3 ] }
        { phase = p'; ket = [| y0; y1 |]; path_var = [ 2; 3 ] } );
    ( "1/2 y1, |y1,y1> -> 1/2 y0, |y0,y0>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      let p = to_poly (Monome.Prod (Scal div2, Qubit y1)) in
      let p' = to_poly (Monome.Prod (Scal div2, Qubit y0)) in
      test_normalise_path_var ~outputs1:out_2_qubits ~outputs2:out_2_qubits
        { phase = p; ket = [| y1; y1 |]; path_var = [ 3 ] }
        { phase = p'; ket = [| y0; y0 |]; path_var = [ 2 ] } );
  ] *)

let test_poly_normalize ?(debug = true) (input : Path_sum.t)
    (expect : Path_sum.t) () =
  if debug then
    printf "Primitives.test_normalise_path_var, expect =\n%s\n\n%!"
      (PSS.pretty expect);
  if debug then
    printf "Primitives.test_normalise_path_var, input =\n%s\n\n%!"
      (PSS.pretty input);
  (* This helper is used only for valid examples; malformed path sums have
     dedicated tests for the typed error below. *)
  let input_normalised =
    match Rules.Variable_replacement.poly_normalized ~debug input with
    | Ok output -> output
    | Error (Rules.MalformedPathSum message) ->
        Alcotest.fail ("unexpected malformed path sum: " ^ message)
  in
  if debug then
    printf "Primitives.test_normalise_path_var, input_normalised =\n%s\n\n%!"
      (PSS.pretty input_normalised);
  let greet = Path_sum.equal ~debug input_normalised expect in
  let expect = true in
  check bool (sprintf "Primitives.test_normalise_path_var") expect greet

let test_poly_normalized_reports_malformed_path_sum () =
  let malformed_path_sum : Path_sum.t =
    {
      phase = to_poly (Qubit (Qubit.Var 2));
      ket = [| Qubit.Var 0 |];
      path_var = [];
    }
  in
  match
    Rules.Variable_replacement.poly_normalized malformed_path_sum
  with
  | Error (Rules.MalformedPathSum _) -> check bool "malformed path sum" true true
  | Ok _ -> check bool "malformed path sum expected" true false

let poly_normalize =
  [
    ( "poly_normalized reports malformed path sum",
      `Quick,
      test_poly_normalized_reports_malformed_path_sum );
    ( "0, x0 -> 0, x0",
      `Quick,
      test_poly_normalize
        { phase = p0; ket = [| v 0 |]; path_var = [] }
        { phase = p0; ket = [| v 0 |]; path_var = [] } );
    ( "x0, x0 -> x0, x0",
      `Quick,
      let x0 = v 0 in
      let p_x0 = to_poly (Qubit x0) in
      test_poly_normalize
        { phase = p_x0; ket = [| x0 |]; path_var = [] }
        { phase = p_x0; ket = [| x0 |]; path_var = [] } );
    ( "1/4, 1 -> 1/4, 1",
      `Quick,
      let p = to_poly (Scal div4) in
      test_poly_normalize
        { phase = p; ket = [| Qubit.One |]; path_var = [] }
        { phase = p; ket = [| Qubit.One |]; path_var = [] } );
    ( "1/4 x0, x0 -> 1/4 x0, x0",
      `Quick,
      let x0 = v 0 in
      let p = to_poly (Prod (Scal div4, Qubit x0)) in
      test_poly_normalize
        { phase = p; ket = [| x0 |]; path_var = [] }
        { phase = p; ket = [| x0 |]; path_var = [] } );
    ( "1/2 y0, y0 -> 1/2 y0, y0",
      `Quick,
      let y0 = v 1 in
      let p = to_poly (Monome.Prod (Scal div2, Qubit y0)) in
      test_poly_normalize
        { phase = p; ket = [| y0 |]; path_var = [ 1 ] }
        { phase = p; ket = [| y0 |]; path_var = [ 1 ] } );
    ( "0, |x0,x1> -> 0, |x0,x1>",
      `Quick,
      let x0 = v 1 in
      test_poly_normalize
        { phase = p0; ket = [| x0; x1 |]; path_var = [] }
        { phase = p0; ket = [| x0; x1 |]; path_var = [] } );
    ( "0, |x0,y0> -> 0, |x0,y0>",
      `Quick,
      let x0 = v 0 in
      let y0 = v 2 in
      test_poly_normalize
        { phase = p0; ket = [| x0; y0 |]; path_var = [ 2 ] }
        { phase = p0; ket = [| x0; y0 |]; path_var = [ 2 ] } );
    ( "0, |y0,x0> -> 0, |y0,x0>",
      `Quick,
      let x0 = v 0 in
      let y0 = v 2 in
      test_poly_normalize
        { phase = p0; ket = [| y0; x0 |]; path_var = [ 2 ] }
        { phase = p0; ket = [| y0; x0 |]; path_var = [ 2 ] } );
    ( "0, |y0,y1> -> 0, |y0,y1>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      test_poly_normalize
        { phase = p0; ket = [| y0; y1 |]; path_var = [ 2; 3 ] }
        { phase = p0; ket = [| y0; y1 |]; path_var = [ 2; 3 ] } );
    ( "0, |y0,y0> -> 0, |y0,y0>",
      `Quick,
      let y0 = v 2 in
      test_poly_normalize
        { phase = p0; ket = [| y0; y0 |]; path_var = [ 2 ] }
        { phase = p0; ket = [| y0; y0 |]; path_var = [ 2 ] } );
    ( "0, |y1,y0> -> 0, |y1,y0>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      test_poly_normalize
        { phase = p0; ket = [| y1; y0 |]; path_var = [ 2; 3 ] }
        { phase = p0; ket = [| y1; y0 |]; path_var = [ 2; 3 ] } );
    ( "1/2 y0, |y1,y0> -> 1/2 y0, |y1,y0>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      let p = to_poly (Monome.Prod (Scal div2, Qubit y0)) in
      test_poly_normalize
        { phase = p; ket = [| y1; y0 |]; path_var = [ 2; 3 ] }
        { phase = p; ket = [| y1; y0 |]; path_var = [ 2; 3 ] } );
    ( "1/2 x0y1, |y0,y1> -> 1/2 x0y0, |y1,y0>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      let p = to_poly (Monome.Prod (Scal div2, Prod (Qubit x0, Qubit y1))) in
      let p' = to_poly (Monome.Prod (Scal div2, Prod (Qubit x0, Qubit y0))) in
      test_poly_normalize
        { phase = p; ket = [| y0; y1 |]; path_var = [ 2; 3 ] }
        { phase = p'; ket = [| y1; y0 |]; path_var = [ 2; 3 ] } );
    ( "1/2 y1, |y1,y1> -> 1/2 y0, |y0,y0>",
      `Quick,
      let y0 = v 2 in
      let y1 = v 3 in
      let p = to_poly (Monome.Prod (Scal div2, Qubit y1)) in
      let p' = to_poly (Monome.Prod (Scal div2, Qubit y0)) in
      test_poly_normalize
        { phase = p; ket = [| y1; y1 |]; path_var = [ 3 ] }
        { phase = p'; ket = [| y0; y0 |]; path_var = [ 2 ] } );
  ]

let test_monome_to_scalar_monome ?(debug = true) (input : Monome.t)
    (expect : Q.t * Monome.t) () =
  let greet, expect =
    match Monome.monome_to_scalar_monome input with
    | Some (s, m) ->
        if debug then
          printf "Primitives.test_monome_to_scalar_monome, s = %s, m = %s\n"
            (Q.to_string s) (Monome.String.exact m);
        let s', m' = expect in
        if debug then
          printf "Primitives.test_monome_to_scalar_monome, s' = %s, m' = %s\n"
            (Q.to_string s') (Monome.String.exact m');
        let s_eq = Q.equal s s' in
        let m_eq = Monome.equal m m' in
        if debug then
          printf
            "Primitives.test_monome_to_scalar_monome, s_eq = %b, m_eq = %b\n"
            s_eq m_eq;
        (s_eq && m_eq, true)
    | None -> (false, false)
  in
  check bool (sprintf "Primitives.test_monome_to_scalar_monome") expect greet

let test_monome_equal_result_returns_true () =
  match
    Monome.equal_result (Monome.Qubit (Qubit.Var 0))
      (Monome.Qubit (Qubit.Var 0))
  with
  | Ok true -> check bool "equal monomes" true true
  | Ok false -> check bool "equal monomes expected" true false
  | Error _ -> check bool "well-formed comparison expected" true false

let test_monome_equal_result_returns_false () =
  match Monome.equal_result (Monome.Scal Q.zero) (Monome.Scal Q.one) with
  | Ok false -> check bool "different monomes" false false
  | Ok true -> check bool "different monomes expected" false true
  | Error _ -> check bool "well-formed comparison expected" true false

let test_monome_equal_result_reports_incompatible_widths () =
  match
    Monome.equal_result ~wq1:0 ~wq2:1 (Monome.Qubit Qubit.Zero)
      (Monome.Qubit Qubit.Zero)
  with
  | Error Monome.IncompatibleWidths -> check bool "incompatible widths" true true
  | Error Monome.IncompletePathVariableMap ->
      check bool "incompatible widths expected" true false
  | Ok _ -> check bool "incompatible widths expected" true false

let test_monome_equal_result_reports_incomplete_path_var_map () =
  let map_path_var1 = IntMap.singleton 1 0 in
  let map_path_var2 = IntMap.empty in
  match
    Monome.equal_result ~wq1:1 ~wq2:1 ~map_path_var1 ~map_path_var2
      (Monome.Qubit (Qubit.Var 1)) (Monome.Qubit (Qubit.Var 1))
  with
  | Error Monome.IncompletePathVariableMap ->
      check bool "incomplete path variable map" true true
  | Error Monome.IncompatibleWidths ->
      check bool "incomplete path variable map expected" true false
  | Ok _ -> check bool "incomplete path variable map expected" true false

let test_monome_of_qubit_to_result_returns_monome () =
  let check_ok name qubit expected_monome =
    match Monome.of_qubit_to_result qubit with
    | Ok monome ->
        check string name (Monome.String.exact expected_monome)
          (Monome.String.exact monome)
    | Error Monome.CannotConvertSumMod2 ->
        check bool "direct monome conversion expected" true false
  in
  check_ok "constant zero" Qubit.Zero (Monome.Scal Q.zero);
  check_ok "variable" (Qubit.Var 1) (Monome.Qubit (Qubit.Var 1));
  check_ok "product" (Qubit.Prod (Qubit.Var 1, Qubit.Var 2))
    (Monome.Prod
       (Monome.Qubit (Qubit.Var 1), Monome.Qubit (Qubit.Var 2)))

let test_monome_of_qubit_to_result_reports_sum_mod2 () =
  match Monome.of_qubit_to_result (Qubit.SumMod2 (Qubit.Var 1, Qubit.Var 2)) with
  | Error Monome.CannotConvertSumMod2 ->
      check bool "sum modulo 2 rejected" true true
  | Ok _ -> check bool "sum modulo 2 rejection expected" true false

let test_monome_to_qubit_result_returns_qubit () =
  let check_ok name monome expected_qubit =
    match Monome.to_qubit_result monome with
    | Ok qubit -> check string name (QS.exact expected_qubit) (QS.exact qubit)
    | Error (Monome.CannotConvertScalarToQubit _) ->
        check bool "qubit conversion expected" true false
  in
  check_ok "zero scalar" (Monome.Scal Q.zero) Qubit.Zero;
  check_ok "qubit monome" (Monome.Qubit (Qubit.Var 1)) (Qubit.Var 1);
  check_ok "product monome"
    (Monome.Prod
       (Monome.Qubit (Qubit.Var 1), Monome.Qubit (Qubit.Var 2)))
    (Qubit.Prod (Qubit.Var 1, Qubit.Var 2))

let test_monome_to_qubit_result_reports_scalar () =
  match Monome.to_qubit_result (Monome.Scal (Q.of_int 2)) with
  | Error (Monome.CannotConvertScalarToQubit scalar) ->
      check string "invalid scalar" "2" (Q.to_string scalar)
  | Ok _ -> check bool "invalid scalar expected" true false

let test_monome_remove_result_returns_some () =
  match
    Monome.remove_result 1
      (Monome.Prod
         (Monome.Qubit (Qubit.Var 1), Monome.Qubit (Qubit.Var 2)))
  with
  | Ok (Some output) ->
      check string "removed variable"
        (Monome.String.exact (Monome.Qubit (Qubit.Var 2)))
        (Monome.String.exact output)
  | Ok None -> check bool "removed variable expected" true false
  | Error Monome.CannotRemoveQubitSum ->
      check bool "product monome expected" true false

let test_monome_remove_result_returns_none () =
  match Monome.remove_result 3 (Monome.Qubit (Qubit.Var 1)) with
  | Ok None -> check bool "absent variable" true true
  | Ok (Some _) -> check bool "absent variable expected" true false
  | Error Monome.CannotRemoveQubitSum ->
      check bool "non-sum qubit expected" true false

let test_monome_remove_result_reports_qubit_sum () =
  match
    Monome.remove_result 1
      (Monome.Qubit (Qubit.SumMod2 (Qubit.Var 1, Qubit.Var 2)))
  with
  | Error Monome.CannotRemoveQubitSum ->
      check bool "qubit sum rejected" true true
  | Ok _ -> check bool "qubit sum rejection expected" true false

let monome_equality =
  [
    ( "equal_result returns true",
      `Quick,
      test_monome_equal_result_returns_true );
    ( "equal_result returns false",
      `Quick,
      test_monome_equal_result_returns_false );
    ( "equal_result reports incompatible widths",
      `Quick,
      test_monome_equal_result_reports_incompatible_widths );
    ( "equal_result reports incomplete path variable map",
      `Quick,
      test_monome_equal_result_reports_incomplete_path_var_map );
    ( "of_qubit_to_result returns monome",
      `Quick,
      test_monome_of_qubit_to_result_returns_monome );
    ( "of_qubit_to_result reports sum modulo 2",
      `Quick,
      test_monome_of_qubit_to_result_reports_sum_mod2 );
    ( "to_qubit_result returns qubit",
      `Quick,
      test_monome_to_qubit_result_returns_qubit );
    ( "to_qubit_result reports scalar",
      `Quick,
      test_monome_to_qubit_result_reports_scalar );
    ( "remove_result returns some",
      `Quick,
      test_monome_remove_result_returns_some );
    ( "remove_result returns none",
      `Quick,
      test_monome_remove_result_returns_none );
    ( "remove_result reports qubit sum",
      `Quick,
      test_monome_remove_result_reports_qubit_sum );
  ]

let monome_to_scalar_monome =
  [
    ( "1/2 x0 -> 1/2, x0",
      `Quick,
      test_monome_to_scalar_monome
        (Monome.Prod (Scal div2, Qubit (Var 0)))
        (div2, Qubit (Var 0)) );
    ( "-1/8 x5 -> -1/8, x0",
      `Quick,
      test_monome_to_scalar_monome
        (Monome.Prod (Scal divm8, Qubit (Var 6)))
        (divm8, Qubit (Var 6)) );
    ( "-1/8 x0x2x3 -> -1/8, x0x2x3",
      `Quick,
      test_monome_to_scalar_monome
        (Monome.Prod
           ( Scal divm8,
             Prod (Qubit (Var 0), Prod (Qubit (Var 2), Qubit (Var 3))) ))
        (divm8, Prod (Qubit (Var 0), Prod (Qubit (Var 2), Qubit (Var 3)))) );
    ( "x0 -> None",
      `Quick,
      test_monome_to_scalar_monome (Qubit (Var 0))
        (Q.of_int 0, Monome.Scal (Q.of_int 0)) );
  ]

let test_poly_equal_result_returns_true () =
  match Poly.equal_result Poly.zero Poly.zero with
  | Ok true -> check bool "equal polynomials" true true
  | Ok false -> check bool "equal polynomials expected" true false
  | Error _ -> check bool "well-formed comparison expected" true false

let test_poly_equal_result_returns_false () =
  match Poly.equal_result Poly.zero Poly.one with
  | Ok false -> check bool "different polynomials" false false
  | Ok true -> check bool "different polynomials expected" false true
  | Error _ -> check bool "well-formed comparison expected" true false

let test_poly_equal_result_reports_incompatible_widths () =
  match
    Poly.equal_result ~wq1:0 ~wq2:1
      (to_poly (Monome.Qubit Qubit.Zero))
      (to_poly (Monome.Qubit Qubit.Zero))
  with
  | Error Poly.IncompatibleWidths -> check bool "incompatible widths" true true
  | Error Poly.IncompletePathVariableMap ->
      check bool "incompatible widths expected" true false
  | Ok _ -> check bool "incompatible widths expected" true false

let test_poly_equal_result_reports_incomplete_path_var_map () =
  let map_path_var1 = IntMap.singleton 1 0 in
  let map_path_var2 = IntMap.empty in
  match
    Poly.equal_result ~wq1:1 ~wq2:1 ~map_path_var1 ~map_path_var2
      (to_poly (Monome.Qubit (Qubit.Var 1)))
      (to_poly (Monome.Qubit (Qubit.Var 1)))
  with
  | Error Poly.IncompletePathVariableMap ->
      check bool "incomplete path variable map" true true
  | Error Poly.IncompatibleWidths ->
      check bool "incomplete path variable map expected" true false
  | Ok _ -> check bool "incomplete path variable map expected" true false

let poly_equality =
  [
    ( "equal_result returns true",
      `Quick,
      test_poly_equal_result_returns_true );
    ( "equal_result returns false",
      `Quick,
      test_poly_equal_result_returns_false );
    ( "equal_result reports incompatible widths",
      `Quick,
      test_poly_equal_result_reports_incompatible_widths );
    ( "equal_result reports incomplete path variable map",
      `Quick,
      test_poly_equal_result_reports_incomplete_path_var_map );
  ]

let test_poly_to_qubit_result_returns_qubit () =
  let check_ok name poly expected_qubit =
    match Poly.to_qubit_result poly with
    | Ok qubit -> check string name (QS.exact expected_qubit) (QS.exact qubit)
    | Error (Poly.CannotConvertScalarMonomeToQubit _) ->
        check bool "qubit conversion expected" true false
  in
  (* An empty polynomial represents no parity term, so it converts to Zero. *)
  check_ok "empty polynomial" Poly.empty Qubit.Zero;
  (* Poly.to_qubit folds monomes into a SumMod2 accumulator initialized to Zero. *)
  check_ok "single qubit monome"
    (Monome.Qubit (Qubit.Var 1) +++ Poly.empty)
    (Qubit.SumMod2 (Qubit.Var 1, Qubit.Zero))

let test_poly_to_qubit_result_reports_scalar_monome () =
  (* A scalar monome is a phase term, not a qubit expression. *)
  match Poly.to_qubit_result (Monome.Scal (Q.of_int 2) +++ Poly.empty) with
  | Error (Poly.CannotConvertScalarMonomeToQubit scalar) ->
      check string "invalid scalar" "2" (Q.to_string scalar)
  | Ok _ -> check bool "invalid scalar expected" true false

let test_poly_of_qubit_result_returns_poly () =
  let check_ok name qubit expected_poly =
    match Poly.of_qubit_result qubit Q.one with
    | Ok poly -> check bool name true (Poly.equal expected_poly poly)
    | Error Poly.UnformattedQubitSum ->
        check bool "formatted qubit expected" true false
  in
  (* For scalar 1, lifting x1 ++ x2 gives x1 + x2 - x1.x2:
     coef_lift(1) = -1, hence the product term below has coefficient -1. *)
  let expected_sum =
    Monome.Qubit (Qubit.Var 1)
    +++ (Monome.Qubit (Qubit.Var 2)
        +++ (Monome.Prod
               ( Monome.Scal (Q.of_int (-1)),
                 Monome.Prod
                   (Monome.Qubit (Qubit.Var 1), Monome.Qubit (Qubit.Var 2)) )
            +++ Poly.empty))
  in
  (* A single variable is already directly convertible to one monome. *)
  check_ok "single variable" (Qubit.Var 1)
    (Monome.Qubit (Qubit.Var 1) +++ Poly.empty);
  (* This is the accepted binary SumMod2 shape: SumMod2 (x1, x2). *)
  check_ok "formatted sum" (Qubit.SumMod2 (Qubit.Var 1, Qubit.Var 2))
    expected_sum

let test_poly_of_qubit_result_reports_unformatted_sum () =
  (* The current implementation rejects a nested sum on the left. Such qubits
     must be normalized before calling Poly.of_qubit_result. *)
  let unformatted_sum =
    Qubit.SumMod2 (Qubit.SumMod2 (Qubit.Var 1, Qubit.Var 2), Qubit.Var 3)
  in
  match Poly.of_qubit_result unformatted_sum Q.one with
  | Error Poly.UnformattedQubitSum ->
      check bool "unformatted qubit sum rejected" true true
  | Ok _ -> check bool "unformatted qubit sum rejection expected" true false

let test_poly_of_qubit_2_pi_result_returns_poly () =
  (* The 2*pi shortcut drops the product correction term. For x1 ++ x2, the
     expected polynomial is only x1 + x2. *)
  let expected_sum =
    Monome.Qubit (Qubit.Var 1)
    +++ (Monome.Qubit (Qubit.Var 2) +++ Poly.empty)
  in
  match Poly.of_qubit_2_pi_result (Qubit.SumMod2 (Qubit.Var 1, Qubit.Var 2)) with
  | Ok poly -> check bool "2*pi formatted sum" true (Poly.equal expected_sum poly)
  | Error Poly.UnformattedQubitSum ->
      check bool "formatted qubit expected" true false

let test_poly_of_qubit_2_pi_result_reports_unformatted_sum () =
  (* Same format restriction as Poly.of_qubit_result: a nested left sum must be
     normalized before this conversion. *)
  let unformatted_sum =
    Qubit.SumMod2 (Qubit.SumMod2 (Qubit.Var 1, Qubit.Var 2), Qubit.Var 3)
  in
  match Poly.of_qubit_2_pi_result unformatted_sum with
  | Error Poly.UnformattedQubitSum ->
      check bool "unformatted qubit sum rejected" true true
  | Ok _ -> check bool "unformatted qubit sum rejection expected" true false

let poly_conversion =
  [
    ( "of_qubit_result returns poly",
      `Quick,
      test_poly_of_qubit_result_returns_poly );
    ( "of_qubit_result reports unformatted sum",
      `Quick,
      test_poly_of_qubit_result_reports_unformatted_sum );
    ( "of_qubit_2_pi_result returns poly",
      `Quick,
      test_poly_of_qubit_2_pi_result_returns_poly );
    ( "of_qubit_2_pi_result reports unformatted sum",
      `Quick,
      test_poly_of_qubit_2_pi_result_reports_unformatted_sum );
    ( "to_qubit_result returns qubit",
      `Quick,
      test_poly_to_qubit_result_returns_qubit );
    ( "to_qubit_result reports scalar monome",
      `Quick,
      test_poly_to_qubit_result_reports_scalar_monome );
  ]

let test_poly_distribution_result_returns_poly () =
  (* Distribution multiplies one monome by each monome of the right polynomial.
     Here both polynomials contain a single qubit monome, so the result is
     exactly x1.x2. *)
  let left = Monome.Qubit (Qubit.Var 1) in
  let right = Monome.Qubit (Qubit.Var 2) +++ Poly.empty in
  let expected =
    Monome.Prod (Monome.Qubit (Qubit.Var 1), Monome.Qubit (Qubit.Var 2))
    +++ Poly.empty
  in
  match Poly.distribution_result left right with
  | Ok poly -> check bool "distributed product" true (Poly.equal expected poly)
  | Error Poly.UnformattedDistributionMonome ->
      check bool "formatted distribution monome expected" true false

let test_poly_distribution_result_reports_unformatted_monome () =
  (* Scalars are expected on the left of Prod. The old distribution function
     raised Failure on this shape; the typed version reports it explicitly. *)
  let unformatted_right =
    Monome.Prod (Monome.Qubit (Qubit.Var 1), Monome.Scal (Q.of_int 2))
    +++ Poly.empty
  in
  match
    Poly.distribution_result (Monome.Qubit (Qubit.Var 0)) unformatted_right
  with
  | Error Poly.UnformattedDistributionMonome ->
      check bool "unformatted distribution monome rejected" true true
  | Ok _ -> check bool "unformatted distribution monome expected" true false

let poly_algebra =
  [
    ( "distribution_result returns poly",
      `Quick,
      test_poly_distribution_result_returns_poly );
    ( "distribution_result reports unformatted monome",
      `Quick,
      test_poly_distribution_result_reports_unformatted_monome );
  ]

let test_path_sum_equal_result_returns_true () =
  let path_sum : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 0 |]; path_var = [] }
  in
  match Path_sum.equal_result path_sum path_sum with
  | Ok true -> check bool "equal path sums" true true
  | Ok false -> check bool "equal path sums expected" true false
  | Error Path_sum.DifferentOutputLengths ->
      check bool "well-formed comparison expected" true false
  | Error Path_sum.InvalidOutputIndex ->
      check bool "well-formed comparison expected" true false
  | Error Path_sum.IncompatiblePhaseWidths ->
      check bool "well-formed comparison expected" true false
  | Error Path_sum.IncompletePhasePathVariableMap ->
      check bool "well-formed comparison expected" true false

let test_path_sum_equal_result_returns_false () =
  let path_sum1 : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Zero |]; path_var = [] }
  in
  let path_sum2 : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.One |]; path_var = [] }
  in
  match Path_sum.equal_result path_sum1 path_sum2 with
  | Ok false -> check bool "different path sums" false false
  | Ok true -> check bool "different path sums expected" false true
  | Error Path_sum.DifferentOutputLengths ->
      check bool "well-formed comparison expected" true false
  | Error Path_sum.InvalidOutputIndex ->
      check bool "well-formed comparison expected" true false
  | Error Path_sum.IncompatiblePhaseWidths ->
      check bool "well-formed comparison expected" true false
  | Error Path_sum.IncompletePhasePathVariableMap ->
      check bool "well-formed comparison expected" true false

let test_path_sum_equal_result_reports_different_output_lengths () =
  let path_sum : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 0 |]; path_var = [] }
  in
  match Path_sum.equal_result ~outputs1:[ 0 ] ~outputs2:[] path_sum path_sum with
  | Error Path_sum.DifferentOutputLengths ->
      check bool "different output lengths" true true
  | Error Path_sum.InvalidOutputIndex ->
      check bool "different output lengths expected" true false
  | Error Path_sum.IncompatiblePhaseWidths ->
      check bool "different output lengths expected" true false
  | Error Path_sum.IncompletePhasePathVariableMap ->
      check bool "different output lengths expected" true false
  | Ok _ -> check bool "different output lengths expected" true false

let test_path_sum_equal_result_reports_invalid_output_index () =
  let path_sum : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 0 |]; path_var = [] }
  in
  match
    Path_sum.equal_result ~outputs1:[ 1 ] ~outputs2:[ 0 ] path_sum path_sum
  with
  | Error Path_sum.InvalidOutputIndex ->
      check bool "invalid output index" true true
  | Error Path_sum.DifferentOutputLengths ->
      check bool "invalid output index expected" true false
  | Error Path_sum.IncompatiblePhaseWidths ->
      check bool "invalid output index expected" true false
  | Error Path_sum.IncompletePhasePathVariableMap ->
      check bool "invalid output index expected" true false
  | Ok _ -> check bool "invalid output index expected" true false

let path_sum_equality =
  [
    ( "equal_result returns true",
      `Quick,
      test_path_sum_equal_result_returns_true );
    ( "equal_result returns false",
      `Quick,
      test_path_sum_equal_result_returns_false );
    ( "equal_result reports different output lengths",
      `Quick,
      test_path_sum_equal_result_reports_different_output_lengths );
    ( "equal_result reports invalid output index",
      `Quick,
      test_path_sum_equal_result_reports_invalid_output_index );
  ]

let test_path_sum_ofSize_init_result_returns_path_sum () =
  let check_ok name width inits_0 expected_output =
    match Path_sum.ofSize_init_result width inits_0 with
    | Ok output ->
        check string name (PSS.exact expected_output) (PSS.exact output)
    | Error Path_sum.InvalidWidth ->
        check bool "valid width expected" true false
    | Error Path_sum.InvalidInitIndex ->
        check bool "valid initialization indices expected" true false
  in
  check_ok "no initialized qubit" 2 []
    { phase = Poly.zero; ket = [| Qubit.Var 0; Qubit.Var 1 |]; path_var = [] };
  check_ok "one initialized qubit" 2 [ 0 ]
    { phase = Poly.zero; ket = [| Qubit.Zero; Qubit.Var 0 |]; path_var = [] };
  check_ok "several initialized qubits" 3 [ 0; 2 ]
    {
      phase = Poly.zero;
      ket = [| Qubit.Zero; Qubit.Var 0; Qubit.Zero |];
      path_var = [];
    };
  check_ok "zero width" 0 [] { phase = Poly.zero; ket = [||]; path_var = [] }

let test_path_sum_ofSize_init_result_reports_invalid_width () =
  match Path_sum.ofSize_init_result (-1) [] with
  | Error Path_sum.InvalidWidth -> check bool "invalid width" true true
  | Error Path_sum.InvalidInitIndex ->
      check bool "invalid width expected" true false
  | Ok _ -> check bool "invalid width expected" true false

let test_path_sum_ofSize_init_result_reports_invalid_init_index () =
  match Path_sum.ofSize_init_result 1 [ 1 ] with
  | Error Path_sum.InvalidInitIndex ->
      check bool "invalid initialization index" true true
  | Error Path_sum.InvalidWidth ->
      check bool "invalid initialization index expected" true false
  | Ok _ -> check bool "invalid initialization index expected" true false

let path_sum_initialization =
  [
    ( "ofSize_init_result returns path sum",
      `Quick,
      test_path_sum_ofSize_init_result_returns_path_sum );
    ( "ofSize_init_result reports invalid width",
      `Quick,
      test_path_sum_ofSize_init_result_reports_invalid_width );
    ( "ofSize_init_result reports invalid init index",
      `Quick,
      test_path_sum_ofSize_init_result_reports_invalid_init_index );
  ]

let test_path_sum_substitute_result_returns_path_sum () =
  let check_ok name ?(except_path_var = false) input variable replacement
      expected_output =
    match
      Path_sum.substitute_result ~except_path_var input variable replacement
    with
    | Ok output ->
        check string name (PSS.exact expected_output) (PSS.exact output)
    | Error Path_sum.CannotSubstitutePathVariable ->
        check bool "substitutable variable expected" true false
  in
  let input : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 1; Qubit.Var 2 |]; path_var = [ 2 ] }
  in
  (* Var 1 is not declared as a path variable, so it may be replaced. *)
  check_ok "substituted free variable" input 1 Qubit.One
    { phase = Poly.zero; ket = [| Qubit.One; Qubit.Var 2 |]; path_var = [ 2 ] };
  (* With except_path_var=true, declared path variables are left untouched. *)
  check_ok "protected path variable" ~except_path_var:true input 2 Qubit.One
    input

let test_path_sum_substitute_result_reports_path_var_substitution () =
  let input : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 1 |]; path_var = [ 1 ] }
  in
  (* Without except_path_var=true, substituting a path variable is rejected. *)
  match Path_sum.substitute_result input 1 Qubit.One with
  | Error Path_sum.CannotSubstitutePathVariable ->
      check bool "path variable substitution rejected" true true
  | Ok _ -> check bool "path variable substitution rejection expected" true false

let path_sum_substitution =
  [
    ( "substitute_result returns path sum",
      `Quick,
      test_path_sum_substitute_result_returns_path_sum );
    ( "substitute_result reports path variable substitution",
      `Quick,
      test_path_sum_substitute_result_reports_path_var_substitution );
  ]

let test_lift_poly ?(debug = true) (p : Poly.t) (expect : Poly.t) (wq : int) ()
    =
  if debug then printf "Primitives.test_lift_poly, p = %s\n%!" (PS.pretty p wq);
  if debug then
    printf "Primitives.test_lift_poly, expect = %s\n%!" (PS.pretty expect wq);
  let expect = Poly.simplify expect in
  let greet = Poly.simplify (Poly.lift_poly ~debug (Poly.simplify p)) in
  if debug then
    printf "Primitives.test_lift_poly, greet = %s\n\n%!" (PS.pretty greet wq);
  let greet = Poly.equal greet expect in
  let expect = true in
  check bool (sprintf "Primitives.test_lift_poly") expect greet

let mx0x1 = Monome.Prod (Scal div4, x0x1)

let poly0 s =
  Prod (Scal s, Qubit x0)
  +++ (Prod (Scal s, Qubit x1)
      +++ to_poly (Prod (Scal (Q.mul minus_two s), x0x1)))

let poly0' s = to_poly (Monome.Prod (Scal s, Qubit (SumMod2 (Var 0, Var 1))))

let poly1 s =
  Prod (Scal s, Qubit x0)
  +++ (Prod (Scal s, Qubit x1)
      +++ (Prod (Scal s, Qubit x2)
          +++ (Prod (Scal (Q.mul s minus_two), x0x1)
              +++ (Prod (Scal (Q.mul s minus_two), x1x2)
                  +++ (Prod (Scal (Q.mul s minus_two), x0x2) +++ Poly.empty))))
      )

let poly1' s = to_poly (Monome.Prod (Scal s, Qubit (x0 ++ (x1 ++ x2))))

let poly2 s =
  Poly.insert
    (Prod (Scal s, Qubit x0))
    (Poly.insert (Prod (Scal s, Qubit x1)) (to_poly mx0x1))

let poly2' s = to_poly (Monome.Prod (Scal s, Qubit (SumMod2 (Var 0, Var 1))))

let lift_poly =
  [
    ( "1/2 -> 1/2",
      `Quick,
      let s = div2 in
      test_lift_poly (to_poly (Monome.Scal s)) (to_poly (Scal s)) 1 );
    ( "1/2 0 -> 0",
      `Quick,
      test_lift_poly (to_poly (Monome.Scal Q.zero)) Poly.zero 1 );
    ( "1/2 [0] -> 0",
      `Quick,
      let s = div2 in
      test_lift_poly (to_poly (Prod (Scal s, Qubit Qubit.Zero))) Poly.zero 1 );
    ( "1/2 x0 -> 1/2 x0",
      `Quick,
      let s = div2 in
      test_lift_poly
        (to_poly (Prod (Scal s, Qubit x0)))
        (to_poly (Prod (Scal s, Qubit x0)))
        1 );
    ( "1/2 x0 ++ x1 -> 1/2 x0 + 1/2 x1",
      `Quick,
      let s = div2 in
      test_lift_poly (poly0' s) (poly0 s) 2 );
    ( "-1/8, x0 ++ x1 -> 7/8 x0 + 7/8 x1 + 1/4 x0x1",
      `Quick,
      let s = divm8 in
      test_lift_poly (poly2' s) (poly2 s) 2 );
    ( "1/8, x0 ++ x1x2 -> 1/8 x0 + 1/8 x1x2 - 1/4 x0x1x2",
      `Quick,
      let s = div8 in
      let s' = divm4 in
      let x =
        to_poly
          (Monome.Prod (Scal s, Qubit (SumMod2 (x0, Monome.to_qubit x1x2))))
      in
      test_lift_poly x
        (Poly.insert
           (Prod (Scal s, Qubit x0))
           (Poly.insert
              (Prod (Scal s, x1x2))
              (to_poly (Prod (Scal s', x0x1x2)))))
        3 );
    ( "1/4, x0++x1++x2 -> 1/4x0+1/4x1+1/4x2 -1/2x0x1-1/2x0x2-1/2x1x2",
      `Quick,
      let s = div4 in
      test_lift_poly (poly1' s) (poly1 s) 3 );
    ( "1/8, x0++x1++x2 -> 1/8x0+1/8x1+1/8x2 -1/4x0x1-1/4x0x2-1/4x1x2 +1/2x0x1x2",
      `Quick,
      let s = div8 in
      let x =
        to_poly (Monome.Prod (Scal s, Qubit (SumMod2 (x0, SumMod2 (x1, x2)))))
      in
      test_lift_poly x
        (Prod (Scal s, Qubit x0)
        +++ (Prod (Scal s, Qubit x1)
            +++ (Prod (Scal s, Qubit x2)
                +++ (Prod (Scal (Q.mul s minus_two), x0x1)
                    +++ (Prod (Scal (Q.mul s minus_two), x1x2)
                        +++ (Prod (Scal (Q.mul s minus_two), x0x2)
                            +++ (Prod (Scal (Q.mul s four), x0x1x2)
                                +++ Poly.empty)))))))
        3 );
    ( "1/4 lift (p1 + p1) = 1/4 lift p1 + 1/4 lift p1",
      `Quick,
      let s = div4 in
      test_lift_poly
        (Poly.merge (poly1' s) (poly1' s))
        (Poly.merge (poly1 s) (poly1 s))
        3 );
    ( "1/4 lift (p0 + p0) = 1/4 lift p0 + 1/4 lift p0",
      `Quick,
      let s = div4 in
      test_lift_poly
        (Poly.merge (poly0' s) (poly0' s))
        (Poly.merge (poly0 s) (poly0 s))
        3 );
    ( "1/8 lift (p0 + p0) = 1/8 lift p0 + 1/8 lift p0",
      `Quick,
      let s = div8 in
      let p = Poly.merge (poly0' s) (poly0' s) in
      let expect = Poly.merge (poly0 s) (poly0 s) in
      test_lift_poly p expect 3 );
    ( "lift (1/2p0 + 1/4p0 + 1/8p0) = 1/2 lift p0 + 1/4 lift p0 + 18 lift p0",
      `Quick,
      let s0 = div2 in
      let s1 = div4 in
      let s2 = divm8 in
      let p = Poly.merge (poly0' s0) (Poly.merge (poly0' s1) (poly0' s2)) in
      let expect = Poly.merge (poly0 s0) (Poly.merge (poly0 s1) (poly0 s2)) in
      test_lift_poly p expect 3 );
  ]

let test_lift_monome ?(debug = true) (m : Monome.t) (expect : Poly.t) (wq : int)
    () =
  if debug then
    printf "Primitives.test_lift_monome, m = %s\n%!" (Monome.String.pretty m wq);
  let expect = Poly.simplify expect in
  if debug then
    printf "Primitives.test_lift_monome, expect = %s\n%!"
      (Poly.String.pretty expect wq);
  let greet = Poly.lift_monome ~debug m in
  if debug then
    printf "Primitives.test_lift_monome, greet = %s\n\n%!"
      (Poly.String.pretty greet wq);
  let greet = Poly.equal greet expect in
  let expect = true in
  check bool (sprintf "Primitives.test_lift_monome") expect greet

let lift_monome =
  [
    ( "1/2 -> 1/2",
      `Quick,
      let s = div2 in
      test_lift_monome (Monome.Scal s) (to_poly (Scal s)) 1 );
    ("1/2 0 -> 0", `Quick, test_lift_monome (Monome.Scal Q.zero) Poly.zero 1);
    ( "1/2 [0] -> 0",
      `Quick,
      let s = div2 in
      test_lift_monome (Prod (Scal s, Qubit Qubit.Zero)) Poly.zero 1 );
    ( "1/2 x0 -> 1/2 x0",
      `Quick,
      let s = div2 in
      test_lift_monome
        (Prod (Scal s, Qubit x0))
        (to_poly (Prod (Scal s, Qubit x0)))
        1 );
    ( "1/2 x0 ++ x1 -> 1/2 x0 + 1/2 x1",
      `Quick,
      let s = div2 in
      let x = Monome.Prod (Scal s, Qubit (SumMod2 (Var 0, Var 1))) in
      test_lift_monome x
        (Poly.insert
           (Prod (Scal s, Qubit x0))
           (to_poly (Prod (Scal s, Qubit x1))))
        2 );
    ( "-1/8, x0 ++ x1 -> 7/8 x0 + 7/8 x1 + 1/4 x0x1",
      `Quick,
      let s = divm8 in
      let x = Monome.Prod (Scal s, Qubit (SumMod2 (Var 0, Var 1))) in
      let mx0x1 = Monome.Prod (Scal div4, x0x1) in
      test_lift_monome x
        (Poly.insert
           (Prod (Scal s, Qubit x0))
           (Poly.insert (Prod (Scal s, Qubit x1)) (to_poly mx0x1)))
        2 );
    ( "1/8, x0 ++ x1x2 -> 1/8 x0 + 1/8 x1x2 - 1/4 x0x1x2",
      `Quick,
      let s = div8 in
      let s' = divm4 in
      let x =
        Monome.Prod (Scal s, Qubit (SumMod2 (x0, Monome.to_qubit x1x2)))
      in
      test_lift_monome x
        (Poly.insert
           (Prod (Scal s, Qubit x0))
           (Poly.insert
              (Prod (Scal s, x1x2))
              (to_poly (Prod (Scal s', x0x1x2)))))
        3 );
    ( "1/4, x0++x1++x2 -> 1/4x0+1/4x1+1/4x2 -1/2x0x1-1/2x0x2-1/2x1x2",
      `Quick,
      let s = div4 in
      let x = Monome.Prod (Scal s, Qubit (SumMod2 (x0, SumMod2 (x1, x2)))) in
      test_lift_monome x
        (Prod (Scal s, Qubit x0)
        +++ (Prod (Scal s, Qubit x1)
            +++ (Prod (Scal s, Qubit x2)
                +++ (Prod (Scal (Q.mul s minus_two), x0x1)
                    +++ (Prod (Scal (Q.mul s minus_two), x1x2)
                        +++ (Prod (Scal (Q.mul s minus_two), x0x2)
                            +++ Poly.empty))))))
        3 );
    ( "1/8, x0++x1++x2 -> 1/8x0+1/8x1+1/8x2 -1/4x0x1-1/4x0x2-1/4x1x2 +1/2x0x1x2",
      `Quick,
      let s = div8 in
      let x = Monome.Prod (Scal s, Qubit (SumMod2 (x0, SumMod2 (x1, x2)))) in
      test_lift_monome x
        (Prod (Scal s, Qubit x0)
        +++ (Prod (Scal s, Qubit x1)
            +++ (Prod (Scal s, Qubit x2)
                +++ (Prod (Scal (Q.mul s minus_two), x0x1)
                    +++ (Prod (Scal (Q.mul s minus_two), x1x2)
                        +++ (Prod (Scal (Q.mul s minus_two), x0x2)
                            +++ (Prod (Scal (Q.mul s four), x0x1x2)
                                +++ Poly.empty)))))))
        3 );
  ]

let test_lift_qubit ?(debug = true) (s : Q.t) (m : Monome.t) (expect : Poly.t)
    (wq : int) () =
  if debug then
    printf "Primitives.test_lift_qubit, m = %s\n%!" (Monome.String.pretty m wq);
  let expect = Poly.simplify expect in
  if debug then
    printf "Primitives.test_lift_qubit, expect = %s\n%!"
      (Poly.String.pretty expect wq);
  let greet = Poly.lift_qubit ~debug s m in
  if debug then
    printf "Primitives.test_lift_qubit, greet = %s\n\n%!"
      (Poly.String.pretty greet wq);
  let greet = Poly.equal greet expect in
  let expect = true in
  check bool (sprintf "Primitives.test_lift_qubit") expect greet

let lift_qubit =
  [
    ( "1/2, 1 -> 1/2",
      `Quick,
      let s = div2 in
      test_lift_qubit s (Qubit Qubit.One) (to_poly (Scal s)) 1 );
    ( "1/2, 0 -> 0",
      `Quick,
      let s = div2 in
      test_lift_qubit s (Qubit Qubit.Zero) Poly.zero 1 );
    ( "1/2, x0 -> 1/2 x0",
      `Quick,
      let s = div2 in
      test_lift_qubit s (Qubit x0) (to_poly (Prod (Scal s, Qubit x0))) 1 );
    ( "1/2, x0 ++ x1 -> 1/2 x0 + 1/2 x1",
      `Quick,
      let s = div2 in
      let x = Monome.Qubit (SumMod2 (Var 0, Var 1)) in
      test_lift_qubit s x
        (Poly.insert
           (Prod (Scal s, Qubit x0))
           (to_poly (Prod (Scal s, Qubit x1))))
        2 );
    ( "-1/8, x0 ++ x1 -> 7/8 x0 + 7/8 x1 + 1/4 x0x1",
      `Quick,
      let s = divm8 in
      let x = Monome.Qubit (SumMod2 (Var 0, Var 1)) in
      let mx0x1 = Monome.Prod (Scal div4, x0x1) in
      test_lift_qubit s x
        (Poly.insert
           (Prod (Scal s, Qubit x0))
           (Poly.insert (Prod (Scal s, Qubit x1)) (to_poly mx0x1)))
        2 );
    ( "1/8, x0 ++ x1x2 -> 1/8 x0 + 1/8 x1x2 - 1/4 x0x1x2",
      `Quick,
      let s = div8 in
      let s' = divm4 in
      let x = Qubit.SumMod2 (x0, Monome.to_qubit x1x2) in
      test_lift_qubit s (Qubit x)
        (Poly.insert
           (Prod (Scal s, Qubit x0))
           (Poly.insert
              (Prod (Scal s, x1x2))
              (to_poly (Prod (Scal s', x0x1x2)))))
        3 );
    ( "1/4, x0++x1++x2 -> 1/4x0+1/4x1+1/4x2 -1/2x0x1-1/2x0x2-1/2x1x2",
      `Quick,
      let s = div4 in
      let x = Qubit.SumMod2 (x0, SumMod2 (x1, x2)) in
      test_lift_qubit s (Qubit x)
        (Prod (Scal s, Qubit x0)
        +++ (Prod (Scal s, Qubit x1)
            +++ (Prod (Scal s, Qubit x2)
                +++ (Prod (Scal (Q.mul s minus_two), x0x1)
                    +++ (Prod (Scal (Q.mul s minus_two), x1x2)
                        +++ (Prod (Scal (Q.mul s minus_two), x0x2)
                            +++ Poly.empty))))))
        3 );
    ( "1/8, x0++x1++x2 -> 1/8x0+1/8x1+1/8x2 -1/4x0x1-1/4x0x2-1/4x1x2 +1/2x0x1x2",
      `Quick,
      let s = div8 in
      let x = Qubit.SumMod2 (x0, SumMod2 (x1, x2)) in
      test_lift_qubit s (Qubit x)
        (Prod (Scal s, Qubit x0)
        +++ (Prod (Scal s, Qubit x1)
            +++ (Prod (Scal s, Qubit x2)
                +++ (Prod (Scal (Q.mul s minus_two), x0x1)
                    +++ (Prod (Scal (Q.mul s minus_two), x1x2)
                        +++ (Prod (Scal (Q.mul s minus_two), x0x2)
                            +++ (Prod (Scal (Q.mul s four), x0x1x2)
                                +++ Poly.empty)))))))
        3 );
  ]

(* phase = x0y0 + x0y1, ket = |y0 + y1> *)
(* phase[y0 <- y0 + y1] = x0y0, ket[y0 <- y0 + y1] = |y0> *)
let test_variable_replacement_factorisation ?(debug = true) (input : Path_sum.t)
    (expect : Path_sum.t) () =
  if debug then
    printf "Test.test_variable_replacement_factorisation, input =\n%s\n\n"
      (PSS.pretty input);
  let greet_repl =
    Rules.Variable_replacement.variable_replacement_factorisation input
  in
  if debug then
    printf "Test.test_variable_replacement_factorisation, greet_repl =\n%s\n\n"
      (PSS.pretty greet_repl);
  let greet = Rules.Simplification.simplify greet_repl in
  if debug then
    printf "Test.test_variable_replacement_factorisation, greet =\n%s\n\n"
      (PSS.pretty greet);
  let expect = Rules.Simplification.simplify expect in
  if debug then
    printf "Test.test_variable_replacement_factorisation, expect =\n%s\n\n"
      (PSS.pretty expect);
  let greeting = greet = expect in
  let expected = true in
  check bool
    (sprintf "test_variable_replacement_factorisation")
    expected greeting

let test_variable_replacement_factorisation_does_not_mutate_input () =
  let phase =
    Prod (Scal div2, Prod (Qubit x0, Qubit (v 1)))
    +++ to_poly (Prod (Scal div2, Prod (Qubit x0, Qubit (v 2))))
  in
  let input : Path_sum.t =
    {
      phase;
      ket = [| x0 ++ Qubit.Var 1 ++ Qubit.Var 2 |];
      path_var = [ 1; 2 ];
    }
  in
  let input_before = PSS.exact input in
  let _ = Rules.Variable_replacement.variable_replacement_factorisation input in
  check string "input unchanged" input_before (PSS.exact input)

let variable_replacement_factorisation =
  [
    ( "|x0> -> |x0>",
      `Quick,
      test_variable_replacement_factorisation
        { phase = to_poly (Scal Q.zero); ket = [| Var 0 |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| Var 0 |]; path_var = [] } );
    ( "|x0+x1> -> |x0+x1>",
      `Quick,
      test_variable_replacement_factorisation
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0; Var 1 |];
          path_var = [];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0; Var 1 |];
          path_var = [];
        } );
    ( "|y0> -> |y0>",
      `Quick,
      test_variable_replacement_factorisation
        { phase = to_poly (Scal Q.zero); ket = [| Var 1 |]; path_var = [ 1 ] }
        { phase = to_poly (Scal Q.zero); ket = [| Var 1 |]; path_var = [ 1 ] }
    );
    ( "|0> -> |0>",
      `Quick,
      test_variable_replacement_factorisation
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.Zero |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.Zero |]; path_var = [] }
    );
    ( "|1> -> |1>",
      `Quick,
      test_variable_replacement_factorisation
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.One |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.One |]; path_var = [] }
    );
    ( "|1+x0> -> |1+x0>",
      `Quick,
      test_variable_replacement_factorisation
        { phase = to_poly (Scal Q.zero); ket = [| one ++ x0 |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| one ++ x0 |]; path_var = [] }
    );
    ( "|0+x0> -> |x0>",
      `Quick,
      test_variable_replacement_factorisation
        { phase = to_poly (Scal Q.zero); ket = [| zero ++ x0 |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| x0 |]; path_var = [] } );
    ( "|0+y0> -> |y1>",
      `Quick,
      test_variable_replacement_factorisation
        {
          phase = to_poly (Scal Q.zero);
          ket = [| zero ++ Var 1 |];
          path_var = [ 1 ];
        }
        { phase = to_poly (Scal Q.zero); ket = [| Var 1 |]; path_var = [ 1 ] }
    );
    ( "|1+y0,y0> -> |1+y0,y0>",
      `Quick,
      test_variable_replacement_factorisation
        {
          phase = to_poly (Scal Q.zero);
          ket = [| one ++ Var 2; Var 2 |];
          path_var = [ 2 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| one ++ Var 2; Var 2 |];
          path_var = [ 2 ];
        } );
    ( "|x0+y0+y1,y0,y1> -> |x0+y0+y1,y0,y1>",
      `Quick,
      test_variable_replacement_factorisation
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ Var 3 ++ Var 4; Var 3; Var 4 |];
          path_var = [ 3; 4 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ Var 3 ++ Var 4; Var 3; Var 4 |];
          path_var = [ 3; 4 ];
        } );
    ( "|x0+y0+y1> -> |x0+y0+y1>",
      `Quick,
      test_variable_replacement_factorisation
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ Var 1 ++ Var 2 |];
          path_var = [ 1; 2 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ Var 1 ++ Var 2 |];
          path_var = [ 1; 2 ];
        } );
    ( "1/2 x0y0 + 1/2 x0y1 |x0+y0+y1> -> 1/2 x0y0 |x0+y0>",
      `Quick,
      let p =
        Prod (Scal div2, Prod (Qubit x0, Qubit (v 1)))
        +++ to_poly (Prod (Scal div2, Prod (Qubit x0, Qubit (v 2))))
      in
      let p' = to_poly (Prod (Scal div2, Prod (Qubit x0, Qubit (v 1)))) in
      let ps : Path_sum.t =
        { phase = p; ket = [| x0 ++ Var 1 ++ Var 2 |]; path_var = [ 1; 2 ] }
      in
      let ps' : Path_sum.t =
        { phase = p'; ket = [| x0 ++ Var 1 |]; path_var = [ 1 ] }
      in
      test_variable_replacement_factorisation ps ps' );
    ( "1/2 x0y0 + 1/2 x0y1 |x0+y0+y1> -> 1/2 x0y0 |x0+y0>",
      `Quick,
      let p =
        Prod (Scal div2, Prod (Qubit x0, Qubit (v 1)))
        +++ to_poly (Prod (Scal div2, Prod (Qubit x0, Qubit (v 2))))
      in
      let p' = to_poly (Prod (Scal div2, Prod (Qubit x0, Qubit (v 1)))) in
      let ps : Path_sum.t =
        { phase = p; ket = [| x0 ++ Var 1 ++ Var 2 |]; path_var = [ 1; 2 ] }
      in
      let ps' : Path_sum.t =
        { phase = p'; ket = [| x0 ++ Var 1 |]; path_var = [ 1 ] }
      in
      test_variable_replacement_factorisation ps ps' );
    ( "factorisation does not mutate input",
      `Quick,
      test_variable_replacement_factorisation_does_not_mutate_input );
    ( "1/4 x0y0 + 1/4 x0y1 |x0+y0+y1> -> 1/4 x0y0 + 1/4 x0y1 |x0+y0+y1>",
      `Quick,
      let p =
        Prod (Scal div4, Prod (Qubit x0, Qubit (v 1)))
        +++ to_poly (Prod (Scal div4, Prod (Qubit x0, Qubit (v 2))))
      in
      let ps : Path_sum.t =
        { phase = p; ket = [| x0 ++ Var 1 ++ Var 2 |]; path_var = [ 1; 2 ] }
      in
      test_variable_replacement_factorisation ps ps );
  ]

let test_variable_replacement ?(debug = true) (input : Path_sum.t)
    (expect : Path_sum.t) () =
  if debug then
    printf "Test.test_variable_replacement, input =\n%s\n\n" (PSS.pretty input);
  (* This helper keeps the historical expectation: no replacement means the
     input path sum is unchanged. *)
  let greet_repl =
    match Rules.Variable_replacement.variable_replacement ~debug input with
    | Ok (Some ps) -> ps
    | Ok None -> input
    | Error (Rules.MalformedPathSum message) ->
        Alcotest.fail ("unexpected malformed path sum: " ^ message)
  in
  if debug then
    printf "Test.test_variable_replacement, greet_repl =\n%s%!\n\n"
      (PSS.pretty greet_repl);
  let greet =
    Rules.Simplification.simplify greet_repl
    (* (Rules.Rename.normalise_path_var ~debug greet_repl) *)
  in
  if debug then
    printf "Test.test_variable_replacement, greet =\n%s%!\n\n"
      (PSS.pretty greet);
  let expect = Rules.Simplification.simplify expect in
  if debug then
    printf "Test.test_variable_replacement, expect =\n%s%!\n\n"
      (PSS.pretty expect);
  let greeting = greet = expect in
  let expected = true in
  check bool (sprintf "test_variable_replacement") expected greeting

let test_variable_replacement_returns_typed_replacement () =
  let input : Path_sum.t =
    { phase = Poly.zero; ket = [| one ++ Var 1 |]; path_var = [ 1 ] }
  in
  let expected_output : Path_sum.t =
    { phase = Poly.zero; ket = [| Var 1 |]; path_var = [ 1 ] }
  in
  match Rules.Variable_replacement.variable_replacement input with
  | Ok (Some output) ->
      check string "replacement result" (PSS.exact expected_output)
        (PSS.exact output)
  | Ok None -> check bool "replacement expected" true false
  | Error (Rules.MalformedPathSum _) -> check bool "valid path sum" true false

let test_variable_replacement_returns_none () =
  let input : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 0 |]; path_var = [] }
  in
  match Rules.Variable_replacement.variable_replacement input with
  | Ok None -> check bool "no replacement" true true
  | Ok (Some _) -> check bool "no replacement expected" true false
  | Error (Rules.MalformedPathSum _) -> check bool "valid path sum" true false

let test_variable_replacement_reports_malformed_path_sum () =
  let malformed_path_sum : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 0 |]; path_var = [ 0 ] }
  in
  match
    Rules.Variable_replacement.variable_replacement malformed_path_sum
  with
  | Error (Rules.MalformedPathSum _) -> check bool "malformed path sum" true true
  | Ok _ -> check bool "malformed path sum expected" true false

let test_replace_not_path_var_by_var_does_not_mutate_input () =
  let input : Path_sum.t =
    {
      phase = Poly.zero;
      ket = [| Qubit.SumMod2 (Qubit.One, Qubit.Var 2) |];
      path_var = [ 2 ];
    }
  in
  let input_before = PSS.exact input in
  let output = Rules.Variable_replacement.replace_not_path_var_by_var input in
  let expected_output : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Var 2 |]; path_var = [ 2 ] }
  in
  check string "input unchanged" input_before (PSS.exact input);
  check string "replacement result" (PSS.exact expected_output) (PSS.exact output)

let v i = Qubit.Var i
let mdiv s = Monome.Scal s

(* TODO : restore variable replacement without reordening *)

let variable_replacement =
  [
    ( "variable_replacement returns typed replacement",
      `Quick,
      test_variable_replacement_returns_typed_replacement );
    ( "variable_replacement returns none",
      `Quick,
      test_variable_replacement_returns_none );
    ( "variable_replacement reports malformed path sum",
      `Quick,
      test_variable_replacement_reports_malformed_path_sum );
    ( "replace_not_path_var_by_var does not mutate input",
      `Quick,
      test_replace_not_path_var_by_var_does_not_mutate_input );
    ( "|x0> -> |x0>",
      `Quick,
      test_variable_replacement
        { phase = to_poly (Scal Q.zero); ket = [| Var 0 |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| Var 0 |]; path_var = [] } );
    ( "|x0+x1> -> |x0+x1>",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0; Var 1 |];
          path_var = [];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0; Var 1 |];
          path_var = [];
        } );
    ( "|y0> -> |y0>",
      `Quick,
      test_variable_replacement
        { phase = to_poly (Scal Q.zero); ket = [| Var 1 |]; path_var = [ 1 ] }
        { phase = to_poly (Scal Q.zero); ket = [| Var 1 |]; path_var = [ 1 ] }
    );
    ( "|0> -> |0>",
      `Quick,
      test_variable_replacement
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.Zero |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.Zero |]; path_var = [] }
    );
    ( "|1> -> |1>",
      `Quick,
      test_variable_replacement
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.One |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| Qubit.One |]; path_var = [] }
    );
    ( "|1+x0> -> |1+x0>",
      `Quick,
      test_variable_replacement
        { phase = to_poly (Scal Q.zero); ket = [| one ++ x0 |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| one ++ x0 |]; path_var = [] }
    );
    ( "|1+y0> -> |y0>",
      `Quick,
      test_variable_replacement
        { phase = Poly.zero; ket = [| one ++ Var 1 |]; path_var = [ 1 ] }
        { phase = Poly.zero; ket = [| Var 1 |]; path_var = [ 1 ] } );
    ( "|1+y0>,y0 -> |y0>,1+y0",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Qubit (v 1));
          ket = [| one ++ v 1 |];
          path_var = [ 1 ];
        }
        {
          phase = Scal Q.one +++ to_poly (Qubit (v 1));
          ket = [| v 1 |];
          path_var = [ 1 ];
        } );
    ( "|1+y0>,y0/2 -> |y0>,1/2 + y0/2",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Prod (mdiv two, Qubit (v 1)));
          ket = [| one ++ v 1 |];
          path_var = [ 1 ];
        }
        {
          phase = mdiv two +++ to_poly (Prod (mdiv two, Qubit (v 1)));
          ket = [| v 1 |];
          path_var = [ 1 ];
        } );
    ( "|0+x0> -> |x0>",
      `Quick,
      test_variable_replacement
        { phase = to_poly (Scal Q.zero); ket = [| zero ++ x0 |]; path_var = [] }
        { phase = to_poly (Scal Q.zero); ket = [| x0 |]; path_var = [] } );
    ( "|0+y0> -> |y0>",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Scal Q.zero);
          ket = [| zero ++ v 1 |];
          path_var = [ 1 ];
        }
        { phase = to_poly (Scal Q.zero); ket = [| v 1 |]; path_var = [ 1 ] } );
    ( "|1+y0,y0> -> |1+y0,y0>",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Scal Q.zero);
          ket = [| one ++ Var 2; Var 2 |];
          path_var = [ 2 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| one ++ Var 2; Var 2 |];
          path_var = [ 2 ];
        } );
    (* ( "|1+y0,y1> -> |y0,y1>",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Scal Q.zero);
          ket = [| one ++ Var 2; Var 3 |];
          path_var = [ 2; 3 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 2; Var 3 |];
          path_var = [ 2; 3 ];
        } ); *)
    (* ( "|x0+y0,y1> -> |x0+y0,y1>",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ v 2; v 3 |];
          path_var = [ 2; 3 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| v 2; v 3 |];
          path_var = [ 2; 3 ];
        } ); *)
    ( "1/4 y0, |x0+y0,y1> -> 1/4 y0, |x0+y0,y1>",
      `Quick,
      let p = to_poly (Prod (Scal div4, Qubit (v 2))) in
      let ps : Path_sum.t =
        { phase = p; ket = [| x0 ++ v 2; v 3 |]; path_var = [ 2; 3 ] }
      in
      test_variable_replacement ps ps );
    ( "1/4 y0, |x0+y0, y0+y1> -> 1/4 y0, |x0+y0, y1>",
      `Quick,
      let p = to_poly (Prod (Scal div4, Qubit (v 2))) in
      let ps : Path_sum.t =
        { phase = p; ket = [| x0 ++ v 2; v 2 ++ v 3 |]; path_var = [ 2; 3 ] }
      in
      let ps' : Path_sum.t =
        { phase = p; ket = [| x0 ++ v 2; v 3 |]; path_var = [ 2; 3 ] }
      in
      test_variable_replacement ps ps' );
    ( "1/4 x0, |x0+y0, y0+y1> -> 1/4 x0, |x0+y0, y0+y1>",
      `Quick,
      let p = to_poly (Prod (Scal div4, Qubit (v 0))) in
      let ps : Path_sum.t =
        { phase = p; ket = [| x0 ++ v 2; v 2 ++ v 3 |]; path_var = [ 2; 3 ] }
      in
      let ps' : Path_sum.t =
        { phase = p; ket = [| x0 ++ v 2; v 3 |]; path_var = [ 2; 3 ] }
      in
      test_variable_replacement ps ps' );
    (* ( "|x0+y0+y1,y1> -> |y0,y1>",
      `Quick,
      test_variable_replacement
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ Var 2 ++ Var 3; Var 3 |];
          path_var = [ 2; 3 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 2; Var 3 |];
          path_var = [ 2; 3 ];
        } ); *)
    ( "|x0+y0+y1,y0,y1> -> |x0+y0+y1,y0,y1>",
      `Quick,
      let ps : Path_sum.t =
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ Var 3 ++ Var 4; Var 3; Var 4 |];
          path_var = [ 3; 4 ];
        }
      in
      test_variable_replacement ps ps );
    ( "|x0+y0+y1> -> |x0+y0+y1>",
      `Quick,
      let ps : Path_sum.t =
        {
          phase = to_poly (Scal Q.zero);
          ket = [| x0 ++ Var 1 ++ Var 2 |];
          path_var = [ 1; 2 ];
        }
      in
      test_variable_replacement ps ps );
  ]

(* let ( ++ ) (m : monome) (p : poly) : poly = Poly.insert m p *)

let test_find_update_pvs (ps : Path_sum.t) update_pvs () =
  let greet =
    Rules.Rename._string_update_pvs (Rules.Rename._find_update_path_var ps)
  in
  let expect = Rules.Rename._string_update_pvs update_pvs in
  let greeting = greet in
  let expected = expect in
  check string (sprintf "generate update pvs ok") expected greeting

let test_path_var_substitute (pvs_input : int list) update pvs_expect () =
  let pvs_greet = Rules.Rename._path_var_substitute pvs_input update in
  let greet = pvs_greet = pvs_expect in
  let greeting = greet in
  let expected = true in
  check bool
    (sprintf
       "Test.test_path_var_substitute,\npvs_greet =\n%s\npvs_expect =\n%s\n"
       (ListBis.string_int pvs_greet)
       (ListBis.string_int pvs_expect))
    expected greeting

let test_substitute_path_var (ps : Path_sum.t) ps_expect () =
  let ps_input = ps in
  let update_pvs = Rules.Rename._find_update_path_var ps_input in
  let ps_greet = Rules.Rename._substitute_path_var ps_input update_pvs in
  let greet = ps_greet = ps_expect in
  let greeting = greet in
  let expected = true in
  check bool
    (sprintf "Test.test_substitute_path_var,\nps_greet =\n%s\nps_expect =\n%s\n"
       (PSS.pretty ps_greet) (PSS.pretty ps_expect))
    expected greeting

let test_substitute_path_var_does_not_mutate_input () =
  let ps_input : Path_sum.t =
    {
      phase = to_poly (Qubit (Qubit.Var 2));
      ket = [| Qubit.Var 2 |];
      path_var = [ 2 ];
    }
  in
  let input_before = PSS.exact ps_input in
  let ps_greet = Rules.Rename._substitute_path_var ps_input [ (2, 1) ] in
  let ps_expect : Path_sum.t =
    {
      phase = to_poly (Qubit (Qubit.Var 1));
      ket = [| Qubit.Var 1 |];
      path_var = [ 1 ];
    }
  in
  check string "input unchanged" input_before (PSS.exact ps_input);
  check string "substitution result" (PSS.exact ps_expect) (PSS.exact ps_greet)

let update_pvs =
  [
    ( "find_pvs ps1",
      `Quick,
      test_find_update_pvs
        { phase = to_poly (Scal Q.zero); ket = [| Var 0 |]; path_var = [ 1 ] }
        [ (1, 1) ] );
    ( "find_pvs ps2",
      `Quick,
      test_find_update_pvs
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0 |];
          path_var = [ 1; 2 ];
        }
        [ (1, 1); (2, 2) ] );
    ( "find_pvs ps3",
      `Quick,
      test_find_update_pvs
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0 |];
          path_var = [ 1; 3 ];
        }
        [ (1, 1); (3, 2) ] );
    ( "find_pvs ps4",
      `Quick,
      test_find_update_pvs
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0 |];
          path_var = [ 1; 5; 10; 15 ];
        }
        [ (1, 1); (5, 2); (10, 3); (15, 4) ] );
    ( "find_pvs ps5",
      `Quick,
      test_find_update_pvs
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0; Var 4; Var 10; Var 2 |];
          path_var = [ 4; 10 ];
        }
        [ (4, 4); (10, 5) ] );
    ( "pvs_subst pvs1",
      `Quick,
      test_path_var_substitute [ 4; 10 ] [ (4, 2) ] [ 2; 10 ] );
    ( "pvs_subst pvs1",
      `Quick,
      test_path_var_substitute [ 4; 10 ] [ (10, 5) ] [ 4; 5 ] );
    ( "subst_pv ps1",
      `Quick,
      test_substitute_path_var
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0; Var 4; Var 10; Var 2 |];
          path_var = [ 4; 10 ];
        }
        {
          phase = to_poly (Scal Q.zero);
          ket = [| Var 0; Var 4; Var 5; Var 2 |];
          path_var = [ 4; 5 ];
        } );
    ( "subst_pv does not mutate input",
      `Quick,
      test_substitute_path_var_does_not_mutate_input );
  ]

let test_qubit q1 q2 () =
  let greeting = QS.exact q1 in
  let expected = QS.exact q2 in
  check string "same string" expected greeting

let test_qubit_equal_result_returns_true () =
  match Qubit.equal_result ~wq1:1 ~wq2:1 (Var 0) (Var 0) with
  | Ok true -> check bool "equal qubits" true true
  | Ok false -> check bool "equal qubits expected" true false
  | Error _ -> check bool "well-formed comparison expected" true false

let test_qubit_equal_result_returns_false () =
  match Qubit.equal_result Zero One with
  | Ok false -> check bool "different qubits" false false
  | Ok true -> check bool "different qubits expected" false true
  | Error _ -> check bool "well-formed comparison expected" true false

let test_qubit_equal_result_reports_incompatible_widths () =
  match Qubit.equal_result ~wq1:0 ~wq2:1 Zero Zero with
  | Error Qubit.IncompatibleWidths -> check bool "incompatible widths" true true
  | Error Qubit.IncompletePathVariableMap ->
      check bool "incompatible widths expected" true false
  | Ok _ -> check bool "incompatible widths expected" true false

let test_qubit_equal_result_reports_incomplete_path_var_map () =
  let map_path_var1 = IntMap.singleton 1 0 in
  let map_path_var2 = IntMap.empty in
  match
    Qubit.equal_result ~wq1:1 ~wq2:1 ~map_path_var1 ~map_path_var2 (Var 1)
      (Var 1)
  with
  | Error Qubit.IncompletePathVariableMap ->
      check bool "incomplete path variable map" true true
  | Error Qubit.IncompatibleWidths ->
      check bool "incomplete path variable map expected" true false
  | Ok _ -> check bool "incomplete path variable map expected" true false

let test_qubit_remove_result_returns_some () =
  match Qubit.remove_result 1 (Prod (Var 1, Var 2)) with
  | Ok (Some output) -> check string "removed variable" "(Var 2)" (QS.exact output)
  | Ok None -> check bool "removed variable expected" true false
  | Error Qubit.CannotRemoveFromSum ->
      check bool "product expression expected" true false

let test_qubit_remove_result_returns_none () =
  match Qubit.remove_result 3 (Prod (Var 1, Var 2)) with
  | Ok None -> check bool "absent variable" true true
  | Ok (Some _) -> check bool "absent variable expected" true false
  | Error Qubit.CannotRemoveFromSum ->
      check bool "product expression expected" true false

let test_qubit_remove_result_reports_sum () =
  match Qubit.remove_result 1 (SumMod2 (Var 1, Var 2)) with
  | Error Qubit.CannotRemoveFromSum ->
      check bool "sum expression rejected" true true
  | Ok _ -> check bool "sum expression rejection expected" true false

let qubit =
  [
    ( "equal_result returns true",
      `Quick,
      test_qubit_equal_result_returns_true );
    ( "equal_result returns false",
      `Quick,
      test_qubit_equal_result_returns_false );
    ( "equal_result reports incompatible widths",
      `Quick,
      test_qubit_equal_result_reports_incompatible_widths );
    ( "equal_result reports incomplete path variable map",
      `Quick,
      test_qubit_equal_result_reports_incomplete_path_var_map );
    ("remove_result returns some", `Quick, test_qubit_remove_result_returns_some);
    ("remove_result returns none", `Quick, test_qubit_remove_result_returns_none);
    ("remove_result reports sum", `Quick, test_qubit_remove_result_reports_sum);
    ( "simplify: x0.(1 ++ x0) -> Zero",
      `Quick,
      test_qubit (Qubit.simplify (Prod (Var 0, One ++ Var 0))) Zero );
    ( "simplify: (x0.(1 ++ x0) ++ x1.x0) -> x0.x1",
      `Quick,
      test_qubit
        (Qubit.simplify
           (SumMod2 (Prod (Var 0, One ++ Var 0), Prod (Var 1, Var 0))))
        (Prod (Var 0, Var 1)) );
    ( "simplify: (x0.(1 ++ x0) ++ x1.One) -> x1",
      `Quick,
      test_qubit
        (Qubit.simplify
           (SumMod2 (Prod (Var 5, One ++ Var 5), Prod (Var 2, One))))
        (Var 2) );
  ]

let test_ket k1 k2 () =
  let greeting = KS.exact k1 in
  let expected = KS.exact k2 in
  check string "same string" expected greeting

let test_ket_equal_result_returns_true () =
  match Ket.equal_result [| Qubit.Var 0 |] [| Qubit.Var 0 |] with
  | Ok (true, _, _) -> check bool "equal kets" true true
  | Ok (false, _, _) -> check bool "equal kets expected" true false
  | Error _ -> check bool "well-formed comparison expected" true false

let test_ket_equal_result_returns_false () =
  match Ket.equal_result [| Qubit.Zero |] [| Qubit.One |] with
  | Ok (false, _, _) -> check bool "different kets" false false
  | Ok (true, _, _) -> check bool "different kets expected" false true
  | Error _ -> check bool "well-formed comparison expected" true false

let test_ket_equal_result_reports_different_output_lengths () =
  match
    Ket.equal_result ~outputs1:[ 0 ] ~outputs2:[ 0; 1 ]
      [| Qubit.Var 0; Qubit.Var 1 |]
      [| Qubit.Var 0; Qubit.Var 1 |]
  with
  | Error Ket.DifferentOutputLengths ->
      check bool "different output lengths" true true
  | Error Ket.InvalidOutputIndex ->
      check bool "different output lengths expected" true false
  | Ok _ -> check bool "different output lengths expected" true false

let test_ket_equal_result_reports_invalid_output_index () =
  match
    Ket.equal_result ~outputs1:[ 1 ] ~outputs2:[ 0 ] [| Qubit.Var 0 |]
      [| Qubit.Var 0 |]
  with
  | Error Ket.InvalidOutputIndex -> check bool "invalid output index" true true
  | Error Ket.DifferentOutputLengths ->
      check bool "invalid output index expected" true false
  | Ok _ -> check bool "invalid output index expected" true false

let test_ket_path_var_order_result_returns_order () =
  (* For a ket of width 2, variables 0 and 1 are input/output variables x0,x1.
     Variables starting at 2 are path variables y0,y1,... *)
  let check_ok name ket path_var_count expected_tmp expected_final =
    match Ket.path_var_order_result ket path_var_count with
    | Ok (tmp_path_vars, path_vars) ->
        check string (name ^ " temporary path vars") expected_tmp
          (ArrayBis.string_int tmp_path_vars);
        check string (name ^ " path vars") expected_final
          (ArrayBis.string_int path_vars)
    | Error Ket.InvalidPathVariableCount ->
        check bool "valid path-variable count expected" true false
    | Error Ket.InvalidPathVariableIndex ->
        check bool "valid path-variable indices expected" true false
  in
  (* The ket contains y0 then y1. The function records their final order
     [2;3] and a temporary negative order [-2;-3] used during renaming. *)
  check_ok "ordered path vars" [| Qubit.Var 2; Qubit.Var 3 |] 2 "-2;-3" "2;3";
  (* With width 1 and no declared path variable, Var 0 is just x0. *)
  check_ok "no path vars" [| Qubit.Var 0 |] 0 "" ""

let test_ket_path_var_order_result_reports_invalid_path_var_count () =
  (* A negative number of declared path variables is malformed metadata. *)
  match Ket.path_var_order_result [||] (-1) with
  | Error Ket.InvalidPathVariableCount ->
      check bool "invalid path-variable count" true true
  | Error Ket.InvalidPathVariableIndex ->
      check bool "invalid path-variable count expected" true false
  | Ok _ -> check bool "invalid path-variable count expected" true false

let test_ket_path_var_order_result_reports_invalid_path_var_index () =
  (* Width is 1, so Var 2 would be y1. With only one declared path variable,
     the only valid path variable is y0, encoded as Var 1. *)
  match Ket.path_var_order_result [| Qubit.Var 2 |] 1 with
  | Error Ket.InvalidPathVariableIndex ->
      check bool "invalid path-variable index" true true
  | Error Ket.InvalidPathVariableCount ->
      check bool "invalid path-variable index expected" true false
  | Ok _ -> check bool "invalid path-variable index expected" true false

let test_ket_substitute_does_not_mutate_input () =
  let input =
    [| Qubit.Var 1; Qubit.SumMod2 (Qubit.Var 1, Qubit.Var 2) |]
  in
  let input_before = KS.exact input in
  let output = Ket.substitute input 1 (Qubit.Var 3) in
  let expected =
    [| Qubit.Var 3; Qubit.SumMod2 (Qubit.Var 2, Qubit.Var 3) |]
  in
  check string "input unchanged" input_before (KS.exact input);
  check string "substitution result" (KS.exact expected) (KS.exact output)

let test_ket_substitute_reuses_input_when_unchanged () =
  let input = [| Qubit.Var 0 |] in
  let output = Ket.substitute input 1 (Qubit.Var 2) in
  check bool "same array when unchanged" true (input == output)

let test_ket_substitute_many_single_pass () =
  let input = [| Qubit.Var 1; Qubit.Var 2 |] in
  let input_before = KS.exact input in
  let output =
    Ket.substitute_many input [ (1, Qubit.Var 2); (2, Qubit.One) ]
  in
  let expected = [| Qubit.Var 2; Qubit.One |] in
  check string "input unchanged" input_before (KS.exact input);
  check string "substitution result" (KS.exact expected) (KS.exact output)

let k1 =
  [|
    Qubit.Var 0;
    SumMod2
      ( Prod (Prod (Var 0, Var 1), Var 2),
        SumMod2 (Prod (Prod (Var 0, Var 1), Var 2), Var 2) );
    Var 3;
  |]

let k1_simplified = Ket.simplify k1
let k2 = [| Qubit.Var 0; Var 2; Var 3 |]

let k3 =
  [|
    Qubit.Var 0;
    SumMod2
      ( Prod (Var 0, Prod (Var 1, Var 2)),
        SumMod2 (Prod (Prod (Var 1, Var 2), Var 0), Var 2) );
    Var 3;
  |]

let k3_simplified = Ket.simplify k3
let k4 = [| Qubit.Var 0; Var 2; Var 3 |]

let ket =
  [
    ("equal_result returns true", `Quick, test_ket_equal_result_returns_true);
    ("equal_result returns false", `Quick, test_ket_equal_result_returns_false);
    ( "equal_result reports different output lengths",
      `Quick,
      test_ket_equal_result_reports_different_output_lengths );
    ( "equal_result reports invalid output index",
      `Quick,
      test_ket_equal_result_reports_invalid_output_index );
    ( "path_var_order_result returns order",
      `Quick,
      test_ket_path_var_order_result_returns_order );
    ( "path_var_order_result reports invalid path-variable count",
      `Quick,
      test_ket_path_var_order_result_reports_invalid_path_var_count );
    ( "path_var_order_result reports invalid path-variable index",
      `Quick,
      test_ket_path_var_order_result_reports_invalid_path_var_index );
    ("(x0.x1 ++ (x0.x1 ++ x2) -> x2", `Quick, test_ket k1_simplified k2);
    ("(x0.x1.x2 ++ (x1.x2.x0 ++ x3) -> x3", `Quick, test_ket k3_simplified k4);
    ( "(x0,(x0.(1 ++ x0) ++ x1.One) -> x1",
      `Quick,
      test_ket
        (Ket.simplify
           [| Var 0; SumMod2 (Prod (Var 5, One ++ Var 5), Prod (Var 2, One)) |])
        [| Var 0; Var 2 |] );
    ( "(x0,(x0.(1 ++ x0) ++ x1.x2) -> x1",
      `Quick,
      test_ket
        (Ket.simplify
           [|
             Var 0; SumMod2 (Prod (Var 5, One ++ Var 5), Prod (Var 2, Var 3));
           |])
        [| Var 0; Prod (Var 2, Var 3) |] );
    ( "substitute does not mutate input",
      `Quick,
      test_ket_substitute_does_not_mutate_input );
    ( "substitute reuses input when unchanged",
      `Quick,
      test_ket_substitute_reuses_input_when_unchanged );
    ( "substitute_many is single pass",
      `Quick,
      test_ket_substitute_many_single_pass );
  ]

let test_gates_apply ?(debug = true) (p : Program.t) (ps : Path_sum.t) () =
  let greeting =
    printf "Test.test_gates_apply, ps =\n%s\n\n" (PSS.pretty ps);
    printf "Test.test_gates_apply, p =\n%s\n\n" (ProgS.pretty p);

    let ps_exe = Program.execution p in
    if debug then
      printf "Test.test_apply_gates, ps_exe =\n%s\n\n" (PSS.pretty ps_exe);
    let ps_greet = reduce_valid_path_sum ~debug ps_exe in
    if debug then
      printf "Test.test_apply_gates, ps_greet =\n%s\n\n" (PSS.pretty ps_greet);
    let ps_expect = reduce_valid_path_sum ~debug ps in
    printf "\nTest.test_gates_apply, ps_expect =\n%s\n\n" (PSS.pretty ps_expect);
    Path_sum.equal ~debug ps_greet ps_expect
  in
  let expected = true in
  check bool
    (sprintf "Test.test_gates_apply\np = %s\n" (ProgS.pretty p))
    expected greeting

let test_path_sum_library_h_result_returns_path_sum () =
  (* For width 1, target 0 is x0 and the first path variable is y0 = Var 1. *)
  (* H maps |x0> to sum_y exp(2.pi.i.x0.y0/2)|y0>. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Prod
          ( Monome.Scal div2,
            Monome.Prod
              (Monome.Qubit (Qubit.Var 0), Monome.Qubit (Qubit.Var 1)) )
        +++ Poly.empty;
      ket = [| Qubit.Var 1 |];
      path_var = [ 1 ];
    }
  in
  match Path_sum_library.h_result 0 1 with
  | Ok path_sum ->
      check string "h gate path sum" (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let test_path_sum_library_h_result_reports_invalid_target () =
  (* Target 1 is outside width 1; the typed constructor reports that directly. *)
  match Path_sum_library.h_result 1 1 with
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

let test_path_sum_library_x_result_returns_path_sum () =
  (* For width 1, target 0 is the only valid input variable: x0. *)
  (* X maps |x0> to |1+x0> and does not introduce phase or path variables. *)
  let expected : Path_sum.t =
    {
      phase = Monome.Scal Q.zero +++ Poly.empty;
      ket = [| Qubit.SumMod2 (Qubit.One, Qubit.Var 0) |];
      path_var = [];
    }
  in
  match Path_sum_library.x_result 0 1 with
  | Ok path_sum ->
      check string "x gate path sum" (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let test_path_sum_library_x_result_reports_invalid_target () =
  (* Target indices are zero-based: target 1 is outside a width-1 path sum. *)
  (* This checks the typed error that replaces the old unchecked xx failure. *)
  match Path_sum_library.x_result 1 1 with
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

let test_path_sum_library_u1_result_returns_path_sum () =
  (* With k=1 and default s=1, U1 adds the phase x0 / 2 and keeps |x0>. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Prod (Monome.Scal div2, Monome.Qubit (Qubit.Var 0))
        +++ Poly.empty;
      ket = [| Qubit.Var 0 |];
      path_var = [];
    }
  in
  match Path_sum_library.u1_result 1 0 1 with
  | Ok path_sum ->
      check string "u1 gate path sum" (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let test_path_sum_library_u1_result_reports_invalid_target () =
  (* U1 also relies on xx: target 1 is outside width 1 and must be reported. *)
  match Path_sum_library.u1_result 1 1 1 with
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

let test_path_sum_library_z_result_returns_path_sum () =
  (* Z is U1 with k=1: it adds phase x0 / 2 and keeps |x0>. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Prod (Monome.Scal div2, Monome.Qubit (Qubit.Var 0))
        +++ Poly.empty;
      ket = [| Qubit.Var 0 |];
      path_var = [];
    }
  in
  match Path_sum_library.z_result 0 1 with
  | Ok path_sum ->
      check string "z gate path sum" (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let test_path_sum_library_z_result_reports_invalid_target () =
  (* z_result delegates target validation to u1_result and reports the same error. *)
  match Path_sum_library.z_result 1 1 with
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

let test_path_sum_library_s_result_returns_path_sum () =
  (* S is U1 with k=2: it adds phase x0 / 4 and keeps |x0>. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Prod (Monome.Scal div4, Monome.Qubit (Qubit.Var 0))
        +++ Poly.empty;
      ket = [| Qubit.Var 0 |];
      path_var = [];
    }
  in
  match Path_sum_library.s_result 0 1 with
  | Ok path_sum ->
      check string "s gate path sum" (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let test_path_sum_library_s_result_reports_invalid_target () =
  (* s_result delegates target validation to u1_result and reports the same error. *)
  match Path_sum_library.s_result 1 1 with
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

let test_path_sum_library_t_result_returns_path_sum () =
  (* T is U1 with k=3: it adds phase x0 / 8 and keeps |x0>. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Prod (Monome.Scal div8, Monome.Qubit (Qubit.Var 0))
        +++ Poly.empty;
      ket = [| Qubit.Var 0 |];
      path_var = [];
    }
  in
  match Path_sum_library.t_result 0 1 with
  | Ok path_sum ->
      check string "t gate path sum" (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let test_path_sum_library_t_result_reports_invalid_target () =
  (* t_result delegates target validation to u1_result and reports the same error. *)
  match Path_sum_library.t_result 1 1 with
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

let test_path_sum_library_zinv_result_returns_path_sum () =
  (* Z inverse is U1 with s=-1 and k=1. The negative angle is normalized to
     1/2, so the expected path sum is the same as Z on one qubit. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Prod (Monome.Scal div2, Monome.Qubit (Qubit.Var 0))
        +++ Poly.empty;
      ket = [| Qubit.Var 0 |];
      path_var = [];
    }
  in
  match Path_sum_library.zinv_result 0 1 with
  | Ok path_sum ->
      check string "zinv gate path sum" (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let test_path_sum_library_zinv_result_reports_invalid_target () =
  (* zinv_result delegates target validation to u1_result and reports the same error. *)
  match Path_sum_library.zinv_result 1 1 with
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

(* These helpers keep the gate-result tests focused on the expected path sum
   instead of repeating the same Ok/Error plumbing in every case. *)
let check_gate_result name expected = function
  | Ok path_sum -> check string name (PSS.exact expected) (PSS.exact path_sum)
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "valid target expected" true false

let check_gate_invalid_target = function
  | Error Path_sum_library.TargetIndexOutOfWidth ->
      check bool "invalid target rejected" true true
  | Ok _ -> check bool "invalid target expected" true false

let one_qubit_phase_path_sum scalar : Path_sum.t =
  {
    phase =
      Monome.Prod (Monome.Scal scalar, Monome.Qubit (Qubit.Var 0))
      +++ Poly.empty;
    ket = [| Qubit.Var 0 |];
    path_var = [];
  }

let test_path_sum_library_sinv_result_returns_path_sum () =
  (* S inverse is U1 with s=-1 and k=2; -1/4 is normalized to 3/4. *)
  check_gate_result "sinv gate path sum"
    (one_qubit_phase_path_sum (3 /// 4))
    (Path_sum_library.sinv_result 0 1)

let test_path_sum_library_sinv_result_reports_invalid_target () =
  (* sinv_result reports the same target-width error as u1_result. *)
  check_gate_invalid_target (Path_sum_library.sinv_result 1 1)

let test_path_sum_library_tinv_result_returns_path_sum () =
  (* T inverse is U1 with s=-1 and k=3; -1/8 is normalized to 7/8. *)
  check_gate_result "tinv gate path sum"
    (one_qubit_phase_path_sum (7 /// 8))
    (Path_sum_library.tinv_result 0 1)

let test_path_sum_library_tinv_result_reports_invalid_target () =
  (* tinv_result reports the same target-width error as u1_result. *)
  check_gate_invalid_target (Path_sum_library.tinv_result 1 1)

let test_path_sum_library_rz_result_returns_path_sum () =
  (* RZ with k=1 adds the global term 3/4 and the target phase x0/2. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Scal (3 /// 4)
        +++ (Monome.Prod (Monome.Scal div2, Monome.Qubit (Qubit.Var 0))
            +++ Poly.empty);
      ket = [| Qubit.Var 0 |];
      path_var = [];
    }
  in
  check_gate_result "rz gate path sum" expected (Path_sum_library.rz_result 1 0 1)

let test_path_sum_library_rz_result_reports_invalid_target () =
  (* rz_result validates its target before building the phase polynomial. *)
  check_gate_invalid_target (Path_sum_library.rz_result 1 1 1)

let test_path_sum_library_rx_result_returns_path_sum () =
  (* With s=0, RX is represented here as the identity path sum on the target. *)
  let expected : Path_sum.t =
    { phase = Monome.Scal Q.zero +++ Poly.empty; ket = [| Qubit.Var 0 |]; path_var = [] }
  in
  check_gate_result "rx gate path sum" expected
    (Path_sum_library.rx_result ~s:0 1 0 1)

let test_path_sum_library_rx_result_reports_invalid_target () =
  (* rx_result still validates the target even when s=0 makes the phase trivial. *)
  check_gate_invalid_target (Path_sum_library.rx_result ~s:0 1 1 1)

let test_path_sum_library_ry_result_returns_path_sum () =
  (* With s=0, RY is represented here as the identity path sum on the target. *)
  let expected : Path_sum.t =
    { phase = Monome.Scal Q.zero +++ Poly.empty; ket = [| Qubit.Var 0 |]; path_var = [] }
  in
  check_gate_result "ry gate path sum" expected
    (Path_sum_library.ry_result ~s:0 1 0 1)

let test_path_sum_library_ry_result_reports_invalid_target () =
  (* ry_result still validates the target even when s=0 makes the phase trivial. *)
  check_gate_invalid_target (Path_sum_library.ry_result ~s:0 1 1 1)

let test_path_sum_library_ch_result_returns_path_sum () =
  (* CH introduces one path variable y0 = Var 2 for width 2. The phase is the
     controlled-Hadamard phase plus its normalization factor. *)
  let control = Qubit.Var 0 in
  let target = Qubit.Var 1 in
  let path_var = Qubit.Var 2 in
  let normalisation =
    Monome.Scal div8
    +++ (Monome.Prod (Monome.Scal divm8, Monome.Qubit control)
        +++ (Monome.Prod
               ( Monome.Scal div4,
                 Monome.Prod (Monome.Qubit control, Monome.Qubit path_var) )
            +++ (Monome.Prod (Monome.Scal divm4, Monome.Qubit path_var)
                +++ Poly.empty)))
  in
  let expected : Path_sum.t =
    {
      phase =
        Poly.simplify
          (Monome.Prod
             ( Monome.Scal div2,
               Monome.Prod
                 ( Monome.Qubit control,
                   Monome.Prod (Monome.Qubit target, Monome.Qubit path_var) ) )
          +++ normalisation);
      ket =
        Ket.simplify
          [|
            control;
            Qubit.SumMod2
              ( Qubit.Prod (control, target),
                Qubit.SumMod2 (Qubit.Prod (control, path_var), target) );
          |];
      path_var = [ 2 ];
    }
  in
  check_gate_result "ch gate path sum" expected (Path_sum_library.ch_result 0 1 2)

let test_path_sum_library_ch_result_reports_invalid_target () =
  (* ch_result validates both selected input variables from left to right. *)
  check_gate_invalid_target (Path_sum_library.ch_result 0 2 2)

let test_path_sum_library_cx_result_returns_path_sum () =
  (* CX maps |x0,x1> to |x0,x0+x1> without phase or path variables. *)
  let expected : Path_sum.t =
    {
      phase = Monome.Scal Q.zero +++ Poly.empty;
      ket = [| Qubit.Var 0; Qubit.SumMod2 (Qubit.Var 0, Qubit.Var 1) |];
      path_var = [];
    }
  in
  check_gate_result "cx gate path sum" expected (Path_sum_library.cx_result 0 1 2)

let test_path_sum_library_cx_result_reports_invalid_target () =
  (* cx_result reports an out-of-width control or target. *)
  check_gate_invalid_target (Path_sum_library.cx_result 0 2 2)

let controlled_phase_path_sum scalar : Path_sum.t =
  {
    phase =
      Monome.Prod
        ( Monome.Scal scalar,
          Monome.Prod (Monome.Qubit (Qubit.Var 0), Monome.Qubit (Qubit.Var 1)) )
      +++ Poly.empty;
    ket = [| Qubit.Var 0; Qubit.Var 1 |];
    path_var = [];
  }

let test_path_sum_library_crz_result_returns_path_sum () =
  (* CRZ with k=1 adds the controlled phase x0.x1/2. *)
  check_gate_result "crz gate path sum"
    (controlled_phase_path_sum div2)
    (Path_sum_library.crz_result 1 0 1 2)

let test_path_sum_library_crz_result_reports_invalid_target () =
  (* crz_result validates both selected input variables. *)
  check_gate_invalid_target (Path_sum_library.crz_result 1 0 2 2)

let test_path_sum_library_cz_result_returns_path_sum () =
  (* CZ is CRZ with k=1. *)
  check_gate_result "cz gate path sum"
    (controlled_phase_path_sum div2)
    (Path_sum_library.cz_result 0 1 2)

let test_path_sum_library_cz_result_reports_invalid_target () =
  (* cz_result reports the same target-width error as crz_result. *)
  check_gate_invalid_target (Path_sum_library.cz_result 0 2 2)

let test_path_sum_library_cs_result_returns_path_sum () =
  (* CS is CRZ with k=2, so the controlled phase is x0.x1/4. *)
  check_gate_result "cs gate path sum"
    (controlled_phase_path_sum div4)
    (Path_sum_library.cs_result 0 1 2)

let test_path_sum_library_cs_result_reports_invalid_target () =
  (* cs_result reports the same target-width error as crz_result. *)
  check_gate_invalid_target (Path_sum_library.cs_result 0 2 2)

let test_path_sum_library_ct_result_returns_path_sum () =
  (* CT is CRZ with k=3, so the controlled phase is x0.x1/8. *)
  check_gate_result "ct gate path sum"
    (controlled_phase_path_sum div8)
    (Path_sum_library.ct_result 0 1 2)

let test_path_sum_library_ct_result_reports_invalid_target () =
  (* ct_result reports the same target-width error as crz_result. *)
  check_gate_invalid_target (Path_sum_library.ct_result 0 2 2)

let test_path_sum_library_ccx_result_returns_path_sum () =
  (* CCX maps |x0,x1,x2> to |x0,x1,x0.x1+x2>. *)
  let expected : Path_sum.t =
    {
      phase = Monome.Scal Q.zero +++ Poly.empty;
      ket =
        [|
          Qubit.Var 0;
          Qubit.Var 1;
          Qubit.SumMod2
            (Qubit.Prod (Qubit.Var 0, Qubit.Var 1), Qubit.Var 2);
        |];
      path_var = [];
    }
  in
  check_gate_result "ccx gate path sum" expected
    (Path_sum_library.ccx_result 0 1 2 3)

let test_path_sum_library_ccx_result_reports_invalid_target () =
  (* ccx_result validates both controls and the target. *)
  check_gate_invalid_target (Path_sum_library.ccx_result 0 1 3 3)

let test_path_sum_library_ccz_result_returns_path_sum () =
  (* CCZ adds the triple controlled phase x0.x1.x2/2. *)
  let expected : Path_sum.t =
    {
      phase =
        Monome.Prod
          ( Monome.Scal div2,
            Monome.Prod
              ( Monome.Qubit (Qubit.Var 0),
                Monome.Prod
                  (Monome.Qubit (Qubit.Var 1), Monome.Qubit (Qubit.Var 2)) ) )
        +++ Poly.empty;
      ket = [| Qubit.Var 0; Qubit.Var 1; Qubit.Var 2 |];
      path_var = [];
    }
  in
  check_gate_result "ccz gate path sum" expected
    (Path_sum_library.ccz_result 0 1 2 3)

let test_path_sum_library_ccz_result_reports_invalid_target () =
  (* ccz_result validates both controls and the target. *)
  check_gate_invalid_target (Path_sum_library.ccz_result 0 1 3 3)

let test_apply_hadamard_does_not_mutate_input () =
  let input = Path_sum.ofSize 1 in
  let input_before = PSS.exact input in
  let _ = Gates.Apply_gates.apply_hadamard input [] 0 in
  check string "input unchanged" input_before (PSS.exact input)

let test_apply_not_does_not_mutate_input () =
  let input = Path_sum.ofSize 1 in
  let input_before = PSS.exact input in
  let _ = Gates.Apply_gates.apply_not input [] 0 in
  check string "input unchanged" input_before (PSS.exact input)

let test_apply_classical_not_does_not_mutate_input () =
  let input : Path_sum.t =
    { phase = Poly.zero; ket = [| Qubit.Zero |]; path_var = [] }
  in
  let input_before = PSS.exact input in
  let _ = Gates.Apply_gates.apply_classical_not input 0 in
  check string "input unchanged" input_before (PSS.exact input)

let gates_apply =
  [
    ( "h_result returns path sum",
      `Quick,
      test_path_sum_library_h_result_returns_path_sum );
    ( "h_result reports invalid target",
      `Quick,
      test_path_sum_library_h_result_reports_invalid_target );
    ( "x_result returns path sum",
      `Quick,
      test_path_sum_library_x_result_returns_path_sum );
    ( "x_result reports invalid target",
      `Quick,
      test_path_sum_library_x_result_reports_invalid_target );
    ( "u1_result returns path sum",
      `Quick,
      test_path_sum_library_u1_result_returns_path_sum );
    ( "u1_result reports invalid target",
      `Quick,
      test_path_sum_library_u1_result_reports_invalid_target );
    ( "z_result returns path sum",
      `Quick,
      test_path_sum_library_z_result_returns_path_sum );
    ( "z_result reports invalid target",
      `Quick,
      test_path_sum_library_z_result_reports_invalid_target );
    ( "s_result returns path sum",
      `Quick,
      test_path_sum_library_s_result_returns_path_sum );
    ( "s_result reports invalid target",
      `Quick,
      test_path_sum_library_s_result_reports_invalid_target );
    ( "t_result returns path sum",
      `Quick,
      test_path_sum_library_t_result_returns_path_sum );
    ( "t_result reports invalid target",
      `Quick,
      test_path_sum_library_t_result_reports_invalid_target );
    ( "zinv_result returns path sum",
      `Quick,
      test_path_sum_library_zinv_result_returns_path_sum );
    ( "zinv_result reports invalid target",
      `Quick,
      test_path_sum_library_zinv_result_reports_invalid_target );
    ( "sinv_result returns path sum",
      `Quick,
      test_path_sum_library_sinv_result_returns_path_sum );
    ( "sinv_result reports invalid target",
      `Quick,
      test_path_sum_library_sinv_result_reports_invalid_target );
    ( "tinv_result returns path sum",
      `Quick,
      test_path_sum_library_tinv_result_returns_path_sum );
    ( "tinv_result reports invalid target",
      `Quick,
      test_path_sum_library_tinv_result_reports_invalid_target );
    ( "rz_result returns path sum",
      `Quick,
      test_path_sum_library_rz_result_returns_path_sum );
    ( "rz_result reports invalid target",
      `Quick,
      test_path_sum_library_rz_result_reports_invalid_target );
    ( "rx_result returns path sum",
      `Quick,
      test_path_sum_library_rx_result_returns_path_sum );
    ( "rx_result reports invalid target",
      `Quick,
      test_path_sum_library_rx_result_reports_invalid_target );
    ( "ry_result returns path sum",
      `Quick,
      test_path_sum_library_ry_result_returns_path_sum );
    ( "ry_result reports invalid target",
      `Quick,
      test_path_sum_library_ry_result_reports_invalid_target );
    ( "ch_result returns path sum",
      `Quick,
      test_path_sum_library_ch_result_returns_path_sum );
    ( "ch_result reports invalid target",
      `Quick,
      test_path_sum_library_ch_result_reports_invalid_target );
    ( "cx_result returns path sum",
      `Quick,
      test_path_sum_library_cx_result_returns_path_sum );
    ( "cx_result reports invalid target",
      `Quick,
      test_path_sum_library_cx_result_reports_invalid_target );
    ( "crz_result returns path sum",
      `Quick,
      test_path_sum_library_crz_result_returns_path_sum );
    ( "crz_result reports invalid target",
      `Quick,
      test_path_sum_library_crz_result_reports_invalid_target );
    ( "cz_result returns path sum",
      `Quick,
      test_path_sum_library_cz_result_returns_path_sum );
    ( "cz_result reports invalid target",
      `Quick,
      test_path_sum_library_cz_result_reports_invalid_target );
    ( "cs_result returns path sum",
      `Quick,
      test_path_sum_library_cs_result_returns_path_sum );
    ( "cs_result reports invalid target",
      `Quick,
      test_path_sum_library_cs_result_reports_invalid_target );
    ( "ct_result returns path sum",
      `Quick,
      test_path_sum_library_ct_result_returns_path_sum );
    ( "ct_result reports invalid target",
      `Quick,
      test_path_sum_library_ct_result_reports_invalid_target );
    ( "ccx_result returns path sum",
      `Quick,
      test_path_sum_library_ccx_result_returns_path_sum );
    ( "ccx_result reports invalid target",
      `Quick,
      test_path_sum_library_ccx_result_reports_invalid_target );
    ( "ccz_result returns path sum",
      `Quick,
      test_path_sum_library_ccz_result_returns_path_sum );
    ( "ccz_result reports invalid target",
      `Quick,
      test_path_sum_library_ccz_result_reports_invalid_target );
    ( "apply_hadamard does not mutate input",
      `Quick,
      test_apply_hadamard_does_not_mutate_input );
    ( "apply_not does not mutate input",
      `Quick,
      test_apply_not_does_not_mutate_input );
    ( "apply_classical_not does not mutate input",
      `Quick,
      test_apply_classical_not_does_not_mutate_input );
    ("id", `Quick, test_gates_apply id (Path_sum.ofSize 0));
    ("h", `Quick, test_gates_apply (h 0) (Path_sum_library.h 0 1));
    ("x", `Quick, test_gates_apply (x 0) (Path_sum_library.x 0 1));
    ("z", `Quick, test_gates_apply (zz 0) (Path_sum_library.z 0 1));
    ("s", `Quick, test_gates_apply (ss 0) (Path_sum_library.s 0 1));
    ("t", `Quick, test_gates_apply (tt 0) (Path_sum_library.t 0 1));
    ("zinv", `Quick, test_gates_apply (zinv 0) (Path_sum_library.zinv 0 1));
    ("sinv", `Quick, test_gates_apply (sinv 0) (Path_sum_library.sinv 0 1));
    ("tinv", `Quick, test_gates_apply (tinv 0) (Path_sum_library.tinv 0 1));
    ("u1 4", `Quick, test_gates_apply (u1 0 0) (Path_sum_library.u1 0 0 1));
    ( "u1 -1",
      `Quick,
      test_gates_apply (u1 ~s:(-1) 1 0) (Path_sum_library.u1 ~s:(-1) 1 0 1) );
    ( "u1 -2",
      `Quick,
      test_gates_apply (u1 ~s:(-1) 2 0) (Path_sum_library.u1 ~s:(-1) 2 0 1) );
    ( "u1 -3 2",
      `Quick,
      test_gates_apply (u1 ~s:(-3) 2 0) (Path_sum_library.u1 ~s:(-3) 2 0 1) );
    ("u1 4", `Quick, test_gates_apply (u1 4 0) (Path_sum_library.u1 4 0 1));
    ("rz 0", `Quick, test_gates_apply (rz 0 0) (Path_sum_library.rz 0 0 1));
    ("rz 4", `Quick, test_gates_apply (rz 4 0) (Path_sum_library.rz 4 0 1));
    ( "rz (-4)",
      `Quick,
      test_gates_apply (rz ~s:(-1) 4 0) (Path_sum_library.rz ~s:(-1) 4 0 1) );
    ("rx 0", `Quick, test_gates_apply (rx 0 0) (Path_sum_library.rx 0 0 1));
    ("rx 1", `Quick, test_gates_apply (rx 1 0) (Path_sum_library.rx 1 0 1));
    ("rx 5", `Quick, test_gates_apply (rx 5 0) (Path_sum_library.rx 5 0 1));
    ( "rx (-5)",
      `Quick,
      test_gates_apply (rx ~s:(-1) 5 0) (Path_sum_library.rx ~s:(-1) 5 0 1) );
    ( "rx (-2,3)",
      `Quick,
      test_gates_apply (rx ~s:(-2) 3 0) (Path_sum_library.rx ~s:(-2) 3 0 1) );
    ("ry 0", `Quick, test_gates_apply (ry 0 0) (Path_sum_library.ry 0 0 1));
    ("ry 1", `Quick, test_gates_apply (ry 1 0) (Path_sum_library.ry 1 0 1));
    ("ry 5", `Quick, test_gates_apply (ry 5 0) (Path_sum_library.ry 5 0 1));
    ( "ry -5",
      `Quick,
      test_gates_apply (ry ~s:(-1) 5 0) (Path_sum_library.ry ~s:(-1) 5 0 1) );
    ( "ry -3/5",
      `Quick,
      test_gates_apply (ry ~s:(-3) 5 0) (Path_sum_library.ry ~s:(-3) 5 0 1) );
    ("ch", `Quick, test_gates_apply (ch 0 1) (Path_sum_library.ch 0 1 2));
    ("cx", `Quick, test_gates_apply (cx 0 1) (Path_sum_library.cx 0 1 2));
    ("cz", `Quick, test_gates_apply (cz 0 1) (Path_sum_library.cz 0 1 2));
    ("cs", `Quick, test_gates_apply (cs 0 1) (Path_sum_library.cs 0 1 2));
    ("ct", `Quick, test_gates_apply (ct 0 1) (Path_sum_library.ct 0 1 2));
    ("ccx", `Quick, test_gates_apply (ccx 0 1 2) (Path_sum_library.ccx 0 1 2 3));
    ("ccz", `Quick, test_gates_apply (ccz 0 1 2) (Path_sum_library.ccz 0 1 2 3));
  ]

let () =
  Alcotest.run "Symbolic execution"
    [
      ("Poly Normalise", poly_normalize);
      (* ("Normalise Path Variables", normalise_path_var); *)
      ("HH", hh);
      ("Path-sum equality", path_sum_equality);
      ("Path-sum initialization", path_sum_initialization);
      ("Path-sum substitution", path_sum_substitution);
      ("Poly equality", poly_equality);
      ("Poly conversion", poly_conversion);
      ("Poly algebra", poly_algebra);
      ("Lift Poly", lift_poly);
      ("Lift Monome", lift_monome);
      ("Lift Qubit", lift_qubit);
      ("Monome equality", monome_equality);
      ("Monome to scalar monome", monome_to_scalar_monome);
      ("Variable replacement Factorisation", variable_replacement_factorisation);
      ("Variable replacement", variable_replacement);
      ("Update Path-vars", update_pvs);
      ("Qubit", qubit);
      ("Ket", ket);
      ("Gates application", gates_apply);
    ]
