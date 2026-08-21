--!strict
-- ============================================================
--  THE ISLAND  —  the walkable world, built on the server.
--
--  This is the half of the map players actually stand on: a round
--  island ringed by terraced canyon, a plaza in the middle to
--  spawn into, dirt paths radiating out to a ring of plots, and
--  market stalls and scenery filling the gaps.
--
--  It lives on the SERVER for three reasons, all of which matter:
--
--   * a floor you can stand on has to replicate, or the character
--     falls through geometry only their own client knows about;
--   * plots are a shared fiction — everyone has to see the same
--     one claimed by the same person;
--   * a client-built world is a client-editable world.
--
--  The launch VALLEY is the opposite case and stays on the client
--  (see Scene.luau): it is a per-player animation rig on a
--  treadmill, and no two players are ever looking at the same
--  frame of it, so replicating it would be pure cost.
--
--  TWO WAYS the world can exist:
--
--   * GENERATED — no Map folder in the place: build() constructs
--     everything at startup, exactly as always.
--   * BAKED — run this from Studio's command bar in EDIT mode:
--         require(game.ServerScriptService.Server.Island).build()
--     and the world is constructed as ordinary saved parts. From
--     then on the PLACE FILE owns the map: edit, move, delete and
--     decorate it by hand like any Roblox game. At startup build()
--     finds the Map folder, skips construction, and wires the plot
--     bookkeeping onto whatever stands there — centres re-derived
--     from each plot's pad, so hand-moved plots fire true. To
--     return to generated mode (or re-bake after importing new
--     models), delete the Map folder and save (then re-run the
--     command to bake again).
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Island = {}

-- ---------- dimensions ----------
-- One radius drives the whole layout, so the island can be resized by
-- changing this and letting everything else fall out of it.
local ISLAND_RADIUS = 210
local BEACH_WIDTH = 18
local PLAZA_RADIUS = 62 -- the event floor, and the biggest open space on the map
local PLOT_SIZE = 40
local PLOT_RING = 152 -- how far out the plot CENTRES sit
local RING_ROAD = 108 -- comfortably between the plaza and the plots
local PATH_WIDTH = 13
local GROUND_Y = 0

-- Every flat surface on the island is stacked on its OWN level. Two slabs
-- sharing a height and overlapping in plan is what z-fighting is, and it was
-- most of what made the first island shimmer: the plaza, its rim, the spokes
-- and the ring road all met at roughly the same Y and fought over the pixels.
-- Gaps of a twentieth of a stud are invisible and settle it completely.
-- ---------- the sea ----------
-- The island is an ISLAND again: flights play in each player's private
-- corridor (see Flight.luau), so what surrounds the plateau is open water
-- to the horizon — scenery with one job, which is to be sea.
-- Half the 2048-stud Part clamp, i.e. the biggest disc Roblox will actually
-- make; the skirt ring in buildGround carries the water on past it.
local PLAIN_RADIUS = 1020
local PLATEAU_DROP = 22 -- how far the base sits above the water

local Y = {
	plain = -PLATEAU_DROP,
	beach = 0,
	field = 0.2,
	ringRoad = 0.5,
	spoke = 0.56,
	plazaRim = 0.62,
	plaza = 0.8,
	plotRim = 1,
	plotPad = 1.4,
}

Island.PLAZA_RADIUS = PLAZA_RADIUS

Island.PLOT_COUNT = 8
Island.PLOT_SIZE = PLOT_SIZE
Island.GROUND_Y = GROUND_Y

-- ---------- palette ----------
-- Shared with the launch valley in Scene.luau so the two halves of the game
-- look like one place. Changing a colour here means changing it there too.
local COLOR = {
	grass = Color3.fromRGB(150, 226, 84),
	grassDark = Color3.fromRGB(130, 210, 80),
	sand = Color3.fromRGB(242, 222, 158),
	water = Color3.fromRGB(96, 196, 234),
	rock = Color3.fromRGB(180, 80, 80),
	rockTop = Color3.fromRGB(130, 210, 80),
	path = Color3.fromRGB(210, 110, 60),
	pathEdge = Color3.fromRGB(184, 92, 48),
	wood = Color3.fromRGB(150, 104, 62),
	plank = Color3.fromRGB(196, 140, 86),
	stone = Color3.fromRGB(196, 192, 188),
	awningA = Color3.fromRGB(232, 74, 74),
	awningB = Color3.fromRGB(250, 246, 240),
	metal = Color3.fromRGB(120, 132, 190),
	metalDark = Color3.fromRGB(52, 56, 84),
}

local root: Folder
local folders: { [string]: Folder } = {}

