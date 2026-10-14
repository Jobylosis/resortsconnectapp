import 'dart:io';
import 'dart:async';
import 'dart:math';
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
      minFaceSize: 0.1, // Accept face if at least ~10% of image height
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _isProcessingImage = false;
  bool _blinkReady = false;
  bool _hasDetectedFace = false;
  bool _isCapturing = false;
  bool _showManualButton = false;
  String _statusMessage = "Position your face in the circle";
  Color _statusColor = Colors.white;

  // Steady face detection tracking
  int _steadyFrames = 0;
  static const int _requiredSteadyFrames = 4; // ~1.0-1.2s at 3-4fps processing
  DateTime? _firstDetectedTime;
  Timer? _manualFallbackTimer;
  Timer? _overallTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startTimers();
  }

  void _startTimers() {
    // Show manual capture button after 8 seconds of no capture
    _manualFallbackTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_isCapturing) {
        setState(() {
          _showManualButton = true;
        });
      }
    });

    // Generous 20-second timeout to guide the user
    _overallTimeoutTimer = Timer(const Duration(seconds: 22), () {
      if (mounted && !_isCapturing) {
        setState(() {
          _showManualButton = true;
          _statusMessage = "Tap 'Take Photo' to continue.";
          _statusColor = Colors.amberAccent;
        });
      }
    });
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
    if (_isProcessingImage || _isCapturing || !mounted) return;
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
        final headRotY = face.headEulerAngleY ?? 0.0; // yaw
        final headRotZ = face.headEulerAngleZ ?? 0.0; // roll
        final headRotX = face.headEulerAngleX ?? 0.0; // pitch

        // Generous pose constraint (+/- 35 degrees)
        final isPoseAcceptable = headRotY.abs() <= 35 && headRotZ.abs() <= 35 && headRotX.abs() <= 35;
        
        final boundingBox = face.boundingBox;
        final faceHeightRatio = boundingBox.height / image.height;
        final isGoodSize = faceHeightRatio >= 0.15 && faceHeightRatio <= 0.85;

        // Position guidance hint
        String hint = "Hold still...";
        if (!isGoodSize) {
          hint = faceHeightRatio < 0.15 ? "Move closer" : "Move slightly back";
        } else if (!isPoseAcceptable) {
          hint = "Face the camera directly";
        }

        if (isPoseAcceptable && isGoodSize) {
          _steadyFrames++;
          _firstDetectedTime ??= DateTime.now();

          if (!_hasDetectedFace || _steadyFrames % 2 == 0) {
            setState(() {
              _hasDetectedFace = true;
              _statusMessage = _steadyFrames >= 2 ? "Hold still... Capturing" : "Face detected! Hold still";
              _statusColor = Colors.greenAccent;
            });
          }

          // Rule 1: Auto-capture once face is detected and held steady for ~1 second (4 steady frames)
          if (_steadyFrames >= _requiredSteadyFrames && !_isCapturing) {
            _captureAndReturn();
            return;
          }
        } else {
          // If pose is skewed, gently reset steady counter
          _steadyFrames = max(0, _steadyFrames - 1);
          setState(() {
            _hasDetectedFace = true;
            _statusMessage = hint;
            _statusColor = Colors.amberAccent;
          });
        }

        // Liveness blink support (optional instant capture if blink occurs)
        if (leftEyeOpen != null && rightEyeOpen != null && !_isCapturing) {
          final avgOpen = (leftEyeOpen + rightEyeOpen) / 2.0;
          if (avgOpen < 0.35) {
            _blinkReady = true;
          } else if (avgOpen > 0.55 && _blinkReady) {
            _blinkReady = false;
            _captureAndReturn();
            return;
          }
        }
      } else {
        _steadyFrames = 0;
        _firstDetectedTime = null;
        if (_hasDetectedFace) {
          setState(() {
            _hasDetectedFace = false;
            _statusMessage = "Position your face in the circle";
            _statusColor = Colors.white;
          });
        }
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
    if (_isCapturing) return;
    _isCapturing = true;

    setState(() {
      _statusMessage = "Capturing selfie...";
      _statusColor = Colors.yellowAccent;
    });

    try {
      await _cameraController?.stopImageStream();
      await Future.delayed(const Duration(milliseconds: 150)); 
      
      final XFile? file = await _cameraController?.takePicture();
      if (file != null && mounted) {
        Navigator.pop(context, file);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _statusMessage = "Failed to capture photo. Tap button below.";
          _statusColor = Colors.red;
          _showManualButton = true;
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
    _manualFallbackTimer?.cancel();
    _overallTimeoutTimer?.cancel();
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
                  "Face Verification",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _hasDetectedFace ? Colors.greenAccent.withOpacity(0.5) : Colors.white24,
                    ),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Primary action: Take Photo (manual fallback)
                if (_showManualButton || _hasDetectedFace)
                  ElevatedButton.icon(
                    onPressed: _isCapturing ? null : _captureAndReturn,
                    icon: const Icon(Icons.camera_alt, color: Colors.black),
                    label: Text(
                      _showManualButton ? "Take Photo" : "Capture Photo",
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white70),
                  label: const Text("Cancel", style: TextStyle(color: Colors.white70, fontSize: 15)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
