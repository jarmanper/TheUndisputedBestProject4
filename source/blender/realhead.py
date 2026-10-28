"""Realistic adult head as signed-distance primitives (graphics v3).

Replaces the mannequin-like face from bodysdf.face(): real eyelids around
separate wet eyeballs, brow ridge, cheekbones, zygomatic arches, a nose with
bridge/tip/alar wings, cupid's-bow lips, mentolabial groove, jaw angles and
ears with helix and lobe. All coordinates are in metres relative to the head
centre `hc` (head faces -Y). `scale` scales everything.

    eyes = head(shape, hc, {...})     # adds the head to an existing Shape
    eyeballs(eyes, iris="grey")       # separate eyeball meshes
"""
import math

from mathutils import Vector

import bodysdf as B
import tlib as T

DEFAULTS = {
    "scale": 1.0,
    "skull": 1.0,        # cranium size
    "brow": 0.6,         # brow ridge strength
    "cheekbone": 0.7,
    "gaunt": 0.3,        # hollow cheeks / temples
    "jaw": 0.85,         # jaw width
    "chin": 0.6,
    "nose_len": 1.0,
    "nose_width": 1.0,
    "nose_bridge": 0.6,
    "lips": 0.6,
    "eye_open": 0.75,    # lid opening (0 closed .. 1 wide, staring)
    "upper_face": True,  # False: stop the cranium at the brow (clockwork twin)
    "ear": 1.0,
}

EYE_R = 0.0118


