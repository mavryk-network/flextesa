open Internal_pervasives

module Key = struct
  module Crypto = Tezai_tz1_crypto.Signer

  module Of_name = struct
    type t = {
      (* name : string; *)
      pkh : Crypto.Public_key_hash.t;
      pk : Crypto.Public_key.t;
      sk : Crypto.Secret_key.t;
    }

    let make name =
      let sk = Crypto.Secret_key.of_seed name in
      let pk = Crypto.Public_key.of_secret_key sk in
      let pkh = Crypto.Public_key_hash.of_public_key pk in
      (* let pkh, pk, sk = Tezos_crypto.Ed25519.generate_key ~seed () in *)
      { (* name;  *) pkh; pk; sk }

    let pubkey n = Crypto.Public_key.to_base58 (make n).pk
    let pubkey_hash n = Crypto.Public_key_hash.to_base58 (make n).pkh
    let private_key n = "unencrypted:" ^ Crypto.Secret_key.to_base58 (make n).sk
  end
end

module Account = struct
  type t =
    | Of_name of string
    | Key_pair of {
        name : string;
        pubkey : string;
        pubkey_hash : string;
        private_key : string;
      }

  let of_name s = Of_name s
  let of_namef fmt = ksprintf of_name fmt
  let name = function Of_name n -> n | Key_pair k -> k.name

  let key_pair name ~pubkey ~pubkey_hash ~private_key =
    Key_pair { name; pubkey; pubkey_hash; private_key }

  let pubkey = function
    | Of_name n -> Key.Of_name.pubkey n
    | Key_pair k -> k.pubkey

  let pubkey_hash = function
    | Of_name n -> Key.Of_name.pubkey_hash n
    | Key_pair k -> k.pubkey_hash

  let private_key = function
    | Of_name n -> Key.Of_name.private_key n
    | Key_pair k -> k.private_key
end

