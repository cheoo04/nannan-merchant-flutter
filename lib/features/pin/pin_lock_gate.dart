import 'package:flutter/material.dart';

import 'pin_entry_screen.dart';

/// Enveloppe [child] (typiquement `MerchantShell`) avec un verrou PIN qui se
/// réactive à chaque retour depuis l'arrière-plan — comme Wave.
///
/// [child] reste monté en permanence, même verrouillé : ses notifiers
/// (Realtime, etc.) continuent de tourner derrière l'écran PIN plutôt que
/// d'être détruits/recréés à chaque verrouillage. L'écran PIN est juste un
/// calque opaque par-dessus tant que [_locked] est vrai.
class PinLockGate extends StatefulWidget {
  final Widget child;
  /// true : démarre verrouillé (cas normal — retour à froid avec PIN déjà
  /// configuré). false : démarre déverrouillé (juste après une connexion ou
  /// une configuration de PIN réussie — pas besoin de le redemander aussitôt).
  final bool startLocked;
  /// Appelé si le marchand a oublié son code — doit remonter jusqu'à
  /// afficher LoginScreen (email/mot de passe) pour repartir à zéro.
  final VoidCallback onForgotPin;

  const PinLockGate({
    super.key,
    required this.child,
    required this.onForgotPin,
    this.startLocked = true,
  });

  @override
  State<PinLockGate> createState() => _PinLockGateState();
}

class _PinLockGateState extends State<PinLockGate> with WidgetsBindingObserver {
  late bool _locked = widget.startLocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reverrouille dès que l'app quitte le premier plan — pas de délai de
    // grâce, comme Wave. hasPin() est toujours vrai ici puisque PinLockGate
    // n'existe que pour un marchand ayant déjà configuré son PIN.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (mounted && !_locked) setState(() => _locked = true);
    }
  }

  Future<void> _onUnlocked() async {
    if (mounted) setState(() => _locked = false);
  }

  Future<void> _onForgotPin() async {
    // PinStorage.clearPin() déjà fait dans PinEntryScreen avant cet appel.
    widget.onForgotPin();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: PinEntryScreen(onUnlocked: _onUnlocked, onForgotPin: _onForgotPin),
          ),
      ],
    );
  }
}
