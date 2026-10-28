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
| Abilities: Inferno / Fire Nova / Meteor (ultimate) | 1 / 2 / 3 (or click the slot) | X / Y / RB |
| Pick level-up card | Mouse click | |
| Pause | Esc | Start |
| Restart (end screen) | R | Back |
| Inspect abilities (pauses; hover a slot for details) | Hold Alt | |
| Debug overlay / spawn 200 enemies / reset cooldowns | F1 / F2 / F3 | |

**Movement tech:** jump on the frame you land to keep momentum (bhop), and strafe and turn in the air to gain speed. Slide while running for a burst; sliding down ramps accelerates you, and slide-jumping keeps the speed.

## Startup

The game opens with the **AtomAI** studio logo (`video/atomai_logo.ogv`, converted to Ogg Theora for Godot). Any key, click or gamepad button skips it. Pass `-- --skip-intro` to skip it from the command line (tests and screenshots skip it automatically).

Then the **title screen**: a living swamp diorama at night. The camera slowly orbits the fire wizard on a mossy stone dais while goblin silhouettes with glowing eyes lurk, creep in and grunt in the fog. "DARK REPUBLIC" burns in Cinzel lettering (`fonts/Cinzel.ttf`, SIL Open Font License) over a Play / Characters / Settings / Quit menu (mouse, keyboard or gamepad). The pause menu and end screen have **Main menu** to return here.

## Character select

**Characters** on the title opens a roster of 25 champions plus 5 mystery slots (shown only as "?"): a 6-wide grid of portraits plus a preview panel with name, epithet, bio and kit. Only **The Fire Wizard** is playable for now; he previews as his live 3D model, and Play starts a run. The other 22 (Ice Wizard, Merlin, Thunder Wizard, Dark Wizard, Ogre, Ghast, Vampire Hunter, Vicki, The Rogue, Gaiden, Dr. Croc, The Arachnid, Blob, Death, Billy Bulldog, Cowboy, Loco Robotico, Singe, An Argyle Sock, Sentient Platypus, Kong, Thog the Troll, Bog Witch, Toadstool Knight) show a padlock and a large portrait. Portraits are drawn in code (`character_icon.gd`) from each character's traits in `data/characters.json` (body, head, headgear, beard/hair, eyes, signature item, particle motif), so adding a character is a JSON entry. **Unlocking with coins:** each locked tile shows its price: 2,000 for the Ice, Thunder and Dark Wizards, 7,000 for Merlin and 10,000 for everyone else. Selecting a locked character turns Play into **Unlock**, which spends the coins. Bought characters get their skill tree and level straight away. Only characters with a model and abilities can be played, which so far is just the Fire Wizard, so others show "playable soon" until they're built.

Each character has a saved level (`lvl`, kept with the coins in `user://progress.cfg`). Tiles show **lvl N** in the bottom-left corner when it's 1 or more, and nothing at 0. Mouse, keyboard and gamepad all work; Esc goes back.

## Character kits

Every character has a designed kit in `data/abilities.json`: a starting weapon plus three abilities on the same keys and unlock levels as the Fire Wizard (**1** from the start, **2** at run level 5, **3** the ultimate at level 10). Cooldowns and numbers are balanced against his kit (about 30 s / 45 s / 2 min; 80-160 damage for the level-5 ability, 200-400 for ultimates).

**On the select screen**, every character shows its weapon and its three ability squares. Hover one for the full description with cooldown and numbers (`KitDB.describe_lines`; `{braces}` in the JSON mark highlighted numbers). Icons are drawn in code by `scripts/ability_glyphs.gd` from each ability's `"icon": {"glyph", "color"}` (36 glyphs). To preview them all: `godot --path . --script res://tools/render_ability_icons.gd -- /out.png`.

**In runs**, only the Fire Wizard's kit is implemented so far (`abilities.gd`); the others are designs until each character is built.

