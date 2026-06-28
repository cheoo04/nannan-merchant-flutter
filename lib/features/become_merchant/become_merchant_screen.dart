import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';

SupabaseClient get _db => Supabase.instance.client;

// ── Catégories marchand (miroir de MERCHANT_CATEGORIES du React) ──────────────
const _categories = [
  (id: 'maquis', label: 'Maquis / Restaurant'),
  (id: 'boulangerie', label: 'Boulangerie'),
  (id: 'boutique', label: 'Boutique / Alimentation'),
  (id: 'gaz', label: 'Recharge bouteilles de gaz'),
  (id: 'pharmacie', label: 'Pharmacie'),
  (id: 'autre', label: 'Autre'),
];

enum _Step { info, terms, pending }

// ── BECOME MERCHANT SCREEN ────────────────────────────────────────────────────
class BecomeMerchantScreen extends StatefulWidget {
  final VoidCallback onBack;

  const BecomeMerchantScreen({super.key, required this.onBack});

  @override
  State<BecomeMerchantScreen> createState() => _BecomeMerchantScreenState();
}

class _BecomeMerchantScreenState extends State<BecomeMerchantScreen> {
  _Step _step = _Step.info;
  bool _existingPending = false;
  bool _existingApproved = false;
  bool _submitting = false;
  bool _checkingExisting = true;

  // Champs étape 1
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController(text: 'Oumé');
  final _address = TextEditingController();
  final _businessName = TextEditingController();
  final _description = TextEditingController();
  String _category = _categories[0].id;

