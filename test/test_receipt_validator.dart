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
    'THOMAS JOHN A',
    'T*o*a* *oh* A',
    'Th***s J**n A',
    'Sent to: Th***s J**n A.',
  ];

  for (final ex in namePassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr(ex),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    expect(res['isValid'], isTrue, reason: 'Expected PASS for "$ex", got ${res['errors']}');
    print('PASS (Name): "$ex" -> Valid');
  }

  // 1a. Names with hyphen, apostrophe, and ñ
  final specialNamesPass = [
    {'expected': 'Ma. Cristina D.', 'cand': 'Ma. Cr*****a D.'},
    {'expected': 'Ma. Cristina D.', 'cand': 'Ma. Cristina D.'},
    {'expected': 'Jose Dela Cruz Jr.', 'cand': 'J**e D**a C**z J*.'},
    {'expected': 'Jose Dela-Cruz Jr.', 'cand': 'J**e D**a-C**z J*.'},
    {'expected': 'Niño P.', 'cand': 'N**o P.'},
    {'expected': 'Niño P.', 'cand': 'Niño P.'},
    {'expected': 'Niño P.', 'cand': 'Nino P.'},
    {'expected': "D'Angelo M.", 'cand': "D'An***o M."},
  ];

  for (final pair in specialNamesPass) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr(pair['cand']!),
      expectedAmount: expectedAmount,
      expectedRecipient: pair['expected']!,
    );
    expect(res['isValid'], isTrue, reason: "Expected PASS for ${pair['expected']} vs ${pair['cand']}, got ${res['errors']}");
    print("PASS (Special Name): ${pair['expected']} vs ${pair['cand']} -> Valid");
  }

  // 1b. Recipient Name FLAG examples
  final nameFlagExamples = [
    'Th**s J**n A.',
    'Th***s J*n A.',
    'Th***s J**n',
    '*h***s J**n A.',
    'Xh***s J**n A.',
    'Th***s J**n B.',
    '',
  ];

  for (final ex in nameFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr(ex),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    if (res['isValid']) {
      print('FAIL: Expected FLAG for "$ex", but passed!');
      fail('Expected name to fail for $ex');
    } else {
      expect((res['errors'] as List).first, 'Recipient name does not match.');
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
    expect(res['isValid'], isTrue, reason: 'Expected PASS for amount $amt');
    print('PASS (Amount): "$amt" -> Valid');
  }

  final amountFlagExamples = ['₱100', '₱100.0', '₱100 00', '₱100.000', '₱100,00', '₱abc.00'];
  for (final amt in amountFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', amt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    expect(res['isValid'], isFalse, reason: 'Expected FLAG for amount $amt');
    expect((res['errors'] as List).first, 'The amount on the receipt is incorrect or has been altered.');
    print('FLAG (Amount): "$amt" -> ${(res['errors'] as List).first}');
  }

  // 3. Reference Number tests
  final refPassExamples = ['0000 000 000000', '1234 567 890123'];
  for (final ref in refPassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', ref),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    expect(res['isValid'], isTrue, reason: 'Expected PASS for ref $ref');
    print('PASS (Ref): "$ref" -> Valid');
  }

  final refFlagExamples = ['0000000000000', '0000 0000 00000', '000 000 000000', '1234 56a 890123'];
  for (final ref in refFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', ref),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    expect(res['isValid'], isFalse, reason: 'Expected FLAG for ref $ref');
    expect((res['errors'] as List).first, 'The reference number is invalid or has already been used.');
    print('FLAG (Ref): "$ref" -> ${(res['errors'] as List).first}');
  }

  // 4. Date and Time tests
  final datePassExamples = ['Oct 13, 2026 12:10 PM', 'Jan 01, 2025 1:00 AM', 'Feb 28, 2024 11:59 PM'];
  for (final dt in datePassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', validRef, dt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    expect(res['isValid'], isTrue, reason: 'Expected PASS for date $dt');
    print('PASS (Date): "$dt" -> Valid');
  }

  final dateFlagExamples = ['Oct 13 2026 12:10', 'Feb 31, 2026 12:10 PM', 'Oct 13, 2026 13:75 PM', '13/10/2026 12:10 PM'];
  for (final dt in dateFlagExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', validRef, dt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    expect(res['isValid'], isFalse, reason: 'Expected FLAG for date $dt');
    expect((res['errors'] as List).first, 'The date and time on the receipt appear to be altered or invalid.');
    print('FLAG (Date): "$dt" -> ${(res['errors'] as List).first}');
  }

  // 5. Unreadable fields test
  final unreadableRes = AiService.validateGCashReceipt(
    ocrData: {
      'raw_lines': ['Thomas John A.'],
      'extracted_text': 'Thomas John A.',
      'raw_amount': '',
      'raw_reference': '',
      'raw_date': '',
    },
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
  );
  expect(unreadableRes['isValid'], isFalse);
  final unreadableErrors = unreadableRes['errors'] as List<String>;
  expect(unreadableErrors, contains("We couldn't read the receipt clearly. Please upload a clearer screenshot."));

  // 6. Checklist Tests: Each field tested independently with ONE intentional error
  const expPhone = '09171234567';
  Map<String, dynamic> makeChecklistOcr({
    String name = 'Thomas John A.',
    String amt = '₱100.00',
    String ref = '0000 000 000000',
    String dt = 'Oct 13, 2026 12:10 PM',
    String phone = '09171234567',
  }) {
    return {
      'raw_lines': [name, phone, 'Amount $amt', 'Ref No. $ref', dt],
      'extracted_text': '$name\n$phone\nAmount: $amt\nRef No. $ref\n$dt',
      'raw_amount': amt,
      'raw_reference': ref,
      'raw_date': dt,
      'phone': phone,
    };
  }

  // 6.1 Wrong Price only -> only Wrong Price error
  final wrongPriceOnly = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(amt: '₱200.00'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(wrongPriceOnly['isValid'], isFalse);
  expect(wrongPriceOnly['errors'], ['The amount on the receipt is incorrect or has been altered.']);

  // 6.2 Wrong Phone only -> only Wrong Phone error
  final wrongPhoneOnly = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(phone: '09189999999'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(wrongPhoneOnly['isValid'], isFalse);
  expect(wrongPhoneOnly['errors'], ['Phone number does not match recipient number.']);

  // 6.3 Wrong Date/Time only -> only Wrong Date/Time error
  final wrongDateOnly = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(dt: 'Oct 13 2026 12:10'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(wrongDateOnly['isValid'], isFalse);
  expect(wrongDateOnly['errors'], ['The date and time on the receipt appear to be altered or invalid.']);

  // 6.4 Wrong Reference only -> only Wrong Reference error
  final wrongRefOnly = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(ref: '00000000000000'), // 14 digits
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(wrongRefOnly['isValid'], isFalse);
  expect(wrongRefOnly['errors'], ['The reference number is invalid or has already been used.']);

  // 6.5 Wrong Recipient Name only -> only Wrong Recipient Name error
  final wrongNameOnly = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(name: 'Pedro Penduko'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(wrongNameOnly['isValid'], isFalse);
  expect(wrongNameOnly['errors'], ['Recipient name does not match.']);

  // 6.6 100% correct receipt -> Verified (isValid == true, empty errors)
  final perfectReceipt = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(perfectReceipt['isValid'], isTrue);
  expect(perfectReceipt['errors'], isEmpty);

  // 6.7 Receipt with two wrong fields (Price + Date) -> exactly those two errors
  final twoErrorsRes = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(amt: '₱500.00', dt: 'Invalid Date'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(twoErrorsRes['isValid'], isFalse);
  expect(twoErrorsRes['errors'], [
    'The amount on the receipt is incorrect or has been altered.',
    'The date and time on the receipt appear to be altered or invalid.',
  ]);

  print('All checklist tests passed: isolated field error mappings verified.');
  });
}
