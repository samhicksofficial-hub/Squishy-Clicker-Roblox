--!strict
-- ============================================================
--  PLOT BOARD  —  the upgrade board standing beside YOUR cannon.
--
--  A wooden stand on your own plot with the cannon's economy on
--  it: the power upgrade with BUY 1 and BUY MAX, and the combined
--  buffs your summoned team is feeding every shot.
--
--  Client-built and client-local ON PURPOSE. Everything it shows
--  is yours alone — your prices, your wallet, your team — and a
--  client-built stand also works in a BAKED world without asking
--  anyone to re-bake the map. Every other player's client builds
--  their own board at their own plot.
--
--  THE SERVER DECIDES, THE CLIENT ASKS: the buttons name an
--  intent (one level, or "max") and never a price or a count. The
--  max preview drawn here is arithmetic over the same Config curve
--  the server charges from; the server walks its own wallet check
--  level by level regardless.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
local UI = require(script.Parent:WaitForChild("UI"))

local PlotBoard = {}

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BuyPower = Remotes:WaitForChild("BuyPower") :: RemoteEvent

local C = UI.color

-- Where the stand sits, relative to the plot: the FRONT-LEFT corner as a
-- player walks in from the path (the name sign holds the front-right one),
-- angled 45° to greet them on the way in.
local BOARD_SIDE = -14 -- along the pad's side axis; negative = the walk-in left
local BOARD_IN = 12 -- inward of the plot centre, toward the entrance path

local folder: Folder? = nil
local surface: SurfaceGui? = nil
local levelLabel: TextLabel? = nil
local powerLabel: TextLabel? = nil
local buffsLabel: TextLabel? = nil
local buyOne: UI.Button? = nil
local buyMax: UI.Button? = nil
local lastState: any = nil

-- The same cost curve the server charges from (see powerUpgradeCost,
-- server-side). Used ONLY to preview what "max" would buy.
local function powerCostAt(level: number): number
	return math.floor(
		Config.PowerUpgradeBaseCost
				* Config.PowerUpgradeCostGrowth ^ level
				* Config.PowerUpgradeCostQuadGrowth ^ (level * level)
			+ 0.5
	)
end

local function repaint()
	local state = lastState
	if not state or not surface then
		return
	end

	local level = state.powerLevel or 0
	local coins = state.coins or 0
	local cost = state.powerCost or powerCostAt(level)
	local maxed = level >= Config.LaunchMaxPowerLevel;

	(levelLabel :: TextLabel).Text = ("🚀 LAUNCH POWER   ·   Lv %d"):format(level);
	(powerLabel :: TextLabel).Text = if maxed
		then ("%s  ·  MAXED!"):format(Format.abbreviate(state.launchPower or 0))
		else ("%s  ➜  %s"):format(
			Format.abbreviate(state.launchPower or 0),
			Format.abbreviate((state.launchPower or 0) * Config.LaunchPowerGrowth)
		)

	-- The max preview: walk the curve until the wallet says stop.
	local walkLevel, total, count = level, 0, 0
	while not maxed and walkLevel < Config.LaunchMaxPowerLevel and count < 200 do
		local step = powerCostAt(walkLevel)
		if total + step > coins then
			break
		end
		total += step
		count += 1
		walkLevel += 1
	end

	local one = buyOne :: UI.Button
	local many = buyMax :: UI.Button
	if maxed then
		one.button.Text = "MAXED"
		many.button.Text = "MAXED"
		UI.setButtonEnabled(one, false, C.green, C.greenDeep)
		UI.setButtonEnabled(many, false, C.orange, C.orangeDeep)
	else
		one.button.Text = ("BUY 1\n$%s"):format(Format.abbreviate(cost))
		UI.setButtonEnabled(one, coins >= cost, C.green, C.greenDeep)
		if count > 0 then
			many.button.Text = ("BUY %d\n$%s"):format(count, Format.abbreviate(total))
			UI.setButtonEnabled(many, true, C.orange, C.orangeDeep)
		else
			many.button.Text = "BUY MAX\n—"
			UI.setButtonEnabled(many, false, C.orange, C.orangeDeep)
		end
	end

	-- What the team is worth, as the finished numbers the server sent.
	(buffsLabel :: TextLabel).Text = ("🚀 +%d%% power    💵 ×%.2f cash    🧲 +%.1f magnet\n🎁 collection ×%.2f    🌍 world ×%s"):format(
		math.floor(((state.teamPower or 0)) * 100 + 0.5),
		state.teamCash or 1,
		state.teamMagnet or 0,
		state.collectionBonus or 1,
		Format.abbreviate(state.worldMultiplier or 1)
	)
