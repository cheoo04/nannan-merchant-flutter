// --- Fichier : lib/features/become_merchant/become_merchant_screen.dart ---
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/ci_phone.dart';
import '../../core/utils/toast.dart';
import '../../core/services/a_nan_nan_api_client.dart';
import '../../core/services/a_nan_nan_services.dart';
import '../../core/services/neon_session.dart';
import '../../main.dart' show LoginScreen, MerchantShell;
import '../location_picker/location_picker_screen.dart';

const String _supportPhoneDial = '+2250565074868';
const String _supportPhoneWa = '2250565074868';

// Codes conformes aux types d'activité attendus par le backend Neon
const _businessTypeCodeByCategory = {
  'restaurant': 'restaurant',
  'fast_food': 'fast_food',
  'boulangerie': 'bakery',
  'boutique': 'grocery',
  'pharmacie': 'pharmacy',
  'autre': 'service',
};

const _categories = [
  (id: 'restaurant', label: 'Restaurant / Maquis'),
  (id: 'fast_food', label: 'Fast-Food'),
  (id: 'boulangerie', label: 'Boulangerie / Pâtisserie'),
  (id: 'boutique', label: 'Épicerie / Boutique'),
  (id: 'pharmacie', label: 'Pharmacie'),
  (id: 'autre', label: 'Autre commerce'),
];

enum _Step { info, terms, pending }

class BecomeMerchantScreen extends StatefulWidget {
  final VoidCallback onBack;
  final bool startAtPending;

  const BecomeMerchantScreen({
    super.key,
    required this.onBack,
    this.startAtPending = false,
  });

  @override
  State<BecomeMerchantScreen> createState() => _BecomeMerchantScreenState();
}

class _BecomeMerchantScreenState extends State<BecomeMerchantScreen> {
  late _Step _step = widget.startAtPending ? _Step.pending : _Step.info;
  bool _existingApproved = false;
  bool _submitting = false;
  bool _checkingExisting = true;
  String? _userId;

  // Champs gérant
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  // Champs boutique
  final _city = TextEditingController(text: 'Oumé');
  final _address = TextEditingController();
  double? _lat;
  double? _lng;
  final _businessName = TextEditingController();
  final _description = TextEditingController();
  String _category = _categories[0].id;

  bool _accepted = false;

  final _api = ANanNanApiClient();
  late final _merchantService = MerchantService(_api);

