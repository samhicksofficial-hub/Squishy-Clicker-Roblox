--!strict
-- ============================================================
--  SQUISHY LAUNCH  —  the main game's controls.
--
--  Aiming is a PRECISION TIMING game: a needle sweeps back and
--  forth across a red-yellow-green bar, and every tap locks in
--  how close to the green centre it was caught. After the
--  configured number of taps the shot fires with the AVERAGE of
--  those accuracies as its power — one lucky tap cannot carry a
--  shot, one slip cannot sink it.
--
--  Then the shot goes out as nothing but {power, angle}, two
--  plain 0-1 numbers. The angle is a Config constant now that
--  the meter owns the skill; the server validates it like any
--  hostile payload regardless.
--
--  The squishy is fired, skips across the plain, sweeps up Cash
--  on the way and rolls to a stop. How far it got is the score,
--  and everything the run earned is read back on a summary card
--  at the end.
--
--  The client never says how far it went, what it collected or
--  what it won. The server simulates the whole flight and sends
--  back its shape — every hop, its peak, its duration — and
--  Flight.luau draws that.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Format"))
local UI = require(script.Parent:WaitForChild("UI"))
-- For the cash-collect animation on landing. One-way: Cannon never
-- requires Launch, so this cannot cycle.
local Cannon = require(script.Parent:WaitForChild("Cannon"))
-- The shot is drawn in the real world, out from the player's own plot. Scene
-- still owns the steamer and the squisher close-ups; it does not own the flight.
local Flight = require(script.Parent:WaitForChild("Flight"))

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

-- Stage of the shot: "idle", "aim" (the meter is up), "flying", "summary".
type Stage = "idle" | "aim" | "flying" | "summary"

-- How long to wait for the server's verdict before giving the screen back.
-- Comfortably longer than any round trip, and shorter than a player's patience.
local LAUNCH_TIMEOUT = 6

