import 'package:flutter/material.dart';

void goToCategoriesHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class HomeButton extends StatelessWidget {
  const HomeButton({super.key, this.onPressed, this.enabled = true});

  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled
          ? onPressed ?? () => goToCategoriesHome(context)
          : null,
      icon: const Icon(Icons.home_outlined),
      tooltip: 'Home — Categories',
    );
  }
}
