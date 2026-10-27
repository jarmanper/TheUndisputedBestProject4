"""Generate every tileable PBR texture set used by TIMBUK.

Run from the repo root:  python3 source/textures/texgen.py [name ...]
Writes assets/textures/<name>_albedo.png, _rough.png, _normal.png and,
where a material needs them, _metal.png and _emit.png.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from texlib import *  # noqa: E402,F403
import texlib as T  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures")
REGISTRY = {}


def tex(fn):
    REGISTRY[fn.__name__] = fn
    return fn


def write(name, albedo, rough, height=None, normal_strength=4.0, metal=None, emit=None, normal=None):
    save_png(os.path.join(OUT, f"{name}_albedo.png"), albedo)
    save_png(os.path.join(OUT, f"{name}_rough.png"), rough)
    if normal is None and height is not None:
        normal = normal_from_height(height, normal_strength)
    if normal is not None:
        save_png(os.path.join(OUT, f"{name}_normal.png"), normal)
    if metal is not None:
        save_png(os.path.join(OUT, f"{name}_metal.png"), metal)
    if emit is not None:
        save_png(os.path.join(OUT, f"{name}_emit.png"), emit)


def grime_layers(n):
    """Shared dirt ingredients: big blotches, medium mottling, fine speckle."""
    big = fbm(n, 2.6, lo=1)
    mid = fbm(n, 2.0, lo=3)
    fine = fbm(n, 1.2, lo=24)
    return big, mid, fine


# ====================================================================
# Architecture
# ====================================================================

@tex
def concrete():
    T.seed(1)
    n = 1024
    big, mid, fine = grime_layers(n)
    f1, edge, _ = worley(n, 900)
    pores = remap(f1, 0.0, 0.12)            # tiny dark pits
    pits = 1.0 - pores
    stains = smooth(remap(big, 0.55, 0.85))
    drip = smooth(remap(fbm(n, 2.2, lo=2, stretch=(1, 7)), 0.55, 0.9))
    base = lerp(srgb("8a8986"), srgb("a3a19c"), mid)
    base = base * (0.92 + 0.16 * fine[:, :, None])
    base = lerp(base, srgb("5d5a54"), stains * 0.55)
    base = lerp(base, srgb("4a463f"), drip * 0.45)
    base = base * (1.0 - pits[:, :, None] * 0.35)
    h = mid * 0.4 + fine * 0.35 - pits * 0.6
    rough = 0.82 + 0.12 * fine - stains * 0.15 - drip * 0.1
    write("concrete", base, rough, h, 3.0)


@tex
def concrete_damaged():
    """Lower-level concrete: cracked, water damaged, darker."""
    T.seed(2)
    n = 1024
    big, mid, fine = grime_layers(n)
    f1, edge, _ = worley(n, 40)
    cracks = 1.0 - remap(edge, 0.0, 0.012)
    cracks *= smooth(remap(fbm(n, 2.0, lo=2), 0.45, 0.65))   # only some edges crack
    p1, _, _ = worley(n, 1200)
    pits = 1.0 - remap(p1, 0, 0.13)
    wet = smooth(remap(big, 0.5, 0.8))
    moss = smooth(remap(fbm(n, 2.4, lo=2), 0.7, 0.95)) * wet
    base = lerp(srgb("6c6a65"), srgb("85827b"), mid)
    base = base * (0.9 + 0.2 * fine[:, :, None])
    base = lerp(base, srgb("3b3833"), wet * 0.6)
    base = lerp(base, srgb("3e4a33"), moss * 0.5)
    base = base * (1 - cracks[:, :, None] * 0.75) * (1 - pits[:, :, None] * 0.35)
    h = mid * 0.5 + fine * 0.3 - cracks * 1.2 - pits * 0.5
    rough = 0.85 + 0.1 * fine - wet * 0.55
    write("concrete_damaged", base, np.clip(rough, 0.18, 1), h, 3.5)


@tex
def lab_floor():
    """Worn vinyl lab tiles, 4x4 per texture (0.6 m tiles at 2.4 m repeat)."""
    T.seed(3)
    n = 1024
    big, mid, fine = grime_layers(n)
    cells = 4
    grout = grid_lines(n, cells, 5, 2.0)
    yy, xx = np.mgrid[0:n, 0:n]
    tid = (yy * cells // n) * cells + (xx * cells // n)
    tint = RNG.random(cells * cells)[tid]
    speck = remap(fbm(n, 0.6, lo=60), 0.62, 0.8)          # terrazzo-like chips
    scuff = smooth(remap(fbm(n, 2.0, lo=6, stretch=(6, 1)), 0.7, 0.95))
    dirt = smooth(remap(big, 0.45, 0.85))
    wet = smooth(remap(fbm(n, 3.0, lo=1), 0.72, 0.9))
    base = lerp(srgb("9ea39d"), srgb("b6b9b0"), tint * 0.6 + mid * 0.4)
    base = lerp(base, srgb("6d706a"), speck * 0.5)
    base = lerp(base, srgb("4b4a44"), dirt * 0.55)
    base = lerp(base, srgb("3c3934"), scuff * 0.35)
    base = lerp(base, srgb("2b2924"), grout * 0.9)
    base = base * (1 - wet[:, :, None] * 0.25)
    h = 1.0 - grout * 0.9 - scuff * 0.08 + fine * 0.05
    rough = 0.55 + 0.25 * dirt + 0.15 * grout - wet * 0.45 + scuff * 0.1
    write("lab_floor", base, np.clip(rough, 0.08, 1), h, 3.0)


@tex
def wall_panel():
    """Pale institutional wall panels: 2 x 2 panels per 2.4 m, screws, grime."""
    T.seed(4)
    n = 1024
    big, mid, fine = grime_layers(n)
    seams = grid_lines(n, 2, 4, 1.5)
    # screws at panel corners (inset)
    screws = np.zeros((n, n))
    for cx in (0.04, 0.46, 0.54, 0.96):
        for cy in (0.04, 0.46, 0.54, 0.96):
            screws = np.maximum(screws, disc(n, cx, cy, 0.006))
    streak = smooth(remap(fbm(n, 2.0, lo=3, stretch=(1, 10)), 0.5, 0.9))
    splotch = smooth(remap(big, 0.6, 0.9))
    chip = remap(fbm(n, 1.6, lo=10), 0.82, 0.86) * splotch
    base = lerp(srgb("b9beb6"), srgb("c9cdc4"), mid)
    base = base * (0.96 + 0.08 * fine[:, :, None])
    base = lerp(base, srgb("7e7a6c"), streak * 0.45)
    base = lerp(base, srgb("6b655a"), splotch * 0.35)
    base = lerp(base, srgb("8a8f8c"), chip)
    base = lerp(base, srgb("3a3a38"), seams * 0.85)
    base = lerp(base, srgb("6e6e6a"), screws)
    h = 1 - seams * 0.8 + screws * 0.5 - chip * 0.2 + fine * 0.03
    rough = 0.6 + streak * 0.2 + splotch * 0.15 + chip * 0.2
    metal = screws * 0.9 + chip * 0.6
    write("wall_panel", base, rough, h, 3.0, metal=metal)


@tex
def ceiling_tile():
    """Acoustic drop-ceiling tiles with water stains (2x2 per 1.2 m)."""
    T.seed(5)
    n = 512
    big, mid, fine = grime_layers(n)
    grid = grid_lines(n, 2, 5, 1.0)
    holes = remap(fbm(n, 0.3, lo=80), 0.7, 0.75)
    stain_mask = fbm(n, 2.4, lo=1)
    stain = smooth(remap(stain_mask, 0.6, 0.75))
    stain_ring = ring_like = np.clip(1 - np.abs(stain_mask - 0.66) * 40, 0, 1)
    base = lerp(srgb("c8c5b8"), srgb("d6d3c7"), mid)
    base = lerp(base, srgb("a08b5c"), stain * 0.55)
    base = lerp(base, srgb("6f5a35"), ring_like * 0.5)
    base = base * (1 - holes[:, :, None] * 0.25)
    base = lerp(base, srgb("8c8f8e"), grid)
    h = 1 - holes * 0.4 + grid * 0.5 + fine * 0.1
    rough = 0.92 - grid * 0.5
    metal = grid * 0.8
    write("ceiling_tile", base, rough, h, 2.5, metal=metal)


@tex
def painted_metal():
    """Dark teal industrial paint, chipped to reveal rust and bare steel."""
    T.seed(6)
    n = 1024
    big, mid, fine = grime_layers(n)
    wear = fbm(n, 1.8, lo=4) * 0.6 + big * 0.4
    chip = smooth(remap(wear, 0.62, 0.66))                  # paint gone
    rust = smooth(remap(wear, 0.66, 0.78))                  # rust inside chips
    edge_halo = smooth(remap(wear, 0.56, 0.62)) * (1 - chip)
    drip = smooth(remap(fbm(n, 2.0, lo=3, stretch=(1, 9)), 0.6, 0.9))
    paint = lerp(srgb("2f4a4c"), srgb("3c5a5a"), mid)
    paint = paint * (0.9 + 0.15 * fine[:, :, None])
    paint = lerp(paint, srgb("1d2a2a"), edge_halo * 0.4)
    paint = lerp(paint, srgb("5a3a22"), drip * 0.5)
    steel = lerp(srgb("6f6d68"), srgb("8f8b84"), fine)
    rustc = lerp(srgb("6a3518"), srgb("9b5427"), fine)
    base = lerp(paint, steel, chip)
    base = lerp(base, rustc, rust)
    h = 1 - chip * 0.4 - rust * 0.25 * fine + mid * 0.05
    rough = lerp(0.45 + fine * 0.1, 0.35, chip) * (1 - rust) + rust * 0.92
    rough = rough + drip * 0.2
    metal = chip * (1 - rust)
    write("painted_metal", base, np.clip(rough, 0, 1), h, 4.0, metal=metal)


@tex
def painted_white_metal():
    """Off-white enamel for lab cabinets and machines."""
    T.seed(7)
    n = 512
    big, mid, fine = grime_layers(n)
    wear = fbm(n, 1.8, lo=4) * 0.7 + big * 0.3
    chip = smooth(remap(wear, 0.72, 0.75))
    grime = smooth(remap(big, 0.5, 0.9))
    base = lerp(srgb("cfd0c8"), srgb("dcdcd2"), mid)
    base = lerp(base, srgb("8b8577"), grime * 0.45)
    base = lerp(base, srgb("5d5f60"), chip)
    h = 1 - chip * 0.3 + fine * 0.02
    rough = 0.35 + grime * 0.35 + chip * 0.1
    write("painted_white_metal", base, rough, h, 3.0, metal=chip)


@tex
def rust():
    T.seed(8)
    n = 1024
    big, mid, fine = grime_layers(n)
    f1, edge, _ = worley(n, 500)
    flakes = remap(edge, 0, 0.05)
    pits = 1 - remap(f1, 0, 0.2)
    base = lerp(srgb("4a2412"), srgb("8e4a20"), mid)
    base = lerp(base, srgb("b06a33"), smooth(remap(fine, 0.6, 0.9)) * 0.6)
    base = lerp(base, srgb("2a160c"), pits * 0.5)
    base = base * (0.85 + 0.25 * flakes[:, :, None])
    h = mid * 0.5 + flakes * 0.3 - pits * 0.5 + fine * 0.3
    rough = 0.85 + fine * 0.1
    metal = smooth(remap(big, 0.75, 0.9)) * 0.4
    write("rust", base, rough, h, 6.0, metal=metal)


@tex
def brushed_steel():
    T.seed(9)
    n = 512
    big, mid, fine = grime_layers(n)
    brush = fbm(n, 1.0, lo=4, stretch=(40, 1))
    scratch = remap(fbm(n, 0.5, lo=40, stretch=(30, 1)), 0.8, 0.9)
    smudge = smooth(remap(big, 0.55, 0.85))
    base = lerp(srgb("8e9194"), srgb("b4b7ba"), brush)
    base = lerp(base, srgb("5e5c58"), smudge * 0.4)
    h = brush * 0.2 - scratch * 0.2
    rough = 0.28 + brush * 0.1 + smudge * 0.3 + scratch * 0.15
    write("brushed_steel", base, rough, h, 2.0, metal=np.ones((n, n)) * 0.95)


@tex
def brass_aged():
    """Antique brass: polished highs, dark tarnish and green patina in low areas."""
    T.seed(10)
    n = 512
    big, mid, fine = grime_layers(n)
    tarnish = smooth(remap(fbm(n, 2.2, lo=2), 0.35, 0.75))
    patina = smooth(remap(fbm(n, 1.8, lo=5), 0.72, 0.85)) * tarnish
    scratch = remap(fbm(n, 0.6, lo=30, stretch=(20, 1)), 0.83, 0.9)
    base = lerp(srgb("8a6a34"), srgb("a8854a"), mid)
    base = lerp(base, srgb("3a2c17"), tarnish * 0.8)
    base = lerp(base, srgb("4f7a64"), patina)
    base = lerp(base, srgb("c9a96a"), scratch * 0.45)
    rough = 0.3 + tarnish * 0.35 + patina * 0.3
    metal = 1 - patina * 0.9
    h = fine * 0.2 + patina * 0.3 - scratch * 0.1
    write("brass_aged", base, rough, h, 3.0, metal=metal)


@tex
def copper_oxidized():
    T.seed(11)
    n = 512
    big, mid, fine = grime_layers(n)
    ox = smooth(remap(fbm(n, 2.0, lo=2) * 0.7 + fine * 0.3, 0.45, 0.7))
    base = lerp(srgb("8a4a2a"), srgb("b8673b"), mid)
    base = lerp(base, srgb("3f2116"), smooth(remap(big, 0.6, 0.9)) * 0.5)
    base = lerp(base, lerp(srgb("4c8c78"), srgb("78b39c"), fine), ox)
    rough = 0.35 + ox * 0.55
    metal = 1 - ox
    h = ox * 0.4 + fine * 0.2
    write("copper_oxidized", base, rough, h, 4.0, metal=metal)


@tex
def tarnished_gold():
    T.seed(12)
    n = 512
    big, mid, fine = grime_layers(n)
    tarn = smooth(remap(fbm(n, 2.2, lo=2), 0.4, 0.8))
    base = lerp(srgb("9c7a35"), srgb("b8954b"), mid)
    base = lerp(base, srgb("33270f"), tarn * 0.75)
    rough = 0.25 + tarn * 0.45
    write("tarnished_gold", base, rough, fine * 0.2, 2.0, metal=np.ones((n, n)))


@tex
def teal_metal_dark():
    """Dark teal mechanical housing for the monster."""
    T.seed(13)
    n = 512
    big, mid, fine = grime_layers(n)
    wear = smooth(remap(fbm(n, 1.6, lo=6), 0.7, 0.78))
    corr = smooth(remap(big, 0.65, 0.9))
    base = lerp(srgb("13312f"), srgb("1f4642"), mid)
    base = lerp(base, srgb("7f8a84"), wear * 0.6)
    base = lerp(base, srgb("4a3a22"), corr * 0.5)
    rough = 0.4 + corr * 0.4 + fine * 0.1 - wear * 0.1
    metal = 0.85 - corr * 0.4
    write("teal_metal_dark", base, rough, fine * 0.2 + corr * 0.2, 3.0, metal=metal + 0 * mid)


@tex
def glass_grime():
    """Roughness/albedo breakup for dirty, scratched glass."""
    T.seed(14)
    n = 512
    big, mid, fine = grime_layers(n)
    smear = smooth(remap(fbm(n, 2.0, lo=2, stretch=(3, 1)), 0.5, 0.85))
    scratch = remap(fbm(n, 0.5, lo=40, stretch=(25, 1)), 0.86, 0.92)
    base = lerp(srgb("cfdcd8"), srgb("8f8a7a"), smear * 0.6)
    rough = 0.03 + smear * 0.35 + scratch * 0.3 + fine * 0.03
    write("glass_grime", base, rough, scratch * -0.2, 1.0)


# ====================================================================
# Organic / soft
# ====================================================================

@tex
def skin_pale():
    T.seed(20)
    n = 1024
    big, mid, fine = grime_layers(n)
    pores_f, _, _ = worley(n, 3000)
    pores = 1 - remap(pores_f, 0, 0.25)
    veins_e = worley(n, 30)[1]
    veins = (1 - remap(veins_e, 0, 0.01)) * smooth(remap(fbm(n, 2, lo=2), 0.5, 0.75))
    blotch = smooth(remap(fbm(n, 2.4, lo=3), 0.5, 0.85))
    base = lerp(srgb("cdb7a6"), srgb("dcc8b8"), mid)
    base = lerp(base, srgb("b9908a"), blotch * 0.35)          # reddish mottling
    base = lerp(base, srgb("7d8aa0"), veins * 0.35)           # blue-grey veins
    base = base * (1 - pores[:, :, None] * 0.06)
    h = -pores * 0.4 + fine * 0.15 + veins * 0.15
    rough = 0.52 + fine * 0.1 + pores * 0.1 - blotch * 0.08
    write("skin_pale", base, rough, h, 2.0)


@tex
def skin_diseased():
    """Chemically altered subject: discolouration and burn scarring."""
    T.seed(21)
    n = 1024
    big, mid, fine = grime_layers(n)
    burn = smooth(remap(fbm(n, 2.2, lo=2) * 0.7 + fine * 0.3, 0.55, 0.7))
    blister_f, _, _ = worley(n, 400)
    blister = (1 - remap(blister_f, 0, 0.35)) * burn
    sick = smooth(remap(fbm(n, 2.0, lo=2), 0.4, 0.7))
    base = lerp(srgb("b8ad94"), srgb("9fa486"), sick)            # yellow-green cast
    base = lerp(base, srgb("6d2f28"), burn * 0.7)
    base = lerp(base, srgb("d9c08e"), blister * 0.5)
    base = base * (0.9 + fine[:, :, None] * 0.15)
    h = fine * 0.2 + blister * 0.6 - burn * 0.2
    rough = 0.6 - blister * 0.35 + burn * 0.15
    write("skin_diseased", base, np.clip(rough, 0.1, 1), h, 4.0)


@tex
def fabric_worn():
    """Faded institutional fabric with a visible weave and dried stains."""
    T.seed(22)
    n = 512
    big, mid, fine = grime_layers(n)
    x = np.arange(n) * 2 * math.pi * 96 / n
    weave = (np.sin(x)[None, :] * 0.5 + 0.5) * (np.sin(x)[:, None] * 0.5 + 0.5)
    stain = smooth(remap(fbm(n, 2.4, lo=2), 0.65, 0.8))
    stain_edge = np.clip(1 - np.abs(fbm(n, 2.4, lo=2) - 0.65) * 50, 0, 1) * 0
    blood = smooth(remap(fbm(n, 2.2, lo=3), 0.78, 0.86))
    base = lerp(srgb("a9ada5"), srgb("c3c5bc"), mid)
    base = base * (0.9 + 0.12 * weave[:, :, None])
    base = lerp(base, srgb("7c7058"), stain * 0.5)
    base = lerp(base, srgb("4a1d17"), blood * 0.8)
    h = weave * 0.6 + fine * 0.2
    rough = 0.9 - blood * 0.25
    write("fabric_worn", base, rough, h + stain_edge, 2.0)


@tex
def rubber_black():
    T.seed(23)
    n = 256
    big, mid, fine = grime_layers(n)
    base = lerp(srgb("1b1b1c"), srgb("2a2a2a"), mid)
    base = lerp(base, srgb("4a4740"), smooth(remap(big, 0.6, 0.9)) * 0.5)
    write("rubber_black", base, 0.75 + fine * 0.15, fine * 0.2, 1.5)


@tex
def plastic_dirty():
    T.seed(24)
    n = 512
    big, mid, fine = grime_layers(n)
    grime = smooth(remap(big, 0.5, 0.85))
    yell = smooth(remap(fbm(n, 2.6, lo=1), 0.3, 0.8))
    scratch = remap(fbm(n, 0.5, lo=40, stretch=(20, 1)), 0.85, 0.9)
    base = lerp(srgb("d8d2c2"), srgb("cdbf98"), yell * 0.7)
    base = lerp(base, srgb("6d6658"), grime * 0.5)
    base = lerp(base, srgb("f0ece0"), scratch * 0.4)
    rough = 0.4 + grime * 0.3 + scratch * 0.2
    write("plastic_dirty", base, rough, fine * 0.05 - scratch * 0.1, 1.5)


@tex
def hazard_stripes():
    T.seed(25)
    n = 512
    big, mid, fine = grime_layers(n)
    yy, xx = np.mgrid[0:n, 0:n] / n
    s = np.sin((xx + yy) * 2 * math.pi * 4)
    stripe = smooth(remap(s, -0.05, 0.05))
    wear = smooth(remap(fbm(n, 1.8, lo=4) * 0.6 + big * 0.4, 0.6, 0.66))
    base = lerp(srgb("161513"), srgb("d4a215"), stripe)
    base = lerp(base, srgb("6a6660"), wear)
    base = lerp(base, srgb("3d3426"), smooth(remap(big, 0.6, 0.9)) * 0.5)
    rough = 0.55 + wear * 0.2 + fine * 0.1
    write("hazard_stripes", base, rough, -wear * 0.2, 2.0, metal=wear)


@tex
def chemical_residue():
    """Glowing green residue puddles (used with emission in the shader)."""
    T.seed(26)
    n = 512
    big, mid, fine = grime_layers(n)
    puddle = smooth(remap(big * 0.7 + fine * 0.3, 0.55, 0.62))
    crust = np.clip(1 - np.abs(big * 0.7 + fine * 0.3 - 0.56) * 25, 0, 1)
    base = lerp(srgb("2c2f22"), srgb("5f8f2a"), puddle)
    base = lerp(base, srgb("c8c49a"), crust * 0.6)
    rough = 0.8 - puddle * 0.75
    emit = color([0.35, 1.0, 0.25], n) * (puddle * (0.5 + 0.5 * mid))[:, :, None]
    write("chemical_residue", base, rough, puddle * 0.3 + crust * 0.2, 2.0, emit=emit)


# ====================================================================
# Monster-specific decals
# ====================================================================

def _crazing(n, count, strength):
    _, edge, _ = worley(n, count)
    return (1 - remap(edge, 0, 0.012)) * strength


@tex
def clock_face():
    """Antique porcelain clock dial with Roman numerals, square, no tiling."""
    T.seed(30)
    n = 1024
    big, mid, fine = grime_layers(n)
    yy, xx = np.mgrid[0:n, 0:n] / n
    r = np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2)
    craze = _crazing(n, 260, 1.0)
    yellow = smooth(remap(r, 0.15, 0.5))                    # darker toward the rim
    base = lerp(srgb("e9dfc4"), srgb("d6c494"), mid * 0.6 + yellow * 0.4)
    base = lerp(base, srgb("8a7140"), smooth(remap(big, 0.6, 0.9)) * 0.45)
    base = lerp(base, srgb("6b5530"), craze * 0.35)
    base = lerp(base, srgb("3a2a14"), smooth(remap(r, 0.44, 0.5)) * 0.8)

    ink = np.zeros((n, n))
    ink = np.maximum(ink, ring(n, 0.5, 0.5, 0.425, 4))
    ink = np.maximum(ink, ring(n, 0.5, 0.5, 0.41, 2))
    ink = np.maximum(ink, ring(n, 0.5, 0.5, 0.30, 2))
    segs = []
    for i in range(60):                                       # minute ticks
        a = i / 60 * 2 * math.pi
        r0 = 0.39 if i % 5 else 0.37
        segs.append((0.5 + math.sin(a) * r0, 0.5 - math.cos(a) * r0,
                     0.5 + math.sin(a) * 0.41, 0.5 - math.cos(a) * 0.41))
    ink = np.maximum(ink, draw_segments(n, segs, 3))
    numerals = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
    nsegs = []
    for i, s in enumerate(numerals):
        a = i / 12 * 2 * math.pi
        h = 0.055
        segs_s, w = text_segments(s, 0, 0, h)
        cx = 0.5 + math.sin(a) * 0.335
        cy = 0.5 - math.cos(a) * 0.335
        for x0, y0, x1, y1 in segs_s:
            nsegs.append((x0 + cx - w / 2, y0 + cy - h / 2, x1 + cx - w / 2, y1 + cy - h / 2))
    ink = np.maximum(ink, draw_segments(n, nsegs, 5))
    ink *= 0.75 + 0.25 * remap(fine, 0.2, 0.8)               # faded print
    ink *= 1 - smooth(remap(big, 0.75, 0.95)) * 0.6          # rubbed off patches
    base = lerp(base, srgb("1a140e"), ink)
    h = -craze * 0.5 + fine * 0.05 - ink * 0.1
    rough = 0.28 + craze * 0.3 + smooth(remap(big, 0.6, 0.9)) * 0.3
    write("clock_face", base, rough, h, 2.0)


@tex
def gauge_face():
    """Small yellowed instrument dial with a red danger arc."""
    T.seed(31)
    n = 512
    big, mid, fine = grime_layers(n)
    yy, xx = np.mgrid[0:n, 0:n] / n
    r = np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2)
    ang = np.arctan2(xx - 0.5, -(yy - 0.5))
    base = lerp(srgb("e2d6ad"), srgb("c9b57a"), mid * 0.5 + smooth(remap(r, 0.1, 0.5)) * 0.5)
    base = lerp(base, srgb("6d5730"), _crazing(n, 120, 0.4) + smooth(remap(big, 0.6, 0.9)) * 0.3)
    segs = []
    for i in range(41):
        a = -2.36 + i / 40 * 4.72
        r0 = 0.33 if i % 5 else 0.3
        segs.append((0.5 + math.sin(a) * r0, 0.5 - math.cos(a) * r0,
                     0.5 + math.sin(a) * 0.38, 0.5 - math.cos(a) * 0.38))
    ink = draw_segments(n, segs, 2.5)
    ink = np.maximum(ink, ring(n, 0.5, 0.5, 0.385, 2.5) * (np.abs(ang) < 2.36))
    danger = (ring(n, 0.5, 0.5, 0.355, 14) * (ang > 1.3) * (ang < 2.36))
    base = lerp(base, srgb("b0261a"), danger * 0.9)
    base = lerp(base, srgb("17120c"), ink)
    base = lerp(base, srgb("3a2a14"), smooth(remap(r, 0.45, 0.5)))
    emit = color([1.0, 0.35, 0.1], n) * danger[:, :, None] * 0.6
    write("gauge_face", base, 0.3 + _crazing(n, 80, 0.3), None, emit=emit,
          normal=np.ones((n, n, 3)) * np.array([0.5, 0.5, 1.0]))


@tex
def eye_iris():
    """Mechanical iris: concentric machined rings, radial vanes, hot pupil."""
    T.seed(32)
    n = 512
    big, mid, fine = grime_layers(n)
    yy, xx = np.mgrid[0:n, 0:n] / n
    r = np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2) * 2
    ang = np.arctan2(yy - 0.5, xx - 0.5)
    rings = 0.5 + 0.5 * np.sin(r * 90)
    vanes = smooth(remap(np.sin(ang * 14 + r * 3), 0.7, 0.9)) * (r > 0.35) * (r < 0.8)
    metal_col = lerp(srgb("3b3f3d"), srgb("8c8a80"), rings * 0.5 + fine * 0.5)
    base = lerp(metal_col, srgb("1b1c1a"), vanes)
    pupil = 1 - remap(r, 0.18, 0.24)
    glow_ring = np.exp(-((r - 0.3) ** 2) / 0.002)
    base = lerp(base, srgb("ff5a1e"), pupil)
    emit = (color([1.0, 0.32, 0.08], n) * (pupil * 3 + glow_ring * 0.6)[:, :, None]
            * (0.85 + 0.15 * fine[:, :, None]))
    h = rings * 0.2 - vanes * 0.3 + (r < 0.35) * 0.2
    rough = 0.35 + vanes * 0.4 - pupil * 0.25
    write("eye_iris", base, rough, h, 3.0, metal=(1 - pupil) * 0.85, emit=np.clip(emit, 0, 1))


@tex
def warning_sign():
    """Yellow warning triangle sign, square decal."""
    T.seed(33)
    n = 512
    big, mid, fine = grime_layers(n)
    yy, xx = np.mgrid[0:n, 0:n] / n
    def tri(scale):
        cx, cy, s = 0.5, 0.56, scale
        y0 = cy - s * 0.55
        y1 = cy + s * 0.4
        inside = (yy > y0) & (yy < y1)
        half = (yy - y0) / (y1 - y0) * s * 0.58
        return (inside & (np.abs(xx - cx) < half)).astype(float)
    outer = blur(tri(0.9), 1.0)
    inner = blur(tri(0.74), 1.0)
    mark = draw_segments(n, [(0.5, 0.36, 0.5, 0.6)], 26) + disc(n, 0.5, 0.7, 0.03)
    base = color(srgb("e4e1d8"), n)
    base = lerp(base, srgb("151413"), outer)
    base = lerp(base, srgb("e3b31a"), inner)
    base = lerp(base, srgb("151413"), np.clip(mark, 0, 1) * inner)
    wear = smooth(remap(fbm(n, 1.8, lo=4) * 0.6 + big * 0.4, 0.66, 0.7))
    base = lerp(base, srgb("8a8a86"), wear)
    base = lerp(base, srgb("4d4334"), smooth(remap(big, 0.55, 0.9)) * 0.45)
    write("warning_sign", base, 0.45 + wear * 0.3, -wear * 0.3, 2.0, metal=wear)


@tex
def monitor_screen():
    """CRT-style monitor glow: scanlines, noise and a dim data readout."""
    T.seed(34)
    n = 512
    big, mid, fine = grime_layers(n)
    yy, xx = np.mgrid[0:n, 0:n] / n
    scan = 0.75 + 0.25 * np.sin(yy * n * math.pi * 0.5)
    row = np.floor(yy * 24)
    line_len = 0.15 + (row * 37 % 11) / 14          # pseudo-random length per text row
    rows = (row % 2 == 0) & (xx > 0.08) & (xx < 0.08 + line_len)
    blocks = rows * (np.sin(xx * 120) > -0.3) * (yy > 0.12) * (yy < 0.88)
    vign = 1 - smooth(remap(np.sqrt((xx - 0.5) ** 2 + (yy - 0.5) ** 2), 0.3, 0.72))
    g = (0.15 + blocks * 0.6 + fine * 0.15) * scan * vign
    emit = np.stack([g * 0.35, g * 0.95, g * 0.6], -1)
    write("monitor_screen", emit * 0.6 + 0.02, np.full((n, n), 0.08), None,
          normal=np.ones((n, n, 3)) * np.array([0.5, 0.5, 1.0]), emit=np.clip(emit, 0, 1))


def contact_sheet():
    """Small preview of every albedo so a human can eyeball them at once."""
    names = sorted(f[:-11] for f in os.listdir(OUT) if f.endswith("_albedo.png"))
    return names


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wanted = sys.argv[1:] or list(REGISTRY)
    for name in wanted:
        print("texture:", name, flush=True)
        REGISTRY[name]()
    print("done", len(wanted))
