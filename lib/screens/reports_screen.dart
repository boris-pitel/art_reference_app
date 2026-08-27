import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/report_service.dart';
import '../widgets/home_button.dart';

/// What people have reported, for the operator to look at.
///
/// Deliberately read-only. Acting on a report — suspending somebody, removing
/// what they sent — happens in the admin console, where there is room to see
/// the whole picture before doing something to a person's account. This screen
/// exists so the operator can find out from their phone that something is
/// waiting, which is the difference between a promise to respond within a day
/// and a promise that depends on being at a desk.
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
      leading: Icon(
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