module Voting_period = struct
  type t = [ `Proposal | `Exploration | `Cooldown | `Promotion | `Adoption ]
end

module Protocol_kind = struct
  type t =
    [ `Athens
    | `Babylon
    | `Carthage
    | `Delphi
    | `Edo
    | `Florence
    | `Granada
    | `Hangzhou
    | `Ithaca
    | `Jakarta
    | `Kathmandu
    | `Lima
    | `Mumbai
    | `Nairobi
    | `Oxford
    | `Alpha ]

  let names =
    [
      ("Athens", `Athens);
      ("Babylon", `Babylon);
      ("Carthage", `Carthage);
      ("Delphi", `Delphi);
      ("Edo", `Edo);
      ("Florence", `Florence);
      ("Granada", `Granada);
      ("Hangzhou", `Hangzhou);
      ("Ithaca", `Ithaca);
      ("Jakarta", `Jakarta);
      ("Kathmandu", `Kathmandu);
      ("Lima", `Lima);
      ("Mumbai", `Mumbai);
      ("Nairobi", `Nairobi);
      ("Oxford", `Oxford);
      ("Alpha", `Alpha);
    ]

  let ( < ) k1 k2 =
    let rec aux = function
      | [] -> assert false
      | (_, k) :: rest ->
          if Poly.equal k k2 then false
          else if Poly.equal k k1 then true
          else aux rest
    in
    aux names

  let default = `Alpha

  let cmdliner_term ?(default = default) ~docs () : t Cmdliner.Term.t =
    let open Cmdliner in
    Arg.(
      value
        (opt (enum names) default
           (info [ "protocol-kind" ] ~docs ~doc:"Set the protocol family.")))

  let pp ppf n =
    Fmt.string ppf
      (List.find_map_exn names ~f:(function
        | s, x when Poly.equal x n -> Some s
        | _ -> None))

  let canonical_hash : t -> string = function
    | `Oxford -> "ProxfordSW2S7fvchT1Zgj2avb5UES194neRyYVXoaDGvF9egt8"
    | `Nairobi -> "PtNairobiyssHuh87hEhfVBGCVrK3WnS8Z2FT4ymB5tAa4r1nQf"
    | `Mumbai -> "PtMumbai2TmsJHNGRkD8v8YDbtao7BLUC3wjASn1inAKLFCjaH1"
    (* Version 1: "PtMumbaiiFFEGbew1rRjzSPyzRbA51Tm3RVZL5suHPxSZYDhCEc" *)
    | `Lima -> "PtLimaPtLMwfNinJi9rCfDPWea8dFgTZ1MeJ9f1m2SRic6ayiwW"
    | `Kathmandu -> "PtKathmankSpLLDALzWw7CGD2j2MtyveTwboEYokqUCP4a1LxMg"
    | `Jakarta -> "PtJakart2xVj7pYXJBXrqHgd82rdkLey5ZeeGwDgPp9rhQUbSqY"
    | `Ithaca -> "Psithaca2MLRFYargivpo7YvUr7wUDqyxrdhC5CQq78mRvimz6A"
    | `Hangzhou ->
        "PtHangz2aRngywmSRGGvrcTyMbbdpWdpFKuS4uMWxg2RaH9i1qx"
        (* Version 1: "PtHangzHogokSuiMHemCuowEavgYTP8J5qQ9fQS793MHYFpCY3r" *)
    | `Granada -> "PtGRANADsDU8R9daYKAgWnQYAJ64omN1o3KMGVCykShA97vQbvV"
    | `Florence -> "PsFLorenaUUuikDWvMDr6fGBRG8kt3e3D3fHoXK1j1BFRxeSH4i"
    | `Carthage -> "PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb"
    | `Delphi -> "PsDELPH1Kxsxt8f9eWbxQeRxkjfbxoqM52jvs5Y5fBxWWh4ifpo"
    | `Alpha -> "ProtoALphaALphaALphaALphaALphaALphaALphaALphaDdp3zK"
    | `Edo -> "PtEdo2ZkT9oKpimTah6x2embF25oss54njMuPzkJTEi5RqfdZFA"
    | `Babylon -> "PsBabyM1eUXZseaJdmXFApDSBqj8YBfwELoxZHHW77EMcAbbwAS"
    | `Athens -> "Pt24m4xiPbLDhVgVfABUjirbmda3yohdN82Sp9FeuAXJ4eV9otd"

  let daemon_suffix_exn : t -> string = function
    | `Oxford -> "Proxford"
    | `Nairobi -> "PtNairob"
    | `Mumbai -> "PtMumbai"
    | `Lima -> "PtLimaPt"
    | `Kathmandu -> "PtKathma"
    | `Jakarta -> "013-PtJakart"
    | `Ithaca -> "012-Psithaca"
    | `Hangzhou -> "011-PtHangz2"
    | `Granada -> "010-PtGRANAD"
    | `Florence -> "009-PsFLoren"
    | `Carthage -> "006-PsCARTHA"
    | `Delphi -> "007-PsDELPH1"
    | `Alpha -> "alpha"
    | `Edo -> "008-PtEdo2Zk"
    | `Babylon -> assert false
    | `Athens -> assert false

  let wants_contract_manager : t -> bool = function
    | `Athens -> true
    | _ -> false

  let wants_endorser_daemon : t -> bool = function
    | `Ithaca | `Jakarta | `Kathmandu | `Lima | `Mumbai | `Nairobi | `Oxford
    | `Alpha ->
        false
    | `Florence | `Carthage | `Delphi | `Hangzhou | `Babylon | `Edo | `Granada
    | `Athens ->
        true
end

type t = {
  id : string;
  kind : Protocol_kind.t;
  bootstrap_accounts : (Account.t * Int64.t) list;
  dictator : Account.t;
  (* ; bootstrap_contracts: (Account.t * int * Script.origin) list *)
  soru_node_op : Account.t;
  expected_pow : int;
  name : string; (* e.g. alpha *)
  hash : string;
  time_between_blocks : int list;
  baking_reward_per_endorsement : int list;
  endorsement_reward : int list;
  blocks_per_roll_snapshot : int;
  blocks_per_voting_period : int;
  blocks_per_cycle : int;
  preserved_cycles : int;
  proof_of_work_threshold : int;
  timestamp_delay : int option;
  custom_protocol_parameters : Ezjsonm.t option;
}

let compare a b = String.compare a.id b.id

let make_bootstrap_accounts ~balance n =
  List.init n ~f:(fun n -> (Account.of_namef "bootacc-%d" n, balance))

let default () =
  let dictator = Account.of_name "dictator-default" in
  let soru_node_op = Account.of_name "soru-node-operator" in
  {
    id = "default-bootstrap";
    kind = Protocol_kind.default;
    bootstrap_accounts = make_bootstrap_accounts ~balance:4_000_000_000_000L 4;
    dictator
    (* ; bootstrap_contracts= [(dictator, 10_000_000, `Sandbox_faucet)] *);
    soru_node_op;
    expected_pow = 1;
    name = "alpha";
    hash = "ProtoALphaALphaALphaALphaALphaALphaALphaALphaDdp3zK";
    time_between_blocks = [ 2; 3 ];
    baking_reward_per_endorsement = [ 78_125; 11_719 ];
    endorsement_reward = [ 78_125; 52_083 ];
    blocks_per_roll_snapshot =
      4 (* From lib_parameters/default_parameters.ml constants_sandbox *);
    blocks_per_voting_period = 16;
    blocks_per_cycle = 8 (* From constants_sandbox *);
    preserved_cycles = 2 (* From constants_sandbox *);
    proof_of_work_threshold = -1 (* From constants_sandbox *);
    timestamp_delay = None;
    custom_protocol_parameters = None;
  }

