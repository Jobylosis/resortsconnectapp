/**
 * Shared GCash Receipt Strict Validator for Website (React)
 * Checks 5 points independently with isolated validators:
 * (1) Recipient Name: validateRecipientName
 * (2) Phone Number: validatePhoneNumber
 * (3) Amount: validateAmount
 * (4) Reference Number: validateReference
 * (5) Date and Time: validateDateTime
 */

// Helper: Strip diacritics / accents (e.g. ñ -> n, é -> e)
function stripAccents(str) {
  if (!str) return '';
  return str.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/ñ/gi, 'n');
}

// Helper: Normalize mask characters: • ● ○ ◦ · ∙ ⦿ ⦾ ◉ ⬤ * ∗ ✱ ✲ \ - _ (each counts as 1 hidden character)
function normalizeMaskChars(str) {
  return (str || '').replace(/[•●○◦·∙⦿⦾◉⬤*∗✱✲\-_]/g, '*');
}

/**
 * 1. Isolated Recipient Name Validator
 */
export function validateRecipientName({ rawLines, rawText, expectedRecipient }) {
  const expNameClean = (expectedRecipient || '').trim().replace(/\s+/g, ' ');
  if (!expNameClean) {
    return { valid: true, error: null };
  }

  const normExpName = stripAccents(expNameClean).toLowerCase();
  const rawExpWords = expNameClean.split(' ').filter(w => w.length > 0);
  const expWords = rawExpWords.map(w => stripAccents(w.replace(/\.+$/, '')).toLowerCase());
  const numWords = expWords.length;

  const lines = Array.isArray(rawLines) && rawLines.length > 0
    ? rawLines.map(l => String(l))
    : String(rawText || '').split('\n');

  let namePassed = false;
  const candidateWordLists = [];

  for (const line of lines) {
    const trimmed = line.trim().replace(/\s+/g, ' ');
    if (!trimmed) continue;

    const normLine = stripAccents(trimmed).toLowerCase();
    const normExpNoDots = expWords.join(' ');
    if (normLine === normExpName || normLine === normExpNoDots || normLine.includes(normExpName) || normLine.includes(normExpNoDots)) {
      namePassed = true;
      break;
    }

    const tokens = trimmed.split(' ').filter(w => w.length > 0);
    if (tokens.length === numWords) {
      candidateWordLists.push(tokens);
    } else if (tokens.length > numWords) {
      for (let i = 0; i <= tokens.length - numWords; i++) {
        candidateWordLists.push(tokens.slice(i, i + numWords));
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
    function gcashWordMatch(candW, expW) {
      if (!candW && !expW) return true;
      if (!candW || !expW) return false;

      const normCandW = normalizeMaskChars(candW).toLowerCase();
      const normExpW = normalizeMaskChars(expW).toLowerCase();

      // For very short words (1-2 chars)
      if (normExpW.length <= 2) {
        const candStripped = normCandW.replace(/\.+$/, '');
        const expStripped = normExpW.replace(/\.+$/, '');
        if (candStripped === expStripped) return true;
        // Allow masking of second char (e.g. 'j*' matching 'jr')
        if (candStripped.length === expStripped.length && candStripped[0] === expStripped[0] && candStripped.slice(1).split('').every(c => c === '*')) {
          return true;
        }
        return false;
      }

      // First character must match (GCash never masks the first char)
      if (normCandW[0] === '*' || normCandW[0] !== normExpW[0]) return false;

      // Tolerating GCash masks & EasyOCR misreading mask bullets/dots as 'o', 'e', 'u', '0':
      // Case A: The candidate word after the first letter is composed only of mask characters or OCR misread symbols (e.g. "M**", "M••", "Moo", "Mee" for "May")
      const afterFirst = normCandW.slice(1);
      if (/^[oeu0*•●○◦∙\-_]+$/.test(afterFirst)) {
        return true;
      }

      // Case B: Last visible character of candidate must match expected word's last char
      // (e.g. "KEoA" or "KE•••A" for "Keisha", last visible char 'a' == 'a')
      if (!normCandW.endsWith('*')) {
        let lastExpChar = '';
        for (let i = normExpW.length - 1; i >= 0; i--) {
          if (normExpW[i] !== '*') { lastExpChar = normExpW[i]; break; }
        }
        let lastCandChar = '';
        for (let i = normCandW.length - 1; i >= 0; i--) {
          if (normCandW[i] !== '*') { lastCandChar = normCandW[i]; break; }
        }
        if (lastExpChar && lastCandChar && lastExpChar !== lastCandChar) return false;
      }

      // Allow flexible word length (±3 chars tolerance)
      if (Math.abs(normCandW.length - normExpW.length) > 3) return false;

      return true;
    }

    for (const candRawWords of candidateWordLists) {
      let candidateMatches = true;

      const cleanedCandWords = candRawWords.map(w => {
        return stripAccents(w.replace(/^[\s,:\-;]+|[\s,:\-.;]+$/g, ''));
      });

      const firstCandWord = cleanedCandWords[0];
      const firstExpWord = expWords[0];
      if (firstCandWord.length > 0 && firstExpWord.length > 0) {
        const firstCandChar = normalizeMaskChars(firstCandWord[0]);
        const firstExpChar = normalizeMaskChars(firstExpWord[0]);
        if (firstCandChar === '*' || firstCandChar.toLowerCase() !== firstExpChar.toLowerCase()) {
          candidateMatches = false;
        }
      }

      if (candidateMatches) {
        for (let wIdx = 0; wIdx < numWords; wIdx++) {
          const expW = expWords[wIdx];
          const rawCandW = cleanedCandWords[wIdx];
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

  // OCR tolerance check (spaces merged/split)
  // Also uses GCash-aware flexible matching
  if (!namePassed) {
    const expWhole = normalizeMaskChars(expWords.join('')).toLowerCase();

    for (const line of lines) {
      const trimmed = line.trim().replace(/\s+/g, ' ');
      if (!trimmed) continue;

      const tokens = trimmed.split(' ').filter(w => w.length > 0);
      const subsets = [];
      if (tokens.length !== numWords) {
        subsets.push(tokens.join(''));
      }
      if (tokens.length > numWords) {
        for (let len = 1; len <= tokens.length; len++) {
          for (let i = 0; i <= tokens.length - len; i++) {
            subsets.push(tokens.slice(i, i + len).join(''));
          }
        }
      }

      for (const rawSubset of subsets) {
        const candClean = stripAccents(rawSubset.replace(/[\s.,:\-;]+/g, ''));
        const normCandWhole = normalizeMaskChars(candClean).toLowerCase();

        // Allow flexible length (±3 tolerance for OCR-mangled mask chars)
        if (Math.abs(normCandWhole.length - expWhole.length) > 3) continue;
        if (!normCandWhole.length) continue;
        if (normCandWhole[0] === '*' || normCandWhole[0] !== expWhole[0]) continue;

        // Check that visible chars in expected appear in roughly the right positions
        let wholeMatch = true;
        let candIdx = 0;
        let expIdx = 0;
        while (expIdx < expWhole.length && candIdx < normCandWhole.length) {
          const cExp = expWhole[expIdx];
          const cCand = normCandWhole[candIdx];
          if (cExp === '*') {
            expIdx++;
            candIdx++;
            continue;
          }
          if (cCand === '*') {
            candIdx++;
            continue;
          }
          if (cCand === cExp) {
            expIdx++;
            candIdx++;
          } else {
            candIdx++;
            if (candIdx - expIdx > 4) {
              wholeMatch = false;
              break;
            }
          }
        }
        // Check we consumed all expected visible chars
        while (expIdx < expWhole.length && expWhole[expIdx] === '*') {
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
    return { valid: false, error: 'Recipient name does not match.' };
  }
  return { valid: true, error: null };
}

/**
 * 2. Isolated Phone Number Validator
 */
export function validatePhoneNumber({ rawText, expectedPhone, rawPhone }) {
  const cleanExpDigits = String(expectedPhone || '').replace(/\D/g, '').trim();
  if (!cleanExpDigits) {
    return { valid: true, error: null };
  }

  function normalizePhone(p) {
    let d = String(p || '').replace(/\D/g, '');
    if (d.startsWith('63') && d.length === 12) {
      return '0' + d.slice(2);
    } else if (d.startsWith('9') && d.length === 10) {
      return '0' + d;
    }
    return d;
  }

  const targetPhone = normalizePhone(cleanExpDigits);

  if (rawPhone && String(rawPhone).trim()) {
    if (normalizePhone(rawPhone) === targetPhone) {
      return { valid: true, error: null };
    }
  }

  const phoneCandidateRegex = /(?:\+?63[\s-]?)?(?:0?9[\s\d*•●○⦿⦾◦·\-_]{9,16})/g;
  const matches = String(rawText || '').match(phoneCandidateRegex) || [];
  let phoneMatched = false;

  for (const cand of matches) {
    const digits = cand.replace(/\D/g, '');
    if (normalizePhone(digits) === targetPhone) {
      phoneMatched = true;
      break;
    }

    const normCand = cand.replace(/[•●○⦿⦾◦·\-_]/g, '*');
    let candClean = normCand.replace(/[\s-]/g, '');
    if (candClean.startsWith('+63')) {
      candClean = '0' + candClean.slice(3);
    } else if (candClean.startsWith('63')) {
      candClean = '0' + candClean.slice(2);
    }

    if (candClean.includes('*') && candClean.length === targetPhone.length) {
      let maskedOk = true;
      for (let i = 0; i < candClean.length; i++) {
        const cCand = candClean[i];
        const cExp = targetPhone[i];
        if (cCand !== '*' && cCand !== cExp) {
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
    return { valid: false, error: 'Phone number does not match recipient number.' };
  }
  return { valid: true, error: null };
}

/**
 * 3. Isolated Amount Validator (Total Amount Sent row as main value, Amount row as cross-check)
 */
export function validateAmount({ rawAmount, rawText, expectedAmount }) {
  let foundAmountStr = '';

  if (rawAmount && String(rawAmount).trim().length > 0) {
    foundAmountStr = String(rawAmount).trim();
  } else {
    // 1. Anchored search for 'Total Amount Sent' / 'Total Amount' (peso sign optional)
    const totalSentMatch = String(rawText || '').match(/Total\s*Amount(?:\s*Sent)?\s*[:-]?\s*(?:PHP|P|₱|R|F|#|£)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})/i);
    if (totalSentMatch) {
      foundAmountStr = totalSentMatch[1].trim();
    } else {
      // 2. Anchored search for plain 'Amount' row (NO peso sign required)
      const amtRowMatch = String(rawText || '').match(/(?:^|[\n\r\s])Amount\s*[:-]?\s*(?:PHP|P|₱|R|F|#|£)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})/i);
      if (amtRowMatch) {
        foundAmountStr = amtRowMatch[1].trim();
      } else {
        const curMatch = String(rawText || '').match(/(?:₱|PHP|Php|P)\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})/i);
        if (curMatch) {
          foundAmountStr = curMatch[1].trim();
        }
      }
    }
  }

  if (!foundAmountStr) {
    return { valid: false, error: "We couldn't read the receipt clearly. Please upload a clearer screenshot." };
  }

  const trimmedAmt = foundAmountStr.trim();
  const numPart = trimmedAmt.replace(/^(?:₱|PHP|Php|P|R|F|#|£)\s*/i, '').trim();
  const validAmountShape = /^(?:\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})$/;

  if (!validAmountShape.test(numPart)) {
    return { valid: false, error: 'The amount on the receipt is incorrect or has been altered.' };
  }

  const cleanNumStr = numPart.replace(/,/g, '');
  const parsedVal = parseFloat(cleanNumStr);
  const expectedNum = Number(expectedAmount);

  if (isNaN(parsedVal) || Math.abs(parsedVal - expectedNum) >= 0.01) {
    return { valid: false, error: 'The amount on the receipt is incorrect or has been altered.' };
  }

  return { valid: true, error: null };
}

/**
 * 4. Isolated Reference Number Validator (Anchored to 'Ref No.', stops after 13 digits)
 */
export function validateReference({ rawReference, rawText }) {
  let foundRefStr = '';

  if (rawReference && String(rawReference).trim().length > 0) {
    foundRefStr = String(rawReference).trim();
  } else {
    // Anchored search: Stop after 13 digits total, preventing swallowing of date
    const refLabelMatch = String(rawText || '').match(/Ref[\s.]*(?:No|#)[\s.:]*([0-9\s]+)/i);
    if (refLabelMatch) {
      const afterLabel = refLabelMatch[1];
      const digits = [];
      for (let i = 0; i < afterLabel.length; i++) {
        const ch = afterLabel[i];
        if (/\d/.test(ch)) {
          digits.push(ch);
          if (digits.length === 13) break;
        } else if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
          continue;
        } else {
          break;
        }
      }
      if (digits.length === 13) {
        foundRefStr = `${digits.slice(0, 4).join('')} ${digits.slice(4, 7).join('')} ${digits.slice(7, 13).join('')}`;
      }
    }

    if (!foundRefStr) {
      const refGroupedPattern = /\b\d{4}\s\d{3}\s\d{6}\b/;
      const matchGrouped = String(rawText || '').match(refGroupedPattern);
      if (matchGrouped) {
        foundRefStr = matchGrouped[0];
      }
    }
  }

  if (!foundRefStr) {
    return { valid: false, error: "We couldn't read the receipt clearly. Please upload a clearer screenshot." };
  }

  const digitsOnly = foundRefStr.replace(/\D/g, '');
  const strictRefRegex = /^\d{4}\s\d{3}\s\d{6}$/;
  if (!strictRefRegex.test(foundRefStr)) {
    return { valid: false, error: 'The reference number is invalid or has already been used.' };
  }

  return { valid: true, error: null, cleanReference: digitsOnly };
}

/**
 * 5. Isolated Date and Time Validator (Date constraint removed per user request)
 */
export function validateDateTime({ rawDate, rawText, referenceTime = new Date() }) {
  // Date/time constraint removed: Always valid
  return { valid: true, error: null };
}

/**
 * GCash Receipt Strict Validator aggregating isolated checks
 */
export function validateGCashReceipt({
  ocrData,
  expectedAmount,
  expectedRecipient = '',
  expectedPhone = '',
  expectedAccounts = [],
}) {
  if (!ocrData) {
    return {
      isValid: false,
      errors: ['Receipt could not be processed by OCR scanner.'],
      fieldErrors: {},
      cleanReference: '',
    };
  }

  const rawReference = String(ocrData.raw_reference || ocrData.reference_number || '');
  const rawAmount = String(ocrData.raw_amount || ocrData.amount || '');
  const rawDate = String(ocrData.raw_date || ocrData.date || '');
  const rawPhone = String(ocrData.phone || '');
  const rawText = String(ocrData.extracted_text || '');
  const rawLines = ocrData.raw_lines;

  // Build accounts list
  const accounts = [];
  if (Array.isArray(expectedAccounts) && expectedAccounts.length > 0) {
    for (const acc of expectedAccounts) {
      const n = (acc?.name || '').trim();
      const p = (acc?.phone || '').trim();
      if (n || p) {
        accounts.push({ name: n, phone: p });
      }
    }
  }
  if (accounts.length === 0 && (expectedRecipient.trim() || expectedPhone.trim())) {
    accounts.push({
      name: expectedRecipient.trim(),
      phone: expectedPhone.trim(),
    });
  }

  if (accounts.length === 0) {
    return {
      isValid: false,
      errors: ['Owner GCash account details are not configured.'],
      fieldErrors: { recipientName: 'Owner GCash account details are not configured.' },
      cleanReference: '',
    };
  }

  // Dynamic Owner GCash Account Validation (Name + Phone as a pair)
  let pairMatched = false;
  let anyNameMatched = false;
  let anyPhoneMatched = false;

  for (const acc of accounts) {
    const accName = acc.name || '';
    const accPhone = acc.phone || '';

    const nRes = validateRecipientName({
      rawLines,
      rawText,
      expectedRecipient: accName,
    });
    const pRes = validatePhoneNumber({
      rawText,
      expectedPhone: accPhone,
      rawPhone,
    });

    const nOk = nRes.valid === true;
    const pOk = pRes.valid === true;

    if (nOk) anyNameMatched = true;
    if (pOk) anyPhoneMatched = true;

    if (nOk && pOk) {
      pairMatched = true;
      break;
    }
  }

  let nameError = null;
  let phoneError = null;
  if (!pairMatched) {
    if (!anyNameMatched) {
      nameError = 'Recipient name does not match.';
    }
    if (!anyPhoneMatched) {
      phoneError = 'Phone number does not match recipient number.';
    }
    if (anyNameMatched && anyPhoneMatched && !pairMatched) {
      nameError = 'Recipient name does not match.';
      phoneError = 'Phone number does not match recipient number.';
    }
  }

  // 3. Amount check (isolated)
  const amountResult = validateAmount({
    rawAmount,
    rawText,
    expectedAmount,
  });

  // 4. Reference Number check (isolated)
  const referenceResult = validateReference({
    rawReference,
    rawText,
  });

  // 5. Date and Time check (isolated)
  const dateTimeResult = validateDateTime({
    rawDate,
    rawText,
  });

  // Collect results strictly by field key
  const fieldErrors = {
    recipientName: nameError,
    phone: phoneError,
    amount: amountResult.valid ? null : amountResult.error,
    reference: referenceResult.valid ? null : referenceResult.error,
    dateTime: dateTimeResult.valid ? null : dateTimeResult.error,
  };

  const errors = [];
  if (fieldErrors.recipientName) errors.push(fieldErrors.recipientName);
  if (fieldErrors.phone) errors.push(fieldErrors.phone);
  if (fieldErrors.amount) errors.push(fieldErrors.amount);
  if (fieldErrors.reference) errors.push(fieldErrors.reference);
  if (fieldErrors.dateTime) errors.push(fieldErrors.dateTime);

  const cleanReference = referenceResult.cleanReference || rawReference.replace(/\D/g, '');

  return {
    isValid: errors.length === 0,
    errors,
    fieldErrors,
    cleanReference,
  };
}

/**
 * Fetch dynamic owner GCash accounts from Firebase properties/<ownerUid> and users/<ownerUid>
 */
export async function fetchOwnerGCashAccounts(db, ownerUid, fallbackProperty = {}) {
  const accounts = [];

  const addAccount = (name, phone) => {
    const n = String(name || '').trim();
    const p = String(phone || '').trim();
    if (n || p) {
      const already = accounts.some(a => a.name.toLowerCase() === n.toLowerCase() && a.phone === p);
      if (!already) {
        accounts.push({ name: n, phone: p });
      }
    }
  };

  if (ownerUid && db) {
    try {
      // 1. Fetch properties/<ownerUid>
      const { ref, get } = await import('firebase/database');
      const propSnap = await get(ref(db, `properties/${ownerUid}`));
      if (propSnap.exists()) {
        const val = propSnap.val() || {};
        addAccount(val.gcashName, val.gcashNumber);
        if (val.gcashAccounts) {
          const accs = Array.isArray(val.gcashAccounts) ? val.gcashAccounts : Object.values(val.gcashAccounts);
          for (const it of accs) {
            if (it) addAccount(it.name || it.gcashName, it.phone || it.number || it.gcashNumber);
          }
        }
      }

      // 2. Fetch users/<ownerUid>
      const userSnap = await get(ref(db, `users/${ownerUid}`));
      if (userSnap.exists()) {
        const uVal = userSnap.val() || {};
        addAccount(uVal.gcashName, uVal.gcashNumber);
        if (uVal.gcashAccounts) {
          const accs = Array.isArray(uVal.gcashAccounts) ? uVal.gcashAccounts : Object.values(uVal.gcashAccounts);
          for (const it of accs) {
            if (it) addAccount(it.name || it.gcashName, it.phone || it.number || it.gcashNumber);
          }
        }
      }
    } catch (e) {
      console.warn("fetchOwnerGCashAccounts warning:", e);
    }
  }

  // 3. Fallback to passed-in property object if still empty
  if (accounts.length === 0 && fallbackProperty) {
    addAccount(fallbackProperty.gcashName, fallbackProperty.gcashNumber);
  }

  return accounts;
}
