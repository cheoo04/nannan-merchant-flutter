# Correctif — cloche notifications dashboard-only

Un seul fichier à remplacer : `lib/main.dart`.

## Ce qui change vs la version précédente que tu as déjà mergée

En comparant directement les routes marchand React (`_app.merchant-dashboard.tsx`,
`_app.merchant-finance.tsx`, `_app.merchant-products.tsx`,
`_app.merchant-prescriptions.tsx`, etc.), la cloche `Bell` + `CitySwitcher`
n'existent QUE sur le dashboard. Aucune des 5 autres pages marchand n'a
de cloche dans le React d'origine.

Avant : `_openNotifications` + `unreadCount: 0` étaient passés aux 6 écrans
(Dashboard, Commandes, Produits, Stories, Ordonnances, Finances).

Maintenant : uniquement passés à `DashboardScreen`. Les 5 autres écrans
n'affichent plus aucune cloche (stub ou pas) — leurs paramètres
`unreadCount`/`onGoToNotifications` étaient déjà optionnels dans leur
code, donc aucun autre fichier n'a besoin d'être modifié.

## À faire

Remplace `lib/main.dart` dans ton repo par celui-ci, puis :

```bash
git add lib/main.dart
git commit -m "fix: cloche notifications affichée uniquement sur le dashboard (miroir React)"
git push
```
