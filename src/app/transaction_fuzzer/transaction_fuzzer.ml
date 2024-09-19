open Core
open Bin_prot.Std
open Mina_base
open Mina_transaction
module Fp = Kimchi_pasta.Basic.Fp
module Ledger = Mina_ledger.Ledger
module Length = Mina_numbers.Length
module Global_slot = Mina_numbers.Global_slot_since_genesis

let txn_state_view : Zkapp_precondition.Protocol_state.View.t =
  { snarked_ledger_hash =
      Fp.of_string
        "19095410909873291354237217869735884756874834695933531743203428046904386166496"
  ; blockchain_length = Length.of_int 1
  ; min_window_density = Length.of_int 77
  ; total_currency = Currency.Amount.of_string "10016100000000000"
  ; global_slot_since_genesis = Global_slot.of_int 0
  ; staking_epoch_data =
      { ledger =
          { hash =
              Fp.of_string
                "19095410909873291354237217869735884756874834695933531743203428046904386166496"
          ; total_currency = Currency.Amount.of_string "10016100000000000"
          }
      ; seed = Mina_base.Epoch_seed.of_decimal_string "0"
      ; start_checkpoint = State_hash.zero
      ; lock_checkpoint = State_hash.zero
      ; epoch_length = Length.of_int 1
      }
  ; next_epoch_data =
      { ledger =
          { hash =
              Fp.of_string
                "19095410909873291354237217869735884756874834695933531743203428046904386166496"
          ; total_currency = Currency.Amount.of_string "10016100000000000"
          }
      ; seed =
          Fp.of_string
            "18512313064034685696641580142878809378857342939026666126913761777372978255172"
      ; start_checkpoint = State_hash.zero
      ; lock_checkpoint =
          Fp.of_string
            "9196091926153144288494889289330016873963015481670968646275122329689722912273"
      ; epoch_length = Length.of_int 2
      }
  }

let ledger = ref (Mina_ledger.Ledger.create_ephemeral ~depth:10 ())

let constraint_constants : Genesis_constants.Constraint_constants.t ref =
  ref Genesis_constants.Constraint_constants.compiled

let set_constraint_constants
    (constants : Genesis_constants.Constraint_constants.t) =
  constraint_constants := constants

let create_initial_accounts accounts =
  let constraint_constants = !constraint_constants in
  let packed =
    Genesis_ledger_helper.Ledger.packed_genesis_ledger_of_accounts
      ~depth:constraint_constants.ledger_depth
      (lazy (List.map ~f:(fun a -> (None, a)) accounts))
  in
  Lazy.force (Genesis_ledger.Packed.t packed)

let set_initial_accounts (accounts : Account.Stable.Latest.t list) : Fp.t =
  let ledger_ = create_initial_accounts accounts in
  ledger := ledger_ ;
  Ledger.merkle_root ledger_

module ApplyTxResult = struct
  type t =
    { root_hash : Fp.Stable.V1.t
    ; apply_result : Mina_transaction_logic.Transaction_applied.Stable.V2.t list
    ; error : Bounded_types.String.Stable.V1.t
    }
  [@@deriving bin_io]
end

let apply_tx (command : User_command.Stable.Latest.t) : ApplyTxResult.t =
  try
    let tx = Transaction.Command command in
    let constraint_constants = !constraint_constants in
    let ledger = !ledger in
    let applied =
      Ledger.apply_transactions ~constraint_constants
        ~global_slot:txn_state_view.global_slot_since_genesis ~txn_state_view
        ledger [ tx ]
    in
    match applied with
    | Ok applied ->
        { root_hash = Ledger.merkle_root ledger
        ; apply_result = applied
        ; error = ""
        }
    | Error e ->
        { root_hash = Ledger.merkle_root ledger
        ; apply_result = []
        ; error = Error.to_string_hum e
        }
  with e ->
    let bt = Printexc.get_backtrace () in
    let msg = Exn.to_string e in
    Core_kernel.printf !"except: %s\n%s\n%!" msg bt ;
    raise e

