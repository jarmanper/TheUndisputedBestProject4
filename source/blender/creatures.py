"""TIMBUK failed-experiment creatures (secondary enemies, visuals only).

Variants (each exported rigged + animated to assets/models/characters/):
  failed_humanoid     - pale, gaunt, surgical scars, hospital gown, long arms
  augmented_subject   - same base with brass/teal implants, spine rods, cables
  chemical_subject    - burned, discoloured skin, swollen asymmetric limbs,
                        corroded implants and glowing residue

Animations (in place, no root motion): idle, walk, react, twitch.
Run:  blender -b --factory-startup --python source/blender/creatures.py [-- name ...]
"""
import math
import os
import random
import sys

import numpy as np

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import tlib as T  # noqa: E402
import anatomy as A  # noqa: E402
import bodysdf as B  # noqa: E402
import sdf as S  # noqa: E402
from anatomy import X, Y, Z, wave, spike  # noqa: E402


def gown(body, name, material="fabric", top_z=1.5, bottom_z=0.62, seed=0, thickness=0.012, joints=None):
    """Loose hospital gown: a smooth SDF shell around torso + thighs (so it
    drapes between the legs like cloth), arm/neck holes, wavy torn hem."""
    j = joints
    J = lambda n: Vector(j[n][1])
    sh = S.Shape()
    pel, ch, cu = J("pelvis"), J("chest"), J("chest_up")
    B.add(sh, B.RC(pel + Vector((0, 0.01, 0)), cu, 0.13, 0.135), 0.05)          # waist: keeps top and skirt joined
    B.add(sh, B.E(ch + Vector((0, 0.0, 0.03)), (0.145, 0.11, 0.17)), 0.06)
    B.add(sh, B.E(cu + Vector((0, 0.01, -0.0)), (0.16, 0.1, 0.08)), 0.06)
    B.add(sh, B.E(pel + Vector((0, 0.01, -0.02)), (0.16, 0.115, 0.1)), 0.1)
    for side in ("L", "R"):
        hip, kn = J(f"hip.{side}"), J(f"knee.{side}")
        B.add(sh, B.RC(hip, hip.lerp(kn, 0.85), 0.088, 0.08), 0.1)
        shp = J(f"shoulder.{side}")
        B.add(sh, B.RC(cu + Vector((0, 0.01, 0.04)), shp + Vector((0, 0, 0.025)), 0.055, 0.05), 0.05)
    # mesh the solid gown volume; its outer skin becomes the cloth after we cut openings
    ob = S.mesh_from_sdf(name, sh, (-0.42, -0.32, 0.3), (0.42, 0.32, 1.7), 0.006, material, decimate=0.25, smooth_iter=3)
    arm_caps = [(J(f"shoulder.{sd}"), J(f"elbow.{sd}")) for sd in ("L", "R")]
    neck_a, neck_b = J("neck"), J("neck_top")

    def near_seg(p, a, b, r):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        return (p - (a + ab * t)).length < r
    import bmesh
    rnd = random.Random(seed)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        ang = math.atan2(c.y, c.x)
        hem = bottom_z + 0.04 * math.sin(ang * 3 + seed) + 0.025 * math.sin(ang * 7 + 1.3 * seed) + 0.012 * math.sin(c.x * 60)
        cw = ob.matrix_world @ c
        if c.z < hem or c.z > top_z + 0.04 * math.sin(ang * 2) \
                or any(near_seg(cw, a + (a - b).normalized() * 0.03, b, 0.062) for a, b in arm_caps) \
                or near_seg(cw, neck_a, neck_b + Vector((0, 0, 0.2)), 0.07):
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # drop loose bits left by the cut
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    sol = ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.005
    sol.offset = 1.0
    T.apply_all([ob])
    return ob


def project(body, pts, direction=(0, 1, 0), lift=0.002):
    """Snap points onto the body surface by casting rays along `direction`."""
    d = Vector(direction).normalized()
    inv = body.matrix_world.inverted()
    out = []
    for p in pts:
        p = Vector(p)
        origin = p - d * 0.5
        hit, loc, nrm, _ = body.ray_cast(inv @ origin, inv.to_3x3() @ d)
        if hit:
            w = body.matrix_world @ loc
            out.append(tuple(w + (body.matrix_world.to_3x3() @ nrm).normalized() * lift))
        else:
            out.append(tuple(p))
    return out


