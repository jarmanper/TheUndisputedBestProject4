# The four mechanics, as built (Nov 2 2026)

What this branch implements, measured against **AGENTS.md section 5** ("Team 3's
mechanics (exact; do not change)"), which is the transcription of Team 3's doc
and the thing a grader will check against.

## Where the spec came from

Until now this branch's mechanics were guesses: the per-member text files
(`JarmanPerry.txt` and friends) are 32 bytes each and only name a mechanic, so
nobody on our side had numbers to build to. The numbers were in two places all
along:

- **AGENTS.md section 5** - the transcription of Team 3's mechanics doc.
- **`origin/playtest-integration`**, `docs/PLAYTEST_INTEGRATION.md` - a teammate's
  independent reconstruction, plus `tests/assignment_mechanics.gd`.
- **`origin/rhaiyn-marking-playable`**, `docs/MARKING_PROTOTYPE.md` - Rhaiyn's
  own Marking prototype, which is first-party for Marking and also defines the
  shared Player/Target API every ability plugs into.

All three agree. The mechanics on this branch did not agree with any of them, so
they were rebuilt rather than adjusted.

## What changed, per mechanic

| | Spec | What this branch had before |
| --- | --- | --- |
| Combat | 20 damage, 3 m, 0.6 s, no ammo | 25 damage, 60 m, 0.28 s, 8-round magazine + reload |
| Marking | 15 m, 8 s, 3 s cd, **one** mark | 40 m, 15 s, 0.4 s cd, three marks, double damage |
| Suspend | 12 m, 2 s (4 s if marked), 7 s cd, one target | 30 m, 4 s flat, 10 s cd, 10 m area freeze |
| Explosion | instant on the marked target, 4 m, 40 / 60 | thrown charge, 2 s fuse, 5 m, chain reactions, knockback |
| Enemies | all 100 HP, 8 m, 2.5 m/s, 0.75 s wind-up, 10 damage | 75 HP, 14 m, 3.2 m/s, instant 15 damage, headshots; Twin had 400 HP and two phases |
| Player | 100 HP, one speed, aim from 1.4 m | sprint, crouch, stamina, noise, interact, flashlight |

Presentation was kept wherever it is not a rule: muzzle flash and gun kick, the
tracker hologram and marked outline, suspend afterimages and particles, the
orange blast and scorch decal, camera shake, footsteps and head bob.

## Consequences worth knowing

- **Combat is now a 3 m attack, not a gun.** At 3 m with a 0.6 s cooldown, five
  hits kill one 100 HP patient while it closes at 2.5 m/s and hits for 10. The
  intended answer is the signature combo, which kills in one cycle:
  Mark -> Suspend (4 s) -> two Combat hits (40) -> Explosion on a suspended
  target (60) = 100.
- **Input is LMB / Q / E / R**, and `sprint`, `interact`, `reload`, `flashlight`
  and `crouch` are gone from the InputMap entirely.
- **Dialogue advances on Space or Enter**, not E, because E is Suspend now.
- **Every scripted door opens at load.** The Twin's chamber used to be sealed
  behind `power_restored`, which came from the generator, which needed the
  keycard pickup. The rules allow no interact action, so none of those flags can
  ever be set and the Twin would have been permanently unreachable. The keycard
  and generator remain in the world as things the player finds but cannot
  operate.
- **The HUD is wordless**: four unlabelled cooldown meters in the same order as
  the controls list, instead of an ammo counter and `MARKS`/`SUSPEND`/`CHARGES`
  status lines. This is required by section 6, and it also took the word budget's
  strict reading from 182 to 140 (see AGENTS.md 4.5).
- **The level is won by defeating all 9 required targets** (8 patients and the
  Twin), not by the Twin alone, and a player death in the same step beats the win.

## The web build

The browser build never loaded for either Oct 28 playtester. **The renderer was
not the reason**, contrary to what this document said on Nov 2. Godot registers
`rendering/renderer/rendering_method.web = "gl_compatibility"` as a built-in
default, so a project left on Forward+ still exports a Compatibility web build -
verified by querying `ProjectSettings` directly:

```
rendering/renderer/rendering_method          = forward_plus
rendering/renderer/rendering_method.web      = gl_compatibility   <- engine default
rendering/renderer/rendering_method.mobile   = mobile
```

The web build was therefore always running Compatibility. What actually broke it:

- **Payload size.** 271 MB with desktop-sized textures. Fixed earlier by
  `tools/web_export.sh` (512 px, no mesh LODs): now 106 MB.
- **A blocking load.** One `change_scene_to_file()` froze the single-threaded
  tab. Fixed earlier by `scenes/web/loading_screen.tscn`, which warms the asset
  library in 24 ms slices.
- **Things Compatibility cannot draw.** This one was real and is fixed here.
  Because the web build was already Compatibility, the 52 FogVolumes across the
  eight area scenes were erroring in the browser the whole time -
  Compatibility cannot compile `FogMaterial` at all, which is a hard error, not
  a warning. `TimbukCompat.adapt()` (`scripts/visual/compat.gd`) now detaches
  them before the first frame, along with SSR, SSAO, SSIL, SDFGI, volumetric fog
  and auto-exposure, lifting ambient light to compensate. `ui_settings.gd` also
  skips its Forward+ only calls there.

**The project renderer stays Forward+, and must.** Setting it to
`gl_compatibility` project-wide was tried on Nov 2 and the *editor* segfaults
with it (`CrashHandlerException: signal 11`) during startup on an AMD Radeon
RX 7700S - every launch, before it loads a scene. Ruled out in turn: the fog
scenes (it crashes with no scene open), a stale D3D12 shader cache (it crashes
on a cache OpenGL itself wrote) and the shader cache entirely (it crashes with
`shader_compiler/shader_cache/enabled=false`). The *game* runs fine in
Compatibility; only the editor is affected. To preview what the browser renders,
force it per run instead: `godot --path . --rendering-method gl_compatibility`,
which is what `tests/compat_smoke.gd` does.

`tools/web_export.sh` additionally pins the renderer project-wide for the
duration of the export and restores it afterwards, so the shipped pack states
`gl_compatibility` outright rather than depending on a feature tag resolving in
a browser nobody here can test.

Two console errors remain on Compatibility, both harmless: `shader type fog not
supported in OpenGL renderer`, logged once per `FogMaterial` as the scene loads
and before the volumes are detached.

## Reproducing the checks

Replace `godot` with the Godot 4.7.2 executable.

```bash
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/validate_resources.gd
godot --headless --path . --script tests/assignment_mechanics.gd
godot --path . --rendering-method gl_compatibility --script tests/compat_smoke.gd
godot --path . --rendering-method gl_compatibility --script tests/rendered_playtest.gd
godot --path . --rendering-method gl_compatibility --script tests/newgame_flow.gd
```

The last three need a real window, not `--headless`, because the whole point is to
compile shaders and draw frames.

| Check | Result |
| --- | --- |
| Script and scene load audit | 44 loaded, 0 failures |
| Exact mechanics suite | 59 checks, 0 failures |
| Compatibility smoke run | 180 rendered frames, 52 fog volumes dropped, exit 0 |
| Live input playtest | 29 checks, 0 failures |
| New Game flow (title -> loading screen -> game) | reaches the game scene in 23.4 s with all 9 targets staged and both doors open |
| Web export | produced `index.html` + `.wasm` + `.pck` with the `web_nothreads_release` template |

The live playtest drives the real scene with real input events: it marks with
Q, freezes with E and confirms the mark bought the 4 s version, deals 20 with a
click, detonates with R for 60 on the suspended target, walks the player with W,
lets a real patient close in and hit for 10, confirms both Twin chamber doors are
open at load, and wins the level by defeating all nine required targets without
that also counting as a loss.

These are automated checks and a produced build, not human playtest results.
**The exported build has not been opened in a browser from this machine**, so
"the web build loads" is not yet proven - only that the cause of the hang is
removed and the game runs on the renderer the browser uses.

**Where the live link comes from.** The assignment requires the export to be
committed at `docs/index.html`, with an empty `docs/.gdignore` beside it, and
Pages served from `main` / `/docs`. The Web preset now exports there, and
`tools/web_export.sh docs/index.html` is what builds it (512 px textures, no
mesh LODs - the desktop asset set is far too big for a browser and would also
blow past GitHub's 100 MB per-file limit). `.github/workflows/deploy-pages.yml`
no longer deploys on push: a Pages site has one source, and it would fight the
`/docs` source for it.

Two consequences to act on:
- **Re-export after every change.** The live link plays the last committed
  export, not the latest code.
- **This work is on `visual-rehaul`.** Pages serves `main`, so none of it is
  live until the branch is merged.

Still needing a human: loading the deployed build in a browser, and walking the
route from the entrance to the Twin. No automated check here proves the facility
is navigable end to end - only that nothing is sealed shut and every target is
reachable in principle.
