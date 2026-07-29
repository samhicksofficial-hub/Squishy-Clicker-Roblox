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
-- Aiming to the RIGHT of the steamer pushes it left on screen, clear of the
-- collection panel. Aim height splits the difference between the tub and the
-- risen dumpling so the whole reveal stays in frame.
local CAMERA_POS = ORIGIN + Vector3.new(0.5, 5.0, 16.5)
local CAMERA_LOOK = ORIGIN + Vector3.new(1.9, 3.0, 0)
local FIELD_OF_VIEW = 50

local BACKDROP_COLOR = Color3.fromRGB(240, 222, 206)
local FLOOR_COLOR = Color3.fromRGB(228, 204, 182)

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
local lidLift = spring(55, 8.5)
local lidTilt = spring(48, 8)
local rise = spring(70, 11) -- dumpling climbing out, 0..1
local jiggle = spring(150, 11)
local glow = spring(90, 12)
local rayGlow = spring(40, 9)

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

-- A cream wall and floor turn the open sky into a soft studio that matches the
-- UI behind it, and give the steamer something to cast a shadow onto.
block(Vector3.new(110, 66, 0.5), ORIGIN + Vector3.new(0, 24, -20), BACKDROP_COLOR)
block(Vector3.new(110, 0.5, 60), ORIGIN + Vector3.new(0, -0.25, -6), FLOOR_COLOR)

-- Contact shadow: without it the steamer looks like it is floating.
local contact = Instance.new("Part")
contact.Shape = Enum.PartType.Cylinder
contact.Size = Vector3.new(0.06, 6.4, 6.4)
contact.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 0.05, 0)) * CFrame.fromEulerAnglesXYZ(0, 0, math.pi / 2)
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
local dumpling = Models.buildDumpling(stage)

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
	advance(lidLift, dt)
	advance(lidTilt, dt)
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

	local baseScale = Vector3.new(1 + sq * 0.13, 1 - sq * 0.19, 1 + sq * 0.13)
	Models.apply(
		baseRig,
		CFrame.new(ORIGIN + Vector3.new(rattle, bob, 0))
			* CFrame.fromEulerAnglesXYZ(0, math.sin(elapsed * 0.5) * 0.06, rattle * 0.05),
		baseScale
	)

	-- The lid rides the tub's squashed top, then lags a touch behind it — the
	-- secondary motion is most of what sells the bounce.
	local lidScale = Vector3.new(1 + sq * 0.09, 1 - sq * 0.13, 1 + sq * 0.09)
	local lidY = LID_REST_Y * baseScale.Y + bob + lidLift.value
	Models.apply(
		lidRig,
		CFrame.new(ORIGIN + Vector3.new(rattle, lidY, 0))
			* CFrame.fromEulerAnglesXYZ(lidTilt.value, lidSpin, lidTilt.value * 0.55),
		lidScale
	)

	mouth.CFrame = CFrame.new(ORIGIN + Vector3.new(rattle, LID_REST_Y * baseScale.Y + bob, 0))

	-- The dumpling sits down inside the tub at rest, hidden by its own walls,
	-- so it needs no showing and hiding — it just climbs out and drops back.
	local risen = rise.value
	local jg = jiggle.value
	local dumplingY = DUMPLING_HIDDEN_Y + (DUMPLING_RISEN_Y - DUMPLING_HIDDEN_Y) * risen
	Models.apply(
		dumpling.rig,
		CFrame.new(ORIGIN + Vector3.new(0, dumplingY + math.sin(elapsed * 3) * 0.08 * risen, 0))
			* CFrame.fromEulerAnglesXYZ(0, dumplingSpin, math.sin(elapsed * 2.2) * 0.05 * risen),
		Vector3.new(1 + jg * 0.18, 1 - jg * 0.22, 1 + jg * 0.18)
	)
	dumpling.billboard.Enabled = risen > 0.06

	glowLight.Brightness = math.max(glow.value, 0)

	local rayAlpha = math.clamp(rayGlow.value, 0, 1)
	local rayPivot = CFrame.new(ORIGIN + Vector3.new(0, DUMPLING_RISEN_Y, -1.4))
	for index, ray in rays do
		local angle = elapsed * 0.55 + (index / #rays) * math.pi * 2
		local length = math.max(9 * rayAlpha, 0.05)
		ray.Size = Vector3.new(0.24, length, 0.24)
		ray.CFrame = rayPivot * CFrame.fromEulerAnglesXYZ(0, 0, angle) * CFrame.new(0, length * 0.5 + 1.6, 0)
		ray.Transparency = 1 - rayAlpha * 0.7
	end

	local camera = workspace.CurrentCamera
	if camera then
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local jolt = Vector3.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)
		camera.CFrame = CFrame.lookAt(CAMERA_POS + jolt, CAMERA_LOOK)
		-- A hair of punch-in on every click, too small to notice and too big to
		-- do without.
		camera.FieldOfView = FIELD_OF_VIEW - sq * 1.2
	end
end)

-- ---------- what init.client.luau calls ----------

function Scene.click()
	kick(squash, 1)
	steam:Emit(2)

	-- Rising pitch as the bar fills. Rate limited so a held-down mouse does not
	-- turn into a machine gun.
	local now = os.clock()
	if now - lastClickSound > 0.05 then
		lastClickSound = now
		clickSound.PlaybackSpeed = 1.2 + progress * 0.6
		clickSound:Play()
	end
end

function Scene.setProgress(fraction: number)
	progress = math.clamp(fraction, 0, 1)
end

-- tier is the squishy's rarity rank, 1 for Common up to 6 for Mythical. The
-- whole show scales off it, so adding a rarity in Squishies.luau automatically
-- gets a bigger reveal than the one below it.
function Scene.open(bodyColor: Color3, sparkle: boolean, rarityColor: Color3, tier: number)
	Models.paintDumpling(dumpling, bodyColor, sparkle)

	-- The lift used to peak at 8.7 studs, which threw the lid clean out of
	-- frame; the whole show now has to fit under the camera's ceiling.
	lidLift.target = 2.6 + tier * 0.4
	lidTilt.target = 0.55
	lidSpinVelocity = 7 + tier * 2.5
	rise.target = 1
	kick(jiggle, 1)
	glow.target = 0.7 + tier * 0.45
	glowLight.Color = rarityColor

	steam:Emit(10 + tier * 4)
	burst.Color = ColorSequence.new(rarityColor)
	burst:Emit(16 + tier * 22)

	dumpling.sparkles.Enabled = sparkle

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
		dumpling.sparkles.Enabled = false

		-- The lid waits for the dumpling to be back inside before dropping,
		-- otherwise it closes straight through it.
		task.delay(0.3, function()
			if token ~= revealToken then
				return
			end
			lidLift.target = 0
			lidTilt.target = 0
		end)
	end)
end

return Scene
