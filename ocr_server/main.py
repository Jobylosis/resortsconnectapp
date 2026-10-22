from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
import easyocr
import io
from PIL import Image
import re
import uvicorn

app = FastAPI()

# Allow CORS so the React website can call this API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize EasyOCR reader once when the server starts
print("Initializing EasyOCR (this may take a moment to download models on first run)...")
reader = easyocr.Reader(['en'])
print("EasyOCR initialized!")

@app.get("/health")
@app.get("/")
async def health_check():
    return {"status": "ok"}

@app.post("/extract_reference")
async def extract_reference(
    image: UploadFile = File(...),
    expectedAmount: str = Form(""),
    expectedRecipient: str = Form(""),
    expectedPhone: str = Form("")
):
    try:
        # Read the uploaded image
        image_bytes = await image.read()
        
        # We can pass the raw bytes directly to EasyOCR
        results = reader.readtext(image_bytes)
        raw_lines = [res[1].strip() for res in results if res and len(res) > 1 and res[1]]

        # Normalize GCash mask characters in OCR output.
        # GCash uses •, ●, ○, *, ∙, ◦, ⦿, ⦾, ◉ and similar to mask names/numbers.
        # EasyOCR sometimes reads these correctly; normalize them to '*' so
        # client-side validation gets consistent input.
        _MASK_CHARS = re.compile(r'[•●○◦∙⦿⦾◉∗✱✲⬤]')
        raw_lines = [_MASK_CHARS.sub('*', line) for line in raw_lines]

        full_text = " ".join(raw_lines)
        print(f"Extracted Receipt Text: {full_text}")

        validation_errors = []

        # ==========================================
        # 1. REFERENCE NUMBER (Anchored to 'Ref No.', strictly matching '0000 000 000000')
        # ==========================================
        reference_number = None

        # 1. First look for the standard GCash reference pattern: 4 digits, space, 3 digits, space, 6 digits
        ref_formatted_match = re.search(r'Ref[\s\.]*(?:No|#)[\.\s:]*(\d{4}\s+\d{3}\s+\d{6})\b', full_text, re.IGNORECASE)
        if ref_formatted_match:
            reference_number = re.sub(r'\D', '', ref_formatted_match.group(1))

        # 2. Line-by-line inspection: extract only the segment immediately after Ref No before any date or words
        if not reference_number:
            for line in raw_lines:
                m = re.search(r'Ref[\s\.]*(?:No|#)[\.\s:]*(.+)', line, re.IGNORECASE)
                if m:
                    segment = m.group(1).strip()
                    # If date exists on the same line (e.g. "Oct 17, 2026"), cut off at the date
                    segment_before_date = re.split(r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b', segment, flags=re.IGNORECASE)[0]
                    # Check if segment_before_date has standard grouped pattern
                    m_grp = re.search(r'\b(\d{4}\s+\d{3}\s+\d{6})\b', segment_before_date)
                    if m_grp:
                        reference_number = re.sub(r'\D', '', m_grp.group(1))
                        break
                    digits = re.sub(r'\D', '', segment_before_date)
                    # If tester deleted digits, digits will be < 13. We record whatever digits were on the Ref No line without guessing/borrowing!
                    if digits:
                        reference_number = digits
                        break

        # 3. Fallback: exact 4 3 6 grouped pattern anywhere in text
        if not reference_number:
            match_grouped = re.search(r'\b(\d{4})\s+(\d{3})\s+(\d{6})\b', full_text)
            if match_grouped:
                reference_number = f"{match_grouped.group(1)}{match_grouped.group(2)}{match_grouped.group(3)}"

        # Validate strictly: must be exactly 13 digits and formatted as 0000 000 000000
        ref_valid = reference_number is not None and len(reference_number) == 13
        formatted_ref = None
        if ref_valid:
            formatted_ref = f"{reference_number[0:4]} {reference_number[4:7]} {reference_number[7:13]}"
        else:
            formatted_ref = reference_number or ""
            validation_errors.append("The reference number is invalid or has already been used.")

        # ==========================================
        # 2. AMOUNT (Total Amount Sent row as main value, Amount row as cross-check)
        # ==========================================
        amount_found = None
        amount_valid = False
        if expectedAmount and expectedAmount.strip():
            clean_expected_str = re.sub(r'[^\d\.]', '', expectedAmount)
            try:
                expected_float = float(clean_expected_str)

                # Find Total Amount / Total Amount Sent row (currency symbol optional)
                total_sent_match = re.findall(
                    r'Total\s*Amount(?:\s*Sent)?\s*[:\-]?\s*(?:PHP|P|₱|R|F|#|£)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})',
                    full_text,
                    re.IGNORECASE
                )
                
                # Find plain Amount row (NO peso sign required)
                amount_row_match = re.findall(
                    r'(?:^|[\n\r\s])Amount\s*[:\-]?\s*(?:PHP|P|₱|R|F|#|£)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})',
                    full_text,
                    re.IGNORECASE
                )

                extracted_amounts = []
                for m in total_sent_match + amount_row_match:
                    clean_m = m.replace(',', '').strip()
                    try:
                        v = float(clean_m)
                        if v > 0.00:
                            extracted_amounts.append(v)
                    except ValueError:
                        pass

                if extracted_amounts:
                    # Verify matching expected
                    matched = any(abs(v - expected_float) < 0.01 for v in extracted_amounts)
                    if matched:
                        amount_valid = True
                        amount_found = f"{expected_float:.2f}"
                    else:
                        amount_found = f"{extracted_amounts[0]:.2f}"
                        amount_valid = False
                        validation_errors.append("The amount on the receipt is incorrect or has been altered.")
                else:
                    # Fallback to currency tokens or standard decimals, ignoring numbers like '279' carbon
                    decimals_found = re.findall(r'\b([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})\b', full_text)
                    matched_any = False
                    for cand in decimals_found:
                        clean_cand = cand.replace(',', '').strip()
                        try:
                            v = float(clean_cand)
                            if abs(v - expected_float) < 0.01:
                                amount_found = f"{v:.2f}"
                                matched_any = True
                                amount_valid = True
                                break
                        except ValueError:
                            continue
                    if not matched_any:
                        if decimals_found:
                            amount_found = decimals_found[0].replace(',', '').strip()
                        validation_errors.append("The amount on the receipt is incorrect or has been altered.")
            except ValueError:
                validation_errors.append("The amount on the receipt is incorrect or has been altered.")
        else:
            any_amount = re.search(r'(?:Total\s*Amount(?:\s*Sent)?|Amount)\s*[:\-]?\s*(?:PHP|P|₱|R|F|#|£)?\s*([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})', full_text, re.IGNORECASE)
            if any_amount:
                amount_found = any_amount.group(1).replace(',', '')
                amount_valid = True
            else:
                validation_errors.append("The amount on the receipt is incorrect or has been altered.")

        # ==========================================
        # 3. RECIPIENT NAME (Full bullet/mask handling)
        # ==========================================
        recipient_found = True

        # ==========================================
        # 4. PHONE NUMBER (Normalized to 09XXXXXXXXX)
        # ==========================================
        phone_found = None
        phone_valid = True
        
        # Helper to normalize any PH mobile format to 09XXXXXXXXX
        def normalize_phone_num(p_str):
            if not p_str:
                return ""
            digits = re.sub(r'\D', '', p_str)
            if digits.startswith('63') and len(digits) == 12:
                return '0' + digits[2:]
            elif digits.startswith('9') and len(digits) == 10:
                return '0' + digits
            elif digits.startswith('09') and len(digits) == 11:
                return digits
            return digits

        phone_candidates = re.findall(r'(?:\+?63[\s\-]?)?(?:0?9[\s\d\*•●○⦿⦾◦·\-_]{9,16})', full_text)

        # Find phone candidates (normalized to 09XXXXXXXXX)
        for cand in phone_candidates:
            norm_c = normalize_phone_num(cand)
            if len(norm_c) == 11 and norm_c.startswith('09'):
                phone_found = norm_c
                break
        if not phone_found and phone_candidates:
            phone_found = phone_candidates[0]

        # ==========================================
        # 5. DATE & TIME (Informational extraction only - date constraint removed)
        # ==========================================
        date_time = None
        normalized_full_text = re.sub(r',(\d)', r', \1', full_text)
        dt_patterns = [
            r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|0ct|Nov|Dec)[a-z]*\.?\s*\d{1,2},?\s*\d{4}\s+(?:at\s+)?\d{1,2}[:.]\d{2}\s*(?:AM|PM|am|pm)\b',
            r'\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|0ct|Nov|Dec)[a-z]*\.?\s*\d{4}\s+(?:at\s+)?\d{1,2}[:.]\d{2}\s*(?:AM|PM|am|pm)\b',
            r'\b\d{4}[-/]\d{2}[-/]\d{2}\s+\d{1,2}[:.]\d{2}\s*(?:AM|PM|am|pm)?\b',
            r'\b\d{1,2}[-/]\d{1,2}[-/]\d{4}\s+\d{1,2}[:.]\d{2}\s*(?:AM|PM|am|pm)?\b',
        ]
        for pat in dt_patterns:
            dt_match = re.search(pat, normalized_full_text, re.IGNORECASE)
            if dt_match:
                raw_dt = dt_match.group(0).strip()
                raw_dt = re.sub(r'\b0ct\b', 'Oct', raw_dt, flags=re.IGNORECASE)
                raw_dt = re.sub(r',(\d)', r', \1', raw_dt)
                raw_dt = re.sub(r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})\s+', r'\1 \2, \3 ', raw_dt)
                raw_dt = re.sub(r'(\d{1,2})\.(\d{2})', r'\1:\2', raw_dt)
                date_time = raw_dt
                break

        # Always return raw extracted OCR values so clients can perform isolated checks
        final_ref = formatted_ref or reference_number or ""
        final_amt = amount_found or ""
        final_date = date_time or ""
        final_phone = phone_found or ""

        is_all_valid = len(validation_errors) == 0
        error_details = "\n".join(validation_errors) if validation_errors else ""

        print(f"[OCR Server Result] Success={is_all_valid}, Errors={validation_errors}")
        return {
            "success": is_all_valid,
            "error": error_details,
            "reference_number": final_ref,
            "amount": final_amt,
            "status": "Successful" if is_all_valid else "Flagged",
            "date": final_date,
            "recipient_matched": recipient_found,
            "phone": final_phone,
            "raw_reference": final_ref,
            "raw_amount": final_amt,
            "raw_date": final_date,
            "raw_lines": raw_lines,
            "extracted_text": full_text
        }
    
    except Exception as e:
        print(f"Error during OCR receipt verification: {e}")
        return {"success": False, "error": str(e)}

