# Potager Tycoon 🥕

Jeu Roblox cosy : chaque joueur a son potager, plante des graines, récolte des pièces, débloque de nouvelles parcelles et de meilleures graines (carotte → tomate → maïs → citrouille → melon d'or).

## 1. Ouvrir et tester (5 min)
1. Installe Roblox Studio (gratuit) : https://create.roblox.com
2. Double-clique sur `PotagerTycoon.rbxlx`.
3. Clique sur **Play** (F5). Approche-toi d'une parcelle et appuie sur **E** pour planter / récolter / acheter.
4. Clique sur les graines en bas de l'écran pour choisir ou débloquer.

## 2. Activer la sauvegarde
Home → Game Settings → Security → active **Enable Studio Access to API Services** (après la 1re publication).

## 3. Publier
File → **Publish to Roblox** → nom : « Potager Tycoon 🥕 », genre : Simulation. Puis dans le Creator Dashboard : rends le jeu **Public**.

## 4. Gagner des Robux
Dans le Creator Dashboard → ton jeu → Monetization :
- **Passes** : crée « Pièces x2 » (~199 Robux) et « Pousse x2 » (~149 Robux).
- **Developer Products** : crée « +1 000 pièces » (~49 Robux).
Copie chaque ID dans `ReplicatedStorage > Shared > Config` (lignes `GamePasses` et `DevProducts` / `DevProductLabels`). Le bouton 🛒 Boutique apparaît tout seul.

## 5. Visuels avec OpenArt (https://openart.ai)
- **Icône (512×512)** : « cute cartoon vegetable garden, smiling carrot and tomato, bright colors, Roblox game icon style, bold outlines, plain sunny background, no text »
- **Miniature (1920×1080)** : « cozy cartoon farm with Roblox-style blocky characters planting giant carrots and golden melons, sparkles, sunny day, vibrant colors, 3D render, no text »
Ajoute ensuite le titre toi-même (Canva) et importe-les dans Creator Dashboard → Places → Thumbnails.

## Modifier le jeu
Tous les réglages (prix, gains, temps de pousse, nouvelles graines) sont dans `Config`. Le dossier `src/` contient le code source (compatible Rojo).
