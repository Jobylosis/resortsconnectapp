const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// 1. Total Bill Calculation
// Triggered when a booking is created or updated
exports.calculateTotalBill = functions.database.ref("/bookings/{bookingId}")
    .onWrite(async (change, context) => {
      const before = change.before.val();
      const after = change.after.val();
      
      const touristUid = after ? after.touristUid : (before ? before.touristUid : null);
      if (!touristUid) return null;

      // Calculate the total outstanding balance for this user
      // Outstanding Balance = Sum of (grandTotal - totalPaid) for all active bookings
      const snapshot = await admin.database().ref("/bookings").orderByChild("touristUid").equalTo(touristUid).once("value");
      let totalOutstandingBalance = 0;

      if (snapshot.exists()) {
        snapshot.forEach((childSnap) => {
          const booking = childSnap.val();
          // Exclude cancelled or declined bookings
          if (booking.status !== "Cancelled" && booking.status !== "Declined" && booking.status !== "Refund Approved") {
             const grandTotal = booking.pricing?.grandTotal || booking.totalPrice || 0;
             const amountPaid = booking.amountPaid || 0;
             totalOutstandingBalance += (grandTotal - amountPaid);
          }
        });
      }

      // Ensure balance doesn't go below 0 due to errors
      totalOutstandingBalance = Math.max(0, totalOutstandingBalance);

      // Update the user's document
      return admin.database().ref(`/users/${touristUid}`).update({
        totalOutstandingBalance: totalOutstandingBalance
      });
    });

// 2. Automatic Payment Status
// Triggered when a payment document is updated (e.g. status changes to 'approved')
exports.automaticPaymentStatus = functions.database.ref("/payments/{paymentId}")
    .onWrite(async (change, context) => {
      const after = change.after.val();
      const before = change.before.val();
      
      // We only care if payment exists and has a booking ID attached
      const bookingId = after ? after.bookingId : (before ? before.bookingId : null);
      if (!bookingId) return null;

      // Fetch all payments for this booking
      const paymentsSnap = await admin.database().ref("/payments").orderByChild("bookingId").equalTo(bookingId).once("value");
      
      let totalPaid = 0;
      if (paymentsSnap.exists()) {
        paymentsSnap.forEach((childSnap) => {
          const payment = childSnap.val();
          if (payment.status === "approved") {
            totalPaid += (parseFloat(payment.amount) || 0);
          }
        });
      }

      // Fetch the booking to compare totalPaid with grandTotal
      const bookingSnap = await admin.database().ref(`/bookings/${bookingId}`).once("value");
      if (!bookingSnap.exists()) return null;
      
      const booking = bookingSnap.val();
      const grandTotal = booking.pricing?.grandTotal || booking.totalPrice || 0;
      
      let newPaymentStatus = "unpaid";
      if (totalPaid >= grandTotal) {
        newPaymentStatus = "fully_paid";
      } else if (totalPaid > 0) {
        newPaymentStatus = "partially_paid";
      }

      // Update the booking with the new payment status and amount paid
      return admin.database().ref(`/bookings/${bookingId}`).update({
        paymentStatus: newPaymentStatus,
        amountPaid: totalPaid
      });
    });
