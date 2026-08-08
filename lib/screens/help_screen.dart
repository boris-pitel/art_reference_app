import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_version.dart';
import 'feedback_screen.dart';
import '../widgets/home_button.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Painter Reference'),
          actions: const [HomeButton()],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.auto_stories_outlined),
                text: 'Introduction',
              ),
              Tab(icon: Icon(Icons.help_outline), text: 'How To'),
              Tab(icon: Icon(Icons.info_outline), text: 'About'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_IntroductionPage(), _HowToPage(), _AboutPage()],
        ),
      ),
    );
  }
}

class _IntroductionPage extends StatelessWidget {
  const _IntroductionPage();

  @override
  Widget build(BuildContext context) {
    return const _HelpPage(
      children: [
        _HelpTitle('Welcome to Painter Reference'),
        _HelpParagraph(
          'Painter Reference is a personal library for collecting, organizing, '
          'finding, and using the photographs that inspire your artwork.',
        ),
        _HelpParagraph(
          'Your library is connected to your account, so you can work with '
          'the same references across supported phones, tablets, Windows '
          'desktop computers, and web browsers.',
        ),
        _HelpSectionTitle('Organize your inspiration'),
        _HelpParagraph(
          'Start with the built-in artistic categories or create your own. '
          'Custom categories can be renamed, given a cover image, or removed '
          'when they are no longer needed.',
        ),
        _HelpParagraph(
          'A reference can be connected to more than one category without '
          'uploading another copy. You can also move it from one category to '
          'another.',
        ),
        _HelpSectionTitle('Find useful references again'),
        _HelpParagraph(
          'Add a title, notes, author, favorite status, and searchable '
          'keywords to each reference. Keyword search helps bring the right '
          'images back when you need them.',
        ),
        _HelpSectionTitle('Connect references with your artwork'),
        _HelpParagraph(
          'Attach sketches, studies, works in progress, crops, edited '
          'versions, or completed artwork to an original reference. '
          'Associated images can be opened, shared, saved, or removed.',
        ),
        _HelpSectionTitle('Use references anywhere'),
        _HelpParagraph(
          'Share reference images through your device, save them to Photos, '
          'or print them. On the web, saving an associated image downloads it '
          'through the browser.',
        ),
        _HelpSectionTitle('Optional AI assistance'),
        _HelpParagraph(
          'When you choose Analyze with AI, Painter Reference can describe the '
          'subject, lighting, composition, dominant colors, and useful '
          'artistic observations. Suggested keywords can be added to your '
          'reference with a tap.',
        ),
        _HelpParagraph(
          'AI analysis is never started automatically; it runs only when you '
          'request it.',
        ),
        _HelpClosing('Spend less time searching and more time creating.'),
      ],
    );
  }
}

// Kept temporarily as a fallback while the Markdown guide is adopted.
// ignore: unused_element
class _BuiltInHowToPage extends StatelessWidget {
  const _BuiltInHowToPage();

