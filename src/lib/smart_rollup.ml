open Internal_pervasives

type mode = [ `Operator | `Batcher | `Observer | `Maintenance | `Accuser ]

type t = {
  id : string;
  level : int;
  custom_kernel : (string * string * string) option;
  node_mode : mode;
  node : Tezos_executable.t;
  client : Tezos_executable.t;
  installer : Tezos_executable.t;
}

let make_path ~state p = Paths.root state // sprintf "smart-rollup" // p

let make_dir state p =
  Running_processes.run_successful_cmdf state "mkdir -p %s" p

module Node = struct
  (* The mode of the smart-rollup node. *)

  let mode_string = function
    | `Operator -> "operator"
    | `Batcher -> "batcher"
    | `Observer -> "observer"
    | `Maintenance -> "maintenance"
    | `Accuser -> "accuser"

  (* A type for the smart-rollup node config. *)
  type config = {
    node_id : string;
    mode : mode;
    operator_addr : string;
    rpc_addr : string option;
    rpc_port : int option;
    endpoint : int option;
    protocol : Tezos_protocol.Protocol_kind.t;
    exec : Tezos_executable.t;
    client : Tezos_client.t;
    smart_rollup : t;
  }

  type t = config

  let make_config ~smart_rollup ?node_id ~mode ~operator_addr ?rpc_addr
      ?rpc_port ?endpoint ~protocol ~exec ~client () : config =
    let name =
      sprintf "%s-smart-rollup-%s-node-%s" smart_rollup.id (mode_string mode)
        (Option.value node_id ~default:"000")
    in
    {
      node_id = Option.value node_id ~default:name;
      mode;
      operator_addr;
      rpc_addr;
      rpc_port;
      endpoint;
      protocol;
      exec;
      client;
      smart_rollup;
    }

  (* smart-rollup node directory. *)
  let node_dir state node p = make_path ~state (sprintf "%s" node.node_id // p)
  let data_dir state node = node_dir state node "data-dir"
  let reveal_data_dir state node = data_dir state node // "wasm_2_0_0"

  (* octez-smart-rollup node command.*)
  let call state ~config command =
    let open Tezos_executable.Make_cli in
    let client_dir = Tezos_client.base_dir ~state config.client in
    Tezos_executable.call state config.exec ~protocol_kind:config.protocol
      ~path:(node_dir state config "exec")
      (Option.value_map config.endpoint ~default:[] ~f:(fun e ->
           opt "endpoint" (sprintf "http://localhost:%d" e))
      (* The base-dir is the octez_client directory. *)
      @ opt "base-dir" client_dir
      @ command
      (* The directory where the node config is stored. *)
      @ opt "data-dir" (data_dir state config)
      @ Option.value_map config.rpc_addr
          ~f:(fun a -> opt "rpc-addr" (sprintf "%s" a))
          ~default:[]
      @ Option.value_map config.rpc_port
          ~f:(fun p -> opt "rpc-port" (sprintf "%d" p))
          ~default:[])

  (* Command to initiate a smart-rollup node [config] *)
  let init state config soru_addr =
    call state ~config
      [
        "init";
        mode_string config.mode;
        "config";
        "for";
        soru_addr;
        "with";
        "operators";
        config.operator_addr;
      ]

  (* Start a running smart-rollup node. *)
  let start state config soru_addr =
    Running_processes.Process.genspio config.node_id
      (Genspio.EDSL.check_sequence ~verbosity:`Output_all
         [
           ("init smart-rollup node", init state config soru_addr);
           ("run smart-rollup node", call state ~config [ "run" ]);
         ])
end

module Kernel = struct
  type config = {
    name : string;
    installer_kernel : string;
    reveal_data_dir : string;
    kind : string;
    michelson_type : string;
    hex : string;
    exec : Tezos_executable.t;
    smart_rollup : t;
    node : Node.t;
  }

  (* smart-rollup kernel dirctory *)
  let kernel_dir ~state smart_rollup p =
    make_path ~state (sprintf "%s-kernel" smart_rollup.id // p)

  let make_config ?(kind = Tx_installer.kind)
      ?(michelson_type = Tx_installer.michelson_type) ?(hex = Tx_installer.hex)
      ~smart_rollup ~node state : config =
    let name = smart_rollup.id in
    let installer_kernel =
      kernel_dir ~state smart_rollup (sprintf "%s-installer.hex" name)
    in
    let reveal_data_dir = Node.reveal_data_dir state node in
    let exec = smart_rollup.installer in
    {
      name;
      installer_kernel;
      reveal_data_dir;
      kind;
      michelson_type;
      hex;
      exec;
      smart_rollup;
      node;
    }

  (* Write the tx-kernel files to the data reveal directory. *)
  let load_default_preimages state reveal_data_dir preimages =
    List_sequential.iter preimages ~f:(fun (p, content) ->
        let filename = Stdlib.Filename.basename p in
        System.write_file state (reveal_data_dir // filename) ~content)

  (* Check the extension of user provided kernel. *)
  let check_extension path =
    let open Stdlib.Filename in
    let ext = extension path in
    match ext with
    | ".hex" -> `Hex path
    | ".wasm" -> `Wasm path
    | _ -> raise (Invalid_argument (sprintf "Wrong file type at: %S" path))

  (* Build the installer_kernel and preimage with the smart_rollup_installer executable. *)
  let installer_create state ~exec ~path ~output ~preimages_dir =
    Running_processes.run_successful_cmdf state
      "%s get-reveal-installer --upgrade-to %s --output %s --preimages-dir %s"
      (Tezos_executable.kind_string exec)
      path output preimages_dir

  (* Build the kernel with the smart_rollup_installer executable. *)
  let build state ~smart_rollup ~node : (config, _) Asynchronous_result.t =
    let config = make_config state ~smart_rollup ~node in
    make_dir state (kernel_dir ~state smart_rollup "") >>= fun _ ->
    make_dir state config.reveal_data_dir >>= fun _ ->
    match smart_rollup.custom_kernel with
    | None ->
        load_default_preimages state config.reveal_data_dir Preimages.tx_kernel
        >>= fun _ -> return config
    | Some (kind, michelson_type, kernel_path) -> (
        System.size state kernel_path >>= fun s ->
        if s > 24 * 1048 then
          (* wasm files larger that 24kB are passed to installer_create. We can't do anything with large .hex files *)
          match check_extension kernel_path with
          | `Hex p ->
              raise
                (Invalid_argument
                   (sprintf
                      "%s is over the max operation size (24kB). Try a .wasm \
                       file \n"
                      p))
          | `Wasm _ ->
              installer_create state ~exec:config.exec.kind ~path:kernel_path
                ~output:config.installer_kernel
                ~preimages_dir:config.reveal_data_dir
              >>= fun _ ->
              System.read_file state config.installer_kernel >>= fun hex ->
              return { config with kind; michelson_type; hex }
        else
          match check_extension kernel_path with
          | `Hex p ->
              System.read_file state p >>= fun hex ->
              return { config with kind; michelson_type; hex }
          | `Wasm p ->
              System.read_file state p >>= fun was ->
              let hex = Hex.(was |> of_string |> show) in
              return { config with kind; michelson_type; hex })
end

(* octez-client call to originate a smart-rollup. *)
let originate state ~client ~account ~kernel () =
  let open Kernel in
  Tezos_client.successful_client_cmd state ~client
    [
      "originate";
      "smart";
      "rollup";
      kernel.name;
      "from";
      account;
      "of";
      "kind";
      kernel.kind;
      "of";
      "type";
      kernel.michelson_type;
      "with";
      "kernel";
      kernel.hex;
      "--burn-cap";
      "999";
    ]

(* octez-client call confirming an operation. *)
let confirm state ~client ~confirmations ~operation_hash () =
  Tezos_client.successful_client_cmd state ~client
    [
      "wait";
      "for";
      operation_hash;
      "to";
      "be";
      "included";
      "--confirmations";
      Int.to_string confirmations;
    ]

(* A type for octez client output from a smart-rollup origination. *)
type origination_result = {
  operation_hash : string;
  address : string;
  origination_account : string;
  out : string list;
}

(* Parse octez-client output of smart-rollup origination. *)
let parse_origination ~lines =
  let rec prefix_from_list ~prefix = function
    | [] -> None
    | x :: xs ->
        if not (String.is_prefix x ~prefix) then prefix_from_list ~prefix xs
        else
          Some
            (String.lstrip
               (String.chop_prefix x ~prefix |> Option.value ~default:x))
  in
  let l = List.map lines ~f:String.lstrip in
  (* This is parsing the unicode output from the octez-client *)
  Option.(
    prefix_from_list ~prefix:"Operation hash is" l >>= fun op ->
    String.chop_prefix ~prefix:"'" op >>= fun suf ->
    String.chop_suffix ~suffix:"'" suf >>= fun operation_hash ->
    prefix_from_list ~prefix:"From:" l >>= fun origination_account ->
    prefix_from_list ~prefix:"Address:" l >>= fun address ->
    return { operation_hash; address; origination_account; out = lines })

let originate_and_confirm state ~client ~account ~kernel ~confirmations () =
  originate state ~client ~account ~kernel () >>= fun res ->
  return (parse_origination ~lines:res#out) >>= fun origination_result ->
  match origination_result with
  | None ->
      System_error.fail_fatalf
        "smart_rollup.originate_and_confirm - failed to parse output."
  | Some origination_result ->
      confirm state ~client ~confirmations
        ~operation_hash:origination_result.operation_hash ()
      >>= fun conf -> return (origination_result, conf)

(* A list of smart rollup executables. *)
let executables ({ client; node; installer; _ } : t) =
  [ client; node; installer ]

let run state ~smart_rollup ~protocol ~keys_and_daemons ~nodes ~base_port =
  match smart_rollup with
  | None -> return ()
  | Some soru -> (
      List.hd keys_and_daemons |> function
      | None -> return ()
      | Some (_, _, client, _, _) ->
          (* Initialize operator keys. *)
          let op_acc = Tezos_protocol.soru_node_operator protocol in
          let op_keys =
            let name, priv =
              Tezos_protocol.Account.(name op_acc, private_key op_acc)
            in
            Tezos_client.Keyed.make client ~key_name:name ~secret_key:priv
          in
          Tezos_client.Keyed.initialize state op_keys >>= fun _ ->
          (* Configure smart-rollup node. *)
          let port = Test_scenario.Unix_port.(next_port nodes) in
          Node.make_config ~smart_rollup:soru ~mode:soru.node_mode
            ~operator_addr:op_keys.key_name ~rpc_addr:"0.0.0.0" ~rpc_port:port
            ~endpoint:base_port ~protocol:protocol.kind ~exec:soru.node ~client
            ()
          |> return
          >>= fun soru_node ->
          (* Configure custom Kernel or use default if none. *)
          Kernel.build state ~smart_rollup:soru ~node:soru_node
          >>= fun kernel ->
          (* Originate smart-rollup.*)
          originate_and_confirm state ~client ~kernel ~account:op_keys.key_name
            ~confirmations:1 ()
          >>= fun (origination_res, _confirmation_res) ->
          (* Start smart-rollup node. *)
          Running_processes.start state
            Node.(start state soru_node origination_res.address)
          >>= fun _ ->
          (* Print smart-rollup info. *)
          Console.say state
            EF.(
              desc_list
                (haf "%S smart optimistic rollup is ready:" soru.id)
                [
                  desc (af "Address:") (af "`%s`" origination_res.address);
                  desc
                    (af "A rollup node in %S mode is listening on"
                       (Node.mode_string soru_node.mode))
                    (af "rpc_port: `%d`"
                       (Option.value_exn
                          ?message:
                            (Some
                               "Failed to get rpc port for Smart rollup node.")
                          soru_node.rpc_port));
                ]))

let cmdliner_term state () =
  let open Cmdliner in
  let open Term in
  let docs =
    Manpage_builder.section state ~rank:2 ~name:"SMART OPTIMISTIC ROLLUPS"
  in
  let extra_doc =
    Fmt.str " for the smart optimistic rollup (requires --smart-rollup)."
  in
  const (fun soru level custom_kernel node_mode node client installer ->
      match soru with
      | true ->
          let id =
            match custom_kernel with
            | None -> Tx_installer.name
            | Some (_, _, p) -> (
                match Kernel.check_extension p with
                | `Hex p | `Wasm p ->
                    Stdlib.Filename.(basename p |> chop_extension))
          in
          Some { id; level; custom_kernel; node_mode; node; client; installer }
      | false -> None)
  $ Arg.(
      value
      & flag
          (info [ "smart-rollup" ]
             ~doc:
               "Start the Flextexa mini-network with a smart optimistic \
                rollup. By default this will be the transction smart rollup \
                (TX-kernel). See `--custom-kernel` for other options."
             ~docs))
  $ Arg.(
      value
      & opt int 5
          (info
             [ "smart-rollup-start-level" ]
             ~doc:(sprintf "Origination `level` %s" extra_doc)
             ~docs ~docv:"LEVEL"))
  $ Arg.(
      value
      & opt (some (t3 ~sep:':' string string string)) None
      & info [ "custom-kernel" ] ~docs
          ~doc:
            (sprintf
               "Originate a smart rollup of KIND and of TYPE with PATH to a \
                custom kernel %s"
               extra_doc)
          ~docv:"KIND:TYPE:PATH")
  $ Arg.(
      value
      & opt
          (enum
             [
               ("operator", `Operator);
               ("batcher", `Batcher);
               ("observer", `Observer);
               ("maintenance", `Maintenance);
               ("accuser", `Accuser);
             ])
          `Operator
      & info ~docs
          [ "smart-rollup-node-mode" ]
          ~doc:(sprintf "Set the rollup node's `mode`%s" extra_doc))
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_node
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_client
      ~prefix:"octez"
  $ Tezos_executable.cli_term ~extra_doc state `Smart_rollup_installer
      ~prefix:"octez"
