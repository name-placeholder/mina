open Core
open Async

module Verify_block_proof = struct
  open Blockchain_snark
  open Mina_state

  let parse_json_or_binprot_file path =
    if String.equal path "quit" then Stdlib.exit 0 ;
    Stdlib.Printf.printf "Parsing.\n%!" ;
    let data = In_channel.read_all path in
    if String.is_prefix data ~prefix:"{" then
      let result =
        Mina_block.Header.Stable.V2.of_yojson (Yojson.Safe.from_string data)
      in
      Result.map_error result ~f:(fun err -> "JSON parsing failure: " ^ err)
    else
      try
        let result =
          Bin_prot.Reader.of_string Mina_block.Header.Stable.V2.bin_reader_t
            data
        in
        Ok result
      with exn -> Error (Exn.to_string exn)

  let get_input file =
    let input =
      match file with
      | None ->
          Stdlib.Printf.printf "Input path/to/file.[json|binprot]:\n%!" ;
          let input_line = Stdlib.input_line Stdlib.stdin in
          parse_json_or_binprot_file input_line
      | Some file ->
          parse_json_or_binprot_file file
    in
    Result.map input ~f:(fun header ->
        let proof = Mina_block.Header.protocol_state_proof header in
        let state = Mina_block.Header.protocol_state header in
        let delta_block_chain_proof =
          Mina_block.Header.delta_block_chain_proof header
        in
        let previous_state_hash =
          Protocol_state.previous_state_hash (Obj.magic (Obj.repr state))
        in
        (state, proof, previous_state_hash, delta_block_chain_proof) )

  let run () =
    Random.self_init () ;
    Stdlib.Printf.printf "Starting verifier\n%!" ;
    let files = ref @@ List.tl_exn @@ Array.to_list @@ Sys.get_argv () in
    Stdlib.Printf.printf "Module name: %s\n%!" __MODULE__ ;
    Stdlib.Printf.printf "To set a breakpoint in this file: break @ %s LINE\n%!"
      __MODULE__ ;
    let proof_level = Genesis_constants.Proof_level.compiled in
    let constraint_constants =
      Genesis_constants.Constraint_constants.compiled
    in
    Stdlib.Printf.printf "Compiling transaction snark module...\n%!" ;
    let before_time = Unix.gettimeofday () in
    let module T = Transaction_snark.Make (struct
      let constraint_constants = constraint_constants

      let proof_level = proof_level
    end) in
    let after_time = Unix.gettimeofday () in
    Stdlib.Printf.printf "Transaction snark module creation time: %fs\n%!"
      (after_time -. before_time) ;
    Stdlib.Printf.printf "Compiling blockchain snark module...\n%!" ;
    let before_time = Unix.gettimeofday () in
    let module B = Blockchain_snark_state.Make (struct
      let tag = T.tag

      let constraint_constants = constraint_constants

      let proof_level = proof_level
    end) in
    let after_time = Unix.gettimeofday () in
    Stdlib.Printf.printf "Blockchain snark module creation time: %fs\n%!"
      (after_time -. before_time) ;
    let verify = B.Proof.verify in
    let pop_file () =
      match !files with
      | [] ->
          None
      | file :: rest ->
          files := rest ;
          Some file
    in
    let rec loop () =
      let next_file = pop_file () in
      match get_input next_file with
      | Error err ->
          Stdlib.Printf.printf "Error processing input: %s\n%!" err ;
          loop ()
      | Ok (state, proof, previous_state_hash, delta_block_chain_proof) -> (
          Stdlib.Printf.printf "Calling verifier.\n%!" ;
          let before_time = Unix.gettimeofday () in
          let result = verify [ (state, proof) ] in
          let after_time = Unix.gettimeofday () in
          Stdlib.Printf.printf "Verification time: %fs\n%!"
            (after_time -. before_time) ;
          match%bind result with
          | Ok () ->
              Stdlib.Printf.printf "Proofs verified successfully.\n%!" ;
              let tfvr =
                Transition_chain_verifier.verify
                  ~target_hash:previous_state_hash
                  ~transition_chain_proof:delta_block_chain_proof
              in
              ( match tfvr with
              | None ->
                  Stdlib.Printf.printf
                    "Failed to verify delta block chain proof.\n%!"
              | Some _ ->
                  Stdlib.Printf.printf
                    "Delta block chain proof verified successfully.\n%!" ) ;
              loop ()
          | Error err ->
              Stdlib.Printf.printf "Proofs failed to verify: %s\n%!"
                (Error.to_string_hum err) ;
              loop () )
    in
    loop ()
