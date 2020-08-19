open Internal_pervasives

module Michelson = struct
  let prepare_origination_of_id_script ?delegate ?(push_drops = 0)
      ?(amount = "2") state ~name ~from ~protocol_kind ~parameter ~init_storage
      =
    let id_script parameter =
      Fmt.strf
        "parameter %s;\n\
         storage %s;\n\
         code\n\
        \  {\n\
        \    %s\n\
        \    { CAR; NIL operation; PAIR }\n\
        \  };\n"
        parameter parameter
        ( match push_drops with
        | 0 -> "# No push-drops"
        | n ->
            Fmt.strf "# %d push-drop%s\n    %s" n
              (if n > 1 then "s" else "")
              ( List.init push_drops ~f:(fun ith ->
                    Fmt.strf "{ PUSH string %S ; DROP } ;"
                      (Fmt.strf
                         "push-dropping %d adds stupid bytes to the contract"
                         ith))
              |> String.concat ~sep:"\n    " ) ) in
    let tmp = Caml.Filename.temp_file "little-id-script" ".tz" in
    System.write_file state tmp ~content:(id_script parameter)
    >>= fun () ->
    Dbg.e EF.(wf "id_script %s: %s" parameter tmp) ;
    let origination =
      let opt = Option.value_map ~default:[] in
      ["--wait"; "none"; "originate"; "contract"; name]
      @ ( match protocol_kind with
        | `Athens -> ["for"; from]
        | `Carthage | `Babylon -> [] )
      @ [ "transferring"; amount; "from"; from; "running"; tmp; "--init"
        ; init_storage; "--force"; "--burn-cap"; "300000000000"
        ; (* ; "--fee-cap" ; "20000000000000" *) "--gas-limit"
        ; "1000000000000000"; "--storage-limit"; "20000000000000"
        ; "--verbose-signing" ]
      @ opt delegate ~f:(fun s -> (* Baby & Aths *) ["--delegate"; s]) in
    return origination
end

module Forge = struct
  let batch_transfer
      ?(protocol_kind : Tezos_protocol.Protocol_kind.t = `Babylon)
      ?(counter = 0) ?(dst = [("tz2KZPgf2rshxNUBXFcTaCemik1LH1v9qz3F", 1)])
      ~src ~fee ~branch n : Ezjsonm.value =
    let open Ezjsonm in
    ignore protocol_kind ;
    dict
      [ ("branch", `String branch)
      ; ( "contents"
        , `A
            (List.map (List.range 0 n) ~f:(fun i ->
                 let dest, amount = List.nth_exn dst (i % List.length dst) in
                 `O
                   [ ("kind", `String "transaction")
                   ; ("source", `String src)
                   ; ("destination", `String dest)
                   ; ("amount", `String (Int.to_string amount))
                   ; ( "fee"
                     , `String (Int.to_string (Float.to_int (fee *. 1000000.)))
                     )
                   ; ("counter", `String (Int.to_string (counter + i)))
                   ; ("gas_limit", `String (Int.to_string 127))
                   ; ("storage_limit", `String (Int.to_string 277)) ])) ) ]

  let endorsement ?(protocol_kind : Tezos_protocol.Protocol_kind.t = `Babylon)
      ~branch level : Ezjsonm.value =
    let open Ezjsonm in
    ignore protocol_kind ;
    dict
      [ ("branch", `String branch)
      ; ( "contents"
        , `A [`O [("kind", `String "endorsement"); ("level", int level)]] ) ]
end

module Multisig = struct
  let signer_names_base =
    [ "Alice"; "Bob"; "Charlie"; "David"; "Elsa"; "Frank"; "Gail"; "Harry"
    ; "Ivan"; "Jane"; "Iris"; "Jackie"; "Linda"; "Mary"; "Nemo"; "Opal"; "Paul"
    ; "Quincy"; "Rhonda"; "Steve"; "Theodore"; "Uma"; "Venus"; "Wimpy"
    ; "Xaviar"; "Yuri"; "Zed" ]

  let get_signer_names signers n =
    let k = List.length signers in
    let rec append = function 0 -> signers | x -> signers @ append (x - 1) in
    let suffix = function 0 -> "" | n -> "-" ^ Int.to_string (n + 1) in
    let fold_f ((xs, i) : string list * int) (x : string) : string list * int =
      let fst = List.cons (x ^ suffix (i / k)) xs in
      (fst, i + 1) in
    let big_list = List.take (append (n / k)) n in
    let result, _ = List.fold big_list ~init:([], 0) ~f:fold_f in
    List.rev result

  let deploy_and_transfer state client nodes ~num_signers ~outer_repeat
      ~contract_repeat =
    let signer_names_plus = get_signer_names signer_names_base num_signers in
    (*loop through batch size *)
    Loop.n_times outer_repeat (fun n ->
        (* generate and import keys *)
        let signer_names = List.take signer_names_plus num_signers in
        Helpers.import_keys_from_seeds state client ~seeds:signer_names
        (* deploy the multisig contract *)
        >>= fun _ ->
        Test_scenario.Queries.wait_for_bake state ~nodes
        (* required to avoid "counter" errors *)
        >>= fun () ->
        let multisig_name = "msig-" ^ Int.to_string n in
        Tezos_client.deploy_multisig state client ~name:multisig_name
          ~amt:100.0 ~from_acct:"bootacc-0" ~threshold:num_signers
          ~signer_names ~burn_cap:100.0
        >>= fun () ->
        Test_scenario.Queries.wait_for_bake state ~nodes
        >>= fun () ->
        (* for each signer, sign the contract *)
        let m_sigs =
          List.map signer_names ~f:(fun s ->
              Tezos_client.sign_multisig state client ~name:multisig_name
                ~amt:100.0 ~to_acct:"Bob" ~signer_name:s) in
        Asynchronous_result.all m_sigs
        >>= fun signatures ->
        (* submit the fully signed multisig contract *)
        Loop.n_times contract_repeat (fun k ->
            Tezos_client.transfer_from_multisig state client
              ~name:multisig_name ~amt:100.0 ~to_acct:"Bob"
              ~on_behalf_acct:"bootacc-0" ~signatures ~burn_cap:100.0
            >>= fun () ->
            Console.say state
              EF.(
                desc
                  (haf "Multi-sig contract generation")
                  (af "Fully signed contract %s (%n) submitted" multisig_name k))))
end

module Random = struct
  let run state ~protocol ~nodes ~clients ~until_level kind =
    assert (Poly.equal kind `Any) ;
    let tbb =
      protocol.Tezos_protocol.time_between_blocks |> List.hd
      |> Option.value ~default:10 in
    let info fmt =
      Fmt.kstr
        (fun s ->
          Console.sayf state Fmt.(fun ppf () -> pf ppf "Randomizer: %s" s))
        fmt in
    let from = "bootacc-0" in
    let client = List.hd_exn clients in
    let pp_success ppf = function
      | true -> Fmt.pf ppf "Success"
      | false -> Fmt.pf ppf "Failure" in
    let valid_contracts = ref [] in
    let rec loop iteration =
      let client_cmd name l =
        Tezos_client.client_cmd ~verbose:false state ~client
          ~id_prefix:(Fmt.str "randomizer-%04d-%s" iteration name)
          l in
      let continue_or_not () =
        Test_scenario.Queries.all_levels state ~nodes
        >>= fun all_levels ->
        if
          List.for_all all_levels ~f:(function
            | _, `Level l when l >= until_level -> true
            | _ -> false)
        then info "Max-level reached: %d" until_level
        else loop (iteration + 1) in
      List.random_element
        [`Sleep; `Add_contract; `Call_contract; `Multisig_contract]
      |> function
      | Some `Sleep ->
          let secs =
            Float.(Random.float_range (of_int tbb * 0.3) (of_int tbb * 1.5))
          in
          info "Sleeping %.2f seconds." secs
          >>= fun () -> System.sleep secs >>= fun () -> continue_or_not ()
      | Some `Call_contract ->
          ( match List.random_element !valid_contracts with
          | None -> info "No valid contracts to call."
          | Some (name, params) ->
              client_cmd
                (Fmt.str "transfer-%s" name)
                ["transfer"; "1"; "from"; from; "to"; name; "--arg"; params]
              >>= fun (success, _) ->
              info "Called %s(%s): %a" name params pp_success success )
          >>= fun () -> continue_or_not ()
      | Some `Add_contract ->
          let name = Fmt.str "contract-%d" iteration in
          let push_drops = Random.int 100 in
          let parameter, init_storage =
            match List.random_element [`Unit; `String] with
            | Some `String ->
                ( "string"
                , Fmt.str "%S"
                    (String.init
                       (Random.int 42 + 1)
                       ~f:(fun _ -> Random.int 20 + 40 |> Char.of_int_exn)) )
            | _ -> ("unit", "Unit") in
          Michelson.prepare_origination_of_id_script state ~name ~from
            ~protocol_kind:protocol.Tezos_protocol.kind ~parameter
            ~init_storage ~push_drops
          >>= fun origination ->
          client_cmd (Fmt.str "originate-%s" name) origination
          >>= fun (success, _) ->
          if success then
            valid_contracts := (name, init_storage) :: !valid_contracts ;
          info "Origination of `%s` (%s : %s): `%a`." name init_storage
            parameter pp_success success
          >>= fun () -> continue_or_not ()
      | Some `Multisig_contract ->
          let num_signers = Random.int 5 + 1 in
          let outer_repeat = Random.int 5 + 1 in
          let contract_repeat = Random.int 5 + 1 in
          Multisig.deploy_and_transfer state client nodes ~num_signers
            ~outer_repeat ~contract_repeat
          >>= fun () -> continue_or_not ()
      | None -> continue_or_not () in
    loop 0
end

module Commands = struct
  let cmdline_fail fmt = Fmt.kstr (fun s -> fail (`Command_line s)) fmt

  let protect_with_keyed_client msg ~client ~f =
    let msg =
      Fmt.str "Command-line %s with client %s (account: %s)" msg
        client.Tezos_client.Keyed.client.id client.Tezos_client.Keyed.key_name
    in
    Asynchronous_result.bind_on_error (f ()) ~f:(fun ~result:_ ->
      function
      | #Process_result.Error.t as e ->
          cmdline_fail "%s -> Error: %a" msg Process_result.Error.pp e
      | #System_error.t as e ->
          cmdline_fail "%s -> Error: %a" msg System_error.pp e
      | `Waiting_for (msg, `Time_out) ->
          cmdline_fail "WAITING-FOR “%s”: Time-out" msg
      | `Command_line _ as e -> fail e)

  module Sexp_options = struct
    type t = {name: string; placeholders: string list; description: string}
    type option = t

    let make_option name ?(placeholders = []) description =
      {name; placeholders; description}

    let pp_options l ppf () =
      let open More_fmt in
      vertical_box ~indent:2 ppf (fun ppf ->
          pf ppf "Options:" ;
          List.iter l ~f:(fun {name; placeholders; description} ->
              cut ppf () ;
              wrapping_box ~indent:2 ppf (fun ppf ->
                  let opt_ex ppf () =
                    prompt ppf (fun ppf ->
                        pf ppf "%s%s" name
                          ( if Poly.equal placeholders [] then ""
                          else
                            List.map ~f:(str " %s") placeholders
                            |> String.concat ~sep:"" )) in
                  pf ppf "* %a  %a" opt_ex () text description)))

    let find opt sexps f =
      List.find_map sexps
        ~f:
          Sexp.(
            function
            | List (Atom a :: more)
              when String.equal a opt.name
                   && Int.(List.length more = List.length opt.placeholders) ->
                Some (f more)
            | _ -> None)

    let find_new opt sexps g =
      let sub_list =
        List.drop_while sexps ~f:(function
          | Sexp.Atom a when String.equal a opt.name -> false
          | _ -> true) in
      match sub_list with
      | Sexp.Atom _ :: Sexp.Atom o :: _ -> Some (g [Sexp.Atom o])
      | _ -> None

    let get opt sexps ~default ~f =
      match find_new opt sexps f with
      | Some n -> return n
      | None -> (
        match find opt sexps f with Some n -> return n | None -> default () )
      | exception e -> cmdline_fail "Getting option %s: %a" opt.name Exn.pp e

    let get_int_exn = function
      | Sexp.[Atom a] -> (
        try Int.of_string a with _ -> Fmt.failwith "%S is not an integer" a )
      | other -> Fmt.failwith "wrong structure: %a" Sexp.pp (Sexp.List other)

    let get_float_exn = function
      | Sexp.[Atom a] -> (
        try Float.of_string a with _ -> Fmt.failwith "%S is not a float" a )
      | other -> Fmt.failwith "wrong structure: %a" Sexp.pp (Sexp.List other)

    let port_number_doc _ ~default_port =
      make_option "port" ~placeholders:["<int>"]
        Fmt.(str "Use port number <int> instead of %d (default)." default_port)

    let port_number _state ~default_port sexps =
      match
        List.find_map sexps
          ~f:
            Base.Sexp.(
              function
              | List [Atom "port"; Atom p] -> (
                try Some (`Ok (Int.of_string p))
                with _ -> Some (`Not_an_int p) )
              | List (Atom "port" :: _ as other) -> Some (`Wrong_option other)
              | _other -> None)
      with
      | None -> return default_port
      | Some (`Ok p) -> return p
      | Some ((`Not_an_int _ | `Wrong_option _) as other) ->
          let problem =
            match other with
            | `Not_an_int s -> Fmt.str "This is not an integer: %S." s
            | `Wrong_option s ->
                Fmt.str "Usage is (port <int>), too many arguments here: %s."
                  Base.Sexp.(to_string_hum (List s)) in
          fail (`Command_line "Error parsing (port ...) option")
            ~attach:[("Problem", `Text problem)]

    let rec fmt_sexp sexp =
      Base.Sexp.(
        match sexp with
        | Atom a -> "Atom:" ^ "\"" ^ a ^ "\""
        | Sexp.List xs ->
            let prefix = "Sexp.List [" ^ fmt_sexps xs in
            String.drop_suffix prefix 2 ^ "]")

    and fmt_sexps xs =
      match xs with [] -> "" | x :: xs -> fmt_sexp x ^ "; " ^ fmt_sexps xs
  end

  type all_options =
    { counter_option: Sexp_options.option
    ; size_option: Sexp_options.option
    ; fee_option: Sexp_options.option
    ; num_signers_option: Sexp_options.option
    ; contract_repeat_option: Sexp_options.option }

  type batch_action = {src: string; counter: int; size: int; fee: float}

  type multisig_action =
    {num_signers: int; outer_repeat: int; contract_repeat: int}

  type action =
    [`Batch_action of batch_action | `Multisig_action of multisig_action]

  let counter_option =
    Sexp_options.make_option ":counter" ~placeholders:["<int>"]
      "The counter to provide (get it from the node by default)."

  let size_option =
    Sexp_options.make_option ":size" ~placeholders:["<int>"]
      "The batch size (default: 10)."

  let fee_option =
    Sexp_options.make_option ":fee" ~placeholders:["<float-tz>"]
      "The fee per operation (default: 0.02)."

  let level_option =
    Sexp_options.make_option ":level" ~placeholders:["<int>"] "The level."

  let contract_repeat_option =
    Sexp_options.make_option ":operation-repeat" ~placeholders:["<int>"]
      "The number of repeated calls to execute the fully-signed multi-sig \
       contract (default: 1)."

  let num_signers_option =
    Sexp_options.make_option ":num-signers" ~placeholders:["<int>"]
      "The number of signers required for the multi-sig contract (default: 3)."

  let repeat_all_option =
    Sexp_options.make_option "repeat"
      ~placeholders:[":times"; "<int>"; "<list of commands>"]
      "The number of times to repeat any dsl commands that follow (default: 1)."

  let random_choice_option =
    Sexp_options.make_option "random-choice"
      ~placeholders:["<list of commands>"]
      "Randomly chose a command from a list of dsl commands."

  let all_opts : all_options =
    { counter_option
    ; size_option
    ; fee_option
    ; num_signers_option
    ; contract_repeat_option }

  let branch state client =
    Tezos_client.rpc state ~client:client.Tezos_client.Keyed.client `Get
      ~path:"/chains/main/blocks/head/hash"
    >>= fun br ->
    let branch = Jqo.get_string br in
    return branch

  let get_batch_args state ~client opts more_args =
    protect_with_keyed_client "generate batch" ~client ~f:(fun () ->
        let src =
          client.key_name |> Tezos_protocol.Account.of_name
          |> Tezos_protocol.Account.pubkey_hash in
        Sexp_options.get opts.counter_option more_args
          ~f:Sexp_options.get_int_exn ~default:(fun () ->
            Tezos_client.rpc state ~client:client.client `Get
              ~path:
                (Fmt.str
                   "/chains/main/blocks/head/context/contracts/%s/counter" src)
            >>= fun counter_json ->
            return ((Jqo.get_string counter_json |> Int.of_string) + 1))
        >>= fun counter ->
        Sexp_options.get opts.size_option more_args ~f:Sexp_options.get_int_exn
          ~default:(fun () -> return 10)
        >>= fun size ->
        Sexp_options.get opts.fee_option more_args
          ~f:Sexp_options.get_float_exn ~default:(fun () -> return 0.02)
        >>= fun fee -> return (`Batch_action {src; counter; size; fee}))

  let get_multisig_args opts (more_args : Sexp.t list) =
    Sexp_options.get opts.size_option more_args ~f:Sexp_options.get_int_exn
      ~default:(fun () -> return 10)
    >>= fun outer_repeat ->
    Sexp_options.get opts.contract_repeat_option more_args
      ~f:Sexp_options.get_int_exn ~default:(fun () -> return 1)
    >>= fun contract_repeat ->
    Sexp_options.get opts.num_signers_option more_args
      ~f:Sexp_options.get_int_exn ~default:(fun () -> return 3)
    >>= fun num_signers ->
    return (`Multisig_action {num_signers; outer_repeat; contract_repeat})

  let to_action state ~client opts sexp =
    match sexp with
    | Sexp.List (Atom "batch" :: more_args) ->
        get_batch_args state ~client opts more_args
    | Sexp.List (Atom "multisig-batch" :: more_args) ->
        get_multisig_args opts more_args
    | Sexp.List (Atom a :: _) ->
        Fmt.kstr failwith "to_action - unexpected atom inside list: %s" a
    | Sexp.List z ->
        Fmt.kstr failwith "to_action - unexpected list. %s"
          (Sexp.to_string (List z))
    | Sexp.Atom b -> Fmt.kstr failwith "to_action - unexpected atom. %s" b

  let process_repeat_action sexp =
    match sexp with
    | Sexp.List (y :: _) -> (
      match y with
      | Sexp.List (Atom "repeat" :: Atom ":times" :: Atom n :: more_args) ->
          let c = Int.of_string n in
          let count = if c <= 0 then 1 else c in
          (count, Sexp.List more_args)
      | _ -> (1, sexp) )
    | _ -> (1, sexp)

  let process_random_choice sexp =
    match sexp with
    | Sexp.List (y :: _) -> (
      match y with
      | Sexp.List (Atom "random-choice" :: more_args) ->
          (true, Sexp.List more_args)
      | _ -> (false, sexp) )
    | other ->
        Fmt.kstr failwith
          "process_random_choice - expecting a list but got - from pp: %a, \
           from fmt_sexp: %s, from Sexp.to_string: %s"
          Sexp.pp other
          (Sexp_options.fmt_sexp other)
          (Sexp.to_string other)

  let process_action_cmds state ~client opts sexp ~random_choice =
    let rec loop (actions : action list) (exps : Base.Sexp.t list) =
      match exps with
      | [x] -> to_action state ~client opts x >>= fun a -> return (a :: actions)
      | x :: xs ->
          to_action state ~client opts x >>= fun a -> loop (a :: actions) xs
      | other ->
          Fmt.kstr failwith "process_action_cmds - something weird: %a" Sexp.pp
            (List other) in
    let exp_list =
      match sexp with
      | Sexp.List (y :: _) -> (
        match y with
        | Sexp.List z -> z
        | other ->
            Fmt.kstr failwith
              "process_action_cmds - inner fail - expecting a list within a \
               list but got: %a"
              Sexp.pp other )
      | other ->
          Fmt.kstr failwith
            "process_action_cmds - outer fail - expecting a list within a \
             list but got: %a"
            Sexp.pp other in
    loop [] exp_list
    >>= fun action_list ->
    if not random_choice then return action_list
    else
      let len = List.length action_list in
      if len = 0 then return []
      else
        let rand = Base.Random.int len in
        let one_action = (List.to_array action_list).(rand) in
        return [one_action]

  let process_gen_batch state ~client act =
    protect_with_keyed_client "generate batch" ~client ~f:(fun () ->
        Helpers.Timing.duration
          (fun aFee ->
            branch state client
            >>= fun the_branch ->
            let json =
              Forge.batch_transfer ~src:act.src ~counter:act.counter ~fee:aFee
                ~branch:the_branch act.size in
            Tezos_client.Keyed.forge_and_inject state client ~json
            >>= fun json_result ->
            Console.sayf state More_fmt.(fun ppf () -> json ppf json_result))
          act.fee
        >>= fun ((), sec) ->
        Console.say state EF.(desc (haf "Execution time:") (af " %fs\n%!" sec)))

  let process_gen_multi_sig state ~client ~nodes act =
    protect_with_keyed_client "generate multisig" ~client ~f:(fun () ->
        Helpers.Timing.duration
          (fun () ->
            Multisig.deploy_and_transfer state client.client nodes
              ~num_signers:act.num_signers ~outer_repeat:act.outer_repeat
              ~contract_repeat:act.contract_repeat)
          ()
        >>= fun ((), sec) ->
        Console.say state EF.(desc (haf "Execution time:") (af " %fs\n%!" sec)))

  let run_actions state ~client ~nodes ~actions ~counter =
    Loop.n_times counter (fun _ ->
        List_sequential.iter actions ~f:(fun a ->
            match a with
            | `Batch_action ba -> process_gen_batch state ~client ba
            | `Multisig_action ma ->
                process_gen_multi_sig state ~client ~nodes ma))
end

module Dsl = struct
  let process_dsl state ~(client : Tezos_client.Keyed.t) ~nodes opts sexp =
    Commands.protect_with_keyed_client "process_dsl" ~client ~f:(fun () ->
        let n, sexp2 = Commands.process_repeat_action sexp in
        let b, sexp3 = Commands.process_random_choice sexp2 in
        Commands.process_action_cmds state ~client opts sexp3 ~random_choice:b
        >>= fun actions ->
        Commands.run_actions state ~client ~nodes ~actions ~counter:n)

  let run state ~nodes ~clients dsl_command =
    let client = List.hd_exn clients in
    process_dsl state ~client ~nodes Commands.all_opts dsl_command
end
