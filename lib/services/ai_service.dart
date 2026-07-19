import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  // OCR for GCash Receipts via Python EasyOCR Backend
  static Future<Map<String, dynamic>?> extractGCashReference(File imageFile, double expectedAmount, String expectedRecipient) async {
    // Note: This URL is provided by Ngrok to expose the local server.
    // Ensure the Ngrok tunnel is running on the computer.
    final uri = Uri.parse('https://walk-versus-peculiar.ngrok-free.dev/extract_reference');
    
    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      request.fields['expectedAmount'] = expectedAmount.toString();
      request.fields['expectedRecipient'] = expectedRecipient;
      
      print("Sending receipt to EasyOCR server...");
      var response = await request.send();
      
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final json = jsonDecode(respStr);
        return json;
      } else {
        print("Server error: ${response.statusCode}");
        return {'success': false, 'error': 'Server Error: ${response.statusCode}'};
      }
    } catch (e) {
      print("Network/OCR Error: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  // Verify ID Name via Python EasyOCR Backend
  static Future<Map<String, dynamic>> verifyIdName(File imageFile, String firstName, String lastName, String idType) async {
    final uri = Uri.parse('https://walk-versus-peculiar.ngrok-free.dev/verify_id');
    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      request.fields['firstName'] = firstName;
      request.fields['lastName'] = lastName;
      request.fields['idType'] = idType;
      
      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final json = jsonDecode(respStr);
        return json;
      }
      return {'success': false, 'error': 'Server Error'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
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
