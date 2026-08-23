import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'pin_keypad.dart';
import 'pin_storage.dart';

/// Saisie du PIN pour déverrouiller une session déjà valide (Supabase reste
/// connecté en arrière-plan — ce n'est pas une ré-authentification, juste un
/// verrou local, comme Wave).
///
/// [onUnlocked] est appelé après un code correct. [onForgotPin] est appelé
/// si le marchand ne se souvient plus de son code (efface le PIN local et
/// doit repasser par email/mot de passe pour en redéfinir un nouveau —
/// impossible de redonner l'ancien PIN oublié).
class PinEntryScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onUnlocked;
  final VoidCallback onForgotPin;

  const PinEntryScreen({
    super.key, required this.userId, required this.onUnlocked, required this.onForgotPin,
  });

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  static const _length = 4;
  late final _pinStorage = PinStorage(userId: widget.userId);

  String _entry = '';
  bool _error = false;
  bool _checking = false;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _refreshLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final seconds = await _pinStorage.remainingLockoutSeconds();
    if (!mounted) return;
    setState(() => _lockoutSeconds = seconds);
    if (seconds > 0) {
      // Calculé une seule fois puis décompté localement — pas de lecture du
      // secure storage à chaque tick, seulement au démarrage du compte à rebours.
      final endTime = DateTime.now().add(Duration(seconds: seconds));
      _lockoutTimer?.cancel();
      _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final remaining = endTime.difference(DateTime.now()).inSeconds;
        setState(() => _lockoutSeconds = remaining > 0 ? remaining : 0);
        if (remaining <= 0) _lockoutTimer?.cancel();
      });
    }
  }

  void _onDigit(String digit) {
    if (_checking || _lockoutSeconds > 0 || _entry.length >= _length) return;
    setState(() {
      _error = false;
      _entry += digit;
    });
    if (_entry.length == _length) _submit();
  }

  void _onBackspace() {
    if (_checking || _lockoutSeconds > 0 || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _checking = true);
    final result = await _pinStorage.verifyPin(_entry);
    if (!mounted) return;
    switch (result) {
      case PinVerifyResult.correct:
        widget.onUnlocked();
        return;
      case PinVerifyResult.incorrect:
        setState(() {
          _error = true;
          _entry = '';
          _checking = false;
        });
        break;
      case PinVerifyResult.locked:
        setState(() { _entry = '';
          _checking = false;
        });
        await _refreshLockout();
    }
  }

  Future<void> _confirmForgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Code PIN oublié',
            style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700)),
        content: const Text(
            'Vous allez devoir vous reconnecter avec votre email et votre mot de passe pour définir un nouveau code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuer',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _pinStorage.clearPin();
      if (mounted) widget.onForgotPin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final locked = _lockoutSeconds > 0;
    return Scaffold(
      // Même raison que pin_setup_screen.dart — pas de TextField système,
      // on ignore l'inset clavier transitoire pour éviter le débordement
      // furtif pendant les transitions (connexion, retour d'arrière-plan).
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: top + 40, left: 24, right: 24),
          child: Column(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.primary),
              const SizedBox(height: 20),
              const Text('Entrez votre code PIN',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                locked
                    ? 'Trop de tentatives — réessayez dans ${_lockoutSeconds}s'
                    : (_error ? 'Code incorrect, réessayez.' : 'Espace marchand A Nan-Nan'),
                style: TextStyle(
                    fontSize: 13,
                    color: (_error || locked) ? AppColors.destructive : AppColors.mutedForeground),
              ),
              const SizedBox(height: 40),
              PinDots(length: _length, filled: _entry.length, error: _error),
              const Spacer(),
              PinKeypad(onDigit: _onDigit, onBackspace: _onBackspace, enabled: !locked && !_checking),
              const SizedBox(height: 16),
              TextButton(
                onPressed: locked ? null : _confirmForgotPin,
                child: const Text('Code PIN oublié ?',
                    style: TextStyle(color: AppColors.mutedForeground, fontSize: 13)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
