import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'core/utils/toast.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dashboard/dashboard_notifier.dart';
import 'features/orders/orders_screen.dart';
import 'features/products/products_screen.dart';
import 'features/finances/finance_screen.dart';
import 'features/prescriptions/prescriptions_screen.dart';
import 'features/stories/stories_screen.dart';
import 'features/become_merchant/become_merchant_screen.dart';
import 'features/auth/signup_screen.dart';
import 'core/utils/ci_phone.dart';
import 'core/services/a_nan_nan_api_client.dart';
import 'features/notifications/notifications_notifier.dart';
import 'features/profile/profile_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'shared/widgets/merchant_bottom_nav.dart';
import 'shared/merchant_category.dart';
import 'features/pin/pin_lock_gate.dart';
import 'features/pin/pin_setup_screen.dart';
import 'features/pin/pin_storage.dart';

Future<void> main() async {
  // Initialiser les données de locale pour intl (DateFormat 'fr_FR')
  // Sans ça : LocaleDataException au premier formatage de date.
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Garde le splash natif (logo) affiché tant qu'on n'a pas explicitement
  // appelé FlutterNativeSplash.remove() — sans ça, le splash natif
  // disparaît dès la première image dessinée par Flutter, qui serait
  // sinon l'écran de chargement générique de _AuthGate (spinner nu sur
  // fond clair) le temps de vérifier la session. Avec preserve(), aucun
  // écran intermédiaire n'est visible : le logo reste jusqu'à ce qu'on
  // sache où rediriger (Login ou MerchantShell).
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await initializeDateFormatting('fr_FR');

  // Barre de statut transparente — rendu immersif
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await Supabase.initialize(
    url: 'https://ilhanzanjduogsmfjmwm.supabase.co',
    publishableKey:
        'sb_publishable_gUzQnBCgVxn_tFlyK9WT5g_MD1X1cCF',
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );

  runApp(const ProviderScope(child: NanNanMerchantApp()));
}

class NanNanMerchantApp extends StatelessWidget {
  const NanNanMerchantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A Nan-Nan — Marchand',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ToastOverlay(child: child ?? const SizedBox()),
      home: const _AuthGate(),
    );
  }
}

// ── GATE AUTH ─────────────────────────────────────────────────────────────────
// ── AUTH GATE ─────────────────────────────────────────────────────────────────
// Vérifie la session + rôle + catégorie du commerce en UNE SEULE passe
// avant de retirer le splash natif. Résultat : MerchantShell reçoit
// isPharmacy dès sa construction → jamais d'état _loadingCategory →
// jamais de skeleton → jamais de flash blanc entre splash et dashboard.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _isMerchant = false;
  bool _isPharmacy = false;
  bool _needsPinSetup = false;
  bool _hasPin = false;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session != null) {
      _userId = session.user.id;
      try {
        // Requête unique : role + catégorie du commerce en parallèle
        final results = await Future.wait([
          client
              .from('users_profiles')
              .select('role')
              .eq('id', session.user.id)
              .maybeSingle(),
          client
              .from('merchants')
              .select('category')
              .eq('owner_id', session.user.id)
              .maybeSingle(),
        ]);
        _isMerchant = results[0]?['role'] == 'merchant';
        _isPharmacy = categoryNeedsPrescriptionFlow(
            results[1]?['category'] as String?);
        if (_isMerchant) {
          final pinStorage = PinStorage(userId: session.user.id);
          _hasPin = await pinStorage.hasPin();
          // Keystore local vide (reset, Keystore purgé par l'OEM...) : on
          // tente une restauration depuis la copie de secours avant de
          // forcer une reconfiguration complète du PIN.
          if (!_hasPin) {
            _hasPin = await pinStorage.restoreFromRemote();
          }
          _needsPinSetup = !_hasPin;
        }
      } catch (_) {
        // Erreur réseau : ne jamais rester bloqué — retour vers Login.
        _isMerchant = false;
        _isPharmacy = false;
      }
    }
    if (mounted) setState(() => _checking = false);
    // Splash retiré seulement ici : on a déjà tout ce qu'il faut pour
    // afficher directement le bon écran sans aucun état intermédiaire.
    FlutterNativeSplash.remove();
  }

  @override
  Widget build(BuildContext context) {
    // Pendant _checking : splash natif toujours visible (preserve() actif)
    // → ce Scaffold ne s'affiche jamais à l'écran.
    if (_checking) return const SizedBox.shrink();
    if (!_isMerchant) return const LoginScreen();
    // PIN pas encore configuré (compte marchand, session valide) —
    // configuration obligatoire avant d'entrer, jamais de saut d'étape.
    if (_needsPinSetup) {
      return PinSetupScreen(
        userId: _userId!,
        onDone: () => setState(() => _needsPinSetup = false),
      );
    }
    // PIN déjà configuré → verrou local par-dessus une session déjà valide,
    // Supabase reste connecté en arrière-plan (voir PinLockGate).
    return PinLockGate(
      userId: _userId!,
      startLocked: true,
      onForgotPin: () => Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      ),
      child: MerchantShell(isPharmacy: _isPharmacy),
    );
  }
}

