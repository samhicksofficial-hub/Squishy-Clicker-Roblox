--!strict
-- ============================================================
--  TRACK  —  the living flight and the endless track, SHARED.
--
--  One module, two jobs, required by BOTH sides:
--
--  1. The flight simulator. A shot is no longer a precomputed arc —
--     it is momentum. Forward speed carries the power the player
--     bought; the vertical envelope is fixed at human scale so
--     boosts, bombs and the corridor ceiling all stay in reach at
--     every power level. The flight lasts exactly as long as the
--     player keeps it alive: boots relaunch it, bombs bleed it,
--     and it ends only when the roll runs out of speed.
--
--  2. The track generator. The field is seeded chunks, generated
--     deterministically from a seed the server picks at fire time.
--     The client generates chunks to DRAW them; the server
--     regenerates the same chunks to VALIDATE and PAY them. Same
--     code, same rng order, same numbers — the two can never drift.
--
--  THE SERVER STILL DECIDES. The client steers its local sim and
--  reports what it touched; the server re-runs this same sim from
--  those events and pays only what the physics agrees happened.
-- ============================================================

local Config = require(script.Parent.Config)

local Track = {}

-- ---------- the flight simulator ----------

export type Physics = {
	gravity: number,
	restitution: number,
	bounceFriction: number,
	minBounceSpeed: number,
	rollSeconds: number,
	endSpeed: number,
	maxSeconds: number,
}

export type Sim = {
	t: number,
	dist: number,
	h: number,
	vx: number,
	vy: number,
	rolling: boolean,
	done: boolean,
	bounced: number,
	-- True only on the step call where the ground was struck — the
	-- caller's one frame to splat, thock and burst.
	hitGround: boolean,
	rollRate: number,
	phys: Physics,
}

-- The default physics, before any squishy ability bends them.
function Track.basePhysics(): Physics
	return {
		gravity = Config.FlightGravity,
		restitution = Config.LaunchRestitution,
		bounceFriction = Config.LaunchBounceFriction,
		minBounceSpeed = Config.LaunchMinBounceSpeed,
		rollSeconds = Config.FlightRollSeconds,
		endSpeed = Config.FlightEndSpeed,
		maxSeconds = Config.FlightMaxSeconds,
	}
end

-- The forward speed that makes a NO-EVENT flight land at `distance`.
-- This is what keeps the whole economy intact through the physics
-- change: the old closed-form simulator still prices power levels in
-- expected studs, and this inverts that expectation into momentum.
-- K sums each hop's hang time (forward speed shedding bounce friction
-- per skip) plus the roll's triangle; distance = vx0 * K exactly.
function Track.calibrate(distance: number, vy: number, phys: Physics): number
	local K, v, f, hops = 0, vy, 1, 0
	while v >= phys.minBounceSpeed and hops < 30 do
		K += f * 2 * v / phys.gravity
		v *= phys.restitution
		f *= phys.bounceFriction
		hops += 1
	end
	K += f * phys.rollSeconds * 0.5
	return math.max(distance, 1) / math.max(K, 0.5)
end

function Track.newSim(vx: number, vy: number, phys: Physics): Sim
	return {
		t = 0,
		dist = 0,
		h = 0.5,
		vx = math.max(vx, 0),
		vy = vy,
		rolling = false,
		done = false,
		bounced = 0,
		hitGround = false,
		rollRate = 0,
		phys = phys,
	}
end

function Track.step(sim: Sim, dt: number)
	if sim.done then
		return
	end
	sim.hitGround = false
	sim.t += dt
	if sim.t >= sim.phys.maxSeconds then
		sim.done = true
		sim.rolling = true
		sim.h = 0
		return
	end
	if sim.rolling then
		sim.vx = math.max(sim.vx - sim.rollRate * dt, 0)
		sim.dist += sim.vx * dt
		if sim.vx <= sim.phys.endSpeed then
			sim.done = true
		end
	else
		sim.vy -= sim.phys.gravity * dt
		sim.h += sim.vy * dt
		sim.dist += sim.vx * dt
		if sim.h <= 0 and sim.vy < 0 then
			sim.h = 0
			sim.hitGround = true
			local rebound = -sim.vy * sim.phys.restitution
			sim.vx *= sim.phys.bounceFriction
			if rebound >= sim.phys.minBounceSpeed then
				sim.vy = rebound
				sim.bounced += 1
			else
				-- Not worth another skip: the rest is the roll, decaying
				-- linearly over rollSeconds so every flight ends on time.
				sim.vy = 0
				sim.rolling = true
				sim.rollRate = math.max(sim.vx, 1) / math.max(sim.phys.rollSeconds, 0.1)
			end
		end
	end
end

-- A boost boot: the vy refresh IS the extension. Works mid-air and —
-- deliberately — mid-ROLL: a ground-line boot relaunches a dying shot,
-- which is the whole reason to steer for one.
function Track.boot(sim: Sim)
	if sim.done then
		return
	end
	sim.vy = math.max(sim.vy, Config.BootImpulse)
	sim.rolling = false
end

-- A bomb: forward speed bled, and knocked downward if airborne.
function Track.bomb(sim: Sim)
	if sim.done then
		return
	end
	sim.vx *= 1 - Config.BombSpeedCut
	if not sim.rolling then
		sim.vy = math.min(sim.vy, -12)
	end
end

-- A slam: a hard dive. Whatever it costs or bursts is judged at the
-- impact the step() after this produces.
function Track.slam(sim: Sim)
	if sim.done or sim.rolling then
		return
	end
	sim.vy = math.min(sim.vy, -Config.SlamDiveSpeed)
end

-- ---------- the endless track ----------

