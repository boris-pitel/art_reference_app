import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/feedback_service.dart';
import '../widgets/home_button.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.currentScreen = 'collections'});
  final String currentScreen;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  late final FeedbackService _service;
  FeedbackType _type = FeedbackType.suggestion;
  XFile? _attachment;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _service = FeedbackService(Supabase.instance.client);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _chooseScreenshot() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    setState(() => _attachment = image);
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);
    try {
      await _service.submit(
        type: _type,
        comment: _commentController.text,
        currentScreen: widget.currentScreen,
        attachment: _attachment,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you. Your feedback was sent.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to send feedback: $error')),
      );
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Feedback'),
        actions: const [HomeButton()],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Help us improve Painter Reference',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account email, app version, platform, and current screen '
                'will be included so we can understand your feedback.',
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<FeedbackType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: 'Feedback type',
                  border: OutlineInputBorder(),
                ),
                items: FeedbackType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: _isSending
                    ? null
                    : (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _commentController,
                enabled: !_isSending,
                minLines: 6,
                maxLines: 12,
                maxLength: 5000,
                decoration: const InputDecoration(
                  labelText: 'Your comments',
                  hintText:
                      'Tell us what happened or what you would like to see.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your comments.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isSending ? null : _chooseScreenshot,
                icon: const Icon(Icons.attach_file),
                label: Text(
                  _attachment == null
                      ? 'Attach screenshot (optional)'
                      : _attachment!.name,
                ),
              ),
              if (_attachment != null)
                TextButton(
                  onPressed: _isSending
                      ? null
                      : () => setState(() => _attachment = null),
                  child: const Text('Remove attachment'),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isSending ? null : _send,
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_isSending ? 'Sending...' : 'Send Feedback'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
