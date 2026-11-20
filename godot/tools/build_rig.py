"""Builds scripts/actors/rig_data.gd: where the hands are in every pose
frame, and where each held item is gripped.

Hands: the Toon character art has skin-coloured fists. Each frame's skin
pixels are split into connected blobs; the biggest is the face, the rest
are fists, the one further forward (+x, the art faces right) is the front
hand. A fist raised against the face merges with it; it is split back off
as that blob's top-front extreme.

Grips: each item icon's silhouette gives a principal axis. The narrower
end is the handle; the grip sits a little way in from it. The angle is
the direction from handle to head.

Run from godot/:  python3 tools/build_rig.py
"""
import json, math, os
from collections import deque
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAMES = ["idle", "walk0", "walk1", "walk2", "walk3", "walk4", "walk5", "walk6", "walk7",
          "run0", "run1", "run2", "jump", "fall", "attack0", "attack1", "attack2", "hurt",
          "interact", "hold", "hit", "fallDown", "cheer0", "cheer1", "talk"]
BODY_W, BODY_H = 192, 256
# AnimatedSprite2D centred, offset (0,-128), at (0,2): pixel -> player-local.
def to_local(x, y):
    return (x - BODY_W / 2, y - BODY_H / 2 - 128 + 2)


def skin(p):
    r, g, b, a = p
    return a > 200 and r > 200 and 150 < g < 225 and 110 < b < 190 and r - b > 50


def blobs(im, test):
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    out = []
    for y in range(h):
        for x in range(w):
            if seen[y * w + x] or not test(px[x, y]):
                continue
            q = deque([(x, y)]); seen[y * w + x] = 1; pts = []
            while q:
                cx, cy = q.popleft(); pts.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and test(px[nx, ny]):
                        seen[ny * w + nx] = 1; q.append((nx, ny))
            out.append(pts)
    return out


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def hands(path):
    im = Image.open(path).convert("RGBA")
    comps = sorted(blobs(im, skin), key=len, reverse=True)
    fists = []
    if comps and len(comps[0]) > 4200:
        face = sorted(comps[0], key=lambda p: -(p[0] * 0.6 - p[1] * 0.4))
        fists.append(face[:1150])
    fists += [c for c in comps[1:] if len(c) > 120]
    centres = sorted((centroid(f) for f in fists), key=lambda c: -c[0])
    front = to_local(*centres[0]) if centres else None
    back = to_local(*centres[1]) if len(centres) > 1 else front
    return front, back


def grip(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    pts = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] > 100]
    cx, cy = centroid(pts)
    sxx = sum((p[0] - cx) ** 2 for p in pts); syy = sum((p[1] - cy) ** 2 for p in pts)
    sxy = sum((p[0] - cx) * (p[1] - cy) for p in pts)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    ax, ay = math.cos(angle), math.sin(angle)
    proj = [((p[0] - cx) * ax + (p[1] - cy) * ay, (p[0] - cx) * -ay + (p[1] - cy) * ax) for p in pts]
    lo, hi = min(t for t, _ in proj), max(t for t, _ in proj)
    span = hi - lo
    def spread(a, b):
        side = [abs(s) for t, s in proj if a <= t <= b]
        return sum(side) / max(len(side), 1)
    lo_spread = spread(lo, lo + span * 0.25)
    hi_spread = spread(hi - span * 0.25, hi)
    if lo_spread > hi_spread:  # the head is at the low end: flip the axis
        ax, ay = -ax, -ay
        lo, hi = -hi, -lo
    handle = lo + span * 0.14
    gx, gy = cx + ax * handle, cy + ay * handle
    return (gx, gy), math.atan2(ay, ax), span


PARTS = ["head", "body", "arm", "hand", "leg"]


def layout(character):
    """Where each body part sits in the character's idle pose: top-left
    corners in pose pixels, found by template matching. The back arm,
    hand and leg are the mirrored part on the other side."""
    import numpy as np
    root = os.path.join(ROOT, "assets/characters", character)
    pose = np.asarray(Image.open(os.path.join(root, "idle.png")).convert("RGBA")).astype(np.float32)
    H, W = pose.shape[:2]
    found = {}
    for part in PARTS:
        for flip in (False, True):
            if flip and part in ("head", "body"):
                continue
            t = Image.open(os.path.join(root, "parts", part + ".png")).convert("RGBA")
            if flip:
                t = t.transpose(Image.FLIP_LEFT_RIGHT)
            t = np.asarray(t).astype(np.float32)
            th, tw = t.shape[:2]
            mask = t[..., 3] > 128
            best = (1e18, 0, 0)
            for y in range(0, H - th + 1):
                rows = pose[y:y + th]
                for x in range(0, W - tw + 1):
                    d = ((rows[:, x:x + tw, :3] - t[..., :3]) ** 2).sum(-1)[mask].mean()
                    if d < best[0]:
                        best = (d, x, y)
            key = part + ("_back" if flip else ("_front" if part in ("arm", "hand", "leg") else ""))
            found[key] = (best[1], best[2], tw, th)
    # Hair behind the head (some characters): mostly hidden by the head, so
    # place it where most of its pixels agree in colour with the pose.
    back_path = os.path.join(root, "parts", "back.png")
    if os.path.exists(back_path):
        t = np.asarray(Image.open(back_path).convert("RGBA")).astype(np.float32)
        th, tw = t.shape[:2]
        mask = t[..., 3] > 128
        best = (-1, 0, 0)
        for y in range(0, H - th + 1):
            for x in range(0, W - tw + 1):
                win = pose[y:y + th, x:x + tw]
                close = (np.abs(win[..., :3] - t[..., :3]).sum(-1) < 40) & mask & (win[..., 3] > 128)
                score = int(close.sum())
                if score > best[0]:
                    best = (score, x, y)
        found["back"] = (best[1], best[2], tw, th)
    return found


