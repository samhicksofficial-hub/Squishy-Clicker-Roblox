--!strict
-- ============================================================
--  KING OF THE STEAMER  —  the shared minigame's panel.
--
--  A giant steamer everyone in the server clicks together. This
--  draws whatever the server broadcasts and sends bare "I
--  clicked" requests back; it never counts, never decides who
--  won, and never says what anyone should get.
--
--  The steamer is drawn in a ViewportFrame using the same model
--  the main stage uses, so the panel shows the real thing rather
--  than a picture of it.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Models = require(script.Parent:WaitForChild("Models"))

local King = {}

local COLOR = {
	panel = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(74, 52, 38),
	dim = Color3.fromRGB(150, 130, 118),
	track = Color3.fromRGB(238, 224, 212),
	fill = Color3.fromRGB(240, 140, 90),
	go = Color3.fromRGB(126, 224, 192),
	locked = Color3.fromRGB(228, 222, 216),
	gold = Color3.fromRGB(255, 199, 92),
	crown = Color3.fromRGB(226, 96, 96),
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

function King.mount(gui: GuiObject, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local clickRemote = remotes:WaitForChild("ClickShared") :: RemoteEvent
	local updateRemote = remotes:WaitForChild("KingUpdate") :: RemoteEvent
	local finishedRemote = remotes:WaitForChild("KingFinished") :: RemoteEvent

	-- ---------- panel ----------
	local panel = make("Frame", {
		Name = "KingPanel",
		Size = UDim2.new(0, 240, 0, 290),
		-- Left of centre, under the header. It shares the toy shop's screen
		-- with the collection panel on the right and the steamer bar below,
		-- and has to stay clear of both.
		Position = UDim2.new(0, 124, 0, 96),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.08,
		Active = true, -- its own taps, not the squisher's
		ZIndex = 4,
		Parent = gui,
	})
	corner(18, panel)

	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		Text = "👑 King of the Steamer",
		TextColor3 = COLOR.text,
		TextSize = 17,
		ZIndex = 5,
		Parent = panel,
	})

	-- The giant steamer itself, rendered from the real model.
	local viewport = make("ViewportFrame", {
		Size = UDim2.new(1, -16, 0, 92),
		Position = UDim2.new(0, 8, 0, 36),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 165, 160),
		LightColor = Color3.fromRGB(255, 250, 244),
		LightDirection = Vector3.new(-0.5, -1, -0.6),
		ZIndex = 5,
		Parent = panel,
	})

	local viewStage = make("Folder", { Name = "Steamer", Parent = viewport })
	local baseRig = Models.buildSteamerBase(viewStage)
	local lidRig = Models.buildSteamerLid(viewStage)
	Models.apply(baseRig, CFrame.new(0, -2.4, 0), Vector3.one)
	Models.apply(lidRig, CFrame.new(0, -0.25, 0), Vector3.one)

	local viewCamera = Instance.new("Camera")
	viewCamera.FieldOfView = 30
	viewCamera.CFrame = CFrame.lookAt(Vector3.new(0, 1.6, 15), Vector3.new(0, 0.2, 0))
	viewCamera.Parent = viewport
	viewport.CurrentCamera = viewCamera

	-- ---------- progress ----------
	local track = make("Frame", {
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.new(0, 8, 0, 136),
		BackgroundColor3 = COLOR.track,
		ZIndex = 5,
		Parent = panel,
	})
	corner(12, track)

	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = COLOR.fill,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = track,
	})
	corner(12, fill)

	local progressLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "0 / 60",
		TextColor3 = COLOR.text,
		TextSize = 13,
		ZIndex = 6,
		Parent = track,
	})

	local helpButton = make("TextButton", {
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.new(0, 8, 0, 168),
		BackgroundColor3 = COLOR.go,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = "HELP PUSH!",
		TextColor3 = COLOR.text,
		TextSize = 18,
		ZIndex = 5,
		Parent = panel,
	})
	corner(12, helpButton)

	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.new(0, 8, 0, 212),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Top helpers",
		TextColor3 = COLOR.dim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = panel,
	})

	local standingsList = make("Frame", {
		Size = UDim2.new(1, -16, 0, 70),
		Position = UDim2.new(0, 8, 0, 230),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = panel,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = standingsList,
	})

	-- Rows are reused rather than rebuilt: this redraws five times a second.
	local rows: { TextLabel } = {}
	for index = 1, 5 do
		rows[index] = make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 13),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = "",
			TextColor3 = COLOR.text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = index,
			Visible = false,
			ZIndex = 6,
			Parent = standingsList,
		})
	end

	helpButton.Activated:Connect(function()
		clickRemote:FireServer()
	end)

	-- The shared steamer belongs to the toy shop, not the valley: it is the
	-- clicker half's minigame, and leaving it up over the launcher was half of
	-- why that screen looked crowded.
	scene.onViewChanged(function(atValley)
		panel.Visible = not atValley
	end)

	-- ---------- the server's picture of the round ----------
	updateRemote.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end

		local clicks = snapshot.clicks or 0
		local goal = math.max(snapshot.goal or 1, 1)
		local active = snapshot.active ~= false

		progressLabel.Text = ("%d / %d"):format(clicks, goal)
		TweenService:Create(
			fill,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.new(math.clamp(clicks / goal, 0, 1), 0, 1, 0) }
		):Play()

		helpButton.Text = active and "HELP PUSH!" or "opening…"
		helpButton.BackgroundColor3 = active and COLOR.go or COLOR.locked
		helpButton.AutoButtonColor = active

		local standings = snapshot.standings or {}
		for index, row in rows do
			local entry = standings[index]
			row.Visible = entry ~= nil
			if entry then
				row.Text = ("%d. %s — %d"):format(index, entry.name, entry.clicks)
				row.TextColor3 = index == 1 and COLOR.crown or COLOR.text
			end
		end
	end)

	-- ---------- the winner announcement ----------
	finishedRemote.OnClientEvent:Connect(function(result)
		if typeof(result) ~= "table" then
			return
		end

		local banner = make("TextLabel", {
			Size = UDim2.new(0, 420, 0, 58),
			Position = UDim2.new(0.5, 0, 0, 96),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = COLOR.gold,
			Font = Enum.Font.FredokaOne,
			Text = result.winner ~= "" and ("👑 %s topped the steamer — got %s!"):format(result.winner, result.prize)
				or "👑 The steamer opened!",
			TextColor3 = COLOR.text,
			TextSize = 18,
			TextScaled = false,
			ZIndex = 25,
			Parent = gui,
		})
		corner(16, banner)

		banner.TextTransparency = 1
		banner.BackgroundTransparency = 1
		TweenService
			:Create(banner, TweenInfo.new(0.3), { TextTransparency = 0, BackgroundTransparency = 0.05 })
			:Play()

		task.delay(4, function()
			TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.delay(0.5, function()
				banner:Destroy()
			end)
		end)
	end)
end

return King
