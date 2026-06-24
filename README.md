# Nan-Nan Connect — App Flutter Marchand

> **Contexte** : Le client a un prototype web React/Lovable fonctionnel (`Nan_Nan_Connect.zip`).
> Tu dois recoder la **partie Marchand uniquement** en Flutter natif, connecté au même backend Supabase.

---

## 🔗 Connexion Supabase (même projet que le web)

```
URL      : https://kmnrwcvaoaiktosvduvc.supabase.co
ANON KEY : eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImttbnJ3Y3Zhb2Fpa3Rvc3ZkdXZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczNDI5NDgsImV4cCI6MjA5MjkxODk0OH0.m7lbgYdkcg4wrlj7yN0nOTn3w3WBYfcWJzK7B9evJq4
```

Mettre ces valeurs dans `lib/core/supabase/supabase_config.dart` (jamais dans le code versionné en prod).

---

## 📋 Ce que tu dois coder (interfaces Marchand)

| ID     | Écran Flutter                  | Équivalent React                         | Priorité |
|--------|-------------------------------|------------------------------------------|----------|
| FE-16  | `DashboardScreen`             | `merchant-dashboard.tsx`                 | 🔴 Haute |
| FE-17  | `OrdersScreen`                | `merchant-orders.tsx`                    | 🔴 Haute |
| FE-18  | `ProductsScreen`              | `merchant-products.tsx`                  | 🔴 Haute |
| FE-19  | `CreateEditProductScreen`     | `merchant-create-product.tsx`            | 🔴 Haute |
| FE-20  | `FinanceScreen`               | `merchant-finance.tsx`                   | 🟡 Moyenne |
| FE-21  | `StoriesScreen`               | *(pas encore codé en React)*             | 🟡 Moyenne |
| FE-22  | `PrescriptionsScreen`         | `merchant-prescriptions.tsx`             | 🔴 Haute |
| FE-23  | `BecomeMerchantScreen`        | `become-merchant.tsx`                    | 🔴 Haute |

> **Auth** : La connexion/inscription est partagée avec les autres équipes.
> Tu dois quand même coder `LoginScreen` et la redirection vers l'espace marchand si `role == 'merchant'`.

---

## 🏗️ Architecture du projet

