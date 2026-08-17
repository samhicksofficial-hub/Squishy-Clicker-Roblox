--!strict
-- ============================================================
--  FLIGHT  —  the living shot, flown in a private endless corridor.
--
--  The bang happens at YOUR cannon on YOUR plot; a beat later the
--  camera cuts to a walled corridor that belongs to this client
--  alone, where the flight plays as a TREADMILL: the squishy stays
--  near a fixed origin and pooled floor tiles, canyon walls and
--  distance numbers painted on the road scroll past at true
--  one-to-one studs. A "10K" on the floor is ten thousand real studs —
--  no log compression anywhere, and no far edge: indices are just
--  integers, so the corridor never ends.
--
--  The flight has NO predetermined length. The server sends momentum
--  (calibrated so the power economy holds), a fixed-scale vertical
--  launch, physics, and a track SEED — then this file flies a real
--  simulation (shared/Track) that lasts exactly as long as the player
--  keeps it alive: boots relaunch it, bombs bleed it, slams dive it,
--  and it ends when the roll runs out of speed. The track itself is
--  seeded chunks generated on demand, so however far the shot goes,
--  there is always more of it.
--
--  Everything draws RELATIVE to the flown distance:
--      corridorAt(d, h) = ORIGIN + FORWARD * (d - shot.flown) + up
--  which is what makes a million-stud flight cost the same as a
--  hundred-stud one — the camera never actually goes anywhere.
--
--  And still: nothing here decides anything that PAYS. Every touch is
--  logged as an event; the server re-runs this same sim from that log
--  and the flight's real distance and income are whatever ITS copy
--  says (see settleFlight, server-side).
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
-- The living flight and the endless track — the SAME module the server
-- settles with, which is what keeps the drawn world and the paid world
-- from ever drifting apart.
local Track = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Track"))
local Models = require(script.Parent:WaitForChild("Models"))

local Flight = {}

local player = Players.LocalPlayer

-- Chase camera, in studs behind / above / to the side of the squishy.
local CHASE_BACK = 26
local CHASE_UP = 14
local CHASE_SIDE = 16

-- ---------- the corridor's coordinate frame ----------
-- Private and at altitude, exactly like Scene.luau's diorama (its ORIGIN is
-- Y 6000; this sits well above so neither world ever appears in the other's
-- frame). Axes are FIXED and plot-independent — the corridor belongs to
-- this client alone, so no bearing math survives from the shared-range era.
local CORRIDOR_ORIGIN = Vector3.new(0, 9000, 0)
local FORWARD = Vector3.xAxis
local SIDE = Vector3.zAxis

local stage = Instance.new("Folder")
stage.Name = "FlightStage"
stage.Parent = workspace

-- The plot's cannon muzzle: where the ignition bang plays, and where the
-- capsule display sits. Set from the player's own plot the moment one is
-- claimed for them; until then the flight has nowhere to bang from and
-- simply does not play. The FLIGHT itself no longer happens here — after
-- CorridorCutDelay seconds of smoke the camera hard-cuts to the corridor.
local muzzle: Vector3? = nil
local outward = Vector3.new(1, 0, 0)

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

-- ---------- the capsule display ----------
-- The chosen squishy's icon floating over the launch capsule, so the pod
-- reads as loaded with THIS one: the same circular swatch as the collection
-- list, with the real 3D model in a viewport and the selection-green ring.
-- Client-local like the rest of this file.

-- Must track STATION_BACK in Island.luau — the capsule stands this far
-- inward of the plot centre.
local STATION_BACK = 13
local CAPSULE_ICON_HEIGHT = 11

local stationAnchor = Instance.new("Part")
stationAnchor.Size = Vector3.one
stationAnchor.Transparency = 1
stationAnchor.Anchored = true
stationAnchor.CanCollide = false
stationAnchor.CanQuery = false
stationAnchor.CanTouch = false
stationAnchor.Position = Vector3.new(0, -500, 0) -- parked until a plot is adopted
stationAnchor.Parent = stage

-- The badge over the capsule: the chosen squishy's circular 3D portrait
-- with the selection-green ring, floating just above the capsule's crown.
-- Parented to PLAYERGUI with the anchor as Adornee, not to the anchor
-- itself: a ViewportFrame inside a workspace-parented BillboardGui does
-- not reliably render its 3D scene. Stud-sized (the Scale component of a
-- BillboardGui's Size is studs), so it shrinks with perspective like the
-- pod it sits on.
local stationGui = Instance.new("BillboardGui")
stationGui.Name = "CapsuleBadge"
stationGui.Size = UDim2.new(4, 0, 4, 0)
stationGui.MaxDistance = 160
stationGui.LightInfluence = 0 -- full brightness; an icon in shadow reads as broken
stationGui.Adornee = stationAnchor
stationGui.Parent = player:WaitForChild("PlayerGui")

local stationIcon = Instance.new("ViewportFrame")
stationIcon.Size = UDim2.fromScale(1, 1)
stationIcon.BackgroundColor3 = Color3.fromRGB(252, 248, 244)
stationIcon.BackgroundTransparency = 0
stationIcon.Ambient = Color3.fromRGB(170, 165, 160)
stationIcon.LightColor = Color3.fromRGB(255, 250, 244)
stationIcon.LightDirection = Vector3.new(-0.5, -1, -0.6)
stationIcon.Parent = stationGui

local stationCorner = Instance.new("UICorner")
stationCorner.CornerRadius = UDim.new(1, 0)
stationCorner.Parent = stationIcon

local stationRing = Instance.new("UIStroke")
stationRing.Color = Color3.fromRGB(70, 200, 60)
-- Stroke pixels don't scale with the stud-sized badge, so a thick ring
-- would swallow the icon once distance shrinks it.
stationRing.Thickness = 3
stationRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stationRing.Parent = stationIcon

local stationCamera = Instance.new("Camera")
stationCamera.FieldOfView = 28
stationCamera.CFrame = CFrame.lookAt(Vector3.new(0, 0.9, 8), Vector3.zero)
stationCamera.Parent = stationIcon
stationIcon.CurrentCamera = stationCamera

local stationStage: Folder? = nil

-- Rebuild the icon's little 3D scene for the current squishy. Same recipe
-- as the collection icons: the real model, narrow lens from further back
-- so the shape reads cleanly at icon size.
local function refreshStationIcon()
	if stationStage then
		stationStage:Destroy()
	end
	local previewStage = Instance.new("Folder")
	previewStage.Name = "Model"
	previewStage.Parent = stationIcon
	stationStage = previewStage

	local preview = Models.buildSquishy(previewStage, modelSpec.shape, modelSpec.color, modelSpec.sparkle, modelSpec.scale)
	Models.apply(preview.rig, CFrame.identity, Vector3.one * preview.sizeScale)
	stationIcon.BackgroundColor3 = modelSpec.color
end

-- ---------- the capsule occupant ----------
-- The player's chosen MAIN squishy stands inside the capsule pod behind
-- their cannon: the badge names the station, the glass shows the goods.
-- Client-local exactly like the badge — every player sees their own
-- squishy in their own capsule. The capsule model is hand-placed in the
-- baked world, so it is found in the plot's own folder by LOOSE name, and
-- the placeholder toy it shipped with ("slime") is hidden locally rather
-- than destroyed — those parts are the server's.
local capsuleSeat: Vector3? = nil
local capsuleHeight = 4 -- world height the occupant is scaled to stand at
-- Bumped per plot adoption, so a stale capsule poller from a previous
-- adoption can never wire an old plot's capsule over the new one's.
local capsuleToken = 0

local function findLoose(container: Instance, needle: string): Instance?
	for _, descendant in container:GetDescendants() do
		if descendant.Name:lower():find(needle, 1, true) then
			return descendant
		end
	end
	return nil
end

local occupant: Models.SquishyModel? = nil

local function rebuildOccupant()
	if occupant then
		occupant.rig.folder:Destroy()
		occupant = nil
	end
	if capsuleSeat then
		occupant = Models.buildSquishy(stage, modelSpec.shape, modelSpec.color, modelSpec.sparkle, modelSpec.scale)
	end
end

-- The live simulation itself (shared/Track), plus the mirror the drawing
-- code reads. `sim` is nil until the first shot; `shot` carries what the
-- corridor, camera and HUD actually consume each frame.
local sim: Track.Sim? = nil
local shot = {
	active = false,
	flown = 0,
	height = 0,
	speed = 0,
	bounced = 0,
	holdUntil = 0,
	-- For the chase camera's FOV stretch: speed reads against this (the
	-- calibrated forward momentum the shot left the barrel with).
	launchSpeed = 1,
	-- The oracle's expected distance. NOT a limit — the flight goes where
	-- it goes — this only sizes the marker ladder so the road numbers suit
	-- the flight's likely scale.
	expected = 100,
}
-- The magnet's sweep width for this shot, in lane units, straight from the
-- server. Pickups this close to centre vacuum themselves as the flight
-- passes — no event sent, because the server pays them unclaimed.
local shotMagnet = 0

-- Impact bookkeeping, outside the shot table because it belongs to the FX
-- layer: which bounce was last given its splat, whether the landing has had
-- its send-off, and the FOV snap-back that decays after each impact.
local lastBounceSeen = 0
local landingDone = true
local fovKick = 0

-- The shot's visible physics. The server still decides every number that
-- matters; these only make the replay OBEY the story those numbers tell:
-- spin is set by the launch and bled off by every bounce (the same friction
-- that slows the ground speed slows the tumble), squash is re-kicked by
-- each impact and relaxes on its own, and the roll turns at whatever rate
-- the ground drawn underneath is actually passing.
local spinAngle = 0
local spinRate = 0
local squash = 0

