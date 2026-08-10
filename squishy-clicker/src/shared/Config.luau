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

	-- Cash cost of the next power level:
	--   base × growth^level × quadGrowth^(level²)
	-- Two regimes on purpose. Early, the plain growth rules and levels stay
	-- cheap (Lv 0 ≈ 120, Lv 10 ≈ 365, Lv 25 ≈ 3.5K) — the start feels like
	-- accelerating. Then the quadratic term takes over and each level's
	-- growth RATE itself climbs: ≈10% per level at Lv 0, ≈29% at Lv 50,
	-- ≈50% by Lv 99 (Lv 50 ≈ 770K, Lv 75 ≈ 1.2B, Lv 100 ≈ 15T). Income
	-- only grows ~14% a level, so the late curve is a wall by construction —
	-- worlds, rebirths, stars and the collection bonus are what breach it.
	-- Which is to say: playing the game does, and buying alone does not.
	PowerUpgradeBaseCost = 120,
	PowerUpgradeCostGrowth = 1.1,
	PowerUpgradeCostQuadGrowth = 1.0016,

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

	-- ===== The flight corridor =====
	-- Your own shot plays in a private, client-local walled corridor — the
	-- lane-runner treadmill: the squishy stays near a fixed origin while
	-- pooled floor tiles, canyon walls and distance boards scroll past at
	-- TRUE 1:1 studs. Endless by construction: no streaming, no float
	-- precision limits, no far edge. Every number a board shows is the real
	-- sim distance.
	CorridorStudsPerLane = 1.6, -- lane units → studs; FIXED (the old range scaled this with distance)
	CorridorFloorWidth = 72, -- wall to wall; wider than the ±24-stud steer span so walls threaten, never block
	CorridorWallHeight = 170, -- taller than the arc ceiling + camera height: the frame never sees over the rim
	CorridorArcCeiling = 130, -- arcs draw at min(this / real peak, 1): small shots 1:1, huge ones compressed to fit
	CorridorTileLength = 64, -- floor/wall segment length; the view window ÷ this sizes the pools
	CorridorViewAhead = 900, -- studs drawn ahead; the fog wall sits here
	CorridorViewBehind = 160, -- studs kept behind, so a bounce just passed doesn't visibly vanish
	CorridorMarkerCount = 14, -- distance boards per flight; spacing snaps to a 1/2.5/5 ladder of REAL studs
	CorridorCutDelay = 0.35, -- seconds of island ignition (smoke, flash, bang) before the hard cut to the corridor

	-- ===== Mid-air controls =====
	-- The flight itself never changed hands: distance, the arc and the
	-- fire-time magnet sweep are still the server's closed-form arithmetic.
	-- What steering adds is a LATERAL game on top — pickups sit across a
	-- lane now, the player steers the replay through them (and away from
	-- bombs), and the claims are settled AFTER landing, validated against
	-- what the steering speed could physically have reached in the time the
	-- flight allowed. A claim the physics couldn't make is simply not paid.
	SteerHalfWidth = 15, -- LANE UNITS either side of the centre line (see CorridorStudsPerLane)
	SteerSpeed = 26, -- lane units/sec — the client's control AND the server's reachability check
	ClaimLaneSlack = 6, -- forgiveness in that check, so honest play never loses a claim to rounding
	ClaimHeightWindow = 60, -- vertical generosity when validating a claimed pickup against the arc
	LaneTouchWidth = 3.4, -- lane units within which a crossed pickup counts as touched

	-- The fraction of pickups laid dead on the centre line, where the
	-- fire-time magnet still sweeps them passively. The rest spread UNIFORM
	-- across the full lane width, edges included — flying straight earns the
	-- floor, and the sides are where the money actually lives.
	PickupCentreFraction = 0.25,

	-- Manual ground slam: SPACE (or a screen tap) dives the squishy into the
	-- ground and bursts the cash near the impact point off the track.
	SlamMaxPerFlight = 3,
	SlamRadiusFraction = 0.05, -- of the shot's distance...
	SlamRadiusMin = 12, -- ...but never tighter than this, in sim studs
	SlamLaneRadius = 14,

	-- ===== Boost Boots =====
	-- Floating green up-arrows on the track. Steering through one kicks the
	-- squishy skyward and pays a Cash bonus (scaled by how far out it sits,
	-- like every pickup, then by the full cash multiplier stack). The kick
	-- is a real little arc — an upward IMPULSE integrated against its own
	-- gravity — so the ride up is smooth and the fall back is earned, never
	-- a teleport.
	BootCount = 2,
	BootCash = 150,
	BootImpulse = 85, -- world studs/sec of upward kick on touch
	BootGravity = 90, -- studs/sec² pulling that kick back down (~40-stud arc)

	-- ===== Bombs =====
	-- Cartoon bombs. Hitting one knocks the squishy down and cuts the
	-- flight bonus — every hit multiplies the claim by (1 - this). Placed
	-- on a density RAMP: sparse in the opening stretch, crowding toward
	-- the far end, and never dead-centre in the opening third.
	BombCount = 10,
	BombClaimPenalty = 0.2,

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

	-- The reference envelope height the server's effectiveMagnet normalizes
	-- the field's tallest pickup against — what turns the screen-unit magnet
	-- into sim studs at any power level. Server-side only.
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

	-- ===== Worlds =====
	-- Retunes of the same valley rather than separate maps: a world changes
	-- the palette of the ground and the canyon and multiplies what the track
	-- pays, and is unlocked by CANNON LEVEL. The gates sit where the upgrade
	-- curve's accelerating growth starts to bite (see PowerUpgradeCost*):
	-- around 50 the quadratic term is charging ~29% a level against income's
	-- ~14%, and Sunset's ×30 is the relief; past 100 the curve is a cliff on
	-- purpose and Frostbite's ×900 plus rebirths are what climb it. One
	-- table drives both the Worlds panel and the colours the stage paints
	-- itself, so adding an entry here is the whole job.
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

	-- ===== The cash icon =====
	-- The kawaii cash-stack image, everywhere Cash shows its face: the
	-- wallet chip, the flying bills, and the pickups on the track. Upload
	-- the PNG as a Decal on the Creator Hub and paste its asset id here as
	-- "rbxassetid://NNNNNNN". While this is empty the 💵 emoji stands in,
	-- so nothing breaks before the upload happens. (VIP pickups keep their
	-- 💰 either way — the jackpot stretch is supposed to look different.)
	CashIconImage = "rbxassetid://131728154516680",

	-- ===== The sky =====
	-- The realistic sky ("AtmosphericClouds2"), owned by CODE: the server
	-- rebuilds it from these ids at every startup, so it can never vanish
	-- with the place file again — which is how it was lost the first time.
	-- The ids came off the adopted Sky instance's own printout, and each was
	-- verified against the asset's face name (Ft/Rt are assigned the way the
	-- pack's author shipped them, which is what rendered correctly).
	SkyTextures = {
		Bk = "http://www.roblox.com/asset/?id=150335574",
		Dn = "http://www.roblox.com/asset/?id=150335585",
		Ft = "http://www.roblox.com/asset/?id=150335628",
		Lf = "http://www.roblox.com/asset/?id=150335620",
		Rt = "http://www.roblox.com/asset/?id=150335610",
		Up = "http://www.roblox.com/asset/?id=150335642",
		SunAngularSize = 21,
		MoonAngularSize = 11,
	},

	-- ===== The collection bonus =====
	-- Discovering squishies pays a permanent Cash bonus that grows with how
	-- much of the CATALOG has been met, topping out at this with every
	-- squishy found. A fraction of the catalog rather than per-head, so
	-- adding squishies later never inflates the cap — each face is just
	-- worth a little less of the same +50%. Dupes feed stars; a NEW face
	-- feeds this, forever.
	CollectionCashMax = 0.5,

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
	-- Every launch is broadcast to the whole server; the feed lists this
	-- many recent ones. Text only now — flights play in private corridors,
	-- so the feed is the lobby's whole window onto other people's shots.
	LobbyFeedSize = 6,

	-- ===== Sprinting =====
	-- Hold Shift to run. Client-side, like all character movement; nothing
	-- on the island is speed-gated, so there is nothing to validate.
	WalkSpeed = 16,
	SprintSpeed = 26,

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

return Config
