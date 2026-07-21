import struct, statistics as st

HDR, REC = 256, 64
rec_s = struct.Struct('<Qqdddqi12x')

def load(path):
    with open(path,'rb') as f:
        h = f.read(HDR)
        point = struct.unpack_from('<d', h, 136)[0]
        mids, ts = [], []
        while True:
            b = f.read(REC)
            if len(b) < REC: break
            _,tmsc,bid,ask,_,_,_ = rec_s.unpack(b)
            mids.append((bid+ask)/2.0); ts.append(tmsc)
    return point, mids, ts

def pct(s,p):
    s=sorted(s); k=(len(s)-1)*p/100.0; lo=int(k); hi=min(lo+1,len(s)-1)
    return s[lo]+(s[hi]-s[lo])*(k-lo)

# Deslocamento liquido |mid(t+L)-mid(t)| sobre janela de L ms (ponteiro deslizante)
def disp(point, mids, ts, L):
    out = []
    n = len(ts); j = 0
    for i in range(n):
        if j < i: j = i
        while j < n and ts[j]-ts[i] < L: j += 1
        if j >= n: break
        out.append(abs(mids[j]-mids[i])/point)  # pts
    return out

for path, tag in [
   (r"c:\dev\MKS-ULTIMATE\tests\golden\e2-decision\XAUUSDm_CR_20260720T233245.mkstick","golden"),
   (r"C:\Users\mikem\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\Files\MKS-ULTIMATE\Ticks\XAUUSDm_CR_20260720T165526.mkstick","CR-live"),
]:
    point, mids, ts = load(path)
    print(f"\n== {tag} (n={len(mids):,}, point={point}) ==")
    for L in (120, 260, 500, 1000):
        d = disp(point, mids, ts, L)
        if not d: continue
        m = st.fmean(d)
        print(f"   L={L:4d}ms: deslocamento |Δmid| pts -> p50={pct(d,50):.0f} mean={m:.0f} "
              f"p90={pct(d,90):.0f} p95={pct(d,95):.0f}   => drift/ms(mean/L)={m/L:.3f} pts/ms")
