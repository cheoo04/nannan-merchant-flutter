import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// ⚠️ STUB TEMPORAIRE — mis de côté le 30/06/2026.
///
/// La vraie implémentation (avec badge temps réel + écran complet) a été
/// déplacée dans `_set_aside/notifications/` car ce périmètre (FE-14,
/// "Notifications") est assigné à la personne qui fait la partie Client
/// dans le tableau de répartition des tâches — pas à la partie Marchand.
///
/// Ce stub garde la cloche visible (même position/taille que l'originale)
/// mais désactive l'action tant que l'équipe n'a pas décidé d'une
/// implémentation commune partagée entre tous les rôles (cf. discussion :
/// au lieu d'avoir N implémentations différentes, une seule vivra dans un
/// module partagé une fois l'app fusionnée).
///
/// Pour remettre la vraie cloche en place :
///   1. Restaurer `_set_aside/notifications/widgets/notification_bell_button.dart`
///      à cet emplacement (ou adopter la version retenue par l'équipe).
///   2. Restaurer `_set_aside/notifications/notifications_notifier.dart`
///      et `notifications_screen.dart` dans `lib/features/notifications/`.
///   3. Ré-instancier `NotificationsNotifier` dans `main.dart` (MerchantShell).
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
      label: 'Notifications (à venir)',
      button: true,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
        child: Icon(Icons.notifications_none_rounded, color: iconColor.withOpacity(0.6), size: 20),
      ),
    );
  }
}
