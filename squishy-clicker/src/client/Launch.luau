--!strict
-- ============================================================
--  SQUISHY LAUNCH  —  the main game's controls.
--
--  A big LAUNCH button at the bottom of the screen. Tap it to
--  start a sweeping CHARGE meter, tap again to lock the charge,
--  once more for the angle. Then the shot goes out as nothing but
--  {power, angle}, two plain 0-1 numbers.
--
--  The squishy is fired, skips down the valley, sweeps up TNT,
--  cash and gems on the way and rolls to a stop. How far it got
--  is the score, and everything the run earned is read back on a
--  summary card at the end.
--
--  The client never says how far it went, what it collected or
--  what it won. The server simulates the whole flight and sends
--  back its shape — every hop, its peak, its duration — and this
--  draws that. See the comment on the server's ballistics section
--  for why the simulation is arithmetic and not Roblox physics.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local UI = require(script.Parent:WaitForChild("UI"))

local Launch = {}

-- Replaced when the panel mounts. No-ops until then, so a sync arriving
-- before the UI is up can't fail on a missing function.
function Launch.setReadyIn(_seconds: number) end
function Launch.setBest(_distance: number) end
-- Called by the plot's ProximityPrompt. The launcher's controls belong to the
-- cannon, so they only exist while the player is stood at it — that is what
-- makes the plot somewhere to go rather than scenery.
function Launch.setNearCannon(_near: boolean) end
function Launch.open() end

local C = UI.color

-- Stage of the shot: "idle", "power", "angle", "flying", "summary".
type Stage = "idle" | "power" | "angle" | "flying" | "summary"

-- How long to wait for the server's verdict before giving the screen back.
-- Comfortably longer than any round trip, and shorter than a player's patience.
local LAUNCH_TIMEOUT = 6

