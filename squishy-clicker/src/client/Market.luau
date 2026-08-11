--!strict
-- ============================================================
--  SQUISHY MARKET  —  the browsing menu behind the plaza stalls.
--
--  Walk up to any market stall and this opens: the full catalog
--  filed into category drawers (Dumplings, Fruits, ...), with a
--  detail card per squishy — stars, copies toward the next star,
--  and the cannon buffs it grants while summoned — plus the
--  MY SQUISHY TEAM strip up top showing the three slots.
--
--  Pure viewing glass over the server's numbers: the only remotes
--  it ever fires are SetActive (add to / drop from the team) and
--  SetClicker (make it the MAIN squisher), and the server re-checks
--  ownership and the slot limit regardless. Copies, stars and buffs
--  are all read from the same SyncData snapshot the collection
--  panel draws from.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Models = require(script.Parent:WaitForChild("Models"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Squishies = require(Shared:WaitForChild("Squishies"))

local Market = {}

-- Dark ink for light cards, same scheme as the collection panel: the HUD's
-- white-with-outline text is exactly wrong on a pale background.
local INK = Color3.fromRGB(74, 52, 38)
local INK_SOFT = Color3.fromRGB(150, 130, 118)
local CARD = Color3.fromRGB(252, 248, 244)
local GOLD = Color3.fromRGB(255, 199, 92)
local LOCKED = Color3.fromRGB(228, 222, 216)
local RING = Color3.fromRGB(70, 200, 60)
local UNDISCOVERED = Color3.fromRGB(90, 82, 76)

-- Rarity rank (Common = 1 ... Mythical = 6): the number every cannon buff
-- scales from, mirroring the server's rarityRank.
local rarityRank: { [string]: number } = {}
for index, rarity in Squishies.rarities do
	rarityRank[rarity.name] = index
end

-- The latest SyncData snapshot, or safe emptiness before the first one.
local latest: any = { counts = {}, stars = {}, active = {} }

-- Set by mount; open() and update() stay harmless no-ops before then.
local root: Frame? = nil
local rerender: () -> () = function() end

function Market.mount(gui: GuiObject)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local SetActive = Remotes:WaitForChild("SetActive") :: RemoteEvent
	local SetClicker = Remotes:WaitForChild("SetClicker") :: RemoteEvent

	local Z = 30 -- above the nav-rail panels, which sit in the low twenties

	local panel = UI.panel({
		parent = gui,
		name = "SquishyMarket",
		size = UDim2.new(0, 780, 0, 560),
		position = UDim2.new(0.5, 0, 0.5, 0),
		icon = "🥟",
		title = "SQUISHY MARKET",
		top = UI.color.pink,
		bottom = UI.color.pinkDeep,
		zIndex = Z,
	})
	root = panel.root

	local selectedCategory: string = Squishies.categories[1]
	local selectedId: string? = nil

	-- The detail stage's spin — the squishy sits on a cushion you can grab
	-- and turn, same toy language as the squisher on its cushion. Persistent
	-- across re-renders so a server sync doesn't snap it back to front-face.
	local spin = {
		angle = 0,
		velocity = 0.6,
		dragging = false,
		lastX = 0,
		model = nil :: any,
		lift = 0,
		scale = 1,
	}

	-- The squishy's real 3D model in a round swatch — one recipe for the team
	-- squares, the grid cards and the detail portrait.
	local function buildPreview(parent: Instance, squishy: Squishies.Squishy, zIndex: number)
		local viewport = UI.make("ViewportFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(170, 165, 160),
			LightColor = Color3.fromRGB(255, 250, 244),
			LightDirection = Vector3.new(-0.5, -1, -0.6),
			ZIndex = zIndex,
			Parent = parent,
		}) :: ViewportFrame
		local stage = UI.make("Folder", { Name = "Model", Parent = viewport })
		local model = Models.buildSquishy(stage, squishy.shape, squishy.color, squishy.sparkle, squishy.scale)
		Models.apply(model.rig, CFrame.identity, Vector3.one * model.sizeScale)
		local camera = Instance.new("Camera")
		camera.FieldOfView = 28
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.9, 8), Vector3.zero)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
	end

	local function inkLabel(props: { [string]: any }): TextLabel
		local defaults: { [string]: any } = {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextColor3 = INK,
			TextStrokeTransparency = 1,
			TextSize = 13,
		}
		for key, value in props do
			defaults[key] = value
		end
		return UI.make("TextLabel", defaults) :: TextLabel
	end

	local function starString(stars: number): string
		return string.rep("★", stars) .. string.rep("☆", Config.MaxStars - stars)
	end

	-- Copies needed for the next star — mirrors the server's prestige math
	-- for display only; the server recomputes it when anyone actually pays.
	local function prestigeCost(squishy: Squishies.Squishy, currentStar: number): number
		local rarity = Squishies.rarityByName[squishy.rarity]
		if not rarity then
			return math.huge
		end
		return rarity.baseCopies * (Config.PrestigeGrowth ^ currentStar)
	end

	-- ---------- MY SQUISHY TEAM ----------
	UI.label({
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 6),
		Text = "MY SQUISHY TEAM",
		TextSize = 22,
		ZIndex = Z + 2,
		Parent = panel.body,
	})

	local teamStrip = UI.make("Frame", {
		Size = UDim2.new(0, 3 * 96 + 2 * 18, 0, 96),
		Position = UDim2.new(0.5, 0, 0, 34),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = Z + 2,
		Parent = panel.body,
	}) :: Frame
	UI.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = teamStrip,
	})

	-- The three squares double as DROP TARGETS for the drag below. Rebuilt
	-- with the strip on every sync, so the list is re-registered each pass.
	local teamSlots: { { button: TextButton, id: string? } } = {}

	local function rebuildTeam()
		for _, child in teamStrip:GetChildren() do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		table.clear(teamSlots)

		local active: { string } = latest.active or {}
		for slot = 1, Config.MaxActiveSquishies do
			local id = active[slot]
			local squishy = id and Squishies.byId[id]

			local square = UI.make("TextButton", {
				Size = UDim2.new(0, 96, 0, 96),
				BackgroundColor3 = squishy and squishy.color or LOCKED,
				AutoButtonColor = squishy ~= nil,
				ClipsDescendants = true,
				Font = Enum.Font.FredokaOne,
				Text = squishy and "" or "+",
				TextColor3 = INK_SOFT,
				TextSize = 40,
				LayoutOrder = slot,
				ZIndex = Z + 2,
				Parent = teamStrip,
			}) :: TextButton
			UI.corner(16, square)
			UI.stroke(square, 3, squishy and RING or UI.color.ink)

			if squishy then
				buildPreview(square, squishy, Z + 3)
				inkLabel({
					Size = UDim2.new(1, 0, 0, 26),
					Position = UDim2.new(0, 0, 1, -26),
					BackgroundTransparency = 0.25,
					BackgroundColor3 = CARD,
					Text = squishy.name,
					TextSize = 11,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = Z + 4,
					Parent = square,
				})
				square.Activated:Connect(function()
					SetActive:FireServer(squishy.id, false)
				end)
			end

			table.insert(teamSlots, { button = square, id = id })
		end
	end

	-- ---------- drag to team ----------
	-- The ADD TO TEAM button works, but dragging a face onto a team square is
	-- what hands expect. A press starts a watch; travelling ~10 pixels turns
	-- it into a real drag with a floating copy under the pointer; releasing
	-- over a team square summons the squishy — swapping out the occupant if
	-- the square was taken. A press that never travels stays a click and
	-- selects the card exactly as before.
	local dragState: { squishy: Squishies.Squishy, ghost: Frame?, fromX: number?, fromY: number? }? = nil

	local function pointOver(object: GuiObject, x: number, y: number): boolean
		local corner = object.AbsolutePosition
		local size = object.AbsoluteSize
		return x >= corner.X and x <= corner.X + size.X and y >= corner.Y and y <= corner.Y + size.Y
	end

	-- The hovered square glows gold while a drag is over it; passing nil
	-- restores every square to its resting stroke.
	local function paintSlotTargets(x: number?, y: number?)
		for _, slot in teamSlots do
			local stroke = slot.button:FindFirstChildOfClass("UIStroke")
			if stroke then
				local over = x ~= nil and y ~= nil and pointOver(slot.button, x, y)
				stroke.Thickness = over and 5 or 3
				stroke.Color = over and GOLD or (slot.id and RING or UI.color.ink)
			end
		end
	end

	local function beginDrag(squishy: Squishies.Squishy)
		dragState = { squishy = squishy }
	end

	UserInputService.InputChanged:Connect(function(input)
		local drag = dragState
		if not drag then
			return
		end
		if
			input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		local x, y = input.Position.X, input.Position.Y
		-- The baseline is the first move after the press, measured in the
		-- same coordinate space as every later move — button-event and
		-- input-event coordinates don't reliably share an origin.
		local fromX, fromY = drag.fromX, drag.fromY
		if not fromX or not fromY then
			drag.fromX, drag.fromY = x, y
			return
		end
		local ghost = drag.ghost
		if not ghost then
			if math.abs(x - fromX) + math.abs(y - fromY) < 10 then
				return
			end
			ghost = UI.make("Frame", {
				Size = UDim2.new(0, 64, 0, 64),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = drag.squishy.color,
				ClipsDescendants = true,
				ZIndex = Z + 10,
				Parent = gui,
			}) :: Frame
			UI.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ghost })
			UI.stroke(ghost, 3, RING)
			buildPreview(ghost, drag.squishy, Z + 11)
			drag.ghost = ghost
		end
		-- Root-relative: input coordinates live in the inset-adjusted space,
		-- while the ghost's offsets are in the inset-IGNORING root's — used
		-- raw, the ghost trails a topbar's height below the finger.
		local rootAt = gui.AbsolutePosition
		ghost.Position = UDim2.fromOffset(x - rootAt.X, y - rootAt.Y)
		paintSlotTargets(x, y)
	end)

	-- The idle turn, the drag's momentum, and the ease back to idle — one
	-- loop drives whichever stage model is currently up.
	RunService.RenderStepped:Connect(function(dt)
		local model = spin.model
		if not model then
			return
		end
		if not spin.dragging then
			spin.velocity += (0.6 - spin.velocity) * math.min(dt * 1.2, 1)
			spin.angle += spin.velocity * dt
		end
		Models.apply(
			model.rig,
			CFrame.new(0, spin.lift, 0) * CFrame.Angles(0, spin.angle, 0),
			Vector3.one * spin.scale
		)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end
		-- Every release lets go of the cushion too.
		spin.dragging = false
		local drag = dragState
		dragState = nil
		if not drag then
			return
		end
		paintSlotTargets(nil, nil)
		local ghost = drag.ghost
		if not ghost then
			return -- never travelled: the card's own tap handler has it
		end
		ghost:Destroy()

		local x, y = input.Position.X, input.Position.Y
		for _, slot in teamSlots do
			if pointOver(slot.button, x, y) then
				-- Dropping on a taken square swaps: the occupant steps down,
				-- the dragged one steps in. The server re-checks ownership
				-- and the slot limit on both, as it does for every request.
				if slot.id ~= drag.squishy.id then
					if slot.id then
						SetActive:FireServer(slot.id, false)
					end
					SetActive:FireServer(drag.squishy.id, true)
				end
				break
			end
		end
	end)

	-- The collection's permanent cash bonus, right where new squishies are
	-- browsed: the standing answer to "why buy another steamer".
	local collectionLabel = UI.label({
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 132),
		Text = "",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(198, 244, 158),
		ZIndex = Z + 2,
		Parent = panel.body,
	})

	-- ---------- category tabs ----------
	local tabRow = UI.make("Frame", {
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.new(0, 8, 0, 148),
		BackgroundTransparency = 1,
		ZIndex = Z + 2,
		Parent = panel.body,
	}) :: Frame
	UI.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabRow,
	})

	local tabButtons: { [string]: UI.Button } = {}
	local function paintTabs()
		for category, entry in tabButtons do
			local picked = category == selectedCategory
			entry.button.BackgroundColor3 = picked and UI.color.orange or UI.color.blue
			entry.stroke.Thickness = picked and 4 or 3
		end
	end

	-- ---------- the grid and the detail pane ----------
	local grid = UI.make("ScrollingFrame", {
		Size = UDim2.new(1, -296, 1, -198),
		Position = UDim2.new(0, 8, 0, 190),
		BackgroundColor3 = UI.color.bodyDark,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = Z + 2,
		Parent = panel.body,
	}) :: ScrollingFrame
	UI.corner(12, grid)

	local detail = UI.make("ScrollingFrame", {
		Size = UDim2.new(0, 272, 1, -198),
		Position = UDim2.new(1, -8, 0, 190),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = CARD,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = Z + 2,
		Parent = panel.body,
	}) :: ScrollingFrame
	UI.corner(12, detail)
	UI.make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = detail,
	})
	UI.make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		Parent = detail,
	})

	local function renderDetail()
		-- The old stage is about to be destroyed with the rest of the pane;
		-- the spin loop must not keep applying CFrames to a dead rig.
		spin.model = nil
		for _, child in detail:GetChildren() do
			if not (child:IsA("UIListLayout") or child:IsA("UIPadding")) then
				child:Destroy()
			end
		end

		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		local squishy = selectedId and Squishies.byId[selectedId]
		if not squishy then
			inkLabel({
				Size = UDim2.new(1, -20, 0, 60),
				Text = "Tap a squishy to inspect it",
				TextColor3 = INK_SOFT,
				TextWrapped = true,
				LayoutOrder = nextOrder(),
				ZIndex = Z + 3,
				Parent = detail,
			})
			return
		end

		local held = (latest.counts and latest.counts[squishy.id]) or 0
		local star = (latest.stars and latest.stars[squishy.id]) or 0
		local discovered = held > 0 or star > 0
		local rarity = Squishies.rarityByName[squishy.rarity]

		if discovered then
			-- The squishy on its display cushion, LIVE: grab and drag to
			-- spin it, let go and it keeps your spin before settling into a
			-- lazy idle turn — the same toy language as the squisher on its
			-- cushion in the shop.
			local stageFrame = UI.make("ViewportFrame", {
				Size = UDim2.new(1, -20, 0, 168),
				BackgroundColor3 = Color3.fromRGB(250, 244, 238),
				Ambient = Color3.fromRGB(170, 165, 160),
				LightColor = Color3.fromRGB(255, 250, 244),
				LightDirection = Vector3.new(-0.5, -1, -0.6),
				Active = true, -- the drag must not scroll the pane under it
				LayoutOrder = nextOrder(),
				ZIndex = Z + 3,
				Parent = detail,
			}) :: ViewportFrame
			UI.corner(12, stageFrame)
			if rarity then
				UI.stroke(stageFrame, 3, rarity.color)
			end

			local stageModels = UI.make("Folder", { Name = "Model", Parent = stageFrame })

			local cushion = Instance.new("Part")
			cushion.Shape = Enum.PartType.Cylinder
			cushion.Size = Vector3.new(0.44, 3.9, 3.9)
			cushion.CFrame = CFrame.new(0, -0.22, 0) * CFrame.Angles(0, 0, math.pi / 2)
			cushion.Color = Color3.fromRGB(240, 205, 212)
			cushion.Material = Enum.Material.Fabric
			cushion.Anchored = true
			cushion.Parent = stageModels

			local preview = Models.buildSquishy(stageModels, squishy.shape, squishy.color, squishy.sparkle, squishy.scale)
			spin.model = preview
			spin.lift = -preview.lowestY * preview.sizeScale
			spin.scale = preview.sizeScale
			Models.apply(
				preview.rig,
				CFrame.new(0, spin.lift, 0) * CFrame.Angles(0, spin.angle, 0),
				Vector3.one * preview.sizeScale
			)

			-- The camera frames the model's REAL bounds rather than sitting at
			-- a fixed seat: the fixed seat was tuned on a dumpling, and every
			-- taller squishy since lost its head off the top of the window.
			local top, radius = 1.6, 2
			for _, part in stageModels:GetDescendants() do
				if part:IsA("BasePart") and part ~= cushion then
					local half = part.Size * 0.5
					top = math.max(top, part.Position.Y + half.Y)
					radius = math.max(
						radius,
						math.abs(part.Position.X) + half.X,
						math.abs(part.Position.Z) + half.Z
					)
				end
			end
			-- Vertical half-extent from cushion bottom to crown, plus a
			-- breath of margin; the distance that fits it in a 32° lens.
			local halfSpan = math.max((top + 0.5) * 0.5 + 0.5, radius * 0.55)
			local centreY = (top - 0.5) * 0.5
			local distance = halfSpan / math.tan(math.rad(16))
			local camera = Instance.new("Camera")
			camera.FieldOfView = 32
			camera.CFrame = CFrame.lookAt(
				Vector3.new(0, centreY + distance * 0.24, distance),
				Vector3.new(0, centreY, 0)
			)
			camera.Parent = stageFrame
			stageFrame.CurrentCamera = camera

			stageFrame.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					spin.dragging = true
					spin.lastX = input.Position.X
					spin.velocity = 0
				end
			end)
			stageFrame.InputChanged:Connect(function(input)
				if not spin.dragging then
					return
				end
				if
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				then
					local dx = input.Position.X - spin.lastX
					spin.lastX = input.Position.X
					spin.angle += dx * 0.012
					-- Remembered as momentum, so a flick keeps it turning.
					spin.velocity = dx * 0.7
				end
			end)

			inkLabel({
				Size = UDim2.new(1, -20, 0, 12),
				Text = "↻ drag to spin",
				TextColor3 = INK_SOFT,
				TextSize = 10,
				LayoutOrder = nextOrder(),
				ZIndex = Z + 3,
				Parent = detail,
			})
		else
			local portrait = UI.make("Frame", {
				Size = UDim2.new(0, 104, 0, 104),
				BackgroundColor3 = UNDISCOVERED,
				ClipsDescendants = true,
				LayoutOrder = nextOrder(),
				ZIndex = Z + 3,
				Parent = detail,
			}) :: Frame
			UI.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = portrait })
			if rarity then
				UI.stroke(portrait, 4, rarity.color)
			end
			inkLabel({
				Size = UDim2.fromScale(1, 1),
				Font = Enum.Font.FredokaOne,
				Text = "?",
				TextColor3 = CARD,
				TextSize = 40,
				ZIndex = Z + 4,
				Parent = portrait,
			})
		end

		inkLabel({
			Size = UDim2.new(1, -20, 0, 24),
			Text = squishy.name,
			TextSize = 20,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})
		inkLabel({
			Size = UDim2.new(1, -20, 0, 16),
			Text = squishy.rarity,
			TextColor3 = rarity and rarity.color or INK_SOFT,
			TextSize = 14,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})
		inkLabel({
			Size = UDim2.new(1, -20, 0, 18),
			Font = Enum.Font.GothamBold,
			Text = starString(star),
			TextColor3 = GOLD,
			TextSize = 16,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})

		-- One friendly line instead of two ledger rows: what you have, and
		-- how close that is to the next star.
		local copiesText
		if star >= Config.MaxStars then
			copiesText = ("You have x%d  ·  ★ MAX!"):format(held)
		else
			local cost = prestigeCost(squishy, star)
			copiesText = ("You have x%d  ·  %d / %d to a ★"):format(held, math.min(held, cost), cost)
		end
		inkLabel({
			Size = UDim2.new(1, -20, 0, 18),
			Text = copiesText,
			TextColor3 = INK_SOFT,
			TextSize = 13,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})

		-- ---------- cannon effects ----------
		-- The same math the server runs when this squishy is on the team:
		-- rarity rank times the per-rank rates, scaled up by its stars.
		inkLabel({
			Size = UDim2.new(1, -20, 0, 20),
			Font = Enum.Font.FredokaOne,
			Text = "CANNON EFFECTS",
			TextSize = 15,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})

		local rank = rarityRank[squishy.rarity] or 1

		-- The ability it grants as the MAIN squisher — the one that actually
		-- goes down the barrel. Same strength math the server uses.
		local strength = rank * (1 + star * Config.AbilityStarBonus)
		local function pct(perRank: number): number
			return math.floor(perRank * strength * 100 + 0.5)
		end
		local ability = squishy.ability
		local abilityText
		if ability == "slide" then
			abilityText = ("🧈 Slippery — shots slide %d%% further"):format(pct(Config.AbilitySlidePerRank))
		elseif ability == "bounce" then
			abilityText = ("🏀 Bouncy — bounces keep %d%% more height"):format(
				math.floor(Config.AbilityBouncePerRank * strength / Config.LaunchRestitution * 100 + 0.5)
			)
		elseif ability == "float" then
			abilityText = ("☁️ Floaty — %d%% less gravity in flight"):format(
				math.floor((1 - 1 / (1 + Config.AbilityFloatPerRank * strength)) * 100 + 0.5)
			)
		elseif ability == "wealth" then
			abilityText = ("🍰 Sweet — shot Cash +%d%%"):format(pct(Config.AbilityWealthPerRank))
		elseif ability == "magnet" then
			abilityText = ("🧠 Magnetic — pickup magnet +%.2f"):format(Config.AbilityMagnetPerRank * strength)
		else
			abilityText = ("💥 Cannonball — launch power +%d%%"):format(pct(Config.AbilityPowerPerRank))
		end
		inkLabel({
			Size = UDim2.new(1, -20, 0, 18),
			Text = abilityText,
			TextColor3 = GOLD,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})
		inkLabel({
			Size = UDim2.new(1, -20, 0, 12),
			Text = "when equipped as your main squisher",
			TextColor3 = INK_SOFT,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})

		local starred = 1 + star * Config.ActiveSquishyStarBonus
		local function percent(perRank: number): number
			return math.floor(rank * perRank * starred * 100 + 0.5)
		end
		local effects = {
			("🚀 Launch Power +%d%%"):format(percent(Config.ActiveSquishyPowerPerRank)),
			("💵 Cash Earned +%d%%"):format(percent(Config.ActiveSquishyCoinPerRank)),
			("🧲 Pickup Magnet +%.2f"):format(rank * Config.ActiveSquishyMagnetPerRank * starred),
		}
		for _, line in effects do
			inkLabel({
				Size = UDim2.new(1, -20, 0, 20),
				Text = line,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = nextOrder(),
				ZIndex = Z + 3,
				Parent = detail,
			})
		end
		inkLabel({
			Size = UDim2.new(1, -20, 0, 14),
			Text = "team boosts work while summoned",
			TextColor3 = INK_SOFT,
			TextSize = 11,
			LayoutOrder = nextOrder(),
			ZIndex = Z + 3,
			Parent = detail,
		})

		-- ---------- main-squisher button ----------
		-- The barrel'd squishy is picked HERE too, not only by tapping a
		-- face in the collection list: this card is where its cannon
		-- ability is being read, so the button belongs beside it. The
		-- server re-checks ownership like always.
		if discovered then
			local isMain = latest.clickerId == squishy.id
			local main = UI.button({
				parent = detail,
				size = UDim2.new(0, 240, 0, 40),
				text = isMain and "★ YOUR MAIN SQUISHY" or "★ MAKE MAIN SQUISHY",
				textSize = 16,
				top = UI.color.purple,
				bottom = UI.color.purpleDeep,
				zIndex = Z + 3,
			})
			main.button.LayoutOrder = nextOrder()
			if isMain then
				UI.setButtonEnabled(main, false, UI.color.purple, UI.color.purpleDeep)
			else
				main.button.Activated:Connect(function()
					SetClicker:FireServer(squishy.id)
				end)
			end
		end

		-- ---------- team button ----------
		if discovered then
			local summoned = false
			for _, activeId in (latest.active or {}) :: { string } do
				if activeId == squishy.id then
					summoned = true
				end
			end
			local slotsLeft = #(latest.active or {}) < Config.MaxActiveSquishies

			local action = UI.button({
				parent = detail,
				size = UDim2.new(0, 240, 0, 40),
				text = summoned and "REMOVE FROM TEAM" or "ADD TO TEAM",
				textSize = 17,
				top = summoned and UI.color.orange or UI.color.green,
				bottom = summoned and UI.color.orangeDeep or UI.color.greenDeep,
				zIndex = Z + 3,
			})
			action.button.LayoutOrder = nextOrder()
			if not summoned and not slotsLeft then
				action.button.Text = "TEAM IS FULL"
				UI.setButtonEnabled(action, false, UI.color.green, UI.color.greenDeep)
			else
				action.button.Activated:Connect(function()
					-- The server re-checks ownership and the three-slot limit;
					-- this is only the friendly path to asking.
					SetActive:FireServer(squishy.id, not summoned)
				end)
			end
		else
			inkLabel({
				Size = UDim2.new(1, -20, 0, 32),
				Text = "Not discovered yet — open steamers to find one!",
				TextColor3 = INK_SOFT,
				TextWrapped = true,
				LayoutOrder = nextOrder(),
				ZIndex = Z + 3,
				Parent = detail,
			})
		end
	end

	local function rebuildGrid()
		for _, child in grid:GetChildren() do
			child:Destroy()
		end
		UI.make("UIGridLayout", {
			CellSize = UDim2.new(0, 88, 0, 112),
			CellPadding = UDim2.new(0, 8, 0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = grid,
		})
		UI.make("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			Parent = grid,
		})

		for index, squishy in Squishies.list do
			if (squishy.category or "Oddities") ~= selectedCategory then
				continue
			end
			local held = (latest.counts and latest.counts[squishy.id]) or 0
			local star = (latest.stars and latest.stars[squishy.id]) or 0
			local discovered = held > 0 or star > 0
			local tier = rarityRank[squishy.rarity] or 1

			local card = UI.make("TextButton", {
				BackgroundColor3 = CARD,
				AutoButtonColor = true,
				Font = Enum.Font.FredokaOne,
				Text = "",
				-- Common → Mythical inside the drawer, catalog order within a tier.
				LayoutOrder = tier * 1000 + index,
				ZIndex = Z + 3,
				Parent = grid,
			}) :: TextButton
			UI.corner(12, card)
			if squishy.id == selectedId then
				UI.stroke(card, 3, GOLD)
			end

			local swatch = UI.make("Frame", {
				Size = UDim2.new(0, 60, 0, 60),
				Position = UDim2.new(0.5, 0, 0, 8),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = discovered and squishy.color or UNDISCOVERED,
				ClipsDescendants = true,
				ZIndex = Z + 4,
				Parent = card,
			}) :: Frame
			UI.make("UICorner", { CornerRadius = UDim.new(1, 0), Parent = swatch })
			-- Rarity ring: the rarity's colour around every face, so a drawer
			-- reads at a glance. Undiscovered ones keep it too — it is the
			-- tease of WHAT tier is hiding behind the question mark.
			local cardRarity = Squishies.rarityByName[squishy.rarity]
			if cardRarity then
				UI.stroke(swatch, 3, cardRarity.color)
			end
			if discovered then
				buildPreview(swatch, squishy, Z + 5)
			else
				inkLabel({
					Size = UDim2.fromScale(1, 1),
					Font = Enum.Font.FredokaOne,
					Text = "?",
					TextColor3 = CARD,
					TextSize = 24,
					ZIndex = Z + 5,
					Parent = swatch,
				})
			end

			inkLabel({
				Size = UDim2.new(1, -6, 0, 26),
				Position = UDim2.new(0, 3, 0, 70),
				Text = squishy.name,
				TextSize = 11,
				TextWrapped = true,
				ZIndex = Z + 4,
				Parent = card,
			})
			-- Only found squishies get a count line: on the unknowns the "?"
			-- already says everything, and 38 repeats of "not found" was most
			-- of what made the grid read as clutter.
			if discovered then
				inkLabel({
					Size = UDim2.new(1, -6, 0, 12),
					Position = UDim2.new(0, 3, 1, -14),
					Text = ("x%d  %s"):format(held, star > 0 and starString(star) or ""),
					TextColor3 = INK_SOFT,
					TextSize = 10,
					ZIndex = Z + 4,
					Parent = card,
				})
			end

			card.Activated:Connect(function()
				selectedId = squishy.id
				rebuildGrid()
				renderDetail()
			end)

			-- Press-and-drag onto a team square. Only discovered squishies:
			-- an unowned one has nothing to summon, so it doesn't lift.
			if discovered then
				card.MouseButton1Down:Connect(function()
					beginDrag(squishy)
				end)
			end
		end
	end

	for order, category in Squishies.categories do
		local tab = UI.button({
			parent = tabRow,
			size = UDim2.new(0, 116, 0, 34),
			text = category,
			textSize = 15,
			top = UI.color.blue,
			bottom = UI.color.blueDeep,
			zIndex = Z + 2,
			radius = 10,
		})
		tab.button.LayoutOrder = order
		tab.button.Activated:Connect(function()
			selectedCategory = category
			-- Selection doesn't chase the tab: the detail keeps showing the
			-- last inspected squishy until a new one is tapped.
			paintTabs()
			rebuildGrid()
		end)
		tabButtons[category] = tab
	end

	rerender = function()
		paintTabs()
		rebuildTeam()
		rebuildGrid()
		renderDetail()

		-- The server sends the finished multiplier; the discovered count is
		-- derived here purely for the wording.
		local discovered = 0
		for _, held in (latest.counts or {}) :: { [string]: number } do
			if held > 0 then
				discovered += 1
			end
		end
		for id, stars in (latest.stars or {}) :: { [string]: number } do
			if stars > 0 and ((latest.counts or {})[id] or 0) <= 0 then
				discovered += 1
			end
		end
		local bonus = math.floor(((latest.collectionBonus or 1) - 1) * 100 + 0.5)
		collectionLabel.Text = ("🎁 %d / %d found  ·  +%d%% Cash every shot"):format(discovered, #Squishies.list, bonus)
	end
end

-- Called from the client's refresh() with every SyncData snapshot. Cheap when
-- the menu is closed: the rebuild waits for open().
function Market.update(payload: any)
	if typeof(payload) == "table" then
		latest = payload
	end
	local frame = root
	if frame and frame.Visible then
		rerender()
	end
end

function Market.open()
	local frame = root
	if not frame then
		return
	end
	rerender()
	UI.popIn(frame)
end

return Market
