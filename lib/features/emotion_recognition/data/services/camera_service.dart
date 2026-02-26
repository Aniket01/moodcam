import 'package:camera/camera.dart';

class CameraService {
  CameraController? _controller;
  CameraController? get controller => _controller;

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
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Android standard
    );

    await _controller!.initialize();
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}
