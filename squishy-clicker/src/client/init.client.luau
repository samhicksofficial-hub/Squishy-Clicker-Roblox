--!strict
-- ============================================================
--  CLIENT  —  the HUD, and the wiring between it and the 3D
--  stage in Scene.luau.
--
--  All numbers come from the server via SyncData; this script
--  only draws them and sends requests. The steamer itself is a
--  real 3D model now, so the UI deliberately stays out of the
--  middle of the screen and leaves the view clear.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
-- Direct require: Squishies lives at Shared/Squishies. If this ever hangs
-- with an orange "Infinite yield possible" warning in Output, the file was
-- moved — put it back at src/shared/Squishies.luau or update this path.
local Squishies = require(Shared:WaitForChild("Squishies"))
local Scene = require(script:WaitForChild("Scene"))
local Models = require(script:WaitForChild("Models"))
local Launch = require(script:WaitForChild("Launch"))
local King = require(script:WaitForChild("King"))
local Cannon = require(script:WaitForChild("Cannon"))
-- Required up here as well as inside the plot wiring below, because refresh()
-- needs it to keep the flying squishy matched to the equipped one.
local ClientFlight = require(script:WaitForChild("Flight"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClickSteamer = Remotes:WaitForChild("ClickSteamer") :: RemoteEvent
local PrestigeSquishy = Remotes:WaitForChild("PrestigeSquishy") :: RemoteEvent
local SteamerOpened = Remotes:WaitForChild("SteamerOpened") :: RemoteEvent
local SyncData = Remotes:WaitForChild("SyncData") :: RemoteEvent
local UnboxSteamer = Remotes:WaitForChild("UnboxSteamer") :: RemoteEvent
local SetClicker = Remotes:WaitForChild("SetClicker") :: RemoteEvent
local SetActive = Remotes:WaitForChild("SetActive") :: RemoteEvent

-- ---------- palette ----------
-- Text is white with a dark outline everywhere, matching UI.luau. The HUD
-- used to be dark-brown-on-cream, which was fine over a pale panel and
-- unreadable the moment it sat over the island.
local COLOR = {
	panel = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(255, 255, 255),
	dim = Color3.fromRGB(244, 232, 214),
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
	unopened = 0,
	clickerId = nil :: string?,
	launchReadyIn = 0,
	bestDistance = 0,
	-- The cannon's own economy. Defaults matter here: refresh() runs once
	-- before the first sync arrives.
	tnt = 0,
	coins = 0,
	gems = 0,
	powerLevel = 0,
	powerCost = Config.PowerUpgradeBaseCost,
	launchPower = Config.LaunchBasePower,
	magnet = Config.LaunchPickupMagnet,
	rebirths = 0,
	rebirthAt = Config.RebirthBaseRequirement,
	rebirthReady = false,
	active = {} :: { string },
	steamerCost = Config.SteamerCoinCost,
	luckySteamerCost = Config.LuckySteamerGemCost,
	boostReadyIn = 0,
	boostLeft = 0,
}

-- Rarity rank (Common = 1 ... Mythical = 6). The reveal scales off this.
local rarityTier: { [string]: number } = {}
for index, rarity in Squishies.rarities do
	rarityTier[rarity.name] = index
end

-- ---------- tiny UI helpers ----------
local function make(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	-- Every piece of text in the HUD gets the dark outline by default. Doing it
	-- here rather than at each call site is the only way it stays consistent —
	-- there are a few dozen labels in this file and one missed stroke is a
	-- label that vanishes against bright grass.
	if (className == "TextLabel" or className == "TextButton") and props.TextStrokeTransparency == nil then
		(inst :: any).TextStrokeColor3 = Color3.fromRGB(52, 38, 30);
		(inst :: any).TextStrokeTransparency = 0.15
	end
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
-- No background frame: the 3D stage IS the background now.
local screen = make("ScreenGui", {
	Name = "SquishyClickerUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- Everything is built at fixed pixel sizes, which is the only sane way to lay
-- out chunky panels — so the HUD has to be SCALED to fit the window rather
-- than each panel guessing at it. This frame is the real root; every panel in
-- the game is a child of it.
local gui = make("Frame", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Parent = screen,
})

-- The size the HUD is laid out for. Anything smaller scales down; anything
-- bigger scales up a little, but not without limit, or a 4K screen gets a HUD
-- with letters four inches tall.
local DESIGN_WIDTH, DESIGN_HEIGHT = 1280, 720
local hudScale = 1

-- ONE UIScale PER TOP-LEVEL PANEL, not one on the root.
--
-- A single UIScale on the root looks like the obvious answer and is wrong: it
-- scales POSITIONS outward from the root's top-left corner, so anything
-- anchored to the right or bottom edge is pushed off the screen when the scale
-- is above 1, and dragged into the middle when it is below. That is exactly
-- what put the wallet, the collection panel and the whole bottom-left bar
-- outside the window on a wide monitor.
--
-- Per-panel scaling has none of that. Each panel stays positioned against the
-- screen edge it belongs to, and the scale only shrinks it in place around its
-- own anchor point — right-anchored panels shrink rightwards, centred ones
-- shrink towards the centre, and nothing moves.
local panelScales: { UIScale } = {}

local function scalePanel(child: Instance)
	if not child:IsA("GuiObject") then
		return
	end

	-- Skip anything that already sizes itself off the screen. A UIScale
	-- multiplies the size it computes, so a panel asking for "full height
	-- minus 210" would come out 10% taller than the screen and hang off the
	-- bottom. Those panels are responsive already and need no help; this is
	-- only for the fixed-pixel ones. (The full-screen click catcher is the
	-- other thing this protects — scaling that would leave a dead margin.)
	local size = child.Size
	if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
		return
	end

	local existing = child:FindFirstChildOfClass("UIScale")
	if existing then
		existing.Scale = hudScale
		return
	end
	local scale = Instance.new("UIScale")
	scale.Scale = hudScale
	scale.Parent = child
	table.insert(panelScales, scale)
end

-- Panels are built by five different modules across several frames, and some
-- of them (reveal banners, the hatch popup) appear long after startup — so
-- this watches for new ones rather than sweeping the tree once.
gui.ChildAdded:Connect(scalePanel)

local function fitHud()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end

	-- Height leads, because the HUD's long runs are vertical: the nav rail,
	-- the collection list, the stacked wallet. Width only gets a vote when the
	-- window is genuinely narrow — that is what the multiplier is for, so a
	-- merely wide-ish window isn't treated as if it were cramped.
	local byHeight = viewport.Y / DESIGN_HEIGHT
	local byWidth = (viewport.X / DESIGN_WIDTH) * 1.5
	hudScale = math.clamp(math.min(byHeight, byWidth), 0.5, 1.1)

	for _, scale in panelScales do
		scale.Scale = hudScale
	end
end

fitHud()
do
	local function watch(camera: Camera?)
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHud)
			fitHud()
		end
	end
	watch(workspace.CurrentCamera)
	-- The camera is swapped out on respawn, and the new one needs the same
	-- connection or the HUD stops resizing halfway through a session.
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watch(workspace.CurrentCamera)
	end)
end

-- ---------- the click target ----------
-- A full-screen invisible button. Catching taps in the UI layer rather than with
-- a ClickDetector on the model means clicking works identically on PC, mobile
-- and console, and never misses because the steamer happened to be mid-bounce.
-- The collection panel sits above this and is Active, so it swallows its own
-- taps instead of leaking them through as clicks.
local clickArea = make("TextButton", {
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromScale(0, 0),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	-- OFF unless the squisher close-up is open. A full-screen button eats
	-- every click and drag underneath it, which is harmless in a clicker with
	-- no character and immediately wrong once the player can walk: it would
	-- swallow the camera drag and the touch-look on mobile.
	Visible = false,
	ZIndex = 1,
	Parent = gui,
})

-- The close-up views are the only place tapping the screen means "squish".
Scene.onViewChanged(function(atValley)
	clickArea.Visible = not atValley
end)

clickArea.MouseButton1Down:Connect(function()
	-- Only counts while the camera is actually at the squisher. The launcher
	-- is the main game now and its view fills the screen, so without this
	-- every tap aimed at the valley would also be squishing a squishy that is
	-- 600 studs away and off camera.
	if Scene.atValley() then
		return
	end
	Scene.click()
	ClickSteamer:FireServer()
end)

-- ---------- drag to spin the squishy ----------
-- Click-and-drag on PC, touch-and-drag on mobile. A press on its own does
-- nothing to the spin: only movement past a few pixels counts as a drag, so
-- hammering the clicker never kills a spin that's already going. Movement and
-- release come from UserInputService rather than the button, so a drag that
-- wanders off the button — or lets go outside it — still behaves.
local DRAG_THRESHOLD = 5 -- pixels of travel before a press becomes a drag

local pointerDown = false
local pointerTouch: InputObject? = nil
local pointerLastX = 0
local pointerTravel = 0
local pointerDragging = false

clickArea.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		pointerDown = true
		pointerTouch = input
		pointerLastX = input.Position.X
		pointerTravel = 0
		pointerDragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not pointerDown then
		return
	end
	-- A mouse reports movement on its own input object; a touch reports it on
	-- the same one that began the press.
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= pointerTouch then
		return
	end

	local delta = input.Position.X - pointerLastX
	pointerLastX = input.Position.X
	pointerTravel += math.abs(delta)
	if not pointerDragging and pointerTravel < DRAG_THRESHOLD then
		return
	end
	pointerDragging = true
	Scene.dragClicker(delta)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input ~= pointerTouch then
		return
	end
	pointerDown = false
	pointerTouch = nil
	if pointerDragging then
		pointerDragging = false
		Scene.releaseClicker()
	end
end)

-- ---------- header ----------
local header = make("Frame", {
	Size = UDim2.new(0, 340, 0, 64),
	Position = UDim2.new(0, 24, 0, 20),
	BackgroundColor3 = COLOR.panel,
	BackgroundTransparency = 0.12,
	ZIndex = 2,
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

-- ---------- click progress (bottom left, under the steamer) ----------
local progressShell = make("Frame", {
	Size = UDim2.new(0, 300, 0, 28),
	Position = UDim2.new(0, 124, 1, -92),
	BackgroundColor3 = COLOR.progressBg,
	ZIndex = 2,
	Parent = gui,
})
corner(14, progressShell)

local progressFill = make("Frame", {
	Size = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = COLOR.gold,
	BorderSizePixel = 0,
	Parent = progressShell,
})
corner(14, progressFill)

local progressLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "0 / 10",
	TextColor3 = COLOR.text,
	TextSize = 15,
	ZIndex = 2,
	Parent = progressShell,
})

local squishHint = make("TextLabel", {
	Size = UDim2.new(0, 300, 0, 20),
	Position = UDim2.new(0, 124, 1, -116),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "tap anywhere to squish!",
	TextColor3 = COLOR.text,
	TextTransparency = 0.25,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 2,
	Parent = gui,
})

-- ---------- the Unbox tray ----------
-- Filling the bar BANKS a steamer instead of opening it; this button spends
-- one. Sits right of the progress bar so the loop reads left to right:
-- fill the bar, then unbox.
local unboxButton = make("TextButton", {
	Size = UDim2.new(0, 160, 0, 44),
	Position = UDim2.new(0, 436, 1, -100),
	BackgroundColor3 = COLOR.locked,
	AutoButtonColor = false,
	Font = Enum.Font.FredokaOne,
	Text = "🥡 Unbox (0)",
	TextColor3 = COLOR.text,
	TextSize = 18,
	ZIndex = 2,
	Parent = gui,
})
corner(14, unboxButton)

-- Guards the swing back to the squisher: another unbox press bumps the token,
-- so a queued "return to main view" from an earlier reveal quietly gives up.
local viewToken = 0

unboxButton.Activated:Connect(function()
	if state.unopened <= 0 then
		return
	end
	viewToken += 1
	Scene.setView("unbox")
	-- Let the camera land on the steamer before the lid pops.
	task.delay(0.55, function()
		UnboxSteamer:FireServer()
	end)
end)

-- Spells out the treadmill, so a rising requirement reads as a mechanic rather
-- than a bug.
local costLabel = make("TextLabel", {
	Size = UDim2.new(0, 320, 0, 20),
	Position = UDim2.new(0, 124, 1, -58),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = COLOR.text,
	TextTransparency = 0.35,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 2,
	Parent = gui,
})

-- ---------- inventory / collection (right side) ----------
-- Sized off the bottom of the wallet rather than centred, so the two never
-- share a pixel: the wallet is always up, and this is only up at the squisher.
local panel = make("Frame", {
	Size = UDim2.new(0, 320, 1, -210),
	Position = UDim2.new(1, -20, 0, 170),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = COLOR.panel,
	BackgroundTransparency = 0.08,
	Active = true, -- consume taps so browsing the collection doesn't click the steamer
	ZIndex = 3,
	Parent = gui,
})
corner(20, panel)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	Text = "My Squishies",
	TextColor3 = COLOR.text,
	TextSize = 24,
	Parent = panel,
})

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 16),
	Position = UDim2.new(0, 0, 0, 30),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "tap a face to make it your squisher",
	TextColor3 = COLOR.dim,
	TextSize = 12,
	Parent = panel,
})

