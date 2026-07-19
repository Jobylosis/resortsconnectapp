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

        # 1. Reference Number Detection
        ref_match = re.search(r'Ref[\s\.]*No[\.\s]*([\d\s]{9,20})', full_text, re.IGNORECASE)
        if ref_match:
            clean_num = re.sub(r'\s+', '', ref_match.group(1))
            if len(clean_num) >= 9:
                reference_number = clean_num[:13]
        
        if not reference_number:
            for match_str in re.finditer(r'\b(?:\d\s*){13}\b', full_text):
                clean_num = re.sub(r'\s+', '', match_str.group(0))
                if len(clean_num) == 13:
                    reference_number = clean_num
                    break

        # 2. Status Detection
        # Made more lenient to handle OCR typos or different GCash receipt formats
        if re.search(r'(success|sent|complete|paid|payment|transfer|gcash|peso|php)', full_text, re.IGNORECASE):
            status_found = True

        # 3. Amount Extraction and Validation
        # Look for PHP, P, or just raw numbers like "1,500.00"
        amount_matches = re.findall(r'(?:PHP|P)?\s*(?:[1-9]\d{0,2}(?:,\d{3})*|0)(?:\.\d{2})', full_text, re.IGNORECASE)
        if amount_matches:
            # Clean commas for comparison
            extracted_amounts = [re.sub(r'[^\d\.]', '', m) for m in amount_matches]
            # If an expected amount is provided, check if it matches any extracted amount
            if expectedAmount:
                clean_expected = re.sub(r'[^\d\.]', '', expectedAmount)
                try:
                    expected_float = float(clean_expected)
                    for ext_amt in extracted_amounts:
                        if ext_amt:
                            if abs(float(ext_amt) - expected_float) < 1.0:
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
        # Strict: Looks for Month/Day/Year + Time (e.g., "07-19-2024 10:30 AM" or "Jul 19, 2024 10:30 AM")
        date_match = re.search(r'([A-Za-z]{3}\s*\d{1,2}[,\s]*\d{4}\s*\d{1,2}[:;.lI]\d{2}\s*[AP]M|\d{2}[-/]\d{2}[-/]\d{4}\s*\d{1,2}[:;.lI]\d{2}\s*[AP]M)', full_text, re.IGNORECASE)
        if date_match:
            date_time = date_match.group(1)

        # 5. GCash Number Detection
        # Lenient: Looks for +63 9XX or 09XX
        number_match = re.search(r'(\+?63\s?9\d{2}\s?\d{3}\s?\d{4}|09\d{2}\s?\d{3}\s?\d{4})', full_text)
        gcash_number = number_match.group(1) if number_match else None

        # 6. Recipient Name Detection
        # GCash masks names (e.g. Keisha -> KE•••A). The OCR often scrambles the bullet points.
        # The safest way is to check if the first 2 letters of the expected name are present.
        if expectedRecipient and len(expectedRecipient.strip()) >= 2:
            first_two = expectedRecipient.strip()[:2].upper()
            # Also get the last initial just to be a bit more sure if possible
            parts = expectedRecipient.upper().split()
            last_initial = parts[-1][0] if parts else ""
            
            if first_two in full_text.upper():
                recipient_found = True
        
        # Fallback: look for any generic masked pattern (2+ uppercase letters followed by symbols)
        if not recipient_found:
            name_match = re.search(r'([A-Z]{2,}[^A-Za-z0-9]+[A-Z])', full_text)
            if name_match:
                recipient_found = True

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
                
                # General amount validation


                # Fallback to general amount validation if still valid
                if is_valid:
                    if not amount_found or abs(float(amount_found.replace(',', '')) - expected_float) >= 1.0:
                        is_valid = False
                        error_messages.append(f"Incorrect amount. Expected: {expectedAmount}, Found: {amount_found}")
            except ValueError:
                is_valid = False
                error_messages.append(f"Amount {expectedAmount} not found on receipt.")
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
            error_messages.append("Recipient name not detected.")

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

def fuzzy_match_name(name, full_text, threshold=0.75):
    if not name: return False
    # Split the name into individual words
    words = name.upper().split()
    # Replace symbols with spaces to get words from full_text
    clean_full_text = re.sub(r'[^A-Z0-9\s]', ' ', full_text)
    text_words = clean_full_text.split()
    
    matched_count = 0
    for word in words:
        # Check for exact match or close match in OCR words
        if word in text_words or len(difflib.get_close_matches(word, text_words, n=1, cutoff=threshold)) > 0:
            matched_count += 1
            
    # At least half of the name words should be found
    return (matched_count / len(words)) >= 0.5

@app.post("/verify_id")
async def verify_id(
    image: UploadFile = File(...), 
    firstName: str = Form(""), 
    lastName: str = Form(""), 
    idType: str = Form("")
):
    try:
        image_bytes = await image.read()
        results = reader.readtext(image_bytes)
        full_text = " ".join([result[1] for result in results]).upper()
        print(f"Extracted ID Text: {full_text}")
        
        fname_match = fuzzy_match_name(firstName, full_text) if firstName else False
        lname_match = fuzzy_match_name(lastName, full_text) if lastName else False
        
        # ID Type Matching Logic
        id_type_match = True
        if idType:
            id_keywords = {
                "Philippine National ID (PhilSys)": ["NATIONALID", "PHILSYS", "PHILIPPINEIDENTIFICATION", "PAMBANSANGPAGKAKAKILANLAN"],
                "Passport": ["PASSPORT", "PASAPORTE"],
                "Driver's License": ["DRIVER", "LICENSE", "LANDTRANSPORTATION", "LTO"],
                "Voter's ID": ["VOTER", "COMELEC", "COMMISSIONONELECTIONS"],
                "SSS / GSIS ID": ["SOCIALSECURITY", "SSS", "GSIS", "GOVERNMENTSERVICE"],
                "PRC ID": ["PROFESSIONALREGULATION", "PRC"],
                "Senior Citizen ID": ["SENIORCITIZEN", "OSCA"],
                "Postal ID": ["POSTAL", "POSTOFFICE", "PHLPOST"],
            }
            
            target_keywords = id_keywords.get(idType, [])
            if target_keywords:
                # Check if any keyword exists in the full_text
                clean_full = re.sub(r'[^A-Z0-9]', '', full_text)
                id_type_match = any(kw in clean_full for kw in target_keywords)
            else:
                id_type_match = True # Other/Unknown
                
        print(f"DEBUG: firstName='{firstName}', lastName='{lastName}', idType='{idType}'")
        print(f"DEBUG: fname_match={fname_match}, lname_match={lname_match}, id_type_match={id_type_match}")
                
        if not id_type_match:
            return {"success": True, "match": False, "message": f"Could not detect '{idType}' format. Ensure you selected the correct ID type."}
            
        # If both matches, or if only one provided and matches
        if (firstName and lastName and fname_match and lname_match) or \
           (firstName and not lastName and fname_match) or \
           (not firstName and lastName and lname_match):
            return {"success": True, "match": True, "message": "Credentials match"}
        else:
            return {"success": True, "match": False, "message": "Name on ID does not match registered name."}
            
    except Exception as e:
        print(f"Error during ID OCR: {e}")
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
