--!strict
-- ============================================================
--  THE SQUISHY CATALOG  —  dumplings edition
--  Add a squishy: one line in the `list`. Add a rarity: one
--  entry in `rarities`. Everything else updates automatically.
--
--  Rarity fields:
--    weight     : roll chance out of the total (1000 here, so 550 = 55%)
--    baseCopies : copies needed for the FIRST star (doubles per star)
--    color      : rarity label color in the inventory
--  Squishy fields:
--    id, name, rarity, color (the dumpling's body color), sparkle
-- ============================================================

export type Rarity = {
	name: string,
	weight: number,
	baseCopies: number,
	color: Color3,
}

export type Squishy = {
	id: string,
	name: string,
	rarity: string,
	color: Color3,
	sparkle: boolean,
	-- Which 3D model the client builds for the reveal (see the shape builders
	-- in Models.luau). Absent = "dumpling", so the original 13 stay untouched.
	shape: string?,
	-- Size multiplier, for the ones whose name promises a size. Absent = 1,
	-- meaning every squishy is normalised to the same on-screen size.
	scale: number?,
}

-- Order matters only for display (least → most rare).
local rarities: { Rarity } = {
	{ name = "Common",    weight = 550, baseCopies = 10, color = Color3.fromRGB(148, 155, 164) },
	{ name = "Uncommon",  weight = 250, baseCopies = 8,  color = Color3.fromRGB(96, 190, 120) },
	{ name = "Rare",      weight = 120, baseCopies = 6,  color = Color3.fromRGB(88, 148, 235) },
	{ name = "Epic",      weight = 55,  baseCopies = 5,  color = Color3.fromRGB(168, 110, 235) },
	{ name = "Legendary", weight = 20,  baseCopies = 4,  color = Color3.fromRGB(240, 165, 60) },
	{ name = "Mythical",  weight = 5,   baseCopies = 3,  color = Color3.fromRGB(240, 95, 150) },
}

-- Size multipliers for the squishies whose name promises one. Kept here so
-- every Mini and every Giant agree with each other.
local MINI = 0.7
local GIANT = 1.45

local list: { Squishy } = {
	-- The dumplings all share the imported opal mesh, tinted — one mould in a
	-- range of colours, the way the real squishies are made.
	-- Commons: the classic solid-color dumplings
	{ id = "red",     name = "Red Dumpling",    rarity = "Common",    color = Color3.fromRGB(214, 69, 65),   sparkle = false, shape = "dumplingmesh" },
	{ id = "pink",    name = "Pink Dumpling",   rarity = "Common",    color = Color3.fromRGB(247, 168, 195), sparkle = false, shape = "dumplingmesh" },
	{ id = "blue",    name = "Blue Dumpling",   rarity = "Common",    color = Color3.fromRGB(94, 156, 222),  sparkle = false, shape = "dumplingmesh" },
	{ id = "green",   name = "Green Dumpling",  rarity = "Common",    color = Color3.fromRGB(139, 197, 96),  sparkle = false, shape = "dumplingmesh" },

	-- Uncommons
	{ id = "white",   name = "White Dumpling",  rarity = "Uncommon",  color = Color3.fromRGB(243, 240, 235), sparkle = false, shape = "dumplingmesh" },
	{ id = "purple",  name = "Purple Dumpling", rarity = "Uncommon",  color = Color3.fromRGB(158, 122, 216), sparkle = false, shape = "dumplingmesh" },
	{ id = "teal",    name = "Teal Dumpling",   rarity = "Uncommon",  color = Color3.fromRGB(84, 196, 196),  sparkle = false, shape = "dumplingmesh" },

	-- Rares: the glitter ones
	{ id = "skyglit",  name = "Sky Glitter",    rarity = "Rare",      color = Color3.fromRGB(70, 120, 200),  sparkle = true,  shape = "dumplingmesh" },
	{ id = "oliveglit", name = "Olive Glitter", rarity = "Rare",      color = Color3.fromRGB(140, 150, 70),  sparkle = true,  shape = "dumplingmesh" },

	-- Epics
	{ id = "confetti", name = "Confetti Pink",  rarity = "Epic",      color = Color3.fromRGB(240, 140, 180), sparkle = true,  shape = "dumplingmesh" },
	{ id = "rainbow",  name = "Rainbow Melt",   rarity = "Epic",      color = Color3.fromRGB(190, 220, 120), sparkle = true,  shape = "dumplingmesh" },

	-- Legendary
	{ id = "gold",     name = "Gold Glitter",   rarity = "Legendary", color = Color3.fromRGB(226, 178, 66),  sparkle = true,  shape = "dumplingmesh" },

	-- Mythical: the big iridescent pearl one — uses the imported 3D mesh when
	-- ReplicatedStorage/SquishyMeshes/OpalDumpling exists (see README).
	{ id = "opal",     name = "Opal Dumpling",  rarity = "Mythical",  color = Color3.fromRGB(232, 225, 245), sparkle = true,  shape = "opalmesh" },

	-- ===== The squishy shop haul =====
	-- Commons: everyday squishies
	{ id = "banana",     name = "Stretch Banana",   rarity = "Common",    color = Color3.fromRGB(250, 216, 88),  sparkle = false, shape = "bananamesh" },
	{ id = "coconut",    name = "Coconut Ball",     rarity = "Common",    color = Color3.fromRGB(196, 228, 200), sparkle = false, shape = "coconutmesh" },
	{ id = "jellycube",  name = "Mini Jelly Cube",  rarity = "Common",    color = Color3.fromRGB(242, 150, 62),  sparkle = false, shape = "cubeorange", scale = MINI },
	{ id = "cloud",      name = "Dough Cloud",      rarity = "Common",    color = Color3.fromRGB(250, 248, 244), sparkle = false, shape = "cloudmesh" },
	{ id = "butter",     name = "Butter Stick",     rarity = "Common",    color = Color3.fromRGB(247, 210, 96),  sparkle = false, shape = "buttermesh" },
	-- Everyday twin of the Giant Strawberry. Its id is "plainstrawberry"
	-- because "strawberry" was taken by the giant, which shipped first and
	-- cannot be renamed without orphaning anyone who already owns one.
	{ id = "plainstrawberry", name = "Strawberry", rarity = "Common",    color = Color3.fromRGB(219, 58, 62),   sparkle = false, shape = "strawberrymesh" },

	-- Uncommons
	{ id = "cheese",     name = "Squeeze Cheese",   rarity = "Uncommon",  color = Color3.fromRGB(245, 196, 54),  sparkle = false, shape = "cheesemesh" },
	{ id = "swirlcube",  name = "Swirl Cube",       rarity = "Uncommon",  color = Color3.fromRGB(235, 122, 168), sparkle = false, shape = "cubepink" },
	{ id = "snowcube",   name = "Snowflake Cube",   rarity = "Uncommon",  color = Color3.fromRGB(138, 200, 240), sparkle = false, shape = "cubeblue" },

	-- Rares
	{ id = "glitcube",   name = "Glitter Cube",     rarity = "Rare",      color = Color3.fromRGB(112, 218, 122), sparkle = true,  shape = "cubegreen" },
	{ id = "twotone",    name = "Two-Tone Glitter", rarity = "Rare",      color = Color3.fromRGB(186, 142, 235), sparkle = true,  shape = "cubepurple" },
	{ id = "cake",       name = "Boxed Cake",       rarity = "Rare",      color = Color3.fromRGB(246, 204, 158), sparkle = true,  shape = "tub" },

	-- Epics
	{ id = "brain",      name = "Pink Brain",       rarity = "Epic",      color = Color3.fromRGB(240, 158, 170), sparkle = false, shape = "brainmesh" },
	{ id = "blobfish",   name = "Blobfish",         rarity = "Epic",      color = Color3.fromRGB(122, 170, 230), sparkle = false, shape = "blobfish" },
	{ id = "sugarbaby",  name = "Sugar Baby",       rarity = "Epic",      color = Color3.fromRGB(230, 120, 198), sparkle = true,  shape = "babymesh" },
	{ id = "rainbutter", name = "Rainbow Butter",   rarity = "Epic",      color = Color3.fromRGB(196, 124, 220), sparkle = false, shape = "rainbuttermesh" },
	{ id = "sparkledrop", name = "Sparkle Drop",    rarity = "Epic",      color = Color3.fromRGB(140, 226, 198), sparkle = true,  shape = "dropmesh" },

	-- Legendary
	{ id = "glowdonut",   name = "Glow Doughnut",   rarity = "Legendary", color = Color3.fromRGB(132, 244, 120), sparkle = true,  shape = "glowdonutmesh" },

	-- ===== Giant editions =====
	-- Same model as their everyday twin, just enormous. Every giant is Epic or
	-- better, so pulling one always feels like an event — which means a giant
	-- is at least two tiers above an everyday Common twin, not merely one.
	{ id = "giantbanana",     name = "Giant Banana",         rarity = "Epic",      color = Color3.fromRGB(250, 216, 88),  sparkle = false, shape = "bananamesh",     scale = GIANT },
	{ id = "giantbutter",     name = "Giant Butter Stick",   rarity = "Epic",      color = Color3.fromRGB(247, 210, 96),  sparkle = false, shape = "buttermesh",     scale = GIANT },
	{ id = "strawberry",      name = "Giant Strawberry",     rarity = "Epic",      color = Color3.fromRGB(219, 58, 62),   sparkle = false, shape = "strawberrymesh", scale = GIANT },
	{ id = "giantrainbutter", name = "Giant Rainbow Butter", rarity = "Legendary", color = Color3.fromRGB(196, 124, 220), sparkle = false, shape = "rainbuttermesh", scale = GIANT },
	{ id = "giantopal",       name = "Giant Opal Dumpling",  rarity = "Mythical",  color = Color3.fromRGB(232, 225, 245), sparkle = true,  shape = "opalmesh",       scale = GIANT },
}

-- ---------- lookups (built once) ----------
local byId: { [string]: Squishy } = {}
for _, squishy in list do
	byId[squishy.id] = squishy
end

local rarityByName: { [string]: Rarity } = {}
local totalWeight = 0
for _, rarity in rarities do
	rarityByName[rarity.name] = rarity
	totalWeight += rarity.weight
end

local squishiesByRarity: { [string]: { Squishy } } = {}
for _, squishy in list do
	local bucket = squishiesByRarity[squishy.rarity]
	if not bucket then
		bucket = {}
		squishiesByRarity[squishy.rarity] = bucket
	end
	table.insert(bucket, squishy)
end

-- Roll a random squishy: pick a rarity by weight, then uniformly within it.
-- (Server calls this; keeping it here means the odds live next to the data.)
local function roll(random: Random): Squishy
	local pick = random:NextNumber() * totalWeight
	local running = 0
	for _, rarity in rarities do
		running += rarity.weight
		if pick <= running then
			local bucket = squishiesByRarity[rarity.name]
			return bucket[random:NextInteger(1, #bucket)]
		end
	end
	-- Float edge case fallback: last rarity's bucket.
	local last = squishiesByRarity[rarities[#rarities].name]
	return last[random:NextInteger(1, #last)]
end

return {
	list = list,
	byId = byId,
	rarities = rarities,
	rarityByName = rarityByName,
	roll = roll,
}
