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

(** {1 Exact Grouping by Basis State} *)

type exact_amplitude
(** Exact amplitude [2^(-s) · Σ_{j < 2^(k-1)} c_j ζ^j] with
    [ζ = e^(2πi / 2^k)], [c_j] signed integers, in reduced form modulo the
    cyclotomic polynomial [Φ_{2^k}(x) = x^(2^(k-1)) + 1] (coefficient vector
    of length [2^(k-1)]).

    The type is abstract: values are built by {!group_exact}, which
    guarantees the invariants [k ≥ 1], [s ≥ 0] and the reduced form, so
    {!exact_is_zero}, {!exact_equal} and {!exact_mul} can rely on them.
    The root exponent is [k = max(1, max k_phases, 3 if m is odd)], where
    [k_phases] are the exponents of the path-phase denominators and [m] is
    the path-variable count: the odd normalization [2^(-m/2) = 2^(-(r+1))·√2]
    with [√2 = ζ_8 + ζ_8^(-1)] requires [k ≥ 3], and [k ≥ 1] represents [-1];
    the phase denominators are never masked by the [k ≥ 1] floor. *)

type exact_grouped_path = {
  basis_state : bool array;
      (** Concrete output state shared by all the grouped paths. *)
  amplitude : exact_amplitude;
      (** Exact sum of the amplitudes of the paths leading to
          [basis_state]. *)
}
(** One basis state with the exact summed amplitude of the paths leading to
    it. Unlike {!grouped_path}, no floating point is involved. *)

type exact_error =
  | PhaseNotDyadic
      (** A path phase is not a dyadic rational. *)
  | RootExponentTooLarge
      (** The required root exponent exceeds [~max_root_exponent]. *)
(** Errors propagated by {!group_exact}. *)

val group_exact :
  ?max_root_exponent:int ->
  path_var_count:int ->
  expanded_path list ->
  (exact_grouped_path list, exact_error) result
(** [group_exact ~path_var_count paths] sums the exact amplitudes of the
    expanded paths leading to the same basis state, returning one entry per
    basis state. It mirrors {!group} but keeps integer arithmetic: each path
    contributes [e^(2πi·phase) / 2^(m/2)] with [m = path_var_count ≥ 0].

    For even [m = 2r] the normalization is [2^(-r)]. For odd [m = 2r+1] it
    is [2^(-(r+1)) · √2] with [√2 = ζ_8 + ζ_8^(-1)] distributed into the
    coefficients, which requires [k ≥ 3]. The root exponent is
    [k = max(1, max k_phases, 3 if m is odd)].

    Each phase denominator is checked strictly positive and a power of two
    before calling [Common.Rational.find_k], so a non-dyadic phase returns
    [Error PhaseNotDyadic] instead of raising. [~max_root_exponent] bounds
    [k] and is checked before any allocation; exceeding it returns
    [Error RootExponentTooLarge]. The int range ([k < Sys.int_size - 1], so
    that [1 lsl k] is well defined and positive) and [Sys.max_array_length]
    are checked as well, before any allocation; violating either also
    returns [Error RootExponentTooLarge].

    Example: grouping exactly the expansion of H on |0> gives two entries,
    |0> and |1>, both with amplitude [1/sqrt(2)] = [2^(-1) · (ζ_8 +
    ζ_8^(-1))]. *)

val exact_is_zero : exact_amplitude -> bool
(** [exact_is_zero amp] is [true] iff all coefficients of the reduced form
    are zero. *)

val exact_equal : exact_amplitude -> exact_amplitude -> bool
(** [exact_equal amp1 amp2] decides equality exactly: it aligns the root
    exponents (spreading multiplicities, [ζ_{2^k1} = ζ_{2^k}^(2^(k-k1))]),
    aligns the scales (multiplying by [2^|Δs|]), folds both sides modulo
    [Φ_{2^k}] and compares the coefficient vectors. *)

val exact_mul : exact_amplitude -> exact_amplitude -> exact_amplitude
(** [exact_mul amp1 amp2] is the exact product: aligned root exponents,
    added scales, convolution of the coefficient vectors folded modulo
    [Φ_{2^k}]. Used for the division-free global-phase comparison.

    Not implemented yet: calling it raises [Failure]. *)
