import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Cloche de notifications avec badge — identique sur les 6 écrans marchand
/// pour garantir la cohérence visuelle. Dimensions calquées exactement sur
/// le bouton d'origine du Dashboard (_HeaderIconButton) : 44×44, icône 20,
/// badge à right:6/top:6.
class NotificationBellButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;
  final Color iconColor;
  final Color backgroundColor;

  const NotificationBellButton({
    super.key,
    required this.unreadCount,
    required this.onTap,
    this.iconColor = Colors.white,
    this.backgroundColor = AppColors.headerOverlay,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Notifications',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
              child: Icon(Icons.notifications_rounded, color: iconColor, size: 20),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: AppColors.warm, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}