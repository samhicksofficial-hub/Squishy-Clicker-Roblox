# 🚀 Squishy Launcher

**The launcher is the game.** You start in a grass valley between red canyon
walls, with a cannon in the foreground and the distance painted flat on the
ground running away to the horizon. Charge, angle, fire, and watch how far
your squishy skips.

The clicker half — the steamer, the collection, the squisher on its cushion —
is still all there, and still feeds the launcher through stars. It just lives
behind two buttons on the nav rail now rather than being the whole screen.

---

## 🥟 The clicker half — Steamer Edition

Tap the bamboo steamer. After enough taps it pops open and reveals a random
dumpling squishy — Common through Mythical. Collect copies, then prestige a
squishy (spend copies) to give it stars, up to ★★★★★. Progress saves
automatically.

## The core loop

Filling the bar **banks** a steamer into the Unbox tray — opening it is its own
button, its own moment. Every steamer you *open* makes the next one cost more
clicks, forever (banked ones are safe to hoard). Stars are the answer: each one
shaves a percentage off the price. Prestige steadily and you stay roughly
level; hoard copies without spending them and you grind slower and slower.

Your **squisher** is the star of the screen and the thing every click squishes.
Everyone starts with a Red Dumpling; tap any discovered squishy's face in the
collection to swap it, and every squishy has its own squish noise. Drag it —
mouse or finger — to spin it on its cushion; let go and it coasts. The steamer
waits in its own nook 90° to the left — pressing Unbox turns the camera to it
for the reveal, then turns back.

## Minigames

**Squishy Launch** — a full launch simulator on the third camera view, right
of the squisher. Tap once to stop the **charge** meter, once more for the
angle, and your squisher is fired down an endless rainbow track with the
camera riding along behind it. How far it gets is the score.

Hitting the ground is not the end of a shot: it **skips** like a stone, each
bounce keeping a share of its speed, and the skips are most of a long run's
distance. That is why the best angle is under 45° rather than at it — a
flatter shot carries more forward speed into the first bounce. When the skips
die out it rolls to a stop, and wherever it stops is the number.

On the way it sweeps up **TNT**, **coins** and **gems** strung along the
flight path, clustered in **VIP zones** where they pay several times over.
Passing a distance **milestone** — 100, 1K, 10K, 100K, 1M — pays a gem bounty
the first time only. **Rain TNT** is a button that floods the next shot's
track with extra TNT on a two-minute cooldown.

The loop from there:

- **TNT** buys **Launch Power** levels, and distance is deliberately linear in
  power — double the power, double the distance, so an upgrade reads as
  exactly what it does.
- **Coins** buy **eggs**, which hatch **pets**. Five follow the squishy at a
  time, and their bonuses add up: launch power, coin and TNT value, gem value,
  and magnet reach.
- **Gems** buy the Cosmic Egg, the only source of the best pets.
- **Rebirth** spends the whole run — TNT, coins, power level and your distance
  record — for a permanent multiplier on distance, coins and TNT. Gems, pets
  and the milestones you have already claimed all survive.

Squishies earn their second keep here too: stars add muzzle power and magnet
reach, so the collection half of the game feeds the cannon half.

The track is drawn on a **treadmill**. A pool of stripes recycles through a
window and the squishy stops moving forward at its station while the world
scrolls underneath, which makes distance unbounded for free. The scales are
per-shot rather than fixed: a level-1 flight and a level-50 flight are drawn
to the same on-screen size and pace, which is the only way a game spanning
four orders of magnitude stays readable. The magnet is quoted in those same
screen units and converted back — so the reach you *see* is the reach that
actually scores, at every power level.

The client sends nothing but `{power, angle}` as two 0-1 numbers. The server
lays the pickups out, simulates the entire flight — every hop, its peak, its
duration — decides which pickups the path touched, applies every multiplier
and awards the lot, then sends back the *shape* of the flight for the client
to draw. Distances, pickups, prices and payouts are never computed
client-side, so there is nothing to fake.

The simulation is closed-form arithmetic rather than Roblox physics on
purpose. Physics runs on whoever owns the part and is not reproducible, which
would mean trusting a client's word for how far it went; deterministic
arithmetic on the server cannot be argued with, and a forty-second flight
costs no simulation time at all.

## The map

One long valley: a grass floor, a darker mown strip down the middle with the
distance printed flat on it, and five stepped terraces of red rock up each
side with grassy lips — the blocky canyon of the reference. Trees, bushes,
crates, log piles and the odd truck are scattered up both banks from a seeded
Random, so the valley is laid out identically every run.

