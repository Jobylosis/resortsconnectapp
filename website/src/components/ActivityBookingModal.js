import React, { useState, useEffect, useRef, useMemo } from 'react';
import { X, Calendar as CalendarIcon, Clock, Users, ArrowRight, Info, CheckCircle2, AlertCircle, AlertTriangle, CreditCard, ChevronLeft, ChevronRight, Sparkles } from 'lucide-react';
import {
  format, addDays, isBefore,
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  eachDayOfInterval, isSameDay, isToday, addMonths, subMonths,
  startOfDay
} from 'date-fns';
import { db, auth } from '../firebase';
import { ref, push, set, get, onValue, serverTimestamp } from 'firebase/database';
import { sendBookingConfirmationEmail, sendAdminAlertEmail, sendOwnerBookingNotificationEmail } from '../services/emailService';
import TermsAndPolicies from './TermsAndPolicies';

const DEFAULT_SCHEDULE = "Kayak, Boat ride to Pagsanjan falls, and Paddle board: 7:00 AM to 3:30 PM. Bar, Karaoke, and Dinner: 7:00 AM to 10:00 PM.";

// Standard fallback catalog as specified by user requirements
const DEFAULT_ACTIVITIES = [
  { id: 'kayak', title: 'Kayak', price: 300, maxPax: 1, desc: '1 max pax per boat' },
  { id: 'paddle_board', title: 'Paddle Board', price: 300, maxPax: 1, desc: '1 max pax per board' },
  { id: 'boatride_falls', title: 'Boatride to falls', price: 1450, minPax: 1, maxPax: 3, desc: 'Min 1, Max 3 pax (+₱750 surcharge if solo passenger)' },
  { id: 'boatride_falls_meal', title: 'Boatride to falls with meal', price: 2000, minPax: 1, maxPax: 3, desc: 'Min 1, Max 3 pax with meal (+₱750 surcharge if solo passenger)' },
  { id: 'karaoke', title: 'Karaoke', price: 750, maxPax: 15, desc: 'Full set karaoke entertainment' }
];

