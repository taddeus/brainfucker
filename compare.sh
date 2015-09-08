#!/usr/bin/env bash
if [ $# -eq 1 ]
then
    basename=`echo $1 | sed 's/.b$//'`
else
    basename=_tmp
    cat > ${basename}.b
fi

mytime () {
    (`which time` -f %e $1 > /dev/null) 2>&1
}

compile () {
    echo -n "compiling $1... "
    t=`mytime "make -s $basename-$1"`
    echo "took $t seconds"
}

set -e

compile plain
compile opt
compile c
compile nayuki

echo "plain:  `mytime ./$basename-plain`"
echo "opt:    `mytime ./$basename-opt`"
echo "c:      `mytime ./$basename-c`"
echo "nayuki: `mytime ./$basename-nayuki`"

rm -f _tmp*
