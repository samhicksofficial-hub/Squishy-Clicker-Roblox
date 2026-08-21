--!strict
-- Central game tuning. Change numbers here rather than hunting through scripts.

local Config = {
	-- ===== The steamer =====
	-- Clicks needed to open the steamer when you have zero stars.
	BaseClicksToOpen = 10,

	-- The steamer can never get faster than this many clicks.
	MinClicksToOpen = 3,

	-- THE TREADMILL: every steamer you EARN — opened or still banked in the
	-- tray — makes the next one cost this many more clicks, forever. Earning
	-- 20 steamers adds 20 clicks to the price, the moment each bar fills.
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
	-- to be won by launching. (Cut from 0.004 when flights went endless — at
	-- the old rate one good run banked several baskets on its own.)
	LaunchClicksPerStud = 0.0012,

	-- The hard lid on that: however far a flight goes, it can never feed the
	-- steamer more than this fraction of the CURRENT basket's click cost.
	-- Scale-proof where a flat cap is not — the treadmill raises the cost,
	-- and the lid rises with it while staying under half a basket per shot.
	SteamerFlightCapFraction = 0.4,

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

	-- ----- The rhythm aim -----
	-- BELOW RhythmPowerReference the cannon simply fires at full power — no
	-- timing game, no timer on screen. AT the reference the rhythm duel
	-- begins: numbered circles appear one after another at random spots,
	-- each with an approach ring shrinking onto it, and every press is
	-- scored by how CLOSED the ring was at that instant. The
	-- AVERAGE of the catches is the power sent to the server, so one lucky
	-- catch cannot carry a shot and one slip cannot sink it.
	LaunchTapsRequired = 3,

	-- The launch elevation, as the same 0-1 fraction of the angle span the
	-- old dial sent. Fixed since the meter took over aiming: the skill moved
	-- into tap timing, and 0.55 (about 48 degrees) is the sweet spot the old
	-- dial was hiding anyway. The server still validates it like any hostile
	-- payload — this is a default the client sends, not a rule it enforces.
	LaunchFixedAngle = 0.55,

	-- Where the duel begins, and how fast its ring closes: base pace AT the
	-- reference power, then LINEARLY faster — double the power, half the
	-- travel time — floored so the duel stays humanly winnable however
	-- monstrous the cannon gets.
	RhythmPowerReference = 50000,
	RhythmApproachSeconds = 1.15, -- ring travel time at the reference power
	RhythmApproachMinSeconds = 0.36, -- the speed cap

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

	-- ===== The living flight =====
	-- A shot has NO predetermined length. The old closed-form simulator
	-- survives only as the ECONOMY ORACLE: it prices what a power level is
	-- expected to cover, and Track.calibrate turns that expectation into
	-- forward momentum. From there the flight is a real simulation — boots
	-- relaunch it, bombs bleed it, and it ends when the roll runs out.
	--
	-- The vertical envelope is FIXED at human scale regardless of power
	-- (forward speed carries the progression), so the corridor ceiling,
	-- the object heights and the touch windows mean the same thing at
	-- level 1 and level 100.
	FlightGravity = 34, -- studs/s² in the live sim (see LaunchGravity for the oracle's own scale)
	FlightVyMin = 30, -- launch vertical speed across the angle span...
	FlightVyMax = 55, -- ...higher angle = longer hang, calibrated to the same expected distance
	FlightRollSeconds = 3, -- the landing roll decays over this long, whatever the speed
	FlightEndSpeed = 10, -- rolling slower than this is the end of the flight
	FlightMaxSeconds = 240, -- hard safety cap; an honest run of chained boosts never meets it

	-- ----- The endless track -----
	-- The field is CHUNKS, generated deterministically from a per-shot seed
	-- by shared/Track.luau. The client generates chunks to draw them; the
	-- server regenerates the same chunks to validate and pay them. However
	-- far a flight goes, there is always more track.
	ChunkLength = 400, -- studs of track per chunk
	ChunkCashCount = 10, -- cash pickups per chunk (plus any VIP cluster)
	ChunkVipChance = 0.18, -- odds a chunk carries a 5-pickup golden knot

	-- Base value of one pickup, before every bonus.
	PickupCoinValue = 15,

	-- Pickups further down the track are worth more, by this fraction of
	-- their base value per 1000 studs out. Without it, a 50,000-stud run pays
	-- the same per pickup as a 500-stud one and the track stops mattering.
	-- (Trimmed from 0.35: track income grows roughly with distance SQUARED —
	-- more pickups crossed, each worth more — while upgrade costs grow ~10%
	-- a level early. At 0.35 the mid-game bought itself in a sitting; this
	-- stretches the climb without touching the first hour's feel.)
	PickupValuePer1kStuds = 0.25,

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
	CorridorArcCeiling = 130, -- the walls contain every height the fixed vertical envelope can produce (boot peak ~106)
	CorridorTileLength = 64, -- floor/wall segment length; the view window ÷ this sizes the pools
	CorridorViewAhead = 900, -- studs drawn ahead; the fog wall sits here
	CorridorViewBehind = 160, -- studs kept behind, so a bounce just passed doesn't visibly vanish
	CorridorMarkerCount = 14, -- road numbers per EXPECTED flight; spacing snaps to a 1/2.5/5 ladder of REAL studs
	CorridorCutDelay = 0.35, -- seconds of island ignition (smoke, flash, bang) before the hard cut to the corridor

	-- The canyon walls either side of the corridor follow the RANGE
	-- HANDOVER (CorridorRangeUntil, below) rather than a switch of their
	-- own: over the painted rings there are no walls at all, because back
	-- on the island everyone else watches a GHOST of this same launch arc
	-- out over the range bands (see Range* below) and open water is the
	-- one story both views can share — then the biome lands past the
	-- handover rise as terraced cliffs, so leaving the sea for a walled
	-- valley IS the arrival. The terraces themselves are built and rolled
	-- per tile in Flight.luau (profileWalls).

	-- What the corridor is dressed as. "ocean" plays the flight over the
	-- SAME rainbow target painted around the island: the floor wears the
	-- ring band the shot's real distance is inside (same ladder, same
	-- colours — see Range* below) flat and level to the horizon either
	-- side, and the haze ahead is tinted the colour of the ring coming up.
	-- With the ghosts skipping over the island's rings at the same moments,
	-- the shooter's view and everyone else's tell ONE story — you really
	-- are firing off the island. "biomes" restores the old canyon lands
	-- (desert, frostlands, volcano, deep space).
	CorridorTheme = "ocean",

	-- How far the painted rings run before the biome lands take over. The
	-- rings are the ILLUSION and the illusion has a range: for the opening
	-- of a flight you really are still out over the island's own target,
	-- with the ghosts skipping the same rings at the same moments, and
	-- that is worth every stud. Past it the shot has genuinely left the
	-- island behind and the lands are the reward for getting there — which
	-- is why this sits exactly on the first biome's start (The Desert, at
	-- 1000, see CorridorBiomes) so the rings hand over to the sand on the
	-- stud the ladder already calls a milestone. Set to 0 for biomes from
	-- the first stud; set enormous to never leave the rings.
	CorridorRangeUntil = 1000,

	-- ----- Corridor biomes -----
	-- The land CHANGES as a flight gets far: each band begins at a real
	-- distance and repaints the floor, the canyon walls and the haze ahead.
	-- Band starts sit exactly on the milestone ladder on purpose — crossing
	-- 10K studs pays a bounty AND flies you somewhere that looks new, which
	-- is the sense of getting somewhere. The first band carries no colours:
	-- it wears the active World's palette, so world unlocks still repaint
	-- the opening stretch of every flight.
	CorridorBiomes = {
		{ at = 0, name = "Meadow", emoji = "🌱" },
		{
			at = 1000,
			name = "The Desert",
			emoji = "🏜️",
			floor = Color3.fromRGB(238, 206, 132),
			floorAlt = Color3.fromRGB(224, 186, 108),
			wall = Color3.fromRGB(216, 152, 92),
			lip = Color3.fromRGB(238, 206, 132),
			haze = Color3.fromRGB(248, 226, 180),
		},
		{
			at = 10000,
			name = "The Frostlands",
			emoji = "❄️",
			floor = Color3.fromRGB(214, 238, 248),
			floorAlt = Color3.fromRGB(184, 220, 240),
			wall = Color3.fromRGB(148, 196, 232),
			lip = Color3.fromRGB(230, 244, 252),
			haze = Color3.fromRGB(226, 242, 252),
		},
		{
			at = 100000,
			name = "The Volcano",
			emoji = "🌋",
			floor = Color3.fromRGB(96, 80, 80),
			floorAlt = Color3.fromRGB(78, 64, 64),
			wall = Color3.fromRGB(142, 72, 56),
			lip = Color3.fromRGB(236, 122, 60),
			haze = Color3.fromRGB(255, 152, 92),
		},
		{
			at = 1000000,
			name = "Deep Space",
			emoji = "🌌",
			floor = Color3.fromRGB(70, 66, 110),
			floorAlt = Color3.fromRGB(54, 50, 88),
			wall = Color3.fromRGB(44, 40, 72),
			lip = Color3.fromRGB(152, 132, 232),
			haze = Color3.fromRGB(28, 24, 50),
		},
	},

	-- ===== Mid-air controls =====
	-- The client steers its local sim and reports every touch as an event
	-- (what, when, which lane). At settle the server RE-RUNS the same sim,
	-- applying each claimed event only if the physics agree the shot was
	-- there: near the object's distance at that moment, near its height,
	-- and laterally REACHABLE — the gap between consecutive touches can
	-- never beat the steering speed times the time between them. A claim
	-- the physics couldn't make is simply not paid.
	SteerHalfWidth = 15, -- LANE UNITS either side of the centre line (see CorridorStudsPerLane)
	SteerSpeed = 26, -- lane units/sec — the client's control AND the server's reachability check
	ClaimLaneSlack = 6, -- forgiveness in that check, so honest play never loses a claim to rounding
	ClaimHeightWindow = 24, -- vertical generosity validating a touch against the re-simulated height
	ClaimDistanceSlackSeconds = 0.25, -- distance window per touch = max(80, vx × this): frame quantisation at speed
	LaneTouchWidth = 3.4, -- lane units within which a crossed pickup counts as touched

	-- The fraction of pickups laid dead on the centre line, where the
	-- fire-time magnet still sweeps them passively. The rest spread UNIFORM
	-- across the full lane width, edges included — flying straight earns the
	-- floor, and the sides are where the money actually lives.
	PickupCentreFraction = 0.25,

	-- Manual ground slam: SPACE (or a screen tap) dives the squishy into the
	-- ground and bursts the cash near the impact point off the track.
	SlamMaxPerFlight = 3,
	SlamDiveSpeed = 95, -- the dive's downward speed, in the live sim's studs/sec
	SlamRadiusFraction = 0.02, -- of the shot's distance...
	SlamRadiusMin = 12, -- ...never tighter than this, in sim studs...
	-- ...and never wider than this. The fraction alone was tuned for the
	-- bounded range; against endless flights it scaled into a vacuum that
	-- swept cash from thousands of studs away. A slam is a local burst.
	SlamRadiusMax = 90,
	SlamLaneRadius = 14,

	-- ===== Boost Boots =====
	-- Floating green up-arrows on the track, placed by the chunk generator
	-- (none in the opening chunk, thickening deeper in). Steering through
	-- one pays Cash AND genuinely relaunches the flight — the sim's
	-- vertical speed is refreshed, buying a whole extra hop of distance.
	-- A ground-line boot even rescues a shot already rolling out, which is
	-- the whole reason to keep steering at the end.
	BootCash = 150,
	BootImpulse = 85, -- studs/sec of upward speed a boot restores

	-- ===== Bombs =====
	-- Cartoon bombs, placed by the chunk generator on a density RAMP:
	-- none in the opening chunk, up to three per chunk deep in, and never
	-- dead-centre early. A hit costs twice — it bleeds the sim's forward
	-- speed (real distance, gone) and cuts the flight bonus by (1 - the
	-- penalty) per hit.
	BombClaimPenalty = 0.2,
	BombSpeedCut = 0.3, -- fraction of forward speed a hit bleeds

	-- The magnet, in LANE UNITS of the centre line. Any pickup lying within
	-- this many lane units of centre is swept automatically as the flight
	-- passes it — no steering required, no height test (it is a magnet).
	-- The client vacuums them visually as it crosses; the server pays every
	-- one along the settled distance without needing them claimed. Stars
	-- and summons widen it.
	LaunchPickupMagnet = 2,

	-- What a VIP-cluster pickup pays over an ordinary one. The clusters
	-- themselves come from the chunk generator (see ChunkVipChance).
	VipZoneValueMultiplier = 4,

	-- ----- Milestones -----
	-- Signs down the track. Passing one for the FIRST time pays its Cash
	-- bounty once — a fat one-off on top of ordinary track income.
	DistanceMilestones = {
		{ at = 100, name = "100", cash = 250 },
		{ at = 1000, name = "1K", cash = 2500 },
		{ at = 10000, name = "10K", cash = 25000 },
		{ at = 100000, name = "100K", cash = 250000 },
		{ at = 1000000, name = "1M", cash = 2500000 },
		{ at = 10000000, name = "10M", cash = 25000000 },
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

	-- ===== The range on the water, and the ghost launches =====
	-- The rainbow target from the shared-range era, BACK — painted on the
	-- ocean now, since the plain it used to cover became the sea. Filled,
	-- contiguous bands from the beach edge outward, rainbow near to far,
	-- with the distance printed flat on each band, exactly as it was.
	--
	-- The GHOSTS give the bands their job again: the moment anybody fires,
	-- everyone ELSE sees a ghost of their squishy blast out of that
	-- player's cannon, skip across the water, and splash down on the band
	-- its expected distance names. The shooter meanwhile plays their real,
	-- private corridor flight exactly as before — the illusion of a shared
	-- range, at none of the old shared range's cost. Island.luau paints the
	-- bands and client/Ghosts.luau flies the ghosts, both through
	-- Config.rangeRadius below, so a ghost always lands on the band its
	-- distance means.
	--
	-- The mapping is LOGARITHMIC, and it has to be: distances run from a
	-- couple of hundred studs to seven figures, and no linear scale shows
	-- both ends of that. On a log scale each band is a power of ten and
	-- every upgrade moves you a visible step.
	RangeNearRadius = 300, -- world studs from the island centre to the first band's edge
	RangeFarRadius = 1000, -- ...and to the last one (the sea disc itself ends at 1020)
	RangeNearStuds = 100, -- the game distance the first band means
	RangeFarStuds = 1000000, -- ...and the last

	-- The bands themselves. Rainbow, near to far, so "how far did it get" is
	-- answerable at a glance by which colour it splashed down on.
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

	-- How many other players' ghosts may be in the air at once (the oldest
	-- is dropped for the newest), and how big a ghost squishy is drawn.
	LobbyMaxGhosts = 4,
	GhostScale = 3,

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

-- How far out from the island centre a given game distance sits, in world
-- studs. Logarithmic — see RangeNearRadius for why.
--
-- This lives here as a function rather than as a formula copied into the
-- island and again into the ghosts, because those two agreeing is the entire
-- point: if they drift, a ghost splashes down on the "10K" band having flown
-- four hundred studs and the range stops meaning anything.
function Config.rangeRadius(studs: number): number
	local near, far = Config.RangeNearStuds, Config.RangeFarStuds
	if studs <= 0 then
		return 0
	end
	if studs < near then
		-- Below the first band there is no room for a decade, so the last
		-- stretch into the shore is drawn straight.
		return studs / near * Config.RangeNearRadius
	end

	local span = math.log(far / near, 10)
	local along = math.clamp(math.log(studs / near, 10) / span, 0, 1)
	return Config.RangeNearRadius + along * (Config.RangeFarRadius - Config.RangeNearRadius)
end

return Config
