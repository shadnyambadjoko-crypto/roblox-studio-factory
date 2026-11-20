# Refuge des Bestioles 🐰🦊🐉

**Genre :** tycoon de collection cosy (sans vol) · **Public :** 7-13 ans · **Créé le :** 20/11/2026

## Concept
Des bestioles perdues se promènent dans la Prairie, la Forêt et la Montagne. Recueille-les, ramène-les dans **ton refuge**, installe-les dans des enclos : elles produisent des **cœurs ❤**. Avec les cœurs, agrandis le refuge, ton panier et ouvre de nouvelles zones. Complète le **Bestiaire** (9 espèces, dont le Dragonnet-nuage légendaire).
Différence avec la vague « Steal a … » : ici on **recueille et on protège**, personne ne vole personne — positionnement famille, rassurant pour les parents.

## Boucle de jeu
1. Prairie → touche E sur une bestiole (maintien plus long pour les rares) → panier.
2. Fil rose vers l'**Accueil** de ton refuge → installation dans un enclos (bonus à la 1re découverte d'une espèce).
3. La **Boîte à cœurs** se remplit (plafond = 10 min de production) → Collecter.
4. ❤ → enclos supplémentaires (4 → 12), panier (+1 place / niveau), Forêt (2 500 ❤), Montagne (50 000 ❤).
5. Refuge plein → « Confier à une famille » : la bestiole est adoptée (bonus = 2 min de sa production) et libère la place pour une meilleure.

## Monétisation (facultative, aucun achat aléatoire)
- Pass **Cœurs x2** (~199 R$) · Pass **Grand panier** (+3 places, ~99 R$) · Produit **+2 500 ❤** (~29 R$).
- Les apparitions rares sont gratuites et identiques pour tous ; rien de payant n'est tiré au hasard.
- Remplace les `0` dans `src/shared/Config.luau` par les ID du Creator Dashboard.

## Fichiers
- `RefugeDesBestioles.rbxlx` : à ouvrir dans Roblox Studio. `src/` : code Rojo. `marketing/` : kit de lancement.

## État
- Build Rojo + luau-lsp : ✅ 0 erreur (20/11/2026)
- **Testé dans Studio : non** (Mac verrouillé pendant la session du 20/11)
- **Publié : non**
- Note qualité provisoire : **73/100** (voir rapport du 20/11) → sous le seuil de 80.

## Limites connues
- ~~Panier non sauvegardé~~ : corrigé le 20/11 au soir (le panier est retrouvé à la reconnexion).
- Bestioles en formes simples (boules) : un vrai modèle par espèce ferait monter la note de direction artistique.
- Pas encore de sons ni de quêtes quotidiennes.
