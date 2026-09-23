// --- Fichier : lib/main.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
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
import 'core/services/a_nan_nan_services.dart';
import 'core/services/neon_session.dart';
import 'features/notifications/notifications_notifier.dart';
import 'features/profile/profile_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'shared/widgets/merchant_bottom_nav.dart';
import 'features/pin/pin_lock_gate.dart';
import 'features/pin/pin_setup_screen.dart';
import 'features/pin/pin_storage.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await initializeDateFormatting('fr_FR');

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

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
      builder: (context, child) =>
          ToastOverlay(child: child ?? const SizedBox()),
      home: const _AuthGate(),
    );
  }
}

// ── AUTH GATE MIGREE VERS NEON ────────────────────────────────────────────────
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _isLoggedIn = false;
  bool _isApprovedMerchant = false;
  bool _isPharmacy = false;
  bool _needsPinSetup = false;
  String? _userId;

  final _api = ANanNanApiClient();

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final loggedIn = await _api.isLoggedIn;
      if (loggedIn) {
        _isLoggedIn = true;
        final me = await _api.me();
        _userId = me['id'] as String;

        final myMerchants = await MerchantService(_api).getMine();
        if (myMerchants.isNotEmpty) {
          final myMerchant = myMerchants.first;
          final status = myMerchant['status'] as String? ?? 'pending';

          if (status == 'active') {
            NeonSession.setCurrentMerchant(myMerchant);
            _isApprovedMerchant = true;

            final bType =
                (myMerchant['business_type'] as String?)?.toLowerCase();
            _isPharmacy = bType == 'pharmacie' || bType == 'pharmacy';

            final pinStorage = PinStorage(userId: _userId!);
            final hasPin = await pinStorage.hasPin();
            _needsPinSetup = !hasPin;
          } else {
            // Boutique en cours d'examen
            _isApprovedMerchant = false;
          }
        } else {
          _isApprovedMerchant = false;
        }
      } else {
        _isLoggedIn = false;
      }
    } catch (_) {
      _isLoggedIn = false;
    }

    if (mounted) setState(() => _checking = false);
    FlutterNativeSplash.remove();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const SizedBox.shrink();

    // 1. Non connecté -> Login
    if (!_isLoggedIn) return const LoginScreen();

    // 2. Connecté mais pas encore de boutique approuvée -> Écran d'attente
    if (!_isApprovedMerchant) {
      return BecomeMerchantScreen(
        startAtPending: true,
        onBack: () => setState(() => _isLoggedIn = false),
      );
    }

    // 3. Marchand approuvé mais PIN pas encore défini
    if (_needsPinSetup) {
      return PinSetupScreen(
        userId: _userId!,
        onDone: () => setState(() => _needsPinSetup = false),
      );
    }

    // 4. Marchand approuvé avec PIN -> Shell Marchand sécurisé
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
class MerchantShell extends StatefulWidget {
  final bool isPharmacy;
  const MerchantShell({super.key, required this.isPharmacy});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  int _index = 0;
  bool _showBecomeMerchant = false;

  bool get _isPharmacy => widget.isPharmacy;