  // Étape 2
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _prefillFromProfile();
    _checkExisting();
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _city.dispose();
    _address.dispose(); _businessName.dispose(); _description.dispose();
    super.dispose();
  }

  Future<void> _prefillFromProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    final profile = await _db
        .from('users_profiles')
        .select('name, phone, email')
        .eq('id', user.id)
        .maybeSingle();
    if (profile != null && mounted) {
      // Préremplissage automatique — miroir de useAuth().profile dans le React
      if ((profile['name'] as String? ?? '').isNotEmpty) {
        _name.text = profile['name'] as String;
      }
      if ((profile['phone'] as String? ?? '').isNotEmpty) {
        _phone.text = profile['phone'] as String;
      }
    }
  }

  Future<void> _checkExisting() async {
    final user = _db.auth.currentUser;
    if (user == null) { setState(() => _checkingExisting = false); return; }
    final apps = await _db.from('partner_applications')
        .select('status')
        .eq('user_id', user.id)
        .eq('type', 'merchant');
    setState(() {
      _checkingExisting = false;
      _existingPending = (apps as List).any((a) => a['status'] == 'pending');
      _existingApproved = apps.any((a) => a['status'] == 'approved');
      if (_existingPending || _existingApproved) _step = _Step.pending;
    });
  }

  // ── Validation étape 1 ────────────────────────────────────
  void _submitInfo() {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      toast.error('Renseignez votre nom et numéro'); return;
    }
    if (_businessName.text.trim().isEmpty) {
      toast.error('Indiquez le nom de votre commerce'); return;
    }
    if (_description.text.trim().isEmpty) {
      toast.error('Ajoutez une description'); return;
    }
    if (_address.text.trim().isEmpty) {
      toast.error("Indiquez l'adresse du commerce"); return;
    }
    setState(() => _step = _Step.terms);
  }

  // ── Soumission finale ─────────────────────────────────────
  Future<void> _submitTerms() async {
    if (!_accepted) { toast.error('Vous devez accepter les conditions'); return; }
    final user = _db.auth.currentUser;
    if (user == null) { toast.error('Connectez-vous'); return; }

    setState(() => _submitting = true);
    try {
      await _db.from('partner_applications').insert({
        'user_id': user.id,
        'type': 'merchant',
        'status': 'pending',
        'payload': {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'city': _city.text.trim(),
          'city_code': 'oume',
          'address': _address.text.trim(),
          'business_name': _businessName.text.trim(),
          'category': _category,
          'description': _description.text.trim(),
        },
      });
      toast.success('Demande envoyée');
      setState(() { _step = _Step.pending; _existingPending = true; });
    } catch (e) {
      toast.error(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    if (_checkingExisting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header sticky (miroir React) ─────────────────
          Container(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 12),
            color: AppColors.background.withOpacity(0.95),
            child: Row(
              children: [
                // Retour
                GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8)],
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Devenir Marchand',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                            fontFamily: 'Sora', color: AppColors.foreground),
                      ),
                      const SizedBox(height: 4),
                      // Stepper 3 barres
                      Row(
                        children: List.generate(3, (i) {
                          final filled = switch (_step) {
                            _Step.info => i == 0,
                            _Step.terms => i <= 1,
                            _Step.pending => true,
                          };
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(right: 3),
                              height: 4,
                              decoration: BoxDecoration(
                                color: filled ? AppColors.primary : AppColors.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.store_rounded, color: AppColors.primary, size: 16),
                ),
              ],
            ),
          ),

          // ── Contenu scrollable ────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).padding.bottom + 24,
              ),
              child: switch (_step) {
                _Step.info => _StepInfo(
                    name: _name, phone: _phone, city: _city,
                    address: _address, businessName: _businessName,
                    description: _description, category: _category,
                    onCategoryChanged: (v) => setState(() => _category = v),
                    onNext: _submitInfo,
                  ),
                _Step.terms => _StepTerms(
                    accepted: _accepted,
                    onAcceptChanged: (v) => setState(() => _accepted = v),
                    onBack: () => setState(() => _step = _Step.info),
                    onSubmit: _submitTerms,
                    submitting: _submitting,
                  ),
                _Step.pending => _StepPending(
                    approved: _existingApproved,
                    onBack: widget.onBack,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── ÉTAPE 1 : INFORMATIONS ────────────────────────────────────────────────────
class _StepInfo extends StatelessWidget {
  final TextEditingController name, phone, city, address, businessName, description;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onNext;

  const _StepInfo({
    required this.name, required this.phone, required this.city,
    required this.address, required this.businessName, required this.description,
    required this.category, required this.onCategoryChanged, required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Étape 1/3 — Informations',
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
        const SizedBox(height: 16),

        _Field(label: 'Nom complet', controller: name, placeholder: 'Aïcha Koné'),
        const SizedBox(height: 12),
        _Field(label: 'Numéro de téléphone', controller: phone,
            placeholder: '+225 07 00 00 00 00', type: TextInputType.phone),
        const SizedBox(height: 12),
        _Field(label: 'Ville', controller: city),
        const SizedBox(height: 12),
        _Field(label: 'Adresse du commerce', controller: address,
            placeholder: 'Quartier, repère'),
        const SizedBox(height: 12),
        _Field(label: 'Nom du commerce', controller: businessName,
            placeholder: 'Chez Tantie Awa'),
        const SizedBox(height: 12),

        // Catégorie — grille 2 colonnes
        const _FieldLabel(text: 'Catégorie'),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8, mainAxisSpacing: 8,
          childAspectRatio: 3.5,
          children: _categories.map((c) {
            final active = category == c.id;
            return GestureDetector(
              onTap: () => onCategoryChanged(c.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.primarySoft : AppColors.card,
                  border: Border.all(
                    color: active ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: active ? null : const [
                    BoxShadow(color: Color(0x0F000000), blurRadius: 8),
                  ],
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: active ? AppColors.primary : AppColors.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // Description
        const _FieldLabel(text: 'Description détaillée'),
        const SizedBox(height: 4),
        TextField(
          controller: description,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Spécialités, horaires, ambiance…',
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.mutedForeground),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 2)),
            filled: true, fillColor: AppColors.card,
          ),
        ),

        const SizedBox(height: 24),

        // Bouton continuer
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('Continuer',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

// ── ÉTAPE 2 : CONDITIONS ──────────────────────────────────────────────────────
class _StepTerms extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onAcceptChanged;
  final VoidCallback onBack;
  final Future<void> Function() onSubmit;
  final bool submitting;

  const _StepTerms({
    required this.accepted, required this.onAcceptChanged,
    required this.onBack, required this.onSubmit, required this.submitting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Étape 2/3 — Conditions d'engagement",
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
        const SizedBox(height: 12),

        // Scroll des conditions
        Container(
          constraints: const BoxConstraints(maxHeight: 340),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: const [
                _Term(
                  title: 'Engagement de service',
                  text: "Je m'engage à respecter les délais, la qualité et la courtoisie envers les clients d'A Nan-Nan.",
                ),
                SizedBox(height: 12),
                _Term(
                  title: 'Commission plateforme',
                  text: "Une commission de 10% est prélevée sur chaque commande livrée via A Nan-Nan.",
                ),
                SizedBox(height: 12),
                _Term(
                  title: 'Données & confidentialité',
                  text: "Mes données personnelles sont utilisées uniquement pour les besoins du service A Nan-Nan.",
                ),
                SizedBox(height: 12),
                _Term(
                  title: 'Validation administrative',
                  text: "Ma demande sera examinée sous 24 à 72h par l'équipe A Nan-Nan avant activation.",
                ),
                SizedBox(height: 12),
                _Term(
                  title: 'Résiliation',
                  text: "Je peux quitter le programme à tout moment depuis mon profil.",
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Checkbox acceptation
        GestureDetector(
          onTap: () => onAcceptChanged(!accepted),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20, height: 20,
                  child: Checkbox(
                    value: accepted,
                    onChanged: (v) => onAcceptChanged(v ?? false),
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "J'ai lu et j'accepte les conditions ci-dessus pour devenir marchand.",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                        color: AppColors.foreground),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Boutons retour + soumettre
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Retour',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.foreground)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: submitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: submitting
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Soumettre',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── ÉTAPE 3 : PENDING ─────────────────────────────────────────────────────────
class _StepPending extends StatelessWidget {
  final bool approved;
  final VoidCallback onBack;

  const _StepPending({required this.approved, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
            ),
            child: Column(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.access_time_rounded,
                      color: AppColors.primary, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  approved ? 'Demande déjà acceptée !' : 'Votre demande est en cours d\'examen',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                      fontFamily: 'Sora', color: AppColors.foreground),
                ),
                const SizedBox(height: 8),
                Text(
                  approved
                      ? 'Votre compte marchand est actif.'
                      : 'Nous vérifions votre dossier. Vous serez notifié dès la validation (sous 24 à 72h).',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.mutedForeground),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded, size: 14, color: AppColors.success),
                      SizedBox(width: 6),
                      Text('Demande enregistrée en sécurité',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: AppColors.success)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: onBack,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
              child: const Text('Retour au profil',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.help_outline_rounded, size: 16),
              label: const Text('Contacter le support',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: AppColors.foreground)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── HELPERS ───────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final TextInputType type;

  const _Field({
    required this.label, required this.controller,
    this.placeholder, this.type = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: label),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: type,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: const TextStyle(fontSize: 13, color: AppColors.mutedForeground),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 2)),
            filled: true, fillColor: AppColors.card,
          ),
          style: const TextStyle(fontSize: 13),
        ),
      ],
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

class _Term extends StatelessWidget {
  final String title;
  final String text;
  const _Term({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check_rounded, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: AppColors.foreground)),
              const SizedBox(height: 2),
              Text(text,
                  style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground)),
            ],
          ),
        ),
      ],
    );
  }
}
