"""Build the TIMBUK facility architecture and export one GLB per area.

How it works (the short version)
1. Every room, doorway and window is a rectangle ("region") on a 10 cm floor-plan grid.
2. Wherever a region touches empty space we build a wall; where two regions with
   different floor/ceiling heights touch we build the strip of wall above/below
   the opening (door headers, window sills). Floors and ceilings are generated
   from the same grid.
3. Each area then gets hand-placed detail: trims, lights, pipes, signs, and
   markers telling Godot where to drop prop scenes ("P__<prop>__n") and lights
   ("L__<kind>__n").

Run:  blender -b --factory-startup --python source/blender/build_facility.py
"""
import math
import os
import random
import sys
from collections import defaultdict

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import tlib as T  # noqa: E402
from tlib import box, cyl, tube, torus, sphere, bezier_points, empty, collider  # noqa: E402

CELL = 0.1
WALL = 0.3
X0, Y0 = -17.0, -25.0
NX, NY = 460, 1450

AREAS = {
    "A": "area_a_entrance",
    "B": "area_b_research",
    "C": "area_c_containment",
    "D": "area_d_lower",
    "E": "area_e_twin_chamber",
}

# style -> (floor, wall, ceiling, lower band or None)
STYLES = {
    "lab":        ("lab_floor", "wall_panel", "ceiling_tile", "painted_metal"),
    "lobby":      ("lab_floor", "wall_panel", "ceiling_tile", "painted_metal"),
    "industrial": ("concrete", "concrete", "concrete", "painted_metal"),
    "lower":      ("concrete_damaged", "concrete_damaged", "concrete_damaged", None),
    "chamber":    ("concrete_damaged", "concrete", "concrete", "teal_metal"),
    "outdoor":    ("concrete", "concrete", None, None),
    "opening":    (None, "steel", "steel", None),
    "window":     ("painted_metal", "painted_metal", "painted_metal", None),
}


class Region:
    def __init__(self, rid, name, area, rect, floor, h, style, stairs=None, glass=None):
        self.id, self.name, self.area = rid, name, area
        self.rect, self.floor, self.h, self.style = rect, floor, h, style
        self.stairs = stairs          # (z_start, z_end) along +Y
        self.glass = glass            # "intact" | "broken" for window regions

    @property
    def zmin(self):
        return min(self.stairs) if self.stairs else self.floor

    @property
    def zmax(self):
        return (max(self.stairs) if self.stairs else self.floor) + self.h

    def floor_at(self, y):
        if not self.stairs:
            return self.floor
        y0, y1 = self.rect[2], self.rect[3]
        t = min(1, max(0, (y - y0) / (y1 - y0)))
        return self.stairs[0] + (self.stairs[1] - self.stairs[0]) * t


REGIONS = [None]


def region(name, area, rect, floor=0.0, h=3.2, style="lab", **kw):
    r = Region(len(REGIONS), name, area, rect, floor, h, style, **kw)
    REGIONS.append(r)
    return r


# =====================================================================
# Floor plan
# =====================================================================

def define_plan():
    # --- A: entrance
    region("A_outside", "A", (-16, 16, -24, -6.3), 0, 12, "outdoor")
    region("A_door_s", "A", (-1.6, 1.6, -6.3, -6.0), 0, 3.0, "opening")
    region("A_win_w", "A", (-6.5, -3.5, -6.3, -6.0), 1.0, 2.2, "window", glass="broken")
    region("A_win_e", "A", (3.5, 6.5, -6.3, -6.0), 1.0, 2.2, "window", glass="intact")
    region("A_lobby", "A", (-8, 8, -6, 6), 0, 4.5, "lobby")
    region("A_door_n", "A", (-0.8, 0.8, 6.0, 6.3), 0, 2.4, "opening")
    # --- B: research wing
    region("B_corridor", "B", (-1.5, 1.5, 6.3, 26), 0, 3.2, "lab")
    region("B_door_lab1", "B", (1.5, 1.8, 11.2, 12.8), 0, 2.4, "opening")
    region("B_win_lab1", "B", (1.5, 1.8, 14.5, 17.5), 1.0, 1.2, "window", glass="intact")
    region("B_lab1", "B", (1.8, 13.8, 8, 18), 0, 3.2, "lab")
    region("B_door_lab2", "B", (-1.8, -1.5, 23.2, 24.8), 0, 2.4, "opening")
    region("B_win_lab2", "B", (-1.8, -1.5, 19.5, 22), 1.0, 1.2, "window", glass="broken")
    region("B_lab2", "B", (-13.8, -1.8, 18.5, 25.5), 0, 3.2, "lab")
    region("B_vestibule", "B", (-2.6, 2.6, 26, 30), 0, 4.6, "industrial")
    # --- C: containment
    region("C_door_s", "C", (-2.0, 2.0, 30, 30.3), 0, 4.0, "opening")
    region("C_hall", "C", (-11, 11, 30.3, 50.3), 0, 8.0, "industrial")
    region("C_win_ctrl", "C", (-11.3, -11, 37, 43), 4.9, 1.7, "window", glass="broken")
    region("C_door_ctrl", "C", (-11.3, -11, 44.2, 45.2), 4.0, 2.2, "opening")
    region("C_control", "C", (-15.3, -11.3, 36, 45.5), 4.0, 3.0, "lab")
    region("C_door_n", "C", (-1.3, 1.3, 50.3, 50.6), 0, 3.0, "opening")
    # --- D: lower levels
    region("D_stairs", "D", (-1.3, 1.3, 50.6, 62.6), 0, 3.4, "lower", stairs=(0.0, -6.0))
    region("D_corr1", "D", (-1.3, 1.3, 62.6, 78.6), -6, 3.0, "lower")
    region("D_corr2", "D", (1.3, 16.0, 76.0, 78.6), -6, 3.0, "lower")
    region("D_door_room", "D", (7.0, 8.6, 75.7, 76.0), -6, 2.3, "opening")
    region("D_room", "D", (3.5, 12.5, 66.0, 75.7), -6, 3.4, "lower")
    region("D_corr3", "D", (13.4, 16.0, 78.6, 92.0), -6, 3.0, "lower")
    # --- E: twin chamber
    region("E_door", "E", (13.7, 15.7, 92.0, 92.3), -6, 3.0, "opening")
    region("E_chamber", "E", (1.7, 27.7, 92.3, 118.3), -6, 14.0, "chamber")


# =====================================================================
# Grid -> walls / floors / ceilings
# =====================================================================

def ix(x):
    return int(round((x - X0) / CELL))


def iy(y):
    return int(round((y - Y0) / CELL))


def wx(i):
    return X0 + i * CELL


def wy(j):
    return Y0 + j * CELL


def rasterize():
    g = np.zeros((NY, NX), np.int32)
    for r in REGIONS[1:]:
        x0, x1, y0, y1 = r.rect
        g[iy(y0):iy(y1), ix(x0):ix(x1)] = r.id
    return g


def runs(mask_line):
    """Yield (start, end) index runs where mask_line is True."""
    idx = np.flatnonzero(mask_line)
    if idx.size == 0:
        return
    start = prev = idx[0]
    for k in idx[1:]:
        if k != prev + 1:
            yield start, prev + 1
            start = k
        prev = k
    yield start, prev + 1


PIECES = defaultdict(list)       # area -> list of objects (structure, collides)
DETAIL = defaultdict(list)       # area -> list of objects (visual only)
EXTRA = defaultdict(list)        # area -> empties / colliders exported as-is


def put(area, ob, structural=True):
    (PIECES if structural else DETAIL)[area].append(ob)
    return ob


def wall_box(area, axis, line, a0, a1, side, z0, z1, mat, thick=WALL):
    """Wall slab along a grid line. axis='x' means the line is x=const."""
    if z1 - z0 < 0.01 or a1 - a0 < 0.01:
        return None
    off = side * thick / 2
    if axis == "x":
        ob = box("wall", (thick, a1 - a0, z1 - z0), (line + off, (a0 + a1) / 2, (z0 + z1) / 2), mat)
    else:
        ob = box("wall", (a1 - a0, thick, z1 - z0), ((a0 + a1) / 2, line + off, (z0 + z1) / 2), mat)
    return put(area, ob)


def build_boundaries(g):
    """Walls between regions/empty along every grid line."""
    walls = []   # (axis, line, a0, a1, regionA (inside), regionB (other, 0=empty), side towards B)
    # vertical lines x = const: compare columns i-1 and i
    for i in range(1, NX):
        a, b = g[:, i - 1], g[:, i]
        diff = a != b
        if not diff.any():
            continue
        pairs = defaultdict(lambda: np.zeros(NY, bool))
        for j in np.flatnonzero(diff):
            pairs[(a[j], b[j])][j] = True
        for (ra, rb), m in pairs.items():
            for s, e in runs(m):
                walls.append(("x", wx(i), wy(s), wy(e), ra, rb))
    for j in range(1, NY):
        a, b = g[j - 1, :], g[j, :]
        diff = a != b
        if not diff.any():
            continue
        pairs = defaultdict(lambda: np.zeros(NX, bool))
        for i in np.flatnonzero(diff):
            pairs[(a[i], b[i])][i] = True
        for (ra, rb), m in pairs.items():
            for s, e in runs(m):
                walls.append(("y", wy(j), wx(s), wx(e), ra, rb))

    for axis, line, a0, a1, ra, rb in walls:
        A, B = REGIONS[ra], REGIONS[rb]
        # orient so R is filled, O is the other side; side = direction from R to O
        if A is None or (B is not None and A.style == "outdoor"):
            R, O, side = B, A, -1
        else:
            R, O, side = A, B, 1
        if R is None:
            continue
        if O is None:
            # the wall itself comes from build_walls(); here we only add trims
            if R.style not in ("outdoor", "opening", "window") and STYLES[R.style][3]:
                wall_trim(R, axis, line, a0, a1, -side)
            continue
        if O.style == "outdoor" and R.style == "outdoor":
            continue
        if O.style == "outdoor":
            # facade side of an interior region: full height outer skin
            continue
        # filled/filled: headers and footers on the side of the smaller opening
        if R.style in ("opening", "window") or (O.style not in ("opening", "window") and R.zmax <= O.zmax):
            small, big, s = R, O, side
        else:
            small, big, s = O, R, -side
        mat = STYLES[small.style][1] if small.style != "opening" else STYLES[big.style][1]
        # header: wall from small's ceiling up to big's ceiling, inside `small`
        # (starts above small's ceiling slab so faces never overlap)
        if big.zmax > small.zmax + 0.01:
            wall_box(small.area, axis, line, a0, a1, -s, small.zmax + WALL, big.zmax + WALL, mat)
        # footer: from big's floor up to the underside of small's floor slab
        if small.floor > big.zmin + 0.01 and not small.stairs:
            wall_box(small.area, axis, line, a0, a1, -s, big.zmin - WALL, small.floor - WALL, mat)


