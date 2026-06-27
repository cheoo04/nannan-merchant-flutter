import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';
import '../../shared/models/models.dart';

SupabaseClient get _db => Supabase.instance.client;

// ── Modèle produit DB ─────────────────────────────────────────────────────────
class DbProduct {
  final String id;
  final String merchantId;
  final String name;
  final String? description;
  final int priceXof;
  final String? imageUrl;
  final String category;
  final bool isAvailable;
  final int? stock;
  final String cityCode;

  const DbProduct({
    required this.id,
    required this.merchantId,
    required this.name,
    this.description,
    required this.priceXof,
    this.imageUrl,
    required this.category,
    required this.isAvailable,
    this.stock,
    required this.cityCode,
  });

  factory DbProduct.fromJson(Map<String, dynamic> j) => DbProduct(
        id: j['id'] as String,
        merchantId: j['merchant_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        priceXof: j['price_xof'] as int? ?? 0,
        imageUrl: j['image_url'] as String?,
        category: j['category'] as String,
        isAvailable: j['is_available'] as bool? ?? true,
        stock: j['stock'] as int?,
        cityCode: j['city_code'] as String? ?? 'oume',
      );
}

// ── Notifier produits ─────────────────────────────────────────────────────────
class ProductsNotifier extends ChangeNotifier {
  List<DbProduct> products = [];
  MerchantModel? merchant;
  bool loadingMerchant = true;
  bool loadingProducts = true;
  String query = '';
  RealtimeChannel? _channel;

  ProductsNotifier() { _init(); }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) { loadingMerchant = false; notifyListeners(); return; }

    final m = await _db.from('merchants').select().eq('owner_id', user.id).maybeSingle();
    if (m == null) { loadingMerchant = false; notifyListeners(); return; }
    merchant = MerchantModel.fromJson(m);
    loadingMerchant = false;
    notifyListeners();

    await _loadProducts();
    _subscribe();
  }

  Future<void> _loadProducts() async {
    if (merchant == null) return;
    final data = await _db
        .from('products')
        .select()
        .eq('merchant_id', merchant!.id)
        .order('created_at', ascending: false);
    products = (data as List).map((e) => DbProduct.fromJson(e)).toList();
    loadingProducts = false;
    notifyListeners();
  }

  void _subscribe() {
    _channel = _db.channel('products-${merchant!.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'merchant_id',
            value: merchant!.id,
          ),
          callback: (_) => _loadProducts(),
        )
        .subscribe();
  }

  List<DbProduct> get filtered => query.isEmpty
      ? products
      : products.where((p) => p.name.toLowerCase().contains(query.toLowerCase())).toList();

  void setQuery(String v) { query = v; notifyListeners(); }

  Future<void> toggleOpen() async {
    if (merchant == null) return;
    await _db.from('merchants').update({'is_open': !merchant!.isOpen}).eq('id', merchant!.id);
    await _init();
  }

  Future<void> pauseMerchant(int minutes) async {
    if (merchant == null) return;
    final until = DateTime.now().add(Duration(minutes: minutes));
    await _db.from('merchants').update({'pause_until': until.toIso8601String()}).eq('id', merchant!.id);
    await _init();
  }

  Future<void> resumeMerchant() async {
    if (merchant == null) return;
    await _db.from('merchants').update({'pause_until': null}).eq('id', merchant!.id);
    await _init();
  }

  Future<void> saveSchedule({required bool enabled, String? opening, String? closing}) async {
    if (merchant == null) return;
    await _db.from('merchants').update({
      'auto_schedule_enabled': enabled,
      'opening_time': enabled ? opening : null,
      'closing_time': enabled ? closing : null,
    }).eq('id', merchant!.id);
    await _init();
  }

  Future<void> toggleAvailability(DbProduct p) async {
    await _db.from('products').update({'is_available': !p.isAvailable}).eq('id', p.id);
  }

  Future<void> deleteProduct(String id) async {
    await _db.from('products').delete().eq('id', id);
  }

  Future<String?> uploadImage(String path, Uint8List bytes) async {
    if (merchant == null) return null;
    final filePath = 'products/${merchant!.id}/$path';
    await _db.storage.from('products').uploadBinary(filePath, bytes,
        fileOptions: const FileOptions(upsert: true));
    return _db.storage.from('products').getPublicUrl(filePath);
  }

  Future<void> createProduct({
    required String name, String? description, required int priceXof,
    String? imageUrl, int? stock,
  }) async {
    if (merchant == null) return;
    final user = _db.auth.currentUser!;
    await _db.from('products').insert({
      'merchant_id': merchant!.id,
      'added_by_user_id': user.id,
      'name': name,
      'description': description,
      'price_xof': priceXof,
      'image_url': imageUrl,
      'stock': stock,
      'category': merchant!.category,
      'city_code': merchant!.cityCode,
    });
  }

  Future<void> updateProduct(String id, {
    required String name, String? description,
    required int priceXof, String? imageUrl, int? stock,
  }) async {
    await _db.from('products').update({
      'name': name,
      'description': description,
      'price_xof': priceXof,
      'image_url': imageUrl,
      'stock': stock,
    }).eq('id', id);
  }

  @override
  void dispose() {
    if (_channel != null) _db.removeChannel(_channel!);
    super.dispose();
  }
}

