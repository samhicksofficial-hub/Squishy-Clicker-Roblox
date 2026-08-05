--!strict
-- ============================================================
--  CANNON PROGRESSION  —  the currency bar, the power shop,
--  rebirth, the egg station, the pet inventory and Rain TNT.
--
--  Everything here is a BUTTON and a NUMBER. Every button fires a
--  bare request — "I would like the next power level", "hatch
--  this egg", "equip this pet" — and every number is drawn from
--  the last sync. Prices are never worked out locally: the server
--  sends the finished figure, so the price shown and the price
--  charged are the same number by construction rather than by two
--  copies of a formula agreeing.
--
--  Rendered as one slide-out drawer rather than four panels, so
--  the 3D stage stays visible, which is the whole reason the HUD
--  is kept to the edges of the screen.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local Pets = require(Shared:WaitForChild("Pets"))

local Cannon = {}

-- Replaced on mount, so a sync arriving before the UI is up is harmless.
function Cannon.update(_state: any) end

local COLOR = {
	panel = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(74, 52, 38),
	dim = Color3.fromRGB(150, 130, 118),
	row = Color3.fromRGB(246, 240, 234),
	go = Color3.fromRGB(126, 224, 192),
	locked = Color3.fromRGB(228, 222, 216),
	tnt = Color3.fromRGB(232, 118, 58),
	coin = Color3.fromRGB(250, 196, 76),
	gem = Color3.fromRGB(110, 220, 212),
	rebirth = Color3.fromRGB(198, 140, 245),
	boost = Color3.fromRGB(240, 130, 90),
}

