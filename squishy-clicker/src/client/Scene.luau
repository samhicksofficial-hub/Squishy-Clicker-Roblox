--!strict
-- ============================================================
--  SCENE  —  the 3D stage: camera, lights, the steamer, and the
--  choreography for opening it.
--
--  Everything here is built on the CLIENT, so each player gets a
--  private steamer that nobody else can see or touch. This file
--  never talks to the server; init.client.luau drives it.
--
--  Motion is SPRING driven rather than tweened. A spring can be
--  re-kicked while it is still moving without fighting a running
--  tween, which is what makes fast clicking feel bouncy instead
--  of stuttery — and it gives squash-and-stretch its overshoot
--  for free.
-- ============================================================

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Models = require(script.Parent:WaitForChild("Models"))

local Scene = {}

-- The stage lives high above the map so whatever is in the place already —
-- baseplate, spawn, the player's own character — stays out of frame.
local ORIGIN = Vector3.new(0, 500, 0)
-- The MAIN view frames the squisher on its cushion; the camera never moves,
-- it only turns. Aim height splits the difference between the cushion and the
-- risen squishy so reveals stay in frame after the turn.
local CAMERA_POS = ORIGIN + Vector3.new(0.5, 5.0, 16.5)
local CAMERA_LOOK = ORIGIN + Vector3.new(1.9, 3.0, 0)
local BASE_LOOK_DIR = CAMERA_LOOK - CAMERA_POS
local FIELD_OF_VIEW = 50

-- The steamer lives in its own nook, exactly 90° to the camera's LEFT — the
-- position is ORIGIN rotated 90° around the camera, so after the turn the
-- steamer occupies the same spot on screen the squisher does in the main view.
local STEAMER_ORIGIN = ORIGIN + Vector3.new(-16, 0, 17)

