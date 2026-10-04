import { format, parse, addDays } from 'date-fns';

export const parseDateSafely = (dateVal) => {
  if (!dateVal) return null;
  if (dateVal instanceof Date) return isNaN(dateVal.getTime()) ? null : dateVal;
  if (typeof dateVal === 'number') {
    const d = new Date(dateVal);
    return isNaN(d.getTime()) ? null : d;
  }
  if (typeof dateVal === 'string') {
    const trimmed = dateVal.trim();
    if (!trimmed || trimmed === 'N/A') return null;

    // Try standard ISO / standard Date constructor (handles 'yyyy-MM-dd', ISO strings, etc.)
    if (trimmed.includes('-') || trimmed.includes('T')) {
      const parts = trimmed.split('-');
      if (parts.length === 3 && !trimmed.includes('T')) {
        const yr = parseInt(parts[0], 10);
        const mo = parseInt(parts[1], 10) - 1;
        const day = parseInt(parts[2], 10);
        if (!isNaN(yr) && !isNaN(mo) && !isNaN(day)) {
          return new Date(yr, mo, day);
        }
      }
      const d = new Date(trimmed);
      if (!isNaN(d.getTime())) return d;
    }

    // Try 'MMM dd, yyyy' or 'MMMM dd, yyyy'
    try {
      const d = parse(trimmed, 'MMM dd, yyyy', new Date());
      if (!isNaN(d.getTime())) return d;
    } catch (e) {}

    try {
      const d = parse(trimmed, 'MMMM dd, yyyy', new Date());
      if (!isNaN(d.getTime())) return d;
    } catch (e) {}

    // Fallback standard Date constructor
    const fallback = new Date(trimmed);
    if (!isNaN(fallback.getTime())) return fallback;
  }
  return null;
};

export const formatBookingDateRange = (booking) => {
  if (!booking) return 'N/A';
  const rawDate = booking.bookingDate || booking.checkInDate || booking.date;
  const startDate = parseDateSafely(rawDate);
  const isActivity = booking.isActivityBooking === true ||
    (booking.activityId && String(booking.activityId).trim() !== '') ||
    (booking.activityTitle && !booking.roomId);

  if (!startDate) {
    return rawDate || 'N/A';
  }

  if (isActivity) {
    return format(startDate, 'MMM dd, yyyy');
  }

  const nights = parseInt(booking.nights, 10) || 1;
  try {
    const endDate = addDays(startDate, nights);
    return `${format(startDate, 'MMM dd, yyyy')} - ${format(endDate, 'MMM dd, yyyy')}`;
  } catch (e) {
    return rawDate || 'N/A';
  }
};
