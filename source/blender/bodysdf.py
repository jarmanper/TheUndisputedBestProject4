"""Anatomical humanoid described as a signed distance field.

body_shape(joints, opt) adds muscles/bones around the skeleton from
anatomy.skeleton(); face(shape, head_center, opt) adds a sculpted face.
Everything is smooth-unioned into one continuous surface.

opt keys (all optional): w (girth), emaciated (0..1 ribs/spine/hollow belly),
muscle (0..1), face dict (see face()).
"""
import math

import numpy as np
from mathutils import Matrix, Vector

import sdf as S


def v(x):
    return np.array(tuple(x), np.float32)


# --- primitive helpers that also return bounds (for fast block sampling)

def E(c, r, rot=None):
    c, r = v(c), v(r)
    m = float(max(r))
    return (lambda p: S.ellipsoid(p, c, r, rot)), (c - m, c + m)


def RC(a, b, r1, r2):
    a, b = v(a), v(b)
    m = max(r1, r2)
    return (lambda p: S.round_cone(p, a, b, r1, r2)), (np.minimum(a, b) - m, np.maximum(a, b) + m)


def CAP(a, b, r):
    a, b = v(a), v(b)
    return (lambda p: S.capsule(p, a, b, r)), (np.minimum(a, b) - r, np.maximum(a, b) + r)


def SPH(c, r):
    c = v(c)
    return (lambda p: S.sphere(p, c, r)), (c - r, c + r)


def RBOX(c, half, r, rot):
    c, h = v(c), v(half)
    m = float(np.linalg.norm(h))
    return (lambda p: S.rounded_box(p, c, h, r, rot)), (c - m, c + m)


def frame(direction, up=(0, -1, 0)):
    """World->local rotation whose local Z follows `direction`."""
    zv = Vector(direction).normalized()
    upv = Vector(up)
    if abs(zv.dot(upv)) > 0.95:
        upv = Vector((1, 0, 0))
    xv = upv.cross(zv).normalized()
    yv = zv.cross(xv)
    return np.array([tuple(xv), tuple(yv), tuple(zv)], np.float32)


def add(shape, prim, k=0.02):
    fn, b = prim
    shape.add(fn, k, b)


def cut(shape, prim, k=0.005):
    fn, b = prim
    shape.cut(fn, k, b)


# ------------------------------------------------------------------ body

