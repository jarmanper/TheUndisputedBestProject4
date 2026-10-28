# October 28 assignment integration

`playtest-integration` starts from `origin/full-game2` (`aa255d6`). Inspected `origin/main` (`fc9a889`), `origin/full-game` (`9f843ab`) and `origin/rhaiyn-marking-playable` (`f0a360c`). The latter supplied the Marking reference; it was not merged or cherry-picked wholesale. AGENTS.md was missing from full-game2 and is restored from main, with the integration authorization, architecture, route and implemented word budget recorded.

## Play

Use Godot 4.7.2, F5, New Game. F6 also works with `scenes/game/main.tscn` or `final_chamber.tscn` open. WASD moves; mouse turns the shoulder camera; Left Mouse/Q/E/R activate Combat/Marking/Suspend/Explosion; Esc pauses and releases or captures the mouse. No jump or other gameplay actions.

The first level instances the existing A/B/C facility areas, with 12 required 100 HP patients. Required doors are open; blank metal geometry closes unused branches and the lower stairs. All patients exist at the start. Clearing them automatically loads the existing Twin chamber as a separate final level with one required 100 HP Twin already present. There are no reinforcements or optional targets. All four abilities start ready in each level. Death reloads the current level after 2 active seconds. Last-target death records victory immediately; same-step player death suppresses the deferred win notification and transition. The final win uses a wordless green overlay.

The original title/settings, new patient models, Twin, lighting, ambient audio, laboratory furniture, failed containment device and experiment tanks remain. Original generated scenes and assets are unchanged relative to full-game2. Compatibility adaptations are process-local: substitute inert cached FogMaterials before loading, remove unsupported volumes from the instance, and duplicate the supplied Environment for fixed ambient light. Unsupported original environment/skin features produce non-fatal warnings; there are no remaining gameplay script errors or unsupported fog-shader errors in the validated rendered run.

Found story: the checkpoint's newspaper at the entrance (23 words), Experiment 024 report in research (25 words), and broken containment hardware show disappearances, inherited time abilities, and failed experiments. No interact key is needed. The implemented game text totals 48 words. Random creature speech is disabled before its audio nodes enter the tree. The much longer full-game2 dialogue/objective layer was removed. Original mesh lettering is merged into map detail meshes, so eight visual-only blank panels cover those sign areas without editing generated graphics. Title and controls text is exempt from the cap.

## Assignment repairs

- Combat: one crosshair target, visible and within 3 m inclusive, instant 20 damage, 0.6 s cooldown, new press only. Marked hits reduce Suspend's remaining cooldown by 1 s including lethal hits; no multiplier, ammo, reload or mark consumption.
- Marking: Q, 15 m inclusive, 8 s duration, 3 s cooldown, one mark, refresh/replacement and invalid-input semantics from Rhaiyn's prototype. No damage, movement interruption, suspension change, or loss on wall/range exit. Depth-tested outline and icon above the visual; wall occlusion suppresses the icon without removing the mark.
- Suspend: E, visible target within 12 m inclusive, 2 s or 4 s if marked at activation, 7 s cooldown, one frozen target. Fixed position, solid collision, damageable; fresh duration on re-suspend. Wind-up cancellation starts the enemy's 2 s attack wait, which continues during suspension.
- Explosion: R, living visible marked target within 15 m, instant sphere at target center, exactly 4 m inclusive, 40 damage normally or 60 total if suspended, geometry-only occlusion, each target once. Snapshots suspension before consuming mark/damage, then ends affected suspensions and resolves defeats. 5 s cooldown. Invalid activation preserves mark/cooldown. No player damage, force, falloff, projectile, chain reaction or damaging fire.
- Enemies, including Twin: 100 HP; chase begins within 8 m and persists, navigates at 2.5 m/s; visible player within 2 m starts 0.75 s wind-up, resolving for 10 damage only if still visible/in range; 2 s wait after resolve/cancel. No sound hunting, headshots, boss phases or special boss stats.
- Player: 100 HP, no regeneration, fixed upright capsule, targeting origin exactly 1.4 m above collider bottom, wordless health/cooldown HUD. Removed sprint, crouch/stamina/noise rules, interact, flashlight toggle, pickups/keys, generator progression, door unlocking, gun/reload/ammo and thrown explosive gameplay. The visual-only weapon model's unused animation helper remains because an existing generated prop references it; it cannot reload or attack in this build.

## Reproduce validation

Replace `godot` below with the Godot executable:

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/validate_resources.gd
godot --headless --path . --script tests/assignment_mechanics.gd
godot --headless --path . --fixed-fps 60 --script tests/playtest_integration.gd
godot --path . --fixed-fps 60 --script tests/rendered_playtest.gd
```

Development checks, not human tester results:

| Validation | Result |
| --- | --- |
| Editor import and script resource audit | 24 gameplay/UI/visual scripts compile, 0 failures |
| Exact mechanics suite | 59 checks, 0 failures |
| Route/lifecycle/input/budget/export-configuration suite | 78 checks, 0 failures |
| Rendered live title-to-game run | 12 checks, 0 failures, including all four mapped inputs, combo, camera, occlusion, live navigation/attacks/death/restart |
| Navigation | All 12 patient positions and Twin reachable on baked navmesh; physical WASD traversal around props reaches containment |
| Word audit | 48 displayed story words; creature speech disabled; eight legacy sign areas masked |
| Rendering | OpenGL 3.3 Compatibility on NVIDIA RTX 3050 Laptop GPU; original unsupported environment feature warnings only |

The mechanics suite uses real physics rays with deterministic active-time deltas at timer boundaries. The route suite checks inclusive ranges, geometry, all target routes, actual input mappings, held-Q behavior, physical movement, pause, same-step loss, restart and separate final-level progression. The live suite lets the real AI attack the real damageable player; it simulates over 30 seconds of active gameplay. PNG captures under ignored `.godot/captures/` cover title, start, marked/suspended target, occlusion, explosion, enemy attack, loss and restart. These were inspected. The route suite can also capture with `-- --capture` and save navmeshes with `-- --save-nav`; remove stale nav files first when rebaking changed geometry.

No measured human completion time is claimed. Full facility side wings and lower tunnels are deliberately outside this playtest route.

## Web export

`export_presets.cfg` provides a Web preset targeting `docs/index.html` with `variant/thread_support=false`, and `docs/.gdignore` exists. Dynamic map/effect/material/nav resources are included; source/test/tools/docs are excluded from the pack. [Godot's Web documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html) describes Compatibility and single-thread export, and the [Web preset reference](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformweb.html) documents the thread option.

Attempted:

```powershell
godot --headless --path . --export-release Web docs/index.html
```

**Export blocked:** the installed Godot 4.7.2 editor has neither expected template:

```text
C:/Users/rhyne/AppData/Roaming/Godot/export_templates/4.7.2.stable/web_nothreads_debug.zip
C:/Users/rhyne/AppData/Roaming/Godot/export_templates/4.7.2.stable/web_nothreads_release.zip
```

Godot reports “Cannot export project with preset Web due to configuration errors” and “No export template found at the expected path.” No index.html, WASM, JS or PCK export is claimed, and no browser test was performed. Install matching 4.7.2 export templates, rerun the export, then test the generated build over HTTP. Desktop Compatibility validation does not prove web performance or browser compatibility. This missing-template blocker is why the integration PR is left for review rather than automatically merged.
