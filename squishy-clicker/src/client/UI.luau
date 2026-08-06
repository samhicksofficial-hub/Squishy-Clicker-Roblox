--!strict
-- ============================================================
--  UI KIT  —  the chunky cartoon look, in one place.
--
--  Every panel in the game is built from these five or six
--  functions, so the style lives here rather than being re-typed
--  (and re-guessed) in every file. Change a stroke width or a
--  header gradient once and the whole game follows.
--
--  The look is the Roblox-simulator house style: heavy dark
--  outlines on everything, a saturated gradient header bar with
--  an icon on the left and a red X on the right, a warm embossed
--  body, and text that is always bold with a dark outline so it
--  stays readable against the 3D stage behind it.
--
--  Two rules worth knowing before adding to this:
--
--  * Strokes are ApplyStrokeMode.Border and scale with the panel,
--    so a small button and a big panel read as the same weight.
--  * Nothing here creates a ScreenGui or parents itself anywhere
--    by default. Callers pass a parent; the kit only builds.
-- ============================================================

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local UI = {}

-- The palette. Anything picking a colour should pick it from here, so a
-- retheme is one table rather than a search across five files.
UI.color = {
	ink = Color3.fromRGB(58, 38, 28), -- outlines and body text
	paper = Color3.fromRGB(255, 255, 255),
	body = Color3.fromRGB(196, 124, 54), -- the warm panel interior
	bodyDark = Color3.fromRGB(168, 100, 40),
	row = Color3.fromRGB(120, 74, 34),

	blue = Color3.fromRGB(88, 186, 246),
	blueDeep = Color3.fromRGB(52, 140, 226),
	orange = Color3.fromRGB(250, 178, 60),
	orangeDeep = Color3.fromRGB(238, 132, 36),
	pink = Color3.fromRGB(248, 112, 168),
	pinkDeep = Color3.fromRGB(226, 62, 128),
	green = Color3.fromRGB(150, 226, 82),
	greenDeep = Color3.fromRGB(96, 190, 48),
	red = Color3.fromRGB(246, 84, 94),
	redDeep = Color3.fromRGB(206, 42, 60),
	purple = Color3.fromRGB(178, 126, 246),
	purpleDeep = Color3.fromRGB(136, 78, 214),
	grey = Color3.fromRGB(178, 172, 168),
	greyDeep = Color3.fromRGB(138, 132, 128),

	cash = Color3.fromRGB(126, 226, 96),
	gem = Color3.fromRGB(120, 232, 224),
	tnt = Color3.fromRGB(246, 146, 70),
	robux = Color3.fromRGB(154, 228, 74),
}

local STROKE = 3

