"""Clipping test for rigged characters.

For every animation (NLA track) and several frames per animation it evaluates
the deformed meshes and reports:
  - hard parts (bone-attached objects) whose vertices sink into the skin/cloth
  - skin poking out through clothing (body vertices outside a garment that
    should cover them)

Run: blender -b source/blender/characters/<name>.blend --python source/blender/clip_check.py -- [tolerance_mm]
Prints "CLIP" lines and a final "CLIP_TOTAL <n>" summary (0 = clean).
"""
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TOL = float(args[0]) / 1000.0 if args else 0.0015          # 1.5 mm grace
SKIN_MATS = ("skin", "skin_real", "skin_patient", "skin_stubble", "skin_corpse", "skin_diseased", "porcelain_crack", "twin_face", "lip")
CLOTH_MATS = ("fabric", "gown_blue", "labcoat", "fabric_dark", "fabric_white", "fabric_bloody", "fabric_uniform")
SOFT_PARTS = ("cable", "lead", "loom", "wire", "strap", "line", "tube", "vein", "tear", "marker", "incision", "staple", "seam", "crack")

scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type == "ARMATURE")
flesh = next(o for o in scene.objects if o.type == "MESH" and o.parent == arm and o.parent_type == "OBJECT")
# "_inset" objects (eyeballs, sockets, pins) are embedded on purpose
parts = [o for o in scene.objects if o.type == "MESH" and o.parent == arm and o.parent_type == "BONE" and "_inset" not in o.name]


def split_tree(ob, depsgraph, mats):
    """BVH of the evaluated faces of `ob` whose material is in `mats`."""
    ev = ob.evaluated_get(depsgraph)
    me = ev.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(ob.matrix_world)
    names = [m.name.split(".")[0] if m else "" for m in me.materials]
    kill = [f for f in bm.faces if names[f.material_index] not in mats]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    tree = BVHTree.FromBMesh(bm) if bm.faces else None
    bm.normal_update()
    verts = [(v.co.copy(), v.normal.copy()) for v in bm.verts]
    bm.free()
    ev.to_mesh_clear()
    return tree, verts


DIRS = [Vector((0.31, 0.12, 0.94)).normalized(), Vector((-0.4, 0.8, -0.2)).normalized(), Vector((0.7, -0.5, 0.3)).normalized()]


def crossings(tree, p, d, limit=3.0):
    n, o = 0, p.copy()
    for _ in range(64):
        hit = tree.ray_cast(o, d, limit)
        if hit[0] is None:
            break
        n += 1
        o = hit[0] + d * 1e-5
    return n


def inside(tree, p, max_d=0.2):
    """Depth of p inside a closed mesh (positive = inside), via ray parity
    (majority of three directions) + distance to the nearest surface."""
    votes = sum(crossings(tree, p, d) % 2 for d in DIRS)
    if votes < 2:
        return -1.0
    hit = tree.find_nearest(p, max_d)
    return hit[3] if hit[0] is not None else max_d


total = 0
zs = []
tracks = list(arm.animation_data.nla_tracks) if arm.animation_data else []
for tr in tracks:
    for t2 in tracks:
        t2.mute = t2 is not tr
    strip = tr.strips[0]
    frames = sorted({int(strip.frame_start + (strip.frame_end - strip.frame_start) * k / 5) for k in range(6)})
    worst = {}
    where = {}
    for f in frames:
        scene.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        skin_tree, skin_verts = split_tree(flesh, dg, SKIN_MATS)
        cloth_tree, _ = split_tree(flesh, dg, CLOTH_MATS)
        # 1) hard parts sinking into skin or cloth
        for ob in parts:
            soft = any(k in ob.name for k in SOFT_PARTS)
            ev = ob.evaluated_get(dg)
            me = ev.to_mesh()
            mw = ob.matrix_world
            for v in list(me.vertices)[::3]:
                p = mw @ v.co
                for tree, label in ((skin_tree, "skin"), (cloth_tree, "cloth")):
                    if tree is None:
                        continue
                    d = inside(tree, p)
                    if d > TOL * (3 if soft else 1):
                        key = (ob.name, label)
                        if d > worst.get(key, 0):
                            worst[key] = d
                            where[key] = tuple(round(x, 3) for x in p)
            ev.to_mesh_clear()
        # 2) skin poking out through clothing: nothing covers the vertex on the
        #    outside, but there is cloth just beneath it -> it went through
        if cloth_tree is not None:
            for p, n in skin_verts[::4]:
                if cloth_tree.find_nearest(p, 0.03)[0] is None:
                    continue
                out_hit = cloth_tree.ray_cast(p + n * 0.0005, n, 0.06)[0]
                in_hit = cloth_tree.ray_cast(p - n * 0.0005, -n, 0.012)[0]
                if out_hit is None and in_hit is not None:
                    worst[("skin", "through_cloth")] = worst.get(("skin", "through_cloth"), 0) + 1
                    if f == frames[0] and tr is tracks[0]:
                        zs.append((round(p.x, 2), round(p.y, 2), round(p.z, 2)))
    for (name, label), d in sorted(worst.items()):
        total += 1
        unit = "verts" if label == "through_cloth" else "mm"
        val = d if label == "through_cloth" else d * 1000
        print(f"CLIP {tr.name:14s} {name:40s} into {label:14s} {val:7.1f} {unit}  at {where.get((name, label), '')}")
from collections import Counter
print("THROUGH_CLOTH_PTS", zs[::12])
print("CLIP_TOTAL", total)