  @override
  void initState() {
    super.initState();
    _checkExistingAndPrefill();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _city.dispose();
    _address.dispose();
    _businessName.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _checkExistingAndPrefill() async {
    try {
      final me = await _api.me();
      _userId = me['id'] as String?;

      if (!mounted) return;

      final first = me['first_name'] as String?;
      final last = me['last_name'] as String?;
      if (first != null && first.isNotEmpty) _firstName.text = first;
      if (last != null && last.isNotEmpty) _lastName.text = last;

      final phone = me['phone'] as String?;
      if (phone != null && phone.isNotEmpty) _phone.text = phone;

      // Vérifier si un commerce est déjà approuvé
      final myMerchants = await _merchantService.getMine();
      if (myMerchants.isNotEmpty) {
        final current = myMerchants.first;
        NeonSession.setCurrentMerchant(current);
        final status = current['status'] as String? ?? 'pending';

        setState(() {
          _step = _Step.pending;
          _existingApproved = status == 'active';
          _checkingExisting = false;
        });
        return;
      }

      if (widget.startAtPending) {
        setState(() {
          _step = _Step.pending;
          _checkingExisting = false;
        });
        return;
      }

      if (_userId != null) {
        final prefs = await SharedPreferences.getInstance();
        final hasPending =
            prefs.getBool('pending_application_$_userId') ?? false;
        if (hasPending) {
          setState(() {
            _step = _Step.pending;
            _existingApproved = false;
            _checkingExisting = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _checkingExisting = false);
  }

  void _submitInfo() {
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      toast.error('Renseignez le prénom et le nom du gérant');
      return;
    }
    if (_phone.text.trim().isEmpty) {
      toast.error('Renseignez le numéro de téléphone');
      return;
    }
    if (_businessName.text.trim().isEmpty) {
      toast.error('Indiquez le nom de votre commerce');
      return;
    }
    if (_address.text.trim().isEmpty) {
      toast.error("Indiquez l'adresse ou repère du commerce");
      return;
    }
    if (_lat == null || _lng == null) {
      toast.error('Positionnez votre commerce sur la carte');
      return;
    }
    setState(() => _step = _Step.terms);
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: _lat,
          initialLng: _lng,
          initialAddress:
              _address.text.trim().isEmpty ? null : _address.text.trim(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lat = result.lat;
      _lng = result.lng;
      if (result.address != null && result.address!.isNotEmpty) {
        _address.text = result.address!;
      }
    });
  }

  Future<void> _submitTerms() async {
    if (!_accepted) {
      toast.error('Vous devez accepter les conditions');
      return;
    }

    setState(() => _submitting = true);
    try {
      final managerFullName =
          '${_firstName.text.trim()} ${_lastName.text.trim()}';
      final cleanPhone = CiPhone.normalize(_phone.text);

      await _api.post('/api/v1/auth/role-applications', body: {
        'requested_role': 'merchant',
        'business_name': _businessName.text.trim(),
        'business_type_code':
            _businessTypeCodeByCategory[_category] ?? 'restaurant',
        'manager_name': managerFullName,
        'manager_phone': cleanPhone,
        'neighborhood':
            _city.text.trim().isEmpty ? 'Oumé Centre' : _city.text.trim(),
        'address_line': _address.text.trim(),
        'latitude': _lat,
        'longitude': _lng,
        if (_description.text.trim().isNotEmpty)
          'description': _description.text.trim(),
      });

      if (_userId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('pending_application_$_userId', true);
      }

      toast.success('Demande envoyée avec succès');
      setState(() => _step = _Step.pending);
    } on ANanNanApiException catch (e) {
      toast.error(e.statusCode == 404
          ? "Code d'activité non reconnu par le serveur"
          : e.message);
    } catch (e) {
      toast.error('Erreur de connexion. Réessayez.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkStatusAgain() async {
    try {
      final myMerchants = await _merchantService.getMine();
      if (myMerchants.isNotEmpty) {
        final current = myMerchants.first;
        final status = current['status'] as String? ?? 'pending';
        if (status == 'active') {
          NeonSession.setCurrentMerchant(current);
          final bType = (current['business_type'] as String?)?.toLowerCase();
          final isPharmacy = bType == 'pharmacie' || bType == 'pharmacy';

          if (mounted) {
            toast.success('Félicitations ! Votre boutique a été validée.');
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => MerchantShell(isPharmacy: isPharmacy)),
              (_) => false,
            );
          }
          return;
        }
      }
      toast.info(
          'Dossier reçu : en attente de validation par l\'administrateur.');
    } catch (_) {
      toast.error('Erreur de connexion lors de la vérification.');
    }
  }

  Future<void> _contactSupport() async {
    final uri = Uri.parse(
        'https://wa.me/$_supportPhoneWa?text=Bonjour,%20je%20souhaite%20suivre%20la%20validation%20de%20ma%20boutique.');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      final telUri = Uri.parse('tel:$_supportPhoneDial');
      await launchUrl(telUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    NeonSession.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    if (_checkingExisting) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, 12),
            color: AppColors.background.withValues(alpha: 0.95),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.card,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x0F000000), blurRadius: 8)
                      ],
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
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Sora',
                            color: AppColors.foreground),
                      ),
                      const SizedBox(height: 4),
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
                                color: filled
                                    ? AppColors.primary
                                    : AppColors.border,
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
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.store_rounded,
                      color: AppColors.primary, size: 16),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.of(context).padding.bottom + 24,
              ),
              child: switch (_step) {
                _Step.info => _StepInfo(
                    firstName: _firstName,
                    lastName: _lastName,
                    phone: _phone,
                    city: _city,
                    address: _address,
                    businessName: _businessName,
                    description: _description,
                    category: _category,
                    lat: _lat,
                    lng: _lng,
                    onCategoryChanged: (v) => setState(() => _category = v),
                    onNext: _submitInfo,
                    onPickLocation: _pickLocation,
                    onGoToPending: () => setState(() => _step = _Step.pending),
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
                    onCheckStatus: _checkStatusAgain,
                    onContactSupport: _contactSupport,
                    onModifyApplication: () =>
                        setState(() => _step = _Step.info),
                    onLogout: _logout,
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
  final TextEditingController firstName,
      lastName,
      phone,
      city,
      address,
      businessName,
      description;
  final String category;
  final double? lat;
  final double? lng;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onNext;
  final VoidCallback onPickLocation;
  final VoidCallback onGoToPending;

  const _StepInfo({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.city,
    required this.address,
    required this.businessName,
    required this.description,
    required this.category,
    this.lat,
    this.lng,
    required this.onCategoryChanged,
    required this.onNext,
    required this.onPickLocation,
    required this.onGoToPending,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Étape 1/3 — Responsable & Commerce',
                style:
                    TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
            GestureDetector(
              onTap: onGoToPending,
              child: const Text(
                'Voir ma demande en attente',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Prénom et Nom distincts du gérant
        Row(
          children: [
            Expanded(
              child: _Field(
                label: 'Prénom du gérant',
                controller: firstName,
                placeholder: 'Marie',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                label: 'Nom du gérant',
                controller: lastName,
                placeholder: 'Kouassi',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _Field(
          label: 'Numéro WhatsApp / Contact',
          controller: phone,
          placeholder: '07 00 00 00 00',
          type: TextInputType.phone,
        ),
        const SizedBox(height: 12),

        _Field(
            label: 'Nom du commerce',
            controller: businessName,
            placeholder: 'Restaurant Chez Marie'),
        const SizedBox(height: 12),

        _Field(
            label: 'Quartier / Ville',
            controller: city,
            placeholder: 'Oumé Centre'),
        const SizedBox(height: 12),

        _Field(
            label: 'Adresse ou repère précis',
            controller: address,
            placeholder: 'Face Mairie, à côté de la pharmacie'),
        const SizedBox(height: 8),

        GestureDetector(
          onTap: onPickLocation,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  lat != null
                      ? Icons.check_circle_rounded
                      : Icons.location_on_outlined,
                  size: 16,
                  color: lat != null
                      ? AppColors.success
                      : AppColors.mutedForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lat != null
                        ? 'Position GPS définie'
                        : 'Positionner sur la carte (GPS)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: lat != null
                          ? AppColors.success
                          : AppColors.foreground,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.mutedForeground),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        const _FieldLabel(text: 'Secteur d\'activité'),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 3.5,
          children: _categories.map((c) {
            final active = category == c.id;
            return GestureDetector(
              onTap: () => onCategoryChanged(c.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.primarySoft : AppColors.card,
                  border: Border.all(
                    color: active ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: active
                      ? null
                      : const [
                          BoxShadow(color: Color(0x0F000000), blurRadius: 8)
                        ],
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

        const _FieldLabel(text: 'Courte description (optionnelle)'),
        const SizedBox(height: 4),
        TextField(
          controller: description,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Spécialités, horaires ou informations utiles…',
            hintStyle:
                const TextStyle(fontSize: 13, color: AppColors.mutedForeground),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2)),
            filled: true,
            fillColor: AppColors.card,
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
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
    required this.accepted,
    required this.onAcceptChanged,
    required this.onBack,
    required this.onSubmit,
    required this.submitting,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Étape 2/3 — Conditions d'engagement",
            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(maxHeight: 340),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 16,
                  offset: Offset(0, 4))
            ],
          ),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _Term(
                  title: 'Engagement de service',
                  text:
                      "Je m'engage à respecter les délais, la qualité et la courtoisie envers les clients d'A Nan-Nan.",
                ),
                SizedBox(height: 12),
                _Term(
                  title: 'Données & confidentialité',
                  text:
                      "Mes données sont utilisées uniquement pour les besoins opérationnels du service A Nan-Nan.",
                ),
                SizedBox(height: 12),
                _Term(
                  title: 'Validation administrative',
                  text:
                      "Ma demande sera examinée sous 24 à 48h par l'équipe A Nan-Nan avant activation de ma vitrine.",
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: accepted,
                    onChanged: (v) => onAcceptChanged(v ?? false),
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "J'ai lu et j'accepte les conditions ci-dessus pour ouvrir mon commerce.",
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Retour',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: submitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Soumettre mon dossier',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── ÉTAPE 3 : PENDING (BOUTONS OPÉRATIONNELS) ──────────────────────────────────
class _StepPending extends StatelessWidget {
  final bool approved;
  final VoidCallback onCheckStatus;
  final VoidCallback onContactSupport;
  final VoidCallback onModifyApplication;
  final VoidCallback onLogout;

  const _StepPending({
    required this.approved,
    required this.onCheckStatus,
    required this.onContactSupport,
    required this.onModifyApplication,
    required this.onLogout,
  });

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
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 16,
                    offset: Offset(0, 4))
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: approved
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    approved
                        ? Icons.check_circle_rounded
                        : Icons.access_time_rounded,
                    color: approved ? AppColors.success : AppColors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  approved
                      ? 'Demande approuvée !'
                      : 'Votre dossier est en cours d\'examen',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Sora',
                      color: AppColors.foreground),
                ),
                const SizedBox(height: 8),
                Text(
                  approved
                      ? 'Votre boutique est active. Vous pouvez accéder à votre tableau de bord.'
                      : 'Notre équipe vérifie vos informations et votre position. Votre commerce sera activé sous 24 à 48h.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.mutedForeground),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user_rounded,
                          size: 14, color: AppColors.success),
                      SizedBox(width: 6),
                      Text('Candidature enregistrée',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onCheckStatus,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              label: Text(
                approved
                    ? 'Accéder à ma boutique'
                    : 'Actualiser / Vérifier mon statut',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onContactSupport,
              icon: const Icon(Icons.chat_rounded,
                  size: 16, color: AppColors.success),
              label: const Text(
                'Contacter le support (WhatsApp)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onModifyApplication,
            icon: const Icon(Icons.edit_note_rounded,
                size: 16, color: AppColors.mutedForeground),
            label: const Text(
              'Modifier ma candidature / Remplir à nouveau',
              style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
            ),
          ),
          TextButton(
            onPressed: onLogout,
            child: const Text(
              'Se déconnecter',
              style: TextStyle(fontSize: 12, color: AppColors.destructive),
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
    required this.label,
    required this.controller,
    this.placeholder,
    this.type = TextInputType.text,
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
            hintStyle:
                const TextStyle(fontSize: 13, color: AppColors.mutedForeground),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2)),
            filled: true,
            fillColor: AppColors.card,
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
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.mutedForeground,
            letterSpacing: 0.8),
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
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.foreground)),
              const SizedBox(height: 2),
              Text(text,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.mutedForeground)),
            ],
          ),
        ),
      ],
    );
  }
}