-- The FOV eases toward its target rather than being set from speed directly:
-- bounces change speed in a single frame, and an FOV that jumps with it reads
-- as a glitch where an FOV that surges reads as acceleration.
local currentFov = Config.ChaseFovBase

-- The chase camera's smoothed eye and aim: the toy draws exactly where the
-- maths puts it (pickup pops must line up), but the CAMERA gliding a beat
-- behind is what makes the whole ride read as smooth.
local camEye: Vector3? = nil
local camLook: Vector3? = nil

-- Impact shake: a damped sine, amplitude set by each hit and decaying
-- exponentially. One oscillator serves every impact — a second hit mid-wobble
-- just re-kicks the amplitude, which is what a real camera would do.
local shakeAmp = 0
local shakePhase = 0

-- Milestones this flight has yet to cross, for the "+Cash" popup at the
-- moment of crossing. Stocked by play() from the server's own first-time
-- list, so the popup can never announce a milestone that didn't pay.
local pendingMilestones: { { at: number, text: string } } = {}

-- The wind: speed-line particles streaming BACKWARD from an invisible part
-- riding the shot, switched on only at speed. This used to be a Trail, but
-- a Trail draws between the subject's historical positions — and on the
-- treadmill the squishy barely moves, so the trail collapsed to a stub.
-- Particles carry their own velocity, so the treadmill can't starve them.
local trailPart = Instance.new("Part")
trailPart.Size = Vector3.one
trailPart.Transparency = 1
trailPart.Anchored = true
trailPart.CanCollide = false
trailPart.CanQuery = false
trailPart.CanTouch = false
trailPart.Parent = stage

local windTrail = Instance.new("ParticleEmitter")
windTrail.Texture = "rbxasset://textures/particles/sparkles_main.dds"
windTrail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
windTrail.Rate = 34
windTrail.Lifetime = NumberRange.new(0.25, 0.4)
windTrail.Speed = NumberRange.new(120, 190)
windTrail.EmissionDirection = Enum.NormalId.Back
windTrail.SpreadAngle = Vector2.new(8, 8)
windTrail.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1.6),
	NumberSequenceKeypoint.new(1, 0.2),
})
windTrail.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.55),
	NumberSequenceKeypoint.new(1, 1),
})
windTrail.LightEmission = 0.6
windTrail.Enabled = false
windTrail.Parent = trailPart

-- ---------- pickups ----------
-- One currency now: every pickup is Cash. The kind key survives so an old
-- server payload can't crash the lookup — anything unknown draws as coin.
-- Deep cash green rather than bright gold: neon brightness rides the
-- colour's luminance, and the old pale gold bloomed into featureless white
-- blobs against the bright sky. VIP pickups stay golden — the jackpot
-- stretch is supposed to shout.
local PICKUP_LOOK = {
	coin = Color3.fromRGB(96, 210, 100),
}
local VIP_GOLD = Color3.fromRGB(240, 190, 70)

-- ---------- the seeded track, client copy ----------
-- Chunks generate on demand from the shot's seed — the same function the
-- server settles with. Everything per-entry is keyed by the entry's id
-- (unique across the whole flight), never by array position: the track has
-- no fixed length for positions to be stable against.
local trackSeed = 0
local chunkCache: { [number]: Track.Chunk } = {}
local function chunkFor(index: number): Track.Chunk
	local cached = chunkCache[index]
	if cached then
		return cached
	end
	local made = Track.chunk(trackSeed, index)
	chunkCache[index] = made
	return made
end

local pickupParts: { BasePart } = {}
local pickupTaken: { [number]: boolean } = {}
-- Where each drawn pickup RESTS: the render loop bobs and spins them around
-- these, so layout writes here and animation never fights it.
local pickupBase: { [number]: Vector3 } = {}

-- ---------- imported track models ----------
-- The cash stack, boost boot and cartoon bomb ride in from Meshy the same
-- way the cannon did: imported by hand into ReplicatedStorage, adopted by a
-- tolerant name match, cloned per pool slot. Only the LARGEST part of a
-- template is taken — Meshy image-to-3d exports are a single mesh, and one
-- part keeps every pool's BasePart logic (CFrame bobbing, transparency
-- toggles, billboards) working unchanged. Clones are geometry-only:
-- stowaway scripts stripped, anchored, inert. No template imported yet =
-- the shaped-part fallbacks, exactly as before.
local meshTemplates: { [string]: BasePart | false } = {}

local function templatePart(cacheKey: string, looseNames: { string }, target: number): BasePart?
	local cached = meshTemplates[cacheKey]
	if cached == false then
		return nil
	end
	if cached then
		return (cached :: BasePart):Clone()
	end

	for _, looseName in looseNames do
		local wanted = looseName:lower():gsub("[%s_]", "")
		for _, descendant in ReplicatedStorage:GetDescendants() do
			if
				(descendant:IsA("Model") or descendant:IsA("BasePart"))
				and descendant.Name:lower():gsub("[%s_]", "") == wanted
			then
				local source: BasePart? = if descendant:IsA("BasePart") then descendant else nil
				if not source and descendant:IsA("Model") then
					local biggest = -1
					for _, piece in descendant:GetDescendants() do
						if piece:IsA("BasePart") then
							local bulk = piece.Size.X * piece.Size.Y * piece.Size.Z
							if bulk > biggest then
								biggest = bulk
								source = piece
							end
						end
					end
				end
				if source then
					local master = source:Clone()
					for _, stowaway in master:GetDescendants() do
						if stowaway:IsA("LuaSourceContainer") then
							stowaway:Destroy()
						end
					end
					master.Anchored = true
					master.CanCollide = false
					master.CanQuery = false
					master.CanTouch = false
					master.Transparency = 1
					local longest = math.max(master.Size.X, master.Size.Y, master.Size.Z)
					if longest > 0.05 then
						master.Size = master.Size * (target / longest)
					end
					-- The flag layout reads to know "this is a real model":
					-- meshes keep their painted size and colour, where the
					-- fallback blocks get resized and tinted per entry.
					master:SetAttribute("MeshBase", master.Size)
					meshTemplates[cacheKey] = master
					return master:Clone()
				end
			end
		end
	end

	meshTemplates[cacheKey] = false
	print(("[SquishyClicker] No '%s' model in ReplicatedStorage — using the built-in shape."):format(looseNames[1]))
	return nil
end

-- Sized to the view WINDOW, not the flight: at most ~4 chunks are ever on
-- show at once (ahead 900 + behind 160 over 400-stud chunks), each holding
-- ChunkCashCount pickups plus a possible 5-pickup VIP knot. (A predecessor
-- of this line once read a REMOVED config key — nil arithmetic killed this
-- module at require time and took the whole HUD down with it. Every button
-- gone, no error visible past the Output.)
local POOL = 64
for _ = 1, POOL do
	-- The imported cash-stack model when it exists; the neon block until.
	local prize = templatePart("cash", { "CashStack", "Cash" }, 6)
	if not prize then
		local block = Instance.new("Part")
		block.Size = Vector3.one * 5.5
		block.Material = Enum.Material.Neon
		prize = block
	end
	local prizePart = prize :: BasePart
	prizePart.Anchored = true
	prizePart.CanCollide = false
	prizePart.CanQuery = false
	prizePart.CanTouch = false
	prizePart.Transparency = 1
	prizePart.Parent = stage

	-- The 💵 over each block is what says "this is money" from any range.
	-- Stud-sized, so it shrinks with distance like the block it labels.
	local icon = Instance.new("BillboardGui")
	icon.Name = "CashIcon"
	icon.Size = UDim2.new(3, 0, 3, 0)
	icon.StudsOffset = Vector3.new(0, 3.4, 0)
	icon.LightInfluence = 0
	icon.Enabled = false
	icon.Parent = prizePart
	local face = Instance.new("TextLabel")
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.Text = "💵"
	face.TextScaled = true
	face.Parent = icon
	-- The uploaded cash-stack image, when Config carries its id. Both live
	-- in the billboard; the field cosmetics pass shows whichever applies.
	local pic = Instance.new("ImageLabel")
	pic.Name = "Pic"
	pic.Size = UDim2.fromScale(1, 1)
	pic.BackgroundTransparency = 1
	pic.Image = Config.CashIconImage
	pic.ScaleType = Enum.ScaleType.Fit
	pic.Visible = false
	pic.Parent = icon

	table.insert(pickupParts, prizePart)
end

-- ---------- the steerable extras ----------
-- Boost boots and bombs ride the same track as the cash, out in the lane
-- where only steering reaches. Same house style as the pickups: a shaped
-- part with a stud-sized emoji billboard, which reads at any distance.
local function makeExtraPart(shape: Enum.PartType, size: number, color: Color3, material: Enum.Material, glyph: string, glyphSize: number): BasePart
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = Vector3.one * size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = stage

	local icon = Instance.new("BillboardGui")
	icon.Name = "Glyph"
	icon.Size = UDim2.new(glyphSize, 0, glyphSize, 0)
	icon.LightInfluence = 0
	icon.Enabled = false
	icon.Parent = part
	local face = Instance.new("TextLabel")
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.Text = glyph
	face.TextScaled = true
	face.Parent = icon
	return part
end

local bootParts: { BasePart } = {}
local bombParts: { BasePart } = {}
-- Pool sizes follow the same window budget as the pickups: up to two boots
-- and three bombs per chunk, four chunks on show.
for _ = 1, 8 do
	local boot = templatePart("boot", { "BoostBoot", "Boost" }, 8)
	if boot then
		boot.Parent = stage
		table.insert(bootParts, boot)
	else
		table.insert(
			bootParts,
			makeExtraPart(Enum.PartType.Block, 7, Color3.fromRGB(88, 232, 96), Enum.Material.Neon, "⬆️", 6)
		)
	end
