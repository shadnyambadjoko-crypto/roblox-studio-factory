--!strict
-- Interface du « Refuge des Bestioles » : cœurs, panier, guide des premières minutes,
-- fil lumineux vers l'accueil, bestiaire, portails ouverts, boutique, notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpgradeNet = remotes:WaitForChild("UpgradeNet") :: RemoteEvent
local Notify = remotes:WaitForChild("Notify") :: RemoteEvent
local Discovered = remotes:WaitForChild("Discovered") :: RemoteEvent

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local PINK = Color3.fromRGB(255, 120, 170)
local CREAM = Color3.fromRGB(255, 250, 240)
local INK = Color3.fromRGB(90, 45, 70)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance)
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end

local function attr(name: string): number
	return (player:GetAttribute(name) :: number?) or 0
end

local function csv(name: string): { [string]: boolean }
	local set = {}
	local raw = (player:GetAttribute(name) :: string?) or ""
	for id in raw:gmatch("[^,]+") do
		set[id] = true
	end
	return set
end

local function textLabel(parent: Instance, size: UDim2, pos: UDim2, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = size
	t.Position = pos
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = color
	t.Parent = parent
	return t
end

local function button(parent: Instance, text: string, color: Color3, size: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.Font = FONT
	b.TextScaled = true
	b.TextColor3 = INK
	b.Text = text
	corner(b, 12)
	stroke(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = b
	b.Parent = parent
	return b
end

local screen = Instance.new("ScreenGui")
screen.Name = "RefugeUI"
screen.ResetOnSpawn = false

---------------------------------------------------------------------
-- Haut : cœurs et production
---------------------------------------------------------------------
local top = Instance.new("Frame")
top.Size = UDim2.fromOffset(330, 58)
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 10)
top.BackgroundColor3 = CREAM
corner(top, 14)
stroke(top)
top.Parent = screen
local heartsLabel = textLabel(top, UDim2.new(0.55, -8, 1, -14), UDim2.fromOffset(8, 7), PINK)
local hpsLabel = textLabel(top, UDim2.new(0.45, -8, 1, -18), UDim2.new(0.55, 0, 0, 9), INK)

-- Guide des premières minutes
local guide = textLabel(screen, UDim2.fromOffset(420, 36), UDim2.new(0.5, 0, 0, 74), Color3.new(1, 1, 1))
guide.AnchorPoint = Vector2.new(0.5, 0)
guide.BackgroundColor3 = INK
guide.BackgroundTransparency = 0.2
corner(guide, 10)

---------------------------------------------------------------------
-- Bas : panier, amélioration, bestiaire
---------------------------------------------------------------------
local bar = Instance.new("Frame")
bar.Size = UDim2.new(0, 0, 0, 56)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -14)
bar.BackgroundTransparency = 1
bar.Parent = screen
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 8)
layout.Parent = bar

local basket = button(bar, "", CREAM, UDim2.fromOffset(140, 56))
basket.AutoButtonColor = false
local netButton = button(bar, "", CREAM, UDim2.fromOffset(210, 56))
local bookButton = button(bar, "📖 Bestiaire", CREAM, UDim2.fromOffset(150, 56))

netButton.Activated:Connect(function()
	UpgradeNet:FireServer()
end)

-- Bestiaire
local book = Instance.new("Frame")
book.Size = UDim2.fromOffset(460, 300)
book.AnchorPoint = Vector2.new(0.5, 0.5)
book.Position = UDim2.fromScale(0.5, 0.5)
book.BackgroundColor3 = CREAM
book.Visible = false
corner(book, 16)
stroke(book)
book.Parent = screen
local bookTitle = textLabel(book, UDim2.new(1, -20, 0, 36), UDim2.fromOffset(10, 8), INK)
local grid = Instance.new("Frame")
grid.Size = UDim2.new(1, -20, 1, -56)
grid.Position = UDim2.fromOffset(10, 48)
grid.BackgroundTransparency = 1
grid.Parent = book
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(140, 74)
gridLayout.CellPadding = UDim2.fromOffset(8, 8)
gridLayout.Parent = grid

type Card = { frame: Frame, dot: Frame, name: TextLabel, info: TextLabel }
local cards: { [string]: Card } = {}
for _, s in Config.Species do
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	corner(f, 10)
	f.Parent = grid
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(30, 30)
	dot.Position = UDim2.fromOffset(8, 8)
	corner(dot, 15)
	dot.Parent = f
	local name = textLabel(f, UDim2.new(1, -50, 0, 30), UDim2.fromOffset(44, 8), INK)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local info = textLabel(f, UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 44), INK)
	info.Font = Enum.Font.GothamBold
	cards[s.id] = { frame = f, dot = dot, name = name, info = info }
