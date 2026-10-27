"""Small numpy toolkit for making seamless (tileable) PBR textures.

Everything here wraps around at the edges, so the textures repeat
without visible seams. No PIL needed: PNGs are written with zlib.
"""
import struct
import zlib

import numpy as np

RNG = np.random.default_rng(440)


def seed(n):
    global RNG
    RNG = np.random.default_rng(n)


# ---------------------------------------------------------------- output

def save_png(path, img):
    """img: HxW (gray) or HxWx3 array of floats in 0..1."""
    a = np.clip(img, 0.0, 1.0)
    a = (a * 255.0 + 0.5).astype(np.uint8)
    if a.ndim == 2:
        color_type, chans = 0, 1
        a = a[:, :, None]
    else:
        color_type, chans = 2, a.shape[2]
    h, w = a.shape[:2]
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


# ---------------------------------------------------------------- noise

def _freq(n):
    f = np.fft.fftfreq(n) * n
    fx, fy = np.meshgrid(f, f)
    return fx, fy


def fbm(n, beta=2.0, lo=1.0, hi=None, stretch=(1.0, 1.0)):
    """Seamless fractal noise made by shaping white noise in frequency space.

    beta: higher = smoother/blobbier. lo/hi: frequency band (in repeats
    per tile). stretch: (sx, sy) > 1 squashes features along that axis,
    e.g. stretch=(1, 8) makes long vertical streaks.
    """
    fx, fy = _freq(n)
    r = np.sqrt((fx * stretch[0]) ** 2 + (fy * stretch[1]) ** 2)
    r[0, 0] = 1.0
    amp = 1.0 / r ** (beta / 2.0)
    amp[r < lo] = 0.0
    if hi is not None:
        amp[r > hi] = 0.0
    amp[0, 0] = 0.0
    spec = (RNG.standard_normal((n, n)) + 1j * RNG.standard_normal((n, n))) * amp
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def worley(n, count, power=1.0):
    """Seamless cellular noise. Returns (f1 distance, f2 - f1 edge, cell id)."""
    pts = RNG.random((count, 2)) * n
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    f1 = np.full((n, n), 1e9, np.float32)
    f2 = np.full((n, n), 1e9, np.float32)
    cid = np.zeros((n, n), np.int32)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, n - dx)
        dy = np.minimum(dy, n - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < f1
        f2 = np.where(closer, f1, np.minimum(f2, d))
        cid = np.where(closer, i, cid)
        f1 = np.where(closer, d, f1)
    scale = n / np.sqrt(count)
    return (f1 / scale) ** power, (f2 - f1) / scale, cid


def blur(img, radius):
    """Seamless gaussian-ish blur via FFT."""
    n = img.shape[0]
    fx, fy = _freq(n)
    g = np.exp(-(fx ** 2 + fy ** 2) * (np.pi * radius / n) ** 2 * 2)
    if img.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(img) * g))
    return np.stack([blur(img[:, :, c], radius) for c in range(img.shape[2])], -1)


def remap(x, a, b):
    return np.clip((x - a) / (b - a), 0.0, 1.0)


def smooth(x):
    return x * x * (3 - 2 * x)


def lerp(a, b, t):
    if np.ndim(t) == 2 and np.ndim(a) == 1:
        a = np.asarray(a)[None, None, :]
    if np.ndim(t) == 2 and np.ndim(b) == 1:
        b = np.asarray(b)[None, None, :]
    if np.ndim(t) == 2 and (np.ndim(a) == 3 or np.ndim(b) == 3):
        t = t[:, :, None]
    return a + (b - a) * t


def color(rgb, n):
    return np.ones((n, n, 3)) * np.asarray(rgb)[None, None, :]


def srgb(hexstr):
    hexstr = hexstr.lstrip("#")
    return np.array([int(hexstr[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


# ---------------------------------------------------------------- maps

def normal_from_height(h, strength=4.0):
    """OpenGL-style normal map (Godot and glTF both use +Y up)."""
    n = h.shape[0]
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength * n / 256.0
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength * n / 256.0
    nx, ny, nz = -dx, dy, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


def grid_lines(n, cells, width_px, soft=1.5):
    """1 on grout/seam lines of a cells x cells grid, 0 inside."""
    p = np.arange(n) * cells / n
    d = np.abs(p - np.round(p)) * n / cells
    line = 1.0 - remap(d, width_px * 0.5, width_px * 0.5 + soft)
    return np.maximum(line[None, :], line[:, None])


def draw_segments(n, segs, width, soft=1.0, ss=1):
    """Rasterise line segments [(x0,y0,x1,y1), ...] given in 0..1 coords."""
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    out = np.zeros((n, n), np.float32)
    for x0, y0, x1, y1 in segs:
        vx, vy = x1 - x0, y1 - y0
        L = vx * vx + vy * vy + 1e-12
        t = np.clip(((xx - x0) * vx + (yy - y0) * vy) / L, 0, 1)
        dx = xx - (x0 + t * vx)
        dy = yy - (y0 + t * vy)
        d = np.sqrt(dx * dx + dy * dy) * n
        out = np.maximum(out, 1.0 - remap(d, width * 0.5, width * 0.5 + soft))
    return out


def disc(n, cx, cy, r, soft=1.0):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) * n
    return 1.0 - remap(d, r * n, r * n + soft)


def ring(n, cx, cy, r, width, soft=1.0):
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32) / n
    d = np.abs(np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) * n - r * n)
    return 1.0 - remap(d, width * 0.5, width * 0.5 + soft)


# Stroke font for Roman numerals and a few capitals, in a 0..1 box.
GLYPHS = {
    "I": [(0.5, 0, 0.5, 1)],
    "V": [(0.05, 0, 0.5, 1), (0.95, 0, 0.5, 1)],
    "X": [(0.05, 0, 0.95, 1), (0.95, 0, 0.05, 1)],
}


def text_segments(s, x, y, h, w_ratio=0.55, gap=0.15):
    """Segments for string s, box starting at x,y (top-left), height h."""
    segs = []
    w = h * w_ratio
    total = len(s) * w + (len(s) - 1) * w * gap
    cx = x
    for ch in s:
        for a, b, c, d in GLYPHS[ch]:
            segs.append((cx + a * w, y + b * h, cx + c * w, y + d * h))
        cx += w * (1 + gap)
    return segs, total
