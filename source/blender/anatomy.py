"""Procedural humanoid anatomy for TIMBUK creatures.

- skeleton(): joint positions/radii for a 1.8 m humanoid in A-pose (faces -Y,
  so it faces +Z / the viewer in Godot, matching the glTF convention).
- body_mesh(): Blender Skin modifier over the joint tree + subdivision ->
  one continuous organic body mesh.
- head_mesh(): a sphere sculpted with gaussian bumps/dents into a face
  (brow, eye sockets, cheekbones, nose, lips, chin, jaw). Used for the
  failed experiments and for the twin monster's human lower face.
- rig(): armature from the same joints + distance-based skin weights.
- keyframe helpers to author animations as armature-space rotations.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

import tlib as T

# ------------------------------------------------------------------ skeleton

# name: (parent, (x, y, z), (radius_x, radius_y))   left side = +X
BASE = {
    "pelvis":     (None,        (0.0, 0.0, 1.0),    (0.15, 0.10)),
    "spine1":     ("pelvis",    (0.0, 0.01, 1.11),  (0.13, 0.09)),
    "spine2":     ("spine1",    (0.0, 0.01, 1.24),  (0.135, 0.09)),
    "chest":      ("spine2",    (0.0, 0.0, 1.37),   (0.16, 0.105)),
    "chest_up":   ("chest",     (0.0, 0.01, 1.47),  (0.15, 0.095)),
    "neck":       ("chest_up",  (0.0, 0.025, 1.56), (0.052, 0.05)),
    "neck_top":   ("neck",      (0.0, 0.02, 1.64),  (0.048, 0.046)),
    "clav.L":     ("chest_up",  (0.09, 0.02, 1.52), (0.055, 0.05)),
    "shoulder.L": ("clav.L",    (0.185, 0.03, 1.5), (0.052, 0.05)),
    "uarm.L":     ("shoulder.L", (0.25, 0.04, 1.39), (0.042, 0.042)),
    "elbow.L":    ("uarm.L",    (0.31, 0.05, 1.27), (0.033, 0.033)),
    "farm.L":     ("elbow.L",   (0.37, 0.03, 1.165), (0.033, 0.028)),
    "wrist.L":    ("farm.L",    (0.43, 0.01, 1.06), (0.025, 0.018)),
    "hand.L":     ("wrist.L",   (0.46, 0.0, 1.0),   (0.034, 0.014)),
    "hip.L":      ("pelvis",    (0.09, 0.0, 0.94),  (0.075, 0.075)),
    "thigh.L":    ("hip.L",     (0.095, 0.0, 0.74), (0.065, 0.065)),
    "knee.L":     ("thigh.L",   (0.1, -0.005, 0.52), (0.045, 0.045)),
    "calf.L":     ("knee.L",    (0.1, 0.015, 0.36), (0.05, 0.048)),
    "ankle.L":    ("calf.L",    (0.1, 0.03, 0.09),  (0.03, 0.03)),
    "foot.L":     ("ankle.L",   (0.1, -0.05, 0.04), (0.04, 0.025)),
    "toe.L":      ("foot.L",    (0.1, -0.13, 0.025), (0.038, 0.018)),
}

FINGERS = {  # relative to hand.L: (x, y, z) offsets of knuckle and tip
    "index":  ((0.03, -0.03, -0.05), (0.052, -0.04, -0.13)),
    "middle": ((0.035, -0.01, -0.056), (0.06, -0.012, -0.145)),
    "ring":   ((0.033, 0.01, -0.051), (0.056, 0.014, -0.13)),
    "pinky":  ((0.027, 0.028, -0.042), (0.044, 0.036, -0.105)),
    "thumb":  ((0.0, -0.04, -0.025), (0.012, -0.07, -0.075)),
}


def skeleton(arm_len=1.0, leg_len=1.0, thin=1.0, finger_len=1.0, asym=0.0, seed=0):
    """Returns {name: [parent, Vector pos, (rx, ry)]} with left and right sides."""
    rnd = random.Random(seed)
    j = {}
    for name, (parent, pos, rad) in BASE.items():
        j[name] = [parent, Vector(pos), (rad[0] * thin, rad[1] * thin)]
    # stretch arms from the shoulder, legs from the hip
    sh = j["shoulder.L"][1].copy()
    for n in ("uarm.L", "elbow.L", "farm.L", "wrist.L", "hand.L"):
        j[n][1] = sh + (j[n][1] - sh) * arm_len
    hip = j["hip.L"][1].copy()
    for n in ("thigh.L", "knee.L", "calf.L", "ankle.L", "foot.L", "toe.L"):
        p = j[n][1]
        if n in ("foot.L", "toe.L"):
            ank = BASE["ankle.L"][1]
            new_ank = hip + (Vector(ank) - hip) * leg_len
            j[n][1] = new_ank + (p - Vector(ank))
        else:
            j[n][1] = hip + (p - hip) * leg_len
    # keep feet on the floor: shift everything so the lowest point is at z=0
    low = min(v[1].z - v[2][1] for v in j.values())
    for v in j.values():
        v[1].z -= low
    hand = j["hand.L"][1]
    for f, (k, t) in FINGERS.items():
        kk = hand + Vector(k) * finger_len
        tt = hand + Vector(t) * finger_len
        mid = kk + (tt - kk) * 0.5
        j[f"{f}1.L"] = ["hand.L", kk, (0.011, 0.01)]
        j[f"{f}2.L"] = [f"{f}1.L", mid, (0.0095, 0.009)]
        j[f"{f}3.L"] = [f"{f}2.L", tt, (0.007, 0.007)]
    # mirror to the right side
    for name in list(j):
        if name.endswith(".L"):
            parent, pos, rad = j[name]
            rname = name[:-2] + ".R"
            rparent = parent[:-2] + ".R" if parent and parent.endswith(".L") else parent
            jitter = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * asym
            j[rname] = [rparent, Vector((-pos.x, pos.y, pos.z)) + jitter, rad]
    return j


# ------------------------------------------------------------------ body

def body_mesh(name, joints, material="skin", subdiv=2, exclude=()):
    """Skin-modifier body over the joint tree (head excluded; see head_mesh)."""
    names = [n for n in joints if n not in exclude]
    index = {n: i for i, n in enumerate(names)}
    me = bpy.data.meshes.new(name)
    verts = [tuple(joints[n][1]) for n in names]
    edges = [(index[joints[n][0]], index[n]) for n in names if joints[n][0] in index]
    me.from_pydata(verts, edges, [])
    ob = bpy.data.objects.new(name, me)
    T.link(ob)
    skin = ob.modifiers.new("skin", "SKIN")
    skin.branch_smoothing = 0.6
    skin.use_smooth_shade = True
    sv = me.skin_vertices[0].data
    for n, i in index.items():
        sv[i].radius = joints[n][2]
    sv[index["pelvis"]].use_root = True
    sub = ob.modifiers.new("subsurf", "SUBSURF")
    sub.levels = subdiv
    sub.render_levels = subdiv
    T.apply_all([ob])
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(T.mat(material))
    T.world_uv(ob)
    return ob


def sculpt(ob, fn):
    """Move each vertex: fn(co: Vector) -> new Vector (object space)."""
    for v in ob.data.vertices:
        v.co = fn(v.co.copy())
    ob.data.update()


def gauss(p, c, w):
    d = p - c
    return math.exp(-(d.x * d.x / (w[0] * w[0]) + d.y * d.y / (w[1] * w[1]) + d.z * d.z / (w[2] * w[2])))


# ------------------------------------------------------------------ head / face

def head_mesh(name, center, size=(0.075, 0.095, 0.115), material="skin", face=None, seg=64, rings=48):
    """Sculpted head. `face` dict tunes features (all optional):
    gaunt, cheek, brow, nose_len, nose_width, lip, mouth_open, jaw_width,
    chin, eye_depth, skull_back, no_eyes (flatten upper face for implants)."""
    f = {"gaunt": 0.3, "cheek": 0.6, "brow": 0.5, "nose_len": 1.0, "nose_width": 0.8,
         "lip": 0.6, "mouth_open": 0.0, "jaw_width": 0.8, "chin": 0.6, "eye_depth": 1.0,
         "skull_back": 0.6, "no_eyes": 0.0}
    f.update(face or {})
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    ob = T.mesh_obj(name, bm, material)
    rx, ry, rz = size
    V = Vector

    def shape(p):
        n = p.normalized()
        x, y, z = n
        r = 1.0
        # skull: longer at the back-top, flat-ish sides
        r += f["skull_back"] * 0.12 * gauss(n, V((0, 0.7, 0.45)), (0.7, 0.5, 0.5))
        r -= 0.06 * gauss(n, V((1, 0, 0.1)), (0.25, 0.6, 0.5)) + 0.06 * gauss(n, V((-1, 0, 0.1)), (0.25, 0.6, 0.5))
        # jaw: narrower toward the chin, front slightly forward
        if z < -0.1:
            t = min(1.0, (-z - 0.1) / 0.9)
            k = 1.0 - (1.0 - f["jaw_width"]) * 0.9 * t - 0.25 * t * t
            x *= k
            if y > 0:
                y *= 1.0 - 0.45 * t      # no back of skull under the jaw
        r += f["chin"] * 0.09 * gauss(n, V((0, -0.8, -0.62)), (0.22, 0.25, 0.18))
        # cheekbones and gaunt hollows
        for s in (-1, 1):
            r += f["cheek"] * 0.07 * gauss(n, V((0.55 * s, -0.75, -0.05)), (0.18, 0.2, 0.13))
            r -= f["gaunt"] * 0.08 * gauss(n, V((0.58 * s, -0.62, -0.38)), (0.17, 0.2, 0.15))
            # eye sockets + brow ridge
            if f["no_eyes"] < 0.5:
                r -= f["eye_depth"] * 0.1 * gauss(n, V((0.33 * s, -0.92, 0.12)), (0.14, 0.2, 0.09))
            r += f["brow"] * 0.05 * gauss(n, V((0.32 * s, -0.93, 0.26)), (0.2, 0.2, 0.06))
            # nostril wings
            r += f["nose_width"] * 0.05 * gauss(n, V((0.12 * s, -0.95, -0.22)), (0.06, 0.1, 0.06))
        # nose ridge: grows toward the tip
        if y < 0:
            tip = gauss(n, V((0, -1, -0.17)), (0.07 * f["nose_width"], 0.3, 0.07))
            ridge = gauss(V((x, 0, 0)), V((0, 0, 0)), (0.05 * f["nose_width"], 1, 1)) * max(0.0, min(1.0, (0.22 - z) / 0.4)) \
                * (1.0 if -0.22 < z < 0.22 else 0.0)
            r += f["nose_len"] * (0.22 * tip + 0.1 * ridge * (-y))
            # lips and mouth line
            r += f["lip"] * 0.045 * gauss(n, V((0, -0.97, -0.39)), (0.18, 0.2, 0.035))
            r += f["lip"] * 0.055 * gauss(n, V((0, -0.95, -0.47)), (0.16, 0.2, 0.04))
            r -= (0.02 + f["mouth_open"] * 0.2) * gauss(n, V((0, -1, -0.43)), (0.16 + f["mouth_open"] * 0.05, 0.3, 0.012 + f["mouth_open"] * 0.08))
        r += f["no_eyes"] * 0.04 * gauss(n, V((0, -0.9, 0.2)), (0.6, 0.3, 0.3))
        q = V((x, y, z)).normalized() * r
        return V((q.x * rx, q.y * ry, q.z * rz))

    sculpt(ob, shape)
    ob.location = center
    T.shade_smooth(ob, 80)
    T.world_uv(ob)
    return ob


def eyeballs(prefix, head_center, size, material="black_cavity", r=0.012, depth=0.82, spread=0.33, z=0.1):
    out = []
    rx, ry, rz = size
    for s in (-1, 1):
        p = Vector(head_center) + Vector((spread * s * rx, -depth * ry, z * rz))
        out.append(T.sphere(f"{prefix}_eye", r, tuple(p), material, 16, 10))
    return out


# ------------------------------------------------------------------ rig

BONE_CHAIN = [
    # bone name, head joint, tail joint
    ("root", None, None),
    ("pelvis", "pelvis", "spine1"), ("spine1", "spine1", "spine2"), ("spine2", "spine2", "chest"),
    ("chest", "chest", "chest_up"), ("chest_up", "chest_up", "neck"), ("neck", "neck", "neck_top"),
    ("head", "neck_top", "head_top"),
]
SIDE_CHAIN = [
    ("clav", "clav", "shoulder"), ("uarm", "shoulder", "elbow"), ("farm", "elbow", "wrist"), ("hand", "wrist", "hand"),
    ("thigh", "hip", "knee"), ("shin", "knee", "ankle"), ("foot", "ankle", "foot"), ("toe", "foot", "toe"),
]
PARENTS = {"pelvis": "root", "spine1": "pelvis", "spine2": "spine1", "chest": "spine2", "chest_up": "chest",
           "neck": "chest_up", "head": "neck", "clav": "chest_up", "uarm": "clav", "farm": "uarm", "hand": "farm",
           "thigh": "pelvis", "shin": "thigh", "foot": "shin", "toe": "foot"}


def rig(name, joints, head_top, fingers=True):
    """Armature from joints. Returns the armature object."""
    joints = dict(joints)
    joints["head_top"] = [None, Vector(head_top), (0, 0)]
    ad = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, ad)
    T.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = ad.edit_bones

    def add(bname, h, t, parent=None, roll_up=Vector((0, -1, 0))):
        b = eb.new(bname)
        b.head = h
        b.tail = t
        b.align_roll(roll_up)
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        return b

    add("root", Vector((0, 0, 0)), Vector((0, 0.25, 0)), roll_up=Vector((0, 0, 1)))
    for bname, hj, tj in BONE_CHAIN[1:]:
        add(bname, joints[hj][1], joints[tj][1], PARENTS[bname])
    for side in ("L", "R"):
        for bname, hj, tj in SIDE_CHAIN:
            h = joints[f"{hj}.{side}"][1]
            t = joints[f"{tj}.{side}"][1]
            if bname == "hand":
                t = h + (joints[f"middle1.{side}"][1] - h) * 1.0
            par = PARENTS[bname]
            par = par if par in ("pelvis", "chest_up") else f"{par}.{side}"
            add(f"{bname}.{side}", h, t, par, roll_up=Vector((0, 0, 1)) if bname in ("foot", "toe") else Vector((0, -1, 0)))
        if fingers:
            for fname in FINGERS:
                prev = f"hand.{side}"
                for k in (1, 2):
                    h = joints[f"{fname}{k}.{side}"][1]
                    t = joints[f"{fname}{k + 1}.{side}"][1]
                    add(f"{fname}{k}.{side}", h, t, prev)
                    prev = f"{fname}{k}.{side}"
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def skin_to(ob, arm, overrides=None, falloff=4.0, max_infl=3, bone_filter=None, parent=True):
    """Parent `ob` to `arm` with distance-based weights.

    overrides: list of (predicate(world_co) -> bone name) applied first, e.g.
    to force everything above the neck onto the head bone.
    """
    bones = [(b.name, arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local)
             for b in arm.data.bones if b.name != "root" and (bone_filter is None or bone_filter(b.name))]
    groups = {n: ob.vertex_groups.get(n) or ob.vertex_groups.new(name=n) for n, _, _ in bones}
    mw = ob.matrix_world
    for v in ob.data.vertices:
        p = mw @ v.co
        forced = None
        for pred, bname in (overrides or []):
            if pred(p):
                forced = bname
                break
        if forced:
            groups[forced].add([v.index], 1.0, "REPLACE")
            continue
        ds = sorted(((_seg_dist(p, h, t), n) for n, h, t in bones), key=lambda x: x[0])[:max_infl + 2]
        dmin = ds[0][0] + 1e-4
        ws = [(n, 1.0 / ((d + 1e-4) / dmin) ** falloff) for d, n in ds if d < dmin * 2.2 + 0.02]
        ws = sorted(ws, key=lambda x: -x[1])[:max_infl]
        tot = sum(w for _, w in ws)
        for n, w in ws:
            groups[n].add([v.index], w / tot, "REPLACE")
    if parent:
        ob.parent = arm
        ob.matrix_parent_inverse = arm.matrix_world.inverted()
        mod = ob.modifiers.new("armature", "ARMATURE")
        mod.object = arm


def attach_to_bone(ob, arm, bone):
    """Rigidly parent a hard-surface part (implant, gauge...) to a bone."""
    mw = ob.matrix_world.copy()
    ob.parent = arm
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    bpy.context.view_layer.update()
    ob.matrix_world = mw


# ------------------------------------------------------------------ animation

class Animator:
    """Author poses as armature-space axis/angle rotations per bone and
    keyframe them into named actions pushed onto NLA tracks."""

    def __init__(self, arm):
        self.arm = arm
        if not arm.animation_data:
            arm.animation_data_create()
        self.rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}

    def local(self, bone, axis, deg):
        """Armature-space rotation -> pose-bone local quaternion."""
        r = self.rest[bone]
        q = Quaternion(Vector(axis).normalized(), math.radians(deg))
        return r.inverted() @ q @ r

    def action(self, name, frames, pose_fn, loop=True, fps=30):
        """pose_fn(t in 0..1) -> {bone: [(axis, deg), ...], "_loc": Vector}"""
        act = bpy.data.actions.new(name)
        ad = self.arm.animation_data
        ad.action = act
        keys = sorted(set([0, frames] + list(range(0, frames + 1, 2))))
        for f in keys:
            t = f / frames
            pose = pose_fn(t if not loop or f < frames else 0.0)
            for pb in self.arm.pose.bones:
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.location = (0, 0, 0)
            for bone, rots in pose.items():
                if bone == "_loc":
                    pb = self.arm.pose.bones["root"]
                    pb.location = self.rest["root"].inverted() @ Vector(rots)
                    continue
                if bone not in self.arm.pose.bones:
                    continue
                q = Quaternion()
                for axis, deg in rots:
                    q = self.local(bone, axis, deg) @ q
                self.arm.pose.bones[bone].rotation_quaternion = q
            for pb in self.arm.pose.bones:
                pb.keyframe_insert("rotation_quaternion", frame=f + 1)
                if pb.name == "root":
                    pb.keyframe_insert("location", frame=f + 1)
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, act)
        strip.name = name
        ad.action = None
        return act


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)


def wave(t, phase=0.0, cycles=1.0):
    return math.sin((t * cycles + phase) * 2 * math.pi)


def spike(t, at, width=0.03):
    """Sharp twitch around time `at`."""
    d = (t - at) / width
    return math.exp(-d * d)
