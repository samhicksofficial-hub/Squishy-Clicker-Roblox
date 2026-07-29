# 🥟 Squishy Clicker — Steamer Edition

Tap the bamboo steamer. After enough taps it pops open and reveals a random
dumpling squishy — Common through Mythical. Collect copies, then prestige a
squishy (spend copies) to give it stars, up to ★★★★★. Every star you earn makes
the steamer open faster. Progress saves automatically.

## The files

```
├── default.project.json     ← how Rojo maps src/ into Roblox
├── rokit.toml               ← pins Rojo 7.7.0 (managed by Rokit)
├── selene.toml              ← linter config
├── src/
│   ├── shared/              → ReplicatedStorage/Shared
│   │   ├── Config.luau        tuning: clicks-to-open, prestige growth, saving
│   │   ├── Squishies.luau     THE CATALOG: rarities, odds, colors, costs
│   │   └── Format.luau        big-number formatting helper
│   ├── server/              → ServerScriptService/Server
│   │   └── init.server.luau   click counting, rolls, inventory, prestige, saving
│   └── client/              → StarterPlayerScripts/Client
│       └── init.client.luau   steamer UI, reveal animation, collection panel
```

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

- Steamer pacing: `BaseClicksToOpen`, `MinClicksToOpen`, `ClickReductionPerStar`
  in `Config.luau`.
- Rarity odds and prestige costs: the `rarities` table in `Squishies.luau`
  (weights are out of 1000: 550 = 55%).
- Add a dumpling: one line in the `list` in `Squishies.luau`.

## Saving

Studio blocks DataStores unless you enable: Game Settings → Security →
**Enable Studio Access to API Services**. The game still runs without it,
it just won't remember progress between sessions.