end
for _ = 1, 14 do
	local bomb = templatePart("bomb", { "CartoonBomb", "Bomb" }, 8)
	if bomb then
		bomb.Parent = stage
		table.insert(bombParts, bomb)
	else
		table.insert(
			bombParts,
			makeExtraPart(Enum.PartType.Ball, 7.5, Color3.fromRGB(52, 52, 58), Enum.Material.SmoothPlastic, "💣", 5.5)
		)
	end
end

local bootBase: { [number]: Vector3 } = {}
local bombBase: { [number]: Vector3 } = {}
local bootTaken: { [number]: boolean } = {}
local bombHit: { [number]: boolean } = {}

-- ---------- pooled part allocation ----------
-- The track is endless but the pools are not: each entry borrows a part
-- while it is inside the view window and hands it back on the way out.
-- Dressing happens once, at assignment — never per frame.
type Allocator = { assign: { [number]: BasePart }, free: { BasePart } }

local function makeAllocator(parts: { BasePart }): Allocator
	local free = table.create(#parts)
	for _, part in parts do
		table.insert(free, part)
	end
	return { assign = {}, free = free }
end

-- Hide an entry's part (if it has one) and return it to the pool.
local function releaseEntry(alloc: Allocator, bases: { [number]: Vector3 }, id: number)
	local part = alloc.assign[id]
	if part then
		alloc.assign[id] = nil
		part.Transparency = 1
		local icon = part:FindFirstChild("CashIcon") or part:FindFirstChild("Glyph")
		if icon then
			(icon :: BillboardGui).Enabled = false
		end
		table.insert(alloc.free, part)
	end
	bases[id] = nil
end

local function releaseAll(alloc: Allocator, bases: { [number]: Vector3 })
	for id in pairs(alloc.assign) do
		releaseEntry(alloc, bases, id)
	end
	table.clear(bases)
end

local pickupAlloc = makeAllocator(pickupParts)
local bootAlloc = makeAllocator(bootParts)
local bombAlloc = makeAllocator(bombParts)

-- The ascending ping for flying through a boot.
local bootSound = Instance.new("Sound")
bootSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
bootSound.Volume = 0.6
bootSound.Parent = SoundService

-- The flight's little orchestra, all built from two stock samples pitched
-- around: snap.wav slowed down is a thump, sped up is a knock; the ping
-- rises with combos. Stock assets on purpose — they can never fail to load.
local launchBoom = Instance.new("Sound")
launchBoom.SoundId = "rbxasset://sounds/snap.wav"
launchBoom.Volume = 0.9
launchBoom.Parent = SoundService

local bounceThock = Instance.new("Sound")
bounceThock.SoundId = "rbxasset://sounds/snap.wav"
bounceThock.Volume = 0.5
bounceThock.Parent = SoundService

local comboPing = Instance.new("Sound")
comboPing.SoundId = "rbxasset://sounds/electronicpingshort.wav"
comboPing.Volume = 0.45
comboPing.Parent = SoundService

-- Combo state: steered pickups taken in quick succession count up, and the
-- count is worth announcing from three. Only ACTIVE collection combos —
-- the magnet's passive sweeps stay quiet, because combos are for skill.
local comboCount = 0
local comboAt = 0

-- Bombs the shot has already sailed close past, so "phew!" fires once each.
local bombNear: { [number]: boolean } = {}

-- ---------- the corridor ----------
-- The treadmill's fixed scenery: pooled floor tiles, canyon walls with lip
-- caps, distance boards, and a fogged end cap. Pools wrap by modulo inside
-- the view window, so the same twenty tiles carry a hundred-stud shot and a
-- million-stud one alike.

-- Lane units → studs, FIXED. The shared range scaled this with distance;
-- the corridor never does — which is what makes the walls honest.
local function laneToStuds(lane: number): number
	return lane * Config.CorridorStudsPerLane
end

-- Where sim distance `d` at sim height `h` draws, relative to the flight's
-- current flown distance. THE treadmill equation: the squishy's own forward
-- term is always zero, and everything else slides past it. Heights are 1:1
-- now — the live sim's fixed vertical envelope never outgrows the walls.
local function corridorAt(d: number, simHeight: number): Vector3
	return CORRIDOR_ORIGIN + FORWARD * (d - shot.flown) + Vector3.new(0, simHeight, 0)
end

-- Snap a raw spacing to the 1 / 2.5 / 5 × 10^k ladder, so marker numbers
-- are always figures a person can read at speed.
local function niceStep(raw: number): number
	local floor10 = 10 ^ math.floor(math.log10(math.max(raw, 1)))
	for _, mult in { 1, 2.5, 5, 10 } do
		if raw <= floor10 * mult then
			return math.max(floor10 * mult, 25)
		end
	end
	return math.max(floor10 * 10, 25)
end

local corridorFolder = Instance.new("Folder")
corridorFolder.Name = "Corridor"
corridorFolder.Parent = stage

-- The palette the corridor wears; Flight.setWorld repaints it. Defaults
-- match Sunny Meadow so the first flight is right even before a sync.
local corridorTheme = {
	grass = Color3.fromRGB(138, 214, 74),
	grassDark = Color3.fromRGB(112, 190, 58),
	canyon = Color3.fromRGB(226, 118, 118),
}

local function corridorPart(size: Vector3, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Parked AT the corridor's altitude from birth. A fresh Part defaults
	-- to the world origin — which is the middle of the plaza, where the end
	-- cap and a canyon wall stood like monoliths until the first flight's
	-- window pass finally seated them.
	part.CFrame = CFrame.new(CORRIDOR_ORIGIN)
	part.Parent = corridorFolder
	return part
end

type MarkerSet = { panel: BasePart, label: TextLabel, index: number }

local corridorTiles: { BasePart } = {}
local corridorWalls: { { left: BasePart, right: BasePart, leftLip: BasePart, rightLip: BasePart } } = {}
local corridorMarkers: { MarkerSet } = {}
local CORRIDOR_POOL = 20

do
	local width = Config.CorridorFloorWidth
	local wallHeight = Config.CorridorWallHeight
	local tileLength = Config.CorridorTileLength

	for index = 1, CORRIDOR_POOL do
		-- Floor: alternating shades, studded — the banding is most of what
		-- conveys the treadmill actually moving.
		local tile = corridorPart(Vector3.new(tileLength, 2, width), corridorTheme.grass, Enum.Material.Plastic)
		tile.TopSurface = Enum.SurfaceType.Studs
		corridorTiles[index] = tile

		-- Walls with lip caps: the island's Canyon/CanyonLip recipe, so the
		-- corridor reads as the same universe.
		local function wallPair(): (BasePart, BasePart)
			local wall = corridorPart(
				Vector3.new(tileLength, wallHeight, 6),
				corridorTheme.canyon,
				Enum.Material.Sandstone
			)
			local lip = corridorPart(Vector3.new(tileLength, 4, 8), corridorTheme.grassDark, Enum.Material.Plastic)
			lip.TopSurface = Enum.SurfaceType.Studs
			return wall, lip
		end
		local left, leftLip = wallPair()
		local right, rightLip = wallPair()
		corridorWalls[index] = { left = left, right = right, leftLip = leftLip, rightLip = rightLip }

		-- A marker: the distance painted flat on the road, like airport
		-- runway numbers. The part itself is invisible — a SurfaceGui
		-- renders regardless of its part's transparency — so all that
		-- shows is the number on the ground.
		local panel = corridorPart(
			Vector3.new(width - 24, 0.5, 16),
			Color3.fromRGB(255, 255, 255),
			Enum.Material.SmoothPlastic
		)
		panel.Transparency = 1
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Top
		surface.PixelsPerStud = 25
		surface.Parent = panel
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = ""
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
		label.TextStrokeTransparency = 0.35
		label.TextTransparency = 0.12
		label.TextScaled = true
		label.Parent = surface
		corridorMarkers[index] = { panel = panel, label = label, index = -1 }
	end
end

-- Depth: a solid end cap past the view window and two translucent fog
-- planes on the way to it. GEOMETRY fog on purpose — classic Lighting fog
-- is ignored while an Atmosphere instance exists (the sky pack ships one),
-- and borrowing Lighting state is how systems here have fought before.
local corridorCap: BasePart
local corridorFog: { BasePart } = {}
do
	local width = Config.CorridorFloorWidth
	local wallHeight = Config.CorridorWallHeight
	corridorCap = corridorPart(Vector3.new(2, wallHeight, width + 16), Color3.fromRGB(196, 220, 244), Enum.Material.SmoothPlastic)
	for _, fraction in { 0.6, 0.85 } do
		local plane = corridorPart(Vector3.new(1, wallHeight, width + 12), Color3.fromRGB(206, 226, 246), Enum.Material.SmoothPlastic)
		plane.Transparency = fraction == 0.6 and 0.65 or 0.45
		plane:SetAttribute("AheadFraction", fraction)
		table.insert(corridorFog, plane)
	end
end

-- The corridor's opening stretch wears the active world's colours. Fed
-- from Cannon.update's world-change detection, beside the island repaint.
-- No repaint loop needed: the window pass paints every tile per frame from
-- the biome its distance lies in, and the first biome reads this theme.
function Flight.setWorld(world: { grass: Color3, grassDark: Color3, canyon: Color3 })
	corridorTheme.grass = world.grass
	corridorTheme.grassDark = world.grassDark
	corridorTheme.canyon = world.canyon
end

-- ---------- biomes ----------
-- The land changes as a flight gets far: Config.CorridorBiomes bands the
-- track by REAL distance, and the window pass below paints each tile from
-- the band its own distance lies in — so the desert scrolls in tile by
-- tile at 1K studs rather than the whole world blinking over at once.
type Biome = {
	at: number,
	name: string,
	emoji: string,
	floor: Color3?,
	floorAlt: Color3?,
	wall: Color3?,
	lip: Color3?,
	haze: Color3?,
}

local function biomeAt(d: number): Biome
	local biomes = Config.CorridorBiomes :: { Biome }
	local current = biomes[1]
	for _, biome in biomes do
		if d >= biome.at then
			current = biome
		end
	end
	return current
end

-- A biome's palette. The first band carries no colours of its own and
-- wears the active world's theme, so world unlocks still repaint the
-- opening stretch of every flight.
local function biomePalette(biome: Biome): (Color3, Color3, Color3, Color3)
	if biome.floor then
		return biome.floor :: Color3,
			biome.floorAlt or biome.floor :: Color3,
			biome.wall or biome.floor :: Color3,
			biome.lip or biome.floor :: Color3
	end
	return corridorTheme.grass, corridorTheme.grassDark, corridorTheme.canyon, corridorTheme.grassDark
end

-- The band the squishy is currently IN, for the "entering the desert!"
-- announcement the moment a new one starts scrolling underfoot.
local currentBiomeAt = 0

-- Ground-owned FX ride the treadmill: a splat must recede with the floor it
-- landed on, or it appears to glide forward against the scroll. Each entry
-- remembers its sim distance, lane and rotation; a per-frame pass reseats
-- them and drops the dead.
type TrackedFx = { part: BasePart, d: number, lane: number, up: number, rot: CFrame }
local trackedFx: { TrackedFx } = {}

local function trackFx(part: BasePart, d: number, lane: number, up: number)
	table.insert(trackedFx, {
		part = part,
		d = d,
		lane = lane,
		up = up,
		rot = part.CFrame.Rotation,
	})
end

-- Per-flight marker spacing: the 1/2.5/5 ladder of the shot's EXPECTED
-- distance (the real one doesn't exist until it lands).
local markerSpacing = 100

-- The ignition-to-corridor cut: the camera holds the barrel bang until this
-- clock, then hard-cuts once (a lerp would swoop nine thousand studs).
local cutAt = 0
local cutDone = true

-- ---------- the mid-air game's state ----------
-- Steering, boots, bombs and slams change the LOCAL sim — that is the whole
-- point now — but nothing they change PAYS until the server re-runs the
-- flight from the event log and agrees (see settleFlight, server-side).
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClaimFlightRemote = Remotes:WaitForChild("ClaimFlight") :: RemoteEvent

local steerPos = 0
local steerVel = 0 -- eased toward the input, so direction flips glide
local slamsUsed = 0
-- A slam is a real dive in the sim now; these only route its IMPACT back
-- to the FX: the next ground contact wears the ring, and a manual slam's
-- contact also bursts the nearby cash.
local slamFxPending = false
local slamManualPending = false
local flightEvents: { { [string]: any } } = {}
local flightSerial = 0
local claimSent = true

-- Touch: horizontal drag steers, a short tap slams.
local touchAt: number? = nil
local touchTravel = 0
local touchBegan = 0

-- The character's own controls, borrowed while a shot is being steered:
-- A/D belongs to the squishy mid-flight and SPACE is a slam, not a jump —
-- without this the character sprinted around the plot with every steer.
-- Returned when the camera hands back, so walking resumes exactly when the
-- view does. pcall'd because PlayerModule's internals are Roblox's to move.
local controlsBorrowed = false
local function borrowCharacterControls(borrow: boolean)
	if borrow == controlsBorrowed then
		return
	end
	controlsBorrowed = borrow
	local ok, controls = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any):GetControls()
	end)
	if ok and controls then
		if borrow then
			controls:Disable()
		else
			controls:Enable()
		end
	end
end

-- ---------- summoned squishies ----------
-- The squishies ARE the pets, and summoning one means it walks the island
-- with YOU — trailing the character, not decorating some stage. They used to
-- be built as followers of the clicker on the hidden diorama, which meant
-- pressing Summon visibly did nothing at all.
type Follower = { model: Models.SquishyModel, scale: number, radius: number, position: Vector3, velocity: Vector3 }
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
			-- Personal space, in studs at the applied summon scale: how close
			-- another summon's centre may come before the two are clipping.
			-- The formation and the separation pass below both read this.
			radius = 2.4 * (spec.sizeScale or 1),
			-- Seeded at the player so a fresh summon walks out from them
			-- rather than sprinting in from the world origin.
			position = seed - Vector3.new(index * 3, 0, 0),
			velocity = Vector3.zero,
		})
	end
