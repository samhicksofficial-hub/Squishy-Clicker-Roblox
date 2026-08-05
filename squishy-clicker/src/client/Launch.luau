--!strict
-- ============================================================
--  SQUISHY LAUNCH  —  the cannon minigame's UI.
--
--  A DISTANCE game. Two taps: the first stops a sweeping POWER
--  bar, the second stops a sweeping ANGLE bar. Then the shot is
--  sent as nothing but {power, angle}, each a plain 0-1 number.
--  The squishy flies, the camera goes with it, and how far it
--  gets is the score — sweets picked up on the way and the zone
--  it lands in both add to the payout.
--
--  The client never says how far it went, what it collected or
--  what it won. The server decides all of it and sends back the
--  shape of the flight; this only draws that.
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

-- Replaced when the panel mounts. No-ops until then, so a sync arriving
-- before the UI is up can't fail on a missing function.
function Launch.setReadyIn(_seconds: number) end
function Launch.setBest(_distance: number) end

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
	local fieldRemote = remotes:WaitForChild("LaunchField") :: RemoteEvent

	local stage: Stage = "idle"
	local sweep = 0 -- the live 0-1 position of whichever bar is moving
	local chosenPower = 0
	local readyIn = 0 -- seconds left on the cooldown, straight from the server
	local best = 0 -- furthest ever flown, straight from the server

	-- The server lays out the NEXT shot's sweets the instant it scores this
	-- one, which lands here while the squishy is still in the air. Applying it
	-- there and then would teleport the sweets out from under a flight that is
	-- still collecting them, so it waits its turn.
	local pendingField: { any }? = nil

	fieldRemote.OnClientEvent:Connect(function(field)
		if typeof(field) ~= "table" then
			return
		end
		if stage == "flying" then
			pendingField = field
		else
			scene.setLaunchField(field)
		end
	end)

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
		Size = UDim2.new(0, 340, 0, 214),
		Position = UDim2.new(0, 24, 1, -324),
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

	-- The number to beat. A distance game needs one on screen at all times.
	local bestLabel = make("TextLabel", {
		Size = UDim2.new(0, 150, 0, 18),
		Position = UDim2.new(1, -196, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "best 0 studs",
		TextColor3 = COLOR.gold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
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

	-- Takes over the two bars once the shot is away: while it's in the air the
	-- only number that matters is how far it has got, counting up live.
	local flightLabel = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 58),
		Position = UDim2.new(0, 10, 0, 56),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.05,
		Font = Enum.Font.FredokaOne,
		Text = "0 studs",
		TextColor3 = COLOR.power,
		TextSize = 40,
		Visible = false,
		ZIndex = 10,
		Parent = panel,
	})
	corner(12, flightLabel)

	local status = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.new(0, 10, 0, 120),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = COLOR.text,
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
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
		flightLabel.Visible = next == "flying"

		if next == "power" then
			title.Text = "Set your power!"
			title.TextColor3 = COLOR.text -- clear a NEW BEST! left over from last shot
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

		-- Now that nothing is in the air, the next shot's sweets can go down.
		local waiting = pendingField
		if waiting then
			pendingField = nil
			scene.setLaunchField(waiting)
		end
	end

	openButton.Activated:Connect(openAiming)
	closeButton.Activated:Connect(closeAiming)

	-- The sweep runs on the render step so the bar moves smoothly; it is only
	-- ever a display, and the value is read at the instant the player taps.
	RunService.RenderStepped:Connect(function(dt)
		if stage == "flying" then
			-- Counting up beside the shot is the whole feedback loop of a
			-- distance game, so it reads the stage's live position rather
			-- than waiting for the landing to show a number.
			flightLabel.Text = ("%d studs"):format(math.floor(scene.flightDistance()))
			return
		end
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
		-- The stage says how long its animation runs, so the summary below can
		-- wait for the landing exactly rather than on a guessed timer.
		local flightSeconds = scene.playLaunch(result)
		local collected = result.collected or {}

		-- The summary only goes up once the shot has actually landed —
		-- announcing the distance while it is still climbing gives the ending
		-- away and makes the flight pointless to watch.
		task.delay(flightSeconds, function()
			if stage ~= "flying" then
				return
			end
			best = math.max(result.best or 0, best)
			bestLabel.Text = ("best %d studs"):format(math.floor(best))

			title.Text = result.record and "NEW BEST!" or (result.zone or "Landed")
			title.TextColor3 = result.record and COLOR.gold or COLOR.text

			local sweets = #collected > 0 and (" · %d sweets"):format(#collected) or ""
			status.Text = ("%d studs — %s ×%.2g%s\n+%d clicks toward your steamer"):format(
				math.floor(result.distance or 0),
				result.zone or "Shop Floor",
				result.multiplier or 1,
				sweets,
				result.bonus or 0
			)
		end)

		-- Then let it be read, and hand the view back.
		task.delay(flightSeconds + 2.4, function()
			if stage == "flying" then
				closeAiming()
			end
		end)
	end)

	-- ---------- cooldown and record, straight from the server ----------
	function Launch.setReadyIn(seconds: number)
		readyIn = math.max(seconds, 0)
	end

	function Launch.setBest(distance: number)
		best = math.max(distance, 0)
		bestLabel.Text = ("best %d studs"):format(math.floor(best))
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
