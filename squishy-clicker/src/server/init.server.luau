--!strict
-- ============================================================
--  SERVER  —  the authority for everything that matters.
--  The client ASKS to click or prestige. The server counts the
--  clicks, rolls the squishy, owns the inventory, and applies
--  star-ups. Exploiters can't fake a Mythical.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
-- Direct require: Squishies lives at Shared/Squishies. If this ever hangs
-- with an orange "Infinite yield possible" warning in Output, the file was
-- moved — put it back at src/shared/Squishies.luau or update this path.
local Squishies = require(Shared:WaitForChild("Squishies"))

-- ---------- Remotes ----------
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local ClickSteamer = Instance.new("RemoteEvent")
ClickSteamer.Name = "ClickSteamer"
ClickSteamer.Parent = Remotes

local PrestigeSquishy = Instance.new("RemoteEvent")
PrestigeSquishy.Name = "PrestigeSquishy"
PrestigeSquishy.Parent = Remotes

-- Fired at ONE client when their steamer opens: (squishyId)
local SteamerOpened = Instance.new("RemoteEvent")
SteamerOpened.Name = "SteamerOpened"
SteamerOpened.Parent = Remotes

-- Client asks to open one of its banked steamers.
local UnboxSteamer = Instance.new("RemoteEvent")
UnboxSteamer.Name = "UnboxSteamer"
UnboxSteamer.Parent = Remotes

-- Client picks which owned squishy is its click toy: (squishyId)
local SetClicker = Instance.new("RemoteEvent")
SetClicker.Name = "SetClicker"
SetClicker.Parent = Remotes

-- Client asks to fire the cannon: (power, angle), both 0-1. Nothing else —
-- the client never says where it landed or what it won.
local LaunchShot = Instance.new("RemoteEvent")
LaunchShot.Name = "LaunchShot"
LaunchShot.Parent = Remotes

-- The server's verdict on a shot, for the client to animate.
local LaunchResult = Instance.new("RemoteEvent")
LaunchResult.Name = "LaunchResult"
LaunchResult.Parent = Remotes

-- Where the mid-air pickups are for this player's NEXT shot. Sent on join and
-- after every shot rather than folded into the ordinary sync, which fires on
-- every single click and doesn't need a dozen extra tables riding along.
local LaunchField = Instance.new("RemoteEvent")
LaunchField.Name = "LaunchField"
LaunchField.Parent = Remotes

-- Client asks to add one click to the shared steamer. No payload at all.
local ClickShared = Instance.new("RemoteEvent")
ClickShared.Name = "ClickShared"
ClickShared.Parent = Remotes

-- Shared steamer state, broadcast to everyone: progress, goal, standings.
local KingUpdate = Instance.new("RemoteEvent")
KingUpdate.Name = "KingUpdate"
KingUpdate.Parent = Remotes

-- A round ended: who won, what they got, what everyone else got.
local KingFinished = Instance.new("RemoteEvent")
KingFinished.Name = "KingFinished"
KingFinished.Parent = Remotes

local SyncData = Instance.new("RemoteEvent")
SyncData.Name = "SyncData"
SyncData.Parent = Remotes

-- ---------- Debug ----------
-- The debug remote is the one thing here that hands out free squishies, so it
-- only exists in Studio (or for the UserIds you allowlist in Config). In a
-- published game this remote is never created and the client's debug menu
-- never appears — there is no request an exploiter could forge.
local debugAllowlisted = #Config.DebugUserIds > 0
local DebugAction: RemoteEvent? = nil
if RunService:IsStudio() or debugAllowlisted then
	local remote = Instance.new("RemoteEvent")
	remote.Name = "DebugAction"
	remote.Parent = Remotes
	DebugAction = remote
end

local function isDebugAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	for _, userId in Config.DebugUserIds do
		if userId == player.UserId then
			return true
		end
	end
	return false
end

-- ---------- Data types ----------
-- One per-second bucket per rate-limited remote.
type RateLimit = { bucket: number, count: number }

-- One floating sweet on the cannon range. Positions are in GAME studs; the
-- client scales them down to fit the stage.
type Pickup = { distance: number, height: number, value: number }