| Character | Role | Weapon | 1 | 2 (Lv 5) | 3 Ultimate (Lv 10) |
|---|---|---|---|---|---|
| Ice Wizard | Crowd control: slows, freezes and shatters | Frost Shards | Flash Freeze | Glacial Path | Absolute Zero |
| Merlin | Control mage who bends time | Arcane Bolts | Time Warp | Polymorph | Rewind |
| Thunder Wizard | Fast, mobile chain-lightning caster | Chain Lightning | Overcharge | Thunderclap | Storm Lord |
| Dark Wizard | Life-drain and undead summoner | Shadow Bolts | Siphon | Raise Dead | Eclipse |
| Ogre | Close-range bruiser with huge cleaves | Tree Trunk | Bellow | Belly Flop | Swamp Rage |
| Ghast | Untouchable spirit that terrifies the horde | Wail | Phase | Haunt | Banshee Scream |
| Vampire Hunter | Precise ranged hunter, deadly to big targets | Silver Bolts | Holy Water | Stake Volley | Hunter's Night |
| Vicki | Aerial lancer who dives on the horde | Valkyrie Spear | Shield Wall | Wings of Valhalla | Ride of the Valkyries |
| The Rogue | Evasive striker with bleeds and bursts | Twin Daggers | Smoke Bomb | Pickpocket | Death by a Thousand Cuts |
| Gaiden | Teleporting ninja duelist | Katana | Shadow Step | Shuriken Storm | Reed Clones |
| Dr. Croc | Alchemist who melts goblins with acid | Volatile Flasks | Mutagen | Death Roll | Toxic Spill |
| The Arachnid | Trapper who poisons and cocoons | Venom Spit | Web Trap | Brood | Cocoon |
| Blob | Tanky puddle that eats goblins | Acid Body | Engulf | Split | The Great Puddle |
| Death | Executioner who reaps the weak | Scythe Sweep | Harvest | Mark of the Inevitable | Overtime |
| Billy Bulldog | Scrappy melee dog with taunts and stuns | Bite | Fetch! | Zoomies | Who's a Good Boy |
| Cowboy | Gunslinger with bursts of precise damage | Six-Shooter | Lasso | Dynamite | High Noon |
| Loco Robotico | Party robot that stuns crowds, then lasers them | Maraca Blasters | Party Mode | Piñata Drop | DESTROY Mode |
| Singe | Fast fire imp who sets the ground ablaze | Cinder Toss | Hotfoot | Flashover | Supernova |
| An Argyle Sock | Odd little whirlwind with static shocks | Static Cling | Spin Cycle | Lost Pair | Laundry Day |
| Sentient Platypus | Poison-kicking scholar with sleep and eggs | Venom Spur | Electro-Bill | Egg Clutch | The Lecture |
| Bog Witch | Hexer who curses and drowns the horde | Ladle of Bile | Bubbling Cauldron | Hex of Silence | Swamp's Fury |
| Toadstool Knight | Brave little defender with spores and summons | Spore Blade | Fungal Shield | Fairy Ring | The Fungus Court |
| Kong | Brawler who throws the swamp at goblins | Shackle Swing | Chest Pound | Log Toss | Rampage |
| Thog the Troll | Slow, heavy smasher who controls space | Big Club | Toll Booth | Goat Charge | Bridge Collapse |

## Character levels and skills

**EXP and levels.** Each character earns **1 EXP per kill**, banked when the run ends and shown on the summary with any level-up. The level (`lvl`, shown on the character select tile) comes from total EXP:

| lvl | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 (max) |
|---|---|---|---|---|---|---|---|---|---|---|
| EXP | 2,000 | 10,000 | 50,000 | 1M | 5M | 15M | 50M | 100M | 500M | 1B |

**Skills.** Playable characters have a **Skills** button between Back and Play. It opens the character's tree (`skill_tree.gd`, `skill_screen.gd`):
- **Layout:** three columns, Defense, Offense and Special, each with two rows of three skill squares.
- **Points:** every level gives one **skill point**, and each skill costs one. The top right shows **lvl/10** with how many points are left to spend.
- **Unlock rules:** a column's second row opens once you've learned any skill in its first row. **Special** is greyed out under a big padlock reading "Unlocks at level 5" until the character reaches level 5.
- **In runs:** learned skills apply to every run with that character. They cover max HP, armor, regen, a starting shield, damage, attack speed, fireball count and pierce, area, move speed, air jumps, pickup range, luck, XP, faster ability recharge and bonus coins.
- **Which skills:** the Fire Wizard has a hand-made fire-themed tree. Every other character gets its own fixed random draw from a shared pool.

## Coins

