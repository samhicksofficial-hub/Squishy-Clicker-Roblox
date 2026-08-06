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

-- The walkable world. Built once, here, because a floor you stand on has to
-- replicate — see the header of Island.luau for why the launch valley is the
-- opposite case and stays on the client.
local Island = require(script:WaitForChild("Island"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
-- Direct require: Squishies lives at Shared/Squishies. If this ever hangs
-- with an orange "Infinite yield possible" warning in Output, the file was
-- moved — put it back at src/shared/Squishies.luau or update this path.
local Squishies = require(Shared:WaitForChild("Squishies"))

-- Rank by position in the rarity table (Common 1 ... Mythical 6), so "rarer"
-- is derived from the one existing set of odds rather than a second table that
-- could drift away from it. Used by the active-squishy buffs, the Lucky
-- Steamer and King of the Steamer alike.
local rarityRank: { [string]: number } = {}
for index, rarity in Squishies.rarities do
	rarityRank[rarity.name] = index
end

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

-- Where the pickups are for this player's NEXT shot. Sent on join and after
-- every shot rather than folded into the ordinary sync, which fires on every
-- single click and doesn't need a couple of dozen extra tables riding along.
local LaunchField = Instance.new("RemoteEvent")
LaunchField.Name = "LaunchField"
LaunchField.Parent = Remotes

-- Cannon progression. Every one of these is a bare "I would like to" — the
-- payload is at most an id, never an amount, a price or a reward.
local BuyPower = Instance.new("RemoteEvent")
BuyPower.Name = "BuyPower"
BuyPower.Parent = Remotes

local DoRebirth = Instance.new("RemoteEvent")
DoRebirth.Name = "DoRebirth"
DoRebirth.Parent = Remotes

-- Cash or gems for a steamer: ("coin") or ("gem"). Nothing but the kind — the
-- price and what comes out are both the server's.
local BuySteamer = Instance.new("RemoteEvent")
BuySteamer.Name = "BuySteamer"
BuySteamer.Parent = Remotes

-- Summon or dismiss a squishy: (squishyId, shouldBeActive). The server owns
-- the three-slot limit and the "do you even own it" check, not the UI.
local SetActive = Instance.new("RemoteEvent")
SetActive.Name = "SetActive"
SetActive.Parent = Remotes

-- Pick a world: (worldId). The unlock gate and the payout multiplier both
-- live here — the client's repaint of the island is cosmetic and local.
local SetWorld = Instance.new("RemoteEvent")
SetWorld.Name = "SetWorld"
SetWorld.Parent = Remotes

local ActivateBoost = Instance.new("RemoteEvent")
ActivateBoost.Name = "ActivateBoost"
ActivateBoost.Parent = Remotes

-- Somebody launched. Goes to EVERY client so the lobby can watch the shot fly
-- and list it in the feed. Carries the shape of the flight and a name, and
-- deliberately nothing about what it earned — that is the launcher's business
-- and nobody else's.
local LaunchBroadcast = Instance.new("RemoteEvent")
LaunchBroadcast.Name = "LaunchBroadcast"
LaunchBroadcast.Parent = Remotes

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

-- "I have finished connecting my handlers, send me everything."
--
-- The server fires the join sync from PlayerAdded (and from the GetPlayers
-- catch-up loop, which runs the instant the server script does). Both can and
-- do beat the client to connecting its listeners, and anything sent before
-- then is simply gone. SyncData survives that because a click re-sends it
-- seconds later — but LaunchField only goes out on join, so a lost one left
-- the whole track bare until after the player's first shot.
local ClientReady = Instance.new("RemoteEvent")
ClientReady.Name = "ClientReady"
ClientReady.Parent = Remotes

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

-- One pickup on the track. Positions are in GAME studs; the client scales
-- them to fit the stage.
type Pickup = { distance: number, height: number, kind: string, value: number, vip: boolean }

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

	-- The cannon's own economy, separate from the steamer's.
	tnt: number,                  -- buys launch power
	coins: number,                -- buys steamers; reset by rebirth
	gems: number,                 -- buys Lucky Steamers; survives rebirth
	powerLevel: number,           -- launch power upgrades bought
	rebirths: number,             -- permanent multipliers earned
	milestones: { [string]: boolean }, -- distance signs already paid out
	steamersBought: number,       -- cash-bought steamers, for the price curve
	active: { string },           -- the (at most three) squishies summoned
	worldId: string,              -- which Config.Worlds entry pays this player
	boostUntil: number,           -- os.clock while Rain TNT is running
	lastBoost: number,            -- os.clock of the last activation

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
-- Every number the cannon turns on is worked out here, on the server. The
-- client is sent the finished shape of the flight and draws it; it never
-- computes a distance, a pickup or a payout of its own.
--
-- The flight is simulated rather than solved: a ballistic arc, then a skip,
-- then another, each one keeping a share of its speed, until the skips die out
-- and it rolls to a stop. Skipping is where most of a good run's distance
-- comes from, and it is the reason the best angle is under 45° rather than at
-- it — a flatter shot keeps more forward speed into the first bounce.
--
-- This is a closed-form simulation on purpose. Roblox's own physics would be
-- the obvious way to bounce something, but physics runs on whoever owns the
-- part and is not reproducible, which would mean trusting a client's word for
-- how far it went. Deterministic arithmetic on the server cannot be argued
-- with, and it also means a 40-second flight costs no simulation time at all.

-- One hop of a flight. `peak` is 0 for the final rolling segment.
type Arc = { fromX: number, toX: number, peak: number, seconds: number, rolling: boolean }

type Flight = {
	distance: number, -- total ground covered, and the score
	arcs: { Arc },
	launchSpeed: number,
	peakHeight: number,
	seconds: number, -- real flight time, for pacing the animation
}

-- How far a bare launch of this power carries, before any bonuses. Kept apart
-- from the simulation so the two callers that only want a distance estimate
-- don't pay for the whole thing.
local function launchSpeedFor(power: number): number
	-- Range of an arc is v²/g, so this makes distance linear in power.
	return math.sqrt(math.max(power, 1) * Config.LaunchGravity * Config.LaunchStudsPerPower)
end

local function simulateFlight(power: number, angleFraction: number): Flight
	local speed = launchSpeedFor(power)
	local radians = math.rad(Config.LaunchMinAngle + (Config.LaunchMaxAngle - Config.LaunchMinAngle) * angleFraction)
	local vx = speed * math.cos(radians)
	local vy = speed * math.sin(radians)

	local arcs: { Arc } = {}
	local x = 0
	local seconds = 0
	local peakHeight = 0

	for _ = 1, Config.LaunchMaxBounces do
		if vy < Config.LaunchMinBounceSpeed then
			break
		end
		-- Up and back down to the same height, so one hop is 2v/g.
		local hang = 2 * vy / Config.LaunchGravity
		local peak = vy * vy / (2 * Config.LaunchGravity)
		local span = vx * hang

		table.insert(arcs, { fromX = x, toX = x + span, peak = peak, seconds = hang, rolling = false })
		x += span
		seconds += hang
		peakHeight = math.max(peakHeight, peak)

		vy *= Config.LaunchRestitution
		vx *= Config.LaunchBounceFriction
	end

	-- Whatever forward speed survived the last skip is spent rolling.
	local rollSpan = vx * vx / (2 * Config.LaunchRollDeceleration)
	local rollSeconds = vx / Config.LaunchRollDeceleration
	table.insert(arcs, { fromX = x, toX = x + rollSpan, peak = 0, seconds = rollSeconds, rolling = true })

	return {
		distance = x + rollSpan,
		arcs = arcs,
		launchSpeed = speed,
		peakHeight = peakHeight,
		seconds = seconds + rollSeconds,
	}
end

-- How high the shot is when it has travelled `x`. The client redraws this same
-- curve from the same arcs to animate; only this copy decides what was
-- collected, so the two drifting apart is a cosmetic bug, never an exploit.
local function heightAt(flight: Flight, x: number): number
	for _, arc in flight.arcs do
		if x <= arc.toX then
			local span = arc.toX - arc.fromX
			if arc.rolling or span <= 0 then
				return 0
			end
			-- Parabola meeting the ground at both ends of the hop.
			local along = (x - arc.fromX) / span
			return arc.peak * 4 * along * (1 - along)
		end
	end
	return 0
end

-- ---------- What the player brings to a shot ----------

local function starPowerFor(data: PlayerData): number
	return math.min(totalStars(data) * Config.LaunchPowerPerStar, Config.LaunchMaxStarPower)
end

-- What the summoned squishies are worth. Bonuses ADD across the three slots
-- rather than multiplying: additive keeps the third summon worth roughly what
-- the first was, where multiplicative stacking runs away the moment somebody
-- has three good ones. Magnet is the exception — it is flat screen studs, so
-- it stays an addend rather than becoming a multiplier.
type Bonuses = { power: number, coins: number, tnt: number, magnet: number }

local function squishyBonuses(data: PlayerData): Bonuses
	local total: Bonuses = { power = 1, coins = 1, tnt = 1, magnet = 0 }
	for _, id in data.active do
		local squishy = Squishies.byId[id]
		if squishy then
			local rank = rarityRank[squishy.rarity] or 1
			-- Stars on THIS squishy, so prestiging the one you actually summon
			-- is what pays rather than stars anywhere in the collection.
			local starred = 1 + (data.stars[id] or 0) * Config.ActiveSquishyStarBonus
			total.power += rank * Config.ActiveSquishyPowerPerRank * starred
			total.coins += rank * Config.ActiveSquishyCoinPerRank * starred
			total.tnt += rank * Config.ActiveSquishyTntPerRank * starred
			total.magnet += rank * Config.ActiveSquishyMagnetPerRank * starred
		end
	end
	return total
end

local function rebirthMultiplier(data: PlayerData, per: number): number
	return 1 + data.rebirths * per
end

-- The world this player is being paid under. Falls back to the first entry
-- rather than erroring, so a world removed from Config never strands the
-- saves that pointed at it.
local function worldFor(data: PlayerData)
	for _, world in Config.Worlds do
		if world.id == data.worldId then
			return world
		end
	end
	return Config.Worlds[1]
end

-- TNT cost of the player's NEXT power level.
local function powerUpgradeCost(level: number): number
	return math.floor(Config.PowerUpgradeBaseCost * Config.PowerUpgradeCostGrowth ^ level + 0.5)
end

-- Cash cost of the player's NEXT bought steamer. Geometric, because cash
-- income grows geometrically too — a flat price would be meaningful for an
-- hour and then free forever.
local function steamerCost(bought: number): number
	return math.floor(Config.SteamerCoinCost * Config.SteamerCostGrowth ^ bought + 0.5)
end

-- A Lucky Steamer's roll: the real odds, but with everything below the
-- minimum rank removed. Keeping the SHAPE of the table matters — a Mythical
-- should still be far rarer than a Rare inside a Lucky Steamer, which a flat
-- pick from everything that qualifies would throw away.
local function rollAtLeastRank(minRank: number): Squishies.Squishy
	local pool = {}
	local total = 0
	for _, rarity in Squishies.rarities do
		if (rarityRank[rarity.name] or 0) >= minRank then
			total += rarity.weight
			table.insert(pool, rarity)
		end
	end
	if total <= 0 then
		return Squishies.roll(rng) -- nothing qualifies; fall back to normal odds
	end

	local ticket = rng:NextNumber() * total
	local chosen = pool[#pool]
	for _, rarity in pool do
		ticket -= rarity.weight
		if ticket <= 0 then
			chosen = rarity
			break
		end
	end

	local members = {}
	for _, squishy in Squishies.list do
		if squishy.rarity == chosen.name then
			table.insert(members, squishy)
		end
	end
	if #members == 0 then
		return Squishies.roll(rng)
	end
	return members[rng:NextInteger(1, #members)]
end

-- Everything that makes a shot go further, gathered in one place so the
-- upgrade screen and the shot itself can never disagree about the total.
local function launchPowerFor(data: PlayerData): number
	local base = Config.LaunchBasePower * Config.LaunchPowerGrowth ^ data.powerLevel
	return base
		* (1 + starPowerFor(data))
		* rebirthMultiplier(data, Config.RebirthDistanceBonus)
		* squishyBonuses(data).power
end

-- The player's magnet, in the SCREEN units Config quotes it in.
local function magnetFor(data: PlayerData): number
	return Config.LaunchPickupMagnet
		+ math.min(totalStars(data) * Config.LaunchMagnetPerStar, Config.LaunchMaxStarMagnet)
		+ squishyBonuses(data).magnet
end

-- The same magnet converted into the game studs a shot is actually measured
-- in. The track is drawn so that a flight's envelope is always about
-- MagnetReferenceHeight tall on screen, so scaling by this field's own tallest
-- pickup undoes that and lands on the equivalent real reach. See the comment
-- on Config.LaunchPickupMagnet for why this cannot be a fixed number.
local function effectiveMagnet(data: PlayerData): number
	local tallest = 1
	for _, pickup in data.launchField do
		tallest = math.max(tallest, pickup.height)
	end
	return magnetFor(data) * tallest / Config.MagnetReferenceHeight
end

local function boostActive(data: PlayerData): boolean
	return os.clock() < data.boostUntil
end

-- Distance needed for the player's next rebirth.
local function rebirthRequirement(rebirths: number): number
	return Config.RebirthBaseRequirement * Config.RebirthRequirementGrowth ^ rebirths
end

-- The distance a good shot at full charge would cover right now. Used to lay
-- the pickup field out where the player can actually reach it, so the track
-- stretches out with them instead of bunching at the cannon forever.
local function expectedReach(data: PlayerData): number
	local power = launchPowerFor(data)
	local best = 0
	for step = 0, 8 do
		local candidate = simulateFlight(power, step / 8).distance
		if candidate > best then
			best = candidate
		end
	end
	return math.max(best, 1)
end

-- ---------- The pickup field ----------

-- VIP zones: bands of the track where pickups cluster and pay several times
-- over. Placed as fractions of the player's own reach, so they stay relevant
-- at every power level rather than being left behind at 500 studs.
local function makeVipZones(reach: number): { { from: number, to: number } }
	local zones = {}
	for index = 1, Config.VipZoneCount do
		-- Spread across the back half of the reach: a VIP zone at the cannon's
		-- feet would be free money on every shot.
		local centre = reach * (0.45 + 0.5 * (index - 0.5) / Config.VipZoneCount)
		local half = reach * Config.VipZoneWidthFraction * 0.5
		table.insert(zones, { from = centre - half, to = centre + half })
	end
	return zones
end

local function inVipZone(zones: { { from: number, to: number } }, at: number): boolean
	for _, zone in zones do
		if at >= zone.from and at <= zone.to then
			return true
		end
	end
	return false
end

local function makeLaunchField(data: PlayerData): { Pickup }
	local reach = expectedReach(data)
	local spread = Config.LaunchPickupFarFraction - Config.LaunchPickupNearFraction
	local zones = makeVipZones(reach)
	local boosted = boostActive(data)

	-- Rain TNT and VIP zones both work by adding EXTRA pickups rather than
	-- replacing the ordinary ones, so neither can ever make a shot worse.
	local count = Config.LaunchPickupCount
	if boosted then
		count = math.floor(count * Config.BoostDensityMultiplier)
	end

	local field: { Pickup } = {}
	local function place(at: number, forceVip: boolean)
		at = math.max(at, 1)
		local vip = forceVip or inVipZone(zones, at)

		-- Height is read off a REAL arc rather than picked out of the air, so
		-- every pickup sits on some flyable path — a different one each time,
		-- which is what stops one angle being the answer to every field.
		local reference = simulateFlight(launchPowerFor(data) * (0.55 + rng:NextNumber() * 0.5), rng:NextNumber())
		local height = heightAt(reference, at)

		local roll = rng:NextNumber()
		local kind, value
		if roll < Config.PickupGemChance then
			kind, value = "gem", Config.PickupGemValue
		elseif roll < Config.PickupGemChance + Config.PickupCoinChance then
			kind, value = "coin", Config.PickupCoinValue
		else
			kind, value = "tnt", Config.PickupTntValue
		end

		-- Further out is worth more, or a six-figure run pays the same per
		-- pickup as a five-hundred-stud one and the track stops mattering.
		value *= 1 + (at / 1000) * Config.PickupValuePer1kStuds
		if vip then
			value *= Config.VipZoneValueMultiplier
		end
		if boosted and kind == "tnt" then
			value *= Config.BoostPickupMultiplier
		end

		table.insert(field, {
			distance = at,
			height = math.max(height, 2),
			kind = kind,
			value = math.max(math.floor(value + 0.5), 1),
			vip = vip,
		})
	end

	for index = 1, count do
		-- Evenly spaced slots with a jitter inside each, rather than free
		-- rolls — free rolls clump, and a clumped field is a dead field.
		local slot = (index - 0.5) / count
		local at = reach * (Config.LaunchPickupNearFraction + spread * slot)
		place(at + (rng:NextNumber() - 0.5) * reach * spread / count, false)
	end

	-- The VIP clusters on top.
	for _, zone in zones do
		for _ = 1, Config.VipZoneDensityMultiplier do
			place(zone.from + rng:NextNumber() * (zone.to - zone.from), true)
		end
	end

	return field
end

-- Milestones the player has just passed for the first time. Paid once each,
-- and the main early source of gems.
local function newMilestones(data: PlayerData, distance: number): { { name: string, gems: number } }
	local reached = {}
	for _, milestone in Config.DistanceMilestones do
		if distance >= milestone.at and not data.milestones[milestone.name] then
			data.milestones[milestone.name] = true
			table.insert(reached, { name = milestone.name, gems = milestone.gems })
		end
	end
	return reached
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

		-- The cannon's economy. Prices and totals are computed HERE and sent
		-- as finished numbers: the client showing a different price from the
		-- one the server charges is the classic way these two drift apart.
		tnt = data.tnt,
		coins = data.coins,
		gems = data.gems,
		powerLevel = data.powerLevel,
		powerCost = powerUpgradeCost(data.powerLevel),
		launchPower = launchPowerFor(data),
		magnet = magnetFor(data),
		rebirths = data.rebirths,
		rebirthAt = rebirthRequirement(data.rebirths),
		rebirthReady = data.bestDistance >= rebirthRequirement(data.rebirths),
		active = data.active,
		steamerCost = steamerCost(data.steamersBought),
		luckySteamerCost = Config.LuckySteamerGemCost,
		-- The active world and what it pays, as finished numbers: the Worlds
		-- panel and the island repaint both key off these.
		worldId = data.worldId,
		worldMultiplier = worldFor(data).multiplier,
		boostReadyIn = math.max(Config.BoostCooldownSeconds - (os.clock() - data.lastBoost), 0),
		boostLeft = math.max(data.boostUntil - os.clock(), 0),
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
		tnt: number?,
		coins: number?,
		gems: number?,
		powerLevel: number?,
		rebirths: number?,
		milestones: { [string]: boolean }?,
		steamersBought: number?,
		active: { string }?,
		worldId: string?,
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
		-- would punish reconnecting, and rejoining to skip the wait is not an
		-- exploit worth defending against.
		--
		-- -inf rather than 0 because these are compared against os.clock(),
		-- which counts from when the SERVER started, not from any epoch. At 0
		-- a freshly started server reads as "launched at clock zero", so the
		-- first several seconds of every Studio session silently refused every
		-- shot. -inf is the only value that honestly means "never".
		lastLaunch = -math.huge,
		-- Saves that predate the distance cannon simply have no record yet.
		-- Every field below follows the same shape, so a save written before
		-- this update loads as a player who has never touched the cannon
		-- rather than as an error.
		bestDistance = loaded and loaded.bestDistance or 0,
		-- Laid out in onPlayerAdded, once the stars this reads are in place.
		launchField = {},

		tnt = loaded and loaded.tnt or 0,
		coins = loaded and loaded.coins or 0,
		gems = loaded and loaded.gems or 0,
		powerLevel = loaded and loaded.powerLevel or 0,
		rebirths = loaded and loaded.rebirths or 0,
		milestones = loaded and loaded.milestones or {},
		steamersBought = loaded and loaded.steamersBought or 0,
		active = loaded and loaded.active or {},
		worldId = loaded and loaded.worldId or Config.Worlds[1].id,
		-- Not persisted, and -inf for the same reason as lastLaunch above.
		boostUntil = 0,
		lastBoost = -math.huge,

		limits = {},
	}

	-- A save can name squishies that were since removed from the catalog, or
	-- more summoned than the limit allows if the limit was lowered, or ones
	-- that were prestiged away since. All three are filtered on load rather
	-- than trusted, so the rest of the file can assume every id in here is
	-- real and owned.
	local active: { string } = {}
	for _, id in data.active do
		local owns = (data.counts[id] or 0) > 0 or (data.stars[id] or 0) > 0
		if Squishies.byId[id] and owns and #active < Config.MaxActiveSquishies then
			table.insert(active, id)
		end
	end
	data.active = active

	-- A saved world has to still exist AND still be earned: rebirths never
	-- decrease, so this only ever catches a save edited by hand or a world
	-- whose unlock requirement was raised since.
	local savedWorld = worldFor(data)
	data.worldId = (data.rebirths >= savedWorld.rebirths) and savedWorld.id or Config.Worlds[1].id

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
			tnt = data.tnt,
			coins = data.coins,
			gems = data.gems,
			powerLevel = data.powerLevel,
			rebirths = data.rebirths,
			milestones = data.milestones,
			steamersBought = data.steamersBought,
			active = data.active,
			worldId = data.worldId,
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

	-- A plot of their own on the island. Claimed before the save loads, so a
	-- slow DataStore never leaves somebody standing on the plaza with nowhere
	-- to launch from. A full island hands back nil and the player simply has
	-- no cannon of their own, which is survivable — the server can hold more
	-- players than there are plots.
	local plot = Island.claim(player)
	if not plot then
		warn(("[SquishyClicker] No free plot for %s — the island is full."):format(player.Name))
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

-- Before any player is served, so the first joiner has an island to stand on
-- and a plot to be handed.
Island.build()

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
	-- Freed immediately rather than on a timer: the next person to join should
	-- get a plot, not be told the island is full by a ghost.
	Island.release(player)
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

-- The client says when it is listening, and gets the join payload again. Rate
-- limited like everything else, and it hands out nothing a sync wouldn't.
ClientReady.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or overRate(data, "ready", 3) then
		return
	end
	if #data.launchField == 0 then
		data.launchField = makeLaunchField(data)
	end
	LaunchField:FireClient(player, data.launchField)
	sync(player)
	-- King of the Steamer answers this same remote in its own section below,
	-- where its snapshot function is in scope.
end)

-- ---------- Squishy Launch (the cannon) ----------

-- A launch request the server will not honour. The client commits to its
-- "flying" state the moment it asks — it has to, or the meters would keep
-- sweeping — so a silent drop leaves it stuck there forever with the flight
-- HUD reading zero and no launch button. Every refusal therefore ANSWERS.
local function rejectLaunch(player: Player, reason: string)
	LaunchResult:FireClient(player, { ok = false, reason = reason })
end

LaunchShot.OnServerEvent:Connect(function(player, power, angle)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	if overRate(data, "launch", MAX_LAUNCHES_PER_SECOND) then
		-- The one refusal that stays silent: answering a flood is the flood.
		-- The client's own watchdog un-sticks it a moment later.
		return
	end

	-- Everything past here treats the payload as hostile: wrong types, NaN
	-- (which slips through math.clamp) and out-of-range are all rejected
	-- before a single number is trusted.
	if typeof(power) ~= "number" or typeof(angle) ~= "number" then
		rejectLaunch(player, "That shot didn't make sense.")
		return
	end
	if power ~= power or angle ~= angle then
		rejectLaunch(player, "That shot didn't make sense.")
		return
	end
	power = math.clamp(power, 0, 1)
	angle = math.clamp(angle, 0, 1)

	local now = os.clock()
	local waitLeft = Config.LaunchCooldownSeconds - (now - data.lastLaunch)
	if waitLeft > 0 then
		rejectLaunch(player, ("Cannon reloading — %ds"):format(math.ceil(waitLeft)))
		return
	end
	data.lastLaunch = now

	-- Charge maps onto a fraction of full power, so even a badly timed tap
	-- still flies — it just doesn't fly far.
	local charged = launchPowerFor(data)
		* (Config.LaunchMinPowerFraction + (1 - Config.LaunchMinPowerFraction) * power)
	local flight = simulateFlight(charged, angle)
	local distance = flight.distance

	-- Sweep up everything the path passed close enough to. The magnet is the
	-- other half of what stars and summons buy: a built-up account both flies
	-- further AND hoovers up more on the way past.
	local magnet = effectiveMagnet(data)
	local bonuses = squishyBonuses(data)
	-- The active world multiplies cash and TNT — not gems, which stay the
	-- un-buffable prize currency, and not the milestone bounties, which are
	-- one-off achievements rather than track income.
	local world = worldFor(data)

	local collected: { number } = {}
	local earnedTnt, earnedCoins, earnedGems = 0, 0, 0
	for index, pickup in data.launchField do
		if pickup.distance <= distance and math.abs(heightAt(flight, pickup.distance) - pickup.height) <= magnet then
			table.insert(collected, index)
			if pickup.kind == "coin" then
				earnedCoins += pickup.value * bonuses.coins * rebirthMultiplier(data, Config.RebirthCoinBonus) * world.multiplier
			elseif pickup.kind == "gem" then
				-- Gems are deliberately UNBUFFED. Summons boost power, cash,
				-- TNT and magnet; letting them boost gems too would devalue
				-- the milestone bounties, which are meant to be the reason
				-- gems feel like a prize. (This line used to multiply by a
				-- pet bonus that no longer exists — hence the nil.)
				earnedGems += pickup.value
			else
				earnedTnt += pickup.value * bonuses.tnt * rebirthMultiplier(data, Config.RebirthTntBonus) * world.multiplier
			end
		end
	end

	earnedTnt = math.floor(earnedTnt)
	earnedCoins = math.floor(earnedCoins)
	earnedGems = math.floor(earnedGems)

	-- Distance milestones pay their gem bounty the first time only.
	local milestones = newMilestones(data, distance)
	local milestoneGems = 0
	for _, milestone in milestones do
		milestoneGems += milestone.gems
	end

	data.tnt += earnedTnt
	data.coins += earnedCoins
	data.gems += earnedGems + milestoneGems

	-- The two halves of the game still touch: distance nudges the steamer bar
	-- along too, at a rate small enough that nobody launches to fill it.
	local steamerBonus = math.floor(distance * Config.LaunchClicksPerStud + 0.5)
	addProgress(data, steamerBonus)

	local record = distance > data.bestDistance
	if record then
		data.bestDistance = distance
	end

	-- The client animates THIS flight — the shape of every hop, which pickups
	-- were taken and what it all paid. It gets no say in any of it.
	LaunchResult:FireClient(player, {
		angle = angle,
		distance = distance,
		arcs = flight.arcs,
		peakHeight = flight.peakHeight,
		launchSpeed = flight.launchSpeed,
		seconds = flight.seconds,
		bounces = #flight.arcs - 1,
		collected = collected,
		tnt = earnedTnt,
		coins = earnedCoins,
		gems = earnedGems + milestoneGems,
		milestones = milestones,
		steamerBonus = steamerBonus,
		best = data.bestDistance,
		record = record,
		-- Shown as the summary's multiplier breakdown, so the player can see
		-- what each part of their account is actually contributing.
		rebirths = data.rebirths,
		coinMultiplier = bonuses.coins * rebirthMultiplier(data, Config.RebirthCoinBonus) * world.multiplier,
		tntMultiplier = bonuses.tnt * rebirthMultiplier(data, Config.RebirthTntBonus) * world.multiplier,
		worldMultiplier = world.multiplier,
		boosted = boostActive(data),
	})

	-- Everyone in the lobby watches the shot fly. Deliberately carries the
	-- SHAPE of the flight and a name and nothing else: what a launch earned is
	-- the launcher's business, and broadcasting balances to the whole server
	-- would be handing every client a list of who is worth targeting.
	LaunchBroadcast:FireAllClients({
		name = player.DisplayName,
		userId = player.UserId,
		distance = distance,
		arcs = flight.arcs,
		seconds = flight.seconds,
		-- So the ghost is drawn as the squishy they actually launched.
		clickerId = data.clickerId,
	})

	-- A fresh field for next time, so the angle that worked once isn't simply
	-- the answer forever.
	data.launchField = makeLaunchField(data)
	LaunchField:FireClient(player, data.launchField)
	sync(player)
end)

-- ---------- Cannon progression ----------

-- Buying power. The client sends nothing at all: it cannot name a level, a
-- price or a quantity, so the only thing it can do is ask for the next one.
BuyPower.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or overRate(data, "buyPower", 8) then
		return
	end
	if data.powerLevel >= Config.LaunchMaxPowerLevel then
		return
	end

	local cost = powerUpgradeCost(data.powerLevel)
	if data.tnt < cost then
		return -- server says no
	end

	data.tnt -= cost
	data.powerLevel += 1

	-- Reach just grew, so the track's pickups belong further out.
	data.launchField = makeLaunchField(data)
	LaunchField:FireClient(player, data.launchField)
	sync(player)
end)

-- Rebirth: spend the cannon's whole run for a permanent multiplier. Gated on
-- the distance RECORD rather than on a currency, so it is earned by playing
-- the game rather than by sitting on a pile of TNT.
DoRebirth.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or overRate(data, "rebirth", 4) then
		return
	end
	if data.bestDistance < rebirthRequirement(data.rebirths) then
		return
	end

	data.rebirths += 1
	-- What resets, and what deliberately does not: gems, squishies and the
	-- milestone record all survive, or a rebirth would cost more than it pays.
	data.tnt = 0
	data.coins = 0
	data.powerLevel = 0
	data.bestDistance = 0

	data.launchField = makeLaunchField(data)
	LaunchField:FireClient(player, data.launchField)
	sync(player)
	print(("[SquishyClicker] %s rebirthed to %d"):format(player.Name, data.rebirths))
end)

-- ---------- The steamer shop ----------
-- What the launcher's cash and gems are FOR. Both buy steamers, which is the
-- join between the two halves of the game: launching earns the currency,
-- the currency buys squishies, and squishies make the next launch go further.

BuySteamer.OnServerEvent:Connect(function(player, kind)
	local data = dataByPlayer[player]
	if not data or overRate(data, "buySteamer", 6) then
		return
	end
	if typeof(kind) ~= "string" then
		return
	end

	if kind == "gem" then
		if data.gems < Config.LuckySteamerGemCost then
			return -- server says no
		end
		data.gems -= Config.LuckySteamerGemCost
		-- A Lucky Steamer is opened on the spot rather than banked: the
		-- guaranteed rarity is the whole product, and making the player go and
		-- unbox it separately would only hide it.
		local squishy = rollAtLeastRank(Config.LuckySteamerMinRank)
		data.counts[squishy.id] = (data.counts[squishy.id] or 0) + 1
		data.totalOpens += 1
		SteamerOpened:FireClient(player, squishy.id)
		updateLeaderstats(player)
	elseif kind == "coin" then
		local cost = steamerCost(data.steamersBought)
		if data.coins < cost then
			return
		end
		data.coins -= cost
		data.steamersBought += 1
		-- Banked rather than opened, so a bought steamer behaves exactly like
		-- an earned one and the Unbox tray stays the only place they open.
		data.unopened += 1
	else
		return -- unknown kind
	end

	sync(player)
end)

-- ---------- Worlds ----------
-- Picking a world is picking a payout multiplier, so the unlock gate lives
-- here and nowhere else. The client's island repaint is cosmetic and local;
-- an exploiter recolouring their own grass earns them nothing.

SetWorld.OnServerEvent:Connect(function(player, worldId)
	local data = dataByPlayer[player]
	if not data or overRate(data, "world", 6) then
		return
	end
	if typeof(worldId) ~= "string" then
		return
	end

	for _, world in Config.Worlds do
		if world.id == worldId then
			if data.rebirths < world.rebirths then
				return -- not earned yet; the UI shows the lock, this enforces it
			end
			data.worldId = world.id
			sync(player)
			return
		end
	end
	-- Unknown id: fall through silently, same as every other bad payload.
end)

-- ---------- Summoned squishies ----------
-- The squishies ARE the pets: up to three follow you around and buff the
-- cannon. Ownership and the slot limit are both checked here — the UI shows
-- the same rule, but it is not the one enforcing it.

SetActive.OnServerEvent:Connect(function(player, squishyId, shouldActivate)
	local data = dataByPlayer[player]
	if not data or overRate(data, "active", 12) then
		return
	end
	if typeof(squishyId) ~= "string" or typeof(shouldActivate) ~= "boolean" then
		return
	end
	if not Squishies.byId[squishyId] then
		return -- unknown id
	end

	if shouldActivate then
		-- You can only summon what you own — copies in hand, or prestiged away
		-- into stars, which still counts as having earned it.
		local owns = (data.counts[squishyId] or 0) > 0 or (data.stars[squishyId] or 0) > 0
		if not owns then
			return
		end
		if #data.active >= Config.MaxActiveSquishies or table.find(data.active, squishyId) then
			return
		end
		table.insert(data.active, squishyId)
	else
		local at = table.find(data.active, squishyId)
		if not at then
			return
		end
		table.remove(data.active, at)
	end

	-- Summoning changes launch power, which changes reach, which is what the
	-- pickup field is laid out against.
	data.launchField = makeLaunchField(data)
	LaunchField:FireClient(player, data.launchField)
	sync(player)
end)

-- ---------- Rain TNT ----------

ActivateBoost.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or overRate(data, "boost", 4) then
		return
	end

	local now = os.clock()
	if now - data.lastBoost < Config.BoostCooldownSeconds then
		return
	end
	data.lastBoost = now
	data.boostUntil = now + Config.BoostSeconds

	-- Relay the field immediately: the whole point of the button is seeing the
	-- track fill up with TNT the moment it is pressed.
	data.launchField = makeLaunchField(data)
	LaunchField:FireClient(player, data.launchField)
	sync(player)

	-- And put it back to normal when it runs out, so the track visibly empties
	-- again rather than staying rich until the next shot.
	task.delay(Config.BoostSeconds, function()
		local current = dataByPlayer[player]
		if current == data and not boostActive(data) then
			data.launchField = makeLaunchField(data)
			LaunchField:FireClient(player, data.launchField)
			sync(player)
		end
	end)
end)

