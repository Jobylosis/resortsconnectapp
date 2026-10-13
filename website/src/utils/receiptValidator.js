/**
 * Shared GCash Receipt Strict Validator for Website (React)
 * Enforces the 4 strict rules:
 * 1. Recipient Name: Masked matching allowed, identical word count & character length per word, visible chars must match.
 * 2. Amount: Exact money format ₱... or digits with 2 decimals, numeric value equals expectedAmount.
 * 3. Date and Time: Chronological format 'Mon DD, YYYY hh:mm AM/PM', valid calendar date and time.
 * 4. Reference Number: Exactly 13 digits grouped as '0000 000 000000'.
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

  // ==========================================
  // RULE 1: RECIPIENT NAME (Masked names allowed)
  // ==========================================
  const expNameClean = (expectedRecipient || '').trim().replace(/\s+/g, ' ');
  if (expNameClean.length > 0) {
    const expWords = expNameClean.split(' ').filter(w => w.length > 0);
    const numWords = expWords.length;

    const lines = Array.isArray(ocrData.raw_lines)
      ? ocrData.raw_lines.map(l => String(l))
      : rawText.split('\n');

    const candidatePhrases = [];
    for (const line of lines) {
      const trimmed = line.trim().replace(/\s+/g, ' ');
      if (trimmed.length > 0) candidatePhrases.push(trimmed);
    }

    const allTokens = rawText.trim().split(/\s+/).filter(t => t.length > 0);
    for (let i = 0; i <= allTokens.length - numWords; i++) {
      const phrase = allTokens.slice(i, i + numWords).join(' ');
      if (!candidatePhrases.includes(phrase)) {
        candidatePhrases.push(phrase);
      }
    }

    let namePassed = false;
    let bestMismatchReason = null;

    for (const candidate of candidatePhrases) {
      const candWords = candidate.split(' ').filter(w => w.length > 0);
      if (candWords.length !== numWords) continue;

      let candidateMatches = true;
      let wordFailureMsg = null;

      for (let wIdx = 0; wIdx < numWords; wIdx++) {
        const expW = expWords[wIdx];
        const candW = candWords[wIdx];

        if (candW.length !== expW.length) {
          candidateMatches = false;
          wordFailureMsg = `expected ${expW.length} characters in '${expW}', found ${candW.length} in '${candW}'.`;
          break;
        }

        for (let cIdx = 0; cIdx < expW.length; cIdx++) {
          const cCand = candW[cIdx];
          const cExp = expW[cIdx];

          if (['*', '•', '●', '○', '⦿'].includes(cCand)) {
            continue;
          }

          if (cCand.toLowerCase() !== cExp.toLowerCase()) {
            candidateMatches = false;
            wordFailureMsg = `character mismatch in '${candW}' for expected '${expW}'.`;
            break;
          }
        }

        if (!candidateMatches) break;
      }

      if (candidateMatches) {
        namePassed = true;
        break;
      } else if (wordFailureMsg && !bestMismatchReason) {
        bestMismatchReason = wordFailureMsg;
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
  // RULE 2: AMOUNT
  // ==========================================
  let foundAmountStr = '';
  const amountPattern = /(?:₱\s?\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})/;

  if (rawAmount.length > 0 && (rawAmount.includes('.') || rawAmount.includes('₱') || rawAmount.includes('P'))) {
    foundAmountStr = rawAmount.trim();
  } else {
    const amtMatch = rawText.match(amountPattern);
    if (amtMatch) {
      foundAmountStr = amtMatch[0];
    }
  }

  if (!foundAmountStr) {
    errors.push('Amount could not be read from the receipt.');
  } else {
    const strictFormat = /^(?:₱\s?\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})$/;
    if (!strictFormat.test(foundAmountStr)) {
      errors.push(`Amount format is invalid: found '${foundAmountStr}'. Expected format like ₱100.00.`);
    } else {
      const cleanNumStr = foundAmountStr.replace(/[^\d.]/g, '');
      const parsedVal = parseFloat(cleanNumStr);
      const expectedNum = Number(expectedAmount);
      if (isNaN(parsedVal) || Math.abs(parsedVal - expectedNum) >= 0.01) {
        const expStr = Number(expectedAmount).toFixed(2);
        errors.push(`Amount does not match expected amount: expected ₱${expStr}, found '${foundAmountStr}'.`);
      }
    }
  }

  // ==========================================
  // RULE 3: DATE AND TIME
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
      errors.push(`Date format is invalid: expected 'Mon DD, YYYY hh:mm AM/PM' (e.g. Oct 13, 2026 12:18 PM), found '${foundDateStr}'.`);
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

  // ==========================================
  // RULE 4: REFERENCE NUMBER
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

  return {
    isValid: errors.length === 0,
    errors,
    cleanReference: rawReference.replace(/\D/g, ''),
  };
}