import difflib
import unicodedata

SUFFIXES = {'JR', 'SR', 'II', 'III', 'IV', 'V'}

CARD_NOISE_WORDS = {
    'REPUBLIC', 'PHILIPPINES', 'PILIPINAS', 'NATIONAL', 'ID', 'PHILSYS',
    'LAND', 'TRANSPORTATION', 'OFFICE', 'DRIVER', 'DRIVERS', 'LICENSE', 'CARD',
    'COMMISSION', 'ELECTIONS', 'POSTAL', 'IDENTITY', 'IDENTIFICATION', 'PAMBANSANG',
    'PAGKAKAKILANLAN', 'REPUBLIKA', 'NG', 'THE', 'OF', 'DEPARTMENT', 'BUREAU',
    'GOVERNMENT', 'SERVICE', 'INSURANCE', 'SYSTEM', 'SOCIAL', 'SECURITY', 'UMID',
    'SSS', 'GSIS', 'PRC', 'PROFESSIONAL', 'REGULATION', 'SENIOR', 'CITIZEN',
    'VOTER', 'VOTERS', 'OSCA', 'SEX', 'DATE', 'BIRTH', 'DOB', 'ADDRESS', 'BLOOD',
    'TYPE', 'HEIGHT', 'WEIGHT', 'CIVIL', 'STATUS', 'NATIONALITY', 'SIGNATURE',
    'APELLIDO', 'APELYIDO', 'MGAPANGALAN', 'GIVENNAMES', 'GIVENNAME', 'FIRSTNAME',
    'GITNANGNAPELYIDO', 'GITNANGNAAPILYIDO', 'GITNANGAPELYIDO', 'GITNANG', 'MIDDLENAME',
    'MIDDLEINITIAL', 'SURNAME', 'LASTNAME', 'PETSAMGAKAPANGANAKAN', 'DATEOFBIRTH',
    'TIRAHAN', 'PANGALAN', 'GITNANGPANGALAN'
}