  @override
  Widget build(BuildContext context) {
    return const _HelpPage(
      children: [
        _HelpTitle('How to Use Painter Reference'),
        _HelpSectionTitle('Create an account'),
        _NumberedInstruction(number: 1, text: 'Select Create Account.'),
        _NumberedInstruction(
          number: 2,
          text: 'Enter your email address and choose a password.',
        ),
        _NumberedInstruction(
          number: 3,
          text:
              'Confirm your email if confirmation is requested, then sign in.',
        ),
        _HelpSectionTitle('Manage categories'),
        _HelpParagraph(
          'Tap Add Category to create a custom category. Use the three-dot '
          'menu on a custom category to rename it, change its cover image, or '
          'delete it. Built-in categories cannot be renamed or deleted.',
        ),
        _HelpParagraph(
          'Deleting a custom category removes its category connections but '
          'does not delete the original image files.',
        ),
        _HelpSectionTitle('Add a reference image'),
        _NumberedInstruction(
          number: 1,
          text: 'Open the category where the reference should appear.',
        ),
        _NumberedInstruction(number: 2, text: 'Tap Add Photo Reference.'),
        _NumberedInstruction(
          number: 3,
          text: 'Choose Gallery, or use Camera when it is available.',
        ),
        _NumberedInstruction(
          number: 4,
          text: 'Allow the requested photo or camera permission.',
        ),
        _NumberedInstruction(
          number: 5,
          text:
              'Wait for the original image and thumbnail to finish uploading.',
        ),
        _HelpSectionTitle('Import from another app'),
        _HelpParagraph(
          'On platforms that support direct sharing into Painter Reference, use '
          'the Share command in a browser or photo app, choose Painter Reference, '
          'then select the destination category. If Painter Reference is not '
          'listed, save the image first and add it from Gallery.',
        ),
        _HelpSectionTitle('View and export a reference'),
        _HelpParagraph(
          'Tap a thumbnail to open its details. The image menu provides Share, '
          'Save to Photos, and Print actions. On a desktop or web browser, '
          'available actions may depend on the operating system and browser.',
        ),
        _HelpParagraph(
          'While viewing image details, swipe left for the next reference or '
          'right for the previous reference in the current category. Vertical '
          'swipes continue to scroll through the details.',
        ),
        _HelpSectionTitle('Add details and keywords'),
        _HelpParagraph(
          'Open a reference to add its title, notes, author, favorite '
          'status, and keywords. Tap Save Details after editing the reference '
          'information. Use the search button on the main screen to find '
          'references by keyword.',
        ),
        _HelpSectionTitle('Organize a reference'),
        _HelpParagraph(
          'Use Move to transfer a reference between categories. Uploading the '
          'same image into another category connects the existing original '
          'instead of storing a duplicate file.',
        ),
        _HelpSectionTitle('Add associated images'),
        _NumberedInstruction(number: 1, text: 'Open the original reference.'),
        _NumberedInstruction(
          number: 2,
          text:
              'Scroll to Associated Images and choose Attach Image or Camera.',
        ),
        _NumberedInstruction(
          number: 3,
          text:
              'Select a sketch, study, work in progress, crop, or finished artwork.',
        ),
        _NumberedInstruction(
          number: 4,
          text: 'Crop, rotate, or straighten the sketch, then tap Done.',
        ),
        _HelpParagraph(
          'Tap an associated image to open its details. Swipe left or right to '
          'move through the other images associated with the same reference. '
          'Open an associated sketch, then tap the image to enter the full-screen '
          'Image window. Use Edit sketch there to crop, rotate, straighten, or '
          'change its proportions. Reference photos do not show editing controls. '
          'The sketch menu also provides Share and Save '
          'actions. Delete removes the association and may remove the file '
          'when it has no other connections.',
        ),
        _HelpSectionTitle('Use AI analysis'),
        _NumberedInstruction(number: 1, text: 'Open a reference image.'),
        _NumberedInstruction(number: 2, text: 'Tap Analyze with AI.'),
        _NumberedInstruction(
          number: 3,
          text:
              'Review the description, lighting, composition, colors, keywords, and artist notes.',
        ),
        _NumberedInstruction(
          number: 4,
          text:
              'Tap a suggested keyword if you want to add it to the reference.',
        ),
        _HelpSectionTitle('Remove a reference from a category'),
        _HelpParagraph(
          'Choose Remove while viewing a reference. Removing it from one '
          'category leaves any connections to other categories in place. If '
          'this is the reference’s final category, the original reference and '
          'its associated images are permanently deleted.',
        ),
        _HelpSectionTitle('Refresh and troubleshoot'),
        _HelpParagraph(
          'Use the refresh button if a recently uploaded image, category '
          'cover, or associated image has not appeared yet. Check your '
          'internet connection before retrying an upload or AI analysis.',
        ),
        _HelpSectionTitle('Sign out'),
        _HelpParagraph(
          'Open the account menu and select Sign Out. Your library remains '
          'connected to your account and is available when you sign in again.',
        ),
      ],
    );
  }
}

