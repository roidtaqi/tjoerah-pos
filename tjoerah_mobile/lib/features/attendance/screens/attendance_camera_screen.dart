import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class AttendanceCameraScreen extends StatefulWidget {
  const AttendanceCameraScreen({super.key, required this.actionLabel});

  final String actionLabel;

  @override
  State<AttendanceCameraScreen> createState() => _AttendanceCameraScreenState();
}

class _AttendanceCameraScreenState extends State<AttendanceCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  Object? _error;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initialize();
    }
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('Kamera tidak tersedia.');
      _camera = cameras.cast<CameraDescription?>().firstWhere(
        (camera) => camera?.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.pop(context, photo.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            _CameraFillPreview(controller: controller)
          else
            Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.no_photography_outlined,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Kamera belum dapat digunakan',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _initialize,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
            ),
          Positioned(
            left: 8,
            right: 8,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Batal',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.actionLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 52),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + 28,
            child: Center(
              child: SizedBox.square(
                dimension: 76,
                child: IconButton.filled(
                  tooltip: 'Ambil foto',
                  onPressed: controller == null || _isCapturing
                      ? null
                      : _capture,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white54,
                  ),
                  icon: _isCapturing
                      ? const SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.camera_alt_rounded, size: 32),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraFillPreview extends StatelessWidget {
  const _CameraFillPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    var scale = screenSize.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(controller)),
    );
  }
}