def main():
    lines = ['# Generated by tools/build_rig.py. Do not edit by hand.',
             'class_name RigData', 'extends RefCounted', '',
             '## Pose frame -> [front hand, back hand], in player-local pixels,',
             '## facing right.', 'const HANDS := {']
    for name in FRAMES:
        path = os.path.join(ROOT, "assets/characters/player", name + ".png")
        if not os.path.exists(path):
            continue
        f, b = hands(path)
        if f is None:
            continue
        lines.append('\t"%s": [Vector2(%.1f, %.1f), Vector2(%.1f, %.1f)],' % (name, f[0], f[1], b[0], b[1]))
    lines += ['}', '', '## Character -> part -> Rect2 of the part in the idle pose (pose pixels).',
              '## The cut-out rig hangs its joints off these.', 'const LAYOUT := {']
    for character in ("player", "zombie", "robot", "wren", "mira", "bram"):
        if not os.path.isdir(os.path.join(ROOT, "assets/characters", character, "parts")):
            continue
        found = layout(character)
        lines.append('\t"%s": {' % character)
        for key, (x, y, w, h) in found.items():
            lines.append('\t\t"%s": Rect2(%d, %d, %d, %d),' % (key, x, y, w, h))
        lines.append('\t},')
    lines += ['}', '', '## Icon -> [grip in icon pixels, handle-to-head angle (radians), length].',
              'const GRIPS := {']
    items = os.path.join(ROOT, "assets/items")
    for name in sorted(os.listdir(items)):
        if not name.endswith(".png"):
            continue
        stem = name[:-4]
        if not any(stem.startswith(k) for k in ("pick", "axe", "sword", "tool", "shovel", "hoe", "hammer")):
            continue
        (gx, gy), a, span = grip(os.path.join(items, name))
        lines.append('\t"items/%s": [Vector2(%.1f, %.1f), %.3f, %.1f],' % (stem, gx, gy, a, span))
    for extra in ("equipment/torch_held",):
        path = os.path.join(ROOT, "assets", extra + ".png")
        if os.path.exists(path):
            (gx, gy), a, span = grip(path)
            lines.append('\t"%s": [Vector2(%.1f, %.1f), %.3f, %.1f],' % (extra, gx, gy, a, span))
    lines.append('}')
    out = os.path.join(ROOT, "scripts/actors/rig_data.gd")
    with open(out, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote", out)




def side_heads():
    """The Toon pose set has one three-quarter view ('side'): the head
    turned toward the direction of travel. Cut that head out (keeping hair
    and skin, dropping the shirt collar below it) as parts/headSide.png, so
    the rig can face where it is going."""
    import numpy as np
    for character in ("player", "zombie", "wren", "mira", "bram"):
        root = os.path.join(ROOT, "assets/characters", character)
        src = os.path.join(root, "side.png")
        if not os.path.exists(src):
            continue
        a = np.asarray(Image.open(src).convert("RGBA")).copy()
        head = Image.open(os.path.join(root, "parts", "head.png"))
        hw, hh = head.size
        found = layout_head_only(a, hw, hh)
        x, y = found
        crop = a[y:y + hh, x:x + hw].copy()
        # The shirt is whatever colour this character's body part mostly is.
        body = np.asarray(Image.open(os.path.join(root, "parts", "body.png")).convert("RGBA")).astype(int)
        opaque = body[..., 3] > 200
        cols, counts = np.unique((body[opaque][:, :3] // 24), axis=0, return_counts=True)
        shirt_col = cols[counts.argmax()] * 24 + 12
        diff = np.abs(crop[..., :3].astype(int) - shirt_col).sum(-1)
        shirt = diff < 60
        low = np.zeros(crop.shape[:2], bool)
        low[int(hh * 0.80):, :] = True
        crop[..., 3][shirt & low] = 0
        Image.fromarray(crop).save(os.path.join(root, "parts", "headSide.png"))
        print("wrote", character, "headSide", (x, y))


def layout_head_only(pose, hw, hh):
    """Where the head sits in a pose: it is the topmost thing drawn, so it
    starts at the first opaque row, centred on the opaque columns just
    below that."""
    import numpy as np
    alpha = pose[..., 3] > 128
    rows = np.where(alpha.any(axis=1))[0]
    top = int(rows[0])
    cols = np.where(alpha[top:top + int(hh * 0.6)].any(axis=0))[0]
    x = int((cols[0] + cols[-1]) / 2 - hw / 2)
    return max(x, 0), top


if __name__ == "__main__":
    import sys
    if "--side-heads" in sys.argv:
        side_heads()
    else:
        main()
