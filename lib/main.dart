import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/reference_category.dart';
import 'navigation.dart';
import 'screens/category_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/help_screen.dart';
import 'screens/login_screen.dart';
import 'screens/maintenance_screen.dart';
import 'services/user_activity_logger.dart';
import 'screens/keyword_search_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/messaging_settings_screen.dart';
import 'screens/shared_image_import_screen.dart';
import 'services/category_service.dart';
import 'services/impersonation_controller.dart';
import 'services/library_home_cache.dart';
import 'services/image_asset_service.dart';
import 'services/messaging_service.dart';
import 'utils/performance_profiler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: 'env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final publishableKey = dotenv.env['SUPABASE_PUBLISHABLE_KEY'];

  if (supabaseUrl == null ||
      supabaseUrl.trim().isEmpty ||
      publishableKey == null ||
      publishableKey.trim().isEmpty) {
    throw StateError('Supabase configuration is missing from .env');
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: publishableKey);

  runApp(const ArtReferenceApp());
}

class ArtReferenceApp extends StatefulWidget {
  const ArtReferenceApp({super.key});

  @override
  State<ArtReferenceApp> createState() => _ArtReferenceAppState();
}

class _ArtReferenceAppState extends State<ArtReferenceApp> {
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<SharedMediaFile>>? _sharingSubscription;

  final Set<String> _handledSharedPaths = <String>{};

  Session? _session;
  String? _pendingSharedImagePath;

  bool _shareScreenIsOpen = false;
  bool _authStateIsReady = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  bool get _sharingIsSupported {
    if (kIsWeb) {
      return false;
    }

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _isSignedIn {
    return _session?.user.email?.trim().isNotEmpty == true;
  }

  @override
  void initState() {
    super.initState();

    _session = _supabase.auth.currentSession;
    _authStateIsReady = true;

    _initializeAuthListener();

    if (_sharingIsSupported) {
      _initializeSharingListener();
    }
  }

  void _initializeAuthListener() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (authState) {
        if (!mounted) {
          return;
        }

        final wasSignedIn = _isSignedIn;

        setState(() {
          _session = authState.session;
          _authStateIsReady = true;
        });

        final isNowSignedIn = _isSignedIn;

        if (!wasSignedIn && isNowSignedIn) {
          _openPendingShareWhenReady();
        }

        if (wasSignedIn && !isNowSignedIn) {
          _closeScreensAfterLogout();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Supabase authentication stream error: $error');
      },
    );
  }

  Future<void> _initializeSharingListener() async {
    _sharingSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          _handleSharedMedia,
          onError: (Object error) {
            debugPrint('Share intent stream error: $error');
          },
        );

    try {
      final initialMedia = await ReceiveSharingIntent.instance
          .getInitialMedia();
      await _handleSharedMedia(initialMedia);
    } catch (error) {
      debugPrint('Unable to read initial share intent: $error');
    }
  }

  Future<void> _handleSharedMedia(List<SharedMediaFile> sharedFiles) async {
    if (sharedFiles.isEmpty) {
      return;
    }

    SharedMediaFile? firstSharedImage;

    for (final sharedFile in sharedFiles) {
      if (sharedFile.type == SharedMediaType.image) {
        firstSharedImage = sharedFile;
        break;
      }
    }

    if (firstSharedImage == null) {
      await ReceiveSharingIntent.instance.reset();
      return;
    }

    final sharedPath = firstSharedImage.path.trim();

    if (sharedPath.isEmpty) {
      await ReceiveSharingIntent.instance.reset();
      return;
    }

    if (_handledSharedPaths.contains(sharedPath)) {
      await ReceiveSharingIntent.instance.reset();
      return;
    }

    _handledSharedPaths.add(sharedPath);

    setState(() {
      _pendingSharedImagePath = sharedPath;
    });

    await ReceiveSharingIntent.instance.reset();
    _openPendingShareWhenReady();
  }

  void _openPendingShareWhenReady() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isSignedIn) {
        return;
      }

      final sharedPath = _pendingSharedImagePath;
      final navigator = rootNavigatorKey.currentState;

      if (sharedPath == null || navigator == null || _shareScreenIsOpen) {
        return;
      }

      setState(() {
        _pendingSharedImagePath = null;
        _shareScreenIsOpen = true;
      });

      navigator
          .push<void>(
            MaterialPageRoute<void>(
              builder: (context) {
                return SharedImageImportScreen(sharedImagePath: sharedPath);
              },
            ),
          )
          .whenComplete(() {
            if (!mounted) {
              return;
            }

            setState(() {
              _shareScreenIsOpen = false;
            });

            if (_pendingSharedImagePath != null) {
              _openPendingShareWhenReady();
            }
          });
    });
  }

  void _closeScreensAfterLogout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _shareScreenIsOpen = false;
      rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _sharingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Painter Reference',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: !_authStateIsReady
          ? const _AuthenticationLoadingScreen()
          : _isSignedIn
          ? const CollectionsScreen()
          : LoginScreen(key: ValueKey<String?>(_pendingSharedImagePath)),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        return _ImpersonationBanner(child: child);
      },
    );
  }
}

