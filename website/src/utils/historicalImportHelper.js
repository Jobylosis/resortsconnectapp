/**
 * Shared Helper for Historical Data Import (React Web Admin)
 * Handles CSV parsing, Registration Card field extraction, duplicate checks,
 * validation, pricing calculations, and Firebase batch formatting.
 */

import { format, parse, isValid } from 'date-fns';

export const SAMPLE_ROOM_CSV = `property,guestName,address,nationality,email,contactNumber,arrivalDate,departureDate,nights,pax,plateNumber,roomType,ratePerNight,totalStay,bookingSource,paymentMethod,paymentOption,note,checkedInBy
"2 Resorts and 1 Hotel","Juan D. Cruz","Makati","Filipino","juan@example.com","09171234567","10/02/26","10/03/26","1","3A","ABC-1234","RY","3730","","Agoda","OTA prepaid","Full Payment","Agoda paid","Staff Maria"
"2 Resorts and 1 Hotel","Mr. Frederick","Antipolo","","","","10/05/26","","","2A","","Rm 001","","","Walk-in","Cash","Full Payment","Paid","Staff Alex"`;

export const SAMPLE_ACTIVITY_CSV = `property,guestName,contactNumber,activityDate,activityTitle,pax,pricePerPax,timeSlot,mealAddons,paymentMethod,bookingSource,note
"2 Resorts and 1 Hotel","Juan D. Cruz","09171234567","10/02/26","Boatride to falls with meal","1","2000","09:00 AM - 10:00 AM","Lunch Set Menu (x1)","Cash","Walk-in","Paid on arrival"
"2 Resorts and 1 Hotel","Maria Santos","09181234567","10/03/26","Kayak","2","300","10:00 AM - 11:00 AM","","GCash","Facebook/Messenger","Prepaid"`;

/**
 * Parses date string in common formats: MM/DD/YY, MM/DD/YYYY, YYYY-MM-DD, MMM dd, yyyy
 */
export function parseHistoricalDate(str) {
  if (!str || typeof str !== 'string') return null;
  const trimmed = str.trim();
  if (!trimmed) return null;

  // Formats to test sequentially
  const formats = [
    'MM/dd/yy',
    'MM/dd/yyyy',
    'M/d/yy',
    'M/d/yyyy',
    'yyyy-MM-dd',
    'MMM dd, yyyy',
    'MMMM dd, yyyy',
    'dd/MM/yyyy',
    'dd/MM/yy',
  ];

  for (const fmt of formats) {
    try {
      const parsed = parse(trimmed, fmt, new Date());
      if (isValid(parsed)) {
        // Adjust for 2-digit years if needed
        const year = parsed.getFullYear();
        if (year < 2000 && year >= 1900) {
          parsed.setFullYear(year + 100);
        }
        return parsed;
      }
    } catch (_) {}
  }

  // Fallback to native Date
  const native = new Date(trimmed);
  if (isValid(native) && !isNaN(native.getTime())) {
    return native;
  }
  return null;
}

/**
 * Parses pax string e.g. "3A", "2A 1C", "3 adults", "2"
 */
export function parsePax(paxStr) {
  if (!paxStr) return { adults: 2, children: 0, total: 2 };
  const str = String(paxStr).trim().toUpperCase();

  let adults = 0;
  let children = 0;

  const adultMatch = str.match(/(\d+)\s*(A|ADULT|ADULTS)?/);
  const childMatch = str.match(/(\d+)\s*(C|CHILD|CHILDREN|KID|KIDS)/);

  if (childMatch) {
    children = parseInt(childMatch[1], 10) || 0;
  }

  if (adultMatch && (!childMatch || adultMatch.index !== childMatch.index)) {
    adults = parseInt(adultMatch[1], 10) || 0;
  } else if (!adultMatch && !childMatch) {
    const rawNum = parseInt(str, 10);
    if (!isNaN(rawNum)) adults = rawNum;
  }

  if (adults === 0 && children === 0) adults = 2;
  return { adults, children, total: adults + children };
}

/**
 * Mask sensitive string (keeps last 4 characters)
 */
export function maskSensitive(val) {
  if (!val || typeof val !== 'string') return '';
  const trimmed = val.trim();
  if (trimmed.length <= 4) return trimmed;
  const last4 = trimmed.slice(-4);
  return '*'.repeat(trimmed.length - 4) + last4;
}

/**
 * Validate and compute a single Room Stay row
 */
