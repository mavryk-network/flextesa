open Internal_pervasives

type t = { name : string; michelson : string }

(* Originate smart contracts passed from the command line or from the derfault
   contracts (see /src/lib/dune) *)
val run :
  < application_name : string
  ; console : Console.t
  ; env_config : Environment_configuration.t
  ; paths : Paths.t
  ; runner : Running_processes.State.t
  ; .. > ->
  keys_and_daemons:
    ('a * Tezos_protocol.Account.t * Tezos_client.t * 'b * 'c) list ->
  smart_contracts:t list ->
  smart_rollup:Smart_rollup.t option ->
  ( unit,
    [> `Process_error of Process_result.Error.error
    | `System_error of [ `Fatal ] * System_error.static ] )
  Asynchronous_result.t

val cmdliner_term :
  < manpager : Manpage_builder.State.t ; .. > -> unit -> t list Cmdliner.Term.t
