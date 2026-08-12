--!strict
-- ============================================================
--  GUIDE PATH  —  the yellow arrow trail home to your own plot.
--
--  A line of floating yellow "V" chevrons (two thin arms meeting
--  at a point, open like ›), built entirely from parts, strung in
--  a straight 3D line from just in front of the player to the
--  centre of their plot, marching forward along it like a
--  conveyor belt.
--
--  Fades out once the player is back within ARRIVE_DISTANCE of
--  their plot, and fades back in once they wander past it again —
--  but only up to CYCLE_LIMIT times per session. After that it
--  stays hidden, UNLESS the player has been away from their plot
--  continuously for AWAY_RESHOW_SECONDS, which forces it to show
--  one more time (without touching the per-session cycle count).
--
--  Client-local: the trail is YOURS, to your own plot.
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GuidePath = {}

local player = Players.LocalPlayer

-- Below this distance from the plot centre, the player is "home": the trail
-- fades out and (if under the cycle limit) is allowed to fade back in the
-- next time they leave.
local ARRIVE_DISTANCE = 40
-- How far above the plot's floor the "middle of the plot" target sits, and
-- roughly how far up the player's own centre is read from — both ends float
-- at about chest height rather than at the ground.
local TARGET_HEIGHT = 3
-- The first chevron floats this far in front of the player's body, not
-- right on top of them.
local START_OFFSET = 1.5
-- How far apart each chevron floats along the line.
local SPACING = 6
-- Each chevron is two thin arms meeting at a point — this is the length of
-- each arm and how thick it is.
local ARM_LENGTH = 1.4
local ARM_THICKNESS = 0.35
-- How far apart the two arms' open ends are, i.e. how wide the V is.
local ARM_SPREAD = 1.1
local ARROW_COLOR = Color3.fromRGB(255, 221, 46)
-- Studs per second the chevrons march forward along the line — the
-- conveyor-belt effect, always flowing toward the plot.
local FLOW_SPEED = 10
-- How long a fade in/out takes.
local FADE_SECONDS = 0.6

-- How many fade-out→fade-in cycles (leaving the plot, then returning) are
-- allowed in a single session before the trail stops reappearing on its own.
local CYCLE_LIMIT = 3
-- Being away from the plot continuously this long forces the trail back on
-- even past the cycle limit — a nudge back that does NOT spend a cycle.
local AWAY_RESHOW_SECONDS = 300

type Chevron = { left: Part, right: Part }

local plotCentre: Vector3? = nil
local folder: Folder? = nil
local chevrons: { Chevron } = {}
local connection: RBXScriptConnection? = nil

-- Whether the trail is CURRENTLY allowed to be visible while the player is
-- away from their plot. Starts true; set false once the cycle limit is hit,
-- and forced back true by the 5-minute away timer.
local visible = true
-- How many fade-out→fade-in cycles have happened this session.
local cyclesUsed = 0
-- True while the player is beyond ARRIVE_DISTANCE (used to detect the
-- leave→return edge that counts as one cycle).
local wasAway = false
-- Set the moment the player is first found beyond ARRIVE_DISTANCE; cleared
-- the moment they're back within it. Drives the 5-minute forced reshow.
local awaySince: number? = nil
-- True when the CURRENT showing was forced on by the 5-minute away timer
-- rather than earned under the normal per-session cap — the return trip
-- that follows one of these does not spend a cycle.
local shownByTimer = false
-- 0 = fully hidden, 1 = fully shown. Eased toward a target each frame.
local shownAlpha = 0

local function buildArm(): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = ARROW_COLOR
	part.Size = Vector3.new(ARM_THICKNESS, ARM_THICKNESS, ARM_LENGTH)
	part.Transparency = 1
	part.Parent = folder
	return part
end

local function buildChevron(): Chevron
	return { left = buildArm(), right = buildArm() }
end

-- Grows or shrinks `list` to `count` items, building with `build` and
-- destroying with `destroy` as needed.
local function resizeList<T>(list: { T }, count: number, build: () -> T, destroy: (T) -> ())
	while #list < count do
		table.insert(list, build())
	end
	while #list > count do
		destroy(table.remove(list) :: T)
	end
end

local function resize(count: number)
	resizeList(chevrons, count, buildChevron, function(chevron: Chevron)
		chevron.left:Destroy()
		chevron.right:Destroy()
	end)
end