-- ---------- unboxing a banked steamer ----------

UnboxSteamer.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or data.unopened <= 0 then
		return
	end
	-- Bounded by the banked count anyway, but rate-limited like every other
	-- remote: uniformity is what makes the missing limiter the bug.
	if overRate(data, "unbox", 6) then
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
	if overRate(data, "clicker", 8) then
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
	if overRate(data, "prestige", 6) then
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
			-- Sitting out a cooldown while testing is misery. -inf, not 0:
			-- these are compared against os.clock(), which starts near zero on
			-- a fresh server, so 0 would leave the cooldown still running.
			data.lastLaunch = -math.huge
			data.lastBoost = -math.huge
		elseif action == "rotateCannons" then
			-- Dial the imported model's facing in by eye, then make it stick.
			local yaw = Island.rotateCannons()
			print(("[SquishyClicker] Cannons at yaw %d — write it into CANNON_YAW_DEGREES in Island.luau."):format(yaw))
		elseif action == "richCannon" then
			-- Enough of everything to reach every screen the cannon has.
			data.tnt += 1000000
			data.coins += 1000000
			data.gems += 500
		elseif action == "powerUp" then
			local levels = (typeof(argument) == "number") and argument or 10
			data.powerLevel = math.min(data.powerLevel + levels, Config.LaunchMaxPowerLevel)
		elseif action == "readyRebirth" then
			-- Records the distance rather than the rebirth itself, so the
			-- button still has to be pressed and its own path still gets run.
			data.bestDistance = rebirthRequirement(data.rebirths)
		elseif action == "reset" then
			-- Back to a fresh save, starter Red Dumpling and all.
			data.counts = { red = 1 }
			data.stars = {}
			data.clickProgress = 0
			data.totalOpens = 0
			data.unopened = 0
			data.clickerId = "red"
			data.bestDistance = 0
			data.tnt = 0
			data.coins = 0
			data.gems = 0
			data.powerLevel = 0
			data.rebirths = 0
			data.milestones = {}
			data.steamersBought = 0
			data.active = {}
			data.worldId = Config.Worlds[1].id
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

