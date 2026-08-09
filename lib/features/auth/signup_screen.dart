import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/ci_phone.dart';
import '../../core/utils/error_message.dart';
import '../become_merchant/become_merchant_screen.dart';

SupabaseClient get _db => Supabase.instance.client;

// ── SIGNUP SCREEN ─────────────────────────────────────────────────────────
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final phone = CiPhone.normalize(_phone.text);
    final email = _email.text.trim();
    final password = _password.text;

    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Veuillez entrer votre nom complet');
      return;
    }
    if (!CiPhone.isValid(phone)) {
      setState(() => _error = 'Numéro invalide. Format attendu : 01 02 03 04 05');
      return;
    }
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Adresse email invalide');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 6 caractères');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      final authEmail = email.isNotEmpty ? email : placeholderEmailForPhone(phone);

      // Le téléphone est passé en métadonnées : le trigger handle_new_user
      // (côté base) lit raw_user_meta_data->>'phone' pour préremplir
      // users_profiles.phone dès l'insertion, sans dépendre uniquement de
      // l'upsert de secours ci-dessous.
      final res = await _db.auth.signUp(
        email: authEmail,
        password: password,
        data: {'phone': phone, 'name': name},
      );
      final userId = res.user?.id;
      if (userId == null) throw Exception('Création du compte échouée');

      // upsert : au cas où un trigger côté base créerait déjà une ligne
      // users_profiles vide à la création du compte auth.
      // Pas de `role` fourni volontairement — la valeur par défaut de la
      // colonne s'applique (à vérifier après un premier test réel).
      await _db.from('users_profiles').upsert({
        'id': userId,
        'name': name,
        'phone': phone,
        'email': email.isNotEmpty ? email : null,
      });

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BecomeMerchantScreen(
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = friendlyError(e));
    } catch (e) {
      setState(() => _error = friendlyError(e,
          fallback:
              'Erreur de connexion. Vérifiez votre connexion internet et réessayez.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: AppColors.gradientHero,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(40),
                  bottomRight: Radius.circular(40),
                ),
              ),
              padding: EdgeInsets.fromLTRB(24, top + 32, 24, 32),
              width: double.infinity,
              child: Column(
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.store_rounded, color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Créer un compte',
                    style: TextStyle(color: Colors.white, fontSize: 22,
                        fontWeight: FontWeight.w700, fontFamily: 'Sora'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Devenez partenaire A Nan-Nan',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel(text: 'Nom complet'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(
                      hint: 'Ex: Yah Mardochée Kouakou',
                      icon: Icons.person_outline_rounded,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const _FieldLabel(text: 'Numéro de téléphone'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration(
                      hint: '01 02 03 04 05',
                      icon: Icons.phone_outlined,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const _FieldLabel(text: 'Adresse email (optionnel)'),
                  const SizedBox(height: 2),
                  const Text(
                    "Utile pour récupérer votre mot de passe en cas d'oubli.",
                    style: TextStyle(fontSize: 11, color: AppColors.mutedForeground),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputDecoration(
                      hint: 'votre@email.com',
                      icon: Icons.mail_outline_rounded,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const _FieldLabel(text: 'Mot de passe'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: _inputDecoration(
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      suffix: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        child: Icon(
                          _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: AppColors.mutedForeground, size: 18,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  const _FieldLabel(text: 'Confirmer le mot de passe'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: _inputDecoration(
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 14, color: AppColors.destructive),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(fontSize: 12, color: AppColors.destructive)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity, height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signup,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Créer mon compte',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text.rich(
                        TextSpan(
                          text: 'Déjà un compte ? ',
                          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground),
                          children: [
                            TextSpan(
                              text: 'Se connecter',
                              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.mutedForeground),
      prefixIcon: Icon(icon, color: AppColors.mutedForeground, size: 18),
      suffixIcon: suffix,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      filled: true, fillColor: AppColors.card,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: AppColors.mutedForeground, letterSpacing: 0.8),
  );
}
