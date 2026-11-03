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
| Sprint (hold) | Shift | Left stick click |
| Slide | Ctrl or C | B / LB |
| Abilities: Inferno / Fire Nova / Meteor (ultimate) | 1 / 2 / 3 (or click the slot) | X / Y / RB |
| Pick level-up card | Mouse click | |
| Pause | Esc | Start |
| Restart (end screen) | R | Back |
| Inspect (pauses; hover an ability or one of your upgrades for details) | Hold Alt | |
| Activate: open a chest (with its key), take a power-up | E ("Press E" shows over them) | D-pad up |
| Debug overlay / spawn 200 enemies / reset cooldowns | F1 / F2 / F3 | |

**Sprint and stamina:** hold Sprint while moving on the ground to run 40% faster. It drains stamina (full lasts 4 s); stop sprinting and it starts refilling after 0.7 s (full again in about 4.5 s). Run it dry and you're **winded**: no sprint until it's back to 30%. The thin yellow-green **STAMINA** bar under your health shows it live (brighter while sprinting, flashing orange while winded, dimmed when full). `Player.STAMINA_*`, `hud._update_stamina`.

**Movement tech:** jump on the frame you land to keep momentum (bhop), and strafe and turn in the air to gain speed. Slide while running for a burst; sliding down ramps accelerates you, and slide-jumping keeps the speed.

## Startup

The game opens with the **AtomAI** studio logo (`video/atomai_logo.ogv`, converted to Ogg Theora for Godot), then the **anime intro** (`video/intro_anime.ogv`, played by `scenes/intro.tscn` / `scripts/intro.gd`, about 30 s, sound effects on the SFX bus). Made with Higgsfield from the game's own character models: the Fire Wizard, Ogre, Vicki, Gaiden and Dr. Croc are asleep in the castle barracks when a stampede shakes the walls; the wizard whistles everyone awake, they rush to the battlements, see Thog the Troll leading the goblin horde, leap into battle, and the wizard ends it as the Meteor. Any key, click or gamepad button skips the logo and the intro. The intro plays on the **first launch only**: once shown it switches **Settings > Gameplay > Play intro on startup** off, and turning that back on replays it next launch. Pass `-- --skip-intro` to go straight to the title (tests and screenshots skip both automatically).

Then the **title screen**: a living swamp diorama at night. The camera slowly orbits the fire wizard on a mossy stone dais while goblin silhouettes with glowing eyes lurk, creep in and grunt in the fog. "DARK REPUBLIC" burns in Cinzel lettering (`fonts/Cinzel.ttf`, SIL Open Font License) over a Play / Settings / Quit menu (mouse, keyboard or gamepad). The pause menu and end screen have **Main menu** to return here, and the end screen also has **Characters** to go straight back to character select.

**Play** opens the mode menu (`scripts/mode_menu.gd`). A burning fuse races out of the button and three cards (Classic, Quickplay, Unrelenting) drop in behind it, each with a flip, a flash and a puff of embers, plus a whoosh-and-thump sound (`audio/ui/menu_reveal.wav`). Esc folds them back.
- **Classic:** character select, then the map. Survive 10 minutes.
- **Quickplay:** a random unlocked, playable character on a random map open to them, straight into the run. There are no difficulty settings yet; when there are, Quickplay will pick the hardest one unlocked.
- **Unrelenting:** character select (tagged UNRELENTING), then the map, with these rules:
  - No time limit; the clock counts up and spawns never stop.
  - Upgrades have no level cap.
  - Past 10:00, enemy contact damage rises 12% per minute and XP drops shrink (1 / (1 + 0.06 per minute)), on top of the usual HP and spawn-rate ramp.
  - Beating Thog doesn't end the run.
  - Lasting **15:00 in the Swamp** earns the feat Ghast needs to be unlocked (`Wallet.feats`).

**Weapon names on cards:** the Ice, Thunder and Dark Wizards' starting weapon shows its own name everywhere, including its stat lines on level-up cards (e.g. "+20% Frost Shards Damage"; `WeaponSystem.retheme_card`). "Fireballs" only appears for the Fire Wizard, or as his signature weapon when it turns up as a legendary reward. The key bindings say Ability 1 / Ability 2 / Ultimate, since every character's abilities differ.

**Run clock:** in Classic it counts **down** from 10:00. During the entrance it spins up from 00:00 to 10:00 with digital blips that rise in pitch (`audio/ui/timer_tick.wav`), then locks in with two beeps (`timer_set.wav`), and a **SURVIVE** banner appears and starts counting down when you land.

## Loading screen

Every scene change goes through one autoload, `Loader` (`scripts/loader.gd`): `Loader.go(path)` replaces `change_scene_to_file` everywhere (title, character select / map picker, Quickplay, the end screen's Restart, **Characters** and Main menu buttons, the pause menu's Restart run and Main menu, the logo and intro into the title).
- **When it shows:** straight away for transitions known to be slow (into a run, which builds the whole map; into the title, which builds its swamp diorama; leaving a run; any scene that took over 1 s last time). Anything else only shows it if the background load is still going after 0.25 s, so quick changes never flash it. Once up it stays at least 0.8 s, fades in over 0.15 s and out over 0.3 s.
- **How:** the scene loads on a background thread (`ResourceLoader.load_threaded_request`) while the overlay animates; it's drawn before the scene swap, stays up while the new scene builds in `_ready` (the map builders run synchronously, so it freezes but never shows a black screen) and for 3 more frames, then fades out.
- **What's on it** (a CanvasLayer at layer 128, above the coin counter): into a run, the map's preview picture (`images/maps/<map>.png`, blurred and dimmed) under its name in Cinzel and the character's name; a spinning circle of runes with an ember arc, drifting embers and a dark vignette; and a **TIP** box at the bottom.
- **Tips:** 32 of them in `data/tips.json` (a plain array of strings; edit freely): shards and the Forge, abilities and cooldowns, chests, keys and the slot machine, potions and power-ups, Luck, bans, coins, bosses and their ultimates, map and champion unlocks, skill trees, burning woods, movement tech and Unrelenting. They rotate every 4.5 s with a crossfade in shuffled order (every tip before any repeats, never the same twice in a row); any key, click or pad button skips to the next. They're translated like everything else (`tools/i18n_extract.py` reads `tips.json`; translations in `data/i18n/src/tips.json`).
- **Tests:** `godot --headless --path . res://tools/test_loading.tscn`. Screenshot: `xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . res://tools/shot_loading.tscn -- --out=/tmp/load.png [--map=forest] [--char=ice_wizard] [--to=title] [--lang=es]` (`Loader.hold`, or `-- --loader-hold` in a normal session, keeps the overlay up).

## Character select

**Play** on the title opens a roster of 30 slots: 25 champions, the map bosses who have joined them (the Pharaoh and the Necromancer; locked behind their own defeats, then playable once bought) and the mystery slots still left (shown only as "?"): a 6-wide grid of portraits plus a preview panel with name, epithet, bio and kit. **The Fire Wizard** plays from the start; the **Ice, Thunder and Dark Wizards** are playable once bought. Characters with a model preview as it in 3D, and Play starts a run. The other 22 (Ice Wizard, Merlin, Thunder Wizard, Dark Wizard, Ogre, Ghast, Vampire Hunter, Vicki, The Rogue, Gaiden, Dr. Croc, The Arachnid, Blob, Death, Billy Bulldog, Cowboy, Loco Robotico, Singe, An Argyle Sock, Sentient Platypus, Kong, Thog the Troll, Bog Witch, Toadstool Knight) show a padlock and a large portrait. Portraits are drawn in code (`character_icon.gd`) from each character's traits in `data/characters.json` (body, head, headgear, beard/hair, eyes, signature item, particle motif), so adding a character is a JSON entry. **Every portrait has a particle motif of its own** that moves while its tile is hovered or selected (embers, snow, drifting stars, sparks, shadow, wisps, bubbles, spores, sand, bog flies, bats, feathers, tumbling coins, petals, spiders on threads, paw prints, dust, purple static, ripples, leaves, rain): a new character picks one of `CharacterIcon.FX_KINDS` for its `"fx"` (or a new one is added there), and `test_character_select` fails if any character has none. A missing one falls back to soft motes in the portrait's colours. **Unlocking with coins:** each locked tile shows its price: 2,000 for the Ice, Thunder and Dark Wizards, 7,000 for Merlin and 10,000 for everyone else. Selecting a locked character shows its unlock requirements as chips with a tick or a cross under "LOCKED · to unlock:" (coins for everyone; **Thog the Troll** also needs beating him in the Swamp, **Singe** beating him in the Ashen Caldera, and the **Ghast** needs 15:00 in the Swamp on Unrelenting), and turns Play into **Unlock**, which works once every requirement is met and spends the coins. Bought characters get their skill tree and level straight away. Only characters with a model and abilities can be played: the four wizards, Merlin, Ogre, Ghast, Vampire Hunter, Vicki, the Rogue, Gaiden, Dr. Croc, Thog (on the Ogre's model for now), An Argyle Sock, Loco Robotico, the Blob, the Arachnid, the Toadstool Knight, the Pharaoh, the Necromancer and Singe (the last eight built in code; the Arachnid also needs beating her in the Castle, and can't pick the Castle; the Toadstool Knight needs beating him in the Magical Forest, and can't pick the Forest; the Pharaoh, the Necromancer and Singe need beating them on their maps, the Desert, the Graveyard and the Ashen Caldera, and can't pick those). The rest show "playable soon" until they're built.

The preview panel shows the character's level (**LVL N**, LVL 0 for characters still locked, bosses included) in its top-left corner with the EXP towards the next level and a thin bar under it, then the character's **starting bonuses** (see **Character bonuses**), and the signature weapon's icon and name in the top-right corner; hover the weapon for its damage, attack rate and what it does. Ability names live in the hover tooltips. Each character has a saved level (`lvl`, kept with the coins in `user://progress.cfg`). Tiles show **lvl N** in the bottom-left corner when it's 1 or more, and nothing at 0. Mouse, keyboard and gamepad all work; Esc goes back.

## Character bonuses

Every character with a roster card starts each run with three stat bonuses of its own (`"bonuses"` in `data/characters.json`, applied by `scripts/char_bonuses.gd` at run start, after the skill tree). Each is `{"stat", "value", "mode"}`: `mult` multiplies the stat (Move Speed x1.2), `set` replaces its starting value (Critical Hit Chance 6% instead of 3%), `flat` adds to it (for stats that start at 0: Armor +5). **Jump Height** is a stat too (`jump_height`, 1.0 in `BASE_STATS`): the jump's apex scales by it (the take-off speed by its square root).

