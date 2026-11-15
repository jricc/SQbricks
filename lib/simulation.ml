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

(* Evaluates a qubit expression on a boolean assignment: [Var v] looks up [v],
   [Prod] is AND, [SumMod2] is XOR. Returns [None] when a variable is missing
   from the assignment, mirroring the [KetNotConcrete] error of {!expand}.
   For example, eval_qubit [(0, true)] (SumMod2 (One, Var 0)) = Some false. *)
let rec eval_qubit (assignment : (int * bool) list) (q : Qubit.t) :
    bool option =
  match q with
  | Qubit.Zero -> Some false
  | Qubit.One -> Some true
  | Qubit.Var v -> List.assoc_opt v assignment
  | Qubit.Prod (a, b) -> (
      match (eval_qubit assignment a, eval_qubit assignment b) with
      | Some x, Some y -> Some (x && y)
      | _ -> None)
  | Qubit.SumMod2 (a, b) -> (
      match (eval_qubit assignment a, eval_qubit assignment b) with
      | Some x, Some y -> Some (x <> y)
      | _ -> None)

(* Evaluates a phase monome to a rational on an assignment: scalars are
   constants, qubit monomes become 0 or 1, products multiply. [None] mirrors
   the [PhaseNotScalar] error of {!expand}. *)
let rec eval_monome (assignment : (int * bool) list) (m : Poly.Monome.t) :
    Q.t option =
  match m with
  | Poly.Monome.Scal q -> Some q
  | Poly.Monome.Qubit q -> (
      match eval_qubit assignment q with
      | Some true -> Some Q.one
      | Some false -> Some Q.zero
      | None -> None)
  | Poly.Monome.Prod (a, b) -> (
      match (eval_monome assignment a, eval_monome assignment b) with
      | Some x, Some y -> Some (Q.mul x y)
      | _ -> None)

(* Sums the evaluated monomes of a phase polynomial on an assignment. *)
let eval_phase (assignment : (int * bool) list) (p : Poly.t) : Q.t option =
  let rec aux p acc =
    if Poly.is_empty p then Some acc
    else
      let m = Poly.find p in
      let p' = Poly.del p in
      match eval_monome assignment m with
      | Some q -> aux p' (Q.add acc q)
      | None -> None
  in
  aux p Q.zero

(** Experimental variant of {!expand}: evaluates the phase and each ket
    qubit directly on every boolean assignment, instead of rebuilding and
    simplifying substituted expressions. Produces the same paths with the
    same errors ([PhaseNotScalar] before [KetNotConcrete], per path, in
    assignment order); kept as a faster expansion candidate, benchmarked
    against {!expand}. *)
let expand_direct (ps : Path_sum.t) : (expanded_path list, expand_error) result
    =
  let expand_one (assignment : (int * bool) list) :
      (expanded_path, expand_error) result =
    match eval_phase assignment ps.phase with
    | None -> Error PhaseNotScalar
    | Some phase ->
        (* [Poly.simplify] drops integer scalars and normalizes negative ones
           (remove_neg_scal), so [expand] returns phases in [0,1); normalize
           the same way here. For example, 1 becomes 0. *)
        let phase =
          Q.make (Z.erem (Q.num phase) (Q.den phase)) (Q.den phase)
        in
        let n = Array.length ps.ket in
        let basis_state = Array.make n false in
        let rec fill i =
          if i >= n then Some basis_state
          else
            match eval_qubit assignment ps.ket.(i) with
            | None -> None
            | Some b ->
                basis_state.(i) <- b;
                fill (i + 1)
        in
        match fill 0 with
        | None -> Error KetNotConcrete
        | Some basis_state -> Ok { basis_state; phase }
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

(* Converts an exact amplitude to a floating-point complex number, for
   numeric cross-checks and debugging only; the exact computation itself
   never uses this. For example, [k=1; s=0; coeffs=[0:1]] gives [1 + 0i]. *)
let exact_to_complex (amplitude : exact_amplitude) : Complex.t =
  (* root = exp(2*pi*i / 2^k); term j is c_j * root^j, evaluated by angle. *)
  let step =
    2. *. Float.pi /. Float.pow 2.0 (Float.of_int amplitude.root_exponent)
  in
  let sum =
    ExponentMap.fold
      (fun exponent coefficient acc ->
        let angle = Z.to_float exponent *. step in
        let c = Z.to_float coefficient in
        Complex.add acc
          { Complex.re = c *. Float.cos angle; Complex.im = c *. Float.sin angle })
      amplitude.coeffs Complex.zero
  in
  let scale = Float.pow 2.0 (Float.neg (Float.of_int amplitude.scale)) in
  let { Complex.re = re; Complex.im = im } = sum in
  { Complex.re = scale *. re; Complex.im = scale *. im }

