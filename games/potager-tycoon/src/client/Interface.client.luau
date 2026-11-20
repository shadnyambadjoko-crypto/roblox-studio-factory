--!strict
-- Interface du joueur : pièces, choix des graines, boutique, notifications.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SelectSeed = remotes:WaitForChild("SelectSeed") :: RemoteEvent
local UnlockSeed = remotes:WaitForChild("UnlockSeed") :: RemoteEvent
local Notify = remotes:WaitForChild("Notify") :: RemoteEvent

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local GREEN = Color3.fromRGB(80, 170, 70)
local CREAM = Color3.fromRGB(255, 248, 230)
local DARK = Color3.fromRGB(60, 45, 30)

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance)
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = DARK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end

local screen = Instance.new("ScreenGui")
screen.Name = "PotagerUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false

---------------------------------------------------------------------
-- Compteur de pièces
---------------------------------------------------------------------
local coinBox = Instance.new("Frame")
coinBox.Size = UDim2.fromOffset(210, 54)
coinBox.Position = UDim2.new(0.5, -105, 0, 10)
coinBox.BackgroundColor3 = CREAM
corner(coinBox, 14)
stroke(coinBox)
coinBox.Parent = screen

local coinLabel = Instance.new("TextLabel")
coinLabel.Size = UDim2.fromScale(1, 1)
coinLabel.BackgroundTransparency = 1
coinLabel.Font = FONT
coinLabel.TextScaled = true
coinLabel.TextColor3 = DARK
coinLabel.Text = "💰 0"
coinLabel.Parent = coinBox
local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = coinLabel

local shownCoins = 0
local function refreshCoins()
	local coins = (player:GetAttribute("Coins") :: number?) or 0
	if coins > shownCoins then
		coinBox.Size = UDim2.fromOffset(230, 60)
		TweenService:Create(coinBox, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(210, 54) }):Play()
	end
	shownCoins = coins
	coinLabel.Text = "💰 " .. formatNumber(coins)
end

---------------------------------------------------------------------
-- Barre des graines
---------------------------------------------------------------------
local seedBar = Instance.new("Frame")
seedBar.Size = UDim2.new(0, 0, 0, 96)
seedBar.AutomaticSize = Enum.AutomaticSize.X
seedBar.AnchorPoint = Vector2.new(0.5, 1)
seedBar.Position = UDim2.new(0.5, 0, 1, -12)
seedBar.BackgroundTransparency = 1
seedBar.Parent = screen
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 8)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = seedBar

type SeedButton = { button: TextButton, title: TextLabel, info: TextLabel }
local seedButtons: { [string]: SeedButton } = {}

local function unlockedSet(): { [string]: boolean }
	local set = {}
	local raw = (player:GetAttribute("UnlockedSeeds") :: string?) or ""
	for id in raw:gmatch("[^,]+") do
		set[id] = true
	end
	return set
end

for _, seed in Config.Seeds do
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(104, 92)
	button.Text = ""
	button.AutoButtonColor = true
	button.BackgroundColor3 = CREAM
	corner(button, 12)
	stroke(button)

	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(26, 26)
	dot.Position = UDim2.new(0.5, -13, 0, 6)
	dot.BackgroundColor3 = seed.color
	corner(dot, 13)
	dot.Parent = button

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -8, 0, 22)
	title.Position = UDim2.fromOffset(4, 34)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextScaled = true
	title.TextColor3 = DARK
	title.Text = seed.name
	title.Parent = button

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -8, 0, 28)
	info.Position = UDim2.fromOffset(4, 58)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamBold
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(110, 90, 70)
	info.Parent = button

	button.Activated:Connect(function()
		if unlockedSet()[seed.id] then
			SelectSeed:FireServer(seed.id)
		else
			UnlockSeed:FireServer(seed.id)
		end
	end)

	button.Parent = seedBar
	seedButtons[seed.id] = { button = button, title = title, info = info }
end

local function refreshSeeds()
	local unlocked = unlockedSet()
	local selected = player:GetAttribute("SelectedSeed")
	for _, seed in Config.Seeds do
		local sb = seedButtons[seed.id]
		local uiStroke = sb.button:FindFirstChildOfClass("UIStroke")
		if unlocked[seed.id] then
			sb.info.Text = seed.cost .. "→" .. seed.reward .. " 💰"
			sb.button.BackgroundColor3 = if selected == seed.id then Color3.fromRGB(200, 240, 180) else CREAM
			if uiStroke then
				uiStroke.Color = if selected == seed.id then GREEN else DARK
			end
		else
			sb.info.Text = "🔒 " .. formatNumber(seed.unlockPrice)
			sb.button.BackgroundColor3 = Color3.fromRGB(215, 205, 190)
			if uiStroke then
				uiStroke.Color = DARK
			end
		end
	end
end

---------------------------------------------------------------------
-- Boutique (seulement si des ID sont configurés)
---------------------------------------------------------------------
type ShopItem = { label: string, buy: () -> () }
local shopItems: { ShopItem } = {}
if Config.GamePasses.DoubleCoins ~= 0 then
	table.insert(shopItems, {
		label = "💰 Pièces x2",
		buy = function()
			MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.DoubleCoins)
		end,
	})
end
if Config.GamePasses.FastGrow ~= 0 then
	table.insert(shopItems, {
		label = "🌱 Pousse x2",
		buy = function()
			MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.FastGrow)
		end,
	})
end
for productId, label in Config.DevProductLabels do
	table.insert(shopItems, {
		label = label,
		buy = function()
			MarketplaceService:PromptProductPurchase(player, productId)
		end,
	})
end

if #shopItems > 0 then
	local shopButton = Instance.new("TextButton")
	shopButton.Size = UDim2.fromOffset(120, 48)
	shopButton.Position = UDim2.new(1, -132, 0, 12)
	shopButton.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
	shopButton.Font = FONT
	shopButton.TextScaled = true
	shopButton.TextColor3 = DARK
	shopButton.Text = "🛒 Boutique"
	corner(shopButton, 12)
	stroke(shopButton)
	shopButton.Parent = screen

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
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 0, 44)
		b.BackgroundColor3 = GREEN
		b.Font = FONT
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = item.label
		corner(b, 10)
		b.Activated:Connect(item.buy)
		b.Parent = panel
	end

	shopButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

---------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------
local toast = Instance.new("TextLabel")
toast.Size = UDim2.fromOffset(360, 44)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 74)
toast.BackgroundColor3 = DARK
toast.BackgroundTransparency = 0.15
toast.TextColor3 = Color3.new(1, 1, 1)
toast.Font = FONT
toast.TextScaled = true
toast.Visible = false
corner(toast, 10)
toast.Parent = screen

local toastToken = 0
Notify.OnClientEvent:Connect(function(text: string)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(2.2, function()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end)

---------------------------------------------------------------------
-- Message de bienvenue + mises à jour
---------------------------------------------------------------------
player:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)
player:GetAttributeChangedSignal("UnlockedSeeds"):Connect(refreshSeeds)
player:GetAttributeChangedSignal("SelectedSeed"):Connect(refreshSeeds)
refreshCoins()
refreshSeeds()

screen.Parent = player:WaitForChild("PlayerGui")

task.delay(2, function()
	toast.Text = "Plante, récolte, agrandis ton potager ! 🥕"
	toast.Visible = true
	task.delay(4, function()
		if toastToken == 0 then
			toast.Visible = false
		end
	end)
end)
