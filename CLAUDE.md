# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Dark Republic is a 3D survivors-like roguelite in **Godot 4.7 (GDScript, Forward Plus, Jolt Physics)**. There is no build step: open `project.godot` in Godot and press F5. `README.md` (~1,000 lines) is the detailed reference for every feature, with exact numbers, file names and test commands. Read the section for the area you're touching before changing it, and update it when behaviour changes. (Its "Known limitations" section at the end is out of date.)

On this machine neither `godot` nor `git` is on the PATH, so ask the user where the Godot executable is before running anything.

## Commands

All tests are headless scenes in `tools/`. Each prints `ok`/`FAIL` lines and a final `TEST PASS|FAIL (n failures)`, and exits 1 on failure. Run one:

```bash
godot --headless --path . res://tools/test_wallet.tscn
```

Some tests need `--fixed-fps 60` (swamp, entrances, minimap, chests, subboss, portal, bonuses). The README's Testing section lists the exact command for each.

```bash
# Full smoke test: bot plays, 1400-enemy stress phase, death screen, restart
godot --headless --path . --fixed-fps 60 -- --smoketest --smoke-seconds=240

# Playtest bot: real runs, one line per run + JSONL with the last 10 s before each death
godot --headless --fixed-fps 60 --path . res://tools/playtest.tscn -- --chars=thunder_wizard --runs=5 --map=forest --out=results.txt

# Screenshot of a run (not headless)
godot --path . -- --shot=/tmp/shot.png --shot-at=4 --shot-cast=0@1 --shot-spawn=120

# Crowd simulation benchmark
godot --headless --path . res://tools/bench_enemies.tscn
```

Useful command-line flags (after `--`): `--map=swamp|forest|castle|desert|graveyard|caldera`, `--lang=es` (language for this session, not saved), `--skip-intro`, `--shot-nohud`, `--shot-pos=x,y,z[,yaw]`, `--boss-at=T`, `--loader-hold`.

Other tools: `tools/render_*.tscn` / `shot_*.tscn` make reference images. `tools/gen_*_sounds.py` generate the procedural sound effects. `tools/bake_vat.gd` re-bakes goblin vertex animations from GLBs. `tools/i18n_extract.py` then `tools/i18n_build.py` update translations.

## Architecture

**Flow:** `scenes/splash.tscn` (logo) → `intro.tscn` (first launch only) → `title.tscn` → mode menu → `character_select.tscn` → map picker → `main.tscn` (the run). **Every scene change goes through `Loader.go(path)`** (`scripts/loader.gd`), never `change_scene_to_file` directly. It handles the background load and the loading screen.

**Autoloads** (`project.godot`): `Events` (signal bus), `Settings` (options, selected character/map, save/load, translations, audio buses `Music`/`SFX`), `Wallet` (coins, character EXP/levels, feats and unlocks, saved to `user://progress.cfg`), `MenuMusic`, `Loader`.

**The run (`scripts/main.gd`)** owns run state, the spawn director and a fixed tick order: spawn → enemies (compact dead, rebuild grid, steer, separate, upload MultiMesh) → weapons and items (query the grid) → gems → contact damage. Kills are flagged and swap-removed at the start of the next tick, so indices stay valid within a frame. Big crowds are data-oriented. `enemy_manager.gd`, `weapon_system.gd`, `gem_manager.gd`, `corpse_manager.gd` and `fx_manager.gd` keep packed arrays and draw one MultiMesh each, not one node per entity. Goblins animate with baked vertex animation (`vat_crowd.gd`). Keep new crowd-scale things in this style.

**Stats:** `stats.gd` computes `(base + flat) * (1 + add%) * mult`. Base stats are `BASE_STATS` in `main.gd`. At run start the skill tree applies first, then character bonuses (`char_bonuses.gd`).

**Data-driven content (`data/`):**
- `upgrades.json`: weapons, tomes and items with `per_level` modifiers, loaded and drafted by `upgrade_db.gd`. Card text is generated from it.
- `characters.json`: roster entries (portrait traits drawn by `character_icon.gd`, `fx` particle motif, `bonuses`, prices, `banned_maps`).
- `abilities.json`: each character's weapon and 3 abilities, read by `kit_db.gd`. `{braces}` mark highlighted numbers. Icons come from `ability_glyphs.gd`.
- `tips.json`, `taglines.json`, and `i18n/` (translations: `src/*.json` hold `[es, fr, ar, de, zh_CN, ja]` per English string).

**Characters:** `hero_base.gd` defines what a playable model provides. The Fire Wizard uses `hero_model.gd` + `abilities.gd`. Everyone else uses `roster_hero.gd`, configured per character in `RosterHero.CFG` (clip segments, `"model"` override, or `"procedural": "<kind>"` for bodies built in code like `sock_body.gd`, `blob_body.gd`, `loco_body.gd`). The Ice/Thunder/Dark Wizards' abilities live in `roster_kit.gd`. All other kits are `scripts/kits/kit_<id>.gd` built on `kit_part.gd`. Weapon holstering is `RosterWeapons.STOW`. Rigged models are under `models/<id>/`.

**Maps:** `world_builder.gd` builds the shared outdoor arena (Swamp and Forest: 440 m, terrain from `swamp_water.gd`, props). The other maps have their own builders (`castle_builder.gd`, `desert_builder.gd`, `graveyard_builder.gd`, `caldera_builder.gd`). Each map has a boss (`*_boss.gd`, shared rules in `map_boss.gd`). Beating it unlocks the next map and sometimes a character. Bosses that can be played use `playable_boss.gd` / `*_body.gd`.

**UI:** `hud.gd` builds all in-run UI in code. Most art (icons, portraits, many bodies and props) is procedural, made in GDScript and shaders, not image files.

**Translations:** player-visible text must be translatable. Labels translate themselves. Text built in code goes through `tr()`, or `I18n.t()` / `I18n.f()` in static functions. After adding strings, run `i18n_extract.py`, add translations in `data/i18n/src/`, then run `i18n_build.py` (it checks that placeholders, `{highlight}` and `[b]` tags survive).

## Adding content

- **Tome or stat item:** a JSON entry in `upgrades.json` with `per_level` modifiers.
- **Item with behaviour:** a JSON entry, then handle it in `item_effects.gd` through `Events`.
- **Weapon:** base stats in `BASE_STATS` (`main.gd`), a JSON entry, and a block in `weapon_system.gd`.
- **Enemy type:** `_add_type(...)` in `enemy_manager.gd`, weighted in `main.gd::_pick_type`.
- **Character:** an entry in `characters.json` (including an `fx` from `CharacterIcon.FX_KINDS`, or `test_character_select` fails), a kit in `abilities.json`, and to make it playable a `RosterHero.CFG` entry plus a `scripts/kits/` kit.
