import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'pin_keypad.dart';
import 'pin_storage.dart';

/// Configuration obligatoire du PIN — affiché juste après la première
/// connexion (email/mot de passe), avant d'entrer dans l'espace marchand.
/// Deux étapes : saisie, puis confirmation (doivent correspondre).
///
/// [onDone] est appelé une fois le PIN enregistré ; c'est à l'appelant de
/// naviguer ensuite vers l'espace marchand (ce widget ne connaît pas
/// `MerchantShell` pour rester découplé).
class PinSetupScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onDone;

  const PinSetupScreen({super.key, required this.userId, required this.onDone});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  static const _length = 4;

  String _firstPin = '';
  String _entry = '';
  bool _confirming = false;
  bool _error = false;
  bool _saving = false;

  void _onDigit(String digit) {
    if (_saving || _entry.length >= _length) return;
    setState(() {
      _error = false;
      _entry += digit;
    });
    if (_entry.length == _length) _onComplete();
  }

  void _onBackspace() {
    if (_saving || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _onComplete() async {
    if (!_confirming) {
      // Fin de la 1ère saisie → passe à la confirmation
      setState(() {
        _firstPin = _entry;
        _entry = '';
        _confirming = true;
      });
      return;
    }
    // Fin de la confirmation
    if (_entry != _firstPin) {
      setState(() {
        _error = true;
        _entry = '';
        _confirming = false;
        _firstPin = '';
      });
      return;
    }
    setState(() => _saving = true);
    await PinStorage(userId: widget.userId).setPin(_entry);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return PopScope(
      // Étape obligatoire — pas de retour arrière possible vers Login tant
      // que ce n'est pas terminé.
      canPop: false,
      child: Scaffold(
        // Pas de TextField ici (clavier custom PinKeypad) — on ignore
        // l'inset clavier, sinon un débordement furtif flashe pendant la
        // transition depuis le formulaire email/mot de passe (dont le
        // clavier système finit de se fermer en même temps que cet écran
        // apparaît).
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(top: top + 24, left: 24, right: 24),
            child: Column(
              children: [
                const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.primary),
                const SizedBox(height: 20),
                Text(
                  _confirming ? 'Confirmez votre code PIN' : 'Créez votre code PIN',
                  style: const TextStyle(
                      fontFamily: 'Sora', fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _error
                      ? 'Les deux codes ne correspondent pas.\nRecommençons depuis le début.'
                      : (_confirming
                          ? 'Répétez le même code pour vous assurer\nde ne pas vous être trompé.'
                          : 'Choisissez 4 chiffres dont vous vous souviendrez —\nvous en aurez besoin à chaque ouverture de l\'app.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: _error ? AppColors.destructive : AppColors.mutedForeground),
                ),
                const SizedBox(height: 40),
                PinDots(length: _length, filled: _entry.length, error: _error),
                const Spacer(),
                PinKeypad(onDigit: _onDigit, onBackspace: _onBackspace, enabled: !_saving),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
