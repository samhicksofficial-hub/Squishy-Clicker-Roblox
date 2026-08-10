--!strict
-- ============================================================
--  FLIGHT  —  the shot, drawn in a private endless corridor.
--
--  The bang happens at YOUR cannon on YOUR plot; a beat later the
--  camera cuts to a walled corridor that belongs to this client
--  alone, where the flight plays as a TREADMILL: the squishy stays
--  near a fixed origin and pooled floor tiles, canyon walls and
--  distance boards scroll past at true one-to-one studs. A board
--  reading "10K Studs" is ten thousand real simulated studs —
--  no log compression anywhere, and no far edge: indices are just
--  integers, so the corridor never ends.
--
--  Everything draws RELATIVE to the flown distance:
--      corridorAt(d, h) = ORIGIN + FORWARD * (d - shot.flown) + up
--  which is what makes a million-stud flight cost the same as a
--  hundred-stud one — the camera never actually goes anywhere.
--
--  Nothing here decides anything. The server simulates the flight
--  and sends its shape — every hop, its peak, its duration — and
--  this draws that shape onto the treadmill.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
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

type Arc = { fromX: number, toX: number, peak: number, seconds: number, rolling: boolean }

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

-- Parented to PLAYERGUI with the anchor as Adornee, not to the anchor
-- itself: a ViewportFrame inside a workspace-parented BillboardGui does not
-- reliably render its 3D scene — which is how the green ring shipped with
-- nothing inside it. Under PlayerGui the full GuiObject feature set applies.
local stationGui = Instance.new("BillboardGui")
stationGui.Name = "CapsuleBadge"
-- Stud-sized (the Scale component of a BillboardGui's Size is studs), not
-- pixel-sized: a pixel badge keeps the same screen size at any range, so
-- from across the plaza it loomed as large as the cannon itself. In studs
-- it shrinks with perspective like the pod it sits on.
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

-- Rebuild the icon's little 3D scene for the current squishy. Same recipe as
-- the collection icons: the real model, narrow lens from further back so the
-- shape reads cleanly at icon size.
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
type PickupEntry = { distance: number, height: number, kind: string, value: number, vip: boolean, lane: number? }
type BootEntry = { distance: number, height: number, lane: number, cash: number }
type BombEntry = { distance: number, height: number, lane: number }

local pickupParts: { BasePart } = {}
local pickupField: { PickupEntry } = {}
local pickupTaken: { [number]: boolean } = {}
local pickupCollecting: { [number]: number } = {}
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

-- Double the base count: headroom for the extra pickups VIP zones add.
-- (This line once multiplied by the Cash Rain density constant — reading a
-- REMOVED config key made it nil arithmetic, which killed this module at
-- require time and took the whole HUD down with it. Every button gone, no
-- error visible past the Output.)
local POOL = Config.LaunchPickupCount * 2 + Config.VipZoneCount * Config.VipZoneDensityMultiplier
for _ = 1, POOL do
	-- The imported cash-stack model when it exists; the neon block until.
	local prize = templatePart("cash", { "CashStack", "Cash" }, 4.2)
	if not prize then
		local block = Instance.new("Part")
		block.Size = Vector3.one * 4
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
for _ = 1, 4 do
	local boot = templatePart("boot", { "BoostBoot", "Boost" }, 5.2)
	if boot then
		boot.Parent = stage
		table.insert(bootParts, boot)
	else
		table.insert(
			bootParts,
			makeExtraPart(Enum.PartType.Block, 4.5, Color3.fromRGB(88, 232, 96), Enum.Material.Neon, "⬆️", 4)
		)
	end
end
for _ = 1, 14 do
	local bomb = templatePart("bomb", { "CartoonBomb", "Bomb" }, 5.4)
	if bomb then
		bomb.Parent = stage
		table.insert(bombParts, bomb)
	else
		table.insert(
			bombParts,
			makeExtraPart(Enum.PartType.Ball, 5, Color3.fromRGB(52, 52, 58), Enum.Material.SmoothPlastic, "💣", 3.6)
		)
	end
end

local bootField: { BootEntry } = {}
local bombField: { BombEntry } = {}
local bootBase: { [number]: Vector3 } = {}
local bombBase: { [number]: Vector3 } = {}
local bootTaken: { [number]: boolean } = {}
local bombHit: { [number]: boolean } = {}

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
-- term is always zero, and everything else slides past it.
local function corridorAt(d: number, simHeight: number): Vector3
	return CORRIDOR_ORIGIN + FORWARD * (d - shot.flown) + Vector3.new(0, simHeight * shot.heightScale, 0)
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
	part.Parent = corridorFolder
	return part
end

type MarkerSet = { stripe: BasePart, boards: { BasePart }, labels: { TextLabel }, index: number }

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
		local function wallPair(sideSign: number): (BasePart, BasePart)
			local wall = corridorPart(
				Vector3.new(tileLength, wallHeight, 6),
				corridorTheme.canyon,
				Enum.Material.Sandstone
			)
			local lip = corridorPart(Vector3.new(tileLength, 4, 8), corridorTheme.grassDark, Enum.Material.Plastic)
			lip.TopSurface = Enum.SurfaceType.Studs
			-- Positioned per-frame; sideSign only decides which side later.
			wall:SetAttribute("SideSign", sideSign)
			lip:SetAttribute("SideSign", sideSign)
			return wall, lip
		end
		local left, leftLip = wallPair(-1)
		local right, rightLip = wallPair(1)
		corridorWalls[index] = { left = left, right = right, leftLip = leftLip, rightLip = rightLip }

		-- A marker set: a bright stripe across the floor plus a number board
		-- on EACH wall (wall boards read at grazing angles where floor text
		-- disappears).
		local stripe = corridorPart(Vector3.new(3, 2.2, width), Color3.fromRGB(255, 244, 200), Enum.Material.Neon)
		local boards: { BasePart } = {}
		local labels: { TextLabel } = {}
		for _, sideSign in { -1, 1 } do
			local board = corridorPart(Vector3.new(2, 12, 30), Color3.fromRGB(56, 40, 32), Enum.Material.SmoothPlastic)
			board:SetAttribute("SideSign", sideSign)
			local surface = Instance.new("SurfaceGui")
			-- The inward face: left wall shows its right face and vice
			-- versa; both are the board's Z-normal faces after per-frame
			-- placement, so Front/Back split the two signs.
			surface.Face = sideSign == -1 and Enum.NormalId.Front or Enum.NormalId.Back
			surface.PixelsPerStud = 16
			surface.Parent = board
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.Text = ""
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
			label.TextStrokeTransparency = 0
			label.TextScaled = true
			label.Parent = surface
			table.insert(boards, board)
			table.insert(labels, label)
		end
		corridorMarkers[index] = { stripe = stripe, boards = boards, labels = labels, index = -1 }
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

-- The corridor wears the active world's colours. Fed from Cannon.update's
-- world-change detection, beside the island repaint.
function Flight.setWorld(world: { grass: Color3, grassDark: Color3, canyon: Color3 })
	corridorTheme.grass = world.grass
	corridorTheme.grassDark = world.grassDark
	corridorTheme.canyon = world.canyon
	for index, tile in corridorTiles do
		tile.Color = index % 2 == 0 and corridorTheme.grass or corridorTheme.grassDark
		local walls = corridorWalls[index]
		walls.left.Color = corridorTheme.canyon
		walls.right.Color = corridorTheme.canyon
		walls.leftLip.Color = corridorTheme.grassDark
		walls.rightLip.Color = corridorTheme.grassDark
	end
end

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

-- Per-flight marker spacing (the 1/2.5/5 ladder of the shot's distance) and
-- the precomputed draw heights that seat boots/bombs ON this flight's arc.
local markerSpacing = 100
local bootDrawHeight: { [number]: number } = {}
local bombDrawHeight: { [number]: number } = {}

-- The ignition-to-corridor cut: the camera holds the barrel bang until this
-- clock, then hard-cuts once (a lerp would swoop nine thousand studs).
local cutAt = 0
local cutDone = true

-- ---------- the mid-air game's state ----------
-- Steering and slamming change NOTHING the server has decided — distance,
-- the arc and the fire-time payout are already settled. What they change is
-- which off-lane things the replay touches, and that list is sent back as a
-- claim for the server to validate and price (see ClaimFlight server-side).
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClaimFlightRemote = Remotes:WaitForChild("ClaimFlight") :: RemoteEvent

local steerPos = 0
local steerVel = 0 -- eased toward the input, so direction flips glide
local slamsUsed = 0
local slamActive = false
local slamDrop = 0 -- 0 riding the arc, 1 pressed to the ground
local slamCollectAt: { distance: number, lane: number }? = nil
local extraLift = 0 -- the boots' kick, integrated as a real mini-arc
local liftVel = 0 -- its vertical velocity, fought by BootGravity
local flightEvents: { { [string]: any } } = {}
local flightSerial = 0
local claimSent = true
local pendingBundle: any = nil

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

-- ---------- drawing the track ----------
-- Field entries stay in SIM space; the window pass below seats whatever is
-- near the flown distance each frame and hides the rest. The *Base tables
-- keep their old contract — "base exists = currently drawn" — which is
-- exactly what the touch detection reads.

-- Per-entry cosmetics run ONCE per field (on bundle apply), not per frame:
-- mesh sizing, VIP tinting, and which face the cash icon wears. A real
-- cash-stack model keeps its own paint (VIPs just come bigger) and needs no
-- floating marker except the 💰 jackpot flag; the fallback blocks get the
-- tint-and-resize treatment and the full billboard.
local function setupFieldCosmetics()
	for index, prize in pickupParts do
		local entry = pickupField[index]
		if entry then
			local meshBase = prize:GetAttribute("MeshBase") :: Vector3?
			if meshBase then
				prize.Size = meshBase * (entry.vip and 1.6 or 1)
			else
				prize.Color = entry.vip and VIP_GOLD or (PICKUP_LOOK[entry.kind] or PICKUP_LOOK.coin)
				prize.Size = Vector3.one * (entry.vip and 6.5 or 4)
			end
			local icon = prize:FindFirstChild("CashIcon") :: BillboardGui?
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
			end
		end
	end
end

-- One pass, one iteration: seat, bob and spin everything inside the view
-- window; hide everything outside it. Only runs while a shot is flying or
-- resting — between shots the corridor is empty and the track with it.
local function drawTrackObjects(idleClock: number)
	local ahead = Config.CorridorViewAhead
	local behind = Config.CorridorViewBehind

	local function inWindow(d: number): boolean
		return d > shot.flown - behind and d < shot.flown + ahead
	end

	for index, prize in pickupParts do
		local entry = pickupField[index]
		local icon = prize:FindFirstChild("CashIcon") :: BillboardGui?
		if entry and not pickupTaken[index] and inWindow(entry.distance) then
			-- Real arc heights on the flight's own scale — the pickup sits
			-- where the arc that placed it actually passes.
			local lift = math.max(entry.height * shot.heightScale, 2)
			local base = corridorAt(entry.distance, 0)
				+ Vector3.new(0, lift, 0)
				+ SIDE * laneToStuds(entry.lane or 0)
			pickupBase[index] = base
			prize.Transparency = if prize:GetAttribute("MeshBase") then 0 else 0.1
			prize.CFrame = CFrame.new(base + Vector3.new(0, math.sin(idleClock * 2.2 + index) * 0.7, 0))
				* CFrame.Angles(0, idleClock * 1.4 + index, 0)
			if icon then
				local meshy = prize:GetAttribute("MeshBase") ~= nil
				icon.Enabled = not meshy or entry.vip == true
			end
		else
			pickupBase[index] = nil
			prize.Transparency = 1
			if icon then
				icon.Enabled = false
			end
		end
	end

	local function seatExtras(
		parts: { BasePart },
		entries: { any },
		bases: { [number]: Vector3 },
		dead: { [number]: boolean },
		heights: { [number]: number },
		spinSpeed: number,
		bobSpeed: number
	)
		for index, part in parts do
			local entry = entries[index]
			local icon = part:FindFirstChild("Glyph") :: BillboardGui?
			if entry and not dead[index] and inWindow(entry.distance) then
				local lift = math.max(heights[index] or 10, 4)
				local base = corridorAt(entry.distance, 0)
					+ Vector3.new(0, lift, 0)
					+ SIDE * laneToStuds(entry.lane)
				bases[index] = base
				part.Transparency = 0
				part.CFrame = CFrame.new(base + Vector3.new(0, math.sin(idleClock * bobSpeed + index * 2) * 0.8, 0))
					* CFrame.Angles(0, idleClock * spinSpeed + index, 0)
				if icon then
					icon.Enabled = true
				end
			else
				bases[index] = nil
				part.Transparency = 1
				if icon then
					icon.Enabled = false
				end
			end
		end
	end

	seatExtras(bootParts, bootField :: { any }, bootBase, bootTaken, bootDrawHeight, 1.8, 2.6)
	seatExtras(bombParts, bombField :: { any }, bombBase, bombHit, bombDrawHeight, 0.8, 1.6)
end

-- ---------- public ----------

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
	smokeAnchor.Position = muzzle :: Vector3

	-- The capsule display floats over the station, STATION_BACK inward of
	-- the plot centre — the same spot Island.luau builds the pod. (The old
	-- field layout call is gone: the track only draws inside the corridor
	-- window mid-flight now, so there is nothing to lay out from a plot.)
	stationAnchor.Position = centre - flat.Unit * STATION_BACK + Vector3.new(0, CAPSULE_ICON_HEIGHT, 0)
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

	-- And the capsule's icon swaps with it.
	refreshStationIcon()
end

local function applyFieldBundle(bundle: any)
	-- The server sends { pickups, boots, bombs } now; a bare array is an old
	-- shape and still works as pickups-only rather than crashing.
	local pickups = bundle.pickups or bundle
	pickupField = pickups
	bootField = bundle.boots or {}
	bombField = bundle.bombs or {}
	pickupTaken = {}
	pickupCollecting = {}
	bootTaken = {}
	bombHit = {}
	bombNear = {}
	for index, entry in pickupParts do
		if not pickupField[index] then
			pickupTaken[index] = true
			entry.Transparency = 1
		end
	end
	setupFieldCosmetics()
end

function Flight.setField(bundle: any)
	if typeof(bundle) ~= "table" then
		return
	end
	-- The NEXT shot's track lands while this one is still flying (the server
	-- lays it the instant it scores). Swapping mid-replay would yank the
	-- steering game's targets out from underneath it — hold the new track
	-- until the landing settles the claim.
	if shot.active then
		pendingBundle = bundle
		return
	end
	applyFieldBundle(bundle)
end

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

-- The visual arc height at `x`, same parabola family the server draws from.
local function simHeightAt(arcs: { Arc }, x: number): number
	for _, arc in arcs do
		if x <= arc.toX then
			local span = arc.toX - arc.fromX
			if arc.rolling or span <= 0 then
				return 0
			end
			local along = (x - arc.fromX) / span
			return arc.peak * 4 * along * (1 - along)
		end
	end
	return 0
end

-- A pickup visually taken by the mid-air game (steer-through or slam
-- burst). Payment is the server's — the claim covers it — this is only the
-- pop the eye needs at the moment of touch.
local function takePickupVisual(index: number, entry: PickupEntry)
	pickupTaken[index] = true
	pickupCollecting[index] = nil
	local prize = pickupParts[index]
	if prize then
		floatPopup(prize.Position, ("+$%d"):format(entry.value), PICKUP_LOOK[entry.kind] or PICKUP_LOOK.coin)
		prize.Transparency = 1
		pickupBase[index] = nil
		local icon = prize:FindFirstChild("CashIcon") :: BillboardGui?
		if icon then
			icon.Enabled = false
		end

		-- The combo: quick successive grabs count up, announce from three,
		-- and the ping climbs with them — a run through a cash line makes
		-- a little ascending scale.
		local now = os.clock()
		comboCount = if now - comboAt <= 1.25 then comboCount + 1 else 1
		comboAt = now
		if comboCount >= 3 then
			floatPopup(
				prize.Position + Vector3.new(0, 6, 0),
				("COMBO x%d!"):format(comboCount),
				Color3.fromRGB(255, 214, 120)
			)
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

-- The dive. Manual slams spend a limited stock and burst nearby cash on
-- impact; bomb knock-downs are the same dive with no reward attached.
local function beginSlam(manual: boolean)
	if slamActive or not shot.active then
		return
	end
	if manual then
		if slamsUsed >= Config.SlamMaxPerFlight then
			return
		end
		slamsUsed += 1
		slamCollectAt = { distance = shot.flown, lane = steerPos }
		table.insert(flightEvents, { kind = "slam", distance = shot.flown, lane = steerPos })
	else
		slamCollectAt = nil
	end
	-- A dive cancels whatever a boot was still carrying.
	extraLift = 0
	liftVel = 0
	slamActive = true
end

-- What a slam's burst reaches, mirrored from the server's own formula so
-- what pops here is exactly what the claim will pay there.
local function slamBurst(at: { distance: number, lane: number })
	local radius = math.max(shot.distance * Config.SlamRadiusFraction, Config.SlamRadiusMin)
	for index, entry in pickupField do
		if
			not pickupTaken[index]
			and pickupBase[index]
			and math.abs(entry.distance - at.distance) <= radius
			and math.abs((entry.lane or 0) - at.lane) <= Config.SlamLaneRadius
		then
			takePickupVisual(index, entry)
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
		beginSlam(true)
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
		beginSlam(true)
	end
end)

