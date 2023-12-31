open Internal_pervasives

type t = { root : string }

let make root =
  {
    root =
      (if Stdlib.Filename.is_relative root then Stdlib.Sys.getcwd () // root
      else root);
  }

let root_path o = o.root
let pp fmt o = Fmt.pf fmt "@[<2>{Root:@ %s}@]" (root_path o)
let ob o : t = o#paths
let root o = ob o |> root_path

let cli_term ?(option_name = "root-path") ~default_root () =
  Cmdliner.(
    Term.(
      pure make
      $ Arg.(
          value & opt string default_root
          & info [ option_name ]
              ~doc:(sprintf "Root path for all configs/data to use."))))
  [@@warning "-3"]
