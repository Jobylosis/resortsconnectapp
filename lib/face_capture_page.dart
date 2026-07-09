import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceCapturePage extends StatefulWidget {
  const FaceCapturePage({super.key});

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage> {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
    ),
  );

  bool _isProcessingImage = false;
  bool _blinkReady = false;
  String _statusMessage = "Position your face in the circle";
  Color _statusColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {});
        _cameraController!.startImageStream(_processCameraImage);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Could not initialize camera.";
          _statusColor = Colors.red;
        });
      }
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessingImage || !mounted) return;
    _isProcessingImage = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isProcessingImage = false;
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        final leftEyeOpen = face.leftEyeOpenProbability;
        final rightEyeOpen = face.rightEyeOpenProbability;

        if (leftEyeOpen != null && rightEyeOpen != null) {
          final avgOpen = (leftEyeOpen + rightEyeOpen) / 2.0;

          if (avgOpen < 0.25) {
            if (!_blinkReady) {
              _blinkReady = true;
            }
          } else if (avgOpen > 0.7) {
            if (_blinkReady) {
              _blinkReady = false;
              _captureAndReturn();
            } else {
              setState(() {
                _statusMessage = "Blink slowly to capture";
                _statusColor = Colors.greenAccent;
              });
            }
          }
        }
      } else {
        setState(() {
          _statusMessage = "Face not detected. Center your face.";
          _statusColor = Colors.white;
        });
        _blinkReady = false;
      }
    } catch (e) {
      // Ignored processing errors
    } finally {
      if (mounted) {
        _isProcessingImage = false;
      }
    }
  }

  void _captureAndReturn() async {
    setState(() {
      _statusMessage = "Blink detected! Capturing...";
      _statusColor = Colors.yellowAccent;
    });

    try {
      await _cameraController?.stopImageStream();
      // Small delay so eyes appear open in the photo
      await Future.delayed(const Duration(milliseconds: 200)); 
      
      final XFile? file = await _cameraController?.takePicture();
      if (file != null && mounted) {
        Navigator.pop(context, file);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Failed to capture photo.";
          _statusColor = Colors.red;
        });
        _cameraController?.startImageStream(_processCameraImage);
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraController!.description;
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null; // Format not supported
    }

    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Circular mask over the camera
          Center(
            child: ClipOval(
              child: SizedBox(
                width: 300,
                height: 300,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          ),

          // Overlay Guide overlay
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const Text(
                  "Liveness Check",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                label: const Text("Cancel", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          )
        ],
      ),
    );
  }
}
