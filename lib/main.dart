import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/reference_category.dart';
import 'screens/category_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/help_screen.dart';
import 'screens/login_screen.dart';
import 'services/user_activity_logger.dart';
import 'screens/keyword_search_screen.dart';
import 'screens/shared_image_import_screen.dart';
import 'services/category_service.dart';
import 'services/library_home_cache.dart';
import 'services/image_asset_service.dart';
import 'utils/performance_profiler.dart';
import 'widgets/home_button.dart';

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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

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
      final navigator = _navigatorKey.currentState;

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
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
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
      navigatorKey: _navigatorKey,
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
      routes: {categoriesHomeRoute: (_) => const CollectionsScreen()},
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

enum _AccountMenuAction { help, about, feedback, signOut }

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  late final CategoryService _categoryService;
  late final ImageAssetService _imageAssetService;

  final List<ReferenceCategory> _categories = <ReferenceCategory>[];
  final Map<String, int> _imageCountsByCategoryCode = <String, int>{};

  bool _isLoading = true;
  bool _isAddingCategory = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final supabase = Supabase.instance.client;

    _categoryService = CategoryService(supabase);
    _imageAssetService = ImageAssetService(supabase);

    _restoreThenRefreshCategories();
  }

  Future<void> _restoreThenRefreshCategories() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      final cached = await LibraryHomeCache.read(userId);
      if (cached != null && mounted) {
        setState(() {
          _categories
            ..clear()
            ..addAll(cached.categories);
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
    setState(() {
      if (showLoading) _isLoading = true;
      _errorMessage = null;
    });

    try {
      final categories = await _categoryService.listCategories();
      profiler.checkpoint('Category records loaded');
      if (!categories.any((category) => category.isMyArt)) {
        categories.add(ReferenceCategory.myArt);
      }
      categories.sort((left, right) {
        if (left.isMyArt) return -1;
        if (right.isMyArt) return 1;
        return left.id.compareTo(right.id);
      });

      final countEntries = await Future.wait(
        categories.map((category) async {
          try {
            final images = await _imageAssetService.listImages(category);
            return MapEntry<String, int>(category.databaseCode, images.length);
          } catch (error) {
            debugPrint(
              'Unable to load the ${category.displayName} count: $error',
            );
            return MapEntry<String, int>(category.databaseCode, 0);
          }
        }),
      );
      profiler.checkpoint('Category image counts loaded');

      if (!mounted) {
        return;
      }

      setState(() {
        _categories
          ..clear()
          ..addAll(categories);

        _imageCountsByCategoryCode
          ..clear()
          ..addEntries(countEntries);

        _isLoading = false;
      });
      profiler.checkpoint('Category grid updated');
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await LibraryHomeCache.write(
          userId,
          categories,
          Map<String, int>.fromEntries(countEntries),
        );
        profiler.checkpoint('Category cache written');
      }
      profiler.finish();
    } catch (error) {
      profiler.fail(error);
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
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

    try {
      await UserActivityLogger.instance.log(
        operation: 'logout',
        status: 'succeeded',
        targetType: 'account',
        targetId: Supabase.instance.client.auth.currentUser?.id,
      );
      await Supabase.instance.client.auth.signOut();
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to sign out: ${error.message}')),
      );
    } catch (error) {
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

  Future<void> _showAddCategoryDialog() async {
    if (_isAddingCategory) {
      return;
    }

    final categoryName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return const _AddCategoryDialog();
      },
    );

    if (categoryName == null || !mounted) {
      return;
    }

    setState(() {
      _isAddingCategory = true;
    });

    try {
      final newCategory = await _categoryService.addCategory(categoryName);

      if (!mounted) {
        return;
      }

      setState(() {
        _categories.add(newCategory);
        _imageCountsByCategoryCode[newCategory.databaseCode] = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${newCategory.displayName} added.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to add category: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isAddingCategory = false;
        });
      }
    }
  }

  Future<void> _renameCategory(ReferenceCategory category) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _AddCategoryDialog(
        title: 'Rename Category',
        actionLabel: 'Rename',
        initialValue: category.displayName,
      ),
    );
    if (name == null || !mounted) return;
    try {
      final updated = await _categoryService.renameCategory(category, name);
      if (!mounted) return;
      setState(() {
        final i = _categories.indexWhere((item) => item.id == updated.id);
        if (i >= 0) _categories[i] = updated;
      });
      _showCategoryMessage('${updated.displayName} renamed.');
    } catch (error) {
      if (mounted) _showCategoryMessage('Unable to rename category: $error');
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

  Future<void> _deleteCategory(ReferenceCategory category) async {
    final count = _imageCountsByCategoryCode[category.databaseCode] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${category.displayName}?'),
        content: Text(
          count == 0
              ? 'This category will be permanently removed.'
              : 'This removes the category from $count ${count == 1 ? 'image' : 'images'}, but does not delete the original image files.',
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
      _showCategoryMessage('${category.displayName} deleted.');
    } catch (error) {
      if (mounted) _showCategoryMessage('Unable to delete category: $error');
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
            onPressed: _isLoading || _categories.isEmpty
                ? null
                : _openKeywordSearch,
            icon: const Icon(Icons.search),
            tooltip: 'Search by keyword',
          ),
          IconButton(
            onPressed: _isLoading || _isAddingCategory ? null : _loadCategories,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh categories',
          ),
          PopupMenuButton<_AccountMenuAction>(
            tooltip: 'Account, Help and About',
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
                const PopupMenuDivider(),
                const PopupMenuItem<_AccountMenuAction>(
                  value: _AccountMenuAction.signOut,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout),
                    title: Text('Sign Out'),
                  ),
                ),
              ];
            },
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isAddingCategory ? null : _showAddCategoryDialog,
        icon: _isAddingCategory
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.create_new_folder_outlined),
        label: Text(_isAddingCategory ? 'Adding...' : 'Add Category'),
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
      padding: const EdgeInsets.all(16),
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

          return CollectionCard(
            category: category,
            imageCount: _imageCountsByCategoryCode[category.databaseCode] ?? 0,
            onTap: () => _openCategory(category),
            onRename: category.canRename
                ? () => _renameCategory(category)
                : null,
            onChangeImage: category.canRename
                ? () => _changeCategoryImage(category)
                : null,
            onDelete: category.canDelete
                ? () => _deleteCategory(category)
                : null,
          );
        },
      ),
    );
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({
    this.title = 'Add Category',
    this.actionLabel = 'Add',
    this.initialValue = '',
  });

  final String title;
  final String actionLabel;
  final String initialValue;

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  late final TextEditingController _controller;

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _submit() {
    final value = _controller.text.trim();

    if (value.isEmpty) {
      return;
    }

    Navigator.of(context).pop(value);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();

    super.dispose();
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
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Category name',
          hintText: 'Animals',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) {
          _submit();
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(widget.actionLabel),
        ),
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
            if (onRename != null)
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
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'image', child: Text('Change image')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
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
          Icons.collections_bookmark_outlined,
          size: 72,
          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}
