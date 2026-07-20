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

(** This module provides types and functions to represent and manipulate path
    sums, which are symbolic forms of quantum states used during circuit
    verification.

    A path sum is defined by:
    - A phase polynomial ({!Poly}),
    - A quantum state ({!Ket}),
    - A set of path variables.

    {b References}:
    - Chareton et al. (2021):
      {i "An Automated Deductive Verification Framework for Circuit-building
         Quantum Programs"}, In {i Programming Languages and Systems}, Springer.
      [DOI](http://dx.doi.org/10.1007/978-3-030-72019-3_6) (ISBN:
      978-3-030-72019-3).

    - Amy (2019):
      {i "Towards Large-scale Functional Verification of Universal Quantum
         Circuits"}, {i Electronic Proceedings in Theoretical Computer Science},
      287:1-21. [DOI](http://dx.doi.org/10.4204/EPTCS.287.1) (ISSN: 2075-2180).
*)

open Common

(** {1 Ket} *)

module Ket : sig
  (** {2 Types} *)

  type t = Qubit.t array
  (** Type of [Ket], represented as arrays of qubits ({!Qubit}). *)

  (** {2 Basic Operations} *)

  val copy : t -> t
  (** [copy ket] creates a fresh copy of [ket] (see
      {{:https://ocaml.org/manual/5.4/api/Array.html#VALcopy} Array.copy}). *)

  type equality_error = DifferentOutputLengths | InvalidOutputIndex
  (** Errors that can prevent a ket comparison from being interpreted as a plain
      equality result.

      - [DifferentOutputLengths] means [outputs1] and [outputs2] do not select
        the same number of qubits.
      - [InvalidOutputIndex] means one selected output index is outside its
        ket. *)

  val equal_result :
    ?debug:bool ->
    ?outputs1:int list ->
    ?outputs2:int list ->
    t ->
    t ->
    (bool * int IntMap.t * int IntMap.t, equality_error) result
  (** [equal_result ?debug ?outputs1 ?outputs2 k1 k2] is the typed version of
      {!equal}. It returns [Ok (eq, map1, map2)] when the comparison is well
      formed. [map1] is the path-variable mapping from [k1] to [k2], and [map2]
      is its inverse. It returns [Error DifferentOutputLengths] when the output
      selections have different lengths, and [Error InvalidOutputIndex] when an
      output selection is out of bounds. *)

  val equal :
    ?debug:bool ->
    ?outputs1:int list ->
    ?outputs2:int list ->
    t ->
    t ->
    bool * int IntMap.t * int IntMap.t
  (** [equal ?debug ?outputs1 ?outputs2 k1 k2] compares two kets [k1] and [k2]
      (arrays of qubits) for structural and logical equivalence, possibly up to
      a renaming of their internal path variables.

      The comparison is performed qubit by qubit:
      - If [outputs1] and [outputs2] are provided, only the qubits at those
        indices are compared.
      - Otherwise, all qubits are compared in order.

      The function returns a triple [(eq, map1, map2)] where:
      - [eq] is [true] if [k1] and [k2] are equivalent modulo a consistent
        renaming of path variables;
      - [map1] is a mapping of path variables from [k1] to [k2];
      - [map2] is the inverse mapping (from [k2] to [k1]).

      These mappings are constructed incrementally during comparison: whenever a
      new pair of path variables is matched, it is added to both maps to ensure
      consistent correspondence.

      For example:
      {[
        let k1 = [| SumMod2 (Var 0, Var 2); SumMod2 (Var 1, Var 3) |]
        and k2 = [| SumMod2 (Var 0, Var 4); SumMod2 (Var 1, Var 2) |] in
        Ket.equal k1 k2;;
        - : bool * int IntMap.t * int IntMap.t =
          (true, {2 -> 4; 3 -> 2}, {2 -> 3; 4 -> 2})
      ]}

      If the number of qubits or output indices differ,
      [(false, IntMap.empty, IntMap.empty)] is returned. Use {!equal_result}
      when the caller needs to distinguish inequality from malformed comparison
      parameters. *)

  val member : ?except:int -> int -> t -> bool
  (** [member ?except var state] checks if variable [var] is present in the
      quantum state, optionally excluding one qubit.

      Example(s):
      - [member 1 [|Var 1; Var 2|]] returns [true]
      - [member ~except:1 1 [|Var 1; Var 2|]] returns [false] *)

  val simplify : t -> t
  (** [simplify state] simplifies qubit expressions within the state.

      Example(s):
      - [simplify [|Prod(One, Var 1)|]] returns [[|Var 1|]] *)

  (** {2 Variable Extraction} *)

  val extract_path_var : ?debug:bool -> ?outputs:int list -> t -> int list
  (** [extract_path_var ?debug ?outputs state] extracts path variables from the
      quantum state, optionally limited to specific qubit indices.

      Example(s):
      - [extract_path_var [|Var 3|]] returns [[3]] *)

  val extract_var : t -> int list -> int list
  (** [extract_var ket indices] extracts variables from specific qubits.

      Example(s):
      - [extract_var [|Var 1; Var 2|] [0;1]] returns [[1; 2]]
      - [extract_var [|Var 1; Var 2|] [0]] returns [[1]] *)

  type path_var_order_error = InvalidPathVariableCount | InvalidPathVariableIndex
  (** Errors that can prevent path-variable ordering.

      - [InvalidPathVariableCount] means the declared number of path variables
        is negative.
      - [InvalidPathVariableIndex] means a path variable found in the ket is
        outside the declared range. *)

  val path_var_order_result :
    ?debug:bool ->
    t ->
    int ->
    (int array * int array, path_var_order_error) result
  (** [path_var_order_result ?debug ket count] is the typed version of
      {!path_var_order}. It computes the ordering arrays for a renamed ket, or
      reports malformed path-variable metadata. *)

  (** Need to have an input "Renamed" ([Rules.Rename.single]) *)
  val path_var_order : ?debug:bool -> t -> int -> int array * int array
  (** Compute the ordering of path variables in a given ket. Use
      {!path_var_order_result} when the caller needs to distinguish malformed
      path-variable metadata from a valid ordering. *)

  val list_of_qubits_to_ket : Qubit.t list -> t
  (** [list_of_qubits_to_ket qubits] converts a list of qubits into a quantum
      state (ket).

      Example(s):
      - [list_of_qubits_to_ket [Var 1; Var 2]] returns [[|Var 1; Var 2|]] *)

  val number_of_sum : t -> int
  (** [number_of_sum state] counts the number of [SumMod2] constructs in the
      ket.

      Example(s):
      - [number_of_sum [|SumMod2(Var 1, Var 2)|]] returns [1] *)

  (** {2 String Conversion} *)

  module String : sig
    val pretty : t -> string
    (** [pretty state] converts a ket to a human-readable string.

        Example(s):
        - [pretty [|Var 1; Var 2|]] returns ["|x1,x2>"] *)

    val exact : t -> string
    (** [exact state] converts a ket to its exact constructor form.

        Example(s):
        - [exact [|Var 1; Var 2|]] returns ["[|Var 1; Var 2|]"] *)
  end

  (** {2 Substitution} *)

  val substitute : ?debug:bool -> t -> int -> Qubit.t -> t
  (** [substitute ?debug state var expr] substitutes occurrences of variable
      [var] in the ket [state] with qubit expression [expr], without mutating
      [state].

      Example(s):
      - [substitute [|Var 1|] 1 (Var 2)] returns [[|Var 2|]] *)

  val substitute_many : ?debug:bool -> t -> (int * Qubit.t) list -> t
  (** [substitute_many ?debug state substitutions] applies all variable
      substitutions in one traversal of [state], without mutating [state].
      Replacement expressions are not substituted again by the same call.

      Example(s):
      - [substitute_many [|Var 1; Var 2|] [(1, Var 3); (2, One)]] returns
        [[|Var 3; One|]] *)
end

(** {1 Path Sum Representation} *)

type t = { phase : Poly.t; ket : Ket.t; path_var : int list }
(** Type representing a path sum. *)

val copy : t -> t
(** [copy ps] returns a deep copy of the path sum. *)

(** {2 String Conversion} *)

module String : sig
  val exact : t -> string
  (** [exact ps] converts a path sum to its exact constructor form.

      Example(s):
      - [exact {phase = Poly.zero; ket = [|Var 1|]; path_var = []}] returns
        ["phase = ; ket = [|Var 1|]; path_var = ;"] *)

  val pretty : t -> string
  (** [pretty ps] converts a path sum into a human-readable form.

      Example(s):
      - [pretty {phase = Poly.zero; ket = [|Var 1|]; path_var = []}] returns
        ["phase = e^{2πi·0};\nket = |x1>;\npath_var = ;"] *)

  val path_var : int list -> int -> string
  (** [path_var vars offset] converts a list of path variables to a string.

      Example(s):
      - [path_var [1; 2] 0] returns ["1;2"] *)
end

(** {1 Comparison and Equality} *)

type equality_error =
  | DifferentOutputLengths
  | InvalidOutputIndex
  | IncompatiblePhaseWidths
  | IncompletePhasePathVariableMap
(** Errors that can prevent a path-sum comparison from being interpreted as a
    plain equality result.

    - [DifferentOutputLengths] means [outputs1] and [outputs2] do not select
      the same number of output qubits.
    - [InvalidOutputIndex] means one selected output index is outside its path
      sum.
    - [IncompatiblePhaseWidths] means the phase comparison was given
      incompatible ket widths.
    - [IncompletePhasePathVariableMap] means that the ket comparison constrains
      one variable from a phase pair but does not provide its corresponding
      entry on the other side. *)

val equal_result :
  ?debug:bool ->
  ?outputs1:int list ->
  ?outputs2:int list ->
  ?global_phase:bool ->
  t ->
  t ->
  (bool, equality_error) result
(** [equal_result ?debug ?outputs1 ?outputs2 ?global_phase ps1 ps2] is the
    typed version of {!equal}. It returns [Ok true] or [Ok false] when the
    comparison is well formed, and [Error DifferentOutputLengths] when the
    output selections have different lengths, or [Error InvalidOutputIndex]
    when an output selection is out of bounds. Phase comparison metadata errors
    are reported explicitly instead of being collapsed to [Ok false]. *)

val equal :
  ?debug:bool ->
  ?outputs1:int list ->
  ?outputs2:int list ->
  ?global_phase:bool ->
  t ->
  t ->
  bool
(** [equal ?debug ?outputs1 ?outputs2 ?global_phase ps1 ps2] checks whether two
    path sums [ps1] and [ps2] are equivalent up to qubits mapping, optionally
    ignoring global phase and restricting comparison to output qubits. Use
    {!equal_result} when the caller needs to distinguish inequality from
    malformed comparison parameters. *)

(** {1 Construction and Initialization} *)

val ofSize : int -> t
(** [ofSize width] creates a path sum with given width, where each qubit is
    initialized as a variable.

    Example(s):
    - [ofSize 2] returns a path sum with qubits [[|Var 0; Var 1|]]. *)

type initialization_error = InvalidWidth | InvalidInitIndex
(** Errors that can prevent initial path-sum construction.

    - [InvalidWidth] means the requested width is negative.
    - [InvalidInitIndex] means one initialized qubit index is outside
      [0, width). *)

val ofSize_init_result :
  ?debug:bool -> int -> int list -> (t, initialization_error) result
(** [ofSize_init_result ?debug width init_values] is the typed version of
    {!ofSize_init}. It returns [Error InvalidWidth] for a negative width and
    [Error InvalidInitIndex] when an initialization index is out of bounds. *)

val ofSize_init : ?debug:bool -> int -> int list -> t
(** [ofSize_init ?debug width init_values] creates an initial path sum with
    given width and initialization values.

    Example(s):
    - [ofSize_init 2 [0]] initializes the first qubit to 0 and the second as a
      variable. *)

val remove_path_var : t -> int -> t
(** [remove_path_var ps var] removes the path variable [var] from the path sum.
*)

type substitution_error = CannotSubstitutePathVariable
(** Errors that can prevent path-sum substitution.

    [CannotSubstitutePathVariable] means the target variable is declared in
    [ps.path_var]. *)

val substitute_result :
  ?debug:bool ->
  ?except_path_var:bool ->
  t ->
  int ->
  Qubit.t ->
  (t, substitution_error) result
(** [substitute_result ?debug ?except_path_var ps var expr] is the typed version
    of {!substitute}. It returns [Error CannotSubstitutePathVariable] when
    [var] is declared in [ps.path_var]. If [except_path_var] is [true], such a
    variable is protected and [ps] is returned unchanged. *)

val substitute :
  ?debug:bool -> ?except_path_var:bool -> t -> int -> Qubit.t -> t
(** [substitute ?debug ?except_path_var ps var expr] substitutes occurrences of
    variable [var] in the path sum [ps] with qubit expression [expr], without
    mutating [ps]. Path variables are protected: if [except_path_var] is [true],
    substituting one returns [ps] unchanged; otherwise it is rejected. *)

(** {1 Path Sum Library} *)

module Path_sum_library : sig
  (** Quantum gate constructors as path sums.

      The rotation coefficient [s] is an integer. Consequently, a negative
      exponent [k] makes [u1], [rz], [rx], and [ry] exact identities. These
      constructors return the unchanged target without path variables in that
      case. [u1] is also the identity for [k = 0]. This is distinct from a
      negative coefficient [s], which represents a valid opposite angle.

      A successful constructor returns a ket with exactly [width] components.
      Unselected wires keep their corresponding input variable. *)

  type gate_error = TargetIndexOutOfWidth | OverlappingGateWires
  (** Errors that can prevent a gate path sum from being constructed.

      [TargetIndexOutOfWidth] means the requested target index is not inside
      the declared circuit width.

      [OverlappingGateWires] means that a controlled gate uses the same wire
      for two roles, such as both control and target. *)

  val h : int -> int -> t
  (** [h target width] creates a Hadamard gate:
      {b (1/√2) Σ_y e^(2πi x·y / 2) |y⟩}.

      Example(s):
      - [h 0 1] creates a Hadamard gate on qubit 0 with width 1. *)

  val h_result : int -> int -> (t, gate_error) result
  (** [h_result target width] is the typed version of {!h}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val x : int -> int -> t
  (** [x target width] creates a Pauli-X (bit-flip) gate.

      Example(s):
      - [x 0 1] creates an X gate on qubit 0 with width 1. *)

  val x_result : int -> int -> (t, gate_error) result
  (** [x_result target width] is the typed version of {!x}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val u1 : ?s:int -> int -> int -> int -> t
  (** [u1 ?s k target width] creates a phase gate: {b e^(2πi s·x / 2^k) |x⟩}.

      Example(s):
      - [u1 1 0 1] creates a U1 gate with s=1, k=1 on qubit 0. *)

  val u1_result : ?s:int -> int -> int -> int -> (t, gate_error) result
  (** [u1_result ?s k target width] is the typed version of {!u1}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val z : int -> int -> t
  (** [z target width] creates a Pauli-Z gate.

      Example(s):
      - [z 0 1] creates a Z gate on qubit 0 with width 1. *)

  val z_result : int -> int -> (t, gate_error) result
  (** [z_result target width] is the typed version of {!z}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val s : int -> int -> t
  (** [s target width] creates an S gate (π/2 phase gate).

      Example(s):
      - [s 0 1] creates an S gate on qubit 0. *)

  val s_result : int -> int -> (t, gate_error) result
  (** [s_result target width] is the typed version of {!s}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val t : int -> int -> t
  (** [t target width] creates a T gate (π/4 phase gate).

      Example(s):
      - [t 0 1] creates a T gate on qubit 0. *)

  val t_result : int -> int -> (t, gate_error) result
  (** [t_result target width] is the typed version of {!t}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val zinv : int -> int -> t
  (** [zinv target width] creates an inverse Z gate. *)

  val zinv_result : int -> int -> (t, gate_error) result
  (** [zinv_result target width] is the typed version of {!zinv}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val sinv : int -> int -> t
  (** [sinv target width] creates an inverse S gate. *)

  val sinv_result : int -> int -> (t, gate_error) result
  (** [sinv_result target width] is the typed version of {!sinv}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val tinv : int -> int -> t
  (** [tinv target width] creates an inverse T gate. *)

  val tinv_result : int -> int -> (t, gate_error) result
  (** [tinv_result target width] is the typed version of {!tinv}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val rz : ?s:int -> int -> int -> int -> t
  (** [rz ?s k target width] creates a Z-rotation gate:
      {b e^(2πi (s·x / 2^k - s / 2^(k+1))) |x⟩}. *)

  val rz_result : ?s:int -> int -> int -> int -> (t, gate_error) result
  (** [rz_result ?s k target width] is the typed version of {!rz}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val rx : ?s:int -> int -> int -> int -> t
  (** [rx ?s k target width] creates an X-rotation gate. *)

  val rx_result : ?s:int -> int -> int -> int -> (t, gate_error) result
  (** [rx_result ?s k target width] is the typed version of {!rx}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val ry : ?s:int -> int -> int -> int -> t
  (** [ry ?s k target width] creates a Y-rotation gate. *)

  val ry_result : ?s:int -> int -> int -> int -> (t, gate_error) result
  (** [ry_result ?s k target width] is the typed version of {!ry}. It returns
      [Error TargetIndexOutOfWidth] when [target] is outside [width]. *)

  val ch : int -> int -> int -> t
  (** [ch control target width] creates a controlled-Hadamard gate. *)

  val ch_result : int -> int -> int -> (t, gate_error) result
  (** [ch_result control target width] is the typed version of {!ch}. It
      returns [Error TargetIndexOutOfWidth] when [control] or [target] is
      outside [width], and [Error OverlappingGateWires] when they are equal. *)

  val cx : int -> int -> int -> t
  (** [cx control target width] creates a CNOT gate. *)

  val cx_result : int -> int -> int -> (t, gate_error) result
  (** [cx_result control target width] is the typed version of {!cx}. It
      returns [Error TargetIndexOutOfWidth] when [control] or [target] is
      outside [width], and [Error OverlappingGateWires] when they are equal. *)

  val crz : int -> int -> int -> int -> t
  (** [crz k control target width] creates a controlled-RZ gate. *)

  val crz_result : int -> int -> int -> int -> (t, gate_error) result
  (** [crz_result k control target width] is the typed version of {!crz}. It
      returns [Error TargetIndexOutOfWidth] when [control] or [target] is
      outside [width], and [Error OverlappingGateWires] when they are equal. *)

  val cz : int -> int -> int -> t
  (** [cz control target width] creates a controlled-Z gate. *)

  val cz_result : int -> int -> int -> (t, gate_error) result
  (** [cz_result control target width] is the typed version of {!cz}. It
      returns [Error TargetIndexOutOfWidth] when [control] or [target] is
      outside [width], and [Error OverlappingGateWires] when they are equal. *)

  val cs : int -> int -> int -> t
  (** [cs control target width] creates a controlled-S gate. *)

  val cs_result : int -> int -> int -> (t, gate_error) result
  (** [cs_result control target width] is the typed version of {!cs}. It
      returns [Error TargetIndexOutOfWidth] when [control] or [target] is
      outside [width], and [Error OverlappingGateWires] when they are equal. *)

  val ct : int -> int -> int -> t
  (** [ct control target width] creates a controlled-T gate. *)

  val ct_result : int -> int -> int -> (t, gate_error) result
  (** [ct_result control target width] is the typed version of {!ct}. It
      returns [Error TargetIndexOutOfWidth] when [control] or [target] is
      outside [width], and [Error OverlappingGateWires] when they are equal. *)

  val ccx : int -> int -> int -> int -> t
  (** [ccx control1 control2 target width] creates a Toffoli (CCX) gate. *)

  val ccx_result : int -> int -> int -> int -> (t, gate_error) result
  (** [ccx_result control1 control2 target width] is the typed version of
      {!ccx}. It returns [Error TargetIndexOutOfWidth] when one selected index
      is outside [width], and [Error OverlappingGateWires] when two selected
      indices are equal. *)

  val ccz : int -> int -> int -> int -> t
  (** [ccz control1 control2 target width] creates a double-controlled Z gate.
  *)

  val ccz_result : int -> int -> int -> int -> (t, gate_error) result
  (** [ccz_result control1 control2 target width] is the typed version of
      {!ccz}. It returns [Error TargetIndexOutOfWidth] when one selected index
      is outside [width], and [Error OverlappingGateWires] when two selected
      indices are equal. *)

  val sh3 : t
  (** [sh3] predefined state for testing and demonstration purposes. *)
end
