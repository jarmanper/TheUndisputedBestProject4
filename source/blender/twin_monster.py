"""The Twin: TIMBUK's signature monster (visual model, rig and animations).

Built from the art brief (reference image pending; see README notes):
  - enormous antique porcelain clock face fused into the upper skull
  - large mechanical eye with a red-orange glowing pupil in the centre of the face
  - two symmetric yellowed side gauges with needles and small lit elements
  - human lower face: narrow nose, pale skin, cheeks, small closed lips,
    thin jaw, delicate chin, expressionless
  - dense crown of tangled wires, filaments and small components
  - slender humanoid body in torn institutional clothing, subtle implants

Extra bones drive the clock hands, eye, gauge needles and wire bundles.
Animations: idle, head_tilt, eye_scan, clock_spin, twitch, wire_vibrate,
walk_slow, posture_shift, reveal.

Run:  blender -b --factory-startup --python source/blender/twin_monster.py
"""
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(__file__))
import tlib as T  # noqa: E402
import anatomy as A  # noqa: E402
import bodysdf as B  # noqa: E402
import sdf as S  # noqa: E402
from anatomy import X, Y, Z, wave, spike  # noqa: E402
from creatures import project  # noqa: E402

NAME = "twin_monster"
HEAD_SCALE = 1.25        # the reference head is oversized relative to the body
RND = random.Random(1979)


# =====================================================================
# Head layout (all relative to the lower-face centre F)
# =====================================================================

class Head:
    """Head layout in metres, relative to the chin point (0, 0, zc).

    Proportions are measured from assets/references/twin_monster_reference.png:
    the yellowed porcelain dome *is* the clock, the big dark eye sits on the
    nose bridge, the two gauge 'eyes' sit in the eye sockets, mechanical
    clamps replace the ears.
    """
    RX, RY, RZ, CZ, CY = 0.118, 0.125, 0.125, 0.19, 0.01      # cranium ellipsoid (matches texgen TWIN_HEAD)

    def __init__(self, chin):
        self.o = Vector(chin)
        self.eye_c = self.P(0, -0.108, 0.146)
        self.eye_r = 0.043
        self.gauge_c = [self.P(s * 0.097, -0.076, 0.152) for s in (-1, 1)]
        self.gauge_r = 0.031
        self.clamp_c = [self.P(s * 0.121, 0.005, 0.15) for s in (-1, 1)]
        self.top = self.P(0, self.CY, self.CZ + self.RZ)
        x, y, z = self.dome(0.0, 0.215)
        self.pivot = self.P(x, y, z)
        self.pivot_n = self.dome_normal(0.0, 0.215)

    def P(self, x, y, z):
        return self.o + Vector((x, y, z))

    def dome(self, x, z):
        k = 1 - (x / self.RX) ** 2 - ((z - self.CZ) / self.RZ) ** 2
        return x, -self.RY * math.sqrt(max(0.0, k)) + self.CY, z

    def dome_normal(self, x, z):
        x, y, z = self.dome(x, z)
        n = Vector((x / self.RX ** 2, (y - self.CY) / self.RY ** 2, (z - self.CZ) / self.RZ ** 2))
        return n.normalized()

    def on_dome(self, x, z, lift=0.0):
        p = Vector(self.dome(x, z))
        return self.o + p + self.dome_normal(x, z) * lift


def disc(name, c, r, depth, mat, rot, seg=64, planar=False, r2=None):
    ob = T.cyl(name, r, depth, tuple(c), mat, rot=tuple(rot), seg=seg, uv=not planar, r2=r2)
    if planar:
        T.planar_uv(ob, "Z")
    return ob


def ring(name, c, R, r, mat, rot, seg=96, rseg=12):
    return T.torus(name, R, r, tuple(c), mat, rot=tuple(rot), seg=seg, rseg=rseg)


def facing(n):
    """Euler that turns a +Z-facing disc to face direction n."""
    return Vector((0, 0, 1)).rotation_difference(Vector(n).normalized()).to_euler()


# =====================================================================
# The head: one sculpted porcelain-skin surface (SDF) with a painted dial
# =====================================================================

