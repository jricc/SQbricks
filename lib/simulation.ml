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

(** Execution and reduction failures are kept distinct.
    For example, a too-small input returns [ExecutionError]. *)
type error =
  | ExecutionError of Program.execution_error
  | ReductionError of Rules.reduction_error

(** Runs a unitary circuit on a concrete basis state and reduces its path sum.
    For example, X on [| false |] produces |1>, zero phase and no paths. *)
let execute ~(input : bool array) (circuit : Program.t) :
    (Path_sum.t, error) result =
  let input_width = Array.length input in
  let _, circuit_width = Program.widths circuit in
  (* An empty input is a concrete zero-wire register. The existing executor
     instead treats its empty default input as a request for symbolic inputs. *)
  if input_width < circuit_width then
    Error
      (ExecutionError
         (Program.InputStateTooSmall (circuit_width, input_width)))
  else
    let input_state : Path_sum.t =
      {
        phase = Poly.empty;
        ket =
          Array.map
            (function false -> Qubit.Zero | true -> Qubit.One)
            input;
        path_var = [];
      }
    in
    match Program.execution_result ~input_state circuit with
    | Error execution_error -> Error (ExecutionError execution_error)
    | Ok executed_state -> (
        match
          Reduction_algorithm.reduction_algorithm executed_state
        with
        | Error reduction_error -> Error (ReductionError reduction_error)
        | Ok reduced_state -> Ok reduced_state)

(** {1 Path Expansion} *)

type expanded_path = { basis_state : bool array; phase : Q.t }

type expand_error = PhaseNotScalar | KetNotConcrete

(* Enumerates all 2^m assignments of the path variables.
   For [y0; y1], the order is: y0=0,y1=0; y0=1,y1=0; y0=0,y1=1; y0=1,y1=1. *)
let enumerate_assignments (path_vars : int list) : (int * bool) list list =
  let rec aux vars =
    match vars with
    | [] -> [ [] ]
    | var :: rest ->
        let rest_assignments = aux rest in
        List.concat_map
          (fun assignment ->
            [ (var, false) :: assignment; (var, true) :: assignment ])
          rest_assignments
  in
  aux path_vars

(* Sums the scalar monomes of a variable-free phase polynomial.
   Returns [None] if any monome is not a pure scalar, which means a path
   variable was not fully substituted. *)
let phase_to_rational (p : Poly.t) : Q.t option =
  let rec aux p acc =
    if Poly.is_empty p then Some acc
    else
      let m = Poly.find p in
      let p' = Poly.del p in
      match m with
      | Poly.Monome.Scal q -> aux p' (Q.add acc q)
      | _ -> None
  in
  aux p Q.zero

(* Converts a ket of concrete qubits to a basis state array.
   Returns [None] if any qubit does not simplify to |0> or |1>. *)
let ket_to_basis_state (ket : Qubit.t array) : bool array option =
  let n = Array.length ket in
  let result = Array.make n false in
  let rec aux i =
    if i >= n then Some result
    else
      match Qubit.simplify ket.(i) with
      | Qubit.Zero ->
          result.(i) <- false;
          aux (i + 1)
      | Qubit.One ->
          result.(i) <- true;
          aux (i + 1)
      | _ -> None
  in
  aux 0

(** Unfolds a reduced path sum by enumerating its path variables.
    For example, H on |0> expands to two paths: |0> and |1>, both phase 0. *)
let expand (ps : Path_sum.t) : (expanded_path list, expand_error) result =
  (* Substitutes one assignment and extracts the concrete path, if possible. *)
  let expand_one (assignment : (int * bool) list) :
      (expanded_path, expand_error) result =
    let substitutions =
      List.map
        (fun (var, value) -> (var, if value then Qubit.One else Qubit.Zero))
        assignment
    in
    (* [Path_sum.substitute] rejects path variables; substitute the phase and
       the ket separately instead. *)
    let phase_subst =
      List.fold_left
        (fun phase (var, qubit) -> Poly.substitute var phase qubit)
        ps.phase substitutions
    in
    let ket_subst = Path_sum.Ket.substitute_many ps.ket substitutions in
    match phase_to_rational (Poly.simplify phase_subst) with
    | None -> Error PhaseNotScalar
    | Some phase -> (
        match ket_to_basis_state ket_subst with
        | None -> Error KetNotConcrete
        | Some basis_state -> Ok { basis_state; phase })
  in
  let results = List.map expand_one (enumerate_assignments ps.path_var) in
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | Ok path :: rest -> collect (path :: acc) rest
    | Error e :: _ -> Error e
  in
  collect [] results
