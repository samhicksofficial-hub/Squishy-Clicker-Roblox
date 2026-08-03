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
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

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

local BACKDROP_COLOR = Color3.fromRGB(240, 222, 206) -- invisible helper parts only

local LID_REST_Y = 2.15 -- where the lid sits on the tub
-- Low enough that the dumpling sits entirely below the tub's interior floor at
-- rest, so it needs no hiding: the tub's own walls do it.
local DUMPLING_HIDDEN_Y = 0.95
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

-- Wooden floor, big enough to run under both the main view and the steamer nook
local shopFloor = block(Vector3.new(110, 0.5, 100), ORIGIN + Vector3.new(0, -0.25, 0), Color3.fromRGB(206, 172, 134))
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

-- The blur that fades the shop out behind the squisher and the steamer.
-- Everything nearer than the focus distance stays sharp; the walls sit past it.
local depthOfField = Instance.new("DepthOfFieldEffect")
depthOfField.FocusDistance = 17
depthOfField.InFocusRadius = 8
depthOfField.FarIntensity = 0.6
depthOfField.NearIntensity = 0
depthOfField.Parent = Lighting

-- For a future free-roam mode: pass false to snap the shop into focus.
function Scene.setBackdropFaded(faded: boolean)
	depthOfField.FarIntensity = faded and 0.6 or 0
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

local CLICKER_POS = ORIGIN + Vector3.new(1.9, 1.75, 3.0)
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
	-- An oversized squishy has to sit deeper at rest, or it pokes up through
	-- the closed lid while it is meant to be a surprise.
	local hiddenY = DUMPLING_HIDDEN_Y - math.max(revealScale - 1, 0) * 1.5
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
	local toy = clickerModel
	if toy then
		local cs = clickerSquash.value
		Models.apply(
			toy.rig,
			CFrame.new(CLICKER_POS + Vector3.new(0, math.sin(elapsed * 2.1) * 0.05, 0))
				* CFrame.fromEulerAnglesXYZ(0, spinAngle + math.sin(elapsed * 1.3) * 0.08 * swayAmount, 0),
			Vector3.new(1 + cs * 0.28, 1 - cs * 0.34, 1 + cs * 0.28) * CLICKER_SCALE * toy.sizeScale
		)
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
		-- 1 is 90° left onto the steamer nook. (+yaw about Y turns left.)
		local yaw = math.clamp(viewYaw.value, -0.15, 1.15) * math.rad(90)
		local dir = CFrame.fromEulerAnglesXYZ(0, yaw, 0):VectorToWorldSpace(BASE_LOOK_DIR)
		-- Shake in view space, so it reads as shake from either angle.
		local right = dir:Cross(Vector3.new(0, 1, 0)).Unit
		local jolt = right * ((math.random() - 0.5) * shake) + Vector3.new(0, (math.random() - 0.5) * shake, 0)
		camera.CFrame = CFrame.lookAt(CAMERA_POS + jolt, CAMERA_POS + jolt + dir)
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

-- Turn the camera: "unbox" swings 90° left onto the steamer nook, anything
-- else swings back to the squisher.
function Scene.setView(view: string)
	viewYaw.target = view == "unbox" and 1 or 0
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
