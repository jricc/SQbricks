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

module GetProg : sig
  val to_prog : ?debug:bool -> string -> Program.t
  (** [to_prog ?debug input] locates and parses the OpenQASM file [input]. Its
      input channel is closed whether parsing succeeds or raises an exception. *)
end

module GetPs : sig
  val to_ps : ?debug:bool -> string -> Path_sum.t
  (** [to_ps ?debug input] locates and parses the path-sum file [input]. Its
      input channel is closed whether parsing succeeds or raises an exception. *)
end
