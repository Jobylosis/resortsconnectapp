// EmailJS Service Module for Web Application
// Provides unified email triggers for booking confirmations, status updates, registrations, and admin alerts.

export const EMAILJS_CONFIG = {
  SERVICE_ID: 'service_6qvfi3q',
  PUBLIC_KEY: 'fSfM4l-f9zmLrmOx5',
  PRIVATE_KEY: '', // Optional private key if backend access token is required
  TEMPLATES: {
    BOOKING_CONFIRMATION: 'template_booking_confirm',
    BOOKING_STATUS_UPDATE: 'template_booking_status',
    USER_REGISTRATION: 'template_welcome_user',
    ADMIN_ALERT: 'template_admin_alert',
    OWNER_BOOKING_NOTIFICATION: 'template_7xvh6ps'
  }
};

/**
 * Sends an email using the EmailJS REST API
 * @param {string} templateId 
 * @param {Object} templateParams 
 */
export const sendEmailJS = async (templateId, templateParams) => {
  try {
    const payload = {
      service_id: EMAILJS_CONFIG.SERVICE_ID,
      template_id: templateId,
      user_id: EMAILJS_CONFIG.PUBLIC_KEY,
      template_params: {
        timestamp: new Date().toLocaleString(),
        ...templateParams
      }
    };

    if (EMAILJS_CONFIG.PRIVATE_KEY) {
      payload.accessToken = EMAILJS_CONFIG.PRIVATE_KEY;
    }

    const response = await fetch('https://api.emailjs.com/api/v1.0/email/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (response.ok) {
      console.log(`[EmailJS] Successfully dispatched email for template: ${templateId}`);
      return { success: true };
    } else {
      const errText = await response.text();
      console.warn(`[EmailJS] Dispatch failed (${response.status}): ${errText}`);
      return { success: false, error: errText };
    }
  } catch (error) {
    console.error('[EmailJS] Network/Execution Error:', error);
    return { success: false, error: error.message };
  }
};

/**
 * Sends a Booking Confirmation email to the tourist
 */
export const sendBookingConfirmationEmail = async ({
  toEmail,
  toName,
  bookingId,
  propertyName,
  roomName,
  checkInDate,
  nights,
  amountPaid,
  grandTotal,
  paymentMethod,
  paymentOption
}) => {
  return sendEmailJS(EMAILJS_CONFIG.TEMPLATES.BOOKING_CONFIRMATION, {
    to_email: toEmail,
    to_name: toName,
    subject: `Booking Confirmation: ${propertyName} (${roomName})`,
    booking_id: bookingId,
    resort_name: propertyName,
    room_name: roomName,
    check_in_date: checkInDate,
    nights: nights,
    amount_paid: `₱${(amountPaid || 0).toLocaleString()}`,
    grand_total: `₱${(grandTotal || 0).toLocaleString()}`,
    payment_method: paymentMethod || 'GCash',
    payment_option: paymentOption || 'Full Payment',
    summary: `Your reservation for ${roomName} at ${propertyName} is being processed.`
  });
};

/**
 * Sends a Booking Status Update email (Approved / Declined / Completed)
 */
export const sendBookingStatusUpdateEmail = async ({
  toEmail,
  toName,
  bookingId,
  propertyName,
  roomName,
  newStatus,
  notes
}) => {
  return sendEmailJS(EMAILJS_CONFIG.TEMPLATES.BOOKING_STATUS_UPDATE, {
    to_email: toEmail,
    to_name: toName,
    subject: `Booking Status Update: ${newStatus.toUpperCase()} - ${propertyName}`,
    booking_id: bookingId,
    resort_name: propertyName,
    room_name: roomName,
    status: newStatus,
    notes: notes || 'No additional notes.',
    summary: `Your booking status for ${propertyName} has been updated to ${newStatus}.`
  });
};

/**
 * Sends an alert to Admin or Property Owner
 */
export const sendAdminAlertEmail = async ({
  toEmail,
  recipientRole = 'Admin',
  title,
  message,
  details
}) => {
  return sendEmailJS(EMAILJS_CONFIG.TEMPLATES.ADMIN_ALERT, {
    to_email: toEmail || 'admin@resortconnect.site',
    to_name: recipientRole,
    subject: `[System Alert] ${title}`,
    alert_title: title,
    alert_message: message,
    details: details ? JSON.stringify(details, null, 2) : '',
    summary: message
  });
};

/**
 * Sends a Welcome / Registration Email
 */
export const sendWelcomeEmail = async ({ toEmail, toName, customId, role }) => {
  return sendEmailJS(EMAILJS_CONFIG.TEMPLATES.USER_REGISTRATION, {
    to_email: toEmail,
    to_name: toName,
    subject: 'Welcome to Resort Connect!',
    custom_id: customId,
    role: role || 'Tourist',
    summary: `Welcome to Resort Connect! Your account (${customId}) has been successfully created.`
  });
};

/**
 * Sends a New Booking Notification email directly to the Resort Owner
 */
export const sendOwnerBookingNotificationEmail = async ({
  toEmail,
  ownerName,
  guestName,
  bookingType = 'room',
  itemName, // room title or activity title
  propertyName,
  checkInDate,
  nights = 1,
  pax = 1,
  totalPrice,
  amountPaid,
  paymentOption,
  paymentMethod = 'GCash',
  referenceNo,
  bookingId
}) => {
  if (!toEmail) {
    console.warn('[EmailJS] Owner email not provided. Cannot send notification.');
    return { success: false, error: 'No owner email provided' };
  }

  const subject = `New Booking Request: ${guestName} - ${itemName} (${propertyName})`;
  const typeLabel = bookingType === 'activity' ? 'Activity' : 'Room';

  return sendEmailJS(EMAILJS_CONFIG.TEMPLATES.OWNER_BOOKING_NOTIFICATION, {
    to_email: toEmail,
    to_name: ownerName || 'Resort Owner',
    owner_name: ownerName || 'Resort Owner',
    guest_name: guestName || 'Guest',
    tourist_name: guestName || 'Guest',
    resort_name: propertyName || 'Your Resort',
    property_name: propertyName || 'Your Resort',
    booking_type: typeLabel,
    item_name: itemName || 'Accommodation',
    room_name: itemName || 'Accommodation',
    activity_name: itemName || 'Accommodation',
    check_in_date: checkInDate || 'N/A',
    booking_date: checkInDate || 'N/A',
    nights: nights,
    pax: pax,
    total_price: `₱${(Number(totalPrice) || 0).toLocaleString()}`,
    total_amount: `₱${(Number(totalPrice) || 0).toLocaleString()}`,
    amount_paid: `₱${(Number(amountPaid) || 0).toLocaleString()}`,
    payment_option: paymentOption || 'Full Payment',
    payment_method: paymentMethod,
    reference_no: referenceNo || 'N/A',
    booking_id: bookingId || 'N/A',
    subject: subject,
    message: `${guestName} has submitted a new ${typeLabel.toLowerCase()} booking for "${itemName}" scheduled for ${checkInDate}. Total: ₱${(Number(totalPrice) || 0).toLocaleString()}`
  });
};
