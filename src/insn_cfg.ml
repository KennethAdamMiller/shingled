open Bap.Std
open Graph
open Core_kernel.Std

module G = Imperative.Digraph.ConcreteBidirectional(struct 
    type t = Addr.t 
    let compare = Addr.compare
    let hash = Addr.hash
    let equal = Addr.equal
  end)
type t = G.t

module Oper = Oper.I(G)
module StrongComponents = Components.Make(G)
module DiscreteComponents = Components.Undirected(G)
module Dfs        = Traverse.Dfs(G)
module Path       = Path.Check(G)
module Gml        = Gml.Print(G)(struct 
    let node (label : G.V.label) = 
      [ "addr", Gml.String (Addr.to_string label)  ]
    let edge (label : G.E.label) = [ ]
  end)

let bad_of_arch arch = 
  G.V.create (Addr.of_int
                ~width:(Size.in_bits @@ Arch.addr_size arch) 0)

let bad_of_addr addr =
  G.V.create (Addr.of_int
                ~width:(Addr.bitwidth addr) 0)

let conflicts_within_insn_at ?conflicts insn_map addr =
  let conflicts = Option.value conflicts ~default:Addr.Set.empty in
  let rec within_insn conflicts insn_map cur_addr len =
    if Addr.(cur_addr >= (addr ++ len)) then
      conflicts
    else
      let conflicts = if Map.mem insn_map cur_addr then
          Set.add conflicts cur_addr
        else conflicts in 
      within_insn conflicts insn_map Addr.(cur_addr ++ 1) len in
  match Map.find insn_map addr with
  | Some ((mem, _)) ->
    (* look within the body for instructions *)
    let len = (Memory.length mem) in
    within_insn conflicts insn_map Addr.(addr ++ 1) len
  | None -> conflicts

let find_all_conflicts insn_map insn_cfg =
  Addr.Map.fold ~init:Addr.Set.empty
    ~f:(fun ~key ~data conflicts -> 
        let insn_addr = key in
        conflicts_within_insn_at ~conflicts insn_map insn_addr
      ) insn_map

let seq_of_addr_range addr len = 
  let open Seq.Generator in
  let rec gen_next_addr cur_addr = 
    if Addr.(cur_addr >= (addr ++ len)) then
      return ()
    else
      yield cur_addr >>=  fun () -> 
      let next_addr = Addr.succ cur_addr in
      gen_next_addr next_addr
  in run (gen_next_addr addr)

let range_seq_of_conflicts insn_map addr len = 
  let range_seq = seq_of_addr_range Addr.(succ addr) len in
  Seq.filter range_seq ~f:Addr.Map.(mem insn_map)
