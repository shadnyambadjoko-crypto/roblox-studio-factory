--!strict
-- Configuration du jeu « Potager Tycoon ». Tout ce qu'on règle se trouve ici.

export type Seed = {
	id: string,
	name: string,
	cost: number, -- prix pour planter une graine
	reward: number, -- pièces gagnées à la récolte
	growTime: number, -- secondes avant d'être mûr
	unlockPrice: number, -- prix pour débloquer cette graine (0 = débloquée au départ)
	color: Color3,
}

local Config = {}

Config.StartingCoins = 25
Config.PlotCount = 6 -- nombre de terrains (donc joueurs max par serveur)
Config.BedsPerPlot = 9 -- parcelles maximum par terrain
Config.StartingBeds = 3 -- parcelles débloquées au départ
Config.BedBasePrice = 50 -- prix de la 4e parcelle, puis x1.6 à chaque fois
Config.BedPriceGrowth = 1.6
Config.AutosaveInterval = 60
Config.DataStoreName = "PotagerTycoon_v1"

Config.Seeds = table.freeze({
	table.freeze({ id = "carotte", name = "Carotte", cost = 2, reward = 5, growTime = 8, unlockPrice = 0, color = Color3.fromRGB(255, 140, 30) }),
	table.freeze({ id = "tomate", name = "Tomate", cost = 10, reward = 28, growTime = 20, unlockPrice = 150, color = Color3.fromRGB(220, 40, 40) }),
	table.freeze({ id = "mais", name = "Maïs", cost = 40, reward = 120, growTime = 45, unlockPrice = 900, color = Color3.fromRGB(250, 215, 60) }),
	table.freeze({ id = "citrouille", name = "Citrouille", cost = 150, reward = 480, growTime = 90, unlockPrice = 5000, color = Color3.fromRGB(240, 110, 20) }),
	table.freeze({ id = "melon_or", name = "Melon d'or", cost = 600, reward = 2200, growTime = 180, unlockPrice = 30000, color = Color3.fromRGB(255, 200, 0) }),
}) :: { Seed }

-- Monétisation : remplace les 0 par les vrais ID créés dans le Creator Dashboard.
-- Tant qu'un ID vaut 0, le bouton correspondant n'apparaît pas.
Config.GamePasses = table.freeze({
	DoubleCoins = 0, -- x2 pièces à chaque récolte
	FastGrow = 0, -- les plantes poussent 2x plus vite
})

Config.DevProducts = table.freeze({
	-- [ID du produit] = pièces données
	-- [123456789] = 1000,
}) :: { [number]: number }

-- Pour l'affichage du bouton de la boutique (ID → libellé)
Config.DevProductLabels = table.freeze({
	-- [123456789] = "+1 000 pièces",
}) :: { [number]: string }

function Config.GetSeed(id: string): Seed?
	for _, seed in Config.Seeds do
		if seed.id == id then
			return seed
		end
	end
	return nil
end

function Config.BedPrice(bedsOwned: number): number
	return math.floor(Config.BedBasePrice * Config.BedPriceGrowth ^ (bedsOwned - Config.StartingBeds))
end

return table.freeze(Config)
