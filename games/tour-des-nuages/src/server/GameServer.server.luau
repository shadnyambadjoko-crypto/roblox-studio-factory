--!strict
-- Serveur de « Tour des Nuages +1 » : puissance de saut gagnée en courant, tour en spirale,
-- étoiles, bottes, checkpoints, renaissance, sauvegarde, achats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"

local function makeRemote(name: string): RemoteEvent
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local BuyBoots = makeRemote("BuyBoots") -- client → serveur
local Rebirth = makeRemote("Rebirth") -- client → serveur
local Teleport = makeRemote("Teleport") -- client → serveur : ("checkpoint" | "sol")
local Notify = makeRemote("Notify") -- serveur → client : (texte)
local Celebrate = makeRemote("Celebrate") -- serveur → client : (étage)
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- Données joueur
---------------------------------------------------------------------
type PlayerData = {
	points: number, -- puissance de saut accumulée (remise à 0 à la renaissance)
	stars: number,
	boots: number,
	rebirths: number,
	wins: number,
	runBest: number, -- meilleur étage de l'ascension en cours
	record: number, -- meilleur étage de tous les temps
	receipts: { string },
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Nuages] DataStore indisponible (active 'Enable Studio Access to API Services' pour tester la sauvegarde) :", result)
	end
end

local sessionData: { [Player]: PlayerData } = {}
local carry: { [Player]: number } = {} -- fraction de point pas encore accordée
local lastPos: { [Player]: Vector3 } = {}
local lastRequest: { [Player]: number } = {}

local function defaultData(): PlayerData
	return { points = 0, stars = 0, boots = 0, rebirths = 0, wins = 0, runBest = 0, record = 0, receipts = {} }
end

local function num(v: any, min: number, max: number, default: number): number
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(math.floor(v), min, max)
end

local function sanitize(raw: any): PlayerData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	data.points = num(raw.points, 0, 1e9, 0)
	data.stars = num(raw.stars, 0, 1e12, 0)
	data.boots = num(raw.boots, 0, Config.BootsMaxLevel, 0)
	data.rebirths = num(raw.rebirths, 0, 1e6, 0)
	data.wins = num(raw.wins, 0, 1e6, 0)
	data.runBest = num(raw.runBest, 0, Config.FloorCount + 1, 0)
	data.record = num(raw.record, 0, Config.FloorCount + 1, 0)
	if type(raw.receipts) == "table" then
		for _, id in raw.receipts do
			if type(id) == "string" and #data.receipts < 50 then
				table.insert(data.receipts, id)
			end
		end
	end
	return data
end

local function snapshot(data: PlayerData): PlayerData
	local copy = table.clone(data)
	copy.receipts = table.clone(data.receipts)
	return copy
end

local function loadData(player: Player): PlayerData
	if not store then
		return defaultData()
	end
	local key = "player_" .. player.UserId
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key)
		end)
		if ok then
			return sanitize(result)
		end
		warn("[Nuages] Échec du chargement (essai " .. attempt .. ") :", result)
		task.wait(attempt)
	end
	player:SetAttribute("SaveDisabled", true) -- on n'écrase pas une sauvegarde illisible
	return defaultData()
end

local function saveData(player: Player): boolean
	local data = sessionData[player]
	if not store or not data or player:GetAttribute("SaveDisabled") then
		return false
	end
	local copy = snapshot(data)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync("player_" .. player.UserId, function()
			return copy
		end)
	end)
	if not ok then
		warn("[Nuages] Échec de la sauvegarde :", err)
	end
	return ok
end

---------------------------------------------------------------------
-- Calculs et synchronisation
---------------------------------------------------------------------
local function multiplier(player: Player, data: PlayerData): number
	local m = Config.BootsMultiplier(data.boots) * Config.RebirthMultiplier(data.rebirths)
	if player:GetAttribute("DoubleSteps") then
		m *= 2
	end
	return m
end

