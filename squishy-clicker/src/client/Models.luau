--!strict
-- ============================================================
--  3D MODELS  —  the bamboo steamer and every squishy shape,
--  built out of Roblox primitives at runtime. Nothing here is an
--  uploaded asset, so reshaping a model means editing numbers in
--  this file and reconnecting Rojo.
--
--  Roblox parts have no transform hierarchy — you cannot parent a
--  part to a part and have it follow along. So each model is a
--  RIG: a list of pieces plus the offset each piece sits at
--  relative to the model's origin. Models.apply(rig, cf, scale)
--  rewrites every piece's CFrame and Size, which is what lets us
--  move AND squash a whole model as though it were one object.
--
--  Squishies are built per-reveal by Models.buildSquishy: the
--  catalog's `shape` field picks a builder from `shapeBuilders`,
--  which constructs the model already tinted in the squishy's
--  colour. Add a new shape: one builder function, then name it
--  from a catalog entry in Squishies.luau.
-- ============================================================

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = {}

-- ---------- glitter ----------
-- The glittery squishies get a real sparkly surface rather than flat plastic.
-- Roblox can't be handed a local image, so upload assets/glitter/glitter.png
-- (Asset Manager → Import) and paste its id here. Leave it empty and the
-- glittery ones simply wear their colour, no harm done.
local GLITTER_TEXTURE = ""
-- Roughly one tile across a squishy. Tiling any tighter and the flakes shrink
-- below a pixel on screen, where they average back into flat grey.
local GLITTER_STUDS_PER_TILE = 2.5

local glitterVariant: MaterialVariant? = nil

local function ensureGlitter(): MaterialVariant?
	if GLITTER_TEXTURE == "" then
		return nil
	end
	if glitterVariant then
		return glitterVariant
	end
	local variant = Instance.new("MaterialVariant")
	variant.Name = "SquishyGlitter"
	variant.BaseMaterial = Enum.Material.Plastic
	variant.ColorMap = GLITTER_TEXTURE
	variant.StudsPerTile = GLITTER_STUDS_PER_TILE
	variant.Parent = MaterialService
	glitterVariant = variant
	return variant
end

-- The part keeps its own Color, and a MaterialVariant's colour map multiplies
-- by it — so one gold glitter sheet becomes gold, pink or green glitter to
-- match whatever squishy is wearing it.
local function applyGlitter(part: BasePart)
	if not ensureGlitter() then
		return
	end
	-- Glass and neon are left alone: being see-through or glowing is the whole
	-- point of the squishies that use them, and glitter would flatten that.
	if part.Material ~= Enum.Material.SmoothPlastic and part.Material ~= Enum.Material.Plastic then
		return
	end
	part.Material = Enum.Material.Plastic
	part.MaterialVariant = "SquishyGlitter"
end

-- Cylinder parts run along their own X axis; this stands one upright.
local UPRIGHT = CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)

local BAMBOO_LIGHT = Color3.fromRGB(226, 190, 142)
local BAMBOO_DARK = Color3.fromRGB(198, 156, 110)
local BAMBOO_LINE = Color3.fromRGB(166, 124, 82)
local INTERIOR = Color3.fromRGB(102, 70, 46)
local FACE_INK = Color3.fromRGB(74, 52, 38)
local LEAF_GREEN = Color3.fromRGB(96, 176, 88)
local TIP_BROWN = Color3.fromRGB(122, 86, 48)
local TUB_CREAM = Color3.fromRGB(246, 240, 230)

export type Piece = { inst: BasePart, offset: CFrame, size: Vector3 }
export type Rig = { folder: Folder, pieces: { Piece } }

export type SquishyModel = {
	rig: Rig,
	primary: BasePart,
	face: TextLabel?,
	billboard: BillboardGui?,
	sparkles: ParticleEmitter,
	-- True when this squishy has a billboard face to switch on. Only dumplings
	-- do, and not even those when their texture already paints one.
	wearsFace: boolean,
	-- The catalog's size multiplier, carried here so every place that draws
	-- this squishy scales it the same way.
	sizeScale: number,
}

-- ---------- rig plumbing ----------

function Models.newRig(name: string, parent: Instance): Rig
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return { folder = folder, pieces = {} }
end

