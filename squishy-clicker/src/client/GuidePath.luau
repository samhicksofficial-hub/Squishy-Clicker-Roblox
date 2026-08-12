--!strict
-- ============================================================
--  GUIDE PATH  —  the glowing trail that teaches the first steps.
--
--  A line of pulsing yellow tiles from the player's feet to the
--  next thing worth doing, the way the genre's games walk in new
--  players. Three lessons, in order, each decided from the same
--  SyncData snapshot everything else reads:
--
--   1. Never fired?            → your cannon.  "Fire your cannon!"
--   2. Can afford level 1?     → the board.    "Buy an upgrade!"
--   3. Nobody summoned?        → the market.   "Summon a squishy!"
--
--  Client-local entirely: the trail is YOURS (everyone gets their
--  own, to their own plot), it works in a baked world untouched,
--  and it retires for good once the cannon reaches a level that
--  says the player knows the game.
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GuidePath = {}

local player = Players.LocalPlayer

-- The player who reaches this cannon level has learned everything the
-- trail teaches; it never shows again this session.
local RETIRE_LEVEL = 4

-- Matches the plot geometry in Island.luau / PlotBoard.luau: the launch
-- station stands STATION_BACK inward of the plot centre, the upgrade
-- board holds the walk-in left corner.
local STATION_BACK = 13
local BOARD_SIDE = -14
local BOARD_IN = 12

-- The trail itself: how the tiles are laid down the line.
local TILE_SPACING = 7
local TILE_COUNT = 24

local plotCentre: Vector3? = nil
local marketAt: Vector3? = nil
local goal: Vector3? = nil
local retired = false
-- The latest sync snapshot, kept so a plot adopted AFTER the join sync
-- can pick its lesson immediately instead of waiting for the next one.
local lastState: any = nil

-- ---------- the parts ----------

local folder = Instance.new("Folder")
folder.Name = "GuidePath"
folder.Parent = workspace

local tiles: { BasePart } = {}
for _ = 1, TILE_COUNT do
	local tile = Instance.new("Part")
	tile.Size = Vector3.new(3, 0.25, 3)
	tile.Color = Color3.fromRGB(255, 230, 60)
	tile.Material = Enum.Material.Neon
	tile.Anchored = true
	tile.CanCollide = false
	tile.CanQuery = false
	tile.CanTouch = false
	tile.CastShadow = false
	tile.Transparency = 1
	tile.Parent = folder
	table.insert(tiles, tile)
end

-- The goal flag: a small floating label over wherever the trail leads.
local goalAnchor = Instance.new("Part")
goalAnchor.Size = Vector3.one
goalAnchor.Transparency = 1
goalAnchor.Anchored = true
goalAnchor.CanCollide = false
goalAnchor.CanQuery = false
goalAnchor.CanTouch = false
goalAnchor.Parent = folder

local goalGui = Instance.new("BillboardGui")
goalGui.Size = UDim2.new(0, 240, 0, 54)
goalGui.StudsOffset = Vector3.new(0, 9, 0)
goalGui.MaxDistance = 400
goalGui.LightInfluence = 0
goalGui.Enabled = false
goalGui.Adornee = goalAnchor
goalGui.Parent = player:WaitForChild("PlayerGui")

local goalLabel = Instance.new("TextLabel")
goalLabel.Size = UDim2.fromScale(1, 1)
goalLabel.BackgroundTransparency = 1
goalLabel.Font = Enum.Font.FredokaOne
goalLabel.Text = ""
goalLabel.TextColor3 = Color3.fromRGB(255, 230, 60)
goalLabel.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
goalLabel.TextStrokeTransparency = 0
goalLabel.TextScaled = true
goalLabel.Parent = goalGui

local function hideAll()
	for _, tile in tiles do
		tile.Transparency = 1
	end
	goalGui.Enabled = false
end

-- ---------- the targets ----------

