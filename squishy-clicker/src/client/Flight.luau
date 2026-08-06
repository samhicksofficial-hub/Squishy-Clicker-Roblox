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
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
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
--
-- The shot leaves the MUZZLE of the plot's own cannon — that is the whole
-- fantasy, and an earlier version that spawned it at the island's centre (so
-- distance measured from where the bands do) had it popping into existence a
-- hundred and fifty studs behind the player instead of out of their barrel.
-- The bands still line up: see worldAt.
local muzzle: Vector3? = nil
local muzzleRadius = 0
local outward = Vector3.new(1, 0, 0)

-- Where bounces land, just proud of the plain's top face. Must track Y.plain
-- in Island.luau, the same pairing as MagnetReferenceHeight / STAGE_APEX.
local PLAIN_TOP = -20

-- Cannon smoke, so the launch has a bang to it. Parked at the muzzle by
-- setPlot; Emit'd by play.
local smokeAnchor = Instance.new("Part")
smokeAnchor.Size = Vector3.one
smokeAnchor.Transparency = 1
smokeAnchor.Anchored = true
smokeAnchor.CanCollide = false
smokeAnchor.CanQuery = false
smokeAnchor.CanTouch = false
smokeAnchor.Parent = stage

local muzzleSmoke = Instance.new("ParticleEmitter")
muzzleSmoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
muzzleSmoke.Rate = 0
muzzleSmoke.Lifetime = NumberRange.new(0.5, 1.2)
muzzleSmoke.Speed = NumberRange.new(12, 22)
muzzleSmoke.SpreadAngle = Vector2.new(18, 18)
muzzleSmoke.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 2),
	NumberSequenceKeypoint.new(1, 8),
})
muzzleSmoke.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(1, 1),
})
muzzleSmoke.Parent = smokeAnchor

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
	-- For the chase camera's FOV stretch: speed reads against this.
	launchSpeed = 1,
	-- What the landing popup announces. Carried on the shot rather than read
	-- back from the summary, so the popup and the flight can never disagree.
	earnedCoins = 0,
}

-- Impact bookkeeping, outside the shot table because it belongs to the FX
-- layer: which bounce was last given its splat, whether the landing has had
-- its send-off, and the FOV snap-back that decays after each impact.
local lastBounceSeen = 0
local landingDone = true
local fovKick = 0

-- The FOV eases toward its target rather than being set from speed directly:
-- bounces change speed in a single frame, and an FOV that jumps with it reads
-- as a glitch where an FOV that surges reads as acceleration.
local currentFov = Config.ChaseFovBase

-- Impact shake: a damped sine, amplitude set by each hit and decaying
-- exponentially. One oscillator serves every impact — a second hit mid-wobble
-- just re-kicks the amplitude, which is what a real camera would do.
local shakeAmp = 0
local shakePhase = 0

-- Milestones this flight has yet to cross, for the "+gems" popup at the
-- moment of crossing. Stocked by play() from the server's own first-time
-- list, so the popup can never announce a milestone that didn't pay.
local pendingMilestones: { { at: number, text: string } } = {}

-- The wind trail: two attachments on an invisible part that rides the shot,
-- switched on only at speed. A trail on a slow roll reads as a glitch.
local trailPart = Instance.new("Part")
trailPart.Size = Vector3.one
trailPart.Transparency = 1
trailPart.Anchored = true
trailPart.CanCollide = false
trailPart.CanQuery = false
trailPart.CanTouch = false
trailPart.Parent = stage

local trailTop = Instance.new("Attachment")
trailTop.Position = Vector3.new(0, 2, 0)
trailTop.Parent = trailPart
local trailBottom = Instance.new("Attachment")
trailBottom.Position = Vector3.new(0, -2, 0)
trailBottom.Parent = trailPart

local windTrail = Instance.new("Trail")
windTrail.Attachment0 = trailTop
windTrail.Attachment1 = trailBottom
windTrail.Lifetime = 0.35
windTrail.WidthScale = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(1, 0.2),
})
windTrail.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})
windTrail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
windTrail.FaceCamera = true
windTrail.Enabled = false
windTrail.Parent = trailPart

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