The valley sits 600 studs from the toy shop and has its **own camera
station**, rather than being 90° off the same one. That distance is not
decoration: when all the views shared one camera position, every piece of
scenery had to be hand-checked against the shop's frustum, and half the map's
dimensions were set by "does this show up in the corner of the toy shop"
rather than by what the valley wanted to be. Now the two sets can never see
each other and the valley is as wide as it likes.

The distance ladder is a **pool**, not a set of signs. It shows a sliding
window of round numbers whose step is chosen per shot, so at 300 studs of
reach it counts in 50s and at 300,000 it counts in 50,000s — the ladder always
reads the same however strong the player is.

**Worlds** are retunes of that one valley: a palette swap on the grass and the
canyon, gated on rebirths. Adding one is a single entry in `Config.Worlds`,
which drives both the Worlds panel and the colours the stage paints itself.

## The look

`src/client/UI.luau` holds the whole visual style — heavy dark outlines,
gradient header bars with an icon and a red X, warm embossed panel bodies,
bold outlined text, green price pills. Everything on screen is built through
it, so changing a stroke width or a header gradient once changes the game.

Two rules worth knowing before adding to it: strokes are `Border` mode so they
never eat into a fill, and nothing in the kit parents itself anywhere — callers
pass a parent and the kit only builds.

## Game Shop

The Starter Pack / VIP Bundle / Auto Clicker cards are a **shell**. Each one
knows its name, its contents and its price, and nothing else. Wiring a card to
a real purchase means giving it a developer product or gamepass id and calling
`MarketplaceService` — deliberately not done here, because those ids have to
come from this game's own Creator Dashboard, and a made-up one would charge
somebody for the wrong thing. Add the ids and the wiring, and the cards are
ready for them.

**King of the Steamer** — one giant steamer the whole server clicks together,
in the panel on the right. The goal scales with how many people are in the
server, fixed at the start of each round. When it opens, everyone who helped
gets a squishy and whoever helped most gets a better one — the bonus roll is
the same odds rolled twice keeping the rarer result, so there is no second
odds table to drift out of step with `Squishies.luau`. A short cooldown, then
a fresh round.

## The files

```
├── default.project.json     ← how Rojo maps src/ into Roblox
├── rokit.toml               ← pins Rojo 7.7.0 and Selene (managed by Rokit)
├── selene.toml              ← linter config
├── src/
│   ├── shared/              → ReplicatedStorage/Shared
│   │   ├── Config.luau        tuning: click costs, launch physics, economy, saving
│   │   ├── Squishies.luau     THE CATALOG: rarities, odds, colors, costs
│   │   ├── Pets.luau          pet stats and the egg drop tables
│   │   └── Format.luau        big-number formatting helper
│   ├── server/              → ServerScriptService/Server
│   │   └── init.server.luau   clicks, rolls, inventory, flight simulation, economy
│   └── client/              → StarterPlayerScripts/Client
│       ├── init.client.luau   the HUD, and wiring it to the stage
│       ├── Scene.luau         the 3D stage: toy shop, track, camera, reveals
│       ├── Models.luau        builds the steamer and every squishy shape
│       ├── UI.luau            the chunky-outline look: panels, buttons, labels
│       ├── Launch.luau        the launcher: charge meter, flight HUD, summary
│       ├── Cannon.luau        wallet, nav rail, upgrades, rebirth, worlds, pets, shop
│       ├── King.luau          the shared-steamer minigame's panel
│       └── Debug.luau         the Studio-only test menu
```

The steamer is a real 3D model, built from parts at runtime — there are no assets
to upload. It lives on the **client**, 500 studs above the map, so every player
gets a private steamer and whatever else is in your place stays out of frame.

Golden rule: **the server decides, the client asks.** Clicks are counted and
squishies are rolled server-side, so nobody can fake a Mythical.

## Clean install (do this if your folder got into a weird state)

1. In your project folder, delete `src/`, `README.md`, and `aftman.toml`
   (keep `.git` if you have one).
2. Copy everything from this zip into the folder.
3. Terminal, from the folder: `rojo serve`
4. Studio: open your place → Plugins tab → Rojo → **Connect**.
5. Check the Explorer: `ReplicatedStorage/Shared` should contain exactly
   Config, Format, Pets, Squishies — no `Classes` folder.
6. **Stop** if you were playing, then **Play** fresh.

