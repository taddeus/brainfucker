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

Building a brainfuck program (plain and optimized):

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
