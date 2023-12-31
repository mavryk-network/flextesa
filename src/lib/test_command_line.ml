open Internal_pervasives

module Command_making_state = struct
  type specific =
    < env_config : Environment_configuration.t
    ; command_name : string
    ; manpager : Manpage_builder.State.t >

  type 'a t = 'a Base_state.t constraint 'a = < specific ; .. >

  let make ~application_name ~command_name () : _ t =
    let env_config = Environment_configuration.default () in
    let manpager = Manpage_builder.State.make () in
    Environment_configuration.init
      (object
         method manpager = manpager
      end)
      env_config;
    object
      method application_name = application_name
      method command_name = command_name
      method env_config = env_config
      method manpager = manpager
    end
end

module Common_errors = struct
  type t =
    [ `Command_line of string
    | `Die of int
    | `Empty_protocol_list
    | `Msg of string
    | `Precheck_failure of string
    | Process_result.Error.t
    | `Scenario_error of string
    | System_error.t
    | Test_scenario.Inconsistency_error.t
    | `Waiting_for of string * [ `Time_out ] ]

  let pp ppf (e : t) =
    match e with
    | `Scenario_error s -> Stdlib.Format.fprintf ppf "%s" s
    | #Test_scenario.Inconsistency_error.t as e ->
        Stdlib.Format.fprintf ppf "%a" Test_scenario.Inconsistency_error.pp e
    | #Process_result.Error.t as e ->
        Stdlib.Format.fprintf ppf "%a" Process_result.Error.pp e
    | #System_error.t as e -> Stdlib.Format.fprintf ppf "%a" System_error.pp e
    | `Waiting_for (msg, `Time_out) ->
        Stdlib.Format.fprintf ppf "WAITING-FOR “%s”: Time-out" msg
    | `Precheck_failure _ as p -> Helpers.System_dependencies.Error.pp ppf p
    | `Die n -> Stdlib.Format.fprintf ppf "Exiting with %d" n
    | `Command_line s -> Stdlib.Format.fprintf ppf "%s" s
    | `Msg s -> Stdlib.Format.fprintf ppf "%s" s
end

module Run_command = struct
  let or_hard_fail ?lwt_run state main ~pp_error : unit =
    let open Asynchronous_result in
    Dbg.e EF.(wf "Run_command.or_hard_fail");
    run_application ?lwt_run (fun () ->
        Dbg.e EF.(wf "Run_command.or_hard_fail bind_on_error");
        bind_on_error (main ()) ~f:(fun ~result _ ->
            Dbg.e EF.(wf "Run_command.or_hard_fail on result");
            transform_error
              ~f:(fun _ -> `Die 3)
              (Console.say state
                 EF.(
                   custom (fun ppf -> Attached_result.pp ppf result ~pp_error)))
            >>= fun () -> die 2)
        >>= fun () ->
        Dbg.e EF.(wf "Run_command.or_hard_fail after bind_on_error");
        return ())

  let term ~pp_error () =
    Cmdliner.Term.pure (fun (state, run) -> or_hard_fail state run ~pp_error)
    [@@warning "-3"]

  let make ~pp_error t (i : Cmdliner.Term.info) =
    Cmdliner.Term.(term ~pp_error () $ t, i)
    [@@warning "-3"]
end

module Full_default_state = struct
  let cmdliner_term base_state ?default_interactivity
      ?(disable_interactivity = false) () =
    let runner = Running_processes.State.make () in
    let default_root = sprintf "/tmp/%s-test" base_state#command_name in
    let pauser = Interactive_test.Pauser.make [] in
    let ops = Log_recorder.Operations.make () in
    let state console paths interactivity (`With_baking baking) =
      object
        method paths = paths
        method runner = runner
        method console = console
        method application_name = base_state#application_name
        method test_interactivity = interactivity
        method test_baking = baking
        method pauser = pauser
        method operations_log = ops
        method env_config = base_state#env_config
      end
    in
    let open Cmdliner in
    let docs = Manpage_builder.section_test_scenario base_state in
    Term.(
      pure state $ Console.cli_term ()
      $ Paths.cli_term ~default_root ()
      $ (if disable_interactivity then pure `None
        else
          Interactive_test.Interactivity.cli_term ?default:default_interactivity
            ())
      $ Arg.(
          pure (fun x -> `With_baking (not x))
          $ value
              (flag
                 (info [ "no-baking" ] ~docs
                    ~doc:
                      "Completely disable baking/endorsing/accusing (you need \
                       to bake manually to make the chain advance)."))))
    [@@warning "-3"]
end

let cli_state ?default_interactivity ?disable_interactivity ~name () =
  let application_name = Fmt.str "Flextesa.%s" name in
  let command_name = name in
  let base_state =
    Command_making_state.make ~application_name ~command_name ()
  in
  Full_default_state.cmdliner_term base_state ?default_interactivity
    ?disable_interactivity ()
