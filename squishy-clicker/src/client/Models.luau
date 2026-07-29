--!strict
-- ============================================================
--  3D MODELS  —  the bamboo steamer and the dumpling squishies,
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
-- ============================================================

local Models = {}

-- Cylinder parts run along their own X axis; this stands one upright.
local UPRIGHT = CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)

local BAMBOO_LIGHT = Color3.fromRGB(226, 190, 142)
local BAMBOO_DARK = Color3.fromRGB(198, 156, 110)
local BAMBOO_LINE = Color3.fromRGB(166, 124, 82)
local INTERIOR = Color3.fromRGB(102, 70, 46)
local FACE_INK = Color3.fromRGB(74, 52, 38)

export type Piece = { inst: BasePart, offset: CFrame, size: Vector3 }
export type Rig = { folder: Folder, pieces: { Piece } }

export type Dumpling = {
	rig: Rig,
	body: BasePart,
	pleats: { BasePart },
	face: TextLabel,
	billboard: BillboardGui,
	sparkles: ParticleEmitter,
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

-- ---------- the dumpling ----------

-- One dumpling model gets built and then recoloured for each pull, since the
-- squishies only differ by colour and whether they sparkle.
function Models.buildDumpling(parent: Instance): Dumpling
	local rig = Models.newRig("Dumpling", parent)

	local body = newPart(Enum.PartType.Ball, Vector3.new(2.5, 2.0, 2.5), BAMBOO_LIGHT, Enum.Material.SmoothPlastic)
	Models.add(rig, body, CFrame.new(0, 0, 0))

	-- The pinched pleats along the top, five little balls in an arc.
	local pleats: { BasePart } = {}
	for i = 1, 5 do
		local t = (i - 3) / 2 -- -1 .. 1
		local pleat = newPart(Enum.PartType.Ball, Vector3.new(0.66, 0.54, 0.66), BAMBOO_LIGHT, Enum.Material.SmoothPlastic)
		Models.add(rig, pleat, CFrame.new(t * 0.9, 0.78 - math.abs(t) * 0.14, 0.3 - math.abs(t) * 0.12))
		table.insert(pleats, pleat)
	end

	-- The face rides on a billboard so it always turns to the camera — the
	-- dumpling can spin freely and still look back at you.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Face"
	billboard.Adornee = body
	billboard.Size = UDim2.fromScale(1.9, 1.1) -- BillboardGui scale is in studs
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0.02, 1.45)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = body

	local face = Instance.new("TextLabel")
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.Font = Enum.Font.FredokaOne
	face.Text = "•ᴗ•"
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
	sparkles.Parent = body

	return { rig = rig, body = body, pleats = pleats, face = face, billboard = billboard, sparkles = sparkles }
end

function Models.paintDumpling(dumpling: Dumpling, color: Color3, sparkle: boolean)
	dumpling.body.Color = color
	local pleatColor = color:Lerp(Color3.new(1, 1, 1), 0.24)
	for _, pleat in dumpling.pleats do
		pleat.Color = pleatColor
	end
	dumpling.face.Text = sparkle and "✧•ᴗ•✧" or "•ᴗ•"
end

return Models
