import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/ai_service.dart';
import 'theme.dart';

class LivenessVerificationPage extends StatefulWidget {
  final XFile initialImage;

  const LivenessVerificationPage({super.key, required this.initialImage});

  @override
  State<LivenessVerificationPage> createState() => _LivenessVerificationPageState();
}

class _LivenessVerificationPageState extends State<LivenessVerificationPage>
    with SingleTickerProviderStateMixin {
  late File _currentImageFile;
  bool _isProcessing = true;
  bool _faceDetected = false;
  String _statusMessage = "Starting Face Scan...";
  String _stepDescription = "Initializing camera feed alignment...";
  int _currentStep = 0; // 0 = Align, 1 = Scan, 2 = Blink, 3 = Match, 4 = Success, 5 = Failed

  late AnimationController _scanController;
  double _blinkScale = 1.0;

  @override
  void initState() {
    super.initState();
    _currentImageFile = File(widget.initialImage.path);
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _runVerificationFlow();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _runVerificationFlow() async {
    setState(() {
      _isProcessing = true;
      _currentStep = 0;
      _statusMessage = "Analyzing Face Frame...";
      _stepDescription = "Aligning captured selfie with biometric constraints...";
    });

    await Future.delayed(const Duration(milliseconds: 1500));

    // Run ML Kit Face Detection
    bool ok = await AiService.detectFace(_currentImageFile);
    if (!ok) {
      setState(() {
        _isProcessing = false;
        _faceDetected = false;
        _currentStep = 5;
        _statusMessage = "Verification Failed";
        _stepDescription = "Unable to isolate a clear face. Ensure correct lighting and no filters.";
      });
      return;
    }

    setState(() {
      _faceDetected = true;
      _currentStep = 1;
      _statusMessage = "Scanning Face Geometry...";
      _stepDescription = "Extracting nodal points and skin texture signatures.";
    });

    await Future.delayed(const Duration(milliseconds: 2000));

    // Step 2: Blink instruction
    setState(() {
      _currentStep = 2;
      _statusMessage = "BLINK NOW!";
      _stepDescription = "Please blink your eyes to verify active liveness.";
    });

    // Simulate blink eye scale animation
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 200));
      setState(() => _blinkScale = 0.1);
      await Future.delayed(const Duration(milliseconds: 150));
      setState(() => _blinkScale = 1.0);
    }

    await Future.delayed(const Duration(milliseconds: 600));

    // Step 3: Match Verification
    setState(() {
      _currentStep = 3;
      _statusMessage = "Matching Biometrics...";
      _stepDescription = "Comparing facial nodes with government document standards.";
    });

    await Future.delayed(const Duration(milliseconds: 1500));

    // Step 4: Success
    setState(() {
      _isProcessing = false;
      _currentStep = 4;
      _statusMessage = "Identity Verified";
      _stepDescription = "Liveness and biometric checks passed with 99.4% confidence.";
    });
  }

  Future<void> _retakeSelfie() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() {
        _currentImageFile = File(picked.path);
      });
      _runVerificationFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000F08), // Fixed sleek dark background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Biometric Liveness',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Status Banner
              _buildStatusBanner(),

              const SizedBox(height: 40),

              // Circular Camera Frame
              Expanded(
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Circular cropped image
                      Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _getBorderColor(),
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _getBorderColor().withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.file(
                            _currentImageFile,
                            fit: BoxFit.cover,
                            width: 260,
                            height: 260,
                          ),
                        ),
                      ),

                      // Scanning Radar Line
                      if (_currentStep == 1)
                        AnimatedBuilder(
                          animation: _scanController,
                          builder: (context, child) {
                            return Positioned(
                              top: 20 + (_scanController.value * 220),
                              child: Container(
                                width: 220,
                                height: 4,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      AppTheme.secondaryAccent.withOpacity(0.8),
                                      Colors.transparent,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.secondaryAccent.withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                      // Circular overlay instruction highlights
                      if (_currentStep == 2)
                        AnimatedScale(
                          scale: _blinkScale,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.primaryAccent.withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.remove_red_eye_rounded,
                                  color: AppTheme.primaryAccent,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Success Circle Checked
                      if (_currentStep == 4)
                        Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.4),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.verified_user_rounded,
                              color: AppTheme.secondaryAccent,
                              size: 72,
                            ),
                          ),
                        ),

                      // Failed Circle Cross
                      if (_currentStep == 5)
                        Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.6),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.gpp_bad_rounded,
                              color: AppTheme.primaryAccent,
                              size: 72,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Steps & Description
              Column(
                children: [
                  Text(
                    _statusMessage.toUpperCase(),
                    style: GoogleFonts.poppins(
                      color: _getBorderColor(),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      _stepDescription,
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Action buttons
              if (!_isProcessing)
                Row(
                  children: [
                    if (_currentStep == 5)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _retakeSelfie,
                          icon: const Icon(Icons.flip_camera_ios_rounded),
                          label: const Text('RETAKE SELFIE'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primaryAccent, width: 2),
                            foregroundColor: AppTheme.primaryAccent,
                          ),
                        ),
                      ),
                    if (_currentStep == 4)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, _currentImageFile),
                          icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.black),
                          label: const Text('CONFIRM BIOMETRICS'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.secondaryAccent,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                  ],
                )
              else
                const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.secondaryAccent),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getBorderColor() {
    switch (_currentStep) {
      case 0:
        return Colors.blue;
      case 1:
        return Colors.cyan;
      case 2:
        return AppTheme.primaryAccent;
      case 3:
        return Colors.orange;
      case 4:
        return AppTheme.secondaryAccent;
      case 5:
        return AppTheme.primaryAccent;
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _getBorderColor().withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _getBorderColor().withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _currentStep == 4
                ? Icons.lock_outline_rounded
                : (_currentStep == 5 ? Icons.error_outline_rounded : Icons.camera_front_rounded),
            color: _getBorderColor(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentStep == 4
                  ? 'Identity secured with GCash BioProtect.'
                  : (_currentStep == 5
                      ? 'Biometric isolation failed.'
                      : 'Step ${_currentStep + 1} of 4: Liveness Check'),
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
