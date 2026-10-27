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
from creatures import project, gown  # noqa: E402

NAME = "twin_monster"
RND = random.Random(1979)


# =====================================================================
# Head layout (all relative to the lower-face centre F)
# =====================================================================

class Head:
    def __init__(self, F):
        self.F = Vector(F)
        f = self.F
        self.clock_c = f + Vector((0, -0.062, 0.25))         # dial centre, high on the skull
        self.clock_tilt = math.radians(16)                    # leans back
        self.clock_r = 0.125
        self.eye_c = f + Vector((0, -0.098, 0.05))
        self.eye_r = 0.047
        self.gauge_c = [f + Vector((s * 0.098, -0.07, 0.04)) for s in (-1, 1)]
        self.gauge_r = 0.04
        self.casing_c = f + Vector((0, 0.014, 0.165))
        self.casing_r = (0.15, 0.135, 0.2)

    def clock_normal(self):
        """Outward normal of the dial (front = -Y, tilted up)."""
        return Vector((0, -math.cos(self.clock_tilt), math.sin(self.clock_tilt)))

    def clock_rot(self):
        """Euler that turns a +Z-facing disc into the dial orientation."""
        return Vector((0, 0, 1)).rotation_difference(self.clock_normal()).to_euler()


def disc(name, c, r, depth, mat, rot, seg=64, planar=False, r2=None):
    ob = T.cyl(name, r, depth, tuple(c), mat, rot=tuple(rot), seg=seg, uv=not planar, r2=r2)
    if planar:
        T.planar_uv(ob, "Z")
    return ob


def ring(name, c, R, r, mat, rot, seg=96, rseg=12):
    return T.torus(name, R, r, tuple(c), mat, rot=tuple(rot), seg=seg, rseg=rseg)


# =====================================================================
# Hard-surface head assembly
# =====================================================================

def casing_mesh(h):
    """Teal metal skull casing (SDF) with recesses for clock, eye and gauges."""
    sh = S.Shape()
    c, r = h.casing_c, h.casing_r
    B.add(sh, B.E(c, r), 0.0)
    # brow plate bulges forward over the eye/gauges
    B.add(sh, B.E(h.F + Vector((0, -0.05, 0.085)), (0.13, 0.06, 0.05)), 0.03)
    # temples flare out to hold the gauges
    for gc in h.gauge_c:
        B.add(sh, B.E(gc + Vector((0, 0.025, 0.0)), (0.055, 0.05, 0.055)), 0.03)
    # flatten the front where the dial sits (plane cut through the dial centre)
    n = h.clock_normal()
    p0 = h.clock_c - n * 0.026          # flat seat well behind the dial
    # signed distance to the dial plane, negative in front of it -> carved away
    sh.cut(lambda p: (p - B.v(p0)) @ B.v(-n), 0.01, None)
    # sockets
    B.cut(sh, B.SPH(h.eye_c + Vector((0, -0.012, 0)), h.eye_r + 0.008), 0.004)
    for gc in h.gauge_c:
        B.cut(sh, B.SPH(gc + Vector((0, -0.02, 0)), h.gauge_r + 0.006), 0.004)
    # panel seams: thin grooves around the skull
    for k, z in enumerate((0.06, 0.15, 0.24)):
        B.cut(sh, B.E(c + Vector((0, 0.02, z - 0.1)), (r[0] + 0.004, r[1] + 0.004, 0.0025)), 0.0)
    B.cut(sh, B.E(c + Vector((0, 0.03, 0.05)), (0.0025, r[1] + 0.01, r[2] + 0.01)), 0.0)
    lo = c - Vector(r) - Vector((0.05, 0.08, 0.05))
    hi = c + Vector(r) + Vector((0.05, 0.05, 0.05))
    ob = S.mesh_from_sdf(NAME + "_casing", sh, tuple(lo), tuple(hi), 0.0024, "teal_metal", decimate=0.18, smooth_iter=1)
    T.shade_smooth(ob, 45)
    return ob


