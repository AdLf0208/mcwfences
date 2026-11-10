#!/usr/bin/env python3
"""Compare the carried mcwfences content against the 1.21.1 jar it came from.

Data-level fidelity check for the Macaw's Fences and Walls content port. It
reads the jar (read-only), the carried folder mod and the prepared 26.3 tables,
and asserts every carried block/item/recipe/loot/lang/model/texture matches
what the jar declares, that the 30 left-out blocks are exactly the ones with a
`fencepart` property (no vanilla template has it), and — the part that matters
most for a fence mod — that every state of every carried block is covered by
its blockstate once it carries the template's state space.

Exit 0 on success, 1 with the failures printed.

Usage:
    python3 tools/verify_content.py \
        [--jar ../../_shared/carry-work/mcwfences/jars/...jar] \
        [--content content] [--resources /path/to/26.3]
"""
from __future__ import annotations

import argparse
import glob
import itertools
import json
import os
import sys
import zipfile

FENCE = "minecraft:oak_fence"
GATE = "minecraft:oak_fence_gate"
SIDES = ("north", "east", "south", "west")


def load(path: str):
    with open(path, encoding="utf-8-sig") as handle:
        return json.load(handle)


def blockstate_props(raw: str) -> set[str]:
    """The property names a blockstate file mentions (variants or multipart)."""
    doc = json.loads(raw)
    props: set[str] = set()
    for key in doc.get("variants", {}):
        for part in key.split(","):
            if part:
                props.add(part.split("=")[0])
    for part in doc.get("multipart", []):
        when = part.get("when", {})
        for cond in [when, *when.get("OR", []), *when.get("AND", [])]:
            props.update(cond)
    return props


def bind(
    blockstate: dict, states: list[dict[str, str]]
) -> tuple[list[list[str] | None], list[str]]:
    """Horizon's `BlockStateDefinition::bind` over a template's state space.

    Returns the model references selected for each state (None = no model,
    a missing-model state) and the selectors that name an unknown property or
    value (Horizon skips those, so their states stay uncovered).
    """
    bound: list[list[str] | None] = [None] * len(states)
    bad: list[str] = []

    def predicate(key: str) -> dict[str, str] | None:
        out: dict[str, str] = {}
        for clause in key.split(","):
            name, _, value = clause.partition("=")
            if not name:
                continue
            if value and not any(state.get(name) == value for state in states):
                return None
            out[name] = value
        return out

    for key, variant in (blockstate.get("variants") or {}).items():
        pred = predicate(key)
        if pred is None:
            bad.append(key)
            continue
        for index, state in enumerate(states):
            if all(state.get(name) == value for name, value in pred.items()):
                if bound[index] is not None:
                    bound[index] = apply_models(variant)
                    break
                bound[index] = apply_models(variant)

    parts = []
    for part in blockstate.get("multipart") or []:
        when = part.get("when") or {}
        parts.append((when, apply_models(part.get("apply") or {})))

    def matches(when: dict, state: dict[str, str]) -> bool:
        if "OR" in when:
            return any(matches(w, state) for w in when["OR"])
        if "AND" in when:
            return all(matches(w, state) for w in when["AND"])
        return all(state.get(name) == value for name, value in when.items())

    for index, state in enumerate(states):
        if bound[index] is None:
            bound[index] = [
                model for when, models in parts if matches(when, state) for model in models
            ]
    return bound, bad