  late final NotificationsNotifier _notifications;
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
            MerchantTab.orders,
            isPharmacy: _isPharmacy)),
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

    final ordersIndex =
        MerchantBottomNav.indexFor(MerchantTab.orders, isPharmacy: _isPharmacy);
    final productsIndex = MerchantBottomNav.indexFor(MerchantTab.products,
        isPharmacy: _isPharmacy);
    final financeIndex = MerchantBottomNav.indexFor(MerchantTab.finance,
        isPharmacy: _isPharmacy);
    final prescriptionsIndex = _isPharmacy
        ? MerchantBottomNav.indexFor(MerchantTab.prescriptions,
            isPharmacy: true)
        : null;

    return IndexedStack(
      index: _index,
      children: [
        DashboardScreen(
          notifier: _dashboard,
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToOrders: () => setState(() => _index = ordersIndex),
          onGoToProducts: () => setState(() => _index = productsIndex),
          onGoToFinance: () => setState(() => _index = financeIndex),
          onGoToStories: _openStories,
          onGoToPrescriptions: prescriptionsIndex == null
              ? () {}
              : () => setState(() => _index = prescriptionsIndex),
          unreadCount: _notifications.unreadCount,
          onGoToNotifications: _openNotifications,
          onGoToProfile: _openProfile,
          onGoToBecomesMerchant: () =>
              setState(() => _showBecomeMerchant = true),
        ),
        OrdersScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: _notifications.unreadCount,
          onGoToNotifications: _openNotifications,
        ),
        ProductsScreen(
          dashboardNotifier: _dashboard,
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: _notifications.unreadCount,
          onGoToNotifications: _openNotifications,
        ),
        if (_isPharmacy)
          PrescriptionsScreen(
            currentNavIndex: _index,
            onNavTap: (i) => setState(() => _index = i),
            onGoToDashboard: () => setState(() => _index = 0),
            unreadCount: _notifications.unreadCount,
            onGoToNotifications: _openNotifications,
          ),
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
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final phone = CiPhone.normalize(_phone.text);
      await _api.login(phone: phone, pin: _pin.text.trim());
      final me = await _api.me();
      final userId = me['id'] as String;

      final myMerchants = await MerchantService(_api).getMine();
      final myMerchant = myMerchants.isNotEmpty ? myMerchants.first : null;
      final status = myMerchant?['status'] as String? ?? 'pending';

      // Si pas de boutique ou boutique pas encore active -> Directement écran d'attente
      if (myMerchant == null || status != 'active') {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => BecomeMerchantScreen(
                startAtPending: true,
                onBack: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
              ),
            ),
          );
        }
        return;
      }

      // Boutique validée -> Accès complet
      NeonSession.setCurrentMerchant(myMerchant);
      final bType = (myMerchant['business_type'] as String?)?.toLowerCase();
      final isPharmacy = bType == 'pharmacie' || bType == 'pharmacy';

      if (mounted) {
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
                    onForgotPin: () =>
                        Navigator.of(routeContext).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (_) => false,
                    ),
                    child: MerchantShell(isPharmacy: isPharmacy),
                  )
                : PinSetupScreen(
                    userId: userId,
                    onDone: () => Navigator.of(routeContext).pushReplacement(
                      MaterialPageRoute(
                        builder: (innerContext) => PinLockGate(
                          userId: userId,
                          startLocked: false,
                          onForgotPin: () =>
                              Navigator.of(innerContext).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                            (_) => false,
                          ),
                          child: MerchantShell(isPharmacy: isPharmacy),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      }
    } on ANanNanApiException catch (e) {
      setState(() => _error =
          e.statusCode == 401 ? 'Numéro ou code PIN incorrect' : e.message);
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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.store_rounded,
                        color: AppColors.primary, size: 36),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'A Nan-Nan',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Sora'),
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
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Sora',
                          color: AppColors.foreground)),
                  const SizedBox(height: 4),
                  const Text('Accédez à votre espace marchand',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.mutedForeground)),
                  const SizedBox(height: 24),
                  const _LoginLabel(text: 'Numéro de téléphone'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '01 02 03 04 05',
                      hintStyle:
                          const TextStyle(color: AppColors.mutedForeground),
                      prefixIcon: const Icon(Icons.phone_outlined,
                          color: AppColors.mutedForeground, size: 18),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2)),
                      filled: true,
                      fillColor: AppColors.card,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _LoginLabel(text: 'Code PIN (4 chiffres)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _pin,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle:
                          const TextStyle(color: AppColors.mutedForeground),
                      prefixIcon: const Icon(Icons.lock_outline_rounded,
                          color: AppColors.mutedForeground, size: 18),
                      suffixIcon: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        child: Icon(
                          _obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: AppColors.mutedForeground,
                          size: 18,
                        ),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide:
                              const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2)),
                      filled: true,
                      fillColor: AppColors.card,
                      counterText: '',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.destructive)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Se connecter',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                          style: TextStyle(
                              fontSize: 13, color: AppColors.mutedForeground),
                          children: [
                            TextSpan(
                              text: 'Créer un compte',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700),
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
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.mutedForeground,
            letterSpacing: 0.8),
      );
}
