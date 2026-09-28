// --- Fichier : lib/features/dashboard/dashboard_notifier.dart ---
import 'dart:async';
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

  Timer? _pollingTimer;

  DashboardNotifier({OrdersRepository? ordersRepo})
      : _ordersRepo = ordersRepo ?? OrdersRepository() {
    _init();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (merchant != null) refresh();
    });
  }

  Future<void> _init() async {
    await _loadMerchant();
  }

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
      debugPrint('[Dashboard] Erreur chargement marchand: $e');
      error = friendlyError(e);
      loadingOrders = false;
    } finally {
      loadingMerchant = false;
      notifyListeners();
    }
  }

  Future<void> _loadOrders(String merchantId) async {
    loadingOrders = true;
    notifyListeners();

    try {
      orders = await _ordersRepo.fetchOrders(merchantId);
      error = null;
    } catch (e) {
      debugPrint('[Dashboard] Erreur chargement commandes: $e');
      error = friendlyError(e);
    } finally {
      loadingOrders = false;
      notifyListeners();
    }
  }

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
      debugPrint('[Dashboard] Erreur refresh: $e');
    }
  }

  // ── Toggle Ouvert/Fermé (Annule définitivement toute pause via pause_until: null) ──
  Future<void> toggleOpen() async {
    if (merchant == null) return;
    try {
      final willBeOpen = !merchant!.isOpen;
      final mId = merchant!.id;

      merchant = merchant!.copyWith(
        isOpen: willBeOpen,
        clearPause: true,
      );
      notifyListeners();

      await _merchantService.update(
        mId,
        isOpen: willBeOpen,
        clearPause: true,
      );

      await refresh();
    } catch (e) {
      debugPrint('[Dashboard] Erreur toggleOpen: $e');
    }
  }

  // ── Mettre en pause ──
  Future<void> pauseMerchant(int minutes) async {
    if (merchant == null) return;
    try {
      final until = DateTime.now().toUtc().add(Duration(minutes: minutes));
      final untilIso = until.toIso8601String();
      final mId = merchant!.id;

      merchant = merchant!.copyWith(
        pauseUntil: untilIso,
      );
      notifyListeners();

      await _merchantService.update(mId, pauseUntil: untilIso);
      await refresh();
    } catch (e) {
      debugPrint('[Dashboard] Erreur pauseMerchant: $e');
    }
  }

  // ── Reprendre maintenant (Lève la pause à 100%) ──
  Future<void> resumeMerchant() async {
    if (merchant == null) return;
    try {
      final mId = merchant!.id;

      merchant = merchant!.copyWith(
        clearPause: true,
        isOpen: true,
      );
      notifyListeners();

      await _merchantService.update(
        mId,
        isOpen: true,
        clearPause: true,
      );

      await refresh();
    } catch (e) {
      debugPrint('[Dashboard] Erreur resumeMerchant: $e');
    }
  }

  Future<void> saveSchedule(
      {required bool enabled, String? opening, String? closing}) async {
    if (merchant == null) return;
    try {
      merchant = merchant!.copyWith(
        autoScheduleEnabled: enabled,
        openingTime: opening,
        closingTime: closing,
      );
      notifyListeners();

      await _merchantService.update(
        merchant!.id,
        autoScheduleEnabled: enabled,
        openingTime: opening,
        closingTime: closing,
      );
      await refresh();
    } catch (e) {
      debugPrint('[Dashboard] Erreur saveSchedule: $e');
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
      debugPrint('[Dashboard] Erreur updateLocation: $e');
      rethrow;
    }
  }

  Future<void> updateImage(String? imageUrl) async {
    if (merchant == null) return;
    try {
      merchant = merchant!.copyWith(imageUrl: imageUrl);
      notifyListeners();
      await _merchantService.update(merchant!.id, logoUrl: imageUrl);
      await refresh();
    } catch (e) {
      debugPrint('[Dashboard] Erreur updateImage: $e');
    }
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
      debugPrint('[Dashboard] Erreur uploadShopImage: $e');
      return null;
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
    final startOfDay =
        DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
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

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
