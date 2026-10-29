# Rhaiyn Newby — complete Marking delivery

Owner: **Rhaiyn Newby**, Team 4, COMP 440 Project 4. Work branch: `playtest-integration`; integration PR: [#3](https://github.com/jarmanper/TheUndisputedBestProject4/pull/3).

## Delivery and scope

The complete Marking mechanic is implemented in the real integrated game, not just the standalone prototype. F5 opens `scenes/ui/title_screen.tscn`; New Game loads `scenes/game/main.tscn`, whose Player instances `scripts/game/mechanics/marking.gd`. Clearing that level loads `final_chamber.tscn`; the same Marking script also works on the Twin.

At the beginning of this audit, remote main `785fbb7` still contained the incorrect full-game2 mechanic (RMB, multiple marks, wrong range/duration/cooldown and marked damage multiplier), while `playtest-integration` contained the compliant integrated architecture. Main, playtest-integration and rhaiyn-marking-playable were inspected before changes. The latest main deployment workflow was merged into the integration branch; an export-preset add/add conflict was resolved using the already validated preset with the same Web name, threads disabled, runtime resources included, and docs output. No newer mechanic changes were overwritten. The three pre-existing local editor/import changes were preserved and excluded from this delivery's commits.

This audit changed Marking's own lifecycle code and added focused acceptance tests. Combat, Suspend, Explosion, enemy code, map scenes and graphics assets were not edited by this Marking follow-up. Their existing compliant integration APIs were exercised instead. Marking now rejects direct activation while paused, and clears/detaches its target reference and callbacks before a target exits the level or is freed. Replacement and teardown remain idempotent; neither writes suspension state.

## Specification acceptance

| Requirement | Evidence |
| --- | --- |
| Physical Q; center-screen crosshair; first living target | Native InputEventKey Q test, nearest-collider test, real facility and Twin tests |
| Geometry/visibility at activation | Real physics wall tests; invalid attempt preserves the previous mark |
| Range 15 m inclusive; 15.001 m invalid | Collider-center to exact player upper-body-point boundary tests |
| One mark; replacement; same-target refresh | Old target clears, new target owns the sole mark, refresh sets exactly 8 seconds |
| Exactly 8-second duration and 3-second cooldown | Checks just before and at the boundaries, using active-gameplay deltas |
| Invalid activation starts no cooldown and leaves old mark/timer intact | Out-of-range, empty-crosshair and wall tests |
| Cooldown presses ignored, never queued; holding does not repeat | Physical Q pressed during cooldown, held past readiness, then released and freshly pressed |
| Persistence after range or visibility loss | Existing mark survives target movement past 15 m and new geometry between player and target |
| Expiration, defeat, consumption and level cleanup | Direct timer/defeat tests, target destruction, owner teardown, actual restart with live mark and actual next-level transition |
| No damage or interruption | HP, movement velocity, wind-up state, wind-up remaining time and enemy attack cooldown unchanged by Marking |
| Bright outline and small overhead icon | Existing materials applied to all creature meshes; icon placed above measured visual bounds; rendered captures inspected |
| No visual through walls | Existing depth-tested shaders retained; occluded icon hidden; inspected occlusion capture shows neither outline nor icon through the test wall |
| Combat preserves mark and reduces Suspend cooldown by 1 s | Nonlethal and lethal marked-hit tests; actual native Left Mouse integration |
| Suspend snapshots mark state at activation | Unmarked activation stays 2 s after marking; marked activation starts 4 s; refresh/removal/expiry never change that duration |
| Explosion requires current mark and consumes only on success | Invalid occluded explosion preserves mark/cooldown; successful explosion uses mark despite crosshair looking away, consumes it, and deals 60 total to suspended target |

All time checks use seconds of active gameplay; pausing freezes timers. Timing is resolved at Godot physics-step precision, not a claim of wall-clock subframe accuracy.

## Reproduce and results — October 29, 2026

Godot used: `4.7.2.stable.official.ed1daf0bf`. These are automated development checks and visually inspected engine renders, not fabricated human playtest results.

```powershell
godot --headless --path . --editor --import --quit
godot --headless --path . --fixed-fps 60 --script tests/marking_complete.gd
godot --headless --path . --fixed-fps 60 --script tests/marking_final_game.gd
godot --path . --fixed-fps 60 --script tests/marking_final_game.gd
godot --headless --path . --script tests/assignment_mechanics.gd
godot --headless --path . --fixed-fps 60 --script tests/playtest_integration.gd
godot --headless --path . --script tests/validate_resources.gd
```

| Suite | Result |
| --- | --- |
| Complete Marking acceptance | 36 checks, 0 failures |
| Actual final-game Marking, headless | 19 checks, 0 failures |
| Actual final-game Marking, rendered Compatibility | 19 checks, 0 failures |
| Existing assignment mechanics regression | 59 checks, 0 failures |
| Existing integrated route/lifecycle regression | 78 checks, 0 failures |
| Script resource audit | 28 scripts compile, 0 failures |

Rendered artifacts are saved under ignored `.godot/captures/` as `marking_final_marked.png`, `marking_final_occluded.png`, `marking_final_suspended.png`, `marking_final_restarted.png` and `marking_final_twin.png`. The marked, occluded and Twin captures were inspected. Test-only walls and manually reset cooldowns are fixtures, not changes to shipping gameplay. The Twin test aims the shoulder-camera ray, accounting for its lateral offset; turning only the body toward the Twin would not aim the center-screen crosshair.

## Files in this Marking follow-up

- `scripts/game/mechanics/marking.gd` — Rhaiyn's mechanic; paused activation and safe target/level cleanup.
- `tests/marking_complete.gd` and `tests/marking_complete.gd.uid` — full mechanic acceptance and all three interactions.
- `tests/marking_final_game.gd` and `tests/marking_final_game.gd.uid` — physical input, feedback, live-mark restart and both integrated levels.
- `AGENTS.md` — completion/API record; displayed word budget unchanged.
- `docs/MARKING_COMPLETION.md` — this delivery and reproducible evidence.
- `docs/PLAYTEST_INTEGRATION.md` — link to the focused Marking follow-up.

The separate main-sync merge also preserves `.github/workflows/deploy-pages.yml` and resolves `export_presets.cfg`; neither is new Marking gameplay. Earlier implementation history is preserved: `e5388c8` (standalone Marking/core), `f0a360c` (prototype evidence), and `e3111ac` (correct integrated mechanic). The new dedicated Marking commit supplies ownership/evidence for this completion audit.

## Remaining work for Rhaiyn's mechanic

No Marking implementation, integration or acceptance-test item remains in the validated build. Repository delivery/merge status is tracked by PR #3. Any future teammate changes to targeting, enemy lifecycle, Combat/Suspend/Explosion or level loading should rerun these two focused suites. Web export and other game-wide work are separate from this Marking completion; no successful web/browser run is claimed here.
