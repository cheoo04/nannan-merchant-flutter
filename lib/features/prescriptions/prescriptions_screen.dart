// --- Fichier : lib/features/prescriptions/prescriptions_screen.dart ---
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/a_nan_nan_api_client.dart';
import '../../core/services/a_nan_nan_services.dart';
import '../../core/services/neon_session.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';
import '../../shared/widgets/notification_bell_button.dart';

// ── Modèle ────────────────────────────────────────────────────────────────────
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
  final String? orderId;
  final DateTime createdAt;

  const PrescriptionRow({
    required this.id,
    required this.clientId,
    required this.merchantId,
    required this.status,
    required this.imagePaths,
    this.clientNote,
    this.deliveryAddress,
    this.quoteItems,
    this.deliveryFeeXof,
    this.totalXof,
    this.estimatedReadyMinutes,
    this.pharmacistNote,
    this.orderId,
    required this.createdAt,
  });

  factory PrescriptionRow.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>>? items;
    if (j['quote_details'] != null) {
      try {
        final decoded = jsonDecode(j['quote_details']);
        if (decoded is List) {
          items =
              decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    } else if (j['quote_items'] != null) {
      items = (j['quote_items'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    final image = j['image_url'] as String?;
    final imagesList =
        (j['image_paths'] as List<dynamic>?)?.cast<String>() ?? [];
    if (image != null && image.isNotEmpty && !imagesList.contains(image)) {
      imagesList.insert(0, image);
    }

    int? total;
    if (j['quoted_amount'] != null) {
      total = double.tryParse(j['quoted_amount'].toString())?.round();
    } else if (j['total_xof'] != null) {
      total = j['total_xof'] as int?;
    }

    return PrescriptionRow(
      id: j['id'] as String,
      clientId: (j['patient_user_id'] ?? j['client_id'] ?? '') as String,
      merchantId: j['merchant_id'] as String? ?? '',
      status: j['status'] as String? ?? 'received',
      imagePaths: imagesList,
      clientNote: (j['notes'] ?? j['client_note']) as String?,
      deliveryAddress: j['delivery_address'] as String?,
      quoteItems: items,
      deliveryFeeXof: j['delivery_fee_xof'] as int?,
      totalXof: total,
      estimatedReadyMinutes: j['estimated_ready_minutes'] as int?,
      pharmacistNote: (j['quote_details'] is String && items == null)
          ? j['quote_details'] as String?
          : (j['pharmacist_note'] as String?),
      orderId: j['order_id'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }
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
  final _api = ANanNanApiClient();
  late final _service = PrescriptionService(_api);

  List<PrescriptionRow> prescriptions = [];
  bool loading = true;
  String? merchantId;

  PrescriptionsNotifier() {
    _init();
  }

  Future<void> _init() async {
    merchantId = NeonSession.merchantId;
    if (merchantId == null) {
      try {
        final mine = await MerchantService(_api).getMine();
        if (mine.isNotEmpty) {
          merchantId = mine.first['id'] as String?;
          NeonSession.setCurrentMerchant(mine.first);
        }
      } catch (_) {}
    }

    if (merchantId != null) {
      await load();
    } else {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (merchantId == null) return;
    try {
      final data = await _service.listForMerchant(merchantId!);
      prescriptions = data
          .map((e) => PrescriptionRow.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
    loading = false;
    notifyListeners();
  }

  List<PrescriptionRow> get inbox => prescriptions
      .where((p) => p.status == 'received' || p.status == 'analyzing')
      .toList();
  List<PrescriptionRow> get quoted => prescriptions
      .where((p) => p.status == 'quoted' || p.status == 'accepted')
      .toList();
  List<PrescriptionRow> get done =>
      prescriptions.where((p) => p.status == 'paid').toList();

  Future<String?> getSignedUrl(String path) async {
    return path;
  }

  Future<void> setStatus(String id, String status) async {
    if (status == 'cancelled') {
      await _service.reject(id, reason: 'Refusée par le pharmacien');
    }
    await load();
  }

  Future<void> submitQuote(
    String id, {
    required List<Map<String, dynamic>> items,
    required int readyMin,
    String? note,
  }) async {
    if (merchantId == null) return;
    final subtotal = items.fold<int>(
      0,
      (s, i) => s + (i['qty'] as int) * (i['unit_price_xof'] as int),
    );

    await _service.submitQuote(
      id,
      merchantId: merchantId!,
      quotedAmount: subtotal.toDouble(),
      details: jsonEncode(items),
    );
    await load();
  }
}

// ── ÉCRAN PRINCIPAL ───────────────────────────────────────────────────────────
class PrescriptionsScreen extends StatefulWidget {
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;
  final VoidCallback onGoToDashboard;
  final int unreadCount;
  final VoidCallback? onGoToNotifications;

  const PrescriptionsScreen({
    super.key,
    required this.currentNavIndex,
    required this.onNavTap,
    required this.onGoToDashboard,
    this.unreadCount = 0,
    this.onGoToNotifications,
  });

  @override
  State<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends State<PrescriptionsScreen> {
  late final PrescriptionsNotifier _n;
  String? _openId;
  String? _openSection;

  String get _defaultOpenSection {
    if (_n.inbox.isNotEmpty) return 'À traiter';
    if (_n.quoted.isNotEmpty) return 'Devis envoyés';
    if (_n.done.isNotEmpty) return 'Payées';
    return '';
  }

  void _toggleSection(String title) {
    final current = _openSection ?? _defaultOpenSection;
    setState(() => _openSection = current == title ? '' : title);
  }

  @override
  void initState() {
    super.initState();
    _n = PrescriptionsNotifier();
    _n.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _n.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    if (_n.loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
        ),
        bottomNavigationBar: MerchantBottomNav(
            currentIndex: widget.currentNavIndex,
            onTap: widget.onNavTap,
            isPharmacy: true),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _n.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _PrescriptionsHeader(
                topPadding: top,
                onBack: widget.onGoToDashboard,
                unreadCount: widget.unreadCount,
                onNotifications: widget.onGoToNotifications,
              ),
            ),
            if (_n.inbox.isNotEmpty)
              _Section(
                title: 'À traiter',
                items: _n.inbox,
                openId: _openId,
                onToggle: (id) =>
                    setState(() => _openId = _openId == id ? null : id),
                notifier: _n,
                onGoToOrders: () => widget.onNavTap(1),
                isOpen: (_openSection ?? _defaultOpenSection) == 'À traiter',
                onToggleSection: () => _toggleSection('À traiter'),
              ),
            if (_n.quoted.isNotEmpty)
              _Section(
                title: 'Devis envoyés',
                items: _n.quoted,
                openId: _openId,
                onToggle: (id) =>
                    setState(() => _openId = _openId == id ? null : id),
                notifier: _n,
                onGoToOrders: () => widget.onNavTap(1),
                isOpen:
                    (_openSection ?? _defaultOpenSection) == 'Devis envoyés',
                onToggleSection: () => _toggleSection('Devis envoyés'),
              ),
            if (_n.done.isNotEmpty)
              _Section(
                title: 'Payées',
                items: _n.done,
                openId: _openId,
                onToggle: (id) =>
                    setState(() => _openId = _openId == id ? null : id),
                notifier: _n,
                onGoToOrders: () => widget.onNavTap(1),
                isOpen: (_openSection ?? _defaultOpenSection) == 'Payées',
                onToggleSection: () => _toggleSection('Payées'),
              ),
            if (_n.prescriptions.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.medication_outlined,
                          size: 48, color: AppColors.mutedForeground),
                      SizedBox(height: 12),
                      Text('Aucune ordonnance reçue pour le moment.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: AppColors.mutedForeground)),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      bottomNavigationBar: MerchantBottomNav(
          currentIndex: widget.currentNavIndex,
          onTap: widget.onNavTap,
          isPharmacy: true),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _PrescriptionsHeader extends StatelessWidget {
  final double topPadding;
  final VoidCallback onBack;
  final int unreadCount;
  final VoidCallback? onNotifications;

  const _PrescriptionsHeader({
    required this.topPadding,
    required this.onBack,
    this.unreadCount = 0,
    this.onNotifications,
  });

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
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.headerOverlay,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              if (onNotifications != null)
                NotificationBellButton(
                    unreadCount: unreadCount, onTap: onNotifications!),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Ordonnances',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFamily: 'Sora',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Espace pharmacien',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Section ───────────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final List<PrescriptionRow> items;
  final String? openId;
  final ValueChanged<String> onToggle;
  final PrescriptionsNotifier notifier;
  final VoidCallback onGoToOrders;
  final bool isOpen;
  final VoidCallback onToggleSection;

  const _Section({
    required this.title,
    required this.items,
    required this.openId,
    required this.onToggle,
    required this.notifier,
    required this.onGoToOrders,
    required this.isOpen,
    required this.onToggleSection,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onToggleSection,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isOpen ? AppColors.primary : AppColors.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isOpen ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$title · ${items.length}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color:
                                isOpen ? Colors.white : AppColors.foreground)),
                    const SizedBox(width: 6),
                    Icon(
                      isOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: isOpen ? Colors.white : AppColors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (isOpen)
              ...items.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PrescriptionCard(
                      p: p,
                      open: openId == p.id,
                      onToggle: () => onToggle(p.id),
                      notifier: notifier,
                      onGoToOrders: onGoToOrders,
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// ── Carte ordonnance ──────────────────────────────────────────────────────────
class _PrescriptionCard extends StatefulWidget {
  final PrescriptionRow p;
  final bool open;
  final VoidCallback onToggle;
  final PrescriptionsNotifier notifier;
  final VoidCallback onGoToOrders;

  const _PrescriptionCard({
    required this.p,
    required this.open,
    required this.onToggle,
    required this.notifier,
    required this.onGoToOrders,
  });

  @override
  State<_PrescriptionCard> createState() => _PrescriptionCardState();
}

class _PrescriptionCardState extends State<_PrescriptionCard> {
  List<String?> _signedUrls = [];
  late List<Map<String, dynamic>> _items;
  late final TextEditingController _readyMin;
  late final TextEditingController _note;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final p = widget.p;
    _items = p.quoteItems?.isNotEmpty == true
        ? List<Map<String, dynamic>>.from(p.quoteItems!)
        : [
            {'name': '', 'qty': 1, 'unit_price_xof': 0}
          ];
    _readyMin = TextEditingController(text: '${p.estimatedReadyMinutes ?? 20}');
    _note = TextEditingController(text: p.pharmacistNote ?? '');
  }

  @override
  void dispose() {
    _readyMin.dispose();
    _note.dispose();
    super.dispose();
  }

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
        0,
        (s, i) =>
            s + (i['qty'] as int? ?? 1) * (i['unit_price_xof'] as int? ?? 0),
      );
  int get _total => _subtotal;

  Future<void> _sendQuote() async {
    final cleaned = _items
        .where((i) =>
            (i['name'] as String?)?.trim().isNotEmpty == true &&
            (i['unit_price_xof'] as int? ?? 0) > 0 &&
            (i['qty'] as int? ?? 0) > 0)
        .toList();
    if (cleaned.isEmpty) {
      toast.error('Ajoutez au moins un produit');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.notifier.submitQuote(
        widget.p.id,
        items: cleaned,
        readyMin: int.tryParse(_readyMin.text) ?? 20,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      toast.success(widget.p.status == 'quoted'
          ? 'Devis mis à jour'
          : 'Devis envoyé au client');
    } catch (_) {
      toast.error("Échec d'envoi");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openPhoto(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Ordonnance', style: TextStyle(fontSize: 14)),
        ),
        body: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2),
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.image_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ordonnance #${p.id.substring(0, 6)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.foreground)),
                        Text(
                          '${p.imagePaths.length} photo${p.imagePaths.length > 1 ? 's' : ''} · '
                          '${formatDateShort(p.createdAt)} ${formatTime(p.createdAt)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      (_statusLabel[p.status] ?? p.status).toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.foreground,
                          letterSpacing: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.open) ...[
            Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.clientNote != null && p.clientNote!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('"${p.clientNote}"',
                          style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: AppColors.foreground)),
                    ),
                  if (_signedUrls.isNotEmpty) ...[
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      children: _signedUrls.map((url) {
                        if (url == null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: AppColors.secondary,
                              child: const Icon(Icons.broken_image_rounded,
                                  color: AppColors.mutedForeground),
                            ),
                          );
                        }
                        return GestureDetector(
                          onTap: () => _openPhoto(context, url),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: AppColors.secondary),
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.secondary,
                                child: const Icon(Icons.broken_image_rounded,
                                    color: AppColors.mutedForeground),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 4),
                    const Text('Appuyez sur une photo pour agrandir',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.mutedForeground)),
                    const SizedBox(height: 12),
                  ],
                  if (_signedUrls.isEmpty && p.imagePaths.isNotEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                    ),
                  if (p.status != 'paid' && p.status != 'cancelled') ...[
                    const Text('PRODUITS',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.mutedForeground,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 8),
                    ...List.generate(
                        _items.length,
                        (idx) => Padding(
                              key: ValueKey('item_$idx'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _QuoteItemRow(
                                key: ValueKey('field_$idx'),
                                item: _items[idx],
                                onChanged: (updated) =>
                                    setState(() => _items[idx] = updated),
                                onDelete: () =>
                                    setState(() => _items.removeAt(idx)),
                              ),
                            )),
                    GestureDetector(
                      onTap: () => setState(() => _items
                          .add({'name': '', 'qty': 1, 'unit_price_xof': 0})),
                      child: const Row(children: [
                        Icon(Icons.add_rounded,
                            size: 14, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text('Ajouter un produit',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    _QuoteField(
                      label: 'Prêt sous (min)',
                      controller: _readyMin,
                      type: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    _QuoteField(
                      label: 'Note pour le client (optionnel)',
                      controller: _note,
                      maxLines: 2,
                      maxLength: 200,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total devis',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                          Text(formatXOF(_total),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Sora',
                                  color: AppColors.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient:
                              _submitting ? null : AppColors.gradientPrimary,
                          color: _submitting
                              ? AppColors.primary.withValues(alpha: 0.5)
                              : null,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _sendQuote,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded,
                                  size: 16, color: Colors.white),
                          label: Text(
                            p.status == 'quoted'
                                ? 'Mettre à jour le devis'
                                : 'Envoyer le devis',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999)),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (p.status == 'paid')
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(children: [
                            Icon(Icons.check_circle_rounded,
                                size: 16, color: AppColors.success),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  'Paiement reçu — préparer la commande.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ]),
                          if (p.orderId != null) ...[
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: widget.onGoToOrders,
                              child: Row(children: [
                                Text(
                                  'Commande #${p.orderId!.substring(0, 8).toUpperCase()}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.success,
                                      decoration: TextDecoration.underline),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_rounded,
                                    size: 12, color: AppColors.success),
                              ]),
                            ),
                          ],
                        ],
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

// ── Ligne médicament dans le formulaire devis ─────────────────────────────────
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
    _nameCtrl =
        TextEditingController(text: widget.item['name'] as String? ?? '');
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
        color: AppColors.secondary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              onChanged: (v) => widget.onChanged({...item, 'name': v}),
              decoration: const InputDecoration(
                hintText: 'Médicament',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepBtn(
                icon: Icons.remove_rounded,
                color: AppColors.card,
                iconColor: AppColors.foreground,
                onTap: () => widget.onChanged({
                  ...item,
                  'qty': ((item['qty'] as int? ?? 1) - 1).clamp(1, 99),
                }),
              ),
              SizedBox(
                width: 24,
                child: Text('${item['qty'] ?? 1}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              _StepBtn(
                icon: Icons.add_rounded,
                color: AppColors.primary,
                iconColor: Colors.white,
                onTap: () => widget.onChanged({
                  ...item,
                  'qty': (item['qty'] as int? ?? 1) + 1,
                }),
              ),
            ],
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 68,
            child: TextField(
              controller: _priceCtrl,
              onChanged: (v) => widget.onChanged({
                ...item,
                'unit_price_xof': int.tryParse(v) ?? 0,
              }),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: 'Prix',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: widget.onDelete,
            child: const Icon(Icons.delete_rounded,
                size: 16, color: AppColors.destructive),
          ),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  const _StepBtn({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 12, color: iconColor),
      ),
    );
  }
}

class _QuoteField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType type;
  final int maxLines;
  final int? maxLength;

  const _QuoteField({
    required this.label,
    required this.controller,
    this.type = TextInputType.text,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.mutedForeground,
                letterSpacing: 0.8)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: type,
          maxLines: maxLines,
          maxLength: maxLength,
          buildCounter: maxLength != null
              ? (_, {required currentLength, required isFocused, maxLength}) =>
                  isFocused
                      ? Text('$currentLength/$maxLength',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.mutedForeground))
                      : null
              : null,
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
