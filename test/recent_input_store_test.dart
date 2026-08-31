import 'package:art_reference_app/services/recent_input_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('login emails are normalized, deduplicated, and most recent first', () async {
    await RecentInputStore.rememberLoginEmail(' First@Example.com ');
    await RecentInputStore.rememberLoginEmail('second@example.com');
    final emails = await RecentInputStore.rememberLoginEmail('FIRST@example.com');

    expect(emails, ['first@example.com', 'second@example.com']);
  });

  test('histories enforce their limits', () async {
    for (var index = 0; index < 12; index++) {
      await RecentInputStore.rememberLoginEmail('person$index@example.com');
      await RecentInputStore.rememberAiPrompt('Prompt $index');
    }

    expect(await RecentInputStore.loginEmails(), hasLength(5));
    final prompts = await RecentInputStore.aiPrompts();
    expect(prompts, hasLength(10));
    expect(prompts.first, 'Prompt 11');
    expect(prompts.last, 'Prompt 2');
  });
}
