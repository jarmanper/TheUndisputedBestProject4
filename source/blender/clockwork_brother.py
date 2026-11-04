"""The Twin, final design: the Clockwork Brother (graphics v4).

Art direction: "a freak of nature - powerful, but lost."

He is not a tall gaunt man any more. He is over-grown and assembled wrong:
a dense, low-slung mass of shoulder and back carrying a head that is far too
small for it. The silhouette is read in three strokes - a hunched yoke of
trapezius and back hump that rises *above* his own skull, one enormously
over-grown right arm whose open hand hangs past the knee, and one small,
child-sized left arm held out in a half-reach. Nothing on him is symmetric.

The power is in the mass: shoulder span, load-bearing yoke, heavy forearm and
hand, thick short legs, wide flat feet. The lost is in the carriage: the head
sunk forward and low between the shoulders, the open slack hands, the small
reaching arm with its hospital ID band still on the wrist, and the brass
yoke they bolted on him as a child that he simply grew around.

The clock motif stays and gets *bigger*, not busier: one large brass dial sunk
into the top of the skull, gauges inside real eyelids, a red lens eye on the
bridge of the nose, and a single pendulum hanging in the opened chest cavity
where his sternum should be. Fewer, larger forms; the old field of small
greebles is cut down to two thick cable looms and five big spine plates.

Exported as assets/models/characters/twin_monster.glb (same name, so every
scene that used the twin picks this up). Bone names, object naming and the
animation set (idle head_tilt eye_scan clock_spin twitch wire_vibrate
walk_slow posture_shift reveal) are unchanged.

Run: blender -b --factory-startup --python source/blender/clockwork_brother.py
     TWIN_FAST=1 ... for a coarse, quick silhouette check.
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
from patients import (clear_path, curve, fit_ring, offset_shape, on_surface,  # noqa: E402
                      ray_to_surface, sdf_grad)
from twin_monster import add_extra_bones, disc, facing, ring, twin_animations  # noqa: E402

NAME = "twin_monster"
RND = random.Random(1985)

FAST = bool(os.environ.get("TWIN_FAST"))      # coarse voxels for silhouette checks
VOX = 0.0066 if FAST else 0.0030              # body voxel size
CLOTH_VOX = 0.009 if FAST else 0.0050

BIG, SMALL = "R", "L"        # the over-grown arm and the under-grown one
GIRTH = 1.30                 # torso/limb girth, before the global scale
TARGET_HC_Z = 1.99           # head-centre height. A 1.75 m player must feel small
HEAD_S = 1.00                # head stays adult-sized on a body that did not
SCALE = [1.0]                # global scale, filled in by twin_skeleton()

X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


# ------------------------------------------------------------------ skeleton

FING = tuple(f"{f}{k}" for f in ("index", "middle", "ring", "pinky", "thumb") for k in (1, 2, 3))
ARM_ORDER = ("shoulder", "uarm", "elbow", "farm", "wrist", "hand")
LEG_ORDER = ("hip", "thigh", "knee", "calf", "ankle", "foot", "toe")


def arm(side, frm="shoulder"):
    i = ARM_ORDER.index(frm)
    return [f"{n}.{side}" for n in ARM_ORDER[i:]] + [f"{n}.{side}" for n in FING]


def leg(side, frm="hip"):
    i = LEG_ORDER.index(frm)
    return [f"{n}.{side}" for n in LEG_ORDER[i:]]


def sgn(side):
    return 1 if side == "L" else -1


def move(j, names, fn):
    for n in names:
        if n in j:
            j[n][1] = fn(j[n][1])


def turn(pivot, axis, deg):
    """Rotation of `deg` about `axis` through `pivot`."""
    M = Matrix.Rotation(math.radians(deg), 4, Vector(axis).normalized())
    pv = Vector(pivot)
    return lambda p: pv + (M @ (p - pv))


def grow(pivot, k):
    pv = Vector(pivot)
    return lambda p: pv + (p - pv) * k


def shift(d):
    d = Vector(d)
    return lambda p: p + d


def twin_skeleton():
    """A body that was never meant to exist: over-grown on one side, hunched,
    short-legged, with a head sunk low between load-bearing shoulders."""
    j = A.skeleton(arm_len=1.0, leg_len=1.0, thin=1.0, finger_len=1.1, asym=0.0, seed=19)
    J = lambda n: Vector(j[n][1])

    # --- legs: wide stance, short and heavy, knees turned slightly inward
    for side in ("L", "R"):
        s = sgn(side)
        move(j, leg(side), shift((s * 0.075, 0, 0)))
        move(j, leg(side, "thigh"), grow(J(f"hip.{side}"), 0.90))       # short legs
        # soft crouch: knee forward and inward, ankle back under the hip
        move(j, leg(side, "knee"), shift((-s * 0.022, -0.045, 0)))
        move(j, leg(side, "ankle"), shift((-s * 0.008, 0.052, 0)))
        move(j, [f"toe.{side}"], shift((-s * 0.028, -0.02, 0)))          # pigeon-toed

    # --- shoulders: a yoke, not a coat hanger
    cu = J("chest_up")
    for side in ("L", "R"):
        s = sgn(side)
        move(j, [f"clav.{side}"], shift((s * 0.095, 0.005, 0.035)))
        move(j, arm(side), shift((s * 0.172, 0.005, 0.045)))

    # --- the wrongness: one arm over-grown, the other left behind
    move(j, arm(BIG), grow(J(f"shoulder.{BIG}"), 1.26))
    move(j, arm(SMALL), grow(J(f"shoulder.{SMALL}"), 0.76))

    # the heavy arm hangs almost plumb, swung a little forward, hand open low
    sb = sgn(BIG)
    sh_b = J(f"shoulder.{BIG}")
    move(j, arm(BIG, "uarm"), turn(sh_b, Y, sb * 3))         # hangs clear of the ribs
    move(j, arm(BIG, "uarm"), turn(sh_b, X, -10))            # and slightly forward
    el_b = J(f"elbow.{BIG}")
    move(j, arm(BIG, "farm"), turn(el_b, X, -14))            # forearm hangs forward

    # the small arm half-reaches: raised in front, forearm up, palm open
    ss = sgn(SMALL)
    sh_s = J(f"shoulder.{SMALL}")
    move(j, arm(SMALL, "uarm"), turn(sh_s, X, -22))
    move(j, arm(SMALL, "uarm"), turn(sh_s, Y, ss * 26))
    el_s = J(f"elbow.{SMALL}")
    move(j, arm(SMALL, "farm"), turn(el_s, X, -78))          # forearm up, palm open
    move(j, arm(SMALL, "farm"), turn(el_s, Z, -ss * 26))     # across the body, offering
    wr_s = J(f"wrist.{SMALL}")
    move(j, [f"{n}.{SMALL}" for n in FING], turn(wr_s, X, -18))   # fingers fall open

    # --- shoulders rolled inward: mass, but also a protective hunch
    for side in ("L", "R"):
        s = sgn(side)
        move(j, [f"clav.{side}"] + arm(side), turn(cu, Z, -s * 15))

    # --- the spine sets wrong: progressive forward hunch plus a lean onto the
    #     heavy side, so even standing still he looks like he is bracing
    upper = ["spine1", "spine2", "chest", "chest_up", "neck", "neck_top"]
    upper += [f"clav.{s}" for s in ("L", "R")] + arm("L") + arm("R")
    move(j, upper, turn(J("pelvis"), X, 10))
    move(j, upper[1:], turn(J("spine2"), X, 13))
    move(j, upper, turn(J("pelvis"), Y, sgn(BIG) * 3))      # barely listing onto the heavy side
    move(j, ["neck", "neck_top"], turn(J("chest_up"), X, 9))

    # --- head centre: sunk forward, low, out of the collar of mass
    hc = J("neck_top") + Vector((0, -0.055, 0.082))

    # --- one global scale so the face lands where the reveal camera looks
    k = TARGET_HC_Z / hc.z
    SCALE[0] = k
    for v in j.values():
        v[1] = v[1] * k
    hc = hc * k
    # the SDF foot is modelled at a fixed height, so keep the ankle near it
    for side in ("L", "R"):
        drop = j[f"ankle.{side}"][1].z - 0.125
        move(j, leg(side, "ankle"), shift((0, 0, -drop)))
    return j, hc, k


# ------------------------------------------------------------------ layout

class Layout:
    def __init__(self, hc, s=1.0):
        self.s = s
        self.hc = Vector(hc)
        # the dial faces up and well forward, so it reads from in front
        self.clock_n = Vector((0, -0.80, 0.60)).normalized()
        self.clock_c = self.hc + Vector((0, 0.012, 0.076)) * s
        self.clock_r = 0.074 * s                                     # one big deliberate form
        self.lens_c = self.hc + Vector((0, -0.094, 0.022)) * s       # bridge of the nose
        self.lens_r = 0.019 * s
        self.eyes = [self.hc + Vector((sd * 0.033, -0.07, 0.008)) * s for sd in (-1, 1)]
        self.pivot_n = self.clock_n                                  # used by twin_animations
        self.top = self.hc + Vector((0, 0.015, 0.125)) * s


# ------------------------------------------------------------------ flesh

def bulk(sh, j, L):
    """The mass that makes him a boss. Every blend radius here is deliberately
    tight: the earlier pass used 0.05-0.09 everywhere and smooth-unioned the
    deltoid, the pec and the lat into one putty surface. Big forms, hard joins."""
    u = SCALE[0]
    J = lambda n: Vector(j[n][1])
    cu, ch, nk = J("chest_up"), J("chest"), J("neck")
    add, cut, E, RC, SPH, CAP = B.add, B.cut, B.E, B.RC, B.SPH, B.CAP

    # upper-back hump: a loaded mass behind and above the shoulders, so the
    # head sits in a notch rather than on top of a neck
    add(sh, E(cu + Vector((0, 0.105, 0.105)) * u, (0.205 * u, 0.125 * u, 0.125 * u)), 0.05)
    add(sh, E(cu + Vector((0, 0.055, 0.01)) * u, (0.235 * u, 0.115 * u, 0.10 * u)), 0.045)

    for side in ("L", "R"):
        s = sgn(side)
        big = side == BIG
        shp, el, wr = J(f"shoulder.{side}"), J(f"elbow.{side}"), J(f"wrist.{side}")
        # trapezius yoke: neck base out to the shoulder cap, rising to ear height
        add(sh, RC(nk + Vector((s * 0.028, 0.062, -0.012)) * u, shp + Vector((-s * 0.02, 0.025, 0.012)) * u,
                   (0.082 if big else 0.070) * u, (0.078 if big else 0.062) * u), 0.03)
        # deltoid: a distinct capped ball with a hard lower edge into the arm
        dr = (0.108 if big else 0.072) * u
        add(sh, E(shp + Vector((s * 0.014, 0.0, 0.012)) * u, (dr, dr * 0.93, dr)), 0.016)
        # pectoral slab with a defined lower border
        add(sh, E(ch + Vector((s * 0.085, -0.088, 0.055)) * u, (0.09 * u, 0.034 * u, 0.058 * u)), 0.018)
        add(sh, CAP(ch + Vector((s * 0.02, -0.115, 0.012)) * u, ch + Vector((s * 0.15, -0.07, 0.03)) * u,
                    0.014 * u), 0.009)                                   # pec border
        # lat flare down to the waist
        add(sh, E(ch + Vector((s * 0.125, 0.045, -0.05)) * u, (0.055 * u, 0.075 * u, 0.135 * u)), 0.025)
        if big:
            ua, fa = (el - shp), (wr - el)
            add(sh, E(shp + ua * 0.5, (0.075 * u, 0.075 * u, ua.length * 0.52), B.frame(ua)), 0.022)
            add(sh, E(el + Vector((0, 0.01, 0)) * u, (0.072 * u, 0.072 * u, 0.07 * u)), 0.022)
            add(sh, RC(el, wr, 0.082 * u, 0.046 * u), 0.02)              # slab forearm, wiry wrist
            add(sh, E(el + fa * 0.3, (0.086 * u, 0.074 * u, fa.length * 0.4), B.frame(fa)), 0.018)
        else:
            # the small arm stays thin: just enough that it is not a stick
            add(sh, RC(shp, el, 0.038 * u, 0.030 * u), 0.02)
            add(sh, RC(el, wr, 0.032 * u, 0.022 * u), 0.016)

    # the heavy hand: a wide slab palm with thick fingers, hanging open
    s = sgn(BIG)
    wr, hd = J(f"wrist.{BIG}"), J(f"hand.{BIG}")
    knuck = [J(f"{f}1.{BIG}") for f in ("index", "middle", "ring", "pinky")]
    kc = sum(knuck, Vector()) / 4
    hdir = kc - wr
    add(sh, B.RBOX(wr + hdir * 0.55, (0.028 * u, 0.09 * u, hdir.length * 0.62), 0.018 * u,
                   B.frame(hdir, up=(s, 0, 0))), 0.015)
    for f in ("index", "middle", "ring", "pinky", "thumb"):
        a, b, c = (J(f"{f}1.{BIG}"), J(f"{f}2.{BIG}"), J(f"{f}3.{BIG}"))
        r0 = (0.0165 if f != "thumb" else 0.019) * u
        add(sh, SPH(a, r0 * 1.12), 0.004)                                # knuckles stand proud
        add(sh, RC(a, b, r0, r0 * 0.86), 0.003)
        add(sh, RC(b, c, r0 * 0.84, r0 * 0.62), 0.003)

    # Legs. They carry a top-heavy body on starved muscle, so they get the same
    # treatment as the arms: masses with a direction and a border, bone where
    # bone belongs. Every offset is scaled off `g`, the leg's own girth, so the
    # landmarks keep touching the limb instead of floating off it as a pad -
    # which is exactly how the knees turned into doll joints last pass.
    for side in ("L", "R"):
        s = sgn(side)
        g = (0.82 if side == BIG else 0.68) * u   # starved legs under an over-grown torso
        hip, kn, an, toe = J(f"hip.{side}"), J(f"knee.{side}"), J(f"ankle.{side}"), J(f"toe.{side}")
        tl, sl = kn - hip, an - kn
        FW, BK, OUT = Vector((0, -1, 0)), Vector((0, 1, 0)), Vector((s, 0, 0))
        UP = Vector((0, 0, 1))
        # thigh shaft
        add(sh, E(hip + tl * 0.2, (0.112 * g, 0.108 * g, tl.length * 0.38), B.frame(tl)), 0.03)
        add(sh, E(hip + tl * 0.55, (0.096 * g, 0.092 * g, tl.length * 0.52), B.frame(tl)), 0.03)
        add(sh, E(hip + tl * 0.88, (0.078 * g, 0.076 * g, tl.length * 0.28), B.frame(tl)), 0.022)
        # quadriceps, with a border that stops above the knee
        add(sh, E(hip + tl * 0.5 + FW * 0.042 * g, (0.062 * g, 0.046 * g, tl.length * 0.40),
                  B.frame(tl)), 0.016)
        # vastus medialis: the teardrop above the inner knee. One of the few
        # shapes that instantly says "leg" rather than "tube".
        add(sh, E(hip + tl * 0.86 + FW * 0.034 * g - OUT * 0.040 * g,
                  (0.038 * g, 0.032 * g, 0.052 * g)), 0.010)
        # hamstring mass and the hollow behind the knee
        add(sh, E(hip + tl * 0.5 + BK * 0.045 * g, (0.058 * g, 0.048 * g, tl.length * 0.42),
                  B.frame(tl)), 0.018)
        cut(sh, E(kn + BK * 0.072 * g, (0.048 * g, 0.034 * g, 0.05 * g)), 0.018)
        # a long diagonal across the thigh, so it has a direction line
        add(sh, CAP(hip + OUT * 0.058 * g + FW * 0.022 * g,
                    kn - OUT * 0.044 * g + FW * 0.030 * g, 0.010 * g), 0.012)
        # knee: condyles at the back, a FLUSH patella at the front with a hollow
        # either side of it, and the tendon running down to the tuberosity
        add(sh, E(kn + Vector((0, -0.008, 0)) * u, (0.072 * g, 0.070 * g, 0.060 * g)), 0.024)
        for sx in (-1, 1):
            add(sh, SPH(kn + OUT * (sx * 0.038 * g) + BK * 0.012 * g, 0.030 * g), 0.016)
            cut(sh, E(kn + FW * 0.052 * g + OUT * (sx * 0.044 * g),
                      (0.020 * g, 0.022 * g, 0.044 * g)), 0.012)
        add(sh, E(kn + FW * 0.050 * g + UP * 0.010 * g, (0.034 * g, 0.020 * g, 0.040 * g)), 0.020)
        add(sh, CAP(kn + FW * 0.054 * g - UP * 0.022 * g, kn + FW * 0.050 * g - UP * 0.070 * g,
                    0.012 * g), 0.007)
        add(sh, SPH(kn + FW * 0.048 * g - UP * 0.082 * g, 0.016 * g), 0.008)     # tibial tuberosity
        # calf: two gastrocnemius heads tapering hard into the achilles
        add(sh, E(kn + sl * 0.22, (0.088 * g, 0.090 * g, sl.length * 0.34), B.frame(sl)), 0.022)
        for sx in (-1, 1):
            add(sh, E(kn + sl * 0.26 + BK * 0.030 * g + OUT * (sx * 0.026 * g),
                      (0.040 * g, 0.042 * g, sl.length * 0.26), B.frame(sl)), 0.014)
        add(sh, E(kn + sl * 0.78, (0.046 * g, 0.046 * g, sl.length * 0.3), B.frame(sl)), 0.014)
        add(sh, CAP(kn + sl * 0.58 + BK * 0.030 * g, an + BK * 0.028 * g, 0.016 * g), 0.010)  # achilles
        # tibial crest: a hard edge all the way down the front of the shin
        add(sh, CAP(kn + FW * 0.046 * g - UP * 0.085 * g, an + FW * 0.030 * g + UP * 0.03 * u,
                    0.011 * g), 0.005)
        for sx in (-1, 1):                                                   # malleoli
            add(sh, SPH(an + Vector((sx * 0.040 * u, 0.004 * u, 0.012 * u)), 0.020 * u), 0.006)
        # foot: a bony instep, not a slipper
        fg = 0.92 * u
        add(sh, E(an + Vector((0, 0.012, -0.05)) * u, (0.054 * fg, 0.068 * fg, 0.052 * fg)), 0.022)
        add(sh, E(an + Vector((0, 0.052, -0.072)) * u, (0.046 * fg, 0.044 * fg, 0.038 * fg)), 0.018)  # calcaneus
        mid = Vector(((an.x + toe.x) * 0.5, (an.y + toe.y) * 0.5 - 0.005 * u, 0.034 * u))
        add(sh, E(mid, (0.066 * fg, 0.112 * fg, 0.030 * fg)), 0.022)
        add(sh, E(Vector((toe.x, toe.y + 0.014 * u, 0.030 * u)), (0.062 * fg, 0.034 * fg, 0.026 * fg)), 0.018)
        for t in range(5):
            tx = toe.x + s * (-0.044 + t * 0.023) * u
            ln = (0.055 - t * 0.007) * u
            w = (0.0150 - t * 0.0016) * u
            # extensor tendon running up the instep to each toe
            add(sh, CAP((tx * 0.55 + an.x * 0.45, an.y + 0.012 * u, 0.050 * u),
                        (tx, toe.y - 0.004 * u, 0.030 * u), 0.0055 * u), 0.006)
            add(sh, SPH((tx, toe.y - 0.006 * u, 0.026 * u), w * 1.05), 0.005)   # metatarsal head
            # toes: flattened, not sausages
            add(sh, E(Vector((tx, toe.y - 0.012 * u - ln * 0.5, 0.020 * u)),
                      (w, ln * 0.55, w * 0.72)), 0.005)
    # pelvis / waist: narrow enough that the shoulders read as enormous
    add(sh, E(J("pelvis") + Vector((0, 0.01, -0.02)) * u, (0.125 * u, 0.095 * u, 0.10 * u)), 0.03)

    # a starved ribcage still showing through the grown-on muscle: the two
    # halves of him disagree about what he is. Sharp, shallow, tightly blended.
    for i in range(6):
        z = ch.z + (0.095 - i * 0.045) * u
        for s in (-1, 1):
            pts = []
            for a in np.linspace(0.12, 1.32, 8):
                pts.append(Vector((ch.x + math.sin(a) * 0.172 * s * u,
                                   ch.y + (-math.cos(a) * 0.126 + 0.012) * u,
                                   z - 0.058 * (a ** 1.6) * u)))
            for a_, b_ in zip(pts, pts[1:]):
                add(sh, CAP(a_, b_, 0.0115 * u), 0.009)
    # short thick neck, swallowed by the yoke
    add(sh, RC(nk + Vector((0, 0.01, -0.02)) * u, J("neck_top"), 0.072 * u, 0.054 * u), 0.03)


def landmarks(sh, j):
    """Hard structure under tension. The previous pass had no sharp edge
    anywhere on him, so all that mass read as fat. These are bone and tendon,
    added with a tight blend radius so they stay crisp instead of melting into
    the muscle: clavicle, acromion, scapula and its spine, neck cords, elbow
    point, ulnar ridge, iliac crest, sternum. The leg landmarks live in
    bulk(), where the leg girth is in scope to scale them."""
    u = SCALE[0]
    J = lambda n: Vector(j[n][1])
    add, E, RC, SPH, CAP, RBOX = B.add, B.E, B.RC, B.SPH, B.CAP, B.RBOX
    cu, ch, nk, nt, pel = J("chest_up"), J("chest"), J("neck"), J("neck_top"), J("pelvis")
    for side in ("L", "R"):
        s = sgn(side)
        big = side == BIG
        shp, el, wr = J(f"shoulder.{side}"), J(f"elbow.{side}"), J(f"wrist.{side}")
        # clavicle: a hard bar cutting across the top of the chest
        add(sh, CAP(cu + Vector((s * 0.022, -0.105, 0.052)) * u, shp + Vector((-s * 0.03, -0.035, 0.035)) * u,
                    0.015 * u), 0.005)
        add(sh, SPH(shp + Vector((s * 0.045, -0.005, 0.05)) * u, 0.026 * u), 0.008)      # acromion
        # scapula: a flat plate standing proud of the back, with its ridge
        add(sh, RBOX(cu + Vector((s * 0.125, 0.10, -0.05)) * u, (0.062 * u, 0.018 * u, 0.095 * u), 0.012 * u,
                     B.frame((s * 0.42, 1, 0.12))), 0.012)
        add(sh, CAP(cu + Vector((s * 0.05, 0.125, 0.012)) * u, cu + Vector((s * 0.18, 0.095, -0.025)) * u,
                    0.013 * u), 0.006)
        # sternocleidomastoid: two cords standing out of a thick neck
        add(sh, CAP(nt + Vector((s * 0.055, 0.015, -0.01)) * u, cu + Vector((s * 0.018, -0.085, 0.055)) * u,
                    0.016 * u), 0.010)
        add(sh, SPH(el + Vector((0, 0.05, 0)) * u, (0.024 if big else 0.017) * u), 0.007)  # olecranon
        add(sh, CAP(el + Vector((s * 0.03, 0.045, -0.01)) * u, wr + Vector((s * 0.012, 0.028, 0.0)) * u,
                    (0.016 if big else 0.010) * u), 0.012)                                  # ulnar ridge
        add(sh, CAP(pel + Vector((s * 0.055, -0.075, 0.055)) * u, pel + Vector((s * 0.14, 0.05, 0.035)) * u,
                    0.014 * u), 0.009)                                                      # iliac crest
    # sternum ridge above the chest cavity and the xiphoid below it
    add(sh, CAP(cu + Vector((0, -0.11, 0.0)) * u, ch + Vector((0, -0.125, 0.05)) * u, 0.016 * u), 0.008)
    add(sh, CAP(ch + Vector((0, -0.12, -0.115)) * u, ch + Vector((0, -0.10, -0.175)) * u, 0.013 * u), 0.010)


def wrongness(sh, L):
    """Skin pulled tight. The old pass added fat low-frequency lumps, which is
    exactly what made him putty; this one only carves - a creased sinew field
    plus a fine grain - so the structure underneath stays legible."""
    hc = np.array(tuple(L.hc), np.float32)

    def d(p):
        r = np.linalg.norm(p - hc, axis=1)
        w = np.clip((r - 0.19) / 0.16, 0.0, 1.0)
        n1 = S.value_noise3(p * np.array([1, 1, 0.55], np.float32), 6.5, seed=21)
        n2 = S.value_noise3(p, 24.0, seed=22)
        crease = np.maximum(0.0, 0.2 - np.abs(n1)) / 0.2
        return w * (0.008 * crease + 0.0018 * n2)
    sh.displace(d)


def skull_face(sh, L):
    """A drawn, starved head with the skull showing through. The previous pass
    left the cheeks full and the eyes wide, which is most of why he read as a
    doll. Orbits are cut deep so the eyes sit in shadow and catch almost no
    light, and the lids are nearly shut."""
    s = L.s
    hc = L.hc
    P = lambda x, y, z: hc + Vector((x, y, z)) * s
    H.head(sh, hc, {"scale": HEAD_S, "skull": 0.98, "gaunt": 1.0, "cheekbone": 1.0,
                    "brow": 1.0, "nose_bridge": 1.0, "eye_open": 0.18, "jaw": 0.9,
                    "chin": 0.42, "lips": 0.28, "nose_len": 1.0, "nose_width": 0.86,
                    "ear": 0.0})
    for sd in (-1, 1):
        # deep orbits: the eye sits back in a socket, not on the surface
        B.cut(sh, B.E(P(sd * 0.032, -0.038, 0.009), (0.025, 0.023, 0.021)), 0.006)
        B.cut(sh, B.E(P(sd * 0.0755, -0.028, 0.022), (0.016, 0.034, 0.03)), 0.014)   # temporal hollow
        B.cut(sh, B.E(P(sd * 0.047, -0.062, -0.052), (0.021, 0.015, 0.027)), 0.012)  # hollow under the cheekbone
        B.cut(sh, B.E(P(sd * 0.026, -0.082, -0.028), (0.009, 0.01, 0.014)), 0.008)   # drawn nasolabial
    B.cut(sh, B.E(P(0, -0.082, 0.028), (0.009, 0.012, 0.012)), 0.006)                # glabella notch
    B.add(sh, B.CAP(P(-0.03, -0.072, -0.085), P(0.03, -0.072, -0.085), 0.009), 0.008)  # jaw edge
    # --- asymmetry. Straight on he was reading placid; a face that does not
    # match itself reads as something that went wrong, and the dragged side
    # does the "lost" work that a symmetrical face cannot.
    B.cut(sh, B.E(P(0.031, -0.074, 0.031), (0.021, 0.013, 0.011)), 0.009)            # that brow sits lower
    B.add(sh, B.CAP(P(-0.047, -0.077, 0.031), P(-0.013, -0.082, 0.033), 0.010), 0.008)  # the other is heavier
    B.cut(sh, B.E(P(0.030, -0.073, -0.008), (0.014, 0.009, 0.005)), 0.004)           # lid sags on one side
    B.cut(sh, B.E(P(0.049, -0.060, -0.030), (0.016, 0.012, 0.020)), 0.012)           # cheek drawn in
    B.cut(sh, B.SPH(P(-0.024, -0.084, -0.067), 0.008), 0.006)                        # mouth corner dragged down
    B.add(sh, B.CAP(P(-0.019, -0.085, -0.057), P(-0.027, -0.080, -0.071), 0.0045), 0.005)


def flesh_shape(j, L):
    sh = B.body_shape(j, {"w": GIRTH * SCALE[0], "emaciated": 0.62, "muscle": 1.0})
    bulk(sh, j, L)
    landmarks(sh, j)
    wrongness(sh, L)                      # before the head, so the face stays clean
    skull_face(sh, L)
    s = L.s
    n = L.clock_n
    # Clock seat: the bore through the skin is NARROWER than the dial behind
    # it, so bone overhangs the rim and the clock reads as grown into the
    # cranium instead of perched on it like a hat.
    B.cut(sh, B.CAP(L.clock_c - n * 0.05, L.clock_c + n * 0.075, L.clock_r - 0.008), 0.003)
    # lens socket in the bridge of the nose, recessed
    B.cut(sh, B.CAP(L.lens_c - Vector((0, 0.012, 0)), L.lens_c + Vector((0, 0.05, 0)), L.lens_r * 0.82), 0.003)
    # temple ports where the two looms enter
    for sd in (-1, 1):
        B.cut(sh, B.SPH(L.hc + Vector((sd * 0.069, 0.012, 0.03)) * s, 0.011 * s), 0.003)
    # the chest cavity: the sternum is gone and a clock hangs in the hole.
    # Anchored on the real sternum surface, so the opening is always open.
    heart = heart_c(j, sh)
    B.cut(sh, B.CAP(heart + HEART_N * 0.05, heart - HEART_N * 0.19, 0.09 * SCALE[0]), 0.010)
    return sh, heart


HEART_N = Vector((0, -1, 0.10)).normalized()      # outward normal of the chest


_HEART = {}


def heart_c(j, shape=None):
    """Surface point on the sternum, cached so the hardware and the hole agree."""
    if "p" in _HEART:
        return _HEART["p"]
    ch = Vector(j["chest"][1])
    start = ch + Vector((0, -0.55, 0.02))
    hit = ray_to_surface(shape, start, (0, 1, 0), 0.0, 0.75) if shape is not None else None
    _HEART["p"] = hit if hit is not None else ch + Vector((0, -0.13, 0.02))
    return _HEART["p"]


def assign_body_materials(ob, L, j):
    """Four skins on one body, so the wrongness reads without extra geometry:
    his brother's real face, porcelain above the crack line, institutional
    pallor over the body, and raw over-grown tissue on the parts of him that
    kept growing (the heavy arm, the shoulder yoke and the back)."""
    me = ob.data
    me.materials.clear()
    for m in ("twin_skin_face", "twin_skin_jaw", "twin_porcelain",
              "twin_flesh", "twin_flesh_grown", "twin_bruise"):  # 0..5
        me.materials.append(T.mat(m))
    hc, s = L.hc, L.s
    J = lambda n: Vector(j[n][1])
    shp_b, el_b, hd_b = J(f"shoulder.{BIG}"), J(f"elbow.{BIG}"), J(f"hand.{BIG}")
    cu, ch = J("chest_up"), J("chest")
    yoke = cu + Vector((0, 0.07, 0.07))
    heart = heart_c(j)
    pts = np.array([tuple(ob.matrix_world @ p.center) for p in me.polygons], np.float32)
    nz = S.value_noise3(pts, 9.0, seed=31)
    bz = S.value_noise3(pts * np.array([1, 1, 0.5], np.float32), 4.0, seed=33)
    for poly, cc, n, bn in zip(me.polygons, pts, nz, bz):
        c = Vector(cc)
        d = c - hc
        if d.length < 0.175 * s and c.z > hc.z - 0.135 * s:
            ang = math.atan2(d.x, -d.y)
            crack_z = (0.028 + 0.013 * math.sin(ang * 5.0) + 0.006 * math.sin(ang * 13.0 + 1.0)) * s
            poly.material_index = 2 if d.z > crack_z else (1 if d.z < -0.035 * s and d.y < 0.03 * s else 0)
            continue
        # congested and bruised where the body is strained or shut away from
        # light: the rim of the chest cavity, the loaded back, the deep folds
        rim = abs((c - heart).length - 0.115 * SCALE[0]) < 0.055
        back = c.y > cu.y + 0.12 and c.z > ch.z - 0.1
        if min((c - L.eyes[0]).length, (c - L.eyes[1]).length) < 0.032 * s:
            poly.material_index = 5                          # socket walls in shadow
            continue
        low = c.z < J("hip." + BIG).z - 0.22 * SCALE[0]      # blood pooled in the legs
        if low and bn > -0.45:
            poly.material_index = 5
            continue
        if (rim or back) and bn > 0.35:
            poly.material_index = 5
            continue
        # the whole heavy side is over-grown tissue; the boundary wanders down
        # his midline like a seam, so he reads as two bodies joined badly
        seam = 0.02 + 0.075 * (n - 0.5) + 0.05 * math.sin(c.z * 3.6)
        over = c.x * sgn(BIG) > seam
        over = over or min(near_d(c, shp_b, el_b), near_d(c, el_b, hd_b)) < 0.18 + 0.05 * n
        over = over or (c - yoke).length < 0.22 + 0.05 * n
        poly.material_index = 4 if over else 3


def near_d(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def crack_seam(shape, L, parts):
    """Dark fissures along the line where skin becomes porcelain."""
    s = L.s
    pts = []
    for k in range(48):
        ang = -math.pi + k / 47 * 2 * math.pi
        z = (0.028 + 0.013 * math.sin(ang * 5.0) + 0.006 * math.sin(ang * 13.0 + 1.0)) * s
        p = L.hc + Vector((math.sin(ang) * 0.09 * s, -math.cos(ang) * 0.11 * s, z))
        pts.append(on_surface(shape, p, 0.0013))
    parts.append((T.tube("seam", [tuple(p) for p in pts], 0.0009, "black_cavity", 5), "SKIN"))
    for k in range(7):                      # a few branching cracks up into the porcelain
        i = RND.randrange(len(pts))
        a = pts[i]
        b = on_surface(shape, a + Vector((RND.uniform(-0.012, 0.012), 0, RND.uniform(0.012, 0.03))), 0.0003)
        parts.append((T.tube("crack", [tuple(a), tuple(b)], 0.0007, "black_cavity", 4), "SKIN"))


# ------------------------------------------------------------------ hardware

def clock(L, parts, bones):
    """One dial, set INTO the cranium. The dial and its bezel sit below the
    bone line and the skull bore is narrower than they are, so the skull
    overhangs the rim. Nothing stands proud: a clock perched on top with a
    visible brim read as a costume."""
    c, n, R = L.clock_c, L.clock_n, L.clock_r
    rot = facing(n)
    parts.append((disc("dial_well", c - n * 0.052, R, 0.055, "black_cavity", rot, 64), "INSET:head"))
    parts.append((disc("dial", c - n * 0.026, R - 0.001, 0.008, "porcelain", rot, 96, planar=True), "INSET:head"))
    parts.append((ring("bezel", c - n * 0.020, R - 0.003, 0.0075, "brass", rot, 128, 12), "INSET:head"))
    q = rot.to_quaternion()
    parts.append((disc("glass", c - n * 0.012, R - 0.006, 0.002, "glass", rot, 64), "INSET:head"))
    hub = c - n * 0.021
    bones["clock_hour"] = (hub, hub + n * 0.03)
    bones["clock_minute"] = (hub, hub + n * 0.035)
    up = q @ Vector((0, 1, 0))
    for name, length, w, bone in (("hour_hand", R * 0.56, 0.0062, "clock_hour"),
                                  ("minute_hand", R * 0.86, 0.0040, "clock_minute")):
        parts.append((T.box(name, (w, length + 0.012, 0.0018), tuple(hub + up * (length / 2 - 0.006)),
                            "light_red", rot=tuple(rot), uv=False), bone))   # glowing red hands
    parts.append((T.cyl("hub_pin", 0.005, 0.007, tuple(hub + n * 0.002), "brass", rot=tuple(rot), seg=12),
                  "INSET:head"))


def eyes_and_lens(L, parts, bones, lights):
    """Two dim embers deep in the orbits and one red lens in the nose bridge.
    The old gauge faces were pale discs sitting on the surface with a visible
    white ring - the single most doll-like thing on him. There is no sclera
    anywhere now; the sockets are dark and only the ring glows."""
    s = L.s
    er = H.EYE_R * s
    for side, ec in zip(("R", "L"), L.eyes):
        n = Vector((0.15 * (-1 if side == "R" else 1), -1, 0.05)).normalized()
        rot = facing(n)
        deep = ec - n * 0.022                      # well back inside the socket
        hot = side == "R"      # twin duality: one socket burns amber, its twin cold cyan
        # a flat dark disc set well back down the socket. A sphere here caught
        # a broad specular and read as a glossy lens no matter how deep it went;
        # a flat face takes the light evenly and stays a hole.
        parts.append((disc("orbit_void", deep - n * 0.042, er * 1.35, 0.05, "black_cavity", rot, 32),
                      "INSET:head"))
        bname = f"gauge_needle.{side}"
        bones[bname] = (deep, deep + n * 0.02)
        upv = rot.to_quaternion() @ Vector((0, 1, 0))
        parts.append((T.box("needle", (0.0008, er * 0.3, 0.0005), tuple(deep - n * 0.004 + upv * er * 0.1),
                            "black_cavity", rot=tuple(rot), uv=False), bname))
        # the only thing in the socket is light: in engine the holes glow from
        # the inside, with nothing there to read as an eyeball
        lights.append(("gauge", deep + n * 0.012, {"energy": 0.35, "range": 0.7,
                                                   "color": [1.0, 0.5, 0.12] if hot else [0.25, 0.8, 1.0],
                                                   "pulse": 0.6}))
    # lens eye in the bridge of the nose, set below the skin line
    c, r = L.lens_c, L.lens_r
    n = Vector((0, -1, 0.15)).normalized()
    rot = facing(n)
    # a small bore, not a ball: a black sphere this far forward was catching a
    # specular and reading as a dark lens stuck on the bridge of his nose
    parts.append((disc("lens_socket", c - n * 0.034, r * 0.8, 0.04, "black_cavity", rot, 28), "INSET:head"))
    bones["eye"] = (c - n * 0.020, c + n * 0.02)
    pupil = T.sphere("lens_pupil", 0.0072, tuple(c - n * 0.016), "eye_glow", 16, 10, scale=(1, 1, 0.6))
    pupil.rotation_euler = rot
    parts.append((pupil, "eye"))
    lights.append(("eye", c + n * 0.04, {"energy": 0.6, "range": 1.6, "color": [1.0, 0.25, 0.06], "flicker": 0.05}))


def heart_clock(j, parts, lights):
    """One pendulum hanging in the opened chest, framed in brass. The second
    big clock form on him, and the only one that is still: a stopped heart."""
    u = SCALE[0]
    c, n = heart_c(j), HEART_N
    rot = facing(n)
    parts.append((disc("heart_well", c - n * 0.11, 0.088 * u, 0.19, "black_cavity", rot, 48), "INSET:chest"))
    parts.append((ring("heart_bezel", c + n * 0.012, 0.094 * u, 0.016 * u, "brass", rot, 72, 10), "chest"))
    parts.append((ring("heart_flange", c - n * 0.014, 0.112 * u, 0.008 * u, "copper", rot, 72, 8), "chest"))
    top = c - n * 0.05 + Vector((0, 0, 0.075 * u))
    bob = c - n * 0.032 + Vector((0.032 * u, 0, -0.040 * u))   # caught mid-swing, never moving again
    parts.append((T.tube("pendulum_rod", [tuple(top), tuple(bob)], 0.006 * u, "brass", 8), "chest"))
    parts.append((disc("pendulum_bob", bob, 0.044 * u, 0.012 * u, "gold", rot, 40, planar=True), "chest"))
    parts.append((T.cyl("heart_pin", 0.010 * u, 0.018 * u, tuple(top), "steel", rot=tuple(rot), seg=12), "chest"))
    lights.append(("heart", c + n * 0.03, {"energy": 0.35, "range": 1.1, "color": [1.0, 0.42, 0.12], "pulse": 0.35}))


def id_band(j, shape, parts):
    """The hospital band they put on him as a child, still on the small wrist
    and long since grown into the skin. The only soft thing on him."""
    wr = Vector(j[f"wrist.{SMALL}"][1])
    el = Vector(j[f"elbow.{SMALL}"][1])
    axis = (wr - el).normalized()
    p = wr - axis * 0.02
    r = fit_ring(shape, p, axis, 0.0015) if not FAST else 0.033
    parts.append((T.torus("id_band", r, 0.0065 * SCALE[0], tuple(p), "id_band", rot=tuple(facing(axis)), seg=32, rseg=6), "SKIN"))


def looms(shape, L, j, parts, bones):
    """Two thick cable looms (4 lanes each) from the clock housing and one
    temple, down the back of the neck into the spine harness. Fewer and
    heavier than before: they have to read at twenty metres, not up close."""
    s = L.s
    nk, cu = Vector(j["neck"][1]), Vector(j["chest_up"][1])
    harness_top = on_surface(shape, cu + Vector((0, 0.16, 0.10)), 0.012) if not FAST else cu + Vector((0, 0.2, 0.10))
    starts = [
        ("wires.0", L.clock_c + L.clock_n * -0.012 + Vector((0, 0.055, 0.02)) * s, Vector((0.0, 1, 0.1))),
        ("wires.1", L.hc + Vector((-0.07, 0.012, 0.03)) * s, Vector((-1, 0.35, 0))),
    ]
    for bone, a, out in starts:
        bones[bone] = (a, a + out.normalized() * 0.05)
    bones["wires.2"] = (L.hc + Vector((0.07, 0.012, 0.03)) * s, L.hc + Vector((0.12, 0.05, 0.03)) * s)
    bones["wires.3"] = (harness_top, harness_top + Vector((0, 0.05, 0)))
    mats = ["wire_black", "wire_red", "wire_copper", "rubber"]
    for li, (bone, a, out) in enumerate(starts):
        out = out.normalized()
        back = L.hc + Vector((out.x * 0.055, 0.115, -0.02) ) * s
        neck_b = nk + Vector((out.x * 0.03, 0.10, 0.05))
        if not FAST:
            neck_b = on_surface(shape, neck_b, 0.024)
        centre = [a + out * 0.008, a + out * 0.032 + Vector((0, 0.022, 0.012)), back, neck_b,
                  harness_top + Vector(((li - 0.5) * 0.055, 0.0, 0.02))]
        centre = [Vector(p) for p in curve(centre, 26)]
        if not FAST:
            centre = [Vector(p) for p in clear_path(shape, [tuple(p) for p in centre], 0.032)]
        for lane in range(4):
            ang = lane / 4 * 2 * math.pi
            lane_pts = []
            for i, p in enumerate(centre):
                t = (centre[min(i + 1, len(centre) - 1)] - centre[max(i - 1, 0)]).normalized()
                ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                u = t.cross(ref).normalized()
                v = t.cross(u)
                spread = 0.0085 * min(1.0, i / 4.0)
                lane_pts.append(p + (u * math.cos(ang) + v * math.sin(ang)) * spread)
            if not FAST:
                lane_pts = clear_path(shape, [tuple(p) for p in lane_pts], 0.005)
            parts.append((T.tube("loom_cable", [tuple(p) for p in lane_pts], 0.0033 * SCALE[0], mats[lane], 6), "SKIN"))
        port = T.cyl("loom_port", 0.013, 0.014, tuple(a), "brass", rot=tuple(facing(out)), seg=14)
        parts.append((port, "INSET:head"))


def spine_harness(shape, j, parts, lights):
    """Five big brass vertebral plates climbing the hump. Large forms, not a
    field of greebles."""
    u = SCALE[0]
    prev = None
    zs = [Vector(j[b][1]).z for b in ("spine1", "spine2", "chest", "chest_up")]
    heights = [zs[0] + 0.04 * u, zs[1] + 0.03 * u, zs[2] + 0.02 * u, zs[3] + 0.02 * u, zs[3] + 0.12 * u]
    for k, z in enumerate(heights):
        guess = Vector((0, 0.22 * u, z))
        if FAST:
            p, n = guess, Vector((0, 1, 0))
        else:
            p = on_surface(shape, guess, 0.009)
            _, n = sdf_grad(shape, np.array(tuple(p), np.float32))
        w = (0.092 - 0.006 * k) * u
        parts.append((T.box("vert_plate", (w, 0.058 * u, 0.02 * u), tuple(p), "brass",
                            rot=tuple(facing(n)), bevel=0.004), "SKIN"))
        if prev is not None:
            parts.append((T.tube("vert_link", [tuple(prev), tuple(p + n * 0.012)], 0.006 * u, "steel", 6), "SKIN"))
        prev = p + n * 0.012
    lights.append(("tower", prev + Vector((0, 0.05, 0)), {"energy": 0.25, "range": 1.0,
                                                          "color": [1.0, 0.4, 0.12], "pulse": 0.4}))


def neck_brass(j, shape, parts):
    """The brass yoke they bolted on him when he was small. It never came off;
    he grew around it. One heavy horizontal form across the top of the
    silhouette, and the anchor the looms and the spine plates run to."""
    nk, nt = Vector(j["neck"][1]), Vector(j["neck_top"][1])
    axis = (nt - nk).normalized()
    p = nk + axis * 0.022
    u = SCALE[0]
    r = fit_ring(shape, p, axis, 0.004) if not FAST else 0.1
    parts.append((T.torus("collar", r, 0.030 * u, tuple(p), "brass", rot=tuple(facing(axis)), seg=48, rseg=10), "SKIN"))
    parts.append((T.torus("collar_lip", r + 0.016 * u, 0.010 * u, tuple(p - axis * 0.03 * u), "copper",
                          rot=tuple(facing(axis)), seg=48, rseg=8), "SKIN"))


# ------------------------------------------------------------------ clothing

def near(p, a, b, r):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length < r


def trousers(j, body_shape):
    """Subject trousers and nothing else. Every earlier version put a lab coat
    on him and every one of them softened the mass it was supposed to frame;
    bare is stronger, and it leaves the chest, the ribs and the brass spine
    doing the talking."""
    J = lambda n: Vector(j[n][1])
    pel = J("pelvis")
    # subject trousers, split at the seams, worn low under the belly
    pants = offset_shape(body_shape, 0.026)

    def creases(q):
        ang = np.arctan2(q[:, 1], q[:, 0])
        n1 = S.value_noise3(q * np.array([1, 1, 0.18], np.float32), 9.0, seed=11)
        return -(0.014 * np.sin(ang * 6 + n1 * 2.8) + 0.005 * S.value_noise3(q, 18.0, 13))
    pants.displace(creases)
    p_ob = S.mesh_from_sdf(NAME + "_pants", pants, (-0.58, -0.46, 0.08), (0.58, 0.46, 1.32), CLOTH_VOX,
                           "twin_trouser", decimate=0.3, smooth_iter=1)
    # only the hands actually touch the trouser surface; using the whole arm
    # here was shaving the fabric off the thighs
    hands = [(J(f"wrist.{sd}"), J(f"hand.{sd}") + (J(f"hand.{sd}") - J(f"wrist.{sd}")) * 3.0)
             for sd in ("L", "R")]
    bm = bmesh.new()
    bm.from_mesh(p_ob.data)
    pts = np.array([tuple(p_ob.matrix_world @ f.calc_center_median()) for f in bm.faces], np.float32)
    rag = S.value_noise3(pts * np.array([1, 1, 0.3], np.float32), 7.0, seed=15)
    cut_z = J("ankle.L").z + 0.05
    kn_z = J("knee.L").z
    kill = []
    sb = sgn(BIG)
    for f, c, rg in zip(bm.faces, pts, rag):
        c = Vector(c)
        shred = rg > 0.52 and c.z < kn_z
        # the heavy leg's trouser is gone from mid-shin down, so the tibial
        # crest, the calf and the achilles are out where they can be seen
        hem = cut_z + 0.13 * rg + (0.30 * SCALE[0] if c.x * sb > 0.0 else 0.0)
        if (c.z > pel.z + 0.10 or c.z < hem or shred
                or any(near(c, a, b, 0.06) for a, b in hands)):
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(p_ob.data)
    bm.free()
    sol = p_ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.005
    sol.offset = 1.0
    T.apply_all([p_ob])
    return p_ob


# ------------------------------------------------------------------ build

def build():
    T.reset()
    j, hc, k = twin_skeleton()
    L = Layout(hc, HEAD_S)
    print(f"twin: scale {k:.3f}, head centre z {hc.z:.3f}, "
          f"shoulder span {abs(j['shoulder.L'][1].x - j['shoulder.R'][1].x):.3f}")
    sh, heart = flesh_shape(j, L)
    print(f"twin: chest cavity at {tuple(round(v, 3) for v in heart)}")
    body = S.mesh_from_sdf(NAME + "_body", sh, (-1.02, -0.70, -0.03), (1.02, 0.50, 2.24), VOX,
                           "twin_flesh", decimate=0.2, smooth_iter=1)
    assign_body_materials(body, L, j)
    parts, bones, lights = [], {}, []
    clock(L, parts, bones)
    eyes_and_lens(L, parts, bones, lights)
    heart_clock(j, parts, lights)
    looms(sh, L, j, parts, bones)
    spine_harness(sh, j, parts, lights)
    neck_brass(j, sh, parts)
    id_band(j, sh, parts)
    crack_seam(sh, L, parts)
    pants = trousers(j, sh)
    arm_ob = A.rig(NAME + "_rig", j, L.top)
    add_extra_bones(arm_ob, bones)
    head_rule = [(lambda p: (p - hc).length < 0.155, "head")]
    A.skin_to(body, arm_ob, overrides=head_rule, parent=False, bone_filter=lambda n: n not in bones)
    soft = [ob for ob, bone in parts if bone == "SKIN"]
    for m in [pants] + soft:
        A.copy_weights(body, m)
    flesh = T.join([body, pants] + soft, NAME + "_flesh")
    flesh.parent = arm_ob
    flesh.matrix_parent_inverse = arm_ob.matrix_world.inverted()
    flesh.modifiers.new("armature", "ARMATURE").object = arm_ob
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
        A.attach_to_bone(joined, arm_ob, bone)
        rigid.append(joined)
    for i, (kind, pos, props) in enumerate(lights):
        e = T.empty(f"L__{kind}__{i}", tuple(pos), props=props)
        A.attach_to_bone(e, arm_ob, {"eye": "eye", "tower": "chest_up", "heart": "chest"}.get(kind, "head"))
        rigid.append(e)
    anim = A.Animator(arm_ob)
    twin_animations(anim, L, contort=0.3)
    T.save_blend(f"source/blender/characters/{NAME}.blend")
    T.export_glb(f"assets/models/characters/{NAME}.glb", [arm_ob, flesh] + rigid, animations=True)


if __name__ == "__main__":
    build()
