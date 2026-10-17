import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';

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

    // Normalizes all GCash mask characters (bullets, dots, asterisks, circles)
    String normalizeMaskChars(String str) {
      var res = str.replaceAll(RegExp(r'[•●○◦·∙⦿⦾◉⬤*∗✱✲\-_]'), '*');
      res = res.replaceAllMapped(RegExp(r'(?<=[A-Za-z0-9])\.+(?=[A-Za-z0-9])'), (m) => '*' * m.group(0)!.length);
      return res;
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

      // Unmasked exact match anywhere in line
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

      // OCR recovery: if last token is 2 characters without period (e.g. 'NL' or 'NL:'),
      // EasyOCR often split the middle word and attached its last letter to the initial.
      if (tokens.length >= 2) {
        final lastTokenClean = tokens.last.replaceAll(RegExp(r'[:;,\.]+$'), '');
        final prevToken = tokens[tokens.length - 2];
        if (lastTokenClean.length == 2 && !tokens.last.contains('.')) {
          final mergedMiddle = prevToken + lastTokenClean[0];
          final newInitial = lastTokenClean[1];
          final retokenized = [...tokens.sublist(0, tokens.length - 2), mergedMiddle, newInitial];
          if (retokenized.length == numWords) {
            candidateWordLists.add(retokenized);
          } else if (retokenized.length > numWords) {
            for (int i = 0; i <= retokenized.length - numWords; i++) {
              candidateWordLists.add(retokenized.sublist(i, i + numWords));
            }
          }
        }
      }
    }

    // GCash-aware word-by-word comparison.
    // GCash masks middle characters of names (e.g. "KE•••A" for "KEISHA").
    // OCR often reads mask dots as random lowercase letters (e.g. "KEooA", "KEeoA")
    // and may produce different character counts than the original.
    // Strategy: verify first char of first word, first+last char of each word,
    // and allow flexible middle lengths (±3 chars tolerance).
    if (!namePassed) {
      // Helper: check if a candidate word matches expected word with GCash masking tolerance
      bool gcashWordMatch(String candW, String expW) {
        if (candW.isEmpty || expW.isEmpty) return candW.isEmpty && expW.isEmpty;

        final normCandW = normalizeMaskChars(candW).toLowerCase();
        final normExpW = normalizeMaskChars(expW).toLowerCase();

        // For very short words (1-2 chars)
        if (normExpW.length <= 2) {
          // Strip trailing dots/periods for single-letter initials (e.g. "B." vs "b")
          final candStripped = normCandW.replaceAll(RegExp(r'\.+$'), '');
          final expStripped = normExpW.replaceAll(RegExp(r'\.+$'), '');
          if (candStripped == expStripped) return true;
          // Allow masking of second char (e.g. 'j*' matching 'jr')
          if (candStripped.length == expStripped.length &&
              candStripped[0] == expStripped[0] &&
              candStripped.substring(1).split('').every((c) => c == '*')) {
            return true;
          }
          return false;
        }

        // First character must match (GCash never masks the first char)
        final firstCand = normCandW[0];
        final firstExp = normExpW[0];
        if (firstCand == '*' || firstCand != firstExp) return false;

        // Case 0: Direct positional match if same character length
        if (normCandW.length == normExpW.length) {
          bool posMatch = true;
          for (int i = 0; i < normCandW.length; i++) {
            if (normCandW[i] != '*' && normCandW[i] != normExpW[i]) {
              posMatch = false;
              break;
            }
          }
          if (posMatch) return true;
        }

        // Tolerating GCash masks & EasyOCR misreading mask bullets/dots as 'o', 'e', 'u', '0':
        // Case A: The candidate word after the first letter is composed only of mask characters or OCR misread symbols (e.g. "M**", "M••", "Moo", "Mee" for "May")
        final afterFirst = normCandW.substring(1);
        if (RegExp(r'^[oeu0*•●○◦∙\-_]+$').hasMatch(afterFirst)) {
          return true;
        }

        // Case B: Last visible character of candidate must match expected word's last char
        // (e.g. "KEoA" or "KE•••A" for "Keisha", last visible char 'a' == 'a')
        if (!normCandW.endsWith('*')) {
          String lastExpChar = '';
          for (int i = normExpW.length - 1; i >= 0; i--) {
            if (normExpW[i] != '*') {
              lastExpChar = normExpW[i];
              break;
            }
          }
          String lastCandChar = '';
          for (int i = normCandW.length - 1; i >= 0; i--) {
            if (normCandW[i] != '*') {
              lastCandChar = normCandW[i];
              break;
            }
          }
          // If expected has a visible last char, candidate's last visible char must match
          if (lastExpChar.isNotEmpty && lastCandChar.isNotEmpty) {
            if (lastExpChar != lastCandChar) return false;
          }
        }

        // Allow flexible word length: OCR can merge/split mask dots
        // Tolerate length difference of up to 3 characters
        if ((normCandW.length - normExpW.length).abs() > 3) return false;

        return true;
      }

      for (final candRawWords in candidateWordLists) {
        bool candidateMatches = true;

        final cleanedCandWords = candRawWords.map((w) {
          return stripAccents(w.replaceAll(RegExp(r'^[\s,:\-;]+|[\s,:\-;\.]+$'), ''));
        }).toList();

        final firstCandWord = cleanedCandWords[0];
        final firstExpWord = expWords[0];
        if (firstCandWord.isNotEmpty && firstExpWord.isNotEmpty) {
          final firstCandChar = normalizeMaskChars(firstCandWord[0]);
          final firstExpChar = normalizeMaskChars(firstExpWord[0]);
          if (firstCandChar == '*' || firstCandChar.toLowerCase() != firstExpChar.toLowerCase()) {
            candidateMatches = false;
          }
        }

        if (candidateMatches) {
          for (int wIdx = 0; wIdx < numWords; wIdx++) {
            final expW = expWords[wIdx];
            final rawCandW = cleanedCandWords[wIdx];
            if (!gcashWordMatch(rawCandW, expW)) {
              candidateMatches = false;
              break;
            }
          }
        }

        if (candidateMatches) {
          namePassed = true;
          break;
        }
      }
    }

    // OCR tolerance check (e.g. spaces merged/split across line)
    // Also uses GCash-aware flexible matching
    if (!namePassed) {
      final expWhole = normalizeMaskChars(expWords.join('')).toLowerCase();

      for (final line in lines) {
        final trimmed = line.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (trimmed.isEmpty) continue;

        final tokens = trimmed.split(' ').where((w) => w.isNotEmpty).toList();
        final subsets = <String>[tokens.join('')];
        if (tokens.length > numWords) {
          for (int len = 1; len <= tokens.length; len++) {
            for (int i = 0; i <= tokens.length - len; i++) {
              subsets.add(tokens.sublist(i, i + len).join(''));
            }
          }
        }

        for (final rawSubset in subsets) {
          final candClean = stripAccents(rawSubset.replaceAll(RegExp(r'[\s\.,:\-;]+'), ''));
          final normCandWhole = normalizeMaskChars(candClean).toLowerCase();

          // Allow flexible length (±3 tolerance for OCR-mangled mask chars)
          if ((normCandWhole.length - expWhole.length).abs() > 3) continue;
          if (normCandWhole.isEmpty) continue;
          if (normCandWhole[0] == '*' || normCandWhole[0] != expWhole[0]) continue;

          // Check that all visible (non-mask) chars in expected appear in roughly the right positions
          bool wholeMatch = true;
          int candIdx = 0;
          int expIdx = 0;
          while (expIdx < expWhole.length && candIdx < normCandWhole.length) {
            final cExp = expWhole[expIdx];
            final cCand = normCandWhole[candIdx];
            if (cExp == '*') {
              // Expected char is masked – skip both
              expIdx++;
              candIdx++;
              continue;
            }
            if (cCand == '*') {
              // Candidate char is masked – skip candidate
              candIdx++;
              continue;
            }
            if (cCand == cExp) {
              expIdx++;
              candIdx++;
            } else {
              // Allow skipping candidate chars (OCR inserted extra chars for mask dots)
              candIdx++;
              // But limit how far we skip
              if (candIdx - expIdx > 4) {
                wholeMatch = false;
                break;
              }
            }
          }
          // Check we consumed all expected visible chars
          while (expIdx < expWhole.length && expWhole[expIdx] == '*') {
            expIdx++;
          }
          if (expIdx < expWhole.length) wholeMatch = false;

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

  /// 2. Phone Number Validator (Normalizes both to canonical 09XXXXXXXXX)
  static Map<String, dynamic> validatePhoneNumber({
    required String rawText,
    required String expectedPhone,
    String? rawPhone,
  }) {
    final cleanExpDigits = expectedPhone.replaceAll(RegExp(r'\D'), '').trim();
    if (cleanExpDigits.isEmpty) {
      return {'valid': true, 'error': null};
    }

    String normalizePhone(String p) {
      var d = p.replaceAll(RegExp(r'\D'), '');
      if (d.startsWith('63') && d.length == 12) {
        return '0${d.substring(2)}';
      } else if (d.startsWith('9') && d.length == 10) {
        return '0$d';
      }
      return d;
    }

    final targetPhone = normalizePhone(cleanExpDigits);

    if (rawPhone != null && rawPhone.trim().isNotEmpty) {
      if (normalizePhone(rawPhone) == targetPhone) {
        return {'valid': true, 'error': null};
      }
    }

    final phoneCandidates = RegExp(r'(?:\+?63[\s\-]?)?(?:0?9[\s\d\*•●○⦿⦾◦·\-_]{9,16})').allMatches(rawText);
    bool phoneMatched = false;

    for (final match in phoneCandidates) {
      final cand = match.group(0)!;
      final digits = cand.replaceAll(RegExp(r'\D'), '');
      if (normalizePhone(digits) == targetPhone) {
        phoneMatched = true;
        break;
      }

      // Check masked phone
      final normMask = cand.replaceAll(RegExp(r'[•●○⦿⦾◦·\-_]'), '*');
      var candClean = normMask.replaceAll(RegExp(r'[\s\-]'), '');
      if (candClean.startsWith('+63')) {
        candClean = '0${candClean.substring(3)}';
      } else if (candClean.startsWith('63')) {
        candClean = '0${candClean.substring(2)}';
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

  /// 3. Amount Validator (Total Amount Sent row as main value, Amount row as cross-check)
  static Map<String, dynamic> validateAmount({
    required String rawAmount,
    required String rawText,
    required double expectedAmount,
  }) {
    String foundAmountStr = '';

    if (rawAmount.trim().isNotEmpty) {
      foundAmountStr = rawAmount.trim();
    } else {
      // 1. Anchored search for 'Total Amount Sent' / 'Total Amount' (peso sign optional)
      final totalSentMatch = RegExp(r'Total\s*Amount(?:\s*Sent)?\s*[:\-]?\s*(?:PHP|P|₱|R|F|#|£)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})', caseSensitive: false).firstMatch(rawText);
      if (totalSentMatch != null) {
        foundAmountStr = totalSentMatch.group(1)!.trim();
      } else {
        // 2. Anchored search for plain 'Amount' row (NO peso sign required)
        final amtRowMatch = RegExp(r'(?:^|[\n\r\s])Amount\s*[:\-]?\s*(?:PHP|P|₱|R|F|#|£)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})', caseSensitive: false).firstMatch(rawText);
        if (amtRowMatch != null) {
          foundAmountStr = amtRowMatch.group(1)!.trim();
        } else {
          final curMatch = RegExp(r'(?:₱|PHP|Php|P)\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})', caseSensitive: false).firstMatch(rawText);
          if (curMatch != null) {
            foundAmountStr = curMatch.group(1)!.trim();
          }
        }
      }
    }

    if (foundAmountStr.isEmpty) {
      return {'valid': false, 'error': "We couldn't read the receipt clearly. Please upload a clearer screenshot."};
    }

    final trimmedAmt = foundAmountStr.trim();
    final numPart = trimmedAmt.replaceAll(RegExp(r'^(?:₱|PHP|Php|P|R|F|#|£)\s*', caseSensitive: false), '').trim();
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

  /// 4. Reference Number Validator (Anchored to 'Ref No.', stops after 13 digits)
  static Map<String, dynamic> validateReference({
    required String rawReference,
    required String rawText,
  }) {
    String foundRefStr = '';

    if (rawReference.trim().isNotEmpty) {
      foundRefStr = rawReference.trim();
    } else {
      // 1. Look for standard 0000 000 000000 pattern anchored to Ref No
      final refFormattedMatch = RegExp(r'Ref[\s\.]*(?:No|#)[\.\s:]*(\d{4}\s+\d{3}\s+\d{6})\b', caseSensitive: false).firstMatch(rawText);
      if (refFormattedMatch != null) {
        foundRefStr = refFormattedMatch.group(1)!;
      }

      // 2. Look for Ref No line up to the date
      if (foundRefStr.isEmpty) {
        final refLabelMatch = RegExp(r'Ref[\s\.]*(?:No|#)[\.\s:]*(.+)', caseSensitive: false).firstMatch(rawText);
        if (refLabelMatch != null) {
          final afterLabel = refLabelMatch.group(1)!.trim();
          // Cut off at the date (e.g. Oct 17, 2026) so date digits are never borrowed
          final beforeDate = afterLabel.split(RegExp(r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b', caseSensitive: false))[0];
          
          final matchGrouped = RegExp(r'\b\d{4}\s+\d{3}\s+\d{6}\b').firstMatch(beforeDate);
          if (matchGrouped != null) {
            foundRefStr = matchGrouped.group(0)!;
          } else {
            // Keep the exact digits found on the Ref No line before the date
            final digits = beforeDate.replaceAll(RegExp(r'\D'), '');
            if (digits.isNotEmpty) {
              if (digits.length == 13) {
                foundRefStr = '${digits.substring(0, 4)} ${digits.substring(4, 7)} ${digits.substring(7, 13)}';
              } else {
                foundRefStr = digits; // Incomplete digits -> will be strictly flagged as invalid!
              }
            }
          }
        }
      }

      if (foundRefStr.isEmpty) {
        final refGroupedPattern = RegExp(r'\b\d{4}\s\d{3}\s\d{6}\b');
        final matchGrouped = refGroupedPattern.firstMatch(rawText);
        if (matchGrouped != null) {
          foundRefStr = matchGrouped.group(0)!;
        }
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

  /// 5. Date and Time Validator (Date constraint removed per user request)
  static Map<String, dynamic> validateDateTime({
    required String rawDate,
    required String rawText,
    DateTime? referenceTime,
  }) {
    // Date/time constraint removed: Always valid
    return {'valid': true, 'error': null};
  }

  /// GCash Receipt Validator aggregating isolated field checks
  static Map<String, dynamic> validateGCashReceipt({
    required Map<String, dynamic>? ocrData,
    required double expectedAmount,
    String expectedRecipient = "",
    String expectedPhone = "",
    List<Map<String, String>>? expectedAccounts,
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

    // Build list of expected accounts (at least one account pair)
    final List<Map<String, String>> accounts = [];
    if (expectedAccounts != null && expectedAccounts.isNotEmpty) {
      for (final acc in expectedAccounts) {
        final n = acc['name']?.trim() ?? '';
        final p = acc['phone']?.trim() ?? '';
        if (n.isNotEmpty || p.isNotEmpty) {
          accounts.add({'name': n, 'phone': p});
        }
      }
    }
    if (accounts.isEmpty && (expectedRecipient.trim().isNotEmpty || expectedPhone.trim().isNotEmpty)) {
      accounts.add({
        'name': expectedRecipient.trim(),
        'phone': expectedPhone.trim(),
      });
    }

    if (accounts.isEmpty) {
      return {
        'isValid': false,
        'errors': ['Owner GCash account details are not configured.'],
        'cleanReference': '',
      };
    }

    // Dynamic Owner GCash Account Validation:
    // Evaluate each configured account independently.
    // If name and number both match one account, pass!
    // Otherwise select the best-matching account (highest score, preferring the primary/first account)
    // and report only the fields that failed against that account.
    Map<String, dynamic>? perfectMatchAccount;
    Map<String, dynamic>? bestAccount;
    int highestScore = -1;
    Map<String, dynamic>? bestNameRes;
    Map<String, dynamic>? bestPhoneRes;

    for (final acc in accounts) {
      final accName = acc['name'] ?? '';
      final accPhone = acc['phone'] ?? '';

      final nRes = validateRecipientName(
        rawLines: rawLines,
        rawText: rawText,
        expectedRecipient: accName,
      );
      final pRes = validatePhoneNumber(
        rawText: rawText,
        expectedPhone: accPhone,
        rawPhone: rawPhone,
      );

      final bool nOk = nRes['valid'] == true;
      final bool pOk = pRes['valid'] == true;
      int score = (nOk ? 1 : 0) + (pOk ? 1 : 0);

      if (nOk && pOk) {
        perfectMatchAccount = acc;
        bestAccount = acc;
        bestNameRes = nRes;
        bestPhoneRes = pRes;
        break;
      }

      if (score > highestScore) {
        highestScore = score;
        bestAccount = acc;
        bestNameRes = nRes;
        bestPhoneRes = pRes;
      }
    }

    bestAccount ??= accounts.first;
    if (bestNameRes == null || bestPhoneRes == null) {
      bestNameRes = validateRecipientName(
        rawLines: rawLines,
        rawText: rawText,
        expectedRecipient: bestAccount['name'] ?? '',
      );
      bestPhoneRes = validatePhoneNumber(
        rawText: rawText,
        expectedPhone: bestAccount['phone'] ?? '',
        rawPhone: rawPhone,
      );
    }

    String? nameError;
    String? phoneError;
    if (perfectMatchAccount == null) {
      if (bestNameRes['valid'] != true) {
        nameError = 'Recipient name does not match.';
      }
      if (bestPhoneRes['valid'] != true) {
        phoneError = 'Phone number does not match recipient number.';
      }
    }

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
      'recipientName': nameError,
      'phone': phoneError,
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

  /// Dynamic lookup of owner GCash accounts from Firebase (reads properties/<ownerUid> and users/<ownerUid>)
  static Future<List<Map<String, String>>> fetchOwnerGCashAccounts({
    required String? ownerUid,
    Map? fallbackPropertyData,
  }) async {
    final List<Map<String, String>> accounts = [];

    void addAccount(dynamic name, dynamic phone) {
      final n = name?.toString().trim() ?? '';
      final p = phone?.toString().trim() ?? '';
      if (n.isNotEmpty || p.isNotEmpty) {
        final already = accounts.any((a) => a['name']?.toLowerCase() == n.toLowerCase() && a['phone'] == p);
        if (!already) {
          accounts.add({'name': n, 'phone': p});
        }
      }
    }

    if (ownerUid != null && ownerUid.trim().isNotEmpty) {
      try {
        final db = FirebaseDatabase.instance.ref();
        // 1. Fetch fresh property profile from properties/<ownerUid>
        final propSnap = await db.child('properties/$ownerUid').get();
        if (propSnap.exists && propSnap.value is Map) {
          final propVal = Map<String, dynamic>.from(propSnap.value as Map);
          addAccount(propVal['gcashName'], propVal['gcashNumber']);

          // Check if owner has multiple accounts under gcashAccounts (list or map)
          if (propVal['gcashAccounts'] != null) {
            final accs = propVal['gcashAccounts'];
            if (accs is List) {
              for (final it in accs) {
                if (it is Map) addAccount(it['name'] ?? it['gcashName'], it['phone'] ?? it['number'] ?? it['gcashNumber']);
              }
            } else if (accs is Map) {
              for (final it in accs.values) {
                if (it is Map) addAccount(it['name'] ?? it['gcashName'], it['phone'] ?? it['number'] ?? it['gcashNumber']);
              }
            }
          }
        }

        // 2. Fetch fresh user profile from users/<ownerUid>
        final userSnap = await db.child('users/$ownerUid').get();
        if (userSnap.exists && userSnap.value is Map) {
          final userVal = Map<String, dynamic>.from(userSnap.value as Map);
          addAccount(userVal['gcashName'], userVal['gcashNumber']);
          if (userVal['gcashAccounts'] != null) {
            final accs = userVal['gcashAccounts'];
            if (accs is List) {
              for (final it in accs) {
                if (it is Map) addAccount(it['name'] ?? it['gcashName'], it['phone'] ?? it['number'] ?? it['gcashNumber']);
              }
            } else if (accs is Map) {
              for (final it in accs.values) {
                if (it is Map) addAccount(it['name'] ?? it['gcashName'], it['phone'] ?? it['number'] ?? it['gcashNumber']);
              }
            }
          }
        }
      } catch (e) {
        debugPrint("Error fetching dynamic owner GCash accounts: $e");
      }
    }

    // 3. Fallback to passed-in propertyData if Firebase returned empty
    if (accounts.isEmpty && fallbackPropertyData != null) {
      addAccount(fallbackPropertyData['gcashName'], fallbackPropertyData['gcashNumber']);
    }

    return accounts;
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

      // 1. First look for standard 0000 000 000000 pattern anchored to Ref No
      final refFormattedMatch = RegExp(r'Ref[\s\.]*No[\.\s:]*(\d{4}\s+\d{3}\s+\d{6})\b', caseSensitive: false).firstMatch(fullText);
      if (refFormattedMatch != null) {
        referenceNumber = refFormattedMatch.group(1)!.replaceAll(RegExp(r'\D'), '');
      }

      // 2. Line-by-line inspection: extract strictly the digits before the date on the Ref No line
      if (referenceNumber == null || referenceNumber.length < 13) {
        for (int i = 0; i < allLines.length; i++) {
          final line = allLines[i];
          final m = RegExp(r'Ref[\s\.]*No[\.\s:]*(.+)', caseSensitive: false).firstMatch(line);
          if (m != null) {
            final afterLabel = m.group(1)!.trim();
            final beforeDate = afterLabel.split(RegExp(r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b', caseSensitive: false))[0];
            final mGrp = RegExp(r'\b\d{4}\s+\d{3}\s+\d{6}\b').firstMatch(beforeDate);
            if (mGrp != null) {
              referenceNumber = mGrp.group(0)!.replaceAll(RegExp(r'\D'), '');
              break;
            }
            final digits = beforeDate.replaceAll(RegExp(r'\D'), '');
            if (digits.isNotEmpty) {
              referenceNumber = digits; // Do NOT borrow from next line or date!
              break;
            }
          }
        }
      }

      // 3. Fallback: exact 4 3 6 grouped pattern anywhere in text
      if (referenceNumber == null || referenceNumber.length < 13) {
        final matchGrouped = RegExp(r'\b(\d{4})\s+(\d{3})\s+(\d{6})\b').firstMatch(fullText);
        if (matchGrouped != null) {
          referenceNumber = '${matchGrouped.group(1)}${matchGrouped.group(2)}${matchGrouped.group(3)}';
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

  /// Calculates a SHA-256 hash string for an ID number, or falls back to name.
  static String? computeIdHash({
    String? idNumber,
    required String firstName,
    required String lastName,
    String? dob,
  }) {
    if (idNumber != null && idNumber.trim().isNotEmpty) {
      final clean = idNumber.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
      if (clean.length >= 5) {
        return _sha256Hex(clean);
      }
    }

    return computeNameHash(firstName: firstName, lastName: lastName);
  }

  /// Calculates a SHA-256 hash string strictly for normalized First Name + Last Name.
  static String? computeNameHash({
    required String firstName,
    required String lastName,
  }) {
    final fn = firstName.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    final ln = lastName.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    if (fn.isNotEmpty && ln.isNotEmpty) {
      return _sha256Hex('${fn}_$ln');
    }
    return null;
  }

  static void import_crypto() {}

  static String _sha256Hex(String input) {
    // SHA-256 implementation using dart:convert & crypto
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