def clock_assembly(h, parts, bones):
    rot = h.clock_rot()
    n = h.clock_normal()
    c, R = h.clock_c, h.clock_r
    # recessed porcelain dial with physical depth (sits slightly inside the bezel)
    parts.append((disc("dial", c - n * 0.006, R, 0.012, "porcelain", rot, 96, planar=True), "head"))
    parts.append((disc("dial_back", c - n * 0.02, R + 0.01, 0.024, "teal_metal", rot, 64), "head"))
    parts.append((ring("bezel", c + n * 0.004, R + 0.012, 0.014, "brass", rot, 128, 14), "head"))
    parts.append((ring("bezel_outer", c - n * 0.004, R + 0.03, 0.009, "copper", rot, 128, 10), "head"))
    parts.append((ring("bezel_inner", c + n * 0.0, R - 0.006, 0.004, "gold", rot, 128, 8), "head"))
    # bezel screws
    q = Euler(rot).to_quaternion()
    for k in range(16):
        a = k / 16 * 2 * math.pi
        p = c + q @ Vector((math.cos(a) * (R + 0.024), math.sin(a) * (R + 0.024), 0)) + n * 0.008
        parts.append((T.cyl("bezel_screw", 0.0045, 0.006, tuple(p), "gold", rot=tuple(rot), seg=10), "head"))
    # cracked glass cover, slightly domed
    parts.append((disc("clock_glass", c + n * 0.006, R + 0.002, 0.004, "glass", rot, 96), "head"))
    # hands (rotate on their own bones) + centre pin + small seconds dial
    hub = c + n * 0.003
    bones["clock_hour"] = (hub, hub + n * 0.03)
    bones["clock_minute"] = (hub, hub + n * 0.035)
    up = q @ Vector((0, 1, 0))
    side = q @ Vector((1, 0, 0))

    def hand(name, length, width, mat="black_cavity", back=0.02):
        # a tapered blade made from a thin box pointing along `up`
        mid = hub + up * (length / 2 - back) + n * 0.002
        ob = T.box(name, (width, length + back, 0.0025), tuple(mid), mat, rot=tuple(rot), uv=False)
        tip = T.cyl(name + "_tip", width * 0.9, 0.003, tuple(hub + up * (length - back - 0.004) + n * 0.002), mat, rot=tuple(rot), seg=3)
        return [ob, tip]

    for ob in hand("hour_hand", R * 0.55, 0.009):
        parts.append((ob, "clock_hour"))
    for ob in hand("minute_hand", R * 0.85, 0.006):
        parts.append((ob, "clock_minute"))
    parts.append((T.cyl("clock_pin", 0.008, 0.012, tuple(hub + n * 0.004), "brass", rot=tuple(rot), seg=16), "head"))
    sub_c = c - up * (R * 0.45) + n * 0.001
    parts.append((ring("seconds_ring", sub_c, 0.022, 0.0025, "gold", rot, 40, 6), "head"))


def eye_assembly(h, parts, bones, lights):
    c, r = h.eye_c, h.eye_r
    rot = (math.pi / 2, 0, 0)            # discs face -Y
    fwd = Vector((0, -1, 0))
    # metal housing: stepped cylinders + concentric rings
    # housing sits behind the iris (front cap 6 mm behind it) so the eye is never covered
    parts.append((T.cyl("eye_housing", r + 0.01, 0.04, tuple(c + Vector((0, 0.026, 0))), "teal_metal", rot=rot, seg=48), "head"))
    parts.append((ring("eye_ring_outer", c + fwd * 0.008, r + 0.006, 0.007, "brass", rot, 64, 10), "head"))
    parts.append((ring("eye_ring_mid", c + fwd * 0.003, r - 0.006, 0.004, "steel", rot, 64, 8), "head"))
    for k in range(10):     # housing bolts
        a = k / 10 * 2 * math.pi
        p = c + Vector((math.cos(a) * (r + 0.009), -0.01, math.sin(a) * (r + 0.009)))
        parts.append((T.cyl("eye_bolt", 0.003, 0.006, tuple(p), "gold", rot=rot, seg=8), "head"))
    # the moving eyeball (iris + lens) on the "eye" bone
    bones["eye"] = (c + Vector((0, 0.01, 0)), c + fwd * 0.04)
    iris = disc("eye_iris", c + fwd * 0.0, r - 0.01, 0.006, "eye_iris", rot, 64, planar=True)
    parts.append((iris, "eye"))
    for k in range(8):      # aperture blades around the pupil
        a = k / 8 * 2 * math.pi
        p = c + fwd * 0.004 + Vector((math.cos(a) * 0.016, 0, math.sin(a) * 0.016))
        parts.append((T.box("aperture", (0.012, 0.002, 0.006), tuple(p), "black_cavity", rot=(math.pi / 2, a + 0.6, 0), uv=False), "eye"))
    parts.append((T.sphere("eye_pupil", 0.013, tuple(c + fwd * 0.004), "eye_glow", 20, 12, scale=(1, 0.45, 1)), "eye"))
    parts.append((T.sphere("eye_lens", r - 0.012, tuple(c + fwd * 0.0), "glass", 32, 16, scale=(1, 0.45, 1)), "eye"))
    parts.append((ring("eye_lens_rim", c + fwd * 0.006, r - 0.012, 0.003, "black_cavity", rot, 48, 6), "eye"))
    lights.append(("eye", c + fwd * 0.05, {"energy": 0.9, "range": 2.2, "color": [1.0, 0.32, 0.08], "flicker": 0.08}))