local invList = make("ScrollingFrame", {
	Size = UDim2.new(1, -16, 1, -58),
	Position = UDim2.new(0, 8, 0, 50),
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
	icon: TextButton,
	equipStroke: UIStroke,
	summon: TextButton,
	-- Whether this squishy is currently summoned, so one button can both
	-- summon and dismiss. Mirrored from the server's list on every sync.
	active: boolean,
	viewport: ViewportFrame?,
}
local rows: { [string]: Row } = {}

-- The little 3D preview inside a collection icon: the real model, same as the
-- one you'd get on the cushion. Built lazily the first time a squishy is
-- discovered — a ViewportFrame is its own render pass, so standing up all 31
-- at launch would cost far more than it's worth while most are question marks.
local function buildIconPreview(row: Row, squishy: { shape: string?, color: Color3, sparkle: boolean, scale: number? })
	if row.viewport then
		return
	end

	local viewport = make("ViewportFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 165, 160),
		LightColor = Color3.fromRGB(255, 250, 244),
		LightDirection = Vector3.new(-0.5, -1, -0.6),
		ZIndex = 2,
		Parent = row.icon,
	})

	local stage = make("Folder", { Name = "Model", Parent = viewport })
	local model = Models.buildSquishy(stage, squishy.shape, squishy.color, squishy.sparkle, squishy.scale)
	-- Scaled here too, so a Mini reads small and a Giant reads big in the list
	-- rather than every squishy looking the same size.
	Models.apply(model.rig, CFrame.identity, Vector3.one * model.sizeScale)

	-- Narrow lens from further back: less perspective distortion than the
	-- default, so the shape reads cleanly at 56 pixels. Far enough out that an
	-- oversized squishy still fits.
	local camera = Instance.new("Camera")
	camera.FieldOfView = 28
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.9, 8), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	row.viewport = viewport
end