-- The market stall is found once, by the prompt Island stamps on it —
-- the same name the interaction listens for.
task.spawn(function()
	local map = workspace:WaitForChild("Map", 30)
	if not map then
		return
	end
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "SquishyMarket" then
			local host = descendant.Parent
			if host and host:IsA("BasePart") then
				marketAt = host.Position
				return
			end
		end
	end
end)

function GuidePath.setPlot(centre: Vector3)
	plotCentre = Vector3.new(centre.X, 0, centre.Z)
	if lastState then
		GuidePath.update(lastState)
	end
end

-- Pick the current lesson from the server's numbers. Called on every
-- sync, exactly like the rest of the HUD.
function GuidePath.update(state: any)
	if retired or typeof(state) ~= "table" then
		return
	end
	lastState = state
	if (state.powerLevel or 0) >= RETIRE_LEVEL then
		-- School's out, permanently for this session.
		retired = true
		goal = nil
		hideAll()
		return
	end

	local centre = plotCentre
	if not centre then
		goal = nil
		hideAll()
		return
	end
	local outward = centre.Magnitude > 1 and centre.Unit or Vector3.xAxis
	local sideWorld = Vector3.new(-outward.Z, 0, outward.X)

	if (state.bestDistance or 0) <= 0 then
		goal = centre - outward * STATION_BACK
		goalLabel.Text = "🚀 Fire your cannon!"
	elseif (state.powerLevel or 0) == 0 and (state.coins or 0) >= (state.powerCost or math.huge) then
		goal = centre - outward * BOARD_IN + sideWorld * BOARD_SIDE
		goalLabel.Text = "⬆️ Buy an upgrade!"
	elseif #((state.active or {}) :: { string }) == 0 and marketAt then
		goal = marketAt
		goalLabel.Text = "🍡 Summon a squishy!"
	else
		goal = nil
	end

	if not goal then
		hideAll()
	end
end

-- ---------- laying the trail ----------
-- Straight from the feet to the goal, a tile every few studs, each rested
-- on whatever ground is actually under it (the plaza, the paths and the
-- plot pads all sit at different heights). The glow MARCHES toward the
-- goal, which is what makes a line read as "this way" instead of "here".
RunService.Heartbeat:Connect(function()
	local target = goal
	if not target or retired then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		hideAll()
		return
	end

	local from = Vector3.new(root.Position.X, 0, root.Position.Z)
	local to = Vector3.new(target.X, 0, target.Z)
	local span = to - from
	local distance = span.Magnitude
	if distance < 12 then
		-- Arrived: the flag says the rest.
		for _, tile in tiles do
			tile.Transparency = 1
		end
		goalAnchor.Position = Vector3.new(target.X, 4, target.Z)
		goalGui.Enabled = true
		return
	end
	local direction = span.Unit

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folder }
	if character then
		table.insert(exclude, character)
	end
	local flightStage = workspace:FindFirstChild("FlightStage")
	if flightStage then
		table.insert(exclude, flightStage)
	end
	params.FilterDescendantsInstances = exclude

	local clock = os.clock()
	for index, tile in tiles do
		local along = 5 + (index - 1) * TILE_SPACING
		if along >= distance - 4 then
			tile.Transparency = 1
			continue
		end
		local at = from + direction * along
		local hit = workspace:Raycast(Vector3.new(at.X, 40, at.Z), Vector3.new(0, -80, 0), params)
		local y = hit and hit.Position.Y or 1
		tile.CFrame = CFrame.new(Vector3.new(at.X, y + 0.15, at.Z))
			* CFrame.Angles(0, math.atan2(-direction.Z, direction.X), 0)
		-- The march: a brightness wave rolling from the player toward the
		-- goal, three tiles long.
		local wave = 0.5 + 0.5 * math.sin(clock * 5 - index * 0.9)
		tile.Transparency = 0.12 + 0.5 * (1 - wave)
	end

	goalAnchor.Position = Vector3.new(target.X, 4, target.Z)
	goalGui.Enabled = true
end)

return GuidePath
