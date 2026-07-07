# Phase 3: Automation & AI Implementation Plan

This document outlines the exact execution plan for Phase 3, which focuses on bringing AI-powered automation to the ResortConnect platform.

> [!IMPORTANT]
> **User Review Required**
> Implementing AI OCR and Facial Verification involves external services. Please review the options below and provide your feedback so we can proceed with the best approach for your capstone project!

## Open Questions

> [!WARNING]
> **1. Which AI Approach do you want to use?**
> - **Option A (Google Cloud Vision - Paid/Billing Required):** We use Cloud Functions and the Google Cloud Vision API. This is highly accurate and runs on the backend, but **requires a Google Cloud Billing account** with a credit card attached.
> - **Option B (Google ML Kit - 100% Free / On-Device):** We use Google ML Kit directly inside the Flutter app. The app will process the image on the user's phone *before* uploading it. This is **completely free**, fast, and doesn't require a billing account, making it perfect for capstone projects!
> 
> **2. Facial Recognition Limitation:**
> Truly comparing two faces (1:1 matching) requires paid services like AWS Rekognition or Azure Face API. If we go with the free route (Option B), we can use ML Kit to verify that a *human face is present* in both the ID and the Selfie, but we cannot mathematically prove they are the *same* person without a paid API. Is checking for the presence of a face sufficient for the capstone scope?

## Proposed Changes

If we proceed with **Option B (Free On-Device ML Kit)**, here is the technical breakdown:

### Mobile App (Flutter)

#### [MODIFY] `pubspec.yaml`
- Add `google_mlkit_text_recognition` for reading GCash receipts.
- Add `google_mlkit_face_detection` for analyzing selfies and IDs.

#### [NEW] `lib/services/ai_service.dart`
- Create a dedicated AI service class to handle image processing.
- `extractGCashReference(File image)`: Runs OCR on the receipt and uses Regular Expressions (Regex) to find the 13-digit GCash reference number.
- `detectFace(File image)`: Runs face detection on an image and returns `true` if exactly one face is detected.

#### [MODIFY] `lib/activity_details_page.dart` & `lib/property_details_page.dart`
- Before uploading the receipt, run `ai_service.extractGCashReference()`.
- If a reference number is found, include it in the booking payload as `extractedRefNo`.
- If no number is found, warn the user but allow them to proceed (manual verification fallback).

#### [MODIFY] `lib/profile_page.dart`
- Add an "Identity Verification" section.
- User captures ID and Selfie.
- Run `ai_service.detectFace()` on both images. If faces are detected, allow the upload.

### Web App (React Admin Dashboard)

#### [MODIFY] `website/src/components/AdminDashboard.js`
- Create an "Identity Verification" tab where the Admin can see the uploaded IDs and Selfies.
- Add "Approve" and "Reject" buttons for manual override.

#### [MODIFY] `website/src/components/OwnerDashboard.js`
- When owners are viewing bookings, prominently display the `extractedRefNo` (GCash Reference Number) that the AI pulled from the receipt to speed up their verification process.

## Verification Plan

### Automated Tests
- Test the ML Kit OCR against sample GCash receipt images.
- Test the ML Kit Face Detection against sample IDs and selfies.

### Manual Verification
- Book a room/activity on the Flutter app, upload a GCash receipt, and verify the reference number is accurately extracted and saved to the database.
- Upload an ID/Selfie on the app, verify ML Kit blocks the upload if no face is detected.
- Verify the Admin can see and approve the identities on the Web Dashboard.
