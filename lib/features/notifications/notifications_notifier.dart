// --- Fichier : lib/features/notifications/notifications_notifier.dart ---
import 'package:flutter/foundation.dart';
import '../../shared/models/models.dart';
import '../../core/utils/error_message.dart';
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

  int get unreadCount => notifications.where((n) => n.isUnread).length;

  List<NotificationRow> get filtered => filter == NotificationFilter.unread
      ? notifications.where((n) => n.isUnread).toList()
      : notifications;

  NotificationsNotifier() {
    _init();
  }

  Future<void> _init() async {
    await load();
  }

  Future<void> load() async {
    try {
      final rows = await _service.list(limit: 100);
      notifications = rows
          .map((e) => NotificationRow.fromJson(e as Map<String, dynamic>))
          .toList();
      error = null;
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
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
}
