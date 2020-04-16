open Flextesa
open Internal_pervasives
module IFmt = More_fmt

let run ?output_error_codes state ~strip_errors ~on_annotations ~input_file
    ~output_file () =
  let open Michelson in
  File_io.read_file state input_file
  >>= fun expr ->
  let transformed, error_codes =
    Transform.expression ~strip_errors ~on_annotations expr in
  File_io.write_file state ~path:output_file transformed
  >>= fun () ->
  Asynchronous_result.map_option output_error_codes ~f:(fun path ->
      List.fold error_codes ~init:(return [])
        ~f:(fun prevm (code, error_msg) ->
          prevm
          >>= fun prevl ->
          Json.of_expr error_msg
          >>= fun json ->
          return (Ezjsonm.(dict [("code", int code); ("value", json)]) :: prevl))
      >>= fun jsons ->
      System.write_file state path
        ~content:(Ezjsonm.to_string ~minify:false (`A jsons))
      >>= fun () ->
      return
        IFmt.(
          fun ppf ->
            wf ppf "%d “error codes” output to `%s`."
              (List.length error_codes) path))
  >>= fun pp_opt ->
  Console.sayf state
    IFmt.(
      fun ppf () ->
        vertical_box ppf (fun ppf ->
            wf ppf "Convertion+stripping: `%s` -> `%s`." input_file output_file ;
            Option.iter pp_opt ~f:(fun f -> cut ppf () ; f ppf)) ;
        cut ppf () ;
        vertical_box ppf ~indent:4 (fun ppf ->
            wf ppf "Deserialized cost:" ;
            cut ppf () ;
            pf ppf "* From: %a" Tz_protocol.Gas_limit_repr.pp_cost
              (Tz_protocol.Script_repr.deserialized_cost expr) ;
            cut ppf () ;
            pf ppf "* To:   %a" Tz_protocol.Gas_limit_repr.pp_cost
              (Tz_protocol.Script_repr.deserialized_cost transformed)) ;
        cut ppf () ;
        wf ppf "Binary-Bytes: %d -> %d"
          (Data_encoding.Binary.length Tz_protocol.Script_repr.expr_encoding
             expr)
          (Data_encoding.Binary.length Tz_protocol.Script_repr.expr_encoding
             transformed))

let make ?(command_name = "transform-michelson") () =
  let open Cmdliner in
  let open Term in
  let pp_error ppf e =
    match e with
    | #System_error.t as e -> System_error.pp ppf e
    | `Michelson_parsing _ as mp -> Michelson.Concrete.Parse_error.pp ppf mp
  in
  Test_command_line.Run_command.make ~pp_error
    ( pure
        (fun strip_errors
             input_file
             output_file
             on_annotations
             output_error_codes
             state
             ->
          ( state
          , run state ~strip_errors ~input_file ~output_file ~on_annotations
              ?output_error_codes ))
    $ Arg.(
        value
          (flag
             (info ["strip-errors"]
                ~doc:"Transform error messages into integers")))
    $ Arg.(
        required
          (pos 0 (some string) None
             (info [] ~docv:"INPUT-PATH" ~doc:"Input file.")))
    $ Arg.(
        required
          (pos 1 (some string) None
             (info [] ~docv:"OUTPUT-PATH" ~doc:"Output file.")))
    $ Michelson.Transform.On_annotations.cmdliner_term ()
    $ Arg.(
        value
          (opt (some string) None
             (info ["output-error-codes"]
                ~doc:
                  "Output the matching of error values to integers (unless \
                   `--strip-errors` is provided, the list will be empty).")))
    $ Test_command_line.cli_state ~name:"michokit-transform" () )
    (info command_name ~doc:"Perform transformations on Michelson code.")