export type Pickup = { id: number, distance: number, height: number, value: number, vip: boolean, lane: number, kind: string }
export type Boot = { id: number, distance: number, height: number, lane: number, cash: number }
export type Bomb = { id: number, distance: number, height: number, lane: number }
export type Chunk = { pickups: { Pickup }, boots: { Boot }, bombs: { Bomb } }

-- Which chunk a distance falls in, and the id scheme: chunk * 4096 +
-- slot, unique across the whole flight, decoded with these two.
function Track.chunkAt(distance: number): number
	return math.max(math.floor(distance / Config.ChunkLength), 0)
end

function Track.chunkOf(id: number): number
	return math.floor(id / 4096)
end

-- One chunk of track, deterministic in (seed, index). BOTH sides call
-- this with the same numbers, and the rng call order below is part of
-- the protocol: reorder these rolls and the client starts hallucinating
-- cash the server never placed.
function Track.chunk(seed: number, index: number): Chunk
	local rng = Random.new(seed + index * 7919)
	local from = index * Config.ChunkLength
	local half = Config.SteerHalfWidth
	local pickups: { Pickup } = {}
	local boots: { Boot } = {}
	local bombs: { Bomb } = {}
	local slot = 0
	local function nextId(): number
		slot += 1
		return index * 4096 + slot
	end
	local function cashValue(at: number, vip: boolean): number
		local value = Config.PickupCoinValue * (1 + at / 1000 * Config.PickupValuePer1kStuds)
		if vip then
			value *= Config.VipZoneValueMultiplier
		end
		return math.max(math.floor(value + 0.5), 1)
	end

	-- Cash: a fraction rides the centre line for the magnet, the rest
	-- spreads the full lane. Heights band across ground / mid-air /
	-- boost-line, so the sky above a boot is never empty.
	for _ = 1, Config.ChunkCashCount do
		local at = from + rng:NextNumber() * Config.ChunkLength
		local lane = 0
		if rng:NextNumber() > Config.PickupCentreFraction then
			lane = (rng:NextNumber() * 2 - 1) * half
		end
		local roll = rng:NextNumber()
		local height = if roll < 0.3 then 2 elseif roll < 0.8 then 8 + rng:NextNumber() * 32 else 55 + rng:NextNumber() * 40
		table.insert(pickups, {
			id = nextId(),
			distance = math.max(at, 1),
			height = height,
			value = cashValue(at, false),
			vip = false,
			lane = lane,
			kind = "coin",
		})
	end

	-- Sometimes a VIP cluster: a golden knot worth several times over,
	-- parked off-centre so it has to be steered for.
	if rng:NextNumber() < Config.ChunkVipChance then
		local centre = from + 40 + rng:NextNumber() * (Config.ChunkLength - 80)
		local lane = (rng:NextNumber() * 2 - 1) * half * 0.8
		for _ = 1, 5 do
			local at = centre + (rng:NextNumber() - 0.5) * 70
			table.insert(pickups, {
				id = nextId(),
				distance = math.max(at, 1),
				height = 6 + rng:NextNumber() * 30,
				value = cashValue(at, true),
				vip = true,
				lane = math.clamp(lane + (rng:NextNumber() - 0.5) * 4, -half, half),
				kind = "coin",
			})
		end
	end

	-- Boots: none in the opening chunk, roughly every other chunk after,
	-- doubling up occasionally deep in the flight — the deeper the run,
	-- the more ways to keep it alive.
	if index >= 1 then
		local count = if rng:NextNumber() < 0.55 then 1 else 0
		if index >= 6 and rng:NextNumber() < 0.25 then
			count += 1
		end
		for _ = 1, count do
			local at = from + rng:NextNumber() * Config.ChunkLength
			table.insert(boots, {
				id = nextId(),
				distance = math.max(at, 1),
				height = 8 + rng:NextNumber() * 36,
				lane = (rng:NextNumber() * 2 - 1) * half * 0.85,
				cash = math.max(math.floor(Config.BootCash * (1 + at / 1000 * Config.PickupValuePer1kStuds) + 0.5), 1),
			})
		end
	end

	-- Bombs: the density RAMP. Nothing in the opening chunk, one apiece
	-- through the early track, up to three deep in — and never parked
	-- dead-centre in the first two chunks, where a hit would land before
	-- the player has meaningfully steered.
	local bombCount = if index <= 0 then 0 elseif index <= 2 then 1 elseif index <= 5 then 2 else 3
	for _ = 1, bombCount do
		if rng:NextNumber() < 0.88 then
			local at = from + rng:NextNumber() * Config.ChunkLength
			local lane = (rng:NextNumber() * 2 - 1) * half
			if index <= 1 and math.abs(lane) < half * 0.25 then
				lane = (if lane < 0 then -1 else 1) * half * (0.25 + rng:NextNumber() * 0.25)
			end
			local height = if rng:NextNumber() < 0.4 then 2 else 6 + rng:NextNumber() * 38
			if rng:NextNumber() < 0.15 then
				height = 55 + rng:NextNumber() * 35
			end
			table.insert(bombs, {
				id = nextId(),
				distance = math.max(at, 1),
				height = height,
				lane = lane,
			})
		end
	end

	return { pickups = pickups, boots = boots, bombs = bombs }
end

-- Find one entry of a chunk by id. Linear on purpose: the lists are a
-- dozen entries long and this runs a few hundred times per settle.
function Track.pickupById(chunk: Chunk, id: number): Pickup?
	for _, entry in chunk.pickups do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function Track.bootById(chunk: Chunk, id: number): Boot?
	for _, entry in chunk.boots do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

function Track.bombById(chunk: Chunk, id: number): Bomb?
	for _, entry in chunk.bombs do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

return Track
