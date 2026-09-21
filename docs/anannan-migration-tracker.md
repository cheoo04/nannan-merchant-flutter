# Suivi migration — Supabase → API Neon (A NAN NAN Livraison Oumé)

Dernière mise à jour : 20/09/2026

Objectif : migrer l'app Marchand de Supabase vers `api-a-nan-nan.vercel.app`.
Ce fichier centralise ce qui est fait, ce qui reste, et ce qui bloque côté
backend — pour ne rien reperdre entre les sessions.

## 🔴 Bloquants backend actifs

**Bloquant central, remonté le 20/09** : aucun moyen pour l'app de récupérer
le `merchant_id` du marchand connecté après `/auth/login` (pas d'endpoint
"mes marchands"), et flou sur qui crée la ligne `merchants` à l'approbation
d'une candidature (`role-applications` → admin approve → ??? ). **Bloque
Dashboard, Products, Orders, Finances** — tout écran qui a besoin de savoir
"quel marchand suis-je" après connexion. Demande envoyée : un endpoint style
`GET /api/v1/merchants/mine`.

## 🟡 Gaps API connus (contournés, pas bloquants)

| Gap | Impact | Contournement actuel |
|---|---|---|
| Pas d'endpoint "mes marchands" (quel marchand m'appartient ?) | Impossible de vérifier le rôle marchand après login | `LoginScreen` route tout le monde vers "Devenir partenaire", comme un nouveau compte (voir TODO dans `main.dart`) |
| Pas d'endpoint "mes candidatures" (côté utilisateur, pas admin) | Impossible de savoir si une demande marchand est déjà en attente | `BecomeMerchantScreen._checkExisting()` ne vérifie plus rien, repart toujours de l'étape info (TODO dans le fichier) |
| Pas de code `business_type` dédié pour "recharge de gaz" | Catégorie mappée sur `service` faute de mieux | Mapping en dur dans `become_merchant_screen.dart` (`_businessTypeCodeByCategory`) |
| Pas de `PATCH /offerings/{id}` | Impossible de modifier un produit existant | `updateProduct()` affiche une erreur claire en attendant |
| Pas de `DELETE /offerings/{id}` | Impossible de supprimer un produit | `deleteProduct()` idem |
| Pas de bascule rapide stock/dispo sur une variante seule | `toggleAvailability()` (le petit switch dispo/masqué) idem | idem |
| Pas de "realtime" (webhooks/websockets) sur Neon | Les autres marchands connectés ne voient plus les changements en direct comme avant (Supabase Realtime) | Rafraîchissement manuel uniquement pour l'instant (`ProductsNotifier.refresh()`) |
| Pas de vraies "stories" (éphémères 24h) | — | `merchants.story_images` (array simple) OU `/publications` (pas d'expiration) — lequel est la voie officielle ? Toujours pas tranché avec le backend |

## 🟠 Code prêt, bloqué uniquement par `merchant_id`

- **Products** (`products_screen.dart`) : `ProductsNotifier` entièrement réécrit
  contre `OfferingService` (list/create + upload d'image). `merchantId` est un
  champ nullable avec `setMerchantId(id)` prévu pour le brancher dès que
  l'endpoint "mes marchands" existe — tant qu'il est `null`, l'écran
  n'appelle jamais la nouvelle API (pas de plantage, juste rien ne se charge)
  et les actions non couvertes (modifier/supprimer un produit, bascule
  stock) affichent un message clair au lieu de planter.

## ✅ Déjà migré (fonctionne avec la nouvelle API)

- **Auth** : `LoginScreen` + `SignupScreen` (`main.dart`, `signup_screen.dart`) — téléphone + PIN, via `ANanNanApiClient.register/login`
- **Candidature marchand** : `BecomeMerchantScreen` → `POST /auth/role-applications`
- **Client API** : `lib/core/services/a_nan_nan_api_client.dart` — auth, refresh automatique sur 401, gestion erreurs, **upload de fichiers** (`uploadFile()`, multipart, indépendant du `merchant_id`)
- **Services prêts à l'emploi** (`a_nan_nan_services.dart`) : `MerchantService`, `CategoryService`, `OfferingService`, `OrderService`, `PublicationService` — écrits mais pas encore branchés sur tous les écrans

## ⬜ Pas encore migré (encore sur Supabase)

- Dashboard (KPIs marchand)
- Orders (commandes) — service prêt, écran pas branché ; **prix confirmé sécurisé côté serveur** (testé le 19/09, rejet 422 si écart)
- Finances
- PIN backup (`pin_hash`/`pin_salt` sur `users_profiles`) — n'a plus lieu d'être une fois basculé sur Neon (le PIN devient l'auth elle-même, plus un verrou d'app à part) ; à retirer plutôt qu'à migrer

## Notes techniques utiles

- Base : Neon (Postgres), séparée du projet Supabase `ilhanzanjduogsmfjmwm`
- Auth : téléphone + PIN 4 chiffres, JWT maison (`access_token` 15 min, `refresh_token` longue durée) — rien à voir avec Supabase Auth
- Le backend revalide les prix côté serveur à la commande (`OrderItemInput.unit_price` est indicatif) — confirmé par test manuel