-- King of the Steamer is an EVENT on a clock rather than a permanent button.
-- The whole server converges on the plaza for thirty seconds every five
-- minutes, which is the only thing that makes a shared bar feel shared — a bar
-- that is always open is just a second clicker nobody watches.
local king = {
	clicks = 0,
	goal = Config.KingCrownClicks,
	contributions = {} :: { [Player]: number },
	active = false,
	-- os.time, not os.clock: this is wall-clock scheduling that has to line up
	-- across a whole server, and os.clock measures CPU time from process start.
	startsAt = os.time() + Config.KingEventInterval,
	endsAt = 0,
	lastCallout = math.huge, -- the largest callout already announced
	dirty = false, -- progress moved since the last broadcast
}

-- Standing on the plaza, measured on the server. The UI mirrors this so the
-- button greys out at the right moment, but this copy is the one that counts.
local function inPlaza(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local offset = root.Position - Vector3.new(0, root.Position.Y, 0)
	return offset.Magnitude <= Config.KingPlazaRadius
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

	local now = os.time()
	return {
		clicks = king.clicks,
		goal = king.goal,
		active = king.active,
		standings = standings,
		-- The two clocks the panel runs on. Only one is ever meaningful at a
		-- time, but sending both means the client never has to guess which
		-- phase it is in.
		startsIn = math.max(king.startsAt - now, 0),
		endsIn = king.active and math.max(king.endsAt - now, 0) or 0,
		plazaRadius = Config.KingPlazaRadius,
	}
end

local function broadcastKing()
	KingUpdate:FireAllClients(kingSnapshot())
	king.dirty = false
end

local function startKingRound()
	king.clicks = 0
	-- The "goal" the clients draw is the crown threshold: the bar to beat is
	-- personal now, not shared, so it doesn't scale with the player count.
	king.goal = Config.KingCrownClicks
	king.contributions = {}
	king.active = true
	king.endsAt = os.time() + Config.KingRoundSeconds
	broadcastKing()
end

local function finishKingRound()
	king.active = false
	-- The next round is scheduled from NOW rather than from the last start, so
	-- a round that ran long (or ended early on a full bar) still leaves the
	-- promised gap before the next one.
	king.startsAt = os.time() + Config.KingCooldownSeconds + Config.KingEventInterval
	king.lastCallout = math.huge

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

	-- The crown has a floor: the top clicker only wins if they got OVER the
	-- threshold. Below it the round still pays every helper their ordinary
	-- roll — it just crowns nobody, and the rarest prize stays in the pot.
	if topClicks <= Config.KingCrownClicks then
		topPlayer = nil
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
	-- You have to actually BE there. The client greys its button out when you
	-- wander off the plaza, but that is a courtesy — this is the check, and it
	-- is the whole reason the event is worth walking to.
	if not inPlaza(player) then
		return
	end

	king.clicks += 1
	king.contributions[player] = (king.contributions[player] or 0) + 1
	king.dirty = true
	-- No early finish on a filled bar: the round is a race, and a race runs
	-- to the bell — being past the threshold just means the crown is live.
end)