// ── PRODUCTS SCREEN ───────────────────────────────────────────────────────────
class ProductsScreen extends StatefulWidget {
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;
  final VoidCallback onGoToDashboard;

  const ProductsScreen({
    super.key,
    required this.currentNavIndex,
    required this.onNavTap,
    required this.onGoToDashboard,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late final ProductsNotifier _n;
  bool _showEditor = false;
  DbProduct? _editing;

  @override
  void initState() {
    super.initState();
    _n = ProductsNotifier();
    _n.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _n.dispose(); super.dispose(); }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.destructive : null,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _confirmDelete(DbProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Supprimer « ${p.name} » ?',
            style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: const Text('Supprimer', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _n.deleteProduct(p.id);
      _showSnack('Produit supprimé');
    } catch (e) { _showSnack(e.toString(), error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── HEADER ────────────────────────────────────
              SliverToBoxAdapter(child: _ProductsHeader(topPadding: top, notifier: _n, onBack: widget.onGoToDashboard)),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── STATUT BOUTIQUE ───────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _n.loadingMerchant
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : _n.merchant == null
                          ? _EmptyMerchant()
                          : _ShopAvailability(notifier: _n, onSnack: _showSnack),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── BOUTON AJOUTER ───────────────────────────
              if (_n.merchant != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () { _editing = null; setState(() => _showEditor = true); },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 2,
                              style: BorderStyle.solid),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ajouter un produit',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                        color: AppColors.primary)),
                                Text('Nom, prix, stock & visibilité',
                                    style: TextStyle(fontSize: 11, color: AppColors.primary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── CATALOGUE ────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Catalogue (${_n.filtered.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        fontFamily: 'Sora', color: AppColors.foreground),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              if (_n.loadingProducts)
                const SliverToBoxAdapter(
                  child: Center(child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('Chargement temps réel…',
                          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
                    ]),
                  )),
                ),

              if (!_n.loadingProducts && _n.filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
                      ),
                      child: const Text('Aucun produit dans votre catalogue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
                    ),
                  ),
                ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final p = _n.filtered[i];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: _ProductRow(
                        product: p,
                        onToggle: () async {
                          try {
                            await _n.toggleAvailability(p);
                            _showSnack(p.isAvailable ? 'Produit masqué' : 'Produit visible');
                          } catch (e) { _showSnack(e.toString(), error: true); }
                        },
                        onEdit: () { _editing = p; setState(() => _showEditor = true); },
                        onDelete: () => _confirmDelete(p),
                      ),
                    );
                  },
                  childCount: _n.filtered.length,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // ── EDITOR BOTTOM SHEET ──────────────────────────
          if (_showEditor && _n.merchant != null)
            _ProductEditor(
              merchantId: _n.merchant!.id,
              initial: _editing,
              notifier: _n,
              onClose: () => setState(() { _showEditor = false; _editing = null; }),
              onSaved: (msg) => _showSnack(msg),
              onError: (msg) => _showSnack(msg, error: true),
            ),
        ],
      ),
      bottomNavigationBar: MerchantBottomNav(
          currentIndex: widget.currentNavIndex, onTap: widget.onNavTap),
    );
  }
}

