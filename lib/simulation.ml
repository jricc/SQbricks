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