end

-- (The arc-sampling curve is gone: the flight is stepped live through
-- shared/Track, the same integrator the server settles with.)

-- ---------- drawing the track ----------
-- Chunk entries stay in SIM space; the window pass below borrows a pooled
-- part for whatever is near the flown distance and hands it back on the
-- way out. The *Base tables keep their old contract — "base exists =
-- currently drawn" — now keyed by entry id.

-- Dressing runs ONCE per assignment, not per frame: mesh sizing, VIP
-- tinting, and which face the cash icon wears. A real cash-stack model
-- keeps its own paint (VIPs just come bigger) and needs no floating marker
-- except the 💰 jackpot flag; the fallback blocks get the tint-and-resize
-- treatment and the full billboard.
local function stylePickup(part: BasePart, entry: Track.Pickup)
	local meshBase = part:GetAttribute("MeshBase") :: Vector3?
	if meshBase then
		part.Size = meshBase * (entry.vip and 1.6 or 1)
	else
		part.Color = entry.vip and VIP_GOLD or (PICKUP_LOOK[entry.kind] or PICKUP_LOOK.coin)
		part.Size = Vector3.one * (entry.vip and 9 or 5.5)
	end
	local icon = part:FindFirstChild("CashIcon") :: BillboardGui?
	if icon then
		local useImage = Config.CashIconImage ~= "" and not entry.vip and meshBase == nil
		local face = icon:FindFirstChildOfClass("TextLabel")
		local pic = icon:FindFirstChild("Pic") :: ImageLabel?
		if pic then
			pic.Visible = useImage
		end
		if face then
			face.Visible = not useImage
			face.Text = entry.vip and "💰" or "💵"
		end
		icon.Enabled = meshBase == nil or entry.vip
	end
end

-- Boots and bombs come pre-dressed from their pools; assignment only has
-- to light the glyph back up.
local function styleExtra(part: BasePart, _entry: any)
	local glyph = part:FindFirstChild("Glyph") :: BillboardGui?
	if glyph then
		glyph.Enabled = true
	end
end

-- One pass per kind: release what slid out of the window, borrow-and-dress
-- for what slid in, then seat, bob and spin everything on show. Only runs
-- while a shot is flying or resting — between shots the corridor is empty
-- and the track with it.
local function drawTrackObjects(idleClock: number)
	local ahead = Config.CorridorViewAhead
	local behind = Config.CorridorViewBehind
	local firstChunk = math.max(Track.chunkAt(shot.flown - behind), 0)
	local lastChunk = Track.chunkAt(shot.flown + ahead)

	local function seatKind(
		alloc: Allocator,
		dead: { [number]: boolean },
		bases: { [number]: Vector3 },
		listOf: (Track.Chunk) -> { any },
		style: (BasePart, any) -> (),
		spinSpeed: number,
		bobSpeed: number,
		fallbackTransparency: number
	)
		local wanted: { [number]: any } = {}
		for index = firstChunk, lastChunk do
			for _, entry in listOf(chunkFor(index)) do
				if
					not dead[entry.id]
					and entry.distance > shot.flown - behind
					and entry.distance < shot.flown + ahead
				then
					wanted[entry.id] = entry
				end
			end
		end
		for id in pairs(alloc.assign) do
			if wanted[id] == nil then
				releaseEntry(alloc, bases, id)
			end
		end
		for id, entry in pairs(wanted) do
			local part = alloc.assign[id]
			if part == nil then
				part = table.remove(alloc.free)
				if part then
					alloc.assign[id] = part
					style(part, entry)
				end
			end
			if part then
				-- Seated no lower than its own half-height plus bob room: a
				-- ground-line entry RESTS on the floor instead of sinking
				-- through it — the cartoon bombs used to sit buried to the
				-- fuse, because "height 2" meant the CENTRE of an 8-stud part.
				local rest = math.max(entry.height, part.Size.Y * 0.5 + 1)
				local base = corridorAt(entry.distance, 0)
					+ Vector3.new(0, rest, 0)
					+ SIDE * laneToStuds(entry.lane)
				bases[id] = base
				part.Transparency = if part:GetAttribute("MeshBase") then 0 else fallbackTransparency
				part.CFrame = CFrame.new(base + Vector3.new(0, math.sin(idleClock * bobSpeed + id * 0.7) * 0.7, 0))
					* CFrame.Angles(0, idleClock * spinSpeed + id * 0.5, 0)
			end
		end
	end

	seatKind(pickupAlloc, pickupTaken, pickupBase, function(chunk)
		return chunk.pickups :: any
	end, stylePickup :: any, 1.4, 2.2, 0.1)
	seatKind(bootAlloc, bootTaken, bootBase, function(chunk)
		return chunk.boots :: any
	end, styleExtra, 1.8, 2.6, 0)
	seatKind(bombAlloc, bombHit, bombBase, function(chunk)
		return chunk.bombs :: any
	end, styleExtra, 0.8, 1.6, 0)
end

-- ---------- public ----------