type PlayerData = {
	counts: { [string]: number }, -- copies of each squishy currently held
	stars: { [string]: number },  -- star level (0-5) per squishy
	clickProgress: number,        -- clicks toward the next open
	totalOpens: number,           -- lifetime steamers opened (for leaderboard)
	unopened: number,             -- banked steamers waiting in the Unbox tray
	clickerId: string?,           -- which owned squishy is the click toy
	lastLaunch: number,           -- os.clock of the last cannon shot
	bestDistance: number,         -- furthest cannon shot ever, in studs
	launchField: { Pickup },      -- pickups waiting for their NEXT shot
	limits: { [string]: RateLimit }, -- rate limiting, keyed by remote
}

-- GetDataStore THROWS in an unpublished place (and in Studio without API
-- access). If that error escaped, it would kill this whole script and every
-- click would be silently ignored — so the store is optional and the game
-- simply doesn't persist when it's unavailable.
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[SquishyClicker] DataStores unavailable — progress will NOT save this session:", result)
	end
end
local dataByPlayer: { [Player]: PlayerData } = {}
local rng = Random.new()

local MAX_CLICKS_PER_SECOND = 25
-- The cannon has its own cooldown measured in seconds; this is only here to
-- stop a flood of requests costing us anything before that check runs.
local MAX_LAUNCHES_PER_SECOND = 4

-- ---------- Helpers ----------

-- True when this player has already used up their allowance of a remote for
-- the current second. Every remote gets one of these — assume the client is
-- hostile and calling as fast as it can.
local function overRate(data: PlayerData, key: string, perSecond: number): boolean
	local limit = data.limits[key]
	if not limit then
		limit = { bucket = 0, count = 0 }
		data.limits[key] = limit
	end

	local bucket = math.floor(os.clock())
	if bucket ~= limit.bucket then
		limit.bucket = bucket
		limit.count = 0
	end
	limit.count += 1
	return limit.count > perSecond
end

local function totalStars(data: PlayerData): number
	local total = 0
	for _, star in data.stars do
		total += star
	end
	return total
end

-- How many clicks this player needs to open the steamer right now.
-- Every steamer already opened makes this number bigger (the treadmill);
-- every star earned shaves a percentage back off (the payoff loop). Prestige
-- enough and you stay roughly level; hoard copies instead and you slow down.
local function clicksToOpen(data: PlayerData): number
	local raw = Config.BaseClicksToOpen + data.totalOpens * Config.ClicksAddedPerOpen
	local discount = math.min(totalStars(data) * Config.StarDiscountPerStar, Config.MaxStarDiscount)
	local needed = math.ceil(raw * (1 - discount))
	return math.clamp(needed, Config.MinClicksToOpen, Config.MaxClicksToOpen)
end

-- The single place steamer progress is added, so every source — clicking,
-- the cannon, anything later — banks a full steamer the same way. Loops
-- because one big award can fill more than one steamer at a time.
local function addProgress(data: PlayerData, amount: number)
	if amount <= 0 then
		return
	end
	data.clickProgress += amount

	local needed = clicksToOpen(data)
	while data.clickProgress >= needed do
		data.clickProgress -= needed
		data.unopened += 1
		needed = clicksToOpen(data) -- clamped to at least 3, so this terminates
	end
end

-- ---------- Cannon ballistics ----------
-- Every number the cannon minigame turns on is worked out here, on the server.
-- The client is sent the finished shape of the flight and draws it; it never
-- computes a distance, a pickup or a payout of its own.

-- One flight, fully described. Distances and heights are in game studs.
type Flight = {
	distance: number, -- total ground covered, and the score
	apexAt: number, -- how far along the top of the arc is
	apexHeight: number, -- how high that top is
	glideRange: number, -- ground covered gliding down from the apex
	riseSeconds: number, -- time spent climbing, for pacing the animation
	glideSeconds: number,
}