for index, squishy in Squishies.list do
	local rarity = Squishies.rarityByName[squishy.rarity]
	local tier = rarityTier[squishy.rarity] or 1

	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Color3.fromRGB(252, 248, 244),
		-- Sort the whole tab Common → Mythical, keeping catalog order inside
		-- each rarity. Without the tier term the shop squishies (appended to
		-- the catalog) land AFTER the Mythical and the tab looks shuffled.
		LayoutOrder = tier * 1000 + index,
		Parent = invList,
	})
	corner(14, row)

	-- The squishy's preview — also the button that equips it as the click toy.
	-- ClipsDescendants keeps the 3D preview inside the round swatch.
	local icon = make("TextButton", {
		Size = UDim2.new(0, 56, 0, 56),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = squishy.color,
		AutoButtonColor = false,
		ClipsDescendants = true,
		Font = Enum.Font.FredokaOne,
		Text = "?",
		TextColor3 = COLOR.text,
		TextSize = 18,
		Parent = row,
	})
	make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = icon })

	-- Gold ring marking the equipped squisher.
	local equipStroke = make("UIStroke", {
		Color = COLOR.gold,
		Thickness = 3,
		Transparency = 1,
		Parent = icon,
	})

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

	-- Summon: the squishies ARE the pets. Up to Config.MaxActiveSquishies walk
	-- with you and buff the cannon, and this is where you choose which.
	local summon = make("TextButton", {
		Size = UDim2.new(0, 84, 0, 18),
		Position = UDim2.new(1, -92, 1, -10),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = COLOR.mint,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "Summon",
		TextColor3 = COLOR.text,
		TextSize = 11,
		Parent = row,
	})
	corner(8, summon)

	local id = squishy.id
	prestige.Activated:Connect(function()
		PrestigeSquishy:FireServer(id)
	end)

	icon.Activated:Connect(function()
		-- Server validates ownership; tapping an undiscovered one does nothing.
		SetClicker:FireServer(id)
	end)

	summon.Activated:Connect(function()
		-- The row remembers whether this one is out, so one button both
		-- summons and dismisses. The server re-checks ownership and the slot
		-- limit either way; this is only the friendly reading of the rule.
		local entry = rows[id]
		SetActive:FireServer(id, not (entry and entry.active))
	end)

	rows[id] = {
		countLabel = countLabel,
		starLabel = starLabel,
		prestige = prestige,
		icon = icon,
		equipStroke = equipStroke,
		summon = summon,
		active = false,
	}
