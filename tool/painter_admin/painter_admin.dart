import 'dart:io';

import 'src/admin_config.dart';
import 'src/admin_service.dart';
import 'src/audit_log.dart';
import 'src/console_io.dart';

Future<void> main(List<String> arguments) async {
  const console = ConsoleIo();
  if (arguments.isEmpty ||
      arguments.contains('--help') ||
      arguments.contains('-h')) {
    _printHelp(console);
    return;
  }

  try {
    final config = AdminConfig.fromEnvironment();
    final service = AdminService(
      url: config.supabaseUrl,
      secretKey: config.secretKey,
    );
    final audit = AuditLog();
    exitCode = await _run(arguments, service, audit, console, config);
  } on Object catch (error) {
    console.error('ERROR: $error');
    exitCode = 1;
  }
}

Future<int> _run(
  List<String> arguments,
  AdminService service,
  AuditLog audit,
  ConsoleIo console,
  AdminConfig config,
) async {
  if (arguments.first == 'feedback') {
    return _runFeedback(arguments, service, audit, console);
  }
  if (arguments.first == 'images') {
    return _runImages(arguments, service, audit, console);
  }
  if (arguments.first != 'users') {
    throw UsageException(
      'Expected the resource "users", "feedback", or "images".',
    );
  }
  if (arguments.length < 2) {
    throw UsageException('A users command is required.');
  }

  final command = arguments[1];
  switch (command) {
    case 'list':
      final users = await service.listUsers();
      if (users.isEmpty) {
        console.out('No registered users.');
        return 0;
      }
      console.out('EMAIL | CREATED | LAST SIGN-IN | ID');
      for (final user in users) {
        console.out(
          '${user.email ?? '(no email)'} | ${_date(user.createdAt)} | '
          '${_date(user.lastSignInAt)} | ${user.id}',
        );
      }
      console.out('\n${users.length} registered user(s).');
      return 0;

    case 'show':
      final email = _requiredEmail(arguments);
      final inventory = await service.inventoryForEmail(email);
      _printInventory(console, inventory);
      return 0;

    case 'remove':
      final email = _requiredEmail(arguments);
      final dryRun = arguments.contains('--dry-run');
      final inventory = await service.inventoryForEmail(email);
      _printInventory(console, inventory);
      if (dryRun) {
        console.out('\nDry run only. Nothing was deleted.');
        return 0;
      }

      console.out();
      console.out('DANGER: PERMANENT ACCOUNT REMOVAL');
      console.out(
        'This deletes the login, database records, and stored files.',
      );
      console.out('This operation cannot be undone.');
      final phrase = 'REMOVE ${inventory.email.toLowerCase()}';
      final confirmation = console.readLine('Type "$phrase" to continue: ');
      if (confirmation != phrase) {
        console.out('Confirmation did not match. Nothing was deleted.');
        return 2;
      }

      try {
        final databaseResult = await service.removeUser(inventory);
        await audit.write(
          action: 'users.remove',
          targetEmail: inventory.email,
          authUserId: inventory.user.id,
          result: 'success',
          details: {
            ...inventory.toAuditDetails(),
            'database_result': databaseResult,
          },
        );
        console.out('User and associated data were permanently removed.');
        return 0;
      } on Object catch (error) {
        await audit.write(
          action: 'users.remove',
          targetEmail: inventory.email,
          authUserId: inventory.user.id,
          result: 'failed',
          details: {...inventory.toAuditDetails(), 'error': error.toString()},
        );
        rethrow;
      }

    case 'password-reset':
      final email = _requiredEmail(arguments);
      final user = await service.findUserByEmail(email);
      final phrase = 'SEND RESET ${user.email!.toLowerCase()}';
      console.out('A Supabase recovery email will be sent to ${user.email}.');
      final confirmation = console.readLine('Type "$phrase" to continue: ');
      if (confirmation != phrase) {
        console.out('Confirmation did not match. No email was sent.');
        return 2;
      }
      try {
        await service.sendPasswordReset(
          user.email!,
          redirectUrl: config.passwordRedirectUrl,
        );
        await audit.write(
          action: 'users.password-reset',
          targetEmail: user.email!,
          authUserId: user.id,
          result: 'success',
          details: {
            if (config.passwordRedirectUrl != null)
              'redirect_url': config.passwordRedirectUrl,
          },
        );
        console.out('Password recovery email requested successfully.');
        return 0;
      } on Object catch (error) {
        await audit.write(
          action: 'users.password-reset',
          targetEmail: user.email!,
          authUserId: user.id,
          result: 'failed',
          details: {'error': error.toString()},
        );
        rethrow;
      }

    case 'set-password':
      final email = _requiredEmail(arguments);
      final user = await service.findUserByEmail(email);
      final phrase = 'SET PASSWORD ${user.email!.toLowerCase()}';
      console.out('WARNING: This directly replaces the user password.');
      final confirmation = console.readLine('Type "$phrase" to continue: ');
      if (confirmation != phrase) {
        console.out('Confirmation did not match. Password was not changed.');
        return 2;
      }
      final password = console.readHidden('New password (12+ characters): ');
      final repeated = console.readHidden('Repeat new password: ');
      if (password != repeated) {
        throw StateError('Passwords did not match.');
      }
      try {
        await service.setPassword(user.email!, password);
        await audit.write(
          action: 'users.set-password',
          targetEmail: user.email!,
          authUserId: user.id,
          result: 'success',
        );
        console.out(
          'Password changed successfully. The password was not logged.',
        );
        return 0;
      } on Object catch (error) {
        await audit.write(
          action: 'users.set-password',
          targetEmail: user.email!,
          authUserId: user.id,
          result: 'failed',
          details: {'error': error.toString()},
        );
        rethrow;
      }

    default:
      throw UsageException('Unknown users command: $command');
  }
}

