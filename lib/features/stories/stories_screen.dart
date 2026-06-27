import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/merchant_bottom_nav.dart';

SupabaseClient get _db => Supabase.instance.client;

// Limites — miroir des specs FE-21
const _maxImages = 5;
const _maxImagesNoVideo = 7;
const _maxVideoSeconds = 90; // 1min30

// ── Notifier ──────────────────────────────────────────────────────────────────
class StoriesNotifier extends ChangeNotifier {
  String? merchantId;
  String? userId;
  List<String> imageUrls = [];   // URLs publiques stockées en DB
  String? videoUrl;              // URL publique vidéo
  bool loading = true;
  bool saving = false;
  String? error;

  StoriesNotifier() { _init(); }

  Future<void> _init() async {
    final user = _db.auth.currentUser;
    if (user == null) { loading = false; notifyListeners(); return; }
    userId = user.id;

    final m = await _db
        .from('merchants')
        .select('id, story_images, story_video_url')
        .eq('owner_id', user.id)
        .maybeSingle();

    if (m != null) {
      merchantId = m['id'] as String;
      imageUrls = (m['story_images'] as List<dynamic>? ?? []).cast<String>();
      videoUrl = m['story_video_url'] as String?;
    }

    loading = false;
    notifyListeners();
  }

  // ── Upload image ──────────────────────────────────────────
  Future<String?> uploadImage(Uint8List bytes, String ext) async {
    if (userId == null || merchantId == null) return 'Non connecté';

    final hasVideo = videoUrl != null;
    final limit = hasVideo ? _maxImages : _maxImagesNoVideo;
    if (imageUrls.length >= limit) {
      return hasVideo
          ? 'Maximum $_maxImages images avec une vidéo'
          : 'Maximum $_maxImagesNoVideo images sans vidéo';
    }

    saving = true;
    notifyListeners();

    try {
      final path = 'stories/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('stories').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
      );
      final url = _db.storage.from('stories').getPublicUrl(path);
      imageUrls = [...imageUrls, url];
      await _saveToDb();
      return null; // succès
    } catch (e) {
      error = e.toString();
      return e.toString();
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  // ── Upload vidéo ──────────────────────────────────────────
  Future<String?> uploadVideo(Uint8List bytes, String ext) async {
    if (userId == null || merchantId == null) return 'Non connecté';
    if (videoUrl != null) return 'Une vidéo existe déjà — supprimez-la d\'abord';
    if (imageUrls.length > _maxImages) {
      return 'Avec une vidéo, maximum $_maxImages images. Supprimez ${imageUrls.length - _maxImages} image(s).';
    }

    saving = true;
    notifyListeners();

    try {
      final path = 'stories/$userId/video_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from('stories').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(
          contentType: ext == 'mp4' ? 'video/mp4' : 'video/quicktime',
          upsert: false,
        ),
      );
      videoUrl = _db.storage.from('stories').getPublicUrl(path);
      await _saveToDb();
      return null;
    } catch (e) {
      error = e.toString();
      return e.toString();
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  // ── Supprimer image ───────────────────────────────────────
  Future<String?> deleteImage(int index) async {
    if (index < 0 || index >= imageUrls.length) return null;
    saving = true;
    notifyListeners();

    try {
      final url = imageUrls[index];
      // Extraire le path depuis l'URL publique
      final path = _pathFromUrl(url);
      if (path != null) {
        await _db.storage.from('stories').remove([path]);
      }
      imageUrls = [...imageUrls]..removeAt(index);
      await _saveToDb();
      return null;
    } catch (e) {
      error = e.toString();
      return e.toString();
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  // ── Supprimer vidéo ───────────────────────────────────────
  Future<String?> deleteVideo() async {
    if (videoUrl == null) return null;
    saving = true;
    notifyListeners();

    try {
      final path = _pathFromUrl(videoUrl!);
      if (path != null) {
        await _db.storage.from('stories').remove([path]);
      }
      videoUrl = null;
      await _saveToDb();
      return null;
    } catch (e) {
      error = e.toString();
      return e.toString();
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  // ── Réordonner images (drag) ──────────────────────────────
  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [...imageUrls];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    imageUrls = list;
    notifyListeners();
    await _saveToDb();
  }

  // ── Persister en DB ───────────────────────────────────────
  Future<void> _saveToDb() async {
    if (merchantId == null) return;
    await _db.from('merchants').update({
      'story_images': imageUrls,
      'story_video_url': videoUrl,
    }).eq('id', merchantId!);
  }

  // ── Helper : extraire le path depuis l'URL publique Storage ──
  String? _pathFromUrl(String url) {
    // URL publique : .../storage/v1/object/public/stories/PATH
    final marker = '/object/public/stories/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;
    return url.substring(idx + marker.length);
  }

  int get maxImages => videoUrl != null ? _maxImages : _maxImagesNoVideo;

  @override
  void dispose() => super.dispose();
}

// ── STORIES SCREEN ────────────────────────────────────────────────────────────
class StoriesScreen extends StatefulWidget {
  final int currentNavIndex;
  final ValueChanged<int> onNavTap;
  final VoidCallback onGoToDashboard;

  const StoriesScreen({
    super.key,
    required this.currentNavIndex,
    required this.onNavTap,
    required this.onGoToDashboard,
  });

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  late final StoriesNotifier _n;
  int? _lightboxIndex; // null = fermé
  bool _lightboxIsVideo = false;

  @override
  void initState() {
    super.initState();
    _n = StoriesNotifier();
    _n.addListener(() => setState(() {}));
  }

  @override
  void dispose() { _n.dispose(); super.dispose(); }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.destructive : null,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Picker image ──────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    final err = await _n.uploadImage(bytes, ext.isEmpty ? 'jpg' : ext);
    if (err != null) _snack(err, error: true);
    else _snack('Photo ajoutée');
  }

  // ── Picker vidéo ──────────────────────────────────────────
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: _maxVideoSeconds),
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    final err = await _n.uploadVideo(bytes, ext.isEmpty ? 'mp4' : ext);
    if (err != null) _snack(err, error: true);
    else _snack('Vidéo ajoutée');
  }

  // ── Confirmer suppression ─────────────────────────────────
  Future<void> _confirmDeleteImage(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer cette photo ?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Sora')),
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
    final err = await _n.deleteImage(index);
    if (err != null) _snack(err, error: true);
    else _snack('Photo supprimée');
  }

  Future<void> _confirmDeleteVideo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer la vidéo ?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Sora')),
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
    final err = await _n.deleteVideo();
    if (err != null) _snack(err, error: true);
    else _snack('Vidéo supprimée');
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final hasVideo = _n.videoUrl != null;
    final imgCount = _n.imageUrls.length;
    final maxImg = _n.maxImages;
    final canAddImage = imgCount < maxImg;
    final canAddVideo = !hasVideo;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── HEADER ──────────────────────────────────────
              SliverToBoxAdapter(
                child: _StoriesHeader(
                  topPadding: top,
                  onBack: widget.onGoToDashboard,
                  imageCount: imgCount,
                  maxImages: maxImg,
                  hasVideo: hasVideo,
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── RÈGLES ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _RulesCard(hasVideo: hasVideo),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── LOADING ──────────────────────────────────────
              if (_n.loading)
                const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2),
                    ),
                  ),
                ),

              // ── BOUTONS D'AJOUT ──────────────────────────────
              if (!_n.loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        // Ajouter photo
                        Expanded(
                          child: _AddButton(
                            icon: Icons.add_photo_alternate_rounded,
                            label: 'Ajouter une photo',
                            hint: '$imgCount / $maxImg',
                            enabled: canAddImage && !_n.saving,
                            onTap: _pickImage,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Ajouter vidéo
                        Expanded(
                          child: _AddButton(
                            icon: Icons.video_call_rounded,
                            label: 'Ajouter une vidéo',
                            hint: hasVideo ? 'Déjà ajoutée' : 'Max 1min30',
                            enabled: canAddVideo && !_n.saving,
                            onTap: _pickVideo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // ── TITRE GALERIE ────────────────────────────────
              if (!_n.loading && (imgCount > 0 || hasVideo))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Publications ($imgCount${hasVideo ? ' + 1 vidéo' : ''})',
                          style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700,
                            fontFamily: 'Sora', color: AppColors.foreground,
                          ),
                        ),
                        if (_n.saving)
                          const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                      ],
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── GRILLE IMAGES (réordonnables) ────────────────
              if (!_n.loading && imgCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ReorderableWrap(
                      images: _n.imageUrls,
                      onReorder: _n.reorder,
                      onDelete: _confirmDeleteImage,
                      onTap: (i) => setState(() {
                        _lightboxIndex = i;
                        _lightboxIsVideo = false;
                      }),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // ── VIDÉO ────────────────────────────────────────
              if (!_n.loading && hasVideo)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _VideoCard(
                      videoUrl: _n.videoUrl!,
                      onDelete: _confirmDeleteVideo,
                      onPreview: () => setState(() {
                        _lightboxIndex = 0;
                        _lightboxIsVideo = true;
                      }),
                    ),
                  ),
                ),

              // ── ÉTAT VIDE ────────────────────────────────────
              if (!_n.loading && imgCount == 0 && !hasVideo)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.collections_rounded,
                                color: AppColors.primary, size: 26),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucune publication',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                fontFamily: 'Sora', color: AppColors.foreground),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ajoutez des photos et une vidéo pour attirer les clients sur votre fiche.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),

          // ── LIGHTBOX IMAGES ──────────────────────────────────
          if (_lightboxIndex != null && !_lightboxIsVideo)
            _ImageLightbox(
              images: _n.imageUrls,
              startIndex: _lightboxIndex!,
              onClose: () => setState(() => _lightboxIndex = null),
            ),

          // ── LIGHTBOX VIDÉO ───────────────────────────────────
          if (_lightboxIndex != null && _lightboxIsVideo && _n.videoUrl != null)
            _VideoLightbox(
              videoUrl: _n.videoUrl!,
              onClose: () => setState(() => _lightboxIndex = null),
            ),
        ],
      ),
      bottomNavigationBar: MerchantBottomNav(
        currentIndex: widget.currentNavIndex,
        onTap: widget.onNavTap,
      ),
    );
  }
}

