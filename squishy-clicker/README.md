# 🥟 Squishy Clicker — Steamer Edition

Tap the bamboo steamer. After enough taps it pops open and reveals a random
dumpling squishy — Common through Mythical. Collect copies, then prestige a
squishy (spend copies) to give it stars, up to ★★★★★. Progress saves
automatically.

## The core loop

Every steamer you open makes the **next one cost more clicks**, forever. Stars
are the answer: each one shaves a percentage off the price. Prestige steadily and
you stay roughly level; hoard copies without spending them and you grind slower
and slower. That tug-of-war is the whole game.

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
│       ├── Scene.luau         the 3D stage: camera, lights, reveal choreography
│       └── Models.luau        builds the steamer and dumplings out of primitives
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
- Add a dumpling: one line in the `list` in `Squishies.luau`. The reveal scales
  off rarity rank automatically, so a new top rarity gets the biggest show.
- Reshape the models: the numbers in `Models.luau`. Camera angle, lighting and
  reveal timing: the constants at the top of `Scene.luau`.

Lint before you commit:

```bash
selene src
```

## Saving

Studio blocks DataStores unless you enable: Game Settings → Security →
**Enable Studio Access to API Services**, and the place must be published to
Roblox. Without either, the game still runs and warns once in the Output —
it just won't remember progress between sessions.
