import React, { useState, useEffect } from 'react';
import { db, auth } from '../firebase';
import { ref, push, set, get, update, query, orderByChild, equalTo, serverTimestamp, onValue } from 'firebase/database';
import { X, Calendar as CalendarIcon, CreditCard, Upload, CheckCircle2, AlertCircle, ChevronLeft, ChevronRight, Info, Wallet, AlertTriangle, Tag, Sparkles } from 'lucide-react';
import {
  format, parse, addDays, isBefore, isAfter,
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  eachDayOfInterval, isSameDay, isToday, addMonths, subMonths,
  startOfDay
} from 'date-fns';
import gcashQr from '../assets/gcashqr1.jpg';
import TermsAndPolicies from './TermsAndPolicies';
import { sendBookingConfirmationEmail, sendAdminAlertEmail, sendOwnerBookingNotificationEmail } from '../services/emailService';
import { parseDateSafely } from './OwnerDashboard';

const BookingModal = ({ room, property, user, onClose, isPreview = false, onViewPolicies }) => {
  const [selectedDate, setSelectedDate] = useState(() => {
    const saved = sessionStorage.getItem('bm_selectedDate');
    return saved ? new Date(saved) : null;
  });
  const [nights, setNights] = useState(() => parseInt(sessionStorage.getItem('bm_nights')) || 1);
  const [selectedAddons, setSelectedAddons] = useState(() => {
    const saved = sessionStorage.getItem('bm_selectedAddons');
    if (saved) {
      try { return JSON.parse(saved); } catch(e) {}
    }
    return {};
  });
  const [paymentOption, setPaymentOption] = useState(() => sessionStorage.getItem('bm_paymentOption') || 'full'); // 'downpayment' or 'full'
  const [receiptUrl, setReceiptUrl] = useState(null);
  const [extractedRefNo, setExtractedRefNo] = useState(null);
  const [ocrStatus, setOcrStatus] = useState(null); // 'Verified' | 'Flagged'
  const [ocrIssues, setOcrIssues] = useState('');
  const [showOcrAlert, setShowOcrAlert] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [step, setStep] = useState(() => parseInt(sessionStorage.getItem('bm_step')) || 1); // 1: Booking, 2: Payment, 3: Success
  const [bookedDates, setBookedDates] = useState([]);

  // Promo and Event States
  const [allPromos, setAllPromos] = useState([]);
  const [promoCodeInput, setPromoCodeInput] = useState('');
  const [appliedPromo, setAppliedPromo] = useState(null);
  const [promoError, setPromoError] = useState('');
  const [activeEventPromo, setActiveEventPromo] = useState(null);
  const [showCouponGuide, setShowCouponGuide] = useState(false);

  useEffect(() => {
    const promosRef = ref(db, 'cms/homepage/promotions');
    const unsub = onValue(promosRef, (snap) => {
      if (snap.exists()) {
        const data = snap.val();
        const list = Object.entries(data).map(([id, p]) => ({ id, ...p }));
        setAllPromos(list);
      }
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    if (selectedDate) sessionStorage.setItem('bm_selectedDate', selectedDate.toISOString());
    else sessionStorage.removeItem('bm_selectedDate');
  }, [selectedDate]);

  useEffect(() => {
    sessionStorage.setItem('bm_nights', nights.toString());
  }, [nights]);

  useEffect(() => {
    sessionStorage.setItem('bm_selectedAddons', JSON.stringify(selectedAddons));
  }, [selectedAddons]);

  useEffect(() => {
    sessionStorage.setItem('bm_paymentOption', paymentOption);
  }, [paymentOption]);

  useEffect(() => {
    sessionStorage.setItem('bm_step', step.toString());
  }, [step]);
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [extraBeds, setExtraBeds] = useState(0);
  const [showQR, setShowQR] = useState(false);
  const [agreedToTerms, setAgreedToTerms] = useState(false);
  const [showPolicies, setShowPolicies] = useState(null);

  const baseDetails = {
    'Boat ride to falls': { unit: 'trip', desc: 'Guided trip (max 5 pax)' },
    'Boat ride': { unit: 'trip', desc: 'Island hopping tour' },
    'Kayak': { unit: 'hour', desc: 'Single kayak' },
    'Meals': { unit: 'pax', desc: 'Daily meals' },
    'Dinner': { unit: 'set', desc: 'Local cuisine buffet' },
    'Lunch': { unit: 'set', desc: 'Premium plated lunch' },
    'Extra Bed': { unit: 'night', desc: 'Foldable mattress' }
  };

  const addonDetails = {};
  if (property?.addonPrices) {
    Object.entries(property.addonPrices).forEach(([name, price]) => {
      addonDetails[name] = {
        price: price,
        unit: baseDetails[name]?.unit || 'item',
        desc: baseDetails[name]?.desc || 'Optional Add-on'
      };
    });
  }

  const addonOptions = Object.keys(addonDetails).filter(k => k !== 'Extra Bed');

  useEffect(() => {
    if (!room?.id) return;

    const bookingsRef = ref(db, 'bookings');
    const q = query(bookingsRef, orderByChild('activityId'), equalTo(room.id));

    const unsubscribe = onValue(q, (snapshot) => {
      const dates = [];
      if (snapshot.exists()) {
        const data = snapshot.val();
        const bookingsArray = Array.isArray(data)
          ? data.map((b, i) => [i.toString(), b]).filter(([id, b]) => b !== null)
          : Object.entries(data);

        bookingsArray.forEach(([id, b]) => {
          const status = (b.status || '').toLowerCase();
          if (status === 'confirmed' || status === 'checked in') {
            try {
              const start = parseDateSafely(b.bookingDate || b.checkInDate || b.date);
              if (start) {
                const duration = parseInt(b.nights) || 1;
                for (let i = 0; i < duration; i++) {
                  dates.push(startOfDay(addDays(start, i)));
                }
              }
            } catch (e) {
              console.error("Date parsing error", e);
            }
          }
        });
      }
      setBookedDates(dates);
    });

    return () => unsubscribe();
  }, [room?.id]);

  const [addonWarning, setAddonWarning] = useState('');

  const updateAddonQty = (name, delta) => {
    const current = selectedAddons[name] || 0;
    const roomCapacity = parseInt(room?.maxPax) || parseInt(room?.capacity) || 2;
    const isFood = name.toLowerCase().includes('breakfast') || 
                   name.toLowerCase().includes('lunch') || 
                   name.toLowerCase().includes('dinner') || 
                   name.toLowerCase().includes('meal');
    const limit = name === 'Extra Bed' ? 3 : (isFood ? roomCapacity * nights : roomCapacity);

    let next = current + delta;
    if (next > limit) {
      setAddonWarning(`Max limit for ${name} is ${limit}.`);
      setTimeout(() => setAddonWarning(''), 3000);
      next = limit;
    } else if (next < 0) {
      next = 0;
    }

    setSelectedAddons(prev => ({ ...prev, [name]: next }));
    setReceiptUrl(null); setOcrStatus(null); setExtractedRefNo(null);
  };

  const handleAddonChange = (name, value) => {
    let next = parseInt(value, 10);
    if (isNaN(next) || next < 0) next = 0;
    
    const roomCapacity = parseInt(room?.maxPax) || parseInt(room?.capacity) || 2;
    const isFood = name.toLowerCase().includes('breakfast') || 
                   name.toLowerCase().includes('lunch') || 
                   name.toLowerCase().includes('dinner') || 
                   name.toLowerCase().includes('meal');
    const limit = name === 'Extra Bed' ? 3 : (isFood ? roomCapacity * nights : roomCapacity);

    if (next > limit) {
      setAddonWarning(`Max limit for ${name} is ${limit}.`);
      setTimeout(() => setAddonWarning(''), 3000);
      next = limit;
    }

    setSelectedAddons(prev => ({ ...prev, [name]: next }));
    setReceiptUrl(null); setOcrStatus(null); setExtractedRefNo(null);
  };

  const isDateBooked = (date) => {
    return bookedDates.some(bookedDate => isSameDay(bookedDate, date));
  };

  const isSelectionConflicting = (startDate, duration) => {
    for (let i = 0; i < duration; i++) {
      if (isDateBooked(addDays(startDate, i))) return true;
    }
    return false;
  };

  // Evaluate Auto-Activating Date-Driven Promo Events
  useEffect(() => {
    if (!allPromos || allPromos.length === 0) return;
    const now = new Date();
    const todayStr = format(now, 'yyyy-MM-dd');
    const roomCat = (room?.category || '').toLowerCase();
    const roomTitle = (room?.title || '').toLowerCase();

    const roomPax = parseInt(room?.maxPax || room?.capacity || 2);

    // Find any auto-activating promo event matching today and room type
    const activeEvent = allPromos.find(p => {
      if (!p.active) return false;
      if (!p.isEvent) return false;
      if (p.startDate && todayStr < p.startDate) return false;
      if (p.endDate && todayStr > p.endDate) return false;
      
      const appRooms = Array.isArray(p.applicableRooms) ? p.applicableRooms : ['ALL'];
      if (appRooms.includes('ALL')) return true;
      return appRooms.some(r => {
        const lower = r.toLowerCase();
        if (lower.includes('2-pax') && roomPax === 2) return true;
        if (lower.includes('4-pax') && roomPax === 4) return true;
        return roomCat.includes(lower) || roomTitle.includes(lower);
      });
    });

    setActiveEventPromo(activeEvent || null);
  }, [allPromos, room]);

  const handleApplyPromoCode = async () => {
    setPromoError('');
    if (!promoCodeInput.trim()) {
      setPromoError('Please enter a promo code');
      return;
    }

    const code = promoCodeInput.trim().toUpperCase();
    let matched = allPromos.find(p => (p.code || '').trim().toUpperCase() === code);

    // Also check user personal coupons if not in public promos
    if (!matched && (user?.uid || auth.currentUser?.uid)) {
      const currentUid = user?.uid || auth.currentUser?.uid;
      try {
        const uCouponSnap = await get(ref(db, `user_coupons/${currentUid}/${code}`));
        if (uCouponSnap.exists()) {
          const uCoupon = uCouponSnap.val();
          if (uCoupon.used) {
            setPromoError('This coupon has already been used');
            return;
          }
          matched = { id: code, ...uCoupon };
        }
      } catch (e) {
        console.warn('Coupon fetch error:', e);
      }
    }

    if (!matched) {
      setPromoError('Invalid promo code');
      return;
    }

    if (matched.active === false) {
      setPromoError('This promo is currently inactive');
      return;
    }

    const todayStr = format(new Date(), 'yyyy-MM-dd');
    if (matched.startDate && todayStr < matched.startDate) {
      setPromoError(`This promo is valid starting ${matched.startDate}`);
      return;
    }
    if (matched.endDate && todayStr > matched.endDate) {
      setPromoError(`This promo expired on ${matched.endDate}`);
      return;
    }

    // Granular Room Type Check
    const roomCat = (room?.category || '').toLowerCase();
    const roomTitle = (room?.title || '').toLowerCase();
    const appRooms = Array.isArray(matched.applicableRooms) ? matched.applicableRooms : ['ALL'];

    const isEligible = appRooms.includes('ALL') || appRooms.some(r => {
      const lower = r.toLowerCase();
      return roomCat.includes(lower) || roomTitle.includes(lower);
    });

    if (!isEligible) {
      setPromoError(`This promo is only applicable to: ${appRooms.join(', ')}`);
      return;
    }

    setAppliedPromo(matched);
  };

  const handleRemovePromo = () => {
    setAppliedPromo(null);
    setPromoCodeInput('');
    setPromoError('');
  };

  const calculatePricing = () => {
    try {
      const priceRaw = room?.price ? room.price.toString().replace(/,/g, '') : '0';
      const basePrice = (parseFloat(priceRaw) || 0) * (nights || 1);

      let addonsTotal = 0;
      const addonsList = [];
      Object.entries(selectedAddons).forEach(([name, qty]) => {
        if (qty > 0) {
          const total = (addonDetails[name]?.price || 0) * qty;
          addonsTotal += total;
          addonsList.push({ name, quantity: qty, total });
        }
      });

      const subtotal = basePrice + addonsTotal;

      // Calculate Discount from either applied manual promo or active automated event
      let discount = 0;
      let discountLabel = '';
      const effectivePromo = appliedPromo || activeEventPromo;

      if (effectivePromo) {
        const val = parseFloat(effectivePromo.discountValue) || 0;
        if (effectivePromo.discountType === 'percentage') {
          discount = (basePrice * (val / 100));
          discountLabel = `${val}% OFF (${effectivePromo.title || effectivePromo.code || 'Promo'})`;
        } else {
          discount = Math.min(val, basePrice);
          discountLabel = `₱${val.toLocaleString()} OFF (${effectivePromo.title || effectivePromo.code || 'Promo'})`;
        }
      }

      const discountedSubtotal = Math.max(0, subtotal - discount);
      const taxes = 0; // Removed taxes
      const grandTotal = discountedSubtotal + taxes;

      return {
        basePrice,
        addonsTotal,
        addonsList,
        discount,
        discountLabel,
        subtotal,
        taxes,
        grandTotal
      };
    } catch (e) {
      console.error("Pricing calculation error", e);
      return { basePrice: 0, addonsTotal: 0, addonsList: [], discount: 0, discountLabel: '', subtotal: 0, taxes: 0, grandTotal: 0 };
    }
  };

  const pricing = calculatePricing();
  const totalAmount = pricing.grandTotal;
  const downpaymentAmount = totalAmount * 0.3;
  const amountToPay = paymentOption === 'full' ? totalAmount : downpaymentAmount;

  const submitBooking = async () => {
    if (!selectedDate) return;

    setUploading(true);

    if (extractedRefNo) {
      try {
        const usedRefSnapshot = await get(ref(db, `used_receipts/${property?.uid}`));
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
        await set(ref(db, `used_receipts/${property?.uid}`), usedReceipts);
      } catch (e) {
        console.error("Error checking used receipts", e);
      }
    }

    const bookingRef = push(ref(db, 'bookings'));
    const tName = user?.firstName || user?.name || user?.fullName || 'Guest';
    const tLast = user?.lastName ? ` ${user.lastName}` : '';
    const touristName = `${tName}${tLast}`.trim();

    const finalAddons = [];
    Object.entries(selectedAddons).forEach(([name, qty]) => {
      if (qty > 0) finalAddons.push(`${name} (x${qty})`);
    });

    const bookingData = {
      touristUid: user?.uid || auth.currentUser?.uid || 'unknown',
      touristName: touristName || 'Guest',
      touristProfilePic: user?.profilePicUrl || '',
      ownerUid: property?.uid || '',
      activityId: room?.id || '',
      propertyName: property?.name || '',
      activityTitle: room?.title || '',
      price: room?.price || 0,
      totalPrice: totalAmount || 0,
      pricing: {
        basePrice: pricing.basePrice || 0,
        subtotal: pricing.subtotal || 0,
        addonsTotal: pricing.addonsTotal || 0,
        addonsList: pricing.addonsList || [],
        taxesAndFees: pricing.taxes || 0,
        grandTotal: pricing.grandTotal || 0
      },
      nights: nights || 1,
      bookingDate: selectedDate ? format(selectedDate, 'MMM dd, yyyy') : '',
      selectedAddons: finalAddons || [],
      paymentMethod: 'GCash',
      paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment',
      amountPaid: amountToPay || 0,
      status: 'Pending',
      paymentStatus: ocrStatus === 'Verified' ? 'paid' : 'pending',
      gcashReceipt: receiptUrl || '',
      extractedRefNo: extractedRefNo || '',
      ocrStatus: ocrStatus || 'Unverified',
      ocrIssues: ocrIssues || '',
      promoCode: (appliedPromo?.code || activeEventPromo?.code || null),
      promoDiscount: pricing.discount || 0,
      promoName: (appliedPromo?.title || activeEventPromo?.title || null),
      agreedToTerms: true,
      termsAcceptedAt: serverTimestamp(),
      timestamp: serverTimestamp(),
    };

    // Prevent undefined values from crashing Firebase
    Object.keys(bookingData).forEach(key => {
      if (bookingData[key] === undefined) {
        bookingData[key] = null;
      }
    });

    try {
      await set(bookingRef, bookingData);

      // If user applied a personal coupon (e.g. WELCOME10), mark it as used
      if (appliedPromo?.code && (user?.uid || auth.currentUser?.uid)) {
        const currentUid = user?.uid || auth.currentUser?.uid;
        try {
          await update(ref(db, `user_coupons/${currentUid}/${appliedPromo.code}`), {
            used: true,
            usedAt: Date.now(),
            bookingId: bookingRef.key
          });
        } catch (couponUseErr) {
          console.warn('Could not update coupon status:', couponUseErr);
        }
      }
      
      const notifRef = push(ref(db, `notifications/${property.uid}`));
      await set(notifRef, {
        title: 'New Booking Request',
        message: `${touristName} has requested to book ${room.title}.`,
        type: 'new_booking',
        isRead: false,
        timestamp: serverTimestamp(),
        bookingId: bookingRef.key
      });

      // Unified EmailJS Trigger
      const touristEmail = user?.email || auth.currentUser?.email;
      if (touristEmail) {
        sendBookingConfirmationEmail({
          toEmail: touristEmail,
          toName: touristName,
          bookingId: bookingRef.key,
          propertyName: property?.name || 'Resort',
          roomName: room?.title || 'Room',
          checkInDate: format(selectedDate, 'MMM dd, yyyy'),
          nights: nights || 1,
          amountPaid: amountToPay || 0,
          grandTotal: totalAmount || 0,
          paymentMethod: 'GCash',
          paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment'
        }).catch(err => console.warn('[EmailJS] Booking confirmation error:', err));
      }

      // Send Notification Email to Resort Owner
      try {
        const ownerUid = property?.uid || room?.ownerUid;
        let ownerEmail = property?.contact?.email || property?.email;
        let ownerName = property?.name || 'Resort Owner';

        if (!ownerEmail && ownerUid) {
          const ownerUserSnap = await get(ref(db, `users/${ownerUid}`));
          if (ownerUserSnap.exists()) {
            const oData = ownerUserSnap.val();
            ownerEmail = oData.email;
            ownerName = oData.firstName ? `${oData.firstName} ${oData.lastName || ''}`.trim() : (property?.name || 'Resort Owner');
          }
        }

        if (ownerEmail) {
          sendOwnerBookingNotificationEmail({
            toEmail: ownerEmail,
            ownerName: ownerName,
            guestName: touristName,
            bookingType: 'room',
            itemName: room?.title || 'Accommodation',
            propertyName: property?.name || 'Your Resort',
            checkInDate: format(selectedDate, 'MMM dd, yyyy'),
            nights: nights || 1,
            totalPrice: totalAmount || 0,
            amountPaid: amountToPay || 0,
            paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment',
            paymentMethod: 'GCash',
            referenceNo: extractedRefNo || 'Manual Review',
            bookingId: bookingRef.key
          }).catch(err => console.warn('[EmailJS] Owner notification error:', err));
        }
      } catch (ownerEmailErr) {
        console.warn('[EmailJS] Failed to retrieve owner email for notification:', ownerEmailErr);
      }

      // Admin Email Alert
      sendAdminAlertEmail({
        title: 'New Booking Received',
        message: `${touristName} submitted a booking for ${room?.title} at ${property?.name}.`,
        details: {
          bookingId: bookingRef.key,
          tourist: touristName,
          total: totalAmount,
          room: room?.title
        }
      }).catch(err => console.warn('[EmailJS] Admin alert error:', err));

      sessionStorage.removeItem('bm_selectedDate');
      sessionStorage.removeItem('bm_nights');
      sessionStorage.removeItem('bm_selectedAddons');
      sessionStorage.removeItem('bm_paymentOption');
      sessionStorage.removeItem('bm_step');
      setStep(3); // Go to Success Step
    } catch (error) {
      alert('Booking failed: ' + error.message);
    } finally {
      setUploading(false);
    }
  };

  const renderCalendar = () => {
    const monthStart = startOfMonth(currentMonth);
    const monthEnd = endOfMonth(monthStart);
    const startDate = startOfWeek(monthStart);
    const endDate = endOfWeek(monthEnd);

    const calendarDays = eachDayOfInterval({
      start: startDate,
      end: endDate,
    });

    const daysOfWeek = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return (
      <div className="modern-calendar">
        <div className="calendar-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>{format(currentMonth, 'MMMM yyyy')}</h3>
          <div style={{ display: 'flex', gap: '8px' }}>
            <button type="button" onClick={() => setCurrentMonth(subMonths(currentMonth, 1))} className="nav-btn"><ChevronLeft size={18} /></button>
            <button type="button" onClick={() => setCurrentMonth(addMonths(currentMonth, 1))} className="nav-btn"><ChevronRight size={18} /></button>
          </div>
        </div>
        <div className="calendar-grid">
          {daysOfWeek.map((day, i) => (
            <div key={i} className="day-label">{day}</div>
          ))}
          {calendarDays.map((day, idx) => {
            const isSelected = selectedDate && isSameDay(day, selectedDate);
            const isBooked = isDateBooked(day);
            const isPast = isBefore(startOfDay(day), startOfDay(new Date()));
            const isCurrentMonth = isSameDay(startOfMonth(day), monthStart);

            let className = "calendar-day";
            if (!isCurrentMonth) className += " other-month";
            if (isBooked) className += " booked";
            if (isSelected) className += " selected";
            if (isPast) className += " past";
            if (isToday(day)) className += " today";

            return (
              <button
                key={idx}
                type="button"
                className={className}
                disabled={isBooked || isPast}
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

  const handleFileUpload = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      alert('File is too large (max 5MB). Please choose a smaller image.');
      return;
    }

    setUploading(true);
    // Don't clear existing receiptUrl so we can append!
    setOcrIssues('');

    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', 'resort_unsigned');

    try {
      // 1. Strict OCR Validation
      const ocrFormData = new FormData();
      ocrFormData.append('image', file);
      ocrFormData.append('expectedAmount', amountToPay.toString());
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
          // Check for duplicate reference immediately
          const usedRefSnapshot = await get(ref(db, `used_receipts/${property?.uid}`));
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
          console.log("OCR Validated. Ref:", ocrData.reference_number, "Amount:", ocrData.amount);
        } else {
          ocrErrorMsg = ocrData.error || "Could not auto-verify GCash receipt.";
          setOcrIssues(ocrErrorMsg);
          setShowOcrAlert(true);
        }
      } catch (ocrError) {
        console.error('OCR Backend failed:', ocrError);
        ocrErrorMsg = "OCR Server unreachable.";
        setOcrIssues(ocrErrorMsg);
        setShowOcrAlert(true);
      }

      // 2. Upload to Cloudinary (allow upload even if OCR flagged)
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
      e.target.value = null; // reset file input
    }
  };

  if (step === 3) {
    return (
      <div className="modal-overlay">
        <div className="card modal-content" style={{ textAlign: 'center', padding: '48px 32px', maxWidth: '400px' }}>
          {ocrStatus === 'Flagged' ? (
            <>
              <div style={{
                width: '80px', height: '80px', background: 'rgba(220, 38, 38, 0.1)',
                borderRadius: '50%', display: 'flex', justifyContent: 'center',
                alignItems: 'center', margin: '0 auto 24px'
              }}>
                <X size={40} color="#DC2626" />
              </div>
              <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0', color: '#DC2626' }}>Booking Declined</h2>
              <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6' }}>
                Your reservation was automatically declined due to invalid payment proof. <br/><br/>
                <strong>Reason:</strong> {ocrIssues}
              </p>
            </>
          ) : (
            <>
              <div style={{
                width: '80px', height: '80px', background: 'rgba(16, 185, 129, 0.1)',
                borderRadius: '50%', display: 'flex', justifyContent: 'center',
                alignItems: 'center', margin: '0 auto 24px'
              }}>
                <CheckCircle2 size={40} color="#10B981" />
              </div>
              <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0' }}>{ocrStatus === 'Verified' ? 'Booking Confirmed!' : 'Request Sent!'}</h2>
              <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6' }}>
                {ocrStatus === 'Verified' 
                  ? `Your reservation for ${room.title} has been automatically confirmed! Your payment was verified successfully.`
                  : `Your reservation for ${room.title} has been submitted. The host will review your proof of payment shortly.`}
              </p>
            </>
          )}
          <button className="btn btn-primary" onClick={() => {
            sessionStorage.removeItem('bm_selectedDate');
            sessionStorage.removeItem('bm_nights');
            sessionStorage.removeItem('bm_selectedAddons');
            sessionStorage.removeItem('bm_paymentOption');
            sessionStorage.removeItem('bm_step');
            onClose();
          }} style={{ marginTop: '32px', width: '100%' }}>Done</button>
        </div>
      </div>
    );
  }

  const selectionConflict = selectedDate && isSelectionConflicting(selectedDate, nights);

  return (
    <div className="modal-overlay" style={{ zIndex: 3000 }}>
      {showOcrAlert && (
        <div className="modal-overlay" style={{ zIndex: 4000 }}>
          <div className="card modal-content" style={{ maxWidth: '400px', padding: '32px', textAlign: 'center', borderRadius: '32px' }}>
            <div style={{
              width: '64px', height: '64px', background: 'rgba(217, 119, 6, 0.1)',
              borderRadius: '50%', display: 'flex', justifyContent: 'center',
              alignItems: 'center', margin: '0 auto 24px'
            }}>
              <AlertTriangle size={32} color="#D97706" />
            </div>
            <h3 style={{ margin: '0 0 12px 0', fontSize: '20px', fontWeight: 800 }}>Validation Flagged</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: '14px', lineHeight: '1.6', marginBottom: '24px' }}>
              <strong>Notice:</strong> {ocrIssues}<br/><br/>
              Because of this issue, your booking will be automatically declined. Please clear the upload and try again with a correct receipt.
            </p>
            <button className="btn btn-primary" onClick={() => setShowOcrAlert(false)} style={{ width: '100%', padding: '14px', borderRadius: '16px', fontWeight: 800 }}>OK, I Understand</button>
          </div>
        </div>
      )}
      {showPolicies && <TermsAndPolicies onClose={() => setShowPolicies(null)} initialScroll={showPolicies} />}
      {showCouponGuide && (
        <div className="modal-overlay" style={{ zIndex: 11000, background: 'rgba(0,0,0,0.65)', display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'fixed', inset: 0, padding: '20px' }}>
          <div className="card" style={{ maxWidth: '420px', width: '100%', background: 'var(--surface)', borderRadius: '24px', padding: '28px', position: 'relative', boxShadow: '0 20px 50px rgba(0,0,0,0.3)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Tag size={20} color="var(--primary)" />
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>How to Earn Coupons</h3>
              </div>
              <button onClick={() => setShowCouponGuide(false)} style={{ background: 'var(--light-bg)', border: 'none', borderRadius: '50%', width: '32px', height: '32px', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}><X size={16} /></button>
            </div>
            <div style={{ background: 'var(--light-bg)', borderRadius: '16px', padding: '16px', fontSize: '14px', lineHeight: '1.6', color: 'var(--text-main)', marginBottom: '20px', whiteSpace: 'pre-line' }}>
              {property?.couponEarningGuide || "Earn discount coupons by booking multi-night stays, participating in resort activities, and during seasonal holiday events! Watch out for special promotions on our homepage."}
            </div>
            <button className="btn btn-primary" onClick={() => setShowCouponGuide(false)} style={{ width: '100%', padding: '12px', borderRadius: '14px', fontWeight: 800 }}>Got It!</button>
          </div>
        </div>
      )}
      <div className="card modal-content" style={{ maxWidth: '500px', padding: '32px', borderRadius: '32px', maxHeight: '90vh', overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>{step === 0 ? 'Room Details' : step === 1 ? 'Reserve Room' : 'Payment Proof'}</h2>
            <p style={{ margin: '4px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>{room.title}</p>
          </div>
          <button onClick={() => {
            sessionStorage.removeItem('bm_selectedDate');
            sessionStorage.removeItem('bm_nights');
            sessionStorage.removeItem('bm_selectedAddons');
            sessionStorage.removeItem('bm_paymentOption');
            sessionStorage.removeItem('bm_step');
            onClose();
          }} className="close-btn"><X size={20} /></button>
        </div>

        {step === 0 ? (
          <div className="step-content">
            <div style={{ marginBottom: '24px', borderRadius: '24px', overflow: 'hidden', height: '240px', position: 'relative' }}>
              <img
                src={(Array.isArray(room.imageUrls) ? room.imageUrls[0] : Object.values(room.imageUrls || {})[0]) || 'https://via.placeholder.com/600x300?text=No+Photo'}
                alt={room.title}
                style={{ width: '100%', height: '100%', objectFit: 'cover' }}
              />
              <div style={{ position: 'absolute', bottom: '16px', left: '16px', background: 'rgba(255,255,255,0.9)', padding: '6px 12px', borderRadius: '12px', fontWeight: 800, color: 'var(--primary)', fontSize: '14px', backdropFilter: 'blur(4px)' }}>
                ₱{room.price?.toLocaleString()} / night
              </div>
            </div>

            <div style={{ marginBottom: '24px' }}>
              <h3 style={{ margin: '0 0 12px 0', fontSize: '18px', fontWeight: 800 }}>About this room</h3>
              <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: '14px', lineHeight: '1.6' }}>
                {room.description || 'Experience a relaxing stay with premium amenities. Perfect for unwinding and creating wonderful memories.'}
              </p>
              {onViewPolicies && (
                <button
                  type="button"
                  onClick={() => onViewPolicies(property)}
                  style={{ background: 'none', border: 'none', color: 'var(--primary)', fontWeight: 700, fontSize: '13px', cursor: 'pointer', padding: 0, marginTop: '8px', textDecoration: 'underline' }}
                >
                  View Resort Policies
                </button>
              )}
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginBottom: '32px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', background: 'var(--light-bg)', padding: '12px', borderRadius: '12px', border: '1px solid var(--border)' }}>
                <div style={{ background: 'var(--surface)', padding: '8px', borderRadius: '8px', border: '1px solid var(--border)' }}>
                  <Info size={16} color="var(--primary)" />
                </div>
                <div>
                  <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)' }}>CAPACITY</div>
                  <div style={{ fontSize: '14px', fontWeight: 800 }}>{room.maxPax || room.capacity || 2} Persons</div>
                </div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', background: 'var(--light-bg)', padding: '12px', borderRadius: '12px', border: '1px solid var(--border)' }}>
                <div style={{ background: 'var(--surface)', padding: '8px', borderRadius: '8px', border: '1px solid var(--border)' }}>
                  <Wallet size={16} color="#10B981" />
                </div>
                <div>
                  <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)' }}>PAYMENT</div>
                  <div style={{ fontSize: '14px', fontWeight: 800 }}>GCash Available</div>
                </div>
              </div>
            </div>

            <button
              type="button"
              className="btn btn-primary"
              style={{ width: '100%', height: '56px', cursor: 'pointer' }}
              onClick={() => {
                setStep(1);
              }}
            >
              Continue to Booking
            </button>
          </div>
        ) : step === 1 ? (
          <div className="step-content">
            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Choose Check-in Date</label>
              {renderCalendar()}
              <div className="calendar-legend" style={{ display: 'flex', gap: '16px', marginTop: '12px', justifyContent: 'center' }}>
                <div className="legend-item"><span className="dot booked"></span> <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)' }}>Reserved</span></div>
                <div className="legend-item"><span className="dot available"></span> <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)' }}>Open</span></div>
              </div>
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Duration of Stay</label>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '24px', background: 'var(--light-bg)', padding: '16px', borderRadius: '20px' }}>
                <button type="button" onClick={() => { setNights(Math.max(1, nights - 1)); setReceiptUrl(null); setOcrStatus(null); setExtractedRefNo(null); }} style={{ width: '48px', height: '48px', borderRadius: '50%', border: '1px solid var(--border)', background: 'var(--surface)', fontSize: '24px', fontWeight: 'bold', color: 'var(--text-main)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'var(--transition)' }}>-</button>
                <div style={{ display: 'flex', alignItems: 'baseline', minWidth: '80px', justifyContent: 'center' }}>
                  <span style={{ fontSize: '32px', fontWeight: 900, color: 'var(--primary)' }}>{nights}</span>
                  <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-muted)', marginLeft: '6px' }}>NIGHTS</span>
                </div>
                <button type="button" onClick={() => {
                  if (selectedDate && isSelectionConflicting(selectedDate, nights + 1)) {
                    alert('Cannot extend stay: Date range overlaps with another booking.');
                  } else {
                    setNights(nights + 1);
                    setReceiptUrl(null); setOcrStatus(null); setExtractedRefNo(null);
                  }
                }} style={{ width: '48px', height: '48px', borderRadius: '50%', border: '1px solid var(--border)', background: 'var(--surface)', fontSize: '24px', fontWeight: 'bold', color: 'var(--text-main)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', transition: 'var(--transition)' }}>+</button>
              </div>
              {selectionConflict && (
                <div style={{ color: 'var(--primary)', fontSize: '13px', marginTop: '12px', display: 'flex', alignItems: 'center', gap: '8px', background: 'rgba(251, 54, 64, 0.15)', padding: '10px', borderRadius: '10px', fontWeight: 600 }}>
                  <AlertCircle size={16} /> Overlaps with an existing booking.
                </div>
              )}
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Extras & Add-ons</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                {Object.entries(addonDetails).map(([name, info]) => {
                  const qty = selectedAddons[name] || 0;
                  const roomCapacity = parseInt(room?.maxPax) || parseInt(room?.capacity) || 2;
                  const isFood = name.toLowerCase().includes('breakfast') || 
                                 name.toLowerCase().includes('lunch') || 
                                 name.toLowerCase().includes('dinner') || 
                                 name.toLowerCase().includes('meal');
                  const limit = name === 'Extra Bed' ? 3 : (isFood ? roomCapacity * nights : roomCapacity);
                  return (
                    <div key={name} style={{ padding: '16px', background: 'var(--light-bg)', borderRadius: '20px', border: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <div>
                        <div style={{ fontSize: '14px', fontWeight: 800 }}>{name}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontWeight: 600 }}>{info.desc} (₱{info.price}/{info.unit})</div>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <button type="button" onClick={() => updateAddonQty(name, -1)} className="counter-btn-small" style={{ opacity: qty === 0 ? 0.3 : 1 }}>-</button>
                        <input 
                          type="number"
                          value={qty}
                          onChange={(e) => handleAddonChange(name, e.target.value)}
                          style={{ width: '40px', textAlign: 'center', fontWeight: 800, fontSize: '14px', border: '1px solid var(--border)', borderRadius: '8px', padding: '4px' }}
                          min="0"
                          max={limit}
                        />
                        <button type="button" onClick={() => updateAddonQty(name, 1)} className="counter-btn-small" style={{ opacity: qty === limit ? 0.3 : 1 }}>+</button>
                      </div>
                    </div>
                  );
                })}
              </div>
              {addonWarning && (
                <div style={{ color: 'var(--primary)', fontSize: '13px', marginTop: '12px', display: 'flex', alignItems: 'center', gap: '8px', background: 'rgba(251, 54, 64, 0.15)', padding: '10px', borderRadius: '10px', fontWeight: 600 }}>
                  <AlertCircle size={16} /> {addonWarning}
                </div>
              )}
            </div>

            <div style={{ marginBottom: '32px' }}>
              <label className="input-label">Payment Option</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <button
                  type="button"
                  onClick={() => {
                    setPaymentOption('downpayment');
                    setReceiptUrl(null);
                    setOcrStatus(null);
                    setExtractedRefNo(null);
                    setOcrIssues(null);
                  }}
                  style={{
                    padding: '16px', borderRadius: '16px', border: '2px solid',
                    borderColor: paymentOption === 'downpayment' ? 'var(--secondary)' : 'var(--border)',
                    background: paymentOption === 'downpayment' ? 'rgba(29, 211, 176, 0.05)' : 'var(--surface)',
                    cursor: 'pointer', textAlign: 'left', transition: 'all 0.2s'
                  }}
                >
                  <div style={{ fontSize: '14px', fontWeight: 800, color: paymentOption === 'downpayment' ? 'var(--secondary)' : 'var(--text-main)' }}>30% Downpayment</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>₱{(downpaymentAmount || 0).toLocaleString()}</div>
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setPaymentOption('full');
                    setReceiptUrl(null);
                    setOcrStatus(null);
                    setExtractedRefNo(null);
                    setOcrIssues(null);
                  }}
                  style={{
                    padding: '16px', borderRadius: '16px', border: '2px solid',
                    borderColor: paymentOption === 'full' ? 'var(--secondary)' : 'var(--border)',
                    background: paymentOption === 'full' ? 'rgba(29, 211, 176, 0.05)' : 'var(--surface)',
                    cursor: 'pointer', textAlign: 'left', transition: 'all 0.2s'
                  }}
                >
                  <div style={{ fontSize: '14px', fontWeight: 800, color: paymentOption === 'full' ? 'var(--secondary)' : 'var(--text-main)' }}>100% Full Payment</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>₱{(totalAmount || 0).toLocaleString()}</div>
                </button>
              </div>
            </div>

            {/* Promo Code & Auto Event Banner */}
            <div style={{ marginBottom: '24px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                <label className="input-label" style={{ display: 'flex', alignItems: 'center', gap: '6px', margin: 0 }}>
                  <Tag size={16} color="var(--primary)" /> Have a Promo Code?
                </label>
                <button
                  type="button"
                  onClick={() => setShowCouponGuide(true)}
                  style={{
                    background: 'none',
                    border: 'none',
                    color: 'var(--secondary)',
                    fontWeight: 700,
                    fontSize: '12px',
                    cursor: 'pointer',
                    textDecoration: 'underline',
                    padding: 0
                  }}
                >
                  How to earn coupons?
                </button>
              </div>

              {activeEventPromo && !appliedPromo && (
                <div style={{
                  padding: '12px 16px',
                  borderRadius: '14px',
                  background: 'rgba(29, 211, 176, 0.1)',
                  border: '1px solid var(--secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '10px',
                  marginBottom: '12px'
                }}>
                  <Sparkles size={18} color="var(--secondary)" />
                  <div style={{ fontSize: '13px', color: 'var(--text-main)' }}>
                    <strong>Auto-applied Event Promo:</strong> {activeEventPromo.title} ({activeEventPromo.discountValue}{activeEventPromo.discountType === 'percentage' ? '%' : '₱'} OFF)
                  </div>
                </div>
              )}

              {appliedPromo ? (
                <div style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  padding: '12px 16px',
                  background: 'var(--light-bg)',
                  borderRadius: '14px',
                  border: '1px solid #10B981'
                }}>
                  <div>
                    <div style={{ fontWeight: 800, color: '#10B981', fontSize: '14px' }}>✓ Promo Applied: {appliedPromo.code}</div>
                    <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>{appliedPromo.title} ({appliedPromo.discountValue}{appliedPromo.discountType === 'percentage' ? '%' : '₱'} discount)</div>
                  </div>
                  <button
                    type="button"
                    onClick={handleRemovePromo}
                    style={{ background: 'none', border: 'none', color: '#EF4444', fontWeight: 700, cursor: 'pointer', fontSize: '13px' }}
                  >
                    Remove
                  </button>
                </div>
              ) : (
                <div style={{ display: 'flex', gap: '8px' }}>
                  <input
                    className="input"
                    placeholder="Enter coupon (e.g. SUMMER20)"
                    value={promoCodeInput}
                    onChange={(e) => { setPromoCodeInput(e.target.value.toUpperCase()); setPromoError(''); }}
                    style={{ flex: 1, textTransform: 'uppercase' }}
                  />
                  <button
                    type="button"
                    onClick={handleApplyPromoCode}
                    className="btn btn-primary"
                    style={{ padding: '0 20px', borderRadius: '12px', height: 'auto', fontWeight: 700 }}
                  >
                    Apply
                  </button>
                </div>
              )}

              {promoError && (
                <div style={{ color: '#EF4444', fontSize: '12px', marginTop: '6px', fontWeight: 600 }}>
                  ✕ {promoError}
                </div>
              )}
            </div>

            <div style={{ background: 'var(--light-bg)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid var(--border)' }}>
              <h4 style={{ margin: '0 0 16px 0', fontSize: '16px', fontWeight: 800 }}>Price Breakdown</h4>
              
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                <span style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Room Base ({nights} {nights === 1 ? 'night' : 'nights'})</span>
                <span style={{ color: 'var(--text-main)', fontSize: '14px', fontWeight: 600 }}>₱{(pricing.basePrice || 0).toLocaleString()}</span>
              </div>
              
              {pricing.addonsTotal > 0 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                  <span style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Add-ons</span>
                  <span style={{ color: 'var(--text-main)', fontSize: '14px', fontWeight: 600 }}>₱{(pricing.addonsTotal || 0).toLocaleString()}</span>
                </div>
              )}

              {pricing.discount > 0 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', color: '#10B981' }}>
                  <span style={{ fontSize: '14px', fontWeight: 700 }}>Promo Discount {pricing.discountLabel ? `(${pricing.discountLabel})` : ''}</span>
                  <span style={{ fontSize: '14px', fontWeight: 800 }}>-₱{(pricing.discount || 0).toLocaleString()}</span>
                </div>
              )}

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: '16px', borderTop: '1px dashed var(--border-dashed)', marginBottom: '16px' }}>
                <span style={{ fontWeight: 800, color: 'var(--text-main)', fontSize: '16px' }}>Booking Total</span>
                <span style={{ color: 'var(--text-main)', fontSize: '18px', fontWeight: 800 }}>₱{(pricing.grandTotal || 0).toLocaleString()}</span>
              </div>

              <div style={{ background: 'var(--surface)', padding: '16px', borderRadius: '16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontWeight: 700, color: 'var(--text-muted)', fontSize: '14px' }}>Amount Due Today ({paymentOption === 'full' ? '100%' : '30%'})</span>
                <span style={{ color: 'var(--secondary)', fontSize: '24px', fontWeight: 800 }}>₱{(amountToPay || 0).toLocaleString()}</span>
              </div>
              
              {paymentOption === 'downpayment' && (
                <p style={{ margin: '8px 0 0 0', fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic', textAlign: 'center' }}>
                  Remaining ₱{((pricing.grandTotal || 0) * 0.7).toLocaleString()} to be paid at check-in
                </p>
              )}
            </div>

            <button
              type="button"
              className="btn btn-primary"
              style={{ width: '100%', height: '56px', cursor: (!selectedDate || selectionConflict) ? 'not-allowed' : 'pointer' }}
              onClick={() => {
                if (isPreview) {
                  alert('Preview Mode: You are viewing this room exactly as a tourist sees it. Bookings are disabled in this mode.');
                  return;
                }
                if (!selectedDate) {
                  alert('Action Required: Please select a check-in date first.');
                  return;
                }
                if (selectionConflict) {
                  alert('Action Required: The selected date is unavailable. Please choose another date.');
                  return;
                }
                console.log("Advancing step to 2");
                setStep(2);
              }}
            >
              {isPreview ? 'Preview Mode (Disabled)' : 'Continue to Payment'}
            </button>
            <div style={{ marginTop: '12px' }}>
              <button type="button" className="btn" style={{ width: '100%', background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }} onClick={() => {
                setStep(0);
                setReceiptUrl(null);
                setOcrStatus(null);
                setExtractedRefNo(null);
                setOcrIssues(null);
              }}>Back to Details</button>
            </div>
          </div>
        ) : (
          <div className="step-content">
            <div style={{ background: 'linear-gradient(135deg, rgba(59, 130, 246, 0.1), #DBEAFE)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid #BFDBFE' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '16px' }}>
                <CreditCard size={20} color="#1D4ED8" />
                <span style={{ fontWeight: 800, color: '#1D4ED8', fontSize: '14px', textTransform: 'uppercase' }}>GCash Payment</span>
              </div>
              <div style={{ marginBottom: '12px' }}>
                <p style={{ margin: 0, fontSize: '12px', color: '#1D4ED8', fontWeight: 700 }}>Account Name</p>
                <p style={{ margin: 0, fontSize: '18px', fontWeight: 800, color: '#111827' }}>{property.gcashName || 'Resort Host'}</p>
              </div>
              <div style={{ marginBottom: '12px' }}>
                <p style={{ margin: 0, fontSize: '12px', color: '#1D4ED8', fontWeight: 700 }}>GCash Number</p>
                <p style={{ margin: 0, fontSize: '18px', fontWeight: 800, color: '#111827', letterSpacing: '1px' }}>{property.gcashNumber || '09XX XXX XXXX'}</p>
              </div>
              <div style={{ paddingTop: '12px', borderTop: '1px dashed #BFDBFE', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: '13px', fontWeight: 700, color: '#1D4ED8' }}>Amount Due:</span>
                <span style={{ fontSize: '18px', fontWeight: 900, color: '#1D4ED8' }}>₱{(amountToPay || 0).toLocaleString()}</span>
              </div>
              <div style={{ marginTop: '16px', display: 'flex', justifyContent: 'center' }}>
                <button type="button" onClick={() => setShowQR(!showQR)} style={{ padding: '10px 20px', borderRadius: '12px', border: '1px solid #BFDBFE', background: '#DBEAFE', color: '#1D4ED8', fontSize: '13px', fontWeight: 700, cursor: 'pointer' }}>
                  {showQR ? 'Hide GCash QR Code' : 'View GCash QR Code'}
                </button>
              </div>
              {showQR && (
                <div style={{ marginTop: '16px', textAlign: 'center' }}>
                  <img src={property.gcashQrUrl || gcashQr} alt="GCash QR" style={{ maxWidth: '100%', borderRadius: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }} />
                </div>
              )}
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label className="input-label" style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>Upload Payment Screenshot</span>
                {receiptUrl && (
                  <span style={{ color: ocrStatus === 'Verified' ? 'var(--success)' : '#F59E0B', fontSize: '11px', fontWeight: 800 }}>
                    {ocrStatus === 'Verified' ? '✓ Verified' : '⚠ Flagged for Manual Review'}
                  </span>
                )}
              </label>
              <div style={{ position: 'relative' }}>
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleFileUpload}
                  style={{ display: 'none' }}
                  id="receipt-upload"
                />
                <label
                  htmlFor="receipt-upload"
                  style={{
                    display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
                    padding: '24px', border: receiptUrl ? (ocrStatus === 'Verified' ? '2px solid var(--success)' : '2px solid #F59E0B') : '2px dashed var(--border)',
                    borderRadius: '16px', background: 'var(--surface)', cursor: uploading ? 'not-allowed' : 'pointer',
                    transition: 'var(--transition)'
                  }}
                >
                  {uploading ? (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'var(--primary)' }}>
                      <span className="spinner" style={{ width: '20px', height: '20px', border: '3px solid', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 1s linear infinite' }} />
                      <span style={{ fontWeight: 700, fontSize: '14px' }}>Scanning & Verifying...</span>
                    </div>
                  ) : receiptUrl ? (
                    <div style={{ textAlign: 'center', color: ocrStatus === 'Verified' ? 'var(--success)' : '#F59E0B' }}>
                      {ocrStatus === 'Verified' ? (
                        <CheckCircle2 size={32} style={{ marginBottom: '8px' }} />
                      ) : (
                        <AlertCircle size={32} style={{ marginBottom: '8px' }} />
                      )}
                      <p style={{ margin: 0, fontWeight: 700, fontSize: '14px' }}>Receipt Uploaded</p>
                      {extractedRefNo && <p style={{ margin: '4px 0 0 0', fontSize: '12px', opacity: 0.8 }}>Ref: {extractedRefNo}</p>}
                      {ocrStatus === 'Flagged' && <p style={{ margin: '4px 0 0 0', fontSize: '11px', color: '#B45309' }}>Booking will be automatically declined</p>}
                    </div>
                  ) : (
                    <div style={{ textAlign: 'center', color: 'var(--text-muted)' }}>
                      <Upload size={32} style={{ marginBottom: '12px', color: 'var(--primary)' }} />
                      <p style={{ margin: 0, fontWeight: 700, fontSize: '14px', color: 'var(--text-main)' }}>Click to upload GCash receipt</p>
                      <p style={{ margin: '8px 0 0 0', fontSize: '12px', color: '#D97706', fontWeight: 600, background: '#FEF3C7', padding: '6px 12px', borderRadius: '8px' }}>
                        ⚠️ Only send the exact amount so that the AI checker works perfectly and the booking process goes smoothly.
                      </p>
                    </div>
                  )}
                </label>
                {receiptUrl && !uploading && (
                  <div style={{ textAlign: 'center', marginTop: '12px' }}>
                    <button 
                      type="button" 
                      onClick={() => {
                        setReceiptUrl(null);
                        setExtractedRefNo(null);
                        setOcrStatus(null);
                        setOcrIssues('');
                      }}
                      style={{ background: 'none', border: 'none', color: '#EF4444', textDecoration: 'underline', fontSize: '12px', cursor: 'pointer', fontWeight: 700 }}
                    >
                      Clear & Re-upload
                    </button>
                  </div>
                )}
              </div>
            </div>

            <div style={{ marginBottom: '24px', display: 'flex', gap: '10px', alignItems: 'flex-start', background: 'var(--light-bg)', padding: '16px', borderRadius: '16px', border: '1px solid var(--border)' }}>
              <input 
                type="checkbox" 
                id="termsCheckbox" 
                checked={agreedToTerms} 
                onChange={(e) => setAgreedToTerms(e.target.checked)} 
                style={{ width: '20px', height: '20px', accentColor: 'var(--primary)', cursor: 'pointer', marginTop: '2px' }} 
              />
              <label htmlFor="termsCheckbox" style={{ fontSize: '13px', color: 'var(--text-muted)', lineHeight: '1.5', cursor: 'pointer' }}>
                I agree to the <span onClick={(e) => { e.preventDefault(); setShowPolicies('terms'); }} style={{ color: 'var(--primary)', fontWeight: 700, textDecoration: 'underline' }}>Terms & Conditions</span> and <span onClick={(e) => { e.preventDefault(); setShowPolicies('privacy'); }} style={{ color: 'var(--primary)', fontWeight: 700, textDecoration: 'underline' }}>Data Privacy Policy</span>. I understand that my booking is subject to the resort's policies.
              </label>
            </div>

            <div style={{ display: 'flex', gap: '12px' }}>
              <button type="button" className="btn" style={{ flex: 1, background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }} onClick={() => {
                setStep(1);
                setReceiptUrl(null);
                setOcrStatus(null);
                setExtractedRefNo(null);
                setOcrIssues(null);
              }}>Back</button>
              <button
                type="button"
                className="btn btn-primary"
                style={{ flex: 2, borderRadius: '16px', padding: '14px', fontSize: '15px', opacity: (receiptUrl && agreedToTerms) ? 1 : 0.5 }}
                disabled={uploading || !receiptUrl || !agreedToTerms}
                onClick={() => {
                  if (isPreview) return;
                  submitBooking();
                }}
              >
                {uploading ? 'Processing...' : 'Submit Booking'}
              </button>
            </div>

            <div style={{ marginTop: '24px', display: 'flex', gap: '10px', alignItems: 'flex-start', background: 'var(--light-bg)', padding: '16px', borderRadius: '16px', border: '1px solid var(--border)' }}>
              <Info size={16} color="var(--text-muted)" style={{ marginTop: '2px' }} />
              <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: 0, lineHeight: '1.5' }}>
                Your host will verify the payment within 24 hours. You can track your status in <strong>My Bookings</strong>.
              </p>
            </div>
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

        /* Counter Controls */
        .counter-control { display: flex; align-items: center; gap: 24px; background: var(--light-bg); padding: 12px 20px; borderRadius: 20px; width: fit-content; }
        .counter-btn { width: 40px; height: 40px; border-radius: 14px; border: 1px solid var(--border); background: var(--surface); color: var(--text-main); fontSize: 20px; font-weight: 700; cursor: pointer; display: flex; align-items: center; justify-content: center; boxShadow: 0 4px 10px rgba(0,0,0,0.05); transition: var(--transition); }
        .counter-btn:hover { background: var(--secondary); color: white; transform: translateY(-2px); }
        .counter-btn-small { width: 32px; height: 32px; border-radius: 10px; border: 1px solid var(--border); background: var(--surface); color: var(--text-main); fontSize: 18px; font-weight: 700; cursor: pointer; display: flex; align-items: center; justify-content: center; boxShadow: 0 2px 6px rgba(0,0,0,0.05); transition: var(--transition); }
        .counter-btn-small:hover { background: var(--secondary); color: white; }
        .counter-value { display: flex; align-items: baseline; }

        /* Addon Chips */
        .addon-chip { padding: 8px 16px; border-radius: 12px; border: 2px solid var(--border); background: var(--surface); font-size: 13px; font-weight: 700; color: var(--text-muted); cursor: pointer; transition: var(--transition); }
        .addon-chip.active { border-color: var(--secondary); background: rgba(29, 211, 176, 0.05); color: var(--secondary); }
        .addon-chip:hover:not(.active) { border-color: var(--border); background: var(--light-bg); }

        /* Upload UI */
        .upload-placeholder { border: 2px dashed var(--border-dashed); border-radius: 24px; padding: 40px 20px; text-align: center; cursor: pointer; background: var(--light-bg); transition: var(--transition); }
        .upload-placeholder:hover { border-color: var(--secondary); background: var(--surface); }
        .remove-img-btn { position: absolute; top: 12px; right: 12px; background: rgba(0,0,0,0.5); color: white; border: none; width: 28px; height: 28px; borderRadius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; backdrop-filter: blur(4px); }
      `}</style>
    </div>
  );
};

export default BookingModal;
