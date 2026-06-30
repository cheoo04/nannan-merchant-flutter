import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'core/utils/toast.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/orders/orders_screen.dart';
import 'features/products/products_screen.dart';
import 'features/finances/finance_screen.dart';
import 'features/prescriptions/prescriptions_screen.dart';
import 'features/stories/stories_screen.dart';
import 'features/become_merchant/become_merchant_screen.dart';
// ⚠️ Notifications mises de côté le 30/06/2026 — voir _set_aside/notifications/
// (périmètre FE-14, assigné à la partie Client, pas Marchand).

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Barre de statut transparente — rendu immersif
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await Supabase.initialize(
    url: 'https://ilhanzanjduogsmfjmwm.supabase.co',
    anonKey:
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
      title: 'Nan-Nan — Marchand',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => ToastOverlay(child: child ?? const SizedBox()),
      home: const _AuthGate(),
    );
  }
}

// ── GATE AUTH ─────────────────────────────────────────────────────────────────
// Vérifie la session Supabase au démarrage.
// Si connecté + rôle merchant → MerchantShell
// Sinon → LoginScreen
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;
  bool _isMerchant = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      try {
        final profile = await Supabase.instance.client
            .from('users_profiles')
            .select('role')
            .eq('id', session.user.id)
            .maybeSingle();
        _isMerchant = profile?['role'] == 'merchant';
      } catch (e) {
        // Erreur réseau/serveur au démarrage : ne jamais rester bloqué sur
        // le spinner — on renvoie vers Login où l'utilisateur peut réessayer.
        _isMerchant = false;
      }
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
        ),
      );
    }
    return _isMerchant ? const MerchantShell() : const LoginScreen();
  }
}

// ── MERCHANT SHELL ────────────────────────────────────────────────────────────
// Gère la navigation entre les 6 onglets de l'espace marchand.
// Utilise IndexedStack pour garder l'état de chaque onglet en mémoire
// (le realtime reste actif même quand on change d'onglet).
//
// Index :
//   0 → Dashboard
//   1 → Commandes
//   2 → Produits
//   3 → Stories / Publications  ← nouveau
//   4 → Ordonnances
//   5 → Finances
class MerchantShell extends StatefulWidget {
  const MerchantShell({super.key});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  int _index = 0;
  bool _showBecomeMerchant = false;

  // ⚠️ Notifications mises de côté le 30/06/2026 — voir _set_aside/notifications/
  // (périmètre FE-14, assigné à la partie Client). En attendant une
  // implémentation partagée par l'équipe, la cloche est un stub désactivé
  // (unreadCount toujours à 0, tap sans effet visible pour le moment).
  void _openNotifications() {
    // No-op volontaire : ne pas ouvrir un écran qui appartient à un autre
    // périmètre. Remettre l'appel à NotificationsScreen une fois la
    // version commune validée par l'équipe.
  }

  @override
  Widget build(BuildContext context) {
    if (_showBecomeMerchant) {
      return BecomeMerchantScreen(
        onBack: () => setState(() => _showBecomeMerchant = false),
      );
    }

    return IndexedStack(
      index: _index,
      children: [
        // 0 — Dashboard
        DashboardScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToOrders: () => setState(() => _index = 1),
          onGoToProducts: () => setState(() => _index = 2),
          onGoToFinance: () => setState(() => _index = 5),
          unreadCount: 0 /* notif mise de côté */,
          onGoToNotifications: _openNotifications,
          onGoToBecomesMerchant: () => setState(() => _showBecomeMerchant = true),
        ),

        // 1 — Commandes
        OrdersScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: 0 /* notif mise de côté */,
          onGoToNotifications: _openNotifications,
        ),

        // 2 — Produits
        ProductsScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: 0 /* notif mise de côté */,
          onGoToNotifications: _openNotifications,
        ),

        // 3 — Stories / Publications
        StoriesScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: 0 /* notif mise de côté */,
          onGoToNotifications: _openNotifications,
        ),

        // 4 — Ordonnances
        PrescriptionsScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          unreadCount: 0 /* notif mise de côté */,
          onGoToNotifications: _openNotifications,
        ),

        // 5 — Finances
        FinanceScreen(
          currentNavIndex: _index,
          onNavTap: (i) => setState(() => _index = i),
          onGoToDashboard: () => setState(() => _index = 0),
          unreadCount: 0 /* notif mise de côté */,
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() { _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      final userId = res.user?.id;
      if (userId == null) throw Exception('Connexion échouée');

      final profile = await Supabase.instance.client
          .from('users_profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      final role = profile?['role'] as String?;
      if (role != 'merchant') {
        await Supabase.instance.client.auth.signOut();
        setState(() => _error = "Ce compte n'est pas un compte marchand.");
        return;
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MerchantShell()),
        );
      }
    } on AuthException catch (_) {
      setState(() => _error = 'Email ou mot de passe incorrect.');
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

                  // Email
                  const _LoginLabel(text: 'Adresse email'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'votre@email.com',
                      hintStyle: const TextStyle(color: AppColors.mutedForeground),
                      prefixIcon: const Icon(Icons.mail_outline_rounded,
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

                  // Mot de passe
                  const _LoginLabel(text: 'Mot de passe'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: '••••••••',
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
                    ),
                  ),

                  // Erreur
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withOpacity(0.1),
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

                  // Devenir marchand
                  Center(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BecomeMerchantScreen(
                            onBack: () => Navigator.of(context).pop(),
                          ),
                        ));
                      },
                      child: const Text.rich(
                        TextSpan(
                          text: "Pas encore partenaire ? ",
                          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground),
                          children: [
                            TextSpan(
                              text: 'Faire une demande',
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