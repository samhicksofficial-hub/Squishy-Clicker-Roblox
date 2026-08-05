--!strict
-- ============================================================
--  CANNON HUD  —  the wallet, the nav rail, and every panel
--  behind it: Upgrades, Rebirth, Worlds, Pets and the Game Shop.
--
--  The launcher is the main game, so this owns most of what is on
--  screen. Everything is built through UI.luau, which means the
--  chunky-outline look is defined in one place rather than
--  re-typed here.
--
--  Everything is a BUTTON and a NUMBER. Every button fires a bare
--  request — "the next power level", "hatch this egg", "equip
--  this pet" — and every number comes from the last sync. Prices
--  are never worked out locally: the server sends the finished
--  figure, so the price shown and the price charged are the same
--  number by construction rather than by two copies of a formula
--  agreeing with each other.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Pets = require(Shared:WaitForChild("Pets"))
local UI = require(script.Parent:WaitForChild("UI"))

local Cannon = {}

-- Replaced on mount, so a sync arriving before the UI is up is harmless.
function Cannon.update(_state: any) end

local C = UI.color

function Cannon.mount(gui: ScreenGui, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local buyPower = remotes:WaitForChild("BuyPower") :: RemoteEvent
	local doRebirth = remotes:WaitForChild("DoRebirth") :: RemoteEvent
	local hatchEgg = remotes:WaitForChild("HatchEgg") :: RemoteEvent
	local togglePet = remotes:WaitForChild("TogglePet") :: RemoteEvent
	local activateBoost = remotes:WaitForChild("ActivateBoost") :: RemoteEvent
	local eggHatched = remotes:WaitForChild("EggHatched") :: RemoteEvent

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

	local petsPanel = UI.panel({
		parent = gui,
		name = "PetsPanel",
		size = UDim2.new(0, 440, 0, 420),
		position = UDim2.fromScale(0.5, 0.5),
		icon = "🥚",
		title = "Pets",
		top = C.purple,
		bottom = C.purpleDeep,
	})
	panels.pets = petsPanel

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
	railButton(5, "🥚", "PETS", C.purple, C.purpleDeep, function()
		showOnly("pets")
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

	-- ---------- Pets panel ----------
	local eggButtons: { [string]: UI.Button } = {}
	for index, egg in Pets.eggs do
		local entry = UI.button({
			parent = petsPanel.body,
			size = UDim2.new(0, 130, 0, 74),
			position = UDim2.new(0, 12 + (index - 1) * 140, 0, 10),
			text = "",
			top = egg.costGems and C.gem or C.cash,
			bottom = egg.costGems and Color3.fromRGB(64, 190, 190) or Color3.fromRGB(84, 186, 60),
			zIndex = 23,
		})
		UI.label({
			Size = UDim2.new(1, -8, 0, 40),
			Position = UDim2.new(0, 4, 0, 4),
			Text = "🥚 " .. egg.name,
			TextSize = 15,
			TextWrapped = true,
			ZIndex = 24,
			Parent = entry.button,
		})
		UI.label({
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.new(0, 4, 0, 46),
			Text = "",
			TextSize = 16,
			Name = "Price",
			ZIndex = 24,
			Parent = entry.button,
		})

		local id = egg.id
		entry.button.Activated:Connect(function()
			hatchEgg:FireServer(id)
		end)
		eggButtons[egg.id] = entry
	end

	local petHeader = UI.label({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.new(0, 12, 0, 92),
		Text = "Equipped 0/5",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 23,
		Parent = petsPanel.body,
	})

	local petList = UI.make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -132),
		Position = UDim2.new(0, 12, 0, 120),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 23,
		Parent = petsPanel.body,
	})
	UI.make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = petList,
	})

	-- Rows are rebuilt on change rather than pooled: the inventory only moves
	-- when a pet is hatched or toggled, which is nothing like per-frame.
	local function drawPets(owned: { string }, equipped: { string })
		for _, child in petList:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		-- Collapse duplicates into "×3" rows, and count how many of each are
		-- currently out, so a row can show two of three equipped.
		local counts: { [string]: number } = {}
		local order: { string } = {}
		for _, id in owned do
			if counts[id] == nil then
				counts[id] = 0
				table.insert(order, id)
			end
			counts[id] += 1
		end
		local out: { [string]: number } = {}
		for _, id in equipped do
			out[id] = (out[id] or 0) + 1
		end

		-- Best first, so the pets worth equipping are the ones on screen.
		table.sort(order, function(a, b)
			local left, right = Pets.byId[a], Pets.byId[b]
			if not left or not right then
				return false
			end
			local rankA = Pets.rarityRank[left.rarity] or 0
			local rankB = Pets.rarityRank[right.rarity] or 0
			if rankA ~= rankB then
				return rankA > rankB
			end
			return left.name < right.name
		end)

		for index, id in order do
			local pet = Pets.byId[id]
			if pet then
				local equippedHere = out[id] or 0
				local rarity = Pets.rarityByName[pet.rarity]
				local rarityColor = rarity and rarity.color or pet.color

				local entry = UI.button({
					parent = petList,
					size = UDim2.new(1, -10, 0, 52),
					text = "",
					top = equippedHere > 0 and C.green or C.row,
					bottom = equippedHere > 0 and C.greenDeep or Color3.fromRGB(92, 56, 26),
					zIndex = 24,
					radius = 10,
				})
				entry.button.LayoutOrder = index

				local swatch = UI.make("Frame", {
					Size = UDim2.new(0, 12, 1, -14),
					Position = UDim2.new(0, 8, 0, 7),
					BackgroundColor3 = rarityColor,
					ZIndex = 25,
					Parent = entry.button,
				})
				UI.corner(6, swatch)
				UI.stroke(swatch, 2)

				-- Only the stats a pet actually has, so a one-trick pet reads
				-- as a one-trick pet rather than as four zeroes.
				local stats: { string } = {}
				if pet.power then
					table.insert(stats, ("+%d%% pow"):format(pet.power * 100))
				end
				if pet.coins then
					table.insert(stats, ("+%d%% cash"):format(pet.coins * 100))
				end
				if pet.gems then
					table.insert(stats, ("+%d%% gem"):format(pet.gems * 100))
				end
				if pet.tnt then
					table.insert(stats, ("+%d%% tnt"):format(pet.tnt * 100))
				end
				if pet.magnet then
					table.insert(stats, ("+%g mag"):format(pet.magnet))
				end

				UI.label({
					Size = UDim2.new(1, -34, 0, 24),
					Position = UDim2.new(0, 28, 0, 4),
					Text = ("%s  ×%d  (%d out)"):format(pet.name, counts[id], equippedHere),
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 25,
					Parent = entry.button,
				})
				UI.label({
					Size = UDim2.new(1, -34, 0, 20),
					Position = UDim2.new(0, 28, 0, 27),
					Text = table.concat(stats, "  "),
					TextSize = 13,
					TextColor3 = Color3.fromRGB(252, 226, 180),
					TextXAlignment = Enum.TextXAlignment.Left,
					StrokeThickness = 1.5,
					ZIndex = 25,
					Parent = entry.button,
				})

				-- One tap equips another copy; once they are all out, it puts
				-- one away. The server re-checks both, so this is only the
				-- friendly reading of the same rule.
				local petId = id
				local allOut = equippedHere >= counts[id]
				entry.button.Activated:Connect(function()
					togglePet:FireServer(petId, not allOut)
				end)
			end
		end
	end

	-- ---------- hatch reveal ----------
	eggHatched.OnClientEvent:Connect(function(petId)
		local pet = typeof(petId) == "string" and Pets.byId[petId]
		if not pet then
			return
		end
		local rarity = Pets.rarityByName[pet.rarity]

		local banner = UI.make("Frame", {
			Size = UDim2.new(0, 360, 0, 76),
			Position = UDim2.new(0.5, 0, 0, 150),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = rarity and rarity.color or pet.color,
			ZIndex = 40,
			Parent = gui,
		})
		UI.corner(16, banner)
		UI.gradient(banner, rarity and rarity.color or pet.color, pet.color)
		UI.stroke(banner, 4)

		UI.label({
			Size = UDim2.fromScale(1, 1),
			Text = ("🥚 %s!\n%s"):format(pet.name, pet.rarity),
			TextSize = 24,
			ZIndex = 41,
			Parent = banner,
		})

		banner.BackgroundTransparency = 1
		TweenService:Create(banner, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
		task.delay(2.6, function()
			TweenService:Create(banner, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
			task.delay(0.45, function()
				banner:Destroy()
			end)
		end)
	end)

	-- ---------- redraw from the server's numbers ----------
	local lastPetSignature = ""
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

		-- ----- eggs -----
		for _, egg in Pets.eggs do
			local entry = eggButtons[egg.id]
			if entry then
				local canPay = (egg.costGems ~= nil and (state.gems or 0) >= egg.costGems)
					or (egg.costCoins ~= nil and (state.coins or 0) >= egg.costCoins)
				local price = entry.button:FindFirstChild("Price") :: TextLabel?
				if price then
					price.Text = ("%s %s"):format(
						Format.abbreviate(egg.costGems or egg.costCoins or 0),
						egg.costGems and "💎" or "💵"
					)
				end
				UI.setButtonEnabled(
					entry,
					canPay,
					egg.costGems and C.gem or C.cash,
					egg.costGems and Color3.fromRGB(64, 190, 190) or Color3.fromRGB(84, 186, 60)
				)
			end
		end

		-- ----- pets -----
		local owned = state.pets or {}
		local equipped = state.equipped or {}
		petHeader.Text = ("Equipped %d/%d  ·  %d owned"):format(#equipped, Config.MaxEquippedPets, #owned)

		-- Rebuilding the list costs a few dozen instances, so it only happens
		-- when the inventory actually changed — not on every click of the
		-- steamer, which also fires a sync.
		local signature = table.concat(owned, ",") .. "|" .. table.concat(equipped, ",")
		if signature ~= lastPetSignature then
			lastPetSignature = signature
			drawPets(owned, equipped)

			local colors: { Color3 } = {}
			for _, id in equipped do
				local pet = Pets.byId[id]
				if pet then
					table.insert(colors, pet.color)
				end
			end
			scene.setPets(colors)
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
