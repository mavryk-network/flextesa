(** This module wraps the type ['kind t] around the notion of octez-executable:
    a path to a binary with octez-specific properties. *)

(** Helper functions to construct exec-style command lines for ["octez-*"]
    applications. *)
module Make_cli : sig
  val flag : string -> string list
  val opt : string -> string -> string list
  val optf : string -> ('a, unit, string, string list) format4 -> 'a
end

(** Manipulate the ["TEZOS_EVENTS_CONFIG"] environment variable. *)
module Unix_files_sink : sig
  type t = private { matches : string list option; level_at_least : string }

  val all_notices : t
  val all_info : t
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
(** The type [kind] is used to distinguish ['a t] executables. *)

type t = private {
  kind : kind;
  binary : string option;
  unix_files_sink : Unix_files_sink.t option;
  environment : (string * string) list;
}
(** The wrapper of the octez-executable. *)

val make :
  ?binary:string ->
  ?unix_files_sink:Unix_files_sink.t ->
  ?environment:(string * string) list ->
  kind ->
  t
(** Create a ["octez-node"] executable. *)

val get : ?protocol_kind:Tezos_protocol.Protocol_kind.t -> t -> string
(** The path to the executable. *)

val call :
  < env_config : Environment_configuration.t ; .. > ->
  t ->
  ?protocol_kind:Tezos_protocol.Protocol_kind.t ->
  path:string ->
  string list ->
  unit Genspio.EDSL.t
(** Build a [Genspio.EDSL.t] script to run a tezos command, the [~path] argument
    is used as a toplevel path for the unix-files event-sink
    (event-logging-framework) and for other local logging files. *)

val cli_term :
  ?extra_doc:string ->
  ?prefix:string ->
  < manpager : Internal_pervasives.Manpage_builder.State.t ; .. > ->
  kind ->
  t Cmdliner.Term.t
(** Build a [Cmdliner] term which creates executables, the second argument is a
    prefix of option names (e.g. ["tezos"] for the option
    ["--tezos-accuser-alpha-binary"]). *)

val kind_string : [< kind ] -> string
(** The name of the executable. *)
