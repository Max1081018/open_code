#!/usr/bin/env python3
"""Builds forge-core's Horizon API knowledge base from a Horizon checkout.

Everything the reconstruction agent may cite about Horizon's API comes out of this file, so
nothing in it is written by hand: hook points and their doc comments from the hook sources,
goal types and constructors from `mobs/goals.rs`, the `mod_api` re-exports, and the sections of
the mod documentation. The checkout's revision is stamped so a stale index is visible.

    python3 tools/build-horizon-api-index.py /path/to/horizon \
        > forge-core/src/main/resources/rustmodforge/horizon-api.json
"""
import json
import os
import re
import subprocess
import sys


def doc_comments_before(lines, idx):
    out = []
    j = idx - 1
    while j >= 0:
        s = lines[j].strip()
        if s.startswith("///"):
            out.insert(0, s[3:].strip())
        elif s.startswith("#[") or s == "":
            pass
        else:
            break
        j -= 1
    return " ".join(out).strip()


def hooks(root):
    catalog = json.load(open(os.path.join(root, "native-hooks.json")))
    by_target = {}
    # Doc comments for every native_* fn in the hook sources.
    for rel in ["crates/horizon-client/src/game/native_hooks.rs", "crates/horizon-client/src/game/native_mobs.rs",
                "crates/horizon-client/src/game/native_entities.rs", "crates/horizon-client/src/game/native_entity_refs.rs",
                "crates/horizon-client/src/game/native_mob_draw.rs", "crates/horizon-client/src/game/native_block_entity_draw.rs",
                "crates/horizon-client/src/game/native_client_services.rs", "crates/horizon-client/src/game/native_motion.rs"]:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            continue
        lines = open(path, encoding="utf-8").read().split("\n")
        for i, line in enumerate(lines):
            m = re.match(r"\s*pub(?:\(\w+\))?\s+fn\s+(native_\w+)\s*(\(.*)", line)
            if not m:
                continue
            name = m.group(1)
            # Signature may span several lines: read until the opening brace.
            sig = m.group(2)
            k = i
            while "{" not in sig and k + 1 < len(lines) and k - i < 12:
                k += 1
                sig += " " + lines[k].strip()
            sig = re.sub(r"\s+", " ", sig.split("{")[0]).strip()
            by_target[name] = {"signature": f"fn {name}{sig}", "doc": doc_comments_before(lines, i), "file": rel}
    out = []
    for h in catalog["hooks"]:
        fn = "native_" + h["name"]
        src = by_target.get(fn, {})
        out.append({
            "kind": "hook", "name": h["name"], "version": h.get("version", 1), "side": h.get("side", ""),
            "contract": (h.get("mod_api") or {}).get("contract", ""), "neoforge": h.get("neoforge", ""),
            "trait_method": h["name"], "event_type": "".join(w[:1].upper() + w[1:] for w in h["name"].split("_")) + "Event",
            "signature": src.get("signature", ""), "doc": src.get("doc", ""), "file": src.get("file", ""),
        })
    helpers = []
    for h in catalog["helpers"]:
        fn = "native_" + h["name"]
        src = by_target.get(fn, {})
        helpers.append({"kind": "helper", "name": h["name"], "host_method": h["name"], "signature": src.get("signature", ""),
                        "doc": src.get("doc", ""), "file": src.get("file", "")})
    return out, helpers


def goals(root):
    path = os.path.join(root, "crates/horizon-client/src/mobs/goals.rs")
    lines = open(path, encoding="utf-8").read().split("\n")
    out = []
    current = None
    for i, line in enumerate(lines):
        m = re.match(r"pub struct (\w+)", line)
        if m:
            current = {"kind": "goal", "name": m.group(1), "path": f"horizon_client::mobs::goals::{m.group(1)}",
                       "doc": doc_comments_before(lines, i), "constructors": [], "file": "crates/horizon-client/src/mobs/goals.rs"}
            out.append(current)
            continue
        m = re.match(r"\s*pub fn (new\w*)\s*(\([^)]*\))\s*->", line)
        if m and current and lines[i - 1:i] and "impl" not in line:
            current["constructors"].append(f"{current['name']}::{m.group(1)}{m.group(2)}")
        if re.match(r"impl Goal for (\w+)", line):
            pass
    # Only types that implement Goal are goals a mod can add.
    text = "\n".join(lines)
    impls = set(re.findall(r"impl Goal for (\w+)", text))
    out = [g for g in out if g["name"] in impls]
    # Public free functions and the trait itself.
    trait_m = re.search(r"pub trait Goal[^{]*\{(.*?)\n\}", text, re.S)
    trait_methods = re.findall(r"fn (\w+)\([^)]*\)[^;{]*", trait_m.group(1)) if trait_m else []
    flags = re.findall(r"pub const (\w+): u8 = (\d+);", text)
    return out, trait_methods, flags


