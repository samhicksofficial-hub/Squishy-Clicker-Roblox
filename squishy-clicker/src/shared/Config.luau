--!strict
-- Central game tuning. Change numbers here rather than hunting through scripts.

local Config = {
	-- ===== The steamer =====
	-- Clicks needed to open the steamer when you have zero stars.
	BaseClicksToOpen = 10,

	-- The steamer can never get faster than this many clicks.
	MinClicksToOpen = 3,

	-- THE TREADMILL: every steamer you open makes the next one cost this many
	-- more clicks, forever. Opening 20 steamers adds 20 clicks to the price.
	ClicksAddedPerOpen = 1,

	-- Hard ceiling, so the treadmill can never make the game unplayable.
	MaxClicksToOpen = 200,

	-- ===== Stars fight the treadmill =====
	-- Each star you've earned (across ALL squishies) shaves this FRACTION off
	-- the requirement. A percentage rather than a flat number, so stars keep
	-- mattering no matter how high the requirement has climbed.
	-- 0.02 = 2% per star, so 10 stars means a 20% cheaper steamer.
	StarDiscountPerStar = 0.02,

	-- Stars can never discount more than this, or the floor becomes trivial.
	MaxStarDiscount = 0.8,

	-- ===== Prestige (star-ups) =====
	MaxStars = 5,

	-- Copies needed for each star DOUBLE every level.
	-- (The per-rarity starting amounts live in Squishies.luau: Common 10 ... Mythical 3.)
	PrestigeGrowth = 2,

	-- ===== Squishy Launch (the cannon) =====
	-- A launch simulator. One shot, one long flight, and how far you get IS
	-- the score. The whole progression is "throw further next time", so every
	-- number here feeds one of two things: how fast the squishy leaves the
	-- barrel, or how much of that speed survives hitting the ground.

	-- The only thing stopping the cannon from out-earning the steamer, so it
	-- is the number to raise if launching ever feels like the better loop.
	LaunchCooldownSeconds = 8,

	-- What one stud of distance pays in steamer clicks. Deliberately tiny:
	-- distances run to six figures late on, and the steamer bar is not meant
	-- to be won by launching.
	LaunchClicksPerStud = 0.004,

	-- Gravity the shot arcs under. Raising it shortens every flight at once,
	-- so it is the single blunt lever over the whole distance economy.
	LaunchGravity = 90,

	-- Distance is deliberately LINEAR in launch power: range for a ballistic
	-- arc is v²/g, so muzzle speed is sqrt(power · gravity · this) and a shot
	-- at 45° covers `power × this` studs before it ever bounces. That means an
	-- upgrade that doubles power reads as double the distance, which is the
	-- only relationship a launch simulator really needs players to feel.
	LaunchStudsPerPower = 1,

	-- A limp shot still leaves the barrel: the charge meter maps onto this
	-- fraction of muzzle speed upwards, rather than starting from nothing.
	LaunchMinPowerFraction = 0.4,

	-- The angle dial sweeps between these, in degrees. 45 is the best angle
	-- for a pure arc, but bounces reward flatter shots, so the sweet spot
	-- sits a little under it.
	LaunchMinAngle = 15,
	LaunchMaxAngle = 75,

	-- ----- Bouncing -----
	-- Hitting the ground is not the end of a shot: the squishy skips along
	-- like a stone, and the skips are most of a good run's distance.

	-- Share of vertical speed kept on each bounce. Under 0.5 and the skips
	-- die out immediately; over about 0.75 and shots never stop.
	LaunchRestitution = 0.62,

	-- Share of FORWARD speed kept on each bounce. This is the real distance
	-- lever of the two — it compounds once per skip.
	LaunchBounceFriction = 0.88,

	-- Below this much upward speed a bounce is not worth drawing, so the
	-- squishy stops skipping and starts rolling.
	LaunchMinBounceSpeed = 8,

	-- Hard cap on skips, purely so the simulation loop always terminates.
	LaunchMaxBounces = 14,

	-- How hard the roll at the end slows down, in studs per second². The roll
	-- covers v²/(2 · this), so lowering it adds a long tail to every shot.
	LaunchRollDeceleration = 34,

	-- ----- Launch power -----
	-- Power is bought in levels with TNT and grows geometrically, which is
	-- what lets distances climb from a few hundred studs to six figures
	-- without the level number becoming absurd.
	LaunchBasePower = 120,
	LaunchPowerGrowth = 1.14,
	LaunchMaxPowerLevel = 200,

	-- TNT cost of the next power level: base × growth^level.
	PowerUpgradeBaseCost = 25,
	PowerUpgradeCostGrowth = 1.16,

	-- ----- What stars buy -----
	-- The squishy collection's second job. Each star adds a fraction to
	-- muzzle power and to the magnet, so the two halves of the game feed each
	-- other. Both capped, or a maxed collection trivialises the cannon.
	LaunchPowerPerStar = 0.01,
	LaunchMaxStarPower = 0.3,
	LaunchMagnetPerStar = 0.02,
	LaunchMaxStarMagnet = 1.5,

	-- ----- Pickups -----
	-- TNT, coins and gems strung along the flight path, laid out fresh after
	-- every shot. The server places them, decides which ones the path actually
	-- passed close enough to, and pays for them; the client only draws them.
	LaunchPickupCount = 26,

	-- Odds a given pickup is each kind. TNT is the common one because it is
	-- what buys the next power level; gems are the rare treat.
	PickupGemChance = 0.07,
	PickupCoinChance = 0.33, -- the rest are TNT

	-- Base value of one pickup of each kind, before rebirth and pet bonuses.
	PickupTntValue = 3,
	PickupCoinValue = 12,
	PickupGemValue = 1,

	-- Pickups further down the track are worth more, by this fraction of
	-- their base value per 1000 studs out. Without it, a 50,000-stud run pays
	-- the same per pickup as a 500-stud one and the track stops mattering.
	PickupValuePer1kStuds = 0.35,

	-- How near the path has to pass to sweep a pickup up — quoted in the units
	-- the player actually SEES, not in game studs.
	--
	-- This matters more than it looks. A level-1 flight peaks around 45 studs
	-- up; a level-50 flight peaks around 33,000. A magnet fixed in game studs
	-- would be a generous sweep at the start and a rounding error later, and
	-- the minigame would quietly stop paying out as players got stronger. So
	-- the magnet is measured against MagnetReferenceHeight — the height the
	-- track is DRAWN at, whatever the real numbers — which keeps the hit rate
	-- steady near 37% at every power level and makes the reach on screen the
	-- reach that actually scores.
	LaunchPickupMagnet = 2,

	-- Must match STAGE_APEX in Scene.luau: that is what draws a flight's
	-- envelope at a constant height on screen, and this is what converts the
	-- magnet back out of those units. Change one and change the other.
	MagnetReferenceHeight = 26,

	-- Pickups spread between these fractions of the player's own expected
	-- shot, so the field always sits where they can actually reach and
	-- stretches down the track as their power grows.
	LaunchPickupNearFraction = 0.05,
	LaunchPickupFarFraction = 1.1,

	-- ----- VIP zones -----
	-- Bands of the track where pickups cluster and pay extra. Placed as
	-- fractions of the expected shot, so they move out with the player.
	VipZoneCount = 2,
	VipZoneWidthFraction = 0.08,
	VipZoneValueMultiplier = 4,
	VipZoneDensityMultiplier = 3,

	-- ----- Milestones -----
	-- Signs down the track. Passing one for the FIRST time pays its gem
	-- bounty once, which is the main early source of gems.
	DistanceMilestones = {
		{ at = 100, name = "100", gems = 1 },
		{ at = 1000, name = "1K", gems = 3 },
		{ at = 10000, name = "10K", gems = 10 },
		{ at = 100000, name = "100K", gems = 40 },
		{ at = 1000000, name = "1M", gems = 150 },
	},

	-- ===== Rebirth =====
	-- Spends everything the cannon has earned for a permanent multiplier.
	-- Coins, TNT and the power level all reset; gems, squishies and the distance
	-- record do not.

	-- Distance needed for the first rebirth, multiplied by this growth for
	-- every rebirth already taken.
	RebirthBaseRequirement = 5000,
	RebirthRequirementGrowth = 6,

	-- What each rebirth permanently adds, as a fraction. Distance is the
	-- headline; the other two stop the reset feeling like a step backwards.
	RebirthDistanceBonus = 0.4,
	RebirthCoinBonus = 0.6,
	RebirthTntBonus = 0.5,

	-- ===== Rain TNT (the active boost) =====
	-- A button that floods the next shot's track with extra TNT. Short, loud
	-- and on a long cooldown, so it is a decision rather than a rotation.
	BoostSeconds = 20,
	BoostCooldownSeconds = 120,
	BoostPickupMultiplier = 3,
	BoostDensityMultiplier = 2,

	-- ===== The range on the ground =====
	-- The rainbow bands painted across the plain, and the mapping that puts a
	-- flight on them. Both the island (which builds the rings) and the flight
	-- animation (which flies over them) read these, so a squishy passing the
	-- "10K Studs" band has genuinely flown ten thousand studs.
	--
	-- The mapping is LOGARITHMIC, and it has to be: distances run from a
	-- couple of hundred studs to seven figures, and no linear scale shows both
	-- ends of that. On a log scale each band is a power of ten and every
	-- upgrade moves you a visible step, which is exactly the feedback a
	-- simulator needs.
	RangeNearRadius = 300, -- world studs from the island centre to the first band
	RangeFarRadius = 1000, -- ...and to the last one
	RangeNearStuds = 100, -- the game distance the first band means
	RangeFarStuds = 1000000, -- ...and the last

	-- The bands themselves. Rainbow, near to far, so "how far did it get" is
	-- answerable at a glance by which colour it sailed over.
	RangeBands = {
		{ studs = 100, name = "100" },
		{ studs = 250, name = "250" },
		{ studs = 500, name = "500" },
		{ studs = 1000, name = "1K" },
		{ studs = 5000, name = "5K" },
		{ studs = 10000, name = "10K" },
		{ studs = 50000, name = "50K" },
		{ studs = 100000, name = "100K" },
		{ studs = 1000000, name = "1M" },
	},

	-- ===== Worlds =====
	-- Retunes of the same valley rather than separate maps: a world changes
	-- the palette of the ground and the canyon and multiplies what the track
	-- pays, and is unlocked by rebirths. One table drives both the Worlds
	-- panel and the colours the stage paints itself, so adding an entry here
	-- is the whole job.
	Worlds = {
		{
			id = "meadow",
			name = "Sunny Meadow",
			rebirths = 0,
			multiplier = 1,
			grass = Color3.fromRGB(138, 214, 74),
			grassDark = Color3.fromRGB(112, 190, 58),
			canyon = Color3.fromRGB(226, 118, 118),
		},
		{
			id = "sunset",
			name = "Sunset Mesa",
			rebirths = 3,
			multiplier = 1.5,
			grass = Color3.fromRGB(238, 176, 96),
			grassDark = Color3.fromRGB(214, 148, 72),
			canyon = Color3.fromRGB(168, 86, 148),
		},
		{
			id = "frost",
			name = "Frostbite Pass",
			rebirths = 5,
			multiplier = 2.2,
			grass = Color3.fromRGB(214, 238, 248),
			grassDark = Color3.fromRGB(178, 214, 236),
			canyon = Color3.fromRGB(120, 158, 206),
		},
	},

	-- ===== Active squishies =====
	-- The squishies ARE the pets. Summon up to this many and they follow you
	-- around and buff the cannon, which is what joins the two halves of the
	-- game together: you launch to earn squishies, and squishies make you
	-- launch further.
	MaxActiveSquishies = 3,

	-- Each active squishy's bonus scales with its RARITY RANK (Common 1 ...
	-- Mythical 6) and again with its stars, so both the collecting loop and
	-- the prestige loop pay into the launcher. A Mythical is six times the
	-- squishy a Common is, and a maxed one is nearly twice that again.
	ActiveSquishyPowerPerRank = 0.06,
	ActiveSquishyCoinPerRank = 0.08,
	ActiveSquishyTntPerRank = 0.07,
	-- Magnet is FLAT screen studs, not a fraction — see LaunchPickupMagnet.
	ActiveSquishyMagnetPerRank = 0.12,
	ActiveSquishyStarBonus = 0.15,

	-- ===== The steamer shop =====
	-- What cash and gems are for. Both buy steamers, which is the whole point:
	-- the launcher's currencies feed the collection, and the collection feeds
	-- the launcher back through active squishies.

	-- Cash price of a plain steamer, times growth for every one already
	-- bought. Geometric, because cash income grows geometrically too.
	SteamerCoinCost = 900,
	SteamerCostGrowth = 1.09,

	-- Gems buy a Lucky Steamer instead: same odds SHAPE, but nothing below
	-- this rarity rank can come out of it (3 = Rare or better).
	LuckySteamerGemCost = 18,
	LuckySteamerMinRank = 3,

	-- ===== The lobby =====
	-- Every launch is broadcast to the whole server so everyone at the cannon
	-- base can watch it fly. This is how many recent ones the feed lists.
	LobbyFeedSize = 6,
	-- How many other players' shots may be in the air at once. Beyond this the
	-- oldest is recycled, so a busy server can't fill the valley with ghosts.
	LobbyMaxGhosts = 6,

	-- ===== King of the Steamer (the shared minigame) =====
	-- Goal for a server of one, plus this much for every player beyond the
	-- first. Scaling on player count is what keeps it beatable alone without
	-- being over in seconds when twenty people pile on.
	KingBaseGoal = 60,
	KingGoalPerPlayer = 45,

	-- ----- The event timer -----
	-- King of the Steamer is an EVENT now, not a permanent button. It runs on
	-- the clock so the whole server converges on the plaza for it, which is
	-- the only thing that makes a shared bar feel shared.

	-- How often a round starts, measured start-to-start.
	KingEventInterval = 300,

	-- How long a round lasts once it opens. Short, so it is a scramble.
	KingRoundSeconds = 30,

	-- Seconds before the start to begin warning people, so somebody deep in
	-- the squishy menu has time to walk back to the plaza.
	KingWarningSeconds = 45,

	-- The countdown only calls out at these marks rather than every second —
	-- a notification a second is noise, not urgency.
	KingCallouts = { 45, 30, 15, 10, 5, 3, 2, 1 },

	-- How far from the middle of the plaza still counts as being at the event.
	-- Slightly under the plaza's own radius, so standing on the very rim does
	-- not qualify. The server measures this; the UI only mirrors it.
	KingPlazaRadius = 58,

	-- Breather between rounds, so a win can be read before the next starts.
	KingCooldownSeconds = 15,

	-- Progress broadcasts per second, at most. Firing on every click would
	-- mean hundreds of remote calls a second on a busy server.
	KingBroadcastsPerSecond = 5,

	-- Per-player click ceiling for the shared steamer, same idea as the
	-- personal one.
	KingClicksPerSecond = 20,

	-- ===== Debug menu =====
	-- The debug menu is Studio-only: in a published game the server never even
	-- creates the remote that powers it, so there is nothing for an exploiter
	-- to call. Put your UserId here to also reach it on a live server while
	-- testing — and take it back out before you tell anyone about the game.
	DebugUserIds = {} :: { number },

	-- ===== Saving =====
	AutoSaveInterval = 60,

	-- v2: the save format changed completely with the steamer update,
	-- so we use a fresh datastore rather than colliding with old saves.
	DataStoreName = "SquishyClicker_v2",
}

-- How far out from the island centre a given game distance sits, in world
-- studs. Logarithmic — see RangeNearRadius for why.
--
-- This lives here as a function rather than as a formula copied into the
-- island and again into the flight animation, because those two agreeing is
-- the entire point: if they drift, a squishy sails over the "10K" band having
-- flown four hundred studs and the range stops meaning anything.
function Config.rangeRadius(studs: number): number
	local near, far = Config.RangeNearStuds, Config.RangeFarStuds
	if studs <= 0 then
		return 0
	end
	if studs < near then
		-- Below the first band there is no room for a decade, so the last
		-- stretch into the cannon is drawn straight.
		return studs / near * Config.RangeNearRadius
	end

	local span = math.log(far / near, 10)
	local along = math.clamp(math.log(studs / near, 10) / span, 0, 1)
	return Config.RangeNearRadius + along * (Config.RangeFarRadius - Config.RangeNearRadius)
end

return Config