def shift(a, dy, dx, fill):
    out = np.full_like(a, fill)
    H, W = a.shape
    ys, yd = (slice(0, H - dy), slice(dy, H)) if dy >= 0 else (slice(-dy, H), slice(0, H + dy))
    xs, xd = (slice(0, W - dx), slice(dx, W)) if dx >= 0 else (slice(-dx, W), slice(0, W + dx))
    out[yd, xd] = a[ys, xs]
    return out


def build_walls(g):
    """Fill empty cells within WALL of any room with solid wall, exactly once.

    Each solid cell remembers which room it is closest to (for its material and
    area) and the lowest floor / highest ceiling of every room around it (for
    its height). Cells with the same (owner, bottom, top) are merged into big
    boxes, so shared walls are built once and corners are filled in.
    """
    steps = int(round(WALL / CELL))
    owner = np.zeros_like(g)
    zlo = np.full(g.shape, np.inf)
    zhi = np.full(g.shape, -np.inf)
    room_owner = np.zeros_like(g)
    for r in REGIONS[1:]:
        if r.style == "outdoor":
            continue
        m = g == r.id
        zlo[m] = r.zmin - WALL
        zhi[m] = r.zmax + WALL
        owner[m] = r.id
        if r.style not in ("opening", "window"):
            room_owner[m] = r.id
    empty_cells = g == 0
    nbrs = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]
    for _ in range(steps):
        new_lo, new_hi = zlo.copy(), zhi.copy()
        new_own, new_room = owner.copy(), room_owner.copy()
        for dy, dx in nbrs:
            new_lo = np.minimum(new_lo, shift(zlo, dy, dx, np.inf))
            new_hi = np.maximum(new_hi, shift(zhi, dy, dx, -np.inf))
            so, sr = shift(owner, dy, dx, 0), shift(room_owner, dy, dx, 0)
            take = empty_cells & (new_own == 0) & (so > 0)
            new_own[take] = so[take]
            take = empty_cells & (new_room == 0) & (sr > 0)
            new_room[take] = sr[take]
        keep = empty_cells
        zlo = np.where(keep, new_lo, zlo)
        zhi = np.where(keep, new_hi, zhi)
        owner = np.where(keep, new_own, owner)
        room_owner = np.where(keep, new_room, room_owner)
    solid = empty_cells & (owner > 0)
    final_owner = np.where(room_owner > 0, room_owner, owner)
    key = np.where(solid, (final_owner.astype(np.int64) * 2000 + np.round((zlo + 50) * 10).astype(np.int64)) * 2000
                   + np.round((zhi + 50) * 10).astype(np.int64), 0)
    groups = defaultdict(list)
    for val in np.unique(key[solid]):
        groups[int(val)] = None
    count = 0
    for val in groups:
        m = key == val
        js, is_ = np.nonzero(m)
        oid = int(final_owner[js[0], is_[0]])
        r = REGIONS[oid]
        mat = STYLES[r.style][1] if r.style not in ("opening",) else "steel"
        for i0, i1, j0, j1 in greedy_rects(m):
            sub_lo = zlo[j0:j1, i0:i1]
            sub_hi = zhi[j0:j1, i0:i1]
            z0, z1 = float(sub_lo.min()), float(sub_hi.max())
            x0, x1, y0, y1 = wx(i0), wx(i1), wy(j0), wy(j1)
            put(r.area, box("wall", (x1 - x0, y1 - y0, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), mat))
            count += 1
    print("wall boxes:", count)


def wall_trim(R, axis, line, a0, a1, inward):
    """Lower wall band, rail and skirting on the inside face of a wall."""
    band_mat = STYLES[R.style][3]
    if R.stairs:
        return
    z = R.floor
    t = 0.025
    off = inward * t / 2
    def strip(h0, h1, thick, mat):
        if axis == "x":
            ob = box("trim", (thick, a1 - a0, h1 - h0), (line + inward * thick / 2, (a0 + a1) / 2, z + (h0 + h1) / 2), mat)
        else:
            ob = box("trim", (a1 - a0, thick, h1 - h0), ((a0 + a1) / 2, line + inward * thick / 2, z + (h0 + h1) / 2), mat)
        put(R.area, ob, structural=False)
    if R.style in ("lab", "lobby"):
        strip(0.0, 1.05, t, band_mat)
        strip(1.05, 1.11, 0.05, "steel")
        strip(0.0, 0.12, 0.04, "rubber")
    elif R.style == "industrial":
        strip(0.0, 1.6, t, band_mat)
        strip(1.6, 1.75, 0.03, "hazard")
    elif R.style == "chamber":
        strip(0.0, 2.4, t, band_mat)


def greedy_rects(mask):
    """Split a boolean grid into a few big rectangles (rows of runs merged)."""
    mask = mask.copy()
    rects = []
    H, W = mask.shape
    for j in range(H):
        i = 0
        while i < W:
            if not mask[j, i]:
                i += 1
                continue
            i1 = i
            while i1 < W and mask[j, i1]:
                i1 += 1
            j1 = j + 1
            while j1 < H and mask[j1, i:i1].all():
                j1 += 1
            mask[j:j1, i:i1] = False
            rects.append((i, i1, j, j1))
            i = i1
    return rects


def build_floors(g):
    for r in REGIONS[1:]:
        if r.stairs:
            build_stairs(r)
            continue
        fmat, _, cmat, _ = STYLES[r.style]
        mask = g == r.id
        for i0, i1, j0, j1 in greedy_rects(mask):
            x0, x1, y0, y1 = wx(i0), wx(i1), wy(j0), wy(j1)
            cx, cy, sx, sy = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
            if r.style == "outdoor":
                put(r.area, box("ground", (sx, sy, 1.0), (cx, cy, r.floor - 0.5), fmat))
                continue
            put(r.area, box("floor", (sx, sy, WALL), (cx, cy, r.floor - WALL / 2), fmat or "concrete"))
        cmask = mask.copy()
        for hx0, hx1, hy0, hy1, hz in HOLES:
            if abs(hz - (r.floor + r.h)) < 0.05:
                cmask[iy(hy0):iy(hy1), ix(hx0):ix(hx1)] = False
        for i0, i1, j0, j1 in ([] if r.style == "outdoor" else greedy_rects(cmask)):
            x0, x1, y0, y1 = wx(i0), wx(i1), wy(j0), wy(j1)
            cx, cy, sx, sy = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
            put(r.area, box("ceiling", (sx, sy, WALL), (cx, cy, r.floor + r.h + WALL / 2), cmat or "concrete"))
        if r.style == "opening":
            door_frame(r)
        if r.style == "window":
            x0, x1, y0, y1 = r.rect
            thin_x = (x1 - x0) < (y1 - y0)
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            z0, z1 = r.floor, r.floor + r.h
            add_glass(r, cx, cy, thin_x, (y1 - y0) if thin_x else (x1 - x0), z0, z1)


def door_frame(r):
    """Steel liners inside the opening and an architrave on both faces."""
    x0, x1, y0, y1 = r.rect
    thin_x = (x1 - x0) < (y1 - y0)
    z0, z1 = r.floor, r.floor + r.h
    depth = (x1 - x0) if thin_x else (y1 - y0)
    width = (y1 - y0) if thin_x else (x1 - x0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    t, f = 0.03, 0.09
    def B(size_along, size_across, size_z, along, across, z):
        if thin_x:
            return box("frame", (size_across, size_along, size_z), (cx + across, cy + along, z), "steel")
        return box("frame", (size_along, size_across, size_z), (cx + along, cy + across, z), "steel")
    for sgn in (-1, 1):
        put(r.area, B(t, depth, z1 - z0, sgn * (width / 2 - t / 2), 0, (z0 + z1) / 2), structural=False)
        for face in (-1, 1):
            put(r.area, B(f, 0.04, z1 - z0 + f, sgn * (width / 2 + f / 2), face * (depth / 2 + 0.02), (z0 + z1 + f) / 2), structural=False)
    put(r.area, B(width, depth, t, 0, 0, z1 - t / 2), structural=False)
    for face in (-1, 1):
        put(r.area, B(width + 2 * f, 0.04, f, 0, face * (depth / 2 + 0.02), z1 + f / 2), structural=False)


def add_glass(r, cx, cy, thin_x, length, z0, z1):
    rnd = random.Random(r.id)
    # frame
    for zz in (z0 + 0.03, z1 - 0.03):
        size = (0.12, length, 0.06) if thin_x else (length, 0.12, 0.06)
        put(r.area, box("wframe", size, (cx, cy, zz), "steel"), structural=False)
    n_mull = max(1, int(length / 1.5))
    for k in range(n_mull + 1):
        t = -length / 2 + k * length / n_mull
        loc = (cx, cy + t, (z0 + z1) / 2) if thin_x else (cx + t, cy, (z0 + z1) / 2)
        size = (0.12, 0.06, z1 - z0) if thin_x else (0.06, 0.12, z1 - z0)
        put(r.area, box("mullion", size, loc, "steel"), structural=False)
    if r.glass == "intact":
        size = (0.02, length, z1 - z0) if thin_x else (length, 0.02, z1 - z0)
        put(r.area, box("glass", size, (cx, cy, (z0 + z1) / 2), "glass"), structural=False)
    else:
        # jagged teeth left in the frame + shards on both sides of the sill
        for k in range(int(length / 0.25)):
            t = -length / 2 + 0.125 + k * 0.25
            hb = rnd.uniform(0.05, 0.45)
            ht = rnd.uniform(0.05, 0.3)
            for zc, hh in ((z0 + hb / 2, hb), (z1 - ht / 2, ht)):
                loc = (cx, cy + t, zc) if thin_x else (cx + t, cy, zc)
                size = (0.02, 0.23, hh) if thin_x else (0.23, 0.02, hh)
                put(r.area, box("glass", size, loc, "glass", rot=(rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05), 0)), structural=False)
        for k in range(18):
            t = rnd.uniform(-length / 2, length / 2)
            d = rnd.choice((-1, 1)) * rnd.uniform(0.2, 1.4)
            # high control-room window: the -x side is the control room floor
            floor_z = 0.0 if r.floor < 4 else (4.0 if d < 0 else 0.0)
            loc = (cx + d, cy + t, floor_z + 0.006) if thin_x else (cx + t, cy + d, floor_z + 0.006)
            put(r.area, box("shard", (rnd.uniform(0.04, 0.2), rnd.uniform(0.04, 0.15), 0.008), loc, "glass",
                            rot=(0, 0, rnd.uniform(0, 6))), structural=False)
    # invisible collision so you can't walk through window frames
    size = (0.3, length, z1 - z0) if thin_x else (length, 0.3, z1 - z0)
    EXTRA[r.area].append(collider(r.name, size, (cx, cy, (z0 + z1) / 2)))