// ── HEADER PRODUITS ───────────────────────────────────────────────────────────
class _ProductsHeader extends StatelessWidget {
  final double topPadding;
  final ProductsNotifier notifier;
  final VoidCallback onBack;

  const _ProductsHeader({required this.topPadding, required this.notifier, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.gradientHero,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.headerOverlay, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
              Text(
                notifier.merchant?.name ?? '—',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Mes produits',
              style: TextStyle(color: Colors.white, fontSize: 24,
                  fontWeight: FontWeight.w700, fontFamily: 'Sora')),
          const SizedBox(height: 4),
          const Text('Catalogue & disponibilité boutique en temps réel.',
              style: TextStyle(color: Colors.white, fontSize: 12)),
          const SizedBox(height: 12),
          // Barre de recherche
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.headerOverlay,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: notifier.setQuery,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Rechercher un produit...',
                      hintStyle: TextStyle(color: Colors.white70, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      fillColor: Colors.transparent,
                      filled: false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── STATUT BOUTIQUE ───────────────────────────────────────────────────────────
class _ShopAvailability extends StatefulWidget {
  final ProductsNotifier notifier;
  final void Function(String msg, {bool error}) onSnack;

  const _ShopAvailability({required this.notifier, required this.onSnack});

  @override
  State<_ShopAvailability> createState() => _ShopAvailabilityState();
}

class _ShopAvailabilityState extends State<_ShopAvailability> {
  bool _showSched = false;
  late String _opening;
  late String _closing;
  late bool _schedEnabled;

  @override
  void initState() {
    super.initState();
    final m = widget.notifier.merchant!;
    _opening = m.openingTime ?? '08:00';
    _closing = m.closingTime ?? '22:00';
    _schedEnabled = m.autoScheduleEnabled;
  }

  Color get _toneBg {
    final t = widget.notifier.merchant!.statusLabel.tone;
    if (t == 'open') return AppColors.success.withOpacity(0.15);
    if (t == 'paused') return AppColors.warm.withOpacity(0.2);
    return AppColors.destructive.withOpacity(0.1);
  }

  Color get _toneFg {
    final t = widget.notifier.merchant!.statusLabel.tone;
    if (t == 'open') return AppColors.success;
    if (t == 'paused') return AppColors.warm;
    return AppColors.destructive;
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.notifier.merchant!;
    final label = m.statusLabel.label;
    final isPaused = m.pauseUntil != null &&
        DateTime.parse(m.pauseUntil!).isAfter(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Statut + toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('STATUT BOUTIQUE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppColors.mutedForeground, letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _toneBg, borderRadius: BorderRadius.circular(999)),
                    child: Text(label,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _toneFg)),
                  ),
                ],
              ),
              // Bouton Ouvrir/Fermer
              GestureDetector(
                onTap: () async {
                  try {
                    await widget.notifier.toggleOpen();
                    widget.onSnack(m.isOpen ? 'Boutique fermée' : 'Boutique ouverte');
                  } catch (e) { widget.onSnack(e.toString(), error: true); }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: m.isOpen ? AppColors.destructive : AppColors.success,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    m.isOpen ? 'Fermer' : 'Ouvrir',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),

          if (isPaused) ...[
            const SizedBox(height: 8),
            Text(
              "En pause jusqu'à ${formatTime(DateTime.parse(m.pauseUntil!))}",
              style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground),
            ),
          ],

          const SizedBox(height: 12),

          // Boutons pause 15/30/60
          Row(
            children: [15, 30, 60].map((min) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () async {
                    try {
                      await widget.notifier.pauseMerchant(min);
                      widget.onSnack('Pause $min min');
                    } catch (e) { widget.onSnack(e.toString(), error: true); }
                  },
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.pause_rounded, size: 12, color: AppColors.foreground),
                        const SizedBox(width: 4),
                        Text('${min}m',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: AppColors.foreground)),
                      ],
                    ),
                  ),
                ),
              ),
            )).toList(),
          ),

          // Bouton reprendre
          if (isPaused) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                try { await widget.notifier.resumeMerchant(); widget.onSnack('Pause levée'); }
                catch (e) { widget.onSnack(e.toString(), error: true); }
              },
              child: Container(
                height: 40, width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 14, color: AppColors.success),
                    SizedBox(width: 6),
                    Text('Reprendre maintenant',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success)),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Horaires automatiques
          GestureDetector(
            onTap: () => setState(() => _showSched = !_showSched),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 14, color: AppColors.foreground),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Horaires automatiques',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    m.autoScheduleEnabled
                        ? '${m.openingTime ?? '?'} → ${m.closingTime ?? '?'}'
                        : 'Désactivés',
                    style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground),
                  ),
                ],
              ),
            ),
          ),

          if (_showSched) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Activer la planification',
                          style: TextStyle(fontSize: 12, color: AppColors.foreground)),
                      Switch(
                        value: _schedEnabled,
                        onChanged: (v) => setState(() => _schedEnabled = v),
                        activeColor: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _TimeField(
                        label: 'Ouverture', value: _opening,
                        onChanged: (v) => setState(() => _opening = v),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _TimeField(
                        label: 'Fermeture', value: _closing,
                        onChanged: (v) => setState(() => _closing = v),
                      )),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await widget.notifier.saveSchedule(
                            enabled: _schedEnabled,
                            opening: _opening,
                            closing: _closing,
                          );
                          setState(() => _showSched = false);
                          widget.onSnack('Horaires enregistrés');
                        } catch (e) { widget.onSnack(e.toString(), error: true); }
                      },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      ),
                      child: const Text('Enregistrer les horaires',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── PRODUCT ROW ───────────────────────────────────────────────────────────────
class _ProductRow extends StatelessWidget {
  final DbProduct product;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductRow({required this.product, required this.onToggle,
      required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Opacity(
      opacity: p.isAvailable ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 2),
              BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
        ),
        child: Row(
          children: [
            // Photo
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: p.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: p.imageUrl!,
                      width: 64, height: 64, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 64, height: 64, color: AppColors.secondary,
                      ),
                    )
                  : Container(
                      width: 64, height: 64,
                      color: AppColors.secondary,
                      alignment: Alignment.center,
                      child: Text(p.name.substring(0, 2).toUpperCase(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                              color: AppColors.mutedForeground)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(formatXOF(p.priceXof),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    children: [
                      // Toggle visible/masqué
                      GestureDetector(
                        onTap: onToggle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.isAvailable
                                ? AppColors.success.withOpacity(0.2)
                                : AppColors.secondary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            p.isAvailable ? 'Visible' : 'Masqué',
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: p.isAvailable ? AppColors.success : AppColors.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                      if (p.stock != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.secondary, borderRadius: BorderRadius.circular(999)),
                          child: Text('Stock ${p.stock}',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                  color: AppColors.foreground)),
                        ),
                      // Modifier
                      GestureDetector(
                        onTap: onEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.primarySoft, borderRadius: BorderRadius.circular(999)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.edit_rounded, size: 10, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text('Modifier',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                    color: AppColors.primary)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Supprimer
            GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.destructive.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(Icons.delete_rounded, size: 14, color: AppColors.destructive),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── PRODUCT EDITOR (bottom sheet) ─────────────────────────────────────────────
class _ProductEditor extends StatefulWidget {
  final String merchantId;
  final DbProduct? initial;
  final ProductsNotifier notifier;
  final VoidCallback onClose;
  final void Function(String) onSaved;
  final void Function(String) onError;

  const _ProductEditor({
    required this.merchantId, this.initial, required this.notifier,
    required this.onClose, required this.onSaved, required this.onError,
  });

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  String? _imageUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _name = TextEditingController(text: p?.name ?? '');
    _desc = TextEditingController(text: p?.description ?? '');
    _price = TextEditingController(text: p != null ? '${p.priceXof}' : '');
    _stock = TextEditingController(text: p?.stock != null ? '${p!.stock}' : '');
    _imageUrl = p?.imageUrl;
  }

  @override
  void dispose() {
    _name.dispose(); _desc.dispose(); _price.dispose(); _stock.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes(); // retourne Uint8List
    final url = await widget.notifier.uploadImage(
      '${DateTime.now().millisecondsSinceEpoch}.jpg', bytes,
    );
    if (url != null) setState(() => _imageUrl = url);
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) { widget.onError('Nom requis'); return; }
    final price = int.tryParse(_price.text);
    if (price == null || price <= 0) { widget.onError('Prix invalide'); return; }
    final stock = _stock.text.isEmpty ? null : int.tryParse(_stock.text);

    setState(() => _saving = true);
    try {
      if (widget.initial != null) {
        await widget.notifier.updateProduct(widget.initial!.id,
            name: _name.text.trim(), description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            priceXof: price, imageUrl: _imageUrl, stock: stock);
        widget.onSaved('Produit mis à jour');
      } else {
        await widget.notifier.createProduct(
            name: _name.text.trim(), description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            priceXof: price, imageUrl: _imageUrl, stock: stock);
        widget.onSaved('Produit créé');
      }
      widget.onClose();
    } catch (e) {
      widget.onError(e.toString());
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).padding.bottom + 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                    )),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.initial != null ? 'Modifier le produit' : 'Nouveau produit',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                              fontFamily: 'Sora'),
                        ),
                        GestureDetector(
                          onTap: widget.onClose,
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(color: AppColors.secondary,
                                borderRadius: BorderRadius.circular(999)),
                            child: const Icon(Icons.close_rounded, size: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Nom
                    _FieldLabel(label: 'Nom'),
                    const SizedBox(height: 4),
                    TextField(controller: _name,
                        decoration: const InputDecoration(hintText: 'Ex: Garba spécial')),

                    const SizedBox(height: 12),

                    // Description
                    _FieldLabel(label: 'Description'),
                    const SizedBox(height: 4),
                    TextField(controller: _desc, maxLines: 2,
                        decoration: const InputDecoration(hintText: 'Ingrédients, détails…')),

                    const SizedBox(height: 12),

                    // Prix + Stock
                    Row(
                      children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _FieldLabel(label: 'Prix (FCFA)'),
                          const SizedBox(height: 4),
                          TextField(controller: _price,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '0')),
                        ])),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _FieldLabel(label: 'Stock (optionnel)'),
                          const SizedBox(height: 4),
                          TextField(controller: _stock,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '∞')),
                        ])),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Photo
                    _FieldLabel(label: 'Photo du produit'),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 100, width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          image: _imageUrl != null
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(_imageUrl!),
                                  fit: BoxFit.cover)
                              : null,
                        ),
                        child: _imageUrl == null
                            ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.add_photo_alternate_rounded,
                                    color: AppColors.mutedForeground, size: 24),
                                SizedBox(height: 4),
                                Text('Choisir une photo',
                                    style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
                              ])
                            : null,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Bouton submit
                    SizedBox(
                      width: double.infinity, height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(widget.initial != null
                                ? Icons.save_rounded : Icons.publish_rounded, size: 18),
                        label: Text(
                          widget.initial != null ? 'Enregistrer' : 'Publier',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── HELPERS ───────────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: AppColors.mutedForeground, letterSpacing: 0.8),
  );
}

class _TimeField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TimeField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.mutedForeground, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () async {
            final parts = value.split(':').map(int.parse).toList();
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
            );
            if (picked != null) {
              onChanged('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _EmptyMerchant extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border, style: BorderStyle.solid),
    ),
    child: const Text('Aucun commerce associé à votre compte.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
  );
}
