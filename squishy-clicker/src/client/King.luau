--!strict
-- ============================================================
--  KING OF THE STEAMER  —  the shared event's presence in the
--  world.
--
--  The event happens ON the plaza, so its clock lives there too:
--  a sign floating over the middle of the island, readable from
--  every plot — counting down between rounds, counting clicks
--  during them. The old 2D panel sat on the steamer close-up,
--  which is the one page the event never happens on.
--
--  The only screen UI left is the HELP PUSH button while a round
--  is live (bottom centre — the launch button's spot, which is
--  free because launch controls only exist at your own cannon and
--  the round is at the plaza), and the winner banner.
--
--  This draws whatever the server broadcasts and sends bare "I
--  clicked" requests back; it never counts, never decides who
--  won, and never says what anyone should get. Standing on the
--  plaza is re-checked by the server on every click — the greyed
--  button here is a courtesy, not the rule.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent:WaitForChild("UI"))

local King = {}

local player = Players.LocalPlayer
local C = UI.color

-- Where the sign floats: over the plaza's centre, high enough to read from
-- the plots and low enough to sit under the flight paths.
local SIGN_POSITION = Vector3.new(0, 26, 0)

function King.mount(gui: GuiObject)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local clickRemote = remotes:WaitForChild("ClickShared") :: RemoteEvent
	local updateRemote = remotes:WaitForChild("KingUpdate") :: RemoteEvent
	local finishedRemote = remotes:WaitForChild("KingFinished") :: RemoteEvent

	-- ---------- the floating sign ----------
	local anchor = Instance.new("Part")
	anchor.Name = "KingSign"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = SIGN_POSITION
	anchor.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 380, 0, 128)
	-- Far enough to read from the plot ring; the diorama six thousand studs
	-- up never sees it, so the sign hides itself on the close-up pages.
	billboard.MaxDistance = 700
	billboard.Parent = anchor

	local function signLine(y: number, height: number, color: Color3): TextLabel
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, height)
		label.Position = UDim2.new(0, 0, 0, y)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = ""
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.fromRGB(48, 34, 28)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Parent = billboard
		return label
	end

	local titleLabel = signLine(0, 32, Color3.fromRGB(255, 214, 120))
	titleLabel.Text = "👑 King of the Steamer"
	local statusLabel = signLine(36, 52, Color3.fromRGB(255, 255, 255))
	local subLabel = signLine(94, 26, Color3.fromRGB(220, 240, 255))

	-- ---------- the push button ----------
	local push = UI.button({
		parent = gui,
		size = UDim2.new(0, 300, 0, 72),
		position = UDim2.new(0.5, 0, 1, -18),
		anchor = Vector2.new(0.5, 1),
		text = "👑 HELP PUSH!",
		textSize = 30,
		top = C.orange,
		bottom = C.orangeDeep,
		zIndex = 8,
		radius = 18,
	})
	push.button.Visible = false
	push.button.Activated:Connect(function()
		clickRemote:FireServer()
	end)

	-- ---------- state ----------
	-- The server's clocks win whenever a broadcast lands; between broadcasts
	-- they tick locally so the countdown moves smoothly.
	local plazaRadius = 58
	local onPlaza = false
	local roundActive = false
	local startsIn = 0
	local endsIn = 0
	local clicks, goal = 0, 60
	local topLine = ""

	local function redraw()
		if roundActive then
			statusLabel.Text = ("%d / %d   ·   %ds left"):format(clicks, goal, math.ceil(endsIn))
			subLabel.Text = topLine ~= "" and ("👑 %s"):format(topLine) or "PUSH! Everyone who helps gets a squishy!"
			push.button.Visible = true
			push.button.Text = onPlaza and "👑 HELP PUSH!" or "GO TO THE PLAZA!"
			UI.setButtonEnabled(push, onPlaza, C.orange, C.orangeDeep)
		else
			local wait = math.max(math.ceil(startsIn), 0)
			statusLabel.Text = if wait >= 60
				then ("Starts in %dm %02ds"):format(wait // 60, wait % 60)
				else ("Starts in %ds"):format(wait)
			subLabel.Text = "Be on the plaza when it opens — best helper wins the rarest roll"
			push.button.Visible = false
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		if roundActive then
			endsIn = math.max(endsIn - dt, 0)
		else
			startsIn = math.max(startsIn - dt, 0)
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		onPlaza = false
		if root then
			onPlaza = Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude <= plazaRadius
		end

		-- A slow bob, so the sign reads as part of the world rather than as a
		-- HUD element that wandered into it.
		anchor.Position = SIGN_POSITION + Vector3.new(0, math.sin(os.clock() * 1.2) * 0.6, 0)
		redraw()
	end)

	updateRemote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		roundActive = snapshot.active ~= false
		startsIn = snapshot.startsIn or 0
		endsIn = snapshot.endsIn or 0
		clicks = snapshot.clicks or 0
		goal = math.max(snapshot.goal or 1, 1)
		plazaRadius = snapshot.plazaRadius or plazaRadius

		topLine = ""
		local standings = snapshot.standings
		if typeof(standings) == "table" and standings[1] then
			topLine = ("%s — %d"):format(standings[1].name, standings[1].clicks)
		end
		redraw()
	end)

	-- ---------- announcements ----------
	-- The same remote carries the countdown callouts and the result, so there
	-- is one place a banner appears rather than two fighting for the spot.
	finishedRemote.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" then
			return
		end

		local message
		if result.countdown then
			local seconds = result.countdown
			message = if seconds >= 60
				then ("👑 King of the Steamer starts in %dm — get to the plaza!"):format(seconds // 60)
				else ("👑 King of the Steamer starts in %ds — get to the plaza!"):format(seconds)
		elseif result.winner ~= "" then
			message = ("👑 %s topped the steamer — got %s!"):format(result.winner, result.prize)
		else
			message = "👑 The steamer closed. Next round soon!"
		end

		local banner = UI.make("Frame", {
			Size = UDim2.new(0, 480, 0, 58),
			Position = UDim2.new(0.5, 0, 0, 96),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = result.countdown and C.pink or C.orange,
			ZIndex = 25,
			Parent = gui,
		})
		UI.corner(16, banner)
		UI.stroke(banner)

		UI.label({
			Size = UDim2.fromScale(1, 1),
			Text = message,
			TextSize = 20,
			ZIndex = 26,
			Parent = banner,
		})

		banner.BackgroundTransparency = 1
		TweenService:Create(banner, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
		task.delay(4, function()
			TweenService:Create(banner, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			for _, child in banner:GetDescendants() do
				if child:IsA("TextLabel") then
					TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
						:Play()
				elseif child:IsA("UIStroke") then
					TweenService:Create(child, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				end
			end
			task.delay(0.5, function()
				banner:Destroy()
			end)
		end)
	end)
end

return King
