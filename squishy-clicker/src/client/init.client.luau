--!strict
-- ============================================================
--  CLIENT  —  the steamer, the reveal, and the collection.
--  All numbers come from the server via SyncData; this script
--  only draws them and sends requests.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
-- Direct require: Squishies lives at Shared/Squishies. If this ever hangs
-- with an orange "Infinite yield possible" warning in Output, the file was
-- moved — put it back at src/shared/Squishies.luau or update this path.
local Squishies = require(Shared:WaitForChild("Squishies"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClickSteamer = Remotes:WaitForChild("ClickSteamer") :: RemoteEvent
local PrestigeSquishy = Remotes:WaitForChild("PrestigeSquishy") :: RemoteEvent
local SteamerOpened = Remotes:WaitForChild("SteamerOpened") :: RemoteEvent
local SyncData = Remotes:WaitForChild("SyncData") :: RemoteEvent

-- ---------- palette ----------
local COLOR = {
	bg = Color3.fromRGB(255, 244, 236),
	bambooLight = Color3.fromRGB(222, 184, 135),
	bambooDark = Color3.fromRGB(196, 154, 108),
	bambooLine = Color3.fromRGB(176, 134, 90),
	panel = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(74, 52, 38),
	dim = Color3.fromRGB(150, 130, 118),
	mint = Color3.fromRGB(126, 224, 192),
	locked = Color3.fromRGB(228, 222, 216),
	gold = Color3.fromRGB(255, 199, 92),
	white = Color3.fromRGB(255, 255, 255),
	progressBg = Color3.fromRGB(238, 224, 212),
}

-- Latest snapshot from the server.
local state = {
	counts = {} :: { [string]: number },
	stars = {} :: { [string]: number },
	clickProgress = 0,
	clicksToOpen = Config.BaseClicksToOpen,
	totalOpens = 0,
	totalStars = 0,
}

-- ---------- tiny UI helpers ----------
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

local function starString(stars: number): string
	return string.rep("★", stars) .. string.rep("☆", Config.MaxStars - stars)
end

-- Copies needed for a squishy's next star (mirrors the server's math for display).
local function prestigeCost(squishyId: string, currentStar: number): number
	local squishy = Squishies.byId[squishyId]
	local rarity = squishy and Squishies.rarityByName[squishy.rarity]
	if not rarity then
		return math.huge
	end
	return rarity.baseCopies * (Config.PrestigeGrowth ^ currentStar)
end

-- ---------- root gui ----------
local gui = make("ScreenGui", {
	Name = "SquishyClickerUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLOR.bg,
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = gui,
})

-- ---------- header ----------
local header = make("Frame", {
	Size = UDim2.new(0, 340, 0, 64),
	Position = UDim2.new(0.5, -160, 0, 20),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = COLOR.panel,
	BackgroundTransparency = 0.05,
	Parent = gui,
})
corner(18, header)

local headerLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	Text = "🥟 Opens: 0    ⭐ Stars: 0",
	TextColor3 = COLOR.text,
	TextSize = 22,
	Parent = header,
})

-- ---------- the bamboo steamer (center-left) ----------
-- Built from layered rounded frames: a lid that pops off on reveal,
-- and a base that stays put.
local steamerRoot = make("Frame", {
	Size = UDim2.new(0, 300, 0, 260),
	Position = UDim2.new(0.5, -160, 0.5, 20),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Parent = gui,
})

-- Base bowl
local steamerBase = make("Frame", {
	Size = UDim2.new(0, 280, 0, 120),
	Position = UDim2.new(0.5, 0, 1, 0),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = COLOR.bambooLight,
	Parent = steamerRoot,
})
corner(28, steamerBase)
make("Frame", { -- rim line
	Size = UDim2.new(1, 0, 0, 10),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundColor3 = COLOR.bambooLine,
	BorderSizePixel = 0,
	Parent = steamerBase,
})

-- The squishy hiding inside (revealed when the lid pops)
local hiddenSquishy = make("TextLabel", {
	Size = UDim2.new(0, 130, 0, 110),
	Position = UDim2.new(0.5, 0, 0, -46),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = COLOR.white,
	Font = Enum.Font.FredokaOne,
	Text = "•ᴗ•",
	TextColor3 = COLOR.text,
	TextSize = 40,
	Visible = false,
	ZIndex = 3,
	Parent = steamerBase,
})
make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hiddenSquishy })

