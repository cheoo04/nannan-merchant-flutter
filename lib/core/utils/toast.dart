import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ── Types de toast ────────────────────────────────────────────────────────────
enum ToastType { success, error, info }

// ── Modèle ────────────────────────────────────────────────────────────────────
class _ToastItem {
  final String id;
  final String title;
  final String? description;
  final ToastType type;

  _ToastItem({
    required this.id,
    required this.title,
    this.description,
    required this.type,
  });
}

// ── Manager global (singleton) ────────────────────────────────────────────────
class ToastManager extends ChangeNotifier {
  static final ToastManager _instance = ToastManager._();
  static ToastManager get instance => _instance;
  ToastManager._();

  final List<_ToastItem> _toasts = [];
  List<_ToastItem> get toasts => List.unmodifiable(_toasts);

  void show(String title, {String? description, ToastType type = ToastType.info}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _toasts.insert(0, _ToastItem(id: id, title: title, description: description, type: type));
    notifyListeners();

    // Auto-dismiss après 3s
    Future.delayed(const Duration(milliseconds: 3000), () => dismiss(id));
  }

  void success(String title, {String? description}) =>
      show(title, description: description, type: ToastType.success);

  void error(String title, {String? description}) =>
      show(title, description: description, type: ToastType.error);

  void info(String title, {String? description}) =>
      show(title, description: description, type: ToastType.info);

  void dismiss(String id) {
    _toasts.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}

// ── Shortcuts globaux ─────────────────────────────────────────────────────────
final toast = ToastManager.instance;

// ── Overlay widget — à placer dans le Stack racine de l'app ──────────────────
/// Miroir de <Toaster position="top-center" /> du React
/// Affiche jusqu'à 3 toasts empilés en haut de l'écran
class ToastOverlay extends StatelessWidget {
  final Widget child;
  const ToastOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ToastManager.instance,
      builder: (context, _) {
        final toasts = ToastManager.instance.toasts.take(3).toList();
        final top = MediaQuery.of(context).padding.top;

        return Stack(
          children: [
            child,
            if (toasts.isNotEmpty)
              Positioned(
                top: top + 8,
                left: 16,
                right: 16,
                child: Column(
                  children: toasts.asMap().entries.map((e) {
                    final index = e.key;
                    final t = e.value;
                    // Les toasts du dessous sont légèrement plus petits (effet empilé)
                    final scale = 1.0 - index * 0.04;
                    final opacity = 1.0 - index * 0.15;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topCenter,
                        child: Opacity(
                          opacity: opacity,
                          child: _ToastCard(
                            item: t,
                            onDismiss: () => ToastManager.instance.dismiss(t.id),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Card toast ────────────────────────────────────────────────────────────────
class _ToastCard extends StatelessWidget {
  final _ToastItem item;
  final VoidCallback onDismiss;

  const _ToastCard({required this.item, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final (icon, iconColor) = switch (item.type) {
      ToastType.success => (Icons.check_circle_rounded, AppColors.success),
      ToastType.error   => (Icons.error_rounded,        AppColors.destructive),
      ToastType.info    => (Icons.info_rounded,         AppColors.primary),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          // Fond blanc avec bordure — miroir exact du style sonner React
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
            BoxShadow(color: Color(0x0A000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.foreground,
                    ),
                  ),
                  if (item.description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.description!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Bouton fermer
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
