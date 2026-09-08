import 'package:flutter/material.dart';

import '../services/local_user_session.dart';
import '../services/network_availability.dart';

/// Shares connectivity with open editors without replacing their draft state.
mixin OfflineEditorState<T extends StatefulWidget> on State<T> {
  bool get editorOffline =>
      ConnectivityMonitor.instance.isOffline ||
      LocalUserSession.isOfflineActive;

  @override
  void initState() {
    super.initState();
    ConnectivityMonitor.instance.addListener(_editorConnectivityChanged);
    LocalUserSession.changes.addListener(_editorConnectivityChanged);
  }

  void _editorConnectivityChanged() {
    if (!mounted) return;
    if (editorOffline) FocusScope.of(context).unfocus();
    setState(() {});
  }

  void reportEditorFailure(Object error) {
    if (NetworkAvailability.isNetworkFailure(error)) {
      ConnectivityMonitor.instance.reportBackendFailure(error);
    }
  }

  Widget offlineEditorBody(Widget child) => OfflineEditingBody(child: child);

  @override
  void dispose() {
    ConnectivityMonitor.instance.removeListener(_editorConnectivityChanged);
    LocalUserSession.changes.removeListener(_editorConnectivityChanged);
    super.dispose();
  }
}

class OfflineEditingBody extends StatelessWidget {
  const OfflineEditingBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ConnectivityMonitor.instance,
        LocalUserSession.changes,
      ]),
      builder: (context, _) {
        final offline =
            ConnectivityMonitor.instance.isOffline ||
            LocalUserSession.isOfflineActive;
        return Column(
          children: [
            if (offline)
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_off),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Offline — editing, saving and AI are paused. '
                          'Your unsaved work stays on this screen. Reconnect before saving.',
                        ),
                      ),
                      if (!LocalUserSession.isOfflineActive &&
                          ConnectivityMonitor.instance.state ==
                              BackendConnectivityState.backendUnavailable)
                        TextButton(
                          onPressed:
                              ConnectivityMonitor.instance.prepareBackendRetry,
                          child: const Text('Try again'),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: offline,
                child: ExcludeFocus(excluding: offline, child: child),
              ),
            ),
          ],
        );
      },
    );
  }
}
