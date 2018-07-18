open Bap.Std
open Core_kernel.Std


type format_as   = | Latex
                   | Standard
[@@deriving sexp]

type metrics = {
  name                : string;
  detected_insn_count : int;
  false_negatives     : int;
  false_positives     : int;
  detected_entries    : int;
  actual_entries      : int;
  trimmed             : int list;
}

module InvariantTrackingApplicator = struct
end

module MetricsGatheringReducer = struct
end

module MetricsInstrument = struct

end

let format_standard metrics =
  match metrics with 
  | Some metrics -> 
    sprintf "%s%d\n%s%d\n%s%d\n%s%d\n%s%d" 
      "Total instructions recovered: " metrics.detected_insn_count
      "False negatives: " metrics.false_negatives
      "False positives: " metrics.false_positives
      "Detected function entrances: " metrics.detected_entries
      "Actual function entrances: " metrics.actual_entries
  | None -> "No metrics gathered!"

let format_latex metrics = 
  match metrics with
  | Some metrics ->
    (match metrics.trimmed with
     | (phase1 :: phase2 :: _) ->
       sprintf "%s & %d & %d & %d & %d \\\\\n"
         metrics.name
         metrics.false_negatives
         phase1
         phase2
         metrics.detected_insn_count;
     | _ -> "Missing trim phases")
  | None -> "No metrics gathered!"

