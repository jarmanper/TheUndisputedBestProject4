"""Write Godot .import stubs for assets/audio WAVs: files named *_loop* or amb_*
import as forward-looping streams, everything else as one-shots."""
import os
D = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
for root, _, files in os.walk(D):
    for f in files:
        if not f.endswith(".wav"):
            continue
        loop = "_loop" in f or f.startswith("amb_")
        with open(os.path.join(root, f + ".import"), "w") as fh:
            fh.write(f'''[remap]

importer="wav"
type="AudioStreamWAV"

[params]

force/max_rate=false
force/mono=true
edit/trim=false
edit/normalize=false
edit/loop_mode={2 if loop else 1}
edit/loop_begin=0
edit/loop_end=-1
compress/mode=2
''')
print("ok")