end

-- ---------- reveal: the UI half of the show ----------
-- Scene.luau handles the steamer, the dumpling and the particles; this adds
-- the banner naming the pull and a screen flash for the best rarities.
local function playReveal(squishyId: string)
	local squishy = Squishies.byId[squishyId]
	if not squishy then
		return
	end
	local rarity = Squishies.rarityByName[squishy.rarity]
	local tier = rarityTier[squishy.rarity] or 1
	local rarityColor = rarity and rarity.color or COLOR.gold

	Scene.open(squishy.shape, squishy.color, squishy.sparkle, rarityColor, tier, squishy.scale)

	local banner = make("TextLabel", {
		Size = UDim2.new(0, 320, 0, 56),
		Position = UDim2.new(0, 24, 0, 100),
		BackgroundColor3 = rarityColor,
		Font = Enum.Font.FredokaOne,
		Text = ("%s!"):format(squishy.name),
		TextColor3 = COLOR.white,
		TextSize = 23,
		Rotation = -3,
		ZIndex = 15,
		Parent = gui,
	})
	corner(16, banner)

	banner.Position = banner.Position - UDim2.new(0, 40, 0, 0)
	banner.TextTransparency = 1
	TweenService:Create(
		banner,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 24, 0, 100), TextTransparency = 0 }
	):Play()

	-- Legendary and Mythical wash the screen out for a moment.
	if tier >= 5 then
		local flash = make("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = COLOR.white,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 20,
			Parent = gui,
		})
		TweenService:Create(
			flash,
			TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
		task.delay(0.85, function()
			flash:Destroy()
		end)
	end

	task.delay(1.7, function()
		TweenService:Create(
			banner,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, BackgroundTransparency = 1 }
		):Play()
		task.delay(0.3, function()
			banner:Destroy()
		end)
	end)

	-- Once the show is over, swing back to the squisher — unless the player
	-- queued another unbox in the meantime.
	viewToken += 1
	local token = viewToken
	task.delay(2.3, function()
		if token == viewToken then
			Scene.setView("main")
		end
	end)
