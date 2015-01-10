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
set -e

echo -n "compiling opt..."
make -s $basename-opt
echo done

echo -n "compiling c..."
make -s $basename-c
echo done

echo -n "compiling nayuki..."
make -s $basename-nayuki
echo done

echo "opt:    `mytime ./$basename-opt`"
echo "c:      `mytime ./$basename-c`"
echo "nayuki: `mytime ./$basename-nayuki`"

rm -f _tmp*