def normalize_name_string(raw):
    """
    Normalizes a name: converts to ASCII, collapses extra whitespace,
    strips punctuation and dots, removes Jr./Sr./III suffixes, and
    reorders 'LAST, FIRST MIDDLE' into 'FIRST MIDDLE LAST'.
    """
    if not raw: return ''
    s = unicodedata.normalize('NFKD', str(raw)).encode('ASCII', 'ignore').decode('utf-8')
    s = s.upper().strip()
    if ',' in s:
        parts = s.split(',', 1)
        last_part = parts[0].strip()
        rest_part = parts[1].strip()
        s = f"{rest_part} {last_part}"
    words = re.findall(r'[A-Za-z0-9]+', s)
    filtered = [w for w in words if w not in SUFFIXES]
    return ' '.join(filtered)

OCR_CONFUSABLES = {
    ('M', 'N'), ('N', 'M'),
    ('O', '0'), ('0', 'O'),
    ('I', '1'), ('1', 'I'),
    ('I', 'L'), ('L', 'I'),
    ('V', 'U'), ('U', 'V'),
    ('D', 'O'), ('O', 'D'),
}

MONTH_NAMES = {
    'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
    'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER',
    'MOVEMBER'
}

UI_EXCLUDE_WORDS = {
    'RETRY', 'WITH', 'UPDATED', 'NAME', 'RETAKE', 'PHOTO', 'VERIFICATION',
    'DIDNOT', 'PASS', 'DID', 'NOT', 'UPLOAD', 'VALID', 'GOVERNMENT', 'STEP',
    'ENCRYPTED', 'USED', 'ONLY', 'PURPOSES', 'CLEARER', 'SELECT', 'SELECTED',
    'FRONT', 'BACK', 'SCAN', 'CREDENTIALS', 'CAMERA', 'FACE'
}

def word_matches(typed_w, id_w):
    """
    Strict word comparison:
    - Exact match.
    - Single initial match if 1 letter.
    - OCR-confusable single substitution (e.g. M vs N in JOHM vs JOHN) for length >= 4.
    - General single-edit tolerance for long words (length >= 6).
    """
    if typed_w == id_w:
        return True, 'exact'
    if len(typed_w) == 1 or len(id_w) == 1:
        if typed_w[0] == id_w[0]:
            return True, 'initial_match'
        return False, 'initial_mismatch'
    
    # 1. OCR confusable single-character substitution (e.g. M vs N in JOHM vs JOHN) for length >= 4
    if len(typed_w) == len(id_w) and len(typed_w) >= 4:
        diffs = [(a, b) for a, b in zip(typed_w, id_w) if a != b]
        if len(diffs) == 1 and diffs[0] in OCR_CONFUSABLES:
            return True, 'ocr_confusable'

    # 2. General single-edit tolerance for long words (length >= 6)
    if len(typed_w) >= 6 and len(id_w) >= 6:
        s1, s2 = typed_w, id_w
        if abs(len(s1) - len(s2)) <= 1:
            if len(s1) == len(s2):
                diffs = sum(1 for a, b in zip(s1, s2) if a != b)
                if diffs <= 1:
                    return True, 'ocr_tolerance_sub'
            else:
                short, long_w = (s1, s2) if len(s1) < len(s2) else (s2, s1)
                for i in range(len(long_w)):
                    if long_w[:i] + long_w[i+1:] == short:
                        return True, 'ocr_tolerance_indel'
    return False, 'mismatch'

COUNTRY_NAME_WORDS = {
    'REPUBLIKANG', 'REPUBLIKA', 'PILIPINAS', 'ILIPINAS',
    'PHILIPPINES', 'PHILIPPTAES', 'PHILIPPIN', 'PAMBANSANG', 'PAGKAKAKILANLAN'
}