(** A basis state and its exact summed amplitude.
    For example, one path leading to |0> produces a single entry. *)
type exact_grouped_path = {
  basis_state : bool array;
      (** Concrete output state shared by the grouped paths. *)
  amplitude : exact_amplitude;
      (** Exact sum of the amplitudes leading to this state. *)
}

(** Input errors for complete exact grouping, checked before any computation.
    For example, zero paths at m=0 give [Invalid_path_count]. *)
type exact_error =
  | Negative_path_var_count of int
      (** The supplied number of path variables is negative. *)
  | Invalid_path_count of {
      path_var_count : int;
      actual_count : int;
    }
      (** Expected [2^path_var_count] paths; [actual_count] is the list length. *)
  | Inconsistent_state_width of {
      path_index : int;
      expected_width : int;
      actual_width : int;
    }
      (** A state's width differs from the first state's width. *)
  | Non_finite_phase of { path_index : int }
      (** The phase is infinite or undefined. *)
  | Non_dyadic_phase of { path_index : int; phase : Q.t }
      (** The finite phase cannot be written with a power-of-two denominator. *)

(* A finite rational always has a strictly positive denominator; Q.inf,
   Q.minus_inf and Q.undef are the only rationals whose denominator is 0.
   For example, Q.den (1/3) = 3 and Q.den Q.inf = 0. *)
let is_finite_phase (phase : Q.t) : bool = Z.sign (Q.den phase) > 0

(* A finite phase is dyadic when the denominator of its reduced form is a
   power of two. For example, 1/8 is dyadic but 1/3 is not. *)
let is_dyadic_phase (phase : Q.t) : bool =
  let den = Q.den phase in
  Z.sign den > 0 && Z.(logand den (den - one)) = Z.zero

(* A positive integer is a power of two iff [n land (n-1) = 0].
   For example, 4 is a power of two but 0 and 3 are not. *)
let is_power_of_two (n : int) : bool = n > 0 && (n land (n - 1)) = 0

(* Base-2 logarithm of a positive power of two, counted by shifts.
   For example, log2_of_power_of_two 8 = 3. *)
let log2_of_power_of_two (n : int) : int =
  let rec aux n acc = if n = 1 then acc else aux (n lsr 1) (acc + 1) in
  aux n 0

(* Non-negative remainder of [a] modulo [b > 0].
   For example, pos_rem (-1) 4 = 3. *)
let pos_rem (a : Z.t) (b : Z.t) : Z.t =
  let r = Z.rem a b in
  if Z.sign r < 0 then Z.add r b else r

(* Checks the accepted input contract in order: a nonnegative path variable
   count, then exactly [2^m] paths (tested through log2 of the list length,
   so a huge [m] never allocates [2^m]), then per path in list order the
   state width against the first state, phase finiteness and phase
   dyadicity. Returns the first error encountered, if any.
   For example, one path of phase 1/3 at m=0 gives [Non_dyadic_phase] at
   index 0, before any later path is inspected. *)
let validate_inputs ~(path_var_count : int) (paths : expanded_path list) :
    exact_error option =
  if path_var_count < 0 then Some (Negative_path_var_count path_var_count)
  else
    let actual_count = List.length paths in
    if
      (not (is_power_of_two actual_count))
      || log2_of_power_of_two actual_count <> path_var_count
    then Some (Invalid_path_count { path_var_count; actual_count })
    else
      match paths with
      | [] -> None (* unreachable: an empty list fails the count check *)
      | first :: _ ->
          let expected_width = Array.length first.basis_state in
          (* Annotated: [basis_state] also exists on other record types, so an
             unannotated pattern would resolve to the wrong one. *)
          let rec aux (path_index : int) (remaining : expanded_path list) :
              exact_error option =
            match remaining with
            | [] -> None
            | path :: rest ->
                let actual_width = Array.length path.basis_state in
                if actual_width <> expected_width then
                  Some
                    (Inconsistent_state_width
                       { path_index; expected_width; actual_width })
                else if not (is_finite_phase path.phase) then
                  Some (Non_finite_phase { path_index })
                else if not (is_dyadic_phase path.phase) then
                  Some (Non_dyadic_phase { path_index; phase = path.phase })
                else aux (path_index + 1) rest
          in
          aux 0 paths

