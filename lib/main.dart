import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/reference_category.dart';
import 'screens/category_screen.dart';
import 'screens/help_screen.dart';
import 'screens/login_screen.dart';
import 'screens/keyword_search_screen.dart';
import 'screens/shared_image_import_screen.dart';
import 'services/category_service.dart';

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
      title: 'Art Reference',
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

enum _AccountMenuAction { help, about, signOut }

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  late final CategoryService _categoryService;

  final List<ReferenceCategory> _categories = <ReferenceCategory>[];

  bool _isLoading = true;
  bool _isAddingCategory = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _categoryService = CategoryService(Supabase.instance.client);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final categories = await _categoryService.listCategories();

      if (!mounted) {
        return;
      }

      setState(() {
        _categories
          ..clear()
          ..addAll(categories);
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
      case _AccountMenuAction.signOut:
        await _signOut();
        return;
    }
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

    final controller = TextEditingController();

    final categoryName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Category name',
              hintText: 'Animals',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              final trimmedValue = value.trim();
              if (trimmedValue.isNotEmpty) {
                Navigator.of(dialogContext).pop(trimmedValue);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final trimmedValue = controller.text.trim();
                if (trimmedValue.isNotEmpty) {
                  Navigator.of(dialogContext).pop(trimmedValue);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    controller.dispose();

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

  @override
  Widget build(BuildContext context) {
    final userEmail =
        Supabase.instance.client.auth.currentUser?.email ?? 'Signed-in user';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Art Reference'),
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
          return CollectionCard(category: _categories[index]);
        },
      ),
    );
  }
}

class CollectionCard extends StatelessWidget {
  const CollectionCard({required this.category, super.key});

  final ReferenceCategory category;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) {
                return CategoryScreen(category: category);
              },
            ),
          );
        },
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
                    '0 images',
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
      return Image.asset(
        thumbnailAsset,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildCustomCategoryBackground(context);
        },
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
