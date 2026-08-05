# 🥟 Squishy Clicker — Steamer Edition

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

**Squishy Launch** — a cannon on the third camera view, right of the squisher,
and a **distance** game. Tap once to stop the power bar, once more for the
angle, and your squisher is fired down a long range with the camera riding
along behind it. How far it gets is the score.

A shot is two halves. It arcs up ballistically, and at the top of the arc it
**glides** — drifting forward while it sinks, which is where most of a long
shot's distance comes from. Glide time grows with how high the apex was, so a
flat shot covers more ground before the top and a steep one glides longer
after it; the best angle is in between (around 48°) rather than at either end.

On the way it sweeps up **sweets** floating down the range, and the **zone** it
lands in multiplies the whole payout — sweets included. The lot converts into
progress toward your next steamer. Stars earn their second keep here twice
over: muzzle speed, so a prestiged collection flies roughly twice as far, and
magnet range, so it hoovers up more going past. One shot every
`LaunchCooldownSeconds`.

The client sends nothing but `{power, angle}` as two 0-1 numbers. The server
lays the sweets out, works out the whole arc, decides which sweets it touched,
picks the zone and awards the bonus — then sends back the *shape* of the
flight for the client to draw. Distances, pickups and payouts are never
computed client-side, so there is nothing to fake.

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
│   │   ├── Config.luau        tuning: click costs, star discount, prestige, saving
│   │   ├── Squishies.luau     THE CATALOG: rarities, odds, colors, costs
│   │   └── Format.luau        big-number formatting helper
│   ├── server/              → ServerScriptService/Server
│   │   └── init.server.luau   click counting, rolls, inventory, prestige, saving
│   └── client/              → StarterPlayerScripts/Client
│       ├── init.client.luau   the HUD, and wiring it to the stage
│       ├── Scene.luau         the 3D stage: toy shop, camera, lights, reveals
│       ├── Models.luau        builds the steamer and every squishy shape
│       ├── Launch.luau        the cannon minigame's aiming UI
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
   Config, Format, Squishies — no `Classes` folder.
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
- Cannon earning rate: `LaunchClicksPerStud` against `LaunchCooldownSeconds`.
  How far a shot goes: `LaunchSpeed` / `LaunchGravity` for the arc, and the
  `LaunchGlide*` numbers for the drift after it. Raising glide flattens the
  best angle; lowering it steepens.
- Cannon zones: the `LaunchZones` table. `from` is in game studs and must
  ascend; the stage reads the same table, so a new zone paints its own stripe
  and sign on the range. With the shipped numbers a starless player tops out
  around 98 studs and a fully starred one around 174, which is what the four
  thresholds are spaced against.
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
flip the camera and blur, aim an imported mesh with Rotate Clicker, and
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