export function validateAndComputeRoomRow(row, property, maskData = false) {
  const errors = [];
  const warnings = [];

  const guestName = (row.guestName || row['Guest Name'] || row.name || '').trim();
  if (!guestName) errors.push('Guest Name is required');

  const arrivalRaw = row.arrivalDate || row['Arrival Date'] || row.arrival || row.checkIn || '';
  const arrivalDate = parseHistoricalDate(arrivalRaw);
  if (!arrivalDate) errors.push(`Invalid arrival date: "${arrivalRaw}"`);

  const departureRaw = row.departureDate || row['Departure Date'] || row.departure || row.checkOut || '';
  const departureDate = parseHistoricalDate(departureRaw);

  const roomTitle = (row.roomType || row.roomTitle || row['Room Type'] || row.room || '').trim();
  if (!roomTitle) errors.push('Room type is required');

  let nights = parseInt(row.nights || row['No. of nights'] || row.noOfNights, 10);
  if (isNaN(nights) || nights <= 0) {
    if (arrivalDate && departureDate) {
      const diffMs = departureDate.getTime() - arrivalDate.getTime();
      nights = Math.max(1, Math.round(diffMs / (1000 * 60 * 60 * 24)));
    } else {
      nights = 1;
      if (!departureRaw) warnings.push('Departure date empty; defaulting to 1 night');
    }
  }

  const computedDeparture = departureDate || (arrivalDate ? new Date(arrivalDate.getTime() + nights * 86400000) : null);

  const paxInfo = parsePax(row.pax || row['No. of Adults/Children'] || row.adults);
  const ratePerNight = parseFloat(row.ratePerNight || row['Rate per night'] || row.rate || 0) || 0;
  let totalStay = parseFloat(row.totalStay || row['Total stay cost'] || row.total || row.totalPrice || 0) || 0;

  if (totalStay <= 0 && ratePerNight > 0) {
    totalStay = ratePerNight * nights;
  } else if (totalStay <= 0 && ratePerNight <= 0) {
    warnings.push('Rate & Total stay are blank (₱0 totalPrice)');
  }

  let contactNumber = (row.contactNumber || row['Contact number'] || row.contact || row.phone || '').trim();
  let email = (row.email || row['E-mail'] || '').trim();

  if (maskData) {
    if (contactNumber) contactNumber = maskSensitive(contactNumber);
    if (email) email = maskSensitive(email);
  }

  const address = (row.address || row['Address'] || '').trim();
  const nationality = (row.nationality || row['Nationality'] || 'Filipino').trim();
  const plateNumber = (row.plateNumber || row['Plate number'] || '').trim();
  const bookingSource = (row.bookingSource || row.source || 'Walk-in').trim();
  const paymentMethod = (row.paymentMethod || row.method || 'Cash').trim();
  const paymentOption = (row.paymentOption || 'Full Payment').trim();
  const note = (row.note || row.notes || '').trim();
  const checkedInBy = (row.checkedInBy || row['Checked in by'] || '').trim();

  const status = errors.length > 0 ? 'invalid' : (warnings.length > 0 ? 'incomplete' : 'valid');

  return {
    status,
    errors,
    warnings,
    parsed: {
      guestName,
      address,
      nationality,
      email,
      contactNumber,
      arrivalDate,
      departureDate: computedDeparture,
      arrivalFormatted: arrivalDate ? format(arrivalDate, 'MMM dd, yyyy') : '',
      departureFormatted: computedDeparture ? format(computedDeparture, 'MMM dd, yyyy') : '',
      nights,
      adults: paxInfo.adults,
      children: paxInfo.children,
      plateNumber,
      roomTitle,
      ratePerNight,
      totalStay,
      bookingSource,
      paymentMethod,
      paymentOption,
      note,
      checkedInBy,
    }
  };
}

/**
 * Validate and compute a single Activity row
 */
export function validateAndComputeActivityRow(row, property, maskData = false) {
  const errors = [];
  const warnings = [];

  const guestName = (row.guestName || row['Guest Name'] || row.name || '').trim();
  if (!guestName) errors.push('Guest Name is required');

  const actDateRaw = row.activityDate || row['Activity Date'] || row.date || row.arrivalDate || '';
  const activityDate = parseHistoricalDate(actDateRaw);
  if (!activityDate) errors.push(`Invalid activity date: "${actDateRaw}"`);

  const activityTitle = (row.activityTitle || row.title || row.activity || '').trim();
  if (!activityTitle) errors.push('Activity title is required');

  const pax = parseInt(row.pax || 1, 10) || 1;
  const pricePerPax = parseFloat(row.pricePerPax || row.price || 0) || 0;
  if (pricePerPax <= 0) warnings.push('Price per pax is ₱0 or blank');

  // Solo surcharge rule: +750 for boatride activities when pax == 1
  const isBoatride = activityTitle.toLowerCase().includes('boatride');
  const soloSurcharge = (isBoatride && pax === 1) ? 750 : 0;
  const activitiesSubtotal = pricePerPax * pax;

  let contactNumber = (row.contactNumber || row['Contact number'] || row.contact || '').trim();
  if (maskData && contactNumber) {
    contactNumber = maskSensitive(contactNumber);
  }

  const timeSlot = (row.timeSlot || (activityTitle.toLowerCase().includes('karaoke') ? 'Entire Day (Exclusive)' : '09:00 AM - 10:00 AM')).trim();
  const mealAddons = (row.mealAddons || row.meals || '').trim();
  const selectedAddons = mealAddons ? mealAddons.split(';').map(m => m.trim()).filter(Boolean) : [];
  
  // Calculate meal total if formatted e.g. "Lunch Set Menu (x2)"
  let mealsTotal = 0;
  selectedAddons.forEach(addon => {
    const qtyMatch = addon.match(/\(x(\d+)\)/);
    const qty = qtyMatch ? parseInt(qtyMatch[1], 10) : 1;
    mealsTotal += 400 * qty; // default plated lunch standard price
  });

  const grandTotal = activitiesSubtotal + soloSurcharge + mealsTotal;
  const bookingSource = (row.bookingSource || 'Walk-in').trim();
  const paymentMethod = (row.paymentMethod || 'Cash').trim();
  const note = (row.note || '').trim();

  const status = errors.length > 0 ? 'invalid' : (warnings.length > 0 ? 'incomplete' : 'valid');

  return {
    status,
    errors,
    warnings,
    parsed: {
      guestName,
      contactNumber,
      activityDate,
      activityFormatted: activityDate ? format(activityDate, 'MMM dd, yyyy') : '',
      activityTitle,
      pax,
      pricePerPax,
      soloSurcharge,
      activitiesSubtotal,
      mealsTotal,
      grandTotal,
      timeSlot,
      selectedAddons,
      bookingSource,
      paymentMethod,
      note,
    }
  };
}