-- Progress goes out on a timer, not on every click: a busy server would
-- otherwise fire hundreds of remotes a second to say the bar moved a pixel.
--
-- The same loop runs the event clock, because the two are the same question —
-- "has anything changed that everyone needs to know about".
task.spawn(function()
	local interval = 1 / Config.KingBroadcastsPerSecond
	local lastSecond = 0

	while true do
		task.wait(interval)
		local now = os.time()

		if king.active then
			if king.dirty then
				broadcastKing()
			end
			-- Thirty seconds and the bar closes whether it filled or not. A
			-- round that can be left open indefinitely is not an event.
			if now >= king.endsAt then
				finishKingRound()
			end
		else
			local startsIn = king.startsAt - now
			if startsIn <= 0 then
				startKingRound()
			elseif now ~= lastSecond then
				lastSecond = now
				-- Call out at the marked seconds only. Announcing every second
				-- for forty-five seconds is noise, not urgency — and each of
				-- these is a remote to every client.
				for _, mark in Config.KingCallouts do
					if startsIn <= mark and king.lastCallout > mark then
						king.lastCallout = mark
						KingFinished:FireAllClients({
							countdown = mark,
							winner = "",
							prize = "",
							clicks = 0,
						})
						break
					end
				end
				-- The panel's own clock still needs feeding while it waits.
				broadcastKing()
			end
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

-- ...and again once the client says it is actually listening, since both of
-- the above can beat it to connecting. Same remote as the launcher's ready
-- handshake; this is the second listener on it — and it needs its OWN rate
-- limit, because each listener on a remote fires independently and the first
-- one's limiter does nothing to stop this one being spammed into an echo.
ClientReady.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data or overRate(data, "kingReady", 2) then
		return
	end
	sendKingStateTo(player)
end)

Players.PlayerRemoving:Connect(function(player)
	king.contributions[player] = nil
end)

-- Deliberately NOT starting a round here. The first one is on the clock like
-- every other, so somebody joining a fresh server gets the countdown rather
-- than walking into a round already half over.
broadcastKing()

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