-- The plot to fire from. The direction is straight out from the island's
-- centre, which is the way every plot's cannon already points.
function Flight.setPlot(centre: Vector3, plotFolder: Instance?)
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
	smokeAnchor.Position = muzzle :: Vector3

	-- The capsule dress-up runs DEFERRED. The plot attribute arrives ahead
	-- of the map's geometry — that race is the whole reason PlotCenter is
	-- an attribute — so a one-shot search here reliably ran before the
	-- capsule had replicated: no seat, no occupant, slime still on show.
	-- The badge takes its classic perch immediately; a poller then waits
	-- for a capsule model to land near the plot (matched by GEOMETRY, not
	-- folder — parents and positions can disagree after hand edits) and
	-- wires the seat, hides the slime, and lifts the badge to the crown.
	capsuleSeat = nil
	rebuildOccupant()
	stationAnchor.Position = centre - flat.Unit * STATION_BACK + Vector3.new(0, CAPSULE_ICON_HEIGHT, 0)
	capsuleToken += 1
	local token = capsuleToken
	local plotsFolder = plotFolder and plotFolder.Parent
	if plotsFolder then
		task.spawn(function()
			for _ = 1, 60 do
				if token ~= capsuleToken then
					return -- a newer plot adoption owns the capsule now
				end
				local capsule: Model? = nil
				local bestAway = 40
				for _, descendant in plotsFolder:GetDescendants() do
					if descendant:IsA("Model") and descendant.Name:lower():find("capsule", 1, true) then
						local pivot = descendant:GetPivot().Position
						local away = Vector3.new(pivot.X - flat.X, 0, pivot.Z - flat.Z).Magnitude
						if away < bestAway then
							bestAway = away
							capsule = descendant
						end
					end
				end
				if capsule then
					local boundsCF, boundsSize = capsule:GetBoundingBox()
					-- A model whose parts haven't replicated yet measures
					-- zero; keep waiting for the real thing.
					if boundsSize.Magnitude > 1 then
						local floorY = boundsCF.Position.Y - boundsSize.Y * 0.5
						capsuleSeat = Vector3.new(boundsCF.Position.X, floorY + boundsSize.Y * 0.14, boundsCF.Position.Z)
						capsuleHeight = boundsSize.Y * 0.42
						stationAnchor.Position = boundsCF.Position + Vector3.new(0, boundsSize.Y * 0.5 + 2.5, 0)

						local slime = findLoose(capsule, "slime")
						if slime then
							if slime:IsA("BasePart") then
								slime.LocalTransparencyModifier = 1
							end
							for _, part in slime:GetDescendants() do
								if part:IsA("BasePart") then
									part.LocalTransparencyModifier = 1
								end
							end
						end
						rebuildOccupant()
						return
					end
				end
				task.wait(0.5)
			end
		end)
	end
end

function Flight.setSquishy(shape: string?, color: Color3, sparkle: boolean, sizeScale: number?)
	modelSpec = { shape = shape, color = color, sparkle = sparkle, scale = sizeScale or 1 }
	if model then
		model.rig.folder:Destroy()
	end
	-- Built NOW rather than lazily on the first shot: between shots this
	-- model sits loaded in the cannon's scoop, so it has to exist the moment
	-- a squishy is equipped, not the moment one is fired.
	model = Models.buildSquishy(stage, modelSpec.shape, modelSpec.color, modelSpec.sparkle, modelSpec.scale)

	-- And both capsule displays swap with it: the badge portrait above the
	-- glass, and the one standing inside it.
	refreshStationIcon()
	rebuildOccupant()
end

-- (Flight.setField and the field bundle are gone: there is no field to
-- push. The seed in each LaunchResult IS the track, generated locally.)

-- ---------- impact FX ----------

-- A paint splat where the squishy hit, tinted its own colour, spreading and
-- fading off the grass. Created per impact rather than pooled: a flight makes
-- at most a dozen, and each destroys itself.
-- Returns the disc, so callers can hand it to the treadmill tracker.
local function splat(at: Vector3, radius: number): BasePart
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
	return disc
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

-- A pickup visually taken by the flight (steer-through, magnet vacuum or
-- slam burst). Payment is the server's — the settlement covers it — this
-- is only the pop the eye needs at the moment of touch. Combos count for
-- SKILL takes only: the magnet's passive sweeps stay quiet.
local function takePickupVisual(entry: Track.Pickup, skill: boolean)
	pickupTaken[entry.id] = true
	local part = pickupAlloc.assign[entry.id]
	local popAt = if part
		then part.Position
		else corridorAt(entry.distance, math.max(entry.height, 2)) + SIDE * laneToStuds(entry.lane)
	releaseEntry(pickupAlloc, pickupBase, entry.id)
	floatPopup(popAt, ("+$%d"):format(entry.value), PICKUP_LOOK[entry.kind] or PICKUP_LOOK.coin)

	if skill then
		-- The combo: quick successive grabs count up, announce from three,
		-- and the ping climbs with them — a run through a cash line makes
		-- a little ascending scale.
		local now = os.clock()
		comboCount = if now - comboAt <= 1.25 then comboCount + 1 else 1
		comboAt = now
		if comboCount >= 3 then
			floatPopup(popAt + Vector3.new(0, 6, 0), ("COMBO x%d!"):format(comboCount), Color3.fromRGB(255, 214, 120))
		end
		comboPing.PlaybackSpeed = math.min(0.9 + comboCount * 0.09, 2.2)
		comboPing:Play()
	end
end

-- A quick dark puff for a bomb connecting.
-- Returns the anchor, so the treadmill tracker can carry the puff along.
local function boomFx(at: Vector3): BasePart
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = at
	anchor.Parent = stage

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 66, 62))
	smoke.Lifetime = NumberRange.new(0.4, 0.8)
	smoke.Speed = NumberRange.new(10, 22)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Size = NumberSequence.new(3, 7)
	smoke.Enabled = false
	smoke.Parent = anchor
	smoke:Emit(24)
	task.delay(1.4, function()
		anchor:Destroy()
	end)
	return anchor
end

-- The dive: a REAL slam in the sim now — vertical speed forced hard
-- downward, the impact handled like any other ground contact. Spends a
-- limited stock; the burst and the ring fire where the sim actually lands.
local function beginSlam()
	local live = sim
	if not live or live.done or live.rolling or slamFxPending or not shot.active then
		return
	end
	if slamsUsed >= Config.SlamMaxPerFlight then
		return
	end
	slamsUsed += 1
	slamFxPending = true
	slamManualPending = true
	table.insert(flightEvents, { kind = "slam", t = live.t, lane = steerPos })
	Track.slam(live)
end

-- What a slam's burst reaches, mirrored from the server's own formula as
-- closely as the moment allows. The server's radius scales with the FINAL
-- distance, unknown mid-flight, so this draws with the running distance —
-- the settlement can only pay MORE than what pops here.
local function slamBurst(atDistance: number, lane: number)
	local radius = math.clamp(shot.flown * Config.SlamRadiusFraction, Config.SlamRadiusMin, Config.SlamRadiusMax)
	local fromChunk = math.max(Track.chunkAt(atDistance - radius), 0)
	for chunkIndex = fromChunk, Track.chunkAt(atDistance + radius) do
		for _, entry in chunkFor(chunkIndex).pickups do
			if
				not pickupTaken[entry.id]
				and math.abs(entry.distance - atDistance) <= radius
				and math.abs(entry.lane - lane) <= Config.SlamLaneRadius
			then
				takePickupVisual(entry, false)
			end
		end
	end
end

-- ---------- mid-air input ----------
-- Keyboard steering is read per-frame in the loop; these are the taps.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space and shot.active then
		beginSlam()
	elseif input.UserInputType == Enum.UserInputType.Touch and shot.active then
		touchAt = input.Position.X
		touchTravel = 0
		touchBegan = os.clock()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch or touchAt == nil then
		return
	end
	local dx = input.Position.X - (touchAt :: number)
	touchAt = input.Position.X
	touchTravel += math.abs(dx)
	-- The finger is a position control and already smooth; the eased
	-- keyboard velocity stands down so the two never fight.
	steerVel = 0
	steerPos = math.clamp(steerPos + dx * 0.06, -Config.SteerHalfWidth, Config.SteerHalfWidth)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Touch or touchAt == nil then
		return
	end
	touchAt = nil
	-- A press that never travelled is a tap, and a tap is a slam.
	if touchTravel < 10 and os.clock() - touchBegan < 0.35 then
		beginSlam()
	end
end)

