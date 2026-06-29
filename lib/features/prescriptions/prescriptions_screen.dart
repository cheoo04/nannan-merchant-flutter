import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';

SupabaseClient get _db => Supabase.instance.client;

// ── Modèle prescription ───────────────────────────────────────────────────────
class PrescriptionRow {
  final String id;
  final String clientId;
  final String merchantId;
  final String status;
  final List<String> imagePaths;
  final String? clientNote;
  final String? deliveryAddress;
  final List<Map<String, dynamic>>? quoteItems;
  final int? deliveryFeeXof;
  final int? totalXof;
  final int? estimatedReadyMinutes;
  final String? pharmacistNote;
  final DateTime createdAt;

  const PrescriptionRow({
    required this.id, required this.clientId, required this.merchantId,
    required this.status, required this.imagePaths,
    this.clientNote, this.deliveryAddress, this.quoteItems,
    this.deliveryFeeXof, this.totalXof, this.estimatedReadyMinutes,
    this.pharmacistNote, required this.createdAt,
  });

  factory PrescriptionRow.fromJson(Map<String, dynamic> j) => PrescriptionRow(
    id: j['id'] as String,
    clientId: j['client_id'] as String,
    merchantId: j['merchant_id'] as String,
    status: j['status'] as String? ?? 'received',
    imagePaths: (j['image_paths'] as List<dynamic>?)?.cast<String>() ?? [],
    clientNote: j['client_note'] as String?,
    deliveryAddress: j['delivery_address'] as String?,
    quoteItems: (j['quote_items'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    deliveryFeeXof: j['delivery_fee_xof'] as int?,
    totalXof: j['total_xof'] as int?,
    estimatedReadyMinutes: j['estimated_ready_minutes'] as int?,
    pharmacistNote: j['pharmacist_note'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

const _statusLabel = {
  'received': 'Reçue',
  'analyzing': 'En analyse',
  'quoted': 'Devis envoyé',
  'accepted': 'Accepté',
  'paid': 'Payée',
  'cancelled': 'Annulée',
};

// ── Notifier ──────────────────────────────────────────────────────────────────
class PrescriptionsNotifier extends ChangeNotifier {
  List<PrescriptionRow> prescriptions = [];
  bool loading = true;
  String? merchantId;

  PrescriptionsNotifier() { _init(); }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) { loading = false; notifyListeners(); return; }
    final m = await _db.from('merchants').select('id').eq('owner_id', user.id).maybeSingle();
    if (m == null) { loading = false; notifyListeners(); return; }
    merchantId = m['id'] as String;
    await load();
  }

  Future<void> load() async {
    if (merchantId == null) return;
    final data = await _db.from('prescriptions').select()
        .eq('merchant_id', merchantId!).order('created_at', ascending: false);
    prescriptions = (data as List).map((e) => PrescriptionRow.fromJson(e)).toList();
    loading = false;
    notifyListeners();
  }

  List<PrescriptionRow> get inbox =>
      prescriptions.where((p) => p.status == 'received' || p.status == 'analyzing').toList();
  List<PrescriptionRow> get quoted =>
      prescriptions.where((p) => p.status == 'quoted' || p.status == 'accepted').toList();
  List<PrescriptionRow> get done =>
      prescriptions.where((p) => p.status == 'paid').toList();

  Future<String?> getSignedUrl(String path) async {
    try {
      final url = await _db.storage.from('prescriptions').createSignedUrl(path, 3600);
      return url;
    } catch (_) { return null; }
  }

  Future<void> setStatus(String id, String status) async {
    await _db.from('prescriptions').update({'status': status}).eq('id', id);
    await load();
  }

  Future<void> submitQuote(String id, {
    required List<Map<String, dynamic>> items,
    required int deliveryFee,
    required int readyMin,
    String? note,
  }) async {
    final subtotal = items.fold<int>(0, (s, i) => s + (i['qty'] as int) * (i['unit_price_xof'] as int));
    await _db.from('prescriptions').update({
      'status': 'quoted',
      'quote_items': items,
      'products_subtotal_xof': subtotal,
      'delivery_fee_xof': deliveryFee,
      'total_xof': subtotal + deliveryFee,
      'estimated_ready_minutes': readyMin,
      'pharmacist_note': note,
      'quoted_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await load();
  }
}

// ── PRESCRIPTIONS SCREEN ──────────────────────────────────────────────────────
class PrescriptionsScreen extends StatefulWidget {
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;

  const PrescriptionsScreen({
    super.key, required this.currentNavIndex, required this.onNavTap,
  });

  @override
  State<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends State<PrescriptionsScreen> {
  late final PrescriptionsNotifier _n;
  String? _openId;

  @override
  void initState() {
    super.initState();
    _n = PrescriptionsNotifier();
    _n.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _n.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    if (_n.loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
        ),
        bottomNavigationBar: MerchantBottomNav(
            currentIndex: widget.currentNavIndex, onTap: widget.onNavTap),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Header simple (pas de gradient hero ici — miroir React) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, top + 24, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ordonnances',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                          fontFamily: 'Sora', color: AppColors.foreground)),
                  const SizedBox(height: 4),
                  const Text('Espace pharmacien — chiffrez les demandes reçues.',
                      style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
                ],
              ),
            ),
          ),

          // ── À traiter ────────────────────────────────────
          if (_n.inbox.isNotEmpty)
            _Section(
              title: 'À traiter',
              items: _n.inbox,
              openId: _openId,
              onToggle: (id) => setState(() => _openId = _openId == id ? null : id),
              notifier: _n,
            ),

          // ── Devis envoyés ────────────────────────────────
          if (_n.quoted.isNotEmpty)
            _Section(
              title: 'Devis envoyés',
              items: _n.quoted,
              openId: _openId,
              onToggle: (id) => setState(() => _openId = _openId == id ? null : id),
              notifier: _n,
            ),

          // ── Payées ───────────────────────────────────────
          if (_n.done.isNotEmpty)
            _Section(
              title: 'Payées',
              items: _n.done,
              openId: _openId,
              onToggle: (id) => setState(() => _openId = _openId == id ? null : id),
              notifier: _n,
            ),

          if (_n.prescriptions.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Aucune ordonnance reçue pour le moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.mutedForeground)),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomNavigationBar: MerchantBottomNav(
          currentIndex: widget.currentNavIndex, onTap: widget.onNavTap),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<PrescriptionRow> items;
  final String? openId;
  final ValueChanged<String> onToggle;
  final PrescriptionsNotifier notifier;

  const _Section({
    required this.title, required this.items, required this.openId,
    required this.onToggle, required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title · ${items.length}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.foreground)),
            const SizedBox(height: 8),
            ...items.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PrescriptionCard(
                p: p,
                open: openId == p.id,
                onToggle: () => onToggle(p.id),
                notifier: notifier,
              ),
            )),
          ],
        ),
      ),
    );
  }
}