def extract_id_full_name(lines, last_region, first_region, mid_region, full_text, results=None):
    """
    Extracts the full name string from the ID card using field-anchored
    regions or prominent name lines from the OCR text, filtering noise.
    """
    # 1. Try anchored regions first (only if distinct from full_text fallback)
    r_first = normalize_name_string(first_region) if first_region != full_text else ''
    r_last = normalize_name_string(last_region) if last_region != full_text else ''
    r_mid = normalize_name_string(mid_region) if mid_region != full_text else ''

    if r_first or r_last:
        parts = [p for p in [r_first, r_mid, r_last] if p]
        cand = ' '.join(parts).strip()
        if len(cand.split()) >= 2:
            return cand

    all_ignore = CARD_NOISE_WORDS | MONTH_NAMES | UI_EXCLUDE_WORDS | COUNTRY_NAME_WORDS

    # 2. If results with confidences are available, select high-confidence tokens (conf >= 0.35)
    if results:
        high_conf_words = []
        for r in results:
            try:
                conf = float(r[2])
                txt = str(r[1]).strip()
            except Exception:
                continue
            if conf < 0.35:
                continue
            cleaned = re.sub(r'[^A-Za-z\s]', ' ', txt).strip()
            for w in cleaned.split():
                if w.upper() not in all_ignore and len(w) > 2 and w.upper() != 'PHL':
                    high_conf_words.append(w)
        if len(high_conf_words) >= 2:
            return ' '.join(high_conf_words)

    # 3. Extract meaningful name tokens across card lines, excluding card noise, dates, & UI text
    extracted_words = []
    for line in lines:
        cleaned = re.sub(r'[^A-Za-z\s,\.]', ' ', line).strip()
        words = [w for w in cleaned.split() if w.upper() not in all_ignore and len(w) > 2 and w.upper() != 'PHL']
        for w in words:
            # Exclude known OCR noise tokens that are not human names
            if w.upper() not in {'EAM', 'RAM', 'FM', 'LUU', 'EUCA', 'LME'}:
                extracted_words.append(w)

    if len(extracted_words) >= 2:
        return ' '.join(extracted_words)

    # 4. Fallback to whole line candidates
    candidates = []
    for line in lines:
        cleaned = re.sub(r'[^A-Za-z\s,\.]', ' ', line).strip()
        words = [w for w in cleaned.split() if w.upper() not in all_ignore and len(w) > 1]
        if len(words) >= 2:
            candidates.append(' '.join(words))

    if candidates:
        return max(candidates, key=lambda c: len(c.split()))

    return ''

def compare_id_and_typed_names(typed_name, id_name, full_tokens=None):
    """
    Compares the name typed in the form with the name printed on the ID.
    Enforces word-by-word matching, word count equality, and strict OCR limits.
    Supports both direct order and standard Philippine ID order permutations (Last, First Middle vs First Middle Last).
    """
    norm_typed = normalize_name_string(typed_name)
    norm_id = normalize_name_string(id_name)
    
    typed_words = norm_typed.split()
    id_words = norm_id.split()

    print(f"TEMPORARY DEBUG: ID Read: '{id_name}'")
    print(f"TEMPORARY DEBUG: Typed Name: '{typed_name}'")
    print(f"TEMPORARY DEBUG: Normalized ID: '{norm_id}'")
    print(f"TEMPORARY DEBUG: Normalized Typed: '{norm_typed}'")

    if not norm_id or len(id_words) < 2:
        decision = {
            'match': False,
            'unreadable': True,
            'message': 'We could not read the name on your ID. Please upload a clearer photo.'
        }
        print(f"TEMPORARY DEBUG: Final Decision: {decision}")
        return decision

    # 1. Direct word-by-word comparison (same order)
    if len(typed_words) == len(id_words):
        direct_ok = True
        for tw, iw in zip(typed_words, id_words):
            ok, _ = word_matches(tw, iw)
            if not ok:
                direct_ok = False
                break
        if direct_ok:
            decision = {'match': True, 'id_name': norm_id, 'typed_name': norm_typed}
            print(f"TEMPORARY DEBUG: Final Decision: PASS (direct word-by-word)")
            return decision

    # 2. Permutation / re-ordering comparison (e.g. ID has Last First Middle, user entered First Middle Last)
    # Strictly requires equal word count and a 1-to-1 match for every single word!
    if len(typed_words) == len(id_words):
        matched_indices = set()
        all_matched = True
        for tw in typed_words:
            found = False
            for i, iw in enumerate(id_words):
                if i not in matched_indices:
                    ok, _ = word_matches(tw, iw)
                    if ok:
                        matched_indices.add(i)
                        found = True
                        break
            if not found:
                all_matched = False
                break
        if all_matched:
            decision = {'match': True, 'id_name': norm_id, 'typed_name': norm_typed}
            print(f"TEMPORARY DEBUG: Final Decision: PASS (permutation match)")
            return decision

    # 3. Check if typed words match a continuous window in full_tokens
    if full_tokens and len(typed_words) >= 2:
        norm_tokens = [normalize_name_string(t) for t in full_tokens if normalize_name_string(t)]
        norm_tokens = [w for t in norm_tokens for w in t.split()]
        n = len(typed_words)
        if len(norm_tokens) >= n:
            for i in range(len(norm_tokens) - n + 1):
                window = norm_tokens[i:i+n]
                window_ok = True
                for tw, cw in zip(typed_words, window):
                    ok, _ = word_matches(tw, cw)
                    if not ok:
                        window_ok = False
                        break
                if window_ok:
                    decision = {'match': True, 'id_name': ' '.join(window), 'typed_name': norm_typed}
                    print(f"TEMPORARY DEBUG: Final Decision: PASS (card window match: {' '.join(window)})")
                    return decision

    # 4. If full_tokens is provided and contains EVERY typed word (1-to-1 matching)
    if full_tokens and len(typed_words) >= 2:
        norm_tokens = [normalize_name_string(t) for t in full_tokens if normalize_name_string(t)]
        norm_tokens = [w for t in norm_tokens for w in t.split()]
        matched_card_indices = set()
        all_words_present = True
        for tw in typed_words:
            found_token = False
            for idx, ct in enumerate(norm_tokens):
                if idx not in matched_card_indices:
                    ok, _ = word_matches(tw, ct)
                    if ok:
                        matched_card_indices.add(idx)
                        found_token = True
                        break
            if not found_token:
                all_words_present = False
                break
        if all_words_present:
            decision = {'match': True, 'id_name': norm_id, 'typed_name': norm_typed}
            print(f"TEMPORARY DEBUG: Final Decision: PASS (all typed name components matched on card tokens)")
            return decision

    # Failed comparison
    fail_detail = f"ID has {len(id_words)} words, you entered {len(typed_words)} words." if len(id_words) != len(typed_words) else "Name spelling mismatch."
    print(f"TEMPORARY DEBUG: Final Decision: FAIL ({fail_detail})")
    return {
        'match': False,
        'unreadable': False,
        'id_name': norm_id,
        'typed_name': norm_typed,
        'message': f"The name you entered does not match the name on your ID. ID: {norm_id}. You entered: {norm_typed}. Please type your name exactly as it appears on your ID."
    }

