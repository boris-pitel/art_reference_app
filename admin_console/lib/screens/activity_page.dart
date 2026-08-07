import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/admin_service.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key, required this.service});

  final AdminService service;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final _emailController = TextEditingController();
  final _operationController = TextEditingController();
  final _searchController = TextEditingController();
  var _status = 'all';
  var _days = 30;
  var _loading = false;
  String? _error;
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _operationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await widget.service.listUserActivity(
        email: _emailController.text,
        operation: _operationController.text,
        status: _status,
        search: _searchController.text,
        days: _days,
      );
      if (mounted) setState(() => _events = events);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 230,
                child: TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'User email',
                    prefixIcon: Icon(Icons.person_search_outlined),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              SizedBox(
                width: 190,
                child: TextField(
                  controller: _operationController,
                  decoration: const InputDecoration(labelText: 'Operation'),
                  onSubmitted: (_) => _load(),
                ),
              ),
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Target or session ID',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(value: 'started', child: Text('Started')),
                  DropdownMenuItem(value: 'succeeded', child: Text('Succeeded')),
                  DropdownMenuItem(value: 'failed', child: Text('Failed')),
                  DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                ],
                onChanged: (value) => setState(() => _status = value ?? 'all'),
              ),
              DropdownButton<int>(
                value: _days,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Last 24 hours')),
                  DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                  DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                  DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                ],
                onChanged: (value) => setState(() => _days = value ?? 30),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              Text('${_events.length} events'),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText('Unable to load activity logs.\n$_error'),
              ),
            ),
          Expanded(
            child: _events.isEmpty && !_loading
                ? const Center(child: Text('No activity events match these filters.'))
                : ListView.separated(
                    itemCount: _events.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _ActivityTile(
                      event: _events[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final status = event['status']?.toString() ?? '';
    final failed = status == 'failed';
    final details = const JsonEncoder.withIndent('  ').convert(event);
    return Card(
      color: failed ? Theme.of(context).colorScheme.errorContainer : null,
      child: ExpansionTile(
        leading: Icon(
          failed ? Icons.error_outline : Icons.check_circle_outline,
          color: failed ? Theme.of(context).colorScheme.error : null,
        ),
        title: Text(
          '${event['operation'] ?? 'operation'} · $status',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${event['created_at'] ?? ''}  •  ${event['user_email'] ?? ''}\n'
          '${event['target_type'] ?? 'target'}: ${event['target_id'] ?? '—'}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(details),
            ),
          ),
        ],
      ),
    );
  }
}
