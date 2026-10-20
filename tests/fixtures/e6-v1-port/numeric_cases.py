"""Dedicated canonical bytes against Python across IEEE-754 and integer edges."""
import json
import math
import random
import struct
import subprocess


def run(parity):
    randomizer = random.Random(139)
    values = [0.0, -0.0, 1.0, 80.0, 1e-6, 1e-5, 1e-4, 1e15, 1e16, 1e20, 1e21, 5e-324,
              9007199254740993, -(10**100), float('inf'), float('-inf'), float('nan')]
    for _ in range(2048):
        value = struct.unpack('>d', randomizer.randbytes(8))[0]
        if math.isfinite(value): values.append(value)
    raw = json.dumps(values)
    script = "import {readFileSync} from 'node:fs'; import {parse,dumps,canonical} from './04-validate-handoff/autobahn/lib/json.mjs'; for(const v of parse(readFileSync(0,'utf8'))) console.log(dumps(v,null,true,true)+'\\t'+canonical(v));"
    result = subprocess.run(['node', '--input-type=module', '-e', script], input=raw, text=True, capture_output=True)
    lines = result.stdout.splitlines()
    expected = [json.dumps(value, sort_keys=True, separators=(',', ':')) for value in values]
    expected = [value + '\t' + parity.sha256(value.encode()) for value in expected]
    parity.same('IEEE-754/integer canonical corpus (%d values)' % len(values), (0, ('\n'.join(expected)+'\n').encode(), b''), (result.returncode, result.stdout.encode(), result.stderr.encode()))
    print('canonical_numeric_values=%d' % len(values))
