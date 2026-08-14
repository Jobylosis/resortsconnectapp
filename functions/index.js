const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require('axios');
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

// 3. Create PayMongo Link
exports.createPaymongoLink = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
  }

  const { amount, description, remarks } = data;

  if (!amount || !description || !remarks) {
    throw new functions.https.HttpsError('invalid-argument', 'Missing required parameters.');
  }

  try {
    const options = {
      method: 'POST',
      url: 'https://api.paymongo.com/v1/links',
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
        authorization: 'Basic ' + Buffer.from(process.env.PAYMONGO_SECRET_KEY || 'dummy_key:').toString('base64')
      },
      data: {
        data: {
          attributes: {
            amount: parseInt(amount, 10), // in cents
            description: description,
            remarks: remarks
          }
        }
      }
    };

    const response = await axios.request(options);
    return {
      checkout_url: response.data.data.attributes.checkout_url,
      reference_number: response.data.data.attributes.reference_number
    };
  } catch (error) {
    console.error('Error creating PayMongo link:', error.response ? error.response.data : error.message);
    throw new functions.https.HttpsError('internal', 'Unable to create PayMongo link.');
  }
});

// 4. PayMongo Webhook
exports.paymongoWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }

  try {
    const event = req.body.data;
    if (event.type === 'link.payment.paid') {
      const attributes = event.attributes;
      const remarks = attributes.data.attributes.remarks; // This is the bookingId
      const amount = attributes.data.attributes.amount / 100; // Convert cents to pesos
      
      if (remarks) {
        // Find the booking and update it
        const bookingRef = admin.database().ref('/bookings/' + remarks);
        const snapshot = await bookingRef.once('value');
        
        if (snapshot.exists()) {
          const booking = snapshot.val();
          const currentPaid = booking.amountPaid || 0;
          
          await bookingRef.update({
            status: 'Confirmed',
            paymentStatus: 'paid',
            amountPaid: currentPaid + amount,
            paymongoReference: attributes.data.attributes.reference_number,
            updatedAt: admin.database.ServerValue.TIMESTAMP
          });
          
          // Also record the payment in /payments
          const newPaymentRef = admin.database().ref('/payments').push();
          await newPaymentRef.set({
            bookingId: remarks,
            amount: amount,
            status: 'approved',
            method: 'paymongo',
            referenceId: attributes.data.attributes.reference_number,
            createdAt: admin.database.ServerValue.TIMESTAMP
          });
        }
      }
    }
    res.status(200).send('Webhook received');
  } catch (error) {
    console.error('Webhook error:', error);
    res.status(500).send('Internal Server Error');
  }
});