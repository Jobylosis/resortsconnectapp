/**
 * Shared Validator and Formatter for Historical Data Import (React Web Admin)
 */

// Format user date input into MM/DD/YY as they type
export function formatAsDateInput(rawVal, prevVal = '') {
  if (!rawVal) return '';

  // If user hit backspace on a slash, remove the digit before the slash as well
  if (prevVal && prevVal.length > rawVal.length) {
    if (prevVal.endsWith('/') && !rawVal.endsWith('/')) {
      return rawVal.slice(0, -1);
    }
    return rawVal;
  }

  // Keep digits only, max 6 digits for MM DD YY
  const digits = rawVal.replace(/\D/g, '').slice(0, 6);
  if (digits.length === 0) return '';
  if (digits.length <= 2) return digits;
  if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`;
  return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4, 6)}`;
}

// Check if a MM/DD/YY string is a strictly valid calendar date
export function isValidDateMMDDYY(dateStr) {
  if (!dateStr || typeof dateStr !== 'string') return false;
  const parts = dateStr.split('/');
  if (parts.length !== 3) return false;
  if (parts[0].length !== 2 || parts[1].length !== 2 || parts[2].length !== 2) return false;

  const m = parseInt(parts[0], 10);
  const d = parseInt(parts[1], 10);
  const y = parseInt(parts[2], 10);

  if (isNaN(m) || isNaN(d) || isNaN(y)) return false;
  if (m < 1 || m > 12) return false;

  const fullYear = 2000 + y;
  const daysInMonth = new Date(fullYear, m, 0).getDate();
  if (d < 1 || d > daysInMonth) return false;

  return true;
}

// Parse MM/DD/YY into a native Date object at midnight local time
export function parseDateMMDDYY(dateStr) {
  if (!isValidDateMMDDYY(dateStr)) return null;
  const [mm, dd, yy] = dateStr.split('/').map(n => parseInt(n, 10));
  return new Date(2000 + yy, mm - 1, dd, 0, 0, 0, 0);
}