// ── HEADER ────────────────────────────────────────────────────────────────────
class _StoriesHeader extends StatelessWidget {
  final double topPadding;
  final VoidCallback onBack;
  final int imageCount;
  final int maxImages;
  final bool hasVideo;

  const _StoriesHeader({
    required this.topPadding, required this.onBack,
    required this.imageCount, required this.maxImages, required this.hasVideo,
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
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.headerOverlay, shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                ),
              ),
              const Text('Espace Marchand',
                  style: TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Stories & Publications',
              style: TextStyle(color: Colors.white, fontSize: 24,
                  fontWeight: FontWeight.w700, fontFamily: 'Sora')),
          const SizedBox(height: 4),
          const Text(
            'Vos publications apparaissent sur votre fiche commerce.',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 16),
          // KPIs
          Row(
            children: [
              Expanded(child: _HeaderKpi(
                icon: Icons.image_rounded,
                label: 'Photos',
                value: '$imageCount / $maxImages',
              )),
              const SizedBox(width: 8),
              Expanded(child: _HeaderKpi(
                icon: Icons.videocam_rounded,
                label: 'Vidéo',
                value: hasVideo ? 'Ajoutée' : 'Aucune',
              )),
              const SizedBox(width: 8),
              Expanded(child: _HeaderKpi(
                icon: Icons.timer_rounded,
                label: 'Durée max',
                value: '1min30',
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderKpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeaderKpi({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.headerOverlay,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13,
                  fontWeight: FontWeight.w700, fontFamily: 'Sora')),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

// ── RÈGLES ────────────────────────────────────────────────────────────────────
class _RulesCard extends StatelessWidget {
  final bool hasVideo;
  const _RulesCard({required this.hasVideo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primary),
              SizedBox(width: 6),
              Text('Règles de publication',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 8),
          _Rule(text: hasVideo
              ? '5 images maximum avec une vidéo'
              : '7 images maximum sans vidéo'),
          _Rule(text: '1 vidéo maximum, durée max 1min30'),
          _Rule(text: 'Vous pouvez réordonner les photos en les glissant'),
          _Rule(text: 'Les publications sont visibles immédiatement sur votre fiche'),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final String text;
  const _Rule({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  ', style: TextStyle(color: AppColors.primary, fontSize: 12)),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 11, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

// ── BOUTON AJOUT ──────────────────────────────────────────────────────────────
class _AddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onTap;

  const _AddButton({
    required this.icon, required this.label, required this.hint,
    required this.enabled, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: enabled ? AppColors.primary.withOpacity(0.5) : AppColors.border,
              width: enabled ? 1.5 : 0.5,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x0A000000), blurRadius: 2),
              BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: enabled ? AppColors.primarySoft : AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: enabled ? AppColors.primary : AppColors.mutedForeground,
                    size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: enabled ? AppColors.foreground : AppColors.mutedForeground,
                  )),
              const SizedBox(height: 2),
              Text(hint,
                  style: const TextStyle(fontSize: 10, color: AppColors.mutedForeground)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── GRILLE RÉORDONNABLES ──────────────────────────────────────────────────────
class ReorderableWrap extends StatelessWidget {
  final List<String> images;
  final Future<void> Function(int, int) onReorder;
  final Future<void> Function(int) onDelete;
  final void Function(int) onTap;

  const ReorderableWrap({
    super.key,
    required this.images, required this.onReorder,
    required this.onDelete, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      onReorder: onReorder,
      buildDefaultDragHandles: false,
      itemBuilder: (context, i) {
        return Padding(
          key: ValueKey(images[i]),
          padding: const EdgeInsets.only(bottom: 10),
          child: _ImageTile(
            url: images[i],
            index: i,
            onTap: () => onTap(i),
            onDelete: () => onDelete(i),
          ),
        );
      },
    );
  }
}

class _ImageTile extends StatelessWidget {
  final String url;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ImageTile({
    required this.url, required this.index,
    required this.onTap, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2),
          BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image
            GestureDetector(
              onTap: onTap,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: AppColors.secondary,
                  child: const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.secondary,
                  child: const Icon(Icons.broken_image_rounded,
                      color: AppColors.mutedForeground),
                ),
              ),
            ),
            // Gradient bas
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 60,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xB3000000), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Numéro
            Positioned(
              bottom: 8, left: 12,
              child: Text(
                'Photo ${index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
            // Bouton supprimer
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.destructive,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
            // Handle drag
            Positioned(
              top: 8, left: 8,
              child: ReorderableDragStartListener(
                index: index,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.drag_handle_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── VIDÉO CARD ────────────────────────────────────────────────────────────────
class _VideoCard extends StatelessWidget {
  final String videoUrl;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  const _VideoCard({
    required this.videoUrl, required this.onDelete, required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2),
          BoxShadow(color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Aperçu placeholder vidéo
          GestureDetector(
            onTap: onPreview,
            child: Container(
              width: 80, height: 60,
              decoration: BoxDecoration(
                color: AppColors.foreground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.play_circle_rounded,
                  color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Vidéo de la boutique',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.foreground)),
                const SizedBox(height: 2),
                const Text('Durée max : 1min30',
                    style: TextStyle(fontSize: 11, color: AppColors.mutedForeground)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onPreview,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Aperçu',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                ),
              ],
            ),
          ),
          // Supprimer
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.destructive.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_rounded, color: AppColors.destructive, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ── LIGHTBOX IMAGES ───────────────────────────────────────────────────────────
class _ImageLightbox extends StatefulWidget {
  final List<String> images;
  final int startIndex;
  final VoidCallback onClose;

  const _ImageLightbox({
    required this.images, required this.startIndex, required this.onClose,
  });

  @override
  State<_ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<_ImageLightbox> {
  late final PageController _page;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.startIndex;
    _page = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() { _page.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.95),
        child: Stack(
          children: [
            // Swipe images
            PageView.builder(
              controller: _page,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => Center(
                child: CachedNetworkImage(
                  imageUrl: widget.images[i],
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              ),
            ),
            // Fermer
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
            // Compteur
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (i) => Container(
                  width: i == _current ? 20 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _current ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── LIGHTBOX VIDÉO ────────────────────────────────────────────────────────────
// Note : lecture vidéo native nécessite le package video_player.
// En attendant, on affiche l'URL et un bouton pour ouvrir dans le navigateur.
class _VideoLightbox extends StatelessWidget {
  final String videoUrl;
  final VoidCallback onClose;

  const _VideoLightbox({required this.videoUrl, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withOpacity(0.95),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_rounded, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Aperçu vidéo',
                    style: TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w700, fontFamily: 'Sora'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ajoutez video_player à pubspec.yaml\npour la lecture intégrée.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  // URL copiable
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      videoUrl,
                      style: const TextStyle(color: Colors.white60, fontSize: 10),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Fermer
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
