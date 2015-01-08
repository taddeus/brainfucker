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

The `text.py` utility genrates single-cell Brainfuck code for a given text:

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

The LLVM optimization engine is able to completely optimize away array accesses
(in the absence of loops):

    $ ./text.py Hello World! | ./bf | opt -O3 -S
    ; ModuleID = '<stdin>'
    target datalayout = "e"

    ; Function Attrs: nounwind
    declare i32 @putchar(i8) #0

    declare void @exit(i32)

    define void @_start() {
    entry:
        %0 = tail call i32 @putchar(i8 72)
        %1 = tail call i32 @putchar(i8 101)
        %2 = tail call i32 @putchar(i8 108)
        %3 = tail call i32 @putchar(i8 108)
        %4 = tail call i32 @putchar(i8 111)
        %5 = tail call i32 @putchar(i8 32)
        %6 = tail call i32 @putchar(i8 87)
        %7 = tail call i32 @putchar(i8 111)
        %8 = tail call i32 @putchar(i8 114)
        %9 = tail call i32 @putchar(i8 108)
        %10 = tail call i32 @putchar(i8 100)
        %11 = tail call i32 @putchar(i8 33)
        %12 = tail call i32 @putchar(i8 10)
        tail call void @exit(i32 0)
        ret void
    }

    attributes #0 = { nounwind }

