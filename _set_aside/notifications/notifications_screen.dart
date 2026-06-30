import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/models/models.dart';
import 'notifications_notifier.dart';

class NotificationsScreen extends StatefulWidget {
  final NotificationsNotifier notifier;
  final VoidCallback onGoToOrders;

  const NotificationsScreen({
    super.key,
    required this.notifier,
    required this.onGoToOrders,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsNotifier _n = widget.notifier;

  @override
  void initState() {
    super.initState();
    _n.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _n.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() => setState(() {});

  Future<void> _handleTap(NotificationRow n) async {
    await _n.markAsRead(n.id);
    if (n.orderId != null) {
      if (mounted) Navigator.of(context).pop();
      widget.onGoToOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _n.filtered;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Notifications',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'Sora')),
                  ),
                  if (_n.unreadCount > 0)
                    TextButton(
                      onPressed: () => _n.markAllAsRead(),
                      child: const Text('Tout marquer comme lu', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),

            // ── Filtres ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Toutes',
                    selected: _n.filter == NotificationFilter.all,
                    onTap: () => _n.setFilter(NotificationFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: _n.unreadCount > 0 ? 'Non lues (${_n.unreadCount})' : 'Non lues',
                    selected: _n.filter == NotificationFilter.unread,
                    onTap: () => _n.setFilter(NotificationFilter.unread),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Liste ──────────────────────────────────────────
            Expanded(
              child: _n.loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : items.isEmpty
                      ? _EmptyState(unreadOnly: _n.filter == NotificationFilter.unread)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) => _NotificationTile(
                            notification: items[i],
                            onTap: () => _handleTap(items[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.secondary,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationRow notification;
  final VoidCallback onTap;
  const _NotificationTile({required this.notification, required this.onTap});

  ({IconData icon, Color color}) get _iconForType {
    switch (notification.type) {
      case 'order':
        return (icon: Icons.shopping_bag_rounded, color: AppColors.primary);
      case 'delivery':
        return (icon: Icons.two_wheeler_rounded, color: AppColors.warm);
      case 'payment':
        return (icon: Icons.credit_card_rounded, color: AppColors.success);
      default:
        return (icon: Icons.shield_rounded, color: AppColors.mutedForeground);
    }
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(notification.createdAt);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return DateFormat('dd/MM/yyyy').format(notification.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final style = _iconForType;
    final unread = notification.isUnread;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: unread ? AppColors.primarySoft.withOpacity(0.4) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: style.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, size: 18, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notification.title,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w600)),
                  if (notification.body != null && notification.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(notification.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
                  ],
                  const SizedBox(height: 4),
                  Text(_timeAgo,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.mutedForeground)),
                ],
              ),
            ),
            if (unread)
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool unreadOnly;
  const _EmptyState({required this.unreadOnly});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded, size: 40, color: AppColors.mutedForeground.withOpacity(0.5)),
            const SizedBox(height: 12),
            Text(
              unreadOnly ? 'Aucune notification non lue' : 'Aucune notification pour le moment',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.mutedForeground, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}