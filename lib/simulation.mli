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
