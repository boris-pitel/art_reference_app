import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reference_category.dart';
import '../services/category_service.dart';
import '../services/image_asset_service.dart';
import '../services/image_save_service.dart';
import '../services/image_share_service.dart';
import '../services/user_activity_logger.dart';
import '../widgets/home_button.dart';
import '../services/app_image_cache.dart';
import '../widgets/cached_image.dart';
import '../widgets/image_delivery.dart';
import 'help_screen.dart';
import 'image_details_screen.dart';
import 'recipient_picker_screen.dart';

class _LoadedImage {
  const _LoadedImage({
    required this.id,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.displayUrl,
    this.parentImageId,
    this.parentImageUrl,
  });

  final String id;
  final String imageUrl;
  final String? thumbnailUrl;
  final String? displayUrl;
  final String? parentImageId;
  final String? parentImageUrl;
}

class _DownloadedImage {
  const _DownloadedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  String get extension {
    if (mimeType == 'image/png') {
      return 'png';
    }

    return 'jpg';
  }
}

enum _ImageAction {
  edit,
  share,
  save,
  print,
  sendToFriend,
  selectMode,
  move,
  remove,
}

/// One entry in the image action list.
///
/// The same actions appear as a bottom sheet on mobile and a popup menu on
/// desktop. They were previously spelled out twice, once per presentation, with
/// nothing keeping them in step — so adding, removing or gating an action meant
/// remembering to edit both, and missing one would not fail to compile.
class _ImageActionEntry {
  const _ImageActionEntry({
    required this.action,
    required this.icon,
    required this.label,
    this.subtitle,
    this.isDestructive = false,
  });

