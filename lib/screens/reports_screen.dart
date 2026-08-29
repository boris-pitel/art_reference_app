import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/report_service.dart';
import '../widgets/home_button.dart';

/// What people have reported, for the operator to look at.
///
/// Tapping a report closes it, either as acted on or as needing nothing. That
/// is the minimum for the queue to work at all: the red flag counts open
/// reports, so without a way to close one it would stay lit for ever and stop
/// meaning anything within a day.
///
/// The heavier consequences — suspending an account, removing what somebody
/// sent — still belong in the admin console, where there is room to see the
/// whole picture before doing something to a person. This screen is for
/// finding out from a phone that something is waiting, and for saying it has
/// been dealt with.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportService _reportService;

  List<ContentReport> _reports = const [];
  bool _isLoading = true;
  String? _errorMessage;

  /// The report currently being closed, so its row can show it is working and
  /// cannot be tapped twice.
  String? _resolving;

  /// Closes a report, having asked which of the two it is.
  ///
  /// "Acted on" and "Nothing needed" both clear it from the queue, and the
  /// difference is kept rather than collapsed into one button: a run of
  /// dismissals against one person reads very differently afterwards from a
  /// run of actions.
  Future<void> _close(ContentReport report) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close this report?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            '${report.reasonLabel}, about '
            '${report.reportedEmail ?? 'someone'}.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'dismissed'),
            child: const Text('Nothing needed'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'actioned'),
            child: const Text('Acted on it'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _resolving = report.id);

    try {
      await _reportService.resolve(reportId: report.id, status: choice);

      if (!mounted) return;
      setState(() {
        // Removed here rather than by reloading, so the list does not jump
        // under the finger that just tapped it.
        _reports = _reports.where((r) => r.id != report.id).toList();
        _resolving = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            choice == 'actioned' ? 'Marked as acted on.' : 'Report closed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _resolving = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not close it: $error')));
    }
  }

  @override
  void initState() {
    super.initState();
    _reportService = ReportService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final reports = await _reportService.listOpenReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load reports.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          const HomeButton(),
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(_errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }

    if (_reports.isEmpty) {
      // Scrollable even when empty, so pulling down still refreshes.
      return ListView(
        padding: const EdgeInsets.all(48),
        children: const [
          Icon(Icons.check_circle_outline, size: 56),
          SizedBox(height: 16),
          Text('Nothing to review.', textAlign: TextAlign.center),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _reports.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildReport(_reports[index]),
    );
  }

  Widget _buildReport(ContentReport report) {
    final theme = Theme.of(context);
    final when = MaterialLocalizations.of(
      context,
    ).formatShortDate(report.createdAt);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(report.createdAt));

    return ListTile(
      isThreeLine: true,
      // Closing a report is the whole point of the queue, so it happens here
      // rather than somewhere else: a badge that cannot be cleared stops being
      // information within a day.
      onTap: _resolving == report.id ? null : () => _close(report),
      leading: _resolving == report.id
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              report.subjectType == 'user'
                  ? Icons.person_outline
                  : Icons.chat_bubble_outline,
              color: theme.colorScheme.error,
            ),
      title: Text(report.reasonLabel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About ${report.reportedEmail ?? 'someone'} · '
            'from ${report.reporterEmail ?? 'someone'}',
            style: theme.textTheme.bodySmall,
          ),
          if (report.details != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                report.details!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (report.messageBody != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '“${report.messageBody!}”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          if (report.hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'An image was attached.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$when at $time', style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