def head_mesh(h, neck_bottom):
    sh = S.Shape()
    P = h.P
    B.add(sh, B.E(P(0, h.CY, h.CZ), (h.RX, h.RY, h.RZ)), 0.0)                    # cranium / clock dome
    B.add(sh, B.E(P(0, -0.005, 0.115), (0.104, 0.1, 0.075)), 0.05)              # mid face
    B.add(sh, B.E(P(0, -0.03, 0.05), (0.062, 0.072, 0.05)), 0.05)               # jaw
    B.add(sh, B.SPH(P(0, -0.082, 0.014), 0.021), 0.025)                         # delicate chin
    for s in (-1, 1):
        B.add(sh, B.E(P(s * 0.058, -0.079, 0.085), (0.034, 0.026, 0.03)), 0.03)   # round cheeks
        B.add(sh, B.E(P(s * 0.082, -0.09, 0.111), (0.028, 0.012, 0.012)), 0.015)  # sagging lower lids
        B.add(sh, B.SPH(P(s * 0.017, -0.114, 0.075), 0.012), 0.008)               # nostril wings
        B.cut(sh, B.SPH(P(s * 0.009, -0.121, 0.067), 0.005), 0.002)               # nostrils
        B.cut(sh, B.SPH(P(s * 0.097, -0.082, 0.152), 0.034), 0.006)               # gauge sockets
        B.cut(sh, B.E(P(s * 0.03, -0.104, 0.098), (0.022, 0.01, 0.014)), 0.012)   # nasolabial hollows
    B.add(sh, B.RC(P(0, -0.108, 0.13), P(0, -0.129, 0.082), 0.0105, 0.017), 0.012)  # nose
    B.add(sh, B.E(P(0, -0.098, 0.05), (0.027, 0.011, 0.0085)), 0.006)            # upper lip
    B.add(sh, B.E(P(0, -0.095, 0.037), (0.023, 0.012, 0.0095)), 0.006)           # lower lip
    B.cut(sh, B.E(P(0, -0.104, 0.0435), (0.028, 0.02, 0.0016)), 0.002)           # closed mouth line
    B.cut(sh, B.SPH(h.eye_c + Vector((0, -0.004, 0)), 0.045), 0.006)             # central eye socket
    B.add(sh, B.RC(P(0, 0.015, (neck_bottom - h.o.z) / HEAD_SCALE), P(0, 0.01, 0.03), 0.034, 0.042), 0.03)   # neck (thin)
    lo = P(-0.16, -0.17, (neck_bottom - h.o.z) / HEAD_SCALE)
    hi = P(0.16, 0.16, 0.335)
    ob = S.mesh_from_sdf(NAME + "_head", sh, tuple(lo), tuple(hi), 0.0016, "twin_face", decimate=0.25, smooth_iter=1)
    # cylindrical UVs around the head axis (must match texgen.twin_uv)
    me = ob.data
    uvl = me.uv_layers.active
    for poly in me.polygons:
        us = []
        for li in poly.loop_indices:
            co = ob.matrix_world @ me.vertices[me.loops[li].vertex_index].co - h.o
            u = 0.5 + math.atan2(co.x, -(co.y - h.CY)) / (2 * math.pi)
            v = (co.z + 0.01) / 0.34
            us.append([u, v])
        if max(a[0] for a in us) - min(a[0] for a in us) > 0.5:    # face straddles the back seam
            for a in us:
                if a[0] < 0.5:
                    a[0] += 1.0
        for li, (u, v) in zip(poly.loop_indices, us):
            uvl.data[li].uv = (u, v)
    T.shade_smooth(ob, 70)
    return ob


def clock_hands(h, parts, bones):
    """Dial hands growing out of the forehead, bent to hug the dome."""
    n = h.pivot_n
    bones["clock_hour"] = (h.pivot, h.pivot + n * 0.03)
    bones["clock_minute"] = (h.pivot, h.pivot + n * 0.035)

    def hand(name, angle_deg, length, r):
        a = math.radians(angle_deg)
        pts = []
        for k in range(11):
            t = k / 10 * length
            x = math.sin(a) * t
            z = 0.215 + math.cos(a) * t
            pts.append(tuple(h.on_dome(x, z, 0.004)))
        blade = T.tube(name, pts, r, "black_cavity", 6)
        tip = Vector(pts[-1])
        back = Vector(pts[-3])
        spear = T.cyl(name + "_tip", r * 2.6, 0.016, tuple(tip), "black_cavity", r2=0.0005, rot=tuple(facing(tip - back)), seg=4)
        return [blade, spear]

    for ob in hand("minute_hand", 38, 0.088, 0.0022):
        parts.append((ob, "clock_minute"))
    for ob in hand("hour_hand", 0, 0.052, 0.003):
        parts.append((ob, "clock_hour"))
    rot = facing(n)
    parts.append((T.cyl("clock_pin", 0.008, 0.01, tuple(h.pivot + n * 0.004), "brass", rot=tuple(rot), seg=16), "head"))
    parts.append((T.torus("clock_pin_ring", 0.011, 0.002, tuple(h.pivot + n * 0.002), "gold", rot=tuple(rot), seg=20, rseg=6), "head"))