-- A shot is two phases: a normal ballistic climb to the apex, then a glide
-- that sinks in a straight line to the floor. Splitting it there is what makes
-- the angle dial a real choice — see the glide comments in Config.
local function flightFor(power: number, angleFraction: number, starPower: number): Flight
	local speed = Config.LaunchSpeed
		* (Config.LaunchMinPowerFraction + (1 - Config.LaunchMinPowerFraction) * power)
		* (1 + starPower)
	local radians = math.rad(Config.LaunchMinAngle + (Config.LaunchMaxAngle - Config.LaunchMinAngle) * angleFraction)
	local vx = speed * math.cos(radians)
	local vy = speed * math.sin(radians)

	local riseSeconds = vy / Config.LaunchGravity
	local apexHeight = vy * riseSeconds * 0.5
	local apexAt = vx * riseSeconds
	local glideSeconds = Config.LaunchGlideSeconds + apexHeight * Config.LaunchGlideSecondsPerStud
	local glideRange = vx * Config.LaunchGlideSpeedFactor * glideSeconds

	return {
		distance = apexAt + glideRange,
		apexAt = apexAt,
		apexHeight = apexHeight,
		glideRange = glideRange,
		riseSeconds = riseSeconds,
		glideSeconds = glideSeconds,
	}
end

-- How high the shot is when it has travelled `x`. The client redraws this same
-- curve to animate; only this copy decides what was collected.
local function heightAt(flight: Flight, x: number): number
	if x <= 0 or flight.apexAt <= 0 then
		return 0
	end
	if x <= flight.apexAt then
		-- Parabola peaking at the apex and meeting the floor at the muzzle.
		local offset = (x - flight.apexAt) / flight.apexAt
		return flight.apexHeight * (1 - offset * offset)
	end
	if flight.glideRange <= 0 then
		return 0
	end
	return math.max(flight.apexHeight * (1 - (x - flight.apexAt) / flight.glideRange), 0)
end

local function starPowerFor(data: PlayerData): number
	return math.min(totalStars(data) * Config.LaunchPowerPerStar, Config.LaunchMaxStarPower)
end

-- The furthest this player could possibly throw right now. Found by sampling
-- the angle dial rather than solving for it: the glide term makes the maximum
-- messy to derive, and twenty samples of arithmetic costs nothing once a shot.
local function bestPossibleDistance(starPower: number): number
	local best = 0
	for step = 0, 20 do
		local candidate = flightFor(1, step / 20, starPower).distance
		if candidate > best then
			best = candidate
		end
	end
	return best
end

-- Lay out the sweets for a shot. They spread across the player's OWN reachable
-- range, so the field stretches further down the course as their stars grow
-- and never sits somewhere they cannot get to.
local function makeLaunchField(data: PlayerData): { Pickup }
	local starPower = starPowerFor(data)
	local reach = bestPossibleDistance(starPower)
	local spread = Config.LaunchPickupFarFraction - Config.LaunchPickupNearFraction

	local field: { Pickup } = {}
	for index = 1, Config.LaunchPickupCount do
		-- Evenly spaced slots with a jitter inside each, rather than twelve
		-- free rolls — free rolls clump, and a clumped field is a dead field.
		local slot = (index - 0.5) / Config.LaunchPickupCount
		local at = reach * (Config.LaunchPickupNearFraction + spread * slot)
		at += (rng:NextNumber() - 0.5) * reach * spread / Config.LaunchPickupCount

		-- Height is read off a real arc rather than picked out of the air, so
		-- every sweet sits on SOME flyable path — a different one each time,
		-- which is what makes one angle right for this field and not the next.
		local reference = flightFor(0.7 + rng:NextNumber() * 0.3, rng:NextNumber(), starPower)
		local golden = rng:NextNumber() < Config.LaunchPickupGoldenChance

		table.insert(field, {
			distance = math.max(at, 1),
			height = math.max(heightAt(reference, at), 1.5),
			value = golden and Config.LaunchPickupGoldenValue or Config.LaunchPickupValue,
		})
	end
	return field
end

-- The furthest zone this distance has reached. Config.LaunchZones ascends, so
-- the last one still below the distance is the one landed in.
local function zoneFor(distance: number)
	local current = Config.LaunchZones[1]
	for _, zone in Config.LaunchZones do
		if distance < zone.from then
			break
		end
		current = zone
	end
	return current
end

-- Copies needed for a squishy's NEXT star, given its rarity and current star.
-- Base amount comes from the rarity (Common 10 ... Mythical 3), doubling per star.
local function prestigeCost(squishyId: string, currentStar: number): number?
	local squishy = Squishies.byId[squishyId]
	if not squishy then
		return nil
	end
	local rarity = Squishies.rarityByName[squishy.rarity]
	if not rarity then
		return nil
	end
	return rarity.baseCopies * (Config.PrestigeGrowth ^ currentStar)