def scar(points, r=0.004, stitches=True, mat="lip"):
    out = [T.tube("scar", points, r, mat, 6)]
    if stitches:
        for a, b in zip(points, points[1:]):
            a, b = Vector(a), Vector(b)
            d = (b - a)
            n = int(d.length / 0.018)
            side = d.normalized().cross(Vector((0, -1, 0))).normalized() * 0.008
            for k in range(n):
                p = a + d * (k + 0.5) / n
                out.append(T.tube("stitch", [tuple(p - side), tuple(p + side)], 0.0016, "wire_black", 4))
    return out


def humanoid_base(name, variant):
    """Builds body + head + rig for a variant. Returns (arm, meshes, joints, head_info)."""
    cfg = {
        "failed_humanoid": dict(arm_len=1.26, leg_len=1.04, thin=0.8, finger=1.65, asym=0.006, skin="skin_corpse",
                                body=dict(w=0.82, emaciated=1.0, muscle=0.2),
                                sdf_face=dict(gaunt=1.2, cheek=1.0, brow=0.8, nose_len=0.6, lip=0.3, mouth_open=1.0,
                                              jaw=0.68, chin=0.5, eye_depth=2.2, jaw_drop=0.045),
                                face=dict(gaunt=0.9, cheek=0.9, brow=0.7, nose_len=0.8, lip=0.2, mouth_open=0.9,
                                          jaw_width=0.65, chin=0.4, eye_depth=1.6)),
        "augmented_subject": dict(arm_len=1.06, leg_len=1.0, thin=0.95, finger=1.1, asym=0.0, skin="skin_corpse",
                                  body=dict(w=1.0, emaciated=0.45, muscle=0.7),
                                  sdf_face=dict(gaunt=0.5, cheek=0.7, brow=0.8, lip=0.6, mouth_open=0.1, jaw=0.85, eye_depth=1.2),
                                  face=dict(gaunt=0.6, cheek=0.7, brow=0.6, lip=0.4, mouth_open=0.2,
                                            jaw_width=0.75, eye_depth=1.2)),
        "chemical_subject": dict(arm_len=1.12, leg_len=0.98, thin=1.0, finger=1.2, asym=0.012, skin="skin_diseased",
                                 body=dict(w=1.08, emaciated=0.2, muscle=0.5),
                                 sdf_face=dict(gaunt=0.3, cheek=0.5, brow=1.0, nose_len=0.6, lip=0.9, mouth_open=0.6,
                                               jaw=0.95, eye_depth=1.4, skull_back=0.9, melt=1.0, jaw_drop=0.015),
                                 face=dict(gaunt=0.4, cheek=0.5, brow=0.9, nose_len=0.5, lip=0.8, mouth_open=0.5,
                                           jaw_width=0.9, eye_depth=1.4, skull_back=0.9)),
    }[variant]
    j = A.skeleton(cfg["arm_len"], cfg["leg_len"], cfg["thin"], cfg["finger"], cfg["asym"], seed=len(variant))
    if variant == "chemical_subject":
        # swollen left forearm and right thigh
        for n, k in (("farm.L", 1.6), ("elbow.L", 1.3), ("thigh.R", 1.25), ("calf.R", 1.2), ("shoulder.L", 1.3)):
            rx, ry = j[n][2]
            j[n][2] = (rx * k, ry * k)
    if variant == "failed_humanoid":
        j["neck_top"][1] = j["neck_top"][1] + Vector((0, -0.02, 0.06))     # unnaturally long neck
        j["neck"][1] = j["neck"][1] + Vector((0, -0.005, 0.02))
    neck_top = j["neck_top"][1]
    hsize = (0.074, 0.094, 0.118)
    hc = neck_top + Vector((0, -0.012, 0.085))
    sh = B.body_shape(j, cfg["body"])
    B.face(sh, hc, cfg["sdf_face"])
    if variant == "chemical_subject":
        # swollen left forearm and right thigh, lumpy growths on the shoulder
        el, wr = Vector(j["elbow.L"][1]), Vector(j["wrist.L"][1])
        B.add(sh, B.E(el.lerp(wr, 0.4), (0.05, 0.045, 0.09), B.frame(wr - el)), 0.04)
        hp, kn = Vector(j["hip.R"][1]), Vector(j["knee.R"][1])
        B.add(sh, B.E(hp.lerp(kn, 0.55) + Vector((0, -0.01, 0)), (0.08, 0.075, 0.14), B.frame(kn - hp)), 0.05)
        shp = Vector(j["shoulder.L"][1])
        for k, off in enumerate(((0.02, -0.02, 0.03), (0.0, 0.03, 0.02), (0.035, 0.0, -0.02))):
            B.add(sh, B.SPH(shp + Vector(off), 0.03 - k * 0.006), 0.03)
    body = S.mesh_from_sdf(name + "_body", sh, (-0.7, -0.3, -0.02), (0.7, 0.3, 1.95), 0.003, cfg["skin"], decimate=0.16)
    meshes = [body]
    eye_mat = {"failed_humanoid": "eye_milky", "augmented_subject": "eye_glow", "chemical_subject": "eye_milky"}[variant]
    for k, p in enumerate(B.eye_positions(hc)):
        if variant == "failed_humanoid":
            # empty sockets: a black void set deep in the skull
            meshes.append(T.sphere(name + "_socket", 0.013, tuple(p + Vector((0, 0.012, 0))), "black_cavity", 16, 10))
        elif variant == "chemical_subject" and k == 1:
            meshes.append(T.sphere(name + "_bulge_eye", 0.017, tuple(p + Vector((0, -0.006, -0.004))), "eye_milky", 16, 10))
        elif variant == "augmented_subject" and k == 1:
            pass      # covered by the face plate
        else:
            meshes.append(T.sphere(name + "_eye", 0.0118, tuple(p), eye_mat, 16, 10))
    if cfg["sdf_face"].get("mouth_open", 0) > 0.3:
        jd = cfg["sdf_face"].get("jaw_drop", 0.0)
        meshes.append(T.sphere(name + "_mouth", 0.017, tuple(hc + Vector((0, -0.075, -0.06 - jd * 0.5))), "black_cavity", 14, 8,
                               scale=(1.2, 0.7, 1.0 + jd * 25)))
    head_top = hc + Vector((0, 0, hsize[2]))
    arm = A.rig(name + "_rig", j, head_top)
    return arm, meshes, j, (hc, hsize)


