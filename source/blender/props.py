"""TIMBUK prop library.

Each @prop function builds one prop at the origin (floor at z=0, front facing
-Y) and returns its objects. `build_all()` exports each to
assets/models/props/<name>.glb with a simple collision box.

Run:  blender -b --factory-startup --python source/blender/props.py [-- name ...]
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import tlib as T  # noqa: E402
from tlib import box, cyl, sphere, torus, tube, bezier_points, collider, empty  # noqa: E402

PROPS = {}


def prop(collide=True):
    def deco(fn):
        PROPS[fn.__name__] = (fn, collide)
        return fn
    return deco


# ----------------------------------------------------------------- helpers

def legs(x, y, h, r=0.022, mat="steel", z0=0.0):
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            out.append(cyl("leg", r, h, (sx * x, sy * y, z0 + h / 2), mat, seg=10))
    return out


def screen(name, w, h, loc, rot=(0, 0, 0), mat="monitor", depth=0.004):
    ob = box(name, (w, depth, h), loc, mat, rot=rot, uv=False)
    T.planar_uv(ob, "Y")
    return ob


def blood_splat(center, size, seed=0, count=9):
    """Irregular dried blood stain built from overlapping flat discs."""
    rnd = random.Random(seed)
    out = []
    for i in range(count):
        r = size * rnd.uniform(0.15, 0.55) * (1.0 if i < 3 else 0.5)
        dx, dy = rnd.gauss(0, size * 0.45), rnd.gauss(0, size * 0.3)
        sq = rnd.uniform(0.5, 1.0)
        d = cyl("blood", r, 0.002, (center[0] + dx, center[1] + dy, center[2] + i * 0.0003), "blood_dry",
                seg=14, uv=False, smooth=False)
        d.scale = (1.0, sq, 1.0)
        d.rotation_euler = (0, 0, rnd.uniform(0, math.pi))
        out.append(d)
    return out


def scatter_papers(n, area, z, seed=0, mats=("paper", "paper_old")):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        x = rnd.uniform(-area[0], area[0])
        y = rnd.uniform(-area[1], area[1])
        out.append(box("paper", (0.21, 0.297, 0.002), (x, y, z + i * 0.0008),
                       rnd.choice(mats), rot=(0, 0, rnd.uniform(0, math.pi)), uv=False))
    return out


# ----------------------------------------------------------------- furniture

@prop()
def lab_table():
    o = [box("top", (1.8, 0.8, 0.04), (0, 0, 0.9), "painted_white", bevel=0.006)]
    o.append(box("apron", (1.7, 0.7, 0.08), (0, 0, 0.84), "steel"))
    o += legs(0.82, 0.33, 0.82)
    o.append(box("shelf", (1.66, 0.66, 0.02), (0, 0, 0.18), "steel"))
    for sx in (-1, 1):
        o.append(box("rail", (0.03, 0.66, 0.03), (sx * 0.82, 0, 0.18), "steel"))
    return o


@prop()
def lab_bench_sink():
    """Long wall bench with cabinets, sink and a tall gooseneck tap."""
    o = [box("counter", (2.4, 0.75, 0.05), (0, 0, 0.92), "black_cavity", bevel=0.008)]
    o.append(box("body", (2.36, 0.68, 0.86), (0, 0.03, 0.45), "painted_white", bevel=0.01))
    for i in range(4):
        x = -0.885 + i * 0.59
        o.append(box("door", (0.56, 0.02, 0.7), (x, -0.32, 0.46), "painted_white", bevel=0.004))
        o.append(box("handle", (0.12, 0.02, 0.015), (x, -0.335, 0.74), "steel"))
    o.append(box("toe", (2.36, 0.05, 0.1), (0, -0.28, 0.05), "rubber"))
    o.append(box("sink", (0.5, 0.4, 0.02), (0.6, 0, 0.9), "steel"))
    o.append(tube("tap", [(0.6, 0.3, 0.94), (0.6, 0.3, 1.25), (0.6, 0.12, 1.3), (0.6, 0.05, 1.22)], 0.012, "steel", 8))
    o.append(box("splash", (2.4, 0.03, 0.4), (0, 0.36, 1.13), "painted_white"))
    return o


@prop()
def exam_bed():
    o = [box("frame", (2.0, 0.75, 0.08), (0, 0, 0.62), "steel", bevel=0.01)]
    o.append(box("mattress", (1.95, 0.7, 0.1), (0, 0, 0.71), "fabric", bevel=0.03))
    o.append(box("pillow", (0.4, 0.6, 0.1), (-0.75, 0, 0.8), "fabric", rot=(0, 0.25, 0), bevel=0.04))
    o += legs(0.9, 0.32, 0.55, 0.02, "steel", 0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(cyl("wheel", 0.05, 0.03, (sx * 0.9, sy * 0.32, 0.05), "rubber", rot=(math.pi / 2, 0, 0), seg=14))
    # restraint straps over the mattress
    for x in (-0.55, 0.05, 0.6):
        o.append(box("strap", (0.08, 0.78, 0.012), (x, 0, 0.765), "rubber"))
        o.append(box("buckle", (0.06, 0.03, 0.05), (x, -0.39, 0.75), "steel"))
    o.append(tube("rail", [(-0.9, -0.38, 0.68), (-0.9, -0.38, 0.95), (0.9, -0.38, 0.95), (0.9, -0.38, 0.68)], 0.015, "steel"))
    o += blood_splat((0.2, 0.05, 0.762), 0.22, seed=2)
    return o


@prop()
def restraint_chair():
    """Reclining experimental chair with head clamp, wrist cuffs and cables."""
    o = [cyl("base", 0.3, 0.08, (0, 0, 0.04), "painted_metal", seg=24)]
    o.append(cyl("column", 0.07, 0.45, (0, 0, 0.3), "steel", seg=16))
    o.append(box("seat", (0.55, 0.55, 0.1), (0, 0, 0.55), "rubber", bevel=0.03))
    o.append(box("back", (0.55, 0.1, 0.8), (0, 0.32, 0.95), "rubber", rot=(-0.35, 0, 0), bevel=0.03))
    o.append(box("legrest", (0.5, 0.55, 0.08), (0, -0.5, 0.42), "rubber", rot=(0.6, 0, 0), bevel=0.03))
    for sx in (-1, 1):
        o.append(box("arm", (0.08, 0.5, 0.06), (sx * 0.33, 0.0, 0.72), "painted_metal", bevel=0.01))
        o.append(torus("cuff", 0.05, 0.015, (sx * 0.33, -0.12, 0.76), "steel", rot=(0, math.pi / 2, 0), seg=24, rseg=8))
        o.append(torus("anklecuff", 0.055, 0.015, (sx * 0.12, -0.78, 0.25), "steel", rot=(math.pi / 2 - 0.6, 0, 0), seg=24, rseg=8))
    # head clamp halo with screws
    o.append(torus("halo", 0.17, 0.018, (0, 0.5, 1.42), "brass", rot=(-0.35 + math.pi / 2, 0, 0), seg=40, rseg=10))
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        p = Vector((math.cos(ang) * 0.17, 0, math.sin(ang) * 0.17))
        p.rotate(__import__("mathutils").Euler((-0.35, 0, 0)))
        o.append(cyl("screw", 0.008, 0.12, (p.x, 0.5 + p.y, 1.42 + p.z), "steel", seg=8,
                     rot=(0, math.atan2(p.x, p.z) + math.pi / 2, 0)))
    o.append(tube("headpost", [(0, 0.42, 1.0), (0, 0.6, 1.25), (0, 0.55, 1.4)], 0.02, "painted_metal"))
    rnd = random.Random(7)
    for i in range(6):
        start = (rnd.uniform(-0.1, 0.1), 0.52, 1.5)
        end = (rnd.uniform(-0.6, 0.6), 1.2, 0.0)
        o.append(tube("cable", bezier_points(start, end, ctrl=(start[0], 1.0, 1.6), steps=14),
                      0.01, rnd.choice(["wire_black", "wire_red", "wire_black"]), 6))
    return o


@prop()
def office_chair():
    o = [box("seat", (0.48, 0.48, 0.08), (0, 0, 0.47), "fabric", bevel=0.02)]
    o.append(box("back", (0.46, 0.06, 0.5), (0, 0.24, 0.8), "fabric", rot=(-0.12, 0, 0), bevel=0.02))
    o.append(cyl("post", 0.025, 0.36, (0, 0, 0.26), "steel"))
    for i in range(5):
        a = i / 5 * 2 * math.pi
        o.append(box("spoke", (0.3, 0.04, 0.03), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.07), "rubber", rot=(0, 0, a)))
        o.append(sphere("caster", 0.025, (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.025), "rubber", 10, 6))
    return o


@prop()
def office_desk():
    o = [box("top", (1.5, 0.75, 0.04), (0, 0, 0.74), "wood_dark", bevel=0.005)]
    o.append(box("drawers", (0.42, 0.7, 0.7), (0.52, 0, 0.36), "painted_white", bevel=0.005))
    for z in (0.18, 0.4, 0.6):
        o.append(box("dhandle", (0.12, 0.015, 0.015), (0.52, -0.36, z), "steel"))
    o.append(box("panel", (0.03, 0.7, 0.7), (-0.72, 0, 0.36), "painted_white"))
    o.append(box("modesty", (1.0, 0.02, 0.4), (-0.2, 0.33, 0.5), "painted_white"))
    o += scatter_papers(5, (0.5, 0.25), 0.762, seed=3)
    return o


@prop()
def security_desk():
    """Curved reception/security counter with monitors and a desk lamp."""
    o = []
    seg = 9
    for i in range(seg):
        a0 = math.radians(-60 + i * 120 / seg)
        a1 = math.radians(-60 + (i + 1) * 120 / seg)
        am = (a0 + a1) / 2
        R = 2.0
        w = 2 * R * math.sin((a1 - a0) / 2) + 0.02
        c = (math.sin(am) * R, -math.cos(am) * R + R, 0)
        o.append(box("front", (w, 0.08, 1.1), (c[0], c[1], 0.55), "painted_metal", rot=(0, 0, am)))
        o.append(box("cap", (w, 0.35, 0.04), (c[0] + math.sin(am) * 0.1, c[1] - math.cos(am) * 0.1 + 0.1, 1.12), "wood_dark", rot=(0, 0, am)))
        o.append(box("work", (w, 0.6, 0.03), (c[0] - math.sin(am) * -0.35, c[1] + math.cos(am) * 0.35, 0.76), "painted_white", rot=(0, 0, am)))
        o.append(box("kick", (w, 0.02, 0.1), (c[0] + math.sin(am) * 0.05, c[1] - math.cos(am) * 0.05, 0.05), "rubber", rot=(0, 0, am)))
    for i, x in enumerate((-0.7, 0.0, 0.7)):
        y = 0.62 + abs(x) * 0.25
        a = -x * 0.5
        o.append(box("mon", (0.42, 0.3, 0.32), (x, y, 0.95), "plastic", rot=(0, 0, a), bevel=0.02))
        o.append(screen("scr", 0.34, 0.25, (x + math.sin(a) * 0.155, y + math.cos(a) * 0.155, 0.96), (0, 0, a),
                        "monitor" if i != 1 else "black_cavity"))
    o.append(box("keyboard", (0.45, 0.15, 0.025), (0, 1.05, 0.79), "plastic", rot=(-0.08, 0, 0)))
    o.append(tube("lamp", [(-1.0, 0.75, 0.78), (-1.0, 0.75, 1.05), (-0.9, 0.9, 1.15)], 0.01, "steel"))
    o.append(cyl("lampshade", 0.06, 0.08, (-0.9, 0.9, 1.13), "painted_metal", r2=0.03))
    for paper in scatter_papers(7, (0.7, 0.12), 0.79, seed=9):
        paper.location.y += 0.95
        o.append(paper)
    o.append(empty("L__desk_lamp__0", (-0.9, 0.9, 1.05), props={"energy": 0.6, "range": 3.0, "color": [1.0, 0.75, 0.45]}))
    return o


@prop()
def storage_cabinet():
    o = [box("body", (0.9, 0.45, 1.9), (0, 0, 0.95), "painted_white", bevel=0.008)]
    o.append(box("inner", (0.84, 0.02, 1.84), (0, -0.2, 0.95), "black_cavity"))
    for i in range(4):
        o.append(box("shelf", (0.84, 0.4, 0.015), (0, 0, 0.35 + i * 0.42), "steel"))
    # left door closed, right door swung open
    o.append(box("doorL", (0.44, 0.02, 1.84), (-0.225, -0.235, 0.95), "painted_white", bevel=0.004))
    door = box("doorR", (0.44, 0.02, 1.84), (0.45 + 0.07, -0.235 - 0.2, 0.95), "painted_white", rot=(0, 0, -1.1), bevel=0.004)
    o.append(door)
    o.append(box("handle", (0.015, 0.02, 0.15), (-0.03, -0.25, 1.0), "steel"))
    for i in range(3):
        o.append(cyl("jar", 0.05, 0.18, (-0.25 + i * 0.12, 0.05, 1.28), "glass", seg=14))
        o.append(cyl("jarcap", 0.052, 0.025, (-0.25 + i * 0.12, 0.05, 1.38), "plastic", seg=14))
    o.append(box("binder", (0.3, 0.25, 0.32), (0.15, 0.0, 0.53), "paper_old", rot=(0, 0.2, 0)))
    return o


@prop()
def filing_cabinet():
    o = [box("body", (0.48, 0.62, 1.32), (0, 0, 0.66), "painted_metal", bevel=0.006)]
    for i in range(4):
        z = 0.18 + i * 0.32
        pull = 0.25 if i == 1 else 0.0
        o.append(box("drawer", (0.44, 0.03, 0.29), (0, -0.31 - pull, z), "painted_metal", bevel=0.004))
        o.append(box("pull", (0.12, 0.02, 0.02), (0, -0.335 - pull, z + 0.06), "steel"))
        if pull:
            o.append(box("drawerbox", (0.42, 0.25, 0.22), (0, -0.19 - pull / 2, z), "painted_metal"))
            for k in range(6):
                o.append(box("folder", (0.4, 0.004, 0.24), (0, -0.4 + k * 0.03, z + 0.05), "paper_old", rot=(0.15 * (k % 3 - 1), 0, 0)))
    return o


@prop()
def cart_trolley():
    o = []
    for z in (0.25, 0.85):
        o.append(box("tray", (0.8, 0.5, 0.02), (0, 0, z), "steel", bevel=0.004))
        o.append(box("lip", (0.8, 0.02, 0.04), (0, -0.25, z + 0.02), "steel"))
    o += legs(0.38, 0.23, 0.85, 0.012, "steel", 0.05)
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(cyl("wheel", 0.04, 0.025, (sx * 0.38, sy * 0.23, 0.04), "rubber", rot=(math.pi / 2, 0, 0), seg=12))
    o.append(box("tray_tools", (0.35, 0.25, 0.02), (-0.15, 0, 0.87), "steel"))
    for i in range(5):
        o.append(cyl("tool", 0.004, 0.2, (-0.25 + i * 0.05, 0, 0.885), "steel", rot=(math.pi / 2, 0, 0.1 * i), seg=6))
    o.append(cyl("bottle", 0.04, 0.16, (0.2, 0.05, 0.95), "glass", seg=14))
    return o


@prop()
def iv_stand():
    o = [cyl("pole", 0.012, 1.9, (0, 0, 0.98), "steel", seg=10)]
    for i in range(5):
        a = i / 5 * 2 * math.pi
        o.append(box("foot", (0.3, 0.03, 0.02), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.06), "steel", rot=(0, 0, a)))
    o.append(box("hook", (0.3, 0.012, 0.012), (0, 0, 1.9), "steel"))
    o.append(box("bag", (0.12, 0.03, 0.2), (0.12, 0, 1.75), "glass_tank", bevel=0.02))
    o.append(tube("line", bezier_points((0.12, 0, 1.64), (0.4, -0.2, 0.9), sag=0.3), 0.003, "plastic", 5))
    return o


# ----------------------------------------------------------------- equipment

@prop()
def computer_terminal():
    """Old CRT terminal + keyboard (sits on a table, base at z=0)."""
    o = [box("crt", (0.42, 0.42, 0.38), (0, 0.08, 0.22), "plastic", bevel=0.03)]
    o.append(box("crt_back", (0.3, 0.25, 0.28), (0, 0.38, 0.2), "plastic", bevel=0.04))
    o.append(screen("scr", 0.32, 0.25, (0, -0.135, 0.23), mat="monitor"))
    o.append(box("bezel", (0.36, 0.01, 0.29), (0, -0.128, 0.23), "black_cavity"))
    o.append(box("foot", (0.3, 0.3, 0.03), (0, 0.1, 0.015), "plastic"))
    o.append(box("kb", (0.44, 0.16, 0.03), (0, -0.3, 0.015), "plastic", rot=(0.06, 0, 0), bevel=0.005))
    for r in range(4):
        o.append(box("keys", (0.4, 0.025, 0.008), (0, -0.35 + r * 0.03, 0.035 + r * 0.002), "rubber"))
    o.append(empty("L__screen__0", (0, -0.3, 0.25), props={"energy": 0.35, "range": 1.6, "color": [0.35, 1.0, 0.6], "flicker": 0.15}))
    return o


@prop()
def monitor_broken():
    o = [box("crt", (0.42, 0.42, 0.38), (0, 0.08, 0.22), "plastic", bevel=0.03)]
    o.append(screen("scr", 0.32, 0.25, (0, -0.135, 0.23), mat="black_cavity"))
    rnd = random.Random(4)
    for i in range(6):   # glass shards hanging in the frame
        o.append(box("shard", (rnd.uniform(0.04, 0.12), 0.003, rnd.uniform(0.04, 0.1)),
                     (rnd.uniform(-0.12, 0.12), -0.14, rnd.uniform(0.14, 0.32)), "glass",
                     rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-1, 1), 0), uv=False))
    o.append(tube("cable", bezier_points((0, 0.3, 0.1), (0.3, 0.6, 0.0), sag=0.05), 0.008, "wire_black", 6))
    return o


@prop()
def server_rack():
    o = [box("body", (0.6, 0.9, 2.0), (0, 0, 1.0), "painted_metal", bevel=0.01)]
    o.append(box("front", (0.54, 0.02, 1.9), (0, -0.45, 1.0), "black_cavity"))
    rnd = random.Random(2)
    for i in range(16):
        z = 0.15 + i * 0.11
        o.append(box("unit", (0.52, 0.03, 0.09), (0, -0.465, z), rnd.choice(["painted_metal", "steel", "plastic"])))
        if rnd.random() < 0.6:
            o.append(box("led", (0.012, 0.01, 0.012), (0.2, -0.485, z), rnd.choice(["light_green", "light_amber", "light_red"]), uv=False))
    return o


@prop()
def electrical_panel():
    o = [box("box", (0.7, 0.2, 1.0), (0, 0.1, 1.4), "painted_metal", bevel=0.01)]
    o.append(box("inside", (0.62, 0.02, 0.92), (0, -0.005, 1.4), "black_cavity"))
    for r in range(4):
        for c in range(6):
            o.append(box("breaker", (0.05, 0.04, 0.12), (-0.22 + c * 0.088, -0.02, 1.13 + r * 0.18),
                         "plastic" if (r + c) % 5 else "light_red"))
    door = box("door", (0.7, 0.02, 1.0), (-0.4, -0.25, 1.4), "painted_metal", rot=(0, 0, 1.2))
    o.append(door)
    o.append(box("sign", (0.25, 0.005, 0.25), (-0.47, -0.37, 1.65), "warning_sign", rot=(0, 0, 1.2), uv=False))
    T.planar_uv(o[-1], "Y")
    rnd = random.Random(5)
    for i in range(5):
        x = -0.2 + i * 0.1
        o.append(tube("conduit", [(x, 0.1, 1.9), (x, 0.1, 2.4 + rnd.random() * 0.3)], 0.025, "steel", 8))
    for i in range(3):
        start = (rnd.uniform(-0.2, 0.2), -0.03, rnd.uniform(1.1, 1.6))
        o.append(tube("loose", bezier_points(start, (start[0] + rnd.uniform(-0.3, 0.3), -0.4, 0.02), sag=0.0,
                                             ctrl=(start[0], -0.3, start[2] - 0.2)), 0.008, rnd.choice(["wire_red", "wire_black", "wire_copper"]), 6))
    return o


@prop()
def microscope():
    o = [box("base", (0.2, 0.25, 0.04), (0, 0, 0.02), "painted_white", bevel=0.01)]
    o.append(tube("arm", [(0, 0.08, 0.04), (0, 0.1, 0.25), (0, 0.04, 0.33)], 0.025, "painted_white", 10))
    o.append(box("stage", (0.14, 0.14, 0.015), (0, -0.02, 0.13), "black_cavity"))
    o.append(cyl("tube", 0.02, 0.18, (0, -0.0, 0.33), "black_cavity", rot=(0.4, 0, 0)))
    o.append(cyl("eyepiece", 0.015, 0.06, (0, 0.04, 0.43), "black_cavity", rot=(0.4, 0, 0)))
    o.append(cyl("knob", 0.03, 0.02, (0.05, 0.09, 0.18), "steel", rot=(0, math.pi / 2, 0)))
    return o


@prop()
def centrifuge():
    o = [box("body", (0.5, 0.55, 0.35), (0, 0, 0.175), "painted_white", bevel=0.03)]
    o.append(cyl("lid", 0.2, 0.02, (0, 0.03, 0.36), "glass", seg=24))
    o.append(box("panel", (0.4, 0.02, 0.12), (0, -0.28, 0.2), "black_cavity", rot=(0.4, 0, 0)))
    o.append(box("led", (0.05, 0.01, 0.02), (0.1, -0.29, 0.22), "light_amber", rot=(0.4, 0, 0)))
    return o


@prop()
def chem_bottles():
    rnd = random.Random(11)
    o = []
    for i in range(9):
        x, y = rnd.uniform(-0.25, 0.25), rnd.uniform(-0.12, 0.12)
        h = rnd.uniform(0.12, 0.3)
        r = rnd.uniform(0.03, 0.06)
        kind = rnd.random()
        if kind < 0.35:  # flask
            o.append(cyl("flask", r * 1.6, h * 0.6, (x, y, h * 0.3), "glass", r2=r * 0.5, seg=16))
            o.append(cyl("neck", r * 0.45, h * 0.4, (x, y, h * 0.8), "glass", seg=12))
            o.append(cyl("liq", r * 1.4, h * 0.25, (x, y, h * 0.13), "tank_fluid", r2=r * 1.0, seg=16))
        else:
            o.append(cyl("bottle", r, h, (x, y, h / 2), "glass" if kind < 0.7 else "plastic", seg=16))
            o.append(cyl("cap", r * 0.6, 0.03, (x, y, h + 0.015), "rubber", seg=12))
            if kind < 0.7:
                o.append(cyl("liq", r * 0.9, h * 0.5, (x, y, h * 0.26), rnd.choice(["tank_fluid", "chem_residue"]), seg=16))
    return o


@prop()
def chem_barrel():
    o = [cyl("drum", 0.29, 0.88, (0, 0, 0.44), "painted_metal", seg=28)]
    for z in (0.02, 0.3, 0.58, 0.86):
        o.append(torus("rib", 0.295, 0.012, (0, 0, z), "painted_metal", seg=28, rseg=6))
    o.append(cyl("band", 0.292, 0.14, (0, 0, 0.44), "hazard", seg=28))
    o.append(cyl("bung", 0.03, 0.02, (0.15, 0.05, 0.89), "steel", seg=10))
    return o


@prop()
def chem_barrel_leaking():
    o = [cyl("drum", 0.29, 0.88, (0.0, 0.0, 0.29), "rust", seg=28, rot=(math.pi / 2, 0, 0.4))]
    o.append(cyl("band", 0.292, 0.14, (0, 0, 0.29), "hazard", seg=28, rot=(math.pi / 2, 0, 0.4)))
    o.append(cyl("puddle", 0.9, 0.006, (0.35, -0.5, 0.003), "chem_residue", seg=32, smooth=False))
    o.append(empty("L__chem__0", (0.35, -0.5, 0.25), props={"energy": 0.5, "range": 2.5, "color": [0.4, 1.0, 0.3]}))
    return o


@prop()
def gas_cylinders():
    o = [box("rack_base", (1.0, 0.35, 0.05), (0, 0, 0.025), "painted_metal")]
    o.append(box("rack_back", (1.0, 0.04, 1.4), (0, 0.17, 0.7), "painted_metal"))
    o.append(box("chain_bar", (1.0, 0.04, 0.04), (0, -0.0, 1.1), "steel"))
    cols = ["painted_metal", "copper", "painted_white", "rust"]
    for i in range(4):
        x = -0.36 + i * 0.24
        o.append(cyl("cyl", 0.1, 1.35, (x, 0, 0.7), cols[i], seg=20))
        o.append(sphere("dome", 0.1, (x, 0, 1.37), cols[i], 20, 10, scale=(1, 1, 0.6)))
        o.append(cyl("valve", 0.03, 0.08, (x, 0, 1.47), "brass", seg=10))
    return o


@prop()
def pipe_valve():
    o = [torus("wheel", 0.2, 0.018, (0, -0.08, 0), "painted_metal", rot=(math.pi / 2, 0, 0), seg=32, rseg=8)]
    for i in range(4):
        a = i * math.pi / 4
        o.append(box("spoke", (0.4, 0.02, 0.02), (0, -0.08, 0), "painted_metal", rot=(0, a, 0)))
    o.append(cyl("hub", 0.04, 0.08, (0, -0.04, 0), "steel", rot=(math.pi / 2, 0, 0)))
    return o


@prop()
def containment_tank():
    """Tall glass specimen cylinder with fluid, caps, pipes and indicator light."""
    o = [cyl("base", 0.75, 0.5, (0, 0, 0.25), "painted_metal", seg=32)]
    o.append(cyl("base_trim", 0.78, 0.06, (0, 0, 0.53), "brass", seg=32))
    o.append(cyl("glass", 0.62, 2.4, (0, 0, 1.76), "glass_tank", seg=40, cap=False))
    o.append(cyl("fluid", 0.6, 2.1, (0, 0, 1.62), "tank_fluid", seg=32))
    o.append(cyl("cap", 0.75, 0.45, (0, 0, 3.18), "painted_metal", seg=32))
    o.append(cyl("cap_trim", 0.78, 0.06, (0, 0, 2.97), "brass", seg=32))
    for i in range(6):
        a = i / 6 * 2 * math.pi
        o.append(cyl("strut", 0.03, 2.45, (math.cos(a) * 0.66, math.sin(a) * 0.66, 1.76), "steel", seg=8))
    rnd = random.Random(1)
    for i in range(3):
        a = rnd.uniform(0, 2 * math.pi)
        o.append(tube("hose", [(math.cos(a) * 0.5, math.sin(a) * 0.5, 3.4), (math.cos(a) * 0.5, math.sin(a) * 0.5, 3.8),
                               (math.cos(a) * 1.2, math.sin(a) * 1.2, 4.2)], 0.05, "rubber", 10))
    for i in range(8):
        o.append(sphere("bubble", rnd.uniform(0.02, 0.05), (rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0.8, 2.5)), "glass", 10, 6))
    o.append(box("panel", (0.35, 0.05, 0.25), (0, -0.76, 0.3), "black_cavity"))
    o.append(screen("readout", 0.28, 0.16, (0, -0.79, 0.3)))
    o.append(empty("L__tank__0", (0, 0, 1.0), props={"energy": 1.2, "range": 4.0, "color": [0.3, 1.0, 0.65]}))
    return o


@prop()
def containment_tank_broken():
    o = [cyl("base", 0.75, 0.5, (0, 0, 0.25), "painted_metal", seg=32)]
    o.append(cyl("base_trim", 0.78, 0.06, (0, 0, 0.53), "brass", seg=32))
    o.append(cyl("cap", 0.75, 0.45, (0, 0, 3.18), "rust", seg=32))
    o.append(cyl("residue", 0.6, 0.02, (0, 0, 0.52), "chem_residue", seg=32))
    rnd = random.Random(3)
    for i in range(6):
        a = i / 6 * 2 * math.pi
        bend = rnd.uniform(-0.25, 0.25)
        o.append(tube("strut", [(math.cos(a) * 0.66, math.sin(a) * 0.66, 0.55),
                                (math.cos(a) * (0.66 + abs(bend)), math.sin(a) * (0.66 + abs(bend)), 1.8),
                                (math.cos(a) * 0.66, math.sin(a) * 0.66, 2.96)], 0.03, "steel", 8))
    # jagged glass collar left at the bottom and top, shards on the floor
    for ring_z, up in ((0.55, 1), (2.96, -1)):
        for i in range(18):
            a = i / 18 * 2 * math.pi
            h = rnd.uniform(0.08, 0.5)
            o.append(box("collar", (0.22, 0.008, h), (math.cos(a) * 0.62, math.sin(a) * 0.62, ring_z + up * h / 2),
                         "glass_tank", rot=(0, 0, a + math.pi / 2), uv=False))
    for i in range(24):
        r = rnd.uniform(0.8, 2.2)
        a = rnd.uniform(0, 2 * math.pi)
        o.append(box("shard", (rnd.uniform(0.05, 0.25), rnd.uniform(0.05, 0.2), 0.008),
                     (math.cos(a) * r, math.sin(a) * r, 0.006), "glass_tank", rot=(0, 0, rnd.uniform(0, 6)), uv=False))
    o.append(cyl("spill", 1.5, 0.004, (0.3, -0.4, 0.002), "chem_residue", seg=40, smooth=False))
    o.append(tube("hose", bezier_points((0.4, 0, 3.4), (1.4, -0.6, 0.02), ctrl=(1.4, -0.3, 3.0)), 0.05, "rubber", 10))
    return o


# ----------------------------------------------------------------- doors & architecture props

@prop()
def security_door():
    """Frame for a 1.6 x 2.4 m opening with a sliding door stuck half open."""
    o = []
    for sx in (-1, 1):
        o.append(box("jamb", (0.15, 0.4, 2.55), (sx * 0.875, 0, 1.275), "steel", bevel=0.01))
    o.append(box("head", (1.9, 0.4, 0.15), (0, 0, 2.475), "steel", bevel=0.01))
    o.append(box("hazard_head", (1.6, 0.42, 0.1), (0, 0, 2.35), "hazard"))
    o.append(box("slab", (0.95, 0.08, 2.38), (0.55, 0.0, 1.19), "painted_metal", bevel=0.01))
    o.append(box("window", (0.3, 0.09, 0.5), (0.45, 0, 1.55), "glass"))
    o.append(box("keypad", (0.14, 0.05, 0.22), (1.1, -0.22, 1.3), "plastic", bevel=0.01))
    o.append(box("keyled", (0.03, 0.01, 0.015), (1.1, -0.25, 1.38), "light_red", uv=False))
    o.append(empty("L__keypad__0", (1.1, -0.35, 1.38), props={"energy": 0.15, "range": 1.0, "color": [1.0, 0.1, 0.05]}))
    return o


@prop()
def blast_door():
    """Heavy two-leaf containment door for a 4 x 4 m opening, jammed partly open."""
    o = []
    for sx in (-1, 1):
        o.append(box("jamb", (0.5, 1.0, 4.4), (sx * 2.25, 0, 2.2), "painted_metal", bevel=0.03))
        o.append(box("jamb_stripe", (0.52, 1.02, 0.4), (sx * 2.25, 0, 0.3), "hazard"))
    o.append(box("head", (5.0, 1.0, 0.6), (0, 0, 4.3), "painted_metal", bevel=0.03))
    o.append(box("head_stripe", (4.0, 1.02, 0.2), (0, 0, 3.95), "hazard"))
    for sx, gap in ((-1, 0.65), (1, 0.75)):
        x = sx * (1.0 + gap)
        o.append(box("leaf", (2.0, 0.35, 3.9), (x, 0, 1.95), "painted_metal", bevel=0.02))
        for z in (0.6, 1.6, 2.6, 3.4):
            o.append(box("rib", (1.9, 0.42, 0.12), (x, 0, z), "steel"))
        # chevron teeth on the meeting edge
        for k in range(8):
            o.append(box("tooth", (0.18, 0.3, 0.3), (x - sx * 1.05, 0, 0.3 + k * 0.48), "painted_metal", rot=(0, 0.785, 0)))
    o.append(box("light_housing", (0.3, 0.2, 0.2), (0, -0.55, 4.75), "painted_metal"))
    o.append(cyl("beacon", 0.09, 0.18, (0, -0.6, 4.95), "light_red", seg=16))
    o.append(empty("L__beacon__0", (0, -0.9, 4.9), props={"energy": 2.5, "range": 9.0, "color": [1.0, 0.08, 0.04], "pulse": 1.2}))
    return o


@prop()
def emergency_beacon():
    o = [box("base", (0.18, 0.12, 0.08), (0, 0.06, 0), "painted_metal")]
    o.append(cyl("dome", 0.07, 0.14, (0, -0.02, 0.0), "light_red", rot=(math.pi / 2, 0, 0), seg=16))
    o.append(empty("L__beacon__0", (0, -0.3, 0), props={"energy": 1.6, "range": 7.0, "color": [1.0, 0.08, 0.04], "pulse": 1.0}))
    return o


@prop(collide=False)
def warning_sign_plate():
    ob = box("sign", (0.45, 0.01, 0.45), (0, 0, 0), "warning_sign", uv=False)
    T.planar_uv(ob, "Y")
    return [ob]


@prop(collide=False)
def wall_clock():
    """Stopped institutional wall clock (frame + porcelain dial + hands)."""
    o = [torus("rim", 0.2, 0.025, (0, -0.02, 0), "brass", rot=(math.pi / 2, 0, 0), seg=40, rseg=10)]
    face = cyl("face", 0.2, 0.02, (0, 0, 0), "porcelain", rot=(math.pi / 2, 0, 0), seg=40, uv=False)
    T.planar_uv(face, "Z")
    o.append(face)
    o.append(box("hour", (0.012, 0.004, 0.11), (0.03, -0.03, 0.04), "black_cavity", rot=(0, -0.7, 0)))
    o.append(box("minute", (0.008, 0.004, 0.16), (-0.05, -0.034, -0.05), "black_cavity", rot=(0, 2.4, 0)))
    o.append(cyl("pin", 0.01, 0.02, (0, -0.035, 0), "brass", rot=(math.pi / 2, 0, 0)))
    return o


@prop()
def debris_pile():
    rnd = random.Random(21)
    o = []
    for i in range(16):
        s = rnd.uniform(0.08, 0.35)
        o.append(box("chunk", (s, s * rnd.uniform(0.6, 1.3), s * rnd.uniform(0.4, 0.9)),
                     (rnd.gauss(0, 0.5), rnd.gauss(0, 0.5), s * 0.25), rnd.choice(["concrete", "concrete_damaged", "ceiling_tile"]),
                     rot=(rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), rnd.uniform(0, 6)), bevel=0.01))
    for i in range(3):
        o.append(tube("rebar", [(rnd.gauss(0, 0.4), rnd.gauss(0, 0.4), 0.05), (rnd.gauss(0, 0.6), rnd.gauss(0, 0.6), rnd.uniform(0.1, 0.5))],
                      0.008, "rust", 6))
    o += scatter_papers(6, (0.8, 0.8), 0.003, seed=21)
    return o


@prop(collide=False)
def papers_scattered():
    return scatter_papers(14, (1.2, 0.9), 0.002, seed=5)


@prop()
def ceiling_tile_fallen():
    rnd = random.Random(8)
    o = []
    for i in range(4):
        o.append(box("tile", (0.6, 0.6, 0.015), (rnd.gauss(0, 0.5), rnd.gauss(0, 0.5), 0.01 + i * 0.016), "ceiling_tile",
                     rot=(rnd.uniform(-0.1, 0.1), rnd.uniform(-0.1, 0.1), rnd.uniform(0, 1))))
    o.append(box("tile_broken", (0.35, 0.6, 0.015), (0.5, 0.3, 0.06), "ceiling_tile", rot=(0.3, 0.1, 0.4)))
    return o


@prop()
def hanging_light_broken():
    """Fluorescent fixture dangling from one chain (top at z=0, hangs down)."""
    o = [tube("chain", [(0.55, 0, 0), (0.55, 0, -0.9)], 0.006, "steel", 5)]
    o.append(tube("wire", bezier_points((-0.55, 0, 0), (-0.35, 0, -1.25), sag=0.2), 0.006, "wire_black", 5))
    hous = box("housing", (1.25, 0.25, 0.08), (0, 0, -1.25), "painted_white", rot=(0, -0.95, 0), bevel=0.01)
    o.append(hous)
    o.append(box("tube", (1.15, 0.05, 0.03), (0.03, 0, -1.29), "light_fluor", rot=(0, -0.95, 0)))
    o.append(empty("L__fluor_hanging__0", (0.0, 0, -1.45), props={"energy": 1.4, "range": 6.0, "color": [0.8, 0.92, 1.0], "flicker": 0.6}))
    return o


# ----------------------------------------------------------------- story / pickup props

@prop(collide=False)
def keycard():
    o = [box("card", (0.054, 0.086, 0.002), (0, 0, 0.001), "painted_white", bevel=0.002, uv=False)]
    o.append(box("stripe", (0.054, 0.02, 0.0022), (0, 0.025, 0.0012), "light_red", uv=False))
    o.append(box("chip", (0.012, 0.01, 0.0024), (-0.012, -0.01, 0.0012), "gold", uv=False))
    o.append(box("photo", (0.018, 0.022, 0.0023), (0.012, -0.015, 0.0012), "photo", uv=False))
    return o


@prop(collide=False)
def old_key():
    o = [torus("bow", 0.012, 0.003, (0, 0, 0.003), "brass", seg=20, rseg=6)]
    o.append(cyl("shaft", 0.0025, 0.06, (0, -0.042, 0.003), "brass", rot=(math.pi / 2, 0, 0), seg=8))
    o.append(box("bit", (0.008, 0.012, 0.003), (0.004, -0.066, 0.003), "brass"))
    return o


@prop(collide=False)
def pistol():
    """Worn service pistol (visual model only, muzzle points -Y)."""
    o = [box("slide", (0.03, 0.19, 0.035), (0, 0, 0.11), "teal_metal", bevel=0.004)]
    o.append(box("frame", (0.028, 0.17, 0.025), (0, 0.01, 0.083), "rubber", bevel=0.003))
    o.append(box("grip", (0.028, 0.05, 0.11), (0, 0.065, 0.03), "rubber", rot=(-0.25, 0, 0), bevel=0.006))
    o.append(cyl("barrel", 0.006, 0.02, (0, -0.1, 0.115), "black_cavity", rot=(math.pi / 2, 0, 0), seg=10))
    o.append(box("guard", (0.006, 0.05, 0.004), (0, 0.0, 0.055), "rubber"))
    o.append(empty("MUZZLE", (0, -0.105, 0.115)))
    return o


@prop(collide=False)
def tracker_device():
    """Handheld marking/tracking device with a dish antenna and readout."""
    o = [box("body", (0.07, 0.14, 0.035), (0, 0, 0.02), "teal_metal", bevel=0.008)]
    o.append(screen("display", 0.05, 0.05, (0, -0.02, 0.038), (math.pi / 2, 0, 0)))
    o.append(cyl("antenna", 0.003, 0.08, (0.025, 0.08, 0.06), "steel", rot=(0.6, 0, 0), seg=6))
    o.append(sphere("tip", 0.006, (0.025, 0.105, 0.093), "light_red", 8, 6))
    o.append(cyl("dish", 0.025, 0.012, (-0.012, 0.075, 0.045), "brass", r2=0.01, rot=(-0.9, 0, 0), seg=16))
    o.append(box("grip", (0.06, 0.06, 0.03), (0, 0.04, 0.0), "rubber", bevel=0.008))
    o.append(empty("L__tracker__0", (0, -0.02, 0.06), props={"energy": 0.2, "range": 0.8, "color": [1.0, 0.2, 0.1], "pulse": 2.0}))
    return o


@prop(collide=False)
def photo_frame():
    o = [box("frame", (0.2, 0.015, 0.25), (0, 0, 0.125), "wood_dark", rot=(-0.2, 0, 0), bevel=0.003)]
    o.append(box("photo", (0.16, 0.017, 0.21), (0, -0.002, 0.125), "photo", rot=(-0.2, 0, 0)))
    o.append(box("stand", (0.02, 0.1, 0.18), (0, 0.06, 0.09), "wood_dark", rot=(0.35, 0, 0)))
    return o


# ----------------------------------------------------------------- exterior & large set pieces

@prop()
def street_lamp():
    o = [cyl("base", 0.18, 0.4, (0, 0, 0.2), "concrete", seg=16)]
    o.append(cyl("pole", 0.07, 6.0, (0, 0, 3.2), "painted_metal", r2=0.05, seg=12))
    o.append(tube("arm", [(0, 0, 6.1), (0, -0.4, 6.4), (0, -1.4, 6.45)], 0.045, "painted_metal", 10))
    o.append(box("head", (0.35, 0.7, 0.14), (0, -1.6, 6.4), "painted_metal", bevel=0.03))
    o.append(box("lens", (0.28, 0.6, 0.02), (0, -1.6, 6.32), "light_amber"))
    o.append(empty("L__sodium__0", (0, -1.6, 6.2), props={"energy": 6.0, "range": 18.0, "color": [1.0, 0.62, 0.3], "spot": 70, "shadow": True, "flicker": 0.08}))
    return o


@prop()
def jersey_barrier():
    o = [box("low", (2.0, 0.6, 0.3), (0, 0, 0.15), "concrete", bevel=0.02)]
    o.append(box("mid", (2.0, 0.35, 0.35), (0, 0, 0.45), "concrete", bevel=0.02))
    o.append(box("top", (2.0, 0.18, 0.2), (0, 0, 0.72), "concrete", bevel=0.02))
    o.append(box("stripe", (0.5, 0.36, 0.1), (0.5, 0, 0.5), "hazard"))
    return o


@prop()
def security_gate():
    """Pair of turnstile posts with a broken barrier arm."""
    o = []
    for sx in (-1, 1):
        o.append(box("post", (0.3, 0.9, 1.0), (sx * 0.65, 0, 0.5), "steel", bevel=0.03))
        o.append(box("cap", (0.32, 0.92, 0.04), (sx * 0.65, 0, 1.02), "black_cavity"))
        o.append(box("led", (0.05, 0.01, 0.03), (sx * 0.65, -0.46, 0.85), "light_red", uv=False))
    o.append(cyl("arm", 0.02, 0.9, (0.1, 0.1, 0.4), "steel", rot=(0.0, 1.2, 0.3), seg=8))
    return o


@prop()
def bench_seating():
    """Row of three waiting-room chairs on a shared beam."""
    o = [box("beam", (2.0, 0.08, 0.06), (0, 0.1, 0.35), "steel")]
    for sx in (-1, 1):
        o.append(box("leg", (0.05, 0.5, 0.35), (sx * 0.85, 0.1, 0.175), "steel"))
    for i in range(3):
        x = -0.65 + i * 0.65
        o.append(box("seat", (0.55, 0.5, 0.05), (x, 0.05, 0.45), "plastic", bevel=0.02))
        o.append(box("back", (0.55, 0.05, 0.45), (x, 0.32, 0.73), "plastic", rot=(-0.15, 0, 0), bevel=0.02))
    return o


@prop()
def surgical_lamp():
    """Ceiling surgical lamp: top at z=0, dish hangs ~1.3 m below."""
    o = [cyl("mount", 0.12, 0.08, (0, 0, -0.04), "painted_white", seg=16)]
    o.append(tube("arm", [(0, 0, -0.08), (0, 0, -0.5), (0.5, 0, -0.75), (0.5, 0, -1.1)], 0.035, "painted_white", 10))
    o.append(cyl("dish", 0.38, 0.14, (0.5, 0, -1.2), "painted_white", r2=0.22, seg=32))
    o.append(cyl("lens", 0.34, 0.01, (0.5, 0, -1.275), "light_fluor", seg=32))
    for i in range(6):
        a = i / 6 * 2 * math.pi
        o.append(cyl("bulb", 0.05, 0.02, (0.5 + math.cos(a) * 0.2, math.sin(a) * 0.2, -1.285), "light_amber", seg=10))
    o.append(empty("L__surgical__0", (0.5, 0, -1.35), props={"energy": 8.0, "range": 5.0, "color": [1.0, 0.95, 0.85], "spot": 40, "shadow": True, "flicker": 0.2}))
    return o


@prop()
def cot():
    """Small institutional child's cot with railings (twin story prop)."""
    o = [box("mattress", (1.3, 0.65, 0.1), (0, 0, 0.45), "fabric", bevel=0.03)]
    o.append(box("base", (1.34, 0.68, 0.04), (0, 0, 0.38), "painted_white"))
    o += legs(0.64, 0.31, 0.4, 0.018, "painted_white")
    for sy in (-1, 1):
        o.append(cyl("toprail", 0.015, 1.3, (0, sy * 0.33, 0.85), "painted_white", rot=(0, math.pi / 2, 0), seg=8))
        for k in range(14):
            o.append(cyl("bar", 0.008, 0.45, (-0.62 + k * 0.095, sy * 0.33, 0.625), "painted_white", seg=6))
    for sx in (-1, 1):
        o.append(box("end", (0.03, 0.68, 0.55), (sx * 0.66, 0, 0.6), "painted_white", bevel=0.01))
    o.append(box("blanket", (0.7, 0.66, 0.03), (0.25, 0, 0.51), "fabric", rot=(0, 0.05, 0.05), bevel=0.01))
    o.append(box("strap", (0.06, 0.7, 0.012), (-0.2, 0, 0.505), "rubber"))
    o.append(box("tag", (0.12, 0.005, 0.08), (0, -0.335, 0.75), "paper_old"))
    return o


