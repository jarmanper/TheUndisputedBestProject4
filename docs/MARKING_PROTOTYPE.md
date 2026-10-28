# Rhaiyn's playable Marking prototype

Branch: `rhaiyn-marking-playable`. Based on main `fc9a889`, including the merged graphics-v2 PR and shared AGENTS.md. Shared gameplay core is claimed by Rhaiyn Newby. No generated scenes, existing assets, import settings, visual scripts, or teammates' mechanic files were edited.

## Run

Open the project in Godot 4.7.2 and press F5. For F6, open `scenes/game/marking_prototype.tscn` first; F6 always runs the currently open scene. WASD moves, mouse turns the shoulder camera, Q marks, and Esc pauses/resumes and releases/recaptures the mouse. No jump. Left Mouse, E and R are reserved inputs with no gameplay yet.

The scene starts in the lobby of Jarman's existing full facility with three stationary failed-humanoid targets. The nearest target is already under the crosshair. Existing paper and photo props provide set dressing. The HUD has a health bar, crosshair, orange Marking cooldown ring, and gray reserved ability icons. Marking uses the existing outline and tracker hologram materials. No mark-duration UI, dialogue, labels, or other story words were added. Test-target speech is disabled in the wrapper, leaving source audio unchanged.

## Integration

- Add sibling ability Nodes under `Player/Abilities` named `Combat`, `Suspend`, `Explosion`, using the scripts owned by Rickey, Jarman and Daniel. HUD discovers these names and reads `cooldown_left` and `COOLDOWN` automatically.
- `Player.crosshair_target(range_m)` selects using geometry/target layers, then checks collider-center distance from the exact upper-body point and geometry-only visibility. `Player.take_hit(amount)` clamps HP and signals death.
- Extend `Target` for Rickey's actual enemies; call `super()` if overriding `_ready()`. Add `CollisionShape3D` centered on the main body. `center()`, `is_alive()`, `apply_damage()`, `marked`, `suspended`, `mark_changed` and `defeated` form the shared API. Death clears effects and removes collision immediately. The fixture's NavigationAgent is a placeholder; no AI or navmesh was implemented.
- Marking owns its timers and `current_target`. Explosion can read the target, validate/snapshot its explosion, then call `consume_mark()`. `clear_mark()` is also available. These methods never change suspension. Combat can snapshot `target.marked` before `apply_damage()` as required for lethal-hit cooldown reductions.
- The level manager registers every required target at start. It records the win immediately, defers the victory notification until same-step damage can resolve, lets loss override that win, and reloads after 2 active gameplay seconds on loss. There is no progression or victory UI in this prototype.
- `Facility` loads the original `timbuk_facility.tscn` into `Facility/Graphics` at runtime. The editor viewport therefore does not preview the map. Compatibility cannot compile FogMaterial: the adapter supplies inert runtime resource-cache replacements for the four fog materials before loading the map, removes unsupported FogVolumes, and duplicates the supplied Environment for fixed ambient fill without auto-exposure. It never writes asset files. Original lights, sky, models, props, collision and ambience remain in use.

## Validation performed October 28, 2026

These are automated development checks and inspected renders, not human playtest results.

Godot used: `4.7.2.stable.official.ed1daf0bf`. Rendered run reports OpenGL 3.3 Compatibility on NVIDIA GeForce RTX 3050 Laptop GPU.

| Check | Result |
| --- | --- |
| Full editor import and script registration | Passed; no parse errors |
| Isolated Marking suite | 37 checks, 0 failures |
| Facility suite, headless | 31 checks, 0 failures |
| Facility suite, rendered | 34 checks, 0 failures |
| Player movement and collision | Automated WASD moves through lobby, remains on floor, stops at existing wall/props |
| Targeting | Crosshair first target, geometry blocking, upper-body occlusion despite camera visibility, exactly 15 m accepted, 15.001 m rejected |
| Mark lifetime/cooldown | Deterministic active-time checks immediately before and at 8 s / 3 s; refresh resets to 8 s; pause freezes both |
| Replacement/input | Only one marked target, no damage, suspension/motion unchanged, held Q does not repeat, invalid input starts no cooldown |
| Persistence/cleanup | Existing mark survives leaving range and wall occlusion; defeat, consumption and teardown clear it |
| Gameplay integration | Physical Q event, actual InputMap, mouse camera, Esc pause/capture, victory/loss priority and automatic restart |
| Visual QA | Inspected start, marked, occluded and paused PNGs: visible orange outline and icon above target, neither visible through test wall, readable wordless HUD |
| F5/F6 configuration | Main scene points at prototype; running that scene succeeds; F6 requires it to be the open scene |

Reproduce (replace `godot` with your Godot executable):

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/core/run_marking_tests.gd
godot --headless --path . --fixed-fps 60 --script tests/core/run_prototype_tests.gd
godot --path . --fixed-fps 60 --script tests/core/run_prototype_tests.gd -- --capture
```

The last command saves `prototype_start.png`, `prototype_marked.png`, `prototype_occluded.png` and `prototype_paused.png` under ignored `.godot/captures/`. Deterministic timer tests advance active gameplay deltas; they do not claim wall-clock precision beyond the physics step. The headless integration suite briefly lets the audio mixing thread release the original map's looping playbacks before exiting.

## Remaining work and limits

Nothing blocks movement and Marking in this desktop prototype. Combat, enemy approach/attacks/navigation, Suspend and Explosion are intentionally pending with their owners, so the final four-mechanic game and normal combat victory/defeat loop are not complete. The player uses a simple capsule visual. Only lobby traversal was exercised; the full facility has not had a human navigation playtest. Web export was not built or tested.

Original resources emit non-fatal Compatibility warnings for unsupported SSIL, volumetric fog, auto-exposure and (rendered) subsurface scattering. The runtime adapter prevents the unsupported fog-shader error and supplies readable fixed lighting; these warnings do not block playability. Jarman can later author native Compatibility materials/environment settings. The repository's existing source-voice word-budget issue remains for the story owner; this prototype does not play those spoken lines.

Computer-use inspection was rejected by automatic approval review with “Computer Use was not approved to use 2-stable_win64.” Visual QA instead used Godot-generated frame captures; no manual UI playtest is claimed.

## Every file created or changed

Changed:
- `AGENTS.md`
- `project.godot`

Created:
- `scenes/game/player.tscn`
- `scenes/game/marking_prototype.tscn`
- `scenes/enemies/marking_test_target.tscn`
- `scripts/abilities/marking.gd`
- `scripts/abilities/marking.gd.uid`
- `scripts/core/player.gd`
- `scripts/core/player.gd.uid`
- `scripts/core/target.gd`
- `scripts/core/target.gd.uid`
- `scripts/core/mark_feedback.gd`
- `scripts/core/mark_feedback.gd.uid`
- `scripts/core/hud.gd`
- `scripts/core/hud.gd.uid`
- `scripts/core/pause_controller.gd`
- `scripts/core/pause_controller.gd.uid`
- `scripts/core/level_manager.gd`
- `scripts/core/level_manager.gd.uid`
- `scripts/core/facility_instance.gd`
- `scripts/core/facility_instance.gd.uid`
- `tests/core/run_marking_tests.gd`
- `tests/core/run_marking_tests.gd.uid`
- `tests/core/run_prototype_tests.gd`
- `tests/core/run_prototype_tests.gd.uid`
- `docs/MARKING_PROTOTYPE.md`
