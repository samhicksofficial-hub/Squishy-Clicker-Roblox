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
--  Everything here is anchored and generated once at startup.
-- ============================================================

local Island = {}

-- ---------- dimensions ----------
-- One radius drives the whole layout, so the island can be resized by
-- changing this and letting everything else fall out of it.
local ISLAND_RADIUS = 130
local BEACH_WIDTH = 14
local PLAZA_RADIUS = 34
local PLOT_SIZE = 34
local PLOT_RING = ISLAND_RADIUS - 34 -- how far out the plots sit
local PATH_WIDTH = 12
local GROUND_Y = 0 -- top of the grass; everything else is measured off it

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

local function signPost(at: Vector3, text: string, color: Color3, parent: Instance): TextLabel
	local post = decor(block(Vector3.new(0.6, 7, 0.6), CFrame.new(at + Vector3.new(0, 3.5, 0)), COLOR.wood, parent))
	post.Material = Enum.Material.Wood

	local board = Instance.new("Part")
	board.Size = Vector3.new(0.4, 0.4, 0.4)
	board.CFrame = CFrame.new(at + Vector3.new(0, 8.6, 0))
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

	-- Water first, widest and lowest, so the island reads as sitting in it.
	local water = cylinder((ISLAND_RADIUS + 40) * 2, 2, Vector3.new(0, GROUND_Y - 3, 0), COLOR.water, ground)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.25
	decor(water)

	-- Beach, then the grass top sitting inside it.
	local beach = cylinder(ISLAND_RADIUS * 2, 5, Vector3.new(0, GROUND_Y - 2.5, 0), COLOR.sand, ground)
	beach.Material = Enum.Material.Sand

	local field = cylinder((ISLAND_RADIUS - BEACH_WIDTH) * 2, 5, Vector3.new(0, GROUND_Y - 2.4, 0), COLOR.grass, ground)
	studded(field)

	-- The plaza: a stone disc in the middle, very slightly proud of the grass
	-- so its edge catches the light rather than z-fighting with it.
	local plaza = cylinder(PLAZA_RADIUS * 2, 1.2, Vector3.new(0, GROUND_Y + 0.1, 0), COLOR.stone, ground)
	studded(plaza)
	local plazaRim = cylinder((PLAZA_RADIUS + 2) * 2, 1, Vector3.new(0, GROUND_Y - 0.1, 0), COLOR.path, ground)
	studded(plazaRim)
end

-- ---------- the canyon ring ----------
-- Terraced red rock around the rim, capped with grass, the same language as
-- the launch valley. Built as a ring of segments rather than a smooth shape:
-- the blockiness is the look, and it means plain Parts throughout.
local function buildCanyon()
	local canyon = group("Canyon")

	local STEPS = 4
	local STEP_HEIGHT = 7
	local STEP_DEPTH = 9
	local SEGMENTS = 44

	for step = 1, STEPS do
		local radius = ISLAND_RADIUS + 6 + (step - 1) * STEP_DEPTH
		local height = step * STEP_HEIGHT
		-- Chord length for one segment of a ring at this radius, plus a little
		-- overlap so the joins never show a gap.
		local width = 2 * math.pi * radius / SEGMENTS + 2

		for index = 1, SEGMENTS do
			local angle = (index / SEGMENTS) * math.pi * 2
			local at = Vector3.new(math.cos(angle) * radius, GROUND_Y + height * 0.5 - 2, math.sin(angle) * radius)
			local face = CFrame.new(at) * CFrame.Angles(0, -angle, 0)

			local wall = block(Vector3.new(STEP_DEPTH, height, width), face, COLOR.rock, canyon)
			wall.Material = Enum.Material.Sandstone

			local lip = block(
				Vector3.new(STEP_DEPTH, 1, width),
				face * CFrame.new(0, height * 0.5 + 0.5, 0),
				COLOR.rockTop,
				canyon
			)
			studded(lip)
		end
	end
end

