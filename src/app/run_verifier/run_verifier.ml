open Core
open Async
open Blockchain_snark
open Mina_base
open Mina_state

let parse_json data =
  if String.is_prefix data ~prefix:"[" then
    [%derive.of_yojson: Blockchain_snark.Blockchain.t list]
      (Yojson.Safe.from_string data)
  else
    Result.map
      ~f:(fun bc -> [ bc ])
      ([%derive.of_yojson: Blockchain_snark.Blockchain.t]
         (Yojson.Safe.from_string data) )

let parse_json_or_binprot_file path =
  if String.equal path "quit" then Stdlib.exit 0 ;
  Stdlib.Printf.printf "Parsing.\n%!" ;
  let data = In_channel.read_all path in
  if String.is_prefix data ~prefix:"[" || String.is_prefix data ~prefix:"{" then
    let result = parse_json data in
    Result.map_error result ~f:(fun err -> err)
  else
    try
      let result =
        Bin_prot.Reader.of_string
          Blockchain_snark.Blockchain.Stable.Latest.bin_reader_t data
      in
      Ok [ result ]
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
  Result.map input ~f:(fun input ->
      List.map input ~f:(fun snark ->
          ( Blockchain_snark.Blockchain.state snark
          , Blockchain_snark.Blockchain.proof snark ) ) )

let run () =
  let files = ref @@ List.tl_exn @@ Array.to_list @@ Sys.get_argv () in
  Stdlib.Printf.printf "Module name: %s\n%!" __MODULE__ ;
  Stdlib.Printf.printf "To set a breakpoint in this file: break @ %s LINE\n%!"
    __MODULE__ ;
  let proof_level = Genesis_constants.Proof_level.compiled in
  let constraint_constants = Genesis_constants.Constraint_constants.compiled in
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
  let verify : (Protocol_state.Value.t * Proof.t) list -> bool =
    B.Proof.verify
  in
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
    | Ok input -> (
        Stdlib.Printf.printf "Calling verifier.\n%!" ;
        let before_time = Unix.gettimeofday () in
        let result = verify input in
        let after_time = Unix.gettimeofday () in
        Stdlib.Printf.printf "Verification time: %fs\n%!"
          (after_time -. before_time) ;
        match result with
        | true ->
            Stdlib.Printf.printf "Proofs verified successfully.\n%!" ;
            loop ()
        | false ->
            Stdlib.Printf.printf "Proofs failed to verify.\n%!" ;
            loop () )
  in
  loop ()

let () =
  Random.self_init () ;
  Stdlib.Printf.printf "Starting verifier\n%!" ;
  run ()