function UI.make(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	return inst
end

function UI.corner(radius: number, parent: Instance)
	UI.make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

-- The dark outline that defines the whole style. Border mode so it sits
-- outside the shape and never eats into the fill.
function UI.stroke(parent: Instance, thickness: number?, color: Color3?)
	UI.make("UIStroke", {
		Thickness = thickness or STROKE,
		Color = color or UI.color.ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- Top-to-bottom lightening, which is what gives these panels their moulded,
-- slightly-inflated look rather than reading as flat rectangles.
function UI.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	UI.make("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

-- Bold, outlined text. Every string in the game goes through this: against a
-- 3D stage, unstroked text is unreadable the moment something bright moves
-- behind it.
function UI.label(props: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Enum.Font.FredokaOne,
		TextColor3 = UI.color.paper,
		TextSize = 16,
	}
	for key, value in props do
		-- StrokeThickness is OURS, not a TextLabel property. It has to be
		-- filtered out here: UI.make assigns every key straight onto the
		-- instance, and assigning an unknown property throws — which takes the
		-- whole mount down with it, along with every button built after it.
		if key ~= "StrokeThickness" then
			defaults[key] = value
		end
	end
	local label = UI.make("TextLabel", defaults) :: TextLabel
	UI.make("UIStroke", {
		Thickness = props.StrokeThickness or 2,
		Color = UI.color.ink,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
	return label
end

-- A chunky pressable button: gradient fill, dark border, outlined label.
-- `enabled` is handled by UI.setButtonEnabled rather than at build time, so a
-- button can grey out and come back without being rebuilt.
export type Button = { button: TextButton, fill: UIGradient, stroke: UIStroke }

function UI.button(props: {
	parent: Instance,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	text: string,
	textSize: number?,
	top: Color3,
	bottom: Color3,
	zIndex: number?,
	radius: number?,
}): Button
	local button = UI.make("TextButton", {
		Size = props.size,
		Position = props.position or UDim2.fromOffset(0, 0),
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = props.top,
		AutoButtonColor = true,
		Font = Enum.Font.FredokaOne,
		Text = props.text,
		TextColor3 = UI.color.paper,
		TextSize = props.textSize or 18,
		ZIndex = props.zIndex or 2,
		Parent = props.parent,
	}) :: TextButton

	UI.corner(props.radius or 12, button)
	local gradient = UI.make("UIGradient", {
		Color = ColorSequence.new(props.top, props.bottom),
		Rotation = 90,
		Parent = button,
	}) :: UIGradient
	local stroke = UI.make("UIStroke", {
		Thickness = STROKE,
		Color = UI.color.ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = button,
	}) :: UIStroke
	UI.make("UIStroke", {
		Thickness = 2,
		Color = UI.color.ink,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = button,
	})

	return { button = button, fill = gradient, stroke = stroke }
end

-- Grey a button out without rebuilding it. Keeping the greyed colours here
-- means "disabled" looks the same everywhere by construction.
function UI.setButtonEnabled(entry: Button, enabled: boolean, top: Color3, bottom: Color3)
	entry.fill.Color = ColorSequence.new(
		enabled and top or UI.color.grey,
		enabled and bottom or UI.color.greyDeep
	)
	entry.button.AutoButtonColor = enabled
	entry.button.TextTransparency = enabled and 0 or 0.25
end

-- The green Robux price pill from the shop mockups. Purely a price TAG — it
-- is not a button and does not know how to charge anyone.
function UI.pricePill(props: {
	parent: Instance,
	size: UDim2,
	position: UDim2,
	anchor: Vector2?,
	text: string,
	zIndex: number?,
}): Frame
	local pill = UI.make("Frame", {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchor or Vector2.zero,
		BackgroundColor3 = UI.color.robux,
		ZIndex = props.zIndex or 3,
		Parent = props.parent,
	}) :: Frame
	UI.corner(8, pill)
	UI.gradient(pill, Color3.fromRGB(178, 240, 108), Color3.fromRGB(126, 202, 60))
	UI.stroke(pill)

	UI.label({
		Size = UDim2.fromScale(1, 1),
		Text = props.text,
		TextSize = 18,
		TextColor3 = UI.color.paper,
		ZIndex = (props.zIndex or 3) + 1,
		Parent = pill,
	})
	return pill
end

-- ---------- juice ----------
-- Pop a frame open or closed with a scale bounce. Both work through a
-- UIScale child (created on first use) rather than tweening Size, so a
-- frame's layout numbers are never touched and anything anchored inside it
-- stays anchored. One live tween per frame, tracked so a fast open-close-open
-- cancels cleanly instead of fighting itself.
local activePops: { [GuiObject]: Tween } = {}

local function popScaleOf(frame: GuiObject): UIScale
	local scale = frame:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = UI.make("UIScale", { Name = "PopScale", Scale = 1, Parent = frame }) :: UIScale
	end
	return scale :: UIScale
end

function UI.popIn(frame: GuiObject)
	local scale = popScaleOf(frame)
	local old = activePops[frame]
	if old then
		old:Cancel()
	end

	frame.Visible = true
	scale.Scale = 0.72
	local tween = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	activePops[frame] = tween
	tween:Play()
end

-- The close is In-eased and quicker than the open: a Back-Out on the way
-- OUT overshoots upward first, which reads as the panel re-opening.
function UI.popOut(frame: GuiObject)
	if not frame.Visible then
		return
	end
	local scale = popScaleOf(frame)
	local old = activePops[frame]
	if old then
		old:Cancel()
	end

	local tween = TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = 0.78,
	})
	activePops[frame] = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			frame.Visible = false
			scale.Scale = 1
		end
	end)
	tween:Play()
end

-- ---------- the modal blur ----------
-- One shared BlurEffect that eases in while ANY panel is open and out when
-- the last one closes. Counted off the scrims rather than asked of callers,
-- so no panel has to know the blur exists — same contract as the scrim.
local modalBlur = Instance.new("BlurEffect")
modalBlur.Size = 0
modalBlur.Parent = Lighting

local openModals = 0
local function noteModal(open: boolean)
	openModals = math.max(openModals + (open and 1 or -1), 0)
	TweenService:Create(modalBlur, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = openModals > 0 and 10 or 0,
	}):Play()
end

-- A full panel: gradient header bar with an icon and title, a red X on the
-- right, and a warm body underneath. Returns the pieces a caller needs — the
-- root to show and hide, and the body to fill in.
export type Panel = { root: Frame, body: Frame, close: TextButton, title: TextLabel, scrim: Frame }

function UI.panel(props: {
	parent: Instance,
	name: string,
	size: UDim2,
	position: UDim2,
	anchor: Vector2?,
	icon: string,
	title: string,
	top: Color3,
	bottom: Color3,
	zIndex: number?,
}): Panel
	local z = props.zIndex or 20

	-- The scrim: a full-screen dim behind every modal panel, so the world
	-- reads as paused and — more importantly — clicks BESIDE the panel die
	-- here instead of bleeding through to the wallet, the rail or the plot
	-- prompts underneath. It mirrors the root's Visible automatically, so
	-- callers keep toggling root.Visible and never have to know it exists.
	local scrim = UI.make("Frame", {
		Name = props.name .. "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 14, 10),
		BackgroundTransparency = 0.45,
		Active = true,
		Visible = false,
		ZIndex = z - 1,
		Parent = props.parent,
	}) :: Frame

	local root = UI.make("Frame", {
		Name = props.name,
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchor or Vector2.new(0.5, 0.5),
		BackgroundColor3 = props.bottom,
		-- Active so a panel swallows its own taps. Without this every click on
		-- a shop button also punches through and squishes the squisher.
		Active = true,
		Visible = false,
		ZIndex = z,
		Parent = props.parent,
	}) :: Frame
	UI.corner(16, root)
	UI.stroke(root, 4)

	-- ---------- header ----------
	local header = UI.make("Frame", {
		Size = UDim2.new(1, -12, 0, 52),
		Position = UDim2.new(0, 6, 0, 6),
		BackgroundColor3 = props.top,
		ZIndex = z + 1,
		Parent = root,
	})
	UI.corner(12, header)
	UI.gradient(header, props.top, props.bottom)
	UI.stroke(header)

	UI.label({
		Size = UDim2.new(0, 44, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		Text = props.icon,
		TextSize = 30,
		ZIndex = z + 2,
		Parent = header,
	})

	local title = UI.label({
		Size = UDim2.new(1, -170, 1, 0),
		Position = UDim2.new(0, 54, 0, 0),
		Text = props.title,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 3,
		ZIndex = z + 2,
		Parent = header,
	})

	local close = UI.button({
		parent = header,
		size = UDim2.new(0, 44, 0, 40),
		position = UDim2.new(1, -6, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		text = "X",
		textSize = 24,
		top = UI.color.red,
		bottom = UI.color.redDeep,
		zIndex = z + 2,
		radius = 10,
	}).button

	-- ---------- body ----------
	local body = UI.make("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -12, 1, -66),
		Position = UDim2.new(0, 6, 0, 60),
		BackgroundColor3 = UI.color.body,
		ZIndex = z + 1,
		Parent = root,
	}) :: Frame
	UI.corner(12, body)
	UI.gradient(body, UI.color.body, UI.color.bodyDark)
	UI.stroke(body)

	close.Activated:Connect(function()
		UI.popOut(root)
	end)

	-- The scrim and the blur both follow the root's Visible, so callers keep
	-- toggling one property and the whole modal treatment comes with it.
	local wasVisible = root.Visible
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		scrim.Visible = root.Visible
		if root.Visible ~= wasVisible then
			wasVisible = root.Visible
			noteModal(root.Visible)
		end
	end)

	return { root = root, body = body, close = close, title = title, scrim = scrim }
end

-- A card inside a panel body: the Starter Pack / VIP Bundle blocks in the
-- mockups are all this shape.
function UI.card(props: {
	parent: Instance,
	size: UDim2,
	position: UDim2,
	top: Color3,
	bottom: Color3,
	zIndex: number?,
}): Frame
	local card = UI.make("Frame", {
		Size = props.size,
		Position = props.position,
		BackgroundColor3 = props.top,
		ZIndex = props.zIndex or 22,
		Parent = props.parent,
	}) :: Frame
	UI.corner(12, card)
	UI.gradient(card, props.top, props.bottom)
	UI.stroke(card)
	return card
end

return UI
