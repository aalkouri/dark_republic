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

The game opens with the **AtomAI** studio logo (`video/atomai_logo.ogv`, converted to Ogg Theora for Godot), then the **anime intro** (`video/intro_anime.ogv`, played by `scenes/intro.tscn` / `scripts/intro.gd`, about 30 s, sound effects on the SFX bus). Made with Higgsfield from the game's own character models: the Fire Wizard, Ogre, Vicki, Gaiden and Dr. Croc are asleep in the castle barracks when a stampede shakes the walls; the wizard whistles everyone awake, they rush to the battlements, see Thog the Troll leading the goblin horde, leap into battle, and the wizard ends it as the Meteor. Any key, click or gamepad button skips the logo and the intro. The intro plays on the **first launch only**: once shown it switches **Settings > Gameplay > Play intro on startup** off, and turning that back on replays it next launch. Pass `-- --skip-intro` to go straight to the title (tests and screenshots skip both automatically).

Then the **title screen**: a living swamp diorama at night. The camera slowly orbits the fire wizard on a mossy stone dais while goblin silhouettes with glowing eyes lurk, creep in and grunt in the fog. "DARK REPUBLIC" burns in Cinzel lettering (`fonts/Cinzel.ttf`, SIL Open Font License) over a Play / Settings / Quit menu (mouse, keyboard or gamepad). The pause menu and end screen have **Main menu** to return here.

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

## Character select

**Play** on the title opens a roster of 25 champions plus 5 mystery slots (shown only as "?"): a 6-wide grid of portraits plus a preview panel with name, epithet, bio and kit. **The Fire Wizard** plays from the start; the **Ice, Thunder and Dark Wizards** are playable once bought. Characters with a model preview as it in 3D, and Play starts a run. The other 22 (Ice Wizard, Merlin, Thunder Wizard, Dark Wizard, Ogre, Ghast, Vampire Hunter, Vicki, The Rogue, Gaiden, Dr. Croc, The Arachnid, Blob, Death, Billy Bulldog, Cowboy, Loco Robotico, Singe, An Argyle Sock, Sentient Platypus, Kong, Thog the Troll, Bog Witch, Toadstool Knight) show a padlock and a large portrait. Portraits are drawn in code (`character_icon.gd`) from each character's traits in `data/characters.json` (body, head, headgear, beard/hair, eyes, signature item, particle motif), so adding a character is a JSON entry. **Unlocking with coins:** each locked tile shows its price: 2,000 for the Ice, Thunder and Dark Wizards, 7,000 for Merlin and 10,000 for everyone else. Selecting a locked character shows its unlock requirements as chips with a tick or a cross under "LOCKED · to unlock:" (coins for everyone; **Thog the Troll** also needs beating him in the Swamp, and the **Ghast** needs 15:00 in the Swamp on Unrelenting), and turns Play into **Unlock**, which works once every requirement is met and spends the coins. Bought characters get their skill tree and level straight away. Only characters with a model and abilities can be played: the four wizards, Merlin, Ogre, Ghast, Vampire Hunter, Vicki, the Rogue, Gaiden, Dr. Croc, Thog (on the Ogre's model for now) and An Argyle Sock (built in code). The rest show "playable soon" until they're built.

The preview panel shows the character's level (**LVL N**) in its top-left corner with the EXP towards the next level and a thin bar under it, and the signature weapon's icon and name in the top-right corner; hover the weapon for its damage, attack rate and what it does. Ability names live in the hover tooltips. Each character has a saved level (`lvl`, kept with the coins in `user://progress.cfg`). Tiles show **lvl N** in the bottom-left corner when it's 1 or more, and nothing at 0. Mouse, keyboard and gamepad all work; Esc goes back.

## Character kits

Every character has a designed kit in `data/abilities.json`: a starting weapon plus three abilities on the same keys and unlock levels as the Fire Wizard (**1** from the start, **2** at run level 5, **3** the ultimate at level 10). Cooldowns and numbers are balanced against his kit (about 30 s / 45 s / 2 min; 80-160 damage for the level-5 ability, 200-400 for ultimates).

**On the select screen**, every character shows its weapon and its three ability squares. Hover one for the full description with cooldown and numbers (`KitDB.describe_lines`; `{braces}` in the JSON mark highlighted numbers). Icons are drawn in code by `scripts/ability_glyphs.gd` from each ability's `"icon": {"glyph", "color"}` (36 glyphs). To preview them all: `godot --path . --script res://tools/render_ability_icons.gd -- /out.png`.

**In runs**, every character with a body is playable: the four wizards, Merlin, Ogre, Ghast, Vampire Hunter, Vicki, the Rogue, Gaiden, Dr. Croc, Thog and An Argyle Sock. The others are designs until each character is built (they show "playable soon" once bought).