def implants(name, j, hc, kind, body):
    """Hard-surface implants. Returns [(object, bone)]."""
    out = []
    rnd = random.Random(hash(name) & 0xffff)
    if kind in ("augmented", "chemical"):
        mat_a, mat_b = ("brass", "teal_metal") if kind == "augmented" else ("rust", "copper")
        # spine rods down the back with vertebra clamps
        for k in range(7):
            z = 1.05 + k * 0.075
            yb = Vector(project(body, [(0, 0, z)], direction=(0, -1, 0), lift=0.008)[0]).y
            c = T.box(f"{name}_vert", (0.06, 0.03, 0.035), (0, yb, z), mat_b, bevel=0.006)
            bone = "spine1" if z < 1.17 else "spine2" if z < 1.3 else "chest" if z < 1.42 else "chest_up"
            out.append((c, bone))
        for sx in (-1, 1):
            rod_pts = project(body, [(sx * 0.03, 0, z) for z in (1.02, 1.14, 1.26, 1.38, 1.5)], direction=(0, -1, 0), lift=0.012)
            rod = T.tube(f"{name}_rod", rod_pts, 0.008, mat_a, 8)
            out.append((rod, "chest"))
        # head cage: ring of struts screwed into the skull
        ring = T.torus(f"{name}_halo", 0.122, 0.008, tuple(hc + Vector((0, 0.012, 0.05))), mat_a, rot=(0.15, 0, 0), seg=32, rseg=6)
        out.append((ring, "head"))
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            p = hc + Vector((math.cos(a) * 0.118, 0.012 + math.sin(a) * 0.118, 0.05))
            q = hc + Vector((math.cos(a) * 0.06, 0.012 + math.sin(a) * 0.075, 0.06))
            out.append((T.tube(f"{name}_pin", [tuple(p), tuple(q)], 0.004, "steel", 6), "head"))
        # arm brace on the right forearm, gauge on the chest
        e, w = j["elbow.R"][1], j["wrist.R"][1]
        for k in range(3):
            p = e + (w - e) * (0.25 + k * 0.25)
            out.append((T.torus(f"{name}_brace", 0.038, 0.007, tuple(p), mat_b, rot=(0, (w - e).to_track_quat("Z", "Y").to_euler().y, 0), seg=20, rseg=6), "farm.R"))
        out.append((T.tube(f"{name}_brace_rod", [tuple(e + Vector((0, -0.04, 0))), tuple(w + Vector((0, -0.035, 0)))], 0.006, mat_a, 6), "farm.R"))
        gp = Vector(project(body, [(0.07, 0, 1.38)], lift=0.006)[0])
        g = T.cyl(f"{name}_gauge", 0.035, 0.015, tuple(gp), "gauge", rot=(math.pi / 2, 0, 0), seg=20, uv=False)
        T.planar_uv(g, "Z")
        out.append((g, "chest"))
        out.append((T.torus(f"{name}_gauge_rim", 0.036, 0.005, tuple(gp + Vector((0, -0.007, 0))), mat_a, rot=(math.pi / 2, 0, 0), seg=20, rseg=6), "chest"))
        # cables from the spine to the head and shoulder
        for k in range(4):
            a = (rnd.uniform(-0.03, 0.03), 0.14, 1.3 + k * 0.05)
            b = tuple(hc + Vector((rnd.uniform(-0.05, 0.05), 0.07, rnd.uniform(-0.05, 0.03))))
            out.append((T.tube(f"{name}_cable", A_bez(a, b), 0.006, rnd.choice(["wire_black", "wire_red", "wire_copper"]), 6), "neck"))
    if kind == "chemical":
        # glowing residue blisters
        for k in range(9):
            bone = rnd.choice(["chest", "spine2", "farm.L", "thigh.R", "uarm.L"])
            if bone in ("chest", "spine2"):
                p = Vector(project(body, [(rnd.uniform(-0.1, 0.1), 0, rnd.uniform(1.2, 1.42))], lift=0.0)[0])
            else:
                b0 = {"farm.L": ("elbow.L", "wrist.L"), "thigh.R": ("hip.R", "knee.R"), "uarm.L": ("shoulder.L", "elbow.L")}[bone]
                p = j[b0[0]][1].lerp(j[b0[1]][1], rnd.uniform(0.2, 0.8)) + Vector((0, -0.045, 0))
            out.append((T.sphere(f"{name}_blister", rnd.uniform(0.01, 0.022), tuple(p), "chem_residue", 10, 6, scale=(1, 0.6, 1)), bone))
    return out


