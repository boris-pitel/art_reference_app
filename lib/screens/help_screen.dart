import 'package:flutter/material.dart';

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
          title: const Text('Art Reference'),
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
        _HelpTitle('Welcome to Art Reference'),
        _HelpParagraph(
          'Every artist collects reference images: a beautiful face, '
          'an interesting building, dramatic lighting, a quiet landscape, '
          'or an unusual still life.',
        ),
        _HelpParagraph(
          'Over time, these images become scattered across phones, '
          'computers, downloads, cloud storage, email, and social media. '
          'Finding the right reference becomes difficult, and useful images '
          'are easily forgotten.',
        ),
        _HelpParagraph(
          'Art Reference is a personal image library designed specifically '
          'for artists. It helps you collect, organize, find, and use your '
          'reference photographs.',
        ),
        _HelpSectionTitle('Organize your inspiration'),
        _HelpParagraph(
          'References can be organized into artistic categories such as '
          'Portrait, Landscape, Architecture, Still Life, Abstract, and Icon.',
        ),
        _HelpParagraph(
          'A single reference may belong to more than one category without '
          'creating another copy of the image.',
        ),
        _HelpSectionTitle('Connect references with your artwork'),
        _HelpParagraph(
          'You can attach sketches, studies, works in progress, and completed '
          'artwork to the original reference image. This keeps the complete '
          'creative process together.',
        ),
        _HelpSectionTitle('AI assistance'),
        _HelpParagraph(
          'Art Reference can analyze an image and suggest useful categories, '
          'keywords, descriptions, and artistic observations.',
        ),
        _HelpParagraph(
          'The goal is simple: spend less time managing photographs and more '
          'time creating art.',
        ),
        _HelpClosing('Welcome to Art Reference, and happy painting!'),
      ],
    );
  }
}

class _HowToPage extends StatelessWidget {
  const _HowToPage();

  @override
  Widget build(BuildContext context) {
    return const _HelpPage(
      children: [
        _HelpTitle('How to Use Art Reference'),
        _HelpSectionTitle('Create an account'),
        _NumberedInstruction(
          number: 1,
          text: 'Open Art Reference and select Create Account.',
        ),
        _NumberedInstruction(
          number: 2,
          text: 'Enter your email address and choose a password.',
        ),
        _NumberedInstruction(
          number: 3,
          text: 'Complete email confirmation if it is requested.',
        ),
        _NumberedInstruction(
          number: 4,
          text: 'Sign in using the same email address and password.',
        ),
        _HelpSectionTitle('Add a reference image'),
        _NumberedInstruction(
          number: 1,
          text: 'Open the category where you want the reference to appear.',
        ),
        _NumberedInstruction(number: 2, text: 'Tap Add Photo Reference.'),
        _NumberedInstruction(
          number: 3,
          text: 'Choose an image from your device.',
        ),
        _NumberedInstruction(
          number: 4,
          text: 'Wait for the image and its thumbnail to finish uploading.',
        ),
        _NumberedInstruction(
          number: 5,
          text: 'The new reference will appear in the selected category.',
        ),
        _HelpSectionTitle('Import an image from another app'),
        _NumberedInstruction(
          number: 1,
          text:
              'Open an image in your browser, photo application, or another '
              'supported app.',
        ),
        _NumberedInstruction(number: 2, text: 'Use the Share command.'),
        _NumberedInstruction(
          number: 3,
          text: 'Select Art Reference from the list of applications.',
        ),
        _NumberedInstruction(
          number: 4,
          text: 'Choose the category in which the reference should appear.',
        ),
        _NumberedInstruction(number: 5, text: 'Confirm the import.'),
        _HelpSectionTitle('Open a reference'),
        _HelpParagraph(
          'Tap any thumbnail to open the full reference and view its '
          'information.',
        ),
        _HelpSectionTitle('Use more than one category'),
        _HelpParagraph(
          'The same reference can appear in multiple categories. Art '
          'Reference keeps one original image and connects it to each chosen '
          'category.',
        ),
        _HelpSectionTitle('Add associated images'),
        _NumberedInstruction(number: 1, text: 'Open the original reference.'),
        _NumberedInstruction(
          number: 2,
          text: 'Open the associated-images section.',
        ),
        _NumberedInstruction(
          number: 3,
          text: 'Add a sketch, study, work in progress, or finished artwork.',
        ),
        _HelpParagraph(
          'Associated images remain connected to the original reference and '
          'do not appear as unrelated reference photographs.',
        ),
        _HelpSectionTitle('Use AI analysis'),
        _NumberedInstruction(number: 1, text: 'Open a reference image.'),
        _NumberedInstruction(
          number: 2,
          text: 'Select the AI analysis command.',
        ),
        _NumberedInstruction(
          number: 3,
          text: 'Wait while the image is analyzed.',
        ),
        _NumberedInstruction(
          number: 4,
          text:
              'Review the suggested description, categories, keywords, and '
              'artistic observations.',
        ),
        _HelpSectionTitle('Remove a reference from a category'),
        _HelpParagraph(
          'Use the remove command while viewing the reference. Removing an '
          'image from one category does not necessarily delete it from other '
          'categories.',
        ),
        _HelpSectionTitle('Sign out'),
        _HelpParagraph(
          'Open the account menu and select Sign Out. Your library remains '
          'connected to your account and will be available when you sign in '
          'again.',
        ),
      ],
    );
  }
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
          'Art Reference',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Version 1.0',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 28),
        const _HelpParagraph(
          'Art Reference is a personal image library created for artists who '
          'collect and use reference photographs in their creative work.',
        ),
        const _HelpParagraph(
          'It helps organize reference images, connect artwork with its '
          'original inspiration, and use artificial intelligence to describe '
          'and classify images.',
        ),
        const _HelpParagraph(
          'Art Reference was created to solve a practical problem: artists '
          'often collect thousands of useful images but have no convenient '
          'way to organize and retrieve them.',
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 20),
        Text(
          'Copyright © 2026 Boris Pitel',
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
          'Thank you for using Art Reference.\n\nHappy painting!',
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
