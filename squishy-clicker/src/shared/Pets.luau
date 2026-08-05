--!strict
-- ============================================================
--  PETS  —  the catalog, and what comes out of each egg.
--
--  Shared because the client needs the names, colours and stats
--  to draw the pet inventory. It deliberately holds no state and
--  no player data: rolling an egg, spending the cost and deciding
--  who owns what all happen on the server. This is a lookup table
--  that both sides read, nothing more.
--
--  Bonuses are FRACTIONS added together across equipped pets, so
--  three pets at 0.25 power make ×1.75, not ×1.95. Additive keeps
--  the fifth pet worth roughly what the first was; multiplicative
--  stacking runs away the moment a player has five good ones.
-- ============================================================

local Pets = {}

export type Pet = {
	id: string,
	name: string,
	rarity: string,
	color: Color3,
	-- All optional: a pet with one strong stat reads better than one
	-- with a little of everything.
	power: number?, -- fraction added to launch power
	coins: number?, -- fraction added to coin pickups
	gems: number?, -- fraction added to gem pickups
	tnt: number?, -- fraction added to TNT pickups
	-- FLAT studs added to the magnet, not a fraction — and in the same screen
	-- units Config.LaunchPickupMagnet is quoted in, which starts at 2. A pet
	-- worth "+1.2 magnet" is therefore a big pet.
	magnet: number?,
}

export type Egg = {
	id: string,
	name: string,
	-- Eggs cost coins OR gems, never both. The premium egg is the only
	-- thing gems buy, which is what keeps gems feeling like a prize.
	costCoins: number?,
	costGems: number?,
	-- Weights are out of whatever they add up to, same as the squishy
	-- rarity table — no need to keep them summing to a round number.
	drops: { { id: string, weight: number } },
}

-- Ranked weakest to strongest. Shares its names with Squishies.rarities so
-- one colour key and one sort order serve both collections.
Pets.rarities = {
	{ name = "Common", color = Color3.fromRGB(176, 176, 176) },
	{ name = "Uncommon", color = Color3.fromRGB(126, 206, 126) },
	{ name = "Rare", color = Color3.fromRGB(96, 168, 236) },
	{ name = "Epic", color = Color3.fromRGB(176, 126, 232) },
	{ name = "Legendary", color = Color3.fromRGB(250, 186, 70) },
	{ name = "Mythical", color = Color3.fromRGB(240, 112, 156) },
}

Pets.list = {
	-- ----- Common -----
	{ id = "pupdough", name = "Dough Pup", rarity = "Common", color = Color3.fromRGB(238, 214, 176), power = 0.05 },
	{ id = "crumbcat", name = "Crumb Cat", rarity = "Common", color = Color3.fromRGB(220, 196, 168), coins = 0.08 },
	{ id = "pebblepal", name = "Pebble Pal", rarity = "Common", color = Color3.fromRGB(186, 186, 192), magnet = 0.4 },

	-- ----- Uncommon -----
	{ id = "minttoad", name = "Mint Toad", rarity = "Uncommon", color = Color3.fromRGB(146, 222, 176), power = 0.1 },
	{ id = "berrybun", name = "Berry Bun", rarity = "Uncommon", color = Color3.fromRGB(238, 138, 168), coins = 0.16 },
	{ id = "fuseferret", name = "Fuse Ferret", rarity = "Uncommon", color = Color3.fromRGB(232, 152, 88), tnt = 0.18 },

	-- ----- Rare -----
	{ id = "rocketrat", name = "Rocket Rat", rarity = "Rare", color = Color3.fromRGB(126, 152, 234), power = 0.2 },
	{ id = "coinkoi", name = "Coin Koi", rarity = "Rare", color = Color3.fromRGB(250, 206, 96), coins = 0.3 },
	{ id = "magnetmole", name = "Magnet Mole", rarity = "Rare", color = Color3.fromRGB(150, 130, 210), magnet = 1.2 },
	{ id = "boomboar", name = "Boom Boar", rarity = "Rare", color = Color3.fromRGB(226, 116, 84), tnt = 0.34 },

	-- ----- Epic -----
	{ id = "cometcub", name = "Comet Cub", rarity = "Epic", color = Color3.fromRGB(160, 196, 250), power = 0.38, magnet = 0.8 },
	{ id = "vaultvole", name = "Vault Vole", rarity = "Epic", color = Color3.fromRGB(242, 196, 120), coins = 0.55 },
	{ id = "gemgecko", name = "Gem Gecko", rarity = "Epic", color = Color3.fromRGB(120, 226, 206), gems = 0.5 },

	-- ----- Legendary -----
	{
		id = "novanewt",
		name = "Nova Newt",
		rarity = "Legendary",
		color = Color3.fromRGB(255, 176, 92),
		power = 0.65,
		tnt = 0.4,
	},
	{
		id = "bullionbat",
		name = "Bullion Bat",
		rarity = "Legendary",
		color = Color3.fromRGB(255, 212, 108),
		coins = 1,
		magnet = 1.6,
	},

	-- ----- Mythical -----
	{
		id = "starsnail",
		name = "Star Snail",
		rarity = "Mythical",
		color = Color3.fromRGB(246, 140, 200),
		power = 1.1,
		coins = 0.8,
		gems = 0.8,
		magnet = 2.2,
	},
	{
		id = "voidvulpes",
		name = "Void Vulpes",
		rarity = "Mythical",
		color = Color3.fromRGB(150, 116, 236),
		power = 1.4,
		tnt = 1,
	},
} :: { Pet }