// ── MERCHANT SHELL ────────────────────────────────────────────────────────────
// Gère la navigation entre les onglets de l'espace marchand.
// Utilise IndexedStack pour garder l'état de chaque onglet en mémoire
// (le realtime reste actif même quand on change d'onglet).
//
// La barre est DYNAMIQUE selon le métier (voir MerchantBottomNav.tabsFor) :
//   - Tout commerçant : Dashboard / Commandes / Produits / Finances (4 onglets)
//   - Pharmacie en plus : Ordonnances, insérée avant Finances (5 onglets)
// Ne jamais recoder un index en dur ici : utiliser MerchantBottomNav.indexFor.
//
// "Stories / Publications" n'est plus un onglet (usage occasionnel) : c'est
// une sous-page ouverte en push depuis le Dashboard, avec retour au tap arrière.
class MerchantShell extends StatefulWidget {
  // isPharmacy résolu dans _AuthGate avant le remove() du splash —
  // MerchantShell n'a donc jamais à charger quoi que ce soit avant
  // de s'afficher : zéro état intermédiaire, zéro flash.
  final bool isPharmacy;
  const MerchantShell({super.key, required this.isPharmacy});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  int _index = 0;
  bool _showBecomeMerchant = false;

  bool get _isPharmacy => widget.isPharmacy;

  // Une seule instance partagée par tous les onglets — une seule
  // souscription realtime pour toute l'app (voir commentaire dans
  // NotificationsNotifier). Le badge "non lus" de chaque cloche et l'écran
  // complet des notifications lisent tous cette même instance.
  late final NotificationsNotifier _notifications;

  // Même principe : une seule instance de DashboardNotifier, partagée entre
  // DashboardScreen et MerchantProfileScreen — le profil affiche les mêmes
  // stats (commandes livrées, en attente, CA total) sans refaire de requête.
  late final DashboardNotifier _dashboard;

  @override
  void initState() {
    super.initState();
    _notifications = NotificationsNotifier();
    _notifications.addListener(_onNotificationsChanged);
    _dashboard = DashboardNotifier();
    _dashboard.addListener(_onDashboardChanged);
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  void _onDashboardChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _notifications.removeListener(_onNotificationsChanged);
    _notifications.dispose();
    _dashboard.removeListener(_onDashboardChanged);
    _dashboard.dispose();
    super.dispose();
  }