## The Ice, Thunder and Dark Wizards

Each plays as its own rigged Higgsfield model (`models/<id>/`, Lean clip set: idle, run, hit, attack, ability) driven by `RosterHero` (`scripts/roster_hero.gd`): idle/run blend by speed, and the staff thrust, hit flinch and ability casts play on the upper body so the legs keep running. The staff comes from `RosterWeapons`, and shots leave from its head. Each arrives as a comet in its own colours instead of the flaming head, and only the Fire Wizard leaves ash footprints.

**Weapons** (the starting `weapon_orb` card is renamed and re-iconed per character, and levels up the same way):

| Character | Weapon | Effect |
|---|---|---|
| Ice Wizard | Frost Shards | Icicles that slow goblins 30% for 2 s |
| Thunder Wizard | Chain Lightning | Instant arcs that jump to 4 more goblins (+1 per pierce) within 6 m, losing 20% per jump |
| Dark Wizard | Shadow Bolts | Slow bolts (60% speed) that pierce 2 more goblins; 20% chance to curse (+25% damage taken for 4 s) |

**Abilities** (`scripts/roster_kit.gd`; damage numbers scale with Damage, % of max HP doesn't):

| | 1 (start) | 2 (level 5) | 3 Ultimate (level 10) |
|---|---|---|---|
| **Ice** | **Flash Freeze** (30 s): goblins within 15 m frozen solid for 3 s; frozen goblins can't hurt you, take +50% damage and shatter on death for 40% of their max HP within 2 yd (chains) | **Glacial Path** (45 s): +60% speed for 6 s; your ice trail lasts 5 s, slows 60% and deals 15/s | **Absolute Zero** (2 min): 25 m blizzard on you for 8 s (80% slow, 4% max HP/s), then everything inside freezes for 2 s and shatters for 200 |
| **Thunder** | **Overcharge** (30 s): +40% speed for 8 s; every jump and landing shocks 6 m for 40 | **Thunderclap** (45 s): 12 bolts on the goblins with the most HP within 25 m: 120 each, 1.5 s stun | **Storm Lord** (2 min): a thundercloud follows you for 10 s, striking a goblin within 18 m every 0.25 s for 90, chaining to 3 more |
| **Dark** | **Siphon** (30 s): goblins within 12 m lose 6% max HP/s for 4 s; you heal 1 HP per goblin per second (max 5% of max HP/s) | **Raise Dead** (50 s): 15 dead goblins (fresh corpses first, the rest claw out of the bog) fight for you for 15 s (25 per hit), then explode for 60 in 3 m | **Eclipse** (2 min): the world goes dark for 8 s; goblins lose track of you and wander, you deal +100% damage, and every kill sends a shadow wisp at a goblin for 60 |

**Goblin statuses** (`enemy_manager.gd`): slow, freeze, stun, curse, the Eclipse wander, and shatter explosions, shown in the goblin shader as icy, frosted or shadowed. Frozen and stunned goblins stand still and deal no contact damage. Raise Dead's allies (`ally_crowd.gd`) reuse the goblin's baked mesh and animations, shadow-tinted. Lightning everywhere is `lightning_fx.gd` (one additive MultiMesh of jagged segments).

## Merlin, Ogre, Ghast, Vampire Hunter, Vicki, Rogue, Gaiden, Dr. Croc, Thog and An Argyle Sock

These run on the same `RosterHero` model player (clip segments per character in `RosterHero.CFG`). The Ghast's model has no skeleton, so it hovers and sways, lunges when it attacks and swells when it casts. **Thog** has no model of his own yet: he plays on the Ogre's rig (`"model": "ogre"` in his CFG entry) with the troll-blue skin the Swamp boss uses, 20% bigger, holding a bigger club; giving him a real model later is a matter of adding `models/thog/` and dropping that line. He's bought for 10,000 coins after beating him in the Swamp, and can't pick the Swamp (it's his home turf).

**An Argyle Sock** has no model at all: `SockBody` (`scripts/sock_body.gd`) builds it in code - a knitted tube bent into a sock (ribbed cuff, leg, heel, foot, toe), about 1.45 m tall, with googly eyes whose pupils wobble on springs. The shader draws the argyle diamonds and criss-cross yarn from the UVs (crisp at any size), bends the sock as it leans and lunges, squashes it as it hops along, and crackles yellow as Static Cling charges up. `RosterHero.CFG` marks it `"procedural": "sock"`; character select shows it idling the same way.

**Weapons** (`weapon_system.gd`). Damage and fire rate are the orb stats scaled by the weapon's own `damage` / `every` in `data/abilities.json`, so every weapon levels up through the same card. On melee weapons, extra count widens the reach.

| Character | Weapon | Effect |
|---|---|---|
| Merlin | Arcane Bolts | Homing bolts that bounce on to 2 more enemies |
| Ogre | Tree Trunk | 120° cleave, 3 m, heavy knockback (360° in Swamp Rage) |
| Ghast | Wail | 8 m cone that hits everything in it and slows 25% |
| Vampire Hunter | Silver Bolts | Fast bolts that pierce 3 enemies, double damage to epics and bosses |
| Vicki | Valkyrie Spear | 6 m piercing thrust; every 4th throw is a javelin flying 25 m |
| Rogue | Twin Daggers | Short-range throws in pairs; hits bleed 3% of max HP/s for 3 s |
| Gaiden | Katana (only drawn while he attacks) | 3-hit combo in a 3 m arc; the 3rd cut sends a 10 m wind slash |
| Dr. Croc | Volatile Flasks | Lobbed vials that shatter with breaking glass: 3 m burst, then a lumpy, bubbling acid puddle (4% of max HP/s) |
| Thog | Big Club | Slow overhead smash in a long 9 m, 100° cone for 90 damage, throws enemies back 8 m. Thog starts with **250 max HP** (everyone else 100): with no projectile he fights up close |
| An Argyle Sock | Static Cling | Zaps the 3 nearest enemies (18 each, every 0.6 s); moving builds a charge up to 2x |

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

New goblin statuses for these: flee, frog, possessed and bleed/acid (`EnemyManager.scare / frog / afflict`, `ally_t`). Frogs, possessed and fleeing goblins can't hurt you. Sounds come from `tools/gen_kit_sounds.py`. **Test:** `godot --headless --path . res://tools/test_kits.tscn [-- --only=<id>]` plays each of the nine and checks its model, weapon and all three abilities. Thog's sounds come from `tools/gen_thog_kit_sounds.py`, the sock's from `tools/gen_sock_sounds.py`.

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
| Singe | Fast fire imp who sets the ground ablaze | Cinder Toss | Hotfoot | Flashover | Supernova |
| An Argyle Sock | Odd little whirlwind with static shocks | Static Cling | Spin Cycle | Lost Pair | Laundry Day |
| Sentient Platypus | Poison-kicking scholar with sleep and eggs | Venom Spur | Electro-Bill | Egg Clutch | The Lecture |
| Bog Witch | Hexer who curses and drowns the horde | Ladle of Bile | Bubbling Cauldron | Hex of Silence | Swamp's Fury |
| Toadstool Knight | Brave little defender with spores and summons | Spore Blade | Fungal Shield | Fairy Ring | The Fungus Court |
| Kong | Brawler who throws the swamp at goblins | Shackle Swing | Chest Pound | Log Toss | Rampage |
| Thog the Troll | Slow, heavy smasher who controls space | Big Club | Toll Booth | Goat Charge | Bridge Collapse |

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

## Elemental shards

A second, persistent currency for upgrading your main weapon (the upgrade menu comes later). There are four kinds, **Fire, Ice, Lightning and Dark**, each drawn as a faceted crystal in code (`scripts/shard_icon.gd`). Their counters sit just left of the coins at the top of the screen, starting at 0. **Every boss you defeat drops 1-5 shards** of random kinds (Thog, the Toadstool Knight, the Arachnid and the Goblin Warlord). They're banked at once (`Wallet.shards`, saved in `user://progress.cfg`), flashed on screen, and listed under **Shards won** on the end screen.

## The Forge (weapon upgrades)

Shards forge a character's signature weapon, up to **level 10** (`scripts/forge.gd`, menu in `forge_menu.gd`). Each weapon has its own recipe of **5 shards**; level 1 costs exactly those, and each later level scales the recipe up: **5, 10, 15, 20, 30, 40, 50, 60, 75, 100** shards.

| Weapon | Recipe (x1 at level 1) | Weapon | Recipe |
|---|---|---|---|
| Fireballs (Fire Wizard) | 5 fire | Twin Daggers (Rogue) | 2 lightning, 3 dark |
| Frost Shards (Ice Wizard) | 5 ice | Katana (Gaiden) | 1 fire, 2 lightning, 2 dark |
| Chain Lightning (Thunder Wizard) | 5 lightning | Volatile Flasks (Dr. Croc) | 2 fire, 1 ice, 2 dark |
| Shadow Bolts (Dark Wizard) | 5 dark | Big Club (Thog) | 2 fire, 2 ice, 1 dark |
| Arcane Bolts (Merlin) | 1 fire, 2 ice, 2 lightning | Static Cling (An Argyle Sock) | 3 lightning, 2 dark |
| Tree Trunk (Ogre) | 3 fire, 2 dark | Silver Bolts (Vampire Hunter) | 2 ice, 3 lightning |
| Wail (Ghast) | 1 ice, 4 dark | Valkyrie Spear (Vicki) | 2 ice, 3 lightning |

- **On the character select,** the next level's shards sit under the weapon icon. For small costs that's one crystal per shard, lit as you collect them; for bigger ones, one crystal per kind with the count, lit when you have that many. When you have them all, the weapon **pulses** while **green plus signs** pop in and out around it. Click it to open the Forge.
- **The Forge** shows the weapon, the shards the next level costs, the weapon's stats now and after forging, and a **Forge Weapon** button (an anvil clang and sparks).
- **Every level:** **+25% damage** and **+8% attack rate**, stacking; levels 4 and 8 add **+1 projectile** (or hit / reach on melee weapons). **Fireballs** also gain a special at level 1: **every 5th hit explodes** like a level 1 Blast Bomb.
- **Everywhere:** forging applies to the weapon wherever it's used. That means your own starting weapon, and also its **Legendary card** when another character pulls it in a run. Forge levels are saved (`Wallet.forge`).
- **Tests:** `godot --headless --path . res://tools/test_forge.tscn`. Screenshots: `res://scenes/character_select.tscn -- --shot-char=argyle_sock --shot-shards=fire,ice,lightning,dark [--shot-forge]`.

## Pause menu and settings

**Esc** opens the pause menu: Resume, Settings, Restart run, Quit to desktop. Changes apply live so you can try them, but they're only saved (to `user://settings.cfg`, applied on startup) when you press **Apply**. Leaving with Back or Esc puts everything back as it was.

- **Gameplay:** a **Language** dropdown with English, Español, Français, العربية, Deutsch, 中文 (简体) and 日本語. It takes effect on Apply, and all game text switches: menus, the HUD, cards, tooltips, character bios, ability and weapon text, and the title taglines. Also **Play intro on startup**.
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
| 3 | **Meteor (ultimate)** | 2 min | Trees, fallen trees and bushes in the blast catch fire and burn, then crumble away leaving a smoking scorch mark. The wizard vanishes (invulnerable, untouchable) and becomes a giant flaming copy of his own head, which crashes where you aim 3 s later: 250 dmg (scales with Damage) in 8 m plus knockback. He reappears at the crash site, and the ground burns for 3 s, dealing 3% of max HP per second to goblins in a 7 m radius |

**Attacks:** his starting weapon hurls **Fireballs**. Each time it fires, he swings his staff down at the target and the fireballs launch from the staff tip.

**Look:** red coat made of animated flames whose back trails along the ground as a train, a two-handed grip on his fire staff, a wrinkled, grimy crimson hat with a wavy brim and a tip that flops to the right, a tarnished gold band, ember eyes, a fire staff, and ash footprints that fade within a second.

**Collisions:** when an enemy touches you, you take its contact damage (shield first), become immune for 0.5 s (shown by dimming the character 50%), and you and the enemy are knocked apart. Enemies that run into you while you're immune bounce back opposite to the way they were heading.

**Epic enemies:** each spawn has a 5% chance to be epic, plus 10% per point of Luck. A Tome of Luck level is 0.1 Luck (+1%), and the Fortune skills give 0.5: 1.5x size, 4x HP and a purple tint. An epic has a 15% chance to drop a potion (`PotionManager.DROP_CHANCE`). Which potion:

| Potion | Chance | Effect |
|---|---|---|
| Purple | 30% | Every ability's cooldown is reduced by 30% of its full duration ("-Ns" pops up above each ability that was cooling down) |
| Red | 50% | Heal 10% of max HP (a red "+N" pops up next to the health bar and above the wizard) |
| Blue | 20% | Shield worth 10% of max HP (absorbs damage first, stacks) |

Potions lean and spin slowly so they're easy to spot. They never despawn and there's no limit on how many can lie around: they wait until you pick them up.

**Power-ups:** each elite kill also has a 2% chance to drop one of these, plus 10% per point of Luck (+1% per Tome of Luck level):

| Power-up | Effect |
|---|---|
| Magnet | Every XP orb on the map flies to you |
| Fear Idol | All goblins run away from you for 15 s |
| 5x Damage | All damage you deal is multiplied by 5 for 10 s |
| Movement Enhancer | +80% move speed for 15 s |

Picking one up while it's active refreshes its timer; active power-ups and their timers show under the run timer.

## Maps

**Play** (on the title screen or character select) first asks which map: **The Swamp**, the **Magical Forest** or **The Castle** (`scripts/map_picker.gd`, previews in `images/maps/`). The Forest is **locked until you beat Thog the Troll**, the Swamp's boss, and the Castle until you beat **the Toadstool Knight**, the Forest's boss; locked cards are darkened, carry a gold padlock and say what's needed. The first time the picker opens after a map is unlocked, its card starts locked, then the padlock rattles, the shackle springs open and the lock tumbles off the bottom of the screen as the card lights up and becomes selectable (each reveal plays once: `Wallet.seen_unlocks`). A character can be barred from a map (`banned_maps` in `data/characters.json`): each boss can't play its own map, since it's their home turf (Thog the Swamp, the Toadstool Knight the Forest, the Arachnid the Castle). The choice is kept for Restart and the next Play (`Settings.selected_map`). Test and screenshot runs take `--map=swamp|forest|castle`, `--shot-nohud` hides the HUD for clean pictures and `--shot-pos=x,y,z[,yaw]` puts the wizard somewhere.

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

### Fire in the woods

Trees, fallen logs and bushes all burn (`TreeFire`, `BushField.ignite`). The Fire Wizard's Meteor lights everything in its blast. **Every other character's ultimate** sets the woods around them ablaze too (`Abilities.ULT_FIRE_RADIUS`: 10-30 m depending on the ultimate's reach). A tree burns for 15 s and a bush for 7 s, charring black. Then the remains crumble into the ground and are **gone**, collision and all. Each leaves a **scorch mark** (`scripts/scorch_mark.gd`) for the rest of the match: a black patch draped over the ground and ringed with ash, glowing embers, a thin column of smoke, and a quiet looping sizzle (`audio/forest/sizzle.wav`) you hear within 16 m. Nothing burns twice.

## The Castle

`scripts/castle_builder.gd` (props in `castle_props.gd`). An enclosed keep on the same 440 m footprint, with the same counts as outdoors: about 250 furniture props, 24 landmarks and 28 chest sites.

- **Layout:** mostly huge open halls with few corridors. The **great hall** (with columns and a red carpet) is behind the front doors. North of it is the **dining hall** with its table, flanked by two **galleries**, and the **throne room** with a raised throne is at the far end. The side wings are the **barracks, armoury, library and chapel**. Wide archways join the rooms, and two short 8 m corridors are the only tight spots. The building has stone walls, flagstone floors and a 24 m timbered roof, so the Meteor and sky bolts start under it.
- **The entrance:** a run starts on the porch outside. The wizard walks in through the 12 m front doors, they swing shut with a boom, and the run starts. The doors stay shut for the rest of the run.
- **Lighting:** wall torches, iron chandeliers and braziers. Banners and stained-glass windows line the walls. Furniture (benches, bookcases, crates, barrels, banners) burns.
- **The feast** (`castle_feast.gd`): a 35 m table in the middle of the dining hall, with benches, set with about 180 plates, goblets, roast pigs, chickens, bread, cheese, pies, grapes, jugs and candlesticks. Each one is a real rigid body under normal gravity, asleep until disturbed. Walk along the table and you kick dishes flying, and landing on it kicks harder. Explosions and Fire Nova blast everything near them off the table (via `FxManager.burst_fired`). Goblins can't climb on the table, so they run around it. **Don't loiter up there:** stand on the table for 2 s and a chandelier snaps loose over the spot where you stood. A red marker fills on the table for 1 s, then it crashes down for 15% of your max HP if you're still under it, smashing the dishes around it. Stay put and another follows every 2 s. Sounds: `tools/gen_castle_sounds.py`.
- **Pathfinding** (`castle_nav.gd`): a 2 m walkable grid with a flow field rebuilt around you about 3 times a second. Goblins follow it through doorways and around the table instead of piling up against walls, and they slide along walls rather than through them. Spawns only appear on floor that can reach you.
- **Skeletons** (`skeleton_crowd.gd`), indoors only: 35% of castle spawns are skeletons (the overall spawn rate is the same as outdoors). **Armoured skeletons** are their epic version, with a helmet, breastplate and shield. Skeletons walk and claw like goblins, but at 3–17 m with a clear line of sight they stop and **throw bones**. Each bone flies in an arc, leads your movement, hits for 70% of their contact damage (armoured ones hit harder), and shatters on walls and the floor. Their throws clear the table, so standing on it won't keep you safe. Killed skeletons collapse into a scatter of bouncing bones, with a clatter. The models are procedural with a vertex-shader walk, claw and throw, drawn as two MultiMeshes.
- **Sounds:** the door slam and the bone clatter are synthesised by `tools/gen_castle_sounds.py`.
- **Tests:** `godot --headless --path . res://tools/test_castle.tscn` checks the counts against the swamp, that every room is reachable, the walk-in and the shut doors, food kicks and blasts, and skeleton throws, hits and collapses.

## The swamp

Every run generates a new dark swamp (`scripts/world_builder.gd`):

- **Sky:** 50% chance of a gloomy day with the sun glowing through dense clouds, 50% chance of a moonlit night with very few clouds and stars. Lighting, ambient light and fog follow.
- **Size:** 440 × 440 m (`ARENA_HALF = 220` in `scripts/main.gd`), with stone walls round the edge.
- **Terrain:** rolling hills, dips and slopes from two layers of smooth noise: broad hills of up to about ±6.5 m and smaller rolls on top. Every slope stays walkable (under 40°). The start point, every pool and every chest site sit on level pads that ramp gently back into the hills. Near the walls the ground climbs into a berm about 7 m high. Everything follows the ground: goblins, drops, trees, grass and the flat ability markers. The Meteor target, Fire Nova's ring and glow, and the Stink Aura are `GroundDisc`s that drape over the slopes. The terrain is baked into a 1 m height grid (`SwampWater.build_terrain`) that collision, the ground mesh and gameplay all share. To tune it, change `HILL_HEIGHT`, `HILL_FREQ`, `BUMP_HEIGHT` and `EDGE_RISE` in `scripts/swamp_water.gd`.
- **Ground:** random patches of wet mud and swamp grass, with swaying grass tufts.
- **180 swamp trees** in 4 variants: bald cypress (flared trunk, knees, hanging moss), dead snag, swamp willow (drooping curtains) and mangrove (stilt roots). All collide with the player.
- **72 fallen trees:** mossy logs with root plates, slightly tilted, which you can climb and jump off.
- **14 big pools of swamp water:** irregular ponds 18-36 m across, at least 66 m apart, recessed into the ground with uneven beds, never deeper than the character. Reeds and cattails grow around the edges. **In water, move speed and jump height are halved** (goblins wade at half speed too).
- **24 mossy stone ruins** as landmarks.
- **Camera zoom:** the mouse wheel zooms the camera in and out (up to 16 m away). All the way in is first person: the camera sits at the wizard's eyes and he's hidden from view, though his shadow stays. The chosen distance is kept between runs (`Player.zoom`).
- **Entrance:** each run opens with the wizard arriving as his own Meteor. For the 3 s it takes to fall, the clock, the spawns and the goblins all hold still and nobody can act. It falls silently and lands with the full impact (explosion sound, no scorched ground), and the run starts (`Abilities.entrance_meteor`, `main.intro`). Screenshot and smoke runs skip it unless you pass `--shot-intro`.
- **Title tagline:** 44 Dungeons & Dragons puns (none about dice) (`data/taglines.json`) rotate under the logo every 5 s with a crossfade. They play in shuffled order, all of them before any repeats. To add your own, edit the list.
- **Upgrade overlay:** the bottom-left corner shows everything you own as icons with their level: weapons and items on the top row, tomes underneath, in the order you got them. On a reward card, the level it will become (for example "Lv 2") sits to the right of its icon.
- **Signature weapons:** every unlocked character's weapon can turn up for the other characters as a rare Legendary level-up reward, under 1% of cards. It fires alongside your own weapon, levels up to 5 and counts as one of your 3 weapons (`WeaponSystem.add_signature_weapons`). **One per run:** once you take one, its level-up cards come up as often as any other weapon's (`UpgradeDB.weight_of`), and no other character's weapon can be pulled for the rest of the run.
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

- **Must be killed to win:** the 10:00 mark no longer ends a Swamp run; you win when Thog falls (he topples backwards into the bog, gems fly to you, and the end screen says **THOG DEFEATED!**). Any level-up choice still open then is skipped.
- **Enrage:** if he's alive 2 minutes after arriving (10:00) he **enrages**: his attacks come **twice as fast** (animations, wind-ups and the pauses between them), though every telegraph still gives at least 1 s of warning, his skin smoulders red and flames pour off him, and the bar turns red.
- **Three attacks,** each telegraphed on the ground in red that fills up until it lands:
  - **Slam** (close): both fists overhead and down into the ground in front of him: 40 damage in the marked circle, then a **shockwave ring** rolls out to 20 m (22 damage; **jump over it**).
  - **Sweep** (close): his club swung across a 130° wedge in front of him, 14 m long: 32 damage and a big sideways knockback.
  - **Bellow** (at range, every 14 s): a roar that calls a ring of 14 goblins and a brute around you.
- **The Quake** (at **75%, 50% and 10% health**): Thog stomps the ground over and over, shaking your camera the whole time, while **the entire map lights up red except the swamp pools** (their shores glow green). You have **7 seconds to get into a pool**. If you're anywhere else when it lands, it takes **50% of your max HP straight through your shield** and wipes the shield out.
- **Under the hood:** Thog is a crowd row in `EnemyManager` (type `TROLL`, 5,200 HP x the 8:00 HP multiplier, about 33,000), so every weapon, burn, freeze, curse and ability hits him; he isn't drawn as a goblin. Knockback doesn't move him, freezes last a third as long and stuns a quarter. Frozen or stunned he can't start an attack. He mostly alternates slam and sweep.
- **Model:** a stand-in until Thog gets his own: the Ogre's rigged model with its skin re-tinted troll blue (`models/ogre/thog_skin.jpg`) and the Ogre's club, scaled up 4.4x. Slam, sweep and bellow are segments of the Ogre's attack, ability and hit clips (`tools/render_thog.tscn` renders contact sheets of them).
- **Rewards:** beating him the first time unlocks the Magical Forest and makes Thog buyable (10,000 coins). The end screen shows an **UNLOCKED!** block: one card per unlock (NEW MAP / NEW CHAMPION, with a hint for what to do next), each flying in from off screen on a swirling, spinning spiral trailing sparks, then landing in its slot with a pop, a flash, a burst of sparks and a ding. The list is read from the data (maps that `require` the boss, characters with `requires_boss`), so future bosses get it for free. Screenshot: `--map=swamp --shot-boss-win=1,3`. Saved in `user://progress.cfg` (`Wallet.bosses_defeated`).
- **Sounds:** roar, slam, sweep, footsteps and the fall are synthesised by `tools/gen_thog_sounds.py`.
- **Tests:** `godot --headless --path . res://tools/test_boss.tscn`. Screenshots: `--map=swamp --thog-at=0.2 --shot-thog=distance,side-angle [--thog-enraged]`.

## The Toadstool Knight (the Magical Forest boss)

`scripts/toadstool_boss.gd`, body in `scripts/toadstool_model.gd`. At **8:00** a 6 m mushroom-capped knight marches out of the trees. Like Thog, he enrages 2 minutes after arriving and must be killed to win the Forest.

- **Spore Slash** (close): an overhead cut across a 120° wedge in front of him (34 damage). It leaves a violet spore cloud that hurts while you stand in it.
- **Fairy Ring:** a ring of mushrooms bursts out of the ground around you (30 damage). The red band shows where it will burst, so step into the middle or out past it.
- **Spore Mortar** (at range): he lobs 5 spore pods (7 when enraged) at and around you. Each flies in an arc onto its own filling circle (20 damage) and leaves a small poison puddle.
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
- **Model:** built entirely in code. A glossy black-violet body with a red hourglass, eight red eyes and fangs, and eight two-jointed legs that walk themselves: each foot stays planted until the body has moved on, then steps, in alternating groups of four. Two-bone IK bends the knees away from whatever she's standing on, so the same legs work on the floor, a wall or the ceiling (`tools/render_spider.tscn` previews it).
- **Rewards:** beating her makes her buyable (10,000 coins). She can't play the Castle.

## Boss rules (all bosses)

`scripts/map_boss.gd` (`MapBoss`) holds what the Forest and Castle bosses share: the crowd row (type `TROLL` with each boss's own numbers), the HUD health bar and enrage countdown, sounds, and the attack helpers.
- **Fair warning:** every attack that lands somewhere is marked on the ground first (circles, wedges, lanes and rings), filling up red until the hit lands. It never fills in less than **1 second** (`MapBoss.MIN_WARN`), even when enraged; enraged bosses are faster, but never faster than that. Thog follows the same rule.
- **Heavy hitters:** every boss's damage (attacks, hazards and contact, Thog and the Goblin Warlord included) is multiplied by `EnemyManager.BOSS_DAMAGE_MULT` (**1.75x**).
- **Projectiles:** lobbed projectiles land exactly when their marker fills.
- **Lingering zones:** spore clouds, puddles and webs are drawn for as long as they last.
- **Sounds:** synthesised by `tools/gen_boss_sounds.py` (`audio/bosses/`).
- **Tests:** `godot --headless --path . res://tools/test_bosses.tscn`.
- **Screenshots:** `--map=forest|castle --boss-at=0.3 --shot-thog=distance,angle`.

## Chests, keys and the slot machine

Each run places **8-28 chests** on level pads around the map: **Bronze** most often (60%), **Silver** sometimes (30%), **Gold** rarely (10%). A chest only opens with a **key of its tier**: walk up to it with the key and it opens; without one it says which key it needs. **Elites drop keys** (12% of them): bronze usually (65%), silver sometimes (27%), gold rarely (8%). Keys spin on the ground until you pick them up, show at the top of the screen while you hold them, and don't carry over between runs. The **key counter** sits at the bottom left, above your upgrades: a bronze, silver and gold key with how many you hold.

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

## Shields

Shields (blue potions, Shield Wall, Fungal Shield, Rewind) soak up damage before your HP. When damage brings a shield to 0 it **breaks with a glass-shatter sound** (`audio/ui/shield_break.wav`, from `tools/gen_shield_sounds.py`; `Player.shield_broken`).

## Goblins

Every enemy is a goblin (contact damage was doubled: 16 / 12 / 32, boss 70): about half the wizard's height. The model is a textured, rigged Higgsfield/Meshy goblin (`models/goblin/`): hunched, warty, with big ears and clawed hands. Types differ by size and colour grade: Goblin, Goblin Scamp (small, fast, yellowish), Goblin Brute (big, grey) and the Goblin Warlord boss (huge, dark red).

**Animation:** goblins charge head-down (run cycle speed matched to their ground speed) and throw punch combos when they reach the wizard. The crowd can reach 1,400, so instead of skeletons the clips are **baked into vertex-animation textures** (`tools/bake_vat.gd`). The goblin shader (`vat_crowd.gd`) replays them per instance from the MultiMesh, with each goblin's clip and phase in its instance colour. That keeps the whole crowd in one draw call.

**Death:** killed goblins play a fall-backwards death animation, lie on the ground (charred if they died burning), then sink away 3 s after death.

**Sounds:** goblins are silent while alive, with no voices or grunts. When one dies within 30 m, a short "splat-pop" plays from where it fell. There are 4 variants, and bigger goblins sound deeper. Death sounds are limited to about 20 per second, so mass kills sound like a crunchy volley. The clips (`audio/goblin/death_*.wav`) are synthesised by `tools/gen_goblin_death_sounds.py`, and the player is `scripts/goblin_audio.gd`.

## Combat feedback

- **Health bars** over every goblin (green → yellow → red; purple border on epics), hidden beyond 45 m.
- **Damage numbers** for every hit: they pop in small, swell big, settle, then float up and fade, all within 0.75 s. Burn damage is totalled and shown in orange twice a second.

## What's in the slice

- **Run structure:** 10-minute run, spawn rate and enemy HP scale with time, a swarm ring every minute. On the Swamp, **Thog the Troll** arrives at 8:00 and the run is won by killing him (see *Thog the Troll*); on the other maps a Goblin Warlord comes at 5:00 (his death vacuums all XP) and surviving 10:00 wins.
- **5 weapons:** Fireballs (auto-targeted, pierce), Stink Aura (damage field), Ground Slam (knockback nova), **Thorns** (anything that hits you takes 2x its damage back, +35% a level) and **Ice Aura** (everything within 5.5 m is slowed 40%, wider and colder each level). Thorns and Ice Aura come up as often as tomes and have their own icons (`skill_icon.gd`: `thorns`, `frost_aura`). Max 3 weapons per run.
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
  potion_manager.gd  epic drops: purple / red / blue potions
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
  chest_manager.gd   places 8-28 bronze/silver/gold chests per run, opens them with keys
  key_manager.gd     chest keys dropped by elites
  slot_machine.gd    the chest slot machine (three reels of your abilities, real odds)
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

# Pause menu / settings tests (tabs, Apply/revert, languages, music + SFX volume and mute, rebinding)
godot --headless --path . res://tools/test_settings.tscn

# Run clock spin-up/countdown, Play mode cards, Quickplay, Unrelenting, Ghast's feat, weapon hover
godot --headless --path . res://tools/test_modes.tscn

# Intro cinematic (splash -> intro -> title, cast, skip)
godot --headless --path . res://tools/test_intro.tscn

# Chests, keys, the slot machine (odds, reels, rewards) and ability levels
godot --headless --path . --fixed-fps 60 res://tools/test_chests.tscn

# Title flow (splash -> title -> settings -> play -> main menu)
godot --headless --path . res://tools/test_title.tscn

# The Forest and Castle bosses (telegraphs, minimum warning, wall climbing, unlocks)
godot --headless --path . res://tools/test_bosses.tscn

# Thog the Troll (arrives at 8:00, attacks, enrage, must die to win, unlocks)
godot --headless --path . res://tools/test_boss.tscn

# Castle (layout and reachability, door walk-in, feast physics, skeletons throwing bones)
godot --headless --path . res://tools/test_castle.tscn

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