local function step(dt: number)
	local centre = plotCentre
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not centre or not root or not folder then
		resize(0)
		return
	end

	-- A true 3D line: just in front of the player, to the plot's middle,
	-- raised to about chest height rather than sitting on the ground.
	local bodyPosition = (root :: BasePart).Position
	local to = centre + Vector3.new(0, TARGET_HEIGHT, 0)
	local bodyToTarget = to - bodyPosition
	local homeDistance = bodyToTarget.Magnitude

	local isAway = homeDistance > ARRIVE_DISTANCE
	local clock = os.clock()

	if isAway then
		if not awaySince then
			awaySince = clock
		elseif not visible and clock - (awaySince :: number) >= AWAY_RESHOW_SECONDS then
			-- Gone long enough: force the trail back on WITHOUT spending one
			-- of the per-session cycles. The return trip that follows this
			-- particular showing is free too — see shownByTimer below.
			visible = true
			shownByTimer = true
		end
		wasAway = true
	else
		awaySince = nil
		if wasAway then
			-- Just arrived home: completes one fade-out→fade-in cycle.
			if visible then
				if shownByTimer then
					-- A free showing from the 5-minute timer: doesn't spend a
					-- cycle, but the cap (already hit, or this ends where it
					-- was) still applies to the NEXT departure — only another
					-- full 5-minute absence earns another free showing.
					visible = cyclesUsed < CYCLE_LIMIT
					shownByTimer = false
				else
					cyclesUsed += 1
					if cyclesUsed >= CYCLE_LIMIT then
						visible = false
					end
				end
			end
		end
		wasAway = false
	end

	local wantShown = isAway and visible
	local alphaStep = dt / math.max(FADE_SECONDS, 1e-3)
	if wantShown then
		shownAlpha = math.min(shownAlpha + alphaStep, 1)
	else
		shownAlpha = math.max(shownAlpha - alphaStep, 0)
	end

	if shownAlpha <= 0 then
		resize(0)
		return
	end

	local direction = bodyToTarget.Unit
	local from = bodyPosition + direction * START_OFFSET
	local distance = math.max(homeDistance - START_OFFSET, 0)
	local count = math.clamp(math.floor(distance / SPACING) + 1, 1, 24)
	resize(count)

	-- Each arm angled off the direction of travel, mirrored left/right, so
	-- the pair meets at a point — an open V/chevron (›), point leading
	-- toward the plot, open end trailing behind.
	local pointFacing = CFrame.lookAt(Vector3.zero, direction).Rotation
	local armAngle = math.atan2(ARM_SPREAD * 0.5, ARM_LENGTH)
	local leftFacing = pointFacing * CFrame.Angles(0, armAngle, 0)
	local rightFacing = pointFacing * CFrame.Angles(0, -armAngle, 0)

	-- The march: chevrons drift forward along the line over time, wrapping
	-- every SPACING studs, so the trail visibly flows toward the plot.
	local flow = (os.clock() * FLOW_SPEED) % SPACING
	local transparency = 1 - shownAlpha

	for i, chevron in chevrons do
		local along = flow + (i - 1) * SPACING
		if along > distance then
			along -= SPACING * count
		end
		-- The march wraps chevrons back to the start of the line, which
		-- would otherwise place one BEHIND `from` — inside the player's own
		-- body, since `from` already sits START_OFFSET out. Hidden instead
		-- of clamped, so it doesn't pop into view already close to the feet.
		if along < 0 then
			chevron.left.Transparency = 1
			chevron.right.Transparency = 1
			continue
		end
		local tip = from + direction * along
		-- Each arm's centre sits half an arm-length back from the shared
		-- tip, offset out along its own angled axis, so the two arms meet
		-- AT the tip and open up behind it.
		local leftCentre = tip - (leftFacing.LookVector * (ARM_LENGTH * 0.5))
		local rightCentre = tip - (rightFacing.LookVector * (ARM_LENGTH * 0.5))
		chevron.left.CFrame = CFrame.new(leftCentre) * leftFacing
		chevron.left.Transparency = transparency
		chevron.right.CFrame = CFrame.new(rightCentre) * rightFacing
		chevron.right.Transparency = transparency
	end
end

-- Called with the same centre Flight.setPlot and PlotBoard.setPlot get, once
-- the server names this player as a plot's owner.
function GuidePath.setPlot(centre: Vector3)
	plotCentre = centre

	if not folder then
		local f = Instance.new("Folder")
		f.Name = "GuidePath"
		f.Parent = workspace
		folder = f
	end

	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
end

return GuidePath