  void _openNotifications() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NotificationsScreen(
        notifier: _notifications,
        onGoToOrders: () => setState(() => _index = MerchantBottomNav.indexFor(
            MerchantTab.orders, isPharmacy: _isPharmacy)),
      ),
    ));
  }

  void _openStories() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoriesScreen(
        onGoToDashboard: () => Navigator.of(context).pop(),
        unreadCount: _notifications.unreadCount,
        onGoToNotifications: _openNotifications,
      ),
    ));
  }

  void _openProfile() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MerchantProfileScreen(
        notifier: _dashboard,
        onSignOut: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        },
        unreadCount: _notifications.unreadCount,
        onGoToNotifications: _openNotifications,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_showBecomeMerchant) {
      return BecomeMerchantScreen(
        onBack: () => setState(() => _showBecomeMerchant = false),
      );
    }

    final ordersIndex = MerchantBottomNav.indexFor(MerchantTab.orders, isPharmacy: _isPharmacy);
    final productsIndex = MerchantBottomNav.indexFor(MerchantTab.products, isPharmacy: _isPharmacy);
    final financeIndex = MerchantBottomNav.indexFor(MerchantTab.finance, isPharmacy: _isPharmacy);
    final prescriptionsIndex = _isPharmacy
        ? MerchantBottomNav.indexFor(MerchantTab.prescriptions, isPharmacy: true)
        : null;

    return IndexedStack(
      index: _index,
      children: [
        // Dashboard — toujours index 0
        DashboardScreen(
          notifier: _dashboard,
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToOrders: () => setState(() => _index = ordersIndex),
          onGoToProducts: () => setState(() => _index = productsIndex),
          onGoToFinance: () => setState(() => _index = financeIndex),
          onGoToStories: _openStories,
          onGoToPrescriptions: prescriptionsIndex == null
              ? () {} // ne devrait jamais être appelé (bouton masqué si non-pharmacie)
              : () => setState(() => _index = prescriptionsIndex),
          unreadCount: _notifications.unreadCount,
          onGoToNotifications: _openNotifications,
          onGoToProfile: _openProfile,
          onGoToBecomesMerchant: () => setState(() => _showBecomeMerchant = true),
        ),

        // Commandes
        OrdersScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: _notifications.unreadCount,
          onGoToNotifications: _openNotifications,
        ),

        // Produits
        ProductsScreen(
          dashboardNotifier: _dashboard,
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: _notifications.unreadCount,
          onGoToNotifications: _openNotifications,
        ),

        // Ordonnances — uniquement pour les pharmacies
        if (_isPharmacy)
          PrescriptionsScreen(
            currentNavIndex: _index,
            onNavTap: (i) => setState(() => _index = i),
            onGoToDashboard: () => setState(() => _index = 0),
            unreadCount: _notifications.unreadCount,
            onGoToNotifications: _openNotifications,
          ),

        // Finances
        FinanceScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: _notifications.unreadCount,
          onGoToNotifications: _openNotifications,
        ),

      ],
    );
  }
}