Coins are saved between sessions (`user://progress.cfg`, autoload `Wallet`), and the counter is always in the top-right corner: title, character select, in-game, pause and the end screen. A run earns **1 coin per second survived** plus **100 coins per 1,000 kills**, but they're only banked on the end-of-run summary.
- **The tally:** the summary lists the time and kill-bonus coins with the total pot.
- **The payout:** coins pour out from the middle of the screen and jump to the counter, disappearing into it. The pot counts down and the counter counts up as they land.
- **Sound:** a casino jingle plays throughout, then a ka-ching when the last coin lands. Both sounds are synthesized by `tools/gen_coin_sounds.py`.

Quitting a run from the pause menu forfeits its coins.

## Pause menu and settings

**Esc** opens the pause menu: Resume, Settings, Restart run, Quit to desktop. Settings are saved to `user://settings.cfg` and applied on startup.

- **Video:** display mode (windowed / fullscreen / borderless), VSync, render scale, field of view, FPS limit, show FPS.
- **Sound:** Music volume and All other audio volume (goblin voices, hits, effects), each with its own Mute checkbox. They use separate audio buses, `Music` and `SFX`.
- **Controls:** mouse sensitivity, invert Y, and rebindable keys for movement, jump, slide, the three abilities and pause (click a key, press the new one; Esc cancels).

## The fire wizard

**Model and animation.** The wizard is a rigged, textured 3D model generated with Higgsfield (Meshy image-to-3D, auto-rigged) from a concept image: `models/wizard/wizard.glb`. Nine animation clips (idle, walk, run, jump, hit reaction, fireball cast, Fire Nova slam, Inferno cast, Meteor cast) were generated on the same rig and merged into `models/wizard/wizard_anims.res` by `tools/import_wizard_anims.gd`. `hero_model.gd` drives them with an AnimationTree:
- **Movement:** idle, walk and run blend by ground speed.
- **Upper-body layers:** the fireball staff thrust, the hit flinch and the Inferno cast play on the spine and arms only, so the legs keep running.
- **Full-body layers:** jump, the Fire Nova ground slam, and the Meteor overhead slam he does just before vanishing.
- **Aiming:** a spine twist turns his torso toward each fireball's target.
- **Staff:** built in code and attached to his right-hand bone. A burning coal sits in its crown under a shader-drawn flame (`staff_flame.gd`): layered noise tongues, a white-hot core and wisps, with a flickering light. The flame stays upright and trails behind as the staff moves. Fireballs leave from the flame.

To add a clip: generate it on the same rig in Higgsfield, then run `godot --headless --path . --script res://tools/import_wizard_anims.gd -- <folder with the .glb>`. Add the Meshy action name to `NAMES` in that script first.

**Abilities** (bottom-center bar; the ultimate, Meteor, has a yellow outline). Inferno is available from the start, Fire Nova unlocks at **level 5** and Meteor at **level 10**; locked slots show a padlock. Ready abilities pulse (brighter and slightly bigger, then back). **Hold Alt** to pause and hover a slot for a description with its current damage numbers.

| Key | Ability | Cooldown | Effect |
|---|---|---|---|
| 1 | Inferno | 30 s | Ignites every goblin: 5% of max HP per second for 10 s. Burning goblins that die explode for 50% of their max HP within 2 yd (chains) |
| 2 | Fire Nova | 45 s | Ring of fire expands from the floor under you to 18 m: 80 dmg, knocks enemies back 5 yd |
| 3 | **Meteor (ultimate)** | 2 min | Trees and fallen trees in the blast catch fire and burn for 15 s, leaving them charred black. The wizard vanishes (invulnerable, untouchable) and becomes a giant flaming copy of his own head, which crashes where you aim 3 s later: 250 dmg (scales with Damage) in 8 m plus knockback. He reappears at the crash site, and the ground burns for 3 s, dealing 3% of max HP per second to goblins in a 7 m radius |

**Attacks:** his starting weapon hurls **Fireballs**. Each time it fires, he swings his staff down at the target and the fireballs launch from the staff tip.

**Look:** red coat made of animated flames whose back trails along the ground as a train, a two-handed grip on his fire staff, a wrinkled, grimy crimson hat with a wavy brim and a tip that flops to the right, a tarnished gold band, ember eyes, a fire staff, and ash footprints that fade within a second.

**Collisions:** when an enemy touches you, you take its contact damage (shield first), become immune for 0.5 s (shown by dimming the character 50%), and you and the enemy are knocked apart. Enemies that run into you while you're immune bounce back opposite to the way they were heading.

