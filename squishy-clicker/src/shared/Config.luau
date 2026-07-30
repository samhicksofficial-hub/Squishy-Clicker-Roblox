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
