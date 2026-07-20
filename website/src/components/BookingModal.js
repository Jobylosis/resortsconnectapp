import React, { useState, useEffect } from 'react';
import { db, auth } from '../firebase';
import { ref, push, set, get, query, orderByChild, equalTo, serverTimestamp, onValue } from 'firebase/database';
import { X, Calendar as CalendarIcon, CreditCard, Upload, CheckCircle2, AlertCircle, ChevronLeft, ChevronRight, Info, Wallet } from 'lucide-react';
import {
  format, parse, addDays, isBefore, isAfter,
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  eachDayOfInterval, isSameDay, isToday, addMonths, subMonths,
  startOfDay
} from 'date-fns';
import gcashQr from '../assets/gcashqr1.jpg';
import TermsAndPolicies from './TermsAndPolicies';

const BookingModal = ({ room, property, user, onClose, isPreview = false, onViewPolicies }) => {
  const [selectedDate, setSelectedDate] = useState(null);
  const [nights, setNights] = useState(1);
  const [selectedAddons, setSelectedAddons] = useState({}); // Name -> Quantity
  const [paymentOption, setPaymentOption] = useState('full'); // 'downpayment' or 'full'
  const [receiptUrl, setReceiptUrl] = useState(null);
  const [extractedRefNo, setExtractedRefNo] = useState(null);
  const [ocrStatus, setOcrStatus] = useState(null); // 'Verified' | 'Flagged'
  const [ocrIssues, setOcrIssues] = useState('');
  const [uploading, setUploading] = useState(false);
  const [step, setStep] = useState(1); // 1: Booking, 2: Payment, 3: Success
  const [bookedDates, setBookedDates] = useState([]);
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
    'Breakfast': { unit: 'set', desc: 'Continental breakfast' },
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
              const start = parse(b.bookingDate, 'MMM dd, yyyy', new Date());
              const duration = parseInt(b.nights) || 1;
              for (let i = 0; i < duration; i++) {
                dates.push(startOfDay(addDays(start, i)));
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
      const taxes = 0; // Removed taxes
      const grandTotal = subtotal + taxes;

      return { basePrice, addonsTotal, addonsList, subtotal, taxes, grandTotal };
    } catch (e) {
      console.error("Pricing calculation error", e);
      return { basePrice: 0, addonsTotal: 0, addonsList: [], subtotal: 0, taxes: 0, grandTotal: 0 };
    }
  };

  const pricing = calculatePricing();
  const totalAmount = pricing.grandTotal;
  const downpaymentAmount = totalAmount * 0.3;
  const amountToPay = paymentOption === 'full' ? totalAmount : downpaymentAmount;

  const submitBooking = async () => {
    if (!selectedDate) return;

    setUploading(true);
    const bookingRef = push(ref(db, 'bookings'));
    const tName = user?.firstName || user?.name || user?.fullName || 'Guest';
    const tLast = user?.lastName ? ` ${user.lastName}` : '';
    const touristName = `${tName}${tLast}`.trim();

    const finalAddons = [];
    Object.entries(selectedAddons).forEach(([name, qty]) => {
      if (qty > 0) finalAddons.push(`${name} (x${qty})`);
    });

    const bookingData = {
      touristUid: user?.uid || auth.currentUser?.uid,
      touristName: touristName,
      touristProfilePic: user?.profilePicUrl || '',
      ownerUid: property.uid,
      activityId: room.id,
      propertyName: property.name,
      activityTitle: room.title,
      price: room.price,
      totalPrice: totalAmount,
      pricing: {
        basePrice: pricing.basePrice,
        subtotal: pricing.subtotal,
        addonsTotal: pricing.addonsTotal,
        addonsList: pricing.addonsList,
        taxesAndFees: pricing.taxes,
        grandTotal: pricing.grandTotal
      },
      nights: nights,
      bookingDate: format(selectedDate, 'MMM dd, yyyy'),
      selectedAddons: finalAddons,
      paymentMethod: 'GCash',
      paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment',
      amountPaid: amountToPay,
      status: ocrStatus === 'Verified' ? 'Confirmed' : (ocrStatus === 'Flagged' ? 'Declined' : 'Pending'),
      paymentStatus: ocrStatus === 'Verified' ? 'paid' : 'pending',
      gcashReceipt: receiptUrl,
      extractedRefNo: extractedRefNo || '',
      ocrStatus: ocrStatus || 'Unverified',
      ocrIssues: ocrIssues || '',
      agreedToTerms: true,
      termsAcceptedAt: serverTimestamp(),
      timestamp: serverTimestamp(),
    };

    try {
      await set(bookingRef, bookingData);
      
      const notifRef = push(ref(db, `notifications/${property.uid}`));
      await set(notifRef, {
        title: 'New Booking Request',
        message: `${touristName} has requested to book ${room.title}.`,
        type: 'new_booking',
        isRead: false,
        timestamp: serverTimestamp(),
        bookingId: bookingRef.key
      });

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
          body: ocrFormData,
        });
        const ocrData = await ocrResponse.json();
        
        if (ocrData.success) {
          isVerified = true;
          setExtractedRefNo(ocrData.reference_number);
          console.log("OCR Validated. Ref:", ocrData.reference_number, "Amount:", ocrData.amount);
        } else {
          ocrErrorMsg = ocrData.error || "Could not auto-verify GCash receipt.";
          setOcrIssues(ocrErrorMsg);
        }
      } catch (ocrError) {
        console.error('OCR Backend failed:', ocrError);
        ocrErrorMsg = "OCR Server unreachable.";
        setOcrIssues(ocrErrorMsg);
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
          <button className="btn btn-primary" onClick={onClose} style={{ marginTop: '32px', width: '100%' }}>Done</button>
        </div>
      </div>
    );
  }

  const selectionConflict = selectedDate && isSelectionConflicting(selectedDate, nights);

  return (
    <div className="modal-overlay" style={{ zIndex: 3000 }}>
      {showPolicies && <TermsAndPolicies onClose={() => setShowPolicies(null)} initialScroll={showPolicies} />}
      <div className="card modal-content" style={{ maxWidth: '500px', padding: '32px', borderRadius: '32px', maxHeight: '90vh', overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>{step === 0 ? 'Room Details' : step === 1 ? 'Reserve Room' : 'Payment Proof'}</h2>
            <p style={{ margin: '4px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>{room.title}</p>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
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
                  if (nights >= 10) {
                    alert('Cannot extend stay: Maximum booking duration is 10 nights.');
                  } else if (selectedDate && isSelectionConflicting(selectedDate, nights + 1)) {
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
                  onClick={() => setPaymentOption('downpayment')}
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
                  onClick={() => setPaymentOption('full')}
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
              <button type="button" className="btn" style={{ width: '100%', background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }} onClick={() => setStep(0)}>Back to Details</button>
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
                      <p style={{ margin: '4px 0 0 0', fontSize: '12px' }}>Amount must match exactly</p>
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
              <button type="button" className="btn" style={{ flex: 1, background: 'var(--light-bg)', color: 'var(--text-main)', border: '1px solid var(--border)' }} onClick={() => setStep(1)}>Back</button>
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