end

bookButton.Activated:Connect(function()
	book.Visible = not book.Visible
end)

---------------------------------------------------------------------
-- Rafraîchissement
---------------------------------------------------------------------
local function refreshBook()
	local found = csv("Discovered")
	local count = 0
	for _, s in Config.Species do
		local c = cards[s.id]
		local zone = Config.GetZone(s.zone)
		if found[s.id] then
			count += 1
			c.dot.BackgroundColor3 = s.color
			c.name.Text = s.name
			c.info.Text = s.rarity .. " · +" .. s.hps .. " ❤/s"
			c.info.TextColor3 = Config.RarityColors[s.rarity]:Lerp(INK, 0.35)
		else
			c.dot.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
			c.name.Text = "???"
			c.info.Text = s.rarity .. " · " .. (if zone then zone.name else "")
			c.info.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end
	bookTitle.Text = "📖 Bestiaire : " .. count .. " / " .. #Config.Species
end

local function refresh()
	local hearts = attr("Hearts")
	local net = attr("Net")
	heartsLabel.Text = "❤ " .. formatNumber(hearts)
	hpsLabel.Text = "+" .. formatNumber(attr("HPS")) .. " ❤/s"
	basket.Text = "🧺 " .. attr("Carried") .. " / " .. attr("Capacity")
	basket.BackgroundColor3 = if attr("Carried") >= attr("Capacity") then Color3.fromRGB(255, 200, 200) else CREAM
	if net >= Config.NetMaxLevel then
		netButton.Text = "🧺 Panier MAX"
		netButton.BackgroundColor3 = CREAM
	else
		local price = Config.NetPrice(net)
		netButton.Text = "🧺 +1 place : " .. formatNumber(price) .. " ❤"
		netButton.BackgroundColor3 = if hearts >= price then Color3.fromRGB(200, 245, 180) else CREAM
	end

	-- Guide
	local carriedCount = attr("Carried")
	local pens = attr("PenCount")
	local zones = csv("Zones")
	if pens == 0 and carriedCount == 0 then
		guide.Text = "1. Va dans la prairie 🌼 et recueille une bestiole (touche E)"
	elseif carriedCount > 0 then
		guide.Text = "2. Suis le fil rose jusqu'à l'Accueil de ton refuge 🧺"
	elseif hearts < 50 and attr("Box") > 0 then
		guide.Text = "3. Collecte les cœurs dans la boîte rose ❤"
	elseif not zones["foret"] then
		guide.Text = "Agrandis ton refuge, puis ouvre la Forêt 🌲 (2 500 ❤)"
	elseif not zones["montagne"] then
		guide.Text = "Prochain objectif : la Montagne 🏔️ (50 000 ❤)"
	else
		guide.Text = "Complète ton bestiaire 📖 et trouve le Dragonnet-nuage !"
	end
end

for _, name in { "Hearts", "HPS", "Net", "Capacity", "Carried", "PenCount", "Zones", "Box" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
player:GetAttributeChangedSignal("Discovered"):Connect(refreshBook)
refresh()
refreshBook()

---------------------------------------------------------------------
-- Portails : un portail ouvert devient traversable pour ce joueur seulement
---------------------------------------------------------------------
local function refreshGates()
	local zones = csv("Zones")
	local folder = workspace:FindFirstChild("Monde")
	local gates = folder and folder:FindFirstChild("Portails")
	if not gates then
		return
	end
	for _, gate in gates:GetChildren() do
		if gate:IsA("BasePart") then
			local open = zones[gate.Name] == true
			gate.CanCollide = not open
			gate.Transparency = if open then 0.85 else 0.3
		end
	end
end
player:GetAttributeChangedSignal("Zones"):Connect(refreshGates)
task.spawn(function()
	local monde = workspace:WaitForChild("Monde", 20)
	if monde then
		monde:WaitForChild("Portails", 20)
		refreshGates()
	end
end)

---------------------------------------------------------------------
-- Fil lumineux vers l'accueil quand le panier n'est pas vide
---------------------------------------------------------------------
local beam = Instance.new("Beam")
beam.Color = ColorSequence.new(PINK)
beam.Width0 = 0.6
beam.Width1 = 0.6
beam.FaceCamera = true
beam.LightEmission = 0.6
beam.TextureSpeed = 1
beam.Enabled = false

local function updateBeam()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local refuges = workspace:FindFirstChild("Refuges")
	local plot = refuges and refuges:FindFirstChild("Refuge" .. attr("PlotIndex"))
	local accueil = plot and plot:FindFirstChild("Accueil")
	if not root or not accueil or attr("Carried") == 0 then
		beam.Enabled = false
		return
	end
	local a0 = root:FindFirstChild("FilA0") :: Attachment?
	if not a0 then
		local new = Instance.new("Attachment")
		new.Name = "FilA0"
		new.Parent = root
		a0 = new
	end
	local a1 = accueil:FindFirstChild("FilA1") :: Attachment?
	if not a1 then
		local new = Instance.new("Attachment")
		new.Name = "FilA1"
		new.Position = Vector3.new(0, 2, 0)
		new.Parent = accueil
		a1 = new
	end
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Parent = accueil
	beam.Enabled = true
end
player:GetAttributeChangedSignal("Carried"):Connect(updateBeam)
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	updateBeam()
end)