Output should show:
```
[SquishyClicker] Server ready.
[SquishyClicker] Client UI ready.
```

If the game is ever a blank screen, open View → Output first: an orange
"Infinite yield possible" warning names the exact line that's stuck.

## Tuning

- How fast the treadmill climbs: `ClicksAddedPerOpen` and `MaxClicksToOpen` in
  `Config.luau`. Raise the first to make the game harder, lower it to make opens
  come quicker.
- How hard stars push back: `StarDiscountPerStar` and `MaxStarDiscount`.
- Starting pace and floor: `BaseClicksToOpen`, `MinClicksToOpen`.
- Rarity odds and prestige costs: the `rarities` table in `Squishies.luau`
  (weights are out of 1000: 550 = 55%).
- Add a squishy: one line in the `list` in `Squishies.luau`. Give it a `shape`
  from the builders in `Models.luau` (or leave it off for a dumpling). The
  reveal scales off rarity rank automatically, so a new top rarity gets the
  biggest show.
- Squishy sizes: every model is normalised to the same size, so a `scale` on a
  catalog entry is what makes a Mini small or a Giant big. It applies on the
  cushion, in the reveal and in the collection icon alike.
- Add a shape: one builder function in `shapeBuilders` in `Models.luau`.
- How far a shot goes: `LaunchStudsPerPower` and `LaunchGravity` for the arc,
  then `LaunchRestitution` and `LaunchBounceFriction` for the skips. Friction
  is the strong one — it compounds once per bounce.
- How fast power grows: `LaunchBasePower` and `LaunchPowerGrowth` against
  `PowerUpgradeBaseCost` and `PowerUpgradeCostGrowth`. Cost growth is set a
  little above power growth on purpose, so levels get slower rather than
  cheaper. Shipped numbers: level 0 reaches ~270 studs, level 20 ~3.7K,
  level 30 ~14K, level 40 ~50K, level 50 ~190K, level 63 crosses 1M.
- How much a shot pays: `PickupTntValue` / `PickupCoinValue` /
  `PickupGemValue` and `PickupValuePer1kStuds`, which is what makes a distant
  pickup worth more than a near one.
- How many pickups you actually catch: `LaunchPickupMagnet`. Shipped at 2,
  which lands around 37% and holds that at every power level — read the
  comment on it before changing it, the units are not what they look like.
- Milestones and their gem bounties: the `DistanceMilestones` table. The stage
  reads the same table, so a new entry puts its own sign on the track.
- Rebirth pacing: `RebirthBaseRequirement` and `RebirthRequirementGrowth`
  against the three `Rebirth*Bonus` numbers. First rebirth lands around
  level 22.
- Pets and eggs: `src/shared/Pets.luau`. Drop tables name pets directly, so a
  new pet can be added to one egg without rebalancing every other egg that
  shares its rarity.
- Reshape the models or the toy-shop backdrop: `Models.luau` and the shop
  section of `Scene.luau`. Camera angle, lighting and reveal timing: the
  constants at the top of `Scene.luau`.

Lint before you commit:

```bash
selene src
```

## Glitter

Squishies marked `sparkle = true` wear a glitter surface, tinted to their own
colour — one gold glitter sheet becomes pink, green or gold glitter depending
on who's wearing it. Roblox needs the image uploaded first:

1. Upload `assets/glitter/glitter.png` — Asset Manager → **Import**.
2. Right-click it once it has processed → **Copy ID**.
3. Paste it into `GLITTER_TEXTURE` at the top of `Models.luau`, as
   `rbxassetid://…`.

That texture is deliberately **greyscale**, not gold. A material's colour map
multiplies by the part's colour, so neutral flakes become gold on the gold
squishy, pink on the pink one and so on. A gold sheet would only ever tint
toward mud. It is also generated seamlessly, so it tiles without visible seams.

Left empty, the glittery squishies just wear their flat colour and nothing
breaks. Glass and neon squishies are skipped deliberately — being see-through
or glowing is the point of those — and an imported mesh with its own texture
keeps that texture.

## Debug menu

Press **F2** in Studio (or click 🐛 Debug, top of the screen) for a test menu:
bank steamers, fill the bar, grant copies, max every star, reset your save,
flip the camera and blur, jump to the cannon range with View: Range, skip the
cannon's grind with Rich Cannon / +10 Power / Ready Rebirth, aim an
imported mesh with Rotate Clicker, and
force-reveal any squishy in the catalog by name — which is how you look at a
Mythical without rolling 0.5% odds.

