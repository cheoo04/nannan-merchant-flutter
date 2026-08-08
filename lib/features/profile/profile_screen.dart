import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';

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

  const MerchantProfileScreen({
    super.key,
    required this.onSignOut,
    this.onGoToNotifications,
    this.unreadCount = 0,
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
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
        ),
      );
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
                const Text('Profil',
                    style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.foreground)),
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
                  ],
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
          const Text(
            'A Nan-Nan Livraison · Oumé, Côte d\'Ivoire',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.mutedForeground),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showSupport(BuildContext context) {
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
            Text('Aide & support',
                style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 16),
            Text('Pour toute question ou problème avec votre espace marchand,\n'
                'contactez l\'équipe Nan-Nan via WhatsApp ou par email.',
                style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
            SizedBox(height: 8),
            Text('📞 WhatsApp : +225 07 00 00 00 00',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 4),
            Text('✉️ support@nannan.ci',
                style: TextStyle(fontSize: 13)),
            SizedBox(height: 24),
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
              BoxShadow(color: Color(0x0A000000), blurRadius: 2),
              BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2)),
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