---------------------------------------------------------------------
-- Les pensionnaires sautillent dans leur enclos (effet local)
---------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, body in CollectionService:GetTagged("Pensionnaire") do
		if body:IsA("BasePart") then
			local base = body:GetAttribute("BaseCFrame")
			if typeof(base) == "CFrame" then
				local phase = (body.Position.X + body.Position.Z) * 0.37
				local hop = math.abs(math.sin(t * 3 + phase)) * 0.8
				body.CFrame = base * CFrame.new(0, hop, 0) * CFrame.Angles(0, math.sin(t + phase) * 0.6, 0)
			end
		end
	end
end)

---------------------------------------------------------------------
-- Boutique (seulement si des ID sont configurés)
---------------------------------------------------------------------
type ShopItem = { label: string, buy: () -> () }
local shopItems: { ShopItem } = {}
if Config.GamePasses.DoubleHearts ~= 0 then
	table.insert(shopItems, {
		label = "💞 Cœurs x2",
		buy = function()
			MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.DoubleHearts)
		end,
	})
end
if Config.GamePasses.BigBasket ~= 0 then
	table.insert(shopItems, {
		label = "🧺 Grand panier",
		buy = function()
			MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.BigBasket)
		end,
	})
end
for productId, text in Config.DevProductLabels do
	table.insert(shopItems, {
		label = text,
		buy = function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end,
	})
end

if #shopItems > 0 then
	local shopButton = button(screen, "🛒 Boutique", Color3.fromRGB(255, 210, 90), UDim2.fromOffset(130, 48))
	shopButton.Position = UDim2.new(1, -142, 0, 12)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(220, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.new(1, -232, 0, 68)
	panel.BackgroundColor3 = CREAM
	panel.Visible = false
	corner(panel, 12)
	stroke(panel)
	panel.Parent = screen
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.Parent = panel
	local panelPad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(panelPad :: any)[side] = UDim.new(0, 8)
	end
	panelPad.Parent = panel
	for _, item in shopItems do
		local b = button(panel, item.label, PINK, UDim2.new(1, 0, 0, 44))
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Activated:Connect(item.buy)
	end
	shopButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

---------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------
local toast = textLabel(screen, UDim2.fromOffset(460, 44), UDim2.new(0.5, 0, 0, 116), Color3.new(1, 1, 1))
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.BackgroundColor3 = PINK
toast.BackgroundTransparency = 0.1
toast.Visible = false
corner(toast, 10)

local toastToken = 0
Notify.OnClientEvent:Connect(function(text: string)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(2.6, function()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end)

Discovered.OnClientEvent:Connect(function(id: string)
	local s = Config.GetSpecies(id)
	if not s then
		return
	end
	local big = textLabel(screen, UDim2.fromOffset(240, 40), UDim2.fromScale(0.5, 0.35), Config.RarityColors[s.rarity])
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.TextStrokeTransparency = 0
	big.TextStrokeColor3 = INK
	big.Text = "📖 " .. s.name .. " !"
	TweenService:Create(big, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(520, 86) }):Play()
	task.delay(1.4, function()
		local fade = TweenService:Create(big, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Connect(function()
			big:Destroy()
		end)
	end)
end)

screen.Parent = player:WaitForChild("PlayerGui")
