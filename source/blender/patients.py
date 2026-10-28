"""Tall Patients: TIMBUK's experiment-subject enemies (graphics v3).

Realistic, unsettling and clearly *experimented on*, not gory: unnaturally
tall adults in hospital gowns with shaved heads, clean surgical incisions,
surgical-marker lines, ID wristbands and medical hardware.

  tall_patient_a  EEG electrodes on the scalp, leads bundled to a back connector
  tall_patient_b  cervical traction halo + shoulder vest, IV port in the arm
  tall_patient_c  spinal brace with straps, measurement grid on the face, eyes wide

Animations (visual only, in place): idle, walk, react, head_snap.
Run: blender -b --factory-startup --python source/blender/patients.py [-- name ...]
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import tlib as T  # noqa: E402
import anatomy as A  # noqa: E402
import bodysdf as B  # noqa: E402
import realhead as H  # noqa: E402
import sdf as S  # noqa: E402
from anatomy import X, Y, Z, wave, spike  # noqa: E402

VARIANTS = ["tall_patient_a", "tall_patient_b", "tall_patient_c"]


# ------------------------------------------------------------------ surface helpers

def sdf_grad(shape, p, eps=0.001):
    q = np.array([p, p + (eps, 0, 0), p + (0, eps, 0), p + (0, 0, eps)], np.float32)
    d = shape(q)
    g = Vector(((d[1] - d[0]) / eps, (d[2] - d[0]) / eps, (d[3] - d[0]) / eps))
    return float(d[0]), (g.normalized() if g.length > 1e-9 else Vector((0, 0, 1)))


def clear_path(shape, pts, clearance, iters=6):
    """Push every point of a cable path out of the body so it never clips.

    Each point is moved along the SDF gradient until it is at least
    `clearance` outside the surface; the path is then lightly smoothed and
    checked again.
    """
    pts = [Vector(p) for p in pts]
    for _ in range(iters):
        for i, p in enumerate(pts):
            d, n = sdf_grad(shape, np.array(tuple(p), np.float32))
            if d < clearance:
                pts[i] = p + n * (clearance - d)
        for i in range(1, len(pts) - 1):      # smooth interior points
            pts[i] = pts[i] * 0.5 + (pts[i - 1] + pts[i + 1]) * 0.25
    for i, p in enumerate(pts):              # final hard guarantee
        d, n = sdf_grad(shape, np.array(tuple(p), np.float32))
        if d < clearance:
            pts[i] = p + n * (clearance - d)
    return [tuple(p) for p in pts]


def ray_to_surface(shape, origin, direction, lift=0.0, max_t=0.6):
    """Sphere-trace from `origin` along `direction` to the surface (+lift).
    Returns None if the ray misses the body."""
    d = Vector(direction).normalized()
    t = 0.0
    while t < max_t:
        p = Vector(origin) + d * t
        dist = sdf_grad(shape, np.array(tuple(p), np.float32))[0]
        if dist - lift < 0.0003:
            return p
        t += max(dist - lift, 0.0004)
    return None


def on_surface(shape, p, lift=0.0):
    """Snap a point onto the SDF surface (+lift along the normal).

    Steps are clamped so the search can never run away; if it fails to
    converge the original point is returned (and logged)."""
    start = Vector(p)
    p = Vector(p)
    for i in range(160):
        d, n = sdf_grad(shape, np.array(tuple(p), np.float32))
        lim = 0.03 if i < 20 else 0.008       # big steps first, then careful ones (thin limbs)
        step = max(-lim, min(lim, (d - lift) * (1.0 if i < 60 else 0.5)))
        p = p - n * step
        if abs(d - lift) < 0.0003:
            return p
    d, _ = sdf_grad(shape, np.array(tuple(p), np.float32))
    if abs(d - lift) > 0.003 or (p - start).length > 0.5:
        # fall back to sphere tracing straight toward the body
        d0, n0 = sdf_grad(shape, np.array(tuple(start), np.float32))
        hit = ray_to_surface(shape, start, -n0 if d0 > lift else n0, lift)
        if hit is not None:
            return hit
        print("on_surface: no convergence near", tuple(round(x, 3) for x in start))
        return start
    return p


def segment_clear(shape, a, b, clearance, samples=24):
    """True if the straight segment a-b stays `clearance` outside the body."""
    for k in range(samples + 1):
        q = Vector(a).lerp(Vector(b), k / samples)
        if sdf_grad(shape, np.array(tuple(q), np.float32))[0] < clearance:
            return False
    return True


def offset_shape(sh, off):
    """The body shape grown outward by `off` metres (for garments that must
    never be smaller than the body). Each primitive is offset; cuts shrink."""
    out = S.Shape()
    for kind, fn, k, bounds in sh.ops:
        if kind == "disp":
            continue
        b = None if bounds is None else (bounds[0] - off, bounds[1] + off)
        if kind == "add":
            out.ops.append(("add", (lambda f: (lambda p: f(p) - off))(fn), k, b))
        else:
            out.ops.append(("cut", (lambda f: (lambda p: f(p) + off))(fn), k, b))
    return out


def fit_ring(shape, centre, axis, clearance=0.003, samples=16):
    """Radius of a ring around `axis` through `centre` that clears the surface."""
    axis = Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(ref).normalized()
    v = axis.cross(u)
    r_max = 0.0
    for k in range(samples):
        a = k / samples * 2 * math.pi
        d = u * math.cos(a) + v * math.sin(a)
        q = ray_to_surface(shape, Vector(centre) + d * 0.15, -d, 0.0, 0.16)
        if q is not None:
            r_max = max(r_max, (q - Vector(centre)).dot(d))
    return r_max + clearance


def curve(pts, steps=24):
    """Catmull-Rom through control points."""
    pts = [Vector(p) for p in pts]
    out = []
    for i in range(len(pts) - 1):
        p0 = pts[i - 1] if i > 0 else pts[i]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[i + 2] if i + 2 < len(pts) else pts[i + 1]
        n = max(2, steps // (len(pts) - 1))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1])
    return out


# ------------------------------------------------------------------ gown with folds

def gown(j, name, body_shape, bottom_z=0.62, seed=0, material="gown_blue", open_back=True):
    J = lambda n: Vector(j[n][1])
    sh = offset_shape(body_shape, 0.013)       # never closer than 13 mm to the skin
    pel, ch, cu = J("pelvis"), J("chest"), J("chest_up")
    B.add(sh, B.E(pel + Vector((0, 0.012, -0.26)), (0.165, 0.13, 0.24)), 0.1)    # one skirt volume over both legs
    B.add(sh, B.RC(pel + Vector((0, 0.01, 0)), cu, 0.13, 0.136), 0.05)
    B.add(sh, B.E(ch + Vector((0, 0.0, 0.03)), (0.146, 0.11, 0.17)), 0.06)
    B.add(sh, B.E(cu + Vector((0, 0.012, 0.0)), (0.162, 0.1, 0.08)), 0.06)
    B.add(sh, B.E(pel + Vector((0, 0.01, -0.02)), (0.165, 0.12, 0.11)), 0.1)
    for side in ("L", "R"):
        hip, kn = J(f"hip.{side}"), J(f"knee.{side}")
        B.add(sh, B.RC(hip, hip.lerp(kn, 0.9), 0.095, 0.09), 0.12)
        B.add(sh, B.RC(cu + Vector((0, 0.01, 0.04)), J(f"shoulder.{side}") + Vector((0, 0, 0.03)), 0.055, 0.05), 0.05)
        B.add(sh, B.RC(J(f"shoulder.{side}"), J(f"shoulder.{side}").lerp(J(f"elbow.{side}"), 0.35), 0.05, 0.045), 0.03)
    # hanging folds: vertical ridges that grow below the chest, plus slack wrinkles
    chest_z = ch.z

    def folds(p):
        ang = np.arctan2(p[:, 1], p[:, 0])
        hang = np.clip((chest_z - p[:, 2]) / 0.5, 0.0, 1.0)
        n1 = S.value_noise3(p * np.array([1, 1, 0.15], np.float32), 9.0, seed=seed)
        return -(0.006 * np.sin(ang * 13 + n1 * 3.0) * hang + 0.0025 * S.value_noise3(p, 30.0, seed + 1))
    sh.displace(folds)
    ob = S.mesh_from_sdf(name, sh, (-0.75, -0.34, 0.3), (0.75, 0.34, 2.3), 0.0045, material, decimate=0.3, smooth_iter=1)
    arm_caps = [(J(f"shoulder.{sd}").lerp(J(f"elbow.{sd}"), 0.33), J(f"hand.{sd}") + (J(f"hand.{sd}") - J(f"wrist.{sd}")) * 3) for sd in ("L", "R")]
    neck_a, neck_b = J("neck"), J("neck_top")
    rnd = random.Random(seed)

    def near(p, a, b, r):
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
        return (p - (a + ab * t)).length < r

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    kill = []
    for f in bm.faces:
        c = ob.matrix_world @ f.calc_center_median()
        ang = math.atan2(c.y, c.x)
        hem = bottom_z + 0.02 * math.sin(ang * 3 + seed)       # clean hem, slight sway
        # round neck hole (scooped lower at the front); shoulders stay covered
        r_neck = math.hypot(c.x - neck_a.x, (c.y - neck_a.y) * 1.25)
        neck_hole = c.z > neck_a.z - (0.045 if c.y < neck_a.y else 0.015) and r_neck < 0.085
        if c.z < hem or neck_hole or c.z > neck_a.z + 0.03 or any(near(c, a, b, 0.075) for a, b in arm_caps):
            kill.append(f)
        elif open_back and c.y > 0.05 and abs(c.x) < 0.035 and chest_z - 0.25 < c.z < chest_z + 0.15:
            kill.append(f)                                    # open back of the gown
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    sol = ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = 1.0
    T.apply_all([ob])
    return ob


# ------------------------------------------------------------------ experiment details

def marker_line(shape, pts, dash=True, r=0.0011):
    """Surgical-marker line (dashed) drawn on the skin."""
    pts = [on_surface(shape, p, 0.0008) for p in pts]
    path = curve(pts, 30)
    out = []
    if not dash:
        return [T.tube("marker", [tuple(p) for p in path], r, "marker_ink", 4)]
    for i in range(0, len(path) - 1, 2):
        out.append(T.tube("marker_dash", [tuple(path[i]), tuple(path[i + 1])], r, "marker_ink", 4))
    return out


def staple_line(shape, pts, n=9):
    """Healed incision with surgical staples."""
    pts = [on_surface(shape, p, 0.0006) for p in pts]
    path = curve(pts, 30)
    out = [T.tube("incision", [tuple(p) for p in path], 0.0012, "lip", 5)]
    for k in range(n):
        i = int((k + 0.5) / n * (len(path) - 1))
        a, b = path[max(0, i - 1)], path[min(len(path) - 1, i + 1)]
        d = (b - a).normalized()
        _, nrm = sdf_grad(shape, np.array(tuple(path[i]), np.float32))
        side = d.cross(nrm).normalized() * 0.004
        p = path[i] + nrm * 0.0012
        out.append(T.tube("staple", [tuple(p - side - nrm * 0.0012), tuple(p - side), tuple(p + side), tuple(p + side - nrm * 0.0012)], 0.0006, "steel", 4))
    return out


def id_band(shape, j, side="L"):
    w = Vector(j[f"wrist.{side}"][1])
    e = Vector(j[f"elbow.{side}"][1])
    d = (w - e).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_euler()
    c = w - d * 0.035
    r = fit_ring(shape, c, d, 0.004)
    band = T.cyl("id_band", r, 0.022, tuple(c), "id_band", rot=tuple(rot), seg=28, cap=False)
    tag = T.box("id_tag", (0.025, 0.004, 0.018), tuple(c + Vector((0, -(r + 0.003), 0))), "paper", rot=tuple(rot))
    return [band, tag], f"farm.{side}"


def eeg_rig(shape, hc, j, parts, seed=3):
    """Electrodes glued across the scalp; leads run over the skull into one
    neat loom down the back of the neck to a connector box on the upper back."""
    rnd = random.Random(seed)
    sites = [(0.0, -0.05, 0.1), (0.035, -0.04, 0.09), (-0.035, -0.04, 0.09), (0.055, 0.0, 0.085),
             (-0.055, 0.0, 0.085), (0.0, 0.0, 0.125), (0.03, 0.04, 0.11), (-0.03, 0.04, 0.11),
             (0.06, 0.03, 0.05), (-0.06, 0.03, 0.05)]
    cu = Vector(j["chest_up"][1])
    box_c = on_surface(shape, cu + Vector((0, 0.15, 0.02)), 0.02)
    parts.append((T.box("eeg_box", (0.07, 0.03, 0.05), tuple(box_c), "plastic", bevel=0.006), "chest_up"))
    parts.append((T.box("eeg_led", (0.008, 0.004, 0.004), tuple(box_c + Vector((0.02, 0.016, 0.015))), "light_green"), "chest_up"))
    neck_back = on_surface(shape, Vector(j["neck"][1]) + Vector((0, 0.08, 0.03)), 0.0)
    for k, (x, y, z) in enumerate(sites):
        p = on_surface(shape, Vector(hc) + Vector((x, y, z)) + Vector((0, 0, 0.05)), 0.0)
        _, n = sdf_grad(shape, np.array(tuple(p), np.float32))
        rot = Vector((0, 0, 1)).rotation_difference(n).to_euler()
        parts.append((T.cyl("electrode", 0.0065, 0.0025, tuple(p + n * 0.0012), "electrode", rot=tuple(rot), seg=14), "head"))
        parts.append((T.cyl("electrode_gel", 0.008, 0.0012, tuple(p + n * 0.0004), "tape", rot=tuple(rot), seg=14), "INSET:head"))
        # lead: lift off the electrode, run back over the skull, join the loom at the neck
        offset = Vector(((k - 4.5) * 0.0028, 0, 0))     # each lead keeps its own lane
        ctrl = [p + n * 0.004, p + n * 0.012 + Vector((0, 0.03, 0)),
                Vector(hc) + Vector((x * 0.6, 0.1, 0.02)) + offset,
                neck_back + Vector((0, 0.025, 0)) + offset * 0.6,
                box_c + Vector((0, 0.0, 0.03)) + offset * 0.4]
        path = clear_path(shape, [tuple(q) for q in curve(ctrl, 26)], 0.005)
        parts.append((T.tube("eeg_lead", path, 0.0012, rnd.choice(["wire_black", "wire_red", "wire_black"]), 5), "SKIN"))
    # loom sleeve where the leads gather
    sleeve = clear_path(shape, [tuple(neck_back + Vector((0, 0.03, 0.02))), tuple(box_c + Vector((0, 0.0, 0.035)))], 0.013)
    parts.append((T.tube("loom", sleeve, 0.009, "rubber", 10), "SKIN"))


def traction_halo(shape, hc, j, parts):
    """Cervical halo: ring pinned into the skull, four rods down to a vest."""
    c = Vector(hc) + Vector((0, 0.005, 0.045))
    # halos are oval: longer front-to-back than side-to-side, clear of the brow
    c = c + Vector((0, -0.006, 0))
    ring = T.torus("halo", 0.115, 0.0075, tuple(c), "steel", seg=48, rseg=8)
    ring.scale = (1.0, 1.26, 1.0)
    T.apply_all([ring])
    bpy.context.view_layer.objects.active = ring
    with bpy.context.temp_override(active_object=ring, selected_editable_objects=[ring], selected_objects=[ring]):
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    parts.append((ring, "head"))
    pins = []
    for a in (math.radians(55), math.radians(125), math.radians(235), math.radians(305)):
        rim = c + Vector((math.cos(a) * 0.115, math.sin(a) * 0.115 * 1.26, 0))
        rim = rim + (rim - c).normalized() * 0.004
        skin = on_surface(shape, c + Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0)), 0.0)
        parts.append((T.tube("halo_pin", [tuple(rim), tuple(skin)], 0.0028, "steel", 6), "INSET:head"))
        parts.append((T.sphere("pin_cap", 0.006, tuple(rim), "brass", 10, 6), "head"))
        parts.append((T.cyl("pin_gauze", 0.007, 0.004, tuple(skin), "gauze", seg=12), "INSET:head"))
        pins.append(rim)
    cu = Vector(j["chest_up"][1])
    vest = offset_shape(shape, 0.03)          # sits over the gown (gown is 13 mm out)
    vest_ob = S.mesh_from_sdf("halo_vest", vest, tuple(cu - Vector((0.3, 0.3, 0.25))), tuple(cu + Vector((0.3, 0.3, 0.15))), 0.006, "plastic", decimate=0.3)
    bm = bmesh.new()
    bm.from_mesh(vest_ob.data)
    kill = [f for f in bm.faces if not (cu.z - 0.2 < (vest_ob.matrix_world @ f.calc_center_median()).z < cu.z + 0.04)
            or abs((vest_ob.matrix_world @ f.calc_center_median()).x) > 0.16]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(vest_ob.data)
    bm.free()
    sol = vest_ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.008
    sol.offset = 1.0
    T.apply_all([vest_ob])
    parts.append((vest_ob, "SKIN"))
    for rim, sx, sy in zip(pins, (1, -1, -1, 1), (1, 1, -1, -1)):
        top = rim + Vector((0, 0, -0.008))
        foot = cu + Vector((sx * 0.14, sy * 0.1, 0.06))
        for _ in range(20):                   # walk the foot outward until the rod clears the body
            if segment_clear(shape, top, foot, 0.026):
                break
            foot = foot + Vector((sx * 0.01, sy * 0.008, 0))
        parts.append((T.tube("halo_rod", [tuple(top), tuple(foot)], 0.006, "steel", 8), "chest_up"))
        parts.append((T.box("rod_mount", (0.03, 0.03, 0.02), tuple(foot), "plastic", bevel=0.004), "chest_up"))


def iv_port(shape, j, parts, side="R"):
    e, w = Vector(j[f"elbow.{side}"][1]), Vector(j[f"wrist.{side}"][1])
    p = on_surface(shape, e.lerp(w, 0.55) + Vector((0, -0.05, 0)), 0.001)
    _, n = sdf_grad(shape, np.array(tuple(p), np.float32))
    rot = Vector((0, 0, 1)).rotation_difference(n).to_euler()
    parts.append((T.box("iv_tape", (0.02, 0.016, 0.0015), tuple(p + n * 0.0012), "tape", rot=tuple(rot)), "SKIN"))
    parts.append((T.cyl("iv_hub", 0.004, 0.018, tuple(p + n * 0.006), "plastic", rot=tuple(rot), seg=10), "SKIN"))
    tube_pts = clear_path(shape, [tuple(p + n * 0.008), tuple(p + n * 0.04 + Vector((0, 0, -0.05))),
                                  tuple(w + Vector((0, -0.07, -0.25))), tuple(w + Vector((0.02, -0.05, -0.4)))], 0.006)
    parts.append((T.tube("iv_line", [tuple(q) for q in curve(tube_pts, 16)], 0.0018, "glass_tank", 6), "SKIN"))


def spinal_brace(shape, j, parts):
    """Rigid back brace worn over the gown, with buckled straps."""
    for k, bone in enumerate(("spine2", "spine2", "chest", "chest_up")):
        zc = Vector(j[bone][1]).z + (0.04 if k else -0.03)
        back = on_surface(shape, Vector((0, 0.2, zc)), 0.056 + (0.012 if bone == "chest_up" else 0.0))  # outside the gown folds
        parts.append((T.box("brace_plate", (0.085, 0.012, 0.09), tuple(back), "plastic", bevel=0.008), bone))
        if k in (1, 3):
            for side in (-1, 1):
                a = on_surface(shape, Vector((side * 0.13, 0.05, zc)), 0.026)
                fr = on_surface(shape, Vector((side * 0.07, -0.2, zc)), 0.026)
                parts.append((T.tube("brace_strap", clear_path(shape, [tuple(back + Vector((side * 0.04, 0, 0))), tuple(a), tuple(fr)], 0.026), 0.004, "rubber", 6), "SKIN"))
            parts.append((T.box("buckle", (0.025, 0.006, 0.02), tuple(on_surface(shape, Vector((0.0, -0.2, zc)), 0.013)), "steel"), bone))
    rod = [tuple(on_surface(shape, Vector((0, 0.2, Vector(j[b][1]).z + 0.04)), 0.068)) for b in ("spine2", "chest", "chest_up")]
    parts.append((T.tube("brace_rod", rod, 0.006, "steel", 8), "SKIN"))


# ------------------------------------------------------------------ animations

def patient_anims(anim, tilt):
    def base(t):
        b = wave(t, 0, 1) * 0.6
        return {
            "spine1": [(X, 3 + b * 0.3)], "spine2": [(X, 2 + b * 0.4)], "chest": [(X, -2 + b)],
            "neck": [(X, 10), (Y, tilt * 0.35)], "head": [(Y, tilt * 0.65), (X, 6)],
            "uarm.L": [(Y, 14), (X, 6)], "uarm.R": [(Y, -14), (X, 6)],     # arms hang clear of the gown sides
            "farm.L": [(X, -6)], "farm.R": [(X, -6)],
            "thigh.L": [(X, -1)], "thigh.R": [(X, -1)], "_loc": (0, 0, 0.0),
        }

    def add(p, b, r):
        p[b] = p.get(b, []) + r

    def fingers(p, curl):
        for side, s in (("L", 1), ("R", -1)):
            for f in ("index", "middle", "ring", "pinky"):
                add(p, f"{f}1.{side}", [(Y, s * curl)])
                add(p, f"{f}2.{side}", [(Y, s * curl * 1.1)])

    def idle(t):
        # almost perfectly still; the stillness is the point. Tiny fast finger and head tremors.
        p = base(t)
        tw = spike(t, 0.53, 0.006)
        add(p, "head", [(Y, 9 * tw), (Z, 3 * wave(t, 0.2, 1))])
        fingers(p, 10 + 3 * wave(t, 0, 7) * wave(t, 0.3, 2))
        return p

    def walk(t):
        # long, stiff strides; upper body stays rigid like it's being carried
        p = base(t)
        s = wave(t)
        c = math.cos(t * 2 * math.pi)
        add(p, "thigh.L", [(X, -17 * s)])
        add(p, "thigh.R", [(X, 17 * s)])
        add(p, "shin.L", [(X, 12 * max(0.0, c))])
        add(p, "shin.R", [(X, 12 * max(0.0, -c))])
        add(p, "pelvis", [(Z, -3 * s)])
        p["_loc"] = (0, 0, -0.01 - 0.012 * abs(s))
        fingers(p, 12)
        return p

    def react(t):
        p = base(0)
        k = math.sin(min(1.0, t * 3.0) * math.pi) * math.exp(-t * 2.5) * 2.0
        add(p, "chest", [(X, -10 * k)])
        add(p, "head", [(Y, -tilt * 0.8 * k), (X, -12 * k)])
        add(p, "uarm.L", [(X, -18 * k)])
        add(p, "uarm.R", [(X, -18 * k)])
        fingers(p, 10 + 50 * k)
        return p

    def head_snap(t):
        # head snaps upright to stare, holds, then slowly sinks back to the tilt
        p = base(t)
        up = 1.0 if 0.1 < t < 0.6 else max(0.0, 1 - (t - 0.6) / 0.35) if t >= 0.6 else t / 0.1
        add(p, "head", [(Y, -tilt * 0.65 * up)])
        add(p, "neck", [(Y, -tilt * 0.35 * up)])
        fingers(p, 10 + 25 * up)
        return p

    anim.action("idle", 150, idle)
    anim.action("walk", 56, walk)
    anim.action("react", 30, react, loop=False)
    anim.action("head_snap", 90, head_snap)


# ------------------------------------------------------------------ build

CFG = {
    "tall_patient_a": dict(seed=11, tilt=-38, iris="eye_grey", eye_open=0.75, extras="eeg"),
    "tall_patient_b": dict(seed=12, tilt=0, iris="eye_brown", eye_open=0.6, extras="halo"),
    "tall_patient_c": dict(seed=13, tilt=-55, iris="eye_grey", eye_open=1.0, extras="brace"),
}


def build(name):
    cfg = CFG[name]
    T.reset()
    rnd = random.Random(cfg["seed"])
    j = A.skeleton(arm_len=1.17, leg_len=1.16, thin=0.85, finger_len=1.3, asym=0.003, seed=cfg["seed"])
    j["neck_top"][1] = j["neck_top"][1] + Vector((0, -0.006, 0.035))          # long neck
    hc = Vector(j["neck_top"][1]) + Vector((0, -0.012, 0.09))
    sh = B.body_shape(j, {"w": 0.88, "emaciated": 0.4, "muscle": 0.3})
    eyes = H.head(sh, hc, {"gaunt": 0.45, "cheekbone": 0.8, "brow": 0.55, "eye_open": cfg["eye_open"],
                           "jaw": 0.82, "lips": 0.45, "nose_len": 1.05})
    body = S.mesh_from_sdf(name + "_body", sh, (-0.72, -0.3, -0.02), (0.72, 0.3, 2.3), 0.0026, "skin_patient", decimate=0.18)
    parts, deform = [], []
    deform += H.eyeballs(eyes, name, cfg["iris"])
    # clinical marks: dashed marker lines on scalp + forearms, a stapled incision
    deform += marker_line(sh, [hc + Vector((x, 0.02 - abs(x) * 0.3, 0.115 - x * x * 3)) for x in np.linspace(-0.06, 0.06, 7)])
    for side in ("L", "R"):
        e, w = Vector(j[f"elbow.{side}"][1]), Vector(j[f"wrist.{side}"][1])
        deform += marker_line(sh, [e.lerp(w, t) + Vector((0, -0.04, 0)) for t in np.linspace(0.15, 0.8, 5)])
    deform += staple_line(sh, [hc + Vector((0.055, 0.03, 0.06)), hc + Vector((0.065, 0.0, 0.03)), hc + Vector((0.068, -0.03, 0.0))])
    if cfg["extras"] == "brace":   # measurement grid on the face
        for z in (0.0, -0.035):
            deform += marker_line(sh, [hc + Vector((x, -0.06 + abs(x) * 0.4, z)) for x in np.linspace(-0.05, 0.05, 6)])
        for x in (-0.03, 0.03):
            deform += marker_line(sh, [hc + Vector((x, -0.07, z)) for z in np.linspace(0.04, -0.06, 5)])
    g = gown(j, name + "_gown", sh, bottom_z=0.72, seed=cfg["seed"], open_back=cfg["extras"] != "brace")
    band, band_bone = id_band(sh, j, "L")
    for b in band:
        parts.append((b, band_bone))
    if cfg["extras"] == "eeg":
        eeg_rig(sh, hc, j, parts, cfg["seed"])
    elif cfg["extras"] == "halo":
        traction_halo(sh, hc, j, parts)
        iv_port(sh, j, parts, "R")
    else:
        spinal_brace(sh, j, parts)
        iv_port(sh, j, parts, "L")
    head_top = hc + Vector((0, 0.01, 0.13))
    arm = A.rig(name + "_rig", j, head_top)
    neck_z = Vector(j["neck_top"][1]).z
    head_rule = [(lambda p: p.z > neck_z + 0.02 and abs(p.x) < 0.16, "head")]
    no_arms = lambda n: not any(n.startswith(k) for k in ("farm", "hand", "index", "middle", "ring", "pinky", "thumb"))
    A.skin_to(body, arm, overrides=head_rule, parent=False)
    A.copy_weights(body, g)
    soft = [ob for ob, bone in parts if bone == "SKIN"]
    for m in soft + deform:
        m.vertex_groups.clear()
        A.copy_weights(body, m)
    flesh = T.join([body, g] + deform + soft, name + "_mesh")
    flesh.parent = arm
    flesh.matrix_parent_inverse = arm.matrix_world.inverted()
    flesh.modifiers.new("armature", "ARMATURE").object = arm
    by_bone = {}
    for ob, bone in parts:
        by_bone.setdefault(bone, []).append(ob)
    rigid = []
    for bone, obs in by_bone.items():
        if bone == "SKIN":
            continue
        inset = bone.startswith("INSET:")
        bone = bone.split(":")[-1]
        joined = T.join(obs, f"{name}_{bone.replace('.', '_')}_{'inset' if inset else 'parts'}")
        T.shade_smooth(joined, 35)
        A.attach_to_bone(joined, arm, bone)
        rigid.append(joined)
    anim = A.Animator(arm)
    patient_anims(anim, cfg["tilt"])
    T.save_blend(f"source/blender/characters/{name}.blend")
    T.export_glb(f"assets/models/characters/{name}.glb", [arm, flesh] + rigid, animations=True)


if __name__ == "__main__":
    for v in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else VARIANTS):
        build(v)