function Launch.mount(gui: GuiObject, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local shotRemote = remotes:WaitForChild("LaunchShot") :: RemoteEvent
	local resultRemote = remotes:WaitForChild("LaunchResult") :: RemoteEvent
	local bonusRemote = remotes:WaitForChild("FlightBonus") :: RemoteEvent

	local stage: Stage = "idle"
	local readyIn = 0 -- seconds left on the cooldown, straight from the server
	local best = 0 -- furthest ever flown, straight from the server
	local launchPower = 0 -- the cannon's power, straight from the server (picks the aim game)
	-- Bumped on every shot AND every reply, so a late watchdog can tell
	-- whether the shot it was armed for is still the one in the air.
	local shotToken = 0

	-- The accuracy locked in by each tap so far.
	local tapsLocked: { number } = {}

	-- The landing watch. A living flight promises no duration, so the
	-- summary cannot run on a timer: the RenderStepped loop below watches
	-- Flight.flying() flip false, arms this deadline, and the settlement
	-- (FlightBonus) either arrives inside it and paints the summary, or the
	-- screen is handed back with an apology.
	local bonusDeadline: number? = nil

	-- The serial of the shot currently on screen, -1 while none is. The
	-- settlement handler only answers for THIS shot: firing while an old
	-- claim went missing makes the server settle the old shot first, and
	-- without the serial gate that stale verdict would hijack the new
	-- flight's summary mid-air.
	local currentSerial = -1

	-- ---------- the record banner ----------
	local bestBanner = UI.make("Frame", {
		Name = "BestBanner",
		-- Below the wallet, which owns the top-centre now.
		Size = UDim2.new(0, 240, 0, 44),
		Position = UDim2.new(0.5, 0, 0, 72),
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

	-- ---------- the locked scores ----------
	-- The rhythm duel needs no panel and no instructions — the numbered
	-- circles ARE the instructions. All that shows is what each catch
	-- scored, filled in left to right above the launch button, so the
	-- average being sent is legible rather than a mystery.
	local locksLabel = UI.label({
		Size = UDim2.new(0, 320, 0, 30),
		Position = UDim2.new(0.5, 0, 1, -116),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "",
		TextSize = 22,
		TextColor3 = Color3.fromRGB(252, 224, 140),
		StrokeThickness = 3,
		Visible = false,
		ZIndex = 9,
		Parent = gui,
	})

	-- ---------- the tap catcher ----------
	-- Full screen, above everything, only while aiming. Every press lands
	-- here and locks a tap — which is what "tap anywhere" costs: while the
	-- meter is up, nothing else on screen is pressable except Cancel.
	local tapCatcher = UI.make("TextButton", {
		Name = "TapCatcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 50,
		Parent = gui,
	}) :: TextButton

	-- The one control that outranks the catcher, so aiming can be walked out
	-- of without walking away from the cannon.
	local cancelButton = UI.button({
		parent = gui,
		size = UDim2.new(0, 44, 0, 40),
		position = UDim2.new(0.5, 244, 1, -212),
		anchor = Vector2.new(0.5, 1),
		text = "X",
		textSize = 22,
		top = C.red,
		bottom = C.redDeep,
		zIndex = 60,
		radius = 10,
	})
	cancelButton.button.Visible = false

	-- Tick per locked tap, pitch rising with the count, so three taps make a
	-- little ascending phrase.
	local tapSound = Instance.new("Sound")
	tapSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	tapSound.Volume = 0.3
	tapSound.Parent = SoundService

	-- ---------- the rhythm aim ----------
	-- THE aim game, from the very first shot: numbered circles appear one
	-- after another at random spots, each with an approach ring shrinking
	-- onto it, and the press is scored by how CLOSED the ring was at that
	-- instant. The ring travels at a gentle fixed pace until the cannon
	-- passes Config.RhythmPowerReference, then LINEARLY faster with power,
	-- so the duel keeps escalating instead of topping out. Three scored
	-- catches average into the same 0-1 power the server validates
	-- regardless.
	local RHYTHM_CIRCLE = 84 -- the target circle's diameter, in pixels
	local RHYTHM_RING_FROM = 3.4 -- the approach ring starts this many circles wide
	local rhythmDuration = 1
	local rhythmStart = 0
	local rhythmCircle: Frame? = nil
	local rhythmRing: Frame? = nil

	local function clearRhythmCircle()
		if rhythmCircle then
			rhythmCircle:Destroy()
			rhythmCircle = nil
		end
		if rhythmRing then
			rhythmRing:Destroy()
			rhythmRing = nil
		end
	end

	local function spawnRhythmCircle()
		clearRhythmCircle()
		rhythmStart = os.clock()
		-- A random seat in the middle band of the screen — never under the
		-- rails, the wallet or the launch controls at the bottom.
		local x = 0.24 + math.random() * 0.52
		local y = 0.2 + math.random() * 0.42

		local circle = UI.make("Frame", {
			Size = UDim2.new(0, RHYTHM_CIRCLE, 0, RHYTHM_CIRCLE),
			Position = UDim2.new(x, 0, y, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.green,
			ZIndex = 52,
			Parent = gui,
		}) :: Frame
		UI.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = circle })
		UI.stroke(circle, 4)
		UI.label({
			Size = UDim2.fromScale(1, 1),
			Text = tostring(#tapsLocked + 1),
			TextSize = 40,
			StrokeThickness = 3,
			ZIndex = 53,
			Parent = circle,
		})

		-- The approach ring: an empty circle outline that the render loop
		-- shrinks onto the target. Catch it at its smallest for the 100%.
		local ring = UI.make("Frame", {
			Size = UDim2.new(0, RHYTHM_CIRCLE * RHYTHM_RING_FROM, 0, RHYTHM_CIRCLE * RHYTHM_RING_FROM),
			Position = UDim2.new(x, 0, y, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = gui,
		}) :: Frame
		UI.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
		UI.stroke(ring, 5, Color3.fromRGB(255, 255, 255))

		rhythmCircle = circle
		rhythmRing = ring
	end

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
		-- Below the wallet, which owns the top-centre now.
		Size = UDim2.new(0, 460, 0, 158),
		Position = UDim2.new(0.5, 0, 0, 72),
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
	UI.label({
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 134),
		Text = "◀ A / D ▶ steer   ·   SPACE or tap to SLAM",
		TextSize = 15,
		TextColor3 = Color3.fromRGB(220, 240, 255),
		ZIndex = 21,
		Parent = flightHud,
	})

	-- ---------- the flight progress bar ----------
	-- A rainbow ruler along the BOTTOM of the screen, running the LEG of
	-- the milestone ladder the flight is currently on (0→100, 100→1K,
	-- 1K→10K, ...): the You marker crawls it, and filling the bar leaps the
	-- labels to the next leg. Legs rather than one fixed track, because an
	-- endless flight against a single 0-to-1M bar would sit at "empty" for
	-- its whole early life — this way the bar is always mid-story. Its own
	-- screen-wide frame rather than a child of the readout, shown and
	-- hidden by the same stage that shows the readout.
	local progressTrack = UI.make("Frame", {
		Name = "FlightProgress",
		Size = UDim2.new(0.7, 0, 0, 36),
		Position = UDim2.new(0.5, 0, 1, -26),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	UI.corner(18, progressTrack)
	UI.stroke(progressTrack)
	UI.make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(238, 72, 200)),
			ColorSequenceKeypoint.new(0.16, Color3.fromRGB(150, 82, 240)),
			ColorSequenceKeypoint.new(0.36, Color3.fromRGB(72, 130, 245)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(62, 202, 220)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(92, 225, 100)),
			ColorSequenceKeypoint.new(0.82, Color3.fromRGB(245, 210, 70)),
			ColorSequenceKeypoint.new(0.92, Color3.fromRGB(245, 150, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 72, 60)),
		}),
		Parent = progressTrack,
	})

	-- The ruler's numbers, five across the leg.
	local progressTicks: { TextLabel } = {}
	for index = 1, 5 do
		local fraction = (index - 1) / 4
		progressTicks[index] = UI.label({
			Size = UDim2.new(0, 110, 1, 0),
			Position = UDim2.new(fraction, if index == 1 then 10 elseif index == 5 then -10 else 0, 0, 0),
			AnchorPoint = Vector2.new(if index == 1 then 0 elseif index == 5 then 1 else 0.5, 0),
			Text = "",
			TextSize = 21,
			StrokeThickness = 2,
			ZIndex = 23,
			Parent = progressTrack,
		})
	end

	-- The You marker riding above the ruler, screenshot-style.
	local youMarker = UI.make("Frame", {
		Name = "You",
		Size = UDim2.new(0, 64, 0, 42),
		Position = UDim2.new(0, 0, 0, -44),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 24,
		Parent = progressTrack,
	})
	UI.label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "You",
		TextSize = 21,
		TextColor3 = Color3.fromRGB(255, 196, 72),
		StrokeThickness = 3,
		ZIndex = 24,
		Parent = youMarker,
	})
	UI.label({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 21),
		Text = "▼",
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 196, 72),
		StrokeThickness = 2,
		ZIndex = 24,
		Parent = youMarker,
	})

	-- The ladder itself: 0 plus every milestone distance, in order.
	local progressLadder: { number } = { 0 }
	for _, milestone in Config.DistanceMilestones do
		table.insert(progressLadder, milestone.at)
	end
	local progressLeg = 0 -- 0 = unlabelled, forces the first relabel

	local function updateProgress(distance: number)
		local leg = #progressLadder - 1
		for index = 1, #progressLadder - 1 do
			if distance < progressLadder[index + 1] then
				leg = index
				break
			end
		end
		local from, to = progressLadder[leg], progressLadder[leg + 1]
		if leg ~= progressLeg then
			progressLeg = leg
			for index, tick in progressTicks do
				tick.Text = Format.abbreviate(from + (to - from) * (index - 1) / 4)
			end
		end
		local fraction = math.clamp((distance - from) / math.max(to - from, 1), 0, 1)
		youMarker.Position = UDim2.new(fraction, 0, 0, -44)
	end

	-- ---------- the end-of-flight summary ----------
	local summary = UI.panel({
		parent = gui,
		name = "FlightSummary",
		size = UDim2.new(0, 420, 0, 430),
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

	-- The reward rows STACK in a list rather than sitting at fixed heights:
	-- most shots have no milestone bounty, and a fixed slot left a hole in
	-- the card exactly where the bounty would have been. Hidden cards now
	-- collapse and everything below rides up.
	local rewards = UI.make("Frame", {
		Size = UDim2.new(1, -24, 0, 220),
		Position = UDim2.new(0, 12, 0, 78),
		BackgroundTransparency = 1,
		ZIndex = 33,
		Parent = summary.body,
	})
	UI.make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rewards,
	})

	-- One row per win, so the reward reads as separate prizes rather than
	-- one sentence nobody parses.
	local function rewardRow(order: number, top: Color3, bottom: Color3): TextLabel
		local card = UI.card({
			parent = rewards,
			size = UDim2.new(1, 0, 0, 44),
			position = UDim2.new(0, 0, 0, 0), -- the list drives placement
			top = top,
			bottom = bottom,
			zIndex = 33,
		})
		card.LayoutOrder = order
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

	-- Track Cash on top, milestone bounties beneath, and the mid-air game's
	-- settled claim (steered pickups, boots, slams, less bombs) under those.
	local coinRow = rewardRow(1, C.cash, Color3.fromRGB(84, 186, 60))
	local bountyRow = rewardRow(2, C.orange, C.orangeDeep)
	local skillRow = rewardRow(3, C.purple, C.purpleDeep)

	local breakdown = UI.label({
		Size = UDim2.new(1, 0, 0, 66),
		LayoutOrder = 10,
		Text = "",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(252, 226, 180),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		StrokeThickness = 1.5,
		ZIndex = 33,
		Parent = rewards,
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

	-- ---------- stages ----------
	-- The launcher's controls belong to the island. At the toy shop they come
	-- down entirely — the nav rail is how you get back to them — because the
	-- big centred LAUNCH button otherwise lands straight on top of the steamer
	-- bar as soon as the window is anything less than very wide.
	local atValley = true
	-- Stood at your own cannon. Everything the launcher offers hangs off this:
	-- walk away and the controls go with you.
	local nearCannon = false


	local function setStage(next: Stage)
		stage = next
		-- Leaving the aim for ANY reason takes the rhythm circles with it.
		if next ~= "aim" then
			clearRhythmCircle()
		end
		local controls = atValley and nearCannon
		local aiming = controls and next == "aim"
		tapCatcher.Visible = aiming
		cancelButton.button.Visible = aiming
		locksLabel.Visible = aiming
		flightHud.Visible = atValley and next == "flying"
		progressTrack.Visible = atValley and next == "flying"
		summary.root.Visible = atValley and next == "summary"
		bestBanner.Visible = controls and (next == "idle" or next == "aim")
		launchButton.button.Visible = controls and next == "idle"
		if not atValley then
			notice.Visible = false
		end

		if next == "idle" then
			launchButton.button.Text = "🚀 LAUNCH!"
		end
	end

	local function closeAiming()
		setStage("idle")
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
	cancelButton.button.Activated:Connect(function()
		if stage == "aim" then
			closeAiming()
		end
	end)

	scene.onViewChanged(function(nowAtValley)
		atValley = nowAtValley
		-- Walking off mid-aim abandons the aim rather than leaving half the
		-- taps locked and waiting for whoever wanders back.
		if not atValley and stage == "aim" then
			setStage("idle")
		else
			setStage(stage)
		end
	end)

	-- ---------- the meter ----------

	local function beginAiming()
		tapsLocked = {}
		locksLabel.Text = ""

		-- Ring speed: a gentle fixed pace until RhythmPowerReference, then
		-- LINEARLY faster with power, floored so the duel stays humanly
		-- winnable however monstrous the cannon gets.
		rhythmDuration = math.clamp(
			Config.RhythmApproachSeconds * Config.RhythmPowerReference / math.max(launchPower, 1),
			Config.RhythmApproachMinSeconds,
			Config.RhythmApproachSeconds
		)

		-- Stage FIRST, circle second. setView re-fires the view listener,
		-- and that listener re-runs setStage with whatever stage is current
		-- — which was "idle", and leaving-aim cleanup ate a circle spawned
		-- any earlier: an aim with no ring, no timeout and no way to fire.
		scene.setView("main")
		setStage("aim")
		spawnRhythmCircle()
	end

	local function fireShot()
		-- The AVERAGE of the locked taps is the power. The angle is a Config
		-- constant — the meter owns the skill now — and the server validates
		-- both like any hostile payload regardless.
		local sum = 0
		for _, locked in tapsLocked do
			sum += locked
		end
		local power = sum / math.max(#tapsLocked, 1)

		setStage("flying")
		distanceLabel.Text = "0"
		vitalsLabel.Text = ""
		progressLeg = 0
		updateProgress(0)
		bonusDeadline = nil
		currentSerial = -1 -- unknown until the server's answer names it
		shotRemote:FireServer(power, Config.LaunchFixedAngle)

		-- WATCHDOG. Entering "flying" hides the controls and hands the screen
		-- to the flight HUD, and it has to happen now rather than on the
		-- reply. The cost is that a reply which never arrives leaves the UI
		-- dead — so this catches whatever falls through. The server answers
		-- every refusal it can; a dropped packet answers nothing.
		shotToken += 1
		local token = shotToken
		task.delay(LAUNCH_TIMEOUT, function()
			if stage == "flying" and token == shotToken then
				abandonShot("No answer from the cannon — try again.")
			end
		end)
	end

	-- `forced` is the timeout path: a ring that fully slipped past scores
	-- as the fumble it was, and the shot still always fires.
	local function lockTap(forced: number?)
		if stage ~= "aim" then
			return
		end

		-- Scored by how CLOSED the approach ring was at the press: 1 at the
		-- instant it meets the circle, falling off on both sides.
		local precision = forced
		if not precision then
			local p = (os.clock() - rhythmStart) / math.max(rhythmDuration, 1e-3)
			precision = math.clamp(1 - math.abs(1 - p) * 2.4, 0, 1)
		end
		table.insert(tapsLocked, precision)

		-- The tick pitches up with each catch, so a full set makes a little
		-- ascending phrase.
		tapSound.PlaybackSpeed = 0.9 + #tapsLocked * 0.18 + precision * 0.25
		tapSound:Play()

		local locked = {}
		for _, value in tapsLocked do
			table.insert(locked, ("%d%%"):format(math.floor(value * 100 + 0.5)))
		end
		locksLabel.Text = table.concat(locked, "  ·  ")

		if #tapsLocked >= Config.LaunchTapsRequired then
			fireShot()
		else
			-- The next circle of the sequence, somewhere new.
			spawnRhythmCircle()
		end
	end

	-- MouseButton1Down rather than Activated: a timing game has to read the
	-- press, not the release, or fast taps score the wrong needle position.
	-- (Touch taps fire this too.) Wrapped, NOT connected directly: the
	-- signal passes the click's x, y — which lockTap would read as its
	-- `forced` score.
	tapCatcher.MouseButton1Down:Connect(function()
		lockTap()
	end)

	launchButton.button.Activated:Connect(function()
		if stage == "idle" and readyIn <= 0 then
			beginAiming()
		end
	end)

	-- The sweep runs on the render step so the needle moves smoothly; it is
	-- only ever a display, and the value is read at the instant of the tap.
	RunService.RenderStepped:Connect(function()
		if stage == "flying" then
			-- Counting up beside the shot is the whole feedback loop of a
			-- distance game, so it reads the stage's live position rather than
			-- waiting for the landing to show a number.
			distanceLabel.Text = Format.abbreviate(math.floor(Flight.distance()))
			local bounces = Flight.bounces()
			vitalsLabel.Text = ("⬆ %s   ⚡ %s/s%s"):format(
				Format.abbreviate(math.floor(Flight.height())),
				Format.abbreviate(math.floor(Flight.speed())),
				bounces > 0 and ("   ↻ %d bounce%s"):format(bounces, bounces == 1 and "" or "s") or ""
			)
			updateProgress(Flight.distance())
			-- The landing watch: the flight is over when the sim says so —
			-- no timer knew in advance. From that moment the settlement has
			-- this long to arrive with the summary's numbers. (Before the
			-- server's launch answer, Flight isn't flying either; the fire
			-- watchdog owns that window, and the result handler re-arms
			-- this one.)
			if not Flight.flying() and bonusDeadline == nil then
				bonusDeadline = os.clock() + 10
			end
			if bonusDeadline and os.clock() > bonusDeadline then
				bonusDeadline = nil
				abandonShot("The landing went missing — try another shot.")
			end
			return
		end
		if stage ~= "aim" then
			return
		end

		-- The approach ring closes on the circle over rhythmDuration; past
		-- a grace beyond the meeting point the catch is scored as the
		-- fumble it was and the duel moves on.
		local ring = rhythmRing
		if not ring then
			-- Belt and braces: an aim stage with no ring would otherwise
			-- sit forever — no circle, no timeout, no way to fire.
			spawnRhythmCircle()
			return
		end
		local p = (os.clock() - rhythmStart) / math.max(rhythmDuration, 1e-3)
		local scale = math.max(RHYTHM_RING_FROM - (RHYTHM_RING_FROM - 1) * p, 1)
		ring.Size = UDim2.new(0, RHYTHM_CIRCLE * scale, 0, RHYTHM_CIRCLE * scale)
		if p > 1.3 then
			lockTap(0.05)
		end
	end)

	-- ---------- the settlement, which IS the summary now ----------
	-- The whole payout arrives here after the flight lands and the server
	-- re-runs it: distance, cash, milestones, the record. Nothing was known
	-- at fire time — a living flight has no numbers until it stops.
	bonusRemote.OnClientEvent:Connect(function(bonus)
		if typeof(bonus) ~= "table" then
			return
		end
		if stage ~= "flying" then
			return
		end
		if typeof(bonus.serial) ~= "number" or bonus.serial ~= currentSerial then
			return -- an old shot's late settlement; not this flight's verdict
		end
		bonusDeadline = nil
		shotToken += 1 -- the shot has fully answered; no watchdog may reclaim it

		best = math.max(bonus.best or 0, best)
		bestLabel.Text = ("🏆 Best  %s Studs"):format(Format.abbreviate(math.floor(best)))

		summary.title.Text = bonus.record and "NEW BEST!" or "Landed!"
		summaryDistance.Text = ("%s Studs"):format(Format.abbreviate(math.floor(bonus.distance or 0)))

		-- The label lives on a card; hiding the label alone leaves an empty
		-- coloured bar, so the CARD is what toggles.
		local cash = bonus.cash or 0
		coinRow.Text = ("💵  +%s Cash"):format(Format.abbreviate(cash));
		(coinRow.Parent :: Frame).Visible = cash > 0

		local bounty = bonus.milestoneCash or 0
		bountyRow.Text = ("🏁  +%s Bounty!"):format(Format.abbreviate(bounty));
		(bountyRow.Parent :: Frame).Visible = bounty > 0

		-- What the steering actually did, in counts a kid can read.
		local pickups = bonus.pickups or 0
		local boots = bonus.boots or 0
		local bombs = bonus.bombs or 0
		skillRow.Text = ("🎯  %d cash grab%s · %d boost%s%s"):format(
			pickups,
			pickups == 1 and "" or "s",
			boots,
			boots == 1 and "" or "s",
			bombs > 0 and ("  · %d 💣"):format(bombs) or ""
		);
		(skillRow.Parent :: Frame).Visible = (pickups + boots + bombs) > 0

		-- The multiplier breakdown: what each part of the account actually
		-- contributed, so an upgrade's effect is visible rather than felt.
		local lines = {
			("%d bounce%s   ·   rebirth ×%d"):format(
				bonus.bounces or 0,
				(bonus.bounces or 0) == 1 and "" or "s",
				bonus.rebirths or 0
			),
			("cash ×%.2f   ·   collection ×%.2f"):format(bonus.coinMultiplier or 1, bonus.collectionBonus or 1),
		}
		local milestones = bonus.milestones or {}
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

		-- The flight's earnings fly home: bills stream from the summary
		-- into the wallet, where the number actually changes.
		Cannon.collectCash(cash + bounty)
	end)

	-- ---------- the server's launch answer ----------
	-- Momentum, physics and a track seed — no distance, no payout. The
	-- flight goes where the player keeps it going; the settlement above is
	-- where the numbers come back.
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

		if typeof(result.seed) ~= "number" or typeof(result.vx) ~= "number" then
			return
		end
		-- A real answer arrived: disarm the fire watchdog, hand the landing
		-- watch a clean slate, and fly.
		shotToken += 1
		bonusDeadline = nil
		currentSerial = if typeof(result.serial) == "number" then result.serial else -1
		Flight.play(result)
	end)

	-- ---------- cooldown and record, straight from the server ----------
	function Launch.setReadyIn(seconds: number)
		readyIn = math.max(seconds, 0)
	end

	function Launch.setBest(distance: number)
		best = math.max(distance, 0)
		bestLabel.Text = ("🏆 Best  %s Studs"):format(Format.abbreviate(math.floor(best)))
	end

	-- The server's launchPower, straight from sync: what decides whether
	-- aiming is the needle or the rhythm duel, and how fast the ring flies.
	function Launch.setPower(power: number)
		launchPower = math.max(power or 0, 0)
	end

	function Launch.setNearCannon(near: boolean)
		if near == nearCannon then
			return
		end
		nearCannon = near
		-- Walking off mid-aim abandons the aim rather than leaving half the
		-- taps locked. A shot already in the air is left alone.
		if not near and stage == "aim" then
			setStage("idle")
		else
			setStage(stage)
		end
	end

	-- The prompt's own activation: skip straight past "idle" into the meter,
	-- so pressing E at the cannon starts aiming rather than only revealing a
	-- button that then has to be pressed as well.
	function Launch.open()
		if not nearCannon or stage ~= "idle" or readyIn > 0 then
			return
		end
		beginAiming()
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