```
nannan_merchant_flutter/
├── lib/
│   ├── main.dart                          # Entrypoint + init Supabase
│   ├── core/
│   │   ├── supabase/
│   │   │   ├── supabase_config.dart       # URL + ANON KEY
│   │   │   └── supabase_service.dart      # Singleton client Supabase
│   │   ├── auth/
│   │   │   ├── auth_service.dart          # login/logout/session
│   │   │   └── auth_guard.dart            # Redirect si pas merchant
│   │   ├── theme/
│   │   │   ├── app_theme.dart             # Couleurs, typos (Sora/Inter)
│   │   │   └── app_colors.dart            # Design tokens
│   │   └── utils/
│   │       ├── formatters.dart            # formatXOF(), dates, etc.
│   │       └── constants.dart             # ORDER_STATUSES, etc.
│   ├── features/
│   │   ├── auth/
│   │   │   ├── login_screen.dart          # FE-02 (partagé équipe)
│   │   │   └── auth_notifier.dart         # State auth (Riverpod/Provider)
│   │   ├── dashboard/
│   │   │   ├── dashboard_screen.dart      # FE-16 🔴
│   │   │   ├── dashboard_notifier.dart    # KPIs, toggle ouvert/fermé
│   │   │   └── widgets/
│   │   │       ├── kpi_card.dart
│   │   │       ├── alert_card.dart
│   │   │       └── merchant_toggle.dart
│   │   ├── orders/
│   │   │   ├── orders_screen.dart         # FE-17 🔴
│   │   │   ├── orders_notifier.dart       # Realtime orders
│   │   │   ├── order_detail_sheet.dart    # Bottom sheet détail
│   │   │   └── widgets/
│   │   │       ├── order_card.dart
│   │   │       └── status_tabs.dart
│   │   ├── products/
│   │   │   ├── products_screen.dart       # FE-18 🔴
│   │   │   ├── create_edit_product_screen.dart  # FE-19 🔴
│   │   │   ├── products_notifier.dart
│   │   │   └── widgets/
│   │   │       └── product_card.dart
│   │   ├── finances/
│   │   │   ├── finance_screen.dart        # FE-20 🟡
│   │   │   └── finance_notifier.dart
│   │   ├── stories/
│   │   │   ├── stories_screen.dart        # FE-21 🟡
│   │   │   └── stories_notifier.dart
│   │   ├── prescriptions/
│   │   │   ├── prescriptions_screen.dart  # FE-22 🔴
│   │   │   └── prescriptions_notifier.dart
│   │   └── become_merchant/
│   │       └── become_merchant_screen.dart # FE-23 🔴
│   └── shared/
│       ├── widgets/
│       │   ├── merchant_bottom_nav.dart   # Tab bar (Home/Commandes/Produits/Finances)
│       │   ├── gradient_header.dart       # Header bleu gradient réutilisable
│       │   ├── image_picker_widget.dart   # Upload photo produit/commerce
│       │   ├── loading_state.dart
│       │   └── error_state.dart
│       └── models/
│           ├── merchant_model.dart        # = Table merchants
│           ├── order_model.dart           # = Table orders + order_items
│           ├── product_model.dart         # = Table products
│           ├── prescription_model.dart    # = Table prescriptions
│           └── notification_model.dart    # = Table notifications
├── pubspec.yaml
└── .env (gitignored)
```

---

## 📦 Dépendances pubspec.yaml (à utiliser)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Supabase
  supabase_flutter: ^2.5.0       # Client Supabase officiel Flutter
  
  # State management
  flutter_riverpod: ^2.5.1       # Recommandé (simple, puissant)
  
  # Navigation
  go_router: ^13.2.0             # Routing déclaratif
  
  # UI / UX
  google_fonts: ^6.2.1           # Sora + Inter
  fl_chart: ^0.68.0              # Graphiques finances (remplace recharts)
  cached_network_image: ^3.3.1   # Images produits depuis Supabase Storage
  image_picker: ^1.1.2           # Upload photo produit
  
  # Utils
  intl: ^0.19.0                  # Formatage dates/monnaie XOF
  timeago: ^3.6.1                # "il y a 5 min"
  flutter_dotenv: ^5.1.0         # Variables d'environnement
```

---

## 🗃️ Tables Supabase utilisées (partie Marchand)

| Table               | Opérations                                              |
|--------------------|---------------------------------------------------------|
| `merchants`         | SELECT (own), UPDATE (is_open, image_url, horaires)    |
| `products`          | SELECT, INSERT, UPDATE, DELETE (merchant_id = own)     |
| `orders`            | SELECT (merchant_id = own), UPDATE (status)            |
| `order_items`       | SELECT (joint avec orders)                             |
| `notifications`     | SELECT (user_id = own), UPDATE (read_at)               |
| `prescriptions`     | SELECT (merchant_id = own), UPDATE (status, devis)     |
| `partner_applications` | INSERT (pour devenir marchand)                      |
| `users_profiles`    | SELECT (own role)                                       |

**Realtime activé sur** : `orders`, `order_items`, `notifications`, `prescriptions`

---

## 🔐 Logique Auth / Rôle

```dart
// Après connexion, vérifier le role dans users_profiles
final profile = await supabase
    .from('users_profiles')
    .select('role')
    .eq('id', userId)
    .single();

// Redirection selon role :
// 'merchant' -> DashboardScreen
// 'client'   -> (autre équipe)
// 'admin'    -> (autre équipe)
// 'delivery' -> (autre équipe)
```

---

## 🔄 Flux Commandes (logique clé)

```
Client passe commande
    -> order.status = 'pending'
    -> Marchand reçoit notification