-- ---------- summoned squishies ----------
-- The squishies ARE the pets, and summoning one means it walks the island
-- with YOU — trailing the character, not decorating some stage. They used to
-- be built as followers of the clicker on the hidden diorama, which meant
-- pressing Summon visibly did nothing at all.
type Follower = { model: Models.SquishyModel, scale: number, position: Vector3, velocity: Vector3 }
local followers: { Follower } = {}

-- Soft and underdamped on purpose: pets that keep up perfectly look welded
-- on, and the lag IS the charm.
local FOLLOW_STIFFNESS = 60
local FOLLOW_DAMPING = 11

function Flight.setActiveSquishies(list: { { shape: string?, color: Color3, sparkle: boolean, sizeScale: number? } })
	for _, follower in followers do
		follower.model.rig.folder:Destroy()
	end
	followers = {}

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local seed = root and root.Position or Vector3.zero

	for index, spec in list do
		if index > Config.MaxActiveSquishies then
			break
		end
		table.insert(followers, {
			model = Models.buildSquishy(stage, spec.shape, spec.color, spec.sparkle, spec.sizeScale),
			scale = spec.sizeScale or 1,
			-- Seeded at the player so a fresh summon walks out from them
			-- rather than sprinting in from the world origin.
			position = seed - Vector3.new(index * 3, 0, 0),
			velocity = Vector3.zero,
		})
	end
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
	origin: Vector3, -- their muzzle
	muzzleRadius: number,
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
		muzzleRadius = 0,
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
--
-- Radius is clamped at the muzzle's, so the shot leaves the barrel rather
-- than teleporting to the island's centre first — and everything past the
-- muzzle is on the same circles the bands are painted on, so the landing sits
-- on exactly the band the distance says. (The first ~50 game studs compress
-- onto the muzzle as a result; they pass in a fraction of the first arc, and
-- the squishy is climbing out of the barrel while they do.)
--
-- The baseline sinks from the barrel's height down to the plain across the
-- first band, so bounces out on the range actually touch the ground instead
-- of skipping along at plateau height 22 studs in the air.
local function worldAt(studs: number, height: number): Vector3
	local from = muzzle or Vector3.zero
	local radius = math.max(Config.rangeRadius(studs), muzzleRadius)
	local blend = math.clamp((radius - muzzleRadius) / math.max(Config.RangeNearRadius - muzzleRadius, 1), 0, 1)
	local baseY = from.Y * (1 - blend) + PLAIN_TOP * blend
	return Vector3.new(outward.X * radius, baseY + height * shot.heightScale, outward.Z * radius)
end

-- ---------- public ----------

-- Laying the field out needs a plot to lay it out FROM. Until one is adopted
-- everything stays hidden: the first field arrives from the server during the
-- join handshake, which can beat the plot attribute replicating, and laying
-- it out from a nil origin scattered glowing crates over the plaza — the
-- "something in the sky" hanging above spawn. Defined above setPlot because
-- both setPlot and setField call it, whichever order the two race in.
local function layoutField()
	if not muzzle then
		return
	end

	local tallest = 1
	for _, entry in pickupField do
		tallest = math.max(tallest, entry.height)
	end

	for index, prize in pickupParts do
		local entry = pickupField[index]
		-- Skip the ones the radius clamp would pile onto the muzzle: worldAt
		-- floors every radius at the muzzle's, so the near end of the field
		-- compressed onto one spot and stacked its neon crates into a glowing
		-- pillar over the cannon — the "beacon" in the sky. They still exist
		-- to the server, which sweeps them in the first instant of a shot;
		-- they are just not worth drawing on top of each other.
		local drawable = entry ~= nil
			and not pickupTaken[index]
			and Config.rangeRadius(entry.distance) > muzzleRadius + 6
		if entry and drawable then
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
	-- The mouth of the plot's cannon: a little outward of the plot centre and
	-- up at the height the barrel's mouth sits. Approximated from the plot's
	-- geometry rather than measured off the barrel part, which is close
	-- enough at cannon scale and keeps this file ignorant of how Island.luau
	-- happens to assemble its cannons.
	muzzle = centre + flat.Unit * 9 + Vector3.new(0, 13, 0)
	muzzleRadius = flat.Magnitude + 9
	smokeAnchor.Position = muzzle :: Vector3

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

