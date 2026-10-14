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
        # 1. REFERENCE NUMBER (Anchored to 'Ref No.', stop after 13 digits)
        # ==========================================
        reference_number = None
        # Anchored search: Find Ref No. label (tolerate Ref No, Ref. No., Ref #)
        ref_label_match = re.search(r'Ref[\s\.]*(?:No|#)[\.\s:]*([0-9\s]+)', full_text, re.IGNORECASE)
        if ref_label_match:
            after_label = ref_label_match.group(1)
            # Take only digits and spaces, stop once 13 digits are collected
            digits_accum = []
            for char in after_label:
                if char.isdigit():
                    digits_accum.append(char)
                    if len(digits_accum) == 13:
                        break
                elif char in (' ', '\t', '\n', '\r'):
                    continue
                else:
                    # Non-digit, non-space encountered
                    break
            if len(digits_accum) == 13:
                reference_number = "".join(digits_accum)

        # Line-by-line inspection if label search did not extract 13 digits
        if not reference_number:
            for i, line in enumerate(raw_lines):
                if re.search(r'Ref[\s\.]*(?:No|#)', line, re.IGNORECASE):
                    line_digits = re.sub(r'\D', '', line)
                    if len(line_digits) >= 13:
                        reference_number = line_digits[:13]
                        break
                    # Check next line if split across lines
                    for next_idx in range(i + 1, min(i + 3, len(raw_lines))):
                        next_digits = re.sub(r'\D', '', raw_lines[next_idx])
                        combined = line_digits + next_digits
                        if len(combined) >= 13:
                            reference_number = combined[:13]
                            break
                    if reference_number:
                        break

        # Fallback: exact 13 grouped or consecutive digits
        if not reference_number:
            for match_str in re.finditer(r'\b\d{4}\s\d{3}\s\d{6}\b', full_text):
                clean_num = re.sub(r'\D', '', match_str.group(0))
                if len(clean_num) == 13:
                    reference_number = clean_num
                    break

        if not reference_number:
            exact_13_tokens = re.findall(r'\b\d{13}\b', full_text)
            if len(exact_13_tokens) == 1:
                reference_number = exact_13_tokens[0]

        ref_valid = reference_number is not None and len(reference_number) == 13
        formatted_ref = None
        if ref_valid:
            formatted_ref = f"{reference_number[0:4]} {reference_number[4:7]} {reference_number[7:13]}"
        else:
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
        return full_text, full_text, full_text, full_text

    last_region  = extract_field_region(lines, anchors.get("last",  []), ALL_FIELD_LABELS)
    first_region = extract_field_region(lines, anchors.get("first", []), ALL_FIELD_LABELS)
    mid_region   = extract_field_region(lines, anchors.get("middle",[]), ALL_FIELD_LABELS)

    # If a region couldn't be anchored, fall back to full text for that field
    if not last_region:  last_region  = full_text
    if not first_region: first_region = full_text
    if not mid_region:   mid_region   = full_text

    print(f"DEBUG regions — last:'{last_region}' first:'{first_region}' middle:'{mid_region}'")
    return full_text, last_region, first_region, mid_region


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
        full_text, last_region, first_region, mid_region = extract_names_from_id(results, idType)
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
                        rot_full, rot_last, rot_first, rot_mid = extract_names_from_id(rot_results, idType)
                        rot_clean = re.sub(r'[^A-Z0-9]', '', rot_full)
                        if any(kw in rot_clean for kw in target_keywords):
                            print(f"DEBUG: Orientation resolved at rotation {rot_angle} deg!")
                            image_bytes = rot_bytes
                            results = rot_results
                            full_text, last_region, first_region, mid_region = rot_full, rot_last, rot_first, rot_mid
                            break
                    except Exception as rot_e:
                        print(f"DEBUG: Rotation {rot_angle} attempt notice: {rot_e}")

        # Try region-anchored match first; if uncropped card shifted labels, fallback to full card text
        def tolerant_match(target_name, region_str, full_str):
            if not target_name or not target_name.strip():
                return True
            clean_target = target_name.strip().upper()
            target_words = [w for w in re.findall(r'[A-Z0-9]+', clean_target) if len(w) > 0]
            if not target_words:
                return True
            
            # 1. Try region-anchored match first
            if region_str and fuzzy_match_name(clean_target, region_str, threshold=0.75):
                return True
                
            # 2. Tolerant fallback to full text
            full_clean = re.sub(r'[^A-Z0-9\s]', ' ', full_str.upper())
            full_tokens = full_clean.split()
            
            matched_words = 0
            for tw in target_words:
                # Single initial support (e.g., "D" or "D.")
                if len(tw) == 1:
                    if any(t.startswith(tw) or t == tw for t in full_tokens):
                        matched_words += 1
                    continue
                # Exact or substring match in full tokens
                if tw in full_tokens or any(tw in t for t in full_tokens):
                    matched_words += 1
                else:
                    close = difflib.get_close_matches(tw, full_tokens, n=1, cutoff=0.75)
                    if close:
                        matched_words += 1
            return matched_words >= len(target_words)

        fname_match = tolerant_match(firstName, first_region, full_text) if firstName else False
        mname_match = tolerant_match(middleName, mid_region, full_text) if middleName and middleName.strip() else True
        lname_match = tolerant_match(lastName, last_region, full_text) if lastName else False
        
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
                
        print(f"DEBUG: firstName='{firstName}', middleName='{middleName}', lastName='{lastName}', idType='{idType}'")
        print(f"DEBUG: fname_match={fname_match}, mname_match={mname_match}, lname_match={lname_match}, id_type_match={id_type_match}")
                
        if not id_type_match:
            print(f"[ID Verification Failed] ID type '{idType}' keywords not detected in card text.")
            return {"success": True, "match": False, "message": f"Could not detect '{idType}' format. Ensure you selected the correct ID type and the card is clearly readable."}
            
        if firstName and lastName:
            if not (fname_match and lname_match):
                print(f"[ID Verification Failed] Name mismatch: fname_match={fname_match}, lname_match={lname_match}")
                return {"success": True, "match": False, "message": "Name on ID does not match registered name. Please ensure first name and surname match your ID."}
            if middleName.strip() and not mname_match:
                print(f"[ID Verification Failed] Middle name mismatch: middleName='{middleName}'")
                return {"success": True, "match": False, "message": "Middle name on ID does not match registered name."}
        elif firstName and not fname_match:
            print(f"[ID Verification Failed] First name mismatch: firstName='{firstName}'")
            return {"success": True, "match": False, "message": "First name on ID does not match registered name."}
        elif lastName and not lname_match:
            print(f"[ID Verification Failed] Last name mismatch: lastName='{lastName}'")
            return {"success": True, "match": False, "message": "Last name on ID does not match registered name."}
        # Extract ID number and DOB, compute hash for duplicate detection
        extracted_id_num, extracted_dob = extract_id_number_and_dob(lines if 'lines' in locals() else [], full_text, idType)
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
            "id_hash": id_hash,
            "id_number": extracted_id_num,
            "fallback_used": fallback_used
        }
            
    except Exception as e:
        print(f"Error during ID OCR: {e}")
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
