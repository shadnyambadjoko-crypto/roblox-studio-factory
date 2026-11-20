--!strict
-- Configuration de « Tour des Nuages +1 ». Tout ce qu'on règle se trouve ici.
-- Principe : chaque pas donne +1 de puissance de saut. Plus tu cours, plus tu sautes haut,
-- plus tu montes dans la tour de nuages. Au sommet : renaissance (multiplicateur permanent).

local Config = {}

Config.DataStoreName = "TourDesNuages_v1"
Config.AutosaveInterval = 60

-- Saut
Config.BaseJumpPower = 50 -- saut normal de Roblox
Config.PowerPerJump = 10 -- 10 points de puissance = +1 JumpPower
Config.MaxJumpPower = 350
Config.StudsPerPoint = 2 -- 2 studs parcourus au sol = +1 point (avant multiplicateurs)

-- Tour
Config.FloorCount = 30
Config.CheckpointEvery = 5
Config.SpiralRadius = 30
Config.SpiralStep = 0.6 -- radians entre deux étages
Config.PlatformSize = 13

-- Hauteur à franchir pour passer de l'étage i-1 à l'étage i
function Config.FloorRise(i: number): number
	return 6 + i * 3
end

-- Puissance de saut nécessaire (avec marge) pour franchir une hauteur
function Config.JumpPowerFor(rise: number): number
	return math.sqrt(2 * 196.2 * rise) * 1.08
end

-- Étoiles gagnées la première fois qu'on atteint l'étage i dans une ascension
function Config.FloorReward(i: number): number
	return 5 * i
end
Config.SummitReward = 500

-- Bottes (amélioration achetée avec les étoiles) : +25 % de points par pas et par niveau
Config.BootsMaxLevel = 20
function Config.BootsPrice(level: number): number
	return math.floor(40 * 1.65 ^ level)
end
function Config.BootsMultiplier(level: number): number
	return 1 + 0.25 * level
end

-- Renaissance : +50 % de points par pas, cumulatif
function Config.RebirthMultiplier(rebirths: number): number
	return 1 + 0.5 * rebirths
end

function Config.JumpPowerFromPoints(points: number): number
	return math.min(Config.BaseJumpPower + points / Config.PowerPerJump, Config.MaxJumpPower)
end

-- Monétisation : remplace les 0 par les vrais ID créés dans le Creator Dashboard.
-- Tant qu'un ID vaut 0, le bouton correspondant n'apparaît pas.
Config.GamePasses = table.freeze({
	DoubleSteps = 0, -- x2 points par pas
	FastRunner = 0, -- vitesse de course 24 au lieu de 16
})
Config.FastWalkSpeed = 24

Config.DevProducts = table.freeze({
	-- [ID du produit] = points de saut donnés
	-- [123456789] = 500,
}) :: { [number]: number }

Config.DevProductLabels = table.freeze({
	-- [123456789] = "+500 saut",
}) :: { [number]: string }

return table.freeze(Config)
