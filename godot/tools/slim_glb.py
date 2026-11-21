"""Slim KayKit character GLBs: keep only the animations the game plays,
then rebuild the binary buffer so the dropped clips' data is gone.

Run from godot/:  python3 tools/slim_glb.py assets/models/kaykit/characters/*.glb
"""
import json, struct, sys

KEEP = {
    "Idle", "Walking_A", "Running_A", "Jump_Idle", "Jump_Land", "2H_Melee_Attack_Chop",
    "1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Stab", "Interact",
    "PickUp", "Dodge_Forward", "Hit_A", "Death_A", "Blocking", "Cheer", "Spellcast_Shoot", "Throw",
    "2H_Melee_Attack_Spin", "Spawn_Ground_Skeletons", "Taunt",
}


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67
    offset = 12
    json_chunk = bin_chunk = None
    while offset < length:
        size, kind = struct.unpack("<II", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + size]
        if kind == 0x4E4F534A:
            json_chunk = json.loads(body)
        elif kind == 0x004E4942:
            bin_chunk = body
        offset += 8 + size
    return json_chunk, bin_chunk


def write_glb(path, gltf, binary):
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binary += b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def slim(path):
    gltf, binary = read_glb(path)
    before = len(binary)
    gltf["animations"] = [a for a in gltf.get("animations", []) if a["name"] in KEEP]
    # Accessors still in use: everything but dropped animation samplers.
    used = set()
    def mark(i):
        if i is not None:
            used.add(i)
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            for i in prim["attributes"].values():
                mark(i)
            mark(prim.get("indices"))
            for target in prim.get("targets", []):
                for i in target.values():
                    mark(i)
    for skin in gltf.get("skins", []):
        mark(skin.get("inverseBindMatrices"))
    for anim in gltf["animations"]:
        for sampler in anim["samplers"]:
            mark(sampler["input"])
            mark(sampler["output"])
    used_views = {gltf["accessors"][i]["bufferView"] for i in used if "bufferView" in gltf["accessors"][i]}
    for image in gltf.get("images", []):
        if "bufferView" in image:
            used_views.add(image["bufferView"])
    # Repack the used buffer views, renumbering everything that points at them.
    new_views, view_map, out = [], {}, bytearray()
    for i, view in enumerate(gltf["bufferViews"]):
        if i not in used_views:
            continue
        start = view.get("byteOffset", 0)
        chunk = binary[start:start + view["byteLength"]]
        while len(out) % 4:
            out.append(0)
        new = dict(view)
        new["byteOffset"] = len(out)
        out += chunk
        view_map[i] = len(new_views)
        new_views.append(new)
    acc_map, new_accessors = {}, []
    for i, acc in enumerate(gltf["accessors"]):
        if i in used:
            acc = dict(acc)
            if "bufferView" in acc:
                acc["bufferView"] = view_map[acc["bufferView"]]
            acc_map[i] = len(new_accessors)
            new_accessors.append(acc)
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            prim["attributes"] = {k: acc_map[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = acc_map[prim["indices"]]
            if "targets" in prim:
                prim["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in prim["targets"]]
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = acc_map[skin["inverseBindMatrices"]]
    for anim in gltf["animations"]:
        for sampler in anim["samplers"]:
            sampler["input"] = acc_map[sampler["input"]]
            sampler["output"] = acc_map[sampler["output"]]
    for image in gltf.get("images", []):
        if "bufferView" in image:
            image["bufferView"] = view_map[image["bufferView"]]
    gltf["accessors"] = new_accessors
    gltf["bufferViews"] = new_views
    gltf["buffers"] = [{"byteLength": len(out)}]
    write_glb(path, gltf, bytes(out))
    print("%s: %d -> %d KB, %d clips" % (path, before // 1024, len(out) // 1024, len(gltf["animations"])))


for p in sys.argv[1:]:
    slim(p)
