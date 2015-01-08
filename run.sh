#!/usr/bin/env bash
set -e
make -s bf
./bf | opt-3.5 -O3 -o prog.bc
make -s prog
./prog
rm -f prog{,.bc,.o}
