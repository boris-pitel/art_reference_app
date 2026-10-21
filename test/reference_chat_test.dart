import 'dart:async';
import 'dart:convert';

import 'package:art_reference_app/screens/reference_chat_screen.dart';
import 'package:art_reference_app/services/reference_chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeChatService extends ReferenceChatService {
  FakeChatService(this.invoke);
  final Future<Map<String, dynamic>> Function(
    String,
    String,
    Map<String, dynamic>,
  )
  invoke;
  @override
  Future<Map<String, dynamic>> call(
    String referenceId,
    String action, [
    Map<String, dynamic> values = const {},
  ]) => invoke(referenceId, action, values);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var admin = true;
  final calls = <Map<String, dynamic>>[];
  var turns = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  bool failSend = false;
  final image = {
    'id': 'attachment',
    'url': 'https://example.test/image.png',
    'label': 'Attachment',
  };
  Map<String, dynamic> data() => {
    'turns': turns,
    'images': [image],
  };
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/token')) {
      final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      String part(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      return http.Response(
        jsonEncode({
          'access_token':
              '${part({'alg': 'HS256'})}.${part({'exp': exp})}.signature',
          'refresh_token': 'refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'admin-user',
            'aud': 'authenticated',
            'email': 'admin@example.test',
            'app_metadata': {'is_admin': admin},
            'user_metadata': {},
            'created_at': '2026-10-21T00:00:00Z',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 200);
  });

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'test',
      httpClient: client,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    admin = true;
    calls.clear();
    turns = [];
    pending = null;
    failSend = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  });
  Future<void> login() => Supabase.instance.client.auth.signInWithPassword(
    email: 'admin@example.test',
    password: 'test-password',
  );
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReferenceChatScreen(
          referenceId: 'reference',
          selectedImageId: 'attachment',
          service: FakeChatService((reference, action, values) async {
            calls.add({'referenceId': reference, 'action': action, ...values});
            if (action == 'send') {
              if (failSend) throw StateError('Please try again');
              if (pending != null) return pending!.future;
            }
            return data();
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ordinary users cannot open or invoke reference chat', (
    tester,
  ) async {
    admin = false;
    await login();
    await open(tester);
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets(
    'attachment enters its parent conversation and duplicate taps send once',
    (tester) async {
      await login();
      await open(tester);
      expect(calls.single['referenceId'], 'reference');
      await tester.enterText(find.byType(TextField), 'Compare the shapes');
      pending = Completer<Map<String, dynamic>>();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      final sends = calls.where((call) => call['action'] == 'send').toList();
      expect(sends, hasLength(1));
      expect(sends.single['imageIds'], ['attachment']);
      expect(sends.single['requestId'], isNotEmpty);
      turns = [
        {
          'id': sends.single['requestId'],
          'text': 'Compare the shapes',
          'images': [],
          'answer': 'Use larger shapes.',
          'generated': [],
        },
      ];
      pending!.complete(data());
      await tester.pumpAndSettle();
      expect(find.text('Use larger shapes.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await open(tester);
      expect(find.text('Use larger shapes.'), findsOneWidget);
    },
  );

  testWidgets('failed send preserves the draft and reuses its retry ID', (
    tester,
  ) async {
    await login();
    await open(tester);
    failSend = true;
    await tester.enterText(find.byType(TextField), 'Keep my question');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my question',
    );
    final first = calls.last['requestId'];
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(calls.last['requestId'], first);
  });

  testWidgets(
    'reopening after a lost reply clears the already committed draft',
    (tester) async {
      await login();
      SharedPreferences.setMockInitialValues({
        'reference_chat_draft_admin-user/reference': jsonEncode({
          'text': 'Already sent',
          'images': ['attachment'],
          'requestId': 'committed',
        }),
      });
      turns = [
        {
          'id': 'committed',
          'text': 'Already sent',
          'images': [],
          'answer': 'Saved answer',
          'generated': [],
        },
      ];
      await open(tester);
      expect(find.text('Saved answer'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(calls.where((call) => call['action'] == 'send'), isEmpty);
    },
  );

  testWidgets('saved generated images cannot be attached a second time', (
    tester,
  ) async {
    await login();
    turns = [
      {
        'id': 'generated-turn',
        'text': 'Make a study',
        'images': [],
        'answer': 'Here is the study.',
        'generated': [
          {
            'id': 'generated',
            'url': 'https://example.test/result.png',
            'savedImageId': 'saved',
          },
        ],
      },
    ];
    await open(tester);
    final saved = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Saved'),
    );
    expect(saved.onPressed, isNull);
    await tester.runAsync(() => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await tester.pumpAndSettle();
    expect(find.text('Administrator access required.'), findsOneWidget);
    expect(find.text('Here is the study.'), findsNothing);
  });
}
