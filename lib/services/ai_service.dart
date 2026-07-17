import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  // OCR for GCash Receipts via Python EasyOCR Backend
  static Future<String?> extractGCashReference(File imageFile) async {
    // Note: 192.168.1.12 is your computer's local IP on the Wi-Fi network.
    // Ensure both the phone and computer are on the same Wi-Fi.
    final uri = Uri.parse('http://192.168.1.12:8000/extract_reference');
    
    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      
      print("Sending receipt to EasyOCR server...");
      var response = await request.send();
      
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final json = jsonDecode(respStr);
        
        if (json['success'] == true) {
          return json['reference_number'].toString();
        } else {
          print("OCR Server returned error: ${json['error']}");
          return null;
        }
      } else {
        print("Server error: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Network/OCR Error: $e");
      return null;
    }
  }

  // Verify ID Name via Python EasyOCR Backend
  static Future<Map<String, dynamic>> verifyIdName(File imageFile, String firstName, String lastName) async {
    final uri = Uri.parse('http://192.168.1.12:8000/verify_id');
    try {
      var request = http.MultipartRequest('POST', uri);
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      request.fields['firstName'] = firstName;
      request.fields['lastName'] = lastName;
      
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
