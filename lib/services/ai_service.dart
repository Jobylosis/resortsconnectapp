import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AiService {
  // OCR for GCash Receipts via Python EasyOCR Backend with on-device ML Kit fallback
  static Future<Map<String, dynamic>?> extractGCashReference(
    File imageFile,
    double expectedAmount,
    String expectedRecipient, {
    String expectedPhone = "",
  }) async {
    // Note: This URL is provided by Ngrok to expose the local server.
    // Ensure the Ngrok tunnel is running on the computer.
    final uri = Uri.parse('https://walk-versus-peculiar.ngrok-free.dev/extract_reference');
    
    try {
      var request = http.MultipartRequest('POST', uri);
      request.headers['ngrok-skip-browser-warning'] = '69420';
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      request.fields['expectedAmount'] = expectedAmount.toStringAsFixed(2);
      request.fields['expectedRecipient'] = expectedRecipient;
      if (expectedPhone.trim().isNotEmpty) {
        request.fields['expectedPhone'] = expectedPhone.trim();
      }
      
      print("Sending receipt to EasyOCR server...");
      var response = await request.send().timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final json = jsonDecode(respStr);
        if (json is Map<String, dynamic>) {
          return json;
        }
      } else {
        print("Server error: ${response.statusCode}");
      }
    } catch (e) {
      print("Network/OCR Server Error: $e. Falling back to on-device ML Kit...");
    }

    // Fallback: On-Device Google ML Kit Text Recognition
    return await _extractOnDeviceMLKit(imageFile, expectedAmount, expectedRecipient, expectedPhone: expectedPhone);
  }

  /// Strict GCash Receipt Validator enforcing 4 rules:
  /// 1. Recipient Name: Masked matching allowed, identical word count & character length per word, visible chars must match.
  /// 2. Amount: Exact money format ₱... or digits with 2 decimals, numeric value equals expectedAmount.
  /// 3. Date and Time: Chronological format 'Mon DD, YYYY hh:mm AM/PM', valid calendar date and time.
  /// 4. Reference Number: Exactly 13 digits grouped as '0000 000 000000'.
  static Map<String, dynamic> validateGCashReceipt({
    required Map<String, dynamic>? ocrData,
    required double expectedAmount,
    required String expectedRecipient,
  }) {
    List<String> errors = [];

    if (ocrData == null) {
      return {
        'isValid': false,
        'errors': ['Receipt could not be processed by OCR scanner.'],
      };
    }

    final rawReference = ocrData['raw_reference']?.toString() ?? ocrData['reference_number']?.toString() ?? '';
    final rawAmount = ocrData['raw_amount']?.toString() ?? ocrData['amount']?.toString() ?? '';
    final rawDate = ocrData['raw_date']?.toString() ?? ocrData['date']?.toString() ?? '';
    final rawText = ocrData['extracted_text']?.toString() ?? '';

    // ==========================================
    // RULE 1: RECIPIENT NAME (Masked names allowed)
    // ==========================================
    final expNameClean = expectedRecipient.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (expNameClean.isNotEmpty) {
      final expWords = expNameClean.split(' ').where((w) => w.isNotEmpty).toList();
      final numWords = expWords.length;

      // Extract raw recipient candidates from raw lines or full text
      final lines = (ocrData['raw_lines'] is List)
          ? (ocrData['raw_lines'] as List).map((e) => e.toString()).toList()
          : rawText.split('\n');

      final List<String> candidatePhrases = [];
      for (final line in lines) {
        final trimmed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (trimmed.isNotEmpty) {
          candidatePhrases.add(trimmed);
        }
      }

      // Also generate n-gram windows of words matching numWords from full text
      final allTokens = rawText.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      for (int i = 0; i <= allTokens.length - numWords; i++) {
        final phrase = allTokens.sublist(i, i + numWords).join(' ');
        if (!candidatePhrases.contains(phrase)) {
          candidatePhrases.add(phrase);
        }
      }

      bool namePassed = false;
      String? bestMismatchReason;

      for (final candidate in candidatePhrases) {
        final candWords = candidate.split(' ').where((w) => w.isNotEmpty).toList();
        if (candWords.length != numWords) {
          continue; // Word count must match
        }

        bool candidateMatches = true;
        String? wordFailureMsg;

        for (int wIdx = 0; wIdx < numWords; wIdx++) {
          final expW = expWords[wIdx];
          final candW = candWords[wIdx];

          // Length check
          if (candW.length != expW.length) {
            candidateMatches = false;
            wordFailureMsg = "expected ${expW.length} characters in '$expW', found ${candW.length} in '$candW'.";
            break;
          }

          // Character-by-character check (asterisk matches any character)
          for (int cIdx = 0; cIdx < expW.length; cIdx++) {
            final cCand = candW[cIdx];
            final cExp = expW[cIdx];

            if (cCand == '*' || cCand == '•' || cCand == '●' || cCand == '○' || cCand == '⦿') {
              continue; // Masked character matches
            }

            if (cCand.toLowerCase() != cExp.toLowerCase()) {
              candidateMatches = false;
              wordFailureMsg = "character mismatch in '$candW' for expected '$expW'.";
              break;
            }
          }

          if (!candidateMatches) break;
        }

        if (candidateMatches) {
          namePassed = true;
          break;
        } else if (wordFailureMsg != null && bestMismatchReason == null) {
          bestMismatchReason = wordFailureMsg;
        }
      }

      if (!namePassed) {
        if (bestMismatchReason != null) {
          errors.add("Recipient name does not match: $bestMismatchReason");
        } else {
          errors.add("Recipient name does not match: expected '$expNameClean' was not found on the receipt.");
        }
      }
    }

    // ==========================================
    // RULE 2: AMOUNT
    // ==========================================
    String foundAmountStr = '';
    final amountPattern = RegExp(r'(?:₱\s?\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})');

    if (rawAmount.isNotEmpty && (rawAmount.contains('.') || rawAmount.contains('₱') || rawAmount.contains('P'))) {
      foundAmountStr = rawAmount.trim();
    } else {
      // Look in raw text
      final amtMatch = amountPattern.firstMatch(rawText);
      if (amtMatch != null) {
        foundAmountStr = amtMatch.group(0)!;
      }
    }

    if (foundAmountStr.isEmpty) {
      errors.add("Amount could not be read from the receipt.");
    } else {
      // Strict regex format check: ^₱\s?\d{1,3}(,\d{3})*\.\d{2}$ or ^\d+\.\d{2}$
      final strictFormat = RegExp(r'^(?:₱\s?\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})$');
      if (!strictFormat.hasMatch(foundAmountStr)) {
        errors.add("Amount format is invalid: found '$foundAmountStr'. Expected format like ₱100.00.");
      } else {
        // Numeric value check against expectedAmount rounded to 2 decimals
        final cleanNumStr = foundAmountStr.replaceAll(RegExp(r'[^\d\.]'), '');
        final parsedVal = double.tryParse(cleanNumStr);
        if (parsedVal == null || (parsedVal - expectedAmount).abs() >= 0.01) {
          final expStr = expectedAmount.toStringAsFixed(2);
          errors.add("Amount does not match expected amount: expected ₱$expStr, found '$foundAmountStr'.");
        }
      }
    }

    // ==========================================
    // RULE 3: DATE AND TIME
    // ==========================================
    String foundDateStr = rawDate.trim();
    if (foundDateStr.isEmpty) {
      final dateMatch = RegExp(r'[A-Za-z]{3}\s+\d{1,2},?\s+\d{4}\s+\d{1,2}:\d{2}\s*(?:AM|PM)?', caseSensitive: false).firstMatch(rawText);
      if (dateMatch != null) {
        foundDateStr = dateMatch.group(0)!.trim();
      }
    }

    if (foundDateStr.isEmpty) {
      errors.add("Date and time could not be read from the receipt.");
    } else {
      final dateStrictRegex = RegExp(r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s(\d{1,2}),\s(\d{4})\s(\d{1,2}):(\d{2})\s(AM|PM)$', caseSensitive: false);
      final match = dateStrictRegex.firstMatch(foundDateStr);
      if (match == null) {
        errors.add("Date format is invalid: expected 'Mon DD, YYYY hh:mm AM/PM' (e.g. Oct 13, 2026 12:18 PM), found '$foundDateStr'.");
      } else {
        // Validate calendar date & time validity
        final monthStr = match.group(1)!.toLowerCase();
        final day = int.parse(match.group(2)!);
        final year = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);

        const monthMap = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
        };
        final month = monthMap[monthStr] ?? 1;

        bool isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
        final daysInMonths = [0, 31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

        if (day < 1 || day > daysInMonths[month] || hour < 1 || hour > 12 || minute < 0 || minute > 59) {
          errors.add("Date format is invalid: contains an impossible date or time '$foundDateStr'.");
        }
      }
    }

    // ==========================================
    // RULE 4: REFERENCE NUMBER
    // ==========================================
    String foundRefStr = '';
    final refGroupedPattern = RegExp(r'\b\d{4}\s\d{3}\s\d{6}\b');
    final matchGrouped = refGroupedPattern.firstMatch(rawText);

    if (matchGrouped != null) {
      foundRefStr = matchGrouped.group(0)!;
    } else if (rawReference.isNotEmpty) {
      foundRefStr = rawReference.trim();
    }

    if (foundRefStr.isEmpty) {
      errors.add("Reference number could not be read from the receipt.");
    } else {
      final strictRefRegex = RegExp(r'^\d{4}\s\d{3}\s\d{6}$');
      if (!strictRefRegex.hasMatch(foundRefStr)) {
        final totalDigits = foundRefStr.replaceAll(RegExp(r'\D'), '').length;
        if (totalDigits != 13) {
          errors.add("Reference number format is invalid: expected 13 digits as '0000 000 000000', found $totalDigits digits.");
        } else {
          errors.add("Reference number format is invalid: expected 13 digits grouped as '0000 000 000000', found '$foundRefStr'.");
        }
      }
    }

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
      'cleanReference': rawReference.replaceAll(RegExp(r'\D'), ''),
    };
  }

  /// On-device OCR fallback supporting both 1-line and 2-line GCash reference formats
  static Future<Map<String, dynamic>> _extractOnDeviceMLKit(
      File imageFile, double expectedAmount, String expectedRecipient, {String expectedPhone = ""}) async {
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

      // Strict 13 digits check for reference number
      if (referenceNumber == null || referenceNumber.length != 13) {
        return {
          'success': false,
          'error': 'Reference Number must strictly be exactly 13 digits. Missing or tampered.',
        };
      }

      // 5. Strict Amount & Total Amount Verification
      // Look for PHP, P, ₱, Amount, Total followed by numbers
      final labeledAmountRegex = RegExp(r'(?:Amount|Total\s*Amount|Total)\s*[:\-]?\s*(?:PHP|P|₱)?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))', caseSensitive: false);
      final currencyAmountRegex = RegExp(r'(?:PHP|P|₱)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))', caseSensitive: false);
      
      final List<double> checkedAmounts = [];
      for (final m in labeledAmountRegex.allMatches(fullText)) {
        final clean = m.group(1)!.replaceAll(',', '').trim();
        final v = double.tryParse(clean);
        if (v != null && v > 0.0) checkedAmounts.add(v);
      }
      for (final m in currencyAmountRegex.allMatches(fullText)) {
        final clean = m.group(1)!.replaceAll(',', '').trim();
        final v = double.tryParse(clean);
        if (v != null && v > 0.0) checkedAmounts.add(v);
      }

      if (checkedAmounts.isNotEmpty) {
        for (final val in checkedAmounts) {
          if ((val - expectedAmount).abs() >= 0.01) {
            return {
              'success': false,
              'error': 'Amount discrepancy detected: Found PHP ${val.toStringAsFixed(2)} which does not match expected PHP ${expectedAmount.toStringAsFixed(2)} (possible edit/tampering).',
              'reference_number': referenceNumber,
            };
          }
        }
      } else {
        final plainNumMatches = RegExp(r'\b([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})\b').allMatches(fullText);
        bool foundExact = false;
        for (final m in plainNumMatches) {
          final clean = m.group(1)!.replaceAll(',', '').trim();
          final v = double.tryParse(clean);
          if (v != null && (v - expectedAmount).abs() < 0.01) {
            foundExact = true;
            break;
          }
        }
        if (!foundExact) {
          return {
            'success': false,
            'error': 'Amount discrepancy: Expected PHP ${expectedAmount.toStringAsFixed(2)} was not found on receipt or was modified.',
            'reference_number': referenceNumber,
          };
        }
      }

      // 6. Recipient Name Verification (if expected recipient provided)
      if (expectedRecipient.trim().isNotEmpty) {
        final cleanRecipient = expectedRecipient.replaceAll(RegExp(r'[^A-Za-z\s]'), '').trim().toUpperCase();
        final recipientWords = cleanRecipient.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        bool recipientMatched = false;
        final upperText = fullText.toUpperCase();

        // Normalize various circle and mask symbols in the OCR text to standard '*'
        final normalizedText = upperText.replaceAll(RegExp(r'[•●○⦿⦾◦·\*\-_]'), '*');

        for (final word in recipientWords) {
          // Direct match of word in text
          if (upperText.contains(word)) {
            recipientMatched = true;
            break;
          }

          if (word.length >= 3) {
            final firstChar = RegExp.escape(word[0]);
            final lastChar = RegExp.escape(word[word.length - 1]);

            // Pattern 1: First letter + mask symbols + Last letter (e.g. K***A, K•••A, K○○○A)
            final patternWithEnd = RegExp(firstChar + r'[\s\*oO0\.]{1,12}?' + lastChar);
            // Pattern 2: First letter + at least 2 mask symbols (e.g. K***, K•••, K○○○, K*** B.)
            final patternPrefixOnly = RegExp(firstChar + r'[\*]{2,}');
            // Pattern 3: 2-letter abbreviation e.g. "JN" for "JUAN"
            final patternAbbr = RegExp(r'\b' + firstChar + lastChar + r'\b');

            if (patternWithEnd.hasMatch(normalizedText) || patternPrefixOnly.hasMatch(normalizedText) || patternAbbr.hasMatch(normalizedText)) {
              recipientMatched = true;
              break;
            }
          } else if (word.length == 2) {
            final firstChar = RegExp.escape(word[0]);
            if (RegExp(firstChar + r'[\*]{2,}').hasMatch(normalizedText)) {
              recipientMatched = true;
              break;
            }
          }
        }

        // Additional check: combined initials pattern e.g., "K*** M*** B" or "Jn D."
        if (!recipientMatched && recipientWords.length >= 2) {
          final firstInitial = RegExp.escape(recipientWords.first[0]);
          final lastInitial = RegExp.escape(recipientWords.last[0]);
          final initialsPattern = RegExp(firstInitial + r'[\s\*A-Za-z\.]{1,25}?' + lastInitial);
          if (initialsPattern.hasMatch(normalizedText)) {
            recipientMatched = true;
          }
        }

        if (!recipientMatched) {
          return {
            'success': false,
            'error': 'Recipient Name mismatch: Expected \'$expectedRecipient\', but name on receipt does not match or was altered.',
            'reference_number': referenceNumber,
          };
        }
      }

      // 7. Phone Number Verification
      final phoneCandidates = RegExp(r'(?:\+?63[\s\-]?)?(?:0?9[\s\d\*•●○⦿⦾◦·\-_]{9,16})').allMatches(fullText).map((m) => m.group(0)!).toList();
      if (expectedPhone.trim().isNotEmpty) {
        String cleanExpPhone = expectedPhone.replaceAll(RegExp(r'\D'), '').trim();
        if (cleanExpPhone.startsWith('63')) {
          cleanExpPhone = '0${cleanExpPhone.substring(2)}';
        }
        bool phoneMatched = false;
        for (final cand in phoneCandidates) {
          String normCand = cand.replaceAll(RegExp(r'[•●○⦿⦾◦·\-_]'), '*').replaceAll(RegExp(r'[\s\-]'), '');
          if (normCand.startsWith('+63')) {
            normCand = '0${normCand.substring(3)}';
          } else if (normCand.startsWith('63')) {
            normCand = '0${normCand.substring(2)}';
          }
          final candDigits = normCand.replaceAll(RegExp(r'\D'), '');
          if (candDigits == cleanExpPhone) {
            phoneMatched = true;
            break;
          }
          if (normCand.contains('*') && normCand.length == cleanExpPhone.length) {
            bool maskedOk = true;
            for (int ci = 0; ci < normCand.length; ci++) {
              if (normCand[ci] != '*' && normCand[ci] != cleanExpPhone[ci]) {
                maskedOk = false;
                break;
              }
            }
            if (maskedOk) {
              phoneMatched = true;
              break;
            }
          }
        }
        if (!phoneMatched) {
          return {
            'success': false,
            'error': 'Phone Number mismatch: Expected \'$expectedPhone\' does not match recipient number on receipt.',
            'reference_number': referenceNumber,
          };
        }
      }

      // 8. Date & Time Verification (Strict Chronological Format)
      final dtRegexes = [
        RegExp(r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\s+(?:at\s+)?\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b', caseSensitive: false),
        RegExp(r'\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{4}\s+(?:at\s+)?\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b', caseSensitive: false),
        RegExp(r'\b\d{4}[-/]\d{2}[-/]\d{2}\s+\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b', caseSensitive: false),
        RegExp(r'\b\d{1,2}[-/]\d{1,2}[-/]\d{4}\s+\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b', caseSensitive: false),
      ];
      String? matchedDateTime;
      for (final r in dtRegexes) {
        final m = r.firstMatch(fullText);
        if (m != null) {
          matchedDateTime = m.group(0)!.trim();
          break;
        }
      }
      if (matchedDateTime == null) {
        return {
          'success': false,
          'error': 'Date & Time is missing, incomplete, or does not match valid chronological format.',
          'reference_number': referenceNumber,
        };
      }

      return {
        'success': true,
        'reference_number': referenceNumber,
        'amount': expectedAmount.toStringAsFixed(2),
        'date': matchedDateTime,
        'status': 'Successful',
        'raw_reference': referenceNumber,
        'raw_amount': expectedAmount.toStringAsFixed(2),
        'raw_date': matchedDateTime,
        'extracted_text': fullText,
      };
    } catch (e) {
      print("MLKit processing error: $e");
      return {'success': false, 'error': e.toString()};
    } finally {
      textRecognizer.close();
    }
  }

  // Warm up backend verification server (called e.g. when entering registration screen)
  static Future<void> warmUpVerificationServer() async {
    try {
      final uri = Uri.parse('https://walk-versus-peculiar.ngrok-free.dev/health');
      final response = await http.get(uri, headers: {
        'ngrok-skip-browser-warning': '69420',
      }).timeout(const Duration(seconds: 10));
      debugPrint("FaceScan: warmUpVerificationServer status=${response.statusCode}");
    } catch (e) {
      debugPrint("FaceScan: warmUpVerificationServer notice: $e");
    }
  }

  // Verify ID Name & Face via Python EasyOCR + DeepFace Backend
  static Future<Map<String, dynamic>> verifyIdName(
    File imageFile,
    File? selfieFile,
    String firstName,
    String lastName,
    String idType, {
    String middleName = "",
  }) async {
    final uri = Uri.parse('https://walk-versus-peculiar.ngrok-free.dev/verify_id');
    final stopwatch = Stopwatch()..start();

    int attempts = 0;
    const maxAttempts = 2;

    while (attempts < maxAttempts) {
      attempts++;
      try {
        final request = http.MultipartRequest('POST', uri);
        request.headers['ngrok-skip-browser-warning'] = '69420';

        final idBytes = await imageFile.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('image', idBytes, filename: 'id.jpg'));

        if (selfieFile != null) {
          final selfieBytes = await selfieFile.readAsBytes();
          request.files.add(http.MultipartFile.fromBytes('selfie', selfieBytes, filename: 'selfie.jpg'));
        }

        request.fields['firstName'] = firstName;
        request.fields['middleName'] = middleName;
        request.fields['lastName'] = lastName;
        request.fields['idType'] = idType;

        debugPrint('FaceScan: sending verify_id request (attempt $attempts/$maxAttempts, idBytes=${idBytes.length}, selfieBytes=${selfieFile != null ? 'present' : 'none'})...');
        final streamedResponse = await request.send().timeout(const Duration(seconds: 50));
        final response = await http.Response.fromStream(streamedResponse);
        final durationMs = stopwatch.elapsedMilliseconds;

        debugPrint('FaceScan: verify_id HTTP ${response.statusCode} in ${durationMs}ms, body: ${response.body}');

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          if (json is Map<String, dynamic>) {
            return json;
          }
        } else {
          debugPrint('FaceScan: server returned HTTP ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('FaceScan: attempt $attempts failed with error: $e');
        if (attempts >= maxAttempts) {
          final durationMs = stopwatch.elapsedMilliseconds;
          debugPrint('FaceScan: all $maxAttempts attempts failed after ${durationMs}ms: $e');
          return {
            'success': false,
            'network_error': true,
            'error': e.toString(),
            'message': 'Verification service is busy. Please try again.'
          };
        }
        // Brief delay before retry
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    return {
      'success': false,
      'network_error': true,
      'error': 'Server Error',
      'message': 'Verification service is busy. Please try again.'
    };
  }

  // Face Detection for Identity Verification
  static Future<bool> detectFace(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final options = FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      minFaceSize: 0.1, // Accept face if at least ~10% of image height
      performanceMode: FaceDetectorMode.fast,
    );
    final faceDetector = FaceDetector(options: options);
    
    try {
      final List<Face> faces = await faceDetector.processImage(inputImage);
      final hasFace = faces.isNotEmpty;
      debugPrint("FaceScan: detectFace faceCount=${faces.length} result=${hasFace ? 'PASS' : 'FAIL'}");
      return hasFace;
    } catch (e) {
      debugPrint("Face Detection Error: $e");
      return false;
    } finally {
      faceDetector.close();
    }
  }
}
