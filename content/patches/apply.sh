#!/usr/bin/env bash
# Re-apply the hand patches after a fresh `horizon-port-pack carry` (it deletes
# and rewrites carry/, and the port copies that tree into content/). Run from
# ports/mcwfences/content.
#
# What the raw carry needed — and what it did not:
#   * template and state space were already right: the 113 four-sided blocks
#     carry on `minecraft:oak_fence` and the 37 gates on
#     `minecraft:oak_fence_gate`, so the connection (`north/east/south/west`),
#     the gate's `in_wall`/`powered` and the fence's `waterlogged` all exist as
#     real states. `tools/e2e.sh` proves them in game; nothing is patched there.
#   * the one missing piece is the creative tab: upstream registers it in Java
#     (`TabInit`), and a data-tier port has no code. It is mirrored here as a
#     26.3 `creative_tab/` file listing the 150 carried blocks (upstream's list
#     also names the 30 blocks the carry leaves out).
set -euo pipefail
cd "$(dirname "$0")/.."

# 1. The creative tab upstream writes in code (`TabInit`), as 26.3 data.
mkdir -p data/mcwfences/horizon/creative_tab
cp patches/tab/fences.json data/mcwfences/horizon/creative_tab/fences.json

# 2. The port owns the manifest (description, authors), not the carry's stub.
cp patches/horizon-mod.toml horizon-mod.toml

echo "patches applied: 1 creative tab, 1 manifest"
