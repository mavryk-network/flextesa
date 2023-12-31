open Internal_pervasives

type t = {
  id : string;
  level : int;
  custom_kernel : (string * string * string) option;
  node_mode : [ `Accuser | `Batcher | `Maintenance | `Observer | `Operator ];
  node : Tezos_executable.t;
  client : Tezos_executable.t;
  installer : Tezos_executable.t;
}

val executables : t -> Tezos_executable.t list

(* Originate a smart rollup with the kernel passed from the command line or the
   default tx-rollup *)
val run :
  < application_name : string
  ; console : Console.t
  ; env_config : Environment_configuration.t
  ; paths : Paths.t
  ; runner : Running_processes.State.t
  ; .. > ->
  smart_rollup:t option ->
  protocol:Tezos_protocol.t ->
  keys_and_daemons:
    (Tezos_node.t
    * Tezos_protocol.Account.t
    * Tezos_client.t
    * Tezos_client.Keyed.t
    * Tezos_daemon.t list)
    list ->
  nodes:Tezos_node.t list ->
  base_port:int ->
  ( unit,
    [> `Process_error of Process_result.Error.error
    | `System_error of [ `Fatal ] * System_error.static ] )
  Asynchronous_result.t

val cmdliner_term :
  < manpager : Manpage_builder.State.t ; .. > ->
  unit ->
  t option Cmdliner.Term.t
