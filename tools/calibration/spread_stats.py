import struct, sys, statistics as st

HDR = 256
REC = 64
rec_s = struct.Struct('<Qqdddqi12x')  # seq,timeMsc,bid,ask,last,volume,flags,+12 pad

def read_header(f):
    h = f.read(HDR)
    point   = struct.unpack_from('<d', h, 136)[0]
    tickcnt = struct.unpack_from('<q', h, 160)[0]
    symbol  = h[88:120].split(b'\x00',1)[0].decode('utf-8','replace')
    digits  = h[120]
    tfirst  = struct.unpack_from('<q', h, 168)[0]
    tlast   = struct.unpack_from('<q', h, 176)[0]
    return point, tickcnt, symbol, digits, tfirst, tlast

def pct(sorted_vals, p):
    if not sorted_vals: return float('nan')
    k = (len(sorted_vals)-1) * p/100.0
    lo = int(k); hi = min(lo+1, len(sorted_vals)-1)
    return sorted_vals[lo] + (sorted_vals[hi]-sorted_vals[lo])*(k-lo)

def analyze(path, sample=1):
    with open(path,'rb') as f:
        point, tickcnt, symbol, digits, tfirst, tlast = read_header(f)
        spreads = []
        neg = zero = 0
        i = 0
        while True:
            b = f.read(REC)
            if len(b) < REC: break
            if sample>1 and (i % sample):
                i+=1; continue
            i+=1
            _,_,bid,ask,_,_,_ = rec_s.unpack(b)
            sp = (ask-bid)/point
            if sp < 0: neg+=1; continue
            if sp == 0: zero+=1
            spreads.append(sp)
    spreads.sort()
    dur_h = (tlast-tfirst)/3600000.0 if tlast>tfirst else 0
    return {
        'path': path.split('\\')[-1].split('/')[-1],
        'symbol': symbol, 'digits': digits, 'point': point,
        'tickcnt': tickcnt, 'sampled': len(spreads), 'sample_step': sample,
        'dur_h': dur_h, 'neg': neg, 'zero': zero,
        'min': spreads[0] if spreads else float('nan'),
        'mean': st.fmean(spreads) if spreads else float('nan'),
        'p25': pct(spreads,25), 'p50': pct(spreads,50), 'p75': pct(spreads,75),
        'p90': pct(spreads,90), 'p95': pct(spreads,95), 'p99': pct(spreads,99),
        'max': spreads[-1] if spreads else float('nan'),
        'stdev': st.pstdev(spreads) if len(spreads)>1 else 0.0,
    }, spreads

def show(r):
    print(f"\n== {r['path']} ==")
    print(f"   symbol={r['symbol']} digits={r['digits']} point={r['point']:.6g} "
          f"ticks={r['tickcnt']:,} sampled={r['sampled']:,} step={r['sample_step']} dur={r['dur_h']:.2f}h")
    print(f"   spread(pts): min={r['min']:.1f} p25={r['p25']:.1f} p50={r['p50']:.1f} "
          f"mean={r['mean']:.1f} p75={r['p75']:.1f} p90={r['p90']:.1f} "
          f"p95={r['p95']:.1f} p99={r['p99']:.1f} max={r['max']:.1f} sd={r['stdev']:.1f}")
    print(f"   spread(USD): p50={r['p50']*r['point']:.3f} mean={r['mean']*r['point']:.3f} "
          f"p95={r['p95']*r['point']:.3f}   (neg={r['neg']} zero={r['zero']})")

files = [
 (r"c:\dev\MKS-ULTIMATE\tests\golden\e2-decision\XAUUSDm_CR_20260720T233245.mkstick", 1),
 (r"C:\Users\mikem\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\Files\MKS-ULTIMATE\Ticks\XAUUSDm_CR_20260720T165526.mkstick", 1),
 (r"C:\Users\mikem\AppData\Roaming\MetaQuotes\Terminal\53785E099C927DB68A545C249CDBCE06\MQL5\Files\MKS-ULTIMATE\Ticks\XAUUSDm_20260720T144207_parity.mkstick", 20),
]

allsp = []
for path, samp in files:
    try:
        r, sp = analyze(path, samp)
        show(r); allsp.extend(sp)
    except Exception as e:
        print(f"\n== {path} ==\n   ERRO: {e}")

if allsp:
    allsp.sort()
    print(f"\n== AGREGADO ({len(allsp):,} amostras) ==")
    print(f"   spread(pts): p50={pct(allsp,50):.1f} mean={st.fmean(allsp):.1f} "
          f"p90={pct(allsp,90):.1f} p95={pct(allsp,95):.1f} p99={pct(allsp,99):.1f} max={allsp[-1]:.1f}")
