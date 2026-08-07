import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_colors.dart';

/// Rectangle arrondi simple (couleur pleine) — brique de base des
/// écrans de chargement. Ne s'anime pas tout seul : c'est [SkeletonList]
/// (ou tout parent qui l'englobe) qui applique l'effet shimmer une seule
/// fois pour toute la liste, afin que le balayage soit synchronisé sur
/// tous les éléments plutôt que désynchronisé boîte par boîte.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
    );
  }
}

/// Skeleton d'une carte générique (titre + sous-titre + montant à droite),
/// dimensionné pour ressembler aux cartes commande/produit/transaction
/// réelles de l'app (coins arrondis 20, padding 12).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const SkeletonBox(
            width: 44, height: 44,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(height: 13, width: 140),
                const SizedBox(height: 8),
                SkeletonBox(height: 11, width: MediaQuery.of(context).size.width * 0.35),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBox(width: 60, height: 16),
        ],
      ),
    );
  }
}

/// Skeleton complet du dashboard marchand — reproduit fidèlement
/// le layout réel (header gradient + KPIs + image + nav cards +
/// alertes) pour que le chargement initial soit invisible à l'œil.
/// Utilisé par MerchantShell pendant _loadingCategory.
class DashboardSkeleton extends StatelessWidget {
  final EdgeInsets topPadding;
  const DashboardSkeleton({super.key, required this.topPadding});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            // ── HEADER GRADIENT (fond bleu, pas de shimmer dessus) ──
            Container(
              decoration: const BoxDecoration(
                gradient: AppColors.gradientHero,
                borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(32)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, topPadding.top + 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ligne top : retour + ville + cloche
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 80, height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // "Espace marchand"
                  Container(
                    width: 100, height: 10,
                    color: Colors.white.withOpacity(0.25),
                  ),
                  const SizedBox(height: 6),
                  // Nom du commerce
                  Container(
                    width: 200, height: 22,
                    color: Colors.white.withOpacity(0.35),
                  ),
                  const SizedBox(height: 12),
                  // Badge ouvert/fermé
                  Container(
                    width: 160, height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // KPIs 2×2
                  Row(
                    children: [
                      Expanded(child: _KpiSkeleton()),
                      const SizedBox(width: 8),
                      Expanded(child: _KpiSkeleton()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _KpiSkeleton()),
                      const SizedBox(width: 8),
                      Expanded(child: _KpiSkeleton()),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image du commerce
                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Nav cards (3 boutons)
                    Row(
                      children: List.generate(3, (i) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                          child: Container(
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      )),
                    ),
                    const SizedBox(height: 16),
                    // Alertes
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Bottom nav fantôme
        bottomNavigationBar: Container(
          height: 60,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _KpiSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 60, height: 9,
              color: Colors.white.withOpacity(0.4)),
          const SizedBox(height: 6),
          Container(
              width: 40, height: 20,
              color: Colors.white.withOpacity(0.5)),
        ],
      ),
    );
  }
}

/// Liste de [count] SkeletonCard espacées, shimmer synchronisé sur
/// l'ensemble — à poser directement à la place d'un indicateur de
/// chargement dans une liste (commandes, produits, transactions...).
class SkeletonList extends StatelessWidget {
  final int count;
  final EdgeInsets padding;

  const SkeletonList({super.key, this.count = 4, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border.withOpacity(0.5),
      highlightColor: AppColors.border.withOpacity(0.15),
      child: Padding(
        padding: padding,
        child: Column(
          children: List.generate(count, (i) => Padding(
            padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 10),
            child: const SkeletonCard(),
          )),
        ),
      ),
    );
  }
}
