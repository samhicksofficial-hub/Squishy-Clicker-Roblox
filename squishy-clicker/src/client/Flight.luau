--!strict
-- ============================================================
--  FLIGHT  —  the shot, drawn in the real world.
--
--  The squishy leaves YOUR cannon, on YOUR plot, and sails out
--  over the rainbow bands painted across the plain. Which band it
--  clears is how far it went: the bands and this animation both
--  read Config.rangeRadius, so a squishy passing "10K Studs" has
--  genuinely flown ten thousand.
--
--  That mapping is LOGARITHMIC and has to be. Distances run from
--  a couple of hundred studs to seven figures; a linear plain long
--  enough for the top end would be a million studs across, and one
--  scaled to fit would put every early shot in the first inch of
--  it. On a log plain every power of ten is a visible step out,
--  which is the feedback the whole upgrade loop hangs on.
--
--  Nothing here decides anything. The server simulates the flight
--  and sends its shape — every hop, its peak, its duration — and
--  this draws that shape onto the ground.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Squishies = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Squishies"))
local Models = require(script.Parent:WaitForChild("Models"))

local Flight = {}

local player = Players.LocalPlayer

-- How tall an arc is drawn, as a fraction of the ground it covers. Purely a
-- look: the real ratio is wild at both ends of the power curve.
local ARC_HEIGHT_RATIO = 0.22
-- Chase camera, in studs behind / above / to the side of the squishy.
local CHASE_BACK = 26
local CHASE_UP = 14
local CHASE_SIDE = 16

type Arc = { fromX: number, toX: number, peak: number, seconds: number, rolling: boolean }

local stage = Instance.new("Folder")
stage.Name = "FlightStage"
stage.Parent = workspace

-- Where the shot starts and which way it goes. Set from the player's own plot
-- the moment one is claimed for them; until then the flight has nowhere to be
-- and simply does not play.
local origin: Vector3? = nil
local outward = Vector3.new(1, 0, 0)

local model: Models.SquishyModel? = nil
local modelSpec = { shape = nil :: string?, color = Color3.fromRGB(226, 120, 120), sparkle = false, scale = 1 }

local shot = {
	active = false,
	progress = 1,
	seconds = 1,
	simSeconds = 1,
	distance = 0,
	arcs = {} :: { Arc },
	arcStarts = {} :: { number },
	heightScale = 1,
	flown = 0,
	height = 0,
	speed = 0,
	bounced = 0,
	holdUntil = 0,
}

-- ---------- pickups ----------
local PICKUP_LOOK = {
	tnt = Color3.fromRGB(232, 118, 58),
	coin = Color3.fromRGB(252, 208, 96),
	gem = Color3.fromRGB(126, 232, 224),
}
type PickupEntry = { distance: number, height: number, kind: string, value: number, vip: boolean }

local pickupParts: { BasePart } = {}
local pickupField: { PickupEntry } = {}
local pickupTaken: { [number]: boolean } = {}
local pickupCollecting: { [number]: number } = {}

local POOL = Config.LaunchPickupCount * Config.BoostDensityMultiplier
	+ Config.VipZoneCount * Config.VipZoneDensityMultiplier
for _ = 1, POOL do
	local prize = Instance.new("Part")
	prize.Size = Vector3.one * 5
	prize.Material = Enum.Material.Neon
	prize.Anchored = true
	prize.CanCollide = false
	prize.CanQuery = false
	prize.CanTouch = false
	prize.Transparency = 1
	prize.Parent = stage
	table.insert(pickupParts, prize)
end

-- ---------- other players' shots ----------
-- The lobby spectacle: everyone's launches arc over the same plain, each one
-- rising from its owner's own plot bearing with a name over it. A pool,
-- round-robined, so a busy server recycles the oldest ghost rather than
-- queueing shots nobody is waiting for.
type Ghost = {
	part: BasePart,
	label: TextLabel,
	arcs: { Arc },
	arcStarts: { number },
	simSeconds: number,
	seconds: number,
	progress: number,
	active: boolean,
	distance: number,
	origin: Vector3,
	outward: Vector3,
	heightScale: number,
}

