# Tour des Nuages +1 ☁️👟

**Genre :** obby incrémental « +1 » · **Public :** 8-14 ans · **Créé le :** 20/11/2026

## Concept
Chaque pas te donne **+1 de puissance de saut**. Cours dans la prairie, saute d'étage en étage sur une tour de 30 nuages en spirale, atteins le **Sommet** puis fais une **Renaissance** (multiplicateur permanent ×1,5 par renaissance).

## Boucle de jeu
1. Courir au sol → points de saut (calculés côté serveur, plafonnés à la vitesse de marche : pas de triche par téléport).
2. Sauter sur l'étage suivant (la barre en haut indique le saut nécessaire).
3. Chaque nouvel étage → ⭐ étoiles (5 × n° d'étage). Checkpoint tous les 5 étages.
4. ⭐ → **Bottes** (+25 % de points par pas et par niveau, 20 niveaux).
5. Sommet (+500 ⭐) → Renaissance : saut remis à zéro, pas ×1,5 de plus.

Rythme visé : étage 1 en ~20 s, sommet en ~6-10 min la première fois.

## Monétisation (facultative, rien n'est obligatoire)
- Pass **Pas x2** (~149 R$) · Pass **Course rapide** (vitesse 24, ~99 R$) · Produit **+500 saut** (~25 R$).
- Remplace les `0` dans `src/shared/Config.luau` par les ID du Creator Dashboard. Aucun achat aléatoire.

## Fichiers
- `TourDesNuages.rbxlx` : à ouvrir dans Roblox Studio (construit par `bash tools/check.sh games/tour-des-nuages`).
- `src/` : code Rojo (serveur, interface, Config). `marketing/` : fiche Roblox, scripts TikTok/Shorts, prompts OpenArt.

## État
- Build Rojo + luau-lsp : ✅ 0 erreur (20/11/2026)
- **Testé dans Studio : non** — le 20/11 le chargement a été lancé dans Studio mais l'écran du Mac s'est verrouillé avant le Play.
- **Publié : non**
- Note qualité provisoire : **70/100** (voir rapport du 20/11) → sous le seuil de 80.

## À faire avant publication
- Test Play complet (sol → étage 5 → checkpoint → sommet → renaissance), vérifier l'Output.
- Visuels : remplacer les nuages en boules par des nuages modélisés, ajouter sons (saut, étage, sommet) libres de droits.
- Classement (leaderboard) des sommets et une piste de course plus lisible.
