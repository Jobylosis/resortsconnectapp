# Walkthrough: Phase 2 Financials (Spark Plan Pivot)

Phase 2 introduces rigorous financial transparency and backend integrity. Following the architecture pivot to accommodate the free Spark Plan, all complex calculations are now securely handled inside the React **Owner Dashboard**.

Here is a summary of what has been implemented and how you can test it.

## 1. Booking Price Breakdown (Frontend)

We replaced the single flat price display with a detailed, receipt-style breakdown.

- **React Website:** In the booking modal, tourists now see exactly how their bill is calculated: Room Base, Add-ons, and 12% Taxes & Fees. The `amountToPay` dynamically adjusts based on whether they chose a 30% downpayment or full payment.
- **Flutter App:** In both the `Property Details` and `Activity Details` pages, the booking confirmation bottom-sheet now includes a matching `Price Breakdown` UI section.

**How to test:** 
1. Open the website or mobile app.
2. Select a room/activity and choose some dates and add-ons.
3. Click "Book Now" and observe the new **Price Breakdown** table before finalizing the payment method.

---

## 2. Total Bill & Payment Status Calculation (Client-Side "Serverless")

Instead of relying on Google Cloud Functions, your React **Owner Dashboard** now acts as the system's "Admin Server". This means the logic only triggers when you (the authorized Admin) interact with bookings, keeping it completely secure from malicious tourists.

- **`totalOutstandingBalance` Calculation:** Whenever you Confirm, Cancel, Check-in, or Delete a booking, the system recalculates the tourist's remaining unpaid balance across all their active bookings, and saves it to their profile. 
- **Automatic Payment Status Updates:** When you click **"Confirm"** on a new booking, the system immediately compares the `amountPaid` (e.g. 30% downpayment) against the `pricing.grandTotal`. It then automatically tags the booking as `fully_paid`, `partially_paid`, or `unpaid`.

### Profile UI Update
We've also added a brand new **Outstanding Balance** widget inside the Tourist's `Profile.js`. It will light up in red and show them exactly how much they owe across all their bookings, but only if they actually have a balance greater than ₱0.

**How to test:**
1. Submit a test booking on the website or app. (e.g. Total ₱1000, GCash 30% Downpayment ₱300).
2. Log in as the Admin/Owner and go to the **Dashboard > Bookings** tab.
3. Find the pending booking and click **Confirm**.
4. The React system will magically calculate the payment status.
5. Log back in as the Tourist, go to **Profile**, and you'll see a red "Outstanding Balance: ₱700" widget!
## 3. Automation & AI (Phase 3)

We've integrated **Google ML Kit** for local, on-device AI capabilities directly in the Flutter App. By running these models locally, you avoid any Google Cloud Vision API billing requirements for your capstone project, while still achieving advanced automation.

### Optical Character Recognition (OCR)
- **Feature:** When a user uploads a GCash receipt in the App for their booking downpayment, the `google_mlkit_text_recognition` library automatically scans the image.
- **Workflow:** It extracts the unique GCash Reference Number from the image pixels and saves it to the database (`extractedRefNo`).
- **Dashboard Integration:** The React Owner Dashboard now displays the "AI Extracted Ref No" when you click on a Booking or scan a tourist's QR code. This allows owners to easily verify payments without manually reading the receipt image.

### Identity Verification (Face Detection)
- **Feature:** We've introduced a new Identity Verification section in the App's Profile page. Users must upload a Government ID and a Selfie.
- **Workflow:** Before uploading, the `google_mlkit_face_detection` library scans the images. If it does not detect a human face in the image, the upload is instantly rejected. If a face is found, the images are uploaded and the profile's `identityStatus` is set to 'pending'.
- **Admin Dashboard Integration:** In the React Admin Dashboard, we've added a **Verifications Tab**. Admins can view pending identity requests, compare the uploaded ID and Selfie, and either Approve or Reject the user. Approved users receive a 'verified' badge.

**How to test Phase 3:**
1. **App:** Go to the Profile tab, scroll down to Identity Verification, and try uploading an image without a face (e.g., a photo of a chair). Notice that it rejects the upload. Then upload a real face/selfie.
2. **App:** Make a booking and upload a sample GCash receipt. Notice the green snackbar confirming the AI found the reference number.
3. **Web:** Log in as an Admin, click the Verifications tab, and approve the new ID request. 
4. **Web:** Log in as an Owner, view your bookings, and see the AI-Extracted GCash Reference Number displayed alongside the booking details!