// ── PRESCRIPTION CARD ─────────────────────────────────────────────────────────
class _PrescriptionCard extends StatefulWidget {
  final PrescriptionRow p;
  final bool open;
  final VoidCallback onToggle;
  final PrescriptionsNotifier notifier;

  const _PrescriptionCard({
    required this.p, required this.open,
    required this.onToggle, required this.notifier,
  });

  @override
  State<_PrescriptionCard> createState() => _PrescriptionCardState();
}

class _PrescriptionCardState extends State<_PrescriptionCard> {
  List<String?> _signedUrls = [];
  late List<Map<String, dynamic>> _items;
  late final TextEditingController _deliveryFee;
  late final TextEditingController _readyMin;
  late final TextEditingController _note;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final p = widget.p;
    _items = p.quoteItems?.isNotEmpty == true
        ? List<Map<String, dynamic>>.from(p.quoteItems!)
        : [{'name': '', 'qty': 1, 'unit_price_xof': 0}];
    _deliveryFee = TextEditingController(text: '${p.deliveryFeeXof ?? 500}');
    _readyMin = TextEditingController(text: '${p.estimatedReadyMinutes ?? 20}');
    _note = TextEditingController(text: p.pharmacistNote ?? '');
  }

  @override
  void dispose() { _deliveryFee.dispose(); _readyMin.dispose(); _note.dispose(); super.dispose(); }

  Future<void> _loadUrls() async {
    final urls = await Future.wait(
      widget.p.imagePaths.map((path) => widget.notifier.getSignedUrl(path)),
    );
    if (mounted) setState(() => _signedUrls = urls);
  }

  @override
  void didUpdateWidget(_PrescriptionCard old) {
    super.didUpdateWidget(old);
    if (widget.open && !old.open) _loadUrls();
  }

  int get _subtotal => _items.fold<int>(
    0, (s, i) => s + (i['qty'] as int? ?? 1) * (i['unit_price_xof'] as int? ?? 0),
  );
  int get _total => _subtotal + (int.tryParse(_deliveryFee.text) ?? 0);

  Future<void> _sendQuote() async {
    final cleaned = _items.where((i) =>
        (i['name'] as String?)?.trim().isNotEmpty == true &&
        (i['unit_price_xof'] as int? ?? 0) > 0 &&
        (i['qty'] as int? ?? 0) > 0).toList();
    if (cleaned.isEmpty) {
      toast.error('Ajoutez au moins un produit'); return;
    }
    setState(() => _submitting = true);
    try {
      await widget.notifier.submitQuote(widget.p.id,
          items: cleaned,
          deliveryFee: int.tryParse(_deliveryFee.text) ?? 0,
          readyMin: int.tryParse(_readyMin.text) ?? 20,
          note: _note.text.trim().isEmpty ? null : _note.text.trim());
      _snack(widget.p.status == 'quoted' ? 'Devis mis à jour' : 'Devis envoyé au client');
    } catch (e) { toast.error('Échec d\'envoi'); }
    finally { if (mounted) setState(() => _submitting = false); }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.destructive : null,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 2),
            BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          // ── Titre card ────────────────────────────────────
          GestureDetector(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.image_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ordonnance #${p.id.substring(0, 6)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(
                          '${p.imagePaths.length} photo${p.imagePaths.length > 1 ? 's' : ''} · '
                          '${formatDateShort(p.createdAt)} ${formatTime(p.createdAt)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      (_statusLabel[p.status] ?? p.status).toUpperCase(),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                          color: AppColors.foreground, letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Contenu expandé ───────────────────────────────
          if (widget.open) ...[
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Note client
                  if (p.clientNote != null && p.clientNote!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('"${p.clientNote}"',
                          style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic,
                              color: AppColors.foreground)),
                    ),

                  // Photos ordonnance
                  if (_signedUrls.isNotEmpty)
                    GridView.count(
                      crossAxisCount: 3, shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 6, mainAxisSpacing: 6,
                      children: _signedUrls.map((url) => ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: url != null
                            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                                placeholder: (_, __) => Container(color: AppColors.secondary))
                            : Container(color: AppColors.secondary,
                                child: const Icon(Icons.broken_image_rounded,
                                    color: AppColors.mutedForeground)),
                      )).toList(),
                    ),

                  if (_signedUrls.isEmpty && p.imagePaths.isNotEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Bouton démarrer analyse
                  if (p.status == 'received') ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await widget.notifier.setStatus(p.id, 'analyzing');
                        },
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        child: const Text("Démarrer l'analyse",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                color: AppColors.foreground)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Formulaire devis
                  if (p.status != 'paid' && p.status != 'cancelled') ...[
                    const Text('PRODUITS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: AppColors.mutedForeground, letterSpacing: 0.8)),
                    const SizedBox(height: 8),

                    // Lignes médicaments
                    ...List.generate(_items.length, (idx) => Padding(
                      key: ValueKey('quote_item_$idx'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _QuoteItemRow(
                        key: ValueKey('quote_item_field_$idx'),
                        item: _items[idx],
                        onChanged: (updated) => setState(() => _items[idx] = updated),
                        onDelete: () => setState(() => _items.removeAt(idx)),
                      ),
                    )),

                    GestureDetector(
                      onTap: () => setState(() =>
                          _items.add({'name': '', 'qty': 1, 'unit_price_xof': 0})),
                      child: const Row(children: [
                        Icon(Icons.add_rounded, size: 14, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text('Ajouter un produit',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ]),
                    ),

                    const SizedBox(height: 12),

                    // Frais livraison + délai
                    Row(
                      children: [
                        Expanded(child: _QuoteField(
                          label: 'Frais livraison', controller: _deliveryFee,
                          type: TextInputType.number,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _QuoteField(
                          label: 'Prêt sous (min)', controller: _readyMin,
                          type: TextInputType.number,
                        )),
                      ],
                    ),

                    const SizedBox(height: 8),

                    _QuoteField(
                      label: 'Note pour le client (optionnel)',
                      controller: _note, maxLines: 2,
                    ),

                    const SizedBox(height: 12),

                    // Total devis
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total devis',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                          Text(formatXOF(_total),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                  fontFamily: 'Sora', color: AppColors.primary)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Bouton envoyer devis
                    SizedBox(
                      width: double.infinity, height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _sendQuote,
                        icon: _submitting
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(
                          p.status == 'quoted' ? 'Mettre à jour le devis' : 'Envoyer le devis',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                      ),
                    ),
                  ],

                  // Payée
                  if (p.status == 'paid')
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(children: [
                        Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
                        SizedBox(width: 8),
                        Text('Paiement reçu — préparer la commande.',
                            style: TextStyle(fontSize: 12, color: AppColors.success,
                                fontWeight: FontWeight.w700)),
                      ]),
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

// ── PETITS WIDGETS ────────────────────────────────────────────────────────────
class _QuoteItemRow extends StatefulWidget {
  final Map<String, dynamic> item;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  const _QuoteItemRow({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_QuoteItemRow> createState() => _QuoteItemRowState();
}

class _QuoteItemRowState extends State<_QuoteItemRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    // Créés UNE SEULE FOIS ici — plus jamais recréés pendant la frappe.
    _nameCtrl = TextEditingController(text: widget.item['name'] as String? ?? '');
    final price = widget.item['unit_price_xof'] as int? ?? 0;
    _priceCtrl = TextEditingController(text: price != 0 ? '$price' : '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Nom médicament
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              onChanged: (v) => widget.onChanged({...item, 'name': v}),
              decoration: const InputDecoration(
                hintText: 'Nom du médicament',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          // Quantité
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => widget.onChanged({
                  ...item,
                  'qty': ((item['qty'] as int? ?? 1) - 1).clamp(1, 99),
                }),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: AppColors.card,
                      borderRadius: BorderRadius.circular(999)),
                  child: const Icon(Icons.remove_rounded, size: 12),
                ),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  '${item['qty'] ?? 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              GestureDetector(
                onTap: () => widget.onChanged({...item, 'qty': (item['qty'] as int? ?? 1) + 1}),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999)),
                  child: const Icon(Icons.add_rounded, size: 12, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          // Prix
          SizedBox(
            width: 72,
            child: TextField(
              controller: _priceCtrl,
              onChanged: (v) => widget.onChanged({...item, 'unit_price_xof': int.tryParse(v) ?? 0}),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: 'Prix',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          // Supprimer
          GestureDetector(
            onTap: widget.onDelete,
            child: const Icon(Icons.delete_rounded, size: 16, color: AppColors.destructive),
          ),
        ],
      ),
    );
  }
}

class _QuoteField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType type;
  final int maxLines;

  const _QuoteField({
    required this.label, required this.controller,
    this.type = TextInputType.text, this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                color: AppColors.mutedForeground, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: type,
          maxLines: maxLines,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}