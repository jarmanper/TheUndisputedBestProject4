# TIMBUK graphics guide

Everything visual in this repo (3D models, materials, lighting, creatures, effects) and how to use it. None of it contains gameplay logic. Combat, Marking, Suspend and Explosion belong to their owners. These assets are meant to be hooked up by them.

## See it

1. Open the project in Godot 4.7.
2. Press **F5**. The main scene is `scenes/visual_inspection.tscn`. Change it in Project Settings if you want your own scene.
3. Controls: mouse to look, **WASD** to move, **Q/E** down/up, **Shift** fast, **1–9 / 0** or **Tab** to jump between viewpoints, **F** flashlight, **G** toggle fog, **H** hide help.

Other scenes worth opening:

| Scene | What it is |
| --- | --- |
| `scenes/environments/timbuk_facility.tscn` | The whole facility: all five areas plus environment, fog, probes |
| `scenes/environments/area_*.tscn` | One area each: entrance (+security, admin), research, containment, lower levels (+tunnels, generator, flooded storage, incinerator), twin chamber, cell block, west wing, east wing |
| `scenes/cinematics/twin_reveal.tscn` | The Twin reveal: camera push-in to the face (press F6) |
| `scenes/effects/effects_gallery.tscn` | Every effect looping side by side |
| `scenes/characters/*.tscn` | Creatures (twin, failed humanoid, augmented, chemical) |
| `scenes/props/*.tscn` | 49 props, each with collision and any built-in lights |

## Layout

```
assets/materials/   shared .tres materials (built from source/materials.json)
assets/textures/    generated PBR textures; vfx/ holds particle sprites
assets/models/      GLB exports (environment/, props/, characters/)
assets/shaders/     VFX shaders (temporal distortion, outline, hit flash, ...)
scenes/             Godot scenes (see table above)
scripts/visual/     visual-only helpers (light flicker, creature anim, vfx player)
source/             Blender + texture generator source (ignored by Godot)
tools/              build scripts that regenerate everything
```

## Using it from gameplay code

**Effects.** Instance a scene from `scenes/effects/` and call `play()`. Set `free_when_done = true` for one-shots.

```gdscript
var boom := preload("res://scenes/effects/explosion_orange.tscn").instantiate()
boom.autoplay = false
boom.free_when_done = true
get_tree().current_scene.add_child(boom)
boom.global_position = where
boom.play()
```

