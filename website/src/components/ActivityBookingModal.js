import React, { useState, useEffect } from 'react';
import { X, Calendar as CalendarIcon, Clock, Users, ArrowRight, Info, CheckCircle2, AlertCircle, AlertTriangle, CreditCard, ChevronLeft, ChevronRight, Sparkles } from 'lucide-react';
import {
  format, addDays, isBefore,
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  eachDayOfInterval, isSameDay, isToday, addMonths, subMonths,
  startOfDay
} from 'date-fns';
import { db, auth } from '../firebase';
import { ref, push, set, get, serverTimestamp } from 'firebase/database';
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
  onClose,
  ownerUid,
  propertyName,
  touristInfo,
  activitySchedule
}) => {
  const [step, setStep] = useState(1); // 1: Select Activities, Meals & Date, 2: Payment Proof, 3: Success
  const [selectedDate, setSelectedDate] = useState(null);
  const [currentMonth, setCurrentMonth] = useState(new Date());

  // Selected activities state: { [actId]: { count: number, pax: number } }
  const [selectedActs, setSelectedActs] = useState({});

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

  // Initialize catalog with fallback
  const catalog = (allActivities && allActivities.length > 0)
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

  // Initial selection when opened with a clicked activity
  useEffect(() => {
    if (!isOpen) return;
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
            pax: match.isBoatride ? 2 : 1 // default to 2 pax for boatride so no solo surcharge by default, but customizable
          }
        });
      }
    } else if (catalog.length > 0) {
      setSelectedActs({
        [catalog[0].id]: { selected: true, pax: 1 }
      });
    }
  }, [isOpen, activity?.id]);

  if (!isOpen) return null;

  const scheduleText = activitySchedule || DEFAULT_SCHEDULE;

  // Meal pricing from property or default menu (Lunch ₱400, Dinner ₱400)
  const mealPrices = {
    Lunch: (property?.addonPrices && property.addonPrices['Lunch']) || 400,
    Dinner: (property?.addonPrices && property.addonPrices['Dinner']) || 400
  };

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

      activitiesSubtotal += itemTotal;
      selectedItemsList.push({
        id: act.id,
        title: act.title,
        price: act.price,
        pax,
        surcharge,
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

    const grandTotal = activitiesSubtotal + boatrideSurcharge + mealsTotal;
    const downpaymentAmount = Math.round(grandTotal * 0.3);
    const amountToPay = paymentOption === 'full' ? grandTotal : downpaymentAmount;
    const remainingAtResort = Math.max(0, grandTotal - downpaymentAmount);

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
      ocrFormData.append('expectedAmount', pricing.amountToPay.toString());
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
        activityList: pricing.selectedItemsList,
        bookingDate: formattedDate,
        checkInDate: formattedDate,
        nights: 1,
        timeSlot: 'Regular Operating Hours',
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
      <div className="modern-calendar">
        <div className="calendar-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
          <h4 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>{format(currentMonth, 'MMMM yyyy')}</h4>
          <div style={{ display: 'flex', gap: '6px' }}>
            <button type="button" onClick={() => setCurrentMonth(subMonths(currentMonth, 1))} className="nav-btn"><ChevronLeft size={16} /></button>
            <button type="button" onClick={() => setCurrentMonth(addMonths(currentMonth, 1))} className="nav-btn"><ChevronRight size={16} /></button>
          </div>
        </div>
        <div className="calendar-grid">
          {daysOfWeek.map((day, i) => (
            <div key={i} className="day-label">{day}</div>
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

      <div className="card modal-content" style={{ maxWidth: '560px', width: '100%', padding: '32px', borderRadius: '32px', maxHeight: '90vh', overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>
              {step === 1 ? 'Book Activities' : step === 2 ? 'Payment Proof' : 'Booking Confirmed'}
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
              {selectedDate && (
                <div style={{ marginTop: '8px', fontSize: '13px', fontWeight: 700, color: 'var(--secondary)' }}>
                  Selected: {format(selectedDate, 'MMMM dd, yyyy')}
                </div>
              )}
            </div>

            {/* Multi-Activity Choices */}
            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Select Activities (Choose Multiple)</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                {catalog.map(act => {
                  const isSelected = !!selectedActs[act.id]?.selected;
                  const currentPax = selectedActs[act.id]?.pax || 1;
                  const isBoatrideSolo = act.isBoatride && isSelected && currentPax === 1;

                  return (
                    <div
                      key={act.id}
                      onClick={() => toggleActivity(act)}
                      style={{
                        padding: '16px',
                        borderRadius: '16px',
                        border: '2px solid',
                        borderColor: isSelected ? 'var(--secondary)' : 'var(--border)',
                        background: isSelected ? 'rgba(29, 211, 176, 0.05)' : 'var(--surface)',
                        cursor: 'pointer',
                        transition: 'all 0.2s'
                      }}
                    >
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                        <div style={{ display: 'flex', alignItems: 'flex-start', gap: '12px' }}>
                          <input
                            type="checkbox"
                            checked={isSelected}
                            onChange={() => {}} // handled by parent div onClick
                            style={{ width: '18px', height: '18px', marginTop: '3px', cursor: 'pointer' }}
                          />
                          <div>
                            <div style={{ fontSize: '15px', fontWeight: 800, color: 'var(--text-main)' }}>
                              {act.title}
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
                          <div style={{ fontSize: '16px', fontWeight: 900, color: 'var(--secondary)' }}>
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
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Food / Meal Menu Add-ons */}
            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Food & Meals Menu Add-ons</label>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                {['Lunch', 'Dinner'].map(meal => {
                  const qty = selectedMeals[meal] || 0;
                  const price = mealPrices[meal] || 400;
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
                  <div style={{ fontSize: '13px', color: 'var(--text-muted)', marginTop: '4px' }}>₱{pricing.downpaymentAmount.toLocaleString()}</div>
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
                  <div style={{ fontSize: '13px', color: 'var(--text-muted)', marginTop: '4px' }}>₱{pricing.grandTotal.toLocaleString()}</div>
                </button>
              </div>
            </div>

            {/* Price Breakdown */}
            <div style={{ background: 'var(--light-bg)', padding: '20px', borderRadius: '20px', marginBottom: '24px', border: '1px solid var(--border)' }}>
              <h4 style={{ margin: '0 0 14px 0', fontSize: '15px', fontWeight: 800 }}>Price Breakdown</h4>

              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>Activities Subtotal</span>
                <span style={{ fontWeight: 600, fontSize: '13px' }}>₱{pricing.activitiesSubtotal.toLocaleString()}</span>
              </div>

              {pricing.boatrideSurcharge > 0 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', color: '#B45309' }}>
                  <span style={{ fontSize: '13px', fontWeight: 700 }}>Single Passenger Boatride Fee</span>
                  <span style={{ fontWeight: 800, fontSize: '13px' }}>+₱{pricing.boatrideSurcharge.toLocaleString()}</span>
                </div>
              )}

              {pricing.mealsTotal > 0 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                  <span style={{ color: 'var(--text-muted)', fontSize: '13px' }}>Meals Menu ({pricing.mealsList.map(m => `${m.name} x${m.quantity}`).join(', ')})</span>
                  <span style={{ fontWeight: 600, fontSize: '13px' }}>₱{pricing.mealsTotal.toLocaleString()}</span>
                </div>
              )}

              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: '12px', borderTop: '1px dashed var(--border-dashed)', marginBottom: '12px' }}>
                <span style={{ fontWeight: 800, fontSize: '15px' }}>Grand Total</span>
                <span style={{ fontWeight: 900, fontSize: '17px' }}>₱{pricing.grandTotal.toLocaleString()}</span>
              </div>

              <div style={{ background: 'var(--surface)', padding: '12px 16px', borderRadius: '14px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontWeight: 700, color: 'var(--text-muted)', fontSize: '13px' }}>Amount Due Now ({paymentOption === 'full' ? '100%' : '30%'})</span>
                <span style={{ color: 'var(--secondary)', fontSize: '20px', fontWeight: 900 }}>₱{pricing.amountToPay.toLocaleString()}</span>
              </div>

              {paymentOption === 'downpayment' && (
                <p style={{ margin: '8px 0 0 0', fontSize: '12px', color: 'var(--text-muted)', fontStyle: 'italic', textAlign: 'center' }}>
                  Remaining balance of ₱{pricing.remainingAtResort.toLocaleString()} to be settled at the resort
                </p>
              )}
            </div>

            <button
              type="button"
              className="btn btn-primary"
              style={{ width: '100%', height: '52px', fontWeight: 800, fontSize: '15px', borderRadius: '16px', cursor: (!selectedDate || pricing.grandTotal <= 0) ? 'not-allowed' : 'pointer' }}
              onClick={() => {
                if (!selectedDate) {
                  return alert("Please select a date for your activities.");
                }
                if (pricing.grandTotal <= 0 || pricing.selectedItemsList.length === 0) {
                  return alert("Please select at least one activity.");
                }
                setStep(2);
              }}
            >
              Continue to Payment (₱{pricing.amountToPay.toLocaleString()})
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
              ⚠️ Please send exact amount (₱{pricing.amountToPay.toLocaleString()}). Upload the GCash receipt screenshot below for automatic verification.
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
                <span style={{ fontWeight: 700 }}>₱{pricing.grandTotal.toLocaleString()}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Payment:</span>
                <span style={{ fontWeight: 700, color: '#10B981' }}>{paymentOption === 'full' ? 'Full Payment' : '30% Downpayment'} (₱{pricing.amountToPay.toLocaleString()})</span>
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
    </div>
  );
};

export default ActivityBookingModal;