/**
 * Format payload for Firebase push to `bookings`
 */
export function formatBookingPayloadForFirebase({
  type = 'room',
  record,
  property,
  batchId,
  userUid,
  dataSource = 'csv_import'
}) {
  const p = record.parsed;
  const randSuffix = Math.random().toString(36).substring(2, 8);
  const syntheticTouristUid = `walkin_${Date.now()}_${randSuffix}`;

  if (type === 'room') {
    const arrivalDate = p.arrivalDate;
    const epochTimestamp = arrivalDate ? arrivalDate.getTime() : Date.now();

    return {
      touristUid: syntheticTouristUid,
      touristName: p.guestName,
      touristProfilePic: null,
      ownerUid: property.uid || property.id,
      propertyName: property.name || property.title || 'Resort Partner',
      roomId: 'historical',
      roomTitle: p.roomTitle,
      activityId: 'historical',
      activityTitle: p.roomTitle,
      isActivityBooking: false,
      pricing: {
        basePrice: p.totalStay,
        addonsTotal: 0,
        taxes: 0,
        grandTotal: p.totalStay
      },
      totalPrice: p.totalStay,
      amountPaid: p.totalStay,
      nights: p.nights,
      bookingDate: p.arrivalFormatted,
      departureDate: p.departureFormatted,
      status: 'Completed',
      paymentStatus: 'paid',
      paymentMethod: p.paymentMethod,
      paymentOption: p.paymentOption,
      bookingSource: p.bookingSource,
      adults: p.adults,
      children: p.children,
      plateNumber: p.plateNumber,
      nationality: p.nationality,
      address: p.address,
      contactNumber: p.contactNumber,
      email: p.email,
      note: p.note,
      checkedInBy: p.checkedInBy,
      selectedAddons: [],
      agreedToTerms: true,
      timestamp: epochTimestamp,
      createdAt: Date.now(),
      // Historical flags
      isHistorical: true,
      importBatchId: batchId,
      importedBy: userUid,
      importedAt: Date.now(),
      dataSource
    };
  } else {
    // Activity Booking
    const actDate = p.activityDate;
    const epochTimestamp = actDate ? actDate.getTime() : Date.now();

    return {
      touristUid: syntheticTouristUid,
      touristName: p.guestName,
      touristProfilePic: null,
      ownerUid: property.uid || property.id,
      propertyName: property.name || property.title || 'Resort Partner',
      roomId: 'historical',
      roomTitle: p.activityTitle,
      activityId: 'historical',
      activityTitle: p.activityTitle,
      isActivityBooking: true,
      selectedActivities: [
        {
          id: 'historical_act',
          title: p.activityTitle,
          price: p.pricePerPax,
          pax: p.pax,
          soloFee: p.soloSurcharge,
          timeSlot: p.timeSlot,
          arrivalTime: p.timeSlot,
          total: p.activitiesSubtotal + p.soloSurcharge
        }
      ],
      pricing: {
        activitiesSubtotal: p.activitiesSubtotal,
        soloSurcharges: p.soloSurcharge,
        mealsTotal: p.mealsTotal,
        grandTotal: p.grandTotal
      },
      totalPrice: p.grandTotal,
      amountPaid: p.grandTotal,
      nights: 1,
      bookingDate: p.activityFormatted,
      departureDate: p.activityFormatted,
      timeSlot: p.timeSlot,
      arrivalTime: p.timeSlot,
      status: 'Completed',
      paymentStatus: 'paid',
      paymentMethod: p.paymentMethod,
      paymentOption: 'Full Payment',
      bookingSource: p.bookingSource,
      contactNumber: p.contactNumber,
      note: p.note,
      selectedAddons: p.selectedAddons,
      agreedToTerms: true,
      timestamp: epochTimestamp,
      createdAt: Date.now(),
      // Historical flags
      isHistorical: true,
      importBatchId: batchId,
      importedBy: userUid,
      importedAt: Date.now(),
      dataSource
    };
  }
}
