import 'package:flutter/material.dart';

import '../services/admin_audit_log.dart';

class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.auditLog});

  final AdminAuditLog auditLog;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  late Future<List<Map<String, dynamic>>> _records;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _records = widget.auditLog.readAll());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Privileged changes made by the CLI and desktop console. '
                  'Passwords and secret keys are never recorded.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              IconButton.filledTonal(
                onPressed: _refresh,
                tooltip: 'Refresh audit log',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            widget.auditLog.file.path,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _records,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(snapshot.error.toString()));
                }
                final records = snapshot.data ?? [];
                if (records.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 54),
                        SizedBox(height: 12),
                        Text('No administrative changes have been logged yet.'),
                      ],
                    ),
                  );
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final success = record['result'] == 'success';
                      return ListTile(
                        leading: Icon(
                          success
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: success
                              ? Colors.green.shade700
                              : Theme.of(context).colorScheme.error,
                        ),
                        title: Text(record['action']?.toString() ?? '-'),
                        subtitle: Text(
                          '${record['target_email'] ?? ''}\n'
                          '${record['actor'] ?? '-'} ? ${_date(record['timestamp'])}',
                        ),
                        isThreeLine: true,
                        trailing: Chip(
                          label: Text(record['result']?.toString() ?? '-'),
                        ),
                        onTap: () => _showRecord(record),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecord(Map<String, dynamic> record) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record['action']?.toString() ?? 'Audit Record'),
        content: SizedBox(
          width: 640,
          child: SelectionArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in record.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: Text(entry.value?.toString() ?? '-')),
                        ],
                      ),
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
  }
}

String _date(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed?.toLocal().toString() ?? value?.toString() ?? '-';
}