def exports(root):
    path = os.path.join(root, "crates/horizon-client/src/mod_api.rs")
    text = open(path, encoding="utf-8").read()
    out = []
    for m in re.finditer(r"pub use ([\w:]+)::\{([^}]*)\};", text, re.S):
        base = m.group(1)
        for name in re.split(r",\s*", m.group(2).replace("\n", " ")):
            name = name.strip()
            if name and not name.startswith("//"):
                out.append({"kind": "export", "name": name.split(" as ")[-1].strip(), "path": f"{base}::{name.split(' as ')[0].strip()}"})
    for m in re.finditer(r"pub use ([\w:]+)::(\w+);", text):
        out.append({"kind": "export", "name": m.group(2), "path": f"{m.group(1)}::{m.group(2)}"})
    return out


def mob_fields(root):
    """Public fields of Mob, MobWorld, PlayerView, GoalSelector and Cx, which goals read."""
    out = []
    targets = {"Mob": "crates/horizon-client/src/mobs.rs", "MobWorld": "crates/horizon-client/src/mobs.rs",
               "PlayerView": "crates/horizon-client/src/mobs.rs", "Cx": "crates/horizon-client/src/mobs/goals.rs",
               "GoalSelector": "crates/horizon-client/src/mobs/goals.rs", "Ai": "crates/horizon-client/src/mobs/ai.rs"}
    for ty, rel in targets.items():
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            continue
        text = open(path, encoding="utf-8").read()
        m = re.search(r"pub struct %s\b[^{]*\{(.*?)\n\}" % ty, text, re.S)
        if not m:
            continue
        fields = re.findall(r"\n\s*pub (\w+): ([^,\n]+),", m.group(1))
        out.append({"kind": "struct", "name": ty, "file": rel, "fields": [f"{n}: {t.strip()}" for n, t in fields][:60]})
        # Public methods of the type's inherent impls, wherever the crate spreads them.
        extra = {"Mob": ["crates/horizon-client/src/mobs/nav.rs", "crates/horizon-client/src/mobs/goals.rs", "crates/horizon-client/src/mobs/control.rs"],
                 "GoalSelector": [], "Cx": [], "Ai": [], "MobWorld": ["crates/horizon-client/src/mobs/world.rs"], "PlayerView": []}
        for mrel in [rel] + extra.get(ty, []):
            mpath = os.path.join(root, mrel)
            if not os.path.exists(mpath):
                continue
            mtext = open(mpath, encoding="utf-8").read()
            for im in re.finditer(r"impl(?:<[^>]*>)? %s(?:<[^>]*>)? \{(.*?)\n\}" % ty, mtext, re.S):
                methods = re.findall(r"\n\s*pub fn (\w+)(\([^)]*\))(?: -> ([^{]+))?", im.group(1))
                out[-1].setdefault("methods", []).extend(f"{n}{a}" + (f" -> {r.strip()}" if r else "") for n, a, r in methods)
        if "methods" in out[-1]:
            out[-1]["methods"] = sorted(set(out[-1]["methods"]))[:120]
    return out


def doc_sections(root):
    out = []
    for rel in ["docs/native-mods.md", "docs/mods.md", "docs/api/mod-files.md"]:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            continue
        text = open(path, encoding="utf-8").read()
        parts = re.split(r"\n(?=#{1,4} )", text)
        for p in parts:
            head, _, body = p.partition("\n")
            if not head.startswith("#"):
                continue
            body = re.sub(r"\n{3,}", "\n\n", body.strip())
            if len(body) < 40:
                continue
            out.append({"kind": "doc", "name": head.lstrip("# ").strip(), "file": rel, "text": body[:2400]})
    return out


def main():
    root = sys.argv[1]
    rev = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    api = re.search(r"NATIVE_HOOKS_API: u32 = (\d+)", open(os.path.join(root, "crates/horizon-client/src/game/native_hooks.rs")).read())
    hook_list, helper_list = hooks(root)
    goal_list, trait_methods, flags = goals(root)
    index = {
        "source": {"repository": "github.com/horizon-rust/horizon", "revision": rev, "native_hooks_api": int(api.group(1)) if api else None,
                   "generated_by": "tools/build-horizon-api-index.py"},
        "goal_trait": {"methods": trait_methods, "flags": {k: int(v) for k, v in flags}},
        "hooks": hook_list, "helpers": helper_list, "goals": goal_list, "structs": mob_fields(root), "exports": exports(root), "docs": doc_sections(root),
    }
    json.dump(index, sys.stdout, indent=1)
    print(f"hooks={len(hook_list)} helpers={len(helper_list)} goals={len(goal_list)} structs={len(index['structs'])} exports={len(index['exports'])} docs={len(index['docs'])}", file=sys.stderr)


if __name__ == "__main__":
    main()
