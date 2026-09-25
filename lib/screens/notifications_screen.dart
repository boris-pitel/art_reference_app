import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_status_service.dart';
import '../widgets/home_button.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final AppStatusService _service;
  List<AppAnnouncement> _announcements = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = AppStatusService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final announcements = await _service.recentAnnouncements();
      if (!mounted) return;
      setState(() => _announcements = announcements);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(AppAnnouncement announcement) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(announcement.title),
      content: SingleChildScrollView(child: Text(announcement.message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh notifications',
            icon: const Icon(Icons.refresh),
          ),
          const HomeButton(),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              const Text('Unable to load notifications.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_announcements.isEmpty) {
      return const Center(child: Text('No announcements yet.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _announcements.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final announcement = _announcements[index];
          final date = announcement.publishedAt;
          return Card(
            child: ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(announcement.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (date != null)
                    Text(
                      MaterialLocalizations.of(context).formatMediumDate(date),
                    ),
                  Text(
                    announcement.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(announcement),
            ),
          );
        },
      ),
    );
  }
}
