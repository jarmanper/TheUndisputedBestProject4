"""Tile screenshots: blender -b --python montage.py -- out.png cols img1 img2 ..."""
import bpy, sys, numpy as np
a = sys.argv[sys.argv.index("--") + 1:]
out, cols, files = a[0], int(a[1]), a[2:]
W, H = 640, 360
rows = (len(files) + cols - 1) // cols
sheet = np.zeros((rows * H, cols * W, 4), np.float32); sheet[..., 3] = 1
for i, f in enumerate(files):
    im = bpy.data.images.load(f); w, h = im.size
    px = np.array(im.pixels[:], np.float32).reshape(h, w, 4)
    ys = (np.arange(H) * h / H).astype(int); xs = (np.arange(W) * w / W).astype(int)
    px = px[ys][:, xs]
    r, c = rows - 1 - i // cols, i % cols
    sheet[r*H:(r+1)*H, c*W:(c+1)*W] = px
img = bpy.data.images.new("m", cols * W, rows * H); img.pixels = sheet.ravel()
img.filepath_raw = out; img.file_format = 'PNG'; img.save()
