"""Render a lineup of props: blender -b --python preview_props.py -- out.png name1 name2 ..."""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import tlib as T, props as P
argv = sys.argv[sys.argv.index("--") + 1:]
out, names = argv[0], argv[1:]
T.reset()
cols = math.ceil(math.sqrt(len(names) * 1.6))
for i, n in enumerate(names):
    objs = P.PROPS[n][0]()
    meshes = [o for o in objs if o.type == "MESH"]
    body = T.join(meshes, n); T.shade_smooth(body, 35)
    r, c = divmod(i, cols)
    body.location.x += c * 2.6; body.location.y += r * 2.6
xmax = (cols - 1) * 2.6; ymax = (math.ceil(len(names) / cols) - 1) * 2.6
T.box("floor", (xmax + 8, ymax + 8, 0.1), (xmax / 2, ymax / 2, -0.05), "lab_floor")
T.render_preview(out, (xmax / 2, -6 - ymax * 0.4, 3.5 + ymax * 0.6), (xmax / 2, ymax / 2, 0.6), lens=28,
                 res=(1400, 900), samples=40, world=0.08,
                 lights=[("AREA", (xmax / 2, ymax / 2 - 2, 7), 1800, (1, 0.97, 0.92), 10),
                         ("POINT", (-3, -4, 3), 400, (0.6, 0.8, 1.0))])
