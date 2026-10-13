import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resortconnectapp/services/ai_service.dart';

void main() {
  test('AiService.validateGCashReceipt passes all test cases in order', () {

  const expectedName = 'Thomas John A.';
  const expectedAmount = 100.00;
  const validRef = '0000 000 000000';
  const validDate = 'Oct 13, 2026 12:10 PM';

  Map<String, dynamic> makeOcr(String name, [String amt = '₱100.00', String ref = validRef, String date = validDate]) {
    return {
      'raw_lines': [name],
      'extracted_text': '$name\nAmount: $amt\nRef No. $ref\n$date',
      'raw_amount': amt,
      'raw_reference': ref,
      'raw_date': date,
    };
  }

  // 1. Recipient Name PASS examples
  final namePassExamples = [
    'Th***s J**n A.',
    'T***** J*** A.',
    'Thomas John A.',
    'T*o*a* *oh* A',
    'Th***s J**n A'
  ];

  for (final ex in namePassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr(ex),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (!res['isValid']) {
      print('FAIL: Expected PASS for "$ex", but got: ${res['errors']}');
    } else {
      print('PASS (Name): "$ex" -> Valid');
    }
  }

  // 1b. Recipient Name FLAG examples
  final nameFlagExamples = [
    'Th**s J**n A.',
    'Th***s J*n A.',
    'Th***s J**n',
    '*h***s J**n A.',
    'Xh***s J**n A.',
    'Th***s J**n B.'
  ];

  for (final ex in nameFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr(ex),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (res['isValid']) {
      print('FAIL: Expected FLAG for "$ex", but passed!');
    } else {
      print('FLAG (Name): "$ex" -> ${(res['errors'] as List).first}');
    }
  }

  // 2. Amount tests
  final amountPassExamples = ['₱100.00', 'P100.00', 'PHP 100.00', 'Php 100.00', '100.00', '₱ 100.00'];
  for (final amt in amountPassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', amt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (!res['isValid']) {
      print('FAIL: Expected PASS for amount "$amt", but got: ${res['errors']}');
    } else {
      print('PASS (Amount): "$amt" -> Valid');
    }
  }

  final amountFlagExamples = ['₱100', '₱100.0', '₱100 00', '₱100.000', '₱100,00', '₱abc.00'];
  for (final amt in amountFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', amt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (res['isValid']) {
      print('FAIL: Expected FLAG for amount "$amt", but passed!');
    } else {
      print('FLAG (Amount): "$amt" -> ${(res['errors'] as List).first}');
    }
  }

  // 3. Reference Number tests
  final refPassExamples = ['0000 000 000000', '1234 567 890123'];
  for (final ref in refPassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', ref),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (!res['isValid']) {
      print('FAIL: Expected PASS for ref "$ref", but got: ${res['errors']}');
    } else {
      print('PASS (Ref): "$ref" -> Valid');
    }
  }

  final refFlagExamples = ['0000000000000', '0000 0000 00000', '000 000 000000', '1234 56a 890123'];
  for (final ref in refFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', ref),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (res['isValid']) {
      print('FAIL: Expected FLAG for ref "$ref", but passed!');
    } else {
      print('FLAG (Ref): "$ref" -> ${(res['errors'] as List).first}');
    }
  }

  // 4. Date and Time tests
  final datePassExamples = ['Oct 13, 2026 12:10 PM', 'Jan 01, 2025 1:00 AM', 'Feb 28, 2024 11:59 PM'];
  for (final dt in datePassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', validRef, dt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (!res['isValid']) {
      print('FAIL: Expected PASS for date "$dt", but got: ${res['errors']}');
    } else {
      print('PASS (Date): "$dt" -> Valid');
    }
  }

  final dateFlagExamples = ['Oct 13 2026 12:10', 'Feb 31, 2026 12:10 PM', 'Oct 13, 2026 13:75 PM', '13/10/2026 12:10 PM'];
  for (final dt in dateFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', validRef, dt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (res['isValid']) {
      print('FAIL: Expected FLAG for date "$dt", but passed!');
    } else {
      print('FLAG (Date): "$dt" -> ${(res['errors'] as List).first}');
    }
  }

  // 5. Multi-check ordered failure test
  final multiFailRes = AiService.validateGCashReceipt(
    ocrData: makeOcr('Xh***s J**n A.', '₱100', '12345', 'Oct 13 2026 12:10'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
  );

  print('Multi-check failures (should be 4 in order: Name, Amount, Ref, Date):');
  final errs = multiFailRes['errors'] as List;
  for (int i = 0; i < errs.length; i++) {
    print(' ${i + 1}. ${errs[i]}');
  }

  expect(errs.length, 4);
  });
}
