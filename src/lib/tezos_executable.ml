open Internal_pervasives

module Make_cli = struct
  let flag name = [ sprintf "--%s" name ]
  let opt name s = [ sprintf "--%s" name; s ]
  let optf name fmt = ksprintf (opt name) fmt
end

module Unix_files_sink = struct
  type t = { matches : string list option; level_at_least : string }

  let all_at_least level_at_least = { matches = None; level_at_least }
  let all_notices = all_at_least "notice"
  let all_info = all_at_least "info"
end

type kind =
  [ `Node
  | `Baker
  | `Endorser
  | `Accuser
  | `Client
  | `Admin
  | `Smart_rollup_node
  | `Smart_rollup_client
  | `Smart_rollup_installer ]

type t = {
  kind : kind;
  binary : string option;
  unix_files_sink : Unix_files_sink.t option;
  environment : (string * string) list;
}

let make ?binary ?unix_files_sink ?(environment = []) (kind : [< kind ]) =
  { kind; binary; unix_files_sink; environment }

let kind_string (kind : [< kind ]) =
  match kind with
  | `Accuser -> "accuser"
  | `Baker -> "baker"
  | `Endorser -> "endorser"
  | `Node -> "node"
  | `Client -> "client"
  | `Admin -> "admin-client"
  | `Smart_rollup_node -> "smart-rollup-node"
  | `Smart_rollup_client -> "smart-rollup-client"
  | `Smart_rollup_installer -> "smart-rollup-installer"

let default_binary ?protocol_kind t =
  let base_name kind = kind_string kind in
  let proto_suffix proto s =
    Fmt.str "%s-%s" s (Tezos_protocol.Protocol_kind.daemon_suffix_exn proto)
  in
  let octez_prefix s = Fmt.str "octez-%s" s in
  match (t.kind, protocol_kind) with
  | ( (`Accuser | `Baker | `Endorser | `Smart_rollup_node | `Smart_rollup_client),
      Some proto ) ->
      base_name t.kind |> proto_suffix proto |> octez_prefix
  | (`Node | `Client | `Admin), _ -> base_name t.kind |> octez_prefix
  | ( (`Accuser | `Baker | `Endorser | `Smart_rollup_node | `Smart_rollup_client),
      _ ) ->
      Fmt.failwith
        "Called default_binary with for octez-%s and protocol_kind = None"
        (kind_string t.kind)
  | `Smart_rollup_installer, _ -> base_name t.kind

let get ?protocol_kind t =
  match t.binary with Some s -> s | None -> default_binary ?protocol_kind t

let call state t ?protocol_kind ~path args =
  let open Genspio.EDSL in
  let unix_files_sink =
    match t.unix_files_sink with
    | Some s -> Some s
    | None ->
        Environment_configuration.default_events_level state
        |> Option.map ~f:Unix_files_sink.all_at_least
  in
  seq
    (Option.value_map unix_files_sink ~default:[] ~f:(function
       | { matches = None; level_at_least } ->
           [
             setenv
               ~var:(str "TEZOS_EVENTS_CONFIG")
               (ksprintf str "unix-files://%s?level-at-least=%s"
                  (path // "events") level_at_least);
           ]
       | _other -> assert false)
    @ [
        exec [ "mkdir"; "-p"; path ];
        write_stdout
          ~path:(path // "last-cmd" |> str)
          (printf (str "ARGS: %s\\n") [ str (String.concat ~sep:" " args) ]);
        exec (get ?protocol_kind t :: args);
      ])

let cli_term ?(extra_doc = "") ?prefix state kind =
  let open Cmdliner in
  let open Term in
  let pfx = match prefix with Some s -> sprintf "%s-" s | None -> "" in
  let docs = Manpage_builder.section state ~rank:2 ~name:"EXECUTABLE PATHS" in
  pure (fun binary ->
      { kind; binary; unix_files_sink = None; environment = [] })
  $ Arg.(
      value
      & opt (some string) None
      & info ~docs
          [ sprintf "%s%s-binary" pfx (kind_string kind) ]
          ~doc:
            (sprintf "Binary for the `octez-%s` to use%s." (kind_string kind)
               extra_doc))
  [@@warning "-3"]
