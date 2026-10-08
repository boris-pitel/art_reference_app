import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/reference_document.dart';
import '../services/document_service.dart';
import '../services/document_delivery.dart';
import '../services/rtf_text.dart';
import '../services/document_text.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({
    super.key,
    required this.document,
    required this.service,
  });
  final ReferenceDocument document;
  final DocumentService service;
  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late Future<Uint8List> _bytes;
  Uint8List? _loaded;
  bool _working = false;
  @override
  void initState() {
    super.initState();
    _bytes = widget.service.bytes(widget.document);
  }

  Future<void> _deliver(bool open) async {
    final bytes = _loaded;
    if (bytes == null || _working) return;
    setState(() => _working = true);
    try {
      if (open) {
        await DocumentDelivery.open(widget.document, bytes);
      } else {
        await DocumentDelivery.save(widget.document, bytes);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editDetails() async {
    final doc = widget.document;
    final title = TextEditingController(text: doc.title),
        notes = TextEditingController(text: doc.notes),
        keywords = TextEditingController(text: doc.keywords.join(', '));
    var favorite = doc.isFavorite;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Document details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                TextField(
                  controller: keywords,
                  decoration: const InputDecoration(
                    labelText: 'Keywords, separated by commas',
                  ),
                ),
                CheckboxListTile(
                  value: favorite,
                  onChanged: (v) => setDialogState(() => favorite = v ?? false),
                  title: const Text('Favorite'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await widget.service.update(
          doc,
          title: title.text.trim().isEmpty ? doc.filename : title.text.trim(),
          notes: notes.text,
          keywords: keywords.text
              .split(',')
              .map((k) => k.trim())
              .where((k) => k.isNotEmpty)
              .toSet()
              .toList(),
          favorite: favorite,
        );
        if (mounted) Navigator.pop(context);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }
    title.dispose();
    notes.dispose();
    keywords.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.document.title),
      actions: [
        IconButton(
          tooltip: 'Document details',
          onPressed: widget.service.offline ? null : _editDetails,
          icon: const Icon(Icons.info_outline),
        ),
        IconButton(
          tooltip: 'Save document',
          onPressed: _loaded == null || _working ? null : () => _deliver(false),
          icon: const Icon(Icons.download),
        ),
      ],
    ),
    body: FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(snapshot.error.toString()),
                TextButton(
                  onPressed: () => setState(
                    () => _bytes = widget.service.bytes(widget.document),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_loaded == null) {
          _loaded = bytes;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        final type = widget.document.fileType;
        if (type == 'pdf') {
          return PdfPreview(
            build: (_) => bytes,
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: false,
            allowSharing: false,
            canDebug: false,
            onError: (context, error) => const Center(
              child: Text(
                'Unable to preview this PDF. Use Save document to open the original file.',
              ),
            ),
          );
        }
        if (type == 'txt' || type == 'rtf') {
          try {
            final spans = type == 'rtf'
                ? rtfText(bytes)
                : [TextSpan(text: documentText(bytes))];
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SelectableText.rich(
                TextSpan(
                  style: Theme.of(context).textTheme.bodyLarge,
                  children: spans,
                ),
              ),
            );
          } catch (error) {
            return Center(
              child: Text('Unable to display this document: $error'),
            );
          }
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 72),
              const SizedBox(height: 16),
              Text(widget.document.filename),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _working ? null : () => _deliver(true),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  kIsWeb ? 'Download Word document' : 'Open in default app',
                ),
              ),
              const SizedBox(height: 12),
              const Text('The original Word document is preserved.'),
            ],
          ),
        );
      },
    ),
  );
}
