import sys
rows=[]
for l in open('/tmp/work/frogger_ram.log'):
    f,_,h=l.strip().partition(' ')
    if len(h)==512: rows.append((int(f),bytes.fromhex(h)))
# scroll regs at even offsets 0..0x3e (32 columns); find the frames during play (>=~1000)
play=[r for r in rows if r[0]>760 and r[0]<1500]
print("frames",play[0][0],play[-1][0],len(play))
for c in range(32):
    d=[]
    for (f0,a),(f1,b) in zip(play,play[1:]):
        dv=(b[c*2]-a[c*2]+128)%256-128
        d.append(dv)
    nz=[x for x in d if x]
    if nz:
        from collections import Counter
        print("col",c,"px/2frames mode",Counter(d).most_common(2),"frac moving %.2f"%(len(nz)/len(d)))