**Epic enemies:** each spawn has a 5% chance (+1% per Tome of Luck level) to be epic: 1.5x size, 4x HP and a purple tint. Each epic drops one potion:

| Potion | Chance | Effect |
|---|---|---|
| Purple | 30% | Every ability's cooldown is reduced by 30% of its full duration ("-Ns" pops up above each ability that was cooling down) |
| Red | 50% | Heal 10% of max HP (a red "+N" pops up next to the health bar and above the wizard) |
| Blue | 20% | Shield worth 10% of max HP (absorbs damage first, stacks) |

Potions lean and spin slowly so they're easy to spot, last 45 s, and blink every 0.3 s during their final 5 s.

**Power-ups:** each elite kill also has a 2% chance (+1% per Tome of Luck level) to drop one of:

| Power-up | Effect |
|---|---|
| Magnet | Every XP orb on the map flies to you |
| Fear Idol | All goblins run away from you for 15 s |
| 5x Damage | All damage you deal is multiplied by 5 for 10 s |
| Movement Enhancer | +80% move speed for 15 s |

Picking one up while it's active refreshes its timer; active power-ups and their timers show under the run timer.

## The swamp

Every run generates a new dark swamp (`scripts/world_builder.gd`):

- **Sky:** 50% chance of a gloomy day with the sun glowing through dense clouds, 50% chance of a moonlit night with very few clouds and stars. Lighting, ambient light and fog follow.
- **Size:** 440 × 440 m (`ARENA_HALF = 220` in `scripts/main.gd`), with stone walls round the edge.
- **Terrain:** rolling hills, dips and slopes from two layers of smooth noise: broad hills of up to about ±6.5 m and smaller rolls on top. Every slope stays walkable (under 40°). The start point, every pool and every shrine sit on level pads that ramp gently back into the hills. Near the walls the ground climbs into a berm about 7 m high. Everything follows the ground: goblins, drops, trees, grass and the flat ability markers. The Meteor target, Fire Nova's ring and glow, and the Stink Aura are `GroundDisc`s that drape over the slopes. The terrain is baked into a 1 m height grid (`SwampWater.build_terrain`) that collision, the ground mesh and gameplay all share. To tune it, change `HILL_HEIGHT`, `HILL_FREQ`, `BUMP_HEIGHT` and `EDGE_RISE` in `scripts/swamp_water.gd`.
- **Ground:** random patches of wet mud and swamp grass, with swaying grass tufts.
- **180 swamp trees** in 4 variants: bald cypress (flared trunk, knees, hanging moss), dead snag, swamp willow (drooping curtains) and mangrove (stilt roots). All collide with the player.
- **72 fallen trees:** mossy logs with root plates, slightly tilted, which you can climb and jump off.
- **14 pools of swamp water:** irregular shapes up to 10 yd across, recessed into the ground with uneven beds, never deeper than the character. Reeds and cattails grow around the edges. **In water, move speed and jump height are halved** (goblins wade at half speed too).
- **24 mossy stone ruins** as landmarks.
- **Camera zoom:** the mouse wheel zooms the camera in and out (up to 16 m away). All the way in is first person: the camera sits at the wizard's eyes and he's hidden from view, though his shadow stays. The chosen distance is kept between runs (`Player.zoom`).
- **Entrance:** each run opens with the wizard arriving as his own Meteor. For the 3 s it takes to fall, the clock, the spawns and the goblins all hold still and nobody can act. It lands with the full impact (sound and explosion, no scorched ground), and the run starts (`Abilities.entrance_meteor`, `main.intro`). Screenshot and smoke runs skip it unless you pass `--shot-intro`.
- **Start banner:** "SURVIVE 10 MINUTES" slams into the middle of the screen as the wizard lands in blood-red letters with a black outline and dripping blood, then fades (`scripts/blood_banner.gd`).
- **Music:** "Tension Drop" (`audio/music/tension_drop.mp3`) starts with the level and loops until the run ends, then fades out. Change `SWAMP_MUSIC` / `MUSIC_VOLUME_DB` in `scripts/main.gd`.
- **Ability sounds:** Inferno and Fire Nova play their sound on the key press and take effect 1 s later (`INFERNO_DELAY`, `NOVA_DELAY`). Meteor plays its sound on the cast and an explosion when it lands. The explosion is synthesised by `tools/gen_explosion_sound.py`. All of them are in `audio/abilities/` and use the SFX bus.
- **Menu music:** "Menu of Shadows" (`audio/music/menu_of_shadows.mp3`) loops on the title and character select screens. The `MenuMusic` autoload (`scripts/menu_music.gd`) plays it, so it carries on without restarting between the two screens and fades out when a run starts.
- **Level-up cards:** each card has a big icon as its centrepiece: tomes are books, weapons are bronze medallions and items are silver charms. The name sits under the icon, and the effect is in its own dark box. The card is outlined thickly in its rarity colour (grey, blue, purple or gold). Icons are set in `data/upgrades.json` (`"icon": {"glyph", "cover", "tint"}`) and drawn by `scripts/upgrade_icon.gd`. To preview all of them, run `godot --path . --script res://tools/render_upgrade_icons.gd -- /out.png`.
- **Character select abilities:** the selected character's three abilities appear as the same squares as the in-run ability bar. Hover one for what it does, its cooldown and the run level it unlocks at (`Abilities.describe_lines`).

