#!/usr/bin/env python3
"""Portable structural audit only; it does NOT certify Julia/Ada execution."""
from pathlib import Path
import hashlib, re, sys
r=Path(__file__).resolve().parent.parent
manifest=r/'MANIFEST.sha256'
if not manifest.is_file(): raise SystemExit('manifest absent')
rows=manifest.read_text().splitlines()
for entry in rows:
    match=re.fullmatch(r'([0-9a-f]{64})  (.+)',entry)
    if not match: raise SystemExit('bad manifest line')
    expected,name=match.groups()
    f=r/name
    if not f.is_file() or hashlib.sha256(f.read_bytes()).hexdigest()!=expected:
        raise SystemExit('hash failure: '+name)
source=(r/'src'/'organism.jl').read_text()
assert 'BF.act!(h.left,env,a' in source, 'missing mandatory gate-backed dispatch'
assert 'transition!(env' not in source, 'direct adapter bypass in new organism'
assert 'permission::Int=1' in source
assert (r/'vendor'/'IXBlackFoxAGI'/'ada'/'src'/'guard.adb').is_file()
assert (r/'vendor'/'IXBlackFoxAGI'/'LICENSE').is_file()
assert (r/'LICENSE').is_file()
print(f'STATIC PASS: {len(rows)} source files, intact hashes, native-gate path present; Julia/Ada tests NOT executed')