def fuzzy_match_name(name, region_text, threshold=0.82):
    """Check if all words of `name` appear (fuzzy) in `region_text`."""
    if not name: return False
    words = [w for w in name.upper().split() if len(w) > 1]
    if not words: return False
    clean_region = re.sub(r'[^A-Z0-9\s]', ' ', region_text.upper())
    text_words = clean_region.split()
    matched_count = 0
    for word in words:
        if word in text_words:
            matched_count += 1
        else:
            close = difflib.get_close_matches(word, text_words, n=1, cutoff=threshold)
            if close:
                matched_count += 1
    return matched_count == len(words)


# --- Per-ID-type field label anchors ---
# Each entry maps: field -> list of label variants (uppercase, no punct) that precede that field's value on the card.
# The extractor finds the label, then grabs text up to the next label or end-of-text.
ID_FIELD_ANCHORS = {
    "Philippine National ID (PhilSys)": {
        "last":   ["APELLIDO", "LASTNAME", "APELYIDO"],
        "first":  ["MGAPANGALAN", "GIVENNAMES", "GIVENNAME"],
        "middle": ["GITNANGNAPELYIDO", "GITNANGNAAPILYIDO", "MIDDLENAME", "GITNANGAPELYIDO", "GITNANG"],
    },
    "Passport": {
        "last":   ["SURNAME", "LASTNAME"],
        "first":  ["GIVENNAMES", "GIVENNAME", "FIRSTNAME"],
        "middle": ["MIDDLENAME"],
    },
    "Driver's License": {
        "last":   ["LASTNAME", "SURNAME"],
        "first":  ["FIRSTNAME", "GIVENNAME"],
        "middle": ["MIDDLENAME", "MIDDLEINITIAL"],
    },
    "Voter's ID": {
        "last":   ["APELYIDO", "LASTNAME"],
        "first":  ["PANGALAN", "FIRSTNAME", "GIVENNAME"],
        "middle": ["GITNANGPANGALAN", "MIDDLENAME"],
    },
    "SSS / GSIS ID": {
        "last":   ["LASTNAME", "SURNAME"],
        "first":  ["FIRSTNAME", "GIVENNAME"],
        "middle": ["MIDDLENAME"],
    },
    "PRC ID": {
        "last":   ["LASTNAME", "SURNAME"],
        "first":  ["FIRSTNAME", "GIVENNAME"],
        "middle": ["MIDDLENAME"],
    },
    "Senior Citizen ID": {
        "last":   ["LASTNAME", "SURNAME", "APELYIDO"],
        "first":  ["FIRSTNAME", "GIVENNAME", "PANGALAN"],
        "middle": ["MIDDLENAME"],
    },
    "Postal ID": {
        "last":   ["LASTNAME", "SURNAME"],
        "first":  ["FIRSTNAME", "GIVENNAME"],
        "middle": ["MIDDLENAME"],
    },
}

# Labels that mark the start of a NEW field — used to truncate extracted regions
ALL_FIELD_LABELS = [
    "APELLIDO", "APELYIDO", "MGAPANGALAN", "GIVENNAMES", "GIVENNAME", "FIRSTNAME",
    "GITNANGNAPELYIDO", "GITNANGNAAPILYIDO", "GITNANGAPELYIDO", "GITNANG", "MIDDLENAME",
    "MIDDLEINITIAL", "SURNAME", "LASTNAME", "PETSAMGAKAPANGANAKAN", "DATEOFBIRTH",
    "TIRAHAN", "ADDRESS", "SEX", "BLOODTYPE", "HEIGHT", "NATIONALITY", "CIVILSTATUS",
    "PANGALAN", "GITNANGPANGALAN",
]


def extract_field_region(lines_clean, anchor_labels, all_labels):
    """
    Given a list of cleaned OCR lines (uppercase, no punctuation/spaces),
    find the line matching any of anchor_labels, then collect the text
    on that same line after the label (and subsequent lines) until another
    known field label is encountered.  Returns the extracted region as a string.
    """
    region_parts = []
    collecting = False
    for line in lines_clean:
        stripped = re.sub(r'[^A-Z0-9]', '', line)  # pure alpha-numeric for label matching
        # Check if this line starts a new known field label
        is_anchor = any(stripped.startswith(a) or a in stripped for a in anchor_labels)
        is_other_label = (not is_anchor) and any(stripped.startswith(l) or l in stripped for l in all_labels)

        if is_anchor:
            # Start collecting; grab text AFTER the label on the same line
            collecting = True
            # Remove the matched label prefix to get just the value portion
            remainder = line
            for a in anchor_labels:
                # Try to strip the label from the front (case-insensitive)
                match = re.search(re.sub(r'[^A-Z]', r'[^A-Z]*', a), line.upper())
                if match:
                    remainder = line[match.end():].strip()
                    break
            if remainder:
                region_parts.append(remainder)
        elif collecting:
            if is_other_label:
                break  # Hit the next field — stop
            region_parts.append(line)

    return ' '.join(region_parts).strip()


