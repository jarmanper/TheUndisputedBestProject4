"""Top-down section render of the facility: blender -b timbuk_facility.blend --python plan_view.py -- out.png cut_z"""
import bpy, sys, math
argv = sys.argv[sys.argv.index("--") + 1:]
out, cut = argv[0], float(argv[1])
s = bpy.context.scene
cam = bpy.data.objects.new("PlanCam", bpy.data.cameras.new("PlanCam"))
s.collection.objects.link(cam)
cam.data.type = "ORTHO"; cam.data.ortho_scale = float(argv[2]) if len(argv) > 2 else 150
cx, cy = (float(argv[3]), float(argv[4])) if len(argv) > 4 else (5.5, 47)
cam.location = (cx, cy, 60); cam.rotation_euler = (0, 0, 0)
cam.data.clip_start = 60 - cut; cam.data.clip_end = 200
s.camera = cam
s.render.engine = "BLENDER_WORKBENCH"
sh = s.display.shading
sh.light = "STUDIO"; sh.color_type = "MATERIAL"; sh.show_shadows = True; sh.show_cavity = True
s.render.resolution_x, s.render.resolution_y = 700, 1500
s.render.filepath = out
bpy.ops.render.render(write_still=True)
