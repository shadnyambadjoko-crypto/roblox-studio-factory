--!strict
-- Serveur de « Potager Tycoon » : terrains, plantations, récoltes, sauvegarde, achats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

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

local SelectSeed = makeRemote("SelectSeed") -- client → serveur : (seedId)
local UnlockSeed = makeRemote("UnlockSeed") -- client → serveur : (seedId)
local Notify = makeRemote("Notify") -- serveur → client : (texte)
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- Données joueur
---------------------------------------------------------------------
type PlayerData = {
	coins: number,
	beds: number,
	seeds: { string },
	harvests: number,
}

type Plant = {
	seed: Config.Seed,
	plantedAt: number,
	growTime: number,
	model: Model,
}

type Bed = {
	part: BasePart,
	prompt: ProximityPrompt,
	index: number,
	plant: Plant?,
}

type Plot = {
	index: number,
	owner: Player?,
	base: BasePart,
	spawnCFrame: CFrame,
	sign: TextLabel,
	beds: { Bed },
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Potager] DataStore indisponible (active 'Enable Studio Access to API Services' pour tester la sauvegarde) :", result)
	end
end

local sessionData: { [Player]: PlayerData } = {}
local playerPlot: { [Player]: Plot } = {}
local lastAction: { [Player]: number } = {}

local function defaultData(): PlayerData
	return {
		coins = Config.StartingCoins,
		beds = Config.StartingBeds,
		seeds = { Config.Seeds[1].id },
		harvests = 0,
	}
end

local function sanitize(raw: any): PlayerData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	if type(raw.coins) == "number" and raw.coins >= 0 then
		data.coins = math.floor(raw.coins)
	end
	if type(raw.beds) == "number" then
		data.beds = math.clamp(math.floor(raw.beds), Config.StartingBeds, Config.BedsPerPlot)
	end
	if type(raw.harvests) == "number" then
		data.harvests = math.floor(raw.harvests)
	end
	if type(raw.seeds) == "table" then
		local seeds = {}
		for _, id in raw.seeds do
			if type(id) == "string" and Config.GetSeed(id) and not table.find(seeds, id) then
				table.insert(seeds, id)
			end
		end
		if not table.find(seeds, Config.Seeds[1].id) then
			table.insert(seeds, 1, Config.Seeds[1].id)
		end
		data.seeds = seeds
	end
	return data
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
		warn("[Potager] Échec du chargement (essai " .. attempt .. ") :", result)
		task.wait(attempt)
	end
	player:SetAttribute("SaveDisabled", true) -- on n'écrase pas une sauvegarde qu'on n'a pas pu lire
	return defaultData()
end

local function saveData(player: Player)
	local data = sessionData[player]
	if not store or not data or player:GetAttribute("SaveDisabled") then
		return
	end
	local key = "player_" .. player.UserId
	local snapshot = table.clone(data)
	snapshot.seeds = table.clone(data.seeds)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key, function()
			return snapshot
		end)
	end)
	if not ok then
		warn("[Potager] Échec de la sauvegarde :", err)
	end
end

---------------------------------------------------------------------
-- Pièces et attributs visibles par le client
---------------------------------------------------------------------
local function syncPlayer(player: Player)
	local data = sessionData[player]
	if not data then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Pièces")
	if coins and coins:IsA("IntValue") then
		coins.Value = data.coins
	end
	player:SetAttribute("Coins", data.coins)
	player:SetAttribute("Beds", data.beds)
	player:SetAttribute("UnlockedSeeds", table.concat(data.seeds, ","))
end

local function addCoins(player: Player, amount: number)
	local data = sessionData[player]
	if data then
		data.coins += amount
		syncPlayer(player)
	end
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
	player:SetAttribute("DoubleCoins", ownsPass(player, Config.GamePasses.DoubleCoins))
	player:SetAttribute("FastGrow", ownsPass(player, Config.GamePasses.FastGrow))
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	if passId == Config.GamePasses.DoubleCoins then
		player:SetAttribute("DoubleCoins", true)
		Notify:FireClient(player, "Merci ! Tes récoltes rapportent maintenant x2 💰")
	elseif passId == Config.GamePasses.FastGrow then
		player:SetAttribute("FastGrow", true)
		Notify:FireClient(player, "Merci ! Tes plantes poussent 2x plus vite 🌱")
	end
end)

---------------------------------------------------------------------
-- Produits (achats répétables) : on n'accorde qu'une fois la sauvegarde faite
---------------------------------------------------------------------
local grantedReceipts: { [string]: boolean } = {}