Future<int> _runFeedback(
  List<String> arguments,
  AdminService service,
  AuditLog audit,
  ConsoleIo console,
) async {
  if (arguments.length < 2) {
    throw UsageException('A feedback command is required.');
  }
  switch (arguments[1]) {
    case 'list':
      final status = _optionValue(arguments, '--status');
      final rows = await service.listFeedback(status: status);
      if (rows.isEmpty) {
        console.out('No feedback found.');
        return 0;
      }
      console.out('CREATED | STATUS | TYPE | EMAIL | ID | COMMENT');
      for (final row in rows) {
        final comment = row['comment'].toString().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        final summary = comment.length > 60
            ? '${comment.substring(0, 57)}...'
            : comment;
        console.out(
          "${row['created_at']} | ${row['status']} | ${row['feedback_type']} | "
          "${row['user_email']} | ${row['id']} | $summary",
        );
      }
      console.out('\n${rows.length} feedback item(s).');
      return 0;

    case 'show':
      final id = _requiredArgument(arguments, 2, 'feedback ID');
      final row = await service.getFeedback(id);
      _printFeedback(console, row);
      final attachmentUrl = await service.feedbackAttachmentUrl(row);
      if (attachmentUrl != null) {
        console.out('Attachment URL: $attachmentUrl');
        console.out('(The private link expires in one hour.)');
      }
      return 0;

    case 'status':
      final id = _requiredArgument(arguments, 2, 'feedback ID');
      final status = _requiredArgument(arguments, 3, 'status').toLowerCase();
      final phrase = 'SET FEEDBACK $id $status';
      final confirmation = console.readLine('Type "$phrase" to continue: ');
      if (confirmation != phrase) {
        console.out('Confirmation did not match. Status was not changed.');
        return 2;
      }
      try {
        final row = await service.updateFeedbackStatus(id, status);
        await audit.write(
          action: 'feedback.status',
          targetEmail: row['user_email']?.toString() ?? '',
          authUserId: row['user_id']?.toString(),
          result: 'success',
          details: {'feedback_id': id, 'status': status},
        );
        console.out('Feedback $id is now $status.');
        return 0;
      } on Object catch (error) {
        await audit.write(
          action: 'feedback.status',
          targetEmail: '',
          result: 'failed',
          details: {
            'feedback_id': id,
            'status': status,
            'error': error.toString(),
          },
        );
        rethrow;
      }

    default:
      throw UsageException('Unknown feedback command: ${arguments[1]}');
  }
}

Future<int> _runImages(
  List<String> arguments,
  AdminService service,
  AuditLog audit,
  ConsoleIo console,
) async {
  if (arguments.length < 2) {
    throw UsageException('An images command is required.');
  }
  switch (arguments[1]) {
    case 'backfill-dimensions':
      final dryRun = arguments.contains('--dry-run');
      if (!dryRun && !arguments.contains('--yes')) {
        console.out(
          'This updates width/height (and, where still recoverable, '
          'camera/lens/aperture/etc.) on every image_assets row missing '
          'dimensions. Existing non-null fields are never overwritten.',
        );
        final confirmation = console.readLine(
          'Type "BACKFILL DIMENSIONS" to continue: ',
        );
        if (confirmation != 'BACKFILL DIMENSIONS') {
          console.out('Confirmation did not match. Nothing was changed.');
          return 2;
        }
      }

      final result = await service.backfillPhotoDimensions(
        dryRun: dryRun,
        onProgress: console.out,
      );

      console.out();
      console.out(
        'Done. ${result.updated} updated, ${result.skipped} skipped, '
        '${result.failed} failed, out of ${result.total} total'
        '${dryRun ? ' (dry run, nothing written)' : ''}.',
      );

      if (!dryRun) {
        await audit.write(
          action: 'images.backfill-dimensions',
          targetEmail: '',
          result: result.failed == 0 ? 'success' : 'partial',
          details: {
            'total': result.total,
            'updated': result.updated,
            'skipped': result.skipped,
            'failed': result.failed,
          },
        );
      }

      return result.failed == 0 ? 0 : 1;

    case 'backfill-display':
      final dryRun = arguments.contains('--dry-run');
      if (!dryRun && !arguments.contains('--yes')) {
        console.out(
          'This generates a ~3072px display derivative for every '
          'image_assets row missing one, and uploads it to Storage.',
        );
        final confirmation = console.readLine(
          'Type "BACKFILL DISPLAY" to continue: ',
        );
        if (confirmation != 'BACKFILL DISPLAY') {
          console.out('Confirmation did not match. Nothing was changed.');
          return 2;
        }
      }

      final result = await service.backfillDisplayImages(
        dryRun: dryRun,
        onProgress: console.out,
      );

      console.out();
      console.out(
        'Done. ${result.updated} updated, ${result.skipped} skipped, '
        '${result.failed} failed, out of ${result.total} total'
        '${dryRun ? ' (dry run, nothing written)' : ''}.',
      );

      if (!dryRun) {
        await audit.write(
          action: 'images.backfill-display',
          targetEmail: '',
          result: result.failed == 0 ? 'success' : 'partial',
          details: {
            'total': result.total,
            'updated': result.updated,
            'skipped': result.skipped,
            'failed': result.failed,
          },
        );
      }

      return result.failed == 0 ? 0 : 1;

    default:
      throw UsageException('Unknown images command: ${arguments[1]}');
  }
}