local function make(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	return inst
end

local function corner(radius: number, parent: Instance)
	make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

function Cannon.mount(gui: ScreenGui, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local buyPower = remotes:WaitForChild("BuyPower") :: RemoteEvent
	local doRebirth = remotes:WaitForChild("DoRebirth") :: RemoteEvent
	local hatchEgg = remotes:WaitForChild("HatchEgg") :: RemoteEvent
	local togglePet = remotes:WaitForChild("TogglePet") :: RemoteEvent
	local activateBoost = remotes:WaitForChild("ActivateBoost") :: RemoteEvent
	local eggHatched = remotes:WaitForChild("EggHatched") :: RemoteEvent

	-- ---------- the currency bar ----------
	-- Top right, always visible: in a simulator the balances are the score.
	local wallet = make("Frame", {
		Name = "Wallet",
		Size = UDim2.new(0, 216, 0, 116),
		Position = UDim2.new(1, -20, 0, 20),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = gui,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = wallet,
	})

	local function walletRow(order: number, color: Color3, icon: string): TextLabel
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = COLOR.panel,
			BackgroundTransparency = 0.1,
			LayoutOrder = order,
			ZIndex = 5,
			Parent = wallet,
		})
		corner(14, row)

		make("TextLabel", {
			Size = UDim2.new(0, 30, 1, 0),
			Position = UDim2.new(0, 6, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.FredokaOne,
			Text = icon,
			TextColor3 = color,
			TextSize = 18,
			ZIndex = 6,
			Parent = row,
		})
		return make("TextLabel", {
			Size = UDim2.new(1, -44, 1, 0),
			Position = UDim2.new(0, 38, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "0",
			TextColor3 = COLOR.text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
			Parent = row,
		})
	end

	local tntLabel = walletRow(1, COLOR.tnt, "🧨")
	local coinLabel = walletRow(2, COLOR.coin, "🪙")
	local gemLabel = walletRow(3, COLOR.gem, "💎")

	-- ---------- Rain TNT ----------
	local boostButton = make("TextButton", {
		Name = "BoostButton",
		Size = UDim2.new(0, 216, 0, 42),
		Position = UDim2.new(1, -20, 0, 144),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLOR.boost,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "🧨 RAIN TNT",
		TextColor3 = COLOR.text,
		TextSize = 17,
		ZIndex = 5,
		Parent = gui,
	})
	corner(14, boostButton)
	boostButton.Activated:Connect(function()
		activateBoost:FireServer()
	end)

	-- ---------- the drawer ----------
	local drawerOpen = false
	local drawer = make("Frame", {
		Name = "CannonDrawer",
		Size = UDim2.new(0, 300, 0, 430),
		Position = UDim2.new(1, 20, 0, 196),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.06,
		Active = true, -- swallow its own taps, never the squisher's
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	})
	corner(18, drawer)

	local drawerButton = make("TextButton", {
		Size = UDim2.new(0, 216, 0, 40),
		Position = UDim2.new(1, -20, 0, 194),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = COLOR.go,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "⚙ Upgrades & Pets",
		TextColor3 = COLOR.text,
		TextSize = 16,
		ZIndex = 5,
		Parent = gui,
	})
	corner(14, drawerButton)

	drawerButton.Activated:Connect(function()
		drawerOpen = not drawerOpen
		drawer.Visible = true
		TweenService
			:Create(drawer, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = drawerOpen and UDim2.new(1, -20, 0, 244) or UDim2.new(1, 20, 0, 244),
			})
			:Play()
		if not drawerOpen then
			task.delay(0.24, function()
				if not drawerOpen then
					drawer.Visible = false
				end
			end)
		end
	end)

	-- ---------- launch power ----------
	make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0, 10, 0, 10),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "Launch Power",
		TextColor3 = COLOR.text,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
		Parent = drawer,
	})

	local powerLabel = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0, 10, 0, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "Lv 0  ·  power 120",
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
		Parent = drawer,
	})

	local powerButton = make("TextButton", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.new(0, 10, 0, 54),
		BackgroundColor3 = COLOR.tnt,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "UPGRADE  ·  25 🧨",
		TextColor3 = COLOR.text,
		TextSize = 16,
		ZIndex = 9,
		Parent = drawer,
	})
	corner(12, powerButton)
	powerButton.Activated:Connect(function()
		buyPower:FireServer()
	end)

	-- ---------- rebirth ----------
	local rebirthLabel = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0, 10, 0, 102),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
		Parent = drawer,
	})

	local rebirthButton = make("TextButton", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.new(0, 10, 0, 122),
		BackgroundColor3 = COLOR.rebirth,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "REBIRTH",
		TextColor3 = COLOR.text,
		TextSize = 16,
		ZIndex = 9,
		Parent = drawer,
	})
	corner(12, rebirthButton)
	rebirthButton.Activated:Connect(function()
		doRebirth:FireServer()
	end)

	-- ---------- eggs ----------
	make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 170),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "Eggs",
		TextColor3 = COLOR.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
		Parent = drawer,
	})

	local eggButtons: { [string]: TextButton } = {}
	for index, egg in Pets.eggs do
		local button = make("TextButton", {
			Size = UDim2.new(0, 90, 0, 38),
			Position = UDim2.new(0, 10 + (index - 1) * 94, 0, 192),
			BackgroundColor3 = egg.costGems and COLOR.gem or COLOR.coin,
			AutoButtonColor = true,
			Font = Enum.Font.GothamBold,
			Text = egg.name,
			TextColor3 = COLOR.text,
			TextSize = 11,
			ZIndex = 9,
			Parent = drawer,
		})
		corner(10, button)
		eggButtons[egg.id] = button

		local id = egg.id
		button.Activated:Connect(function()
			hatchEgg:FireServer(id)
		end)
	end

	-- ---------- pets ----------
	local petHeader = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 238),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "Pets  0/5 equipped",
		TextColor3 = COLOR.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 9,
		Parent = drawer,
	})

	local petList = make("ScrollingFrame", {
		Size = UDim2.new(1, -20, 0, 160),
		Position = UDim2.new(0, 10, 0, 260),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 9,
		Parent = drawer,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 4),
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
		-- currently out, so the row can show 1/3 equipped.
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

				local row = make("TextButton", {
					Size = UDim2.new(1, -6, 0, 34),
					BackgroundColor3 = equippedHere > 0 and COLOR.go or COLOR.row,
					AutoButtonColor = true,
					Font = Enum.Font.GothamBold,
					Text = "",
					LayoutOrder = index,
					ZIndex = 10,
					Parent = petList,
				})
				corner(8, row)

				make("Frame", {
					Size = UDim2.new(0, 6, 1, -10),
					Position = UDim2.new(0, 5, 0, 5),
					BackgroundColor3 = rarity and rarity.color or pet.color,
					BorderSizePixel = 0,
					ZIndex = 11,
					Parent = row,
				})

				-- Only the stats a pet actually has, so a one-trick pet reads
				-- as a one-trick pet rather than as three zeroes.
				local stats: { string } = {}
				if pet.power then
					table.insert(stats, ("+%d%% pow"):format(pet.power * 100))
				end
				if pet.coins then
					table.insert(stats, ("+%d%% coin"):format(pet.coins * 100))
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

				make("TextLabel", {
					Size = UDim2.new(1, -22, 0, 16),
					Position = UDim2.new(0, 16, 0, 2),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Text = ("%s  ×%d  (%d out)"):format(pet.name, counts[id], equippedHere),
					TextColor3 = COLOR.text,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 11,
					Parent = row,
				})
				make("TextLabel", {
					Size = UDim2.new(1, -22, 0, 14),
					Position = UDim2.new(0, 16, 0, 17),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamMedium,
					Text = table.concat(stats, "  "),
					TextColor3 = COLOR.dim,
					TextSize = 10,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 11,
					Parent = row,
				})

				-- One tap equips another copy; once they are all out, it puts
				-- one away. The server re-checks both, so this is only the
				-- friendly reading of the same rule.
				local petId = id
				local allOut = equippedHere >= counts[id]
				row.Activated:Connect(function()
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

		local banner = make("TextLabel", {
			Size = UDim2.new(0, 340, 0, 62),
			Position = UDim2.new(0.5, 0, 0, 170),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = rarity and rarity.color or pet.color,
			Font = Enum.Font.FredokaOne,
			Text = ("🥚 %s!\n%s"):format(pet.name, pet.rarity),
			TextColor3 = COLOR.text,
			TextSize = 20,
			ZIndex = 28,
			Parent = gui,
		})
		corner(16, banner)

		banner.TextTransparency = 1
		banner.BackgroundTransparency = 1
		TweenService:Create(banner, TweenInfo.new(0.25), { TextTransparency = 0, BackgroundTransparency = 0.08 }):Play()
		task.delay(2.6, function()
			TweenService:Create(banner, TweenInfo.new(0.35), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
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

		local level = state.powerLevel or 0
		local cost = state.powerCost or 0
		powerLabel.Text = ("Lv %d  ·  power %s  ·  magnet %.0f"):format(
			level,
			Format.abbreviate(math.floor(state.launchPower or 0)),
			state.magnet or 0
		)

		local maxed = level >= Config.LaunchMaxPowerLevel
		local affordable = (state.tnt or 0) >= cost
		powerButton.Text = maxed and "MAXED" or ("UPGRADE  ·  %s 🧨"):format(Format.abbreviate(cost))
		powerButton.BackgroundColor3 = (not maxed and affordable) and COLOR.tnt or COLOR.locked
		powerButton.AutoButtonColor = not maxed and affordable

		local rebirths = state.rebirths or 0
		rebirthLabel.Text = ("Rebirths: %d  ·  next at %s studs"):format(
			rebirths,
			Format.abbreviate(math.floor(state.rebirthAt or 0))
		)
		rebirthButton.Text = state.rebirthReady and ("REBIRTH  →  ×%.1f distance"):format(
			1 + (rebirths + 1) * Config.RebirthDistanceBonus
		) or ("REBIRTH  ·  %s / %s"):format(
			Format.abbreviate(math.floor(state.bestDistance or 0)),
			Format.abbreviate(math.floor(state.rebirthAt or 0))
		)
		rebirthButton.BackgroundColor3 = state.rebirthReady and COLOR.rebirth or COLOR.locked
		rebirthButton.AutoButtonColor = state.rebirthReady == true

		for _, egg in Pets.eggs do
			local button = eggButtons[egg.id]
			if button then
				local canPay = (egg.costGems and (state.gems or 0) >= egg.costGems)
					or (egg.costCoins and (state.coins or 0) >= egg.costCoins)
				button.Text = ("%s\n%s %s"):format(
					egg.name,
					Format.abbreviate(egg.costGems or egg.costCoins or 0),
					egg.costGems and "💎" or "🪙"
				)
				button.BackgroundColor3 = canPay and (egg.costGems and COLOR.gem or COLOR.coin) or COLOR.locked
				button.AutoButtonColor = canPay == true
			end
		end

		local owned = state.pets or {}
		local equipped = state.equipped or {}
		petHeader.Text = ("Pets  %d/%d equipped  ·  %d owned"):format(
			#equipped,
			Config.MaxEquippedPets,
			#owned
		)

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
				boostButton.Text = ("🧨 RAINING  %ds"):format(math.ceil(boostLeft))
				boostButton.BackgroundColor3 = COLOR.boost
				boostButton.AutoButtonColor = false
			elseif boostReadyIn > 0 then
				boostButton.Text = ("🧨 %ds"):format(math.ceil(boostReadyIn))
				boostButton.BackgroundColor3 = COLOR.locked
				boostButton.AutoButtonColor = false
			else
				boostButton.Text = "🧨 RAIN TNT"
				boostButton.BackgroundColor3 = COLOR.boost
				boostButton.AutoButtonColor = true
			end
		end
	end)
end

return Cannon