MarketplaceService.ProcessReceipt = function(receipt)
	local purchaseId = receipt.PurchaseId
	if grantedReceipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local amount = Config.DevProducts[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not amount or not player or not sessionData[player] then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox réessaiera plus tard
	end
	addCoins(player, amount)
	if store and not player:GetAttribute("SaveDisabled") then
		local ok = pcall(function()
			local data = sessionData[player]
			local snapshot = table.clone(data)
			snapshot.seeds = table.clone(data.seeds);
			(store :: DataStore):UpdateAsync("player_" .. player.UserId, function()
				return snapshot
			end)
		end)
		if not ok then
			addCoins(player, -amount)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end
	grantedReceipts[purchaseId] = true
	Notify:FireClient(player, "+" .. amount .. " pièces ! Merci 🙏")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------
-- Construction de la carte
---------------------------------------------------------------------
local mapFolder = Instance.new("Folder")
mapFolder.Name = "Potager"

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

local plots: { Plot } = {}
local PLOT_SIZE = 46
local BED_SIZE = 8
local BED_GAP = 4

local function updateBedPrompt(plot: Plot, bed: Bed)
	local prompt = bed.prompt
	local owner = plot.owner
	local data = owner and sessionData[owner]
	if not owner or not data then
		prompt.Enabled = false
		bed.part.Color = Color3.fromRGB(90, 70, 55)
		bed.part.Transparency = 0.6
		return
	end
	if bed.index > data.beds then
		bed.part.Transparency = 0.6
		bed.part.Color = Color3.fromRGB(90, 70, 55)
		if bed.index == data.beds + 1 then
			prompt.Enabled = true
			prompt.ActionText = "Acheter (" .. Config.BedPrice(data.beds) .. " 💰)"
			prompt.ObjectText = "Nouvelle parcelle"
		else
			prompt.Enabled = false
		end
		return
	end
	bed.part.Transparency = 0
	bed.part.Color = Color3.fromRGB(110, 75, 45)
	prompt.Enabled = true
	local plant = bed.plant
	if not plant then
		local seed = Config.GetSeed((owner:GetAttribute("SelectedSeed") :: string?) or "") or Config.Seeds[1]
		prompt.ActionText = "Planter (" .. seed.cost .. " 💰)"
		prompt.ObjectText = seed.name
	elseif os.clock() - plant.plantedAt >= plant.growTime then
		prompt.ActionText = "Récolter"
		prompt.ObjectText = plant.seed.name .. " mûr(e) !"
	else
		local left = math.ceil(plant.growTime - (os.clock() - plant.plantedAt))
		prompt.ActionText = "Pousse… " .. left .. " s"
		prompt.ObjectText = plant.seed.name
	end
end

local function refreshPlot(plot: Plot)
	for _, bed in plot.beds do
		updateBedPrompt(plot, bed)
	end
end

local function makePlantModel(seed: Config.Seed, bed: Bed): Model
	local model = Instance.new("Model")
	model.Name = seed.name
	local top = bed.part.Position + Vector3.new(0, bed.part.Size.Y / 2, 0)
	local stem = part({
		Name = "Tige",
		Size = Vector3.new(0.4, 2, 0.4),
		Color = Color3.fromRGB(60, 160, 60),
		Material = Enum.Material.Grass,
		CanCollide = false,
		CanQuery = false,
		Position = top + Vector3.new(0, 1, 0),
	})
	stem.Parent = model
	local fruit = part({
		Name = "Fruit",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		Color = seed.color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		Position = top + Vector3.new(0, 2.6, 0),
	})
	fruit.Parent = model
	model.WorldPivot = CFrame.new(top) -- la plante grandit depuis la terre
	model:ScaleTo(0.2)
	model.Parent = bed.part
	return model
end

local function onBedTriggered(plot: Plot, bed: Bed, player: Player)
	if plot.owner ~= player then
		Notify:FireClient(player, "Ce n'est pas ton potager 🙂")
		return
	end
	local data = sessionData[player]
	if not data then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.15 then
		return
	end
	lastAction[player] = now

	-- Acheter une parcelle
	if bed.index > data.beds then
		if bed.index ~= data.beds + 1 then
			return
		end
		local price = Config.BedPrice(data.beds)
		if data.coins < price then
			Notify:FireClient(player, "Il te manque " .. (price - data.coins) .. " pièces")
			return
		end
		data.coins -= price
		data.beds += 1
		syncPlayer(player)
		refreshPlot(plot)
		Notify:FireClient(player, "Nouvelle parcelle débloquée ! 🎉")
		return
	end

	local plant = bed.plant
	if not plant then
		-- Planter
		local seedId = (player:GetAttribute("SelectedSeed") :: string?) or Config.Seeds[1].id
		local seed = Config.GetSeed(seedId)
		if not seed or not table.find(data.seeds, seed.id) then
			seed = Config.Seeds[1]
		end
		local s = seed :: Config.Seed
		if data.coins < s.cost then
			Notify:FireClient(player, "Pas assez de pièces pour planter : " .. s.name)
			return
		end
		data.coins -= s.cost
		syncPlayer(player)
		local growTime = if player:GetAttribute("FastGrow") then s.growTime / 2 else s.growTime
		bed.plant = {
			seed = s,
			plantedAt = now,
			growTime = growTime,
			model = makePlantModel(s, bed),
		}
		updateBedPrompt(plot, bed)
	elseif now - plant.plantedAt >= plant.growTime then
		-- Récolter
		local reward = plant.seed.reward
		if player:GetAttribute("DoubleCoins") then
			reward *= 2
		end
		plant.model:Destroy()
		bed.plant = nil
		data.harvests += 1
		addCoins(player, reward)
		updateBedPrompt(plot, bed)
		Notify:FireClient(player, "+" .. reward .. " 💰")
	end
end

local function buildPlot(index: number, origin: Vector3): Plot
	local folder = Instance.new("Folder")
	folder.Name = "Terrain" .. index

	local base = part({
		Name = "Herbe",
		Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
		Position = origin,
		Color = Color3.fromRGB(95, 170, 80),
		Material = Enum.Material.Grass,
	})
	base.Parent = folder

	-- Clôture basse
	for _, offset in { Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) } do
		local alongX = offset.Z ~= 0
		local fence = part({
			Name = "Cloture",
			Size = if alongX then Vector3.new(PLOT_SIZE, 1.5, 0.6) else Vector3.new(0.6, 1.5, PLOT_SIZE),
			Position = origin + offset * (PLOT_SIZE / 2) + Vector3.new(0, 1.25, 0),
			Color = Color3.fromRGB(235, 225, 205),
			Material = Enum.Material.Wood,
		})
		fence.Parent = folder
	end

	-- Panneau avec le nom du propriétaire
	local signPost = part({
		Name = "Panneau",
		Size = Vector3.new(10, 4, 0.5),
		Position = origin + Vector3.new(0, 5, -PLOT_SIZE / 2 + 1),
		Color = Color3.fromRGB(160, 110, 60),
		Material = Enum.Material.Wood,
	})
	signPost.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = "Terrain libre"
	label.Parent = gui
	gui.Parent = signPost

	local plot: Plot = {
		index = index,
		owner = nil,
		base = base,
		spawnCFrame = CFrame.new(origin + Vector3.new(0, 4, -PLOT_SIZE / 2 + 6)) * CFrame.Angles(0, math.pi, 0),
		sign = label,
		beds = {},
	}

	-- 3 x 3 parcelles
	local span = BED_SIZE * 3 + BED_GAP * 2
	local start = origin + Vector3.new(-span / 2 + BED_SIZE / 2, 0.75, -span / 2 + BED_SIZE / 2 + 3)
	local i = 0
	for row = 0, 2 do
		for col = 0, 2 do
			i += 1
			local bedPart = part({
				Name = "Parcelle" .. i,
				Size = Vector3.new(BED_SIZE, 0.6, BED_SIZE),
				Position = start + Vector3.new(col * (BED_SIZE + BED_GAP), 0, row * (BED_SIZE + BED_GAP)),
				Material = Enum.Material.Ground,
			})
			local prompt = Instance.new("ProximityPrompt")
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 9
			prompt.RequiresLineOfSight = false
			prompt.Parent = bedPart
			bedPart.Parent = folder
			local bed: Bed = { part = bedPart, prompt = prompt, index = i, plant = nil }
			table.insert(plot.beds, bed)
			prompt.Triggered:Connect(function(player)
				onBedTriggered(plot, bed, player)
			end)
		end
	end

	folder.Parent = mapFolder
	return plot
