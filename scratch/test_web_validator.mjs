import { validateGCashReceipt } from '../website/src/utils/receiptValidator.js';

const expectedName = 'Thomas John A.';
const expectedAmount = 100.00;
const validRef = '0000 000 000000';
const validDate = 'Oct 13, 2026 12:10 PM';

function makeOcr(name, amt = '₱100.00', ref = validRef, date = validDate, phone = '') {
  return {
    raw_lines: [name],
    extracted_text: `${name}\nAmount: ${amt}\nRef No. ${ref}\n${date}`,
    raw_amount: amt,
    raw_reference: ref,
    raw_date: date,
    phone: phone,
  };
}

const specialNamesPass = [
  { expected: 'Ma. Cristina D.', cand: 'Ma. Cr*****a D.' },
  { expected: 'Ma. Cristina D.', cand: 'Ma. Cristina D.' },
  { expected: 'Jose Dela Cruz Jr.', cand: 'J**e D**a C**z J*.' },
  { expected: 'Jose Dela-Cruz Jr.', cand: 'J**e D**a-C**z J*.' },
  { expected: 'Niño P.', cand: 'N**o P.' },
  { expected: 'Niño P.', cand: 'Niño P.' },
  { expected: 'Niño P.', cand: 'Nino P.' },
  { expected: "D'Angelo M.", cand: "D'An***o M." },
  { expected: 'JOHN JASON L.', cand: 'JO•N JA••N L.' },
  { expected: 'JOHN JASON L.', cand: 'JO.N JA..N L.' },
  { expected: 'JOHN JASON L.', cand: 'JO-N JA NL:' },
  { expected: 'Keisha Mae Brosas', cand: 'KE•••A M•• B.' },
  { expected: 'Keisha Mae B.', cand: 'KE•••A M•• B.' },
  { expected: 'KEISHA MAY B.', cand: 'KE•••A M•• B.' },
  { expected: 'Justine Aguila', cand: 'JU••••E A••••A' },
  { expected: 'Justine Aguila', cand: 'JU•••NE A•••LA' },
  { expected: 'Justine Aguila', cand: 'JUSTINE AGUILA' },
];

let failed = 0;
for (const pair of specialNamesPass) {
  const res = validateGCashReceipt({
    ocrData: makeOcr(pair.cand),
    expectedAmount: expectedAmount,
    expectedRecipient: pair.expected,
  });
  if (!res.isValid) {
    console.error(`FAIL: Expected PASS for "${pair.expected}" vs cand "${pair.cand}", got errors:`, res.errors);
    failed++;
  } else {
    console.log(`PASS: "${pair.expected}" vs cand "${pair.cand}"`);
  }
}

// Test with phone numbers and QR receipts
const qrTest = validateGCashReceipt({
  ocrData: makeOcr('JU•••NE A•••LA', '₱100.00', '1234 567 890123', validDate, ''),
  expectedAmount: 100,
  expectedRecipient: 'Justine Aguila',
  expectedPhone: '09551280430',
});
if (!qrTest.isValid) {
  console.error('FAIL QR test:', qrTest.errors);
  failed++;
} else {
  console.log('PASS QR receipt without phone (name matched)');
}

// Test masked phone match
const phoneMatchTest = validateGCashReceipt({
  ocrData: {
    raw_lines: ['JU•••NE A•••LA', '0955 ••• 0430'],
    extracted_text: 'JU•••NE A•••LA\n0955 ••• 0430\nAmount: ₱100.00\nRef No. 1234 567 890123\nOct 13, 2026',
    raw_amount: '₱100.00',
    raw_reference: '1234 567 890123',
    raw_date: 'Oct 13, 2026',
    phone: '0955 ••• 0430'
  },
  expectedAmount: 100,
  expectedRecipient: 'Justine Aguila',
  expectedPhone: '09551280430',
});
if (!phoneMatchTest.isValid) {
  console.error('FAIL Masked Phone test:', phoneMatchTest.errors);
  failed++;
} else {
  console.log('PASS Masked Phone test');
}

console.log(`\nTotal failures: ${failed}`);


// Test missing phone cases for KEISHA MAY B.
const missingPhoneCases = [
  '0947 •• 4967',
  '0947 • 4967',
  '0947 4967',
  '0947 ••• 49',
  '0947 •••',
  '0947 455',
  '0947',
  '0947 •••• 4967',
  '0999 ••• 9999',
];

for (const cand of missingPhoneCases) {
  const res = validateGCashReceipt({
    ocrData: {
      raw_lines: ['Express Send', 'KE•••A M•• B.', cand],
      extracted_text: `Express Send\nKE•••A M•• B.\n${cand}\nAmount: ₱1.00\nRef No. 8046 439 672663\nOct 13, 2026`,
      raw_amount: '1.00',
      raw_reference: '8046 439 672663',
      raw_date: 'Oct 13, 2026',
    },
    expectedAmount: 1.00,
    expectedRecipient: 'KEISHA MAY B.',
    expectedPhone: '09474554967',
  });
  if (res.isValid) {
    console.error(`FAIL: Expected missing phone "${cand}" to fail, but passed!`);
    failed++;
  } else {
    console.log(`PASS: Missing phone "${cand}" correctly flagged: ${res.errors}`);
  }
}

// Test Express Send with no phone line
const noPhoneExpressRes = validateGCashReceipt({
  ocrData: {
    raw_lines: ['Express Send', 'KE•••A M•• B.'],
    extracted_text: 'Express Send\nKE•••A M•• B.\nAmount: ₱1.00\nRef No. 8046 439 672663\nOct 13, 2026',
    raw_amount: '1.00',
    raw_reference: '8046 439 672663',
    raw_date: 'Oct 13, 2026',
  },
  expectedAmount: 1.00,
  expectedRecipient: 'KEISHA MAY B.',
  expectedPhone: '09474554967',
});
if (noPhoneExpressRes.isValid) {
  console.error('FAIL: Expected Express Send without phone to fail, but passed!');
  failed++;
} else {
  console.log('PASS: Express Send without phone correctly flagged');
}
