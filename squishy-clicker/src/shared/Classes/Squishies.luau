--!strict
-- ============================================================
--  THE SQUISHY CATALOG
--  This is the file you'll edit most. Add a new line to the
--  list and a new squishy instantly appears in the shop.
--
--  id        : unique short code, no spaces (used for saving)
--  name      : shown in the shop
--  emoji     : placeholder art (swap for a real image later)
--  cost      : how much Squish it costs to unlock
--  perClick  : how much this adds to every click, once owned
--  perSecond : idle Squish per second, once owned
-- ============================================================

export type Squishy = {
	id: string,
	name: string,
	emoji: string,
	cost: number,
	perClick: number,
	perSecond: number,
}

local Squishies: { Squishy } = {
	{ id = "peachcat",  name = "Peach Cat",     emoji = "🍑", cost = 50,      perClick = 1,   perSecond = 0 },
	{ id = "boba",      name = "Boba Buddy",    emoji = "🧋", cost = 250,     perClick = 3,   perSecond = 1 },
	{ id = "ducky",     name = "Squishy Duck",  emoji = "🦆", cost = 1000,    perClick = 8,   perSecond = 3 },
	{ id = "dino",      name = "Baby Dino",     emoji = "🦖", cost = 5000,    perClick = 20,  perSecond = 10 },
	{ id = "unicorn",   name = "Cloud Unicorn", emoji = "🦄", cost = 25000,   perClick = 60,  perSecond = 35 },
	{ id = "star",      name = "Sleepy Star",   emoji = "⭐", cost = 120000,  perClick = 180, perSecond = 120 },
	{ id = "rainbow",   name = "Rainbow Cake",  emoji = "🌈", cost = 600000,  perClick = 500, perSecond = 400 },
}

-- Quick lookup by id, built once when the module loads.
local byId: { [string]: Squishy } = {}
for _, squishy in Squishies do
	byId[squishy.id] = squishy
end

return {
	list = Squishies,
	byId = byId,
}
