import '../services/pending_original_store.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/reference_category.dart';
import '../services/local_user_session.dart';
import '../services/offline_upload_queue.dart';

/// Capture is acknowledged only after the original and queue record are durable.
/// Uploads resume after leaving the camera; they never gate the shutter.
class ContinuousCameraScreen extends StatefulWidget {
  const ContinuousCameraScreen({
    super.key,
    required this.category,
    this.parentImageId,
  });
  final ReferenceCategory category;
  final String? parentImageId;
  @override
  State<ContinuousCameraScreen> createState() => _ContinuousCameraScreenState();
}

class _ContinuousCameraScreenState extends State<ContinuousCameraScreen>
    with WidgetsBindingObserver {
  static const double _zoomLimit = 20;
  static const double _pinchSensitivity = 0.45;
  CameraController? _camera;
  bool _busy = false;
  bool _initializing = false;
  bool _active = true;
  int _saved = 0;
  double _minZoom = 1, _maxZoom = 1, _zoom = 1, _pinchStart = 1;
  CameraController? _zoomWriter;

  double get _zoomSliderValue {
    if (_maxZoom <= _minZoom) return 0;
    return math.log(_zoom / _minZoom) / math.log(_maxZoom / _minZoom);
  }

  double _zoomFromSlider(double value) {
    return _minZoom * math.pow(_maxZoom / _minZoom, value).toDouble();
  }

  void _setZoom(double value) {
    final camera = _camera;
    if (camera == null) return;
    setState(() => _zoom = value.clamp(_minZoom, _maxZoom).toDouble());
    if (identical(_zoomWriter, camera)) return;
    _zoomWriter = camera;
    unawaited(_applyZoom(camera));
  }

  Future<void> _applyZoom(CameraController camera) async {
    try {
      while (mounted && identical(_camera, camera)) {
        final requested = _zoom;
        await camera.setZoomLevel(requested);
        if (_zoom == requested) break;
      }
    } catch (error) {
      if (mounted && identical(_camera, camera)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to change camera zoom.')),
        );
      }
    } finally {
      if (identical(_zoomWriter, camera)) _zoomWriter = null;
    }
  }

  String? _error;
  XFile? _unsaved;
  late final String? _userId = LocalUserSession.effectiveUserId;
  late final String? _email = LocalUserSession.effectiveEmail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineUploadQueue.instance.pauseForCapture();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_initializing || !mounted || !_active) return;
    _initializing = true;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera is available.');
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        description,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await controller.initialize();
      var minZoom = 1.0;
      var maxZoom = 1.0;
      try {
        minZoom = await controller.getMinZoomLevel();
        maxZoom = math.min(await controller.getMaxZoomLevel(), _zoomLimit);
      } catch (_) {
        // A camera without zoom support can still take photos.
      }
      if (!mounted || !_active) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoom = 1.0.clamp(minZoom, maxZoom).toDouble();
        _error = null;
      });
    } catch (error) {
      await controller?.dispose();
      if (mounted) setState(() => _error = 'Unable to open camera: $error');
    } finally {
      _initializing = false;
      if (mounted && _active && _camera == null && _error == null) {
        unawaited(_initialize());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      final camera = _camera;
      _camera = null;
      if (camera != null) unawaited(camera.dispose());
    } else {
      unawaited(_initialize());
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_userId == null ||
          _email == null ||
          LocalUserSession.effectiveUserId != _userId) {
        throw StateError('Sign in before taking photos.');
      }
      _unsaved ??= await _camera!.takePicture();
      final shot = _unsaved!;
      await OfflineUploadQueue.instance.enqueue(
        userId: _userId,
        userEmail: _email,
        category: widget.category,
        imageBytes: await shot.readAsBytes(),
        originalFilename: shot.name,
        parentImageId: widget.parentImageId,
        deferPreview: true,
      );
      _unsaved = null;
      unawaited(releaseCapturedTemporaryFile(shot.path));
      if (mounted) setState(() => _saved++);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'Photo could not be saved: $error. Free some storage and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active = false;
    unawaited(_camera?.dispose());
    OfflineUploadQueue.instance.resumeAfterCapture();
    unawaited(
      OfflineUploadQueue.instance
          .syncAfterCapture(Supabase.instance.client)
          .catchError((Object error) {
            debugPrint('Camera upload queue retained for retry: $error');
            return const OfflineUploadSyncResult(
              uploaded: 0,
              failed: 0,
              remaining: 0,
            );
          }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _unsaved == null,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || _busy || _unsaved == null) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Photo has not been saved'),
          content: const Text(
            'Stay here to retry saving, or discard this unsaved shot. Previously saved photos will stay in the queue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep photo'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard shot'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) {
        setState(() {
          _unsaved = null;
          _error = null;
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text('Camera · $_saved saved'),
        actions: [
          TextButton(
            onPressed: _busy || _unsaved != null
                ? null
                : () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _camera?.value.isInitialized == true
                  ? GestureDetector(
                      onScaleStart: (_) => _pinchStart = _zoom,
                      onScaleUpdate: (details) {
                        if (details.pointerCount >= 2) {
                          // Camera zoom ranges can be very wide. Damp the raw
                          // gesture so a small pinch makes a precise change.
                          _setZoom(
                            (_pinchStart *
                                    math.pow(details.scale, _pinchSensitivity))
                                .toDouble(),
                          );
                        }
                      },
                      child: CameraPreview(_camera!),
                    )
                  : _error == null
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.no_photography),
            ),
          ),
          if (_camera != null && _maxZoom > _minZoom)
            Row(
              children: [
                const SizedBox(width: 16),
                Text('${_zoom.toStringAsFixed(1)}×'),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 1,
                    divisions: 100,
                    value: _zoomSliderValue.clamp(0, 1),
                    label: '${_zoom.toStringAsFixed(1)}×',
                    onChanged: (value) => _setZoom(_zoomFromSlider(value)),
                  ),
                ),
              ],
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Photos are saved on this device. Uploads resume when you finish.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy || (_camera == null && _unsaved == null)
                        ? null
                        : _capture,
                    icon: Icon(
                      _unsaved == null ? Icons.camera_alt : Icons.refresh,
                    ),
                    label: Text(
                      _busy
                          ? 'Saving…'
                          : _unsaved == null
                          ? 'Take photo'
                          : 'Retry saving',
                    ),
                  ),
                  if (_camera == null && !_initializing)
                    TextButton(
                      onPressed: _initialize,
                      child: const Text('Retry camera'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
