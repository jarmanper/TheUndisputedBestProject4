"""Build a contact sheet of texture albedos: blender -b --python contact_sheet.py -- <outpng> [suffix]"""
import bpy, os, sys, numpy as np
args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]; suffix = args[1] if len(args) > 1 else "_albedo.png"
d = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures")
names = sorted(f for f in os.listdir(d) if f.endswith(suffix))
T = 192; cols = 6; rows = (len(names) + cols - 1) // cols
sheet = np.zeros((rows * T, cols * T, 4), np.float32); sheet[..., 3] = 1
for i, f in enumerate(names):
    im = bpy.data.images.load(os.path.join(d, f))
    w, h = im.size
    px = np.array(im.pixels[:], np.float32).reshape(h, w, 4)
    step = max(1, w // T)
    px = px[::step, ::step][:T, :T]
    r, c = rows - 1 - i // cols, i % cols
    sheet[r*T:r*T+px.shape[0], c*T:c*T+px.shape[1]] = px
    print(i, f)
img = bpy.data.images.new("sheet", cols * T, rows * T)
img.pixels = sheet.ravel()
img.filepath_raw = out; img.file_format = 'PNG'; img.save()
