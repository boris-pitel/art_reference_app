import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/audit_page.dart';
import 'screens/activity_page.dart';
import 'screens/feedback_page.dart';
import 'screens/users_page.dart';
import 'services/admin_audit_log.dart';
import 'services/admin_config.dart';
import 'services/admin_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = await AdminConfig.load();
    final service = AdminService(
      url: config.supabaseUrl,
      secretKey: config.secretKey,
    );
    final repositoryRoot = config.sourcePath == 'process environment'
        ? Directory.current
        : File(config.sourcePath).parent;
    runApp(
      PainterAdminApp(
        service: service,
        auditLog: AdminAuditLog(repositoryRoot: repositoryRoot),
        configurationSource: config.sourcePath,
        passwordRedirectUrl: config.passwordRedirectUrl,
      ),
    );
  } on Object catch (error) {
    runApp(ConfigurationErrorApp(error: error.toString()));
  }
}

class PainterAdminApp extends StatelessWidget {
  const PainterAdminApp({
    super.key,
    required this.service,
    required this.auditLog,
    required this.configurationSource,
    required this.passwordRedirectUrl,
  });

  final AdminService service;
  final AdminAuditLog auditLog;
  final String configurationSource;
  final String? passwordRedirectUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6B4E8A),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Painter Reference Admin',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF9F6FB),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: AdminShell(
        service: service,
        auditLog: auditLog,
        configurationSource: configurationSource,
        passwordRedirectUrl: passwordRedirectUrl,
      ),
    );
  }
}

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.service,
    required this.auditLog,
    required this.configurationSource,
    required this.passwordRedirectUrl,
  });

  final AdminService service;
  final AdminAuditLog auditLog;
  final String configurationSource;
  final String? passwordRedirectUrl;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      UsersPage(
        service: widget.service,
        auditLog: widget.auditLog,
        passwordRedirectUrl: widget.passwordRedirectUrl,
      ),
      FeedbackPage(service: widget.service, auditLog: widget.auditLog),
      ActivityPage(service: widget.service),
      AuditPage(auditLog: widget.auditLog),
    ];
    const titles = ['Users', 'Feedback', 'User Activity', 'Admin Audit Log'];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            extended: true,
            leading: const Padding(
              padding: EdgeInsets.fromLTRB(12, 20, 12, 28),
              child: Column(
                children: [
                  Icon(Icons.palette_outlined, size: 40),
                  SizedBox(height: 8),
                  Text(
                    'Painter Reference\nAdministration',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('Users'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.feedback_outlined),
                selectedIcon: Icon(Icons.feedback),
                label: Text('Feedback'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                selectedIcon: Icon(Icons.monitor_heart),
                label: Text('User Activity'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('Admin Audit Log'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 18,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            titles[_index],
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Tooltip(
                          message: 'Credentials: ${widget.configurationSource}',
                          child: const Chip(
                            avatar: Icon(Icons.lock_outline, size: 18),
                            label: Text('Local privileged session'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: IndexedStack(index: _index, children: pages),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B4E8A)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 52),
                    const SizedBox(height: 16),
                    Text(
                      'Painter Reference Admin',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The administration console cannot start until local '
                      'Supabase credentials are configured.',
                    ),
                    const SizedBox(height: 16),
                    SelectableText(error),
                    const SizedBox(height: 16),
                    const Text(
                      'Create .env.admin beside the repository or executable, '
                      'then restart the application. This file is excluded from Git.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
