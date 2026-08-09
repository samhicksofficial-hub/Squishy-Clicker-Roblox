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

	-- The angle span the launch fraction maps across, in degrees. 45 is the
	-- best angle for a pure arc, but bounces reward flatter shots, so the
	-- sweet spot sits a little under it.
	LaunchMinAngle = 15,
	LaunchMaxAngle = 75,

	-- ----- The precision meter -----
	-- Aiming is a timing game now: a needle sweeps a red-yellow-green bar and
	-- every tap locks in how close to the green centre it was. The AVERAGE of
	-- the taps is the power sent to the server, so one lucky tap cannot carry
	-- a shot and one slip cannot sink it.
	LaunchTapsRequired = 3,

	-- Full needle sweeps per second. Faster is harder: the green window
	-- passes under the needle more often but for less time.
	LaunchNeedleHz = 0.55,

	-- Each locked tap multiplies the sweep speed by this, so a shot gets
	-- harder as it goes: the first tap is the read, the last is the test.
	-- At 1.35 the third tap sweeps at nearly double the first's speed.
	LaunchNeedleGrowth = 1.35,

	-- The launch elevation, as the same 0-1 fraction of the angle span the
	-- old dial sent. Fixed since the meter took over aiming: the skill moved
	-- into tap timing, and 0.55 (about 48 degrees) is the sweet spot the old
	-- dial was hiding anyway. The server still validates it like any hostile
	-- payload — this is a default the client sends, not a rule it enforces.
	LaunchFixedAngle = 0.55,

	-- ----- Flight feel (client-side FX tuning) -----
	-- The chase camera's field of view: base at rest, plus this much stretch
	-- at full launch speed (70 up to 92). It eases rather than jumps —
	-- ChaseFovSmoothing is how quickly it chases its target, per second — and
	-- snaps back toward base on every bounce, which is most of what makes an
	-- impact feel like one.
	ChaseFovBase = 70,
	ChaseFovBoost = 22,
	ChaseFovSmoothing = 6,

	-- Impact shake: a damped sine on the camera, amplitude scaled by how fast
	-- the squishy was going when it hit. Magnitude in studs; damping is the
	-- exponential decay rate; Hz is the wobble frequency.
	ImpactShakeMagnitude = 1.6,
	ImpactShakeDamping = 6,
	ImpactShakeHz = 7,

	-- The wind trail only draws above this fraction of launch speed: a trail
	-- on a slow roll reads as a glitch, not as speed.
	WindTrailMinSpeedFraction = 0.45,

	-- The paint splat left where the squishy hits: its size and how long it
	-- takes to fade off the grass.
	LaunchSplatRadius = 7,
	LaunchSplatFadeSeconds = 2.4,

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
	-- Power is bought in levels with Cash and grows geometrically, which is
	-- what lets distances climb from a few hundred studs to six figures
	-- without the level number becoming absurd.
	LaunchBasePower = 120,
	LaunchPowerGrowth = 1.14,
	LaunchMaxPowerLevel = 200,

	-- Cash cost of the next power level: base × growth^level. The growth
	-- deliberately OUTPACES the 1.14 the power (and so the income) grows by:
	-- every level takes ≈1.07× longer than the last, compounding. That
	-- compounding IS the world schedule — by level ~50 an upgrade takes ~30×
	-- what it did fresh, which is exactly the ×30 Sunset Mesa pays; by ~100
	-- the wall is ~900× and Frostbite Pass picks it up. Levels 50 and 100
	-- are where moving worlds should FEEL necessary, and the world gates
	-- below sit on the same numbers.
	PowerUpgradeBaseCost = 40,
	PowerUpgradeCostGrowth = 1.22,

	-- ----- What stars buy -----
	-- The squishy collection's second job. Each star adds a fraction to
	-- muzzle power and to the magnet, so the two halves of the game feed each
	-- other. Both capped, or a maxed collection trivialises the cannon.
	LaunchPowerPerStar = 0.01,
	LaunchMaxStarPower = 0.3,
	LaunchMagnetPerStar = 0.02,
	LaunchMaxStarMagnet = 1.5,

	-- ----- Pickups -----
	-- Cash strung along the flight path, laid out fresh after every shot.
	-- The server places it, decides what the path actually passed close
	-- enough to, and pays for it; the client only draws it. One currency on
	-- purpose: everything a shot earns competes for the same wallet, so
	-- upgrading the cannon and buying steamers are a real choice.
	LaunchPickupCount = 26,

	-- Base value of one pickup, before every bonus.
	PickupCoinValue = 15,

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
	-- Signs down the track. Passing one for the FIRST time pays its Cash
	-- bounty once — a fat one-off on top of ordinary track income.
	DistanceMilestones = {
		{ at = 100, name = "100", cash = 250 },
		{ at = 1000, name = "1K", cash = 2500 },
		{ at = 10000, name = "10K", cash = 25000 },
		{ at = 100000, name = "100K", cash = 250000 },
		{ at = 1000000, name = "1M", cash = 2500000 },
	},

	-- ===== Rebirth =====
	-- Spends everything the cannon has earned for a permanent multiplier.
	-- Cash and the power level reset; squishies, milestones and the distance
	-- record do not.

	-- Distance needed for the first rebirth, multiplied by this growth for
	-- every rebirth already taken.
	RebirthBaseRequirement = 5000,
	RebirthRequirementGrowth = 6,

	-- What each rebirth permanently adds, as a fraction. Distance is the
	-- headline; the Cash bonus stops the reset feeling like a step backwards.
	RebirthDistanceBonus = 0.4,
	RebirthCoinBonus = 0.6,

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
	-- pays, and is unlocked by CANNON LEVEL. The gates sit exactly on the
	-- upgrade curve's walls (see PowerUpgradeCostGrowth): the ×30 and ×900
	-- are sized to cancel how far costs have outrun income by the time each
	-- gate opens, so a new world makes upgrades affordable again rather than
	-- merely bigger-numbered. One table drives both the Worlds panel and the
	-- colours the stage paints itself, so adding an entry here is the job.
	Worlds = {
		{
			id = "meadow",
			name = "Sunny Meadow",
			level = 0,
			multiplier = 1,
			grass = Color3.fromRGB(138, 214, 74),
			grassDark = Color3.fromRGB(112, 190, 58),
			canyon = Color3.fromRGB(226, 118, 118),
		},
		{
			id = "sunset",
			name = "Sunset Mesa",
			level = 50,
			multiplier = 30,
			grass = Color3.fromRGB(238, 176, 96),
			grassDark = Color3.fromRGB(214, 148, 72),
			canyon = Color3.fromRGB(168, 86, 148),
		},
		{
			id = "frost",
			name = "Frostbite Pass",
			level = 100,
			multiplier = 900,
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
	-- Magnet is FLAT screen studs, not a fraction — see LaunchPickupMagnet.
	ActiveSquishyMagnetPerRank = 0.12,
	ActiveSquishyStarBonus = 0.15,

	-- ===== The sky =====
	-- The realistic sky, owned by CODE once its texture ids are known. A Sky
	-- instance living only in the place file kept vanishing between Studio
	-- sessions; with the ids filled in here the server rebuilds it at every
	-- startup and nothing can lose it again. While this is false, the server
	-- falls back to adopting whatever Sky instance it finds — and prints
	-- this exact line, filled in, to the Output. Paste that over this.
	SkyTextures = false,

	-- ===== The collection bonus =====
	-- Every DISTINCT squishy ever discovered adds this to the Cash
	-- multiplier, permanently — dupes feed stars, but a NEW face pays for
	-- itself forever. This is the standing reason to keep buying steamers
	-- long after a serviceable team exists.
	CollectionCashPerSquishy = 0.03,

	-- ===== Main-squishy abilities =====
	-- The EQUIPPED squisher is the one that goes down the barrel, so what it
	-- is shapes the shot (which ability each squishy has lives in
	-- Squishies.luau). Every ability scales off the same strength:
	--   strength = rarity rank * (1 + its stars * AbilityStarBonus)
	-- so a Common butter slides a little and a starred Legendary butter is a
	-- bar of soap. Rates are per point of strength (Mythical rank 6, five
	-- stars ≈ strength 10.5).
	AbilityStarBonus = 0.15,
	AbilitySlidePerRank = 0.15, -- landing roll distance +15% each
	AbilityBouncePerRank = 0.01, -- restitution +0.01 each, capped below
	AbilityBounceCap = 0.82, -- past this the shot barely comes down
	AbilityFloatPerRank = 0.03, -- gravity divided by (1 + this * strength)
	AbilityPowerPerRank = 0.02, -- launch power +2% each
	AbilityWealthPerRank = 0.04, -- shot Cash +4% each
	AbilityMagnetPerRank = 0.06, -- flat magnet screen studs each

	-- ===== The lobby =====
	-- Every launch is broadcast to the whole server so everyone at the cannon
	-- base can watch it fly. This is how many recent ones the feed lists.
	LobbyFeedSize = 6,
	-- How many other players' shots may be in the air at once. Beyond this the
	-- oldest is recycled, so a busy server can't fill the valley with ghosts.
	LobbyMaxGhosts = 6,

	-- ===== King of the Steamer (the shared minigame) =====
	-- The round is a race, not a shared bar: whoever clicks the most wins the
	-- crown — but only if they got over this many clicks. A dead round where
	-- the "winner" tapped a dozen times shouldn't hand out the rarest roll.
	KingCrownClicks = 100,

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
