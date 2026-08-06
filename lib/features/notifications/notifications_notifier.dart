import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/models.dart';

enum NotificationFilter { all, unread }

/// Notifier partagé au niveau de MerchantShell — une seule souscription
/// realtime pour toute l'app, le badge "non lus" et l'écran complet
/// l'utilisent tous les deux depuis cette même instance.
class NotificationsNotifier extends ChangeNotifier {
  final SupabaseClient _db = Supabase.instance.client;
  RealtimeChannel? _channel;

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
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      loading = false;
      notifyListeners();
      return;
    }
    await _load(userId);
    _subscribe(userId);
  }

  Future<void> _load(String userId) async {
    try {
      final rows = await _db
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(200);
      notifications = (rows as List)
          .map((r) => NotificationRow.fromJson(r as Map<String, dynamic>))
          .toList();
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _subscribe(String userId) {
    _channel = _db
        .channel('notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _load(userId),
        )
        .subscribe();
  }

  void setFilter(NotificationFilter f) {
    filter = f;
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    final n = notifications.firstWhere((n) => n.id == id, orElse: () => notifications.first);
    if (!n.isUnread) return;
    // Optimiste : on met à jour localement tout de suite, le realtime
    // confirmera ensuite (ou corrigera si l'update serveur échoue).
    final idx = notifications.indexWhere((x) => x.id == id);
    if (idx != -1) {
      notifications[idx] = NotificationRow(
        id: n.id, userId: n.userId, type: n.type, title: n.title,
        body: n.body, orderId: n.orderId, readAt: DateTime.now(), createdAt: n.createdAt,
      );
      notifyListeners();
    }
    try {
      await _db.from('notifications').update({
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    } catch (_) {
      // pas grave si ça échoue silencieusement, le prochain _load() corrigera
    }
  }

  Future<void> markAllAsRead() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _db
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId)
          .filter('read_at', 'is', null);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }
}