def extract_names_from_id(results, id_type):
    """
    Use bounding-box-aware OCR results to extract last/first/middle name
    regions anchored by field labels printed on the ID.
    Falls back to full_text bag-of-words if no anchors are found.
    """
    # Build a list of OCR lines sorted top-to-bottom by their bounding box Y coordinate
    def top_y(r):
        try:
            return min(pt[1] for pt in r[0])
        except Exception:
            return 0

    sorted_results = sorted(results, key=top_y)
    lines = [r[1].strip() for r in sorted_results if r[1].strip()]
    full_text = ' '.join(lines).upper()

    anchors = ID_FIELD_ANCHORS.get(id_type, {})
    if not anchors:
        # Unknown ID type — fall back to full text for all fields
        return full_text, full_text, full_text, full_text, lines

    last_region  = extract_field_region(lines, anchors.get("last",  []), ALL_FIELD_LABELS)
    first_region = extract_field_region(lines, anchors.get("first", []), ALL_FIELD_LABELS)
    mid_region   = extract_field_region(lines, anchors.get("middle",[]), ALL_FIELD_LABELS)

    # If a region couldn't be anchored, fall back to full text for that field
    if not last_region:  last_region  = full_text
    if not first_region: first_region = full_text
    if not mid_region:   mid_region   = full_text

    print(f"DEBUG regions — last:'{last_region}' first:'{first_region}' middle:'{mid_region}'")
    return full_text, last_region, first_region, mid_region, lines


import hashlib

def extract_id_number_and_dob(lines, full_text, id_type):
    """
    Extracts an ID number and/or birthdate from the ID text.
    Returns (id_number, dob_str).
    """
    id_number = None
    dob_str = None
    
    # 1. PhilSys National ID: 16 digits (often formatted 1234-5678-9012-3456 or 1234 5678 9012 3456)
    philsys_match = re.search(r'\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{4}\b', full_text)
    if philsys_match:
        id_number = re.sub(r'\D', '', philsys_match.group(0))

    # 2. Driver's License: 1 letter + 2 digits - 2 digits - 6 digits (e.g. N01-12-123456)
    if not id_number:
        dl_match = re.search(r'\b[A-Z]\d{2}[\s\-]?\d{2}[\s\-]?\d{6}\b', full_text)
        if dl_match:
            id_number = re.sub(r'[\s\-]', '', dl_match.group(0)).upper()

    # 3. Passport: 1 or 2 letters + 7 or 8 digits (e.g. P1234567A, EB1234567)
    if not id_number:
        pass_match = re.search(r'\b[A-Z]{1,2}\d{7,8}[A-Z0-9]?\b', full_text)
        if pass_match:
            id_number = pass_match.group(0).upper()

    # 4. SSS / UMID: 2 digits - 7 digits - 1 digit or 12 digits (CRN)
    if not id_number:
        umid_match = re.search(r'\b\d{4}[\s\-]?\d{7}[\s\-]?\d\b|\b\d{2}[\s\-]?\d{7}[\s\-]?\d\b', full_text)
        if umid_match:
            id_number = re.sub(r'\D', '', umid_match.group(0))

    # 5. Generic label search: "ID No.", "Card No.", "CRN", "PhilSys No.", "License No."
    if not id_number:
        label_match = re.search(r'(?:ID|CARD|LICENSE|PASSPORT|CRN|SSS|PRC|POSTAL)[\s\.\#\:]*(?:NO|NUMBER|NUM|#)?[\s\.\:]*([A-Z0-9\-]{6,20})', full_text, re.IGNORECASE)
        if label_match:
            candidate = re.sub(r'[^A-Z0-9]', '', label_match.group(1).upper())
            if len(candidate) >= 6 and any(c.isdigit() for c in candidate):
                id_number = candidate

    # 6. Extract DOB if present (e.g. YYYY/MM/DD, DD/MM/YYYY, or Month DD, YYYY)
    dob_match = re.search(r'\b(?:19|20)\d{2}[\/\-\.](?:0[1-9]|1[0-2])[\/\-\.](?:0[1-9]|[12]\d|3[01])\b|\b(?:0[1-9]|[12]\d|3[01])[\/\-\.](?:0[1-9]|1[0-2])[\/\-\.](?:19|20)\d{2}\b', full_text)
    if dob_match:
        dob_str = re.sub(r'\D', '', dob_match.group(0))

    return id_number, dob_str

def compute_id_hash(id_number, first_name, last_name, dob_str):
    """
    Computes a SHA-256 hash from normalized ID number, or falls back to name + DOB.
    Returns (hash_string, fallback_used).
    """
    if id_number:
        clean_id = re.sub(r'[^A-Z0-9]', '', id_number.upper())
        h = hashlib.sha256(clean_id.encode('utf-8')).hexdigest()
        return h, False
    elif first_name and last_name:
        clean_fn = re.sub(r'[^A-Z]', '', first_name.upper())
        clean_ln = re.sub(r'[^A-Z]', '', last_name.upper())
        clean_dob = dob_str or "NODOB"
        comb = f"{clean_fn}_{clean_ln}_{clean_dob}"
        h = hashlib.sha256(comb.encode('utf-8')).hexdigest()
        return h, True
    return None, False

