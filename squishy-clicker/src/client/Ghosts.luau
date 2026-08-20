--!strict
-- ============================================================
--  GHOST LAUNCHES  —  other players' shots, arcing over the sea.
--
--  The real flight happens in the shooter's own private corridor
--  (Flight.luau), and nothing about that changes. This file is
--  the ISLAND'S window onto it: the moment anyone fires, everyone
--  else sees a ghost of their squishy blast out of their cannon,
--  skip across the rainbow rings painted on the ocean, and splash
--  down on the band matching the shot's expected distance.
--
--  It is an optical illusion BY DESIGN. The ghost steps the same
--  shared sim (shared/Track) from the same launch numbers the
--  shooter got — no steering events, so it flies the honest
--  no-event flight — and its distance is compressed onto the
--  range's log ladder, because a real six-figure flight would
--  leave the map in a heartbeat. Which band it lands on says how
--  big the shot was; the lobby feed's settled number, arriving a
--  few seconds later, says exactly what it scored.
--
--  Nothing here pays, decides or replicates: the server broadcasts
--  a shot's physics (never balances), every client draws its own
--  ghosts locally, and your OWN launches are skipped — you are in
--  the corridor watching the real thing.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Squishies = require(Shared:WaitForChild("Squishies"))
local Track = require(Shared:WaitForChild("Track"))
local Models = require(script.Parent:WaitForChild("Models"))

local Ghosts = {}

local player = Players.LocalPlayer

-- Mirrors the sea geometry in Island.luau: the range bands lie just above
-- the sea's top face (Y.plain - 4 = -26). This is the ground line the ghost
-- skips off — the surface of the painted target.
local SEA_LEVEL = -24.4
-- Mirrors Flight.setPlot's muzzle approximation, so the ghost leaves from
-- the same spot the shooter's own ignition bang plays at.
local MUZZLE_OUT = 9
local MUZZLE_UP = 13
-- The ghost's ground line drops from the muzzle down to the sea over the
-- first stretch of its journey — as a fraction of the whole trip, clamped —
-- so the opening skips land on water rather than in mid-air off the cliff.
local DESCENT_FRACTION = 0.3
local DESCENT_MIN = 60
local DESCENT_MAX = 240

local stage = Instance.new("Folder")
stage.Name = "GhostStage"
stage.Parent = workspace

type Ghost = {
	sim: Track.Sim,
	model: Models.SquishyModel,
	splash: ParticleEmitter,
	origin: Vector3, -- the muzzle's ground point (Y 0), world space
	outwardDir: Vector3, -- unit, out from the island's centre
	scale: number, -- sim studs → world studs along the radial
	descent: number, -- world studs over which the ground line reaches the sea
	spin: number,
	doneAt: number?, -- os.clock when the sim finished, for the linger
}

local ghosts: { Ghost } = {}

-- Where a shot of this expected distance lands, as a radius from the
-- island's centre: Config.rangeRadius, the same mapping the range bands are
-- painted with — which is what makes a ghost splash down on the band its
-- distance names. The floor keeps even a barrel-fumble clear of the beach,
-- so every ghost visibly reaches the water.
local function landingRadius(expected: number): number
	return math.max(Config.rangeRadius(expected), Config.RangeNearRadius * 0.85)
end

local function destroyGhost(index: number)
	local ghost = table.remove(ghosts, index)
	if ghost then
		-- The name tag and the splash emitter ride the rig's primary part,
		-- so the one folder takes everything with it.
		ghost.model.rig.folder:Destroy()
	end
end

local function num(value: any, fallback: number): number
	return if typeof(value) == "number" and value == value then value else fallback
end

