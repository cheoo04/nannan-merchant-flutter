import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'app_router.g.dart';

// Chemins de navigation
abstract class AppRoutes {
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const orders = '/orders';
  static const products = '/products';
  static const createProduct = '/products/create';
  static const editProduct = '/products/edit/:productId';
  static const finance = '/finance';
  static const stories = '/stories';
  static const prescriptions = '/prescriptions';
  static const becomeMerchant = '/become-merchant';
  static const notifications = '/notifications';
}

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final isLogin = state.matchedLocation == AppRoutes.login;

      // Pas connecté → login
      if (session == null) {
        return isLogin ? null : AppRoutes.login;
      }

      // Connecté → vérifier le rôle
      if (isLogin) {
        final profile = await Supabase.instance.client
            .from('users_profiles')
            .select('role')
            .eq('id', session.user.id)
            .single();

        final role = profile['role'] as String?;
        if (role == 'merchant') return AppRoutes.dashboard;
        // Autre rôle = pas autorisé dans cette app
        return null;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const _PlaceholderScreen('Login'),
      ),
      ShellRoute(
        builder: (context, state, child) => _MerchantShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const _PlaceholderScreen('Dashboard'),
          ),
          GoRoute(
            path: AppRoutes.orders,
            builder: (context, state) => const _PlaceholderScreen('Commandes'),
          ),
          GoRoute(
            path: AppRoutes.products,
            builder: (context, state) => const _PlaceholderScreen('Produits'),
          ),
          GoRoute(
            path: AppRoutes.createProduct,
            builder: (context, state) => const _PlaceholderScreen('Créer produit'),
          ),
          GoRoute(
            path: AppRoutes.finance,
            builder: (context, state) => const _PlaceholderScreen('Finances'),
          ),
          GoRoute(
            path: AppRoutes.stories,
            builder: (context, state) => const _PlaceholderScreen('Stories'),
          ),
          GoRoute(
            path: AppRoutes.prescriptions,
            builder: (context, state) => const _PlaceholderScreen('Ordonnances'),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.becomeMerchant,
        builder: (context, state) => const _PlaceholderScreen('Devenir Marchand'),
      ),
    ],
  );
}

/// Shell avec la bottom nav bar marchand
class _MerchantShell extends StatelessWidget {
  final Widget child;
  const _MerchantShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _MerchantBottomNav(),
    );
  }
}

class _MerchantBottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // TODO: remplacer par le vrai widget MerchantBottomNav
    return BottomNavigationBar(
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Commandes'),
        BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Produits'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Finances'),
      ],
    );
  }
}

/// Placeholder temporaire pendant le développement
class _PlaceholderScreen extends StatelessWidget {
  final String name;
  const _PlaceholderScreen(this.name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Text('🚧 $name — À coder', style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