// Regex patterns according to field validation specification
export const NAME_REGEX = /^[A-Za-z\u00C0-\u024F\u1E00-\u1EFF\s.'-]+$/;
export const PHILIPPINE_PHONE_REGEX = /^(09\d{9}|\+639\d{9})$/;
export const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const ADDRESS_REGEX = /^[A-Za-z0-9\s,.\-#]+$/;
export const NATIONALITY_REGEX = /^[A-Za-z\s-]+$/;
export const ROOM_TYPE_REGEX = /^[A-Za-z0-9\s-]+$/;
export const PLATE_REGEX = /^[A-Za-z0-9\s-]+$/;
export const FORBIDDEN_NOTE_CHARS = /[<>{}[\]\\|^`~$%*=+;]/;

// Validate a single field
export function validateField(field, value, allValues = {}) {
  const val = (value || '').toString().trim();

  switch (field) {
    case 'guestName':
    case 'checkedInBy': {
      if (field === 'guestName' && !val) return 'Guest name is required';
      if (!val) return null; // checkedInBy is optional
      if (val.length < 2 || val.length > 60) return 'Must be between 2 and 60 characters';
      if (!NAME_REGEX.test(val)) return 'Letters, spaces, period, hyphen, apostrophe only (no numbers/symbols)';
      return null;
    }

    case 'contactNumber': {
      if (!val) return null;
      if (!PHILIPPINE_PHONE_REGEX.test(val)) return 'Invalid Philippine mobile number (e.g. 09171234567 or +639XXXXXXXXX)';
      return null;
    }

    case 'email': {
      if (!val) return null;
      if (val.length > 100) return 'Email must not exceed 100 characters';
      if (/\s/.test(val) || !EMAIL_REGEX.test(val)) return 'Valid email format required (name@domain.tld)';
      return null;
    }

    case 'address': {
      if (!val) return null;
      if (val.length > 120) return 'Address must not exceed 120 characters';
      if (!ADDRESS_REGEX.test(val)) return 'Letters, numbers, spaces, comma, period, hyphen, and # only';
      return null;
    }

    case 'nationality': {
      if (!val) return null;
      if (val.length > 40) return 'Must not exceed 40 characters';
      if (!NATIONALITY_REGEX.test(val)) return 'Letters, spaces, hyphen only';
      return null;
    }

    case 'roomType': {
      if (!val) return 'Room type / number is required';
      if (val.length > 40) return 'Must not exceed 40 characters';
      if (!ROOM_TYPE_REGEX.test(val)) return 'Letters, numbers, spaces, hyphen only';
      return null;
    }

    case 'activityTitle': {
      if (!val) return 'Activity title is required';
      if (val.length > 60) return 'Must not exceed 60 characters';
      return null;
    }

    case 'plateNumber': {
      if (!val) return null;
      if (val.length > 12) return 'Plate number must not exceed 12 characters';
      if (!PLATE_REGEX.test(val)) return 'Letters, numbers, spaces, hyphen only';
      return null;
    }

    case 'adults': {
      const a = parseInt(val, 10);
      if (isNaN(a) || a < 0 || a > 50) return 'Whole number between 0 and 50';
      const c = parseInt(allValues.children || '0', 10) || 0;
      if (a + c < 1) return 'At least 1 adult or child required overall';
      return null;
    }

    case 'children': {
      const c = parseInt(val, 10);
      if (isNaN(c) || c < 0 || c > 50) return 'Whole number between 0 and 50';
      return null;
    }

    case 'pax': {
      const p = parseInt(val, 10);
      if (isNaN(p) || p < 1 || p > 100) return 'Pax must be between 1 and 100';
      return null;
    }

    case 'nights': {
      const n = parseInt(val, 10);
      if (isNaN(n) || n < 1 || n > 365) return 'Whole number between 1 and 365';
      return null;
    }

    case 'ratePerNight':
    case 'pricePerPax': {
      if (!val) return null;
      const num = parseFloat(val);
      if (isNaN(num) || num < 0 || num > 1000000) return 'Number between 0 and 1,000,000';
      if (!/^\d+(\.\d{1,2})?$/.test(val)) return 'Maximum 2 decimal places';
      return null;
    }

    case 'totalStay': {
      if (!val) return null;
      const num = parseFloat(val);
      if (isNaN(num) || num < 0 || num > 1000000) return 'Number between 0 and 1,000,000';
      if (!/^\d+(\.\d{1,2})?$/.test(val)) return 'Maximum 2 decimal places';
      return null;
    }

    case 'arrivalDate': {
      if (!val) return 'Arrival date is required';
      if (!isValidDateMMDDYY(val)) return 'Invalid date (use MM/DD/YY e.g. 10/02/26)';
      return null;
    }

    case 'departureDate': {
      if (!val) return null;
      if (!isValidDateMMDDYY(val)) return 'Invalid date (use MM/DD/YY e.g. 10/03/26)';
      if (allValues.arrivalDate && isValidDateMMDDYY(allValues.arrivalDate)) {
        const arr = parseDateMMDDYY(allValues.arrivalDate);
        const dep = parseDateMMDDYY(val);
        if (arr && dep && dep < arr) return 'Departure must not be earlier than arrival';
      }
      return null;
    }

    case 'note': {
      if (!val) return null;
      if (val.length > 200) return 'Must not exceed 200 characters';
      if (FORBIDDEN_NOTE_CHARS.test(val)) return 'Contains forbidden characters (< > { } [ ] \\ | ^ ` ~ $ % * = + ;)';
      if (/<[^>]*>|javascript:/i.test(val)) return 'HTML / scripts are not allowed';
      return null;
    }

    default:
      return null;
  }
}

// Validate entire form, returning map of field -> error string
export function validateEntireForm(form, recordType = 'Room') {
  const errors = {};

  const check = (field) => {
    const err = validateField(field, form[field], form);
    if (err) errors[field] = err;
  };

  check('guestName');
  check('contactNumber');
  check('email');
  check('address');
  check('nationality');
  check('arrivalDate');
  check('note');

  if (recordType === 'Room') {
    check('departureDate');
    check('nights');
    check('roomType');
    check('adults');
    check('children');
    check('plateNumber');
    check('ratePerNight');
    check('totalStay');
    check('checkedInBy');
  } else {
    check('activityTitle');
    check('pax');
    check('pricePerPax');
  }

  return errors;
}

// Clean string by collapsing multiple spaces
export function cleanSpacedString(str) {
  if (!str) return '';
  return str.toString().trim().replace(/\s+/g, ' ');
}

// Mask sensitive string (keeps last 4 characters)
export function maskSensitive(val) {
  if (!val || typeof val !== 'string') return '';
  const trimmed = val.trim();
  if (trimmed.length <= 4) return trimmed;
  const last4 = trimmed.slice(-4);
  return '*'.repeat(trimmed.length - 4) + last4;
}
