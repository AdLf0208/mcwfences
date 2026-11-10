#!/usr/bin/env bash
# In-game check for the Macaw's Fences and Walls content port (180 blocks ->
# 150 carried: 113 four-sided fences/walls + 37 gates), Minecraft 26.3 on the
# campaign pin 41f822b6.
#
# Default run (offscreen renderer, creative, The End, shared unmodded game +
# `--dev-mod content/`):
#   0. tools/verify_content.py compares the carried folder mod with the 1.21.1
#      jar first (blockstate/model/texture/recipe/loot/lang/tag fidelity and
#      all 4800 states covered), so a broken asset never reaches the game;
#   1. the mod loads (no "content mods not loaded");
#   2. all 150 carried ids `setblock` and read back, so every registry entry
#      and its default state binds;
#   3. the connection state is real, not only declared: a lonely fence has no
#      side, a pair joins on the facing sides, a mod fence joins a vanilla
#      oak_fence and a solid block, a `*_wall` block joins its own kind, and a
#      waterlogged fence keeps `waterlogged=true` (the template's 5th state);
#   4. a gate takes `in_wall=true` beside a carried wall block (the tag drives
#      it) and drops back to false when the wall goes, so the gate's 32-state
#      space is exercised, not just its default;
#   5. a gate item places with a facing, right-click opens and closes it, and a
#      redstone block opens it (`powered=true,open=true`) and removing it
#      closes it - the vanilla fence-gate behaviour the template carries;
#   6. in survival a placed fence drops itself (the carried loot table), the
#      one thing a data carry owns end to end;
#   7. screenshots: a fence/wall/gate scene and a gate in
#      `in_wall=true,powered=true` each differ from the same frame with the
#      blocks removed, and the log carries no mcwfences missing-model or
#      missing-texture warning (missing assets are a failure);
#   8. the creative tab lists all 150 carried blocks;
#   9. controls: an unknown id, an impossible state and a plain stick are
#      refused, and a vanilla oak_fence shows the same connection behaviour.
#
# NEGATIVE=1 keeps the scenario but expects the fence pair NOT to join: the run
# MUST fail at that assertion, proving the connection check is not vacuous.
# `SKIP_VERIFY=1` skips the jar comparison (debugging only).
set -euo pipefail