def A_bez(a, b):
    a, b = Vector(a), Vector(b)
    return T.bezier_points(tuple(a), tuple(b), ctrl=tuple((a + b) / 2 + Vector((0, 0.06, 0))), steps=8)


# ------------------------------------------------------------------ animations

def anims_shambler(anim, limp=1.0, hunch=22.0, twitchy=1.0):
    """Shared animation set for the failed experiments (visual only)."""

    def posture(t):
        breath = wave(t, 0, 2) * 1.5
        return {
            "spine1": [(X, hunch * 0.35 + breath * 0.3)],
            "spine2": [(X, hunch * 0.35 + breath * 0.5)],
            "chest": [(X, hunch * 0.3 + breath), (Y, 4)],
            "neck": [(X, -hunch * 0.15), (Y, 8)],
            "head": [(X, hunch * 0.1), (Y, 14), (Z, 6)],
            # +Y lowers the left arm, -Y lowers the right; -X bends elbows forward
            "uarm.L": [(Y, 30), (X, 8)], "uarm.R": [(Y, -27), (X, 12)],
            "farm.L": [(X, -16)], "farm.R": [(X, -24)],
            "hand.L": [(X, -8)], "hand.R": [(X, -12)],
            "clav.L": [(Y, 6)], "clav.R": [(Y, -4)],
            "thigh.L": [(X, -8)], "thigh.R": [(X, -6)],
            "shin.L": [(X, 12)], "shin.R": [(X, 10)],
            "foot.L": [(X, -4)], "foot.R": [(X, -4)],
            "_loc": (0, 0, -0.04),
        }

    def add(p, bone, rots):
        p.setdefault(bone, [])
        p[bone] = p[bone] + rots

    def fingers(p, curl, side):
        # palms face the body: left fingers curl about +Y, right about -Y
        s = 1 if side == "L" else -1
        for f in ("index", "middle", "ring", "pinky"):
            add(p, f"{f}1.{side}", [(Y, s * curl)])
            add(p, f"{f}2.{side}", [(Y, s * curl * 1.2)])

    def idle(t):
        p = posture(t)
        sway = wave(t, 0, 1)
        add(p, "spine1", [(Y, sway * 2)])
        add(p, "head", [(Z, wave(t, 0.2, 1) * 6), (Y, wave(t, 0.5, 0.5) * 5)])
        tw = spike(t, 0.37, 0.012) * twitchy
        tw2 = spike(t, 0.71, 0.018) * twitchy
        add(p, "head", [(Y, -35 * tw), (X, 12 * tw2)])
        # slow, too-far head roll: the neck bends further than a living person's can
        roll = max(0.0, wave(t, 0.1, 1)) ** 3
        add(p, "head", [(Y, 48 * roll * twitchy)])
        add(p, "neck", [(Y, 22 * roll * twitchy)])
        add(p, "neck", [(Z, 18 * tw)])
        add(p, "uarm.R", [(X, -20 * tw2)])
        add(p, "farm.R", [(X, -25 * tw2)])
        fingers(p, 15 + 30 * tw2, "R")
        fingers(p, 22 + wave(t, 0, 3) * 6, "L")
        return p

    def walk(t):
        p = posture(t)
        s = wave(t)            # +1: left leg forward
        c = math.cos(t * 2 * math.pi)
        drag = limp
        add(p, "thigh.L", [(X, -26 * s)])
        add(p, "thigh.R", [(X, 22 * s * (1 - 0.4 * drag))])
        add(p, "shin.L", [(X, 28 * max(0.0, c))])
        add(p, "shin.R", [(X, 18 * max(0.0, -c) * (1 - 0.5 * drag))])
        add(p, "foot.R", [(X, 10 * drag)])
        add(p, "pelvis", [(Y, 6 * s), (Z, -5 * s)])
        add(p, "spine2", [(Z, 6 * s), (Y, -4 * s)])
        add(p, "chest", [(Y, 7 * s * drag)])
        add(p, "uarm.L", [(X, 18 * s)])
        add(p, "uarm.R", [(X, -10 * s)])
        add(p, "farm.L", [(X, -10 * max(0.0, s))])
        add(p, "head", [(Y, -8 * s), (X, 4 * abs(c))])
        fingers(p, 18, "L")
        fingers(p, 25, "R")
        p["_loc"] = (0, 0, -0.04 - 0.035 * abs(s) * (1 + drag * 0.5))
        return p

    def react(t):
        p = posture(0)
        k = math.sin(min(1.0, t * 3.2) * math.pi) * math.exp(-t * 2.2) * 2.2
        add(p, "spine2", [(X, -18 * k)])
        add(p, "chest", [(X, -14 * k), (Y, 8 * k)])
        add(p, "head", [(X, -25 * k), (Y, 15 * k)])
        add(p, "uarm.L", [(Y, -25 * k), (X, -30 * k)])
        add(p, "uarm.R", [(Y, 25 * k), (X, -35 * k)])
        add(p, "farm.L", [(X, -40 * k)])
        add(p, "farm.R", [(X, -45 * k)])
        add(p, "thigh.R", [(X, 15 * k)])
        p["_loc"] = (0, 0.06 * k, -0.04)
        fingers(p, 70 * k + 20, "L")
        fingers(p, 70 * k + 20, "R")
        return p

    def twitch(t):
        p = posture(t)
        for k, at in enumerate((0.1, 0.18, 0.33, 0.41, 0.6, 0.64, 0.82)):
            s = spike(t, at, 0.01)
            add(p, "head", [(Y, (40 if k % 2 else -45) * s), (X, 20 * s)])
            add(p, "neck", [(Z, (-20 if k % 2 else 25) * s)])
            add(p, "chest", [(Y, (8 if k % 2 else -10) * s)])
            add(p, "uarm.L" if k % 2 else "uarm.R", [(X, -30 * s)])
        fingers(p, 60, "L")
        fingers(p, 55, "R")
        return p

    anim.action("idle", 120, idle)
    anim.action("walk", 44, walk)
    anim.action("react", 30, react, loop=False)
    anim.action("twitch", 90, twitch)


