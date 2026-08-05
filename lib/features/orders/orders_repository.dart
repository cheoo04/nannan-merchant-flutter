import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/models.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Identité minimale du marchand connecté, utilisée par les écrans qui
/// n'ont besoin que de filtrer les commandes (Orders, Finances).
/// Le Dashboard, lui, a besoin du MerchantModel complet et garde sa
/// propre requête — ce n'est pas la même donnée, pas de la duplication.
class MerchantIdentity {
  final String id;
  final String category;
  const MerchantIdentity({required this.id, required this.category});
}

/// Source unique des requêtes Supabase pour l'entité `orders`.
///
/// Avant : orders_notifier.dart, finance_screen.dart et dashboard_notifier.dart
/// construisaient chacun leur propre requête `.from('orders')...`, avec des
/// résultats divergents (seul orders_notifier faisait la jointure
/// `user_addresses` pour récupérer adresse/GPS ; les deux autres non).
///
/// Toute évolution du schéma `orders` (ça a déjà bougé plusieurs fois) se
/// corrige maintenant à un seul endroit.
class OrdersRepository {
  const OrdersRepository();

  /// Résout le marchand (id + catégorie) à partir de l'utilisateur connecté.
  /// Retourne null si l'utilisateur n'a pas de fiche marchand.
  Future<MerchantIdentity?> resolveMerchant(String userId) async {
    final m = await _db
        .from('merchants')
        .select('id, category')
        .eq('owner_id', userId)
        .maybeSingle();
    if (m == null) return null;
    return MerchantIdentity(
      id: m['id'] as String,
      category: (m['category'] as String?) ?? '',
    );
  }

  /// Charge les commandes d'un marchand, toujours avec la jointure adresse
  /// (label/detail/lat/lng résolus via `delivery_address_id`).
  Future<List<OrderModel>> fetchOrders(
    String merchantId, {
    int limit = 200,
  }) async {
    final data = await _db
        .from('orders')
        // Join sur user_addresses via delivery_address_id pour récupérer
        // le texte de l'adresse (label + detail) et les coordonnées GPS.
        .select('*, address:user_addresses!delivery_address_id(label,detail,lat,lng)')
        .eq('merchant_id', merchantId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((e) => OrderModel.fromJson(e)).toList();
  }

  /// Ouvre un channel realtime sur les commandes d'un marchand.
  /// L'appelant est responsable de fermer le channel via [removeChannel].
  RealtimeChannel subscribeOrders({
    required String merchantId,
    required String channelName,
    required void Function() onChange,
  }) {
    return _db
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'merchant_id',
            value: merchantId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  void removeChannel(RealtimeChannel channel) => _db.removeChannel(channel);

  Future<List<OrderItemModel>> fetchOrderItems(String orderId) async {
    final data = await _db
        .from('order_items')
        .select()
        .eq('order_id', orderId)
        .order('created_at');
    return (data as List).map((e) => OrderItemModel.fromJson(e)).toList();
  }

  /// Passe une commande en 'accepted'. `.eq('status', 'pending')` sert de
  /// garde-fou contre un double traitement (deux onglets ouverts, ou
  /// commande déjà traitée entre-temps). Retourne false si rien n'a été mis
  /// à jour (donc déjà traitée).
  Future<bool> acceptOrder(String orderId) async {
    final updated = await _db.from('orders').update({
      'status': 'accepted',
      'merchant_confirmed_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId).eq('status', 'pending').select();
    return (updated as List).isNotEmpty;
  }

  /// Passe une commande en 'cancelled'. Même garde-fou que [acceptOrder].
  Future<bool> refuseOrder(String orderId) async {
    final updated = await _db
        .from('orders')
        .update({'status': 'cancelled'})
        .eq('id', orderId)
        .eq('status', 'pending')
        .select();
    return (updated as List).isNotEmpty;
  }
}