@prop(collide=False)
def teddy_bear():
    o = [sphere("body", 0.09, (0, 0, 0.09), "fabric", 16, 10, scale=(1, 0.85, 1.1))]
    o.append(sphere("head", 0.065, (0, -0.01, 0.23), "fabric", 16, 10))
    for sx in (-1, 1):
        o.append(sphere("ear", 0.022, (sx * 0.05, 0, 0.29), "fabric", 10, 6))
        o.append(sphere("arm", 0.03, (sx * 0.09, -0.02, 0.12), "fabric", 10, 6, scale=(0.8, 0.8, 1.4)))
        o.append(sphere("leg", 0.035, (sx * 0.05, -0.06, 0.03), "fabric", 10, 6, scale=(1, 1.4, 0.8)))
        o.append(sphere("eye", 0.008, (sx * 0.022, -0.07, 0.24), "black_cavity", 8, 5))
    o.append(sphere("snout", 0.025, (0, -0.065, 0.215), "paper_old", 10, 6))
    o.append(box("stitch", (0.005, 0.004, 0.08), (0.03, -0.075, 0.1), "wire_black", rot=(0, 0.3, 0)))
    return o


@prop(collide=False)
def blood_trail():
    """Smeared drag trail along -Y (about 3 m long)."""
    o = []
    rnd = random.Random(12)
    for i in range(14):
        y = -i * 0.22
        o += blood_splat((rnd.gauss(0, 0.06), y, 0.002), 0.14 * (1 - i / 20), seed=i, count=4)
    return o