def body_shape(j, opt=None):
    o = {"w": 1.0, "emaciated": 0.6, "muscle": 0.5}
    o.update(opt or {})
    w, em, mu = o["w"], o["emaciated"], o["muscle"]
    sh = S.Shape()
    J = lambda n: Vector(j[n][1])

    pel, sp1, sp2, ch, cu = J("pelvis"), J("spine1"), J("spine2"), J("chest"), J("chest_up")
    nk, nt = J("neck"), J("neck_top")
    # torso core
    add(sh, E(pel + Vector((0, 0.01, 0.0)), (0.145 * w, 0.095 * w, 0.095)), 0.04)
    add(sh, RC(sp1 + Vector((0, 0.005, 0)), ch, 0.108 * w * (1 - 0.15 * em), 0.118 * w), 0.06)
    add(sh, E(ch + Vector((0, 0.0, 0.025)), (0.142 * w, 0.098 * w, 0.155)), 0.05)
    add(sh, E(cu + Vector((0, 0.01, -0.01)), (0.15 * w, 0.085 * w, 0.075)), 0.05)
    # glutes, lats, scapulae, pecs
    for s in (-1, 1):
        add(sh, E(pel + Vector((s * 0.06, 0.055, -0.035)), (0.07 * w, 0.06 * w, 0.08)), 0.035)
        add(sh, E(ch + Vector((s * 0.095 * w, 0.04, -0.02)), (0.055 * w, 0.05, 0.12)), 0.04)
        add(sh, E(cu + Vector((s * 0.075, 0.08 * w, -0.035)), (0.055, 0.018, 0.07)), 0.025)
        add(sh, E(cu + Vector((s * 0.062, -0.068 * w, -0.04)), (0.07, 0.022 + 0.012 * mu, 0.05)), 0.03)
    # belly: hollow when emaciated
    if em > 0.3:
        cut(sh, E(sp1 + Vector((0, -0.11 * w, 0.05)), (0.08, 0.03 * em, 0.07)), 0.05)
    else:
        add(sh, E(sp1 + Vector((0, -0.06 * w, 0.03)), (0.09 * w, 0.045, 0.1)), 0.04)
    # ribs (visible when emaciated): arcs hugging the ribcage front
    if em > 0.2:
        for i in range(7):
            z = ch.z + 0.11 - i * 0.03
            spread = 0.125 * w * (1.0 - 0.15 * abs(i - 2) / 4)
            pts = []
            for a in np.linspace(-1.15, 1.15, 9):
                x = math.sin(a) * spread
                y = -math.cos(a) * 0.098 * w + 0.004
                pts.append(Vector((x, y, z - 0.035 * (abs(a) ** 1.5))))
            for a_, b_ in zip(pts, pts[1:]):
                add(sh, CAP(a_, b_, 0.006 * em), 0.012)
        # spine bumps
        for i in range(11):
            z = pel.z + 0.06 + i * 0.045
            add(sh, SPH((0, 0.088 * w + 0.008, z), 0.012 * em + 0.004), 0.016)
    # collarbones, trapezius, neck
    for s in (-1, 1):
        shp = J("shoulder.L" if s > 0 else "shoulder.R")
        add(sh, CAP(Vector((s * 0.018, -0.058, cu.z + 0.05)), shp + Vector((-s * 0.02, -0.035, 0.022)), 0.0075), 0.022)
        add(sh, RC(Vector((s * 0.022, 0.03, nk.z + 0.05)), shp + Vector((-s * 0.04, 0.025, 0.012)), 0.032 * w, 0.02), 0.05)
        # neck tendons (sternocleidomastoid)
        add(sh, CAP(Vector((s * 0.048, 0.015, nt.z + 0.02)), Vector((s * 0.012, -0.05, cu.z + 0.055)), 0.0115), 0.02)
    add(sh, RC(nk, nt + Vector((0, -0.005, 0.03)), 0.046 * w, 0.042), 0.03)
    add(sh, SPH((0, -0.041, nk.z + 0.03), 0.0065), 0.016)

    # arms
    for side in ("L", "R"):
        s = 1 if side == "L" else -1
        shp, el, wr, hd = J(f"shoulder.{side}"), J(f"elbow.{side}"), J(f"wrist.{side}"), J(f"hand.{side}")
        ua = (el - shp)
        fa = (wr - el)
        add(sh, E(shp + Vector((s * 0.018, 0.0, -0.025)), (0.052 * w, 0.056 * w, 0.07), frame(ua)), 0.035)
        add(sh, RC(shp, el, 0.04 * w, 0.03 * w), 0.03)
        add(sh, E(shp + ua * 0.55 + Vector((0, -0.018, 0)), (0.028 * w * (0.8 + mu * 0.4), 0.03 * w * (0.8 + mu * 0.4), 0.065), frame(ua)), 0.025)
        add(sh, E(shp + ua * 0.45 + Vector((0, 0.02, 0)), (0.03 * w, 0.028 * w, 0.075), frame(ua)), 0.025)
        add(sh, SPH(el + Vector((0, 0.022, 0)), 0.022), 0.02)
        add(sh, RC(el, wr, 0.033 * w, 0.02 * w), 0.025)
        add(sh, E(el + fa * 0.28 + Vector((s * 0.008, -0.006, 0)), (0.034 * w, 0.03 * w, 0.075), frame(fa)), 0.025)
        add(sh, E(wr, (0.024, 0.014, 0.014), frame(fa)), 0.012)
        # hand: palm + knuckles + fingers
        knuck = [J(f"{f}1.{side}") for f in ("index", "middle", "ring", "pinky")]
        kc = sum(knuck, Vector()) / 4
        hand_dir = (kc - wr)
        palm_c = wr + hand_dir * 0.55
        add(sh, RBOX(palm_c, (0.012, 0.038, hand_dir.length * 0.55), 0.01, frame(hand_dir, up=(s, 0, 0))), 0.012)
        for f in ("index", "middle", "ring", "pinky", "thumb"):
            a, b, c = J(f"{f}1.{side}"), J(f"{f}2.{side}"), J(f"{f}3.{side}")
            r0 = 0.0082 if f != "thumb" else 0.0098
            if f == "thumb":
                add(sh, RC(wr + hand_dir * 0.2 + Vector((0, -0.015, 0)), a, 0.014, r0), 0.01)
            add(sh, SPH(a, r0 * 1.08), 0.004)
            add(sh, RC(a, b, r0, r0 * 0.88), 0.002)
            add(sh, SPH(b, r0 * 0.92), 0.002)
            add(sh, RC(b, c, r0 * 0.86, r0 * 0.68), 0.002)

    # legs
    for side in ("L", "R"):
        s = 1 if side == "L" else -1
        hip, th, kn, cf, an, ft, toe = (J(f"{n}.{side}") for n in ("hip", "thigh", "knee", "calf", "ankle", "foot", "toe"))
        tl = kn - hip
        add(sh, RC(hip + Vector((0, 0.005, 0.03)), kn, 0.072 * w, 0.042 * w), 0.05)
        add(sh, E(hip + tl * 0.5 + Vector((0, -0.028, 0)), (0.052 * w, 0.045 * w * (0.8 + mu * 0.3), 0.14), frame(tl)), 0.035)
        add(sh, E(hip + tl * 0.45 + Vector((0, 0.03, 0)), (0.048 * w, 0.04 * w, 0.13), frame(tl)), 0.035)
        add(sh, E(hip + tl * 0.35 + Vector((-s * 0.03, 0, 0)), (0.035 * w, 0.04 * w, 0.12), frame(tl)), 0.03)
        add(sh, SPH(kn + Vector((0, -0.026, 0.005)), 0.019), 0.025)
        add(sh, E(kn, (0.04, 0.038, 0.04)), 0.03)
        sl = an - kn
        add(sh, RC(kn, an, 0.043 * w, 0.026 * w), 0.03)
        add(sh, E(kn + sl * 0.3 + Vector((0, 0.03, 0)), (0.04 * w, 0.04 * w, 0.1), frame(sl)), 0.03)
        add(sh, CAP(kn + Vector((0, -0.03, -0.03)), an + Vector((0, -0.012, 0.03)), 0.012), 0.02)   # shin bone ridge
        for sx in (-1, 1):
            add(sh, SPH(an + Vector((sx * 0.024, 0.0, 0.0)), 0.015), 0.012)
        heel = an + Vector((0, 0.03, -0.06))
        add(sh, E(heel, (0.032, 0.038, 0.032)), 0.025)
        mid = Vector(((an.x + toe.x) / 2, (heel.y + toe.y) / 2, 0.035))
        add(sh, RC(an + Vector((0, 0.0, -0.01)), mid, 0.034, 0.03), 0.03)
        add(sh, E(mid, (0.044, 0.105, 0.03), frame(Vector((0, -1, 0)), up=(0, 0, 1))), 0.03)
        add(sh, E(Vector((toe.x, toe.y + 0.02, 0.022)), (0.045, 0.035, 0.02)), 0.025)
        for t in range(5):
            tx = toe.x + s * (-0.025 + t * 0.013)
            tl_ = 0.035 - t * 0.004
            add(sh, CAP((tx, toe.y - 0.005, 0.015), (tx, toe.y - 0.005 - tl_, 0.012), 0.008 - t * 0.0007), 0.006)
    return sh


