// --- Fichier : lib/features/notifications/notifications_notifier.dart ---
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../shared/models/models.dart';
import '../../core/utils/error_message.dart';
import '../../core/utils/toast.dart';
import '../../core/services/a_nan_nan_api_client.dart';
import '../../core/services/a_nan_nan_services.dart';

enum NotificationFilter { all, unread }

class NotificationsNotifier extends ChangeNotifier {
  final _api = ANanNanApiClient();
  late final _service = NotificationService(_api);

  List<NotificationRow> notifications = [];
  NotificationFilter filter = NotificationFilter.all;
  bool loading = true;
  String? error;
  int _lastKnownUnread = 0;

  Timer? _pollingTimer;

  int get unreadCount => notifications.where((n) => n.isUnread).length;

  List<NotificationRow> get filtered => filter == NotificationFilter.unread
      ? notifications.where((n) => n.isUnread).toList()
      : notifications;

  NotificationsNotifier() {
    _init();
    // Vérification automatique toutes les 15 secondes
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkNewNotifications();
    });
  }

  Future<void> _init() async {
    await load();
    _lastKnownUnread = unreadCount;
  }

  Future<void> load() async {
    try {
      final rows = await _service.list(limit: 100);
      notifications = rows
          .map((e) => NotificationRow.fromJson(e as Map<String, dynamic>))
          .toList();
      _lastKnownUnread = unreadCount;
      error = null;
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Vérifie si de nouvelles notifications sont arrivées sans saturer la connexion
  Future<void> _checkNewNotifications() async {
    try {
      final remoteUnread = await _service.getUnreadCount();
      if (remoteUnread > _lastKnownUnread) {
        // Une nouvelle notification est arrivée !
        await load();
        final latest = notifications.firstOrNull;
        if (latest != null) {
          toast.info(
            latest.title,
            description: latest.body,
          );
        }
      } else if (remoteUnread != unreadCount) {
        await load();
      }
    } catch (_) {}
  }

  void setFilter(NotificationFilter f) {
    filter = f;
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    final idx = notifications.indexWhere((x) => x.id == id);
    if (idx != -1 && notifications[idx].isUnread) {
      final n = notifications[idx];
      notifications[idx] = NotificationRow(
        id: n.id,
        userId: n.userId,
        type: n.type,
        title: n.title,
        body: n.body,
        orderId: n.orderId,
        readAt: DateTime.now(),
        createdAt: n.createdAt,
        orderAcceptCode: n.orderAcceptCode,
        orderTotalAmount: n.orderTotalAmount,
        orderStatus: n.orderStatus,
      );
      _lastKnownUnread = unreadCount;
      notifyListeners();

      try {
        await _service.markAsRead(id);
      } catch (_) {}
    }
  }

  Future<void> markAllAsRead() async {
    final unread = notifications.where((n) => n.isUnread).toList();
    for (final n in unread) {
      await markAsRead(n.id);
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