local ghosts: { Ghost } = {}
local nextGhost = 1
for _ = 1, Config.LobbyMaxGhosts do
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * 6
	ball.Material = Enum.Material.Neon
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Transparency = 1
	ball.Parent = stage

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 200, 0, 40)
	gui.StudsOffset = Vector3.new(0, 7, 0)
	gui.MaxDistance = 2500
	gui.Parent = ball

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = gui

	table.insert(ghosts, {
		part = ball,
		label = label,
		arcs = {},
		arcStarts = {},
		simSeconds = 1,
		seconds = 1,
		progress = 1,
		active = false,
		distance = 0,
		origin = Vector3.zero,
		outward = Vector3.xAxis,
		heightScale = 1,
	})
end

-- ---------- the curve ----------
-- The same two-phase-per-hop curve the server scored against, reproduced to
-- animate. Only the server's copy decides what was collected, so the two
-- drifting apart is a cosmetic bug and never an exploit. Generic over the arc
-- list because ghosts replay other players' flights through it too.
local function sampleArcs(arcs: { Arc }, starts: { number }, endDistance: number, simTime: number): (number, number, number)
	for index, arc in arcs do
		local started = starts[index] or 0
		if simTime <= started + arc.seconds or index == #arcs then
			local span = arc.toX - arc.fromX
			if arc.seconds <= 0 or span <= 0 then
				return arc.toX, 0, 0
			end
			local along = math.clamp((simTime - started) / arc.seconds, 0, 1)
			if arc.rolling then
				local eased = along * (2 - along)
				return arc.fromX + span * eased, 0, (span / arc.seconds) * (1 - along) * 2
			end
			return arc.fromX + span * along, arc.peak * 4 * along * (1 - along), span / arc.seconds
		end
	end
	return endDistance, 0, 0
end

local function sample(simTime: number): (number, number, number)
	return sampleArcs(shot.arcs, shot.arcStarts, shot.distance, simTime)
end

-- Where a game distance sits in the world, on the ray out from the plot.
local function worldAt(studs: number, height: number): Vector3
	local from = origin or Vector3.zero
	return from + outward * Config.rangeRadius(studs) + Vector3.new(0, height * shot.heightScale, 0)
end

-- ---------- public ----------

-- Laying the field out needs a plot to lay it out FROM. Until one is adopted
-- everything stays hidden: the first field arrives from the server during the
-- join handshake, which can beat the plot attribute replicating, and laying
-- it out from a nil origin scattered glowing crates over the plaza — the
-- "something in the sky" hanging above spawn. Defined above setPlot because
-- both setPlot and setField call it, whichever order the two race in.
local function layoutField()
	if not origin then
		return
	end

	local tallest = 1
	for _, entry in pickupField do
		tallest = math.max(tallest, entry.height)
	end

	for index, prize in pickupParts do
		local entry = pickupField[index]
		if entry and not pickupTaken[index] then
			prize.Color = PICKUP_LOOK[entry.kind] or PICKUP_LOOK.tnt
			prize.Size = Vector3.one * (entry.vip and 8 or 5)
			prize.Transparency = 0.1
			-- Laid out against the field's own tallest, so the strung-out
			-- pickups sit at a readable height whatever the power level.
			local lift = entry.height / tallest * 90
			prize.Position = worldAt(entry.distance, 0) + Vector3.new(0, lift, 0)
		else
			prize.Transparency = 1
		end
	end
end

-- The plot to fire from. The direction is straight out from the island's
-- centre, which is the way every plot's cannon already points.
function Flight.setPlot(centre: Vector3)
	local flat = Vector3.new(centre.X, 0, centre.Z)
	if flat.Magnitude < 1 then
		return
	end
	outward = flat.Unit
	-- Started at the island's middle rather than at the plot, so a shot's
	-- distance is measured from the same place the rainbow bands are: the
	-- bands are circles about the centre, and firing from the rim would put
	-- the squishy over the wrong one.
	origin = Vector3.new(0, centre.Y + 8, 0)

	-- A field may have arrived before the plot did — lay it out now.
	layoutField()