## Shrines

Each run places **1-8 shrines** on open ground, each marked by a tall beam of light in its tier colour. Stand inside the glowing **10-yard zone** for **10 seconds** to complete it (the ring fills up; leaving the zone resets the timer to 0) while dodging its damage pattern. Completing a shrine spawns a chest: **Difficulty 1 → Bronze, 2 → Silver, 3 → Gold** (chest rewards are placeholders for now).

| Pattern | Difficulty 1 | Difficulty 2 | Difficulty 3 |
|---|---|---|---|
| **Chain Shrine:** chains reaching the zone edge swing around the shrine at shin height (jump over them) | 1 plain chain (hit: 10% max HP) | 2 burning chains | 3 burning chains, and the shrine itself is on fire |
| **Storm Shrine:** rings of crackling lightning, floating a little off the ground, spread out to the zone edge (jump over them; hit: 8% max HP) | 1 ring every 2 s | 2 rings 0.5 s apart every 2 s | 1 ring every 1.5 s |

**Shrine hits work like enemy hits:** you're knocked back and get 0.5 s of immunity to all shrine damage, burning chains included.

**Burn** (burning chains / burning shrine): 5% of max HP per second for 2 s. Touching fire again restarts the 2 s but never stacks.

## Goblins

Every enemy is a goblin (contact damage was doubled: 16 / 12 / 32, boss 70): about half the wizard's height. The model is a textured, rigged Higgsfield/Meshy goblin (`models/goblin/`): hunched, warty, with big ears and clawed hands. Types differ by size and colour grade: Goblin, Goblin Scamp (small, fast, yellowish), Goblin Brute (big, grey) and the Goblin Warlord boss (huge, dark red).

**Animation:** goblins charge head-down (run cycle speed matched to their ground speed) and throw punch combos when they reach the wizard. The crowd can reach 1,400, so instead of skeletons the clips are **baked into vertex-animation textures** (`tools/bake_vat.gd`). The goblin shader (`vat_crowd.gd`) replays them per instance from the MultiMesh, with each goblin's clip and phase in its instance colour. That keeps the whole crowd in one draw call.

**Death:** killed goblins play a fall-backwards death animation, lie on the ground (charred if they died burning), then sink away 3 s after death.

**Sounds:** goblins are silent while alive, with no voices or grunts. When one dies within 30 m, a short "splat-pop" plays from where it fell. There are 4 variants, and bigger goblins sound deeper. Death sounds are limited to about 20 per second, so mass kills sound like a crunchy volley. The clips (`audio/goblin/death_*.wav`) are synthesised by `tools/gen_goblin_death_sounds.py`, and the player is `scripts/goblin_audio.gd`.

## Combat feedback

- **Health bars** over every goblin (green → yellow → red; purple border on epics), hidden beyond 45 m.
- **Damage numbers** for every hit: they pop in small, swell big, settle, then float up and fade, all within 0.75 s. Burn damage is totalled and shown in orange twice a second.

## What's in the slice

