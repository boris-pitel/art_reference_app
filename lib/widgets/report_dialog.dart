import 'package:flutter/material.dart';

import '../services/report_service.dart';

/// What the person chose when they reported something.
class ReportOutcome {
  const ReportOutcome({
    required this.reason,
    this.details,
    this.alsoBlock = false,
  });

  final ReportReason reason;
  final String? details;

  /// Reporting somebody and wanting nothing more to do with them are usually
  /// the same impulse, so the block is offered here rather than left as a
  /// second thing to find afterwards.
  final bool alsoBlock;
}

/// Asks why, and offers to block on the way out.
///
/// Returns null if the person changed their mind, which is common: opening
/// this dialog is often how somebody decides the thing was not worth
/// reporting after all.
Future<ReportOutcome?> showReportDialog({
  required BuildContext context,
  required String title,
  required String subtitle,
  bool offerBlock = true,
  String? blockLabel,
}) {
  return showDialog<ReportOutcome>(
    context: context,
    builder: (dialogContext) => _ReportDialog(
      title: title,
      subtitle: subtitle,
      offerBlock: offerBlock,
      blockLabel: blockLabel,
    ),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.title,
    required this.subtitle,
    required this.offerBlock,
    this.blockLabel,
  });

  final String title;
  final String subtitle;
  final bool offerBlock;
  final String? blockLabel;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason? _reason;
  bool _alsoBlock = false;
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      // Narrower than the phone it has to fit on. A dialog that overflows the
      // screen cannot be dismissed by the button that is off the edge of it.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.subtitle, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (value) => setState(() => _reason = value),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final reason in ReportReason.values)
                      RadioListTile<ReportReason>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: reason,
                        title: Text(reason.label),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Anything else we should know?',
                  hintText: 'Optional',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.offerBlock)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _alsoBlock,
                  title: Text(widget.blockLabel ?? 'Also block this person'),
                  subtitle: const Text('They will not be able to message you'),
                  onChanged: (value) =>
                      setState(() => _alsoBlock = value ?? false),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Nothing is sent without a reason: a queue of reports that say only
          // "reported" cannot be triaged.
          onPressed: _reason == null
              ? null
              : () => Navigator.of(context).pop(
                  ReportOutcome(
                    reason: _reason!,
                    details: _details.text,
                    alsoBlock: _alsoBlock,
                  ),
                ),
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