local function group(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = root
	folders[name] = folder
	return folder
end

-- Every part on the island goes through this. Collidable by default, because
-- the whole point of this half of the map is that it holds you up.
local function block(size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- The classic stud top, which is most of what makes this style read.
local function studded(part: BasePart): BasePart
	part.TopSurface = Enum.SurfaceType.Studs
	return part
end

-- Slabs are placed by their TOP face rather than their centre. Every layer on
-- the island is "a floor at this height", so saying it that way removes a
-- half-thickness from every call site and with it the arithmetic slips that
-- put two of them on the same level in the first place.
local function slabAt(top: number, thickness: number): number
	return top - thickness * 0.5
end

local function cylinder(diameter: number, height: number, at: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	-- Cylinders point along X, so this stands one on its end.
	part.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.Anchored = true
	part.CanCollide = true
	part.Parent = parent
	return part
end

-- Decoration never needs collision, and turning it off for a few hundred
-- parts is worth real physics time on a busy server.
local function decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- The sea kills on contact: no barrier stops a player walking off the
-- plateau's rim anymore, so the water is what ends the fall instead of
-- Roblox's own kill-plane far below. CanTouch stays on (unlike decor()), and
-- CanCollide off — the water should catch the fall as a touch, not as a
-- floor to land and stand on.
local function drowns(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = true
	part.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
	return part
end

local function signPost(at: Vector3, text: string, color: Color3, parent: Instance, labelHeight: number?): TextLabel
	local post = decor(block(Vector3.new(0.6, 7, 0.6), CFrame.new(at + Vector3.new(0, 3.5, 0)), COLOR.wood, parent))
	post.Material = Enum.Material.Wood

	local board = Instance.new("Part")
	board.Size = Vector3.new(0.4, 0.4, 0.4)
	board.CFrame = CFrame.new(at + Vector3.new(0, labelHeight or 8.6, 0))
	board.Transparency = 1
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 220, 0, 54)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 260
	gui.Parent = board

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
	return label
end

-- ---------- the ground ----------

local function buildGround()
	local ground = group("Ground")

	-- The SEA first: the same disc-plus-skirt geometry that used to carry
	-- the launch range, wearing water. Flights live in each player's own
	-- corridor now, so what surrounds the island is simply ocean — which is
	-- what it originally was. Named "Sea", NOT "Grass", so the world
	-- repaint's name sweep leaves it blue in every world. (Recolourable
	-- ground is NAMED — "Grass" — because the client repaints the island
	-- locally when a world is selected, and matching parts by name is the
	-- only contract that survives this file being rearranged.)
	-- Dropped a few studs below the old plain so the sand cliff reads as a
	-- shoreline rather than a wall.
	local sea = cylinder(PLAIN_RADIUS * 2, 12, Vector3.new(0, slabAt(Y.plain - 4, 12), 0), COLOR.water, ground)
	sea.Name = "Sea"
	sea.Material = Enum.Material.SmoothPlastic
	drowns(sea)

	-- The water carries to the horizon. The radial span (≈1985) sits just
	-- under the 2048 Part clamp — one ring of segments carries it all, each
	-- chord sized for the OUTER rim so the ring can't open wedge gaps.
	local SKIRT_OUTER = 3000
	local SKIRT_SEGMENTS = 96
	local skirtMid = (PLAIN_RADIUS - 5 + SKIRT_OUTER) * 0.5
	local skirtWidth = 2 * math.pi * SKIRT_OUTER / SKIRT_SEGMENTS + 6
	for index = 1, SKIRT_SEGMENTS do
		local angle = (index / SKIRT_SEGMENTS) * math.pi * 2
		local at = Vector3.new(math.cos(angle) * skirtMid, slabAt(Y.plain - 4.1, 12), math.sin(angle) * skirtMid)
		local piece = block(
			Vector3.new(SKIRT_OUTER - (PLAIN_RADIUS - 5), 12, skirtWidth),
			CFrame.new(at) * CFrame.Angles(0, -angle, 0),
			COLOR.water,
			ground
		)
		piece.Name = "Sea"
		piece.Material = Enum.Material.SmoothPlastic
		drowns(piece)
	end

	-- The plateau the base sits on. A thick sand slab dropping to the plain,
	-- which reads as a cliff edge from below and as a beach from above.
	local cliff = cylinder(
		ISLAND_RADIUS * 2,
		PLATEAU_DROP + 8,
		Vector3.new(0, slabAt(Y.beach, PLATEAU_DROP + 8), 0),
		COLOR.sand,
		ground
	)
	cliff.Material = Enum.Material.Sand

	local field =
		cylinder((ISLAND_RADIUS - BEACH_WIDTH) * 2, 8, Vector3.new(0, slabAt(Y.field, 8), 0), COLOR.grass, ground)
	field.Name = "Grass"
	studded(field)

	-- The plaza: a big stone disc with a path-coloured rim, and the event
	-- floor for King of the Steamer. Its size is the reason the island is as
	-- wide as it is — everything else is laid out around it.
	local plazaRim =
		cylinder((PLAZA_RADIUS + 4) * 2, 1.6, Vector3.new(0, slabAt(Y.plazaRim, 1.6), 0), COLOR.path, ground)
	studded(plazaRim)

	local plaza = cylinder(PLAZA_RADIUS * 2, 2, Vector3.new(0, slabAt(Y.plaza, 2), 0), COLOR.stone, ground)
	studded(plaza)
end

-- ---------- the range on the water ----------
-- The rainbow target from the shared-range era, back exactly as it was —
-- painted on the OCEAN now, since the plain it used to cover became the sea.
-- Filled bands from the beach edge out to the last ring, rainbow near to
-- far, each with its distance printed FLAT on it once per plot bearing.
-- The ghost launches (client/Ghosts.luau) splash down on the band their
-- shot's expected distance names, through the same Config.rangeRadius, so
-- the bands are a scoreboard everyone on the island reads at a glance.
--
-- Filled rather than thin stripes, because a solid band is the thing that
-- reads at a thousand studs — a nine-stud line seen almost edge-on is a
-- scratch. Printed on the water rather than floated above it, because
-- floating signs draw at a fixed pixel size however far away they are.
-- Each band floats a few hundredths of a stud above its inner neighbour —
-- the island's own no-shared-heights rule — so the half-stud overlap where
-- bands meet can never z-fight. Parts are named "RangeBand", NOT "Sea" or
-- "Grass", so neither the drowning sweep nor the world repaint touches them.
--
-- Runs in BOTH world modes: the generated build calls it like any other
-- ground pass, and the baked-world adoption grows the target in at startup
-- until a re-bake saves it — the Range folder is the already-dressed marker
-- either way, so the bands can never double-stack.
local function buildRangeBands(parent: Instance)
	if parent:FindFirstChild("Range") then
		return
	end
	local markers = Instance.new("Folder")
	markers.Name = "Range"
	markers.Parent = parent

	local bands = Config.RangeBands
	-- The sea's top face sits at Y.plain - 4 (see buildGround); the bands
	-- lie just above it, like the old ones lay on the plain.
	local seaTop = Y.plain - 4

	local inner = ISLAND_RADIUS -- the first band starts at the shoreline
	for order, band in bands do
		local outer = Config.rangeRadius(band.studs)
		local depth = outer - inner
		if depth > 1 then
			-- Rainbow near to far, so "how far did it get" is answerable at
			-- a glance by which colour it splashed down on.
			local color = Color3.fromHSV((order - 1) / #bands * 0.86, 0.72, 1)
			local mid = (inner + outer) * 0.5
			local stripY = seaTop + 0.7 + order * 0.05

			-- Segment count scales with circumference: a fixed count would
			-- make the inner rings needlessly dense and the outer ones
			-- coarse enough to show as a polygon.
			local segments = math.clamp(math.floor(mid / 7), 48, 160)
			local width = 2 * math.pi * mid / segments + 3

			for index = 1, segments do
				local angle = (index / segments) * math.pi * 2
				local at = Vector3.new(math.cos(angle) * mid, stripY, math.sin(angle) * mid)
				local strip = block(
					Vector3.new(depth + 1, 1.2, width),
					CFrame.new(at) * CFrame.Angles(0, -angle, 0),
					color,
					markers
				)
				strip.Name = "RangeBand"
				studded(decor(strip))
			end

			-- The number, lying on the band, once per plot bearing so
			-- whichever way a cannon points there is a figure under it. Sat
			-- near the band's OUTER edge: that is the line the distance
			-- actually means, and the edge a ghost splashes across.
			for slot = 1, Island.PLOT_COUNT do
				local angle = (slot - 1) / Island.PLOT_COUNT * math.pi * 2
				local textRadius = outer - math.min(depth * 0.42, 34)
				local at = Vector3.new(math.cos(angle) * textRadius, stripY + 1, math.sin(angle) * textRadius)

				-- X runs radially, Z runs along the band, so the text reads
				-- across the ring the way a real distance marker does.
				local plateDepth = math.min(depth * 0.7, 56)
				local plate = block(
					Vector3.new(plateDepth, 0.6, plateDepth * 3.4),
					CFrame.new(at) * CFrame.Angles(0, -angle, 0),
					color,
					markers
				)
				plate.Name = "RangeBand"
				plate.Transparency = 1 -- the plate is only a surface to print on
				decor(plate)

				local surface = Instance.new("SurfaceGui")
				surface.Face = Enum.NormalId.Top
				-- Low, because the text has to be huge in world terms to be
				-- read from the island a thousand studs away.
				surface.PixelsPerStud = 12
				surface.Parent = plate

				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 1)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.FredokaOne
				label.Text = ("%s Studs"):format(band.name)
				label.TextColor3 = Color3.fromRGB(255, 255, 255)
				label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
				label.TextStrokeTransparency = 0
				label.TextScaled = true
				-- Printed to be read from the island looking OUT, not from
				-- the horizon looking back.
				label.Rotation = 180
				label.Parent = surface
			end
		end
		inner = outer
	end
end

-- ---------- the horizon mesas ----------
-- A ring of blocky terraced mesas standing in the outer sea past the last
-- range band, closing the skyline the way distant land does. PARTS, not
-- Terrain: the whole game is chunky slabs and studs, and the sculpted
-- smooth-terrain hills that used to hold this ring read as a different
-- game pasted onto the horizon. The recipe is the reference-photo one the
-- corridor's canyon walls already wear — brown rock drums stepping in as
-- they rise, a studded grass cap overhanging each, a sand skirt at the
-- waterline, block trees on the tops — so the island, the flight and the
-- horizon are one construction language.
--
-- Two rows at different radii, the outer one taller, purely for parallax:
-- from the plaza the far row slides behind the near one and the horizon
-- reads as depth rather than as a fence. Deterministic (fixed seed) so a
-- re-bake grows the same skyline. Runs in both world modes exactly like
-- buildRangeBands: the Horizon folder is the already-built marker.
local function buildHorizon(parent: Instance)
	if parent:FindFirstChild("Horizon") then
		return
	end
	local horizon = Instance.new("Folder")
	horizon.Name = "Horizon"
	horizon.Parent = parent

	local seaTop = Y.plain - 4
	local rng = Random.new(19)
	-- Deeper than the island's own palette on purpose: the sky pack's
	-- Atmosphere desaturates hard at a thousand studs, and mesas painted in
	-- island colours washed to white up there — green caps and trees left
	-- hovering over invisible rock. These read as the island's browns and
	-- greens AFTER the haze has taken its cut.
	local CLIFF = Color3.fromRGB(128, 88, 54)
	local CLIFF_DARK = Color3.fromRGB(108, 74, 46)
	local CAP = Color3.fromRGB(140, 216, 76)
	local LEAF = Color3.fromRGB(84, 176, 64)
	local TRUNK = Color3.fromRGB(120, 82, 50)

	-- One mesa: sand skirt, two or three shrinking rock drums each capped
	-- with an overhanging studded grass slab, and a tree or two on top.
	local function mesa(bearing: number, radius: number, tall: number)
		local at = Vector3.new(math.cos(bearing) * radius, 0, math.sin(bearing) * radius)
		local yaw = CFrame.Angles(0, -bearing + rng:NextNumber(-0.2, 0.2), 0)
		local function place(size: Vector3, top: number, color: Color3): Part
			return decor(
				block(size, CFrame.new(at + Vector3.new(0, slabAt(top, size.Y), 0)) * yaw, color, horizon)
			) :: Part
		end

		-- Sizes: radial depth shallow, tangent width broad, so the ring
		-- reads as a wall of land rather than a circle of towers.
		local width = rng:NextNumber(120, 210)
		local depth = rng:NextNumber(60, 95)

		place(Vector3.new(depth + 34, 10, width + 34), seaTop + 2.5, COLOR.sand).Name = "Horizon"

		local drums = if tall > 95 then 3 else 2
		local level = seaTop + 2.5
		local remaining = tall
		for drum = 1, drums do
			local height = if drum == drums then remaining else remaining * rng:NextNumber(0.42, 0.55)
			remaining -= height
			local color = if drum % 2 == 1 then CLIFF else CLIFF_DARK
			place(Vector3.new(depth, height, width), level + height, color).Name = "Horizon"
			local cap = place(Vector3.new(depth + 7, 4.5, width + 7), level + height + 4.5, CAP)
			studded(cap).Name = "Horizon"
			level += height + 4.5
			width *= rng:NextNumber(0.68, 0.8)
			depth *= rng:NextNumber(0.72, 0.84)
		end

		-- Trees, scaled up from the corridor's: at a thousand studs a
		-- corridor-sized tree is a speck.
		for _ = 1, rng:NextInteger(0, 2) do
			local along = rng:NextNumber(-width * 0.35, width * 0.35)
			local trunkHeight = rng:NextNumber(9, 14)
			local treeAt = at + yaw:VectorToWorldSpace(Vector3.new(0, 0, along))
			local trunk = decor(block(
				Vector3.new(4, trunkHeight, 4),
				CFrame.new(treeAt + Vector3.new(0, level + trunkHeight * 0.5, 0)) * yaw,
				TRUNK,
				horizon
			))
			trunk.Material = Enum.Material.Wood
			trunk.Name = "Horizon"
			local leafY = level + trunkHeight
			local leafSide = rng:NextNumber(18, 25)
			for layer = 1, 2 do
				local side = leafSide * (if layer == 1 then 1 else 0.6)
				local thickness = if layer == 1 then 9 else 6
				local leaf = decor(block(
					Vector3.new(side, thickness, side),
					CFrame.new(treeAt + Vector3.new(0, leafY + thickness * 0.5, 0)) * yaw,
					LEAF,
					horizon
				))
				studded(leaf).Name = "Horizon"
				leafY += thickness
			end
		end
	end

	-- The inner row, then the taller outer row phase-shifted half a step so
	-- its mesas stand in the near row's gaps.
	local innerCount = 30
	for step = 1, innerCount do
		local bearing = (step / innerCount) * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
		mesa(bearing, rng:NextNumber(1090, 1160), rng:NextNumber(55, 115))
	end
	local outerCount = 26
	for step = 1, outerCount do
		local bearing = ((step + 0.5) / outerCount) * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		mesa(bearing, rng:NextNumber(1230, 1320), rng:NextNumber(110, 190))
	end
end

-- ---------- paths ----------
-- One spoke out to each plot, plus a ring road joining them. Laid as a run of
-- overlapping blocks rather than one long rotated slab, so a path can bend
-- later without the geometry fighting it.
local function buildPaths()
	local paths = group("Paths")

	-- Spokes stop just short of the plot rims. Running them under the pads is
	-- what put two studded surfaces on top of each other at the plot edge.
	local plotInner = PLOT_RING - PLOT_SIZE * 0.5 - 4
	for index = 1, Island.PLOT_COUNT do
		local angle = (index - 1) / Island.PLOT_COUNT * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local from = PLAZA_RADIUS + 2
		local length = plotInner - from
		local centre = direction * (from + length * 0.5)

		local spoke = block(
			Vector3.new(length, 1.2, PATH_WIDTH),
			CFrame.new(centre + Vector3.new(0, slabAt(Y.spoke, 1.2), 0)) * CFrame.Angles(0, -angle, 0),
			COLOR.path,
			paths
		)
		studded(spoke)
	end

	-- The ring road, as segments following a circle that clears the plaza on
	-- one side and the plots on the other.
	local SEGMENTS = 72
	local width = 2 * math.pi * RING_ROAD / SEGMENTS + 1.5
	for index = 1, SEGMENTS do
		local angle = (index / SEGMENTS) * math.pi * 2
		local at = Vector3.new(math.cos(angle) * RING_ROAD, slabAt(Y.ringRoad, 1.2), math.sin(angle) * RING_ROAD)
		local ring = block(
			Vector3.new(PATH_WIDTH * 0.85, 1.2, width),
			CFrame.new(at) * CFrame.Angles(0, -angle, 0),
			COLOR.pathEdge,
			paths
		)
		studded(ring)
	end
end

-- ---------- market stalls ----------
-- Wooden counter, four posts, striped awning. Same silhouette as the ones on
-- the launch bank, so the two areas read as the same world.
local function buildStall(at: Vector3, facing: number, parent: Instance)
	local frame = CFrame.new(at) * CFrame.Angles(0, facing, 0)
	local function piece(size: Vector3, offset: Vector3, color: Color3, material: Enum.Material): Part
		local part = block(size, frame * CFrame.new(offset), color, parent)
		part.Material = material
		return part
	end

	piece(Vector3.new(11, 4, 4), Vector3.new(0, 2, 0), COLOR.wood, Enum.Material.WoodPlanks)
	piece(Vector3.new(11.6, 1.4, 2), Vector3.new(0, 4.4, -2), COLOR.plank, Enum.Material.WoodPlanks)
	for _, side in { -5, 5 } do
		for _, depth in { -2, 2 } do
			decor(piece(Vector3.new(0.7, 8, 0.7), Vector3.new(side, 4, depth), COLOR.wood, Enum.Material.Wood))
		end
	end
	for strip = -5, 5 do
		decor(piece(
			Vector3.new(1, 0.6, 6),
			Vector3.new(strip, 8.4, 0),
			strip % 2 == 0 and COLOR.awningA or COLOR.awningB,
			Enum.Material.SmoothPlastic
		))
	end

	-- The browse prompt lives on its own invisible host in front of the
	-- counter rather than on the scenery — same pattern as the cannons, so a
	-- future fancier stall model doesn't take the interaction down with it.
	-- The client opens the squishy market menu when this fires; the server
	-- hands out nothing here, so there is nothing to validate.
	local host = Instance.new("Part")
	host.Name = "MarketPromptHost"
	host.Size = Vector3.new(5, 6, 4)
	host.CFrame = frame * CFrame.new(0, 3, -4)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Parent = parent

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SquishyMarket"
	prompt.ObjectText = "Squishy Market"
	prompt.ActionText = "Browse Squishies"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
end

-- ---------- scenery ----------

local function buildTree(at: Vector3, scale: number, parent: Instance)
	local trunk = block(
		Vector3.new(1.2 * scale, 5 * scale, 1.2 * scale),
		CFrame.new(at + Vector3.new(0, 2.5 * scale, 0)),
		COLOR.wood,
		parent
	)
	trunk.Material = Enum.Material.Wood

	for tier = 0, 2 do
		local width = (7 - tier * 1.8) * scale
		local leaf = block(
			Vector3.new(width, 2.4 * scale, width),
			CFrame.new(at + Vector3.new(0, (5.6 + tier * 2.1) * scale, 0)),
			tier == 0 and Color3.fromRGB(96, 186, 76) or Color3.fromRGB(120, 208, 92),
			parent
		)
		studded(decor(leaf))
	end
end

local function buildScenery()
	local props = group("Props")
	-- Seeded, so the island is laid out identically on every server rather
	-- than being a different place each time someone joins.
	local rng = Random.new(2026)

	-- Stalls ON the spoke paths — every other spoke, counter fronting the
	-- path like a market street. Beside the paving rather than across it
	-- (a stall planted mid-path is a stall you cannot walk past), close
	-- enough that the awning overhangs the edge and it reads as ON the path.
	for index = 1, 4 do
		local spoke = index * 2 - 1
		local angle = (spoke - 1) / Island.PLOT_COUNT * math.pi * 2
		local along = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local perp = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		-- Alternate sides of the path so walking the ring passes stalls on
		-- both hands instead of a one-sided arcade.
		local side = if index % 2 == 0 then 1 else -1
		local at = along * (PLAZA_RADIUS + 28) + perp * (side * (PATH_WIDTH / 2 + 3.5))
		-- The stall's open front is local -Z; aim it across at the paving.
		local look = -perp * side
		local facing = math.atan2(-look.X, -look.Z)
		buildStall(Vector3.new(at.X, GROUND_Y, at.Z), facing, props)
	end

	-- Where the plots will be. Scenery is placed against the real centres
	-- rather than against an angle-slot approximation of them — that
	-- approximation is what dropped trees through the plot fences.
	local plotCentres: { Vector3 } = {}
	for index = 1, Island.PLOT_COUNT do
		local angle = (index - 1) / Island.PLOT_COUNT * math.pi * 2
		table.insert(plotCentres, Vector3.new(math.cos(angle) * PLOT_RING, 0, math.sin(angle) * PLOT_RING))
	end

	-- Clear of everything built so far: the plaza, the ring road, the spokes,
	-- the plot pads and the stalls.
	local function isClear(at: Vector3, radius: number, angle: number): boolean
		if math.abs(radius - RING_ROAD) < PATH_WIDTH then
			return false
		end
		for _, centre in plotCentres do
			-- Square check, because a plot pad is a square.
			local offset = at - centre
			if math.abs(offset.X) < PLOT_SIZE * 0.75 and math.abs(offset.Z) < PLOT_SIZE * 0.75 then
				return false
			end
		end
		-- Distance from the nearest spoke, measured across it rather than
		-- along: near the plaza a few degrees is a couple of studs, out by the
		-- plots the same few degrees is twenty.
		local slot = angle / (math.pi * 2) * Island.PLOT_COUNT
		local offBySlots = math.abs(slot - math.floor(slot + 0.5))
		local acrossSpoke = offBySlots * (math.pi * 2 / Island.PLOT_COUNT) * radius
		return acrossSpoke > PATH_WIDTH
	end

	for _ = 1, 150 do
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber(PLAZA_RADIUS + 14, ISLAND_RADIUS - BEACH_WIDTH - 8)
		local at = Vector3.new(math.cos(angle) * radius, GROUND_Y + Y.field, math.sin(angle) * radius)

		if isClear(at, radius, angle) then
			local roll = rng:NextNumber()
			if roll < 0.46 then
				buildTree(at, rng:NextNumber(0.8, 1.5), props)
			elseif roll < 0.76 then
				local size = rng:NextNumber(3, 5)
				local bush = block(
					Vector3.new(size, size * 0.7, size),
					CFrame.new(at + Vector3.new(0, size * 0.35, 0)),
					Color3.fromRGB(104, 196, 80),
					props
				)
				studded(decor(bush))
			else
				local size = rng:NextNumber(2, 4.5)
				local rock = block(
					Vector3.new(size, size * 0.8, size * 1.2),
					CFrame.new(at + Vector3.new(0, size * 0.4, 0)) * CFrame.Angles(0, rng:NextNumber() * 6, 0),
					Color3.fromRGB(152, 152, 158),
					props
				)
				rock.Material = Enum.Material.Slate
			end
		end
	end
end

-- ---------- plots ----------

export type Plot = {
	index: number,
	folder: Folder,
	centre: Vector3,
	facing: number, -- radians, pointing outward from the island
	sign: TextLabel,
	prompt: ProximityPrompt,
	owner: Player?,
}

local plots: { Plot } = {}

-- ---------- imported models on a plot ----------

-- A template found by a tolerant name match anywhere under ReplicatedStorage
-- — "Squishy Cannon", "SquishyCannon" and any casing all resolve, because
-- exact-name lookups on hand-imported models are how a month of "the model
-- doesn't show" bugs happened. `looseName` is the lowercased, de-spaced form.
local function findImportTemplate(looseName: string): (Model | BasePart)?
	for _, descendant in game:GetService("ReplicatedStorage"):GetDescendants() do
		local loosened = descendant.Name:lower():gsub("[%s_]", "")
		if loosened == looseName and (descendant:IsA("Model") or descendant:IsA("BasePart")) then
			return descendant :: any
		end
	end
	return nil
end

-- The shared handling every import gets, in one place because the second
-- import (the capsule pod) would otherwise re-learn each lesson the cannon
-- already paid for.
--
-- Scripts are destroyed — an import is GEOMETRY, nothing more. The cannon
-- arrived carrying a toolbox touch-and-fling script written for R6 that
-- reached for character.Torso and errored on every modern avatar; foreign
-- scripts inside imported models do not get to run at all, both for the
-- error spam and as basic hygiene. Every part is anchored, or the model
-- falls through the pad the moment it spawns.
--
-- Returns false for a GUTTED import (no parts left — a Studio deletion that
-- overshot), so the caller can fall back loudly instead of placing pure
-- invisibility.
local function prepareImport(clone: Model | BasePart): boolean
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end

	local hasAnyPart = clone:IsA("BasePart")
	if clone:IsA("BasePart") then
		clone.Anchored = true
	end
	for _, part in clone:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			hasAnyPart = true
		end
	end
	return hasAnyPart
end

-- Scale to a standard largest-dimension size, whatever the import was
-- authored at.
local function scaleImport(clone: Model | BasePart, target: number)
	if clone:IsA("Model") then
		local size = clone:GetExtentsSize()
		local largest = math.max(size.X, size.Y, size.Z, 0.001)
		pcall(function()
			clone:ScaleTo(clone:GetScale() * target / largest)
		end)
	elseif clone:IsA("BasePart") then
		local largest = math.max(clone.Size.X, clone.Size.Y, clone.Size.Z, 0.001)
		clone.Size = clone.Size * (target / largest)
	end
end

-- How big the placed cannon should be, as its largest dimension.
local CANNON_TARGET_SIZE = 26

-- Which way the import's MUZZLE points relative to its authored front, as a
-- yaw correction on top of a lookAt down the radial. 0 = authored facing -Z
-- (the usual convention), 180 = facing +Z, ±90 for the sides.
--
-- Dialled in BY EYE with the debug menu's Rotate Cannons and written back
-- from the number the Output printed — never deduced from screenshots, which
-- went wrong twice before that button existed. If a future import faces the
-- wrong way, do the same: press until right, copy the number here.
local CANNON_YAW_DEGREES = 90

-- And the same for PITCH. The FIRST import was authored nose-up and needed
-- -90 to tip it onto the radial; the current one is authored upright, so
-- the leftover -90 was exactly what knocked it onto its side. Zero for a
-- sensibly-authored model; only touch this if an import arrives tilted.
local CANNON_PITCH_DEGREES = 0

-- Every placed cannon's placement closure, plus the live debug offset, so
-- Rotate Cannons can re-aim the whole island at once.
local placedCannons: { (extraYaw: number) -> () } = {}
local cannonExtraYaw = 0

-- The old built-from-parts cannon: the fallback whenever the import is
-- missing OR unusable, so a plot always has a cannon on it no matter what
-- state the place file is in.
local function buildFallbackCannon(frame: CFrame, folder: Folder)
	local plinth = block(Vector3.new(9, 4.5, 9), frame * CFrame.new(2, 3.9, 0), Color3.fromRGB(240, 224, 186), folder)
	plinth.Material = Enum.Material.SmoothPlastic

	local barrel = Instance.new("Part")
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(11, 5.6, 5.6)
	barrel.CFrame = frame * CFrame.new(4, 8.4, 0) * CFrame.Angles(0, 0, math.rad(38)) * CFrame.new(4, 0, 0)
	barrel.Color = COLOR.metal
	barrel.Material = Enum.Material.SmoothPlastic
	barrel.Anchored = true
	barrel.CanCollide = true
	barrel.Parent = folder

	local mouth = Instance.new("Part")
	mouth.Shape = Enum.PartType.Cylinder
	mouth.Size = Vector3.new(0.5, 4.6, 4.6)
	mouth.CFrame = barrel.CFrame * CFrame.new(5.4, 0, 0)
	mouth.Color = COLOR.metalDark
	mouth.Material = Enum.Material.SmoothPlastic
	mouth.Anchored = true
	decor(mouth)
	mouth.Parent = folder
end

local function buildCannon(frame: CFrame, folder: Folder)
	local template = findImportTemplate("squishycannon")

	if not template then
		warn("[SquishyClicker] No 'Squishy Cannon' model found in ReplicatedStorage — using the built-in cannon.")
		buildFallbackCannon(frame, folder)
		return
	end

	local cannon = template:Clone()

	if not prepareImport(cannon) then
		warn(
			"[SquishyClicker] The 'Squishy Cannon' template has no parts left — "
				.. "did a Studio deletion take the mesh with it? Using the built-in cannon."
		)
		cannon:Destroy()
		buildFallbackCannon(frame, folder)
		return
	end

	scaleImport(cannon, CANNON_TARGET_SIZE)

	-- Place it in two steps: roughly on the pad first, then measured — the
	-- bounding box is nudged so its BOTTOM sits exactly on the pad's top,
	-- which works whatever the model's authored pivot happens to be.
	--
	-- Orientation is built FROM THE RADIAL rather than from the plot frame's
	-- axes: lookAt aims the model's authored front straight along the line
	-- from the island's centre through this plot to the range, and the one
	-- yaw constant above corrects for where this particular import keeps its
	-- muzzle. There is no other rotation in the chain to be 90° off in.
	local seat = frame:PointToWorldSpace(Vector3.new(2, 0, 0))
	local outwardRadial = frame:VectorToWorldSpace(Vector3.xAxis)
	local padTopY = frame.Position.Y + Y.plotPad

	-- The whole placement as a closure taking an extra yaw, so the debug
	-- menu's Rotate Cannons can re-aim every cannon live and the right value
	-- can be READ OFF rather than deduced. Guessing an unseen model's axes
	-- from screenshots went wrong twice; it does not get a third attempt.
	local function place(extraYaw: number)
		local yaw = CANNON_YAW_DEGREES + extraYaw
		cannon:PivotTo(
			CFrame.lookAt(seat, seat + outwardRadial)
				* CFrame.Angles(0, math.rad(yaw), 0)
				* CFrame.Angles(math.rad(CANNON_PITCH_DEGREES), 0, 0)
		)

		local boundsCFrame, boundsSize
		if cannon:IsA("Model") then
			boundsCFrame, boundsSize = cannon:GetBoundingBox()
		else
			boundsCFrame, boundsSize = cannon.CFrame, cannon.Size
		end
		local bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
		cannon:PivotTo(cannon:GetPivot() + Vector3.new(0, padTopY - bottomY, 0))
	end

	place(0)
	table.insert(placedCannons, place)
	cannon.Parent = folder
end

-- Turn every placed cannon another 90° and hand back the yaw now in effect,
-- for the debug menu: press until they face the range, then write the printed
-- number into CANNON_YAW_DEGREES above.
function Island.rotateCannons(): number
	cannonExtraYaw = (cannonExtraYaw + 90) % 360
	-- In an ADOPTED (baked) world there are no placement closures — the
	-- cannons are saved geometry, rotated by hand in Studio like anything
	-- else — so this debug helper quietly has nothing to turn.
	if #placedCannons == 0 then
		warn("[SquishyClicker] Rotate Cannons does nothing in a baked world — rotate the cannon models in Studio instead.")
	end
	for _, place in placedCannons do
		place(cannonExtraYaw)
	end
	return (CANNON_YAW_DEGREES + cannonExtraYaw) % 360
end

-- ---------- the station beside the cannon ----------
-- The visible thing at the prompt spot: the imported capsule pod, or the old
-- wooden block when the import is missing. The PROMPT itself lives on a
-- separate invisible host built in buildPlot — swapping the scenery must
-- never be able to break the interaction.

local CAPSULE_TARGET_SIZE = 9

-- How far INWARD of the plot centre the station sits. The doubled cannon
-- spans about eleven studs behind its own seat, so anything nearer than
-- twelve ends up under the carriage — which is exactly where the capsule
-- first appeared.
local STATION_BACK = 13

local function buildStation(frame: CFrame, folder: Folder)
	local seat = frame:PointToWorldSpace(Vector3.new(-STATION_BACK, 0, 0))
	local padTopY = frame.Position.Y + Y.plotPad

	local template = findImportTemplate("capsulepod")
	if not template then
		warn("[SquishyClicker] No 'Capsule Pod' model found in ReplicatedStorage — using the wooden stand.")
		local stand = block(Vector3.new(3, 5, 3), CFrame.new(seat + Vector3.new(0, 2.5 + Y.plotPad, 0)), COLOR.plank, folder)
		stand.Material = Enum.Material.WoodPlanks
		return
	end

	local capsule = template:Clone()
	if not prepareImport(capsule) then
		warn("[SquishyClicker] The 'Capsule Pod' template has no parts left — using the wooden stand.")
		capsule:Destroy()
		local stand = block(Vector3.new(3, 5, 3), CFrame.new(seat + Vector3.new(0, 2.5 + Y.plotPad, 0)), COLOR.plank, folder)
		stand.Material = Enum.Material.WoodPlanks
		return
	end

	scaleImport(capsule, CAPSULE_TARGET_SIZE)

	-- Faces the radial like the cannon; a pod is near-symmetric so no yaw
	-- correction has earned its keep yet.
	local outwardRadial = frame:VectorToWorldSpace(Vector3.xAxis)
	capsule:PivotTo(CFrame.lookAt(seat, seat + outwardRadial))

	local boundsCFrame, boundsSize
	if capsule:IsA("Model") then
		boundsCFrame, boundsSize = capsule:GetBoundingBox()
	else
		boundsCFrame, boundsSize = capsule.CFrame, capsule.Size
	end
	local bottomY = boundsCFrame.Position.Y - boundsSize.Y * 0.5
	capsule:PivotTo(capsule:GetPivot() + Vector3.new(0, padTopY - bottomY, 0))

	capsule.Parent = folder
end

-- ---------- the upgrade board stand ----------
-- The PHYSICAL half of the plot's upgrade board: two posts and a blank
-- plank, real geometry in the world (and in the baked file), holding the
-- walk-in corner at a 45° greeting. The LIVE half — prices, buffs, the
-- buy buttons — is the client's: PlotBoard.luau finds this stand by name
-- and adornes its own SurfaceGui onto the plank, so every player reads
-- their own numbers off the same wood. Dimensions and pose mirror
-- PlotBoard's fallback exactly. The plot's name sign caps it — see
-- attachPlotSign below.
local BOARD_SIDE = -14
local BOARD_IN = 12

local function buildBoardStand(centre: Vector3, folder: Folder)
	local flat = Vector3.new(centre.X, 0, centre.Z)
	if flat.Magnitude < 1 then
		return
	end
	local outward = flat.Unit
	local sideWorld = Vector3.new(-outward.Z, 0, outward.X)
	local at = flat - outward * BOARD_IN + sideWorld * BOARD_SIDE
	local facing = (-outward - sideWorld * math.sign(BOARD_SIDE)).Unit
	local face = CFrame.lookAt(at + Vector3.new(0, 6, 0), at + Vector3.new(0, 6, 0) + facing)

	for _, offset in { CFrame.new(-4.6, -2.4, 0.6), CFrame.new(4.6, -2.4, 0.6) } do
		local post = Instance.new("Part")
		post.Size = Vector3.new(0.7, 7, 0.7)
		post.CFrame = face * offset
		post.Color = COLOR.wood
		post.Material = Enum.Material.Wood
		post.Anchored = true
		post.CanCollide = false
		post.CanQuery = false
		post.CanTouch = false
		post.Parent = folder
	end

	local board = Instance.new("Part")
	board.Name = "UpgradeBoard"
	board.Size = Vector3.new(11, 6.4, 0.5)
	board.CFrame = face
	board.Color = Color3.fromRGB(92, 62, 40)
	board.Material = Enum.Material.WoodPlanks
	board.Anchored = true
	board.CanCollide = false
	-- Queryable ON PURPOSE: the client adornes its buy buttons here, and
	-- buttons only hear clicks the mouse can actually hit.
	board.CanQuery = true
	board.CanTouch = false
	board.Parent = folder

	return board
end

-- The board PART named UpgradeBoard, not the Model that may be wrapping it:
-- a stand grouped by hand in Studio answers FindFirstChild("UpgradeBoard")
-- with the group, and everything downstream wants the plank itself.
local function findBoardPart(folder: Instance): BasePart?
	for _, descendant in folder:GetDescendants() do
		if descendant.Name == "UpgradeBoard" and descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

-- ---------- the plot's name sign ----------
-- Nailed to the TOP of the upgrade board: a header plank capping the wood,
-- with the owner's name painted straight onto it. It used to be its own
-- free-standing post with the label floating 32 studs overhead so it would
-- clear the cannon — which read as a bare stick on the pad and a name
-- hanging unattached in the sky. One structure carries both now: you walk
-- up to the board to read whose plot it is and what the upgrades cost.
--
-- A SurfaceGui, not a BillboardGui, precisely so it stays ON the wood at
-- the board's 45° greeting angle instead of swivelling to face every
-- camera. The gui keeps the name PlotSign and keeps a TextLabel as its
-- child: the adoption path and the claim/release bookkeeping both find the
-- sign by that name and write the owner's name into that label.
local SIGN_HEADER = "UpgradeBoardHeader"
local SIGN_HEIGHT = 2

local function attachPlotSign(board: BasePart): TextLabel
	local header = Instance.new("Part")
	header.Name = SIGN_HEADER
	header.Size = Vector3.new(board.Size.X + 1.2, SIGN_HEIGHT, 0.9)
	-- Sat on the board's top edge, and pushed back so the two front faces
	-- finish flush — a header standing proud of the board would cast a lip
	-- of shadow across the prices.
	header.CFrame = board.CFrame * CFrame.new(0, (board.Size.Y + SIGN_HEIGHT) * 0.5, (0.9 - board.Size.Z) * 0.5)
	header.Color = COLOR.wood
	header.Material = Enum.Material.Wood
	header.Anchored = true
	header.CanCollide = false
	header.CanQuery = false
	header.CanTouch = false
	-- Beside the board rather than at the plot root, so a stand that has been
	-- grouped in Studio keeps its header inside that group.
	header.Parent = board.Parent

	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlotSign"
	gui.Face = Enum.NormalId.Front
	-- The MODE, not just the number: a SurfaceGui left on its default
	-- 800×600 canvas ignores PixelsPerStud, which on a plank this wide
	-- would letterbox the name into the top third of the wood.
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.MaxDistance = 260
	gui.Parent = header

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.new(0, 8, 0, 4)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "Empty Plot"
	label.TextColor3 = Color3.fromRGB(230, 226, 220)
	label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Parent = gui

	return label
end

-- One plot: a raised pad with a fence, a sign, and a cannon on it aimed out
-- over the water. The cannon is the interactive bit — everything else is
-- there to make the pad feel like somewhere rather than a square of floor.
local function buildPlot(index: number): Plot
	local angle = (index - 1) / Island.PLOT_COUNT * math.pi * 2
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local centre = outward * PLOT_RING
	local frame = CFrame.new(centre + Vector3.new(0, GROUND_Y, 0)) * CFrame.Angles(0, -angle, 0)

	local folder = Instance.new("Folder")
	folder.Name = ("Plot%d"):format(index)
	-- The plot's position, stamped as data rather than left to be read off
	-- the geometry. The client needs it to aim flights out of this plot, and
	-- reading it from a child part was a race: a folder's attributes arrive
	-- with the folder, but its PARTS can replicate later (later still with
	-- streaming on), and a client that looked too early found no part, gave
	-- up silently, and then had "no plot adopted" when the cannon fired.
	folder:SetAttribute("PlotCenter", centre)
	folder.Parent = folders.Plots

	-- The pad, with a lip of path colour around it so it reads as built. Both
	-- are placed by their top face on their own level — see the Y table.
	local rim = block(
		Vector3.new(PLOT_SIZE + 5, 2, PLOT_SIZE + 5),
		frame * CFrame.new(0, slabAt(Y.plotRim, 2), 0),
		COLOR.path,
		folder
	)
	studded(rim)

	local pad =
		block(Vector3.new(PLOT_SIZE, 2.4, PLOT_SIZE), frame * CFrame.new(0, slabAt(Y.plotPad, 2.4), 0), COLOR.grassDark, folder)
	studded(pad)
	-- Named for the ADOPTION path: a baked world re-derives each plot's
	-- centre from this pad, so a plot dragged somewhere new in Studio still
	-- fires its flights from where it actually stands.
	pad.Name = "PlotPad"

	-- A low fence on the three sides that are not the entrance.
	local half = PLOT_SIZE * 0.5
	for _, spec in
		{
			{ size = Vector3.new(1, 3, PLOT_SIZE), offset = Vector3.new(half, 3, 0) },
			{ size = Vector3.new(PLOT_SIZE, 3, 1), offset = Vector3.new(0, 3, half) },
			{ size = Vector3.new(PLOT_SIZE, 3, 1), offset = Vector3.new(0, 3, -half) },
		}
	do
		local fence = block(spec.size, frame * CFrame.new(spec.offset), COLOR.plank, folder)
		fence.Material = Enum.Material.WoodPlanks
	end

	-- The cannon. The imported "Squishy Cannon" model when it exists, and the
	-- old built-from-parts one otherwise, so a place without the import still
	-- has a cannon on every plot rather than an empty pad.
	buildCannon(frame, folder)

	-- Where the prompt lives: an INVISIBLE host at head height beside the
	-- cannon, deliberately separate from whatever scenery stands there. The
	-- visible half is buildStation's capsule pod (or its fallback), and
	-- swapping that scenery can never break the interaction because the
	-- interaction was never attached to it.
	local station = Instance.new("Part")
	-- Named for the ADOPTION path: the plot's one true prompt host, found by
	-- name in a baked world rather than trusted to be the only prompt (an
	-- imported model could smuggle one in).
	station.Name = "Station"
	station.Size = Vector3.new(4, 6, 4)
	-- On the same STATION_BACK as the capsule, so the "hold E" hint sits at
	-- the thing the player is actually walking up to.
	station.CFrame = frame * CFrame.new(-STATION_BACK, 4, 0)
	station.Transparency = 1
	station.CanCollide = false
	station.Anchored = true
	station.Parent = folder

	buildStation(frame, folder)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Launch"
	prompt.ObjectText = "Your Cannon"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false -- until somebody owns this plot
	prompt.Parent = station

	-- The name rides the upgrade board rather than a post of its own: one
	-- structure in the walk-in corner instead of a bare stick at one corner
	-- and a label hanging over the cannon. The gui inside is named PlotSign
	-- for the ADOPTION path, which finds the owner's label by that name.
	local board = buildBoardStand(centre, folder)
	local sign = attachPlotSign(board :: BasePart)

	return {
		index = index,
		folder = folder,
		centre = centre,
		facing = angle,
		sign = sign,
		prompt = prompt,
		owner = nil,
	}
end

-- ---------- spawn ----------

local function buildSpawn()
	local spawns = group("Spawn")

	-- In the middle of the plaza, deliberately NOT inside anybody's cannon.
	local pad = cylinder(24, 1.6, Vector3.new(0, slabAt(Y.plaza + 0.2, 1.6), 0), COLOR.path, spawns)
	studded(pad)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn"
	spawn.Size = Vector3.new(18, 1, 18)
	spawn.CFrame = CFrame.new(0, Y.plaza + 0.7, 0)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 1
	spawn.Neutral = true
	-- Off, or Roblox draws its own glowing ring on top of the plaza.
	spawn.Enabled = true
	spawn.Duration = 0
	spawn.Parent = spawns

	signPost(Vector3.new(0, Y.plaza, -20), "🚀 Squishy Launcher", Color3.fromRGB(252, 214, 132), spawns)
end

-- ---------- assembly ----------

-- The sky. Two paths, in order of preference:
--
-- 1. Config.SkyTextures filled in: the server BUILDS the sky from those ids
--    at every startup. Code cannot lose it; the place file is irrelevant.
-- 2. Config empty: adopt a Sky instance from wherever Studio dropped it
--    (Lighting, ReplicatedStorage, Workspace, nested anywhere), seat it in
--    Lighting — and print its ids as a ready-to-paste Config line, which is
--    the exit ramp to path 1. A Sky that lives only in the place file has
--    already vanished between sessions once.
--
-- Lighting replicates, so every player gets the sky either way without the
-- client doing anything.
local function adoptSkybox()
	local lighting = game:GetService("Lighting")

	local wanted: any = (Config :: any).SkyTextures
	if wanted then
		local sky = lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
		sky.SkyboxBk = wanted.Bk
		sky.SkyboxDn = wanted.Dn
		sky.SkyboxFt = wanted.Ft
		sky.SkyboxLf = wanted.Lf
		sky.SkyboxRt = wanted.Rt
		sky.SkyboxUp = wanted.Up
		if wanted.SunAngularSize then
			sky.SunAngularSize = wanted.SunAngularSize
		end
		if wanted.MoonAngularSize then
			sky.MoonAngularSize = wanted.MoonAngularSize
		end
		sky.Parent = lighting
		return
	end

	local sky: Sky? = nil
	for _, container in { lighting :: Instance, ReplicatedStorage :: Instance, workspace :: Instance } do
		for _, descendant in container:GetDescendants() do
			if descendant:IsA("Sky") then
				sky = descendant
				break
			end
		end
		if sky then
			break
		end
	end
	if not sky then
		warn(
			"[SquishyClicker] No skybox found — insert the Realistic Sky anywhere (Lighting or ReplicatedStorage) and it will be adopted, and its ids printed for Config.SkyTextures."
		)
		return
	end

	sky.Parent = lighting
	-- The exit ramp: paste this over Config's `SkyTextures = false,` and the
	-- sky stops depending on the place file forever.
	print("[SquishyClicker] Sky adopted. To make it permanent, paste this into Config.luau:")
	print(
		("\tSkyTextures = { Bk = %q, Dn = %q, Ft = %q, Lf = %q, Rt = %q, Up = %q, SunAngularSize = %g, MoonAngularSize = %g },"):format(
			sky.SkyboxBk,
			sky.SkyboxDn,
			sky.SkyboxFt,
			sky.SkyboxLf,
			sky.SkyboxRt,
			sky.SkyboxUp,
			sky.SunAngularSize,
			sky.MoonAngularSize
		)
	)
end

-- The sky pack also dumps post-processing effects into WORKSPACE, where they
-- silently do nothing — effects only run under Lighting or a camera. The
-- SunRays are worth adopting: the game has none, and god rays belong to the
-- realistic sun. The pack's Bloom, Blur and ColorCorrection are NOT — the
-- client already builds its own tuned bloom and grade (Scene.luau), and
-- stacking a second set on top is exactly how the over-bright washout looked
-- before, with a screen blur thrown in. Those get cleared, loudly.
local function adoptSkyEffects()
	local lighting = game:GetService("Lighting")
	for _, child in workspace:GetChildren() do
		if child:IsA("SunRaysEffect") then
			if lighting:FindFirstChildOfClass("SunRaysEffect") then
				child:Destroy()
			else
				child.Parent = lighting
			end
		elseif child:IsA("PostEffect") then
			warn(("[SquishyClicker] Removed a stray %s from Workspace — the game runs its own tuned post-processing."):format(child.ClassName))
			child:Destroy()
		end
	end
end

-- The name sign, for a plot that came out of the place file rather than out
-- of buildPlot. A world baked since the sign moved onto the board hands its
-- header straight back; anything older is carrying the RETIRED shape — a
-- bare 7-stud post at the far corner with the label hanging 32 studs over
-- it — and that gets torn out and re-nailed to the board. Doing the repair
-- here rather than asking for a re-bake means an old place file opens with
-- the sign already fixed.
local function adoptPlotSign(folder: Instance, board: BasePart): TextLabel
	local existing = folder:FindFirstChild("PlotSign", true)
	local host = existing and existing.Parent

	if existing and host and host.Name == SIGN_HEADER then
		local label = existing:FindFirstChildOfClass("TextLabel")
		if label then
			return label :: TextLabel
		end
	end

	if host and host:IsA("BasePart") then
		-- The old post is unnamed, so it is matched on SHAPE: the one
		-- 0.6×7×0.6 stick standing under the label's anchor. The board's own
		-- legs are 0.7 thick and stand elsewhere, so they survive this.
		local at = host.Position
		for _, part in folder:GetDescendants() do
			if
				part ~= host
				and part:IsA("BasePart")
				and (part.Size - Vector3.new(0.6, 7, 0.6)).Magnitude < 0.05
				and Vector3.new(part.Position.X - at.X, 0, part.Position.Z - at.Z).Magnitude < 1.5
			then
				part:Destroy()
			end
		end
		host:Destroy() -- takes the gui with it
	elseif existing then
		existing:Destroy()
	end

	local strandedHeader = folder:FindFirstChild(SIGN_HEADER, true)
	if strandedHeader then
		strandedHeader:Destroy()
	end

	return attachPlotSign(board)
end

-- ---------- adopting a baked world ----------
-- The world can be BAKED: run Island.build() once from Studio's command bar
-- in EDIT mode, and the whole map is constructed as ordinary saved parts —
-- editable, movable, deletable by hand like any Roblox place. At runtime,
-- finding that Map folder already in Workspace means the place file owns
-- the world: nothing is rebuilt, and this instead walks the plots and wires
-- the live bookkeeping (signs, prompts, centres) onto whatever the builder
-- left — or the builder moved, since centres re-derive from the geometry.
local function adoptPlots(map: Folder): boolean
	local plotsFolder = map:FindFirstChild("Plots")
	if not plotsFolder then
		return false
	end

	-- Every folder named PlotN counts, not a fixed 1..8: duplicating a plot
	-- folder in Studio and renaming it Plot9 is how a hand-built island
	-- grows a ninth cannon.
	local found: { { index: number, folder: Folder } } = {}
	for _, child in plotsFolder:GetChildren() do
		local index = tonumber(child.Name:match("^Plot(%d+)$"))
		if index and child:IsA("Folder") then
			table.insert(found, { index = index, folder = child })
		end
	end
	table.sort(found, function(a, b)
		return a.index < b.index
	end)

	for _, entry in found do
		local folder = entry.folder

		-- The centre comes from the PAD where possible — the one honest
		-- record of where the plot actually stands after hand edits — with
		-- the stamped attribute as the fallback for a pad that was deleted.
		local pad = folder:FindFirstChild("PlotPad", true)
		local centre: Vector3? = nil
		if pad and pad:IsA("BasePart") then
			centre = Vector3.new(pad.Position.X, GROUND_Y, pad.Position.Z)
		else
			local stamped = folder:GetAttribute("PlotCenter")
			if typeof(stamped) == "Vector3" then
				centre = stamped
			end
		end

		local station = folder:FindFirstChild("Station", true)
		local prompt = station and station:FindFirstChildOfClass("ProximityPrompt")

		if not (centre and prompt) then
			warn(
				("[SquishyClicker] %s in the baked world is missing its %s — that plot is skipped. Delete the Map folder and re-bake to repair it."):format(
					folder.Name,
					not centre and "PlotPad" or "Station prompt"
				)
			)
			continue
		end

		local plotCentre = centre :: Vector3
		local plotPrompt = prompt :: ProximityPrompt

		-- A baked world from before the stands existed gets one grown in;
		-- a world that already carries its stand keeps it exactly as is.
		local board = findBoardPart(folder) or buildBoardStand(plotCentre, folder)
		if not board then
			warn(
				("[SquishyClicker] %s in the baked world has no UpgradeBoard and sits too near the island centre to grow one — that plot is skipped."):format(
					folder.Name
				)
			)
			continue
		end

		local plotSign = adoptPlotSign(folder, board :: BasePart)

		-- Re-stamped rather than trusted: the client aims flights off this
		-- attribute, and a hand-moved plot must fire from where it stands
		-- now, not where the bake once put it. The session state resets too
		-- — a place saved mid-playtest may have frozen a claimed sign or a
		-- live prompt into the file.
		folder:SetAttribute("PlotCenter", plotCentre)
		folder:SetAttribute("OwnerUserId", nil)
		plotSign.Text = "Empty Plot"
		plotSign.TextColor3 = Color3.fromRGB(230, 226, 220)
		plotPrompt.Enabled = false

		table.insert(plots, {
			index = entry.index,
			folder = folder,
			centre = plotCentre,
			facing = math.atan2(plotCentre.Z, plotCentre.X),
			sign = plotSign,
			prompt = plotPrompt,
			owner = nil,
		})
	end

	-- ---------- the plot capsules ----------
	-- Hand-placed capsule models, matched to plots by GEOMETRY rather than
	-- by folder: paste-and-drag leaves parents and positions disagreeing in
	-- every direction (the builder's posed capsule sat in one plot's folder
	-- while standing at another plot's station, and a folder-trusting
	-- rescue hauled it away from the pose it was dialled into). A capsule
	-- STANDING in a plot is the builder's reference and is never touched;
	-- its pose — read live off the model, no hand-derived Euler angles to
	-- get wrong — replays onto a spare for every plot without one, each in
	-- its own frame (local +X = outward).
	local function plotFrame(centre: Vector3): CFrame
		return CFrame.new(centre.X, 0, centre.Z) * CFrame.Angles(0, -math.atan2(centre.Z, centre.X), 0)
	end

	local capsules: { Model } = {}
	for _, descendant in plotsFolder:GetDescendants() do
		if descendant:IsA("Model") and descendant.Name:lower():find("capsule", 1, true) then
			for _, part in descendant:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			table.insert(capsules, descendant)
		end
	end

	local function nearestPlot(position: Vector3): (number?, number)
		local bestIndex: number? = nil
		local bestAway = math.huge
		for index, plot in plots do
			local away = Vector3.new(position.X - plot.centre.X, 0, position.Z - plot.centre.Z).Magnitude
			if away < bestAway then
				bestAway = away
				bestIndex = index
			end
		end
		return bestIndex, bestAway
	end

	-- ONE MASTER POSE, every plot identical. The capsule standing closest
	-- to its plot is the master; every plot's capsule — already standing
	-- or drawn from the spares — snaps to exactly that pose in its own
	-- plot's frame. Re-posing the whole ring is therefore one job: move
	-- the master in Studio and every station follows at the next startup.
	local seatedBy: { [number]: Model } = {}
	local spares: { Model } = {}
	local masterRelative: CFrame? = nil
	local masterScale = 1
	local masterAway = math.huge
	for _, capsule in capsules do
		local index, away = nearestPlot(capsule:GetPivot().Position)
		if index and away <= PLOT_SIZE then
			if seatedBy[index] then
				table.insert(spares, capsule)
			else
				seatedBy[index] = capsule
			end
			if away < masterAway then
				masterAway = away
				masterRelative = plotFrame(plots[index].centre):ToObjectSpace(capsule:GetPivot())
				masterScale = capsule:GetScale()
			end
		else
			table.insert(spares, capsule)
		end
	end

	-- No master placed yet: an approximation of the dialled pose keeps a
	-- fresh world presentable until the builder stands one somewhere.
	local relative = masterRelative
		or CFrame.new(-14, 5.9, 0) * CFrame.fromOrientation(0, math.pi, math.rad(90))
	local scale = if masterRelative then masterScale else 1.571
	for index, plot in plots do
		local capsule = seatedBy[index] or table.remove(spares)
		if capsule then
			capsule:ScaleTo(scale)
			capsule:PivotTo(plotFrame(plot.centre) * relative)
		end
	end

	return #plots > 0
end

-- ---------- the nature pass ----------
-- Regreening for a BAKED world: the blocky built-from-parts trees, bushes
-- and rocks in Props are cleared (the stalls, found by their own prompts,
-- are spared) and the island is replanted from the hand-imported nature
-- pack — trees where trees were, plus rocks, logs, bushes and flowers
-- scattered across the grass between the plaza and the beach. Templates
-- are found by LOOSE name wherever the pack was dropped and classified by
-- keyword, so the pack needs no particular structure; every clone goes
-- through prepareImport (scripts stripped, parts anchored), Toolbox
-- hygiene being what it is. Runs at every startup until the world is
-- BAKED with it (run Island.build() from the command bar in edit mode and
-- save); the Nature folder is the already-dressed marker either way.
local function dressNature(map: Folder)
	if map:FindFirstChild("Nature") then
		return
	end

	-- The pack, wherever it landed — and moved into ReplicatedStorage if
	-- it is sitting in the world, where it does not belong.
	local pack: Instance? = nil
	for _, container in { ReplicatedStorage :: Instance, workspace :: Instance } do
		for _, child in container:GetDescendants() do
			if (child:IsA("Folder") or child:IsA("Model")) and child.Name:lower():find("nature", 1, true) then
				pack = child
				break
			end
		end
		if pack then
			break
		end
	end
	if not pack then
		return -- nothing imported yet; the blocky scenery keeps its job
	end
	if not pack:IsDescendantOf(ReplicatedStorage) then
		(pack :: Instance).Parent = ReplicatedStorage
	end

	-- Classify the pack's models by name. Depth-first preorder means
	-- parents come before children, so a matched tree's own "Trunk" or
	-- "Leaves" submodels never get claimed twice.
	local KEYWORDS: { [string]: { string } } = {
		tree = { "tree", "pine", "oak", "birch", "palm", "spruce", "fir" },
		rock = { "rock", "stone", "boulder", "pebble" },
		flower = { "flower", "tulip", "daisy", "rose", "sunflower", "plant", "mushroom" },
		log = { "log", "stump", "branch" },
		bush = { "bush", "shrub", "fern", "grass" },
	}
	local kinds: { [string]: { Model } } = { tree = {}, rock = {}, flower = {}, log = {}, bush = {} }
	local claimed: { [Instance]: boolean } = {}
	for _, descendant in pack:GetDescendants() do
		if descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("BasePart", true) then
			local ancestorClaimed = false
			local walk = descendant.Parent
			while walk and walk ~= pack do
				if claimed[walk] then
					ancestorClaimed = true
					break
				end
				walk = walk.Parent
			end
			if not ancestorClaimed then
				local name = descendant.Name:lower()
				for kind, words in KEYWORDS do
					local matched = false
					for _, word in words do
						if name:find(word, 1, true) then
							matched = true
							break
						end
					end
					if matched then
						table.insert(kinds[kind], descendant)
						claimed[descendant] = true
						break
					end
				end
			end
		end
	end
	if #kinds.tree == 0 then
		warn("[SquishyClicker] Nature pack found but no models named like trees — the old scenery stays until there are replacements.")
		return
	end

	-- The stalls, spared by position: theirs are the only parts in Props
	-- worth keeping, and their prompts say exactly where they stand.
	local stallAt: { Vector3 } = {}
	for _, descendant in map:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "SquishyMarket" then
			local host = descendant.Parent
			if host and host:IsA("BasePart") then
				table.insert(stallAt, host.Position)
			end
		end
	end

	local props = map:FindFirstChild("Props")
	if props then
		for _, child in props:GetChildren() do
			if child:IsA("BasePart") then
				local nearStall = false
				for _, at in stallAt do
					if Vector3.new(child.Position.X - at.X, 0, child.Position.Z - at.Z).Magnitude < 11 then
						nearStall = true
						break
					end
				end
				if not nearStall then
					child:Destroy()
				end
			end
		end
	end

	local nature = Instance.new("Folder")
	nature.Name = "Nature"
	nature.Parent = map

	-- Seeded, like the scenery it replaces: the island is laid out
	-- identically on every server.
	local rng = Random.new(20260821)

	-- Clear of the plaza, the beach, the ring road, the spokes (their
	-- width varies by how picky the caller is — flowers may hug paths
	-- that trees must not), the plots and the stalls.
	local function isClear(at: Vector3, minAcrossSpoke: number): boolean
		local radius = Vector3.new(at.X, 0, at.Z).Magnitude
		if radius < PLAZA_RADIUS + 4 or radius > ISLAND_RADIUS - BEACH_WIDTH - 6 then
			return false
		end
		if math.abs(radius - RING_ROAD) < PATH_WIDTH then
			return false
		end
		for _, plot in plots do
			local offset = at - plot.centre
			if math.abs(offset.X) < PLOT_SIZE * 0.75 and math.abs(offset.Z) < PLOT_SIZE * 0.75 then
				return false
			end
		end
		for _, stall in stallAt do
			if Vector3.new(at.X - stall.X, 0, at.Z - stall.Z).Magnitude < 14 then
				return false
			end
		end
		local angle = math.atan2(at.Z, at.X)
		local slot = angle / (math.pi * 2) * Island.PLOT_COUNT
		local offBySlots = math.abs(slot - math.floor(slot + 0.5))
		return offBySlots * (math.pi * 2 / Island.PLOT_COUNT) * radius > minAcrossSpoke
	end

	local planted: { [string]: number } = {}
	local function plant(kind: string, targetSize: number, jitter: number, minAcross: number, tries: number)
		local templates = kinds[kind]
		if #templates == 0 then
			return
		end
		planted[kind] = 0
		for _ = 1, tries do
			local angle = rng:NextNumber() * math.pi * 2
			local radius = rng:NextNumber(PLAZA_RADIUS + 4, ISLAND_RADIUS - BEACH_WIDTH - 6)
			local at = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			if isClear(at, minAcross) then
				local clone = templates[rng:NextInteger(1, #templates)]:Clone()
				if prepareImport(clone) then
					scaleImport(clone, targetSize * rng:NextNumber(1 - jitter, 1 + jitter))
					clone:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0))
					-- Stood on the grass by its own bounds, like everything
					-- else hand-imported.
					local boundsCF, boundsSize = clone:GetBoundingBox()
					local bottomY = boundsCF.Position.Y - boundsSize.Y * 0.5
					clone:PivotTo(clone:GetPivot() + Vector3.new(0, (GROUND_Y + Y.field) - bottomY, 0))
					clone.Parent = nature
					planted[kind] += 1
				else
					clone:Destroy()
				end
			end
		end
	end

	plant("tree", 14, 0.3, PATH_WIDTH, 60)
	plant("bush", 4.5, 0.35, PATH_WIDTH, 40)
	plant("rock", 4.5, 0.4, PATH_WIDTH, 34)
	plant("log", 5.5, 0.3, PATH_WIDTH, 20)
	-- Flowers may crowd closer to the paths and the plaza rim than the
	-- big stuff: they decorate the walk, not block it.
	plant("flower", 2, 0.35, 8, 90)

	local summary = {}
	for kind, count in planted do
		table.insert(summary, ("%d %s"):format(count, kind))
	end
	print(("[SquishyClicker] Nature pass planted: %s. Bake it in with Island.build() from the edit-mode command bar, then save."):format(table.concat(summary, ", ")))
end

function Island.build()
	-- Parent-checked rather than nil-checked: Studio's command bar caches
	-- this module, so a delete-the-Map-and-re-bake in the same session
	-- arrives here with a stale root pointing at destroyed geometry.
	if root and root.Parent then
		return -- already built; this is called once from the server's startup
	end
	root = nil :: any
	table.clear(plots)
	table.clear(folders)
	table.clear(placedCannons)

	adoptSkybox()
	adoptSkyEffects()

	-- The place file carries stowaways from the template it was made from: a
	-- Baseplate and its SpawnLocation. The baseplate is why the painted range
	-- VANISHED — its top sits at Y0 while the sea and every rainbow band lie
	-- 26 studs below it, so the entire target sat under the floor, and the
	-- "dark grey expanse" around the island was the baseplate itself. This
	-- sweep runs in BOTH world modes now: it used to sit after the baked
	-- world's adoption returned, so a baked place kept its baseplate forever
	-- and it hid the sea bands exactly the way it once hid the painted range.
	-- (A SpawnLocation caught here is the template's, never ours: IslandSpawn
	-- lives INSIDE the Map folder, out of this top-level sweep's reach.)
	for _, child in workspace:GetChildren() do
		if (child:IsA("BasePart") and child.Name == "Baseplate") or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	-- A Map folder already in Workspace is a BAKED world: the place file
	-- owns the geometry and this run only adopts it.
	local existing = workspace:FindFirstChild("Map")
	if existing and existing:IsA("Folder") then
		-- A baked world is GEOMETRY and nothing else: the bake writes no
		-- scripts, so any script found here rode in inside a hand-placed
		-- free model — which is exactly how Toolbox backdoors travel (one
		-- shipped inside a capsule model, complete with a fake "Model Parse
		-- Error" dialog begging to be pasted into the command bar). They
		-- are destroyed LOUDLY before adoption, every startup.
		for _, descendant in existing:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") then
				warn(("[SquishyClicker] Destroyed a stowaway script in the baked world: %s"):format(descendant:GetFullName()))
				descendant:Destroy()
			end
		end
		if adoptPlots(existing) then
			root = existing
			for _, child in existing:GetChildren() do
				if child:IsA("Folder") then
					folders[child.Name] = child
				end
			end
			-- After the plots, so the pass can place around their REAL
			-- centres, hand-moved or not.
			dressNature(existing)
			-- A baked world from before the range gets it grown in; a
			-- world already carrying its Range folder keeps it as is.
			buildRangeBands(existing)
			-- Same deal for the horizon mesas: grown into an older bake,
			-- kept as saved if the place already carries its Horizon folder.
			buildHorizon(existing)
			print(("[SquishyClicker] Adopted the baked world from the place file — %d plots wired."):format(#plots))
			return
		end
		-- A Map with no usable plots would leave the game unplayable, and
		-- building fresh INSIDE it would double the world. Stand the broken
		-- bake aside (runtime-only — the place file is untouched) and build.
		warn(
			"[SquishyClicker] A Map folder exists but no plots could be adopted — it has been set aside as 'Map (unadopted)' for this session and a fresh world built. Delete the Map folder in Studio and re-bake to fix the place."
		)
		existing.Name = "Map (unadopted)"
	end

	root = Instance.new("Folder")
	root.Name = "Map"

	group("Plots")

	buildGround()
	buildRangeBands(root)
	buildHorizon(root)
	buildPaths()
	buildScenery()
	buildSpawn()

	for index = 1, Island.PLOT_COUNT do
		table.insert(plots, buildPlot(index))
	end

	-- Parented LAST, in one step: baking from the Studio command bar runs
	-- this exact function in edit mode, and a whole world arriving at once
	-- is kinder to the editor than five hundred parts trickling in.
	root.Parent = workspace
end

-- Hand a free plot to a player. Returns nil when the island is full, which the
-- caller has to cope with rather than assume away — a server can hold more
-- players than there are plots.
function Island.claim(player: Player): Plot?
	for _, plot in plots do
		if plot.owner == nil then
			plot.owner = player
			plot.sign.Text = ("🏠 %s"):format(player.DisplayName)
			plot.sign.TextColor3 = Color3.fromRGB(252, 214, 132)
			plot.prompt.Enabled = true
			-- Stamped on the folder so the client can tell whose plot it is
			-- without another remote: the prompt fires locally, and the owner
			-- check has to happen there to keep it instant.
			plot.folder:SetAttribute("OwnerUserId", player.UserId)
			return plot
		end
	end
	return nil
end

function Island.release(player: Player)
	for _, plot in plots do
		if plot.owner == player then
			plot.owner = nil
			plot.sign.Text = "Empty Plot"
			plot.sign.TextColor3 = Color3.fromRGB(230, 226, 220)
			plot.prompt.Enabled = false
			plot.folder:SetAttribute("OwnerUserId", nil)
		end
	end
end

function Island.plotOf(player: Player): Plot?
	for _, plot in plots do
		if plot.owner == player then
			return plot
		end
	end
	return nil
end

return Island
