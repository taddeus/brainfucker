About
=====

This is a minimal compiler for the
[Brainfuck](https://en.wikipedia.org/wiki/Brainfuck) language, written for the
purpose of practicing OCaml LLVM bindings and seeing how well LLVM optimizes
arrays. Brainfuck commands are transformed to LLVM IR, which is generated in
such a way that it is easy to optimize for LLVM's `opt` utility.


Building and usage
==================

Building the `bf` compiler (Debian dependencies):

    $ sudo apt-get install ocaml llvm-3.4 libllvm-3.4-ocaml-dev
    $ make

Building a Brainfuck program (plain and optimized):

    $ make hello hello-opt  # compile file "hello.b" to binaries
    $ ./hello
    Hello World!
    $ ./hello-opt
    Hello World!

Quick compilation and running (deletes temporary binary after running):

    $ echo ++++++++++++. | ./run.sh
    $ ./run.sh < hello.b
    Hello World!

Examining generated LLVM:

    $ echo ++++++++++++. | ./bf
    ...
    $ echo ++++++++++++. | ./bf | opt -O3 -S
    ...


Optimization example
--------------------

The `text.py` utility generates single-cell Brainfuck code for a given text:

    $ ./text.py Hello World!
    ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++.
    +++++++++++++++++++++++++++++.
    +++++++.
    .
    +++.
    -------------------------------------------------------------------------------.
    +++++++++++++++++++++++++++++++++++++++++++++++++++++++.
    ++++++++++++++++++++++++.
    +++.
    ------.
    --------.
    -------------------------------------------------------------------.
    -----------------------.

The compiler generates very verbose code:

    $ ./text.py Hello World! | ./bf
    ...

    define void @_start() {
    entry:
        ; initialization
        %mem = alloca [30000 x i8]
        %idx = alloca i32
        %0 = bitcast [30000 x i8]* %mem to i8*
        call void @llvm.memset.p0i8.i32(i8* %0, i8 0, i32 30000, i32 0, i1 false)
        store i32 0, i32* %idx

        ; command: +
        %1 = load i32* %idx
        %2 = getelementptr inbounds [30000 x i8]* %mem, i32 0, i32 %1
        %3 = load i8* %2
        %4 = add i8 %3, 1
        %5 = load i32* %idx
        %6 = getelementptr inbounds [30000 x i8]* %mem, i32 0, i32 %5
        store i8 %4, i8* %6

        ; command: +
        %7 = load i32* %idx
        %8 = getelementptr inbounds [30000 x i8]* %mem, i32 0, i32 %7
        %9 = load i8* %8
        %10 = add i8 %9, 1
        %11 = load i32* %idx
        %12 = getelementptr inbounds [30000 x i8]* %mem, i32 0, i32 %11
        store i8 %10, i8* %12

        ...

        ; command: . (outputs 'H' after 72 times a '+' command)
        %433 = load i32* %idx
        %434 = getelementptr inbounds [30000 x i8]* %mem, i32 0, i32 %433
        %435 = load i8* %434
        %436 = call i32 @putchar(i8 %435)

        ...

        call void @exit(i32 0)
        ret void
    }

The LLVM optimization engine is able to completely optimize away array accesses
using constant propagation/folding. In the absence of loops, this effectively
evaluates the whole program at compile time:

    $ ./text.py Hello World! | ./bf | opt -O3 -S
    ...
    define void @_start() {
    entry:
        %0 = tail call i32 @putchar(i8 72)    ; H
        %1 = tail call i32 @putchar(i8 101)   ; e
        %2 = tail call i32 @putchar(i8 108)   ; l
        %3 = tail call i32 @putchar(i8 108)   ; l
        %4 = tail call i32 @putchar(i8 111)   ; o
        %5 = tail call i32 @putchar(i8 32)    ;
        %6 = tail call i32 @putchar(i8 87)    ; W
        %7 = tail call i32 @putchar(i8 111)   ; o
        %8 = tail call i32 @putchar(i8 114)   ; r
        %9 = tail call i32 @putchar(i8 108)   ; l
        %10 = tail call i32 @putchar(i8 100)  ; d
        %11 = tail call i32 @putchar(i8 33)   ; !
        %12 = tail call i32 @putchar(i8 10)   ; \n
        tail call void @exit(i32 0)
        ret void
    }
