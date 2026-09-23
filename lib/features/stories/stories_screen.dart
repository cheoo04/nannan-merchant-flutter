// --- Fichier : lib/features/stories/stories_screen.dart ---
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/toast.dart';
import '../../core/utils/error_message.dart';
import '../../core/services/a_nan_nan_api_client.dart';
import '../../core/services/a_nan_nan_services.dart';
import '../../core/services/neon_session.dart';
import '../../shared/widgets/notification_bell_button.dart';

const _maxImages = 5;
const _maxImagesNoVideo = 7;
const _maxVideoSeconds = 90;

class MerchantStoryItem {
  final String id;
  final String mediaType;
  final String mediaUrl;
  final String? description;
  final int position;

  const MerchantStoryItem({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    this.description,
    required this.position,
  });

  factory MerchantStoryItem.fromJson(Map<String, dynamic> j) =>
      MerchantStoryItem(
        id: j['id'] as String,
        mediaType: j['media_type'] as String? ?? 'image',
        mediaUrl: j['media_url'] as String,
        description: j['description'] as String?,
        position: j['sort_order'] as int? ?? 0,
      );

  MerchantStoryItem copyWith({String? description, int? position}) =>
      MerchantStoryItem(
        id: id,
        mediaType: mediaType,
        mediaUrl: mediaUrl,
        description: description ?? this.description,
        position: position ?? this.position,
      );
}

class StoriesNotifier extends ChangeNotifier {
  final _api = ANanNanApiClient();
  late final _pubService = PublicationService(_api);

  String? merchantId;
  List<MerchantStoryItem> images = [];
  MerchantStoryItem? video;
  bool loading = true;
  bool saving = false;
  String? error;

