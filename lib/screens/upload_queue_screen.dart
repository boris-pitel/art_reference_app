import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/local_user_session.dart';
import '../services/offline_upload_queue.dart';
import '../widgets/pending_thumbnail.dart';
import 'pending_image_screen.dart';

class UploadQueueScreen extends StatefulWidget {
  const UploadQueueScreen({super.key});
  @override
  State<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends State<UploadQueueScreen> {
  List<PendingImageUpload> _items = [];
  String? _error;
  bool _loading = true;
  bool _syncing = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    OfflineUploadQueue.instance.addListener(_changed);
    LocalUserSession.changes.addListener(_changed);
    _changed();
  }

  void _changed() {
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final user = LocalUserSession.effectiveUserId;
    try {
      final items = user == null
          ? <PendingImageUpload>[]
          : await OfflineUploadQueue.instance.listForUser(
              user,
              includeOriginals: false,
            );
      if (mounted && generation == _generation) {
        setState(() {
          _items = items;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _retry() async {
    setState(() => _syncing = true);
    try {
      await OfflineUploadQueue.instance.syncForCurrentUser(
        Supabase.instance.client,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  void dispose() {
    OfflineUploadQueue.instance.removeListener(_changed);
    LocalUserSession.changes.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Upload queue · ${_items.length}'),
      actions: [
        TextButton(
          onPressed: _syncing ? null : _retry,
          child: Text(_syncing ? 'Uploading…' : 'Retry uploads'),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              if (_items.isEmpty)
                const Expanded(
                  child: Center(child: Text('No uploads pending.')),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        leading: SizedBox(
                          width: 56,
                          height: 56,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PendingThumbnail(
                                key: ValueKey(item.id),
                                item: item,
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton.filledTonal(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  tooltip: 'Delete image',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    try {
                                      await OfflineUploadQueue.instance.remove(
                                        item.id,
                                      );
                                    } catch (error) {
                                      if (mounted) {
                                        setState(() => _error = '$error');
                                      }
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        title: Text(
                          item.originalFilename ?? 'Photo ${index + 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.lastError == null
                              ? '${item.categoryName} · Waiting to upload'
                              : '${item.categoryName} · ${item.lastError}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Icon(
                          item.lastError == null
                              ? Icons.cloud_upload_outlined
                              : Icons.error_outline,
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => PendingImageScreen(
                              items: _items,
                              initialIndex: index,
                            ),
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