-- ---------- impact FX ----------

-- A paint splat where the squishy hit, tinted its own colour, spreading and
-- fading off the grass. Created per impact rather than pooled: a flight makes
-- at most a dozen, and each destroys itself.
local function splat(at: Vector3, radius: number)
	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.3, radius, radius)
	disc.CFrame = CFrame.new(at + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	disc.Color = modelSpec.color
	disc.Material = Enum.Material.SmoothPlastic
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.Transparency = 0.2
	disc.Parent = stage

	TweenService:Create(disc, TweenInfo.new(Config.LaunchSplatFadeSeconds, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.3, radius * 1.6, radius * 1.6),
		Transparency = 1,
	}):Play()
	task.delay(Config.LaunchSplatFadeSeconds + 0.1, function()
		disc:Destroy()
	end)
end

-- A small floating number: pops in with a scale bounce, drifts up four studs
-- and is gone in six tenths of a second. Used for every pickup swept mid-air
-- and every milestone crossed — the moment-to-moment juice, where the landing
-- popup below is the finale.
local function floatPopup(at: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = at
	anchor.Parent = stage

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 24, 0, 10) -- scales up in the pop
	gui.MaxDistance = 2500
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 150, 0, 44),
	}):Play()
	TweenService:Create(anchor, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = at + Vector3.new(0, 4, 0),
	}):Play()
	task.delay(0.25, function()
		TweenService:Create(label, TweenInfo.new(0.35), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end)
	task.delay(0.65, function()
		anchor:Destroy()
	end)
end

-- The landing announcement: "+X Studs" and "+$Y" popping up out of the point
-- of rest, scaling in with a bounce and floating away. World-space rather
-- than HUD, so it happens WHERE the shot ended — the summary card already
-- covers the screen-space version.
local function payoutPopup(at: Vector3, distance: number, coins: number)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = at + Vector3.new(0, 6, 0)
	anchor.Parent = stage

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 30, 0, 12) -- scales up to full in the pop
	gui.MaxDistance = 2500
	gui.Parent = anchor

	local function popLine(y: number, text: string, color: Color3, size: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, size + 8)
		label.Position = UDim2.new(0, 0, 0, y)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Parent = gui
		return label
	end

	local lines = { popLine(0, ("+%s Studs"):format(Format.abbreviate(math.floor(distance))), Color3.fromRGB(255, 255, 255), 40) }
	if coins > 0 then
		table.insert(lines, popLine(52, ("+$%s"):format(Format.abbreviate(coins)), Color3.fromRGB(146, 240, 108), 32))
	end

	-- Scale-up pop, then a slow float upward, then fade — three tweens that
	-- overlap rather than queue, which is what makes it feel like one motion.
	TweenService:Create(gui, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 260, 0, 104),
	}):Play()
	TweenService:Create(anchor, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, 12, 0),
	}):Play()
	task.delay(1.1, function()
		for _, label in lines do
			TweenService:Create(label, TweenInfo.new(0.5), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			}):Play()
		end
	end)
	task.delay(1.8, function()
		anchor:Destroy()
	end)
end

