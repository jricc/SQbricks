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

(** Experimental execution of unitary circuits on concrete basis inputs.

    Example: executing X on [| false |] returns the path sum for |1>. *)

type error =
  | ExecutionError of Program.execution_error
      (** The existing executor rejected the circuit or its input width. *)
  | ReductionError of Rules.reduction_error
      (** The existing reducer rejected a malformed path sum. *)
(** Errors propagated by {!execute}; execution and reduction remain distinct. *)

val execute : input:bool array -> Program.t -> (Path_sum.t, error) result
(** [execute ~input circuit] executes [circuit] on a computational-basis input
    and returns its reduced path sum, preserving normalization and global phase.

    [input.(i)] gives the value of qubit [i]: [false] means |0> and [true]
    means |1>. Its length is the register width, including unused wires.

    Execution errors, including a register too small for the circuit or a
    hybrid construct, return [ExecutionError]. Reduction errors return
    [ReductionError].

    Example: [execute ~input:[| false |] (Program.Macros.x 0)] returns a
    phase-zero path sum with ket [| Qubit.One |] and no path variables. *)

(** {1 Path Expansion} *)

type expanded_path = {
  basis_state : bool array;
      (** Concrete output: [basis_state.(i)] is [false] for |0> and [true] for
          |1>. *)
  phase : Q.t;
      (** Rational phase in units of 2π. The path contributes
          [e^(2πi·phase) / 2^(m/2)] to the amplitude of [basis_state], where
          [m] is the number of path variables in the expanded path sum. *)
}
(** One unfolded path: a concrete basis state and its rational phase. *)

type expand_error =
  | PhaseNotScalar
      (** After substitution, the phase still contains path variables or
          non-scalar terms. *)
  | KetNotConcrete
      (** After substitution, a ket qubit does not simplify to |0> or |1>. *)
(** Errors propagated by {!expand}. *)

val expand : Path_sum.t -> (expanded_path list, expand_error) result
(** [expand ps] enumerates all assignments of the path variables in [ps] and
    returns one entry per path with its concrete basis state and rational phase.

    The amplitude of each path is [e^(2πi·phase) / 2^(m/2)] where [m] is the
    number of path variables ([List.length ps.path_var]). Paths leading to the
    same basis state must be grouped before computing probabilities.

    Example: expanding the reduced path sum of H on |0> gives two paths, |0>
    and |1>, both with phase 0. *)

(** {1 Grouping by Basis State} *)

type grouped_path = {
  basis_state : bool array;
      (** Concrete output state shared by all the grouped paths. *)
  amplitude : Complex.t;
      (** Sum of the amplitudes of the paths leading to [basis_state]. Each
          path contributes [e^(2πi·phase) / 2^(m/2)], so paths with opposite
          phases cancel (destructive interference) and equal phases reinforce
          (constructive interference). The probability of [basis_state] is
          [Complex.norm2 amplitude], the squared modulus of the amplitude. *)
}
(** One basis state with the summed amplitude of the paths leading to it. *)

val group : path_var_count:int -> expanded_path list -> grouped_path list
(** [group ~path_var_count paths] sums the amplitudes of the expanded paths
    leading to the same basis state, returning one entry per basis state.

    [path_var_count] is the number of path variables of the expanded path
    sum ([List.length ps.path_var]); it fixes the per-path normalization
    [1 / 2^(path_var_count/2)].

    Example: grouping the expansion of H on |0> gives two entries, |0> and
    |1>, both with amplitude [1/sqrt(2)]. *)

(** An exact amplitude, without conversion to floating-point numbers.
    Example: the amplitude 1 is represented exactly. *)
type exact_amplitude

val exact_to_string : exact_amplitude -> string
(** Returns the exact representation for debugging and tests.
    Example: 1 is represented as [k=1; s=0; coeffs=[0:1]].
    No floating-point conversion is performed. *)

(** A basis state and the exact sum of its contributions.
    Example: two paths leading to |0> produce a single entry. *)
type exact_grouped_path = {
  basis_state : bool array;
      (** Basis state; [false] represents |0>, [true] represents |1>. *)
  amplitude : exact_amplitude;
      (** Exact sum of the amplitudes leading to this state. *)
}

(** An exact grouping error.
    Error cases will be specified with their dedicated tests. *)
type exact_error

val group_exact :
  path_var_count:int ->
  expanded_path list ->
  (exact_grouped_path list, exact_error) result
(** [group_exact ~path_var_count paths] groups paths by basis state,
    summing their amplitudes exactly.

    [path_var_count] is the number of path variables in the expanded
    path sum; it fixes the common normalization [2^(-path_var_count/2)].

    Currently supports no paths, or one path with phase 0, 1/2 or 1/4 and
    [path_var_count = 0]. Other cases raise [Failure] until implemented.

    Example: [group_exact ~path_var_count:0 []] returns [Ok []]. *)