  final _ImageAction action;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isDestructive;
}

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key, required this.category});

  final ReferenceCategory category;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen>
    with WidgetsBindingObserver {
  final ImagePicker _imagePicker = ImagePicker();

  late final ImageAssetService _imageAssetService;

  final List<_LoadedImage> _images = [];

  /// Every image URL on this screen is signed and stops working after an hour.
  /// Listing them again is the only way to get working ones.
  static const Duration _signedUrlLifetime = Duration(hours: 1);

  /// Comfortably inside that hour, so a screen returning to the foreground is
  /// refreshed before its URLs die rather than after a picture has failed.
  static const Duration _refreshAfter = Duration(minutes: 45);

  /// When the URLs now on screen were issued.
  DateTime? _urlsIssuedAt;

  /// Whether a failed thumbnail has already prompted a re-listing for this
  /// batch. One retry is a recovery; retrying on every failure would be a
  /// loop, because an image whose file is genuinely gone fails every time.
  bool _retriedAfterFailure = false;

  /// Thumbnails already reported, so a grid that rebuilds while scrolling
  /// writes one log line per broken image rather than one per rebuild.
  final Set<String> _reportedThumbnailFailures = {};

  bool _isLoading = true;
  bool _isUploading = false;

  String _uploadStatus = '';
  double? _uploadProgress;

  String? _openingImageId;
  String? _removingImageId;
  String? _sharingImageId;
  String? _savingImageId;
  String? _printingImageId;
  String? _sendingImageId;
  String? _movingImageId;
  String? _errorMessage;

  bool _isSelecting = false;
  bool _isBulkMoving = false;
  final Set<String> _selectedImageIds = <String>{};

  bool get _isBusy {
    return _isUploading ||
        _openingImageId != null ||
        _removingImageId != null ||
        _sharingImageId != null ||
        _savingImageId != null ||
        _printingImageId != null ||
        _sendingImageId != null ||
        _movingImageId != null ||
        _isBulkMoving;
  }

  /// The actions offered for one image, in order — the single definition
  /// behind both the mobile sheet and the desktop menu.
  List<_ImageActionEntry> _imageActions() {
    return [
      _ImageActionEntry(
        action: _ImageAction.edit,
        icon: Icons.edit_outlined,
        label: widget.category.isMyArt
            ? 'Edit parent details'
            : 'Edit details',
        subtitle: 'Open titles, notes, and image options',
      ),
      const _ImageActionEntry(
        action: _ImageAction.selectMode,
        icon: Icons.checklist_outlined,
        label: 'Select images',
        subtitle: 'Pick several images to move at once',
      ),
      // Omitted where Save opens the same share sheet, which would offer two
      // items here that do exactly the same thing.
      if (!ImageDelivery.shareAndSaveAreIdentical)
        const _ImageActionEntry(
          action: _ImageAction.share,
          icon: Icons.ios_share_outlined,
          label: 'Share',
        ),
      _ImageActionEntry(
        action: _ImageAction.save,
        icon: Icons.photo_library_outlined,
        label: ImageSaveService.actionLabel,
      ),
      const _ImageActionEntry(
        action: _ImageAction.print,
        icon: Icons.print_outlined,
        label: 'Print',
      ),
      const _ImageActionEntry(
        action: _ImageAction.sendToFriend,
        icon: Icons.person_add_alt_outlined,
        label: 'Send to friend',
      ),
      const _ImageActionEntry(
        action: _ImageAction.move,
        icon: Icons.drive_file_move_outline,
        label: 'Move...',
      ),
      const _ImageActionEntry(
        action: _ImageAction.remove,
        icon: Icons.delete_outline,
        label: 'Remove',
        isDestructive: true,
      ),
    ];
  }

  /// Renders one entry, shared by both presentations so an action cannot look
  /// different depending on which menu it appears in.
  Widget _imageActionTile(
    BuildContext tileContext,
    _ImageActionEntry entry, {
    required bool compact,
  }) {
    final errorColor = Theme.of(tileContext).colorScheme.error;

    return ListTile(
      contentPadding: compact ? EdgeInsets.zero : null,
      leading: Icon(entry.icon, color: entry.isDestructive ? errorColor : null),
      title: Text(
        entry.label,
        style: entry.isDestructive ? TextStyle(color: errorColor) : null,
      ),
      subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
    );
  }

  /// True when another action is already running, having said so.
  ///
  /// Every action on this screen shares one busy flag, and each used to return
  /// silently when it was set. A screen that was merely working then looked
  /// broken: the menu opened, the item looked live, and the tap did nothing.
  bool _rejectWhileBusy() {
    if (!_isBusy) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Still finishing the previous action…'),
        duration: Duration(seconds: 2),
      ),
    );

    return true;
  }

  bool get _cameraIsAvailable {
    if (kIsWeb) {
      return true;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _imageAssetService = ImageAssetService(Supabase.instance.client);

    _loadImages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  /// Re-lists the images when the app comes back after being away a while.
  ///
  /// This screen used to load once and never again: the URLs it was holding
  /// were signed for an hour, and nothing re-issued them. Leaving the app for
  /// lunch and returning to this screen therefore meant every picture not
  /// already on the device failed to load, while the cached ones carried on
  /// looking fine — which is why only some tiles ever broke.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state != AppLifecycleState.resumed) return;
    if (_isLoading || _isBusy) return;

    final issued = _urlsIssuedAt;
    if (issued == null) return;
    if (DateTime.now().difference(issued) < _refreshAfter) return;

    _loadImages();
  }

  /// A thumbnail that would not load.
  ///
  /// Nothing recorded this before, which is why a screen full of broken tiles
  /// left no trace in the logs and had to be diagnosed by reasoning rather
  /// than by evidence. The age of the URLs is included because an expired
  /// signature and a missing file look identical from here, and the age is
  /// what tells them apart.
  void _onThumbnailFailed(_LoadedImage image, Object error) {
    final issued = _urlsIssuedAt;
    final age = issued == null
        ? null
        : DateTime.now().difference(issued).inSeconds;

    if (_reportedThumbnailFailures.add(image.id)) {
      UserActivityLogger.instance.record(
        operation: 'image_thumbnail_view',
        status: 'failed',
        targetType: 'image',
        targetId: image.id,
        details: {
          'category': widget.category.databaseCode,
          'url_age_seconds': ?age,
          if (age != null)
            'url_expired': age >= _signedUrlLifetime.inSeconds,
          'retried': _retriedAfterFailure,
        },
        error: error,
      );
    }

    // Recover rather than only complain. Re-listing re-signs every URL, so one
    // pass repairs the whole grid instead of one tile at a time.
    if (_retriedAfterFailure || _isLoading || _isBusy) return;

    _retriedAfterFailure = true;

    // This arrives from an error widget's builder, so the frame is still being
    // laid out. Reloading here would rebuild the tree during a build; waiting
    // for the frame to finish is the difference between a recovery and a
    // crash.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _loadImages();
    });
  }

  Future<List<_LoadedImage>> _fetchImages() async {
    final imageInfoList = await _imageAssetService.listImages(widget.category);

    return imageInfoList
        .map(
          (imageInfo) => _LoadedImage(
            id: imageInfo.id,
            imageUrl: imageInfo.imageUrl,
            thumbnailUrl: imageInfo.thumbnailUrl,
            displayUrl: imageInfo.displayUrl,
            parentImageId: imageInfo.parentImageId,
            parentImageUrl: imageInfo.parentImageUrl,
          ),
        )
        .toList();
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final loadedImages = await _fetchImages();

      if (!mounted) {
        return;
      }

      setState(() {
        _images
          ..clear()
          ..addAll(loadedImages);

        // A fresh batch of signatures, so the clock restarts and the tiles
        // that failed against the old ones are worth reporting again.
        _urlsIssuedAt = DateTime.now();
        _reportedThumbnailFailures.clear();

        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _openHelp() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => const HelpScreen()));
  }

  Future<void> _addPhotoReference(ImageSource source) async {
    if (_rejectWhileBusy()) return;

    final sourceDescription = source == ImageSource.camera
        ? 'Opening camera...'
        : 'Opening photo library...';

    setState(() {
      _isUploading = true;
      _uploadStatus = sourceDescription;
    });

    try {
      late final List<XFile> selectedImages;
      if (source == ImageSource.gallery) {
        selectedImages = await _imagePicker.pickMultiImage();
      } else {
        final selectedImage = await _imagePicker.pickImage(source: source);
        selectedImages = selectedImage == null ? <XFile>[] : [selectedImage];
      }

      if (selectedImages.isEmpty) {
        return;
      }

      if (selectedImages.length > 1 &&
          !await _confirmMultipleSelection(selectedImages.length)) {
        return;
      }

      await _uploadSelectedImages(selectedImages);

      if (!mounted) {
        return;
      }

      return;
    } on FunctionException catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.status == 409
          ? 'This photo is already in this category.'
          : 'Unable to save the photo: ${error.details}';

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save the photo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
          _uploadProgress = null;
        });
      }
    }
  }

  Future<bool> _confirmMultipleSelection(int count) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Add $count photos?'),
            content: Text(
              'The photos will be added to ${widget.category.displayName}. '
              'You will see progress for each upload.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Add photos'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _uploadSelectedImages(List<XFile> files) async {
    final failures = <XFile>[];
    String? firstFailure;
    var saved = 0;
    for (var index = 0; index < files.length; index++) {
      if (!mounted) return;
      setState(() {
        _uploadProgress = index / files.length;
        _uploadStatus = 'Uploading ${index + 1} of ${files.length}…';
      });

      // Recorded before the file is even read. Everything the service logs
      // happens after the upload call, so a failure while reading the bytes —
      // which is where a very large photo is most likely to die — left no
      // trace at all, on any device.
      UserActivityLogger.instance.record(
        operation: 'image_upload',
        status: 'started',
        targetType: 'image',
        details: {
          'category': widget.category.databaseCode,
          'file_name': files[index].name,
        },
      );

      try {
        final bytes = await files[index].readAsBytes();
        await _imageAssetService.uploadImage(
          bytes,
          widget.category,
          originalFilename: files[index].name,
        );
        saved++;
      } catch (error) {
        // Previously discarded, which is why a failed upload could not be
        // explained afterwards by the user or the logs.
        final duplicate = ImageAssetService.isDuplicateRejection(error);

        UserActivityLogger.instance.record(
          operation: 'image_upload',
          status: duplicate ? 'cancelled' : 'failed',
          targetType: 'image',
          details: {
            'category': widget.category.databaseCode,
            'file_name': files[index].name,
            'stage': 'read_or_upload',
            if (duplicate) 'reason': 'duplicate',
          },
          error: error,
        );

        firstFailure ??= error.toString();
        failures.add(files[index]);
      }
    }
    if (!mounted) return;
    setState(() {
      _uploadProgress = 1;
      _uploadStatus = 'Refreshing ${widget.category.displayName}…';
    });
    await _loadImages();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? '$saved ${saved == 1 ? 'photo' : 'photos'} saved.'
              // Naming the reason: "1 failed" alone gave the user nothing to
              // act on and nothing to report.
              : '$saved saved; ${failures.length} failed.'
                    '${firstFailure == null ? '' : ' $firstFailure'}',
        ),
        duration: failures.isEmpty
            ? const Duration(seconds: 4)
            : const Duration(seconds: 12),
        action: failures.isEmpty
            ? null
            : SnackBarAction(
                label: 'Retry',
                onPressed: () => _retryFailedUploads(failures),
              ),
      ),
    );
  }

  Future<void> _retryFailedUploads(List<XFile> files) async {
    if (_rejectWhileBusy()) return;
    setState(() => _isUploading = true);
    try {
      await _uploadSelectedImages(files);
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatus = '';
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _openImageDetails(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    setState(() {
      _openingImageId = image.id;
    });

    try {
      final detailsImageId = widget.category.isMyArt
          ? image.parentImageId
          : image.id;
      final detailsImageUrl = widget.category.isMyArt
          ? image.parentImageUrl
          : image.imageUrl;
      // list-finished-artworks doesn't yet return a display derivative for
      // the parent reference, so that path falls back to the original.
      final detailsDisplayUrl = widget.category.isMyArt
          ? null
          : image.displayUrl;
      if (detailsImageId == null || detailsImageUrl == null) {
        _showMessage('The parent photo reference could not be opened.');
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => ImageDetailsScreen(
            imageId: detailsImageId,
            imageUrl: detailsImageUrl,
            displayUrl: detailsDisplayUrl,
            navigationItems: _images
                .map(
                  (item) => ImageDetailsNavigationItem(
                    imageId: widget.category.isMyArt
                        ? item.parentImageId ?? item.id
                        : item.id,
                    imageUrl: widget.category.isMyArt
                        ? item.parentImageUrl ?? item.imageUrl
                        : item.imageUrl,
                    displayUrl: widget.category.isMyArt
                        ? null
                        : item.displayUrl,
                  ),
                )
                .toList(growable: false),
            navigationIndex: _images.indexWhere((item) => item.id == image.id),
          ),
        ),
      );

      if (changed == true && mounted) {
        await _loadImages();
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingImageId = null;
        });
      }
    }
  }

  /// How long a single image download may take before it is abandoned.
  ///
  /// Generous, because these are full-resolution originals — a 48MP photo is
  /// over 10MB and a slow connection can legitimately need a minute. The point
  /// is to fail eventually rather than quickly.
  static const _downloadTimeout = Duration(minutes: 2);

  Future<_DownloadedImage> _downloadImage(_LoadedImage image) async {
    // Bounded because every action on this screen begins here, and the busy
    // flag set before it can only be cleared once this returns. Unbounded, a
    // stalled request left the whole screen silently inert until the user
    // navigated away and came back.
    final response = await http
        .get(Uri.parse(image.imageUrl))
        .timeout(
          _downloadTimeout,
          onTimeout: () => throw TimeoutException(
            'The image took too long to download.',
            _downloadTimeout,
          ),
        );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Image download failed with status ${response.statusCode}.',
      );
    }

    final bytes = response.bodyBytes;

    if (bytes.isEmpty) {
      throw StateError('The downloaded image is empty.');
    }

    return _DownloadedImage(
      bytes: bytes,
      mimeType: _detectMimeType(response.headers['content-type'], bytes),
    );
  }

  Future<void> _shareImage(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    setState(() {
      _sharingImageId = image.id;
    });

    try {
      final downloadedImage = await _downloadImage(image);

      if (!mounted) {
        return;
      }

      Rect? sharePositionOrigin;

      final renderObject = context.findRenderObject();

      if (renderObject is RenderBox && renderObject.hasSize) {
        final topLeft = renderObject.localToGlobal(Offset.zero);

        sharePositionOrigin = topLeft & renderObject.size;
      }

      await UserActivityLogger.instance.trace<void>(
        operation: 'image_share',
        targetType: 'image',
        targetId: image.id,
        action: () => ImageShareService.share(
          downloadedImage.bytes,
          fileName: 'art_reference_${image.id}.${downloadedImage.extension}',
          mimeType: downloadedImage.mimeType,
          subject: 'Painter Reference',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to share the reference: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sharingImageId = null;
        });
      }
    }
  }

  Future<void> _saveImageToPhotos(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    setState(() {
      _savingImageId = image.id;
    });

    try {
      // Traced because this is where silent failure lives: the photo library
      // can accept the file and discard it, reporting nothing back. A
      // 'started' with no matching end is the only trace such a save leaves.
      final result = await UserActivityLogger.instance.trace(
        operation: 'image_save',
        targetType: 'image',
        targetId: image.id,
        outcome: (result) => result.wasCancelled ? 'cancelled' : 'succeeded',
        action: () async {
          final downloadedImage = await _downloadImage(image);

          if (!mounted) throw StateError('The screen closed before saving.');

          return ImageDelivery.save(
            context,
            downloadedImage.bytes,
            fileName: 'art_reference_${image.id}.${downloadedImage.extension}',
          );
        },
      );

      if (!mounted || result.wasCancelled) {
        return;
      }

      _showMessage(
        result.path != null
            ? 'Reference saved to ${result.path}'
            : (kIsWeb ? 'Reference downloaded.' : 'Reference saved to Photos.'),
      );
    } on GalException catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to save the reference: ${error.type.message}');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to save the reference: $error');
    } finally {
      if (mounted) {
        setState(() {
          _savingImageId = null;
        });
      }
    }
  }

  Future<void> _printImage(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    setState(() {
      _printingImageId = image.id;
    });

    try {
      await UserActivityLogger.instance.trace<void>(
        operation: 'image_print',
        targetType: 'image',
        targetId: image.id,
        action: () async {
          final downloadedImage = await _downloadImage(image);

          if (!mounted) throw StateError('The screen closed before printing.');

          await ImageDelivery.printImage(
            context,
            downloadedImage.bytes,
            documentName: 'Painter Reference ${image.id}',
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to print the reference: $error');
    } finally {
      if (mounted) {
        setState(() {
          _printingImageId = null;
        });
      }
    }
  }

  Future<void> _sendToFriend(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    setState(() {
      _sendingImageId = image.id;
    });

    try {
      final downloadedImage = await _downloadImage(image);

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RecipientPickerScreen(
            imageBytes: downloadedImage.bytes,
            imageLabel: widget.category.displayName,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to prepare the image to send: $error');
    } finally {
      if (mounted) {
        setState(() {
          _sendingImageId = null;
        });
      }
    }
  }

  Future<void> _moveImageToAnotherCategory(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    setState(() {
      _movingImageId = image.id;
    });

    try {
      final categoryService = CategoryService(Supabase.instance.client);
      final allCategories = await categoryService.listCategories();
      final destinationCategories = allCategories
          .where(
            (category) =>
                category.databaseCode != widget.category.databaseCode,
          )
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      if (destinationCategories.isEmpty) {
        _showMessage('There is no other category to move this image to.');
        return;
      }

      final toCategory = await _pickDestinationCategory(destinationCategories);

      if (toCategory == null || !mounted) {
        return;
      }

      await _imageAssetService.moveImageToCategory(
        imageId: image.id,
        fromCategory: widget.category,
        toCategory: toCategory,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _images.removeWhere((existingImage) => existingImage.id == image.id);
      });

      _showMessage('Image moved to ${toCategory.displayName}.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to move image: $error');
    } finally {
      if (mounted) {
        setState(() {
          _movingImageId = null;
        });
      }
    }
  }

  Future<ReferenceCategory?> _pickDestinationCategory(
    List<ReferenceCategory> destinationCategories,
  ) {
    return showDialog<ReferenceCategory>(
      context: context,
      builder: (dialogContext) {
        ReferenceCategory? selected;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Move Reference'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current category: ${widget.category.displayName}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 18),
                    const Text('Move to'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ReferenceCategory>(
                      initialValue: selected,
                      decoration: const InputDecoration(
                        hintText: 'Choose a destination category',
                        border: OutlineInputBorder(),
                      ),
                      items: destinationCategories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category.displayName),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setDialogState(() {
                          selected = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(selected),
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Move'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _bulkMoveSelectedImages() async {
    if (_isBusy || _selectedImageIds.isEmpty) {
      return;
    }

    setState(() => _isBulkMoving = true);

    try {
      final categoryService = CategoryService(Supabase.instance.client);
      final allCategories = await categoryService.listCategories();
      final destinationCategories = allCategories
          .where(
            (category) => category.databaseCode != widget.category.databaseCode,
          )
          .toList(growable: false);

      if (!mounted) return;

      if (destinationCategories.isEmpty) {
        _showMessage('There is no other category to move these images to.');
        return;
      }

      final toCategory = await _pickDestinationCategory(destinationCategories);
      if (toCategory == null || !mounted) return;

      final movingIds = _selectedImageIds.toList(growable: false);
      final movedIds = <String>{};
      var failed = 0;
      for (final imageId in movingIds) {
        try {
          await _imageAssetService.moveImageToCategory(
            imageId: imageId,
            fromCategory: widget.category,
            toCategory: toCategory,
          );
          movedIds.add(imageId);
        } catch (error) {
          failed += 1;

          // The loop continues so one bad image cannot strand the rest, but
          // the reason used to be dropped here — leaving the user with a
          // count of failures and no way to find out why any of them failed.
          UserActivityLogger.instance.record(
            operation: 'image_move',
            status: 'failed',
            targetType: 'image',
            targetId: imageId,
            details: {'to_category': toCategory.displayName},
            error: error,
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _images.removeWhere((image) => movedIds.contains(image.id));
        _selectedImageIds.removeAll(movedIds);
        if (_selectedImageIds.isEmpty) _isSelecting = false;
      });

      _showMessage(
        failed == 0
            ? '${movedIds.length} ${movedIds.length == 1 ? 'image' : 'images'} moved to ${toCategory.displayName}.'
            : '${movedIds.length} moved to ${toCategory.displayName}; $failed failed.',
      );
    } catch (error) {
      if (mounted) _showMessage('Unable to move images: $error');
    } finally {
      if (mounted) setState(() => _isBulkMoving = false);
    }
  }

  String _detectMimeType(String? responseContentType, Uint8List bytes) {
    final normalizedHeader = responseContentType
        ?.split(';')
        .first
        .trim()
        .toLowerCase();

    if (normalizedHeader == 'image/jpeg' || normalizedHeader == 'image/png') {
      return normalizedHeader!;
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }

    return 'image/jpeg';
  }

  Future<void> _removeFromCategory(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    setState(() {
      _removingImageId = image.id;
    });

    try {
      await _imageAssetService.removeImageFromCategory(
        image.id,
        widget.category,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _images.removeWhere((existingImage) => existingImage.id == image.id);

        _removingImageId = null;
      });

      _showMessage('Reference removed.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _removingImageId = null;
      });

      _showMessage('Unable to remove reference: $error');
    }
  }

  Future<void> _handleImageAction(
    _ImageAction action,
    _LoadedImage image,
  ) async {
    switch (action) {
      case _ImageAction.edit:
        await _openImageDetails(image);
        return;
      case _ImageAction.share:
        await _shareImage(image);
        return;

      case _ImageAction.save:
        await _saveImageToPhotos(image);
        return;

      case _ImageAction.print:
        await _printImage(image);
        return;

      case _ImageAction.sendToFriend:
        await _sendToFriend(image);
        return;

      case _ImageAction.selectMode:
        _enterSelectModeWithImage(image);
        return;

      case _ImageAction.move:
        await _moveImageToAnotherCategory(image);
        return;

      case _ImageAction.remove:
        await _removeFromCategory(image);
        return;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _toggleSelecting() {
    if (_rejectWhileBusy()) return;
    setState(() {
      _isSelecting = !_isSelecting;
      if (!_isSelecting) _selectedImageIds.clear();
    });
  }

  void _toggleImageSelected(_LoadedImage image) {
    setState(() {
      if (!_selectedImageIds.remove(image.id)) {
        _selectedImageIds.add(image.id);
      }
    });
  }

  void _enterSelectModeWithImage(_LoadedImage image) {
    setState(() {
      _isSelecting = true;
      _selectedImageIds.add(image.id);
    });
  }

  Future<void> _showMobileActions(_LoadedImage image) async {
    if (_rejectWhileBusy()) return;

    final action = await showModalBottomSheet<_ImageAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in _imageActions())
                  InkWell(
                    onTap: () => Navigator.of(sheetContext).pop(entry.action),
                    child: _imageActionTile(
                      sheetContext,
                      entry,
                      compact: false,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (action != null && mounted) {
      await _handleImageAction(action, image);
    }
  }

  Future<void> _showDesktopActions(
    _LoadedImage image,
    Offset globalPosition,
  ) async {
    if (_rejectWhileBusy()) return;

    final overlay = Overlay.of(context).context.findRenderObject();

    if (overlay is! RenderBox) {
      return;
    }

    final action = await showMenu<_ImageAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final entry in _imageActions())
          PopupMenuItem(
            value: entry.action,
            child: _imageActionTile(context, entry, compact: true),
          ),
      ],
    );

    if (action != null && mounted) {
      await _handleImageAction(action, image);
    }
  }

  Future<void> _handleLongPress(_LoadedImage image) async {
    await HapticFeedback.selectionClick();

    if (!mounted) {
      return;
    }

    await _showMobileActions(image);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelecting
              ? '${_selectedImageIds.length} selected'
              : widget.category.displayName,
        ),
        leading: _isSelecting
            ? IconButton(
                onPressed: _isBulkMoving ? null : _toggleSelecting,
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
              )
            : null,
        actions: [
          if (!widget.category.isMyArt)
            IconButton(
              onPressed: _isLoading || (_isBusy && !_isSelecting)
                  ? null
                  : _toggleSelecting,
              icon: Icon(
                _isSelecting ? Icons.checklist : Icons.checklist_outlined,
              ),
              tooltip: _isSelecting ? 'Cancel selection' : 'Select images',
            ),
          if (!_isSelecting) ...[
            const HomeButton(),
            IconButton(
              onPressed: _openHelp,
              icon: const Icon(Icons.help_outline),
              tooltip: 'Help and About',
            ),
            IconButton(
              onPressed: _isLoading || _isBusy ? null : _loadImages,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody()),
          if (_isUploading) Positioned.fill(child: _buildUploadOverlay()),
        ],
      ),
      floatingActionButton: widget.category.isMyArt || _isSelecting
          ? null
          : _buildAddButtons(),
      bottomNavigationBar: _isSelecting ? _buildSelectionBar() : null,
    );
  }

  Widget _buildSelectionBar() {
    final hasSelection = _selectedImageIds.isNotEmpty;
    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isBulkMoving ? null : _toggleSelecting,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: !hasSelection || _isBulkMoving
                ? null
                : _bulkMoveSelectedImages,
            icon: _isBulkMoving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.drive_file_move_outline),
            label: Text('Move (${_selectedImageIds.length})'),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildAddButtons() {
    if (!_cameraIsAvailable) {
      return FloatingActionButton.extended(
        heroTag: 'galleryButton',
        onPressed: _isBusy
            ? null
            : () => _addPhotoReference(ImageSource.gallery),
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_isUploading ? 'Working...' : 'Add image'),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'galleryButton',
          onPressed: _isBusy
              ? null
              : () => _addPhotoReference(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Add image'),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'cameraButton',
          onPressed: _isBusy
              ? null
              : () => _addPhotoReference(ImageSource.camera),
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('Camera'),
        ),
      ],
    );
  }

  Widget _buildUploadOverlay() {
    return ColoredBox(
      color: Colors.black45,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _uploadProgress == null
                      ? const CircularProgressIndicator()
                      : LinearProgressIndicator(value: _uploadProgress),
                  const SizedBox(height: 20),
                  Text(
                    _uploadStatus.isEmpty ? 'Working...' : _uploadStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'You can leave successful items in place and retry only failures.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Unable to load photo references.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadImages,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_images.isEmpty) {
      return const Center(
        child: Text('No photo references yet.', style: TextStyle(fontSize: 20)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _images.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final image = _images[index];

        final isOpening = _openingImageId == image.id;
        final isRemoving = _removingImageId == image.id;
        final isSharing = _sharingImageId == image.id;
        final isSaving = _savingImageId == image.id;
        final isPrinting = _printingImageId == image.id;
        final isSending = _sendingImageId == image.id;
        final isMoving = _movingImageId == image.id;

        final isWorking =
            isOpening ||
            isRemoving ||
            isSharing ||
            isSaving ||
            isPrinting ||
            isSending ||
            isMoving;

        final isSelected = _selectedImageIds.contains(image.id);

        return GestureDetector(
          onLongPress: isWorking || _isSelecting
              ? null
              : () => _handleLongPress(image),
          onSecondaryTapDown: isWorking || _isSelecting
              ? null
              : (details) => _showDesktopActions(image, details.globalPosition),
          child: Material(
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: isWorking
                  ? null
                  : _isSelecting
                  ? () => _toggleImageSelected(image)
                  : () => _openImageDetails(image),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildThumbnail(image),
                  if (_isSelecting)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Checkbox(
                          value: isSelected,
                          onChanged: isWorking
                              ? null
                              : (_) => _toggleImageSelected(image),
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                          ),
                          checkColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  if (isSelected)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (isWorking)
                    Container(
                      color: Colors.black38,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              isRemoving
                                  ? 'Removing...'
                                  : isSharing
                                  ? 'Preparing...'
                                  : isSaving
                                  ? 'Saving...'
                                  : isPrinting
                                  ? 'Preparing print...'
                                  : isSending
                                  ? 'Preparing...'
                                  : isMoving
                                  ? 'Moving...'
                                  : 'Opening...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(_LoadedImage image) {
    final thumbnailUrl = image.thumbnailUrl;

    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      return _buildThumbnailPlaceholder();
    }

    return CachedImage(
      url: thumbnailUrl,
      cacheKey: AppImageCache.thumbnailKey(image.id),
      fit: BoxFit.cover,
      placeholder: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      onFailed: (error) => _onThumbnailFailed(image, error),
      errorWidget: (context, error) {
        return _buildThumbnailPlaceholder();
      },
    );
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 44,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