-- The cannon sits the same 90° out on the other side, so the three views are
-- one camera turning left, centre and right rather than three cameras.
local CANNON_ORIGIN = ORIGIN + Vector3.new(17, 0, 18)
-- ---------- fitting an unbounded track onto a finite stage ----------
-- Distances run from a few hundred studs to seven figures, so nothing here is
-- drawn at 1:1 and nothing is drawn to the end. Instead:
--
--  * the TRACK is a treadmill. A fixed pool of stripes recycles through a
--    window, and the squishy stops moving forward once it reaches its station
--    while the world scrolls underneath. That makes distance unbounded for
--    free, and keeps every piece of scenery inside the frustum checks the
--    other two camera views depend on.
--
--  * the SCALES are per-field, not fixed. `runScale` is chosen so a full shot
--    always sweeps about TRACK_RUN studs of stage, and `heightScale` so its
--    arc always peaks about STAGE_APEX studs up — whatever the real numbers
--    are. A level-1 shot and a level-80 shot therefore look and pace the
--    same, which is the only way a launch simulator stays readable across
--    four orders of magnitude.
--
-- Both are recomputed when a pickup field arrives (the server sizes that to
-- the player's reach) and then held for the shot, so nothing jumps at launch.
local TRACK_RUN = 300 -- stage studs a full shot scrolls through
-- Stage studs a full shot's arc peaks at. MUST match Config.MagnetReferenceHeight:
-- the magnet is quoted in these same screen units and converted back out
-- against this number, so the reach a player SEES is the reach that scores.
local STAGE_APEX = Config.MagnetReferenceHeight
local STAGE_LEAD_IN = 15 -- how far the squishy travels before the world starts scrolling
local MAX_HEIGHT_STRETCH = 2.5 -- arcs may be this much taller than wide, no more

-- Fallback used before the first field arrives.
local RANGE_SCALE = 0.28
local runScale = RANGE_SCALE
local heightScale = RANGE_SCALE
local scroll = 0 -- stage studs the world has slid backwards

-- The recycling stripe pool. Its span is the whole visible track, and the
-- rainbow runs exactly once around it so a stripe wrapping from the far end
-- back to the near one lands on the colour its new neighbour expects.
local TRACK_STRIPES = 64
local STRIPE_DEPTH = 2.2
local TRACK_SPAN = TRACK_STRIPES * STRIPE_DEPTH
-- The barrel's pivot, which is also where a shot starts from. Sits on top of
-- the cannon's plinth, so raising the plinth means raising this.
local MUZZLE_HEIGHT = 3.6

-- Where the chase camera sits relative to the shot while it's in the air:
-- behind it down the range, above it, and off to the near side so the arc is
-- seen from three-quarters rather than dead-on. It looks slightly AHEAD of the
-- squishy, which keeps the ground still to come in frame.
local CHASE_BACK = 7
local CHASE_UP = 3.6
local CHASE_SIDE = 12
local CHASE_LEAD = 5

-- Half-turns of tumble over a whole flight, airborne versus rolling. Fired out
-- of a cannon it spins hard; once it is rolling it settles to a lazy turn.
local TUMBLE_AIR = 9
local TUMBLE_ROLL = 3

-- How hard a pet chases the slot in front of it. Soft and underdamped on
-- purpose: pets that keep up perfectly look welded on.
local PET_STIFFNESS = 90
local PET_DAMPING = 12

local BACKDROP_COLOR = Color3.fromRGB(240, 222, 206) -- invisible helper parts only

local LID_REST_Y = 2.15 -- where the lid sits on the tub
-- The highest a hidden squishy's top may reach and still be swallowed by the
-- tub walls. Resting height is worked back from this per squishy, so the tub
-- hides it whatever its size and shape.
local TUB_TOP_INSIDE = 1.9
local DUMPLING_RISEN_Y = 4.0
local REVEAL_SECONDS = 1.7

-- ---------- springs ----------

type Spring = { value: number, velocity: number, target: number, stiffness: number, damping: number }

local function spring(stiffness: number, damping: number): Spring
	return { value = 0, velocity = 0, target = 0, stiffness = stiffness, damping = damping }
end

local function advance(s: Spring, dt: number)
	local accel = (s.target - s.value) * s.stiffness - s.velocity * s.damping
	s.velocity += accel * dt
	s.value += s.velocity * dt
end

-- Snap a spring to a value and let it settle back to its target. This is the
-- "kick" that makes a click land instantly instead of easing in.
local function kick(s: Spring, amount: number)
	s.value = amount
	s.velocity = 0
end

local squash = spring(190, 15) -- the whole steamer compressing on a click
local clickerSquash = spring(210, 13) -- the click toy, squishing harder
local lidLift = spring(55, 8.5)
local lidTilt = spring(48, 8)
-- Slides the lid SIDEWAYS during a reveal. Without it the lid hovers directly
-- over the risen squishy and hides the whole show from the camera.
local lidSide = spring(38, 7.5)
local rise = spring(70, 11) -- dumpling climbing out, 0..1
local jiggle = spring(150, 11)
local glow = spring(90, 12)
local rayGlow = spring(40, 9)

-- 0 = facing the squisher, 1 = turned 90° left to the steamer nook. Springy
-- so the turn eases out with a hint of overshoot instead of lerping flatly.
local viewYaw = spring(30, 10)

local lidSpin = 0
local lidSpinVelocity = 0
local dumplingSpin = 0
local shake = 0
local elapsed = 0
local progress = 0
local revealToken = 0

-- ---------- the stage ----------

local stage = Instance.new("Folder")
stage.Name = "SquishyStage"
stage.Parent = workspace

local function block(size: Vector3, position: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = stage
	return part
end

-- ---------- the toy shop ----------
-- A stylised toy store behind the steamer: teal walls, white pillars, a
-- skylight band, shelves of colourful boxes and a high ledge of plush balls.
-- Deliberately chunky and low-detail — a DepthOfField effect blurs it into a
-- soft backdrop while the steamer is the focus, so silhouettes and colour are
-- all that survive anyway. Seeded Random keeps the clutter identical every run.
local shopRandom = Random.new(7)
local TOY_COLORS = {
	Color3.fromRGB(232, 82, 82),
	Color3.fromRGB(245, 166, 60),
	Color3.fromRGB(248, 214, 80),
	Color3.fromRGB(110, 200, 110),
	Color3.fromRGB(88, 160, 230),
	Color3.fromRGB(170, 120, 230),
	Color3.fromRGB(240, 130, 190),
	Color3.fromRGB(250, 246, 240),
}
local function toyColor(): Color3
	return TOY_COLORS[shopRandom:NextInteger(1, #TOY_COLORS)]
end

-- Wooden floor, wide enough to run under all three views: the steamer nook to
-- the left, the squisher ahead, and the cannon range to the right.
local shopFloor = block(Vector3.new(160, 0.5, 100), ORIGIN + Vector3.new(0, -0.25, 0), Color3.fromRGB(206, 172, 134))
shopFloor.Material = Enum.Material.WoodPlanks

-- Teal back wall with a white upper band and skylight strip above
local wall = block(Vector3.new(110, 13, 0.8), ORIGIN + Vector3.new(0, 6.5, -16), Color3.fromRGB(62, 178, 186))
wall.Material = Enum.Material.SmoothPlastic
block(Vector3.new(110, 3.2, 0.8), ORIGIN + Vector3.new(0, 14.6, -16), Color3.fromRGB(248, 246, 242))
local skylight = block(Vector3.new(110, 6, 0.6), ORIGIN + Vector3.new(0, 19.2, -15.8), Color3.fromRGB(198, 224, 242))
skylight.Material = Enum.Material.Glass
for i = -5, 5 do -- skylight mullions
	block(Vector3.new(0.5, 6, 0.7), ORIGIN + Vector3.new(i * 9, 19.2, -15.7), Color3.fromRGB(248, 246, 242))
end

-- White pillars against the wall
for _, x in { -13, -4.5, 4.5, 13 } do
	block(Vector3.new(1.4, 16.2, 1.2), ORIGIN + Vector3.new(x, 8.1, -15.3), Color3.fromRGB(250, 248, 244))
end

-- High ledge with the rainbow plush row, like the balcony in the reference
block(Vector3.new(110, 0.5, 2.4), ORIGIN + Vector3.new(0, 12.6, -14.8), Color3.fromRGB(250, 248, 244))
for i = 1, 14 do
	local plush = Instance.new("Part")
	plush.Shape = Enum.PartType.Ball
	local diameter = shopRandom:NextNumber(1.5, 2.2)
	plush.Size = Vector3.new(diameter, diameter, diameter)
	plush.Position = ORIGIN + Vector3.new(-26 + i * 3.7, 12.85 + diameter / 2, -14.8)
	plush.Color = Color3.fromHSV((i - 1) / 14, 0.62, 0.95)
	plush.Material = Enum.Material.SmoothPlastic
	plush.Anchored = true
	plush.CanCollide = false
	plush.CanQuery = false
	plush.CanTouch = false
	plush.Parent = stage
end

-- Shelf gondolas stacked with colourful toy boxes
for _, shelfX in { -13, -5, 3.5, 12 } do
	local shelfZ = -11.5
	for side = -1, 1, 2 do -- white end panels
		block(Vector3.new(0.35, 6.0, 2.0), ORIGIN + Vector3.new(shelfX + side * 3.1, 3.0, shelfZ), Color3.fromRGB(250, 248, 244))
	end
	for level = 0, 2 do
		local boardY = 1.1 + level * 1.9
		block(Vector3.new(6.2, 0.28, 1.9), ORIGIN + Vector3.new(shelfX, boardY, shelfZ), Color3.fromRGB(222, 196, 158))
		local cursor = -2.6
		while cursor < 2.2 do
			local width = shopRandom:NextNumber(0.6, 1.2)
			local height = shopRandom:NextNumber(0.7, 1.4)
			block(
				Vector3.new(width, height, shopRandom:NextNumber(0.5, 1.0)),
				ORIGIN + Vector3.new(shelfX + cursor + width / 2, boardY + 0.14 + height / 2, shelfZ),
				toyColor()
			)
			cursor += width + shopRandom:NextNumber(0.1, 0.5)
		end
	end
end

-- The steamer nook: the wall the camera faces after the 90° turn left. Same
-- teal-and-skylight language as the main wall, meeting it in an L corner.
local unboxWall = block(Vector3.new(0.8, 13, 56), ORIGIN + Vector3.new(-32, 6.5, 12), Color3.fromRGB(62, 178, 186))
unboxWall.Material = Enum.Material.SmoothPlastic
block(Vector3.new(0.8, 3.2, 56), ORIGIN + Vector3.new(-32, 14.6, 12), Color3.fromRGB(248, 246, 242))
local unboxSkylight = block(Vector3.new(0.6, 6, 56), ORIGIN + Vector3.new(-31.8, 19.2, 12), Color3.fromRGB(198, 224, 242))
unboxSkylight.Material = Enum.Material.Glass
for _, z in { -2, 12, 26 } do
	block(Vector3.new(1.2, 16.2, 1.4), ORIGIN + Vector3.new(-31.3, 8.1, z), Color3.fromRGB(250, 248, 244))
end

-- ---------- the cannon range ----------
-- The third view: a cannon and a long course running down +X, marked out in
-- zones. Geometry only — the server decides how far any shot actually goes.

-- Where a game-stud distance sits on the stage right now. Everything on the
-- track goes through this one function, so the treadmill is a single subtraction
-- rather than something each piece of scenery has to remember to do.
local function rangeSpot(distance: number, height: number): Vector3
	return CANNON_ORIGIN + Vector3.new(distance * runScale - scroll, height * heightScale, 0)
end

-- True when a stage X is close enough to the camera's window to be worth
-- drawing. Anything else is parked invisible rather than destroyed.
local function onScreen(stageX: number): boolean
	return stageX > CANNON_ORIGIN.X - 12 and stageX < CANNON_ORIGIN.X + TRACK_SPAN
end

-- The range is deliberately NOT the toy shop: the cannon fires out of the shop
-- and onto a bright rainbow runway under open sky. It's the one view where
-- distance is the whole point, and a wall at the end of it would fight that —
-- so the course simply runs to the horizon.
-- All three views share one camera position, so the range has to keep out of
-- the main view's frustum entirely. That is what fixes these bounds: the
-- runway is narrow and the grass starts well out along +X and +Z, because
-- anything nearer than this shows up as a wedge of lawn inside the toy shop.
-- Twelve studs across still fills most of the cannon view at this distance.
local RANGE_HALF_WIDTH = 6
local RANGE_DRAWN = TRACK_SPAN

local GRASS_COLOR = Color3.fromRGB(124, 200, 84)
local SAND_COLOR = Color3.fromRGB(243, 222, 168)
local WATER_COLOR = Color3.fromRGB(118, 200, 232)

-- Grass apron either side of the runway, laid over the shop's floorboards.
-- Every one of these four bounds is set by the main view rather than by taste:
-- the near corner (GRASS_START_X, GRASS_NEAR_Z) is the one that decides it,
-- and it sits outside the main camera's frustum with room to spare even on an
-- ultrawide screen. Pull either in and lawn appears inside the toy shop.
local GRASS_START_X = CANNON_ORIGIN.X - 5
local GRASS_END_X = CANNON_ORIGIN.X + RANGE_DRAWN + 15
local GRASS_NEAR_Z = CANNON_ORIGIN.Z - 8
local GRASS_FAR_Z = CANNON_ORIGIN.Z + 22
local grass = block(
	Vector3.new(GRASS_END_X - GRASS_START_X, 0.5, GRASS_FAR_Z - GRASS_NEAR_Z),
	Vector3.new((GRASS_START_X + GRASS_END_X) * 0.5, ORIGIN.Y - 0.19, (GRASS_NEAR_Z + GRASS_FAR_Z) * 0.5),
	GRASS_COLOR
)
grass.Material = Enum.Material.Grass

-- The cannon's little island: a ring of water round a sand bank, straight out
-- of the reference. Cylinders rather than blocks so it reads as an island.
local function disc(diameter: number, height: number, centre: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = CFrame.new(centre) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = stage
	return part
end

disc(12, 0.35, CANNON_ORIGIN + Vector3.new(0, 0.1, 0), WATER_COLOR)
disc(9.5, 0.5, CANNON_ORIGIN + Vector3.new(0, 0.2, 0), SAND_COLOR)

-- ---------- the rainbow runway ----------
-- Bands laid ACROSS the course, marching away from the cannon. Perpendicular
-- stripes are what give a flat plane its sense of speed, and they are the
-- reason the treadmill reads as motion at all.
local trackStripes: { BasePart } = {}
for step = 1, TRACK_STRIPES do
	local stripe = block(
		Vector3.new(STRIPE_DEPTH, 0.3, RANGE_HALF_WIDTH * 2),
		CANNON_ORIGIN + Vector3.new(step * STRIPE_DEPTH, 0.25, 0),
		-- One full rainbow around the pool, so the wrap is seamless.
		Color3.fromHSV((step - 1) / TRACK_STRIPES, 0.82, 1)
	)
	stripe.Material = Enum.Material.SmoothPlastic
	table.insert(trackStripes, stripe)
end

-- Returns the invisible anchor rather than the label: a sign on the treadmill
-- is moved by its anchor, and the text never changes once it is set.
local function floatingLabel(at: Vector3, text: string, color: Color3, width: number, height: number): Part
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = at
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = stage

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, width, 0, height)
	gui.AlwaysOnTop = false
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(52, 38, 30)
	label.TextStrokeTransparency = 0.15
	label.TextScaled = true
	label.Parent = gui
	return anchor
end

-- ---------- milestone signs ----------
-- One gate per entry in Config.DistanceMilestones, repositioned every frame
-- from the treadmill rather than built where it belongs: 1,000,000 studs has
-- no fixed place on the stage, only a place relative to where the shot is now.
local MILESTONE_COLORS = {
	Color3.fromRGB(238, 232, 224),
	Color3.fromRGB(120, 205, 235),
	Color3.fromRGB(250, 200, 80),
	Color3.fromRGB(245, 150, 95),
	Color3.fromRGB(226, 96, 96),
}

type MilestoneSign = { at: number, gate: BasePart, post: BasePart, sign: BasePart }
local milestoneSigns: { MilestoneSign } = {}
for index, milestone in Config.DistanceMilestones do
	local color = MILESTONE_COLORS[index] or Color3.fromRGB(238, 232, 224)

	local gate = block(Vector3.new(0.8, 0.16, RANGE_HALF_WIDTH * 2), CANNON_ORIGIN, Color3.fromRGB(255, 255, 255))
	gate.Material = Enum.Material.SmoothPlastic

	table.insert(milestoneSigns, {
		at = milestone.at,
		gate = gate,
		post = block(Vector3.new(0.35, 7, 0.35), CANNON_ORIGIN, Color3.fromRGB(250, 248, 244)),
		sign = floatingLabel(CANNON_ORIGIN, ("%s studs"):format(milestone.name), color, 150, 40),
	})
end

-- Boulders down the far side of the course, purely so it isn't a bare green
-- field. Far side only: the near side is where the shop is, and there is not
-- enough lawn between the runway and the corner to put anything on.
local rangeRandom = Random.new(19)
for _ = 1, 12 do
	local along = rangeRandom:NextNumber(4, RANGE_DRAWN)
	local out = rangeRandom:NextNumber(RANGE_HALF_WIDTH + 4, RANGE_HALF_WIDTH + 14)
	local size = rangeRandom:NextNumber(1.4, 3.2)
	local rock = block(
		Vector3.new(size, size * 0.75, size * 1.2),
		CANNON_ORIGIN + Vector3.new(along, size * 0.3, out),
		Color3.fromRGB(152, 152, 158)
	)
	rock.Material = Enum.Material.Slate
end

-- ---------- the pickups strung along the track ----------
-- A fixed pool, positioned from whatever field the server last sent. Pooled
-- rather than rebuilt because the field is replaced after every single shot,
-- and generously sized because Rain TNT and the VIP zones both ADD to the
-- ordinary count rather than replacing it.
local PICKUP_LOOK = {
	tnt = { color = Color3.fromRGB(232, 118, 58), size = 1.7, material = Enum.Material.WoodPlanks },
	coin = { color = Color3.fromRGB(252, 208, 96), size = 1.5, material = Enum.Material.Neon },
	gem = { color = Color3.fromRGB(126, 232, 224), size = 1.7, material = Enum.Material.Neon },
}
local PICKUP_POOL = Config.LaunchPickupCount * Config.BoostDensityMultiplier
	+ Config.VipZoneCount * Config.VipZoneDensityMultiplier

type PickupEntry = { distance: number, height: number, kind: string, value: number, vip: boolean }

local pickupParts: { BasePart } = {}
for _ = 1, PICKUP_POOL do
	local prize = Instance.new("Part")
	prize.Size = Vector3.one * 1.5
	prize.Color = PICKUP_LOOK.tnt.color
	prize.Material = Enum.Material.Neon
	prize.Anchored = true
	prize.CanCollide = false
	prize.CanQuery = false
	prize.CanTouch = false
	prize.Transparency = 1 -- nothing to show until a field arrives
	prize.Parent = stage
	table.insert(pickupParts, prize)
end

-- The live field, and what has already been eaten this flight. Distances stay
-- in GAME studs: the treadmill means their stage position changes every frame,
-- so caching a Vector3 would be caching something already stale.
local pickupField: { PickupEntry } = {}
local pickupTaken: { boolean } = {}
local pickupCollecting: { [number]: number } = {} -- index -> distance it pops at

-- ---------- pets ----------
-- Up to five followers trailing the squishy in a loose line.
--
-- The brief asked for AlignPosition/AlignOrientation. Those are physics
-- constraints and need unanchored parts with a network owner; this entire
-- stage is anchored client-side geometry 500 studs above the map, with no
-- character and no physics ownership anywhere in it. Springs give the same
-- lagging, overshooting follow and are what the rest of this file already
-- uses, so pets move like everything else here rather than being the one
-- thing driven by a different system.
local PET_TRAIL_SPACING = 1.5 -- stage studs of lag between one pet and the next
local PET_SIZE = 1.05

type PetFollower = { part: BasePart, position: Vector3, velocity: Vector3 }
local petFollowers: { PetFollower } = {}
for _ = 1, Config.MaxEquippedPets do
	local pet = Instance.new("Part")
	pet.Shape = Enum.PartType.Ball
	pet.Size = Vector3.one * PET_SIZE
	pet.Color = Color3.fromRGB(255, 255, 255)
	pet.Material = Enum.Material.SmoothPlastic
	pet.Anchored = true
	pet.CanCollide = false
	pet.CanQuery = false
	pet.CanTouch = false
	pet.Transparency = 1
	pet.Parent = stage
	-- Seeded at the origin; the first frame springs them to the squishy.
	table.insert(petFollowers, { part = pet, position = ORIGIN, velocity = Vector3.zero })
end

-- ---------- the cannon ----------
-- Chunky and cartoon rather than military: a cream crate of a plinth, a fat
-- pastel barrel, a ladder up the side and crates of TNT stacked around it.
local PLINTH_COLOR = Color3.fromRGB(240, 224, 186)
local BARREL_COLOR = Color3.fromRGB(140, 152, 205)
local BARREL_DARK = Color3.fromRGB(52, 56, 84)
local LADDER_COLOR = Color3.fromRGB(178, 128, 74)

-- Launch pad: the red apron the cannon stands on.
local pad = disc(8, 0.3, CANNON_ORIGIN + Vector3.new(0, 0.42, 0), Color3.fromRGB(232, 92, 80))
pad.Material = Enum.Material.SmoothPlastic
-- On the near lip of the pad: the cannon view looks down +X, so -X is the
-- edge closest to the camera and the only one that isn't hidden by the plinth.
floatingLabel(CANNON_ORIGIN + Vector3.new(-3.6, 0.9, 0), "LAUNCH", Color3.fromRGB(255, 255, 255), 130, 34)

local plinth = block(Vector3.new(5.4, 2.2, 5.4), CANNON_ORIGIN + Vector3.new(0, 1.3, 0), PLINTH_COLOR)
plinth.Material = Enum.Material.SmoothPlastic
local plinthTop = block(Vector3.new(4.6, 0.5, 4.6), CANNON_ORIGIN + Vector3.new(0, 2.6, 0), Color3.fromRGB(226, 206, 162))
plinthTop.Material = Enum.Material.SmoothPlastic

-- Ladder up the face nearest the camera, like the reference. Rungs run along
-- Z because that face looks back down -X toward the viewer.
for rung = 0, 4 do
	block(Vector3.new(0.16, 0.16, 0.9), CANNON_ORIGIN + Vector3.new(-2.78, 0.55 + rung * 0.48, 0), LADDER_COLOR)
end
for _, rail in { -0.42, 0.42 } do
	block(Vector3.new(0.16, 2.5, 0.16), CANNON_ORIGIN + Vector3.new(-2.78, 1.35, rail), LADDER_COLOR)
end

-- Leafy tuft at the foot of it, so the island isn't bare sand.
for leaf = 1, 5 do
	local angle = (leaf / 5) * math.pi * 2
	local frond = block(
		Vector3.new(1.7, 0.3, 0.5),
		CANNON_ORIGIN + Vector3.new(math.cos(angle) * 0.9 + 3.4, 0.65, math.sin(angle) * 0.9 - 2.2),
		Color3.fromRGB(96, 186, 104)
	)
	frond.Material = Enum.Material.Grass
end

-- Crates of TNT scattered round the base.
local TNT_SPOTS = {
	Vector3.new(-3.4, 0, -2.6),
	Vector3.new(-3.9, 0, -1.2),
	Vector3.new(-2.9, 0, -3.6),
	Vector3.new(-3.2, 1.3, -2.1),
}
for _, spot in TNT_SPOTS do
	local crate = block(Vector3.new(1.3, 1.3, 1.3), CANNON_ORIGIN + spot + Vector3.new(0, 1.1, 0), Color3.fromRGB(228, 118, 58))
	crate.Material = Enum.Material.WoodPlanks
end

-- The barrel is the one moving piece: the render loop tilts it to the aim.
local BARREL_LENGTH = 5.6
local cannonBarrel = Instance.new("Part")
cannonBarrel.Shape = Enum.PartType.Cylinder
cannonBarrel.Size = Vector3.new(BARREL_LENGTH, 3.1, 3.1)
cannonBarrel.Color = BARREL_COLOR
cannonBarrel.Material = Enum.Material.SmoothPlastic
cannonBarrel.Anchored = true
cannonBarrel.CanCollide = false
cannonBarrel.CanQuery = false
cannonBarrel.CanTouch = false
cannonBarrel.Parent = stage

-- The dark mouth, and a band round it. Both ride the barrel, so they are
-- positioned in the render loop alongside it rather than once here.
local barrelLip = Instance.new("Part")
barrelLip.Shape = Enum.PartType.Cylinder
barrelLip.Size = Vector3.new(0.7, 3.4, 3.4)
barrelLip.Color = Color3.fromRGB(120, 132, 190)
barrelLip.Material = Enum.Material.SmoothPlastic
barrelLip.Anchored = true
barrelLip.CanCollide = false
barrelLip.CanQuery = false
barrelLip.CanTouch = false
barrelLip.Parent = stage

local barrelMouth = Instance.new("Part")
barrelMouth.Shape = Enum.PartType.Cylinder
barrelMouth.Size = Vector3.new(0.25, 2.5, 2.5)
barrelMouth.Color = BARREL_DARK
barrelMouth.Material = Enum.Material.SmoothPlastic
barrelMouth.Anchored = true
barrelMouth.CanCollide = false
barrelMouth.CanQuery = false
barrelMouth.CanTouch = false
barrelMouth.Parent = stage

local muzzleSmoke = Instance.new("ParticleEmitter")
muzzleSmoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
muzzleSmoke.Rate = 0
muzzleSmoke.Lifetime = NumberRange.new(0.5, 1.1)
muzzleSmoke.Speed = NumberRange.new(8, 16)
muzzleSmoke.SpreadAngle = Vector2.new(14, 14)
muzzleSmoke.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.6),
	NumberSequenceKeypoint.new(1, 3.4),
})
muzzleSmoke.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})
muzzleSmoke.LightEmission = 0.3
muzzleSmoke.Parent = cannonBarrel

