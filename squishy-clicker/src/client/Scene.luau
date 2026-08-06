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
local Format = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Format"))
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

-- ---------- the launch valley ----------
-- The launcher is the MAIN game now, and it lives a long way from the toy
-- shop rather than 90° off it.
--
-- That distance is not decoration. When all three views shared one camera
-- position, every piece of scenery on the range had to be checked against the
-- shop's frustum by hand, and half the map's dimensions were set by "does
-- this show up in the corner of the toy shop" rather than by what the valley
-- wanted to be. Giving the valley its own camera station 600 studs away
-- removes that whole class of problem: the two sets can never see each other,
-- so the valley can be as wide and as tall as it likes.
local CANNON_ORIGIN = ORIGIN + Vector3.new(0, 0, 600)

-- Where the camera stands to watch the valley, and what it looks at. Well back
-- and high, on a shallow downward angle, so the launcher sits in the lower
-- foreground and the track runs away to a vanishing point behind it — which is
-- the shot the whole map is composed for.
local VALLEY_CAM_POS = CANNON_ORIGIN + Vector3.new(-24, 13, 0)
local VALLEY_CAM_LOOK = CANNON_ORIGIN + Vector3.new(58, 2, 0)
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

-- How much track is drawn ahead of the launcher, in stage studs. The valley
-- camera looks a long way down the course, so this has to cover the view to
-- the vanishing point — anything past it is culled rather than drawn.
local TRACK_SPAN = 220
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
-- purpose: a summon that keeps up perfectly looks welded on.
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

-- 0 = the toy shop, 1 = the launch valley. The valley is where the game
-- starts, so this begins pinned at 1 rather than easing in from the shop.
local viewRange = spring(26, 9)
viewRange.value = 1
viewRange.target = 1

-- True while this file is allowed to drive the camera. Off by default: the
-- player is stood on the island and the character camera owns the view until
-- they open a close-up or fire a shot.
local sceneDrivesCamera = false
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
-- Everything this file builds lives under Workspace.Map, sorted into folders
-- by what it is. That is worth the few extra lines: the map is a couple of
-- thousand parts generated at runtime, and a flat folder of them is unusable
-- in the Explorer when something needs finding.

-- Named apart from the server's Workspace.Map on purpose: that one is the
-- island players walk on, this one is the per-player animation rig sitting
-- 500 studs above it. Two folders called Map would be a genuine trap.
local stage = Instance.new("Folder")
stage.Name = "LaunchStage"
stage.Parent = workspace

