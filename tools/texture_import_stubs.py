"""Write Godot .import stubs so textures import as VRAM-compressed 3D textures
and *_normal.png files are flagged as normal maps. Run after texgen.py."""
import os
D = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
for f in sorted(os.listdir(D)):
    if not f.endswith(".png"):
        continue
    stub = os.path.join(D, f + ".import")
    if os.path.exists(stub):
        continue
    normal = f.endswith("_normal.png")
    rough = f.endswith(("_rough.png", "_metal.png"))
    with open(stub, "w") as fh:
        fh.write(f'''[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality={"true" if normal else "false"}
compress/normal_map={1 if normal else 2}
mipmaps/generate=true
roughness/mode=0
detect_3d/compress_to=0
''')
print("ok")
