#!/usr/bin/env python3
"""Reads a `PlaybackProbe` JSON report and prints what the main thread spent, per operation.

The report is the instrument's own output and is deliberately raw; this is the reader. It prints
three things and nothing else:

  * the run's shape, so a table pasted into PERFORMANCE.md carries its own provenance;
  * one row per operation — busy, the bursts the owner can see, and the named spans inside it;
  * the phase table, main-thread only, with the unattributed remainder named.

Usage: tools/probe-report.py <report.json> [<report.json> ...]
"""
import json
import sys


def ms(x):
    return f"{x:7.1f}"


def one(path):
    d = json.load(open(path))
    print("=" * 100)
    print(f"{path.split('/')[-1]}   {d['device']} iOS {d['os']}  mode={d.get('mode')}")
    print(f"  {d['canvasWidth']}x{d['canvasHeight']}  layers={d['layers']} frames={d['frames']} "
          f"baked={d.get('bakedCount')} bakeWait={d.get('bakeWaitSeconds', 0):.1f}s "
          f"onion={d.get('onionSkinEnabled')}/{d.get('onionSkinPlacement')} "
          f"ringBudget={d.get('ringByteBudget', 0)/1e6:.0f}MB events={d.get('eventCount')}")
    if d.get("traceOverflowed"):
        print("  ** TRACE OVERFLOWED — the tail of this run is missing **")

    ops = d.get("operations") or []
    ticks = d.get("ticks") or []
    if ops:
        print(f"\n  {'op':<9} {'busy':>7} {'onCPU':>7} {'unattr':>7}  bursts")
        for i, t in enumerate(ticks):
            name = ops[i] if i < len(ops) else f"tick{i}"
            bursts = " ".join(f"[{b['at']:.0f}+{b['ms']:.0f}]" for b in t.get("bursts", []))
            u = t.get("unattributedMs")
            c = t.get("mainCpuMs")
            print(f"  {name:<9} {t['mainBusyMs']:7.1f} "
                  f"{('' if c is None else f'{c:7.1f}')} "
                  f"{('' if u is None else f'{u:7.1f}')}  {bursts}")

        # Per-phase mean across the operations that are real edits (not the closing anchor).
        edits = [(ops[i], t) for i, t in enumerate(ticks)
                 if i < len(ops) and ops[i] != "end"]
        keys = set()
        for _, t in edits:
            keys |= set(t.get("phaseMs", {}).keys())
        rows = []
        for k in keys:
            vals = [t.get("phaseMs", {}).get(k, 0.0) for _, t in edits]
            rows.append((sum(vals) / max(len(vals), 1), max(vals), k))
        rows.sort(reverse=True)
        print(f"\n  per-operation mean over {len(edits)} edits (ms)")
        print(f"  {'phase':<22} {'mean':>7} {'max':>7}")
        for mean, mx, k in rows:
            if mean < 0.05 and mx < 0.5:
                continue
            print(f"  {k:<22} {mean:7.1f} {mx:7.1f}")

    print(f"\n  phase totals over the whole run")
    print(f"  {'phase':<22} {'n':>5} {'onMain':>6} {'total':>8} {'mean':>7} {'p50':>7} {'p90':>7} {'max':>8}")
    for p in d.get("phases", []):
        print(f"  {p['phase']:<22} {p['count']:5d} {p['onMainCount']:6d} {p['totalMs']:8.1f} "
              f"{p['meanMs']:7.2f} {p['p50Ms']:7.2f} {p['p90Ms']:7.2f} {p['maxMs']:8.1f}")
    if "attribution" in d:
        a = d["attribution"]
        print(f"\n  main-thread busy {a['mainBusyMs']:.1f} ms = attributed {a['attributedMs']:.1f} "
              f"+ UNATTRIBUTED {a['unattributedMs']:.1f} ms ({a['unattributedShare']*100:.0f}%)")
        if "mainCpuMs" in a:
            print(f"  of that busy, {a['mainCpuMs']:.1f} ms on a core and "
                  f"{a['offCpuMs']:.1f} ms blocked or descheduled "
                  f"({a['offCpuMs']/max(a['mainBusyMs'],1)*100:.0f}%)")


def bursts(path, limit=6):
    d = json.load(open(path))
    print(f"\n  the {limit} longest main-thread stalls, opened up")
    for b in (d.get("burstDetail") or [])[:limit]:
        print(f"  --- {b['ms']:.1f} ms at t={b['at']:.2f}s   "
              f"lead {b['leadMs']:.1f} | gaps {b['gapMs']:.1f} | tail {b['tailMs']:.1f}"
              f"   || sources {b.get('sourceMs', 0):.1f} | observers {b.get('observerMs', 0):.1f}"
              f" | caCommit {b.get('commitMs', 0):.1f} | onCPU {b.get('cpuMs', 0):.1f}")
        for s in b["spans"]:
            print(f"        +{s['at']:7.2f}  {s['ms']:6.2f}  {s['phase']}")


if __name__ == "__main__":
    for path in sys.argv[1:]:
        one(path)
        bursts(path)