REGIONS_BY_NAME = {}
HOLES = []   # (x0, x1, y0, y1, z_ceiling): cut out of ceilings, plenum built above


def hole(x0, x1, y0, y1, z):
    r = lambda v: round(v * 10) / 10
    HOLES.append((r(x0), r(x1), r(y0), r(y1), z))


def build_plenum(area, x0, x1, y0, y1, z, seed):
    """Open-bottomed dark cavity above a ceiling hole: ducts, cables, torn tiles."""
    d = 0.9
    t = 0.05
    cx, cy, sx, sy = (x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0
    put(area, box("plenum_top", (sx + 0.2, sy + 0.2, t), (cx, cy, z + WALL + d), "concrete_damaged"), structural=False)
    for (px, py, wx_, wy_) in ((x0 - t / 2, cy, t, sy + 0.2), (x1 + t / 2, cy, t, sy + 0.2),
                               (cx, y0 - t / 2, sx + 0.2, t), (cx, y1 + t / 2, sx + 0.2, t)):
        put(area, box("plenum_side", (wx_, wy_, d + WALL), (px, py, z + (d + WALL) / 2), "concrete_damaged"), structural=False)
    rnd = random.Random(seed)
    put(area, box("duct", (sx + 0.2, 0.45, 0.35), (cx, cy + rnd.uniform(-0.2, 0.2) * sy, z + WALL + 0.45), "steel"), structural=False)
    for k in range(3):
        a = (x0 + 0.05, rnd.uniform(y0, y1), z + WALL + rnd.uniform(0.1, 0.6))
        b = (x1 - 0.05, rnd.uniform(y0, y1), z + WALL + rnd.uniform(0.1, 0.6))
        put(area, tube("plenum_cable", bezier_points(a, b, sag=0.15, steps=8), 0.015, "wire_black", 6), structural=False)
    # torn tile flaps hanging from the edge
    for k in range(2):
        ex = rnd.uniform(x0 + 0.2, x1 - 0.2)
        put(area, box("tile_flap", (0.55, 0.012, 0.5), (ex, y0 + 0.02, z - 0.22), "ceiling_tile",
                      rot=(rnd.uniform(0.2, 0.5), 0, rnd.uniform(-0.2, 0.2))), structural=False)


def build_stairs(r):
    x0, x1, y0, y1 = r.rect
    za, zb = r.stairs
    n = int(round(abs(zb - za) / 0.25))
    run = (y1 - y0) / n
    rise = (zb - za) / n
    w = x1 - x0
    cx = (x0 + x1) / 2
    for k in range(n):
        top = za + rise * (k + 1) if rise > 0 else za + rise * k
        y_mid = y0 + run * (k + 0.5)
        h = top - min(za, zb) + 0.3
        put(r.area, box("step", (w, run, h), (cx, y_mid, top - h / 2), "concrete_damaged"), structural=False)
        put(r.area, box("nosing", (w, 0.05, 0.02), (cx, y0 + run * k + 0.025, top + 0.01), "hazard"), structural=False)
    # sloped ceiling slab and ramp collider (smooth for character controllers)
    length = math.hypot(y1 - y0, zb - za)
    ang = math.atan2(zb - za, y1 - y0)
    put(r.area, box("stair_ceiling", (w, length + 0.6, WALL), (cx, (y0 + y1) / 2, (za + zb) / 2 + r.h + WALL / 2),
                    "concrete_damaged", rot=(ang, 0, 0)), structural=False)
    EXTRA[r.area].append(collider(r.name + "_ramp", (w, length + 0.2, 0.2),
                                  (cx, (y0 + y1) / 2, (za + zb) / 2 - 0.1 - 0.125), rot=(ang, 0, 0)))
    # handrails
    for sx in (-1, 1):
        x = cx + sx * (w / 2 - 0.08)
        pts = [(x, y0 + 0.2, za + 0.95), (x, y1 - 0.2, zb + 0.95)]
        put(r.area, tube("handrail", pts, 0.025, "steel", 8), structural=False)
        for k in range(0, n, 4):
            y = y0 + run * (k + 0.5)
            z = za + rise * (k + 1)
            put(r.area, cyl("post", 0.02, 0.95, (x, y, z + 0.47), "steel", seg=8), structural=False)


# =====================================================================
# Markers
# =====================================================================

_COUNT = defaultdict(int)


def P(area, prop_name, loc, rz=0.0, rx=0.0, ry=0.0):
    """Marker for a prop instance (Godot builder drops scenes/props/<name>.tscn here)."""
    k = _COUNT[prop_name]
    _COUNT[prop_name] += 1
    EXTRA[area].append(empty(f"P__{prop_name}__{k}", loc, (rx, ry, rz)))


def L(area, kind, loc, rot=(0, 0, 0), **props):
    k = _COUNT["L" + kind]
    _COUNT["L" + kind] += 1
    EXTRA[area].append(empty(f"L__{kind}__{k}", loc, rot, props=props))


def V(area, name, loc, look_at):
    """Named viewpoint used by the inspection scene's camera hotkeys."""
    # glTF turns Blender +Y into Godot -Z (forward) and Blender +Z into Godot +Y (up)
    d = Vector(look_at) - Vector(loc)
    rot = d.to_track_quat("Y", "Z").to_euler()
    EXTRA[area].append(empty(f"VIEW__{name}", loc, tuple(rot)))


# =====================================================================
# Shared detail kits
# =====================================================================

def ceiling_lights(area, rect, z_ceiling, spacing=(3.0, 2.4), seed=0, broken=0.25, off=0.15):
    """Recessed fluorescent troffers on a grid, some flickering, dead or fallen."""
    rnd = random.Random(seed)
    x0, x1, y0, y1 = rect
    nx = max(1, int((x1 - x0) / spacing[0]))
    ny = max(1, int((y1 - y0) / spacing[1]))
    for a in range(nx):
        for b in range(ny):
            x = x0 + (a + 0.5) * (x1 - x0) / nx
            y = y0 + (b + 0.5) * (y1 - y0) / ny
            roll = rnd.random()
            if roll < broken * 0.4:
                # fixture fell: real hole in the ceiling, fixture dangling out of it
                hole(x - 0.3, x + 0.3, y - 0.6, y + 0.6, z_ceiling)
                build_plenum(area, *HOLES[-1][:4], z_ceiling, seed + a * 7 + b)
                P(area, "hanging_light_broken", (x, y + 0.3, z_ceiling), rz=rnd.uniform(-0.4, 0.4))
                continue
            put(area, box("troffer", (0.62, 1.22, 0.06), (x, y, z_ceiling - 0.02), "steel"), structural=False)
            lit = roll > off + broken * 0.4
            put(area, box("diffuser", (0.54, 1.12, 0.02), (x, y, z_ceiling - 0.055), "light_fluor" if lit else "light_fluor_off"),
                structural=False)
            if lit:
                flick = 0.0 if rnd.random() > broken else rnd.uniform(0.3, 0.9)
                L(area, "fluor", (x, y, z_ceiling - 0.35), flicker=flick)


def ceiling_vent(area, x, y, z):
    put(area, box("vent", (0.6, 0.6, 0.04), (x, y, z - 0.02), "steel"), structural=False)
    for k in range(7):
        put(area, box("slat", (0.52, 0.03, 0.03), (x, y - 0.24 + k * 0.08, z - 0.05), "painted_white", rot=(0.5, 0, 0)), structural=False)


def pipe_run(area, pts, r=0.08, mat="painted_metal", brackets=2.0, bracket_to=None):
    put(area, tube("pipe", pts, r, mat, 14), structural=False)
    # flanges at each joint
    for p in pts[1:-1]:
        put(area, sphere("elbow", r * 1.15, p, mat, 14, 8), structural=False)
    for p0, p1 in zip(pts, pts[1:]):
        p0, p1 = Vector(p0), Vector(p1)
        L_ = (p1 - p0).length
        nseg = int(L_ / brackets)
        for k in range(1, nseg + 1):
            p = p0 + (p1 - p0) * (k / (nseg + 1))
            d = (p1 - p0).normalized()
            rot = d.to_track_quat("Z", "Y").to_euler()
            put(area, cyl("flange", r * 1.3, 0.04, tuple(p), "steel", rot=tuple(rot), seg=14), structural=False)
            if bracket_to is not None:
                top = Vector((p.x, p.y, bracket_to))
                put(area, tube("hanger", [tuple(p), tuple(top)], 0.012, "steel", 6), structural=False)


def hanging_cables(area, x0, x1, y0, y1, z, count, seed, sag=(0.3, 1.2)):
    rnd = random.Random(seed)
    for i in range(count):
        a = (rnd.uniform(x0, x1), rnd.uniform(y0, y1), z)
        b = (a[0] + rnd.uniform(-2.5, 2.5), a[1] + rnd.uniform(-2.5, 2.5), z)
        put(area, tube("cable", bezier_points(a, b, sag=rnd.uniform(*sag), steps=14), rnd.uniform(0.01, 0.025),
                       rnd.choice(["wire_black", "wire_black", "wire_red", "rubber"]), 6), structural=False)


def dangling_cables(area, x, y, z_top, length, count, seed):
    rnd = random.Random(seed)
    for i in range(count):
        ox, oy = rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3)
        end = (x + ox * 3, y + oy * 3, z_top - length * rnd.uniform(0.6, 1.0))
        pts = bezier_points((x + ox, y + oy, z_top), end, ctrl=(x + ox * 2, y + oy * 2, z_top - length * 0.3), steps=10)
        put(area, tube("dangle", pts, rnd.uniform(0.008, 0.02), rnd.choice(["wire_black", "wire_red", "wire_copper"]), 6), structural=False)


