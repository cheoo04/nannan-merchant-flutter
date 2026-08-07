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