**On the select screen** they sit under the level, left of the character, as **STARTING BONUSES**: stat name, value, and a bar (shown for locked characters too, so you can see what you'd get). The bar's length is the size of the boost (full at 2x) and its colour the tier:
- **Red, small:** under 1.3x.
- **Yellow, medium:** 1.3x to 1.5x.
- **Green, big:** 1.5x and up.

A boost is measured against the stat's base: x1.2 is 1.2x, crit 6% against 3% is 2x, and Ability Cooldown -20% is 1.25x (shorter is better). For stats that start at 0, a flat bonus counts against a reference amount: Armor 10, HP Regen 1/s, Luck 25%, Extra Jumps 1.5 (so Armor +5 is 1.5x, big). Each character has one signature (big) bonus and two smaller ones; Gaiden's three are exactly as requested (crit 6%, move speed x1.2, jump height x1.6).

| Character | Bonus 1 | Bonus 2 | Bonus 3 |
|---|---|---|---|
| The Fire Wizard | Area x1.5 (big) | Attack Speed x1.2 (small) | Projectile Speed x1.15 (small) |
| Ice Wizard | Armor +5 (big) | Area x1.25 (small) | Projectile Speed x1.2 (small) |
| Thunder Wizard | Attack Speed x1.5 (big) | Move Speed x1.2 (small) | Critical Hit Chance 4% (medium) |
| Merlin | XP Gain x1.5 (big) | Ability Cooldown -20% (small) | Area x1.2 (small) |
| Dark Wizard | Damage x1.5 (big) | Luck +10% (medium) | Ability Cooldown -15% (small) |
| Ogre | Max HP x1.6 (big) | Armor +3 (medium) | Area x1.2 (small) |
| Ghast | Extra Jumps +1 (big) | Pickup Range x1.3 (medium) | Move Speed x1.15 (small) |
| Vampire Hunter | Projectile Speed x1.5 (big) | Critical Hit Chance 4% (medium) | HP Regen/s +0.2 (small) |
| Vicki | Jump Height x1.5 (big) | Damage x1.3 (medium) | Move Speed x1.1 (small) |
| The Rogue | Critical Hit Chance 6% (big) | Critical Damage 195% (medium) | Luck +5% (small) |
| Gaiden | Critical Hit Chance 6% (big) | Move Speed x1.2 (small) | Jump Height x1.6 (big) |
| Dr. Croc | HP Regen/s +0.6 (big) | Max HP x1.2 (small) | Armor +2 (small) |
| The Arachnid | Max HP x1.5 (big) | Move Speed x1.3 (medium) | Attack Speed x1.15 (small) |
| Blob | HP Regen/s +0.5 (big) | Max HP x1.3 (medium) | Pickup Range x1.2 (small) |
| Death | Critical Damage 225% (big) | Critical Hit Chance 4% (medium) | XP Gain x1.1 (small) |
| Billy Bulldog | Max HP x1.5 (big) | Armor +4 (medium) | Damage x1.1 (small) |
| Cowboy | Attack Speed x1.5 (big) | Critical Hit Chance 4% (medium) | Projectile Speed x1.2 (small) |
| Loco Robotico | Armor +6 (big) | Attack Speed x1.2 (small) | Pickup Range x1.2 (small) |
| Singe | Area x1.5 (big) | Damage x1.3 (medium) | Max HP x1.2 (small) |
| An Argyle Sock | Luck +15% (big) | Coin Gain x1.2 (small) | Move Speed x1.15 (small) |
| Sentient Platypus | Pickup Range x1.5 (big) | XP Gain x1.25 (small) | Ability Cooldown -20% (small) |
| Bog Witch | Area x1.5 (big) | Ability Cooldown -20% (small) | Luck +5% (small) |
| Toadstool Knight | Armor +5 (big) | Max HP x1.3 (medium) | HP Regen/s +0.2 (small) |
| Kong | Damage x1.5 (big) | Max HP x1.3 (medium) | Jump Height x1.2 (small) |
| Thog the Troll | HP Regen/s +0.6 (big) | Damage x1.3 (medium) | Area x1.2 (small) |
| The Pharaoh | Luck +15% (big) | Area x1.3 (medium) | Armor +2 (small) |
| The Necromancer | Ability Cooldown -35% (big) | Pickup Range x1.3 (medium) | Damage x1.15 (small) |

## Character kits

Every character has a designed kit in `data/abilities.json`: a starting weapon plus three abilities on the same keys and unlock levels as the Fire Wizard (**1** from the start, **2** at run level 5, **3** the ultimate at level 10). Cooldowns and numbers are balanced against his kit (about 30 s / 45 s / 2 min; 80-160 damage for the level-5 ability, 200-400 for ultimates).

**On the select screen**, every character shows its weapon and its three ability squares. Hover one for the full description with cooldown and numbers (`KitDB.describe_lines`; `{braces}` in the JSON mark highlighted numbers). Icons are drawn in code by `scripts/ability_glyphs.gd` from each ability's `"icon": {"glyph", "color"}` (39 glyphs, among them the ankh, the grave and the volcano). To preview them all: `godot --path . --script res://tools/render_ability_icons.gd -- /out.png`.

**In runs**, every character with a body is playable: the four wizards, Merlin, Ogre, Ghast, Vampire Hunter, Vicki, the Rogue, Gaiden, Dr. Croc, Thog, An Argyle Sock, Loco Robotico, the Blob, the Arachnid, the Toadstool Knight, the Pharaoh, the Necromancer and Singe. The others are designs until each character is built (they show "playable soon" once bought).

## The Ice, Thunder and Dark Wizards

Each plays as its own rigged Higgsfield model (`models/<id>/`, Lean clip set: idle, run, hit, attack, ability) driven by `RosterHero` (`scripts/roster_hero.gd`): idle/run blend by speed, and the staff thrust, hit flinch and ability casts play on the upper body so the legs keep running. The staff comes from `RosterWeapons`, and shots leave from its head. **Weapons are put away when not in use:** every character carries its weapon on its back or belt (`RosterWeapons.STOW`) and only draws it to attack or cast: a quick pop into the hand (0.12 s), out through the move, put back 0.6 s after the clip ends (at least 1 s after the move starts; `RosterHero.HOLSTER_DELAY` / `HOLSTER_MIN`), so it stays out through steady fire and goes away between bursts and when nothing is in range. Getting hit doesn't draw it. Two copies are built once (hand and back/belt `BoneAttachment3D`s) and toggled, and shots always leave from the hand copy's head, even mid-draw. Where each goes: staffs (Ice, Thunder, Dark Wizards, Merlin) and Vicki's spear slung diagonally across the back, head over the right shoulder; the Ogre's and Thog's club across the back, heavy end over the right shoulder; the Vampire Hunter's crossbow on the back; the Rogue's daggers in leather sheaths on both hips; Gaiden's katana in a black scabbard on his back, hilt over the right shoulder (the scabbard stays when he draws); Dr. Croc's flask on his belt at the right hip; the Toadstool Knight's sword sheathed at his left hip (`ToadstoolBody`); Loco Robotico's maracas tucked in his belt at the back (`LocoBody`; they stay out through Party and DESTROY Mode); the Fire Wizard's flaming staff across his back (`HeroModel` moves the one staff between hand and back). The Pharaoh's crook and flail go through his belt (crook across the small of his back, flail at his right hip) and the Necromancer's staff is slung diagonally across his back (`PharaohBody` / `NecromancerBody`). The Ghast, Argyle Sock, Blob, Arachnid and Singe fight with their bodies and have nothing to put away. Entrances start with the weapon put away (a cast in the entrance draws it), and the character select preview shows everyone relaxed with weapons away (the Knight's practice cut and Loco's maraca burst draw theirs briefly). **Tests:** `godot --headless --path . res://tools/test_holster.tscn`. Pictures: `res://tools/render_holster.tscn -- vicki,gaiden,ogre /out.png [rest|attack|cast]` (back, side and front of each). The Thunder Wizard arrives as a comet in his own colours; every other character has an entrance of its own (see **Entrances** below), and only the Fire Wizard leaves ash footprints.

**Weapons** (the starting `weapon_orb` card is renamed and re-iconed per character, and levels up the same way):

| Character | Weapon | Effect |
|---|---|---|
| Ice Wizard | Frost Shards | Icicles that slow goblins 30% for 2 s |
| Thunder Wizard | Chain Lightning | Instant arcs that jump to 4 more goblins (+1 per pierce) within 6 m, losing 15% per jump. Hits 1.6x the shared base damage, and double on bosses and epics; the first arc reaches a boss up to 40 m away |
| Dark Wizard | Shadow Bolts | Slow bolts (60% speed) that pierce 2 more goblins; 20% chance to curse (+25% damage taken for 4 s) |

**Abilities** (`scripts/roster_kit.gd`; damage numbers scale with Damage, % of max HP doesn't):

| | 1 (start) | 2 (level 5) | 3 Ultimate (level 10) |
|---|---|---|---|
| **Ice** | **Flash Freeze** (30 s): goblins within 15 m frozen solid for 3 s; frozen goblins can't hurt you, take +50% damage and shatter on death for 40% of their max HP within 2 yd (chains) | **Glacial Path** (45 s): +60% speed for 6 s; your ice trail lasts 5 s, slows 60% and deals 15/s | **Absolute Zero** (2 min): 25 m blizzard on you for 8 s (80% slow, 4% max HP/s), then everything inside freezes for 2 s and shatters for 200 |
| **Thunder** | **Overcharge** (30 s): +40% speed and **invincible** for 8 s; every jump and landing shocks 6 m for 40 | **Thunderclap** (30 s): 12 bolts on the goblins with the most HP within 25 m: 120 each, 1.5 s stun; a boss within 40 m can take up to 4 of them | **Storm Lord** (2 min): a thundercloud follows you for 10 s, striking a goblin within 18 m every 0.25 s for 90, chaining to 3 more; every 3rd strike goes to a boss in range |
| **Dark** | **Siphon** (30 s): goblins within 12 m lose 6% max HP/s for 4 s; you heal 1 HP per goblin per second (max 5% of max HP/s) | **Raise Dead** (50 s): 15 dead goblins (fresh corpses first, the rest claw out of the bog) fight for you for 15 s (25 per hit), then explode for 60 in 3 m | **Eclipse** (2 min): the world goes dark for 8 s; goblins lose track of you and wander, you deal +100% damage, and every kill sends a shadow wisp at a goblin for 60 |

**Goblin statuses** (`enemy_manager.gd`): slow, freeze, stun, curse, the Eclipse wander, and shatter explosions, shown in the goblin shader as icy, frosted or shadowed. Frozen and stunned goblins stand still and deal no contact damage. Raise Dead's allies (`ally_crowd.gd`) reuse the goblin's baked mesh and animations, shadow-tinted. Lightning everywhere is `lightning_fx.gd` (one additive MultiMesh of jagged segments).

## Merlin, Ogre, Ghast, Vampire Hunter, Vicki, Rogue, Gaiden, Dr. Croc, Thog, An Argyle Sock, Loco Robotico, the Blob, the Arachnid, the Toadstool Knight, the Pharaoh, the Necromancer and Singe

These run on the same `RosterHero` model player (clip segments per character in `RosterHero.CFG`). The Ghast's model has no skeleton, so it hovers and sways, lunges when it attacks and swells when it casts. **Thog** has no model of his own yet: he plays on the Ogre's rig (`"model": "ogre"` in his CFG entry) with the troll-blue skin the Swamp boss uses, 20% bigger, holding a bigger club; giving him a real model later is a matter of adding `models/thog/` and dropping that line. He's bought for 10,000 coins after beating him in the Swamp, and can't pick the Swamp (it's his home turf).

**An Argyle Sock** has no model at all: `SockBody` (`scripts/sock_body.gd`) builds it in code - a knitted tube bent into a sock (ribbed cuff, leg, heel, foot, toe), about 1.45 m tall, with googly eyes whose pupils wobble on springs. The shader draws the argyle diamonds and criss-cross yarn from the UVs (crisp at any size), bends the sock as it leans and lunges, squashes it as it hops along, and crackles yellow as Static Cling charges up. `RosterHero.CFG` marks it `"procedural": "sock"`; character select shows it idling the same way.

**Loco Robotico** is built in code too: `LocoBody` (`scripts/loco_body.gd`) is a boxy retro party robot about 1.9 m to the top of his sombrero - two little wheels on accordion legs, a riveted tin torso with a speaker grille, big buttons and a strip of disco lights, a TV-screen head, a straw sombrero with a pom-pom fringe, and a maraca in each claw. The screen's pixel face is drawn by a shader: a smile that blinks, `^ ^` and a big grin in party colours while he casts or parties, X eyes when he's hit, and red angry eyes with gritted teeth in DESTROY Mode. The parts are separate pivots, so he rolls along on spinning wheels, leans and pumps his arms as he runs, grooves on the spot when idle, shakes a maraca with each pulse (left, right, left...), throws both arms up when he casts, and in DESTROY Mode spins his torso like a turret with both arms out along the lasers. `RosterHero.CFG` marks him `"procedural": "loco"`.

**The Blob** is built in code as well: `BlobBody` (`scripts/blob_body.gd`) is a glossy, see-through green slime about 1.4 m tall - a flat-bottomed dome of jelly with a little curl of a peak on top, two big eyes with springy pupils, and bubbles drifting up inside. It's drawn in two passes (the darker inside, then the glossy outside with a bright rim), so whatever is inside shows through. The shader wobbles the surface all the time and ripples it outward with every Acid Body pulse; the body squashes and stretches on a spring: it hops along as it moves, stretches tall in the air, splats flat on landing, swells when it casts, and splats when hit, spraying droplets. It grows with its kills (up to +50%), bulges with whatever it has swallowed, and spreads flat into the Great Puddle with just its eyes poking up. `RosterHero.CFG` marks it `"procedural": "blob"`; Split spawns two half-size ones.

**The Arachnid** plays as the Castle boss's own code-built spider: `ArachnidBody` (`scripts/arachnid_body.gd`) is `SpiderModel` (`scripts/spider_model.gd`) at player size - about 1.5 m tall and 3 m across the legs, glossy black-violet with a cluster of red eyes, a red hourglass and a drop of green venom on each fang. Its eight legs walk themselves: each foot stays planted until the body has moved on, then steps (in two alternating groups of four, two-bone IK for the knees), so it scuttles at any speed without a run cycle. On top of that it bobs and leans as it runs, sways and breathes when idle, jabs its head forward with each Venom Spit (the venom flares), rears up clawing the air when it casts, recoils when hit, lets its legs hang when it jumps, and curls its legs up when it dies. `RosterHero.CFG` marks it `"procedural": "arachnid"`.

**The Toadstool Knight** plays as the Forest boss's own body: `ToadstoolBody` (`scripts/toadstool_body.gd`) is `ToadstoolModel` (`scripts/toadstool_model.gd`: silver plate, a huge glossy red toadstool cap with white spots, a sword glowing violet with spores) at player size - he's small, about 1.45 m to the top of his cap. Where the boss plays whole clips, the knight's body runs its own AnimationTree on the same rig, so his legs keep running while he fights: idle and run blended by speed, an upper-body overhead cut with every Spore Blade swing (the torso twists toward the target), a low sweep-and-thrust when he casts, a flinch when hit, and a death where he staggers and topples over backwards. Spores drift up off his cap. `RosterHero.CFG` marks him `"procedural": "toadstool"`.

**The Pharaoh, the Necromancer and Singe** play as their map bosses' own code-built bodies at player size (`PlayableBoss`, `scripts/playable_boss.gd`; `RosterHero.CFG` marks them `"procedural": "pharaoh" / "necromancer" / "singe"`), posed by hand every frame:
- **The Pharaoh** (`PharaohBody`, `scripts/pharaoh_body.gd`): `PharaohModel` at 0.95x, about 1.8 m. He stands with his arms crossed on his chest (the Osiride pose); running, it's a stiff mummy's jog, leaning in, arms pumping, cloak and bandage ends streaming. He thrusts the crook at each target (the scarabs leave from its hook) while his legs keep running, flings both arms up to cast, rises off the ground for Wrath of the Sands, jolts back and flashes when hit, and when the run ends his knees buckle and he crumbles into sand.
- **The Necromancer** (`NecromancerBody`, `scripts/necromancer_body.gd`): `NecromancerModel` at 0.62x, about 1.85 m to the hood's peak. The boss model holds his staff baked into his arm; here the arm is built empty (an inner `Rig` subclass) and the staff is a separate piece, so it can be slung on his back. He hovers and glides, leaning into a run, levels the staff at each target (the soul bolts leave from its soul-flame) and holds it levelled for Soul Drain, flings his arms up to cast, rises arms spread for The Graves Open, and his robe collapses empty when he dies.
- **Singe** (`SingeBody`, `scripts/singe_body.gd`): `SingeModel` back down to his roster size (0.26x), a little imp about 1.55 m to the crown of his head, flame hair above (its fire and embers sized down). He rubs his hands and hops from foot to foot when idle, capers along, and flat out (over 5 m/s) scampers bent low with his arms flung back; each Fireflick is a claw flick from his right hand, he cackles arms-up to cast, bounces cackling for the eruption, tucks into a spinning ball of coals for Lava Cannonball, and fizzles into a heap of coals when he dies.

Their risen dead (the Pharaoh's mummies, the Necromancer's skeletons) are the Dark Wizard's `AllyCrowd` allies, tinted (`AllyCrowd.tint`): sand-gold and grave-green.

**Weapons** (`weapon_system.gd`). Damage and fire rate are the orb stats scaled by the weapon's own `damage` / `every` in `data/abilities.json`, so every weapon levels up through the same card. On melee weapons, extra count widens the reach.

| Character | Weapon | Effect |
|---|---|---|
| Merlin | Arcane Bolts | Homing bolts that bounce on to 2 more enemies; triple damage to elites (epics) and bosses |
| Ogre | Tree Trunk | 120° cleave, 3 m, heavy knockback (360° in Swamp Rage) |
| Ghast | Wail | 8 m cone that hits everything in it and slows 25% |
| Vampire Hunter | Silver Bolts | Fast bolts that pierce 3 enemies, double damage to epics and bosses |
| Vicki | Valkyrie Spear | 6 m piercing thrust; every 4th throw is a javelin flying 25 m |
| Rogue | Twin Daggers | Short-range throws in pairs; hits bleed 3% of max HP/s for 3 s |
| Gaiden | Katana (sheathed on his back, drawn while he attacks) | 3-hit combo in a 3 m arc; the 3rd cut sends a 10 m wind slash |
| Dr. Croc | Volatile Flasks | Lobbed vials that shatter with breaking glass: 3 m burst, then a lumpy, bubbling acid puddle (4% of max HP/s) |
| Thog | Big Club | Slow overhead smash in a long 9 m, 100° cone for 90 damage, throws enemies back 8 m. Thog starts with **250 max HP** (everyone else 100): with no projectile he fights up close |
| An Argyle Sock | Static Cling | Zaps the 3 nearest enemies (18 each, every 0.6 s); moving builds a charge up to 2x |
| Loco Robotico | Maraca Blasters | Alternating sonic pulses in a 6 m, 60° cone (20 each, every 0.8 s), each hitting at most 2 enemies (+1 per extra Quantity), bosses and elites first. Standing still they come at half speed; moving builds the tempo up to 30% faster, and sprinting gives full tempo at once |
| The Blob | Acid Body | Burns every enemy touching you (2.5 m) for 30 a second, in pulses every 0.5 s; each kill grows you (and the burn) 1%, up to +50% |
| The Arachnid | Venom Spit | Fast globs of venom (12 each, every 0.5 s) that poison for 3% of max HP a second for 4 s, stacking 3 times (`EnemyManager.poison`) |
| Toadstool Knight | Spore Blade | Sword slash in a 3 m, 140° arc (30 damage, every 0.8 s); leaves a 2 m spore cloud for 3 s that poisons for 2% of max HP a second |
| The Pharaoh | Scarab Bolts | Golden scarabs that seek their target (14 each, every 0.6 s), then burrow in for 2% of max HP a second for 2 s |
| The Necromancer | Soul Bolts | Green skull bolts of soul-fire (20 each, every 0.8 s) that pierce 2 more enemies |
| Singe | Fireflick | Embers flicked in pairs, 14 m (8 each, every 0.5 s); each sets what it hits burning for 3% of max HP a second for 2 s |
| Death | Scythe Sweep | A 360° spin every 1.5 s (4 m, 35); anything left under 10% HP is reaped outright (not the boss) |
| Billy Bulldog | Bite | A lunge at the nearest enemy (2 m, 25, every 0.6 s); every 5th bite shakes it for 3x |
| Cowboy | Six-Shooter | 6 quick shots (40 each, pierce 1, every 0.25 s), then a 1.5 s reload |
| Sentient Platypus | Venom Spur | A kick (2.2 m, 15, every 0.6 s) that poisons for 2% of max HP a second; each stack (max 5) slows 10% |
| Bog Witch | Ladle of Bile | Lobs bile that splashes for 25 within 3 m and slows 20% |
| Kong | Shackle Swing | Swings his chains all round him (4 m, 30, every 1 s) with knockback |

Once bought, every character's weapon can also turn up for the others as a rare Legendary level-up reward. The odds are shared out, so the rewards stay rare however many characters you own.

**Abilities**: one `KitPart` per character in `scripts/kits/`, run by `RosterKit`. They follow the numbers in `data/abilities.json`:

| | 1 (start) | 2 (level 5) | 3 Ultimate (level 10) |
|---|---|---|---|
| **Merlin** | **Time Warp**: a 20 m bubble of slow time (70% slower) for 5 s, +50% attack speed | **Polymorph**: 40 enemies become hopping frogs for 8 s (harmless, double damage, 2x XP) | **Rewind**: HP/shield back to 8 s ago, other cooldowns reset, everything within 25 m flung 10 yd and stunned |
| **Ogre** | **Bellow**: enemies within 14 m flee for 4 s; you take less damage for 6 s | **Belly Flop**: leap up to 20 m where you aim; 160 + 2 s stun within 7 m | **Swamp Rage**: 12 s bigger, +60% damage, no knockback, 360° cleave, kills heal 2% |
| **Ghast** | **Phase**: 4 s intangible, drifting through walls, trees and enemies (30 dmg + slow to each) | **Haunt**: possess the biggest non-boss enemy for 10 s; it fights for you (3x), then bursts | **Banshee Scream**: 15% max HP to all within 30 m, they flee 6 s, those under 20% die |
| **Vampire Hunter** | **Holy Water**: thrown pool, 8 m across for 6 s, 25/s and 40% slow | **Stake Volley**: 16 stakes all round, 90 each, pin for 2 s | **Hunter's Night**: 10 s of red night; enemies at half speed, bolts lock on to the 3 biggest for 3x, kills heal 1% |
| **Vicki** | **Shield Wall**: 15% max HP shield for 6 s; attackers take 2x their contact damage | **Wings of Valhalla**: leap and glide up to 4 s, then dive for 140 within 6 m | **Ride of the Valkyries**: a spectral winged horse charges through 3 times for 180 per pass; kills heal 1% |
| **Rogue** | **Smoke Bomb**: invisible 4 s (enemies wander), next attack 3x | **Pickpocket**: dash 12 m through up to 10 enemies, 70 each + an extra XP gem each | **Death by a Thousand Cuts**: blink to the 20 nearest over 3 s, 120 + bleed each, invulnerable, then back home |
| **Gaiden** | **Shadow Step** (2 charges): teleport behind the biggest enemy, 250, 1.5 s invulnerable | **Shuriken Storm**: 3 spiralling rings of 12 piercing shuriken, 50 each | **Reed Clones**: 4 shadow clones for 12 s copying your attacks at 60% |
| **Dr. Croc** | **Mutagen**: +50% attack speed, +30% speed, +10% damage taken for 8 s; like the Hulk he swells to twice his size over 2 s, flashing, his lab coat torn tight, and shrinks back the same way | **Death Roll**: roll 15 m, carrying enemies (50 every 0.25 s), then fling them; invulnerable while rolling (boss hits too) | **Toxic Spill**: 20 m acid flood for 10 s (4% max HP/s); deaths in it burst for 30% max HP |
| **Thog** | **Toll Booth**: 8 s: every enemy that comes within 6 m pays 80 and drops an XP gem | **Goat Charge**: 20 m headfirst charge where you aim, 120 to each and thrown 8 yd | **Bridge Collapse**: a stone bridge falls across your aim (25 m), 350 each; the rubble walls enemies off for 10 s (`EnemyManager.barriers`) |
| **An Argyle Sock** | **Spin Cycle**: 5 s whirlwind, pulls enemies within 6 m in, 40 every 0.5 s | **Lost Pair**: the partner sock (blue and orange) fights beside you for 15 s, copying every zap; enemies zapped by both take 2x | **Laundry Day**: a washing machine falls where you aim, sucks in everything within 10 m, washes it 4 s (10% max HP/s); survivors come out shrunk for 20 s (half damage, double damage taken) |
| **Loco Robotico** | **Party Mode**: a disco ball drops; enemies within 15 m dance for 6 s (can't move or attack) and lose 5% max HP/s | **Piñata Drop**: a donkey piñata lands where you aim (25 m); enemies within 14 m swarm it, and after 3 s it bursts into 20 candy bombs, 60 each within 3 m | **DESTROY Mode**: 12 s of twin lasers sweeping round you to 20 m (8% max HP/s in the beams) and +50% armour |
| **The Blob** | **Engulf**: swallows up to 20 enemies within 6 m (not the boss); they shrink and swirl inside the jelly for 6 s, digested for 8% max HP/s; heal 1% max HP per enemy; survivors are spat out | **Split**: 2 half-size mini-blobs chase enemies for 10 s, each with its own Acid Body at 60% | **The Great Puddle**: spread into a 20 m puddle for 6 s: can't move but invulnerable; enemies in it are slowed 90% and take 6% max HP/s; then survivors are flung out 6 yd |
| **The Arachnid** | **Web Trap**: a 10 m web lands where you aim (25 m); for 4 s everything in it is stuck fast (the boss slowed by half) and takes +30% damage from poison | **Brood**: an egg sac hatches 12 spiderlings that leap onto enemies (a boss in range first) for 15 s, 20 damage a second each, poisoning what they cling to | **Cocoon**: every enemy within 25 m is wrapped in silk for 5 s (can't move or attack) and takes 25% of its max HP; heal 1% max HP per cocoon; the boss is only slowed |
| **Toadstool Knight** | **Fungal Shield**: a shield worth 20% of max HP for 8 s (a translucent toadstool cap over him); when it breaks or runs out it bursts into spores: 60 within 8 m, plus poison | **Fairy Ring**: a 10 m ring of mushrooms springs up around you for 10 s; enemies that cross it take 50 and wander confused for 3 s (harmless; `EnemyManager.confuse`, not the bosses) | **The Fungus Court**: 6 giant toadstool guardians rise in a 12 m ring around you for 15 s; each draws enemies within 9 m to it and slams every 1.5 s: 80 within 4 m |
| **The Pharaoh** | **Curse of the Sands** (30 s): a beam of cursed green-gold light runs 22 m down where you aim (3 m wide): 60, then cursed (+25% damage taken) for 6 s, slowed 50% and withering for 3% of max HP a second for 4 s | **Sandstorm** (45 s): a storm whirls round you for 8 s out to 8 m: slowed 50%, 20 a second, and blinded (`EnemyManager.confuse`: they wander, harmless) for 2 s when it first catches them | **Wrath of the Sands** (2 min): a spectral Sphinx's head rises 16 m ahead of you, looking back over you, and its eyes blaze, two beams sweeping the field; 1.4 s later a great storm tears through every enemy within 25 m for 300 (and slows them); up to 10 of the fallen rise as mummies that fight for you for 12 s, 20 a hit |
| **The Necromancer** | **Raise the Dead** (30 s): up to 8 of the dead (fresh corpses first, then older dead clawing up out of the ground, each from a green-lit grave) fight for you for 12 s, 18 a hit | **Soul Drain** (45 s): a green beam from the staff drains everything in a 16 m line (2.4 m wide) for 4 s, following your aim: 40 a second; you heal 20% of what it does (up to 4% of max HP a second) | **The Graves Open** (2 min): a grave cracks open under every enemy within 25 m; 0.55 s later bone spikes burst out of them: 300, rooted 1.5 s; then up to 16 of the dead rise and fight for you for 10 s |
| **Singe** | **Scorch Trail** (25 s): +30% speed for 6 s, leaving burning scorch marks every 0.9 m that last 4 s; enemies on them take 15 (at most every 0.5 s) and burn for 5% of max HP a second for 3 s | **Lava Cannonball** (45 s): he tucks into a ball of coals and dives up to 18 m where you aim, untouchable in the air (0.8 s), crashing down for 150 within 6 m with knockback and leaving a 4 m lava pool for 3 s (4% of max HP a second) | **Caldera Eruption** (2 min): the ground cracks open round him (22 m) and 36 lava bombs rain down over 6 s, most of them on enemies: each 110 within 3.5 m plus a burn (4% of max HP a second for 3 s) |

New goblin statuses for these: flee, frog, possessed and bleed/acid (`EnemyManager.scare / frog / afflict`, `ally_t`). Frogs, possessed and fleeing goblins can't hurt you. Sounds come from `tools/gen_kit_sounds.py`. **Test:** `godot --headless --path . res://tools/test_kits.tscn [-- --only=<id>]` plays each of the nine and checks its model, weapon and all three abilities. Thog's sounds come from `tools/gen_thog_kit_sounds.py`, the sock's from `tools/gen_sock_sounds.py`, Loco Robotico's (and his maraca shake) from `tools/gen_loco_sounds.py`, the Blob's from `tools/gen_blob_sounds.py`, the Arachnid's (and her spit) from `tools/gen_arachnid_sounds.py`, the Toadstool Knight's (and his sword's swish) from `tools/gen_toadstool_sounds.py`, the Pharaoh's, the Necromancer's and Singe's (and their weapons' shots) from `tools/gen_playable_boss_sounds.py`. **Test:** `godot --headless --fixed-fps 60 --path . res://tools/test_playable_bosses.tscn [-- --only=pharaoh|necromancer|singe]` checks their bodies (size, holstering, poses), weapons, all three abilities and their cooldowns, the forge recipe and special, the character select preview, the unlock rules and a run on a map that isn't home.

**The last six** (Death, Billy Bulldog, Cowboy, the Sentient Platypus, the Bog Witch and Kong) are built in code from primitives by `HeroBody` (`scripts/hero_body.gd`): one jointed humanoid (hips, torso, head, two-part arms and legs) dressed per character (a robed skeleton with a scythe who glides, a stocky bulldog on his hind legs with a spiked collar and wagging tail, a gunslinger in a hat, a platypus in a top hat and monocle with a beaver tail and heel spurs, a hunched green witch with her ladle, a gorilla with long arms and broken shackles) and posed by hand every frame: walk / run, idle breathing, the weapon move (a full spin, a lunging bite, aim and recoil, a spur kick, an overhead lob), casts with both arms up (Kong beats his chest), a flinch, and a topple (Death's robe empties and sinks). They plug in through `PlayableBoss` like the boss bodies. Their kits (`kit_death.gd`, `kit_bulldog.gd`, `kit_cowboy.gd`, `kit_platypus.gd`, `kit_witch.gd`, `kit_kong.gd`):

| Character | 1 | 2 (Lv 5) | 3 Ultimate (Lv 10) |
|---|---|---|---|
| **Death** | **Harvest** (30 s): reaps every enemy within 12 m under 30% HP (not the boss); each soul +2% damage for 20 s, up to +50% | **Mark of the Inevitable** (45 s): an hourglass over the 8 enemies with the most HP within 30 m; 5 s later each takes 400 | **Overtime** (2 min): the run clock and spawns stop for 10 s; +100% damage and kills drop 2x XP |
| **Billy Bulldog** | **Fetch!** (25 s): throws his bone up to 25 m; enemies within 15 m rush to it and squabble (harmless) for 4 s, then it explodes for 100 within 5 m | **Zoomies** (45 s): double move speed for 6 s; his dust trail deals 30 a second and knocks back | **Who's a Good Boy** (2 min): everything within 20 m stops to pet him for 4 s while he can't be hurt, then a bark: 250 within 12 m and a big knockback |
| **Cowboy** | **Lasso** (25 s): ropes the enemy with the most HP within 20 m (not the boss), swings it round him for 3 s (60 to everything it hits), then hurls it 15 m | **Dynamite** (40 s): 3 sticks in a fan, each exploding after 1.5 s for 120 within 5 m | **High Noon** (2 min): everything within 30 m freezes for 2 s while he marks up to 30 of them with crosshairs, then he fires: 300 each |
| **Sentient Platypus** | **Electro-Bill** (30 s): an electric pulse to 15 m, 60 and a 1.5 s stun | **Egg Clutch** (45 s): 4 eggs round him hatch after 2 s; each explodes for 80 within 4 m and poisons | **The Lecture** (2 min): everything within 25 m falls asleep for 6 s (the boss is only slowed) and takes +25% damage |
| **Bog Witch** | **Bubbling Cauldron** (35 s): a cauldron stands for 15 s, spitting a glob (50) at an enemy within 15 m every second; standing next to it heals 2% of max HP a second | **Hex of Silence** (45 s): enemies within 20 m are hexed for 8 s (+25% damage taken); a hexed enemy that dies passes the hex on to its 2 nearest | **Swamp's Fury** (2 min): the ground within 30 m turns to bog for 12 s (slowed 70%); every second hands drag the 3 nearest under (elites and the boss take 25% of max HP instead) |
| **Kong** | **Chest Pound** (30 s): 3 shockwaves to 10 m, 50 each; the last stuns for 2 s | **Log Toss** (45 s): bowls a log 30 m where you aim, 120 to everything it flattens | **Rampage** (2 min): 12 s of +80% damage and +50% move speed; every 3 m he runs the ground quakes (60 within 6 m) and his broken chains lash out to 25 m |

Their forge recipes and specials are in `forge.gd` (Scythe: reaps under 20%; Bite: every bite stuns; Six-Shooter: reloads twice as fast; Venom Spur: poison stacks 8 times; Ladle of Bile: splashes 50% bigger; Shackle Swing: double knockback). **Test:** `godot --headless --fixed-fps 60 --path . res://tools/test_six.tscn` plays each of the six and checks its body, weapon and all three abilities.

**Sounds** are synthesised by `tools/gen_roster_sounds.py` into `audio/abilities/`. **Tests:** `godot --headless --path . res://tools/test_roster.tscn` plays a run as each character and checks the model, entrance, weapon and all nine abilities. Screenshot runs take `--char=<id>` to play as someone else, and `--shot-slow=T` to slow to a crawl at T seconds so short effects like bolts are caught.

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
| Singe | Fast fire imp who sets the ground ablaze | Fireflick | Scorch Trail | Lava Cannonball | Caldera Eruption |
| The Pharaoh | Cursed king who commands the sand and the dead | Scarab Bolts | Curse of the Sands | Sandstorm | Wrath of the Sands |
| The Necromancer | Grave-lord who drains souls and raises the dead | Soul Bolts | Raise the Dead | Soul Drain | The Graves Open |
| An Argyle Sock | Odd little whirlwind with static shocks | Static Cling | Spin Cycle | Lost Pair | Laundry Day |
| Sentient Platypus | Poison-kicking scholar with sleep and eggs | Venom Spur | Electro-Bill | Egg Clutch | The Lecture |
| Bog Witch | Hexer who curses and drowns the horde | Ladle of Bile | Bubbling Cauldron | Hex of Silence | Swamp's Fury |
| Toadstool Knight | Brave little defender with spores and summons | Spore Blade | Fungal Shield | Fairy Ring | The Fungus Court |
| Kong | Brawler who throws the swamp at goblins | Shackle Swing | Chest Pound | Log Toss | Rampage |
| Thog the Troll | Slow, heavy smasher who controls space | Big Club | Toll Booth | Goat Charge | Bridge Collapse |

## Entrances

Every playable character starts a run its own way, tied to who they are; nobody else gets the glowing ball from the sky. The **Fire Wizard** still crashes down as a giant flaming copy of his own head and the **Thunder Wizard** keeps his comet (both in `Abilities.entrance_meteor`). A kit can bring its own (`RosterKit.entrance`: the Sock's washing machine), which comes first; everyone else plays one of `HeroEntrances` (`scripts/hero_entrances.gd`, one function per character named after its id), started from `Abilities.entrance_meteor` and ticked by `Abilities.tick`; a character with no entry there falls back to the comet.

| Character | Entrance |
|---|---|
| Ice Wizard | **Frost spire:** frost races out over the ground in a six-pointed star, ice spikes jut up along its rays, a crystal spire grows up around him (frozen inside, glowing), cracks twice and shatters outward in a spray of shards |
| Dark Wizard | **Shadow rise:** a pool of living shadow spreads, tendrils curl up out of it, a murder of crows bursts out and scatters, and he rises slowly out of the dark; a pulse of shadow rolls out |
| Merlin | **Rewind** ("mostly in reverse"): time runs backwards. Dust and sparkles rush inward, accelerating like an explosion played backwards, and reassemble into him as a rune circle draws itself backwards round the ground; he settles with a twinkle and an owl flaps off |
| Ogre | **Bog geyser:** the ground bulges, trembles and cracks, then bursts in a fountain of bog mud with him in it; mud splatters everywhere, he lands with a thud and shakes himself off like a wet dog |
| Ghast | **Fog wail:** thick fog rolls in from every side, a wail rises, and it fades in out of the mist, see-through and glowing, chains rattling; the wail blasts the fog back out |
| Vampire Hunter | **Bat whirlwind:** a swarm of bats spirals down into a whirlwind; he bursts out of it, crossbow up, the bats scatter, and he puts a bolt into the ground with a thunk |
| Vicki | **Valkyrie descent:** a shaft of golden light parts the sky and she glides down it on wings of light, plants her spear, and a golden ring of force rolls out |
| Rogue | **Smoke bomb:** a smoke bomb lobbed in from the side bounces to a stop, fizzes and goes off in a thick grey cloud; as it thins he's crouched there, stands, and flips a dagger |
| Gaiden | **Leaf slash:** a whirl of leaves and reeds whips round the spot, three slashes cut across it in a blink, the leaves burst apart and he's simply there, kneeling; he rises and sheathes with a click |
| Dr. Croc | **Chemical lurk:** the ground turns into a bubbling green chemical pool; his eyes and snout surface and glide across it like a lurking crocodile, then he surges up in a green splash and adjusts his goggles |
| An Argyle Sock | **Lost in the Wash:** its own entrance from its kit (`KitSock.entrance`): a washing machine drops in, the door flies open, the sock pops out and the machine sinks away |
| Blob | **Ooze seep:** a little ooze puddle seeps up through the ground and spreads, bubbling and gurgling, then swells up into the full Blob, wobbles, and lands a wet splort |
| The Arachnid | **Silk drop:** it lowers itself on a silk thread from high above, swinging, hangs a moment, lets go and drops the last bit, legs splaying, and a web puffs out across the ground |
| Loco Robotico | **Piñata party:** a piñata swings in on a rope and bursts into confetti and streamers; a cardboard box drops out of it, its flaps pop open and the robot springs up out of it with the disco lights on |
| Toadstool Knight | **Fairy ring:** a ring of mushrooms pops up one by one, a giant toadstool grows in the middle with him riding up on its cap, and he somersaults off it into a burst of spores |
| Thog the Troll | **Troll leap:** one enormous leap from far across the field, club up, coming down club-first: the ground cracks into a crater and rocks fly |
| The Pharaoh | **Sarcophagus rise:** the sand turns into a whirlpool and a gilded sarcophagus rises out of it, sand pouring off; the lid falls open with a thud, scarabs scatter, and it sinks back down leaving him standing there |
| The Necromancer | **Grave rise:** green ghost-fire rings the spot, skeletal hands claw up out of the earth, a headstone heaves up, its cracks glow green and it bursts apart: he's standing where it was |
| Singe | **Fuse flare:** a lit fuse burns its way in over the ground in a spiral, scorching a trail, the spot glows and cracks, and a pillar of flame erupts that the little imp hops out of (the bushes nearby catch) |
| Death | **Reaper mist:** a cold blue mist pools on the spot and he rises slowly out of it to a tolling bell |
| Billy Bulldog | **Dig out:** the dirt churns and he digs his way out with a hop and a bark |
| Cowboy | **Dust devil:** a dust devil spins up and he strolls out of it, spurs jingling |
| Sentient Platypus | **River surface:** the ground ripples like water and he surfaces with a splash |
| Bog Witch | **Cauldron rise:** green bog bubbles up and she rises out of it |
| Kong | **Jungle drop:** leaves shake down and he drops out of the sky with a ground-shaking landing |

Each lasts 3.0-3.4 s (`HeroEntrances.SPECS`: duration, impact time, shake, camera framing). The world holds still meanwhile (`main.intro`), the camera frames the event (riding down with Vicki and the Arachnid), and the hero is seen arriving, using the real model and its clips. At the impact moment the arrival does what the comet did: 250 damage (Damage stat and Meteor ability level apply) and knockback to every enemy within 8 m. It ends with the hero standing on the spot, `entrance_landed` fires once and the run starts. Leftover debris fades for 3 s, then the entrance frees itself. Everything is built in code (particles, MultiMesh swarms for shards, crows, bats, leaves, confetti and rocks, ground decals that drape over the terrain, lights), so it works on every outdoor map. **Sounds:** `tools/gen_entrance_sounds.py` writes `audio/entrances/<id>.wav`, timed to each entrance. **Test:** `godot --headless --fixed-fps 60 --path . res://tools/test_entrances.tscn [-- --only=<id>]` runs every character's entrance on the outdoor maps in turn. **Screenshots:** `godot --fixed-fps 60 --path . res://tools/shot_entrance.tscn -- <id> <map> /out/prefix 1.0,2.0` captures frames mid-entrance.

## Character levels and skills

**EXP and levels.** Each character earns EXP from every run (`Wallet.run_exp`), banked when the run ends. The summary shows it itemised along with any level-up:

| Source | EXP |
|---|---|
| Each kill | 1 |
| Each elite killed | +10 |
| The map's boss | +2,000 |
| Each chest opened | +125 |
| Time alive | +100 a minute |
| Winning (killing the boss) | +25% of all the above |

A full 10-minute run earns roughly 4,000-6,000 EXP, a winning one more. So level 1 comes after the first run, the first few levels every couple of runs, and level 10 after about 50 runs. The level (`lvl`, shown on the character select tile) comes from total EXP:

| lvl | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 (max) |
|---|---|---|---|---|---|---|---|---|---|---|
| EXP | 2,000 | 6,000 | 13,000 | 24,000 | 40,000 | 62,000 | 92,000 | 132,000 | 185,000 | 250,000 |

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

**Testing cheat:** press **F8** on the title screen for +100,000 coins (`title.gd`, `CHEAT_COINS`); remove it before release.


**Boss targeting:** whenever a boss is within an attack's range, every weapon and attack goes for it before any other enemy (`EnemyManager.nearest_k` puts bosses in range first; bouncing bolts jump to one first too).
## Elemental shards

A second, persistent currency for upgrading your main weapon in the Forge. There are five kinds, **Fire, Ice, Lightning, Dark and Light**, each drawn as a faceted crystal in code (`scripts/shard_icon.gd`; Light is a pale white-gold gem). Their counters sit just left of the coins at the top of the screen, starting at 0. **Every boss you defeat drops 1-5 shards**, but **each map only yields its own two kinds** (`Wallet.MAP_SHARDS`):

| Map | Shards | Why |
|---|---|---|
| The Swamp | Dark, Ice | Fog and cold black water |
| Magical Forest | Light, Lightning | Sunlit glades and summer storms |
| The Castle | Fire, Ice | Roaring hearths in cold stone halls |
| The Desert | Fire, Lightning | Blazing sun and sandstorms |
| The Graveyard | Dark, Light | The restless dead and holy ground |
| The Ashen Caldera | Fire, Dark | Lava and obsidian |

Each map card in the picker shows its two shards over the corner of the picture. The boss **drops them on the ground** as glowing crystals round his body (see **Boss rules: after the boss**); each one is banked the moment you walk over it (`Wallet.shards`, saved in `user://progress.cfg`), with a chime and the counter popping, and listed under **Shards won** on the end screen. Any kind can still be bought with coins in the Forge.

## Items

Items don't come from level-ups. They come from the world (`item_drops.gd`):

- **Burning trees:** every ability (not just ultimates) sets trees, fallen logs and burnable props alight: those within 6 m of you when you cast, and those near any goblin an ability hits. A tree burns for **3 s** (`TreeFire.BURN_TIME`, was 15 s), then crumbles to dust and **leaves a random item** where it stood, one that can still level up (weighted, rarity rolled with your Luck).
- **Graveyard crypts:** walk up to a crypt door and press Activate (E): the item comes out of the door, then the whole crypt grinds down into the earth and is gone (so you never try the same one twice), clearing the path.
- **Desert statues:** the colossi and ram-sphinx avenues work the same way: Activate at the base, the item comes out, the statue sinks into the sand.
- **Rarely (2%) a shard** of the current map's kinds drops instead of an item.
- Items hover where they land (their charm icon, a rarity-coloured glow); walk over one (pulled in by your pickup range) and the run **pauses on an "ITEM FOUND!" card**: the icon, its name in its rarity colour, NEW ITEM or LEVEL n (MAX at the cap), what it does and the stats it just added. Continue / E / Enter / Esc goes on. Sounds from `tools/gen_item_sounds.py`. On the minimap, items are magenta stars and unopened crypts / statues pale stone tombstones.

The items (`data/upgrades.json`, behaviour in `item_effects.gd`, `main.gd` and `player.gd`):

Every item has a **tier** (`"tier"` in the JSON): it's the colour it shows in (on the ground, on the ITEM FOUND card) and how often it drops (`UpgradeDB.ITEM_TIER_WEIGHTS`: Common 10, Rare 6, Epic 3, Legendary 1, so the Legendary Glass Cannon Skull is about 1 drop in 45). Items don't roll a rarity: their numbers are fixed.

| Item | Tier | Per level | Max |
|---|---|---|---|
| Vampire Fang | Common | +4% chance to heal on a kill | 5 |
| **Second Wind Flask** | Common | +25% max stamina (the stamina bar grows longer) | 4 |
| Blast Bomb | Rare | Enemies have a chance to explode on death | 5 |
| Feather | Rare | +1 mid-air jump | 2 |
| **Cursed Coin** | Rare | +2% chance a kill drops a coin (banked with the run's coins, shown as "Cursed Coin" on the end screen), but +6% damage taken. | 5 |
| **Glass Cannon Skull** | Legendary | +20% damage, -10% max HP | 4 |
| **Hourglass** | Epic | Each elite kill cuts every running ability cooldown by 1 s | 5 |
| **Mirror Shard** | Epic | +4% chance (capped at 60%) to dodge a hit completely: a glassy shimmer, a DODGE pop and a short grace window | 5 |

Sounds for the new items come from `tools/gen_item_sounds.py` (`audio/items/`).

## The Forge (weapon upgrades)

Shards forge a character's signature weapon, up to **level 10** (`scripts/forge.gd`, menu in `forge_menu.gd`). Each weapon has its own recipe of **5 shards**; level 1 costs exactly those, and each later level scales the recipe up: **5, 10, 15, 20, 30, 40, 50, 60, 75, 100** shards.

| Weapon | Recipe (x1 at level 1) | Weapon | Recipe |
|---|---|---|---|
| Fireballs (Fire Wizard) | 5 fire | Twin Daggers (Rogue) | 2 lightning, 3 dark |
| Frost Shards (Ice Wizard) | 5 ice | Katana (Gaiden) | 1 fire, 2 lightning, 2 dark |
| Chain Lightning (Thunder Wizard) | 5 lightning | Volatile Flasks (Dr. Croc) | 2 fire, 1 ice, 2 dark |
| Shadow Bolts (Dark Wizard) | 5 dark | Big Club (Thog) | 2 fire, 2 ice, 1 dark |
| Arcane Bolts (Merlin) | 1 fire, 2 ice, 2 light | Static Cling (An Argyle Sock) | 3 lightning, 2 dark |
| Tree Trunk (Ogre) | 3 fire, 2 dark | Silver Bolts (Vampire Hunter) | 2 ice, 3 light |
| Wail (Ghast) | 1 ice, 4 dark | Valkyrie Spear (Vicki) | 3 light, 2 lightning |
| Maraca Blasters (Loco Robotico) | 2 fire, 3 lightning | Acid Body (The Blob) | 2 fire, 3 dark |
| Venom Spit (The Arachnid) | 1 ice, 1 lightning, 3 dark | Spore Blade (Toadstool Knight) | 1 fire, 1 ice, 3 dark |
| Scarab Bolts (The Pharaoh) | 2 fire, 1 lightning, 2 light | Soul Bolts (The Necromancer) | 1 ice, 3 dark, 1 light |
| Fireflick (Singe) | 3 fire, 2 dark | | |

- **On the character select,** the next level's shards sit under the weapon icon. For small costs that's one crystal per shard, lit as you collect them; for bigger ones, one crystal per kind with the count, lit when you have that many. When you have them all, the weapon **pulses** while **green plus signs** pop in and out around it. Click it to open the Forge.
- **The Forge** shows the weapon, the shards the next level costs, the weapon's stats now and after forging side by side (no headings) with a glowing forged-iron arrow between them, and a **Forge Weapon** button (an anvil clang and sparks).
- **Short on shards?** The Forge offers to **buy the missing ones with coins: 150 coins a shard** (any kind; `Wallet.SHARD_PRICE`). Level 1 costs 750 coins if bought outright (about one good run), level 10 alone 15,000, and a weapon from nothing to level 10 about 60,750. Bosses still drop them for free.
- **Every level:** **+25% damage** and **+8% attack rate**, stacking; levels 4 and 8 add **+1 projectile** (or hit / reach on melee weapons). **Every weapon also gains its own special at level 1** (`Forge.SPECIALS`, listed in the Forge and the weapon tooltip; worked out by style in `weapon_system.gd`, so a forged Legendary card has it too):

  | Weapon | Level 1 special |
  |---|---|
  | Fireballs | Every 5th hit explodes like a level 1 Blast Bomb |
  | Frost Shards | Every 5th hit freezes the enemy for 1.5 s |
  | Chain Lightning | Chains to 2 more enemies |
  | Shadow Bolts | Every hit curses (instead of a 20% chance) |
  | Arcane Bolts | +2 bounces |
  | Tree Trunk | Every 4th swing is a full 360° sweep |
  | Wail | Enemies hit flee in fear for 1.5 s |
  | Silver Bolts | +2 pierce |
  | Valkyrie Spear | Every 3rd throw is a javelin (instead of every 4th) |
  | Twin Daggers | Bleeds deal double damage |
  | Katana | Every 3rd cut deals 2x (instead of 1.25x) |
  | Volatile Flasks | Bursts and acid puddles 50% bigger |
  | Big Club | Smashes stun everything hit for 0.6 s |
  | Static Cling | Zaps hit 2 more enemies |
  | Maraca Blasters | Pulses knock enemies back |
  | Acid Body | Enemies it kills burst for 25% of their max HP within 3 m |
  | Venom Spit | Poison stacks 5 times instead of 3 |
  | Spore Blade | Spore clouds are twice as big |
  | Scarab Bolts | Each scarab seeks on to 1 more enemy |
  | Soul Bolts | Each hit heals you 1 HP (up to 4 a second) |
  | Fireflick | Burns deal double damage |
- **Everywhere:** forging applies to the weapon wherever it's used. That means your own starting weapon, and also its **Legendary card** when another character pulls it in a run. Forge levels are saved (`Wallet.forge`).
- **Tests:** `godot --headless --path . res://tools/test_forge.tscn`. Screenshots: `res://scenes/character_select.tscn -- --shot-char=argyle_sock --shot-shards=fire,ice,lightning,dark,light [--shot-forge]`.

## Pause menu and settings

**Muffled music in menus:** while a level-up, a chest or the pause menu holds the run, the music sounds muffled, as if heard from a cave: a low-pass filter closes to 900 Hz with a touch of echo, easing in and out over 0.35 s (`Settings.update_muffle`, effects on the Music bus).

**Esc** opens the pause menu: Resume, Settings, Restart run, Quit to desktop. Changes apply live so you can try them, but they're only saved (to `user://settings.cfg`, applied on startup) when you press **Apply**. Leaving with Back or Esc puts everything back as it was.

- **Gameplay:** a **Language** dropdown with English, Español, Français, العربية, Deutsch, 中文 (简体) and 日本語. It takes effect on Apply, and all game text switches: menus, the HUD, cards, tooltips, character bios, ability and weapon text, and the title taglines. Also **Play intro on startup** and **Show minimap**.
- **Video:** display mode (windowed / fullscreen / borderless), VSync, render scale, field of view, FPS limit, show FPS.
- **Sound:** Music volume and All other audio volume (goblin voices, hits, effects), each with its own Mute checkbox. They use separate audio buses, `Music` and `SFX`.
- **Controls:** mouse sensitivity, invert Y, and rebindable keys for movement, jump, slide, the three abilities and pause (click a key, press the new one; Esc cancels).

## Languages

The translations live in `data/i18n/`.
- **Where the text is:** `tools/i18n_extract.py` collects every player-visible English string from `scripts/` and `data/*.json` into `_source.json`.
- **Translations:** they're kept in `src/*.json`, one entry per English string with `[es, fr, ar, de, zh_CN, ja]`. `tools/i18n_build.py` merges them into one catalogue per language and checks that every `%s`/`%d` placeholder, `{highlight}` and `[b]` tag survives.
- **Loading:** at startup `Settings` loads the catalogues into the `TranslationServer`. Labels and buttons translate themselves; text assembled in code goes through `tr()` (or `I18n.t()` / `I18n.f()` in static functions).
- **Fonts and Arabic:** Chinese, Japanese and Arabic glyphs come from the system font fallback. Arabic text is shaped right-to-left, but screen layouts stay left-to-right (`internationalization/rendering/root_node_layout_direction`).
- **Testing:** `-- --lang=es` runs a session in a language without saving it.

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
| 3 | **Meteor (ultimate)** | 2 min | Trees, fallen trees and bushes in the blast catch fire and burn, then crumble away. The wizard vanishes (invulnerable, untouchable) and becomes a giant flaming copy of his own head, which crashes where you aim 3 s later: 250 dmg (scales with Damage) in 8 m plus knockback. He reappears at the crash site, and the ground burns for 3 s, dealing 3% of max HP per second to goblins in a 7 m radius |

**Attacks:** his starting weapon hurls **Fireballs**. Each time it fires, he swings his staff down at the target and the fireballs launch from the staff tip.

**Look:** red coat made of animated flames whose back trails along the ground as a train, a two-handed grip on his fire staff, a wrinkled, grimy crimson hat with a wavy brim and a tip that flops to the right, a tarnished gold band, ember eyes, a fire staff, and ash footprints that fade within a second.

**Collisions:** when an enemy touches you, you take its contact damage (shield first), become immune for 0.5 s (shown by dimming the character 50%), and you and the enemy are knocked apart. Enemies that run into you while you're immune bounce back opposite to the way they were heading.

**Epic enemies:** each spawn has a 5% chance to be epic, plus 10% per point of Luck. A Tome of Luck level is 0.1 Luck (+1%), and the Fortune skills give 0.5: 1.5x size, 4x HP and a purple tint. An epic has a 15% chance to drop a potion (`PotionManager.DROP_CHANCE`). Which potion:

| Potion | Chance | Effect |
|---|---|---|
| Yellow (Liquid Soul-Amber: a squat glass jar of glowing amber in a dark iron frame with glowing runes) | 20% | 5x damage for 10 s (the 5x Damage power-up's effect) |
| Red (Vampiric Dew: a tall teardrop vial of deep red in an ornate silver cage, spiked foot, horn-tipped stopper) | 55% | Heal 10% of max HP (a red "+N" pops up next to the health bar and above the wizard) |
| Blue (Bioluminescent Nectar: a round flask of glowing cyan wrapped in luminous veins, ball stopper, sparkles) | 25% | Shield worth 10% of max HP (absorbs damage first, stacks) |

The bottles are built from primitives in `potion_model.gd`. Potions lean and spin slowly so they're easy to spot. They never despawn and there's no limit on how many can lie around: they wait until you pick them up.

**Power-ups:** each elite kill also has a 2% chance to drop one of these, plus 10% per point of Luck (+1% per Tome of Luck level). The NUKE is half as likely as each of the others (`PowerupManager.WEIGHTS`: 2 / 2 / 2 / 2 / 1, so about 11% of drops):

| Power-up | Effect |
|---|---|
| Magnet | Every XP orb on the map flies to you |
| Fear Idol | All goblins run away from you for 15 s |
| 5x Damage | All damage you deal is multiplied by 5 for 10 s |
| Movement Enhancer | +80% move speed for 15 s |
| **NUKE** | Every enemy alive at that moment dies; bosses lose 15% of their max HP instead |

Picking one up while it's active refreshes its timer; active power-ups and their timers show under the run timer.

**The NUKE** (`scripts/nuke_blast.gd`, pickup model `scripts/nuke_model.gd`): it lies on the ground as a cartoon atomic bomb, a fat rounded olive casing with a seam, a red nose band, a tapered tail into a boxy fin cage and a yellow-and-black radiation trefoil on each flank and on top (a texture drawn in code), glowing yellow-green and bobbing and spinning like the others. Press E and:
- **Who dies:** every enemy alive at that instant is marked (by uid); anything that spawns afterwards is spared. A shockwave runs out from you and each marked enemy dies as it arrives, nearest first, so the horde falls in a wave over **0.6 s**. **Bosses** (Thog, the map bosses, the Goblin Warlord) aren't killed: each loses exactly **15% of its max HP** (whatever damage buffs are running) and nothing else.
- **Rewards:** kills count and drop XP gems as usual (the gem cap merges them), then every gem on the map flies to you. Elites can still drop keys, potions and power-ups.
- **Safe:** it never hurts you; bomber skeletons it kills don't drop their barrels.
- **Untouchable enemies too:** it kills enemies directly rather than through `damage()`, so vultures circling out of reach on the Desert (`EnemyManager.is_airborne`) die with the rest.
- **Spectacle (kept small, an indicator rather than a real bomb, `NukeBlast.VISUAL_SCALE` 0.16):** a faint glint, a tiny fireball and a little **mushroom cloud** of churning puffs (fire cooling to smoke) about 5 m tall over you, a condensation ring, a short **shockwave** ring along the ground (fades by 22 m), a small light, a light shake and a softer boom with a rush of wind (`audio/powerups/nuke*.wav`, from `tools/gen_nuke_sounds.py`). Indoors (the Castle) the cloud is squashed under the ceiling (`Abilities.ceiling`).
- **Icon:** `PowerupIcon` (`scripts/powerup_icon.gd`) draws every power-up in 2D (the NUKE as a little bomb with the trefoil); the minimap uses it for power-up blips. Screenshots: `--shot-powerups` lays out all five, `--shot-nuke=T` sets one off at T seconds.

## The minimap

`scripts/minimap.gd`, in the HUD's **top-right corner** just under the coin and shard counters (the kills / enemies counter moved down below it). A round, semi-transparent dark map with a gold rim, 216 px across, showing **65 m** around you. It **turns with the camera**: you're the white arrow in the middle, always pointing the way the camera looks, and a gold **N** on the rim shows north.

**The big map (M, rebindable as "Map"):** pauses the run on a big square map in the middle of the screen: the **whole arena, north up**, with everything the minimap shows (chests, keys, potions, power-ups, items, crypts / statues to open, waygates, the boss, safe zones) and you as an arrow where you stand, turned the way you look. Like holding Alt, the mouse is free so you can **hover your weapons, tomes and items** in the bottom left for their details. M or Esc closes it and the run carries on. It's a second `Minimap` made full (`make_full`); `hud.set_big_map`, `main.open_map` / `close_map`.
- **Blips:** enemies as tiny dim red dots (sampled, at most 300), elites purple, bosses a big red diamond with a skull; unopened chests in their tier's colour (opened ones disappear); power-ups as their own icons in a pulsing ring; dropped keys and potions; the portal out once the boss is down (a violet swirl, or a violet arrow on the rim); sub-bosses (an orange skull hexagon) and waygates (an arch: dim, bright aqua or muted teal; see **Sub-bosses and waygates**).
- **Map context:** the arena edge, the swamp pools, the Caldera's lava pools and rivers, and the Castle's walls with their doorways.
- **Boss ultimates:** while one is coming, the places to stand **pulse bright green**: Thog's quake ponds, the Pharaoh's three golden safe spots (Wrath of the Sands), the Necromancer's churchyard and holy-light circles (The Graves Open) and Singe's basalt islands (Caldera Eruption). The Arachnid's web swath is the reverse: the webbed half of the keep is **tinted red**. Bosses report these through `map_safe_zones()` / `map_danger_zones()` (default empty in `MapBoss`; `ThogBoss` has the same pair), returning `{pos, radius}` circles or `{rect}` areas.
- **The boss off the map:** whenever a boss is alive beyond the map's range, a **big, bright red, pulsing double arrow** sits on the rim pointing toward him (it turns with the map: lower left means behind you, to your left); once he's in range his skull blip shows instead.
- **Past the edge:** safe zones (the nearest four), power-ups and chests you hold the key for sit on the rim as small arrows pointing their way.
- **Cost:** the map content redraws 20 times a second (about 1.5 ms per redraw with 1,400 enemies, headless); between redraws the layer is only turned and slid, so it stays smooth.
- **Settings > Gameplay > Show minimap** (on by default, saved). Hidden during the entrance and with `--shot-nohud`.
- **Screenshots:** `res://tools/shot_minimap.tscn -- play|quake|bossarrow|pickup|cloud[:T] OUT.png` (play / quake / bossarrow with the HUD; pickup and cloud with their own camera and no HUD).
- **Tests:** `godot --headless --path . --fixed-fps 60 res://tools/test_minimap.tscn` (layout and overlaps, blip positions as the map turns, opened chests, the dot cap, the toggle, the boss's red rim arrow, Thog's quake ponds, the Pharaoh's Wrath, the NUKE taking airborne vultures on the Desert, and the NUKE in a Castle run). The NUKE's numbers (drop odds, the wave, bosses' 15%, later spawns spared, you unhurt) are also in `test_abilities`.

## Maps

**Play** (on the title screen or character select) first asks which map: **The Swamp**, the **Magical Forest**, **The Castle**, **The Desert**, **The Graveyard** or **The Ashen Caldera** (`scripts/map_picker.gd`, previews in `images/maps/`). The Forest is **locked until you beat Thog the Troll**, the Swamp's boss, the Castle until you beat **the Toadstool Knight**, the Forest's boss, and so on down the line: the Desert needs the Arachnid, the Graveyard the Pharaoh, the Ashen Caldera the Necromancer; locked cards are darkened, carry a gold padlock and say what's needed. The first time the picker opens after a map is unlocked, its card starts locked, then the padlock rattles, the shackle springs open and the lock tumbles off the bottom of the screen as the card lights up and becomes selectable (each reveal plays once: `Wallet.seen_unlocks`). A character can be barred from a map (`banned_maps` in `data/characters.json`): each boss can't play its own map, since it's their home turf (Thog the Swamp, the Toadstool Knight the Forest, the Arachnid the Castle, the Pharaoh the Desert, the Necromancer the Graveyard, Singe the Caldera). The choice is kept for Restart and the next Play (`Settings.selected_map`). Test and screenshot runs take `--map=swamp|forest|castle|desert|graveyard|caldera`, `--shot-nohud` hides the HUD for clean pictures and `--shot-pos=x,y,z[,yaw]` puts the wizard somewhere.

The two outdoor maps share the same 440 m arena, terrain generator (hills, berm, level pads, 1 m height grid), counts and placement rules, so they play the same: 180 trees, 72 fallen logs, 24 landmarks, 14 pools, grass, walls and the chest pads. `WorldBuilder.build(..., map)` picks the look.

## The Magical Forest

`scripts/forest_builder.gd`, props in `scripts/forest_props.gd`. A bright, sunlit woodland, deliberately unlike the gloomy swamp: a third of the time each: sunny noon with fair-weather clouds, a warm golden afternoon, or a clear moonlit night (the flowering bushes glow). Vivid colour grading and only a light haze. Screenshots take `--forest-time=noon|golden|night`.

- **320 trees** (the swamp has 180) of **7 realistic species**, grown procedurally: a leaning, bending trunk with a root flare, branches that fork and spread, and lumpy leaf clumps along the branches and at every tip in a few shades of the species' colour. Bark is bright so trunks stand out. Each species has 4 shared shapes, rotated and scaled, to keep the forest cheap to draw.

| Tree | Look |
|---|---|
| Silver Birch | Slender white trunk with black bark marks, airy yellow-green crown |
| Oak | Thick light-brown trunk, wide spreading limbs, big rich-green crown |
| Beech | Tall smooth pale-grey trunk, bright lime crown |
| Maple | Tan trunk, autumn crown in orange, scarlet and gold |
| Cherry | Rosy-brown trunk, a cloud of pink and white blossom |
| Pine | Straight orange-tan trunk under tiers of deep-green boughs |
| Aspen | White trunk, golden crown |

- **The ground** is bright green grass everywhere (no dirt or mud), carpeted with grass tufts, drifts of wildflowers (white, yellow, pink, purple, blue, red) and ferns. These are drawn in 40 m chunks that only render within 75 m of the camera. Ground foliage is always lit from above (`MeshBuilder.foliage_material`), so blades never show dark backs.
- **72 mossy fallen logs** with root plates and red toadstools. The **landmarks** keep the magic: giant glowing crystal clusters and rune stones, every 3rd one casting coloured light.
- **Ponds** are clear blue with lily pads and a sandy bed, ringed with reeds.
- **Bushes** (`scripts/bush_field.gd`): 480 bright flowering bushes you can walk through, with no collision. Moving through one shakes it, rustles (4 synthesised variants from `tools/gen_forest_sounds.py`, at most about 3 times a second per bush, from the bush), and sometimes throws out a burst of leaves (45% when you push in, plus about once a second while you keep moving). Standing still in one is silent.
- **By day, butterflies** (`scripts/butterflies.gd`): 70 of them in bright colours with dark-bordered, spotted wings flutter around you on meandering paths, bobbing with each wingbeat, and now and then settle on the grass with their wings slowly opening and closing. **At night, fireflies** (`scripts/fireflies.gd`) drift and blink instead. Both follow the camera, so there are always some nearby.
- **Tests:** `godot --headless --path . res://tools/test_forest.tscn` (more trees than the swamp, daylight, green ground, bright bark, grass and flowers everywhere, bushes react and burn, a run starts on it). To preview the props: `godot --path . res://tools/render_forest_props.tscn -- /out.png [centre-x]`.

- **Balance** (tuned with the playtest bot for the Thunder Wizard demo): **Goblin Brutes** stop growing as a share of spawns at weight 4 (grunts are 10; `Main.TANK_WEIGHT_CAP`), since walls of them were the main cause of death. Each minute's **swarm ring leaves a 90° opening** toward where you're heading (`Main.RING_GAP`), so you can run out through it. Other maps are unchanged.

### Fire in the woods

Trees, fallen logs and bushes all burn (`TreeFire`, `BushField.ignite`). The Fire Wizard's Meteor lights everything in its blast. **Every other character's ultimate** sets the woods around them ablaze too (`Abilities.ULT_FIRE_RADIUS`: 10-30 m depending on the ultimate's reach). A tree burns for 3 s and a bush for 7 s, charring black. Then the charred remains **crumble to dust** (a cloud of ash and cinders pouring off as it sinks in on itself, 1.4 s) and are **gone**, collision and all, leaving the ground clean (no scorch mark) and the tree's **item left in the ash where it stood**. Nothing burns twice.

## The Castle

`scripts/castle_builder.gd` (props in `castle_props.gd`). An enclosed keep on the same 440 m footprint, with the same counts as outdoors: about 250 furniture props, 24 landmarks and 28 chest sites.

- **Layout:** mostly huge open halls with few corridors. The **great hall** (with columns and a red carpet) is behind the front doors. North of it is the **dining hall** under its chandeliers, flanked by two **galleries**, and the **throne room** is at the far end: the throne stands on a 2.4 m raised platform of ashlar built against the middle of the north wall, 20 m wide, with a carpeted staircase down the front, a gold-trimmed edge, pillars at the front corners with braziers burning on top, and two tall banners on the wall behind (`CastleBuilder._throne_dais`). The side wings are the **barracks, armoury, library and chapel**. Wide archways join the rooms, and two short 8 m corridors are the only tight spots. The building has stone walls (ashlar blocks, every one different in shade and tint, some halved, with uneven edges, chipped corners, cracks, the odd long crack running down several courses, water stains streaking down, damp low on the wall, and patches of ivy climbing up from the floor with tendrils reaching higher; all in `WALL_SHADER`), flagstone floors (every stone different: some split in two, varied shades and tints, worn middles and grimy edges, chipped corners, cracks that sometimes fork, the odd shattered stone, stains, and moss in the mortar; all in `FLOOR_SHADER`) and a 24 m timbered roof, so the Meteor and sky bolts start under it.
- **The entrance:** a run starts on the porch outside. The wizard walks in through the 12 m front doors, they swing shut with a boom, and the run starts. The doors stay shut for the rest of the run.
- **Lighting:** wall torches, iron chandeliers and braziers. Banners and stained-glass windows line the walls. Furniture (benches, bookcases, crates, barrels, banners) burns.
- **The runners** in the great hall and throne room are woven carpets (`CARPET_SHADER`): a gold rim, a navy border with a running gold vine and lozenges, a field of small diamonds with a big lozenge medallion every 9 m, visible warp and weft, gold-fringed ends, and age: faded patches, a threadbare path down the middle, dirt and stains, and about one hole or ragged tear every 28 m (cut out of the carpet, frayed round the edge).
- **Wall memorabilia** between the torches (most gaps): painted kite shields over crossed swords (4 heraldries), woven tapestries of a castle in the hills (3 colourings), a stag's antlers, a boar's head and crossed battle-axes; heraldic banners high on the walls come in four schemes (red with a gold lozenge, blue with a silver cross, green with a gold chevron, black with red bars).
- **The feast** (`castle_feast.gd`): two 17.75 m carved oak tables (moulded edge, panelled apron, turned legs, a deep red runner with gold trim) at opposite ends of the keep: one in the great hall beside the runner (south, near the entrance) and one in the throne room (north), each with benches and two chandeliers over it. Together they're laid with about 270 pieces: about 70 place settings in three table sets that change every 6 m (silver, gold and pewter plates, each with a knife and spoon, and **a goblet of wine at every place**), and down the middle whole roast chickens, roast boars with apples in their mouths, platters of turkey legs, silver platters of fruit (apples, pears, oranges, plums, grapes), meat pies, loaves, cheese wheels, **wine bottles**, jugs and candlesticks. A goblet that tips over spills: a splash of wine, then a pool where it comes to rest. A bottle that hits the floor shatters with breaking glass, green shards and a pool of wine where it broke (up to 60 pools at once). Each one is a real rigid body under normal gravity, asleep until disturbed. Walk along the table and you kick dishes flying, and landing on it kicks harder. Explosions and Fire Nova blast everything near them off the table (via `FxManager.burst_fired`). Goblins can't climb on the table, so they run around it. **Don't loiter up there:** stand on the table for 2 s and a chandelier snaps loose over the spot where you stood. A red marker fills on the table for 1 s, then it crashes down for 15% of your max HP if you're still under it, smashing the dishes around it. Stay put and another follows every 2 s. Sounds: `tools/gen_castle_sounds.py`.
- **Pathfinding** (`castle_nav.gd`): a 2 m walkable grid with a flow field rebuilt around you about 3 times a second. Goblins follow it through doorways and around the table instead of piling up against walls, and they slide along walls rather than through them. Spawns only appear on floor that can reach you.
- **Skeletons** (`skeleton_crowd.gd`), indoors only: 35% of castle spawns are skeletons (the overall spawn rate is the same as outdoors). **Armoured skeletons** are their epic version, with a helmet, breastplate and shield. Skeletons walk and claw like goblins, but at 3–17 m with a clear line of sight they stop and **throw bones**. Each bone flies in an arc, leads your movement, hits for 70% of their contact damage (armoured ones hit harder), and shatters on walls and the floor. Their throws clear the table, so standing on it won't keep you safe. Killed skeletons collapse into a scatter of bouncing bones, with a clatter. The models are procedural with a vertex-shader walk, claw and throw, drawn as two MultiMeshes.
- **Bomber skeletons** (`bomber_skeletons.gd`): on the Castle the minute-by-minute swarm ring is replaced by the dead rising (no on-screen message). 10 bomber skeletons (+2 per minute of the run) claw up out of the floor in a ring 14–22 m round you, each with a keg of black powder strapped to its back and a lit fuse. They take 1.3 s to climb out (sunk in the floor and harmless meanwhile, a dust burst and grinding stone), then sprint at you at 1.9x skeleton speed. One that reaches you **blows up on the spot** for 40 damage (x the run's enemy damage multiplier), and is gone. Kill one first and it **drops its keg** as it falls apart: the keg lies there fizzing with a red ring filling on the floor for 1.6 s, then explodes for 32 damage to you inside the 3.5 m ring. Neither blast hurts other enemies (both do fling the feast about). They have 60% of a skeleton's health. Sounds: `tools/gen_bomber_sounds.py`. Screenshots: `--swarm-at=T` brings the first swarm early.
- **Sounds:** the door slam and the bone clatter are synthesised by `tools/gen_castle_sounds.py`.
- **Tests:** `godot --headless --path . res://tools/test_castle.tscn` checks the counts against the swamp, that every room is reachable, the walk-in and the shut doors, food kicks and blasts, and skeleton throws, hits and collapses.

## The Desert

`scripts/desert_builder.gd` (layout, terrain, sand shader, ground scatter), `desert_props.gd` (stone shader, pyramids, trees, ruins, landmarks), `desert_sphinx.gd` (the Great Sphinx, its plinth and tomb door), `desert_edge.gd` (the edge), `desert_wind.gd` (blowing sand). Locked until **the Arachnid** is beaten. Same 440 m footprint and terrain generator as the Swamp and the Forest (`SwampWater`), with the hills re-shaped into wind-blown dunes (ridged crests running across the prevailing wind) and lifted so the ground never dips below 0. Blazing noon (most often), a red-gold dusk or a moonlit night (`--desert-time=day|dusk|night`).

- **The Great Sphinx** lies on a two-step stone plinth 80 m north of the start, facing it, at the head of a graded **processional causeway** of worn flagstones lined with ram-headed sphinxes (so it's in view from the start). 37 m long: a deep barrel of a body with the spine ridge, shoulder blades, erosion bands and fallen-out chunks, heavy haunches, folded hind legs, the tail curled round the right haunch, forelegs stretched out to great paws with toes and claws, courses of restoration masonry along the legs and flanks; a pharaoh's head in the striped nemes (faded ochre and lapis bands open at the face, brow band, flaring wings, striped lappets on the chest, the queue down the back), almond eyes in kohl, eyebrows, cheeks, full lips, big ears, a broken nose, the stub of the uraeus and the plaited beard. The Dream Stele stands between its paws under a winged sun, with an altar before it; obelisks flank the steps and braziers burn at the plinth's corners. Its eyes are their own surface (the Pharaoh's ultimate sets them blazing). Solid to you; the horde walks round its body (`EnemyManager.barriers`).
- **Pyramids** (`DesertBuilder.PYRAMID_LAYOUT`): a great one behind the sphinx (24 m) and three smaller (15, 11, 7.5 m). Each is **baked into the height grid** as an even 37.6-degree slope (steps 0.5 m high and 0.65 m deep, the slope a quarter-metre above the step edges) with a flat summit, so you can **walk (or jump) up them**, and every walking enemy, pickup, chest, ground marker and blast follows the steps for free. The stone drawn on top is built course by course and block by block in running bond: every block a shade of its own, a little proud of or sunk into the face, now and then one missing, the corners worn back, joints and chipped edges cut by the stone shader; sand drifts heap against their feet and fallen blocks lie about. The ground shader knows each pyramid's courses and cuts the sand away wherever stone stands above it. One face of each has a gabled entrance; the second pyramid keeps its smooth white limestone casing on the top third and a gilded capstone, the others end in a broken summit.
- **Stone** (`DesertProps.STONE_SHADER`): sandstone weathered by noise, bedding lines, pits, grime streaks down the faces, sand settled on every upward face, and carved **hieroglyphs** (columns of suns, eyes, reeds, ankhs, water, birds, houses) on obelisks, pylons, columns, sarcophagi, the stele and the lintels.
- **The sand** (`DesertBuilder.GROUND_SHADER`): warm sand with drifts of redder and paler sand, wind ripples (a bump normal with lit crests), long pale wisps of blowing sand sliding across it, darker damp packed patches, gravel, slip faces a touch darker, wet sand and a fringe of green round the two **oases** (reeds, papyrus and date palms).
- **Props** (the swamp's counts): 180 standing (date and doum palms, umbrella acacias, bleached dead trees, rock pillars, boulder heaps; the trees burn), 72 lying (fallen columns, colossal heads half buried in the sand, camel skeletons, crumbling mud-brick walls, sarcophagi, snapped obelisks) and 24 landmarks (obelisks, seated colossi, temple pylons, colonnades, avenues of ram sphinxes; braziers burn by some at night). Ground scatter in 40 m chunks drawn within 75 m: dry grass, saltbush, camel-thorn, pebbles, stones, bleached skulls and bones, potsherds; lush grass by the oases. Blowing sand streams round the camera.
- **The edge** (`DesertEdge`): towering dunes rise 20-40 m all round beyond the invisible walls, flat-topped mesas of banded sandstone stand above them on one side, and the hazy pyramids of another necropolis sit on the horizon.
- **No goblins.** `EnemyManager.type_remap` turns every goblin spawn into its zombie counterpart, and `DesertCrowd.pick_type` adds mummies and vultures. The swarm ring is a ring of sprinting zombies (no on-screen message). `DesertCrowd` (`scripts/desert_crowd.gd`) draws them (code-built models, vertex-shader animation) and plays their deaths:
  - **Zombie** (the goblins' place): hunched and shambling, one leg dragging, arms out in front, torn shirt, rotting skin, ribs and bone showing, dimly glowing eyes. **Sprinting Zombie** (the scamps'): lean, bare-chested, arms pumping. **Zombie Brute** (the brutes'): bloated, in torn overalls, lumbering. Epic zombies are **Plague Zombies** with glowing boils.
  - **Climbing:** walkers follow the height grid up the pyramids; on the steps they slow (45% slower), lean in and claw up hand over hand.
  - **Mummy**: slow and tanky (36 HP), bound in bandages that flutter, one eye burning through the wraps; it claws its way out of the sand when it spawns (harmless for 1.4 s) and its touch **curses** you: half speed for 1.6 s. Epic: a **Mummy Priest** in a gold-and-lapis nemes and collar, with a crook.
  - **Vulture**: circles 5 m up on a thermal that drifts after you but keeps its distance (15-19.5 m, so a bird never comes within landing range on its own). While it's up there it's harmless and out of reach: nothing can hit, target or damage it (`EnemyManager.is_airborne`). Come within **9.5 m** of one and it glides down over 1.2 s, flaring its wings, to land 3 m from you (on a pyramid's steps too; still out of reach until it touches down). On the ground it folds its wings and waddles after you, head bobbing, at 2.4 m/s (slower than a zombie); now it can be hit. It does no contact damage: within 2 m it stops, rears back and a **red wedge** (2.7 m, about 63 degrees wide) fills on the ground in front of it for 0.8 s, then it lunges and pecks: 1.5 zombie hits (24, times the run's enemy damage) if you're still in the wedge, nothing if you stepped out. 1.5 s between pecks. If you get more than 16 m away, or it has been on foot 8 s without pecking you, it takes off again (out of reach once it's 1.6 m up) and won't land for 4 s. Frozen or stunned on the ground it stays put (and a peck being wound up is called off); frozen in the air it hangs there.
  - Deaths: zombies pitch over and sink into the sand, mummies crumble to dust, a vulture shot on the ground keels over onto its side in a puff of feathers (one caught in the air, by the nuke or a burn, tumbles out of the sky). Voices: zombie groans, mummy rasps, vulture screeches, wingbeats and pecks (`tools/gen_desert_sounds.py`).

## The Graveyard

`scripts/graveyard_builder.gd` (layout, ground shader, fog, clouds, placement), `graveyard_props.gd` (stone and masonry shaders, headstones, crypts, the chapel, railings, trees, coffins, grave dressing), `graveyard_edge.gd` (the cemetery wall), `graveyard_ambience.gd` (will-o'-wisps, flickering lights, crows, the bell). Locked until **the Pharaoh** is beaten. Same 440 m footprint and terrain generator as the Swamp and the Forest (gentle hills, three murky ponds, level chest pads), always at night.

- **Layout:** two wide gravel avenues cross at the start (a round plaza), narrower winding paths every 40 m split the ground into plots. Most plots hold **rows** of headstones facing a path, each over its grave (bare earth in front; some framed by a stone kerb); some are **old plots**, irregular and overgrown, the stones leaning, sunken and broken and mossier; some hold **family plots** ringed by low wrought-iron railings round an obelisk, angel or urn. About 4,000 headstones in twelve kinds (rounded, gothic pointed, shouldered tablet, Latin cross, Celtic cross with ring and knotwork, obelisk, praying or pointing angel, broken, child's stone with a lamb, ledger slab, chest tomb, draped urn), all with carved names, dates and emblems, in granite, sandstone, slate and marble. The stone shader weathers them: grain, streaks running down, grime at the foot, lichen blotches, and moss on the tops, low down and in the letters. Drawn in 60 m chunks within 150 m; you bump into them.
- **Graves:** 40 **open graves** (the ground shader cuts the hole; the pit has spade marks and roots, a coffin below, a spoil heap with a shovel, sometimes a lantern) and 60 **fresh graves** (a heaped mound and a crude wooden cross). Candles, funeral wreaths and withered flowers left on graves; crows perched on the taller stones (they peck and look about).
- **Landmarks** (the swamp's 24): **the ruined chapel** in a railed churchyard (consecrated ground): a roofless nave with jagged broken walls and empty lancet windows, a breach in one side, a gable front with a moulded pointed doorway and an empty rose window, a broken apse, charred roof timbers and a corner of slate roof, toppled pews, an altar with lit candles, rubble, and a tall **bell tower** with an open belfry, a bronze bell and a cracked, leaning slate spire. And 23 **crypts and mausoleums** fronting the paths, the ground levelled under each, in four kinds: a classical mausoleum (steps, fluted columns, a lettered frieze, pediment and urns), a gothic crypt (buttresses, a steep slate roof, a pointed door with moulded arches, a rose window), a domed tomb (an octagon of pilasters under a ribbed verdigris dome and lantern) and a barrow vault (a grassed mound, a stone facade, skull-topped pillars with glowing eyes). All with iron grille gates, wreaths and candles. The masonry shader gives them coursed blocks, cracks, damp streaks, moss on ledges and ivy climbing from the ground.
- **Trees and props:** 150 gnarled dead trees (twisting trunks, crooked forking branches, broken stubs, hanging moss) and 18 weeping willows round the ponds; 72 lying props (coffins, an open coffin with a skeleton, a coffin stack, dead logs, a gravedigger's wheelbarrow); all burn. Lantern posts line the avenues.
- **Ground** (`GraveyardBuilder.GROUND_SHADER`): dead and dying grass in drifts of straw, olive and grey, darker hollows, bare earth over the graves, gravel paths with a muddy fringe, ruts and puddles, fallen leaves (thickest under the trees) and damp pond banks. Ground debris in 40 m chunks within 75 m: dead grass tufts, leaf litter, pebbles, toadstools, skulls and bones.
- **Sky and air:** a big moon in a starry sky with clouds drifting across it (a cloud layer with a silver lining near the moon), cold blue moonlight with long shadows, height fog and two layers of **ground fog** draped over the hills, rolling slowly; **will-o'-wisps** drifting over graves, crypt doors and trees; crows wheeling overhead and cawing; the chapel bell tolls in the distance now and then. Only 14 real lights (the chapel, some crypt doors, the plaza lanterns), flickering.
- **The edge** (`GraveyardEdge`): a high cemetery wall all round (a stone plinth wall, tall iron railings between piers, urns on every eighth pier) with the great cemetery gate on the south side, dead woods beyond.
- **The dead** (`scripts/undead_crowd.gd`, `UndeadCrowd`, code-built models animated in the vertex shader like the skeletons). `EnemyManager.type_remap` turns goblin spawns into **ghouls** (the goblins' places: gaunt hunched grey-green corpse-eaters loping fast and raking with long claws; they pitch into the dirt and sink when killed), **ghosts** (the scamps': hooded tattered wraiths floating 0.75 m up with streaming tails, drawn see-through and flickering; they drift through headstones, railings and crypt walls, their touch **chills** you (60% speed for 1.6 s), and their hit box reaches their floating bodies; they rise and fade with a wail) and **skeletons** (the brutes'). **The swarm** is the dead climbing out of the graves round you (skeletons, ghouls and ghosts, harmless until they're out; clods of earth fly), no on-screen message. Voices: ghost wails, ghoul snarls, crumbling earth (`tools/gen_graveyard_sounds.py`).

## The Ashen Caldera

`scripts/caldera_builder.gd` (layout, terrain, lava, ground shader, crossings, placement, ground scatter), `caldera_props.gd` (the rock shader, every prop, landmark and set piece), `caldera_edge.gd` (the crater cliffs, the great volcano, the cinder cone), `caldera_ambience.gd` (ash and embers round the camera, rumbles, the lava's burn, eruptions). Locked until **the Necromancer** is beaten. Same 440 m footprint and terrain generator as the other outdoor maps (`SwampWater`: hills, level pads, chest sites, the 1 m height grid), built entirely in code. A volcanic crater floor under a smouldering red-orange sky (a black, lava-lit night now and then; `--caldera-time=ember|night`), the haze thick with drifting ash. Music: its own track (`audio/music/caldera_map.mp3`).

- **Lava instead of water.** Three rivers of lava wind across the caldera: one pours from the **lava falls** on the northern ridge into the **great lava pool** north of the start (Singe's lair), one runs out of the pool to the eastern cliffs, one winds west to east across the south; plus a few side pools. Lava is carved into the height grid (a channel 0.35 m deep under the lava's surface, banks easing to walkable slopes, levees where the ground was lower), so everything follows it for free, and its surface is drawn on top (`LAVA_SHADER`: dark crust plates drifting on the flow, cracked finer, molten rock glowing between them, bright upwellings; the falls stream down). **Standing in lava burns:** 7 damage every 0.5 s and a brief burn (`Player.ignite`), and it doesn't slow you; enemies wade through unharmed. There's **no swamp water anywhere**: `SwampWater` keeps no pools, and the whole ground is lifted so even the lava beds sit well above 0.
- **Crossings:** each river has **natural rock bridges** (the channel left uncut and the ground humped over it, a rough arch of boulders on both faces with the lava pouring into its dark mouth) and **basalt stepping stones** (lines of solid hexagonal columns, tops just over the lava, close enough to walk across).
- **The ground** (`GROUND_SHADER`): black basalt and grey ash drifts, cooled **pahoehoe** ropes (a bump normal), scorched and rusty patches, sulphur-yellow crusts, and a network of **glowing cracks** that pulse, broken and patchy out in the open, wider and hotter toward the lava, which glows along its banks.
- **Set pieces:** the dwarves' road of hexagonal basalt paving runs from the start down to the great pool between stone posts with burning braziers. The **ruined dwarven forge-temple** (walls of squared basalt broken to jagged tops, rune-lit door jambs, bronze-banded octagonal columns, a hearth of glowing coals under a hood and chimney with bellows, a quenching trough of lava, hanging braziers, stout dwarf statues at the door) has a **giant anvil** in the middle with a hammer leaning on it. The **smith-god's colossus** lies half sunk in the biggest side pool: a bearded head in a crested helm, a shoulder and an arm thrust up out of the lava still gripping a broken hammer, cracks glowing where the lava eats it. The **lava falls** pour over a ridge of black rock. A **cinder cone** (baked into the ground in a corner) smokes, its crater glowing, lava streaming down its flank.
- **Props** (the swamp's counts): 180 standing (charred trees that burn, petrified trees, basalt column clusters, obsidian shards, scoria boulders with glowing cracks, steaming sulphur vents, hornitos), 72 lying (toppled basalt columns, charred logs, pahoehoe lobes, the bones of huge beasts, wrecked forge gear, volcanic bombs), and 24 landmarks: **basalt column fields** (honeycombs of hexagonal columns whose tops climb in 0.45 m steps to 5.8 m: jump up them), **obsidian spires** (towering blades of black glass), **chained braziers** (rune-carved pillars, braziers hanging on chains), **fumarole fields** (crusted vents pouring steam), **sulphur crystal clusters** and the **skeleton of some enormous beast** (an 8 m ribcage, a horned skull). Ground scatter in 40 m chunks drawn within 75 m: pumice, scoria, ash drifts, singed tufts, glowing embers and little glowing fissures (mostly near the lava), sulphur crumbs, stones.
- **The air** (`CalderaAmbience`): ash drifting down round the camera, embers rising, a bubbling lava sound from the nearest lava, and now and then a distant **rumble**: the camera trembles and the cinder cone flares and puffs ash.
- **The edge** (`CalderaEdge`): towering crater cliffs of banded basalt and red scoria, lava seeping down them in places, beyond invisible walls; on the horizon a **great active volcano** with a glowing crater, lava streaking its flanks and a column of ash boiling up.
- **Eruptions:** the minute's swarm here is the volcano erupting (no on-screen text): a rumble, the cinder cone blows, and **lava bombs** arc from it onto **marked circles** round you (6 + 1 a minute, up to 14; one where you're heading; each circle fills for at least 1 s, most for 2-3 s): 22 damage (rising through the run) and a burn if you're inside. They only hurt the player. A ring of magma imps claws up out of the cracks round you (harmless while they climb out) with cinder bats among them.
- **The creatures** (`scripts/caldera_crowd.gd`, `CalderaCrowd`; code-built models animated in the vertex shader, MultiMeshes like the Desert's). No goblins come to the Caldera: `EnemyManager.type_remap` turns them into:
  - **Magma Imp** (the goblins' place): a small hunched imp of cracked black rock with lava glowing in its seams, curling horns, ember eyes, a spade tail; it scuttles fast, **in packs** (imps spawned close together join up). It bursts into a puff of embers and a scatter of rock chunks that cool from orange to black, and crumbles away. Its epic is the **Ember Fiend**: bigger, seams blazing, a mane of flame.
  - **Cinder Bat** (the scamps'): smouldering cinders, glowing wing veins and a tail of flame; it flies loose **figure-eights** above you, then **dives** at you and climbs away, leaving a trail of embers. Near you it flies at your height, so it reaches you on top of a basalt column; its row is at its real height, so every weapon hits it. It tumbles out of the air in a burst of sparks.
  - **Obsidian Golem** (the brutes'): slow and huge, glossy black glass with a lava core glowing through a split in its chest; its heavy steps shake the ground near you; it **shatters** into a spray of glass shards. Its epic is the **Molten Golem**, glowing hot through and through.
  - **Lava Slug** (new): slow and soft, crusted on top and molten underneath, eye stalks waving; it leaves a **trail of burning lava** that hurts you for 4 s after (enemies don't mind it), and melts into a cooling puddle when it dies.
  - Voices and deaths: imp chitters and crackling pops, bat screeches and wingbeats, golem footfalls and shattering glass, slug squelches and sizzles (`tools/gen_caldera_sounds.py`, `audio/caldera/`).
- **Tests:** `godot --headless --path . res://tools/test_caldera.tscn`. Contact sheets: `res://tools/render_caldera.tscn -- crowd|props|landmarks|forge|statue|singe /out.png`; Singe's moments: `res://tools/shot_caldera.tscn -- crowd|rise|singe|breath|scamper|ult|dead /out/prefix [seed]`.

## The swamp

Every run generates a new dark swamp (`scripts/world_builder.gd`):

- **Sky:** 50% chance of a gloomy day with the sun glowing through dense clouds, 50% chance of a moonlit night with very few clouds and stars. Lighting, ambient light and fog follow.
- **Size:** 440 × 440 m (`ARENA_HALF = 220` in `scripts/main.gd`), with stone walls round the edge.
- **Terrain:** rolling hills, dips and slopes from two layers of smooth noise: broad hills of up to about ±6.5 m and smaller rolls on top. Every slope stays walkable (under 40°). The start point, every pool and every chest site sit on level pads that ramp gently back into the hills. Near the walls the ground climbs into a berm about 7 m high. Everything follows the ground: goblins, drops, trees, grass and the flat ability markers. The Meteor target, Fire Nova's ring and glow, and the Stink Aura are `GroundDisc`s that drape over the slopes. The terrain is baked into a 1 m height grid (`SwampWater.build_terrain`) that collision, the ground mesh and gameplay all share. To tune it, change `HILL_HEIGHT`, `HILL_FREQ`, `BUMP_HEIGHT` and `EDGE_RISE` in `scripts/swamp_water.gd`.
- **Ground:** random patches of wet mud and swamp grass, with swaying grass tufts.
- **Swamp floor** (`scripts/swamp_foliage.gd`): every pool is carpeted with notched lily pads (densest near the shore) and the odd yellow spatterdock flower, with big heart-shaped leaves on stalks in the shallows; clumps of sedge ring the banks; ferns spread over the grassy ground and round the foot of every tree; half-sunk mossy stones, sticks and arching roots litter the shores. The banks themselves are drawn in the ground shader (`shore_detail`): glossy black mud with a fringe of algae at the waterline, wavy tide lines, then paler drying mud split by cracks with pebbles pressed in. All of it is in 40 m chunks drawn within 75 m of the camera.
- **180 swamp trees** in 4 variants: bald cypress (tall, fluted buttressed base, knees, lumpy foliage clusters on crooked branches and long curtains of grey-green Spanish moss), dead snag, swamp willow (drooping curtains) and mangrove (stilt roots). All collide with the player.
- **72 fallen trees:** mossy logs with root plates, slightly tilted, which you can climb and jump off.
- **14 big pools of swamp water:** irregular ponds 18-36 m across, at least 66 m apart, recessed into the ground with uneven beds, never deeper than the character. Reeds and cattails grow around the edges. **In water, move speed and jump height are halved** (goblins wade at half speed too).
- **24 mossy stone ruins** as landmarks.
- **Camera zoom:** the mouse wheel zooms the camera in and out (up to 16 m away). All the way in is first person: the camera sits at the wizard's eyes and he's hidden from view, though his shadow stays. The chosen distance is kept between runs (`Player.zoom`).
- **Entrance:** each run opens with the Fire Wizard arriving as his own Meteor (every other character has its own entrance: see **Entrances**). For the 3 s it takes to fall, the clock, the spawns and the goblins all hold still and nobody can act. It falls silently and lands with the full impact (explosion sound, no scorched ground), and the run starts (`Abilities.entrance_meteor`, `main.intro`). Screenshot and smoke runs skip it unless you pass `--shot-intro`.
- **Title tagline:** 44 Dungeons & Dragons puns (none about dice) (`data/taglines.json`) rotate under the logo every 5 s with a crossfade. They play in shuffled order, all of them before any repeats. To add your own, edit the list.
- **Upgrade overlay:** the bottom-left corner shows everything you own as icons with their level: weapons and items on the top row, tomes underneath, in the order you got them. On a reward card, the level it will become (for example "Lv 2") sits to the right of its icon.
- **Signature weapons:** every unlocked character's weapon can turn up for the other characters as a rare Legendary level-up reward, under 1% of cards. It fires alongside your own weapon, levels up to 5 and counts as one of your 4 weapons (`WeaponSystem.add_signature_weapons`). **One per run:** once you take one, its level-up cards come up as often as any other weapon's (`UpgradeDB.weight_of`), and no other character's weapon can be pulled for the rest of the run.
- **Unlock reveal:** buying a character shows "UNLOCKED <weapon>" over a collectible-style card of their weapon, with a fanfare. Click or press any key to continue (`scripts/unlock_reveal.gd`, `scripts/weapon_card.gd`).
- **BAN:** under each reward card a BAN button (100 coins) throws that reward out of this draft and every later draft in the run. You lose that choice, and you get 3 bans per run. Banning plays a stamp-and-"denied" sound. You can't ban the last card left (`BANS_PER_RUN`, `BAN_COST` in `scripts/main.gd`).
- **Level-up sounds:** a "power surge" (a low punch and a bright synth stab) plays when you level up and a soft tick when you hover over a reward card. Picking a tome slams a book shut, and picking anything else rings a magic "shing". Choose them in `UI_SOUNDS` in `scripts/hud.gd`. `tools/gen_ui_sounds.py` synthesises the candidates in `audio/ui/`.
- **Start banner:** "SURVIVE 10 MINUTES" slams into the middle of the screen as the wizard lands in blood-red letters with a black outline and dripping blood, then fades (`scripts/blood_banner.gd`).
- **Music:** "Tension Drop" (`audio/music/tension_drop.mp3`) starts with the level and loops until the run ends, then fades out. Change `SWAMP_MUSIC` / `MUSIC_VOLUME_DB` in `scripts/main.gd`.
- **Ability sounds:** Inferno and Fire Nova play their sound on the key press and take effect 1 s later (`INFERNO_DELAY`, `NOVA_DELAY`). Meteor plays its sound on the cast and an explosion when it lands. The explosion is synthesised by `tools/gen_explosion_sound.py`. All of them are in `audio/abilities/` and use the SFX bus.
- **Menu music:** "Menu of Shadows" (`audio/music/menu_of_shadows.mp3`) loops on the title and character select screens. The `MenuMusic` autoload (`scripts/menu_music.gd`) plays it, so it carries on without restarting between the two screens and fades out when a run starts.
- **Level-up cards:** each card has a big icon as its centrepiece: tomes are books, weapons are bronze medallions and items are silver charms. The name sits under the icon, and the effect is in its own dark box. The card is outlined thickly in its rarity colour (grey, blue, purple or gold). Icons are set in `data/upgrades.json` (`"icon": {"glyph", "cover", "tint"}`) and drawn by `scripts/upgrade_icon.gd`. To preview all of them, run `godot --path . --script res://tools/render_upgrade_icons.gd -- /out.png`.
- **Character select abilities:** the selected character's three abilities appear as the same squares as the in-run ability bar. Hover one for what it does, its cooldown and the run level it unlocks at (`Abilities.describe_lines`).

## Thog the Troll (the Swamp boss)

`scripts/thog_boss.gd`, body in `scripts/thog_model.gd`. With **2 minutes left (8:00)** a 10 m blue troll with a studded club walks out of the swamp (the Goblin Warlord no longer comes on the Swamp). A health bar appears under the timer with a countdown to his enrage.

- **Must be killed to win:** the 10:00 mark no longer ends a Swamp run. When Thog falls (he topples backwards into the bog and gems fly to you) he drops his shards and a portal opens; step through it and the end screen says **THOG DEFEATED!** (see **Boss rules: after the boss**). Any level-up choice still open then is skipped.
- **Enrage:** if he's alive 2 minutes after arriving (10:00) he **enrages**: his attacks come **twice as fast** (animations, wind-ups and the pauses between them), though every telegraph still gives at least 1 s of warning, his skin smoulders red and flames pour off him, and the bar turns red.
- **Three attacks,** each telegraphed on the ground in red that fills up until it lands:
  - **Slam** (close): both fists overhead and down into the ground in front of him: 40 damage in the marked circle, then a **shockwave ring** rolls out to 20 m (22 damage; **jump over it**).
  - **Sweep** (close): his club swung across a 130° wedge in front of him, 14 m long: 32 damage and a big sideways knockback.
  - **Bellow** (at range, every 14 s): a roar that calls a ring of 14 goblins and a brute around you.
- **The Quake** (at **75%, 50% and 10% health**): Thog slowly raises both fists overhead and pounds the ground, about every 2 s (quickening to 1.6 s), each blow jolting the camera over a light, growing tremble, while **the entire map lights up red except the swamp pools** (their shores glow green). You have **10 seconds to get into a pool**, and a big glowing green arrow bobs over every pool, pointing down into it. If you're anywhere else when it lands, it takes **50% of your max HP straight through your shield** and wipes the shield out.
- **Under the hood:** Thog is a crowd row in `EnemyManager` (type `TROLL`, 5,200 HP x the 8:00 HP multiplier, about 33,000), so every weapon, burn, freeze, curse and ability hits him; he isn't drawn as a goblin. Knockback doesn't move him, freezes last a third as long and stuns a quarter. Frozen or stunned he can't start an attack. He mostly alternates slam and sweep.
- **Model:** a stand-in until Thog gets his own: the Ogre's rigged model with its skin re-tinted troll blue (`models/ogre/thog_skin.jpg`) and the Ogre's club, scaled up 4.4x. Slam, sweep and bellow are segments of the Ogre's attack, ability and hit clips (`tools/render_thog.tscn` renders contact sheets of them).
- **Rewards:** beating him the first time unlocks the Magical Forest and makes Thog buyable (10,000 coins). The end screen shows an **UNLOCKED!** block: one card per unlock (NEW MAP / NEW CHAMPION, with a hint for what to do next), each flying in from off screen on a swirling, spinning spiral trailing sparks, then landing in its slot with a pop, a flash, a burst of sparks and a ding. The list is read from the data (maps that `require` the boss, characters with `requires_boss`), so future bosses get it for free. Screenshot: `--map=swamp --shot-boss-win=1,3`. Saved in `user://progress.cfg` (`Wallet.bosses_defeated`).
- **Sounds:** roar, slam, sweep, footsteps and the fall are synthesised by `tools/gen_thog_sounds.py`.
- **Tests:** `godot --headless --path . res://tools/test_boss.tscn`. Screenshots: `--map=swamp --thog-at=0.2 --shot-thog=distance,side-angle [--thog-enraged]`.

## The Toadstool Knight (the Magical Forest boss)

`scripts/toadstool_boss.gd`, body in `scripts/toadstool_model.gd`. At **8:00** a 6 m mushroom-capped knight marches out of the trees. He enrages **3 minutes** after arriving (other bosses: 2; `MapBoss.enrage_after`) and must be killed to win the Forest. Base health 2,400 (x the run's HP multiplier: about 15,300 at 8:00). While he's up the fight is a duel: the steady goblin trickle stops at **90 alive** (the all-boss cap, `Main.BOSS_LIVE_CAP`; normally 250) and no swarm rings come. Touching him deals 30.

- **Spore Slash** (close): an overhead cut across a 120° wedge in front of him (26 damage). It leaves a violet spore cloud that hurts while you stand in it.
- **Fairy Ring:** a ring of mushrooms bursts out of the ground around you (24 damage). The red band shows where it will burst, so step into the middle or out past it.
- **Spore Mortar** (at range): he lobs 5 spore pods (7 when enraged) at and around you. Each flies in an arc onto its own filling circle (14 damage) and leaves a small poison puddle.
- **Fungus Court** (every 24 s, from 25 s in): three 4.5 m toadstool guardians rise at marked spots around you for 12 s, each slamming the marked ground around itself every 3 s.
- **Model:** a stand-in until he gets his own. It's Gaiden's rigged swordsman polished up into silver plate, with a huge glossy red toadstool cap with white spots (built in code on the Head bone) and a blade that glows violet. Slash and cast are segments of Gaiden's attack and ability clips (`tools/render_clips.tscn` renders contact sheets).
- **Rewards:** beating him the first time unlocks **the Castle** and makes him buyable (10,000 coins). He can't play the Forest; it's his home turf.

## The Arachnid (the Castle boss)

`scripts/arachnid_boss.gd`, body in `scripts/spider_model.gd`. At **8:00** a 10 m spider scuttles in. She enrages after 2 minutes and must be killed to win the Castle.

- **Climbing (new):** every 16 s or so she bounds to the nearest wall of the room you're in, avoiding doorways, and runs up it. She then scuttles along the wall 16 m up, staying level with you:
  - Touching her can't hurt you up there.
  - Her hitbox reaches her, so your shots still connect.
  - From the wall she shoots webs and venom down at you.
- **Coming down:** after a while she either drops from the wall onto a marked spot, or crawls out across the ceiling upside down until she's over you and then drops. Either way a big circle fills under her first (45 damage), and a brood of spiderlings scatters from the impact.
- **Lunge** (close): a red lane appears in front of her, then she dashes down it fangs first (38 damage).
- **Venom Spit:** globs (3, enraged 5) arc onto marked circles and leave poison puddles.
- **Web Shot** (from the wall): a web lands on a marked circle. Standing in it slows you to 40% for 5 s.
- **Brood:** an egg sac is laid at a marked spot and hatches spiderlings 2 s later.
- **Webs** (`spider_webs.gd`): she always leaves a **trail of webs** wherever she walks on the floor; each fades after about 3 s. Her ultimate, the **Web Swath** (at 75%, 50% and 10% health, like Thog's quake), has her rear up and screech, then webs spread out from her across **one half of the keep** (west, east, north or south, at random) over 2.5 s and stay for **a minute**. Standing in any web: **half speed and no jumping**, lasting **4 s after you leave** the last web.
- **Model:** built entirely in code. A glossy black-violet body with a red hourglass, eight red eyes and fangs, and eight two-jointed legs that walk themselves: each foot stays planted until the body has moved on, then steps, in alternating groups of four. Two-bone IK bends the knees away from whatever she's standing on, so the same legs work on the floor, a wall or the ceiling (`tools/render_spider.tscn` previews it).
- **Rewards:** beating her makes her buyable (10,000 coins). She can't play the Castle.

## The Pharaoh (the Desert boss)

`scripts/pharaoh_boss.gd`, body in `scripts/pharaoh_model.gd`. At **8:00** the tomb slabs before the Sphinx's paws grind apart, gold light and sand pour out, and a 6 m mummified king rises out of the shaft. He enrages after 2 minutes and must be killed to win the Desert.

- **Look:** a gold death mask in a gold-and-lapis nemes with burning green-gold eyes, the uraeus and the plaited beard; yellowed bandages (a woven, grimy linen shader) wound round every limb, loose ends trailing; a broad collar of gold, lapis and carnelian beads, a scarab pectoral, a gold belt and pleated kilt, gold arm bands and anklets, a tattered royal-blue cloak; the crook and the flail, held crossed on his chest as he walks (the flail's beaded strands swing).
- **Flail Slam** (close): a circle in front of him fills as the flail rises, then it comes down on the mark. **Curse Beam**: a lane toward you fills, then green-gold light leaves his crook down it: damage, and you're cursed (half speed for 3 s). **Sandstorm**: a whirling storm settles on a marked circle at you for 6 s, slowing you to half speed and scouring you. **Scarab Swarm**: three marked lanes fan out at you and black scarabs pour down them. **Raise the Dead**: four (enraged six) marked circles round you; mummies claw up out of them. **Sand Walk**: run too far and he sinks into the sand and bursts out of a marked circle beside you.
- **Wrath of the Sands** (his ultimate, at 75%, 50% and 10% health): he rises into the air, the Sphinx's eyes blaze and two beams of light fall from them, a great sandstorm is marked over everything round you (32 m, 3.2 s of warning) except **three golden safe spots**; be in one when it lands or take 55 damage and a slow, as the sand howls round you.
- **Death:** his knees buckle, he slumps and crumbles into a heap of sand; the tomb's glow dies. Beating him the first time makes him buyable (10,000 coins), and then he's playable (see the roster kits). He can't play the Desert.

## The Necromancer (the Graveyard boss)

`scripts/necromancer_boss.gd`, body in `scripts/necromancer_model.gd`. At **8:00** a 4.3 m sorcerer steps out of the grave-mist as the chapel bell tolls. He enrages after 2 minutes and must be killed to win the Graveyard.

- **Look:** a long tattered robe of black and grave-purple with gold-trimmed edges and faint glowing runes, a deep hood over a bare skull with burning green eyes and a circlet of bone spikes, a mantle of bone plates and little skulls, a belt of skull trinkets and a chained grimoire, long bony hands, and a twisted staff crowned with a horned skull clutching a green soul-flame (it lights the ground round him). He hovers, the ragged hem streaming; souls circle him.
- **Staff Slam** (close): a circle round him fills, then bone spikes burst out of the ground all round. **Bone Lines**: three lanes fanned at you; spikes erupt along each from his feet outward. **Bone Ring**: a band round you fills; spikes burst up in it. **Raise the Dead**: green circles over graves round you; when each fills skeletons and ghouls claw out of it and hands grab whoever stands there (hurt and rooted). **Soul Drain**: a lane marks where the beam starts, then a green beam pours from his staff for 2.8 s, swinging after you slowly enough to outrun; it drains you and heals him. **Cursed Circle**: a big circle where you're heading becomes a ring of slowly turning curse runes for 6 s that hurts and slows you.
- **The Graves Open** (his ultimate, at 75%, 50% and 10% health): he rises into the air laughing and the whole graveyard glows a sickly green, cracks crawling over it, for 9 s. Only **consecrated ground** is safe: the chapel's churchyard and four circles of holy light (each under a pillar of light) round you. Anyone anywhere else loses 40% of their max HP, straight through shields; bone spikes erupt and the dead rise from the graves all round.
- **Death:** he shrieks, the soul-flame gutters out and the robe collapses empty into the dirt in a burst of escaping souls; the dead he raised fall back. Beating him the first time records his defeat and makes him buyable (10,000 coins), and then he's playable (see the roster kits). He can't play the Graveyard. Sounds: `tools/gen_graveyard_sounds.py`.

## Singe (the Ashen Caldera boss)

`scripts/singe_boss.gd`, body in `scripts/singe_model.gd`. Singe, the Living Cinder from the roster ("a little imp made of hot coals"), swollen into a giant. At **8:00** the great lava pool bubbles and he **bursts up out of the lava** like a jack-in-the-box, cackling. He enrages after 2 minutes and must be killed to win the Caldera.

- **Look** (built in code): about 6 m tall, a pot-bellied heap of cracked black coals with glowing orange seams that pulse, hotter lumps of coal stuck all over him; a big round head with long pointed ears, heavy mischievous brows over glowing yellow eyes with slit pupils, a snub nose and a wide impish grin of jagged charred teeth around a glowing furnace (a hinged jaw that cackles); a crown of roaring flame hair (licking flame cones and fire), spindly arms with long three-clawed hands, spindly backward-kneed legs with clawed toes, a long pointy tail with a spade tip that never stops swishing; embers stream off him and his belly lights the ground. He hops and capers when he walks, rubs his hands with glee when he stops, and cackles, head thrown back, at every trick. The **Magma Imps** are his minions: a sixth his size, rocky, darker and horned, with no flaming crown or glowing grin.
- **Claw Swipe** (close): a wedge in front of him fills while he cocks his claws back, then he rakes them through it (damage and a burn). **Fire Breath**: he rears back drawing breath while a cone from his grin fills, then spews fire down it (damage and a burn), and the ground in the cone burns for 4 s. **Lava Dive**: he leaps, tucked into a cannonball, into the nearest lava (or straight through the crust if there's none within 30 m) with a SPLOOSH, then pops out under a circle marked by you (also when you run too far from him), leaving burning ground. **Meteor Call**: he juggles lava bombs over his head, then flings them onto five (enraged seven) marked circles round you. **Summon**: his magma imps claw out of marked cracks round you, every other time with an obsidian golem. **Scorch Run** (scorch marks on everything): he crouches cackling, then scampers in a loop round you; every footfall is marked on the ground first, filling until he gets there (the first at least 1.1 s ahead), and leaves a **scorch mark** for 6 s: step on one and you burn for 3 s.
- **Caldera Eruption** (his ultimate, at 75%, 50% and 10% health, like Thog's quake): he flings up his arms cackling, the volcano erupts and the ground's cracks race open and pulse for **10 seconds**, while four **raised basalt islands** burst up out of the ground round you, each under a big glowing arrow pointing down at it. Then the **whole floor floods with lava** for 8.5 s. On an island you're safe; anywhere else it takes 35% of your max HP straight through your shield when it floods and 6% every second you stay in it, and sets you burning. Then the islands sink again.
- **Death:** he sputters and staggers, his flame hair dies down and he fizzles and shrinks, guttering out into a small heap of cooling coals with one last puff of smoke; every lava surface on the map dims. Beating him the first time records his defeat (`"singe"`), which (with 10,000 coins) unlocks **Singe** on the roster. He can't play the Caldera. Sounds (a synthesised cackle and giggle, spew, splash, scamper, fizzle and puff): `tools/gen_caldera_sounds.py`.

## Sub-bosses and waygates (Swamp)

A try-out to ease the pressure of the horde: mid-run mini-bosses whose deaths leave a pair of linked portals you can hop between. Data per map in `SubBosses.MAPS` (`scripts/sub_bosses.gd`): only `"swamp": {"times": [120, 240], "kind": "bog_shaman"}` for now; other maps get it with one line (and a kind in `SubBoss.KINDS`).

- **The Bog Shaman** (`scripts/sub_boss.gd`, `SubBoss`): arrives at **2:00** and again at **4:00**, 25-35 m from you on dry ground, with a burst of bog mud and a guttural chant. A 2.2x goblin chieftain in bog-green rags (a crowd row of its own type, `EnemyManager.SUB_BOSS`, drawn by the goblin VAT) with a code-built bone crown and horns, a hide mantle, a totem staff topped with a skull and a ball of green swamp-fire (with its own light), and a green aura ring on the ground. Its name and an orange-bordered health bar float over it (not the big boss bar).
  - **Numbers:** 320 HP x the run's HP multiplier (about 600 at 2:00, 970 at 4:00; an epic is 40, Thog about 33,000), speed 3.3, contact damage 32 (a brute's), 40 XP. Can't be polymorphed or shrunk; otherwise every weapon, burn and status hits it.
  - **Targeted like an elite:** the bosses-first rule stays the real boss's. **Spawns aren't reduced** while it's up (`main.boss_up()` is the map boss only).
  - **Mud Slam** (close, every 7 s): a 5 m circle round it fills for 1.1 s, then it slams: 24 damage, slowed to half for 2.5 s, shoved back.
  - **Bog Bolt** (4-22 m, every 8 s): a 20 m lane, 3.2 m wide, fills toward where you're heading for 1.0 s, then a bolt of bog water tears down it: 18 damage, slowed 35% for 2 s.
  - It stands still while it casts; every telegraph gives at least 1 s (`SubBoss.MIN_WARN`).
  - **Rewards:** its XP gems, an elite's ~10% chance at a chest key, and it counts as an elite kill for character EXP.
- **Waygates** (`scripts/waygate.gd`, `Waygate`): each sub-boss drops one where it fell (snapped to the nearest flat, dry, open ground: not in water, props, chests or on top of the other gate). A mossy trilithon about 2.9 m tall (two standing stones and a lintel carved with runes, in a ring of half-sunk stones) that grinds up out of the ground, its front facing you.
  - **Inactive** (the first one): dark, runes faint. Within 4 m a floating text says **"Needs another portal to activate"**.
  - **Active** (once the second drops; both flare up with a chord): runes glow blue-green, a swirling vortex fills the arch, a light and a hum. Near one, **Press E**: you're thrown to the other (a whoosh and a flash), landing just in front of it facing away, and goblins right there are shoved back so you don't land in a crowd. One teleport per press.
  - **Recharging:** after any use both gates dim for **90 s** (`SubBosses.COOLDOWN`); the floating text counts down ("Recharging 1:12") and E does nothing.
  - **Until the map is done:** they stay until the map boss dies (`main._on_boss_defeated` calls `SubBosses.on_map_boss_defeated`), then fade and sink away; also when the run ends. A sub-boss still alive when Thog arrives stays (and no longer drops a gate once he's dead).
- **Minimap:** the sub-boss is a deep orange skull hexagon (`Minimap.SUBBOSS`); gates are a little arch, dim grey-teal inactive, bright aqua active, muted teal while recharging (`Minimap.WAYGATE_COLS`; active or recharging gates out of range get a rim arrow).
- **Sounds:** `tools/gen_subboss_sounds.py` (`audio/subboss/`: arrival, slam, bolt, death, the gate rising, activating, its hum loop and the teleport whoosh).
- **Debug:** `-- --subboss-at=T[,T2...]` replaces the map's times (and turns them on for any map), `-- --waygates-at=T` drops two active gates near you, `-- --shot-subboss` keeps the camera on the sub-boss.
- **Other maps later:** add a `MAPS` entry. The Desert, Graveyard and Caldera draw their own crowds, so a kind there would want its own look rather than the goblin VAT.
- **Tests:** `godot --headless --fixed-fps 60 --path . res://tools/test_subboss.tscn` (2:00 and 4:00 arrivals, HP between an epic and Thog, both telegraphs >= 0.8 s and hitting, the inactive gate and its text, activation, teleport and landing, one per press, the full 90 s recharge and its countdown, the minimap blips, the gates going with Thog, none on the Forest).

## Boss rules (all bosses)

- **A quieter fight:** while any map boss is out, the steady trickle runs at a fifth of its usual rate (`Main.BOSS_SPAWN_MULT`), never more than **90 enemies alive** at once (`Main.BOSS_LIVE_CAP`; a boss can ask for fewer with `MapBoss.crowd_cap`), and **no swarm waves** come at all: no rings, no Castle bombers, no Caldera eruptions, no Graveyard risings. The boss's own summons still come.

`scripts/map_boss.gd` (`MapBoss`) holds what the Forest and Castle bosses share: the crowd row (type `TROLL` with each boss's own numbers), the HUD health bar and enrage countdown, sounds, and the attack helpers.
- **Fair warning:** every attack that lands somewhere is marked on the ground first (circles, wedges, lanes and rings), filling up red until the hit lands. It never fills in less than **1 second** (`MapBoss.MIN_WARN`), even when enraged; enraged bosses are faster, but never faster than that. Thog follows the same rule.
- **Heavy hitters:** every boss's damage (attacks, hazards and contact, Thog and the Goblin Warlord included) is multiplied by `EnemyManager.BOSS_DAMAGE_MULT` (**1.75x**).
- **Projectiles:** lobbed projectiles land exactly when their marker fills.
- **Lingering zones:** spore clouds, puddles and webs are drawn for as long as they last.
- **Sounds:** synthesised by `tools/gen_boss_sounds.py` (`audio/bosses/`).
- **Tests:** `godot --headless --path . res://tools/test_bosses.tscn`.
- **Screenshots:** `--map=forest|castle --boss-at=0.3 --shot-thog=distance,angle`.

### After the boss: shards and the portal

Killing a map's boss **doesn't end the run** on any map (`scripts/boss_aftermath.gd`, `BossAftermath`, called from `main._on_boss_defeated`):
- **At once:** his defeat is recorded (`Wallet.defeat_boss`, so unlocks are kept even if you die afterwards), XP gems fly to you, and **no more monsters come**: the trickle, the swarm rings, the Castle's bomber skeletons, the Caldera's eruptions and the Graveyard's rising dead all stop (`main.boss_down`). Whatever is still alive stays and can be fought. The run's time (and its coins) stop at the moment he fell.
- **His shards drop** (`scripts/shard_drops.gd`, `ShardDrops`): one faceted crystal per shard (1-5 of the map's two kinds, `Wallet.roll_boss_shards`) bursts out of the body with a crystalline crack and arcs onto the ground round it, tumbling, then hovers, bobs and spins, glowing in its element's colours (`ShardIcon.COLORS`) with a halo, a light and a ring on the ground. If he fell somewhere you can't stand (in lava, up a wall) they land on the nearest good ground toward you. **Walk over one** (1.5 m; within your pickup range they drift to you) and it's banked at once with a chime, a burst, "+1 Fire Shard" and the counter popping.
- **The portal** (`scripts/boss_portal.gd`, `BossPortal`): **2.5 s** after he falls a ring of carved stone (4.3 m tall, glowing runes, a low round dais, violet-flamed braziers) grinds up out of the ground, then a swirling violet vortex ignites inside it (shader), with motes, sparks spiralling in, a light, a soft hum loop and, on the outdoor maps, a **pillar of light into the sky** you can see from anywhere. The clock gives way to **PORTAL OPEN**, "THE PORTAL IS OPEN" flashes, an arrow on screen points to it (with the distance), and the minimap shows it (a violet swirl, or an arrow on the rim).
- **Where it opens** (`BossPortal.preferred`, then the nearest flat, dry spot clear of props, walls and chests): **the Desert** on the causeway in front of the Sphinx (8 m before its plinth); **the Castle** the middle of the keep (the dining hall, facing the front doors); **the Ashen Caldera** at the foot of the dwarves' road, on the basalt beside the great lava pool Singe rose from; **the Swamp, the Forest and the Graveyard** the clearing, glade or plaza where the run began.
- **Step into it** and you're drawn into the vortex with a whoosh and a flash; any shards still lying about are banked for you (nothing is lost), and the run is won as before: "<BOSS> DEFEATED!", coins, EXP and the unlock cards.
- **Unrelenting:** the monsters keep coming (that's the mode), but the boss still drops his shards and the portal still opens, as a way out with a win; or keep going.
- **Sounds:** `tools/gen_portal_sounds.py` (`audio/portal/`: the portal rising, its hum, the whoosh, the shard chime and burst).
- **Tests:** `godot --headless --path . --fixed-fps 60 res://tools/test_portal.tscn [-- --maps=desert,castle]` (every map: no end screen at the kill, no more spawns, the shards' count, kinds and spots, picking one up, where the portal opens, walking in wins and banks the rest). The playtest bot picks up the shards and walks to the portal (round the walls indoors: `BossPortal.way_from`).
- **Screenshots:** `--portal-at=T` drops shards in front of you and opens the portal at T seconds without a boss (nothing is banked), e.g. `--map=desert --shot-pos=0,4,-22,0 --portal-at=0.3 --shot-at=2`.

## Chests, keys and the slot machine

**The prize flies home:** on Continue the machine fades and the winning icon pops off the reel (a soft whoosh). If two or three reels show it, they gather in the middle of the screen and merge into one (a glassy chime), then it drops into that ability's square on the ability bar, which pulses as it lands (a thump and a sparkle of bells). Sounds from `tools/gen_natural_sounds.py` (`slot_lift`, `slot_merge`, `slot_land`).

Each run places **18-28 chests** on level pads around the map: **Bronze** most often (60%), **Silver** sometimes (30%), **Gold** rarely (10%). A chest only opens with a **key of its tier**: walk up to it with the key and it opens; without one it says which key it needs. **Elites drop keys** (about 10% of them): per elite, bronze 5.5%, silver 2.3%, gold 1.9% (bronze and silver were cut 65%; gold unchanged). **Used chests sink away:** half a second after the slot machine closes, the lid falls shut and the chest grinds down into the ground with a short rumble and a puff of dust, like the crypts (`Chest._vanish`). When a boss falls, every chest still standing sinks the same way. Keys spin on the ground until you pick them up, show at the top of the screen while you hold them, and don't carry over between runs. The **key counter** sits at the bottom left, above your upgrades: a bronze, silver and gold key with how many you hold.

**Level-up cards:** under each card, a small **BAN 100** button (with a coin) throws the reward out of this and every later draft. Legendary cards also get **Convert**: skip the upgrade for one chest key, **60% bronze, 30% silver, 10% gold**. The key pops up big in the middle of the screen, then flies down into the key counter.

**Hold Alt** to pause and inspect: hovering an ability shows its tooltip, and hovering one of your upgrades in the bottom left shows what it does and its stats (where they started and where they are now).

Opening a chest pauses the game (like a level-up) and brings up a **slot machine** with three reels of your three abilities. Pull the handle (click it, or press Space / Enter): the reels spin and stop left to right.

| Result | Reward |
|---|---|
| Three of a kind | that ability **+3 levels** |
| A pair | the pair's ability +1 level |
| All three different | one of them, at random, +1 level |

Like a real machine, the result is rolled the moment you pull, then the reels stop to show it. The chest's tier sets the odds of three of a kind: **Bronze 8%, Silver 15%, Gold 30%** (shown on the machine). Abilities already at max level can appear on the reels but are never the one levelled; if all three are maxed, a chest fully heals you instead. Code: `chest_manager.gd`, `chest.gd`, `key_manager.gd`, `slot_machine.gd`; sounds from `tools/gen_slot_sounds.py`.

## Ability levels

**Abilities deal double their listed damage** (`EnemyManager.ABILITY_DAMAGE_MULT`, matched by the three ability names as damage sources). When a chest's slot machine stops, the result spells out the upgrade: the ability and its new level, each stat it raises (+% and its total multiplier) and the cooldown in seconds before and after (`Abilities.level_change_lines`).

Every ability starts at **level 1** (as designed) and goes up to **level 10**, only through chests; levels reset each run. Each level adds a third of the ability's base strength to its main stat, so **level 4 is 2x, level 7 is 3x and level 10 is 4x**, and cuts its cooldown, down to **-40% at level 10**. The ability bar shows a level badge, and the tooltip lists the level, which stats it raises, and the current and next level's numbers.

| Character | Ability 1 | Ability 2 | Ability 3 |
|---|---|---|---|
| Fire Wizard | Inferno: burn damage | Fire Nova: damage | Meteor: damage (and its burning ground) |
| Ice Wizard | Flash Freeze: radius | Glacial Path: trail damage | Absolute Zero: damage |
| Thunder Wizard | Overcharge: shock damage | Thunderclap: damage | Storm Lord: damage |
| Dark Wizard | Siphon: drain damage and healing | Raise Dead: damage | Eclipse: damage bonus and wisp damage |
| Merlin | Time Warp: duration | Polymorph: frog count | Rewind: radius |
| Ogre | Bellow: radius | Belly Flop: damage | Swamp Rage: damage bonus |
| Ghast | Phase: damage | Haunt: damage | Banshee Scream: damage |
| Vampire Hunter | Holy Water: damage | Stake Volley: damage | Hunter's Night: duration |
| Vicki | Shield Wall: shield | Wings of Valhalla: damage | Ride of the Valkyries: damage |
| Rogue | Smoke Bomb: ambush damage bonus | Pickpocket: damage | Death by a Thousand Cuts: damage |
| Gaiden | Shadow Step: damage | Shuriken Storm: damage | Reed Clones: clone damage |
| Dr. Croc | Mutagen: speed bonus | Death Roll: damage | Toxic Spill: damage |
| Thog | Toll Booth: damage | Goat Charge: damage | Bridge Collapse: damage |
| An Argyle Sock | Spin Cycle: damage | Lost Pair: partner damage | Laundry Day: damage |
| Loco Robotico | Party Mode: damage | Piñata Drop: bomb damage | DESTROY Mode: damage |
| The Blob | Engulf: digest damage | Split: mini-blob damage | The Great Puddle: damage |
| The Arachnid | Web Trap: poison bonus | Brood: spiderling damage | Cocoon: damage |
| Toadstool Knight | Fungal Shield: shield and burst damage | Fairy Ring: damage | The Fungus Court: slam damage |

## Shields

Shields (blue potions, Shield Wall, Fungal Shield, Rewind) soak up damage before your HP. When damage brings a shield to 0 it **breaks with a glass-shatter sound** (`audio/ui/shield_break.wav`, from `tools/gen_shield_sounds.py`; `Player.shield_broken`).

## Goblins

Every enemy is a goblin (contact damage was doubled: 16 / 12 / 32, boss 70): about half the wizard's height. The model is a textured, rigged Higgsfield/Meshy goblin (`models/goblin/`): hunched, warty, with big ears and clawed hands. Types differ by size and colour grade: Goblin, Goblin Scamp (small, fast, yellowish), Goblin Brute (big, grey) and the Goblin Warlord boss (huge, dark red).

**Animation:** goblins charge head-down (run cycle speed matched to their ground speed) and throw punch combos when they reach the wizard. The crowd can reach 1,400, so instead of skeletons the clips are **baked into vertex-animation textures** (`tools/bake_vat.gd`). The goblin shader (`vat_crowd.gd`) replays them per instance from the MultiMesh, with each goblin's clip and phase in its instance colour. That keeps the whole crowd in one draw call.

**Death:** killed goblins play a fall-backwards death animation, lie on the ground (charred if they died burning), then sink away 3 s after death.

**Sounds:** goblins are silent while alive, with no voices or grunts. When one dies within 30 m, a short "splat-pop" plays from where it fell. There are 4 variants, and bigger goblins sound deeper. Death sounds are limited to about 20 per second, so mass kills sound like a crunchy volley. The clips (`audio/goblin/death_*.wav`) are synthesised by `tools/gen_goblin_death_sounds.py`, and the player is `scripts/goblin_audio.gd`.

## Shots on slopes

Straight (non-homing) projectiles follow the slope they're fired along: each keeps the height above the ground it left the weapon at (`WeaponSystem.p_clear`), climbing uphill and dipping downhill instead of flying level into a hillside or off into the air. Homing shots (Arcane Bolts, scarabs, hunting shots) steer themselves, Singe's flicked embers keep their arc, and indoors (the Castle) the floor is flat so nothing changes. Melee sweeps (Maraca Blasters' sound rings and the other fans) lean with the ground they sweep over too.

## Combat feedback

- **Health bars** over every goblin (green → yellow → red; purple border on epics), hidden beyond 45 m.
- **Damage numbers** for every hit: they pop in small, swell big, settle, then float up and fade, all within 0.75 s. Burn damage is totalled and shown in orange twice a second.

## What's in the slice

- **Run structure:** 10-minute run, spawn rate and enemy HP scale with time, a swarm ring every minute (bomber skeletons rising on the Castle). On the Swamp, **Thog the Troll** arrives at 8:00 and the run is won by killing him (see *Thog the Troll*); on the other maps a Goblin Warlord comes at 5:00 (his death vacuums all XP) and surviving 10:00 wins.
- **5 weapons:** Fireballs (auto-targeted, pierce), Stink Aura (damage field), Ground Slam (knockback nova), **Thorns** (anything that hits you takes 2x its damage back, +35% a level) and **Ice Aura** (everything within 5.5 m is slowed 40%, wider and colder each level). Thorns and Ice Aura come up as often as tomes and have their own icons (`skill_icon.gd`: `thorns`, `frost_aura`). **Max 4 weapons and 4 tome types per run** (`Main.MAX_WEAPONS`, `UpgradeDB.MAX_TOMES`): once your slots are full, only the ones you have come up in level-up drafts. **Until then, drafts push you to fill them:** while a weapon slot is open, one of the three cards is always a new weapon, and while a tome slot is open, one is always a new tome; the remaining card(s) use the normal weights (`UpgradeDB.draft`). The bottom-left HUD shows a row of 4 weapon slots and a row of 4 tome slots (empty slots outlined until filled), and items on a row below.
- **13 tomes** (stat upgrades) and **3 items** (explode on kill, heal on kill, extra jumps).
- **Rarity rolls** (Common → Legendary, x1–x3 effect): Luck raises the weight of Rare, Epic and Legendary by its value (0.1 per Tome of Luck level).
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
  potion_manager.gd  epic drops: yellow / red / blue potions (bottles: potion_model.gd)
  fx_manager.gd      pooled bursts and ash footprints (MultiMesh)
  ability_slot.gd    one ability-bar slot (procedural icon, cooldown, ult outline)
  ability_glyphs.gd  procedural icons for the roster kits' abilities
  kit_db.gd          loads data/abilities.json: every character's weapon + 3 abilities, tooltips
  hero_base.gd       what a playable character's model provides (HeroModel and RosterHero)
  roster_hero.gd     rigged roster character in runs: clips, staff, twist, colours
  roster_kit.gd      the Ice / Thunder / Dark Wizards' abilities; hands everyone else's to scripts/kits/
  kits/              KitPart and one kit per character (Merlin ... Dr. Croc)
  scorch_mark.gd     the smoking, sizzling black patch a burnt-out tree or bush leaves behind
  ally_crowd.gd      Raise Dead's risen goblins
  lightning_fx.gd    pooled jagged lightning bolts
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
  chest_manager.gd   places 18-28 bronze/silver/gold chests per run, opens them with keys
  key_manager.gd     chest keys dropped by elites
  slot_machine.gd    the chest slot machine (three reels of your abilities, real odds)
  chest.gd           Bronze / Silver / Gold chest (placeholder: rewards TBD)
  powerup_manager.gd elite power-up drops and timed effects
  nuke_blast.gd      the NUKE power-up's wave of kills, mushroom cloud, flash and shockwave
  nuke_model.gd      the NUKE pickup (cartoon atomic bomb, radiation trefoil texture)
  powerup_icon.gd    2D power-up icons (minimap, HUD)
  minimap.gd         the HUD minimap: blips, map context, boss safe / danger zones
  tree_fire.gd       trees set alight by the Meteor, charring over 15 s
  splash.gd          startup logo video, skippable
  title.gd           title screen: swamp diorama, burning title, menu
  character_select.gd  roster grid + preview panel (data/characters.json)
  character_icon.gd  procedural character portraits
  hud.gd             all UI, built in code
  loader.gd          autoload: every scene change, behind the loading screen with rotating tips
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

**Playtest bot** (`tools/playtest.gd`): plays real runs and reports wins and deaths.
`godot --headless --fixed-fps 60 --path . res://tools/playtest.tscn -- --chars=thunder_wizard --runs=5 --map=forest --out=results.txt` writes one line per run, plus a JSON line per run to `results.txt.jsonl` (upgrades in order, pickups, and on a death the **last 10 s**: HP, goblins within 8 m and what was touching it). While a boss is up it logs his health and distance every 15 s. It kites the horde, dodges boss markers and steps out of boss clouds, drifts back toward a boss more than 26 m away, hops while Overcharge is up, and picks upgrades from a fixed priority list. It doesn't go after potions, so a person does better. `--boss-at=T` brings the boss early. Two processes in parallel suit a 2-core machine.

```bash
# Full headless smoke test: bot plays, 1400-enemy stress phase, death screen, restart
godot --headless --path . --fixed-fps 60 -- --smoketest --smoke-seconds=240

# Gameplay spec tests (abilities, burn/explosions, epics, potions, shield, immunity)
godot --headless --path . res://tools/test_abilities.tscn

# Screenshot: cast Meteor at 1 s, capture at 4 s
godot --path . -- --shot=/tmp/shot.png --shot-at=4 --shot-cast=0@1 --shot-spawn=120

# Desert tests (sphinx, pyramids baked into the ground and climbable, zombies instead of goblins
# and climbing, vultures landing, walking and pecking (on a summit too), mummies' curse, the Pharaoh's attacks and Wrath)
godot --headless --path . res://tools/test_desert.tscn

# Ashen Caldera tests (lava carved into the ground and burning you, stepping stones and bridges,
# eruption bombs, imps/bats/golems/slugs instead of goblins, Singe's attacks and Caldera Eruption)
godot --headless --path . res://tools/test_caldera.tscn

# Graveyard tests (headstones, crypts, chapel, railings; ghouls instead of goblins; ghosts float,
# drift through crypts, chill you and can be shot; the dead rise from graves; the Necromancer)
godot --headless --path . res://tools/test_graveyard.tscn

# Swamp tests (pool size/depth, recessed collision, 50% speed and jump in water)
godot --headless --path . --fixed-fps 60 res://tools/test_swamp.tscn

# Pause menu / settings tests (tabs, Apply/revert, languages, music + SFX volume and mute, rebinding)
godot --headless --path . res://tools/test_settings.tscn

# Run clock spin-up/countdown, Play mode cards, Quickplay, Unrelenting, Ghast's feat, weapon hover
godot --headless --path . res://tools/test_modes.tscn

# Run-start entrances: every character on the outdoor maps, its own entrance, lands once, hurts nearby goblins
godot --headless --fixed-fps 60 --path . res://tools/test_entrances.tscn

# Intro cinematic (splash -> intro -> title, cast, skip)
godot --headless --path . res://tools/test_intro.tscn

# Minimap (layout, blips, toggle, boss safe zones) and the NUKE power-up in a run
godot --headless --path . --fixed-fps 60 res://tools/test_minimap.tscn

# Chests, keys, the slot machine (odds, reels, rewards) and ability levels
godot --headless --path . --fixed-fps 60 res://tools/test_chests.tscn

# Loading screen (autoload, shown into a run and back, tips rotate and are translated)
godot --headless --path . res://tools/test_loading.tscn

# Title flow (splash -> title -> settings -> play -> main menu)
godot --headless --path . res://tools/test_title.tscn

# The Forest and Castle bosses (telegraphs, minimum warning, wall climbing, unlocks)
godot --headless --path . res://tools/test_bosses.tscn

# Sub-bosses and waygates (Swamp: 2:00 / 4:00 Bog Shamans, their telegraphs, the linked portals and cooldown)
godot --headless --fixed-fps 60 --path . res://tools/test_subboss.tscn

# Thog the Troll (arrives at 8:00, attacks, enrage, must die to win, unlocks)
godot --headless --path . res://tools/test_boss.tscn

# After the boss: shards on the ground, no more spawns, the portal per map, walking in wins
godot --headless --path . --fixed-fps 60 res://tools/test_portal.tscn

# Castle (layout and reachability, door walk-in, feast physics, skeletons throwing bones)
godot --headless --path . res://tools/test_castle.tscn

# Character select (roster data, locked/unlocked, preview, back, play)
godot --headless --path . res://tools/test_character_select.tscn

# Character bonuses (3 per card, Gaiden's numbers, applied in a run, jump apex, bar tiers, LVL on every card)
godot --headless --fixed-fps 60 --path . res://tools/test_bonuses.tscn

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