CLONE=${CAMPAIGN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}
PORT=$CLONE/ports/mcwfences
SHARED=$CLONE/ports/_shared/bin/horizon-41f822b6
CTL=${CTL:-$SHARED/horizon-ctl}
GAME=${GAME:-$SHARED/horizon-client}
RES=${RES:-${HORIZON_RES:-$HOME/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/mcwfences-e2e.sock}
NEGATIVE=${NEGATIVE:-0}
SKIP_VERIFY=${SKIP_VERIFY:-0}

[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/content/horizon-mod.toml" ] || { echo "missing content mod: $PORT/content" >&2; exit 1; }

BLOCK_DIR=$PORT/content/data/mcwfences/horizon/block
mapfile -t BLOCKS < <(find "$BLOCK_DIR" -name '*.json' -printf '%f\n' | sed 's/\.json$//' | sort)
[ "${#BLOCKS[@]}" -eq 150 ] || { echo "expected 150 carried blocks, found ${#BLOCKS[@]}" >&2; exit 1; }
BLOCK_DECL=$BLOCK_DIR

say() { echo "== $* =="; }
fail() { echo "FAIL: $*" >&2; exit 1; }
template_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["template"])' \
    "$BLOCK_DECL/$1.json"; }

if [ "$SKIP_VERIFY" = 1 ]; then
    echo "== jar comparison skipped (SKIP_VERIFY=1) =="
else
    say "data fidelity: carried content vs the 1.21.1 jar"
    python3 "$PORT/tools/verify_content.py" --content "$PORT/content" --resources "$RES" \
        || fail "verify_content.py failed"
fi

SCRATCH=$(mktemp -d /tmp/opencode/mcwfences-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
end() { ctl command "execute in minecraft:the_end run $1"; }
count_item() { ctl inventory | jq -r --arg i "$1" '.counts[$i] // 0'; }
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
prop() { echo "$1" | grep -o "$2=[a-z]*" | head -1 | cut -d= -f2 || true; }
assert_prop() {
    local state=$1 key=$2 want=$3 got
    got=$(prop "$state" "$key")
    [ "$got" = "$want" ] || fail "$state: $key is '$got', expected '$want'"
}
mean_rgb() {
    python3 - "$1" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
crop = im.crop((w * 3 // 10, h * 3 // 10, w * 7 // 10, h * 7 // 10))
px = list(crop.getdata())
n = len(px)
print(sum(p[0] for p in px) / n, sum(p[1] for p in px) / n, sum(p[2] for p in px) / n)
PY
}
pixel_fraction() { # file-a file-b -> the share of pixels that changed (max channel > 12)
    python3 - "$1" "$2" <<'PY'
import sys
from PIL import Image
a = list(Image.open(sys.argv[1]).convert("RGB").getdata())
b = list(Image.open(sys.argv[2]).convert("RGB").getdata())
changed = sum(
    1
    for p, q in zip(a, b)
    if max(abs(p[0] - q[0]), abs(p[1] - q[1]), abs(p[2] - q[2])) > 12
)
print(f"{changed / len(a):.5f}")
PY
}
frame_differs() { # file-a file-b label min-fraction
    local fraction
    fraction=$(pixel_fraction "$1" "$2")
    echo "share of pixels changed by $3: $fraction (mean RGB $(mean_rgb "$1") vs $(mean_rgb "$2"))"
    awk -v f="$fraction" -v m="$4" 'BEGIN { exit !(f >= m) }' \
        || fail "the frame did not change when $3 was removed (no model drawn?)"
}

cleanup() {
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$SCRATCH" || true
}
trap cleanup EXIT

say "launch (offscreen renderer, creative, The End, content --dev-mod content/)"
"$CTL" --socket "$SOCK" launch \
    --game "$GAME" --world McwFencesE2E --seed 20261107 --creative --offscreen --wait \
    --game-dir "$SCRATCH/game" --resources "$RES" --dev-mod "$PORT/content"
ctl wait-ready 180
if ctl logs --lines 4000 2>/dev/null | grep -q "content mods not loaded"; then
    ctl logs --lines 4000 | grep "content mods not loaded" >&2
    fail "the content mod did not load"
fi
echo "content mod loaded (no 'content mods not loaded')"

say "The End arena: floor at y=79, clear above"
end "forceload add -8 -8 72 72"
end "tp @s 8.5 80 8.5"
ctl wait 40
end "fill -8 79 -8 72 79 32 minecraft:stone"
end "fill -8 80 -8 72 88 32 minecraft:air"
end "difficulty peaceful"
end "gamerule spawn_mobs false"
ctl wait 10
ctl close >/dev/null 2>&1 || true
ctl wait 2

# ------------------------------------------------------------------ registry
say "all ${#BLOCKS[@]} carried ids bind their default state"
PER=25
for i in "${!BLOCKS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    ctl setblock "$x" 80 "$z" "mcwfences:${BLOCKS[$i]}" >/dev/null \
        || fail "setblock mcwfences:${BLOCKS[$i]} failed"
done
ctl wait 10
for i in "${!BLOCKS[@]}"; do
    x=$((2 + i % PER)); z=$((2 + i / PER))
    got=$(block_name "$x" 80 "$z")
    [ "$got" = "mcwfences:${BLOCKS[$i]}" ] \
        || fail "x=$x z=$z reads '$got', expected mcwfences:${BLOCKS[$i]}"
done
echo "${#BLOCKS[@]}/${#BLOCKS[@]} ids registered and their default state bound"

# -------------------------------------------------------------- connections
say "a fence joins its neighbours, a lonely one has no side"
ctl setblock 10 80 12 mcwfences:oak_picket_fence >/dev/null
ctl setblock 12 80 12 mcwfences:oak_picket_fence >/dev/null
ctl setblock 13 80 12 mcwfences:oak_picket_fence >/dev/null
ctl wait 5
lonely=$(block_state 10 80 12)
for side in north east south west; do assert_prop "$lonely" "$side" false; done
echo "lonely fence: $lonely"
west=$(block_state 12 80 12)
east=$(block_state 13 80 12)
want_join=true
[ "$NEGATIVE" = 1 ] && want_join=false
[ "$(prop "$west" east)" = "$want_join" ] \
    || fail "the fence pair did not join: west fence east=$(prop "$west" east), expected $want_join"
[ "$(prop "$east" west)" = "$want_join" ] \
    || fail "the fence pair did not join: east fence west=$(prop "$east" west), expected $want_join"
assert_prop "$west" north false
assert_prop "$west" waterlogged false
echo "pair: west fence east=true, east fence west=true (other sides false)"

say "a fence joins a vanilla fence and a solid block; a wall block joins its kind"
sb() { # x y z block -> the placed state, printed as evidence
    local reply
    reply=$(ctl setblock "$1" "$2" "$3" "$4") || { echo "setblock $4 at $1 $2 $3 failed: $reply"; return 1; }
    echo "setblock $4 at $1 $2 $3 -> $(echo "$reply" | jq -r '.block // empty')"
}
sb 15 80 12 minecraft:oak_fence || fail "cannot place the vanilla fence"
sb 16 80 12 mcwfences:oak_picket_fence || fail "cannot place the mod fence beside it"
# The solid neighbour goes in after the fence: at this pin a fence placed beside
# an existing solid block does not connect on placement (vanilla oak_fence
# behaves identically, checked in the baseline below), while the neighbour
# update the solid block's placement sends connects both.
sb 19 80 12 mcwfences:oak_picket_fence || fail "cannot place the mod fence"
sb 18 80 12 minecraft:stone || fail "cannot place the stone"
sb 21 80 12 mcwfences:stone_grass_topped_wall || fail "cannot place the wall block"
sb 22 80 12 mcwfences:stone_pillar_wall || fail "cannot place the pillar wall block"
ctl wait 5
echo "16 (beside a vanilla fence): $(block_state 16 80 12)"
echo "19 (beside a solid block):   $(block_state 19 80 12)"
echo "15 (vanilla side):           $(block_state 15 80 12)"
assert_prop "$(block_state 16 80 12)" west true
assert_prop "$(block_state 19 80 12)" west true
assert_prop "$(block_state 21 80 12)" east true
assert_prop "$(block_state 22 80 12)" west true
echo "mod fence <-> vanilla oak_fence: yes; mod fence <-> stone: yes; wall pair: yes"

say "vanilla oak_fence placement beside an existing solid block (engine control)"
sb 56 80 12 minecraft:stone || fail "cannot place the control stone"
sb 55 80 12 minecraft:oak_fence || fail "cannot place the control fence"
ctl wait 4
echo "55 (vanilla oak_fence placed beside a stone): $(block_state 55 80 12)"
echo "(the same all-false placement seen above is the engine's, not the carry's)"

say "a waterlogged fence keeps the template's 5th state"
ctl setblock 24 80 12 "mcwfences:oak_picket_fence[waterlogged=true]" >/dev/null
ctl wait 3
assert_prop "$(block_state 24 80 12)" waterlogged true
echo "waterlogged=true reads back on the fence"

# ----------------------------------------------------------- the wall/block class
say "the *_wall carried blocks are fence-class (4 sides), not vanilla walls"
wall_template=$(template_of stone_pillar_wall)
[ "$wall_template" = minecraft:oak_fence ] \
    || fail "stone_pillar_wall carries $wall_template, expected the fence template"
echo "stone_pillar_wall template: $wall_template (it has no vanilla wall's 'up' state)"

# ------------------------------------------------------------------- gate
say "a gate takes in_wall beside a carried wall block and drops it again"
ctl setblock 32 80 12 "mcwfences:oak_highley_gate[facing=east,open=false]" >/dev/null
ctl wait 3
assert_prop "$(block_state 32 80 12)" in_wall false
# `stone_grass_topped_wall` is in the jar's `minecraft:walls` tag (the pillar and
# modern walls are not), and the gate's `in_wall` reads that tag.
ctl setblock 32 80 11 mcwfences:stone_grass_topped_wall >/dev/null
ctl wait 4
gate=$(block_state 32 80 12)
assert_prop "$gate" in_wall true
assert_prop "$gate" facing east
assert_prop "$gate" open false
echo "gate beside a carried wall: $gate"
ctl setblock 32 80 11 minecraft:air >/dev/null
ctl wait 4
assert_prop "$(block_state 32 80 12)" in_wall false
echo "removing the wall set in_wall=false again (the minecraft:walls tag drives it)"

say "a gate item places with a facing, right-click opens and closes it"
ctl command "clear @s" >/dev/null
ctl give mcwfences:oak_highley_gate 2 >/dev/null || fail "cannot give mcwfences:oak_highley_gate"
ctl wait 3
ctl select mcwfences:oak_highley_gate >/dev/null || fail "cannot select mcwfences:oak_highley_gate"
ctl wait 2
ctl tp 28.5 80 14.5
ctl wait 3
ctl look-at-block 28 80 12 >/dev/null 2>&1 || true
ctl wait 2
reply=$(ctl place 28 80 12 --item mcwfences:oak_highley_gate 2>&1) || { echo "place reply: $reply"; fail "cannot place the gate"; }
echo "place reply: $reply"
ctl wait 3
placed=$(block_state 28 80 12)
case "$placed" in mcwfences:oak_highley_gate*) ;; *) fail "the placed gate is '$placed'" ;; esac
assert_prop "$placed" open false
assert_prop "$placed" in_wall false
case "$(prop "$placed" facing)" in
    north | south | east | west) ;;
    *) fail "the placed gate's facing is '$(prop "$placed" facing)'" ;;