-- ---------- paths ----------
-- One spoke out to each plot, plus a ring road joining them. Laid as a run of
-- overlapping blocks rather than one long rotated slab, so a path can bend
-- later without the geometry fighting it.
local function buildPaths()
	local paths = group("Paths")

	for index = 1, Island.PLOT_COUNT do
		local angle = (index - 1) / Island.PLOT_COUNT * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local from = PLAZA_RADIUS - 1
		local to = PLOT_RING - PLOT_SIZE * 0.4

		local length = to - from
		local centre = direction * (from + length * 0.5)
		local spoke = block(
			Vector3.new(length, 0.8, PATH_WIDTH),
			CFrame.new(centre + Vector3.new(0, GROUND_Y + 0.05, 0)) * CFrame.Angles(0, -angle, 0),
			COLOR.path,
			paths
		)
		studded(spoke)
	end

	-- The ring road, as segments following the plot circle.
	local SEGMENTS = 56
	local radius = PLOT_RING - PLOT_SIZE * 0.75
	local width = 2 * math.pi * radius / SEGMENTS + 1.5
	for index = 1, SEGMENTS do
		local angle = (index / SEGMENTS) * math.pi * 2
		local at = Vector3.new(math.cos(angle) * radius, GROUND_Y + 0.05, math.sin(angle) * radius)
		local ring = block(
			Vector3.new(PATH_WIDTH * 0.8, 0.8, width),
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

	-- Stalls in an arc around one side of the plaza.
	for index = 1, 4 do
		local angle = math.rad(200 + (index - 1) * 25)
		local at = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (PLAZA_RADIUS + 12)
		buildStall(Vector3.new(at.X, GROUND_Y, at.Z), -angle + math.pi, props)
	end

	-- Trees, bushes and rocks between the ring road and the beach, well clear
	-- of the plots and the spokes.
	for _ = 1, 90 do
		local angle = rng:NextNumber() * math.pi * 2
		local radius = rng:NextNumber(PLAZA_RADIUS + 16, ISLAND_RADIUS - BEACH_WIDTH - 6)
		local at = Vector3.new(math.cos(angle) * radius, GROUND_Y, math.sin(angle) * radius)

		-- Keep the ring road and the plot pads clear.
		local nearRing = math.abs(radius - (PLOT_RING - PLOT_SIZE * 0.75)) < PATH_WIDTH
		local plotSlot = (angle / (math.pi * 2)) * Island.PLOT_COUNT
		local nearPlot = math.abs(plotSlot - math.floor(plotSlot + 0.5)) < 0.28
			and math.abs(radius - PLOT_RING) < PLOT_SIZE
		if not (nearRing or nearPlot) then
			local roll = rng:NextNumber()
			if roll < 0.5 then
				buildTree(at, rng:NextNumber(0.8, 1.4), props)
			elseif roll < 0.78 then
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
	folder.Parent = folders.Plots

	-- The pad, with a lip of path colour around it so it reads as built.
	local pad = block(Vector3.new(PLOT_SIZE, 1.6, PLOT_SIZE), frame * CFrame.new(0, 0.8, 0), COLOR.grassDark, folder)
	studded(pad)
	local rim = block(
		Vector3.new(PLOT_SIZE + 3, 1.2, PLOT_SIZE + 3),
		frame * CFrame.new(0, 0.5, 0),
		COLOR.path,
		folder
	)
	studded(rim)

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

	-- The cannon: a cream plinth and a fat barrel, pointed out over the water
	-- and tilted up. Simplified from the one on the launch stage — this one is
	-- scenery plus a prompt, and the real shot is drawn on the client.
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

	-- Where the prompt lives. Its own small part at head height beside the
	-- plinth, so the "hold E" hint sits where a player walking up expects it
	-- rather than buried inside the barrel.
	local station = Instance.new("Part")
	station.Size = Vector3.new(3, 5, 3)
	station.CFrame = frame * CFrame.new(-6, 3.5, 0)
	station.Color = COLOR.plank
	station.Material = Enum.Material.WoodPlanks
	station.Anchored = true
	station.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Launch"
	prompt.ObjectText = "Your Cannon"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false -- until somebody owns this plot
	prompt.Parent = station

	local sign = signPost(centre + Vector3.new(0, GROUND_Y + 1.6, 0) - outward * (half - 3), "Empty Plot", Color3.fromRGB(
		230,
		226,
		220
	), folder)

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
	local pad = cylinder(18, 1.4, Vector3.new(0, GROUND_Y + 0.9, 0), COLOR.path, spawns)
	studded(pad)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "IslandSpawn"
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = CFrame.new(0, GROUND_Y + 1.7, 0)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 1
	spawn.Neutral = true
	-- Off, or Roblox draws its own glowing ring on top of the plaza.
	spawn.Enabled = true
	spawn.Duration = 0
	spawn.Parent = spawns

	signPost(Vector3.new(0, GROUND_Y + 1.6, -14), "🚀 Squishy Launcher", Color3.fromRGB(252, 214, 132), spawns)
end

-- ---------- assembly ----------

function Island.build()
	if root then
		return -- already built; this is called once from the server's startup
	end

	root = Instance.new("Folder")
	root.Name = "Map"
	root.Parent = workspace

	group("Plots")

	buildGround()
	buildCanyon()
	buildPaths()
	buildScenery()
	buildSpawn()

	for index = 1, Island.PLOT_COUNT do
		table.insert(plots, buildPlot(index))
	end
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