@prop()
def failed_containment_device():
    """Centerpiece: a 3 m pressure chamber burst open from the inside."""
    o = []
    rnd = random.Random(40)
    o.append(cyl("plinth", 2.6, 0.5, (0, 0, 0.25), "concrete", seg=40))
    o.append(cyl("plinth_trim", 2.65, 0.08, (0, 0, 0.5), "hazard", seg=40))
    o.append(cyl("base_ring", 1.9, 0.6, (0, 0, 0.8), "painted_metal", seg=40))
    o.append(torus("base_bolt_ring", 1.92, 0.05, (0, 0, 1.1), "brass", seg=48, rseg=8))
    o.append(cyl("floor_grate", 1.6, 0.04, (0, 0, 1.1), "steel", seg=40))
    # bent ribs: torn outward toward -Y where the subject broke out
    for i in range(12):
        a = i / 12 * 2 * math.pi
        outward = max(0.0, -math.sin(a)) ** 2 * 1.2
        p0 = (math.cos(a) * 1.6, math.sin(a) * 1.6, 1.1)
        p1 = (math.cos(a) * (1.65 + outward * 0.6), math.sin(a) * (1.65 + outward * 0.9), 2.5)
        p2 = (math.cos(a) * (1.6 + outward), math.sin(a) * (1.6 + outward * 1.4), 3.6 - outward * 0.8)
        if outward > 0.9 and i % 2:
            p2 = (p1[0] * 1.3, p1[1] * 1.5, 2.4)
        o.append(tube("rib", [p0, p1, p2], 0.07, "steel" if i % 3 else "rust", 10))
    o.append(torus("top_ring", 1.62, 0.12, (0, 0.25, 4.05), "painted_metal", rot=(0.25, 0, 0), seg=48, rseg=10))
    o.append(cyl("top_cap", 1.7, 0.6, (0, 0.35, 4.45), "painted_metal", rot=(0.25, 0, 0), seg=40))
    o.append(cyl("top_core", 0.5, 0.8, (0, 0.5, 5.0), "copper", rot=(0.25, 0, 0), seg=24))
    for k in range(5):
        o.append(torus("coil", 0.55, 0.04, (0, 0.5 + k * 0.03, 4.75 + k * 0.12), "copper", rot=(0.25, 0, 0), seg=28, rseg=6))
    # glass: remaining jagged collar on the back half, shards everywhere in front
    for i in range(26):
        a = i / 26 * 2 * math.pi
        if math.sin(a) < -0.2:
            continue
        h = rnd.uniform(0.3, 2.3)
        o.append(box("glass", (0.42, 0.012, h), (math.cos(a) * 1.55, math.sin(a) * 1.55, 1.1 + h / 2), "glass_tank",
                     rot=(0, 0, a + math.pi / 2), uv=False))
    for i in range(60):
        r = rnd.uniform(1.8, 5.5)
        a = rnd.gauss(-math.pi / 2, 0.8)
        o.append(box("shard", (rnd.uniform(0.05, 0.35), rnd.uniform(0.05, 0.25), 0.012),
                     (math.cos(a) * r, math.sin(a) * r, 0.01), "glass_tank", rot=(rnd.uniform(-0.1, 0.1), 0, rnd.uniform(0, 6)), uv=False))
    # restraint arms hanging open inside
    for sx in (-1, 1):
        o.append(tube("restraint", [(sx * 0.9, 0.4, 3.9), (sx * 0.7, 0.2, 3.0), (sx * 0.9, -0.4, 2.3)], 0.05, "painted_metal", 8))
        o.append(torus("cuff", 0.12, 0.03, (sx * 0.9, -0.45, 2.2), "steel", rot=(0.6, sx * 0.4, 0), seg=24, rseg=8))
    # pressure pipes and torn cables
    for i in range(6):
        a = math.pi / 2 + (i - 2.5) * 0.35
        p0 = (math.cos(a) * 1.9, math.sin(a) * 1.9, 0.9)
        o.append(tube("pipe", [p0, (p0[0] * 1.5, p0[1] * 1.5, 0.9), (p0[0] * 2.0, p0[1] * 2.0, 0.3), (p0[0] * 2.4, p0[1] * 2.4, 0.15)],
                      0.09, "painted_metal" if i % 2 else "copper", 12))
    for i in range(10):
        a = rnd.uniform(0, 2 * math.pi)
        start = (math.cos(a) * 1.4, 0.4 + math.sin(a) * 1.4, 4.3)
        end = (math.cos(a) * rnd.uniform(1.5, 3.5), math.sin(a) * rnd.uniform(1.5, 3.5), 0.05)
        o.append(tube("cable", bezier_points(start, end, ctrl=(start[0] * 1.5, start[1] * 1.5, 2.0), steps=16), 0.025,
                      rnd.choice(["wire_black", "wire_red", "wire_black", "wire_copper"]), 6))
    for i in range(4):
        a = i / 4 * 2 * math.pi + 0.4
        o.append(box("gauge_box", (0.5, 0.3, 0.6), (math.cos(a) * 2.2, math.sin(a) * 2.2, 0.8), "painted_metal", rot=(0, 0, a + math.pi / 2), bevel=0.02))
        g = cyl("gauge", 0.16, 0.03, (math.cos(a) * 2.37, math.sin(a) * 2.37, 0.85), "gauge", rot=(math.pi / 2, 0, a + math.pi / 2), seg=24, uv=False)
        T.planar_uv(g, "Z")
        o.append(g)
    o += blood_splat((0.3, -2.2, 0.012), 0.6, seed=4, count=12)
    o.append(empty("L__core__0", (0, 0.5, 4.2), props={"energy": 3.0, "range": 8.0, "color": [1.0, 0.45, 0.15], "flicker": 0.5}))
    o.append(empty("L__red__0", (0, 0, 0.6), props={"energy": 2.0, "range": 6.0, "color": [1.0, 0.1, 0.05], "pulse": 0.8}))
    return o