It is **Studio only**. The server only creates the remote behind it when
`RunService:IsStudio()` is true, so a published game has nothing to call. To
use it on a live server while testing, add your UserId to `DebugUserIds` in
`Config.luau` — and take it out again before the game goes anywhere.

## Imported 3D models (assets/)

Real meshes (like the opal dumpling in `assets/opal-dumpling/`) can't be synced
by Rojo — they go through Studio once:

Three models live in `assets/`, each needing the same one-time import:

| Folder | Name it exactly | Used by | Texturing |
|---|---|---|---|
| `opal-dumpling/` | `OpalDumpling` | all 13 dumplings (tinted) | PBR maps |
| `banana/` | `BananaSquishy` | Stretch Banana | one baked texture |
| `butter/` | `ButterSquishy` | Butter Stick | one baked texture |
| `rainbow-butter/` | `RainbowButter` | Rainbow Butter | one baked texture |
| `glow-donut/` | `GlowDonut` | Glow Doughnut | one baked texture |
| `cheese/` | `SquishCheese` | Squeeze Cheese | one baked texture |
| `coconut/` | `CoconutBall` | Coconut Ball | one baked texture |
| `glitter-baby/` | `GlitterBaby` | Sugar Baby | one baked texture |
| `sparkle-drop/` | `SparkleDrop` | Sparkle Drop | one baked texture |
| `brain/` | `SquishyBrain` | Pink Brain | one baked texture |
| `cloud/` | `DoughCloud` | Dough Cloud | one baked texture |
| `strawberry/` | `StrawberrySquishy` | Strawberry + Giant | one baked texture |
| `ice-cube/` | `IceCubeSquishy` | Ice Cube Squishy | one baked texture |

Do all of this in **Edit mode, with the playtest stopped** — anything you create
while the game is running is discarded the moment you press Stop.

1. Studio → **File → Import 3D** → pick that folder's `base.obj`.
2. Texture it. For the **baked texture** models, `base.mtl` points at
   `texture.png` sitting beside it, so the importer usually applies it by
   itself — if it doesn't, upload `texture.png` and paste its ID into the
   MeshPart's **TextureID**. For the **PBR** model, add a **SurfaceAppearance**
   child and paste uploaded image IDs (`rbxassetid://…`) into its map slots:
   ColorMap = `texture_diffuse.png`, NormalMap = `texture_normal.png`,
   MetalnessMap = `texture_metallic.png`, RoughnessMap = `texture_roughness.png`.
   Those slots are plain text fields; upload the PNGs first via **View → Asset
   Manager → Images → Add Images**, then right-click each → Copy ID.
3. Drag it into **ReplicatedStorage** and rename it to the name in the table
   above. A `SquishyMeshes` folder is the tidy home, but anywhere in
   ReplicatedStorage works. A Model wrapper is fine — including one Studio has
   split into several MeshParts, which it does to dense meshes. The game
   reassembles every piece and scales them as one object.
4. If the face points the wrong way, equip it and press **Rotate Clicker** in
   the debug menu until it looks right, then write the yaw it prints into
   `MESH_SHAPES` in `Models.luau` so it sticks. (Rotating the template in
   Studio works too — the game applies that on top.)

The Output tells you which way it went: `Using imported mesh 'OpalDumpling'`, or
a warning naming exactly what it couldn't find.

All thirteen dumplings share that one mesh: `opalmesh` uses the texture as
imported, and `dumplingmesh` tints it via `SurfaceAppearance.Color` — the
texture is pale and pearly, so multiplying by a colour keeps the glitter and
the baked-in face while changing the shade. One mould, thirteen colours. Both
fall back to the primitive dumpling when the template is missing, so nothing
breaks in a place without the import.

Where a set comes as one model per colour — the cubes, named
`<Colour>CubeSquishy` — a mesh config names a `family` suffix as well as its
preferred `template`. Each cube asks for its own colour and settles for a
tinted sibling when that colour hasn't been made yet, so the set works however
far along the models are and picks up new colours just by their being named to
match. New mesh squishies follow the same pattern: add the source
files under `assets/`, an entry in `MESH_SHAPES` in `Models.luau`, and a
template part under SquishyMeshes.

## Saving

Studio blocks DataStores unless you enable: Game Settings → Security →
**Enable Studio Access to API Services**, and the place must be published to
Roblox. Without either, the game still runs and warns once in the Output —
it just won't remember progress between sessions.