def gauge_assembly(h, parts, bones, lights):
    rot = (math.pi / 2, 0, 0)
    fwd = Vector((0, -1, 0))
    for side, gc in zip(("R", "L"), h.gauge_c):
        r = h.gauge_r
        s = -1 if side == "R" else 1
        tilt = (math.pi / 2, 0, s * 0.35)           # angled outward slightly
        q = Euler(tilt).to_quaternion()
        n = q @ Vector((0, 0, 1))
        parts.append((T.cyl("gauge_case", r + 0.008, 0.035, tuple(gc - n * 0.0155), "brass", rot=tilt, seg=40), "head"))
        parts.append((disc("gauge_dial", gc + n * 0.004, r, 0.004, "gauge", tilt, 48, planar=True), "head"))
        parts.append((ring("gauge_bezel", gc + n * 0.007, r + 0.004, 0.005, "copper", tilt, 48, 8), "head"))
        parts.append((disc("gauge_glass", gc + n * 0.009, r, 0.002, "glass", tilt, 40), "head"))
        bname = f"gauge_needle.{side}"
        bones[bname] = (gc + n * 0.006, gc + n * 0.03)
        up = q @ Vector((0, 1, 0))
        nd = T.box("needle", (0.003, r * 0.85, 0.0015), tuple(gc + n * 0.0065 + up * (r * 0.35)), "light_red", rot=tilt, uv=False)
        parts.append((nd, bname))
        parts.append((T.cyl("needle_pin", 0.004, 0.004, tuple(gc + n * 0.008), "black_cavity", rot=tilt, seg=10), "head"))
        # small lit indicator above each gauge
        led = gc + q @ Vector((0, r + 0.016, 0)) + n * 0.002
        parts.append((T.sphere("gauge_led", 0.0045, tuple(led), "light_amber", 10, 6), "head"))
        lights.append(("gauge", led + n * 0.02, {"energy": 0.12, "range": 0.5, "color": [1.0, 0.6, 0.2], "pulse": 0.7 + 0.3 * s}))


