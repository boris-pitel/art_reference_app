import 'package:flutter/material.dart';

import '../services/admin_audit_log.dart';
import '../services/admin_service.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({
    super.key,
    required this.service,
    required this.auditLog,
  });

  final AdminService service;
  final AdminAuditLog auditLog;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  static const statuses = ['new', 'reviewed', 'planned', 'resolved', 'closed'];

  List<Map<String, dynamic>> _rows = [];
  String? _status = 'new';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.service.listFeedback(status: _status);
      if (!mounted) return;
      setState(() => _rows = rows);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String?>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    for (final status in statuses)
                      DropdownMenuItem(
                        value: status,
                        child: Text(_label(status)),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _status = value);
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: _loading ? null : _load,
                tooltip: 'Refresh feedback',
                icon: const Icon(Icons.refresh),
              ),
              const Spacer(),
              Text('${_rows.length} feedback items'),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
                trailing: FilledButton.tonal(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            )
          else if (!_loading && _rows.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 54),
                    SizedBox(height: 12),
                    Text('No feedback matches this status.'),
                  ],
                ),
              ),
            )
          else if (!_loading)
            Expanded(
              child: ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return Card(
                    child: ListTile(
                      isThreeLine: true,
                      leading: CircleAvatar(
                        child: Icon(
                          _typeIcon(row['feedback_type']?.toString()),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row['user_email']?.toString() ?? '(unknown user)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          _StatusChip(status: row['status']?.toString() ?? ''),
                        ],
                      ),
                      subtitle: Text(
                        '${_date(row['created_at'])}\n${_summary(row['comment'])}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showFeedback(row),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showFeedback(Map<String, dynamic> summary) async {
    final id = summary['id'].toString();
    _showProgress('Loading feedback...');
    Map<String, dynamic> row;
    String? attachmentUrl;
    try {
      row = await widget.service.getFeedback(id);
      attachmentUrl = await widget.service.feedbackAttachmentUrl(row);
    } on Object catch (error) {
      if (mounted) _message(error.toString(), error: true);
      return;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Feedback Details')),
            _StatusChip(status: row['status']?.toString() ?? ''),
          ],
        ),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow('User', row['user_email']?.toString() ?? '-'),
                  _DetailRow('Created', _date(row['created_at'])),
                  _DetailRow(
                    'Type',
                    _label(row['feedback_type']?.toString() ?? ''),
                  ),
                  _DetailRow('Platform', row['platform']?.toString() ?? '-'),
                  _DetailRow(
                    'App version',
                    row['app_version']?.toString() ?? '-',
                  ),
                  _DetailRow(
                    'Screen',
                    row['current_screen']?.toString() ?? '-',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Comment',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(row['comment']?.toString() ?? ''),
                  if (attachmentUrl != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Private attachment link (expires in one hour)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(attachmentUrl),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Change status',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final status in statuses)
                        ActionChip(
                          label: Text(_label(status)),
                          onPressed: status == row['status']
                              ? null
                              : () => Navigator.pop(context, status),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected != null) await _updateStatus(row, selected);
  }

  Future<void> _updateStatus(Map<String, dynamic> row, String status) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change feedback status?'),
        content: Text('Set this feedback item to ${_label(status)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change Status'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    _showProgress('Updating feedback status...');
    try {
      final updated = await widget.service.updateFeedbackStatus(
        row['id'].toString(),
        status,
      );
      await widget.auditLog.write(
        action: 'feedback.status',
        targetEmail: updated['user_email']?.toString() ?? '',
        authUserId: updated['user_id']?.toString(),
        result: 'success',
        details: {'feedback_id': row['id'].toString(), 'status': status},
      );
      if (mounted) _message('Feedback status changed to ${_label(status)}.');
      await _load();
    } on Object catch (error) {
      await widget.auditLog.write(
        action: 'feedback.status',
        targetEmail: row['user_email']?.toString() ?? '',
        authUserId: row['user_id']?.toString(),
        result: 'failed',
        details: {
          'feedback_id': row['id'].toString(),
          'status': status,
          'error': error.toString(),
        },
      );
      if (mounted) _message(error.toString(), error: true);
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showProgress(String text) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(_label(status)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

IconData _typeIcon(String? type) => switch (type) {
  'problem' => Icons.bug_report_outlined,
  'question' => Icons.help_outline,
  'suggestion' => Icons.lightbulb_outline,
  _ => Icons.chat_bubble_outline,
};

String _label(String value) {
  if (value.isEmpty) return '-';
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _summary(Object? value) =>
    value?.toString().replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

String _date(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed?.toLocal().toString() ?? value?.toString() ?? '-';
}
