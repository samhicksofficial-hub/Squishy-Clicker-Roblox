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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = {}

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
	face: TextLabel,
	billboard: BillboardGui,
	sparkles: ParticleEmitter,
	-- True for imported meshes whose texture already includes a face: the
	-- billboard face must stay OFF for these or the squishy grows two faces.
	hasOwnFace: boolean,
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
	-- Lift the tint toward white before multiplying, 0..1. Tinting only ever
	-- darkens, so a strong colour over an already-bright texture turns to mud
	-- (purple over yellow butter goes brown). Lifting keeps it pastel.
	tintLift: number?,
	-- True when the texture already paints a face on. The billboard face stays
	-- off for these, or the squishy ends up with two.
	bakedFace: boolean?,
	-- Primitive builder to use when the imported mesh isn't in the place, so a
	-- missing banana falls back to the banana rather than to a dumpling.
	fallback: string?,
}

local MESH_SHAPES: { [string]: MeshConfig } = {
	-- The Mythical keeps the opal texture exactly as imported.
	opalmesh = { template = "OpalDumpling", yaw = 180, bakedFace = true, fallback = "dumpling" },
	-- Every other dumpling: same mesh, tinted.
	dumplingmesh = { template = "OpalDumpling", yaw = 180, tint = true, bakedFace = true, fallback = "dumpling" },
	-- These two textures paint no face, so they wear the billboard one.
	bananamesh = { template = "BananaSquishy", yaw = 180, fallback = "banana" },
	buttermesh = { template = "ButterSquishy", yaw = 180, fallback = "butter" },
	-- Rainbow Butter borrows the butter mesh, lifted so it reads pastel
	-- instead of brown.
	rainbuttermesh = {
		template = "ButterSquishy",
		yaw = 180,
		tint = true,
		tintLift = 0.5,
		fallback = "butter",
	},
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

-- Said once per template. A mesh that silently falls back to a primitive is
-- exactly the bug that wastes an afternoon, so the Output always explains
-- itself — either which mesh is in use, or precisely what is missing.
local meshReported: { [string]: boolean } = {}

local function findMeshTemplate(templateName: string): BasePart?
	-- Searched recursively. The tidy home is ReplicatedStorage/SquishyMeshes,
	-- but ANYWHERE in ReplicatedStorage works — a model dragged straight in
	-- shouldn't be a silent failure over a missing folder.
	local entry = ReplicatedStorage:FindFirstChild(templateName, true)
	if not entry then
		return nil
	end
	if entry:IsA("BasePart") then
		return entry
	end
	-- Studio's Import 3D wraps the mesh in a Model, so accept that too and dig
	-- the MeshPart out rather than failing on a technicality.
	for _, descendant in entry:GetDescendants() do
		if descendant:IsA("MeshPart") then
			return descendant
		end
	end
	return nil
end

local function reportMissingMesh(shape: string, templateName: string)
	local found: { string } = {}
	for _, child in ReplicatedStorage:GetChildren() do
		table.insert(found, ("%s [%s]"):format(child.Name, child.ClassName))
	end
	warn(
		("[SquishyClicker] '%s' wants a MeshPart named '%s' somewhere in ReplicatedStorage, and nothing there has that name — using the primitive shape. Fix: STOP the playtest first (anything created while playing is thrown away when you stop), then drag the imported model into ReplicatedStorage and rename it to exactly '%s'. A Model wrapper is fine as long as a MeshPart is inside. ReplicatedStorage currently holds: %s"):format(
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
local function tintMesh(mesh: BasePart, color: Color3, lift: number)
	local shade = lift > 0 and color:Lerp(Color3.new(1, 1, 1), lift) or color
	mesh.Color = shade
	color = shade

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
	local template = findMeshTemplate(templateName)
	if not template then
		if not meshReported[templateName] then
			meshReported[templateName] = true
			reportMissingMesh(shape, templateName)
		end
		return nil
	end

	local mesh = template:Clone()
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	if config.tint then
		tintMesh(mesh, color, config.tintLift or 0)
	end

	-- Normalise the largest dimension to squishy size, however the import came
	-- in — Import 3D scales are wildly inconsistent between models.
	local size = mesh.Size
	local largest = math.max(size.X, size.Y, size.Z, 0.05)
	mesh.Size = size * (2.7 / largest)

	-- Configured yaw first, then whatever rotation the template carries in
	-- Studio, so the model can be aimed from either place.
	Models.add(rig, mesh, CFrame.fromEulerAnglesXYZ(0, math.rad(config.yaw), 0) * template.CFrame.Rotation)

	if not meshReported[templateName] then
		meshReported[templateName] = true
		print(("[SquishyClicker] Using imported mesh '%s' for '%s'."):format(templateName, shape))
	end
	return mesh
end

-- ---------- building a squishy ----------

function Models.buildSquishy(parent: Instance, shape: string?, color: Color3, sparkle: boolean): SquishyModel
	local rig = Models.newRig("Squishy", parent)

	local primary: BasePart? = nil
	local hasOwnFace = false
	local meshConfig = MESH_SHAPES[shape or ""]
	if meshConfig then
		primary = tryBuildMesh(rig, shape :: string, meshConfig, color)
		hasOwnFace = primary ~= nil and meshConfig.bakedFace == true
	end
	if not primary then
		local key = (meshConfig and meshConfig.fallback) or shape or "dumpling"
		local builder = shapeBuilders[key] or shapeBuilders.dumpling
		primary = builder(rig, color)
	end
	assert(primary, "shape builder returned no primary part")

	-- The face rides on a billboard so it always turns to the camera — the
	-- squishy can spin freely and still look back at you.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Face"
	billboard.Adornee = primary
	billboard.Size = UDim2.fromScale(1.7, 1.0) -- BillboardGui scale is in studs
	-- CAMERA-space offset, not world-space: it slides the face toward whoever
	-- is looking, so it always reads as painted on the front of the body.
	-- Must stay a touch beyond the widest model radius or the parts poke
	-- through and swallow the face.
	billboard.StudsOffset = Vector3.new(0, 0.05, 1.55)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = primary

	local face = Instance.new("TextLabel")
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.Font = Enum.Font.FredokaOne
	face.Text = sparkle and "✧•ᴗ•✧" or "•ᴗ•"
	face.TextColor3 = FACE_INK
	face.TextScaled = true
	face.Parent = billboard

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
		hasOwnFace = hasOwnFace,
	}
end

return Models
