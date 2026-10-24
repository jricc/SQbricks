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

(** This module provides functions for verifying the equivalence of quantum
    circuits using symbolic execution and path sum techniques. *)

(** Type representing the result of an equivalence check between quantum
    circuits. *)
type result =
  | SubCircuitEquivalent  (** Circuits are equivalent as subcircuits *)
  | FullCircuitEquivalent
  | GlobalPhaseEquivalent  (** Circuits are equivalent up to global phase *)
  | NotEquivDiffMeasurements  (** Circuits differ in measurements *)
  | NotEquivDiffOutputs  (** Circuits differ in outputs *)
  | NotEquivDiffInputs  (** Circuits differ in inputs *)
  | NotEquivDiffInputsOutputs  (** Circuits differ in both inputs and outputs *)
  | NotEquivDiffStates of bool array * bool array
      (** Circuits differ on a concrete input: the counterexample is the
          input and the first differing basis state. *)
  | SubCircuitInconclusive  (** Subcircuit equivalence check was inconclusive *)
  | Entanglement1  (** First circuit shows entanglement *)
  | Entanglement2  (** Second circuit shows entanglement *)
  | GlobalPhaseInconclusive
      (** Global phase equivalence check was inconclusive *)
  | FullCircuitInconclusive
  | FullCircuitInconclusiveAmp
  | FullCircuitInconclusiveKet
  | ErrorCircuitNotUnitary  (** Error: circuit is not unitary *)
  | ErrorInvalidQubitIndex  (** Error: input, output, or measurement index is invalid *)
  | ErrorInvalidProgram
      (** Error: the program has an invalid gate application *)
  | ErrorFullCircuitNotImplemented
      (** Error: full-circuit equivalence is not implemented *)
  | ErrorBothCircuitsHaveInits
      (** Error: sequential equivalence cannot handle initializations on both circuits *)
  | ErrorMalformedPathSum
      (** Error: reduction received a malformed path sum *)

val result_to_string : result -> string
(** Converts an equivalence result to a string representation.

    Example: [result_to_string SubCircuitEquivalent] results
    ["SubCircuitEquivalent"] *)

(** Type representing the type of equivalence to check. *)
type equivalence = SubCircuit | FullCircuit | GlobalPhase

val seq :
  ?debug:bool ->
  ?inputs1:int list ->
  ?inputs2:int list ->
  ?outputs1:int list ->
  ?outputs2:int list ->
  ?meas1:int list ->
  ?meas2:int list ->
  ?equivalence:equivalence ->
  Program.t ->
  Program.t ->
  result
(** Checks equivalence of two quantum circuits using sequence algorithm. Returns
    one of the result values indicating equivalence or reason for
    non-equivalence.

    Example: [seq (h 0) (h 0)] results [SubCircuitEquivalent] *)

val parallel :
  ?debug:bool ->
  ?inputs1:int list ->
  ?inputs2:int list ->
  ?outputs1:int list ->
  ?outputs2:int list ->
  ?meas1:int list ->
  ?meas2:int list ->
  ?equivalence:equivalence ->
  Program.t ->
  Program.t ->
  result
(** Checks equivalence of two quantum circuits using parallel algorithm. Returns
    one of the result values indicating equivalence or reason for
    non-equivalence.

    Example: [parallel (h 0) (h 0)] results [SubCircuitEquivalent] *)

(** Type representing the algorithm to use for equivalence checking. *)
type algo = Parallel | Sequence | Simulation

val sqv :
  ?debug:bool ->
  ?inputs1:int list ->
  ?inputs2:int list ->
  ?outputs1:int list ->
  ?outputs2:int list ->
  ?meas1:int list ->
  ?meas2:int list ->
  ?algo:algo ->
  ?equivalence:equivalence ->
  Program.t ->
  Program.t ->
  result
(** Main function for verifying equivalence between quantum circuits. Uses
    either sequence or parallel algorithm based on parameter.

    Example: [sqv (h 0) (h 0)] results [SubCircuitEquivalent] *)

val sqv_simple :
  ?debug:bool ->
  ?inputs1:int list ->
  ?inputs2:int list ->
  ?outputs1:int list ->
  ?outputs2:int list ->
  ?meas1:int list ->
  ?meas2:int list ->
  ?algo:algo ->
  ?equivalence:equivalence ->
  ?not_equiv:bool ->
  Program.t ->
  Program.t ->
  bool
(** Simplified version of sqv that returns a boolean indicating equivalence.

    Example: [sqv_simple (h 0) (h 0)] results [true] *)

val simulation :
  ?debug:bool ->
  ?inputs1:int list ->
  ?inputs2:int list ->
  ?outputs1:int list ->
  ?outputs2:int list ->
  ?meas1:int list ->
  ?meas2:int list ->
  ?equivalence:equivalence ->
  ?max_inputs:int ->
  ?max_path_vars:int ->
  ?max_root_exponent:int ->
  Program.t ->
  Program.t ->
  result
(** Checks equivalence of two unitary circuits by variable instantiation,
    reusing the metadata validation of {!seq} and {!parallel}.

    Not implemented yet: calling [simulation] raises [Failure]. The rest of
    this comment describes the planned increment 1.

    Planned increment 1 (concrete, level 2): each basis input is
    instantiated in turn; path variables are unfolded and grouped exactly
    ({!Simulation.group_exact}). The first differing input/state pair
    proves non-equivalence and is returned as [NotEquivDiffStates];
    exhausting all inputs proves equivalence at the requested level.

    Supported configurations (planned increment 1): full inputs and outputs
    on both circuits ([inputs = outputs = [0..wq-1]]), no initialized
    ancillas, equal register widths. Comparing complete states then
    respects the [FullCircuit] and [GlobalPhase] contracts exactly. Any
    other configuration — partial inputs or outputs, ancillas, differing
    widths — returns the inconclusive result of the requested level, after
    metadata validation. [SubCircuit] is not decided by this increment and
    returns [SubCircuitInconclusive].

    [~max_inputs] bounds the number of concrete inputs enumerated (default
    256, i.e. up to 8 qubits); [~max_path_vars] bounds the path-variable
    count [m] (no [2^m] unfolding beyond it); [~max_root_exponent] bounds
    the cyclotomic exponent [k], checked before any allocation. Exceeding a
    bound returns the corresponding inconclusive result.

    Unlike {!seq} and {!parallel}, [FullCircuit] is decided here: exact
    amplitude equality comes for free from the simulation.

    Planned example: [simulation ~equivalence:FullCircuit (x 0) (x 0)]
    results [FullCircuitEquivalent] *)
