"""Signed-distance modelling + surface-nets meshing (numpy only).

An organic shape is written as a function f(p) that is negative inside and
positive outside, built from simple primitives (spheres, ellipsoids, tapered
capsules) merged with *smooth* unions so muscles and bones blend like flesh.
`mesh_from_sdf()` samples f on a voxel grid and extracts a quad mesh with the
surface-nets algorithm, then hands it to Blender.
"""
import math

import bmesh
import bpy
import numpy as np

import tlib as T

# ------------------------------------------------------------------ primitives
# p is an (N, 3) float32 array of points. All return (N,) distances.


def _v(a):
    return np.asarray(a, np.float32)


def sphere(p, c, r):
    return np.linalg.norm(p - _v(c), axis=1) - r


def ellipsoid(p, c, r, rot=None):
    """Approximate ellipsoid distance (Inigo Quilez). rot: 3x3 world->local."""
    q = p - _v(c)
    if rot is not None:
        q = q @ _v(rot).T
    r = _v(r)
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def round_cone(p, a, b, r1, r2):
    """Capsule from a (radius r1) to b (radius r2) with a smooth taper."""
    a, b = _v(a), _v(b)
    ba = b - a
    l2 = float(ba @ ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = p - a
    y = pa @ ba
    z = y - l2
    xv = pa * l2 - y[:, None] * ba
    x2 = np.einsum("ij,ij->i", xv, xv)
    y2 = y * y * l2
    z2 = z * z * l2
    k = math.copysign(1.0, rr) * rr * rr * x2
    out = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    m1 = np.sign(z) * a2 * z2 > k
    m2 = np.sign(y) * a2 * y2 < k
    out = np.where(m1, np.sqrt(x2 + z2) * il2 - r2, out)
    out = np.where(m2 & ~m1, np.sqrt(x2 + y2) * il2 - r1, out)
    return out


def capsule(p, a, b, r):
    a, b = _v(a), _v(b)
    pa, ba = p - a, b - a
    h = np.clip((pa @ ba) / float(ba @ ba), 0, 1)
    return np.linalg.norm(pa - h[:, None] * ba, axis=1) - r


def rounded_box(p, c, half, r, rot=None):
    q = p - _v(c)
    if rot is not None:
        q = q @ _v(rot).T
    d = np.abs(q) - (_v(half) - r)
    return np.linalg.norm(np.maximum(d, 0), axis=1) + np.minimum(d.max(axis=1), 0) - r


# ------------------------------------------------------------------ operators

def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def subtract(a, b, k=0.0):
    """Carve b out of a."""
    return smax(a, -b, k) if k > 0 else np.maximum(a, -b)


class Shape:
    """Accumulates primitives with smooth unions/subtractions.

    Each op records (kind, fn, k, bbox) so evaluation can skip points that
    are far from a primitive (big speedup on large grids).
    """

    def __init__(self):
        self.ops = []

    def add(self, fn, k=0.02, bounds=None):
        self.ops.append(("add", fn, k, bounds))
        return self

    def cut(self, fn, k=0.005, bounds=None):
        self.ops.append(("cut", fn, k, bounds))
        return self

    def displace(self, fn):
        self.ops.append(("disp", fn, 0, None))
        return self

    def restrict(self, lo, hi, margin=0.03):
        """Shape with only the ops whose bounds touch [lo, hi]; None if nothing is added there."""
        sub = Shape()
        any_add = False
        for op in self.ops:
            kind, fn, k, bounds = op
            if bounds is not None and kind != "disp":
                blo, bhi = bounds
                if np.any(blo - k - margin > hi) or np.any(bhi + k + margin < lo):
                    continue
            sub.ops.append((kind, fn, k, None if kind == "disp" else None))
            any_add |= kind == "add"
        return sub if any_add else None

    def __call__(self, p):
        d = np.full(len(p), 1e3, np.float32)
        for kind, fn, k, bounds in self.ops:
            if kind == "disp":
                d = d + fn(p)
                continue
            if bounds is not None:
                lo, hi = bounds
                m = np.all((p >= lo - 0.05) & (p <= hi + 0.05), axis=1)
                if not m.any():
                    continue
                v = np.full(len(p), 1e3, np.float32)
                v[m] = fn(p[m])
            else:
                v = fn(p)
            d = smin(d, v, k) if kind == "add" else subtract(d, v, k)
        return d


# ------------------------------------------------------------------ noise for skin detail

def value_noise3(p, freq, seed=0):
    """Cheap smooth 3D value noise in [-1, 1] (hash on lattice + trilinear)."""
    q = p * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)

    def h(ix, iy, iz):
        n = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
        n = (n ^ (n >> 13)) * 1274126177
        return ((n & 0xFFFF) / 32767.5 - 1.0).astype(np.float32)

    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * h(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out


# ------------------------------------------------------------------ surface nets

_EDGES = [((0, 0, 0), (1, 0, 0)), ((0, 1, 0), (1, 1, 0)), ((0, 0, 1), (1, 0, 1)), ((0, 1, 1), (1, 1, 1)),
          ((0, 0, 0), (0, 1, 0)), ((1, 0, 0), (1, 1, 0)), ((0, 0, 1), (0, 1, 1)), ((1, 0, 1), (1, 1, 1)),
          ((0, 0, 0), (0, 0, 1)), ((1, 0, 0), (1, 0, 1)), ((0, 1, 0), (0, 1, 1)), ((1, 1, 0), (1, 1, 1))]


def sample(fn, lo, hi, voxel, block=48):
    """Sample fn on a grid. If fn is a Shape with bounds, each block of the
    grid only evaluates the primitives near it (much faster)."""
    lo, hi = np.asarray(lo, np.float32), np.asarray(hi, np.float32)
    n = np.ceil((hi - lo) / voxel).astype(int) + 1
    F = np.full((n[0], n[1], n[2]), 1e3, np.float32)
    axes = [lo[a] + np.arange(n[a], dtype=np.float32) * voxel for a in range(3)]
    for i0 in range(0, n[0], block):
        for j0 in range(0, n[1], block):
            for k0 in range(0, n[2], block):
                i1, j1, k1 = min(n[0], i0 + block), min(n[1], j0 + block), min(n[2], k0 + block)
                xs, ys, zs = axes[0][i0:i1], axes[1][j0:j1], axes[2][k0:k1]
                blo = np.array([xs[0], ys[0], zs[0]])
                bhi = np.array([xs[-1], ys[-1], zs[-1]])
                f = fn.restrict(blo, bhi) if isinstance(fn, Shape) else fn
                if f is None:
                    continue
                gx, gy, gz = np.meshgrid(xs, ys, zs, indexing="ij")
                pts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], 1)
                F[i0:i1, j0:j1, k0:k1] = f(pts).reshape(len(xs), len(ys), len(zs))
    return F, lo