local function group(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = stage
	return folder
end

local valleyFolder = group("Valley") -- ground, canyon walls, distance ladder
local baseFolder = group("Base") -- the lobby: paths, stalls, catapults
local propsFolder = group("Props") -- trees, rocks, crates, trucks

local function block(size: Vector3, position: Vector3, color: Color3, parent: Instance?): Part
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
	part.Parent = parent or stage
	return part
end

-- The classic Roblox stud top, which is most of what makes the reference's
-- ground read as ground rather than as a flat green plane.
local function studded(part: BasePart): BasePart
	part.TopSurface = Enum.SurfaceType.Studs
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

-- A wide grass valley running between stepped red canyon walls, under open
-- sky, with the distance painted flat on the ground and shrinking away to a
-- vanishing point. Nothing caps the far end: in a game about distance, a wall
-- to stop at would be the wrong idea.
local VALLEY_HALF_WIDTH = 26 -- grass, from the centre line out
local TRACK_HALF_WIDTH = 17 -- the mown strip the distance markers sit on
local RANGE_DRAWN = TRACK_SPAN

-- Straight off the reference. The canyon is a muted brick rather than the
-- pink it used to be, and the field is a bright lime with a slightly deeper
-- mown strip down the middle for the track.
local GRASS_COLOR = Color3.fromRGB(150, 226, 84)
local GRASS_DARK = Color3.fromRGB(130, 210, 80)
local CANYON_COLOR = Color3.fromRGB(180, 80, 80)
local CANYON_TOP = Color3.fromRGB(130, 210, 80)
local PATH_COLOR = Color3.fromRGB(210, 110, 60)
local WOOD_COLOR = Color3.fromRGB(150, 104, 62)

-- The valley floor. One long slab, wide enough that the canyon walls are
-- scenery rather than fences.
local grass = block(
	Vector3.new(RANGE_DRAWN + 80, 1, VALLEY_HALF_WIDTH * 2),
	CANNON_ORIGIN + Vector3.new(RANGE_DRAWN * 0.5 - 20, -0.5, 0),
	GRASS_COLOR,
	valleyFolder
)
grass.Material = Enum.Material.Plastic
studded(grass)

-- A slightly darker mown strip down the middle, so the track reads as a track
-- without needing a painted road on it.
local mown = block(
	Vector3.new(RANGE_DRAWN + 80, 1, TRACK_HALF_WIDTH * 2),
	CANNON_ORIGIN + Vector3.new(RANGE_DRAWN * 0.5 - 20, -0.46, 0),
	GRASS_DARK,
	valleyFolder
)
mown.Material = Enum.Material.Plastic
studded(mown)

-- ---------- the canyon walls ----------
-- Stepped terraces of red rock either side, each step capped with grass, in
-- the blocky style of the reference. Built once at full length rather than
-- recycled: they are pure silhouette, and a seam sliding past at the edge of
-- frame would be more noticeable than the repetition is.
local CANYON_STEPS = 5
local CANYON_STEP_HEIGHT = 5
local CANYON_STEP_DEPTH = 6

-- Kept so a world change can repaint them; nothing else touches these.
local canyonFaces: { BasePart } = {}
local canyonLips: { BasePart } = {}

for side = -1, 1, 2 do
	for step = 1, CANYON_STEPS do
		local outward = VALLEY_HALF_WIDTH + (step - 1) * CANYON_STEP_DEPTH
		local height = step * CANYON_STEP_HEIGHT

		local face = block(
			Vector3.new(RANGE_DRAWN + 80, height, CANYON_STEP_DEPTH),
			CANNON_ORIGIN + Vector3.new(RANGE_DRAWN * 0.5 - 20, height * 0.5, side * (outward + CANYON_STEP_DEPTH * 0.5)),
			CANYON_COLOR,
			valleyFolder
		)
		face.Material = Enum.Material.Sandstone
		table.insert(canyonFaces, face)

		-- The grassy lip on top of each terrace, which is what makes the
		-- reference's cliffs read as land rather than as a red wall.
		local lip = block(
			Vector3.new(RANGE_DRAWN + 80, 0.8, CANYON_STEP_DEPTH),
			CANNON_ORIGIN + Vector3.new(RANGE_DRAWN * 0.5 - 20, height + 0.4, side * (outward + CANYON_STEP_DEPTH * 0.5)),
			CANYON_TOP,
			valleyFolder
		)
		lip.Material = Enum.Material.Plastic
		studded(lip)
		table.insert(canyonLips, lip)
	end
end

-- ---------- the base ----------
-- The lobby at the foot of the cannon: a dirt path network, a row of market
-- stalls, and everybody else's catapults lined up along it. This is where the
-- camera sits between shots, so it is what the player is looking at whenever
-- they are not watching something fly.
--
-- All of it is static rather than on the treadmill, which is safe because it
-- lives BEHIND the launch pad: once a shot is away the chase camera is already
-- past it, so it never appears to follow the squishy down the track.
-- The valley camera stands at the pad looking down the track, so the base has
-- to FLANK that view rather than sit behind it: anything much further back
-- than the camera is simply never seen. Stalls and catapults therefore line
-- the banks either side of the near track, between the mown strip and the
-- canyon, which is also how the reference arranges them.
local BASE_BACK = -40 -- where the approach path starts
local BASE_BANK = (TRACK_HALF_WIDTH + VALLEY_HALF_WIDTH) * 0.5 -- the strip they stand on
local PATH_WIDTH = 9

-- Ground paint. Sits a hair above the field so it never z-fights with it.
local function paint(size: Vector3, centre: Vector3, color: Color3): Part
	local part = block(size, centre, color, baseFolder)
	part.Material = Enum.Material.Plastic
	return studded(part) :: Part
end

-- A cross path just in front of the pad, and an approach running back down the
-- middle to it. The approach STOPS at the pad — past that the track is green,
-- which is what makes the orange read as "the bit you stand on".
paint(
	Vector3.new(PATH_WIDTH, 0.4, BASE_BANK * 2 + 8),
	CANNON_ORIGIN + Vector3.new(-11, 0.22, 0),
	PATH_COLOR
)
paint(
	Vector3.new(math.abs(BASE_BACK) + 2, 0.4, PATH_WIDTH),
	CANNON_ORIGIN + Vector3.new(BASE_BACK * 0.5, 0.22, 0),
	PATH_COLOR
)
-- Spurs out to each bank, so the stalls and the catapults are connected to
-- the path rather than dropped on the grass beside it.
for _, side in { -1, 1 } do
	paint(
		Vector3.new(PATH_WIDTH * 0.7, 0.4, BASE_BANK - 2),
		CANNON_ORIGIN + Vector3.new(-11, 0.22, side * (BASE_BANK * 0.5 + 1)),
		PATH_COLOR
	)
end

-- ---------- market stalls ----------
-- Wooden counter, four posts, and a red-and-white striped awning, which is the
-- whole silhouette in the reference. Built facing the path they stand on.
local function stall(at: Vector3, facing: number)
	local frame = CFrame.new(at) * CFrame.Angles(0, facing, 0)
	local function piece(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): Part
		local part = block(size, at, color, baseFolder)
		part.CFrame = frame * CFrame.new(offset)
		part.Material = material
		return part
	end

	piece(Vector3.new(9, 1.2, 1.6), Vector3.new(0, 2.6, -1.6), Color3.fromRGB(196, 140, 86), Enum.Material.WoodPlanks)
	piece(Vector3.new(9, 3, 3.4), Vector3.new(0, 1.5, 0), Color3.fromRGB(150, 104, 62), Enum.Material.WoodPlanks)
	for _, side in { -4.2, 4.2 } do
		piece(Vector3.new(0.6, 6, 0.6), Vector3.new(side, 3, -1.4), WOOD_COLOR, Enum.Material.Wood)
		piece(Vector3.new(0.6, 6, 0.6), Vector3.new(side, 3, 1.4), WOOD_COLOR, Enum.Material.Wood)
	end

	-- Striped awning: alternating blocks rather than a texture, so it reads at
	-- distance and needs no uploaded asset.
	for strip = -4, 4 do
		piece(
			Vector3.new(1, 0.5, 5),
			Vector3.new(strip, 6.3, 0),
			strip % 2 == 0 and Color3.fromRGB(232, 74, 74) or Color3.fromRGB(250, 246, 240),
			Enum.Material.SmoothPlastic
		)
	end
end

-- Turned to face the path, so the counters point inward at the player.
for index = 1, 3 do
	stall(CANNON_ORIGIN + Vector3.new(-22 + (index - 1) * 15, 0, -BASE_BANK), math.pi)
end

-- ---------- the catapult row ----------
-- Everybody else's launchers, lined up along the far side of the base. They
-- are scenery — the player's own cannon is the real one — but a row of them is
-- what makes the place read as somewhere other people also launch from.
local function catapult(at: Vector3)
	local function piece(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): Part
		local part = block(size, at + offset, color, baseFolder)
		part.Material = material
		return part
	end

	piece(Vector3.new(7, 0.8, 5), Vector3.new(0, 0.4, 0), Color3.fromRGB(178, 132, 84), Enum.Material.WoodPlanks)
	for _, side in { -2.2, 2.2 } do
		local leg = piece(Vector3.new(0.8, 6.5, 0.8), Vector3.new(-1, 3.2, side), WOOD_COLOR, Enum.Material.Wood)
		leg.CFrame = CFrame.new(at + Vector3.new(-1, 3.2, side)) * CFrame.Angles(0, 0, math.rad(18))
	end
	local arm = piece(Vector3.new(8, 0.7, 0.9), Vector3.new(0.5, 5.2, 0), Color3.fromRGB(196, 140, 86), Enum.Material.WoodPlanks)
	arm.CFrame = CFrame.new(at + Vector3.new(0.5, 5.2, 0)) * CFrame.Angles(0, 0, math.rad(-28))
	piece(Vector3.new(1.8, 1.4, 1.8), Vector3.new(4, 7.2, 0), Color3.fromRGB(120, 150, 210), Enum.Material.SmoothPlastic)
end

for index = 1, 4 do
	catapult(CANNON_ORIGIN + Vector3.new(-24 + (index - 1) * 13, 0, BASE_BANK))
end

-- ---------- ground signage ----------
-- Text printed flat on the ground, the way the reference marks its launch pad.
-- A part with a Top-facing SurfaceGui rather than a Decal, so there is nothing
-- to upload and the wording can be changed in one line here.
local function groundText(size: Vector3, centre: Vector3, text: string, color: Color3, rotate: boolean)
	local plate = block(size, centre, GRASS_COLOR, baseFolder)
	plate.Transparency = 1

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.PixelsPerStud = 28
	surface.Parent = plate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(52, 34, 28)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	-- Printed to be read from the base looking down the track, not from the
	-- far end looking back.
	label.Rotation = rotate and 180 or 0
	label.Parent = surface
end

groundText(
	Vector3.new(15, 0.16, TRACK_HALF_WIDTH * 2.2),
	CANNON_ORIGIN + Vector3.new(13, 0.3, 0),
	"🚀 LAUNCH ZONE 🚀",
	Color3.fromRGB(238, 62, 62),
	true
)

-- Flat cylinders, for the launch pad and its island.
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

-- ---------- the distance ladder ----------
-- The numbers painted flat on the grass, shrinking away down the valley. This
-- is the single most important thing on the map: it is the only thing telling
-- the player how far they have got, and perspective does the rest.
--
-- An infinite track cannot have fixed signs, so this is a POOL that shows a
-- sliding window of round numbers. The step is chosen per field, so at 300
-- studs of reach it counts in 50s and at 300,000 it counts in 50,000s — the
-- ladder always reads the same however strong the player is.
local LADDER_RUNGS = 14
local ladderStep = 50

type Rung = { plate: BasePart, label: TextLabel }
local ladder: { Rung } = {}
for _ = 1, LADDER_RUNGS do
	local plate = block(Vector3.new(9, 0.12, TRACK_HALF_WIDTH * 1.7), CANNON_ORIGIN, GRASS_DARK)
	plate.Transparency = 1 -- the plate is only a surface to print on

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Top
	surface.PixelsPerStud = 26
	surface.AlwaysOnTop = false
	surface.Parent = plate

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(48, 40, 34)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Rotation = 180 -- printed to be read from the launcher, not from the far end
	label.Parent = surface

	table.insert(ladder, { plate = plate, label = label })
end

-- A round-ish step for the current scale: the ladder should show roughly ten
-- rungs across the visible track whatever the numbers are, and it should show
-- them as 50s and 500s rather than as 47s and 468s.
local function niceStep(rough: number): number
	local magnitude = 10 ^ math.floor(math.log(math.max(rough, 1), 10))
	for _, multiple in { 1, 2, 5, 10 } do
		if magnitude * multiple >= rough then
			return magnitude * multiple
		end
	end
	return magnitude * 10
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

	local gate = block(Vector3.new(1.2, 0.2, TRACK_HALF_WIDTH * 2), CANNON_ORIGIN, Color3.fromRGB(255, 255, 255))
	gate.Material = Enum.Material.SmoothPlastic

	table.insert(milestoneSigns, {
		at = milestone.at,
		gate = gate,
		post = block(Vector3.new(0.5, 9, 0.5), CANNON_ORIGIN, Color3.fromRGB(250, 248, 244)),
		sign = floatingLabel(CANNON_ORIGIN, ("%s studs"):format(milestone.name), color, 190, 48),
	})
end

-- Signs over the base, so the two halves of it name themselves. Placed here
-- rather than up with the rest of the base because floatingLabel is only in
-- scope from this point on.
floatingLabel(
	CANNON_ORIGIN + Vector3.new(-14, 11, -BASE_BANK),
	"🏠 Your Base",
	Color3.fromRGB(252, 214, 132),
	200,
	46
)
floatingLabel(
	CANNON_ORIGIN + Vector3.new(-11, 11, BASE_BANK),
	"🎪 Launch Row",
	Color3.fromRGB(198, 244, 158),
	200,
	46
)

-- ---------- scenery ----------
-- Trees, bushes, crates, logs and the odd truck scattered up both banks of the
-- valley. Fixed geometry rather than treadmill-recycled: the eye reads the
-- ladder and the canyon for motion, and props sliding past would only compete
-- with them. Seeded, so the same valley is laid out identically every run.
local rangeRandom = Random.new(19)

local function tree(at: Vector3, scale: number)
	local trunk =
		block(Vector3.new(0.9 * scale, 3 * scale, 0.9 * scale), at + Vector3.new(0, 1.5 * scale, 0), WOOD_COLOR, propsFolder)
	trunk.Material = Enum.Material.Wood
	-- Three shrinking slabs rather than a cone: the reference's trees are
	-- stacked blocks, and it reads better at a distance than a smooth shape.
	for tier = 0, 2 do
		local width = (5 - tier * 1.3) * scale
		local leaf = block(
			Vector3.new(width, 1.6 * scale, width),
			at + Vector3.new(0, (3.4 + tier * 1.4) * scale, 0),
			tier == 0 and Color3.fromRGB(96, 186, 76) or Color3.fromRGB(120, 208, 92),
			propsFolder
		)
		leaf.Material = Enum.Material.Plastic
		studded(leaf)
	end
end

local function crate(at: Vector3, size: number)
	local box = block(Vector3.new(size, size, size), at + Vector3.new(0, size * 0.5, 0), Color3.fromRGB(198, 132, 74))
	box.Material = Enum.Material.WoodPlanks
end

local function logPile(at: Vector3)
	for index = 0, 2 do
		local piece = Instance.new("Part")
		piece.Shape = Enum.PartType.Cylinder
		piece.Size = Vector3.new(3.4, 1.1, 1.1)
		piece.CFrame = CFrame.new(at + Vector3.new(0, 0.55 + (index > 1 and 1 or 0), (index % 2) * 1.2))
		piece.Color = WOOD_COLOR
		piece.Material = Enum.Material.Wood
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Parent = stage
	end
end

local function truck(at: Vector3)
	local body = block(Vector3.new(5, 2, 2.6), at + Vector3.new(0, 1.6, 0), Color3.fromRGB(214, 74, 92))
	body.Material = Enum.Material.SmoothPlastic
	block(Vector3.new(2, 1.5, 2.4), at + Vector3.new(1.4, 3.2, 0), Color3.fromRGB(122, 158, 226))
	for _, corner in { Vector3.new(-1.6, 0.7, 1.4), Vector3.new(1.6, 0.7, 1.4), Vector3.new(-1.6, 0.7, -1.4), Vector3.new(1.6, 0.7, -1.4) } do
		block(Vector3.new(1.4, 1.4, 0.6), at + corner, Color3.fromRGB(58, 52, 56))
	end
end

for index = 1, 26 do
	local side = index % 2 == 0 and 1 or -1
	local along = rangeRandom:NextNumber(-14, RANGE_DRAWN + 40)
	-- Out on the banks, clear of the mown strip the numbers are printed on.
	local out = side * rangeRandom:NextNumber(TRACK_HALF_WIDTH + 3, VALLEY_HALF_WIDTH - 2)
	local at = CANNON_ORIGIN + Vector3.new(along, 0, out)

	local roll = rangeRandom:NextNumber()
	if roll < 0.42 then
		tree(at, rangeRandom:NextNumber(0.8, 1.5))
	elseif roll < 0.6 then
		local size = rangeRandom:NextNumber(2.2, 3.6)
		local bush = block(Vector3.new(size, size * 0.7, size), at + Vector3.new(0, size * 0.35, 0), Color3.fromRGB(104, 196, 80))
		bush.Material = Enum.Material.Grass
	elseif roll < 0.76 then
		crate(at, rangeRandom:NextNumber(1.6, 2.6))
	elseif roll < 0.9 then
		logPile(at)
	else
		truck(at)
	end
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

-- ---------- summoned squishies ----------
-- The squishies ARE the pets: up to three trail along behind, drawn as their
-- REAL models rather than as stand-in spheres, because seeing which one you
-- brought is the whole point of summoning it.
--
-- Springs rather than AlignPosition/AlignOrientation: those are physics
-- constraints needing unanchored parts with a network owner, and this entire
-- stage is anchored client-side geometry with no character and no physics
-- ownership anywhere in it. Springs give the same lagging, overshooting follow
-- and are what the rest of this file already uses.
local FOLLOW_SPACING = 2.4 -- stage studs of lag between one summon and the next
local FOLLOW_SCALE = 0.6 -- summons are smaller than the squisher itself

type Follower = { model: Models.SquishyModel, position: Vector3, velocity: Vector3 }
local followers: { Follower } = {}

-- ---------- the lobby ----------
-- A deck at the foot of the launcher. There is no walkable avatar in this
-- game — controls are disabled and the camera is scriptable — so the lobby is
-- somewhere the camera SITS rather than somewhere a character stands: you look
-- out over the valley from it between your own shots and watch everyone
-- else's fly past.
local LOBBY_COLOR = Color3.fromRGB(206, 158, 108)
local LOBBY_RAIL = Color3.fromRGB(160, 112, 68)

local lobbyDeck = block(Vector3.new(22, 1, 30), CANNON_ORIGIN + Vector3.new(-20, 0.5, 0), LOBBY_COLOR)
lobbyDeck.Material = Enum.Material.WoodPlanks
block(Vector3.new(22, 0.4, 30), CANNON_ORIGIN + Vector3.new(-20, 1.1, 0), Color3.fromRGB(226, 182, 132)).Material =
	Enum.Material.WoodPlanks

-- A rail along the front edge, so the deck reads as a viewing platform rather
-- than as a raised patch of floor.
for _, side in { -1, 1 } do
	block(Vector3.new(22, 0.4, 0.5), CANNON_ORIGIN + Vector3.new(-20, 3.2, side * 15), LOBBY_RAIL)
	for post = -2, 2 do
		block(Vector3.new(0.5, 2.4, 0.5), CANNON_ORIGIN + Vector3.new(-20 + post * 5, 2.2, side * 15), LOBBY_RAIL)
	end
end

-- Benches facing down the valley.
for _, offset in { -8, 0, 8 } do
	block(Vector3.new(3, 0.5, 6), CANNON_ORIGIN + Vector3.new(-24, 2.3, offset), LOBBY_RAIL)
	block(Vector3.new(0.6, 1.6, 6), CANNON_ORIGIN + Vector3.new(-25.4, 2.9, offset), LOBBY_RAIL)
end

-- ---------- other players' shots ----------
-- Every launch in the server is broadcast, and the lobby draws them.
--
-- Each ghost gets its OWN scale rather than the local player's, so a shot ten
-- times stronger than yours doesn't leave the frame in the first half second
-- and a shot a tenth of it doesn't crawl. Every ghost therefore covers about
-- the same stretch of track whatever it really flew — the real number is on
-- the name tag, which is the honest place for it. They also ignore the
-- treadmill scroll entirely, so your own shot never drags them along with it.
type Ghost = {
	part: BasePart,
	label: TextLabel,
	arcs: { FlightArc },
	arcStarts: { number },
	simSeconds: number,
	seconds: number,
	progress: number,
	runScale: number,
	heightScale: number,
	lane: number,
	active: boolean,
}
local ghosts: { Ghost } = {}
local nextGhost = 1

for index = 1, Config.LobbyMaxGhosts do
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * 1.8
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Parent = stage

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 160, 0, 34)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(48, 40, 34)
	label.TextStrokeTransparency = 0.1
	label.TextScaled = true
	label.Parent = gui

	table.insert(ghosts, {
		part = part,
		label = label,
		arcs = {},
		arcStarts = {},
		simSeconds = 1,
		seconds = 1,
		progress = 1,
		runScale = 1,
		heightScale = 1,
		-- Spread across the width of the track so two ghosts in the air at
		-- once are visibly two shots rather than one flickering one.
		lane = (index - (Config.LobbyMaxGhosts + 1) / 2) * 3.5,
		active = false,
	})
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
	local box = block(Vector3.new(1.3, 1.3, 1.3), CANNON_ORIGIN + spot + Vector3.new(0, 1.1, 0), Color3.fromRGB(228, 118, 58))
	box.Material = Enum.Material.WoodPlanks
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
-- Early afternoon: high enough for a bright sky, off-noon enough that the sun
-- is at an angle and everything on the map casts a readable shadow.
Lighting.ClockTime = 14
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