  StoriesNotifier() {
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
      final rows = await _pubService.list(merchantId!, activeOnly: false);
      final items = rows
          .map((e) => MerchantStoryItem.fromJson(e as Map<String, dynamic>))
          .toList();

      images = items.where((e) => e.mediaType == 'image').toList();
      final videos = items.where((e) => e.mediaType == 'video').toList();
      video = videos.isNotEmpty ? videos.first : null;
      error = null;
    } catch (e) {
      error = friendlyError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String?> uploadImage(Uint8List bytes, String ext,
      {String? description}) async {
    if (merchantId == null) return 'Boutique introuvable';

    final hasVideo = video != null;
    final limit = hasVideo ? _maxImages : _maxImagesNoVideo;
    if (images.length >= limit) {
      return hasVideo
          ? 'Maximum $_maxImages images avec une vidéo'
          : 'Maximum $_maxImagesNoVideo images sans vidéo';
    }

    saving = true;
    notifyListeners();

    try {
      final filename = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final url = await _api.uploadFile(
        bytes: bytes,
        filename: filename,
        folder: 'publications',
      );

      final row = await _pubService.create(
        merchantId!,
        title: 'Publication',
        mediaUrl: url,
        mediaType: 'image',
        description: description,
      );

      images = [...images, MerchantStoryItem.fromJson(row)];
      return null;
    } catch (e) {
      final msg = friendlyError(e);
      error = msg;
      return msg;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<String?> uploadVideo(Uint8List bytes, String ext,
      {String? description}) async {
    if (merchantId == null) return 'Boutique introuvable';
    if (video != null) return 'Une vidéo existe déjà — supprimez-la d\'abord';
    if (images.length > _maxImages) {
      return 'Avec une vidéo, maximum $_maxImages images. Supprimez ${images.length - _maxImages} image(s).';
    }

    saving = true;
    notifyListeners();

    try {
      final filename = 'video_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final url = await _api.uploadFile(
        bytes: bytes,
        filename: filename,
        folder: 'publications',
      );

      final row = await _pubService.create(
        merchantId!,
        title: 'Vidéo',
        mediaUrl: url,
        mediaType: 'video',
        description: description,
      );

      video = MerchantStoryItem.fromJson(row);
      return null;
    } catch (e) {
      final msg = friendlyError(e);
      error = msg;
      return msg;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<String?> deleteImage(int index) async {
    if (index < 0 || index >= images.length) return null;
    saving = true;
    notifyListeners();

    try {
      final item = images[index];
      await _pubService.delete(item.id);
      images = [...images]..removeAt(index);
      return null;
    } catch (e) {
      final msg = friendlyError(e);
      error = msg;
      return msg;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<String?> deleteVideo() async {
    if (video == null) return null;
    saving = true;
    notifyListeners();

    try {
      await _pubService.delete(video!.id);
      video = null;
      return null;
    } catch (e) {
      final msg = friendlyError(e);
      error = msg;
      return msg;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [...images];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    images = list;
    notifyListeners();
  }

  Future<String?> updateDescription({
    required String id,
    required bool isVideo,
    String? text,
  }) async {
    saving = true;
    notifyListeners();
    try {
      await _api.patch('/api/v1/publications/$id', body: {'description': text});
      if (isVideo && video != null && video!.id == id) {
        video = video!.copyWith(description: text);
      } else {
        final idx = images.indexWhere((e) => e.id == id);
        if (idx != -1) {
          images = [...images];
          images[idx] = images[idx].copyWith(description: text);
        }
      }
      return null;
    } catch (e) {
      final msg = friendlyError(e);
      error = msg;
      return msg;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  int get maxImages => video != null ? _maxImages : _maxImagesNoVideo;
}

class StoriesScreen extends StatefulWidget {
  final VoidCallback onGoToDashboard;
  final int unreadCount;
  final VoidCallback? onGoToNotifications;

  const StoriesScreen({
    super.key,
    required this.onGoToDashboard,
    this.unreadCount = 0,
    this.onGoToNotifications,
  });

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  late final StoriesNotifier _n;
  int? _lightboxIndex;
  bool _lightboxIsVideo = false;

  @override
  void initState() {
    super.initState();
    _n = StoriesNotifier();
    _n.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _n.dispose();
    super.dispose();
  }

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
    if (err != null) {
      toast.error(err);
    } else {
      toast.success('Photo ajoutée');
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;

    final controller = VideoPlayerController.file(File(file.path));
    Duration? duration;
    try {
      await controller.initialize();
      duration = controller.value.duration;
    } catch (_) {
    } finally {
      await controller.dispose();
    }

    if (duration != null && duration.inSeconds > _maxVideoSeconds) {
      toast.error(
        'Vidéo trop longue (${duration.inSeconds}s) — maximum ${_maxVideoSeconds}s (1min30).',
      );
      return;
    }

    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    final err = await _n.uploadVideo(bytes, ext.isEmpty ? 'mp4' : ext);
    if (err != null) {
      toast.error(err);
    } else {
      toast.success('Vidéo ajoutée');
    }
  }

  Future<void> _confirmDeleteImage(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer cette photo ?',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Sora')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: const Text('Supprimer',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await _n.deleteImage(index);
    if (err != null) {
      toast.error(err);
    } else {
      toast.success('Photo supprimée');
    }
  }

  Future<void> _confirmDeleteVideo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer la vidéo ?',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Sora')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: const Text('Supprimer',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await _n.deleteVideo();
    if (err != null) {
      toast.error(err);
    } else {
      toast.success('Vidéo supprimée');
    }
  }

  Future<void> _editDescription({
    required String id,
    required bool isVideo,
    required String? current,
  }) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Description',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Sora')),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 200,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Décrivez cette publication…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Enregistrer',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result == null) return;
    final err = await _n.updateDescription(
      id: id,
      isVideo: isVideo,
      text: result.isEmpty ? null : result,
    );
    if (err != null) {
      toast.error(err);
    } else {
      toast.success('Description enregistrée');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final hasVideo = _n.video != null;
    final imgCount = _n.images.length;
    final maxImg = _n.maxImages;
    final canAddImage = imgCount < maxImg;
    final canAddVideo = !hasVideo;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _StoriesHeader(
                  topPadding: top,
                  onBack: widget.onGoToDashboard,
                  imageCount: imgCount,
                  maxImages: maxImg,
                  hasVideo: hasVideo,
                  unreadCount: widget.unreadCount,
                  onNotifications: widget.onGoToNotifications,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _RulesCard(hasVideo: hasVideo),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
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
              if (!_n.loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
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
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Sora',
                            color: AppColors.foreground,
                          ),
                        ),
                        if (_n.saving)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary),
                          ),
                      ],
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (!_n.loading && imgCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ReorderableWrap(
                      items: _n.images,
                      onReorder: _n.reorder,
                      onDelete: _confirmDeleteImage,
                      onTap: (i) => setState(() {
                        _lightboxIndex = i;
                        _lightboxIsVideo = false;
                      }),
                      onEditDescription: (item) => _editDescription(
                        id: item.id,
                        isVideo: false,
                        current: item.description,
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (!_n.loading && hasVideo)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _VideoCard(
                      videoUrl: _n.video!.mediaUrl,
                      description: _n.video!.description,
                      onDelete: _confirmDeleteVideo,
                      onPreview: () => setState(() {
                        _lightboxIndex = 0;
                        _lightboxIsVideo = true;
                      }),
                      onEditDescription: () => _editDescription(
                        id: _n.video!.id,
                        isVideo: true,
                        current: _n.video!.description,
                      ),
                    ),
                  ),
                ),
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
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: AppColors.primarySoft,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.collections_rounded,
                                color: AppColors.primary, size: 26),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucune publication',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Sora',
                                color: AppColors.foreground),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ajoutez des photos et une vidéo pour attirer les clients sur votre fiche.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.mutedForeground),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          if (_lightboxIndex != null && !_lightboxIsVideo)
            _ImageLightbox(
              images: _n.images.map((e) => e.mediaUrl).toList(),
              startIndex: _lightboxIndex!,
              onClose: () => setState(() => _lightboxIndex = null),
            ),
          if (_lightboxIndex != null && _lightboxIsVideo && _n.video != null)
            _VideoLightbox(
              videoUrl: _n.video!.mediaUrl,
              onClose: () => setState(() => _lightboxIndex = null),
            ),
        ],
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
  final int unreadCount;
  final VoidCallback? onNotifications;

  const _StoriesHeader({
    required this.topPadding,
    required this.onBack,
    required this.imageCount,
    required this.maxImages,
    required this.hasVideo,
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
              Row(
                children: [
                  const Text('Espace Marchand',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  if (onNotifications != null) ...[
                    const SizedBox(width: 10),
                    NotificationBellButton(
                        unreadCount: unreadCount, onTap: onNotifications!),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Stories & Publications',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Sora')),
          const SizedBox(height: 4),
          const Text(
            'Vos publications apparaissent sur votre fiche commerce.',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _HeaderKpi(
                icon: Icons.image_rounded,
                label: 'Photos',
                value: '$imageCount / $maxImages',
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _HeaderKpi(
                icon: Icons.videocam_rounded,
                label: 'Vidéo',
                value: hasVideo ? 'Ajoutée' : 'Aucune',
              )),
              const SizedBox(width: 8),
              const Expanded(
                  child: _HeaderKpi(
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

  const _HeaderKpi(
      {required this.icon, required this.label, required this.value});

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
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Sora')),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  final bool hasVideo;
  const _RulesCard({required this.hasVideo});

  @override
  Widget build(BuildContext context) {
    return Text(
      hasVideo
          ? '5 images max · 1 vidéo max (1min30) · glisser pour réordonner'
          : '7 images max · 1 vidéo max (1min30) · glisser pour réordonner',
      style: const TextStyle(
        fontSize: 11,
        color: AppColors.mutedForeground,
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onTap;

  const _AddButton({
    required this.icon,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onTap,
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
              color: enabled
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : AppColors.border,
              width: enabled ? 1.5 : 0.5,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x0A000000), blurRadius: 2),
              BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 16,
                  offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: enabled ? AppColors.primarySoft : AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color:
                        enabled ? AppColors.primary : AppColors.mutedForeground,
                    size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: enabled
                        ? AppColors.foreground
                        : AppColors.mutedForeground,
                  )),
              const SizedBox(height: 2),
              Text(hint,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.mutedForeground)),
            ],
          ),
        ),
      ),
    );
  }
}

class ReorderableWrap extends StatelessWidget {
  final List<MerchantStoryItem> items;
  final Future<void> Function(int, int) onReorder;
  final Future<void> Function(int) onDelete;
  final void Function(int) onTap;
  final void Function(MerchantStoryItem) onEditDescription;

  const ReorderableWrap({
    super.key,
    required this.items,
    required this.onReorder,
    required this.onDelete,
    required this.onTap,
    required this.onEditDescription,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      onReorderItem: (oldIndex, newIndex) => onReorder(oldIndex, newIndex),
      buildDefaultDragHandles: false,
      itemBuilder: (context, i) {
        final item = items[i];
        return Padding(
          key: ValueKey(item.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ImageTile(
                url: item.mediaUrl,
                index: i,
                onTap: () => onTap(i),
                onDelete: () => onDelete(i),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: GestureDetector(
                  onTap: () => onEditDescription(item),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_note_rounded,
                          size: 15, color: AppColors.mutedForeground),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (item.description != null &&
                                  item.description!.isNotEmpty)
                              ? item.description!
                              : 'Ajouter une description',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: (item.description != null &&
                                    item.description!.isNotEmpty)
                                ? FontStyle.normal
                                : FontStyle.italic,
                            color: (item.description != null &&
                                    item.description!.isNotEmpty)
                                ? AppColors.foreground
                                : AppColors.mutedForeground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
    required this.url,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2),
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
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
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
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
            Positioned(
              bottom: 8,
              left: 12,
              child: Text(
                'Photo ${index + 1}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.destructive,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_rounded,
                      color: Colors.white, size: 16),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: ReorderableDragStartListener(
                index: index,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
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

class _VideoCard extends StatelessWidget {
  final String videoUrl;
  final String? description;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  final VoidCallback onEditDescription;

  const _VideoCard({
    required this.videoUrl,
    required this.description,
    required this.onDelete,
    required this.onPreview,
    required this.onEditDescription,
  });

  @override
  Widget build(BuildContext context) {
    final hasDescription = description != null && description!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 2),
          BoxShadow(
              color: Color(0x0F000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onPreview,
            child: Container(
              width: 80,
              height: 60,
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
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground)),
                const SizedBox(height: 2),
                const Text('Durée max : 1min30',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.mutedForeground)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onEditDescription,
                  child: Row(
                    children: [
                      const Icon(Icons.edit_note_rounded,
                          size: 14, color: AppColors.mutedForeground),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          hasDescription
                              ? description!
                              : 'Ajouter une description',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: hasDescription
                                ? FontStyle.normal
                                : FontStyle.italic,
                            color: hasDescription
                                ? AppColors.foreground
                                : AppColors.mutedForeground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onPreview,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Aperçu',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.destructive.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_rounded,
                  color: AppColors.destructive, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageLightbox extends StatefulWidget {
  final List<String> images;
  final int startIndex;
  final VoidCallback onClose;

  const _ImageLightbox({
    required this.images,
    required this.startIndex,
    required this.onClose,
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
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.95),
        child: Stack(
          children: [
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
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    widget.images.length,
                    (i) => Container(
                          width: i == _current ? 20 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color:
                                i == _current ? Colors.white : Colors.white38,
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

class _VideoLightbox extends StatefulWidget {
  final String videoUrl;
  final VoidCallback onClose;

  const _VideoLightbox({required this.videoUrl, required this.onClose});

  @override
  State<_VideoLightbox> createState() => _VideoLightboxState();
}

class _VideoLightboxState extends State<_VideoLightbox> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller!.play();
      }).catchError((e) {
        if (!mounted) return;
        setState(() => _error = friendlyError(e));
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.95),
        child: Stack(
          children: [
            Center(
              child: _error != null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: Colors.white60, size: 40),
                          SizedBox(height: 12),
                          Text('Impossible de lire cette vidéo',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )
                  : !ready
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)
                      : GestureDetector(
                          onTap: () => setState(() {
                            c.value.isPlaying ? c.pause() : c.play();
                          }),
                          child: AspectRatio(
                            aspectRatio: c.value.aspectRatio,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(c),
                                if (!c.value.isPlaying)
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.play_arrow_rounded,
                                        color: Colors.white, size: 32),
                                  ),
                              ],
                            ),
                          ),
                        ),
            ),
            if (ready)
              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