let protocol_parameters_json t : Ezjsonm.t =
  match t.custom_protocol_parameters with
  | Some s -> s
  | None ->
      let open Ezjsonm in
      (match t.kind with
      | `Nairobi | `Oxford | `Alpha -> ()
      | other ->
          Fmt.failwith
            "Flextesa cannot generate parameters for old protocols like %a, \
             please provide your own JSON file."
            Protocol_kind.pp other);
      let unsupported_protocol where t =
        Fmt.failwith "BUG: %s -> Unsupported protocol: %a" where
          Protocol_kind.pp t
      in
      let make_account (account, amount) =
        strings [ Account.pubkey account; sprintf "%Ld" amount ]
      in
      (* Use 'add_replace' and 'remove' to align "base" parameters to protocol
         specifications. Ensure that "base" list remains up-to-date by adding new
         parameters to the "base" list and use these functions for the older
         protocols; which will eventually be removed. *)
      let add_replace (k, v) l = List.Assoc.add l ~equal:String.equal k v in
      let remove key l = List.Assoc.remove l ~equal:String.equal key in
      (* Use to prefix a string to key. Key prefixes can change with new protocol.  *)
      let prefix_keys prefix l =
        List.map l ~f:(fun (k, v) -> (Fmt.str "%s_%s" prefix k, v))
      in
      let tx_rollup_specific_parameters =
        let base =
          [
            ("tx_rollup_enable", bool false);
            ("tx_rollup_origination_size", int 60_000);
            ("tx_rollup_hard_size_limit_per_inbox", int 100_000);
            ("tx_rollup_hard_size_limit_per_message", int 5_000);
            ("tx_rollup_max_withdrawals_per_batch", int 255);
            ("tx_rollup_commitment_bond", string (Int.to_string 10_000_000_000));
            ("tx_rollup_finality_period", int 2_000);
            ("tx_rollup_max_inboxes_count", int 2_100);
            ("tx_rollup_withdraw_period", int 2_000);
            ("tx_rollup_max_messages_per_inbox", int 1_010);
            ("tx_rollup_max_commitments_count", int 4_100);
            ("tx_rollup_cost_per_byte_ema_factor", int 120);
            ("tx_rollup_max_ticket_payload_size", int 10_240);
            ("tx_rollup_rejection_max_proof_size", int 30_000);
            ("tx_rollup_sunset_level", int32 3_473_409l);
          ]
        in
        match t.kind with `Nairobi -> base | _ -> []
      in
      let dal_specific_parameters =
        let dal_parametric =
          let base =
            (* Most of these valuse are from lib_parameters/default_parameters.ml constants_sandbox *)
            [
              ("page_size", int (4096 / 32));
              ("slot_size", int ((1 lsl 20) / 32));
              ("redundancy_factor", int 8);
              ("number_of_shards", int (2048 / 32));
              ("feature_enable", bool false);
              ("number_of_slots", int 16);
              ("attestation_lag", int 1);
              ("attestation_threshold", int 50);
              ("blocks_per_epoch", int32 2l);
            ]
          in
          match t.kind with
          | `Nairobi -> base
          | `Oxford | `Alpha -> base |> add_replace ("attestation_lag", int 4)
          | _ -> []
        in
        [ ("dal_parametric", dict dal_parametric) ]
      in
      let smart_rollup_specific_parameters =
        let reveal_activation_level =
          let base =
            [
              ("raw_data", dict [ ("Blake2B", int 0) ]);
              ("metadata", int 0);
              (* dal_page = *)
              (*   (if default_dal.feature_enable then Raw_level.root *)
              (*   else *)
              (*     (\* Deactivate the reveal if the dal is not enabled. *\) *)
              (*     (\* https://gitlab.com/tezos/tezos/-/issues/5968 *)
              (*        Encoding error with Raw_level *)

              (*        We set the activation level to [pred max_int] to deactivate *)
              (*        the feature. The [pred] is needed to not trigger an encoding *)
              (*        exception with the value [Int32.int_min] (see tezt/tests/mockup.ml). *\) *)
              (*     Raw_level.of_int32_exn Int32.(pred max_int)); *)
              ("dal_page", int32 Int32.(pred max_value));
            ]
          in
          match t.kind with `Oxford | `Alpha -> base | _ -> []
        in
        let base =
          (* challenge_window_in_blocks is reduce to minimized the time required to cement commitments. *)
          let challenge_window_in_blocks = 30 in
          [
            ("enable", bool true);
            ("arith_pvm_enable", bool false);
            ("origination_size", int 6_314);
            ("challenge_window_in_blocks", int challenge_window_in_blocks);
            ("commitment_period_in_blocks", int (challenge_window_in_blocks / 2));
            ("stake_amount", string (Int.to_string 10_000_000_000));
            ("max_lookahead_in_blocks", int (challenge_window_in_blocks * 2));
            ("max_active_outbox_levels", int challenge_window_in_blocks);
            ("max_outbox_messages_per_level", int 100);
            ("number_of_sections_in_dissection", int 32);
            ("timeout_period_in_blocks", int (challenge_window_in_blocks / 2));
            ( "max_number_of_cemented_commitments",
              int 30 (* Keep more old commitments. *) );
            ("max_number_of_parallel_games", int 32);
            ("reveal_activation_level", dict reveal_activation_level);
          ]
        in
        match t.kind with
        | `Nairobi ->
            prefix_keys "smart_rollup" (base |> remove "reveal_activation_level")
        | `Oxford -> prefix_keys "smart_rollup" base
        | `Alpha ->
            prefix_keys "smart_rollup"
              (base |> add_replace ("private_enable", bool false))
        | _ -> []
      in
      let zk_rollup_specific_parameters =
        let base =
          [
            ("enable", bool false);
            ("origination_size", int 4_000);
            ("min_pending_to_process", int 10);
            ("max_ticket_payload_size", int 2_048);
          ]
        in
        match t.kind with
        | `Nairobi ->
            prefix_keys "zk_rollup" (base |> remove "max_ticket_payload_size")
        | `Oxford | `Alpha -> prefix_keys "zk_rollup" base
        | _ -> []
      in
      let adaptive_issuance_specific_parameters =
        let adaptive_rewards =
          let base =
            [
              ( "issuance_ratio_min",
                dict
                  [
                    ("numerator", string (Int.to_string 5));
                    ("denominator", string (Int.to_string 10000));
                  ] );
              ( "issuance_ratio_max",
                dict
                  [
                    ("numerator", string (Int.to_string 5));
                    ("denominator", string (Int.to_string 20));
                  ] );
              ("max_bonus", string (Int64.to_string 50_000_000_000_000L));
              ("growth_rate", string (Int64.to_string 115_740_740L));
              ( "center_dz",
                dict
                  [
                    ("numerator", string (Int.to_string 1));
                    ("denominator", string (Int.to_string 2));
                  ] );
              ( "radius_dz",
                dict
                  [
                    ("numerator", string (Int.to_string 1));
                    ("denominator", string (Int.to_string 50));
                  ] );
            ]
          in
          match t.kind with `Oxford | `Alpha -> base | _ -> []
        in
        let base =
          [
            ("global_limit_of_staking_over_baking", int 5);
            ("edge_of_staking_over_delegation", int 2);
            ("adaptive_issuance_launch_ema_threshold", int32 1l);
            ("adaptive_rewards_params", dict adaptive_rewards);
          ]
        in
        match t.kind with `Oxford | `Alpha -> base | _ -> []
      in
      let general_parameters =
        let consensus_committee_size =
          256 (* From lib_parameters/default_parameters.ml constants_sandbox *)
        in
        let consensus_threshold = 0 (* From constants_sandbox *) in
        let issuance_weights =
          (* Form module Generated in /lib_protocol/constants_repr.ml *)
          let bonus_committee_size =
            consensus_committee_size - consensus_threshold
          in
          let _reward_parts_whole = 20480 (* = 256 * 80 *) in
          let reward_parts_half = 10240 (* = reward_parts_whole / 2 *) in
          let reward_parts_quarter = 5120 (* = reward_parts_whole / 4 *) in
          let reward_parts_16th = 1280 (* = reward_parts_whole / 16 *) in
          let base =
            [
              ( "base_total_issued_per_minute",
                string (Int64.to_string 85_007_812L) );
              ( "baking_reward_fixed_portion_weight",
                int
                  (if bonus_committee_size <= 0 then reward_parts_half
                  else reward_parts_quarter) );
              ( "baking_reward_bonus_weight",
                int
                  (if bonus_committee_size <= 0 then 0
                  else reward_parts_quarter) );
              ("attesting_reward_weight", int reward_parts_half);
              ("liquidity_baking_subsidy_weight", int reward_parts_16th);
              ("seed_nonce_revelation_tip_weight", int 1);
              ("vdf_revelation_tip_weight", int 1);
            ]
          in
          match t.kind with `Oxford | `Alpha -> base | _ -> []
        in
        let base =
          [
            ( "bootstrap_accounts",
              list make_account
                (t.bootstrap_accounts
                @ [ (t.dictator, 10_000_000L) ]
                @ [ (t.soru_node_op, 1_000_000_000_000L) ]) );
            ("preserved_cycles", int t.preserved_cycles);
            ("blocks_per_cycle", int t.blocks_per_cycle);
            ("blocks_per_commitment", int 4 (* From constants_sandbox *));
            ("nonce_revelation_threshold", int 4 (* From constants_sandbox *));
            ("blocks_per_stake_snapshot", int t.blocks_per_roll_snapshot);
            ( "cycles_per_voting_period",
              int
                ( t.blocks_per_voting_period / t.blocks_per_cycle |> fun c ->
                  if c = 0 then
                    Fmt.failwith
                      "Requries (t.blocks_per_voting_period / \
                       t.blocks_per_cycle) >= 1"
                  else c ) );
            ("hard_gas_limit_per_operation", string (Int.to_string 1_040_000));
            ("hard_gas_limit_per_block", string (Int.to_string 2_600_000));
            ( "proof_of_work_threshold",
              ksprintf string "%d" t.proof_of_work_threshold );
            ("minimal_stake", string (Int.to_string 6_000_000_000));
            ("minimal_frozen_stake", string (Int.to_string 600));
            ( "vdf_difficulty",
              string (Int.to_string 50_000) (*From constants_sandbox *) );
            ("origination_size", int 257);
            ("issuance_weights", dict issuance_weights);
            ("hard_storage_limit_per_operation", string (Int.to_string 60_000));
            ("cost_per_byte", string (Int.to_string 250));
            ("quorum_min", int 2_000);
            ("quorum_max", int 7_000);
            ("min_proposal_quorum", int 500);
            ("liquidity_baking_toggle_ema_threshold", int 1_000_000_000);
            ("max_operations_time_to_live", int 240);
            ( "minimal_block_delay",
              string
                (match List.nth_exn t.time_between_blocks 0 with
                | n -> Int.to_string n
                | exception _ ->
                    Fmt.failwith "time_between_blocks cannot be an empty list")
            );
            ( "delay_increment_per_round",
              string
                (match t.time_between_blocks with
                | [ n ] | _ :: n :: _ -> Int.to_string n
                | _ ->
                    Fmt.failwith "time_between_blocks cannot be an empty list")
            );
            ("consensus_committee_size", int consensus_committee_size);
            ("consensus_threshold", int consensus_threshold);
            ( "minimal_participation_ratio",
              dict [ ("numerator", int 2); ("denominator", int 3) ] );
            ("max_slashing_period", int 2);
            ( "limit_of_delegation_over_baking",
              int 19 (* From constants_sandbox *) );
            ("percentage_of_frozen_deposits_slashed_per_double_baking", int 10);
            ( "percentage_of_frozen_deposits_slashed_per_double_attestation",
              int 50 );
            ("cache_script_size", int 100_000_000);
            ("cache_stake_distribution_cycles", int 8);
            ("cache_sampler_state_cycles", int 8);
          ]
        in
        match t.kind with
        | `Nairobi ->
            base
            |> add_replace
                 ( "frozen_deposits_percentage",
                   int 5 (* From constants_sandbox *) )
            |> add_replace
                 (* minimal_stake / double_baking_punishment must be >= 10 to
                    caclulate the Oxford constants. *)
                 ("double_baking_punishment", string (Int.to_string 640_000_000))
            |> add_replace
                 ( "ratio_of_frozen_deposits_slashed_per_double_endorsement",
                   dict [ ("numerator", int 1); ("denominator", int 2) ] )
            |> add_replace
                 ("seed_nonce_revelation_tip", string (Int.to_string 125_000))
            |> add_replace
                 ( "baking_reward_fixed_portion",
                   string (Int.to_string 5_000_000) )
            |> add_replace ("baking_reward_bonus_per_slot", string "2143")
            |> add_replace ("endorsing_reward_per_slot", string "1428")
            |> add_replace
                 ("liquidity_baking_subsidy", string (Int.to_string 1_250_000))
            |> remove "minimal_frozen_stake"
            |> remove "issuance_weights"
            |> remove "limit_of_delegation_over_baking"
            |> remove "percentage_of_frozen_deposits_slashed_per_double_baking"
            |> remove
                 "percentage_of_frozen_deposits_slashed_per_double_attestation"
        | `Oxford | `Alpha -> base
        | other -> unsupported_protocol "defalut_parameters" other
      in
      dict
        (general_parameters @ tx_rollup_specific_parameters
       @ dal_specific_parameters @ smart_rollup_specific_parameters
       @ zk_rollup_specific_parameters @ adaptive_issuance_specific_parameters)

let voting_period_to_string t (p : Voting_period.t) =
  (* This has to mimic: src/proto_alpha/lib_protocol/voting_period_repr.ml *)
  match p with
  | `Promotion ->
      if Protocol_kind.(t.kind < `Florence) then "promotion_vote"
      else "promotion"
  | `Exploration ->
      if Protocol_kind.(t.kind < `Florence) then "testing_vote"
      else "exploration"
  | `Proposal -> "proposal"
  | `Cooldown ->
      if Protocol_kind.(t.kind < `Florence) then "testing" else "cooldown"
  | `Adoption -> "adoption"

let sandbox { dictator; _ } =
  let pk = Account.pubkey dictator in
  Ezjsonm.to_string (`O [ ("genesis_pubkey", `String pk) ])