function Flight.play(plan: {
	serial: number?,
	seed: number,
	vx: number,
	vy: number,
	gravity: number,
	restitution: number,
	bounceFriction: number,
	minBounceSpeed: number,
	rollSeconds: number,
	endSpeed: number,
	maxSeconds: number,
	expected: number,
	magnet: number?,
	milestones: { { name: string, at: number, cash: number } }?,
}): number
	if not muzzle then
		-- Should be impossible once a plot is claimed, so if it ever happens
		-- it must say so in the Output rather than fail as a blank screen.
		warn("[SquishyClicker] Launch with no plot adopted — nothing to draw the flight from.")
		return 0
	end

	-- The living sim, from the server's own numbers. No distance in the
	-- payload — there isn't one until this lands.
	sim = Track.newSim(plan.vx, plan.vy, {
		gravity = plan.gravity,
		restitution = plan.restitution,
		bounceFriction = plan.bounceFriction,
		minBounceSpeed = plan.minBounceSpeed,
		rollSeconds = plan.rollSeconds,
		endSpeed = plan.endSpeed,
		maxSeconds = plan.maxSeconds,
	})

	-- The whole track resets to this shot's seed: fresh chunks, fresh
	-- taken-sets, every pooled part back in its pool.
	trackSeed = plan.seed
	table.clear(chunkCache)
	releaseAll(pickupAlloc, pickupBase)
	releaseAll(bootAlloc, bootBase)
	releaseAll(bombAlloc, bombBase)
	table.clear(pickupTaken)
	table.clear(bootTaken)
	table.clear(bombHit)

	shot.flown, shot.height, shot.speed, shot.bounced = 0, 0, 0, 0
	shot.active = true
	-- A floor under the camera's tenancy until the landing sets the real
	-- lease; the flying flag is what actually holds it open.
	shot.holdUntil = os.clock() + 3
	shot.launchSpeed = math.max(plan.vx, 1)
	shot.expected = math.max(plan.expected, 100)
	shotMagnet = plan.magnet or 0
	lastBounceSeen = 0
	landingDone = false
	fovKick = 0
	shakeAmp = 0

	-- Spin leaves the barrel with the shot: a harder launch tumbles faster.
	spinAngle = 0
	spinRate = math.pi * 5 * math.clamp(shot.launchSpeed / 260, 0.7, 1.8)
	squash = 0

	-- The character stands down while the squishy takes the controls.
	borrowCharacterControls(true)

	-- The camera opens ON the barrel for the ignition beat, then hard-cuts
	-- to the corridor once — set here, honored in the camera block. A lerp
	-- across the nine thousand studs to the corridor would read as a swoop
	-- through the sky, which is why the cut is a cut.
	local from = muzzle :: Vector3
	camEye = from - outward * 6 + Vector3.new(0, 5, 0)
	camLook = from + outward * 40
	cutAt = os.clock() + Config.CorridorCutDelay
	cutDone = false

	-- The corridor dresses for this flight: marker spacing on the 1/2.5/5
	-- ladder of the EXPECTED distance (the real one doesn't exist yet — a
	-- great run simply sails past more numbers), stale tracked FX purged,
	-- and marker slots forced to relabel.
	markerSpacing = niceStep(shot.expected / Config.CorridorMarkerCount)
	for _, fx in trackedFx do
		if fx.part.Parent then
			fx.part:Destroy()
		end
	end
	table.clear(trackedFx)
	for _, marker in corridorMarkers do
		marker.index = -1
	end

	-- The mid-air game resets with the shot.
	flightSerial = plan.serial or 0
	flightEvents = {}
	claimSent = false
	steerPos = 0
	steerVel = 0
	slamsUsed = 0
	slamFxPending = false
	slamManualPending = false
	touchAt = nil
	currentBiomeAt = 0

	-- The milestones this account has NOT yet earned, straight from the
	-- server with their positions — the popup fires at the sign the moment
	-- the flight actually crosses it.
	pendingMilestones = {}
	for _, milestone in plan.milestones or {} do
		table.insert(pendingMilestones, {
			at = milestone.at,
			text = ("🏁 %s Studs!  +%s 💵"):format(milestone.name, Format.abbreviate(milestone.cash)),
		})
	end

	if not model then
		model = Models.buildSquishy(stage, modelSpec.shape, modelSpec.color, modelSpec.sparkle, modelSpec.scale)
	end

	-- The BANG. Ignition should be the biggest frame of the whole flight:
	-- a fat smoke wall, a flash that lights the plot, a deep thump and a
	-- camera jolt, all in the same instant the squishy leaves.
	comboCount = 0
	bombNear = {}
	muzzleSmoke:Emit(46)
	launchBoom.PlaybackSpeed = 0.38 + math.random() * 0.08
	launchBoom:Play()
	shakeAmp = Config.ImpactShakeMagnitude * 0.8
	shakePhase = 0

	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.one * 3
	flash.Position = from + outward * 2
	flash.Color = Color3.fromRGB(255, 236, 160)
	flash.Material = Enum.Material.Neon
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Parent = stage
	local glare = Instance.new("PointLight")
	glare.Brightness = 6
	glare.Range = 34
	glare.Color = flash.Color
	glare.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * 13,
		Transparency = 1,
	}):Play()
	TweenService:Create(glare, TweenInfo.new(0.28), { Brightness = 0 }):Play()
	task.delay(0.35, function()
		flash:Destroy()
	end)

	-- No duration to promise: the flight lasts as long as it stays alive.
	-- Launch watches Flight.flying() for the landing instead.
	return 0
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
-- True from ignition to landing. Launch's landing watch reads this: when
-- it flips false, the settlement (FlightBonus) is what arrives next.
function Flight.flying(): boolean
	return shot.active
end

-- ---------- the loop ----------

