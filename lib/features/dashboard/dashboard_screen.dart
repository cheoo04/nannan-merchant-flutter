import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';
import '../../shared/widgets/city_switcher_chip.dart';
import '../../shared/widgets/notification_bell_button.dart';
import 'dashboard_notifier.dart';

class DashboardScreen extends StatefulWidget {
  /// Callbacks de navigation vers les autres onglets
  final VoidCallback onGoToOrders;
  final VoidCallback onGoToProducts;
  final VoidCallback onGoToFinance;
  final VoidCallback onGoToNotifications;
  final int unreadCount;
  final VoidCallback onGoToBecomesMerchant;
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;

  const DashboardScreen({
    super.key,
    required this.onGoToOrders,
    required this.onGoToProducts,
    required this.onGoToFinance,
    required this.onGoToNotifications,
    this.unreadCount = 0,
    required this.onGoToBecomesMerchant,
    required this.currentNavIndex,
    required this.onNavTap,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = DashboardNotifier();
    _notifier.addListener(_onUpdate);
  }

  void _onUpdate() => setState(() {});

  @override
  void dispose() {
    _notifier.removeListener(_onUpdate);
    _notifier.dispose();
    super.dispose();
  }

  // ── Toggle ouvert/fermé ───────────────────────────────────
  Future<void> _handleToggle() async {
    // Lire AVANT le toggle (même logique que le React: !merchant.is_open)
    final wasOpen = _notifier.merchant?.isOpen ?? false;
    await _notifier.toggleOpen();
    if (!mounted) return;
    toast.success(!wasOpen ? 'Boutique ouverte' : 'Boutique fermée');
  }

  @override
  Widget build(BuildContext context) {
    // Insets pour safe area
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) {
          final merchant = _notifier.merchant;
          final isOpen = merchant?.isOpenNow ?? false;
          final statusLabel = merchant?.statusLabel.label ?? '—';
          final merchantName = merchant?.name ?? 'Mon commerce';
          final hasData = _notifier.totalCount > 0;

          return CustomScrollView(
            slivers: [
              // ── HEADER GRADIENT ────────────────────────────
              SliverToBoxAdapter(
                child: _GradientHeader(
                  topPadding: top,
                  merchantName: merchantName,
                  isOpen: isOpen,
                  statusLabel: statusLabel,
                  pendingCount: _notifier.pendingCount,
                  unreadCount: widget.unreadCount,
                  cityCode: merchant?.cityCode ?? 'oume',
                  revenueDay: _notifier.revenueDay,
                  totalCount: _notifier.totalCount,
                  pendingCountKpi: _notifier.pendingCount,
                  deliveredCount: _notifier.deliveredCount,
                  onToggle: _handleToggle,
                  onNotifications: widget.onGoToNotifications,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── PHOTO DU COMMERCE ──────────────────────────
              if (merchant != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ShopImagePicker(
                      imageUrl: merchant.imageUrl,
                      onPick: (file) => _notifier.uploadShopImage(file),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── LOADING ────────────────────────────────────
              if (_notifier.loadingOrders)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Chargement temps réel…',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── ÉTAT VIDE ──────────────────────────────────
              if (!_notifier.loadingOrders && !hasData)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _EmptyOrdersCard(),
                  ),
                ),

              // ── NAV CARDS (Commandes / Produits / Finances) ─
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: _NavCard(
                          icon: Icons.receipt_long_rounded,
                          label: 'Commandes',
                          hint: '${_notifier.pendingCount} new',
                          onTap: widget.onGoToOrders,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _NavCard(
                          icon: Icons.inventory_2_rounded,
                          label: 'Produits',
                          hint: 'Catalogue',
                          onTap: widget.onGoToProducts,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _NavCard(
                          icon: Icons.bar_chart_rounded,
                          label: 'Finances',
                          hint: 'Tendances',
                          onTap: widget.onGoToFinance,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── REVENUS JOUR / SEMAINE / MOIS ──────────────
              if (hasData)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: _RevCard(
                            label: 'Jour',
                            value: _notifier.revenueDay,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RevCard(
                            label: 'Semaine',
                            value: _notifier.revenueWeek,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RevCard(
                            label: 'Mois',
                            value: _notifier.revenueMonth,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── ALERTES ────────────────────────────────────
              if (_notifier.alerts.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _AlertsSection(
                      alerts: _notifier.alerts,
                      onTap: widget.onGoToNotifications,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── INSCRIRE UN NOUVEAU COMMERCE ───────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _RegisterMerchantCard(
                    onTap: widget.onGoToBecomesMerchant,
                  ),
                ),
              ),

              // Espace pour la bottom nav
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      bottomNavigationBar: MerchantBottomNav(
        currentIndex: widget.currentNavIndex,
        onTap: widget.onNavTap,
      ),
    );
  }
}

// ── HEADER GRADIENT ─────────────────────────────────────────────────────────

class _GradientHeader extends StatelessWidget {
  final double topPadding;
  final String merchantName;
  final bool isOpen;
  final String statusLabel;
  final int pendingCount;
  final int unreadCount;
  final String cityCode;
  final int revenueDay;
  final int totalCount;
  final int pendingCountKpi;
  final int deliveredCount;
  final VoidCallback onToggle;
  final VoidCallback onNotifications;

  const _GradientHeader({
    required this.topPadding,
    required this.merchantName,
    required this.isOpen,
    required this.statusLabel,
    required this.pendingCount,
    required this.unreadCount,
    required this.cityCode,
    required this.revenueDay,
    required this.totalCount,
    required this.pendingCountKpi,
    required this.deliveredCount,
    required this.onToggle,
    required this.onNotifications,
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
          // Top row : retour + ville + notifications
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Bouton retour (profil)
              _HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Retour',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              Row(
                children: [
                  CitySwitcherChip(cityCode: cityCode),
                  const SizedBox(width: 8),
                  NotificationBellButton(unreadCount: unreadCount, onTap: onNotifications),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Sous-titre
          const Text(
            'Espace marchand',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 2),

          // Nom du commerce (Sora Bold)
          Text(
            merchantName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.2,
              fontFamily: 'Sora',
            ),
          ),

          const SizedBox(height: 12),

          // Toggle Ouvert / Fermé
          GestureDetector(
            onTap: onToggle,
            child: Container(
              // touch target 44pt
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isOpen ? AppColors.success : AppColors.headerOverlay,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOpen ? Colors.white : AppColors.warm,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$statusLabel · toucher pour changer',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // KPIs 2×2
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'CA du jour',
                  value: formatXOF(revenueDay),
                  small: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiCard(label: 'Commandes', value: '$totalCount'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiCard(label: 'En attente', value: '$pendingCountKpi'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiCard(label: 'Livrées', value: '$deliveredCount'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── PETITS WIDGETS ───────────────────────────────────────────────────────────

/// Bouton icône dans le header (fond blanc/15, touch target 44×44)
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.headerOverlay,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// KPI card dans le header gradient
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _KpiCard({required this.label, required this.value, this.small = false});

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
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: small ? 14 : 20,
              fontWeight: FontWeight.w700,
              fontFamily: 'Sora',
            ),
          ),
        ],
      ),
    );
  }
}

/// Navigation card (Commandes / Produits / Finances)
class _NavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
            BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 16),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
            ),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte revenu Jour/Semaine/Mois
class _RevCard extends StatelessWidget {
  final String label;
  final int value;

  const _RevCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.mutedForeground,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatXOF(value),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              fontFamily: 'Sora',
            ),
          ),
        ],
      ),
    );
  }
}

/// État vide commandes
class _EmptyOrdersCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.access_time_rounded,
            size: 24,
            color: AppColors.mutedForeground,
          ),
          const SizedBox(height: 8),
          const Text(
            'Aucune commande pour le moment',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            "Dès qu'un client commandera, vous le verrez ici en temps réel.",
            style: TextStyle(
              fontSize: 11,
              color: AppColors.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Section alertes
class _AlertsSection extends StatelessWidget {
  final List<({String id, String title, String body})> alerts;
  final VoidCallback onTap;

  const _AlertsSection({required this.alerts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Notifications importantes',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Sora',
            color: AppColors.foreground,
          ),
        ),
        const SizedBox(height: 8),
        ...alerts.map(
          (a) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0A000000), blurRadius: 2),
                    BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.warmSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.notifications_rounded,
                        color: AppColors.warm,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.foreground,
                            ),
                          ),
                          Text(
                            a.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.mutedForeground,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bouton "Inscrire un nouveau commerce"
class _RegisterMerchantCard extends StatelessWidget {
  final VoidCallback onTap;

  const _RegisterMerchantCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.add_rounded,
                color: AppColors.foreground,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inscrire un nouveau commerce',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground,
                    ),
                  ),
                  Text(
                    "Avec ou sans aide d'un livreur sur le terrain",
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.mutedForeground,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sélecteur de photo du commerce
class _ShopImagePicker extends StatefulWidget {
  final String? imageUrl;
  final Future<String?> Function(File file) onPick;

  const _ShopImagePicker({this.imageUrl, required this.onPick});

  @override
  State<_ShopImagePicker> createState() => _ShopImagePickerState();
}

class _ShopImagePickerState extends State<_ShopImagePicker> {
  bool _uploading = false;

  Future<void> _handleTap() async {
    if (_uploading) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1280,
    );
    if (file == null) return;

    setState(() => _uploading = true);
    final url = await widget.onPick(File(file.path));
    if (mounted) setState(() => _uploading = false);

    if (url != null) toast.success('Photo mise à jour');
    else toast.error("Échec de l'envoi de la photo");
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.imageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _handleTap,
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 0.5),
              image: imageUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(imageUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _uploading
                ? const Center(
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : imageUrl == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_rounded,
                            color: AppColors.mutedForeground,
                            size: 28,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Photo de mon commerce',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.mutedForeground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : null,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Cette photo s'affiche aux clients sur la fiche de votre commerce.",
          style: TextStyle(fontSize: 10, color: AppColors.mutedForeground),
        ),
      ],
    );
  }
}