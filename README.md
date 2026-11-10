# Macaw's Fences and Walls — Horizon port

A port of [Macaw's Fences and Walls](https://github.com/sketchmacaw/Fences) by Sketch Macaw and Peachy Macaw for
Horizon. A data-tier carry: no native code and no hooks.

**Status:** the slice below is what works today; the second list is what is
missing. Nothing here claims parity with the original.

## What works

- 150 blocks: 113 four-sided fences, hedges, bamboo, cheval-de-frise and stone/modern
  walls on the vanilla fence template, and 37 highley, pyramid and railing gates on the
  vanilla fence-gate template.
- The mod's own blockstates, models, textures, 192 recipes, 180 loot tables, 27 tag
  files, 22 advancements and 14 language files.
- Fences connect to each other, to vanilla fences and to solid blocks, and `waterlogged`
  works; gates read `in_wall` from the `minecraft:walls` tag and open on right-click or
  redstone.
- A creative tab (`itemGroup.mcwfences`) listing the 150 carried blocks.

## Not yet ported

- 30 blocks are not carried: 14 metal fences (a placed three-block column with its own
  shape) and 16 curved/double gates (a two-block hinge); a vanilla template cannot
  express them, so their models and textures are inert.
- Wired fences do not damage entities that cross them (`entityInside` is code).
- Fence items do not burn in a furnace (upstream's `FuelItemBlock`).
- The two cheval-de-frise blocks use the vanilla fence outline and collision.
- Stone and metal gates share the wooden template's strength and flammability.

## Install

1. Take `mcwfences.hmod` from this repository (or build it below).
2. Put it in the game folder's `horizon-mods` folder — the game folder is the
   one holding `options.txt`.
3. Mods are off by default: enable this one in the game's mod list.

To try it without installing, start the game with
`--dev-mod mcwfences.hmod`.

## Build from source

This is a content-only mod: `content/horizon-mod.toml` plus `assets/` and
`data/`.

```sh
cd content && cargo horizon-mod build    # packs content/ into the .hmod and checks it
bash content/patches/apply.sh          # re-applies the 26.3 creative tab and the manifest
```

`cargo-horizon-mod` comes from the Horizon repository
(`cargo install --git https://github.com/horizon-rust/horizon cargo-horizon-mod`).
`tools/` holds the content generator and the in-game harness. The harness
expects a campaign checkout (`$CAMPAIGN_ROOT`) with the prepared 26.3 resources
(`$HORIZON_RES`, default `~/Desktop/horizon/.local/horizon-client/26.3`).

## Compatibility

- Horizon `1d63e0a` (see `compatibility.json` for the exact revision this
  artifact was built against).
- horizon-mixins `5a64af93`, schema 6.
- Minecraft: Java Edition 26.3.

## Credits

Macaw's Fences and Walls 1.2.1 by Sketch Macaw and Peachy Macaw — <https://github.com/sketchmacaw/Fences>.
The original copyright and licence notices are kept in
[LICENSE](LICENSE); [LICENSE-NOTICE.md](LICENSE-NOTICE.md) records where each
was read from.

This is an unofficial port: Horizon is not affiliated with the original author.

## Licence

MIT — see [LICENSE](LICENSE).

## Contributing

The "Not yet ported" list is the gap list; an issue or a pull request that
closes one item is welcome. Please keep the original notices and say which
slice you are working on.