end

SteamerOpened.OnClientEvent:Connect(playReveal)

-- A floating "+N clicks" whenever the requirement climbs, so the cost of an
-- open is visible at the moment you pay it.
local function showCostRise(amount: number)
	local floater = make("TextLabel", {
		Size = UDim2.new(0, 200, 0, 26),
		Position = UDim2.new(0, 124, 1, -92),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = ("+%d click%s to open"):format(amount, amount == 1 and "" or "s"),
		TextColor3 = Color3.fromRGB(226, 96, 96),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 16,
		Parent = gui,
	})
	TweenService:Create(
		floater,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 124, 1, -140), TextTransparency = 1 }
	):Play()
	task.delay(1.2, function()
		floater:Destroy()
	end)
end

-- A floating note when a full bar banks a steamer — the moment needs SOME
-- fanfare now that it no longer opens anything.
local function showBanked()
	local floater = make("TextLabel", {
		Size = UDim2.new(0, 220, 0, 26),
		Position = UDim2.new(0, 436, 1, -110),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "🥡 steamer banked!",
		TextColor3 = COLOR.mint,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 16,
		Parent = gui,
	})
	TweenService:Create(
		floater,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 436, 1, -158), TextTransparency = 1 }
	):Play()
	task.delay(1.2, function()
		floater:Destroy()
	end)
end

-- ---------- redraw from server state ----------
local appliedClickerId: string? = nil

