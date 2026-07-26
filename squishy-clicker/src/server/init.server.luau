--!strict
-- ============================================================
--  SERVER  —  the authority for everything that matters.
--  Clients can ASK to click or buy; only this script decides
--  what actually happens to a player's Squish. That's what
--  stops exploiters from handing themselves a billion currency.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Squishies = require(Shared:WaitForChild("Squishies"))

-- ---------- Remotes ----------
-- Created here at runtime so the whole network layer lives in one place.
local Remotes = Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local ClickSquishy = Instance.new("RemoteEvent")
ClickSquishy.Name = "ClickSquishy"
ClickSquishy.Parent = Remotes

local BuySquishy = Instance.new("RemoteEvent")
BuySquishy.Name = "BuySquishy"
BuySquishy.Parent = Remotes

local SyncData = Instance.new("RemoteEvent")
SyncData.Name = "SyncData"
SyncData.Parent = Remotes

-- ---------- Data types ----------
type PlayerData = {
	squish: number,
	owned: { [string]: boolean },
	perClick: number,  -- derived from owned squishies
	perSecond: number, -- derived from owned squishies
	lastSecondBucket: number, -- for click rate limiting
	clicksThisSecond: number,
}

local store = DataStoreService:GetDataStore(Config.DataStoreName)
local dataByPlayer: { [Player]: PlayerData } = {}

-- Never process more than this many clicks per second, per player.
local MAX_CLICKS_PER_SECOND = 25

-- ---------- Helpers ----------

-- Recompute perClick / perSecond from the set of owned squishies.
local function recompute(data: PlayerData)
	local perClick = Config.BasePerClick
	local perSecond = 0
	for id in data.owned do
		local squishy = Squishies.byId[id]
		if squishy then
			perClick += squishy.perClick
			perSecond += squishy.perSecond
		end
	end
	data.perClick = perClick
	data.perSecond = perSecond
end

-- Push the current state to one player's client so their UI updates.
local function sync(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	SyncData:FireClient(player, {
		squish = data.squish,
		owned = data.owned,
		perClick = data.perClick,
		perSecond = data.perSecond,
	})
end

-- Keep the native leaderboard number in step with our real value.
local function updateLeaderstat(player: Player)
	local data = dataByPlayer[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if data and leaderstats then
		local squishValue = leaderstats:FindFirstChild("Squish") :: IntValue?
		if squishValue then
			squishValue.Value = math.floor(data.squish)
		end
	end
end

-- ---------- Join / leave ----------

local function loadData(player: Player): PlayerData
	local loaded: { squish: number, owned: { [string]: boolean } }? = nil

	-- pcall so a DataStore hiccup (or Studio API access being off)
	-- doesn't crash the game — the player just starts fresh.
	local ok, result = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)
	if ok and typeof(result) == "table" then
		loaded = result :: any
	elseif not ok then
		warn("[SquishyClicker] Could not load data for", player.Name, "-", result)
	end

	local data: PlayerData = {
		squish = loaded and loaded.squish or Config.StartingSquish,
		owned = loaded and loaded.owned or {},
		perClick = Config.BasePerClick,
		perSecond = 0,
		lastSecondBucket = 0,
		clicksThisSecond = 0,
	}
	recompute(data)
	return data
end

local function saveData(player: Player)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("player_" .. player.UserId, {
			squish = data.squish,
			owned = data.owned,
		})
	end)
	if not ok then
		warn("[SquishyClicker] Could not save data for", player.Name, "-", err)
	end
end

Players.PlayerAdded:Connect(function(player)
	local data = loadData(player)
	dataByPlayer[player] = data

	-- Native leaderboard (top-right) — a free bonus from naming a folder "leaderstats".
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local squishValue = Instance.new("IntValue")
	squishValue.Name = "Squish"
	squishValue.Value = math.floor(data.squish)
	squishValue.Parent = leaderstats

	sync(player)
end)

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	dataByPlayer[player] = nil
end)

-- ---------- Clicking ----------

ClickSquishy.OnServerEvent:Connect(function(player)
	local data = dataByPlayer[player]
	if not data then
		return
	end

	-- Simple rate limit: bucket clicks per whole second.
	local bucket = math.floor(os.clock())
	if bucket ~= data.lastSecondBucket then
		data.lastSecondBucket = bucket
		data.clicksThisSecond = 0
	end
	data.clicksThisSecond += 1
	if data.clicksThisSecond > MAX_CLICKS_PER_SECOND then
		return -- ignore spam beyond the cap
	end

	data.squish += data.perClick
	updateLeaderstat(player)
	sync(player)
end)

-- ---------- Buying ----------

BuySquishy.OnServerEvent:Connect(function(player, squishyId)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	if typeof(squishyId) ~= "string" then
		return
	end

	local squishy = Squishies.byId[squishyId]
	if not squishy then
		return -- unknown id, ignore
	end
	if data.owned[squishyId] then
		return -- already owned
	end
	if data.squish < squishy.cost then
		return -- can't afford; server says no
	end

	data.squish -= squishy.cost
	data.owned[squishyId] = true
	recompute(data)
	updateLeaderstat(player)
	sync(player)
end)

-- ---------- Idle income ----------

task.spawn(function()
	while true do
		task.wait(Config.AutoIncomeInterval)
		for player, data in dataByPlayer do
			if data.perSecond > 0 then
				data.squish += data.perSecond * Config.AutoIncomeInterval
				updateLeaderstat(player)
				sync(player)
			end
		end
	end
end)

-- ---------- Autosave ----------

task.spawn(function()
	while true do
		task.wait(Config.AutoSaveInterval)
		for player in dataByPlayer do
			saveData(player)
		end
	end
end)

-- Best-effort save when the server shuts down (also runs when you stop Play in Studio).
game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for player in dataByPlayer do
		saveData(player)
	end
	task.wait(2) -- give SetAsync calls a moment to finish
end)

print("[SquishyClicker] Server ready.")