class _ImpersonationBanner extends StatelessWidget {
  const _ImpersonationBanner({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ImpersonationController.instance.impersonatedEmail,
      builder: (context, impersonatedEmail, _) {
        if (impersonatedEmail == null) {
          return child;
        }
        final colors = Theme.of(context).colorScheme;
        return Column(
          children: [
            SafeArea(
              bottom: false,
              child: Material(
                color: colors.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.visibility, color: colors.onErrorContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Impersonating $impersonatedEmail',
                          style: TextStyle(
                            color: colors.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          ImpersonationController.instance
                              .returnToOriginalAccount();
                        },
                        child: Text(
                          'Return to my account',
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class _AuthenticationLoadingScreen extends StatelessWidget {
  const _AuthenticationLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

enum _AccountMenuAction { help, about, feedback, privacy, signOut }

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  late final CategoryService _categoryService;
  late final ImageAssetService _imageAssetService;
  late final MessagingService _messagingService;

  final List<ReferenceCategory> _categories = <ReferenceCategory>[];
  final Map<String, int> _imageCountsByCategoryCode = <String, int>{};

  bool _isLoading = true;
  bool _isIngesting = false;
  bool _isAddingCategory = false;
  bool _isAdmin = false;
  int _unreadMessageCount = 0;
  String? _errorMessage;

  bool get _cameraIsAvailable {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    final supabase = Supabase.instance.client;

    _categoryService = CategoryService(supabase);
    _imageAssetService = ImageAssetService(supabase);
    _messagingService = MessagingService(supabase);

    _restoreThenRefreshCategories();
    _refreshAdminStatus();
    _refreshUnreadMessageCount();

    // This screen's State is never recreated by an impersonation switch
    // (Navigator.popUntil reuses the existing root route rather than
    // rebuilding it), so without this listener the category grid would keep
    // showing whichever identity's data was loaded when initState first
    // ran, regardless of who the app is actually signed in as afterward.
    ImpersonationController.instance.impersonatedEmail.addListener(
      _refreshHome,
    );
  }

  @override
  void dispose() {
    ImpersonationController.instance.impersonatedEmail.removeListener(
      _refreshHome,
    );
    super.dispose();
  }

  Future<void> _refreshAdminStatus() async {
    try {
      final response = await Supabase.instance.client.auth.getUser();
      final isAdmin = response.user?.appMetadata['is_admin'] == true;
      if (mounted && isAdmin != _isAdmin) {
        setState(() => _isAdmin = isAdmin);
      }
    } catch (error) {
      debugPrint('Unable to refresh administrator status: $error');
      if (mounted && _isAdmin) setState(() => _isAdmin = false);
    }
  }

  Future<void> _refreshUnreadMessageCount() async {
    try {
      final conversations = await _messagingService.listConversations();
      final unread = conversations.fold<int>(
        0,
        (total, conversation) => total + conversation.unreadCount,
      );
      if (mounted && unread != _unreadMessageCount) {
        setState(() => _unreadMessageCount = unread);
      }
    } catch (error) {
      debugPrint('Unable to refresh unread message count: $error');
    }
  }

  Future<void> _refreshHome() async {
    await Future.wait<void>([
      _loadCategories(),
      _refreshAdminStatus(),
      _refreshUnreadMessageCount(),
    ]);
  }

  Future<void> _openMaintenance() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MaintenanceScreen()),
    );
    await _refreshAdminStatus();
  }

  Future<void> _restoreThenRefreshCategories() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final cached = await LibraryHomeCache.read(userId);
      if (cached != null && mounted) {
        final visibleCachedCategories = cached.categories
            .where(
              (category) =>
                  category.isMyArt ||
                  !category.isBuiltIn ||
                  ReferenceCategory.visibleCategoryCodes.contains(
                    category.databaseCode,
                  ),
            )
            .toList();
        setState(() {
          _categories
            ..clear()
            ..addAll(visibleCachedCategories);
          _imageCountsByCategoryCode
            ..clear()
            ..addAll(cached.counts);
          _isLoading = false;
        });
      }
    }
    await _loadCategories(showLoading: _categories.isEmpty);
  }

  Future<void> _loadCategories({bool showLoading = true}) async {
    final profiler = PerformanceProfiler('CATEGORY RETURN/REFRESH');
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final categories = await _loadOrderedCategoriesWithRetry();
      profiler.checkpoint('Category records loaded');

      final countEntries = await Future.wait(
        categories.map((category) async {
          try {
            final images = await _imageAssetService.listImages(category);
            return MapEntry<String, int>(category.databaseCode, images.length);
          } catch (error) {
            debugPrint(
              'Unable to load the ${category.displayName} count: $error',
            );
            return MapEntry<String, int>(
              category.databaseCode,
              _imageCountsByCategoryCode[category.databaseCode] ?? 0,
            );
          }
        }),
      );
      profiler.checkpoint('Category image counts loaded');

      if (!mounted) {
        return;
      }

      final counts = Map<String, int>.fromEntries(countEntries);
      final shouldUpdateGrid =
          _isLoading ||
          _errorMessage != null ||
          !_sameCategoryPresentation(_categories, categories) ||
          !mapEquals(_imageCountsByCategoryCode, counts);
      if (shouldUpdateGrid) {
        setState(() {
          _categories
            ..clear()
            ..addAll(categories);

          _imageCountsByCategoryCode
            ..clear()
            ..addAll(counts);

          _isLoading = false;
          _errorMessage = null;
        });
        profiler.checkpoint('Category grid updated');
      } else {
        profiler.checkpoint('Category grid unchanged');
      }
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await LibraryHomeCache.write(userId, categories, counts);
        profiler.checkpoint('Category cache written');
      }
      profiler.finish();
    } catch (error) {
      profiler.fail(error);
      if (!mounted) {
        return;
      }

      final hasUsableCategories = _categories.isNotEmpty;
      final nextError = hasUsableCategories ? null : error.toString();
      if (_isLoading || _errorMessage != nextError) {
        setState(() {
          _isLoading = false;
          _errorMessage = nextError;
        });
      }
      if (hasUsableCategories) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to refresh categories. Showing the saved library.',
            ),
          ),
        );
      }
    }
  }

  bool _sameCategoryPresentation(
    List<ReferenceCategory> current,
    List<ReferenceCategory> next,
  ) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      final left = current[index];
      final right = next[index];
      if (left.id != right.id ||
          left.databaseCode != right.databaseCode ||
          left.displayName != right.displayName ||
          left.isBuiltIn != right.isBuiltIn ||
          left.thumbnailAsset != right.thumbnailAsset ||
          left.userId != right.userId) {
        return false;
      }
    }
    return true;
  }

  Future<List<ReferenceCategory>> _loadOrderedCategoriesWithRetry() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final categories = await _categoryService.listCategories();
        if (!categories.any((category) => category.isMyArt)) {
          categories.add(ReferenceCategory.myArt);
        }
        return await _categoryService.applySavedOrder(categories);
      } catch (error) {
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: attempt == 0 ? 350 : 900),
          );
        }
      }
    }
    throw lastError!;
  }

  Future<void> _openHelp({int initialTabIndex = 0}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return HelpScreen(initialTabIndex: initialTabIndex);
        },
      ),
    );
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'You will need your email and password to sign in again.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true || !mounted) {
      return;
    }

    final auth = Supabase.instance.client.auth;
    UserActivityLogger.instance.record(
      operation: 'logout',
      status: 'succeeded',
      targetType: 'account',
      targetId: auth.currentUser?.id,
    );
    try {
      await auth.signOut(scope: SignOutScope.local);
    } on AuthException catch (error) {
      // Supabase clears the local session before it attempts remote token
      // revocation. A network failure must not undo a successful local logout.
      if (auth.currentSession == null) {
        debugPrint('Remote sign-out could not be completed: $error');
        return;
      }
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to sign out: ${error.message}')),
      );
    } catch (error) {
      if (auth.currentSession == null) {
        debugPrint('Remote sign-out could not be completed: $error');
        return;
      }
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to sign out: $error')));
    }
  }

  Future<void> _handleAccountMenuAction(_AccountMenuAction action) async {
    switch (action) {
      case _AccountMenuAction.help:
        await _openHelp(initialTabIndex: 0);
        return;
      case _AccountMenuAction.about:
        await _openHelp(initialTabIndex: 2);
        return;
      case _AccountMenuAction.feedback:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const FeedbackScreen()));
        return;
      case _AccountMenuAction.privacy:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const MessagingSettingsScreen(),
          ),
        );
        return;
      case _AccountMenuAction.signOut:
        await _signOut();
        return;
    }
  }

  Future<void> _openCategory(ReferenceCategory category) async {
    final profiler = PerformanceProfiler('RETURN FROM CATEGORY');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return CategoryScreen(category: category);
        },
      ),
    );

    if (!mounted) {
      return;
    }

    profiler.checkpoint('Category route closed');
    await _loadCategories(showLoading: false);
    profiler.finish();
  }

  Future<void> _openMessages() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const MessagesScreen()),
    );
    if (mounted) await _refreshUnreadMessageCount();
  }

  Future<void> _openKeywordSearch() async {
    if (_isLoading || _categories.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return KeywordSearchScreen(
            categories: List<ReferenceCategory>.unmodifiable(_categories),
          );
        },
      ),
    );
  }

  Future<void> _ingestImagesToInbox(ImageSource source) async {
    if (_isIngesting || _isLoading) return;
    ReferenceCategory? inbox;
    for (final category in _categories) {
      if (category.isInbox) {
        inbox = category;
        break;
      }
    }
    if (inbox == null) {
      _showCategoryMessage('Inbox is unavailable. Refresh and try again.');
      return;
    }

    final picker = ImagePicker();
    List<XFile> selected;
    try {
      if (source == ImageSource.gallery) {
        selected = await picker.pickMultiImage();
      } else {
        final captured = await picker.pickImage(source: ImageSource.camera);
        selected = captured == null ? <XFile>[] : <XFile>[captured];
      }
    } catch (error) {
      // Unlike the upload loop below, nothing catches a failure from the
      // picker call itself here, and the app has no global error handler —
      // without this, a thrown PlatformException (camera busy, activity
      // recreation, etc.) would silently vanish with no feedback at all.
      if (mounted) {
        _showCategoryMessage(
          source == ImageSource.camera
              ? 'Unable to open the camera: $error'
              : 'Unable to open the photo library: $error',
        );
      }
      return;
    }
    if (selected.isEmpty || !mounted) return;
    if (selected.length > 1) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Add ${selected.length} images to Inbox?'),
          content: const Text(
            'Every selected image will be uploaded directly to Inbox.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add images'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }

    setState(() => _isIngesting = true);
    var saved = 0;
    var failed = 0;
    try {
      for (final image in selected) {
        try {
          await _imageAssetService.uploadImage(
            await image.readAsBytes(),
            inbox,
          );
          saved += 1;
        } catch (error) {
          failed += 1;
          debugPrint('Unable to ingest ${image.name}: $error');
        }
      }
      if (mounted) await _loadCategories(showLoading: false);
      if (mounted) {
        _showCategoryMessage(
          failed == 0
              ? '$saved ${saved == 1 ? 'image' : 'images'} added to Inbox.'
              : '$saved added to Inbox; $failed failed.',
        );
      }
    } finally {
      if (mounted) setState(() => _isIngesting = false);
    }
  }

  Future<void> _showAddCategoryDialog() async {
    if (_isAddingCategory) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCategoryDialog(title: 'Add category'),
    );
    if (name == null || !mounted) return;
    setState(() => _isAddingCategory = true);
    try {
      final category = await _categoryService.addCategory(name);
      if (!mounted) return;
      setState(() {
        _categories.add(category);
        _imageCountsByCategoryCode[category.databaseCode] = 0;
      });
      await _persistCategoryOrder();
      if (mounted) _showCategoryMessage('${category.displayName} added.');
    } catch (error) {
      if (mounted) _showCategoryMessage('Unable to add category: $error');
    } finally {
      if (mounted) setState(() => _isAddingCategory = false);
    }
  }

  Future<void> _renameCategory(ReferenceCategory category) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _AddCategoryDialog(
        title: 'Rename category',
        initialValue: category.displayName,
      ),
    );
    if (name == null || !mounted) return;
    try {
      final updated = await _categoryService.renameCategory(category, name);
      if (!mounted) return;
      setState(() {
        final index = _categories.indexWhere((item) => item.id == category.id);
        if (index >= 0) _categories[index] = updated;
      });
      _showCategoryMessage('Category renamed.');
    } catch (error) {
      if (mounted) _showCategoryMessage('Unable to rename category: $error');
    }
  }

  Future<void> _deleteCategory(ReferenceCategory category) async {
    final count = _imageCountsByCategoryCode[category.databaseCode] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${category.displayName}?'),
        content: Text(
          count == 0
              ? 'The category will be permanently removed.'
              : 'The category will be removed from its $count images. The images themselves will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _categoryService.deleteCategory(category);
      if (!mounted) return;
      setState(() {
        _categories.removeWhere((item) => item.id == category.id);
        _imageCountsByCategoryCode.remove(category.databaseCode);
      });
      await _persistCategoryOrder();
      if (mounted) _showCategoryMessage('Category deleted.');
    } catch (error) {
      if (mounted) _showCategoryMessage('Unable to delete category: $error');
    }
  }

  Future<void> _moveCategory(int fromIndex, int toIndex) async {
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        toIndex < 0 ||
        fromIndex >= _categories.length ||
        toIndex >= _categories.length) {
      return;
    }
    final previous = List<ReferenceCategory>.of(_categories);
    setState(() {
      final category = _categories.removeAt(fromIndex);
      _categories.insert(toIndex, category);
    });
    try {
      await _persistCategoryOrder();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _categories
          ..clear()
          ..addAll(previous);
      });
      _showCategoryMessage('Unable to save category order: $error');
    }
  }

  Future<void> _persistCategoryOrder() async {
    await _categoryService.saveCategoryOrder(_categories);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await LibraryHomeCache.write(
        userId,
        _categories,
        _imageCountsByCategoryCode,
      );
    }
  }

  Future<void> _changeCategoryImage(ReferenceCategory category) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final updated = await _categoryService.uploadCover(
        category,
        await picked.readAsBytes(),
      );
      if (!mounted) return;
      setState(() {
        final i = _categories.indexWhere((item) => item.id == updated.id);
        if (i >= 0) _categories[i] = updated;
      });
      _showCategoryMessage('Category image updated.');
    } catch (error) {
      if (mounted) {
        _showCategoryMessage('Unable to update category image: $error');
      }
    }
  }

  void _showCategoryMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  @override
  Widget build(BuildContext context) {
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? 'Signed-in user';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painter Reference'),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: _openMessages,
            icon: Badge(
              label: Text('$_unreadMessageCount'),
              isLabelVisible: _unreadMessageCount > 0,
              child: const Icon(Icons.mail_outline),
            ),
            tooltip: _unreadMessageCount > 0
                ? 'Messages ($_unreadMessageCount unread)'
                : 'Messages',
          ),
          IconButton(
            onPressed: _isLoading || _categories.isEmpty
                ? null
                : _openKeywordSearch,
            icon: const Icon(Icons.search),
            tooltip: 'Search by keyword',
          ),
          IconButton(
            onPressed: _isLoading || _isIngesting ? null : _refreshHome,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh categories',
          ),
          if (_isAdmin)
            IconButton(
              onPressed: _openMaintenance,
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Maintenance',
            ),
          PopupMenuButton<_AccountMenuAction>(
            tooltip: 'Account and sign out',
            onSelected: _handleAccountMenuAction,
            itemBuilder: (context) {
              return [
                PopupMenuItem<_AccountMenuAction>(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Signed in as',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(userEmail),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<_AccountMenuAction>(
                  value: _AccountMenuAction.signOut,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout),
                    title: Text('Sign Out'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<_AccountMenuAction>(
                  value: _AccountMenuAction.help,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.help_outline),
                    title: Text('Help'),
                    subtitle: Text('Introduction and how to use the app'),
                  ),
                ),
                const PopupMenuItem<_AccountMenuAction>(
                  value: _AccountMenuAction.about,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_outline),
                    title: Text('About'),
                  ),
                ),
                const PopupMenuItem<_AccountMenuAction>(
                  value: _AccountMenuAction.feedback,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.feedback_outlined),
                    title: Text('Send Feedback'),
                    subtitle: Text('Report a problem or share an idea'),
                  ),
                ),
                const PopupMenuItem<_AccountMenuAction>(
                  value: _AccountMenuAction.privacy,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.privacy_tip_outlined),
                    title: Text('Privacy and blocking'),
                    subtitle: Text('Manage who can find and message you'),
                  ),
                ),
              ];
            },
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _buildHomeActions(),
    );
  }

  Widget _buildHomeActions() {
    final addImages = FloatingActionButton.extended(
      heroTag: 'inboxGalleryButton',
      onPressed: _isIngesting
          ? null
          : () => _ingestImagesToInbox(ImageSource.gallery),
      icon: _isIngesting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_photo_alternate_outlined),
      label: Text(_isIngesting ? 'Adding to Inbox...' : 'Add images'),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'addCategoryButton',
          onPressed: _isAddingCategory ? null : _showAddCategoryDialog,
          tooltip: 'Add category',
          child: _isAddingCategory
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.create_new_folder_outlined),
        ),
        const SizedBox(width: 12),
        addImages,
        if (_cameraIsAvailable) ...[
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'inboxCameraButton',
            onPressed: _isIngesting
                ? null
                : () => _ingestImagesToInbox(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Camera'),
          ),
        ],
      ],
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
                'Unable to load categories.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadCategories,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.drag_indicator,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Press and hold a category, then drag it to rearrange.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              itemCount: _categories.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final category = _categories[index];

                final card = CollectionCard(
                  category: category,
                  imageCount:
                      _imageCountsByCategoryCode[category.databaseCode] ?? 0,
                  onTap: () => _openCategory(category),
                  onRename: category.canRename
                      ? () => _renameCategory(category)
                      : null,
                  onChangeImage: category.canChangeImage
                      ? () => _changeCategoryImage(category)
                      : null,
                  onDelete: category.canDelete
                      ? () => _deleteCategory(category)
                      : null,
                );
                return DragTarget<int>(
                  onWillAcceptWithDetails: (details) => details.data != index,
                  onAcceptWithDetails: (details) {
                    unawaited(_moveCategory(details.data, index));
                  },
                  builder: (context, candidates, rejected) =>
                      LongPressDraggable<int>(
                        data: index,
                        maxSimultaneousDrags: 1,
                        feedback: Material(
                          elevation: 10,
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 220,
                            height: 220,
                            child: CollectionCard(
                              category: category,
                              imageCount:
                                  _imageCountsByCategoryCode[category
                                      .databaseCode] ??
                                  0,
                              onTap: () {},
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: 0.25, child: card),
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 120),
                          scale: candidates.isEmpty ? 1 : 0.96,
                          child: card,
                        ),
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({required this.title, this.initialValue});

  final String title;
  final String? initialValue;

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Category name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class CollectionCard extends StatelessWidget {
  const CollectionCard({
    required this.category,
    required this.imageCount,
    required this.onTap,
    this.onRename,
    this.onChangeImage,
    this.onDelete,
    super.key,
  });

  final ReferenceCategory category;
  final int imageCount;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onChangeImage;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(context),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.45, 1],
                ),
              ),
            ),
            if (onRename != null || onChangeImage != null || onDelete != null)
              Positioned(
                top: 6,
                right: 6,
                child: PopupMenuButton<String>(
                  tooltip: 'Manage category',
                  color: Theme.of(context).colorScheme.surface,
                  onSelected: (value) {
                    if (value == 'rename') onRename?.call();
                    if (value == 'image') onChangeImage?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (onRename != null)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                    if (onChangeImage != null)
                      const PopupMenuItem(
                        value: 'image',
                        child: Text('Change image'),
                      ),
                    if (onDelete != null) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ],
                  icon: Icon(Icons.more_vert, color: Colors.white),
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$imageCount ${imageCount == 1 ? 'image' : 'images'}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    final thumbnailAsset = category.thumbnailAsset;

    if (thumbnailAsset != null && thumbnailAsset.isNotEmpty) {
      if (thumbnailAsset.startsWith('http://') ||
          thumbnailAsset.startsWith('https://')) {
        return Image.network(
          thumbnailAsset,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildCustomCategoryBackground(context),
        );
      }
      return Image.asset(
        thumbnailAsset,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildCustomCategoryBackground(context),
      );
    }

    return _buildCustomCategoryBackground(context);
  }

  Widget _buildCustomCategoryBackground(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primaryContainer, colorScheme.tertiaryContainer],
        ),
      ),
      child: Center(
        child: Icon(
          category.isInbox
              ? Icons.inbox_outlined
              : Icons.collections_bookmark_outlined,
          size: 72,
          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
