import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';
import '../../shared/models/models.dart';

SupabaseClient get _db => Supabase.instance.client;

const _commissionPct = 0.1; // 10% — miroir de COMMISSION_PCT du React

// ── Notifier ──────────────────────────────────────────────────────────────────
class FinanceNotifier extends ChangeNotifier {
  List<OrderModel> orders = [];
  bool loading = true;
  String range = 'week'; // week | month | quarter

  FinanceNotifier() { _init(); }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) { loading = false; notifyListeners(); return; }
    final m = await _db.from('merchants').select('id').eq('owner_id', user.id).maybeSingle();
    if (m == null) { loading = false; notifyListeners(); return; }

    final data = await _db.from('orders').select()
        .eq('merchant_id', m['id'] as String)
        .order('created_at', ascending: false);
    orders = (data as List).map((e) => OrderModel.fromJson(e)).toList();
    loading = false;
    notifyListeners();
  }

  void setRange(String r) { range = r; notifyListeners(); }

  List<OrderModel> get delivered =>
      orders.where((o) => o.status == OrderStatus.delivered).toList();

  List<OrderModel> get refunded => orders
      .where((o) => o.status == OrderStatus.cancelled || o.status == OrderStatus.refunded)
      .toList();

  // Données graphique barres — miroir exact du daily du React
  List<({String label, int sales, int count})> get chartData {
    final (days, buckets, labels) = switch (range) {
      'month' => (30, 4, ['S1', 'S2', 'S3', 'S4']),
      'quarter' => (90, 3, ['M1', 'M2', 'M3']),
      _ => (7, 7, ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']),
    };

    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - days * 86400000;
    final bucketMs = (days * 86400000) / buckets;

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
        sales: data[idx].sales + o.totalXof,
        count: data[idx].count + 1,
      );
    }
    return data;
  }

  int get totalSales => chartData.fold(0, (s, d) => s + d.sales);
  int get totalOrders => chartData.fold(0, (s, d) => s + d.count);
  int get commission => (totalSales * _commissionPct).round();
  int get netRevenue => totalSales - commission;
  int get refundedTotal => refunded.fold(0, (s, o) => s + o.totalXof);
}

// ── FINANCE SCREEN ────────────────────────────────────────────────────────────
class FinanceScreen extends StatefulWidget {
  final VoidCallback onGoToDashboard;
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;

  const FinanceScreen({
    super.key,
    required this.onGoToDashboard,
    required this.currentNavIndex,
    required this.onNavTap,
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
      body: CustomScrollView(
        slivers: [
          // ── HEADER ──────────────────────────────────────
          SliverToBoxAdapter(
            child: _FinanceHeader(
              topPadding: top,
              onBack: widget.onGoToDashboard,
              totalSales: _n.totalSales,
              totalOrders: _n.totalOrders,
              netRevenue: _n.netRevenue,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // ── LOADING ─────────────────────────────────────
          if (_n.loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.mutedForeground)),
                  SizedBox(width: 8),
                  Text('Chargement…', style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
                ]),
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
          if (!_n.loading && _n.orders.isNotEmpty)
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

          // ── DÉTAIL FINANCIER ─────────────────────────────
          if (!_n.loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FinanceCard(
                  title: 'Détail',
                  child: Column(
                    children: [
                      _DetailRow(label: 'Ventes brutes', value: formatXOF(_n.totalSales)),
                      const SizedBox(height: 8),
                      _DetailRow(
                        label: 'Commission plateforme (${(_commissionPct * 100).round()}%)',
                        value: '-${formatXOF(_n.commission)}',
                        muted: true,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(color: AppColors.border, height: 1),
                      ),
                      _DetailRow(
                        label: 'Revenu net',
                        value: formatXOF(_n.netRevenue),
                        primary: true,
                        bold: true,
                      ),
                    ],
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
                                  Text('-${formatXOF(o.totalXof)}',
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
          if (!_n.loading && _n.delivered.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _FinanceCard(
                  title: 'Historique des paiements',
                  child: Column(
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
                          Text(formatXOF(o.totalXof),
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
      bottomNavigationBar: MerchantBottomNav(
          currentIndex: widget.currentNavIndex, onTap: widget.onNavTap),
    );
  }
}

// ── HEADER ────────────────────────────────────────────────────────────────────
class _FinanceHeader extends StatelessWidget {
  final double topPadding;
  final VoidCallback onBack;
  final int totalSales;
  final int totalOrders;
  final int netRevenue;

  const _FinanceHeader({
    required this.topPadding, required this.onBack,
    required this.totalSales, required this.totalOrders, required this.netRevenue,
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
                  decoration: BoxDecoration(color: AppColors.headerOverlay, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
              const Text('Données temps réel',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Finances',
              style: TextStyle(color: Colors.white, fontSize: 24,
                  fontWeight: FontWeight.w700, fontFamily: 'Sora')),
          const SizedBox(height: 4),
          const Text('Ventes, commission plateforme et revenu net.',
              style: TextStyle(color: Colors.white, fontSize: 12)),
          const SizedBox(height: 16),
          // 3 KPIs
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
              const SizedBox(width: 8),
              Expanded(child: _HeaderKpi(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Net',
                value: formatXOF(netRevenue),
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

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: data.isEmpty ? 100 : data.map((d) => d.sales.toDouble()).reduce((a, b) => a > b ? a : b) * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool muted;
  final bool primary;
  final bool bold;

  const _DetailRow({
    required this.label, required this.value,
    this.muted = false, this.primary = false, this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = primary ? AppColors.primary : muted ? AppColors.mutedForeground : AppColors.foreground;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        Text(value, style: TextStyle(fontSize: 12, color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      ],
    );
  }
}
