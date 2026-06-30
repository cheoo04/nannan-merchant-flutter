import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/models/models.dart';
import 'notifications_notifier.dart';

// Port fidèle de _app.notifications.tsx (React).
// Placé dans _set_aside/ car FE-14 est côté Client, pas Marchand.
// À déplacer dans lib/features/notifications/ quand la partie Client
// sera construite.

// Équivalent de ICONS (React)
({IconData icon, Color color, Color bg}) _iconForType(String type) {
  switch (type) {
    case 'order':
      return (
        icon: Icons.shopping_bag_rounded,
        color: AppColors.primary,
        bg: AppColors.primarySoft,
      );
    case 'delivery':
      return (
        icon: Icons.two_wheeler_rounded,
        color: AppColors.warm,
        bg: AppColors.warm.withOpacity(0.2),
      );
    case 'payment':
      return (
        icon: Icons.credit_card_rounded,
        color: const Color(0xFF047857), // emerald-700
        bg: const Color(0xFFD1FAE5),    // emerald-100
      );
    default:
      return (
        icon: Icons.shield_rounded,
        color: const Color(0xFF1D4ED8), // blue-700
        bg: const Color(0xFFDBEAFE),    // blue-100
      );
  }
}

// Équivalent de LABELS (React)
String _labelForType(String type) {
  switch (type) {
    case 'order':    return 'Commande';
    case 'delivery': return 'Livraison';
    case 'payment':  return 'Paiement';
    default:         return 'Système';
  }
}

// Port exact de timeAgo() React (mêmes seuils, mêmes libellés)
String _timeAgo(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  final m = diff.inMinutes;
  if (m < 1)  return "à l'instant";
  if (m < 60) return 'il y a $m min';
  final h = diff.inHours;
  if (h < 24) return 'il y a $h h';
  return 'il y a ${diff.inDays} j';
}

class NotificationsScreen extends StatefulWidget {
  final NotificationsNotifier notifier;
  final VoidCallback onGoToOrders; // navigate({ to: "/orders" })

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

  void _handleTap(NotificationRow n) {
    if (n.isUnread) _n.markAsRead(n.id);
    if (n.orderId != null) {
      Navigator.of(context).maybePop();
      widget.onGoToOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items  = _n.filtered;
    final unread = _n.unreadCount;
    final all    = _n.notifications;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Header row (= ligne bouton retour + titre + CheckCheck) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bouton retour — bg-card shadow-card, 40×40 (h-10 w-10)
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Titre + sous-titre (unread count ou "Tout est à jour ✨")
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Notifications',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Sora')),
                        Text(
                          unread > 0
                              ? '$unread non lue${unread > 1 ? "s" : ""}'
                              : 'Tout est à jour ✨',
                          style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  // Bouton CheckCheck — désactivé si unread == 0
                  GestureDetector(
                    onTap: unread > 0 ? () => _n.markAllAsRead() : null,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Icon(
                        Icons.done_all_rounded, // = CheckCheck
                        size: 20,
                        color: unread > 0 ? AppColors.primary : AppColors.mutedForeground.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Filtres pleine largeur en grid-cols-2 (= React) ──────────
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    _FilterTab(
                      // "Toutes · 5"
                      label: 'Toutes · ${all.length}',
                      selected: _n.filter == NotificationFilter.all,
                      onTap: () => _n.setFilter(NotificationFilter.all),
                    ),
                    _FilterTab(
                      // "Non lues · 2"
                      label: 'Non lues · $unread',
                      selected: _n.filter == NotificationFilter.unread,
                      onTap: () => _n.setFilter(NotificationFilter.unread),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Liste ────────────────────────────────────────────────────
              Expanded(
                child: _n.loading
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: AppColors.card.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text('Chargement…',
                              style: TextStyle(fontSize: 14, color: AppColors.mutedForeground)),
                        ),
                      )
                    : items.isEmpty
                        ? _EmptyState(
                            unreadOnly: _n.filter == NotificationFilter.unread,
                            onBack: () => Navigator.of(context).maybePop(),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) => _NotificationTile(
                              n: items[i],
                              onTap: () => _handleTap(items[i]),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _FilterTab : pleine largeur dans un Row, actif = bg-card shadow ──────────
class _FilterTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

// ── _NotificationTile ─────────────────────────────────────────────────────────
class _NotificationTile extends StatelessWidget {
  final NotificationRow n;
  final VoidCallback onTap;
  const _NotificationTile({required this.n, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRead = !n.isUnread;
    final meta   = _iconForType(n.type);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(12), // p-3
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16), // rounded-2xl
          border: !isRead
              ? Border.all(color: AppColors.primary.withOpacity(0.3), width: 1) // ring-1 ring-primary/30
              : Border.all(color: Colors.transparent, width: 1),
          boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icône (40×40, rounded-xl)
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: meta.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(meta.icon, size: 20, color: meta.color),
            ),
            const SizedBox(width: 12),
            // Contenu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre + point non-lu
                  Row(
                    children: [
                      Expanded(
                        child: Text(n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      if (!isRead) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                  // Body (line-clamp-2)
                  if (n.body != null && n.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(n.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
                  ],
                  // "COMMANDE · il y a 5 min" — text-[10px] uppercase tracking-wide
                  const SizedBox(height: 4),
                  Text(
                    '${_labelForType(n.type)} · ${_timeAgo(n.createdAt)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _EmptyState ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool unreadOnly;
  final VoidCallback onBack; // = <Link to="/" /> React
  const _EmptyState({required this.unreadOnly, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.card.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.border,
              style: BorderStyle.solid,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_off_rounded, // BellOff
                  size: 32, color: AppColors.mutedForeground),
              const SizedBox(height: 8),
              Text(
                unreadOnly ? 'Aucune notification non lue.' : 'Aucune notification.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 12),
              // Lien "Retour à l'accueil" = <Link to="/" ...>
              GestureDetector(
                onTap: onBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text("Retour à l'accueil",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}