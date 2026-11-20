--!strict
-- Serveur du « Refuge des Bestioles » : zones, bestioles sauvages, panier, refuges, enclos,
-- boîte à cœurs, bestiaire, adoption, sauvegarde, achats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
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

local UpgradeNet = makeRemote("UpgradeNet") -- client → serveur
local Notify = makeRemote("Notify") -- serveur → client : (texte)
local Discovered = makeRemote("Discovered") -- serveur → client : (speciesId)
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- Données joueur
---------------------------------------------------------------------
type PlayerData = {
	hearts: number,
	slots: number,
	net: number,
	pens: { string }, -- espèces installées (une par enclos)
	zones: { string },
	discovered: { string },
	adopted: number,
	receipts: { string },
	basket: { string }, -- bestioles dans le panier (sauvegardées aussi)
}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[Refuge] DataStore indisponible (active 'Enable Studio Access to API Services' pour tester la sauvegarde) :", result)
	end
end

local sessionData: { [Player]: PlayerData } = {}
local carried: { [Player]: { string } } = {}
local boxHearts: { [Player]: number } = {}
local lastRequest: { [Player]: number } = {}

local function defaultData(): PlayerData
	return {
		hearts = Config.StartingHearts,
		slots = Config.StartingSlots,
		net = 0,
		pens = {},
		zones = { "prairie" },
		discovered = {},
		adopted = 0,
		receipts = {},
		basket = {},
	}
end

local function num(v: any, min: number, max: number, default: number): number
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(math.floor(v), min, max)
end

local function idList(raw: any, valid: (string) -> boolean, max: number, unique: boolean): { string }
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, id in raw do
		if #out >= max then
			break
		end
		if type(id) == "string" and valid(id) and not (unique and table.find(out, id)) then
			table.insert(out, id)
		end
	end
	return out
end

local function isSpecies(id: string): boolean
	return Config.GetSpecies(id) ~= nil
end

