#!/usr/bin/env python3
"""Measure one process's CPU time delta; 100% means one busy CPU core."""
import argparse
import json
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('pid', type=int)
parser.add_argument('--seconds', type=float, default=20)
parser.add_argument('--label', default='')
args = parser.parse_args()
if args.seconds <= 0:
    parser.error('--seconds must be positive')

def cpu_time():
    value = subprocess.check_output(['ps', '-p', str(args.pid), '-o', 'time='], text=True).strip()
    return sum(float(part) * 60 ** index for index, part in enumerate(reversed(value.split(':'))))

before = cpu_time()
start = time.monotonic()
time.sleep(args.seconds)
delta = cpu_time() - before
elapsed = time.monotonic() - start
print(json.dumps({'label': args.label, 'pid': args.pid, 'elapsed_seconds': round(elapsed, 2),
                  'cpu_seconds': round(delta, 3), 'cpu_percent_one_core': round(delta / elapsed * 100, 2)}))
