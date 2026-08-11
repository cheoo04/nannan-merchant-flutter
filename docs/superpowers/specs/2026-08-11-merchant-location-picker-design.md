# Design — Sélecteur de position GPS marchand

Date : 2026-08-11
Statut : Validé par l'utilisateur, prêt pour `writing-plans`

## Contexte

Le dev client (documents `OSRM_Map_Integration_Plan.md`, `Livreur_Marchand_Tracking_Guidelines.md`,
`Integration_Livreur_Marchand.md`) a besoin que chaque marchand ait des coordonnées GPS précises
en base pour que le calcul d'itinéraire OSRM (Livreur → Marchand) fonctionne côté application Client.

La table `merchants` a déjà les colonnes nécessaires :
- `lat` (`double precision`, nullable)
- `lng` (`double precision`, nullable)

Aucune migration SQL n'est donc nécessaire pour la table `merchants`.

`MerchantModel` (`lib/shared/models/models.dart`) n'a en revanche **aucun champ GPS** actuellement —
c'est le premier trou à combler.

## Objectif

Permettre à un marchand de renseigner sa position GPS de deux façons complémentaires,
combinées dans un seul composant réutilisable :
1. Recherche d'adresse en texte libre (géocodage)
2. Capture de la position GPS de son téléphone (utile quand il est physiquement en boutique)

Avec, dans les deux cas, un ajustement manuel final du point sur une carte.

Et ce, à deux moments :
- **À l'inscription** (`BecomeMerchantScreen`)
- **Après coup**, modifiable depuis les réglages boutique

## Service de géocodage

Aucun service de géocodage n'est documenté ni fourni par le dev client (vérifié : les 3 documents
ne mentionnent que l'endpoint de routage OSRM `osrm.are-healthcare.me/route/v1/driving/...` et le
package `flutter_map` pour l'affichage — rien pour la recherche d'adresse par nom).

Décision : utiliser **Nominatim** (service public OpenStreetMap, gratuit, sans clé API), cohérent
avec le choix de `flutter_map`/OpenStreetMap déjà fait pour le reste du projet.
- Endpoint : `https://nominatim.openstreetmap.org/search?q={query}&countrycodes=ci&format=json`
- Contrainte à respecter : [politique d'usage Nominatim](https://operations.osmfoundation.org/policies/nominatim/)
  (1 requête/seconde max, User-Agent identifiable) — le debounce sur la recherche couvre cette limite.

## Architecture

### Nouveau composant partagé : `LocationPickerScreen`
Nouveau dossier `lib/features/location_picker/`.

Écran poussé en `Navigator.push`, qui retourne `{lat, lng, address}` via `Navigator.pop(result)` —
comme un formulaire modal classique. Réutilisé identiquement aux deux points d'entrée (inscription
et modification), pour éviter toute duplication de logique carte/recherche/GPS.

**Paramètres d'entrée** (optionnels) : `initialLat`, `initialLng`, `initialAddress` — pour le cas
modification, où l'écran s'ouvre déjà centré sur la position existante avec un marqueur en place.

**Flux interne :**
1. Ouverture : carte `flutter_map` centrée sur la position initiale si fournie, sinon sur Oumé par défaut.
2. Barre de recherche en haut → requêtes debouncées vers Nominatim → liste de résultats sous la barre.
3. Sélection d'un résultat → carte recentrée, marqueur placé.
4. Bouton flottant "Utiliser ma position actuelle" (`geolocator`) → carte recentrée sur la position
   device, marqueur placé.
5. Le marqueur reste ajustable manuellement sur la carte (drag, ou solution équivalente à valider
   en implémentation selon le support de `flutter_map`).
6. Bouton "Confirmer cette position" → retourne le résultat à l'appelant.

### Nouveaux packages
- `flutter_map` (carte, basé sur Leaflet, pas de clé API)
- `geolocator` (position GPS device)
- `latlong2` (type `LatLng` utilisé par `flutter_map`)

### `MerchantModel`
Ajout de deux champs optionnels :
```dart
final double? lat;
final double? lng;
```
Mappés depuis/vers `j['lat']` / `j['lng']` dans `fromJson`.

### Point d'entrée 1 — Inscription (`BecomeMerchantScreen`)
Dans l'étape 1 du formulaire (`_submitInfo`), à côté du champ adresse texte existant : bouton
"Localiser mon commerce" ouvrant `LocationPickerScreen`. Le résultat est stocké dans le `payload`
JSON de `partner_applications` (aux côtés de `address`, `business_name`, etc.), au même niveau que
les autres champs déjà présents.

⚠️ **Point ouvert, hors périmètre de ce dépôt** : la fonction `approve_partner_application()`
(côté base de données, non présente dans ce dépôt) doit recopier `payload.lat`/`payload.lng` vers
`merchants.lat`/`merchants.lng` au moment de la création de la ligne marchand. À vérifier/adapter
en base après implémentation — sans quoi la capture à l'inscription n'aura aucun effet en pratique.

### Point d'entrée 2 — Modification (réglages boutique)
Les réglages boutique (horaires, pause) vivent actuellement dans `products_screen.dart`. Ajout
d'une section "Position" affichant l'adresse actuelle + bouton "Modifier la position" ouvrant
`LocationPickerScreen` pré-rempli avec les `lat`/`lng` existants du marchand. Confirmation → `update`
direct sur `merchants` (`.eq('id', merchant.id)`), suivant le pattern déjà utilisé dans ce fichier
pour les horaires et la pause boutique.

### Permissions
- Android : `ACCESS_FINE_LOCATION` dans `android/app/src/main/AndroidManifest.xml`
- iOS : `NSLocationWhenInUseUsageDescription` dans `ios/Runner/Info.plist`

## Gestion des erreurs

En s'appuyant sur `friendlyError()` (`lib/core/utils/error_message.dart`) déjà en place :
- Permission GPS refusée → message inline non bloquant ("Position refusée — recherchez votre
  adresse à la place"), la recherche texte reste utilisable
- GPS indisponible / timeout → couvert par le cas `TimeoutException` déjà géré dans `friendlyError`
- Échec réseau sur la recherche Nominatim → couvert par les cas `SocketException`/`ClientException`
  déjà gérés dans `friendlyError`
- Aucun résultat de recherche → message "Aucune adresse trouvée" sous la barre (pas une erreur)
- Bouton "Confirmer" désactivé tant qu'aucune position n'a été choisie

## Tests

Le composant est très visuel/GPS-dépendant, difficile à unit-tester utilement dans son ensemble :
- Test unitaire sur le parsing de la réponse Nominatim (JSON → liste de résultats)
- Vérification manuelle sur device réel pour le flux complet (inscription + modification), avant
  de considérer la fonctionnalité terminée (skill `verification-before-completion`)

## Hors périmètre

- Application Livreur (émission GPS en tâche de fond) — pas ce dépôt
- Application Client (affichage carte, animation moto, tracking temps réel) — pas ce dépôt
- `orders.delivery_lat`/`delivery_lng` — géré côté création de commande, à voir séparément si
  pertinent pour ce dépôt marchand
- Correctif du compte marchand sans ligne `merchants` — sujet séparé (bug, pas une fonctionnalité),
  traité indépendamment via `systematic-debugging` une fois le résultat de la requête diagnostic
  disponible