-- The player walks around a real island now, so the default controls and the
-- default camera stay exactly as Roblox made them. This file only BORROWS the
-- camera — for a flight, or for one of the close-up views — and hands it
-- straight back afterwards.
--
-- That handing-back is the whole trick. An earlier version pinned the camera
-- to Scriptable forever, which is fine when there is nothing to walk to and
-- immediately wrong once there is: the character would move and the view
-- would not.
local player = Players.LocalPlayer

-- ---------- the animation loop ----------

RunService.RenderStepped:Connect(function(deltaTime)
	-- A long frame hitch would launch the springs into orbit, so cap the step.
	local dt = math.min(deltaTime, 1 / 30)
	elapsed += dt

	advance(squash, dt)
	advance(clickerSquash, dt)
	advance(viewYaw, dt)
	advance(viewRange, dt)
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

	-- The distance ladder. Rungs sit on multiples of ladderStep in GAME studs,
	-- and the window of multiples currently on screen slides as the shot
	-- travels — so the numbers count up past the player rather than the track
	-- being a fixed set of signs.
	local firstRung = math.floor(scroll / (ladderStep * runScale)) + 1
	for index, rung in ladder do
		local at = (firstRung + index - 1) * ladderStep
		local spot = rangeSpot(at, 0)
		if onScreen(spot.X) and at > 0 then
			rung.plate.Position = spot + Vector3.new(0, 0.08, 0)
			rung.label.Text = ("%s Studs"):format(Format.abbreviate(at))
			rung.label.TextTransparency = 0
		else
			rung.label.TextTransparency = 1
		end
	end

	-- Milestone gates have no fixed home: 1,000,000 studs is wherever the
	-- treadmill currently puts it, and most of them are off-stage most of the
	-- time. Parked out of sight rather than destroyed and rebuilt.
	for _, sign in milestoneSigns do
		local spot = rangeSpot(sign.at, 0)
		local visible = onScreen(spot.X)
		sign.gate.Transparency = visible and 0 or 1
		sign.post.Transparency = visible and 0 or 1
		if visible then
			sign.gate.Position = spot + Vector3.new(0, 0.5, 0)
			sign.post.Position = spot + Vector3.new(0, 4.7, TRACK_HALF_WIDTH + 2)
			sign.sign.Position = spot + Vector3.new(0, 10.5, TRACK_HALF_WIDTH + 2)
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

	-- The blur exists to push the toy shop back behind the squisher, but in
	-- the valley the distance IS the subject — blurring it would fog out the
	-- far end of the track, which is the bit worth looking at. So it fades off
	-- as the camera travels out there, and off entirely during a flight.
	local away = math.max(math.clamp(viewRange.value, 0, 1), flightCam)
	depthOfField.FarIntensity = backdropFaded and 0.6 * (1 - away) or 0

	-- The barrel and its two trim pieces all hang off one pivot, so the mouth
	-- can never drift away from the end of the barrel it belongs to.
	local barrelPivot = CFrame.new(CANNON_ORIGIN + Vector3.new(0, MUZZLE_HEIGHT, 0))
		* CFrame.fromEulerAnglesXYZ(0, 0, aimTilt.value)
	cannonBarrel.CFrame = barrelPivot * CFrame.new(BARREL_LENGTH * 0.5, 0, 0)
	barrelLip.CFrame = barrelPivot * CFrame.new(BARREL_LENGTH - 0.35, 0, 0)
	barrelMouth.CFrame = barrelPivot * CFrame.new(BARREL_LENGTH - 0.1, 0, 0)

	local toy = clickerModel
	-- What the summons follow. Deliberately the CUSHION, not wherever the
	-- squisher happens to be: mid-shot the squisher is the cannonball, 600
	-- studs away in the valley, and summons chasing it would streak across the
	-- whole map at launch. They stay home and wait.
	local summonAnchor = CLICKER_SPOT + Vector3.new(0, CLICKER_REST_Y, 0)

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
			summonAnchor = CLICKER_SPOT + Vector3.new(0, restY, 0)
			Models.apply(
				toy.rig,
				CFrame.new(CLICKER_SPOT + Vector3.new(0, restY + math.sin(elapsed * 2.1) * 0.05, 0))
					* CFrame.fromEulerAnglesXYZ(0, spinAngle + math.sin(elapsed * 1.3) * 0.08 * swayAmount, 0),
				toyScale
			)
		end
	end

	-- Summons trail the squisher in a line, each one chasing the slot in front of
	-- it. Critically damped springs rather than a fixed offset, so they swing
	-- wide on a turn and stretch out at speed instead of moving as one rigid
	-- object — the lag IS the effect.
	local ahead = summonAnchor
	for index, follower in followers do
		local target = ahead - Vector3.new(FOLLOW_SPACING, 0, 0)
		local pull = (target - follower.position) * PET_STIFFNESS - follower.velocity * PET_DAMPING
		follower.velocity += pull * dt
		follower.position += follower.velocity * dt

		local model = follower.model
		local scale = FOLLOW_SCALE * model.sizeScale
		-- Stood on its own underside like the squisher is, so a tall summon
		-- doesn't sink into the ground it's bobbing over.
		local lift = -model.lowestY * scale
		Models.apply(
			model.rig,
			CFrame.new(
				follower.position
					+ Vector3.new(0, lift + math.sin(elapsed * 3 + index) * 0.18, math.sin(elapsed * 1.7 + index * 2) * 0.6)
			) * CFrame.fromEulerAnglesXYZ(0, elapsed * 0.7 + index, 0),
			Vector3.one * scale
		)
		ahead = follower.position
	end

	-- Other players' shots. Each runs on its own clock and its own scale, so
	-- they neither share the treadmill nor fight each other for the frame.
	for _, ghost in ghosts do
		if ghost.active then
			ghost.progress += dt / ghost.seconds
			if ghost.progress >= 1 then
				ghost.progress = 1
				ghost.active = false
				ghost.part.Transparency = 1
				ghost.label.Text = ""
			else
				local simTime = ghost.progress * ghost.simSeconds
				local x, y = 0, 0
				for index, arc in ghost.arcs do
					local started = ghost.arcStarts[index] or 0
					if simTime <= started + arc.seconds or index == #ghost.arcs then
						local span = arc.toX - arc.fromX
						local along = arc.seconds > 0 and math.clamp((simTime - started) / arc.seconds, 0, 1) or 1
						x = arc.fromX + span * along
						y = arc.rolling and 0 or arc.peak * 4 * along * (1 - along)
						break
					end
				end
				ghost.part.Position = CANNON_ORIGIN
					+ Vector3.new(x * ghost.runScale, y * ghost.heightScale + MUZZLE_HEIGHT, ghost.lane)
			end
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
		-- Borrowed only while there is something to show: a shot in the air,
		-- or a close-up view the player opened. The rest of the time the
		-- character owns it and this hands it straight back.
		local borrowed = sceneDrivesCamera or flight.progress < 1 or elapsed < flight.holdUntil
		if not borrowed then
			if camera.CameraType == Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Custom
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					camera.CameraSubject = humanoid
				end
			end
			return
		end

		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		-- The camera stands still and TURNS: viewYaw 0 faces the squisher,
		-- 1 is 90° left onto the steamer nook, -1 is 90° right onto the
		-- cannon. (+yaw about Y turns left.) The clamp allows a little past
		-- each end so the spring's overshoot isn't cut off.
		-- The shop camera stands still and TURNS: viewYaw 0 faces the
		-- squisher, 1 is 90° left onto the steamer nook. (+yaw about Y turns
		-- left.) The clamp allows a little past each end so the spring's
		-- overshoot isn't cut off.
		local yaw = math.clamp(viewYaw.value, -0.15, 1.15) * math.rad(90)
		local dir = CFrame.fromEulerAnglesXYZ(0, yaw, 0):VectorToWorldSpace(BASE_LOOK_DIR)
		-- Shake in view space, so it reads as shake from any angle.
		local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
		local jolt = right * ((math.random() - 0.5) * shake) + Vector3.new(0, (math.random() - 0.5) * shake, 0)
		local shopCFrame = CFrame.lookAt(CAMERA_POS + jolt, CAMERA_POS + jolt + dir)

		-- The valley is a different PLACE, not a different angle, so this is a
		-- travelling shot rather than a turn.
		local valleyCFrame = CFrame.lookAt(VALLEY_CAM_POS + jolt, VALLEY_CAM_LOOK)
		local resting = shopCFrame:Lerp(valleyCFrame, math.clamp(viewRange.value, 0, 1))

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

	-- Retune the distance ladder to match: about ten rungs across the visible
	-- track, snapped to a round number so it counts in 50s and 500s rather
	-- than in 47s and 468s.
	ladderStep = niceStep(TRACK_SPAN / runScale / 10)

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

	-- Take the camera for the duration. The render loop hands it back on its
	-- own once holdUntil passes, so nothing has to remember to.
	sceneDrivesCamera = true
	viewRange.target = 1
	viewRange.value = 1
	task.delay(flight.seconds + 1.1, function()
		if flight.progress >= 1 then
			sceneDrivesCamera = false
		end
	end)

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

-- Summon this exact set of squishies. Rebuilt rather than recoloured because
-- each one is its real model — a banana summon has to actually be a banana —
-- and the set only changes when somebody presses Summon, which is nothing
-- like per-frame.
function Scene.setActiveSquishies(list: { { shape: string?, color: Color3, sparkle: boolean, sizeScale: number? } })
	for _, follower in followers do
		follower.model.rig.folder:Destroy()
	end
	followers = {}

	for index, spec in list do
		if index > Config.MaxActiveSquishies then
			break
		end
		table.insert(followers, {
			model = Models.buildSquishy(stage, spec.shape, spec.color, spec.sparkle, spec.sizeScale),
			-- Seeded behind the squisher so they walk in rather than snapping
			-- into place from wherever the last set left off.
			position = CLICKER_SPOT - Vector3.new(FOLLOW_SPACING * index, 0, 0),
			velocity = Vector3.zero,
		})
	end
end

-- Fly somebody else's shot down the valley for the lobby to watch. The whole
-- flight arrives in one broadcast, so this needs no further contact with the
-- server — it just plays what it was handed.
function Scene.playGhost(shot: {
	name: string,
	distance: number,
	arcs: { FlightArc },
	seconds: number,
}, color: Color3)
	if typeof(shot.arcs) ~= "table" or #shot.arcs == 0 then
		return
	end

	-- Round-robin the pool: on a busy server the oldest ghost is simply
	-- recycled mid-flight rather than queueing shots nobody is waiting for.
	local ghost = ghosts[nextGhost]
	nextGhost = nextGhost % #ghosts + 1

	ghost.arcs = shot.arcs
	ghost.arcStarts = {}
	local running = 0
	local peak = 1
	for index, arc in shot.arcs do
		ghost.arcStarts[index] = running
		running += arc.seconds
		peak = math.max(peak, arc.peak)
	end

	ghost.simSeconds = math.max(shot.seconds, 1e-3)
	ghost.seconds = math.clamp(ghost.simSeconds * 0.25, 2.2, 8)
	ghost.progress = 0
	ghost.active = true

	-- Its own scale, so every ghost is drawn at a readable size whatever it
	-- really flew. See the comment on the Ghost type.
	local distance = math.max(shot.distance, 1)
	ghost.runScale = TRACK_RUN * 0.7 / distance
	ghost.heightScale = math.min(STAGE_APEX * 0.7 / peak, ghost.runScale * MAX_HEIGHT_STRETCH)

	ghost.part.Color = color
	ghost.part.Transparency = 0.25
	ghost.label.Text = ("%s — %s"):format(shot.name, Format.abbreviate(math.floor(distance)))
end

-- Told whenever the camera moves between the valley and the toy shop, so each
-- half of the game can put its own HUD up and take the other's down. Without
-- this both halves' panels are on screen at once and fight for the same
-- corners, which is most of what "cluttered" means.
local viewListeners: { (atValley: boolean) -> () } = {}

function Scene.onViewChanged(listener: (atValley: boolean) -> ())
	table.insert(viewListeners, listener)
	-- Called straight away with the current view, so a listener registering
	-- late doesn't sit in the wrong state until the player moves.
	listener(viewRange.target > 0.5)
end

-- Move the camera. "main" and "cannon" are the launch valley, which is where
-- the game lives; "unbox" and "clicker" travel back to the toy shop, the
-- steamer nook and the squisher respectively.
function Scene.setView(view: string)
	if view == "unbox" then
		viewRange.target = 0
		viewYaw.target = 1
		sceneDrivesCamera = true
	elseif view == "clicker" then
		viewRange.target = 0
		viewYaw.target = 0
		sceneDrivesCamera = true
	else
		-- "main" is the island now: the camera goes back to the character and
		-- the player walks. The valley is only ever seen during a flight.
		viewRange.target = 1
		-- Snapped rather than sprung, because the next thing the camera does
		-- is belong to somebody else — easing toward a position it is about to
		-- stop drawing would only show as a lurch on the way out.
		viewRange.value = 1
		sceneDrivesCamera = false
	end

	local atValley = viewRange.target > 0.5
	for _, listener in viewListeners do
		listener(atValley)
	end
end

-- Which half of the game the camera is on, so the HUD can show the launcher's
-- controls or the shop's rather than both at once.
function Scene.atValley(): boolean
	return viewRange.target > 0.5
end

-- Repaint the valley in another world's palette. A world is a retune of the
-- same track rather than a second map — the geometry, the ladder and the
-- treadmill are identical, which is why switching is a colour swap and not a
-- teleport. Everything repainted here is cosmetic; the server still owns
-- every number that decides a payout.
function Scene.setWorld(index: number)
	local world = Config.Worlds[index]
	if not world then
		return
	end
	grass.Color = world.grass
	mown.Color = world.grassDark
	for _, face in canyonFaces do
		face.Color = world.canyon
	end
	for _, lip in canyonLips do
		lip.Color = world.grass
	end
	for _, rung in ladder do
		rung.plate.Color = world.grassDark
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
