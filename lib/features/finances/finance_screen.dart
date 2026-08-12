import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';
import '../../shared/merchant_category.dart';
import '../../shared/widgets/notification_bell_button.dart';
import '../../shared/widgets/skeleton.dart';
import '../../shared/models/models.dart';
import '../orders/orders_repository.dart';

SupabaseClient get _db => Supabase.instance.client;

// ── Notifier ──────────────────────────────────────────────────────────────────
class FinanceNotifier extends ChangeNotifier {
  final OrdersRepository _repo;

  List<OrderModel> orders = [];
  bool loading = true;
  String range = 'week'; // week | month | quarter
  String _merchantCategory = '';
  String? _merchantId;

  // Canal Realtime — même pattern que OrdersNotifier et PrescriptionsNotifier.
  // Finance doit se mettre à jour quand une commande arrive/change de statut
  // (ex: delivered → le CA du jour et le graphique changent immédiatement).
  RealtimeChannel? _channel;

  bool get isPharmacy => categoryNeedsPrescriptionFlow(_merchantCategory);

  FinanceNotifier({OrdersRepository repo = const OrdersRepository()}) : _repo = repo {
    _init();
  }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) { loading = false; notifyListeners(); return; }
    final merchant = await _repo.resolveMerchant(user.id);
    if (merchant == null) { loading = false; notifyListeners(); return; }
    _merchantId = merchant.id;
    _merchantCategory = merchant.category;
    await load();
    _subscribe();
  }

  Future<void> load() async {
    if (_merchantId == null) return;
    orders = await _repo.fetchOrders(_merchantId!);
    loading = false;
    notifyListeners();
  }

  void _subscribe() {
    if (_merchantId == null) return;
    _channel = _repo.subscribeOrders(
      merchantId: _merchantId!,
      channelName: 'finance-merchant-$_merchantId',
      onChange: load,
    );
  }

  @override
  void dispose() {
    if (_channel != null) _repo.removeChannel(_channel!);
    super.dispose();
  }

  void setRange(String r) { range = r; notifyListeners(); }

  List<OrderModel> get delivered =>
      orders.where((o) => o.status == OrderStatus.delivered).toList();

  List<OrderModel> get refunded => orders
      .where((o) => o.status == OrderStatus.cancelled || o.status == OrderStatus.refunded)
      .toList();

  // Données graphique barres — miroir exact du daily du React
  List<({String label, int sales, int count})> get chartData {
    final (days, buckets) = switch (range) {
      'month'   => (30, 4),
      'quarter' => (90, 3),
      _         => (7, 7),
    };

    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final cutoff = nowMs - days * 86400000;
    final bucketMs = (days * 86400000) / buckets;

    // Labels dynamiques basés sur la date réelle — bug fix :
    // les labels Lun→Dim étaient fixes (index 0 = toujours "Lun")
    // alors que le bucket 0 est "il y a 7 jours", pas forcément un lundi.
    final List<String> labels;
    if (range == 'month') {
      labels = ['S1', 'S2', 'S3', 'S4'];
    } else if (range == 'quarter') {
      labels = ['M1', 'M2', 'M3'];
    } else {
      // Pour la semaine : calculer le vrai jour de chaque bucket
      const dayNames = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
      labels = List.generate(7, (i) {
        final bucketCenter = cutoff + (i + 0.5) * bucketMs;
        final day = DateTime.fromMillisecondsSinceEpoch(bucketCenter.toInt()).weekday % 7;
        return dayNames[day]; // weekday: 1=Lun…7=Dim, % 7 → 0=Dim…6=Sam
      });
    }

    final data = List.generate(
      buckets,
      (i) => (label: labels[i], sales: 0, count: 0),
    );

    for (final o in delivered) {
      final ts = (o.deliveredAt ?? o.createdAt).millisecondsSinceEpoch;
      if (ts < cutoff) continue;
      final idx = ((ts - cutoff) / bucketMs).floor().clamp(0, buckets - 1);
      data[idx] = (
        label: data[idx].label,
        // itemsAmount (articles uniquement) — pas totalAmount : la livraison
        // revient au livreur, pas au marchand (pas de commission plateforme).
        sales: data[idx].sales + o.itemsAmount,
        count: data[idx].count + 1,
      );
    }
    return data;
  }

  int get totalSales => chartData.fold(0, (s, d) => s + d.sales);
  int get totalOrders => chartData.fold(0, (s, d) => s + d.count);
  int get refundedTotal => refunded.fold(0, (s, o) => s + o.itemsAmount);
}