def eye_assembly(h, parts, bones, lights):
    """Big dark central eye on the nose bridge with a hot red pupil."""
    c, r = h.eye_c, h.eye_r
    n = Vector((0, -1, 0.12)).normalized()
    rot = facing(n)
    parts.append((T.cyl("eye_housing", r + 0.004, 0.04, tuple(c - n * 0.024), "teal_metal", rot=tuple(rot), seg=48), "head"))
    parts.append((ring("eye_rim", c + n * 0.0, r, 0.0065, "black_cavity", rot, 64, 12), "head"))
    parts.append((ring("eye_rim_brass", c + n * 0.006, r - 0.008, 0.003, "brass", rot, 64, 8), "head"))
    for k in range(12):
        a = k / 12 * 2 * math.pi
        q = Euler(rot).to_quaternion()
        p = c + q @ Vector((math.cos(a) * (r + 0.001), math.sin(a) * (r + 0.001), 0)) + n * 0.006
        parts.append((T.sphere("eye_rivet", 0.0028, tuple(p), "gold", 8, 5), "head"))
    bones["eye"] = (c - n * 0.01, c + n * 0.04)
    parts.append((disc("eye_lens", c - n * 0.004, r - 0.012, 0.006, "eye_iris", rot, 64, planar=True), "eye"))
    parts.append((ring("eye_inner_ring", c - n * 0.0, r - 0.022, 0.002, "steel", rot, 48, 6), "eye"))
    parts.append((T.sphere("eye_pupil", 0.011, tuple(c + n * 0.0), "eye_glow", 20, 12, scale=(1, 1, 0.45)), "eye"))
    parts[-1][0].rotation_euler = rot
    parts.append((T.sphere("eye_glass", r - 0.012, tuple(c - n * 0.004), "glass", 32, 16, scale=(1, 1, 0.35)), "eye"))
    parts[-1][0].rotation_euler = rot
    lights.append(("eye", c + n * 0.05, {"energy": 0.8, "range": 2.0, "color": [1.0, 0.25, 0.06], "flicker": 0.06}))


def gauge_assembly(h, parts, bones, lights):
    """The two yellow gauge 'eyes' in thick dark housings."""
    for side, gc in zip(("R", "L"), h.gauge_c):
        s = -1 if side == "R" else 1
        n = Vector((s * 0.42, -1, 0.05)).normalized()
        rot = facing(n)
        r = h.gauge_r
        parts.append((T.cyl("gauge_case", r + 0.006, 0.04, tuple(gc - n * 0.024), "teal_metal", rot=tuple(rot), seg=40), "head"))
        parts.append((ring("gauge_rim", gc - n * 0.002, r + 0.002, 0.006, "black_cavity", rot, 48, 10), "head"))
        parts.append((ring("gauge_rim2", gc + n * 0.006, r - 0.002, 0.0028, "steel", rot, 48, 6), "head"))
        parts.append((disc("gauge_dial", gc - n * 0.002, r - 0.003, 0.004, "gauge_eye", rot, 48, planar=True), "head"))
        parts.append((disc("gauge_glass", gc + n * 0.002, r - 0.003, 0.002, "glass", rot, 40), "head"))
        bname = f"gauge_needle.{side}"
        bones[bname] = (gc, gc + n * 0.03)
        q = Euler(rot).to_quaternion()
        up = q @ Vector((0, 1, 0))
        parts.append((T.box("needle", (0.0018, r * 0.75, 0.001), tuple(gc + n * 0.0005 + up * (r * 0.3)), "black_cavity", rot=tuple(rot), uv=False), bname))
        led = gc + n * 0.002
        lights.append(("gauge", led + n * 0.03, {"energy": 0.25, "range": 0.7, "color": [1.0, 0.55, 0.15], "pulse": 0.5 + 0.2 * s}))


def ear_clamps(h, parts):
    """Mechanical brackets where the ears would be."""
    for s, c in zip((-1, 1), h.clamp_c):
        rot = (0, s * math.pi / 2, 0)
        parts.append((T.cyl("clamp_drum", 0.03, 0.03, tuple(c), "teal_metal", rot=rot, seg=32), "head"))
        parts.append((T.torus("clamp_ring", 0.03, 0.005, tuple(c + Vector((s * 0.015, 0, 0))), "brass", rot=rot, seg=32, rseg=8), "head"))
        parts.append((T.cyl("clamp_hub", 0.012, 0.02, tuple(c + Vector((s * 0.022, 0, 0))), "gold", rot=rot, seg=16), "head"))
        for k in range(8):   # gear teeth on the drum
            a = k / 8 * 2 * math.pi
            p = c + Vector((s * 0.005, math.cos(a) * 0.034, math.sin(a) * 0.034))
            parts.append((T.box("clamp_tooth", (0.024, 0.008, 0.008), tuple(p), "teal_metal", rot=(a, 0, 0)), "head"))
        parts.append((T.box("clamp_bar", (0.014, 0.07, 0.016), tuple(c + Vector((s * 0.004, 0.045, -0.02))), "black_cavity", rot=(0.4, 0, 0), bevel=0.003), "head"))
        parts.append((T.box("clamp_bar2", (0.012, 0.016, 0.06), tuple(c + Vector((s * 0.006, -0.02, -0.045))), "teal_metal", rot=(0, 0, 0), bevel=0.003), "head"))
        for dz in (-0.018, 0.018):
            parts.append((T.cyl("clamp_bolt", 0.004, 0.012, tuple(c + Vector((s * 0.028, 0.02, dz))), "gold", rot=rot, seg=8), "head"))