-- Lid (drawn AFTER the squishy so it covers it until animated away)
local lid = make("Frame", {
	Size = UDim2.new(0, 300, 0, 150),
	Position = UDim2.new(0.5, 0, 0, 0),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = COLOR.bambooDark,
	ZIndex = 5,
	Parent = steamerRoot,
})
corner(40, lid)
make("Frame", { -- weave line 1
	Size = UDim2.new(0.8, 0, 0, 8),
	Position = UDim2.new(0.1, 0, 0.35, 0),
	BackgroundColor3 = COLOR.bambooLine,
	BorderSizePixel = 0,
	ZIndex = 6,
	Parent = lid,
})
make("Frame", { -- weave line 2
	Size = UDim2.new(0.9, 0, 0, 8),
	Position = UDim2.new(0.05, 0, 0.62, 0),
	BackgroundColor3 = COLOR.bambooLine,
	BorderSizePixel = 0,
	ZIndex = 6,
	Parent = lid,
})
make("Frame", { -- handle nub
	Size = UDim2.new(0, 54, 0, 22),
	Position = UDim2.new(0.5, 0, 0, 8),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = COLOR.bambooLine,
	ZIndex = 6,
	Parent = lid,
})

-- Invisible click catcher over the whole steamer
local steamerButton = make("TextButton", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "",
	ZIndex = 10,
	Parent = steamerRoot,
})

make("TextLabel", {
	Size = UDim2.new(0, 300, 0, 24),
	Position = UDim2.new(0.5, -160, 0.5, 170),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "tap the steamer to open it!",
	TextColor3 = COLOR.dim,
	TextSize = 16,
	Parent = gui,
})

-- ---------- click progress bar (under the steamer) ----------
local progressShell = make("Frame", {
	Size = UDim2.new(0, 280, 0, 26),
	Position = UDim2.new(0.5, -160, 0.5, 205),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COLOR.progressBg,
	Parent = gui,
})
corner(13, progressShell)

local progressFill = make("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = COLOR.gold,
	BorderSizePixel = 0,
	Parent = progressShell,
})
corner(13, progressFill)

local progressLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "0 / 10",
	TextColor3 = COLOR.text,
	TextSize = 14,
	ZIndex = 2,
	Parent = progressShell,
})

-- ---------- steamer animations ----------
local lidHome = lid.Position
local revealing = false

local function wobbleLid()
	TweenService:Create(
		lid,
		TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = lidHome + UDim2.new(0, 0, 0, -8), Rotation = (math.random() - 0.5) * 6 }
	):Play()
	task.delay(0.06, function()
		if revealing then
			return
		end
		TweenService:Create(
			lid,
			TweenInfo.new(0.2, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ Position = lidHome, Rotation = 0 }
		):Play()
	end)
end

steamerButton.Activated:Connect(function()
	if revealing then
		return -- let the reveal finish before more clicks count visually
	end
	wobbleLid()
	ClickSteamer:FireServer()
end)

-- ---------- inventory / collection (right side) ----------
local panel = make("Frame", {
	Size = UDim2.new(0, 320, 0, 480),
	Position = UDim2.new(1, -20, 0.5, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	BackgroundColor3 = COLOR.panel,
	BackgroundTransparency = 0.05,
	Parent = gui,
})
corner(20, panel)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	Text = "My Squishies",
	TextColor3 = COLOR.text,
	TextSize = 24,
	Parent = panel,
})

local invList = make("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -52),
	Position = UDim2.new(0, 8, 0, 44),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = panel,
})
make("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = invList,
})

type Row = {
	countLabel: TextLabel,
	starLabel: TextLabel,
	prestige: TextButton,
	icon: TextLabel,
}
local rows: { [string]: Row } = {}