-- The blur that fades the shop out behind the squisher and the steamer.
-- Everything nearer than the focus distance stays sharp; the walls sit past it.
local depthOfField = Instance.new("DepthOfFieldEffect")
depthOfField.FocusDistance = 17
depthOfField.InFocusRadius = 8
depthOfField.FarIntensity = 0.6
depthOfField.NearIntensity = 0
depthOfField.Parent = Lighting

local backdropFaded = true

-- For a future free-roam mode: pass false to snap the shop into focus.
function Scene.setBackdropFaded(faded: boolean)
	backdropFaded = faded
end

-- Contact shadow: without it the steamer looks like it is floating.
local contact = Instance.new("Part")
contact.Shape = Enum.PartType.Cylinder
contact.Size = Vector3.new(0.06, 6.4, 6.4)
contact.CFrame = CFrame.new(STEAMER_ORIGIN + Vector3.new(0, 0.05, 0)) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
contact.Color = Color3.fromRGB(120, 92, 70)
contact.Transparency = 0.72
contact.Material = Enum.Material.SmoothPlastic
contact.Anchored = true
contact.CanCollide = false
contact.CanQuery = false
contact.CanTouch = false
contact.Parent = stage

local baseRig = Models.buildSteamerBase(stage)
local lidRig = Models.buildSteamerLid(stage)