def wire_nest(h, parts, bones):
    """Thin golden wires tangled over the dome and up into the frame behind."""
    for b, (bx, by) in enumerate([(-1, 0.5), (1, 0.5), (0, 1.0), (0, 0.0)]):
        anchor = h.P(bx * 0.08, 0.04 + by * 0.06, 0.29)
        bones[f"wires.{b}"] = (anchor, anchor + Vector((bx * 0.08, by * 0.08, 0.12)))
    mats = ["wire_gold", "wire_gold", "wire_gold", "brass", "copper", "wire_black"]
    for k in range(140):
        # start on the top/back of the dome, keep the painted forehead clear
        x = RND.uniform(-0.11, 0.11)
        z = RND.uniform(0.27, 0.315)
        front = RND.random() < 0.08          # keep the painted dial on the forehead visible
        a = h.on_dome(x, z, 0.0)
        if not front:
            a = a + Vector((0, RND.uniform(0.04, 0.2), 0))
            a.y = min(a.y, h.o.y + h.CY + h.RY * 0.9)
            a.z = min(a.z, h.top.z - 0.005)
        out = (a - h.P(0, h.CY, h.CZ)).normalized()
        mid = a + out * RND.uniform(0.02, 0.09) + Vector((RND.gauss(0, 0.03), RND.gauss(0, 0.03), RND.uniform(0.01, 0.08)))
        if RND.random() < 0.6:
            end = h.on_dome(RND.uniform(-0.11, 0.11), RND.uniform(0.25, 0.31), 0.0) + Vector((0, RND.uniform(0.0, 0.15), 0))
        else:   # up into the frame towers behind the head
            sx = RND.choice((-1, 1))
            end = h.P(sx * RND.uniform(0.11, 0.15), RND.uniform(0.12, 0.17), RND.uniform(0.3, 0.55))
        pts = A_curve(a, mid, end, 16, wobble=0.004)
        rad = RND.choice([0.0007, 0.0009, 0.0012, 0.0012, 0.0016, 0.0022])
        if RND.random() < 0.45:   # curl the filament into small loops like the reference
            curled = []
            for i, q in enumerate(pts):
                q = Vector(q)
                if 0 < i < len(pts) - 1:
                    ang = i * 1.6 + k
                    q = q + Vector((math.cos(ang), math.sin(ang), math.cos(ang * 0.7))) * 0.008
                curled.append(tuple(q))
            pts = curled
        ob = T.tube("nest_wire", pts, rad, RND.choice(mats), 5)
        bundle = 0 if a.x < h.o.x - 0.04 else 1 if a.x > h.o.x + 0.04 else (2 if a.y > h.o.y + 0.05 else 3)
        parts.append((ob, f"wires.{bundle}"))
    # small clock parts caught in the nest
    for k in range(14):
        p = h.on_dome(RND.uniform(-0.1, 0.1), RND.uniform(0.27, 0.31), RND.uniform(0.015, 0.05))
        p.y += RND.uniform(0.0, 0.12)
        rot = facing((RND.uniform(-1, 1), RND.uniform(-1, 1), 1))
        r = RND.uniform(0.008, 0.016)
        parts.append((T.cyl("nest_gear", r, 0.003, tuple(p), RND.choice(["gold", "brass"]), rot=tuple(rot), seg=20), "head"))
        q = Euler(rot).to_quaternion()
        for t in range(10):
            a_ = t / 10 * 2 * math.pi
            tp = p + q @ Vector((math.cos(a_) * (r + 0.002), math.sin(a_) * (r + 0.002), 0))
            parts.append((T.box("nest_tooth", (0.003, 0.003, 0.003), tuple(tp), "gold", rot=tuple(rot), uv=False), "head"))


def back_frame(h, j, parts, lights):
    """Dark mechanical frame on the upper back rising behind the head (reference silhouette)."""
    cu = Vector(j["chest_up"][1])
    base_y = cu.y + 0.1
    top_z = h.top.z + 0.32
    for s in (-1, 1):
        x = s * 0.13
        parts.append((T.box("tower", (0.06, 0.05, top_z - cu.z), (x, base_y + 0.04, (cu.z + top_z) / 2), "painted_metal", bevel=0.006), "chest_up"))
        parts.append((T.box("tower_cap", (0.075, 0.065, 0.03), (x, base_y + 0.04, top_z + 0.015), "teal_metal", bevel=0.005), "chest_up"))
        parts.append((T.cyl("tower_lamp", 0.01, 0.02, (x, base_y + 0.04, top_z + 0.04), "light_red", seg=12), "chest_up"))
        lights.append(("tower", Vector((x, base_y + 0.0, top_z + 0.06)), {"energy": 0.3, "range": 1.2, "color": [1.0, 0.15, 0.05], "pulse": 0.4}))
        for k in range(3):   # pipes running up the towers
            parts.append((T.cyl("tower_pipe", 0.008, top_z - cu.z, (x + (k - 1) * 0.018, base_y + 0.072, (cu.z + top_z) / 2), RND.choice(["copper", "brass", "rust"]), seg=10), "chest_up"))
        g = T.cyl("tower_gauge", 0.018, 0.01, (x, base_y + 0.012, h.top.z + 0.1), "gauge", rot=(math.pi / 2, 0, 0), seg=20, uv=False)
        T.planar_uv(g, "Z")
        parts.append((g, "chest_up"))
    for z in (cu.z + 0.12, h.top.z + 0.2):
        parts.append((T.box("frame_bar", (0.3, 0.035, 0.03), (0, base_y + 0.05, z), "painted_metal", bevel=0.005), "chest_up"))
    parts.append((T.box("back_plate", (0.26, 0.03, 0.22), (0, base_y + 0.02, cu.z - 0.02), "teal_metal", bevel=0.01), "chest_up"))