// ── FINANCE SCREEN ────────────────────────────────────────────────────────────
class FinanceScreen extends StatefulWidget {
  final VoidCallback onGoToDashboard;
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;
  final int unreadCount;
  final VoidCallback? onGoToNotifications;

  const FinanceScreen({
    super.key,
    required this.onGoToDashboard,
    required this.currentNavIndex,
    required this.onNavTap,
    this.unreadCount = 0,
    this.onGoToNotifications,
  });

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  late final FinanceNotifier _n;

  @override
  void initState() {
    super.initState();
    _n = FinanceNotifier();
    _n.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _n.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _n.load,
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ── HEADER ──────────────────────────────────────
          SliverToBoxAdapter(
            child: _FinanceHeader(
              topPadding: top,
              onBack: widget.onGoToDashboard,
              totalSales: _n.totalSales,
              totalOrders: _n.totalOrders,
              unreadCount: widget.unreadCount,
              onNotifications: widget.onGoToNotifications,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // ── LOADING ─────────────────────────────────────
          if (_n.loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: SkeletonList(count: 3),
              ),
            ),

          // ── ÉTAT VIDE ────────────────────────────────────
          if (!_n.loading && _n.orders.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                  ),
                  child: const Column(children: [
                    Text('Pas encore de ventes enregistrées',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Vos finances s\'afficheront ici dès la première commande livrée.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
                  ]),
                ),
              ),
            ),

          // ── SÉLECTEUR PÉRIODE ────────────────────────────
          if (!_n.loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final (id, label) in [
                      ('week', 'Semaine'),
                      ('month', 'Mois'),
                      ('quarter', 'Trimestre'),
                    ]) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _n.setRange(id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _n.range == id ? AppColors.primary : AppColors.card,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _n.range == id ? AppColors.primary : AppColors.border,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(label,
                                style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: _n.range == id ? Colors.white : AppColors.foreground,
                                )),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── GRAPHIQUE BARRES ─────────────────────────────
          // Affiché systématiquement, même sans données (miroir React :
          // BarChart rendu toujours, le bloc "Pas encore de ventes" est
          // affiché EN PLUS, pas à la place).
          if (!_n.loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FinanceCard(
                  title: 'Ventes par période',
                  child: SizedBox(
                    height: 180,
                    child: _SalesBarChart(data: _n.chartData),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── COMMANDES ANNULÉES/REMBOURSÉES ───────────────
          if (!_n.loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FinanceCard(
                  title: 'Commandes annulées / remboursées',
                  child: _n.refunded.isEmpty
                      ? const Text('Aucune annulation.',
                          style: TextStyle(fontSize: 12, color: AppColors.mutedForeground))
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const Text('Total : ',
                                      style: TextStyle(fontSize: 11, color: AppColors.mutedForeground)),
                                  Text(formatXOF(_n.refundedTotal),
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                          color: AppColors.destructive)),
                                ],
                              ),
                            ),
                            ..._n.refunded.take(10).map((o) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.refresh_rounded, size: 12, color: AppColors.destructive),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('#${o.id.substring(0, 8)}',
                                            style: const TextStyle(fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                        Text(formatDateShort(o.createdAt),
                                            style: const TextStyle(fontSize: 10,
                                                color: AppColors.mutedForeground)),
                                      ],
                                    ),
                                  ),
                                  Text('-${formatXOF(o.itemsAmount)}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                          color: AppColors.destructive)),
                                ],
                              ),
                            )),
                          ],
                        ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── HISTORIQUE PAIEMENTS ─────────────────────────
          if (!_n.loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FinanceCard(
                  title: 'Historique des paiements',
                  child: _n.delivered.isEmpty
                      ? const Text('Aucune vente livrée pour le moment.',
                          style: TextStyle(fontSize: 12, color: AppColors.mutedForeground))
                      : Column(
                    children: _n.delivered.take(20).map((o) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('#${o.id.substring(0, 8)}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                Text(
                                  '${formatDateShort(o.deliveredAt ?? o.createdAt)}'
                                  ' · ${formatTime(o.deliveredAt ?? o.createdAt)}'
                                  ' · ${o.paymentMethod}',
                                  style: const TextStyle(fontSize: 10, color: AppColors.mutedForeground),
                                ),
                              ],
                            ),
                          ),
                          Text(formatXOF(o.itemsAmount),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
        ),
      ),
      bottomNavigationBar: MerchantBottomNav(
          currentIndex: widget.currentNavIndex,
          onTap: widget.onNavTap,
          isPharmacy: _n.isPharmacy),
    );
  }
}

