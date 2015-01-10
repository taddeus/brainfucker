open Llvm

type program = command list
and command =
  | Shift of int
  | Goto of int
  | Add of int
  | Set of int
  | Out | In
  | Loop of program
  | Offset of int * command
  | Mul of int * int

let read_program ic =
  let rec next cur stack =
    try
      match input_char ic, stack with
      | '>', _ -> next (Shift 1 :: cur) stack
      | '<', _ -> next (Shift (-1) :: cur) stack
      | '+', _ -> next (Add 1 :: cur) stack
      | '-', _ -> next (Add (-1) :: cur) stack
      | '.', _ -> next (Out :: cur) stack
      | ',', _ -> next (In :: cur) stack
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
  | Shift 1            -> ">"
  | Shift -1           -> "<"
  | Shift n when n < 0 -> "(<" ^ string_of_int (-n) ^ ")"
  | Shift n            -> "(+" ^ string_of_int n ^ ")"
  | Goto n             -> "(_" ^ string_of_int n ^ ")"
  | Add 1              -> "+"
  | Add -1             -> "-"
  | Add n when n < 0   -> "(-" ^ string_of_int (-n) ^ ")"
  | Add n              -> "(+" ^ string_of_int n ^ ")"
  | Set n              -> "(=" ^ string_of_int n ^ ")"
  | Mul (x, y)         -> "(>" ^ string_of_int x ^ "*" ^ string_of_int y ^ ")"
  | Out                -> "."
  | In                 -> ","
  | Loop p             -> "[" ^ string_of_program p ^ "]"
  | Offset (o, cmd) ->
    "(" ^ string_of_int o ^ ":" ^ string_of_command cmd ^ ")"

let compile_llvm memsize program =
  let ctx = global_context () in
  let m = create_module ctx "brainfucker" in

  let byte_ty = i8_type ctx in
  let byteptr_ty = pointer_type byte_ty in
  let bool_ty = i1_type ctx in
  let i32_ty = i32_type ctx in
  let void_ty = void_type ctx in

  let memset =
    let arg_types = [|byteptr_ty; byte_ty; i32_ty; i32_ty; bool_ty|] in
    declare_function "llvm.memset.p0i8.i32" (function_type void_ty arg_types) m
  in
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
  let ptr = build_alloca byteptr_ty "ptr" b in

  let load p = build_load p "" b in
  let store p value = ignore (build_store value p b) in
  let gep n = build_in_bounds_gep (load ptr) [|i32 n|] "" b in

  let rec compile_command = function
    | Shift n ->
      store ptr (gep n)
    | Goto n ->
      let memptr = build_in_bounds_gep mem [|i32 0; i32 n|] "" b in
      build_bitcast memptr byteptr_ty "" b |> store ptr
    | Offset (o, Add n) ->
      build_add (load (gep o)) (i8 n) "" b |> store (gep o)
    | Offset (o, Set n) ->
      store (gep o) (i8 n)
    | Offset (o, Out) ->
      build_call putchar [|load (gep o)|] "" b |> ignore
    | Offset (o, In) ->
      build_call getchar [||] "" b |> store (gep o)
    | Offset (o, Mul (x, y)) ->
      let mul = build_mul (load (gep (o + x))) (i8 y) "" b in
      build_add (load (gep o)) mul "" b |> store (gep o)
    | (Add _ | Set _ | Out | In | Mul _) as cmd ->
      compile_command (Offset (0, cmd))
    | Loop p ->
      let bb_end = append_block ctx "" f in
      move_block_after !bb_cur bb_end;
      let bb_body = insert_block ctx "" bb_end in
      let bb_cond = insert_block ctx "" bb_body in

      build_br bb_cond b |> ignore;
      position_at_end bb_cond b;
      let cond = build_icmp Icmp.Eq (load (gep 0)) (i8 0) "" b in
      build_cond_br cond bb_end bb_body b |> ignore;

      set_cur_bb bb_body;
      List.iter compile_command p;
      build_br bb_cond b |> ignore;

      set_cur_bb bb_end
    | cmd ->
      failwith ("cannot compile: " ^ string_of_command cmd)
  in

  (* zero-initialize memory (use intrinsic for optimization assumptions) *)
  set_data_layout "e" m;  (* little-endian, needed for optimization *)
  let memptr = build_bitcast mem byteptr_ty "" b in
  build_call memset [|memptr; i8 0; i32 memsize; i32 0; i 1 0|] "" b |> ignore;

  (* set pivot to index 0 and compile program commands *)
  build_in_bounds_gep mem [|i32 0; i32 0|] "" b |> store ptr;
  List.iter compile_command program;

  (* exit gracefully *)
  build_call cexit [|i32 0|] "" b |> ignore;
  build_ret_void b |> ignore;
  m

