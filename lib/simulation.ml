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

(** {1 Exact Grouping by Basis State} *)

(* The record is concrete here; the interface keeps the type abstract so
   that callers cannot build values violating the invariants documented in
   simulation.mli (k >= 1, s >= 0, reduced exponents, no zero
   coefficients). *)
module ExponentMap = Map.Make (Z)

(* An exact amplitude is A = 2^(-s) * sum_j c_j * zeta^j, with
   zeta = e^(2*pi*i/2^k) a primitive 2^k-th root of unity.

   Notations, matching the record fields:
   - k = [root_exponent]: the cyclotomic field Q(zeta) holding all the
     dyadic phases (k >= 1);
   - s = [scale]: the common path factor 2^(-m/2) is factored out, with
     m = the path-variable count and s = m/2 + (m mod 2) (s >= 0);
   - c_j = [coeffs]: signed count of the paths whose phase reduces to
     j/2^k modulo 2^(k-1) (zeta^(j + 2^(k-1)) = -zeta^j); only non-zero
     counts are stored, so the empty map is the zero amplitude.

   Examples: i = zeta_4 is (k=2, s=0, {1 -> 1}); 1/sqrt(2), from H on |0>
   with m = 1, is 2^(-1) * (zeta_8 - zeta_8^3), i.e. (k=3, s=1,
   {1 -> 1; 3 -> -1}). *)
type exact_amplitude = {
  root_exponent : int;
  scale : int;
  coeffs : Z.t ExponentMap.t;
}

type exact_grouped_path = {
  basis_state : bool array;
  amplitude : exact_amplitude;
}

type exact_error = PhaseNotDyadic | RootExponentTooLarge

let group_exact ?(max_root_exponent = 32) ~(path_var_count : int)
    (paths : expanded_path list) :
    (exact_grouped_path list, exact_error) result =
  (* A phase is dyadic when its denominator is a power of two. The check is
     done before Common.Rational.find_k, which raises Failure otherwise. *)
  let phase_exponent (phase : Q.t) : (int, exact_error) result =
    let den = Q.den phase in
    if
      Z.gt den Z.zero
      && Z.(equal (logand den (den - one)) zero)
    then Ok (Common.Rational.find_k den)
    else Error PhaseNotDyadic
  in
  let rec collect_exponents acc = function
    | [] -> Ok (List.rev acc)
    | path :: rest -> (
        match phase_exponent path.phase with
        | Error error -> Error error
        | Ok k -> collect_exponents (k :: acc) rest)
  in
  match collect_exponents [] paths with
  | Error error -> Error error
  | Ok exponents ->
      let m = path_var_count in
      (* k = max(1, max k_phases, 3 when m is odd: the odd normalization
         needs sqrt(2) = zeta_8 + zeta_8^(-1)). *)
      let k =
        let k_phases = List.fold_left max 1 exponents in
        if m mod 2 = 1 then max k_phases 3 else k_phases
      in
      (* The user bound is a resource bound: it limits the size of the
         integers manipulated (exponents and coefficients), not the number
         of stored terms. It is checked before any allocation. *)
      if k > max_root_exponent then Error RootExponentTooLarge
      else
        (* m = 2r gives s = r; m = 2r+1 gives s = r+1, absorbing 1/sqrt(2).
           m / 2 + m mod 2 avoids the overflow of m + 1 at max_int. *)
        let s = m / 2 + (m mod 2) in
        (* Exponents are reduced modulo 2^(k-1): zeta^(j + 2^(k-1)) =
           -zeta^j. The reduction is applied on insertion, so each map only
           stores reduced exponents in [0, 2^(k-1)) with non-zero
           coefficients. *)
        let half = Z.pow (Z.of_int 2) (k - 1) in
        let size = Z.pow (Z.of_int 2) k in
        (* Adds [coeff] at exponent [j] (j in [0, 2^k)), reducing it modulo
           2^(k-1); removes the entry when the coefficient cancels. *)
        let add_term (coeffs : Z.t ExponentMap.t) (j : Z.t) (coeff : Z.t) :
            Z.t ExponentMap.t =
          let j, coeff =
            if Z.geq j half then (Z.sub j half, Z.neg coeff) else (j, coeff)
          in
          ExponentMap.update j
            (function
              | None -> Some coeff
              | Some old ->
                  let sum = Z.add old coeff in
                  if Z.equal sum Z.zero then None else Some sum)
            coeffs
        in
        (* Association list keyed by basis state, in first-appearance order
           as in [group]. Structural equality on bool arrays is the intended
           comparison for concrete basis states. Each state owns a private
           sparse map of reduced exponents to non-zero coefficients. *)
        let add_path (acc : (bool array * Z.t ExponentMap.t) list)
            (path : expanded_path) : (bool array * Z.t ExponentMap.t) list =
          let k_phase = Common.Rational.find_k (Q.den path.phase) in
          (* phase = num / 2^k_phase = (num * 2^(k - k_phase)) / 2^k *)
          let p =
            Z.mul (Q.num path.phase) (Z.shift_left Z.one (k - k_phase))
          in
          let j = Z.erem p size in
          let add_to (coeffs : Z.t ExponentMap.t) : Z.t ExponentMap.t =
            add_term coeffs j Z.one
          in
          let rec aux before = function
            | [] ->
                List.rev_append before
                  [ (path.basis_state, add_to ExponentMap.empty) ]
            | (state, coeffs) :: rest ->
                if state = path.basis_state then
                  List.rev_append before ((state, add_to coeffs) :: rest)
                else aux ((state, coeffs) :: before) rest
          in
          aux [] acc
        in
        let by_state = List.fold_left add_path [] paths in
        let grouped =
          List.map
            (fun (state, coeffs) ->
              (* For odd m, the 1/sqrt(2) factor is absorbed by multiplying
                 the sum by sqrt(2) = zeta_8 + zeta_8^(-1), with
                 zeta_8 = zeta^(2^(k-3)) (k >= 3). In reduced form,
                 zeta_8^(-1) = -zeta^(3*2^(k-3)). *)
              let coeffs =
                if m mod 2 = 1 then
                  let shift = Z.pow (Z.of_int 2) (k - 3) in
                  ExponentMap.fold
                    (fun j c acc ->
                      add_term
                        (add_term acc (Z.add j shift) c)
                        (Z.add j (Z.mul (Z.of_int 3) shift))
                        (Z.neg c))
                    coeffs ExponentMap.empty
                else coeffs
              in
              {
                basis_state = state;
                amplitude = { root_exponent = k; scale = s; coeffs };
              })
            by_state
        in
        Ok grouped

