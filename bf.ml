open Llvm

type program = command list
and command =
  | Incptr | Decptr
  | Incdata | Decdata
  | Output | Input
  | Loop of program
  | Addptr of int
  | Adddata of int
  | Setptr of int
  | Setdata of int


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
  let rec cat buf = function
    | [] -> buf
    | cmd :: tl -> cat (buf ^ string_of_command cmd) tl
  in
  cat "" program
and string_of_command = function
  | Incptr  -> ">"
  | Decptr  -> "<"
  | Incdata -> "+"
  | Decdata -> "-"
  | Output  -> "."
  | Input   -> ","
  | Loop p  -> "[" ^ string_of_program p ^ "]"

  | Addptr n when n < 0  -> "(<" ^ string_of_int (-n) ^ ")"
  | Addptr n             -> "(>" ^ string_of_int n ^ ")"
  | Adddata n when n < 0 -> "(" ^ string_of_int n ^ ")"
  | Adddata n            -> "(+" ^ string_of_int n ^ ")"
  | Setptr n             -> "(<>" ^ string_of_int n ^ ")"
  | Setdata n            -> "(=" ^ string_of_int n ^ ")"

let compile memsize program =
  let ctx = global_context () in
  let m = create_module ctx "brainfucker" in

  let byte_ty = i8_type ctx in
  let byteptr_ty = pointer_type byte_ty in
  let bool_ty = i1_type ctx in
  let i32_ty = i32_type ctx in
  let void_ty = void_type ctx in

  let putchar = declare_function "putchar" (function_type i32_ty [|byte_ty|]) m in
  let getchar = declare_function "getchar" (function_type byte_ty [||]) m in
  let cexit = declare_function "exit" (function_type void_ty [|i32_ty|]) m in

  (* use custom _start symbol rather than main function to reduce complexity *)
  let f = define_function "_start" (function_type void_ty [||]) m in
  let bb_cur = ref (entry_block f) in
  let b = builder_at_end ctx !bb_cur in

  let set_cur_bb bb =
    position_at_end bb b;
    bb_cur := bb
  in

  let i w n = const_int (integer_type ctx w) n in
  let i8 = i 8 in
  let i32 = i 32 in

  let mem = build_alloca (array_type byte_ty memsize) "mem" b in
  let idx = build_alloca i32_ty "idx" b in

  let load ptr = build_load ptr "" b in
  let store ptr value = ignore (build_store value ptr b) in
  let gep () = build_in_bounds_gep mem [|i32 0; load idx|] "" b in

  let rec compile_command = function
    | Incptr ->
      build_add (load idx) (i32 1) "" b |> store idx
    | Decptr ->
      build_sub (load idx) (i32 1) "" b |> store idx
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

      build_br bb_cond b |> ignore;
      position_at_end bb_cond b;
      let cond = build_icmp Icmp.Eq (load (gep ())) (i8 0) "" b in
      build_cond_br cond bb_end bb_body b |> ignore;

      set_cur_bb bb_body;
      List.iter compile_command p;
      build_br bb_cond b |> ignore;

      set_cur_bb bb_end
    | Addptr n ->
      build_add (load idx) (i32 n) "" b |> store idx
    | Adddata n ->
      build_add (load (gep ())) (i8 n) "" b |> store (gep ())
    | Setptr n when n >= 0 ->
      store idx (i32 n)
    | Setdata n when n >= 0 ->
      store (gep ()) (i8 n)
    | cmd -> failwith ("invalid command: " ^ string_of_command cmd)
  in

  (* zero-initialize memory (use intrinsic for optimization assumptions) *)
  set_data_layout "e" m;  (* little-endian, needed for optimization *)
  let memset =
    let arg_types = [|byteptr_ty; byte_ty; i32_ty; i32_ty; bool_ty|] in
    declare_function "llvm.memset.p0i8.i32" (function_type void_ty arg_types) m
  in
  let ptr = build_bitcast mem byteptr_ty "" b in
  build_call memset [|ptr; i8 0; i32 memsize; i32 0; i 1 0|] "" b |> ignore;

  (* set pivot to index 0 and compile program commands *)
  store idx (i32 0);
  List.iter compile_command program;

  (* exit gracefully *)
  build_call cexit [|i32 0|] "" b |> ignore;
  build_ret_void b |> ignore;
  m

let compile_to_c memsize program =
  let indent = Str.global_replace (Str.regexp "^\\(.\\)") "    \\1" in
  let rec compile_commands buf = function
    | [] -> buf
    | cmd :: tl -> compile_commands (buf ^ compile_command cmd ^ "\n") tl
  and compile_command = function
    | Incptr    -> "idx++;"
    | Decptr    -> "idx--;"
    | Incdata   -> "mem[idx]++;"
    | Decdata   -> "mem[idx]--;"
    | Output    -> "putchar(mem[idx]);"
    | Input     -> "mem[idx] = getchar();"
    | Loop p    -> "while (mem[idx] != 0) {\n" ^ indent (compile_commands "" p) ^ "}"
    | Addptr n  -> "idx += " ^ string_of_int n ^ ";"
    | Adddata n -> "mem[idx] += " ^ string_of_int n ^ ";"
    | Setptr n  -> "idx = " ^ string_of_int n ^ ";"
    | Setdata n -> "mem[idx] = " ^ string_of_int n ^ ";"
  in
  "#include <stdio.h>\n" ^
  "#include <stdlib.h>\n" ^
  "void _start() {\n" ^
  "    unsigned char mem[" ^ string_of_int memsize ^ "] = {};\n" ^
  "    unsigned idx = 0;\n" ^
       indent (compile_commands "" program) ^
  "    exit(0);\n" ^
  "}\n"

let rec optimize program =
  let rec opt = function
    | Incptr :: tl -> opt (Addptr 1 :: tl)
    | Decptr :: tl -> opt (Addptr (-1) :: tl)
    | Incdata :: tl -> opt (Adddata 1 :: tl)
    | Decdata :: tl -> opt (Adddata (-1) :: tl)

    | Addptr a :: Addptr b :: tl -> opt (Addptr (a + b) :: tl)
    | Adddata a :: Adddata b :: tl -> opt (Adddata (a + b) :: tl)

    | Loop [Addptr -1] :: tl -> opt (Setptr 0 :: tl)
    | Loop [Adddata (1 | -1)] :: tl -> opt (Setdata 0 :: tl)

    | (Addptr 0 | Adddata 0) :: tl
    | (Addptr _ | Setptr _) :: (Setptr _ :: _ as tl)
    | (Adddata _ | Setdata _) :: (Setdata _ :: _ as tl) -> opt tl

    | Loop p :: tl -> Loop (optimize p) :: opt tl
    | hd :: tl -> hd :: opt tl
    | [] -> []
  in
  match opt program with
  | p when p <> program -> optimize p
  | p -> p

let rec flatten = function
  | Addptr 1 :: tl     -> Incptr :: flatten tl
  | Addptr (-1) :: tl  -> Decptr :: flatten tl
  | Adddata 1 :: tl    -> Incdata :: flatten tl
  | Adddata (-1) :: tl -> Decdata :: flatten tl
  | Loop p :: tl -> Loop (flatten p) :: flatten tl
  | hd :: tl -> hd :: flatten tl
  | [] -> []

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  stdin |> read_program
  |> (if List.mem "-o" args then optimize else fun p -> p)
  |> fun program ->
    if List.mem "-e" args then
      program |> flatten |> string_of_program |> print_endline
    else if List.mem "-c" args then
      program |> flatten |> compile_to_c 30000 |> print_string
    else
      program |> compile 30000 |> string_of_llmodule |> print_string
