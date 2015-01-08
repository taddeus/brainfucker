#!/usr/bin/env python
import sys

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print >>sys.stderr, 'usage: python %s STRING' % sys.argv[0]
        sys.exit(1)

    def cmd(c):
        return ('+' * c if c > 0 else '-' * -c) + '.'

    input_string = ' '.join(sys.argv[1:]) + '\n'
    ords = [0] + map(ord, input_string)
    diffs = [ords[i + 1] - c for i, c in enumerate(ords[:-1])]
    print '\n'.join(map(cmd, diffs))
