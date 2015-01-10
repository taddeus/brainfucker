#!/usr/bin/env bash
set -e
cat > _tmp.b
make -s _tmp-opt
./_tmp-opt
rm -f _tmp*
