import { ref, get } from "firebase/database";
import { db as defaultDb } from "../firebase.js";

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
// Also normalizes internal dots/periods masking letters (e.g. JO.N -> JO*N, JA..N -> JA**N)
function normalizeMaskChars(str) {
  if (!str) return '';
  let res = str.replace(/[•●○◦·∙⦿⦾◉⬤*∗✱✲\-_]/g, '*');
  res = res.replace(/(?<=[A-Za-z0-9])\.+(?=[A-Za-z0-9])/g, (m) => '*'.repeat(m.length));
  return res;
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

    // Recovery 1: If tokens has fewer tokens than numWords (e.g. 'JA**NL' merged into 1 token)
    if (tokens.length === numWords - 1 && numWords >= 2) {
      const lastTokenClean = tokens[tokens.length - 1].replace(/[:;,\.]+$/, '');
      if (lastTokenClean.length >= 2) {
        const expectedLastChar = expWords[expWords.length - 1][0];
        if (lastTokenClean[lastTokenClean.length - 1].toLowerCase() === expectedLastChar) {
          const splitMiddle = lastTokenClean.slice(0, -1);
          const splitInitial = lastTokenClean.slice(-1);
          const retokenized = [...tokens.slice(0, -1), splitMiddle, splitInitial];
          candidateWordLists.push(retokenized);
        }
      }
    }

    // OCR recovery: if last token is 2 characters without period (e.g. 'NL' or 'NL:'),
    // EasyOCR often split the middle word and attached its last letter to the initial.
    if (tokens.length >= 2) {
      const lastTokenClean = tokens[tokens.length - 1].replace(/[:;,\.]+$/, '');
      const prevToken = tokens[tokens.length - 2];
      if (lastTokenClean.length === 2 && !tokens[tokens.length - 1].includes('.')) {
        const mergedMiddle = prevToken + lastTokenClean[0];
        const newInitial = lastTokenClean[1];
        const retokenized = [...tokens.slice(0, tokens.length - 2), mergedMiddle, newInitial];
        if (retokenized.length === numWords) {
          candidateWordLists.push(retokenized);
        } else if (retokenized.length > numWords) {
          for (let i = 0; i <= retokenized.length - numWords; i++) {
            candidateWordLists.push(retokenized.slice(i, i + numWords));
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
    function gcashWordMatch(candW, expW) {
      if (!candW && !expW) return true;
      if (!candW || !expW) return false;

      const normCandW = normalizeMaskChars(candW).toLowerCase();
      const normExpW = normalizeMaskChars(expW).toLowerCase();

      // Handle single-letter initial on candidate side (e.g. "B." or "B" matching "Brosas", "B.", or "B")
      const candStripped = normCandW.replace(/\.+$/, '');
      const expStripped = normExpW.replace(/\.+$/, '');

      if (candStripped.length === 1 || expStripped.length === 1) {
        return candStripped[0] === expStripped[0];
      }

      // For very short expected words (1-2 chars, e.g. "B.", "Jr.")
      if (normExpW.length <= 2) {
        if (candStripped === expStripped) return true;
        // Allow masking of second char (e.g. 'j*' matching 'jr')
        if (candStripped.length === expStripped.length && candStripped[0] === expStripped[0] && candStripped.slice(1).split('').every(c => c === '*')) {
          return true;
        }
        return false;
      }

      // First character must match (GCash never masks the first char)
      if (normCandW[0] === '*' || normCandW[0] !== normExpW[0]) return false;

      // Case 0: Direct positional match if same character length
      if (normCandW.length === normExpW.length) {
        let posMatch = true;
        for (let i = 0; i < normCandW.length; i++) {
          if (normCandW[i] !== '*' && normCandW[i] !== normExpW[i]) {
            posMatch = false;
            break;
          }
        }
        if (posMatch) return true;
      }

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
      const subsets = [tokens.join('')];
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
export function validatePhoneNumber({ rawText, expectedPhone, rawPhone, isRecipientVerified = false }) {
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

  const phoneCandidateRegex = /(?<!\d)(?:(?:\+?63[ \t-]?)9|09)[ \t\d*•●○⦿⦾◦·\-_.:]{7,16}(?!\d)/g;
  const matches = String(rawText || '').match(phoneCandidateRegex) || [];
  let phoneMatched = false;

  for (const cand of matches) {
    const digits = cand.replace(/\D/g, '');
    if (normalizePhone(digits) === targetPhone) {
      phoneMatched = true;
      break;
    }

    let normCand = cand.replace(/[•●○⦿⦾◦·\-_]/g, '*');
    normCand = normCand.replace(/\./g, '*');
    let candClean = normCand.replace(/[\s\-:]/g, '');
    if (candClean.startsWith('+63')) {
      candClean = '0' + candClean.slice(3);
    } else if (candClean.startsWith('63')) {
      candClean = '0' + candClean.slice(2);
    } else if (candClean.startsWith('9') && candClean.length === 10) {
      candClean = '0' + candClean;
    }

    if (candClean.includes('*') && targetPhone.length === 11) {
      const prefixOk = candClean.startsWith(targetPhone.slice(0, 4));
      const suffixOk = candClean.endsWith(targetPhone.slice(-4));
      if (prefixOk && suffixOk) {
        const midCand = candClean.slice(4, -4);
        const midExp = targetPhone.slice(4, -4);
        if (midCand.length === midExp.length) {
          let midOk = true;
          for (let i = 0; i < midCand.length; i++) {
            if (midCand[i] !== '*' && midCand[i] !== midExp[i]) {
              midOk = false;
              break;
            }
          }
          if (midOk) {
            phoneMatched = true;
            break;
          }
        } else {
          phoneMatched = true;
          break;
        }
      }
    }
  }

  if (!phoneMatched) {
    // GCash QR code receipts do NOT display a phone number.
    // If no phone number was found on the receipt and recipient name is verified,
    // this is a valid QR payment receipt.
    const hasPhoneCandidate = matches.some(m => /\d{3,}/.test(m));
    if ((matches.length === 0 || !hasPhoneCandidate) && isRecipientVerified) {
      return { valid: true, error: null };
    }
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
    // 1. Look for standard 0000 000 000000 pattern anchored to Ref No
    const refFormattedMatch = String(rawText || '').match(/Ref[\s.]*(?:No|#)[\s.:]*(\d{4}\s+\d{3}\s+\d{6})\b/i);
    if (refFormattedMatch) {
      foundRefStr = refFormattedMatch[1];
    }

    // 2. Look for Ref No line up to the date
    if (!foundRefStr) {
      const refLabelMatch = String(rawText || '').match(/Ref[\s.]*(?:No|#)[\s.:]*(.+)/i);
      if (refLabelMatch) {
        const afterLabel = refLabelMatch[1].trim();
        // Cut off at the date (e.g. Oct 17, 2026) so date digits are never borrowed
        const beforeDate = afterLabel.split(/\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/i)[0];

        const matchGrouped = beforeDate.match(/\b\d{4}\s+\d{3}\s+\d{6}\b/);
        if (matchGrouped) {
          foundRefStr = matchGrouped[0];
        } else {
          // Keep the exact digits found on the Ref No line before the date
          const digits = beforeDate.replace(/\D/g, '');
          if (digits.length > 0) {
            if (digits.length === 13) {
              foundRefStr = `${digits.slice(0, 4)} ${digits.slice(4, 7)} ${digits.slice(7, 13)}`;
            } else {
              foundRefStr = digits; // Incomplete digits -> will be strictly flagged as invalid!
            }
          }
        }
      }
    }

    if (!foundRefStr) {
      const refGroupedPattern = /\b\d{4}\s+\d{3}\s+\d{6}\b/;
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
  expectedRecipient = "",
  expectedPhone = "",
}) {
  if (!ocrData) {
    return {
      isValid: false,
      errors: ["Receipt could not be processed by OCR scanner."],
      fieldErrors: {},
      cleanReference: "",
    };
  }

  const rawReference = String(ocrData.raw_reference || ocrData.reference_number || "");
  const rawAmount = String(ocrData.raw_amount || ocrData.amount || "");
  const rawDate = String(ocrData.raw_date || ocrData.date || "");
  const rawPhone = String(ocrData.phone || "");
  const rawText = String(ocrData.extracted_text || "");
  const rawLines = ocrData.raw_lines;

  const expRecipientClean = String(expectedRecipient || "").trim();
  const expPhoneClean = String(expectedPhone || "").trim();

  // If owner GCash is not set up, show clear error without blaming receipt
  if (!expRecipientClean && !expPhoneClean) {
    return {
      isValid: false,
      errors: ["The resort's GCash account is not set up yet. Please contact the owner."],
      fieldErrors: { recipientName: "The resort's GCash account is not set up yet. Please contact the owner." },
      cleanReference: "",
    };
  }

  // 1. Recipient Name check (isolated)
  const nameResult = validateRecipientName({
    rawLines,
    rawText,
    expectedRecipient: expRecipientClean,
  });

  // 2. Phone Number check (isolated)
  const phoneResult = validatePhoneNumber({
    rawText,
    expectedPhone: expPhoneClean,
    rawPhone,
    isRecipientVerified: nameResult.valid,
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

  const cleanReference = referenceResult.cleanReference || rawReference.replace(/\D/g, "");

  return {
    isValid: errors.length === 0,
    fieldErrors,
    errors,
    cleanReference,
  };
}

/**
 * Fetch fresh current owner GCash account from Firebase properties/<ownerUid>
 * Robust against property id slugs (e.g. 'casa-delrio') as well as true owner UIDs.
 */
export async function fetchCurrentOwnerGCashAccount(dbInstance, ownerUid, fallbackProperty = {}) {
  let name = "";
  let phone = "";
  const database = dbInstance || defaultDb;
  const rawId = ownerUid || fallbackProperty?.ownerUid || fallbackProperty?.uid || fallbackProperty?.id;
  const resolvedUid = rawId ? String(rawId).trim() : "";

  if (resolvedUid && database) {
    try {
      // 1. Direct lookup by key on properties/<resolvedUid>
      const propSnap = await get(ref(database, `properties/${resolvedUid}`));
      if (propSnap.exists()) {
        const val = propSnap.val() || {};
        name = String(val.gcashName || "").trim();
        phone = String(val.gcashNumber || "").trim();
      }

      // 2. If not found by key, resolvedUid might be a slug (e.g. 'casa-delrio'). Search properties list
      if (!name || !phone) {
        const allPropsSnap = await get(ref(database, "properties"));
        if (allPropsSnap.exists()) {
          const allProps = allPropsSnap.val() || {};
          for (const [key, pVal] of Object.entries(allProps)) {
            if (key === resolvedUid || pVal?.id === resolvedUid || pVal?.ownerUid === resolvedUid) {
              if (!name) name = String(pVal?.gcashName || "").trim();
              if (!phone) phone = String(pVal?.gcashNumber || "").trim();
              break;
            }
          }
        }
      }

      // 3. Fallback to users/<resolvedUid> only if still empty and looks like a Firebase UID
      if ((!name || !phone) && resolvedUid.length > 20) {
        try {
          const userSnap = await get(ref(database, `users/${resolvedUid}`));
          if (userSnap.exists()) {
            const uVal = userSnap.val() || {};
            if (!name) name = String(uVal.gcashName || "").trim();
            if (!phone) phone = String(uVal.gcashNumber || "").trim();
          }
        } catch (_) {
          // Ignore permission denied on users/
        }
      }
    } catch (e) {
      console.warn("fetchCurrentOwnerGCashAccount warning:", e);
    }
  }

  // 4. Fallback to passed-in fallbackProperty if still empty
  if ((!name || !phone) && fallbackProperty) {
    if (!name) name = String(fallbackProperty.gcashName || "").trim();
    if (!phone) phone = String(fallbackProperty.gcashNumber || "").trim();
  }

  return { name, phone };
}

// Backward-compatible alias that returns [ { name, phone } ] if called
export async function fetchOwnerGCashAccounts(db, ownerUid, fallbackProperty = {}) {
  const current = await fetchCurrentOwnerGCashAccount(db, ownerUid, fallbackProperty);
  return (current.name || current.phone) ? [current] : [];
}