local function refresh()
	headerLabel.Text = ("🥟 Opens: %d    ⭐ Stars: %d"):format(state.totalOpens, state.totalStars)

	-- The cannon's cooldown, distance record, balances and prices are all the
	-- server's to know, not ours to guess.
	Launch.setReadyIn(state.launchReadyIn or 0)
	Launch.setBest(state.bestDistance or 0)
	Cannon.update(state)

	unboxButton.Text = ("🥡 Unbox (%d)"):format(state.unopened)
	unboxButton.BackgroundColor3 = state.unopened > 0 and COLOR.mint or COLOR.locked
	unboxButton.AutoButtonColor = state.unopened > 0

	-- Equip the chosen squisher on the stage (once per change, not per sync).
	if state.clickerId ~= appliedClickerId then
		appliedClickerId = state.clickerId
		local equipped = appliedClickerId and Squishies.byId[appliedClickerId]
		if equipped then
			Scene.setClicker(equipped.shape, equipped.color, equipped.sparkle, equipped.id, equipped.scale)
			-- The same squishy is what comes out of the cannon, so the thing
			-- flying over the range is the one sat on the cushion.
			ClientFlight.setSquishy(equipped.shape, equipped.color, equipped.sparkle == true, equipped.scale)
		end
	end

	progressLabel.Text = ("%d / %d"):format(state.clickProgress, state.clicksToOpen)
	local frac = math.clamp(state.clickProgress / math.max(state.clicksToOpen, 1), 0, 1)
	Scene.setProgress(frac)
	TweenService:Create(
		progressFill,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(frac, 0, 1, 0) }
	):Play()

	local discount = math.min(state.totalStars * Config.StarDiscountPerStar, Config.MaxStarDiscount)
	costLabel.Text = ("every open costs +%d · your %d★ cut the price %d%%"):format(
		Config.ClicksAddedPerOpen,
		state.totalStars,
		math.floor(discount * 100 + 0.5)
	)

	-- Which squishies are out, as a set, so the loop below is a lookup rather
	-- than a scan per row.
	local activeList: { string } = state.active
	local summoned: { [string]: boolean } = {}
	for _, id in activeList do
		summoned[id] = true
	end
	local summonedCount = #activeList

	for id, row in rows do
		local held = state.counts[id] or 0
		local star = state.stars[id] or 0

		row.countLabel.Text = "x" .. held
		row.starLabel.Text = starString(star)
		row.equipStroke.Transparency = (id == state.clickerId) and 0 or 1

		-- Summon button: out, available, or full. "Full" stays readable rather
		-- than hiding, so the three-slot limit is visible before it's hit.
		local discoveredHere = held > 0 or star > 0
		local isOut = summoned[id] == true
		row.active = isOut
		local slotsLeft = summonedCount < Config.MaxActiveSquishies
		row.summon.Visible = discoveredHere
		row.summon.Text = isOut and "Dismiss" or (slotsLeft and "Summon" or "Slots full")
		row.summon.BackgroundColor3 = isOut and COLOR.gold or (slotsLeft and COLOR.mint or COLOR.locked)

		-- Undiscovered squishies stay dark question marks — the collection
		-- tease. Discovering one builds its 3D preview, once.
		local squishy = Squishies.byId[id]
		local discovered = held > 0 or star > 0
		if squishy then
			row.icon.BackgroundColor3 = discovered and squishy.color or Color3.fromRGB(90, 82, 76)
			row.icon.Text = discovered and "" or "?"
			if discovered then
				buildIconPreview(row, squishy)
			end
			local preview = row.viewport
			if preview then
				preview.Visible = discovered
			end
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

local hasSynced = false

SyncData.OnClientEvent:Connect(function(payload)
	local previousRequirement = state.clicksToOpen
	local previousUnopened = state.unopened
	state = payload
	refresh()

	-- No floaters on the join sync: a returning player's saved numbers
	-- differing from the defaults isn't news.
	if hasSynced then
		local rise = state.clicksToOpen - previousRequirement
		if rise > 0 then
			showCostRise(rise)
		end
		if state.unopened > previousUnopened then
			showBanked()
		end
	end
	hasSynced = true
end)