function Models.add(rig: Rig, inst: BasePart, offset: CFrame)
	table.insert(rig.pieces, { inst = inst, offset = offset, size = inst.Size })
	inst.Parent = rig.folder
end

-- How much a rig-space scale stretches a part along one of its OWN axes.
-- Every rotation we use is a multiple of 90 degrees, so this is exact: it
-- just picks out whichever rig axis that part's axis happens to point down.
local function axisScale(axis: Vector3, scale: Vector3): number
	return math.abs(axis.X) * scale.X + math.abs(axis.Y) * scale.Y + math.abs(axis.Z) * scale.Z
end

function Models.apply(rig: Rig, cf: CFrame, scale: Vector3)
	for _, piece in rig.pieces do
		local rot = piece.offset.Rotation
		local pos = piece.offset.Position

		piece.inst.CFrame = cf * CFrame.new(pos.X * scale.X, pos.Y * scale.Y, pos.Z * scale.Z) * rot

		local size = piece.size
			* Vector3.new(
				axisScale(rot.RightVector, scale),
				axisScale(rot.UpVector, scale),
				axisScale(-rot.LookVector, scale)
			)
		-- Parts refuse sizes below 0.05 on any axis.
		piece.inst.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	end
end

-- ---------- part helper ----------

local function newPart(shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- ---------- the steamer ----------

-- The tub. Its origin sits on the floor at the centre, so scaling squashes it
-- downward and keeps it planted instead of sinking through the ground.
function Models.buildSteamerBase(parent: Instance): Rig
	local rig = Models.newRig("SteamerBase", parent)

	local function ring(y: number, height: number, diameter: number, color: Color3): Part
		local part = newPart(Enum.PartType.Cylinder, Vector3.new(height, diameter, diameter), color, Enum.Material.Wood)
		Models.add(rig, part, CFrame.new(0, y, 0) * UPRIGHT)
		return part
	end

	ring(1.0, 2.0, 5.0, BAMBOO_LIGHT) -- tub body
	ring(0.16, 0.32, 5.25, BAMBOO_DARK) -- foot
	ring(1.92, 0.42, 5.32, BAMBOO_DARK) -- top rim
	for i = 1, 3 do -- woven bands
		ring(0.55 + (i - 1) * 0.45, 0.13, 5.12, BAMBOO_LINE)
	end
	ring(2.1, 0.16, 4.5, INTERIOR) -- the inside, revealed when the lid comes off

	return rig
end

-- The domed lid. Origin sits at its underside so it can rest exactly on top
-- of the tub, and so tilting it pivots around the rim rather than mid-air.
function Models.buildSteamerLid(parent: Instance): Rig
	local rig = Models.newRig("SteamerLid", parent)

	local band = newPart(Enum.PartType.Cylinder, Vector3.new(0.58, 5.38, 5.38), BAMBOO_DARK, Enum.Material.Wood)
	Models.add(rig, band, CFrame.new(0, 0.29, 0) * UPRIGHT)

	for i = 1, 2 do
		local line = newPart(Enum.PartType.Cylinder, Vector3.new(0.1, 5.44, 5.44), BAMBOO_LINE, Enum.Material.Wood)
		Models.add(rig, line, CFrame.new(0, 0.16 + (i - 1) * 0.26, 0) * UPRIGHT)
	end

	local dome = newPart(Enum.PartType.Ball, Vector3.new(5.0, 1.7, 5.0), BAMBOO_LIGHT, Enum.Material.Wood)
	Models.add(rig, dome, CFrame.new(0, 0.6, 0))

	local stem = newPart(Enum.PartType.Cylinder, Vector3.new(0.3, 0.5, 0.5), BAMBOO_LINE, Enum.Material.Wood)
	Models.add(rig, stem, CFrame.new(0, 1.4, 0) * UPRIGHT)

	local knob = newPart(Enum.PartType.Cylinder, Vector3.new(0.26, 1.25, 1.25), BAMBOO_DARK, Enum.Material.Wood)
	Models.add(rig, knob, CFrame.new(0, 1.62, 0) * UPRIGHT)

	return rig
end

-- ---------- squishy shape builders ----------
-- Each builder fills the rig with parts already tinted in the squishy's
-- colour and returns the PRIMARY part — the one the face and sparkles ride
-- on. Origins sit at the model's centre; keep everything within roughly
-- 2.5 studs so every shape reads the same size inside the steamer.

local function ball(rig: Rig, size: Vector3, color: Color3, offset: CFrame, material: Enum.Material?): Part
	local part = newPart(Enum.PartType.Ball, size, color, material or Enum.Material.SmoothPlastic)
	Models.add(rig, part, offset)
	return part
end

local function box(rig: Rig, size: Vector3, color: Color3, offset: CFrame, material: Enum.Material?): Part
	local part = newPart(Enum.PartType.Block, size, color, material or Enum.Material.SmoothPlastic)
	Models.add(rig, part, offset)
	return part
end

local shapeBuilders: { [string]: (Rig, Color3) -> BasePart } = {}

shapeBuilders.dumpling = function(rig, color)
	local body = ball(rig, Vector3.new(2.5, 2.0, 2.5), color, CFrame.new(0, 0, 0))
	local pleatColor = color:Lerp(Color3.new(1, 1, 1), 0.24)
	for i = 1, 5 do
		local t = (i - 3) / 2 -- -1 .. 1
		ball(
			rig,
			Vector3.new(0.66, 0.54, 0.66),
			pleatColor,
			CFrame.new(t * 0.9, 0.78 - math.abs(t) * 0.14, 0.3 - math.abs(t) * 0.12)
		)
	end
	return body
end

shapeBuilders.ball = function(rig, color)
	return ball(rig, Vector3.new(2.4, 2.15, 2.4), color, CFrame.new(0, 0, 0), Enum.Material.Glass)
end

-- Jelly cubes are translucent so they read as jelly, not dice.
shapeBuilders.jellycube = function(rig, color)
	local body = box(rig, Vector3.new(2.1, 2.1, 2.1), color, CFrame.new(0, 0, 0), Enum.Material.Glass)
	body.Transparency = 0.3
	return body
end

shapeBuilders.cheese = function(rig, color)
	local body = box(rig, Vector3.new(2.3, 1.7, 2.3), color, CFrame.new(0, 0, 0))
	local holeColor = color:Lerp(Color3.fromRGB(90, 60, 15), 0.4)
	-- Half-sunk darker balls fake the holes.
	ball(rig, Vector3.new(0.7, 0.7, 0.7), holeColor, CFrame.new(-0.6, 0.55, 0.85))
	ball(rig, Vector3.new(0.5, 0.5, 0.5), holeColor, CFrame.new(0.7, -0.2, 0.95))
	ball(rig, Vector3.new(0.6, 0.6, 0.6), holeColor, CFrame.new(0.15, 0.86, -0.2))
	ball(rig, Vector3.new(0.55, 0.55, 0.55), holeColor, CFrame.new(-1.0, -0.35, 0.2))
	return body
end

shapeBuilders.banana = function(rig, color)
	-- Balls along a downward arc make the curve; shrinking ends taper it.
	local body: Part? = nil
	for i = 1, 7 do
		local t = (i - 4) / 3 -- -1 .. 1
		local diameter = 0.95 - math.abs(t) * 0.35
		local segment = ball(
			rig,
			Vector3.new(diameter, diameter, diameter),
			color,
			CFrame.new(t * 1.35, 0.35 - t * t * 0.95, 0)
		)
		if i == 4 then
			body = segment
		end
	end
	ball(rig, Vector3.new(0.4, 0.4, 0.4), TIP_BROWN, CFrame.new(-1.5, -0.68, 0))
	ball(rig, Vector3.new(0.4, 0.4, 0.4), TIP_BROWN, CFrame.new(1.5, -0.68, 0))
	return body :: Part
end

shapeBuilders.strawberry = function(rig, color)
	local body = ball(rig, Vector3.new(2.3, 2.5, 2.3), color, CFrame.new(0, -0.1, 0))
	-- Leaf crown: flattened green balls around a stubby stem.
	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2
		ball(
			rig,
			Vector3.new(0.8, 0.28, 0.5),
			LEAF_GREEN,
			CFrame.new(math.cos(angle) * 0.55, 1.05, math.sin(angle) * 0.55)
		)
	end
	local stem = newPart(Enum.PartType.Cylinder, Vector3.new(0.5, 0.25, 0.25), LEAF_GREEN, Enum.Material.SmoothPlastic)
	Models.add(rig, stem, CFrame.new(0, 1.3, 0) * UPRIGHT)
	return body
end

shapeBuilders.brain = function(rig, color)
	-- Two lumpy hemispheres with a groove between them.
	local body: Part? = nil
	for side = -1, 1, 2 do
		for i = 1, 3 do
			local t = (i - 2) / 1 -- -1, 0, 1
			local lump = ball(
				rig,
				Vector3.new(1.35 - math.abs(t) * 0.3, 1.15 - math.abs(t) * 0.25, 1.35 - math.abs(t) * 0.3),
				color,
				CFrame.new(t * 0.85, 0.15 - t * t * 0.18, side * 0.5)
			)
			if side == 1 and i == 2 then
				body = lump
			end
		end
	end
	-- Brain stem / base
	ball(rig, Vector3.new(2.2, 0.9, 1.8), color:Lerp(Color3.new(0, 0, 0), 0.12), CFrame.new(0, -0.5, 0))
	return body :: Part
end

shapeBuilders.blobfish = function(rig, color)
	local body = ball(rig, Vector3.new(2.6, 1.8, 2.3), color, CFrame.new(0, 0, 0), Enum.Material.Glass)
	body.Transparency = 0.2
	-- The famous droopy nose, hanging off the front.
	local nose = ball(rig, Vector3.new(0.62, 0.78, 0.62), color:Lerp(Color3.new(1, 1, 1), 0.15), CFrame.new(0, -0.18, 1.1))
	nose.Material = Enum.Material.Glass
	nose.Transparency = 0.2
	-- Little side fins.
	for side = -1, 1, 2 do
		local fin = ball(rig, Vector3.new(0.3, 0.55, 0.75), color, CFrame.new(side * 1.3, -0.1, -0.3))
		fin.Material = Enum.Material.Glass
		fin.Transparency = 0.35
	end
	return body
end

shapeBuilders.butter = function(rig, color)
	local body = box(rig, Vector3.new(2.7, 1.15, 1.35), color, CFrame.new(0, 0, 0))
	-- Slightly lighter top face, like the printed wrapper edge.
	box(rig, Vector3.new(2.5, 0.22, 1.2), color:Lerp(Color3.new(1, 1, 1), 0.3), CFrame.new(0, 0.62, 0))
	return body
end

shapeBuilders.cloud = function(rig, color)
	local body = ball(rig, Vector3.new(1.9, 1.5, 1.6), color, CFrame.new(0, 0.1, 0))
	ball(rig, Vector3.new(1.3, 1.1, 1.3), color, CFrame.new(-1.0, -0.1, 0))
	ball(rig, Vector3.new(1.3, 1.1, 1.3), color, CFrame.new(1.0, -0.1, 0))
	ball(rig, Vector3.new(1.1, 0.95, 1.1), color, CFrame.new(-0.45, 0.6, 0))
	ball(rig, Vector3.new(1.0, 0.85, 1.0), color, CFrame.new(0.5, 0.55, 0))
	box(rig, Vector3.new(2.8, 0.5, 1.4), color, CFrame.new(0, -0.5, 0))
	return body
end

shapeBuilders.baby = function(rig, color)
	-- The translucent glitter baby: a head, a body, stubby arms and legs.
	local head = ball(rig, Vector3.new(1.5, 1.4, 1.4), color, CFrame.new(0, 0.75, 0), Enum.Material.Glass)
	head.Transparency = 0.25
	local torso = ball(rig, Vector3.new(1.7, 1.8, 1.4), color, CFrame.new(0, -0.55, 0), Enum.Material.Glass)
	torso.Transparency = 0.25
	for side = -1, 1, 2 do
		local arm = ball(rig, Vector3.new(0.5, 0.9, 0.5), color, CFrame.new(side * 0.95, -0.15, 0), Enum.Material.Glass)
		arm.Transparency = 0.25
		local leg = ball(rig, Vector3.new(0.55, 0.95, 0.55), color, CFrame.new(side * 0.45, -1.35, 0), Enum.Material.Glass)
		leg.Transparency = 0.25
	end
	return head
end

shapeBuilders.drop = function(rig, color)
	-- A teardrop: a big base ball with shrinking balls stacked into the point.
	-- Neon, because these are the glow-in-the-dark ones.
	local body = ball(rig, Vector3.new(2.0, 1.9, 2.0), color, CFrame.new(0, -0.35, 0), Enum.Material.Neon)
	ball(rig, Vector3.new(1.3, 1.2, 1.3), color, CFrame.new(0, 0.5, 0), Enum.Material.Neon)
	ball(rig, Vector3.new(0.75, 0.8, 0.75), color, CFrame.new(0, 1.1, 0), Enum.Material.Neon)
	ball(rig, Vector3.new(0.4, 0.55, 0.4), color, CFrame.new(0, 1.55, 0), Enum.Material.Neon)
	return body
end

shapeBuilders.donut = function(rig, color)
	-- A ring of balls standing face-on to the camera. The face billboard sits
	-- in the hole, which is exactly where it belongs.
	local body: Part? = nil
	local count = 10
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local segment = ball(
			rig,
			Vector3.new(1.0, 1.0, 0.9),
			color,
			CFrame.new(math.cos(angle) * 1.0, math.sin(angle) * 1.0, 0),
			Enum.Material.Neon
		)
		if i == 1 then
			body = segment
		end
	end
	return body :: Part
end

shapeBuilders.tub = function(rig, color)
	-- The boxed cake / ice-cream tub: a cream container with a scoop on top.
	local container = newPart(Enum.PartType.Cylinder, Vector3.new(1.3, 2.3, 2.3), TUB_CREAM, Enum.Material.SmoothPlastic)
	Models.add(rig, container, CFrame.new(0, -0.55, 0) * UPRIGHT)
	local rim = newPart(Enum.PartType.Cylinder, Vector3.new(0.25, 2.45, 2.45), TUB_CREAM, Enum.Material.SmoothPlastic)
	Models.add(rig, rim, CFrame.new(0, 0.15, 0) * UPRIGHT)
	local scoop = ball(rig, Vector3.new(1.9, 1.7, 1.9), color, CFrame.new(0, 0.75, 0))
	return scoop
end

-- ---------- imported mesh squishies ----------
-- Real 3D models (source files live in assets/) can't be synced by Rojo: they
-- must be imported once in Studio and parked as a MeshPart template under
-- ReplicatedStorage/SquishyMeshes. Shapes listed here use that template when
-- it exists and quietly fall back to their primitive builder when it doesn't,
-- so the game never breaks in a place without the imports.
export type MeshConfig = {
	template: string,
	-- Spins the imported model about Y so its face points at the camera.
	-- Importers disagree about which way is "front", so this is per-model.
	-- Keep it to 90° steps: the squash maths in Models.apply is only exact on
	-- right angles. Find the right value live with the debug menu's
	-- "Rotate Clicker" button, then write it in here.
	yaw: number,
	-- Repaint the mesh in the squishy's colour. The opal texture is pale and
	-- pearly, so multiplying it by a colour keeps the glitter and the baked-in
	-- face while changing the shade — one mould, thirteen dumplings, exactly
	-- how the real squishies are made.
	tint: boolean?,
	-- Shifts the model relative to where it is placed, in studs. Imported
	-- meshes don't agree about where their centre is, so this nudges one that
	-- sits too low or off to the side. Dial it in with the debug menu's
	-- "Raise"/"Lower" buttons, then write the number in here.
	offset: Vector3?,
	-- True when the texture already paints a face on. The billboard face stays
	-- off for these, or the squishy ends up with two.
	bakedFace: boolean?,
	-- A naming suffix shared by a set of interchangeable models, e.g. every
	-- cube colour is named <Colour>CubeSquishy. When `template` isn't in the
	-- place, any model from the family stands in and gets tinted — so the set
	-- works however many colours have actually been made, and new ones are
	-- picked up just by being named to match.
	family: string?,
	-- Primitive builder to use when no mesh at all is available, so a missing
	-- banana falls back to the banana rather than to a dumpling.
	fallback: string?,
}

local MESH_SHAPES: { [string]: MeshConfig } = {
	-- The Mythical keeps the opal texture exactly as imported.
	opalmesh = { template = "OpalDumpling", yaw = 180, bakedFace = true, fallback = "dumpling" },
	-- Every other dumpling: same mesh, tinted.
	dumplingmesh = { template = "OpalDumpling", yaw = 180, tint = true, bakedFace = true, fallback = "dumpling" },
	-- No bakedFace on these, and they aren't dumplings, so they wear no face
	-- at all — real bananas and butter sticks don't have one.
	bananamesh = { template = "BananaSquishy", yaw = 180, fallback = "banana" },
	buttermesh = { template = "ButterSquishy", yaw = 180, fallback = "butter" },
	-- Rainbow Butter has its own tie-dye model, so it needs no tinting.
	rainbuttermesh = { template = "RainbowButter", yaw = 90, fallback = "butter" },
	glowdonutmesh = { template = "GlowDonut", yaw = 0, fallback = "donut" },
	cheesemesh = { template = "SquishCheese", yaw = 0, fallback = "cheese" },
	coconutmesh = { template = "CoconutBall", yaw = 0, fallback = "ball" },
	babymesh = { template = "GlitterBaby", yaw = 0, fallback = "baby" },
	dropmesh = { template = "SparkleDrop", yaw = 0, fallback = "drop" },
	-- The cubes come as one model per colour, named <Colour>CubeSquishy. Each
	-- asks for its own colour and settles for a tinted sibling if that one
	-- hasn't been made yet.
	cubeorange = { template = "OrangeCubeSquishy", family = "CubeSquishy", yaw = 0, fallback = "jellycube" },
	cubepink = { template = "PinkCubeSquishy", family = "CubeSquishy", yaw = 0, fallback = "jellycube" },
	cubeblue = { template = "BlueCubeSquishy", family = "CubeSquishy", yaw = 0, fallback = "jellycube" },
	cubegreen = { template = "GreenCubeSquishy", family = "CubeSquishy", yaw = 0, fallback = "jellycube" },
	cubepurple = { template = "PurpleCubeSquishy", family = "CubeSquishy", yaw = 0, fallback = "jellycube" },
}

-- Debug hook: nudge a mesh's facing at runtime so the right angle can be found
-- by eye. Returns the new yaw, or nil if this shape isn't mesh-backed.
function Models.bumpMeshYaw(shape: string?, delta: number): number?
	local config = MESH_SHAPES[shape or ""]
	if not config then
		return nil
	end
	config.yaw = (config.yaw + delta) % 360
	return config.yaw
end

-- Debug hook: shift a mesh at runtime, same idea as bumpMeshYaw.
function Models.nudgeMeshOffset(shape: string?, delta: Vector3): Vector3?
	local config = MESH_SHAPES[shape or ""]
	if not config then
		return nil
	end
	config.offset = (config.offset or Vector3.zero) + delta
	return config.offset
end

-- Said once per template. A mesh that silently falls back to a primitive is
-- exactly the bug that wastes an afternoon, so the Output always explains
-- itself — either which mesh is in use, or precisely what is missing.
local meshReported: { [string]: boolean } = {}

-- Names get typed by hand in Studio, so case, spaces and underscores shouldn't
-- decide whether a model is found: "Squishy Cube" and "squishy_cube" both mean
-- SquishyCube.
local function loosen(name: string): string
	return (name:lower():gsub("[^%a%d]", ""))
end

local function findMeshEntry(templateName: string): Instance?
	-- Searched recursively. The tidy home is ReplicatedStorage/SquishyMeshes,
	-- but ANYWHERE in ReplicatedStorage works — a model dragged straight in
	-- shouldn't be a silent failure over a missing folder.
	local exact = ReplicatedStorage:FindFirstChild(templateName, true)
	if exact then
		return exact
	end

	local wanted = loosen(templateName)
	for _, descendant in ReplicatedStorage:GetDescendants() do
		if descendant:IsA("MeshPart") or descendant:IsA("Model") then
			if loosen(descendant.Name) == wanted then
				return descendant
			end
		end
	end
	return nil
end

-- Any model whose name ends in the family suffix, e.g. the first thing called
-- <something>CubeSquishy. Used to stand in for a colour nobody has made yet.
local function findMeshFamily(family: string): Instance?
	local suffix = loosen(family)
	for _, descendant in ReplicatedStorage:GetDescendants() do
		if descendant:IsA("MeshPart") or descendant:IsA("Model") then
			local name = loosen(descendant.Name)
			if #name >= #suffix and name:sub(-#suffix) == suffix then
				return descendant
			end
		end
	end
	return nil
end

-- Import 3D wraps meshes in a Model, and SPLITS anything too dense into
-- several MeshParts. Both are normal, so gather every part and rebuild the
-- whole assembly rather than grabbing one piece and rendering a fragment.
local function collectMeshParts(entry: Instance): { BasePart }
	if entry:IsA("BasePart") then
		return { entry }
	end
	local parts: { BasePart } = {}
	for _, descendant in entry:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function reportMissingMesh(shape: string, templateName: string, entry: Instance?)
	if entry then
		warn(
			("[SquishyClicker] '%s' found '%s' [%s] in ReplicatedStorage, but there are no parts inside it — using the primitive shape instead."):format(
				shape,
				templateName,
				entry.ClassName
			)
		)
		return
	end

	local found: { string } = {}
	for _, child in ReplicatedStorage:GetChildren() do
		table.insert(found, ("%s [%s]"):format(child.Name, child.ClassName))
	end
	warn(
		("[SquishyClicker] '%s' wants a MeshPart named '%s' somewhere in ReplicatedStorage, and nothing there has that name — using the primitive shape. Fix: STOP the playtest first (anything created while playing is thrown away when you stop), then drag the imported model into ReplicatedStorage and rename it to exactly '%s'. A Model wrapper is fine, including one Studio split into several MeshParts. ReplicatedStorage currently holds: %s"):format(
			shape,
			templateName,
			templateName,
			#found > 0 and table.concat(found, ", ") or "nothing"
		)
	)
end

local tintReported = false

-- SurfaceAppearance.Color multiplies the ColorMap, which is what lets one
-- pearly texture become a whole colour range. MeshPart.Color is set too as a
-- fallback for meshes imported without a SurfaceAppearance.
local function tintMesh(mesh: BasePart, color: Color3)
	mesh.Color = color

	local appearance = mesh:FindFirstChildOfClass("SurfaceAppearance")
	if not appearance then
		return
	end
	local ok = pcall(function()
		(appearance :: any).Color = color
	end)
	if not ok and not tintReported then
		tintReported = true
		warn(
			"[SquishyClicker] This Studio build's SurfaceAppearance has no Color property, so tinted dumplings will all wear the opal texture. Fix: update Studio, or delete the SurfaceAppearance from the template to fall back to flat colours."
		)
	end
end

local function tryBuildMesh(rig: Rig, shape: string, config: MeshConfig, color: Color3): BasePart?
	local templateName = config.template
	local entry = findMeshEntry(templateName)

	-- No model in this exact colour? Borrow a sibling and paint it.
	local borrowed = false
	if not entry and config.family then
		entry = findMeshFamily(config.family)
		borrowed = entry ~= nil
	end

	local parts = if entry then collectMeshParts(entry) else {}
	if #parts == 0 then
		if not meshReported[templateName] then
			meshReported[templateName] = true
			reportMissingMesh(shape, templateName, entry)
		end
		return nil
	end

	-- One bounding box around every piece, so a split model scales and centres
	-- as a single object instead of each fragment doing its own thing.
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	for _, part in parts do
		local half = part.Size * 0.5
		low = low:Min(part.Position - half)
		high = high:Max(part.Position + half)
	end
	local centre = (low + high) * 0.5
	local extents = high - low
	-- Normalise the largest dimension to squishy size, however the import came
	-- in — Import 3D scales are wildly inconsistent between models.
	local scale = 2.7 / math.max(extents.X, extents.Y, extents.Z, 0.05)
	local yaw = CFrame.fromEulerAnglesXYZ(0, math.rad(config.yaw), 0)
	-- Applied outside the yaw, so a nudge always moves the model the way the
	-- camera sees it regardless of how the model is turned.
	local shift = CFrame.new(config.offset or Vector3.zero)

	-- The face and sparkles ride the biggest piece.
	local primary: BasePart = parts[1]
	local biggest = -1

	for _, part in parts do
		local clone = part:Clone()
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		-- A borrowed model is always tinted, whatever the config says: it is
		-- wearing the wrong colour by definition.
		if config.tint or borrowed then
			tintMesh(clone, color)
		end
		clone.Size = part.Size * scale

		-- Configured yaw first, then whatever rotation the piece carries, so
		-- the assembly turns as a unit and each piece keeps its orientation.
		Models.add(rig, clone, shift * yaw * CFrame.new((part.Position - centre) * scale) * part.CFrame.Rotation)

		local volume = clone.Size.X * clone.Size.Y * clone.Size.Z
		if volume > biggest then
			biggest = volume
			primary = clone
		end
	end

	if not meshReported[templateName] then
		meshReported[templateName] = true
		if borrowed then
			print(
				("[SquishyClicker] '%s': no %s in the place, so %q is standing in, tinted. Add one named '%s' to give it its own."):format(
					shape,
					templateName,
					(entry :: Instance).Name,
					templateName
				)
			)
		else
			print(
				("[SquishyClicker] Using imported mesh '%s' for '%s' (%d part%s)."):format(
					templateName,
					shape,
					#parts,
					#parts == 1 and "" or "s"
				)
			)
		end
	end
	return primary
end

-- ---------- building a squishy ----------

-- Only dumplings have faces. The shop squishies are bananas, butter sticks and
-- jelly cubes — real ones have no features, and a face stuck on the side of a
-- banana read as a mistake rather than a character.
local FACE_SHAPES: { [string]: boolean } = {
	dumpling = true,
	dumplingmesh = true,
	opalmesh = true,
}

function Models.buildSquishy(
	parent: Instance,
	shape: string?,
	color: Color3,
	sparkle: boolean,
	sizeScale: number?
): SquishyModel
	local rig = Models.newRig("Squishy", parent)

	local primary: BasePart? = nil
	local shapeKey = shape or "dumpling"
	local textureFace = false

	local meshConfig = MESH_SHAPES[shape or ""]
	if meshConfig then
		primary = tryBuildMesh(rig, shape :: string, meshConfig, color)
		textureFace = primary ~= nil and meshConfig.bakedFace == true
	end
	if not primary then
		-- Fell back to a primitive, so the effective shape is that one.
		shapeKey = (meshConfig and meshConfig.fallback) or shape or "dumpling"
		local builder = shapeBuilders[shapeKey] or shapeBuilders.dumpling
		primary = builder(rig, color)
	end
	assert(primary, "shape builder returned no primary part")

	-- Glittery squishies get the glitter surface. On an imported mesh that
	-- already carries its own texture this is a no-op — the texture wins — so
	-- it only ever dresses the plain surfaces that need it.
	if sparkle then
		for _, piece in rig.pieces do
			applyGlitter(piece.inst)
		end
	end

	-- A billboard face is only built when there is one to show: a dumpling
	-- whose texture doesn't already paint it on.
	local wearsFace = FACE_SHAPES[shapeKey] == true and not textureFace
	local billboard: BillboardGui? = nil
	local face: TextLabel? = nil

	if wearsFace then
		-- The face rides on a billboard so it always turns to the camera — the
		-- squishy can spin freely and still look back at you.
		local gui = Instance.new("BillboardGui")
		gui.Name = "Face"
		gui.Adornee = primary
		gui.Size = UDim2.fromScale(1.7, 1.0) -- BillboardGui scale is in studs
		-- CAMERA-space offset, not world-space: it slides the face toward
		-- whoever is looking, so it always reads as painted on the front of the
		-- body. Must stay a touch beyond the widest model radius or the parts
		-- poke through and swallow the face.
		gui.StudsOffset = Vector3.new(0, 0.05, 1.55)
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.Enabled = false
		gui.Parent = primary
		billboard = gui

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = sparkle and "✧•ᴗ•✧" or "•ᴗ•"
		label.TextColor3 = FACE_INK
		label.TextScaled = true
		label.Parent = gui
		face = label
	end

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 14
	sparkles.Lifetime = NumberRange.new(0.6, 1.1)
	sparkles.Speed = NumberRange.new(1.5, 3.5)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.LightEmission = 0.9
	sparkles.Acceleration = Vector3.new(0, -4, 0)
	sparkles.Enabled = false
	sparkles.Parent = primary

	return {
		rig = rig,
		primary = primary,
		face = face,
		billboard = billboard,
		sparkles = sparkles,
		wearsFace = wearsFace,
		sizeScale = sizeScale or 1,
	}
end

return Models
