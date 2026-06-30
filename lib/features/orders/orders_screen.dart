import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';
import '../../shared/widgets/notification_bell_button.dart';
import 'orders_notifier.dart';
import '../../shared/models/models.dart';

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
    (id: 'accepted', label: 'Acceptées'),
    (id: 'in_delivery', label: 'En livraison'),
    (id: 'delivered', label: 'Terminées'),
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

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.destructive : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleRefuse(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Refuser cette commande ?',
          style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: const Text(
          'Le client sera notifié et remboursé.',
          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: const Text('Refuser', style: TextStyle(fontWeight: FontWeight.w700)),
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
      toast.success('Commande acceptée');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── HEADER ──────────────────────────────────────
          _OrdersHeader(
            topPadding: top,
            onBack: widget.onGoToDashboard,
            unreadCount: widget.unreadCount,
            onNotifications: widget.onGoToNotifications,
          ),

          // ── ONGLETS ─────────────────────────────────────
          const SizedBox(height: 16),
          SizedBox(
            height: 36,
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : AppColors.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active ? AppColors.primary : AppColors.border,
                      ),
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

          const SizedBox(height: 8),

          // ── LOADING ─────────────────────────────────────
          if (_notifier.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mutedForeground),
                  ),
                  SizedBox(width: 8),
                  Text('Connexion temps réel…',
                      style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
                ],
              ),
            ),

          // ── LISTE COMMANDES ──────────────────────────────
          Expanded(
            child: ListenableBuilder(
              listenable: _notifier,
              builder: (context, _) {
                final visible = _notifier.visibleOrders;

                if (!_notifier.loading && visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.border,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: const Text(
                          'Aucune commande dans cette section.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground),
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final order = visible[i];
                    return _OrderCard(
                      order: order,
                      notifier: _notifier,
                      onRefuse: () => _handleRefuse(order.id),
                      onAcceptSubmit: () => _handleAccept(order.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: MerchantBottomNav(
        currentIndex: widget.currentNavIndex,
        onTap: widget.onNavTap,
      ),
    );
  }
}

// ── HEADER ────────────────────────────────────────────────────────────────────
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
              // Bouton retour — touch target 44×44
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.headerOverlay,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
              Row(
                children: [
                  const Text(
                    'Temps réel',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  if (onNotifications != null) ...[
                    const SizedBox(width: 10),
                    NotificationBellButton(
                      unreadCount: unreadCount,
                      onTap: onNotifications!,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Gestion des commandes',
            style: TextStyle(
              color: Colors.white, fontSize: 24,
              fontWeight: FontWeight.w700, fontFamily: 'Sora',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Suivez chaque commande synchronisée en direct.',
            style: TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

// ── ORDER CARD ────────────────────────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final OrderModel order;
  final OrdersNotifier notifier;
  final VoidCallback onRefuse;
  final VoidCallback onAcceptSubmit;

  const _OrderCard({
    required this.order,
    required this.notifier,
    required this.onRefuse,
    required this.onAcceptSubmit,
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
    final n = widget.notifier;
    final isAccepting = n.acceptingOrderId == o.id;
    final busy = n.busyOrderId == o.id;

    final received = formatTime(o.createdAt);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // ── Corps ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre + montant
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Commande #${o.id.substring(0, 8)}',
                            style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: AppColors.foreground,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'reçue à $received · ${o.paymentMethod}',
                            style: const TextStyle(
                              fontSize: 11, color: AppColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatXOF(o.totalXof),
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Statut + codes
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _StatusChip(status: o.status),
                    // Code accept (pending)
                    if (o.status == OrderStatus.pending)
                      _BadgeChip(
                        icon: Icons.key_rounded,
                        label: 'Code: ${o.acceptCode}',
                        color: AppColors.primary,
                        bg: AppColors.primarySoft,
                      ),
                    // Code pickup (accepted ou in_delivery)
                    if (o.status == OrderStatus.accepted ||
                        o.status == OrderStatus.inDelivery)
                      _BadgeChip(
                        icon: Icons.local_shipping_rounded,
                        label: 'Retrait livreur: ${o.pickupCode}',
                        color: AppColors.warm,
                        bg: AppColors.warmSoft,
                      ),
                  ],
                ),

                // Articles
                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: _items.map((it) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${it.qty}× ${it.productName}',
                              style: const TextStyle(fontSize: 11, color: AppColors.foreground),
                            ),
                            Text(
                              formatXOF(it.subtotal),
                              style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: AppColors.foreground,
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ],

                // Commentaire client
                if (o.clientComment != null && o.clientComment!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warmSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '« ${o.clientComment} »',
                      style: const TextStyle(
                        fontSize: 11, fontStyle: FontStyle.italic,
                        color: AppColors.warm,
                      ),
                    ),
                  ),
                ],

                // Adresse de livraison
                if (o.deliveryAddress != null && o.deliveryAddress!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 12, color: AppColors.mutedForeground),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Livraison: ${o.deliveryAddress}',
                          style: const TextStyle(
                            fontSize: 11, color: AppColors.mutedForeground,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ── Saisie code acceptation ──────────────────────
          if (isAccepting) ...[
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                color: AppColors.primarySoft,
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Saisissez votre code d'acceptation à 4 chiffres :",
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          maxLength: 4,
                          textAlign: TextAlign.center,
                          onChanged: (v) => widget.notifier.setCode(v),
                          decoration: InputDecoration(
                            hintText: '••••',
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700,
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Valider
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: busy || n.codeInput.length != 4
                              ? null
                              : widget.onAcceptSubmit,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white,
                                  ),
                                )
                              : const Text('Valider',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Annuler
                      SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: () => widget.notifier.cancelAccept(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Annuler',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppColors.foreground)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ── Actions pending ──────────────────────────────
          if (o.status == OrderStatus.pending && !isAccepting)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  // Refuser
                  Expanded(
                    child: GestureDetector(
                      onTap: busy ? null : widget.onRefuse,
                      child: Container(
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Color(0x1AEF4444),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close_rounded, size: 16, color: AppColors.destructive),
                            SizedBox(width: 6),
                            Text('Refuser',
                                style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppColors.destructive,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Accepter
                  Expanded(
                    child: GestureDetector(
                      onTap: () => widget.notifier.startAccept(o.id),
                      child: Container(
                        height: 48,
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.only(
                            bottomRight: Radius.circular(20),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text('Accepter',
                                style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Info livreur accepted ────────────────────────
          if (o.status == OrderStatus.accepted)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, size: 12, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'En attente du livreur. Donnez-lui le code ',
                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                        children: [
                          TextSpan(
                            text: o.pickupCode,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: ' lors du retrait.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── PETITS WIDGETS ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final OrderStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      OrderStatus.pending => (const Color(0x40E8854A), AppColors.warm),
      OrderStatus.accepted => (AppColors.primarySoft, AppColors.primary),
      OrderStatus.inDelivery => (const Color(0x40E8854A), AppColors.warm),
      OrderStatus.delivered => (const Color(0x3334A96B), AppColors.success),
      OrderStatus.cancelled || OrderStatus.refunded =>
        (const Color(0x26D94F2A), AppColors.destructive),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

extension on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'En attente',
        OrderStatus.accepted => 'Acceptée',
        OrderStatus.inDelivery => 'En livraison',
        OrderStatus.delivered => 'Livrée',
        OrderStatus.cancelled => 'Annulée',
        OrderStatus.refunded => 'Remboursée',
      };
}

class _BadgeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;

  const _BadgeChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}