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
collection to swap it, and every squishy has its own squish noise. The steamer
waits in its own nook 90° to the left — pressing Unbox turns the camera to it
for the reveal, then turns back.

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
- Add a shape: one builder function in `shapeBuilders` in `Models.luau`.
- Reshape the models or the toy-shop backdrop: `Models.luau` and the shop
  section of `Scene.luau`. Camera angle, lighting and reveal timing: the
  constants at the top of `Scene.luau`.

Lint before you commit:

```bash
selene src
```

## Debug menu

Press **F2** in Studio (or click 🐛 Debug, top of the screen) for a test menu:
bank steamers, fill the bar, grant copies, max every star, reset your save,
flip the camera and blur, and force-reveal any squishy in the catalog by name —
which is how you look at a Mythical without rolling 0.5% odds.

It is **Studio only**. The server only creates the remote behind it when
`RunService:IsStudio()` is true, so a published game has nothing to call. To
use it on a live server while testing, add your UserId to `DebugUserIds` in
`Config.luau` — and take it out again before the game goes anywhere.

## Imported 3D models (assets/)

Real meshes (like the opal dumpling in `assets/opal-dumpling/`) can't be synced
by Rojo — they go through Studio once:

1. Studio → **File → Import 3D** → pick `assets/opal-dumpling/base.obj`.
2. Select the imported MeshPart → add a **SurfaceAppearance** child → set its
   maps by uploading the textures from the same folder: ColorMap =
   `texture_diffuse.png`, NormalMap = `texture_normal.png`, MetalnessMap =
   `texture_metallic.png`, RoughnessMap = `texture_roughness.png`.
3. In ReplicatedStorage, make a Folder named **SquishyMeshes** and put the
   MeshPart inside, renamed to **OpalDumpling**.
4. If the face points the wrong way in Play, rotate the template in 90° steps
   and test again — the game copies the template's rotation.

The catalog's `shape = "opalmesh"` uses that template automatically and falls
back to the primitive dumpling when it's missing, so nothing breaks in a place
without the import. New mesh squishies follow the same pattern: add the source
files under `assets/`, an entry in `MESH_SHAPES` in `Models.luau`, and a
template part under SquishyMeshes.

## Saving

Studio blocks DataStores unless you enable: Game Settings → Security →
**Enable Studio Access to API Services**, and the place must be published to
Roblox. Without either, the game still runs and warns once in the Output —
it just won't remember progress between sessions.
