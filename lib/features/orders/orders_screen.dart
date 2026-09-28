import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';
import '../../shared/widgets/notification_bell_button.dart';
import '../../shared/widgets/skeleton.dart';
import 'orders_notifier.dart';
import '../../shared/models/models.dart';
import '../../core/services/neon_session.dart';

class OrdersScreen extends StatefulWidget {
  final VoidCallback onGoToDashboard;
  final int unreadCount;
  final VoidCallback? onGoToNotifications;
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;

  const OrdersScreen({
    super.key,
    required this.onGoToDashboard,
    this.unreadCount = 0,
    this.onGoToNotifications,
    required this.currentNavIndex,
    required this.onNavTap,
  });

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late final OrdersNotifier _notifier;

  static const _tabs = [
    (id: 'all', label: 'Toutes'),
    (id: 'pending', label: 'Nouvelles'),
    (id: 'accepted', label: 'En cours'),
    (id: 'in_delivery', label: 'En livraison'),
    (id: 'delivered', label: 'Livrées'),
    (id: 'cancelled', label: 'Annulées'),
  ];

  @override
  void initState() {
    super.initState();
    _notifier = OrdersNotifier();
    _notifier.addListener(_onUpdate);
  }

  void _onUpdate() => setState(() {});

  @override
  void dispose() {
    _notifier.removeListener(_onUpdate);
    _notifier.dispose();
    super.dispose();
  }

