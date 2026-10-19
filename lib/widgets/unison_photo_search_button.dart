import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class UnisonPhotoSearchButton extends StatefulWidget {
  const UnisonPhotoSearchButton({
    super.key,
    required this.capture,
    required this.openMatches,
    this.enabled = true,
    this.usesCamera = true,
  });
  final Future<Uint8List?> Function() capture;
  final Future<void> Function(Uint8List) openMatches;
  final bool enabled, usesCamera;
  @override
  State<UnisonPhotoSearchButton> createState() =>
      _UnisonPhotoSearchButtonState();
}

class _UnisonPhotoSearchButtonState extends State<UnisonPhotoSearchButton> {
  bool _busy = false;
  Future<void> _open() async {
    if (_busy || !widget.enabled) return;
    setState(() => _busy = true);
    try {
      final bytes = await widget.capture();
      if (!mounted || !widget.enabled || bytes == null) return;
      await widget.openMatches(bytes);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open photo search: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: widget.enabled && !_busy ? _open : null,
    icon: Icon(
      widget.usesCamera
          ? Icons.photo_camera_outlined
          : Icons.add_photo_alternate_outlined,
    ),
    label: Text(
      _busy
          ? 'Opening photo…'
          : widget.usesCamera
          ? 'Search by camera'
          : 'Search by photo',
    ),
  );
}
