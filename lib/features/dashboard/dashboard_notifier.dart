import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/models.dart';
import '../orders/orders_repository.dart';

SupabaseClient get _db => Supabase.instance.client;

/// ChangeNotifier qui maintient en temps réel :
/// - Le marchand connecté (via owner_id)
/// - Ses commandes (via merchant_id)
/// Se désabonne proprement dans dispose().
class DashboardNotifier extends ChangeNotifier {
  final OrdersRepository _ordersRepo;

  MerchantModel? merchant;
  List<OrderModel> orders = [];
  bool loadingMerchant = true;
  bool loadingOrders = true;
  String? error;

  RealtimeChannel? _merchantChannel;
  RealtimeChannel? _ordersChannel;

  DashboardNotifier({OrdersRepository ordersRepo = const OrdersRepository()})
      : _ordersRepo = ordersRepo {
    _init();
  }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      loadingMerchant = false;
      loadingOrders = false;
      notifyListeners();
      return;
    }

    await _loadMerchant(user.id);
    _subscribeMerchant(user.id);
  }

  // ── Merchant ──────────────────────────────────────────────

  Future<void> _loadMerchant(String userId) async {
    try {
      final data = await _db
          .from('merchants')
          .select()
          .eq('owner_id', userId)
          .maybeSingle();

      merchant = data != null ? MerchantModel.fromJson(data) : null;
      if (merchant != null) {
        await _loadOrders(merchant!.id);
        _subscribeOrders(merchant!.id);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loadingMerchant = false;
      notifyListeners();
    }
  }

  void _subscribeMerchant(String userId) {
    _merchantChannel = _db
        .channel('dashboard-merchant-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'merchants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'owner_id',
            value: userId,
          ),
          callback: (_) => _loadMerchant(userId),
        )
        .subscribe();
  }

  // ── Orders ────────────────────────────────────────────────

  Future<void> _loadOrders(String merchantId) async {
    try {
      orders = await _ordersRepo.fetchOrders(merchantId);
    } catch (e) {
      error = e.toString();
    } finally {
      loadingOrders = false;
      notifyListeners();
    }
  }

  /// Rechargement manuel (pull-to-refresh) — filet de sécurité si le
  /// realtime ne diffuse pas un changement.
  Future<void> refresh() async {
    if (merchant == null) return;
    try {
      orders = await _ordersRepo.fetchOrders(merchant!.id);
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  void _subscribeOrders(String merchantId) {
    _ordersChannel = _ordersRepo.subscribeOrders(
      merchantId: merchantId,
      channelName: 'dashboard-orders-$merchantId',
      onChange: () => _loadOrders(merchantId),
    );
  }

  // ── KPIs calculés (même logique que le React) ─────────────

  int get pendingCount =>
      orders.where((o) => o.status == OrderStatus.pending).length;

  int get acceptedCount =>
      orders.where((o) => o.status == OrderStatus.accepted).length;

  int get inDeliveryCount =>
      orders.where((o) => o.status == OrderStatus.inDelivery).length;

  int get deliveredCount =>
      orders.where((o) => o.status == OrderStatus.delivered).length;

  int get totalCount => orders.length;

  int get revenueDay {
    final startOfDay = DateTime.now().copyWith(
      hour: 0, minute: 0, second: 0, millisecond: 0,
    );
    return orders
        .where((o) =>
            o.status == OrderStatus.delivered &&
            (o.deliveredAt ?? o.createdAt).isAfter(startOfDay))
        .fold(0, (s, o) => s + o.totalAmount);
  }

  int get revenueWeek {
    final start = DateTime.now().subtract(const Duration(days: 7));
    return orders
        .where((o) =>
            o.status == OrderStatus.delivered &&
            (o.deliveredAt ?? o.createdAt).isAfter(start))
        .fold(0, (s, o) => s + o.totalAmount);
  }

  int get revenueMonth {
    final start = DateTime.now().subtract(const Duration(days: 30));
    return orders
        .where((o) =>
            o.status == OrderStatus.delivered &&
            (o.deliveredAt ?? o.createdAt).isAfter(start))
        .fold(0, (s, o) => s + o.totalAmount);
  }

  /// CA total, toutes dates confondues — pour le résumé du profil.
  /// Distinct de revenueDay/Week/Month qui filtrent par période.
  int get revenueTotal => orders
      .where((o) => o.status == OrderStatus.delivered)
      .fold(0, (s, o) => s + o.totalAmount);

  /// Commandes pas encore terminées (ni livrées, ni annulées/remboursées) —
  /// utilisé pour le résumé "en attente" du profil.
  int get activeCount => pendingCount + acceptedCount + inDeliveryCount;

  /// Alertes à afficher (même logique que le React, max 3)
  List<({String id, String title, String body})> get alerts {
    final list = <({String id, String title, String body})>[];
    if (pendingCount > 0) {
      list.add((
        id: 'n1',
        title: '$pendingCount nouvelle(s) commande(s)',
        body: 'À accepter au plus vite',
      ));
    }
    if (acceptedCount > 0) {
      list.add((
        id: 'n2',
        title: '$acceptedCount en attente livreur',
        body: 'Préparez les colis',
      ));
    }
    if (merchant != null && !merchant!.isOpenNow) {
      list.add((
        id: 'n3',
        title: 'Votre boutique est fermée',
        body: 'Les clients ne peuvent pas commander',
      ));
    }
    return list.take(3).toList();
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> toggleOpen() async {
    if (merchant == null) return;
    try {
      final patch = <String, dynamic>{'is_open': !merchant!.isOpen};
      if (!merchant!.isOpen) patch['pause_until'] = null;
      await _db.from('merchants').update(patch).eq('id', merchant!.id);
      // Rechargement explicite — ne pas attendre uniquement le realtime
      final userId = _db.auth.currentUser?.id;
      if (userId != null) await _loadMerchant(userId);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateImage(String? imageUrl) async {
    if (merchant == null) return;
    await _db
        .from('merchants')
        .update({'image_url': imageUrl}).eq('id', merchant!.id);
  }

  /// Upload réel de la photo de commerce vers le bucket 'merchant-images'.
  /// Chemin = $userId/... (pas merchant.id) pour respecter la policy
  /// Storage : (storage.foldername(name))[1] = auth.uid().
  Future<String?> uploadShopImage(File file) async {
    if (merchant == null) return null;
    try {
      final userId = _db.auth.currentUser!.id;
      final ext = file.path.split('.').last.toLowerCase();
      final path = '$userId/cover_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await file.readAsBytes();

      await _db.storage.from('merchant-images').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final url = _db.storage.from('merchant-images').getPublicUrl(path);
      await updateImage(url);
      return url;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ── Dispose ───────────────────────────────────────────────

  @override
  void dispose() {
    if (_merchantChannel != null) _db.removeChannel(_merchantChannel!);
    if (_ordersChannel != null) _ordersRepo.removeChannel(_ordersChannel!);
    super.dispose();
  }
}