module Action = struct
  type t =
    | SetConstraintConstants of Genesis_constants.Constraint_constants.t
    | SetInitialAccounts of Account.Stable.Latest.t list
    | ApplyTx of User_command.Stable.Latest.t
    | Exit
  [@@deriving bin_io]
end

module Output = struct
  type t =
    | ConstraintConstantsSet
    | InitialAccountsSet of Fp.t
    | TxApplied of ApplyTxResult.t
    | ExitAck
  [@@deriving bin_io]
end

let handle_action (action : Action.t) : Output.t =
  match action with
  | Action.SetConstraintConstants constants ->
      set_constraint_constants constants ;
      Output.ConstraintConstantsSet
  | Action.SetInitialAccounts accounts ->
      let ledger_hash = set_initial_accounts accounts in
      Output.InitialAccountsSet ledger_hash
  | Action.ApplyTx user_command ->
      let tx_result = apply_tx user_command in
      Output.TxApplied tx_result
  | Action.Exit ->
      Output.ExitAck

let read_exactly in_channel n =
  let buf = Bytes.create n in
  let rec aux pos remaining =
    if remaining = 0 then ()
    else
      let bytes_read = In_channel.input in_channel ~buf ~pos ~len:remaining in
      if bytes_read = 0 then failwith "Unexpected EOF while reading input"
      else aux (pos + bytes_read) (remaining - bytes_read)
  in
  aux 0 n ; buf

let write_length out_channel len =
  let bytes = Bytes.create 4 in
  Bytes.set bytes 0 (Char.of_int_exn ((len lsr 24) land 0xFF)) ;
  Bytes.set bytes 1 (Char.of_int_exn ((len lsr 16) land 0xFF)) ;
  Bytes.set bytes 2 (Char.of_int_exn ((len lsr 8) land 0xFF)) ;
  Bytes.set bytes 3 (Char.of_int_exn (len land 0xFF)) ;
  Out_channel.output_bytes out_channel bytes

let read_length in_channel =
  let len_bytes = read_exactly in_channel 4 in
  let b0 = Char.to_int (Bytes.get len_bytes 0) in
  let b1 = Char.to_int (Bytes.get len_bytes 1) in
  let b2 = Char.to_int (Bytes.get len_bytes 2) in
  let b3 = Char.to_int (Bytes.get len_bytes 3) in
  (b0 lsl 24) lor (b1 lsl 16) lor (b2 lsl 8) lor b3

let rec loop () =
  try
    let len = read_length In_channel.stdin in
    let cmd_bytes = read_exactly In_channel.stdin len in
    let action = Bin_prot.Reader.of_bytes Action.bin_reader_t cmd_bytes in
    let output = handle_action action in
    let output_bytes = Bin_prot.Writer.to_bytes Output.bin_writer_t output in
    let output_len = Bytes.length output_bytes in

    write_length Out_channel.stdout output_len ;
    Out_channel.output_bytes Out_channel.stdout output_bytes ;
    Out_channel.flush Out_channel.stdout ;

    match action with Action.Exit -> () | _ -> loop ()
  with
  | End_of_file ->
      () (* Gracefully handle EOF *)
  | exn ->
      let msg = Exn.to_string exn in
      let bt = Printexc.get_backtrace () in
      eprintf "Exception: %s\n%s\n" msg bt ;
      loop ()

let execute_subcommand =
  Command.basic
    ~summary:
      "Execute actions based on binprot-encoded commands from stdin in a loop"
    Command.Let_syntax.(
      let%map_open () = return () in
      fun () -> loop ())

let () =
  Command.run
    (Command.group ~summary:"transaction_fuzzer"
       [ (Parallel.worker_command_name, Parallel.worker_command)
       ; ("execute", execute_subcommand)
       ] )