end

do
	local ground = workspace:FindFirstChild("Baseplate")
	if not ground then
		local g = part({
			Name = "Baseplate",
			Size = Vector3.new(400, 2, 400),
			Position = Vector3.new(0, -1.5, 0),
			Color = Color3.fromRGB(120, 190, 100),
			Material = Enum.Material.Grass,
		})
		g.Parent = workspace
	end
	local cols = 3
	for index = 1, Config.PlotCount do
		local row = (index - 1) // cols
		local col = (index - 1) % cols
		local origin = Vector3.new((col - 1) * (PLOT_SIZE + 14), 0, (row - 0.5) * (PLOT_SIZE + 30))
		table.insert(plots, buildPlot(index, origin))
	end
	mapFolder.Parent = workspace
end

---------------------------------------------------------------------
-- Arrivée / départ des joueurs
---------------------------------------------------------------------
local function assignPlot(player: Player): Plot?
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			plot.sign.Text = "Potager de " .. player.DisplayName
			playerPlot[player] = plot
			return plot
		end
	end
	return nil
end

local function freePlot(player: Player)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	for _, bed in plot.beds do
		if bed.plant then
			bed.plant.model:Destroy()
			bed.plant = nil
		end
	end
	plot.owner = nil
	plot.sign.Text = "Terrain libre"
	playerPlot[player] = nil
	refreshPlot(plot)