let protocol_parameters t =
  Ezjsonm.to_string ~minify:false (protocol_parameters_json t)

let expected_pow t = t.expected_pow
let id t = t.id
let bootstrap_accounts t = List.map ~f:fst t.bootstrap_accounts
let kind t = t.kind
let dictator_name { dictator; _ } = Account.name dictator
let dictator_secret_key { dictator; _ } = Account.private_key dictator
let soru_node_operator t = t.soru_node_op
let make_path config t = Paths.root config // sprintf "protocol-%s" (id t)
let sandbox_path config t = make_path config t // "sandbox.json"

let protocol_parameters_path config t =
  make_path config t // "protocol_parameters.json"

let ensure_script state t =
  let open Genspio.EDSL in
  let file string p =
    let path = p state t in
    ( Stdlib.Filename.basename path,
      write_stdout ~path:(str path)
        (feed ~string:(str (string t)) (exec [ "cat" ])) )
  in
  check_sequence
    ~verbosity:(`Announce (sprintf "Ensure-protocol-%s" (id t)))
    [
      ("directory", exec [ "mkdir"; "-p"; make_path state t ]);
      file sandbox sandbox_path;
      file protocol_parameters protocol_parameters_path;
    ]

let ensure state t =
  Running_processes.run_successful_cmdf state "sh -c %s"
    (Genspio.Compile.to_one_liner (ensure_script state t)
    |> Stdlib.Filename.quote)
  >>= fun _ -> return ()

let cli_term state =
  let open Cmdliner in
  let open Term in
  let def = default () in
  let docs = Manpage_builder.section state ~rank:2 ~name:"PROTOCOL OPTIONS" in
  pure
    (fun
      bootstrap_accounts
      (`Blocks_per_voting_period blocks_per_voting_period)
      (`Protocol_hash hash_opt)
      (`Time_between_blocks time_between_blocks)
      (`Blocks_per_cycle blocks_per_cycle)
      (`Preserved_cycles preserved_cycles)
      (`Timestamp_delay timestamp_delay)
      (`Protocol_parameters custom_protocol_parameters)
      kind
    ->
      let id = "default-and-command-line" in
      let hash =
        match hash_opt with
        | None -> Protocol_kind.canonical_hash kind
        | Some s -> s
      in
      {
        def with
        id;
        kind;
        custom_protocol_parameters;
        blocks_per_cycle;
        hash;
        bootstrap_accounts;
        time_between_blocks;
        preserved_cycles;
        timestamp_delay;
        blocks_per_voting_period;
      })
  $ Arg.(
      pure (fun remove_all nb balance add_bootstraps ->
          add_bootstraps
          @ make_bootstrap_accounts ~balance (if remove_all then 0 else nb))
      $ value
          (flag
             (info
                ~doc:
                  "Do not create any of the default bootstrap accounts (this \
                   overrides `--number-of-bootstrap-accounts` with 0)."
                ~docs
                [ "remove-default-bootstrap-accounts" ]))
      $ value
          (opt int 4
             (info
                [ "number-of-bootstrap-accounts" ]
                ~docs ~doc:"Set the number of generated bootstrap accounts."))
      $ (pure (function
           | `Tez, f -> f *. 1_000_000. |> Int64.of_float
           | `Mutez, f -> f |> Int64.of_float)
        $ value
            (opt
               (pair ~sep:':'
                  (enum [ ("tz", `Tez); ("tez", `Tez); ("mutez", `Mutez) ])
                  float)
               (`Tez, 4_000_000.)
               (info
                  [ "balance-of-bootstrap-accounts" ]
                  ~docv:"UNIT:FLOAT" ~docs
                  ~doc:
                    "Set the initial balance of bootstrap accounts, for \
                     instance: `tz:2_000_000.42` or \
                     `mutez:42_000_000_000_000`.")))
      $ Arg.(
          pure (fun l ->
              List.map l
                ~f:(fun ((name, pubkey, pubkey_hash, private_key), tez) ->
                  (Account.key_pair name ~pubkey ~pubkey_hash ~private_key, tez)))
          $ value
              (opt_all
                 (pair ~sep:'@' (t4 ~sep:',' string string string string) int64)
                 []
                 (info
                    [ "add-bootstrap-account" ]
                    ~docs
                    ~docv:"NAME,PUBKEY,PUBKEY-HASH,PRIVATE-URI@MUTEZ-AMOUNT"
                    ~doc:
                      "Add a custom bootstrap account, e.g. \
                       `LedgerBaker,edpku...,tz1YPS...,ledger://crouching-tiger.../ed25519/0'/0'@20_000_000_000`. \
                       Note: that Oxford protocal starts bootstrap_accounts \
                       with portion of their balance already staked (minimum \
                       mutez:6_000_000_000). The staked balance doesn't show \
                       up as avaialbe balance until it is unstaked. "))))
  $ Arg.(
      pure (fun x -> `Blocks_per_voting_period x)
      $ value
          (opt int def.blocks_per_voting_period
             (info ~docs
                [ "blocks-per-voting-period" ]
                ~doc:"Set the length of voting periods.")))
  $ Arg.(
      pure (fun x -> `Protocol_hash x)
      $ value
          (opt (some string) None
             (info [ "protocol-hash" ] ~docs
                ~doc:
                  "Set the (initial) protocol hash (the default is to derive  \
                   it from the protocol kind).")))
  $ Arg.(
      let doc =
        "Set the time between blocks bootstrap-parameter, e.g. `2,3,2`, the \
         first value is used as minimal-block-delay. For Tenderbake, we fill \
         the `round0` and `round1` fields of `round_durations` with the 2 \
         first values of the list, or duplicate the first if it is the only \
         one."
      in
      pure (fun x -> `Time_between_blocks x)
      $ value
          (opt (list ~sep:',' int) def.time_between_blocks
             (info [ "time-between-blocks" ] ~docv:"COMMA-SEPARATED-SECONDS"
                ~docs ~doc)))
  $ Arg.(
      pure (fun x -> `Blocks_per_cycle x)
      $ value
          (opt int def.blocks_per_cycle
             (info [ "blocks-per-cycle" ] ~docv:"NUMBER" ~docs
                ~doc:"Number of blocks per cycle.")))
  $ Arg.(
      pure (fun x -> `Preserved_cycles x)
      $ value
          (opt int def.preserved_cycles
             (info [ "preserved-cycles" ] ~docv:"NUMBER" ~docs
                ~doc:
                  "Base constant for baking rights (search for \
                   `PRESERVED_CYCLES` in the white paper).")))
  $ Arg.(
      pure (fun x -> `Timestamp_delay x)
      $ value
          (opt (some int) def.timestamp_delay
             (info [ "timestamp-delay" ] ~docv:"NUMBER" ~docs
                ~doc:"Protocol activation timestamp delay in seconds.")))
  $ Arg.(
      pure (fun f ->
          `Protocol_parameters
            (Option.map f ~f:(fun path ->
                 let i = Stdlib.open_in path in
                 Ezjsonm.from_channel i)))
      $ value
          (opt (some file) None
             (info
                [ "override-protocol-parameters" ]
                ~doc:
                  "Use these protocol parameters instead of the generated ones \
                   (technically this invalidates most other options from a \
                   node's point of view, use at your own risk)."
                ~docv:"JSON-FILE" ~docs)))
  $ Protocol_kind.cmdliner_term () ~docs
  [@@warning "-3"]

module Pretty_print = struct
  open More_fmt

  let verbatim_protection f ppf json_blob =
    try f ppf json_blob
    with e ->
      json ppf json_blob;
      cut ppf ();
      exn ppf e

  let fail_expecting s = failwith "PP: Expecting %s" s

  let mempool_pending_operations_rpc ppf mempool_json =
    let pp_op_list_short ppf l =
      let kinds =
        List.map l ~f:(fun js -> Jqo.(field ~k:"kind" js |> get_string))
      in
      pf ppf "%s"
        (List.fold kinds ~init:[] ~f:(fun prev k ->
             match prev with
             | (kind, n) :: more when String.equal kind k ->
                 (kind, n + 1) :: more
             | other -> (k, 1) :: other)
        |> List.map ~f:(function k, 1 -> k | k, n -> str "%s×%d" k n)
        |> String.concat ~sep:"+")
    in
    let open Jqo in
    match mempool_json with
    | `O four_fields ->
        List.iter four_fields ~f:(fun (name, content) ->
            pf ppf "@,* `%s`: " (String.capitalize name);
            match content with
            | `A [] -> pf ppf "Empty."
            | `A l -> (
                match name with
                | "applied" ->
                    List.iter l ~f:(fun op ->
                        let contents = field ~k:"contents" op |> get_list in
                        let pp_op_long ppf js =
                          match field ~k:"kind" js |> get_string with
                          | "transaction" ->
                              pf ppf "@,       * Mutez:%s: `%s` -> `%s`%s"
                                (field ~k:"amount" js |> get_string)
                                (field ~k:"source" js |> get_string)
                                (field ~k:"destination" js |> get_string)
                                (try
                                   let _ = field ~k:"parameters" js in
                                   "+parameters"
                                 with _ -> "")
                          | "origination" ->
                              pf ppf
                                "@,       * Mutez:%s, source: `%s`, fee: `%s`"
                                (field ~k:"balance" js |> get_string)
                                (field ~k:"source" js |> get_string)
                                (field ~k:"fee" js |> get_string)
                          | _ -> ()
                        in
                        pf ppf "@,   * [%a] %a" pp_op_list_short contents
                          (long_string ~max:15)
                          (field ~k:"hash" op |> get_string);
                        List.iter contents ~f:(pp_op_long ppf))
                | _other ->
                    List.iter l ~f:(function
                      | `A [ `String opid; op ] ->
                          let contents = field ~k:"contents" op |> get_list in
                          pf ppf "@,    * [%s]: %a" opid pp_op_list_short
                            contents;
                          pf ppf "@,    TODO: %a" json content
                      | _ -> fail_expecting "a operation tuple"))
            | _ -> fail_expecting "a list of operations")
    | _ -> fail_expecting "a JSON object"

  let block_head_rpc ppf block_json =
    let open Jqo in
    let proto = field ~k:"protocol" block_json |> get_string in
    let hash = field ~k:"hash" block_json |> get_string in
    let metadata = field ~k:"metadata" block_json in
    let next_protocol = metadata |> field ~k:"next_protocol" |> get_string in
    let header = field ~k:"header" block_json in
    let level = field ~k:"level" header |> get_int in
    let timestamp = field ~k:"timestamp" header |> get_string in
    let voting_kind =
      metadata
      |> field ~k:"voting_period_info"
      |> field ~k:"voting_period" |> field ~k:"kind" |> get_string
    in
    let voting_pos =
      metadata
      |> field ~k:"voting_period_info"
      |> field ~k:"position" |> get_int
    in
    let voting_nth =
      metadata |> field ~k:"level" |> field ~k:"voting_period" |> get_int
    in
    let baker = metadata |> field ~k:"baker" |> get_string in
    pf ppf "Level %d | `%s` | %s" level hash timestamp;
    pf ppf "@,* Protocol: `%s`" proto;
    if String.equal proto next_protocol then pf ppf " (also next)"
    else pf ppf "@,* Next-protocol: `%s`" next_protocol;
    pf ppf "@,* Voting period %d: `%s` (level: %d)" voting_nth voting_kind
      voting_pos;
    pf ppf "@,* Baker: `%s`" baker
end