# ------------------------------------------------------------------ build

def build(variant):
    T.reset()
    arm, meshes, j, (hc, hsize) = humanoid_base(variant, variant)
    extra = []
    if variant in ("failed_humanoid", "augmented_subject"):
        body = meshes[0]
        extra.append(gown(body, variant + "_gown", "fabric_bloody" if variant == "failed_humanoid" else "fabric", top_z=1.56,
                          bottom_z=0.6 if variant == "failed_humanoid" else 0.82, seed=3, joints=j))
    if variant == "failed_humanoid":
        # Y-incision on the chest and a skull scar
        body = meshes[0]
        def line(a, b, n=8):
            return [tuple(Vector(a).lerp(Vector(b), t / n)) for t in range(n + 1)]
        for a, b in (((-0.1, 0, 1.47), (0.0, 0, 1.36)), ((0.1, 0, 1.47), (0.0, 0, 1.36)), ((0.0, 0, 1.36), (0.0, 0, 1.12))):
            extra += scar(project(body, line(a, b)))
        top = hc + Vector((0, 0, 0.2))
        skull = [tuple(top + Vector((x, y, 0))) for x, y in ((-0.05, -0.05), (-0.02, -0.01), (0.01, 0.02), (0.04, 0.05), (0.05, 0.08))]
        extra += scar(project(body, skull, direction=(0, 0, -1)))
    body = meshes[0]
    if variant == "failed_humanoid":
        # blood tears from the empty sockets, long cracked nails
        for p in B.eye_positions(hc):
            pts = project(body, [tuple(p + Vector((dx, 0, -0.012 - k * 0.012))) for k, dx in enumerate((0, 0.002, -0.001, 0.003, 0.0, 0.004, 0.002))], lift=0.0015)
            extra.append(T.tube("blood_tear", pts, 0.0025, "blood_dry", 6))
        mouth_pts = project(body, [tuple(hc + Vector((x, 0, -0.1 - abs(x) * 0.3))) for x in (-0.012, -0.004, 0.004, 0.012)], lift=0.001)
        for mp in mouth_pts:
            extra.append(T.tube("drool", [mp, tuple(Vector(mp) + Vector((0, -0.004, -0.04)))], 0.0022, "blood_dry", 5))
        for side in ("L", "R"):
            for f in ("index", "middle", "ring", "pinky", "thumb"):
                a, b = Vector(j[f"{f}2.{side}"][1]), Vector(j[f"{f}3.{side}"][1])
                d = (b - a).normalized()
                extra.append(T.cyl("nail", 0.005, 0.03, tuple(b + d * 0.012), "black_cavity", r2=0.0006,
                                   rot=tuple(Vector((0, 0, 1)).rotation_difference(d).to_euler()), seg=6))
    rigid = []
    if variant == "augmented_subject":
        rigid = implants(variant, j, hc, "augmented", meshes[0])
        # mouth stapled shut, riveted plate over the left half of the face, bloody piercings
        for k in range(7):
            x = -0.018 + k * 0.006
            p = Vector(project(body, [tuple(hc + Vector((x, 0, -0.056)))], lift=0.001)[0])
            rigid.append((T.box(f"{variant}_staple", (0.002, 0.003, 0.016), tuple(p), "steel"), "head"))
        plate_c = Vector(project(body, [tuple(hc + Vector((0.035, 0, 0.0)))], lift=0.004)[0])
        rigid.append((T.box(f"{variant}_faceplate", (0.06, 0.008, 0.075), tuple(plate_c), "teal_metal", rot=(0, 0, 0.35), bevel=0.004), "head"))
        for dx, dz in ((-0.024, 0.03), (0.024, 0.03), (-0.024, -0.03), (0.024, -0.03)):
            rp = plate_c + Vector((dx, -0.006, dz))
            rigid.append((T.sphere(f"{variant}_rivet", 0.004, tuple(rp), "gold", 8, 5), "head"))
            extra.append(T.sphere("pierce_blood", 0.006, tuple(rp + Vector((0, 0.003, -0.006))), "blood_dry", 8, 5, scale=(1, 0.3, 1.6)))
        rigid.append((T.sphere(f"{variant}_lens", 0.013, tuple(plate_c + Vector((-0.004, -0.007, 0.012))), "eye_glow", 14, 8, scale=(1, 0.5, 1)), "head"))
    if variant == "chemical_subject":
        rigid = implants(variant, j, hc, "chemical", meshes[0])
        extra.append(gown(meshes[0], variant + "_rags", "fabric_bloody", top_z=1.12, bottom_z=0.74, seed=9, joints=j))
        # glowing veins crawling over the body
        rnd = random.Random(77)
        for k in range(14):
            bone = rnd.choice(["farm.L", "uarm.L", "thigh.R", "chest", "neck", "uarm.R"])
            pair = {"farm.L": ("elbow.L", "wrist.L"), "uarm.L": ("shoulder.L", "elbow.L"), "uarm.R": ("shoulder.R", "elbow.R"),
                    "thigh.R": ("hip.R", "knee.R"), "chest": ("chest", "chest_up"), "neck": ("neck", "neck_top")}[bone]
            a, b = Vector(j[pair[0]][1]), Vector(j[pair[1]][1])
            t0 = rnd.uniform(0, 0.6)
            raw = [a.lerp(b, t0 + i * 0.07) + Vector((rnd.gauss(0, 0.012), 0, rnd.gauss(0, 0.012))) for i in range(6)]
            pts = project(body, [tuple(r) for r in raw], lift=0.0012)
            extra.append(T.tube("vein", pts, 0.0028, "chem_residue", 5))
    neck_z = j["neck_top"][1].z
    head_rule = [(lambda p: p.z > neck_z + 0.02 and abs(p.x) < 0.16, "head")]
    cloth = [m for m in extra if "_gown" in m.name or "_rags" in m.name]
    no_arms = lambda n: not any(n.startswith(k) for k in ("uarm", "farm", "hand", "index", "middle", "ring", "pinky", "thumb"))
    for m in meshes + extra:
        if m in cloth:
            A.skin_to(m, arm, bone_filter=no_arms, parent=False, falloff=2.5)
        else:
            A.skin_to(m, arm, overrides=head_rule, parent=False)
    skin = T.join([m for m in meshes + extra if m.type == "MESH"], variant + "_mesh")
    skin.parent = arm
    skin.matrix_parent_inverse = arm.matrix_world.inverted()
    skin.modifiers.new("armature", "ARMATURE").object = arm
    for ob, bone in rigid:
        A.attach_to_bone(ob, arm, bone)
    anim = A.Animator(arm)
    anims_shambler(anim, limp={"failed_humanoid": 1.0, "augmented_subject": 0.3, "chemical_subject": 0.7}[variant],
                   hunch={"failed_humanoid": 40.0, "augmented_subject": 16.0, "chemical_subject": 28.0}[variant],
                   twitchy={"failed_humanoid": 1.0, "augmented_subject": 1.4, "chemical_subject": 0.6}[variant])
    objs = [arm, skin] + [o for o, _ in rigid]
    T.save_blend(f"source/blender/characters/{variant}.blend")
    T.export_glb(f"assets/models/characters/{variant}.glb", objs, animations=True)
    return arm, skin


VARIANTS = ["failed_humanoid", "augmented_subject", "chemical_subject"]

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else VARIANTS
    for v in argv:
        build(v)
