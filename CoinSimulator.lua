-- COIN SIMULATOR - tek script oyun
-- Kurulum: Roblox Studio > ServerScriptService > sag tik > Insert Object > Script
-- Icindeki her seyi sil, bu kodun tamamini yapistir, Play'e bas.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local DataStoreService = game:GetService("DataStoreService")

---------------------------------------------------------------- AYARLAR
local ZONE_SIZE = 120
local ZONES = {
	{ name = "Baslangic", coinValue = 1, color = Color3.fromRGB(255, 200, 0), ground = Color3.fromRGB(90, 170, 90), cost = 0 },
	{ name = "Buz Diyari", coinValue = 5, color = Color3.fromRGB(0, 200, 255), ground = Color3.fromRGB(190, 225, 255), cost = 500 },
	{ name = "Lav Diyari", coinValue = 25, color = Color3.fromRGB(255, 60, 120), ground = Color3.fromRGB(110, 50, 50), cost = 10000 },
}
local COINS_PER_ZONE = 30
local COIN_RESPAWN = 2
local MAX_SPEED_LEVEL = 10
local MAX_JUMP_LEVEL = 8
local MAX_MULT_LEVEL = 50
local REBIRTH_BASE_COST = 50000
local CHEST_COOLDOWN = 180
local AUTOSAVE_SECONDS = 60

---------------------------------------------------------------- VERI
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("CoinSimulator_v1")
end)

local data = {} -- [player] = { coins, speed, jump, mult, tier, rebirths }
local loadedOk = {} -- veri duzgun yuklenmediyse uzerine yazmayiz
local lastChest = {}
local msgToken = {}

local function newData()
	return { coins = 0, speed = 0, jump = 0, mult = 0, tier = 0, rebirths = 0 }
end

local function loadData(player)
	local d = newData()
	local ok = false
	if store then
		local success, saved = pcall(function()
			return store:GetAsync("p_" .. player.UserId)
		end)
		if success then
			ok = true
			if type(saved) == "table" then
				for key in pairs(d) do
					if type(saved[key]) == "number" then
						d[key] = saved[key]
					end
				end
			end
		else
			warn("Veri yuklenemedi (Studio'da API Services kapali olabilir): " .. tostring(saved))
		end
	end
	return d, ok
end

local function saveData(player)
	local d = data[player]
	if not (store and d and loadedOk[player]) then
		return
	end
	local success, err = pcall(function()
		store:SetAsync("p_" .. player.UserId, d)
	end)
	if not success then
		warn("Veri kaydedilemedi: " .. tostring(err))
	end
end

---------------------------------------------------------------- YARDIMCILAR
local function short(n)
	n = math.floor(n)
	local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, u in ipairs(units) do
		if n >= u[1] then
			return string.format("%.1f%s", n / u[1], u[2])
		end
	end
	return tostring(n)
end

local function totalMult(d)
	return (1 + d.mult) * (1 + d.rebirths)
end

local function speedCost(d) return math.floor(25 * 2 ^ d.speed) end
local function jumpCost(d) return math.floor(40 * 2 ^ d.jump) end
local function multCost(d) return math.floor(50 * 1.6 ^ d.mult) end
local function rebirthCost(d) return REBIRTH_BASE_COST * (d.rebirths + 1) end

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = props.Parent or workspace
	return p
end

local function addBillboard(part, text, color)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 70)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = gui
	gui.Parent = part
	return label
end

local function addPrompt(part, action, object)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

---------------------------------------------------------------- ARAYUZ (HUD)
local function buildHud(player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false

	local stats = Instance.new("TextLabel")
	stats.Name = "Stats"
	stats.AnchorPoint = Vector2.new(0, 0.5)
	stats.Position = UDim2.new(0, 12, 0.5, 0)
	stats.Size = UDim2.fromOffset(250, 190)
	stats.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	stats.BackgroundTransparency = 0.25
	stats.TextColor3 = Color3.new(1, 1, 1)
	stats.Font = Enum.Font.GothamBold
	stats.TextSize = 16
	stats.TextXAlignment = Enum.TextXAlignment.Left
	stats.TextYAlignment = Enum.TextYAlignment.Top
	stats.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = stats
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 10)
	pad.Parent = stats
	stats.Parent = gui

	local msg = Instance.new("TextLabel")
	msg.Name = "Msg"
	msg.AnchorPoint = Vector2.new(0.5, 0)
	msg.Position = UDim2.new(0.5, 0, 0.12, 0)
	msg.Size = UDim2.fromOffset(520, 44)
	msg.BackgroundTransparency = 1
	msg.TextColor3 = Color3.fromRGB(255, 240, 120)
	msg.TextStrokeTransparency = 0
	msg.Font = Enum.Font.FredokaOne
	msg.TextScaled = true
	msg.Text = ""
	msg.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function levelLine(name, level, max, cost)
	if level >= max then
		return string.format("%s Sv.%d  (MAX)", name, level)
	end
	return string.format("%s Sv.%d  > %s", name, level, short(cost))