# ------------------------------------------------------------------ face

def face(sh, hc, opt=None, upper_face=True):
    """Sculpted head around center hc. opt keys:
    jaw (width), chin, cheek, gaunt, brow, nose_len, nose_width, lip,
    mouth_open, eye_depth, skull_back. upper_face=False leaves the upper
    head flat (the twin's clock/eye assembly replaces it)."""
    f = {"jaw": 0.85, "chin": 0.7, "cheek": 0.6, "gaunt": 0.4, "brow": 0.6, "nose_len": 1.0, "nose_width": 1.0,
         "lip": 0.7, "mouth_open": 0.0, "eye_depth": 1.0, "skull_back": 0.6, "scale": 1.0}
    f.update(opt or {})
    sc = f["scale"]
    c = Vector(hc)
    P = lambda x, y, z: c + Vector((x, y, z)) * sc
    if upper_face:
        add(sh, E(P(0, 0.012, 0.018), (0.072 * sc, 0.092 * sc, 0.094 * sc)), 0.02)
        add(sh, E(P(0, 0.04, 0.03), (0.066 * sc, 0.07 * sc * (0.8 + 0.3 * f["skull_back"]), 0.08 * sc)), 0.03)
        add(sh, E(P(0, -0.06, 0.035), (0.06 * sc, 0.03 * sc, 0.05 * sc)), 0.03)   # forehead
    else:
        add(sh, E(P(0, 0.012, -0.005), (0.07 * sc, 0.09 * sc, 0.07 * sc)), 0.02)
    jw = f["jaw"]
    add(sh, E(P(0, -0.022, -0.058), (0.058 * jw * sc, 0.068 * sc, 0.05 * sc)), 0.035)
    for s in (-1, 1):
        add(sh, SPH(P(s * 0.05 * jw, -0.005, -0.06), 0.017 * sc), 0.03)                 # jaw angle
        add(sh, E(P(s * 0.046, -0.058, -0.004), (0.024 * sc, 0.02 * sc, 0.014 * sc)), 0.016 * f["cheek"] + 0.004)
        add(sh, E(P(s * 0.038, -0.066, -0.042), (0.024 * sc, 0.016 * sc * f["cheek"] + 0.002, 0.024 * sc)), 0.02)
        if f["gaunt"] > 0.05:
            cut(sh, E(P(s * 0.052, -0.072, -0.05), (0.02 * sc, 0.01 * sc * f["gaunt"] + 0.001, 0.022 * sc)), 0.02)
        if upper_face:
            cut(sh, E(P(s * 0.033, -0.088, 0.012), (0.018 * sc, 0.02 * sc * f["eye_depth"], 0.013 * sc)), 0.009)
        # ears
        add(sh, E(P(s * 0.071, 0.008, -0.002), (0.008 * sc, 0.02 * sc, 0.029 * sc), frame((s * 0.3, 1, 0), up=(0, 0, 1))), 0.008)
        cut(sh, E(P(s * 0.078, 0.004, -0.004), (0.004 * sc, 0.011 * sc, 0.016 * sc)), 0.004)
        # nostril wings
        add(sh, SPH(P(s * 0.0115 * f["nose_width"], -0.1, -0.034), 0.0085 * sc), 0.006)
        cut(sh, SPH(P(s * 0.0065 * f["nose_width"], -0.105, -0.043), 0.0035 * sc), 0.002)
    if upper_face:
        add(sh, CAP(P(-0.044, -0.083, 0.03), P(0.044, -0.083, 0.03), 0.0115 * sc * f["brow"] + 0.004), 0.02)
    # nose
    nl = f["nose_len"]
    add(sh, RC(P(0, -0.084, 0.012 if upper_face else -0.008), P(0, -0.09 - 0.024 * nl, -0.03), 0.0088 * sc * f["nose_width"], 0.0108 * sc), 0.01)
    add(sh, E(P(0, -0.086, 0.0), (0.009 * sc, 0.008 * sc, 0.018 * sc)), 0.01)
    # chin + lips + mouth
    add(sh, E(P(0, -0.076, -0.094), (0.02 * sc * f["chin"] + 0.006, 0.014 * sc, 0.016 * sc)), 0.02)
    lp = f["lip"]
    add(sh, E(P(0, -0.092, -0.05), (0.021 * sc, 0.0085 * sc * lp + 0.003, 0.0075 * sc)), 0.006)
    add(sh, E(P(0, -0.089, -0.0625), (0.018 * sc, 0.0095 * sc * lp + 0.003, 0.0085 * sc)), 0.006)
    mo = f["mouth_open"]
    cut(sh, E(P(0, -0.098, -0.0565 - mo * 0.012), (0.021 * sc + mo * 0.004, 0.02 * sc + mo * 0.03, 0.0014 * sc + mo * 0.017)), 0.002 + mo * 0.004)
    return sh


def eye_positions(hc, sc=1.0):
    c = Vector(hc)
    return [c + Vector((s * 0.033, -0.077, 0.012)) * sc for s in (-1, 1)]
