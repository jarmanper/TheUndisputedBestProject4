"""Render creature previews:
blender -b <file.blend> --python preview_creature.py -- <out_prefix> <anim|rest> <frame> [height] [views]"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import tlib as T
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
out, anim, frame = a[0], a[1], int(a[2])
H = float(a[3]) if len(a) > 3 else 1.75
views = a[4].split(",") if len(a) > 4 else ["front", "threeq", "side", "face"]
s = bpy.context.scene
for ob in s.objects:
    if ob.type == "ARMATURE" and ob.animation_data:
        for tr in ob.animation_data.nla_tracks:
            tr.mute = (tr.name != anim)
        if anim == "rest":
            ob.data.pose_position = "REST"
s.frame_set(frame)
T.box("floor", (8, 8, 0.1), (0, 0, -0.05), "concrete")
T.box("wall", (8, 0.2, 5), (0, 2.5, 2.5), "concrete_damaged")
cams = {
    "front": ((0, -3.6 * H / 1.75, H * 0.55), (0, 0, H * 0.5), 50),
    "threeq": ((2.3 * H / 1.75, -2.6 * H / 1.75, H * 0.7), (0, 0, H * 0.5), 50),
    "side": ((3.6 * H / 1.75, 0, H * 0.55), (0, 0, H * 0.5), 50),
    "face": ((0.25 * H / 1.75, -0.75 * H / 1.75, H * 0.93), (0, 0, H * 0.9), 70),
}
lights = [("AREA", (-1.5, -2.5, 3.0), 500, (1.0, 0.92, 0.85), 2.0),
          ("AREA", (2.0, 1.5, 2.5), 350, (0.5, 0.7, 1.0), 1.5),
          ("POINT", (0.6, -1.2, 0.5), 30, (1.0, 0.4, 0.2))]
for v in views:
    loc, tgt, lens = cams[v]
    T.render_preview(f"{out}_{v}.png", loc, tgt, lens=lens, res=(640, 800), samples=32, world=0.02, lights=lights)
