import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/skeleton.dart';

// ⚠️ PLACEHOLDER — même faux numéro que côté React (_app.profile.tsx),
// à remplacer par le vrai numéro de support avant mise en production.
const String _supportPhoneDisplay = '+225 07 00 00 00 00';
const String _supportPhoneDial = '+22507000000'; // format tel: sans espaces
const String _supportPhoneWa = '22507000000'; // format wa.me sans le +
const String _supportEmail = 'support@nannan.ci';

SupabaseClient get _db => Supabase.instance.client;

// ── Modèle profil léger ────────────────────────────────────────────────────────
class _ProfileData {
  final String name;
  final String email;
  final String phone;
  final String role;

  const _ProfileData({
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
  });
}

// ── Écran profil marchand ──────────────────────────────────────────────────────
// Miroir de ProfileScreen côté client (même structure : header card avec
// avatar initiales + gradient, lignes menu, bouton déconnexion rouge).
// Adapté au contexte marchand : lignes spécifiques (mon commerce, notifications,
// devenir partenaire...) à la place des lignes client (adresses, ordonnances...).
class MerchantProfileScreen extends StatefulWidget {
  final VoidCallback onSignOut;
  final VoidCallback? onGoToNotifications;
  final int unreadCount;
  /// Stats lues depuis DashboardNotifier (partagé, voir main.dart) — pas de
  /// requête DB dédiée pour cet écran.
  final int deliveredCount;
  final int activeCount;
  final int revenueTotal;

  const MerchantProfileScreen({
    super.key,
    required this.onSignOut,
    this.onGoToNotifications,
    this.unreadCount = 0,
    this.deliveredCount = 0,
    this.activeCount = 0,
    this.revenueTotal = 0,
  });

  @override
  State<MerchantProfileScreen> createState() => _MerchantProfileScreenState();
}

class _MerchantProfileScreenState extends State<MerchantProfileScreen> {
  _ProfileData? _profile;
  bool _loading = true;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _db.auth.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    try {
      final data = await _db
          .from('users_profiles')
          .select('name, email, phone, role')
          .eq('id', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _profile = _ProfileData(
            name: (data?['name'] as String? ?? '').isNotEmpty
                ? data!['name'] as String
                : user.email ?? 'Marchand',
            email: data?['email'] as String? ?? user.email ?? '',
            phone: data?['phone'] as String? ?? '',
            role: data?['role'] as String? ?? 'merchant',
          );
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    final result = await showModalBottomSheet<({String name, String phone})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _EditProfileSheet(
        initialName: _profile?.name ?? '',
        initialPhone: _profile?.phone ?? '',
        userId: user.id,
      ),
    );

    final saved = result != null;
    final newName = result?.name ?? '';
    final newPhone = result?.phone ?? '';

    if (saved && mounted) {
      setState(() {
        _profile = _ProfileData(
          name: newName.isNotEmpty ? newName : (_profile?.name ?? 'Marchand'),
          email: _profile?.email ?? '',
          phone: newPhone,
          role: _profile?.role ?? 'merchant',
        );
      });
      toast.success('Profil mis à jour');
    }
  }