def wire_crown(h, parts, bones):
    """Dense tangle of wires, filaments and parts around the head.

    Wires are grouped into 4 bundles, each on a 'wires.N' bone so the
    wire_vibrate animation can shake them.
    """
    c, r = h.casing_c, h.casing_r

    def on_casing(theta, phi, out=0.0):
        d = Vector((math.cos(phi) * math.sin(theta), math.sin(phi) * math.sin(theta), math.cos(theta)))
        return c + Vector((d.x * (r[0] + out), d.y * (r[1] + out), d.z * (r[2] + out)))

    bundle_dirs = [(-1, 0.4), (1, 0.4), (0, 1.0), (0, 0.2)]  # left, right, back, top
    for b, (bx, by) in enumerate(bundle_dirs):
        anchor = c + Vector((bx * r[0] * 0.8, by * r[1] * 0.8, r[2] * (0.75 if b != 2 else 0.4)))
        tip = anchor + Vector((bx * 0.12, by * 0.12, 0.1))
        bones[f"wires.{b}"] = (anchor, tip)
    mats = ["wire_black"] * 5 + ["wire_red", "wire_copper", "rubber", "wire_black", "copper"]
    for k in range(78):
        theta = RND.uniform(0.15, 1.75)       # from top down to the sides/back
        phi = RND.uniform(-0.6, math.pi + 0.6)
        if math.sin(phi) < -0.25 and theta > 0.5:
            phi = math.pi - phi               # keep the face clear
        a = on_casing(theta, phi, -0.004)
        out = (a - c).normalized()
        L_ = RND.uniform(0.08, 0.32)
        mid = a + out * L_ * 0.7 + Vector((RND.gauss(0, 0.04), RND.gauss(0, 0.04), RND.uniform(0.0, 0.12)))
        if RND.random() < 0.55 or a.y < c.y - 0.02:   # loops back into the casing (front wires never hang)
            end = on_casing(min(1.9, theta + RND.uniform(-0.5, 0.6)), phi + RND.uniform(-0.8, 0.8), -0.004)
        else:                     # hangs down to the neck/shoulders
            end = h.F + Vector((RND.uniform(-0.15, 0.15), RND.uniform(0.0, 0.1), -0.16 - RND.uniform(0, 0.12)))
        pts = A_curve(a, mid, end, 14, wobble=0.008)
        rad = RND.choice([0.0018, 0.0025, 0.0035, 0.005, 0.007, 0.01])
        mat = "wire_copper" if rad < 0.002 else RND.choice(mats)
        ob = T.tube("crown_wire", pts, rad, mat, 6 if rad < 0.004 else 8)
        x = a.x
        bundle = 0 if x < -0.06 else 1 if x > 0.06 else (2 if a.y > c.y + 0.02 else 3)
        parts.append((ob, f"wires.{bundle}"))
    # small components caught in the tangle
    for k in range(22):
        theta, phi = RND.uniform(0.2, 1.5), RND.uniform(-0.3, math.pi + 0.3)
        if math.sin(phi) < -0.2:
            phi = math.pi - phi
        p = on_casing(theta, phi, RND.uniform(0.02, 0.07))
        n = (p - c).normalized()
        rot = Vector((0, 0, 1)).rotation_difference(n).to_euler()
        kind = k % 4
        if kind == 0:   # vacuum tube with a warm filament
            parts.append((T.cyl("vtube", 0.009, 0.04, tuple(p), "glass", rot=tuple(rot), seg=14), "head"))
            parts.append((T.cyl("vtube_glow", 0.003, 0.025, tuple(p), "light_amber", rot=tuple(rot), seg=8), "head"))
            parts.append((T.cyl("vtube_base", 0.01, 0.012, tuple(p - n * 0.024), "rubber", rot=tuple(rot), seg=14), "head"))
        elif kind == 1:   # capacitor
            parts.append((T.cyl("cap", 0.008, 0.026, tuple(p), RND.choice(["teal_metal", "copper", "steel"]), rot=tuple(rot), seg=12), "head"))
        elif kind == 2:   # copper coil
            parts.append((T.torus("coil", 0.012, 0.003, tuple(p), "copper", rot=tuple(rot), seg=20, rseg=6), "head"))
            parts.append((T.torus("coil2", 0.012, 0.003, tuple(p + n * 0.007), "copper", rot=tuple(rot), seg=20, rseg=6), "head"))
        else:             # tiny gear
            parts.append((T.cyl("gear", 0.014, 0.005, tuple(p), "gold", rot=tuple(rot), seg=24), "head"))
            for t in range(10):
                a_ = t / 10 * 2 * math.pi
                qq = Euler(rot).to_quaternion()
                tp = p + qq @ Vector((math.cos(a_) * 0.016, math.sin(a_) * 0.016, 0))
                parts.append((T.box("gear_tooth", (0.004, 0.004, 0.005), tuple(tp), "gold", rot=tuple(rot), uv=False), "head"))


def A_curve(a, m, b, steps, wobble=0.0):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        p = (1 - t) ** 2 * a + 2 * (1 - t) * t * m + t * t * b
        if 0 < i < steps and wobble:
            p = p + Vector((RND.gauss(0, wobble), RND.gauss(0, wobble), RND.gauss(0, wobble)))
        pts.append(tuple(p))
    return pts


def seam_rivets(h, face_mesh, parts):
    """Rivets and a dark gasket where flesh meets the metal casing."""
    c, r = h.casing_c, h.casing_r
    for k in range(26):
        a = math.pi + 0.35 + k / 25 * (math.pi - 0.7)   # front half, below the gauges
        x = math.cos(a) * r[0] * 0.92
        y = math.sin(a) * r[1] * 0.92
        z = c.z - r[2] * 0.62 + 0.012 * math.cos(a * 2)
        p = Vector((x, y, z))
        hit = project(face_mesh, [tuple(p + Vector((0, 0, 0.0)))], direction=(-x, -y, 0), lift=0.001)[0]
        parts.append((T.sphere("rivet", 0.0035, hit, "gold", 8, 5), "head"))


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
    shirt = S.mesh_from_sdf(NAME + "_shirt", sh, (-0.62, -0.3, 0.8), (0.62, 0.3, 1.7), 0.005, "fabric_uniform", decimate=0.25, smooth_iter=2)
    cut_cloth(shirt, keep=lambda p: p.z > pel.z - 0.04 + 0.02 * math.sin(p.x * 30) and not (abs(p.x) < 0.07 and p.z > cu.z + 0.03 and p.y < 0.02)
              and p.z < cu.z + 0.09)
    out.append(shirt)
    # trousers
    pt = S.Shape()
    B.add(pt, B.E(pel + Vector((0, 0.01, -0.02)), (0.15, 0.11, 0.1)), 0.06)
    for sd in ("L", "R"):
        hip, kn, an = J(f"hip.{sd}"), J(f"knee.{sd}"), J(f"ankle.{sd}")
        B.add(pt, B.RC(hip + Vector((0, 0.005, 0.02)), kn, 0.08, 0.058), 0.05)
        B.add(pt, B.SPH(kn + Vector((0, -0.012, 0.0)), 0.056), 0.03)
        B.add(pt, B.RC(kn, kn.lerp(an, 0.75), 0.056, 0.047), 0.02)
    pants = S.mesh_from_sdf(NAME + "_pants", pt, (-0.3, -0.25, 0.0), (0.3, 0.25, 1.15), 0.005, "fabric_uniform", decimate=0.25, smooth_iter=2)
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
    n = h.clock_normal()
    clock_axis = tuple(n)
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

