import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class AiService {
  // OCR for GCash Receipts
  static Future<String?> extractGCashReference(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    
    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      String fullText = recognizedText.text;
      
      // GCash reference numbers are typically 13 digits (e.g., 1000 000 000 000 without spaces, or 9+ digits)
      // Some receipts show "Ref. No. 1234567890123"
      final RegExp refNoRegex = RegExp(r'\b\d{9,13}\b');
      final match = refNoRegex.firstMatch(fullText);
      
      if (match != null) {
        return match.group(0); // The extracted reference number
      }
      return null;
    } catch (e) {
      print("OCR Error: $e");
      return null;
    } finally {
      textRecognizer.close();
    }
  }

  // Face Detection for Identity Verification
  static Future<bool> detectFace(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final options = FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      performanceMode: FaceDetectorMode.fast,
    );
    final faceDetector = FaceDetector(options: options);
    
    try {
      final List<Face> faces = await faceDetector.processImage(inputImage);
      // We want to ensure there is exactly one face detected.
      return faces.length == 1;
    } catch (e) {
      print("Face Detection Error: $e");
      return false;
    } finally {
      faceDetector.close();
    }
  }
}