def surface_nets(F, origin, voxel):
    """Return (verts (V,3), quads (Q,4)) for the zero level set of F."""
    nx, ny, nz = F.shape
    inside = F < 0
    cs = (nx - 1, ny - 1, nz - 1)
    acc = np.zeros(cs + (3,), np.float32)
    cnt = np.zeros(cs, np.uint8)
    for c0, c1 in _EDGES:
        f0 = F[c0[0]:c0[0] + cs[0], c0[1]:c0[1] + cs[1], c0[2]:c0[2] + cs[2]]
        f1 = F[c1[0]:c1[0] + cs[0], c1[1]:c1[1] + cs[1], c1[2]:c1[2] + cs[2]]
        m = (f0 < 0) != (f1 < 0)
        if not m.any():
            continue
        t = np.where(m, f0 / np.where(m, f0 - f1, 1.0), 0.0)
        for ax in range(3):
            acc[..., ax] += np.where(m, c0[ax] + t * (c1[ax] - c0[ax]), 0.0)
        cnt += m
    active = cnt > 0
    vid = np.full(cs, -1, np.int64)
    idx = np.argwhere(active)
    vid[active] = np.arange(len(idx))
    verts = (idx + acc[active] / cnt[active][:, None]) * voxel + origin
    quads = []
    # x-edges: grid points (i, j, k)-(i+1, j, k); cells (i, j-1..j, k-1..k)
    s = inside
    m = s[:-1, 1:-1, 1:-1] != s[1:, 1:-1, 1:-1]
    i, j, k = np.nonzero(m)
    j, k = j + 1, k + 1
    flip = s[i, j, k]
    q = np.stack([vid[i, j - 1, k - 1], vid[i, j, k - 1], vid[i, j, k], vid[i, j - 1, k]], 1)
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    m = s[1:-1, :-1, 1:-1] != s[1:-1, 1:, 1:-1]
    i, j, k = np.nonzero(m)
    i, k = i + 1, k + 1
    flip = s[i, j, k]
    q = np.stack([vid[i - 1, j, k - 1], vid[i - 1, j, k], vid[i, j, k], vid[i, j, k - 1]], 1)
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    m = s[1:-1, 1:-1, :-1] != s[1:-1, 1:-1, 1:]
    i, j, k = np.nonzero(m)
    i, j = i + 1, j + 1
    flip = s[i, j, k]
    q = np.stack([vid[i - 1, j - 1, k], vid[i, j - 1, k], vid[i, j, k], vid[i - 1, j, k]], 1)
    q[flip] = q[flip][:, ::-1]
    quads.append(q)
    quads = np.concatenate(quads)
    quads = quads[(quads >= 0).all(axis=1)]
    return verts, quads


def mesh_from_sdf(name, fn, lo, hi, voxel, material="skin", decimate=None, smooth_iter=2):
    F, origin = sample(fn, lo, hi, voxel)
    verts, quads = surface_nets(F, origin, voxel)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts.tolist(), [], quads.tolist())
    me.validate()
    ob = bpy.data.objects.new(name, me)
    T.link(ob)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    if smooth_iter:
        sm = ob.modifiers.new("smooth", "LAPLACIANSMOOTH")
        sm.iterations = smooth_iter
        sm.lambda_factor = 0.5
        sm.use_volume_preserve = True
    if decimate:
        dec = ob.modifiers.new("decimate", "DECIMATE")
        dec.ratio = decimate
        dec.use_collapse_triangulate = False
    T.apply_all([ob])
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.data.materials.append(T.mat(material))
    T.world_uv(ob)
    print(f"sdf mesh {name}: {len(ob.data.vertices)} verts, {len(ob.data.polygons)} faces")
    return ob