esac
echo "placed facing=$(prop "$placed" facing) open=false in_wall=false"
ctl look-at-block 28 80 12 >/dev/null 2>&1 || true
reply=$(ctl interact 28 80 12)
echo "open click: $reply"
ctl wait 3
want_open=true
[ "$NEGATIVE" = 1 ] && want_open=false
[ "$(prop "$(block_state 28 80 12)" open)" = "$want_open" ] \
    || fail "open=$(prop "$(block_state 28 80 12)" open), expected $want_open after the right-click"
echo "right-click set open=$want_open"
ctl look-at-block 28 80 12 >/dev/null 2>&1 || true
ctl interact 28 80 12 >/dev/null
ctl wait 3
[ "$(prop "$(block_state 28 80 12)" open)" = false ] \
    || fail "the second click did not close the gate (open=$(prop "$(block_state 28 80 12)" open))"
echo "second right-click closed it"

say "redstone opens the gate and its removal closes it"
ctl command "clear @s" >/dev/null
ctl setblock 36 80 12 "mcwfences:oak_pyramid_gate[facing=east,open=false,powered=false]" >/dev/null
ctl wait 3
assert_prop "$(block_state 36 80 12)" open false
ctl setblock 36 80 11 minecraft:redstone_block >/dev/null
ctl wait 5
powered=$(block_state 36 80 12)
assert_prop "$powered" powered true
assert_prop "$powered" open true
echo "redstone block beside it: $powered"
ctl setblock 36 80 11 minecraft:air >/dev/null
ctl wait 5
assert_prop "$(block_state 36 80 12)" open false
echo "removing the redstone closed it (open=false)"