  Future<void> _handleRefuse(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Refuser cette commande ?',
          style: TextStyle(
              fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: const Text(
          'Le client sera notifié de l\'annulation.',
          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: const Text('Confirmer le refus',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final err = await _notifier.refuseOrder(orderId);
    if (err != null) {
      toast.error(err);
    } else {
      toast.success('Commande refusée');
    }
  }

  Future<void> _handleAccept(String orderId) async {
    final err = await _notifier.acceptOrder(orderId);
    if (err != null) {
      toast.error(err);
    } else {
      toast.success('Commande acceptée : en préparation');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _OrdersHeader(
            topPadding: top,
            onBack: widget.onGoToDashboard,
            unreadCount: widget.unreadCount,
            onNotifications: widget.onGoToNotifications,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final tab = _tabs[i];
                final active = _notifier.activeTab == tab.id;
                final count = _notifier.counts[tab.id] ?? 0;
                return GestureDetector(
                  onTap: () => _notifier.setTab(tab.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: active ? AppColors.primary : AppColors.border),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2))
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${tab.label} · $count',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppColors.foreground,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListenableBuilder(
              listenable: _notifier,
              builder: (context, _) {
                final visible = _notifier.visibleOrders;

                if (_notifier.loading) {
                  return const SkeletonList(
                    count: 3,
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 100),
                  );
                }

                if (!_notifier.loading && visible.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _notifier.refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                            height: MediaQuery.of(context).size.height * 0.22),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Container(
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_rounded,
                                      size: 36,
                                      color: AppColors.mutedForeground),
                                  SizedBox(height: 12),
                                  Text(
                                    'Aucune commande dans cette section',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.foreground),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Tirez vers le bas pour actualiser à tout moment.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.mutedForeground),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _notifier.refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      final order = visible[i];
                      return _OrderCard(
                        order: order,
                        notifier: _notifier,
                        onRefuse: () => _handleRefuse(order.id),
                        onAccept: () => _handleAccept(order.id),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: MerchantBottomNav(
        currentIndex: widget.currentNavIndex,
        onTap: widget.onNavTap,
        isPharmacy: NeonSession.isPharmacy,
      ),
    );
  }
}

class _OrdersHeader extends StatelessWidget {
  final double topPadding;
  final VoidCallback onBack;
  final int unreadCount;
  final VoidCallback? onNotifications;

  const _OrdersHeader({
    required this.topPadding,
    required this.onBack,
    this.unreadCount = 0,
    this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.gradientHero,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                      color: AppColors.headerOverlay, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              if (onNotifications != null)
                NotificationBellButton(
                    unreadCount: unreadCount, onTap: onNotifications!),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Commandes',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFamily: 'Sora'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Gestion en direct des préparations et retraits coursier.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatefulWidget {
  final OrderModel order;
  final OrdersNotifier notifier;
  final VoidCallback onRefuse;
  final VoidCallback onAccept;

  const _OrderCard({
    required this.order,
    required this.notifier,
    required this.onRefuse,
    required this.onAccept,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  List<OrderItemModel> _items = [];

  @override
  void initState() {
    super.initState();
    widget.notifier.fetchItems(widget.order.id).then((items) {
      if (mounted) setState(() => _items = items);
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final isBusy = widget.notifier.busyOrderId == o.id;
    final shortId = o.id.length >= 8
        ? o.id.substring(0, 8).toUpperCase()
        : o.id.toUpperCase();
    final timeStr = formatTime(o.createdAt);

    final commentText = o.clientComment?.trim() ?? '';
    final addressText = o.deliveryAddressText?.trim() ?? '';
    final isDuplicate = commentText.isNotEmpty &&
        addressText.isNotEmpty &&
        commentText.toLowerCase() == addressText.toLowerCase();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.6),
        boxShadow: const [
          BoxShadow(
              color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#$shortId',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'Sora',
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedForeground,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    _StatusChip(status: o.status),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            size: 14, color: AppColors.mutedForeground),
                        const SizedBox(width: 4),
                        Text(
                          o.paymentMethod,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedForeground,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      formatXOF(o.itemsAmount),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Sora',
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                else
                  ..._items.map((it) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.secondary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${it.qty}x',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.foreground),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                it.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.foreground),
                              ),
                            ),
                            Text(
                              formatXOF(it.subtotal),
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.foreground),
                            ),
                          ],
                        ),
                      )),
                if (commentText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warmSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.warm.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.mode_comment_outlined,
                            size: 14, color: AppColors.warm),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            commentText,
                            style: const TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: AppColors.foreground),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (addressText.isNotEmpty && !isDuplicate) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.mutedForeground),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          addressText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Action Accepter / Refuser (pour les nouvelles commandes)
          if (o.status == OrderStatus.pending) ...[
            Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppColors.border, width: 0.6)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextButton(
                      onPressed: isBusy ? null : widget.onRefuse,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(20))),
                      ),
                      child: const Text('Refuser',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.destructive)),
                    ),
                  ),
                  Container(width: 1, height: 48, color: AppColors.border),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: isBusy ? null : widget.onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                                bottomRight: Radius.circular(20))),
                      ),
                      icon: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded,
                              size: 18, color: Colors.white),
                      label: Text(
                        isBusy ? 'Validation...' : 'Accepter la commande',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Commande acceptée en cours : affichage universel du code retrait pour le coursier
          if (o.status == OrderStatus.accepted) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.inventory_2_rounded,
                          size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'En préparation',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Code retrait : ',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedForeground,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          o.pickupCode,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Sora',
                            color: AppColors.foreground,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (o.status == OrderStatus.inDelivery) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.warmSoft,
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.two_wheeler_rounded,
                      size: 18, color: AppColors.warm),
                  SizedBox(width: 8),
                  Text(
                    'Prise en charge par le coursier en route vers le client',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warm),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final OrderStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      OrderStatus.pending => (AppColors.warmSoft, AppColors.warm, 'À valider'),
      OrderStatus.accepted => (
          AppColors.primarySoft,
          AppColors.primary,
          'En cours'
        ),
      OrderStatus.inDelivery => (
          AppColors.warmSoft,
          AppColors.warm,
          'En livraison'
        ),
      OrderStatus.delivered => (
          const Color(0xFFE8F9EE),
          AppColors.success,
          'Livrée'
        ),
      OrderStatus.cancelled || OrderStatus.refunded => (
          const Color(0xFFFEECEB),
          AppColors.destructive,
          'Annulée'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
