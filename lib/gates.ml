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

open Printf
open Common
include Rational
include Path_sum
module PS = Poly.String
module QS = Qubit.String
module PSS = String
module Monome = Poly.Monome

type t = GP of Q.t * int | U1 of Q.t * int | X | H

let to_string g =
  match g with
  | H -> "H"
  | X -> "X"
  | U1 (s, k) -> sprintf "Rz(%s.2.pi/2^%d)" (Q.to_string s) k
  | GP (s, k) -> sprintf "GP(%s.2.pi/2^%d)" (Q.to_string s) k

let equal g1 g2 =
  match (g1, g2) with
  | H, H -> true
  | X, X -> true
  | U1 (s1, k1), U1 (s2, k2) when Q.equal s1 s2 -> k1 = k2
  | GP (s1, k1), GP (s2, k2) when Q.equal s1 s2 -> k1 = k2
  | _ -> false

(* Temporary profiler for locating gate-application costs. Measurements are
   aggregated in memory because writing one line per gate would perturb short
   operations. Nested stages therefore overlap with the [total] measurement. *)
module Gate_cost_profile = struct
  type measurement = {
    mutable calls : int;
    mutable wall_seconds : float;
    mutable cpu_seconds : float;
  }

  type state = {
    channel : out_channel;
    measurements : (string * int * int * string, measurement) Hashtbl.t;
  }

  let state =
    match Sys.getenv_opt "SQBRICKS_PROFILE_GATE_COST_FILE" with
    | None -> None
    | Some filename ->
        let channel =
          open_out_gen [ Open_wronly; Open_creat; Open_append; Open_text ] 0o644
            filename
        in
        fprintf channel "GATE_PROFILE_BEGIN pid=%d\n%!" (Unix.getpid ());
        Some { channel; measurements = Hashtbl.create 32 }

  let enabled = match state with None -> false | Some _ -> true

  let add_measurement measurements key wall_seconds cpu_seconds =
    let measurement =
      match Hashtbl.find_opt measurements key with
      | Some measurement -> measurement
      | None ->
          let measurement = { calls = 0; wall_seconds = 0.; cpu_seconds = 0. } in
          Hashtbl.add measurements key measurement;
          measurement
    in
    measurement.calls <- measurement.calls + 1;
    measurement.wall_seconds <- measurement.wall_seconds +. wall_seconds;
    measurement.cpu_seconds <- measurement.cpu_seconds +. cpu_seconds

  let measure gate control_count width stage operation =
    match state with
    | None -> operation ()
    | Some { measurements; _ } ->
        let wall_start = Unix.gettimeofday () in
        let cpu_start = Sys.time () in
        Fun.protect
          ~finally:(fun () ->
            add_measurement measurements (gate, control_count, width, stage)
              (Unix.gettimeofday () -. wall_start)
              (Sys.time () -. cpu_start))
          operation

  let write_measurements { channel; measurements } =
    let entries =
      Hashtbl.fold
        (fun key measurement entries -> (key, measurement) :: entries)
        measurements []
      |> List.fast_sort (fun (key1, _) (key2, _) -> Stdlib.compare key1 key2)
    in
    List.iter
      (fun ((gate, control_count, width, stage), measurement) ->
        fprintf channel
          "GATE_PROFILE gate=%s controls=%d width=%d stage=%s calls=%d wall_s=%.6f cpu_s=%.6f\n"
          gate control_count width stage measurement.calls
          measurement.wall_seconds measurement.cpu_seconds)
      entries;
    fprintf channel "GATE_PROFILE_END pid=%d\n%!" (Unix.getpid ());
    close_out_noerr channel

  let () =
    match state with
    | None -> ()
    | Some state -> at_exit (fun () -> write_measurements state)
end

