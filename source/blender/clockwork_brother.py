"""The Twin, final design: the Clockwork Brother (graphics v3).

A tall, gaunt adult whose body has set wrong: spine arched back, head lolled
to one side, one shoulder hiked. His face is real (stubble, lids, lips) until
it reaches the brow, where the skin cracks into yellowed porcelain around a
brass clock set into the top of his skull (the reference painting + the v1
clock). Gauges sit in his eye sockets inside real eyelids; a lens eye with a
red pupil is set into the bridge of his nose. Cable looms leave the back of
the clock housing and the temples and run, evenly spaced and clear of the
skin, down his neck into a brass spine harness visible through a tear in his
lab coat.

Exported as assets/models/characters/twin_monster.glb (same name, so every
scene that used the twin picks this up). Bones/animations match the v2 twin.
Run: blender -b --factory-startup --python source/blender/clockwork_brother.py
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import tlib as T  # noqa: E402
import anatomy as A  # noqa: E402
import bodysdf as B  # noqa: E402
import realhead as H  # noqa: E402
import sdf as S  # noqa: E402
from patients import clear_path, curve, fit_ring, offset_shape, on_surface, sdf_grad  # noqa: E402
from twin_monster import add_extra_bones, disc, facing, ring, twin_animations  # noqa: E402

NAME = "twin_monster"
RND = random.Random(1985)


class Layout:
    def __init__(self, hc):
        self.hc = Vector(hc)
        self.clock_n = Vector((0, -0.62, 0.78)).normalized()          # dial faces up and forward
        self.clock_c = self.hc + Vector((0, -0.05, 0.092))
        self.clock_r = 0.064
        self.lens_c = self.hc + Vector((0, -0.094, 0.024))             # bridge of the nose
        self.lens_r = 0.017
        self.eyes = [self.hc + Vector((s * 0.032, -0.07, 0.008)) for s in (-1, 1)]
        self.pivot_n = self.clock_n                                     # used by twin_animations
        self.top = self.hc + Vector((0, 0.015, 0.13))


# ------------------------------------------------------------------ flesh

def flesh_shape(j, L):
    sh = B.body_shape(j, {"w": 0.86, "emaciated": 0.5, "muscle": 0.35})
    H.head(sh, L.hc, {"gaunt": 0.55, "cheekbone": 0.85, "brow": 0.45, "eye_open": 0.9, "jaw": 0.86,
                      "chin": 0.55, "lips": 0.4, "nose_len": 1.05, "nose_width": 0.95, "ear": 0.0})
    # clock housing seat: a cylindrical socket sunk into the top of the skull
    n = L.clock_n
    B.cut(sh, B.CAP(L.clock_c - n * 0.035, L.clock_c + n * 0.06, L.clock_r + 0.008), 0.004)
    # lens socket in the bridge of the nose
    B.cut(sh, B.SPH(L.lens_c + Vector((0, 0.004, 0)), L.lens_r + 0.002), 0.003)
    # temple ports where the looms enter
    for s in (-1, 1):
        B.cut(sh, B.SPH(L.hc + Vector((s * 0.069, 0.01, 0.03)), 0.009), 0.003)
    return sh


def assign_head_materials(ob, L):
    """Lower face = stubbled skin, skull above the crack line = porcelain."""
    me = ob.data
    me.materials.clear()
    for m in ("skin_real", "skin_stubble", "porcelain_crack"):
        me.materials.append(T.mat(m))
    hc = L.hc
    for poly in me.polygons:
        c = ob.matrix_world @ poly.center
        d = c - hc
        in_head = d.length < 0.17 and c.z > hc.z - 0.13
        if not in_head:
            poly.material_index = 0
            continue
        ang = math.atan2(d.x, -d.y)
        crack_z = 0.03 + 0.012 * math.sin(ang * 5.0) + 0.006 * math.sin(ang * 13.0 + 1.0)
        poly.material_index = 2 if d.z > crack_z else (1 if d.z < -0.035 and d.y < 0.03 else 0)


def crack_seam(shape, L, parts):
    """Dark fissures along the line where skin becomes porcelain."""
    pts = []
    for k in range(64):
        ang = -math.pi + k / 63 * 2 * math.pi
        z = 0.03 + 0.012 * math.sin(ang * 5.0) + 0.006 * math.sin(ang * 13.0 + 1.0)
        p = L.hc + Vector((math.sin(ang) * 0.09, -math.cos(ang) * 0.11, z))
        pts.append(on_surface(shape, p, 0.0013))
    parts.append((T.tube("seam", [tuple(p) for p in pts], 0.0012, "black_cavity", 5), "SKIN"))
    for k in range(9):                      # short branching cracks up into the porcelain
        i = RND.randrange(len(pts))
        a = pts[i]
        b = on_surface(shape, a + Vector((RND.uniform(-0.01, 0.01), 0, RND.uniform(0.01, 0.025))), 0.0003)
        parts.append((T.tube("crack", [tuple(a), tuple(b)], 0.0008, "black_cavity", 4), "SKIN"))


# ------------------------------------------------------------------ hardware

def clock(L, parts, bones):
    c, n, R = L.clock_c, L.clock_n, L.clock_r
    rot = facing(n)
    parts.append((disc("dial", c - n * 0.004, R, 0.008, "porcelain", rot, 96, planar=True), "head"))
    parts.append((disc("dial_well", c - n * 0.02, R + 0.006, 0.03, "black_cavity", rot, 64), "INSET:head"))
    parts.append((ring("bezel", c + n * 0.002, R + 0.006, 0.0075, "brass", rot, 128, 12), "head"))
    parts.append((ring("bezel_outer", c - n * 0.006, R + 0.012, 0.004, "copper", rot, 128, 8), "head"))
    q = facing(n).to_quaternion()
    parts.append((disc("glass", c + n * 0.006, R + 0.001, 0.002, "glass", rot, 64), "head"))
    hub = c + n * 0.001
    bones["clock_hour"] = (hub, hub + n * 0.03)
    bones["clock_minute"] = (hub, hub + n * 0.035)
    up = q @ Vector((0, 1, 0))
    for name, length, w, bone in (("hour_hand", R * 0.55, 0.005, "clock_hour"), ("minute_hand", R * 0.85, 0.0032, "clock_minute")):
        parts.append((T.box(name, (w, length + 0.01, 0.0015), tuple(hub + up * (length / 2 - 0.005)), "light_red", rot=tuple(rot), uv=False), bone))   # his unique accent: glowing red hands
    parts.append((T.cyl("hub_pin", 0.004, 0.006, tuple(hub + n * 0.002), "brass", rot=tuple(rot), seg=12), "head"))


def eyes_and_lens(L, parts, bones, lights):
    # gauges inside the lids where the eyes should be
    for side, ec in zip(("R", "L"), L.eyes):
        n = Vector((0.15 * (-1 if side == "R" else 1), -1, 0.05)).normalized()
        rot = facing(n)
        parts.append((T.sphere("gauge_ball", H.EYE_R * 0.98, tuple(ec), "teal_metal", 24, 16), "INSET:head"))
        # (inside the lids like a real eyeball: tagged INSET for the clip test)
        parts.append((disc("gauge_dial", ec + n * (H.EYE_R * 0.8), H.EYE_R * 0.62, 0.002, "gauge_eye", rot, 40, planar=True), "INSET:head"))
        hot = side == "R"      # twin duality: one gauge eye burns hot amber, its twin cold cyan
        parts.append((ring("gauge_rim", ec + n * (H.EYE_R * 0.84), H.EYE_R * 0.64, 0.0012, "light_amber" if hot else "light_cyan", rot, 40, 6), "INSET:head"))
        parts.append((disc("gauge_glass", ec + n * (H.EYE_R * 0.9), H.EYE_R * 0.62, 0.0008, "glass", rot, 32), "INSET:head"))
        bname = f"gauge_needle.{side}"
        bones[bname] = (ec + n * H.EYE_R * 0.85, ec + n * (H.EYE_R + 0.02))
        upv = facing(n).to_quaternion() @ Vector((0, 1, 0))
        parts.append((T.box("needle", (0.0008, H.EYE_R * 0.5, 0.0006), tuple(ec + n * H.EYE_R * 0.86 + upv * H.EYE_R * 0.2), "black_cavity", rot=tuple(rot), uv=False), bname))
        lights.append(("gauge", ec + n * 0.03, {"energy": 0.2, "range": 0.6, "color": [1.0, 0.55, 0.15] if hot else [0.3, 0.85, 1.0], "pulse": 0.6}))
    # lens eye in the bridge of the nose
    c, r = L.lens_c, L.lens_r
    n = Vector((0, -1, 0.15)).normalized()
    rot = facing(n)
    parts.append((T.cyl("lens_housing", r, 0.026, tuple(c - n * 0.008), "teal_metal", rot=tuple(rot), seg=40), "INSET:head"))
    parts.append((ring("lens_rim", c + n * 0.005, r - 0.001, 0.0028, "black_cavity", rot, 48, 8), "head"))
    bones["eye"] = (c - n * 0.006, c + n * 0.03)
    parts.append((disc("lens_iris", c + n * 0.0045, r - 0.004, 0.0015, "eye_iris", rot, 48, planar=True), "eye"))
    pupil = T.sphere("lens_pupil", 0.0042, tuple(c + n * 0.006), "eye_glow", 16, 10, scale=(1, 1, 0.5))
    pupil.rotation_euler = rot
    parts.append((pupil, "eye"))
    glass = T.sphere("lens_glass", r - 0.004, tuple(c + n * 0.003), "glass", 24, 12, scale=(1, 1, 0.4))
    glass.rotation_euler = rot
    parts.append((glass, "eye"))
    lights.append(("eye", c + n * 0.04, {"energy": 0.6, "range": 1.6, "color": [1.0, 0.25, 0.06], "flicker": 0.05}))


def looms(shape, L, j, parts, bones):
    """Three tidy cable looms (5 lanes each) from the clock housing and the
    temples down the back of the neck into the spine harness. Every lane is
    offset from its neighbours and pushed clear of the skin."""
    nk, cu = Vector(j["neck"][1]), Vector(j["chest_up"][1])
    harness_top = on_surface(shape, cu + Vector((0, 0.16, 0.05)), 0.012)
    starts = [
        ("wires.0", L.clock_c + L.clock_n * -0.01 + Vector((0, 0.05, 0.02)), Vector((0.0, 1, 0))),
        ("wires.1", L.hc + Vector((-0.07, 0.01, 0.03)), Vector((-1, 0.3, 0))),
        ("wires.2", L.hc + Vector((0.07, 0.01, 0.03)), Vector((1, 0.3, 0))),
    ]
    for bone, a, out in starts:
        bones[bone] = (a, a + out.normalized() * 0.05)
    bones["wires.3"] = (harness_top, harness_top + Vector((0, 0.05, 0)))
    mats = ["wire_black", "wire_red", "wire_copper", "wire_black", "rubber"]
    for li, (bone, a, out) in enumerate(starts):
        out = out.normalized()
        # loom centreline: off the skull, round the back of the head, down the neck
        back = L.hc + Vector((out.x * 0.05, 0.11, -0.02))
        neck_b = on_surface(shape, nk + Vector((out.x * 0.02, 0.08, 0.03)), 0.022)
        centre = [a + out * 0.006, a + out * 0.03 + Vector((0, 0.02, 0.01)), back, neck_b,
                  harness_top + Vector(((li - 1) * 0.022, 0.0, 0.02))]
        centre = [Vector(p) for p in clear_path(shape, [tuple(p) for p in curve(centre, 30)], 0.03)]
        for lane in range(5):
            ang = lane / 5 * 2 * math.pi
            lane_pts = []
            for i, p in enumerate(centre):
                t = (centre[min(i + 1, len(centre) - 1)] - centre[max(i - 1, 0)]).normalized()
                ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                u = t.cross(ref).normalized()
                v = t.cross(u)
                spread = 0.0055 * min(1.0, i / 4.0)          # lanes fan out from a single port
                lane_pts.append(p + (u * math.cos(ang) + v * math.sin(ang)) * spread)
            lane_pts = clear_path(shape, [tuple(p) for p in lane_pts], 0.004)
            parts.append((T.tube("loom_cable", lane_pts, 0.0017, mats[lane], 6), "SKIN"))
        port = T.cyl("loom_port", 0.009, 0.012, tuple(a), "brass", rot=tuple(facing(out)), seg=14)
        parts.append((port, "INSET:head"))


def spine_harness(shape, j, parts, lights):
    """Brass vertebral plates on the spine, shown through the tear in the coat."""
    prev = None
    for k, bone in enumerate(("spine1", "spine2", "chest", "chest_up")):
        z = Vector(j[bone][1]).z + 0.03
        for dz in (0.0, 0.055):
            p = on_surface(shape, Vector((0, 0.15, z + dz)), 0.0075)    # plate centre 7.5 mm off the skin
            _, n = sdf_grad(shape, np.array(tuple(p), np.float32))
            # thin side (12 mm) along the surface normal, so the plate lies flat on the spine
            parts.append((T.box("vert_plate", (0.045, 0.03, 0.012), tuple(p), "brass", rot=tuple(facing(n)), bevel=0.003), "SKIN"))
            if prev is not None:
                parts.append((T.tube("vert_link", [tuple(prev), tuple(p + n * 0.01)], 0.0035, "steel", 6), "SKIN"))
            prev = p + n * 0.01
    lights.append(("tower", prev + Vector((0, 0.05, 0)), {"energy": 0.25, "range": 1.0, "color": [1.0, 0.4, 0.12], "pulse": 0.4}))


def neck_brass(j, shape, parts):
    nk, nt = Vector(j["neck"][1]), Vector(j["neck_top"][1])
    for t in (0.25, 0.7):
        p = nk.lerp(nt, t)
        axis = (nt - nk).normalized()
        r = fit_ring(shape, p, axis, 0.004)
        parts.append((T.torus("neck_band", r, 0.003, tuple(p), "gold", rot=tuple(facing(axis)), seg=40, rseg=6), "SKIN"))


# ------------------------------------------------------------------ clothing

def lab_coat(j, body_shape):
    J = lambda n: Vector(j[n][1])
    sh = offset_shape(body_shape, 0.02)       # coat stays 2 cm off the skin everywhere
    pel, ch, cu = J("pelvis"), J("chest"), J("chest_up")
    B.add(sh, B.RC(pel + Vector((0, 0.01, 0)), cu, 0.135, 0.14), 0.05)
    B.add(sh, B.E(ch + Vector((0, 0.0, 0.03)), (0.15, 0.112, 0.17)), 0.06)
    B.add(sh, B.E(cu + Vector((0, 0.012, 0.0)), (0.17, 0.104, 0.08)), 0.06)
    B.add(sh, B.E(pel + Vector((0, 0.012, -0.14)), (0.168, 0.13, 0.26)), 0.08)     # coat skirt hangs to the knee
    for side in ("L", "R"):
        shp, el, wr = J(f"shoulder.{side}"), J(f"elbow.{side}"), J(f"wrist.{side}")
        B.add(sh, B.RC(cu + Vector((0, 0.01, 0.04)), shp + Vector((0, 0, 0.03)), 0.06, 0.055), 0.05)
        B.add(sh, B.RC(shp, el, 0.058, 0.05), 0.03)
        B.add(sh, B.RC(el, el.lerp(wr, 0.85), 0.05, 0.045), 0.02)
    chest_z = ch.z

    def folds(p):
        ang = np.arctan2(p[:, 1], p[:, 0])
        hang = np.clip((chest_z - p[:, 2]) / 0.45, 0.0, 1.0)
        n1 = S.value_noise3(p * np.array([1, 1, 0.12], np.float32), 8.0, seed=4)
        return -(0.007 * np.sin(ang * 11 + n1 * 3.0) * hang + 0.003 * S.value_noise3(p, 26.0, 5))
    sh.displace(folds)
    ob = S.mesh_from_sdf(NAME + "_coat", sh, (-0.75, -0.34, 0.25), (0.75, 0.34, 2.1), 0.0045, "labcoat", decimate=0.3, smooth_iter=1)
    hands = [(J(f"wrist.{sd}") - (J(f"wrist.{sd}") - J(f"elbow.{sd}")).normalized() * 0.03,
              J(f"hand.{sd}") + (J(f"hand.{sd}") - J(f"wrist.{sd}")) * 4) for sd in ("L", "R")]
    neck_a, neck_b = J("neck"), J("neck_top")
    hem_z = J("knee.L").z + 0.06

    def near(p, a, b, r):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        return (p - (a + ab * t)).length < r
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    pts = np.array([tuple(ob.matrix_world @ f.calc_center_median()) for f in bm.faces], np.float32)
    tears = S.value_noise3(pts, 14.0, seed=7)
    kill = []
    for f, c, tr in zip(bm.faces, pts, tears):
        c = Vector(c)
        ang = math.atan2(c.y, c.x)
        front_open = c.y < -0.04 and abs(c.x) < 0.035 + max(0.0, (cu.z - c.z)) * 0.05 and c.z < cu.z + 0.02
        back_tear = c.y > 0.05 and abs(c.x - 0.01 * math.sin(c.z * 40)) < 0.03 and pel.z - 0.05 < c.z < cu.z + 0.06
        hem = hem_z + 0.03 * math.sin(ang * 4) + (0.08 if abs(c.x) > 0.1 and c.y < 0 else 0)
        if (c.z < hem or front_open or back_tear or near(c, neck_a - Vector((0, 0.01, 0.04)), neck_b + Vector((0, 0, 0.3)), 0.095)
                or c.z > neck_b.z or any(near(c, a, b, 0.07) for a, b in hands)
                or tr > 0.9 or c.z < hem + 0.02 and tr > 0.6):
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    sol = ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = 1.0
    T.apply_all([ob])
    # shirt underneath (dark, buttoned) and trousers
    shirt = offset_shape(body_shape, 0.007)
    shirt.displace(lambda p: -0.002 * S.value_noise3(p, 30.0, 9))
    sh_ob = S.mesh_from_sdf(NAME + "_shirt", shirt, (-0.4, -0.3, 0.8), (0.4, 0.3, 1.9), 0.0045, "fabric_dark", decimate=0.3, smooth_iter=1)
    arms = [(J(f"shoulder.{sd}").lerp(J(f"elbow.{sd}"), 0.25), J(f"hand.{sd}")) for sd in ("L", "R")]
    bm = bmesh.new()
    bm.from_mesh(sh_ob.data)
    kill = [f for f in bm.faces if (sh_ob.matrix_world @ f.calc_center_median()).z > cu.z + 0.05
            or (sh_ob.matrix_world @ f.calc_center_median()).z < pel.z - 0.02
            or any(near(sh_ob.matrix_world @ f.calc_center_median(), a, b, 0.06) for a, b in arms)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(sh_ob.data)
    bm.free()
    pants = offset_shape(body_shape, 0.011)
    pants.displace(lambda p: -0.004 * S.value_noise3(p * np.array([1, 1, 0.3], np.float32), 14.0, 11))
    p_ob = S.mesh_from_sdf(NAME + "_pants", pants, (-0.3, -0.25, 0.0), (0.3, 0.25, 1.15), 0.0045, "fabric_dark", decimate=0.3, smooth_iter=1)
    bm = bmesh.new()
    bm.from_mesh(p_ob.data)
    ank = J("ankle.L").z + 0.05
    kill = [f for f in bm.faces if (p_ob.matrix_world @ f.calc_center_median()).z > pel.z + 0.07
            or (p_ob.matrix_world @ f.calc_center_median()).z < ank
            or any(near(p_ob.matrix_world @ f.calc_center_median(), a, b, 0.065) for a, b in arms)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(p_ob.data)
    bm.free()
    for o in (sh_ob, p_ob):
        sol = o.modifiers.new("solid", "SOLIDIFY")
        sol.thickness = 0.003
        sol.offset = 1.0
        T.apply_all([o])
    return ob, sh_ob, p_ob


# ------------------------------------------------------------------ build

def build():
    T.reset()
    j = A.skeleton(arm_len=1.08, leg_len=1.08, thin=0.84, finger_len=1.22, asym=0.004, seed=19)
    hc = Vector(j["neck_top"][1]) + Vector((0, -0.012, 0.09))
    L = Layout(hc)
    sh = flesh_shape(j, L)
    body = S.mesh_from_sdf(NAME + "_body", sh, (-0.72, -0.3, -0.02), (0.72, 0.3, 2.15), 0.0024, "skin_real", decimate=0.2)
    assign_head_materials(body, L)
    parts, bones, lights = [], {}, []
    clock(L, parts, bones)
    eyes_and_lens(L, parts, bones, lights)
    looms(sh, L, j, parts, bones)
    spine_harness(sh, j, parts, lights)
    neck_brass(j, sh, parts)
    crack_seam(sh, L, parts)
    coat, shirt, pants = lab_coat(j, sh)
    arm = A.rig(NAME + "_rig", j, L.top)
    add_extra_bones(arm, bones)
    neck_z = Vector(j["neck_top"][1]).z
    head_rule = [(lambda p: p.z > neck_z + 0.02 and abs(p.x) < 0.16, "head")]
    A.skin_to(body, arm, overrides=head_rule, parent=False, bone_filter=lambda n: n not in bones)
    no_hands = lambda n: n not in bones and not any(n.startswith(k) for k in ("index", "middle", "ring", "pinky", "thumb", "hand"))
    no_upper = lambda n: n in ("pelvis", "spine1") or any(n.startswith(k) for k in ("thigh", "shin", "foot", "toe"))
    soft = [ob for ob, bone in parts if bone == "SKIN"]
    for m in [coat, shirt, pants] + soft:
        A.copy_weights(body, m)
    flesh = T.join([body, coat, shirt, pants] + soft, NAME + "_flesh")
    flesh.parent = arm
    flesh.matrix_parent_inverse = arm.matrix_world.inverted()
    flesh.modifiers.new("armature", "ARMATURE").object = arm
    by_bone = {}
    for ob, bone in parts:
        if bone != "SKIN":
            by_bone.setdefault(bone, []).append(ob)
    rigid = []
    for bone, obs in by_bone.items():
        inset = bone.startswith("INSET:")
        bone = bone.split(":")[-1]
        joined = T.join(obs, f"{NAME}_{bone.replace('.', '_')}_{'inset' if inset else 'parts'}")
        T.shade_smooth(joined, 35)
        A.attach_to_bone(joined, arm, bone)
        rigid.append(joined)
    for i, (kind, pos, props) in enumerate(lights):
        e = T.empty(f"L__{kind}__{i}", tuple(pos), props=props)
        A.attach_to_bone(e, arm, {"eye": "eye", "tower": "chest_up"}.get(kind, "head"))
        rigid.append(e)
    anim = A.Animator(arm)
    twin_animations(anim, L, contort=1.0)
    T.save_blend(f"source/blender/characters/{NAME}.blend")
    T.export_glb(f"assets/models/characters/{NAME}.glb", [arm, flesh] + rigid, animations=True)


if __name__ == "__main__":
    build()
