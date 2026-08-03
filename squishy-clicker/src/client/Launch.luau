--!strict
-- ============================================================
--  SQUISHY LAUNCH  —  the cannon minigame's UI.
--
--  Two taps: the first stops a sweeping POWER bar, the second
--  stops a sweeping ANGLE bar. Then the shot is sent as nothing
--  but {power, angle}, each a plain 0-1 number. The client never
--  says how far it went or what it won — the server decides
--  both, and this only animates whatever comes back.
--
--  The spec asked for a ProximityPrompt on a cannon in the
--  world. That cannot work here: this game runs a scriptable
--  camera with the player's controls disabled, so the character
--  never walks anywhere and would never be in range of a prompt.
--  The cannon is stage geometry (still built in code, still in
--  Git) and the camera turns to it instead.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Launch = {}

-- Replaced when the panel mounts. A no-op until then, so a sync arriving
-- before the UI is up can't fail on a missing function.
function Launch.setReadyIn(_seconds: number) end

local COLOR = {
	panel = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(74, 52, 38),
	dim = Color3.fromRGB(150, 130, 118),
	track = Color3.fromRGB(238, 224, 212),
	power = Color3.fromRGB(240, 130, 90),
	angle = Color3.fromRGB(120, 190, 240),
	go = Color3.fromRGB(126, 224, 192),
	locked = Color3.fromRGB(228, 222, 216),
	gold = Color3.fromRGB(255, 199, 92),
}

