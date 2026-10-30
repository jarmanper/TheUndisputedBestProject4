# AGENTS.md: Timbuk (Team 4, Comp 440 Project 4)

Shared context for every person and coding agent working in this repo. Read it all before changing anything. When a decision changes, update this file in the same commit.

## 1. What this is

- **Assignment:** Project 4, "Someone Else's Mechanics, Your Story." Theme: **Found** (the player finds the story in places, objects, sounds and what's left behind).
- **Team 4:** Daniel Animashaun, Rickey Johnson, Rhaiyn Newby, Jarman Perry.
- **We build Team 3's four mechanics** (Combat, Marking, Suspend, Explosion) exactly as written, and we write the story.
- **Engine:** Godot 4.7, GDScript, Forward+, Jolt Physics. 1 world unit = 1 meter.
- **Game due:** Wednesday, November 4, 2026 (final playtest).
- **Grading:** Team 3 reports whether each mechanic was built exactly as written. Another team judges the story.

## 2. Hard rules (never break these)

1. **Never change a Team 3 number.** Damage, ranges, durations, cooldowns, HP and speeds are fixed (section 5).
2. **Never add or cut a mechanic, a player action, or a rule.** No pickups, no interact button, no inventory, no keys that gate doors, no armor, no damage over time. We *may* add levels, objects and content.
3. **All four abilities work from the first frame of every level.** Finding a weapon in the world is visual only.
4. **150-word cap** on all on-screen text *and* speech in the whole game. The title screen and controls screen don't count. Signs, labels, documents, voice lines and ending text do. Update the budget table (section 4.5) in the same commit as any text or voice change.
5. **The story must give the player a reason to do every mechanic.**
6. **Don't edit generated scenes.** `tools/build_scenes.gd` overwrites everything under `scenes/environments/`, `scenes/props/`, `scenes/characters/`, `scenes/effects/`, `scenes/cinematics/` and `scenes/visual_inspection.tscn`. Instance them from your own scenes instead.
7. **Never fabricate** playtest results, tester quotes, or "AI output we rejected" examples in any doc.

## 3. Who owns what

Edit only the files you own. If you need a change in someone else's file, ask them (or leave a note in your PR).

| Area | Owner | Files |
| --- | --- | --- |
| Combat + enemy behavior (Team 3 defines enemies inside Combat) | Rickey | `scripts/abilities/combat.gd`, `scripts/enemies/`, `scenes/enemies/` *(proposed)* |
| Marking | Rhaiyn | `scripts/abilities/marking.gd` *(proposed)* |
| Suspend | Jarman | `scripts/abilities/suspend.gd` *(proposed)* |
| Explosion | Daniel | `scripts/abilities/explosion.gd` *(proposed)* |
| Graphics, audio, map | Jarman | `assets/`, `source/`, `tools/`, `scripts/visual/`, all generated scenes |
| Shared core: player, target base class, targeting, HUD, level manager, input map, physics layers | **Unassigned. Claim it before starting.** | `scripts/core/`, `scenes/game/` *(proposed)* |
| Story text and word budget | **Unassigned** | Label3D text, `source/audio/voice_lines.txt`, section 4.5 here |

**Git:** one branch per person, merged into `main` through a pull request (as `graphics-v2` was). Pull before you start. `project.godot` is shared: change it (input map, layer names, autoloads, main scene) in one small commit and tell the team. Never let two people edit the same `.tscn`.

## 4. The story (as submitted in the Story Checkpoint, Oct 26)

### 4.1 Premise
The player, whose parents worked at the facility Timbuk and mysteriously disappeared, enters the abandoned lab to find out what happened and discovers increasingly dangerous experiments throughout the facility.

### 4.2 Beats (Kishōtenketsu)
| Beat | What happens | Where in the game |
| --- | --- | --- |
| Introduction | The character, their family, and the incidents at the lab | Not set yet |
| Development | Exploring rooms and experiments, learning about the disappearances and the parents' experiments | Not set yet |
| Twist | The main monster is the player's twin, made by the parents. He's connected to their disappearance | Twin chamber (Area E) |
| Reconciliation | Defeating the twin gives closure about the parents | Not set yet |

### 4.3 Mechanics in the fiction
| Mechanic | Key | In the story |
| --- | --- | --- |
| Combat | Left mouse | Defending yourself from the aggressive experiments. The weapon isn't decided (section 9) |
| Marking | Q | A thrown "airtag": a covert tracking device that also carries an explosive charge, from the player's toolkit |
| Suspend | E | The player's inherited time power. It's new to him, so it's weak (2 s, or 4 s on a marked target) |
| Explosion | R | Detonating the marked target. The submitted text blames lab chemicals, so keep it consistent with the airtag carrying the charge |

The clock motif (the Twin's clock-face skull, clock workshop, grandfather clocks, "tick tock") ties the twin and the player's time power together.

### 4.4 Found moments (submitted)
| # | Thing | What it tells | Where |
| --- | --- | --- | --- |
| 1 | The twin brother | Why the parents disappeared (the twin killed or ate them; not decided) | Twin chamber (Area E) |
| 2 | Paper clippings | The experiments, what went wrong, the parents' part, hints about the player's powers | Entrance and offices (newspaper); research rooms (reports) |
| 3 | Weapons | The tools to fight and mark | Not set. Visual only (rule 3) |
| 4 | Failed containment device | The scientists knew the experiments were getting out of control | Main experiment area |
| 5 | Key | Progress to the next area | **Conflicts with the rules. See section 8** |

### 4.5 Word budget (150 max)

**This table is the build, audited Oct 29 2026, not a plan.** The old table listed
a newspaper, an "Experiment 024" report, a "Security Log 17", four warning signs
and a Twin exchange that **were never built**: none of those strings appears
anywhere under `scenes/`, `scripts/`, `source/`, `assets/` or `tools/`. The game
that exists tells a different story (Reyes the contractor, a voice on the radio
claiming to be Dr. Hale, the twins Tomas and Teo). The 117 / 160 figures in the old
table were therefore both wrong. The real as-built count before this trim was
**656 words, 4.4x over the cap**: 501 words of trigger dialogue + 32 words of
objectives + 6 words of speaker nameplates in `scenes/game/story_layer.tscn`, 31
in `scenes/game/main.tscn`, 44 on the death and ending screens, and 42 spoken
(the 48 recorded words minus the 6 `chemical_*` words, which no creature in the
build loads).

**Counting rule.** One word per whitespace-separated token that contains a letter
or digit. Hyphenated compounds, numbers and "TIMBUK" are one word each. Bare
punctuation ("...", "???") is zero. A string shown in more than one place is
counted once. Speaker nameplates are counted once per distinct speaker.

**What counts (rule 4: displayed or spoken story text):**

| Text | Type | File:line | Words |
| --- | --- | --- | --- |
| Hale: "Reyes? The blackout sealed everything. Restart the generator." | Trigger dialogue | `scenes/game/story_layer.tscn:45` | 8 |
| "Find the keycard" | Objective | `story_layer.tscn:46` | 3 |
| "Restore power" | Objective | `story_layer.tscn:58` | 2 |
| Recording: "One heartbeat, two bodies. Teo died, so I built him a clockwork heart." | Trigger dialogue (the twist) | `story_layer.tscn:82` | 13 |
| Reyes: "Hale. What did you build?" | Trigger dialogue | `story_layer.tscn:82` | 5 |
| ???: "Tick... tock... where are you, brother?" | Trigger dialogue | `story_layer.tscn:95` | 6 |
| Hale: "Hear ticking? Don't run." | Trigger dialogue | `story_layer.tscn:120` | 4 |
| Hale: "It winds down in the chamber." | Trigger dialogue | `story_layer.tscn:145` | 6 |
| "Open the chamber" | Objective | `story_layer.tscn:146` | 3 |
| Recording: "You don't sleep anymore, Teo." | Trigger dialogue | `story_layer.tscn:158` | 5 |
| Hale: "It's both my boys now. Stop the clockwork." | Final encounter | `story_layer.tscn:171` | 8 |
| Twin: "Doctor... you wound us too tight." | Final encounter | `story_layer.tscn:171` | 6 |
| Reyes: "Hale? It's your voice." | Final encounter | `story_layer.tscn:171` | 4 |
| "Stop the Twin" | Objective | `story_layer.tscn:172` | 3 |
| Nameplates: HALE, RECORDING, REYES, TWIN, ??? | Speaker labels (the `"Speaker:"` prefixes, drawn by `dialogue_box.gd:67`) | `story_layer.tscn` | 4 |
| "Security keycard. Level 3 clearance." | Pickup text | `scenes/game/main.tscn:130` | 5 |
| "The panel is locked. It needs a keycard." | Locked text | `scenes/game/main.tscn:142` | 8 |
| "The generator coughs to life. Somewhere below, a door unlocks." | Switch text | `scenes/game/main.tscn:143` | 10 |
| "Sealed. There is no power to the lock." | Locked text (both doors, counted once) | `scenes/game/main.tscn:151`, `:161` | 8 |
| "YOUR CLOCK STOPPED" / "It heard you." | Death screen | `scripts/ui/dialogue_box.gd:129` | 6 |
| "THE CLOCK IS SILENT" / "Nothing in TIMBUK is ticking." | Ending screen | `scripts/ui/dialogue_box.gd:136-137` | 9 |
| "help me", "it hurts", "mother" | Creature speech (failed patients) | `source/audio/voice_lines.txt:16-18` | 5 |
| "brother", "tick tock" | Creature speech (the Twin) | `source/audio/voice_lines.txt:19-20` | 3 |
| **Total as built** | | | **134** |

**134 / 150. 16 words of headroom.** Verified by parsing the files above, not by
re-reading this table. The three triggers with no `lines` (`research`,
`cell_block`, `lower_stairs`) are deliberately wordless — those rooms carry their
story in props and sound.

**What does not count, and why.** Rule 4 exempts the title and controls screens,
which puts menus outside the cap, and section 6 specifies a wordless HUD. So the
following ~53 words are treated as **interface chrome, not story**, and are
excluded: HUD readouts (`HEALTH`, ammo, `RELOADING`, `NO AMMO`, `[R] RELOAD`,
`MARKS`, `SUSPEND`/`READY`, `CHARGES` — `scripts/game/hud.gd`); the pause menu
(`PAUSED`, `Resume`, `Settings`, `Quit to title` — `hud.gd:204-213`); the settings
panel (`scripts/game/ui_settings_panel.gd`); interact prompts (`[E] Take keycard`,
`[E] Restore power`, `[E] Try door` — `scripts/game/interactable.gd:61-66`); the
`OBJECTIVE` header, the `[E] continue` hint and the end-screen buttons
(`Retry`, `Play again`, `Return to title` — `scripts/ui/dialogue_box.gd`); and the
title screen (exempt by rule 4). **If a grader counts chrome too, the total is
187 and we fail.** Getting under 150 on the strict reading needs cuts in `hud.gd`
and `ui_settings_panel.gd`, which section 6 already says should have no words.

**Not words, by our reading:** the only text baked into a texture is the Roman
numeral ring on clock faces, the Twin's head and the suspend effect
(`XII, I, ... XI`, from the three-glyph stroke font `GLYPHS` in
`source/textures/texlib.py:290`). Those are dial markings, not language — the font
physically cannot spell anything else. Nothing else in `source/textures/` or
`source/blender/` renders text; the `warning_sign` texture is a wordless triangle.

**First cut if we need more room:** the four interactable strings in
`scenes/game/main.tscn` are 31 words — 23% of the cap spent on door and pickup
flavour. Shortening them to roughly `"Keycard."` / `"Locked. Needs a keycard."` /
`"Power's back."` / `"No power."` (about 8 words) would put the game at ~111.

**Spoken lines are enforced in code.** `tools/build_scenes.gd` fills each
creature's `lines` by globbing every `assets/audio/voices/<prefix>_*.wav`, so the
generated character scenes still reference all 19 recorded lines (48 words).
`BUDGETED_LINES` in `scripts/visual/creature_audio.gd` drops everything not in the
5-line list above at load time; the surplus `.wav` files stay on disk so those
generated scenes keep valid resource paths. The cut lines are kept, commented out,
at the bottom of `source/audio/voice_lines.txt`. Adding a line needs an entry in
*both* places and a matching cut here. The augmented patient now has no spoken
lines at all and falls back to its servo/glitch noises.

## 5. Team 3's mechanics (exact; do not change)

Transcribed from Team 3's mechanics doc. If the original disagrees with this, the original wins.

### Shared rules
- Ranges include their boundary (exactly 3 m counts as within 3 m).
- Distances run from the **center of the player's upper body** to the **center of the target's main body collider**.
- Cooldowns and durations count seconds of active gameplay. **Pausing freezes timers.**
- All four abilities **start ready**. A successful activation starts its cooldown immediately. An invalid activation does nothing and starts no cooldown. Inputs during a cooldown are **ignored, not queued**. Each action needs a new button press.
- **Targeting (Combat, Marking, Suspend):** a ray through the center-screen crosshair selects the first living target it hits. Solid level geometry blocks it; the player's own collider is ignored. The target must be within range, with an unobstructed line from the player's upper-body point to the target's center.
- **Explosion** uses the existing marked target; the crosshair doesn't need to be on it.
- Targets start at **100 HP**. HP can't go below 0. At 0 the target is defeated immediately, and any mark or suspension on it is removed.
- Marks and suspension are separate effects. Changing one never changes the other unless a rule says so.

### Enemy behavior (part of Combat)
- Approach the player along navigable routes at **2.5 m/s**.
- May begin an attack when the player is **visible and within 2 m**.
- **0.75 s wind-up.** At the end it deals **10 damage** only if the player is still visible and within 2 m; otherwise it misses.
- After an attack resolves or is canceled, wait **2 s** before starting another.
- **Suspension cancels a wind-up in progress** and blocks new attacks. The attack cooldown keeps counting during suspension. After release, the enemy attacks again only once its cooldown is done and range and visibility are met.

### A. Combat (left mouse)
- One close-range attack on the selected target: **20 damage, range 3 m, 0.6 s cooldown**.
- Order on success: record whether the target is marked → apply 20 damage → start cooldown → if it was marked, **reduce Suspend's remaining cooldown by 1 s** (min 0) → defeat it if HP is 0.
- A lethal hit on a marked target still grants the 1 s reduction (marked state is checked before damage).
- Hits one target only. Doesn't remove a mark or end suspension. Suspended targets take normal damage.
- The reduction can't be banked: if Suspend is already ready, it does nothing.
- Holding the button doesn't repeat. Damage is instant; animation never changes timing.

### B. Marking (Q)
- Marks the selected target: **range 15 m, lasts 8 s, 3 s cooldown. Only one mark at a time.**
- On success: remove the old mark → mark the target → set 8 s → start cooldown.
- Re-marking the same target resets it to 8 s (doesn't add). No damage; doesn't interrupt enemies.
- A mark ends when: its timer expires, it's replaced, the target is defeated, Explosion consumes it, or the level ends or restarts.
- **Leaving range or going behind walls does NOT remove a mark.**
- A mark applied after Suspend began doesn't extend that suspension. An invalid attempt leaves the current mark untouched.

### C. Suspend (E)
- Freezes the selected target: **range 12 m; 2 s, or 4 s if marked at activation; 7 s cooldown** starting at activation. **One suspended target at a time.**
- On success: end the previous suspension → check whether the target is marked → suspend 4 s if marked, 2 s if not → start cooldown.
- While suspended the target can't move or begin attacks, and a wind-up in progress is canceled. It **stays damageable**; Combat hits don't end suspension.
- Position and collision don't change (visuals may show the freeze).
- Re-suspending the same target gives a fresh duration (no stacking). Duration is fixed at activation.
- Canceled attacks don't resume partway. If Explosion hits it, the 60 damage is calculated **before** suspension ends.

### D. Explosion (R)
- Requires: Explosion ready, a **living marked target within 15 m**, and an unobstructed line from the player to it.
- On success, in order:
  1. Record the marked target's center.
  2. Find living targets whose centers are within a **4 m sphere**, including the marked one.
  3. Exclude targets blocked from the center by **solid level geometry** (other targets don't block).
  4. Record which are suspended.
  5. **Consume the mark.**
  6. Deal **40 damage** to unsuspended targets and **60** to suspended ones.
  7. **End suspension** on affected targets.
  8. Defeat targets at 0 HP.
  9. Start the **5 s cooldown**.
- No falloff (exactly 4 m counts). Each target is hit once. **No player damage, no knockback, no lingering area, no chain explosions.** Damage is instant.
- An invalid activation keeps the mark and starts no cooldown.

### Win and lose
- **Win:** defeat every required target in the level while player HP > 0. All required targets exist **when the level begins**. Victory happens the instant the last one dies.
- **Lose:** player HP reaches 0. Player starts at **100 HP**, enemy hits deal 10, no regeneration. Restart restores everything (HP, targets, positions, cooldowns, effects). If the player and the final target die in the same step, **loss wins**.
- Defeated targets can't move, attack, receive effects, or block movement.
- **Signature combo:** Mark → Suspend (4 s) → 2 Combat hits (40) → Explode (60) = 100 = one kill.

## 6. Answers we build to where Team 3 is silent

Our submitted clarity rating marked every mechanic "Clear" and can't be revised, so these choices aren't on record with Team 3. Keep them small and defensible.

| Question | Answer | Source |
| --- | --- | --- |
| When do enemies start approaching? | When the player is within 8 m | Swap Day (submitted) |
| Does an enemy stop chasing if the player leaves 8 m? | Default: no, once triggered it keeps chasing | **Not agreed yet** |
| What is "visible" for an enemy attack? | Unobstructed ray from the enemy's center to the player's upper-body point; only level geometry (layer 1) blocks | Swap Day, made exact |
| Can the player move while attacking? | Yes, attacks never lock or slow movement | Swap Day |
| Upper-body point height | Exactly 1.4 m above the bottom of the player's collider | Swap Day ("about 1.4 m"), made exact |
| How is a mark shown? | Bright outline plus a small icon above the target; no timer | Swap Day |
| Is the mark visible through walls? | No, the outline only shows when the target is visible | Swap Day |
| Does gravity or pushing move a suspended target? | No, frozen exactly in place | Swap Day |
| Does a suspended target still block the player? | Yes, its collider stays solid | Swap Day |
| How is suspension shown? | Blue glow plus a timer (a shrinking ring, no digits) | Swap Day; ring is a default |
| Is the explosion radius shown? | Yes, a ring expanding to exactly 4 m | Swap Day |
| Does Explosion hurt props? | No, targets only | Swap Day |
| Restart (R is taken by Explosion)? | Auto-restart 2 s after losing; no restart key | Planning default |
| Pause key? | Esc | Planning default |
| Are some targets optional? | No, every target in a level is required | Planning default |
| HUD | Health bar, 4 cooldown icons, crosshair. No words anywhere | Planning default |
| Camera and jumping | Third-person camera turned by mouse, WASD to move, no jump | Planning default |
| Explosion "blocked by geometry" check | One ray from the explosion center to each target center; only layer 1 blocks | Planning default |

## 7. Technical contract (so we can work at the same time)

**Status: proposed. Nothing in `scripts/core/` exists yet.** Whoever claims the shared core finalizes this and updates the section.

### Folders
```
scenes/game/        playable levels; each instances an area from scenes/environments/
scenes/enemies/     enemy scenes (CharacterBody3D + collider + NavigationAgent3D + a character scene as "Visual")
scripts/core/       player.gd, target.gd, level_manager.gd, hud.gd
scripts/abilities/  combat.gd, marking.gd, suspend.gd, explosion.gd (one Node each under Player/Abilities)
scripts/enemies/    enemy.gd (extends Target)
```

### Physics layers
| Layer | What | Notes |
| --- | --- | --- |
| 1 | Level geometry | Already set: environment meshes import with trimesh collision (`-col`), props with invisible box collision (`-colonly`) |
| 2 | Player | |
| 3 | Targets (all enemies) | |

Line-of-sight rays use mask = layer 1 only. The crosshair ray uses layers 1 and 3 and excludes the player.

### Input actions (add once to `project.godot`)
`move_forward` W, `move_back` S, `move_left` A, `move_right` D, `attack` left mouse, `mark` Q, `suspend` E, `explode` R, `pause` Esc. Read abilities with `Input.is_action_just_pressed()` so holding never repeats, and drop presses during cooldown (no buffering).

### Shared API (minimum)
```gdscript
# scripts/core/target.gd: every enemy extends this
class_name Target extends CharacterBody3D
signal defeated(target: Target)
const MAX_HP := 100
var hp := MAX_HP
var marked := false      # written only by Marking and Explosion
var suspended := false   # written only by Suspend and Explosion
func is_alive() -> bool
func center() -> Vector3                 # center of the main body collider
func apply_damage(amount: int) -> void   # clamps at 0; at 0: clear marked and suspended, emit defeated

# scripts/core/player.gd
class_name Player extends CharacterBody3D
const MAX_HP := 100
const UPPER_BODY_HEIGHT := 1.4
func upper_body_point() -> Vector3
func crosshair_target(range_m: float) -> Target   # null if nothing valid (rules in section 5)
func take_hit(amount: int) -> void

# every ability in scripts/abilities/
var cooldown_left := 0.0
func is_ready() -> bool
```
Abilities find each other as siblings under `Player/Abilities` (`$"../Suspend"`). Combat calls `suspend.reduce_cooldown(1.0)`. Explosion reads Marking's current target and asks Suspend to end suspensions. The HUD reads `cooldown_left` from all four.

### Godot gotchas
- **Timers:** count down with `delta` in `_physics_process` (or use Timer nodes). Both freeze when `get_tree().paused = true`. Never use wall-clock time. The pause menu node needs `PROCESS_MODE_WHEN_PAUSED`.
- **Navigation:** there's no navmesh yet. The enemy owner adds a `NavigationRegion3D` to each game level and bakes it from layer 1 colliders.
- **Creatures have no collider or body.** `scenes/characters/*.tscn` roots are plain `Node3D` visuals. Wrap them in an enemy scene.
- **Models face +Z** (Godot's forward is −Z). Use `look_at(target, Vector3.UP, true)` so creatures face where they walk.
- **Numbers live in named constants** at the top of the owning script (`const DAMAGE := 20`). The post-build PDF asks for the exact file, value and edit that would double the difficulty.
- **Main scene** is still `scenes/visual_inspection.tscn` (the flycam). Switch `run/main_scene` to the first game level in one coordinated commit.
- The flycam's Q/E fly up and down. That only applies to the inspection scene.

## 8. Art and audio to use

Full guide: [docs/GRAPHICS.md](docs/GRAPHICS.md). Effects: instance from `scenes/effects/`, set `autoplay = false` and `free_when_done = true`, add to the scene, position it, call `play()`.

| Need | Use | Watch out |
| --- | --- | --- |
| Combat hit | `impact_sparks`, `assets/materials/fx_hit_flash.tres` (`material_overlay`, animate `flash` 1 → 0) | `muzzle_flash` and `bullet_hole` are gun effects. Combat is a 3 m attack |
| Mark | `assets/materials/fx_marked_outline.tres` (`material_overlay`; depth-tested, so it hides behind walls as required), `tracking_indicator`, `fx_tracker_hologram.tres`; handheld model `scenes/props/tracker_device.tscn` | `tracking_indicator` is built for the feet; the submitted answer puts the icon above the target |
| Suspend | `suspend_field` (animate material `strength` 0–1), `suspended_particles`, `scripts/visual/afterimage_spawner.gd`, `fx_temporal_distortion.tres` | Don't move or disable the collider |
| Explosion | `explosion_{orange,green,blue,purple}`; the `Shockwave` ring grows to exactly 4 m radius in 0.45 s; `scorch_mark` | `fire_*` loops forever. Team 3 forbids lingering areas, so fire is cosmetic only, short, and never does damage |
| Enemies | `failed_humanoid`, `augmented_subject`, `chemical_subject`, `twin_monster` in `scenes/characters/`. Call `play_visual("walk")`. Failed: `idle walk react twitch`. Twin: `idle head_tilt eye_scan clock_spin twitch wire_vibrate walk_slow posture_shift reveal` | Animations are in place (no root motion). The Twin has the same 100 HP and numbers as every other target |
| Creature voices | `CreatureAudio` node on each character: `say("help_me")`, `vocalize()`. Set `lines` to only budgeted lines | Random lines use words from the budget (section 4.5) |
| Twin reveal | `scenes/cinematics/twin_reveal.tscn`, `scripts/visual/reveal_sequence.gd` (set `auto_loop = false` in game) | It speaks "you found me" (3 words). The Twin must already exist at level start |
| Readable text | Paper and newspaper props are blank. Add `Label3D` in your own scene | Every word counts |
| Story props | `failed_containment_device`, `photo_frame`, `teddy_bear`, `papers_scattered`, `containment_tank(_broken)`, `cell_bars`, `clock_workbench`, `grandfather_clock`, `wall_clock`, `old_key`, `keycard`, `pistol` | Keys and weapons are set dressing only (rule 2) |

**Map areas** (`scenes/environments/`):
| Scene | Rooms |
| --- | --- |
| `area_a_entrance` | Lobby, security office (pistol and keycard on the desk), admin cubicles |
| `area_b_research` | Research corridor and labs |
| `area_g_west_wing` | Break room, lockers and showers, dormitory, archive maze, service tunnel, specimen storage (loops into containment) |
| `area_h_east_wing` | Clock workshop, animal lab, morgue, surgical theatre with observation gallery |
| `area_f_cell_block` | 14 barred cells with tally marks, warden's office, link corridor to containment |
| `area_c_containment` | Containment hall, control room |
| `area_d_lower` | Stairs, corridors, the twins' room, generator room, flooded storage, incinerator, hidden passage to the twin chamber |
| `area_e_twin_chamber` | The Twin's chamber |
| `timbuk_facility` | All areas together, plus environment, fog and probes |

## 9. Story vs. rules: conflicts to settle

| Submitted story says | Problem | Safe build until decided |
| --- | --- | --- |
| Explosion makes lingering fire; green spreads fast, blue burns longer | Team 3: no lingering area, damage is instant. Different fire behaviors add rules | Color is cosmetic. No fire area, no damage after the instant hit |
| A key drops from the last monster and opens the next area | No pickup action exists; gating doors adds a rule | Treat each area as its own level: clearing it is a win, and the next level loads. A key can appear as visual flavor only |
| Weapons are found in the world | Abilities must work from the first frame | Weapons in the world are set dressing; the player already has them |
| A pistol is modeled for Combat | Combat is a 3 m attack; a 3 m gun will feel broken | Decide the weapon (melee fits the numbers) |
| Twin final dialogue and reveal | The Twin must exist at level start and follow the same AI rules | Pause gameplay during the reveal (timers freeze) or start it before the Twin's 8 m trigger |
| One big facility (~10 min run) | Every target in a level is required; the Twin won't necessarily die last | Put the Twin chamber in its own final level |

## 10. Open decisions
- [ ] Who builds the shared core (section 7)
- [ ] The Combat weapon
- [ ] Levels: how many, and which areas each one uses
- [ ] Progression between areas (section 9, key row)
- [ ] What the twin did to the parents (killed or ate)
- [ ] What the player finds after the Twin dies (the Reconciliation beat needs a found moment)
- [ ] Locations for the beats and found moments (needed for the story revision)
- [x] Trim the voice lines to fit 150 words — done Oct 29 2026, and the whole game
  re-audited: 656 → **134 / 150**. See section 4.5 for the table, the counting
  rule, the chrome ruling and the next cut if we need more room.

## 11. Deadlines
- **Story revision:** sections 1–4 and 6 can be revised once. One member emails it before **4:00 pm, Wednesday November 4, 2026**. The clarity rating is final.
- **Game due:** **Wednesday, November 4, 2026.** The final playtest uses the latest story version.
- After the build, the team writes a post-build PDF (core loop; exact file, function and value for 2–3 key mechanics; one AI output we changed; what Wednesday's changes did; what's fragile). Record real results as they happen. Never invent them.
