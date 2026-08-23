import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the two ways an icon can be on screen and invisible.
///
/// Both happened to the monochrome and grid controls at once, which is why
/// neither could be ruled out by looking: they were laid out, took up space in
/// the app bar, and drew nothing.

/// Icons above the basic multilingual plane are unreliable on Flutter web: the
/// codepoint becomes a surrogate pair and the glyph can fail to render even
/// though the font contains it. Every icon on a screen the web build serves has
/// to sit below this line.
const int _highestSafeCodepoint = 0xFFFF;

/// What colour an icon is actually painted.
///
/// Icons render as text, so the colour reaching the screen is the one on the
/// span — not whatever was passed in, and not necessarily the ambient theme.
Color? paintedColour(WidgetTester tester, IconData icon) {
  final richText = tester.widget<RichText>(
    find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
  );
  return richText.text.style?.color;
}

void main() {
  group('icons used on the black image viewer', () {
    test('sit inside the plane Flutter web renders reliably', () {
      const used = <String, IconData>{
        'monochrome': Icons.tonality,
        'composition grid': Icons.grid_on,
        'reset zoom': Icons.fit_screen_outlined,
        'share': Icons.share_outlined,
        'save': Icons.download_outlined,
      };

      for (final entry in used.entries) {
        expect(
          entry.value.codePoint,
          lessThanOrEqualTo(_highestSafeCodepoint),
          reason:
              '${entry.key} is 0x${entry.value.codePoint.toRadixString(16)}, '
              'above the basic plane, where it may not render on web',
        );
      }
    });

    testWidgets('are painted a colour that shows on black', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          home: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.tonality),
                  color: Colors.white,
                ),
                PopupMenuButton<int>(
                  icon: const Icon(Icons.grid_on),
                  iconColor: Colors.white,
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 1, child: Text('Off')),
                  ],
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );

      for (final icon in const [Icons.tonality, Icons.grid_on]) {
        final colour = paintedColour(tester, icon);

        expect(colour, isNotNull, reason: 'no colour reached the glyph');
        expect(
          colour,
          isNot(Colors.black),
          reason: 'black on a black app bar is invisible',
        );
        // Stated rather than inherited: the bug was a null colour resolving to
        // whatever the theme chose, which on this screen was dark.
        expect(colour, Colors.white);
      }
    });
  });
}