String _requiredArgument(List<String> arguments, int index, String name) {
  if (arguments.length <= index || arguments[index].startsWith('-')) {
    throw UsageException('This command requires a $name.');
  }
  return arguments[index];
}

String? _optionValue(List<String> arguments, String option) {
  final index = arguments.indexOf(option);
  if (index < 0) return null;
  return _requiredArgument(arguments, index + 1, option);
}

String _requiredEmail(List<String> arguments) {
  if (arguments.length < 3 || arguments[2].startsWith('-')) {
    throw UsageException('This command requires an email address.');
  }
  return arguments[2];
}

void _printInventory(ConsoleIo console, UserInventory inventory) {
  console.out('User:             ${inventory.email}');
  console.out('Auth user ID:     ${inventory.user.id}');
  console.out('Data owner ID:    ${inventory.dataUserId}');
  console.out('Created:          ${_date(inventory.user.createdAt)}');
  console.out('Last sign-in:     ${_date(inventory.user.lastSignInAt)}');
  console.out('Images:           ${inventory.images.length}');
  console.out(
    'Custom categories:${inventory.categories.length.toString().padLeft(2)}',
  );
  for (final entry in inventory.storagePathsByBucket.entries) {
    console.out(
      'Storage ${entry.key.padRight(17)} ${entry.value.length} file(s)',
    );
  }
  console.out('Total files:      ${inventory.storageFileCount}');
}

void _printFeedback(ConsoleIo console, Map<String, dynamic> row) {
  console.out("ID:          ${row['id']}");
  console.out("Created:     ${row['created_at']}");
  console.out("Status:      ${row['status']}");
  console.out("Type:        ${row['feedback_type']}");
  console.out("User:        ${row['user_email']}");
  console.out("User ID:     ${row['user_id']}");
  console.out("Platform:    ${row['platform']}");
  console.out("App version: ${row['app_version']}");
  console.out("Screen:      ${row['current_screen'] ?? '-'}");
  console.out("Attachment:  ${row['attachment_path'] ?? '-'}");
  console.out('Comment:');
  console.out(row['comment']?.toString() ?? '');
}

String _date(Object? value) {
  if (value == null) return '-';
  if (value is DateTime) return value.toUtc().toIso8601String();
  return value.toString();
}

void _printHelp(ConsoleIo console) {
  console.out('Painter Reference administration console');
  console.out();
  console.out('Usage:');
  console.out('  painter-admin users list');
  console.out('  painter-admin users show EMAIL');
  console.out('  painter-admin users remove EMAIL [--dry-run]');
  console.out('  painter-admin users password-reset EMAIL');
  console.out('  painter-admin feedback list [--status STATUS]');
  console.out('  painter-admin feedback show ID');
  console.out('  painter-admin feedback status ID STATUS');
  console.out('    STATUS: new, reviewed, planned, resolved, or closed');
  console.out('  painter-admin users set-password EMAIL');
  console.out(
    '  painter-admin images backfill-dimensions [--dry-run] [--yes]',
  );
  console.out(
    '  painter-admin images backfill-display [--dry-run] [--yes]',
  );
  console.out();
  console.out('Required environment variables:');
  console.out('  SUPABASE_URL');
  console.out('  SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY)');
  console.out();
  console.out('Optional: SUPABASE_PASSWORD_REDIRECT_URL');
}

class UsageException implements Exception {
  UsageException(this.message);
  final String message;
  @override
  String toString() => '$message Run with --help for usage.';
}
