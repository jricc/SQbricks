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

(* Prototype benchmark: exact grouping (Simulation.group_exact) against the
   approximate Complex grouping (Simulation.group) on the same prebuilt
   paths. Every case is synthetic and explicit: reinforcement without
   cancellation, partial cancellation, total cancellation. Only the grouping
   call is inside the timed region; data generation, the expected-state
   check and printing happen outside it.
   Protocol: per case, one probe call that reports an error explicitly (and
   then skips timing) and checks the per-call state count against the value
   expected from the generator parameters; then [batches] batches of [reps]
   calls, reported as median per-call wall time with min and max.
   Allocated words per call use the exact counters of [Gc.counters ()]:
   minor + major - promoted (promoted words appear in both minor and major
   and must not be counted twice). This is a cumulative allocation figure,
   not a peak-memory figure. Wrap the run in an external timeout, e.g.
   [timeout 300 dune exec ./test/simulation_exact_bench.exe]. *)

open SQbricks

(* Deterministic synthetic complete expansion: n = 2^m paths over at most
   2^width states. State s carries the base phase (s mod 2^den_exp) /
   2^den_exp; every non-paired path going to state s uses that same phase,
   so paths to the same state reinforce and never cancel by accident. The
   first [2 * cancel_pairs] paths form explicit cancelling pairs: both paths
   of pair p share state (p mod 2^width) and carry the base phase q of that
   state and q + 1/2, so each pair cancels exactly. *)
let make_paths ~(path_var_count : int) ~(width : int) ~(den_exp : int)
    ~(cancel_pairs : int) : Simulation.expanded_path list =
  let n = 1 lsl path_var_count in
  let state_count = 1 lsl width in
  let den = 1 lsl den_exp in
  let state_of s =
    Array.init width (fun bit -> (s / (1 lsl bit)) mod 2 = 1)
  in
  let base_phase s = Q.make (Z.of_int (s mod den)) (Z.of_int den) in
  let pair_paths =
    List.concat_map
      (fun p ->
        let s = p mod state_count in
        let q = base_phase s in
        let half = Q.make Z.one (Z.of_int 2) in
        [
          ({ basis_state = state_of s; phase = q } : Simulation.expanded_path);
          ( {
              basis_state = state_of s;
              phase = Q.add q half;
            }
            : Simulation.expanded_path );
        ])
      (List.init cancel_pairs (fun p -> p))
  in
  let remaining = n - (2 * cancel_pairs) in
  let other_paths =
    List.init remaining (fun i ->
        let s = i mod state_count in
        ( {
            basis_state = state_of s;
            phase = base_phase s;
          }
          : Simulation.expanded_path ))
  in
  pair_paths @ other_paths

(* Expected per-call state count, computed from the parameters alone and
   checked outside the timed region. The exact grouping drops pair-only
   states (each pair cancels exactly), so it keeps the states that have at
   least one reinforcing path: min(remaining, state_count). The Complex
   grouping keeps zero-amplitude states, so every touched state counts:
   min(max(cancel_pairs, remaining), state_count). *)
let expected_states ~(path_var_count : int) ~(width : int)
    ~(cancel_pairs : int) ~(exact : bool) : int =
  let state_count = 1 lsl width in
  let remaining = (1 lsl path_var_count) - (2 * cancel_pairs) in
  if exact then min remaining state_count
  else min (max cancel_pairs remaining) state_count

(* Cumulative allocated words from the exact counters of [Gc.counters ()]:
   minor + major - promoted, because promoted words appear in both the minor
   and the major counter. *)
let allocated_words () : float =
  let minor, promoted, major = Gc.counters () in
  minor +. major -. promoted

let string_of_exact_error (error : Simulation.exact_error) : string =
  match error with
  | Simulation.Negative_path_var_count m ->
      Printf.sprintf "Negative_path_var_count %d" m
  | Simulation.Invalid_path_count { path_var_count; actual_count } ->
      Printf.sprintf "Invalid_path_count {path_var_count=%d; actual_count=%d}"
        path_var_count actual_count
  | Simulation.Inconsistent_state_width
      { path_index; expected_width; actual_width } ->
      Printf.sprintf
        "Inconsistent_state_width {path_index=%d; expected_width=%d; \
         actual_width=%d}"
        path_index expected_width actual_width
  | Simulation.Non_finite_phase { path_index } ->
      Printf.sprintf "Non_finite_phase {path_index=%d}" path_index
  | Simulation.Non_dyadic_phase { path_index; phase } ->
      Printf.sprintf "Non_dyadic_phase {path_index=%d; phase=%s}" path_index
        (Q.to_string phase)

