import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  CameraController? get controller => _controller;
  CameraDescription? get cameraDescription => _controller?.description;
  bool _isStreaming = false;

  Future<void> initialize() async {
    if (_controller != null) return;

    //  Fetch all available cameras on the device
    final cameras = await availableCameras();

    //  Find the front-facing camera
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    //  Initialize the controller with high resolution and no audio
    _controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();
  }

  void startStream(Function(CameraImage) onImage) {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isStreaming) {
      return;
    }
    _isStreaming = true;
    _controller!.startImageStream(onImage);
  }

  Future<void> stopStream() async {
    if (_controller == null || !_isStreaming) return;
    _isStreaming = false;
    await _controller!.stopImageStream();
  }

  void dispose() async {
    await stopStream();
    _controller?.dispose();
    _controller = null;
  }
}
