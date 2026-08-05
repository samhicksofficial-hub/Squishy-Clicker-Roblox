--!strict
-- ============================================================
--  SQUISHY LAUNCH  —  the cannon's UI.
--
--  A launch simulator. Two taps: the first stops a sweeping
--  CHARGE meter, the second an ANGLE meter. Then the shot goes
--  out as nothing but {power, angle}, two plain 0-1 numbers.
--
--  The squishy is fired, skips down an endless rainbow track,
--  sweeps up TNT, coins and gems on the way and rolls to a stop.
--  How far it got is the score, and everything the run earned is
--  read back on a summary card at the end.
--
--  The client never says how far it went, what it collected or
--  what it won. The server simulates the whole flight and sends
--  back its shape — every hop, its peak, its duration — and this
--  draws that. See the comment at the top of the server's
--  ballistics section for why the simulation is arithmetic and
--  not Roblox physics.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))

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
	tnt = Color3.fromRGB(232, 118, 58),
	coin = Color3.fromRGB(250, 196, 76),
	gem = Color3.fromRGB(110, 220, 212),
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

-- Stage of the shot: "idle" (closed), "power", "angle", "flying", "summary".
type Stage = "idle" | "power" | "angle" | "flying" | "summary"

function Launch.mount(gui: ScreenGui, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shotRemote = remotes:WaitForChild("LaunchShot") :: RemoteEvent
	local resultRemote = remotes:WaitForChild("LaunchResult") :: RemoteEvent
	local fieldRemote = remotes:WaitForChild("LaunchField") :: RemoteEvent

	local stage: Stage = "idle"
	local sweep = 0 -- the live 0-1 position of whichever meter is moving
	local chosenPower = 0
	local readyIn = 0 -- seconds left on the cooldown, straight from the server
	local best = 0 -- furthest ever flown, straight from the server

	-- The server lays out the NEXT shot's pickups the instant it scores this
	-- one, which lands here while the squishy is still in the air. Applying it
	-- there and then would teleport the track out from under a flight that is
	-- still collecting from it, so it waits its turn.
	local pendingField: { any }? = nil

	fieldRemote.OnClientEvent:Connect(function(field)
		if typeof(field) ~= "table" then
			return
		end
		if stage == "flying" or stage == "summary" then
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
		Size = UDim2.new(0, 340, 0, 200),
		Position = UDim2.new(0, 24, 1, -310),
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
		Text = "Charge it up!",
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
		Text = "tap the meter to lock it in",
		TextColor3 = COLOR.dim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = panel,
	})

	-- The number to beat. A distance game needs one on screen at all times.
	local bestLabel = make("TextLabel", {
		Size = UDim2.new(0, 150, 0, 18),
		Position = UDim2.new(1, -160, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "best 0",
		TextColor3 = COLOR.gold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 7,
		Parent = panel,
	})

	-- Two meters, each with a bar that sweeps back and forth. A locked-in
	-- value leaves its bar parked where it was stopped. The charge meter FILLS
	-- rather than showing a marker, because "how full is it" is the thing the
	-- player is actually timing.
	local function newMeter(y: number, fill: Color3, filling: boolean): (Frame, Frame)
		local track = make("Frame", {
			Size = UDim2.new(1, -20, 0, 24),
			Position = UDim2.new(0, 10, 0, y),
			BackgroundColor3 = COLOR.track,
			ClipsDescendants = true,
			ZIndex = 7,
			Parent = panel,
		})
		corner(12, track)

		local bar = make("Frame", {
			Size = filling and UDim2.new(0, 0, 1, 0) or UDim2.new(0, 10, 1, -6),
			Position = filling and UDim2.fromScale(0, 0) or UDim2.new(0, 3, 0, 3),
			BackgroundColor3 = fill,
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = track,
		})
		corner(filling and 12 or 5, bar)
		return track, bar
	end

	local powerTrack, powerBar = newMeter(60, COLOR.power, true)
	local angleTrack, angleBar = newMeter(94, COLOR.angle, false)

	local function meterLabel(track: Frame, text: string)
		make("TextLabel", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = COLOR.text,
			TextTransparency = 0.35,
			TextSize = 12,
			ZIndex = 9,
			Parent = track,
		})
	end
	meterLabel(powerTrack, "CHARGE")
	meterLabel(angleTrack, "ANGLE")

	local status = make("TextLabel", {
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0, 10, 0, 124),
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
		Text = "LOCK CHARGE",
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

	-- ---------- the in-flight readout ----------
	-- Deliberately huge and centred at the top of the screen rather than tucked
	-- in the panel: while the shot is in the air the distance is the only thing
	-- on screen worth reading, and it has to be legible at a glance on a phone.
	local flightHud = make("Frame", {
		Name = "FlightHud",
		Size = UDim2.new(0, 420, 0, 132),
		Position = UDim2.new(0.5, 0, 0, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})

	local distanceLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "0",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeColor3 = Color3.fromRGB(52, 38, 30),
		TextStrokeTransparency = 0.1,
		TextSize = 68,
		ZIndex = 21,
		Parent = flightHud,
	})

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 70),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "STUDS",
		TextColor3 = COLOR.gold,
		TextStrokeColor3 = Color3.fromRGB(52, 38, 30),
		TextStrokeTransparency = 0.25,
		TextSize = 18,
		ZIndex = 21,
		Parent = flightHud,
	})

	local vitalsLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 96),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeColor3 = Color3.fromRGB(52, 38, 30),
		TextStrokeTransparency = 0.25,
		TextSize = 17,
		ZIndex = 21,
		Parent = flightHud,
	})

	-- ---------- the end-of-flight summary ----------
	local summary = make("Frame", {
		Name = "FlightSummary",
		Size = UDim2.new(0, 340, 0, 320),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.04,
		Active = true,
		Visible = false,
		ZIndex = 24,
		Parent = gui,
	})
	corner(20, summary)

	local summaryTitle = make("TextLabel", {
		Size = UDim2.new(1, -24, 0, 32),
		Position = UDim2.new(0, 12, 0, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "Landed!",
		TextColor3 = COLOR.text,
		TextSize = 26,
		ZIndex = 25,
		Parent = summary,
	})

	local summaryDistance = make("TextLabel", {
		Size = UDim2.new(1, -24, 0, 56),
		Position = UDim2.new(0, 12, 0, 46),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "0 studs",
		TextColor3 = COLOR.power,
		TextSize = 44,
		ZIndex = 25,
		Parent = summary,
	})

	-- One row per currency, so the reward reads as three separate wins rather
	-- than one sentence nobody parses.
	local function rewardRow(y: number, color: Color3): TextLabel
		local row = make("Frame", {
			Size = UDim2.new(1, -24, 0, 34),
			Position = UDim2.new(0, 12, 0, y),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.82,
			ZIndex = 25,
			Parent = summary,
		})
		corner(10, row)
		return make("TextLabel", {
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "",
			TextColor3 = COLOR.text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 26,
			Parent = row,
		})
	end

	local tntRow = rewardRow(112, COLOR.tnt)
	local coinRow = rewardRow(150, COLOR.coin)
	local gemRow = rewardRow(188, COLOR.gem)

	local breakdown = make("TextLabel", {
		Size = UDim2.new(1, -24, 0, 46),
		Position = UDim2.new(0, 12, 0, 228),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 25,
		Parent = summary,
	})

	local againButton = make("TextButton", {
		Size = UDim2.new(1, -24, 0, 38),
		Position = UDim2.new(0, 12, 1, -48),
		BackgroundColor3 = COLOR.go,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "NICE!",
		TextColor3 = COLOR.text,
		TextSize = 18,
		ZIndex = 25,
		Parent = summary,
	})
	corner(12, againButton)

	-- ---------- driving the meters ----------
	local function setStage(next: Stage)
		stage = next
		panel.Visible = next == "power" or next == "angle"
		flightHud.Visible = next == "flying"
		summary.Visible = next == "summary"

		if next == "power" then
			title.Text = "Charge it up!"
			title.TextColor3 = COLOR.text
			lockButton.Text = "LOCK CHARGE"
			lockButton.BackgroundColor3 = COLOR.go
			status.Text = ""
		elseif next == "angle" then
			title.Text = "Now the angle!"
			lockButton.Text = "FIRE!"
			lockButton.BackgroundColor3 = COLOR.power
		end
	end

	local function applyPendingField()
		local waiting = pendingField
		if waiting then
			pendingField = nil
			scene.setLaunchField(waiting)
		end
	end

	local function closeAiming()
		setStage("idle")
		scene.setView("main")
		-- Now that nothing is in the air, the next shot's track can go down.
		applyPendingField()
	end

	local function openAiming()
		if readyIn > 0 or stage ~= "idle" then
			return
		end
		chosenPower = 0
		sweep = 0
		powerBar.Size = UDim2.new(0, 0, 1, 0)
		angleBar.Position = UDim2.new(0, 3, 0, 3)
		scene.setView("cannon")
		setStage("power")
	end

	openButton.Activated:Connect(openAiming)
	closeButton.Activated:Connect(closeAiming)
	againButton.Activated:Connect(closeAiming)

	-- The sweep runs on the render step so the meters move smoothly; they are
	-- only ever a display, and the value is read at the instant of the tap.
	RunService.RenderStepped:Connect(function(dt)
		if stage == "flying" then
			-- Counting up beside the shot is the whole feedback loop of a
			-- distance game, so it reads the stage's live position rather than
			-- waiting for the landing to show a number.
			distanceLabel.Text = Format.abbreviate(math.floor(scene.flightDistance()))
			local bounces = scene.flightBounces()
			vitalsLabel.Text = ("⬆ %s   ⚡ %s/s%s"):format(
				Format.abbreviate(math.floor(scene.flightHeight())),
				Format.abbreviate(math.floor(scene.flightSpeed())),
				bounces > 0 and ("   ↻ %d bounce%s"):format(bounces, bounces == 1 and "" or "s") or ""
			)
			return
		end
		if stage ~= "power" and stage ~= "angle" then
			return
		end

		-- Ping-pong 0-1: a triangle wave is easier to read and to time than a
		-- sine, which crawls at both ends.
		sweep = (sweep + dt * 0.85) % 2
		local value = sweep <= 1 and sweep or 2 - sweep

		if stage == "power" then
			powerBar.Size = UDim2.fromScale(value, 1)
			status.Text = ("charge %d%%"):format(math.floor(value * 100 + 0.5))
		else
			angleBar.Position = UDim2.new(value, -value * 13 + 3, 0, 3)
			scene.setCannonAim(value)
			status.Text = ("charge %d%%   ·   angle %d°"):format(
				math.floor(chosenPower * 100 + 0.5),
				math.floor(Config.LaunchMinAngle + (Config.LaunchMaxAngle - Config.LaunchMinAngle) * value + 0.5)
			)
		end
	end)

	local function currentSweep(): number
		return sweep <= 1 and sweep or 2 - sweep
	end

	lockButton.Activated:Connect(function()
		if stage == "power" then
			chosenPower = currentSweep()
			powerBar.Size = UDim2.fromScale(chosenPower, 1)
			sweep = 0
			setStage("angle")
		elseif stage == "angle" then
			local chosenAngle = currentSweep()
			setStage("flying")
			distanceLabel.Text = "0"
			vitalsLabel.Text = ""
			-- Two numbers, nothing else. The server does the rest.
			shotRemote:FireServer(chosenPower, chosenAngle)
		end
	end)

	-- ---------- the server's verdict ----------
	resultRemote.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" or typeof(result.arcs) ~= "table" then
			return
		end

		-- The stage says how long its animation runs, so the summary can wait
		-- for the landing exactly rather than on a guessed timer.
		local flightSeconds = scene.playLaunch(result)

		task.delay(flightSeconds + 0.4, function()
			if stage ~= "flying" then
				return
			end
			best = math.max(result.best or 0, best)
			bestLabel.Text = ("best %s"):format(Format.abbreviate(math.floor(best)))

			summaryTitle.Text = result.record and "NEW BEST!" or "Landed!"
			summaryTitle.TextColor3 = result.record and COLOR.gold or COLOR.text
			summaryDistance.Text = ("%s studs"):format(Format.abbreviate(math.floor(result.distance or 0)))

			tntRow.Text = ("🧨  +%s TNT"):format(Format.abbreviate(result.tnt or 0))
			coinRow.Text = ("🪙  +%s coins"):format(Format.abbreviate(result.coins or 0))
			gemRow.Text = ("💎  +%s gems"):format(Format.abbreviate(result.gems or 0))

			-- The multiplier breakdown: what each part of the account actually
			-- contributed, so an upgrade's effect is visible rather than felt.
			local lines = {
				("%d bounce%s  ·  rebirth ×%d"):format(
					result.bounces or 0,
					(result.bounces or 0) == 1 and "" or "s",
					result.rebirths or 0
				),
				("coins ×%.2f   ·   TNT ×%.2f"):format(result.coinMultiplier or 1, result.tntMultiplier or 1),
			}
			if result.boosted then
				table.insert(lines, "🧨 Rain TNT was running")
			end
			local milestones = result.milestones or {}
			if #milestones > 0 then
				local names = {}
				for _, milestone in milestones do
					table.insert(names, milestone.name)
				end
				table.insert(lines, ("🏁 passed %s for the first time"):format(table.concat(names, ", ")))
			end
			breakdown.Text = table.concat(lines, "\n")

			setStage("summary")
			summary.BackgroundTransparency = 1
			TweenService:Create(summary, TweenInfo.new(0.25), { BackgroundTransparency = 0.04 }):Play()
		end)
	end)

	-- ---------- cooldown and record, straight from the server ----------
	function Launch.setReadyIn(seconds: number)
		readyIn = math.max(seconds, 0)
	end

	function Launch.setBest(distance: number)
		best = math.max(distance, 0)
		bestLabel.Text = ("best %s"):format(Format.abbreviate(math.floor(best)))
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