Marchand accepte avec accept_code
    -> order.status = 'accepted'
    -> Client reçoit notification

Livreur récupère avec pickup_code
    -> order.status = 'in_delivery'

Client confirme avec delivery_code
    -> order.status = 'delivered'
```

**Actions marchand sur une commande :**
```dart
// Accepter
await supabase.from('orders')
    .update({'status': 'accepted', 'merchant_confirmed_at': DateTime.now().toIso8601String()})
    .eq('id', orderId)
    .eq('accept_code', codeInput); // Vérification du code

// Refuser
await supabase.from('orders')
    .update({'status': 'cancelled'})
    .eq('id', orderId);
```

---

## 🎨 Design Tokens (copier le style du React)

```dart
// app_colors.dart
static const primary = Color(0xFF6C4EF2);     // Violet principal (gradient hero)
static const primarySoft = Color(0xFFEDE9FF);
static const warm = Color(0xFFF97316);         // Orange alertes
static const success = Color(0xFF22C55E);      // Vert ouvert
static const card = Colors.white;
static const background = Color(0xFFF8F8FC);

// Gradient header (bg-gradient-hero du React)
static const gradientHero = LinearGradient(
    colors: [Color(0xFF6C4EF2), Color(0xFF8B6BF2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
);
```

**Typographies** : `Sora` (display/titres gras) + `Inter` (body)

---

## 📋 Commandes Flutter utiles

```bash
# Créer le projet
flutter create --org com.nannan --project-name nannan_merchant .

# Lancer en dev
flutter run

# Build APK
flutter build apk --release

# Ajouter une dépendance
flutter pub add supabase_flutter
```

---

## 🚦 Ordre de développement recommandé

1. **Setup** : `main.dart` + Supabase init + `app_theme.dart` + `go_router`
2. **Auth** : `login_screen.dart` + redirection par rôle
3. **Dashboard** (FE-16) : le plus important, vitrail de tout
4. **Orders** (FE-17) : coeur du business, avec Realtime
5. **Products** (FE-18 + FE-19) : CRUD catalogue
6. **Prescriptions** (FE-22) : spécifique pharmacies
7. **Become Merchant** (FE-23) : formulaire onboarding
8. **Finance** (FE-20) : KPIs + graphique barres
9. **Stories** (FE-21) : upload médias

---

## ⚠️ Points critiques à ne pas oublier

- **Bug BE-06** : La fonction `is_admin()` a un problème de permissions RLS. Si tu fais des lectures publiques sur `merchants`, tu pourrais tomber dessus. L'équipe backend doit corriger `GRANT EXECUTE ON FUNCTION is_admin TO anon`.
- **Snapshots commandes** : `order_items.product_name` et `unit_price` sont des snapshots au moment de la commande. Ne jamais join avec `products` pour l'affichage des commandes.
- **Realtime** : S'abonner au channel Supabase dès que l'écran est ouvert, et se désabonner dans le `dispose()`.
- **Images Storage** : Les photos produits sont dans Supabase Storage. Utiliser `supabase.storage.from('products').getPublicUrl(path)` ou des URLs signées pour les prescriptions.

---

## 🤝 Coordination avec les autres équipes

| Équipe     | Ce qu'ils font              | Ce que tu partages avec eux         |
|------------|----------------------------|--------------------------------------|
| Client     | App client (commandes)     | Même Supabase, même `users_profiles` |
| Livreur    | App livreur (missions)     | Même table `orders` (lecture seule)  |
| Admin      | Dashboard admin web        | Même DB, ils valident tes `merchant` |
| Backend    | Migrations SQL, RLS        | Tu dépends de leurs RLS pour tout    |

---

*Document généré le 24/06/2026 — Nan-Nan Connect v1.0*