end

function Flight.setSquishy(shape: string?, color: Color3, sparkle: boolean, sizeScale: number?)
	modelSpec = { shape = shape, color = color, sparkle = sparkle, scale = sizeScale or 1 }
	if model then
		model.rig.folder:Destroy()
		model = nil
	end
end

function Flight.setField(field: { PickupEntry })
	pickupField = field
	pickupTaken = {}
	pickupCollecting = {}
	for index, entry in pickupParts do
		if not field[index] then
			pickupTaken[index] = true
			entry.Transparency = 1
		end
	end
	layoutField()
end

function Flight.play(plan: {
	distance: number,
	arcs: { Arc },
	seconds: number,
	peakHeight: number,
	collected: { number },
}): number
	if not origin then
		-- Should be impossible once a plot is claimed, so if it ever happens
		-- it must say so in the Output rather than fail as a blank screen.
		warn("[SquishyClicker] Launch with no plot adopted — nothing to draw the flight from.")
		return 0
	end

	shot.distance = math.max(plan.distance, 0)
	shot.arcs = plan.arcs
	shot.simSeconds = math.max(plan.seconds, 1e-3)

	shot.arcStarts = {}
	local running = 0
	for index, arc in plan.arcs do
		shot.arcStarts[index] = running
		running += arc.seconds
	end

	-- Arcs are drawn a fixed fraction as tall as the ground they cover, rather
	-- than to their real height: a maxed shot peaks thirty thousand studs up,
	-- which is off the top of any sky worth having.
	local span = math.max(Config.rangeRadius(shot.distance), 1)
	shot.heightScale = span * ARC_HEIGHT_RATIO / math.max(plan.peakHeight, 1)

	shot.seconds = math.clamp(shot.simSeconds * 0.25, 2.4, 8)
	shot.flown, shot.height, shot.speed, shot.bounced = 0, 0, 0, 0
	shot.progress = 0
	shot.active = true
	shot.holdUntil = os.clock() + shot.seconds + 1.4

	pickupCollecting = {}
	for _, index in plan.collected do
		local entry = pickupField[index]
		if entry and not pickupTaken[index] then
			pickupCollecting[index] = entry.distance
		end
	end

	if not model then
		model = Models.buildSquishy(stage, modelSpec.shape, modelSpec.color, modelSpec.sparkle, modelSpec.scale)
	end
	return shot.seconds
end

-- Somebody else launched: fly their shot out from THEIR plot, over the same
-- bands, with their name over it. Takes the broadcast payload as-is.
function Flight.playGhost(shot2: {
	userId: number?,
	name: string?,
	distance: number,
	arcs: { Arc },
	seconds: number,
	clickerId: string?,
})
	if typeof(shot2.arcs) ~= "table" or #shot2.arcs == 0 then
		return
	end
	if shot2.userId == player.UserId then
		return -- own shot is already flying as the real thing
	end

	-- Their bearing, read off their plot's ownership stamp. No plot found
	-- means nothing to fire from — the feed still lists the shot.
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local bearing: Vector3? = nil
	local originY = 8
	if plots then
		for _, plotFolder in plots:GetChildren() do
			if plotFolder:GetAttribute("OwnerUserId") == shot2.userId then
				local pad = plotFolder:FindFirstChildWhichIsA("BasePart")
				if pad then
					local flat = Vector3.new(pad.Position.X, 0, pad.Position.Z)
					if flat.Magnitude > 1 then
						bearing = flat.Unit
						originY = pad.Position.Y + 8
					end
				end
				break
			end
		end
	end
	if not bearing then
		return
	end

	local ghost = ghosts[nextGhost]
	nextGhost = nextGhost % #ghosts + 1

	ghost.arcs = shot2.arcs
	ghost.arcStarts = {}
	local running, peak = 0, 1
	for index, arc in shot2.arcs do
		ghost.arcStarts[index] = running
		running += arc.seconds
		peak = math.max(peak, arc.peak)
	end

	ghost.simSeconds = math.max(shot2.seconds, 1e-3)
	ghost.seconds = math.clamp(ghost.simSeconds * 0.25, 2.4, 8)
	ghost.progress = 0
	ghost.active = true
	ghost.distance = math.max(shot2.distance, 0)
	ghost.origin = Vector3.new(0, originY, 0)
	ghost.outward = bearing

	local span = math.max(Config.rangeRadius(ghost.distance), 1)
	ghost.heightScale = span * ARC_HEIGHT_RATIO / peak

	local squishy = shot2.clickerId and Squishies.byId[shot2.clickerId]
	ghost.part.Color = squishy and squishy.color or Color3.fromRGB(240, 240, 240)
	ghost.part.Transparency = 0.1
	ghost.label.Text = shot2.name or ""