def build():
    T.reset()
    j = A.skeleton(arm_len=1.04, leg_len=1.03, thin=0.9, finger_len=1.18, asym=0.0, seed=7)
    F = Vector(j["neck_top"][1]) + Vector((0, -0.01, 0.07))
    h = Head(F)
    # flesh: body + human lower face in one continuous SDF surface
    sh = B.body_shape(j, {"w": 0.9, "emaciated": 0.45, "muscle": 0.35})
    B.face(sh, F, {"jaw": 0.7, "chin": 0.55, "cheek": 0.75, "gaunt": 0.25, "nose_len": 0.95,
                   "nose_width": 0.75, "lip": 0.45, "mouth_open": 0.0}, upper_face=False)
    body = S.mesh_from_sdf(NAME + "_body", sh, (-0.7, -0.3, -0.02), (0.7, 0.3, 1.9), 0.0028, "skin", decimate=0.16)
    parts, bones, lights = [], {}, []
    casing = casing_mesh(h)
    clock_assembly(h, parts, bones)
    eye_assembly(h, parts, bones, lights)
    gauge_assembly(h, parts, bones, lights)
    wire_crown(h, parts, bones)
    seam_rivets(h, body, parts)
    body_implants(j, body, parts)
    cloth = clothing(j, body)
    # rig
    head_top = h.casing_c + Vector((0, 0, h.casing_r[2]))
    arm = A.rig(NAME + "_rig", j, head_top)
    add_extra_bones(arm, bones)
    neck_z = Vector(j["neck_top"][1]).z
    head_rule = [(lambda p: p.z > neck_z + 0.015 and abs(p.x) < 0.17, "head")]
    no_head = lambda n: n not in bones and n != "head"
    A.skin_to(body, arm, overrides=head_rule, parent=False, bone_filter=lambda n: n not in bones)
    no_arms = lambda n: n not in bones and not any(n.startswith(k) for k in ("index", "middle", "ring", "pinky", "thumb", "hand"))
    no_upper = lambda n: n in ("pelvis", "spine1") or any(n.startswith(k) for k in ("thigh", "shin", "foot", "toe"))
    A.skin_to(cloth[0], arm, parent=False, bone_filter=no_arms, falloff=3.0)
    A.skin_to(cloth[1], arm, parent=False, bone_filter=no_upper, falloff=3.0)
    flesh = T.join([body] + cloth, NAME + "_flesh")
    flesh.parent = arm
    flesh.matrix_parent_inverse = arm.matrix_world.inverted()
    flesh.modifiers.new("armature", "ARMATURE").object = arm
    # hard-surface: join parts per bone (fewer objects/draw calls), then bone-parent
    by_bone = {}
    for ob, bone in parts:
        by_bone.setdefault(bone, []).append(ob)
    by_bone.setdefault("head", []).append(casing)
    rigid = []
    for bone, obs in by_bone.items():
        joined = T.join(obs, f"{NAME}_{bone.replace('.', '_')}_parts")
        T.shade_smooth(joined, 35)
        A.attach_to_bone(joined, arm, bone)
        rigid.append(joined)
    # light markers on the head bone
    for kind, pos, props in lights:
        e = T.empty(f"L__{kind}__{len([x for x in rigid if x.type == 'EMPTY'])}", tuple(pos), props=props)
        A.attach_to_bone(e, arm, "eye" if kind == "eye" else "head")
        rigid.append(e)
    anim = A.Animator(arm)
    twin_animations(anim, h)
    T.save_blend(f"source/blender/characters/{NAME}.blend")
    T.export_glb(f"assets/models/characters/{NAME}.glb", [arm, flesh] + rigid, animations=True)


if __name__ == "__main__":
    build()
