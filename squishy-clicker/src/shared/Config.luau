--!strict
-- Central game tuning. Change numbers here rather than hunting through scripts.

local Config = {
	-- ===== The steamer =====
	-- Clicks needed to open the steamer when you have zero stars.
	BaseClicksToOpen = 10,

	-- The steamer can never get faster than this many clicks.
	MinClicksToOpen = 3,

	-- Every star you've earned (across ALL squishies) shaves this many clicks
	-- off the requirement. 0.25 means every 4 stars = 1 fewer click.
	-- THIS is why prestiging matters: your collection makes you faster.
	ClickReductionPerStar = 0.25,

	-- ===== Prestige (star-ups) =====
	MaxStars = 5,

	-- Copies needed for each star DOUBLE every level.
	-- (The per-rarity starting amounts live in Squishies.luau: Common 10 ... Mythical 3.)
	PrestigeGrowth = 2,

	-- ===== Saving =====
	AutoSaveInterval = 60,

	-- v2: the save format changed completely with the steamer update,
	-- so we use a fresh datastore rather than colliding with old saves.
	DataStoreName = "SquishyClicker_v2",
}

return Config