function Flight.play(plan: {
	distance: number,
	arcs: { Arc },
	seconds: number,
	peakHeight: number,
	launchSpeed: number?,
	coins: number?,
	milestones: { { name: string, gems: number } }?,
	collected: { number },
}): number
	if not muzzle then
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
	shot.launchSpeed = math.max(plan.launchSpeed or 1, 1)
	shot.earnedCoins = plan.coins or 0
	lastBounceSeen = 0
	landingDone = false
	fovKick = 0
	shakeAmp = 0

	-- The milestones this shot crosses for the first time, positioned from
	-- Config by name so the popup fires at the sign it belongs to.
	pendingMilestones = {}
	for _, milestone in plan.milestones or {} do
		for _, entry in Config.DistanceMilestones do
			if entry.name == milestone.name then
				table.insert(pendingMilestones, {
					at = entry.at,
					text = ("🏁 %s Studs!  +%d 💎"):format(milestone.name, milestone.gems),
				})
				break
			end
		end
	end

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
	muzzleSmoke:Emit(18)
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

	-- Their bearing and muzzle, read off their plot's ownership stamp. No
	-- plot found means nothing to fire from — the feed still lists the shot.
	local map = workspace:FindFirstChild("Map")
	local plots = map and map:FindFirstChild("Plots")
	local bearing: Vector3? = nil
	local theirMuzzle = Vector3.zero
	local theirMuzzleRadius = 0
	if plots then
		for _, plotFolder in plots:GetChildren() do
			if plotFolder:GetAttribute("OwnerUserId") == shot2.userId then
				-- The stamped centre, not the geometry — same replication
				-- race as our own plot, same fix.
				local centre = plotFolder:GetAttribute("PlotCenter")
				if typeof(centre) == "Vector3" then
					local flat = Vector3.new(centre.X, 0, centre.Z)
					if flat.Magnitude > 1 then
						bearing = flat.Unit
						-- Same approximation as our own muzzle in setPlot.
						theirMuzzle = centre + flat.Unit * 9 + Vector3.new(0, 13, 0)
						theirMuzzleRadius = flat.Magnitude + 9
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
	ghost.origin = theirMuzzle
	ghost.muzzleRadius = theirMuzzleRadius
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

	-- Impact FX. A splat per skip and a snap of the camera's FOV; a bigger
	-- splat plus the payout popup once, at the point of rest. landingDone
	-- starts true, so none of this can fire before the first real flight.
	local impactStrength = math.clamp(shot.speed / shot.launchSpeed, 0, 1)
	if flying and shot.bounced > lastBounceSeen then
		lastBounceSeen = shot.bounced
		fovKick = 1
		splat(worldAt(shot.flown, 0), Config.LaunchSplatRadius * 0.7)
		-- Re-kick the shake oscillator, scaled by how fast the hit was.
		shakeAmp = Config.ImpactShakeMagnitude * (0.4 + 0.6 * impactStrength)
		shakePhase = 0
	elseif not flying and not landingDone then
		landingDone = true
		fovKick = 1
		shakeAmp = Config.ImpactShakeMagnitude
		shakePhase = 0
		local ground = worldAt(shot.distance, 0)
		splat(ground, Config.LaunchSplatRadius)
		payoutPopup(ground, shot.distance, shot.earnedCoins)
	end
	fovKick = math.max(fovKick - dt * 3, 0)
	shakePhase += dt

	-- The wind trail rides the shot and only draws at speed.
	trailPart.CFrame = CFrame.new(at)
	windTrail.Enabled = flying and impactStrength > Config.WindTrailMinSpeedFraction

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

	-- Pickups pop as the shot reaches them — with a little "+value" floating
	-- off each one, so a good line through a cluster reads as a combo rather
	-- than as scenery quietly vanishing. The server already decided WHICH
	-- ones; this is only the moment they disappear.
	for index, distance in pickupCollecting do
		if shot.flown >= distance then
			local prize = pickupParts[index]
			local entry = pickupField[index]
			if prize and entry then
				local icon = entry.kind == "coin" and "💵" or entry.kind == "gem" and "💎" or "🧨"
				floatPopup(prize.Position, ("+%d %s"):format(entry.value, icon), PICKUP_LOOK[entry.kind] or PICKUP_LOOK.tnt)
				prize.Transparency = 1
			end
			pickupTaken[index] = true
			pickupCollecting[index] = nil
		end
	end

	-- Milestone signs call out the moment the shot crosses them, at the spot
	-- on the ground the sign marks.
	if flying then
		for index = #pendingMilestones, 1, -1 do
			local milestone = pendingMilestones[index]
			if shot.flown >= milestone.at then
				floatPopup(worldAt(milestone.at, 0) + Vector3.new(0, 16, 0), milestone.text, Color3.fromRGB(255, 220, 120))
				table.remove(pendingMilestones, index)
			end
		end
	end

	-- Summoned squishies trail the character in a loose wedge: first straight
	-- behind, then back-left and back-right. Springs rather than fixed
	-- offsets, so they swing wide on a turn and string out at a sprint.
	local summoner = player.Character
	local characterRoot = summoner and summoner:FindFirstChild("HumanoidRootPart") :: BasePart?
	if characterRoot then
		local look = characterRoot.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		flatLook = flatLook.Magnitude > 0.05 and flatLook.Unit or Vector3.xAxis
		local right = Vector3.new(-flatLook.Z, 0, flatLook.X)

		-- Where the actual ground is, measured off the character rather than
		-- assumed: root centre, less half the root part, less the humanoid's
		-- own hip height. The old fixed -2.1 was wrong for both R6 and R15.
		local humanoid = summoner and summoner:FindFirstChildOfClass("Humanoid")
		local hip = humanoid and humanoid.HipHeight or 2
		local groundY = characterRoot.Position.Y - characterRoot.Size.Y * 0.5 - hip

		for index, follower in followers do
			local sideAmount = index == 2 and -1 or index == 3 and 1 or 0
			local target = characterRoot.Position - flatLook * (5 + index) + right * (sideAmount * 4)
			local pull = (target - follower.position) * FOLLOW_STIFFNESS - follower.velocity * FOLLOW_DAMPING
			follower.velocity += pull * dt
			follower.position += follower.velocity * dt

			-- Stood on its own UNDERSIDE, like the clicker on its cushion: a
			-- model is not centred on the ground, it rests on it, and the
			-- giant squishies were half-buried by exactly their own radius.
			local applied = 1.5 * follower.scale
			local lift = -follower.model.lowestY * applied
			local standAt = Vector3.new(
				follower.position.X,
				groundY + lift + 0.05 + math.sin(os.clock() * 3 + index * 2) * 0.12,
				follower.position.Z
			)
			Models.apply(
				follower.model.rig,
				CFrame.lookAt(standAt, standAt + flatLook),
				Vector3.one * applied
			)
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
				-- The same clamped radius and sinking baseline as our own
				-- shot, so their squishy also leaves a barrel and also
				-- bounces on the actual ground.
				local radius = math.max(Config.rangeRadius(flown), ghost.muzzleRadius)
				local blend = math.clamp(
					(radius - ghost.muzzleRadius) / math.max(Config.RangeNearRadius - ghost.muzzleRadius, 1),
					0,
					1
				)
				local baseY = ghost.origin.Y * (1 - blend) + PLAIN_TOP * blend
				ghost.part.Position = Vector3.new(
					ghost.outward.X * radius,
					baseY + height * ghost.heightScale + 2,
					ghost.outward.Z * radius
				)
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
		-- The damped harmonic shake: an exponentially decaying sine, kicked
		-- by every impact, riding the eye in view space so it reads as the
		-- CAMERA being jolted rather than the world wobbling.
		local wobble = shakeAmp * math.exp(-Config.ImpactShakeDamping * shakePhase)
			* math.sin(shakePhase * math.pi * 2 * Config.ImpactShakeHz)
		local shakeOffset = Vector3.new(0, wobble, 0) + side * wobble * 0.4

		local eye = at - outward * CHASE_BACK + Vector3.new(0, CHASE_UP, 0) + side * CHASE_SIDE + shakeOffset
		camera.CFrame = CFrame.lookAt(eye, at + outward * 20)
		-- FOV stretches with speed — measured against this shot's own launch
		-- speed, so a level-1 arc and a level-80 arc both read as fast at
		-- their own fastest — and every impact snaps it back toward base,
		-- which is most of what makes a bounce feel like hitting something.
		-- Eased toward its target rather than set: speed changes in a single
		-- frame at each bounce, and an FOV that jumps with it reads as a
		-- glitch where one that surges reads as acceleration.
		local speedFactor = math.clamp(shot.speed / shot.launchSpeed, 0, 1)
		local fovTarget = Config.ChaseFovBase + Config.ChaseFovBoost * speedFactor * (1 - fovKick)
		currentFov += (fovTarget - currentFov) * math.min(dt * Config.ChaseFovSmoothing, 1)
		camera.FieldOfView = currentFov
	elseif camera and camera.CameraType == Enum.CameraType.Scriptable and shot.holdUntil > 0 then
		-- Once, on the way out, rather than every frame forever. The FOV goes
		-- back with the camera: leaving it stretched would hand the character
		-- a fisheye and nobody would know which system to blame. The smoothed
		-- value resets too, or the NEXT flight would open mid-surge.
		shot.holdUntil = 0
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = Config.ChaseFovBase
		currentFov = Config.ChaseFovBase
		windTrail.Enabled = false
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end)

return Flight
