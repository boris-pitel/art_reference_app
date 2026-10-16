import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnisonSwatch extends StatefulWidget {
  const UnisonSwatch({super.key, required this.path});
  final String? path;
  @override
  State<UnisonSwatch> createState() => _UnisonSwatchState();
}

class _UnisonSwatchState extends State<UnisonSwatch> {
  Future<String>? _url;
  void _load() {
    _url = widget.path == null
        ? null
        : Supabase.instance.client.storage
              .from('pastel-catalogue')
              .createSignedUrl(widget.path!, 3600);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UnisonSwatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 64,
    child: FutureBuilder<String>(
      future: _url,
      builder: (context, snapshot) => snapshot.hasData
          ? Image.network(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            )
          : Icon(
              snapshot.hasError
                  ? Icons.broken_image_outlined
                  : Icons.palette_outlined,
            ),
    ),
  );
}