// ── LOGIN SCREEN ──────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _api = ANanNanApiClient();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() { _phone.dispose(); _pin.dispose(); super.dispose(); }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final phone = CiPhone.normalize(_phone.text);
      await _api.login(phone: phone, pin: _pin.text.trim());
      final me = await _api.me();
      final userId = me['id'] as String;

      // TODO backend : il n'existe pour l'instant aucun endpoint "quel(s)
      // marchand(s) m'appartien(nen)t ?" sur la nouvelle API (contrairement
      // à la requête Supabase ci-dessous qu'on remplace). Le rôle marchand
      // n'est donc pas vérifiable ici pour l'instant — comportement
      // temporaire : tout le monde passe par le formulaire de candidature,
      // comme un compte qui n'a encore rien soumis. Corrigé dès que le
      // backend expose cet endpoint (demandé le 19/09).
      const role = null;
      const isPharmacy = false;
      if (role != 'merchant') {
        // Tout compte non-marchand est redirigé vers le formulaire de
        // candidature — que la personne n'ait encore rien soumis (l'écran
        // affichera le formulaire vierge), soit déjà en attente, soit déjà
        // approuvée. Jamais de blocage sec : sans ça, quelqu'un qui
        // s'inscrit puis abandonne avant de soumettre sa candidature
        // n'aurait plus aucun moyen de revenir sur ce compte.
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BecomeMerchantScreen(
              onBack: () => Navigator.of(context).pop(),
            ),
          ));
        }
        return;
      }

      if (mounted) {
        // PIN déjà configuré (ex: reconnexion après déconnexion volontaire,
        // le PIN survit à un signOut) → verrou direct, pas besoin de le
        // redemander juste après avoir tapé le mot de passe. Sinon,
        // configuration obligatoire avant d'entrer.
        //
        // Important : les callbacks onDone/onForgotPin ci-dessous s'exécutent
        // bien après que cet écran (LoginScreen) ait été remplacé — on utilise
        // donc le `context` de chaque `builder`, pas celui de LoginScreen
        // (qui sera démonté), sinon Navigator.of(context) plante.
        final pinStorage = PinStorage(userId: userId);
        var hasPin = await pinStorage.hasPin();
        if (!hasPin) {
          hasPin = await pinStorage.restoreFromRemote();
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (routeContext) => hasPin
                ? PinLockGate(
                    userId: userId,
                    startLocked: false,
                    onForgotPin: () => Navigator.of(routeContext).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    ),
                    child: const MerchantShell(isPharmacy: isPharmacy),
                  )
                : PinSetupScreen(
                    userId: userId,
                    onDone: () => Navigator.of(routeContext).pushReplacement(
                      MaterialPageRoute(
                        builder: (innerContext) => PinLockGate(
                          userId: userId,
                          startLocked: false,
                          onForgotPin: () => Navigator.of(innerContext).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (_) => false,
                          ),
                          child: const MerchantShell(isPharmacy: isPharmacy),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      }
    } on ANanNanApiException catch (e) {
      setState(() => _error = e.statusCode == 401
          ? 'Numéro ou code PIN incorrect'
          : e.message);
    } catch (e) {
      setState(() => _error =
          'Erreur de connexion. Vérifiez votre connexion internet et réessayez.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header gradient
            Container(
              decoration: const BoxDecoration(
                gradient: AppColors.gradientHero,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              padding: EdgeInsets.fromLTRB(24, top + 48, 24, 48),
              width: double.infinity,
              child: Column(
                children: [
                  // Logo
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.store_rounded, color: AppColors.primary, size: 36),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'A Nan-Nan',
                    style: TextStyle(color: Colors.white, fontSize: 28,
                        fontWeight: FontWeight.w700, fontFamily: 'Sora'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Espace Marchand',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(24, 32, 24, bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Connexion',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                          fontFamily: 'Sora', color: AppColors.foreground)),
                  const SizedBox(height: 4),
                  const Text('Accédez à votre espace marchand',
                      style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
                  const SizedBox(height: 24),

                  // Téléphone
                  const _LoginLabel(text: 'Numéro de téléphone'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '01 02 03 04 05',
                      hintStyle: const TextStyle(color: AppColors.mutedForeground),
                      prefixIcon: const Icon(Icons.phone_outlined,
                          color: AppColors.mutedForeground, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                      filled: true, fillColor: AppColors.card,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Code PIN
                  const _LoginLabel(text: 'Code PIN (4 chiffres)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _pin,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle: const TextStyle(color: AppColors.mutedForeground),
                      prefixIcon: const Icon(Icons.lock_outline_rounded,
                          color: AppColors.mutedForeground, size: 18),
                      suffixIcon: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        child: Icon(
                          _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: AppColors.mutedForeground, size: 18,
                        ),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                      filled: true, fillColor: AppColors.card,
                      counterText: '',
                    ),
                  ),

                  // Erreur
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 14, color: AppColors.destructive),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(fontSize: 12, color: AppColors.destructive)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Bouton connexion
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Se connecter',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Créer un compte
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const SignupScreen(),
                        ));
                      },
                      child: const Text.rich(
                        TextSpan(
                          text: "Pas encore partenaire ? ",
                          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground),
                          children: [
                            TextSpan(
                              text: 'Créer un compte',
                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginLabel extends StatelessWidget {
  final String text;
  const _LoginLabel({required this.text});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: AppColors.mutedForeground, letterSpacing: 0.8),
  );
}