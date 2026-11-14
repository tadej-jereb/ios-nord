#!/usr/bin/env bash
# 62-msgbuf-summary.sh - one screen of judgement for a tooling/60-qemu-boot.sh run.
#
# Reads RUN_DIR/msgbuf.txt (the kernel message ring that 60 dumps out of guest
# RAM after the run; screen.txt is blank in the high-framebuffer layout) and
# answers the only questions a boot rung is judged on:
#
#   * how far the log got (last timestamp + its text) and what result.json said
#   * when "Early boot complete" was reached, or that it was not (found mid-line
#     too: when a kprintf has no trailing newline the next record is glued onto
#     it, so the marker can have no timestamp of its own)
#   * how many "exec xpcproxy" - the userland fan-out that is this rung's measure
#   * every other "exec <name>" with its time (found mid-line too, and one count
#     per occurrence when a glued line carries more than one launch)
#   * every SWEET line after early boot, grouped, so a new one stands out
#   * any panic string, with its timestamp
#   * with a baseline run: which exec names appeared/vanished and how counts moved
#
# A 128 KiB ring can fill up: then the dump starts mid-record and the early boot
# is simply not in the file.  That is detected (msgbuf.txt longer than the write
# pointer console_flags.json reports, a file that starts mid-record with a first
# timestamp that is not in the first second of boot) and reported as
# "RING WRAPPED, early lines lost" with the missing span, never as
# "early boot: NOT REACHED" - which would claim a fact the file cannot support.
#
#   tooling/62-msgbuf-summary.sh logs/qemu/20261114-094151
#   tooling/62-msgbuf-summary.sh logs/qemu/<stamp>-lane2 logs/qemu/20261114-094151
#
# Exit: 0 no panic, 2 a panic string was found, 1 usage or unreadable run dir.
# Nothing is written, nothing is booted, the phone is not touched.
set -uo pipefail

usage() {
	sed -n '2,30p' "$0"
	exit 1
}

