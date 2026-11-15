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

(* PROTOTYPE external comparison runner for SQbricks. For each OpenQASM file
   given as argument, runs the exact symbolic pipeline on the all-zero input
   given as argument (with --direct, group_exact runs on the paths of
   expand_direct instead of expand), and prints machine-readable lines:
     phase_ms,<case>,<phase>,<ms>   parse | execute | reduce | expand |
                                    expand_direct | group_exact | total
     metric,<case>,expand_variant,expand|expand_direct
     metric,<case>,expanded_paths,<n>   and   metric,<case>,paths_agree,0|1
     amp,<case>/group_exact,<index>,<re>,<im>
     peak_rss_mb,<case>,<mb>        process peak RSS (VmHWM, Linux)
     error,<case>,<phase>,<kind>
   Only the exact chain is measured: the approximate [Simulation.group] is
   not part of this pipeline. Exported amplitudes come from
   [Simulation.group_exact], converted to floats with
   [Simulation.exact_to_complex] solely for the numeric cross-check.
   Basis index convention: qubit i is bit i of the index (little-endian), the
   same convention as Qiskit. The global phase is kept. *)

open SQbricks

let now () = Unix.gettimeofday ()

let elapsed_ms t0 t1 = (t1 -. t0) *. 1000.0

(* Peak resident set of this process, read from /proc/self/status (kB). *)
let peak_rss_kb () =
  let ic = In_channel.open_text "/proc/self/status" in
  let rec find () =
    match In_channel.input_line ic with
    | None -> 0
    | Some line ->
        if String.starts_with ~prefix:"VmHWM:" line then
          (try Scanf.sscanf line "VmHWM: %d kB" (fun kb -> kb) with _ -> 0)
        else find ()
  in
  let kb = find () in
  In_channel.close ic;
  kb

(* Little-endian basis index: qubit i is bit i of the state index. *)
let index_of_state (state : bool array) : int =
  let index = ref 0 in
  Array.iteri (fun i bit -> if bit then index := !index + (1 lsl i)) state;
  !index

(* Set by the --direct flag: the exact grouping then runs on the paths of
   [expand_direct] instead of [expand]. *)
let use_direct = ref false

(* Phase equality modulo 1: phases are defined up to an integer (e^(2*pi*i*p)
   is 1-periodic), and [Poly.simplify] normalizes them into [0,1). *)
let phase_mod_one (q : Q.t) : Q.t =
  Q.make (Z.erem (Q.num q) (Q.den q)) (Q.den q)

let paths_equal_mod_one (a : Simulation.expanded_path list)
    (b : Simulation.expanded_path list) : bool =
  List.length a = List.length b
  && List.for_all2
       (fun (x : Simulation.expanded_path) (y : Simulation.expanded_path) ->
         x.basis_state = y.basis_state
         && Q.equal (phase_mod_one x.phase) (phase_mod_one y.phase))
       a b