RunService.RenderStepped:Connect(function(dt)
	local toy = model
	local live = sim
	local flying = shot.active and live ~= nil and not live.done
	-- Where the shot was at the top of the frame: touches are judged by
	-- CROSSING an entry's distance, so a fast segment that passes a whole
	-- cluster in one frame still counts every member it swept.
	local flownBefore = shot.flown
	-- Any ground contact this frame (a fast frame can hold several sim
	-- steps); the impact FX below read this.
	local hitThisFrame = false

	if shot.active and live then
		-- The live step: substepped so the physics stay stable at any frame
		-- rate, capped so a tab-out can't fast-forward the flight in one
		-- giant leap.
		local remaining = math.min(dt, 0.25)
		while remaining > 0 and not live.done do
			local step = math.min(remaining, 1 / 60)
			Track.step(live, step)
			if live.hitGround then
				hitThisFrame = true
			end
			remaining -= step
		end
		shot.flown = live.dist
		shot.height = live.h
		shot.speed = live.vx
		shot.bounced = live.bounced

		if live.done then
			-- The flight ran out of speed: THAT is the landing. Settle the
			-- claim — the server re-runs everything from these events and
			-- FlightBonus brings back the verdict.
			shot.active = false
			shot.holdUntil = os.clock() + 1.6
			if not claimSent then
				claimSent = true
				ClaimFlightRemote:FireServer(flightSerial, flightEvents)
			end
		end
	end

	if flying then
		-- Keyboard steering, read fresh each frame: A / D or the arrows.
		-- EASED, not instant: the velocity chases the keys, so direction
		-- flips glide instead of kinking — which is most of what "smooth"
		-- means at these speeds.
		local steerInput = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
			steerInput -= 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
			steerInput += 1
		end
		local targetVel = steerInput * Config.SteerSpeed
		steerVel += (targetVel - steerVel) * math.min(dt * 9, 1)
		steerPos += steerVel * dt
		if steerPos >= Config.SteerHalfWidth then
			steerPos = Config.SteerHalfWidth
			steerVel = math.min(steerVel, 0)
		elseif steerPos <= -Config.SteerHalfWidth then
			steerPos = -Config.SteerHalfWidth
			steerVel = math.max(steerVel, 0)
		end
	end

	-- A slam's IMPACT: the dive itself is the sim's (Track.slam forced the
	-- vertical speed), so the FX fire at the real ground contact — ring,
	-- squash, thock, and the manual burst.
	if hitThisFrame and slamFxPending then
		slamFxPending = false
		local ground = corridorAt(shot.flown, 0) + SIDE * laneToStuds(steerPos)
		trackFx(splat(ground, Config.LaunchSplatRadius * 0.9), shot.flown, steerPos, 0.4)
		squash = 1
		shakeAmp = Config.ImpactShakeMagnitude
		shakePhase = 0
		fovKick = 1
		bounceThock.PlaybackSpeed = 0.45
		bounceThock:Play()

		-- The shockwave: a white ring racing out from the impact, which
		-- is what sells the slam as a HIT rather than a fast descent.
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.4, 6, 6)
		ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Color = Color3.fromRGB(255, 255, 255)
		ring.Material = Enum.Material.Neon
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Transparency = 0.2
		ring.Parent = stage
		trackFx(ring, shot.flown, steerPos, 0.6)
		TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.4, 44, 44),
			Transparency = 1,
		}):Play()
		task.delay(0.5, function()
			ring:Destroy()
		end)
		if slamManualPending then
			slamManualPending = false
			floatPopup(ground + Vector3.new(0, 8, 0), "💥 SLAM!", Color3.fromRGB(255, 214, 120))
			slamBurst(shot.flown, steerPos)
		end
	end

	-- Where the squishy actually draws: at the treadmill's origin, at the
	-- LIVE sim's own height — boots, bombs and slams are all already in it
	-- — and steered sideways across the fixed lane.
	local at = corridorAt(shot.flown, shot.height) + SIDE * laneToStuds(steerPos)

	-- The corridor itself: tiles, walls and marker boards wrap through the
	-- window by modulo, so the same pooled parts carry every distance.
	if flying or os.clock() < shot.holdUntil then
		local tileLength = Config.CorridorTileLength
		local width = Config.CorridorFloorWidth
		local wallHeight = Config.CorridorWallHeight
		local firstTile = math.floor((shot.flown - Config.CorridorViewBehind) / tileLength)
		local lastTile = math.floor((shot.flown + Config.CorridorViewAhead) / tileLength)
		for tileIndex = firstTile, lastTile do
			local slot = (tileIndex % CORRIDOR_POOL) + 1
			local tile = corridorTiles[slot]
			local centreD = (tileIndex + 0.5) * tileLength
			local base = corridorAt(centreD, 0)
			-- Painted from the biome THIS tile's distance lies in, so a new
			-- land scrolls in tile by tile across its boundary.
			local floorA, floorB, wallColor, lipColor = biomePalette(biomeAt(centreD))
			tile.Color = tileIndex % 2 == 0 and floorA or floorB
			tile.CFrame = CFrame.new(base - Vector3.new(0, 1, 0))
			local walls = corridorWalls[slot]
			walls.left.Color = wallColor
			walls.right.Color = wallColor
			walls.leftLip.Color = lipColor
			walls.rightLip.Color = lipColor
			walls.left.CFrame = CFrame.new(base + SIDE * (-width / 2 - 3) + Vector3.new(0, wallHeight / 2, 0))
			walls.right.CFrame = CFrame.new(base + SIDE * (width / 2 + 3) + Vector3.new(0, wallHeight / 2, 0))
			walls.leftLip.CFrame = CFrame.new(base + SIDE * (-width / 2 - 3) + Vector3.new(0, wallHeight + 2, 0))
			walls.rightLip.CFrame = CFrame.new(base + SIDE * (width / 2 + 3) + Vector3.new(0, wallHeight + 2, 0))
		end

		local firstMarker = math.max(math.floor((shot.flown - Config.CorridorViewBehind) / markerSpacing), 1)
		-- Never more markers in the window than the pool holds — on a short
		-- shot the ladder bottoms out at 25-stud spacing, and an uncapped
		-- window would fold two distances onto one pooled panel.
		local lastMarker = math.min(
			math.floor((shot.flown + Config.CorridorViewAhead) / markerSpacing),
			firstMarker + CORRIDOR_POOL - 1
		)
		for markerIndex = firstMarker, lastMarker do
			local slot = (markerIndex % CORRIDOR_POOL) + 1
			local marker = corridorMarkers[slot]
			local d = markerIndex * markerSpacing
			local base = corridorAt(d, 0)
			-- Flat on the road, yawed so the gui's up axis runs down-track:
			-- the number reads right-way-up as the squishy flies toward it,
			-- exactly like paint on a runway.
			marker.panel.CFrame = CFrame.new(base + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, -math.pi / 2, 0)
			if marker.index ~= markerIndex then
				-- Relabel only on slot reuse: TextLabel writes are not free.
				marker.index = markerIndex
				marker.label.Text = Format.abbreviate(d)
			end
		end

		-- The static depth dressing rides at fixed offsets from the origin,
		-- hazed in the colour of the biome it is looking INTO — desert air
		-- ahead of the desert, the near-black of space ahead of space.
		local hazeBiome = biomeAt(shot.flown + Config.CorridorViewAhead)
		local haze = hazeBiome.haze or Color3.fromRGB(206, 226, 246)
		corridorCap.Color = haze
		corridorCap.CFrame = CFrame.new(
			CORRIDOR_ORIGIN + FORWARD * Config.CorridorViewAhead + Vector3.new(0, wallHeight / 2, 0)
		)
		for _, plane in corridorFog do
			local fraction = plane:GetAttribute("AheadFraction") :: number
			plane.Color = haze
			plane.CFrame = CFrame.new(
				CORRIDOR_ORIGIN + FORWARD * (Config.CorridorViewAhead * fraction) + Vector3.new(0, wallHeight / 2, 0)
			)
		end

		-- And everything the shot can touch, seated in the same window.
		drawTrackObjects(os.clock())
	end

	-- Ground-owned FX ride the treadmill: reseat every tracked part at its
	-- remembered distance and lane, drop what has died or fallen behind.
	for index = #trackedFx, 1, -1 do
		local fx = trackedFx[index]
		if fx.part.Parent == nil or fx.d < shot.flown - Config.CorridorViewBehind - 40 then
			table.remove(trackedFx, index)
		else
			fx.part.CFrame = CFrame.new(
				corridorAt(fx.d, 0) + SIDE * laneToStuds(fx.lane) + Vector3.new(0, fx.up, 0)
			) * fx.rot
		end
	end

	-- Steering through things: whatever the sim touches, the claim
	-- remembers — with when and where, because the server re-runs the whole
	-- flight from this log. Judged in LANE UNITS and by crossing, never
	-- world proximity, and against the CHUNKS the frame swept rather than
	-- the drawn window: a fast segment can cross more track in one frame
	-- than the window even shows.
	if flying and toy and live then
		local laneTouch = Config.LaneTouchWidth
		local function crossed(distance: number): boolean
			return distance > flownBefore and distance <= shot.flown
		end
		local function popPosition(entry: any): Vector3
			return corridorAt(entry.distance, math.max(entry.height, 2)) + SIDE * laneToStuds(entry.lane)
		end

		for chunkIndex = Track.chunkAt(flownBefore), Track.chunkAt(shot.flown) do
			local chunk = chunkFor(chunkIndex)
			for _, entry in chunk.pickups do
				if not pickupTaken[entry.id] and crossed(entry.distance) then
					if math.abs(entry.lane) <= shotMagnet then
						-- The magnet's vacuum: no event — the server pays
						-- every centre-line pickup along the settled
						-- distance without being asked.
						takePickupVisual(entry, false)
					elseif
						math.abs(entry.lane - steerPos) <= laneTouch
						and math.abs(entry.height - shot.height) <= 16
					then
						takePickupVisual(entry, true)
						table.insert(flightEvents, { kind = "pickup", id = entry.id, t = live.t, lane = steerPos })
					end
				end
			end
			for _, entry in chunk.boots do
				if
					not bootTaken[entry.id]
					and crossed(entry.distance)
					and math.abs(entry.lane - steerPos) <= laneTouch
					and math.abs(entry.height - shot.height) <= 15
				then
					bootTaken[entry.id] = true
					local base = bootBase[entry.id] or popPosition(entry)
					releaseEntry(bootAlloc, bootBase, entry.id)
					-- The relaunch is REAL: the sim's vertical speed comes
					-- back and the flight simply keeps going. This is the
					-- whole point of the boots.
					Track.boot(live)
					bootSound.PlaybackSpeed = 1 + 0.1 * (#flightEvents % 5)
					bootSound:Play()
					floatPopup(base, "+BOOST!", Color3.fromRGB(120, 244, 128))
					table.insert(flightEvents, { kind = "boot", id = entry.id, t = live.t, lane = steerPos })
				end
			end
			for _, entry in chunk.bombs do
				-- Sailing close PAST a bomb earns a once-per-bomb "phew!" —
				-- the near-miss is half of why dodging feels like anything.
				if
					not bombHit[entry.id]
					and not bombNear[entry.id]
					and crossed(entry.distance)
					and math.abs(entry.lane - steerPos) > laneTouch
					and math.abs(entry.lane - steerPos) <= laneTouch * 2.4
				then
					bombNear[entry.id] = true
					floatPopup(popPosition(entry) + Vector3.new(0, 6, 0), "phew!", Color3.fromRGB(255, 240, 150))
				end
				if
					not bombHit[entry.id]
					and crossed(entry.distance)
					and math.abs(entry.lane - steerPos) <= laneTouch
					and math.abs(entry.height - shot.height) <= 15
				then
					bombHit[entry.id] = true
					local base = bombBase[entry.id] or popPosition(entry)
					releaseEntry(bombAlloc, bombBase, entry.id)
					-- The hit is REAL: forward speed bled and the body
					-- knocked down, in the same sim the server will re-run.
					Track.bomb(live)
					boomFx(base)
					bounceThock.PlaybackSpeed = 0.5
					bounceThock:Play()
					floatPopup(base, "-BOOM!", Color3.fromRGB(255, 110, 92))
					spinRate *= 0.55
					fovKick = 1
					shakeAmp = Config.ImpactShakeMagnitude
					shakePhase = 0
					table.insert(flightEvents, { kind = "bomb", id = entry.id, t = live.t, lane = steerPos })
				end
			end
		end
	end

	-- Impact FX. A splat per skip and a snap of the camera's FOV; a bigger
	-- splat plus the payout popup once, at the point of rest. landingDone
	-- starts true, so none of this can fire before the first real flight.
	local impactStrength = math.clamp(shot.speed / shot.launchSpeed, 0, 1)
	if flying and shot.bounced > lastBounceSeen then
		lastBounceSeen = shot.bounced
		fovKick = 1
		trackFx(
			splat(corridorAt(shot.flown, 0) + SIDE * laneToStuds(steerPos), Config.LaunchSplatRadius * 0.7),
			shot.flown,
			steerPos,
			0.4
		)
		-- Re-kick the shake oscillator, scaled by how fast the hit was.
		shakeAmp = Config.ImpactShakeMagnitude * (0.4 + 0.6 * impactStrength)
		shakePhase = 0
		-- The hit buys squash. (Spin is no longer bled here — the tumble
		-- re-grips the ground speed at every contact in the toy block below.)
		squash = 0.5 + 0.5 * impactStrength
		-- And a knock you can HEAR, pitched by how hard it landed — the
		-- skips make a decelerating drum line down the range.
		bounceThock.PlaybackSpeed = 0.55 + impactStrength * 0.55
		bounceThock:Play()
	elseif not flying and not landingDone then
		landingDone = true
		fovKick = 1
		shakeAmp = Config.ImpactShakeMagnitude
		shakePhase = 0
		-- The treadmill has stopped (the sim is done), so the landing FX
		-- sit still on their own — but they register with the tracker
		-- anyway, in case a later system ever moves the window at rest.
		-- The popup announces the DISTANCE only: what it earned is the
		-- server's verdict, still in flight to the summary card.
		local ground = corridorAt(shot.flown, 0) + SIDE * laneToStuds(steerPos)
		trackFx(splat(ground, Config.LaunchSplatRadius), shot.flown, steerPos, 0.4)
		payoutPopup(ground, shot.flown, 0)
		bounceThock.PlaybackSpeed = 0.42
		bounceThock:Play()

		-- Confetti at the point of rest: the flight earns a little party at
		-- the end, scaled by nothing — every landing deserves one.
		local party = Instance.new("Part")
		party.Size = Vector3.one
		party.Transparency = 1
		party.Anchored = true
		party.CanCollide = false
		party.CanQuery = false
		party.CanTouch = false
		party.Position = ground + Vector3.new(0, 4, 0)
		party.Parent = stage
		local confetti = Instance.new("ParticleEmitter")
		confetti.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 140)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 220, 130)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 170, 255)),
		})
		confetti.Lifetime = NumberRange.new(0.7, 1.3)
		confetti.Speed = NumberRange.new(18, 34)
		confetti.SpreadAngle = Vector2.new(70, 70)
		confetti.Rotation = NumberRange.new(0, 360)
		confetti.RotSpeed = NumberRange.new(-240, 240)
		confetti.Size = NumberSequence.new(1.4, 0.6)
		confetti.Enabled = false
		confetti.Parent = party
		confetti:Emit(42)
		trackFx(party, shot.flown, steerPos, 4)
		task.delay(1.8, function()
			party:Destroy()
		end)
		-- The full pancake, for the full stop.
		squash = 1
	end
	fovKick = math.max(fovKick - dt * 3, 0)
	shakePhase += dt

	-- The wind rides the shot, blowing BACKWARD down the corridor, and only
	-- draws at speed. -Z is the emitter's Back face, so aim it at +FORWARD.
	trailPart.CFrame = CFrame.lookAt(at, at - FORWARD)
	windTrail.Enabled = flying and impactStrength > Config.WindTrailMinSpeedFraction

	if toy then
		-- Much smaller than the old 5×: the squishy is a projectile, not a
		-- parade float, and at this size the lane, the pickups and the
		-- obstacles all read around it instead of underneath it.
		local applied = 2.6 * modelSpec.scale
		-- Tumbling about the axis PERPENDICULAR to the direction of travel
		-- (the outer `side`), so it somersaults forward whichever way the
		-- plot faces.
		--
		-- Impact deformation runs pancake THEN rebound: the damped cosine
		-- takes the shape from squashed flat through an overshoot into a
		-- tall stretch and back to rest — the rubbery plush read, in one
		-- curve instead of chained tweens. Volume roughly conserved either
		-- way: what the height loses or gains, the width gives back.
		squash = math.max(squash - dt * 5, 0)
		local deform = squash ^ 1.4 * math.cos((1 - squash) * 5)
		local scaleVec =
			Vector3.new(applied * (1 + 0.3 * deform), applied * (1 - 0.42 * deform), applied * (1 + 0.3 * deform))

		-- Stood on its UNDERSIDE like the summons — measured on the SQUASHED
		-- height, so a pancaked hit presses into the ground it is denting
		-- instead of hovering over it.
		local lift = -toy.lowestY * scaleVec.Y

		if flying then
			-- The somersault GRIPS the floor at every contact: the final
			-- roll locks to the treadmill's true ground speed like a wheel,
			-- and every skip re-spins the tumble toward that same rate
			-- (capped, or a six-figure flight would strobe). It used to only
			-- BLEED spin per bounce — ten skips into a long tail the tumble
			-- had all but stopped, and a ball skimming the floor in one
			-- frozen pose reads as gliding, never as hitting.
			local radiusWorld = math.max(-toy.lowestY * applied, 0.5)
			local groundRate = if dt > 0 then (shot.flown - flownBefore) / dt / radiusWorld else 0
			local rollingNow = live ~= nil and live.rolling
			if rollingNow then
				spinRate = groundRate
			elseif hitThisFrame then
				spinRate = math.clamp(groundRate, -math.pi * 10, math.pi * 10)
			end
			spinAngle += spinRate * dt

			Models.apply(
				toy.rig,
				CFrame.new(at + Vector3.new(0, lift, 0)) * CFrame.fromAxisAngle(SIDE, -spinAngle),
				scaleVec
			)
		elseif os.clock() < shot.holdUntil then
			-- Landed, camera still lingering: the squishy SITS where it
			-- stopped — pancaked from the landing, easing back to shape —
			-- instead of blinking out the frame the flight ends.
			local ground = corridorAt(shot.flown, 0) + SIDE * laneToStuds(steerPos)
			Models.apply(
				toy.rig,
				CFrame.new(ground + Vector3.new(0, lift, 0)) * CFrame.fromAxisAngle(SIDE, -spinAngle),
				scaleVec
			)
		else
			-- Parked between shots. The squishy briefly sat loaded on the
			-- cannon here, but on the real model it read as a pet standing on
			-- the barrel rather than as ammunition — cut on request. The
			-- squishy lives on the cushion and in the collection; the cannon
			-- carries it only mid-flight.
			Models.apply(toy.rig, CFrame.new(0, -500, 0), Vector3.one * 0.001)
		end
	end

	-- Entering a new biome announces itself the moment the new land starts
	-- scrolling underfoot — the flight's "you got somewhere" beat.
	if flying then
		local nowBiome = biomeAt(shot.flown)
		if nowBiome.at ~= currentBiomeAt then
			currentBiomeAt = nowBiome.at
			if nowBiome.at > 0 then
				floatPopup(
					at + Vector3.new(0, 16, 0),
					("%s  %s!"):format(nowBiome.emoji, nowBiome.name:upper()),
					nowBiome.lip or Color3.fromRGB(255, 220, 120)
				)
				comboPing.PlaybackSpeed = 0.7
				comboPing:Play()
			end
		end
	end

	-- Milestone popups fire on CROSSING, so their corridor position is right
	-- beside the squishy — exactly where the eye already is.
	if flying then
		for index = #pendingMilestones, 1, -1 do
			local milestone = pendingMilestones[index]
			if shot.flown >= milestone.at then
				floatPopup(
					corridorAt(milestone.at, 0) + Vector3.new(0, 16, 0),
					milestone.text,
					Color3.fromRGB(255, 220, 120)
				)
				table.remove(pendingMilestones, index)
			end
		end
	end

	-- The capsule occupant: the chosen squishy turning gently on its seat
	-- inside the pod's glass, scaled to the capsule that holds it.
	local sitting = occupant
	local seat = capsuleSeat
	if sitting and seat then
		local clock = os.clock()
		local span = math.max(sitting.highestY - sitting.lowestY, 0.5)
		local applied = capsuleHeight / span
		local lift = -sitting.lowestY * applied
		Models.apply(
			sitting.rig,
			CFrame.new(seat + Vector3.new(0, lift + math.sin(clock * 1.7) * 0.08, 0))
				* CFrame.Angles(0, clock * 0.9, 0),
			Vector3.one * applied
		)
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

		-- The wedge is spaced for the BIGGEST summon that is out: the old
		-- fixed offsets put three Giants in the same three studs and the
		-- team read as one fused blob.
		local spread = 0
		for _, follower in followers do
			spread = math.max(spread, follower.radius)
		end

		for index, follower in followers do
			local sideAmount = index == 2 and -1 or index == 3 and 1 or 0
			local target = characterRoot.Position
				- flatLook * (5 + index * (1 + spread * 0.5))
				+ right * (sideAmount * (2.5 + spread * 1.6))
			local pull = (target - follower.position) * FOLLOW_STIFFNESS - follower.velocity * FOLLOW_DAMPING
			follower.velocity += pull * dt
			follower.position += follower.velocity * dt
		end

		-- Formation spacing alone can't stop the melt: the springs steer all
		-- three through the same spot on a tight turn. Any overlapping pair
		-- is nudged apart along the line between their centres — positions
		-- only, velocities untouched, so the springs re-form the wedge
		-- smoothly instead of twanging off the correction.
		for a = 1, #followers do
			for b = a + 1, #followers do
				local first, second = followers[a], followers[b]
				local offset = Vector3.new(second.position.X - first.position.X, 0, second.position.Z - first.position.Z)
				local minGap = first.radius + second.radius
				local gap = offset.Magnitude
				if gap < minGap then
					local push = if gap > 0.05 then offset.Unit else flatLook
					local correction = push * (minGap - gap) * 0.5
					first.position -= correction
					second.position += correction
				end
			end
		end

		for index, follower in followers do
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

	-- The camera rides behind the shot and hands straight back afterwards.
	local camera = workspace.CurrentCamera
	if camera and (flying or os.clock() < shot.holdUntil) then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		-- The damped harmonic shake: an exponentially decaying sine, kicked
		-- by every impact, riding the eye in view space so it reads as the
		-- CAMERA being jolted rather than the world wobbling.
		local wobble = shakeAmp * math.exp(-Config.ImpactShakeDamping * shakePhase)
			* math.sin(shakePhase * math.pi * 2 * Config.ImpactShakeHz)
		local shakeOffset = Vector3.new(0, wobble, 0) + SIDE * wobble * 0.4

		if not cutDone and os.clock() < cutAt then
			-- The ignition beat: hold the barrel shot while the bang plays.
			-- camEye/camLook were seeded at the muzzle by play().
			camera.CFrame = CFrame.lookAt((camEye :: Vector3) + shakeOffset, camLook :: Vector3)
		else
			-- The corridor chase. On the first frame past the beat this is a
			-- HARD CUT — eye and aim assigned, not lerped, because a glide
			-- would swoop nine thousand studs through the open sky.
			-- The eye's lateral seat is clamped inside the walls, or a full
			-- steer plus the side offset would poke the camera through them.
			local eyeSide = math.clamp(
				laneToStuds(steerPos) + CHASE_SIDE,
				-(Config.CorridorFloorWidth / 2 - 8),
				Config.CorridorFloorWidth / 2 - 8
			)
			local targetEye = CORRIDOR_ORIGIN
				- FORWARD * CHASE_BACK
				+ Vector3.new(0, (at.Y - CORRIDOR_ORIGIN.Y) * 0.6 + CHASE_UP, 0)
				+ SIDE * eyeSide
			local targetLook = at + FORWARD * 20
			if not cutDone then
				cutDone = true
				camEye = targetEye
				camLook = targetLook
			else
				-- After the cut the glide returns: steering, boosts and
				-- slams all move the squishy sharply, and a camera bolted
				-- straight to it re-broadcasts every kink.
				local glide = 1 - math.exp(-dt * 10)
				camEye = (camEye :: Vector3):Lerp(targetEye, glide)
				camLook = (camLook :: Vector3):Lerp(targetLook, glide)
			end
			camera.CFrame = CFrame.lookAt((camEye :: Vector3) + shakeOffset, camLook :: Vector3)
		end
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
		camEye = nil
		camLook = nil
		-- The character gets its controls back the moment it gets its
		-- camera back — the two leaving and returning together is what
		-- makes the borrow invisible.
		borrowCharacterControls(false)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end)

return Flight
