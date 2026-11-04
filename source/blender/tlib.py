"""Shared Blender helpers for every TIMBUK asset script.

Conventions
- Units are metres, +Z up in Blender (glTF export converts to Godot's +Y up).
- Architecture/props get "world box" UVs measured in metres, so a material's
  `repeat` in source/materials.json is the real-world size of one texture tile.
- Materials are named exactly like materials.json keys. GLBs are exported with
  viewport-only materials; tools/timbuk_post_import.gd swaps in the real .tres.
- Objects whose name ends in "-colonly" become invisible collision in Godot.
- Empties named "LIGHT_<kind>..." / "MARK_<kind>..." are read by the Godot
  scene builder to place lights and props.
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures")
SPEC = json.load(open(os.path.join(ROOT, "source", "materials.json")))


# ------------------------------------------------------------------ scene

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.unit_settings.system = "METRIC"
    return s


def collection(name, parent=None):
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if col.name not in (parent or bpy.context.scene.collection).children:
        (parent or bpy.context.scene.collection).children.link(col)
    return col


_ACTIVE = [None]


def use_collection(col):
    _ACTIVE[0] = col


def link(obj):
    col = _ACTIVE[0] or bpy.context.scene.collection
    col.objects.link(obj)
    return obj


# ------------------------------------------------------------------ materials

def _img(path, non_color):
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def mat(name):
    """Get or build the Blender preview material for a materials.json key."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    d = SPEC.get(name, {})
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    alb = d.get("albedo", [0.7, 0.7, 0.7])
    bsdf.inputs["Base Color"].default_value = (*alb, 1)
    bsdf.inputs["Roughness"].default_value = d.get("roughness", 0.8)
    bsdf.inputs["Metallic"].default_value = d.get("metallic", 0.0)
    m.diffuse_color = (*alb, 1)

    base = d.get("tex")
    if base:
        uv = nodes.new("ShaderNodeTexCoord")
        mp = nodes.new("ShaderNodeMapping")
        s = 1.0 / d.get("repeat", 1.0)
        mp.inputs["Scale"].default_value = (s, s, s)
        links.new(uv.outputs["UV"], mp.inputs["Vector"])

        def tex(kind, non_color):
            p = os.path.join(TEX_DIR, f"{base}_{kind}.png")
            if not os.path.exists(p):
                return None
            n = nodes.new("ShaderNodeTexImage")
            n.image = _img(p, non_color)
            links.new(mp.outputs["Vector"], n.inputs["Vector"])
            return n

        a = tex("albedo", False)
        if a:
            if "albedo" in d:
                mix = nodes.new("ShaderNodeMix")
                mix.data_type = "RGBA"
                mix.blend_type = "MULTIPLY"
                mix.inputs["Factor"].default_value = 1.0
                links.new(a.outputs["Color"], mix.inputs["A"])
                mix.inputs["B"].default_value = (*alb, 1)
                links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
            else:
                links.new(a.outputs["Color"], bsdf.inputs["Base Color"])
            # viewport colour = average of texture so GLB placeholders look sane
            m.diffuse_color = (*_avg_color(a.image), 1)
        r = tex("rough", True)
        if r:
            links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
        mt = tex("metal", True)
        if mt:
            links.new(mt.outputs["Color"], bsdf.inputs["Metallic"])
        nm = tex("normal", True)
        if nm:
            nmap = nodes.new("ShaderNodeNormalMap")
            nmap.inputs["Strength"].default_value = d.get("normal", 1.0)
            links.new(nm.outputs["Color"], nmap.inputs["Color"])
            links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        em = tex("emit", False)
        if em:
            links.new(em.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = d.get("emission_energy", 1.0)

    if "emission" in d:
        bsdf.inputs["Emission Color"].default_value = (*d["emission"], 1)
        bsdf.inputs["Emission Strength"].default_value = d.get("emission_energy", 1.0)
    if d.get("transparent"):
        bsdf.inputs["Alpha"].default_value = d.get("alpha", 0.5)
        if "glass" in name:
            bsdf.inputs["Transmission Weight"].default_value = 1.0
            bsdf.inputs["Alpha"].default_value = 1.0
            bsdf.inputs["Roughness"].default_value = 0.05
    if "sss" in d:
        bsdf.inputs["Subsurface Weight"].default_value = d["sss"] * 0.5
        bsdf.inputs["Subsurface Radius"].default_value = d.get("sss_color", [0.8, 0.3, 0.3])
        bsdf.inputs["Subsurface Scale"].default_value = 0.01
    return m


def _avg_color(img):
    px = img.pixels[:]
    step = max(4, (len(px) // 4 // 2000) * 4)
    r = sum(px[0::step]) / len(px[0::step])
    g = sum(px[1::step]) / len(px[1::step])
    b = sum(px[2::step]) / len(px[2::step])
    return (r, g, b)


# ------------------------------------------------------------------ meshes

def mesh_obj(name, bm, material=None, materials=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    for mname in (materials or ([material] if material else [])):
        me.materials.append(mat(mname))
    return link(ob)


def box(name, size, loc=(0, 0, 0), material="concrete", rot=(0, 0, 0), bevel=0.0, uv=True):
    """Axis box of full size (x, y, z) centred at loc."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = mesh_obj(name, bm, material)
    ob.location = loc
    ob.rotation_euler = rot
    if bevel > 0:
        add_bevel(ob, bevel)
    if uv:
        world_uv(ob)
    return ob


def cyl(name, r, depth, loc=(0, 0, 0), material="steel", rot=(0, 0, 0), seg=24, r2=None, cap=True, uv=True, smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg,
                          radius1=r, radius2=r if r2 is None else r2, depth=depth)
    ob = mesh_obj(name, bm, material)
    ob.location = loc
    ob.rotation_euler = rot
    if smooth:
        shade_smooth(ob)
    if uv:
        world_uv(ob)
    return ob


def sphere(name, r, loc=(0, 0, 0), material="steel", seg=24, rings=16, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    bmesh.ops.scale(bm, vec=Vector(scale), verts=bm.verts)
    ob = mesh_obj(name, bm, material)
    ob.location = loc
    shade_smooth(ob)
    world_uv(ob)
    return ob


def torus(name, R, r, loc=(0, 0, 0), material="brass", rot=(0, 0, 0), seg=48, rseg=12):
    bm = bmesh.new()
    verts = []
    for i in range(seg):
        a = i / seg * 2 * math.pi
        ring = []
        for j in range(rseg):
            b = j / rseg * 2 * math.pi
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
        verts.append(ring)
    for i in range(seg):
        for j in range(rseg):
            a, b = verts[i][j], verts[(i + 1) % seg][j]
            c, d = verts[(i + 1) % seg][(j + 1) % rseg], verts[i][(j + 1) % rseg]
            bm.faces.new((a, b, c, d))
    ob = mesh_obj(name, bm, material)
    ob.location = loc
    ob.rotation_euler = rot
    shade_smooth(ob)
    world_uv(ob)
    return ob


def tube(name, points, r, material="wire_black", seg=8, closed=False, taper=None):
    """Sweep a circle along a polyline of world points (pipes, cables, wires)."""
    pts = [Vector(p) for p in points]
    bm = bmesh.new()
    rings = []
    prev_n = None
    for i, p in enumerate(pts):
        if i == 0:
            t = (pts[1] - pts[0]).normalized()
        elif i == len(pts) - 1:
            t = (pts[-1] - pts[-2]).normalized()
        else:
            t = ((pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()).normalized()
        if prev_n is None:
            up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
            n = t.cross(up).normalized()
        else:  # parallel transport keeps the tube from twisting
            n = (prev_n - t * prev_n.dot(t)).normalized()
        prev_n = n
        b = t.cross(n)
        rr = r * (taper[i] if taper else 1.0)
        ring = [bm.verts.new(p + (n * math.cos(a) + b * math.sin(a)) * rr)
                for a in (j / seg * 2 * math.pi for j in range(seg))]
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(seg):
            bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][(j + 1) % seg], rings[i][(j + 1) % seg]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    ob = mesh_obj(name, bm, material)
    shade_smooth(ob)
    tube_uv(ob, seg, len(rings), pts, r)
    return ob


def tube_uv(ob, seg, nrings, pts, r):
    """UVs along the length in metres so textures don't stretch on cables."""
    me = ob.data
    uvl = me.uv_layers.new(name="UVMap")
    dist = [0.0]
    for i in range(1, len(pts)):
        dist.append(dist[-1] + (pts[i] - pts[i - 1]).length)
    circ = 2 * math.pi * r
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            ring, j = divmod(vi, seg)
            ring = min(ring, nrings - 1)
            uvl.data[li].uv = (j / seg * circ, dist[ring])


def bezier_points(p0, p1, sag=0.0, steps=12, ctrl=None):
    """Points on a sagging cable from p0 to p1 (quadratic curve)."""
    p0, p1 = Vector(p0), Vector(p1)
    c = Vector(ctrl) if ctrl else (p0 + p1) / 2 + Vector((0, 0, -sag))
    return [tuple((1 - t) ** 2 * p0 + 2 * (1 - t) * t * c + t * t * p1)
            for t in (i / steps for i in range(steps + 1))]


def shade_smooth(ob, angle=40):
    """Smooth shading, but keep edges sharper than `angle` degrees crisp."""
    me = ob.data
    for p in me.polygons:
        p.use_smooth = True
    me.set_sharp_from_angle(angle=math.radians(angle))


def add_bevel(ob, width, segments=2):
    mod = ob.modifiers.new("bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.harden_normals = False
    return mod


def world_uv(ob, scale=1.0):
    """Box-project UVs from world coordinates (1 UV unit = 1 metre)."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active
    mw = ob.matrix_world if ob.matrix_world else Matrix()
    bpy.context.view_layer.update()
    mw = _compose(ob)
    nm = mw.to_3x3().inverted_safe().transposed()
    for poly in me.polygons:
        n = (nm @ poly.normal).normalized()
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y * (1 if n.x > 0 else -1), co.z
            elif ax == 1:
                u, v = co.x * (-1 if n.y > 0 else 1), co.z
            else:
                u, v = co.x, co.y * (1 if n.z > 0 else -1)
            uvl.data[li].uv = (u * scale, v * scale)


def _compose(ob):
    return Matrix.LocRotScale(Vector(ob.location), ob.rotation_euler.to_quaternion(), Vector(ob.scale))


def planar_uv(ob, axis="Y"):
    """0..1 UVs over the object's bounding box on a plane (decals/dials)."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active
    xs = [v.co for v in me.vertices]
    ia, ib = {"X": (1, 2), "Y": (0, 2), "Z": (0, 1)}[axis]
    amin, amax = min(c[ia] for c in xs), max(c[ia] for c in xs)
    bmin, bmax = min(c[ib] for c in xs), max(c[ib] for c in xs)
    for poly in me.polygons:
        for li in poly.loop_indices:
            c = me.vertices[me.loops[li].vertex_index].co
            uvl.data[li].uv = ((c[ia] - amin) / max(amax - amin, 1e-6),
                               (c[ib] - bmin) / max(bmax - bmin, 1e-6))


def empty(name, loc, rot=(0, 0, 0), size=0.3, kind="PLAIN_AXES", props=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = kind
    e.empty_display_size = size
    e.location = loc
    e.rotation_euler = rot
    for k, v in (props or {}).items():
        e[k] = v
    return link(e)


def collider(name, size, loc, rot=(0, 0, 0)):
    """Invisible box collision (Godot '-colonly' import hint)."""
    ob = box(name + "-colonly", size, loc, None, rot=rot, uv=False)
    ob.display_type = "WIRE"
    ob.hide_render = True
    return ob


# -------------------------------------------------- per-part box collision
#
# One axis-aligned box over a whole prop makes flat or splayed geometry
# (puddles, leg splay, lamp arms, slid-open doors) inflate into an invisible
# wall metres away from anything the player can see. `part_colliders()` instead
# fits a box per visible part, throws away the parts nothing should bump into,
# and merges the rest only while a merge stays tight.

# Cosmetic parts that are solid enough to survive the geometric filters below
# but must never block the player.
NONSOLID_PARTS = frozenset((
    "blood", "puddle", "spill", "residue", "shard", "drag", "finger", "smear",
    "paper", "form", "folder", "label", "tag", "toe_tag", "card", "number",
    "cable", "wire", "hose", "zip", "line", "chain", "cord", "bubble",
    "fluid", "liq", "drape", "curtain", "blanket", "coat", "rag", "dead",
    "glass", "collar", "pane", "window", "lens", "screen", "readout", "scr",
))
MIN_SOLID_THICK = 0.02     # thinner than this is a pane/sheet/wire: no collision
PANEL_SPAN = 0.35          # ... unless it spans this much both ways (a shelf)
MIN_SOLID_SIZE = 0.10      # smaller than this in every axis is a trinket
STEP_OVER = 0.12           # parts entirely below this are walked over
COL_MIN = 0.05             # smallest collider box Godot should get
ROUND_DIA = 1.0            # round parts this wide get a 12-gon, not a box
ROUND_TOL = 0.08           # how straight a part's silhouette must be to count


def _part_base(ob):
    return ob.name.split(".")[0]


def round_collider(name, r, h, loc, rot=(0, 0, 0), seg=12):
    """Invisible 12-gon prism collision: a box over a wide cylinder leaves
    invisible corners sticking out by 41% of its radius."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r / math.cos(math.pi / seg), radius2=r / math.cos(math.pi / seg),
                          depth=max(h, COL_MIN))
    ob = mesh_obj(name + "-colonly", bm, None)
    ob.location = loc
    ob.rotation_euler = rot
    ob.display_type = "WIRE"
    ob.hide_render = True
    return ob


SPLIT_VOL = 0.12           # only parts with a box this big are worth splitting
SPLIT_LEN = 0.7            # ... and this long
SPLIT_GAIN = 0.4           # keep the split only if it costs this much of the box


def _slab_boxes(ob, size, rot):
    """Boxes that follow a long bent part (a pipe, an arc, a cable run) instead
    of one box around its diagonal. None when splitting does not pay off."""
    if _vol(size) < SPLIT_VOL or max(size) < SPLIT_LEN:
        return None
    bb = [Vector(c) for c in ob.bound_box]
    lo = Vector([min(v[i] for v in bb) for i in range(3)])
    hi = Vector([max(v[i] for v in bb) for i in range(3)])
    axis = max(range(3), key=lambda i: hi[i] - lo[i])
    n = min(8, max(2, int(math.ceil((hi[axis] - lo[axis]) / 0.4))))
    step = (hi[axis] - lo[axis]) / n
    sc = [abs(s) for s in ob.scale]
    cuts = []
    for k in range(n):
        a0, a1 = lo[axis] + k * step, lo[axis] + (k + 1) * step
        sel = [v.co for v in ob.data.vertices if a0 - 1e-6 <= v.co[axis] <= a1 + 1e-6]
        if not sel:
            cuts.append(None)       # a plain box has vertices only at its corners
            continue
        slo = Vector([min(p[i] for p in sel) for i in range(3)])
        shi = Vector([max(p[i] for p in sel) for i in range(3)])
        slo[axis], shi[axis] = a0, a1
        cuts.append((slo, shi))
    # a slab with no vertices of its own spans whatever its neighbours span, so
    # splitting a solid box gives the box back and is rejected by the gain test
    for k, c in enumerate(cuts):
        if c is not None:
            continue
        near = [d for d in (next((cuts[m] for m in range(k, -1, -1) if cuts[m]), None),
                            next((cuts[m] for m in range(k, n) if cuts[m]), None)) if d]
        if not near:
            return None
        slo = Vector([min(d[0][i] for d in near) for i in range(3)])
        shi = Vector([max(d[1][i] for d in near) for i in range(3)])
        slo[axis] = lo[axis] + k * step
        shi[axis] = lo[axis] + (k + 1) * step
        cuts[k] = (slo, shi)
    out = []
    for slo, shi in cuts:
        ssize = Vector([(shi[i] - slo[i]) * sc[i] for i in range(3)])
        out.append((ob.matrix_world @ ((slo + shi) / 2), ssize, rot, _vol(ssize)))
    if not out or sum(b[3] for b in out) > SPLIT_GAIN * _vol(size):
        return None
    return out


def _round_part(ob, size):
    """(radius, is_round): a part whose silhouette around its own Z axis is a
    circle (cylinder, disc, ring) rather than a box."""
    if abs(size.x - size.y) > 0.02 + 0.05 * max(size.x, size.y):
        return 0.0, False
    vs = ob.data.vertices
    if len(vs) < 8:
        return 0.0, False
    bb = [Vector(c) for c in ob.bound_box]
    cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
    cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
    rs = [math.hypot(v.co.x - cx, v.co.y - cy) for v in vs]
    rmax = max(rs)
    if rmax < 1e-4 or (rmax - min(rs)) / rmax > ROUND_TOL:
        return 0.0, False
    return rmax * abs(ob.scale.x), True


def _local_box(ob):
    """(centre, size, rot) of a part's own bounding box in its parent frame."""
    bb = [Vector(c) for c in ob.bound_box]
    lo = Vector([min(v[i] for v in bb) for i in range(3)])
    hi = Vector([max(v[i] for v in bb) for i in range(3)])
    s = ob.scale
    size = Vector([(hi[i] - lo[i]) * abs(s[i]) for i in range(3)])
    ctr = ob.matrix_world @ ((lo + hi) / 2)
    return ctr, size, tuple(ob.rotation_euler)


def _corners(ctr, size, rot):
    m = Matrix.Translation(ctr) @ Euler(rot).to_matrix().to_4x4()
    return [m @ Vector((sx * size.x / 2, sy * size.y / 2, sz * size.z / 2))
            for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]


def _world_aabb(ctr, size, rot):
    pts = _corners(ctr, size, rot)
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def _vol(size):
    return max(size.x, 1e-4) * max(size.y, 1e-4) * max(size.z, 1e-4)


MERGE_GAP = 0.25           # never merge across a horizontal gap wider than this
MERGE_GAP_Z = 0.6          # ... or a vertical one wider than this
FORCED_WASTE = 5.0         # over the box cap, merges may be this much looser


def _gap(a, b):
    """(horizontal, vertical) empty gap between two boxes (0 = they overlap).
    Merging across a real gap is what turns a jammed-open door or a row of bars
    into an invisible wall, so the gap caps apply to every merge."""
    lo_a, hi_a = _world_aabb(*a[:3])
    lo_b, hi_b = _world_aabb(*b[:3])
    g = [max(lo_b[i] - hi_a[i], lo_a[i] - hi_b[i], 0.0) for i in range(3)]
    return max(g[0], g[1]), g[2]


def _merge_pair(a, b):
    """Merged box of two (ctr, size, rot, solid) entries, kept oriented when
    both share a rotation, otherwise their axis-aligned union."""
    if max(abs(a[2][i] - b[2][i]) for i in range(3)) < 1e-4:
        rot = a[2]
        inv = Euler(rot).to_matrix().inverted()
        pts = []
        for e in (a, b):
            pts += [inv @ p for p in _corners(e[0], e[1], e[2])]
        lo = Vector([min(p[i] for p in pts) for i in range(3)])
        hi = Vector([max(p[i] for p in pts) for i in range(3)])
        ctr = Euler(rot).to_matrix() @ ((lo + hi) / 2)
        return (ctr, hi - lo, rot, a[3] + b[3])
    lo_a, hi_a = _world_aabb(*a[:3])
    lo_b, hi_b = _world_aabb(*b[:3])
    lo = Vector([min(lo_a[i], lo_b[i]) for i in range(3)])
    hi = Vector([max(hi_a[i], hi_b[i]) for i in range(3)])
    return ((lo + hi) / 2, hi - lo, (0, 0, 0), a[3] + b[3])


def part_colliders(name, parts, skip=(), max_boxes=20, waste=1.5, floor=0.0):
    """Collision boxes that hug `parts` (the prop's meshes before they are
    joined). Returns a list of collider objects, possibly empty.

    skip      extra part-name substrings that should not collide
    max_boxes soft cap: above it looser merges are allowed, but a merge never
              bridges a gap the player could walk through (MERGE_GAP)
    waste     a merge is free while merged volume <= waste * the solid volume
              of the parts inside it
    floor     colliders are clipped to this Z and never pushed below it
    """
    boxes = []
    rounds = []
    for ob in parts:
        if ob.type != "MESH":
            continue
        base = _part_base(ob)
        if base in NONSOLID_PARTS or any(k and k in base for k in skip):
            continue
        ctr, size, rot = _local_box(ob)
        dims = sorted(size)
        if dims[2] < MIN_SOLID_SIZE:                       # trinket
            continue
        # a thin part only collides if it is a real panel (shelf, cage wall,
        # table top) rather than a pane, strap, blade of grass or sheet of paper
        if dims[0] < MIN_SOLID_THICK and dims[1] < PANEL_SPAN:
            continue
        lo, hi = _world_aabb(ctr, size, rot)
        if hi.z <= floor + STEP_OVER:
            continue
        r, is_round = _round_part(ob, size)
        if is_round and 2 * r >= ROUND_DIA:
            rounds.append((ctr, r, size.z, rot))
            continue
        slabs = _slab_boxes(ob, size, rot)
        boxes += slabs if slabs else [(ctr, size, rot, _vol(size))]

    while len(boxes) > 1:
        over = len(boxes) > max_boxes
        best = None
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                hg, vg = _gap(boxes[i], boxes[j])
                if hg > MERGE_GAP or vg > MERGE_GAP_Z:
                    continue            # merging these would wall off a real gap
                m = _merge_pair(boxes[i], boxes[j])
                cost = _vol(m[1]) / m[3]
                if cost > waste and not (over and cost <= FORCED_WASTE):
                    continue
                if best is None or cost < best[0]:
                    best = (cost, i, j, m)
        if best is None:
            break
        cost, i, j, m = best
        boxes = [b for k, b in enumerate(boxes) if k not in (i, j)] + [m]

    out = []
    total = len(boxes) + len(rounds)
    for k, (ctr, size, rot, _solid) in enumerate(boxes):
        size = Vector([max(s, COL_MIN) for s in size])
        if max(abs(r) for r in rot) < 1e-4:          # clip flat boxes to the floor
            lo_z, hi_z = ctr.z - size.z / 2, ctr.z + size.z / 2
            if lo_z < floor:
                lo_z = min(floor, hi_z - COL_MIN)
                size.z = hi_z - lo_z
                ctr = Vector((ctr.x, ctr.y, (lo_z + hi_z) / 2))
        out.append(collider(f"{name}_col{k}" if total > 1 else f"{name}_col",
                            tuple(size), tuple(ctr), rot))
    for k, (ctr, r, h, rot) in enumerate(rounds):
        out.append(round_collider(f"{name}_round{k}", r, h, tuple(ctr), rot))
    return out


def apply_all(objs=None):
    """Apply transforms + modifiers so exported meshes are clean."""
    objs = objs or [o for o in bpy.context.scene.objects if o.type == "MESH"]
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in objs:
        if ob.type != "MESH":
            continue
        ev = ob.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
        old = ob.data
        ob.modifiers.clear()
        ob.data = me
        if old.users == 0:
            bpy.data.meshes.remove(old)


def join(objs, name):
    """Join mesh objects into one (fewer draw calls)."""
    objs = [o for o in objs if o and o.type == "MESH"]
    if not objs:
        return None
    apply_all(objs)
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs,
                                   selected_objects=objs):
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


# ------------------------------------------------------------------ export

IMPORT_STUB = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[params]

import_script/path="res://tools/timbuk_post_import.gd"
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
animation/import=true
"""


def export_glb(path, objs=None, animations=False):
    """Export to res:// path (relative to repo root) and add the import stub."""
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    if objs is not None:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
            for c in o.children_recursive:
                c.select_set(True)
    anim_kw = dict(export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                   export_skins=True, export_def_bones=False, export_frame_step=1) if animations else {}
    bpy.ops.export_scene.gltf(
        filepath=full, export_format="GLB", use_selection=objs is not None,
        export_materials="VIEWPORT", export_apply=not animations, export_yup=True,
        export_animations=animations, export_extras=True, export_lights=False,
        export_cameras=False, **anim_kw)
    stub = full + ".import"
    if not os.path.exists(stub):
        with open(stub, "w") as f:
            f.write(IMPORT_STUB)
    print("exported", path)


def save_blend(path):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=full, compress=True)


# ------------------------------------------------------------------ preview renders

def render_preview(out, cam_loc, target, lens=50, res=(800, 800), samples=48,
                   lights=None, world=0.03, engine="CYCLES"):
    s = bpy.context.scene
    s.render.engine = engine
    if engine == "CYCLES":
        s.cycles.device = "CPU"
        s.cycles.samples = samples
        s.cycles.use_denoising = True
        s.cycles.max_bounces = 6
    s.render.resolution_x, s.render.resolution_y = res
    s.render.film_transparent = False
    s.view_settings.view_transform = "AgX"
    w = s.world or bpy.data.worlds.new("w")
    s.world = w
    w.color = (world, world, world)
    if w.node_tree:
        bg = w.node_tree.nodes.get("Background")
        if bg:
            bg.inputs["Color"].default_value = (world, world, world * 1.1, 1)
    cam = bpy.data.objects.get("PreviewCam")
    if not cam:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        s.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.clip_end = 500
    cam.location = cam_loc
    d = Vector(target) - Vector(cam_loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    s.camera = cam
    made = []
    for i, (kind, loc, energy, col, *extra) in enumerate(lights or []):
        ld = bpy.data.lights.new(f"PL{i}", kind)
        ld.energy = energy
        ld.color = col
        if kind == "AREA":
            ld.size = extra[0] if extra else 2.0
        if kind == "SPOT":
            ld.spot_size = math.radians(extra[0] if extra else 45)
        lo = bpy.data.objects.new(f"PL{i}", ld)
        lo.location = loc
        lo.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        s.collection.objects.link(lo)
        made.append(lo)
    s.render.filepath = out
    bpy.ops.render.render(write_still=True)
    for lo in made:
        bpy.data.objects.remove(lo)
    print("rendered", out)