- **Run structure:** 10-minute run, spawn rate and enemy HP scale with time, a swarm ring every minute, and a boss (the Goblin Warlord) at 5:00 whose death vacuums all XP.
- **3 weapons:** Fireballs (auto-targeted, pierce), Stink Aura (damage field), Ground Slam (knockback nova). Max 3 weapons per run.
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
  abilities.gd       Meteor, Fire Nova, Inferno; cooldowns and VFX
  hero_model.gd      rigged fire wizard: AnimationTree layers, staff, dimming, hit flash
  spine_twist.gd     SkeletonModifier3D that turns the torso toward a fireball's target
  wizard_model.gd    old procedural wizard (its head is still the giant Meteor head)
  potion_manager.gd  epic drops: purple / red / blue potions
  fx_manager.gd      pooled bursts and ash footprints (MultiMesh)
  ability_slot.gd    one ability-bar slot (procedural icon, cooldown, ult outline)
  ability_glyphs.gd  procedural icons for the roster kits' abilities
  kit_db.gd          loads data/abilities.json: every character's weapon + 3 abilities, tooltips
  vat_crowd.gd       baked vertex-animation playback for the goblin crowd (clip/phase per instance, tint, burn, epic, hit flash)
  goblin_mesh.gd     old procedural goblin (unused)
  goblin_audio.gd    goblin death sounds (rate-limited, positional)
  swamp_props.gd     procedural swamp trees (4 variants), fallen trees, ruins
  swamp_water.gd     terrain (hills, pads, berm, height grid) + recessed pools: outline, bed, water shader, collision, slow zones
  ground_disc.gd     flat markers that drape over the hills (vertex shader samples the height texture)
  mesh_builder.gd    merges primitives into vertex-colored meshes with wind sway
  damage_numbers.gd  pooled pop-and-fade damage numbers
  corpse_manager.gd  fallen goblins (topple, linger, sink) in one MultiMesh
  settings.gd        autoload: audio buses, video/controls options, key remaps, save/load
  settings_menu.gd   Video / Sound / Controls settings screen
  shrine.gd          shrine challenge: zone timer, chain + storm patterns, completion
  shrine_manager.gd  places 1-8 shrines per run, spawns chests
  chest.gd           Bronze / Silver / Gold chest (placeholder: rewards TBD)
  powerup_manager.gd elite power-up drops and timed effects
  tree_fire.gd       trees set alight by the Meteor, charring over 15 s
  splash.gd          startup logo video, skippable
  title.gd           title screen: swamp diorama, burning title, menu
  character_select.gd  roster grid + preview panel (data/characters.json)
  character_icon.gd  procedural character portraits
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

# Swamp tests (pool size/depth, recessed collision, 50% speed and jump in water)
godot --headless --path . --fixed-fps 60 res://tools/test_swamp.tscn

# Pause menu / settings tests (tabs, independent music + SFX volume and mute, saving, rebinding)
godot --headless --path . res://tools/test_settings.tscn

# Shrine tests (placement, zone timer/reset, chest tiers, chains, burn, storm rings, jumping)
godot --headless --path . --fixed-fps 60 res://tools/test_shrines.tscn

# Title flow (splash -> title -> settings -> play -> main menu)
godot --headless --path . res://tools/test_title.tscn

# Character select (roster data, locked/unlocked, preview, back, play)
godot --headless --path . res://tools/test_character_select.tscn

# Re-bake the goblin animations from Higgsfield GLBs
godot --headless --path . --script res://tools/bake_vat.gd -- <glb dir> res://models/goblin "run=Male_Head_Down_Charge:16:loop,attack=Punch_Combo:50:loop,death=Shot_and_Fall_Backward:40:hold"

# Skill trees (structure, learning rules, effects in a run, character select Skills screen)
godot --headless --path . res://tools/test_skills.tscn

# Coins (reward maths, banked only at the end, payout animation, counter on every screen)
godot --headless --path . res://tools/test_wallet.tscn

# Crowd simulation benchmark
godot --headless --path . res://tools/bench_enemies.tscn
```

Measured on a 2-vCPU cloud VM, simulation only: about 1.6 ms at 500 enemies, 3.2 ms at 1,000, and 4.8 ms at 1,400. Real gameplay hits roughly 750 enemies around the 5-minute mark at about 2 ms.

## Known limitations and next steps

- Goblins walk *through* trees and logs (they only collide with each other and wade through water). A flow field over a coarse nav grid would fix that and also scale better.
- The crowd sim is GDScript. Porting `EnemyManager.tick` to C# or a GDExtension is the path to 5,000+ enemies.
- There's no meta-progression, character select, chests, shrines, audio or damage numbers yet.
- All art is procedural (built from primitives in code).