end

local function refresh(player)
	local d = data[player]
	if not d then
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Coin.Value = math.floor(d.coins)
		ls.Rebirth.Value = d.rebirths
	end
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("HUD")
	if gui then
		gui.Stats.Text = table.concat({
			"Coin: " .. short(d.coins),
			"Carpan: x" .. short(totalMult(d)),
			"",
			levelLine("Hiz", d.speed, MAX_SPEED_LEVEL, speedCost(d)),
			levelLine("Ziplama", d.jump, MAX_JUMP_LEVEL, jumpCost(d)),
			levelLine("Carpan", d.mult, MAX_MULT_LEVEL, multCost(d)),
			"",
			"Rebirth: " .. d.rebirths .. "  > " .. short(rebirthCost(d)),
		}, "\n")
	end
end

local function notify(player, text)
	local gui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("HUD")
	if not gui then
		return
	end
	local token = (msgToken[player] or 0) + 1
	msgToken[player] = token
	gui.Msg.Text = text
	task.delay(2.5, function()
		if msgToken[player] == token and gui.Parent then
			gui.Msg.Text = ""
		end
	end)
end

---------------------------------------------------------------- KARAKTER
PhysicsService:RegisterCollisionGroup("Door1")
PhysicsService:RegisterCollisionGroup("Door2")
for tier = 0, 2 do
	PhysicsService:RegisterCollisionGroup("Tier" .. tier)
end
PhysicsService:CollisionGroupSetCollidable("Tier1", "Door1", false)
PhysicsService:CollisionGroupSetCollidable("Tier2", "Door1", false)
PhysicsService:CollisionGroupSetCollidable("Tier2", "Door2", false)

local function applyCharacter(player)
	local d = data[player]
	local char = player.Character
	if not (d and char) then
		return
	end
	local group = "Tier" .. math.clamp(d.tier, 0, 2)
	for _, obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.CollisionGroup = group
		end
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 16 + d.speed * 4
		hum.UseJumpPower = false
		hum.JumpHeight = 7.2 + d.jump * 2.5
	end
end

---------------------------------------------------------------- HARITA
for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
	local old = workspace:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local map = Instance.new("Folder")
map.Name = "CoinSimulatorMap"
map.Parent = workspace

local function zoneCenterZ(i)
	return -(i - 1) * ZONE_SIZE
end

for i, zone in ipairs(ZONES) do
	makePart({
		Name = "Zemin" .. i,
		Size = Vector3.new(ZONE_SIZE, 4, ZONE_SIZE),
		Position = Vector3.new(0, -2, zoneCenterZ(i)),
		Color = zone.ground,
		Material = Enum.Material.Grass,
		Parent = map,
	})
end

local spawn = Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = Vector3.new(10, 1, 10)
spawn.Position = Vector3.new(0, 0.5, 45)
spawn.Color = Color3.fromRGB(255, 255, 255)
spawn.Material = Enum.Material.Neon
spawn.Parent = map

-- Coinler
local function spawnCoin(i)
	local zone = ZONES[i]
	local coin = makePart({
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 3.5, 3.5),
		Position = Vector3.new(math.random(-52, 52), 2.5, zoneCenterZ(i) + math.random(-48, 48)),
		Orientation = Vector3.new(0, math.random(0, 180), 0),
		Color = zone.color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = map,
	})
	local taken = false
	coin.Touched:Connect(function(hit)
		if taken then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local d = player and data[player]
		if not d then
			return
		end
		taken = true
		d.coins += zone.coinValue * totalMult(d)
		refresh(player)
		coin:Destroy()
		task.delay(COIN_RESPAWN, spawnCoin, i)
	end)
end

for i = 1, #ZONES do
	for _ = 1, COINS_PER_ZONE do
		spawnCoin(i)
	end
end

-- Bolge kapilari
for i = 2, #ZONES do
	local zone = ZONES[i]
	local tier = i - 1
	local wallZ = zoneCenterZ(i) + ZONE_SIZE / 2
	local wall = makePart({
		Name = "Kapi" .. tier,
		Size = Vector3.new(ZONE_SIZE, 70, 2),
		Position = Vector3.new(0, 35, wallZ),
		Color = zone.color,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		Parent = map,
	})
	wall.CollisionGroup = "Door" .. tier

	local sign = makePart({
		Name = "KapiTabela" .. tier,
		Size = Vector3.new(8, 1, 4),
		Position = Vector3.new(0, 0.5, wallZ + 6),
		Color = zone.color,
		Material = Enum.Material.Neon,
		Parent = map,
	})
	addBillboard(sign, zone.name .. "\n" .. short(zone.cost) .. " Coin", zone.color)
	addPrompt(sign, "Kilidi Ac", zone.name).Triggered:Connect(function(player)
		local d = data[player]
		if not d then
			return
		end
		if d.tier >= tier then
			notify(player, "Bu bolge zaten acik!")
		elseif d.tier < tier - 1 then
			notify(player, "Once onceki bolgeyi ac!")
		elseif d.coins < zone.cost then
			notify(player, "Yetersiz coin! Gereken: " .. short(zone.cost))
		else
			d.coins -= zone.cost
			d.tier = tier
			applyCharacter(player)
			refresh(player)
			notify(player, zone.name .. " acildi! Coinler burada x" .. zone.coinValue)
		end
	end)