(* Both groupings behind the same interface: Ok with the grouped list. *)
let group_complex ~(path_var_count : int)
    (paths : Simulation.expanded_path list) :
    (Simulation.grouped_path list, string) result =
  Ok (Simulation.group ~path_var_count paths)

let group_exact ~(path_var_count : int)
    (paths : Simulation.expanded_path list) :
    (Simulation.exact_grouped_path list, string) result =
  match Simulation.group_exact ~path_var_count paths with
  | Ok grouped -> Ok grouped
  | Error error -> Error (string_of_exact_error error)

(* Times [batches] batches of [reps] calls of [group] on the prebuilt [paths].
   The probe call reports an error explicitly and skips timing; its state
   count is checked against [expected_states]. Inside the timed region only
   the grouping call runs: the result is stored in a ref and inspected
   after. *)
let measure label ~(expected_states : int) ~(batches : int) ~(reps : int)
    (paths : Simulation.expanded_path list) group =
  match group paths with
  | Error message ->
      Printf.printf "%-24s FAILED: %s; no timing reported\n" label message;
      flush stdout
  | Ok first ->
      let states = List.length first in
      let check = if states = expected_states then "OK" else "MISMATCH" in
      Gc.full_major ();
      let alloc_before = allocated_words () in
      let batch_seconds =
        List.init batches (fun _ ->
            let t0 = Unix.gettimeofday () in
            let sink = ref first in
            for _ = 1 to reps do
              match group paths with
              | Ok grouped -> sink := grouped
              | Error message -> failwith message
            done;
            let t1 = Unix.gettimeofday () in
            ignore !sink;
            t1 -. t0)
      in
      let alloc_after = allocated_words () in
      let per_call =
        List.sort compare
          (List.map (fun seconds -> seconds /. float_of_int reps) batch_seconds)
      in
      let median = List.nth per_call (batches / 2) in
      let min = List.hd per_call in
      let max = List.nth per_call (batches - 1) in
      Printf.printf
        "%-24s states/call=%-5d expected=%-5d %-8s batches=%d reps=%-4d \
         median %9.4f ms/call (min %9.4f, max %9.4f) %12.1f words/call\n"
        label states expected_states check batches reps (median *. 1000.0)
        (min *. 1000.0) (max *. 1000.0)
        ((alloc_after -. alloc_before) /. float_of_int (batches * reps));
      flush stdout

(* Bounded explicit cases: reinforcement without cancellation, partial
   cancellation and total cancellation, at several sizes. *)
let batches = 5

let configs =
  [
    (* name, m, width, den_exp, cancel_pairs, reps *)
    ("reinforce small", 4, 2, 3, 0, 500);
    ("reinforce large", 12, 5, 8, 0, 3);
    ("reinforce many states", 8, 8, 5, 0, 50);
    ("partial cancellation", 8, 8, 5, 100, 50);
    ("partial cancellation wide", 10, 4, 6, 256, 10);
    ("total cancellation", 2, 1, 2, 2, 2000);
  ]

let () =
  Printf.printf
    "SQbricks prototype benchmark: group_exact (exact) vs group (Complex).\n";
  Printf.printf
    "Synthetic complete expansions, prebuilt once; only the grouping call is timed.\n";
  Printf.printf
    "Protocol: probe call with expected-state check, then %d batches per case; \
     median per-call wall time (Unix.gettimeofday).\n"
    batches;
  Printf.printf
    "Allocated words per call: Gc.counters minor + major - promoted \
     (cumulative, not peak).\n";
  List.iter
    (fun (name, m, width, den_exp, cancel_pairs, reps) ->
      let paths =
        make_paths ~path_var_count:m ~width ~den_exp ~cancel_pairs
      in
      Printf.printf
        "\ncase %s: m=%d paths=%d width=%d den_exp=%d cancel_pairs=%d\n" name m
        (List.length paths) width den_exp cancel_pairs;
      measure "group (Complex)"
        ~expected_states:
          (expected_states ~path_var_count:m ~width ~cancel_pairs ~exact:false)
        ~batches ~reps paths (group_complex ~path_var_count:m);
      measure "group_exact"
        ~expected_states:
          (expected_states ~path_var_count:m ~width ~cancel_pairs ~exact:true)
        ~batches ~reps paths (group_exact ~path_var_count:m))
    configs
