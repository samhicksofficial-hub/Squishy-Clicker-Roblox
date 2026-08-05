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
	-- A DISTANCE game: one shot, one flight, and how far you get IS the score.
	-- Two numbers decide the whole minigame's earning rate between them — how
	-- far a good shot travels (the arc numbers) and what a stud is worth
	-- (LaunchClicksPerStud). Tune those two before touching anything else.

	-- The only thing stopping the cannon from out-earning the steamer, so it
	-- is the number to raise if launching ever feels like the better loop.
	LaunchCooldownSeconds = 15,

	-- What one stud of distance pays in steamer clicks. A well-aimed shot at
	-- full power travels about 95 studs with the arc numbers below, so this is
	-- roughly 11 clicks before pickups and the zone multiplier are added.
	LaunchClicksPerStud = 0.12,

	-- Muzzle speed at full power, and the gravity the shot arcs under. These
	-- two set the height and the length of the ballistic half of the flight;
	-- everything else scales off them.
	LaunchSpeed = 90,
	LaunchGravity = 90,

	-- A limp shot still leaves the barrel: power maps onto this fraction of
	-- muzzle speed upwards, rather than starting from nothing.
	LaunchMinPowerFraction = 0.35,

	-- The angle dial sweeps between these, in degrees.
	LaunchMinAngle = 15,
	LaunchMaxAngle = 75,

	-- ----- The glide -----
	-- At the top of the arc the squishy stops falling and GLIDES: it drifts
	-- forward while sinking, and the ground covered doing that is most of a
	-- long shot. Glide time grows with how high the apex was, and that is what
	-- stops the angle dial having one obvious right answer — a flat shot
	-- travels further before the apex, a steep one glides longer after it, and
	-- the best angle sits between the two (around 48° with these numbers).
	LaunchGlideSeconds = 0.6,
	LaunchGlideSecondsPerStud = 0.04,

	-- Fraction of forward speed kept while gliding. Below 1, or the ballistic
	-- half of the flight stops mattering and every shot is a flat one.
	LaunchGlideSpeedFactor = 0.55,

	-- ----- What stars buy -----
	-- Stars' SECOND job. Each adds a fraction to muzzle speed and to the
	-- magnet, so a prestiged collection flies further AND sweeps up more on
	-- the way. Both capped, or a late player cannot help but max every shot.
	LaunchPowerPerStar = 0.01,
	LaunchMaxStarPower = 0.3,
	LaunchMagnetPerStar = 0.03,
	LaunchMaxStarMagnet = 1,

	-- ----- Mid-air pickups -----
	-- Sweets floating down the range, laid out fresh after every shot. The
	-- server places them, decides which ones the arc actually touched, and
	-- pays for them; the client only ever draws them.
	LaunchPickupCount = 12,
	LaunchPickupValue = 3, -- clicks each
	LaunchPickupGoldenValue = 12, -- the rare one worth bending a shot for
	LaunchPickupGoldenChance = 0.12,

	-- How near the arc has to pass to sweep one up, in studs, before stars.
	LaunchPickupMagnet = 3,

	-- Pickups are spread between these fractions of the player's own best
	-- possible shot, so the field always sits where they can actually reach —
	-- it stretches further down the range as their stars grow.
	LaunchPickupNearFraction = 0.12,
	LaunchPickupFarFraction = 1.05,

	-- ----- Zones -----
	-- Distance milestones down the range. Landing in one multiplies the WHOLE
	-- payout, pickups included, so a longer shot is worth more than just its
	-- extra studs. `from` is in game studs and must ascend.
	LaunchZones = {
		{ from = 0, name = "Shop Floor", multiplier = 1 },
		{ from = 40, name = "Toy Aisle", multiplier = 1.15 },
		{ from = 70, name = "The Big Window", multiplier = 1.3 },
		{ from = 110, name = "Out the Door", multiplier = 1.5 },
		{ from = 160, name = "Over the Rooftops", multiplier = 1.8 },
	},

	-- ===== King of the Steamer (the shared minigame) =====
	-- Goal for a server of one, plus this much for every player beyond the
	-- first. Scaling on player count is what keeps it beatable alone without
	-- being over in seconds when twenty people pile on.
	KingBaseGoal = 60,
	KingGoalPerPlayer = 45,

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
