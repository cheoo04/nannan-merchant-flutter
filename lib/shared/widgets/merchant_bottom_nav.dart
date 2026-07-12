import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Barre de navigation marchand — dynamique selon le métier.
///
/// - Tout commerçant : Accueil / Commandes / Produits / Finance (4 onglets).
/// - Pharmacie uniquement : + Ordonnances, inséré avant Finance (5 onglets).
/// - "Stories" n'est PAS un onglet fixe : usage occasionnel, il vit comme
///   action rapide sur le Dashboard (voir _NavCard "Publications").
///
/// Règle produit : jamais plus de 5 onglets dans cette barre.
///
/// Pour éviter tout décalage d'index entre écrans, ne pas coder les indices
/// en dur ailleurs : utiliser [MerchantBottomNav.indexFor].
enum MerchantTab { home, orders, products, prescriptions, finance }

class MerchantBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isPharmacy;

  const MerchantBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.isPharmacy,
  });

  /// Ordre canonique des onglets pour ce type de commerce.
  static List<MerchantTab> tabsFor({required bool isPharmacy}) => [
        MerchantTab.home,
        MerchantTab.orders,
        MerchantTab.products,
        if (isPharmacy) MerchantTab.prescriptions,
        MerchantTab.finance,
      ];

  /// Index à passer à [currentIndex] pour un onglet donné, selon le métier.
  /// Ex: MerchantBottomNav.indexFor(MerchantTab.finance, isPharmacy: true) == 4
  static int indexFor(MerchantTab tab, {required bool isPharmacy}) =>
      tabsFor(isPharmacy: isPharmacy).indexOf(tab);

  static const _iconByTab = <MerchantTab, IconData>{
    MerchantTab.home: Icons.grid_view_rounded,
    MerchantTab.orders: Icons.receipt_long_rounded,
    MerchantTab.products: Icons.inventory_2_rounded,
    MerchantTab.prescriptions: Icons.medication_rounded,
    MerchantTab.finance: Icons.bar_chart_rounded,
  };

  static const _labelByTab = <MerchantTab, String>{
    MerchantTab.home: 'Accueil',
    MerchantTab.orders: 'Cmd',
    MerchantTab.products: 'Produits',
    MerchantTab.prescriptions: 'Ord.',
    MerchantTab.finance: 'Finance',
  };

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final tabs = tabsFor(isPharmacy: isPharmacy);
    assert(tabs.length <= 5, 'MerchantBottomNav ne doit jamais dépasser 5 onglets');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(0.95),
        border: const Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000), // shadow-tab
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: bottomPadding, // safe area
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
          // touch target min 44pt
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
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}