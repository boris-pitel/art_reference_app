import 'package:flutter/material.dart';

/// Shared viewing controls for cached references and locally queued photos.
class ReferenceViewerScreen extends StatefulWidget {
  const ReferenceViewerScreen({
    super.key,
    required this.count,
    required this.imageBuilder,
    this.initialIndex = 0,
  });
  final int count;
  final int initialIndex;
  final Widget Function(BuildContext, int) imageBuilder;
  @override
  State<ReferenceViewerScreen> createState() => _ReferenceViewerScreenState();
}

class _ReferenceViewerScreenState extends State<ReferenceViewerScreen> {
  late int _index = widget.initialIndex;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('View image')),
    body: ColoredBox(
      color: Colors.black,
      child: Center(
        child: InteractiveViewer(
          key: ValueKey(_index),
          minScale: 0.5,
          maxScale: 8,
          child: widget.imageBuilder(context, _index),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Previous image',
            onPressed: _index > 0 ? () => setState(() => _index--) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${_index + 1} of ${widget.count}'),
          IconButton(
            tooltip: 'Next image',
            onPressed: _index + 1 < widget.count
                ? () => setState(() => _index++)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ),
  );
}