end

module Verify_zkapp_proof = struct
  let parse_json_or_binprot_file path =
    if String.equal path "quit" then Stdlib.exit 0 ;
    Stdlib.Printf.printf "Parsing.\n%!" ;
    let data = In_channel.read_all path in
    try
      let result :
          Pickles.Side_loaded.Verification_key.t
          * Mina_base.Zkapp_statement.t
          * Pickles.Side_loaded.Proof.t =
        Bin_prot.Reader.of_string
          (Bin_prot.Type_class.bin_reader_triple
             Pickles.Side_loaded.Verification_key.Stable.V2.bin_reader_t
             Mina_base.Zkapp_statement.Stable.V2.bin_reader_t
             Pickles.Side_loaded.Proof.Stable.V2.bin_reader_t )
          data
      in
      Ok result
    with exn -> Error (Exn.to_string exn)

  let get_input file =
    let input =
      match file with
      | None ->
          Stdlib.Printf.printf "Input path/to/file.[json|binprot]:\n%!" ;
          let input_line = Stdlib.input_line Stdlib.stdin in
          parse_json_or_binprot_file input_line
      | Some file ->
          parse_json_or_binprot_file file
    in
    input

  let run () =
    Random.self_init () ;
    Stdlib.Printf.printf "Starting verifier\n%!" ;
    let files = ref @@ List.tl_exn @@ Array.to_list @@ Sys.get_argv () in
    Stdlib.Printf.printf "Module name: %s\n%!" __MODULE__ ;
    Stdlib.Printf.printf "To set a breakpoint in this file: break @ %s LINE\n%!"
      __MODULE__ ;
    let proof_level = Genesis_constants.Proof_level.compiled in
    let constraint_constants =
      Genesis_constants.Constraint_constants.compiled
    in
    (* NOTE: this module is not used but for some reason we need to initializ
       a snark module to avoid a "pre-computed committed lagrange bases not found" error later *)
    Stdlib.Printf.printf "Compiling transaction snark module...\n%!" ;
    let before_time = Unix.gettimeofday () in
    let module T = Transaction_snark.Make (struct
      let constraint_constants = constraint_constants

      let proof_level = proof_level
    end) in
    let after_time = Unix.gettimeofday () in
    Stdlib.Printf.printf "Transaction snark module creation time: %fs\n%!"
      (after_time -. before_time) ;
    let pop_file () =
      match !files with
      | [] ->
          None
      | file :: rest ->
          files := rest ;
          Some file
    in
    let rec loop () =
      let next_file = pop_file () in
      match get_input next_file with
      | Error err ->
          Stdlib.Printf.printf "Error processing input: %s\n%!" err ;
          loop ()
      | Ok (vk, statement, proof) -> (
          Stdlib.Printf.printf "Calling verifier.\n%!" ;
          let before_time = Unix.gettimeofday () in
          let result =
            Pickles.Side_loaded.verify ~typ:Mina_base.Zkapp_statement.typ
              [ (vk, statement, proof) ]
          in
          let after_time = Unix.gettimeofday () in
          Stdlib.Printf.printf "Verification time: %fs\n%!"
            (after_time -. before_time) ;
          match%bind result with
          | Ok () ->
              Stdlib.Printf.printf "Proofs verified successfully.\n%!" ;
              loop ()
          | Error err ->
              Stdlib.Printf.printf "Proofs failed to verify: %s\n%!"
                (Error.to_string_hum err) ;
              loop () )
    in
    loop ()
end

let () =
  (* Change to fst for block proofs *)
  let run = snd (Verify_block_proof.run, Verify_zkapp_proof.run) in
  Command.async ~summary:"Run verifier" (Command.Param.return run)
  |> Command.run
