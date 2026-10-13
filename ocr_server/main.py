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
        full_text = " ".join(raw_lines)
        print(f"Extracted Receipt Text: {full_text}")

        validation_errors = []

        # ==========================================
        # 1. REFERENCE NUMBER (Strictly exactly 13 digits)
        # ==========================================
        reference_number = None
        # Check explicit Ref No label first
        ref_label_match = re.search(r'Ref[\s\.]*No[\.\s:]*([0-9\s]{13,30})', full_text, re.IGNORECASE)
        if ref_label_match:
            digits_in_label = re.sub(r'\D', '', ref_label_match.group(1))
            if len(digits_in_label) == 13:
                reference_number = digits_in_label

        # Line-by-line inspection if not yet matched
        if not reference_number:
            for i, line in enumerate(raw_lines):
                if re.search(r'Ref[\s\.]*No', line, re.IGNORECASE):
                    line_digits = re.sub(r'\D', '', line)
                    if len(line_digits) == 13:
                        reference_number = line_digits
                        break
                    # Check next line if split across 2 lines
                    for next_idx in range(i + 1, min(i + 3, len(raw_lines))):
                        next_digits = re.sub(r'\D', '', raw_lines[next_idx])
                        combined = line_digits + next_digits
                        if len(combined) == 13:
                            reference_number = combined
                            break
                    if reference_number:
                        break

        # Fallback: check isolated 13 consecutive digits token in full text
        if not reference_number:
            exact_13_tokens = re.findall(r'\b\d{13}\b', full_text)
            if len(exact_13_tokens) == 1:
                reference_number = exact_13_tokens[0]

        # Spaced 13 digits fallback (e.g. 1234 567 890123)
        if not reference_number:
            for match_str in re.finditer(r'\b(?:\d[\s]*){13}\b', full_text):
                clean_num = re.sub(r'\D', '', match_str.group(0))
                if len(clean_num) == 13:
                    reference_number = clean_num
                    break

        if not reference_number or len(reference_number) != 13:
            validation_errors.append("Reference Number must strictly be exactly 13 digits. Missing or tampered.")

        # ==========================================
        # 2. AMOUNT & TOTAL AMOUNT (Must match expected payment exactly down to the centavo)
        # ==========================================
        amount_found = None
        if expectedAmount and expectedAmount.strip():
            clean_expected_str = re.sub(r'[^\d\.]', '', expectedAmount)
            try:
                expected_float = float(clean_expected_str)

                # Find all explicit labeled Amount and Total Amount entries
                labeled_amount_matches = re.findall(
                    r'(?:Amount|Total\s*Amount|Total)\s*[:\-]?\s*(?:PHP|P|₱)?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))',
                    full_text,
                    re.IGNORECASE
                )
                
                # Also find amounts prefixed by currency symbols PHP/P/₱
                currency_amount_matches = re.findall(
                    r'(?:PHP|P|₱)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))',
                    full_text,
                    re.IGNORECASE
                )

                # Combine labeled and currency amounts (excluding 0.00 fees)
                checked_values = []
                for m in labeled_amount_matches + currency_amount_matches:
                    val_clean = m.replace(',', '').strip()
                    try:
                        v = float(val_clean)
                        if v > 0.00:  # Ignore 0.00 fee / charge lines
                            checked_values.append(v)
                    except ValueError:
                        pass

                if checked_values:
                    # STRICT CHECK: If any detected amount tied to Amount / Total Amount does not match expected_float, flag as discrepancy
                    has_discrepancy = False
                    for val in checked_values:
                        if abs(val - expected_float) >= 0.01:
                            has_discrepancy = True
                            validation_errors.append(f"Amount discrepancy detected: Found PHP {val:.2f} which does not match expected PHP {expected_float:.2f} (possible edit/tampering).")
                            break

                    if not has_discrepancy:
                        amount_found = f"{expected_float:.2f}"
                else:
                    # Fallback to general decimal tokens if no labels or currency symbols were read
                    all_decimals = re.findall(r'\b([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2}|[0-9]+\.[0-9]{2})\b', full_text)
                    matched_any = False
                    for candidate in all_decimals:
                        clean_cand = candidate.replace(',', '').strip()
                        try:
                            cand_val = float(clean_cand)
                            if abs(cand_val - expected_float) < 0.01:
                                amount_found = f"{cand_val:.2f}"
                                matched_any = True
                                break
                        except ValueError:
                            continue
                    if not matched_any:
                        validation_errors.append(f"Amount discrepancy: Expected PHP {expected_float:.2f} was not found on receipt or was modified.")
            except ValueError:
                validation_errors.append(f"Invalid expected amount parameter: {expectedAmount}")
        else:
            # If no expected amount passed, verify that a valid currency amount format is present
            any_amount = re.search(r'(?:PHP|P|₱|Amount:?|Total:?)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{2})|[0-9]+(?:\.[0-9]{2}))', full_text, re.IGNORECASE)
            if any_amount:
                amount_found = any_amount.group(1).replace(',', '')
            else:
                validation_errors.append("Payment amount not found on receipt.")

        # ==========================================
        # 3. RECIPIENT NAME (Character-level strict match, allowing standard masked formats e.g. Jn D. or J*** D***)
        # ==========================================
        recipient_found = False
        if expectedRecipient and expectedRecipient.strip():
            clean_expected_name = re.sub(r'[^A-Za-z\s]', '', expectedRecipient).strip().upper()
            expected_words = [w for w in clean_expected_name.split() if w]
            
            # Normalize bullet / circle mask characters across all lines to standard '*'
            tokens_in_receipt = []
            for line in raw_lines:
                normalized_line = re.sub(r'[•●○⦿⦾◦·\-_]', '*', line.upper())
                tokens = re.findall(r'[A-Z0-9\*]+', normalized_line)
                tokens_in_receipt.extend(tokens)

            matched_name_words = 0
            for exp_w in expected_words:
                w_len = len(exp_w)
                word_matched = False

                for tok in tokens_in_receipt:
                    # Exact unmasked match
                    if tok == exp_w:
                        word_matched = True
                        break
                    # Masked with asterisks/bullets: e.g. J***, J***N, JU**
                    if '*' in tok:
                        if tok.startswith(exp_w[0]):
                            if len(tok) == w_len:
                                is_char_match = True
                                for c_tok, c_exp in zip(tok, exp_w):
                                    if c_tok != '*' and c_tok != c_exp:
                                        is_char_match = False
                                        break
                                if is_char_match:
                                    word_matched = True
                                    break
                            elif tok.endswith(exp_w[-1]) and len(tok) <= w_len + 2:
                                word_matched = True
                                break
                            elif len(tok.replace('*', '')) == 1 and tok.count('*') >= 2:
                                word_matched = True
                                break
                    # Abbreviated single-letter initial e.g. "J" or "D"
                    elif len(tok) == 1 and tok == exp_w[0]:
                        word_matched = True
                        break
                    # 2-letter abbreviation e.g. "JN" for "JUAN"
                    elif len(tok) == 2 and tok[0] == exp_w[0] and tok[1] == exp_w[-1]:
                        word_matched = True
                        break

                if word_matched:
                    matched_name_words += 1

            min_required_words = 1 if len(expected_words) == 1 else min(len(expected_words), 2)
            if matched_name_words >= min_required_words:
                recipient_found = True
            else:
                validation_errors.append(f"Recipient Name mismatch: Expected '{expectedRecipient}', but name on receipt does not match or was altered.")
        else:
            recipient_found = True

        # ==========================================
        # 4. PHONE NUMBER (Must match expected recipient number, allowing standard GCash masking)
        # ==========================================
        phone_found = None
        phone_candidates = re.findall(r'(?:\+?63[\s\-]?)?(?:0?9[\s\d\*•●○⦿⦾◦·\-_]{9,16})', full_text)
        
        if expectedPhone and expectedPhone.strip():
            clean_expected_phone = re.sub(r'\D', '', expectedPhone.strip())
            if clean_expected_phone.startswith('63'):
                clean_expected_phone = '0' + clean_expected_phone[2:]
            
            phone_matched = False
            for cand in phone_candidates:
                norm_cand = re.sub(r'[•●○⦿⦾◦·\-_]', '*', cand)
                cand_clean = re.sub(r'[\s\-]', '', norm_cand)
                if cand_clean.startswith('+63'):
                    cand_clean = '0' + cand_clean[3:]
                elif cand_clean.startswith('63'):
                    cand_clean = '0' + cand_clean[2:]
                
                # Check exact digits
                cand_digits = re.sub(r'\D', '', cand_clean)
                if cand_digits == clean_expected_phone:
                    phone_matched = True
                    phone_found = clean_expected_phone
                    break
                # Check masked phone (e.g., 09** *** 6789 or 0917***6789)
                if '*' in cand_clean and len(cand_clean) == len(clean_expected_phone):
                    masked_ok = True
                    for c_cand, c_exp in zip(cand_clean, clean_expected_phone):
                        if c_cand != '*' and c_cand != c_exp:
                            masked_ok = False
                            break
                    if masked_ok:
                        phone_matched = True
                        phone_found = clean_expected_phone
                        break

            if not phone_matched:
                validation_errors.append(f"Phone Number mismatch: Expected '{expectedPhone}' does not match recipient number on receipt.")
        else:
            # If no expected phone provided, check if a valid 11-digit GCash mobile number exists on the receipt
            for cand in phone_candidates:
                digits_only = re.sub(r'\D', '', cand)
                if len(digits_only) == 11 and digits_only.startswith('09'):
                    phone_found = digits_only
                    break
                elif len(digits_only) == 12 and digits_only.startswith('639'):
                    phone_found = '0' + digits_only[2:]
                    break
            if not phone_found:
                # Also accept masked 11-character phone format e.g. 09** *** 1234
                for cand in phone_candidates:
                    norm_c = re.sub(r'[\s\-•●○⦿⦾◦·_]', '', cand)
                    if len(norm_c) == 11 and norm_c.startswith('09'):
                        phone_found = norm_c
                        break
            if not phone_found:
                validation_errors.append("Recipient Phone Number was not detected on receipt.")

        # ==========================================
        # 5. DATE & TIME (Strict chronological format; flag if missing or tampered)
        # ==========================================
        date_time = None
        # Strict patterns matching GCash timestamps e.g. "Oct 12, 2026 08:30 PM", "Oct 12, 2026 08.30 PM", "12 Oct 2026 08:30 PM", "2026-10-12 20:30"
        dt_patterns = [
            r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4}\s+(?:at\s+)?\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b',
            r'\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{4}\s+(?:at\s+)?\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b',
            r'\b\d{4}[-/]\d{2}[-/]\d{2}\s+\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b',
            r'\b\d{1,2}[-/]\d{1,2}[-/]\d{4}\s+\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s*(?:AM|PM)?\b',
        ]
        for pat in dt_patterns:
            dt_match = re.search(pat, full_text, re.IGNORECASE)
            if dt_match:
                date_time = dt_match.group(0).strip()
                break

        if not date_time:
            validation_errors.append("Date & Time is missing, incomplete, or does not match valid chronological format.")

        # ==========================================
        # FINAL STRICT VERDICT
        # ==========================================
        if validation_errors:
            error_details = " | ".join(validation_errors)
            print(f"[Strict Receipt Validation Rejected] {error_details}")
            return {
                "success": False,
                "error": f"Strict Validation Failed: {error_details}",
                "extracted_text": full_text
            }

        print(f"[Strict Receipt Validation Passed] Ref={reference_number}, Amount={amount_found}, Recipient={recipient_found}, Phone={phone_found}, DateTime={date_time}")
        return {
            "success": True,
            "reference_number": reference_number,
            "amount": amount_found,
            "status": "Successful",
            "date": date_time,
            "recipient_matched": recipient_found,
            "phone": phone_found,
            "raw_reference": reference_number,
            "raw_amount": amount_found,
            "raw_date": date_time,
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
        elif not firstName and not lastName:
            return {"success": True, "match": False, "message": "Name is required for verification."}

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

        return {"success": True, "match": True, "message": "Credentials match"}
            
    except Exception as e:
        print(f"Error during ID OCR: {e}")
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