@prop()
def cardboard_boxes():
    """Stack of archive boxes, one crushed and spilling files."""
    rnd = random.Random(31)
    o = []
    spots = [(0, 0, 0), (0.48, 0.05, 0), (0.1, 0.02, 0.32), (0.25, -0.5, 0)]
    for k, (x, y, z) in enumerate(spots):
        sq = 0.75 if k == 3 else 1.0
        b = box("box", (0.45, 0.35, 0.3 * sq), (x, y, z + 0.15 * sq), "paper_old", rot=(0, 0, rnd.uniform(-0.2, 0.2)), bevel=0.01)
        o.append(b)
        o.append(box("lid", (0.47, 0.37, 0.04), (x, y, z + 0.3 * sq + 0.01), "paper_old", rot=(0, rnd.uniform(-0.05, 0.05), rnd.uniform(-0.2, 0.2)), bevel=0.005))
        o.append(box("label", (0.12, 0.005, 0.07), (x, y - 0.178, z + 0.17 * sq), "paper", rot=(0, 0, 0)))
    o += scatter_papers(6, (0.4, 0.3), 0.003, seed=31)
    return o


@prop()
def covered_gurney():
    """Gurney with a stained sheet draped over a human shape."""
    o = [box("frame", (2.0, 0.7, 0.06), (0, 0, 0.78), "steel", bevel=0.01)]
    o += legs(0.9, 0.3, 0.72, 0.02, "steel", 0.06)
    for sx in (-1, 1):
        for sy in (-1, 1):
            o.append(cyl("wheel", 0.05, 0.03, (sx * 0.9, sy * 0.3, 0.05), "rubber", rot=(math.pi / 2, 0, 0), seg=14))
    # body volume under the sheet: head, chest, hips, legs, feet
    shapes = [(-0.78, 0.13, 0.11, 0.1), (-0.4, 0.26, 0.16, 0.13), (0.05, 0.24, 0.14, 0.12),
              (0.45, 0.2, 0.1, 0.1), (0.78, 0.16, 0.08, 0.12)]
    for x, ry, rz, rx in shapes:
        o.append(sphere("form", 1.0, (x, 0, 0.83 + rz * 0.6), "fabric", 16, 10, scale=(rx * 2.2, ry, rz)))
    sheet = box("sheet", (2.1, 0.86, 0.03), (0, 0, 0.84), "fabric", bevel=0.01)
    o.append(sheet)
    for sy in (-1, 1):
        o.append(box("drape", (2.05, 0.02, 0.32), (0, sy * 0.44, 0.7), "fabric", rot=(sy * 0.12, 0, 0)))
    o += blood_splat((-0.35, 0.05, 1.0), 0.18, seed=6, count=7)
    o.append(box("toe_tag", (0.05, 0.003, 0.08), (1.02, 0.1, 0.78), "paper_old", rot=(0, 0.3, 0)))
    return o


# ----------------------------------------------------------------- export

def build_all(names=None):
    names = names or list(PROPS)
    for name in names:
        fn, collide = PROPS[name]
        T.reset()
        objs = fn()
        meshes = [o for o in objs if o.type == "MESH"]
        empties = [o for o in objs if o.type == "EMPTY"]
        body = T.join(meshes, name)
        T.shade_smooth(body, 35)
        out = [body] + empties
        if collide:
            bb = [body.matrix_world @ Vector(c) for c in body.bound_box]
            lo = Vector((min(v.x for v in bb), min(v.y for v in bb), max(0.0, min(v.z for v in bb))))
            hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
            size = hi - lo
            if size.z > 0.05:
                out.append(collider(name + "_col", tuple(max(s, 0.02) for s in size), tuple((lo + hi) / 2)))
        T.export_glb(f"assets/models/props/{name}.glb", out)
        T.save_blend(f"source/blender/props/{name}.blend")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build_all(argv or None)