local function sanitize(raw: any): PlayerData
	local data = defaultData()
	if type(raw) ~= "table" then
		return data
	end
	data.hearts = num(raw.hearts, 0, 1e13, Config.StartingHearts)
	data.slots = num(raw.slots, Config.StartingSlots, Config.MaxSlots, Config.StartingSlots)
	data.net = num(raw.net, 0, Config.NetMaxLevel, 0)
	data.adopted = num(raw.adopted, 0, 1e9, 0)
	data.pens = idList(raw.pens, isSpecies, data.slots, false)
	data.discovered = idList(raw.discovered, isSpecies, #Config.Species, true)
	data.zones = idList(raw.zones, function(id)
		return Config.GetZone(id) ~= nil
	end, #Config.Zones, true)
	if not table.find(data.zones, "prairie") then
		table.insert(data.zones, 1, "prairie")
	end
	data.basket = idList(raw.basket, isSpecies, Config.NetCapacity(Config.NetMaxLevel) + Config.BigBasketBonus, false)
	data.receipts = idList(raw.receipts, function()
		return true
	end, 50, true)
	return data
end

local function snapshot(data: PlayerData): PlayerData
	local copy = table.clone(data)
	copy.pens = table.clone(data.pens)
	copy.zones = table.clone(data.zones)
	copy.discovered = table.clone(data.discovered)
	copy.receipts = table.clone(data.receipts)
	copy.basket = table.clone(data.basket)
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
		warn("[Refuge] Échec du chargement (essai " .. attempt .. ") :", result)
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
	-- les cœurs encore dans la boîte sont sauvegardés avec le reste
	copy.hearts += math.floor(boxHearts[player] or 0)
	copy.basket = table.clone(carried[player] or {})
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync("player_" .. player.UserId, function()
			return copy
		end)
	end)
	if not ok then
		warn("[Refuge] Échec de la sauvegarde :", err)
	end
	return ok
end

---------------------------------------------------------------------
-- Calculs et synchronisation
---------------------------------------------------------------------
local function heartsPerSecond(player: Player, data: PlayerData): number
	local total = 0
	for _, id in data.pens do
		local s = Config.GetSpecies(id)
		if s then
			total += s.hps
		end
	end
	if player:GetAttribute("DoubleHearts") then
		total *= 2
	end
	return total
end

local function capacity(player: Player, data: PlayerData): number
	return Config.NetCapacity(data.net) + (if player:GetAttribute("BigBasket") then Config.BigBasketBonus else 0)
end

local function syncPlayer(player: Player)
	local data = sessionData[player]
	if not data then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local h = leaderstats:FindFirstChild("Cœurs")
		if h and h:IsA("IntValue") then
			h.Value = math.min(data.hearts, 2 ^ 31 - 1)
		end
		local b = leaderstats:FindFirstChild("Bestioles")
		if b and b:IsA("IntValue") then
			b.Value = #data.pens
		end
	end
	player:SetAttribute("Hearts", data.hearts)
	player:SetAttribute("HPS", heartsPerSecond(player, data))
	player:SetAttribute("Net", data.net)
	player:SetAttribute("Capacity", capacity(player, data))
	player:SetAttribute("Carried", #(carried[player] or {}))
	player:SetAttribute("PenCount", #data.pens)
	player:SetAttribute("Slots", data.slots)
	player:SetAttribute("Zones", table.concat(data.zones, ","))
	player:SetAttribute("Discovered", table.concat(data.discovered, ","))
	player:SetAttribute("Box", math.floor(boxHearts[player] or 0))
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
	player:SetAttribute("DoubleHearts", ownsPass(player, Config.GamePasses.DoubleHearts))
	player:SetAttribute("BigBasket", ownsPass(player, Config.GamePasses.BigBasket))
	syncPlayer(player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	if passId == Config.GamePasses.DoubleHearts then
		player:SetAttribute("DoubleHearts", true)
		Notify:FireClient(player, "Merci ! Tes bestioles donnent x2 cœurs 💞")
	elseif passId == Config.GamePasses.BigBasket then
		player:SetAttribute("BigBasket", true)
		Notify:FireClient(player, "Merci ! Ton panier a +" .. Config.BigBasketBonus .. " places 🧺")
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
	data.hearts += amount
	table.insert(data.receipts, purchaseId)
	if #data.receipts > 50 then
		table.remove(data.receipts, 1)
	end
	if store and not player:GetAttribute("SaveDisabled") and not saveData(player) then
		data.hearts -= amount
		local i = table.find(data.receipts, purchaseId)
		if i then
			table.remove(data.receipts, i)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	syncPlayer(player)
	Notify:FireClient(player, "+" .. amount .. " ❤ ! Merci 🙏")
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------
-- Outils de construction
---------------------------------------------------------------------
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

local function billboard(parent: Instance, text: string, color: Color3, height: number, width: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = 70
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.Text = text
	t.Parent = gui
	gui.Parent = parent
	return t
end

local function surfaceText(target: BasePart, face: Enum.NormalId, text: string, color: Color3): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color
	t.Text = text
	t.Parent = gui
	gui.Parent = target
	return t
end

-- Modèle d'une bestiole : corps rond, oreilles, yeux, aura selon la rareté
local function makeCritter(species: Config.Species, cf: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = species.name
	local s = species.size
	local body = part({
		Name = "Corps",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(s, s, s),
		CFrame = cf,
		Color = species.color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	})
	body.Parent = model
	local function attach(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p = part({
			Name = name,
			Shape = Enum.PartType.Ball,
			Size = size,
			CFrame = cf * CFrame.new(offset),
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Anchored = false,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Massless = true,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
	end
	attach("OreilleG", Vector3.new(s * 0.3, s * 0.55, s * 0.3), Vector3.new(-s * 0.25, s * 0.5, 0), species.accent)
	attach("OreilleD", Vector3.new(s * 0.3, s * 0.55, s * 0.3), Vector3.new(s * 0.25, s * 0.5, 0), species.accent)
	attach("OeilG", Vector3.new(s * 0.16, s * 0.16, s * 0.16), Vector3.new(-s * 0.18, s * 0.1, -s * 0.44), Color3.fromRGB(30, 30, 40))
	attach("OeilD", Vector3.new(s * 0.16, s * 0.16, s * 0.16), Vector3.new(s * 0.18, s * 0.1, -s * 0.44), Color3.fromRGB(30, 30, 40))
	attach("Nez", Vector3.new(s * 0.12, s * 0.12, s * 0.12), Vector3.new(0, -s * 0.05, -s * 0.5), species.accent)
	if species.rarity ~= "Commune" then
		local light = Instance.new("PointLight")
		light.Color = Config.RarityColors[species.rarity]
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = body
	end
	if species.rarity == "Épique" or species.rarity == "Légendaire" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Config.RarityColors[species.rarity]
		sparkles.Parent = body
	end
	model.PrimaryPart = body
	return model, body
end

---------------------------------------------------------------------
-- Carte : place centrale, zones, portails
---------------------------------------------------------------------
local map = Instance.new("Folder")
map.Name = "Monde"

local ground = part({
	Name = "Sol",
	Size = Vector3.new(420, 2, 520),
	Position = Vector3.new(0, -1, 140),
	Color = Color3.fromRGB(165, 215, 135),
	Material = Enum.Material.Grass,
})
ground.Parent = map

local rng = Random.new()
local W = Config.ZoneHalfWidth

-- Murs invisibles autour des zones
for _, w in
	{
		{ size = Vector3.new(2, 40, 360), pos = Vector3.new(-W - 1, 20, 190) },
		{ size = Vector3.new(2, 40, 360), pos = Vector3.new(W + 1, 20, 190) },
		{ size = Vector3.new(2 * W + 4, 40, 2), pos = Vector3.new(0, 20, 371) },
	}
do
	part({ Name = "Limite", Size = w.size, Position = w.pos, Transparency = 1 }).Parent = map
end

local gatesFolder = Instance.new("Folder")
gatesFolder.Name = "Portails"
gatesFolder.Parent = map

local zoneDecor: { [string]: () -> Vector3 } = {}
for index, zone in Config.Zones do
	local depth = zone.zMax - zone.zMin
	local floor = part({
		Name = "Zone_" .. zone.id,
		Size = Vector3.new(2 * W, 0.4, depth + 20),
		Position = Vector3.new(0, 0.2, (zone.zMin + zone.zMax) / 2),
		Color = zone.color,
		Material = if zone.id == "montagne" then Enum.Material.Snow else Enum.Material.Grass,
		CanQuery = false,
	})
	floor.Parent = map
	zoneDecor[zone.id] = function()
		return Vector3.new(rng:NextNumber(-W + 8, W - 8), 0.4, rng:NextNumber(zone.zMin + 5, zone.zMax - 5))
	end
	-- Décor : fleurs, sapins ou rochers
	for _ = 1, 26 do
		local p = zoneDecor[zone.id]()
		if zone.id == "prairie" then
			local flower = part({
				Name = "Fleur",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.4, 1.4, 1.4),
				Position = p + Vector3.new(0, 0.6, 0),
				Color = Color3.fromHSV(rng:NextNumber(), 0.5, 1),
				CanCollide = false,
				CanQuery = false,
			})
			flower.Parent = map
		elseif zone.id == "foret" then
			local trunk = part({ Name = "Tronc", Size = Vector3.new(2, 8, 2), Position = p + Vector3.new(0, 4, 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood })
			trunk.Parent = map
			local leaves = part({
				Name = "Feuillage",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(10, 10, 10),
				Position = p + Vector3.new(0, 11, 0),
				Color = Color3.fromRGB(50, 120 + rng:NextInteger(0, 40), 60),
				Material = Enum.Material.Grass,
				CanCollide = false,
			})
			leaves.Parent = map
		else
			local rock = part({
				Name = "Rocher",
				Size = Vector3.new(rng:NextNumber(4, 9), rng:NextNumber(3, 7), rng:NextNumber(4, 9)),
				Position = p + Vector3.new(0, 1.5, 0),
				Color = Color3.fromRGB(150, 155, 170),
				Material = Enum.Material.Slate,
				Orientation = Vector3.new(0, rng:NextNumber(0, 360), 0),
			})
			rock.Parent = map
		end
	end
	-- Portail (sauf la prairie, ouverte à tous)
	if zone.price > 0 then
		local gate = part({
			Name = zone.id,
			Size = Vector3.new(2 * W, 24, 2),
			Position = Vector3.new(0, 12, zone.zMin - 10),
			Color = Color3.fromRGB(255, 190, 220),
			Material = Enum.Material.ForceField,
			Transparency = 0.3,
		})
		gate.Parent = gatesFolder
		local sign = part({
			Name = "Panneau_" .. zone.id,
			Size = Vector3.new(14, 5, 1),
			Position = Vector3.new(0, 4, zone.zMin - 13),
			Color = Color3.fromRGB(255, 250, 240),
			Material = Enum.Material.SmoothPlastic,
		})
		surfaceText(sign, Enum.NormalId.Front, "🔒 " .. zone.name .. "\n" .. zone.price .. " ❤", Color3.fromRGB(150, 60, 110))
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Ouvrir (" .. zone.price .. " ❤)"
		prompt.ObjectText = zone.name
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = sign
		sign.Parent = map
		prompt.Triggered:Connect(function(player)
			local data = sessionData[player]
			if not data then
				return
			end
			if table.find(data.zones, zone.id) then
				Notify:FireClient(player, zone.name .. " est déjà ouverte pour toi 🙂")
				return
			end
			-- il faut avoir ouvert la zone précédente
			local previous = Config.Zones[index - 1]
			if previous and not table.find(data.zones, previous.id) then
				Notify:FireClient(player, "Ouvre d'abord : " .. previous.name)
				return
			end
			if data.hearts < zone.price then
				Notify:FireClient(player, "Il te manque " .. (zone.price - data.hearts) .. " ❤")
				return
			end
			data.hearts -= zone.price
			table.insert(data.zones, zone.id)
			syncPlayer(player)
			Notify:FireClient(player, zone.name .. " ouverte ! De nouvelles bestioles t'attendent 🌲")
		end)
	end
end

-- Lumière douce
Lighting.ClockTime = 16
do
	local atmo = Instance.new("Atmosphere")
	atmo.Density = 0.2
	atmo.Haze = 0.8
	atmo.Color = Color3.fromRGB(255, 235, 220)
	atmo.Parent = Lighting
end

map.Parent = workspace

---------------------------------------------------------------------
-- Bestioles sauvages
---------------------------------------------------------------------
local wildFolder = Instance.new("Folder")
wildFolder.Name = "BestiolesSauvages"
wildFolder.Parent = workspace

local function pickSpecies(zoneId: string): Config.Species
	local pool = {}
	local total = 0
	for _, s in Config.Species do
		if s.zone == zoneId then
			table.insert(pool, s)
			total += s.weight
		end
	end
	local roll = rng:NextNumber(0, total)
	for _, s in pool do
		roll -= s.weight
		if roll <= 0 then
			return s
		end
	end
	return pool[1]
end

local spawnWild: (zone: Config.Zone) -> ()

local function catchCritter(player: Player, zone: Config.Zone, species: Config.Species, model: Model): boolean
	local data = sessionData[player]
	if not data or model.Parent == nil then
		return false
	end
	if not table.find(data.zones, zone.id) then
		Notify:FireClient(player, "Ouvre d'abord la zone : " .. zone.name)
		return false
	end
	local bag = carried[player]
	if #bag >= capacity(player, data) then
		Notify:FireClient(player, "Panier plein ! Ramène tes bestioles au refuge 🧺")
		return false
	end
	table.insert(bag, species.id)
	model:Destroy()
	syncPlayer(player)
	Notify:FireClient(player, species.name .. " (" .. species.rarity .. ") dans ton panier ! " .. #bag .. "/" .. capacity(player, data))
	task.delay(3, spawnWild, zone)
	return true
end

spawnWild = function(zone: Config.Zone)
	local species = pickSpecies(zone.id)
	local start = zoneDecor[zone.id]() + Vector3.new(0, species.size / 2 + 0.2, 0)
	local model, body = makeCritter(species, CFrame.new(start))
	CollectionService:AddTag(model, "Sauvage")
	billboard(body, species.name, Config.RarityColors[species.rarity], species.size + 1.5, 140)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Recueillir"
	prompt.ObjectText = species.name .. " · " .. species.rarity
	prompt.HoldDuration = Config.RarityHold[species.rarity] or 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	model.Parent = wildFolder
	prompt.Triggered:Connect(function(player)
		catchCritter(player, zone, species, model)
	end)
	-- Balade : la bestiole se promène doucement dans sa zone
	task.spawn(function()
		while model.Parent do
			task.wait(rng:NextNumber(1.5, 4))
			if not model.Parent then
				break
			end
			local here = body.Position
			local target = Vector3.new(
				math.clamp(here.X + rng:NextNumber(-18, 18), -W + 6, W - 6),
				here.Y,
				math.clamp(here.Z + rng:NextNumber(-18, 18), zone.zMin + 3, zone.zMax - 3)
			)
			local distance = (target - here).Magnitude
			if distance > 1 then
				local tween = TweenService:Create(body, TweenInfo.new(distance / 7, Enum.EasingStyle.Sine), {
					CFrame = CFrame.lookAt(target, target + (target - here).Unit),
				})
				body.CFrame = CFrame.lookAt(here, here + (target - here).Unit)
				tween:Play()
				tween.Completed:Wait()
			end
		end
	end)
end

for _, zone in Config.Zones do
	for _ = 1, zone.wildCount do
		spawnWild(zone)
	end
end

---------------------------------------------------------------------
-- Refuges (un par joueur)
---------------------------------------------------------------------
type Slot = { part: BasePart, prompt: ProximityPrompt, index: number, model: Model? }
type Plot = {
	index: number,
	owner: Player?,
	spawnCFrame: CFrame,
	sign: TextLabel,
	boxLabel: TextLabel,
	slots: { Slot },
}

local plots: { Plot } = {}
local playerPlot: { [Player]: Plot } = {}
local refugeFolder = Instance.new("Folder")
refugeFolder.Name = "Refuges"

local PLOT = 44
local SLOT = 8
local SLOT_GAP = 2

local function refreshSlot(plot: Plot, slot: Slot)
	local owner = plot.owner
	local data = owner and sessionData[owner]
	if slot.model then
		slot.model:Destroy()
		slot.model = nil
	end
	local prompt = slot.prompt
	if not owner or not data then
		prompt.Enabled = false
		slot.part.Transparency = 0.6
		return
	end
	if slot.index > data.slots then
		slot.part.Transparency = 0.6
		prompt.Enabled = slot.index == data.slots + 1
		prompt.HoldDuration = 0
		prompt.ActionText = "Agrandir (" .. Config.SlotPrice(data.slots) .. " ❤)"
		prompt.ObjectText = "Nouvel enclos"
		return
	end
	slot.part.Transparency = 0
	local id = data.pens[slot.index]
	local species = id and Config.GetSpecies(id)
	if not species then
		prompt.Enabled = false
		return
	end
	local cf = CFrame.new(slot.part.Position + Vector3.new(0, 0.3 + species.size / 2, 0)) * CFrame.Angles(0, math.pi, 0)
	local model, body = makeCritter(species, cf)
	body:SetAttribute("BaseCFrame", cf)
	billboard(body, "+" .. species.hps .. " ❤/s", Color3.fromRGB(255, 120, 160), species.size + 1.2, 110)
	CollectionService:AddTag(body, "Pensionnaire")
	model.Parent = slot.part
	slot.model = model
	prompt.Enabled = true
	prompt.HoldDuration = 1.2
	prompt.ActionText = "Confier à une famille (+" .. species.hps * Config.AdoptBonusSeconds .. " ❤)"
	prompt.ObjectText = species.name
end

local function refreshPlot(plot: Plot)
	for _, slot in plot.slots do
		refreshSlot(plot, slot)
	end
end

local function onSlotTriggered(plot: Plot, slot: Slot, player: Player)
	local data = sessionData[player]
	if plot.owner ~= player or not data then
		Notify:FireClient(player, "Ce n'est pas ton refuge 🙂")
		return
	end
	if slot.index > data.slots then
		if slot.index ~= data.slots + 1 then
			return
		end
		local price = Config.SlotPrice(data.slots)
		if data.hearts < price then
			Notify:FireClient(player, "Il te manque " .. (price - data.hearts) .. " ❤")
			return
		end
		data.hearts -= price
		data.slots += 1
		syncPlayer(player)
		refreshPlot(plot)
		Notify:FireClient(player, "Nouvel enclos ! 🏡")
		return
	end
	local id = data.pens[slot.index]
	local species = id and Config.GetSpecies(id)
	if not species then
		return
	end
	-- Adoption : la bestiole part dans une famille, l'enclos est libéré
	table.remove(data.pens, slot.index)
	local bonus = species.hps * Config.AdoptBonusSeconds
	data.hearts += bonus
	data.adopted += 1
	syncPlayer(player)
	refreshPlot(plot)
	Notify:FireClient(player, species.name .. " a trouvé une famille ! +" .. bonus .. " ❤ 💌")
end

local function deposit(plot: Plot, player: Player)
	local data = sessionData[player]
	if plot.owner ~= player or not data then
		Notify:FireClient(player, "Ce n'est pas ton refuge 🙂")
		return
	end
	local bag = carried[player]
	if #bag == 0 then
		Notify:FireClient(player, "Ton panier est vide : va recueillir des bestioles dans la prairie 🌼")
		return
	end
	local placed = 0
	while #bag > 0 and #data.pens < data.slots do
		local id = table.remove(bag, 1) :: string
		table.insert(data.pens, id)
		placed += 1
		if not table.find(data.discovered, id) then
			table.insert(data.discovered, id)
			local s = Config.GetSpecies(id)
			if s then
				local bonus = s.hps * Config.DiscoveryBonusSeconds
				data.hearts += bonus
				Discovered:FireClient(player, id)
				Notify:FireClient(player, "Nouvelle espèce : " .. s.name .. " ! +" .. bonus .. " ❤ 📖")
			end
		end
	end
	syncPlayer(player)
	refreshPlot(plot)
	if #bag > 0 then
		Notify:FireClient(player, placed .. " installée(s). Refuge plein : agrandis-le ou confie une bestiole à une famille")
	elseif placed > 0 then
		Notify:FireClient(player, placed .. " bestiole(s) installée(s) ! Elles produisent des ❤")
	end
end

local function collect(plot: Plot, player: Player)
	local data = sessionData[player]
	if plot.owner ~= player or not data then
		Notify:FireClient(player, "Ce n'est pas ton refuge 🙂")
		return
	end
	local amount = math.floor(boxHearts[player] or 0)
	if amount <= 0 then
		Notify:FireClient(player, "La boîte est vide : installe des bestioles !")
		return
	end
	boxHearts[player] = (boxHearts[player] or 0) - amount
	data.hearts += amount
	syncPlayer(player)
	Notify:FireClient(player, "+" .. amount .. " ❤")
end

local function newPrompt(parent: Instance, action: string, object: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function buildPlot(index: number, origin: Vector3): Plot
	local folder = Instance.new("Model")
	folder.Name = "Refuge" .. index

	local base = part({
		Name = "Base",
		Size = Vector3.new(PLOT, 1, PLOT),
		Position = origin,
		Color = Color3.fromRGB(205, 235, 175),
		Material = Enum.Material.Grass,
	})
	base.Parent = folder

	-- Haie basse sur 3 côtés (l'avant est ouvert vers la place centrale)
	local sides: { { offset: Vector3, alongX: boolean } } = {
		{ offset = Vector3.new(0, 0, -1), alongX = true },
		{ offset = Vector3.new(1, 0, 0), alongX = false },
		{ offset = Vector3.new(-1, 0, 0), alongX = false },
	}
	for _, side in sides do
		local offset = side.offset
		local alongX = side.alongX
		local hedge = part({
			Name = "Haie",
			Size = if alongX then Vector3.new(PLOT, 3, 1.5) else Vector3.new(1.5, 3, PLOT),
			Position = origin + offset * (PLOT / 2) + Vector3.new(0, 2, 0),
			Color = Color3.fromRGB(80, 160, 80),
			Material = Enum.Material.Grass,
		})
		hedge.Parent = folder
	end

	-- Panneau du propriétaire, au fond
	local signPart = part({
		Name = "Panneau",
		Size = Vector3.new(16, 5, 0.6),
		Position = origin + Vector3.new(0, 6, -PLOT / 2 + 1),
		Color = Color3.fromRGB(255, 235, 245),
		Material = Enum.Material.SmoothPlastic,
	})
	signPart.Parent = folder
	local sign = surfaceText(signPart, Enum.NormalId.Back, "Refuge libre", Color3.fromRGB(170, 70, 120))

	-- Accueil (on dépose le panier) et boîte à cœurs, à l'avant
	local accueil = part({
		Name = "Accueil",
		Size = Vector3.new(8, 1, 6),
		Position = origin + Vector3.new(-8, 0.9, PLOT / 2 - 5),
		Color = Color3.fromRGB(255, 200, 120),
		Material = Enum.Material.Wood,
	})
	accueil.Parent = folder
	billboard(accueil, "🧺 Accueil", Color3.fromRGB(255, 255, 255), 3, 140)
	local box = part({
		Name = "BoiteACoeurs",
		Size = Vector3.new(4, 4, 4),
		Position = origin + Vector3.new(8, 2.5, PLOT / 2 - 5),
		Color = Color3.fromRGB(255, 120, 170),
		Material = Enum.Material.SmoothPlastic,
	})
	box.Parent = folder
	local boxLabel = billboard(box, "❤ 0", Color3.fromRGB(255, 255, 255), 4, 140)

	local plot: Plot = {
		index = index,
		owner = nil,
		spawnCFrame = CFrame.lookAt(origin + Vector3.new(0, 4, PLOT / 2 - 12), origin + Vector3.new(0, 4, PLOT)),
		sign = sign,
		boxLabel = boxLabel,
		slots = {},
	}

	newPrompt(accueil, "Installer les bestioles", "Accueil").Triggered:Connect(function(player)
		deposit(plot, player)
	end)
	newPrompt(box, "Collecter", "Boîte à cœurs").Triggered:Connect(function(player)
		collect(plot, player)
	end)

	-- 12 enclos : 4 colonnes x 3 rangées
	local cols = 4
	local span = cols * SLOT + (cols - 1) * SLOT_GAP
	for i = 1, Config.MaxSlots do
		local col = (i - 1) % cols
		local row = (i - 1) // cols
		local slotPart = part({
			Name = "Enclos" .. i,
			Size = Vector3.new(SLOT, 0.4, SLOT),
			Position = origin + Vector3.new(-span / 2 + SLOT / 2 + col * (SLOT + SLOT_GAP), 0.7, 6 - row * (SLOT + SLOT_GAP)),
			Color = Color3.fromRGB(240, 220, 170),
			Material = Enum.Material.Sand,
		})
		local prompt = newPrompt(slotPart, "", "")
		prompt.MaxActivationDistance = 8
		slotPart.Parent = folder
		local slot: Slot = { part = slotPart, prompt = prompt, index = i, model = nil }
		table.insert(plot.slots, slot)
		prompt.Triggered:Connect(function(player)
			onSlotTriggered(plot, slot, player)
		end)
	end

	folder.Parent = refugeFolder
	return plot
end

for i = 1, Config.PlotCount do
	local x = (i - (Config.PlotCount + 1) / 2) * (PLOT + 14)
	table.insert(plots, buildPlot(i, Vector3.new(x, 0.5, -60)))
end
refugeFolder.Parent = workspace

---------------------------------------------------------------------
-- Arrivée / départ des joueurs
---------------------------------------------------------------------
local function assignPlot(player: Player): Plot?
	for _, plot in plots do
		if not plot.owner then
			plot.owner = player
			plot.sign.Text = "Refuge de " .. player.DisplayName
			playerPlot[player] = plot
			player:SetAttribute("PlotIndex", plot.index)
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
	plot.owner = nil
	plot.sign.Text = "Refuge libre"
	plot.boxLabel.Text = "❤ 0"
	playerPlot[player] = nil
	refreshPlot(plot)
end

local function onCharacterAdded(player: Player, character: Model)
	local plot = playerPlot[player]
	if plot then
		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait(0.1)
			if character.Parent then
				character:PivotTo(plot.spawnCFrame)
			end
		end)
	end
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local h = Instance.new("IntValue")
	h.Name = "Cœurs"
	h.Parent = leaderstats
	local b = Instance.new("IntValue")
	b.Name = "Bestioles"
	b.Parent = leaderstats
	leaderstats.Parent = player

	local data = loadData(player)
	if player.Parent == nil then
		return
	end
	sessionData[player] = data
	carried[player] = table.clone(data.basket) -- le panier est retrouvé à la reconnexion
	boxHearts[player] = 0
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
	carried[player] = nil
	boxHearts[player] = nil
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
-- Production de cœurs (chaque seconde, dans la boîte du refuge)
---------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		for player, data in sessionData do
			local hps = heartsPerSecond(player, data)
			if hps > 0 then
				local cap = hps * Config.BoxCapSeconds
				boxHearts[player] = math.min((boxHearts[player] or 0) + hps, cap)
				local amount = math.floor(boxHearts[player])
				player:SetAttribute("Box", amount)
				local plot = playerPlot[player]
				if plot then
					plot.boxLabel.Text = "❤ " .. amount .. (if amount >= cap then " (pleine)" else "")
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Remotes client → serveur (tout est vérifié ici)
---------------------------------------------------------------------
UpgradeNet.OnServerEvent:Connect(function(player: Player)
	local data = sessionData[player]
	local now = os.clock()
	if not data or now - (lastRequest[player] or 0) < 0.3 then
		return
	end
	lastRequest[player] = now
	if data.net >= Config.NetMaxLevel then
		Notify:FireClient(player, "Panier au niveau maximum ! 🧺")
		return
	end
	local price = Config.NetPrice(data.net)
	if data.hearts < price then
		Notify:FireClient(player, "Il te manque " .. (price - data.hearts) .. " ❤")
		return
	end
	data.hearts -= price
	data.net += 1
	syncPlayer(player)
	Notify:FireClient(player, "Panier agrandi : " .. capacity(player, data) .. " places 🧺")
end)