def neck_gold(h, j, parts):
    """Ornate gold mechanisms around the neck (reference)."""
    nk, nt = Vector(j["neck"][1]), Vector(j["neck_top"][1])
    for k, t in enumerate((0.15, 0.55, 0.9)):
        p = nk.lerp(nt, t)
        parts.append((T.torus("neck_ring", 0.048 - k * 0.002, 0.0045, tuple(p), "gold", seg=32, rseg=8), "neck"))
    parts.append((T.tube("throat_rod", [tuple(nk + Vector((0, -0.05, -0.02))), tuple(nt + Vector((0, -0.052, 0.0)))], 0.006, "brass", 8), "neck"))
    for k in range(3):
        p = nk.lerp(nt, 0.2 + k * 0.3) + Vector((0, -0.053, 0))
        parts.append((T.cyl("throat_gear", 0.011, 0.004, tuple(p), "gold", rot=(math.pi / 2, 0, 0), seg=16), "neck"))


def A_curve(a, m, b, steps, wobble=0.0):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        p = (1 - t) ** 2 * a + 2 * (1 - t) * t * m + t * t * b
        if 0 < i < steps and wobble:
            p = p + Vector((RND.gauss(0, wobble), RND.gauss(0, wobble), RND.gauss(0, wobble)))
        pts.append(tuple(p))
    return pts


# =====================================================================
# Body and clothing
# =====================================================================

def clothing(j, body):
    """Torn research-subject uniform: long-sleeve top + trousers (SDF shells)."""
    J = lambda n: Vector(j[n][1])
    out = []
    # shirt
    sh = S.Shape()
    pel, ch, cu = J("pelvis"), J("chest"), J("chest_up")
    B.add(sh, B.RC(pel + Vector((0, 0.01, 0.0)), cu, 0.128, 0.132), 0.04)
    B.add(sh, B.E(ch + Vector((0, 0.0, 0.03)), (0.138, 0.105, 0.165)), 0.05)
    B.add(sh, B.E(cu + Vector((0, 0.01, 0.0)), (0.152, 0.095, 0.075)), 0.05)
    for sd in ("L", "R"):
        shp, el, wr = J(f"shoulder.{sd}"), J(f"elbow.{sd}"), J(f"wrist.{sd}")
        B.add(sh, B.RC(shp + Vector((0, 0.0, 0.0)), el, 0.05, 0.043), 0.035)
        B.add(sh, B.RC(el, el.lerp(wr, 0.7), 0.043, 0.035), 0.02)
    shirt = S.mesh_from_sdf(NAME + "_shirt", sh, (-0.62, -0.3, 0.8), (0.62, 0.3, 1.7), 0.005, "fabric_white", decimate=0.25, smooth_iter=2)
    cut_cloth(shirt, keep=lambda p: p.z > pel.z - 0.04 + 0.02 * math.sin(p.x * 30) and p.z < cu.z + 0.075)
    out.append(shirt)
    # trousers
    pt = S.Shape()
    B.add(pt, B.E(pel + Vector((0, 0.01, -0.02)), (0.15, 0.11, 0.1)), 0.06)
    for sd in ("L", "R"):
        hip, kn, an = J(f"hip.{sd}"), J(f"knee.{sd}"), J(f"ankle.{sd}")
        B.add(pt, B.RC(hip + Vector((0, 0.005, 0.02)), kn, 0.08, 0.058), 0.05)
        B.add(pt, B.SPH(kn + Vector((0, -0.012, 0.0)), 0.056), 0.03)
        B.add(pt, B.RC(kn, kn.lerp(an, 0.75), 0.056, 0.047), 0.02)
    pants = S.mesh_from_sdf(NAME + "_pants", pt, (-0.3, -0.25, 0.0), (0.3, 0.25, 1.15), 0.005, "fabric_dark", decimate=0.25, smooth_iter=2)
    hem = {sd: J(f"knee.{sd}").lerp(J(f"ankle.{sd}"), 0.72).z for sd in ("L", "R")}
    cut_cloth(pants, keep=lambda p: p.z < pel.z + 0.06 and p.z > hem["L" if p.x > 0 else "R"] + 0.025 * math.sin(p.y * 70 + p.x * 20))
    out.append(pants)
    return out


