open Internal_pervasives

type args =
  | Baker : string -> args
  | Endorser : string -> args
  | Accuser : args

type ai_vote = [ `On | `Off | `Pass ]

type t = {
  node : Tezos_node.t;
  client : Tezos_client.t;
  exec : Tezos_executable.t;
  protocol_kind : Tezos_protocol.Protocol_kind.t;
  args : args;
  name_tag : string option;
  adaptive_issuance : ai_vote;
}

let of_node ?(adaptive_issuance = `Pass) ?name_tag node args ~protocol_kind
    ~exec ~client =
  { node; exec; client; args; name_tag; protocol_kind; adaptive_issuance }

let baker_of_node ?name_tag nod ~key ~adaptive_issuance =
  of_node nod ~adaptive_issuance ?name_tag (Baker key)

let endorser_of_node ?name_tag nod ~key = of_node nod ?name_tag (Endorser key)
let accuser_of_node ?name_tag nod = of_node ?name_tag nod Accuser

let arg_to_string = function
  | Baker k -> sprintf "baker-%s" k
  | Endorser k -> sprintf "endorser-%s" k
  | Accuser -> "accuser"

let to_script state (t : t) =
  let base_dir = Tezos_client.base_dir ~state t.client in
  let call t args =
    Tezos_executable.call state t.exec ~protocol_kind:t.protocol_kind
      ~path:
        (base_dir
        // sprintf "exec-%s-%d%s" (arg_to_string t.args)
             t.node.Tezos_node.rpc_port
             (Option.value_map t.name_tag ~default:"" ~f:(sprintf "-%s")))
      args
  in
  match t.args with
  | Baker key ->
      let node_path = Tezos_node.data_dir state t.node in
      let ai =
        [
          "--adaptive-issuance-vote";
          (function `On -> "on" | `Off -> "off" | `Pass -> "pass")
            t.adaptive_issuance;
        ]
      in
      let lb = [ "--liquidity-baking-toggle-vote"; "pass" ] in
      let extra_options =
        match t.protocol_kind with
        | `Oxford | `Alpha -> ai @ lb
        | `Jakarta | `Kathmandu | `Lima | `Mumbai | `Nairobi -> lb
        | `Florence | `Carthage | `Delphi | `Ithaca | `Hangzhou | `Babylon
        | `Edo | `Granada | `Athens ->
            []
      in
      call t
        ([
           "--endpoint";
           sprintf "http://localhost:%d" t.node.Tezos_node.rpc_port;
           "--base-dir";
           base_dir;
           "run";
           "with";
           "local";
           "node";
           node_path;
           key;
         ]
        @ extra_options)
  | Endorser key ->
      call t
        [
          "--endpoint";
          sprintf "http://localhost:%d" t.node.Tezos_node.rpc_port;
          "--base-dir";
          base_dir;
          "run";
          key;
        ]
  | Accuser ->
      call t
        [
          "--endpoint";
          sprintf "http://localhost:%d" t.node.Tezos_node.rpc_port;
          "--base-dir";
          base_dir;
          "run";
          "--preserved-levels";
          "10";
        ]

let process state (t : t) =
  Running_processes.Process.genspio
    (sprintf "%s-for-%s%s" (arg_to_string t.args) t.node.Tezos_node.id
       (Option.value_map t.name_tag ~default:"" ~f:(sprintf "-%s")))
    (to_script state t)
