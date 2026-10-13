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

// Helper: Normalize mask characters: * ∗ ✱ ✲ • · (each counts as 1 letter)
function normalizeMaskChars(str) {
  return (str || '').replace(/[∗✱✲•·*]/g, '*');
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

  // Word-by-word comparison for candidate word lists
  if (!namePassed) {
    for (const candRawWords of candidateWordLists) {
      let candidateMatches = true;

      const cleanedCandWords = candRawWords.map(w => {
        return stripAccents(w.replace(/^[\s,:\-;]+|[\s,:\-;\.]+$/g, ''));
      });

      const firstCandWord = cleanedCandWords[0];
      const firstExpWord = expWords[0];
      if (firstCandWord.length > 0 && firstExpWord.length > 0) {
        const firstCandChar = normalizeMaskChars(firstCandWord[0]);
        if (firstCandChar === '*' || firstCandChar.toLowerCase() !== firstExpWord[0].toLowerCase()) {
          candidateMatches = false;
        }
      }

      if (candidateMatches) {
        for (let wIdx = 0; wIdx < numWords; wIdx++) {
          const expW = expWords[wIdx];
          const rawCandW = cleanedCandWords[wIdx];
          const normCandW = normalizeMaskChars(rawCandW);

          if (normCandW.length !== expW.length) {
            candidateMatches = false;
            break;
          }

          for (let cIdx = 0; cIdx < expW.length; cIdx++) {
            const cCand = normCandW[cIdx];
            const cExp = expW[cIdx];

            if (cCand === '*') continue;

            if (cCand.toLowerCase() !== cExp.toLowerCase()) {
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

  // OCR tolerance check (spaces merged/split)
  if (!namePassed) {
    const expWhole = expWords.join('');
    const totalExpLetters = expWhole.length;

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
        const candClean = stripAccents(rawSubset.replace(/[\s\.,:\-;]+/g, ''));
        const normCandWhole = normalizeMaskChars(candClean);

        if (normCandWhole.length !== totalExpLetters) continue;
        if (normCandWhole[0] === '*' || normCandWhole[0].toLowerCase() !== expWhole[0].toLowerCase()) {
          continue;
        }

        let wholeMatch = true;
        for (let i = 0; i < totalExpLetters; i++) {
          const cCand = normCandWhole[i];
          const cExp = expWhole[i];
          if (cCand === '*') continue;
          if (cCand.toLowerCase() !== cExp.toLowerCase()) {
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
    return { valid: false, error: 'Recipient name does not match.' };
  }
  return { valid: true, error: null };
}

/**
 * 2. Isolated Phone Number Validator
 */
export function validatePhoneNumber({ rawText, expectedPhone, rawPhone }) {
  const cleanExp = String(expectedPhone || '').replace(/\D/g, '').trim();
  if (!cleanExp) {
    return { valid: true, error: null };
  }

  let targetPhone = cleanExp;
  if (targetPhone.startsWith('63')) {
    targetPhone = '0' + targetPhone.slice(2);
  }

  if (rawPhone && String(rawPhone).trim()) {
    let cleanRaw = String(rawPhone).replace(/\D/g, '');
    if (cleanRaw.startsWith('63')) cleanRaw = '0' + cleanRaw.slice(2);
    if (cleanRaw === targetPhone) {
      return { valid: true, error: null };
    }
  }

  const phoneCandidateRegex = /(?:\+?63[\s\-]?)?(?:0?9[\s\d\*•●○⦿⦾◦·\-_]{9,16})/g;
  const matches = String(rawText || '').match(phoneCandidateRegex) || [];
  let phoneMatched = false;

  for (const cand of matches) {
    const normCand = cand.replace(/[•●○⦿⦾◦·\-_]/g, '*');
    let candClean = normCand.replace(/[\s\-]/g, '');
    if (candClean.startsWith('+63')) {
      candClean = '0' + candClean.slice(3);
    } else if (candClean.startsWith('63')) {
      candClean = '0' + candClean.slice(2);
    }

    const candDigits = candClean.replace(/\D/g, '');
    if (candDigits === targetPhone) {
      phoneMatched = true;
      break;
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
 * 3. Isolated Amount Validator
 */
export function validateAmount({ rawAmount, rawText, expectedAmount }) {
  let foundAmountStr = '';

  if (rawAmount && String(rawAmount).trim().length > 0) {
    foundAmountStr = String(rawAmount).trim();
  } else {
    const amtLabelMatch = String(rawText || '').match(/(?:Amount|Total\s*Amount|Total)\s*[:-]?\s*([^\n\r]+)/i);
    if (amtLabelMatch) {
      foundAmountStr = amtLabelMatch[1].trim();
    } else {
      const curMatch = String(rawText || '').match(/(?:₱|PHP|Php|P)\s*[\d,.\s]+/i);
      if (curMatch) {
        foundAmountStr = curMatch[0].trim();
      }
    }
  }

  if (!foundAmountStr) {
    return { valid: false, error: "We couldn't read the receipt clearly. Please upload a clearer screenshot." };
  }

  const trimmedAmt = foundAmountStr.trim();
  const numPart = trimmedAmt.replace(/^(?:₱|PHP|Php|P)\s*/i, '').trim();
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
 * 4. Isolated Reference Number Validator
 */
export function validateReference({ rawReference, rawText }) {
  let foundRefStr = '';

  // Priority: use explicit rawReference if provided, otherwise search grouped pattern in rawText
  if (rawReference && String(rawReference).trim().length > 0) {
    foundRefStr = String(rawReference).trim();
  } else {
    const refGroupedPattern = /\b\d{4}\s\d{3}\s\d{6}\b/;
    const matchGrouped = String(rawText || '').match(refGroupedPattern);
    if (matchGrouped) {
      foundRefStr = matchGrouped[0];
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
 * 5. Isolated Date and Time Validator
 */
export function validateDateTime({ rawDate, rawText }) {
  let foundDateStr = String(rawDate || '').trim();
  if (!foundDateStr) {
    const dateMatch = String(rawText || '').match(/[A-Za-z]{3}\s+\d{1,2},?\s+\d{4}\s+\d{1,2}[:.]\d{2}\s*(?:AM|PM)?/i);
    if (dateMatch) {
      foundDateStr = dateMatch[0].trim();
    }
  }

  if (!foundDateStr) {
    return { valid: false, error: "We couldn't read the receipt clearly. Please upload a clearer screenshot." };
  }

  // Normalize OCR period separator in time e.g. "08.30 PM" -> "08:30 PM"
  let normalizedDateStr = foundDateStr.replace(/(\d{1,2})\.(\d{2})\s*(AM|PM)/i, '$1:$2 $3');

  // Normalize comma spacing if missing e.g. "Oct 13 2026" -> "Oct 13, 2026"
  normalizedDateStr = normalizedDateStr.replace(/^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})\s+/i, '$1 $2, $3 ');

  const dateStrictRegex = /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s(\d{1,2}),\s(\d{4})\s(\d{1,2}):(\d{2})\s(AM|PM)$/i;
  const match = normalizedDateStr.match(dateStrictRegex);
  if (!match) {
    return { valid: false, error: 'The date and time on the receipt appear to be altered or invalid.' };
  }

  const monthStr = match[1].toLowerCase();
  const day = parseInt(match[2], 10);
  const year = parseInt(match[3], 10);
  const hour = parseInt(match[4], 10);
  const minute = parseInt(match[5], 10);

  const monthMap = {
    jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
    jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12
  };
  const month = monthMap[monthStr] || 1;

  const isLeapYear = (year % 4 === 0 && year % 100 !== 0) || (year % 400 === 0);
  const daysInMonths = [0, 31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  if (day < 1 || day > daysInMonths[month] || hour < 1 || hour > 12 || minute < 0 || minute > 59) {
    return { valid: false, error: 'The date and time on the receipt appear to be altered or invalid.' };
  }

  return { valid: true, error: null };
}

/**
 * GCash Receipt Strict Validator aggregating isolated checks
 */
export function validateGCashReceipt({ ocrData, expectedAmount, expectedRecipient, expectedPhone = '' }) {
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

  // 1. Recipient Name check (isolated)
  const nameResult = validateRecipientName({
    rawLines,
    rawText,
    expectedRecipient,
  });

  // 2. Phone Number check (isolated)
  const phoneResult = validatePhoneNumber({
    rawText,
    expectedPhone,
    rawPhone,
  });

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
    recipientName: nameResult.valid ? null : nameResult.error,
    phone: phoneResult.valid ? null : phoneResult.error,
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