end

function Flight.distance(): number
	return shot.flown
end
function Flight.height(): number
	return shot.height
end
function Flight.speed(): number
	return shot.speed
end
function Flight.bounces(): number
	return shot.bounced
end

-- ---------- the loop ----------

RunService.RenderStepped:Connect(function(dt)
	local toy = model
	local flying = shot.progress < 1

	if shot.active then
		shot.progress += dt / shot.seconds
		if shot.progress >= 1 then
			shot.progress = 1
			shot.active = false
		end
	end

	if flying then
		shot.flown, shot.height, shot.speed = sample(shot.progress * shot.simSeconds)

		local skips = 0
		for index, arc in shot.arcs do
			if not arc.rolling and shot.flown >= arc.toX and index < #shot.arcs then
				skips += 1
			end
		end
		shot.bounced = skips
	end

	local at = worldAt(shot.flown, shot.height)

	if toy then
		-- Hidden between shots: the squishy belongs on the cushion, not
		-- hovering over the plain waiting for the next launch.
		local scale = flying and 5 * modelSpec.scale or 0.001
		-- Tumbling about the axis PERPENDICULAR to the direction of travel,
		-- so it somersaults forward whichever way the plot faces. A fixed
		-- world axis only looks right on two of the eight bearings; on the
		-- others it reads as a sideways barrel roll.
		local side = Vector3.new(-outward.Z, 0, outward.X)
		Models.apply(
			toy.rig,
			CFrame.new(at) * CFrame.fromAxisAngle(side, -shot.progress * math.pi * 9),
			Vector3.one * scale
		)
	end

	-- Pickups pop as the shot reaches them. The server already decided which
	-- ones; this is only the moment they disappear.
	for index, distance in pickupCollecting do
		if shot.flown >= distance then
			local prize = pickupParts[index]
			if prize then
				prize.Transparency = 1
			end
			pickupTaken[index] = true
			pickupCollecting[index] = nil
		end
	end

	-- Other players' shots, arcing out from their own plots.
	for _, ghost in ghosts do
		if ghost.active then
			ghost.progress += dt / ghost.seconds
			if ghost.progress >= 1 then
				ghost.active = false
				ghost.part.Transparency = 1
			else
				local flown, height =
					sampleArcs(ghost.arcs, ghost.arcStarts, ghost.distance, ghost.progress * ghost.simSeconds)
				ghost.part.Position = ghost.origin
					+ ghost.outward * Config.rangeRadius(flown)
					+ Vector3.new(0, height * ghost.heightScale + 2, 0)
			end
		end
	end

	-- The camera rides behind the shot and hands straight back afterwards.
	local camera = workspace.CurrentCamera
	if camera and (flying or os.clock() < shot.holdUntil) then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local side = Vector3.new(-outward.Z, 0, outward.X)
		local eye = at - outward * CHASE_BACK + Vector3.new(0, CHASE_UP, 0) + side * CHASE_SIDE
		camera.CFrame = CFrame.lookAt(eye, at + outward * 20)
	elseif camera and camera.CameraType == Enum.CameraType.Scriptable and shot.holdUntil > 0 then
		-- Once, on the way out, rather than every frame forever.
		shot.holdUntil = 0
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end)

return Flight