Pets.byId = {} :: { [string]: Pet }
for _, pet in Pets.list do
	Pets.byId[pet.id] = pet
end

Pets.rarityByName = {} :: { [string]: { name: string, color: Color3 } }
Pets.rarityRank = {} :: { [string]: number }
for index, rarity in Pets.rarities do
	Pets.rarityByName[rarity.name] = rarity
	Pets.rarityRank[rarity.name] = index
end

-- Three eggs, each a straight upgrade on the last. Drop tables name pets
-- directly rather than rolling a rarity and then a pet within it: naming them
-- means a new pet can be added to exactly one egg without silently rebalancing
-- every other egg that happens to share its rarity.
Pets.eggs = {
	{
		id = "basic",
		name = "Basic Egg",
		costCoins = 600,
		drops = {
			{ id = "pupdough", weight = 300 },
			{ id = "crumbcat", weight = 300 },
			{ id = "pebblepal", weight = 220 },
			{ id = "minttoad", weight = 90 },
			{ id = "berrybun", weight = 60 },
			{ id = "fuseferret", weight = 25 },
			{ id = "rocketrat", weight = 5 },
		},
	},
	{
		id = "golden",
		name = "Golden Egg",
		costCoins = 12000,
		drops = {
			{ id = "minttoad", weight = 240 },
			{ id = "berrybun", weight = 210 },
			{ id = "fuseferret", weight = 200 },
			{ id = "rocketrat", weight = 130 },
			{ id = "coinkoi", weight = 110 },
			{ id = "magnetmole", weight = 60 },
			{ id = "boomboar", weight = 40 },
			{ id = "cometcub", weight = 8 },
			{ id = "vaultvole", weight = 2 },
		},
	},
	{
		id = "cosmic",
		name = "Cosmic Egg",
		costGems = 30,
		drops = {
			{ id = "rocketrat", weight = 180 },
			{ id = "coinkoi", weight = 170 },
			{ id = "magnetmole", weight = 150 },
			{ id = "boomboar", weight = 150 },
			{ id = "cometcub", weight = 130 },
			{ id = "vaultvole", weight = 110 },
			{ id = "gemgecko", weight = 80 },
			{ id = "novanewt", weight = 18 },
			{ id = "bullionbat", weight = 14 },
			{ id = "starsnail", weight = 4 },
			{ id = "voidvulpes", weight = 3 },
		},
	},
} :: { Egg }

Pets.eggById = {} :: { [string]: Egg }
for _, egg in Pets.eggs do
	Pets.eggById[egg.id] = egg
end

-- Roll one pet out of an egg. Takes the Random so the caller owns the stream —
-- the server passes its own, and nothing else is ever allowed to call this.
function Pets.roll(egg: Egg, rng: Random): Pet
	local total = 0
	for _, drop in egg.drops do
		total += drop.weight
	end

	local ticket = rng:NextNumber() * total
	for _, drop in egg.drops do
		ticket -= drop.weight
		if ticket <= 0 then
			local pet = Pets.byId[drop.id]
			if pet then
				return pet
			end
		end
	end

	-- Only reachable if a drop table names an id that no longer exists.
	-- Returning the first pet beats erroring inside a purchase the player has
	-- already paid for.
	return Pets.list[1]
end

-- The combined bonuses of a set of equipped pets, as multipliers ready to use
-- (magnet is the exception: flat studs, so it stays an addend). Server and
-- client both call this — the client to preview the numbers, the server to
-- actually apply them.
export type Bonuses = { power: number, coins: number, gems: number, tnt: number, magnet: number }

function Pets.bonuses(equipped: { string }): Bonuses
	local total: Bonuses = { power = 1, coins = 1, gems = 1, tnt = 1, magnet = 0 }
	for _, id in equipped do
		local pet = Pets.byId[id]
		if pet then
			total.power += pet.power or 0
			total.coins += pet.coins or 0
			total.gems += pet.gems or 0
			total.tnt += pet.tnt or 0
			total.magnet += pet.magnet or 0
		end
	end
	return total
end

return Pets
