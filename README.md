About
=====

This is a minimal compiler for the
[Brainfuck](https://en.wikipedia.org/wiki/Brainfuck) language, written for the
purpose of practicing OCaml LLVM bindings and seeing how well LLVM optimizes
arrays. Brainfuck commands are transformed to [LLVM
IR](http://llvm.org/docs/LangRef.html), which is generated in such a way that
it is easy to optimize for LLVM's `opt` utility.

The (only) source file `bf.ml` pretty much explains itself. `hello.b` and
`rot13.b` can be used for quick testing as demonstrated below.


Building and usage
==================

Building the `bf` compiler (Debian dependencies, replace 3.4 with the version
of the `llvm` package):

    $ sudo apt-get install ocaml llvm libllvm-3.4-ocaml-dev
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
        %ptr = alloca i8*
        %0 = bitcast [30000 x i8]* %mem to i8*
        call void @llvm.memset.p0i8.i32(i8* %0, i8 0, i32 30000, i32 0, i1 false)
        %1 = getelementptr inbounds [30000 x i8]* %mem, i32 0, i32 0
        store i8* %1, i8** %ptr

        ; command: +
        %2 = load i8** %ptr
        %3 = getelementptr inbounds i8* %2, i32 0
        %4 = load i8* %3
        %5 = add i8 %4, 1
        %6 = load i8** %ptr
        %7 = getelementptr inbounds i8* %6, i32 0
        store i8 %5, i8* %7

        ; command: +
        %8 = load i8** %ptr
        %9 = getelementptr inbounds i8* %8, i32 0
        %10 = load i8* %9
        %11 = add i8 %10, 1
        %12 = load i8** %ptr
        %13 = getelementptr inbounds i8* %12, i32 0
        store i8 %11, i8* %13

        ...

        ; command: . (outputs 'H' after 72 times a '+' command)
        %434 = load i8** %ptr
        %435 = getelementptr inbounds i8* %434, i32 0
        %436 = load i8* %435
        %437 = call i32 @putchar(i8 %436)

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
