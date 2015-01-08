open Llvm

type program = command list
and command =
  | Incptr | Decptr
  | Incdata | Decdata
  | Output | Input
  | Loop of program

let read_program ic =
  let rec next cur stack =
    try
      match input_char ic, stack with
      | '>', _ -> next (Incptr :: cur) stack
      | '<', _ -> next (Decptr :: cur) stack
      | '+', _ -> next (Incdata :: cur) stack
      | '-', _ -> next (Decdata :: cur) stack
      | '.', _ -> next (Output :: cur) stack
      | ',', _ -> next (Input :: cur) stack
      | '[', _ -> next [] (cur :: stack)
      | ']', [] -> failwith "unmatched ']'"
      | ']', (hd :: tl) -> next (Loop (List.rev cur) :: hd) tl
      | _ -> next cur stack
    with End_of_file ->
      if List.length stack > 0 then failwith "unmatched '['";
      List.rev cur
  in
  next [] []

let rec string_of_program program =
  let string_of_command = function
    | Incptr  -> ">"
    | Decptr  -> "<"
    | Incdata -> "+"
    | Decdata -> "-"
    | Output  -> "."
    | Input   -> ","
    | Loop p  -> "[" ^ string_of_program p ^ "]"
  in
  let rec cat buf = function
    | [] -> buf
    | cmd :: tl -> cat (buf ^ string_of_command cmd) tl
  in
  cat "" program

let compile memsize program =
  let ctx = global_context () in
  let m = create_module ctx "brainfucker" in

  let byte_ty = i8_type ctx in
  let byteptr_ty = pointer_type byte_ty in
  let i1_ty = i1_type ctx in
  let i32_ty = i32_type ctx in
  let int_ty = i32_ty in
  let void_ty = void_type ctx in

  let putchar = declare_function "putchar" (function_type int_ty [|byte_ty|]) m in
  let getchar = declare_function "getchar" (function_type byte_ty [||]) m in

  let f = define_function "_start" (function_type void_ty [||]) m in
  let bb_cur = ref (entry_block f) in
  let b = builder_at_end ctx !bb_cur in

  let set_cur_bb bb =
    position_at_end bb b;
    bb_cur := bb
  in

  let i n = const_int int_ty n in
  let i8 n = const_int byte_ty n in

  (*let mem = define_global "mem" (const_null (array_type byte_ty memsize)) m in
  set_linkage Linkage.Private mem;*)
  let mem = build_alloca (array_type byte_ty memsize) "mem" b in
  let idx = build_alloca int_ty "idx" b in

  let gep () = build_in_bounds_gep mem [|i 0; build_load idx "" b|] "" b in
  let load ptr = build_load ptr "" b in
  let store ptr value = ignore (build_store value ptr b) in

  let rec compile_command = function
    | Incptr ->
      build_add (load idx) (i 1) "" b |> store idx
    | Decptr ->
      build_sub (load idx) (i 1) "" b |> store idx
    | Incdata ->
      build_add (load (gep ())) (i8 1) "" b |> store (gep ())
    | Decdata ->
      build_sub (load (gep ())) (i8 1) "" b |> store (gep ())
    | Output ->
      build_call putchar [|load (gep ())|] "" b |> ignore
    | Input ->
      build_call getchar [||] "" b |> store (gep ())
    | Loop p ->
      let bb_end = append_block ctx "" f in
      move_block_after !bb_cur bb_end;
      let bb_body = insert_block ctx "" bb_end in
      let bb_cond = insert_block ctx "" bb_body in

      ignore (build_br bb_cond b);
      position_at_end bb_cond b;
      let cond = build_icmp Icmp.Eq (load (gep ())) (i8 0) "" b in
      ignore (build_cond_br cond bb_end bb_body b);

      set_cur_bb bb_body;
      List.iter compile_command p;
      ignore (build_br bb_cond b);

      set_cur_bb bb_end
  in

  (* zero-initialize memory (use intrinsic for optimization assumptions) *)
  set_data_layout "e" m;  (* little-endian, needed for optimization *)
  let memset =
    let arg_types = [|byteptr_ty; byte_ty; i32_ty; i32_ty; i1_ty|] in
    declare_function "llvm.memset.p0i8.i32" (function_type void_ty arg_types) m
  in
  let ptr = build_bitcast mem byteptr_ty "" b in
  build_call memset [|ptr; i8 0; i memsize; i 0; const_int i1_ty 0|] "" b |> ignore;

  (* set pivot to index 0 and compile program commands *)
  store idx (i 0);
  List.iter compile_command program;

  (* exit gracefully *)
  let cexit = declare_function "exit" (function_type void_ty [|i32_ty|]) m in
  ignore (build_call cexit [|i 0|] "" b);
  ignore (build_ret_void b);
  m

let () =
  stdin |> read_program |> compile 30000 |> string_of_llmodule |> print_string
