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
	-- The only thing stopping the cannon from out-earning the steamer, so it
	-- is the number to raise if launching ever feels like the better loop.
	LaunchCooldownSeconds = 15,

	-- Clicks of steamer progress a dead-centre shot pays.
	LaunchBullseyeBonus = 10,

	-- How far out the bullseye sits, and how wide each scoring ring is.
	LaunchTargetDistance = 70,
	LaunchRingWidth = 7,

	-- What each ring pays as a fraction of the bullseye, centre outwards.
	-- Miss past the last one and the shot is worth nothing.
	LaunchRingPays = { 1.0, 0.6, 0.35, 0.15 },

	-- Muzzle speed at full power and the gravity the shot falls under. Range
	-- works out at speed^2 * sin(2 * angle) / gravity, so these two together
	-- decide whether the target is even reachable — 90/90 puts maximum range
	-- at 90 studs, comfortably past the 70-stud bullseye.
	LaunchSpeed = 90,
	LaunchGravity = 90,

	-- A limp shot still leaves the barrel: power maps onto this fraction of
	-- muzzle speed upwards, rather than starting from nothing.
	LaunchMinPowerFraction = 0.35,

	-- The angle dial sweeps between these, in degrees.
	LaunchMinAngle = 15,
	LaunchMaxAngle = 75,

	-- Stars' SECOND job: every star adds this fraction to muzzle speed, so a
	-- prestiged collection reaches further. Capped, or late players can't miss.
	LaunchPowerPerStar = 0.01,
	LaunchMaxStarPower = 0.3,

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
