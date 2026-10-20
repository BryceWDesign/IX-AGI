#!/usr/bin/env python3
"""Stdlib-only numerical sanity check. This does NOT execute IX-AGI's Julia code."""
import hashlib
import math
import random

WIDTH=32
TRIALS=1000

def encode(features):
    vector=[0.0]*WIDTH
    for feature in features:
        d=hashlib.sha256(feature.encode()).digest()
        ix=((d[0]<<8)+d[1])%WIDTH
        vector[ix]+=1.0 if d[2]&1 else -1.0
    length=math.sqrt(sum(v*v for v in vector))
    return [v/length for v in vector] if length else vector

def dot(a,b):
    return sum(x*y for x,y in zip(a,b))

before=encode(('ready/?1','station/:hub'))
after=encode(('ready/?1','station/:hub','beacon/:hub'))
message=[math.tanh(x-y) for x,y in zip(after,before)]
true_goal=encode(('beacon/:hub',))
false_goal=encode(('unrelated/:hub',))
reversed_goal=encode(('jammed/:hub',))
correct=wrong=reverse=0
for seed in range(TRIALS):
    rng=random.Random(seed)
    matrix=[[0.0]*WIDTH for _ in range(WIDTH)]
    for i in range(WIDTH):
        matrix[i][i]=0.4
        for j in range(WIDTH):
            if i!=j and rng.random()<0.07:
                matrix[i][j]=0.05 if rng.random()<0.5 else -0.05
    received=[math.tanh(dot(row,message)) for row in matrix]
    correct+=dot(true_goal,received)>0.08
    wrong+=dot(false_goal,received)>0.08
    reverse+=dot(reversed_goal,received)>0.08
assert correct==TRIALS,(correct,TRIALS)
assert wrong==0,wrong
assert reverse==0,reverse
print(f'PASS: {correct}/{TRIALS} aligned numerical projections')
print(f'PASS: {wrong}/{TRIALS} unrelated-goal false positives')
print(f'PASS: {reverse}/{TRIALS} inverted-goal false positives')
print('Only a mathematical approximation; native Julia/Ada execution NOT established.')
