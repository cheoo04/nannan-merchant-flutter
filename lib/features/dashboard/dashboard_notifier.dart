// --- Fichier : lib/features/dashboard/dashboard_notifier.dart ---
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../shared/models/models.dart';
import '../orders/orders_repository.dart';
import '../../core/utils/error_message.dart';
import '../../core/services/a_nan_nan_api_client.dart';
import '../../core/services/a_nan_nan_services.dart';
import '../../core/services/neon_session.dart';

class DashboardNotifier extends ChangeNotifier {
  final OrdersRepository _ordersRepo;
  final ANanNanApiClient _api = ANanNanApiClient();
  late final MerchantService _merchantService = MerchantService(_api);

  MerchantModel? merchant;
  List<OrderModel> orders = [];
  bool loadingMerchant = true;
  bool loadingOrders = true;
  String? error;

  DashboardNotifier({OrdersRepository? ordersRepo})
      : _ordersRepo = ordersRepo ?? OrdersRepository() {
    _init();
  }

  Future<void> _init() async {
    await _loadMerchant();
  }

  // ── Merchant ──────────────────────────────────────────────

  Future<void> _loadMerchant() async {
    loadingMerchant = true;
    notifyListeners();

    try {
      final myMerchants = await _merchantService.getMine();
      if (myMerchants.isNotEmpty) {
        final data = myMerchants.first;
        NeonSession.setCurrentMerchant(data);
        merchant = MerchantModel.fromJson(data);
        await _loadOrders(merchant!.id);
      } else {
        merchant = null;
        loadingOrders = false;
      }
      error = null;
    } catch (e) {
      error = friendlyError(e);
      loadingOrders = false;
    } finally {
      loadingMerchant = false;
      notifyListeners();
    }
  }

  // ── Orders ────────────────────────────────────────────────

  Future<void> _loadOrders(String merchantId) async {
    loadingOrders = true;
    notifyListeners();

    try {
      orders = await _ordersRepo.fetchOrders(merchantId);
      error = null;
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loadingOrders = false;
      notifyListeners();
    }
  }

  /// Rechargement manuel (pull-to-refresh)
  Future<void> refresh() async {
    if (merchant == null) {
      await _loadMerchant();
      return;
    }
    try {
      orders = await _ordersRepo.fetchOrders(merchant!.id);
      final refreshedMerchant = await _merchantService.getById(merchant!.id);
      merchant = MerchantModel.fromJson(refreshedMerchant);
      error = null;
      notifyListeners();
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
    }
  }

  // ── KPIs calculés ─────────────────────────────────────────

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
      hour: 0,
      minute: 0,
      second: 0,
      millisecond: 0,
    );
    return orders
        .where((o) =>
            o.status == OrderStatus.delivered &&
            (o.deliveredAt ?? o.createdAt).isAfter(startOfDay))
        .fold(0, (s, o) => s + o.itemsAmount);
  }

  int get revenueWeek {
    final start = DateTime.now().subtract(const Duration(days: 7));
    return orders
        .where((o) =>
            o.status == OrderStatus.delivered &&
            (o.deliveredAt ?? o.createdAt).isAfter(start))
        .fold(0, (s, o) => s + o.itemsAmount);
  }

  int get revenueMonth {
    final start = DateTime.now().subtract(const Duration(days: 30));
    return orders
        .where((o) =>
            o.status == OrderStatus.delivered &&
            (o.deliveredAt ?? o.createdAt).isAfter(start))
        .fold(0, (s, o) => s + o.itemsAmount);
  }

  int get revenueTotal => orders
      .where((o) => o.status == OrderStatus.delivered)
      .fold(0, (s, o) => s + o.itemsAmount);

  int get activeCount => pendingCount + acceptedCount + inDeliveryCount;

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
    if (merchant != null && !merchant!.isOpen) {
      list.add((
        id: 'n3',
        title: 'Votre boutique est fermée',
        body: 'Les clients ne peuvent pas commander',
      ));
    }
    return list.take(3).toList();
  }

  // ── Actions Marchand ──────────────────────────────────────

  Future<void> toggleOpen() async {
    if (merchant == null) return;
    try {
      final newStatus = merchant!.isOpen ? 'closed' : 'active';
      await _api.patch('/api/v1/merchants/${merchant!.id}', body: {
        'status': newStatus,
      });
      await refresh();
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> pauseMerchant(int minutes) async {
    if (merchant == null) return;
    try {
      final until = DateTime.now().add(Duration(minutes: minutes));
      await _api.patch('/api/v1/merchants/${merchant!.id}', body: {
        'settings': {'pause_until': until.toIso8601String()}
      });
      await refresh();
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> resumeMerchant() async {
    if (merchant == null) return;
    try {
      await _api.patch('/api/v1/merchants/${merchant!.id}', body: {
        'settings': {'pause_until': null}
      });
      await refresh();
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> saveSchedule(
      {required bool enabled, String? opening, String? closing}) async {
    if (merchant == null) return;
    try {
      await _api.patch('/api/v1/merchants/${merchant!.id}', body: {
        'settings': {
          'auto_schedule_enabled': enabled,
          'opening_time': enabled ? opening : null,
          'closing_time': enabled ? closing : null,
        }
      });
      await refresh();
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
    }
  }

  Future<void> updateLocation({
    required double lat,
    required double lng,
    String? address,
  }) async {
    if (merchant == null) return;
    try {
      await _merchantService.update(
        merchant!.id,
        latitude: lat,
        longitude: lng,
        address: address,
      );
      await refresh();
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateImage(String? imageUrl) async {
    if (merchant == null) return;
    await _merchantService.update(merchant!.id, logoUrl: imageUrl);
    await refresh();
  }

  Future<String?> uploadShopImage(File file) async {
    if (merchant == null) return null;
    try {
      final bytes = await file.readAsBytes();
      final ext = file.path.split('.').last.toLowerCase();
      final filename = 'cover_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final url = await _api.uploadFile(
        bytes: bytes,
        filename: filename,
        folder: 'merchants',
      );

      await updateImage(url);
      return url;
    } catch (e) {
      error = friendlyError(e);
      notifyListeners();
      return null;
    }
  }
}
