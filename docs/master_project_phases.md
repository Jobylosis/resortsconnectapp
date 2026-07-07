# ResortConnect Master Project Phases (1 - 4)

This document contains the consolidated list of all features implemented across Phase 1 through Phase 4. It ensures that both the Web Application and the Mobile Application are kept in sync.

---

## Phase 1: Core Foundation
**Objective:** Build the core booking management system connecting tourists with resort owners.

*   **Web App:** 
    *   **Owner Dashboard:** Property profile creation, Room inventory management, Booking requests & approvals.
    *   **Admin Dashboard:** Basic user moderation and property verifications.
*   **Mobile App:** 
    *   Tourist Registration & Login (Firebase Auth).
    *   Property & Activity Browsing (Maps, Amenities, Photos).
    *   Booking system allowing users to select dates, rooms, and optional add-ons.
*   **How to test:** 
    *   Register as a new tourist on the mobile app, browse a property, and submit a booking. Log in to the web app as the owner and approve that booking.

---

## Phase 2: Financials & Pricing Breakdown
**Objective:** Add rigorous financial transparency and payment tracking.

*   **Web App:**
    *   **Serverless Balance Tracking:** The Owner Dashboard dynamically calculates a tourist's "Total Outstanding Balance" whenever bookings are approved or checked out.
    *   **Tourist Profile:** Displays a prominent red "Outstanding Balance" warning widget if they owe money.
    *   **Booking Modals:** Updated to show a receipt-style breakdown (Room Base, Add-ons, 12% Tax).
*   **Mobile App:**
    *   Property and Activity booking confirmation bottom sheets match the exact pricing breakdown (Room, Add-ons, Taxes).
*   **How to test:**
    *   Submit a booking with a 30% GCash downpayment on the app. Verify the detailed receipt breakdown. Then on the web, login as an owner and confirm the booking. Log back into the app/web as the tourist to see the red Outstanding Balance warning.

---

## Phase 3: Automation & AI
**Objective:** Introduce free, on-device AI tools (Google ML Kit) to automate verifications without requiring external paid APIs or credit cards.

*   **Web App:**
    *   **Admin Dashboard:** Added a "Verifications" tab for Admins to manually approve or reject tourist ID submissions.
    *   **Owner Dashboard:** Bookings now display the "AI-Extracted GCash Reference Number" for fast payment verification.
*   **Mobile App:**
    *   **Identity Verification (Face Detection):** Added to the Tourist Profile page. The AI scans the uploaded Government ID and selfie to ensure a human face is present before allowing the upload to Firebase.
    *   **GCash OCR (Text Recognition):** When a tourist uploads a GCash receipt, the app scans the image and automatically extracts the Reference Number to send to the database.
*   **How to test:**
    *   *App:* Go to Profile -> Identity Verification. Try uploading a picture of an inanimate object; the app will reject it. Upload a photo of a real face, and it will go through.
    *   *App:* Upload a GCash receipt during a booking. Watch for the green AI success snackbar stating the reference number was found.
    *   *Web:* Go to the Admin dashboard and approve the ID. Go to the Owner dashboard and find the extracted GCash reference number on the booking details.

---

## Phase 4: UI/UX, Reporting, & Polish (Current Phase)
**Objective:** Ensure all changes are perfectly mirrored across both the Web and Mobile app, add robust reporting tools, and squash bugs for capstone defense preparation.

*   **Web & Mobile App:**
    *   Ensure any new property restrictions, text validations (e.g. 30-character limits, emoji filtering), or layout changes are identical on both platforms.
    *   Ensure GCash dynamic QR code payments are strictly tied to specific properties rather than global hardcoded images.
*   **Owner Dashboard (Web/App):**
    *   Added "Share/Export" functionality for monthly revenue reports. On the app, clicking the share icon next to a month instantly formats a text-based sales report for Messenger/Email.
*   **How to test:**
    *   Test all text inputs (like Add-on names and User Registration) for consistent emoji-filtering and character limits.
    *   Try exporting a monthly revenue report on the App and Web to verify the sharing functionality.