local function make(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	return inst
end

local function corner(radius: number, parent: Instance)
	make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

-- Stage of the aim: "idle" (closed), "power", "angle", or "flying".
type Stage = "idle" | "power" | "angle" | "flying"

function Launch.mount(gui: ScreenGui, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shotRemote = remotes:WaitForChild("LaunchShot") :: RemoteEvent
	local resultRemote = remotes:WaitForChild("LaunchResult") :: RemoteEvent

	local stage: Stage = "idle"
	local sweep = 0 -- the live 0-1 position of whichever bar is moving
	local chosenPower = 0
	local readyIn = 0 -- seconds left on the cooldown, straight from the server

	-- ---------- the open button, beside the Unbox tray ----------
	local openButton = make("TextButton", {
		Name = "CannonButton",
		Size = UDim2.new(0, 160, 0, 44),
		Position = UDim2.new(0, 508, 1, -100),
		BackgroundColor3 = COLOR.gold,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "🎯 Cannon",
		TextColor3 = COLOR.text,
		TextSize = 18,
		ZIndex = 2,
		Parent = gui,
	})
	corner(14, openButton)

	-- ---------- the aiming panel ----------
	local panel = make("Frame", {
		Name = "CannonPanel",
		Size = UDim2.new(0, 340, 0, 190),
		Position = UDim2.new(0, 24, 1, -300),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.06,
		Active = true, -- swallow taps, or aiming also squishes the squishy
		Visible = false,
		ZIndex = 6,
		Parent = gui,
	})
	corner(18, panel)

	local title = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 26),
		Position = UDim2.new(0, 10, 0, 10),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "Set your power!",
		TextColor3 = COLOR.text,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = panel,
	})

	make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.new(0, 10, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "tap the bar to lock it in",
		TextColor3 = COLOR.dim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = panel,
	})

	-- Two tracks, each with a marker that sweeps back and forth. A locked-in
	-- value leaves its marker parked where it was stopped.
	local function newTrack(y: number, fill: Color3): (Frame, Frame)
		local track = make("Frame", {
			Size = UDim2.new(1, -20, 0, 22),
			Position = UDim2.new(0, 10, 0, y),
			BackgroundColor3 = COLOR.track,
			ZIndex = 7,
			Parent = panel,
		})
		corner(11, track)

		local marker = make("Frame", {
			Size = UDim2.new(0, 10, 1, -6),
			Position = UDim2.new(0, 3, 0, 3),
			BackgroundColor3 = fill,
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = track,
		})
		corner(5, marker)
		return track, marker
	end

	local powerTrack, powerMarker = newTrack(60, COLOR.power)
	local angleTrack, angleMarker = newTrack(92, COLOR.angle)

	local function trackLabel(track: Frame, text: string)
		make("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = COLOR.text,
			TextTransparency = 0.45,
			TextSize = 12,
			ZIndex = 9,
			Parent = track,
		})
	end
	trackLabel(powerTrack, "POWER")
	trackLabel(angleTrack, "ANGLE")

	local status = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 10, 0, 122),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = panel,
	})

	local lockButton = make("TextButton", {
		Size = UDim2.new(1, -20, 0, 38),
		Position = UDim2.new(0, 10, 1, -48),
		BackgroundColor3 = COLOR.go,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "LOCK POWER",
		TextColor3 = COLOR.text,
		TextSize = 17,
		ZIndex = 7,
		Parent = panel,
	})
	corner(12, lockButton)

	local closeButton = make("TextButton", {
		Size = UDim2.new(0, 28, 0, 28),
		Position = UDim2.new(1, -36, 0, 8),
		BackgroundColor3 = COLOR.locked,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		Text = "✕",
		TextColor3 = COLOR.text,
		TextSize = 15,
		ZIndex = 8,
		Parent = panel,
	})
	corner(8, closeButton)

	-- ---------- driving the sweep ----------
	local function setStage(next: Stage)
		stage = next
		panel.Visible = next ~= "idle"

		if next == "power" then
			title.Text = "Set your power!"
			lockButton.Text = "LOCK POWER"
			lockButton.BackgroundColor3 = COLOR.go
			status.Text = ""
		elseif next == "angle" then
			title.Text = "Now the angle!"
			lockButton.Text = "FIRE!"
			lockButton.BackgroundColor3 = COLOR.power
		elseif next == "flying" then
			title.Text = "Away it goes…"
			lockButton.Text = "…"
			lockButton.BackgroundColor3 = COLOR.locked
		end
	end

	local function openAiming()
		if readyIn > 0 or stage ~= "idle" then
			return
		end
		chosenPower = 0
		sweep = 0
		powerMarker.Position = UDim2.new(0, 3, 0, 3)
		angleMarker.Position = UDim2.new(0, 3, 0, 3)
		scene.setView("cannon")
		setStage("power")
	end

	local function closeAiming()
		setStage("idle")
		scene.setView("main")
	end

	openButton.Activated:Connect(openAiming)
	closeButton.Activated:Connect(closeAiming)

	-- The sweep runs on the render step so the bar moves smoothly; it is only
	-- ever a display, and the value is read at the instant the player taps.
	RunService.RenderStepped:Connect(function(dt)
		if stage ~= "power" and stage ~= "angle" then
			return
		end
		-- Ping-pong 0-1: a triangle wave is easier to read and to time than a
		-- sine, which crawls at both ends.
		sweep = (sweep + dt * 0.85) % 2
		local value = sweep <= 1 and sweep or 2 - sweep

		local marker = stage == "power" and powerMarker or angleMarker
		marker.Position = UDim2.new(value, -value * 13 + 3, 0, 3)

		if stage == "angle" then
			scene.setCannonAim(value)
			status.Text = ("power %d%%   ·   angle %d°"):format(
				math.floor(chosenPower * 100 + 0.5),
				math.floor(Config.LaunchMinAngle + (Config.LaunchMaxAngle - Config.LaunchMinAngle) * value + 0.5)
			)
		else
			status.Text = ("power %d%%"):format(math.floor(value * 100 + 0.5))
		end
	end)

	local function currentSweep(): number
		return sweep <= 1 and sweep or 2 - sweep
	end

	lockButton.Activated:Connect(function()
		if stage == "power" then
			chosenPower = currentSweep()
			sweep = 0
			setStage("angle")
		elseif stage == "angle" then
			local chosenAngle = currentSweep()
			setStage("flying")
			-- Two numbers, nothing else. The server does the rest.
			shotRemote:FireServer(chosenPower, chosenAngle)
		end
	end)

	-- ---------- the server's verdict ----------
	resultRemote.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" then
			return
		end
		scene.playLaunch(result.angle or 0.5, result.distance or 0)

		local ring = result.ring or 0
		local bonus = result.bonus or 0
		if ring == 1 then
			title.Text = "BULLSEYE!"
		elseif ring > 0 then
			title.Text = ("Ring %d!"):format(ring)
		else
			title.Text = "Missed the field…"
		end
		status.Text = bonus > 0 and ("+%d clicks toward your steamer"):format(bonus) or "no bonus this time"

		-- Let the shot land and be read, then hand the view back.
		task.delay(2.6, function()
			if stage == "flying" then
				closeAiming()
			end
		end)
	end)

	-- ---------- cooldown, straight from the server ----------
	function Launch.setReadyIn(seconds: number)
		readyIn = math.max(seconds, 0)
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			if readyIn > 0 then
				readyIn = math.max(readyIn - 0.25, 0)
			end
			if readyIn > 0 then
				openButton.Text = ("🎯 %ds"):format(math.ceil(readyIn))
				openButton.BackgroundColor3 = COLOR.locked
				openButton.AutoButtonColor = false
			else
				openButton.Text = "🎯 Cannon"
				openButton.BackgroundColor3 = COLOR.gold
				openButton.AutoButtonColor = true
			end
		end
	end)
end

return Launch
