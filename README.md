# Dark Republic

A 3D survivors-like roguelite prototype in **Godot 4.7 (GDScript)**: survive 10 minutes against escalating hordes, level up, and draft weapons, tomes and items, with movement tech (bunny hopping, sliding, air strafing) at the core.

## Run it

1. Install **Godot 4.7.x** (the standard build is fine; the .NET build is not required).
2. Open Godot → **Import** → select this folder's `project.godot`.
3. Press **F5**.

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / look | WASD + mouse | Left / right stick |
| Jump (buffered, coyote time) | Space | A |
| Slide | Shift, Ctrl or C | B / LB |
| Abilities: Meteor / Fire Shockwave / Inferno | 1 / 2 / 3 (or click the slot) | X / Y / RB |
| Pick level-up card | Mouse click | |
| Pause | Esc | Start |
| Restart (end screen) | R | Back |
| Debug overlay / spawn 200 enemies / reset cooldowns | F1 / F2 / F3 | |

**Movement tech:** jump on the frame you land to keep momentum (bhop), and strafe and turn in the air to gain speed. Slide while running for a burst; sliding down ramps accelerates you, and slide-jumping keeps the speed.

## The fire wizard

**Abilities** (bottom-center bar; the ultimate has a yellow outline):

| Key | Ability | Cooldown | Effect |
|---|---|---|---|
| 1 | Meteor | 30 s | Lands where you aim 3 s after casting: 250 dmg (scales with Damage) in 8 m, plus knockback |
| 2 | Fire Shockwave | 45 s | Ring of fire expands from the floor under you to 9 m: 80 dmg, knocks enemies back 5 yd |
| 3 | Inferno (ultimate) | 2 min | Ignites every enemy: 5% of max HP per second for 10 s. Burning enemies that die explode for 50% of their max HP within 2 yd (chains) |

**Look:** red coat made of animated flames, a pointy crimson hat with a gold band, ember eyes, a fire staff, and ash footprints that fade within a second.

**Collisions:** when an enemy touches you, you take its contact damage (shield first), become immune for 0.5 s (shown by dimming the character 50%), and you and the enemy are knocked apart. Enemies that run into you while you're immune bounce back opposite to the way they were heading.

**Epic enemies:** each spawn has a 5% chance (+1% per Tome of Luck level) to be epic: 1.5x size, 4x HP and a purple tint. Each epic drops one potion:

| Potion | Chance | Effect |
|---|---|---|
| Purple | 30% | Every ability's cooldown is reduced by 30% of its full duration |
| Red | 50% | Heal 10% of max HP |
| Blue | 20% | Shield worth 10% of max HP (absorbs damage first, stacks) |

## Goblins

Every enemy is a goblin: about half the wizard's height, pot-bellied, with stubby legs (they waddle) and comically large ears. Types differ by size and clothing: Goblin (brown), Goblin Scamp (small, fast, yellow), Goblin Brute (big, grey) and the Big Bonker boss (huge, dark red).

**Sounds** (`audio/goblin/`, generated in Higgsfield):
- Ambient: a random nearby goblin voices one of five clips every 0.8–2.2 s. Each clip has its own 5 s cooldown, so the same sound never repeats within 5 s. Bigger goblins are pitched lower.
- Collision: "Ow!" plays whenever a goblin runs into the player.
- To swap or add clips, edit `AMBIENT_CLIPS` / `COLLISION_CLIP` in `scripts/goblin_audio.gd`.

## What's in the slice

- **Run structure:** 10-minute run, spawn rate and enemy HP scale with time, a swarm ring every minute, and a boss (Big Bonker) at 5:00 whose death vacuums all XP.
- **3 weapons:** Bonk Orbs (auto-targeted, pierce), Stink Aura (damage field), Ground Slam (knockback nova). Max 3 weapons per run.
- **13 tomes** (stat upgrades) and **3 items** (explode on kill, heal on kill, extra jumps).
- **Rarity rolls** (Common → Legendary, x1–x3 effect) influenced by Luck.
- **Arena:** procedurally scattered platforms, ramps and pillars.

## Architecture

```
scripts/
  main.gd            run state, spawn director, fixed tick order, input map, smoke test
  player.gd          kinematic controller (Quake-style accel, bhop, slide, coyote/buffer), camera
  enemy_manager.gd   data-oriented crowd: packed arrays + MultiMesh + uniform grid
  weapon_system.gd   weapons + pooled projectiles (MultiMesh)
  gem_manager.gd     XP gems with magnet pickup (MultiMesh)
  item_effects.gd    event-driven item behaviours (on-kill hooks, queued explosions)
  upgrade_db.gd      loads data/upgrades.json, drafts weighted choices, applies modifiers
  stats.gd           stat pipeline: (base + flat) * (1 + add%) * mult
  events.gd          autoload event bus
  world_builder.gd   procedural arena, lighting, environment
  abilities.gd       Meteor, Fire Shockwave, Inferno; cooldowns and VFX
  wizard_model.gd    procedural fire wizard (flame-coat shader, hat, staff, dimming)
  potion_manager.gd  epic drops: purple / red / blue potions
  fx_manager.gd      pooled bursts and ash footprints (MultiMesh)
  ability_slot.gd    one ability-bar slot (procedural icon, cooldown, ult outline)
  goblin_mesh.gd     procedural goblin mesh + shader (clothing tint, burn, epic, hit flash)
  goblin_audio.gd    ambient goblin voices with per-clip cooldowns, collision sound
  hud.gd             all UI, built in code
data/upgrades.json   every weapon/tome/item and rarity, as data
tools/               headless micro-benchmarks
```

**Tick order (main.gd):** spawn → enemies (compact dead, rebuild grid, steer, separate, upload MultiMesh buffer) → weapons and items (query the grid) → gems → contact damage. Kills are flagged and swap-removed at the start of the next tick, so indices stay valid within a frame.

**Adding content:**
- **Tome or stat item:** add a JSON entry with `per_level` modifiers. The draft card text is generated from it.
- **Item with behaviour:** add a JSON entry with its stats, then handle it in `item_effects.gd` via `Events`.
- **Weapon:** add base stats to `BASE_STATS` in `main.gd`, a JSON entry, and a block in `weapon_system.gd`.
- **Enemy type:** call `_add_type(...)` in `enemy_manager.gd` and weight it in `main.gd::_pick_type`.

## Testing

```bash
# Full headless smoke test: bot plays, 1400-enemy stress phase, death screen, restart
godot --headless --path . --fixed-fps 60 -- --smoketest --smoke-seconds=240

# Gameplay spec tests (abilities, burn/explosions, epics, potions, shield, immunity)
godot --headless --path . res://tools/test_abilities.tscn

# Screenshot: cast Meteor at 1 s, capture at 4 s
godot --path . -- --shot=/tmp/shot.png --shot-at=4 --shot-cast=0@1 --shot-spawn=120

# Crowd simulation benchmark
godot --headless --path . res://tools/bench_enemies.tscn
```

Measured on a 2-vCPU cloud VM, simulation only: about 1.6 ms at 500 enemies, 3.2 ms at 1,000, and 4.8 ms at 1,400. Real gameplay hits roughly 750 enemies around the 5-minute mark at about 2 ms.

## Known limitations and next steps

- Enemies walk *through* platforms (they only collide with each other). A flow field over a coarse nav grid would fix that and also scale better.
- The crowd sim is GDScript. Porting `EnemyManager.tick` to C# or a GDExtension is the path to 5,000+ enemies.
- There's no meta-progression, character select, chests, shrines, audio or damage numbers yet.
- Placeholder art: primitives plus a checker ground.
