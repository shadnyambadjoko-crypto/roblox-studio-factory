--!strict
-- Configuration du « Refuge des Bestioles ». Tout ce qu'on règle se trouve ici.
-- Principe : explore la prairie, la forêt et la montagne, recueille des bestioles perdues,
-- installe-les dans ton refuge. Elles te donnent des cœurs ❤ qui servent à agrandir le refuge.

export type Species = {
	id: string,
	name: string,
	zone: string,
	rarity: string,
	weight: number, -- chance d'apparition relative dans sa zone (gratuit, jamais payant)
	hps: number, -- cœurs par seconde dans un enclos
	color: Color3,
	accent: Color3,
	size: number,
}

export type Zone = {
	id: string,
	name: string,
	price: number,
	wildCount: number,
	zMin: number,
	zMax: number,
	color: Color3,
}

local Config = {}

Config.DataStoreName = "RefugeDesBestioles_v1"
Config.AutosaveInterval = 60
Config.PlotCount = 6
Config.StartingHearts = 0

-- Enclos
Config.StartingSlots = 4
Config.MaxSlots = 12
function Config.SlotPrice(slotsOwned: number): number
	return math.floor(150 * 2.1 ^ (slotsOwned - Config.StartingSlots))
end

-- Panier (combien de bestioles on porte à la fois)
Config.NetMaxLevel = 5
Config.BigBasketBonus = 3
function Config.NetCapacity(level: number): number
	return 2 + level
end
function Config.NetPrice(level: number): number
	return math.floor(120 * 3.2 ^ level)
end

-- Boîte à cœurs : se remplit toute seule, plafonnée à 10 minutes de production
Config.BoxCapSeconds = 600

-- Confier une bestiole à une famille (libère l'enclos) : bonus = 2 minutes de sa production
Config.AdoptBonusSeconds = 120
-- Bonus de première découverte d'une espèce
Config.DiscoveryBonusSeconds = 30

Config.RarityColors = table.freeze({
	Commune = Color3.fromRGB(235, 235, 235),
	Rare = Color3.fromRGB(110, 190, 255),
	["Épique"] = Color3.fromRGB(200, 120, 255),
	["Légendaire"] = Color3.fromRGB(255, 200, 50),
}) :: { [string]: Color3 }

Config.RarityHold = table.freeze({
	Commune = 0.3,
	Rare = 0.7,
	["Épique"] = 1.2,
	["Légendaire"] = 2,
}) :: { [string]: number }

Config.Zones = table.freeze({
	table.freeze({ id = "prairie", name = "Prairie", price = 0, wildCount = 10, zMin = 15, zMax = 120, color = Color3.fromRGB(140, 210, 110) }),
	table.freeze({ id = "foret", name = "Forêt", price = 2500, wildCount = 8, zMin = 140, zMax = 240, color = Color3.fromRGB(70, 140, 80) }),
	table.freeze({ id = "montagne", name = "Montagne", price = 50000, wildCount = 7, zMin = 260, zMax = 360, color = Color3.fromRGB(215, 225, 240) }),
}) :: { Zone }
Config.ZoneHalfWidth = 120

Config.Species = table.freeze({
	-- Prairie
	table.freeze({ id = "lapinou", name = "Lapinou", zone = "prairie", rarity = "Commune", weight = 60, hps = 1, color = Color3.fromRGB(250, 250, 250), accent = Color3.fromRGB(255, 180, 200), size = 2.4 }),
	table.freeze({ id = "poussin", name = "Poussin-pomme", zone = "prairie", rarity = "Commune", weight = 35, hps = 2, color = Color3.fromRGB(255, 230, 90), accent = Color3.fromRGB(230, 70, 60), size = 2.2 }),
	table.freeze({ id = "herisson", name = "Hérisson-fraise", zone = "prairie", rarity = "Rare", weight = 5, hps = 6, color = Color3.fromRGB(240, 90, 110), accent = Color3.fromRGB(90, 200, 90), size = 2.6 }),
	-- Forêt
	table.freeze({ id = "renardeau", name = "Renardeau", zone = "foret", rarity = "Commune", weight = 60, hps = 12, color = Color3.fromRGB(240, 130, 50), accent = Color3.fromRGB(255, 255, 255), size = 3 }),
	table.freeze({ id = "ecureuil", name = "Écureuil-gland", zone = "foret", rarity = "Rare", weight = 32, hps = 25, color = Color3.fromRGB(170, 100, 60), accent = Color3.fromRGB(240, 200, 120), size = 2.6 }),
	table.freeze({ id = "cerf", name = "Faon-lune", zone = "foret", rarity = "Épique", weight = 8, hps = 70, color = Color3.fromRGB(150, 160, 230), accent = Color3.fromRGB(255, 255, 200), size = 3.6 }),
	-- Montagne
	table.freeze({ id = "chamois", name = "Chamois-neige", zone = "montagne", rarity = "Commune", weight = 60, hps = 150, color = Color3.fromRGB(245, 245, 255), accent = Color3.fromRGB(120, 130, 160), size = 3.2 }),
	table.freeze({ id = "hibou", name = "Hibou-étoile", zone = "montagne", rarity = "Rare", weight = 32, hps = 320, color = Color3.fromRGB(80, 70, 140), accent = Color3.fromRGB(255, 230, 100), size = 2.8 }),
	table.freeze({ id = "dragonnet", name = "Dragonnet-nuage", zone = "montagne", rarity = "Légendaire", weight = 8, hps = 1000, color = Color3.fromRGB(150, 230, 255), accent = Color3.fromRGB(255, 160, 220), size = 3.8 }),
}) :: { Species }

function Config.GetSpecies(id: string): Species?
	for _, s in Config.Species do
		if s.id == id then
			return s
		end
	end
	return nil
end

function Config.GetZone(id: string): Zone?
	for _, z in Config.Zones do
		if z.id == id then
			return z
		end
	end
	return nil
end

-- Monétisation : remplace les 0 par les vrais ID créés dans le Creator Dashboard.
-- Tant qu'un ID vaut 0, le bouton correspondant n'apparaît pas. Aucun achat aléatoire.
Config.GamePasses = table.freeze({
	DoubleHearts = 0, -- x2 cœurs
	BigBasket = 0, -- +3 places dans le panier
})

Config.DevProducts = table.freeze({
	-- [ID du produit] = cœurs donnés
	-- [123456789] = 2500,
}) :: { [number]: number }

Config.DevProductLabels = table.freeze({
	-- [123456789] = "+2 500 ❤",
}) :: { [number]: string }

return table.freeze(Config)