def apply_models(apply: dict) -> list[str]:
    entries = apply if isinstance(apply, list) else [apply]
    return [entry["model"] for entry in entries if "model" in entry]


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    port = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--jar",
        default=os.path.join(
            port,
            "../_shared/carry-work/mcwfences/jars/"
            "mcw-mcwfences-1.2.1-mc1.21.1neoforge.jar",
        ),
    )
    ap.add_argument("--content", default=os.path.join(port, "content"))
    ap.add_argument(
        "--resources",
        default=os.environ.get(
            "HORIZON_RES", os.path.expanduser("~/Desktop/horizon/.local/horizon-client/26.3")
        ),
    )
    args = ap.parse_args()

    failures: list[str] = []

    def check(ok: bool, msg: str) -> None:
        if not ok:
            failures.append(msg)

    def say(msg: str) -> None:
        print(f"ok: {msg}")

    z = zipfile.ZipFile(args.jar)
    names = {n for n in z.namelist() if not n.endswith("/")}

    jar_blocks = {}
    for n in sorted(names):
        if n.startswith("assets/mcwfences/blockstates/") and n.endswith(".json"):
            jar_blocks[n.rsplit("/", 1)[-1][:-5]] = blockstate_props(
                z.read(n).decode("utf-8-sig")
            )
    four = {b for b, p in jar_blocks.items() if p == set(SIDES)}
    gates = {b for b, p in jar_blocks.items() if p == {"facing", "open"}}
    part_fence = {b for b, p in jar_blocks.items() if p == set(SIDES) | {"fencepart"}}
    part_gate = {
        b for b, p in jar_blocks.items() if p == {"facing", "fencepart", "hinge", "open"}
    }
    say(
        f"jar: {len(jar_blocks)} blockstates = {len(four)} four-sided + "
        f"{len(gates)} gates + {len(part_fence)} metal fences + "
        f"{len(part_gate)} curved gates"
    )
    check(len(jar_blocks) == 180, f"expected 180 jar blockstates, found {len(jar_blocks)}")
    check(len(four) == 113, f"expected 113 four-sided blocks, found {len(four)}")
    check(len(gates) == 37, f"expected 37 gates, found {len(gates)}")
    check(len(part_fence) == 14, f"expected 14 metal fences, found {len(part_fence)}")
    check(len(part_gate) == 16, f"expected 16 curved gates, found {len(part_gate)}")
    left_out = part_fence | part_gate
    carried = four | gates
    say(f"skipped: {len(left_out)} blocks whose blockstate needs `fencepart`")

    # --- block declarations ------------------------------------------------
    decl = {
        os.path.basename(p)[:-5]: load(p)
        for p in glob.glob(
            os.path.join(args.content, "data/mcwfences/horizon/block/*.json")
        )
    }
    check(
        set(decl) == carried,
        f"declared blocks != jar blocks: {sorted(set(decl) ^ carried)[:8]}",
    )
    say(f"content: {len(decl)} block declarations, exactly the jar's fence and gate blocks")

    # --- templates and the state space -------------------------------------
    facts = load(os.path.join(args.resources, "facts.json"))
    schema: dict[str, dict[str, set[str]]] = {}
    template_states: dict[str, list[dict[str, str]]] = {}
    for entry in facts["states"]:
        name = entry[0]
        props = entry[-1].get("properties", {})
        for prop, value in props.items():
            schema.setdefault(name, {}).setdefault(prop, set()).add(value)
        template_states.setdefault(name, []).append(props)

    for template, expected in ((FENCE, four), (GATE, gates)):
        got = {b for b, d in decl.items() if d["template"] == template}
        check(got == expected, f"{template}: {len(got)} blocks, expected {len(expected)}")
        check(
            len(template_states[template]) == 32,
            f"{template} has {len(template_states[template])} states, expected 32",
        )
    say(
        "templates: 113 x minecraft:oak_fence + 37 x minecraft:oak_fence_gate, "
        "32 states each"
    )

    # --- every state of every block has a model ----------------------------
    universe = {
        template: [
            dict(zip(sorted(schema[template]), values))
            for values in itertools.product(
                *(sorted(schema[template][p]) for p in sorted(schema[template]))
            )
        ]
        for template in (FENCE, GATE)
    }
    for template, states in universe.items():
        check(len(states) == 32, f"{template}: state space is {len(states)}, expected 32")

    uncovered: list[str] = []
    bad_keys: list[str] = []
    model_refs: set[str] = set()
    for block in sorted(carried):
        template = decl[block]["template"]
        raw = os.path.join(args.content, "assets/mcwfences/blockstates", block + ".json")
        check(os.path.isfile(raw), f"missing blockstate asset for {block}")
        if not os.path.isfile(raw):
            continue
        doc = load(raw)
        bound, bad = bind(doc, universe[template])
        bad_keys.extend(f"{block}: {key}" for key in bad)
        missing = [
            f"{block} {json.dumps(state, sort_keys=True)}"
            for state, models in zip(universe[template], bound)
            if not models
        ]
        uncovered.extend(missing)
        for models in bound:
            model_refs.update(models or [])
    check(not bad_keys, f"variant selectors naming unknown values: {bad_keys[:5]}")
    check(
        not uncovered,
        f"{len(uncovered)} block states have no model (a missing model in game): "
        f"{uncovered[:4]}",
    )
    say(
        f"state space: {len(carried) * 32} states, all covered (fence `waterlogged`, "
        "gate `in_wall`/`powered` included)"
    )

    # --- model + texture resolution ---------------------------------------
    model_files = {
        p.rsplit("models/", 1)[-1][:-5]
        for p in glob.glob(
            os.path.join(args.content, "assets/mcwfences/models/**/*.json"),
            recursive=True,
        )
    }
    item_defs = {
        p.rsplit("/items/", 1)[-1][:-5]
        for p in glob.glob(os.path.join(args.content, "assets/mcwfences/items/*.json"))
    }
    for block in carried:
        check(block in item_defs, f"missing 26.3 item definition for {block}")
        if block in item_defs:
            item = load(os.path.join(args.content, "assets/mcwfences/items", block + ".json"))
            model = item.get("model")
            if isinstance(model, dict):
                model_refs.add(model.get("model", ""))
            elif isinstance(model, str):
                model_refs.add(model)

    def resolves_model(ref: str) -> bool:
        ns, _, path = ref.partition(":")
        if ns == "minecraft":  # vanilla model, in the prepared resources
            return os.path.isfile(
                os.path.join(args.resources, "assets/minecraft/models", path + ".json")
            )
        if ns and ns != "mcwfences":
            return False
        return path in model_files

    missing_models = sorted(m for m in model_refs if m and not resolves_model(m))
    check(not missing_models, f"referenced models missing: {missing_models[:8]}")
    say(
        f"models: {len(model_files)} present, {len(model_refs)} referenced by the "
        "carried blockstates and item definitions, 0 missing"
    )

    textures = {
        p.rsplit("textures/", 1)[-1][:-4]
        for p in glob.glob(
            os.path.join(args.content, "assets/mcwfences/textures/**/*.png"), recursive=True
        )
    }

    def split_ref(ref: str) -> tuple[str, str]:
        """`ns:path`, with a bare reference the vanilla namespace's."""
        if ":" in ref:
            ns, _, path = ref.partition(":")
            return ns, path
        return "minecraft", ref

    def model_doc(ref: str) -> dict | None:
        ns, path = split_ref(ref)
        if ns == "minecraft":
            path = os.path.join(args.resources, "assets/minecraft/models", path + ".json")
        elif ns == "mcwfences":
            path = os.path.join(args.content, "assets/mcwfences/models", path + ".json")
        else:
            return None
        return load(path) if os.path.isfile(path) else None

    def composed_textures(ref: str, seen: frozenset[str] = frozenset()) -> dict[str, str]:
        """The texture map a model ends up with: its own entries over its parent's.

        Macaw's models parent a shared `parent/*` model whose textures are
        placeholders (`mcwfences:block/cobblestone`) that every child overrides
        with the vanilla texture, exactly as vanilla model inheritance works.
        """
        if ref in seen:
            return {}
        doc = model_doc(ref)
        if doc is None:
            return {}
        out: dict[str, str] = {}
        parent = doc.get("parent")
        if isinstance(parent, str):
            out.update(composed_textures(parent, seen | {ref}))
        for key, value in (doc.get("textures") or {}).items():
            if isinstance(value, str):
                out[key] = value
        return out

    def resolves_texture(ref: str) -> bool:
        ns, path = split_ref(ref)
        if ns == "minecraft":  # a bare ref is the vanilla namespace's
            return os.path.isfile(
                os.path.join(args.resources, "assets/minecraft/textures", path + ".png")
            )
        if ns != "mcwfences":
            return False
        return path in textures

    # Only models a blockstate or item definition names directly: a parent
    # model's own texture map is a placeholder every child overrides.
    direct = sorted(m for m in model_refs if m.startswith("mcwfences:"))
    untextured: set[str] = set()
    parents: set[str] = set()
    for ref in direct:
        for value in composed_textures(ref).values():
            if isinstance(value, str) and not value.startswith("#"):
                untextured.add(value)
        parent = (model_doc(ref) or {}).get("parent")
        while isinstance(parent, str) and split_ref(parent)[0] == "mcwfences":
            parents.add(parent)
            parent = (model_doc(parent) or {}).get("parent")

    missing_textures = sorted(t for t in untextured if not resolves_texture(t))
    check(not missing_textures, f"missing textures: {missing_textures[:8]}")
    say(
        f"textures: {len(textures)} present, {len(direct)} models named by the carried "
        f"blockstates/items (+{len(parents)} mod parents), every texture resolves after "
        "parent inheritance"
    )

    # --- recipes ------------------------------------------------------------
    recipes = {
        os.path.basename(p)[:-5]: load(p)
        for p in glob.glob(os.path.join(args.content, "data/mcwfences/recipe/*.json"))
    }
    jar_recipes = {
        n.rsplit("/", 1)[-1][:-5]
        for n in names
        if n.startswith("data/mcwfences/recipe/") and n.endswith(".json")
    }
    expected_recipes = jar_recipes - left_out
    check(
        set(recipes) == expected_recipes,
        f"recipes differ from the jar (minus left-out blocks): "
        f"{sorted(set(recipes) ^ expected_recipes)[:8]}",
    )
    registered = {f"mcwfences:{b}" for b in carried}
    bad_result = [
        r
        for r, d in recipes.items()
        if d.get("result", {}).get("id") not in registered
    ]
    check(not bad_result, f"recipes with an unregistered result: {bad_result[:8]}")
    tag_uses = json.dumps(list(recipes.values()))
    check(
        "#c:" not in tag_uses and "forge:" not in tag_uses,
        "recipes still use NeoForge c:/forge: tags",
    )
    say(
        f"recipes: {len(recipes)} carried ({len(jar_recipes)} in the jar, "
        f"{len(jar_recipes) - len(recipes)} left out with their blocks), every result "
        "registered, no NeoForge tags"
    )

    # --- loot ---------------------------------------------------------------
    loot = {
        os.path.basename(p)[:-5]
        for p in glob.glob(
            os.path.join(args.content, "data/mcwfences/loot_table/blocks/*.json")
        )
    }
    check(loot >= carried, f"blocks without a loot table: {sorted(carried - loot)}")
    check(not (loot - carried - left_out), f"loot for unknown blocks: {sorted(loot - carried - left_out)}")
    say(
        f"loot: {len(loot)} tables = one per carried block + {len(loot - carried)} "
        "inert ones for the left-out blocks"
    )

    # --- lang ---------------------------------------------------------------
    lang = load(os.path.join(args.content, "assets/mcwfences/lang/en_us.json"))
    unnamed = [b for b in carried if f"block.mcwfences.{b}" not in lang]
    check(not unnamed, f"blocks without an en_us name: {unnamed[:8]}")
    check("itemGroup.mcwfences" in lang, "itemGroup.mcwfences is missing")
    say(f"lang: all {len(carried)} carried blocks named, itemGroup.mcwfences present")

    # --- tags ---------------------------------------------------------------
    tag_files = [p for p in names if "/tags/" in p]
    carried_tags = {
        p
        for p in glob.glob(
            os.path.join(args.content, "data/minecraft/tags/**/*.json"), recursive=True
        )
        + glob.glob(
            os.path.join(args.content, "data/mcwfences/tags/**/*.json"), recursive=True
        )
    }
    check(
        len(carried_tags) == 27,
        f"{len(carried_tags)} tag files carried, expected 27 (28 in the jar, "
        "the diagonalfences one is quarantined)",
    )
    merged = 0
    for path in carried_tags:
        ns_path = os.path.relpath(path, os.path.join(args.content, "data")).replace(os.sep, "/")
        raw = "data/" + ns_path
        check(raw in names, f"tag {ns_path} is not in the jar")
        if raw in names:
            values = load(path).get("values", [])
            check(
                values == json.loads(z.read(raw).decode("utf-8-sig")).get("values", []),
                f"tag {ns_path} differs from the jar",
            )
            merged += len(
                [v for v in values if isinstance(v, str) and v.startswith("mcwfences:")]
            )
    say(
        f"tags: {len(carried_tags)} files byte-equal to the jar's values, "
        f"{merged} mod ids named (30 for left-out blocks, dropped by the game)"
    )

    # --- creative tab -------------------------------------------------------
    tab = load(
        os.path.join(args.content, "data/mcwfences/horizon/creative_tab/fences.json")
    )
    tab_ids = [i.split(":", 1)[1] for i in tab["items"]]
    check(len(tab_ids) == 150, f"creative tab lists {len(tab_ids)} items, expected 150")
    check(
        set(tab_ids) == carried,
        f"creative tab != carried blocks: {sorted(set(tab_ids) ^ carried)[:8]}",
    )
    check(tab["title"] in lang, "the tab title key is not in en_us")
    say("creative tab: 150 items = every carried block, title key in en_us")

    if failures:
        print("\nFAILURES:")
        for failure in failures:
            print(f"  FAIL: {failure}")
        return 1
    print(
        f"\nPASS: {len(carried)} fence/gate blocks ({len(four)} fences + {len(gates)} "
        f"gates) and {len(recipes)} recipes match the 1.21.1 jar; all "
        f"{len(carried) * 32} states have a model, every texture resolves, and the "
        f"{len(left_out)} `fencepart` blocks are the only ones left out"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
