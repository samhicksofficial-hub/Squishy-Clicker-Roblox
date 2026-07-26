--!strict
-- Central game tuning. Change numbers here rather than hunting through scripts.

local Config = {
	-- How much Squish a brand-new player starts with.
	StartingSquish = 0,

	-- Squish gained per click before any squishies are owned.
	BasePerClick = 1,

	-- How often idle income ticks, in seconds.
	AutoIncomeInterval = 1,

	-- Autosave interval in seconds (also saves on leave / shutdown).
	AutoSaveInterval = 60,

	-- Bump this string if you ever change the save format and want a clean slate.
	DataStoreName = "SquishyClicker_v1",
}

return Config
