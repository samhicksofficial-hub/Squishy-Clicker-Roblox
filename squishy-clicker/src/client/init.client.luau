--!strict
-- ============================================================
--  CLIENT  —  everything the player sees and touches.
--  It never decides the numbers itself; it asks the server
--  and redraws whatever the server sends back via SyncData.
--  The whole UI is built in code so it lives in Git with the
--  rest of the project (no manually-placed GUI to lose).
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Squishies = require(Shared:WaitForChild("Squishies"))
local Format = require(Shared:WaitForChild("Format"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClickSquishy = Remotes:WaitForChild("ClickSquishy") :: RemoteEvent
local BuySquishy = Remotes:WaitForChild("BuySquishy") :: RemoteEvent
local SyncData = Remotes:WaitForChild("SyncData") :: RemoteEvent

-- ---------- palette ----------
local COLOR = {
	pink = Color3.fromRGB(255, 143, 177),
	purple = Color3.fromRGB(182, 146, 246),
	mint = Color3.fromRGB(126, 224, 192),
	panel = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(58, 46, 74),
	dim = Color3.fromRGB(140, 130, 155),
	locked = Color3.fromRGB(210, 205, 215),
}

-- Latest snapshot from the server. Everything on screen reads from this.
local state = { squish = 0, owned = {}, perClick = 1, perSecond = 0 }

-- ---------- tiny UI helper ----------
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

-- ---------- root gui ----------
local gui = make("ScreenGui", {
	Name = "SquishyClickerUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Soft background wash so it reads as its own screen, not the baseplate.
make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 241, 247),
	BorderSizePixel = 0,
	ZIndex = 0,
	Parent = gui,
})

-- ---------- currency panel (top) ----------
local topPanel = make("Frame", {
	Size = UDim2.new(0, 320, 0, 84),
	Position = UDim2.new(0.5, 0, 0, 24),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = COLOR.panel,
	BackgroundTransparency = 0.05,
	Parent = gui,
})
corner(20, topPanel)

local squishLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 44),
	Position = UDim2.new(0, 0, 0, 8),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	Text = "🫧 0",
	TextColor3 = COLOR.text,
	TextSize = 34,
	Parent = topPanel,
})

local rateLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 22),
	Position = UDim2.new(0, 0, 0, 52),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = COLOR.dim,
	TextSize = 14,
	Parent = topPanel,
})

-- ---------- the big squishy (center) ----------
local squishyButton = make("TextButton", {
	Size = UDim2.new(0, 240, 0, 240),
	Position = UDim2.new(0.5, 0, 0.5, 10),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COLOR.purple,
	BackgroundTransparency = 0.15,
	AutoButtonColor = false,
	Font = Enum.Font.FredokaOne,
	Text = "🍑",
	TextSize = 130,
	TextColor3 = COLOR.text,
	Parent = gui,
})
make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = squishyButton })

make("TextLabel", {
	Size = UDim2.new(0, 260, 0, 24),
	Position = UDim2.new(0.5, 0, 0.5, 150),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "tap the squishy!",
	TextColor3 = COLOR.dim,
	TextSize = 16,
	Parent = gui,
})

-- squish bounce + floating "+N" on every tap
local baseSize = squishyButton.Size
local squashed = UDim2.new(0, 210, 0, 210)

local function playSquish()
	TweenService:Create(
		squishyButton,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = squashed }
	):Play()
	task.delay(0.08, function()
		TweenService:Create(
			squishyButton,
			TweenInfo.new(0.28, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ Size = baseSize }
		):Play()
	end)
end

local function floatText(amount: number)
	local label = make("TextLabel", {
		Size = UDim2.new(0, 120, 0, 40),
		Position = UDim2.new(0.5, math.random(-40, 40), 0.5, -60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "+" .. Format.abbreviate(amount),
		TextColor3 = COLOR.pink,
		TextSize = 28,
		Parent = gui,
	})
	TweenService:Create(
		label,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = label.Position + UDim2.new(0, 0, 0, -70), TextTransparency = 1 }
	):Play()
	task.delay(0.7, function()
		label:Destroy()
	end)
end

squishyButton.Activated:Connect(function()
	-- Optimistic feedback: animate now, let the server confirm the real total.
	playSquish()
	floatText(state.perClick)
	ClickSquishy:FireServer()
end)

-- ---------- shop (right side) ----------
local shop = make("Frame", {
	Size = UDim2.new(0, 300, 0, 420),
	Position = UDim2.new(1, -24, 0.5, 10),
	AnchorPoint = Vector2.new(1, 0.5),
	BackgroundColor3 = COLOR.panel,
	BackgroundTransparency = 0.05,
	Parent = gui,
})
corner(20, shop)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	Text = "Squishy Shop",
	TextColor3 = COLOR.text,
	TextSize = 24,
	Parent = shop,
})

local shopList = make("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -52),
	Position = UDim2.new(0, 8, 0, 44),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = shop,
})
make("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = shopList,
})

-- Build one row per squishy and remember its parts so we can update them.
type Row = { buy: TextButton, info: TextLabel }
local rows: { [string]: Row } = {}

for index, squishy in Squishies.list do
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundColor3 = Color3.fromRGB(250, 246, 255),
		LayoutOrder = index,
		Parent = shopList,
	})
	corner(14, row)

	make("TextLabel", {
		Size = UDim2.new(0, 56, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = squishy.emoji,
		TextSize = 40,
		Parent = row,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -140, 0, 24),
		Position = UDim2.new(0, 60, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = squishy.name,
		TextColor3 = COLOR.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local info = make("TextLabel", {
		Size = UDim2.new(1, -140, 0, 20),
		Position = UDim2.new(0, 60, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = ("+%d/tap  +%d/s"):format(squishy.perClick, squishy.perSecond),
		TextColor3 = COLOR.dim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local buy = make("TextButton", {
		Size = UDim2.new(0, 72, 0, 56),
		Position = UDim2.new(1, -80, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLOR.mint,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "🫧 " .. Format.abbreviate(squishy.cost),
		TextColor3 = COLOR.text,
		TextSize = 15,
		Parent = row,
	})
	corner(12, buy)

	local id = squishy.id
	buy.Activated:Connect(function()
		BuySquishy:FireServer(id)
	end)

	rows[id] = { buy = buy, info = info }
end

-- ---------- redraw from server state ----------
local function refresh()
	squishLabel.Text = "🫧 " .. Format.abbreviate(state.squish)
	rateLabel.Text = ("+%s / tap   •   +%s / sec"):format(
		Format.abbreviate(state.perClick),
		Format.abbreviate(state.perSecond)
	)

	for id, row in rows do
		local squishy = Squishies.byId[id]
		if state.owned[id] then
			row.buy.Text = "Owned ✓"
			row.buy.BackgroundColor3 = COLOR.locked
			row.buy.AutoButtonColor = false
		elseif squishy and state.squish >= squishy.cost then
			row.buy.Text = "🫧 " .. Format.abbreviate(squishy.cost)
			row.buy.BackgroundColor3 = COLOR.mint
			row.buy.AutoButtonColor = true
		elseif squishy then
			row.buy.Text = "🫧 " .. Format.abbreviate(squishy.cost)
			row.buy.BackgroundColor3 = Color3.fromRGB(235, 232, 240)
			row.buy.AutoButtonColor = true
		end
	end
end

SyncData.OnClientEvent:Connect(function(payload)
	state = payload
	refresh()
end)

refresh()
print("[SquishyClicker] Client UI ready.")