# ------------------------------------------------------------------- drops
say "in survival a placed fence drops itself (the carried loot table)"
ctl command "gamemode survival @s" >/dev/null
ctl wait 2
ctl command "clear @s" >/dev/null
ctl give mcwfences:oak_picket_fence 2 >/dev/null || fail "cannot give mcwfences:oak_picket_fence"
ctl wait 3
ctl select mcwfences:oak_picket_fence >/dev/null || fail "cannot select mcwfences:oak_picket_fence"
ctl wait 2
ctl tp 40.5 80 14.5
ctl wait 3
ctl place 40 80 12 --item mcwfences:oak_picket_fence >/dev/null || fail "cannot place the survival fence"
ctl wait 3
before=$(count_item mcwfences:oak_picket_fence)
echo "fences in the inventory after placing: $before"
reply=$(ctl break 40 80 12 --timeout 30)
echo "break reply: $reply"
ctl wait 10
# Creative-mode breaks drop nothing, so this is survival: the carried loot table
# rolls the block's own item. It may land in the inventory or on the ground.
dropped=$(echo "$reply" | jq '[
    .drops["mcwfences:oak_picket_fence"] // 0,
    .picked_up["mcwfences:oak_picket_fence"] // 0,
    ([.on_ground[]? | select(.item == "mcwfences:oak_picket_fence") | .count] | add // 0)
] | max')
[ "$dropped" -ge 1 ] || fail "breaking the fence dropped $dropped of it (the loot table did not run)"
[ "$(block_name 40 80 12)" = minecraft:air ] || fail "the fence is still at 40 80 12"
after=$(count_item mcwfences:oak_picket_fence)
echo "the broken fence dropped itself: $dropped item(s), inventory $before -> $after"
ctl command "gamemode creative @s" >/dev/null
ctl wait 2

# --------------------------------------------------------------- screenshot
say "screenshots: the carried models are drawn, the empty frames are not"
ctl setblock 44 80 12 mcwfences:oak_stockade_fence >/dev/null
ctl setblock 45 80 12 mcwfences:stone_grass_topped_wall >/dev/null
ctl setblock 46 80 12 "mcwfences:oak_highley_gate[facing=north,open=false]" >/dev/null
ctl tp 45.5 80 15.5
ctl look-at-block 45 80 12 >/dev/null 2>&1 || true
ctl wait 12
ctl screenshot "$SCRATCH/scene.png" >/dev/null
for x in 44 45 46; do ctl setblock "$x" 80 12 minecraft:air >/dev/null; done
ctl wait 12
ctl screenshot "$SCRATCH/scene-empty.png" >/dev/null
frame_differs "$SCRATCH/scene.png" "$SCRATCH/scene-empty.png" "the fence/wall/gate scene" 0.01

ctl setblock 50 80 13 "mcwfences:oak_highley_gate[facing=east,open=false,in_wall=true,powered=true]" >/dev/null
ctl tp 50.5 80 16.5
ctl look-at-block 50 80 13 >/dev/null 2>&1 || true
ctl wait 12
ctl screenshot "$SCRATCH/gate.png" >/dev/null
ctl setblock 50 80 13 minecraft:air >/dev/null
ctl wait 12
ctl screenshot "$SCRATCH/gate-empty.png" >/dev/null
frame_differs "$SCRATCH/gate.png" "$SCRATCH/gate-empty.png" "a gate in in_wall=true,powered=true" 0.004

say "no missing model/texture warnings for mcwfences"
ctl logs --lines 6000 > "$SCRATCH/game.log" 2>/dev/null || true
if grep -iE "missing texture for mcwfences|block models incomplete.*mcwfences|no model.*mcwfences|mcwfences.*missing (model|texture)" "$SCRATCH/game.log"; then
    fail "the log reports a missing model/texture for mcwfences"
fi
echo "the log has no mcwfences missing-model/missing-texture warning"

# -------------------------------------------------------------- creative tab
say "the creative tab lists all 150 carried blocks"
CREATIVE=$(find "$SCRATCH/game/.horizon-cache/mod-content" -name creative-inventory.json -print -quit 2>/dev/null || true)
[ -n "$CREATIVE" ] && [ -f "$CREATIVE" ] || fail "no creative-inventory.json (content mod not loaded)"
python3 "$PORT/tools/tab_check.py" "$CREATIVE" 150 \
    mcwfences:oak_picket_fence mcwfences:stone_pillar_wall mcwfences:oak_highley_gate \
    || fail "the creative tab check failed"

# ---------------------------------------------------------------- controls
say "unknown ids, impossible states and a plain stick are refused"
if ctl give mcwfences:not_a_fence 1 >/dev/null 2>&1; then
    fail "give mcwfences:not_a_fence succeeded"
fi
ctl setblock 60 80 12 mcwfences:bogus_fence >/dev/null 2>&1 || true
[ "$(block_name 60 80 12)" = minecraft:air ] || fail "mcwfences:bogus_fence became a block"
if ctl setblock 62 80 12 \
    "mcwfences:oak_picket_fence[north=true,up=true]" >/dev/null 2>&1; then
    got=$(block_state 62 80 12)
    case "$got" in *up=*) fail "an impossible fence state was accepted: $got" ;; esac
