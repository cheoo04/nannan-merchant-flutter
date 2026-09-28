// --- Fichier : lib/shared/widgets/merchant_bottom_nav.dart ---
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/neon_session.dart';

enum MerchantTab { home, orders, products, prescriptions, finance, profile }

class MerchantBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool? isPharmacy;

  const MerchantBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isPharmacy,
  });

  // Immunité absolue : si la session est une pharmacie, la barre a TOUJOURS 5 onglets
  bool get _resolvedIsPharmacy => isPharmacy == true || NeonSession.isPharmacy;

  static List<MerchantTab> tabsFor({required bool isPharmacy}) => [
        MerchantTab.home,
        MerchantTab.orders,
        MerchantTab.products,
        if (isPharmacy) MerchantTab.prescriptions,
        MerchantTab.finance,
      ];

  static int indexFor(MerchantTab tab, {required bool isPharmacy}) =>
      tabsFor(isPharmacy: isPharmacy).indexOf(tab);

  static const _iconByTab = <MerchantTab, IconData>{
    MerchantTab.home: Icons.grid_view_rounded,
    MerchantTab.orders: Icons.receipt_long_rounded,
    MerchantTab.products: Icons.inventory_2_rounded,
    MerchantTab.prescriptions: Icons.medication_rounded,
    MerchantTab.finance: Icons.bar_chart_rounded,
    MerchantTab.profile: Icons.person_rounded,
  };

  static const _labelByTab = <MerchantTab, String>{
    MerchantTab.home: 'Accueil',
    MerchantTab.orders: 'Cmd',
    MerchantTab.products: 'Produits',
    MerchantTab.prescriptions: 'Ord.',
    MerchantTab.finance: 'Finance',
    MerchantTab.profile: 'Profil',
  };

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final tabs = tabsFor(isPharmacy: _resolvedIsPharmacy);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: bottomPadding,
          top: 6,
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _NavItem(
                icon: _iconByTab[tabs[i]]!,
                label: _labelByTab[tabs[i]]!,
                active: currentIndex == i,
                onTap: () => onTap(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.mutedForeground;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: color,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: color, // S'allume en bleu vif quand actif !
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