function Launch.mount(gui: GuiObject, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shotRemote = remotes:WaitForChild("LaunchShot") :: RemoteEvent
	local resultRemote = remotes:WaitForChild("LaunchResult") :: RemoteEvent
	local fieldRemote = remotes:WaitForChild("LaunchField") :: RemoteEvent

	local stage: Stage = "idle"
	local sweep = 0 -- the live 0-1 position of whichever meter is moving
	local chosenPower = 0
	local readyIn = 0 -- seconds left on the cooldown, straight from the server
	local best = 0 -- furthest ever flown, straight from the server
	-- Bumped on every shot AND every reply, so a late watchdog can tell
	-- whether the shot it was armed for is still the one in the air.
	local shotToken = 0

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

	-- ---------- the record banner ----------
	local bestBanner = UI.make("Frame", {
		Name = "BestBanner",
		Size = UDim2.new(0, 240, 0, 44),
		Position = UDim2.new(0.5, 0, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.orange,
		ZIndex = 5,
		Parent = gui,
	})
	UI.corner(14, bestBanner)
	UI.gradient(bestBanner, C.orange, C.orangeDeep)
	UI.stroke(bestBanner)

	local bestLabel = UI.label({
		Size = UDim2.fromScale(1, 1),
		Text = "🏆 Best  0 Studs",
		TextSize = 20,
		ZIndex = 6,
		Parent = bestBanner,
	})

	-- ---------- the charge panel ----------
	-- Bottom centre, right above the launch button, so the meter and the
	-- thumb that stops it are in the same place.
	local panel = UI.make("Frame", {
		Name = "ChargePanel",
		Size = UDim2.new(0, 420, 0, 132),
		Position = UDim2.new(0.5, 0, 1, -108),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.body,
		Active = true, -- swallow taps, or aiming also squishes the squisher
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	})
	UI.corner(16, panel)
	UI.gradient(panel, C.body, C.bodyDark)
	UI.stroke(panel, 4)

	local title = UI.label({
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 10, 0, 6),
		Text = "Charge it up!",
		TextSize = 24,
		ZIndex = 9,
		Parent = panel,
	})

	-- Two meters. The charge one FILLS, because "how full is it" is the thing
	-- the player is timing; the angle one slides a marker, because there the
	-- question is "where is it pointing".
	local function meter(y: number, top: Color3, bottom: Color3, filling: boolean, caption: string): (Frame, Frame)
		local track = UI.make("Frame", {
			Size = UDim2.new(1, -20, 0, 30),
			Position = UDim2.new(0, 10, 0, y),
			BackgroundColor3 = Color3.fromRGB(96, 58, 26),
			ClipsDescendants = true,
			ZIndex = 9,
			Parent = panel,
		})
		UI.corner(12, track)
		UI.stroke(track)

		local bar = UI.make("Frame", {
			Size = filling and UDim2.new(0, 0, 1, 0) or UDim2.new(0, 16, 1, -8),
			Position = filling and UDim2.fromScale(0, 0) or UDim2.new(0, 4, 0, 4),
			BackgroundColor3 = top,
			BorderSizePixel = 0,
			ZIndex = 10,
			Parent = track,
		})
		UI.corner(filling and 12 or 8, bar)
		UI.gradient(bar, top, bottom)

		UI.label({
			Size = UDim2.fromScale(1, 1),
			Text = caption,
			TextSize = 15,
			ZIndex = 12,
			Parent = track,
		})
		return track, bar
	end

	local _, powerBar = meter(42, C.orange, C.orangeDeep, true, "CHARGE")
	local _, angleBar = meter(80, C.blue, C.blueDeep, false, "ANGLE")

	-- ---------- the notice line ----------
	-- Sits just above the launch button and says why a shot did not happen.
	-- A refusal the player cannot see is indistinguishable from a broken game,
	-- which is exactly how the cooldown used to read.
	local notice = UI.label({
		Name = "LaunchNotice",
		Size = UDim2.new(0, 420, 0, 30),
		Position = UDim2.new(0.5, 0, 1, -104),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(252, 214, 132),
		StrokeThickness = 3,
		Visible = false,
		ZIndex = 9,
		Parent = gui,
	})
	local noticeToken = 0

	-- ---------- the launch button ----------
	local launchButton = UI.button({
		parent = gui,
		size = UDim2.new(0, 300, 0, 78),
		position = UDim2.new(0.5, 0, 1, -18),
		anchor = Vector2.new(0.5, 1),
		text = "🚀 LAUNCH!",
		textSize = 34,
		top = C.green,
		bottom = C.greenDeep,
		zIndex = 8,
		radius = 18,
	})

	-- ---------- the in-flight readout ----------
	-- Deliberately huge and centred rather than tucked in a panel: while the
	-- shot is in the air the distance is the only thing worth reading, and it
	-- has to be legible at a glance on a phone.
	local flightHud = UI.make("Frame", {
		Name = "FlightHud",
		Size = UDim2.new(0, 460, 0, 140),
		Position = UDim2.new(0.5, 0, 0, 20),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})

	local distanceLabel = UI.label({
		Size = UDim2.new(1, 0, 0, 82),
		Text = "0",
		TextSize = 76,
		StrokeThickness = 4,
		ZIndex = 21,
		Parent = flightHud,
	})
	UI.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 78),
		Text = "STUDS",
		TextSize = 20,
		TextColor3 = Color3.fromRGB(252, 214, 132),
		ZIndex = 21,
		Parent = flightHud,
	})
	local vitalsLabel = UI.label({
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 0, 104),
		Text = "",
		TextSize = 19,
		ZIndex = 21,
		Parent = flightHud,
	})

	-- ---------- the end-of-flight summary ----------
	local summary = UI.panel({
		parent = gui,
		name = "FlightSummary",
		size = UDim2.new(0, 420, 0, 400),
		position = UDim2.fromScale(0.5, 0.5),
		icon = "🚀",
		title = "Landed!",
		top = C.green,
		bottom = C.greenDeep,
		zIndex = 30,
	})

	local summaryDistance = UI.label({
		Size = UDim2.new(1, -24, 0, 64),
		Position = UDim2.new(0, 12, 0, 8),
		Text = "0 Studs",
		TextSize = 50,
		StrokeThickness = 3,
		ZIndex = 33,
		Parent = summary.body,
	})

	-- One row per currency, so the reward reads as three separate wins rather
	-- than one sentence nobody parses.
	local function rewardRow(y: number, top: Color3, bottom: Color3): TextLabel
		local card = UI.card({
			parent = summary.body,
			size = UDim2.new(1, -24, 0, 44),
			position = UDim2.new(0, 12, 0, y),
			top = top,
			bottom = bottom,
			zIndex = 33,
		})
		return UI.label({
			Size = UDim2.new(1, -20, 1, 0),
			Position = UDim2.new(0, 12, 0, 0),
			Text = "",
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 34,
			Parent = card,
		})
	end

	local tntRow = rewardRow(78, C.tnt, Color3.fromRGB(212, 106, 40))
	local coinRow = rewardRow(128, C.cash, Color3.fromRGB(84, 186, 60))
	local gemRow = rewardRow(178, C.gem, Color3.fromRGB(64, 190, 190))

	local breakdown = UI.label({
		Size = UDim2.new(1, -24, 0, 66),
		Position = UDim2.new(0, 12, 0, 228),
		Text = "",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(252, 226, 180),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		StrokeThickness = 1.5,
		ZIndex = 33,
		Parent = summary.body,
	})

	local againButton = UI.button({
		parent = summary.body,
		size = UDim2.new(1, -24, 0, 50),
		position = UDim2.new(0, 12, 1, -60),
		text = "LAUNCH AGAIN",
		textSize = 24,
		top = C.green,
		bottom = C.greenDeep,
		zIndex = 33,
	})

	-- ---------- driving the meters ----------
	-- The launcher's controls belong to the valley. At the toy shop they come
	-- down entirely — the nav rail is how you get back to them — because the
	-- big centred LAUNCH button otherwise lands straight on top of the steamer
	-- bar as soon as the window is anything less than very wide.
	local atValley = true
	-- Stood at your own cannon. Everything the launcher offers hangs off this:
	-- walk away and the controls go with you.
	local nearCannon = false

	local function setStage(next: Stage)
		stage = next
		local aiming = next == "idle" or next == "power" or next == "angle"
		-- Mid-shot the player is not stood anywhere in particular — the camera
		-- is off down the valley — so the flight HUD and the summary ignore
		-- nearCannon and only the aiming controls respect it.
		local controls = aiming and nearCannon
		panel.Visible = atValley and controls and (next == "power" or next == "angle")
		flightHud.Visible = atValley and next == "flying"
		summary.root.Visible = atValley and next == "summary"
		bestBanner.Visible = atValley and controls
		launchButton.button.Visible = atValley and controls
		if not atValley then
			notice.Visible = false
		end

		if next == "power" then
			title.Text = "Charge it up!"
			launchButton.button.Text = "LOCK CHARGE"
		elseif next == "angle" then
			title.Text = "Now the angle!"
			launchButton.button.Text = "🔥 FIRE!"
		elseif next == "idle" then
			launchButton.button.Text = "🚀 LAUNCH!"
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
		-- Now that nothing is in the air, the next shot's track can go down.
		applyPendingField()
	end

	-- A refused or lost shot. Hands the screen straight back rather than
	-- leaving the player looking at a flight that is never going to happen.
	local function abandonShot(reason: string)
		shotToken += 1 -- disarm any watchdog still counting down for this shot
		closeAiming()
		notice.Text = reason
		notice.Visible = true
		noticeToken += 1
		local token = noticeToken
		task.delay(2.6, function()
			if token == noticeToken then
				notice.Visible = false
			end
		end)
	end

	summary.close.Activated:Connect(closeAiming)
	againButton.button.Activated:Connect(closeAiming)

	scene.onViewChanged(function(nowAtValley)
		atValley = nowAtValley
		-- Walking off mid-aim abandons the aim rather than leaving a half-set
		-- charge waiting to be fired at whatever the meters happen to read
		-- when the player wanders back.
		if not atValley and (stage == "power" or stage == "angle") then
			setStage("idle")
		else
			setStage(stage)
		end
	end)

	local function currentSweep(): number
		return sweep <= 1 and sweep or 2 - sweep
	end

	launchButton.button.Activated:Connect(function()
		if stage == "idle" then
			if readyIn > 0 then
				return
			end
			chosenPower = 0
			sweep = 0
			powerBar.Size = UDim2.new(0, 0, 1, 0)
			angleBar.Position = UDim2.new(0, 4, 0, 4)
			scene.setView("main")
			setStage("power")
		elseif stage == "power" then
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

			-- WATCHDOG. Entering "flying" hides the launch button and hands the
			-- screen to the flight HUD, and it has to happen now rather than on
			-- the reply — otherwise the meters keep sweeping under the player's
			-- thumb while the round trip completes. The cost is that a reply
			-- which never arrives leaves the UI dead: HUD stuck at zero, no
			-- button, no way back. The server answers every refusal it can, but
			-- a dropped packet or a rate-limit drop answers nothing, so this
			-- catches whatever falls through.
			shotToken += 1
			local token = shotToken
			task.delay(LAUNCH_TIMEOUT, function()
				if stage == "flying" and token == shotToken then
					abandonShot("No answer from the cannon — try again.")
				end
			end)
		end
	end)

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
			title.Text = ("Charge  %d%%"):format(math.floor(value * 100 + 0.5))
		else
			angleBar.Position = UDim2.new(value, -value * 20 + 4, 0, 4)
			scene.setCannonAim(value)
			title.Text = ("Charge %d%%   ·   Angle %d°"):format(
				math.floor(chosenPower * 100 + 0.5),
				math.floor(Config.LaunchMinAngle + (Config.LaunchMaxAngle - Config.LaunchMinAngle) * value + 0.5)
			)
		end
	end)

	-- ---------- the server's verdict ----------
	resultRemote.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" then
			return
		end

		-- A refusal. The server tells us why rather than dropping the request,
		-- so the screen comes straight back with a reason on it.
		if result.ok == false then
			abandonShot(typeof(result.reason) == "string" and result.reason or "The cannon refused that shot.")
			return
		end

		if typeof(result.arcs) ~= "table" then
			return
		end
		-- A real verdict arrived: disarm the watchdog armed when we fired.
		shotToken += 1

		-- The stage says how long its animation runs, so the summary can wait
		-- for the landing exactly rather than on a guessed timer. Announcing
		-- the distance mid-flight would give the ending away.
		local flightSeconds = scene.playLaunch(result)

		task.delay(flightSeconds + 0.4, function()
			if stage ~= "flying" then
				return
			end
			best = math.max(result.best or 0, best)
			bestLabel.Text = ("🏆 Best  %s Studs"):format(Format.abbreviate(math.floor(best)))

			summary.title.Text = result.record and "NEW BEST!" or "Landed!"
			summaryDistance.Text = ("%s Studs"):format(Format.abbreviate(math.floor(result.distance or 0)))

			tntRow.Text = ("🧨  +%s TNT"):format(Format.abbreviate(result.tnt or 0))
			coinRow.Text = ("💵  +%s Cash"):format(Format.abbreviate(result.coins or 0))
			gemRow.Text = ("💎  +%s Gems"):format(Format.abbreviate(result.gems or 0))

			-- The multiplier breakdown: what each part of the account actually
			-- contributed, so an upgrade's effect is visible rather than felt.
			local lines = {
				("%d bounce%s   ·   rebirth ×%d"):format(
					result.bounces or 0,
					(result.bounces or 0) == 1 and "" or "s",
					result.rebirths or 0
				),
				("cash ×%.2f   ·   TNT ×%.2f"):format(result.coinMultiplier or 1, result.tntMultiplier or 1),
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
			summary.root.BackgroundTransparency = 1
			TweenService:Create(summary.root, TweenInfo.new(0.22), { BackgroundTransparency = 0 }):Play()
		end)
	end)

	-- ---------- cooldown and record, straight from the server ----------
	function Launch.setReadyIn(seconds: number)
		readyIn = math.max(seconds, 0)
	end

	function Launch.setBest(distance: number)
		best = math.max(distance, 0)
		bestLabel.Text = ("🏆 Best  %s Studs"):format(Format.abbreviate(math.floor(best)))
	end

	function Launch.setNearCannon(near: boolean)
		if near == nearCannon then
			return
		end
		nearCannon = near
		-- Walking off mid-aim abandons the aim rather than leaving a half-set
		-- charge waiting to be fired at whatever the meters read when the
		-- player wanders back. A shot already in the air is left alone.
		if not near and (stage == "power" or stage == "angle") then
			setStage("idle")
		else
			setStage(stage)
		end
	end

	-- The prompt's own activation: skip straight past "idle" into the charge
	-- meter, so pressing E at the cannon starts aiming rather than only
	-- revealing a button that then has to be pressed as well.
	function Launch.open()
		if not nearCannon or stage ~= "idle" or readyIn > 0 then
			return
		end
		chosenPower = 0
		sweep = 0
		powerBar.Size = UDim2.new(0, 0, 1, 0)
		angleBar.Position = UDim2.new(0, 4, 0, 4)
		setStage("power")
	end

	task.spawn(function()
		while true do
			task.wait(0.25)
			if readyIn > 0 then
				readyIn = math.max(readyIn - 0.25, 0)
			end
			if stage == "idle" then
				local ready = readyIn <= 0
				launchButton.button.Text = ready and "🚀 LAUNCH!" or ("🚀 %ds"):format(math.ceil(readyIn))
				UI.setButtonEnabled(launchButton, ready, C.green, C.greenDeep)
			end
		end
	end)

	setStage("idle")
end

return Launch
