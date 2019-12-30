open Flextesa.Internal_pervasives

module Small_utilities = struct
  let key_of_name_command () =
    let open Cmdliner in
    let open Term in
    ( ( pure (fun n ->
            let open Flextesa.Tezos_protocol.Account in
            let account = of_name n in
            Caml.Printf.printf "%s,%s,%s,%s\n%!" (name account)
              (pubkey account) (pubkey_hash account) (private_key account))
      $ Arg.(
          required
            (pos 0 (some string) None
               (info [] ~docv:"NAME" ~doc:"String to generate the data from.")))
      )
    , info "key-of-name"
        ~doc:"Make an unencrypted key-pair deterministically from a string."
        ~man:
          [ `P
              "`flextesa key-of-name hello-world` generates a key-pair of the \
               `unencrypted:..` kind and outputs it as a 4 values separated \
               by commas: `name,pub-key,pub-key-hash,private-uri` (hence \
               compatible with the `--add-bootstrap-account` option of some \
               of the test scenarios)." ] )

  let netstat_ports ~pp_error () =
    let open Cmdliner in
    let open Term in
    Flextesa.Test_command_line.Run_command.make ~pp_error
      ( pure (fun state ->
            Flextesa.
              ( state
              , fun () ->
                  Helpers.Netstat.used_listening_ports state
                  >>= fun ports ->
                  let to_display =
                    List.map ports ~f:(fun (p, _) -> p)
                    |> List.sort ~compare:Int.compare in
                  Console.sayf state
                    Fmt.(
                      hvbox ~indent:2 (fun ppf () ->
                          box words ppf "Netstat listening ports:" ;
                          sp ppf () ;
                          box
                            (list
                               ~sep:(fun ppf () -> string ppf "," ; sp ppf ())
                               (fun ppf p -> fmt "%d" ppf p))
                            ppf to_display)) ))
      $ Flextesa.Test_command_line.cli_state ~disable_interactivity:true
          ~name:"netstat-ports" () )
      (info "netstat-listening-ports"
         ~doc:"Like `netstat -nut | awk something-something` but glorified.")

  let all ~pp_error () = [key_of_name_command (); netstat_ports ~pp_error ()]
end

let () =
  let open Cmdliner in
  let pp_error = Flextesa.Test_command_line.Common_errors.pp in
  let help = Term.(ret (pure (`Help (`Auto, None))), info "flextesa") in
  Term.exit
    (Term.eval_choice
       (help : unit Term.t * _)
       ( Small_utilities.all ~pp_error ()
       @ [Michokit.Command.make (); Flextesa.Interactive_mini_network.cmd ()]
       ))