(* implement jmp_of_fp as a map from target to source in *)
(* True positive set is going to come up short because if it isn't in *)
(* the isg, it isn't going to be explored *)
let true_positives superset f = 
  let function_starts =
    Insn_disasm_benchmark.ground_truth_of_unstripped_bin f |> ok_exn
  in
  let ground_truth =
    Addr.Set.of_list @@ Seq.to_list function_starts in
  let insn_isg = Superset_risg.Oper.mirror (Superset.get_graph superset) in
  let true_positives = Addr.Hash_set.create () in
  Set.iter ground_truth ~f:(fun addr -> 
      if Superset_risg.G.mem_vertex insn_isg addr then
        Superset_risg.Dfs.prefix_component 
          (Hash_set.add true_positives) insn_isg addr;
    );
  true_positives

let reduced_occlusion superset tp =
  let fps = Addr.Hash_set.create () in
  Hash_set.iter tp ~f:(fun addr ->
      let len = Superset.len_at superset addr in
      Seq.iter (Superset_risg.seq_of_addr_range addr len) 
        ~f:(fun x -> Hash_set.add fps x);
      Hash_set.remove fps addr;
    );
  fps

let false_positives superset ro = 
  let insn_risg = Superset.get_graph superset in
  let fps = Addr.Hash_set.create () in
  Hash_set.iter ro ~f:(fun v ->
      if Superset_risg.G.mem_vertex insn_risg v then
        Hash_set.add fps v
    );
  fps

let fn_insn_cnt superset tps =
  let insn_risg = Superset.get_graph superset in
  Hash_set.fold ~init:0 tps ~f:(fun count v -> 
      if Superset_risg.G.mem_vertex insn_risg v then count 
      else count+1)

let fn_insns superset tps =
  let insn_risg = Superset.get_graph superset in
  let fn_insns = Addr.Hash_set.create () in
  Superset_risg.G.iter_vertex 
    (fun v -> if Hash_set.mem tps v then 
        Hash_set.add fn_insns v) insn_risg 

(* adjust this to collect metrics into the metrics field, and then *)
(* split the printing out into a separate function *)
let gather_metrics ~bin superset =
  let insn_map = Superset.get_map superset in
  let insn_risg = Superset.get_graph superset in
  let function_starts =
    Insn_disasm_benchmark.ground_truth_of_unstripped_bin bin |> ok_exn in
  let ground_truth =
    Addr.Set.of_list @@ Seq.to_list function_starts in
  let reduced_occlusion = Addr.Hash_set.create () in
  let true_positives = true_positives superset bin in
  let insn_isg = Superset_risg.Oper.mirror insn_risg in
  let data_bytes = Addr.Hash_set.create () in
  let dfs_find_conflicts total addr =
    let is_clean = ref true in
    let add_conflicts addr =
      (*Hash_set.add true_positives addr;*)
      (* TODO insn_map is getting mixed from the ground truth, so it *)
      (* doesn't have the length for either a removed false positive *)
      (* or negative *)
      let len = Superset.len_at superset addr in
      Seq.iter (Superset_risg.seq_of_addr_range addr len) 
        ~f:(fun x -> Hash_set.add data_bytes x);
      let conflicts_at = Superset_risg.conflict_seq_at insn_map addr
      in
      let conflicts_at = Seq.filter conflicts_at 
          ~f:Superset_risg.G.(mem_vertex insn_risg) in
      let conflicts_at = Seq.to_list conflicts_at in
      List.iter conflicts_at
        ~f:(fun x -> Hash_set.add reduced_occlusion x);
      if not (List.length conflicts_at = 0) then is_clean := false in
    if Superset_risg.G.mem_vertex insn_isg addr then
      Superset_risg.Dfs.prefix_component add_conflicts insn_isg addr;
    if !is_clean then total+1 else total
  in
  let num_bytes =
    let open Superset in 
    let segments = Table.to_sequence 
        Superset.(get_segments superset) in
    Seq.fold segments ~init:0 ~f:(fun len (mem, segment) ->
        if Image.Segment.is_executable segment then
          len + (Memory.length mem)
        else len
      ) in
  let entries = Superset_risg.entries_of_isg insn_risg in
  let branches = Grammar.linear_branch_sweep superset entries in
  let n = Hash_set.length branches in
  let tp_branches = 
    Hash_set.fold ~init:0 true_positives
      ~f:(fun tp_branches x -> 
          if Hash_set.mem branches x
          then tp_branches + 1 else tp_branches) in
  let fp_branches = n - tp_branches in
  printf "Num f.p. branches: %d, num tp branches: %d\n" fp_branches tp_branches;
  printf "superset_isg_of_mem length %d\n" num_bytes;
  let total_clean = Set.fold ground_truth ~init:0 ~f:
      dfs_find_conflicts in
  printf "Number of functions precisely trimmed: %d of %d\n"
    total_clean Set.(length ground_truth);
  (* TODO number of functions not directly referenced by an edge that *)
  (* are trimmed *)
  printf "Number of possible reduced false positives: %d\n" 
    Hash_set.(length data_bytes);
  printf "Reduced occlusion: %d\n" Hash_set.(length reduced_occlusion);
  printf "True positives: %d\n" Hash_set.(length true_positives);
  let detected_insns = 
    Superset_risg.G.fold_vertex 
      (fun vert detected_insns -> Set.add detected_insns vert) 
      insn_risg Addr.Set.empty in
  let missed_set = Set.diff ground_truth detected_insns in
  if not (Set.length missed_set = 0) then
    printf "Missed function entrances %s\n" 
      (List.to_string ~f:Addr.to_string @@ Set.to_list missed_set);
  printf "Occlusion: %d\n" 
    (Set.length @@ Superset_risg.find_all_conflicts insn_map);
  printf "Instruction fns: %d\n" (fn_insn_cnt superset true_positives);
  printf "superset_map length %d graph size: %d num edges %d\n" 
    Addr.Map.(length insn_map) 
    (Superset_risg.G.nb_vertex insn_risg)
    (Superset_risg.G.nb_edges insn_risg);
  let detected_entries =
    Set.(length (inter detected_insns ground_truth)) in
  let missed_entrances = Set.diff ground_truth detected_insns in
  let false_negatives =
    Set.(length (missed_entrances)) in
  let false_positives =
    Set.(length (diff detected_insns ground_truth)) in
  let detected_insn_count = Superset_risg.G.nb_vertex insn_risg in
  Some ({
      name                = bin;
      detected_insn_count = detected_insn_count;
      false_positives     = false_positives;
      false_negatives     = false_negatives;
      detected_entries    = detected_entries;
      actual_entries      = (Set.length ground_truth);
      trimmed             = [];
    })

module Opts = struct 
  open Cmdliner

  let list_content_doc = sprintf
      "Metrics may be collected against a symbol file"
  let content_type = 
    Arg.(value &
         opt (some string) (None)
         & info ["metrics_data"] ~doc:list_content_doc)

  let list_formats_types = [
    "standard", Standard;
    "latex", Latex;
  ]
  let list_formats_doc = sprintf
      "Available output metrics formats: %s" @@ 
    Arg.doc_alts_enum list_formats_types
  let metrics_format = 
    Arg.(value & opt (enum list_formats_types) Standard
         & info ["metrics_format"] ~doc:list_formats_doc)

end
