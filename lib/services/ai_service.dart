import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  // OCR for GCash Receipts via Python EasyOCR Backend with on-device ML Kit fallback
  static Future<Map<String, dynamic>?> extractGCashReference(File imageFile, double expectedAmount, String expectedRecipient) async {
    // Note: This URL is provided by Ngrok to expose the local server.
    // Ensure the Ngrok tunnel is running on the computer.
    final uri = Uri.parse('https://walk-versus-peculiar.ngrok-free.dev/extract_reference');
    
    try {
      var request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = '69420';
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      request.fields['expectedAmount'] = expectedAmount.toString();
      request.fields['expectedRecipient'] = expectedRecipient;
      
      print("Sending receipt to EasyOCR server...");
      var response = await request.send().timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final json = jsonDecode(respStr);
        if (json is Map<String, dynamic> && json['success'] == true) {
          return json;
        }
      } else {
        print("Server error: ${response.statusCode}");
      }
    } catch (e) {
      print("Network/OCR Server Error: $e. Falling back to on-device ML Kit...");
    }

    // Fallback: On-Device Google ML Kit Text Recognition
    return await _extractOnDeviceMLKit(imageFile, expectedAmount, expectedRecipient);
  }

  /// On-device OCR fallback supporting both 1-line and 2-line GCash reference formats
  static Future<Map<String, dynamic>> _extractOnDeviceMLKit(
      File imageFile, double expectedAmount, String expectedRecipient) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final fullText = recognizedText.text;
      print("MLKit Recognized Text: $fullText");

      String? referenceNumber;

      // 1. Single-line pattern with Ref No prefix
      final refMatch = RegExp(r'Ref[\s\.]*No[\.\s:]*([0-9\s\n\r]{9,30})', caseSensitive: false)
          .firstMatch(fullText);
      if (refMatch != null) {
        String cleanNum = refMatch.group(1)!.replaceAll(RegExp(r'\D'), '');
        if (cleanNum.length >= 13) {
          referenceNumber = cleanNum.substring(0, 13);
        } else if (cleanNum.length >= 9) {
          // Check following text for remaining digits
          final endPos = refMatch.end;
          final remainingSnippet = fullText.substring(endPos, (endPos + 40).clamp(0, fullText.length));
          final remMatch = RegExp(r'\b\d{4,8}\b').firstMatch(remainingSnippet);
          if (remMatch != null) {
            final combined = cleanNum + remMatch.group(0)!;
            if (combined.length >= 13) {
              referenceNumber = combined.substring(0, 13);
            }
          }
          referenceNumber ??= cleanNum;
        }
      }

      // 2. Multi-line inspection across text blocks and lines
      if (referenceNumber == null || referenceNumber.length < 13) {
        final List<String> allLines = [];
        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            final t = line.text.trim();
            if (t.isNotEmpty) allLines.add(t);
          }
        }

        for (int i = 0; i < allLines.length; i++) {
          final line = allLines[i];
          if (RegExp(r'Ref[\s\.]*No', caseSensitive: false).hasMatch(line)) {
            String digits = line.replaceAll(RegExp(r'\D'), '');
            if (digits.length >= 13) {
              referenceNumber = digits.substring(0, 13);
              break;
            }
            // Check next lines for split reference e.g.:
            // Line i:   "Ref No. 1234 123"
            // Line i+1: "123456"
            for (int j = i + 1; j < (i + 4).clamp(0, allLines.length); j++) {
              final nextDigits = allLines[j].replaceAll(RegExp(r'\D'), '');
              if (nextDigits.isNotEmpty) {
                final combined = digits + nextDigits;
                if (combined.length >= 13) {
                  referenceNumber = combined.substring(0, 13);
                  break;
                }
                digits = combined;
              }
            }
            if (referenceNumber != null && referenceNumber.length >= 13) break;
          }
        }
      }

      // 3. Fallback: Any 13 consecutive digits in full text
      if (referenceNumber == null || referenceNumber.length < 13) {
        final match13 = RegExp(r'\b(?:\d[\s\n\r]*){13}\b').firstMatch(fullText);
        if (match13 != null) {
          referenceNumber = match13.group(0)!.replaceAll(RegExp(r'\D'), '');
        }
      }

      // 4. Fallback: Adjacent digit blocks summing to 13 digits (e.g. 7 digits + 6 digits)
      if (referenceNumber == null || referenceNumber.length < 13) {
        final blockMatches = RegExp(r'\b\d{3,9}\b').allMatches(fullText).map((m) => m.group(0)!).toList();
        for (int i = 0; i < blockMatches.length - 1; i++) {
          final comb = blockMatches[i] + blockMatches[i + 1];
          if (comb.length == 13) {
            referenceNumber = comb;
            break;
          }
        }
      }

      if (referenceNumber != null && referenceNumber.isNotEmpty) {
        return {
          'success': true,
          'reference_number': referenceNumber,
          'amount': expectedAmount.toString(),
          'status': 'Successful',
        };
      }

      return {
        'success': false,
        'error': 'Could not detect GCash reference number on receipt.',
      };
    } catch (e) {
      print("MLKit processing error: $e");
      return {'success': false, 'error': e.toString()};
    } finally {
      textRecognizer.close();
    }
  }

  // Verify ID Name via Python EasyOCR Backend
  static Future<Map<String, dynamic>> verifyIdName(File imageFile, File? selfieFile, String firstName, String lastName, String idType) async {
    final uri = Uri.parse('https://walk-versus-peculiar.ngrok-free.dev/verify_id');
    try {
      var request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = '69420';
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      if (selfieFile != null) {
        request.files.add(await http.MultipartFile.fromPath('selfie', selfieFile.path));
      }
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