function Flight.play(plan: {
	serial: number?,
	distance: number,
	arcs: { Arc },
	seconds: number,
	peakHeight: number,
	launchSpeed: number?,
	coins: number?,
	milestones: { { name: string, cash: number } }?,
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

	-- Arc height policy: small shots draw 1:1 in every axis (a level-one
	-- flight peaks ~45 real studs); only the big ones compress, down to the
	-- corridor's ceiling, so the walls always contain the whole show.
	shot.heightScale = math.min(Config.CorridorArcCeiling / math.max(plan.peakHeight, 1), 1)

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
	-- ladder of ITS distance (~CorridorMarkerCount boards however far it
	-- goes), stale tracked FX purged, and marker slots forced to relabel.
	markerSpacing = niceStep(shot.distance / Config.CorridorMarkerCount)
	for _, fx in trackedFx do
		if fx.part.Parent then
			fx.part:Destroy()
		end
	end
	table.clear(trackedFx)
	for _, marker in corridorMarkers do
		marker.index = -1
	end

	-- The mid-air game resets with the shot...
	flightSerial = plan.serial or 0
	flightEvents = {}
	claimSent = false
	steerPos = 0
	steerVel = 0
	slamsUsed = 0
	slamActive = false
	slamDrop = 0
	slamCollectAt = nil
	extraLift = 0
	liftVel = 0
	touchAt = nil

	-- ...and the boots and bombs seat ON this flight's own visual arc — the
	-- draw heights are precomputed here, and the per-frame window pass reads
	-- them, so the path runs straight through every one and steering
	-- sideways is genuinely how they are hit or dodged.
	table.clear(bootDrawHeight)
	table.clear(bombDrawHeight)
	for index, entry in bootField do
		bootDrawHeight[index] = simHeightAt(shot.arcs, entry.distance) * shot.heightScale
	end
	for index, entry in bombField do
		bombDrawHeight[index] = simHeightAt(shot.arcs, entry.distance) * shot.heightScale
	end

	-- The milestones this shot crosses for the first time, positioned from
	-- Config by name so the popup fires at the sign it belongs to.
	pendingMilestones = {}
	for _, milestone in plan.milestones or {} do
		for _, entry in Config.DistanceMilestones do
			if entry.name == milestone.name then
				table.insert(pendingMilestones, {
					at = entry.at,
					text = ("🏁 %s Studs!  +%s 💵"):format(milestone.name, Format.abbreviate(milestone.cash)),
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

	return shot.seconds
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
	-- Where the shot was at the top of the frame: touches are judged by
	-- CROSSING an entry's distance, so a fast segment that passes a whole
	-- cluster in one frame still counts every member it swept.
	local flownBefore = shot.flown

	if shot.active then
		shot.progress += dt / shot.seconds
		if shot.progress >= 1 then
			shot.progress = 1
			shot.active = false
			-- The replay is over: settle the mid-air game. One claim per
			-- shot, and the held-back next track can finally land.
			if not claimSent then
				claimSent = true
				ClaimFlightRemote:FireServer(flightSerial, flightEvents)
			end
			if pendingBundle then
				local bundle = pendingBundle
				pendingBundle = nil
				applyFieldBundle(bundle)
			end
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

	-- The slam's dive and recovery. The arc itself never changes — the dive
	-- scales the drawn height down to the ground and eases it back after.
	if slamActive then
		slamDrop = math.min(slamDrop + dt * 5, 1)
		if slamDrop >= 1 then
			slamActive = false
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
			if slamCollectAt then
				floatPopup(ground + Vector3.new(0, 8, 0), "💥 SLAM!", Color3.fromRGB(255, 214, 120))
				slamBurst(slamCollectAt :: { distance: number, lane: number })
				slamCollectAt = nil
			end
		end
	elseif slamDrop > 0 then
		slamDrop = math.max(slamDrop - dt * 2.2, 0)
	end

	-- The boots' kick, integrated: an impulse rises against its own gravity
	-- and falls back to the server's arc — a smooth little bounce on top of
	-- the flight, not a teleport up and an ooze down.
	if extraLift > 0 or liftVel > 0 then
		liftVel -= Config.BootGravity * dt
		extraLift = math.max(extraLift + liftVel * dt, 0)
		if extraLift == 0 and liftVel < 0 then
			liftVel = 0
		end
	end

	-- Where the squishy actually draws: at the treadmill's origin, on the
	-- server's arc, dived by any slam, kicked by any boot, and steered
	-- sideways across the fixed lane.
	local arcAt = corridorAt(shot.flown, shot.height)
	local groundLevel = CORRIDOR_ORIGIN.Y
	local at = Vector3.new(
		arcAt.X,
		groundLevel + (arcAt.Y - groundLevel) * (1 - slamDrop) + extraLift,
		arcAt.Z
	) + SIDE * laneToStuds(steerPos)

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
			tile.Color = tileIndex % 2 == 0 and corridorTheme.grass or corridorTheme.grassDark
			tile.CFrame = CFrame.new(base - Vector3.new(0, 1, 0))
			local walls = corridorWalls[slot]
			walls.left.CFrame = CFrame.new(base + SIDE * (-width / 2 - 3) + Vector3.new(0, wallHeight / 2, 0))
			walls.right.CFrame = CFrame.new(base + SIDE * (width / 2 + 3) + Vector3.new(0, wallHeight / 2, 0))
			walls.leftLip.CFrame = CFrame.new(base + SIDE * (-width / 2 - 3) + Vector3.new(0, wallHeight + 2, 0))
			walls.rightLip.CFrame = CFrame.new(base + SIDE * (width / 2 + 3) + Vector3.new(0, wallHeight + 2, 0))
		end

		local firstMarker = math.max(math.floor((shot.flown - Config.CorridorViewBehind) / markerSpacing), 1)
		local lastMarker = math.floor((shot.flown + Config.CorridorViewAhead) / markerSpacing)
		for markerIndex = firstMarker, lastMarker do
			local slot = (markerIndex % CORRIDOR_POOL) + 1
			local marker = corridorMarkers[slot]
			local d = markerIndex * markerSpacing
			local base = corridorAt(d, 0)
			marker.stripe.CFrame = CFrame.new(base + Vector3.new(0, 0.2, 0))
			if marker.index ~= markerIndex then
				-- Relabel only on slot reuse: TextLabel writes are not free.
				marker.index = markerIndex
				local text = ("%s Studs"):format(Format.abbreviate(d))
				for _, label in marker.labels do
					label.Text = text
				end
			end
			for boardIndex, board in marker.boards do
				local sideSign = boardIndex == 1 and -1 or 1
				board.CFrame = CFrame.new(
					base + SIDE * (sideSign * (width / 2 + 2)) + Vector3.new(0, 20, 0)
				)
			end
		end

		-- The static depth dressing rides at fixed offsets from the origin.
		corridorCap.CFrame = CFrame.new(
			CORRIDOR_ORIGIN + FORWARD * Config.CorridorViewAhead + Vector3.new(0, wallHeight / 2, 0)
		)
		for _, plane in corridorFog do
			local fraction = plane:GetAttribute("AheadFraction") :: number
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

	-- Steering through things: whatever the drawn squishy touches, the claim
	-- remembers. The server re-prices all of it; these are the visuals.
	-- Judged in LANE UNITS and by crossing, never world proximity — the
	-- lane's world width varies with distance now, so a fixed world radius
	-- would be untouchable far out and unmissable up close.
	if flying and toy then
		local laneTouch = Config.LaneTouchWidth
		local function crossed(distance: number, lane: number): boolean
			return distance > flownBefore
				and distance <= shot.flown
				and math.abs(lane - steerPos) <= laneTouch
		end

		for index, entry in pickupField do
			local base = pickupBase[index]
			if base and not pickupTaken[index] and pickupCollecting[index] == nil then
				if crossed(entry.distance, entry.lane or 0) and math.abs(base.Y - at.Y) <= 16 then
					takePickupVisual(index, entry)
					table.insert(flightEvents, { kind = "pickup", index = index })
				end
			end
		end
		for index, entry in bootField do
			local base = bootBase[index]
			if base and not bootTaken[index] and crossed(entry.distance, entry.lane) and math.abs(base.Y - at.Y) <= 15 then
				bootTaken[index] = true
				bootBase[index] = nil
				bootParts[index].Transparency = 1
				local glyph = bootParts[index]:FindFirstChild("Glyph") :: BillboardGui?
				if glyph then
					glyph.Enabled = false
				end
				-- An impulse, not a position set: the loop's integrator turns
				-- it into the smooth rise. Chained boots keep the stronger kick.
				liftVel = math.max(liftVel, Config.BootImpulse)
				bootSound.PlaybackSpeed = 1 + 0.12 * index
				bootSound:Play()
				floatPopup(base, "+BOOST!", Color3.fromRGB(120, 244, 128))
				table.insert(flightEvents, { kind = "boot", index = index })
			end
		end
		for index, entry in bombField do
			local base = bombBase[index]
			-- Sailing close PAST a bomb earns a once-per-bomb "phew!" — the
			-- near-miss is half of why dodging feels like anything.
			if
				base
				and not bombHit[index]
				and not bombNear[index]
				and entry.distance > flownBefore
				and entry.distance <= shot.flown
				and math.abs(entry.lane - steerPos) > laneTouch
				and math.abs(entry.lane - steerPos) <= laneTouch * 2.4
			then
				bombNear[index] = true
				floatPopup(base + Vector3.new(0, 6, 0), "phew!", Color3.fromRGB(255, 240, 150))
			end
			if base and not bombHit[index] and crossed(entry.distance, entry.lane) and math.abs(base.Y - at.Y) <= 15 then
				bombHit[index] = true
				bombBase[index] = nil
				bombParts[index].Transparency = 1
				local glyph = bombParts[index]:FindFirstChild("Glyph") :: BillboardGui?
				if glyph then
					glyph.Enabled = false
				end
				boomFx(base)
				bounceThock.PlaybackSpeed = 0.5
				bounceThock:Play()
				floatPopup(base, "-BOOM!", Color3.fromRGB(255, 110, 92))
				-- The hit reads in the body: spin knocked down, and a forced
				-- dive with no burst attached.
				spinRate *= 0.55
				beginSlam(false)
				fovKick = 1
				shakeAmp = Config.ImpactShakeMagnitude
				shakePhase = 0
				table.insert(flightEvents, { kind = "bomb", index = index })
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
		-- The hit costs spin (bounce friction, made visible) and buys squash.
		spinRate *= 0.78
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
		-- The treadmill has stopped (flown == distance), so the landing FX
		-- sit still on their own — but they register with the tracker
		-- anyway, in case a later system ever moves the window at rest.
		local ground = corridorAt(shot.distance, 0) + SIDE * laneToStuds(steerPos)
		trackFx(splat(ground, Config.LaunchSplatRadius), shot.distance, steerPos, 0.4)
		payoutPopup(ground, shot.distance, shot.earnedCoins)
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
		trackFx(party, shot.distance, steerPos, 4)
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
			-- The somersault runs at the spin the LAUNCH gave it, not on a
			-- timer — each bounce has already bled some off above — and once
			-- the shot is down in its final roll, the turn rate locks to the
			-- TREADMILL's drawn ground speed, like a wheel. The corridor is
			-- 1:1 longitudinally, so the sim's own delta IS the visual speed.
			local radiusWorld = math.max(-toy.lowestY * applied, 0.5)
			local lastArc = shot.arcs[#shot.arcs]
			local rollingNow = lastArc and lastArc.rolling and shot.flown >= lastArc.fromX
			if rollingNow and dt > 0 then
				spinRate = (shot.flown - flownBefore) / dt / radiusWorld
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
			local ground = corridorAt(shot.distance, 0) + SIDE * laneToStuds(steerPos)
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

	-- Pickups pop as the shot reaches them — with a little "+value" floating
	-- off each one, so a good line through a cluster reads as a combo rather
	-- than as scenery quietly vanishing. The server already decided WHICH
	-- ones; this is only the moment they disappear.
	for index, distance in pickupCollecting do
		if shot.flown >= distance then
			local prize = pickupParts[index]
			local entry = pickupField[index]
			if prize and entry then
				floatPopup(prize.Position, ("+%d 💵"):format(entry.value), PICKUP_LOOK[entry.kind] or PICKUP_LOOK.coin)
				prize.Transparency = 1
				pickupBase[index] = nil
				local icon = prize:FindFirstChild("CashIcon") :: BillboardGui?
				if icon then
					icon.Enabled = false
				end
			end
			pickupTaken[index] = true
			pickupCollecting[index] = nil
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