def cut_cloth(ob, keep, tears=0.11):
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    cs = [ob.matrix_world @ f.calc_center_median() for f in bm.faces]
    pts = np.array([tuple(c) for c in cs], np.float32)
    noise = S.value_noise3(pts, 22.0, seed=5) * 0.6 + S.value_noise3(pts, 55.0, seed=9) * 0.4
    kill = [f for f, c, nz in zip(bm.faces, cs, noise) if not keep(c) or nz > 1.0 - tears * 2]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    sol = ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = 1.0
    T.apply_all([ob])


def body_implants(j, body, parts):
    """Subtle implants: spine port, neck cables into the casing, wrist bands."""
    J = lambda n: Vector(j[n][1])
    for k, z in enumerate((1.3, 1.38, 1.46)):
        p = project(body, [(0, 0, z)], direction=(0, -1, 0), lift=0.006)[0]
        parts.append((T.cyl("spine_port", 0.016, 0.014, p, "teal_metal", rot=(math.pi / 2, 0, 0), seg=16), "chest"))
        parts.append((T.torus("spine_port_ring", 0.016, 0.003, p, "brass", rot=(math.pi / 2, 0, 0), seg=20, rseg=6), "chest"))
    for sd in ("L", "R"):
        w = J(f"wrist.{sd}")
        e = J(f"elbow.{sd}")
        d = (w - e).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(d).to_euler()
        parts.append((T.torus("wrist_band", 0.03, 0.006, tuple(w - d * 0.03), "brass", rot=tuple(rot), seg=24, rseg=6), f"farm.{sd}"))
        parts.append((T.torus("wrist_band2", 0.029, 0.004, tuple(w - d * 0.045), "teal_metal", rot=tuple(rot), seg=24, rseg=6), f"farm.{sd}"))


# =====================================================================
# Rig extras + animation
# =====================================================================

def add_extra_bones(arm, bones):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for name, (h, t) in bones.items():
        b = eb.new(name)
        b.head, b.tail = h, t
        b.parent = eb["head"]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"