class _HowToPage extends StatelessWidget {
  const _HowToPage();

  static final Future<String> _contents = rootBundle.loadString(
    'assets/help/how_to.md',
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _contents,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _HelpPage(
            children: [
              _HelpTitle('How To'),
              _HelpParagraph('The How To guide could not be loaded.'),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _HelpPage(children: _markdownHelpWidgets(snapshot.data!));
      },
    );
  }
}

List<Widget> _markdownHelpWidgets(String markdown) {
  final widgets = <Widget>[];
  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('# ')) {
      widgets.add(_HelpTitle(line.substring(2)));
    } else if (line.startsWith('## ')) {
      widgets.add(_HelpSectionTitle(line.substring(3)));
    } else if (RegExp(r'^\d+\. ').hasMatch(line)) {
      final match = RegExp(r'^(\d+)\. (.*)$').firstMatch(line)!;
      widgets.add(
        _NumberedInstruction(
          number: int.parse(match.group(1)!),
          text: match.group(2)!,
        ),
      );
    } else if (line.startsWith('- ')) {
      widgets.add(_HelpParagraph('• ${line.substring(2)}'));
    } else {
      widgets.add(_HelpParagraph(line));
    }
  }
  return widgets;
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _HelpPage(
      children: [
        const SizedBox(height: 12),
        Center(
          child: Icon(
            Icons.palette_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Painter Reference',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          appVersionLabel,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 28),
        const _HelpParagraph(
          'Painter Reference is a cross-platform personal image library for '
          'artists who collect and use reference photographs in their '
          'creative work.',
        ),
        const _HelpParagraph(
          'It combines custom categories, searchable details and keywords, '
          'associated artwork, sharing and saving tools, and optional AI '
          'analysis in one focused workspace.',
        ),
        const _HelpParagraph(
          'Painter Reference was created to solve a practical problem: useful '
          'images are easily scattered or forgotten, while the connection '
          'between a reference and the artwork it inspired is often lost.',
        ),
        const _HelpSectionTitle('Data and Privacy'),
        const _HelpParagraph(
          'Your account information, library details, and uploaded images are '
          'stored online so your library can be available across supported '
          'devices. Access to your personal library requires your account.',
        ),
        const _HelpParagraph(
          'AI analysis is optional. A reference image is sent to the analysis '
          'service only after you tap Analyze with AI; the app does not start '
          'AI analysis automatically.',
        ),
        const _HelpSectionTitle('Artificial Intelligence'),
        const _HelpParagraph(
          'Optional image analysis is currently provided by OpenAI using the '
          'GPT-5 mini vision-capable model. The active provider or model may '
          'change as the service evolves; Painter Reference will disclose the '
          'provider used for an analysis and will not analyze an image without '
          'your request.',
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        Center(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FeedbackScreen(currentScreen: 'about'),
                ),
              );
            },
            icon: const Icon(Icons.feedback_outlined),
            label: const Text('Send Feedback'),
          ),
        ),
        Text(
          'Copyright 2026 Boris Pitel',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'All rights reserved.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        const _HelpClosing(
          'Thank you for using Painter Reference.\n\nHappy painting!',
        ),
      ],
    );
  }
}

class _HelpPage extends StatelessWidget {
  const _HelpPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          children: children,
        ),
      ),
    );
  }
}

class _HelpTitle extends StatelessWidget {
  const _HelpTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _HelpSectionTitle extends StatelessWidget {
  const _HelpSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 9),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _HelpParagraph extends StatelessWidget {
  const _HelpParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }
}

class _HelpClosing extends StatelessWidget {
  const _HelpClosing(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    );
  }
}

class _NumberedInstruction extends StatelessWidget {
  const _NumberedInstruction({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