[ $# -ge 1 ] || usage
case $1 in
-h | --help) usage ;;
esac
[ -d "$1" ] || { echo "error: no run directory $1" >&2; exit 1; }
[ -r "$1/msgbuf.txt" ] || {
	echo "error: no $1/msgbuf.txt (was the run killed before the dump, or is it a --gdb run?)" >&2
	exit 1
}
[ $# -ge 2 ] && [ ! -d "$2" ] && { echo "error: no baseline directory $2" >&2; exit 1; }

python3 - "$1" "${2:-}" <<'PY'
import json, os, re, sys

run, base = sys.argv[1], sys.argv[2]

# msgbuf lines look like "[   31.055028]: text"; a few records lose their
# newline in the ring wrap and turn up glued to the previous one, so a real
# record can begin mid-line - and carry no timestamp at all.
TS = re.compile(r"^\[\s*(\d+(?:\.\d+)?)\]!?:\s?(.*)$")
# a timestamp anywhere in a line (for markers that lost their line start)
TS_INLINE = re.compile(r"\[\s*(\d+\.\d{4,6})\]")
# the leading timestamp of a record, up to and including its ": " - matched
# separately from TS so its end offset is usable for the mid-line search
LEAD = re.compile(r"^\[\s*(\d+(?:\.\d+)?)\]!?:\s?")
# "exec <name>" anywhere in a line, not just at its start: when a kprintf has no
# trailing newline the next record is glued onto it, so a launch can begin
# mid-line - and then carry no timestamp of its own. The name stops at
# whitespace or '[' so a timestamp glued to its tail is not swallowed into it.
EXEC = re.compile(r"exec\s+([^\s\[]+)")
# "panic_trace:" is a normal kprintf, so no case-insensitive / bare "panic".
PANIC = re.compile(r"PANIC|panic\(|panic:|Assertion failed|no PTE for|unexpected SIGKILL")
# the launchd boot event; matched as a plain substring anywhere in a line so a
# record glued onto the tail of an unterminated kprintf is still found.
EARLY = "Early boot complete"


def read(path):
    """-> timed [(t, text)], untimed [text]"""
    timed, untimed = [], []
    with open(path, "rb") as f:
        raw = f.read().decode("utf-8", "replace")
    for line in raw.splitlines():
        m = TS.match(line)
        if m:
            timed.append((float(m.group(1)), m.group(2)))
        elif line.strip():
            untimed.append(line)
    return timed, untimed


def scan_execs(path):
    """Every "exec <name>" in the ring, wherever it sits on its line.

    -> [{"t","name","how","line","lo","hi"}] in file order, one entry per
    occurrence - a glued line can carry two launches and both are counted. A
    launch can begin mid-line when the kprintf before it lost its newline, so
    matching is not anchored; the timestamp follows the same rule as the
    early-boot marker:
      how="line"    the launch starts its own record; t is that [t].
      how="inline"  it sits mid-line behind a glued kprintf; t is the nearest
                    preceding [N.NNNNNN] on the line, i.e. that launch's own.
      how="spliced" the line carries no timestamp at all; t is the lower bound
                    of the enclosing timed records (lo), else the next (hi).
    """
    with open(path, "rb") as f:
        lines = f.read().decode("utf-8", "replace").splitlines()
    lead = [LEAD.match(line) for line in lines]
    own = [float(m.group(1)) if m else None for m in lead]
    out = []
    for i, line in enumerate(lines):
        for m in EXEC.finditer(line):
            name = m.group(1).rstrip(",;")
            if not name:
                continue
            # timestamps on this line before the launch, ignoring the record's
            # own leading one so the normal case stays how="line"
            start = lead[i].end() if lead[i] is not None else 0
            before = [float(x.group(1)) for x in
                      TS_INLINE.finditer(line, start, m.start())]
            if before:
                out.append({"t": before[-1], "name": name, "how": "inline",
                            "line": i + 1})
            elif lead[i] is not None:
                out.append({"t": own[i], "name": name, "how": "line",
                            "line": i + 1})
            else:
                lo = next((own[j] for j in range(i - 1, -1, -1)
                           if own[j] is not None), None)
                hi = next((own[j] for j in range(i + 1, len(lines))
                           if own[j] is not None), None)
                out.append({"t": lo if lo is not None else hi, "name": name,
                            "how": "spliced", "line": i + 1, "lo": lo, "hi": hi})
    return out


def scan_early(path, want=EARLY):
    """Find the launchd boot event in *every* line, not just timestamped ones.

    Returns None or {"t", "how", "line", "lo", "hi"}:
      how="line"    the usual case: own [t] at the start of its line.
      how="inline"  the marker sits mid-line after a kprintf that lost its
                    newline; "t" is the nearest preceding [N.NNNNNN] on that
                    line, which is that record's own timestamp.
      how="spliced" no timestamp on the line at all; "t" is the lower bound of
                    the enclosing timed records (lo) - anything between lo and
                    hi belongs to the glued block, so lo is a safe estimate.
    """
    with open(path, "rb") as f:
        lines = f.read().decode("utf-8", "replace").splitlines()
    own = []
    for line in lines:
        m = TS.match(line)
        own.append(float(m.group(1)) if m else None)
    for i, line in enumerate(lines):
        pos = line.find(want)
        if pos < 0:
            continue
        if own[i] is not None:
            return {"t": own[i], "how": "line", "line": i + 1}
        before = [float(m.group(1)) for m in TS_INLINE.finditer(line, 0, pos)]
        if before:
            return {"t": before[-1], "how": "inline", "line": i + 1}
        lo = next((own[j] for j in range(i - 1, -1, -1) if own[j] is not None), None)
        hi = next((own[j] for j in range(i + 1, len(lines)) if own[j] is not None), None)
        return {"t": lo if lo is not None else hi, "how": "spliced",
                "line": i + 1, "lo": lo, "hi": hi}
    return None


def note(ev, where, indent=" " * 18):
    """-> indented explanation lines for a non-'line' early boot hit."""
    if ev is None or ev["how"] == "line":
        return []
    if ev["how"] == "inline":
        return [f"{indent}^ marker is mid-line; timestamp is the nearest preceding "
                f"[{ev['t']:.6f}] on that line ({where}:{ev['line']})"]
    lo, hi = ev.get("lo"), ev.get("hi")
    if lo is not None and hi is not None:
        span = f"between {lo:.6f} and {hi:.6f}"
    elif lo is not None or hi is not None:
        span = f"only bound {lo if lo is not None else hi:.6f}"
    else:
        span = "no neighbouring timestamp at all"
    tail = ("there is no time to report" if ev["t"] is None
            else "reported value is the lower bound")
    return [f"{indent}^ spliced, no own timestamp ({span}), {tail} "
            f"({where}:{ev['line']})"]


def note_exec(evs, where, indent=" " * 18):
    """-> indented explanation lines for execs whose timestamp is not their own."""
    out = []
    for e in evs:
        if e["how"] == "inline":
            out.append(f"{indent}^ exec {e['name']} is mid-line; timestamp is the "
                       f"nearest preceding [{e['t']:.6f}] on that line "
                       f"({where}:{e['line']})")
        else:
            lo, hi = e.get("lo"), e.get("hi")
            if lo is not None and hi is not None:
                span = f"between {lo:.6f} and {hi:.6f}"
            elif lo is not None or hi is not None:
                span = f"only bound {lo if lo is not None else hi:.6f}"
            else:
                span = "no neighbouring timestamp at all"
            tail = ("there is no time to report" if e["t"] is None
                    else "reported value is the lower bound")
            out.append(f"{indent}^ exec {e['name']} is spliced, no own timestamp "
                       f"({span}), {tail} ({where}:{e['line']})")
    return out


def groups(pairs):
    """[(t, text)] -> [(count, tfirst, tlast, text)], first-appearance order."""
    out, index = [], {}
    for t, text in pairs:
        if text in index:
            i = index[text]
            out[i] = (out[i][0] + 1, out[i][1], t, text)
        else:
            index[text] = len(out)
            out.append((1, t, t, text))
    return out


def fmt(t):
    return "-" if t is None else f"{t:9.6f}"


def flags_of(run):
    """console_flags.json -> dict with 0x strings as ints; {} if absent."""
    try:
        d = json.load(open(os.path.join(run, "console_flags.json")))
    except (OSError, ValueError):
        return {}
    out = {}
    for k, v in d.items():
        if isinstance(v, str) and v.lower().startswith("0x"):
            try:
                v = int(v, 16)
            except ValueError:
                pass
        out[k] = v
    return out


def first_record(path):
    """-> (first non-blank line, the timestamp it starts with or None)."""
    with open(path, "rb") as f:
        for line in f.read().decode("utf-8", "replace").splitlines():
            if line.strip():
                m = LEAD.match(line)
                return line, (float(m.group(1)) if m else None)
    return "", None


def ring_state(run, size, first_line, first_ts):
    """-> (wrapped, [reason...], ring, bufx)

    msgbuf.txt is the ring rotated to start at the write pointer with the NULs
    stripped, so its length is the amount of text the ring still holds - which
    is exactly the write pointer until something is overwritten.  A wrapped
    ring is therefore visible three ways:

      * len(file) > bufx, the write pointer the kernel itself reports in
        console_flags.json: the pointer came round, so the head of the boot
        was overwritten by the newest text (decisive when present);
      * len(file) >= the ring size, with the pointer at its end;
      * the file does not begin at a record boundary AND its first timestamp is
        not in the first second of boot (every boot's first kprintf is ~0.02 s).

    Without console_flags.json only the last two are available.
    """
    fl = flags_of(run)
    ring, bufx = fl.get("msgbuf_size"), fl.get("msgbuf_bufx")
    midstart = bool(first_line) and LEAD.match(first_line) is None
    late = first_ts is not None and first_ts >= 1.0
    why = []
    if isinstance(bufx, int) and size > bufx:
        why.append(f"msgbuf.txt ({size} B) is longer than the write pointer "
                   f"bufx={bufx} the kernel reports, so it has come round")
    if midstart and late:
        why.append(f"the file starts mid-record ('{first_line.strip()[:50]}') and its "
                   f"first timestamp is {first_ts:.6f}, not in the first second of boot")
    if not isinstance(bufx, int) and ring and size >= ring:
        why.append(f"the file is the whole {ring} B ring the kernel reports")
    return bool(why), why, ring, bufx


timed, untimed = read(os.path.join(run, "msgbuf.txt"))
size = os.path.getsize(os.path.join(run, "msgbuf.txt"))
strings = [(t, s) for t, s in timed] + [(None, s) for s in untimed]
first_line, first_ts = first_record(os.path.join(run, "msgbuf.txt"))
wrapped, why, ring, bufx = ring_state(run, size, first_line, first_ts)
empty = bool(first_line) is False and size == 0
last_t = timed[-1][0] if timed else None
first_t = timed[0][0] if timed else None
rings = f"{ring} B ({ring:#x})" if isinstance(ring, int) else "unknown"

print(f"# msgbuf summary: {run}")
print(f"#   baseline:      {base or '(none)'}")

res = {}
try:
    res = json.load(open(os.path.join(run, "result.json")))
except (OSError, ValueError):
    pass
if res:
    print(f"#   result.json:   status={res.get('status')} "
          f"seconds_to_point={res.get('seconds_to_point')} "
          f"deepest={res.get('deepest_marker')} "
          f"qemu_exceptions={res.get('qemu_exceptions')} "
          f"panic_at={res.get('panic_at')}")
else:
    print("#   result.json:   (missing)")
print(f"#   msgbuf:        {size} B, {len(timed) + len(untimed)} lines, {len(timed)} timed")
fl = flags_of(run)
if fl.get("msgbuf_ring_via"):
    print(f"#   ring read via: {fl['msgbuf_ring_via']}"
          + (f" (pa {fl['msgbuf_ring_pa']})" if fl.get("msgbuf_ring_pa") else ""))
if empty:
    print(f"#   ring:          EMPTY DUMP - 0 B. The kernel reports a {rings} ring, so the "
          f"dump read the wrong address")
    print(f"#                  (see console_flags.json; nothing can be judged from this run)")
elif wrapped:
    print(f"#   ring:          FULL - RING WRAPPED, early lines lost ({size} B of the {rings} ring"
          + (f", bufx {bufx}" if isinstance(bufx, int) else "") + ")")
    for w in why:
        print(f"#                  - {w}")

# patch 0047's _sweet_log_ring: what reached _cnputs (dyld's /dev/console
# output for pid 1, invisible in msgbuf.txt).  60 writes it next to msgbuf.
sl_path = os.path.join(run, "sweetlog.txt")
if os.path.exists(sl_path):
    sl = os.path.getsize(sl_path)
    print(f"#   sweetlog:      {sl} B (of {fl.get('sweetlog_total', '?')} appended, via "
          f"{fl.get('sweetlog_via', '?')})")
    if sl:
        hit = fl.get("sweetlog_dyld_reject", fl.get("sweetlog_not_loaded"))
        if isinstance(hit, int) and hit:
            print(f"#                  dyld rejected the cache {hit}x - "
                  f"grep 'not loaded:' {sl_path}")
elif fl.get("sweetlog_ring_sym"):
    sym = fl["sweetlog_ring_sym"]
    print(f"#   sweetlog:      NO FILE - _sweet_log_ring is in the symtab "
          f"({f'{sym:#x}' if isinstance(sym, int) else sym}) but 60 wrote no "
          f"sweetlog.txt for this run")

if not timed:
    print("\nlast timestamp  : (none - the ring is empty or has no kprintf at all)")
else:
    last_s = timed[-1][1]
    print(f"\nlast timestamp  : {fmt(last_t)}  {last_s[:110]}")
    if wrapped:
        print(f"first timestamp : {fmt(first_t)}  {timed[0][1][:110]}")
        print(f"window          : {first_t:.6f} .. {last_t:.6f}  "
              f"({last_t - first_t:.6f} s of the run kept, {len(timed)} timed lines)")
        print(f"MISSING         : 0.000000 .. {first_t:.6f}  ({first_t:.6f} s at the head of "
              f"the boot; the {rings} ring")
        print(f"                  kept only the last {size} B of text, so the early boot and "
              f"the first exec wave are gone)")

ev = scan_early(os.path.join(run, "msgbuf.txt"))
early = ev["t"] if ev else None
if ev is None and empty:
    print("early boot      : UNKNOWN (msgbuf.txt is 0 B - the dump read nothing, so no "
          "line can be judged)")
elif ev is None and wrapped:
    print(f"early boot      : UNKNOWN - ring WRAPPED, early lines lost (no 'Early boot "
          f"complete' in the {last_t - first_t:.6f} s that survived;")
    print(f"                  if the boot reached it at ~32 s it was overwritten)")
elif ev is None:
    print(f"early boot      : NOT REACHED (no 'Early boot complete' in "
          f"{len(timed) + len(untimed)} lines)")
elif early is None:
    print(f"early boot      : {fmt(early)}  Early boot complete "
          f"(found, but no timestamp anywhere near it)")
    for line in note(ev, "msgbuf.txt"):
        print(line)
else:
    after = sum(1 for t, _ in timed if t > early)
    print(f"early boot      : {fmt(early)}  Early boot complete "
          f"({after} timed lines after it)")
    for line in note(ev, "msgbuf.txt"):
        print(line)

ex = scan_execs(os.path.join(run, "msgbuf.txt"))
xp = [e["t"] for e in ex if e["name"] == "xpcproxy"]
print(f"exec xpcproxy   : {len(xp)}"
      + (f"   first {fmt(xp[0])}  last {fmt(xp[-1])}" if xp else "")
      + ("   (window only: ring wrapped)" if wrapped else ""))

others = groups([(e["t"], e["name"]) for e in ex if e["name"] != "xpcproxy"])
print(f"exec other      : {len(others)} name(s)")
for count, t0, t1, name in others:
    if count == 1 or t0 is None or t1 is None:
        print(f"  {fmt(t0)}  {name}" + (f"  x{count}" if count > 1 else ""))
    else:
        print(f"  {t0:9.6f}..{t1:<9.6f}  {name}  x{count}")
for line in note_exec([e for e in ex if e["how"] != "line"], "msgbuf.txt"):
    print(line)

sweet = [(t, s) for t, s in timed
         if "SWEET" in s and (early is None or t >= early)]
gsweet = groups(sweet)
if wrapped and early is None:
    print(f"\nSWEET in the window (early boot not in the ring): {len(sweet)} line(s), "
          f"{len(gsweet)} distinct")
else:
    print(f"\nSWEET after early boot: {len(sweet)} line(s), {len(gsweet)} distinct")
if not sweet:
    print("  (none)")
for count, t0, t1, text in gsweet:
    span = f"{fmt(t0)}" if count == 1 else f"{t0:9.6f}..{t1:<9.6f} x{count}"
    print(f"  {span}  {text[:150]}")

hits = [(t, s) for t, s in strings if PANIC.search(s)]
print(f"\npanic           : {'NONE' if not hits else str(len(hits)) + ' line(s)'}"
      + (f"   (window only: a panic before {first_t:.6f} would have been overwritten)"
         if wrapped and not hits else ""))
for t, s in hits:
    print(f"  {fmt(t)}  {s[:160]}")

if base:
    btimed, _ = read(os.path.join(base, "msgbuf.txt"))
    bex = [e["name"] for e in scan_execs(os.path.join(base, "msgbuf.txt"))]
    names = {e["name"] for e in ex}
    bnames = set(bex)
    bsize = os.path.getsize(os.path.join(base, "msgbuf.txt"))
    bwrapped, _, _, _ = ring_state(base, bsize,
                                   *first_record(os.path.join(base, "msgbuf.txt")))
    print(f"\nexec diff vs baseline ({base}):")
    if wrapped or bwrapped:
        print(f"  WARNING       : counts are window-only on a wrapped side - this run "
              f"{'WRAPPED' if wrapped else 'complete'}, "
              f"baseline {'WRAPPED' if bwrapped else 'complete'}")
    only_here = [n for n in dict.fromkeys(e["name"] for e in ex) if n not in bnames]
    only_base = [n for n in dict.fromkeys(bex) if n not in names]
    print(f"  only here     : {', '.join(only_here) or '(none)'}")
    print(f"  only baseline : {', '.join(only_base) or '(none)'}")
    counts_here = {}
    for e in ex:
        counts_here[e["name"]] = counts_here.get(e["name"], 0) + 1
    counts_base = {}
    for n in bex:
        counts_base[n] = counts_base.get(n, 0) + 1
    moved = [f"{n} {counts_base.get(n, 0)} -> {counts_here.get(n, 0)}"
             for n in dict.fromkeys([e["name"] for e in ex] + bex)
             if counts_base.get(n, 0) != counts_here.get(n, 0)]
    print(f"  count changed : {', '.join(moved) or '(none)'}")
    bev = scan_early(os.path.join(base, "msgbuf.txt"))
    searly = bev["t"] if bev else None
    print(f"  early boot    : {fmt(searly)} -> {fmt(early)}"
          + ("" if early is None or searly is None
             else f"  ({early - searly:+.3f} s)"))
    for ev_, where in ((bev, "baseline"), (ev, "here")):
        for line in note(ev_, f"{where} msgbuf.txt", indent=" " * 18):
            print(line)
    if timed and btimed:
        print(f"  last timestamp: {fmt(btimed[-1][0])} -> {fmt(timed[-1][0])}"
              f"  ({timed[-1][0] - btimed[-1][0]:+.3f} s)")

sys.exit(2 if hits else 0)
PY
exit $?