def twin_animations(anim, h):
    clock_axis = tuple(h.pivot_n)
    eye_up = (0, 0, 1)

    def base(t, slump=0.0):
        breath = wave(t, 0, 2) * 1.2
        return {
            "spine1": [(X, 4 + slump * 10 + breath * 0.3)],
            "spine2": [(X, 3 + slump * 12 + breath * 0.5)],
            "chest": [(X, 2 + slump * 10 + breath), (Y, 2)],
            "neck": [(X, -4 + slump * 18)],
            "head": [(X, -2 + slump * 20), (Y, 6)],
            "uarm.L": [(Y, 34 + slump * 6), (X, 4)], "uarm.R": [(Y, -34 - slump * 6), (X, 4)],
            "farm.L": [(X, -10)], "farm.R": [(X, -12)],
            "hand.L": [(X, -6)], "hand.R": [(X, -6)],
            "thigh.L": [(X, -2 - slump * 4)], "thigh.R": [(X, -2 - slump * 4)],
            "shin.L": [(X, 4 + slump * 8)], "shin.R": [(X, 4 + slump * 8)],
            "_loc": (0, 0, -0.01 - slump * 0.03),
        }

    def add(p, bone, rots):
        p[bone] = p.get(bone, []) + rots

    def fingers(p, curl, side):
        s = 1 if side == "L" else -1
        for f in ("index", "middle", "ring", "pinky"):
            add(p, f"{f}1.{side}", [(Y, s * curl)])
            add(p, f"{f}2.{side}", [(Y, s * curl * 1.3)])

    def clock(p, t, minute_turns=1.0, hour_turns=1 / 12):
        add(p, "clock_minute", [(clock_axis, -360 * minute_turns * t)])
        add(p, "clock_hour", [(clock_axis, -360 * hour_turns * t - 70)])

    def gauges(p, t, jitter=1.0):
        for sd, ph in (("L", 0.0), ("R", 0.37)):
            v = 25 * wave(t, ph, 3) + 8 * wave(t, ph * 2, 11) * jitter
            add(p, f"gauge_needle.{sd}", [((0, -1, 0), v - 20)])

    def idle(t):
        p = base(t)
        add(p, "head", [(Z, wave(t, 0.1) * 4), (Y, wave(t, 0.4, 0.5) * 3)])
        add(p, "eye", [(eye_up, wave(t, 0, 1) * 10), (X, wave(t, 0.3, 2) * 4)])
        fingers(p, 12 + wave(t, 0, 4) * 4, "L")
        fingers(p, 14 + spike(t, 0.6, 0.02) * 30, "R")
        clock(p, t, 1.0)
        gauges(p, t)
        return p

    def head_tilt(t):
        p = base(t)
        k = math.sin(t * math.pi) ** 2        # slow tilt and return
        add(p, "head", [(Y, 38 * k), (Z, -12 * k)])
        add(p, "neck", [(Y, 10 * k)])
        add(p, "eye", [(eye_up, -15 * k)])
        clock(p, t, 0.5)
        gauges(p, t, 0.5)
        return p

    def eye_scan(t):
        p = base(t)
        stops = [(0.0, 0, 0), (0.2, 25, 5), (0.35, 25, 5), (0.5, -22, -6), (0.7, -22, -6), (0.85, 0, 12), (1.0, 0, 0)]
        for (t0, a0, b0), (t1, a1, b1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                u = (t - t0) / (t1 - t0)
                u = u * u * (3 - 2 * u)
                yaw, pitch = a0 + (a1 - a0) * u, b0 + (b1 - b0) * u
        add(p, "eye", [(eye_up, yaw), (X, -pitch)])
        add(p, "head", [(Z, yaw * 0.25)])
        clock(p, t, 1.0)
        gauges(p, t)
        return p

    def clock_spin(t):
        p = base(t)
        clock(p, t, 6.0, 0.5)
        gauges(p, t, 3.0)
        add(p, "head", [(Y, 4 * wave(t, 0, 8))])
        return p

    def twitch(t):
        p = base(t)
        for k, at in enumerate((0.12, 0.2, 0.47, 0.55, 0.58, 0.83)):
            s = spike(t, at, 0.008)
            add(p, "head", [(Y, (30 if k % 2 else -34) * s), (X, 14 * s)])
            add(p, "neck", [(Z, (18 if k % 2 else -20) * s)])
            add(p, "clav.L" if k % 2 else "clav.R", [(X, -15 * s)])
            add(p, "eye", [(eye_up, (40 if k % 2 else -40) * s)])
        clock(p, t, 2.0)
        gauges(p, t, 4.0)
        return p

    def wire_vibrate(t):
        p = idle(t)
        for b in range(4):
            add(p, f"wires.{b}", [(X, 3 * wave(t, b * 0.21, 14)), (Z, 2.5 * wave(t, b * 0.33, 19))])
        return p

    def walk_slow(t):
        p = base(t)
        s = wave(t)
        c_ = math.cos(t * 2 * math.pi)
        add(p, "thigh.L", [(X, -20 * s)])
        add(p, "thigh.R", [(X, 20 * s)])
        add(p, "shin.L", [(X, 24 * max(0.0, c_))])
        add(p, "shin.R", [(X, 24 * max(0.0, -c_))])
        add(p, "pelvis", [(Y, 4 * s), (Z, -4 * s)])
        add(p, "spine2", [(Z, 4 * s)])
        add(p, "uarm.L", [(X, 8 * s)])
        add(p, "uarm.R", [(X, -8 * s)])
        add(p, "head", [(Z, -3 * s)])
        p["_loc"] = (0, 0, -0.015 - 0.02 * abs(s))
        clock(p, t, 1.0)
        gauges(p, t)
        return p

    def posture_shift(t):
        # slumped -> unnaturally upright with a head snap -> slumped
        k = 0.5 - 0.5 * math.cos(t * 2 * math.pi)
        slump = 1.0 - k
        p = base(t, slump)
        snap = spike(t, 0.5, 0.03)
        add(p, "head", [(X, -12 * snap), (Y, 20 * snap)])
        add(p, "chest", [(X, -6 * k)])
        clock(p, t, 1.0)
        gauges(p, t)
        return p

    def reveal(t):
        # head hangs low, then rises slowly; arms open slightly; ends held
        u = min(1.0, max(0.0, (t - 0.1) / 0.75))
        u = u * u * (3 - 2 * u)
        p = base(t, 1.0 - u)
        add(p, "head", [(X, 25 * (1 - u) - 6 * u), (Y, 8 * (1 - u))])
        add(p, "uarm.L", [(Y, -12 * u), (X, -6 * u)])
        add(p, "uarm.R", [(Y, 12 * u), (X, -6 * u)])
        add(p, "farm.L", [(X, -14 * u)])
        add(p, "farm.R", [(X, -14 * u)])
        fingers(p, 30 * u, "L")
        fingers(p, 30 * u, "R")
        add(p, "eye", [(eye_up, 0)])
        clock(p, t, 0.25 + 2.0 * u)
        gauges(p, t, 1.0 + 3 * u)
        return p

    anim.action("idle", 150, idle)
    anim.action("head_tilt", 120, head_tilt)
    anim.action("eye_scan", 150, eye_scan)
    anim.action("clock_spin", 90, clock_spin)
    anim.action("twitch", 90, twitch)
    anim.action("wire_vibrate", 90, wire_vibrate)
    anim.action("walk_slow", 60, walk_slow)
    anim.action("posture_shift", 180, posture_shift)
    anim.action("reveal", 180, reveal, loop=False)


# =====================================================================
# Build
# =====================================================================

def collar(j, parts):
    """White shirt collar (rigid on the upper chest)."""
    nk = Vector(j["neck"][1])
    parts.append((T.cyl("collar_band", 0.052, 0.04, tuple(nk + Vector((0, 0.005, -0.01))), "fabric_white", r2=0.047, seg=36, cap=False), "chest_up"))
    for s in (-1, 1):   # folded collar points lying on the chest
        p = nk + Vector((s * 0.03, -0.05, -0.04))
        parts.append((T.box("collar_flap", (0.04, 0.005, 0.05), tuple(p), "fabric_white", rot=(0.45, s * 0.35, s * 0.5), bevel=0.002), "chest_up"))


def build():
    T.reset()
    j = A.skeleton(arm_len=1.04, leg_len=1.03, thin=0.9, finger_len=1.18, asym=0.0, seed=7)
    nt, nk = Vector(j["neck_top"][1]), Vector(j["neck"][1])
    h = Head(nt + Vector((0, -0.02, -0.02)))          # chin sits just in front of the neck top
    body = S.mesh_from_sdf(NAME + "_body", B.body_shape(j, {"w": 0.9, "emaciated": 0.45, "muscle": 0.35}),
                           (-0.7, -0.3, -0.02), (0.7, 0.3, 1.9), 0.0028, "skin", decimate=0.16)
    head = head_mesh(h, nk.z - 0.03)
    parts, bones, lights = [], {}, []
    clock_hands(h, parts, bones)
    eye_assembly(h, parts, bones, lights)
    gauge_assembly(h, parts, bones, lights)
    ear_clamps(h, parts)
    wire_nest(h, parts, bones)
    # enlarge everything that belongs to the head about the chin point
    o = h.o
    S_ = Matrix.Translation(o) @ Matrix.Scale(HEAD_SCALE, 4) @ Matrix.Translation(-o)
    bpy.context.view_layer.update()
    for ob in [head] + [ob for ob, _ in parts]:
        ob.matrix_world = S_ @ ob.matrix_world
    T.apply_all([head] + [ob for ob, _ in parts])
    for ob in [head] + [ob for ob, _ in parts]:
        bpy.context.view_layer.objects.active = ob
        with bpy.context.temp_override(active_object=ob, selected_editable_objects=[ob], selected_objects=[ob]):
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for k, (a, b) in list(bones.items()):
        bones[k] = (S_ @ Vector(a), S_ @ Vector(b))
    lights[:] = [(kind, S_ @ Vector(pos), props) for kind, pos, props in lights]
    head_top = S_ @ h.top
    h.top = head_top
    back_frame(h, j, parts, lights)
    neck_gold(h, j, parts)
    collar(j, parts)
    body_implants(j, body, parts)
    cloth = clothing(j, body)
    # rig
    arm = A.rig(NAME + "_rig", j, h.top)
    add_extra_bones(arm, bones)
    neck_z = nt.z
    head_rule = [(lambda p: p.z > neck_z + 0.015 and abs(p.x) < 0.17, "head")]
    A.skin_to(body, arm, overrides=head_rule, parent=False, bone_filter=lambda n: n not in bones)
    A.skin_to(head, arm, overrides=[(lambda p: p.z > h.o.z + 0.02, "head")], parent=False,
              bone_filter=lambda n: n in ("neck", "head", "chest_up"))
    no_arms = lambda n: n not in bones and not any(n.startswith(k) for k in ("index", "middle", "ring", "pinky", "thumb", "hand"))
    no_upper = lambda n: n in ("pelvis", "spine1") or any(n.startswith(k) for k in ("thigh", "shin", "foot", "toe"))
    A.skin_to(cloth[0], arm, parent=False, bone_filter=no_arms, falloff=3.0)
    A.skin_to(cloth[1], arm, parent=False, bone_filter=no_upper, falloff=3.0)
    flesh = T.join([body, head] + cloth, NAME + "_flesh")
    flesh.parent = arm
    flesh.matrix_parent_inverse = arm.matrix_world.inverted()
    flesh.modifiers.new("armature", "ARMATURE").object = arm
    # hard-surface: join parts per bone (fewer draw calls), then bone-parent
    by_bone = {}
    for ob, bone in parts:
        by_bone.setdefault(bone, []).append(ob)
    rigid = []
    for bone, obs in by_bone.items():
        joined = T.join(obs, f"{NAME}_{bone.replace('.', '_')}_parts")
        T.shade_smooth(joined, 35)
        A.attach_to_bone(joined, arm, bone)
        rigid.append(joined)
    for i, (kind, pos, props) in enumerate(lights):
        e = T.empty(f"L__{kind}__{i}", tuple(pos), props=props)
        A.attach_to_bone(e, arm, {"eye": "eye", "tower": "chest_up"}.get(kind, "head"))
        rigid.append(e)
    anim = A.Animator(arm)
    twin_animations(anim, h)
    T.save_blend(f"source/blender/characters/{NAME}.blend")
    T.export_glb(f"assets/models/characters/{NAME}.glb", [arm, flesh] + rigid, animations=True)


if __name__ == "__main__":
    build()
