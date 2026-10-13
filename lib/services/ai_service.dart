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
  // =========================================================================
  // ISOLATED FIELD VALIDATORS (Each field has zero shared mutable state or regex)
  // =========================================================================

  /// 1. Recipient Name Validator
  static Map<String, dynamic> validateRecipientName({
    required dynamic rawLines,
    required String rawText,
    required String expectedRecipient,
  }) {
    final expNameClean = expectedRecipient.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (expNameClean.isEmpty) {
      return {'valid': true, 'error': null};
    }

    String stripAccents(String str) {
      const withAccents = 'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÑñÇç';
      const withoutAccents = 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuNnCc';
      var res = str;
      for (var i = 0; i < withAccents.length; i++) {
        res = res.replaceAll(withAccents[i], withoutAccents[i]);
      }
      return res;
    }

    String normalizeMaskChars(String str) {
      return str.replaceAll(RegExp(r'[\*∗✱✲•·]'), '*');
    }

    final normExpName = stripAccents(expNameClean).toLowerCase();
    final rawExpWords = expNameClean.split(' ').where((w) => w.isNotEmpty).toList();
    final expWords = rawExpWords.map((w) => stripAccents(w.replaceAll(RegExp(r'\.+$'), '')).toLowerCase()).toList();
    final numWords = expWords.length;

    final List<String> lines = (rawLines is List && rawLines.isNotEmpty)
        ? rawLines.map((e) => e.toString()).toList()
        : rawText.split('\n');

    bool namePassed = false;
    final List<List<String>> candidateWordLists = [];

    for (final line in lines) {
      final trimmed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (trimmed.isEmpty) continue;

      final normLine = stripAccents(trimmed).toLowerCase();
      final normExpNoDots = expWords.join(' ');
      if (normLine == normExpName || normLine == normExpNoDots || normLine.contains(normExpName) || normLine.contains(normExpNoDots)) {
        namePassed = true;
        break;
      }

      final tokens = trimmed.split(' ').where((w) => w.isNotEmpty).toList();
      if (tokens.length == numWords) {
        candidateWordLists.add(tokens);
      } else if (tokens.length > numWords) {
        for (int i = 0; i <= tokens.length - numWords; i++) {
          candidateWordLists.add(tokens.sublist(i, i + numWords));
        }
      }
    }

    // Word-by-word comparison for candidate word lists
    if (!namePassed) {
      for (final candRawWords in candidateWordLists) {
        bool candidateMatches = true;

        final cleanedCandWords = candRawWords.map((w) {
          return stripAccents(w.replaceAll(RegExp(r'^[\s,:\-;]+|[\s,:\-;\.]+$'), ''));
        }).toList();

        final firstCandWord = cleanedCandWords[0];
        final firstExpWord = expWords[0];
        if (firstCandWord.isNotEmpty && firstExpWord.isNotEmpty) {
          final firstCandChar = normalizeMaskChars(firstCandWord[0]);
          if (firstCandChar == '*' || firstCandChar.toLowerCase() != firstExpWord[0].toLowerCase()) {
            candidateMatches = false;
          }
        }

        if (candidateMatches) {
          for (int wIdx = 0; wIdx < numWords; wIdx++) {
            final expW = expWords[wIdx];
            final rawCandW = cleanedCandWords[wIdx];
            final normCandW = normalizeMaskChars(rawCandW);

            if (normCandW.length != expW.length) {
              candidateMatches = false;
              break;
            }

            for (int cIdx = 0; cIdx < expW.length; cIdx++) {
              final cCand = normCandW[cIdx];
              final cExp = expW[cIdx];
              if (cCand == '*') continue;
              if (cCand.toLowerCase() != cExp.toLowerCase()) {
                candidateMatches = false;
                break;
              }
            }
            if (!candidateMatches) break;
          }
        }

        if (candidateMatches) {
          namePassed = true;
          break;
        }
      }
    }

    // OCR tolerance check (e.g. spaces merged/split)
    if (!namePassed) {
      final expWhole = expWords.join('');
      final totalExpLetters = expWhole.length;

      for (final line in lines) {
        final trimmed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (trimmed.isEmpty) continue;

        final tokens = trimmed.split(' ').where((w) => w.isNotEmpty).toList();
        final subsets = <String>[];
        if (tokens.length != numWords) {
          subsets.add(tokens.join(''));
        }
        if (tokens.length > numWords) {
          for (int len = 1; len <= tokens.length; len++) {
            for (int i = 0; i <= tokens.length - len; i++) {
              subsets.add(tokens.sublist(i, i + len).join(''));
            }
          }
        }

        for (final rawSubset in subsets) {
          final candClean = stripAccents(rawSubset.replaceAll(RegExp(r'[\s\.,:\-;]+'), ''));
          final normCandWhole = normalizeMaskChars(candClean);

          if (normCandWhole.length != totalExpLetters) continue;
          if (normCandWhole[0] == '*' || normCandWhole[0].toLowerCase() != expWhole[0].toLowerCase()) continue;

          bool wholeMatch = true;
          for (int i = 0; i < totalExpLetters; i++) {
            final cCand = normCandWhole[i];
            final cExp = expWhole[i];
            if (cCand == '*') continue;
            if (cCand.toLowerCase() != cExp.toLowerCase()) {
              wholeMatch = false;
              break;
            }
          }

          if (wholeMatch) {
            namePassed = true;
            break;
          }
        }
        if (namePassed) break;
      }
    }

    if (!namePassed) {
      return {'valid': false, 'error': 'Recipient name does not match.'};
    }
    return {'valid': true, 'error': null};
  }

  /// 2. Phone Number Validator
  static Map<String, dynamic> validatePhoneNumber({
    required String rawText,
    required String expectedPhone,
    String? rawPhone,
  }) {
    final cleanExp = expectedPhone.replaceAll(RegExp(r'\D'), '').trim();
    if (cleanExp.isEmpty) {
      return {'valid': true, 'error': null};
    }

    String targetPhone = cleanExp;
    if (targetPhone.startsWith('63')) {
      targetPhone = '0${targetPhone.substring(2)}';
    }

    // Direct check if rawPhone was passed and matched
    if (rawPhone != null && rawPhone.trim().isNotEmpty) {
      String cleanRaw = rawPhone.replaceAll(RegExp(r'\D'), '');
      if (cleanRaw.startsWith('63')) cleanRaw = '0${cleanRaw.substring(2)}';
      if (cleanRaw == targetPhone) {
        return {'valid': true, 'error': null};
      }
    }

    final phoneCandidates = RegExp(r'(?:\+?63[\s\-]?)?(?:0?9[\s\d\*•●○⦿⦾◦·\-_]{9,16})').allMatches(rawText);
    bool phoneMatched = false;

    for (final match in phoneCandidates) {
      final cand = match.group(0)!;
      final normCand = cand.replaceAll(RegExp(r'[•●○⦿⦾◦·\-_]'), '*');
      var candClean = normCand.replaceAll(RegExp(r'[\s\-]'), '');
      if (candClean.startsWith('+63')) {
        candClean = '0${candClean.substring(3)}';
      } else if (candClean.startsWith('63')) {
        candClean = '0${candClean.substring(2)}';
      }

      final candDigits = candClean.replaceAll(RegExp(r'\D'), '');
      if (candDigits == targetPhone) {
        phoneMatched = true;
        break;
      }

      if (candClean.contains('*') && candClean.length == targetPhone.length) {
        bool maskedOk = true;
        for (int i = 0; i < candClean.length; i++) {
          final cCand = candClean[i];
          final cExp = targetPhone[i];
          if (cCand != '*' && cCand != cExp) {
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
      return {'valid': false, 'error': 'Phone number does not match recipient number.'};
    }
    return {'valid': true, 'error': null};
  }

  /// 3. Amount Validator
  static Map<String, dynamic> validateAmount({
    required String rawAmount,
    required String rawText,
    required double expectedAmount,
  }) {
    String foundAmountStr = '';

    if (rawAmount.trim().isNotEmpty) {
      foundAmountStr = rawAmount.trim();
    } else {
      final amtLabelMatch = RegExp(r'(?:Amount|Total\s*Amount|Total)\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false).firstMatch(rawText);
      if (amtLabelMatch != null) {
        foundAmountStr = amtLabelMatch.group(1)!.trim();
      } else {
        final curMatch = RegExp(r'(?:₱|PHP|Php|P)\s*[\d,\.\s]+', caseSensitive: false).firstMatch(rawText);
        if (curMatch != null) {
          foundAmountStr = curMatch.group(0)!.trim();
        }
      }
    }

    if (foundAmountStr.isEmpty) {
      return {'valid': false, 'error': "We couldn't read the receipt clearly. Please upload a clearer screenshot."};
    }

    final trimmedAmt = foundAmountStr.trim();
    final numPart = trimmedAmt.replaceAll(RegExp(r'^(?:₱|PHP|Php|P)\s*', caseSensitive: false), '').trim();
    final validAmountShape = RegExp(r'^(?:\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})$');

    if (!validAmountShape.hasMatch(numPart)) {
      return {'valid': false, 'error': 'The amount on the receipt is incorrect or has been altered.'};
    }

    final cleanNumStr = numPart.replaceAll(',', '');
    final parsedVal = double.tryParse(cleanNumStr);
    if (parsedVal == null || (parsedVal - expectedAmount).abs() >= 0.01) {
      return {'valid': false, 'error': 'The amount on the receipt is incorrect or has been altered.'};
    }

    return {'valid': true, 'error': null};
  }

  /// 4. Reference Number Validator
  static Map<String, dynamic> validateReference({
    required String rawReference,
    required String rawText,
  }) {
    String foundRefStr = '';

    // Priority: use explicit rawReference if provided, otherwise search grouped pattern in rawText
    if (rawReference.trim().isNotEmpty) {
      foundRefStr = rawReference.trim();
    } else {
      final refGroupedPattern = RegExp(r'\b\d{4}\s\d{3}\s\d{6}\b');
      final matchGrouped = refGroupedPattern.firstMatch(rawText);
      if (matchGrouped != null) {
        foundRefStr = matchGrouped.group(0)!;
      }
    }

    if (foundRefStr.isEmpty) {
      return {'valid': false, 'error': "We couldn't read the receipt clearly. Please upload a clearer screenshot."};
    }

    final strictRefRegex = RegExp(r'^\d{4}\s\d{3}\s\d{6}$');
    final digitsOnly = foundRefStr.replaceAll(RegExp(r'\D'), '');
    if (!strictRefRegex.hasMatch(foundRefStr)) {
      return {'valid': false, 'error': 'The reference number is invalid or has already been used.'};
    }

    return {'valid': true, 'error': null, 'cleanReference': digitsOnly};
  }

  /// 5. Date and Time Validator
  static Map<String, dynamic> validateDateTime({
    required String rawDate,
    required String rawText,
  }) {
    String foundDateStr = rawDate.trim();
    if (foundDateStr.isEmpty) {
      final dateMatch = RegExp(r'[A-Za-z]{3}\s+\d{1,2},?\s+\d{4}\s+\d{1,2}[:.]\d{2}\s*(?:AM|PM)?', caseSensitive: false).firstMatch(rawText);
      if (dateMatch != null) {
        foundDateStr = dateMatch.group(0)!.trim();
      }
    }

    if (foundDateStr.isEmpty) {
      return {'valid': false, 'error': "We couldn't read the receipt clearly. Please upload a clearer screenshot."};
    }

    // Normalize OCR period separator in time e.g. "08.30 PM" -> "08:30 PM"
    String normalizedDateStr = foundDateStr.replaceAllMapped(
      RegExp(r'(\d{1,2})\.(\d{2})\s*(AM|PM)', caseSensitive: false),
      (m) => '${m.group(1)}:${m.group(2)} ${m.group(3)}',
    );

    // Normalize comma spacing if missing e.g. "Oct 13 2026" -> "Oct 13, 2026"
    normalizedDateStr = normalizedDateStr.replaceAllMapped(
      RegExp(r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})\s+', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}, ${m.group(3)} ',
    );

    final dateStrictRegex = RegExp(r'^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s(\d{1,2}),\s(\d{4})\s(\d{1,2}):(\d{2})\s(AM|PM)$', caseSensitive: false);
    final match = dateStrictRegex.firstMatch(normalizedDateStr);
    if (match == null) {
      return {'valid': false, 'error': 'The date and time on the receipt appear to be altered or invalid.'};
    }

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
      return {'valid': false, 'error': 'The date and time on the receipt appear to be altered or invalid.'};
    }

    return {'valid': true, 'error': null};
  }

  /// GCash Receipt Validator aggregating isolated field checks
  static Map<String, dynamic> validateGCashReceipt({
    required Map<String, dynamic>? ocrData,
    required double expectedAmount,
    required String expectedRecipient,
    String expectedPhone = "",
  }) {
    if (ocrData == null) {
      return {
        'isValid': false,
        'errors': ['Receipt could not be processed by OCR scanner.'],
        'cleanReference': '',
      };
    }

    final rawReference = ocrData['raw_reference']?.toString() ?? ocrData['reference_number']?.toString() ?? '';
    final rawAmount = ocrData['raw_amount']?.toString() ?? ocrData['amount']?.toString() ?? '';
    final rawDate = ocrData['raw_date']?.toString() ?? ocrData['date']?.toString() ?? '';
    final rawPhone = ocrData['phone']?.toString() ?? '';
    final rawText = ocrData['extracted_text']?.toString() ?? '';
    final rawLines = ocrData['raw_lines'];

    // 1. Recipient Name check (isolated)
    final nameResult = validateRecipientName(
      rawLines: rawLines,
      rawText: rawText,
      expectedRecipient: expectedRecipient,
    );

    // 2. Phone Number check (isolated)
    final phoneResult = validatePhoneNumber(
      rawText: rawText,
      expectedPhone: expectedPhone,
      rawPhone: rawPhone,
    );

    // 3. Amount check (isolated)
    final amountResult = validateAmount(
      rawAmount: rawAmount,
      rawText: rawText,
      expectedAmount: expectedAmount,
    );

    // 4. Reference Number check (isolated)
    final referenceResult = validateReference(
      rawReference: rawReference,
      rawText: rawText,
    );

    // 5. Date and Time check (isolated)
    final dateTimeResult = validateDateTime(
      rawDate: rawDate,
      rawText: rawText,
    );

    // Collect errors strictly keyed by field
    final Map<String, String?> fieldErrors = {
      'recipientName': nameResult['valid'] ? null : nameResult['error'],
      'phone': phoneResult['valid'] ? null : phoneResult['error'],
      'amount': amountResult['valid'] ? null : amountResult['error'],
      'reference': referenceResult['valid'] ? null : referenceResult['error'],
      'dateTime': dateTimeResult['valid'] ? null : dateTimeResult['error'],
    };

    final List<String> errors = [];
    if (fieldErrors['recipientName'] != null) errors.add(fieldErrors['recipientName']!);
    if (fieldErrors['phone'] != null) errors.add(fieldErrors['phone']!);
    if (fieldErrors['amount'] != null) errors.add(fieldErrors['amount']!);
    if (fieldErrors['reference'] != null) errors.add(fieldErrors['reference']!);
    if (fieldErrors['dateTime'] != null) errors.add(fieldErrors['dateTime']!);

    final cleanRef = referenceResult['cleanReference']?.toString() ?? rawReference.replaceAll(RegExp(r'\D'), '');

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
      'fieldErrors': fieldErrors,
      'cleanReference': cleanRef,
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

      final List<String> allLines = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) allLines.add(t);
        }
      }

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
        for (int i = 0; i < allLines.length; i++) {
          final line = allLines[i];
          if (RegExp(r'Ref[\s\.]*No', caseSensitive: false).hasMatch(line)) {
            String digits = line.replaceAll(RegExp(r'\D'), '');
            if (digits.length >= 13) {
              referenceNumber = digits.substring(0, 13);
              break;
            }
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

      // Extract amount candidate
      String? extractedAmount;
      final labeledAmountMatch = RegExp(r'(?:Amount|Total\s*Amount|Total)\s*[:\-]?\s*(?:PHP|P|₱)?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))', caseSensitive: false).firstMatch(fullText);
      if (labeledAmountMatch != null) {
        extractedAmount = labeledAmountMatch.group(1);
      } else {
        final currencyAmountMatch = RegExp(r'(?:PHP|P|₱)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))', caseSensitive: false).firstMatch(fullText);
        if (currencyAmountMatch != null) {
          extractedAmount = currencyAmountMatch.group(1);
        }
      }

      // Extract date candidate
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

      // Format reference number as grouped if 13 digits
      String formattedRef = referenceNumber ?? '';
      if (formattedRef.length == 13) {
        formattedRef = '${formattedRef.substring(0, 4)} ${formattedRef.substring(4, 7)} ${formattedRef.substring(7, 13)}';
      }

      // Extract phone candidate
      String? extractedPhone;
      final phoneMatch = RegExp(r'(?:\+?63[\s\-]?)?(?:0?9[\s\d\*•●○⦿⦾◦·\-_]{9,16})').firstMatch(fullText);
      if (phoneMatch != null) {
        extractedPhone = phoneMatch.group(0)!.trim();
      }

      // Return raw OCR extraction data for validateGCashReceipt to evaluate
      return {
        'success': true,
        'reference_number': formattedRef,
        'amount': extractedAmount ?? expectedAmount.toStringAsFixed(2),
        'date': matchedDateTime ?? '',
        'phone': extractedPhone ?? '',
        'status': 'Successful',
        'raw_reference': formattedRef,
        'raw_amount': extractedAmount ?? '',
        'raw_date': matchedDateTime ?? '',
        'raw_lines': allLines,
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