end

-- Build (or rebuild) the stand at this plot. Called with the same centre
-- Flight.setPlot gets, whenever the plot attribute names this player.
function PlotBoard.setPlot(centre: Vector3)
	local flat = Vector3.new(centre.X, 0, centre.Z)
	if flat.Magnitude < 1 then
		return
	end
	local outward = flat.Unit
	local sideWorld = Vector3.new(-outward.Z, 0, outward.X)

	-- The gui is parented to PlayerGui, NOT the folder — destroying only
	-- the stand on a rebuild would strand the old gui there forever.
	if folder then
		folder:Destroy()
	end
	if surface then
		surface:Destroy()
	end
	local stand = Instance.new("Folder")
	stand.Name = "PlotBoard"
	stand.Parent = workspace
	folder = stand

	local at = flat - outward * BOARD_IN + sideWorld * BOARD_SIDE

	local function woodPart(size: Vector3, cframe: CFrame): Part
		local part = Instance.new("Part")
		part.Size = size
		part.CFrame = cframe
		part.Color = Color3.fromRGB(150, 104, 62)
		part.Material = Enum.Material.Wood
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Parent = stand
		return part
	end

	-- Faces 45° between the entrance path (inward) and the pad's centre
	-- line — square-on to a player walking in, whichever corner it holds.
	local facing = (-outward - sideWorld * math.sign(BOARD_SIDE)).Unit
	local face = CFrame.lookAt(at + Vector3.new(0, 6, 0), at + Vector3.new(0, 6, 0) + facing)
	woodPart(Vector3.new(0.7, 7, 0.7), face * CFrame.new(-4.6, -2.4, 0.6))
	woodPart(Vector3.new(0.7, 7, 0.7), face * CFrame.new(4.6, -2.4, 0.6))
	local board = woodPart(Vector3.new(11, 6.4, 0.5), face)
	board.Color = Color3.fromRGB(92, 62, 40)
	board.Material = Enum.Material.WoodPlanks

	-- The gui lives under PlayerGui with the board as Adornee — parented to
	-- the part itself, buttons stop receiving input (the same lesson the
	-- capsule badge learned about ViewportFrames).
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlotBoardGui"
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 40
	gui.Adornee = board
	gui.Parent = player:WaitForChild("PlayerGui")
	surface = gui

	local body = UI.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(64, 44, 30),
		Parent = gui,
	})
	UI.corner(14, body)
	UI.stroke(body, 4)

	UI.label({
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.new(0, 0, 0, 4),
		Text = "⬆️ UPGRADES",
		TextSize = 30,
		StrokeThickness = 3,
		Parent = body,
	})

	levelLabel = UI.label({
		Size = UDim2.new(1, -24, 0, 26),
		Position = UDim2.new(0, 12, 0, 52),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(252, 214, 132),
		Parent = body,
	})
	powerLabel = UI.label({
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.new(0, 12, 0, 80),
		Text = "",
		TextSize = 20,
		Parent = body,
	})

	buyOne = UI.button({
		parent = body,
		size = UDim2.new(0.5, -18, 0, 62),
		position = UDim2.new(0, 12, 0, 112),
		text = "BUY 1",
		textSize = 20,
		top = C.green,
		bottom = C.greenDeep,
		radius = 12,
	})
	buyMax = UI.button({
		parent = body,
		size = UDim2.new(0.5, -18, 0, 62),
		position = UDim2.new(1, -12, 0, 112),
		anchor = Vector2.new(1, 0),
		text = "BUY MAX",
		textSize = 20,
		top = C.orange,
		bottom = C.orangeDeep,
		radius = 12,
	});

	(buyOne :: UI.Button).button.Activated:Connect(function()
		BuyPower:FireServer()
	end);
	(buyMax :: UI.Button).button.Activated:Connect(function()
		BuyPower:FireServer("max")
	end)

	UI.label({
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.new(0, 12, 0, 182),
		Text = "— YOUR TEAM'S BUFFS —",
		TextSize = 17,
		TextColor3 = Color3.fromRGB(214, 236, 255),
		Parent = body,
	})
	buffsLabel = UI.label({
		Size = UDim2.new(1, -24, 0, 46),
		Position = UDim2.new(0, 12, 0, 206),
		Text = "",
		TextSize = 17,
		Parent = body,
	})

	repaint()
end

function PlotBoard.update(state: any)
	lastState = state
	repaint()
end

return PlotBoard
