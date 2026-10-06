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

@app.post("/extract_reference")
async def extract_reference(
    image: UploadFile = File(...),
    expectedAmount: str = Form(""),
    expectedRecipient: str = Form("")
):
    try:
        # Read the uploaded image
        image_bytes = await image.read()
        
        # We can pass the raw bytes directly to EasyOCR
        results = reader.readtext(image_bytes)
        
        # Extract just the text from the results
        full_text = " ".join([result[1] for result in results])
        print(f"Extracted Text: {full_text}")
        
        reference_number = None
        amount_found = None
        status_found = False
        date_time = None
        recipient_found = False

        # 1. Reference Number Detection (supports 1-line e.g. '1234 123 123456' and 2-line split e.g. '1234 123 \n 123456')
        # Check explicit Ref No prefix first
        ref_match = re.search(r'Ref[\s\.]*No[\.\s:]*([0-9\s\n\r]{9,30})', full_text, re.IGNORECASE)
        if ref_match:
            clean_num = re.sub(r'\D', '', ref_match.group(1))
            if len(clean_num) >= 13:
                reference_number = clean_num[:13]
            elif len(clean_num) >= 9:
                # If only part of the reference number was captured in group 1 (e.g. 7 digits '1234 123'),
                # check if the remaining digits follow immediately in full_text
                end_pos = ref_match.end()
                remainder_text = full_text[end_pos:end_pos+40]
                rem_digits = re.findall(r'\b\d{4,8}\b', remainder_text)
                if rem_digits:
                    combined = clean_num + rem_digits[0]
                    if len(combined) >= 13:
                        reference_number = combined[:13]
                if not reference_number:
                    reference_number = clean_num

        # Check line-by-line / detection results if not found or incomplete
        if not reference_number or len(reference_number) < 13:
            raw_lines = [res[1].strip() for res in results if res and len(res) > 1 and res[1]]
            for i, line in enumerate(raw_lines):
                if re.search(r'Ref[\s\.]*No', line, re.IGNORECASE):
                    line_digits = re.sub(r'\D', '', line)
                    # If full 13 digits are in the same line
                    if len(line_digits) >= 13:
                        reference_number = line_digits[:13]
                        break
                    # If split across 2 lines (e.g. line i has 'Ref No. 1234 123' and line i+1 has '123456')
                    for next_idx in range(i + 1, min(i + 4, len(raw_lines))):
                        next_digits = re.sub(r'\D', '', raw_lines[next_idx])
                        if next_digits:
                            combined = line_digits + next_digits
                            if len(combined) >= 13:
                                reference_number = combined[:13]
                                break
                            line_digits = combined
                    if reference_number and len(reference_number) >= 13:
                        break

        # Fallback: find any 13 consecutive digits (allowing spaces/newlines between them)
        if not reference_number or len(reference_number) < 13:
            for match_str in re.finditer(r'\b(?:\d[\s\n\r]*){13}\b', full_text):
                clean_num = re.sub(r'\D', '', match_str.group(0))
                if len(clean_num) == 13:
                    reference_number = clean_num
                    break

        # Fallback 2: find adjacent groups of numbers that sum to 13 digits (e.g. 7 digits + 6 digits: '1234 123' and '123456')
        if not reference_number or len(reference_number) < 13:
            blocks = re.findall(r'\b\d{3,9}\b', full_text)
            for idx in range(len(blocks) - 1):
                comb = blocks[idx] + blocks[idx+1]
                if len(comb) == 13:
                    reference_number = comb
                    break

        # 2. Status Detection
        # Made more lenient to handle OCR typos or different GCash receipt formats
        if re.search(r'(success|sent|complete|paid|payment|transfer|gcash|peso|php)', full_text, re.IGNORECASE):
            status_found = True

        # 3. Amount Extraction and Validation
        # Look for PHP, P, ₱, Amount, Total followed by numbers (supports centavos e.g. 10.78, 0.30, and whole pesos e.g. 1000)
        amount_matches = re.findall(r'(?:PHP|P|₱|Amount:?|Total:?)\s*((?:[1-9]\d{0,2}(?:,\d{3})+|[1-9]\d*|0)(?:\.\d{2})?)', full_text, re.IGNORECASE)
        # Fallback to plain decimal patterns (e.g. 10.78, 0.30) if no currency prefix found
        if not amount_matches:
            amount_matches = re.findall(r'\b(?:[1-9]\d{0,2}(?:,\d{3})+|[1-9]\d*|0)\.\d{2}\b', full_text)

        if amount_matches:
            # Clean commas for comparison
            extracted_amounts = [re.sub(r'[^\d\.]', '', m) for m in amount_matches]
            # If an expected amount is provided, check if it matches any extracted amount
            if expectedAmount:
                clean_expected = re.sub(r'[^\d\.]', '', expectedAmount)
                try:
                    expected_float = float(clean_expected)
                    for ext_amt in extracted_amounts:
                        if ext_amt and abs(float(ext_amt) - expected_float) < 0.05:
                            amount_found = ext_amt
                            break
                except ValueError:
                    pass
                
                # If we have an expected amount but didn't find it in the receipt
                if not amount_found:
                    amount_found = extracted_amounts[0] # Store the incorrect amount for error reporting
            else:
                if not amount_found and extracted_amounts:
                    amount_found = extracted_amounts[0]

        # 4. Date and Time Detection
        # Lenient: Accommodate dots, seconds, A.M., missing year, or just standard time formats since app compression can mess up parts of the date string
        date_match = re.search(r'([A-Za-z]{3}\.?\s*\d{1,2}[,\s]*\d{4}|\d{2}[-/]\d{2}[-/]\d{4}|\d{1,2}[:;.lI]\d{2}(?:[:;.lI]\d{2})?\s*[AP]\.?M\.?|\d{1,2}\s+[A-Za-z]{3}\s+\d{4})', full_text, re.IGNORECASE)
        if date_match:
            date_time = date_match.group(1)

        # 5. GCash Number Detection
        # Lenient: Looks for +63 9XX or 09XX
        number_match = re.search(r'(\+?63\s?9\d{2}\s?\d{3}\s?\d{4}|09\d{2}\s?\d{3}\s?\d{4})', full_text)
        gcash_number = number_match.group(1) if number_match else None

        # 6. Recipient Name Detection
        recipient_found = False
        if expectedRecipient:
            # Clean name to only alphabets to prevent regex crashes with special characters
            clean_name = re.sub(r'[^A-Za-z\s]', '', expectedRecipient).strip()
            expected_words = [w for w in clean_name.upper().split() if w]
            upper_text = full_text.upper()
            # Normalize various circle and mask symbols in the OCR text to standard '*'
            # Supports: • (bullet), ● (black circle), ○ (white circle), ⦿, ⦾, ◦, · (middle dot), *, -, _
            normalized_text = re.sub(r'[•●○⦿⦾◦·\*\-_]', '*', upper_text)

            for word in expected_words:
                if word in upper_text:
                    recipient_found = True
                    break

                if len(word) >= 3:
                    first_char = re.escape(word[0])
                    last_char = re.escape(word[-1])
                    pattern_with_end = first_char + r'[\s\*oO0\.]{1,12}?' + last_char
                    pattern_prefix_only = first_char + r'[\*]{2,}'

                    if re.search(pattern_with_end, normalized_text) or re.search(pattern_prefix_only, normalized_text):
                        recipient_found = True
                        break
                elif len(word) == 2:
                    first_char = re.escape(word[0])
                    if re.search(first_char + r'[\*]{2,}', normalized_text):
                        recipient_found = True
                        break

            # Fallback for combined initials e.g. "K*** M*** B" or "K*** B***"
            if not recipient_found and len(expected_words) >= 2:
                first_initial = re.escape(expected_words[0][0])
                last_initial = re.escape(expected_words[-1][0])
                initials_pattern = first_initial + r'[\s\*A-Z\.]{1,25}?' + last_initial
                if re.search(initials_pattern, normalized_text):
                    recipient_found = True
        else:
            recipient_found = False

        # Strict Validation Checks
        is_valid = True
        error_messages = []
        
        if not reference_number:
            is_valid = False
            error_messages.append("No reference number detected.")
        if not status_found:
            is_valid = False
            error_messages.append("Transaction does not appear to be successful.")
        
        if expectedAmount:
            clean_expected = re.sub(r'[^\d\.]', '', expectedAmount)
            try:
                expected_float = float(clean_expected)
                if not amount_found:
                    is_valid = False
                    error_messages.append(f"Amount ₱{expectedAmount} not found on receipt. Please ensure the price is visible.")
                elif abs(float(amount_found.replace(',', '')) - expected_float) >= 0.05:
                    is_valid = False
                    error_messages.append(f"Incorrect amount. Expected: ₱{expectedAmount}, Found: ₱{amount_found}")
            except ValueError:
                is_valid = False
                error_messages.append(f"Amount ₱{expectedAmount} not found on receipt. Please ensure the price is visible.")
        elif not amount_found:
            is_valid = False
            error_messages.append("Amount not found on receipt.")
        if not date_time:
            is_valid = False
            error_messages.append("Date and time not detected.")
        if not gcash_number:
            is_valid = False
            error_messages.append("GCash number not detected.")
        if not recipient_found:
            is_valid = False
            error_messages.append(f"Recipient name not detected or did not match expected owner.")

        if not is_valid:
            return {
                "success": False, 
                "error": "Strict Validation Failed: " + ", ".join(error_messages),
                "extracted_text": full_text
            }

        return {
            "success": True, 
            "reference_number": reference_number,
            "amount": amount_found,
            "status": "Successful",
            "date": date_time,
            "recipient_matched": recipient_found
        }
    
    except Exception as e:
        print(f"Error during OCR: {e}")
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
        
        # Check image aspect ratio to enforce cropping
        try:
            from PIL import Image
            import io
            with Image.open(io.BytesIO(image_bytes)) as img:
                width, height = img.size
                # Standard ID is landscape. If it's portrait or too square, it's likely uncropped.
                if width < height * 1.1:
                    return {
                        "success": True, 
                        "match": False, 
                        "message": "Please crop the photo to only show the ID card. Remove unnecessary text, blank spaces, or borders."
                    }
        except Exception as e:
            print(f"Error checking image size: {e}")

        results = reader.readtext(image_bytes)
        full_text, last_region, first_region, mid_region = extract_names_from_id(results, idType)
        print(f"Extracted ID Text: {full_text}")

        # Match each name against its label-anchored region (not the whole card text)
        fname_match = fuzzy_match_name(firstName, first_region) if firstName else False
        mname_match = fuzzy_match_name(middleName, mid_region)  if middleName else True
        lname_match = fuzzy_match_name(lastName,  last_region)  if lastName  else False
        
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
            return {"success": True, "match": False, "message": f"Could not detect '{idType}' format. Ensure you selected the correct ID type."}
            
        # Require both firstName and lastName to strictly match
        # Strict Name Matching:
        # First Name strictly maps to First Name
        # Surname strictly maps to Surname
        # Middle Name is optional; if provided by user, it must match
        if firstName and lastName:
            if not (fname_match and lname_match):
                return {"success": True, "match": False, "message": "Name on ID does not match registered name. Please ensure first name and surname match your ID."}
            if middleName.strip() and not mname_match:
                return {"success": True, "match": False, "message": "Middle name on ID does not match registered name."}
        elif firstName and not fname_match:
            return {"success": True, "match": False, "message": "First name on ID does not match registered name."}
        elif lastName and not lname_match:
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
                
                with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp_id:
                    tmp_id.write(image_bytes)
                    id_path = tmp_id.name
                    
                with tempfile.NamedTemporaryFile(delete=False, suffix=".jpg") as tmp_selfie:
                    tmp_selfie.write(selfie_bytes)
                    selfie_path = tmp_selfie.name
                
                try:
                    import cv2
                    import numpy as np
                    
                    # Blur detection for ID
                    id_img = cv2.imread(id_path)
                    if id_img is not None:
                        gray_id = cv2.cvtColor(id_img, cv2.COLOR_BGR2GRAY)
                        blur_score_id = cv2.Laplacian(gray_id, cv2.CV_64F).var()
                        if blur_score_id < 50:
                            return {"success": True, "match": False, "message": "ID photo is too blurry. Please take a clearer photo."}
                            
                    # Blur detection for Selfie
                    selfie_img = cv2.imread(selfie_path)
                    if selfie_img is not None:
                        gray_selfie = cv2.cvtColor(selfie_img, cv2.COLOR_BGR2GRAY)
                        blur_score_selfie = cv2.Laplacian(gray_selfie, cv2.CV_64F).var()
                        if blur_score_selfie < 50:
                            return {"success": True, "match": False, "message": "Selfie is too blurry. Please take a clearer photo in good lighting."}

                    # enforce_detection=True so it rejects faces with masks, heavy sunglasses, or heavy blur
                    result = DeepFace.verify(img1_path=selfie_path, img2_path=id_path, enforce_detection=True, model_name="VGG-Face", detector_backend="mtcnn")
                    if not result.get("verified", False):
                        return {"success": True, "match": False, "message": "Facial recognition failed: Selfie does not match the person on the ID."}
                except ValueError as ve:
                    # DeepFace throws ValueError if a face cannot be detected due to occlusion
                    return {"success": True, "match": False, "message": "Face not detected clearly. Please ensure you are not wearing a cap, sunglasses, or mask, and the ID is fully visible."}
                finally:
                    os.remove(id_path)
                    os.remove(selfie_path)
                    
            except Exception as e:
                print(f"DeepFace error: {e}")
                return {"success": True, "match": False, "message": "Facial recognition engine error. Please ensure both photos show a clear face."}

        return {"success": True, "match": True, "message": "Credentials match"}
            
    except Exception as e:
        print(f"Error during ID OCR: {e}")
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
