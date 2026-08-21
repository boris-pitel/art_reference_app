import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/user_activity_logger.dart';

/// The version of the documents currently in force.
///
/// Recorded alongside each acceptance, so that when the documents change it is
/// possible to tell who agreed to which version and who still needs to see the
/// new one. Bump this whenever either document changes materially.
const String legalDocumentVersion = '1.0';

const String _privacyUrl = 'https://painterreference.com/privacy';
const String _termsUrl = 'https://painterreference.com/terms';

/// The line beneath the sign-in buttons that makes the agreement binding.
///
/// It sits under *both* buttons rather than inside the create-account branch,
/// so it is present on every sign-in and covers the Google path — which has no
/// form at all, just a single tap. Notice placed beside the action is what
/// makes tapping it an agreement; a link elsewhere in the app would not.
class LegalAgreementNotice extends StatelessWidget {
  const LegalAgreementNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    final linkStyle = baseStyle?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'By continuing you agree to the '),
            TextSpan(
              text: 'Terms',
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _open(context, _termsUrl, 'terms'),
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _open(context, _privacyUrl, 'privacy_policy'),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  static Future<void> _open(
    BuildContext context,
    String url,
    String document,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) throw StateError('The browser declined to open $url.');
    } catch (error) {
      // Someone tapping this is trying to read what they are agreeing to.
      // Failing silently would leave them agreeing to something they were
      // prevented from seeing.
      UserActivityLogger.instance.record(
        operation: 'legal_document_open',
        status: 'failed',
        targetType: 'document',
        targetId: document,
        error: error,
      );

      messenger?.showSnackBar(
        SnackBar(content: Text('Unable to open the document. Visit $url')),
      );
    }
  }
}

/// Records that an account was created under a specific version of the
/// documents.
///
/// This is the closest thing to a signature that exists here: the user tapped
/// a button with the notice beside it, and this is the record of when, and of
/// which version was in force at the time.
void recordLegalAcceptance({required String method}) {
  UserActivityLogger.instance.record(
    operation: 'terms_accepted',
    status: 'succeeded',
    targetType: 'account',
    details: {'version': legalDocumentVersion, 'method': method},
  );
}