-- The squishy inside the steamer. Rebuilt on every open so each reveal shows
-- the actual shape that was rolled — a banana looks like a banana. The
-- placeholder dumpling just fills the tub before the first open.
local squishyModel = Models.buildSquishy(stage, "dumpling", Color3.fromRGB(226, 190, 142), false)

local function swapSquishy(shape: string?, color: Color3, sparkle: boolean, sizeScale: number)
	squishyModel.rig.folder:Destroy()
	squishyModel = Models.buildSquishy(stage, shape, color, sparkle, sizeScale)
end

-- ---------- the click toy ----------
-- The player's chosen squishy IS the main clicker: it sits centre stage on a
-- big cushion, alone in frame, and squishes with every click. The steamer is
-- off in its nook, out of view until an unbox turns the camera.

local CLICKER_SPOT = ORIGIN + Vector3.new(1.9, 0, 3.0)
-- The cushion's top face is at 0.425; this leaves a clear gap above it, so
-- every squishy floats rather than sinking in.
local CLICKER_REST_Y = 0.58
local CLICKER_SCALE = 1.35 -- centrepiece, so a touch bigger than the reveal size

local cushion = Instance.new("Part")
cushion.Shape = Enum.PartType.Cylinder
cushion.Size = Vector3.new(0.45, 4.4, 4.4)
cushion.CFrame = CFrame.new(ORIGIN + Vector3.new(1.9, 0.2, 3.0)) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
cushion.Color = Color3.fromRGB(243, 200, 210)
cushion.Material = Enum.Material.Fabric
cushion.Anchored = true
cushion.CanCollide = false
cushion.CanQuery = false
cushion.CanTouch = false
cushion.Parent = stage

local clickerModel: Models.SquishyModel? = nil
-- Remembered so the debug menu can rebuild the toy after nudging its facing.
local clickerSpec: { shape: string?, color: Color3, sparkle: boolean, id: string, sizeScale: number }? = nil

-- ---------- spinning the click toy ----------
-- Drag the squishy and it turns on its cushion, then coasts to a stop like a
-- flywheel. Drag deltas are banked here and spent in the render loop: input
-- events fire at their own rate, and a velocity only means something measured
-- against a known frame time.
local RADIANS_PER_PIXEL = 0.015
local SPIN_FRICTION = 1.6 -- how quickly a released spin bleeds off

local spinAngle = 0
local spinVelocity = 0
local spinDragging = false
local spinPending = 0
-- The idle sway steps aside while the squishy is being spun, then eases back.
local swayAmount = 1

-- ---------- cannon state ----------
-- The barrel follows the aim dial live, so the player sees the angle they are
-- choosing before committing to it.
local aimTilt = spring(60, 11)
-- A shot in the air. The squisher itself is the projectile — it leaves the
-- cushion, flies, and comes back — so there is nothing extra to build.
-- Every number in here arrives from the server; none of it is worked out
-- locally, because all of it decides what the shot was worth.
type FlightArc = { fromX: number, toX: number, peak: number, seconds: number, rolling: boolean }

local flight = {
	active = false,
	progress = 1, -- 1 means landed, which is where we start
	seconds = 1, -- how long the ANIMATION runs, not the simulated flight
	simSeconds = 1, -- how long the simulated flight took
	distance = 0, -- game studs the shot covers in total
	arcs = {} :: { FlightArc },
	-- Cumulative simulated time at the START of each arc, so a playback time
	-- can be turned into a position without walking the whole list twice.
	arcStarts = {} :: { number },
	flown = 0, -- game studs covered so far, for the ticking readout
	height = 0, -- game studs off the ground right now
	speed = 0, -- game studs per second, forward
	bounced = 0, -- skips completed, so the UI can call them out
	peakFraction = 1, -- peak of the CURRENT hop, for judging ground contact
	holdUntil = 0, -- keeps the chase camera on a beat past the landing
}
-- 0 = the fixed stage camera, 1 = riding along behind the shot.
local flightCam = 0

