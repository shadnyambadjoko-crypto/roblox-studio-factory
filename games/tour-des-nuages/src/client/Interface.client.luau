--!strict
-- Interface de « Tour des Nuages +1 » : saut, étoiles, objectif suivant, bottes, checkpoint,
-- renaissance, boutique, notifications et petits « +1 » qui s'envolent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local BuyBoots = remotes:WaitForChild("BuyBoots") :: RemoteEvent
local Rebirth = remotes:WaitForChild("Rebirth") :: RemoteEvent
local Teleport = remotes:WaitForChild("Teleport") :: RemoteEvent
local Notify = remotes:WaitForChild("Notify") :: RemoteEvent
local Celebrate = remotes:WaitForChild("Celebrate") :: RemoteEvent

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local SKY = Color3.fromRGB(110, 160, 255)
local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(40, 55, 110)
local GOLD = Color3.fromRGB(255, 205, 60)
local SUMMIT = Config.FloorCount + 1

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = 3
	s.Color = color or INK
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

local screen = Instance.new("ScreenGui")
screen.Name = "NuagesUI"
screen.ResetOnSpawn = false

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
	b.AutoButtonColor = true
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

---------------------------------------------------------------------
-- Haut de l'écran : saut + étoiles
---------------------------------------------------------------------
local top = Instance.new("Frame")
top.Size = UDim2.fromOffset(340, 58)
top.AnchorPoint = Vector2.new(0.5, 0)
top.Position = UDim2.new(0.5, 0, 0, 10)
top.BackgroundColor3 = WHITE
corner(top, 14)
stroke(top)
top.Parent = screen

local jumpLabel = textLabel(top, UDim2.new(0.55, -8, 1, -14), UDim2.fromOffset(8, 7), INK)
local starLabel = textLabel(top, UDim2.new(0.45, -8, 1, -14), UDim2.new(0.55, 0, 0, 7), Color3.fromRGB(200, 140, 0))

-- Objectif : prochain étage
local goal = Instance.new("Frame")
goal.Size = UDim2.fromOffset(340, 40)
goal.AnchorPoint = Vector2.new(0.5, 0)
goal.Position = UDim2.new(0.5, 0, 0, 74)
goal.BackgroundColor3 = INK
goal.BackgroundTransparency = 0.2
corner(goal, 10)
goal.Parent = screen
local goalFill = Instance.new("Frame")
goalFill.Size = UDim2.fromScale(0, 1)
goalFill.BackgroundColor3 = SKY
goalFill.BorderSizePixel = 0
corner(goalFill, 10)
goalFill.Parent = goal
local goalText = textLabel(goal, UDim2.new(1, -16, 1, -10), UDim2.fromOffset(8, 5), WHITE)
goalText.ZIndex = 2

---------------------------------------------------------------------
-- Bas de l'écran : actions
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

local bootsButton = button(bar, "", WHITE, UDim2.fromOffset(190, 56))
local checkpointButton = button(bar, "⬆️ Checkpoint", WHITE, UDim2.fromOffset(140, 56))
local groundButton = button(bar, "⬇️ Sol", WHITE, UDim2.fromOffset(90, 56))
local rebirthButton = button(bar, "🌈 Renaissance", GOLD, UDim2.fromOffset(170, 56))

bootsButton.Activated:Connect(function()
	BuyBoots:FireServer()
end)
checkpointButton.Activated:Connect(function()
	Teleport:FireServer("checkpoint")
end)
groundButton.Activated:Connect(function()
	Teleport:FireServer("sol")
end)
rebirthButton.Activated:Connect(function()
	Rebirth:FireServer()
end)

-- Statistiques à gauche
local stats = textLabel(screen, UDim2.fromOffset(200, 70), UDim2.new(0, 12, 0.5, -35), INK)
stats.TextXAlignment = Enum.TextXAlignment.Left
stats.TextStrokeColor3 = WHITE
stats.TextStrokeTransparency = 0.2

---------------------------------------------------------------------
-- Rafraîchissement
---------------------------------------------------------------------
local function refresh()
	local jump = attr("Jump")
	local stars = attr("Stars")
	local boots = attr("Boots")
	local runBest = attr("RunBest")
	jumpLabel.Text = "👟 Saut " .. formatNumber(jump)
	starLabel.Text = "⭐ " .. formatNumber(stars)

	if runBest >= SUMMIT then
		goalText.Text = "🏆 Sommet atteint ! Renaissance = x" .. Config.RebirthMultiplier(attr("Rebirths") + 1)
		goalFill.Size = UDim2.fromScale(1, 1)
	else
		local nextFloor = runBest + 1
		local needed = math.ceil(Config.JumpPowerFor(Config.FloorRise(nextFloor)))
		local name = if nextFloor == SUMMIT then "Sommet" else "Étage " .. nextFloor
		if jump >= needed then
			goalText.Text = name .. " : tu peux sauter ! ⬆️"
		else
			goalText.Text = name .. " : saut " .. needed .. " (cours encore !)"
		end
		goalFill.Size = UDim2.fromScale(math.clamp((jump - Config.BaseJumpPower) / math.max(needed - Config.BaseJumpPower, 1), 0, 1), 1)
	end

	if boots >= Config.BootsMaxLevel then
		bootsButton.Text = "👢 Bottes MAX"
	else
		bootsButton.Text = "👢 Bottes " .. (boots + 1) .. " : " .. formatNumber(Config.BootsPrice(boots)) .. " ⭐"
	end
	bootsButton.BackgroundColor3 = if boots < Config.BootsMaxLevel and stars >= Config.BootsPrice(boots) then Color3.fromRGB(190, 240, 170) else WHITE
	rebirthButton.Visible = runBest >= SUMMIT
	checkpointButton.Visible = runBest >= Config.CheckpointEvery

	stats.Text = string.format(
		"Record : étage %d\nMultiplicateur : x%.2f\nRenaissances : %d",
		math.min(attr("Record"), Config.FloorCount),
		attr("Multiplier"),
		attr("Rebirths")
	)