for index, squishy in Squishies.list do
	local rarity = Squishies.rarityByName[squishy.rarity]

	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Color3.fromRGB(252, 248, 244),
		LayoutOrder = index,
		Parent = invList,
	})
	corner(14, row)

	-- the dumpling itself: colored circle with a face
	local icon = make("TextLabel", {
		Size = UDim2.new(0, 56, 0, 56),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = squishy.color,
		Font = Enum.Font.FredokaOne,
		Text = squishy.sparkle and "✧•ᴗ•✧" or "•ᴗ•",
		TextColor3 = COLOR.text,
		TextSize = squishy.sparkle and 13 or 18,
		Parent = row,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = icon })

	make("TextLabel", {
		Size = UDim2.new(1, -170, 0, 22),
		Position = UDim2.new(0, 76, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = squishy.name,
		TextColor3 = COLOR.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -170, 0, 16),
		Position = UDim2.new(0, 76, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = squishy.rarity,
		TextColor3 = rarity and rarity.color or COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local starLabel = make("TextLabel", {
		Size = UDim2.new(1, -170, 0, 16),
		Position = UDim2.new(0, 76, 0, 48),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = starString(0),
		TextColor3 = COLOR.gold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local countLabel = make("TextLabel", {
		Size = UDim2.new(1, -170, 0, 16),
		Position = UDim2.new(0, 76, 0, 64),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "x0",
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local prestige = make("TextButton", {
		Size = UDim2.new(0, 84, 0, 60),
		Position = UDim2.new(1, -92, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLOR.locked,
		AutoButtonColor = false,
		Font = Enum.Font.FredokaOne,
		Text = "",
		TextColor3 = COLOR.text,
		TextSize = 13,
		TextWrapped = true,
		Parent = row,
	})
	corner(12, prestige)

	local id = squishy.id
	prestige.Activated:Connect(function()
		PrestigeSquishy:FireServer(id)
	end)

	rows[id] = { countLabel = countLabel, starLabel = starLabel, prestige = prestige, icon = icon }
end

-- ---------- reveal animation ----------
local function playReveal(squishyId: string)
	local squishy = Squishies.byId[squishyId]
	if not squishy then
		return
	end
	local rarity = Squishies.rarityByName[squishy.rarity]
	revealing = true

	-- Show the squishy inside the base, pop the lid up and off.
	hiddenSquishy.BackgroundColor3 = squishy.color
	hiddenSquishy.Text = squishy.sparkle and "✧•ᴗ•✧" or "•ᴗ•"
	hiddenSquishy.Visible = true

	TweenService:Create(
		lid,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Position = lidHome + UDim2.new(0, 90, 0, -170), Rotation = 24 }
	):Play()

	-- Banner naming the pull, colored by rarity.
	local banner = make("TextLabel", {
		Size = UDim2.new(0, 300, 0, 54),
		Position = UDim2.new(0.5, -160, 0.5, -170),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rarity and rarity.color or COLOR.gold,
		Font = Enum.Font.FredokaOne,
		Text = ("%s!"):format(squishy.name),
		TextColor3 = COLOR.white,
		TextSize = 22,
		ZIndex = 15,
		Parent = gui,
	})
	corner(16, banner)
	banner.Rotation = -4

	-- Sparkles for the fancy ones.
	if squishy.sparkle then
		for _ = 1, 6 do
			local spark = make("TextLabel", {
				Size = UDim2.new(0, 30, 0, 30),
				Position = UDim2.new(0.5, -160 + math.random(-130, 130), 0.5, math.random(-120, 60)),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.FredokaOne,
				Text = "✦",
				TextColor3 = COLOR.gold,
				TextSize = math.random(18, 30),
				ZIndex = 14,
				Parent = gui,
			})
			TweenService:Create(
				spark,
				TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = spark.Position + UDim2.new(0, 0, 0, -50), TextTransparency = 1 }
			):Play()
			task.delay(1.2, function()
				spark:Destroy()
			end)
		end
	end

	-- Put everything back after a moment.
	task.delay(1.35, function()
		banner:Destroy()
		hiddenSquishy.Visible = false
		lid.Position = lidHome + UDim2.new(0, 0, 0, -40)
		lid.Rotation = 0
		TweenService
			:Create(lid, TweenInfo.new(0.25, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Position = lidHome })
			:Play()
		revealing = false
	end)
end

SteamerOpened.OnClientEvent:Connect(playReveal)

-- ---------- redraw from server state ----------
local function refresh()
	headerLabel.Text = ("🥟 Opens: %d    ⭐ Stars: %d"):format(state.totalOpens, state.totalStars)

	progressLabel.Text = ("%d / %d"):format(state.clickProgress, state.clicksToOpen)
	local frac = math.clamp(state.clickProgress / math.max(state.clicksToOpen, 1), 0, 1)
	TweenService:Create(
		progressFill,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(frac, 0, 1, 0) }
	):Play()

	for id, row in rows do
		local held = state.counts[id] or 0
		local star = state.stars[id] or 0

		row.countLabel.Text = "x" .. held
		row.starLabel.Text = starString(star)

		-- Undiscovered squishies show as dark silhouettes — the collection tease.
		local squishy = Squishies.byId[id]
		local discovered = held > 0 or star > 0
		if squishy then
			row.icon.BackgroundColor3 = discovered and squishy.color or Color3.fromRGB(90, 82, 76)
			row.icon.Text = discovered and (squishy.sparkle and "✧•ᴗ•✧" or "•ᴗ•") or "?"
		end

		if star >= Config.MaxStars then
			row.prestige.Text = "MAX ⭐"
			row.prestige.BackgroundColor3 = COLOR.gold
			row.prestige.AutoButtonColor = false
		else
			local cost = prestigeCost(id, star)
			row.prestige.Text = ("%d/%d\n→ %d★"):format(math.min(held, cost), cost, star + 1)
			if held >= cost then
				row.prestige.BackgroundColor3 = COLOR.mint
				row.prestige.AutoButtonColor = true
			else
				row.prestige.BackgroundColor3 = COLOR.locked
				row.prestige.AutoButtonColor = false
			end
		end
	end
end

SyncData.OnClientEvent:Connect(function(payload)
	state = payload
	refresh()
end)

refresh()
print("[SquishyClicker] Client UI ready.")