local function spawnGhost(payload: { [string]: any })
	-- Your own launch is the real one, playing in your corridor right now.
	if payload.userId == player.UserId then
		return
	end
	local origin = payload.origin
	if typeof(origin) ~= "Vector3" then
		return
	end
	local flat = Vector3.new(origin.X, 0, origin.Z)
	if flat.Magnitude < 1 then
		return
	end

	local expected = math.max(num(payload.expected, 100), 1)
	local vx = num(payload.vx, 0)
	local vy = num(payload.vy, Config.FlightVyMin)
	if vx <= 0 then
		return
	end

	-- The same physics the shooter is flying, stepped with no events: the
	-- honest no-event flight, which Track.calibrate sized to land at the
	-- expected distance — so the scaled ghost lands on the expected band.
	local phys = Track.basePhysics()
	phys.gravity = math.max(num(payload.gravity, phys.gravity), 1)
	phys.restitution = math.clamp(num(payload.restitution, phys.restitution), 0, 0.95)
	phys.bounceFriction = math.clamp(num(payload.bounceFriction, phys.bounceFriction), 0, 1)
	phys.minBounceSpeed = math.max(num(payload.minBounceSpeed, phys.minBounceSpeed), 1)
	phys.rollSeconds = math.max(num(payload.rollSeconds, phys.rollSeconds), 0.5)
	phys.endSpeed = math.max(num(payload.endSpeed, phys.endSpeed), 1)
	phys.maxSeconds = math.min(num(payload.maxSeconds, phys.maxSeconds), 60)

	-- The newest shot always flies: past the cap, the oldest ghost yields.
	while #ghosts >= Config.LobbyMaxGhosts do
		destroyGhost(1)
	end

	local outwardDir = flat.Unit
	local muzzleGround = flat + outwardDir * MUZZLE_OUT
	local startRadius = muzzleGround.Magnitude
	local span = math.max(landingRadius(expected) - startRadius, 40)

	-- The shooter's real squisher, so a banana launch is visibly a banana.
	-- Meshes and fallbacks come along for free through Models.buildSquishy.
	local squishy = Squishies.byId[tostring(payload.clickerId or "")] or Squishies.byId.red or Squishies.list[1]
	local model = Models.buildSquishy(stage, squishy.shape, squishy.color, squishy.sparkle == true, squishy.scale)

	-- The name over the shot, readable from the plaza. No distance on it —
	-- a living flight has no number until it settles, and the settled one
	-- belongs to the lobby feed.
	local tag = Instance.new("BillboardGui")
	tag.Name = "GhostTag"
	tag.Size = UDim2.new(0, 210, 0, 36)
	tag.StudsOffset = Vector3.new(0, 6, 0)
	tag.MaxDistance = 1400
	tag.LightInfluence = 0
	tag.Parent = model.primary
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = ("🚀 %s"):format(tostring(payload.name or "???"))
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = tag

	-- The splash for every skip: a puff of pale spray emitted from wherever
	-- the ghost is when the sim touches its ground line.
	local splash = Instance.new("ParticleEmitter")
	splash.Name = "GhostSplash"
	splash.Texture = "rbxasset://textures/particles/smoke_main.dds"
	splash.Color = ColorSequence.new(Color3.fromRGB(214, 242, 252))
	splash.Rate = 0
	splash.Lifetime = NumberRange.new(0.4, 0.8)
	splash.Speed = NumberRange.new(8, 18)
	splash.SpreadAngle = Vector2.new(70, 70)
	splash.Size = NumberSequence.new(2.4, 5)
	splash.Transparency = NumberSequence.new(0.25, 1)
	splash.EmissionDirection = Enum.NormalId.Top
	splash.Parent = model.primary

	table.insert(ghosts, {
		sim = Track.newSim(vx, vy, phys),
		model = model,
		splash = splash,
		origin = muzzleGround,
		outwardDir = outwardDir,
		scale = span / expected,
		descent = math.clamp(span * DESCENT_FRACTION, DESCENT_MIN, DESCENT_MAX),
		spin = 0,
		doneAt = nil,
	})
end

-- The flight loop: every live ghost steps its sim and draws at the scaled
-- position. Heartbeat rather than RenderStepped — ghosts are scenery, not
-- the camera. An empty list costs one comparison per frame.
RunService.Heartbeat:Connect(function(deltaTime)
	for index = #ghosts, 1, -1 do
		local ghost = ghosts[index]
		local sim = ghost.sim

		if not sim.done then
			-- Substepped like the real flight, capped so a tab-out cannot
			-- fast-forward a ghost across the sea in one giant leap.
			local remaining = math.min(deltaTime, 0.25)
			while remaining > 0 and not sim.done do
				local step = math.min(remaining, 1 / 60)
				Track.step(sim, step)
				if sim.hitGround then
					ghost.splash:Emit(14)
				end
				remaining -= step
			end
			if sim.done then
				ghost.doneAt = os.clock()
				ghost.splash:Emit(26)
			end
		end

		-- The ground line: the muzzle's height at the barrel, easing down
		-- to the sea over the opening stretch, so the first skip lands on
		-- water. Sim height rides on top at 1:1 — the fixed vertical
		-- envelope fits the sea view as well as it fits the corridor.
		local worldAlong = sim.dist * ghost.scale
		local drop = math.clamp(worldAlong / ghost.descent, 0, 1)
		local baseY = MUZZLE_UP + (SEA_LEVEL - MUZZLE_UP) * drop
		local at = ghost.origin + ghost.outwardDir * worldAlong + Vector3.new(0, baseY + sim.h, 0)

		-- The somersault, about the axis perpendicular to the travel, same
		-- as the corridor's toy — slowing as the shot rolls out.
		local tumble = if sim.done then 0 else math.pi * 2.2 * math.clamp(sim.vx * ghost.scale / 60, 0.2, 1.6)
		ghost.spin += tumble * deltaTime

		local applied = Config.GhostScale * ghost.model.sizeScale
		local sideAxis = Vector3.new(-ghost.outwardDir.Z, 0, ghost.outwardDir.X)
		Models.apply(
			ghost.model.rig,
			CFrame.new(at + Vector3.new(0, -ghost.model.lowestY * applied, 0))
				* CFrame.fromAxisAngle(sideAxis, -ghost.spin),
			Vector3.one * applied
		)

		-- Landed: float on the water a beat so the band it reached can be
		-- read, then gone.
		if ghost.doneAt and os.clock() - (ghost.doneAt :: number) > 2.4 then
			destroyGhost(index)
		end
	end
end)

function Ghosts.mount()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ghostRemote = remotes:WaitForChild("GhostLaunch") :: RemoteEvent

	ghostRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		spawnGhost(payload)
	end)
end

return Ghosts