let run_case (path : string) : unit =
  let case_name = Filename.remove_extension (Filename.basename path) in
  let report phase t0 t1 =
    Printf.printf "phase_ms,%s,%s,%.6f\n" case_name phase (elapsed_ms t0 t1)
  in
  let t_total0 = now () in
  let t0 = now () in
  let parsed =
    try Some (Parser_get.GetProg.to_prog path)
    with e ->
      Printf.printf "error,%s,parse,%s\n" case_name (Printexc.to_string e);
      None
  in
  match parsed with
  | None -> ()
  | Some prog ->
      let _, circuit_width = Program.widths prog in
      let input_state : Path_sum.t =
        {
          phase = Poly.empty;
          ket = Array.make circuit_width Qubit.Zero;
          path_var = [];
        }
      in
      let t1 = now () in
      report "parse" t0 t1;
      match Program.execution_result ~input_state prog with
      | Error _ -> Printf.printf "error,%s,execute,execution_error\n" case_name
      | Ok executed ->
          let t2 = now () in
          report "execute" t1 t2;
          match Reduction_algorithm.reduction_algorithm executed with
          | Error _ ->
              Printf.printf "error,%s,reduce,reduction_error\n" case_name
          | Ok reduced ->
              let t3 = now () in
              report "reduce" t2 t3;
              let m = List.length reduced.path_var in
              (* Reference expansion and experimental direct expansion. *)
              let t4 = now () in
              let expanded = Simulation.expand reduced in
              let t5 = now () in
              report "expand" t4 t5;
              let t6 = now () in
              let direct = Simulation.expand_direct reduced in
              let t7 = now () in
              report "expand_direct" t6 t7;
              let chosen, chosen_name =
                if !use_direct then (direct, "expand_direct")
                else (expanded, "expand")
              in
              Printf.printf "metric,%s,expand_variant,%s\n" case_name
                chosen_name;
              (match (expanded, direct) with
              | Ok paths, Ok direct_paths ->
                  Printf.printf "metric,%s,expanded_paths,%d\n" case_name
                    (List.length paths);
                  (* Structural equality is intended here: same physical
                     paths produced by the two expansions. *)
                  let agree = paths_equal_mod_one paths direct_paths in
                  Printf.printf "metric,%s,paths_agree,%d\n" case_name
                    (if agree then 1 else 0);
                  if not agree then
                    (* Diagnostic: first differing paths, old vs direct. *)
                    let state_string s =
                      String.concat ""
                        (Array.to_list
                           (Array.map (fun b -> if b then "1" else "0") s))
                    in
                    let diffs = ref 0 in
                    List.iteri
                      (fun i (a : Simulation.expanded_path) ->
                        if !diffs < 5 && i < List.length direct_paths then
                          let b = List.nth direct_paths i in
                          if
                            (not (a.basis_state = b.basis_state))
                            || not
                                 (Q.equal (phase_mod_one a.phase)
                                    (phase_mod_one b.phase))
                          then begin
                            incr diffs;
                            Printf.printf "pathdiff,%s,%d,%s,%s,%s,%s\n"
                              case_name i (state_string a.basis_state)
                              (Q.to_string a.phase)
                              (state_string b.basis_state)
                              (Q.to_string b.phase)
                          end)
                      paths
              | Error _, _ ->
                  Printf.printf "error,%s,expand,expand_error\n" case_name
              | _, Error _ ->
                  Printf.printf "error,%s,expand_direct,expand_error\n"
                    case_name);
              match chosen with
              | Error _ ->
                  Printf.printf "error,%s,chosen_expand,expand_error\n"
                    case_name
              | Ok paths ->
                  let t8 = now () in
                  (match Simulation.group_exact ~path_var_count:m paths with
                  | Error _ ->
                      Printf.printf "error,%s,group_exact,exact_error\n"
                        case_name
                  | Ok grouped_exact ->
                      let t9 = now () in
                      report "group_exact" t8 t9;
                      List.iter
                        (fun (entry : Simulation.exact_grouped_path) ->
                          let index = index_of_state entry.basis_state in
                          let { Complex.re = re; Complex.im = im } =
                            Simulation.exact_to_complex entry.amplitude
                          in
                          Printf.printf "amp,%s/group_exact,%d,%.17g,%.17g\n"
                            case_name index re im)
                        grouped_exact;
                      report "total" t_total0 t9);
                  Printf.printf "peak_rss_mb,%s,%.1f\n" case_name
                    (float_of_int (peak_rss_kb ()) /. 1024.0);
                  flush stdout

let () =
  Printf.printf "version,ocaml,%s\n" Sys.ocaml_version;
  let files =
    List.filter
      (fun arg ->
        if arg = "--direct" then (
          use_direct := true;
          false)
        else true)
      (List.tl (Array.to_list Sys.argv))
  in
  match files with
  | [] ->
      prerr_endline
        "usage: simulation_external_bench [--direct] <file.qasm> [...]";
      exit 2
  | _ -> List.iter run_case files
