--!strict
-- ============================================================
--  CANNON HUD  —  the wallet, the nav rail, the lobby feed, and
--  every panel behind them: Upgrades, Rebirth, Worlds, Steamers
--  and the Game Shop.
--
--  The launcher is the main game, so this owns most of what is on
--  screen. Everything is built through UI.luau, which means the
--  chunky-outline look is defined in one place rather than
--  re-typed here.
--
--  Everything is a BUTTON and a NUMBER. Every button fires a bare
--  request — "the next power level", "a steamer", "summon this
--  squishy" — and every number comes from the last sync. Prices
--  are never worked out locally: the server sends the finished
--  figure, so the price shown and the price charged are the same
--  number by construction rather than by two copies of a formula
--  agreeing with each other.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Squishies = require(Shared:WaitForChild("Squishies"))
local UI = require(script.Parent:WaitForChild("UI"))

local Cannon = {}

-- Replaced on mount, so a sync arriving before the UI is up is harmless.
function Cannon.update(_state: any) end

local C = UI.color

function Cannon.mount(gui: ScreenGui, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local buyPower = remotes:WaitForChild("BuyPower") :: RemoteEvent
	local doRebirth = remotes:WaitForChild("DoRebirth") :: RemoteEvent
	local buySteamer = remotes:WaitForChild("BuySteamer") :: RemoteEvent
	local activateBoost = remotes:WaitForChild("ActivateBoost") :: RemoteEvent
	local launchBroadcast = remotes:WaitForChild("LaunchBroadcast") :: RemoteEvent

	-- ---------- the wallet ----------
	-- Top right, always visible: in a simulator the balances are the score.
	local wallet = UI.make("Frame", {
		Name = "Wallet",
		Size = UDim2.new(0, 210, 0, 132),
		Position = UDim2.new(1, -18, 0, 16),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	})
	UI.make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wallet,
	})

	local function walletRow(order: number, top: Color3, bottom: Color3, icon: string): TextLabel
		local row = UI.make("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundColor3 = top,
			LayoutOrder = order,
			ZIndex = 5,
			Parent = wallet,
		})
		UI.corner(14, row)
		UI.gradient(row, top, bottom)
		UI.stroke(row)

		UI.label({
			Size = UDim2.new(0, 34, 1, 0),
			Position = UDim2.new(0, 6, 0, 0),
			Text = icon,
			TextSize = 22,
			ZIndex = 6,
			Parent = row,
		})
		return UI.label({
			Size = UDim2.new(1, -46, 1, 0),
			Position = UDim2.new(0, 42, 0, 0),
			Text = "0",
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
			Parent = row,
		})
	end

	local tntLabel = walletRow(1, C.tnt, Color3.fromRGB(212, 106, 40), "🧨")
	local coinLabel = walletRow(2, C.cash, Color3.fromRGB(84, 186, 60), "💵")
	local gemLabel = walletRow(3, C.gem, Color3.fromRGB(64, 190, 190), "💎")

	-- ---------- panels ----------
	-- Built up front and hidden; opening one is a Visible flag rather than a
	-- rebuild, so a panel keeps its scroll position between visits.
	local panels: { [string]: UI.Panel } = {}
	local function showOnly(name: string?)
		for key, panel in panels do
			panel.root.Visible = key == name
		end
	end

	local upgradesPanel = UI.panel({
		parent = gui,
		name = "UpgradesPanel",
		size = UDim2.new(0, 420, 0, 300),
		position = UDim2.fromScale(0.5, 0.5),
		icon = "🧨",
		title = "Upgrades",
		top = C.orange,
		bottom = C.orangeDeep,
	})
	panels.upgrades = upgradesPanel

	local rebirthPanel = UI.panel({
		parent = gui,
		name = "RebirthPanel",
		size = UDim2.new(0, 440, 0, 340),
		position = UDim2.fromScale(0.5, 0.5),
		icon = "🔄",
		title = "Rebirth",
		top = C.pink,
		bottom = C.pinkDeep,
	})
	panels.rebirth = rebirthPanel

	local worldsPanel = UI.panel({
		parent = gui,
		name = "WorldsPanel",
		size = UDim2.new(0, 400, 0, 340),
		position = UDim2.fromScale(0.5, 0.5),
		icon = "🌍",
		title = "Worlds",
		top = C.blue,
		bottom = C.blueDeep,
	})
	panels.worlds = worldsPanel

	local steamersPanel = UI.panel({
		parent = gui,
		name = "SteamersPanel",
		size = UDim2.new(0, 420, 0, 350),
		position = UDim2.fromScale(0.5, 0.5),
		icon = "🥡",
		title = "Steamers",
		top = C.purple,
		bottom = C.purpleDeep,
	})
	panels.steamers = steamersPanel

	local shopPanel = UI.panel({
		parent = gui,
		name = "ShopPanel",
		size = UDim2.new(0, 520, 0, 360),
		position = UDim2.fromScale(0.5, 0.5),
		icon = "🧺",
		title = "Game Shop",
		top = C.orange,
		bottom = C.orangeDeep,
	})
	panels.shop = shopPanel

	-- ---------- the nav rail ----------
	-- Down the left edge, the way these games always do it. The first three
	-- buttons MOVE THE CAMERA rather than opening a panel: the launcher is the
	-- game, and the squisher and the steamer are two places you can visit.
	local rail = UI.make("Frame", {
		Name = "NavRail",
		Size = UDim2.new(0, 92, 0, 470),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	})
	UI.make("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rail,
	})

	local function railButton(order: number, icon: string, caption: string, top: Color3, bottom: Color3, onClick: () -> ())
		local entry = UI.button({
			parent = rail,
			size = UDim2.new(1, 0, 0, 66),
			text = "",
			top = top,
			bottom = bottom,
			zIndex = 5,
			radius = 16,
		})
		entry.button.LayoutOrder = order

		UI.label({
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.new(0, 0, 0, 6),
			Text = icon,
			TextSize = 28,
			ZIndex = 6,
			Parent = entry.button,
		})
		UI.label({
			Size = UDim2.new(1, -6, 0, 20),
			Position = UDim2.new(0, 3, 1, -24),
			Text = caption,
			TextSize = 13,
			ZIndex = 6,
			Parent = entry.button,
		})
		entry.button.Activated:Connect(onClick)
		return entry
	end

	railButton(1, "🚀", "LAUNCH", C.green, C.greenDeep, function()
		showOnly(nil)
		scene.setView("main")
	end)
	railButton(2, "🥟", "SQUISHY", C.pink, C.pinkDeep, function()
		showOnly(nil)
		scene.setView("clicker")
	end)
	railButton(3, "🥡", "STEAMER", C.blue, C.blueDeep, function()
		showOnly(nil)
		scene.setView("unbox")
	end)
	railButton(4, "🧨", "UPGRADE", C.orange, C.orangeDeep, function()
		showOnly("upgrades")
	end)
	railButton(5, "🥡", "STEAMERS", C.purple, C.purpleDeep, function()
		showOnly("steamers")
	end)
	railButton(6, "🌍", "WORLDS", C.blue, C.blueDeep, function()
		showOnly("worlds")
	end)

	-- Rebirth and the shop sit apart from the rail, the way the mockups put
	-- them: the two things the game most wants noticed.
	local rebirthOpen = UI.button({
		parent = gui,
		size = UDim2.new(0, 168, 0, 46),
		position = UDim2.new(1, -18, 0, 158),
		anchor = Vector2.new(1, 0),
		text = "🔄 REBIRTH",
		textSize = 18,
		top = C.pink,
		bottom = C.pinkDeep,
		zIndex = 5,
	})
	rebirthOpen.button.Activated:Connect(function()
		showOnly("rebirth")
	end)

	local shopOpen = UI.button({
		parent = gui,
		size = UDim2.new(0, 168, 0, 46),
		position = UDim2.new(1, -18, 0, 212),
		anchor = Vector2.new(1, 0),
		text = "🧺 SHOP",
		textSize = 18,
		top = C.orange,
		bottom = C.orangeDeep,
		zIndex = 5,
	})
	shopOpen.button.Activated:Connect(function()
		showOnly("shop")
	end)

	-- ---------- Rain TNT ----------
	local boost = UI.button({
		parent = gui,
		size = UDim2.new(0, 168, 0, 46),
		position = UDim2.new(1, -18, 0, 266),
		anchor = Vector2.new(1, 0),
		text = "🧨 RAIN TNT",
		textSize = 17,
		top = C.red,
		bottom = C.redDeep,
		zIndex = 5,
	})
	boost.button.Activated:Connect(function()
		activateBoost:FireServer()
	end)

	-- ---------- Upgrades panel ----------
	local powerTitle = UI.label({
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.new(0, 12, 0, 10),
		Text = "Launch Power",
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = upgradesPanel.body,
	})

	local powerStats = UI.label({
		Size = UDim2.new(1, -24, 0, 60),
		Position = UDim2.new(0, 12, 0, 46),
		Text = "",
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 23,
		Parent = upgradesPanel.body,
	})

	local powerBuy = UI.button({
		parent = upgradesPanel.body,
		size = UDim2.new(1, -24, 0, 56),
		position = UDim2.new(0, 12, 1, -70),
		text = "UPGRADE",
		textSize = 22,
		top = C.green,
		bottom = C.greenDeep,
		zIndex = 23,
	})
	powerBuy.button.Activated:Connect(function()
		buyPower:FireServer()
	end)

	-- ---------- Rebirth panel ----------
	UI.label({
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.new(0, 12, 0, 8),
		Text = "- Requirements -",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(252, 214, 132),
		ZIndex = 23,
		Parent = rebirthPanel.body,
	})

	local rebirthNeed = UI.label({
		Size = UDim2.new(1, -24, 0, 34),
		Position = UDim2.new(0, 12, 0, 34),
		Text = "Fly 5K studs",
		TextSize = 26,
		ZIndex = 23,
		Parent = rebirthPanel.body,
	})

	local rebirthTrack = UI.make("Frame", {
		Size = UDim2.new(1, -32, 0, 34),
		Position = UDim2.new(0, 16, 0, 74),
		BackgroundColor3 = C.redDeep,
		ZIndex = 23,
		Parent = rebirthPanel.body,
	})
	UI.corner(10, rebirthTrack)
	UI.stroke(rebirthTrack)

	local rebirthFill = UI.make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.green,
		BorderSizePixel = 0,
		ZIndex = 24,
		Parent = rebirthTrack,
	})
	UI.corner(10, rebirthFill)
	UI.gradient(rebirthFill, Color3.fromRGB(178, 240, 108), C.greenDeep)

	local rebirthProgress = UI.label({
		Size = UDim2.fromScale(1, 1),
		Text = "0 / 5K",
		TextSize = 18,
		ZIndex = 26,
		Parent = rebirthTrack,
	})

	UI.label({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.new(0, 12, 0, 116),
		Text = "- Rewards -",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(198, 244, 158),
		ZIndex = 23,
		Parent = rebirthPanel.body,
	})

	local rewardLabels: { TextLabel } = {}
	for index, reward in { "💵 Cash", "🧨 TNT", "🚀 Distance" } do
		local card = UI.card({
			parent = rebirthPanel.body,
			size = UDim2.new(0, 118, 0, 78),
			position = UDim2.new(0, 16 + (index - 1) * 130, 0, 146),
			top = C.row,
			bottom = Color3.fromRGB(92, 56, 26),
			zIndex = 23,
		})
		UI.label({
			Size = UDim2.new(1, -8, 0, 26),
			Position = UDim2.new(0, 4, 0, 8),
			Text = reward,
			TextSize = 15,
			ZIndex = 24,
			Parent = card,
		})
		rewardLabels[index] = UI.label({
			Size = UDim2.new(1, -8, 0, 32),
			Position = UDim2.new(0, 4, 0, 38),
			Text = "×1.0",
			TextSize = 22,
			TextColor3 = Color3.fromRGB(252, 224, 140),
			ZIndex = 24,
			Parent = card,
		})
	end

	local rebirthGo = UI.button({
		parent = rebirthPanel.body,
		size = UDim2.new(1, -32, 0, 54),
		position = UDim2.new(0, 16, 1, -66),
		text = "REBIRTH",
		textSize = 26,
		top = C.green,
		bottom = C.greenDeep,
		zIndex = 23,
	})
	rebirthGo.button.Activated:Connect(function()
		doRebirth:FireServer()
	end)

	-- ---------- Worlds panel ----------
	-- Worlds are gated on rebirths, so this doubles as a preview of what
	-- rebirthing is FOR — which is why the locked rows still show their name
	-- and their multiplier rather than being blanked out.
	type WorldRow = { entry: UI.Button, sub: TextLabel }
	local worldRows: { WorldRow } = {}
	for index, world in Config.Worlds do
		local entry = UI.button({
			parent = worldsPanel.body,
			size = UDim2.new(1, -24, 0, 76),
			position = UDim2.new(0, 12, 0, 10 + (index - 1) * 86),
			text = "",
			top = C.blue,
			bottom = C.blueDeep,
			zIndex = 23,
		})

		UI.label({
			Size = UDim2.new(1, -20, 0, 30),
			Position = UDim2.new(0, 12, 0, 8),
			Text = world.name,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 24,
			Parent = entry.button,
		})
		local sub = UI.label({
			Size = UDim2.new(1, -20, 0, 24),
			Position = UDim2.new(0, 12, 0, 40),
			Text = "",
			TextSize = 16,
			TextColor3 = Color3.fromRGB(252, 224, 140),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 24,
			Parent = entry.button,
		})

		local worldIndex = index
		entry.button.Activated:Connect(function()
			-- Purely a stage retheme, so it is the one thing in this file the
			-- client is allowed to decide on its own. The server still owns
			-- every number; nothing about the world changes a payout yet.
			scene.setWorld(worldIndex)
			showOnly(nil)
			scene.setView("main")
		end)

		worldRows[index] = { entry = entry, sub = sub }
	end

	-- ---------- Game Shop panel ----------
	-- The add-ons from the mockups. This is the SHELL only: each card knows
	-- its name, its contents and its price, and nothing else. Wiring a card to
	-- a real purchase means giving it a developer product or gamepass id and
	-- calling MarketplaceService — deliberately not done here, because those
	-- ids have to come from the game's own Creator Dashboard and inventing one
	-- would charge somebody for the wrong thing.
	local SHOP_ITEMS = {
		{
			name = "Starter Pack",
			lines = { "5,000 Cash", "Golden Apple", "1.25x Cash (10:00)" },
			price = "9",
			top = C.blue,
			bottom = C.blueDeep,
			size = UDim2.new(0, 300, 0, 122),
			position = UDim2.new(0, 12, 0, 10),
		},
		{
			name = "VIP Bundle",
			lines = { "VIP Chat Tag", "Golden Catapult", "1.2x Cash Boost" },
			price = "135",
			top = C.orange,
			bottom = C.orangeDeep,
			size = UDim2.new(0, 300, 0, 122),
			position = UDim2.new(0, 12, 0, 142),
		},
		{
			name = "Auto Clicker",
			lines = { "• OP •" },
			price = "45",
			top = C.pink,
			bottom = C.pinkDeep,
			size = UDim2.new(0, 168, 0, 254),
			position = UDim2.new(0, 322, 0, 10),
		},
	}

	for _, item in SHOP_ITEMS do
		local card = UI.card({
			parent = shopPanel.body,
			size = item.size,
			position = item.position,
			top = item.top,
			bottom = item.bottom,
			zIndex = 23,
		})

		UI.label({
			Size = UDim2.new(1, -16, 0, 34),
			Position = UDim2.new(0, 10, 0, 6),
			Text = item.name,
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 24,
			Parent = card,
		})
		for line, text in item.lines do
			UI.label({
				Size = UDim2.new(1, -16, 0, 22),
				Position = UDim2.new(0, 10, 0, 40 + (line - 1) * 24),
				Text = "• " .. text,
				TextSize = 16,
				TextColor3 = Color3.fromRGB(186, 248, 142),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 24,
				Parent = card,
			})
		end

		UI.pricePill({
			parent = card,
			size = UDim2.new(0, 100, 0, 40),
			position = UDim2.new(1, -10, 1, -10),
			anchor = Vector2.new(1, 1),
			text = "⬢ " .. item.price,
			zIndex = 24,
		})
	end

	UI.label({
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.new(0, 12, 1, -30),
		Text = "Shop items need product ids before they can be bought.",
		TextSize = 13,
		TextColor3 = Color3.fromRGB(252, 226, 180),
		ZIndex = 23,
		Parent = shopPanel.body,
	})

	-- ---------- Steamers panel ----------
	-- What the launcher's cash and gems buy. This is the join between the two
	-- halves of the game: launching earns the currency, the currency buys
	-- squishies, and summoned squishies make the next launch go further.
	local steamerCard = UI.card({
		parent = steamersPanel.body,
		size = UDim2.new(1, -24, 0, 96),
		position = UDim2.new(0, 12, 0, 10),
		top = C.cash,
		bottom = Color3.fromRGB(84, 186, 60),
		zIndex = 23,
	})
	UI.label({
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 12, 0, 6),
		Text = "🥡 Steamer",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = steamerCard,
	})
	UI.label({
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0, 12, 0, 34),
		Text = "Banked straight into your Unbox tray.",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(240, 252, 220),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 1.5,
		ZIndex = 24,
		Parent = steamerCard,
	})
	local buyCoinButton = UI.button({
		parent = steamerCard,
		size = UDim2.new(1, -24, 0, 34),
		position = UDim2.new(0, 12, 1, -42),
		text = "BUY",
		textSize = 18,
		top = C.green,
		bottom = C.greenDeep,
		zIndex = 24,
		radius = 10,
	})
	buyCoinButton.button.Activated:Connect(function()
		buySteamer:FireServer("coin")
	end)

	local luckyCard = UI.card({
		parent = steamersPanel.body,
		size = UDim2.new(1, -24, 0, 96),
		position = UDim2.new(0, 12, 0, 116),
		top = C.gem,
		bottom = Color3.fromRGB(64, 190, 190),
		zIndex = 23,
	})
	UI.label({
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 12, 0, 6),
		Text = "💎 Lucky Steamer",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 24,
		Parent = luckyCard,
	})
	UI.label({
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0, 12, 0, 34),
		Text = ("Opens on the spot. %s or better, guaranteed."):format(
			Squishies.rarities[Config.LuckySteamerMinRank].name
		),
		TextSize = 14,
		TextColor3 = Color3.fromRGB(226, 252, 250),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 1.5,
		ZIndex = 24,
		Parent = luckyCard,
	})
	local buyGemButton = UI.button({
		parent = luckyCard,
		size = UDim2.new(1, -24, 0, 34),
		position = UDim2.new(0, 12, 1, -42),
		text = "BUY",
		textSize = 18,
		top = C.green,
		bottom = C.greenDeep,
		zIndex = 24,
		radius = 10,
	})
	buyGemButton.button.Activated:Connect(function()
		buySteamer:FireServer("gem")
	end)

	UI.label({
		Size = UDim2.new(1, -24, 0, 44),
		Position = UDim2.new(0, 12, 0, 220),
		Text = "Summon squishies from My Squishies — up to "
			.. Config.MaxActiveSquishies
			.. " at once. Rarer and more starred means a bigger buff.",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(252, 226, 180),
		TextWrapped = true,
		StrokeThickness = 1.5,
		ZIndex = 23,
		Parent = steamersPanel.body,
	})

	-- ---------- the lobby feed ----------
	-- Bottom left, above the progress bar: a running list of everyone's
	-- launches. This is the whole social half of the lobby — you sit at the
	-- deck between your own shots and watch the server's shots go past.
	local feed = UI.make("Frame", {
		Name = "LaunchFeed",
		Size = UDim2.new(0, 250, 0, 26 + Config.LobbyFeedSize * 22),
		Position = UDim2.new(0, 124, 1, -170),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = C.body,
		BackgroundTransparency = 0.25,
		ZIndex = 4,
		Parent = gui,
	})
	UI.corner(12, feed)
	UI.stroke(feed)

	UI.label({
		Size = UDim2.new(1, -12, 0, 22),
		Position = UDim2.new(0, 6, 0, 4),
		Text = "🚀 Recent Launches",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = feed,
	})

	local feedRows: { TextLabel } = {}
	for index = 1, Config.LobbyFeedSize do
		feedRows[index] = UI.label({
			Size = UDim2.new(1, -12, 0, 20),
			Position = UDim2.new(0, 6, 0, 26 + (index - 1) * 22),
			Text = "",
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			StrokeThickness = 1.5,
			ZIndex = 5,
			Parent = feed,
		})
	end

	-- Newest first, oldest dropped. Kept as plain strings rather than as a
	-- scrolling list: six rows never needs a scrollbar, and rewriting six
	-- labels is cheaper than building and destroying rows.
	local feedLines: { string } = {}

	launchBroadcast.OnClientEvent:Connect(function(shot)
		if typeof(shot) ~= "table" or typeof(shot.name) ~= "string" then
			return
		end

		-- Everyone gets the broadcast, including whoever fired it. Their own
		-- shot is already flying as the real thing, so drawing a ghost of it
		-- too would put two squishies down the valley for one launch.
		local mine = shot.userId == Players.LocalPlayer.UserId
		if not mine then
			-- Draw it as the squishy they actually launched, when we know it.
			local squishy = typeof(shot.clickerId) == "string" and Squishies.byId[shot.clickerId]
			scene.playGhost(shot, squishy and squishy.color or Color3.fromRGB(250, 240, 220))
		end

		table.insert(feedLines, 1, ("%s — %s"):format(shot.name, Format.abbreviate(math.floor(shot.distance or 0))))
		while #feedLines > Config.LobbyFeedSize do
			table.remove(feedLines)
		end
		for index, row in feedRows do
			row.Text = feedLines[index] or ""
			-- The newest line is bright; older ones fade back, so the eye goes
			-- to what just happened rather than to a wall of equal text.
			row.TextTransparency = index == 1 and 0 or math.min(0.15 * index, 0.55)
		end
	end)
	-- ---------- redraw from the server's numbers ----------
	local lastActiveSignature = ""
	local boostReadyIn = 0
	local boostLeft = 0

	function Cannon.update(state: any)
		tntLabel.Text = Format.abbreviate(state.tnt or 0)
		coinLabel.Text = Format.abbreviate(state.coins or 0)
		gemLabel.Text = Format.abbreviate(state.gems or 0)

		-- ----- upgrades -----
		local level = state.powerLevel or 0
		local cost = state.powerCost or 0
		local maxed = level >= Config.LaunchMaxPowerLevel
		local affordable = (state.tnt or 0) >= cost

		powerTitle.Text = ("Launch Power  ·  Lv %d"):format(level)
		powerStats.Text = ("Power %s   ·   Magnet %.1f\nDistance is linear in power: double it, fly twice as far."):format(
			Format.abbreviate(math.floor(state.launchPower or 0)),
			state.magnet or 0
		)
		powerBuy.button.Text = maxed and "MAXED" or ("UPGRADE  ·  %s 🧨"):format(Format.abbreviate(cost))
		UI.setButtonEnabled(powerBuy, not maxed and affordable, C.green, C.greenDeep)

		-- ----- rebirth -----
		local rebirths = state.rebirths or 0
		local need = math.floor(state.rebirthAt or 0)
		local have = math.floor(state.bestDistance or 0)
		rebirthNeed.Text = ("Fly %s Studs"):format(Format.abbreviate(need))
		rebirthProgress.Text = ("%s / %s"):format(Format.abbreviate(have), Format.abbreviate(need))
		rebirthFill.Size = UDim2.fromScale(math.clamp(have / math.max(need, 1), 0, 1), 1)

		-- What the NEXT rebirth would make each multiplier, since that is the
		-- question the panel is actually being opened to answer.
		rewardLabels[1].Text = ("×%.2f"):format(1 + (rebirths + 1) * Config.RebirthCoinBonus)
		rewardLabels[2].Text = ("×%.2f"):format(1 + (rebirths + 1) * Config.RebirthTntBonus)
		rewardLabels[3].Text = ("×%.2f"):format(1 + (rebirths + 1) * Config.RebirthDistanceBonus)

		rebirthGo.button.Text = ("REBIRTH  (%d)"):format(rebirths)
		UI.setButtonEnabled(rebirthGo, state.rebirthReady == true, C.green, C.greenDeep)
		rebirthOpen.button.Text = state.rebirthReady and "🔄 REBIRTH!" or ("🔄 REBIRTH %d"):format(rebirths)

		-- ----- worlds -----
		for index, world in Config.Worlds do
			local row = worldRows[index]
			if row then
				local unlocked = rebirths >= world.rebirths
				row.sub.Text = unlocked and ("Unlocked  ·  ×%.1f rewards"):format(world.multiplier)
					or ("🔄 Needs Rebirth %d"):format(world.rebirths)
				UI.setButtonEnabled(row.entry, unlocked, C.blue, C.blueDeep)
			end
		end

		-- ----- steamer shop -----
		local steamerPrice = math.floor(state.steamerCost or 0)
		local luckyPrice = math.floor(state.luckySteamerCost or 0)
		buyCoinButton.button.Text = ("BUY  ·  %s 💵"):format(Format.abbreviate(steamerPrice))
		buyGemButton.button.Text = ("BUY  ·  %s 💎"):format(Format.abbreviate(luckyPrice))
		UI.setButtonEnabled(buyCoinButton, (state.coins or 0) >= steamerPrice, C.green, C.greenDeep)
		UI.setButtonEnabled(buyGemButton, (state.gems or 0) >= luckyPrice, C.green, C.greenDeep)

		-- ----- summoned squishies -----
		-- Rebuilding the followers destroys and re-creates real models, so it
		-- only happens when the summoned set actually changed — not on every
		-- click of the steamer, which also fires a sync.
		local active = state.active or {}
		local signature = table.concat(active, ",")
		if signature ~= lastActiveSignature then
			lastActiveSignature = signature

			local specs = {}
			for _, id in active do
				local squishy = Squishies.byId[id]
				if squishy then
					table.insert(specs, {
						shape = squishy.shape,
						color = squishy.color,
						sparkle = squishy.sparkle == true,
						sizeScale = squishy.scale,
					})
				end
			end
			scene.setActiveSquishies(specs)
		end

		boostReadyIn = state.boostReadyIn or 0
		boostLeft = state.boostLeft or 0
	end

	-- The two boost timers tick locally between syncs, so the button counts
	-- down smoothly instead of jumping whenever a click happens to sync.
	task.spawn(function()
		while true do
			task.wait(0.25)
			boostReadyIn = math.max(boostReadyIn - 0.25, 0)
			boostLeft = math.max(boostLeft - 0.25, 0)

			if boostLeft > 0 then
				boost.button.Text = ("🧨 RAINING %ds"):format(math.ceil(boostLeft))
				UI.setButtonEnabled(boost, false, C.red, C.redDeep)
			elseif boostReadyIn > 0 then
				boost.button.Text = ("🧨 %ds"):format(math.ceil(boostReadyIn))
				UI.setButtonEnabled(boost, false, C.red, C.redDeep)
			else
				boost.button.Text = "🧨 RAIN TNT"
				UI.setButtonEnabled(boost, true, C.red, C.redDeep)
			end
		end
	end)
end

return Cannon