-- Spawned because mounting waits on remotes; the HUD must not wait with it.
--
-- Wrapped, because a spawned thread that throws dies SILENTLY as far as the
-- rest of the game is concerned: the buttons built before the error are on
-- screen and look fine, the ones after it never appear, and nothing says why.
-- That is exactly how a one-line typo once left the game stuck on the launcher
-- with a LAUNCH button that did nothing. Now it names itself in the Output.
local function mount(what: string, build: () -> ())
	task.spawn(function()
		-- The inner wrapper declares a return type purely so pcall is typed as
		-- giving back an error value as well as a success flag; a `() -> ()`
		-- passed straight to pcall types as returning the flag alone.
		local ok, err = pcall(function(): string?
			build()
			return nil
		end)
		if not ok then
			warn(("[SquishyClicker] %s UI failed to build — %s"):format(what, tostring(err)))
		end
	end)
end

mount("Launcher", function()
	Launch.mount(gui, Scene)
end)
mount("King of the Steamer", function()
	King.mount(gui, Scene)
end)
mount("Cannon HUD", function()
	Cannon.mount(gui, Scene)
	-- Mounting replaced Cannon.update, so the numbers already in state need
	-- pushing through it once — the next sync could be a click away.
	Cannon.update(state)
end)

-- ---------- the cannon on your plot ----------
-- The prompt lives on a server-built part, but these events fire LOCALLY, so
-- showing the launcher costs no round trip. The owner check has to happen here
-- for the same reason — and it is only a UI gate: the actual shot is still
-- validated by the server, which knows whose plot is whose without being told.
do
	local ProximityPromptService = game:GetService("ProximityPromptService")

	local function ownsPrompt(prompt: ProximityPrompt): boolean
		local plot = prompt:FindFirstAncestorOfClass("Folder")
		return plot ~= nil and plot:GetAttribute("OwnerUserId") == player.UserId
	end

	-- Find the plot the server gave us and point the flight out from it. Done
	-- by watching for the attribute rather than by asking, because the server
	-- stamps it during the join handshake and the answer may already be
	-- sitting there by the time this runs.
	local Flight = require(script:WaitForChild("Flight"))

	local function adoptPlot(plot: Instance)
		if plot:GetAttribute("OwnerUserId") ~= player.UserId then
			return
		end
		-- The pad is the biggest part on the plot, and its centre is the
		-- bearing the cannon points along.
		local pad = plot:FindFirstChildWhichIsA("BasePart")
		if pad then
			Flight.setPlot(pad.Position)
		end
	end

	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		local plots = map and map:WaitForChild("Plots", 30)
		if not plots then
			warn("[SquishyClicker] No plots on the island — the launcher has nowhere to fire from.")
			return
		end
		for _, plot in plots:GetChildren() do
			adoptPlot(plot)
			plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
				adoptPlot(plot)
			end)
		end
	end)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		if ownsPrompt(prompt) then
			Launch.setNearCannon(true)
		end
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if ownsPrompt(prompt) then
			Launch.setNearCannon(false)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer == player and ownsPrompt(prompt) then
			Launch.open()
		end
	end)
end

refresh()

-- ---------- one HUD per view ----------
-- The launcher and the clicker are two different games sharing a screen, and
-- both want the same corners. So each view shows only its own half: the
-- valley gets the launch controls and the lobby feed, the toy shop gets the
-- steamer bar, the Unbox tray and the collection. The wallet and the nav rail
-- belong to neither and stay up throughout.
local steamerHud = { header, progressShell, costLabel, unboxButton, panel, squishHint }

Scene.onViewChanged(function(atValley)
	for _, element in steamerHud do
		element.Visible = not atValley
	end
end)

-- Tell the server we are listening. Its join sync and — more importantly — its
-- join LaunchField both fire the moment the player is added, which routinely
-- beats this script to connecting its handlers. A lost sync fixes itself on
-- the next click; a lost field left the track with no pickups on it at all
-- until after the player's first shot.
task.spawn(function()
	local ready = Remotes:WaitForChild("ClientReady") :: RemoteEvent
	ready:FireServer()
end)

-- Studio-only debug menu. Spawned because it waits on a remote that will never
-- arrive in a published game, and the HUD must not wait with it.
task.spawn(function()
	local Debug = require(script:WaitForChild("Debug"))
	Debug.mount(gui, Scene)
end)

print("[SquishyClicker] Client UI ready.")
