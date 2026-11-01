#!/usr/bin/env python3
"""Fail if any research ROM content ends up in a build artifact (APK / PCK / zip).

Usage: verify_no_rom_content.py <artifact> [--roms "qbert 2.zip" "frogger (1).zip"]

Checks, recursively through nested zips (an APK is a zip, ROM ZIPs are zips):
  * entry names that look like the ROM ZIPs / ROM members
  * byte signatures (first 64 bytes + a middle slice) of every ROM member file
  * the byte stream of the ROM ZIP files themselves
This script only READS the ROM ZIPs to build signatures; nothing is copied.
"""
import sys, zipfile, io, os, re

def load_signatures(rom_zips):
    sigs, names = [], set()
    for z in rom_zips:
        raw = open(z, "rb").read()
        sigs.append((os.path.basename(z) + " (whole file head)", raw[:64]))  # zip header: distinctive (names, CRCs)
        with zipfile.ZipFile(z) as zf:
            for n in zf.namelist():
                names.add(os.path.basename(n).lower())
                d = zf.read(n)
                # only distinctive (non-padding) 96-byte windows make useful signatures
                for off in (0, len(d) // 4, len(d) // 2, 3 * len(d) // 4):
                    w = d[off:off + 96]
                    if len(w) == 96 and len(set(w)) >= 16:
                        sigs.append((f"{n} @{off}", w))
    return sigs, names

BAD_NAME = re.compile(r"(qbert|frogger\s*\(|\.rom$|\.zip$|(^|/)research/)", re.I)

def scan(data, label, sigs, names, problems, depth=0):
    for desc, sig in sigs:
        if sig and sig in data:
            problems.append(f"{label}: contains ROM bytes ({desc})")
    if depth < 3 and data[:2] == b"PK":
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                for n in zf.namelist():
                    base = os.path.basename(n).lower()
                    if base in names or BAD_NAME.search(n):
                        problems.append(f"{label}: forbidden entry name '{n}'")
                    scan(zf.read(n), f"{label}!{n}", sigs, names, problems, depth + 1)
        except zipfile.BadZipFile:
            pass

def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); return 2
    art = args[0]
    roms = ["qbert 2.zip", "frogger (1).zip"]
    if "--roms" in args:
        roms = args[args.index("--roms") + 1:]
    sigs, names = load_signatures(roms)
    problems = []
    data = open(art, "rb").read()
    # PCK directory lists plain-text res:// paths
    for m in re.finditer(rb"res://[^\x00]{0,200}", data):
        p = m.group(0).decode("latin1")
        if BAD_NAME.search(p):
            problems.append(f"pck path: {p}")
    scan(data, os.path.basename(art), sigs, names, problems)
    entries = None
    if data[:2] == b"PK":
        with zipfile.ZipFile(art) as zf:
            entries = len(zf.namelist())
    if problems:
        print("FAIL: ROM/research content found in", art)
        for p in sorted(set(problems)): print("  -", p)
        return 1
    print(f"OK: {art} ({len(data)} bytes{', %d zip entries' % entries if entries else ''}) contains no ROM content")
    return 0

if __name__ == "__main__":
    sys.exit(main())