const ActivityBookingModal = ({
  activity,
  allActivities = [],
  property,
  isOpen,
  isMultiMode = false,
  onClose,
  ownerUid,
  propertyName,
  touristInfo,
  activitySchedule
}) => {
  const [step, setStep] = useState(1); // 1: Select Activities, Meals & Date, 2: Payment Proof, 3: Success
  const modalContentRef = useRef(null);
  useEffect(() => {
    if (modalContentRef.current) {
      modalContentRef.current.scrollTo({ top: 0, behavior: 'smooth' });
    }
  }, [step]);
  const [selectedDate, setSelectedDate] = useState(null);
  const [currentMonth, setCurrentMonth] = useState(new Date());

// Standard Operating Hours time slots (7:00 AM to 5:00 PM, 1-hour increments)
const TIME_SLOTS = [
  '07:00 AM - 08:00 AM',
  '08:00 AM - 09:00 AM',
  '09:00 AM - 10:00 AM',
  '10:00 AM - 11:00 AM',
  '11:00 AM - 12:00 PM',
  '12:00 PM - 01:00 PM',
  '01:00 PM - 02:00 PM',
  '02:00 PM - 03:00 PM',
  '03:00 PM - 04:00 PM',
  '04:00 PM - 05:00 PM'
];

  // Selected activities state: { [actId]: { count: number, pax: number } }
  const [selectedActs, setSelectedActs] = useState({});

  // Arrival time / time slot per activity: { [actId]: string }
  const [arrivalTimes, setArrivalTimes] = useState({});

  // Existing property bookings for activity conflict detection
  const [existingBookings, setExistingBookings] = useState([]);

  // Meal add-ons state: { [mealName]: quantity }
  const [selectedMeals, setSelectedMeals] = useState({ Lunch: 0, Dinner: 0 });

  // Payment states
  const [paymentOption, setPaymentOption] = useState('full'); // 'downpayment' | 'full'
  const [receiptUrl, setReceiptUrl] = useState(null);
  const [extractedRefNo, setExtractedRefNo] = useState(null);
  const [ocrStatus, setOcrStatus] = useState(null); // 'Verified' | 'Flagged'
  const [ocrIssues, setOcrIssues] = useState('');
  const [showOcrAlert, setShowOcrAlert] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [agreedToTerms, setAgreedToTerms] = useState(false);
  const [showPolicies, setShowPolicies] = useState(null);

  // Real-time listener for existing property bookings
  useEffect(() => {
    const targetOwner = property?.uid || ownerUid;
    const bookingsRef = ref(db, 'bookings');
    const unsub = onValue(bookingsRef, (snap) => {
      if (snap.exists()) {
        const val = snap.val();
        const list = (Array.isArray(val) ? val.filter(Boolean) : Object.values(val)).filter(b => {
          if (!b) return false;
          const belongsToOwner = !targetOwner || b.ownerUid === targetOwner;
          const status = (b.status || '').toLowerCase().trim();
          const isActive = status !== 'cancelled' && status !== 'declined' && status !== 'refund approved';
          return belongsToOwner && isActive;
        });
        setExistingBookings(list);
      } else {
        setExistingBookings([]);
      }
    });
    return () => unsub();
  }, [property?.uid, ownerUid]);

  const formatPrice = (val) => {
    const num = Number(val) || 0;
    return num.toLocaleString('en-US', {
      minimumFractionDigits: num % 1 !== 0 ? 2 : 0,
      maximumFractionDigits: 2
    });
  };

  // Initialize catalog with fallback memoized against allActivities
  const catalog = useMemo(() => {
    return (allActivities && allActivities.length > 0)
      ? allActivities.map(a => {
          const titleLower = (a.title || '').toLowerCase();
          let minPax = a.minPax || 1;
          let maxPax = parseInt(a.maxPax) || 1;
          let isBoatride = titleLower.includes('boatride') || titleLower.includes('boat ride');

          if (isBoatride) {
            minPax = 1;
            maxPax = 3;
          } else if (titleLower.includes('kayak') || titleLower.includes('paddle board')) {
            maxPax = 1;
          }

          return {
            id: a.id || a.key || a.title,
            title: a.title,
            price: Number(a.price || 0),
            minPax,
            maxPax,
            isBoatride,
            desc: a.description || (isBoatride ? 'Min 1, Max 3 pax (+₱750 surcharge if solo passenger)' : `Max ${maxPax} pax`)
          };
        })
      : DEFAULT_ACTIVITIES.map(a => ({
          ...a,
          isBoatride: a.title.toLowerCase().includes('boatride')
        }));
  }, [allActivities]);

  // Active catalog: if isMultiMode is false and an activity is provided, only show that independent activity!
  const activeCatalog = useMemo(() => {
    if (!isMultiMode && activity) {
      const match = catalog.find(c => c.id === activity.id || c.title === activity.title);
      return match ? [match] : catalog;
    }
    return catalog;
  }, [catalog, isMultiMode, activity]);

  // Initial selection only runs when the modal opens (isOpen transition to true or activity changes)
  const prevIsOpenRef = useRef(false);
  useEffect(() => {
    if (!isOpen) {
      prevIsOpenRef.current = false;
      return;
    }
    // Only reset state if the modal just opened
    if (!prevIsOpenRef.current) {
      prevIsOpenRef.current = true;
      setStep(1);
      setReceiptUrl(null);
      setExtractedRefNo(null);
      setOcrStatus(null);
      setOcrIssues('');
      setAgreedToTerms(false);

      if (activity) {
        const match = catalog.find(c => c.id === activity.id || c.title === activity.title) || catalog[0];
        if (match) {
          setSelectedActs({
            [match.id]: {
              selected: true,
              pax: match.isBoatride ? 2 : 1
            }
          });
        }
      } else if (catalog.length > 0) {
        setSelectedActs({
          [catalog[0].id]: { selected: true, pax: 1 }
        });
      }
    }
  }, [isOpen, activity, catalog, isMultiMode]);

  if (!isOpen) return null;

  const scheduleText = activitySchedule || DEFAULT_SCHEDULE;

  // Meal pricing from property addonPrices
  const mealPrices = property?.addonPrices || {};

  const toggleActivity = (act) => {
    setSelectedActs(prev => {
      const exists = prev[act.id]?.selected;
      if (exists) {
        const next = { ...prev };
        delete next[act.id];
        return next;
      }
      return {
        ...prev,
        [act.id]: {
          selected: true,
          pax: act.isBoatride ? 2 : 1
        }
      };
    });
    setReceiptUrl(null); setOcrStatus(null); setExtractedRefNo(null);
  };

  const updatePax = (act, delta) => {
    setSelectedActs(prev => {
      const current = prev[act.id] || { selected: true, pax: 1 };
      let nextPax = (current.pax || 1) + delta;
      const minP = act.minPax || 1;
      const maxP = act.maxPax || 10;
      if (nextPax < minP) nextPax = minP;
      if (nextPax > maxP) nextPax = maxP;
      return {
        ...prev,
        [act.id]: { selected: true, pax: nextPax }
      };
    });
    setReceiptUrl(null); setOcrStatus(null); setExtractedRefNo(null);
  };

  const updateMealQty = (name, delta) => {
    setSelectedMeals(prev => {
      const curr = prev[name] || 0;
      const next = Math.max(0, Math.min(20, curr + delta));
      return { ...prev, [name]: next };
    });
    setReceiptUrl(null); setOcrStatus(null); setExtractedRefNo(null);
  };

  // Helper: check if a booking matches a given date
  const isBookingOnDate = (b, targetDateStr) => {
    if (!b || !targetDateStr) return false;
    const bDate = b.bookingDate || b.checkInDate || b.date;
    if (bDate) {
      if (bDate === targetDateStr) return true;
      try {
        const parsed = new Date(bDate);
        if (!isNaN(parsed.getTime()) && format(parsed, 'MMM dd, yyyy') === targetDateStr) {
          return true;
        }
      } catch (e) {}
    }
    return false;
  };

  // Helper: check if an activity title refers to Karaoke
  const isKaraokeTitle = (title) => {
    return (title || '').toLowerCase().includes('karaoke');
  };

  // Check if Karaoke is booked on the selected date
  const isKaraokeBookedOnDate = (targetDate) => {
    if (!targetDate) return false;
    const targetStr = format(targetDate, 'MMM dd, yyyy');
    return existingBookings.some(b => {
      if (!isBookingOnDate(b, targetStr)) return false;
      if (isKaraokeTitle(b.activityTitle)) return true;
      if (Array.isArray(b.selectedActivities) && b.selectedActivities.some(a => isKaraokeTitle(a.title))) return true;
      if (Array.isArray(b.activityList) && b.activityList.some(a => isKaraokeTitle(a.title))) return true;
      return false;
    });
  };

  // Get occupied time slots for a specific activity on selectedDate
  const getOccupiedSlotsForActivity = (act, targetDate) => {
    if (!targetDate || !act) return [];
    if (isKaraokeTitle(act.title)) {
      return isKaraokeBookedOnDate(targetDate) ? [...TIME_SLOTS] : [];
    }

    const targetStr = format(targetDate, 'MMM dd, yyyy');
    const actIdNorm = String(act.id || '').toLowerCase();
    const actTitleNorm = (act.title || '').toLowerCase();

    const occupied = new Set();

    existingBookings.forEach(b => {
      if (!isBookingOnDate(b, targetStr)) return;

      // Extract slot if this booking matches the activity
      const checkAndAdd = (itemTitle, itemId, slot) => {
        if (!slot || slot === 'Regular Operating Hours') return;
        const itTitleNorm = (itemTitle || '').toLowerCase();
        const itIdNorm = String(itemId || '').toLowerCase();
        if (
          itTitleNorm === actTitleNorm ||
          (actTitleNorm.includes('boatride') && itTitleNorm.includes('boatride')) ||
          (actTitleNorm.includes('kayak') && itTitleNorm.includes('kayak')) ||
          (actTitleNorm.includes('paddle') && itTitleNorm.includes('paddle')) ||
          (itIdNorm && itIdNorm === actIdNorm)
        ) {
          occupied.add(slot);
        }
      };

      if (Array.isArray(b.activityList)) {
        b.activityList.forEach(item => {
          checkAndAdd(item.title, item.id, item.timeSlot || item.arrivalTime || b.timeSlot);
        });
      } else if (Array.isArray(b.selectedActivities)) {
        b.selectedActivities.forEach(item => {
          checkAndAdd(item.title, item.id, item.timeSlot || item.arrivalTime || b.timeSlot);
        });
      } else {
        checkAndAdd(b.activityTitle, b.activityId, b.timeSlot || b.arrivalTime);
      }
    });

    return Array.from(occupied);
  };

  // Pricing Calculation
  const calculatePricing = () => {
    let activitiesSubtotal = 0;
    let boatrideSurcharge = 0;
    const selectedItemsList = [];

    Object.entries(selectedActs).forEach(([actId, data]) => {
      if (!data?.selected) return;
      const act = catalog.find(c => c.id === actId);
      if (!act) return;

      const pax = data.pax || 1;
      let itemTotal = act.price;

      // Rule: Boatride is ₱1450 (or ₱2000 with meal) min 1 max 3 pax.
      // If the boatride only has 1 passenger it has a ₱750 pesos surcharge.
      let surcharge = 0;
      if (act.isBoatride && pax === 1) {
        surcharge = 750;
        boatrideSurcharge += surcharge;
      }

      const assignedTime = isKaraokeTitle(act.title)
        ? 'Entire Day (Exclusive)'
        : (arrivalTimes[act.id] || '');

      activitiesSubtotal += itemTotal;
      selectedItemsList.push({
        id: act.id,
        title: act.title,
        price: act.price,
        pax,
        surcharge,
        timeSlot: assignedTime,
        total: itemTotal + surcharge
      });
    });

    // Meals Add-ons
    let mealsTotal = 0;
    const mealsList = [];
    Object.entries(selectedMeals).forEach(([meal, qty]) => {
      if (qty > 0) {
        const cost = (mealPrices[meal] || 400) * qty;
        mealsTotal += cost;
        mealsList.push({ name: meal, quantity: qty, price: mealPrices[meal], total: cost });
      }
    });

    const grandTotal = parseFloat((activitiesSubtotal + boatrideSurcharge + mealsTotal).toFixed(2));
    const downpaymentAmount = parseFloat((grandTotal * 0.3).toFixed(2));
    const amountToPay = paymentOption === 'full' ? grandTotal : downpaymentAmount;
    const remainingAtResort = parseFloat(Math.max(0, grandTotal - downpaymentAmount).toFixed(2));

    return {
      activitiesSubtotal,
      boatrideSurcharge,
      selectedItemsList,
      mealsTotal,
      mealsList,
      grandTotal,
      downpaymentAmount,
      amountToPay,
      remainingAtResort
    };
  };

  const pricing = calculatePricing();

  // Receipt File Upload & OCR Validation
  const handleFileUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    setUploading(true);
    setOcrIssues('');

    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', 'resort_unsigned');

    try {
      // 1. Strict OCR Validation
      const ocrFormData = new FormData();
      ocrFormData.append('image', file);
      ocrFormData.append('expectedAmount', Number(pricing.amountToPay).toFixed(2));
      ocrFormData.append('expectedRecipient', property?.gcashName || '');

      let ocrErrorMsg = '';
      let isVerified = false;

      try {
        const ocrResponse = await fetch('https://walk-versus-peculiar.ngrok-free.dev/extract_reference', {
          method: 'POST',
          headers: { 'ngrok-skip-browser-warning': '69420' },
          body: ocrFormData,
        });
        const ocrData = await ocrResponse.json();

        if (ocrData.success) {
          // Check for duplicate reference
          const usedRefSnapshot = await get(ref(db, `used_receipts/${property?.uid || ownerUid}`));
          let usedReceipts = [];
          if (usedRefSnapshot.exists()) {
            usedReceipts = usedRefSnapshot.val() || [];
            if (!Array.isArray(usedReceipts)) {
              usedReceipts = Object.values(usedReceipts);
            }
          }
          usedReceipts = usedReceipts.map(r => String(r));
          if (usedReceipts.includes(String(ocrData.reference_number))) {
            alert("This receipt reference number has already been used for another booking.");
            setUploading(false);
            e.target.value = null;
            return;
          }

          isVerified = true;
          setExtractedRefNo(ocrData.reference_number);
        } else {
          ocrErrorMsg = ocrData.error || "Could not auto-verify GCash receipt.";
          setOcrIssues(ocrErrorMsg);
          setShowOcrAlert(true);
        }
      } catch (ocrError) {
        ocrErrorMsg = "OCR Server unreachable. Sent for manual host review.";
        setOcrIssues(ocrErrorMsg);
      }

      // 2. Cloudinary Upload
      const response = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', {
        method: 'POST',
        body: formData,
      });
      const data = await response.json();

      setReceiptUrl(data.secure_url);
      setOcrStatus(isVerified ? 'Verified' : 'Flagged');
    } catch (error) {
      alert('Upload failed. Please try again.');
    } finally {
      setUploading(false);
      e.target.value = null;
    }
  };

  const submitBooking = async () => {
    if (uploading) return;
    if (!receiptUrl) {
      return alert("Please upload your GCash payment screenshot.");
    }
    if (!agreedToTerms) {
      return alert("Please agree to the Terms & Conditions and Policies.");
    }

    setUploading(true);

    try {
      // Prevent duplicate receipt usage
      if (extractedRefNo) {
        try {
          const usedRefSnapshot = await get(ref(db, `used_receipts/${property?.uid || ownerUid}`));
          let usedReceipts = [];
          if (usedRefSnapshot.exists()) {
            usedReceipts = usedRefSnapshot.val() || [];
            if (!Array.isArray(usedReceipts)) {
              usedReceipts = Object.values(usedReceipts);
            }
          }
          usedReceipts = usedReceipts.map(r => String(r));
          if (usedReceipts.includes(String(extractedRefNo))) {
            alert("This receipt reference number has already been used for another booking.");
            setUploading(false);
            return;
          }
          usedReceipts.push(extractedRefNo);
          if (usedReceipts.length > 500) {
            usedReceipts = usedReceipts.slice(usedReceipts.length - 500);
          }
          await set(ref(db, `used_receipts/${property?.uid || ownerUid}`), usedReceipts);
        } catch (e) {
          console.error("Error checking used receipts", e);
        }
      }

      const bookingRef = push(ref(db, 'bookings'));
      const guestName = touristInfo?.name || touristInfo?.fullName || 'Guest';
      const formattedDate = selectedDate ? format(selectedDate, 'MMM dd, yyyy') : format(new Date(), 'MMM dd, yyyy');

      const itemsSummary = pricing.selectedItemsList.map(i => `${i.title} (${i.pax} pax)`).join(', ');
      const addonsSummary = pricing.mealsList.map(m => `${m.name} (x${m.quantity})`);

      const bookingData = {
        type: 'activity',
        bookingCategory: 'activity',
        touristUid: touristInfo?.uid || auth.currentUser?.uid || 'guest',
        touristName: guestName,
        touristProfilePic: touristInfo?.profilePicUrl || '',
        ownerUid: property?.uid || ownerUid,
        propertyName: propertyName || property?.name || 'Property',
        activityTitle: itemsSummary || 'Activities Booking',
        activityId: pricing.selectedItemsList.length === 1 ? pricing.selectedItemsList[0].id : '',
        activityList: pricing.selectedItemsList,
        isActivityBooking: true,
        hours: 1,
        bookingDate: formattedDate,
        checkInDate: formattedDate,
        nights: 1,
        timeSlot: pricing.selectedItemsList.map(i => `${i.title}: ${i.timeSlot}`).join(', ') || 'Regular Operating Hours',
        arrivalTime: pricing.selectedItemsList.map(i => `${i.title}: ${i.timeSlot}`).join(', ') || 'Regular Operating Hours',
        totalPrice: pricing.grandTotal,
        amountPaid: pricing.amountToPay,
        paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment',
        paymentMethod: 'GCash',
        status: 'Pending',
        paymentStatus: ocrStatus === 'Verified' ? 'paid' : 'pending',
        gcashReceipt: receiptUrl || '',
        extractedRefNo: extractedRefNo || '',
        ocrStatus: ocrStatus || 'Unverified',
        ocrIssues: ocrIssues || '',
        pricing: {
          activitiesSubtotal: pricing.activitiesSubtotal,
          boatrideSurcharge: pricing.boatrideSurcharge,
          mealsTotal: pricing.mealsTotal,
          grandTotal: pricing.grandTotal,
          amountPaid: pricing.amountToPay,
          remainingAtResort: pricing.remainingAtResort
        },
        selectedAddons: addonsSummary,
        agreedToTerms: true,
        termsAcceptedAt: serverTimestamp(),
        timestamp: serverTimestamp(),
      };

      await set(bookingRef, bookingData);

      // Notification in DB
      try {
        const notifRef = push(ref(db, `notifications/${property?.uid || ownerUid}`));
        await set(notifRef, {
          title: 'New Activity Reservation',
          message: `${guestName} booked activities (${itemsSummary}) for ${formattedDate}.`,
          type: 'new_booking',
          isRead: false,
          timestamp: serverTimestamp(),
          bookingId: bookingRef.key
        });
      } catch (e) {
        console.warn('DB notification warning:', e);
      }

      // Email notifications
      const touristEmail = touristInfo?.email || auth.currentUser?.email;
      if (touristEmail) {
        sendBookingConfirmationEmail({
          toEmail: touristEmail,
          toName: guestName,
          bookingId: bookingRef.key,
          propertyName: propertyName || 'Resort',
          roomName: itemsSummary || 'Resort Activities',
          checkInDate: formattedDate,
          nights: 1,
          amountPaid: pricing.amountToPay,
          grandTotal: pricing.grandTotal,
          paymentMethod: 'GCash',
          paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment'
        }).catch(err => console.warn('[EmailJS] Guest confirmation error:', err));
      }

      try {
        let ownerEmail = property?.contact?.email || property?.email;
        let ownerName = propertyName || 'Resort Owner';

        if (!ownerEmail && ownerUid) {
          const ownerSnap = await get(ref(db, `users/${ownerUid}`));
          if (ownerSnap.exists()) {
            const uData = ownerSnap.val();
            ownerEmail = uData.email;
            ownerName = uData.firstName ? `${uData.firstName} ${uData.lastName || ''}`.trim() : ownerName;
          }
        }

        if (ownerEmail) {
          sendOwnerBookingNotificationEmail({
            toEmail: ownerEmail,
            ownerName: ownerName,
            guestName: guestName,
            bookingType: 'activity',
            itemName: itemsSummary || 'Resort Activities',
            propertyName: propertyName || 'Your Resort',
            checkInDate: formattedDate,
            nights: 1,
            pax: pricing.selectedItemsList.reduce((acc, i) => acc + i.pax, 0),
            totalPrice: pricing.grandTotal,
            amountPaid: pricing.amountToPay,
            paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment',
            paymentMethod: 'GCash',
            referenceNo: extractedRefNo || 'Manual Review',
            bookingId: bookingRef.key
          }).catch(err => console.warn('[EmailJS] Owner notification error:', err));
        }
      } catch (e) {
        console.warn('[EmailJS] Owner email fetch error:', e);
      }

      // Admin Alert
      sendAdminAlertEmail({
        title: 'New Activity Booking',
        message: `${guestName} booked activities (${itemsSummary}) at ${propertyName}.`,
        details: {
          bookingId: bookingRef.key,
          tourist: guestName,
          total: pricing.grandTotal,
          items: itemsSummary
        }
      }).catch(err => console.warn('[EmailJS] Admin alert error:', err));

      setStep(3); // Success Step
    } catch (err) {
      alert("Booking failed: " + err.message);
    } finally {
      setUploading(false);
    }
  };

  const renderCalendar = () => {
    const monthStart = startOfMonth(currentMonth);
    const monthEnd = endOfMonth(monthStart);
    const startDate = startOfWeek(monthStart);
    const endDate = endOfWeek(monthEnd);

    const calendarDays = eachDayOfInterval({ start: startDate, end: endDate });
    const daysOfWeek = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return (
      <div className="modern-calendar" style={{ background: 'var(--light-bg)', padding: '20px', borderRadius: '24px', border: '1px solid var(--border)' }}>
        <div className="calendar-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>{format(currentMonth, 'MMMM yyyy')}</h3>
          <div style={{ display: 'flex', gap: '8px' }}>
            <button type="button" onClick={() => setCurrentMonth(subMonths(currentMonth, 1))} className="nav-btn"><ChevronLeft size={18} /></button>
            <button type="button" onClick={() => setCurrentMonth(addMonths(currentMonth, 1))} className="nav-btn"><ChevronRight size={18} /></button>
          </div>
        </div>
        <div className="calendar-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: '8px' }}>
          {daysOfWeek.map((day, i) => (
            <div key={i} className="day-label" style={{ textAlign: 'center', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', paddingBottom: '10px' }}>{day}</div>
          ))}
          {calendarDays.map((day, idx) => {
            const isSelected = selectedDate && isSameDay(day, selectedDate);
            const isPast = isBefore(startOfDay(day), startOfDay(new Date()));
            const isCurrentMonth = isSameDay(startOfMonth(day), monthStart);

            let className = "calendar-day";
            if (!isCurrentMonth) className += " other-month";
            if (isSelected) className += " selected";
            if (isPast) className += " past";
            if (isToday(day)) className += " today";

            return (
              <button
                key={idx}
                type="button"
                className={className}
                disabled={isPast}
                onClick={() => setSelectedDate(day)}
              >
                {format(day, 'd')}
              </button>
            );
          })}
        </div>
      </div>
    );
  };

  return (
    <>
      <div className="modal-overlay" style={{ zIndex: 3000, background: 'rgba(0,0,0,0.65)', backdropFilter: 'blur(4px)' }}>
        {showOcrAlert && (
          <div className="modal-overlay" style={{ zIndex: 4000 }}>
            <div className="card modal-content" style={{ maxWidth: '400px', padding: '32px', textAlign: 'center', borderRadius: '32px' }}>
              <div style={{ width: '64px', height: '64px', background: 'rgba(217, 119, 6, 0.1)', borderRadius: '50%', display: 'flex', justifyContent: 'center', alignItems: 'center', margin: '0 auto 24px' }}>
                <AlertTriangle size={32} color="#D97706" />
              </div>
              <h3 style={{ margin: '0 0 12px 0', fontSize: '20px', fontWeight: 800 }}>Validation Flagged</h3>
              <p style={{ color: 'var(--text-muted)', fontSize: '14px', lineHeight: '1.6', marginBottom: '24px' }}>
                <strong>Notice:</strong> {ocrIssues}<br/><br/>
                The host will review your uploaded screenshot manually upon submission.
              </p>
              <button className="btn btn-primary" onClick={() => setShowOcrAlert(false)} style={{ width: '100%', padding: '14px', borderRadius: '16px', fontWeight: 800 }}>OK, Continue</button>
            </div>
          </div>
        )}

        {showPolicies && <TermsAndPolicies onClose={() => setShowPolicies(null)} initialScroll={showPolicies} />}

        <div ref={modalContentRef} className="card modal-content" style={{ maxWidth: '560px', width: '100%', padding: '32px', borderRadius: '32px', maxHeight: '90vh', overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>
              {step === 1 ? (!isMultiMode && activity ? `Book ${activity.title}` : 'Book Activities') : step === 2 ? 'Payment Proof' : 'Booking Confirmed'}
            </h2>
            <p style={{ margin: '4px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>
              {propertyName || 'Resort Activities'}
            </p>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        {/* STEP 1: Select Activities, Meals & Date */}
        {step === 1 && (
          <div className="step-content">
            {/* Operating Schedule Notice */}
            <div style={{
              background: 'rgba(245, 158, 11, 0.08)',
              border: '1px solid rgba(245, 158, 11, 0.3)',
              borderRadius: '16px',
              padding: '14px 16px',
              display: 'flex',
              gap: '12px',
              alignItems: 'flex-start',
              marginBottom: '20px'
            }}>
              <div style={{ background: '#F59E0B', color: 'white', borderRadius: '50%', width: '26px', height: '26px', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginTop: '2px' }}>
                <Clock size={15} />
              </div>
              <div>
                <div style={{ fontSize: '12px', fontWeight: 800, color: '#B45309', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '2px' }}>
                  Activity Operating Schedule
                </div>
                <div style={{ fontSize: '13px', color: 'var(--text-main)', lineHeight: '1.4', fontWeight: 600 }}>
                  {scheduleText}
                </div>
              </div>
            </div>

            {/* Date Selection Calendar */}
            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Select Date</label>
              {renderCalendar()}
              <div className="calendar-legend" style={{ display: 'flex', gap: '16px', marginTop: '12px', justifyContent: 'center' }}>
                <div className="legend-item"><span className="dot available"></span> <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)' }}>Open</span></div>
                <div className="legend-item"><span className="dot booked"></span> <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)' }}>Unavailable</span></div>
              </div>
              {selectedDate && (
                <div style={{ marginTop: '10px', textAlign: 'center', fontSize: '13px', fontWeight: 700, color: 'var(--secondary)' }}>
                  Selected: {format(selectedDate, 'MMMM dd, yyyy')}
                </div>
              )}
            </div>

            {/* Multi-Activity Choices or Single Selected Activity */}
            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">
                {!isMultiMode && activity
                  ? `Selected Activity: ${activity.title}`
                  : 'Select Activities (Choose Multiple)'}
              </label>

              {/* Show Global Notice if any selected activity has occupied slots on selectedDate */}
              {selectedDate && Object.keys(selectedActs).some(id => {
                const act = activeCatalog.find(c => c.id === id);
                if (!act || isKaraokeTitle(act.title)) return false;
                const occ = getOccupiedSlotsForActivity(act, selectedDate);
                return occ.length > 0;
              }) && (
                <div style={{
                  background: 'rgba(239, 68, 68, 0.08)',
                  border: '1px solid rgba(239, 68, 68, 0.3)',
                  borderRadius: '14px',
                  padding: '12px 14px',
                  marginBottom: '16px',
                  display: 'flex',
                  alignItems: 'flex-start',
                  gap: '10px'
                }}>
                  <AlertCircle size={18} color="#DC2626" style={{ flexShrink: 0, marginTop: '2px' }} />
                  <div style={{ fontSize: '12.5px', color: '#B91C1C', lineHeight: '1.4' }}>
                    {Object.keys(selectedActs).map(id => {
                      const act = activeCatalog.find(c => c.id === id);
                      if (!act || isKaraokeTitle(act.title)) return null;
                      const occ = getOccupiedSlotsForActivity(act, selectedDate);
                      if (occ.length === 0) return null;
                      return (
                        <div key={id} style={{ marginBottom: '4px' }}>
                          <strong>Notice:</strong> <strong>{act.title}</strong> is occupied for <strong>{occ.join(', ')}</strong> on this date. Please choose from the remaining free hours below.
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                {activeCatalog.map(act => {
                  const isKaraoke = isKaraokeTitle(act.title);
                  const isKaraokeDisabled = isKaraoke && selectedDate && isKaraokeBookedOnDate(selectedDate);
                  const occupiedSlots = selectedDate ? getOccupiedSlotsForActivity(act, selectedDate) : [];
                  const isAllSlotsOccupied = !isKaraoke && TIME_SLOTS.length > 0 && occupiedSlots.length >= TIME_SLOTS.length;
                  const isActivityDisabled = isKaraokeDisabled || isAllSlotsOccupied;

                  // If in single mode, always treat the single activity as selected unless disabled
                  const isSingle = !isMultiMode && activity;
                  const isSelected = (isSingle || !!selectedActs[act.id]?.selected) && !isActivityDisabled;
                  const currentPax = selectedActs[act.id]?.pax || 1;
                  const isBoatrideSolo = act.isBoatride && isSelected && currentPax === 1;
                  const currentSlot = arrivalTimes[act.id] || '';

                  return (
                    <div
                      key={act.id}
                      onClick={() => {
                        if (isActivityDisabled) return;
                        if (!isSingle) toggleActivity(act);
                      }}
                      style={{
                        padding: '16px',
                        borderRadius: '16px',
                        border: '2px solid',
                        borderColor: isActivityDisabled ? '#E5E7EB' : isSelected ? 'var(--secondary)' : 'var(--border)',
                        background: isActivityDisabled ? '#F9FAFB' : isSelected ? 'rgba(29, 211, 176, 0.05)' : 'var(--surface)',
                        cursor: isActivityDisabled ? 'not-allowed' : (isSingle ? 'default' : 'pointer'),
                        opacity: isActivityDisabled ? 0.6 : 1,
                        transition: 'all 0.2s'
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
                          {!isSingle && (
                            <input
                              type="checkbox"
                              checked={isSelected}
                              disabled={isActivityDisabled}
                              onClick={(e) => e.stopPropagation()}
                              onChange={() => {
                                if (isActivityDisabled) return;
                                toggleActivity(act);
                              }}
                              style={{ width: '18px', height: '18px', marginTop: '3px', cursor: isActivityDisabled ? 'not-allowed' : 'pointer' }}
                            />
                          )}
                          <div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                              <span style={{ fontSize: '15px', fontWeight: 800, color: isActivityDisabled ? '#9CA3AF' : 'var(--text-main)' }}>
                                {act.title}
                              </span>
                              {isKaraokeDisabled && (
                                <span style={{
                                  fontSize: '11px',
                                  fontWeight: 700,
                                  color: '#DC2626',
                                  background: '#FEE2E2',
                                  padding: '2px 8px',
                                  borderRadius: '6px'
                                }}>
                                  Occupied (Booked for the whole day)
                                </span>
                              )}
                              {isAllSlotsOccupied && (
                                <span style={{
                                  fontSize: '11px',
                                  fontWeight: 700,
                                  color: '#DC2626',
                                  background: '#FEE2E2',
                                  padding: '2px 8px',
                                  borderRadius: '6px'
                                }}>
                                  Fully Occupied for this date
                                </span>
                              )}
                            </div>
                            <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>
                              {act.desc}
                            </div>
                            {isBoatrideSolo && (
                              <div style={{ fontSize: '12px', color: '#B45309', fontWeight: 700, marginTop: '4px', background: 'rgba(245, 158, 11, 0.15)', padding: '2px 8px', borderRadius: '6px', display: 'inline-block' }}>
                                +₱750 Single Passenger Fee Applied
                              </div>
                            )}
                          </div>
                        </div>
                        <div style={{ textAlign: 'right' }}>
                          <div style={{ fontSize: '16px', fontWeight: 900, color: isActivityDisabled ? '#9CA3AF' : 'var(--secondary)' }}>
                            ₱{(act.price + (isBoatrideSolo ? 750 : 0)).toLocaleString()}
                          </div>
                          <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                            {act.isBoatride ? 'per trip' : 'per unit'}
                          </div>
                        </div>
                      </div>

                      {/* Pax Counter if Activity is Selected and supports pax adjustment */}
                      {isSelected && (
                        <div
                          onClick={e => e.stopPropagation()}
                          style={{
                            marginTop: '12px',
                            paddingTop: '12px',
                            borderTop: '1px solid var(--border)',
                            display: 'flex',
                            justifyContent: 'space-between',
                            alignItems: 'center'
                          }}
                        >
                          <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-muted)' }}>
                            Passengers / Pax:
                          </span>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                            <button
                              type="button"
                              onClick={() => updatePax(act, -1)}
                              className="counter-btn-small"
                              disabled={currentPax <= (act.minPax || 1)}
                              style={{ opacity: currentPax <= (act.minPax || 1) ? 0.3 : 1 }}
                            >
                              -
                            </button>
                            <span style={{ minWidth: '32px', textAlign: 'center', fontWeight: 800, fontSize: '14px' }}>
                              {currentPax}
                            </span>
                            <button
                              type="button"
                              onClick={() => updatePax(act, 1)}
                              className="counter-btn-small"
                              disabled={currentPax >= (act.maxPax || 10)}
                              style={{ opacity: currentPax >= (act.maxPax || 10) ? 0.3 : 1 }}
                            >
                              +
                            </button>
                            <span style={{ fontSize: '11px', color: 'var(--text-muted)', marginLeft: '4px' }}>
                              (Max {act.maxPax} pax)
                            </span>
                          </div>
                        </div>
                      )}

                      {/* Arrival Time Selection for Selected Non-Karaoke Activities */}
                      {isSelected && !isKaraoke && (
                        <div
                          onClick={e => e.stopPropagation()}
                          style={{
                            marginTop: '10px',
                            paddingTop: '10px',
                            borderTop: '1px dashed var(--border)',
                          }}
                        >
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                            <label style={{ fontSize: '12.5px', fontWeight: 700, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                              <Clock size={14} color="var(--secondary)" />
                              Time of Arrival / Schedule:
                            </label>
                            {occupiedSlots.length > 0 && (
                              <span style={{ fontSize: '11px', color: '#D97706', fontWeight: 600 }}>
                                {occupiedSlots.length} slot(s) occupied
                              </span>
                            )}
                          </div>

                          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', alignItems: 'center', marginBottom: '8px' }}>
                            <span style={{ fontSize: '11px', fontWeight: 700, color: '#16A34A' }}>Free Hours:</span>
                            {TIME_SLOTS.filter(s => !occupiedSlots.includes(s)).map(slot => (
                              <span
                                key={slot}
                                onClick={() => setArrivalTimes(prev => ({ ...prev, [act.id]: slot }))}
                                style={{
                                  fontSize: '11px',
                                  fontWeight: 700,
                                  color: currentSlot === slot ? '#FFFFFF' : '#15803D',
                                  background: currentSlot === slot ? '#16A34A' : '#DCFCE7',
                                  border: '1px solid #86EFAC',
                                  borderRadius: '6px',
                                  padding: '2px 8px',
                                  cursor: 'pointer',
                                  transition: 'all 0.15s ease'
                                }}
                                title="Click to choose this free hour"
                              >
                                {slot}
                              </span>
                            ))}
                          </div>

                          <select
                            value={currentSlot}
                            onChange={(e) => {
                              const val = e.target.value;
                              setArrivalTimes(prev => ({ ...prev, [act.id]: val }));
                            }}
                            style={{
                              width: '100%',
                              padding: '10px 12px',
                              borderRadius: '10px',
                              border: '1.5px solid var(--border)',
                              fontSize: '13px',
                              fontWeight: 600,
                              background: 'var(--surface)',
                              color: 'var(--text-main)',
                              outline: 'none',
                              cursor: 'pointer'
                            }}
                          >
                            <option value="">-- Choose Arrival Time --</option>
                            {TIME_SLOTS.map(slot => {
                              const isOccupied = occupiedSlots.includes(slot);
                              return (
                                <option key={slot} value={slot} disabled={isOccupied}>
                                  {isOccupied ? `${slot} (Occupied)` : slot}
                                </option>
                              );
                            })}
                          </select>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Food / Meal Menu Add-ons */}
            {property?.enableCustomMenuUpload !== true && Object.keys(mealPrices).length > 0 && (
              <div style={{ marginBottom: '24px' }}>
                <label className="input-label">Food & Meals Menu Add-ons</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {Object.keys(mealPrices).map(meal => {
                    const qty = selectedMeals[meal] || 0;
                    const price = mealPrices[meal] || 0;
                    return (
                      <div
                        key={meal}
                        style={{
                          padding: '14px 16px',
                          background: 'var(--light-bg)',
                          borderRadius: '16px',
                          border: '1px solid var(--border)',
                          display: 'flex',
                          justifyContent: 'space-between',
                          alignItems: 'center'
                        }}
                      >
                        <div>
                          <div style={{ fontSize: '14px', fontWeight: 800 }}>{meal} Menu Set</div>
                          <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>₱{price.toLocaleString()} per set meal</div>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                          <button type="button" onClick={() => updateMealQty(meal, -1)} className="counter-btn-small" style={{ opacity: qty === 0 ? 0.3 : 1 }}>-</button>
                          <span style={{ minWidth: '32px', textAlign: 'center', fontWeight: 800, fontSize: '14px' }}>{qty}</span>
                          <button type="button" onClick={() => updateMealQty(meal, 1)} className="counter-btn-small">+</button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Payment Option: 30% Downpayment vs 100% Full Payment */}
            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Payment Option</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <button
                  type="button"
                  onClick={() => setPaymentOption('downpayment')}
                  style={{
                    padding: '16px', borderRadius: '16px', border: '2px solid',
                    borderColor: paymentOption === 'downpayment' ? 'var(--secondary)' : 'var(--border)',
                    background: paymentOption === 'downpayment' ? 'rgba(29, 211, 176, 0.05)' : 'var(--surface)',
                    cursor: 'pointer', textAlign: 'left'
                  }}
                >
                  <div style={{ fontSize: '14px', fontWeight: 800, color: paymentOption === 'downpayment' ? 'var(--secondary)' : 'var(--text-main)' }}>30% Downpayment</div>
                  <div style={{ fontSize: '13px', color: 'var(--text-muted)', marginTop: '4px' }}>₱{formatPrice(pricing.downpaymentAmount)}</div>
                </button>
                <button
                  type="button"
                  onClick={() => setPaymentOption('full')}
                  style={{
                    padding: '16px', borderRadius: '16px', border: '2px solid',
                    borderColor: paymentOption === 'full' ? 'var(--secondary)' : 'var(--border)',
                    background: paymentOption === 'full' ? 'rgba(29, 211, 176, 0.05)' : 'var(--surface)',
                    cursor: 'pointer', textAlign: 'left'
                  }}
                >
                  <div style={{ fontSize: '14px', fontWeight: 800, color: paymentOption === 'full' ? 'var(--secondary)' : 'var(--text-main)' }}>100% Full Payment</div>
                  <div style={{ fontSize: '13px', color: 'var(--text-muted)', marginTop: '4px' }}>₱{formatPrice(pricing.grandTotal)}</div>
                </button>
              </div>
            </div>

            {/* Price Breakdown */}
            <div style={{ background: 'var(--light-bg)', padding: '20px', borderRadius: '20px', marginBottom: '24px', border: '1px solid var(--border)' }}>
              <h4 style={{ margin: '0 0 14px 0', fontSize: '15px', fontWeight: 800 }}>Price Breakdown</h4>

              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>Activities Subtotal</span>
                <span style={{ fontWeight: 600, fontSize: '13px' }}>₱{formatPrice(pricing.activitiesSubtotal)}</span>
              </div>

              {pricing.boatrideSurcharge > 0 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', color: '#B45309' }}>
                  <span style={{ fontSize: '13px', fontWeight: 700 }}>Single Passenger Boatride Fee</span>
                  <span style={{ fontWeight: 800, fontSize: '13px' }}>+₱{formatPrice(pricing.boatrideSurcharge)}</span>
                </div>
              )}

              {pricing.mealsTotal > 0 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                  <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>Meals Menu ({pricing.mealsList.map(m => `${m.name} x${m.quantity}`).join(', ')})</span>
                  <span style={{ fontWeight: 600, fontSize: '13px' }}>₱{formatPrice(pricing.mealsTotal)}</span>
                </div>
              )}

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: '12px', borderTop: '1px dashed var(--border-dashed)', marginBottom: '12px' }}>
                <span style={{ fontWeight: 800, fontSize: '15px' }}>Grand Total</span>
                <span style={{ fontWeight: 900, fontSize: '17px' }}>₱{formatPrice(pricing.grandTotal)}</span>
              </div>

              <div style={{ background: 'var(--surface)', padding: '12px 16px', borderRadius: '14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontWeight: 700, color: 'var(--text-muted)', fontSize: '13px' }}>Amount Due Now ({paymentOption === 'full' ? '100%' : '30%'})</span>
                <span style={{ color: 'var(--secondary)', fontSize: '20px', fontWeight: 900 }}>₱{formatPrice(pricing.amountToPay)}</span>
              </div>

              {paymentOption === 'downpayment' && (
                <p style={{ margin: '8px 0 0 0', fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic', textAlign: 'center' }}>
                  Remaining balance of ₱{formatPrice(pricing.remainingAtResort)} to be settled at the resort
                </p>
              )}
            </div>

            {(!selectedDate || pricing.grandTotal <= 0) && (
              <div style={{
                background: 'rgba(59, 130, 246, 0.08)',
                border: '1px solid rgba(59, 130, 246, 0.25)',
                borderRadius: '12px',
                padding: '10px 14px',
                marginBottom: '14px',
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                fontSize: '12px',
                color: '#1D4ED8',
                fontWeight: 600
              }}>
                <Info size={16} />
                <span>
                  {!selectedDate
                    ? 'Please select a date on the calendar above to continue.'
                    : 'Please select at least one activity to continue.'}
                </span>
              </div>
            )}

            <button
              type="button"
              className="btn btn-primary"
              style={{
                width: '100%',
                height: '52px',
                fontWeight: 800,
                fontSize: '15px',
                borderRadius: '16px',
                opacity: (!selectedDate || pricing.grandTotal <= 0) ? 0.7 : 1,
                cursor: 'pointer'
              }}
              onClick={() => {
                if (!selectedDate) {
                  return alert("Please select a date for your activities on the calendar.");
                }
                if (pricing.grandTotal <= 0 || pricing.selectedItemsList.length === 0) {
                  return alert("Please select at least one activity.");
                }

                // Check that each selected non-karaoke activity has an arrival time chosen
                for (const item of pricing.selectedItemsList) {
                  const act = catalog.find(c => c.id === item.id);
                  if (act && !isKaraokeTitle(act.title)) {
                    if (!arrivalTimes[act.id]) {
                      return alert(`Please select an arrival time / schedule for ${act.title}.`);
                    }
                  }
                }

                setStep(2);
              }}
            >
              Continue to Payment (₱{formatPrice(pricing.amountToPay)})
            </button>
          </div>
        )}

        {/* STEP 2: GCash Payment Proof & Terms */}
        {step === 2 && (
          <div className="step-content">
            <div style={{ background: 'linear-gradient(135deg, rgba(59, 130, 246, 0.1), #DBEAFE)', padding: '20px', borderRadius: '20px', marginBottom: '20px', border: '1px solid #BFDBFE' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                <CreditCard size={20} color="#1D4ED8" />
                <h4 style={{ margin: 0, fontSize: '15px', fontWeight: 800, color: '#1E40AF' }}>GCash Payment Details</h4>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', background: 'white', padding: '14px', borderRadius: '14px', marginBottom: '12px' }}>
                <div>
                  <div style={{ fontSize: '11px', fontWeight: 700, color: '#64748B' }}>GCASH NUMBER</div>
                  <div style={{ fontSize: '15px', fontWeight: 900, color: '#0F172A' }}>{property?.gcashNumber || '09123456789'}</div>
                </div>
                <div>
                  <div style={{ fontSize: '11px', fontWeight: 700, color: '#64748B' }}>ACCOUNT NAME</div>
                  <div style={{ fontSize: '15px', fontWeight: 900, color: '#0F172A' }}>{property?.gcashName || propertyName || 'Resort Admin'}</div>
                </div>
              </div>

              {property?.gcashQrUrl && (
                <div style={{ textAlign: 'center', marginTop: '12px' }}>
                  <img
                    src={property.gcashQrUrl}
                    alt="GCash QR"
                    style={{ width: '160px', height: '160px', objectFit: 'contain', background: 'white', padding: '8px', borderRadius: '12px', border: '1px solid #CBD5E1' }}
                  />
                  <div style={{ fontSize: '11px', color: '#64748B', marginTop: '4px', fontWeight: 600 }}>Scan QR to Pay via GCash</div>
                </div>
              )}
            </div>

            {/* Warning Note */}
            <div style={{
              background: 'rgba(245, 158, 11, 0.1)',
              border: '1px solid rgba(245, 158, 11, 0.3)',
              borderRadius: '14px',
              padding: '12px 14px',
              fontSize: '12px',
              color: '#B45309',
              lineHeight: '1.4',
              marginBottom: '20px',
              fontWeight: 600
            }}>
              ⚠️ Please send exact amount (₱{formatPrice(pricing.amountToPay)}). Upload the GCash receipt screenshot below for automatic verification.
            </div>

            {/* File Upload Box */}
            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Upload GCash Receipt Screenshot</label>
              <div style={{
                border: '2px dashed var(--border-dashed)',
                borderRadius: '20px',
                padding: '24px',
                textAlign: 'center',
                background: receiptUrl ? 'rgba(16, 185, 129, 0.05)' : 'var(--light-bg)',
                borderColor: receiptUrl ? '#10B981' : 'var(--border-dashed)'
              }}>
                {receiptUrl ? (
                  <div>
                    <img src={receiptUrl} alt="Receipt" style={{ maxHeight: '180px', borderRadius: '12px', marginBottom: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }} />
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px', color: ocrStatus === 'Verified' ? '#10B981' : '#F59E0B', fontWeight: 800, fontSize: '14px' }}>
                      {ocrStatus === 'Verified' ? <CheckCircle2 size={18} /> : <AlertTriangle size={18} />}
                      {ocrStatus === 'Verified' ? `Verified! Ref: ${extractedRefNo}` : 'Receipt Flagged (Will be reviewed manually)'}
                    </div>
                    <label style={{ display: 'inline-block', marginTop: '10px', fontSize: '12px', color: 'var(--primary)', cursor: 'pointer', fontWeight: 700, textDecoration: 'underline' }}>
                      Re-upload receipt
                      <input type="file" accept="image/*" onChange={handleFileUpload} hidden disabled={uploading} />
                    </label>
                  </div>
                ) : (
                  <div>
                    <label style={{ cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                      <div style={{ width: '48px', height: '48px', borderRadius: '50%', background: 'white', display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 2px 8px rgba(0,0,0,0.08)' }}>
                        <ArrowRight size={20} color="var(--primary)" style={{ transform: 'rotate(-90deg)' }} />
                      </div>
                      <span style={{ fontSize: '14px', fontWeight: 800, color: 'var(--text-main)' }}>
                        {uploading ? 'Scanning receipt...' : 'Click to Upload Receipt Screenshot'}
                      </span>
                      <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>JPEG, PNG files supported</span>
                      <input type="file" accept="image/*" onChange={handleFileUpload} hidden disabled={uploading} />
                    </label>
                  </div>
                )}
              </div>
            </div>

            {/* Terms and Policies */}
            <div style={{ marginBottom: '24px', display: 'flex', alignItems: 'flex-start', gap: '10px' }}>
              <input
                type="checkbox"
                id="act-terms"
                checked={agreedToTerms}
                onChange={e => setAgreedToTerms(e.target.checked)}
                style={{ width: '18px', height: '18px', marginTop: '2px', cursor: 'pointer' }}
              />
              <label htmlFor="act-terms" style={{ fontSize: '13px', color: 'var(--text-muted)', lineHeight: '1.5', cursor: 'pointer' }}>
                I agree to the{' '}
                <span onClick={(e) => { e.preventDefault(); setShowPolicies('terms'); }} style={{ color: 'var(--primary)', fontWeight: 700, textDecoration: 'underline' }}>
                  Terms & Conditions
                </span>{' '}
                and{' '}
                <span onClick={(e) => { e.preventDefault(); setShowPolicies('privacy'); }} style={{ color: 'var(--primary)', fontWeight: 700, textDecoration: 'underline' }}>
                  Resort Policies
                </span>
                . I acknowledge that fees are subject to host confirmation.
              </label>
            </div>

            {/* Actions */}
            <div style={{ display: 'flex', gap: '12px' }}>
              <button
                type="button"
                className="btn"
                style={{ flex: 1, background: 'var(--light-bg)', border: '1px solid var(--border)', fontWeight: 700 }}
                onClick={() => setStep(1)}
              >
                Back
              </button>
              <button
                type="button"
                className="btn btn-primary"
                style={{ flex: 2, height: '52px', fontWeight: 800, borderRadius: '14px' }}
                disabled={uploading || !receiptUrl || !agreedToTerms}
                onClick={submitBooking}
              >
                {uploading ? 'Submitting...' : 'Complete Reservation'}
              </button>
            </div>
          </div>
        )}

        {/* STEP 3: Success Confirmation */}
        {step === 3 && (
          <div style={{ textAlign: 'center', padding: '24px 0' }}>
            <div style={{ width: '72px', height: '72px', background: 'rgba(16, 185, 129, 0.1)', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 20px' }}>
              <CheckCircle2 size={40} color="#10B981" />
            </div>
            <h2 style={{ fontSize: '22px', fontWeight: 800, margin: '0 0 8px 0' }}>
              Activity Reservation Submitted!
            </h2>
            <p style={{ fontSize: '14px', color: 'var(--text-muted)', lineHeight: '1.6', marginBottom: '24px' }}>
              Your reservation has been received. A notification was sent to {propertyName}. Confirmation details were also dispatched to your registered email.
            </p>
            <div style={{ background: 'var(--light-bg)', padding: '16px', borderRadius: '16px', marginBottom: '24px', textAlign: 'left', fontSize: '13px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Date:</span>
                <span style={{ fontWeight: 700 }}>{selectedDate ? format(selectedDate, 'MMM dd, yyyy') : 'Scheduled'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '6px' }}>
                <span style={{ color: 'var(--text-muted)' }}>Total Amount:</span>
                <span style={{ fontWeight: 700 }}>₱{formatPrice(pricing.grandTotal)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Payment:</span>
                <span style={{ fontWeight: 700, color: '#10B981' }}>{paymentOption === 'full' ? 'Full Payment' : '30% Downpayment'} (₱{formatPrice(pricing.amountToPay)})</span>
              </div>
            </div>
            <button
              className="btn btn-primary"
              style={{ width: '100%', padding: '14px', borderRadius: '14px', fontWeight: 800 }}
              onClick={onClose}
            >
              Done
            </button>
          </div>
        )}
      </div>

      <style>{`
        .input-label { display: block; font-size: 13px; font-weight: 800; color: var(--text-main); margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
        .close-btn { background: var(--light-bg); border: 1px solid var(--border); border: none; width: 36px; height: 36px; borderRadius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); }
        .close-btn:hover { background: var(--surface); transform: rotate(90deg); }

        /* Modern Calendar Styles */
        .modern-calendar { background: var(--light-bg); padding: 20px; border-radius: 24px; border: 1px solid var(--border); }
        .nav-btn { background: var(--surface); border: 1px solid var(--border); color: var(--text-main); width: 32px; height: 32px; borderRadius: 10px; display: flex; align-items: center; justify-content: center; cursor: pointer; boxShadow: 0 2px 8px rgba(0,0,0,0.05); }
        .calendar-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 8px; }
        .day-label { text-align: center; font-size: 11px; font-weight: 800; color: var(--text-muted); padding-bottom: 10px; }
        .calendar-day { aspect-ratio: 1; border: none; background: var(--surface); color: var(--text-main); borderRadius: 12px; font-size: 14px; font-weight: 700; cursor: pointer; transition: var(--transition); display: flex; align-items: center; justify-content: center; boxShadow: 0 2px 4px rgba(0,0,0,0.02); }
        .calendar-day:hover:not(:disabled) { transform: scale(1.1); boxShadow: 0 4px 12px rgba(0,0,0,0.1); z-index: 1; }
        .calendar-day.selected { background: var(--primary) !important; color: white !important; boxShadow: 0 8px 15px rgba(251, 54, 64, 0.3); transform: scale(1.1); z-index: 1; }
        .calendar-day.booked { background: rgba(239, 68, 68, 0.1); color: #EF4444; text-decoration: line-through; cursor: not-allowed; opacity: 0.5; border: 1px dashed #FEE2E2; }
        .calendar-day.past { color: #E5E7EB; cursor: not-allowed; background: transparent; boxShadow: none; }
        .calendar-day.today { color: var(--secondary); border: 2px solid var(--secondary); }
        .calendar-day.other-month { opacity: 0.3; }
        .dot { width: 8px; height: 8px; borderRadius: 50%; display: inline-block; margin-right: 6px; }
        .dot.booked { background: #EF4444; }
        .dot.available { background: var(--surface); border: 1px solid var(--border); }
      `}</style>
    </div>
    </>
  );
};

export default ActivityBookingModal;