def head(sh, hc, opt=None):
    o = dict(DEFAULTS)
    o.update(opt or {})
    s = o["scale"]
    c = Vector(hc)
    P = lambda x, y, z: c + Vector((x, y, z)) * s

    add, cut, E, SPH, CAP, RC = B.add, B.cut, B.E, B.SPH, B.CAP, B.RC

    # --- cranium + face mass
    if o["upper_face"]:
        sk = o["skull"]
        add(sh, E(P(0, 0.018, 0.03), (0.073 * sk, 0.095 * sk, 0.098 * sk)), 0.0)
        add(sh, E(P(0, 0.055, 0.0), (0.06 * sk, 0.06, 0.07)), 0.04)            # occiput
        add(sh, E(P(0, -0.052, 0.045), (0.062, 0.035, 0.052)), 0.035)           # forehead
        for side in (-1, 1):                                                    # temporal hollows
            cut(sh, E(P(side * 0.074, -0.03, 0.01), (0.012, 0.03, 0.025)), 0.02 * (0.4 + o["gaunt"]))
    else:
        add(sh, E(P(0, 0.015, -0.01), (0.07, 0.09, 0.07)), 0.0)
    add(sh, E(P(0, -0.035, -0.035), (0.06, 0.06, 0.055)), 0.04)                  # midface mass
    # --- jaw / mandible
    jw = o["jaw"]
    add(sh, E(P(0, -0.03, -0.075), (0.052 * jw, 0.058, 0.035)), 0.035)
    for side in (-1, 1):
        add(sh, E(P(side * 0.052 * jw, 0.0, -0.07), (0.012, 0.022, 0.024)), 0.025)    # jaw angle
        add(sh, CAP(P(side * 0.05 * jw, 0.0, -0.075), P(side * 0.018, -0.07, -0.103), 0.008), 0.02)  # jawline
    add(sh, E(P(0, -0.077, -0.103), (0.016 * (0.6 + o["chin"]), 0.012, 0.014)), 0.02)  # chin pad
    # --- brow ridge, glabella, cheekbones, zygomatic arches
    if o["upper_face"]:
        for side in (-1, 1):
            add(sh, E(P(side * 0.031, -0.081, 0.027), (0.024, 0.01, 0.007)), 0.012 * (0.5 + o["brow"]))
        add(sh, E(P(0, -0.088, 0.02), (0.012, 0.008, 0.012)), 0.01)              # glabella
    for side in (-1, 1):
        cb = o["cheekbone"]
        add(sh, E(P(side * 0.046, -0.064, -0.006), (0.019, 0.014, 0.011)), 0.014 * cb + 0.004)
        add(sh, CAP(P(side * 0.055, -0.05, -0.004), P(side * 0.068, -0.005, 0.0), 0.006 * cb + 0.002), 0.012)
        add(sh, E(P(side * 0.036, -0.071, -0.04), (0.022, 0.012 * (1.2 - o["gaunt"]), 0.022)), 0.02)   # cheek fat
        if o["gaunt"] > 0.05:
            cut(sh, E(P(side * 0.05, -0.068, -0.05), (0.016, 0.008 * o["gaunt"], 0.02)), 0.02)
        # nasolabial fold
        cut(sh, CAP(P(side * 0.019, -0.088, -0.033), P(side * 0.028, -0.081, -0.062), 0.0018), 0.004)
    # --- eyes: socket, lids, opening
    eyes = []
    if o["upper_face"]:
        for side in (-1, 1):
            ec = P(side * 0.032, -0.07, 0.008)
            eyes.append(ec)
            cut(sh, SPH(ec + Vector((0, -0.006, 0.0)) * s, 0.0145 * s), 0.008)               # orbit
            add(sh, SPH(ec, (EYE_R + 0.0016) * s), 0.005)                                    # lid shell
            op = o["eye_open"]
            # almond opening, slightly tilted, wider at the outer corner
            cut(sh, E(ec + Vector((side * 0.001, -0.012, 0.0005)) * s,
                      (0.0128 * s, 0.009 * s, (0.0018 + 0.0045 * op) * s),
                      B.frame((0, -1, 0), up=(side * 0.08, 0, 1))), 0.0015)
            add(sh, CAP(ec + Vector((-0.011 * side, -0.011, 0.007)) * s, ec + Vector((0.012 * side, -0.009, 0.0075)) * s,
                        0.0016 * s), 0.003)                                                    # upper lid crease fold
            add(sh, E(ec + Vector((0, -0.0105, -0.009)) * s, (0.012 * s, 0.0028 * s, 0.0025 * s)), 0.003)  # lower lid
    # --- nose
    nl, nw = o["nose_len"], o["nose_width"]
    top = P(0, -0.083, 0.012) if o["upper_face"] else P(0, -0.083, -0.006)
    tip = P(0, -0.105 - 0.008 * nl, -0.034 * nl)
    add(sh, RC(top, tip, 0.0068 * nw + 0.002 * o["nose_bridge"], 0.0095 * nw), 0.007)
    add(sh, SPH(tip + Vector((0, 0.002, 0.001)) * s, 0.0088 * s * nw), 0.004)              # tip lobule
    for side in (-1, 1):
        add(sh, E(P(side * 0.0125 * nw, -0.094, -0.036 * nl), (0.0075 * nw, 0.008, 0.0065)), 0.004)  # alar wing
        cut(sh, E(P(side * 0.0058 * nw, -0.099, -0.042 * nl), (0.0035, 0.004, 0.0022)), 0.0015)     # nostril
    cut(sh, CAP(P(0, -0.1, -0.044 * nl), P(0, -0.094, -0.05), 0.0012), 0.002)               # columella notch
    # --- mouth
    lp = o["lips"]
    zm = -0.058
    cut(sh, CAP(P(0, -0.095, -0.046), P(0, -0.093, zm + 0.005), 0.0022), 0.003)            # philtrum
    for side in (-1, 1):
        add(sh, E(P(side * 0.009, -0.091, zm + 0.004), (0.011, 0.006 * lp + 0.002, 0.004)), 0.003)  # cupid's bow
    add(sh, E(P(0, -0.087, zm - 0.0075), (0.019, 0.0075 * lp + 0.0025, 0.0055)), 0.004)    # lower lip
    cut(sh, E(P(0, -0.094, zm), (0.0215, 0.01, 0.0009)), 0.0012)                            # lip line
    for side in (-1, 1):
        cut(sh, SPH(P(side * 0.0215, -0.085, zm - 0.0005), 0.0022), 0.003)                  # mouth corners
    cut(sh, E(P(0, -0.088, zm - 0.02), (0.016, 0.004, 0.003)), 0.006)                       # mentolabial groove
    # --- ears
    if o["ear"] > 0:
        for side in (-1, 1):
            ear_c = P(side * 0.071, 0.012, -0.008)
            fr = B.frame((side * 0.25, 1, 0), up=(0, 0, 1))
            add(sh, E(ear_c, (0.006, 0.019, 0.029), fr), 0.006)
            cut(sh, E(ear_c + Vector((side * 0.006, -0.002, -0.004)), (0.004, 0.011, 0.014), fr), 0.003)   # concha
            add(sh, E(ear_c + Vector((side * 0.002, 0.004, 0.021)), (0.005, 0.013, 0.006), fr), 0.004)     # helix top
            add(sh, E(ear_c + Vector((side * 0.002, 0.0, -0.028)), (0.005, 0.008, 0.007), fr), 0.004)      # lobe
    return eyes


def eyeballs(eye_centres, prefix, iris="eye_grey", scale=1.0, look=(0, -1, 0)):
    """Separate eyeball meshes with a planar-mapped iris texture facing `look`."""
    out = []
    for ec in eye_centres:
        ob = T.sphere(prefix + "_eyeball", EYE_R * scale, tuple(ec), iris, 32, 20)
        T.planar_uv(ob, "Y")
        # mirror U so the iris map is centred on the front (planar_uv spans the full sphere)
        out.append(ob)
    return out