def floor_decal(area, rect, z, mat="hazard"):
    x0, x1, y0, y1 = rect
    put(area, box("decal", (x1 - x0, y1 - y0, 0.004), ((x0 + x1) / 2, (y0 + y1) / 2, z + 0.002), mat), structural=False)


def wall_sign_text(area, text, loc, rot, size=0.35, mat="painted_white", extrude=0.02, backing=None):
    """3D text sign (Blender text converted to mesh)."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = extrude
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.bevel_depth = extrude * 0.25
    ob = bpy.data.objects.new("sign_" + text[:8], cu)
    T.link(ob)
    ob.location = loc
    ob.rotation_euler = rot
    bpy.context.view_layer.objects.active = ob
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mob = bpy.data.objects.new("sign_" + text[:8], me)
    T.link(mob)
    mob.matrix_world = ob.matrix_world
    bpy.data.objects.remove(ob)
    me.materials.append(T.mat(mat))
    T.world_uv(mob)
    put(area, mob, structural=False)
    return mob


def column(area, x, y, z0, h, w=0.5, mat="concrete", band=None):
    put(area, box("column", (w, w, h), (x, y, z0 + h / 2), mat, bevel=0.02))
    if band:
        put(area, box("col_band", (w + 0.03, w + 0.03, 1.5), (x, y, z0 + 0.75), band), structural=False)


# =====================================================================
# Areas
# =====================================================================

def area_a():
    a = "A"
    # ---- exterior: facade, sign, canopy, lamps
    fz = 9.0
    for x0, x1 in ((-12, -6.5), (-3.5, -1.6), (1.6, 3.5), (6.5, 12)):
        put(a, box("facade", (x1 - x0, 0.6, fz), ((x0 + x1) / 2, -6.6, fz / 2), "concrete"))
    put(a, box("facade_top", (24, 0.6, fz - 3.2), (0, -6.6, 3.2 + (fz - 3.2) / 2), "concrete"))
    put(a, box("facade_sill_w", (3.0, 0.6, 1.0), (-5, -6.6, 0.5), "concrete"))
    put(a, box("facade_sill_e", (3.0, 0.6, 1.0), (5, -6.6, 0.5), "concrete"))
    put(a, box("facade_door_top", (3.2, 0.6, 0.2), (0, -6.6, 3.1), "concrete"))
    put(a, box("parapet", (24.4, 0.9, 0.4), (0, -6.6, fz + 0.2), "painted_metal"))
    for x in (-12, -8, 8, 12):
        put(a, box("pilaster", (0.7, 0.4, fz), (x, -7.0, fz / 2), "concrete", bevel=0.02))
    # canopy over the entrance
    put(a, box("canopy", (6.0, 3.2, 0.3), (0, -8.4, 3.9), "painted_metal", bevel=0.02))
    put(a, box("canopy_edge", (6.1, 0.1, 0.45), (0, -10.0, 3.85), "steel"))
    for x in (-2.7, 2.7):
        put(a, cyl("canopy_post", 0.09, 3.8, (x, -9.8, 1.9), "steel", seg=14))
    L(a, "spot", (0, -8.6, 3.7), rot=(0, 0, 0), energy=3.0, range=7.0, color=[0.75, 0.85, 1.0], spot=60, flicker=0.4, shadow=True)
    # TIMBUK sign: backlit letters on a steel band, two letters dead
    put(a, box("sign_band", (11.0, 0.3, 2.0), (0, -7.05, 6.4), "painted_metal", bevel=0.03))
    letters = "TIMBUK"
    for k, ch in enumerate(letters):
        x = -4.1 + k * 1.64
        dead = ch in ("M", "U")
        wall_sign_text(a, ch, (x, -7.25, 6.45), (math.pi / 2, 0, 0), size=1.55,
                       mat="steel" if dead else "light_red", extrude=0.1)
        if not dead:
            L(a, "sign", (x, -7.8, 6.4), energy=1.2, range=4.5, color=[1.0, 0.12, 0.06], flicker=0.25 if ch == "K" else 0.0)
    wall_sign_text(a, "RESEARCH  INSTITUTE  OF  TEMPORAL  BIOLOGY", (0, -7.25, 5.15), (math.pi / 2, 0, 0), size=0.32,
                   mat="steel", extrude=0.03)
    # ground details: curb, puddles, barrier, lamps
    put(a, box("curb", (32, 0.3, 0.15), (0, -14, 0.075), "concrete"))
    put(a, box("steps", (8, 2.0, 0.15), (0, -7.9, 0.075), "concrete", bevel=0.01))
    rnd = random.Random(3)
    for i in range(7):
        put(a, cyl("puddle", rnd.uniform(0.6, 1.8), 0.004, (rnd.uniform(-12, 12), rnd.uniform(-22, -10), 0.003),
                   "glass", seg=24, smooth=False), structural=False)
    P(a, "street_lamp", (-7.5, -12.5, 0), rz=math.pi)
    P(a, "street_lamp", (7.5, -12.5, 0), rz=math.pi)
    P(a, "jersey_barrier", (-3.5, -16, 0), rz=0.15)
    P(a, "jersey_barrier", (2.8, -17, 0), rz=-0.4)
    P(a, "chem_barrel", (-9.5, -8.2, 0))
    P(a, "chem_barrel_leaking", (-10.3, -9.0, 0), rz=0.6)
    P(a, "debris_pile", (5.5, -9.0, 0))
    P(a, "papers_scattered", (1.0, -11.5, 0), rz=0.7)
    P(a, "warning_sign_plate", (-1.9, -6.95, 1.7))
    put(a, box("chainfence_w", (0.06, 10, 2.4), (-16, -15, 1.2), "steel"), structural=False)
    put(a, box("chainfence_e", (0.06, 10, 2.4), (16, -15, 1.2), "steel"), structural=False)
    # broken glass doors in the main entrance
    for x, ang in ((-0.8, 0.0), (1.25, -1.2)):
        put(a, box("glassdoor_frame", (1.5, 0.08, 2.9), (x, -6.15, 1.45), "steel"), structural=False)
    put(a, box("glassdoor_glass", (1.3, 0.02, 2.6), (-0.8, -6.15, 1.45), "glass"), structural=False)
    V(a, "entrance_exterior", (0.0, -21.0, 1.7), (0, -6, 4.5))

    # ---- lobby
    lob = (-8, 8, -6, 6)
    ceiling_lights(a, (-7, 7, -5, 5), 4.5, spacing=(3.5, 3.3), seed=11, broken=0.35, off=0.2)
    for x in (-4, 4):
        column(a, x, 0, 0, 4.5, 0.6, "wall_panel", band="painted_metal")
    ceiling_vent(a, -2, -3.5, 4.5)
    ceiling_vent(a, 5.5, 3.5, 4.5)
    # hole in the ceiling with debris and dangling cables below it
    hole(-6.5, -4.5, 2.7, 4.3, 4.5)
    build_plenum(a, -6.5, -4.5, 2.7, 4.3, 4.5, 99)
    dangling_cables(a, -5.5, 3.5, 4.5, 2.6, 6, seed=1)
    P(a, "debris_pile", (-5.5, 3.5, 0))
    P(a, "ceiling_tile_fallen", (-4.4, 2.3, 0))
    # logo wall behind reception
    put(a, box("logo_panel", (6.0, 0.08, 1.4), (0, 5.95, 3.45), "teal_metal", bevel=0.02), structural=False)
    wall_sign_text(a, "TIMBUK", (-0.8, 5.88, 3.45), (math.pi / 2, 0, 0), size=0.75, mat="brass", extrude=0.05)
    P(a, "wall_clock", (2.4, 5.9, 3.45), rz=0)
    P(a, "security_desk", (0, 0.6, 0))
    P(a, "office_chair", (0.4, 2.1, 0), rz=2.6)
    P(a, "office_chair", (-1.6, 3.0, 0.25), rz=1.0, rx=1.57)       # knocked over
    P(a, "security_gate", (0, 4.4, 0))
    P(a, "security_door", (0, 6.15, 0))
    P(a, "emergency_beacon", (0, 5.98, 2.7))
    P(a, "warning_sign_plate", (1.5, 5.97, 1.7))
    P(a, "bench_seating", (-7.3, -2.0, 0), rz=-math.pi / 2)
    P(a, "bench_seating", (-7.3, 1.5, 0), rz=-math.pi / 2)
    P(a, "bench_seating", (7.3, -1.0, 0), rz=math.pi / 2)
    P(a, "filing_cabinet", (6.0, 5.6, 0), rz=math.pi)
    P(a, "filing_cabinet", (6.6, 5.6, 0), rz=math.pi)
    P(a, "storage_cabinet", (-7.6, 4.8, 0), rz=-math.pi / 2)
    P(a, "papers_scattered", (2.5, -1.5, 0), rz=0.3)
    P(a, "papers_scattered", (-2.0, 2.5, 0), rz=2.0)
    P(a, "blood_trail", (0.8, 4.0, 0), rz=0.15)
    P(a, "chem_barrel", (6.8, -4.8, 0))
    P(a, "office_desk", (5.6, 3.6, 0), rz=math.pi)
    P(a, "computer_terminal", (5.3, 3.6, 0.76), rz=math.pi)
    P(a, "photo_frame", (6.1, 3.5, 0.76), rz=math.pi + 0.3)
    V(a, "lobby", (-5.5, -4.8, 1.7), (1.5, 4.0, 1.4))


def area_b():
    a = "B"
    # ---- corridor
    ceiling_lights(a, (-1.5, 1.5, 6.3, 26), 3.2, spacing=(3.0, 3.0), seed=21, broken=0.4, off=0.25)
    pipe_run(a, [(-1.25, 6.4, 2.95), (-1.25, 25.9, 2.95)], 0.07, "painted_metal", 2.5)
    pipe_run(a, [(-1.05, 6.4, 3.0), (-1.05, 25.9, 3.0)], 0.04, "copper", 3.0)
    for y in (9.5, 20.5):
        P(a, "wall_clock", (-1.45, y, 2.3), rz=-math.pi / 2)
    P(a, "electrical_panel", (-1.5, 15.5, 0), rz=-math.pi / 2)
    P(a, "cart_trolley", (-0.8, 13.0, 0), rz=0.3)
    P(a, "iv_stand", (0.9, 19.0, 0))
    P(a, "office_chair", (0.6, 22.5, 0.25), rx=1.57, rz=0.4)
    P(a, "papers_scattered", (0.0, 17.0, 0), rz=1.2)
    P(a, "blood_trail", (-0.2, 12.5, 0), rz=-0.3)
    P(a, "warning_sign_plate", (1.47, 13.6, 1.6), rz=math.pi / 2)
    P(a, "emergency_beacon", (1.47, 25.5, 2.6), rz=math.pi / 2)
    wall_sign_text(a, "RESEARCH  LAB  1  >", (1.47, 9.8, 2.2), (math.pi / 2, 0, -math.pi / 2), size=0.16, mat="painted_white", extrude=0.01)
    wall_sign_text(a, "<  OBSERVATION  2", (-1.47, 22.6, 2.2), (math.pi / 2, 0, math.pi / 2), size=0.16, mat="painted_white", extrude=0.01)
    V(a, "corridor", (0.0, 7.5, 1.65), (0.3, 20, 1.3))

    # ---- lab 1 (research)
    ceiling_lights(a, (1.8, 13.8, 8, 18), 3.2, spacing=(3.0, 2.5), seed=31, broken=0.3, off=0.4)
    ceiling_vent(a, 7.5, 13.0, 3.2)
    for k, (x, y) in enumerate(((5.5, 11.0), (9.5, 11.0), (5.5, 14.8), (9.5, 14.8))):
        P(a, "lab_table", (x, y, 0), rz=0.0 if k != 3 else 0.35)
    P(a, "microscope", (5.0, 11.0, 0.92), rz=0.2)
    P(a, "chem_bottles", (6.1, 11.1, 0.92))
    P(a, "computer_terminal", (9.2, 11.0, 0.92), rz=0.15)
    P(a, "centrifuge", (10.1, 11.1, 0.92), rz=-0.3)
    P(a, "chem_bottles", (5.3, 14.8, 0.92), rz=1.4)
    P(a, "monitor_broken", (9.6, 14.8, 0.92), rz=0.9)
    P(a, "lab_bench_sink", (5.0, 17.6, 0), rz=math.pi)
    P(a, "lab_bench_sink", (9.8, 17.6, 0), rz=math.pi)
    P(a, "storage_cabinet", (13.5, 9.5, 0), rz=math.pi / 2)
    P(a, "storage_cabinet", (13.5, 10.6, 0), rz=math.pi / 2)
    P(a, "server_rack", (13.4, 15.6, 0), rz=math.pi / 2)
    P(a, "server_rack", (13.4, 16.3, 0), rz=math.pi / 2)
    P(a, "filing_cabinet", (2.2, 8.5, 0), rz=-math.pi / 2)
    P(a, "office_chair", (8.0, 12.6, 0), rz=2.0)
    P(a, "office_chair", (7.0, 9.5, 0.25), rx=-1.57, rz=0.2)
    P(a, "papers_scattered", (7.5, 13.0, 0), rz=0.5)
    P(a, "exam_bed", (11.5, 8.8, 0), rz=0.05)
    P(a, "gas_cylinders", (3.0, 17.6, 0), rz=math.pi)
    P(a, "chem_bottles", (4.3, 17.55, 0.95), rz=math.pi)
    P(a, "microscope", (5.6, 17.5, 0.95), rz=math.pi + 0.3)
    P(a, "centrifuge", (9.2, 17.45, 0.95), rz=math.pi)
    P(a, "chem_bottles", (10.6, 17.55, 0.95), rz=2.0)
    P(a, "lab_table", (12.0, 13.0, 0.4), rz=0.3, rx=1.45)          # flipped on its side
    P(a, "debris_pile", (11.2, 12.0, 0))
    P(a, "cardboard_boxes", (2.5, 13.2, 0), rz=0.4)
    P(a, "cardboard_boxes", (12.9, 17.2, 0), rz=2.0)
    P(a, "blood_trail", (11.0, 13.5, 0), rz=-2.2)
    P(a, "wall_clock", (7.5, 17.95, 2.4), rz=math.pi)
    pipe_run(a, [(2.0, 17.7, 2.9), (13.6, 17.7, 2.9)], 0.06, "painted_white", 2.5)
    V(a, "lab1", (12.9, 8.7, 1.7), (5.0, 15.5, 0.9))

    # ---- lab 2 (human experimentation / observation)
    ceiling_lights(a, (-13.8, -1.8, 18.5, 25.5), 3.2, spacing=(3.0, 2.4), seed=41, broken=0.45, off=0.6)
    P(a, "restraint_chair", (-8.0, 22.0, 0), rz=-0.4)
    P(a, "surgical_lamp", (-8.4, 21.8, 3.2), rz=0.3)
    P(a, "exam_bed", (-11.8, 19.6, 0))
    P(a, "exam_bed", (-11.8, 24.4, 0), rz=0.12)
    P(a, "iv_stand", (-10.4, 19.3, 0))
    P(a, "cart_trolley", (-6.6, 23.0, 0), rz=1.1)
    P(a, "storage_cabinet", (-4.0, 25.2, 0), rz=math.pi)
    P(a, "office_desk", (-3.4, 19.2, 0), rz=0)
    P(a, "computer_terminal", (-3.6, 19.3, 0.76))
    P(a, "photo_frame", (-2.9, 19.1, 0.76), rz=0.4)
    P(a, "filing_cabinet", (-13.5, 22.0, 0), rz=-math.pi / 2)
    P(a, "papers_scattered", (-7.0, 20.0, 0), rz=2.2)
    P(a, "blood_trail", (-8.0, 21.0, 0), rz=2.6)
    P(a, "monitor_broken", (-5.0, 24.9, 0.92 - 0.92), rz=math.pi + 0.6)
    P(a, "chem_bottles", (-6.6, 23.0, 0.87))
    P(a, "warning_sign_plate", (-13.75, 20.5, 1.6), rz=-math.pi / 2)
    P(a, "covered_gurney", (-5.4, 20.6, 0), rz=1.3)
    P(a, "cardboard_boxes", (-13.2, 25.0, 0), rz=0.2)
    P(a, "chem_barrel", (-2.4, 25.0, 0))
    P(a, "debris_pile", (-10.0, 24.0, 0))
    V(a, "lab2", (-3.0, 24.6, 1.7), (-9.5, 20.5, 0.9))

    # ---- vestibule before the blast door
    L(a, "red", (0, 28.0, 4.2), energy=2.0, range=7.0, pulse=1.0)
    L(a, "fluor", (0, 27.0, 4.3), flicker=0.8)
    put(a, box("vest_light", (1.2, 0.3, 0.06), (0, 27.0, 4.57), "light_fluor"), structural=False)
    floor_decal(a, (-2.0, 2.0, 29.3, 29.9), 0.0, "hazard")
    P(a, "gas_cylinders", (-2.0, 27.0, 0), rz=-math.pi / 2)
    P(a, "chem_barrel", (2.1, 26.6, 0))
    P(a, "chem_barrel", (1.9, 27.3, 0))
    P(a, "warning_sign_plate", (2.57, 28.5, 1.8), rz=math.pi / 2)
    P(a, "pipe_valve", (-2.5, 28.8, 1.3), rz=-math.pi / 2)
    pipe_run(a, [(-2.4, 26.1, 4.2), (-2.4, 29.8, 4.2)], 0.12, "rust", 1.5)
    pipe_run(a, [(2.35, 26.1, 3.9), (2.35, 29.8, 3.9)], 0.09, "painted_metal", 1.5)
    V(a, "vestibule", (0, 26.5, 1.7), (0, 31, 2.0))


def area_c():
    a = "C"
    hall = (-11, 11, 30.3, 50.3)
    P(a, "blast_door", (0, 30.15, 0))
    # structure: pilasters, ceiling beams, crane rail
    for y in np.arange(32.3, 50.0, 4.0):
        for x in (-10.75, 10.75):
            column(a, x, y, 0, 8.0, 0.5, "concrete", band="painted_metal")
        put(a, box("beam", (22, 0.35, 0.6), (0, y, 7.7), "painted_metal"), structural=False)
        put(a, box("beam_flange", (22, 0.5, 0.06), (0, y, 7.4), "painted_metal"), structural=False)
    for x in (-6, 6):
        put(a, box("crane_rail", (0.3, 20, 0.4), (x, 40.3, 7.2), "rust"), structural=False)
    put(a, box("crane_bridge", (12.6, 0.8, 0.7), (0, 44.5, 6.8), "hazard", bevel=0.02), structural=False)
    put(a, box("crane_hoist", (0.9, 0.9, 0.7), (1.5, 44.5, 6.2), "painted_metal", bevel=0.03), structural=False)
    put(a, tube("crane_chain", [(1.5, 44.5, 5.9), (1.4, 44.4, 2.8)], 0.03, "steel", 6), structural=False)
    put(a, torus("crane_hook", 0.18, 0.04, (1.4, 44.4, 2.6), "rust", rot=(math.pi / 2, 0, 0), seg=20, rseg=8), structural=False)
    # high-bay lamps hanging from the beams
    rnd = random.Random(51)
    for y in (34.3, 40.3, 46.3):
        for x in (-5.5, 0.0, 5.5):
            put(a, tube("lamp_rod", [(x, y, 7.4), (x, y, 6.0)], 0.015, "steel", 6), structural=False)
            put(a, cyl("lamp_shade", 0.45, 0.4, (x, y, 5.85), "painted_metal", r2=0.15, seg=20), structural=False)
            dead = rnd.random() < 0.3
            put(a, cyl("lamp_lens", 0.4, 0.02, (x, y, 5.65), "light_fluor_off" if dead else "light_fluor", seg=20), structural=False)
            if not dead:
                L(a, "highbay", (x, y, 5.5), energy=4.0, range=11.0, spot=75, shadow=(x == 0.0),
                  flicker=0.5 if rnd.random() < 0.25 else 0.0, color=[0.78, 0.9, 1.0])
    # emergency beacons on walls
    for x, y, rz in ((-10.45, 33.0, -math.pi / 2), (10.45, 39.0, math.pi / 2), (-10.45, 48.0, -math.pi / 2), (10.45, 47.0, math.pi / 2)):
        P(a, "emergency_beacon", (x, y, 4.0), rz=rz)
    # pipes along both long walls + vertical drops
    pipe_run(a, [(10.3, 30.6, 6.4), (10.3, 50.0, 6.4)], 0.18, "painted_metal", 2.0)
    pipe_run(a, [(10.0, 30.6, 6.9), (10.0, 50.0, 6.9)], 0.1, "copper", 2.0)
    pipe_run(a, [(-10.3, 30.6, 6.6), (-10.3, 50.0, 6.6)], 0.14, "rust", 2.0)
    for y in (36.0, 44.0):
        pipe_run(a, [(10.3, y, 6.4), (10.3, y, 1.4), (9.6, y, 0.6)], 0.12, "painted_metal", 1.5)
        P(a, "pipe_valve", (10.05, y, 1.6), rz=math.pi / 2)
    # tanks along the east wall
    for k, y in enumerate((34.0, 38.6, 43.2, 47.6)):
        P(a, "containment_tank_broken" if k in (1, 3) else "containment_tank", (8.3, y, 0), rz=rnd.uniform(0, 6))
    # centerpiece
    P(a, "failed_containment_device", (0.0, 41.0, 0), rz=0.0)
    floor_decal(a, (-4.2, 4.2, 36.6, 36.9), 0.0)
    floor_decal(a, (-4.2, 4.2, 45.1, 45.4), 0.0)
    floor_decal(a, (-4.2, -3.9, 36.6, 45.4), 0.0)
    floor_decal(a, (3.9, 4.2, 36.6, 45.4), 0.0)
    hanging_cables(a, -9, 9, 32, 49, 7.3, 14, seed=5)
    dangling_cables(a, 0.0, 41.0, 7.4, 2.3, 8, seed=7)
    # catwalk and stairs on the west side up to the control room door
    cw_z = 4.0
    put(a, box("catwalk", (1.6, 14.0, 0.1), (-10.2, 40.5, cw_z - 0.05), "steel"))
    for y in np.arange(34.0, 47.6, 1.0):
        put(a, box("cw_joist", (1.6, 0.08, 0.15), (-10.2, y, cw_z - 0.15), "painted_metal"), structural=False)
    for y in np.arange(34.0, 47.6, 2.7):
        put(a, cyl("cw_post", 0.06, cw_z, (-9.45, y, cw_z / 2), "painted_metal", seg=10), structural=False)
    put(a, tube("cw_rail", [(-9.45, 33.5, cw_z + 1.05), (-9.45, 47.5, cw_z + 1.05)], 0.03, "hazard", 8), structural=False)
    put(a, tube("cw_rail2", [(-9.45, 33.5, cw_z + 0.55), (-9.45, 47.5, cw_z + 0.55)], 0.02, "steel", 8), structural=False)
    for y in np.arange(33.5, 47.6, 1.0):
        put(a, cyl("cw_baluster", 0.015, 1.05, (-9.45, y, cw_z + 0.52), "steel", seg=6), structural=False)
    EXTRA[a].append(collider("catwalk_rail", (0.1, 14.0, 1.1), (-9.45, 40.5, cw_z + 0.55)))
    # stairs from the hall floor (south) up to the catwalk
    n = 16
    for k in range(n):
        z = (k + 1) * cw_z / n
        y = 33.5 - (n - k) * 0.28 + 0.14
        put(a, box("cw_step", (1.2, 0.28, 0.04), (-10.2, y, z - 0.02), "steel"), structural=False)
    put(a, tube("cw_stair_rail", [(-9.6, 33.5 - n * 0.28, 1.0), (-9.6, 33.5, cw_z + 1.0)], 0.025, "hazard", 8), structural=False)
    stair_len = math.hypot(n * 0.28, cw_z)
    EXTRA[a].append(collider("cw_stair_ramp", (1.2, stair_len, 0.1),
                             (-10.2, 33.5 - n * 0.28 / 2, cw_z / 2 - 0.05), rot=(math.atan2(cw_z, n * 0.28), 0, 0)))
    # cluttered floor
    P(a, "chem_barrel", (-6.5, 31.5, 0))
    P(a, "chem_barrel", (-5.9, 31.2, 0), rz=1.0)
    P(a, "chem_barrel_leaking", (-6.8, 32.6, 0), rz=-0.8)
    P(a, "gas_cylinders", (6.0, 31.0, 0))
    P(a, "server_rack", (-8.4, 49.5, 0), rz=math.pi)
    P(a, "server_rack", (-7.8, 49.5, 0), rz=math.pi)
    P(a, "electrical_panel", (5.0, 50.25, 0), rz=math.pi)
    P(a, "debris_pile", (4.0, 47.0, 0))
    P(a, "debris_pile", (-5.0, 38.0, 0))
    P(a, "cart_trolley", (3.6, 35.0, 0), rz=0.7)
    P(a, "papers_scattered", (-2.0, 34.0, 0), rz=0.4)
    P(a, "blood_trail", (0.5, 37.5, 0), rz=math.pi + 0.2)
    P(a, "warning_sign_plate", (1.5, 50.25, 1.8), rz=math.pi)
    wall_sign_text(a, "CONTAINMENT  HALL  C", (0, 30.62, 6.0), (math.pi / 2, 0, math.pi), size=0.6, mat="painted_white", extrude=0.03)
    wall_sign_text(a, "SUBLEVEL  ACCESS", (0, 49.98, 3.6), (math.pi / 2, 0, 0), size=0.25, mat="hazard", extrude=0.02)
    V(a, "containment", (6.5, 31.8, 2.4), (-1.0, 42.0, 2.0))
    V(a, "centerpiece", (2.8, 34.0, 1.6), (0.0, 41.0, 2.2))

    # ---- control room above
    ceiling_lights(a, (-15.3, -11.3, 36, 45.5), 7.0, spacing=(2.5, 3.2), seed=61, broken=0.5, off=0.3)
    P(a, "office_desk", (-12.0, 39.0, 4.0), rz=-math.pi / 2)
    P(a, "office_desk", (-12.0, 41.4, 4.0), rz=-math.pi / 2)
    P(a, "computer_terminal", (-11.9, 38.6, 4.76), rz=-math.pi / 2)
    P(a, "monitor_broken", (-11.9, 39.4, 4.76), rz=-math.pi / 2 + 0.3)
    P(a, "computer_terminal", (-11.9, 41.2, 4.76), rz=-math.pi / 2)
    P(a, "photo_frame", (-12.2, 42.0, 4.76), rz=-math.pi / 2 - 0.4)
    P(a, "office_chair", (-13.0, 39.2, 4.0), rz=-1.2)
    P(a, "office_chair", (-13.4, 41.8, 4.25), rx=1.57, rz=0.5)
    P(a, "server_rack", (-14.9, 37.0, 4.0), rz=-math.pi / 2)
    P(a, "filing_cabinet", (-14.9, 43.0, 4.0), rz=-math.pi / 2)
    P(a, "papers_scattered", (-13.5, 40.5, 4.0))
    V(a, "control_room", (-14.6, 44.8, 5.7), (-10.0, 39.0, 4.0))


def area_d():
    a = "D"
    rnd = random.Random(71)
    L(a, "red", (0, 56.0, -2.0), energy=1.5, range=6.0, pulse=0.7)
    L(a, "cage", (0, 61.5, -3.3), energy=1.2, range=6.0, color=[1.0, 0.6, 0.3], flicker=0.6)
    put(a, sphere("cage_bulb", 0.07, (0, 61.5, -3.15), "light_amber", 10, 6), structural=False)
    pipe_run(a, [(1.05, 50.8, 3.0), (1.05, 62.4, -3.0)], 0.08, "rust", 2.0)
    L(a, "fluor", (0, 51.2, 2.6), flicker=0.7)
    put(a, box("stair_top_light", (1.2, 0.3, 0.06), (0, 51.2, 3.37), "light_fluor"), structural=False)
    for k, y in enumerate((53.5, 57.0, 60.5)):
        z = -(y - 50.6) / 12.0 * 6.0 + 2.2
        put(a, sphere("stair_bulb", 0.06, (-1.2, y, z), "light_amber" if k != 1 else "light_fluor_off", 10, 6), structural=False)
        if k != 1:
            L(a, "cage", (-1.0, y, z), energy=1.4, range=6.0, color=[1.0, 0.62, 0.32], flicker=0.3 * k)
    V(a, "stairs_down", (0, 51.2, 1.6), (0, 60, -4.0))

    def caged_lamp(x, y, z, face, dead=False, flick=0.0):
        put(a, cyl("lamp_base", 0.08, 0.06, (x, y, z), "painted_metal", rot=face, seg=12), structural=False)
        put(a, sphere("lamp_bulb", 0.06, (x, y, z), "light_fluor_off" if dead else "light_amber", 10, 6), structural=False)
        put(a, torus("lamp_cage", 0.08, 0.008, (x, y, z), "steel", rot=face, seg=16, rseg=6), structural=False)
        if not dead:
            L(a, "cage", (x, y, z - 0.1), energy=1.6, range=6.5, color=[1.0, 0.62, 0.32], flicker=flick)

    # corridor 1 (south-north)
    for y in np.arange(64.0, 78.0, 3.5):
        caged_lamp(-1.2, y, -3.6, (0, math.pi / 2, 0), dead=rnd.random() < 0.3, flick=rnd.choice([0, 0, 0.5, 0.9]))
    pipe_run(a, [(1.05, 62.7, -3.25), (1.05, 77.0, -3.25), (2.0, 77.4, -3.25), (15.5, 77.4, -3.25)], 0.1, "rust", 2.0)
    pipe_run(a, [(0.75, 62.7, -3.35), (0.75, 78.4, -3.35)], 0.05, "copper", 2.0)
    hanging_cables(a, -1.0, 1.0, 63, 77, -3.05, 8, seed=8, sag=(0.2, 0.8))
    for y in (66.5, 70.0, 73.5):
        P(a, "wall_clock", (-1.27, y, -4.4 + rnd.uniform(-0.4, 0.4)), rz=-math.pi / 2 + rnd.uniform(-0.2, 0.2))
    P(a, "debris_pile", (0.4, 68.0, -6))
    P(a, "papers_scattered", (-0.2, 72.0, -6), rz=1.1)
    P(a, "chem_barrel", (0.9, 64.0, -6))
    P(a, "chem_barrel_leaking", (0.6, 75.3, -6), rz=2.2)
    P(a, "blood_trail", (0.0, 77.0, -6), rz=math.pi / 2)
    V(a, "lower_corridor", (0.0, 63.5, -4.35), (0.3, 75.0, -4.6))

    # corridor 2 (west-east)
    for x in np.arange(3.0, 15.5, 3.5):
        caged_lamp(x, 78.5, -3.6, (math.pi / 2, 0, 0), dead=rnd.random() < 0.35, flick=rnd.choice([0, 0.4, 0.9]))
    hanging_cables(a, 2, 15, 76.2, 78.4, -3.05, 7, seed=9, sag=(0.2, 0.9))
    P(a, "cart_trolley", (11.0, 77.0, -6), rz=1.4)
    P(a, "electrical_panel", (15.95, 77.3, -6), rz=math.pi / 2)
    wall_sign_text(a, "B-7   SUBJECT  HOUSING", (8.0, 78.55, -3.8), (math.pi / 2, 0, 0), size=0.14, mat="hazard", extrude=0.01)

    # subject housing room (the twins' room)
    ceiling_lights(a, (3.5, 12.5, 66.0, 75.7), -2.6, spacing=(3.0, 3.3), seed=81, broken=0.6, off=0.4)
    P(a, "cot", (5.0, 73.6, -6), rz=0.0)
    P(a, "cot", (7.0, 73.6, -6), rz=0.04)
    P(a, "teddy_bear", (5.25, 73.6, -5.49), rz=0.6)
    P(a, "restraint_chair", (10.0, 70.0, -6), rz=0.8)
    P(a, "iv_stand", (10.9, 70.6, -6))
    P(a, "office_desk", (5.0, 67.0, -6), rz=math.pi)
    P(a, "photo_frame", (4.6, 66.9, -5.24), rz=math.pi + 0.3)
    P(a, "photo_frame", (5.3, 67.0, -5.24), rz=math.pi - 0.2)
    P(a, "computer_terminal", (5.6, 67.1, -5.24), rz=math.pi)
    P(a, "filing_cabinet", (3.85, 69.0, -6), rz=-math.pi / 2)
    P(a, "papers_scattered", (7.0, 69.5, -6), rz=0.2)
    P(a, "storage_cabinet", (12.2, 74.0, -6), rz=math.pi / 2)
    # the clock wall: many stopped clocks on the west wall
    for k in range(14):
        P(a, "wall_clock", (3.53, 67.4 + (k % 7) * 1.15 + rnd.uniform(-0.15, 0.15), -4.9 + (k // 7) * 0.9 + rnd.uniform(-0.15, 0.15)),
          rz=-math.pi / 2 + rnd.uniform(-0.1, 0.1))
    V(a, "subject_room", (11.6, 67.0, -4.3), (5.5, 73.0, -5.3))

    # corridor 3 (towards the chamber): distortion, clocks, darker
    for y in np.arange(80.0, 91.5, 3.8):
        caged_lamp(16.0 - 0.05, y, -3.6, (0, -math.pi / 2, 0), dead=rnd.random() < 0.4, flick=rnd.choice([0.5, 0.9]))
    hanging_cables(a, 13.6, 15.8, 79, 91.5, -3.05, 10, seed=10, sag=(0.3, 1.4))
    for y in np.arange(80.5, 91.0, 1.6):
        put(a, box("rib", (2.6, 0.18, 0.18), (14.7, y, -3.1), "rust"), structural=False)
        for x in (13.48, 15.92):
            put(a, box("rib_side", (0.16, 0.18, 3.0), (x, y, -4.5), "rust"), structural=False)
    for k in range(5):
        P(a, "wall_clock", (13.45, 81.0 + k * 2.2, -4.5 + (k % 2) * 0.5), rz=-math.pi / 2 + (k - 2) * 0.25)
    P(a, "debris_pile", (14.2, 86.0, -6))
    P(a, "blood_trail", (14.9, 91.0, -6), rz=0.0)
    L(a, "chamber_spill", (14.7, 91.6, -3.6), energy=2.0, range=6.0, color=[1.0, 0.45, 0.15], flicker=0.2)
    V(a, "chamber_approach", (14.7, 80.0, -4.35), (14.7, 92.0, -4.6))


def area_e():
    a = "E"
    cx, cy = 14.7, 105.3
    zf = -6.0
    H = 14.0
    # corner buttresses -> octagonal feel
    for sx in (-1, 1):
        for sy in (-1, 1):
            put(a, box("corner", (6.5, 6.5, H), (cx + sx * 13.0, cy + sy * 13.0, zf + H / 2), "concrete",
                       rot=(0, 0, math.pi / 4)))
    # ribbed wall columns
    for k in range(16):
        ang = k / 16 * 2 * math.pi
        r = 12.6
        x, y = cx + math.cos(ang) * r, cy + math.sin(ang) * r
        if abs(x - cx) > 12.9 or abs(y - cy) > 12.9:
            continue
        put(a, box("rib", (0.7, 0.9, H), (x, y, zf + H / 2), "teal_metal", rot=(0, 0, ang)), structural=False)
    # stepped circular dais
    for k, (r, h) in enumerate(((7.0, 0.3), (5.6, 0.6), (4.2, 0.9))):
        put(a, cyl("dais", r, h, (cx, cy + 1.5, zf + h / 2), "concrete" if k < 2 else "teal_metal", seg=64, smooth=False))
        put(a, torus("dais_trim", r, 0.05, (cx, cy + 1.5, zf + h), "brass", seg=96, rseg=8), structural=False)
    platform_z = zf + 0.9
    put(a, cyl("platform_grate", 3.0, 0.04, (cx, cy + 1.5, platform_z + 0.02), "steel", seg=48), structural=False)
    for k in range(12):
        ang = k / 12 * 2 * math.pi
        put(a, box("platform_light", (0.25, 0.08, 0.03), (cx + math.cos(ang) * 3.6, cy + 1.5 + math.sin(ang) * 3.6, platform_z + 0.015),
                   "light_amber" if k % 3 else "light_red", rot=(0, 0, ang)), structural=False)
    # broken containment cylinder around the platform
    rnd = random.Random(91)
    for k in range(40):
        ang = k / 40 * 2 * math.pi
        if -0.9 < math.sin(ang) < -0.2 and abs(math.cos(ang)) < 0.75:
            continue   # the front is blown open toward the entrance
        h = rnd.uniform(0.5, 4.5) if math.sin(ang) < 0.3 else rnd.uniform(3.0, 6.0)
        put(a, box("cont_glass", (0.82, 0.03, h), (cx + math.cos(ang) * 3.3, cy + 1.5 + math.sin(ang) * 3.3, platform_z + h / 2),
                   "glass_tank", rot=(0, 0, ang + math.pi / 2)), structural=False)
    for k in range(10):
        ang = k / 10 * 2 * math.pi
        put(a, cyl("cont_strut", 0.07, 7.0, (cx + math.cos(ang) * 3.4, cy + 1.5 + math.sin(ang) * 3.4, platform_z + 3.5),
                   "brass" if k % 2 else "teal_metal", seg=10), structural=False)
    put(a, torus("cont_top_ring", 3.4, 0.22, (cx, cy + 1.5, platform_z + 7.0), "teal_metal", seg=96, rseg=12), structural=False)
    put(a, torus("cont_top_ring2", 3.6, 0.08, (cx, cy + 1.5, platform_z + 7.3), "brass", seg=96, rseg=8), structural=False)
    for k in range(70):
        ang = rnd.gauss(-math.pi / 2, 0.6)
        r = rnd.uniform(3.6, 9.0)
        put(a, box("shard", (rnd.uniform(0.05, 0.4), rnd.uniform(0.05, 0.3), 0.012),
                   (cx + math.cos(ang) * r, cy + 1.5 + math.sin(ang) * r, zf + (0.31 if r < 7 else 0.01)),
                   "glass_tank", rot=(0, 0, rnd.uniform(0, 6))), structural=False)
    # giant clock on the back wall
    clock_c = (cx, cy + 12.5, zf + 8.0)
    face = cyl("giant_clock_face", 4.6, 0.25, clock_c, "porcelain", rot=(math.pi / 2, 0, 0), seg=96, uv=False)
    T.planar_uv(face, "Z")
    put(a, face, structural=False)
    put(a, torus("giant_clock_rim", 4.75, 0.3, (clock_c[0], clock_c[1] - 0.15, clock_c[2]), "brass", rot=(math.pi / 2, 0, 0), seg=128, rseg=14), structural=False)
    put(a, torus("giant_clock_rim2", 5.2, 0.12, (clock_c[0], clock_c[1] - 0.1, clock_c[2]), "teal_metal", rot=(math.pi / 2, 0, 0), seg=128, rseg=8), structural=False)
    put(a, box("hour_hand", (0.28, 0.06, 2.6), (clock_c[0] - 0.75, clock_c[1] - 0.25, clock_c[2] + 0.75), "black_cavity", rot=(0, 0.79, 0)), structural=False)
    put(a, box("minute_hand", (0.18, 0.06, 3.9), (clock_c[0] + 0.2, clock_c[1] - 0.3, clock_c[2] - 1.6), "black_cavity", rot=(0, math.pi - 0.12, 0)), structural=False)
    put(a, cyl("clock_pin", 0.3, 0.4, (clock_c[0], clock_c[1] - 0.4, clock_c[2]), "brass", rot=(math.pi / 2, 0, 0)), structural=False)
    # cracks radiating from the clock (dark strips)
    for k in range(7):
        ang = rnd.uniform(0, 2 * math.pi)
        L_ = rnd.uniform(1.0, 3.5)
        put(a, box("clock_crack", (0.04, 0.02, L_), (clock_c[0] + math.cos(ang) * (1.2 + L_ / 2), clock_c[1] - 0.14,
                                                   clock_c[2] + math.sin(ang) * (1.2 + L_ / 2)), "black_cavity", rot=(0, -ang + math.pi / 2, 0)), structural=False)
    # gear machinery flanking the clock
    for sx in (-1, 1):
        gx = cx + sx * 8.0
        for k, (r, z) in enumerate(((2.2, zf + 9.5), (1.4, zf + 5.8), (0.9, zf + 11.8))):
            g = (gx + sx * k * 0.6, cy + 12.4, z)
            put(a, cyl("gear", r, 0.35, g, "brass" if k != 1 else "copper", rot=(math.pi / 2, 0, 0), seg=48), structural=False)
            teeth = int(r * 14)
            for t in range(teeth):
                ang = t / teeth * 2 * math.pi
                put(a, box("tooth", (0.22, 0.35, 0.25), (g[0] + math.cos(ang) * (r + 0.1), g[1], g[2] + math.sin(ang) * (r + 0.1)),
                           "brass" if k != 1 else "copper", rot=(0, -ang, 0)), structural=False)
            put(a, cyl("axle", 0.18, 0.9, (g[0], g[1] - 0.3, g[2]), "steel", rot=(math.pi / 2, 0, 0), seg=16), structural=False)
    # overhead machinery: big ring gantry and cables down to the platform
    put(a, torus("gantry_ring", 6.5, 0.35, (cx, cy + 1.5, zf + 12.2), "painted_metal", seg=96, rseg=12), structural=False)
    for k in range(6):
        ang = k / 6 * 2 * math.pi + 0.3
        put(a, tube("gantry_arm", [(cx + math.cos(ang) * 6.5, cy + 1.5 + math.sin(ang) * 6.5, zf + 12.2),
                                   (cx + math.cos(ang) * 11.5, cy + 1.5 + math.sin(ang) * 11.5, zf + 13.6)], 0.22, "painted_metal", 10),
            structural=False)
    put(a, cyl("core_emitter", 1.4, 2.2, (cx, cy + 1.5, zf + 10.6), "copper", r2=0.6, seg=40), structural=False)
    for k in range(6):
        put(a, torus("emitter_coil", 1.2 - k * 0.1, 0.07, (cx, cy + 1.5, zf + 9.8 + k * 0.32), "copper", seg=48, rseg=6), structural=False)
    put(a, sphere("emitter_tip", 0.35, (cx, cy + 1.5, zf + 9.4), "eye_glow", 20, 12), structural=False)
    for k in range(18):
        ang = rnd.uniform(0, 2 * math.pi)
        start = (cx + math.cos(ang) * rnd.uniform(1.0, 6.0), cy + 1.5 + math.sin(ang) * rnd.uniform(1.0, 6.0), zf + 12.1)
        end = (cx + math.cos(ang) * rnd.uniform(2.6, 3.2), cy + 1.5 + math.sin(ang) * rnd.uniform(2.6, 3.2), platform_z + 0.05)
        put(a, tube("chamber_cable", bezier_points(start, end, ctrl=(start[0] * 0.6 + end[0] * 0.4, start[1] * 0.6 + end[1] * 0.4, zf + 6.0), steps=20),
                    rnd.uniform(0.03, 0.08), rnd.choice(["wire_black", "wire_black", "rubber", "wire_red", "wire_copper"]), 8), structural=False)
    hanging_cables(a, 4, 25, 95, 116, zf + 13.9, 12, seed=12, sag=(0.8, 2.5))
    # side machinery and storytelling
    P(a, "containment_tank_broken", (5.5, 112.0, zf), rz=0.4)
    P(a, "containment_tank", (23.9, 112.0, zf), rz=1.2)
    P(a, "server_rack", (3.0, 102.0, zf), rz=-math.pi / 2)
    P(a, "server_rack", (3.0, 102.7, zf), rz=-math.pi / 2)
    P(a, "electrical_panel", (27.65, 101.0, zf), rz=math.pi / 2)
    P(a, "gas_cylinders", (26.9, 106.0, zf), rz=math.pi / 2)
    P(a, "restraint_chair", (20.5, 97.2, zf), rz=-0.9)
    P(a, "cart_trolley", (8.4, 97.0, zf), rz=0.5)
    P(a, "papers_scattered", (11.0, 97.5, zf), rz=0.9)
    P(a, "debris_pile", (22.0, 95.5, zf))
    P(a, "blood_trail", (14.6, 98.5, zf), rz=0.0)
    for x in (4.5, 25.0):
        P(a, "emergency_beacon", (x, 92.6, zf + 4.5), rz=math.pi)
    # lighting: key spot on the platform, rim lights, clock wash
    for k in range(10):
        ang = k / 10 * 2 * math.pi + 0.31
        px, py = cx + math.cos(ang) * 11.6, cy + math.sin(ang) * 11.6
        if abs(px - cx) > 12.4 or abs(py - cy) > 12.4 or (py < cy - 10 and abs(px - cx) < 3):
            continue
        put(a, box("uplight", (0.4, 0.3, 0.2), (px, py, zf + 0.1), "painted_metal"), structural=False)
        put(a, box("uplight_lens", (0.34, 0.24, 0.02), (px, py, zf + 0.21), "light_amber"), structural=False)
        L(a, "uplight", (px, py, zf + 0.4), aim=[px + math.cos(ang) * 0.6, py + math.sin(ang) * 0.6, zf + 8.0])
    for sx in (-1, 1):
        L(a, "chamber_high", (cx + sx * 6.0, cy + 2.0, zf + 12.5))
    L(a, "reveal_key", (cx - 4.0, cy - 5.0, zf + 9.0), energy=16.0, range=22.0, spot=38, shadow=True, color=[1.0, 0.86, 0.72],
      aim=[cx, cy + 1.5, platform_z + 1.6])
    L(a, "reveal_rim", (cx + 3.5, cy + 6.5, zf + 6.0), energy=10.0, range=14.0, spot=35, shadow=True, color=[0.4, 0.75, 1.0],
      aim=[cx, cy + 1.5, platform_z + 1.8])
    L(a, "reveal_fill", (cx, cy - 3.0, platform_z + 1.0), energy=1.4, range=7.0, color=[1.0, 0.45, 0.2])
    L(a, "clock_wash", (cx, cy + 7.0, zf + 3.0), energy=6.0, range=14.0, spot=55, color=[1.0, 0.8, 0.55],
      aim=[cx, cy + 12.4, zf + 8.0])
    L(a, "emitter", (cx, cy + 1.5, zf + 9.0), energy=3.0, range=10.0, color=[1.0, 0.35, 0.08], flicker=0.3)
    for sx in (-1, 1):
        L(a, "red", (cx + sx * 10.5, cy - 9.5, zf + 6.0), energy=2.5, range=12.0, pulse=0.5)
    EXTRA[a].append(empty("REVEAL__monster", (cx, cy + 1.5, platform_z), (0, 0, math.pi)))
    V(a, "chamber_entrance", (14.7, 93.5, -4.3), (14.7, 106.8, -3.5))
    V(a, "reveal", (14.7, 100.6, -3.9), (14.7, 106.8, -3.6))
    V(a, "chamber_overview", (20.5, 95.8, 1.5), (13.5, 110.0, -2.5))
    V(a, "giant_clock", (14.7, 104.0, -2.0), (14.7, 117.8, 2.0))


# =====================================================================
# Main
# =====================================================================

def export_area(key):
    name = AREAS[key]
    structure = T.join(PIECES[key], f"{name}_structure-col")
    detail = T.join(DETAIL[key], f"{name}_detail")
    objs = [o for o in (structure, detail) if o] + EXTRA[key]
    for o in (structure, detail):
        if o:
            T.shade_smooth(o, 30)
    T.export_glb(f"assets/models/environment/{name}.glb", objs)


def main():
    T.reset()
    define_plan()
    for r in REGIONS[1:]:
        REGIONS_BY_NAME[r.name] = r
    g = rasterize()
    build_walls(g)
    build_boundaries(g)
    area_a()
    area_b()
    area_c()
    area_d()
    area_e()
    build_floors(g)
    for r in REGIONS[1:]:
        if r.style in ("opening", "window"):
            continue
        x0, x1, y0, y1 = r.rect
        h = r.zmax - r.zmin
        EXTRA[r.area].append(empty(f"ROOM__{r.name}", ((x0 + x1) / 2, (y0 + y1) / 2, r.zmin + h / 2),
                                   props={"size": [x1 - x0, y1 - y0, h], "style": r.style}))
    T.save_blend("source/blender/environment/timbuk_facility.blend")
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(AREAS)
    for k in wanted:
        export_area(k)


if __name__ == "__main__":
    main()
