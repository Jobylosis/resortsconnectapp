/**
 * Shared GCash Receipt Strict Validator for Website (React)
 * Checks 4 points in this exact order:
 * (1) Recipient Name
 * (2) Amount
 * (3) Reference Number
 * (4) Date and Time
 */

export function validateGCashReceipt({ ocrData, expectedAmount, expectedRecipient }) {
  const errors = [];

  if (!ocrData) {
    return {
      isValid: false,
      errors: ['Receipt could not be processed by OCR scanner.'],
      cleanReference: '',
    };
  }

  const rawReference = String(ocrData.raw_reference || ocrData.reference_number || '');
  const rawAmount = String(ocrData.raw_amount || ocrData.amount || '');
  const rawDate = String(ocrData.raw_date || ocrData.date || '');
  const rawText = String(ocrData.extracted_text || '');

  console.log('[GCash Receipt Validation] Raw Inputs:', {
    rawRecipientText: (ocrData.raw_lines || []).join(' | ') || rawText.slice(0, 80),
    rawAmount,
    rawReference,
    rawDate,
    expectedAmount,
    expectedRecipient,
  });

  // ==========================================
  // CHECK 1: RECIPIENT NAME (GCash masks random letters with *)
  // ==========================================
  const expNameClean = (expectedRecipient || '').trim().replace(/\s+/g, ' ');
  if (expNameClean.length > 0) {
    const rawExpWords = expNameClean.split(' ').filter(w => w.length > 0);
    // Strip trailing period from initials (not counted as a letter)
    const expWords = rawExpWords.map(w => w.replace(/\.+$/, ''));
    const numWords = expWords.length;

    const lines = Array.isArray(ocrData.raw_lines) && ocrData.raw_lines.length > 0
      ? ocrData.raw_lines.map(l => String(l))
      : rawText.split('\n');

    const candidatePhrases = [];
    for (const line of lines) {
      const trimmed = line.trim().replace(/\s+/g, ' ');
      if (trimmed.length > 0) candidatePhrases.push(trimmed);
    }

    // Helper: Normalize mask characters: * ∗ ✱ ✲ • · (each counts as 1 letter)
    function normalizeMaskChars(str) {
      return str.replace(/[∗✱✲•·*]/g, '*');
    }

    let namePassed = false;
    let bestMismatchReason = null;

    // 1. Word-by-word comparison for candidate phrases with matching word count
    for (const candidate of candidatePhrases) {
      const candRawWords = candidate.split(' ').filter(w => w.length > 0);
      if (candRawWords.length !== numWords) continue;

      let candidateMatches = true;
      let wordFailureMsg = null;

      // Check first letter of whole name: must be visible and match first letter of expected name
      const firstCandWord = candRawWords[0].replace(/\.+$/, '');
      const firstExpWord = expWords[0];
      if (firstCandWord.length > 0 && firstExpWord.length > 0) {
        const firstCandChar = normalizeMaskChars(firstCandWord[0]);
        if (firstCandChar === '*') {
          candidateMatches = false;
          wordFailureMsg = `first letter cannot be masked in '${firstCandWord}'.`;
        } else if (firstCandChar.toLowerCase() !== firstExpWord[0].toLowerCase()) {
          candidateMatches = false;
          wordFailureMsg = `first letter mismatch in '${firstCandWord}', expected '${firstExpWord[0]}'.`;
        }
      }

      if (candidateMatches) {
        for (let wIdx = 0; wIdx < numWords; wIdx++) {
          const expW = expWords[wIdx];
          const rawCandW = candRawWords[wIdx];
          const candWClean = rawCandW.replace(/\.+$/, '');
          const normCandW = normalizeMaskChars(candWClean);

          // Letter count check
          if (normCandW.length !== expW.length) {
            candidateMatches = false;
            wordFailureMsg = `expected ${expW.length} letters in '${expW}', found ${normCandW.length} in '${rawCandW}'.`;
            break;
          }

          // Visible (non-mask) letters check in any random position
          for (let cIdx = 0; cIdx < expW.length; cIdx++) {
            const cCand = normCandW[cIdx];
            const cExp = expW[cIdx];

            if (cCand === '*') continue;

            if (cCand.toLowerCase() !== cExp.toLowerCase()) {
              candidateMatches = false;
              wordFailureMsg = `character mismatch in '${rawCandW}' for expected '${expW}'.`;
              break;
            }
          }

          if (!candidateMatches) break;
        }
      }

      if (candidateMatches) {
        namePassed = true;
        break;
      } else if (wordFailureMsg && !bestMismatchReason) {
        bestMismatchReason = wordFailureMsg;
      }
    }

    // 2. OCR tolerance: if OCR merged or split words so word count differs,
    // compare with spaces and periods removed: same total letter count, first letter matches, visible letters match in order
    if (!namePassed) {
      const expWhole = expWords.join('');
      const totalExpLetters = expWhole.length;

      for (const candidate of candidatePhrases) {
        const candRawWords = candidate.split(' ').filter(w => w.length > 0);
        if (candRawWords.length === numWords) continue; // already evaluated word-by-word above

        const candCleanWords = candRawWords.map(w => w.replace(/\.+/g, ''));
        const candWholeRaw = candCleanWords.join('');
        const normCandWhole = normalizeMaskChars(candWholeRaw);

        if (normCandWhole.length !== totalExpLetters) continue;

        // First letter must be visible and match
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
    }

    if (!namePassed) {
      if (bestMismatchReason) {
        errors.push(`Recipient name does not match: ${bestMismatchReason}`);
      } else {
        errors.push(`Recipient name does not match: expected '${expNameClean}' was not found on the receipt.`);
      }
    }
  }

  // ==========================================
  // CHECK 2: AMOUNT
  // ==========================================
  let foundAmountStr = '';

  if (rawAmount.length > 0) {
    foundAmountStr = rawAmount.trim();
  } else {
    const amtLabelMatch = rawText.match(/(?:Amount|Total\s*Amount|Total)\s*[:-]?\s*([^\n\r]+)/i);
    if (amtLabelMatch) {
      foundAmountStr = amtLabelMatch[1].trim();
    } else {
      const curMatch = rawText.match(/(?:₱|PHP|Php|P)\s*[\d,.\s]+/i);
      if (curMatch) {
        foundAmountStr = curMatch[0].trim();
      }
    }
  }

  if (!foundAmountStr) {
    errors.push('Amount could not be read from the receipt.');
  } else {
    let trimmedAmt = foundAmountStr.trim();
    // Remove currency symbol (₱, P, PHP, Php) and optional whitespace
    let numPart = trimmedAmt.replace(/^(?:₱|PHP|Php|P)\s*/i, '').trim();

    // Accepted shape: ^\d{1,3}(,\d{3})*\.\d{2}$ or ^\d+\.\d{2}$
    const validAmountShape = /^(?:\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})$/;

    if (!validAmountShape.test(numPart)) {
      errors.push(`Amount format is invalid: found '${foundAmountStr}'. Expected two decimals like ₱100.00.`);
    } else {
      const cleanNumStr = numPart.replace(/,/g, '');
      const parsedVal = parseFloat(cleanNumStr);
      const expectedNum = Number(expectedAmount);

      if (isNaN(parsedVal) || Math.abs(parsedVal - expectedNum) >= 0.01) {
        const expStr = Number(expectedAmount).toFixed(2);
        errors.push(`Amount does not match expected amount: expected ₱${expStr}, found '${foundAmountStr}'.`);
      }
    }
  }

  // ==========================================
  // CHECK 3: REFERENCE NUMBER
  // ==========================================
  let foundRefStr = '';
  const refGroupedPattern = /\b\d{4}\s\d{3}\s\d{6}\b/;
  const matchGrouped = rawText.match(refGroupedPattern);

  if (matchGrouped) {
    foundRefStr = matchGrouped[0];
  } else if (rawReference.length > 0) {
    foundRefStr = rawReference.trim();
  }

  if (!foundRefStr) {
    errors.push('Reference number could not be read from the receipt.');
  } else {
    const strictRefRegex = /^\d{4}\s\d{3}\s\d{6}$/;
    if (!strictRefRegex.test(foundRefStr)) {
      const totalDigits = foundRefStr.replace(/\D/g, '').length;
      if (totalDigits !== 13) {
        errors.push(`Reference number format is invalid: expected 13 digits as '0000 000 000000', found ${totalDigits} digits.`);
      } else {
        errors.push(`Reference number format is invalid: expected 13 digits grouped as '0000 000 000000', found '${foundRefStr}'.`);
      }
    }
  }

  // ==========================================
  // CHECK 4: DATE AND TIME
  // ==========================================
  let foundDateStr = rawDate.trim();
  if (!foundDateStr) {
    const dateMatch = rawText.match(/[A-Za-z]{3}\s+\d{1,2},?\s+\d{4}\s+\d{1,2}:\d{2}\s*(?:AM|PM)?/i);
    if (dateMatch) {
      foundDateStr = dateMatch[0].trim();
    }
  }

  if (!foundDateStr) {
    errors.push('Date and time could not be read from the receipt.');
  } else {
    const dateStrictRegex = /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s(\d{1,2}),\s(\d{4})\s(\d{1,2}):(\d{2})\s(AM|PM)$/i;
    const match = foundDateStr.match(dateStrictRegex);
    if (!match) {
      errors.push(`Date format is invalid: expected 'Mon DD, YYYY hh:mm AM/PM' (e.g. Oct 13, 2026 12:10 PM), found '${foundDateStr}'.`);
    } else {
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
        errors.push(`Date format is invalid: contains an impossible date or time '${foundDateStr}'.`);
      }
    }
  }

  return {
    isValid: errors.length === 0,
    errors,
    cleanReference: rawReference.replace(/\D/g, ''),
  };
}