end

local function onCharacterAdded(player: Player, character: Model)
	local plot = playerPlot[player]
	if plot then
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait(0.1) -- laisse Roblox placer le personnage, puis on le déplace
			if character.Parent then
				character:PivotTo(plot.spawnCFrame)
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Pièces"
	coins.Parent = leaderstats
	leaderstats.Parent = player

	player:SetAttribute("SelectedSeed", Config.Seeds[1].id)
	local data = loadData(player)
	if player.Parent == nil then
		return -- parti pendant le chargement
	end
	sessionData[player] = data
	syncPlayer(player)
	task.spawn(refreshPasses, player)

	local plot = assignPlot(player)
	if not plot then
		player:Kick("Serveur plein, réessaie dans un autre serveur !")
		return
	end
	refreshPlot(plot)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	saveData(player)
	freePlot(player)
	sessionData[player] = nil
	lastAction[player] = nil
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
SelectSeed.OnServerEvent:Connect(function(player: Player, seedId: unknown)
	local data = sessionData[player]
	if not data or type(seedId) ~= "string" then
		return
	end
	if table.find(data.seeds, seedId) then
		player:SetAttribute("SelectedSeed", seedId)
		local plot = playerPlot[player]
		if plot then
			refreshPlot(plot)
		end
	end
end)

UnlockSeed.OnServerEvent:Connect(function(player: Player, seedId: unknown)
	local data = sessionData[player]
	if not data or type(seedId) ~= "string" then
		return
	end
	local seed = Config.GetSeed(seedId)
	if not seed or table.find(data.seeds, seedId) then
		return
	end
	if data.coins < seed.unlockPrice then
		Notify:FireClient(player, "Il te manque " .. (seed.unlockPrice - data.coins) .. " pièces")
		return
	end
	data.coins -= seed.unlockPrice
	table.insert(data.seeds, seedId)
	player:SetAttribute("SelectedSeed", seedId)
	syncPlayer(player)
	local plot = playerPlot[player]
	if plot then
		refreshPlot(plot)
	end
	Notify:FireClient(player, seed.name .. " débloqué(e) ! 🌟")
end)

---------------------------------------------------------------------
-- Croissance des plantes
---------------------------------------------------------------------
local accumulator = 0
RunService.Heartbeat:Connect(function(dt: number)
	accumulator += dt
	if accumulator < 0.5 then
		return
	end
	accumulator = 0
	local now = os.clock()
	for _, plot in plots do
		if plot.owner then
			for _, bed in plot.beds do
				local plant = bed.plant
				if plant then
					local progress = math.clamp((now - plant.plantedAt) / plant.growTime, 0, 1)
					plant.model:ScaleTo(0.2 + 0.8 * progress)
					if progress >= 1 and not plant.model:FindFirstChild("Brillance") then
						local fruit = plant.model:FindFirstChild("Fruit")
						if fruit then
							local sparkles = Instance.new("Sparkles")
							sparkles.Name = "Brillance"
							sparkles.SparkleColor = plant.seed.color
							sparkles.Parent = fruit
							local marker = Instance.new("BoolValue")
							marker.Name = "Brillance"
							marker.Parent = plant.model
						end
					end
					updateBedPrompt(plot, bed)
				end
			end
		end
	end
end)