-- Where the shot is at a given moment of SIMULATED time. The arcs come from
-- the server, and this reproduces the same curve it scored against — a
-- parabola per skip, meeting the ground at both ends, then a decelerating
-- roll. Redrawn here purely to animate; the server's copy is the one that
-- decided what was collected, so the two drifting apart is a cosmetic bug.
local function flightAt(simTime: number): (number, number, number)
	local arcs = flight.arcs
	for index, arc in arcs do
		local started = flight.arcStarts[index] or 0
		if simTime <= started + arc.seconds or index == #arcs then
			local span = arc.toX - arc.fromX
			if arc.seconds <= 0 or span <= 0 then
				return arc.toX, 0, 0
			end
			local along = math.clamp((simTime - started) / arc.seconds, 0, 1)
			if arc.rolling then
				-- Decelerating, so it covers ground fastest at the start.
				local eased = along * (2 - along)
				return arc.fromX + span * eased, 0, (span / arc.seconds) * (1 - along) * 2
			end
			return arc.fromX + span * along, arc.peak * 4 * along * (1 - along), span / arc.seconds
		end
	end
	return flight.distance, 0, 0
end

-- How high THIS hop goes. Shots peak in the thousands of studs early and in
-- single digits by the last skip, so anything that wants to know "how near the
-- ground are we" has to measure against the current hop rather than against
-- the flight as a whole.
local function flightArcPeak(x: number): number
	for _, arc in flight.arcs do
		if x <= arc.toX then
			return arc.peak
		end
	end
	return 0
end

-- ---------- lights and particles ----------

-- Restrained on purpose: the first pass at these numbers (Brightness 2.4,
-- heavy bloom) blew the pale backdrop out to pure white and the whole stage
-- vanished into glow. If it ever looks foggy-bright again, suspect these
-- before suspecting the models.
Lighting.Ambient = Color3.fromRGB(96, 90, 86)
Lighting.OutdoorAmbient = Color3.fromRGB(112, 105, 99)
Lighting.Brightness = 1.15
Lighting.ClockTime = 14.2
Lighting.GeographicLatitude = 8
Lighting.GlobalShadows = true
Lighting.FogEnd = 100000

local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.3
bloom.Size = 18
bloom.Threshold = 1.75 -- only genuinely emissive things (neon rays) may glow
bloom.Parent = Lighting

local keyLightHost = block(Vector3.new(0.2, 0.2, 0.2), ORIGIN + Vector3.new(5, 9, 9), BACKDROP_COLOR)
keyLightHost.Transparency = 1
local keyLight = Instance.new("PointLight")
keyLight.Brightness = 0.45
keyLight.Range = 44
keyLight.Color = Color3.fromRGB(255, 240, 214)
keyLight.Shadows = false
keyLight.Parent = keyLightHost

-- Matching key light for the steamer nook, so the unbox view isn't dimmer.
local nookLightHost = block(Vector3.new(0.2, 0.2, 0.2), STEAMER_ORIGIN + Vector3.new(6, 9, 5), BACKDROP_COLOR)
nookLightHost.Transparency = 1
local nookLight = Instance.new("PointLight")
nookLight.Brightness = 0.45
nookLight.Range = 44
nookLight.Color = Color3.fromRGB(255, 240, 214)
nookLight.Shadows = false
nookLight.Parent = nookLightHost

-- Everything that erupts out of the steamer hangs off this one tiny invisible
-- part, which we keep parked at the tub's mouth as the steamer bounces around.
local mouth = block(Vector3.new(0.2, 0.2, 0.2), ORIGIN + Vector3.new(0, LID_REST_Y, 0), BACKDROP_COLOR)
mouth.Transparency = 1

-- Kept wispy: at its first size (peaking at 3.2 studs, 42% opaque, rate 7)
-- the steam filled the frame with white haze and read as a rendering bug.
local steam = Instance.new("ParticleEmitter")
steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
steam.Rate = 3
steam.Lifetime = NumberRange.new(1.4, 2.2)
steam.Speed = NumberRange.new(1.2, 2.4)
steam.SpreadAngle = Vector2.new(12, 12)
steam.Acceleration = Vector3.new(0, 2.2, 0)
steam.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.25),
	NumberSequenceKeypoint.new(0.45, 1.1),
	NumberSequenceKeypoint.new(1, 1.7),
})
steam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.18, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})
steam.Rotation = NumberRange.new(0, 360)
steam.RotSpeed = NumberRange.new(-25, 25)
steam.LightEmission = 0.15
steam.EmissionDirection = Enum.NormalId.Top
steam.Parent = mouth

-- Rate 0: this one only ever fires in bursts, on a reveal.
local burst = Instance.new("ParticleEmitter")
burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
burst.Rate = 0
burst.Lifetime = NumberRange.new(0.7, 1.5)
burst.Speed = NumberRange.new(12, 26)
burst.SpreadAngle = Vector2.new(180, 180)
burst.Acceleration = Vector3.new(0, -26, 0)
burst.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.45),
	NumberSequenceKeypoint.new(1, 0),
})
burst.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(1, 1),
})
burst.LightEmission = 0.9
burst.EmissionDirection = Enum.NormalId.Top
burst.Parent = mouth

local glowLight = Instance.new("PointLight")
glowLight.Brightness = 0
glowLight.Range = 30
glowLight.Shadows = true
glowLight.Parent = mouth

-- God rays for the rare pulls: thin neon blades fanned out behind the
-- dumpling, spinning slowly. Bloom does the rest of the work.
local rays: { BasePart } = {}
for _ = 1, 10 do
	local ray = Instance.new("Part")
	ray.Size = Vector3.new(0.24, 8, 0.24)
	ray.Material = Enum.Material.Neon
	ray.Color = Color3.fromRGB(255, 255, 255)
	ray.Transparency = 1
	ray.Anchored = true
	ray.CanCollide = false
	ray.CanQuery = false
	ray.CanTouch = false
	ray.CastShadow = false
	ray.Parent = stage
	table.insert(rays, ray)
end

-- ---------- sound ----------

local function newSound(volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local clickSound = newSound(0.11)
local openSound = newSound(0.38)
local lastClickSound = 0

-- Every squishy gets its own squish noise: the base sound comes from what the
-- shape is made of, and a hash of the id detunes the pitch so no two squishies
-- sound quite alike.
local clickerSound = newSound(0.3)
local clickerBasePitch = 1

local SQUISH_SOUNDS: { [string]: { id: string, pitch: number } } = {
	jellycube = { id = "rbxasset://sounds/impact_water.mp3", pitch = 1.5 },
	ball = { id = "rbxasset://sounds/impact_water.mp3", pitch = 1.3 },
	blobfish = { id = "rbxasset://sounds/impact_water.mp3", pitch = 1.1 },
	baby = { id = "rbxasset://sounds/impact_water.mp3", pitch = 1.4 },
	drop = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.1 },
	donut = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.9 },
	default = { id = "rbxasset://sounds/impact_water.mp3", pitch = 1.7 },
}

local function tuneClickerSound(shape: string?, id: string)
	local entry = SQUISH_SOUNDS[shape or "default"] or SQUISH_SOUNDS.default
	local hash = 0
	for i = 1, #id do
		hash = (hash * 31 + string.byte(id, i)) % 1000
	end
	clickerSound.SoundId = entry.id
	clickerBasePitch = entry.pitch + (hash / 1000) * 0.35
end

-- ---------- camera ----------

-- The default camera scripts have to be told to stand down, and the player's
-- own controls with them: there is nothing to walk to in a clicker, and a
-- stray WASD press would only make the character wander off the baseplate.
local player = Players.LocalPlayer

local function releaseControls()
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local module = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not module then
		return false
	end
	local ok = pcall(function()
		local controls = (require(module) :: any):GetControls()
		controls:Disable()
	end)
	return ok
end

task.spawn(function()
	-- PlayerModule is created by Roblox's own scripts, so it may not exist yet
	-- — and in a place with default scripts stripped out it never will. Either
	-- way this must not block the game, so it gets a deadline.
	local deadline = os.clock() + 10
	while os.clock() < deadline do
		if releaseControls() then
			return
		end
		task.wait(0.25)
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	releaseControls()
end)

-- ---------- the animation loop ----------

