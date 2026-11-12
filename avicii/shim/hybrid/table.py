#!/usr/bin/env python3
"""Print the H/F ladder: expectation, build state, verify state, observed signature.

    table.py                     # table from out/
    table.py set TARGET RESULT   # record an observation, e.g. set h1 "parked, 94 s"
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cards import CARDS, ORDER  # noqa: E402

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')


def row(t):
    c = CARDS[t]
    img = f'{out}/{t}.img'
    build, passed, sha = 'MISSING', '-', '-'
    if os.path.exists(img) and os.path.getsize(img) == 100663296:
        build = 'built'
        if os.path.exists(img + '.sha256'):
            sha = open(img + '.sha256').read().split()[0][:16]
        if os.path.exists(img + '.verify'):
            txt = open(img + '.verify').read()
            passed = 'PASS' if any(l.startswith('PASS') for l in txt.splitlines()) else 'FAIL'
    res = '-'
    if os.path.exists(img + '.result'):
        res = open(img + '.result').read().strip()
    return f'| {t} | {c["code0"]} | {c["exp"]} | {build} | {passed} | {sha} | {res} |'


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'set':
        open(f'{out}/{sys.argv[2]}.img.result', 'w').write(sys.argv[3] + '\n')
        sys.exit(0)
    print('| img | code0 | expected | build | verify | sha256[:16] | observed |')
    print('|---|---|---|---|---|---|---|')
    for t in ORDER:
        print(row(t))
    imgs = [p for p in glob.glob(f'{out}/*.img') if os.path.getsize(p) == 100663296]
    print(f'\n{len(imgs)} image(s), all 100663296 B' if imgs else '\nno images')
