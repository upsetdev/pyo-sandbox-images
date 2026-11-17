#!/usr/bin/env python3
"""Writes the licenses of the Rust crates built into voxl, for its docs.

Run in voxl's source folder after `cargo build`, with the same features:

    voxl-licenses.py OUT_DIR [cargo metadata flags...]

It follows the normal dependencies (not build or dev ones) of voxl for this
machine's target, the crates that end up in the binary. Each one's license
files (LICENSE*, COPYING*, NOTICE*) go to OUT_DIR/<name>-<version>/, and
OUT_DIR/README.md lists every crate with its version, license and source.
"""

import json
import os
import shutil
import subprocess
import sys

out = sys.argv[1]
host = next(
    line.split(": ", 1)[1]
    for line in subprocess.run(["rustc", "-vV"], capture_output=True, text=True, check=True).stdout.splitlines()
    if line.startswith("host: ")
)
meta = json.loads(subprocess.run(
    ["cargo", "metadata", "--format-version", "1", "--locked", "--filter-platform", host, *sys.argv[2:]],
    capture_output=True, text=True, check=True,
).stdout)

packages = {p["id"]: p for p in meta["packages"]}
nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
root = meta["resolve"]["root"]

# Normal dependencies only, from voxl down.
seen, todo = set(), [root]
while todo:
    pid = todo.pop()
    if pid in seen:
        continue
    seen.add(pid)
    for dep in nodes[pid]["deps"]:
        if any(k["kind"] is None for k in dep["dep_kinds"]):
            todo.append(dep["pkg"])
seen.discard(root)

os.makedirs(out, exist_ok=True)
rows, missing = [], []
for pid in sorted(seen, key=lambda i: (packages[i]["name"], packages[i]["version"])):
    p = packages[pid]
    name, version = p["name"], p["version"]
    src = os.path.dirname(p["manifest_path"])
    files = sorted(
        f for f in os.listdir(src)
        if f.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE", "COPYRIGHT"))
        and os.path.isfile(os.path.join(src, f))
    )
    if files:
        dest = os.path.join(out, f"{name}-{version}")
        os.makedirs(dest, exist_ok=True)
        for f in files:
            shutil.copy(os.path.join(src, f), os.path.join(dest, f))
    else:
        missing.append(name)
    link = p.get("repository") or f"https://crates.io/crates/{name}"
    rows.append(f"| {name} | {version} | {p.get('license') or p.get('license_file') or 'unknown'} | {link} |")

with open(os.path.join(out, "README.md"), "w") as f:
    f.write(
        "# Rust crates in voxl\n\n"
        "voxl's binary is built with these crates from crates.io, at the versions its\n"
        "Cargo.lock pins. Their license files are in the folder named after each\n"
        "one. A crate with no folder ships no license file: its license is the SPDX\n"
        "one named here.\n\n"
        "| Crate | Version | License | Source |\n| --- | --- | --- | --- |\n"
    )
    f.write("\n".join(rows) + "\n")
print(f"{len(rows)} crates, {len(rows) - len(missing)} with license files", file=sys.stderr)
if missing:
    print("no license file: " + ", ".join(missing), file=sys.stderr)
