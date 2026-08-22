import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Clavier numérique 0-9 + effacer, réutilisé par setup et saisie du PIN.
class PinKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  const PinKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((key) {
              if (key.isEmpty) return const SizedBox(width: 72, height: 60);
              final isBackspace = key == '⌫';
              return _KeypadButton(
                label: key,
                icon: isBackspace ? Icons.backspace_outlined : null,
                enabled: enabled,
                onTap: isBackspace ? onBackspace : () => onDigit(key),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback onTap;

  const _KeypadButton({
    required this.label, this.icon, required this.enabled, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72, height: 60,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Center(
            child: icon != null
                ? Icon(icon, size: 22,
                    color: enabled ? AppColors.foreground : AppColors.mutedForeground)
                : Text(label,
                    style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w600,
                      color: enabled ? AppColors.foreground : AppColors.mutedForeground,
                    )),
          ),
        ),
      ),
    );
  }
}

/// Rangée de points indiquant combien de chiffres ont été saisis sur les 4
/// attendus — utilisée par setup et saisie du PIN.
class PinDots extends StatelessWidget {
  final int length;
  final int filled;
  final bool error;

  const PinDots({super.key, required this.length, required this.filled, this.error = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16, height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: error
                ? AppColors.destructive
                : (isFilled ? AppColors.primary : Colors.transparent),
            border: Border.all(
              color: error ? AppColors.destructive : AppColors.primary,
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}