- Combat: `muzzle_flash` (barrel points along -Z), `impact_sparks` (surface normal = +Y), `bullet_hole`, and `assets/materials/fx_hit_flash.tres` (set as `material_overlay`, animate `flash` 1 → 0).
- Marking: `tracking_indicator` (place at the target's feet), `assets/materials/fx_marked_outline.tres` (set as `material_overlay`). `scenes/props/tracker_device.tscn` is the handheld model.
- Suspend: `suspend_field` (animate the material's `strength` 0–1 to fade it), `suspended_particles`, and `scripts/visual/afterimage_spawner.gd` (`spawn(mesh_instance)` leaves a fading ghost of the current pose).
- Explosion: `explosion_{orange,green,blue,purple}`, `fire_{orange,green,blue,purple}`, `scorch_mark`.

**Creatures.** Each character scene has `creature_visual.gd`. Call `play_visual("walk")`.
- Failed experiments: `idle`, `walk`, `react`, `twitch`.
- Twin: `idle`, `head_tilt`, `eye_scan`, `clock_spin`, `twitch`, `wire_vibrate`, `walk_slow`, `posture_shift`, `reveal`.
- Models face +Z and animate in place (no root motion).

**Models.** `pistol`, `keycard`, `old_key`, `tracker_device` are in `scenes/props/`. The pistol has a `MUZZLE` node at the barrel tip.

## Map layout (graphics-v2)

Roughly three times the original floor space, with loops so players can explore rather than walk one line:

- Entrance: lobby, security office (pistol + keycard on the desk), admin cubicles
- Research corridor and labs, plus a **west wing** (break room, locker room and showers, dormitory, archive maze, service tunnel, specimen storage that loops back into containment) and an **east wing** (clock workshop, animal lab, morgue, surgical theatre with observation gallery)
- **Cell block F**: 14 barred cells off a long corridor, a warden's office, and a link corridor back into the containment hall
- Containment hall and control room
- Lower levels: stairs, corridors, the twins' room, plus a maintenance tunnel to the generator room, a long tunnel to the flooded storage room, a hidden west passage into the twin chamber, and an incinerator
- Twin chamber

## Sound

- `assets/audio/ambience/`: room ambience, placed per room automatically (Ambience bus)
- `assets/audio/sfx/`: prop and light loops, effect sounds, footsteps (`footstep_concrete_0..3`, `footstep_metal_0..3`) for the player controller
- `assets/audio/creatures/` and `assets/audio/voices/`: creature loops, groans and spoken lines. Each character scene has a `CreatureAudio` node that randomly speaks or groans; call `say("help_me")` or `vocalize()` from gameplay code.
- Buses: Ambience, SFX, Voices (`default_bus_layout.tres`).
- Rebuild: `python3 source/audio/sfxgen.py`, then `python3 tools/audio_import_stubs.py`. Voice lines are listed in `source/audio/voice_lines.txt` (raw takes come from Windows text-to-speech, then get distorted).

## Rebuilding assets

Everything is generated by scripts, so the visuals can be changed and rebuilt. Run from the repo root (WSL / Linux shell, Blender 5 on PATH):

```bash
python3 source/textures/texgen.py                      # PBR textures + VFX sprites
blender -b --factory-startup --python source/blender/props.py
blender -b --factory-startup --python source/blender/build_facility.py
blender -b --factory-startup --python source/blender/creatures.py
blender -b --factory-startup --python source/blender/clockwork_brother.py   # the Twin (twin_monster.py is a helper)
tools/godot.sh script res://tools/build_materials.gd     # .tres materials
tools/godot.sh import                                    # import GLBs/textures
tools/godot.sh script res://tools/build_scenes.gd        # props, areas, facility, characters, inspection, reveal
tools/godot.sh script res://tools/build_effects.gd       # effects + gallery
tools/godot.sh script res://tools/qa_check.gd            # missing-material / budget report
tools/godot.sh --resolution 1280x720 --script res://tools/capture.gd -- res://scenes/visual_inspection.tscn
```

`build_scenes.gd` regenerates the scenes it owns. Put your gameplay nodes in your own scenes that instance these, rather than editing generated scenes directly.

How it works, briefly:
- Rooms are rectangles on a 10 cm floor-plan grid (`build_facility.py`). Walls, door headers and window sills are derived from the grid. Blender empties named `P__<prop>`, `L__<light>`, `ROOM__`, `VIEW__` tell Godot where to put props, lights, probes/fog and camera viewpoints.
- Creatures are modelled as signed distance fields (muscles, bones, facial features blended smoothly), meshed with surface nets, then rigged with distance-based skin weights. Animations are keyframed procedurally.
- All meshes export with placeholder material names. `tools/timbuk_post_import.gd` swaps in the shared `.tres` materials at import time.

## Performance

At 1920×1080 on the dev laptop (Radeon RX 7700S), GPU render time is about 8–9 ms in every area and in the reveal, so there's comfortable headroom for 60 FPS. Lights fade out with distance, glass and fluids skip shadow maps, and Godot generates mesh LODs on import. SSR is disabled because it smears additive effects and the reflection probes cover reflections.

## Known gaps

- The Twin now follows `assets/references/twin_monster_reference.png`. It is procedural, so close-up detail is simpler than the painting.
- Creature faces and hands are procedural, so they read well at gameplay distance but are simpler than hand-sculpted models up close.
- Documents/newspaper props are blank paper. Readable text (Label3D) is left for whoever owns the story content, to avoid adding new narrative.
