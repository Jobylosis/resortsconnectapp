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
    {'expected': 'JOHN JASON L.', 'cand': 'JO•N JA••N L.'},
    {'expected': 'JOHN JASON L.', 'cand': 'JO.N JA..N L.'},
    {'expected': 'JOHN JASON L.', 'cand': 'JO-N JA NL:'},
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

  // 1b. Recipient Name FLAG examples (genuinely wrong names)
  final nameFlagExamples = [
    'Th***s J**n',     // Missing last initial/word
    '*h***s J**n A.',  // Masked first letter (illegal in GCash)
    'Xh***s J**n A.',  // Wrong first letter
    'Th***s J**n B.',  // Wrong last initial
    'Pedro Penduko',   // Entirely different name
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

  // 4. Date and Time tests (Date constraint removed - always passes)
  final datePassExamples = [
    'Oct 13, 2026 12:10 PM',
    'Oct 13, 2026 12:18 PM',
    'Oct 12, 2026 1:00 PM',
    'Jan 01, 2025 1:00 AM',
    'Oct 13 2026 12:10',
    'Feb 31, 2026 12:10 PM',
  ];
  for (final dt in datePassExamples) {
    final res = AiService.validateGCashReceipt(
      ocrData: makeOcr('Thomas John A.', '₱100.00', validRef, dt),
      expectedAmount: expectedAmount,
      expectedRecipient: expectedName,
    );
    expect(res['isValid'], isTrue, reason: 'Expected PASS for date $dt');
    print('PASS (Date - constraint removed): "$dt" -> Valid');
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

  // 6.3 Date/Time does not block validation (date constraint removed)
  final wrongDateOnly = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(dt: 'Oct 13 2026 12:10'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(wrongDateOnly['isValid'], isTrue);

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

  // 6.7 Receipt with two wrong fields (Price + Phone) -> exactly those two errors
  final twoErrorsRes = AiService.validateGCashReceipt(
    ocrData: makeChecklistOcr(amt: '₱500.00', phone: '09999999999'),
    expectedAmount: expectedAmount,
    expectedRecipient: expectedName,
    expectedPhone: expPhone,
  );
  expect(twoErrorsRes['isValid'], isFalse);
  expect(twoErrorsRes['errors'], [
    'Phone number does not match recipient number.',
    'The amount on the receipt is incorrect or has been altered.',
  ]);

  // 8. Real Receipt Test Case from User Request
  // Layout, top to bottom:
  // - "KE•••A M•• B." (masked with bullets)
  // - "+63 947 455 4967"
  // - "Sent via GCash"
  // - "Amount 1.00"
  // - "Total Amount Sent ₱1.00"
  // - "Ref No. 8046 069 534857   Oct 13, 2026 12:18 PM" (SAME HORIZONTAL LINE)
  // - "279g (gCO2e) By going digital..."
  const realExpName = 'KE•••A M•• B.';
  const realExpPhone = '+63 947 455 4967';
  const realExpAmount = 1.00;

  Map<String, dynamic> makeRealOcr({
    String name = 'KE•••A M•• B.',
    String phone = '+63 947 455 4967',
    String amtRow = 'Amount 1.00',
    String totalRow = 'Total Amount Sent ₱1.00',
    String refDateRow = 'Ref No. 8046 069 534857 Oct 13, 2026 12:18 PM',
    String? rawAmt,
    String? rawRef,
    String? rawDate,
  }) {
    final rawLines = [
      name,
      phone,
      'Sent via GCash',
      amtRow,
      totalRow,
      refDateRow,
      '279g (gCO2e) By going digital, you reduce your carbon footprint from transportation, paper, and plastic.',
    ];
    final rawText = rawLines.join('\n');
    return {
      'raw_lines': rawLines,
      'extracted_text': rawText,
      'raw_amount': rawAmt ?? (totalRow.contains('₱') ? totalRow.split('Sent ')[1].trim() : amtRow.split('Amount ')[1].trim()),
      'raw_reference': rawRef ?? '8046 069 534857',
      'raw_date': rawDate ?? 'Oct 13, 2026 12:18 PM',
      'phone': phone,
    };
  }

  // 8.1 100% correct real receipt -> Verified, zero errors
  final realRes = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(),
    expectedAmount: realExpAmount,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realRes['isValid'], isTrue, reason: 'Expected real receipt to be Verified with 0 errors, got: ${realRes['errors']}');
  expect(realRes['errors'], isEmpty);

  // 8.1b Also test with expected recipient stored as full name "KELVIA MAE B." (where letters match K-E-...-A, M-a-e, B)
  final realWithFullNameRes = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(),
    expectedAmount: realExpAmount,
    expectedRecipient: 'KELVIA MAE B.',
    expectedPhone: realExpPhone,
  );
  expect(realWithFullNameRes['isValid'], isTrue, reason: 'Expected real receipt against matching full name KELVIA MAE B. to pass, got: ${realWithFullNameRes['errors']}');

  // 8.2 Real receipt with Wrong Price only -> only Wrong Price
  final realWrongPrice = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(amtRow: 'Amount 50.00', totalRow: 'Total Amount Sent ₱50.00'),
    expectedAmount: realExpAmount,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realWrongPrice['isValid'], isFalse);
  expect(realWrongPrice['errors'], ['The amount on the receipt is incorrect or has been altered.']);

  // 8.3 Real receipt with Wrong Phone only -> only Wrong Phone Number
  final realWrongPhone = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(phone: '+63 912 345 6789'),
    expectedAmount: realExpAmount,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realWrongPhone['isValid'], isFalse);
  expect(realWrongPhone['errors'], ['Phone number does not match recipient number.']);

  // 8.4 Real receipt with different Date/Time -> Passes (date constraint removed)
  final realAlteredDate = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(
      refDateRow: 'Ref No. 8046 069 534857 2026-10-13 12:18:00',
      rawDate: '2026-10-13 12:18:00',
    ),
    expectedAmount: realExpAmount,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realAlteredDate['isValid'], isTrue);

  // 8.5 Real receipt with Wrong Reference only -> only Wrong Reference
  final realWrongRef = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(
      refDateRow: 'Ref No. 9999 999 9999999 Oct 13, 2026 12:18 PM', // 14 digits
      rawRef: '9999 999 9999999',
    ),
    expectedAmount: realExpAmount,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realWrongRef['isValid'], isFalse);
  expect(realWrongRef['errors'], ['The reference number is invalid or has already been used.']);

  // 8.6 Real receipt with Wrong Recipient Name only -> only Wrong Recipient Name
  final realWrongName = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(name: 'JO•••N D•• C.'),
    expectedAmount: realExpAmount,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realWrongName['isValid'], isFalse);
  expect(realWrongName['errors'], ['Recipient name does not match.']);

  // 8.7 Real receipt with Two wrong fields (Phone + Amount) -> exactly those two errors
  final realTwoWrong = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(
      amtRow: 'Amount 99.00',
      totalRow: 'Total Amount Sent ₱99.00',
      phone: '+63 999 999 9999',
    ),
    expectedAmount: realExpAmount,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realTwoWrong['isValid'], isFalse);
  expect(realTwoWrong['errors'], [
    'Phone number does not match recipient number.',
    'The amount on the receipt is incorrect or has been altered.',
  ]);

  // 8.8 Dynamic Owner GCash Account: Owner with two accounts (A & B)
  final ownerAccountA = {'name': 'KE•••A M•• B.', 'phone': '+63 947 455 4967'};
  final ownerAccountB = {'name': 'Mark John A.', 'phone': '09123456789'};
  final multiAccounts = [ownerAccountA, ownerAccountB];

  // Receipt sent to account A -> Passes
  final multiAccARes = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(),
    expectedAmount: realExpAmount,
    expectedAccounts: multiAccounts,
  );
  expect(multiAccARes['isValid'], isTrue);
  expect(multiAccARes['errors'], isEmpty);

  // Receipt sent to account B -> Passes against Account B
  final ocrForAccountB = {
    'reference_number': '8046 069 534857',
    'amount': '1.00',
    'date': 'Oct 13, 2026 12:18 PM',
    'phone': '09123456789',
    'raw_lines': [
      'Mark John A.',
      '09123456789',
      'Sent via GCash',
      'Amount 1.00',
      'Total Amount Sent ₱1.00',
      'Ref No. 8046 069 534857 Oct 13, 2026 12:18 PM',
    ],
    'extracted_text': 'Mark John A.\n09123456789\nSent via GCash\nAmount 1.00\nTotal Amount Sent ₱1.00\nRef No. 8046 069 534857 Oct 13, 2026 12:18 PM',
  };
  final multiAccBRes = AiService.validateGCashReceipt(
    ocrData: ocrForAccountB,
    expectedAmount: realExpAmount,
    expectedAccounts: multiAccounts,
  );
  expect(multiAccBRes['isValid'], isTrue);
  expect(multiAccBRes['errors'], isEmpty);

  // Mixing name of Account A with phone of Account B -> FAILS (must be matched as a pair!)
  final mixedAccountReceipt = {
    'reference_number': '8046 069 534857',
    'amount': '1.00',
    'date': 'Oct 13, 2026 12:18 PM',
    'phone': '09123456789', // phone from B
    'raw_lines': [
      'KE•••A M•• B.', // name from A
      '09123456789',
      'Sent via GCash',
      'Amount 1.00',
      'Total Amount Sent ₱1.00',
      'Ref No. 8046 069 534857 Oct 13, 2026 12:18 PM',
    ],
    'extracted_text': 'KE•••A M•• B.\n09123456789\nSent via GCash\nAmount 1.00\nTotal Amount Sent ₱1.00\nRef No. 8046 069 534857 Oct 13, 2026 12:18 PM',
  };
  final mixedRes = AiService.validateGCashReceipt(
    ocrData: mixedAccountReceipt,
    expectedAmount: realExpAmount,
    expectedAccounts: multiAccounts,
  );
  expect(mixedRes['isValid'], isFalse);
  // 8.9 Expected Amount tests: Full Payment (1.00) vs 30% Downpayment (0.30)
  // Case A: Real receipt (1.00) with Full Payment (1.00 expected) -> 100% VALID, 0 errors
  final realFullPayment = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(),
    expectedAmount: 1.00,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realFullPayment['isValid'], isTrue);
  expect(realFullPayment['errors'], isEmpty);

  // Case B: Real receipt (1.00) with 30% Downpayment (0.30 expected) -> FLAGGED ONLY FOR AMOUNT
  final realDownpaymentMismatch = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(),
    expectedAmount: 0.30,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realDownpaymentMismatch['isValid'], isFalse);
  expect(realDownpaymentMismatch['errors'], ['The amount on the receipt is incorrect or has been altered.']);

  // Case C: Real receipt with 0.30 paid with 30% Downpayment (0.30 expected) -> 100% VALID, 0 errors
  final realDownpaymentMatch = AiService.validateGCashReceipt(
    ocrData: makeRealOcr(amtRow: 'Amount 0.30', totalRow: 'Total Amount Sent ₱0.30', rawAmt: '0.30'),
    expectedAmount: 0.30,
    expectedRecipient: realExpName,
    expectedPhone: realExpPhone,
  );
  expect(realDownpaymentMatch['isValid'], isTrue);
  expect(realDownpaymentMatch['errors'], isEmpty);

  print('All real receipt tests passed: 100% verified with zero errors and isolated error mapping!');
  });
}
