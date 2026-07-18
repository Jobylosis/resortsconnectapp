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
        if re.search(r'(successful|success|sent successfully|successfully sent)', full_text, re.IGNORECASE):
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
            if not amount_found and extracted_amounts:
                amount_found = extracted_amounts[0]

        # 4. Date and Time Detection (simple heuristic)
        date_match = re.search(r'([A-Za-z]{3}\s\d{1,2},\s\d{4}\s\d{1,2}:\d{2}\s(?:AM|PM))', full_text, re.IGNORECASE)
        if date_match:
            date_time = date_match.group(1)

        # 5. Recipient Matching
        if expectedRecipient and expectedRecipient.strip():
            # Check if any part of the recipient name is in the text
            parts = expectedRecipient.upper().split()
            full_text_upper = full_text.upper()
            if any(part in full_text_upper for part in parts if len(part) > 2):
                recipient_found = True
        else:
            # If no recipient name to check, we just assume True
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
        
        if expectedAmount and not amount_found:
            is_valid = False
            error_messages.append(f"Amount {expectedAmount} not found on receipt.")

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

@app.post("/verify_id")
async def verify_id(image: UploadFile = File(...), firstName: str = "", lastName: str = ""):
    try:
        image_bytes = await image.read()
        results = reader.readtext(image_bytes)
        full_text = " ".join([result[1] for result in results]).upper()
        print(f"Extracted ID Text: {full_text}")
        
        fname_match = firstName.upper() in full_text if firstName else False
        lname_match = lastName.upper() in full_text if lastName else False
        
        # If both matches, or if only one provided and matches
        if (firstName and lastName and fname_match and lname_match) or \
           (firstName and not lastName and fname_match) or \
           (not firstName and lastName and lname_match):
            return {"success": True, "match": True, "message": "Credentials match"}
        else:
            return {"success": True, "match": False, "message": "Credentials mismatch"}
            
    except Exception as e:
        print(f"Error during ID OCR: {e}")
        return {"success": False, "error": str(e)}

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