local function applyHumanoid(player: Player)
	local data = sessionData[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not humanoid then
		return
	end
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.JumpPowerFromPoints(data.points)
	humanoid.WalkSpeed = if player:GetAttribute("FastRunner") then Config.FastWalkSpeed else 16
end

local function syncPlayer(player: Player)
	local data = sessionData[player]
	if not data then
		return
	end
	local jump = math.floor(Config.JumpPowerFromPoints(data.points))
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local s = leaderstats:FindFirstChild("Saut")
		if s and s:IsA("IntValue") then
			s.Value = jump
		end
		local w = leaderstats:FindFirstChild("Sommets")
		if w and w:IsA("IntValue") then
			w.Value = data.wins
		end
	end
	player:SetAttribute("Points", data.points)
	player:SetAttribute("Jump", jump)
	player:SetAttribute("Stars", data.stars)
	player:SetAttribute("Boots", data.boots)
	player:SetAttribute("Rebirths", data.rebirths)
	player:SetAttribute("RunBest", data.runBest)
	player:SetAttribute("Record", data.record)
	player:SetAttribute("Multiplier", multiplier(player, data))
	applyHumanoid(player)
end

---------------------------------------------------------------------
-- Pass de jeu
---------------------------------------------------------------------
local function ownsPass(player: Player, passId: number): boolean
	if passId == 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	return ok and owns == true
end

local function refreshPasses(player: Player)
	player:SetAttribute("DoubleSteps", ownsPass(player, Config.GamePasses.DoubleSteps))
	player:SetAttribute("FastRunner", ownsPass(player, Config.GamePasses.FastRunner))
	syncPlayer(player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	if passId == Config.GamePasses.DoubleSteps then
		player:SetAttribute("DoubleSteps", true)
		Notify:FireClient(player, "Merci ! Chaque pas compte double 👟👟")
	elseif passId == Config.GamePasses.FastRunner then
		player:SetAttribute("FastRunner", true)
		Notify:FireClient(player, "Merci ! Tu cours plus vite ⚡")
	end
	syncPlayer(player)
end)

---------------------------------------------------------------------
-- Produits (achats répétables) : accordés une seule fois, après sauvegarde
---------------------------------------------------------------------
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and sessionData[player]
	local amount = Config.DevProducts[receipt.ProductId]
	if not player or not data or not amount then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	data.points += amount
	table.insert(data.receipts, purchaseId)
	if #data.receipts > 50 then
		table.remove(data.receipts, 1)
	end
	if store and not player:GetAttribute("SaveDisabled") and not saveData(player) then
		data.points -= amount
		local i = table.find(data.receipts, purchaseId)
		if i then
			table.remove(data.receipts, i)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	syncPlayer(player)
	Notify:FireClient(player, "+" .. amount .. " points de saut ! Merci 🙏")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------
-- Construction de la carte
---------------------------------------------------------------------
local map = Instance.new("Folder")
map.Name = "TourDesNuages"

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function label(parent: BasePart, text: string, size: number, offset: Vector3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size * 2, size)
	gui.StudsOffset = offset
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.Parent = gui
	gui.Parent = parent
end

type Floor = { index: number, part: BasePart, checkpoint: boolean }
local floors: { Floor } = {}
local floorTop: { number } = {}

-- Sol
local ground = part({
	Name = "Prairie",
	Size = Vector3.new(500, 2, 500),
	Position = Vector3.new(0, -1, 0),
	Color = Color3.fromRGB(150, 215, 140),
	Material = Enum.Material.Grass,
})
ground.Parent = map

-- Piste de course décorative autour de la tour (on peut courir partout)
for i = 0, 35 do
	local a = i / 36 * math.pi * 2
	local tile = part({
		Name = "Piste",
		Size = Vector3.new(9, 0.2, 10),
		CFrame = CFrame.new(math.cos(a) * 75, 0.1, math.sin(a) * 75) * CFrame.Angles(0, -a, 0),
		Color = if i % 2 == 0 then Color3.fromRGB(240, 120, 110) else Color3.fromRGB(255, 160, 130),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	tile.Parent = map
end

-- Panneau d'accueil
local welcome = part({
	Name = "Panneau",
	Size = Vector3.new(14, 6, 0.6),
	Position = Vector3.new(0, 5, 52),
	Color = Color3.fromRGB(255, 250, 240),
	Material = Enum.Material.SmoothPlastic,
})
welcome.Parent = map
do
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.fromRGB(70, 90, 160)
	t.Text = "Cours = +1 saut 👟\nSaute d'étage en étage ☁️\nAtteins le sommet !"
	t.Parent = gui
	gui.Parent = welcome
end

-- Étages en spirale
local height = 0
for i = 1, Config.FloorCount do
	height += Config.FloorRise(i)
	local angle = i * Config.SpiralStep
	local hue = (0.55 + i / Config.FloorCount * 0.4) % 1
	local isCheckpoint = i % Config.CheckpointEvery == 0
	local size = Config.PlatformSize + (if isCheckpoint then 4 else 0)
	local p = part({
		Name = "Etage" .. i,
		Size = Vector3.new(size, 2, size),
		Position = Vector3.new(math.cos(angle) * Config.SpiralRadius, height - 1, math.sin(angle) * Config.SpiralRadius),
		Color = if isCheckpoint then Color3.fromRGB(255, 225, 120) else Color3.fromHSV(hue, 0.18, 1),
		Material = Enum.Material.SmoothPlastic,
	})
	p:SetAttribute("Floor", i)
	label(p, (if isCheckpoint then "⭐ " else "") .. "Étage " .. i, 3, Vector3.new(0, 4, 0))
	-- petits nuages décoratifs sous la plateforme
	for k = 1, 3 do
		local puff = part({
			Name = "Nuage",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(6, 6, 6),
			Position = p.Position + Vector3.new((k - 2) * 4, -2, (k % 2) * 3 - 1.5),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		puff.Parent = p
	end
	p.Parent = map
	floors[i] = { index = i, part = p, checkpoint = isCheckpoint }
	floorTop[i] = height
end

-- Sommet
local SUMMIT = Config.FloorCount + 1
local summitHeight = height + Config.FloorRise(SUMMIT)
local summit = part({
	Name = "Sommet",
	Size = Vector3.new(26, 2, 26),
	Position = Vector3.new(0, summitHeight - 1, 0),
	Color = Color3.fromRGB(255, 205, 60),
	Material = Enum.Material.Neon,
})
summit:SetAttribute("Floor", SUMMIT)
label(summit, "🏆 SOMMET 🏆", 6, Vector3.new(0, 7, 0))
summit.Parent = map
floors[SUMMIT] = { index = SUMMIT, part = summit, checkpoint = true }
floorTop[SUMMIT] = summitHeight

map.Parent = workspace

-- Ciel
do
	Lighting.ClockTime = 15
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.25
	atmo.Haze = 1.2
	atmo.Color = Color3.fromRGB(200, 225, 255)
	atmo.Decay = Color3.fromRGB(255, 220, 240)
	atmo.Parent = Lighting
end

local function floorCFrame(index: number): CFrame
	local f = floors[index]
	return CFrame.new(f.part.Position + Vector3.new(0, 4, 0))
end

local function lastCheckpoint(runBest: number): number
	return runBest - runBest % Config.CheckpointEvery
end

---------------------------------------------------------------------
-- Arrivée sur un étage
---------------------------------------------------------------------
local function reachFloor(player: Player, index: number)
	local data = sessionData[player]
	if not data or index <= data.runBest then
		return
	end
	-- Un étage n'est validé que si on avait la puissance nécessaire pour le précédent (anti-triche simple)
	if index > data.runBest + 1 and index ~= SUMMIT then
		local needed = Config.JumpPowerFor(Config.FloorRise(index))
		if Config.JumpPowerFromPoints(data.points) < needed * 0.7 then
			return
		end
	end
	data.runBest = index
	data.record = math.max(data.record, index)
	if index == SUMMIT then
		data.stars += Config.SummitReward
		data.wins += 1
		Notify:FireClient(player, "🏆 SOMMET ! +" .. Config.SummitReward .. " ⭐ — Renaissance disponible !")
	else
		local reward = Config.FloorReward(index)
		data.stars += reward
		local msg = "Étage " .. index .. " ! +" .. reward .. " ⭐"
		if floors[index].checkpoint then
			msg ..= " — checkpoint ✅"
		end
		Notify:FireClient(player, msg)
	end
	Celebrate:FireClient(player, index)
	syncPlayer(player)
end

for _, f in floors do
	local index = f.index
	f.part.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			reachFloor(player, index)
		end
	end)
end

---------------------------------------------------------------------
-- Points gagnés en courant (calcul côté serveur uniquement)
---------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	for player, data in sessionData do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local pos = root.Position
			local prev = lastPos[player]
			lastPos[player] = pos
			if prev and humanoid.FloorMaterial ~= Enum.Material.Air and humanoid.MoveDirection.Magnitude > 0.1 then
				local flat = Vector3.new(pos.X - prev.X, 0, pos.Z - prev.Z).Magnitude
				-- plafonné à la vitesse de marche : un téléport ou un exploit de vitesse ne rapporte rien
				local d = math.min(flat, humanoid.WalkSpeed * dt * 1.25)
				local gained = d / Config.StudsPerPoint * multiplier(player, data) + (carry[player] or 0)
				local whole = math.floor(gained)
				carry[player] = gained - whole
				if whole > 0 then
					data.points += whole
					player:SetAttribute("Points", data.points)
					local jump = Config.JumpPowerFromPoints(data.points)
					humanoid.JumpPower = jump
					if math.floor(jump) ~= player:GetAttribute("Jump") then
						syncPlayer(player)
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Arrivée / départ des joueurs
---------------------------------------------------------------------
local function onCharacterAdded(player: Player, character: Model)
	lastPos[player] = nil
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end
	applyHumanoid(player)
	local data = sessionData[player]
	if data then
		local cp = lastCheckpoint(data.runBest)
		if cp > 0 then
			task.wait(0.1)
			if character.Parent then
				character:PivotTo(floorCFrame(cp))
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local s = Instance.new("IntValue")
	s.Name = "Saut"
	s.Parent = leaderstats
	local w = Instance.new("IntValue")
	w.Name = "Sommets"
	w.Parent = leaderstats
	leaderstats.Parent = player

	local data = loadData(player)
	if player.Parent == nil then
		return
	end
	sessionData[player] = data
	syncPlayer(player)
	task.spawn(refreshPasses, player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	saveData(player)
	sessionData[player] = nil
	carry[player] = nil
	lastPos[player] = nil
	lastRequest[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

game:BindToClose(function()
	if RunService:IsStudio() and not store then
		return
	end
	local pending = 0
	for _, player in Players:GetPlayers() do
		pending += 1
		task.spawn(function()
			saveData(player)
			pending -= 1
		end)
	end
	local started = os.clock()
	while pending > 0 and os.clock() - started < 25 do
		task.wait(0.2)
	end
end)

task.spawn(function()
	while true do
		task.wait(Config.AutosaveInterval)
		for _, player in Players:GetPlayers() do
			task.spawn(saveData, player)
		end
	end
end)

---------------------------------------------------------------------
-- Remotes client → serveur (tout est vérifié ici)
---------------------------------------------------------------------
local function throttled(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < 0.3 then
		return true
	end
	lastRequest[player] = now
	return false
end

BuyBoots.OnServerEvent:Connect(function(player: Player)
	local data = sessionData[player]
	if not data or throttled(player) then
		return
	end
	if data.boots >= Config.BootsMaxLevel then
		Notify:FireClient(player, "Bottes au niveau maximum ! 👢")
		return
	end
	local price = Config.BootsPrice(data.boots)
	if data.stars < price then
		Notify:FireClient(player, "Il te manque " .. (price - data.stars) .. " ⭐")
		return
	end
	data.stars -= price
	data.boots += 1
	syncPlayer(player)
	Notify:FireClient(player, "Bottes niveau " .. data.boots .. " ! Chaque pas rapporte plus 👟")
end)

Rebirth.OnServerEvent:Connect(function(player: Player)
	local data = sessionData[player]
	if not data or throttled(player) then
		return
	end
	if data.runBest < SUMMIT then
		Notify:FireClient(player, "Atteins d'abord le sommet 🏆")
		return
	end
	data.rebirths += 1
	data.points = 0
	data.runBest = 0
	carry[player] = 0
	syncPlayer(player)
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(0, 5, 40))
	end
	Notify:FireClient(player, "Renaissance " .. data.rebirths .. " ! Tes pas valent maintenant x" .. Config.RebirthMultiplier(data.rebirths) .. " 🌈")
end)

Teleport.OnServerEvent:Connect(function(player: Player, where: unknown)
	local data = sessionData[player]
	local character = player.Character
	if not data or not character or throttled(player) then
		return
	end
	if where == "sol" then
		character:PivotTo(CFrame.new(0, 5, 40))
	elseif where == "checkpoint" then
		local cp = lastCheckpoint(data.runBest)
		if cp == 0 then
			Notify:FireClient(player, "Pas encore de checkpoint : atteins l'étage " .. Config.CheckpointEvery .. " ⭐")
			return
		end
		character:PivotTo(floorCFrame(cp))
	end
	lastPos[player] = nil
end)
