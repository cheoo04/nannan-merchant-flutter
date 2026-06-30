# Fichiers modifiés — session du 30/06/2026

Arborescence à recopier telle quelle dans `nannan-merchant-flutter/` (mêmes chemins).

## 1. Fichiers MODIFIÉS (à écraser dans ton repo)

- `lib/main.dart`
  → Cloche notifications neutralisée (stub désactivé, unreadCount=0, tap
  no-op). Imports vers `features/notifications/...` retirés.

- `lib/features/finances/finance_screen.dart`
  → 3 corrections pour matcher le React `_app.merchant-finance.tsx` :
    1. `maxY` ne tombe plus à 0 quand toutes les ventes valent 0 (c'était
       la cause du graphique sans axes/graduations sur ta capture).
    2. Le graphique "Ventes par période" s'affiche maintenant toujours
       (même sans aucune commande), comme en React.
    3. "Historique des paiements" affiche le message
       "Aucune vente livrée pour le moment." au lieu de disparaître.

## 2. Fichier NOUVEAU (à créer)

- `lib/shared/widgets/notification_bell_button.dart`
  → Remplace l'ancien (déplacé, voir partie 3). Stub visuel : cloche
  grisée, badge jamais affiché, tap sans effet. Garde la même position
  et taille que l'originale pour ne rien casser visuellement dans les
  6 écrans qui l'utilisent.

- `supabase/migrations/20260630000000_stories_module.sql`
  → Migration manquante pour que le module Stories marche sur une base
  fraîche (pas seulement la tienne) :
    - colonnes `story_images` / `story_video_url` sur `merchants`
    - bucket Storage `stories` + policies RLS (upload dans son propre
      dossier, lecture publique)
  À exécuter sur Supabase (SQL Editor ou `supabase db push`) si ce
  bucket n'a pas déjà été créé manuellement ailleurs.

## 3. Fichiers DÉPLACÉS, pas supprimés (dans `_set_aside/notifications/`)

Ce sont tes fichiers ORIGINAUX, fonctionnels, juste sortis du chemin
de compilation actif. Périmètre FE-14 "Notifications" = assigné à la
partie Client dans le tableau de répartition, pas à Marchand.

- `_set_aside/notifications/notifications_notifier.dart`
- `_set_aside/notifications/notifications_screen.dart`
- `_set_aside/notifications/widgets/notification_bell_button.dart`
  (= l'ANCIEN bell button, avec le vrai badge fonctionnel — à montrer
  à la personne qui fait Client pour comparer avec sa propre version)

À recopier dans ton repo sous `nannan-merchant-flutter/_set_aside/...`
(nouveau dossier à la racine, à côté de `lib/`).

## Pour remettre les vraies notifications plus tard

1. Restaurer les 3 fichiers de `_set_aside/notifications/` à leur
   ancien emplacement (`lib/features/notifications/...` et
   `lib/shared/widgets/notification_bell_button.dart`).
2. Dans `main.dart` : ré-ajouter les imports, recréer
   `NotificationsNotifier` dans `_MerchantShellState`, restaurer
   `_openNotifications()` pour ouvrir `NotificationsScreen`, remplacer
   `0 /* notif mise de côté */` par `_notifNotifier.unreadCount`.