let compile_c memsize program =
  let indent = Str.global_replace (Str.regexp "^\\(.\\)") "    \\1" in
  let ptr o = "p[" ^ string_of_int o ^ "]" in
  let add = function
    | 1            -> "++"
    | -1           -> "--"
    | n when n < 0 -> " -= " ^ string_of_int (-n)
    | n            -> " += " ^ string_of_int n
  in
  let rec compile_commands buf = function
    | [] -> buf
    | cmd :: tl -> compile_commands (buf ^ compile_command cmd ^ "\n") tl
  and compile_command = function
    | Loop p ->
      "while (*p) {\n" ^ indent (compile_commands "" p) ^ "}"
    | Offset (o, cmd) ->
      begin
        match cmd with
        | Shift n     -> "p" ^ add n
        | Add n       -> ptr o ^ add n
        | Goto 0      -> "p = mem"
        | Goto n      -> "p = mem + " ^ string_of_int n
        | Set n       -> ptr o ^ " = " ^ string_of_int n
        | Out         -> "putchar(" ^ ptr o ^ ")"
        | In          -> ptr o ^ " = getchar()"
        | Mul (x, 1)  -> ptr o ^ " += " ^ ptr (o + x)
        | Mul (x, -1) -> ptr o ^ " -= " ^ ptr (o + x)
        | Mul (x, y)  -> ptr o ^ " += " ^ ptr (o + x) ^ " * " ^ string_of_int y
        | _           -> failwith "cannot compile: " ^ string_of_command cmd
      end ^ ";"
    | cmd ->
      compile_command (Offset (0, cmd))
  in
  "#include <stdio.h>\n" ^
  "#include <stdlib.h>\n" ^
  "void _start() {\n" ^
  "    unsigned char mem[" ^ string_of_int memsize ^ "] = {}, *p = mem;\n" ^
       indent (compile_commands "" program) ^
  "    exit(0);\n" ^
  "}\n"

let optimize program =
  let opt_loop p =
    let rec next buf counter_found = function
      | Add -1 :: tl when not counter_found ->
        next buf true tl
      | Offset (o, Add n) :: tl ->
        next (Offset (o, Mul (-o, n)) :: buf) counter_found tl
      | [] when counter_found ->
        List.rev (Offset (0, Set 0) :: buf)
      | _ ->
        [Loop p]
    in
    next [] false p
  in
  let can_offset = function
    | Add _ | Set _ | Out | In | Mul _ -> true
    | _ -> false
  in
  let rec opt = function
    | Shift a :: Shift b :: tl ->
      Shift (a + b) :: tl |> opt
    | Add a :: Add b :: tl ->
      Add (a + b) :: tl |> opt

    | Set 0 :: Loop _ :: tl ->
      Set 0 :: tl |> opt

    | Goto a :: Shift b :: tl ->
      Goto (a + b) :: tl |> opt
    | Set a :: Add b :: tl ->
      Set (a + b) :: tl |> opt

    | (Shift 0 | Add 0) :: tl
    | (Shift _ | Goto _) :: (Goto _ :: _ as tl)
    | (Add _ | Set _) :: (Set _ :: _ as tl) ->
      opt tl

    | Goto o :: cmd :: tl when can_offset cmd ->
      Offset (o, cmd) :: Goto o :: tl |> opt
    | Shift o :: cmd :: tl when can_offset cmd ->
      Offset (o, cmd) :: Shift o :: tl |> opt

    | Offset (a, Offset (b, cmd)) :: tl ->
      Offset (a + b, cmd) :: tl |> opt
    | Offset (0, cmd) :: tl ->
      cmd :: tl |> opt

    | Offset (i, a) :: Offset (j, b) :: tl when i = j ->
      begin match opt [a; b] with
      | [cmd] -> Offset (i, cmd) :: tl |> opt
      | _ -> Offset (i, a) :: opt (Offset (j, b) :: tl)
      end

    | Shift i :: Offset (j, cmd) :: tl ->
      Offset (i + j, cmd) :: Shift i :: tl |> opt

    | Shift i :: cmd :: tl when can_offset cmd ->
      Offset (i, cmd) :: Shift i :: tl |> opt

    | Loop [Add (1 | -1)] :: tl ->
      Set 0 :: tl |> opt

    | Loop p :: tl ->
      begin match opt_loop (check_change p) with
      | [Loop _ as loop] -> loop :: opt tl
      | replacement -> opt (replacement @ tl)
      end

    | hd :: tl -> hd :: opt tl
    | [] -> []
  and check_change program =
    match opt program with
    | p when p <> program -> check_change p
    | p -> p
  in
  match check_change (Set 0 :: program) with Set 0 :: p | p -> p

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  stdin |> read_program
  |> (if List.mem "-o" args then optimize else fun p -> p)
  |> fun program ->
    if List.mem "-e" args then
      program |> string_of_program |> print_endline
    else if List.mem "-c" args then
      program |> compile_c 30000 |> print_string
    else
      program |> compile_llvm 30000 |> string_of_llmodule |> print_string