end

for _, name in { "Jump", "Stars", "Boots", "RunBest", "Record", "Rebirths", "Multiplier" } do
	player:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

---------------------------------------------------------------------
-- Petits « +N » qui s'envolent quand on gagne des points en courant
---------------------------------------------------------------------
local lastPoints = attr("Points")
local pending = 0
player:GetAttributeChangedSignal("Points"):Connect(function()
	local p = attr("Points")
	if p > lastPoints then
		pending += p - lastPoints
	end
	lastPoints = p
end)

task.spawn(function()
	local rng = Random.new()
	while true do
		task.wait(0.35)
		if pending > 0 then
			local amount = pending
			pending = 0
			local pop = textLabel(screen, UDim2.fromOffset(90, 34), UDim2.new(0.5, rng:NextInteger(-120, 80), 1, -110), Color3.fromRGB(90, 200, 90))
			pop.Text = "+" .. formatNumber(amount)
			pop.TextStrokeTransparency = 0.2
			pop.TextStrokeColor3 = WHITE
			local tween = TweenService:Create(pop, TweenInfo.new(0.9), {
				Position = pop.Position - UDim2.fromOffset(0, 70),
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			tween:Play()
			tween.Completed:Connect(function()
				pop:Destroy()
			end)
		end
	end
end)

---------------------------------------------------------------------
-- Boutique (seulement si des ID sont configurés)
---------------------------------------------------------------------
type ShopItem = { label: string, buy: () -> () }
local shopItems: { ShopItem } = {}
if Config.GamePasses.DoubleSteps ~= 0 then
	table.insert(shopItems, {
		label = "👟👟 Pas x2",
		buy = function()
			MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.DoubleSteps)
		end,
	})
end
if Config.GamePasses.FastRunner ~= 0 then
	table.insert(shopItems, {
		label = "⚡ Course rapide",
		buy = function()
			MarketplaceService:PromptGamePassPurchase(player, Config.GamePasses.FastRunner)
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
	local shopButton = button(screen, "🛒 Boutique", GOLD, UDim2.fromOffset(130, 48))
	shopButton.Position = UDim2.new(1, -142, 0, 12)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(220, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Position = UDim2.new(1, -232, 0, 68)
	panel.BackgroundColor3 = WHITE
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
		local b = button(panel, item.label, SKY, UDim2.new(1, 0, 0, 44))
		b.TextColor3 = WHITE
		b.Activated:Connect(item.buy)
	end
	shopButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

---------------------------------------------------------------------
-- Notifications et célébrations
---------------------------------------------------------------------
local toast = textLabel(screen, UDim2.fromOffset(420, 44), UDim2.new(0.5, 0, 0, 122), WHITE)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.BackgroundTransparency = 0.15
toast.BackgroundColor3 = INK
toast.Visible = false
corner(toast, 10)

local toastToken = 0
local function showToast(text: string, duration: number)
	toastToken += 1
	local token = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(duration, function()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end
Notify.OnClientEvent:Connect(function(text: string)
	showToast(text, 2.4)
end)

Celebrate.OnClientEvent:Connect(function(floor: number)
	local big = textLabel(screen, UDim2.fromOffset(500, 90), UDim2.fromScale(0.5, 0.35), GOLD)
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.TextStrokeTransparency = 0
	big.TextStrokeColor3 = INK
	big.Text = if floor >= SUMMIT then "🏆 SOMMET ! 🏆" else "ÉTAGE " .. floor .. " !"
	big.Size = UDim2.fromOffset(250, 45)
	local grow = TweenService:Create(big, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(500, 90) })
	grow:Play()
	task.delay(1.1, function()
		local fade = TweenService:Create(big, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Connect(function()
			big:Destroy()
		end)
	end)
end)

screen.Parent = player:WaitForChild("PlayerGui")

task.delay(2, function()
	if toastToken == 0 then
		showToast("Cours partout : chaque pas = +1 saut ! 👟☁️", 5)
	end
end)
