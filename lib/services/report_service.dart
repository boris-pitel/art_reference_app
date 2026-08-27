import 'package:supabase_flutter/supabase_flutter.dart';

/// Why something was reported.
///
/// A short list rather than free text alone, because the reasons want
/// different responses: spam is a nuisance, a threat is not, and an operator
/// triaging a queue needs to see that difference before opening anything.
enum ReportReason {
  harassment('harassment', 'Harassment or bullying'),
  sexual('sexual', 'Sexual or explicit content'),
  violence('violence', 'Violence or threats'),
  spam('spam', 'Spam or a scam'),
  other('other', 'Something else');

  const ReportReason(this.code, this.label);

  final String code;
  final String label;
}

/// One entry in the operator's queue.
class ContentReport {
  const ContentReport({
    required this.id,
    required this.createdAt,
    required this.subjectType,
    required this.reason,
    required this.status,
    this.reporterEmail,
    this.reportedEmail,
    this.details,
    this.messageBody,
    this.hasImage = false,
  });

  final String id;
  final DateTime createdAt;
  final String subjectType;
  final String reason;
  final String status;
  final String? reporterEmail;
  final String? reportedEmail;
  final String? details;
  final String? messageBody;
  final bool hasImage;

  String get reasonLabel => ReportReason.values
      .firstWhere((r) => r.code == reason, orElse: () => ReportReason.other)
      .label;

  static ContentReport fromRow(Map<String, dynamic> row) {
    final snapshot = row['content_snapshot'];
    final body = snapshot is Map ? snapshot['body']?.toString() : null;
    final imagePath = snapshot is Map
        ? snapshot['image_storage_path']?.toString()
        : null;

    return ContentReport(
      id: row['id'].toString(),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      subjectType: row['subject_type']?.toString() ?? 'message',
      reason: row['reason']?.toString() ?? 'other',
      status: row['status']?.toString() ?? 'open',
      reporterEmail: row['reporter_email']?.toString(),
      reportedEmail: row['reported_email']?.toString(),
      details: row['details']?.toString(),
      messageBody: (body ?? '').isEmpty ? null : body,
      hasImage: imagePath != null && imagePath.isNotEmpty,
    );
  }
}

/// Filing reports, and — for operators — reading the queue back.
class ReportService {
  ReportService(this._supabase);

  final SupabaseClient _supabase;

  Future<void> reportMessage({
    required String messageId,
    required ReportReason reason,
    String? details,
  }) async {
    await _file({
      'subjectType': 'message',
      'messageId': messageId,
      'reason': reason.code,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

  Future<void> reportUser({
    required String userId,
    required ReportReason reason,
    String? conversationId,
    String? details,
  }) async {
    await _file({
      'subjectType': 'user',
      'reportedUserId': userId,
      'conversationId': ?conversationId,
      'reason': reason.code,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    });
  }

  Future<void> _file(Map<String, dynamic> body) async {
    final FunctionResponse response;
    try {
      response = await _supabase.functions.invoke('report-content', body: body);
    } on FunctionException catch (error) {
      // Non-2xx throws rather than returning a body, so the readable message
      // the function wrote is inside the exception rather than in hand.
      final details = error.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw StateError(
        message?.isNotEmpty == true
            ? message!
            : 'The report could not be sent (${error.status}).',
      );
    }

    final data = response.data;
    if (data is! Map || data['success'] != true) {
      throw StateError(
        (data is Map ? data['error']?.toString() : null) ??
            'The report could not be sent.',
      );
    }
  }

  /// How many reports are waiting. Zero for anyone who is not an operator:
  /// the row level security policy refuses the read rather than the client
  /// deciding whether to ask.
  Future<int> openReportCount() async {
    try {
      final rows = await _supabase
          .from('content_reports')
          .select('id')
          .eq('status', 'open');

      return rows.length;
    } catch (_) {
      // A non-operator is refused, which is not a failure worth surfacing.
      return 0;
    }
  }

  Future<List<ContentReport>> listOpenReports() async {
    final rows = await _supabase
        .from('content_reports')
        .select()
        .eq('status', 'open')
        .order('created_at', ascending: false)
        .limit(100);

    return rows
        .map((row) => ContentReport.fromRow(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}
