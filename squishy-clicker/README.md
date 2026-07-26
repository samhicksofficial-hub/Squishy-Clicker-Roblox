# 🫧 Squishy Clicker

A collect-and-click game: tap the squishy to earn **Squish**, spend it in the
shop to unlock new squishies, and each one you own makes every tap worth more
*and* earns Squish while you're away. Progress saves automatically.

Built as a real Rojo project — the code lives in files, syncs into Roblox
Studio, and is tracked in Git.

---

## What's in here

```
squishy-clicker/
├── default.project.json     ← tells Rojo how folders map into Roblox
├── rokit.toml               ← pins the exact Rojo version
├── src/
│   ├── shared/              → ReplicatedStorage (code both sides can see)
│   │   ├── Config.luau        game tuning numbers
│   │   ├── Squishies.luau     THE CATALOG — edit this to add squishies
│   │   └── Format.luau        big-number formatting (1500 → "1.5K")
│   ├── server/             → ServerScriptService (the authority)
│   │   └── init.server.luau   currency, purchases, idle income, saving
│   └── client/             → StarterPlayerScripts (what the player sees)
│       └── init.client.luau   the whole UI, built in code
```

The golden rule this project is built around: **the server decides, the client
asks.** The client can request a click or a purchase, but only the server
changes your Squish. That's what stops cheating.

---

## One-time setup

### 1. Install Rokit (manages the Rojo version for you)
Download the latest release for your OS from
https://github.com/rojo-rbx/rokit/releases , extract it, and run:

```bash
rokit self-install
```

Close and reopen your terminal afterward so it's on your PATH.

### 2. Install this project's tools
From inside the `squishy-clicker` folder:

```bash
rokit install
```

This reads `rokit.toml` and installs Rojo 7.7.0.

### 3. Install the Rojo plugin in Studio
```bash
rojo plugin install
```

Restart Studio if it was open. You'll now have a **Rojo** button in the Plugins tab.

### 4. Start Git (optional but you asked for it)
From inside the folder:

```bash
git init
git add .
git commit -m "Initial squishy clicker scaffold"
```

---

## Running it

1. Open Roblox Studio → **New** → **Baseplate**.
2. In your terminal, from the project folder:
   ```bash
   rojo serve
   ```
3. In Studio, click the **Rojo** plugin button → **Connect**. You should see the
   `Shared`, `Server`, and `Client` folders appear in the Explorer.
4. **Turn on saving:** Home tab → **Game Settings** → **Security** → enable
   **Enable Studio Access to API Services**. Without this, DataStore saving is
   blocked in Studio (the game still runs — it just won't remember progress).
5. Press **Play**. Tap the squishy, earn Squish, buy from the shop.

While `rojo serve` is running, any edit you save to a `.luau` file appears in
Studio instantly. Edit in VS Code, save, and it's live.

---

## Make it yours

**Add a new squishy** — open `src/shared/Squishies.luau` and add a line to the
list:

```lua
{ id = "mochi", name = "Mochi Blob", emoji = "🍡", cost = 3000000, perClick = 1500, perSecond = 1200 },
```

Save. It appears in the shop automatically — no other file to touch.

**Change how fast things earn** — the numbers in `src/shared/Config.luau` and
the `perClick` / `perSecond` values in the catalog.

**Swap emoji for real art** — the emoji are placeholders so you need zero asset
uploads to start. Later, upload squishy images as Decals and replace the
`TextLabel` art with `ImageLabel`s pointing at your asset IDs.

---

## Publishing

When it's fun: File → **Publish to Roblox As…**, then set the place to Public in
the Creator Dashboard. Test on a phone before you share it — most young players
are on mobile, and the shop panel may need resizing for small screens.