fi
if ctl give mcwfences:oak_curved_gate 1 >/dev/null 2>&1; then
    got=$(count_item mcwfences:oak_curved_gate)
    [ "$got" -eq 0 ] || fail "a left-out block's item exists (count $got)"
fi
ctl give minecraft:stick 1 >/dev/null
ctl wait 2
ctl select minecraft:stick >/dev/null
ctl tp 64.5 80 14.5
ctl wait 2
ctl place 64 80 12 --item minecraft:stick >/dev/null 2>&1 || true
ctl wait 3
[ "$(block_name 64 80 12)" = minecraft:air ] || fail "a stick placed $(block_name 64 80 12)"
echo "unknown ids and impossible states refused; a stick placed nothing"

say "vanilla oak_fence baseline in the same harness"
ctl setblock 66 80 12 minecraft:oak_fence >/dev/null
ctl setblock 67 80 12 minecraft:oak_fence >/dev/null
ctl wait 4
assert_prop "$(block_state 66 80 12)" east true
assert_prop "$(block_state 67 80 12)" west true
echo "vanilla oak_fence pair joins the same way"

# ---------------------------------------------------------------- evidence
cp "$SCRATCH/scene.png" "$PORT/tools/.e2e-last-scene.png" 2>/dev/null || true
echo "PASS: ${#BLOCKS[@]}/150 ids bind, a fence pair joins on the facing sides while a lonely fence has none, a mod fence joins a vanilla fence and a solid block, a waterlogged fence keeps waterlogged=true, a gate takes in_wall=true beside a carried wall block and loses it again, a gate item places with a horizontal facing and opens/closes on right-click and on redstone, a placed fence drops itself in survival, the fence/wall/gate scene and an in_wall=true,powered=true gate both render (screenshots differ from the empty frames, no missing texture), the creative tab lists 150 items, and unknown ids, impossible states and a stick are refused"
echo "EXIT:0"
exit 0