end

local function sync(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	SyncData:FireClient(player, {
		counts = data.counts,
		stars = data.stars,
		clickProgress = data.clickProgress,
		clicksToOpen = clicksToOpen(data),
		totalOpens = data.totalOpens,
		totalStars = totalStars(data),
		unopened = data.unopened,
		clickerId = data.clickerId,
		-- Seconds until the cannon is usable again, so the UI can show the
		-- wait rather than the client guessing at it.
		launchReadyIn = math.max(Config.LaunchCooldownSeconds - (os.clock() - data.lastLaunch), 0),
		bestDistance = data.bestDistance,
	})
end

local function updateLeaderstats(player: Player)
	local data = dataByPlayer[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if data and leaderstats then
		local opens = leaderstats:FindFirstChild("Opens") :: IntValue?
		if opens then
			opens.Value = data.totalOpens
		end
		local stars = leaderstats:FindFirstChild("Stars") :: IntValue?
		if stars then
			stars.Value = totalStars(data)
		end
	end
end

-- ---------- Join / leave ----------

local function loadData(player: Player): PlayerData
	local loaded: {
		counts: { [string]: number }?,
		stars: { [string]: number }?,
		totalOpens: number?,
		unopened: number?,
		clickerId: string?,
		bestDistance: number?,
	}? =
		nil

	local activeStore = store
	if activeStore then
		local ok, result = pcall(function()
			return activeStore:GetAsync("player_" .. player.UserId)
		end)
		if ok and typeof(result) == "table" then
			loaded = result :: any
		elseif not ok then
			warn("[SquishyClicker] Could not load data for", player.Name, "-", result)
		end
	end

	local data: PlayerData = {
		counts = loaded and loaded.counts or {},
		stars = loaded and loaded.stars or {},
		clickProgress = 0,
		totalOpens = loaded and loaded.totalOpens or 0,
		unopened = loaded and loaded.unopened or 0,
		clickerId = loaded and loaded.clickerId or nil,
		-- Deliberately not persisted: a cannon cooldown surviving a rejoin
		-- would punish reconnecting, and rejoining to skip 15 seconds is not
		-- an exploit worth defending against.
		lastLaunch = 0,
		-- Saves that predate the distance cannon simply have no record yet.
		bestDistance = loaded and loaded.bestDistance or 0,
		-- Laid out in onPlayerAdded, once the stars this reads are in place.
		launchField = {},
		limits = {},
	}

	-- Starter gift: the squisher IS the main clicker, so nobody may start
	-- without one. Everyone gets a Red Dumpling; players who never picked a
	-- squisher get it equipped (and granted, if they somehow don't own it).
	if data.clickerId == nil then
		if (data.counts.red or 0) <= 0 and (data.stars.red or 0) <= 0 then
			data.counts.red = 1
		end
		data.clickerId = "red"
	end

	return data
end

local function saveData(player: Player)
	local data = dataByPlayer[player]
	local activeStore = store
	if not data or not activeStore then
		return
	end
	local ok, err = pcall(function()
		activeStore:SetAsync("player_" .. player.UserId, {
			counts = data.counts,
			stars = data.stars,
			totalOpens = data.totalOpens,
			unopened = data.unopened,
			clickerId = data.clickerId,
			bestDistance = data.bestDistance,
		})
	end)
	if not ok then
		warn("[SquishyClicker] Could not save data for", player.Name, "-", err)
	end
end

local function onPlayerAdded(player: Player)
	if dataByPlayer[player] then
		return -- already initialized (guards against double-init)
	end

	local data = loadData(player)
	dataByPlayer[player] = data

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local opens = Instance.new("IntValue")
	opens.Name = "Opens"
	opens.Value = data.totalOpens
	opens.Parent = leaderstats

	local stars = Instance.new("IntValue")
	stars.Name = "Stars"
	stars.Value = totalStars(data)
	stars.Parent = leaderstats

	-- The range needs sweets on it before they ever open the cannon panel.
	data.launchField = makeLaunchField(data)
	LaunchField:FireClient(player, data.launchField)

	sync(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- CRITICAL: players can join BEFORE the line above runs (especially in
-- Studio Play Solo). Without this loop, those players are invisible to the
-- server — every click silently ignored. This catches them.
for _, existing in Players:GetPlayers() do
	task.spawn(onPlayerAdded, existing)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	dataByPlayer[player] = nil
end)

-- ---------- Clicking the steamer ----------

ClickSteamer.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data then
		return
	end

	if overRate(data, "click", MAX_CLICKS_PER_SECOND) then
		return
	end

	-- A full bar BANKS a steamer rather than opening it: opening is its own
	-- moment, and its own choice.
	addProgress(data, 1)
	sync(player)
end)

-- ---------- Squishy Launch (the cannon) ----------

LaunchShot.OnServerEvent:Connect(function(player, power, angle)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	if overRate(data, "launch", MAX_LAUNCHES_PER_SECOND) then
		return
	end

	-- Everything past here treats the payload as hostile: wrong types, NaN
	-- (which slips through math.clamp) and out-of-range are all rejected
	-- before a single number is trusted.
	if typeof(power) ~= "number" or typeof(angle) ~= "number" then
		return
	end
	if power ~= power or angle ~= angle then
		return
	end
	power = math.clamp(power, 0, 1)
	angle = math.clamp(angle, 0, 1)

	local now = os.clock()
	if now - data.lastLaunch < Config.LaunchCooldownSeconds then
		return
	end
	data.lastLaunch = now

	local flight = flightFor(power, angle, starPowerFor(data))
	local distance = flight.distance

	-- Sweep up every sweet the arc passed close enough to. The magnet is the
	-- other half of what stars buy: a prestiged collection both flies further
	-- and hoovers up more on the way past.
	local magnet = Config.LaunchPickupMagnet
		+ math.min(totalStars(data) * Config.LaunchMagnetPerStar, Config.LaunchMaxStarMagnet)

	local collected: { number } = {}
	local pickupBonus = 0
	for index, pickup in data.launchField do
		if pickup.distance <= distance and math.abs(heightAt(flight, pickup.distance) - pickup.height) <= magnet then
			table.insert(collected, index)
			pickupBonus += pickup.value
		end
	end

	-- The zone multiplies the sweets too, so pushing for distance is worth
	-- more than the extra studs on their own.
	local zone = zoneFor(distance)
	local bonus = math.floor((distance * Config.LaunchClicksPerStud + pickupBonus) * zone.multiplier + 0.5)
	addProgress(data, bonus)

	local record = distance > data.bestDistance
	if record then
		data.bestDistance = distance
	end

	-- The client animates THIS flight — the shape of the arc, which sweets
	-- were taken and what it all paid. It gets no say in any of it.
	LaunchResult:FireClient(player, {
		angle = angle,
		distance = distance,
		apexAt = flight.apexAt,
		apexHeight = flight.apexHeight,
		glideRange = flight.glideRange,
		riseSeconds = flight.riseSeconds,
		glideSeconds = flight.glideSeconds,
		collected = collected,
		pickupBonus = pickupBonus,
		zone = zone.name,
		multiplier = zone.multiplier,
		bonus = bonus,
		best = data.bestDistance,
		record = record,
	})

	-- A fresh field for next time, so the angle that worked once isn't simply
	-- the answer forever.
	data.launchField = makeLaunchField(data)
	LaunchField:FireClient(player, data.launchField)
	sync(player)
end)

-- ---------- unboxing a banked steamer ----------

UnboxSteamer.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or data.unopened <= 0 then
		return
	end

	data.unopened -= 1
	-- The treadmill ticks on the OPEN, not the bank: hoarding unopened
	-- steamers never makes the current one more expensive.
	data.totalOpens += 1

	local squishy = Squishies.roll(rng)
	data.counts[squishy.id] = (data.counts[squishy.id] or 0) + 1

	SteamerOpened:FireClient(player, squishy.id)
	updateLeaderstats(player)
	sync(player)
end)

-- ---------- choosing the click toy ----------

SetClicker.OnServerEvent:Connect(function(player, squishyId)
	local data = dataByPlayer[player]
	if not data or typeof(squishyId) ~= "string" then
		return
	end
	if not Squishies.byId[squishyId] then
		return
	end
	-- You can only squish what you own (copies in hand, or prestiged away).
	if (data.counts[squishyId] or 0) <= 0 and (data.stars[squishyId] or 0) <= 0 then
		return
	end

	data.clickerId = squishyId
	sync(player)
end)

-- ---------- Prestiging a squishy ----------

PrestigeSquishy.OnServerEvent:Connect(function(player, squishyId)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	if typeof(squishyId) ~= "string" then
		return
	end

	local squishy = Squishies.byId[squishyId]
	if not squishy then
		return -- unknown id
	end

	local currentStar = data.stars[squishyId] or 0
	if currentStar >= Config.MaxStars then
		return -- already maxed
	end

	local cost = prestigeCost(squishyId, currentStar)
	if not cost then
		return
	end

	local held = data.counts[squishyId] or 0
	if held < cost then
		return -- not enough copies; server says no
	end

	-- Spend the copies, grant the star.
	data.counts[squishyId] = held - cost
	data.stars[squishyId] = currentStar + 1

	updateLeaderstats(player)
	sync(player)
	print(("[SquishyClicker] %s prestiged %s to %d star(s)"):format(player.Name, squishy.name, currentStar + 1))
end)

-- ---------- Debug actions ----------

if DebugAction then
	DebugAction.OnServerEvent:Connect(function(player, action, argument)
		if not isDebugAllowed(player) then
			return
		end
		local data = dataByPlayer[player]
		if not data or typeof(action) ~= "string" then
			return
		end

		if action == "bank" then
			data.unopened += (typeof(argument) == "number") and argument or 1
		elseif action == "fillBar" then
			-- One click short, so you can watch the bar land and bank.
			data.clickProgress = math.max(clicksToOpen(data) - 1, 0)
		elseif action == "giveAll" then
			local amount = (typeof(argument) == "number") and argument or 5
			for _, squishy in Squishies.list do
				data.counts[squishy.id] = (data.counts[squishy.id] or 0) + amount
			end
		elseif action == "maxStars" then
			for _, squishy in Squishies.list do
				data.stars[squishy.id] = Config.MaxStars
			end
		elseif action == "forceOpen" then
			-- Reveal one specific squishy. Deliberately does NOT tick
			-- totalOpens: testing reveals shouldn't inflate the click cost.
			local squishy = (typeof(argument) == "string") and Squishies.byId[argument]
			if squishy then
				data.counts[squishy.id] = (data.counts[squishy.id] or 0) + 1
				SteamerOpened:FireClient(player, squishy.id)
			end
		elseif action == "readyCannon" then
			data.lastLaunch = 0 -- sitting out a 15s cooldown while testing is misery
		elseif action == "reset" then
			-- Back to a fresh save, starter Red Dumpling and all.
			data.counts = { red = 1 }
			data.stars = {}
			data.clickProgress = 0
			data.totalOpens = 0
			data.unopened = 0
			data.clickerId = "red"
			data.bestDistance = 0
		else
			return
		end

		-- Stars decide how far the field is spread, and half these actions move
		-- them, so the range is relaid every time rather than left stale.
		data.launchField = makeLaunchField(data)
		LaunchField:FireClient(player, data.launchField)

		updateLeaderstats(player)
		sync(player)
	end)
end

-- ---------- King of the Steamer ----------
-- One giant steamer the whole server clicks together. Everyone who helped
-- gets a squishy when it opens; whoever helped most gets a better one.

-- Rank by position in the rarity table, so "rarer" is derived from the one
-- existing set of odds rather than a second table that could drift from it.
local rarityRank: { [string]: number } = {}
for index, rarity in Squishies.rarities do
	rarityRank[rarity.name] = index
end

-- The top contributor's prize: roll the SAME odds twice and keep the rarer
-- result. No separate bonus odds to maintain — add a rarity to Squishies and
-- this improves with it automatically.
local function rollBest(attempts: number): Squishies.Squishy
	local best = Squishies.roll(rng)
	for _ = 2, attempts do
		local other = Squishies.roll(rng)
		if (rarityRank[other.rarity] or 0) > (rarityRank[best.rarity] or 0) then
			best = other
		end
	end
	return best
end

local king = {
	clicks = 0,
	goal = Config.KingBaseGoal,
	contributions = {} :: { [Player]: number },
	active = true,
	nextRoundAt = 0,
	dirty = false, -- progress moved since the last broadcast
}

-- Fixed at the start of each round rather than recomputed as people come and
-- go: a goal that moved underneath players mid-round would feel broken.
local function kingGoal(): number
	local population = math.max(#Players:GetPlayers(), 1)
	return Config.KingBaseGoal + (population - 1) * Config.KingGoalPerPlayer
end

local function kingSnapshot()
	local standings: { { name: string, clicks: number } } = {}
	for contributor, clicks in king.contributions do
		-- dataByPlayer is cleared on leave, so this also skips anyone gone.
		if dataByPlayer[contributor] then
			table.insert(standings, { name = contributor.DisplayName, clicks = clicks })
		end
	end
	table.sort(standings, function(a, b)
		return a.clicks > b.clicks
	end)
	while #standings > 5 do -- nobody reads past fifth place
		table.remove(standings)
	end

	return {
		clicks = king.clicks,
		goal = king.goal,
		active = king.active,
		standings = standings,
	}
end

local function broadcastKing()
	KingUpdate:FireAllClients(kingSnapshot())
	king.dirty = false
end

local function startKingRound()
	king.clicks = 0
	king.goal = kingGoal()
	king.contributions = {}
	king.active = true
	broadcastKing()
end

local function finishKingRound()
	king.active = false
	king.nextRoundAt = os.clock() + Config.KingCooldownSeconds

	-- Settle who won before handing anything out, so the winner's own prize
	-- is decided by the same pass as everyone else's.
	local topPlayer: Player? = nil
	local topClicks = 0
	for contributor, clicks in king.contributions do
		if clicks > topClicks and dataByPlayer[contributor] then
			topClicks = clicks
			topPlayer = contributor
		end
	end

	local winnerName = ""
	local winnerPrize = ""

	for contributor, clicks in king.contributions do
		local data = dataByPlayer[contributor]
		-- A contributor who left mid-round simply isn't here to pay; their
		-- clicks still counted toward opening it.
		if data and clicks > 0 then
			local squishy = if contributor == topPlayer then rollBest(2) else Squishies.roll(rng)
			data.counts[squishy.id] = (data.counts[squishy.id] or 0) + 1
			SteamerOpened:FireClient(contributor, squishy.id)
			updateLeaderstats(contributor)
			sync(contributor)

			if contributor == topPlayer then
				winnerName = contributor.DisplayName
				winnerPrize = squishy.name
			end
		end
	end

	KingFinished:FireAllClients({
		winner = winnerName,
		prize = winnerPrize,
		clicks = topClicks,
		cooldown = Config.KingCooldownSeconds,
	})
	broadcastKing()
end

ClickShared.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or not king.active then
		return
	end
	if overRate(data, "king", Config.KingClicksPerSecond) then
		return
	end

	king.clicks += 1
	king.contributions[player] = (king.contributions[player] or 0) + 1
	king.dirty = true

	if king.clicks >= king.goal then
		finishKingRound()
	end
end)

-- Progress goes out on a timer, not on every click: a busy server would
-- otherwise fire hundreds of remotes a second to say the bar moved a pixel.
task.spawn(function()
	local interval = 1 / Config.KingBroadcastsPerSecond
	while true do
		task.wait(interval)
		if king.dirty then
			broadcastKing()
		elseif not king.active and os.clock() >= king.nextRoundAt then
			startKingRound()
		end
	end
end)

-- Newcomers need the current state or their panel sits empty until someone
-- clicks. Same GetPlayers catch-up as the main join handler, for anyone who
-- arrived before this script ran.
local function sendKingStateTo(player: Player)
	KingUpdate:FireClient(player, kingSnapshot())
end

Players.PlayerAdded:Connect(sendKingStateTo)
for _, existing in Players:GetPlayers() do
	task.spawn(sendKingStateTo, existing)
end

Players.PlayerRemoving:Connect(function(player)
	king.contributions[player] = nil
end)

startKingRound()

-- ---------- Autosave ----------

task.spawn(function()
	while true do
		task.wait(Config.AutoSaveInterval)
		for player in dataByPlayer do
			saveData(player)
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for player in dataByPlayer do
		saveData(player)
	end
	task.wait(2)
end)

print("[SquishyClicker] Server ready.")