RunService.RenderStepped:Connect(function(deltaTime)
	-- A long frame hitch would launch the springs into orbit, so cap the step.
	local dt = math.min(deltaTime, 1 / 30)
	elapsed += dt

	advance(squash, dt)
	advance(clickerSquash, dt)
	advance(viewYaw, dt)
	advance(lidLift, dt)
	advance(lidTilt, dt)
	advance(lidSide, dt)
	advance(rise, dt)
	advance(jiggle, dt)
	advance(glow, dt)
	advance(rayGlow, dt)

	lidSpinVelocity *= 1 - math.min(dt * 2.2, 1)
	lidSpin += lidSpinVelocity * dt
	dumplingSpin += dt * 0.85
	shake *= 1 - math.min(dt * 4.5, 1)

	-- The steamer breathes, and rattles harder the closer the bar is to full.
	local tension = progress * progress * 0.1
	local rattle = math.sin(elapsed * 26) * tension
	local bob = math.sin(elapsed * 1.6) * 0.06
	local sq = squash.value

	-- The steamer lives in the nook the camera faces after the 90° left turn.
	-- That camera looks down -X, so its screen-horizontal is the world Z axis:
	-- every sideways motion (rattle, the lid's side-throw) rides Z here, and
	-- lidSide is negated because screen-left for that camera is +Z.
	local baseScale = Vector3.new(1 + sq * 0.13, 1 - sq * 0.19, 1 + sq * 0.13)
	Models.apply(
		baseRig,
		CFrame.new(STEAMER_ORIGIN + Vector3.new(0, bob, rattle))
			* CFrame.fromEulerAnglesXYZ(0, math.sin(elapsed * 0.5) * 0.06, rattle * 0.05),
		baseScale
	)

	-- The lid rides the tub's squashed top, then lags a touch behind it — the
	-- secondary motion is most of what sells the bounce.
	local lidScale = Vector3.new(1 + sq * 0.09, 1 - sq * 0.13, 1 + sq * 0.09)
	local lidY = LID_REST_Y * baseScale.Y + bob + lidLift.value
	Models.apply(
		lidRig,
		CFrame.new(STEAMER_ORIGIN + Vector3.new(0, lidY, rattle - lidSide.value))
			* CFrame.fromEulerAnglesXYZ(lidTilt.value, lidSpin, lidTilt.value * 0.55),
		lidScale
	)

	mouth.CFrame = CFrame.new(STEAMER_ORIGIN + Vector3.new(0, LID_REST_Y * baseScale.Y + bob, rattle))

	-- The squishy sits down inside the tub at rest, hidden by its own walls,
	-- so it needs no showing and hiding — it just climbs out and drops back.
	local risen = rise.value
	local jg = jiggle.value
	local revealScale = squishyModel.sizeScale
	-- Tucked so its very top clears the rim, whatever size and shape it is,
	-- or it pokes up through the closed lid while meant to be a surprise.
	local hiddenY = TUB_TOP_INSIDE - squishyModel.highestY * revealScale
	local squishyY = hiddenY + (DUMPLING_RISEN_Y - hiddenY) * risen
	Models.apply(
		squishyModel.rig,
		CFrame.new(STEAMER_ORIGIN + Vector3.new(0, squishyY + math.sin(elapsed * 3) * 0.08 * risen, 0))
			* CFrame.fromEulerAnglesXYZ(0, dumplingSpin, math.sin(elapsed * 2.2) * 0.05 * risen),
		Vector3.new(1 + jg * 0.18, 1 - jg * 0.22, 1 + jg * 0.18) * revealScale
	)
	local revealFace = squishyModel.billboard
	if revealFace then
		revealFace.Enabled = risen > 0.06
	end

	-- Drag-to-spin: spend whatever the pointer banked this frame, else coast.
	if spinDragging then
		local applied = spinPending
		spinPending = 0
		spinAngle += applied
		-- Smoothed, so one stuttery frame at the moment of release doesn't
		-- decide how hard the squishy was thrown.
		spinVelocity += (applied / dt - spinVelocity) * math.min(dt * 18, 1)
	else
		spinAngle += spinVelocity * dt
		spinVelocity *= 1 - math.min(dt * SPIN_FRICTION, 1)
		if math.abs(spinVelocity) < 0.01 then
			spinVelocity = 0
		end
	end
	local swayTarget = (spinDragging or math.abs(spinVelocity) > 0.25) and 0 or 1
	swayAmount += (swayTarget - swayAmount) * math.min(dt * 4, 1)

	-- The click toy on its cushion: idle breathing, hard squash on clicks.
	-- The barrel tracks the aim dial, and a shot in the air carries the clock.
	advance(aimTilt, dt)
	if flight.active then
		flight.progress += dt / flight.seconds
		if flight.progress >= 1 then
			flight.progress = 1
			flight.active = false
		end
	end

	-- Ground covered so far. Playback runs on SIMULATED time so every hop
	-- keeps its true share of the flight — the first arc is most of it, and
	-- the skips at the end come thick and fast.
	if flight.progress < 1 then
		local simTime = flight.progress * flight.simSeconds
		flight.flown, flight.height, flight.speed = flightAt(simTime)
		flight.peakFraction = flightArcPeak(flight.flown)

		-- Count skips as they happen, so the HUD can shout about them.
		local skips = 0
		for index, arc in flight.arcs do
			if not arc.rolling and flight.flown >= arc.toX and index < #flight.arcs then
				skips += 1
			end
		end
		flight.bounced = skips
	else
		-- Landed: sit exactly on the server's number rather than wherever the
		-- last frame before the finish happened to fall.
		flight.flown = flight.distance
		flight.height = 0
		flight.speed = 0
	end

	-- THE TREADMILL. The squishy runs forward until it reaches its station,
	-- and after that the world slides backwards instead. Everything on the
	-- track goes through rangeSpot, so this one line is the whole illusion.
	scroll = math.max(flight.flown * runScale - STAGE_LEAD_IN, 0)

	-- Where the shot is on the stage this frame. The toy is drawn here and the
	-- chase camera watches it, so both read the position from one place.
	local shotPosition = rangeSpot(flight.flown, flight.height) + Vector3.new(0, MUZZLE_HEIGHT, 0)

	-- Recycle the runway stripes through the scroll window. Modulo on the pool
	-- span means a stripe leaving the near end reappears at the far one, and
	-- the rainbow runs exactly once around the pool so the seam is invisible.
	for index, stripe in trackStripes do
		local along = (index * STRIPE_DEPTH - scroll) % TRACK_SPAN
		stripe.Position = CANNON_ORIGIN + Vector3.new(along, 0.25, 0)
	end

	-- Milestone signs have no fixed home: 1,000,000 studs is wherever the
	-- treadmill currently puts it, and most of them are off-stage most of the
	-- time. Parked out of sight rather than destroyed and rebuilt.
	for _, sign in milestoneSigns do
		local spot = rangeSpot(sign.at, 0)
		local visible = onScreen(spot.X)
		sign.gate.Transparency = visible and 0 or 1
		sign.post.Transparency = visible and 0 or 1
		if visible then
			sign.gate.Position = spot + Vector3.new(0, 0.45, 0)
			sign.post.Position = spot + Vector3.new(0, 3.7, RANGE_HALF_WIDTH + 2)
			sign.sign.Position = spot + Vector3.new(0, 8.2, RANGE_HALF_WIDTH + 2)
		end
	end

	-- Pickups pop as the squishy reaches them. The server already decided
	-- which ones; this is only the moment they disappear.
	for index, at in pickupCollecting do
		if flight.flown >= at then
			local prize = pickupParts[index]
			if prize then
				prize.Transparency = 1
			end
			pickupTaken[index] = true
			pickupCollecting[index] = nil
			kick(clickerSquash, 0.45)
		end
	end

	-- Stream the rest along the treadmill, bobbing so the track doesn't read
	-- as a still photograph.
	for index, prize in pickupParts do
		local entry = pickupField[index]
		if entry and not pickupTaken[index] then
			local spot = rangeSpot(entry.distance, entry.height) + Vector3.new(0, MUZZLE_HEIGHT, 0)
			if onScreen(spot.X) then
				prize.Transparency = entry.vip and 0 or 0.12
				prize.Position = spot + Vector3.new(0, math.sin(elapsed * 2.4 + index) * 0.22, 0)
				prize.CFrame = CFrame.new(prize.Position) * CFrame.fromEulerAnglesXYZ(0, elapsed * 1.6 + index, 0.4)
			else
				prize.Transparency = 1
			end
		elseif entry == nil then
			prize.Transparency = 1
		end
	end

	-- The chase camera leads in and out rather than cutting, and holds a beat
	-- past the landing so the last thing seen is where it came down.
	local chaseWanted = (flight.progress < 1 or elapsed < flight.holdUntil) and 1 or 0
	flightCam += (chaseWanted - flightCam) * math.min(dt * 3.5, 1)

	-- The blur exists to push the toy shop back behind the squisher, but on
	-- the range the distance IS the subject — blurring it would fog out the
	-- far end of the runway, which is the bit worth looking at. So it fades
	-- off as the camera turns right, and off entirely during a flight.
	local towardCannon = math.clamp(-viewYaw.value, 0, 1)
	depthOfField.FarIntensity = backdropFaded and 0.6 * (1 - math.max(towardCannon, flightCam)) or 0

	-- The barrel and its two trim pieces all hang off one pivot, so the mouth
	-- can never drift away from the end of the barrel it belongs to.
	local barrelPivot = CFrame.new(CANNON_ORIGIN + Vector3.new(0, MUZZLE_HEIGHT, 0))
		* CFrame.fromEulerAnglesXYZ(0, 0, aimTilt.value)
	cannonBarrel.CFrame = barrelPivot * CFrame.new(BARREL_LENGTH * 0.5, 0, 0)
	barrelLip.CFrame = barrelPivot * CFrame.new(BARREL_LENGTH - 0.35, 0, 0)
	barrelMouth.CFrame = barrelPivot * CFrame.new(BARREL_LENGTH - 0.1, 0, 0)

	local toy = clickerModel
	-- Where the pets follow. Set by whichever branch below actually draws.
	local toyPosition = CLICKER_SPOT + Vector3.new(0, CLICKER_REST_Y, 0)

	if toy then
		local cs = clickerSquash.value
		local toyScale = Vector3.new(1 + cs * 0.28, 1 - cs * 0.34, 1 + cs * 0.28) * CLICKER_SCALE * toy.sizeScale

		if flight.progress < 1 then
			-- Mid-shot the squisher IS the cannonball: it leaves the cushion,
			-- skips down the track and comes back, so there is no second model
			-- to build and the cushion is visibly empty while it's away.
			--
			-- Tumbling accumulates from progress alone rather than switching
			-- rate per phase, so it never snaps round mid-flight. It rolls
			-- fastest while airborne and settles as the roll takes over.
			local airborne = flight.height > 0.001
			local tumble = flight.progress * math.pi * (airborne and TUMBLE_AIR or TUMBLE_ROLL)

			-- Squashed flat at the moment of each ground contact. Height is in
			-- game studs and shots peak in the thousands, so "near the ground"
			-- has to be measured as a FRACTION of this shot's own peak.
			local nearGround = 1 - math.clamp(flight.height / math.max(flight.peakFraction, 1e-3), 0, 1)
			local impact = nearGround * nearGround * nearGround
			local squashed = Vector3.new(1 + impact * 0.4, 1 - impact * 0.35, 1 + impact * 0.4)

			toyPosition = shotPosition
			Models.apply(
				toy.rig,
				CFrame.new(shotPosition) * CFrame.fromEulerAnglesXYZ(0, 0, -tumble),
				toyScale * squashed
			)
		else
			-- Stood on the cushion by its own underside rather than centred on
			-- a fixed height, so a tall model doesn't sink through it. Using
			-- the live Y scale also means a squash presses down onto the
			-- cushion rather than shrinking away from it.
			local restY = CLICKER_REST_Y - toy.lowestY * toyScale.Y
			toyPosition = CLICKER_SPOT + Vector3.new(0, restY, 0)
			Models.apply(
				toy.rig,
				CFrame.new(CLICKER_SPOT + Vector3.new(0, restY + math.sin(elapsed * 2.1) * 0.05, 0))
					* CFrame.fromEulerAnglesXYZ(0, spinAngle + math.sin(elapsed * 1.3) * 0.08 * swayAmount, 0),
				toyScale
			)
		end
	end

	-- Pets trail the squishy in a line, each one chasing the slot in front of
	-- it. Critically damped springs rather than a fixed offset, so they swing
	-- wide on a turn and stretch out at speed instead of moving as one rigid
	-- object — the lag IS the effect.
	local ahead = toyPosition
	for index, follower in petFollowers do
		if follower.part.Transparency < 1 then
			local target = ahead - Vector3.new(PET_TRAIL_SPACING, 0, 0) + Vector3.new(0, 0.5, 0)
			local pull = (target - follower.position) * PET_STIFFNESS - follower.velocity * PET_DAMPING
			follower.velocity += pull * dt
			follower.position += follower.velocity * dt
			follower.part.Position = follower.position
				+ Vector3.new(0, math.sin(elapsed * 3 + index) * 0.18, math.sin(elapsed * 1.7 + index * 2) * 0.5)
			ahead = follower.position
		end
	end

	glowLight.Brightness = math.max(glow.value, 0)

	-- Rays fan in the Y-Z plane (spinning about X) because the nook camera
	-- looks down -X; pivoting at -X puts them behind the risen squishy.
	local rayAlpha = math.clamp(rayGlow.value, 0, 1)
	local rayPivot = CFrame.new(STEAMER_ORIGIN + Vector3.new(-1.4, DUMPLING_RISEN_Y, 0))
	for index, ray in rays do
		local angle = elapsed * 0.55 + (index / #rays) * math.pi * 2
		local length = math.max(9 * rayAlpha, 0.05)
		ray.Size = Vector3.new(0.24, length, 0.24)
		ray.CFrame = rayPivot * CFrame.fromEulerAnglesXYZ(angle, 0, 0) * CFrame.new(0, length * 0.5 + 1.6, 0)
		ray.Transparency = 1 - rayAlpha * 0.7
	end

	local camera = workspace.CurrentCamera
	if camera then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		-- The camera stands still and TURNS: viewYaw 0 faces the squisher,
		-- 1 is 90° left onto the steamer nook, -1 is 90° right onto the
		-- cannon. (+yaw about Y turns left.) The clamp allows a little past
		-- each end so the spring's overshoot isn't cut off.
		local yaw = math.clamp(viewYaw.value, -1.15, 1.15) * math.rad(90)
		local dir = CFrame.fromEulerAnglesXYZ(0, yaw, 0):VectorToWorldSpace(BASE_LOOK_DIR)
		-- Shake in view space, so it reads as shake from either angle.
		local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
		local jolt = right * ((math.random() - 0.5) * shake) + Vector3.new(0, (math.random() - 0.5) * shake, 0)
		local resting = CFrame.lookAt(CAMERA_POS + jolt, CAMERA_POS + jolt + dir)

		if flightCam > 0.001 then
			-- The whole point of a distance game is watching the distance, so
			-- the camera leaves its stand and travels with the shot: trailing
			-- it, a little above and off to the side, looking slightly ahead so
			-- the ground still to come stays in frame.
			local chasePos = shotPosition + Vector3.new(-CHASE_BACK, CHASE_UP, CHASE_SIDE)
			local chaseLook = shotPosition + Vector3.new(CHASE_LEAD, 0, 0)
			camera.CFrame = resting:Lerp(CFrame.lookAt(chasePos + jolt, chaseLook), flightCam)
		else
			camera.CFrame = resting
		end
		-- A hair of punch-in on every click, too small to notice and too big to
		-- do without.
		camera.FieldOfView = FIELD_OF_VIEW - math.max(sq, clickerSquash.value) * 1.2
	end
end)

-- ---------- what init.client.luau calls ----------

-- Drag the squishy round on its cushion. Called only once the pointer has
-- actually moved, never on a bare press, so ordinary clicking never stops a
-- spin that is already going.
function Scene.dragClicker(deltaPixels: number)
	spinDragging = true
	spinPending += deltaPixels * RADIANS_PER_PIXEL
end

-- Let go: whatever speed it was turning at, it keeps, and winds down.
function Scene.releaseClicker()
	spinDragging = false
end

-- Point the barrel, 0 for the flattest shot and 1 for the steepest. Purely a
-- preview of the aim dial; the server is told the same number and does its own
-- sums with it.
function Scene.setCannonAim(angle: number)
	local degrees = Config.LaunchMinAngle + (Config.LaunchMaxAngle - Config.LaunchMinAngle) * math.clamp(angle, 0, 1)
	aimTilt.target = math.rad(degrees)
end

-- Lay the pickups out from the field the server sent, and RESCALE the track
-- to it. The server sizes a field to the player's own reach, so it is the best
-- available description of the shot about to be taken — using it for both
-- means nothing jumps when the shot actually starts.
function Scene.setLaunchField(field: { PickupEntry })
	pickupField = field
	pickupTaken = {}
	pickupCollecting = {}

	local furthest, highest = 1, 1
	for _, entry in field do
		furthest = math.max(furthest, entry.distance)
		highest = math.max(highest, entry.height)
	end

	-- A full shot should always sweep about TRACK_RUN studs of stage and peak
	-- about STAGE_APEX studs up, whether it travels 300 studs or 300,000. The
	-- stretch cap stops a high, short shot from becoming a needle.
	runScale = TRACK_RUN / furthest
	heightScale = math.min(STAGE_APEX / highest, runScale * MAX_HEIGHT_STRETCH)

	for index, prize in pickupParts do
		local entry = field[index]
		if entry then
			local look = PICKUP_LOOK[entry.kind] or PICKUP_LOOK.tnt
			prize.Color = look.color
			prize.Material = look.material
			-- VIP pickups are bigger and brighter, so a cluster is worth
			-- spotting from the aiming screen and bending a shot towards.
			prize.Size = Vector3.one * look.size * (entry.vip and 1.5 or 1)
			prize.Transparency = 0.12
		else
			-- A shorter field than the pool: park the spares out of sight.
			prize.Transparency = 1
			pickupTaken[index] = true
		end
	end
end

-- Fly the shot the SERVER worked out. Every number here — every hop, how high,
-- which pickups went — arrived in the result payload; this only draws it.
function Scene.playLaunch(plan: {
	distance: number,
	arcs: { FlightArc },
	seconds: number,
	collected: { number },
}): number
	flight.distance = math.max(plan.distance, 0)
	flight.arcs = plan.arcs
	flight.simSeconds = math.max(plan.seconds, 1e-3)

	-- Cumulative start time per arc, worked out once here rather than
	-- re-summed on every frame of playback.
	flight.arcStarts = {}
	local running = 0
	for index, arc in plan.arcs do
		flight.arcStarts[index] = running
		running += arc.seconds
	end

	-- Playback is a compressed version of real time: a maxed shot hangs in the
	-- air for the better part of a minute, which is longer than it is fun, and
	-- a first shot is over in a couple of seconds, which is too quick to read.
	flight.seconds = math.clamp(flight.simSeconds * 0.25, 2.2, 8)
	flight.flown = 0
	flight.height = 0
	flight.speed = 0
	flight.bounced = 0
	flight.progress = 0
	flight.active = true
	flight.holdUntil = elapsed + flight.seconds + 1.1

	-- Queue the pickups to pop as the shot reaches each one.
	pickupCollecting = {}
	for _, index in plan.collected do
		local entry = pickupField[index]
		if entry and not pickupTaken[index] then
			pickupCollecting[index] = entry.distance
		end
	end

	muzzleSmoke:Emit(22)
	openSound.PlaybackSpeed = 0.75
	openSound:Play()
	kick(clickerSquash, 1)
	shake = 0.55

	-- Handed back so the UI can hold its summary until the shot has actually
	-- landed, rather than guessing at how long that takes.
	return flight.seconds
end

-- Live readouts for the flight HUD, in game units. Read rather than pushed, so
-- the HUD can sample them at whatever rate it draws at.
function Scene.flightDistance(): number
	return flight.flown
end

function Scene.flightHeight(): number
	return flight.height
end

function Scene.flightSpeed(): number
	return flight.speed
end

function Scene.flightBounces(): number
	return flight.bounced
end

-- Show the equipped pets and colour them. Passing fewer than the maximum
-- hides the rest; the server owns how many that may be.
function Scene.setPets(colors: { Color3 })
	for index, follower in petFollowers do
		local color = colors[index]
		follower.part.Transparency = color and 0 or 1
		if color then
			follower.part.Color = color
		end
	end
end

-- Turn the camera: "unbox" swings 90° left onto the steamer nook, "cannon"
-- swings 90° right onto the range, anything else back to the squisher.
function Scene.setView(view: string)
	if view == "unbox" then
		viewYaw.target = 1
	elseif view == "cannon" then
		viewYaw.target = -1
	else
		viewYaw.target = 0
	end
end

function Scene.click()
	kick(squash, 1)

	-- Rising pitch as the bar fills. Rate limited so a held-down mouse does not
	-- turn into a machine gun.
	local now = os.clock()
	if now - lastClickSound > 0.05 then
		lastClickSound = now
		if clickerModel then
			clickerSound.PlaybackSpeed = clickerBasePitch + progress * 0.3
			clickerSound:Play()
		else
			clickSound.PlaybackSpeed = 1.2 + progress * 0.6
			clickSound:Play()
		end
	end

	if clickerModel then
		kick(clickerSquash, 1)
	end
end

-- Equip an owned squishy as the click toy on the cushion.
function Scene.setClicker(shape: string?, color: Color3, sparkle: boolean, id: string, sizeScale: number?)
	local previous = clickerModel
	if previous then
		previous.rig.folder:Destroy()
	end
	local scale = sizeScale or 1
	clickerSpec = { shape = shape, color = color, sparkle = sparkle, id = id, sizeScale = scale }

	local toy = Models.buildSquishy(stage, shape, color, sparkle, scale)
	if toy.billboard then
		toy.billboard.Enabled = true
	end
	toy.sparkles.Rate = 6 -- gentler than the reveal sparkle shower
	toy.sparkles.Enabled = sparkle
	clickerModel = toy

	tuneClickerSound(shape, id)
	kick(clickerSquash, 1) -- welcome squish
end

-- Debug: turn the equipped mesh 90° and rebuild it, so its facing can be dialled
-- in by eye. Returns the new yaw and which shape it belongs to, or nil if the
-- equipped squishy is a primitive (those are authored facing the camera).
function Scene.rotateClicker(): (number?, string?)
	local spec = clickerSpec
	if not spec then
		return nil, nil
	end
	local yaw = Models.bumpMeshYaw(spec.shape, 90)
	if not yaw then
		return nil, spec.shape
	end
	Scene.setClicker(spec.shape, spec.color, spec.sparkle, spec.id, spec.sizeScale)
	return yaw, spec.shape
end

-- Debug: tip the equipped mesh forward 90°, for a model whose front is facing
-- the sky rather than the camera.
function Scene.tiltClicker(): (number?, string?)
	local spec = clickerSpec
	if not spec then
		return nil, nil
	end
	local pitch = Models.bumpMeshPitch(spec.shape, 90)
	if not pitch then
		return nil, spec.shape
	end
	Scene.setClicker(spec.shape, spec.color, spec.sparkle, spec.id, spec.sizeScale)
	return pitch, spec.shape
end

-- Debug: shift the equipped mesh, for one that sits too low or too high on the
-- cushion. Same deal — returns the offset to write into MESH_SHAPES.
function Scene.nudgeClicker(delta: Vector3): (Vector3?, string?)
	local spec = clickerSpec
	if not spec then
		return nil, nil
	end
	local offset = Models.nudgeMeshOffset(spec.shape, delta)
	if not offset then
		return nil, spec.shape
	end
	Scene.setClicker(spec.shape, spec.color, spec.sparkle, spec.id, spec.sizeScale)
	return offset, spec.shape
end

function Scene.setProgress(fraction: number)
	progress = math.clamp(fraction, 0, 1)
end

-- tier is the squishy's rarity rank, 1 for Common up to 6 for Mythical. The
-- whole show scales off it, so adding a rarity in Squishies.luau automatically
-- gets a bigger reveal than the one below it.
function Scene.open(
	shape: string?,
	bodyColor: Color3,
	sparkle: boolean,
	rarityColor: Color3,
	tier: number,
	sizeScale: number?
)
	swapSquishy(shape, bodyColor, sparkle, sizeScale or 1)

	-- Up AND well off to the side: a lid that only rises hovers directly over
	-- the squishy and hides it from the camera. It slides left because the
	-- camera aims right of centre, so left is the emptier half of the frame.
	lidLift.target = 2.6 + tier * 0.4
	lidSide.target = -4.4 - tier * 0.25
	lidTilt.target = 0.7
	lidSpinVelocity = 7 + tier * 2.5
	rise.target = 1
	kick(jiggle, 1)
	glow.target = 0.7 + tier * 0.45
	glowLight.Color = rarityColor

	steam:Emit(10 + tier * 4)
	burst.Color = ColorSequence.new(rarityColor)
	burst:Emit(16 + tier * 22)

	squishyModel.sparkles.Enabled = sparkle

	-- Epic and up get the full treatment: rays behind, and a shove to the camera.
	if tier >= 4 then
		rayGlow.target = 1
		for _, ray in rays do
			ray.Color = rarityColor
		end
		shake = 0.28 + tier * 0.07
	end

	openSound.PlaybackSpeed = 1
	openSound:Play()

	-- A fast second pull would otherwise be cut short by the previous reveal's
	-- reset landing on top of it.
	revealToken += 1
	local token = revealToken
	task.delay(REVEAL_SECONDS, function()
		if token ~= revealToken then
			return
		end
		rise.target = 0
		glow.target = 0
		rayGlow.target = 0
		squishyModel.sparkles.Enabled = false

		-- The lid waits for the squishy to be back inside before dropping,
		-- otherwise it closes straight through it.
		task.delay(0.3, function()
			if token ~= revealToken then
				return
			end
			lidLift.target = 0
			lidSide.target = 0
			lidTilt.target = 0
		end)
	end)
end

return Scene
