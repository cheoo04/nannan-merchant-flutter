import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class AppRoutes {
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const orders = '/orders';
  static const products = '/products';
  static const createProduct = '/products/create';
  static const finance = '/finance';
  static const stories = '/stories';
  static const prescriptions = '/prescriptions';
  static const becomeMerchant = '/become-merchant';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const _PlaceholderScreen('Login'),
      ),
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
      GoRoute(
        path: AppRoutes.becomeMerchant,
        builder: (context, state) => const _PlaceholderScreen('Devenir Marchand'),
      ),
    ],
  );
});

class _PlaceholderScreen extends StatelessWidget {
  final String name;
  const _PlaceholderScreen(this.name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Text('🚧 $name — À coder',
            style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
