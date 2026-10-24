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

(** {1 Grouping by Basis State} *)

type grouped_path = { basis_state : bool array; amplitude : Complex.t }

(** Sums the amplitudes of the expanded paths leading to the same basis
    state. Each path contributes e^(2πi·phase) / 2^(m/2), so paths with
    opposite phases cancel (destructive interference) and equal phases
    reinforce (constructive interference). For example, grouping the
    expansion of the interference circuit gives amplitude 0 for |100> and
    1/sqrt(2) for |000>. *)
let group ~(path_var_count : int) (paths : expanded_path list) :
    grouped_path list =
  let normalization =
    1. /. Float.pow 2.0 (Float.of_int path_var_count /. 2.0)
  in
  let path_amplitude (phase : Q.t) : Complex.t =
    let angle = 2. *. Float.pi *. Q.to_float phase in
    (* e^(2πi·phase) = exp(i·angle), scaled by the per-path normalization. *)
    Complex.mul
      (Complex.exp { Complex.re = 0.; Complex.im = angle })
      { Complex.re = normalization; Complex.im = 0. }
  in
  (* Association list keyed by basis state. Structural equality on bool
     arrays is the intended comparison for concrete basis states. *)
  let add_path (acc : grouped_path list) (path : expanded_path) :
      grouped_path list =
    let contribution = path_amplitude path.phase in
    let rec aux before = function
      | [] ->
          List.rev_append before
            [ { basis_state = path.basis_state; amplitude = contribution } ]
      | entry :: rest ->
          if entry.basis_state = path.basis_state then
            List.rev_append before
              ( {
                  entry with
                  amplitude = Complex.add entry.amplitude contribution;
                }
              :: rest )
          else aux (entry :: before) rest
    in
    aux [] acc
  in
  List.fold_left add_path [] paths

(** Sparse integer coefficients indexed by root exponents.
    For example, exponent 0 with coefficient 1 represents 1. *)
module ExponentMap = Map.Make (Z)

(** Represents [2^(-scale) * sum_j coeffs[j] * root^j].
    For example, 1 has root exponent 1, scale 0 and coefficient 0:1. *)
type exact_amplitude = {
  root_exponent : int;
      (** Selects [root = exp(2*pi*i / 2^root_exponent)]. *)
  scale : int;
      (** Exponent of the common factor [2^(-scale)]. *)
  coeffs : Z.t ExponentMap.t;
      (** Nonzero integer coefficients, indexed by reduced root exponents. *)
}

(** Prints the exact coordinates without floating-point conversion.
    For example, 1 gives [k=1; s=0; coeffs=[0:1]]. *)
let exact_to_string (amplitude : exact_amplitude) : string =
  let coefficients =
    ExponentMap.bindings amplitude.coeffs
    |> List.map (fun (exponent, coefficient) ->
           Z.to_string exponent ^ ":" ^ Z.to_string coefficient)
    |> String.concat "; "
  in
  Printf.sprintf "k=%d; s=%d; coeffs=[%s]" amplitude.root_exponent
    amplitude.scale coefficients

(** A basis state and its exact summed amplitude.
    For example, one path leading to |0> produces a single entry. *)
type exact_grouped_path = {
  basis_state : bool array;
      (** Concrete output state shared by the grouped paths. *)
  amplitude : exact_amplitude;
      (** Exact sum of the amplitudes leading to this state. *)
}

(** No exact grouping error is produced at this step.
    For example, grouping [] succeeds without an error value. *)
type exact_error = |

(** Handles no paths or one path with phase 0 or 1/2 and no path variables.
    For example, one path to |0> with phase 0 and path count 0 has amplitude 1.
    Other cases are not implemented yet and raise [Failure]. *)
let group_exact ~(path_var_count : int) (paths : expanded_path list) :
    (exact_grouped_path list, exact_error) result =
  match paths with
  | [] -> Ok []
  | [ path ] when path_var_count = 0 && Q.equal path.phase Q.zero ->
      (* With no path variables, normalization and phase both contribute 1. *)
      let amplitude =
        {
          root_exponent = 1;
          scale = 0;
          coeffs = ExponentMap.singleton Z.zero Z.one;
        }
      in
      Ok [ { basis_state = path.basis_state; amplitude } ]
  | [ path ]
    when path_var_count = 0 && Q.equal path.phase (Q.make Z.one (Z.of_int 2)) ->
      (* At k=1, the half-turn phase is -1 times the zeroth root power. *)
      let amplitude =
        {
          root_exponent = 1;
          scale = 0;
          coeffs = ExponentMap.singleton Z.zero Z.minus_one;
        }
      in
      Ok [ { basis_state = path.basis_state; amplitude } ]
  | _ :: _ ->
      (* Temporary boundary: other cases need their own tests first. *)
      failwith "Simulation.group_exact: case not implemented yet"