module Apply_gates = struct
  type poly = Poly.PolyHeap.t

  let merge = Poly.merge
  let ( ++ ) (m : Monome.t) (p : Poly.t) : Poly.t = Poly.insert m p
  let ( @@ ) (p1 : poly) (p2 : poly) : poly = merge p1 p2
  let ( +++ ) p1 p2 : Qubit.t = SumMod2 (p1, p2)

  let rec apply_control (ket : Ket.t) co : Qubit.t =
    match co with
    | h :: [] -> ket.(h)
    | h :: co' -> Qubit.Prod (ket.(h), apply_control ket co')
    | [] -> Qubit.One

  let of_qubit ?(debug = false) (q : Qubit.t) (s : Q.t) : poly =
    Poly.of_qubit ~debug (Qubit.simplify q) s

  let of_qubit_2_pi (q : Qubit.t) : poly = Poly.of_qubit_2_pi (Qubit.simplify q)
  let distribution = Poly.distribution
  let int_sort l = List.fast_sort Int.compare l

  let simplify_gate_output ?(simplify_all = true) ?target ~phase_changed gate
      control_count ps =
    if simplify_all && not Gate_cost_profile.enabled then
      Rules.Simplification.simplify ps
    else
      let width = Array.length ps.ket in
      let ket =
        if simplify_all then
          Gate_cost_profile.measure gate control_count width "ket_simplification"
            (fun () -> Ket.simplify ps.ket)
        else
          match target with
          | None -> ps.ket
          | Some target ->
              Gate_cost_profile.measure gate control_count width
                "target_ket_simplification" (fun () ->
                  let ket = Ket.copy ps.ket in
                  ket.(target) <- Qubit.simplify ket.(target);
                  ket)
      in
      let phase =
        if simplify_all || phase_changed then
          Gate_cost_profile.measure gate control_count width
            "phase_simplification" (fun () -> Poly.simplify ps.phase)
        else ps.phase
      in
      { phase; ket; path_var = ps.path_var }

  let profile_gate gate ps controls operation =
    Gate_cost_profile.measure gate (List.length controls)
      (Array.length ps.ket) "total" operation

  let profile_gate_stage gate ps controls stage operation =
    Gate_cost_profile.measure gate (List.length controls)
      (Array.length ps.ket) stage operation

  let apply_hadamard_impl ~simplify_all ps co ta : Path_sum.t =
    (* \(1/2 (x_{co} x_{ta} y) + 1/8 ((1-x_{co}) (1-2y)) \) *)
    let apply_hadamard_phase (xta : Qubit.t) (y0 : int) (control : Qubit.t) :
        poly =
      let p_control = of_qubit_2_pi control in
      Scal div8
      ++ (Prod (Scal divm4, Qubit (Var y0))
         ++ (distribution ~s1:div2 (Qubit (Var y0))
               (of_qubit_2_pi (Prod (control, xta)))
            @@ distribution (Scal divm8) p_control
            @@ distribution ~s1:div4 (Qubit (Var y0)) p_control))
    in
    let apply_hadamard_without_control ps ta y0 : Path_sum.t =
      let lifted_target =
        profile_gate_stage "H" ps co "target_lift" (fun () ->
            let simplified_target =
              profile_gate_stage "H" ps co "target_qubit_simplification"
                (fun () -> Qubit.simplify (Prod (Var y0, ps.ket.(ta))))
            in
            profile_gate_stage "H" ps co "target_poly_conversion" (fun () ->
                Poly.of_qubit_2_pi simplified_target))
      in
      let simplified_delta =
        profile_gate_stage "H" ps co "delta_simplification" (fun () ->
            Poly.simplify_monomes lifted_target)
      in
      let scaled_delta =
        profile_gate_stage "H" ps co "delta_distribution" (fun () ->
            distribution (Scal div2) simplified_delta)
      in
      let p : poly =
        profile_gate_stage "H" ps co "phase_merge" (fun () ->
            scaled_delta @@ ps.phase)
      in
      let output_ket =
        profile_gate_stage "H" ps co "ket_update" (fun () ->
            let output_ket = Ket.copy ps.ket in
            output_ket.(ta) <- Var y0;
            output_ket)
      in
      let path_var =
        profile_gate_stage "H" ps co "path_var_sort" (fun () ->
            int_sort (y0 :: ps.path_var))
      in
      { phase = p; ket = output_ket; path_var }
    in
    let apply_hadamard_ket (input_ket : Ket.t) ta y0 control : Ket.t =
      let output_ket = Ket.copy input_ket in
      let target_qubit = input_ket.(ta) in
      output_ket.(ta) <-
        Prod (control, Var y0)
        +++ (target_qubit +++ Prod (control, target_qubit));
      output_ket
    in
    let y0 =
      profile_gate_stage "H" ps co "fresh_path_var" (fun () ->
          if List.equal Int.equal ps.path_var [] then Array.length ps.ket
          else ListBis.max_int ps.path_var + 1)
    in
    let ps_output : Path_sum.t =
      match co with
      | [] -> apply_hadamard_without_control ps ta y0
      | _ ->
          let control =
            profile_gate_stage "H" ps co "control_update" (fun () ->
                Qubit.simplify (apply_control ps.ket co))
          in
          let xta = ps.ket.(ta) in
          let phase =
            profile_gate_stage "H" ps co "phase_update" (fun () ->
                ps.phase @@ apply_hadamard_phase xta y0 control)
          in
          let ket =
            profile_gate_stage "H" ps co "ket_update" (fun () ->
                apply_hadamard_ket ps.ket ta y0 control)
          in
          let path_var =
            profile_gate_stage "H" ps co "path_var_sort" (fun () ->
                int_sort (y0 :: ps.path_var))
          in
          {
            phase;
            ket;
            path_var;
          }
    in
    simplify_gate_output ~simplify_all ~target:ta ~phase_changed:true "H"
      (List.length co) ps_output

  let apply_hadamard ?(simplify_all = true) ps co ta =
    profile_gate "H" ps co (fun () ->
        apply_hadamard_impl ~simplify_all ps co ta)

  let apply_not_impl ~simplify_all ps co ta =
    let (q : Qubit.t) =
      match co with
      | [] -> One +++ ps.ket.(ta)
      | _ -> apply_control ps.ket co +++ ps.ket.(ta)
    in
    let output_ket = Ket.copy ps.ket in
    output_ket.(ta) <- q;
    let ps_output =
      { phase = ps.phase; ket = output_ket; path_var = ps.path_var }
    in
    simplify_gate_output ~simplify_all ~target:ta ~phase_changed:false "X"
      (List.length co) ps_output

  let apply_not ?(simplify_all = true) ps co ta =
    profile_gate "X" ps co (fun () -> apply_not_impl ~simplify_all ps co ta)

  let apply_u1_impl ?(debug = false) ~simplify_all (angle' : Q.t) ps co ta =
    let width = Array.length ps.ket in
    if debug then
      printf "Gates.apply_u1, angle' = %s\n\n%!" (Q.to_string angle');
    if debug then
      printf "Gates.apply_u1, co = %s, ta = %d\n\n%!" (ListBis.string_int co) ta;
    if debug then printf "Gates.apply_u1, ps =\n%s\n\n%!" (PSS.pretty ps);
    let angle =
      let k = find_k angle'.den in
      if Q.lt angle' Q.zero then
        Q.make (Z.sub (pow2Z k) (Z.neg angle'.num)) angle'.den
      else angle'
    in
    if debug then printf "Gates.apply_u1, angle = %s\n\n%!" (Q.to_string angle);
    let p_ta =
      profile_gate_stage "U1" ps co "target_lift" (fun () ->
          let simplified_target =
            profile_gate_stage "U1" ps co "target_qubit_simplification"
              (fun () -> Qubit.simplify ps.ket.(ta))
          in
          profile_gate_stage "U1" ps co "target_poly_conversion" (fun () ->
              if Q.equal angle div2 || Q.equal angle divm2 then
                Poly.of_qubit_2_pi simplified_target
              else Poly.of_qubit ~debug simplified_target angle))
    in
    if debug then
      printf "Gates.apply_u1, p_ta = %s\n\n%!" (PS.pretty p_ta width);
    let p_output =
      match co with
      | [] ->
          let p =
            profile_gate_stage "U1" ps co "phase_distribution" (fun () ->
                distribution (Scal angle) p_ta)
          in
          if debug then
            printf "Gates.apply_u1, p = %s\n\n%!" (PS.pretty p width);
          let simplified_delta =
            profile_gate_stage "U1" ps co "delta_simplification" (fun () ->
                Poly.simplify p)
          in
          profile_gate_stage "U1" ps co "phase_merge" (fun () ->
              ps.phase @@ simplified_delta)
      | _ ->
          let p_control =
            profile_gate_stage "U1" ps co "control_lift" (fun () ->
                if Q.equal angle div2 || Q.equal angle divm2 then
                  of_qubit_2_pi (apply_control ps.ket co)
                else of_qubit (apply_control ps.ket co) angle)
          in
          let product =
            profile_gate_stage "U1" ps co "phase_product" (fun () ->
                Poly.prod p_control p_ta)
          in
          let scaled_product =
            profile_gate_stage "U1" ps co "phase_distribution" (fun () ->
                distribution (Scal angle) product)
          in
          profile_gate_stage "U1" ps co "phase_merge" (fun () ->
              ps.phase @@ scaled_product)
    in
    let ps_output =
      { phase = p_output; ket = ps.ket; path_var = ps.path_var }
    in
    simplify_gate_output ~simplify_all ~phase_changed:true "U1"
      (List.length co) ps_output

  let apply_u1 ?(debug = false) ?(simplify_all = true) angle ps co ta =
    profile_gate "U1" ps co (fun () ->
        apply_u1_impl ~debug ~simplify_all angle ps co ta)

  let apply_gp_impl ~simplify_all (angle' : Q.t) ps co =
    let angle =
      let k = find_k angle'.den in
      if Q.lt angle' Q.zero then
        Q.make (Z.sub (pow2Z k) (Z.neg angle'.num)) angle'.den
      else angle'
    in
    let p_output =
      match co with
      | [] -> Scal angle ++ ps.phase
      | _ ->
          let p_control =
            if Q.equal angle Q.one then of_qubit_2_pi (apply_control ps.ket co)
            else of_qubit (apply_control ps.ket co) angle
          in
          ps.phase @@ distribution (Scal angle) p_control
    in
    let ps_output =
      { phase = p_output; ket = ps.ket; path_var = ps.path_var }
    in
    simplify_gate_output ~simplify_all ~phase_changed:true "GP"
      (List.length co) ps_output

  let apply_gp ?(simplify_all = true) angle ps co =
    profile_gate "GP" ps co (fun () ->
        apply_gp_impl ~simplify_all angle ps co)

  let apply_classical_not ps ta =
    let output_ket = Ket.copy ps.ket in
    (match output_ket.(ta) with
    | Zero -> output_ket.(ta) <- One
    | One -> output_ket.(ta) <- Zero
    | _ ->
        failwith (sprintf "Path_sum.Not, ta = %d, ps = %s" ta (PSS.pretty ps)));
    { phase = ps.phase; ket = output_ket; path_var = ps.path_var }
end
