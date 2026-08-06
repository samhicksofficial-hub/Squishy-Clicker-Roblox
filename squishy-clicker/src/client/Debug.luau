--!strict
-- ============================================================
--  DEBUG MENU  —  test everything without grinding for it.
--
--  This whole module is inert unless the server created the
--  DebugAction remote, which it only does in Studio (or for the
--  UserIds allowlisted in Config). In a published game the remote
--  is absent, mount() gives up, and no menu is ever built.
--
--  Every button that changes data goes through the server, so
--  what you are testing is the real code path — not a client-side
--  puppet show that works differently from the live game.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Squishies = require(Shared:WaitForChild("Squishies"))

local Debug = {}

local COLOR = {
	panel = Color3.fromRGB(28, 30, 38),
	row = Color3.fromRGB(44, 47, 58),
	text = Color3.fromRGB(238, 240, 246),
	dim = Color3.fromRGB(150, 156, 172),
	accent = Color3.fromRGB(120, 200, 255),
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

-- scene is Scene.luau; kept untyped to avoid a circular require just for types.
function Debug.mount(gui: GuiObject, scene: any)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	-- Timed wait: returns nil in a published game instead of hanging forever.
	local action = remotes:WaitForChild("DebugAction", 8) :: RemoteEvent?
	if not action then
		return
	end
	local fire = action

	local toggle = make("TextButton", {
		Name = "DebugToggle",
		Size = UDim2.new(0, 104, 0, 38),
		Position = UDim2.new(0, 376, 0, 20),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		Text = "🐛 Debug",
		TextColor3 = COLOR.text,
		TextSize = 15,
		ZIndex = 40,
		Parent = gui,
	})
	corner(10, toggle)

	local panel = make("Frame", {
		Name = "DebugPanel",
		Size = UDim2.new(0, 320, 0, 580),
		Position = UDim2.new(0, 376, 0, 66),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.06,
		Active = true, -- swallow taps so the menu never clicks the squisher
		Visible = false,
		ZIndex = 40,
		Parent = gui,
	})
	corner(14, panel)

	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Debug  ·  Studio only",
		TextColor3 = COLOR.dim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
		Parent = panel,
	})

	-- ---------- quick actions ----------
	-- Two columns of 32px rows with 8px gaps; the height has to be an exact
	-- number of those or the last row is clipped. Nine rows = 18 buttons.
	local grid = make("Frame", {
		Size = UDim2.new(1, -16, 0, 352),
		Position = UDim2.new(0, 8, 0, 32),
		BackgroundTransparency = 1,
		ZIndex = 41,
		Parent = panel,
	})
	make("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, 32),
		CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local function quickButton(order: number, text: string, onClick: () -> ())
		local button = make("TextButton", {
			BackgroundColor3 = COLOR.row,
			AutoButtonColor = true,
			Font = Enum.Font.GothamMedium,
			Text = text,
			TextColor3 = COLOR.text,
			TextSize = 13,
			LayoutOrder = order,
			ZIndex = 41,
			Parent = grid,
		})
		corner(8, button)
		button.Activated:Connect(onClick)
	end

	quickButton(1, "+1 Steamer", function()
		fire:FireServer("bank", 1)
	end)
	quickButton(2, "+10 Steamers", function()
		fire:FireServer("bank", 10)
	end)
	quickButton(3, "Fill Bar", function()
		fire:FireServer("fillBar")
	end)
	quickButton(4, "+5 of Each", function()
		fire:FireServer("giveAll", 5)
	end)
	quickButton(5, "Max All Stars", function()
		fire:FireServer("maxStars")
	end)
	quickButton(6, "Reset Save", function()
		fire:FireServer("reset")
	end)
	quickButton(14, "Ready Cannon", function()
		fire:FireServer("readyCannon")
	end)
	-- The cannon's progression takes hours to walk through honestly, so these
	-- three drop you at each of its interesting screens directly.
	quickButton(16, "Rich Cannon", function()
		fire:FireServer("richCannon")
	end)
	quickButton(17, "+10 Power", function()
		fire:FireServer("powerUp", 10)
	end)
	quickButton(18, "Ready Rebirth", function()
		fire:FireServer("readyRebirth")
	end)

	local backdropFaded = true
	quickButton(7, "View: Steamer", function()
		scene.setView("unbox")
	end)
	-- (The old "View: Range" button is gone with the diorama valley it looked
	-- at: the range is the real world now, reached by walking.)
	quickButton(8, "Toggle Blur", function()
		backdropFaded = not backdropFaded
		scene.setBackdropFaded(backdropFaded)
	end)
	-- These three print the shape they changed, so the value can be written
	-- into the right MESH_SHAPES entry without having to remember what was
	-- equipped at the time.
	local function notMesh(shape: string?)
		print(
			("[SquishyClicker] '%s' is a built-in shape — only imported meshes need aiming."):format(shape or "dumpling")
		)
	end

	quickButton(9, "Rotate Clicker", function()
		local yaw, shape = scene.rotateClicker()
		if yaw then
			print(("[SquishyClicker] %s: yaw = %d — write it into MESH_SHAPES in Models.luau."):format(shape, yaw))
		else
			notMesh(shape)
		end
	end)
	quickButton(13, "Tilt Clicker", function()
		local pitch, shape = scene.tiltClicker()
		if pitch then
			print(("[SquishyClicker] %s: pitch = %d — write it into MESH_SHAPES in Models.luau."):format(shape, pitch))
		else
			notMesh(shape)
		end
	end)

	quickButton(10, "Raise Clicker", function()
		local offset, shape = scene.nudgeClicker(Vector3.new(0, 0.1, 0))
		if offset then
			print(
				("[SquishyClicker] %s: offset = Vector3.new(%.2f, %.2f, %.2f) — write it into MESH_SHAPES."):format(
					shape,
					offset.X,
					offset.Y,
					offset.Z
				)
			)
		else
			notMesh(shape)
		end
	end)
	-- Every importable thing sitting in ReplicatedStorage, so a newly added
	-- model's exact name can be read off rather than guessed at. Names are
	-- what MESH_SHAPES matches on, and they are case and space sensitive.
	quickButton(12, "List Meshes", function()
		print("[SquishyClicker] Mesh templates in ReplicatedStorage:")
		local found = 0
		for _, descendant in ReplicatedStorage:GetDescendants() do
			if descendant:IsA("MeshPart") or descendant:IsA("Model") then
				found += 1
				local parent = descendant.Parent
				print(("   %q [%s] in %q"):format(descendant.Name, descendant.ClassName, parent and parent.Name or "?"))
			end
		end
		if found == 0 then
			print("   nothing — imported models need to live in ReplicatedStorage.")
		end
	end)

	quickButton(11, "Lower Clicker", function()
		local offset, shape = scene.nudgeClicker(Vector3.new(0, -0.1, 0))
		if offset then
			print(
				("[SquishyClicker] %s: offset = Vector3.new(%.2f, %.2f, %.2f) — write it into MESH_SHAPES."):format(
					shape,
					offset.X,
					offset.Y,
					offset.Z
				)
			)
		else
			notMesh(shape)
		end
	end)

	-- ---------- force a reveal ----------
	make("TextLabel", {
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.new(0, 8, 0, 390),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Force reveal (also grants a copy)",
		TextColor3 = COLOR.dim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
		Parent = panel,
	})

	local list = make("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -420),
		Position = UDim2.new(0, 8, 0, 412),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 41,
		Parent = panel,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = list,
	})

	-- Same Common-to-Mythical ordering as the collection panel, so the two
	-- lists read the same way.
	local rarityTier: { [string]: number } = {}
	for index, rarity in Squishies.rarities do
		rarityTier[rarity.name] = index
	end

	for index, squishy in Squishies.list do
		local rarity = Squishies.rarityByName[squishy.rarity]
		local tier = rarityTier[squishy.rarity] or 1

		local row = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = COLOR.row,
			AutoButtonColor = true,
			Font = Enum.Font.GothamMedium,
			Text = "",
			LayoutOrder = tier * 1000 + index,
			ZIndex = 41,
			Parent = list,
		})
		corner(6, row)

		make("Frame", { -- rarity colour chip
			Size = UDim2.new(0, 16, 0, 16),
			Position = UDim2.new(0, 7, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = squishy.color,
			BorderSizePixel = 0,
			ZIndex = 42,
			Parent = row,
		})

		make("TextLabel", {
			Size = UDim2.new(1, -80, 1, 0),
			Position = UDim2.new(0, 30, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = squishy.name,
			TextColor3 = COLOR.text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 42,
			Parent = row,
		})

		make("TextLabel", {
			Size = UDim2.new(0, 68, 1, 0),
			Position = UDim2.new(1, -72, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = squishy.shape or "dumpling",
			TextColor3 = rarity and rarity.color or COLOR.accent,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 42,
			Parent = row,
		})

		local id = squishy.id
		row.Activated:Connect(function()
			-- Swing to the steamer first, exactly like a real unbox.
			scene.setView("unbox")
			task.delay(0.55, function()
				fire:FireServer("forceOpen", id)
			end)
		end)
	end

	-- ---------- open / close ----------
	local function setOpen(open: boolean)
		panel.Visible = open
		toggle.Text = open and "🐛 Close" or "🐛 Debug"
	end

	toggle.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F2 then
			setOpen(not panel.Visible)
		end
	end)

	print("[SquishyClicker] Debug menu ready (F2).")
end

return Debug