let exact_is_zero (amp : exact_amplitude) : bool =
  (* The sparse map stores no zero coefficient: it is empty iff the
     amplitude is zero. *)
  ExponentMap.is_empty amp.coeffs

let exact_equal (amp1 : exact_amplitude) (amp2 : exact_amplitude) : bool =
  (* Align the root exponents: zeta_{2^ki}^j = zeta_{2^k}^(j * 2^(k-ki)),
     so the map of the smaller field spreads by shifting its keys. The
     spread keys stay below 2^(k-1), hence already reduced modulo
     Phi_{2^k}. *)
  let k = max amp1.root_exponent amp2.root_exponent in
  let spread (amp : exact_amplitude) : Z.t ExponentMap.t =
    let d = k - amp.root_exponent in
    if d = 0 then amp.coeffs
    else
      ExponentMap.fold
        (fun j c acc -> ExponentMap.add (Z.shift_left j d) c acc)
        amp.coeffs ExponentMap.empty
  in
  (* Align the scales: 2^(-s1) C1 = 2^(-s2) C2 iff 2^(s-s1) C1 = 2^(s-s2)
     C2 with s = max(s1, s2). *)
  let s = max amp1.scale amp2.scale in
  let rescale (amp : exact_amplitude) (coeffs : Z.t ExponentMap.t) :
      Z.t ExponentMap.t =
    let d = s - amp.scale in
    if d = 0 then coeffs
    else ExponentMap.map (fun c -> Z.shift_left c d) coeffs
  in
  let c1 = rescale amp1 (spread amp1) in
  let c2 = rescale amp2 (spread amp2) in
  (* Compare the sparse maps: same reduced keys, same coefficients. *)
  ExponentMap.equal Z.equal c1 c2

(* Temporary stub: exact_mul is only needed for the GlobalPhase comparison
   (cross-multiplication), implemented after the FullCircuit level. *)
let exact_mul (amp1 : exact_amplitude) (amp2 : exact_amplitude) :
    exact_amplitude =
  ignore (amp1, amp2);
  failwith "Simulation.exact_mul: not implemented yet"