// ── HEADER ────────────────────────────────────────────────────────────────────
class _FinanceHeader extends StatelessWidget {
  final double topPadding;
  final VoidCallback onBack;
  final int totalSales;
  final int totalOrders;
  final int unreadCount;
  final VoidCallback? onNotifications;

  const _FinanceHeader({
    required this.topPadding, required this.onBack,
    required this.totalSales, required this.totalOrders,
    this.unreadCount = 0, this.onNotifications,
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
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: AppColors.headerOverlay, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
              Row(
                children: [
                  if (onNotifications != null)
                    NotificationBellButton(unreadCount: unreadCount, onTap: onNotifications!),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Finances',
              style: TextStyle(color: Colors.white, fontSize: 24,
                  fontWeight: FontWeight.w700, fontFamily: 'Sora')),
          const SizedBox(height: 4),
          const Text('Ventes (articles) et commandes livrées.',
              style: TextStyle(color: Colors.white, fontSize: 12)),
          const SizedBox(height: 16),
          // 2 KPIs — plus de "Net" : pas de commission plateforme, le
          // marchand reçoit directement le montant des articles.
          Row(
            children: [
              Expanded(child: _HeaderKpi(
                icon: Icons.trending_up_rounded,
                label: 'Ventes',
                value: formatXOF(totalSales),
              )),
              const SizedBox(width: 8),
              Expanded(child: _HeaderKpi(
                icon: Icons.receipt_rounded,
                label: 'Commandes',
                value: '$totalOrders',
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderKpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeaderKpi({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.headerOverlay,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 14,
                  fontWeight: FontWeight.w700, fontFamily: 'Sora')),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

// ── GRAPHIQUE BARRES (fl_chart) ───────────────────────────────────────────────
class _SalesBarChart extends StatelessWidget {
  final List<({String label, int sales, int count})> data;

  const _SalesBarChart({required this.data});

  // Format compact pour l'axe Y (ex: 12000 -> "12k") — recharts affiche les
  // valeurs brutes de l'axe sans formatXOF, on reste lisible sur peu d'espace.
  static String _compactXOF(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).round()}k';
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: () {
          if (data.isEmpty) return 1000.0;
          final maxSales = data.map((d) => d.sales.toDouble()).reduce((a, b) => a > b ? a : b);
          if (maxSales <= 0) return 1000.0;
          // Arrondir maxY à un multiple de 500 (ou 1000 si > 5000) pour
          // éviter que fl_chart génère des graduations Y qui se chevauchent.
          final padded = maxSales * 1.25;
          final step = padded > 5000 ? 1000.0 : 500.0;
          return (padded / step).ceil() * step;
        }(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Text(
                _compactXOF(v),
                style: const TextStyle(fontSize: 10, color: AppColors.mutedForeground),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                return Text(data[i].label,
                    style: const TextStyle(fontSize: 10, color: AppColors.mutedForeground));
              },
            ),
          ),
        ),
        barGroups: data.asMap().entries.map((e) => BarChartGroupData(
          x: e.key,
          barRods: [
            BarChartRodData(
              toY: e.value.sales.toDouble(),
              color: AppColors.primary,
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ],
        )).toList(),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              formatXOF(rod.toY.toInt()),
              const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

// ── PETITS WIDGETS ────────────────────────────────────────────────────────────
class _FinanceCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FinanceCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2),
          BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.foreground)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}