end

-- Yukseltme standlari
local function makeStand(pos, color, title, key, maxLevel, costFn)
	local stand = makePart({
		Name = "Stand_" .. key,
		Size = Vector3.new(7, 1, 7),
		Position = pos,
		Color = color,
		Material = Enum.Material.Neon,
		Parent = map,
	})
	addBillboard(stand, title, color)
	addPrompt(stand, "Yukselt", title).Triggered:Connect(function(player)
		local d = data[player]
		if not d then
			return
		end
		local cost = costFn(d)
		if d[key] >= maxLevel then
			notify(player, title .. " zaten maksimum!")
		elseif d.coins < cost then
			notify(player, "Yetersiz coin! Gereken: " .. short(cost))
		else
			d.coins -= cost
			d[key] += 1
			applyCharacter(player)
			refresh(player)
			notify(player, title .. " yukseltildi! Seviye " .. d[key])
		end
	end)
end

makeStand(Vector3.new(-45, 0.5, 40), Color3.fromRGB(0, 170, 255), "HIZ", "speed", MAX_SPEED_LEVEL, speedCost)
makeStand(Vector3.new(-45, 0.5, 20), Color3.fromRGB(0, 230, 120), "ZIPLAMA", "jump", MAX_JUMP_LEVEL, jumpCost)
makeStand(Vector3.new(-45, 0.5, 0), Color3.fromRGB(255, 170, 0), "COIN CARPANI", "mult", MAX_MULT_LEVEL, multCost)

-- Rebirth
local rebirthPad = makePart({
	Name = "Rebirth",
	Size = Vector3.new(9, 1, 9),
	Position = Vector3.new(45, 0.5, 10),
	Color = Color3.fromRGB(200, 60, 255),
	Material = Enum.Material.Neon,
	Parent = map,
})
addBillboard(rebirthPad, "REBIRTH\nKalici x2 carpan!", Color3.fromRGB(220, 120, 255))
addPrompt(rebirthPad, "Rebirth Yap", "Rebirth").Triggered:Connect(function(player)
	local d = data[player]
	if not d then
		return
	end
	local cost = rebirthCost(d)
	if d.coins < cost then
		notify(player, "Rebirth icin " .. short(cost) .. " coin lazim!")
		return
	end
	d.coins, d.speed, d.jump, d.mult = 0, 0, 0, 0
	d.rebirths += 1
	applyCharacter(player)
	refresh(player)
	notify(player, "REBIRTH! Kalici carpanin artik x" .. (1 + d.rebirths))
end)

-- Bedava odul sandigi
local chest = makePart({
	Name = "OdulSandigi",
	Size = Vector3.new(6, 5, 6),
	Position = Vector3.new(45, 2.5, 40),
	Color = Color3.fromRGB(255, 215, 0),
	Material = Enum.Material.Neon,
	Parent = map,
})
addBillboard(chest, "BEDAVA ODUL\n3 dakikada bir", Color3.fromRGB(255, 230, 80))
addPrompt(chest, "Odulu Al", "Sandik").Triggered:Connect(function(player)
	local d = data[player]
	if not d then
		return
	end
	local wait = CHEST_COOLDOWN - (os.clock() - (lastChest[player] or -CHEST_COOLDOWN))
	if wait > 0 then
		notify(player, "Sandik " .. math.ceil(wait) .. " saniye sonra hazir!")
		return
	end
	lastChest[player] = os.clock()
	local reward = 100 * totalMult(d) * (d.tier + 1)
	d.coins += reward
	refresh(player)
	notify(player, "+" .. short(reward) .. " coin kazandin!")
end)

---------------------------------------------------------------- OYUNCU
local function onPlayerAdded(player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coinStat = Instance.new("IntValue")
	coinStat.Name = "Coin"
	coinStat.Parent = ls
	local rebirthStat = Instance.new("IntValue")
	rebirthStat.Name = "Rebirth"
	rebirthStat.Parent = ls
	ls.Parent = player

	local d, ok = loadData(player)
	if not player.Parent then
		return
	end
	data[player] = d
	loadedOk[player] = ok

	buildHud(player)
	refresh(player)
	notify(player, "Coin topla, guclen, yeni bolgeleri ac!")

	local function onCharacter(char)
		char:WaitForChild("Humanoid")
		task.wait(0.2)
		applyCharacter(player)
		char.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") and data[player] then
				obj.CollisionGroup = "Tier" .. math.clamp(data[player].tier, 0, 2)
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	saveData(player)
	data[player] = nil
	loadedOk[player] = nil
	lastChest[player] = nil
	msgToken[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(saveData, player)
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveData(player)
	end
end)
