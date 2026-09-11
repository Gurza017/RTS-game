# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

3D RTS prototype on **Godot 4.6** (GDScript, **GL Compatibility** renderer) in the spirit of Total War / Cossacks: economy, buildings, resource gathering, and unit combat. README and most code comments are in Russian.

## Exporting (this is where "works in the editor" stops meaning anything)

**Never enumerate a directory to find assets.** `DirAccess.list_dir_begin()`/`get_next()` returns *different names* in an exported build than in the editor, and that difference silently downgraded every archer in the .exe to a procedural placeholder while spearmen were fine. Measured inside a real export (`qa_build/Test.tscn` run as the main scene of an exported binary):

- editor listing: `Archer_Idle.png`, `Archer_Idle.png.import`, …
- export listing: `Archer_Idle.png.import` **only** — no bare `.png`

so `filename.ends_with(".png")` matched nothing, `found_any` stayed false, and `Archer._setup_visual` fell through GLB → single PNG → `_add_bow_procedural()`. Archer was the *only* unit built by `SpriteSheetParser.build_animated_sprite` (the scanner); Spearman/Worker/Warrior/Monk list their sheets by name via `build_sprite_from_map`, which is why only archers broke. `build_animated_sprite` now strips a trailing `.import`/`.remap` before the extension test, but it stays a **fallback only** — a new unit must name its sheets explicitly (see `Archer.SHEETS_COLOR` / `SHEETS_PLAIN`).

**Probe for "does this folder have a sprite set" with `SpriteSheetParser.folder_has(dir, file)`, never `DirAccess.open(dir) != null`.** The old probe asked whether a *directory* exists in the pack, which depends on packing details invisible from the game; `folder_has` asks `ResourceLoader.exists()` about a concrete file, which goes through the same remap table as `load()` and answers identically in editor and export. It caches — it runs on every unit spawn, and hiring a squad is 20 spawns in one frame.

**The PCK filesystem is case-sensitive on every OS, including Windows.** `UIAssets.DIR` said `menu UI` while the folder is `menu ui`; the editor on Windows didn't care, the export returned false from `ResourceLoader.exists()`, `_load_image` returned null, and the game shipped without cursors or HP bars. Nothing warns about this before the build. `qa_build/Test.tscn` checks the whole asset surface, and there are two throwaway audit scripts worth re-running after any asset move: one comparing every `res://` string literal against the real filename, one expanding the `%s` templates in `game_settings.gd` across all colours/units/buildings.

- **`qa_build/Test.tscn`** — asset presence + real sheet assembly, per faction colour. Run it **twice**: `godot --headless --path . res://qa_build/Test.tscn` for the baseline, then point `run/main_scene` at it, export a *debug* build and run that binary. Release **and** debug templates refuse a scene path on the command line (`disable_path_overrides`), so temporarily repointing `run/main_scene` is the only way to run anything inside a build — restore it immediately afterwards.
- **`qa_build/Leak.tscn`** — three waves of 300 spawned-and-killed units, comparing `Performance.OBJECT_COUNT`/`OBJECT_NODE_COUNT`/orphans between waves. Current result: **+0 objects, +0 nodes, 0 orphans** across 900 units. Do not chase the engine's "ObjectDB instances leaked at exit" line — it fires on a healthy project too (the static `SpriteSheetParser`/`UIAssets` caches live to process exit by design) and cannot distinguish a cache from a leak; the wave-to-wave drift can.
- **`export_presets.cfg`**: `exclude_filter` drops `_trash/*`, `qa_*/*`, `addon.py`, `*.md` — verified by loading the built `.pck` into a throwaway empty project and walking it with `DirAccess`: **1640 files → 1060**, `_trash` 123 → 0, `qa_*` 250 → 0, 28.2 MB → 22.6 MB. `include_filter` was `*.png, *.png.import` and is now empty: it was a **no-op**, not a size problem — Godot treats anything with an `.import` as an imported resource and ships the `.ctex`, so the raw PNG count in the pack is **0 either way**. The `.import` sidecars ship regardless of any filter (430 of them), which is precisely why the export directory listing shows `X.png.import` and never `X.png`. Note `binary_format/embed_pck=false` produces `.exe` + `.pck` that testers must keep together; flip it to `true` for a single-file alpha drop.
- **To inspect what actually shipped**, don't string-scan the `.pck` (that hits resource *contents* and lies — it "found" 276 raw PNGs that do not exist as entries). Make an empty project, `ProjectSettings.load_resource_pack(path, false)`, then walk `res://` with `DirAccess`.

## Running / validating

- Open `project.godot` in **Godot .NET 4.7.1 (mono)** — the project contains C# (`csharp/ArmyCore.cs`) and the Standard build cannot load it at all. Press F5. Build the assembly with `dotnet build "Ten Thousand Spearmen.csproj"` (needs .NET SDK 8+; 10.0.400 here). Main scene is `scenes/MainMenu.tscn` → button leads to `scenes/Main.tscn`.
- **Headless validation is available**: the Godot binary lives at `E:\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64_console.exe` (the 4.6.3 standard build in `E:\Games\` predates the C# port and no longer opens the project). After any script change run:
  - `<godot> --headless --import` — recompiles all scripts; parse/compile errors print to stdout. A parse error in any script in a dependency chain of an autoload (GameManager, ResourceManager) breaks the whole game with a gray screen.
  - `<godot> --headless --path . res://scenes/Main.tscn --quit-after 300` — smoke-runs the game scene.
- **Heavy benchmarks run headless and silent.** `qa_mass_perf` (the 810/3000/5000/6000 stress test) never opens a window — it checks `DisplayServer.get_name() == "headless"` and skips every window/vsync/draw-call call — and it prints **nothing at all during the run**: every line is buffered and emitted as one table by a single `print()` at the end. That is deliberate: streaming output into the VS Code console buffer freezes the editor UI, and a windowed 5000-man run pins the GPU. Arguments: `-- --count=N`, `-- --steps=a,b,c`, `-- --verbose` (adds the branch breakdown). Exit code is 0/1 on PASS/FAIL against the 16.6 ms physics budget. **Any new mass harness must follow the same contract**; per-unit `print()` in game code does not exist and must not be added (the only `push_error`/`push_warning` sites are in `Building.gd`, `HUD.gd`, `unit_stats_config.gd`, none in a hot path). The windowed render measurement stays in `qa_march_perf` at 810 models.
- GDScript 4.6 gotcha that has repeatedly broken this project: `var x := arr[i]` or `dict[key]` **cannot infer type** (Variant) — always write `var x: String = arr[i]` when indexing untyped arrays/dictionaries.
- No test suite / linter. Temporary test scenes (root Node + script that instantiates Main.tscn and drives it) work well for smoke tests — delete them afterwards.
- **`qa_shot9`, `qa_shot10` and `qa_shotvis` are the harnesses that must NOT run headless** (`qa_shotvis` shoots the world rather than the HUD — see "Highlight, stumps and the rally flag") — they save real screenshots of the HUD (`get_viewport().get_texture().get_image().save_png()`), and headless renders nothing. `qa_shot9` shoots a worker-crew selection: `<godot> --path . res://qa_shot9/Test.tscn -- --out=<abs path>.png --size=1280x720`. `qa_shot10` shoots the two-level selection and writes **two** files, `<out>_lvl1.png` and `<out>_lvl2.png`: `<godot> --path . res://qa_shot10/Test.tscn -- --out=<abs path prefix> --size=1280x720`. Use them whenever a layout change needs to be judged by eye rather than by numbers; `qa_ui9` and `qa_sel2` cover the numbers.
- **`qa_sel2` is the harness for the two-level selection pass** (33 checks): levels 1/2 and the transitions between them, the −50 % panel scale and its real geometry, `Z`/⏸ pausing game **and** audio, ruin→construction-site rebuild, the idle widget selecting all, the smithy's `#32CD32` check and research-queue row, and the star centroid/size. Run headless like any other.

## Scenes & assets

- Only two hand-written `.tscn`: `MainMenu.tscn` (Control + MainMenu.gd) and `Main.tscn` (empty Node3D + Main.gd). Everything else is spawned imperatively from `Main.gd`.
- Visuals: units are **billboard sprites** (PNG spritesheets under `assets/factions/<name>/units/`, parsed by `SpriteSheetParser`); buildings are procedural meshes; the castle loads `assets/models/castle.glb`. Unit GLB models (worker/spearman/archer .glb) exist but are **deliberately unused** — in GL Compatibility their materials render black. Every visual builder has a procedural-primitive fallback chain (`_build_visual()` / `_setup_visual()` patterns) so missing assets never crash.
- Decorative environment (pond, bushes, clouds, rubber duck) uses billboard quads with textures from `assets/environment/`.

## Architecture

**Two autoload singletons** (declared in `project.godot`):
- `ResourceManager` — per-faction resource bank (`resources[faction][type]`, 5 types: wood/gold/stone/food/water); emits `resources_changed(faction)`. HUD listens. `reset_resources()` sets starting amounts.
- `GameManager` — holds `main` (the `Main` node), dropoff registry, **per-faction upgrades** (`upgrades[faction][stat]`, use `apply_upgrade(faction, stat, val)` / `get_upgrade(faction, stat)`), the `try_build_*` placement flows, and selection-change bridging to `Main`/HUD. It also owns the three shared subsystems (`unit_grid`, `far_units`, `sel_decals`) and **runs the whole unit tick** (see below).

**Units have no physics body and no per-node tick.**
- `Unit` **extends `Node3D`**, not `CharacterBody3D` (migrated Aug 5 2026). Measured in `qa_node_cost`: the mere existence of a body in `PhysicsServer3D` cost **5.7 µs/unit/frame** — 900 bodies with an *empty* tick were 5.72 ms/frame vs 0.66 ms as `Node3D`, and the logic inside made no difference (+0.03 ms). Nothing was paying for it: `collision_mask` is 0 everywhere, `move_and_slide`/`move_and_collide` are never called, and the one selection raycast that used the body now takes candidates from `SpatialGrid`. `velocity` is a plain declared field on `Unit`. `Building`/`ResourceNode` are still `StaticBody3D` and were not touched. `PHYSICS_3D_ACTIVE_OBJECTS` reads **0** in game.
- `Unit` does **not** override `_physics_process` — the engine never calls it. The entry point is `Unit.tick_physics(delta)`, called directly from `GameManager._physics_process` over the flat array `GameManager._live_units` (`register_unit()` in `Unit._ready`, `unregister_unit()` in `_exit_tree`). A flat array, not `get_tree().get_nodes_in_group("all_units")` — the group copies its internal `Array` on every access and this loop runs 60×/s. The group still exists and is fine for **rare** lookups.
- `set_physics_process(false)` keeps its old meaning ("turn this unit's tick off": `Castle.absorb_unit`/`release_unit`, `qa_guard`, `qa_formation`) — `GameManager` checks `is_physics_processing()` before calling.

**Class hierarchy** (each script declares `class_name`):
- `Unit (Node3D)` → `Worker`, `Spearman`, `Archer`, `Warrior`. Base holds the FSM (IDLE/MOVING/ATTACKING/GATHERING/RETURNING/DEAD/BUILDING — `BUILDING` was appended last on purpose so the other numbers didn't shift), health, combat, movement, walk-bob animation, stances. Damage/defense upgrades are read live per faction (`_upgrade_damage_bonus()`, overridden by Archer to add `arrow_dmg`).
- `Building (StaticBody3D)` → `Castle` (hub: trains workers/warriors, dropoff, passive gold), `Barracks` (spearmen ×20, archers ×10), `Smithy` (research), `Mine` (passive gold), `TownCenter` (legacy, mostly unused). Base holds production queue with squad spawning (`queue_unit` snapshots squad size/cols/spacing) and a `_dead` guard so `died` fires once.
- `ResourceNode (StaticBody3D)` — 5 resource types; `extract()` shrinks visual, frees when depleted.
- Helpers: `RTSCamera` (pan/zoom/orbit), `SelectionManager` (click/box/hotkey-group selection, line-formation orders via RMB drag), `FormationPreview`, `HUD` (all UI incl. pause/victory/defeat), `Arrow` (visual projectile), `SpriteSheetParser`, `Constants`.

**Game flow** (`Main.gd`): `MainMenu` → `Main._ready()` builds environment/terrain/camera/HUD → `start_game()` spawns resources + enemy base. Player places the Castle via HUD button (placement ghost, refund on cancel) → 5 starting workers auto-gather. Enemy AI: 5-minute peaceful phase (patrols, trains nothing), then trains squads and attacks nearest player target; reinforcement waves every 35 s (max 3). Victory/defeat checked every 3 s.

**HUD / input / camera specifics:**
- **Alt toggles all HP bars.** Caught in `Main._input` (not `_unhandled_input` — the HUD would swallow it), `echo` filtered. State lives in `GameManager.hp_bars_forced`; `toggle_hp_bars()` / `set_hp_bars_forced()` walk `all_units` + `all_buildings` calling `refresh_hp_bar()`. The flag is **absolute**: with it down, no bar node is created at all, not even on damage or spawn. New entities read it in `_ready()`.
- **`Z` and the ⏸ icon both pause the game *and* the audio**, through the single entry point `HUD.toggle_pause()` → `set_paused()` → `get_tree().paused` + `AudioManager.set_paused()`. Two things to know. (1) `AudioManager` runs in `PROCESS_MODE_ALWAYS` (the settings sliders have to work while paused), so `get_tree().paused` never touched it — music and forest ambience kept playing over a frozen picture. It pauses via `stream_paused` on `_music`, `_ambience` and every pool voice, **not** `stop()` (loses the position — the forest would restart from second zero) and **not** a bus mute (the streams would keep running silently and resume mid-phrase); its `_process` early-returns while paused so the music-swell timer can't elapse unheard. (2) `Z` is caught in `HUD._unhandled_input`, **not** `Main._input`: `Main` is `PROCESS_MODE_INHERIT`, so once the tree is paused input never reaches it and there would be no way back out. `echo` is filtered, and `Z` is ignored while an overlay (pause menu / victory / defeat) is open. The Escape settings menu deliberately does **not** mute audio — you cannot judge a volume slider in silence.
- **RMB on a ruin with workers selected rebuilds it** (`SelectionManager._try_rebuild_ruin` → `GameManager.rebuild_ruin`): the ruin is replaced by a `ConstructionSite` for the same `building_id` in the same frame, at the same position, and the whole selected crew is sent to it with `command_build`. No placement ghost — the site is already chosen. Cost is the **normal** building cost, spent immediately (a discounted "repair" would make it profitable to let your own buildings fall); if it is unaffordable `rebuild_ruin` returns null, `_try_rebuild_ruin` returns false and the click degrades into an ordinary move order rather than being silently swallowed. Ruins are still **not** buildings: no groups, no health, no left-click selection. They only gained a `StaticBody3D` + box collider on **`Constants.LAYER_RUINS` (16)**, a layer that appears **only** in the right-click mask — putting them on `LAYER_BUILDINGS` would have been a trap, because `_resolve_node` returns null for them and a null resolve in `_pick_at` means "that's the ground, stop scanning", so a ruin would have made everything behind it unclickable. `_resolve_node` recognises them by the `"ruins"` group, and `spawn_ruin()` stores `ruin_building_id` / `ruin_faction` / `ruin_size` as metadata.
- **The mouse is NOT confined to the window** — do not re-add `Input.MOUSE_MODE_CONFINED`. `Main._confine_mouse()` used to set it on window focus to stop edge-scroll from firing while the cursor sat on a second monitor, but it also locked the cursor away from the Windows titlebar, so minimize/maximize/close were unreachable and the game felt hung. Removed Aug 2026. The original edge-scroll bug is now handled at the source in `RTSCamera._process`, which requires `_window_focused()` (`DisplayServer.window_is_focused()`, always true in headless) on top of the existing "cursor is not over a Control" check.
- **The game window opens Maximized** (`display/window/size/mode=2` in `project.godot`) — a normal resizable window with its titlebar, *not* mode 4 (Exclusive Fullscreen). F11/Alt+Enter still toggle exclusive fullscreen at runtime (`Main._toggle_fullscreen`).
- **Camera:** edge scroll has its own multiplier `RTSCamera.edge_pan_boost` (1.35) separate from `pan_speed`; MMB drag passes `Vector2(-d.x, -d.y)` — `_pan_by` negates `step.y` internally, so a non-negated `d.y` produced the inverted-vertical bug.
- **Camera pan bounds are zoom- and aspect-dependent, not a fixed number** (`RTSCamera._clamp_focus()`/`_visible_ground_half()`, fixed Aug 2026). The camera is orthographic with a fixed 45° pitch; the old code clamped the pivot's XZ focus to a flat `map_half − 12m` margin that ignored both the current zoom (`Camera3D.size`) and the screen's aspect ratio. At max zoom-out on a normal 16:9 window the actual visible ground already exceeded that margin by ~60m, and on an ultra-wide monitor by much more — panning toward any edge showed black void past the terrain. The visible ground half-extent is **not symmetric**: half-width = `size * aspect / 2` (ordinary KEEP_HEIGHT scaling), but half-**depth** = `size / (2 * sin(pitch))` — the tilt stretches how much ground-depth a given vertical frame-size covers (at 45° pitch that's ×1.41 over the naive `size/2`). `set_bounds(half_x, half_z)` now stores the *raw* map half-extent (`_map_half`); the actual clamp is recomputed every pan/zoom from `max(_height, _target_height)` (use the not-yet-settled, larger value during a zoom-out animation, so panning mid-zoom can't outrun where the camera will end up) and the live viewport aspect via `get_viewport().get_visible_rect().size`. `Main._setup_camera()` now calls `set_bounds(MAP_HALF_X - MAP_EDGE_MARGIN, MAP_HALF_Z - MAP_EDGE_MARGIN)` — the old pre-shrunk `CAM_BOUND_X/Z` constants are gone. On top of that, `RTSCamera.EDGE_OVERSCROLL` (26 m) lets the focus deliberately travel *past* the map edge, so black void **is** visible along the border at the extremes — that is intended, not a regression: clamping exactly at the terrain edge pinned a corner castle/unit to the very rim of the screen (partly under the HUD panels) and made it unselectable. With the overscroll the map corner crosses screen centre and stays comfortably in frame. Do not "fix" the black border by removing it.
- **The match opens FULLY ZOOMED IN** (`Main.start_game()` → `jump_to(PLAYER_BASE_ANCHOR, _camera.min_height)`, owner's call Aug 8 2026 — this reverses the previous "opens zoomed out" state). The old objection to `min_height` was that it dropped the player nose-first into the grass with no sense of the surrounding map; **fog of war is what makes it acceptable now** — zoomed out you would see grey pelt and nothing else anyway, while the castle pad is pre-revealed (`_reveal_start_area()`) so the opening choice is never made blind.
- **The first castle cannot be cancelled.** `Main._cancel_or_keep_placing()` (bound to RMB and Escape during placement) no-ops while `_phase == PLACING_CASTLE and not _castle_placed`. Without it, an accidental RMB in the opening seconds dismissed the placement ghost permanently and left the player on an empty map with no way back into build mode and no castle to produce workers — an unrecoverable dead end. Every other placement (including later castles) still cancels and refunds through `_refund_and_cancel()` as before.
- **Selection is TWO-LEVEL** (owner's call, Aug 7 2026 — this reverses the brief "the over-bar banner is GONE" state of the previous pass). `show_selection()` only records the new selection and rebuilds the group bar; **all panel drawing lives in `HUD._refresh_panel()`**, which reads `_sel_units` + `_expanded_type` and picks a level:
  - **Level 1 — two or more troop *types* selected** (`selection_type_count() >= GROUP_BAR_MIN_TYPES`): the bottom panel is **hidden entirely** and the only thing on screen is the compact group bar (`_build_overbar`, node `OverBar`) — one slot per type, icon plus a badge with the **squad** count (4 spearman squads → "4"). This is what fixed the original complaint: the banner used to *duplicate* the detail panel; now it *replaces* it, so nothing is shown twice.
  - **Level 2 — a group slot was clicked** (`_on_type_filter_pressed` → `_expanded_type` → `_refresh_panel`): the panel comes back showing **only that type** (`_build_type_detail`) — type icon in the portrait, total men in `info_label` ("Отряд лучников: 21 бойцов • отрядов: 3"), one card per squad in `_squad_strip`, and stance/guard buttons built from that type's members. Clicking the same slot again toggles back to level 1.
  - **One type selected** → group bar hidden, ordinary detail panel as before.
  - `_on_type_filter_pressed` calls `_refresh_panel()` and deliberately **does not** rebuild the group bar — `_rebuild_overbar()` frees all its children, and that would free the very button under the player's finger (the same bug that moved the idle widget out years-equivalent ago).
- **Over-bar / group bar** (`HUD._build_overbar`, called from `show_hud()`) is the single strip above the command panel. It holds one summary slot per selected unit type — **the idle-workers slot is not in it** (moved out Aug 2026, see below). `HUD.type_slots()` reports the full child count of the bar; `_rebuild_overbar()` no-ops unless the selected squad set changed. Neither its width nor its height is a number: it grows right from the left edge and **up** from its bottom edge (`grow_vertical = GROW_DIRECTION_BEGIN`), and `_position_group_bar()` sets that bottom edge — above the panel when the panel is visible, down at the screen edge when it is not (level 1 has no panel, and a bar floating over empty space looked broken).
- **Per-squad cards** (`_squad_card`) carry three things: the alive count as a corner badge, the red strength bar under the icon, and — new — the **veterancy star** as a `Label` in the top-left corner (count and colour from `_UCfg.veteran_star_tier`, so level 4 is one *silver* star, not four bronze). Top-left is deliberate: the count badge owns the bottom-right.
- **Idle-workers indicator is a standalone widget** (`HUD._build_idle_widget`, node name `IdleWorkersWidget`), built once in `show_hud()`, positioned top-left directly under the resource bar — **not** rebuilt on every selection change like the old over-bar slot was (that was the actual bug: `_rebuild_overbar()` frees all its children on every selection change, so the idle button the player just clicked could be freed mid-click). `_idle_btn`/`_idle_count_label` now live for the whole match; `_apply_idle_state()`/`_update_idle_counter()` are unaffected by selection.
- **One click on the idle widget selects ALL idle workers** (`_select_idle_workers`) and focuses the camera on their **centroid**, not on the first one. The old cycle-one-at-a-time behaviour (`_focus_next_idle_worker`) is still in the file but no longer wired to the button — handing work to six idlers cost six clicks and six orders. The count is a bare `Label` **directly inside the Button** with a black outline; it used to sit in its own dark `PanelContainer`, which is the "black square under the number" the owner complained about — the outline does the same readability job without drawing geometry. A `Button` is not a `PanelContainer`, so the label's `PRESET_FULL_RECT` + right/bottom alignment actually corners it.
- **SUPERSEDED TWICE — read "Resource bar: the tool glyph is per resource (Aug 14 2026)" instead.** The two reversals below are the history of this line; the current rule is one tool glyph per resource and no "total" section at all.
- **The tool glyph and worker counter live in ONE section — the rightmost (Food)** (`RES_WORKER_SECTION`, owner's call Aug 8 2026). They used to sit in every section (axe on Wood, knife on Food, `⛏N` on all four); the width for them was reserved in all four and stood empty in three, which is the "empty gaps" the owner asked to close. `RES_CARD_SIZE` no longer includes that tail at all and `RES_CARD_SIZE_WORKERS` (Food only) adds it back. **The counter shows the player's TOTAL workers, not "workers on food"** — food is produced by Houses and never gathered, so a per-resource count there would be permanently zero and the moved icon would never light up, i.e. the move would not actually deliver what was asked.
- **Resource bar is one line per section** (icon + white amount + green income, no per-resource worker-gather badge any more — that duplicated the idle counter's "worker icon + number" look and got removed with it). Any icon put in a `Container` (not a plain `Control`) **must** set `TextureRect.expand_mode = EXPAND_IGNORE_SIZE`, or the control reports the texture's *native* pixel size as its minimum size and blows out the container regardless of `custom_minimum_size` — this inflated the resource bar from ~38px to 130px tall when the row moved from a plain `Control` wrapper (which doesn't propagate children's minimum size) to a real `HBoxContainer`.
- **`Label.clip_text = true` zeroes the label's own minimum size — never use it on a Label sitting directly in a `BoxContainer` without an explicit `custom_minimum_size`.** A non-expanding child gets exactly its minimum, so the label collapses to **1 px** and the text vanishes while `text` still reads correctly — the resource amounts/income rendered as empty sections this way, and `_fix_label()` (which sets `clip_text`) collapsed the bottom panel's info line to 1 px *tall*, leaving the wide dark gap between portrait and buttons. Use a fixed `custom_minimum_size` instead: the resource numbers use `RES_AMOUNT_W`/`RES_INCOME_W` (which also keeps sections from jittering as values grow — the original reason `clip_text` was there), and `_fix_label()` now derives a minimum height from the label's actual `font_size`. Symptom to recognise: text present in the node, rect 1 px on one axis.
- **"≡ Меню" lives in the top-right widget** (pause/timer/FPS/menu, one dark block), not in the resource bar — it used to sit at the end of the resource bar's `hbox` in a red/brown style that visually didn't match anything and stretched the resource panel's background far past its 4 cards.
- **Bottom panel's hire-queue and build-button columns (`_queue_box`, `button_container`) collapse to 0 width and hide when empty** (`HUD._sync_panel_grid_widths()`, called after `show_selection()` populates buttons and after every `_rebuild_queue()`). Both columns still use a **fixed** width while non-empty (`QUEUE_W`, `BTN_COLS * BTN_SIZE + …`) — that part is deliberate and must stay (see next bullet) — only the *empty* state changed, so a selection that trains/builds nothing (a lone Spearman, an enemy unit) no longer drags a wide reserved-but-blank panel behind it.
- **Clicking a summary slot expands that group** into per-squad cards in `HUD._squad_strip` (inside the bottom panel), each with a permanent red bar from `_squad_strength(sid)` = summed HP / (full squad size × max HP), so both losses and wounds shorten it. Clicking a card narrows the selection to that one squad. Selection is untouched by expanding.
- **HUD scale, two passes.** First pass (resource bar −40 % wide but taller, top-right −30 %) still stands. The bottom panel then got a **second** pass, −50 % again on top of the first: `PANEL_H` 72→40, `COL_H` 60→32, `PORTRAIT_W` 54→30, `INFO_W` 152→110, `BTN_SIZE` 44→22, `BTN_GAP` 4→3, `BTN_ICON_PAD` 5→3, `QUEUE_ORDER_ICON` 17→10, `FILTER_SLOT` 52→34. Geometry halved, **fonts only 11→10 / 10→9** — half of 11 px is 5 px, i.e. unreadable on any monitor. Remember the whole HUD is additionally multiplied by the `canvas_items` stretch: with a 720-tall base viewport a 1386-tall monitor draws every one of these numbers ×1.93, which is why the panels read as "gigantic" on the owner's screen while measuring modestly in canvas units. `SQUAD_CARD` (32) was **not** halved — it is the content of level 2 and has to hold a count, a bar and a star. Measure with `qa_ui9` (both resolutions) and `qa_sel2` (the −50 % itself).
- **`PANEL_TOP` is a `var`, not a `const`, and the panel's height is computed from its content.** At 40 px a fixed height stopped working: eight smithy slots in a `BTN_COLS`-wide grid wrap to a **second row**, squad cards are taller than buttons by the bar, and the production line adds one more. `_sync_panel_height()` zeroes the panel's own `custom_minimum_size` (or it would measure its previous self and never shrink), reads `get_combined_minimum_size().y`, clamps it to `PANEL_H` and writes back both the minimum and `PANEL_TOP` / the offsets, then re-places the group bar. It is called from `_refresh_panel()`, from `_rebuild_squad_strip`'s caller, and — only on a **visibility change** — from `_process`; never per frame, or the panel would breathe 60×/s. Everything that hangs above the panel (placement hint, garrison strip, stat panel, hover card) reads `PANEL_TOP` live and needs no change.
- **The production line hides itself when empty** (`_set_progress_text()`): a `BoxContainer` skips invisible children entirely, but a *visible* `Label` with empty text still claims its minimum height — a sixth of a 40 px panel reserved for nothing. Always set that label through the helper.
- **Anything inside a `PanelContainer` gets stretched to fill it — anchors and offsets on that child are ignored.** The portrait count badge and the veterancy stars are children of the portrait's `PanelContainer`, so `PRESET_BOTTOM_RIGHT` on them did nothing and the only reason the number looked cornered was text alignment inside a full-size rect. They now sit in a plain `Control` (`PortraitBadges`) that fills the panel and imposes nothing on *its* children, so anchors work again.
- **`_fix_label()` derives line height from the font, not from `font_size + 4`.** At `font_size = 11` the old estimate gave 15 px per line while the font needs ~16, so a two-line label had room for one and silently ellipsised the rest ("Артель: 5 рабочих —..."). Symptom to recognise: the node's `text` is complete, the screen shows one line and a `…`.
- **Command-button icons use `STRETCH_KEEP_ASPECT_CENTERED`, not `STRETCH_SCALE`** (`_stretched_icon`). Order buttons are square and building art is tall, so plain scaling squashed towers/smithy/houses into "stumps". `EXPAND_IGNORE_SIZE` must stay alongside it — without it the `TextureRect` imposes the file's native pixel size on the layout. Padding comes from `BTN_ICON_PAD`.
- **Resource icons are cropped to their opaque bounding box** (`HUD._trimmed_icon` → `AtlasTexture` over `Image.get_used_rect()`). `Woods.png`/`Meat.png` are real HUD icons whose art fills the canvas; `Rock2.png`/`Gold_Resource.png` come from world sprites and sit in a large transparent field, so aspect-correct fitting of the *whole canvas* drew them as dots next to the other two. Cropping fixes it at the source and needs no per-file fudge factors — a new icon adapts by itself.
- **Resource-bar corners are rounded on all four sides** (`_corners(style, 6)`), matching the top-right widget. The bar stands 8 px away from the screen edge, so square top corners were visible and looked unfinished next to the right panel.
- **The top-right widget has no fixed width.** It hugs its content and grows leftwards (`grow_horizontal = GROW_DIRECTION_BEGIN`, no `offset_left`); the old `TOP_RIGHT_W` constant was wider than pause+timer+FPS+menu and the difference showed as an empty black tail. "≡ Меню" is the whole right section: its `normal` stylebox is fully transparent with **zero** border, so it reads as part of the panel rather than a button drawn inside a button; only `hover` paints anything.
- **`_queue_box`/`button_container` are fixed-width while non-empty on purpose** ("ЖЁСТКАЯ СЕТКА" in `HUD.gd`): the queue grid is sized for `QUEUE_ORDER_MAX` cells and the button grid for a full `BTN_COLS`-wide row regardless of how many are actually filled, so the panel doesn't resize on every single order queued/completed. Do not make these grids shrink-to-fit their *populated* cell count — only the empty↔non-empty transition (`_sync_panel_grid_widths`) is allowed to change their width.

**Cross-cutting conventions — match these when adding entities:**
- **Faction** is an int (`Constants.FACTION_PLAYER` / `FACTION_ENEMY`), set on the node *before* `add_child()`, read in `_ready()`.
- **Groups** drive lookups: `all_units`, `player_units`/`enemy_units`, `all_buildings`, `player_buildings`/`enemy_buildings`, `resource_nodes`. **Never in a per-frame path** — `get_nodes_in_group()` copies its array on every call. Hot paths use `GameManager._live_units` (the tick), `GameManager.unit_grid` (neighbours) and `GameManager.nodes_in_group_cached()` (per-frame cache, used for buildings).
- **Collision layers** per type (`Constants.LAYER_*`); **`collision_mask` is deliberately 0** everywhere — nothing collides; movement is direct kinematic integration into `global_position` on the XZ plane (no `move_and_slide`, no `look_at` — units track `_facing` and the node never rotates). `SelectionManager` raycasts use layers as picking masks for *buildings*; unit picking goes through the grid. Do not enable masks casually (README: disabled to stop ground-contact jitter) and do not give units a physics body again (see the 5.7 µs measurement above).
- **Allies never push each other — do not add it back.** There is no separation/avoidance/steering between friendly units: they overlap freely and walk straight through one another. A unit that reaches its target (`Unit.ARRIVE_RADIUS`) zeroes `velocity`, goes IDLE and sets `_settled`; nothing moves it afterwards except a *new order*. Every attempt at "smart" crowding (per-neighbour separation radii, yield corridors, `_reform_step` pulling units back to their slot, arrival grace periods) ended as mutually-cancelling forces that never converged — that was the "units jitter and freeze in a crowd" bug, and the whole machinery was deleted, not tuned. What legitimately still moves a unit: `_move_blocked`/`SpatialGrid.enemy_block` (the **enemy** line is impassable), `_apply_push` (melee wall-vs-wall shove, enemies only), trunk avoidance, `_phalanx_advance` (only with an enemy in sight), and `GameManager.squad_close_ranks()` — an event-driven, cooldown-limited re-issue of move orders, not a per-frame force. Covered by `qa_settle`.
- **Ground has relief** (`Main.TERRAIN_RELIEF`, three incommensurate sine harmonics, amplitude `RELIEF_AMP` 0.85 m) — always set Y through `GameManager.get_terrain_height(x, z)`, never hard-code 0. In the move commit path the height is **cached and only recomputed after 0.25 m of travel** (`Unit.TERRAIN_RECHECK_SQ`): the shortest harmonic has a ~13 m wavelength, so the error stays under a centimetre, and the naive version cost two cross-object calls plus three `sin()` per unit per frame.
- **Order of the step pipeline** (`Unit._move_blocked`, the only place `global_position` changes): water (`GameManager.water_active` gate → `is_water` → `slide_around_water`) → trunk (`trunk_block`, tangential slide, head-on case deflected by instance-id parity) → enemy line (`unit_grid.enemy_block`, skipped while `retreating`, sets `_enemy_contact`) → map clamp (inline `clampf` against `GameManager.map_lim_x/z`, **not** a call to `clamp_to_map` — that path is hot) → terrain height → commit. Each stage has a `mb_*` profile bucket.
- **Interfaces relied on elsewhere** (keep names): `set_selected(bool)`, `take_damage(amount, attacker)`, `is_dead()`, `display_name`, `current_health`/`max_health`, `faction`, `command_move/attack/gather`. `SelectionManager._resolve_node()` walks parents to find `Unit`/`Building`/`ResourceNode`; HUD builds buttons by `is`-checking concrete classes.
- Spending is immediate at queue/placement time via `ResourceManager.spend()`; placement cancel refunds via `Main._placing_refund`.

## Command priority: the player target lock (Aug 8 2026)

`Unit.target_lock` implements a three-tier order hierarchy. Read this before touching `_process_attack` or `command_attack`.

- **№1 — the lock.** `command_attack(target, forced, charge, lock = true)` is set **only** by the player's RMB (`SelectionManager._handle_right_click`) and by `_resume_attack` restoring that same order (`_atk_pending_lock`). It stores the **enemy squad id** (`_lock_squad`), not the model: when the victim dies, `_process_attack`'s retarget branch takes the next member of that same squad via `_lock_next_victim()` instead of `_find_nearest_enemy_in_range`. That scan is what used to scatter a squad across every nearby target. The lock is **never cleared inside `command_attack`** — only `command_move`, `begin_retreat`, and "the locked squad is wiped" release it (`release_target_lock()`); a blocker intercept calls `command_attack(blocker, false)` and must not cancel the player's order.
- **The biggest single source of "the squad splits up" was in `SelectionManager`, not in `Unit`.** The attack branch built the *whole* enemy list (`enemy_units + enemy_buildings`) and gave **each selected unit its own nearest target** out of it — clicking one squad issued N different orders. It now passes the one clicked target to everyone and lets `command_attack` → `GameManager.squad_pick_member` spread the squad across that squad's models.
- **№2 — a blocker in contact.** Under a lock the intercept radius is `minf(attack_range, LOCK_BLOCKER_RANGE) + INTERCEPT_MARGIN`, **not** `attack_range + INTERCEPT_MARGIN`. For an archer the latter is its full ~20 m bow range, so a squad ordered onto a distant target stopped halfway and shot whatever was nearest. `_enemy_contact` (set by `_move_blocked`) still triggers in the same frame, so real contact is never missed.
- **№3 — auto-aggro** runs only when there is no lock. `take_damage`'s ranged counter-charge branch is gated on `not target_lock`, and `GameManager.squad_counter_charge` skips locked members — otherwise one enemy archer poking the column rewrote `_atk_pending` and swapped the player's order for a stray skirmish. Contact retaliation (attacker within `attack_range`) still fires: that is priority №2.
- A player attack order also calls `GameManager.squad_clear_formation(sid)`. `squad_close_ranks` issues `command_move` to every member, which would release the lock and drag the squad onto stale slots mid-charge.
- **`PULL_UP_SPEED` (0.55) must stay 0.55 — it is not the archer-crawl bug.** The crawl is fixed by the lock bypassing `_should_pull_up` entirely (a locked unit approaches at full `_effective_speed()`). Raising the constant, or letting full speed apply beyond a band near `attack_range`, was tried and **broke retreat**: pull-up also runs on the *pursuer* (auto-aggro calls `command_attack(forced)` on an enemy past weapon range), and at 100 % the chaser matches the fleeing squad's speed, stays in contact the whole way and wipes it. Measured: `qa_disengage` B3 went 6/6 → 0/6, C1 4/4 → 0/4. The 0.55 encodes "you do not run somebody down on your own initiative".
- Covered by **`qa_target_lock`** (14 checks: no splitting, retarget within the locked squad, archer approach speed vs. the crawl, volley entry, harassment ignored, lock released by a move order / by wiping the squad, auto-aggro resuming afterwards).

## UI focus, squad grid, reformation (Aug 8 2026, second pass)

- **`drag_start` is recorded in `SelectionManager._input()`, NOT in `_unhandled_input()` — and that is the whole reason the forge panel used to close on every click inside it.** A press on a Button (forge tab, tech node) or on a panel background is consumed by the GUI, so `_unhandled_input` never sees it and `drag_start` kept the position of the **last click that reached the map**, often half a screen away. When a release did reach `_unhandled_input`, `drag_start.distance_to(drag_end)` was huge, the click was routed to the **box-select** branch, and that branch asked "is this UI?" about the *start* point — a point out on the map. The answer was honestly "no", the box ran, selection cleared, forge closed. **The panel geometry was never the problem; the wrong point was being tested.** `_input()` sees events before the GUI and consumes nothing, so `drag_start` is now correct whether the press landed on the map or on a button, and `_press_over_ui` (set at the same moment) discards the whole gesture if it began over the UI — at any drag distance. `_rmb_press_over_ui` does the same for right-click. Reproduced and pinned by `qa_forge_focus` B3/B4, with B5 asserting a gesture begun on the map still closes the panel.
- **`_handle_box_select` rejects a box whose *either* end is over UI**, duplicating the `_press_over_ui` guard on purpose: that guard knows where the press was, this one works from raw coordinates and so holds however the function is called (harnesses included).
- **Floating tooltips are part of the safe zone** (`_forge_tip`, `_stat_card`, `_bonus_tip` are in `_focus_panels()`). The forge tooltip is pinned *beside* its panel by design, so it falls outside `_forge_panel.get_global_rect()`; without listing it, clicking a visible tooltip fell through to the world and closed the very panel it described.
- **A click inside a visible HUD panel never reaches the world.** `SelectionManager._over_ui()` → `HUD.point_over_ui()` tests the click point against every visible panel rect (`_bottom_panel`, `_forge_panel`, `_overbar`, `_res_panel`, `_top_right`, `_idle_widget`, `_stat_panel`, `_garrison_strip`) and LMB/RMB/box-select all bail out early. `MOUSE_FILTER_STOP` on the buttons was **not** enough: labels and icons sit at `IGNORE` (so they don't steal hover from the button beneath), gaps between buttons are covered by nothing, and the forge's node grid and arrow canvas are bare `Control`s — a click into any of those gaps fell through to the world, read as "clicked empty ground" and closed the panel. The panel therefore closed on a **miss**, not on a hit.
- **Escape closes the building panel first, the settings menu second** (`HUD._close_building_panel`). Escape with nothing open still opens the pause menu.
- **The forge's "currently researching" cell is `FORGE_QUEUE_ICON` (42), not `QUEUE_ORDER_ICON` (10).** The "empty black rectangle under the Smithy icon" was that cell — a 10 px slot is too small to show a tech icon. `_research_slot` picks its size from `forge_visible()`, and `FORGE_QUEUE_DROP` pushes the row down under the building icon.
- **Horizontal `link` arrows in the forge are now REAL, but as an ALTERNATIVE entry (OR), not a requirement (AND).** `research_blockers` opens a node if all `prerequisites` are researched **or** any `link_ids` neighbour is. This is the owner's "step sideways if there is an arrow" rule. The old warning ("making links prerequisites deadlocks both cells") applied to AND — the arrows are drawn double-headed, so `2a` would need `2b` and `2b` would need `2a`. As an alternative path, two-way links are safe by construction: they only ever permit. `qa_forge` B7–B9 pin this down.
- **Barracks/TownCenter use the same `_castle_boost` flag as the Castle** — one standard, not three. Any new production building gets the fixed panel, rounded portrait with HP above it, centred oversized hire buttons and the 2×5 queue by setting that one flag.
- **Ally overlap never pushes a moving unit backwards** (`Unit._resolve_overlap`). Allies never blocked the step (`_move_blocked` only checks the enemy line and trunks) — the separation nudge was what stalled a march through a dense friendly block, arriving from several neighbours at once and cancelling the step. For a unit in MOVING/ATTACKING the component of the push **against** its velocity is removed; the lateral part stays, so it slides around neighbours. Arrival is then guaranteed by construction: forward progress can no longer go negative. Standing units keep the full push.
- **`squad_close_ranks` synthesizes a formation when the squad never had one** (`_default_block_slots`: a square block around the current centroid, facing the squad course or the mean facing). A squad that walked out of a barracks and straight into a fight had `slots` empty and stayed a shapeless blob afterwards — the owner's "phantom soldiers with spears pointing nowhere". Two guards on it, both learned the hard way:
  - **`at_order <= 0` is only checked on the `force = false` path.** It exists solely for the loss fraction. As a general early-out it silently killed the whole feature for exactly the squads that needed it (never ordered ⇒ `at_order` 0). Diagnosed with a throwaway probe: slots were built, `reshuffled` stayed 0.
  - **Never synthesize while the squad is on the move** (`_squad_on_the_move`: any member sprinting, or MOVING with `_march_pending`). `close_ranks` sends `command_move` to everyone, which cancels a sprint and drops the target lock. Measured (`qa_upd4` D4, went red): a squad ordered to *run past* an enemy took an arrow, the "recently hit" retry fired just as it drew level with that enemy, the sprint was cancelled and three of four engaged — the exact thing the run order was avoiding.
  - A squad under a player `target_lock` is skipped entirely: the lock outranks reformation.
- **A player attack order no longer clears the squad's formation.** It is *suspended* (close_ranks refuses while the lock is live) and reused to reform after the fight. `squad_clear_formation` there meant a squad that ever attacked lost its shape permanently.
- **Several selected squads land on a grid, not in a heap** (`SelectionManager._issue_group_grid_move`). The click is the group centre; each squad keeps its internal shape (`_issue_march_keeping_shape` with a shared `course_override`, or flanking blocks arrive fanned out). Columns: 1–2 → one row; **3–4 → three columns** so the middle squad lands exactly on the click (the owner's "centre squad on the click, others left/right/behind" — `ceil(sqrt(4))` would give 2×2 and put *nobody* there); 5+ → `ceil(sqrt(n))`. Rows are centred individually so a short last row sits in the middle. Cell size comes from the widest/deepest selected squad plus `GROUP_CELL_GAP`.
- Covered by **`qa_group_grid`** (12 checks: 2/3/5-squad layouts, the centre-on-click rule, marching through a 30-man friendly wall, and post-combat reformation with a single shared facing).

## Squad lifecycle additions

- **Gate spawning:** the exit is a real `Marker3D` child named `SpawnPoint`, placed at the **drawn** doors — see "Units came out of the corner" below. (Until Aug 14 2026 it was `front_dir()`, "toward map centre", which is what put the squad beside the building.) `Building.square_cols(total)` gives the square-brick column count and is used by both hiring and garrison release.
- **Rank-by-rank exit:** `_drain_pending_spawns(delta)` releases one whole rank per `ROW_RELEASE_SEC`, not N units per frame. **Anything deciding "do I need another order?" must use `Building.orders_in_progress()` / `in_progress_count()`, never `production_queue.size()`** — the queue empties the moment production finishes, while the squad is still walking out for up to ~2 s, and the AI double-ordered in that window (qa_ai showed 7 spearman squads against a limit of 3). Harnesses that want to skip the pacing set `bld._row_gate = 0.0` alongside `_production_timer`.
- **Post-combat reformation:** leaving combat calls `squad_close_ranks(sid, force = true)`, which bypasses the loss threshold (a melee scatters the block even with zero casualties) but still respects the cooldown.
- **Catch-up:** a unit reaching its slot calls `GameManager.squad_note_arrival()`; past `CATCH_UP_TRIGGER` (35%) the squad flips `catch_up` and stragglers get `Unit.CATCH_UP_FACTOR` (+15%). Reset by `squad_set_formation`. The flag is **pushed down to the members** (`GameManager.squad_set_catch_up()` → `_push_catch_up()` writes `Unit._catch_up`), it is *not* polled per frame — writing `squads[sid]["catch_up"]` directly no longer reaches the units, use the setter (that is what broke `qa_spear` B5/B6 once).
- **Retreat mode:** `Unit.retreating` (set via `begin_retreat()`, cleared by `end_retreat()`/any new `command_move` without `keep_retreat`). While set: no march interception, no auto-aggro, no retaliation, and `_move_blocked` ignores enemy ranks so the squad can't be cornered. Damage still applies — "ignores damage" means "doesn't get distracted", not invulnerable.
- **Mid-combat move orders:** `Unit._disengaging`, set in `command_move()` only when `attack_target` was still live (i.e. the order interrupted a fight), cleared on arrival or by `command_attack()`. Suppresses march-interception (`_process_move`) and in-place retaliation (`take_damage()`) for that march — without it, a unit ordered away from an adjacent enemy took a half-step, re-intercepted the same enemy, and never actually left. Unlike `retreating`, `_move_blocked`/`enemy_block` still holds: a plain move order doesn't ghost through enemy lines, it slides along them. `_resume_march()` (continuing a march after its own intercepting fight ends) nulls `attack_target` before calling `command_move()`, so resumed marches still intercept new enemies encountered further along — only a direct order given *while* a target was live suppresses it.
- **Charge flag:** `command_attack(target, forced, charge)` — only `charge = true` (player RMB, AI attack decisions) makes spearmen level spears on the march. Auto-aggro also sets `forced`, so `forced` alone is not enough to distinguish an ordered charge.
- `_effective_speed()` stacks: march ×0.5, phalanx-in-motion ×0.75, catch-up ×1.15.
- **Retarget after a squad-order target dies:** `_process_attack()`'s `attack_target == null` branch re-seeks within `attack_range` normally, or `maxf(attack_range, FORCED_RETARGET_RANGE)` (6.0) when `_attack_is_forced` — the `FORCED_RETARGET_RANGE` floor exists to catch flanking melee ranks whose `attack_range` (~1.8-2m) is smaller than the gap that can open around a dying scrum, **not** to cap ranged units. Using the bare constant instead of `maxf(...)` shrank an archer's normal ~20m firing radius to 6m the instant its shared target died — with several archers sharing one target (squad_pick_member spreads by least-attacked, so a squad outnumbering its target does this), the survivors went IDLE while a live enemy stood a few meters outside the 6m floor, well inside actual bow range. Covered by `qa_archer_retarget` (deliberately fewer enemies than archers, so multiple archers must reacquire after a shared kill — a 1:1 squad matchup never exercises this path at all).
- **Forced-attack orders now intercept blockers too:** `_process_move()`'s enemy-intercept (contact with a foreign squad pauses a plain move order, `_march_pending`/`_resume_march()` continues it afterwards) used to be the *only* path that did this — a forced `command_attack()` march (dist > attack_range, approach branch) never read `_enemy_contact` at all, so a squad ordered to attack a far target walked straight **through** any other enemy squad standing in the way, dealing and taking zero damage (confirmed via `qa_approach_intercept`, red before the fix). Mirrored the same contact-check into that branch; the original forced order is now remembered as `Unit._atk_pending`/`_atk_pending_squad` (a squad id, not a unit reference — the originally-ordered model may die to someone else's hand while the blocker fight is in progress) and resumed via `_resume_attack()` the same way `_march_pending` resumes a move order. `command_attack(forced=true)` sets it (mirrors clearing `_march_pending`); `command_move()` clears it (a fresh move order overrides a pending attack-resume, symmetric to how a fresh forced attack clears `_march_pending`). Covered by `qa_approach_intercept`.
- **Squad-level combat lock (`GameManager.squad_in_combat`)**: `squad_close_ranks()` used to be called *unconditionally* by whichever single unit's own fight happened to end first — either from `_die()` (a squadmate's death, `force=false`, gated only by a loss threshold) or from `_process_attack()`'s "nothing left nearby" branch (`force=true`). `close_ranks()` itself issues `command_move()` to **every living squad member**, and `command_move()` on a unit with a live `attack_target` drops that target — so the moment *any one* member ran out of personal targets, the whole squad (including members still actively fighting a few meters away) got yanked into a march toward the *old* formation slots, auto-aggro immediately re-engaged them, and the squad visibly "danced" forward/back until the enemy was wiped. Root-caused by reading the code, not by guessing (matches the player's "kill one model → whole squad tries to reform → auto-aggro drags it back" report exactly). Fix: `GameManager.squad_in_combat(sid)` is true while *any* living member has a live `attack_target`, or the squad took damage within `RECENT_HIT_WINDOW_MS` (3000ms, tracked via `squad_mark_hit()` called from `Unit.take_damage()` — covers being shot at from outside melee range with no one engaged in melee). Both `_die()`'s and `_process_attack()`'s deferred `squad_close_ranks` calls are now gated on `not squad_in_combat(sid)`; the "recent hit" clause also self-schedules one retry (`get_tree().create_timer`) so a squad that stops taking damage right as its last melee target dies still gets swept once the window lapses, even if no unit transitions through `_process_attack()` again afterward — and that retry **re-arms itself** (`GameManager._reform_check`/`_arm_reform_check`) if the squad is still in combat when it fires, because `squad_mark_hit()` only updates the timestamp while a check is already pending: a single early firing used to consume the one and only retry and leave the squad permanently unformed (`qa_combat_lock` #3, intermittently red). When the squad genuinely leaves combat, `squad_close_ranks(sid, force=true)` now recomputes the slot positions around the squad's **current** centroid (`GameManager._slots_recentered`) instead of the stale slots from the original march/attack order — otherwise a squad that won its fight somewhere other than its original destination marched back to that stale point instead of reforming where it stood. Only the `force=true` ("left combat") path recenters; the loss-triggered in-march reshuffle (`force=false`) still targets the original march destination, which is correct while the march is still in progress. Covered by `qa_combat_lock`.
- **Test-harness timing gotcha (distinct from the real-time `while Time.get_ticks_msec()` one already documented):** a QA harness that awaits `get_tree().process_frame` in a loop to simulate "N frames = N/60 simulated seconds" is only accurate if render frames and physics ticks stay 1:1. With `Engine.max_fps = 0` (used by every perf/long-running harness to skip the render cap), render can tick **faster** than the fixed 60Hz physics rate, so most `process_frame` signals fire with zero physics ticks in between — "await 6000 process_frame" can complete in far less simulated time than 100 seconds, and the shortfall varies run-to-run with however fast the render loop happens to spin. This produced an apparent regression in `qa_approach_intercept`/`qa_combat_lock` (test failed once, passed cleanly on a rerun with no code changed) that had nothing to do with game logic. Fix: harnesses whose `frames()` helper needs to correspond to real simulated time should await `get_tree().physics_frame` instead — it fires exactly once per `_physics_process` tick regardless of render speed. `qa_archer_retarget`, `qa_approach_intercept`, and `qa_combat_lock` all do this now; older harnesses (e.g. `qa_mass_move`) still use `process_frame` and haven't been audited for this — treat an unexplained one-off failure in any `Engine.max_fps=0` harness as possibly this, not a real regression, before chasing it as a bug.

## Smart targeting on the forest, and the squad hitbox

- **SUPERSEDED Aug 14 2026 — the tree's collider is no longer the whole sprite.** The two bullets below argue from a 1.35 × 4.8 m cylinder covering the crown; it is now a 0.60 × 1.80 m cylinder on the trunk, and wood gained the camera-lean correction it did not need before. The reasoning about *why* a wide crown collider swallows orders still stands — it is the reason the owner asked for the change.
- **A tree is a target only for a Worker.** `SelectionManager._handle_right_click` puts `Constants.LAYER_RESOURCES` into the pick mask **only when `selection_has_worker()`**. This is done at the mask, not as a post-filter: with the layer absent the ray passes the forest entirely, the ground point is computed *behind* the trunks, and the usual unit scan around that point finds an enemy standing **in** the wood with no extra branch. A tree's collider is a 1.35 × 4.8 m cylinder and the camera looks down at 45°, so that column of air covers several metres of ground *in front* of the trunk — a soldier order into open woodland was regularly swallowed by it (a swordsman has no "chop" command).
- `Main._update_hover_cursor` reads the same `selection_has_worker()`, so the gather cursor only appears when the click would actually gather.
- **A click near an enemy block counts as an attack on it** (`_enemy_in_squad_zone`, `SQUAD_CLICK_REACH` 2.5 m): the player aims at a squad, not at one man's pixels. Only consulted when the pick found nothing (or one of your own units), and only when the selection can actually fight (`_selection_can_attack`) — a worker crew must not be sent to die on a click near a spear line.
- A mixed selection splits the order: workers gather, everyone else gets a move order to the click point (before, non-workers silently got nothing).

## Sprite proportions

Any textured quad must take its aspect from the **texture frame**, never from a collision box or a hard-coded pair. `Building.sprite_quad_size(tex, box)` is the single helper (width from the building's plan, height derived from `BillboardUtil.frame_aspect`); the placement ghost in `Main._create_ghost` uses it too. Sizing buildings from `build_size` squashed barracks/smithy/mine by 2.1–2.3× — only the castle looked right because its box happens to match its art. Unit sprites are `AnimatedSprite3D`/`Sprite3D` scaled by a single `pixel_size`, so they are aspect-correct by construction; frames are square (192² for worker/archer/warrior, 320² for spearman, hence the spearman's larger on-screen height). `qa_aspect` audits all of it.

## Castle panel, resource bar and config files (Aug 8 2026 pass)

- **Castle panel is 345 × 74** (`CASTLE_PANEL_W/H`, +15 % wide / +20 % tall). Still a *fixed* size — the queue must not be able to move it. Height has a floor of `CASTLE_PORTRAIT_W + CASTLE_CAPTION_BAND + CASTLE_CAPTION_INSET` so the caption band can never collapse onto the icon.
- **The Castle icon sits at the bottom** (`_portrait_wrap.size_flags_vertical = SIZE_SHRINK_END`, reset to `SHRINK_CENTER` for every other selection), leaving the band above it for "Замок N/N HP". The portrait's stylebox now has `_corners(…, 5)` + `_borders(…, 1)` — the same shape and edge as the unit/command icons in `_cmd`.
- **Hire buttons are vertically centred** (`button_container.size_flags_vertical = SIZE_SHRINK_CENTER`; a `GridContainer` stretched to full height lays its children from the top, which is why they looked "задраны вверх") and pushed right by `_btn_spacer` (`SIZE_EXPAND_FILL`, inert on every panel whose width is content-derived). The right margin is `_btn_right_pad`, and it is **`CASTLE_BTN_RIGHT_PAD − PANEL_HBOX_SEP − PANEL_BORDER_W`**, not 15 flat: the distance from the buttons to the panel edge is separator + spacer + border. `_squad_strip` was moved **before** the spacer — anything after it belongs to the right-hand group and would push the buttons off the edge.
- **The order queue is a 2 × 5 grid with no frame.** `_queue_grid_cols(n)` keeps 5 columns up to 10 orders (so 6 orders read 5 + 1, as the mockup asks) and adds columns beyond that while staying two rows; `_queue_cell_side(n)` divides the zone on **both** axes and takes the smaller. `QUEUE_ORDER_MAX` is 20. The yellow border is gone (`_borders(qf, 0)`, `draw_center = false`) — the `PanelContainer` stays only because it holds the fixed footprint.
- **SUPERSEDED TWICE — read "Resource bar: the tool glyph is per resource (Aug 14 2026)" instead.** The two reversals below are the history of this line; the current rule is one tool glyph per resource and no "total" section at all.
- **Every resource section carries the worker tail again** (owner reversed the earlier "one section only" call): pickaxe `RES_GATHER_GLYPH` + per-resource count on wood/stone/gold, axe `RES_WORKER_GLYPH` + **total** workers on food (food is produced by Houses, never gathered, so a per-resource count there would be permanently zero). Gathered sections show the counter **always, including 0** — that is the answer the player asked for — dimmed at zero. `RES_WORKER_GLYPH_W` 15→12 and `RES_WORKERS_W` 11→9 keep the four tails from sprawling; `qa_ui9` #4's width guard moved 0.30 → 0.36 for the same reason.
- **Tooltips are pinned above the *panel*, not just above the button** (`_tip_anchor_geometry` clamps to `PANEL_TOP - TIP_GAP`). Those coincided only while buttons were top-aligned; centring them put the anchor deep inside the panel and the card landed on top of it (`qa_hud5` D3).
- **Starting resources live in the config**: `unit_stats_config.PLAYER_STARTING_RESOURCES` / `AI_STARTING_RESOURCES` + `starting_resources(faction)`. Two blocks with **identical** values — the equal start is deliberate (an AI with 50 more wood/gold laid its first building sooner, which read as "resources fall from the sky"); the split exists so a handicap can be given on purpose.
- **Tooltip contents are config-driven** (`scripts/tooltip_config.gd`): `PARAMS` is the library of renderable rows (`value_type` is `stat` / `current_max` / `plain` / `pair`), and `TOOLTIPS[id]` carries `display_name`, `icon`, `description` and `visible_stats` — the exhaustive, ordered list of rows for that card. **A parameter absent from `visible_stats` is not rendered** — that is how "Броня" disappears from the Worker card instead of printing `Броня 0`. `base_value()` is a second gate: a row listed but missing from `STATS` also renders nothing, and an unknown key is skipped rather than crashing. A row entry may override the library (`{"key": "cooldown", "fmt": "…"}`) without touching `PARAMS`. `HUD._unit_card`/`_tip_row` contain no per-unit special cases.
- **`PARAMS` / `TOOLTIPS` / `DEFAULT_VISIBLE_STATS` are `static var`, not `const`, on purpose** — same as `VET_CONFIG`. Godot 4 makes `const` collections **read-only at runtime**, so the requested "edit the config and the modal rebuilds itself" is impossible with `const`: writing to it does nothing (and cost a hung harness before this was understood). `static var` keeps them editable live; `qa_cfg` B1–B4 add and remove rows at runtime and assert the card follows.
- **`forge_config.node_view(id)` / `tree_view(unit)` present a node in the requested self-describing shape** — `id`, `title`, `description`, `icon` (resolved to a full `res://` path), `cost` as `{"gold":…,"wood":…}`, `research_time`, `prerequisites` and `links` as full node ids, `stat_bonus` as `{"attack":2,…}`, with zero-valued entries omitted. It is a **view, not a second copy**: the numbers still live once in `UNITS`/`GRID` (flat `cost_*`/`bonus_*` keys, which are what makes the table editable by eye). Edit `UNITS`/`GRID`, read `node_view()`.

## Config is the source of truth

`scripts/unit_stats_config.gd` is the owner's balance sheet — unit stats, veterancy bonuses, kill thresholds, upgrade slots, prices, times. **It is always right.** When a harness disagrees with it, fix the harness.

QA harnesses must never hard-code a number that lives in the config. Derive expectations from `_UCfg.*` and assert *properties*, not values: "the bonus reached every model", "the level flips exactly at the configured threshold", "the total equals the sum of what was actually chosen". Also make no structural assumptions: `KILL_BONUS_THRESHOLDS` is currently `[40, 120, 200, 200, 300, 400, 500]` — thresholds may repeat (one kill can grant two levels), and squad level never decreases even if a test rewinds the counter.

**Never index `UPGRADE_SLOTS[0]` (or any slot by position) — ask `GameManager.can_research()` for one.** `UPGRADE_SLOTS[0]` ("spears") carries `"requires": "Bla bla bla"`, a placeholder that names no real upgrade, so `can_research()` refuses it **forever**, `Smithy.research()` returns false and nothing starts. A harness that hard-codes slot 0 then silently tests an idle smithy and reports whatever the empty state happens to be (that is what `qa_queue` 4c was doing — it asserted the big progress bar stays visible during research, while no research had begun). Both `qa_queue` and `qa_sel2` now scan for the first slot that `can_research()` accepts *and* whose `upgrade_research_time()` is above zero. The placeholder is the owner's, it is not a bug to "fix" in the config.

## Veterancy grades (7 levels, three star tiers)

**Star count is NOT the level any more.** `VET_STAR_TIERS` maps level → `{count, tier}`: levels 1–3 are 1/2/3 **bronze** stars, 4–6 are 1/2/3 **silver**, 7 is a single **red** one. Colours live in `VET_TIER_COLORS`, per-tier size multiplier in `VET_TIER_SCALE` (red is ×1.35 — the highest grade is deliberately bigger). `veteran_star_tier(lvl)` is the single resolver and returns `{count, tier, color, scale}`; a level past the last entry keeps the last grade rather than vanishing. Both consumers read it: the 3D `VeterancyStar.gd` and `HUD._stars_text()` / the portrait star label. Anything asserting "N stars = level N" is stale — derive the expected count from `veteran_star_tier()` (that is what broke `qa_vet` 4б/6/4в once).

**The star hangs at the squad's centre of mass, in the world — not on a unit.** It used to be a child of `members[0]`, which was free (it rode along with no `_process` at all) but wrong twice over: it floated over the *edge* man of the block, and it jumped to a different person whenever the leader died. `GameManager.refresh_star()` now parents it to `main` and `_place_star()` puts it at the plain mean of every survivor's position, with Y from `get_terrain_height()` (the centroid can land where nobody stands — a squad flowing around a tree). `_update_squad_stars()` in `GameManager._process` moves them, throttled to every `STAR_UPDATE_FRAMES` (6 ≈ 10 Hz) and skipping squads with no star; `squad_centroid(sid)` is the public form of the same maths. `remove_from_squad()` no longer re-hangs anything — a death cannot orphan a world-parented node, it only shifts the average.

`VeterancyStar.STAR_RADIUS` is **0.196** — doubled from 0.098 at the owner's request, because the small size was chosen back when the star sat above one man's head; over a whole block it read as a speck. Star spacing is expressed as `SPACING_RATIO × radius`, **not** a fixed metre value — a fixed step would let the larger red star's points overlap its neighbours.

The same `chosen` list also drives the HUD bonus row (see below), so a level may legitimately repeat a bonus id.

## Squad bonus row (icons, Roman stacks, tooltip)

`GameManager.squad_chosen(sid)` returns a **copy** of the squad's picks *in level order* (element `i` = the reward taken at level `i+1`), so the same id repeats when the player takes it several times. `HUD._build_bonus_row()` renders one icon **per kind of bonus**, not per level, and overlays a Roman numeral (`HUD._roman`) from the second take onward — `II`, `III`, `IV`. Icons are `BONUS_ICON_SIZE = BONUS_ICON_BASE * 0.7` (−30 %, owner's request) and carry **no green check** — that mark means "purchased" in the smithy, and this row means "how many times taken".

Hovering an icon opens `HUD._show_bonus_tip()` — its **own** panel, not the shared `_show_card()`: the shared card is pinned to the top edge of the bottom panel, which is exactly where the stat panel (and therefore the icon row) lives, so it would cover its own anchor. The tip stacks above `_stat_panel.offset_top`. The per-bonus total is summed **through `veteran_choice_at(level, id)`**, never "value × count" — the same id is worth different amounts at different levels.

## Forge tech tree (the Smithy panel)

**The Smithy does not use the shared bottom panel at all** (owner's redesign, Aug 7 2026). Selecting a player Smithy hides `_bottom_panel` and shows `HUD._forge_panel` instead — `show_selection()` branches on this *before* the two selection levels, and `hide_forge()` runs unconditionally otherwise. The reason is geometric, not cosmetic: the 5×4 node grid with dependency arrows is ~230×240 px of **absolutely positioned** children (`_forge_cell_pos`), and the shared panel derives its height from `get_combined_minimum_size()` — a bare `Control` full of absolutely placed buttons reports nothing, so the panel collapsed and clipped rows 4–5. `FORGE_PANEL_H` is therefore an **explicit** number, summed from the same constants that lay the grid out.

- **Data lives in `scripts/forge_config.gd`, not in `unit_stats_config.gd`, and it is now ONE table.** `UNITS[unit][cell]` carries both the shape (`icon`, `prereq`, `link`) and the numbers (name, desc, costs, time, `bonus_*`, `squad_unlock_cost`). The old second table `GRID` — one shape shared by every tab — is **deleted** (owner's call, Aug 14 2026): sharing it made "change the archer's icon without touching the swordsman's" impossible in principle, because all tabs drew the same pictures from the same graph. The price is accepted and known: the combat branches now repeat the same graph four times and a change to *the tree itself* must be made in all of them. `tree(unit_id)` assembles a cell into a full node and caches it, and it is the **only** reader of `UNITS` — the panel, the arrows, the tooltips and `GameManager` all take the assembled node, so "the icon comes from `UNITS`" is stated once instead of five times.
- **There are five tabs, and `worker` is first** (`UNIT_TABS`). Its branch is economic — A вместимость, B темп добычи, C ходьба/живучесть — and its graph is deliberately a different shape from the combat ones (two sideways pairs instead of a link on every row), which is the whole point of per-unit shape.
- **`BONUS_KEYS` gained `bonus_carry` and `bonus_gather`.** `bonus_carry` adds to `Worker.gather_amount` (read through `Worker.carry_capacity()`); `bonus_gather` is **seconds off the gather cycle** — stored positive like every other bonus and *subtracted* in `Worker._cycle_time()`, floored by `Worker.MIN_CYCLE_TIME` (1.10). One key with an inverted sign in the balance sheet would eventually be filled in the wrong direction. `HUD._BONUS_TITLES` and `_upgrade_card`'s `human` table need an entry for every new key — the latter used to do `String(human[k])` and would crash on `Nil` for an unknown one; it now falls back to the raw key.
- **A column-D cell is an ABILITY only if it declares `squad_unlock_cost`.** The worker's D column is ordinary passive research (there is nothing for a worker squad to buy), so `tree()` sets `is_unit_ability` from the price, not from the column. The **row gate** still applies to all of column D regardless — that is a layout rule, not a property of abilities. `qa_forge` A6 asserts the invariant and that the price is present in the whole column or in none of it.
- **A tree node IS an upgrade slot.** `unit_stats_config.get_upgrade_slot()` falls back to `forge_config.get_node()`, so the entire existing research machinery — resource spend, smithy queue, `researched`/`researching`, bonus accumulation, instant HP top-up — works on tree nodes with **zero** extra branches. Node ids are globally unique (`warrior_3b`) precisely so they can share `GameManager.researched[faction]`.
- **Access rules are `GameManager.research_blockers()`, not a bool.** Three kinds stack: `requires` (the old flat slots' single parent), `prerequisites` (array — **all** needed), and `row_gate` (column D only). `can_research()` is just `research_blockers().is_empty()`. The blocker list exists because the hover panel must *name* the missing node — a grey icon with no explanation is the thing the redesign was meant to fix.
- **Column D is gated by its whole row, not by an arrow.** `1D` needs `1A + 1B + 1C` researched. This is a separate rule from `prerequisites`, and the tooltip says so in words ("изучите весь ряд N") rather than listing three ids.
- **Horizontal `link` arrows are decoration, not dependencies.** The mockup draws them double-headed; making them real prerequisites would deadlock both cells forever. Real dependencies are always vertical, top-down. `qa_forge` B6 asserts no mutual pair exists.
- **Abilities are two-stage.** Researching a D node unlocks it for the *faction*; each squad then buys it for itself with gold (`GameManager.squad_buy_ability`, cost `squad_unlock_cost`). The mark lives in `squads[sid]["abilities"]`, so a wiped squad loses it and a fresh one pays again. The buy button is built by `HUD._maybe_add_ability_buttons()` in the **squad's** panel (both selection levels), never in the forge.
- **Locked forge nodes stay `disabled = false`.** `_apply_upgrade_state()` would disable them, but a disabled `Button` swallows `mouse_entered` — i.e. exactly the node the player wants to hover ("why can't I take this?") would show no tooltip. Re-ordering is refused by `Smithy.research()`, as it already is for in-progress slots. `qa_upgrade` D3/D6 pin this down.
- **`_rebuild_*` uses `remove_child()` before `queue_free()`.** Freeing is deferred to end-of-frame, so a same-name replacement added in the same call gets uniquified (`ResearchSlot_x` → `…@2`) and lookups by name silently miss. This bit `qa_upd4` B8 during the build.
- The research-queue row is the same `_research_slot()` widget as before, just re-homed: `_rebuild_research_queue()` targets `_forge_queue` when `forge_visible()`, else `_queue_box`.
- Covered by **`qa_forge`** (42 checks: config integrity, arrow gating, the row gate, panel/tab/grid geometry, tooltip placement and wording, the two-stage ability purchase). `qa_upgrade`, `qa_icons`, `qa_sel2` E1–E4 and `qa_upd4` B7–B9 were repointed at the forge panel — their assertions are unchanged in meaning, only the container moved.

## Smithy research queue

The smithy still researches strictly one technology at a time, but orders **stack**: `Smithy.research(id)` starts it if idle, otherwise appends `{id, time}` to `research_queue` (cap `QUEUE_MAX`). Resources are spent **at queue time**, like unit hiring — otherwise the player reserves five technologies for free and is broke when they start. The queued item stores its own `time`; it is not re-read from the config on start, so a cancelled slot cannot be started twice.

`GameManager.cancel_research(faction, id)` clears the "in progress" mark and refunds **100 %** (owner's call: no penalty for a misclick). An already-**finished** research is not cancellable — the bonus has already been distributed to units and there is nothing to roll back. `Smithy.cancel_research()` handles both the current item (next in queue takes over immediately via `_start_next()`) and a queued one.

`GameManager.can_research()` already returns false for anything marked in progress, so the queue needs no separate duplicate check — one id can be ordered once.

HUD specifics: the researching/queued button stays **`disabled = false` on purpose**. A disabled `Button` swallows mouse input, and RMB-to-cancel arrives via `gui_input`; double-ordering is prevented by `Smithy.research()` returning false, not by the widget. A **researched** upgrade gets *light* dimming (`UPG_DONE_MODULATE`, ~0.88 grey) plus a `DoneCheck` in exactly `UPG_CHECK_COLOR` = **#32CD32** — it must **not** go dark/solid (explicit owner complaint).

**The queue is a row of icons, not numbers on the buttons.** `QueueBadge` is gone: the order is shown by `_rebuild_research_queue()`, which fills the panel's left column (`_queue_box`, the same one the hire queue uses — a selected smithy has no hire queue, so the column was idle) with one `ResearchSlot_<id>` cell per order, `columns` set to the order count so it stays a **single horizontal row**. First cell = what is researching now (gold border + progress bar fed from `_update_queue_ui`'s Smithy branch); RMB on any cell cancels that order through the same `_on_upgrade_gui_input`. `_queue_signature()` prefixes the smithy's signature with `"R:"` so an empty hire queue and an empty research queue aren't the same string.

**`_add_done_check` stretches the label over the whole button and corners it by *alignment*.** A `side × side` rect does not work: a `Control` cannot be smaller than its own minimum size, so at `BTN_SIZE = 22` the label inflated to the glyph's size and spilled *outside* the button — the opposite of "inside the corner". Same trick as `_add_badge`.

## Sprint (double RMB)

There is exactly **one** standard walking speed — the config's. `MARCH_SPEED_FACTOR` (the old ×0.5 "march") is **deleted**; `command_move`'s `slow_march` argument survives only as a formation-strictness flag stored per squad. The one movement multiplier left is `Unit.SPRINT_SPEED_FACTOR` (1.4). `PHALANX_ATTACK_FACTOR` and `CATCH_UP_FACTOR` were kept deliberately — the first is a stance-combat penalty, the second a straggler correction; neither is a movement "mode".

`SelectionManager._consume_rmb_double()` detects the second RMB **click** (not drag) within `RMB_DOUBLE_TIME` (0.35 s) and `RMB_DOUBLE_SLOP` (24 px) of the previous one, comparing **screen** points — the camera can pan within 0.35 s, so two world positions for "the same spot" diverge. A recognised double consumes the state, so a triple click is a sprint plus a fresh first click, and an RMB **drag** (line formation) resets it. The flag rides `_handle_right_click → _issue_formation_move → _issue_march_keeping_shape → command_move(..., run)`.

`Unit.sprinting` is set only through `_set_sprinting()` (it marks `_pose_dirty` and wakes the process, so a sleeping spearman re-poses). While set it behaves like a stricter `retreating`: `_effective_speed()` applies ×1.4 and skips the phalanx penalty, `_phalanx_advance` is off, `Spearman._spear_leveled()` returns false **first**, before both the DEFENCE stance and the charge order (spears go vertical, the block runs), all five combat gates (`not retreating and not sprinting`) suppress auto-aggro, march interception and retaliation, and `_move_blocked` skips `enemy_block` so the squad runs *through* enemy ranks instead of sliding along them. Damage still lands — sprinting troops are deliberately vulnerable. The flag clears itself on arrival (`_arrive_at_target`) and on any new non-run order. `Worker.command_move` overrides the base and must forward `run`.

All four of the above are covered by `qa_upd4` (26 checks: star grades, queue/cancel/refund/HUD state, bonus row + tooltip maths, sprint speed/phalanx/no-combat/auto-clear/double-click, plus a walking control case that must still intercept).

## Battle cry and the active-stance highlight

- **The sound file is `assets/factions/humans/Sounds Human/soldiers-battle-cry.wav`** — lowercase, hyphenated. It is *not* `res://Sounds/Human/Soldiers_BattleCry.wav`; that path does not exist in the project. Registered as the `battle_cry` category in `AudioManager.SFX_BANK`.
- **`battle_cry` is the only category with `gap = 0.0`, and that is deliberate.** `gap` in `SFX_LIMITS` is a *per-category* throttle — `play_3d` drops a sound if the same category fired less than `gap` seconds ago. For axes that stops a metronome; for a battle cry it would destroy the whole point, since the requirement is one cry *per squad simultaneously* and any non-zero gap leaves exactly one — whoever got there first. The chorus is bounded by `voices` (6) instead, so six squads sound together and the rest are dropped without eating the 28-voice pool.
- **Rate limiting lives on the squad, not the category** (`GameManager.CRY_COOLDOWN_MS`, 1.5 s, tracked in `_cry_last`). Without it, ten move orders in a row give ten overlapping cries.
- **It is 3D audio, not `AudioStreamPlayer2D`** (which the request asked for). The game is 3D: the voice pool is `AudioStreamPlayer3D`, the listener sits at the camera focus, and falloff is measured in world metres. An `AudioStreamPlayer2D` lives in screen space and knows nothing about the world — it would give neither distance falloff nor panning, i.e. the opposite of the "keep the spatial acoustics when the camera moves" requirement.
- **One cry per squad, from `squad_centroid`** — not per unit (20 men would be 20 calls, all but a few thrown away) and not from `members[0]` (the voice would jump between flanks as the leader changes).
- Triggers: `SelectionManager.set_selection_stance` (only when the stance *actually changes* — re-clicking the active button is silent), `_issue_formation_move` and `_execute_line_formation`. The two move-order entry points are the *top-level* ones on purpose: `_issue_march_keeping_shape` / `_issue_group_grid_move` are the layouts those two choose between, and crying there would fire twice. Ctrl+1..9 needs no branch of its own — a hotkey group only *selects*, the order still arrives through `_issue_formation_move`. Worker crews never cry.
- **`_cmd(..., active)` paints the yellow active border** (`ACTIVE_BORDER_W/RADIUS/COLOR`) on both `normal` and `hover`, so hovering the active stance does not erase the very answer the player is looking for. Relying on the fill colour alone was not enough — both Attack shades are dark red and read the same at a glance.
- Covered by **`qa_battlecry`** (16 checks: bank/file/limits, per-squad chorus on stance change, silence on a repeat click, cooldown, move orders including after a Ctrl+1 recall, workers silent, and the highlight moving between buttons).

## Icons

Smithy upgrade / veterancy icons live under `unit_stats_config.SMITH_ICONS_DIR`; config tables store **file names only** (`"icon_sword.png"`). Resolve with `smith_icon_path()` (accepts a bare name, adds `.png`, passes a full `res://` path through untouched) or `smith_icon()` for a Texture2D. `HUD._icon_texture()` is the single UI entry point and is what every button/card uses — it returns null and `push_warning`s with the attempted path instead of silently drawing a blank button. Never paste absolute icon paths into the config: a moved folder then breaks silently.

**New asset folders must be imported** (`godot --headless --import`) or `ResourceLoader.exists()` returns false at runtime even though the `.png` is on disk.

## Wind

`Tree*.png` and `Bushe*.png` are 8-frame **sway animations** — that's what the strips are for. Playback lives in `shaders/cyl_billboard.gdshader` (`frame_fps` + `frame_phase`) and is switched on via `BillboardUtil.make_wind_material()`, which randomises both the phase **and** the cycle length per plant (`WIND_CYCLE_MIN/MAX`, 2.4–4.0 s). Randomising phase alone is not enough — equal rates keep the forest moving as one body, which is why playback was originally disabled as "crawling bushes". Speed is expressed as a **cycle duration**, not fps, so 6-frame and 8-frame strips sway at the same tempo. Plants with a single frame instead get a shader vertex bend (`sway_amount`/`sway_speed`/`sway_phase`, weighted by `(1 - UV.y)²` so the base stays planted). Buildings (`make_static_material`) and stumps stay still. Covered by `qa_wind`.

## Resource income display

`ResourceManager.gather_resource()` is the entry point for anything that **appears** in the world — a worker dropping his load (`Worker._process_return`), the castle's passive gold, the mine, the house's food. It calls `add_resource()` and additionally bumps a monotonic per-faction `gathered` ledger. Refunds (cancelled construction, cancelled research) deliberately go through plain `add_resource()`: they are not income.

The HUD's green "+N" reads that ledger over a sliding window (`INC_WINDOW_SEC` 20 s, halved rather than reset so old data fades instead of stepping), and shows nothing until the window holds `INC_MIN_SAMPLE_SEC` (8 s) — dividing one delivery by the first second produced four-digit "units per minute" in the opening seconds. Two earlier attempts are documented in the function and should not be retried: measuring the **bank delta** (any purchase on the same tick drove it to zero or negative while workers kept digging) and summing the **config nominal** over workers in `State.GATHERING` (a worker is only at the rock for a small slice of each round trip, so the number flashed at the moment of delivery and went dark again — the "income flickers" complaint). `Worker.assigned_resource_type()` — as opposed to `active_resource_type()` — answers "which resource is this worker on" across the *whole* trip, and is what keeps the label lit for a crew that is currently walking.

## Trees

- **Trunk obstacles** live in `GameManager` (`register_trunk`/`unregister_trunk`/`trunk_block`), a coarse `OBST_CELL` grid — not physics, matching the project's `collision_mask = 0` rule. `ResourceNode` registers deferred (position is set after `add_child`) and drops out when it becomes a stump. `Main.start_game()` calls `clear_trunks()`.
- Collision radius is the **trunk** (`ResourceNode.TRUNK_RADIUS = 0.35`), not the 5 m sprite — otherwise a forest is a wall.
- **Gold clusters use two SEPARATE tighten multipliers, not one** (`Main.GOLD_SPREAD_TIGHTEN` 0.85, `GOLD_GAP_TIGHTEN` 0.55 — was a single `GOLD_CLUSTER_TIGHTEN` = 0.55 applied to both `spread` *and* `PIECE_MIN_GAP` at once, reversed Aug 7 2026). Squeezing the RADIUS that hard collapsed a pile's "big" pieces almost into one point, and since each piece's billboard is ~2.5×size_scale m tall regardless, overlapping tall quads on a near-zero footprint read from the camera as a narrow vertical column, not a pile ("golden pillar" complaint). `min_gap` still needs its own squeeze (`GOLD_GAP_TIGHTEN`) — without it the placement loop can't satisfy the gap check inside gold's smaller disk and dumps every piece at `Vector2.ZERO`. Both types still share `CLUSTER_PRESETS`.
- **Resource quads (gold/stone/food) are cropped to their opaque bounding box, not scaled from the full canvas** (`ResourceNode._maybe_load_sprite`, same technique as `HUD._trimmed_icon`: `AtlasTexture` over `Image.get_used_rect()`). The piece fills its square canvas very unevenly — `Gold Stone 1/2.png` is ~6% opaque, `Gold Stone 6.png` ~45%, `Rock1.png` ~20% — so at one `size_scale` the same "big"/"mid"/"small" class rendered as anything from a speck to a proper chunk. A first attempt inflated the WHOLE canvas (margins included) until the *drawn* pixels hit a target height; on a sparse variant (Gold1: art is 23% of frame height) that blew the invisible quad past 17 m, and a couple of overlapping neighbors of that size dwarfed the whole pile before their pixels even mattered. Cropping first and sizing the quad from the crop avoids inflating the margin at all. `ResourceNode._visual_half_width` (the true half-width of the drawn piece, not the padded quad) now feeds `slot_radius()` — the old flat `1.0 * size_scale` guess put a worker's approach ring *inside* a sparsely-filled variant's real silhouette once the crop made that silhouette bigger than the guess ("stands inside the ore texture" complaint); the ring now takes whichever of the two is larger.
- **The gold shimmer overlay is ON** (`ResourceNode.GOLD_SHIMMER = true`, restored Aug 7 2026). Checked pixel-by-pixel across all 6 variants × all 6 `*_Highlight.png` frames: the opaque region is identical to the base sprite's, no halo wider than the nugget in the current art — the "soft halo" this flag used to guard against isn't present in these files (assets were likely cleaned since the flag was first flipped off). What *did* still bite: piles overlap by design (`PIECE_MIN_GAP`), so neighboring pieces' shimmer quads land on the same screen pixels, and `blend_add` **sums** their contributions — the old default `gain = 0.85` on the shimmer shader (`shaders/gold_shimmer.gdshader`) blew two or three overlapping glints straight to solid white. `gain` is now `0.22`, low enough that even several stacked pieces don't clip. The shimmer quad's own crop (`crop_rect` uniform) is derived from the exact same `used_rect` as the base sprite's `AtlasTexture` above, so the sparkle still lands pixel-for-pixel on the visible nugget rather than the old full, uncropped frame.
- `Unit._move_blocked` slides along the tangent. A head-on approach cancels the step entirely, so the degenerate case is deflected sideways (side picked by instance id) — without that, trees stop units dead.
- Chopping slots derive from `TRUNK_RADIUS`, and the gatherer creeps onto its exact slot while working (`SLOT_SETTLE`/`SETTLE_SPEED`); the generous `SLOT_ARRIVE = 0.6` arrival tolerance must stay, it prevents the never-settles bug.
- Chop cadence `Worker.CHOP_SWING_RATE` drives shake **and** sound, so they cannot desync.

## Phalanx rank system (fragile — read before touching)

`_live_rank` is recomputed live from `SpatialGrid.allies_ahead(dir, FILE_LOOK_AHEAD, FILE_HALF_WIDTH)`. Three constants in `Unit.gd` are coupled and must keep this relation: `PHALANX_GAP (0.7) < PHALANX_HOLE_GAP (0.9) < FILE_LOOK_AHEAD/2 (0.95)`.
- Ally within `PHALANX_GAP` ahead → hold position.
- Nearest ally ahead in `(PHALANX_HOLE_GAP, FILE_LOOK_AHEAD]` → real hole, step up to close it **regardless of enemy distance** (`ADVANCE_MAX_DIST` only gates the true front rank, which has nobody ahead). Without this, deep ranks 4–5 m from the enemy could never close and the brick stretched to 1.6 m spacing.
- The unconditional `_enemy_seen_dist <= attack_range + 0.1 → return` must stay, or gap-closing turns into a shove that carries the whole block past the enemy line.
- `FILE_LOOK_AHEAD` is 1.9 (was 1.5): at 1.5 any real spacing above ~0.75 pushed the second rank ahead out of the cone, every unit thought it was front rank, and the whole depth levelled spears.
- **`_phalanx_dir()` order matters:** squad formation course → squad-shared enemy direction (`GameManager.squad_enemy_dir`) → own enemy direction → facing. Per-unit "direction to nearest enemy" skews by 15–20° across a wide squad, which tilts the rank-counting slab and makes side neighbours count as "ahead" (ranks up to 6 in a 4-rank block). Do not widen `FILE_HALF_WIDTH` to compensate — that stalls rank closing at ~1.0 m instead of `PHALANX_GAP`.
- **Gap closing is latched** (`_closing_gap`): it starts when the hole exceeds `PHALANX_HOLE_GAP` and only releases when the unit is within `PHALANX_GAP`. Re-evaluating every frame makes the squad stop at 0.9 m and never reach the nominal 0.7.
- `Spearman._process_can_sleep()` must stay awake while `_spear_down != (_live_rank < PHALANX_FRONT_RANKS)`; `_spear_down` flips inside `_spear_leveled()`, which only `_update_dir_sprite()` calls, so a unit that sleeps on the exact frame its drop delay expires keeps its spear up forever.

## Unit rendering (MultiMesh — the whole army, not just far units)

`GameManager.far_units` (`scripts/FarUnitRenderer.gd`) draws units as slots in shared `MultiMeshInstance3D` nodes instead of one sprite node each. **`perf_config.mm_render_all = true`: every unit goes through it, near ones included** — the old "MultiMesh only past the LOD radius" split was pointless, since the near zone is exactly what fills the screen (810 models = 1130 draw calls that way). The switch stays only for A/B measuring. The name is historical.

- **One bucket per frame strip**, key `"<sheet RID>|<frames>|<pixel_size>"` — *not* per `stat_id × faction × moving`. Sprite centre Y is deliberately excluded from the key (walk bob is mixed into it and would re-bucket a unit every step; it is part of the position, not the geometry).
- **There is no faction tint.** Sides use *different PNG files* (`game_settings.unit_folder`), so the strip already carries the side and the per-strip bucket separates factions by itself. `use_colors` carries something else: **r = frame index / 255, g = mirror flag**, decoded by `shaders/mm_unit_sprite.gdshader`. Mirroring is *not* `Basis.scaled(-1,1,1)` — the transform is pure translation.
- Deliberately **no `custom_data`**: GL Compatibility (this project's renderer) has an open, unfixed reliability bug with it (godot/godot#96503). Confirmed viable by the manual visual spike `qa_mm_spike/Test.tscn` and `qa_mm_anim` (headless can't render pixels, so those checks are eyeballed, not scripted).
- **Transforms are submitted in one `set_buffer()` per bucket per frame, never per instance.** Each `Bucket` keeps a shadow `PackedFloat32Array` (stride 16 = 12 transform floats + 4 colour floats, fixed by `TRANSFORM_3D` + `use_colors`); units write into it and `GameManager._process` (with `process_priority = 1000`, so it runs *after* every unit) calls `far_units.flush()` + `sel_decals.flush()`, which pushes only the buckets marked dirty. Per-instance `set_instance_transform`/`set_instance_color` was the single biggest frame cost in the project: ~1620 RenderingServer calls per frame on 810 spearmen, and switching one `Unit._process` off used to take the march from 33 to 216 FPS while GDScript time barely moved.
- **All writes into the shadow buffer live inside the `Bucket`/`Layer` inner class.** Packed arrays are copy-on-write values: `b.buf[i] = x` from outside the owning class makes the interpreter fetch the array, mutate a *copy* and write it back — kilobytes copied per float. Inside a method of the class that owns the field it is an in-place indexed store. Same rule in `SelectionDecalRenderer`.
- **Two update paths, not one.** `refresh()` re-reads `Unit.sheet_frame()` (strip, frame, mirror, possible bucket migration) and runs on the same cadence as the animation/pose update — `ANIM_EVERY` (3) frames, phase-offset by `_sep_phase`, plus urgent `_pose_dirty`/`_flip_dirty`. Every other frame a visible unit only calls `Slot.move_to()`, which writes three floats and **skips the write entirely if the position is unchanged** (a standing formation never dirties its bucket). `Unit` holds a direct `_far_slot` reference so the fast path costs no dictionary lookup; the reference is refreshed by every `refresh()` because a strip change migrates the slot to another bucket.
- **The walk bob is a number (`Unit._bob`), not a write into the sprite node**, whenever the unit is MultiMesh-only (`_mm_only`): that node is invisible, and writing `position.y` on it only dirtied a transform for nothing. The fallback path (`mm_render_all = false`) still animates the node, and `FarUnitRenderer` re-reads `sheet_frame()[4]` on every `refresh()` so both modes stay correct.
- **The whole visual state is numbers on `Unit`, not properties of a `Sprite3D`.** `_look_tex` / `_look_frame` / `_look_frames` / `_look_px` / `_look_fps` / `_look_loop` / `_anim_name` / `_anim_phase` / `_flip_h_state` / `_sprite_base_y` are the single owner of "what is drawn"; `sheet_frame()` just returns them and touches no node at all. The sprite node is snapshotted **once** (`_look_bind()`, lazily from `_process` or from `sheet_frame()` — a harness can register a unit into the MultiMesh before its first frame) and then *detached* (`_look_detach_node()` → `AnimatedSprite3D.pause()`), because an `AnimatedSprite3D` advances its own animation from an engine internal process **per node, regardless of visibility**. Frames are advanced by `_advance_look_frame()` — two multiplies and a modulo. Writes back into the node (`frame`, `flip_h`, `texture`, `hframes`, `position.y`, `play()`, the spearman's attack-lunge `Tween`) all sit behind `if not _mm_only` and only run in the fallback render mode.
  - `SpriteFrames` is decomposed once per **resource** into `Unit._sheet_table()` (`anim → [atlas, frames, fps, loop]`, keyed by instance id) and cached on the unit as `_look_table`, so changing animation never reaches the node either. Subclasses switch animation through `_set_anim(name)` / `_has_anim(name)` and read `_anim_name` — never `asp.animation` / `asp.play()`.
  - `Spearman` has **no `_process` of its own** any more: directional-pose selection is its override of `_update_sprite_anim()`, which the base already calls on the `ANIM_EVERY` cadence for visible units only. Its 8-sector mirror now goes through `_set_dir_flip()` into the same `_flip_h_state` the renderer reads — previously it wrote `flip_h` straight into the node, bypassing that field, so in MultiMesh mode a levelled-spear rank was drawn with the *stale* base mirror.
  - Consequence for harnesses: **`spr.flip_h` and `asp.animation` are no longer the source of truth** — assert against `unit._flip_h_state` / `unit._anim_name` (that is what `qa_guard` B2/B3/B4 do now).
- **Selection markers are batched the same way** (`SelectionDecalRenderer`, rings + shadows as two `MultiMesh` layers, stride 12). They used to be two extra `MeshInstance3D` children per selected unit — 1620 extra objects on a selected 810-man army, draw calls 1124 → 2744 the moment the player selected. Selecting a marching army now costs ~2 draw calls.
- The transition is driven from `Unit._process` → `_sync_far_render(seen, look_changed)`, gated by the *existing* `_lod_visible()` check (`Unit.gd`). With `mm_render_all` on, registration is never dropped when a unit comes back into view — only the **update frequency** differs (visible: every frame; far: every `ANIM_EVERY`). Combat/movement/FSM run at full fidelity for far units either way; LOD only throttles the picture. The `seen` answer is cached in `Unit._seen` so subclasses (`Spearman`) don't ask `near_view()` a second time.
- **Sleeping units are the trap here.** An IDLE, settled unit calls `set_process(false)` (see "РАСКЛАДКА РАБОТЫ ПО КАДРАМ" in `Unit.gd`) to skip animation upkeep — which also stops `_sync_far_render` from ever running again. A far, sleeping unit (e.g. an idle enemy garrison) would never notice the camera panning back onto it and would stay a flat billboard forever. Fixed by `GameManager._wake_returned_far_units()`, a cheap sweep over only `far_units.registered_units()` (the small far set, not all units) every `FAR_WAKE_CHECK_FRAMES` (15) physics frames, calling the new `Unit.wake_for_lod()` on any that re-entered view. The reverse direction (a near, sleeping unit becoming geometrically far) is not handled and does not need to be — real movement always keeps a unit awake, so the only way to trigger it is a raw `global_position` teleport outside the command/damage system, which normal gameplay never does.
- `FarUnitRenderer.register()`/`unregister()`/`refresh()`/`update_pos()` are bookkeeping-only and don't touch `Node3D` visibility themselves — that's `Unit`'s job. `Unit._exit_tree()` calls `unregister_far()` unconditionally (idempotent no-op if not registered) so death/despawn can't leak a slot. `update_transform()` is kept as an alias of `refresh()` for older callers.
- Covered by `qa_far_render` (module bookkeeping in isolation: registration, slot reuse, bucket growth, idempotent unregister) and `qa_far_wire` (the actual `Unit` ↔ `GameManager` wiring: near/far transitions, sprite visibility, the sleep/wake edge case, cleanup on `queue_free()` and on death).

## Scaling to 15,000 units — Phase 0 (Aug 12 2026)

Start of a phased rework toward 15k units at 100–120 FPS. Phase 0 is hygiene only: no architecture changed, `Unit`/`Building`/autoloads/public APIs untouched.

- **The GDScript floor is measured, not guessed** (`qa_soa_floor`, N = 15000, best of 40 runs): pure SoA position integration **0.86 ms**; a realistic SoA step with state + timers **2.68 ms**; a flat-grid full rebuild **3.53 ms**; a throttled neighbour scan **0.73 ms**; and the same arithmetic done as **`Node3D` array + method call — 12.34 ms (0.82 µs/unit)**. That last row is the current architecture with the logic emptied out, and it alone busts the 8.33 ms budget of 120 FPS. **This is the proof that node elimination is mandatory, not an optimisation** — no amount of tuning inside `Unit` can beat 0.82 µs/unit of pure dispatch.
- **`GameManager.unregister_unit` was the project's only true O(n²)** — `Array.erase()` is a linear search plus a tail shift. Now swap-remove via `Unit._live_idx` (a hint, with a `find` fallback if it doesn't match). Measured (`qa_soa_floor/Unreg.tscn`, 6000 spawned then freed, total free time): death order *forward* 183 → 160 ms, *shuffled* (closest to a real battle) 305 → **196 ms**, *reverse* 392 → **162 ms**. Note the new numbers are flat across orders — that is the O(1) property; the residual ~160 ms is node destruction itself. Registry order is no longer birth order, which nothing depends on (shard iteration is by index, and `erase` already reshuffled shards by one).
- **Squad corridors expired in lockstep.** `_recalc_corridor` is cheap per squad, but every squad was created in the same frame, so all 300 expired on the same frame — the profiler read `squad_corridor` 11.9 % at **12.0 ms/call**, which is a ~144 ms spike every 12th frame averaged out. Fixed by jittering the **first** TTL only (`1 + (sid * 37) % CORRIDOR_TTL_MS`, from the squad id so runs stay reproducible); phases then hold by themselves. `CORRIDOR_BUDGET` (64/frame) is a second fence for mass simultaneous births. Result: 11.9 % → **4.9 %**. What remains is honest per-object cost (50 `global_position` reads per squad) that Phase 1 removes by moving positions into SoA.
- **`SpatialGrid` no longer calls a method inside its neighbour loops.** `u.is_dead()` was a GDScript call whose whole body is `state == State.DEAD`; all six scans now read the field and cast to `Unit` once (three of them were duck-typing `n.faction` on `Node3D`, which is both slower and would break silently if anything but a unit entered the grid — only `Unit`/`Worker` insert).
- **Arrows come from a pool** (`GameManager.spawn_arrow` / `recycle_arrow`, cap `ARROW_POOL_MAX` 512). A shot used to cost two nodes + a `QuadMesh` + a `ShaderMaterial` + a `SceneTreeTimer`, all discarded a second later. A spent arrow now goes invisible, stops processing and returns to the pool **while staying in the tree** — a detached node would be an orphan (which `qa_arrow/Perf` prints as a leak) and would outlive the scene owned by nobody. Lifetime is a **field ticked in `_process`**, not a `SceneTreeTimer`: the timer was both an object per shot and incompatible with reuse (its `timeout → queue_free` from a previous life would kill the arrow mid-flight). Consequence: a stuck arrow must **keep** `_process` on — that is where its lifetime is counted. `_despawn()` also nulls `shooter`, or the pool would hold a freed unit. Covered by `qa_arrow/Pool.tscn` (14 checks incl. damage landing from a thrice-reused arrow).

### Vegetation is drawn by MultiMesh (`scripts/VegetationRenderer.gd` + `shaders/veg_multimesh.gdshader`)

- **Each plant carried its own `ShaderMaterial`**, because per-plant wind phase and cycle live in shader uniforms (`BillboardUtil.make_wind_material`) — and without that spread the forest sways as one body. A private material means no batching at all: one draw call per plant. Measured on an **empty map with no army, whole map in frame** (`qa_veg/Test.tscn`, RTX 4070): **1806 draw calls, 6.47 ms/frame**. The spread now rides in the instance colour (`r` = phase 0..1, `g` = cycle normalised between `WIND_CYCLE_MIN/MAX`), exactly the `use_colors` trick already proven for units — **385 draw calls, 1.29 ms/frame**. Node count on a fresh map 8948 → 6918, `MeshInstance3D` 2330 → **448**.
- **This is invisible in `qa_march_perf`** (131 draw calls at 810 marching men) because the gameplay camera there is zoomed in and the forest is out of frame. A 15k army is commanded zoomed **out**, which is exactly when all 1800 draw calls arrive — measure decoration with `qa_veg`, not with the march scene.
- **Windowed harnesses must disable V-Sync or they measure the monitor.** `qa_veg` first reported a flat 75 FPS both before *and* after draw calls fell 4.5×. `Performance.TIME_FPS` also returned nonsense (1) with vsync off, and `TIME_PROCESS` read 0.00 ms on a full map. Frame time is now taken from `Time.get_ticks_usec()` across N frames — trust the clock, not the engine's monitors.
- **Only trees and decorative bushes moved.** Gold/stone/food keep their nodes: they carry crop rects, the shimmer overlay and highlight children, and there are far fewer of them.
- **The `StaticBody3D` + `CollisionShape3D` on every `ResourceNode` stays and is NOT dead weight** — it is the pick target for right-click gathering (`SelectionManager` adds `LAYER_RESOURCES` to the mask only when a worker is selected, and `Main._update_hover_cursor` reads the same). A tree's collider is deliberately the whole 1.35 × 4.8 m crown. Static bodies are also not a frame cost: `PHYSICS_3D_ACTIVE_OBJECTS` reads 0 in game. Moving resource picking onto the grid (as units already did) is possible but changes click semantics, so it belongs in a deliberate pass, not here.
- **A tree's shake now moves its MultiMesh instance, not `_visual_root`.** `_visual_root.position` stays zero forever for sprite trees, so anything asserting on it silently reads 0 — that is exactly how `qa_tree` B5 went red (same class of stale assertion as `qa_fix` #1 with `spr.position.y`). `ResourceNode._veg_slot` is the owner of that number now.
- **`Slot.move_to` uses an absolute epsilon, never `Vector3.is_equal_approx`.** That helper's tolerance scales with the coordinate: on a tree 100 m from origin it is ~1 mm, so the decaying chop shake stopped short and left the trunk permanently offset (`qa_veg` D2 caught 0.0008 m). Same absolute `MOVE_EPS_SQ` rule as `FarUnitRenderer.Slot`.
- **Planting is deferred** (`call_deferred("_plant_tree_now")`) for the same reason trunk registration is: a `ResourceNode`'s position is assigned *after* `add_child`, so `_ready` still sees the origin. With no node of its own to be dragged along later, the world point has to be right on the first write.
- **`GameManager.veg.clear_bookkeeping()` is called from `Main._ready()`, right after `_world` is built — not from `start_game()`.** The forest and bushes are planted from `_setup_terrain`/`_setup_environment`, i.e. *before* `start_game()`; clearing after planting would leave the previous map's buckets in the world as a second set.
- New harnesses: **`qa_veg`** (`SelfTest.tscn` 17 headless checks that the drawn geometry equals what the old node produced — instance scale = `TREE_HEIGHT`, quad centre at +2.5 m, bucket mesh = unit-height quad with the *frame* aspect, wind spread still per-plant, chop shake returning exactly, stump releasing the slot; `Test.tscn` the windowed draw-call measurement; `Shot.tscn` a screenshot), **`qa_census`** (what the map is actually made of, by class and by owner), **`qa_soa_floor`** (the GDScript floor + `Unreg.tscn`).

**Pre-existing reds confirmed unchanged by Phase 0** (verified by running the same harnesses on a stashed baseline, failure lists identical line for line): `qa_formation` B1/B2, `qa_spear` C9/C11/C12/C14, `qa_garrison` 9 of 13. These are about the castle-garrison chain and ally pass-through, and were red before this work — do not attribute them to it.

## Scaling to 15,000 units — Phase 1: the SoA core (`scripts/army/ArmySoA.gd`)

Per-unit data that batch loops need now lives in flat `PackedFloat32Array`/`PackedInt32Array` columns; a unit knows only its **row number** (`Unit._soa`). `Unit` and every public API are untouched — `SelectionManager`, `HUD`, `Castle`, `EnemyAI` cannot tell the difference.

- **`Unit` was deliberately NOT turned into properties over the SoA.** Measured (`qa_soa_floor` E1/E2, 15000 objects, two reads each): plain object fields **0.16 µs**, `get`/`set` properties backed by a SoA row **0.42 µs** — 2.6× worse. While the nodes are alive and the logic walks *objects*, such a façade is a guaranteed loss. The rule that fell out of this: **the unit's own fields stay fields; the row is written through at the same points the unit already changed the value; only BATCH loops read the row.** In Phase 4, when the node disappears, the direction reverses — the row becomes the only storage and a façade object is materialised on demand for cold paths (selection, panel, garrison), where 0.42 µs means nothing.
- **Nothing may be added to the per-unit per-frame path — not even a comparison.** Two attempts had each unit write its own row (first on the grid's 20 cm cadence, then on its own 1 m threshold). Both were rejected by measurement: `grid_update` 5.8 % → 8.4 %, whole 15000 march 59.9 → 62.3 ms. The 1 m threshold cut the *writes* fivefold and barely helped, which is the actual lesson — the cost was not the write but the six field reads and one compare that ran on **every** unit **every** tick: +0.44 µs/call ≈ **+2.2 ms/frame at 15000**.
- **Positions are therefore harvested per squad, not pushed per unit** (`ArmySoA.harvest_squad`, called from `_recalc_corridor`, i.e. once per `CORRIDOR_TTL_MS` per squad). That member walk already existed before the SoA, so no new pass over the army was introduced. The whole loop lives **inside** `ArmySoA` for two reasons already paid for once in this project: writes into `Packed*Array` must happen inside the owning class (from outside, copy-on-write copies the whole array — see `FarUnitRenderer.Bucket`), and `Unit.State.DEAD` / `Unit.AGGRO_RADIUS` / `Unit.INTERCEPT_MARGIN` are **runtime lookups into another script**, not inlined constants, so they are passed in as arguments instead of being read inside a per-member loop.
- **`Unit` builds its flag word with literal bit shifts, not `ArmySoA.F_*`,** for the same lookup reason. `qa_army` A1 asserts the two sets of bit numbers still agree — that check is the only thing keeping the duplication honest.
- **A column that lies is worse than a missing column.** Dropping `st[i] = u.state` from the harvest ("state is pushed by event in `_die`") looked like a free saving; `qa_army` C3 immediately caught all 60 marching units still reading `IDLE` in their rows, because only *death* was event-pushed and `IDLE↔MOVING↔ATTACKING` was pushed by nothing. `atk_range` genuinely is event-only (`_soa_push_stats` at spawn and on upgrades) and is correctly absent from the harvest.
- **`squad_centroid` deliberately still reads node positions.** Reading rows instead was cheaper but made the veterancy star lag the block by ~0.2 m (`qa_vet` #4 caught it), and the benchmark showed no gain at all — stars move every `STAR_UPDATE_FRAMES`. Rows become the right source here only once they are refreshed every frame, i.e. in Phase 2.
- **Honest cost of Phase 1: the 15000 march tick went 59.9 → 61.7 ms (+3 %)**, 5000 unchanged (18.1 → 18.2), visual and leaks unchanged. The store buys nothing measurable *yet* — by construction, since its readers are Phase 2 (the flat grid rebuilt from these columns, replacing ~5.8 ms/frame of `unit_grid.update()` calls) and Phase 3 (batch combat). Reported as a down payment, not as a win.
- Covered by **`qa_army/SelfTest.tscn`** (15 checks: flag-bit agreement, row allocation/uniqueness, position/state/health agreeing with the objects, damage and death landing in the row immediately, rows returned and reused without leaking the previous tenant's numbers, squad id).
- **`qa_vet` is 43/43.**

## Scaling to 15,000 units — Phase 2: the flat grid

`SpatialGrid`'s `Dictionary<Vector2i, Array[Node3D]>` is gone. `scripts/army/ArmySoA.gd` now owns a flat grid over the same columns, and `SpatialGrid.gd` is a one-line-per-method **façade** that keeps every existing caller (`Unit`, `Worker`, `Castle`, `Arrow`, `SelectionManager`, `GameManager`, harnesses) working untouched.

- **Cells are linked lists of row numbers, not prefix-summed buckets.** The textbook counting-sort layout (`counts` → prefix sum → `items`) needs a pass over **every cell** for the prefix sum. There are tens of thousands of cells and a GDScript array loop costs ~0.05 µs/step — 260k cells would be **13 ms a frame**, more than the grid saves. A linked list (`head[cell]` → `next[row]`) costs two array writes per unit and no cell pass at all, and clearing is `head.fill(-1)`, a memset inside the engine rather than an interpreter loop.
- **The coarse faction-presence layer was deleted and had to be restored — the measurement is the reason.** A 1 m cell is right for *short* questions (separation 0.29 m, enemy-line blocking 0.55 m: two or three cells). But "is there any enemy nearby" is asked at the **squad's attention radius, ~22 m**, i.e. ~2000 metre-cells each walked as a list. On a map with no enemies at all that is pure waste: `squad_corridor` went 6.0 % → **11.9 %** and `mb_enemyblock` 0.38 → **1.24 µs/call**. The 16 m per-faction count grid is back (rebuilt in the same pass, one increment per unit), `enemy_near` answers from it alone (conservatively, exactly as before), and it now also pre-filters `best_enemy` and `nearest_enemy_offset` — which the *old* code never did, so an archer's 20 m target scan used to run in full over empty ground.
- **Grid bounds are computed from the rows, not from the map.** Harnesses place units 300–500 m from map centre (`qa_settle`, `qa_formation`); a grid stretched over `map_lim` would drop them or pile them into one edge cell, making the whole harness each other's neighbours. Cell size doubles only if the bounding box would otherwise exceed `MAX_CELLS`.
- **The bounds pass runs only when it must.** Walking every row for min/max costs about as much as the layout itself, and it is almost never needed — units are clamped to the map, so once the bounds fit they keep fitting. `rebuild_grid()` lays out with the previous bounds and only recomputes when `_fill_grid()` reports someone outside. Steady state is **one pass, not two** (5.9 → measured saving of ~0.6 ms).
- **Per-unit grid bookkeeping is gone.** `Unit.tick_physics` no longer calls `unit_grid.update(self)` (key construction + two dictionaries); it writes its pose into the columns with a single `army.write_pose()` and the grid is rebuilt whole, once per frame, *before* the army walk. The "did I move 20 cm" test was dropped deliberately: Phase 1 measured that a couple of field reads plus one compare costs +2.2 ms/frame at 15000 — the condition was dearer than the unconditional write.
- **Semantics changed in one visible way, for the better.** Scans now see a consistent snapshot taken at the start of the frame. Previously the order was sequential — a unit earlier in the registry moved first and later ones saw its *new* position — so separation depended on registry order. Simultaneity removes that; the lag is one frame, 6.7 cm at 4 m/s against a 0.29 m separation threshold.
- **Measured (15000 marching, headless, light meter):** whole tick **59.9 (Phase 0) → 61.7 (Phase 1) → 58.1 ms**; `sep_overlap` 5.36 → **3.71 µs/call** (share 13.1 % → 9.9 %), `grid_update` 1.20 → **1.04**, `mv_intercept` 0.91 → **0.52**, `squad_corridor` 6.0 % → **4.1 %**. The new `grid_rebuild` line costs **5.9 ms/frame** — it is the price of the whole-army rebuild and now the largest item after `process_move`.
- **Known next step, deliberately not taken here:** making the grid persistent with a doubly-linked list (unlink/relink only units whose cell changed) would remove the 5.9 ms rebuild in exchange for per-mover bookkeeping and more mutable state. It also gives back the order-dependent semantics. Left for Phase 3, where `process_move` — still **50 % of the tick** — is the actual target.
- Gate: `qa_phalanx`, `qa_crowd` 8/8, `qa_settle` 17/17, `qa_squad` 46/46, `qa_guard` 46/46, `qa_vet` 43/43, `qa_target_lock` 14/14, `qa_combat_lock` 5/5, `qa_aggro` 7/7, `qa_leash` 4/4, `qa_archer_retarget` 3/3, `qa_approach_intercept` 4/4, `qa_army` 15/15, `qa_veg` 17/17, `qa_arrow/Pool` 14/14, `qa_tree` 21/21 all green; leaks +0/+0/0. `qa_spear` 4/45 and `qa_formation` 2/7 stay red with a **line-for-line identical** failure list to the pre-Phase-0 baseline.

## Scaling to 15,000 units — Phase 3: batch separation, and what was NOT batched

- **Ally-overlap resolution is now one pass over the columns** (`ArmySoA.batch_separation`, called from `GameManager._physics_process` **after** the army walk). It used to be `Unit._resolve_overlap` per unit on its own timer: 2500 calls/frame, each hopping `GameManager.unit_grid` (façade) → `ArmySoA.ally_overlap`, then reading `map_lim_*`, `water_active`, `get_terrain_height` and writing `global_position`. Measured 3.71 µs/call ≈ **9.3 ms/frame at 15000**; the batch pass costs **4.0 ms** for the whole army. The rule is unchanged to the letter (monotone, outward only; the component *against* course is cut for a unit under orders; no push past the map edge or into water) — only the neighbour scan is inlined and the timer moved into a column (`sep_t`). Going outside now happens **only for units actually pushed** (terrain height, water test, `wake_for_lod`).
- **It runs after the walk on purpose**: by then everyone who marched has moved, so the correction is computed from the frame's final positions rather than a mix of old and new.
- **Result: 5000 marching now fits the budget** — 18.1 ms (Phase 0) → **14.93 ms, 90 % of the 16.6 ms physics budget, PASS**. 15000 marching: 59.9 → **52.7 ms**.
- **New harness `qa_mass_battle`** — the missing half of the picture. `qa_mass_perf` places no enemies at all (`process_attack` reads 0.0 % there), so combat cost was never measured. Two equal armies are set facing each other and ordered in; the tick is sampled three times (closing, clash, grind). Same contract as the other mass harnesses: headless, silent, one table at the end. Measured: **5000 → 19.5 / 22.9 / 23.6 ms**, **15000 → 66.9 / 62.7 / 62.2 ms** against 52.7 ms marching, i.e. **combat adds roughly 10 ms at 15000**, not a multiple.
- **Movement stepping and the attack FSM were deliberately NOT converted**, and the reason is the measurement, not the effort. Of `_move_blocked`'s cost, the two largest parts cannot be removed by batching: `mb_commit` (~0.96 µs/unit) *is* the write to the node's `global_position`, which every consumer still reads (rendering, selection, fog, arrows) and which only disappears with the nodes in Phase 4; and `mb_trunk` (~1.47 µs/unit) is the trunk-registry query, which stays a query wherever the loop lives. What batching would actually remove is the per-unit dispatch and the repeated `GameManager.` lookups — worth a few ms, against a rewrite touching target lock, march resume, disengage, sprint, phalanx advance and stuck detection all at once. Converting it while `qa_target_lock`, `qa_combat_lock`, `qa_spear`, `qa_settle` and `qa_formation` stay green is a phase of its own; it is the right first move of Phase 4, when the node write disappears and the whole step becomes pure column arithmetic.
- Gate: `qa_combat_lock` 5/5, `qa_target_lock` 14/14, `qa_archer_retarget` 3/3, `qa_phalanx`, `qa_crowd` 8/8, `qa_settle` 17/17, `qa_squad` 46/46, `qa_guard` 46/46, `qa_vet` 43/43, `qa_aggro` 7/7, `qa_leash` 4/4, `qa_disengage` 11/11, `qa_approach_intercept` 4/4, `qa_army` 15/15, `qa_veg` 17/17, `qa_arrow/Pool` 14/14, `qa_tree` 21/21 green; smoke and leaks clean. `qa_spear` 4/45 and `qa_formation` 2/7 red with the same line-for-line failure list as the pre-Phase-0 baseline.

### Cumulative measurement across the four phases (15000 marching, headless, light meter)

| | tick | 5000 tick | notes |
|---|---|---|---|
| before | 65.0 ms | 18.1 ms | |
| Phase 0 | 59.9 | 18.1 | vegetation 1806 → 385 draw calls; army-death unregister O(n²) → O(1) |
| Phase 1 | 61.7 | 18.2 | SoA store built; +3 % is the down payment |
| Phase 2 | 58.1 | 18.0 | flat grid; `sep_overlap` 5.36 → 3.71 µs/call |
| Phase 3 | **52.7** | **14.9 (PASS)** | batch separation 9.3 → 4.0 ms/frame |

## Scaling to 15,000 units — Phase 4: what a node actually costs

**The single most important number of the whole effort.** Bench D ("array of `Node3D` + method call") was quoted for three phases as "the nodes alone cost 10–12 ms, so they must go". That was measured with a body that *also* read and wrote `global_position`, so it conflated three different things. `qa_soa_floor` F1–F4 separates them at 15000:

| | µs total | µs/unit | what it adds |
|---|---|---|---|
| F1. columns only, no objects | 712 | 0.05 | — |
| F2. + object method call, transform untouched | 4105 | 0.27 | **dispatch: 3.4 ms** |
| F3. + `position` write (local) | 5620 | 0.37 | local transform: 1.5 ms |
| F4. + `global_position` write (world) | 7526 | 0.50 | world transform: 3.4 ms |

Three consequences, all acted on:

- **`global_position = np` → `position = np` in the commit path.** The numbers are identical — everything on the map lives under `World`, whose transform is zero and never changes (`Main._ready`) — but the world setter first converts into the parent's frame. Worth **1.9 ms/frame at 15000**. The premise is *checked*, not assumed: `Unit._local_xform` compares the parent's `global_transform` against the identity, deferred to after `add_child` (same ordering trap as trunk registration and tree planting). A harness that parents a unit somewhere odd falls back to the world setter automatically.
- **`tick_visual` takes the position from the row, not from the node.** It was reading `global_position` for every unit in every *render* frame and feeding it to fog, LOD and the MultiMesh slot. The physics tick of the same frame already wrote that number into the columns. Units with `F_POS_VALID` clear (garrison, never ticked) still ask the node.
- **`Unit.sync_row()` for anything that moves a unit outside the tick.** `Castle.release_unit` teleports a soldier out of the gate; with the grid and the picture both reading columns now, the row has to be corrected by hand there.

**Measured: 15000 marching 52.7 → 48.6 ms; 5000 stays PASS at 14.8 ms. Draw calls at 810 marching-and-selected: 89 (131 before Phase 0), 93 FPS windowed (68–80 before).**

### Full node elimination: what it would buy, and why it is not a phase

Goals 1–4 of the Phase 4 brief (soldiers with no `Node3D`/`Sprite3D` at all, lazy `Unit` façades materialised on click, movement and combat as pure column arithmetic) were **not** delivered. The reason is the table above plus a count of the blast radius, and both are worth recording before anyone attempts it again:

- **The prize is smaller than it looked.** Removing the node removes dispatch (3.4 ms) and the world-transform write (now already down to 1.5 ms as a local write) — about **5 ms out of 48.6**, roughly 10 %. It does *not* remove the trunk query, the grid rebuild, the neighbour scans or the movement arithmetic, which is where the rest of the frame is.
- **The blast radius is the whole object model.** `Unit` is referenced ~150 times across `SelectionManager` (38), `GameManager` (48), `HUD` (31), `Castle` (13), `EnemyAI` (9), plus `Building`, `Arrow`, `FogOfWar`, `SelectionDecalRenderer`, and **~60 QA harnesses** that all do `Spearman.new()` → `world_add` → `u.global_position = …` → `u.command_move(…)`. Lazy façades mean every one of those sites has to distinguish "a soldier that exists" from "a soldier object I asked for", including `squads["members"]`, `FarUnitRenderer`'s per-`Unit` slot dictionary, and the `died` signal wiring.
- **Therefore it is a rewrite of the game's object model, not an optimisation pass**, and it cannot be landed as one verified step: the gate would be red everywhere at once with no way to bisect. The honest sequence, if it is ever taken: (1) make `_move_blocked` a batch pass over the columns while the nodes still exist — that is where the remaining `process_move` share lives and it is independently testable; (2) replace the per-unit `Sprite3D` with a per-*type* look table so `_look_bind` needs no node; (3) only then swap `squads`/selection/HUD onto row indices with `Unit` created on demand.
- **The `Sprite3D` per soldier is the one cheap part of goal 1** and is worth doing on its own: it is already invisible and detached from its own animation (`_look_detach_node`), and everything it holds is per-type texture data that `_dir_textures` already caches. Removing it drops 15000 nodes without touching a single call site outside the visual builders.

## Final tally — five phases (15000 unless stated)

| | march tick | 5000 march | battle tick | draw calls @810 | FPS @810 | decoration frame |
|---|---|---|---|---|---|---|
| before | 65.0 ms | 18.1 ms | — | 131 | 68–80 | 6.47 ms / 1806 calls |
| Phase 0 | 59.9 | 18.1 | — | — | — | **1.29 ms / 385 calls** |
| Phase 1 | 61.7 | 18.2 | — | — | — | — |
| Phase 2 | 58.1 | 18.0 | — | — | — | — |
| Phase 3 | 52.7 | **14.9 PASS** | 62.2–66.9 | — | — | — |
| Phase 4 | **48.6** | **14.8 PASS** | 62.8–66.8 | **89** | **93** | — |

**Combat did not improve in Phase 4 and that is expected, not a miss.** The phase's win is in the movement commit (`position` instead of `global_position`), and a unit standing in a melee does not commit a step — it fights in place. The gap is now march 48.6 vs battle ~63 ms, i.e. **combat costs ~14 ms on top of movement at 15000**, and that is where the next work belongs: `_process_attack`, target selection and damage application are still per-object, and `qa_mass_battle` is the harness that will show whether batching them pays.

5000 units fit the 16.6 ms physics budget. 15000 do not: the frame is still ~49 ms of which `process_move` is ~60 %, and closing that gap needs the batch step pass described above, after which the remaining ceiling is GDScript itself (`qa_soa_floor` B: the *minimum* realistic per-unit step is 2.6 ms at 15000, before any of the game's actual rules).

## Bug pass after the scaling phases (Aug 12 2026)

- **Workers lost their SoA row, and it was a regression from the scaling work.** `Worker` **overrides `tick_physics`** and in the `GATHERING` / `BUILDING` / `RETURNING` branches never reaches `super()` — where the only `write_pose` lives. Those branches called `GameManager.unit_grid.update(self)`, which Phase 2 turned into a **no-op**. While only neighbours read the columns this was invisible; once Phase 4 made `tick_visual` read them, the bug appeared in full: the logic walked to the tree while the **sprite stayed at the last written point** (the castle), hammering at thin air, then "teleported" when the worker returned to an ordinary state — that teleport was simply the first row write in minutes. Fixed with `_sync_soa_row()` in all three branches. **Rule this leaves behind: any subclass that overrides `tick_physics` owns its row.** Covered by `qa_army` G1–G3.
- **The garrison softlock was pure geometry, and it explains two long-standing red harnesses.** Units are ordered to `_gate_position()` = castle centre + `GATE_DISTANCE` (**6.5 m**), while admission was tested as distance to the castle **centre** against `GARRISON_ENTER_RADIUS` (**5.0 m**). 6.5 > 5.0 always, so a unit standing exactly where it was told could never be admitted: `all_in` stayed false, and the watchdog below saw `IDLE` and **re-issued the move order every frame** — the "marching on the spot" and "the squad ignores every new order" from the report. Now the distance is measured **to the gate point**, which is what "reached the entrance" means and no longer depends on `GATE_DISTANCE`. Result: `qa_garrison` **9 red → 13/13**, and `qa_spear` **4 red → 46/46** (its C9–C14 were the same garrison chain). The two reds documented for months as "pre-existing, not a regression" were this one bug.
- **The watchdog also had to stop overriding the player.** Its condition was "IDLE **or** not retreating", but an ordinary player order clears retreat (`command_move` without `keep_retreat`) — so the castle dragged the squad back to the gate the very next frame. Now: *not retreating and doing something* = the player took over, the garrison request is cancelled; *IDLE* = knocked off course, re-issue.
- **Formation preview: recomputed per mouse event, drawn per unit.** `_update_formation_preview` ran on every `InputEventMouseMotion` — mouse motion arrives at the mouse's polling rate, 5–10 events per frame — and each run did a physics ray, a slot for every selected unit, `camera.unproject_position` per unit and **two canvas primitives per unit**. Hence 60 → 29 FPS while dragging. Two fixes: events are coalesced to **one recompute per rendered frame** (`SelectionManager._process`, skipped entirely if the cursor moved < 2 px), and `FormationPreview._draw` now emits the whole formation as **one `canvas_item_add_triangle_array` plus one `draw_multiline`** instead of 2N primitives, with the rotation sine/cosine hoisted out of the loop. Picture is identical to the pixel.
- **`monk` was a hire button with no scene behind it.** `Monk.gd` is complete, the config lists it and the Castle offers it, but `scenes/units/Monk.tscn` did not exist and was not in `Building.PRELOAD_SCENES` — so the order was **paid for**, reached `_spawn_one` and died on `push_error`. Added the scene (root `Node3D`, matching `Unit`) and the registry entry; `queue_unit` now refuses anything `can_spawn()` rejects **before** `ResourceManager.spend()`, and `_spawn_one` degrades to a single warning per type instead of an error per soldier.
- **Missing HUD icons warned on every panel rebuild.** `_icon_texture` already checked `ResourceLoader.exists()`, but the warning fired per call — i.e. on every selection — for `Pawn_human.png`, `Warrior_human.png`, `Archer_human.png`, `Lancer_human.png`, which are simply absent from `assets/ui/icons_units_human/`. Now: warn **once per path** and return a procedurally built placeholder (framed square with a diagonal) so the layout keeps its slot. The diagnostic value the warning was added for is preserved; only the repetition is gone.
- **Veterancy stars outlived their squads.** The star is a world-parented node (not a child of a soldier), and both places that dropped a squad did a bare `squads.erase()` — so the node stayed on the map forever. Both paths now go through `_disband_squad()`, which frees the star first; `reset_squads()` sweeps them too. This covers both cases in the report (reward taken, and reward pending but never clicked — it is the same node).
- **Stars now follow instead of teleporting.** The heavy part (walking the squad, centroid of the **living** members) still runs every `STAR_UPDATE_FRAMES`, but between recomputes the star lerps toward the stored goal every frame (`STAR_FOLLOW`), so a marching squad no longer makes it jump every sixth frame. Consequence for harnesses: the star never *exactly* equals the centroid — `qa_vet` #4 now settles first and allows 10 cm.
- **V-Sync toggle in the pause menu** (`HUD._add_vsync_toggle`). Deliberately **not** persisted: it is a session-scoped engineering switch, not a game option. It also sets `Engine.max_fps = 0`, because clearing vsync alone does not lift the cap.
- **Unit scenes are `CharacterBody3D` while `Unit extends Node3D` — checked, and it is NOT a performance problem.** All four `scenes/units/*.tscn` still declare a physics body, so every soldier spawned *in the real game* has one, while every mass harness (`Spearman.new()`) has none — which looked like a hole big enough to invalidate all the scaling numbers. Measured directly (`qa_soa_floor/Bodies.tscn`, 3000 units, scene vs `new()`): **0 active bodies both ways, tick 13.66 vs 13.50 ms — 1 %, i.e. noise.** A body that never calls `move_and_slide` sleeps and `PhysicsServer3D` does not tick it; the old "5.7 µs/unit" figure was for *active* bodies. Left alone: changing scene root types risks the `.tscn` load path for no measured gain. Worth knowing before someone else "discovers" it.

## Resource art pass (Aug 12 2026) — gold and stone

- **The additive gold aura is OFF again** (`ResourceNode.GOLD_SHIMMER = false`, owner's call, reversing the Aug 7 decision). On grass it read as "a blurred yellow blob under the ore", and pieces standing overlapped summed their glows. **Honest consequence: gold now has no sparkle at all** — the animation exists *only* as the separate `Gold Stone N_Highlight.png` strip (768×128, 6 frames); the base `Gold Stone N.png` is a single 128×128 frame with no "native animation inside the sprite". Bringing shimmer back without an overlay means drawing the base sprite as a frame strip, after which it rides the ordinary per-frame path like trees and bushes.
- **`cyl_billboard` and `veg_multimesh` now sample `filter_nearest_mipmap`, not `filter_linear_mipmap`.** This was the direct cause of "pixels smear and go mushy": all the art is pixel art, units were already drawn with `filter_nearest` (`mm_unit_sprite`) and looked crisp, while everything through the billboard shader — rocks, ore, trees, buildings — was being smoothed. Mipmaps are kept, or the distant forest shimmers when the camera moves.
- **Ore quads are no longer stretched to a fixed world height.** `lump_h = 2.5 * size_scale` gave every piece the same metres regardless of how many pixels were drawn — a `Rock*.png` crop of ~45 px was blown up to 2.5–4 m. Size now starts from the source pixels (`FRAME_METRES_*` = world size of a full frame) and is only pulled toward a per-class target within `ZOOM_MIN..ZOOM_MAX`. **Why the clamp exists:** pure crop-proportional sizing was tried first and the variants fill their canvas from ~6 % to ~45 %, so a normal nugget ended up next to one-pixel specks — a 10:1 spread. `PIECE_TARGET_H` is the single knob for "make all ore bigger/smaller".
- **Cluster layout is a fixed template, not a random scatter** (`Main.CLUSTER_LAYOUTS`). Pieces used to be thrown onto a disc with a deliberate *overlap* (`PIECE_MIN_GAP` 0.42 m, smaller than their own radii) plus an extra squeeze on gold — hence "a solid heap". Now three hand-authored compositions (core of big pieces, mids at the sides, small ones at the edges) are placed with rotation and an X mirror; distances are set so pieces touch but never stack. `PIECE_CLASSES`' random `jitter` is gone with it: a fractional random scale is exactly the "procedural stretching" that resamples pixel art unevenly, and the variety comes from 3 classes × 4–6 variants instead. `GOLD_SPREAD_TIGHTEN` / `GOLD_GAP_TIGHTEN` / `PIECE_MIN_GAP` no longer apply — the single remaining knob is `LAYOUT_SPAN_*`.
- **Unit card icons pointed at files that do not exist.** `tooltip_config` listed `res://assets/ui/icons_units_human/*.png` (only `Attacks_human.png` and `Deffens_humans.png` are in that folder), while the castle and squad buttons used `HUD.UNIT_ICONS` and rendered fine — so the same unit had a working icon on a button and a grey placeholder in its tooltip. Paths repointed at `UNIT_ICONS`' files, and `_unit_card` now falls back to `UNIT_ICONS` when the configured path **does not resolve**, not only when it is empty: two lists of paths to the same pictures will drift again, and when they do it should degrade to the working icon rather than to the placeholder.
- Harness notes: `qa_ui9`'s three shimmer checks asserted the aura is **on** and were inverted with the feature (same reversal history as in Aug 7 — read the comment there before flipping them a third time); `qa_fix` #5 looked for triangles by the name of a function that batching removed.

## Resource clusters, the hard click contract, and the gather auto-cycle (Aug 13 2026)

- **A cluster is now a real entity, not just a composition on screen.** `ResourceNode.cluster_id` + the `Main.res_clusters` registry (`id → {type, center, radius, half}`), filled by `_spawn_resource_cluster` from the pieces it **actually placed** (water and reserved-pad rejects drop out, so a pile at the shore is honestly smaller and off-centre). Cleared in `start_game()` alongside `clear_trunks()` — ids from the previous match would otherwise stay valid and a worker would look for a neighbour in a pile that no longer exists.
- **SUPERSEDED Aug 14 2026 — piece count no longer sets the stock at all.** The paragraph below described stock as the sum of `PIECE_CLASSES.amount` over the layout; that coupling is gone (see "The ore deposit is one object"), and `amount` was deleted from `PIECE_CLASSES` rather than left unused. What still stands is the layout itself and its clearance rule.
- **Ore piles hold twice as many PIECES.** All three `CLUSTER_LAYOUTS` went 8 → 16 pieces with the class composition doubled (2 big + 3 mid + 3 small → 4+6+6, "Гряда" is 4+7+5). Owner's explicit call: *don't touch gather speed, add more gold*. The composition's span grew only ~5.2×2.1 m → ~5.7×2.6 m — the extra pieces went into a second and third **row**, not outward; doubling both axes would have made a pile cover half a clearing. The pairwise rule is unchanged and now **checked** (`qa_res2` A3): a neighbour's centre must not fall inside a piece's silhouette (≈`0.62 × scale`). Two template coordinates had to move by 5–8 cm to satisfy it.
- **`_pick_at` had no camera-angle correction for resources, and that was the whole "clicked a rock, the worker went to chop a bush" bug.** Units have had `unit_slack` since forever; ore had nothing. The camera is fixed at 45°, so aiming at a drawn nugget puts the **ground point** roughly its own height *behind* it — aiming at the top of a big piece is ~2 m behind. A tree standing there scored 0 (its ground disc is a flat 1.35 m) while the rock scored 0.69, and the tree won. Fixed by **shifting** the candidate's disc along the view lean (`anchor += lean * pick_body_h()`), never by growing it: growing it would make a small chip a fat target that steals its neighbours' clicks, which is the same disease. `ResourceNode.pick_body_h()` returns `0.64 * size_scale` for ore and **0 for wood** (a tree's collider already covers its whole 4.8 m sprite on purpose, so a click on any branch sends a worker to chop).
- **`_pick_rank` now separates ore (1) from wood (2).** They shared rank 1 and ties were broken by "smaller radius wins" — sound in general, wrong here, because a tree's disc is a constant 1.35 m while an ore piece's is `0.85 × size_scale` (0.53–1.36 m). Ore is generated exactly where the forest is, so the two are in contention constantly; ore wins now. The reverse case is safe by construction — aiming at a trunk in open woodland simply never puts a nugget in the candidate list.
- **What is highlighted is what gets ordered, and that is enforced by construction, not by care.** `SelectionManager.order_pick_mask()` is the single mask, `gather_target_from_pick()` the single resolver, and `resource_under_cursor()` (hover) and `_handle_right_click` (order) both go through them. They had already drifted: the hover path built its own mask with `LAYER_RESOURCES` set **always**, so the gather cursor was promised where the click would not deliver it.
- **A click into the gap between nuggets counts as a click on the pile** (`_ore_in_cluster_zone`, the resource analogue of `_enemy_in_squad_zone`). The test is the **ellipse the highlight draws** (`half + CLUSTER_RIM`), not an approximation — the promise and its execution must be the same geometry. It fires **only when the ray found nothing at all**; an explicit click on a tree, a building or a soldier is never overridden.
- **Highlight rendering costs no draw call for the tree itself.** `veg_multimesh.gdshader` gained `COLOR.b` as a highlight factor (`r`/`g` were already wind phase/cycle, `b`/`a` were free) — a private material would have kicked that tree out of its bucket and restored the per-plant draw call the whole `VegetationRenderer` exists to remove. `VegetationRenderer.set_highlight()` is a no-op when the value is unchanged, which matters because hover is polled. The green ring/oval is **one** `MeshInstance3D` for the whole game (`Main._hl_node`, `shaders/res_highlight.gdshader`), moved and rescaled — there is only ever one target under the cursor. `depth_draw_never` and **not** `depth_test_disabled`: the ring must honestly go behind a soldier standing in front of the vein; the fog plane's opposite choice is for the opposite requirement.
- **Ring for a tree, oval for a pile — the shapes encode different orders.** A tree is chopped one trunk at a time; a pile is worked as a deposit, and the crew takes neighbouring pieces by itself. The highlight shows the real scope of the order, so it must differ.
- **The auto-cycle is bounded, and player and AI have different policies.** `Worker._auto_find_resource` used to call `find_nearest_resource`, i.e. *nearest of this type anywhere on the map* — so the crew silently walked across the map past the lake and the enemy patrols, and the idle-workers counter **could never fire on an exhausted pile** because a worker always found something. Now: `find_next_resource_nearby` takes the next piece **in the worker's own pile** (ore, via `_gather_cluster`) or the nearest live trunk within `WOOD_NEXT_RADIUS` (26 m, wood has no pile id — forests are scattered, not composed). Player: nothing nearby ⇒ release the slot, go IDLE, land in the Idle Workers counter. AI: falls through to `find_next_cluster_resource` (nearest piece of any *other* pile) — nobody hands an AI crew a manual order, and a crew stuck on a mined-out vein is just dead economy.
- **`Worker._gather_cluster` is snapshotted in `command_gather`, not read from the target later.** An ore piece is `queue_free`d when exhausted, so at the exact moment the pile id is needed there is nothing left to ask. Same reasoning as `_gather_res_type`. It is cleared by `command_move` and `command_build` — a direct order ends the job.
- **Chop is denser; mining deliberately is not.** `CHOP_SWING_RATE` 4.55 → **6.30** = exactly one swing per second (owner: "звуков топора очень жиденько"). The limiter was never the constraint — five workers at 0.72 Hz produce 3.6 hits/s against a `gap` window that passes 14 — so raising `SFX_LIMITS.chop` alone would have changed nothing audible; the limits were raised anyway (`voices` 6→8, `gap` 0.07→0.045, wider pitch because there are only 4 chop samples and at the higher rate a narrow ±6 % started sounding looped) to lift the ceiling for a large crew. **`MINE_SWING_RATE` (4.55) is a new, separate constant**: it was one constant for the whole toolset, and speeding up the axe would have silently sped up the pickaxe and the builder's hammer too. `_swing_rate()` checks `State.BUILDING` **first** — a builder's `gather_target` is null and `_work_res_type()` would have returned the *cargo* type (wood by default).
- **Gather time was NOT changed.** The original brief asked for +15 %; the owner reversed it in the same session ("ничего замедлять не надо"). `WOOD_SPEEDUP = 0.85` stands.
- Measured after the doubling (`qa_veg`, whole map in frame, RTX 4070): **290 draw calls, 1.21 ms/frame** — the ~160 extra ore `MeshInstance3D` did not create a rendering problem (documented pre-doubling reference was 385 calls / 1.29 ms, the spread is map randomisation). Node count 6868.
- Covered by **`qa_res2`** (24 checks: layout doubling and pairwise clearance, registry and oval coverage, the rock-behind-tree pick, hover≡order, gap-in-pile click, in-pile auto-cycle, player idles vs AI moves on, wood clearing radius both sides, swing rates and audio limits). **B2/B4 were verified to go red with the pick fix disabled** — the harness reproduces the reported bug, it does not merely assert the new behaviour. `qa_tree` B1 asserted "exactly +30 % against 3.5" and is now a property check (chop ≥ 1 hit/s and faster than the pickaxe) — the same stale-assertion class documented elsewhere in this file.

## Targeting and enemy inspection (Aug 13 2026)

- **Hovering an enemy squad lights red rings under every one of its models** (`Main._update_enemy_hover`, polled on the *same* `CURSOR_POLL` tick as the resource highlight — both answers are needed at the same moment and both cost one ray). It highlights the **squad**, not the model under the cursor: the game commands squads, and ringing one man out of twenty would misstate what the order will hit. `_enemy_in_squad_zone`'s `SQUAD_CLICK_REACH` generosity is reused so aiming a step wide of the block still reads as aiming at it.
- **Gated on `_selection_can_attack()`**: a worker crew hovering spearmen must not promise a fight it cannot start (`attack_damage = 0`). Also suppressed while the cursor is over a resource — two contradictory promises under one cursor is worse than either alone.
- **Red rings are a third `Layer` in `SelectionDecalRenderer`, not a recolour of the existing one.** Ring colour is baked into the *mesh's* material (`UnitVisuals.ring_mesh`), so "the same ring in another colour" is unavoidably another mesh and therefore another MultiMesh. It is cheap by construction — at most one squad is ever hovered. `UnitVisuals.hover_ring_mesh()` is deliberately **wider** than the yellow ring (0.31/0.35 vs 0.26/0.29), not just differently coloured: your selected squad and a hovered enemy squad can share the frame, and radius reads faster than hue in a dense block. No shadow layer — the shadow means "mine, and under my command".
- **The inspected enemy squad lives in `SelectionManager.recon_units`, NOT in `selected_units`, and that is a safety property, not tidiness.** `_handle_right_click` iterates `selected_units` and issues orders to everything in it — an enemy soldier in that array would take orders from the player. Keeping them apart makes that impossible by construction rather than by vigilance. `qa_recon` D1/D2 pin it down.
- **LMB on a visible enemy unit opens the recon card and returns.** That branch previously did not exist — the condition required `faction == FACTION_PLAYER`, so a click on an enemy silently cleared the selection. **Order matters inside the branch**: `on_selection_changed` fires *first*, then `_set_recon`. The reverse (which is what was written first, and it failed) has the card open and then immediately wiped, because `HUD.show_selection` clears `_recon_units` by design — own troops and foreign troops must never share the panel.
- **The recon card reuses `_show_stat_panel` wholesale.** That panel already reads `faction` off the sample unit, so the *enemy's* forge grades resolve by themselves with no second branch — `qa_recon` C1 researches a node for `FACTION_ENEMY` and asserts the card follows. Veterancy stars and the earned-bonus icon row come along for free. What the recon card omits is **every command button**: `button_container` stays empty (and collapses via `_sync_panel_grid_widths`), and the squad-card strip is skipped too, since clicking a card there narrows the *selection*.
- **`Health` was added as the first line of `_show_stat_panel`, and its base is computed backwards.** Every other stat is added by the forge *at read time*, so field + bonus = total. `bonus_health` is the one exception — `GameManager._apply_health_bonus_now` writes it straight into `max_health` at research time — so printing `base = max_health` would show the bonus twice. The line subtracts it back out. The panel header additionally carries the squad's **live** total (`243/250 HP`): the Health line is the model's passport, the header is what is left standing right now, which is the whole point of scouting.
- **Recon respects fog** (`SelectionManager._visible_to_player`). Without it the player could poke the black and get a full squad card, i.e. find the enemy army by touch, straight past the mechanic. Members of a hovered squad that are individually unlit are dropped from the ring set too — drawing rings on them would leak the position fog is hiding. `fog.enabled = false` (harnesses) means everything is visible, as before. Note the check is on the **new recon/hover paths only**; right-click attack on an unseen enemy is a pre-existing hole and was left alone.
- **Harness trap worth remembering: the fog mask only covers the map.** `qa_recon` originally parked its squads at `z = -240` (map half-Z is ~73), where `is_lit()` honestly answers false for everyone — and E1's "lit ⇒ rings, unlit ⇒ no rings" formulation passed while testing nothing. Any fog assertion must place units **inside** the map and assert the positive case explicitly.
- Covered by **`qa_recon`** (19 checks: rings on the whole squad and only on enemies, no rings without a selection / with a worker crew / over a resource, card contents incl. HP-damage-armour and live squad HP, enemy forge grade and veterancy visible, own selection closing the card, and the two safety checks). Pre-existing reds confirmed unchanged: `qa_hudcam` A4/A5/A9/A11b (4 of 70, HP-bar assertions — identical on a stashed baseline) and `qa_vet`'s `_die on Nil` script error (43/43 verdicts regardless, also identical on baseline).

## Tactical and economic AI (Aug 13 2026)

Everything below runs **once per `THINK_INTERVAL` (2 s) and once per SQUAD**, never per soldier. The AI's army is ~10 squads; the same decisions taken per man would cost 20× and change none of them — a squad retreats, flanks and hides as a body. Measured: a full `tick()` with 9 squads / 360 men against 30 player units is **3.7 ms**, i.e. a fifth of one frame, once every two seconds. `qa_mass_perf` at 3000 is unchanged (8.45 ms marching, PASS).

- **The AI never bought anything from the forge tree, and that was a hole, not a balance choice.** `_construction` only walked `_UCfg.UPGRADE_SLOTS` — the legacy flat slots, whose first entry is permanently closed by a placeholder `requires`. The entire 4×20 tree was invisible to it, so a long game pitted an upgraded player against a base-stat AI, which read as "the AI is weak". `_research_forge()` now scores every unlocked node by `AI_FORGE_WEIGHTS` divided by its gold cost (so it climbs the tree from the cheap end instead of stalling on one expensive node), restricted to unit types the AI actually trains, and keeps `AI_RESEARCH_GOLD_RESERVE` untouched — an upgraded army of three loses to an untrained army of thirty. **No engine change was needed**: a tree node *is* an upgrade slot (`get_upgrade_slot` falls back to `forge_config.get_node`), so `can_research`, `Smithy.research`, cost, queue and bonus accumulation all worked already.
- **Squad strength is measured against the squad's own PEAK, not against `_UCfg.squad_size`, and this is the single most important lesson of the block.** The first version used the config's full squad size as the denominator — "fraction of a full squad", which sounds right. But AI squads are *assembled by reinforcement*: the barracks releases men rank by rank and `_regroup` starts a squad from **one** soldier, topping it up over later ticks. By the config yardstick such a squad reads as 5 % strength, so fresh reinforcements turned round at the gate and walked back into the castle — permanently, because inside they became reinforcements again. `qa_ai2` caught it as six swordsmen getting role `retreat` instead of `flank`. Peak-based strength has no such failure mode and matches the brief better: a whole squad of any size reads 1.0, and the number falls only from losses and wounds — which is what "critical damage" means.
- **`peak` is written in a FOURTH pass of `_regroup`, after recruits are folded in — not in the pruning pass.** A squad formed this tick did not exist during pass 1, so its peak would stay 1 until the next tick; and if it took casualties inside that window, the peak would be recorded *already reduced*, making a wrecked squad look whole forever. The harness caught this too, as "strength 60.00" for sixty freshly grouped spearmen.
- **Retreating squads are handed to `Castle.request_garrison` and then left completely alone.** That call already clears the formation, puts everyone in retreat mode (no interception, no auto-aggro, passes through enemy ranks) and walks them to the gate; a home-grown "go to the castle" order would reimplement all of it worse. `_apply_orders` therefore `continue`s on `ROLE_RETREAT` — **any** order from the AI would be a `command_move` without `keep_retreat`, which clears `retreating` and sends the squad back into the fight it was pulled out of. Garrison ids come from the *members* (`u.squad_id`), not from the AI's own record: the garrison speaks GameManager squads, and the AI's record is its own grouping that can hold remnants of several.
- **Garrisoned members are dropped from AI squads exactly like the dead** (`_regroup`). They are alive but off the map (`Castle.absorb_unit` hides them and pulls them out of rendering); left in the roster, the AI would hold the `retreat` role forever, assign posts to invisible men and never train replacements. Units released from the castle are picked up again by the ordinary recruit pass.
- **Swordsmen flank by SPRINTING past the wall, and that is load-bearing, not flavour.** A sprinting unit is skipped by `enemy_block` and by every combat gate (`Unit.sprinting`), so it actually goes *around* the spear line instead of sliding along it and being sucked into the first skirmish. The flag clears itself on arrival, at which point the squad attacks the archers it came for. The price is honest and intended: sprinting troops take damage normally. The approach is two-stage (arc waypoint beside the archers while far, direct attack when close) and the side of the arc is frozen per squad at birth — recomputing it each tick made two squads swap flanks every 2 s and go nowhere.
- **Archer kiting falls back behind the nearest friendly melee squad, measured FROM THE THREAT.** The retreat point is `cover + normalize(cover − threat) * KITE_BACK_DIST`, so the infantry ends up *between* the threat and the archers; computing "behind" relative to the archers themselves would happily place them behind their own cover but still in front of the enemy. It uses a plain `command_move`, **not** retreat mode — archers must keep shooting, and retreat mode silences auto-aggro.
- **Phalanx: rank count is the input, column count is derived** (`cols = ceil(men / PHALANX_RANKS)`). The old hard-coded 6 columns laid 20 spearmen out as 6+6+6+2 — neither even ranks nor a predictable depth. Now 60 men on 4 ranks is exactly 15×4 and stays even under losses.
- **Spears are lowered by the DEFENCE stance, not by the march** (`Spearman._spear_leveled`: `holds = _stance_holds_ground() or _charging()`). A marching AI squad was in ATTACK stance, so it advanced with spears up and only levelled them at the moment an attack order landed, i.e. already in contact. `AI_SPEAR_PHALANX_ON_MARCH` keeps spearmen in DEFENCE while no player unit is within `CONTACT_RADIUS`, and returns them to ATTACK on contact. The contact test is one scan per squad, not per man.
- **The home garrison is a screen, not a ring.** `_guard_post` spread posts evenly around a circle regardless of branch, so half the garrison stood facing its own rear and archers were as likely as not to end up in front of the spearmen. `_assign_home_posts` / `_screen_post` now lay it out facing the player's base — spearmen forward, archers behind them, swordsmen on the flanks — the same shape as `_command_last_stand`, deliberately: the formation at your own walls should not depend on whether the AI arrived there by plan or by retreat.
- **Tactical roles are applied from inside `_apply_orders`, not from each planning branch.** That is the only place orders actually reach soldiers, so tactics anchored there cannot be forgotten when a new planning branch is added. Order of checks is order of priority: retreat outranks everything, then archer cover, then the flank. One tactical role per squad per tick.
- Covered by **`qa_ai2`** (24 checks: forge node choice / trained branches only / gold reserve, even ranks and lowered spears on the march and the switch on contact, flank role + lateral waypoint + sprint + final attack on archers, kite trigger and direction and cover, whole-squad-doesn't-retreat vs wrecked-squad-does, retreat mode surviving a second tick, screen geometry, and the 3.7 ms tick cost). `qa_ai` #5 asserted "all guard posts lie on `GUARD_RING`" — a ring cannot satisfy the screen requirement at all, so it was rewritten to assert the new property (nothing facing the rear, spearmen deeper along the course than archers). Same stale-assertion class as `qa_tree` B1.

## The ore deposit is one object (`scripts/MineCluster.gd`, Aug 14 2026)

A pile of gold or stone used to exist only on screen: a dozen-and-a-half separate `ResourceNode`s, each with its own stock, its own ring of work slots and its own life. Every complaint about mining traced back to that one fact.

- **Work slots ringed EACH PIECE, and the pieces stand touching — so half the slots fell between the rocks, i.e. inside the pile.** That is the whole "workers climb into the ore texture and twitch": a slot in a gap is reachable only by walking into the heap, where neighbours immediately shove you off it, arrival is never registered, and the order is re-issued. `MineCluster` marks slots on the **outer perimeter of the whole ellipse** (`stand = outline + STAND_GAP`) and `qa_res2` A6а checks the property directly — not one of the 48 slots may have a normalised ellipse radius below 1.
- **The gather target is the CLUSTER, not the piece you clicked.** `ResourceNode.gather_anchor()` redirects `Worker.command_gather` to the piece that survives the whole depletion (`MineCluster.anchor()`, the largest one nearest the centre). Without that, every cosmetically vanished nugget would drop the worker's target and send it hunting for a new one mid-job.
- **`in_work_reach` is asked of the TARGET, not computed by the worker.** A pile has no meaningful "centre" to measure to — it is elongated, and a worker at the far end would honestly read as out of range. `ResourceNode.in_work_reach(pos)` answers by distance for a lone resource and by the ellipse for a pile.
- **A piece's `remaining` is a MIRROR of the cluster's stock**, rewritten on every extraction (16 writes, once per worker trip — nothing). That is what keeps every pre-existing `rn.remaining <= 0.0` test — the next-target search, the click resolver, the auto-cycle — answering correctly while knowing nothing about clusters.
- **Capacity is one number in the config**: `unit_stats_config.DEFAULT_CLUSTER_GOLD` / `_STONE` (50000), resolved by `cluster_stock(kind)`. Previously the stock was the sum of `PIECE_CLASSES.amount` over the layout — i.e. **the balance was derived from the artwork**: editing how a deposit looks silently changed how much it held, and adding gold meant editing the composition. `amount` (and the long-dead `jitter`/`spread`) were **deleted** from `PIECE_CLASSES`, not left unused — an unused number in a balance sheet eventually gets edited by someone expecting an effect.
- **Depletion shrinks AND removes, both driven by the stock fraction.** Every standing piece scales to `lerp(FADE_MIN_SCALE, 1, frac)` and `ceil(frac × n)` of them stay; the removal order is "small and far from the centre first", so the heap thins like a real spoil pile and the anchor is last by construction. A hidden piece leaves the group, zeroes its collision layer and **drops its trunk obstacle** — otherwise an invisible wall would stand where the rock was (the same trap `extract` documents for stumps). The node stays alive: the member list has to stay whole, and 16 sleeping nodes per pile is not worth coding around holes in an array.
- **"Workers are forbidden inside" is enforced twice, and the second one is only a backstop.** Primary: no order into the interior is ever issued, because the destination is a perimeter slot. Backstop: `MineCluster.outward_push` nudges a worker that *other* forces (neighbour separation, trunk avoidance, a crew arriving) pushed inside, at the same invisible `SETTLE_SPEED` used to settle onto a slot.
- `MineCluster` is `RefCounted`, not a node: it has nothing to draw and no reason to tick. It deliberately does **not** preload `ResourceNode` (that would be a cycle) and calls its members' methods by name. `ResourceNode._mine` is typed `null`/untyped on purpose — annotating it with the `class_name` would tie the file to the global class cache, which has broken this project's build before.
- Covered by **`qa_res2`** A5–A8 (pool from config, mirrored remaining, slots outside the oval, reach from every slot, two workers never share a point, push-out, shrink-and-vanish, pile freed at zero), **F** (end-to-end: order → perimeter slot → work → shared pool, never once inside), and **G** (the worker's forge branch actually reaching the worker, and the cycle floor).

## Highlight, stumps and the rally flag (Aug 14 2026)

- **`res_highlight.gdshader` measures the distance to the ellipse boundary IN METRES and has no fill mode any more.** The soft wash under an ore pile (`fill`) read as a blurred blob covering the very nuggets it pointed at, and the ring's thickness used to be a *fraction of the radius* (`inner`) — fine for a circle, wrong for an oval, where the same fraction is twice as thick along the long axis. Now `half_size` (world semi-axes) and `ring_width` (world metres) go to the shader, and antialiasing is one screen pixel via `fwidth`, which also stops the line from ever thinning below a pixel. `HOVER_RING_W` is 5 cm for both the trunk ring and the cluster oval.
- **The trunk ring is 0.5 m, half of what it was, and that is what fixed "the ring is off-centre".** The old radius came from `slot_radius()` — the circle the *lumberjacks* stand on. It described the crew, not the tree, which is exactly why it looked displaced from the trunk. `HOVER_TREE_RADIUS` now describes the comel.
- **SUPERSEDED Aug 14 2026 — the ring is light, almost white** (`0.90, 0.94, 0.92`, `alpha_max` 0.78), and it is lifted to the drawn comel by `ResourceNode.hover_ring_lift()`, which measures the transparent padding under the trunk in the texture itself (`Image.get_used_rect`, cached per sheet) rather than hard-coding a number. Dark green worked on grass and vanished on stone, gold and in forest shade; a hairline has to read on all three, and only a light tone is contrasty against green, grey and yellow at once. The `highlight_gain`/`highlight_lift` pair dropped another 20 % (0.36 → 0.288, 1.16 → 1.128). The bullet below is kept for the reasoning about *why* the two colours are allowed to differ.
- `HOVER_RES_COLOR` was a restrained dark green (`0.12, 0.52, 0.20`). It deliberately **no longer matches** `veg_multimesh`'s `highlight_tint`: a tint mixed into bark needs a light shade or the tree just darkens, while a hairline on grass needs a dark one or it disappears into fresh green. The tint's strength dropped 20 % as asked — `highlight_gain` 0.45 → 0.36 *and* the brightening 1.20 → 1.16 (now the uniform `highlight_lift`); changing one without the other is meaningless, the green reads as their product.
- Stumps are another −10 % (`STUMP_HEIGHT` 0.855 → 0.7695); the procedural fallback stump was scaled by the same factor, or a map without stump sprites would look different from one with them.
- **The rally marker is a swallowtail pennant, half size, dark red**, with a 4 cm ring at 0.54 m. `QuadMesh` cannot make that shape, so `_build_rally_flag_mesh()` builds three triangles by hand with the offset from the pole **baked into the vertices** — an `ArrayMesh` has no `center_offset`, but local coordinates are turned by the billboard exactly the same way, so the cloth still hangs beside the pole from any camera angle and is not sliced in half by the opaque cylinder.
- **`qa_shotvis/Shot.tscn` is the harness that must NOT run headless** — it saves real screenshots of a highlighted tree (before/after), a highlighted ore pile, that pile depleted to a quarter, a stump, the rally flag, **a squad leaving a barracks (`_spawn`), the unexplored map (`_fog`, `_fog_base`) and the selected-squad panel with its stat window (`_panel`)**. `<godot> --path . res://qa_shotvis/Shot.tscn -- --out=<abs path prefix> --size=900x580`. Two traps it documents in code: the project window opens **Maximized**, so `window_set_size` is silently ignored until you switch to `WINDOW_MODE_WINDOWED` (the first run came out 3440 px wide and a 5 cm line was invisible); and `Main._process` polls the cursor every frame and resets the highlight to whatever the mouse is over, so a forced `_update_hover_highlight()` is undone before the frame is captured unless `main.set_process(false)` is called first. It also plants its **own** tree on a cleared spot — inside real forest the ring at the comel is hidden by the crown of whichever tree stands nearer the camera.

## Units came out of the corner: two facades that had drifted apart (Aug 14 2026)

The complaint was "squads spawn beside the barracks, not from the doors", and the suspected cause was a pivot anchored to a sprite corner. **The pivot was fine** — every building sprite already stands with its bottom edge on the ground at its own point (`_maybe_load_building_sprite`), and so do trees, ore and stumps. The bug was a disagreement between two things that were each individually correct:

- the **picture** is nailed with its facade on world **+Z** and is not linked to the camera at all (`make_static_material`, zero node rotation) — so the drawn door always faces the bottom of the screen;
- the **gate** was `front_dir()`, "from the building toward map centre" — an arbitrary direction that depends on where the building was placed.

The player's base sits in a corner, so `front_dir` points diagonally, and the squad left through a side wall. Finding this needed the two to be compared with each other; each on its own reads as correct code.

- **The gate is now a real node**: `Marker3D` named `SpawnPoint`, child of the building, position `facade_dir() * gate_depth()`. `_gate_position()` reads `spawn_point.global_position`, so moving the marker moves the spawn — "the exit point is a node" is not just a comment. (The brief asked for `Marker2D`; the game is 3D and a 2D marker has no world point to hand a soldier.) Buildings here are built in code, not scenes, so the node is created in `_ready` — the requirement's substance (one explicit, visible, movable place instead of a formula spread across three files) is unchanged.
- **It must be created in `_ready`, not lazily.** `_gate_position()` is called from `_physics_process` (the castle's garrison watchdog), and `add_child` while the engine is walking the tree is refused — the marker then has no parent, its `global_position` is its LOCAL position, and the gate lands at map origin. `qa_garrison` caught exactly that: a squad marching forever toward `(0, 0, 6.5)`. `_gate_position()` also keeps a fallback (`global_position + spawn_offset`) for a building assembled outside the tree, which harnesses do.
- **`front_dir()` still exists and is still right** — `EnemyAI` uses it to know which way a base is turned. What was wrong was using it for the gate.
- `Barracks`/`Smithy` no longer set `spawn_offset`: it was overwritten by `_face_front()` before it was ever read, i.e. a number that documented nothing.
- **Consequence for harnesses, and it is real gameplay**: the gate can now be on the far side of the building from an approaching squad. `qa_garrison`'s wait was tuned to the old diagonal gate 2.9 m away; the same squad now walks 8.0 m, so its patience went 20 → 60 steps. `qa_spawnlane` D1 measured lateral drift against `front_dir()` — i.e. against the wrong axis, which is why it stayed green while the bug was live — and now measures against `facade_dir()` plus "the gate is outside the front wall".

## Fog of war, second pass: opaque, silent and still (Aug 14 2026)

- **Unexplored is now 100 % opaque black** (`hidden_alpha` 0.86 → 1.0, `fog_color` → black). At 0.86 fourteen per cent of the picture came through, and on the owner's screenshot the terrain, the forest and the **enemy castle** were all plainly readable through "fog". A translucent pelt hides nothing: scouting is pointless when the whole map is visible from frame one. `seen_alpha` went 0.42 → 0.34 — the explored-but-unwatched band only has to say "this is memory, not events"; foreign units and buildings there are hidden by *not being drawn* (`Unit.tick_visual`, `_apply_enemy_building_visibility`), not by the pelt's opacity.
- **Spatial sound from unlit ground does not play** (`AudioManager._audible_at`, called first in `play_3d`). This is anti-cheat, not polish: axes and combat clatter из черноты let a player locate the enemy base and army by ear, bypassing the whole mechanic. The gate is `is_lit`, not `is_seen` — explored-but-left ground shows remembered terrain, and hearing "someone is chopping there right now" gives the same thing away one tick later. It is checked **before** thinning, file pick and voice allocation: a sound that will not be heard must not consume a voice or the category's rate-limit window.
- **Tree sway freezes outside the lit zone.** The fog mask is handed to `VegetationRenderer.set_fog()` once (`FogOfWar.setup`), stored, and applied per **bucket** — buckets are a handful, plants are thousands, and the shader answers "am I visible" itself from the instance origin. The decision is made **once per plant in `vertex()`**, not per pixel: with a per-pixel test a crown could sway while its trunk stood still where the fog edge crosses it. A frozen plant holds *its own phase frame* (`floor(COLOR.r * frame_count)`), not frame 0 — a whole forest stopped in the identical pose looks worse than one that moves.
- **`ResourceNode.shake()` returns early when the tree is unlit** — a trembling trunk gives an enemy lumberjack away exactly as the axe sound would, and it also stops an invisible tree from waking its per-frame tick and dirtying the shared buffer.
- **Every harness that measures sound or shake now switches the fog off** (`qa_audio`, `qa_audio2`, `qa_tree`, `qa_veg/SelfTest`) — they place their objects where no player unit stands, i.e. in the dark, and they test the sound, not the fog. `enabled = false` is the documented escape hatch (`is_lit` answers true everywhere). The gate itself is pinned in **`qa_fog` F0–F4**: silence and stillness in the dark, sound and shake still working on lit ground, and the off-switch restoring both — otherwise those four harnesses would be silently measuring nothing.

## Bottom panel, second pass (Aug 14 2026)

- **+10 % height** (`PANEL_H` 40 → 44, `COL_H` 32 → 36, `PORTRAIT_W` 30 → 33). The halving of the previous pass turned out too tight once the panel had to hold a portrait with a badge, a caption and an XP bar. `INFO_W` 110 → 132 for the same reason — the bar lives in that column.
- **The panel had no content margin at all**, because `StyleBoxFlat`'s default is 0 — that is why the "helmet" was flush against the frame. `PANEL_PAD_X` = 6 (the brief's "at least 5" plus room for the border), `PANEL_PAD_Y` = 3. Anything measuring distance to the panel edge must now count **four** terms — separator + spacer + border + this padding; `_sync_panel_grid_widths` was off by exactly `PANEL_PAD_X` until that was added (`qa_hud5` C8г: 19 px against a configured 15).
- **The count badge is 10 px, not 12**, and its box shrank to match: at 12 px a two-digit squad size ("30") covered the helmet outright.
- **Buttons are centred by a `CenterContainer` wrapper (`_btn_slot`), not by the grid.** The reserved width is a full `BTN_COLS` row and must stay fixed (that is the anti-jitter rule), but a `GridContainer` given that width lays 3–4 buttons from the **left** and leaves a gap on the right. The wrapper holds the reserved size; the grid shrinks to its content and sits in the middle. `_slot_min()` is the single writer, because three branches (castle / worker crew / ordinary) set that size.
- **Button order and colour are fixed**: `[Attack red] → [Defend green] → [Passive yellow] → [To Castle dark red]`. Defend was **blue**, which corresponded to nothing and shared the shield icon with the passive toggle. Order is achieved by call order — `_add_to_castle_button` is called **last** in both `show_selection` and `_build_type_detail`, since a grid lays children out in insertion order; there is no anchor that would put one child "in the right corner".
- **"To Castle" bails out when the squad has an unclaimed veterancy reward.** The reward menu replaces the whole button row (`_maybe_add_stance_buttons` returns early for it), and a sixth button added past that early return broke the row — `qa_vet` reported "6 buttons, expected 5" immediately.
- **The XP bar replaced a duplicated line.** "Отряд мечников — 30 бойцов" stood in the bottom panel word for word under the *same* sentence in the stat window directly above it, with the count also drawn as a badge on the portrait — one number said three times. The panel caption is now the squad name; the count stays on the badge; the freed line is `_xp_bar` + `_xp_label` ("Ранг 2 → 3  12/40"). Its own `ProgressBar`, not the existing `progress_bar`: that one shows production and a selected barracks would have both fighting for one strip.
- **`_xp_progress` treats the threshold ladder as possibly flat.** `VET_CONFIG.thresholds` may legitimately repeat (`[40,40,40,40,40,40,50]` — one kill grants several levels), so the naive `(kills − th[lvl−1]) / (th[lvl] − th[lvl−1])` divides by zero. It searches for the nearest threshold **strictly above** the kill count and the largest one already taken.
- **Live squad HP stayed only in the recon card** (`_show_stat_panel(..., live_hp)`). For your own squad it is noise — health bars are on the soldiers — but for a scouted enemy "how much of it is left right now" is the entire reason the card is opened.
- **A tooltip never lands on the stat panel.** `_tip_anchor_geometry` pushes the window right past `_stat_panel`'s rect when they would overlap. Only the **horizontal** overlap is tested, and that is not a shortcut: the stat panel is pinned to the left edge and grows upward from the same line the tooltip grows from, so they share a vertical band by construction. Ability buttons sit in the left half of the row, so the overlap happened on every hover.
- **The gap between the stat window and the panel is gone** (`PANEL_TOP − 6` → `PANEL_TOP`): six pixels of dark made two blocks read as two unrelated windows.
- **The worker's portrait is no longer enlarged** — one template for workers, swordsmen, spearmen and archers, as asked. The build **buttons** keep their boost: that is about reading small building art, not about the template.

## Resource bar: the tool glyph is per resource (Aug 14 2026)

- `RES_TOOL_GLYPHS` gives each resource the tool its worker actually uses in the sprite (`Worker._update_sprite_anim`): 🪓 wood, ⛏ stone and gold, 🔪 food. One pickaxe for all three gathered resources was simply untrue for the forest, and read as a bug on the owner's screenshot.
- **`RES_WORKER_SECTION` is now −1: there is no "total workers" section.** Food used to show the player's total, because food is produced by Houses and a per-resource count there is permanently zero; the owner reversed that — an honest zero is the answer they want. All four sections now answer one question. **Honest consequence: the total worker count is no longer displayed anywhere in the HUD**; the nearest thing is the idle-workers widget. The branch is kept (not deleted) so restoring it is a one-line change.

## Density, not unit count: the melee optimisation (Aug 14 2026, second pass)

The report was "43 FPS with ~1400 units attacking a base, and the army flickers". Headless said the physics tick at 1400 was 6.8 ms — i.e. the harnesses were measuring the wrong thing, because a windowed frame is what the player sees. **`qa_fx/Test.tscn` is the windowed battle benchmark that closed that gap**: two armies of N/2, real map, V-Sync off, timing by the clock (`Performance.TIME_FPS` lies without vsync — same as `qa_veg`), split into `тик / визуал / прочее`, plus draw calls, bucket migrations and a flicker metric. Takes `--count`, `--secs`, `--seed`, `--fog`, `--prof`.

- **Cost per soldier grows with DENSITY, not with army size.** Measured: 600 → 9.5 µs/unit, 1000 → 13, 1400 → 23–27 — while the number of units *walked per tick* stayed ~470 (sharding is already at its 3-shard floor above 1200). What grows is the length of the cell lists the neighbour scans walk.
- **The fix was to split the grid's cell lists by side** (`ArmySoA._head`, index `cell*2 + side`, 0 = player, 1 = everyone else). Every scan asks about exactly one side — "is an enemy blocking me" (`enemy_block`, target search) or "did I overlap an ally" (separation, phalanx rank) — and the shared list forced each of them to walk **both** and throw away half with a `fac[j] == myf` test. `query_radius` is the only scan that wants everyone, and it is the only one that walks both lists; it is a cold path (mouse click, arrow hit).
  - The invariant this rests on: **`_side()` is binary, not "faction number"**. A third faction would silently be lumped with the enemy. That is a deliberate trade — the scans' question is always "mine or not mine" — and it is the reason the `fac[j]` tests were removed rather than kept as a belt-and-braces filter: a redundant test that can only ever be true hides the assumption instead of stating it.
- **`_cell_box()` allocated an `Array` per scan.** In a melee that is hundreds of heap allocations per tick. The five hot scans now compute the four cell bounds into locals inline (the same thing `batch_separation` already did).
- **Measured, same map seed, 1400 in one dense scrum in forest:** melee tick **15.2 → 10.4–11.2 ms**, frame **21.6 → 17.0–18.2 ms**, **46 → 55–59 FPS**. On a favourable (thin-forest) map the same run reached 93 FPS. `qa_mass_perf 3000` marching 9.1 → 8.8 ms, still PASS; `qa_mass_battle 5000` unchanged at ~24 ms (it was already over budget before this work — see the Phase-3 table).
- **What is left is `process_move` at ~74 % of the tick**, of which `mb_enemyblock` is now 7.5 µs (was 9.85) and ~28 %. The remaining ~10 µs inside `_process_move` is unattributed by the branch profiler and cutting it means the batch movement pass already scoped in "Full node elimination" — a phase of its own, not a tuning knob.

### Flicker: what was measured, and what was not

- **`qa_fx` counts it instead of arguing about it**: per frame, "alive but not drawn" (units with no MultiMesh slot) and the frame-to-frame jump in the drawn count. Both are near zero now (worst jump 3–4, average 0.2 — that is deaths).
- **Bucket migrations are NOT the cause** — 5–9 per frame at 1400, measured (`FarUnitRenderer.migrations`).
- **Fixed and measured: the fog edge.** Foreign units are not drawn at all under the pelt, the mask is rebuilt 7×/s, and units on the boundary crossed it constantly — they blinked at the mask rate. `Unit.FOG_HIDE_GRACE` (0.45 s ≈ three mask rebuilds) holds a unit drawn after it stops being watched. Hidden-unit count at 1400 with fog on: 163 → 100. **The grace is measured on the CLOCK, not by subtracting delta**: an idle unit sleeps and is woken by `_wake_returned_far_units` for one frame every 0.25 s, so a delta-based countdown would have needed ~7 seconds of wall time to expire (`qa_fog` D2 caught exactly that). A unit that was **never** lit gets no grace — otherwise fresh enemy hires would flash on screen.
- **Fixed but NOT proven to be the reported flicker: a register/slot desync.** `_far_registered = true` was set unconditionally after `register_far()`, and `refresh()` may legitimately return null (a strip change unregisters and then fails to re-register). The unit then stayed "registered" with no slot and was never drawn again — permanent, not blinking. It is now `_far_registered = _far_slot != null` and the null result re-arms registration. A/B with the old code showed a gap of 0 in this scenario, so it is a real hole that this scenario does not hit; it is fixed on its own merits.
- **Honest residue**: with fog off I could not reproduce flicker at all. A large part of what reads as "мерцание" at 43 FPS is the frame rate itself — sprite animation runs at 6–10 fps and aliases badly against an uneven 43 FPS frame time.

## Fog, stars and overlays: everything above a unit obeys the same visibility (Aug 14 2026)

- **Enemy construction sites were revealing the map.** `FogOfWar._collect_building_sources` walked the `construction_sites` group with **no faction filter** — and that group is shared by both sides (the check exists one function below, in `_apply_enemy_building_visibility`). Every AI foundation lit a `BUILDING_VISION` (42 m) circle for the player, so the AI's base — castle, walls, forest — appeared on the map within the first minutes. Hiding enemy buildings by `is_seen` was working correctly the whole time; the ground genuinely *was* explored. Pinned by **`qa_fog` G1/G2** (enemy site reveals nothing / own site still does — without the second half the check would also pass on code where sites reveal nothing at all and the build crew works in the dark). G1 was verified to go red with the filter removed.
- **Veterancy stars are world-parented nodes, so they did not inherit anything.** They stayed drawn over black while their squad was hidden — a red star hovering in the dark is a free map of the enemy army. `_update_squad_stars` now sets `star.visible` from `fog.is_lit(centroid)`.
- **A garrisoned soldier is alive, so he was still in the centroid** — the star crawled onto the castle roof as the squad walked inside ("звезда прилипла к зданию"). `_on_map_members()` filters `Unit.garrisoned` out of everything drawn above a squad; an entirely-garrisoned squad hides its star.
- **HP bars are slots in `HpBarRenderer`, not children of the unit**, so hiding the sprite left a red tick floating in the fog. `_hide_in_fog()` unregisters the bar and `_hp_fog_hidden` brings it back when the unit is lit again (a flag, not an unconditional call: this path runs for every foreign unit every frame).
- **A destroyed castle now empties its garrison instead of deleting it.** Garrisoned units are alive but hidden, un-ticked, out of the faction groups and standing at the castle's point; `Building._die()` just freed the building and left them as permanent invisible ghosts that the victory check still counted. `Castle._evacuate_on_death()` releases every garrisoned squad at the gate and cancels the incoming ones (their retreat mode is cleared, or they would march to a gate that no longer exists). Of the owner's two options — "run out" or "die in the rubble" — the first was chosen: they are the defender's own troops, healing rather than hiding, and deleting them rewards the attacker for something he did not do.

## Sprinting no longer walks through bodies (Aug 14 2026)

`_move_blocked` skipped `enemy_block` for `sprinting` as well as `retreating`. For the player's double-RMB that read as "run past without being drawn in"; for the AI's flanking swordsmen (`ROLE_FLANK`) it read as **infantry walking straight through the player's spear line**, which is what was reported.

The two meanings that flag had were separated: *don't join the fight* stays with sprinting (auto-aggro, march interception and retaliation are still suppressed by the five `not sprinting` gates); *pass through people* is gone. Pass-through is now retreat-only — a squad recalled to the castle must not be cornered, which is why that exception exists.

- **A sprinter's step is ROTATED onto the tangent with its length preserved, not merely stripped of its inward component.** Stripping leaves a unit heading nearly head-on with centimetres of lateral movement: it crawls along the line at a few cm/s. Measured — four runners past a single body in 7 s: 0 of 4 with the strip, 2 of 4 with a head-on deflection added, 4 of 4 with the full rotation.
- **The "second pass" block test is skipped for sprinters**, and without that exception the rotation was pointless: sliding *along* a line keeps you at the same distance from the bodies, so `enemy_block` at the new point is non-zero again and the whole step was cancelled. A walker in that situation must stop (it is about to fight anyway); a sprinter has no inward component left to sink with.

## Workers: the pile stopped being a maze (Aug 14 2026)

- **"Running on the spot" at an ore pile was the push-out having no dead band.** Work slots sit exactly on the `stand` ellipse (k = 1.000) and `outward_push` fired at `k < 1.0` — so settle noise, terrain height or a neighbour's nudge kicked the worker out, the settle step pulled him back, and he oscillated at the rim without ever starting work. `PUSH_DEADBAND` (0.92) is wider than any of that noise and still well inside the drawn heap.
- **`is_inside()` now means "inside the DRAWN heap" (`outline`), not "inside the standing ring" (`stand`).** A slot point sat exactly on the boundary of the old test, so the answer came down to the last bit of the mantissa — `qa_res2` F2 passed or failed depending on the map roll.
- **Small and medium ore pieces are no longer obstacles** (`ORE_OBSTACLE_MIN_SCALE`): sixteen half-metre colliders standing shoulder to shoulder is a maze, and a worker who dodged one immediately hit the next. Only "big" pieces block now — the pile still reads as an obstacle and squads do not march through it.
- **A worker whose pile still has stock re-acquires instead of idling.** The nearby search is bounded by a radius around the *worker*, and a worker pushed out of that radius went idle next to a live vein. `GameManager.cluster_anchor()` answers "the piece that outlives the whole pile" and the worker goes back to it.
- **Workers at a resource are allowed to overlap** (`ArmySoA.F_WORKING`, `WORK_OVERLAP` = 0.62 of the normal spacing ≈ a third of a sprite). Separation is not switched off — five workers would then converge to one point — the working unit simply gets a shorter threshold. The flag is written in one place (`Worker.tick_physics`, from the state) so no order path can leave a unit permanently "working".

## Volley fire, veterancy alerts, tactical pause (Aug 14 2026, third pass)

### Volley fire (`forge_config` archer 1d, a squad MODE)

The two-stage ability machinery already existed (research unlocks it for the faction, each squad then buys it with gold) — what was missing is that owning it did nothing, and that a bought ability had no on/off state.

- **`toggle: true` in the config is what makes an ability a mode**, not an `if id == "archer_1d"` in the panel. `forge_config.is_toggle_ability()` / `toggle_ability_of(unit)` are the only readers; the HUD, the AI and the harness all ask the config, so the next mode needs no UI change. A bought mode starts **off**.
- **Synchrony is a squad-level answer, exactly like the corridor and the battle line.** `GameManager._sweep_volleys()` runs once per squad per physics frame (and skips squads with no bought ability in one dictionary test); the archer only *asks* (`Archer._may_strike_now`). A soldier cannot decide "are the others ready" on his own.
- **It opens a WINDOW (`VOLLEY_WINDOW_MS` = 200), not a one-frame flag.** The army tick is sharded, so a given archer is polled every second or third frame; a one-frame "fire!" would have caught a third of the squad and split the volley into three ragged waves.
- **`_may_strike_now()` clamps `_attack_timer` to 0 instead of letting it run negative** — "reloaded and waiting" has to be a stable state, because the squad counts how many of its members are in it (`VOLLEY_READY_FRACTION` = 0.7; not "all", or one man whose target drifted out of range stalls the squad forever).
- **The aim point is the enemy SQUAD's centroid, not the mean of the archers' individual targets** — targets are picked by each archer's own scan, so their mean is biased toward whichever flank has more shooters. Falls back to the target mean when the victim has no squad.
- **Zero dispersion was rejected on the physics.** An arrow damages whoever is within `HIT_RADIUS` = 0.35 m of it (`Arrow._check_hit`), so twenty arrows converging on one point all enter the same soldier — nineteen of them into a corpse. What is removed is the *random* scatter (`VOLLEY_JITTER` = 0.10 against the normal 0.35–1.5 m); in its place each archer takes a **deterministic** slot on a golden-angle spiral sized to the target block (`_volley_offset`, capped by `VOLLEY_CLUSTER_MAX`). The result is a dense cloud covering the block evenly with no gaps and no overkill — the brief's "100 % hits on packed formations" without its literal reading's failure mode.
- **The AI buys and enables it** (`EnemyAI._buy_squad_abilities`, its own gold reserve). Without that pass it would research the node and never use it: the player's second stage is a click on the panel, and the AI has no panel.
- Covered by **`qa_volley`** (23 checks: locked until 1D is researched, buy/toggle/off-by-default, volley fires in bursts while normal fire is a trickle, aim = enemy centroid, every archer gets his own slot in the cloud, several enemies actually wounded, and the AI path including its gold reserve).

### Veterancy alert stack

- Squads with an unclaimed reward stack as pulsing icons under the idle-workers widget. **Empty means empty** — no dimmed placeholders. That is deliberately different from the idle widget, which at zero *dims* rather than disappears: "no idle workers" is an answer, "nobody is waiting for a reward" is the absence of a question.
- The stack is rebuilt only when the **set of squads** changes (signature string), on the same 0.5 s tick as the idle counter — rebuilding per frame would restart every icon's pulse from the beginning.
- Clicking an icon centres the camera on the squad's centroid, selects it and opens the panel — one click instead of hunting the squad on the map.
- **The reward buttons flash once when the panel opens** (`_flash_once`, staggered left-to-right). Once, not looping: a permanently blinking row under the player's hand is irritating, unlike an alert in the screen corner, which exists precisely to nag. The pivot is set to the button's centre first, or a scale/flash tween drags it out of its grid cell.

### Tactical pause: the world stops, the game does not

`get_tree().paused` froze everything except the HUD, so the pause was only good for walking away — you could not select a squad, give an order, place a building or move the camera.

- **`process_mode` is inherited downward, and that is the whole design constraint.** Putting `ALWAYS` on `Main` (needed — the placement ghost and the hover cursor live there) also puts it on `_world` and the entire army, and the game would not pause at all. So the branches are listed explicitly in `Main._setup_pause_modes()`: `Main`, camera, `SelectionManager`, HUD are **ALWAYS**; `_world`, `enemy_ai` and the fog are **PAUSABLE**. `GameManager` is deliberately absent — it is an autoload outside `Main` and pauses on its own, taking the army tick and all rendering with it.
- **`Main._process` now has to gate its own simulation by hand** (`get_tree().paused`): the placement ghost and hover cursor keep working, the victory check and the duck's bobbing do not.
- **Orders given during a pause neither execute early nor get lost**: `command_move` and friends only write fields on the unit, and the step is taken by its tick — which is stopped. Verified as behaviour, not as a flag (`qa_pause` B2/B4).
- **Space is a second pause key next to Z**, both through `HUD.toggle_pause()`.
- Covered by **`qa_pause`** (18 checks: the per-branch process modes including "ALWAYS did not leak down", orders on pause, the alert stack appearing/clicking/vanishing on reward taken and on squad wiped, and the dimmed idle widget).

## Ground decals follow the DRAWN unit, not the logical one (Aug 14 2026, fourth pass)

The report was "selection rings sit half a metre down-right of the soldiers' feet, on spearmen, archers and a lone worker alike". **The rings were never wrong.** `SelectionDecalRenderer` writes them at `unit.global_position`, and `qa_ring` B measures the sprite anchor straight out of the sheet's alpha: feet land within 1–2 cm of the logical point on all four unit types. What moved was the *picture*.

- **`Unit._smoothed()` draws the soldier at a lagging point**, on purpose: the logic steps once per physics tick, and with sharding once per *three* ticks, while the sprite is drawn every render frame. Catch-up smoothing is what stops that from reading as stutter. Its steady-state cost is a lag equal to a fraction of one step — **measured at 0 on one shard (`vis_lerp_k` clamps to 1) and 0.28 m per axis on three**, i.e. 0.4 m along a diagonal march. That is exactly the reported offset, and it is why the bug only shows up in a real battle: below ~1200 men the game runs one shard and there is no lag to see.
- **The fix is one accessor.** `Unit.draw_position()` returns `_draw_pos`, and `SelectionDecalRenderer` (yellow rings, shadows, red hover rings) plus `HpBarRenderer` now read it instead of `global_position`. The logical point stays honest — hits, clicks, grid, fog and blocking all still use it.
- **The decal sweep moved from `_physics_process` to `_process`**, right after the army's visual tick and before the flushes. `_draw_pos` is recomputed in `tick_visual`; updating decals in the physics tick would have read the value from the frame before and reintroduced the same class of gap, only smaller. Sharding then works in the project's favour: a unit whose `tick_visual` was skipped this frame has neither a new sprite position nor a new decal position, so the two cannot drift by construction.
- Pinned by **`qa_ring`** (16 checks). Section A **forces three shards** (`perf_config.tick_shards_force = 3`) and asserts both "ring is within 2 cm of the drawn point" *and* "the picture really is lagging" — without the second check the first would be green on the broken code too, because at one shard there is nothing to lag.

## The garrison could split a squad in two, permanently

Screenshot: one squad standing as two clumps at opposite ends of the map with its veterancy star hanging in the empty middle. Two independent causes, both fixed:

- **A cancelled march into the castle abandoned whoever was already inside.** `_process_garrison` drops a squad from `_incoming` when the player gives one of its members a different order (`cancelled`), and the old code left the already-absorbed men in the castle — where nothing could ever release them: they are not in `garrison` (`all_in` never became true) and no longer in `_incoming`. Half the squad stayed invisible forever, and `_evacuate_on_death` walks `garrison`, so they died with the building too. `_spill_absorbed()` now pushes them back out at the gate. It deliberately does **not** call `_release_members` — that would re-order every member to the gate, i.e. overwrite the very player order that caused the cancel.
- **`_release_members` gave out slots but never registered a formation.** Every released man got his own point, while the squad's `slots` stayed empty — for `GameManager` that is "a squad that was never formed", so `close_ranks` had to synthesize a shape from scratch and until then the squad moved as a blob. It now calls `squad_set_formation`, and the move order goes to **every** member (including those who never went inside), which is what pulls a split squad back together.

## Defence means defence (Aug 14 2026)

Owner's rule, and it reverses two earlier decisions:

- **A direct attack order no longer breaks the DEFENCE stance.** `command_attack(forced)` used to call `set_stance(STANCE_ATTACK)` — so the phalanx existed only until the player's first click on an enemy, after which it chased like ordinary infantry. Now the stance outranks the order: a squad in DEFENCE hits what it can reach and does not move. Want a charge — switch the stance, that is what the button is for.
- **`_should_pull_up` is skipped in DEFENCE.** Rank pull-up moves a soldier *toward the target*, which is the opposite of holding a line. Closing a hole in one's own formation is a different mechanism (`_phalanx_advance`) and still runs.
- **`PHALANX_ADVANCE_ON_ENEMY` is false.** The front rank no longer steps toward a nearby enemy on its own; the only step left is into a gap in its own block. The branch is kept behind the constant, not deleted — it is a rule of combat and will be argued about again.
- **`Unit.pursues_target()` — `Archer` returns false.** A ranged unit approaches an ordered target only until that target is *first* inside `attack_range` (`_engaged_once`, reset by `command_move` and by a change of target); after that it never takes another step toward anything. Measured in `qa_hold` D: an archer ordered onto a target 40 m away stops at exactly 20.0 m, its bow range, and opens fire. Melee keeps pursuit — without it a swordsman with a 1.6 m reach could not fight at all.
- Covered by **`qa_hold`** (12 checks: the wall does not creep on a standing enemy or follow a fleeing one even under a player order; the rear rank still closes a gap and does not turn that into an advance; archers hold position, drop an unreachable target, pick up a new one in range, and still execute an approach order).

## Stumps were already inert — the sticking is live trees

Checked rather than assumed. `ResourceNode.extract()` on the last of a tree's wood already drops the trunk from the obstacle registry, zeroes `collision_layer`, leaves the `resource_nodes` group and stops ticking; **`qa_stump` (10 checks) confirms a worker walks through a wall of eight stumps in a straight line with zero stalled frames, and a nine-man block marches through ten of them.** No code change was needed.

Worth knowing, because it cost a debugging round: the first version of that harness laid its stumps "somewhere" and failed — the map carries ~1800 real trunks, the test lane ran through a live copse, and the worker honestly slid around a **live** tree. Any harness about movement must clear its corridor first (`_clear_lane`), and must clear it as a *band*, not a line: a tree 4 m to the side stops the flank file of a marching block.

## Modifiers are one table, zero-filled (Aug 14 2026)

Owner's request: every research node and every veterancy reward carries the **whole** list of modifiers the game has, with `0` against everything it does not give, so tuning is editing a number in place rather than remembering a key name and where to add it.

- `unit_stats_config.MODIFIERS` is that list, and `BONUS_KEYS` is the same thing as an array for hot loops. Twelve keys; three of them are new and are wired, not decorative: `bonus_range` (metres of reach), `bonus_cooldown` (seconds off the strike timer, floored by `MIN_COOLDOWN`), `bonus_spread` (fraction by which an archer's random scatter is cut). `bonus_defense` was veterancy-only and is now readable from the forge too.
- **Sign discipline: plus is always good.** Where the effect is a reduction (cooldown, scatter, gather cycle) the subtraction lives in code. One column with an inverted sign in a balance sheet is a future mistake.
- **`bonus_range` is written into the field, not read live.** `attack_range` is read dozens of times per tick per unit (intercept, pull-up, target scan, fog vision); a cross-object call in each of those would cost more than the bonus is worth. Same trick as `bonus_health`: `Unit._ready()` adds it at birth, `GameManager._apply_range_bonus_now()` hands it to everyone already standing.
- **Veterancy rewards lost their `stat`/`value` pair from the table.** They now carry the same twelve keys, and a reward may legitimately grant several at once — `apply_veteran_choice` iterates the non-zero ones. The short pair is *derived* on read (`veteran_choices` fills it in from the first non-zero key), because keeping it in the table would be the same number written twice, and two descriptions of one number always drift.
- The expansion is mechanical and was done by script; integrity is pinned by `qa_forge` (47), `qa_cfg` (14), `qa_vet` (43) and `qa_upgrade` (25), all green afterwards.

## The 1400-man frame, measured with a working economy (Aug 14 2026)

The report was "with ~1200+ fighters and a live economy (~40 workers a side, bases, smithies) the army flickers and jerks, and the frame collapses". `qa_fx` gained an `--eco` mode that builds exactly that scene — castle + barracks + smithy per side, continuous hiring, 80 workers on real ore and forest — plus a **step-jitter metric**: the coefficient of variation of the *drawn* point's per-frame step, averaged over the sample members that are actually walking (a standing soldier has a zero mean step and would otherwise dominate the number).

Measured, 1400 fighters, same map seed, RTX 4070, V-Sync off:

| | frame | tick | visual | other | FPS |
|---|---|---|---|---|---|
| no economy | 19.0–27.2 ms | 8.8–17.3 | 5.0–6.3 | 3.1–3.9 | 37–53 |
| **with economy** | 20.9–27.3 ms | 9.6–16.4 | 6.0–6.8 | 4.4–4.9 | **37–48** |

- **The economy costs about 1–2 ms, i.e. it is not the cause.** 80 gathering workers, seven buildings, continuous hiring and 2100 resource nodes are within noise of the same battle without any of it. What eats the frame is the melee — the density effect already documented above.
- **Nothing disappears.** "Alive but not drawn" stays **0** across the whole run and the frame-to-frame change in the drawn count averages 0.2 (that is deaths). So the visible artefact is not units blinking out.
- **What is visible is stepping.** At 1400 the ladder gives three shards: a soldier's position changes 20 times a second and is drawn 37–48 times a second. Step jitter measures 1.7–2.2, where 1.41 is the signature of a perfect three-shard staircase.
- **The obvious fix was implemented, measured and switched off.** Smoothing (`Unit._smoothed`) lives *inside* the sharded visual tick, so it fires at the same moment as the step and does nothing in between — the natural repair is a separate light pass every frame (`Unit.tick_draw`, `perf_config.draw_catchup`). Result: visual 6.0–6.8 → **10.8–12.6 ms**, frame → 26.3–33.7 ms, FPS 36–48 → **30–38**, and jitter 1.88 → **1.76**. Six milliseconds for seven per cent. The reason it fails is arithmetic: `vis_lerp_k = delta / (interval × VIS_SMOOTH_TAU)`, and at 30–40 FPS with a 50 ms update interval that expression already saturates at 1, i.e. there is nothing left to catch up. **Smoothing is killed by the low frame rate, not by where it is called from — the frame has to come first.** The code and the switch are kept as the ready-made A/B; the default is `false`.
- **Where the frame actually goes** (`--prof`, shares only — the branch profiler inflates absolutes ~1.8×): `process_move` **75 %** of the tick at 24.5 µs/call, of which `mb_enemyblock` is 8.6 µs; `sep_overlap` 1.17 ms/frame, `grid_rebuild` 0.57, `squad_corridor` 0.28. The telling ratio is `mb_enemyblock` 87 413 calls against `mb_commit` **14 960** — **83 % of steps are cancelled by the enemy line**, i.e. most of the army pays the whole step pipeline every tick to move nowhere. That is the case the batch movement pass scoped in "Full node elimination" exists for, and it is the only thing left that can buy the remaining ~10 ms. Tuning inside the current per-object step will not: the per-branch numbers are already at the level the density pass left them.
- **One cheaper idea is written down but deliberately NOT taken here.** A unit whose step was cancelled by the enemy line is, by definition, standing still against a wall of bodies; it could take a short movement lock (a few ticks) instead of re-running water → trunk → enemy-line → clamp → commit every tick to move nowhere. Rough ceiling from the numbers above: ~2–4 ms of the 16 ms tick. It is not done because it changes the core of movement, and every one of `qa_spear`, `qa_guard`, `qa_settle`, `qa_crowd`, `qa_target_lock`, `qa_combat_lock` and `qa_disengage` depends on that path — a speculative change there belongs at the start of a pass, with room to validate it, not bolted onto the end of one.

## Big-battle pass at 2500+ units (Aug 15 2026)

Everything in this section came out of one report: crashes, a two-second pulse,
and squads behaving wrongly at ~2500 units (32 player squads = 1934 men plus
600+ AI). Numbers below are measured on this machine, RTX 4070.

### The crash was a two-line ordering mistake, and it also explains the "deadlock"

`SelectionDecalRenderer.gd` and `HpBarRenderer.gd` both walked their
`Dictionary<Unit, slot>` like this: `var u: Unit = unit` **then**
`if not is_instance_valid(u)`. **Assigning a freed object into a typed variable
throws by itself** — the guard the line was written for could never run. In a
2500-man battle that error printed every frame for every fallen unit: the
picture kept ticking while physics and audio stalled, which is what the report
called a deadlock. The rules this leaves behind:

- **Check `is_instance_valid` on the raw loop variable, BEFORE any typed
  assignment or `as`-cast.** `m as Unit` on a freed object does not return null
  either — it throws "Trying to cast a freed object" (`GameManager._matrix_allowed`
  already documented this; the renderers were the two places that had it backwards).
- **A helper that cleans up after freed objects must take `Variant`, not the
  class.** `unregister(unit: Unit)` throws on the very garbage it was called to
  remove, so `_drop_slot(unit)` / `drop_hover(u)` are deliberately untyped.
- **The prickly one is the hover layer.** Red aiming rings are set from the
  cursor poll (12 Hz) while a hovered squad is cut down in a fraction of that,
  and `Unit._exit_tree` cleaned the yellow rings and the HP bar but **not** the
  hover set. That was the actual leak; the loop ordering was the second half.
  `_exit_tree` now also drops hover, and `sel_decals.unregister` is called
  unconditionally instead of `if _selected` — the flag is a second description
  of the same fact and the two can drift.
- Pinned by **`qa_recon` F1-F3**, verified to go red *with both fixes removed*
  (it prints the exact reported `SCRIPT ERROR: Trying to assign invalid
  previously freed instance`). Either fix alone makes it green, so the check
  only means something against the original state.

### The "two-second pulse" was one function called per soldier

`EnemyAI._apply_orders` called `_nearest_player_target()` **inside its loop over
squad members**, and that function walked `get_nodes_in_group("player_units")`
plus `player_buildings` — i.e. it *copied* the group's internal array on every
call and measured distance to every unit on the map. Measured directly on one
scene (1900 player units, 600 AI units in 30 squads, throwaway harness):

| | one AI think tick |
|---|---|
| per soldier, group walk (old) | **509 ms** |
| per squad, flat grid (new) | **2.68 ms** |

509 ms in a single frame every 2 s is the pulse, and it is exactly the reported
"drops to 6 FPS at the first clash" — the more squads, the bigger the stall.

- The unit half now goes through **`ArmySoA.nearest_of_side(x, z, side, radius)`**,
  a new point-based query over the grid that is already rebuilt this frame
  (`best_enemy` asks from a *row*; the AI has no row, only a centroid).
  Buildings are not in the grid, so their list is snapshotted **once per tick**
  (`_refresh_target_cache`).
- **One target per squad, not per soldier — and that is a behaviour fix too.**
  Giving every man his own nearest target is precisely the mechanism documented
  as the biggest source of "the squad splits up" (see `SelectionManager`).
  `command_attack` spreads one order across the enemy squad by itself through
  `GameManager.squad_pick_member`, and it spreads it evenly rather than by
  proximity.
- **Order issuing is spread over frames** (`_order_queue` / `_drain_orders`,
  `ORDER_BUDGET_MEMBERS` = 200). The *decision* still happens for all squads at
  once — the situation must be consistent — but handing `command_move` /
  `command_attack` to 600 men is drained a few hundred per frame. At 600 men
  that is 3-4 frames, i.e. 50-70 ms against a 2 s tick.

### Defence means defence — but a phalanx under orders MOVES (reverses Aug 14)

The Aug 14 rule ("a direct attack order no longer breaks the DEFENCE stance")
stands; what is reversed is that DEFENCE also meant *never take a step*.
`_process_attack` nulled the target the moment it left weapon reach **even under
a direct order**, so clicking an enemy twenty metres away moved the wall not one
step. The requirement now splits in two:

- **At rest — nailed down.** Nothing changed: auto-aggro in DEFENCE only takes
  what is already inside `attack_range` (`_check_auto_aggro`), the counter-charge
  on being hit is gated off, and `_should_pull_up` is skipped.
- **Under orders — the wall advances**, slowly (`PHALANX_ATTACK_FACTOR` 0.75),
  spears down (DEFENCE already levels them), killing what it meets.

Two things carry this, and both *removed* code rather than adding a flag:

- **`pursues_target()` returns `not _stance_holds_ground()`.** The archers'
  "approach once, never chase" machinery (`_engaged_once`) was already written
  and tested; DEFENCE is simply its second case. The bare `_stance_holds_ground()`
  term is gone from the give-up condition.
- **`_phalanx_march`: the wall walks to the POINT of the order, not after the
  target.** Aiming at a live target *is* pursuit, only performed by the whole
  squad — so `command_attack(forced)` in DEFENCE stores `_hold_goal` (where the
  enemy stood when the order was given) and the block goes there. Whatever comes
  within reach on the way is engaged by swapping `attack_target` **directly**,
  never via `command_attack` (that would overwrite `_attack_is_forced` with its
  own argument and cancel the very order the wall is executing). `_flank_step`
  (individual weaving around a scrum) is skipped in DEFENCE — that is what
  "single fence" means mechanically.
- `_hold_goal` is cleared by `command_move`, `begin_retreat` and by switching
  *into* DEFENCE (pressing the shield means "stand here", not "first finish
  walking where I sent you a minute ago").
- `qa_hold` A2 asserted the *old* requirement in so many words ("the stance holds
  position even so") and was rewritten to the new property: the wall closes the
  3.5 m gap of the order and stops, while the enemy that ran 20 m away is not
  followed. A2b additionally asserts it really did move — without it the first
  half would be green on a completely immobile block.

### Two ways enemies walked into the middle of a phalanx

Both were movements that bypassed the enemy-body check entirely:

- **`_rear_step`** (the cheap step for men marked "behind my own front") only
  ever asked about *its own* file depth. In a sparse fight the rear is far from
  the enemy and this is invisible; in a dense melee the formations interleave and
  a man marked rear by *his* squad walked straight through foreign bodies — into
  the middle of the opposing phalanx, past every spear. It now honours
  `enemy_block`, using the squad corridor answer (`_clear_enemy`) as a free
  early-out. The saving `_rear_step` exists for (no water, no trunks, no combat
  FSM) is untouched.
- **`_apply_push`'s winner half-step.** The only movement in the game with no
  body check at all. Two centimetres per push looks harmless, but pushes repeat
  every `PUSH_EVERY` strikes for as long as the rank is winning.

### Group movement: no reshuffling, and rear echelons are centred

- **`_block_formation_slots` handed line sections out in SELECTION order.** The
  grid path (`_issue_group_grid_move`) had been sorted by position for a while;
  the RMB-drag path had not, so a squad standing on the left flank could be given
  the right-hand section and walk there *through* its neighbours. `_blocks_along`
  now orders blocks by their centroid projected on the line — movement vectors
  come out parallel and paths cannot cross by construction.
- **Every echelon got the WHOLE line.** For the spearmen that is right — they are
  the front — but one archer squad stretched over the same width as four spearman
  squads lies in a *single rank as long as the whole army*. That is the thin
  thread visible behind the blocks in the formation preview, and it is the real
  shape behind "the archers end up on the right flank". A rear echelon's width is
  now proportional to its own strength against the first echelon and centred on
  the front's middle, so 20 archers behind 80 spearmen take a quarter of the
  front, dead centre, at the **same men-per-metre density** as the front.
- The preview draws from the same function, so it follows for free.
- New harness **`qa_line2`** (9 checks): rear echelon width/centre/depth/density,
  and squads keeping their left-to-right order through a drag ordered
  deliberately backwards.

### AI: no retreating out of a melee, and one battle order for all tactics

- **`_try_retreat` refuses while the squad is in contact** (`AI_NO_RETREAT_IN_MELEE`).
  A squad that turns its back mid-fight does not retreat, it dies: retreat mode
  silences auto-aggro *and* retaliation, so it walks to the gate absorbing free
  hits. Retreat is allowed before contact and after it, never out of it. Contact
  is read from the existing bookkeeping via the new `GameManager.squad_engaged(sid)`
  — no new walk over members appears, and its 0.4 s staleness works in the right
  direction (a squad that just broke contact still counts as fighting).
- **The idle-nudge was a second source of the same thing.** "More than half the
  squad is idle → re-issue orders" is *always* true in a melee where the squad
  outnumbers its foe: only the front rank reaches, the rest honestly stand in
  `State.IDLE`. The re-issued `command_move` then dropped the live targets of the
  front rank (`_disengaging`). It is now skipped while the squad is engaged.
- **`TACTICS` was rewritten, not bypassed.** The old table swapped the *arms
  themselves* (`archers_front` put bowmen in front of the spear wall), which
  directly contradicts the new requirement. Config is the source of truth, so the
  battle order lives in the table: spearmen hold the front line, archers strictly
  behind them, warriors on both flanks — in **all three** tactics, which now
  differ by depth and width instead. `qa_ai` #6 asserted the old per-tactic
  ordering and was rewritten to assert the invariant.
- **The wave now faces the player's ARMY, not their castle** (`AI_FACE_PLAYER_ARMY`,
  `ARMY_AIM_RADIUS` 120 m). The course orients the whole order — echelon depth,
  flank spread and every squad's facing — and taken castle-to-castle it could
  present the shield wall sideways to an army met in the field, with the archers
  beside their own infantry instead of behind it. The aim point comes from the
  same grid query as above, one scan per tick.

### Workers: the endless retry was the "broken Idle with a tick"

A worker in `State.IDLE` holding a `gather_target` it could not reach re-issued
`command_gather` to itself **once a second, forever** — step, blocked, IDLE,
repeat. It never appeared in the Idle Workers counter either, because formally it
had a job. Now the attempts are counted (`APPROACH_GIVE_UP` = 4, i.e. four
seconds), after which the vein is declared unreachable, **excluded from the next
search** (otherwise "nearest" returns it again immediately and the loop restarts)
and a replacement is looked for in a **wider** radius (`WIDE_SEARCH_SCALE` 2.5).
Nothing there either → the worker honestly stands idle and enters the counter.

**Trap this cost a debugging round:** `command_gather` reset the attempt counter,
and the retry calls `command_gather` — so the threshold was never reached and the
first version of the fix did nothing. The counter now resets only on a *change*
of target. Covered by `qa_res2` H1-H3.

### Measured at 2600 units

Headless (`qa_mass_perf` / `qa_mass_battle`, light meter, 16.6 ms budget):
marching **8.17 ms (49%)**, battle **10.2 / 13.0 / 13.2 ms — PASS**.

Windowed, two armies of 1300 in forest with a live economy (`qa_fx --eco
--count=2600`, V-Sync off, RTX 4070):

| phase | frame | tick | visual | FPS |
|---|---|---|---|---|
| standing | 24.4 ms | 12.5 | 7.7 | 41 |
| closing | 21.6 | 13.1 | 5.2 | 46 |
| clash | 13.0 | 7.6 | 4.3 | 77 |
| grind | 8.0 | 6.2 | 2.9 | **126** |

"Alive but not drawn" is **0** across the run (no flicker). Console is clean on
a real game run.

**The 70 FPS goal is met in the clash and the grind and is NOT met while standing
or closing (41-46).** What holds the frame there is no longer any of the bugs
above: the branch profile says `process_move` **58%** of the tick, batch
separation 22%, grid rebuild 8%. That is the per-object movement step, and
removing it is the batch movement pass already scoped under "Full node
elimination" — a phase of its own, not a knob. Step jitter stays ~1.8 (three
shards at 2600; `perf_config.draw_catchup` was measured and rejected earlier for
exactly this case — see that section).

### Harness lessons from this pass

- **`Main._process` polls the cursor and resets hover/highlight every frame.**
  Already documented for `qa_shotvis`; it bit `qa_recon` F too, where the section
  passed or failed depending on the poll timer's phase. Any harness that sets
  hover rings by hand must `main.set_process(false)` first.
- **A regression check is only worth something if it goes red on the original
  code.** `qa_recon` F was green with *either* half of the crash fix removed and
  only reproduces the reported error with **both** removed — worth knowing before
  trusting it.

## Batch Movement Phase and the move to C# (Aug 15 2026)

The engine changed under this pass: the project now runs on **Godot .NET 4.7.1
(mono)** with **.NET SDK 10.0.400**, and `csharp/ArmyCore.cs` is compiled into
the game. `Godot_v4.6.3` (standard) can no longer load the project — it has no
C# support at all. Numbers taken before and after therefore also carry an engine
change; where that matters it is said so.

### What moved, and what deliberately did not

`scripts/army/ArmySoA.gd` is now a **façade**. It owns nothing: the columns, the
flat grid, the coarse faction layer, every neighbour scan, the trunk registry
and the two batch passes all live in `ArmyCore.cs`. Every public name is
unchanged, so `Unit`, `Worker`, `Castle`, `Arrow`, `SelectionManager`,
`GameManager`, `SpatialGrid` and ~60 harnesses were not rewritten.

**The solver owns the arrays, and that is not a preference.** On the
GDScript↔C# boundary `Packed*Array` marshals **by copy**. Handing a solver ten
arrays of 3000 floats every frame gives back the entire win at the border. So
the arrays never cross: what crosses is single numbers (thin setters) and
"compute the frame" commands.

**The trunk registry moved with them.** It was the last call *out* of the step
(`GameManager.trunk_block`), and while it stayed in GDScript every batch pass
jumped back into the interpreter once per marching soldier. `GameManager` keeps
`register_trunk`/`trunk_block`/`trunk_near` as one-line forwards.

### Batch movement: the unit asks for a step, it no longer takes one

`Unit._process_move` (and the attack approach, the phalanx march and rank
pull-up — all of them, through `_commit_step`) writes the desired displacement
into the row and raises `F_STEP_PENDING`. One pass after the army walk
(`ArmyCore.BatchMove`) runs the whole geometry: water → trunk → enemy line →
map clamp → terrain height → commit. **The rules did not change by one line** —
same stage order, same tangential slide, same pass-through for retreating
troops; only the place where the arithmetic happens.

Two things this exposed that had been wrong for a long time:

- **`F_CLEAR_TRUNK`, `F_CLEAR_ENEMY`, `F_RETREATING`, `F_SPRINTING` were
  declared and never written** — leftovers from Phase 1, where `Unit` was
  supposed to build a flag word. Nothing read them either, so it was invisible.
  The batch pass reads them for real, so `request_step` now carries a freshly
  built flag word (literal bit shifts on the `Unit` side, as the project rule
  demands; `qa_army` A1 guards the numbering, now through bit 13).
- **The squad matrix (`perf_config.squad_matrix`) stays off, and the batch pass
  is why it can.** Its own note already measured that it engages on ~8 % of the
  map (a clear corridor of trunks is rare in a forest) while costing a full walk
  of every squad every frame. Batch movement gets the same saving *without* any
  precondition — it never has to ask whether the corridor is clean.

### C# was SLOWER at first, and the reason is worth more than the fix

First working port, 3000 units, headless: march **9.31 → 11.82 ms**, battle
**13.5 → 20.1 ms (FAIL)**. The pure loops were dramatically faster and the frame
still got worse. The per-phase profiler said exactly why:

| branch | GDScript | C#, first port | C#, after |
|---|---|---|---|
| `batch_move` | 7356 µs/frame | **1752** | 633 |
| `sep_overlap` | 2929 | **481** | 321 |
| `grid_rebuild` | 1105 | **70** | 70 |
| `squad_corridor` | 615 | **2977** ✗ | 449 |
| `grid_update` (write_pose) | 1.03 µs/call | **2.30** ✗ | 2.21 |
| `vis_row` (row → position) | 0.80 µs/call | **2.30** ✗ | 0.23 |

**One crossing of the language boundary costs ~1.5–2.5 µs — five to ten times a
GDScript field read.** That is the whole story. The loops won 4–15×; the
per-soldier calls around them lost more than the loops won. Four fixes, each of
which removes crossings rather than making them cheaper:

- **`harvest_squad` was the worst thing in the port and is gone.** It took a
  list of *objects* and read three properties per member through `Variant`
  (`_soa`, `state`, `global_position`) — 615 → 2977 µs/frame. Harvesting
  positions from nodes is not needed at all any more: the columns are written by
  the batch step and by separation, so they *are* the fresh truth.
  `SquadBounds(rows, …)` is pure column arithmetic — **one crossing per squad
  instead of three per soldier.**
- **`_recalc_melee` must take a snapshot, not read per soldier.** Replacing
  `army.px` with per-index `pos_x()` calls looked like the tidy thing and cost
  `melee_calc` 22 → 251 µs per recalc. A snapshot copies 12 KB once per squad;
  3200 boundary crossings cost far more. The rule this leaves: **cross the
  boundary in batches or once, never inside a loop over soldiers.**
- **Nobody should ask the solver for a position that the node already has.**
  `tick_visual` went through three variants and all three were measured:
  `global_position` (a property that rebuilds the world matrix through the
  parent chain), four column reads (0.80 µs), one `pos_or()` call (**2.30 µs —
  worse than both**). The right answer is to ask nobody: local `position` is a
  plain transform field and equals world position under the motionless `World`
  (`_local_xform`, a premise that is checked, not assumed). Same fix applied in
  `tick_physics` and in `_process_attack`, where **both** the unit's and the
  target's `global_position` were being read per tick.
- **The pose is published only when it changed.** The old comment above that
  line said the opposite — "a condition here costs more than writing three
  numbers unconditionally" — and on plain GDScript that was *true*. At 2.2 µs a
  crossing it stopped being true, and in a dense fight hundreds of soldiers
  stand in `ATTACKING` with zero velocity for many ticks in a row. Six field
  comparisons (~0.1 µs) against 2.2 µs. `sync_row()` forces the next write, so
  garrison exit and harness teleports cannot desync the row.

Two smaller ones with the same shape: `SpatialGrid` holds a direct reference to
the core (a scan was `Unit → SpatialGrid → ArmySoA → C#`, two of the three hops
pure forwarding), and `FarUnitRenderer.refresh` takes the caller's known slot
and reads the unit's look fields directly instead of a dictionary lookup plus
`sheet_frame()`, which **allocated a five-element Array on every call**.

### Measured at 3000 (1500 vs 1500)

Headless, light meter, 16.6 ms physics budget:

| | before (GDScript, 4.6.3) | after (C#, 4.7.1) |
|---|---|---|
| standing | 5.57 ms | **2.42** |
| marching | 10.04 | **9.35** |
| battle: closing / clash / grind | 12.92 / 15.33 / 15.84 | **10.05 / 11.49 / 11.00** |
| headless main-loop FPS (march) | 49.0 | **81.6** |

Windowed, two armies of 1500 in forest, V-Sync off, RTX 4070 (`qa_fx --count=3000`):

| phase | before | after |
|---|---|---|
| standing (armies in contact, 3000 alive) | 26.1 ms / **38.3 FPS** | 22.3 ms / **44.8** |
| closing | 25.0 / **40.0** | 17.4 / **57.6** |
| clash | 13.7 / **73.1** | 12.1 / **82.4** |
| grind | 7.4 / **134.6** | 9.1 / **110.4** |

"Alive but not drawn" stays **0**; the console is clean; the whole gate passes
(`qa_spear` 47, `qa_guard` 46, `qa_settle` 17, `qa_crowd` 8, `qa_target_lock`
14, `qa_combat_lock` 5, `qa_disengage` 11, `qa_hold` 13, `qa_army` 18,
`qa_vet` 43, `qa_res2` 45, `qa_ai` 34, `qa_ai2` 24, `qa_forge` 47, `qa_fog` 40,
plus the rest). `qa_formation` went **2 red → 1**: one of the long-standing
pre-existing failures fixed itself on the new step path.

**The grind phase reads worse and that is a different scene, not a regression:**
1556 soldiers were still alive at the end against 1304 before, i.e. the same
timestamp now holds a bigger battle.

### The 70 FPS goal: met in three phases of four, and here is what holds the last

Marching, closing, clash and grind are at or above target headroom; **standing
at 44.8 FPS is not**, and it is the honest hard case — 3000 living soldiers with
both fronts already in contact. What holds it is no longer the movement step:

| branch (standing, shares only) | µs/frame | note |
|---|---|---|
| `process_attack` | 4780 | **51 % of the tick**, still per-object GDScript |
| `vis_far` | 2958 | visual pass, per-object GDScript |
| `grid_update` | 1971 | the remaining `write_pose` crossings |
| `vis_pose` | 1733 | pose/mirror recompute |
| `batch_move` | 633 | the C# solver |
| `sep_overlap` | 321 | the C# solver |

The two batch passes together are now **under 1 ms of a 10.6 ms tick**. What is
left is the combat FSM and the visual tick, and both are per-object GDScript —
i.e. the same kind of work the movement step was before this pass, and the same
kind of answer would apply. That is a separate phase with its own gate; doing it
by feel at the end of this one would put `qa_spear`, `qa_guard`, `qa_vet`,
`qa_volley` and `qa_target_lock` at risk with no room left to validate.

### Rules this pass leaves behind

1. **Cross the GDScript↔C# boundary in batches or once — never in a loop over
   soldiers.** One crossing ≈ 1.5–2.5 µs ≈ five to ten field reads.
2. **A per-call snapshot of a column beats per-index accessors** whenever the
   caller touches more than ~10 rows.
3. **`global_position` is a property, not a field.** After anything writes a
   transform it rebuilds the world matrix through the parent chain. Under the
   motionless `World`, local `position` is the same number for free — use it,
   and let `_local_xform` check the premise.
4. **Conditions that were "more expensive than the write" in pure GDScript are
   not, once the write crosses a language boundary.** Re-measure such comments
   instead of trusting them; two of them in this file were already stale.
5. **A C# port is not automatically faster.** Measure the *branch shares*, not
   the total: the first port here won 4–15× inside its loops and still lost the
   frame.

## Batch Combat Phase: what paid, and what was rejected by measurement (Aug 15 2026)

### First: measure the branches, not the function

`process_attack` was 51 % of the tick in the contact phase, and the obvious
reading — "the combat FSM is expensive, move it to C#" — turned out to be wrong
about *which part*. Counting the branches (`qa_fx`, 3000 units, contact phase,
90 frames) gave:

| branch | calls |
|---|---|
| approach | 64532, **of which rank pull-up 60143 (93 %)** |
| within weapon reach | 12185 |
| target lost | 725 |
| **strikes** | **0** |

Not one strike in ninety frames. Target search, damage, cooldowns — none of it
was the bottleneck. **One branch was: a soldier standing in a scrum creeping
toward his target at 55 % speed.** And its cost was not the arithmetic — it was
that the branch ended in `_commit_step`, i.e. **a language-boundary crossing per
soldier per tick**.

### What paid: queues instead of per-soldier crossings

Both of these apply the rule the previous pass wrote down — *cross the boundary
in batches or once, never in a loop over soldiers* — to the two remaining
per-soldier crossings:

- **Step requests are queued.** `Unit._commit_step` no longer calls the solver;
  it appends to four `Packed*Array`s owned by `GameManager` (an in-GDScript
  write), and the whole list goes over in **one** call after the army walk
  (`ArmyCore.BatchMoveQueued`). Side benefit: the pass now iterates the
  *requests* rather than the whole row capacity — hundreds instead of thousands.
- **Pose writes are queued** the same way. `write_pose` was 908 crossings per
  frame at 2.14 µs — 1.9 ms, the second-largest item in the tick. Skipping
  unchanged poses does not help here: in a contact fight almost everyone is
  creeping, so the pose changes for almost everyone. The queue carries the gate
  flags and the effective speed too — the array is being sent anyway, so extra
  fields in it are free.

Ordering that matters: **poses are flushed BEFORE `BatchMove`.** The other way
round they would overwrite the step just computed with the position as of the
start of the frame.

### What was rejected: the batch combat pass itself

It is written, complete, and passes the whole gate — and it is **off by
default** (`perf_config.batch_combat`), because it does not pay. `ArmyCore.BatchCombat`
computes the pull-up step for every eligible row and returns which soldiers
still need the full FSM; everything that is a *decision* or an *event* (target
choice, the player's target lock, blocker intercept, the wall's march, the
strike with its sound, arrow, shove and kill credit) stays in GDScript.

Two versions were built and both measured:

1. **Return a list of soldiers needing the FSM.** Much worse: ~200 `Variant`
   marshals plus 200 GDScript property writes per frame. Clash went 91.8 → 60.5
   FPS. **The boundary is expensive in both directions — a return is a crossing
   too.**
2. **Return a byte mask, one array per frame.** Still a wash. A/B on one seed
   (`qa_fx`, 3000, windowed): contact phase 50.7 vs 48.8 (+4 %, inside the
   harness's own ~5 % run-to-run spread), closing 52.6 vs 63.6, clash 54.6 vs
   81.1.

**Why it cannot pay, stated plainly:** by the time it was written, the crossing
had already been removed from that branch by the step queue, leaving ~4 µs of
plain GDScript. To beat that, the batch must scan **every** row each frame — it
cannot use the army walk's sharding, because the two partitions differ and a
soldier reached by the walk on its own frame must see a fresh decision — and it
must hand the answer back for every soldier. Scan plus answer costs about what
it saves.

The general form, worth remembering: **changing the language of a computation
buys nothing unless the computation is BATCH-SHAPED.** The movement step is
(a thousand identical requests); the combat FSM is not (every soldier takes a
different branch).

One real bug was found and fixed on the way: the first version was **not
sharded** and ran the pull-up every frame instead of every third, tripling both
the scan and the number of step requests. It showed up immediately (clash
91.8 → 55.1) and is the reason `BatchCombat` takes `shards`/`phase` and
multiplies `delta` by the shard count — exactly as the army walk does.

Also removed from the hot scan: `GodotObject.IsInstanceValid` was being called
on all ~3000 rows every frame. It goes into the engine. Row liveness is already
expressed by `F_POS_VALID` (a released row clears it), so the object is only
checked for the few soldiers actually handed to GDScript.

### Measured at 3000 (1500 vs 1500)

Headless, light meter, 16.6 ms budget, **idle machine** (see the trap below):

| | before this pass | after |
|---|---|---|
| marching | 9.35 ms | **7.89 – 8.15** |
| battle: closing / clash / grind | 10.05 / 11.49 / 11.00 | **8.32 / 9.95 / 10.05** |

Windowed (`qa_fx --count=3000`), and note the harness's own spread — two runs of
the *same* configuration gave 42.4/41.5, 59.8/57.6, 78.7/73.7, 99.3/99.2 FPS:

| phase | FPS |
|---|---|
| standing (both fronts in contact, 3000 alive) | 42 – 50 |
| closing | 58 – 75 |
| clash | 74 – 99 |
| grind | 99 – 134 |

"Alive but not drawn" stays 0. Console clean. Gate green: `qa_spear` 47,
`qa_guard` 46, `qa_vet` 43, `qa_volley` 23, `qa_target_lock` 14,
`qa_combat_lock` 5, `qa_disengage` 11, `qa_hold` 13, `qa_settle` 17,
`qa_crowd` 8, `qa_army` 18, `qa_res2` 45, `qa_ai` 34, `qa_ai2` 24, `qa_fog` 40,
`qa_squad` 46, `qa_recon` 22 and the rest; `qa_formation` keeps its documented
pre-existing 2 of 7.

**The 70 FPS goal is met in the clash and the grind, not in the standing and
closing phases.** What holds those is no longer combat or movement: the tick is
~9.7 ms of which the C# passes are well under 1 ms, while the *visual* pass is
8.9 ms and rendering ("прочее") another 5. The next honest target is the visual
tick — `vis_far` (the MultiMesh slot update) and `vis_pose` — and it is a
different subsystem with a different gate.

### A measurement trap that cost real time here

A windowed harness run killed by `timeout` **leaves the Godot process alive**,
and it keeps eating CPU and GPU. Measurements taken afterwards are quietly
poisoned: the same build measured 6.28 ms and 10.54 ms for the identical march
scene, twenty minutes apart, purely because of one leftover instance. This is
the same failure mode `qa_bugpack2` 9b already documents for wall-clock
assertions. **Before believing any timing number, check:**

```
Get-CimInstance Win32_Process -Filter "Name LIKE '%Godot%'"
```

and tell harness runs (`--path . res://qa_*`) apart from the owner's editor
(`--editor`) before killing anything.

## Visual Batching Phase (Aug 15 2026)

### Harnesses now run out of the way

Owner's requirement: mass-battle measurements must not jump onto the main screen
or steal focus. `qa_fx` therefore sets `WINDOW_FLAG_NO_FOCUS` and parks the
window past the bottom-right corner of the desktop; `--show` restores normal
behaviour when the picture needs to be judged by eye.

**Minimising is not an option and was not used:** a minimised window is not
rendered, so the harness would measure an empty frame instead of a battle. It
was A/B-checked that the background mode does not itself change the numbers —
`--show` and the default gave the same readings on the same machine.

### The big win was a flag, not a batch

The counters — which, unlike a clock, do not care how loaded the machine is —
said this about the contact phase over 90 frames:

| | before | after |
|---|---|---|
| pose recomputes | 34638 | **17077** |
| …of them from the animation cadence | 16568 | 16331 |
| …of them from `_pose_dirty` | **23301** | **1022** |
| full MultiMesh slot updates | 34788 | **17227** |

Two thirds of all pose work was triggered by a dirty flag rather than by the
animation clock, and **`wake_for_lod()` was the source**: it called
`_wake_process()`, which sets `_pose_dirty` unconditionally. But
`wake_for_lod` is called by `ArmyCore.BatchSeparation` for *every soldier it
nudged* — hundreds per frame in a scrum — and being nudged does not change how
a soldier looks.

The two meanings were separated. `wake_for_lod()` now only wakes the visual tick
(and dirties the pose **only** when actually coming out of sleep, where the pose
really is stale); `_wake_process()` keeps dirtying, and it is what real
appearance changes call — orders, stance, the start of a strike. Nothing
lags: the pose is still recomputed on the `anim_every` cadence, i.e. within
five of the soldier's own ticks.

### Strings and arrays in the pose path

`Spearman._update_dir_sprite` built **a new `Array` and a new `String` on every
call** (`_sector_to_key` returned `[name, mirror]`; the key was
`"attack_" + name`). At ~800 pose updates per frame that is ~1600 heap
allocations per frame, in the hottest visual path — the same mistake the
`FarUnitRenderer` header already warns about for bucket keys.

Sectors are now an **index**, and the keys come from ready-made tables
(`ATTACK_KEYS`, `DEFENCE_KEYS`, `SECTOR_MIRROR`). The kind of the current pose
is kept as an int (`_cur_kind`) instead of `begins_with("attack")` string scans
in `_update_sprite_flip` and `_process_can_sleep`.

Also: `Unit.target_in_range` and `Spearman._own_enemy_dir` were reading
`global_position` of both the soldier and its target — that is the fourth place
in this project where a matrix rebuild was being paid per call in a hot path.
Both now use the cheap local `position` when `_local_xform` holds, **inlined**:
a hoisted `world_pos_cheap()` helper was tried first and measured no better,
because the call costs about what it saves.

### Measured and rejected: moving the MultiMesh buffers into C#

The plan was to hand slot writes to the solver the way steps and poses already
are. Splitting `vis_far` into its two paths killed the idea before the port:

| path | calls/frame | µs/call |
|---|---|---|
| fast (`Slot.move_to`, position only) | ~680 | **1.21** |
| full (`refresh`, strip/frame/mirror) | ~185 | **4.31** |
| function prologue (before either branch) | ~900 | **~1.4** |

The write itself is 1.21 µs, of which most is the GDScript call — and a queue
append would cost roughly the same. Meanwhile the prologue, the single largest
piece, is not batchable without moving `tick_visual` itself into C#, which needs
the whole animation state machine to go with it. **Same verdict as the batch
combat pass, and for the same reason: the work is not batch-shaped.**

### Measured at 3000 (1500 vs 1500), idle machine

Headless, light meter, 16.6 ms budget:

| | before this pass | after |
|---|---|---|
| standing | 3.43 ms | **2.73** |
| marching | 7.89 – 8.15 | **5.55** (33 % of budget) |
| battle: closing / clash / grind | 8.32 / 9.95 / 10.05 | **5.92 / 7.01 / 6.90** |
| headless main-loop FPS (march) | ~70 | **90.4** |

Windowed (`qa_fx --count=3000`):

| phase | before | after |
|---|---|---|
| standing (both fronts in contact, 3000 alive) | 42 – 50 FPS | **57 – 61** |
| closing | 58 – 75 | **88 – 95** |
| clash | 74 – 99 | **108 – 115** |
| grind | 99 – 134 | **132 – 133** |

Visual pass 8.9 → **6.5 – 6.7 ms**. "Alive but not drawn" 0; worst frame-to-frame
blink 4, average 0.5 — no flicker. Console clean. Gate green (`qa_spear` 47,
`qa_guard` 46, `qa_vet` 43, `qa_volley` 23, `qa_target_lock` 14,
`qa_combat_lock` 5, `qa_settle` 17, `qa_crowd` 8, `qa_disengage` 11, `qa_hold`
13, `qa_army` 18, `qa_res2` 45, `qa_squad` 46, `qa_fog` 40, `qa_recon` 22,
`qa_ring` 16, `qa_group_grid` 15, `qa_line2` 9, `qa_tree` 21); `qa_formation`
keeps its documented pre-existing red (1–2 of 7, it fluctuates).

**70 FPS is met in closing, clash and grind; the standing phase reaches 57–61.**
What holds it is the per-soldier dispatch of `tick_visual` itself (~1.4 µs of
prologue before any branch, ~900 times a frame) plus rendering. Removing that
means moving the visual tick into C# together with the animation state machine —
a phase of its own.

### Rules this pass adds

1. **A "wake" is not a "looks different".** Anything that moves a soldier
   (separation, LOD sweep, teleport) must wake the visual tick without dirtying
   the pose; only real appearance changes may dirty it. Getting this wrong is
   invisible in behaviour and doubles the visual cost.
2. **No `String` or `Array` construction in a per-frame path.** Sectors, keys and
   kinds are integers and lookup tables. This is the third time this project has
   paid for it (bucket keys, formation slots, now poses).
3. **Split a hot function's branches before porting it.** `vis_far` looked like
   3 µs of batchable work and turned out to be 1.2 µs of write, 4.3 µs of a rare
   path and 1.4 µs of unbatchable prologue.

## Animation & Visual Tick Phase (Aug 15 2026)

Goal: 70+ FPS in the contact phase at 3000. **Reached: 85.9 FPS.** And the C#
port that was asked for is *not* what got us there — measuring the prologue
first showed the money was somewhere else entirely.

### The 1.4 µs prologue was eight cross-object reads

Before the first branch, `tick_visual` read **eight values that are identical
for the whole army and change at most once per frame**: `GameManager._view_x`,
`_view_z`, `_view_r2`, `vis_lerp_k`, and the static settings `sprite_lod`,
`visual_smoothing`, `mm_render_all`, `profile_physics`. Then, for every *enemy*
soldier, two more cross-object calls for the fog gate.

They are now read once per frame in `GameManager._process` and passed as
arguments — the same treatment `frame` and `anim_every` already had. Two switches
fold into the value they gate: LOD off becomes an infinite radius, smoothing off
becomes `lerp_k = 1.0`, so the branch disappears along with the read.

The same audit on the physics side found `profile_physics`, `batch_move` and
`GameManager.bonus_version` being read per soldier per tick; all three now
arrive as arguments (`bonus_version` is cached in `_bonus_ver`, a one-tick-stale
value that only delays a fresh upgrade by one tick).

Result at 3000, contact phase: **57.0 → 66.5 FPS**, `grid_update` 2.18 → 1.21
µs/call. Nothing moved to C#; the reads were simply not repeated.

### `wake_for_lod` was dirtying the pose — the other half

Covered in the previous section, repeated here because the two together are the
whole win: separation nudges hundreds of soldiers a frame and each nudge marked
the pose dirty, so `refresh` ran on essentially every visual tick.

### The visual pass may be sharded harder than the physics pass

The last 1 ms came from a config change, not code: at 2000+ soldiers the visual
walk now uses **one shard more** than the physics walk (`vis_shards_for`).

This reads like trading smoothness for frames, and the numbers say it is not —
provided you measure the update interval in **wall time** rather than in frames:

| | visual pass | frame | FPS | drawn-point update |
|---|---|---|---|---|
| 3 shards | 5.48 ms | 15.03 ms | 66.5 | 3 / 66.5 = **45 ms** |
| 4 shards | 3.94 | 11.65 | **85.9** | 4 / 85.9 = **47 ms** |

The drawn position updates at practically the same rate; there are simply 29 %
more frames. The "step jitter" metric rises (1.64 → 1.84) **because of how it is
defined** — it is the spread of the drawn step *per frame*, and there are now
more frames between two steps. Flicker, the metric that actually detects
artefacts, is unchanged: "alive but not drawn" 0, worst frame-to-frame change in
the drawn count 3, average 0.4.

**One trap this exposed:** `vis_lerp_k` was derived from the *physics* shard
count. While the two were equal that was invisible; with the visual pass on its
own cadence the smoothing was tuned for a faster step than actually happens and
under-corrected. It now derives from the visual shard count.

The extra shard is applied only from `vis_extra_from` (2000) soldiers up — a
small army has frame budget to spare and no reason to lose picture rate.

### What was NOT done, and why

The brief asked to move the visual tick loop and the animation state machine
into `ArmyCore.cs`. It was scoped and rejected before writing it, on the same
measurement that produced the fix above:

- The prologue — the thing that was supposed to justify the port — turned out to
  be **eight repeated reads**, removable without leaving GDScript.
- Splitting `vis_far` showed the actual write costs **1.21 µs**, of which most is
  the GDScript call itself; a queue append into C# would cost about the same
  (this is now the third measurement in this project saying so — batch combat and
  the MultiMesh buffer port said it before).
- Moving the animation state machine means moving `SpriteFrames` decomposition,
  the 8-sector directional pose, the spear-down rule and the sleep rule — with
  their state living in two languages at once. That is a rewrite of the visual
  object model with `qa_spear`, `qa_guard`, `qa_far_wire` and `qa_ring` as its
  gate, and it would have bought a fraction of what eight hoists and one shard
  did.

### Measured at 3000 (1500 vs 1500), idle machine

Headless, light meter, 16.6 ms budget:

| | before this pass | after |
|---|---|---|
| standing | 2.73 ms | 2.94 |
| marching | 5.55 | **5.57** |
| battle: closing / clash / grind | 5.92 / 7.01 / 6.90 | **5.94 / 7.49 / 7.52** |
| headless main-loop FPS (march) | 90.4 | **120.6** |

Windowed (`qa_fx --count=3000`), and this is the number the goal was stated in:

| phase | before | after |
|---|---|---|
| **standing (both fronts in contact, 3000 alive)** | 57 – 61 FPS | **85.9** |
| closing | 88 – 95 | **132.4** |
| clash | 108 – 115 | **147.9** |
| grind | 132 – 133 | **142.5** |

Visual pass **6.7 → 3.9 ms**. No flicker. Console clean. Gate green — `qa_spear`
47, `qa_guard` 46, `qa_vet` 43, `qa_volley` 23, `qa_target_lock` 14,
`qa_combat_lock` 5, `qa_settle` 17, `qa_crowd` 8, `qa_disengage` 11, `qa_hold`
13, `qa_ring` 16, `qa_far_wire` 15, `qa_far_render` 12, `qa_fog` 40, `qa_army`
18, `qa_res2` 45, `qa_squad` 46, `qa_ai` 34, `qa_ai2` 24, `qa_recon` 22,
`qa_group_grid` 15, `qa_tree` 21; `qa_formation` keeps its pre-existing red.

### Rules this pass adds

1. **Anything identical for the whole army must be read once per frame and
   passed down.** Eight such reads in one function cost more than a milliseconds
   at 3000. This is the "currency of the project" rule applied to the visual
   tick, where there had never been a profiler at all.
2. **Fold a switch into the value it gates.** `sprite_lod` off = infinite
   radius; `visual_smoothing` off = `k = 1.0`. The soldier then has neither the
   read nor the branch.
3. **Measure the update rate in seconds, not in frames, before calling a shard
   change a smoothness regression.** And know that "step jitter" rises with
   shard count by construction — cross-check it against the flicker metric,
   which measures artefacts rather than cadence.
4. **Split a function's prologue from its branches before porting it anywhere.**
   Three ports in this project were rejected on that measurement; this one was
   rejected before it was written.

## Documentation layout

Three files, one subject each — `README_ASSETS.md` and `MAP_ASSETS.md` described two *different* and both partly imaginary folder layouts and were merged:

- **`README.md`** — what the game is, controls, the loop, honest limitations.
- **`BALANCE.md`** — the tuning map: which number lives in which dictionary of which file, per subject (unit stats, veterancy, forge, AI, worker economy and map generation), plus which harness to run after touching each.
- **`ASSETS.md`** — where to put files, the frame-strip format, the fallback chain.
- **`CLAUDE.md`** (this file) — how the code works, what was measured, and which traps are already paid for.

## Harness lessons from the Aug 14 pass

- **`qa_ai` #7 was not flaky — it was the documented render/physics skew.** `_finish_sites()` awaited `process_frame`, so "240 frames" meant "as many as rendering manages", which in headless outruns the fixed 60 Hz physics and does so *further* the cheaper the frame gets. The AI's crew physically could not walk to the emergency foundation, and the check failed or passed depending on unrelated performance work. Now `physics_frame`; two consecutive runs green. **Any harness that waits for something to walk somewhere must await `physics_frame`.**
- **A parse error in a harness looks exactly like a hang.** `var lit := main.PLAYER_BASE_ANCHOR` — `main` is untyped, so the type cannot be inferred (the GDScript 4.6 gotcha already in this file) — the whole script fails to load, the scene gets no script, nothing prints and nothing ever quits. `print()` to a redirected stdout is block-buffered, so partial output does not appear either. **Diagnose with `--quit-after N` and read the HEAD of the log**, not the tail. Note `--headless --import` did not surface it.
- **`qa_garrison` and `qa_ai` both needed more patience for the same reason**: the gate moved to the drawn facade, so a squad may now walk around the building. Extending a wait is masking *only* if the thing under test never completes — here diagnostics showed the straggler honestly `MOVING`, 5.3 m short.
- **Three checks were repaired because the requirement reversed, not because code broke**: `qa_spear` A4 and `qa_spawnlane` D1 measured the gate against `front_dir()` — i.e. against the very rule that caused the bug, which is why they stayed green while it was live; `qa_hud5` B2/B6, `qa_sel2` A4/B2 and `qa_squad` #6 asserted the resource-bar and caption wording the owner has now reversed. Each was rewritten to assert the *new property*, and the count checks were re-pointed at the portrait badge, where the number actually lives now — not deleted.
- **`qa_far_wire` check 4 was flaky "about one run in three" for years, and the reason was in the harness's own arithmetic.** It parks "far" units at `lod_radius × 3` = 270 m while the map half-extent is ~71 m: the first step such a unit took clamped it to the map edge, i.e. back **inside** the LOD radius, and the check failed. Whether it took a step at all was the coin toss. `world_bounds_enabled = false` (points outside the map there are deliberate) makes it 0/15 every run. Raw teleports in it also now call `sync_row()`, per the documented rule — the visual tick reads the position from the SoA row, not from the node.
- **`qa_hudcam` F22 was testing its own fake.** It set `worker.state = GATHERING` with no target — a state the game never produces; `_process_gather` sees the empty target on the next tick, finds no work nearby and honestly returns the worker to IDLE, so it reappeared in the idle counter. It now issues a real `command_gather`.

## Performance rules (learned the expensive way)

**The currency in this project is the cross-object GDScript call, not arithmetic.** `Main.is_water()` returns `false` on a constant and still cost 0.61 µs/unit/frame through two hops; two `near_view()` calls per unit per frame were worth ~5 FPS on 810 models. Before optimising a hot function, count its calls out of the object, not its maths.

- **Throttles in place** (all real names): `RANK_RECHECK` 0.25 (phalanx only), `AGGRO_INTERVAL_HOT` 0.5 / `AGGRO_INTERVAL_CALM` 2.0, `RETARGET_RETRY_SEC` 0.2, `ANIM_EVERY` 3 (phase-offset by `_sep_phase = get_instance_id() & 7`), `SQUAD_FACE_TTL` 0.25, `perf_config.squad_target_ttl` 0.4, `FAR_WAKE_CHECK_FRAMES` 15, grid re-insert only past 20 cm of travel, terrain height only past 25 cm.
- **The aggro gate lives at the call site** (`tick_physics`, IDLE branch), not inside `_check_auto_aggro()` — the GDScript call itself cost more than the compare, and `check_auto_aggro` was once 88 % of the whole tick.
- **Shared per-squad scans:** `GameManager.squad_target_get/put` (one target search per squad, TTL 0.4 s) and `squad_enemy_pos/dir` (`_squad_face`, TTL 0.25 s). One 10 m scan per squad instead of ~441 cells per unit.
- **Cached instead of recomputed:** `_stance_holds_ground()` (memoised on the stance string — it was called up to 4× per unit per frame), `_base_speed()` (keyed on upgrade version + `vet_speed` + own `move_speed`), camera axes (`GameManager.camera_right/forward`), `Unit._seen`, `Unit._prof_on` (the profiling flag, read once per tick instead of per branch).
- **Never write a node property that has not changed.** `SpriteBase3D.set_flip_h`/`Sprite3D.set_frame` do not compare with the old value — every assignment queues a geometry rebuild. Animations run at 6–10 fps against a 60 fps game, so 5 of 6 assignments were setting the same value.
- **Profiling — two instruments, and they disagree on purpose.** `perf_config.profile_physics` + `prof_reset()`/`prof_add()`/`prof_report()` gives the **per-branch breakdown**, but it costs two `Time.get_ticks_usec()` calls *per branch per unit* — on 5000 men that is tens of thousands of calls a frame, and it inflates the total by roughly **1.8×**. Use it for **shares, never for absolutes**. The absolute number comes from `perf_config.tick_meter` (`tick_reset()`/`tick_add()`/`tick_ms()`), one usec pair **per frame** around the whole army walk in `GameManager._physics_process`; `vis_meter`/`vis_ms()` is its twin for the visual pass in `_process`. **`time_per_tick`, PASS/FAIL and anything quoted to the owner must come from the meters**, not from `!ВЕСЬ ТИК ЮНИТОВ`. `Performance.TIME_PHYSICS_PROCESS` is **useless** here: with `Engine.max_fps = 0` render ticks faster than the fixed 60 Hz physics rate, and two consecutive measurements of the same still scene gave 10.8 and 20.1 ms.
- **Squad-level batching of the step's obstacle queries (`GameManager._sweep_corridors`).** `_move_blocked` has to answer "is there a trunk near me" and "is there an enemy rank near me", and both cost a call out of the object *per marching unit per frame* — measured at `mb_trunk` 2.4 µs + `mb_enemyblock` 2.1–4.0 µs, over a third of the whole step. But a squad marches as a tight clump: fifty men were asking the same question fifty times. The question is now asked **once per squad per `CORRIDOR_TTL_MS` (200 ms)** over the squad's bounding circle, and the answer is *pushed down* into `Unit._clear_trunk` / `_clear_enemy` (same technique as `_push_catch_up`). A clear corridor means the unit makes **no call out of the object for the entire step** — only arithmetic and one `global_position` write. Measured: `mb_enemyblock` 2.1 → **0.11 µs**, `mb_trunk` 2.4 → **0.56 µs**.
  - The same `_clear_enemy` answer also short-circuits **both enemy scans** — the march-interception scan in `_process_move` and the IDLE auto-aggro in `tick_physics`. Both gates must still re-arm `_aggro_timer` themselves, or the branch is entered every frame instead of every 0.5–2 s.
  - Because of that, the corridor's enemy radius is `squad bounds + CORRIDOR_MARGIN + max(AGGRO_RADIUS, attack_range) + INTERCEPT_MARGIN` over the members — **an archer watches 20 m**, and a corridor sized only for `BLOCK_RADIUS` would have blinded exactly the unit that shoots furthest. The trunk radius stays at `squad bounds + CORRIDOR_MARGIN` (a trunk only obstructs a body).
  - `CORRIDOR_MARGIN` (8 m) covers closing speed during the TTL from *both* sides (~1.6 m at 4 m/s) with a large multiple to spare. Getting it wrong means marching through an enemy line, so it is deliberately generous, not tight.
  - Defaults are **`false` = "don't know, check for yourself"**: a unit with no squad, and any unit before its first push, takes the original full path. `remove_from_squad()` resets both flags — a stale `true` on an ex-member would be a permanent licence to walk through trees and enemy ranks.
- **Three caches tried here that did NOT pay, and were removed rather than kept** (measure, don't assume): folding the movement multipliers into an integer key in `_effective_speed()` (`mv_speed` 0.73 → 0.70 µs, i.e. noise — three multiplies are cheaper than building and comparing a key); a per-unit "no trunk in my 4 m cell" cache with a trunk-registry generation counter (`mb_trunk` 1.14 → 1.14 µs — on a forested map the 3×3 cell block almost always holds a tree, so the cache answered "don't know" precisely where it was needed); and **pushing the actual trunk *list* down from the squad corridor** instead of a bool, so the step could test a handful of `(x, z, r)` triples inline with no call out of the object at all (`mb_trunk` 1.13 → **1.71 µs**, whole-army marching tick 16.4 → **18.8 ms** — *worse*, and for the same reason as the cell cache: a squad's bounding circle is ~12 m and a forest puts **dozens** of trunks inside it, so the inline sweep beats a 4 m cell lookup that almost always examines one or two cells only when the list is tiny, which it never is. Lowering the cap just means the list is never used).
- **`Engine.max_physics_steps_per_frame = 1`** (`project.godot`, `[physics] common/max_physics_steps_per_frame`). The engine default is **8**: when a physics tick runs over budget the engine tries to *catch up* and runs up to eight of them in one frame, so an over-budget tick is multiplied, not merely late. Measured at 5000 marching men: a 28.9 ms tick produced **4.7 FPS** (≈ 212 ms/frame ≈ 8 × 28.9 — this, not the raw simulation cost, was the "5–6 FPS at 5000–6000" the owner reported). With the cap at 1 the same tick gave **16.2 FPS** and degrades as graceful time dilation instead of a death spiral. Do not raise it back.
- **The army tick is sharded across frames** (`perf_config.shards_for()`, `GameManager._physics_process` / `_process`). What holds a frame is the work *in one frame*, not the work per second, and 60 simulation updates per second per man is not needed in a mass battle. The army is split into `shards` groups by index in `_live_units`, **one group is walked per frame**, and that group is handed `delta * shards` — distance travelled, attack cooldowns and aggro timers are all delta-driven and come out identical; only the polling *rate* changes. The ladder is measured, not a ratio: **≤1500 → 1 shard (60 Hz, untouched behaviour), ≤3500 → 2, above → 3** (20 Hz). `tick_shards_force` overrides it for A/B runs. Index-stride iteration means skipped units are not touched at all; a death shifting the array moves a unit by one shard for one frame, which is harmless.
- **The visual tick is centralised too** — `Unit` no longer defines `_process()`; the entry point is `Unit.tick_visual(delta, frame)`, called from `GameManager._process` over the same `_live_units` and sharded the same way, *before* `far_units.flush()`. Rationale beyond the 5000 engine notifications: at 2 shards a unit only moves on every other frame, so on the frames in between the whole visual chain (LOD, walk bob, pose, MultiMesh slot) was recomputing an unchanged position. `set_process(false)` keeps its old meaning (`GameManager` checks `is_processing()`), but — exactly like `set_physics_process` — the engine no longer auto-enables it, so `Unit._ready()` must call `set_process(true)` explicitly. `Warrior` overrides `tick_visual`, not `_process`. The frame number is passed in because `Engine.get_process_frames()` was 5000 calls into the engine per frame for one shared integer.
- **Reference numbers** (`qa_march_perf`, 810 spearmen in frame, windowed, GL Compatibility, this dev machine; run-to-run spread is ±15 %): standing **132–158 FPS**, marching **121–141**, marching **while selected ~105**, ~387 draw calls, **0 physics bodies**. Marching physics tick ≈ **8.0 ms/frame** for all 810 *with profiling on*, `_process_move` ≈ 7.2 µs/call under the profiler. Before the Aug 6 batching work the same scene marched at **33 FPS** (30 while selected) with 516 draw calls. At 810 the shard count is 1, so this scene measures exactly the same code path as before the sharding work.
- **Scale reference** (`qa_mass_perf`, spearmen only, no enemies — measures whether the *logic* holds up, not the picture; **all numbers from the lightweight `tick_meter`, not the profiler**): marching whole-army tick **4.3 ms at 810** (1 shard), **9.3 ms at 3000** (2 shards), **11.7 ms at 5000** and **14.4 ms at 6000** (3 shards) against a 16.6 ms budget; standing 1.4 / 2.9 / 3.9 / 4.5 ms. The visual pass costs about the same again per render frame (3.8 / 9.4 / 10.4 / 13.2 ms), so the **headless main-loop ceiling** is 136 / 61 / 44 / 34 FPS. Per *update* the cost is flat at ~5–6 µs/unit, i.e. the architecture still scales linearly; the sharding buys the frame, not the per-unit cost. **Earlier reports of 30.5 ms at 3000 and 51.6 ms at 5000 came from the branch profiler measuring itself** — the honest figures for that same unsharded code were 15.7 and 28.9 ms.
- **The environment, not the units, is the draw-call problem at battle scale.** In `qa_mass_perf` the camera has to zoom out to hold 5000 men, and draw calls go 789 → 2017 while the army itself stays a handful of MultiMesh buckets. The extra ~1200 are trees/bushes as individual `MeshInstance3D`. Next rendering work belongs there, not in the unit path.

## Castle panel, order queue, and the tooltip standard

- **The Castle panel is a FIXED size** (`CASTLE_PANEL_W` 300 × `CASTLE_PANEL_H` 62), set directly in `_sync_panel_height()` instead of being derived from content like every other selection. The complaint it fixes: every queued order changed the content width, so the panel grew under the cursor and the hire buttons slid right between two clicks. `maxf` against content is kept only as an overflow guard — the queue can no longer drive it, because the yellow box has a constant footprint.
- **The order queue lives in a fixed yellow box** (`_queue_frame`, `QUEUE_BOX_INNER`). Cells are laid out as **one row** (`columns = n`) and `_queue_cell_side(n)` divides the box width among them, clamped to `QUEUE_CELL_MIN`/`MAX` — that is the "icons shrink proportionally but stay strictly inside" rule, and it holds by construction for any n up to `QUEUE_ORDER_MAX`. A `CenterContainer` sits between frame and grid: `PanelContainer` stretches its child, so without it the shrunk row would be pinned to the box's top-left corner with empty space under it. **Size is set on the frame, never on the grid** — a minimum on the grid would push `CenterContainer` to full size and there would be nothing left to centre.
- **`remove_child()` before `queue_free()` when a container's child count is read later in the same frame.** `_refresh_panel` cleared `button_container` with a bare `queue_free()`; freeing is deferred, so `_sync_panel_grid_widths()` at the end of that same call counted the old three buttons *plus* the new three and reserved a 6-column grid — ~95 px of empty tail on the Castle panel. Same trap already documented for `_rebuild_forge_grid` and `_rebuild_research_queue`; it is the single most common layout bug in this file.
- **The empty info column collapses.** The Castle writes "Замок N/N HP" into the panel header (`_update_castle_caption`, now pinned *inside* the top edge rather than floating above the panel), leaving `info_label` empty — but its `INFO_W` minimum still reserved 110 px of nothing mid-panel.
- **Tooltips open directly above the hovered icon** — one rule for the whole UI, via `_tip_anchor_geometry(anchor, width)` → `_pin_floater_above()`. The centre comes from the anchor's **real** `get_global_rect()`, not from `bx - (CARD_W - BTN_SIZE)/2`: `BTN_SIZE` is the plain order-button constant, and Castle/crew/forge buttons are all boosted, so the old formula missed the centre by more the larger the button. The bottom edge is pinned above the button and the box grows upward, so long text never reaches down over the panel.
  - **The forge tooltip is a deliberate exception** and stays to the *right* of its panel (`_pin_forge_tip`). The 5×4 node grid fills the panel's height, so a window above a top-row node would hit the ceiling and fold back over the grid; sitting beside the panel satisfies "must not cover the buttons" more strictly than the general rule, and matches the owner's mockup.

## Fog of war

`scripts/FogOfWar.gd` (+ `shaders/fog_of_war.gdshader`), created by `Main._setup_fog()` and published as `GameManager.fog`. **Three states, not two**: `lit` (someone of yours is looking at it right now — no fog, foreign units render), `seen` (you have been here — lighter pelt so the terrain/forest is remembered, but foreign units stay hidden), and unexplored (solid pelt). One cumulative state would have made "units in fog are not rendered" meaningless — a corner visited once would show everything happening there forever.

- **A mask texture, not per-source lighting in the shader.** GL Compatibility cannot carry hundreds of vision sources as uniforms, and per-pixel iteration over them is worse. The mask is one `MASK_CELL` (1.5 m) grid → 174×98 R8G8 pixels, rebuilt on CPU every `UPDATE_INTERVAL` (0.15 s) and uploaded whole; the shader does a single `texture()` fetch. R = lit, G = seen.
- **Sources are collapsed onto a coarse `SRC_CELL` (8 m) grid before stamping.** The naive "one disc per unit" costs πr²/cell² writes each — an archer with 60 m vision is ~2800 cells, and a hundred of them makes the rebuild the most expensive thing in the frame. One disc per occupied 8 m cell (largest radius wins) turns a packed 20-man squad into one or two discs. The stamped radius gets `SRC_CELL * 0.71` added because the disc is drawn from the cell's centre but must cover anyone standing anywhere in it.
- **Discs are composited with `max()`, and the rim is feathered** (`EDGE_FEATHER` 3 m). Plain overwrite made a later disc's pale rim erase an earlier disc's bright interior — a dark seam along every overlap. `sqrt` runs **only** inside the rim band; the interior is a squared-distance compare.
- **Vision radius = `3 × attack_range`** (`unit_stats_config.vision_radius`, `VISION_MULT`). `VISION_MIN` (18 m) is a mandatory floor, not a fudge: melee `attack_range` is ~1.6–1.8, so the bare formula gives a swordsman 5 m of sight on a 260×146 map — an all-infantry army would walk blind. Buildings and construction sites use `BUILDING_VISION` (42 m) since they have no attack range.
- **Foreign units in fog are removed from rendering entirely**, not dimmed: `Unit.tick_visual` early-returns through `_hide_in_fog()`, which unregisters the MultiMesh slot. The check runs **only for non-player factions** — your own units are the vision sources, so they are always lit and asking would be paying for a known answer.
- **Foreign BUILDINGS hide by `is_seen`, units by `is_lit` — and that difference is the whole scouting mechanic.** A building is immobile, so once found it must stay on the map as a last-known position under the grey pelt (`Building.set_fog_hidden`, driven from `FogOfWar._apply_enemy_building_visibility()` on the mask's own tick). Gating buildings on `is_lit` like units would make the enemy castle blink out every time a scout stepped back, and scouting would mean nothing. Units keep using `is_lit`, so troop movement and new production under that same pelt stay hidden — exactly the owner's split. Hiding also **zeroes `collision_layer`**: selection raycasts walk layers, not visibility, so an invisible building would otherwise still be clickable and the player could find the enemy base by poking the black. `Building._ready()` hides itself via `call_deferred` (position is assigned after `add_child`, so `_ready` still sees the origin — the same trap `ResourceNode._register_trunk` documents), otherwise a newly built enemy structure flashes on screen for one frame before the next mask rebuild.
- **The sleeping-unit trap applies here too** and is handled in the same sweep as the LOD one: a unit that fell asleep while visible never ticks again, so it would stay drawn through fog that later rolled over it. `GameManager._wake_returned_far_units()` now wakes on *either* condition.
- **The fog plane is `depth_test_disabled` at y = 0.05.** It has to cover 5 m trees and buildings, so it cannot rely on depth; it sits nearly on the ground rather than high up because the camera is orthographic at 45° and any real height would visibly parallax the pelt off the terrain it hides. `render_priority = 8` puts it after vegetation (0) and units (1).
- `enabled = false` makes `is_lit()` answer true everywhere — that is how a harness isolates another mechanic (`qa_far_wire` does exactly this, since half its units are enemies parked in unexplored territory).
- Covered by **`qa_fog`** (30 checks: camera start, mask coverage, pre-revealed pad, the radius formula and its floor, reveal/remember/hide transitions, free first castle, the building crew).

## First castle and the starting crew

The first castle is **free** and is placed by the player inside a green pad in their corner (`_show_start_zone()`, the same square `clamp_to_player_start()` enforces — the hint must not disagree with the rule it depicts). The pad is drawn with a *very weak* additive wash: plain 16 % alpha green was invisible on green grass, and full-strength additive flooded the whole screen, because the match now opens fully zoomed in and every visible metre is inside the pad.

`_spawn_starting_workers()` spawns `START_WORKER_RESOURCES.size()` (4) workers **with the foundation** and gives each `command_build(site)` — they raise the castle first and only scatter to resources from `_on_castle_built()` → `_send_starting_workers_to_resources()`. The crew is tracked in `Main._start_crew` so that dispatch hits *that* crew and not whoever the castle has hired since. `ConstructionSite.self_building` is deliberately **left on** as a backstop: if the crew is killed or ordered away the castle still finishes and the match cannot dead-end, and the flag is inert while `builder_count() > 0`.

## Known caveats

No pathfinding/avoidance (straight-line movement), no multiplayer, no save games. Fog of war **exists** (see its own section). Faction choice in the menu only switches sprite folders (only `humans` has content). Scaling: hot paths (target search, phalanx rank counting, enemy-line blocking) go through `GameManager.unit_grid` (`SpatialGrid`, cell 1.0, plus a coarse 16 m layer with per-faction counts for early-outs) — keep it that way. The remaining ceiling is per-unit GDScript interpreter overhead in `_process_move`, so the "10,000 units" goal still needs flow-field / batched movement; centralised update loops (physics **and** visual), frame sharding and MultiMesh rendering are **done**, and 5000–6000 now fit the frame budget. Sharding has a floor: 3 shards is 20 updates/s per man, and going lower would make a single step visible as a jerk up close — past 6000 the next win has to come from the step itself, not from polling less often. Set `attack_target` only via `set_attack_target()` (died-signal cleanup). `addon.py` in the repo root is a Blender asset-pipeline tool, not part of the game.

**`qa_audio2` C1 is the same kind of broken absolute-time assertion as `qa_bugpack2` 9b, and it fails on an idle machine too — do not chase it.** It claims "sound adds less than 1 ms per frame in a mass battle". Measured A/B on identical code: with a one-line change 8.20 / 8.34 / 8.99 ms, with that line reverted 8.43 / 8.28 / 8.36 / 8.55 ms — the same distribution — while one run right after `--import` reported **−0.840 ms** (i.e. the "with sound" frame came out *faster* than the control). A metric that swings ~9 ms on unchanged code, and goes negative, is not measuring the thing it names. The pattern seems to be that the first run after a re-import passes and later ones fail, so a green C1 is as meaningless as a red one.

**`qa_bugpack2` 9b measures ABSOLUTE wall-clock time and fails on a loaded machine — always re-run it alone before believing it.** It asserts "the DEFENCE stance fits a 5 ms frame budget on 300 men". With other Godot instances alive it reported 6.4–6.8 ms and, in one run, an *attack*-stance figure of 13.58 ms against 6.39 ms in the previous run — the same measurement, twice, differing 2×. Alone on an idle machine it reads 4.73 ms and passes. Two practical consequences: `qa_world3` runs for **~7 minutes by construction** (a hard-coded 300 s wait at Test.gd:1095 plus a 60 s one at :1030), so killing it on a shorter timeout leaves a headless process running and quietly poisons every timing measurement afterwards; and `Get-CimInstance Win32_Process -Filter "Name LIKE '%Godot%'"` is the way to tell your stuck harnesses (`--headless --path . res://qa_*`) from the owner's editor (`--editor`) before killing anything.

**Known-red harnesses that are stale, not regressions:** `qa_world2` C5/C7 (assert a minimum gap between allies pressed against the map wall — allies deliberately overlap, see "Allies never push each other"), `qa_queue2` 6a/6b/6e/7a/12d (synthetic real mouse events into the HUD), and `qa_bugpack2` 6f (compares `_block_formation_slots()`'s preview against the `move_target`s left by `_execute_line_formation()`; fails **deterministically** with "расхождений 11, макс 32.491 м" on every run, i.e. an ordering/blocking difference between preview and execution, not a flake — **not yet root-caused**, and untouched by the two-level-selection pass).

**Two harnesses were red because the camera now opens at the player's base, fully zoomed out** (`Main.start_game()` → `jump_to(PLAYER_BASE_ANCHOR, max_height)`, changed an earlier session) — both are now fixed and are worth recognising, because any harness that assumes the camera sits at the origin will fail the same way: `qa_far_wire` 1/3/4 set the LOD view point once with `update_view_point(Vector3.ZERO)`, but `RTSCamera._process` overwrote it every frame from the real focus hundreds of metres away, so a unit at (5, 0, 5) measured as *far* — the fix is to `set_process(false)` on the camera first (check 4 additionally needed `wake_for_lod()` after its raw teleport, the documented sleeping-unit case). `qa_world` 1c dragged the middle mouse button from wherever the camera happened to be; at max zoom-out in a map corner `_clamp_focus()` already has the focus pinned on both axes, so dragging further into the corner honestly moves it 0 m — the fix is `jump_to(Vector3.ZERO, min_height)` before the drag.

`qa_bugpack` 9a/9c/9d were in that list and are **fixed**: 9a asserted a hard-coded 18 HP/s garrison heal against the config's 1.0. It now derives everything from `_UCfg.GARRISON_HEAL_PER_SEC` — the wound depth is `rate × 3 s` (so the wait scales with the balance sheet instead of timing out at a fixed 9 s), and a new 9e measures the *actual* heal rate and compares it back against the config.

`qa_fix` #1 was also red and is **fixed the same way**: it compared `spr.position.y` across directional sheets, but with MultiMesh on, `Spearman._apply_dir_tex` returns before touching the node and the vertical anchor lives in `Unit._sprite_base_y` — the harness saw one identical value on all eight sheets ("расхождений=8"). It now reads `_sprite_base_y`, which is the documented owner of that number.

**Стенды краснеют от смены требования чаще, чем от поломки кода — это самый частый случай в проекте.** Каждый раз, когда владелец разворачивал решение (баннер выделения, плашка бездельников, звезда отряда, ширина панели, точка выхода из здания, стойка «Защита»), краснели ровно те проверки, которые утверждали ПРЕЖНЕЕ требование. Правило: прежде чем чинить код по красному стенду, посмотрите, не утверждает ли проверка то, что владелец только что отменил, — и перепишите её на СВОЙСТВО, а не на число. Отдельно стоит помнить два типовых источника ложной красноты: проверка, читающая узел `Sprite3D` (в общей отрисовке он невидим, и правда живёт в полях `Unit._sprite_base_y` / `_flip_h_state` / `_anim_name`), и проверка, ждущая `process_frame` там, где нужно `physics_frame`.

**Intermittent, not a regression:** `qa_approach_intercept` #2 and `qa_formation` B1 fail roughly one run in three with no code change — the `Engine.max_fps = 0` render/physics timing skew already documented above (B1 reports a 0.25 m spread on a bad run, 0.12–0.13 m otherwise). Re-run before investigating. Two more belong in this list:
- `qa_rally2` A1/Bб — 0 to 2 failures across identical runs. **Сюда же F2**
  (авг. 2026): «отряд доходит до зажатой точки» требует d <= 3 м, а меряется
  23-25 м. Проверено A/B при добавлении разведения отрядов
  (GameManager.free_squad_spot): с ПОЛНОСТЬЮ выключенным разведением те же
  23.76 м, то есть к нему отношения не имеет.
- ~~`qa_ai` #6~~ — **FIXED Aug 15 2026 and no longer random.** It used to assert the depth offsets of a *named* tactic while `tactic_for_wave()` calls `randi()` when `TACTICS_IN_ORDER` is false, so the verdict depended on the roll. With the single battle order (see "Big-battle pass at 2500+ units") the check is one invariant for all tactics — spearmen in front, archers behind, warriors on both flanks — and it is reproducible by construction.


## Натиск, продавливание, разведение отрядов и вечные трупы (авг. 2026)

Пакет из семи заказов владельца за один заход. Ниже — только то, что не
выводится из кода: замеры и развороты решений.

### Здание как цель: сломано было НЕ то, на что жаловались

Жалоба: «лучники и пехота не могут выбрать вражеские здания кликом как цель для
атаки». Зонд (`qa_bldattack`, блоки A–C) показал, что ВЕСЬ боевой путь работал и
до правки: маска клика включает `LAYER_BUILDINGS`, `_pick_at` возвращает
постройку, ПКМ доходит до `command_attack`, лучник по бараку стреляет и сносит
его, копейщик подходит и рубит. Ни одной строчки чинить в этом не пришлось.

Не было ДВУХ вещей, и обе — про то, что игрок ВИДИТ:

1. **Обратной связи.** Весь путь подсветки написан под `pick["target"] as Unit`
   и на постройке молча отдавал `null`: наведясь на вражеский барак, игрок не
   получал ни красного кольца, ни какого-либо иного признака, что клик вообще
   что-то сделает. Единственным способом узнать было кликнуть и смотреть,
   полетят ли стрелы. С точки зрения игрока это неотличимо от «здание нельзя
   выбрать целью» — и именно так и было названо в заказе.
2. **Честной дистанции.** `global_position` постройки лежит в ЦЕНТРЕ коробки, а
   коробка замка — восемь метров. Пока дистанция считалась до центра, «дойти на
   дистанцию удара» означало для копейщика с его 2.5 м войти ВНУТРЬ здания
   (масок столкновений в проекте нет, он туда честно заходил), а для лучника —
   встать в четырёх метрах от стены вместо двадцати. Замер после правки:
   копейщик встаёт на 6.50 м от центра при стене на 4.00.

Вывод на будущее: жалоба «не работает» на механику, которая работает, почти
всегда означает «не показывает, что работает».

### Толчок раз в десять ударов — это механика, которой на экране нет

`PUSH_EVERY` стоял 10 с обоснованием «шеренга давит плавно, а не рывками».
Плавность он давал вместе с полной невидимостью: копейщик бьёт раз в 2 секунды,
значит толчок срабатывал раз в ДВАДЦАТЬ секунд и двигал строй на пять
сантиметров. Заказ «включить постоянный расчёт push_force» переведён буквально —
на каждый удар.

Плавность при этом обеспечивает не редкость толчка, а его РАЗМЕР: шаг зажат
сверху 0.4 м и умножен на `PUSH_GLOBAL_SCALE` 0.35. Паритет при равном напоре
сломаться не может по построению — `_apply_push` выходит на неположительной
разнице (`qa_push` B1).

**Цена и как она была отбита.** `qa_mass_battle` на 5000 бойцов: переход на
«каждый удар» стоил около миллисекунды фазы свалки. Считается там не толчок, а
`_push_power()` / `_stand_power()` — два чтения таблицы бонусов в автозагрузке и
два поиска в таблице стоек, и всё это дважды (свой и чужой) на КАЖДЫЙ удар.
Величина же меняется считанные разы за партию. Кэш по ключу
«версия бонусов + стойка + мораль + push_force» (`Unit._refresh_power`, приём
скопирован с `_base_speed`) вернул время обратно: итоговый чередующийся A/B
даёт 15.77 → 16.03 мс свалки, то есть разницу внутри разброса прогонов.

**Что пробовали и НЕ оставили.** Дописывать точку толчка в колонку ядра
(`set_pos` на цель и на себя) прямо в `_apply_push`: разбор наложения читает
колонку, а не узел, и до ближайшего тика цели видит отброшенного на старом
месте. Подтвердить пользу замером не вышло — `qa_mass_battle` в этой фазе
разбрасывает от 14.5 до 16.5 мс на НЕИЗМЕННОМ коде, то есть разброс прогонов
шире любого наблюдавшегося эффекта. А польза и не нужна: строка сходится сама на
ближайшем тике (дерущийся боец тикает каждый кадр или через кадр), и толчок
накапливается — `qa_cavalry` E1 даёт 42 сдвинутых из 46 живых, худший на 7.9 м.

### Натиск конницы: почему разгон взводится один раз

Первая версия взводила `is_charging` всякий раз, когда цель оказывалась ближе
`charge_range`. В свалке цель меняется каждые пару секунд, и «первый контакт»
наступал бы снова и снова, не сходя с места: кабан снимал бы по половине
максимального запаса с каждого следующего соседа подряд. Поэтому `_charge_ready`
гаснет ударом и возвращается ТОЛЬКО когда всадник снова оказался дальше
`charge_range` от цели, то есть реально оторвался и разогнался заново.

Отбрасывание сделано прямым смещением, а не импульсом: физтел в игре нет вовсе,
скорость никем не интегрируется между кадрами, и импульс потребовал бы своего
поля и своей ветки в тике ради эффекта длиной в доли секунды. Направление —
преимущественно ВБОК: строй должен разойтись, открыв проход, а назад его двигает
постоянное продавливание, и дублировать его здесь означало бы удвоить ту же силу.

### Разведение отрядов: почему НЕ отталкивание центров

Заказ звучал как «добавить физическое отталкивание между центрами отрядов».
Сделано иначе, и вот почему. Центр отряда — величина производная (медиана по
осям, `GameManager._centroid_of`), и двигать по ней людей означало бы завести
вторую, параллельную механику перемещения: с силами, с затуханием, с борьбой
против разметки строя. Ровно от этого в проекте однажды уже отказались —
см. «союзники друг друга не толкают» у `Unit.SEP_MIN_DIST`.

Вместо этого разбор наложения научился различать «сосед по шеренге» и «боец
чужого отряда»: одно сравнение `int` на соседа, норма шире в `SEP_CROSS_SQUAD`
раз. Ничего нового в механике не появляется вовсе — та же монотонная поправка,
тот же такт, та же мёртвая зона. Строй ВНУТРИ отряда остаётся ровно таким же
плотным, каким был; шире расходится только граница между отрядами.

Заодно исправлено расхождение, из-за которого «тысяча бойцов не держит ширину
строя»: личный круг выводится из самого плотного строевого интервала в проекте,
но был выведен из 0.35, а сам интервал (`Building.squad_spacing`) с тех пор
подняли до 0.55 — радиус за ним не поехал. Теперь `PERSONAL_RADIUS` 0.25, и
вместе с ним обязан был подняться `ARRIVE_RADIUS` (жёсткая связь: допуск
прибытия обязан быть БОЛЬШЕ личного круга, иначе боец, идущий в занятую точку,
никогда не отчитается о прибытии).

**Цена:** `qa_mass_perf` на 5000 — 4.76 → 4.91 мс стоя и 10.56 → 10.62 мс на
марше, то есть внутри разброса.

**Стенд `qa_settle` E2 покраснел и это НЕ регрессия.** Он ждал 3 секунды и мерил
дрожание кучи из 240 бойцов, собранной из ШЕСТИ отрядов; при расширенной норме
куче нужно больше места, и через 3 секунды она ещё расходится. При ожидании 15
секунд дрожание той же кучи равно 0.00000 м — куча встаёт насмерть, просто
позже. Срок ожидания в стенде теперь ВЫВОДИТСЯ из норм (`settle_ms`), а не стоит
числом.

**А вот замер «сваливаем всех в одну точку» мерил не то.** Первая версия
`qa_push` D сваливала два отряда в одну точку и получала зазор 0.19 м вместо
0.67. Разбор: у бойца в середине идеально симметричной кучи соседи стоят со всех
сторон и их поправки почти взаимно гасятся — за 4 секунды куча проходила 0.35 м
при потолке 3 м, то есть меньше десятой доли возможного. Мерить надо
РАВНОВЕСИЕ, а не переходный процесс: теперь два готовых строя ставятся плечом к
плечу, и проверяется, что разошлась именно граница между ними (0.60 м) при
неизменном внутреннем строе (0.40 м).

### Тела: пять тысяч, четверть часа и полминуты разложения

Потолок поднят с 500 до 5000. Число вызовов отрисовки от потолка не зависит
вовсе — оно равно числу РАЗНЫХ ЛЕНТ на поле (`qa_shotcorpse`: 55 вызовов на
завале и до правки, и после). Растут две статьи, и обе прижаты:

* **подача буфера.** `set_buffer` гонит бакет целиком — 320 КБ на пять тысяч
  тел. Поэтому доля разложения уезжает в буфер шагами `DISSOLVE_WRITE_STEP`
  (десять раз в секунду вместо шестидесяти), а полностью неподвижное поле не
  подаёт буфер вовсе;
* **обход очереди.** Срок жизни у всех один, а очередь упорядочена по времени
  укладки — значит истекает он строго по порядку, и проверять надо ровно голову
  (`_scan`), а не все пять тысяч. Снятые места выбрасываются пачкой (`_compact`),
  а не `erase` по значению: тот стоит прохода по всему списку на каждое тело.

Часы у слоя СВОИ, а не `Time.get_ticks_msec()`: на паузе тела обязаны лежать, а
не доживать свои пятнадцать минут за спиной у игрока. Стенду те же часы дают
возможность не ждать четверть часа взаправду (`age_shift`).

Разложение — не просто прозрачность. Тело, начавшее редеть с первой секунды
фазы, полфазы стоит полупрозрачным, и на завале сквозь него видно соседние тела.
Поэтому сперва оно землеет и темнеет, а дизер включается позже
(`dither_start`). Бурый ЗАМЕЩАЕТ обесцвеченный тон, а не подмешивается к
исходному: подмес дал бы грязь поверх рисунка — та же причина, по которой
притенение слоёв сделано умножением.

Растворений в слое теперь ДВА, и путать их нельзя: `DISSOLVE_SEC` (30 с) —
штатное разложение по сроку жизни, `FADE_SEC` (2 с) — спешное вытеснение по
потолку. Доля в буфер считается от СВОЕЙ длительности (`Corpse.fade_total`),
иначе вытесненное тело прыгало бы на пятнадцатую долю сразу.

### Стенды, покрасневшие от разворота требования

* `qa_cavalry` B2 требовал, чтобы период толчка у конницы был СТРОГО МЕНЬШЕ
  пехотного. С постоянным расчётом напора пехота подтянута к конному темпу, и
  проверка краснела ровно оттого, что заказ выполнен. Переписана на то, что
  осталось истинным: напор считается постоянно, конница не толкает реже пехоты,
  а её преимущество живёт в размере шага (B1/B3) и в натиске (блок F).
* `qa_cavalry` F7 («лобовой навал на копья не отбрасывает копейщика») мерил
  смещение за всё ожидание и намерил 1.23 м при разлёте 2.2 — почти провал.
  Двигал копейщика там не натиск, а обычное продавливание: у кабана
  `push_force` 15 с множителем 3.5, и толкает он теперь на каждый удар. Натиск
  же — событие ровно одного кадра, и в этом кадре бойца не бьют вовсе
  (`_process_attack` выходит сразу после удара с разгона). Проверка переведена
  на дельту за тот единственный кадр: стало 0.00 м.

## Знамёна ветеранства вместо звёзд (авг. 2026)

### Главное решение: знамя — ТЕКСТУРА, а не геометрия

Звезда ветерана строилась процедурной геометрией, и первым порывом было сделать
знамя так же — треугольниками с вершинными цветами. Отказались из-за ВТОРОЙ
половины заказа: упавшее знамя обязано запекаться в тот же `MultiMesh`, что и
тела, и наследовать их срок жизни с разложением.

Слой тел не знает слова «труп»: он умеет ровно одно — класть плашмя КВАД С
ЛЕНТОЙ и гасить его по времени. Знамя-из-треугольников туда не положить никак;
пришлось бы заводить свой слой, свой шейдер растворения и свой таймер, то есть
второй экземпляр всей машинерии тел. Знамя-текстура ложится ТОЙ ЖЕ СТРОЧКОЙ,
что и павший копейщик, и получает потолок, вытеснение, пятнадцать минут, дизер
и пятно тени даром.

Побочная выгода оказалась не меньше основной: живое знамя и упавшее — ОДНА И ТА
ЖЕ картинка, и разъехаться по виду они физически не могут.

Пробовали и обратный порядок — оставить геометрию, а для упавшего завести
отдельный `MultiMesh` с вершинными цветами. Уперлись в кодировку: слой тел гонит
долю разложения через instance-цвет (`COLOR.b`), а у меша с вершинными цветами
`COLOR` — это произведение вершинного на instance-цвет, и разделить их в шейдере
нечем. `custom_data` в GL Compatibility непригоден (открытый баг, из-за которого
и `mm_unit_sprite`, и `mm_corpse` сидят на `use_colors`).

### Грабля: укладка знамени приходит из `_exit_tree`

Первый прогон дал `Parent node is busy setting up children, add_child() failed`.
Разбор: знамя падает, когда выбыл ПОСЛЕДНИЙ боец, а узнать об этом можно только
в `remove_from_squad` — то есть в `Unit._exit_tree`, когда движок перестраивает
дерево. Слою тел `add_child` в этот момент нужен: первое тело каждой ленты
заводит свой `MultiMeshInstance3D`.

Обычные трупы этой грабли не знают, потому что ложатся из `take_damage`, посреди
физического тика, — и именно поэтому она не всплывала раньше ни разу.

Лечение: уровень и точку падения снимаем СИНХРОННО (через кадр записи о них уже
нет — отряд стирается следующей же строкой), а саму укладку откладываем
`call_deferred`. Та же грабля и то же лечение, что у ворот замка
(`Building._ensure_spawn_point`).

### Последняя точка отряда пишется на каждом выбывшем

Знамя обязано упасть там, где пал последний боец. Но узнать, что боец
последний, можно лишь ПОСЛЕ `members.erase(unit)`, а к этому моменту его узел
уже уходит из дерева. Поэтому `squads[sid]["last_pos"]` обновляется на КАЖДОМ
выбывшем — одна запись `Vector3` на выбывшего, и вопрос закрыт без единой
проверки «а не последний ли он».

### Размер знамени подбирается только глазом

Считать его в метрах бессмысленно: на экране высота билборда домножается ещё и
на компенсацию наклона камеры (`BillboardUtil.V_STRETCH` ≈ 1.41), и «сколько
метров» с «сколько пикселей рядом с копейщиком» — разные вопросы. Первый подбор
(`PIXEL_SIZE` 0.011) дал знамя на четверть выше копий: пика знаменосца читалась
не как пика, а как мачта. 0.0091 при `CENTER_Y` 1.34 ставит полотнище чуть выше
остальных копий строя. Судится это на `qa_banner/Shot` и больше нигде.

### Стенды, покрасневшие от разворота требования

Всё те же семь штук, и все — про то, что метка ветеранства сменила природу:

* `qa_vet` 2в/4/4б/6 и `qa_sel2` A5/E — считали ЛУЧИ ЗВЕЗДЫ и звёзды «★» в
  подписи. Переписаны на «под какой грейд построено знамя» и на значок ранга из
  конфига (`veteran_badge_text`), а не на свою копию шкалы.
* `qa_vet` «звезда стоит по центру масс отряда» и `qa_sel2` E6 — требование
  ОБРАЩЕНО. Звезда была меткой над отрядом и висела над средней точкой, то есть
  над местом, где может вообще никого не быть; знамя — предмет в руках бойца, и
  стоять обязано НА ЗНАМЕНОСЦЕ. Новая проверка сверяет знамя с
  `draw_position()` носителя и отдельно убеждается, что это не совпало с
  центром случайно (`E6б`: у растянутого облака знаменосец и центр — разные
  точки).
* `qa_vet` 4в «звезда перевешена на живого бойца» — проверка существовала, но
  ничего не проверяла: звезду к тому времени уже вынесли в мир, и её
  «носителем» был `get_parent()`, то есть всегда один и тот же узел мира.
  У знамени носитель настоящий, и блок наконец мерит заказанное: знамя перешло,
  перешло к БЛИЖАЙШЕМУ к павшему, грейд не потерялся, сам узел не пересоздан.
* `qa_sel2` E8/E9 — «звезда вдвое крупнее прежней» и «ранги 1-3 бронзовые».
  Заменены на то, что осталось истинным: знамя это ОДИН квад (а не поверхность
  на фигуру) и формы грейдов идут вымпел → «ласточкин хвост» → штандарт.

## Проход по скриншотам владельца: знамёна, заслон ИИ, контур зданий, конец партии (авг. 2026)

Шесть точечных правок по присланным скриншотам. Ниже — только то, что не
выводится из кода.

### «Пехотинцы телепортируются при таране» — виноват был не удар

Первое подозрение (нужен импульс и его затухание) оказалось неверным. Спрайт
бойца и так догоняет тело плавно; у сглаживания есть предохранитель: прыжок
дальше `VIS_SNAP_SQ` = 2 м считается телепортом и рисуется мгновенно — иначе
спрайт полз бы через полкарты после гарнизона или постановки стендом.
Отбрасывание при таране равно `charge_knockback` = **2.2 м**, то есть ровно ЗА
этим порогом. Удар честно двигал бойца, картинка честно перескакивала.

Лечение вышло в три строки: метка `_fling_left` на полсекунды, и пока она жива
— предохранитель пропускается, а доля догона берётся своя, помедленнее. Поле
скорости с затуханием тут было бы дороже эффекта: физтел в игре нет вовсе, и
интегрировать её было бы некому, кроме специально заведённой ветки в тике.

Стенд проверяет обе половины: боец помечен летящим И его нарисованная точка
отстаёт от логической (`qa_cavalry` F5в), плюс отдельно — что разлёт вообще
дальше порога, то есть без метки картинка бы перескочила (F5г). Второе важнее
первого: подними кто-нибудь `VIS_SNAP_SQ` — и проверка честно покраснеет, хотя
код не менялся.

### «Куча в центре» у заслона ИИ — арифметика, а не поведение

Ширина заслона стояла числом: `SCREEN_WIDTH` = 18 м на весь фронт, а место
отряда считалось как доля от неё. При `HOME_GUARD_PER_TYPE` = 7 семь отрядов
копейщиков получали центры в **2.6 м** друг от друга — при том что отряд из
шестидесяти человек занимает около трёх метров в ширину и почти шесть в глубину
(6 колонок × 0.58 м). Места перекрывались физически, четыреста бойцов сходились
в одну точку, расталкивание их разбрасывало, следующий такт размышления гнал
всех обратно в те же перекрытые точки. Отсюда и «сжатие → выталкивание →
сжатие» без конца.

Теперь шаг ВЫВОДИТСЯ из ширины самого отряда (`_screen_step` = колонки ×
интервал + просвет) и вышел 5.68 м против 2.57. Не поместившиеся в
`SCREEN_MAX_WIDTH` уходят во второй эшелон, а не втискиваются в линию.

**Первая версия этой правки сломала другое требование.** Фланговых мечников я
разнёс по ГЛУБИНЕ — каждая пара на `SCREEN_ROW_DEPTH` назад, — и на шести
отрядах третья пара ушла ЗА ЗАМОК: глубина по курсу на врага вышла −4 м. Заслон
стоит МЕЖДУ замком и противником, и `qa_ai` поймал это своей проверкой «ни один
пост не смотрит в тыл». Фланги теперь расходятся вширь, а эшелоны зажаты полом
`SCREEN_MIN_DEPTH`. Проверка была права, код — нет.

### Толстый угловатый контур под зданием — цена растянутого чужого меша

Контур цели рисовался кольцом БОЙЦА в масштабе: тор радиуса 0.35 с трубкой в
4 см и **двенадцатью** сегментами по окружности. На бойце двенадцати сегментов
не видно — круг размером с ладонь. Замку нужен масштаб ×11, и масштаб тянет
всё: трубка становится 46 см, а двенадцать сегментов превращаются в
двенадцатиугольник. Ровно это и было на скриншоте.

Разные меши в одном `MultiMesh` не живут (буфер хранит трансформы, меш у слоя
один), поэтому у зданий теперь свой слой и свой меш: тор ЕДИНИЧНОГО радиуса,
тонкий, о 64 сегментах. Масштаб равен половине габарита постройки, то есть
трубка выходит 2-5 см на любом здании. Слой ленивый — пока ни на одну постройку
не навелись, узла нет и вызовов отрисовки он не стоит.

### Знамёна: что именно увеличивать

Заказ «увеличить знамёна на 50%» нельзя выполнять подъёмом `PIXEL_SIZE`: он
тянет ВЕСЬ холст, включая древко, и пика знаменосца снова превращается в мачту
(это уже ловили при первом подборе размера). Растёт полотнище — `FLAG_H` /
`FLAG_LEN`, а у штандарта `STD_*` вдвое. Холст при этом пришлось расширить с 80
до 128 пикселей, и вот тут вылезла бы вторая грабля: сдвиг знамени над бойцом
считается от разницы «центр квада — центр древка», и зашитая константа после
расширения оставила бы знамя висеть мимо знаменосца. Сдвиг теперь ВЫВОДИТСЯ
(`BannerArt.pole_offset_px`).

Две мелочи из той же серии:
* вымпел сужался только снизу, верхняя кромка шла прямой до конца — на экране
  это читалось не треугольником, а флагом с обрезанным краем. Сходятся обе;
* лычка, смотрящая ВЛЕВО, при общей базе с правыми упиралась в древко и
  срезалась проверкой «рисовать только по полотнищу»: база — это ОСНОВАНИЕ
  шеврона, а остриё уходит от неё на пол-высоты в сторону `chevron_dir`.
  Левосмотрящим база сдвинута на эту же половину вправо.

### Знаменосец возвращается по МЕСТУ В РАЗМЕТКЕ, а не по текущей точке

Возврат на левый фланг повешен на смыкание рядов — оно и есть «конец
экшн-сцены». Но выбирать там по текущим координатам нельзя: смыкание ТОЛЬКО ЧТО
раздало приказы, и никто ещё не сделал ни шагу — бойцы стоят так, как их
разбросала свалка. Выбор идёт по `post_pos` (`_bearer_anchor`), то есть по
месту, которое боец займёт.

### Крепость «уходит в режим повторной постройки»

Две независимые причины, обе честные:
* `EnemyAI._no_castle` проверял только ДЕНЬГИ. Фундамент вставал, попадал в
  группу зданий фракции, а достроить его без единого рабочего некому — и
  условие победы («у врага не осталось ни зданий, ни юнитов») переставало
  выполняться навсегда;
* само условие требовало ПОЛНОГО отсутствия зданий, то есть висело, пока игрок
  не обойдёт карту за последним домиком.

Теперь закладка требует живых юнитов, а победа считается по снесённой ГЛАВНОЙ
КРЕПОСТИ при отсутствии живых. Живые считаются проверкой `is_dead()`, а не
размером группы: павший уходит из неё лишь в конце кадра.

### Стенды, покрасневшие от разворота требования

`qa_vet` 6 — проверяли, что в заголовке панели стоит ЗНАЧОК ранга. Владелец
развернул: «убрать символьные лычки из заголовков UI», название собирать
словами («Отряд закалённых лучников»). Проверки переписаны на новое требование
— в заголовке ЕСТЬ звание и НЕТ значка. Значок остался там, где на слова нет
места: на портрете и на карточке отряда.

## Бой: качели отхода, петля погони, замок обороны и лучники (авг. 2026)

### «Качели» ИИ: решение принималось и тут же отменялось

Отряд подходил, получал стрелы, начинал убегать, разворачивался и умирал в
спину. Роль ROLE_RETREAT сама по себе была липкой (`_try_retreat` возвращает
true, если она уже стоит), но этого мало: замка нужно ДВА, и они в разных
местах, потому что решение и его исполнение живут порознь.

* **Решение** держит `_retreat_locked` в `_set_role`. Это ЕДИНСТВЕННАЯ точка,
  через которую роли вообще меняются, поэтому одной проверки хватает на все
  пути сразу — и на раздачу постов гарнизона, и на боевой порядок, и на
  тактические переопределения.
* **Исполнение** держит `Unit.retreat_locked()`. До бойца доходят приказы не
  только от ИИ: смыкание рядов, сплочённость, возврат на пост — и КАЖДЫЙ звал
  `command_move` без `keep_retreat`, то есть гасил `retreating`. Роль при этом
  оставалась «отход», а боец разворачивался и шёл драться. Ровно это и видно
  на экране как разворот на 180°.

Сроки держатся одним числом на обоих концах (`Unit.RETREAT_LOCK_SEC` =
`AICfg.RETREAT_MIN_SEC`): два замка на одно решение обязаны кончаться вместе,
иначе один отпустит раньше другого и качели вернутся. Стенд это и проверяет
(`qa_bugpass` M4).

### Петля погони: два противоположных решения внутри одного отряда

«Задние отстают, теряют цель и возвращаются в строй, а передние продолжают
бежать» — это не два бага, а один: **поводок погони был ЛИЧНЫМ**. Каждый боец
отсчитывал `PURSUIT_LIMIT` от СВОЕЙ точки первого касания. Передние касались
раньше и ближе, задние позже и дальше, кто-то не касался вовсе — и дальше
каждый честно принимал своё решение. Отряд исполнял два противоположных
приказа одновременно и растягивался в нитку.

Якорь теперь один на отряд: ставит первый дотянувшийся, меряются от него все,
кончается поводок у всех разом.

**Вариант «лидер решает, остальные идут за ним» отвергнут осознанно.** Лидер —
это ещё одна сущность: его надо выбирать, переназначать при гибели и
синхронизировать с разметкой строя. Ровно эту цену уже платит знаменосец, и
заводить вторую такую же ради поводка незачем — общий якорь даёт то же
поведение одним `Vector3` на отряд.

**Первая версия стоила кадра.** Якорь читался ДО проверки
`_pursuit_anchored and _attack_is_forced`, то есть словарный поиск в
автозагрузке выполнялся для КАЖДОГО бойца в ветке подхода — а через неё в
массовом бою проходит почти вся армия каждый кадр. Перенесён внутрь условия.

### Замок обороны: почему не скоростью

Соблазн очевиден: `move_speed_mult = 0` — и никто никуда не идёт. Так делать
нельзя. Боец получил бы приказ, ушёл в `State.MOVING`, шагал бы на ноль метров
и НИКОГДА не доложил о прибытии: не заснул бы по картинке (`_proc_sleeping`
требует IDLE), не освободил бы тик, и «замок позиции» стоил бы кадра на каждого
копейщика фаланги.

Поэтому замок сделан НА УРОВНЕ ПРИКАЗА: `command_move` у залоченного просто не
исполняется. И не откладывается — отложенный приказ выстрелил бы при первом же
переключении стойки и увёл бы отряд туда, куда игрок показывал минуту назад.

`holds_ground` этого не закрывал и закрыть не мог: он запрещает ПОГОНЮ, а
сдвинуться фаланга могла ещё двумя законными путями — точкой приказа
(`_phalanx_march`) и смыканием дыр в собственном строю. Оба выглядят одинаково:
«крайние копейщики срываются с места».

Исключение ровно одно и оно обязательно: смыкание рядов
(`Unit.allow_reform_move`). Выдаётся на СЕКУНДЫ, а не «пока не дойдёт» — дойти
боец может и никогда (место занято деревом, его добили по дороге), и вечное
разрешение превратило бы замок в фикцию.

### Лучник бежал в рукопашную не потому, что хотел

Жалоба: «кликаешь по вражескому отряду, который подошёл вплотную, — лучники
бегут во врага, как пехота». Погони у стрелка нет (`pursues_target()` = false),
и она тут ни при чём.

Разбор: приказ атаки назначается ПО ОТРЯДУ, а конкретную жертву выбирает
`squad_pick_member` — «наименее обстрелянный», то есть чаще всего НЕ ближайший.
Стрелку доставалась модель с дальнего края чужого строя, до неё было больше
дальности выстрела, и он честно шёл к ней — прямо сквозь тех, кто стоял в двух
метрах. Со стороны неотличимо от «побежал в рукопашную».

Лечение — подмена цели, а не запрет движения: тому, кто не преследует, цель
меняется на бойца ТОГО ЖЕ отряда, до которого уже дострелить. Приказ игрока
остаётся приказом по этому отряду, меняется только, с кого начать. Пехоты это
не касается вовсе — первая строка `_prefer_in_range` возвращает вход.

Заодно закрыт потолок дальности: она растёт от кузницы и вписывается прямо в
поле бойца, а потолка не было. Держать его надо в ДВУХ местах — при рождении и
при выдаче исследования уже стоящим на карте; второй путь и уводил дальность за
все пределы.

### Смыкание после прохода союзников: событие ловить не надо

Прежнее смыкание взводится ТОЛЬКО боем (`squad_mark_hit`). Проход своих сквозь
строй боем не является — отметка не ставилась, дыры оставались до первой
стычки.

Соблазн — завести детектор «союзник прошёл сквозь строй». Отвергнут: он
ошибался бы и на расталкивании, и на толчке конницы, и на возврате из
гарнизона, а лечение у всех этих случаев ОДНО И ТО ЖЕ. Поэтому редкий обход
смотрит не на причину, а на результат: уехали ли бойцы стоящего отряда от своих
мест. Цена замерена A/B на `qa_mass_battle` (5000): 17.46/17.74 без обхода
против 17.47/17.11 с ним — разницы нет.

### Стенд, покрасневший от разворота требования (третий раз на одном месте)

`qa_hold` A2/A2б. История: сначала «стойка держит позицию ДАЖЕ по приказу» →
потом «по приказу фаланга идёт вперёд единым забором» → теперь «перемещение
запрещено на уровне 0.0». Проверка переписана на новое требование и читает
`lock_position` ИЗ КОНФИГА: вернёт владелец `false` — она сама поедет за ним, а
не покраснеет. Добавлена парная A2б: залоченный строй ОБЯЗАН развернуться на
врага, иначе «замок позиции» неотличим от «боец вообще ничего не делает».

### Замер

`qa_mass_perf` — PASS на всех размерах (5000: 4.98 мс стоя, 11.06 на марше).
`qa_mass_battle` на 5000 держится 16.3-16.8 мс при бюджете 16.6 и проходит
через раз — но этот сценарий сидел на самой линии и до правок (в том же сеансе
он давал от 14.5 до 16.5 мс на НЕИЗМЕННОМ коде). Отделить здесь десятые доли
от разброса прогонов нельзя, и делать вид, что можно, не стоит.

## Фаланга, флажки за ордой, смыкание линии и тайминг тарана (авг. 2026)

### Глухой замок позиции был неверным лечением

Жалоба «крайние копейщики выбегают из строя» закрывалась дважды. Первый раз —
глухим замком (`lock_position = true`): не двигаться вообще. Жалобу он закрыл и
создал другую, ровно противоположную: фаланга перестала ходить по приказу
игрока, а это её штатная работа.

Настоящая причина оказалась не в разрешении двигаться, а в ТОЧКЕ. Приказ атаки
раздаётся каждому бойцу отдельно, и каждый получал одну и ту же цель —
координату вражеской модели. Шеренга честно шла в одну точку, то есть
СХЛОПЫВАЛАСЬ; первыми это видно на флангах, им идти дальше всех. Стена теперь
переносится целиком (`_wall_goal`): точка каждого смещается на тот же вектор,
на который сдвигается центр отряда. Замер: ширина строя 6.30 → 6.30 м при
проходе вперёд на 6.5 м.

**Порядок ворот в `_process_attack` важнее самих ворот.** Запрет «сам к цели не
ходи» обязан стоять ПОСЛЕ `_phalanx_march`, а не до него: ход стены — движение
ОТРЯДА по приказу, и он разрешён; до запрета доходят только те, у кого точки
приказа нет, то есть кто собрался идти сам. При первой правке ворота встали
выше — и фаланга перестала ходить вовсе.

### «Синие флажки за орками»: знамя роняла не гибель, а перекладывание

Отряд пустеет ДВУМЯ путями, и в коде они выглядят одинаково: последнего бойца
убили — или его перевели в другой отряд (`add_to_squad` первым делом зовёт
`remove_from_squad`). ИИ и орда перекладывают бойцов каждый такт размышления, и
на каждом перекладывании на землю падало знамя. За ордой тянулся след из
знамён её же живых отрядов; синих — потому что синий это грейды 4-6.

**Мест, откуда отряд расформировывается, ДВА, и второе легко упустить.**
Очевидное — `remove_from_squad`. Главное — `squad_members()`: он фильтрует
мёртвых и, если живых не осталось, расформировывает отряд сам. Именно этим
путём и уходит по-настоящему выбитый отряд, и первая версия правки его не
трогала: стенд `qa_vet` 4в честно показал «прибавилось 59, ждали 60». Признак
«отряд ВЫБИТ» там выводится из того, был ли среди отфильтрованных хоть один
МЁРТВЫЙ: освобождённые живыми (стенды, смена сцены) дают false.

### Таран: два разных бага под одной жалобой

«Разлёт срабатывает дважды и не в момент удара» — это два независимых дефекта.

1. **Дважды.** Натиск взводился по одной лишь ДИСТАНЦИИ до цели. В свалке цель
   меняется каждые пару секунд, новая нередко оказывается за десять метров — и
   условие взвода выполнялось снова, стоя на месте. Теперь проверяется не
   намерение, а факт: сколько всадник реально проехал с момента взвода
   (`charge_min_runup`).
2. **Не в момент удара.** Тик бойца шардирован, и «дистанция стала меньше
   дальности» замечалось с опозданием — всадник успевал въехать в строй, и
   только потом срабатывал разлёт. `_enemy_contact` ставится в тот же кадр,
   когда шаг реально упёрся в чужое тело: это и есть миллисекунда касания.

**Порог разгона пришлось опустить с 6 до 5 метров.** При шести стенд краснел
через раз, и это была не флуктуация, а честная арифметика: разгон начинается за
`charge_range` = 10 м, касание происходит примерно за 2.5 м — на полный проезд
остаётся около 7.5 м. Если цель успевает подойти сама, всадник взводит разгон
позже десяти метров и своего не добирает. Пять метров оставляют запас и всё ещё
попадают в заказанный диапазон «5-10».

### Смыкание линии в обороне

Отдельно проверено то, о чём говорил владелец дословно: копейщики, расставленные
растяжкой ПКМ (ОДНОШЕРЕНОЖНАЯ разметка) и стоящие в ОБОРОНЕ, после прохода
лучников сквозь строй смыкаются сами. Оба отличия от блока с обычным блочным
строем существенны: разметка другая, и стойка запрещает бойцу двигаться по
собственной инициативе — надо было убедиться, что смыкание из-под этого запрета
всё же работает. Работает: 10 из 10 вернулись на места.


## Перенос стены строя на приказ АТАКИ — ЧЕТВЁРТАЯ ПОПЫТКА, СНЯТ (31.08.2026)

**ИТОГ ЗАХОДА: перенос доведён до конца, измерен честным A/B и СНЯТ.** Причина
снятия НОВАЯ и она главная — её не знала ни одна из трёх прошлых попыток:
**весь выигрыш формации давала ОСТАНОВКА БОЯ, а не построение.**

Ход рассуждения по числам:

| что мерили | с переносом | без |
|---|---|---|
| сдвиг формы после боя (qa_mega_battle B7-2) | 0.90 / 0.88 / 0.93 | 1.09 / 1.04 / 1.05 |
| перелом схватки 60 на 60 (qa_balance B1) | **148 с** | **32 с** |
| замок цели держится (qa_target_lock B1) | **0 из 6** | 6 из 6 |
| замок снят по выбитому отряду (qa_target_lock E2) | **0 из 4** | 4 из 4 |

Обе поломки были найдены и ПОЧИНЕНЫ порознь:
  • замок цели — ход стены делал `return` из ветки «цель погибла», где живёт
    вся работа с замком; починка — не пускать туда ход стены вне обороны;
  • вязкий бой — приход стены гасил `_attack_is_forced` и ставил
    `_engaged_once`, то есть отряд доходил до дистанции копья и переставал
    сближаться; починка — гасить приказ только в обороне.

**И вот после ОБЕИХ починок выигрыш формации исчез целиком: 1.08 против
базовых 1.04-1.09, на подходе 0.70 против 0.70.** То есть механизм не
сохраняет строй — он останавливает отряд, и «сохранённый строй» это просто
строй, который никуда не пошёл. Оставлять правку, у которой все измеримые
следствия отрицательные, незачем: снято целиком (`_wall_aim`,
`_wall_order_allowed`, `GameManager.squad_front_extent` удалены, гейт вернулся
к условию по стойке).

**ЧТО ЭТО ЗНАЧИТ ДЛЯ ЗАКАЗА «сохраняй геометрию отряда при приказе атаки».**
Замер говорит, что НА ПОДХОДЕ строй и так сохраняется: сдвиг формы 0.70 м и с
переносом, и без него. Разваливается отряд НЕ на марше, а в контакте — и это
уже не задача переноса точки. Пятую попытку по этому пути начинать не стоит;
если жалоба «рассыпается в толпу» повторится, мерить надо КОНТАКТ (кто с кем
сцепился и куда его увело), а не дорогу до него.

Ниже — разбор самой реализации: он остаётся полезным, потому что четыре
условия, которые она потребовала, верны сами по себе и понадобятся любому,
кто возьмётся за строй в атаке снова.

Заказ владельца «сохраняй геометрию отряда при приказе атаки», трижды
откаченный. Ниже — что понадобилось сверх прошлой попытки и чем это доказано.
Правила и ссылки на код — в `CLAUDE.md`, раздел «Ряды, копья и строй в атаке».

**ЧЕТЫРЕ УСЛОВИЯ, И НИ ОДНО НЕ ЛИШНЕЕ.** Прошлая попытка снимала одно условие по
стойке и падала на трёх замерах. Каждый из них закрыт своим условием, и к ним
добавилось четвёртое, которого раньше не видели вовсе:

1. `_is_ranged()` — стрелки не идут в рукопашную строем (`qa_hold` C1/C4).
2. `target is Unit` — у зданий свой подход по дуге (`qa_wall` B1).
3. **Отступ перед чужим строем вместо самой цели** (`Unit._wall_aim` +
   `GameManager.squad_front_extent`) — против прохода насквозь (`qa_wall` A1).
4. **`lock`, а не `forced`** — см. ниже, это стоило дороже всего.

**`forced` — НЕ «ПРИКАЗ ИГРОКА», И ЭТО САМАЯ ДОРОГАЯ ЛОВУШКА ЗАХОДА.**
`command_attack(x, true)` зовут ответ на удар (`take_damage`), подтягивание
фланга и оба ИИ. Точка стены считается ОТ ТЕКУЩЕГО центра отряда, значит каждый
такой вызов двигает её на шаг вперёд, а в рукопашной удары приходят каждую
секунду. Замер `qa_melee`, блок F: отряд прополз сквозь противника, ушёл с
площадки стенда в живую партию и был там вырублен целиком — 12 из 12, узлы
освобождены, отряд расформирован. Снаружи это выглядело как «F1 связка была
установлена: противник = 9» (номер ЧУЖОГО, игрового отряда) и «F3 центр масс
сместился на 72.8 м» — а 72.8 это ровно `|(70, −20)|`, то есть центр пустого
массива. **Стенд, у которого центр считается по живым, обязан отличать «отряд
ушёл далеко» от «отряда нет вовсе».**

**ХОД СТЕНЫ КОНЧАЕТСЯ ПЕРВЫМ КОНТАКТОМ.** Пока точка жила всю схватку (как она
живёт в обороне), отряд возобновлял ход после каждого убитого и давил на чужую
шеренгу безостановочно: `qa_wall` A1 дал 4-7 просочившихся из 48 в трёх
прогонах подряд против нуля до правки. Гасится в `_phalanx_march` — и при
подмене цели, и по признаку `bumped` (упёрся, но бить некого).

**В ОБОРОНЕ ОТСТУПА НЕТ.** С ним `qa_hold` A2 «стена дошла до точки приказа»
упала с 2.75 м до 0.26 м при разрыве 3.5 м: строй делал четверть шага и считал
приказ исполненным. Там точка И ЕСТЬ приказ, а весь ход — короткий шаг до упора.

### Чем доказано

**A/B чередованием, три раунда, база и правка подряд** (`qa_mega_battle` B7):

| | с переносом | без |
|---|---|---|
| сдвиг формы на подходе | 0.59 / 0.57 / 0.65 | 0.67 / 0.70 / 0.68 |
| сдвиг формы после боя | 0.90 / 0.88 / 0.93 | 1.09 / 1.04 / 1.05 |

`qa_wall` A1, четыре прогона на сторону: 0/0/0/3 против 0/2/0/0 — то есть тот же
мигающий красный, на перенос не реагирует.

### Три ловушки замера, каждая давала уверенный неверный вывод

1. **ГАБАРИТ ОТРЯДА ЖАЛОБУ НЕ ЛОВИТ.** B7-1 зелёная и БЕЗ переноса (7.4 → 7.1 м
   при пороге 11.8): отряд, подошедший поштучно, случайно укладывается в прежнюю
   ширину. Ловит сдвиг ВЗАИМНОГО расположения — смещение каждого от медианного
   центра до приказа и после.
2. **ОДИНОЧНЫЙ ПРОГОН ЗДЕСЬ ВРЁТ.** Два прогона на НЕИЗМЕННОМ коде дали 0.87 и
   1.10 — весь эффект целиком. Только чередование.
3. **РУЧКА A/B МОЖЕТ НЕ СНЯТЬСЯ.** Временный `return false` в
   `_wall_order_allowed` пережил текстовую замену (не совпали переводы строк), и
   четыре прогона подряд «доказывали», что правка ничего не меняет. Ловится
   счётчиком `_hold_goal_set` сразу после приказа: 0 из 50 вместо 50 из 50.
   **Замер правки начинается с проверки, что правка включена.**

### `qa_melee` F2 — «приказ на марш вывел отряд из боя» (29.08.2026)

**Стабильно красный: 12 из 12 остаются с целью.** Отряд при этом УХОДИТ —
соседняя проверка F3 зелёная, центр масс смещается на 6.4 м. То есть приказ
исполняется, но по дороге отряд снова ввязывается в драку.

**Ход событий (зонд по одному бойцу раз в секунду):** пять секунд боец идёт
(`MOVING`, цели нет, продвигается), на шестой — `ATTACKING` со сцепкой
(`_melee_grip`), и обратно в марш уже не возвращается. Ловит его признак упора
`wall` в `_process_move`: он перебивает и замок приказа, и выход из боя. Его
третье условие (`not moved_recently()`) заведено ровно против этого случая, но
окно там 200 мс при пороге 0.6 м/с, а выдавливающийся из свалки отряд идёт
0.53 м/с рывками — на каждом провале рывка упор срабатывал.

**ПОПЫТКА ПОЧИНКИ СДЕЛАНА И ОТКАЧЕНА — ЗАМЕРЫ ЗДЕСЬ, ЧТОБЫ НЕ ПОВТОРЯТЬ.**
Заводился четвёртый разделитель `_prog_ok` — «продвигаюсь ли я к точке
приказа», своё окно 1 с при планке 0.35 м/с плюс выдержка 1.7 с (сначала без
выдержки — не помогло вовсе, признак гас между замерами). Результат:
- `qa_melee` F2 стало лучше, но не зелено: 12 → 8 с целью, уход длится 7 с
  вместо 5;
- **`qa_wall` C1 стало ХУЖЕ и это уже потеря требования владельца:** «упёршиеся
  в чужой строй вступают в бой» — дерутся 5 из 37 (14%). Отряд, посланный ЗА
  СПИНУ противнику, ползёт вдоль чужого строя и по новой мере ПРОДВИГАЕТСЯ,
  то есть считает себя уходящим, а не упёршимся.

Требования спорят напрямую: «упор перебивает любой приказ» (заказ, третья
партия) против «приказ рвёт связку» (заказ, часть 2). Мера продвижения их не
разводит, потому что ползущий вдоль строя и выдавливающийся из свалки идут с
одной скоростью.

**Отдельно: полностью выключить `wall` — не вариант.** Зондом проверено: F2
тогда зелёный (0 с целью, уход 9.3 м), но это ровно та жалоба, ради которой
`wall` и заведён.

#### Вторая попытка (31.08.2026): ещё три меры, все три сняты

Прошлый вывод звучал так: «разводит их НАПРАВЛЕНИЕ — уходящий увеличивает
дистанцию до ТОГО, кто его держит». Это проверено в трёх видах, и **ни один не
работает**. Код возвращён в исходное; ниже числа, чтобы не заходить в четвёртый
раз тем же путём.

1. **Рост дистанции до КОНКРЕТНОГО держащего** (помним того, о кого упёрся шаг;
   отсчёт от самой близкой точки, порог 0.45 м). Не работает по построению: в
   свалке помеха меняется постоянно, и у выдавливающегося она меняется НА БОЛЕЕ
   ДАЛЬНЮЮ — смена помехи сбрасывает отсчёт ровно в миг ухода. F2: 12 из 12.
2. **Рост дистанции до ЛЮБОГО ближайшего чужого тела** (без привязки к
   личности). Не работает, и причина глубже: отряд, из которого выходят,
   **ПРЕСЛЕДУЮТ**. Замер по секундам — свои идут 0.92 м/с, враг 0.90 м/с, то
   есть контакт восстанавливается каждую секунду и минимум дистанции не растёт
   НИКОГДА. F2: 12 из 12; `qa_wall` C1 при этом вырос с 93 % до 97-100 %.
3. **Угол на помеху** (уходит тот, у кого помеха в задней полусфере, порог
   `cos < −0.34`). Направление брать у `velocity` НЕЛЬЗЯ: у того, чей шаг
   упёрся, её обнуляет разбор помехи — то есть выдавливающийся читается как
   «стою». По `move_target` направление честное, но это ухудшает то, ради чего
   перехват заведён: `qa_wall` C1 93 % → 89 %, A1 ноль просочившихся → один.
   F2 при этом всё равно 12 из 12.

**ПОЧЕМУ ВСЕ ТРИ МИМО — РАЗБОР ПО СЕКУНДАМ (главное из этого захода).**
Зонд печатал раз в секунду число бойцов с целью, среднюю z своих и чужих и
состав состояний:

    T1  с целью 0   свои z −19.8  враг −16.8   12 × MOVING, замок 2.0
    T4  с целью 3   свои z −24.4  враг −19.5    9 × MOVING, замок истёк
    T6  с целью 10  свои z −23.2  враг −21.3   10 × ATTACKING, сцепка
    T12 с целью 12  свои z −20.6  враг −19.1   12 × ATTACKING, сцепка

То есть **приказ исполняется честно первые четыре секунды** (отряд уходит на
4.6 м, целей нет), а потом истекает `FORCED_MOVE_SEC`, и дальше каждый удар в
спину зовёт `command_attack(attacker, true)`, переводя бойца в ATTACKING
НАСОВСЕМ: помеха жива, вернуть его в марш некому. Дальше это лавина — вставший
боец пиннит следующую шеренгу, та перестаёт двигаться, проходит ворота
`moved_recently()` и тоже отвечает на удар.

**ЧТО ЭТО ЗНАЧИТ ДЛЯ СЛЕДУЮЩЕЙ ПОПЫТКИ.** Разделителя в СВОЙСТВАХ БОЙЦА не
существует: боец, которого прижали свои же задние ряды, физически неотличим от
упёршегося. Спорят не два признака, а два СРОКА — «замок приказа живёт три
секунды» против «марш на тридцать метров идёт десять». Значит, вопрос не
технический, а к владельцу: **должен ли приказ игрока на движение переживать
контакт до исполнения** (то есть жить до прихода в точку, а не по таймеру).
Если да — правится один срок, и всё остальное встаёт на место; если нет — F2
требует того, чего игра делать не должна, и краснеть он будет всегда.
Пробовать четвёртый признак смысла нет.

### `qa_wall` A1 — «враг не проходит сквозь ЖИВОЙ строй» (29.08.2026)

**Красный в 4 прогонах из 6, 1-3 просочившихся из 48 (изредка 8).** Разобран до
конца, но НЕ починен — ниже всё, чтобы не начинать заново.

**Сперва починен САМ ЗАМЕР — старый критерий врал.** Он считал строй целым по
ДОЛЕ ЖИВЫХ ВО ВСЁМ ФРОНТЕ и судил о месте прорыва по ТЕКУЩЕЙ точке
просочившегося. Обе половины неверны:
- все три вражеских отряда посланы на ОДНУ приманку в центре, то есть 48
  мечников сходятся на среднюю треть из 24 копейщиков. Замер: середина выбита
  до 16 из 24 (67%) при 53 из 72 (74%) по всему строю — общий порог считал
  целым участок УЖЕ РАЗБИТЫЙ;
- перешедший линию идёт к приманке в центр. Замер: 13 «прорвавшихся» стояли за
  ЦЕЛОЙ серединой, а перешли линию через РАЗБИТЫЙ левый край. По нынешнему
  месту о прорыве судить нельзя вовсе.

Разброс на НЕИЗМЕННОМ коде был от 0 до 18 человек в тылу. Теперь решение
принимается ОДИН РАЗ, в миг перехода (опрос раз в 10 кадров вместо 60: мечник
идёт 3 м/с, за секунду он уходит от места перехода на три метра), и по МЕСТНОЙ
плотности — живые в полосе ±0.9 м по X и ВПЕРЕДИ точки перехода, порог 3
человека. Местная мера обязательна и по второй причине: стенд ставит три отряда
по восемь в шеренге с шагом 7 м, между ними пустые промежутки по 2.8 м, и
прошедший по пустому месту не проходил сквозь строй вовсе.

**Что проверено и НЕ является причиной остатка:**
- билет прохода приказа (`Unit._forced_move_pass`) — зондом показано, что в
  блоке A он не срабатывает НИ РАЗУ (некому: `player_order` там только у
  постановки стены до появления врага);
- билет отхода (`Unit._retreat_pass`) — заглушен, 2 прогона из 4 всё равно
  красные (худший 8).

Остаётся сам пакетный шаг: у копейщиков шаг разметки 0.6 м при личном круге
0.25, то есть щель между соседями около 0.1 м, и при сорока восьми напирающих
единицы её находят. Это свойство расталкивания без поиска пути, и лечится оно
не условием, а тем, чтобы солвер видел ШЕРЕНГУ преградой, а не набор кругов.

**ПЕРЕМЕРЕНО A/B 31.08.2026, ЧЕТЫРЕ ПРОГОНА НА СТОРОНУ** (ручка — перенос стены
на приказ атаки, см. `Unit._wall_order_allowed`):

    без переноса стены:  0, 2, 0, 0 просочившихся  (красный 1 из 4)
    с переносом:         0, 0, 0, 3               (красный 1 из 4)

То есть A1 остаётся ровно тем же мигающим красным и **на перенос стены не
реагирует** — при условии, что ход стены гасится упором (`_phalanx_march`,
ветка `bumped`). Без этого гашения он реагирует, и плохо: 4-7 просочившихся из
48 в трёх прогонах подряд, потому что строй возобновляет ход после каждого
убитого и давит на чужую шеренгу безостановочно. Напор — не новая дыра, а
множитель к той же щели в 0.1 м.
## Известные красные (перенесено из CLAUDE.md, авг. 2026)

Пре-существующие «красные», не регрессии: `qa_crowd` B2 и **C1**,
`qa_target_lock` F2/F4, `qa_spear` A10, **`qa_volley` D5** и
`qa_approach_intercept` #2 — плавающие (перезапустить). `qa_volley` D5 проверен
перезапуском (авг. 2026, вторая партия правок): «ранено 2 из 15» в одном
прогоне и 23 из 23 в следующем на НЕИЗМЕННОМ коде — там разброс тучи стрел,
и на пятнадцати мишенях он иногда даёт двоих. **`qa_crowd` C1 проверен A/B (авг. 2026, правка смыкания
строя):** краснеет примерно в одном прогоне из шести и при ПОЛНОСТЬЮ
выключенном обходе `GameManager._sweep_reform`, то есть к смыканию отношения
не имеет. На провале печатается «дошёл: false» — бойца застают НА ХОДУ, он не
наматывает круги (детектор `_trunk_ignore` не срабатывает). Порог там ножевой:
`ARRIVE_RADIUS + 0.1` = 0.58 м при штатном остатке 0.48 м. Заодно стенду
исправлено ожидание: было 8000 мс по СТЕННЫМ часам, стало 480 физкадров —
правило 11 проекта, одну из причин мигания это снимает. `qa_target_lock` F2/F4 проверены A/B: без правки поправки
целей стрелка (`Unit._prefer_in_range`) они краснеют с той же частотой, то есть
к ней отношения не имеют. `qa_spear` A10 тоже мигает — порог 2.2 при
измеряемых 2.20 (в одном прогоне 2.21 — красный, в двух следующих 1.23 и 1.30); `qa_formation` B1/B2,
`qa_world2` C5/C7, `qa_queue2` (синтетические события мыши), `qa_bugpack2` 6f,
`qa_audio2` C1 (замер абсолютного времени — не чинить; **A/B авг. 2026:**
с полностью выключенными маршем и лимитером надбавка та же ~3 мс, то есть
измеряется шум машины, а не звук; сам марш добавляет ~0.35 мс — 3.34 против
2.98 при шести голосах против нуля), `qa_hudcam`
A4/A5/A9/A11b, `qa_wind` B1/B3/B4/C1 (ищет у каждого растения свой
`MeshInstance3D` с приватным материалом — их нет с переезда растительности в
MultiMesh; актуальный стенд по растительности — `qa_veg`).

### Добавлено авг. 2026 (заход по оптимизации ядра и покадровых путей)

- **`qa_balance` C7 «признак паники снят со всех бойцов» — мигает, и причина
  В САМОМ СТЕНДЕ, а не в панике.** Перезапуски на НЕИЗМЕННОМ коде дали
  **0 / 1 / 0** провалов; на красном печатается «осталось помеченных 2».
  Разбор по коду: `GameManager._end_panic` снимает признак обходом
  `squad_members(sid)`, то есть ТОЛЬКО У ЖИВЫХ и только у тех, кто ещё числится
  в отряде. А стенд проверяет СВОЙ список `weak`, снятый до паники, — и, в
  отличие от соседних проверок C3 и C4, **без оговорки `not is_dead()`**:

      for u in weak:
          if is_instance_valid(u) and (u as Unit).is_panicked():
              still += 1

  Рядом стоит вражеский отряд, и за шесть секунд бегства часть `weak` гибнет.
  У павшего `_panicked` так и остаётся взведённым — снимать его уже некому и
  незачем, — а стенд его считает. Сколько именно погибнет, от прогона к
  прогону разное: отсюда и мигание. Чинить надо стенд (добавить `not is_dead()`
  тем же порядком, что в C3/C4), код паники тут ни при чём.
- **`qa_melee` B1/B2 «в контакте / свободных посчитано верно» — мигают, и
  каждый раз по-разному.** Три прогона подряд на неизменном коде дали: B1+B2
  («отряд говорит 18, вручную 19» и «2 против 1»), затем F2 («приказ на марш
  вывел отряд»), затем ни одной. Расхождение всегда НА ЕДИНИЦУ, и это
  сравнение снимков РАЗНОЙ СВЕЖЕСТИ: стенд считает дерущихся вручную по
  ТЕКУЩИМ позициям (`u.global_position.distance_to(t.global_position) <=
  u.attack_range`), а `GameManager.melee_counts` отдаёт готовую боевую
  бухгалтерию `_melee`, которая пересчитывается раз в `MELEE_TTL_MS` = 400 мс.
  Боец, стоящий ровно на границе дальности, попадает то в один снимок, то в
  другой. Это свойство замера: чинить — либо сверять сразу после пересчёта
  бухгалтерии, либо допускать разницу в одного бойца.
- **`qa_wall` A1 «враг не проходит сквозь ЖИВОЙ строй» — мигает.**
  Перезапуски на неизменном коде дали **0 / 0 / 1** провалов; на красном —
  «замеров на целом строю 24, худший — 1 в тылу». Порог ножевой по
  построению: проверка требует НУЛЯ противников за спиной целой шеренги, и
  достаточно ОДНОГО бойца в ОДНОМ замере из двадцати четырёх, чтобы стенд
  покраснел. Смысл проверки от этого не портится (она ловит именно
  «протекание строем»), но единичный красный сам по себе ничего не значит —
  смотреть надо на «худший» и на повторяемость.
- **ОБЩЕЕ ДЛЯ ВСЕХ ТРЁХ: перед тем как чинить код по этим красным,
  перезапустите стенд.** Все три поймали меня в заходе по `squad_in_combat` и
  по чистке ядра, и все три оказались не при чём. Заодно подтверждена и
  прежняя запись про `qa_spear` A10: в одном прогоне «соотношение 3.34» —
  красный, в двух следующих подряд зелёный.

## Roadmap: плотный список живых строк в `ArmyCore`

**СТАТУС: СДЕЛАНО (сент. 2026), СПИСОК ОТСОРТИРОВАННЫЙ — поведение не
изменилось ни в одном стенде. Разбор — раздел «Сентябрь 2026, этапы A и B».**
Ниже — исходная постановка (оставлена: в ней замеры и опасности).

**СТАТУС ИСХОДНЫЙ: НЕ СДЕЛАНО НАМЕРЕННО.** Задача снята с текущего захода и ждёт
следующего крупного рефакторинга физического ядра. Ниже — всё, что нужно,
чтобы взяться за неё, не начиная разбор заново.

**ЧТО ЕСТЬ СЕЙЧАС.** Покадровые проходы солвера (`FillGrid`,
`BatchSeparation`, `BatchCombat`) обходят ДИАПАЗОН `0.._top`, где `_top` —
верхняя граница занятых строк (см. CLAUDE.md, «Ядро армии»). Это уже лучше
обхода по ёмкости, но граница упирается в самого верхнего ЖИВОГО.

**ЧЕГО НЕ ХВАТАЕТ.** Замер зондом `qa_ab/Probe` (2000 бойцов, ёмкость 2048):

    после найма 2000:     ёмкость=2048  граница=2000  занято=2000
    выбили НИЖНИЕ 1900:   ёмкость=2048  граница=2000  занято=100   ← вхолостую 1900
    выбили всех:          ёмкость=2048  граница=0     занято=0     ← вхолостую 0

При рассеянных потерях — а в бою они именно такие — граница не опускается, и
проход по-прежнему перебирает пустые строки. Плотный список (`_liveRows`,
удаление перестановкой с последним) убрал бы это полностью.

**ПОЧЕМУ ЭТО НЕ «ПРОСТО ОПТИМИЗАЦИЯ», А ПРАВКА ПОВЕДЕНИЯ.** `FillGrid`
строит списки ячеек ВСТАВКОЙ В ГОЛОВУ (`_next[i] = _head[c]; _head[c] = i`),
поэтому порядок обхода строк задаёт порядок соседей внутри ячейки. Сейчас он
строго возрастающий, и `_top` его не меняет (обе версии идут по возрастанию,
просто разной длины). Плотный список после первой же смерти перестаёт быть
отсортированным — а по этим спискам идут `EnemyAt`, `BestEnemy`,
`NearestOfSide` и `ScanBlock`, и там есть разрешения ничьих «первый
подходящий». Значит, поменяется ВЫБОР ЦЕЛИ в равных ситуациях: не хуже и не
лучше, но ИНАЧЕ — а на этом стоят десятки стендов.

**ЧТО СДЕЛАТЬ, КОГДА ВОЗЬМЁТЕСЬ:**
1. Вести `_liveRows` + `_rowSlot` (обратный индекс), удаление перестановкой с
   последним — тот же приём, что у `GameManager._live_units`.
2. Либо держать список ОТСОРТИРОВАННЫМ (тогда поведение не меняется вовсе, но
   вставка/удаление становятся O(n) — на сотнях смертей в секунду это дороже
   того, что экономится), либо принять смену порядка и прогнать ВЕСЬ шлюз,
   ожидая расхождений в стендах на выбор цели.
3. Мерить `qa_ab` — но сцену придётся завести НОВУЮ: в текущих блоках бойцы
   бессмертны, и разреженности реестра там не возникает вовсе. Нужен блок
   «армия понесла рассеянные потери», иначе замерять будет нечего.

**ЧЕГО ЖДАТЬ ПО ВЕЛИЧИНЕ.** Немного. Сэкономленная итерация — одна загрузка
флага и сравнение в C#; при 6000 пустых строк и двух проходах это десятки
микросекунд на кадр. Браться стоит вместе с другой работой по ядру, а не ради
одного этого.

## Август 2026: разбор багов на 700×700 и отказ от «стерильных» стендов

Заказ владельца: шесть пунктов по реальному бою на большой карте, с условием
сперва согласовать архитектуру. Ниже — что оказалось правдой при замере, а что
пришлось переделать по дороге.

### Чем меряли

Заведён `qa_mass_siege` — 1400 бойцов смешанного состава плюс база из шести
построек. Все числа ниже с него, тик печатается в каждом разделе.

### Что и насколько изменилось

| симптом | до | после |
|---|---|---|
| растянутость разметки при приказе | 19.9 м | 5.2-5.7 м (`slots`) |
| разброс тел отряда на марше | 21.9 м | 4.7-8.7 м |
| оторвавшихся от отряда | 8 из 426 (1.9%) | 0-1 из ~580 |
| проход сквозь союзный строй | «дошла половина» за 7.0 с | 35 из 35 за 4.2-4.5 с, завязших 0 |
| пять отрядов у постройки | все в центре, 1.3 м между центрами | у своих секторов, отставание 1.5 м |
| «бег на месте» на марше | — | 0 из 1400 |
| рабочие к флажку | шеренгой через полкарты | самый дальний в 0.8 м |
| тик на 1400 бойцах | — | свалка 2.7-3.0 мс, затяжной бой 2.9-3.8 мс |

### Четыре стенда меряли не то, что утверждали

Главный итог этого захода — не правки кода, а то, что половина «красных»
вердиктов оказалась ошибкой ИЗМЕРЕНИЯ. Все четыре случая стоит помнить.

1. **Осада мерилась по дороге к базе.** Приказ отдавался оттуда, где отряды
   стояли, а между ними и постройкой была вся чужая армия. До здания не
   доходил никто (сектора розданы верно, отставание 33-45 м), и «ближайшие
   центры 1.9 м» описывали общую свалку на полпути, а не кучу у стены.
2. **Бой мерился ПОСЛЕ осады**, которая переставляет пять отрядов к базе. В
   замер попадали отряды, бредущие обратно: разброс прыгал 5.8 → 24.6 м на
   неизменном коде.
3. **«Растянутость разметки» мерилась по `post_pos`.** Личный пост переписывает
   любой `command_move`, в том числе законный подзыв отставшего. Настоящие
   строевые места лежат в `squads[sid]["slots"]` и не растягиваются вовсе.
   Плюс огрызки отряда: двое выживших с далёкими слотами давали «растянутую
   разметку» на пустом месте.
4. **«Колбаса» мерилась сырым разбросом тел от медианы.** Сражающийся отряд
   честно даёт 15-20 м: передние сцепились с врагом, задние стоят на местах.
   Это линия боя, а не развал строя. Развал — это боец, ушедший И от своего
   слота, И от своего отряда; ровно такого зовёт назад `_cohesion_guard`, и
   мерить надо то же самое.

Пятый случай того же рода — вердикт «центры отрядов не ближе 4 м» у постройки:
требование невыполнимо по геометрии, периметр здания короче. Стенд теперь
считает хорду `2·r·sin(дуга/2n)` сам.

### Конфиг владельца поехал прямо во время работы

`unit_stats_config.gd` был изменён владельцем в 22:41 (наград на уровень стало
три вместо пяти, и каждая награда теперь даёт НАБОР модификаторов). Красными
стали `qa_vet` (6 провалов) и `qa_recon` (1). Ни один из них не был регрессией
кода — оба стенда хардкодили конфиг и утверждали развёрнутые требования:

- `qa_vet` ждал ровно пять кнопок и брал награды по индексам 0..4 (падение
  «Out of bounds get index 3»), сверял эффект с полем `value` — короткой
  подписью для кнопки, — тогда как награда применяет ВСЕ свои модификаторы.
  Переписан: идёт по составу конфига, каждую награду проверяет по её
  собственным модификаторам, сумму сверяет с пересчётом из конфига по списку
  `squads[sid]["chosen"]`.
- `qa_recon` искал в заголовке панели глиф «★», а звёзды в проекте давно
  заменены знамёнами; ранг читается названием отряда
  (`veteran_rank_name`).

### Аудио

Лимитер с мастер-шины СНЯТ (заказ владельца): `AudioEffectHardLimiter` резал
атаки металлических ударов, из-за чего пропадал лязг оружия. Громкость горна и
марша поднята на +3.5 дБ (`MARCH_WALK_DB` −17.2, `MARCH_RUN_DB` −14.2, горн
+0.5). Добавлен слой звона брони на марше: `metal_punch_06` с питч-шифтом
1.2-1.5, лимит три голоса, интервал 0.20 с, шанс 0.55 на такт обхода. Бюджет
некогерентной суммы после подъёма — 0.478 при потолке 0.5 (`qa_voice`, 39/39).

## Кастрюля на голове и флаг в пустой траве (26 авг. 2026)

Две жалобы владельца одним заходом, и обе оказались НЕ тем, чем выглядели.

### Слой «звона доспехов» откачен целиком

Прошлая правка завела поверх марш-лупа отдельный слой: `metal_punch_06` с
питч-шифтом 1.2-1.5, случайный марширующий отряд раз в `ARMOR_JINGLE_MIN_GAP`.
Вердикт владельца: «регулярный удар по кастрюле, надетой на голову».

Механика была верна по цене (звенел ОТРЯД, а не боец) и неверна по существу.
Сэмпл — УДАР одного металлического предмета: у него одна атака и один хвост, а
звон снаряжения на марше это десятки мелких несинхронных призвуков. Питч-шифт
одного в другое не превращает, и поверх НЕПРЕРЫВНОГО лупа регулярный удар
слышится метрономом — ухо цепляется за единственное периодическое событие в
шуме. Сделать такой слой можно только СВОИМ сэмплом кольчуги, а его в проекте
нет; в `community-marching-loop` он записан внутри, ради чего луп и выбран.
Удалены `armor_jingle` из `SFX_BANK`/`SFX_LIMITS` и `GameManager._jingle_armor`.

Заодно снят подъём громкости, который делался ПОД этот слой. История ручки
теперь такая: −23/−20 → −20.7/−17.7 (+30% амплитуды по заказу) → −17.2/−14.2
(+3.5 дБ вместе с лимитером и звоном) → **−19.0/−16.0**, ровно посередине между
двумя крайностями, которые владелец слышал. Бег при −14.2 занимал 0.478 бюджета
из 0.5, то есть шёл впритык к потолку и глушил бой, ради фона под которым марш
и заведён; теперь 0.28 у шага и 0.39 у бега (`qa_voice` 39/39).

### «Синие флажки плодятся» — дубликатов не было ни одного

Жалоба формулировалась как утечка: «при движении и бое спамятся дубликаты
знамён ветеранов и зависают на карте». Первым делом это было ПРОВЕРЕНО, а не
исправлено. Зонд `qa_reform/Flags` поднимает настоящую партию (деревня, орда из
`Main`, живой `GoblinAI`, туман) и каждые две секунды сравнивает число узлов
`SquadBanner` в дереве с числом отрядов, которые на них ссылаются. За весь бой,
включая марш, свалку, отход в хижины и пополнение: **узлов 5, у отрядов 5,
бесхозных 0** — ни одного дубликата, ни одного сироты. Второй зонд (оконный,
`qa_reform/FlagShot`) показал, что и на экране знамя сидит в гуще своего отряда.

Настоящая причина — ЗАМЕРШАЯ НАРИСОВАННАЯ ТОЧКА, и она видна только вместе с
туманом. Боец под пеленой снимается с общей отрисовки в `Unit._hide_in_fog` и
выходит из `tick_visual` РАНЬШЕ, чем обновит `_draw_pos`; значит
`draw_position()` у него остаётся равной месту, где его видели в последний раз.
`_update_squad_banners` брал эту точку И ДЛЯ ПОСТАНОВКИ, И ДЛЯ ВОПРОСА К
ТУМАНУ — то есть спрашивал не «видно ли хозяина», а «освещено ли место, где он
когда-то был». Дальше всё складывается само: орда уходит под пелену, армия
игрока наступает и освещает её вчерашнюю кромку — и над пустой травой
загорается флаг, который стоит там, пока хозяин не выйдет на свет или не
погибнет. Пять ветеранских отрядов орды за партию оставляют такие метки в
разных местах, и на экране это читается ровно как «флажки плодятся».

Лечение: спрашивать ФАКТ ОТРИСОВКИ (`Unit.is_drawn()` — `_far_registered`, а в
запасном режиме `mm_render_all = false` видимость собственного спрайта). Он
разом покрывает туман, гарнизон и уход бойца с карты и не зависит от свежести
нарисованной точки. Туман проверяется дополнительно по ЛОГИЧЕСКОЙ точке бойца,
ставится знамя по-прежнему в нарисованную — сглаживание там уже сделано.

Стенд: `qa_reform` B6/B7. Порядок шагов в нём значим, и первая версия была
неверной: мало увести орду в темноту — пока действует `FOG_HIDE_GRACE`, боец
ещё тикает и переносит нарисованную точку за собой, то есть замирает она уже в
темноте и знамя гаснет само. Воспроизводит жалобу только полный порядок:
орду видели ЗДЕСЬ → свет ушёл, и под пеленой она ушла отсюда → армия игрока
НАСТУПИЛА и осветила это место снова. A/B на старом коде: видимое знамя стояло
в **765 м** от своего знаменосца; с правкой — погашено.

Шлюз после правок: `qa_mass_siege` 9/9, `qa_reform` 16/16, `qa_voice` 39/39,
`qa_audio` 43/43, весь список шлюза зелёный, кроме двух известных
пре-существующих красных (`qa_ai` проверка 5, `qa_target_lock` F2/F4) и
`qa_audio2` C1 (замер абсолютного времени).

## Панель ветеранства: редизайн по семи пунктам (26 авг. 2026)

Заказ владельца по трём скриншотам. Ниже — только то, что оказалось не таким
очевидным, как выглядело в задании.

### Требование пришло развёрнутым дважды за один заход

Пункт 5 задания: «текст вида `★ Ветеран 2 — выберите награду` ПОЛНОСТЬЮ УДАЛИ,
на его место вставь флажки рангов». Сделано — вместе с подписью отряда, которая
жила в том же `info_label`. Через несколько минут поправка владельца: «надписи,
где отряд опытных копейщиков, отряд элитных копейщиков — эти надписи не надо ни
в коем случае убирать, верни». Итог: убирается СЛУЖЕБНАЯ строка, название со
званием остаётся, флажки встают ПОД подписью, а не вместо неё. Стенд сторожит
обе половины разом (`qa_vetui` E1 и E1б) — иначе следующая правка снова снесёт
подпись целиком.

### Что пришлось делать не так, как написано в задании

- **«Иконку выбранного бонуса перенести в правую часть таблицы»** — перенос
  сам по себе тривиален, но ряд был ГОРИЗОНТАЛЬНЫМ, а в правой колонке ширины
  на семь иконок нет. Стал сеткой в две колонки; имя узла оставлено прежним
  (`BonusRow`), потому что по нему ряд ищут стенды.
- **«Тултип всплывает справа от панели наград»** — это НАРУШЕНИЕ общего правила
  интерфейса «окно строго над наведённой кнопкой», и нарушение осознанное: над
  рядом наград висит таблица статов, и плашка легла бы ровно на неё, то есть
  закрыла бы предпросмотр, ради которого игрок и навёл курсор.
- **«При клике эти цифры фиксируются в постоянный показатель»** — фиксировать
  нечего и НЕЛЬЗЯ: клик применяет награду, панель пересобирается штатным
  `show_selection`, и числа приходят настоящими, из полей бойца. Любая
  «фиксация» предпросмотра завела бы второй источник правды о статах.
- **«+1 к урону каждой модели» в старом тултипе не просто лишняя, она врала:**
  награда даёт НАБОР модификаторов (владелец переписал конфиг в прошлом заходе),
  а строка печатала первый попавшийся. Новая плашка перечисляет все ненулевые.

### Камера на паузе и почему подсветка — элемент HUD

Клик по значку ранга обязан переводить камеру плавно и НА ПАУЗЕ: награду
выбирают именно на паузе. Камера в `PROCESS_MODE_ALWAYS`, поэтому глиссада
считается в её собственном `_process` и своего таймера не требует. Ручное
движение её отменяет — иначе камера уползает из-под пальцев.

Подсветку отряда сперва хотелось сделать ещё одним слоем колец в мире. Нельзя:
слои ведёт `GameManager._process`, а он PAUSABLE — на паузе буфер не подаётся
вовсе, и подсветка не появилась бы ровно в том случае, ради которого её просили.
Плюс кольцо под ногами в гуще боя перекрыто спрайтами. Поэтому метка рисуется в
HUD (он ALWAYS) поверх толпы, кольцо строится кодом и кэшируется.

### Ловушки стенда, а не кода

Первый прогон `qa_vetui` дал три красных, и ни один не был багом интерфейса:

1. **Значок показывал лычки третьего ранга вместо второго.** Уровень отряда
   поднимается В МОМЕНТ ЗАСЛУГИ, а невыбранные награды висят в `pending`:
   «текущее» — это `level − pending`, иначе заслуженная лычка уже горит.
   Это правка кода, а не стенда.
2. **Камера «не доезжала» до отряда.** Отряд стоял в 90 м от центра карты, а
   фокус зажимается границей МИНУС видимая полоса (`_clamp_focus`): у края
   карты камера физически не может встать на отряд. Стенд мерил зажим.
3. **В headless курсор лежит в (0,0)** — то есть в самом углу экрана, и камера
   честно едет туда скроллом края каждый кадр, отменяя глиссаду. В игре этого
   случая нет: по значку кликают курсором, лежащим НА КНОПКЕ, а над элементом
   интерфейса край экрана камеру не гонит. В стенде отсечка отключается
   (`edge_pan_margin = -1`; ноль не годится — условие там `x <= margin`).

Плюс `qa_vet` и `qa_queue2` утверждали удалённый текст («★ Ветеран N») — оба
переписаны на проверку СВОЙСТВА (ряд флажков показан, служебной строки нет).

Шлюз после правок: `qa_vetui` 40/40, `qa_vet` 55/55, `qa_upd4` 26/26,
`qa_hud5` 35/35, `qa_recon` 22/22, `qa_squad` 52/52, остальной шлюз зелёный,
кроме известных пре-существующих красных (`qa_ai` проверка 5,
`qa_target_lock` F2/F4, `qa_queue2` 12b/12j/14b/14d/14e — панель фильтра типов
и ярлыки найма, к панели ветеранства отношения не имеют).

### `qa_ui9` не компилировался, а не «краснел» (26 авг. 2026)

Стенд ссылался на `ResourceNode.GOLD_SHIMMER` — ВЫКЛЮЧАТЕЛЬ аддитивного блика
золота, удалённый вместе с самим бликом (второго квада с
`gold_shimmer.gdshader` в игре нет вовсе, см. запись от 12 авг.). Ссылка на
несуществующую константу — это не красный вердикт, а **ошибка парсинга**: файл
не грузился целиком, и стенд молча не проверял ни один из девяти пунктов
вёрстки. Тем и опасен такой случай: в отчётах он выглядит как «стенд ничего не
печатает», а не как провал.

Проверка переписана на СВОЙСТВО (правило 10): вместо снятой ручки сторожим то,
ради чего она заводилась, — «аура выключена, а золото по-прежнему
переливается». Свойств два: ни один кусок не носит узла `GoldShimmer` (этот
вердикт был и раньше) и у каждой золотой жилы ЛЕНТА ИЗ НЕСКОЛЬКИХ КАДРОВ
(`ResourceNode.sprite_frames_drawn > 1`), то есть перелив идёт штатным кадровым
путём. Число кадров не хардкодится — важно «больше одного».

Замер сперва мигал: `sprite_frames_drawn` выставляется при сборке визуала, а
мир раскладывает ресурсы не в один кадр, и проверка через пять кадров после
старта сцены мерила собственную спешку. Теперь она ждёт готовности жил (до 120
кадров) и только потом судит. Итог: **43/43**, и в окне, и headless.

## Август 2026: генеральная уборка, сложность, сохранения и разбор масштаба 6000

Заказ владельца из пяти шагов: вычистить наследие звёздочек ветеранства,
задокументировать конфиги построчно, расширить конфиг ИИ стартовым составом с
рангом, разобрать масштаб 6000 и заложить сложность и сохранения.

### Что удалено (и почему это оказалось безопасно)

`scripts/VeterancyStar.gd` и `shaders/gold_shimmer.gdshader` лежали в дереве
неиспользуемыми с пометкой «оставлено, по нему меряются стенды прежнего вида».
Проверка показала, что держали их ровно три стенда: `qa_upd4` (весь блок A),
`qa_sel2` (мёртвый `preload`, ни одного обращения) и `qa_shotcorpse` (снимок
«stars»). Блок A переписан на знамёна — он и должен был проверять их, а не
геометрию звезды; снимок из `qa_shotcorpse` снят целиком, потому что знамёна
уже снимает `qa_banner/Shot`, и второй снимок того же не проверяет ничего.

Вместе со звездой ушла её шкала из конфига: `VET_STAR_TIERS`,
`VET_TIER_COLORS`, `VET_TIER_SCALE`, `VET_STAR_OUTLINE` и `veteran_star_tier()`.
Единственное, что из неё было живым, — цвет обводки значка ранга в панели; он
переехал в секцию знамён как `VET_BADGE_OUTLINE`. `goblin_config` перестал
искать «уровень серебряного грейда» перебором таблицы — теперь ранг задаётся
числом в строке стартового состава.

Переименования в HUD: `_portrait_stars_lbl` → `_portrait_rank_lbl`, узел
`SquadStar` → `SquadRank`. Функция `_stars_text` не вызывалась ниоткуда и
удалена (была мёртвой ещё до правки).

### Стартовый состав: почему список, а не три числа

Прежнее описание орды — «состав `ARMY_COMPOSITION` плюс первым
`VETERAN_START_SQUADS` отрядам выдать грейд `VETERAN_TIER` с
`VETERAN_AUTO_PICKS` наградами» — умело ровно один сценарий. Дать кабанам ранг
выше, чем пехоте, или вывести один отряд-легенду было нельзя, не переписав код
спавна. Теперь строка на отряд: род войск, численность, ранг, число наград.

`ARMY_COMPOSITION` и `ARMY_SQUADS` стали функциями, выведенными из нового
списка. Два независимых списка неминуемо разъехались бы: правка стартовой орды
молча меняла бы то, что орда потом донанимает.

Тот же формат заведён красному ИИ (`ai_start_army_limit.START_SQUADS`), и по
умолчанию он ПУСТ — старт равный, это стережёт `qa_ai` (проверка 2). Непустым
его делает пресет сложности Hard.

Раздача наград сведена в одну функцию `Main.grant_squad_veterancy`, общую на обе
фракции: она идёт тем же путём, каким награду берёт игрок.

### Сложность: множители, а не вторая копия баланса

`game_difficulty_config.gd` не хранит ни одного базового числа. Пресет — это
множители поверх `ai_start_army_limit`, `goblin_config` и
`unit_stats_config` плюс один список-замена. Копия неизбежно разъехалась бы:
владелец правит лимит в своей таблице, а на «обычной» сложности ничего не
меняется, потому что там лежит вторая, забытая цифра.

Из этого следует главное свойство, которое и проверяется первым: **Normal
обязан быть в точности прежней игрой**, все его множители равны единице.
Сложности появились поверх баланса, который настраивали без них.

Крутятся только лимиты и темп — ни одна ручка не трогает урон, запас жизни и
броню. Иначе «сложнее» означало бы «у врага другие правила», и замер боя
перестал бы быть сравнимым между уровнями.

Выбор хранится статикой, а не в `GameManager`: он нужен ДО того, как
автозагрузка успевает что-либо решить (главное меню строится первым), и нужен
он конфигам — а конфиг, лезущий в автозагрузку, тянул бы всё дерево движка в
стенд, который его не поднимал.

### Сохранения: мир пересевается, а не сохраняется

В файл уходит ЗЕРНО (`Main.world_seed`), а карта строится из него заново.
Тысячи деревьев весили бы больше всей остальной партии и читались бы дольше,
чем генерируются. Отсюда двухходовка загрузки: слепок кладётся в
`GameManager.pending_load`, сцена перезапускается, `Main._ready()` берёт зерно
(лес и вода сажаются там же, то есть ДО `start_game()`), и уже
`start_game()` последним делом зовёт `apply()`.

Бойцы ложатся колонками `Packed*Array` — тем же приёмом, что в ядре армии.
Шесть тысяч бойцов это ≈170 КБ и один `store_var`.

`store_var(..., false)`: full_objects выключен намеренно. Разреши ссылки на
объекты — и в файл уехал бы кусок дерева сцены, а чтение такого файла означало
бы исполнение чужого кода.

Живое сносится СМЕРТЬЮ, а не `queue_free`: только на этом пути боец снимает с
себя строку в ядре армии, место в сетке и место в отряде. Та же грабля, что и
у расформирования отряда.

Исследования восстанавливаются через `finish_research` по списку id, а не
числами из файла: бонусы пересчитываются из таблиц, и правка баланса доезжает
до старых сохранений.

Приказы не сохраняются намеренно — приказ ссылается на конкретный узел цели, а
узлы после загрузки другие.

### Масштаб 6000: числа и вывод

Замеры (26.08.2026, headless):

```
марш  3000: тик 6.24 мс (38 %), визуал 3.6 мс, 110 FPS, 107 МБ
марш  6000: тик 13.66 мс (82 %), визуал 8.6 мс,  36 FPS, 190 МБ
бой   6000: сближение 14.51, свалка 18.66, затяжной 17.93 мс — FAIL
```

Решающее число дала перепись линии соприкосновения: **достают до цели оружием
26 %, идут к ней 74 %.** Три четверти армии в свалке платят полную цену
подхода, не имея по кому ударить, — оптимизировать надо не удар, а ожидание
удара. Профиль это подтверждает: `process_attack` — 80.7 % тика.

Полный разбор и план из шести правок — в `docs/PERF_6000.md`. Ни одна из них не
реализована в этой сессии: заказ был на анализ и план, а первые три правки
трогают частоту опроса бойца, то есть требуют своего замерочного окна и своего
A/B, а не попутной правки в уборочной сессии.

## Август 2026: шесть правок масштаба — что окупилось, а что оказалось уже сделано

Заказ владельца: вытащить плотный бой 3000×3000 из FAIL и уложить тик в 11-12 мс
по шести пунктам плана из `docs/PERF_6000.md`. Ниже — то, чего в самом плане
быть не могло: чем он разошёлся с деревом.

### Замер обязан браться в том же заходе, что и правка

Первая же попытка сравнить «до» и «после» по вчерашним числам дала ложный
результат: правка, ничего не менявшая, «ухудшила» тик с 18.66 до 20.31 мс.
Контрольный прогон с выключенной правкой показал те же 20.3 — то есть уехала
БАЗА, а не код. Правило 12 проекта («абсолютное время врёт на загруженной
машине») касается не только соседних прогонов, но и соседних дней.

Дальше всё мерилось так: база, правка, контроль — подряд, по два прогона на
точку. Для мелких правок этого мало, и тогда судит ПРОФИЛЬ (мкс на вызов), а
не итоговый тик: он устойчив, потому что не зависит от того, сколько бойцов
успело умереть к моменту замера.

### Сон задних шеренг: механика уже была, и была отвергнута

Главный пункт плана (−3 мс) оказался уже написанным: `perf_config.battle_lines`,
выключен по замеру ещё раньше, с таблицей цены прямо в комментарии — 24.4 мс
при 33 % бойцов в контакте против 21.5 мс при 20 %.

Я этого не знал, когда писал план, и потому проверил заново — с другой стороны:
не включая старую механику, а написав новую (ожидание фронта в `_process_attack`)
и задрав её порог так, чтобы спали почти все. Получилось 11.3 мс при 6 % в
контакте. **Тот же вывод, полученный независимо: экономятся не лишние вычисления,
а бойцы, переставшие доходить до врага.**

Попутно выяснилось, почему аккуратные варианты не работают. Первый критерий —
«боец за тик не приблизился к цели» — не срабатывал НИ РАЗУ: в свалке дистанция
шумит на сантиметры от расталкивания и от движения самой цели. Второй —
«впереди стоят двое своих» (`_flank_blocked`) — срабатывал у одного из семи,
потому что признак обновляется раз в десять КАДРОВ, а тик бойца шардирован, и
в это окно он попадает раз в десять своих тиков.

Правка откачена целиком. В `PERF_6000.md` пункт закрыт с обоснованием.

### Что окупилось

**Позу отправляет только тот, кого сдвинул не солвер — НЕ ОКУПИЛОСЬ, ОТКАЧЕНО.**
Замысел верный: условие сравнивало точку с последней отправленной, в свалке
срабатывало почти у всех (расталкивание двигает бойца каждый кадр), и
координата уходила обратно тому самому солверу, который её и записал. Но
позицию бойцу присваивают не только пять помеченных мест — так делают стенды,
спавн, сценарии, любой код без `sync_row()`. Раньше такая точка доезжала до
колонки ближайшим тиком; без сравнения она не доезжала вовсе, а разбор
наложения тем временем утаскивал бойца обратно по устаревшей колонке.
Поймал `qa_squad` (проверка 4) через полтора часа после правки. Выигрыш был
0.2 мкс на вызов — в пределах разброса. Снято целиком; метки `_pose_force`
оставлены, они верны сами по себе.

**Отсюда правило:** сравнение координат в `tick_physics` — не «лишняя
проверка», а единственный общий путь, которым внешнее перемещение доезжает до
ядра армии.

**Отрядные сроки растягиваются на большой армии (−1.5 мс).** Разнос по фазе в
проекте уже был; недоставало другого — сами сроки коридора и связки боя
рассчитаны на малую армию, а описывают обстановку, которая с ростом плотности
меняется медленнее. Потолок растяжения двойной, и это замер: при тройном отряд
узнаёт об окончании боя через полторы секунды, и на экране появляется пауза
между «последний враг упал» и «строй сомкнулся».

**Поиск целей (−29 % на вызов).** Двухуровневый выбор цели не понадобился:
9.2 мкс уходили не на скан сетки, а на обвязку — два новых массива на каждый
вызов ради ответа «кто мне чужой» и чтение `global_position` у каждого здания,
хотя здания неподвижны. Теперь справочник строится один раз, координаты зданий
берутся снимком на кадр, своя точка читается по дешёвому пути.

**Будильник вынесен из расталкивания (−0.6 мс).** `BatchSeparation` звал
`u.Call("wake_for_lod")` на каждого сдвинутого — переход границы языков по имени
метода, до двух тысяч раз в кадр, а метод первым же условием выходил. Состояние
сна переехало битом в колонку (`FSleepDraw`).

**Мёртвый код.** `Unit._grid_pos` и пара вычитаний вокруг него остались от
старой поштучной сетки: считались каждый тик у каждого бойца и не читались
нигде.

### Чего делать не стали и почему

`Parallel.For` в расталкивании: цикл не только считает поправки, но и применяет
их — пишет `Node3D.Position` и зовёт метод узла, а к узлам сцены из рабочих
потоков в Godot обращаться нельзя. Разделение на «посчитать / применить»
технически возможно, но превращает Гаусса-Зейделя в Якоби: сейчас каждый
следующий боец видит уже сдвинутых соседей. Результат меняется на сантиметры, а
его стерегут `qa_push` и `qa_crowd` с точностью до сантиметров.

### Итог

`qa_mass_siege` 3000×3000: свалка 12.88 → **11.2 мс**, затяжной бой
13.10 → **11.6-12.9 мс** (разброс прогонов), проверка B3 ПРОШЛО с запасом.
Живых 5343-5466 против 5486, доля бойцов в контакте 25-26 % — бой не изменился.

`qa_mass_battle` 6000: 20.9/20.3 → 18.6/18.1 мс. Стенд остаётся FAIL и это
ожидаемо: он намеренно ставит худший случай — шесть тысяч ЧИСТЫХ копейщиков,
все до одного идущие в контакт. В партии такого состава не бывает.


## Август 2026 (вторая партия): два стенда покраснели от РАЗВОРОТА ТРЕБОВАНИЯ

Оба случая — ровно то, о чём предупреждает правило 10 проекта, и оба стоили
времени, потому что выглядели как регрессии.

1. **`qa_formation` D2 «опускание НЕ одновременное»** держал ЖЁСТКУЮ четырёхсотку
   миллисекунд, посчитанную под прежний разброс `Spearman.DROP_DELAY_MAX_MS`
   = 1900. Владелец разброс сократил (жалоба «копья выставляют один-два
   человека, приходится нажимать кнопку дважды»), и проверка честно покраснела
   на 185 мс. Порог переписан НА СВОЙСТВО и выводится из самого конфига —
   четверть заданного разброса: волна есть, шлагбаума нет.
2. **`qa_vet` 4г «на крайнем левом месте ряда»** покраснел на 0.8 м, то есть
   ровно на один интервал строя. Причина не в новом правиле выбора знаменосца
   (по `slots[0]`), а в том, что смыкание рядов рассаживает людей по
   ПЕРЕНЕСЁННОЙ разметке (`_slots_recentered` / `_slots_moved_to`), а в записи
   отряда лежит исходная. По исходной точке ближайшим оказывался сосед по
   колонке. Лечится не порогом, а передачей ТОЙ ЖЕ разметки в
   `_assign_bearer` третьим аргументом.

**Вывод, который стоит помнить:** покрасневший стенд после правки — это ещё не
регрессия. Сначала надо посмотреть, не описывает ли проверка требование,
которое только что развернули, и не сравнивает ли она две разные величины,
называя их одним именем.

## Август 2026: профиль партии на 3000+ и второй заход по кадру (`qa_mass3k`)

Жалоба владельца: «при 3000 юнитов (1200 игрока + 1000 орков + 800 ИИ) и
работающей экономике FPS проседает до 41; хочу 60-70 минимум».

### Чем меряли и почему понадобился ещё один стенд

`qa_fps` меряет ДВЕ СТОЯЩИЕ АРМИИ копейщиков, разведённые по углам: ни боя, ни
рабочих, ни смешанного состава. Заведён **`qa_mass3k`** — окно 1920×1080, три
армии смешанного состава сходятся в одну кучу в центре, у обеих сторон по сорок
рабочих на добыче, туман, HUD, растительность и деревня гоблинов на месте.
Всего живых юнитов **3880** (три тысячи стенда плюс спящая деревня и стартовые
отряды самой сцены) — то есть сцена ЖЁСТЧЕ той, на которую жаловались.

Две ловушки замера, обе стоили по прогону:

1. **СЦЕНА УТЕКАЛА ИЗ-ПОД ЗАМЕРА.** За минуту A/B армия редела с 3500 до 2000,
   тик падал сам собой, и «вариант B» получал фору просто потому, что мерился
   позже — первая версия так намеряла ОТРИЦАТЕЛЬНЫЙ прирост кадров при явно
   более дешёвом тике. Лечится заморозкой потерь (`_freeze_losses`): запас жизни
   поднимается всем разом, бой идёт как шёл, но никто не выбывает.
2. **КАДРЫ НЕ СКЛАДЫВАЮТСЯ, А ФИЗИКА НЕ ЛИНЕЙНА.** Физика идёт фиксированные
   60 Гц, поэтому при кадре в 24 мс на него приходится 1.43 физического тика.
   Отсюда честное уравнение кадра:
   **FPS = (1000 − 60 × физтик_мс) / R**, где R — вся остальная работа кадра
   (визуальный проход, подача буферов, рендер). Проверка: (1000 − 60×9.45)/10.34
   = 41.9 — ровно то, что показывает счётчик.

Это уравнение и есть главный вывод захода: **каждая миллисекунда физтика стоит
60 миллисекунд процессорного времени в секунду**, и потому тик — единственная
статья, где правка окупается кратно.

### Что было и что стало

| фаза (3660-3880 юнитов, 1920×1080) | было (3 шарда) | стало (4 шарда) |
|---|---|---|
| стоят, экономика идёт | 41.4-43.2 FPS, физтик 10.0-10.5 мс | **44.2 FPS, 8.21 мс** |
| свалка трёх армий | 33.5-38.2 FPS, физтик 11.1-12.3 мс | **41.9 FPS, 9.45 мс** |

### Разбор кадра в свалке (после правок)

    кадр 23.89 мс = физтик 9.45 × 1.43 тика (13.55) + кадр логики 3.96 + рендер ~6.4
    вызовов отрисовки 519 (из них ~190 — стрелы: у каждой свой узел и свой вызов)

Цена подсистем (гасим и ВОЗВРАЩАЕМ, против среднего двух базовых замеров):

| подсистема | без неё, FPS |
|---|---|
| физический тик армии | **68.0** |
| визуальный тик армии | 54.8 |
| стрелы (187 вызовов отрисовки) | 50.6 |
| растительность | 48.0 |
| мышление ИИ | 49.4 |
| туман войны | 41.6 (в пределах разброса) |
| HUD | 45.1 |

### A/B чередованием (три раунда, замороженная численность)

| правка | физтик | вывод |
|---|---|---|
| шардов физики 3 → 4 | 9.78 → 8.01 мс (**−1.77**) | взято |
| шардов физики 4 → 5 | 8.04 → 7.01 мс (−1.03) | НЕ взято, см. ниже |
| визуальных шардов 2 → 4 | −0.03 мс | не окупается |
| такт позы 5 → 8 кадров | −0.25 мс | не окупается |

**Четвёртый шард взят, пятый — нет.** Прежний потолок стоял на трёх с пометкой
«ниже нельзя, виден рывок». Пометка писалась ДО того, как догон картинки и
визуальный проход обзавелись своим шардированием и сглаживанием: рывок сейчас
гасит не частота опроса, а сглаживание нарисованной точки. Пятый шард — это 12
опросов в секунду, 0.17 м за шаг, и на подходе к цели это уже видно.

### Что убрано из горячего пути

- **Часы армии читаются раз в кадр** (`Unit.now_ms`). `Time.get_ticks_msec()` —
  вызов в движок, и он стоял в шести местах, каждое НА БОЙЦА: замер смещения в
  физтике, туман и такт позы в визуальном, срок опускания копья у копейщика.
- **Номер физического кадра — тоже раз в кадр** (`Unit.phys_frame`).
  `Engine.get_physics_frames()` стоял во фланговом обходе (`_flank_step`), то
  есть у каждого бойца в трёх с половиной метрах от своей цели — почти у всей
  свалки в каждом её тике.
- **Сторона обхода считается при рождении** (`Unit._side_sign`).
  `get_instance_id()` — тоже вызов в движок, а значение постоянно за всю жизнь
  узла; спрашивали его в трёх горячих ветках.
- **Догон картинки получил долю аргументом и развёрнутую арифметику**
  (`Unit.tick_draw(k)`): чтение `GameManager.vis_lerp_k` из каждого бойца и
  второй вызов `_smoothed()` убраны. Ветка выключена по умолчанию
  (`perf_config.draw_catchup`), но остаётся рычагом A/B, и рычаг должен быть
  честным.

**По отдельности ни одна из этих правок из шума не вылезла** — сумма их эффекта
меньше разброса прогонов (±0.5 мс тика). Записаны они не как победа, а как
устранение работы, которой не должно быть: правило проекта «общее на армию
читать раз в кадр» нарушалось шестью местами сразу.

### Чего достичь НЕ УДАЛОСЬ, и почему

Заказ был 60-70 FPS. На 3880 юнитах в свалке получено 41.9. Разрыв объясняется
арифметикой, а не недоработкой:

- при физтике 9.45 мс физика съедает 567 мс из каждой секунды процессора;
- на кадры остаётся 433 мс, и при R = 10.3 мс это ровно 42 кадра;
- чтобы получить 60 FPS при нынешнем R, физтик обязан упасть до **7.2 мс**,
  а при R = 7 мс — до 8.5 мс.

Замер «выключить физический тик армии целиком» даёт 68 FPS — то есть весь
остальной кадр (визуал, рендер, ИИ, туман, экономика) в шестьдесят кадров
укладывается с запасом. Упирается всё в тик, а он **размазан**: крупнейшая
ветка `process_attack` — четверть, дальше `grid_update`, `sep_overlap`,
`squad_corridor`, и ни одной статьи больше 25 %. Одной правкой такое не
снимается; нужен либо перенос боевого автомата в солвер (проверен и отвергнут
замером — см. `perf_config.batch_combat`), либо снижение частоты опроса ниже
15 Гц, что уже видно глазом.

**Что доступно владельцу одной строкой, если кадр важнее плавности:**
`perf_config.tick_shards_max = 5` — ещё −1.0 мс тика и примерно +4 кадра, ценой
заметного шага на подходе к цели.

---

## Август 2026: балансный заход — TTK, мораль, экономика, ветеранство

Расчётный документ — `docs/BALANCE_MATH.md`. Здесь только то, что выяснилось
ЗАМЕРОМ по ходу, и то, что покраснело.

### Замеры до и после

| | было | стало | заказ |
|---|---:|---:|---|
| Дуэль копейщик × копейщик | 9.3 с | **30.0 с** | 30–60 с |
| Схватка 60 × 60, перелом | 14 с | **31 с** | 30–60 с |
| Схватка 60 × 60, истребление | 26 с | **57 с** | — |
| Первый узел кузницы (бригада 4+4) | мгновенно | **2.7 мин** | ~3 мин |
| Хватает ли старта на два узла | на двадцать | **нет** | нет |

### Три вещи, которые пришлось чинить по замеру, а не по чертежу

**1. Потери считались долей штата ИЗ КОНФИГА, и паника не наступала никогда.**
Отряд бывает неполным: последние из барака, огрызок после боя. Стенд ставил
12 бойцов, конфиг говорил «шестьдесят», и гибель ВСЕХ ДВЕНАДЦАТИ снимала пятую
часть морали. Лечение — `GameManager.squad_full_size()`: НАИБОЛЬШИЙ состав за
жизнь отряда, пишется в `add_to_squad`. Поймал `qa_balance` C1.

**2. `MORALE_GAIN_PER_KILL` = 12 отменял механику целиком.** Отряд отыгрывал
мораль за убийства быстрее, чем терял её за своих павших, и паниковала только
сторона, проигравшая всухую, — то есть та, которой паника уже не нужна.
Опущено до 2.0, `MORALE_LOSS_PER_DEATH` поднят с 55 до 90.

**3. Полтора десятка стендов покраснели от УДВОЕНИЯ ЗАПАСА ЖИЗНИ, а не от
поломок.** Это самый дорогой урок захода: числа времени и дистанции, зашитые в
стенды, были выведены из ПРЕЖНЕЙ длительности боя.

* `qa_vet` #5 проверял ВЫЧИТАНИЕ брони — переписан на вызов
  `_UCfg.damage_after_armor`;
* `qa_leash` L1/L3: 45 с на снос заслона и 6 м допуска — заслон теперь живёт
  вдвое дольше; подняты до 100 с и 9 м;
* `qa_cavalry` E3: 900 кадров ожидания → 2100;
* `qa_combat_lock` #2/#4: чужой отряд ПАНИКОВАЛ и убегал, и бой кончался
  раньше, чем гибнул последний. Стенд про смыкание рядов, а не про мораль —
  подопытному отряду выдан `legend_steadfast` (иммунитет к панике);
* `qa_recon` C1 сравнивал `int(bonus)` с округлением в HUD;
* `qa_leash` L1 ослаблял нападающих строкой `max_health = 50.0` — половиной от
  прежних семидесяти. При базе 180 это стало ЧЕТВЕРТЬЮ, и шестнадцать
  нападающих гибли все до одного, не досняв заслон из восьми. Переписано на
  ДОЛЮ от базы (×0.5).

**Общее правило подтвердилось: стенд, зашивший число из конфига, краснеет на
первой же правке баланса.** Проверять надо СВОЙСТВО.

### Подгонять долю до узкой щели — не починка, а лотерея

У `qa_leash` L1 половинное здоровье стояло не просто так: прежний комментарий
обещал, что заслон выбьет ЧАСТЬ отряда и тем проверит смыкание рядов ПО ГИБЕЛИ.
С новым TTK размен шестнадцати против восьми настолько односторонний, что щели
между «не гибнет никто» и «гибнут все» не осталось вовсе:

| доля запаса | свои живы | заслон жив |
|---:|---:|---:|
| 0.28 (прежние 50 очков) | 0 из 16 | 2 из 8 |
| 0.35 | 16 из 16 | 2 из 8 |
| 0.50 | 16 из 16 | **0 из 8** |

Взята половина — проверяемое свойство («заслон на пути снесён») она держит
устойчиво, два прогона подряд. Обещание про смыкание по гибели из комментария
УБРАНО, а не подогнано: это путь `qa_combat_lock` (блоки 2 и 4), где он и есть
предмет стенда. Стенд, который держится на удачном исходе боя, хуже, чем
стенд, честно проверяющий одно свойство.

### Почему у `qa_melee` F2 не стало проверки «отряд ушёл на N метров»

Добавил и убрал. Двенадцать на двенадцать СЦЕПЛЕНЫ телами, и пока противник
жив и держит, отряд никуда не уходит — сколько ни жди (замер: за 12 секунд
смещение −1.0 м, то есть в сторону врага). Требование другое и оно выше:
приказ РВЁТ СВЯЗКУ, то есть ни у кого не остаётся цели (0 из 12). Дистанцию
отхода честно меряет `qa_disengage` A4, где противник отряд не держит.

---

## Август 2026 (четвёртая партия): семь жалоб — пять общих причин

Разбор по разделам заказа — в `CLAUDE.md`. Здесь только то, что стоит помнить
при следующей правке: **семь внешне разных жалоб свелись к пяти корням**, и
четыре из этих корней уже встречались в проекте под другими именами.

### 1. Послабление, выданное всем, работает не туда, ради чего заведено

`_forced_move_pass` заводился под ОДИН случай — «отряд в плотной рубке не идёт
с первого клика». Выдавался он ЛЮБОМУ приказу игрока, и всадник, кликнутый из
чистого поля, получал те же полторы секунды прохода сквозь тела — то есть
проезжал строй копейщиков насквозь. Жалоба звучала как «баг коллизий», а была
разрешением, выданным слишком широко.

**Урок: у послабления обязано быть УСЛОВИЕ ВЫДАЧИ, а не только срок.**

### 2. Признак, который ставит солвер, отвечает не на тот вопрос

Первая версия условия выдачи спрашивала `_enemy_contact` («мой шаг упёрся в
чужое тело»). Замер `qa_disengage` D2: окружённый боец прошёл **0.00 м** — он
не шагает вовсе, шагать он начнёт только от этого приказа. Спрашивать надо было
ГЕОМЕТРИЮ, а не историю шага.

### 3. Узел живёт дольше записи, которая им управляет

Белый флаг паники ездит за отрядом из `_update_panic_flags`, а тот обходит
РЕЕСТР отрядов. Расформированный отряд из реестра уходит — и флаг остаётся в
мире навсегда. Ровно та же форма, что у метки приказа (`squad_orders`) и у
знамени ветеранства, и оба этих случая уже были починены в `_disband_squad`; у
флага строки там просто не оказалось.

**Урок: всё, чем управляет запись реестра, обязано гаснуть в `_disband_squad`.**

### 4. Одно число не выражает два требования

`MORALE_LOSS_PER_DEATH` отвечало сразу за «страшно» и за «нас почти не
осталось». Владелец потребовал сдвинуть второе (срыв при 3-7 выживших) — а
двинулось бы и первое. Разделили: мораль осталась мерой страха,
`PANIC_LAST_MEN` считает живых. Побочно выяснилось, что счёт живых нельзя
вести в головах — конный отряд из десяти моделей срывался бы после четырёх
потерь, отсюда `squad_weight` (заказ владельца «1 всадник = 2 пехотинца»).

### 5. Переопределённый tick_physics не доходит до базового — значит, не тикает и всё, что там считается

Две жалобы («рабочие несут ресурсы спиной вперёд», «на стройке бегут на месте»)
оказались одним корнем: `Worker.tick_physics` в трёх своих состояниях выходит
раньше `super`, и окно замера смещения у работающего рабочего не тикало НИ
РАЗУ. `_mv_dir` оставался направлением К дереву, пока рабочий едет ОТ него.
Вынесено в `Unit._sample_movement()` и зовётся из обеих веток.

**Урок: при переопределении горячего тика надо проверять не только то, что
добавлено, но и то, что перестало вызываться.**

### Чего в этой партии НЕ делали

* **Не заводили физические тела и маски столкновений.** Требование «пехота
  оказывает физическую блокировку для кавалерии» уже выполнено солвером
  (`enemy_block` в пакетном шаге) — не работало оно ровно из-за пункта 1.
* **Не заводили второй механизм движения для подтягивания фланга.** Отряду
  выдаётся ЦЕЛЬ (`command_attack`), а подход к ней делает штатный марш. Раздача
  поштучных `command_move` в бою в этом проекте уже проверена и отвергнута —
  она рвала отряд цепочкой и заставляла рабочих бросать работу.

## Сентябрь 2026: сон idle-анимаций, пиксель руды и стресс 30-й минуты (3300+)

### «Лучники и рыцари еле дышат» — виноват сон визуального тика, а не fps лент

Темп у всех лент покоя одинаковый (6 к/с, `SpriteSheetParser._default_fps`), а
кадры в общей отрисовке листает ТОЛЬКО визуальный тик (`_advance_look_frame`)
— узел спрайта стоит на паузе (`_look_detach_node`). Стоящий боец засыпает по
картинке (`set_draw(false)`), и его idle замирает на случайном кадре. Копейщик
единственный держал правило «многокадровый покой не усыпляем»
(`Spearman._process_can_sleep`, «застывал статуей»), у мечника стоял устаревший
комментарий «AnimatedSprite3D крутит цикл сам» — верный до общей отрисовки.
Правило поднято в базу (`Unit._process_can_sleep`: `_look_loop and
_look_frames > 1` — не спим) и продублировано в переопределении мечника (он не
зовёт super). Кадров в лентах покоя: копейщик 12, мечник 8 (guard 6), лучник 6,
рабочий 8 — теперь дышат все. Цена на стресс-сцене не видна (фаза 1 qa_mass3k:
42.4 FPS на 4238 живых, экономика идёт).

### Пиксель руды приведён к юнитскому (заказ: «перерастянутый комок»)

Пиксель бойца 0.0108 м; у руды был 4.4/128 = 0.034 (золото) и 3.8/64 = 0.059 м
(камень) — в 3.2 и 5.5 раза крупнее, и поверх ZOOM_MAX дотягивал ещё до 1.75x.
Сделано: `FRAME_METRES_GOLD` 4.4 → 2.0, `_STONE` 3.8 → 1.55, `ZOOM_MAX` 1.75 →
1.25, `PIECE_TARGET_H` 1.28 → 0.85 (и `pick_body_h` выведен из неё, а не 0.64
числом). Главное — вариант рисунка привязан к классу (`Main.ORE_VARIANT_POOLS`):
обмер кадров показал заполнение 20-57% у золота и 38-61% у камня, и «big»-кусок
со случайным мелким вариантом надувался зумом — теперь крупный класс берёт
крупно НАРИСОВАННЫЙ вариант. Раскладки перевёрнуты с «массы крупняка» на
россыпь (1-2 big + 3 mid + мелочь; координаты кусков не тронуты — понижены
только классы), `LAYOUT_SPAN_STONE` 1.0 → 0.75 (куски усохли, размах должен
был усохнуть следом). `WORLD_GEN_VERSION` 2 → 3: на кусок добавился вызов
randi(), поток генератора сдвинулся. Снимки — qa_gold/OreShot (оконный, без
вердиктов, ставит кучи САМ на расчищенном месте). Проверено: qa_aspect 0/15,
qa_helpbuild 0/24, qa_pivot 0/10, qa_res2 0/45, qa_visual_smoke 0/19.

### Стресс 30-й минуты: 1500+800+1000+100 рабочих (qa_mass3k, RTX 4070, 1920x1080)

Два полных прогона (числа второго / в скобках первый, где расходятся):
- ФАЗА 1 «стоят, экономика идёт», 4238 живых: 42.4 FPS, физтик 9.59 мс,
  кадр логики 4.17 мс.
- ФАЗА 2 «свалка на три стороны», 4080 живых: 37.0 FPS (27.0 мс), физтик
  11.73 мс x 1.62 = 19.0 мс на кадр, кадр логики 5.36 мс.
- ФАЗА 3 «реальные потери + волна с края» (НОВАЯ, дописана в стенд; смертность
  возвращается, 200 гоблинов заходят с края, ветеранство и укладка тел живые):
  при 111 смертях/с кадр +1.71 мс и физтик +0.35 мс против замороженной свалки
  (первый прогон: +0.70 / -0.09). **Гибель, опыт и трупы — НЕ убийца кадра.**
- Цена подсистем (гасим-меряем-возвращаем): физтик армии 6.3 (3.5) мс кадра —
  без него 52 FPS; визуальный тик 2.0 (3.8) — без него 46-53 FPS; **мышление
  ИИ 2.45 (2.29) мс — стабильно в обоих прогонах и подозрительно дорого для
  такта раз в 2 с**; HUD 1.4 (0.8); тела павших 1.8 (0.45); туман,
  растительность и стрелы — в пределах разброса (знак прыгает).
- Разбивка тика (ранжирование): process_attack 25% (4.0-4.1 мс, ~900
  вызовов/кадр по 4.5 мкс — КАЖДЫЙ тикнутый в свалке идёт этой веткой),
  vis_far 14.5%, squad_corridor 7%, atk_strike 6.5%, grid_update 5.5%,
  sep_overlap 5.4%. Гипотезы «O(N^2) поиск целей», «мусор трупов» и «просчёт
  опыта» СНЯТЫ ЗАМЕРОМ: atk_find_enemy 0.13 мс, слой тел и смерти — выше.
- A/B чередованием: шарды физики 3v4 — 4 лучше (+5.9 FPS, авто-выбор верен);
  4v5 — тик дешевле на 1.4 мс, но FPS не растёт (не брать); визуальные шарды
  2v4 — кадр логики -1.55/-1.83 мс, +1.9/+2.1 FPS В ОБОИХ прогонах (кандидат,
  цена — отставание нарисованной точки); такт позы 5v8 — шум (+1.2 и -3.7).

## Сентябрь 2026, этапы A и B: горб орды, дрёма боя, плотный список живых

### Мышление ИИ: 2.4 мс/кадр давал ТАКТ ОРДЫ, а не частота

qa_mass3k показывал стабильные 2.3-2.5 мс «мышления ИИ» на кадр, при том что
оба ИИ думают раз в 2 с и между тактами выходят в две строки. Зонд
`qa_mass3k/AIProbe` (headless, свалка 3300, ручной прогон _process с
секундомером) разложил: красный ИИ — 2-6 мс на такт (его раздача давно
нарезана `_drain_orders`), а ОРДА — **46-72 мс на такт**: `_issue_orders`
выдавал command_attack/command_move КАЖДОМУ из тысячи гоблинов каждые две
секунды, даже когда ни фаза, ни цель не менялись. Перенесены оба приёма
красного ИИ: неизменившийся приказ не переиздаётся (отряд в бою не трогается
вовсе; марш в ту же точку — не чаще REISSUE_KEEPALIVE_SEC = 8 с), раздача
нарезана очередью по ORDER_BUDGET_MEMBERS = 150 бойцов за кадр. A/B зондом:
**476 → 86 мс** на 900 кадров, максимальный горб **72 → 12 мс**. В qa_mass3k
цена «мышления ИИ» упала с 2.45 до 0.22 мс (уровень шума).

### Дрёма перезарядки (`Unit._atk_snooze`)

process_attack — крупнейшая ветка тика свалки (~25%, ~900 вызовов/кадр), и
почти все вызовы — боец, стоящий В УПОР к цели в ожидании остывания удара.
Теперь такой боец дремлет: тело функции сворачивается до тика таймера,
пробуждение за ATK_SNOOZE_SPARE = 0.15 с до готовности, следующий тик заново
меряет дистанцию штатно. Дрёму снимает смена цели (set_attack_target, включая
гибель цели сигналом died). Лучник в залпе не дремлет по построению (его
таймер зажат в ноль). Замер: process_attack 4.46 → 4.06 мкс/вызов, физтик
свалки 11.7 → 10.8 мс (вместе с плотным списком). DPS не меняется — таймер
тикает той же арифметикой.

### Плотный список живых строк — СДЕЛАН, И ОН ОТСОРТИРОВАН

Снят пункт roadmap. Ключевое решение: список ЖИВЫХ строк (`_liveRows`)
держится ОТСОРТИРОВАННЫМ (вставка/удаление сдвигом через двоичный поиск), а
не свапом с последним — порядок обхода тогда в точности равен прежнему скану
`0.._top` по занятым, порядок соседей в ячейках сетки не меняется, и выбор
цели при ничьих (`EnemyAt`/`BestEnemy`/`NearestOfSide`) остаётся прежним —
ровно та опасность, из-за которой задача лежала в roadmap. Цена сдвига при
сотнях смертей в секунду — микросекунды против экономии итерации в трёх
проходах каждый кадр. Все четыре обхода (`RecomputeBounds`, `FillGrid`,
`BatchSeparation`, `BatchCombat`) идут по списку; `_top`/`Top()` оставлены
(их читают стенды). Шлюз после правки: 30+ стендов зелёные, `qa_army/SelfTest`
0/18.

### Правки замеров, всплывшие на прогоне шлюза (все три — ошибки замера)

- **qa_guard H1/H2/J1** утверждали РАЗВЁРНУТОЕ требование «стоящие мечники
  засыпают» — сон покоя снят правкой «еле дышат» (сент. 2026). Переписаны на
  новое свойство: стоящий мечник НЕ спит и права на сон при многокадровой
  ленте нет (`_process_can_sleep()` == false — свойство, не зависящее от LOD).
- **qa_melee B1/B2** сверяли КЭШ возрастом до MELEE_TTL_MS с ручным счётом
  «сейчас», да ещё трёхмерной дистанцией против планарной у учёта — на границе
  дальности расхождение в единицу. Теперь стенд зовёт `_recalc_melee` и меряет
  той же метрикой в том же кадре.
- **qa_clash A2** — ножевой порог: равновесие в контакте ПО ПОСТРОЕНИЮ садится
  ровно на границу мёртвой зоны (0.33-0.35 при пороге 0.333), строгое `>=`
  мигало на третьем знаке. Дан допуск 0.02 м — заведомо меньше настоящего
  провала «расталкивание сдалось».
- **qa_cavalry E3** покраснел один раз В ПАКЕТЕ, где параллельно шёл
  dotnet build (правило 12 — сам себе загрузил машину); на чистой машине
  дважды зелёный. **qa_mega_battle B2-0** дал 1 просочившегося из 493 один раз
  из четырёх — редкая утечка семейства qa_wall A1, в трёх прогонах 0.

### Контрольный qa_mass3k (1500+800+1000+100, RTX 4070, 1920x1080)

| фаза | было | стало | выигрыш |
|---|---|---|---|
| стоят, экономика | 42.4 FPS / 23.6 мс | **50.0 FPS / 20.0 мс** | +7.6 FPS / −3.6 мс |
| свалка 3 стороны | 37.0 FPS / 27.0 мс | **42.4 FPS / 23.6 мс** | +5.4 FPS / −3.4 мс |
| реальные потери | 34.8 FPS / 28.7 мс | **37.3 FPS / 26.8 мс** | +2.5 FPS / −1.9 мс |

Слагаемые: орда без горба (−2.2 мс кадра), vis_shards_extra 4 (кадр логики
5.36 → 3.86 мс), дрёма + плотный список (физтик свалки 11.73 → 10.84 мс).
Цель этапа A «45+ на 3300» в фазах 1-2 взята (42-50 на 4100-4200 живых с
деревней), этап B двинул свалку, но главный резерв остаётся прежним:
process_attack 3.49 мс (21%) и vis_far 2.36 мс (14.5%) — это этап C
(порт боевого автомата свалки в C#).

## Сентябрь 2026, этап C: дрёма боя в ядре — третий замер закона о пакетной природе

### Что сделано

Дрёма перезарядки перенесена из GDScript в ядро (`ArmyCore.TickSnooze`,
`FAtkSnooze = 1 << 18`, колонка `_atkReach`): пока боец в упоре к цели ждёт
остывания удара, его GDScript-автомат не входит даже в тело `_process_attack`
(гейт в диспетчере `tick_physics`), а таймер и стражу цели ведёт C#-проход по
плотному списку живых. Пробуждение — событие: за `ATK_SNOOZE_SPARE` (0.15 с)
до готовности, при гибели цели и при уходе цели за
`attack_range + pad + ATK_SNOOZE_REACH_SLACK` (0.6 м; без люфта качание свалки
будило весь фронт каждые пару кадров, и выигрыша не было ВООБЩЕ). Список
проснувшихся забирается вторым вызовом только при ненулевом счёте — в тихий
кадр один переход границы и ноль аллокаций. `_attack_timer` на время дрёмы
заморожен и синхронизируется при пробуждении/снятии; читатели снаружи
(`_sweep_volleys`) видят арм-значение — честное «не готов».

### Честная цена — A/B чередованием, и только им

Межпрогонные сравнения оказались мусором: фаза «стоят» (дрёма не участвует)
уплывала между прогонами одного кода на 7 FPS (50.0 / 47.7 / 42.8) — машина
дрейфует за десятки минут. В `qa_mass3k` добавлен A/B-блок «дрёма ВЫКЛ против
ВКЛ» (ручка `perf_config.atk_snooze`, 4 раунда чередованием):
**физтик 11.18 → 10.71 мс, экономия +0.47 мс тика**; кадр логики и FPS — шум.
Цена самого прохода TickSnooze — 0.14 мс (уже внутри стороны «вкл»).

**Это ТРЕТИЙ замер одного и того же закона** (первые два — qa_fx и qa_ab по
полному BatchCombat, см. шапку perf_config.batch_combat): смена языка
вычислителя окупается только у работы с пакетной природой. Ожидание кулдауна
однородно — и отдаёт свои полмиллисекунды; решающие ветки (подход, перехват,
перенацеливание) разнородны, и «process_attack из топа» переносом в C# не
уходит: его профильные ~4 мс — это ~870 гейтированных входов с ценой обвязки
плюс ~300 настоящих полных автоматов по ~10 мкс. Следующий рычаг тика боя —
не язык, а ЧАСТОТА решений либо частота физики (30 Гц с интерполяцией).

### vis_far — у него пакетная природа ЕСТЬ, и это следующий кандидат

2.4-2.7 мс визуального прохода — однородная работа (догон точки + запись трёх
float на бойца). Честный порт = буфер бакета во владении C# (RID MultiMesh +
RenderingServer.MultimeshSetBuffer из C#), то есть хирургия FarUnitRenderer с
его каналами урона, кадров и foot_drop. Не начата: объём отдельного захода.

### Попутные находки (обе — не дрёма)

- **qa_target_lock F2 мигал НЕ из-за правок**: выключение дрёмы целиком
  оставило флейк (1 из 4). Зонды показали цепочку: приманка-копейщики в стойке
  АТАКА сами шли на лучников (авто-агро, 7 м — в радиусе инициативы), добегали
  и били с длины руки, а удар В УПОР под замком ЗАКОННО получает ответ
  (приоритет №2). Проверка мерила гонку «успеет ли приманка дойти за окно», а
  не замок. Приманке дана стойка ЗАЩИТА (стоит соблазном, не подходит) —
  5 прогонов из 5 зелёные.
- **Правило 5 в моей же очереди орды**: `var foe: Node3D = plan.get("foe")`
  бросает на освобождённой цели ДО проверки живости (цель пала, пока запись
  ждала кадра). Исправлено сырой ссылкой.
- **Оконный измерительный стенд обязан снимать случайную паузу**: пауза партии
  висит на ПРОБЕЛЕ, окно забирает фокус, и случайное нажатие замораживает
  дерево — все метры дальше честно меряют мёртвую сцену (физтик −1, «393 FPS»
  свалки). `qa_mass3k._sample` теперь снимает `get_tree().paused`.

## Сентябрь 2026, этапы C.1-C.2: буферы отрисовки в ядре и приговор 30 Гц

### C.1: буферы MultiMesh и покадровый догон картинки — в ядре

Буферы бакетов переехали из GDScript (PackedFloat32Array в
FarUnitRenderer.Bucket) во владение C# (`ArmyCore.Rb`), подача —
`RenderingServer.MultimeshSetBuffer` из ядра (RbFlush, один вызов на грязный
бакет). GDScript остался владельцем ЖИЗНЕННОГО ЦИКЛА (создание бакетов,
материалы, foot_drop, раздача слотов) и СОБЫТИЙНЫХ записей (полная запись при
смене ленты, кадр походки, урон, скрытие) — теперь это делегаты в ядро.
Покадровый догон нарисованной точки, покачивание шага и запись позиций ведёт
`ArmyCore.BatchVisual` — один C#-проход по плотному списку живых КАЖДЫЙ кадр
отрисовки (строки привязываются к слотам через RowBind при регистрации).
Семантика GDScript-пути повторена дословно: сглаживаются только X/Z, Y идёт за
логикой, предохранитель телепорта `VIS_SNAP_SQ`, боббинг sin² от фактической
скорости строки со сбросом у стоящего; разлёт от тарана (F_VIS_SELF) ведёт
картинку сам и по концу полёта возвращает строку ядру (RowSyncDraw).
`draw_position()` привязанной строки читает ядро (знамёна, кольца).

**Честная цена (A/B чередованием в qa_mass3k, ручка perf_config.vis_core_path,
обе стороны пишут в буферы через ядро): кадр логики 9.29 → 8.53 мс,
−0.76 мс.** Оставлено включённым. Профильная строка vis_far при этом ВЫРОСЛА
(6.2 мкс/вызов) — это цена измерителя и подорожавших СОБЫТИЙНЫХ переходов
границы; решает не профиль, а чередование (третий раз за месяц).

Побочные окна для стендов: rb_slot (16 float слота), rb_dirty/rb_clear_dirty —
qa_wound читал буфер и флаг грязности напрямую. Зонды: qa_mass3k/BindProbe
(доля привязанных строк — 200 из 200).

### C.2: 30 Гц — пробовано ДВУМЯ способами, оба сняты замером

**Глобальные 30 Гц движка** (project.godot) сняты за один прогон шлюза: в
МЕЛКИХ сценах (1 шард) дельта бойца удваивается (1/60 → 1/30), и qa_wall тут
же поймал участившееся протекание сквозь строй (прямая жалоба владельца);
часы стендов, меряющие время в физкадрах, поехали все разом; стенное время
pframe-стендов удвоилось.

**Половинный тик АРМИИ** (движок 60 Гц, весь обход армии в
GameManager._physics_process каждый второй такт с накопленной дельтой,
`perf_config.army_tick_div`; личную частоту бойца сохраняет лестница шардов от
`army_hz()`) — построен, отлажен и ИЗМЕРЕН: A/B чередованием (4 раунда, два
прогона) даёт физтик-за-секунду лишь ~5% дешевле (10.0 мс × 60 против
18.7 мс × 30), кадр логики +2.2-2.7 мс и FPS −0.7…−1.3 — редкий тяжёлый тик
ломает пейсинг кадра. **Делитель возвращён в 1; ручка и A/B-блок в стенде
остаются.** Урок: тактовые статьи (сетка, свипы, обвязка) малы, тик армии
почти целиком состоит из по-юнитной работы, УЖЕ прореженной шардами до 15 Гц
на бойца — халвинг частоты не даёт ей ничего.

**Ловушка, съевшая половину отладки: фаза шардов от номера кадра движка.**
При делителе 2 армия тикает по чётным кадрам, и `get_physics_frames() % shards`
при чётном числе шардов давал вечно одну фазу — ПОЛОВИНА армии не тикала
вовсе (qa_mega_battle B4-3: «сдвинулись 300, остались 300» — ровно половина).
Заведён счётчик тактов армии (GameManager.army_ticks), все фазы — от него.

### Стенды, вскрытые сдвигом фаз тактов (все — ошибки замера, код цел)

- **qa_ai2 B4**: приманка ставилась от точки СТАРТА отряда, а контакт меряется
  от живого центроида МАРШИРУЮЩЕГО (зонд: 11.4 м до приманки — честное «нет
  контакта»); плюс `_spawn` стенда не звал sync_row, и сетка не видела свежих
  до их первого личного тика. Приманка — от центроида, sync_row добавлен.
- **qa_squad 4**: стенд ТЕЛЕПОРТИРОВАЛ приманки узлом без sync_row — строки
  ядра оставались со старыми позициями, и клик находил пустую сетку
  (зонд: grid_рядом=0 при совпадающих координатах). sync_row добавлен.
- **qa_ui9 5** «золото плотнее камня» — требование легально перевернулось
  переделкой руды (крупный кусок теперь делается АРТОМ, а камню размах ужат
  сильнее); проверка переписана на «обе кучи компактны».
- **qa_formation B2** (вне главного шлюза) красен ОДИНАКОВО на делителе 1 и 2
  (1 из 10) — к заходу отношения не имеет, пре-существующий; его тему несут
  qa_reform (0/16) и qa_mass_siege (проход 35 из 35).
- **qa_world3** (вне шлюза) длиннее 10 минут стенного времени — не прогнан.

### Итог шлюза на финальной конфигурации

40+ стендов зелёные; красные — только документированные qa_melee F2 (ждёт
решения владельца) и мигающие qa_wall A1 / qa_mega_battle B1-1 (ножевой
порог 11.6-13.6, краснеет и на неизменном коде).

## Сентябрь 2026, спринт D — этап D1 построен, gate-check остановил D2/D3

### Что построено

**Тыловой напор** (`ArmyCore.RearPressPass`, F_REAR_PRESS = 1 << 21):
пехотинец с рангом >= 2, чья цель дальше оружия, получает АРЕНДУ (выдаёт и
гасит `GameManager._recalc_melee` — тот же приём, что у `_rear_line`: не
подтвердили — вернулся сам). Пока аренда жива, шаг к точке боя ему кладёт
ядро той же геометрией пакетного шага (вода, стволы, ЧУЖОЙ СТРОЙ — биты
просвета гасятся принудительно), а GDScript-тик пропускается целиком
(прецедент `_matrix_driven`). Пробуждения — событиями: упор в чужое тело
(ветка блокировки BatchMoveRows), удар по строке, смена цели, паника
(`panic_flee` рвёт аренды немедленно), приход к точке. Ворота годности:
только рукопашная АТАКА без замка, не конница и **НЕ НА КОННИЦУ** (толпа,
давящая навстречу разгону, съедала кабанам пробег — qa_cavalry E2 терял
вмятину тарана; замер: без напора вмятина стабильна 3 из 3).

**Автопилот подхода** (`ArmyCore.AutopilotPass`, F_AUTOPILOT = 1 << 22):
дальняя дорога к цели без входа в автомат, направление — на живую строку
цели, стражи: дистанция удара, гибель цели, упор, «враг в длине руки» раз в
12 тактов. ОБЯЗАТЕЛЬНЫЕ ворота, найденные стендом: взводится только по
объявленно чистому пути (`_clear_enemy` от коридора) — без них цикл
«шаг-скольжение-пробуждение» прощупывал стену настойчивее полного автомата,
и qa_wall A1 уезжал с 1-3 просочившихся на 5-8 (шесть прогонов подряд без
нуля; с воротами — 0/0/0/5/0).

### Замер — и почему спринт остановлен на gate-check

Прогноз D1 «физтик свалки 11.75 → 7.5-8.5 мс» ОПРОВЕРГНУТ: A/B чередованием
в свалке qa_mass3k — **+0.1 мс (шум)**, покрытие — 37 строк на кадр из ~870.
Причина записана нашей же физикой: qa_clash показывал, что бой сминается до
полутора шеренг — «глубокого тыла» в замершей рубке НЕ СУЩЕСТВУЕТ, все в
контакте, и их уже накрывает дрёма. Прогноз опирался на ложную предпосылку.

На СВОЕЙ сцене D1 честен: qa_ab, фаза сближения (1440 копейщиков, цели
видны, дотянуться нельзя), раздельные блоки:
- E1 только напор: **+0.341 мс на тик (10.2%)** — оставлен ВКЛЮЧЁННЫМ;
- E2 только автопилот: +0.008 мс (ноль) — после обязательных ворот
  безопасности его сцены не осталось; **выключен по замеру**, механизм и
  ручка (`perf_config.approach_autopilot`) на месте.

По правилу самого плана (PLAN_D_70FPS: «если D1 не привозит прогноз —
решение возвращается владельцу с числами») **D2/D3 не начаты**: их прогнозы
строились на D1-объёме пакетной работы. Пересчитанный потолок без новых
решений — ~40-45 FPS на 4000, не 70.

### Правки замеров по дороге

- qa_balance C6/C7 меряются ОДНИМ кадром: C7 сканировал бойцов спустя обход
  после выхода C6, и в щель влезал ЗАКОННЫЙ повторный срыв — «осталось
  помеченных 5» ловило новую панику, а не залипший признак.
- Инструментарий: qa_ab обзавёлся ручками KNOB_D1/KNOB_PRESS/KNOB_AUTO и
  блоками E/E1/E2 (фаза сближения — сцена, под которую механики писаны);
  qa_mass3k — A/B-блоком D1.

### Итог шлюза

Зелёный; красные — только документированные мигающие qa_wall A1 (2 в тылу —
штатная полоса) и qa_mega_battle B1-1 (12.8 при пределе 11.6), плюс qa_melee
F2 (ждёт решения владельца).

## Сентябрь 2026, спринт D завершён: D2 (потоки ядра) и D3 (туман, стрелы)

### D2: потоки пакетных проходов (`ArmyCore.CoreThreads`, Parallel.For)

Разведение отрезано на две фазы БЕЗУСЛОВНО: фаза РАСЧЁТА читает снимок
позиций и пишет только скрэтч своей строки (поэтому диапазоны строк считаются
в параллель без единого лока, и число потоков не меняет результат ни на бит);
фаза ПРИМЕНЕНИЯ последовательная — вода (вызов GDScript), узлы (дерево
сцены), пробуждение спящих. Так же распараллелен BatchVisual (чистая
математика, записи в свой слот бакета; Dirty — благоприятная гонка). Подача
в RenderingServer как была — главный поток, RbFlush.
**Замер чередованием (свалка 4100): физтик +0.52 мс, +1.9 FPS.**
Ручка `perf_config.core_threads` (1 = однопоточно), A/B-блок в qa_mass3k.

### D3: маска тумана в ядре и стрелы одним MultiMesh

**Туман**: попиксельная часть пересчёта (штампы кругов с каймой, накопление
«разведано», сборка RGBA) — в C# (`ArmyCore.FogRefresh`); GDScript собирает
ИСТОЧНИКИ и хранит копии lit/seen для чтения — is_lit каждого бойца остался
без перехода границы. Один маршал на пересчёт (раз в UPDATE_INTERVAL).
**Замер чередованием: +0.9 FPS.** Ручка `perf_config.fog_core`.

**Стрелы**: узел Arrow остался ЛОГИКОЙ (полёт, попадание, сроки, пул), а
картинка всех стрел — один MultiMesh (`ArrowRenderer` + `mm_arrow.gdshader`);
ось и дизер-растворение едут в instance-цвете (у стрел каналы урона свободны;
custom_data не взят из-за открытого бага GL). Буфер — та же Rb-инфраструктура
ядра (RbWriteColor добавлен). Замер qa_shotcorpse: **36 торчащих стрел = +1
вызов отрисовки** (был +36); свалка mass3k — 237-275 вызовов против прежних
460-580. Прямой FPS-выигрыш на 4070 около нуля (отрисовка и не была узким
местом) — ценность в запасе на рост и минус сотня материалов/квадов.
Стенд qa_corpse обновлён на новые носители тех же инвариантов: ось — кэш
экземпляра (_axis_now), порог среза — общебакетный uniform, до которого
гашение экземпляра физически не дотягивается (K1 стал строже).

### Сводка спринта (все вердикты — чередованием в одном прогоне)

| правка | физтик | FPS |
|---|---|---|
| D1 напор (фаза сближения, qa_ab) | +0.34 мс (10%) | — |
| D1 в замершей свалке | шум | шум |
| D2 потоки 1→3 | +0.52 мс | +1.9 |
| D3 туман в ядре | шум | +0.9 |
| D3 стрелы в MultiMesh | — | −220 вызовов |

Финальные фазы (1500+800+1000+100, 1920x1080): стоят 45.0 FPS (физтик 9.2),
свалка **37.3 FPS** (физтик 11.2), реальные потери **35.6 FPS** (10.8).

### Честный статус против скорректированной планки

Планка «60 на 3000 / 48-52 в мясорубке на 4000» пока НЕ ВЗЯТА: мясорубка на
4100 — 37-40. Следующая крупная непокрытая статья видна в той же таблице:
«визуальный тик армии» — 5.2 мс кадра (без него 52.7 FPS) — это GDScript-обход
поз/ракурсов/тумана по бойцам (vis_pose/vis_walk/vis_fog), у которого, в
отличие от боевых решений, природа полупакетная. Плюс кадр логики в A/B-фазах
держится 8-9 мс. Это кандидаты СЛЕДУЮЩЕГО захода — спринт D закрыт, проект
уходит в фазу дизайна (карта POI / кузница).

## 03.09.2026: стенд настоящей партии на 4000 и жёсткое ядро билетов прохода

### Зачем

Три жалобы владельца на реальном билде при зелёном шлюзе: стрелы висят в
воздухе пачками, мечники протекают сквозь фалангу, кадр падает. Ни одна не
живёт в стерильной сцене: стрелы виснут только там, где стреляют по живым
сотнями, протекание — на стыках строёв с приказами и отходами, кадр — когда
одновременно идут рубка, ИИ, туман, доставка ресурсов и стройка.

### Что сделано

- **`qa_full_game_4k`** — сцена как в партии (замки на якорях, `WORKER_LIMIT`
  рабочих с доставкой, стройки, ИИ, орда, туман, HUD), два фронта по 2000.
  Вердикты — свойства: стрелы не висят (подъём над грунтом по буферу
  `rb_slot`), буфер и реестр стрел не текут, живых внутри ядра чужого тела
  < 1 %, в окне — цель по кадру. Печатает разбор кадра, экономику и цену
  подсистем.
- **Стрелы**: `_stick_into_ground` теперь зовёт `_push_visual()` — слот
  MultiMesh оставался с точкой конца дуги (высота груди цели) до `_set_fade`.
- **Билет отхода** (`Unit._retreat_pass`): `qa_spear` C9 показал, что полное
  снятие прохода у отхода застревало половину отряда, отозванного в гарнизон.
  Билет даётся на 2.5 м от точки начала отхода, едет тем же битом
  `F_ORDER_PASS`.
- **Ядро тела для билетов** (`ArmyCore.PassCoreFrac` / `Unit.PASS_CORE_FRAC`
  = 0.55): билет сужает тело до 0.30 м, а не снимает; второй проход по ядру
  добавлен и в скольжение бегущего. Читатель — `EnemyOverlapCount` (окно для
  стендов по колонкам).

### Ловушки стенда, все три давали ложный диагноз

1. **Расписание в кадрах отрисовки.** «30 с рубки» при 137 FPS headless —
   две игровые секунды: 0 погибших, 0 стрел, «сдано +0» и «возвращающихся
   нет». Зонд обвинял экономику; переведено на `physics_frame`, экономике
   дан прогрев 25 игровых секунд (цикл 5 с + ходка от жилы у базы).
2. **Нет замка игрока.** В партии его кладёт первый клик; стенд ставит
   `Castle.new()` на `PLAYER_BASE_ANCHOR`, иначе у рабочих игрока нет склада.
3. **`sort()` по имени сцены = лучники в первом эшелоне.** На 4000 в
   контакте стояло 7-36 бойцов при 832 погибших за 30 с — перестрелка, а не
   рубка. Порядок эшелонов задан явно (`_echelon_of`).

### Замеры

A/B ядра на одной сцене (400 на 400, зерно 11), худший снимок «живых внутри
0.30 м от чужого тела»:

| ядро | внутри ядра | доля |
|---|---|---|
| 0.0 (снятие проверки) | 148 | 8.94 % |
| 0.55 (0.30 м) | 9 | 0.54 % |

Ядро в C# при этом стояло в нуле, а в GDScript — 0.55: база A/B, не
возвращённая на место. Возвращено.

Полноразмерный прогон (2000 на 2000 + 2×40 рабочих + 2×12 строителей, headless,
ядро 0.55, копейщики в первом эшелоне): экономика без боя 59.6 FPS (физтик
9.0 мс), рубка с потерями — худший снимок 39.6 FPS (физтик 12.3 мс, кадр
логики 6.5 мс), заморожено 45.2. В контакте 598 в первом снимке, 811 погибших
за 30 с, выпущено 2130 стрел, висящих 0 (подъём 0.20-0.22 м), буфер 384 слота
при 327 узлах, реестр торчащих 182 при потолке 160, внутри ядра худший
снимок 11 (0.26 %). Обе стороны сдают на склад (+240/+165/+120 у игрока за
55 игровых секунд). Цена подсистем (мс кадра): физтик армии 11.3, визуальный
тик 11.1, стрелы 0.7, туман 0.5, HUD 0.5, рабочие 0.25, ИИ ~0 — headless,
FPS здесь только темп цикла; цель по кадру проверяется в окне.

### Шлюз после ядра: что покраснело и почему

- **`qa_wall` C1 «упёршиеся в чужой строй вступают в бой» — 7 из 38.**
  Регрессия от ядра, починена в `Unit._process_move`: ворота упора
  исключали окно прохода приказа по предпосылке «под билетом чужие тела не
  преграда, упора не бывает». С ядром упор под билетом — норма, и боец
  стоял все три секунды замка, не отвечая. Исключение снято; «реально
  выбирается» от «упёрся» отличает `moved_recently`, как и в ответе на удар.
- **`qa_spear` C9 «отряд зашёл в замок» — 5 из 6 — РАЗОБРАН ДО КОНЦА И
  ПОЧИНЕН.** A/B: ядро 0 → 6 из 6, ядро 0.55 → 5 из 6. Зонд (печатается
  стендом): шестой стоит в 0.32 м от ОДНОГО врага, в MOVING, скорость 2 м/с
  к воротам, билет отхода жив, строка ядра есть — шаг запрашивается каждый
  кадр и отбрасывается. Две причины, обе в ядре: (1) `ScanBlock` блокировал
  любой шаг с новой точкой внутри радиуса, включая шаги вдоль и прочь, —
  боец внутри радиуса заперт навсегда (с полным радиусом 0.55 внутрь было
  не попасть, ядро 0.30 меньше игрового просвета 0.33); теперь запрещено
  СБЛИЖЕНИЕ, а не пребывание. (2) Ветка скольжения идущего снимает НАРУЖНУЮ
  составляющую шага (`into2 > 0` при нормали наружу), шаг внутрь остаётся,
  второй проход его блокирует — пехотинец у чужого тела встаёт, не скользит.
  Для обычного бойца это тюнингованное «упёрся — дерись» и не тронуто; под
  билетом прохода снимается внутренняя составляющая. (3) Даже так — 5 из 6:
  нормаль для касательной считана в НОВОЙ точке прямого шага, которая ближе
  к телу, и «касательная» проходит на 1.5 мм ближе к телу, чем текущая точка
  (0.302 против 0.3035); правило «прочь» её отвергает. Лечит четверть шага
  наружу вдоль нормали (`PassSlideOut`). Правило «прочь» при этом ТОЛЬКО
  под билетом: для всех оно ломало `qa_crowd` A1/A3 (толпа у спящей орды не
  замирала: дрожание 0.0000 → 0.0647 м). Ловушки опыта: счётчики `Bm*`
  обнуляются каждый пакетный проход — читать их разностью за 60 кадров
  бессмысленно, суммировать покадрово; прямой запрос `enemy_block` для
  касательной по нормали в текущей точке отвечал «свободно», а ядро
  отказывало каждый кадр. После трёх правок C9 — 6 из 6 при ядре 0.55.
  Правила в обеих дорогах.
- **`qa_disengage` D2 «с первого приказа вышел из окружения» — 0.07 м.** НЕ
  регрессия кода, а цена решения: пройти между двумя телами можно только в просвет шире двух
  ядер (0.60 м), кольцо стенда стоит с просветом 0.29 м, самый редкий строй
  игры — 0.55. Промежуточного ядра, разделяющего «кольцо окружения» и
  «шеренгу», не существует: геометрически это одна и та же щель. Ядро 0.25
  открыло бы стоящий строй, 0.17 — сжатый в бою. Выбор между «сквозь строй
  не проходит никто» (жалоба владельца, ради которой заведён стенд партии)
  и «из свалки с первого клика» — за владельцем; до решения ядро 0.55, D2 —
  документированный красный и печатает геометрию просвета.
- **`qa_volley` E1 «без режима пачек нет» — пик 5 при пороге < 5.** Ножевой
  порог на десяти стрелках, получающих цель в один кадр; к правке стрел
  (только слот картинки) отношения не имеет.
- **`qa_goblin` блок F ронялся молча:** гоблин гибнет о девять копейщиков
  раньше конца окна, обращение к освобождённому узлу — SCRIPT ERROR, три
  вердикта не печатались, сводка «0 провалов». Стенд починен (точка и факт
  боя снимаются, пока узел жив; гибель в контакте — упор и рубка). **Сводка
  шлюза обязана считать и `SCRIPT ERROR`**, а не только «НЕ ПРОШЛО».
- **`qa_mega_battle` B2-3 и B1-1 — красные, которых раньше НЕ БЫЛО ВИДНО.**
  Блок B2 падал на освобождённом узле (правило 5) ДО приказов отхода, и ни
  B2-3, ни последующий B1 сцену после отхода не видели. Теперь видят:
  B2-0 (отход сквозь ЦЕЛУЮ фалангу, до боя — настоящая проверка) 0 из 495;
  B2-3 (тот же отход после 30 с рубки пятисот рыцарей) 18 из 129, во втором
  круге 5 из 34 — доля одна. В бою ряды не смыкаются (`squad_in_combat`), и
  в шеренге стоят дыры от павших: обычному бойцу нужна дыра 1.1 м, билету
  отхода — 0.6. Стенд сам называет B2-3 «страховкой, вырождающейся после
  свалки»; чтобы он что-то значил, ему нужна мера целости участка, как у
  `qa_wall` A1 (полоса ±0.9 м в миг перехода). B1-1 (разброс отряда
  копейщиков от знаменосца, 23.8-27.6 м) меряется ПОСЛЕ сцены отхода:
  единицы копейщиков уходят за отходящими рыцарями (B1-3: 13 из 323 дальше
  6 м) — это следствие порядка блоков, а не новая поломка строя.
  Оба — следующий заход по стенду, не по коду.
- **Мигающие на неизменном для них коде (четыре круга шлюза за день):**
  `qa_balance` C7 «признак паники снят тем же кадром» (красный в кругах 1 и
  4, зелёный во 2-м — «осталось помеченных 5», то есть законный повторный
  срыв всё ещё влезает в щель замера), `qa_wound` C1 «вспышка погасла за
  свой срок» (0.003 в буфере через 0.21 с — временной ножевой порог),
  `qa_volley` E1 (пик 5 при пороге < 5), `qa_wall` A1 (0 → 6 → 2 → 0 в
  тылу). Ни один не касается движения и тел; чинить — сами замеры.
- **`qa_full_game_4k` B1 на последнем снимке — 1.18 % при пороге 1 %, и это
  НЕ билеты.** Окно `EnemyOverlapCountFlagged` (счёт по битам строки): из 35
  внутри ядра с билетом прохода 0, отходящих 0, при 96 в контакте на 3800
  живых. Это остатки боя — конница против разрозненных, толчок удара и
  разлёт пишут координаты без проверки тел. B1 переведён на снимки
  линейного боя (в контакте >= 100), остатки печатаются отдельно долей от
  контактных. Источник поздних наложений — толчок/разлёт — следующий заход,
  не сегодняшний.

### Итог захода 03.09.2026

Шлюз (четыре круга за день, 44 стенда): зелёный, кроме документированных
`qa_disengage` D2 (цена ядра, вопрос владельцу), `qa_melee` F2 и `qa_rally2`
F2 (прежние), `qa_mega_battle` B2-3/B1-1 (стенд, после починки падавшего
блока), мигающих `qa_balance` C7 / `qa_wound` C1 / `qa_volley` E1 /
`qa_wall` A1 и ножевого `qa_mass_siege` S1 (3.3 против 3.0). Починены по
дороге: `qa_wall` C1 (ворота упора), `qa_spear` C9 (скольжение под билетом),
`qa_goblin` F, `qa_mega_battle` B2 (правило 5).
- **`qa_mass_siege` S1 — стабильный ножевой красный (3.3-3.4 м при пороге
  3.0, два повтора подряд).** Отряд на конце дуги (сектор (70, ±7.5)) стоит
  центром в 3 м ДАЛЬШЕ своего сектора от здания. Карта проекта уже отмечает у
  S1 чувствительность к 0.33 м. В осаде билетов прохода нет, к правкам ядра
  не сводится; довод «до сегодняшних правок было зелёным» не проверен —
  стенд в главный шлюз не входит, последний записанный прогон 26.08.
  Следующий заход: печатать, чем именно заперт концевой отряд.

## 03.09.2026, Часть 3: ядро зафиксировано, три хвоста закрыты, финальный замер

### Решение владельца

Ядро билета прохода `PassCoreFrac` = `PASS_CORE_FRAC` = 0.55 (0.30 м)
зафиксировано. Фаланга монолитна: выход из плотного окружения сквозь тела
не требуется. `qa_disengage` D2 переписан: D2a — сквозь кольцо с просветом
0.29 м НЕ выходит (moved < 0.5 м), D2b — из кольца с просветом 2·ядро·1.3
выходит с первого приказа (moved > 1.0 м). Прежний вердикт утверждал
снятое требование.

### Хвост 1: наложения в остатках боя — разлёт и толчок

Окно по битам показало: внутри ядра ни одного с билетом и ни одного
отходящего, то есть источник — движения мимо проверки тел. Их было два.
`_tick_fling` проверял чужие тела только при `_fling_solid` (прорыв
всадника); сбитый пехотинец летел 2.2 м без проверки и в окружении влетал
внутрь второго врага. `_apply_push` двигал жертву на 0.04-0.4 м, проверяя
только воду и край карты. Оба теперь проходят `enemy_block(BLOCK_RADIUS)`
для СВОЕЙ фракции (жертвы — для жертвы). `_fling_solid` остался признаком
прорыва: он ставит `_enemy_contact`, сбитому пехотинцу контакт не ставится.
Движений мимо проверки тел в проекте больше нет — разведение своих, шаг,
напор, автопилот и теперь разлёт с толчком идут одной геометрией.

### Хвост 2: честная мера целости для B2-3

B2-3 считал «призраком» любого отходящего, оказавшегося за линией к концу
двенадцати секунд, а после 30 с рубки в шеренге стоят дыры от павших (ряды в
бою не смыкаются). Теперь решение принимается один раз, в миг пересечения
линии: живые копейщики в полосе ±0.9 м по фронту и 2.5 м от линии — проход
СКВОЗЬ строй (призрак); их нет — проход в дыру, печатается отдельно. Тот же
приём, что у `qa_wall` A1.

### Хвост 3: концевой отряд в S1

Не заклинивание, а геометрия прихода. Сектор у здания — точка, отряд —
тридцать пять тел; «держащий позицию» отряд второго ряда шёл к самой точке,
каждый вставал в `RING_ARRIVE` (1.5 м) от неё с той стороны, откуда пришёл,
и центр отряда оказывался в 3.3-3.4 м снаружи сектора. Первый ряд этого не
показывал: он идёт дальше, к стене. Лечение — тот же перенос, что у стены
строя (`_wall_goal`): точка каждого смещена на «сектор минус центр отряда»,
к сектору приходит ЦЕНТР, взаимное расположение тел не меняется.

### Замеры

Финальный прогон `qa_full_game_4k` (2000 на 2000 + 2×40 рабочих + 2×12
строителей, headless, ядро 0.55, весь код Части 3):

| фаза | FPS (темп цикла) | физтик, мс | кадр логики, мс |
|---|---|---|---|
| экономика без боя | 59.1 | 8.6 | 4.3 |
| рубка с потерями, худший снимок | 40.1 | 12.1 | 6.4 |
| рубка, потери заморожены | 44.8 | 9.6 | 7.2 |

Разбивка физтика в рубке (профиль, читать как ранжирование): весь тик
юнитов на GDScript 7.8 мс/кадр, из них визуальный проход по бойцам (vis_far)
4.5, автомат боя (process_attack) 2.7, удар 0.8, сетка 0.9; отрядные обходы
на GDScript: коридор 1.0, бой отряда 0.6; C#-проходы: разведение 0.6,
пакетный шаг 0.4. Цена подсистем: физтик армии 11.5 мс кадра, визуальный
тик 12.8 (из них 5.3 кадра логики), остальное (туман, HUD, ИИ, рабочие,
стрелы, спрайты) по 0-1 мс каждое. **«Внутри ядра» — 0 во всех шести
снимках** (до правок разлёта и толчка доходило до 35 на последнем).
Шлюз после Части 3: `qa_disengage` 0 из 15 (D2a/D2b), `qa_mass_siege`
0 из 9 (S1: концевые отряды 1.4-1.5 м от сектора вместо 3.3-3.4),
`qa_mega_battle` B2-0 0 из 492, B2-1 0 из 233 с мерой щели, B2-3 1 сквозь
живой участок при 33 законных проходах в дыры из 170 (допуск 1 %); B1-1
остаётся (спутник сцены отхода). `qa_wall`, `qa_cavalry`, `qa_push`,
`qa_clash`, `qa_crowd`, `qa_spear`, `qa_bldattack`, `qa_panic`,
`qa_balance` чистые. `qa_melee` F3 стал ножевым спутником известного F2
(3.0 м при пороге > 3.0): раньше выход подталкивали вражеские толчки,
вдавливавшие бойцов в чужие тела, теперь толчок честный.

## 03.09.2026, голосовое управление: прототип на три команды

Vosk (офлайн, малая русская модель, грамматика из словаря команд) в фоновом
C#-потоке; `AudioEffectCapture` на своём бусе «Record» (громкость −80 дБ,
эффект стоит до регулятора); push-to-talk на V; плашка текста; клич отряда.
Три команды всем копейщикам игрока: оборона, марш по курсу на 40 м, отход
на N м (умолчание 20). Стенд `qa_voice_cmd`: 19 проверок, 0 провалов;
`qa_bugpass` с новым узлом в Main — 0 из 45; окно — без предупреждений.

Ловушки по дороге (все в коде и в CLAUDE.md): обёртка Vosk.dll маршалит
строки ANSI (кириллица → '?????'), ушли на прямой `DllImport` с UTF-8;
`DllImport("libvosk")` не находит DLL рядом со сборкой в плагинном контексте
Godot — явная загрузка по пути и резолвер; правило «короткая основа только
точно» срезало четырёхбуквенные основы («атак», «стро») — введён список
`exact`; D2 «противник не тронут» мерил такт ИИ противника — ИИ в стенде
заглушен; heredoc Git Bash съедает обратные слэши в патчах (дважды за
заход) — патчи только файлом.

Что дальше: разбор по выделению и по типам войск (лучники, мечники,
конница), «огонь по готовности» / «залп» через режим залпа, свой сэмпл
«Есть!», образцы фраз для блока E, экспорт (модель и четыре DLL рядом с exe).

### Голос, вторая итерация: типы войск, шесть команд, отход фаланги

Группы по типу отряда (копейщики, лучники, мечники, конница, все), шесть
намерений (атака с горном, вперёд 20 м, отход N м, стоять, держать позицию,
вольно), отход фаланги последовательностью «копья вверх → отход → встали
лицом к противнику → копья вниз» через отложенный такт `_reform`. «Стоять» —
приказ идти в собственную точку (мгновенное прибытие, покой, стойка цела).
Стенд `qa_voice_cmd` — 27 проверок, 0 провалов, включая последовательность
отхода (сдвиг 19.5 м, 12 из 12 в обороне и лицом по курсу по приходу).

Ловушка словаря: малая русская модель не знает «мечники» (и ещё семь форм),
но знает «мечников», «мечи», «рыцари», «воины». Проверить можно только
пробой (предупреждения при создании грамматики), words.txt у сжатого графа
нет; сделано пробной пачкой из 28 кандидатов, принятые оставлены в словаре.

## 09.09.2026, строительный и звуковой спринт: аудио-окно, башня, стрелковая, дома

### Аудио-окно камеры

Жалоба: марш слышен со всей карты. Прежний закон — громкость по наземному
расстоянию от слушателя, делённому на радиус отсечки, следующий за зумом:
на дальнем плане в кадре двести метров поля, и с ними весь марш. Теперь
окно задано метрами от ФОКУСА камеры (центр экрана): до 15 м полная, до
40 м квадратичный спад в ноль, дальше голос не выдаётся; сверху режется
видимой полосой. Второй множитель — зум: (1 − t)^1.5, ноль на пределе
отдаления (тогда голоса не раздаются вовсе). Слушатель остался на камере
для панорамы; расстояние от него не годится — камера стоит позади фокуса
на десятки метров.

Темп: шаг 1.08, бег 1.12 → 1.23. Зонд `qa_march_env/Probe`
(AudioEffectCapture в headless — dummy-драйвер микширует, PCM читается)
показал у бегового лупа 0.78 с тишины в начале файла и первый сапог на
1.10 с; вместе с тактом обхода (0.25) и входом (0.12) это и была секунда
между «побежали» и «затопали». Луп стартует и зацикливается с 0.78 с.

`qa_voice` 50/50 после переноса площадки блока D к фокусу (у слушателя она
лежала за окном).

### Меню построек, башня, стрелковая, дома

«Выбираю вышку — строится домик» оказалось рудником: иконка Tower.png при
спрайте House1. Теперь `Tower.gd` (наследник Castle ради гарнизона: один
отряд, только лучники, без авто-выхода, обзор 35 м, часовой из первого
кадра Archer_Idle на настиле, ПКМ выпускает, руины и стройка в долю 0.6),
`Archery.gd` (лучники; в бараках копейщики и мечники; ИИ строит стрелковую
после кузницы, до неё нанимает лучников в замке), три дома одним скриптом
(`House.variant_id`), лимит населения (база 6/3, дом +3/+3, живые плюс
заказанные, ворота в `queue_unit`, включает партия — стенды его не видят).
`is Castle` перестал значить «столица»: `is_stronghold()` в зоне застройки,
кнопке «в замок», условии поражения и точке базы ИИ.

Стенд `qa_tower`: 41 проверка, 0 провалов. Ловушки по дороге: счётчик домов
приводил освобождённый объект из кэша группы (правило 5); строка панели дома
затиралась покадровым обновлением HP; башня стенда стояла за краем карты
(z = 90 при MAP_HALF_Z 73), и туман отвечал «темно», потому что клетки нет.

## 09.09.2026, спринт: босс-тролль, новая карта, монах-целитель

### Тролль и логово

`Troll.gd` — Unit гоблинов с пятью переопределениями: размер ×4 (свой
pixel_size 0.0307), серия ударов → одышка (`_may_strike_now` false и тик
без базы), брызги дубины, таран по `charge_*` с замахом, цена смерти 180
убийств по долям урона (`GameManager.credit_kills`). Логово `TrollLair.gd` —
Building с деревом, кольями и костями; стражи и подмога на половине запаса.
Месть гоблинов — отдельные часы в `GoblinAI`: по зачистке раз в 600 с десять
отрядов с ролью «месть» идут на кольцо вокруг дерева, приказы им идут и в
спячке орды. Стенд `qa_troll` 24/24.

### Карта ×3, река с бродом, гора, тайлы

`MAP_GROWTH` 2.25 (×3 по площади; линейное ×3 дало бы ×9). Река вдоль Z по
центру с меандром, брод 36 м посередине, гора у замка игрока, логово за
ней. Высота стала составной и ЖИВЁТ В ДВУХ ЯЗЫКАХ: ядро считало три копии
гармоник — теперь `ArmyCore.Height` с горой и рекой, параметры подаёт
`refresh_map_bounds`. Вода реки проверяется в ядре (`RiverWater`), без
вызова GDScript на каждый шаг; берег ведёт к броду (`slide_around_water`
вдоль Z к `FORD_Z`). Первый прогон стенда поймал ровно это: боец шёл сквозь
реку 577 кадров, потому что `water_active` гасился по флагу озера. Земля из
тайлов: трава/песок, гора (Elevation), вода (Water повтором), пена, камни
брода. Стенд `qa_map` 24/24 (переход через брод: 187 м пути, 0 кадров в
воде).

### Монах

Одиночный найм (`SQUAD_SIZE_MONKS` 1, `MONK_LIMIT` 1 — правило бойца, в
`pop_allows` всегда), аватар из Human avatar, лента Heal. Лечение — такт раз
в 0.5 с, самый раненый свой в 12 м, темп «полный боец за 10 с» (замер: 63 HP
за 4 с при ожидании 72 — первый такт съедает задержку). Стенд `qa_monk`
13/13.

Не сделано намеренно: эффект Heal_Effect над целью (нет узла-эффекта в
проекте, заводить ради него слой не стал), автотайлинг кромок берега
(внутренние тайлы), ускорение бойцов на склоне (у рельефа нет цены шага).


## 09.09.2026, третья часть: аудит кадра после новой карты, туман в ядре целиком, башня стреляет

Жалоба: «после тайлсета и расширения карты FPS упал до 40-50, появились
фризы и микролаги; до обновления летала». Заказ — вернуть 60-70 FPS на
4000, перевести туман на GPU или разреженную сетку, запечь слои тайлсета,
защитить и вооружить гарнизон башни.

### Что показал замер ДО правок

Три измерения, все в окне 1920×1080, RTX 4070, машина свободна
(правило 12).

**1. Та же сцена на старой и новой карте** — `qa_fps` (две стоящие армии
по 2000) на дереве HEAD (карта 150×150, до тайлсета) в отдельном worktree
и на рабочем дереве:

| | старая карта (HEAD) | новая карта (450×253, тайлы, река) |
|---|---|---|
| база стоя | 61.8 FPS, 16.18 мс, 261 вызов | **72.4 FPS, 13.80 мс, 165 вызовов** |
| физтик | 7.01 мс | 6.79 мс |
| кадр логики | 3.86 мс | 3.77 мс |
| вся армия выделена | 37.0 FPS | 35.3 FPS |
| та же армия на марше | 30.5 FPS | 30.0 FPS |

Средний кадр стоячей сцены на новой карте НЕ просел — он стал легче
(меньше вызовов отрисовки: озеро с кольцом камней и уткой выключено).
Марш — 30 FPS в обоих случаях, это цена тика 2000 идущих, к карте
отношения не имеет.

**2. Настоящая партия** — `qa_full_game_4k` (две смешанные армии по 2000,
рабочие, стройки, ИИ, орда, туман, HUD), теперь с ПИКАМИ кадра:

| фаза | FPS | физтик × тиков/кадр | кадр логики | худший кадр / p95 |
|---|---|---|---|---|
| экономика без боя (4957 живых) | 48.0 | 8.28 × 1.25 = 10.3 мс | 5.0 мс | 33.6 / 27.0 мс |
| рубка, худший снимок | 32.0 | 11.94 × 1.88 = 22.4 мс | 7.1 мс | 44.6 / 39.3 мс |
| рубка, потери заморожены | 36.0 | 10.42 × 1.67 = 17.4 мс | 7.1 мс | 40.4 / 33.0 мс |

Цена подсистем на замороженной рубке (гасим — меряем — возвращаем): туман
−0.39 мс (шум), HUD 0.37, ИИ −0.92 (шум), рабочие 1.48, стрелы 1.52,
спрайты армии 0.81, **физический тик армии 7.24 мс тика**, визуальный
тик армии **5.78 мс кадра логики**. Это те же числа, что в закрытии
спринта D: кадр держат тик и визуальный проход, а не туман и не земля.

**3. Один пересчёт тумана** — зонд `qa_fogperf/Probe` (4856 живых, маска
300×169 = 50 700 ячеек, 74 ячейки-источника):

| часть | до | после |
|---|---|---|
| полный `refresh()` | **4.59 мс** | **1.56 мс** |
| сбор источников по бойцам (GDScript) | 3.38 мс | 0 (в ядре) |
| штампы + RGBA + маршал (C#) | 0.92-1.32 мс | то же |
| заливка текстуры 203 КБ | < 0.01 мс | то же |

Пересчёт идёт раз в 0.15 с и ложится в ОДИН кадр: при кадре в 14 мс
каждый девятый кадр был 19 мс. Это единственная найденная статья, которая
читается глазом как «микролаг» и при этом растёт с картой (маска ×3) и с
армией (обход бойцов). Маска в C# уже была (этап D3); дорогим оказался
СПИСОК источников — `global_position` (свойство, правило 2),
`is_instance_valid`, `is_dead` и словарь на каждого из четырёх тысяч ради
семидесяти четырёх ячеек.

### Что сделано

- **Источники тумана собирает ядро** (`ArmyCore.FogRefreshRows`): по
  плотному списку живых строк своей фракции с `FPosValid`, радиус —
  `max(_atkRange × VISION_MULT, VISION_MIN)`, слияние по ячейке `SRC_CELL`
  с наибольшим радиусом. Те же 74 источника, 4.59 → 1.56 мс. GDScript
  собирает только постройки и постоянные засветы. GPU-шейдер тумана ЕСТЬ
  и был (`fog_of_war.gdshader`, одна выборка маски на пиксель); переносить
  на GPU было нечего — узким местом был обход бойцов, а не пиксели.
- **Гарнизон снят из сетки ядра** (`ArmyCore.SetOffMap`, `Unit.set_off_map`
  из `Castle.absorb_unit`). Найдено по дороге: вошедший в башню или замок
  оставался «настоящей» строкой на точке у ворот — цели и стрелы его
  находили. Это и было «лучники в башне получают урон».
- **Удар по укрытому принимает здание** (`Unit.take_damage` →
  `garrison_host.absorb_damage_for`), **гарнизон башни стреляет с площадки**
  (`Tower._tick_fire`: его же `_on_attack_fired`, его же перезарядка, одна
  цель на площадку в `TOWER_FIRE_RANGE` 35 м, поиск раз в 0.25 с). Ссылка
  на цель нетипизирована — правило 5 поймало на первом же прогоне (26
  исключений за 4 с, по кадру на освобождённую цель).
- **Пена одним мешем, камни брода — MultiMesh на лист**: до 96 вызовов
  отрисовки при реке в кадре → не больше пяти. Земля, гора и вода уже были
  тремя мешами; «запекать» там нечего.
- `qa_full_game_4k` печатает худший кадр и p95; `qa_tower` 46/46 (пять
  новых), `qa_map` E4/E5 переписаны под пакетную отрисовку.

### Что показал замер ПОСЛЕ

`qa_full_game_4k`, тот же посев (seed 11), окно 1920×1080:

| фаза | до | после |
|---|---|---|
| экономика без боя | 48.0 FPS, 305 вызовов, пики 33.6 / 27.0 | 46.7 FPS, **214 вызовов**, пики 33.9 / 26.6 |
| рубка, худший снимок | 32.0 FPS, физтик 11.94 | 32.0 FPS, физтик 12.71 |
| рубка (заморожено) | 36.0 FPS, физтик 10.42 | 34.5 FPS, физтик 10.92 |

Вызовов отрисовки −90 (пена и камни), средний FPS — в пределах разброса
прогонов (±3-5 FPS на неизменном коде), ПИКИ НЕ ИЗМЕНИЛИСЬ: худший кадр
34-46 мс — это кадры, в которые попадает ДВА физических тика по 11-12 мс,
а не пересчёт тумана. Фризы в партии на 4000 структурные: при 35 FPS на
кадр приходится 1.7 тика, и любой кадр с двумя тиками вдвое длиннее
соседей. Снятые 3 мс тумана раз в 0.15 с в этом распределении не видны;
видны они будут там, где тик короче — на 1000-2000 бойцах.

**Ловушка A/B, которую стоит запомнить: `qa_fps` НЕ ПОСЕЯН.** Три прогона
одного дерева дали 72.4, 137.0 и 63.2 FPS при 165, 86 и 138 вызовах
отрисовки — лес и кусты сеются заново каждый запуск, и в кадр попадает
разное число бакетов растительности. Для сравнения «до/после» годится
только `qa_full_game_4k` (seed 11) или `qa_ab` чередованием.

`qa_visual_smoke` 19/19 после того, как стенд научился прятать
анимированные камни брода: площадка стенда стоит в центре карты, центр
теперь брод, а камень, сменивший кадр между двумя снимками, засчитывался
копейщику в силуэт («кромка опущена на 1.93 м» на целом бойце — под квадом
копейщика 122 px пустого поля, и камень в него попадал). На дереве HEAD
(старая карта) стенд зелёный без правки — артефакт окружения, не картинки.

Шлюз затронутых стендов (headless): qa_map 24, qa_fog, qa_keep, qa_goblin,
qa_troll, qa_recon, qa_spear, qa_difficulty, qa_bugpass, qa_monk, qa_guard,
qa_hold — 0 провалов, 0 SCRIPT ERROR; qa_tower 46/46; qa_full_game_4k
A1-A3, B1 зелёные, C1 (60 FPS) красная, как и до правок.

Утечки при выходе, замеченные во всех оконных прогонах: «2 RID allocations
of type Texture leaked» (3468 и 4540 байт) — две мелкие текстуры в
статических полях (`HUD._ping_tex` и подобные) переживают дерево сцены;
на партию не влияют, чинятся освобождением статики в `_exit_tree`
автозагрузки, в этот заход не трогал.

### Честный потолок

60-70 FPS в рубке на 4000 этим спринтом не берутся, и это не новость —
см. `PLAN_D_70FPS.md`, «Закрытие спринта»: свалка на 4100 — 37-40 FPS,
следующая крупная статья — GDScript-визуальный проход армии (5-6 мс
кадра), а тик рубки упирается в трижды измеренный закон о разнородных
решениях боя. Уравнение кадра прежнее: FPS = (1000 − 60 × физтик) / R;
при физтике 11.9 мс на 60 Гц уходит 714 мс каждой секунды процессора.
Туман и тайлсет в этом уравнении стоят меньше миллисекунды и в среднем
кадре не видны; они видны в ПИКАХ — и ровно это снято.

## 09.09.2026, четвёртая часть: тролль-таран, дубина дугой, сбитые с ног, кровь

Заказ: скорость и патруль тролля вверх, толчок сильнее конницы, топтание
первых трёх при таране, дубина по шести впереди с отлётом и «лежат как
мёртвые, потом встают», слабее вспышка и кровь пятнами; башня стреляет на
штатную дальность лучника; портреты монаха по цвету.

### Что где лежит

Числа — `unit_stats_config.STATS["troll"]` (скорость 2.88,
`charge_push_mult` 6.6) и `goblin_config.TROLL_*` (патруль 23.4, топтание 3,
дуга 6 / cos 0.5 / +0.8 м, отлёт 2.6 м, лежание 2.5 с, вспышка 0.22, кровь
1.0). Механика — три переопределяемых крючка в `Unit` (`_trample_count`,
`hit_flash_peak`, `blood_spots`) плюс общий режим «сбит с ног»
(`knock_down` / `is_down` / `_stand_up`), которым может пользоваться любой
удар, не только дубина.

### Три решения, которые стоит знать

1. **«На 20 % сильнее конницы» — это множитель после потолка, а не
   `push_force`.** Шаг толчка = clamp(разница напора × 0.15, 0.04, 0.4) ×
   `charge_push_mult`; при разнице в три единицы потолок уже достигнут, и
   напор 60 против 25 ничего не добавляет. Разница живёт в множителе: 5.5 у
   кабана → 6.6 у тролля.
2. **Стенка копий топчущего не останавливает.** Иначе фаланга лбом отменяла
   бы всё топтание: `_charge_impact` у обычной конницы на копьях обрывается,
   у тролля — берёт укол и продолжает. Первые три по проекции на вектор удара
   гибнут через `take_damage` сверх запаса, остальные в круге брызг получают
   долю запаса и отлёт, как от кабана.
3. **Лежащий боец — это его же тело из `CorpseRenderer`.** Общий MultiMesh
   армии рисует только вертикальные билборды, а квад плашмя с поворотом
   поперёк экрана уже есть у слоя тел. На срок лежания у бойца снимается слот
   и визуальный тик, кладётся тело тем же `spawn`, что у павшего; новые
   `move_now` (везёт тело за летящим) и `remove_now` (снимает без
   растворения). Ворота в `tick_physics` — после такта разлёта: сбитый
   обязан долететь. Замер стенда: накрыто 5 из 6 возможных, все в дуге,
   отлёт до 2.55 м за полсекунды, через 2.5 с все встали и 4 из 5 сразу в
   бою.

Кровь — процедурные пятна в `mm_unit_sprite` (11×11 клеток кадра, хэш от
клетки, плотность (1 − hp) × blood_spots, капля вытянута вниз); включаются
uniform'ом бакета, у пехоты ноль и одно сравнение. Снимок —
`qa_troll_impact/Shot`.

Башня: разворот от утреннего решения — `fire_range()` теперь наибольший
`attack_range` гарнизона, константа `TOWER_FIRE_RANGE` снята; `qa_tower` B8а
и B8д переписаны (враг дальше лука, но в обзоре — ноль выстрелов).

Монах: `Avatars_04.png` в паке нет (лежит только `.import`), взят
`Monk_blue.png`; жёлтым `Avatars_14`, красным `Avatars_09`, выбор по
`GameManager.color_of` в одной функции `HUD.unit_icon_path`.

### Шлюз

Полный список из CLAUDE.md плюс `qa_troll_impact`, `qa_monk`, `qa_map`,
`qa_hud5`, `qa_ui9` — 47 сцен, 0 SCRIPT ERROR. Красных три, и все три
не от спринта: `qa_mega_battle` B1-1 (ножевой порог 11.6 м, мигает на
неизменном коде — см. раздел мега-стенда), `qa_balance` E2 «стартового
запаса не хватает на исследование» (в закоммиченном конфиге владельца лежит
отладочный запас 22550/22380 — стенд честно видит 75 узлов), `qa_ui9` 3
«нижняя панель уже половины экрана» (748 из 1280; проверено с обходом
правки аватаров — то же число, панель раздала строка лимита населения из
утреннего спринта). `qa_wall` A1 в этом прогоне тоже красный (5 в тылу) —
известный.

Стенд `qa_troll_impact` мигал дважды, оба раза замер, а не код: первый
взмах после тарана нередко достаёт одну цель (строй разбросан) — теперь
ждёт взмах, накрывший двоих и больше; следующий взмах (раз в 1.4 с)
укладывал тех же бойцов заново и продлевал лежание — на время проверки
подъёма тролль снимается с тика. После правок 7 прогонов подряд 17/17.
Оконные: `qa_visual_smoke` 19/19, снимок `qa_troll_impact/Shot` — пятна на
тролле, четверо сбитых лежат телами.

## 09.09.2026, пятая часть: визуальный проход армии в ядре (этап E1-E2)

Заказ: освободить 5-6 мс кадра, которые визуальный проход в GDScript
съедает на 4000, — перенести в C# интерполяцию, анимацию, кольца и полоски.

### Где на самом деле лежали миллисекунды

Догон нарисованной точки и покачивание уже жили в ядре (этап C.1). В
GDScript на бойца в кадр оставались: туман, LOD, листание кадра ленты плюс
переход границы на каждую смену кадра (`Slot.set_frame`), полный разбор
позы раз в `anim_every` тактов, состояние урона. А САМАЯ дорогая статья
была не в тике бойца вовсе: кольца выделения и полоски здоровья обходились
GDScript-циклом по словарю выделенных, читали `draw_position()` (переход
границы) и писали 24 float в `PackedFloat32Array` на каждого — с
`set_buffer` на каждый кадр с движением. В стоячем стенде это не видно
(выделения нет), в партии — «выделил всю армию и получил 35 FPS».

### Что сделано

- **E1, кадр ленты в ядре.** `RowAnim` пишет параметры ленты по событию
  (`_set_anim`, `_apply_dir_tex`, регистрация слота), `BatchVisual` ведёт
  фазу и пишет номер кадра в слот только на смену. Побочно снято правило
  «многокадровый покой не усыпляется»: стоящий с зацикленным idle спит по
  картинке, дышит за него ядро.
- **E2, кольца/тени/полоски в ядре.** Слои держат буферы в Rb ядра; привязка
  строки к слоту по событию (`DecalBind`/`HpBind`), позиция и доля жизни —
  в том же `BatchVisual`; GDScript-обход остался запасной дорогой для бойца
  без слота в общей отрисовке.

### Замер (`qa_visab`, headless, 2000 своих маршем + 2000 чужих, все свои
### выделены, полоски на всех, чередование 4 раунда)

| ручка | кадр логики база → правка |
|---|---|
| anim_core | 8.28 → 8.06 мс (−0.22) |
| decal_core | **79.2 → 7.8 мс (−71.5)** |
| обе | 79.2 → 8.0 мс |

`qa_fps` 2000 на 2000 (окно 1920×1080; стенд не посеян, сравнивать только
сцены «выделена вся армия» и «марш» внутри одного прогона с базой того же
прогона): база стоя 66 FPS, **вся армия выделена 54-62 FPS в двух прогонах (15.1 → 18.5 и
14.5 → 16.1 мс; прежде 13.8 → 28.3 мс, то есть 35 FPS)**, та же армия на
марше 39-52 FPS (прежде 30); расхождение кольца со спрайтом 0.000 м —
обе точки пишет один проход. `qa_full_game_4k` (seed 11): экономика 46.7 FPS, кадр логики
**5.8 → 4.5 мс** на замороженной рубке; FPS рубки 33-39 — прежние: кадр
держит физтик 11-12 мс × 1.7 тика, визуальный проход в нём — не главная
статья. Метрика «метка под ногами» в `qa_fps` переведена на чтение буферов
ядра (`rb_slot` кольца и бакета): GDScript-словарь `_last_pos` у ведомых
ядром колец больше не ведётся, и старая метрика показывала 2.96 м на
исправной картинке.


Шлюз стендов картинки и боя (qa_wound, qa_sel2, qa_facing, qa_orders,
qa_fog, qa_keep, qa_corpse, qa_reform, qa_cavalry, qa_troll_impact,
qa_bugpass, qa_vetui, qa_hud5, qa_panic, qa_spear, qa_squad, qa_vet,
qa_goblin, qa_troll, qa_tower, qa_recon, qa_army SelfTest, qa_balance) — 0
провалов, 0 SCRIPT ERROR; `qa_visual_smoke` 19/19, `qa_wound/Shot` снят.

### Что дальше по плану (база под три хака)

Полный порт автомата поз (walk/idle, направленные листы копейщика, ракурс
по камере) в C# не сделан: это разнородные решения по подклассам, и по
трижды измеренному закону проекта смена языка окупается только у
пакетной работы. Следующий шаг там — событийный пересчёт позы вместо
периодического (`anim_every`): сектор взгляда и зеркало считать в тике и
метить позу грязной только на смену. Стартовый запас возвращён к
штатному 550/380/340/200 — `qa_balance` E2 снова зелёная.

## 09.09.2026, шестая часть: событийная поза (E3) и декларативные стрелы (хак №1)

### Событийная поза

Периодический разбор позы (`anim_every` визуальных тактов, на 4000 — каждый
пятый такт восьми шардов, до 0.67 с) заменён событиями: состояние, живой
ряд, взгляд/направление хода (порог 20° через квадрат косинуса, без sqrt),
истечение замка удара, поворот камеры (эпоха оси экрана в `GameManager`),
возврат в кадр, смена цели. Расписание осталось страховкой в шесть раз
реже. Замер `qa_visab` D (марш 2000, чередование): 7.51 → 7.44 мс (−0.07).
Вывод честный: разбор позы и раньше стоил полмиллисекунды на кадр, деньги
были не там; выигрыш правки — в отзывчивости (поза меняется тем же тактом,
а не через полсекунды) и в базе под сон бойцов с направленными листами.

### Декларативные стрелы

Стрела в полёте была узлом с `_process`: три перехода границы на кадр
(позиция+ось в буфер, `enemy_at`) на каждую из 60-70 летящих. Теперь полёт
— запись в ядре (`ArrowLaunch`), `BatchArrows` одним проходом двигает все,
пишет слот MultiMesh и ищет попадание тем же `EnemyAt` (XZ-радиус 0.35 —
правило сохранено дословно, высота полёта не проверялась и раньше), наружу
— события пачкой (`TakeArrowEvents` → `Arrow.core_event`: удар, здание,
втыкание — тот же код). Узел остаётся ради втыкания, тела, растворения и
пула. «Расчёт попадания при выстреле» в буквальном смысле (жертва
назначается в момент спуска тетивы) сделан НЕ был: он менял бы баланс —
стрела перестала бы бить того, кто вошёл под её дугу; попадание считает
ядро без участия GDScript, и это то, что снимало цену.

Замер `qa_full_game_4k` (окно, seed 11): цена статьи «стрелы (логика
полёта, узлы)» 1.52 мс кадра → −0.46 (в шуме); профиль показывает
`arrow_core` 0.40 мс/кадр. Экономика 53 FPS (было 46.7), рубка 33-45 FPS
(было 32-38), физтик 11-13 мс — потолок прежний.

### Ловушка захода

Патч ядра был применён, а сборка C# — нет (скрипт правок упал на другом
файле раньше `dotnet build`); шлюз пошёл со старой DLL и сыпал «Nonexistent
function ArrowLaunch». Правило: после ЛЮБОЙ правки `ArmyCore.cs` — сборка
отдельной командой, до импорта и до стендов.

### Шлюз

25 сцен: 0 SCRIPT ERROR; красные — `qa_wall` A1 и `qa_mega_battle` B1-1
(известные), `qa_spear` C9 «внутри 5 из 6» под нагрузкой шлюза (отряд ещё
шёл к воротам), отдельно — 49/49 дважды. `qa_visual_smoke` 19/19,
`qa_shotcorpse` — стрелы втыкаются в тела и грунт, 64 вызова, как прежде.

Хаки №2 (отряд как геометрический отрезок-стена в C#) и №3 (площадка сбора
у замка) — не начаты; первый требует пересмотра `EnemyBlock`/`ScanBlock`
(столкновение с отрезком строя вместо перебора тел), второй — приказа.

## 09.09.2026, седьмая часть: хак №2 измерен и не построен, хак №3 — площадка сбора

### Хак №2: отряд как стена-отрезок

Прежде чем строить геометрию отрезков вместо проверки тел, измерен ПОТОЛОК
выигрыша: ручка `ArmyCore.SkipBodyScan` выключает `ScanBlock`/`EnemyBlock`
целиком (тела проходят друг сквозь друга), `qa_ab` блоки F/F2 меряют тик
чередованием, 6 раундов.

| сцена (24 отряда по 60, бессмертные) | проверка тел есть | выключена |
|---|---|---|
| F — сплошная рубка | 3.12 мс | 3.04 мс (+0.09, 2.7 %) |
| F2 — сближение | 3.80 мс | 3.95 мс (−0.16: без тел строй гуще, боёв больше) |

Никакая замена проверки тел отрезками не выиграет больше, чем её полное
отсутствие, а это — шум. Премисса заказа («тысячи точечных проверок
ежекадрово») не подтверждается профилем: `batch_move` + `sep_overlap` ≈
0.9 мс/кадр на 4000, тогда как решения боя в GDScript (`process_attack`
3.0, `atk_strike` 1.3, `atk_find_enemy` 0.4, `check_auto_aggro` 0.3) — около
5 мс. Хак не построен; ручка и блоки оставлены измерителем. Следующий
резерв тика — там же, где и был: частота решений фронта (см. закрытие
спринта D).

### Хак №3: площадка сбора

`_spawn_one` считал место бойца по рядам полос и раньше; менялось одно —
`_place_spawned` ставит бойца СРАЗУ на это место (`zone_pos`), а не в
проём ворот с маршем. Очередь в воротах, разбор наложения у дверей и
толчея двух заказов исчезают по построению; с флажком отряд собирается на
площадке и идёт к точке строем. `rally_zone()` — прямоугольник от
`SQUAD_EXIT_DISTANCE` до последней полосы, `in_rally_zone` — принадлежность,
рамка — у выделенного здания.

Две ловушки: `rally_zone()` обязан звать `_gate_position()` первым (тот
лениво ставит фасад и переписывает `spawn_offset`; прочитанный раньше — это
начальные (3, 0, 0), и площадка разворачивалась вбок); прозрачная заливка
маркера в GL Compatibility гасила под собой спрайты бойцов целиком (снимок:
два отряда пропали), плоский квад тонул в рельефе (±0.85 м) — рисуется
рамка из четырёх непрозрачных полос по рельефу.

Стенды прежнего требования «появились у ворот» переписаны на новое:
`qa_spawnlane` C1 («на площадке»), D2 («на площадке своего барака»),
A1-A3/B1 читают точку бойца вместо погашенного `move_target` (приказ в
своё же место исполняется тем же кадром), A2 — допуск 0.25 м вместо 0.01
(разбор наложения даёт сантиметры, рост отступа — метры); `qa_squad` 2.
Новый `qa_rally_zone` 12/12.

Известный красный `qa_rally2` F2: на карте 450 м зажатая точка сбора
ушла на 123 м от барака (было 28), терпения стенда не хватает — красный
существовал и до карты, разбор прежний.

### Шлюз

Стенды, которым спавн и площадка небезразличны (qa_rally_zone,
qa_spawnlane, qa_squad, qa_keep, qa_rally2, qa_guard, qa_hold, qa_settle,
qa_vet, qa_ai, qa_ai2, qa_res2, qa_difficulty, qa_bugpass, qa_tower,
qa_goblin, qa_troll, qa_mega_battle, qa_full_game_4k, qa_crowd, qa_push,
qa_helpbuild, qa_visab): красные — `qa_rally2` F2 (известный),
`qa_mega_battle` B1-1 (известный). Под нагрузкой шлюза мигнули и отдельно
зелёные: `qa_mega_battle` B2-3 («сквозь живой участок 3 из 64», отдельно
дважды 0 из 157 и 0 из 75), `qa_spawnlane` B1 (точка бойца читалась до
отложенной постановки на площадку — стенд теперь ждёт кадр), `qa_crowd`
(SCRIPT ERROR на освобождённом бойце в блоке C; отдельно 8/8).
`qa_rally_zone` 12/12.

## 10.09.2026, восьмая часть: шесть скриншотов, тролли, поражение, золотой рудник, рельеф, овцы

### Ресурсы — зафиксированы владельцем

`PLAYER_STARTING_RESOURCES` = 20 000 × 4 по прямому распоряжению («больше
никогда его не трогай»). `qa_balance` E2 («стартового запаса не хватает и на
одно исследование») переписан на запас ИИ — расчётная экономика судится по
нему, запас игрока — тестовый.

### Площадка сбора: 18 м вплотную

Скриншоты 1-3: жёлтая рамка мешает, первая шеренга в четырёх метрах от ворот,
рабочий появляется далеко под замком. `SQUAD_EXIT_DISTANCE` 1.0,
`GATE_CLEARANCE` 0.5, `EXIT_LANE_GAP` 1.0, `SINGLE_AGENT_EXIT_DISTANCE` 0.8
шага при шаге 0.7, `ZONE_DEPTH` 18. Число рядов выводится
(`Building.exit_lanes`): 20 копейщиков — 5 рядов с шагом 3.7 м (площадка
17.4 м), 60 — 3 ряда с шагом 6.3 м. Рамка спрятана ручкой `ZONE_MARKER_SHOWN`.
Стенды прежних чисел: `qa_rally_zone` B2 мерил «проём» кругом 1.2 м вокруг
ворот — теперь это круг до первой шеренги; `qa_squad` 2 требовал «> 5 м от
здания» и «ворота + 2 м»; `qa_rally2` E2 (3-5 м), E5 (2 м), E7 (центры > 5 м)
— все переведены на свойства от `SQUAD_EXIT_DISTANCE`, `squad_spacing` и
глубины строя. Известный красный `qa_rally2` F2 (зажатая точка сбора) остался.

### Тролль

Пятна крови сняты (`TROLL_BLOOD_SPOTS` 0, `qa_troll_impact` D2 развёрнут),
запас 32400 → 22680, кулдаун 1.4 → 1.167, подмога 2 → 1 тролль на 0.35
запаса вместо 0.5. Обрезанный спрайт тела: лента гибели уже нарисована
лежащей (последний кадр 384×384, рисунок в строках 168-296), общий слой тел
клал 11.8-метровый квад плашмя на рельеф с амплитудой 0.85 м — грунт резал
его. Тело тролля теперь свой билборд по правилам декораций, лента обрезана
до строк 86-311 (иначе 2.7 м пустого поля поднимали бы тело), кадры листает
таймер под узлом (10 кадров при 8 к/с), зеркало по стороне обидчика
относительно `camera.basis.x`. Клик: `pick_body_h` 3.0 / `pick_radius` 1.7,
кольцо ×4.2 — базис слота пишет GDScript, ядро трогает только точку
(проверено чтением `rb_slot`: buf[0] = buf[10] = 4.2). Стенд E1-E10
(клик в середину, макушку, край кольца; мимо в 14 м; тело билбордом, зеркало,
низ на грунте, доигранная лента).

### Орда и поражение

`GoblinAI._issue_orders`: нет бойца в `CENTER_RADIUS` — ближайшая чужая
постройка в 70 м получает `command_attack` (кроме охраны деревни и мести).
`Main._player_defeated`: правила 1 (крепость снесена и отстроить нельзя —
цена замка или нет рабочего/заложенной крепости) и 2 (ничего не осталось).
`qa_bugpass` 45/45, `qa_goblin` 72/72.

### Золотой рудник

Нейтральная сторона `FACTION_NEUTRAL` = 3 (ArmyCore.Factions = 4 — запас был
ровно под неё), группы `neutral_*`, вне `FACTION_COUNT`. Захват присутствием
пехоты (3 с без чужих; гоблины/тролли — защитники), флажок BannerArt цвета
стороны, доход 10 + 1/рабочий (замер: +30 и +45 золота за 3 с), рабочие
внутри тем же контрактом, что стройка, скрыты как гарнизон, перекраска при
смене владельца (сторона, строка ядра `set_faction`, отряд, ленты цветовой
папки), общая руина Destroyed с восстановлением любой стороной. Два ничейных
рудника на плато между замками. ПКМ по ничейному — марш. Стенд `qa_gold_mine`
24/24 (захват за 176 физкадров при пороге 3 с, контест 0.00 прогресса,
восстановление за 110 физкадров).

### Рельеф

Плато: `plateau_height` в GDScript и `ArmyCore.PlateauHeight` (расхождение
0.0000 м на 16 точках, `qa_map` F4). Спуск: уклон 0.23 + гармоники = 0.36
худший вдоль спуска (F3), обрыв 0.71. Порог стены у плато 0.45 — общий 0.30
попадал на спуск. Река: дно −1.07 при береге +0.60 (F5), зеркало 0.15 (F6),
брод 0.13 м воды над дном (F7). Оттенки: три листа `Tilemap_color` в сцене
(F9). Визуальный дым сперва дал 5 красных: ряды стенда стояли в русле (теперь
под водой) и на склоне плато — `_clear_spot` обходит откосы (`RIVER_BANK` + 2
м) и плато; после этого 19/19 в точке (−33, 14). `WORLD_GEN_VERSION` 4.

### Овцы

`Sheep.gd` — Node3D-декорация с `_process`, ленты обрезаны и зеркала
пересобраны в статический кэш. `TrollLair`: 5 на старте, +2 раз в 300 с до
10 (таймер-узел). `Troll._tick_hunger`: голод 150 с ±20 % или стадо > 5,
подход, удар, звук `nom_nom` (два синтезированных wav: три хруста
фильтрованного шума и глоток), +20 % запаса (15876 при ожидаемых 15876).
Стенд поймал: стартовый страж тоже ест (стадо 10 > 5) — C3 считает убыль «от
1 до числа троллей». Звук в headless не выдаётся (отсечка по дистанции до
слушателя) — стенд судит по факту запроса.

## 10.09.2026, девятая часть: строитель, еда и голод, кража овец, кузница, лист камня

### Шлюз восьмой части

55 сцен. Красные: `qa_mega_battle` B1-1 (ножевой порог, 20.0 м при 11.6 —
известный), `qa_rally2` F2 (83 м до зажатой точки — известный), `qa_ui9`
(панель 748 px — известный). `qa_balance` C7 («признак паники снят тем же
кадром», осталось 6) и `qa_troll` B5/B6 (одышка после серии, «ударов 1»)
покраснели под нагрузкой шлюза; одиночно сразу после — 21/21 и 24/24.
`qa_visual_smoke` 19/19 после того, как ряды стенда увели с откосов реки и
склонов плато.

### Анимация строителя

`want = "walk" if moved_recently() else "build"` давал молоток в первый кадр
приказа: окно замера хода пусто, боец «стоит». Теперь поза читает защёлку
прихода `_build_settled`, замах — тоже. Стенд: A2 считает кадры с молотком
в пути (0 из 234 физкадров), исключая кадр прихода — защёлка взводится
внутри того же физкадра, что и последний шаг.

### Содержание армии едой

До этого еда не тратилась нигде (комментарий «тратится на найм» был
пожеланием). Модель: `FOOD_UPKEEP_SQUAD_PER_SEC` 0.1 (60 за 10 минут —
ориентир владельца), `FOOD_UPKEEP_WORKER_PER_SEC` 1/30, дом 2.0 еды за 8 с
(было 4.0). Тождество 10 домов = 30 рабочих + 15 отрядов выполняется в
точности (2.5 = 2.5), стережёт `qa_food_economy` A1. Замер B1: три рабочих
и два отряда съели 1.50 за 5 с при ожидаемых 1.50. Голод: мораль отряда вне
боя 98 → 92.5 за 4 с и до пола 40.0 за 40 с, не ниже; еда вернулась —
46.0 через 3 с. HUD: «+0 −18» у еды, красным при дефиците.

### Кража овцы

Сценарий стенда: замок в 22 м от овцы, рабочий в 6 м. Взятие за 90
физкадров, путь к складу 441, у склада овца в 6.7 м от центра замка, пять
надрезов с миганием, 60 мяса (склад +59.5 — полсекунды содержания
самого вора), стадо 5 → 4. Загон-заглушка (`sheep_pens` + `accept_sheep`)
берётся вместо склада. Отмена приказом освобождает овцу на земле.

### Кузница и лист камня

Кузница 40 с (бараки 20), `bonus_build` удваивает темп площадки при 1.0
(замер D1: 1.00 → 2.00 прогресса за 60 физкадров). `qa_ai` 27/27 — темп
первых построек ИИ не сломался. Лист `Black/Pawn_Run_Stone.png` 1020×77 →
1152×192 (1894 перекрашенных пикселя, шесть золотых оттенков → серые).

## 10.09.2026, десятая часть: шаги тише, живые иконки, реплики реже, агро троллей

### Шаги

`MARCH_WALK_DB` −11.0 → −14.1, `MARCH_RUN_DB` −9.1 → −12.2 (−3.1 дБ =
амплитуда ×0.70). Потолок бюджета (−9.03 дБ на голос при двух) не тронут.

### Живая доступность иконок

До правки цвет «доступно / нет денег» ставился один раз в `_cmd` при сборке
панели. Теперь `_train_cmd` и `_build_cmd` регистрируют кнопку в
`_afford_watch` (кнопка, базовый цвет, цена, фракция, unit_id, здание,
последний вердикт), а `_on_resources_changed` зовёт `_refresh_afford()`:
пересчёт `can_afford ∧ pop_allows`, перекраска только сменившихся через
`_style_cmd_button` (те же стилбоксы, что у `_cmd`). В кузнице
`_rebuild_forge_grid` красит узлы `_forge_node_style(done, busy, avail,
afford)`; неоплатный доступный узел получает `FORGE_LACK_BORDER`, обновляет
`_retint_forge_nodes()` по тому же сигналу без пересборки сетки. Плашка узла:
строка «Цена: …» заменена рядом `_build_cost_row(upgrade_cost(node))`.
Замер `qa_hud_afford`: рамка кнопки замка меняется через 2 кадра после
`set_amount`, реестр пуст после `show_selection([])`, в плашке узла иконок
не меньше числа ресурсов в цене, строк с буквами 0.

### Реплики

`VOICE_ALTERNATE = {"hold_line": true}` — чётные вызовы пропускаются
(`_voice_alt`), пропуск пишет `_voice_last`. Окна mass_march/hold_line
6 → 9 с. Стенд: true/false/true при сброшенных окнах.

### Тролли

Скорость: `Troll.tick_physics` после `_was_charging` ставит `move_speed =
_base_move_speed × 1.2` при `attack_target != null or is_charging`, иначе
базовую; на смену — `_soa_push_stats()`. Замер A3: за 60 физкадров прошёл
≥ 0.8 × 3.46 м/с.

Агро: `Troll.take_damage` → `lair.on_guard_hit(self, attacker)`; при
`aggro_wave == 0` логово переводит волну в 1 и спавнит 2 помощников с
`command_attack(attacker, true, true)`; ужаленный без цели берёт обидчика.
`on_troll_died(u)` считает живых без `u`; при волне 1 и нуле живых — волна 2,
2 бонусных с `standard_reinforce = true` на `_last_attacker`. Подмога на
трети запаса (`TROLL_REINFORCE_AT` 0.35) осталась только у
`standard_reinforce`. `qa_troll` C1/C2/D3 переписаны под цепочку (было:
подмога на трети у стартового тролля), `qa_troll_impact._check_charge`
выключает `aggro_enabled`.

Ловушка стенда: помощники получают приказ на бойца из ОТРЯДА обидчика
(`squad_pick_member` — наименее обстрелянный), при двух копейщиках один
помощник шёл на второго; B3/C3 сверяют `squad_id` цели.

### Побочные находки

`Sheep.DIR` — `resources/sheep/` при папке `Sheep/`: Windows открывает с
предупреждением на каждый кадр, PCK не открыл бы вовсе (правило 8).
`qa_voice` F1в переписан на планку ×0.7; `qa_troll_impact` C7 — троллю
возвращается тик, вставшие отвечают на удар (прежде «в бою» обеспечивала
подмога на трети запаса, которой у стартового стража больше нет);
`qa_troll` — обидчик берётся живым из отряда.

## 10.09.2026, одиннадцатая часть: тактический разум гоблинов при штурме базы

### Архитектура

`scripts/goblin/GoblinAttackCommander.gd` (RefCounted, без class_name) —
командир штурма, объект вожака (`GoblinAI.commander`). Вход — `plan(field,
aim, village, clock)`: полевые отряды, точка базы, деревня, часы вожака;
выход — записи для `_order_queue`. Своего движения и боя нет: три вида
записей (марш, атака, отход) исполняет `GoblinAI._issue_squad`. Отход —
новый вид записи: `squad_clear_formation`, `begin_retreat`, `command_move(…,
keep_retreat = true)` в точку лагеря с местами толпы. Флаг `wake` у марша и
атаки снимает режим отхода (`end_retreat(true)`) — иначе вернувшийся щуп не
брал бы целей.

Состояния: `idle` → `assembling` → (`feint_attack` | `flank_sweep` |
`full_charge`) → `retreat_and_heal` → `idle`. Ось штурма (армия → ближайшая
постройка базы) замораживается вне `idle`/`retreat`. Линия сбора —
`front_pt − axis × ASSAULT_STANDOFF`, места отрядов поперёк оси через
`ASSAULT_LINE_STEP`. Слабое место — `weakest_side()`: число чужих у трёх
точек (левый фланг, центр, правый) по `army.query_radius`.

### Числа

`ASSAULT_STANDOFF` 30 (стрела и башня — 20 м, обзор построек 34 м),
`PROBE_FLANK_OFFSET` 22, `PROBE_INFANTRY_SEC` 8, `PROBE_CAVALRY_SEC` 5,
`PROBE_RECOVER_SEC` 5, `PROBE_CYCLES` 2, `HR_CAVALRY_SEC` 6,
`HR_CAVALRY_BACK_SEC` 6, `HR_BRAWL_SEC` 20, `HR_LOSING_DROP` 0.25,
`FAN_OFFSET` 24, `FAN_CASCADE_SEC` 1.5, `ASSAULT_RETREAT_HP` 0.5,
`ASSAULT_REARM_HP` 0.9, `ASSAULT_CAMP_FAR` 120, `ASSAULT_CAMP_DIST` 70,
`CAMP_HEAL_RADIUS` 30, `CAMP_HEAL_PER_SEC` 2 (гарнизон хижины лечит 1/с —
костры лагеря вдвое быстрее, число владельца).

### Стенд qa_goblin_tactics

Замок игрока и фаланга обороны (20 копейщиков), армия орды — два пеших
отряда по 30 и конный из 12 в 90 м «ниже» базы; деревня выключена. Блоки:
A сбор (линия в 30 м, армия дошла и встала без боя, ближайший гоблин не
подходил ближе линии минус радиус сбора), B провокатор (щуп пеший на фланг,
линия держится, отход щупа в режиме отхода, укол и отход конницы, после двух
векторов — навал, атака всем отрядам), C отход и лечение (запас 30 % →
`retreat_and_heal`, все в отходе, лагерь ≥ 70 м от базы, запас растёт у
костров, восстановились → новая волна, режим отхода снят), D веер (три
группы) и откатные волны (конница «attack», пехота без атаки).

### Уточнение владельца: тактики на всех фазах

Командир получил режимы (`mode`): `assault` (охота), `advance` (центр),
`defense` (деревня); `GoblinAI._issue_orders` зовёт `plan` / `plan_advance` /
`plan_defense` по фазе, смена режима сбрасывает ход. Марш: тело — линия
поперёк живой оси «армия → точка», дозор — конный отряд (нет конницы —
наименьший) на `VANGUARD_LEAD` 25 впереди тела, цель дозора переиздаётся при
уходе дальше 8 м; контакт (`VANGUARD_SIGHT` 30) → `full_charge` на точку
контакта; тихо и чужих у армии нет → марш. Оборона: угроза в
`DEFEND_RADIUS` 40 + `DEFEND_ALERT_PAD` 20 от деревни; рубеж пехоты
`DEFEND_LINE_DIST` 18, бой только в `DEFEND_ENGAGE` 16 от места; конница —
фланг угрозы `DEFEND_CAV_FLANK` 20, удар 6 с, отход 5 с, стороны чередуются;
раненые (< 50 %) к кострам до 90 %. Стенд: блоки E (дозор впереди пехоты на
марше, контакт → штурм всем отрядам, выбитый пикет → марш) и F (угрозы нет —
у костров; угроза в 45 м — пехота на рубеже в 18 м, конница с фланга,
после укола отходит, пехота за рубеж не выбегает, раненый отряд у костров с
ростом запаса).

### 🗓️ ШЛЮЗЫ ДЕСЯТОЙ И ОДИННАДЦАТОЙ ЧАСТИ (ШЛЮЗЫ #9 & #10) — ИТОГИ (сводка владельца)

#### 1. Полировка UI, Звука, Троллей и Тактический ИИ Гоблинов:
* **Звук и Голос:** Звуки ходьбы/бега снижены на 30%. Добавлен кулдаун на
  реплики войск (например, "Hold the line"). `qa_voice` — PASSED.
* **Реактивный UI:** Все иконки заказа юнитов, зданий и Кузницы обновляются
  динамически при притоке ресурсов без перезахода. Тултипы переведены на
  формат [Иконка + Цифра]. `qa_hud_afford` (13/13) — PASSED.
* **Агро-Система Троллей:** В преследовании скорость тролля +20%. При уроне
  возле Логова выбегают 2 помощника, при гибели всей троицы — гарантированно
  спавнятся еще 2 подкрепления. `qa_troll_aggro` (15/15) — PASSED.
* **Тактический Разум Гоблинов (`GoblinAttackCommander.gd`):**
  - Линия сбора в 30 м от базы.
  - Паттерны: «Провокатор» (щуп флангов), «Откатные волны» (удар конницы ->
    отход -> пехота), «Широкий веер» (3 группы).
  - Отступление при <50% сил на базу/костры для лечения до 90%.
  - `qa_goblin_tactics` (16/16 на приёмке, 25/25 после уточнения),
    `qa_goblin` (27/27) — PASSED.
* **Фиксы Ресурсов:** Исправлена заглавная буква папки `Sheep/` в пути
  `Sheep.gd` для корректного экспорта.

#### 2. Состояние Сюита:
* `qa_goblin_tactics`, `qa_troll_aggro`, `qa_hud_afford`, `qa_sheep` — GREEN.
* Полный шлюз #9 (60 сцен): известные красные `qa_mega_battle` B1-1,
  `qa_rally2` F2, `qa_ui9` 3, `qa_wall` A1; мигают под нагрузкой `qa_squad`
  3, `qa_mega_battle` B2-1, `qa_volley` (одиночно зелёные).

Побочно: приказ отхода сначала СНИМАЛ разметку отряда (как хижина), и
`qa_goblin` K3а («разметка на каждого бойца») краснел — план обороны
отправлял раненый отряд к кострам без мест. Теперь отход ставит разметку
толпы на лагерь; стенд K3а разбирает очередь приказов сам, а не читает
разметку прошлого плана. Затронутые стенды после уточнения: `qa_goblin`
72/72, `qa_troll` 24/24, `qa_bugpass`, `qa_full_game_4k`, `qa_reform` —
зелёные, дым Main без ошибок.

## 10.09.2026, двенадцатая часть: девять скриншотов владельца

Семь блоков заказа. Числа и правила — в CLAUDE.md, раздел «Двенадцатая
часть»; здесь — что мерилось и на чём спотыкались стенды.

### Старт и туман

Замер `qa_start_build` A: крепостей 0, рабочих 5, отступ от угла 44 м (было
24), освещено 1.7 % карты, центр карты тёмный, узлов `StartZone` и
`WorldBevel` нет. B: у бригады строить можно, в центре карты нельзя, правило
одно на все постройки. C: потолки 5/0 без крепости и 15/5 с ней, обзор
крепости 62 м, точка в 40 м от неё освещена.

**СТЕНДЫ, УТВЕРЖДАВШИЕ ОТМЕНЁННОЕ ТРЕБОВАНИЕ** (правило 10 проекта): `qa_fog`
B3 («площадка под замок раскрыта заранее»), B4 («раскрыта вся достижимая зона
размещения»), B6 (доля до 35 %) — переписаны на новое правило; `qa_world` 2i
(симметрия баз) — с поправкой на сдвиг старта, 4i/4j (бортик) — на «рамки нет,
чернота есть», с ветвью на случай, если ручку включат обратно.

**ПОБОЧНЫЕ НАХОДКИ В СТЕНДАХ.** `qa_world` и `qa_world3` роняли SCRIPT ERROR
на `main.CAM_BOUND_X` — константы с таким именем в Main нет и не было, то
есть блок камеры в `qa_world` и ВЕСЬ `qa_world3` умирали молча (та самая
ловушка «ошибка внутри корутины стенда убивает её без единого признака»).
Предел фокуса теперь берётся у камеры (`RTSCamera.bounds_max`). `qa_construct`
ставил замок кликом при включённом тумане — теперь глушит туман явно, как
остальные стенды. `qa_tower` D6 ждал, что найм упрётся ровно в потолок, — а
часть потолка занята стартовой бригадой партии; ожидание стало «потолок минус
занятые». `qa_worker_sheep` B6 требовал прирост склада не меньше сданного
мяса: разделка теперь длится сорок секунд, и содержание армии съедает часть
на глазах — судим по `meat_delivered`, склад с поправкой.

### Башня

Замер `qa_start_build` D: внутрь входит отряд 30, на настиле 10 спрайтов,
смертельный выстрел уменьшает гарнизон 30 → 29 и НЕ трогает запас башни
(6000 → 6000), точка падения тела в 2.0 м от центра, ряд снова 10 из 29,
удар копьём 500 уходит в стены (5500) и гарнизон не трогает.

### Тролль

E: тень 0.0, овал 1.45 × 0.90 при кольце 4.2, прицел 2.6 м, шесть стрел из
восьми гнёзд держатся в туше, в кольце из двенадцати копейщиков `breaks_bodies`
взведён и раздвинуто 12 из 12, крен туши при гибели 2.8° (разброс ±34° от
точки гибели). `qa_troll_impact` E2 переписан на овал и получил E2б — «базис
тени нулевой».

### Трава и порядок спрайтов

`GRASS_SUBDIV` 2 даёт вчетверо больше квадов у травяных поверхностей (клетка
рельефа осталась 2.5 м, тайл стал 1.25 м). Дым Main и `qa_visual_smoke` 19/19
после правки — силуэты и нижние кромки на месте, то есть ни глубина, ни
привязка спрайтов к земле не поехали.

### Что НЕ сделано и почему

«Войска не должны сбиваться в кучу» реализовано для ИИ (рассеивание вместо
последнего рубежа, когда противника рядом нет) и для орды (оборона деревни
рубежом, одиннадцатая часть). Своих бойцов игрока в кучу собирает ЕГО ЖЕ
приказ в одну точку — там работает штатное разведение отрядов
(`free_squad_spot`, `SEP_CROSS_SQUAD`), и менять его без замера на большой
сцене нельзя.

## Спринт 13 (10.09.2026): декорации, гноллы, загон, спецприёмы

Семь блоков заказа. Стенд `qa_sprint13` — **80 проверок, провалов 0**.
Компиляция чистая (`--headless --import`), дым `Main` чистый.

### Что сделано по блокам

1. **Декорации.** `Main._scatter_deco` сажает 01-15 по карте
   (`DECO_SMALL_PER_UNIT` × MAP_GROWTH² = 759 штук на нынешней карте),
   16-17 вдоль прямой между базами (8 указателей), 18 по периметру крупных
   зон (6 пугал). Всё — через `VegetationRenderer.plant`, то есть по одному
   бакету на файл: 26 бакетов на 5312 экземпляров вместе с лесом.
   `WORLD_GEN_VERSION` 4 → 5.
2. **Гноллы.** `scripts/goblin/Gnoll.gd`, `STATS["gnoll"]` (55 HP, урон 4,
   шаг 3.6, дальность 11 м), `goblin_config.GNOLL_*`. Кость — второй
   экземпляр `ArrowRenderer` (`GameManager.bones_mm`) со своим пулом; замер
   стендом: 24 кости в своём слое, в слое стрел ноль, `core_id` разные.
   Промахов 3 из 24 при `GNOLL_MISS_CHANCE` 0.3. Кайт: два срабатывания,
   дистанция 2.0 → 3.3 м. Стая — 3 отряда × 12 у пня, волна по удару,
   откат 600 с после третьей.
3. **Загон.** `scripts/SheepPen.gd` (плоский меш ограды по рельефу, 42
   вершины), запись `sheep_pen` в `BUILDINGS`, `mine.worker_buildable` =
   false. Потолки: 20 в загоне против 5 у замка; периоды 150 против 300 с.
   Разделка: 5 ударов до смерти, туша на боку (наклон 90°, `world_fixed` 1),
   20 ходок × 15 = 300 еды, 92 с под ножом плюс дорога.
4. **Четвёртый слот.** `squad_unlock_cost` = 0, `squad_has_ability` отвечает
   по исследованию фракции, `squad_ability_on` по умолчанию `true`.
   Стенд: ряд D закрыт до трёх базовых узлов, после них открыт.
5. **Спецприёмы.** `warrior_1d` «Яростный Набег» (серия
   [обычный, мощный, обычный, мощный, обычный], шаг 1.90 → 2.75 м/с,
   перезарядка 1.60 → 0.72 с, щит поднят), `spearman_4d` «Натиск Фаланги»
   (ход 2.00 → 1.20 м/с, удар 14 → 21, затем оттеснение: входящий ×0.70,
   напор 3.6). Раздача — `SelectionManager._trigger_double_rmb_abilities`.
6. **Ребаланс мечника** (сделан ранее в этом же заходе): 2 слота лимита,
   340 HP против 180, броня 10 против 3, шаг 1.90 против 2.00, напор 3.4
   против 1.0, вес 2.0 против 1.0, 600 золота и 60 с против 60 и 30.
7. **Монах:** потолок 3, зелёный эффект над целью (узел `HealVFX` в мире,
   а не ребёнком монаха).

### Ловушки этого захода

- **HEREDOC BASH СХЛОПЫВАЕТ ОБРАТНЫЕ СЛЭШИ** — правка `.gd` с продолжением
  строки (`\`) или с `\n` внутри формата через `python - <<'PYEOF'` молча
  не находит якорь. Такие патчи писать ТОЛЬКО файлом (Write), а не heredoc'ом.
  Поймано трижды за заход.
- **`class_name` ОБЯЗАН ИДТИ СРАЗУ ЗА `extends`.** Вставка `const` между ними
  (`Worker.gd`) — ошибка разбора. Второй раз за два захода (первый был
  `RTSCamera.gd`).
- **ПРАВИЛО 6 СНОВА:** пересборка меша ограды через `queue_free` без
  `remove_child` оставляла старый узел с его ИМЕНЕМ до конца кадра, и новый
  получал суффикс — стенд, искавший «PenFence» по имени, не находил ничего.
- **ПРОПУЩЕННЫЙ `await` У БЛОКА СТЕНДА ГАСИТ ЕГО МОЛЧА.** `_h_monk()` без
  `await` в `_run()` доходил до первого ожидания физкадра, а `_run`
  продолжал до `_finish()` и гасил сцену: три вердикта не печатались вовсе,
  и «провалов: 0» оставалось честным.
- **ПРАВИЛО 5 В СТЕНДЕ:** `sh.consume()` ставит признак и отправляет узел в
  очередь освобождения — читать у него поле через кадр нельзя.
- **ЗАМАХ ЛОМАЛ ПРОВЕРКУ ЩИТА.** Гоблин в полутора метрах успевал получить
  авто-агро, замах ставил `_anim_lock_until_ms`, и `_update_guard` делал
  ранний выход: «щит в набеге поднят» краснело через прогон НЕ на коде.
  Лечение — заморозить обоих `set_tick(false)`, как всадника в `qa_cavalry`.

### `qa_world3` после починки: что осталось красным

Стенд впервые ЗАПУСТИЛСЯ в прошлом заходе (до этого он молча умирал на
несуществующей константе `main.CAM_BOUND_X`), и вскрывшиеся провалы —
пре-существующие, а не регрессии спринта. Разобрано:

- **З1 и З8 УТВЕРЖДАЛИ ОТСУТСТВИЕ ЗАПАСА ЗА КРАЕМ КАРТЫ.**
  `RTSCamera.EDGE_OVERSCROLL` = 26 м заведён НАМЕРЕННО и с разбором в
  комментарии: без него угловой замок прижимался к самому краю экрана и
  частью уезжал под панели HUD. Обе проверки переписаны на защищаемое
  свойство — пределы разведены по осям и не выходят за карту БОЛЬШЕ, чем на
  этот запас.
- **С6 УТВЕРЖДАЛ ЗЕЛЁНУЮ ЗОНУ ЗАСТРОЙКИ**, которую владелец развернул
  10.09.2026: зоны больше нет вовсе, строить можно где угодно вне тумана, и
  призрак зажимается только пределами карты. Переписан на них.
- **С7 НЕ ГЛУШИЛ ТУМАН** перед постановкой замка (с 10.09.2026 постройка
  разрешена только на разведанной земле), а печать точки непоставленного
  замка роняла блок `SCRIPT ERROR`: тернарник в аргументе `print` вычисляет
  ОБЕ ветви, и с ним умирали С8-С10.
- **М0 БРАЛ ЧИСЛО БОЙЦОВ ИЗ ПАМЯТИ, А НЕ ИЗ КОНФИГА (правило 10).** Стенд
  ставил 60 копейщиков «на глаз при уставном отряде 50», а
  `SQUAD_SIZE_SPEARMEN` с тех пор стал ровно 60 — все шестьдесят складывались
  в ОДИН отряд, который честно вставал гарнизоном: «в поле 0 бойцов при
  1 отряде». Теперь число выводится из `squad_size("spearman")`.
- **М0-М7 ПОСЛЕ ПОЧИНОК ЗЕЛЁНЫЕ ЦЕЛИКОМ.** Красными их держали два числа в
  самом стенде: гарнизон ИИ (он оставляет дома до `HOME_GUARD_PER_TYPE` = 7
  отрядов на род, а стенд ставил три и ждал излишка) и ШИРИНА БЛОКА армии —
  она стояла числом 8, и на пятистах сорока бойцах блок уходил на шестьдесят
  метров в глубину, то есть ЗА КРАЙ КАРТЫ; «центр армии» оказывался у самой
  границы, и М2 «идёт серединой карты» ловила 1559 кадров у стены на
  исправном коде. Оба числа теперь выводятся из конфигов.
- **ОСТАЁТСЯ ОДИН КРАСНЫЙ — Г12** («на потолке зума у короткой кромки поле
  занимает 43 % кадра вместо половины»). Это свойство ПРЕДЕЛОВ ЗУМА на карте
  ×3 по площади, к спринту отношения не имеет и разбирать его надо отдельным
  заходом: либо опускать `max_height`, либо признать, что на пределе
  отдаления чернота по краям занимает больше половины кадра, и переписать
  проверку под это.

### Стенды, покрасневшие НА РАЗВОРОТЕ ТРЕБОВАНИЯ, а не на коде (спринт 13)

Правило 10 в четвёртый раз за проект: прежде чем чинить код по красному
стенду, проверь, не утверждает ли проверка требование, которое владелец
только что развернул. Все четыре случая — ровно это.

- **`qa_forge` A6, E2-E7 и `qa_volley` A5, B1-B3, E1-E2, F1, F4** держались на
  отменённой ПЛАТЕ ЗА ДОСТУП: «способность покупается каждым отрядом за
  `squad_unlock_cost` и сразу после покупки ВЫКЛЮЧЕНА». Заказ блока 4 говорит
  обратное — «открывается сразу для всех юнитов соответствующего типа, плату
  за применение убрать», — и блока 5 — «активна по умолчанию, можно
  отключить». Переписаны на новые свойства: признак способности остался
  структурным (колонка D), доступ выдаёт ИССЛЕДОВАНИЕ фракции, режим включён
  сразу, а «без режима» в замере темпа стрельбы теперь ЗАДАЁТСЯ тем же
  переключателем, которым его гасит игрок.
- **`qa_monk` A3, A4, A6** утверждали ЧИСЛО, а не правило: «второй заказ
  отклонён» при `MONK_LIMIT` = 1. Потолок поднят до трёх; проверки переписаны
  на «принимается ровно `MONK_LIMIT`, следующий отбивается».
- **`qa_worker_sheep` B4-B7** описывали прежний ОДНОШАГОВЫЙ порядок: донёс
  овцу до склада — сразу режет. Спринт 13 разделил его на два: живая овца
  уходит НА ВЫПАС (загон или зона замка), а разделка — отдельный приказ по
  своей овце. Блок переписан под оба шага, B5 теперь стережёт ОТСУТСТВИЕ
  красного мигания, а не его наличие.
- **`qa_worker_sheep` B2 краснел ПО ДРУГОЙ ПРИЧИНЕ, и она настоящая.**
  Со спринта 13 у пня стоят 36 гноллов, и тридцать шесть чужих ТЕЛ вокруг
  овцы физически не пускают вора к ней (`enemy_block` на шаге): стенд ловил
  «фаза GO, 1200 физкадров» на исправном коде. Это не послабление, а правило
  проекта — сценарий, зависящий от окружения, обязан ставить это окружение
  сам; стенд теперь убирает стаю, потому что меряет РАБОЧЕГО, а не бой.
- **`qa_worker_sheep` B4в нашёл НАСТОЯЩИЙ БАГ.** Лента разделки выбиралась по
  РЕСУРСУ (`_work_res_type`), и с ножом она совпадала лишь потому, что фаза
  переноски выставляла `carrying_type` = FOOD. Разделка СВОЕЙ овцы на выпасе
  такой фазы не проходит вовсе — приказ идёт сразу в `KILL`, — и рабочий
  махал ТОПОРОМ по овце. Теперь лента спрашивает сам род работы (фазу), а не
  её побочный признак.

### Ещё три настоящих бага, вскрытых оживлением qa_world3 и qa_fog

- **ДЕСЯТЬ РАБОЧИХ ВМЕСТО ПЯТИ.** До заказа 10.09.2026 партия начиналась
  фантомом замка, и стартовую бригаду выдавала САМА постановка первой
  крепости. Заказ развернул начало: пятеро выходят сразу, в `start_game()`, а
  крепость игрок закладывает кнопкой рабочего — и прежний вызов
  `_spawn_starting_workers` в `_try_place_castle` остался ВТОРЫМ. На карте
  оказывалось десять рабочих, из них пять взявшихся из ниоткуда и не считанных
  лимитом населения. Поймал `qa_world3` С8 («рабочих 10, дальний 14.3 м»).
- **ПРОСТО СНЯТЬ ТОТ ВЫЗОВ БЫЛО НЕЛЬЗЯ, И ЭТО ПОЙМАЛ ВТОРОЙ СТЕНД.** Вместе с
  рождением он делал ВТОРУЮ вещь — отправлял бригаду СТРОИТЬ ЗАМОК; без неё
  пятеро продолжали рубить лес, пока крепость поднималась сама
  (`qa_fog` E4-E6: «строят 0, добывают 5 из 5»). Теперь
  `Main._crew_to_first_castle` ставит на стройку ТУ бригаду, что уже есть, а
  рождение осталось запасной дорогой для случая «рабочих нет вовсе» (стенды,
  ставящие замок первым действием, и старые слепки). И только для ПЕРВОЙ
  крепости: снимать пятерых с добычи на каждый новый замок нельзя.
- **ЗАМОК ЗАЖИМАЛСЯ НЕ ТЕМ КРАЕМ.** `_try_place_castle` звал
  `GameManager.clamp_to_map`, а тот держит предел ХОДЬБЫ БОЙЦА
  (`MAP_HALF − MAP_EDGE_MARGIN`). У построек край свой и ближе к центру
  (`MAP_CLAMP = MAP_HALF − 5`), и клик далеко за краем ставил замок на
  223.5 м при строительном пределе 220 — крайняя стена уезжала в черноту.
  Поймал `qa_world3` С10.
- **`qa_fog` D6б МИГАЛ НА ЗАГРУЗКЕ, А НЕ НА КОДЕ** (правила 11 и 12):
  задержка гашения `FOG_HIDE_GRACE` считается СТЕННЫМИ ЧАСАМИ, а стенд ждал
  «столько-то кадров ОТРИСОВКИ». Одиночно 42/42, в шлюзе рядом с другими
  прогонами задержка не успевала истечь. Ждём теперь СВОЙСТВО с потолком по
  часам.

## Спринт 14 (11.09.2026): тролль, гноллы, овцы, логика огня, приёмы, VFX, башня

Семь блоков заказа плюс две отдельные задачи, пришедшие по ходу (VFX лечения
монаха и спрайты этапов башни). Пять новых стендов спринта, два новых сверх
него. Ниже — только то, что нельзя вывести из кода.

### Стрелы на лету превращались в кости: один `int` на все полёты

**ЖАЛОБА ВЛАДЕЛЬЦА ДОСЛОВНО:** «лучники стреляли стрелами, стрелы летели и в
какой-то момент превращались в кости, и падали кости, и валялись кости».

- **ПЕРВЫЙ ЗОНД ОБВИНИЛ НЕ ТО, И ЭТО БЫЛО ЗАКОНОМЕРНО.** Слои и пулы проверены
  и чисты: у стрелы своя текстура (43×12) и свой буфер, у кости своя (35×44) и
  свой; признак `bone` ставится ДО `_ready()`, пулы раздельные
  (`GameManager._bone_pool`). То есть РАЗДАЧА снаряда исправна — и ровно
  поэтому первая версия проверки ничего не нашла.
- **ЛОМАЛСЯ САМ ПОЛЁТ, И ЭТО ВИДНО ИЗ ФОРМУЛИРОВКИ ЖАЛОБЫ.** Слово «на лету»
  указывает не на спавн, а на `BatchArrows`: номер буфера отрисовки хранился
  ОДНИМ ПОЛЕМ на все полёты сразу (`ArmyCore._afB`), и его перезаписывал
  КАЖДЫЙ следующий `ArrowLaunch`. Взлетела кость — и весь проход начинал
  писать позиции ВСЕХ летящих стрел в буфер костей: стрела в воздухе меняла
  картинку, а потом втыкалась в землю костью.
- **ЛЕЧЕНИЕ — КОЛОНКА, А НЕ ПОЛЕ** (`_afB` стал массивом, как `_afId`/`_afSlot`
  и все прочие свойства полёта). Плюс страховка в `BatchArrows`: номер буфера
  вне диапазона снимает полёт, а не роняет проход.
- **ЧТО ИЗ ЭТОГО СЛЕДУЕТ НА БУДУЩЕЕ.** Всё, что описывает ОДИН полёт, обязано
  лежать в колонке полёта. Скалярным полем в пакетном проходе может быть
  только то, что одинаково для ВСЕХ его строк.
- Стережёт `qa_gnoll_fix`, блок E: стрела и кость летят ОДНОВРЕМЕННО и
  вперемежку, и каждая обязана всю дорогу оставаться в СВОЁМ коридоре
  «вылет → цель» (отклонение по земле у честного полёта нулевое — дуга
  поднимает только высоту).

### Точку летящего снаряда знает БУФЕР, а не узел

Ловушка стенда, стоившая двух красных подряд: на время полёта стрела — ЗАПИСЬ
в ядре, её узел стоит там, где взлетел, а позицию ведёт `BatchArrows` и пишет
прямо в слот общего MultiMesh. Замер высоты дуги по `global_position` меряет
ТОЧКУ ВЫЛЕТА: первая версия `qa_gnoll_fix` C4 намеряла ровно `GNOLL_THROW_Y`
(1.05 м) и объявила навес сломанным. Читать надо `rb_slot` слоя (раскладка 16
float, точка в 3/7/11) — тогда пик выходит 11.6-13.3 м при броске на 8.5.

### Тролль: тонкий овал вместо толстых дуг, стрелы больше не торчат

- **ОБВОД — ТОТ ЖЕ МЕШ, ЧТО У ЗДАНИЯ, А НЕ РАСТЯНУТОЕ КОЛЬЦО БОЙЦА.** Кольцо
  пехотинца — тор о ДВЕНАДЦАТИ сегментах; растянутое до тролля (×4.2) оно
  давало и толстую трубу (0.168 м), и угловатый обвод — ровно «толстые кривые
  красные дуги» со скриншота. Тонкий меш единичного радиуса о 64 сегментах
  даёт 0.023 м, то есть в семь раз тоньше. Признак «кому тонкий обвод» —
  свойство (`Unit.fine_ring_radius() > 0`), а не список типов: у зданий он
  уже был, тролль просто встал в тот же ряд.
- **ГНЁЗД ПОД СТРЕЛЫ У ТРОЛЛЯ БОЛЬШЕ НЕТ ВОВСЕ** (`arrow_sockets()` → 0, вся
  машинерия `stick_arrow`/`_move_arrows`/`_drop_arrows` удалена). Заказ
  спринта 12 («стрелы торчат в живой туше») развёрнут спринтом 14. Пехота
  платит за это ровно одно сравнение, как и раньше.
- **ПРОМАХИ ПО КРУПНОЙ ЦЕЛИ — ЭТО ТОЧКА, А НЕ ВЕРОЯТНОСТЬ УРОНА**
  (`aim_miss_chance` / `aim_miss_spread`, у тролля 0.22 и 2.4 м): доля стрел
  намеренно уходит в землю рядом и втыкается там. Тот же приём, что у
  промахов гнолла, и та же причина: это видно на экране и не требует ни одной
  новой ветки в расчёте урона.

### Гнолл больше не бежит на месте

- **ПРИЧИНА БЫЛА В КАЙТЕ, А НЕ В АНИМАЦИИ.** Отход выдавался приказом раз в
  `GNOLL_KITE_SEC`, а сквозь чужой строй не проходит никто: окружённый гнолл
  вечно оставался в `State.MOVING` с зацикленным лупом шагов. Теперь
  проверяется ФАКТ: не сдвинулся за `GNOLL_KITE_GIVEUP` больше чем на
  `GNOLL_KITE_MIN_GAIN` — кайт глушится на `GNOLL_KITE_BLOCK_SEC`, скорость
  обнуляется, состояние уходит из MOVING. Свойство, а не таймер: «некуда
  отбегать» — это про геометрию, а не про время.
- Стенд воспроизводит жалобу дословно: кольцо из двенадцати чужих тел вокруг
  одного гнолла.

### Логика огня лучников: встаёт ВЕСЬ отряд по первому дострелившему

- **«ДОСТРЕЛИЛ» СТАЛО ОТРЯДНОЙ ВЕЛИЧИНОЙ** (`GameManager._ranged_engaged`).
  Личный признак `_engaged_once` верен для того, кто уже дошёл: передний
  встаёт, задний в трёх метрах позади — ещё нет, и отряд втягивается в
  противника ниткой по одному, теряя залп. Живёт отметка рядом с якорем
  погони: у них общий жизненный цикл, и снимает обоих один и тот же новый
  приказ. Отдельно от якоря — потому что якорь ставится и рукопашной пехоте,
  а «встать и стрелять» — правило ТОЛЬКО дальнобойных.
- **ЗАМЕР (`qa_archer_logic`, 16 лучников колонной в четыре шеренги):** отряд
  идёт 8 м, объявляет «дострелили», и дальше центр стоит (25.8 → 26.1 м за
  шесть секунд, блуждание 0.27 м) и стреляет, при том что ЗАДНИЕ ряды до
  врага не дотягиваются.

### Что стенды нашли про сам движок правил (и чего не чинили)

Три находки, каждая — ловушка не только для стенда, но и для игрока.

- **ПРИКАЗ АТАКИ ПО ЦЕЛИ ДАЛЬШЕ `_lock_sight_range()` НЕ ДОЖИВАЕТ ДО ЦЕЛИ.**
  Замок держится, пока цель ближе максимума из двойной дальности оружия и
  2 × `AGGRO_RADIUS` (у лучника 40 м, у пехоты 20 м). Дальше приказ считается
  исчерпанным: боец снимает замок, переносит пост и разворачивается. Замер:
  отряд, посланный на врага в 46 м, честно шёл девять секунд до 30 м, затем
  уходил обратно и вставал в 52 м. Правило старое и осознанное, но с новым
  «встать и стрелять» оно образует потолок дальности приказа — и это стоит
  знать, прежде чем удивляться. Стенды ставят цель ВНУТРИ этой черты.
- **КЛИК ПО БОЙЦУ НА ВОЗВЫШЕННОСТИ ПРОМАХИВАЕТСЯ.** `SelectionManager._pick_at`
  считает точку земли под курсором аналитически, пересечением луча с
  плоскостью y = 0 («грунт плоский»). Боец на плато выше этой плоскости, и
  точка земли уезжает от него на высоту, делённую на тангенс наклона камеры:
  на плато в 5.65 м это 6.5 м, то есть мимо любого радиуса поиска. Замер
  `qa_knights_push`: «под курсором `<null>`» при курсоре ровно на спрайте.
  **Не чинилось в этом заходе** — правка трогает разбор ЛЮБОГО клика в игре;
  стенд выбирает ровную площадку (`_flat_spot`) и печатает перепад.
- **ОТРЯД, ВСТАВШИЙ СТРЕЛЯТЬ, УХОДИТ ОБРАТНО, КОГДА ПРИКАЗ ИСЧЕРПАН.** Зонд
  `qa_archer_logic` (без вердикта): ещё через 20 с центр 25.8 → 45.4 м. Это
  штатный путь `release_target_lock` + `_hold_where_i_stand`: цель признана
  недостижимой, приказ считается выполненным, боец переносит пост. Спорным
  тут остаётся ровно одно — что «недостижимой» цель становится у стрелка,
  который по ней СТРЕЛЯЕТ; вопрос владельцу, а не коду.
  **МОМЕНТ ЭТОГО СНЯТИЯ В HEADLESS ПЛАВАЕТ, И ЭТО ЛОВУШКА ДЛЯ СТЕНДА.** Часть
  ворот боя отмеряется настенными часами, а физкадры их обгоняют (правило 12):
  один и тот же код давал «гулял 0.27 м» и «гулял 11.14 м» в двух прогонах
  подряд. Поэтому окно замера в блоке C закрывается ПО СВОЙСТВУ — по снятию
  замка приказа, — а сколько оно продержалось, печатается числом (B3б следит,
  чтобы замер не выродился в ноль). Что происходит ПОСЛЕ, меряет зонд, и
  вердикта у него нет.

### «Яростный Набег»: множитель толчка обязан идти ПОСЛЕ потолка шага

- **ПЕРВАЯ ВЕРСИЯ ПРИЁМА НЕ ДЕЛАЛА НИЧЕГО, И ЭТО ПОКАЗАЛ СТЕНД.** Заказ просил
  «увеличить силу отталкивания, чтобы врагов заметно раскидывало»; правка
  подняла НАПОР (`_push_power`) в 2.6 раза — и жертву отодвигало на 0.70 м
  против 0.68 без набега (`qa_knights_push` D4). Причина записана в шапке
  `_apply_push` и была пропущена: шаг зажат потолком 0.4 м, а потолок
  срабатывает уже при разнице напора в три единицы — весь избыток в него и
  упёрся.
- **РАБОТАЕТ ТО ЖЕ, ЧТО У КОННИЦЫ: МНОЖИТЕЛЬ ПОСЛЕ `clampf`.** Прежде это было
  ПОЛЕ (`charge_push_mult`), и полем его хватало, пока такой множитель был
  только у конницы и стоял на всю её жизнь. У приёма он ВРЕМЕННЫЙ (девять
  секунд), и гонять поле туда-обратно значило бы вести состояние в двух
  местах. Заведён виртуал `Unit._push_after_cap()`; мечник домножает его на
  время набега. Замер после правки: **2.37 м против 0.82 м**.
- **ПОБОЧНО ЭТО ВКЛЮЧАЕТ ПЛАВНЫЙ КАНАЛ И ВМЯТИНУ РАЗМЕТКИ** — обе ветки
  `_apply_push` теперь спрашивают тот же `after_cap`. Так и задумано: без
  вмятины смыкание рядов вернуло бы строй на место, и от набега не осталось
  бы следа; без плавного канала отлёт читался бы телепортом.
- **ЛОВУШКА ЗОНДА, СТОИВШАЯ КРАСНОГО:** плавный толчок кладёт жертве СКОРОСТЬ,
  а интегрирует её ЕЁ ЖЕ физический тик. Замороженная жертва (`set_tick(false)`)
  не сдвигается ни на сантиметр — первая версия намеряла «в набеге 0.00 м» на
  работающем толчке. И мерить оба случая надо ПОСЛЕ того, как скорость
  погасла: обычный пехотный толчок переносит точку сразу, плавный — за доли
  секунды.

### Что сломал сам авто-переход рабочего (поймал шлюз)

Переход на следующую овцу «тем же кадром» — это не только новая возможность,
но и новое СОСТОЯНИЕ мира, в котором прежние стенды не жили: рабочий после
выработанной туши больше никогда не бывает свободным, пока рядом есть овцы.
Два вердикта `qa_worker_sheep` на этом и покраснели, и оба — про снятое
требование, а не про поломку.

- **СЧЁТЧИК ХОДОК ПРИНАДЛЕЖИТ ТЕКУЩЕЙ ТУШЕ.** B5б читал `sheep_trips()` ПОСЛЕ
  конца разделки и ждал там двадцать. Новая работа обнуляет счётчик, и в конце
  там законный ноль. Судить надо по ходкам, ЗАМЕЧЕННЫМ ПО ХОДУ (стенд их и так
  считал), а не по остатку.
- **ПРИКАЗ ПО ОВЦЕ, КОТОРУЮ РАБОЧИЙ И ТАК НЕСЁТ, УХОДИТ В НИКУДА.**
  `command_steal_sheep` выходит сразу, если овца не свободна (`is_free`), — а
  своя же захваченная как раз несвободна. Блок C заказывал «ближайшую», получал
  ту, что рабочий уже нёс, и мерил чужую, уже идущую работу. Стенд теперь
  сперва освобождает рабочего и берёт заведомо свободную овцу.
- **И ОВЦА ДЛЯ ЭТОЙ ПРОВЕРКИ ОБЯЗАНА БЫТЬ ДИКОЙ.** Ближайшей свободной
  оказывалась СВОЯ — та, что блоком раньше ушла на выпас к замку; такую режут
  НА МЕСТЕ (`SheepPhase.KILL`), а не несут, и признак «нёс» законно оставался
  ложным. Три условия отбора (свободна, жива, дика) нужны все три.

### VFX лечения монаха живёт НА ИСЦЕЛЯЕМОМ

- **УЗЕЛ ОДИН НА МОНАХА, А «ЭФФЕКТ НА ЮНИТЕ» — ЭТО ПРИВЯЗКА.** Лечение идёт
  два раза в секунду (`MONK_HEAL_TICK` 0.5), и квад на каждый такт означал бы
  два узла в секунду на монаха до конца партии. Снять эффект с юнита — это
  разорвать привязку и погасить квад; освобождается он вместе с монахом.
- **ЕДЕТ ЗА ЦЕЛЬЮ КАЖДЫЙ ТИК, А НЕ РАЗ В ТАКТ.** Прежняя версия ставила точку
  один раз на такт, и уходящий раненый оставлял эффект висеть за спиной.
  Точка берётся НАРИСОВАННАЯ (`draw_position`) — та же, по которой едут
  знамёна. Высота — `aim_height()` цели: у тролля центр массы на 2.7 м, у
  пехотинца на 0.8, и общая константа повесила бы заклинание либо в ноги,
  либо в небо.
- **ПРИЧИН ПРЕКРАЩЕНИЯ ПЯТЬ, И КАЖДАЯ ПРОВЕРЯЕТСЯ ОТДЕЛЬНО** (`qa_monk_vfx`,
  блок E): цель вылечена, монах переключился на другую, монах отошёл дальше
  радиуса, монах погиб, монах ушёл со сцены. Окно `HEAL_VFX_GRACE` чуть шире
  такта — без него эффект мигал бы между тактами, потому что «монах лечит» —
  событие, а не состояние.
- **`remove_child` В `_exit_tree` ОТБИВАЕТСЯ ДВИЖКОМ** («Parent node is busy
  adding/removing children»). Правило 6 писано для случая, когда детей
  контейнера считают в том же кадре; здесь мы приходим, когда движок УЖЕ
  перестраивает дерево. Та же грабля, что у укладки упавшего знамени, только
  там отбивался `add_child`. Поймал `qa_monk_vfx`.

### Башня: свои спрайты этапов

- **НАБОР КАРТИНОК ИЩЕТСЯ ПО ID ПОСТРОЙКИ, А НЕ СПИСКОМ ИСКЛЮЧЕНИЙ**
  (`game_settings._process_sprite`). Было «замок → свои, всё прочее → общие
  домовые»; стало — строка в `PROCESS_SPRITES` по ключу постройки, чего нет в
  таблице, берёт домовые. Заведётся своя картинка у бараков — хватит строки.
- **ВТОРОЙ КОРЕНЬ, А НЕ КОПИЯ ФАЙЛОВ.** Спрайты башни лежат рядом с
  постройками, а не в папке «процессов»; копировать их во вторую папку ради
  единообразия нельзя — два файла с одной картинкой разъедутся при первой же
  перерисовке. Строка таблицы называет корень (`root: "buildings"`).
- **ДОЛЯ 0.6 СНЯТА.** Она ужимала ЧУЖУЮ («домовую») картинку: та широкая и
  низкая, а башня узкая и высокая, и в полный размер пепелище лежало шире
  самой башни. Свои спрайты нарисованы ровно по башне (128×256, как сам
  `Tower.png`) — ужимать нечего.
- **PNG БЕЗ `.import` НЕ ГРУЗИТСЯ ВОВСЕ** («No loader found for resource»):
  файлы лежали в репозитории с августа, но импорта у них не было. Заметил
  стенд; лечится одним `--headless --import`.
- `qa_tower` B3б переписан: он утверждал снятое требование («картинка в долю,
  меньше 1»).