  Future<void> _signOut() async {
    // Confirmation avant déconnexion — même pattern que le client
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Déconnexion',
            style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700)),
        content: const Text(
            'Êtes-vous sûr de vouloir vous déconnecter de votre espace marchand ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler',
                style: TextStyle(color: AppColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter',
                style: TextStyle(
                    color: AppColors.destructive,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _signingOut = true);
    try {
      await _db.auth.signOut();
      widget.onSignOut();
    } catch (_) {
      if (mounted) {
        setState(() => _signingOut = false);
        toast.error('Erreur lors de la déconnexion');
      }
    }
  }

  // Initiales depuis le nom complet — même logique que ProfileScreen client
  static String _initials(String name) {
    final parts = name.trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'NN';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    if (_loading) {
      return ProfileSkeleton(topPadding: top);
    }

    final name = _profile?.name ?? 'Marchand';
    final email = _profile?.email ?? '';
    final phone = _profile?.phone ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Header card (même structure que client) ────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [
                BoxShadow(color: Color(0x0A000000), blurRadius: 2),
                BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 16,
                    offset: Offset(0, 4)),
              ],
            ),
            padding: EdgeInsets.fromLTRB(20, top + 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 40, height: 40,
                        decoration: const BoxDecoration(
                          color: AppColors.background,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_rounded, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('Profil',
                            style: TextStyle(
                                fontFamily: 'Sora',
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.foreground)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    // Avatar avec initiales + gradient (miroir client)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        gradient: AppColors.gradientPrimary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(name),
                        style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontFamily: 'Sora',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.foreground)),
                          const SizedBox(height: 2),
                          if (email.isNotEmpty)
                            Text(email,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.mutedForeground)),
                          if (phone.isNotEmpty)
                            Text(phone,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.mutedForeground)),
                        ],
                      ),
                    ),
                    // Badge rôle
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('Marchand',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _editProfile,
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit_rounded,
                            size: 16, color: AppColors.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Quick stats — depuis DashboardNotifier, aucune requête ici ──────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _Stat(
                      label: 'Livrées', value: '${widget.deliveredCount}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child:
                      _Stat(label: 'En attente', value: '${widget.activeCount}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stat(
                      label: 'CA total', value: formatXOF(widget.revenueTotal)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Lignes menu ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                // Notifications
                if (widget.onGoToNotifications != null)
                  _ProfileRow(
                    icon: Icons.notifications_rounded,
                    title: 'Notifications',
                    subtitle: widget.unreadCount > 0
                        ? '${widget.unreadCount} non lue(s)'
                        : 'Commandes, livraisons, alertes',
                    badge: widget.unreadCount > 0
                        ? widget.unreadCount
                        : null,
                    onTap: widget.onGoToNotifications!,
                  ),
                if (widget.onGoToNotifications != null)
                  const SizedBox(height: 8),

                // Aide & support
                _ProfileRow(
                  icon: Icons.help_outline_rounded,
                  title: 'Aide & support',
                  subtitle: 'FAQ, contact, signaler un problème',
                  onTap: () => _showSupport(context),
                ),
                const SizedBox(height: 8),

                // À propos
                _ProfileRow(
                  icon: Icons.info_outline_rounded,
                  title: 'À propos',
                  subtitle: 'A Nan-Nan Livraison · Oumé, Côte d\'Ivoire',
                  onTap: () => _showAbout(context),
                ),
                const SizedBox(height: 24),

                // Bouton déconnexion (rouge, même style que client)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _signingOut ? null : _signOut,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                          color: AppColors.destructive.withOpacity(0.35),
                          width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: _signingOut
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.destructive))
                        : const Icon(Icons.logout_rounded,
                            size: 18, color: AppColors.destructive),
                    label: Text(
                      _signingOut ? 'Déconnexion...' : 'Se déconnecter',
                      style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.destructive),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Footer
          _AppFooter(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) toast.error('Impossible d\'ouvrir cette action');
    }
  }

  void _showSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aide & support',
                style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text(
                'Pour toute question ou problème avec votre espace marchand, '
                'contactez l\'équipe Nan-Nan :',
                style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _launch(Uri.parse('tel:$_supportPhoneDial')),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Appeler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _launch(
                        Uri.parse('https://wa.me/$_supportPhoneWa')),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success,
                        side: const BorderSide(color: AppColors.success)),
                    icon: const Icon(Icons.chat_rounded, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('📞 $_supportPhoneDisplay',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _launch(Uri.parse('mailto:$_supportEmail')),
              child: const Text('✉️ $_supportEmail',
                  style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 20),
            const Text('Questions fréquentes',
                style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const _FaqItem(
              q: 'Comment recevoir une nouvelle commande ?',
              a: 'Vous êtes notifié dès qu\'un client commande. Acceptez-la '
                  'avec le code affiché avant que le livreur ne passe.',
            ),
            const _FaqItem(
              q: 'Le livreur n\'est pas encore passé ?',
              a: 'Contactez-nous par appel ou WhatsApp, on intervient.',
            ),
            const _FaqItem(
              q: 'Comment mettre ma boutique en pause ?',
              a: 'Depuis le tableau de bord, utilisez le bouton Ouvert/Fermé '
                  'en haut de l\'écran.',
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('À propos',
                style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 16),
            Text('A Nan-Nan Livraison',
                style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Marketplace locale de livraison\nOumé, Côte d\'Ivoire · v1.0',
                style: TextStyle(
                    fontSize: 13, color: AppColors.mutedForeground)),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── FAQ dépliable, dans le bottom sheet support ─────────────────────────────
class _FaqItem extends StatefulWidget {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.q,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Icon(
                  _open ? Icons.remove_rounded : Icons.add_rounded,
                  size: 18,
                  color: AppColors.mutedForeground,
                ),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(widget.a,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.mutedForeground)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Widget stat (mini-carte, "Quick stats" côté React) ──────────────────────
class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Text(value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.mutedForeground)),
        ],
      ),
    );
  }
}

// ── Footer : nom + version app + date de build ──────────────────────────────
// La date est codée en dur — Flutter n'a pas d'équivalent natif à
// __BUILD_DATE__ (spécifique aux bundlers JS type Vite). À METTRE À JOUR
// MANUELLEMENT à chaque nouvelle release. Format ISO (YYYY-MM-DD), même
// convention que le footer React.
const String _buildDate = '2026-07-26';

class _AppFooter extends StatelessWidget {
  _AppFooter();

  @override
  Widget build(BuildContext context) {
    // Une seule ligne, comme côté React — la localisation (Oumé, Côte
    // d'Ivoire) est déjà donnée par la ligne "À propos" juste au-dessus,
    // pas besoin de la répéter ici.
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '';
        return Text(
          version.isEmpty
              ? 'A Nan-Nan · build $_buildDate · Made in 🇨🇮'
              : 'A Nan-Nan · v$version · build $_buildDate · Made in 🇨🇮',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground),
        );
      },
    );
  }
}

// ── Widget ligne menu (miroir _ProfileRowTile client) ──────────────────────────
class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int? badge;

  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              // Icône chip
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.foreground)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.mutedForeground)),
                  ],
                ),
              ),
              // Badge non lus (pour notifications)
              if (badge != null && badge! > 0)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.destructive,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$badge',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

// ── EDIT PROFILE SHEET ────────────────────────────────────────────────────────
class _EditProfileSheet extends StatefulWidget {
  final String initialName;
  final String initialPhone;
  final String userId;

  const _EditProfileSheet({
    required this.initialName,
    required this.initialPhone,
    required this.userId,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      toast.error('Le nom ne peut pas être vide');
      return;
    }
    setState(() => _saving = true);
    try {
      await _db.from('users_profiles').update({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      }).eq('id', widget.userId);
      if (mounted) {
        Navigator.of(context).pop((
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        ));
      }
    } catch (_) {
      setState(() => _saving = false);
      if (mounted) toast.error('Échec de la mise à jour');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24,
        24 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Modifier mes informations',
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom complet',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Numéro de téléphone',
              hintText: '+225 07 00 00 00 00',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}