(* Basis-state map; [compare] on bool arrays is lexicographic with
   [false < true], which is also the required output order. *)
module StateMap = Map.Make (struct
  type t = bool array

  let compare = compare
end)

(* Smallest root exponent representing a dyadic phase: the reduced
   denominator is [2^k_phase]. For example, phase_root_exponent (1/8) = 3 and
   phase_root_exponent 1 = 0. *)
let phase_root_exponent (phase : Q.t) : int =
  let den = Q.den phase in
  if Z.equal den Z.one then 0 else Z.log2 den

(* Adds [c * root^j] to a coefficient map, using [root^(2^(k-1)) = -1] to
   reduce [j >= 2^(k-1)]; one step suffices because [j < 2^k]. Zero
   coefficients are removed. For example, at k=2, adding root^3 gives
   exponent 1 with coefficient -1. *)
let add_term ~half (coeffs : Z.t ExponentMap.t) (j : Z.t) (c : Z.t) :
    Z.t ExponentMap.t =
  let j, c =
    if Z.compare j half >= 0 then (Z.sub j half, Z.neg c) else (j, c)
  in
  let updated =
    match ExponentMap.find_opt j coeffs with
    | None -> c
    | Some previous -> Z.add previous c
  in
  if Z.equal updated Z.zero then ExponentMap.remove j coeffs
  else ExponentMap.add j updated coeffs

(** Checks the input contract, then groups a complete expansion exactly.
    For example, one path to |0> with phase 0 and path count 0 has amplitude
    [k=1; s=0; coeffs=[0:1]], and the two phase-zero paths of H on |0> give
    |0> then |1>, each with [k=3; s=1; coeffs=[1:1; 3:-1]]. *)
let group_exact ~(path_var_count : int) (paths : expanded_path list) :
    (exact_grouped_path list, exact_error) result =
  match validate_inputs ~path_var_count paths with
  | Some error -> Error error
  | None ->
      (* Common coordinates: the smallest k >= 1 representing every phase,
         raised to 3 when m is odd so the sqrt(2) factor fits; s = ceil(m/2)
         absorbs the 2^(-m/2) normalization without further simplification. *)
      let k =
        List.fold_left
          (fun k (path : expanded_path) ->
            max k (phase_root_exponent path.phase))
          1 paths
      in
      let k = if path_var_count mod 2 = 1 then max k 3 else k in
      let scale = path_var_count / 2 + (path_var_count mod 2) in
      let half = Z.pow (Z.of_int 2) (k - 1) in
      (* Root exponent of one path in [0, 2^k): r = num mod den in [0, den)
         is shifted by k - k_phase(p); r < 2^k_phase keeps j < 2^k. *)
      let path_exponent (path : expanded_path) : Z.t =
        let den = Q.den path.phase in
        let r = pos_rem (Q.num path.phase) den in
        Z.mul r (Z.pow (Z.of_int 2) (k - phase_root_exponent path.phase))
      in
      (* Sum the reduced terms of all paths leading to the same state. *)
      let grouped =
        List.fold_left
          (fun acc (path : expanded_path) ->
            let terms =
              match StateMap.find_opt path.basis_state acc with
              | None -> ExponentMap.empty
              | Some terms -> terms
            in
            StateMap.add path.basis_state
              (add_term ~half terms (path_exponent path) Z.one)
              acc)
          StateMap.empty paths
      in
      (* For odd m, 2^(-m/2) = 2^(-s) * sqrt(2) with
         sqrt(2) = root^(2^(k-3)) - root^(3*2^(k-3)); fold it into each sum.
         New exponents stay below 2^k because stored j < 2^(k-1). *)
      let grouped =
        if path_var_count mod 2 = 1 then
          let eighth = Z.pow (Z.of_int 2) (k - 3) in
          StateMap.map
            (fun terms ->
              ExponentMap.fold
                (fun j c acc ->
                  add_term ~half
                    (add_term ~half acc (Z.add j eighth) c)
                    (Z.add j (Z.mul (Z.of_int 3) eighth))
                    (Z.neg c))
                terms ExponentMap.empty)
            grouped
        else grouped
      in
      (* Drop zero-amplitude states; bindings are already sorted. *)
      let result =
        List.filter_map
          (fun (basis_state, coeffs) ->
            if ExponentMap.is_empty coeffs then None
            else
              Some
                {
                  basis_state;
                  amplitude = { root_exponent = k; scale; coeffs };
                })
          (StateMap.bindings grouped)
      in
      Ok result
