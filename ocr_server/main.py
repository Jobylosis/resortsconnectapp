from fastapi import FastAPI, File, UploadFile
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
async def extract_reference(image: UploadFile = File(...)):
    try:
        # Read the uploaded image
        image_bytes = await image.read()
        
        # We can pass the raw bytes directly to EasyOCR
        results = reader.readtext(image_bytes)
        
        # Extract just the text from the results
        full_text = " ".join([result[1] for result in results])
        print(f"Extracted Text: {full_text}")
        
        # First priority: Look for "Ref No" followed by digits
        ref_match = re.search(r'Ref[\s\.]*No[\.\s]*([\d\s]{9,20})', full_text, re.IGNORECASE)
        if ref_match:
            clean_num = re.sub(r'\s+', '', ref_match.group(1))
            if len(clean_num) >= 9:
                print(f"Found Reference Number (via Ref No text): {clean_num[:13]}")
                return {"success": True, "reference_number": clean_num[:13]}
                
        # Second priority: Look for exactly 13 digits (GCash standard)
        for match_str in re.finditer(r'\b(?:\d\s*){13}\b', full_text):
            clean_num = re.sub(r'\s+', '', match_str.group(0))
            if len(clean_num) == 13:
                print(f"Found Reference Number (via 13-digit match): {clean_num}")
                return {"success": True, "reference_number": clean_num}
        
        return {"success": False, "error": "No reference number found in the receipt"}
    
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