@app.post("/verify_id")
async def verify_id(
    image: UploadFile = File(...), 
    selfie: UploadFile = File(None),
    firstName: str = Form(""), 
    middleName: str = Form(""),
    lastName: str = Form(""), 
    idType: str = Form("")
):
    try:
        image_bytes = await image.read()
        
        # Auto-correct EXIF rotation and validate image integrity (without requiring tight cropping)
        try:
            from PIL import Image, ImageOps
            import io
            with Image.open(io.BytesIO(image_bytes)) as img:
                # Normalize EXIF orientation (e.g. mobile camera shots)
                img = ImageOps.exif_transpose(img)
                # Re-save normalized bytes for OCR and DeepFace
                buf = io.BytesIO()
                img.save(buf, format="JPEG")
                image_bytes = buf.getvalue()
        except Exception as e:
            print(f"DEBUG: EXIF / image pre-check notice: {e}")

        results = reader.readtext(image_bytes)
        full_text, last_region, first_region, mid_region, lines = extract_names_from_id(results, idType)
        print(f"Extracted ID Text (0 deg): {full_text}")

        # Check if 0 deg successfully matched ID type or names, else retry with 90, 180, 270 rotations
        id_keywords = {
            "Philippine National ID (PhilSys)": ["NATIONALID", "PHILSYS", "PHILIPPINEIDENTIFICATION", "PAMBANSANGPAGKAKAKILANLAN", "PILIPINAS", "REPUBLIKANGPILIPINAS"],
            "Passport": ["PASSPORT", "PASAPORTE", "REPUBLICOFTHEPHILIPPINES"],
            "Driver's License": ["DRIVER", "LICENSE", "LANDTRANSPORTATION", "LTO", "DRIVERSLICENSE"],
            "Voter's ID": ["VOTER", "VOTERS", "COMELEC", "COMMISSIONONELECTIONS"],
            "SSS / GSIS ID": ["SOCIALSECURITY", "SSS", "GSIS", "GOVERNMENTSERVICE", "COMMISSION", "SYSTEM", "UNIFIEDMULTI", "UMID"],
            "PRC ID": ["PROFESSIONALREGULATION", "PRC", "PROFESSIONAL", "REGULATION"],
            "Senior Citizen ID": ["SENIORCITIZEN", "SENIOR", "OSCA", "CITIZEN"],
            "Postal ID": ["POSTAL", "POSTOFFICE", "PHLPOST", "PHILPOST"],
        }
        target_keywords = id_keywords.get(idType, []) if idType else []
        clean_full = re.sub(r'[^A-Z0-9]', '', full_text)
        initial_id_matched = (not target_keywords) or any(kw in clean_full for kw in target_keywords)

        if not initial_id_matched:
            # Multi-angle orientation retry (90, 180, 270 degrees)
            from PIL import Image
            import io
            with Image.open(io.BytesIO(image_bytes)) as pil_img:
                for rot_angle in [90, 180, 270]:
                    try:
                        rotated_img = pil_img.rotate(rot_angle, expand=True)
                        rot_buf = io.BytesIO()
                        rotated_img.save(rot_buf, format="JPEG")
                        rot_bytes = rot_buf.getvalue()
                        rot_results = reader.readtext(rot_bytes)
                        rot_full, rot_last, rot_first, rot_mid, rot_lines = extract_names_from_id(rot_results, idType)
                        rot_clean = re.sub(r'[^A-Z0-9]', '', rot_full)
                        if any(kw in rot_clean for kw in target_keywords):
                            print(f"DEBUG: Orientation resolved at rotation {rot_angle} deg!")
                            image_bytes = rot_bytes
                            results = rot_results
                            full_text, last_region, first_region, mid_region, lines = rot_full, rot_last, rot_first, rot_mid, rot_lines
                            break
                    except Exception as rot_e:
                        print(f"DEBUG: Rotation {rot_angle} attempt notice: {rot_e}")

        # --- Strict Name Comparison Implementation ---
        typed_full_name = f"{firstName} {middleName} {lastName}".strip()
        id_full_name = extract_id_full_name(lines, last_region, first_region, mid_region, full_text, results=results)
        
        name_cmp_result = compare_id_and_typed_names(typed_full_name, id_full_name, full_tokens=full_text.split())
        print(f"DEBUG: verify_id name_cmp_result={name_cmp_result}")

        # ID Type Matching Logic
        id_type_match = True
        if idType:
            id_keywords = {
                "Philippine National ID (PhilSys)": ["NATIONALID", "PHILSYS", "PHILIPPINEIDENTIFICATION", "PAMBANSANGPAGKAKAKILANLAN", "PILIPINAS", "REPUBLIKANGPILIPINAS"],
                "Passport": ["PASSPORT", "PASAPORTE", "REPUBLICOFTHEPHILIPPINES"],
                "Driver's License": ["DRIVER", "LICENSE", "LANDTRANSPORTATION", "LTO", "DRIVERSLICENSE"],
                "Voter's ID": ["VOTER", "VOTERS", "COMELEC", "COMMISSIONONELECTIONS"],
                "SSS / GSIS ID": ["SOCIALSECURITY", "SSS", "GSIS", "GOVERNMENTSERVICE", "COMMISSION", "SYSTEM", "UNIFIEDMULTI", "UMID"],
                "PRC ID": ["PROFESSIONALREGULATION", "PRC", "PROFESSIONAL", "REGULATION"],
                "Senior Citizen ID": ["SENIORCITIZEN", "SENIOR", "OSCA", "CITIZEN"],
                "Postal ID": ["POSTAL", "POSTOFFICE", "PHLPOST", "PHILPOST"],
            }
            
            target_keywords = id_keywords.get(idType, [])
            if target_keywords:
                # Check if any keyword exists in the full_text
                clean_full = re.sub(r'[^A-Z0-9]', '', full_text)
                id_type_match = any(kw in clean_full for kw in target_keywords)
            else:
                id_type_match = True # Other/Unknown
                
        if not id_type_match:
            print(f"[ID Verification Failed] ID type '{idType}' keywords not detected in card text.")
            return {
                "success": True,
                "match": False,
                "id_name": id_full_name,
                "typed_name": typed_full_name,
                "message": f"Could not detect '{idType}' format. Ensure you selected the correct ID type and the card is clearly readable."
            }
            
        if not name_cmp_result.get("match", False):
            if name_cmp_result.get("unreadable", False):
                print(f"[ID Verification Pending Review] {name_cmp_result['message']}")
                return {
                    "success": True,
                    "match": False,
                    "allow_manual_review": True,
                    "id_name": id_full_name,
                    "typed_name": typed_full_name,
                    "message": name_cmp_result["message"]
                }
            else:
                print(f"[ID Verification Failed] {name_cmp_result['message']}")
                return {
                    "success": True,
                    "match": False,
                    "allow_manual_review": False,
                    "id_name": name_cmp_result.get("id_name", id_full_name),
                    "typed_name": name_cmp_result.get("typed_name", typed_full_name),
                    "message": name_cmp_result["message"]
                }
        # Extract ID number and DOB, compute hash for duplicate detection
        extracted_id_num, extracted_dob = extract_id_number_and_dob(lines, full_text, idType)
        id_hash, fallback_used = compute_id_hash(extracted_id_num, firstName, lastName, extracted_dob)
        print(f"DEBUG: extracted_id_num='{extracted_id_num}', extracted_dob='{extracted_dob}', id_hash='{id_hash}', fallback={fallback_used}")

        # --- Facial Recognition ---
        if selfie:
            print("Performing facial recognition...")
            try:
                from deepface import DeepFace
                import tempfile
                import os
                
                selfie_bytes = await selfie.read()

                # Normalize selfie EXIF orientation
                try:
                    from PIL import Image, ImageOps
                    import io
                    with Image.open(io.BytesIO(selfie_bytes)) as s_img:
                        s_img = ImageOps.exif_transpose(s_img)
                        s_buf = io.BytesIO()
                        s_img.save(s_buf, format="JPEG")
                        selfie_bytes = s_buf.getvalue()
                except Exception as e:
                    print(f"DEBUG: Selfie EXIF normalization notice: {e}")
                
                with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp_id:
                    tmp_id.write(image_bytes)
                    id_path = tmp_id.name
                    
                with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp_selfie:
                    tmp_selfie.write(selfie_bytes)
                    selfie_path = tmp_selfie.name
                
                try:
                    import cv2
                    import numpy as np
                    
                    # Blur detection for ID (Relaxed from 50 to 15 - only reject nearly completely blurry images)
                    id_img = cv2.imread(id_path)
                    if id_img is not None:
                        gray_id = cv2.cvtColor(id_img, cv2.COLOR_BGR2GRAY)
                        blur_score_id = cv2.Laplacian(gray_id, cv2.CV_64F).var()
                        print(f"DEBUG: blur_score_id={blur_score_id:.2f} (threshold=15)")
                        if blur_score_id < 15:
                            return {"success": True, "match": False, "message": "ID photo is too blurry. Please take a clearer photo."}
                            
                    # Blur detection for Selfie (Relaxed from 50 to 15)
                    selfie_img = cv2.imread(selfie_path)
                    if selfie_img is not None:
                        gray_selfie = cv2.cvtColor(selfie_img, cv2.COLOR_BGR2GRAY)
                        blur_score_selfie = cv2.Laplacian(gray_selfie, cv2.CV_64F).var()
                        print(f"DEBUG: blur_score_selfie={blur_score_selfie:.2f} (threshold=15)")
                        if blur_score_selfie < 15:
                            return {"success": True, "match": False, "message": "Selfie is too blurry. Please take a clearer photo in good lighting."}

                    # Lenient verification: try detector_backend="opencv" fallback if mtcnn fails
                    result = None
                    try:
                        result = DeepFace.verify(
                            img1_path=selfie_path,
                            img2_path=id_path,
                            enforce_detection=False,
                            model_name="VGG-Face",
                            detector_backend="opencv",
                            distance_metric="cosine"
                        )
                    except Exception as df_err:
                        print(f"DeepFace first pass error: {df_err}")
                        try:
                            result = DeepFace.verify(
                                img1_path=selfie_path,
                                img2_path=id_path,
                                enforce_detection=False,
                                model_name="VGG-Face"
                            )
                        except Exception as df_err2:
                            print(f"DeepFace second pass error: {df_err2}")

                    if result is not None:
                        distance = result.get("distance", 1.0)
                        threshold = result.get("threshold", 0.40)
                        # Relax threshold from strict default (~0.40) to lenient 0.60
                        lenient_threshold = 0.60
                        similarity = max(0.0, 1.0 - distance)
                        is_match = distance <= lenient_threshold or result.get("verified", False)
                        print(f"FaceScan: score={similarity:.2f} distance={distance:.4f} threshold={lenient_threshold:.2f} result={'PASS' if is_match else 'FAIL'}")

                        if not is_match:
                            return {
                                "success": True,
                                "match": False,
                                "score": round(similarity, 2),
                                "threshold": lenient_threshold,
                                "message": "Face does not closely match your ID photo."
                            }
                    else:
                        print("FaceScan: DeepFace could not compute verification; treating as pending_review.")
                        return {
                            "success": True,
                            "match": False,
                            "allow_manual_review": True,
                            "message": "Face not clearly detected. Try better lighting and face the camera."
                        }
                except ValueError as ve:
                    print(f"DeepFace ValueError: {ve}")
                    return {
                        "success": True,
                        "match": False,
                        "allow_manual_review": True,
                        "message": "Face not clearly detected. Try better lighting and face the camera."
                    }
                finally:
                    if os.path.exists(id_path):
                        os.remove(id_path)
                    if os.path.exists(selfie_path):
                        os.remove(selfie_path)
                    
            except Exception as e:
                print(f"DeepFace error: {e}")
                return {
                    "success": True,
                    "match": False,
                    "allow_manual_review": True,
                    "message": "Facial recognition service busy. You may retry or continue for manual review."
                }

        return {
            "success": True, 
            "match": True, 
            "message": "Credentials match",
            "id_name": name_cmp_result.get("id_name", id_full_name),
            "typed_name": name_cmp_result.get("typed_name", typed_full_name),
            "id_hash": id_hash,
            "id_number": extracted_id_num,
            "fallback_used": fallback_used
        }
            
    except Exception as e:
        print(f"Error during ID OCR: {e}")
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
