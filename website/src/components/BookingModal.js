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

const BookingModal = ({ room, property, user, onClose }) => {
  const [selectedDate, setSelectedDate] = useState(null);
  const [nights, setNights] = useState(1);
  const [selectedAddons, setSelectedAddons] = useState([]);
  const [paymentOption, setPaymentOption] = useState('full'); // 'downpayment' or 'full'
  const [receiptUrl, setReceiptUrl] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [step, setStep] = useState(1); // 1: Details, 2: Payment, 3: Success
  const [bookedDates, setBookedDates] = useState([]);
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [extraBeds, setExtraBeds] = useState(0);

  const addonPrices = {
    'Boat ride to falls': 1200,
    'Kayak': 1200,
    'Dinner': 400,
    'Lunch': 400,
    'Breakfast': 300,
    'Extra Bed': 200
  };

  const addonOptions = [
    'Boat ride to falls',
    'Kayak',
    'Dinner',
    'Lunch',
    'Breakfast'
  ];

  useEffect(() => {
    if (!room?.id) return;

    const bookingsRef = ref(db, 'bookings');
    const q = query(bookingsRef, orderByChild('activityId'), equalTo(room.id));

    const unsubscribe = onValue(q, (snapshot) => {
      const dates = [];
      if (snapshot.exists()) {
        const bookings = snapshot.val();
        Object.values(bookings).forEach(b => {
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

  const toggleAddon = (addon) => {
    setSelectedAddons(prev =>
      prev.includes(addon) ? prev.filter(a => a !== addon) : [...prev, addon]
    );
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

  const calculateTotal = () => {
    try {
      const priceRaw = room?.price ? room.price.toString().replace(/,/g, '') : '0';
      const roomBase = (parseFloat(priceRaw) || 0) * (nights || 1);
      const addonsBase = (selectedAddons || []).reduce((sum, addon) => sum + (addonPrices[addon] || 0), 0);
      const extraBedsBase = (extraBeds || 0) * (addonPrices['Extra Bed'] || 0);
      return roomBase + addonsBase + extraBedsBase;
    } catch (e) {
      console.error("Total calculation error", e);
      return 0;
    }
  };

  const totalAmount = calculateTotal();
  const downpaymentAmount = totalAmount * 0.3;
  const amountToPay = paymentOption === 'full' ? totalAmount : downpaymentAmount;

  const submitBooking = async () => {
    if (!receiptUrl || !selectedDate) return;

    const bookingRef = push(ref(db, 'bookings'));
    const touristName = `${user.firstName || 'Guest'} ${user.lastName || ''}`.trim();

    const finalAddons = [...selectedAddons];
    if (extraBeds > 0) finalAddons.push(`Extra Bed (${extraBeds})`);

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
      nights: nights,
      bookingDate: format(selectedDate, 'MMM dd, yyyy'),
      selectedAddons: finalAddons,
      extraBeds: extraBeds,
      gcashReceipt: receiptUrl,
      paymentMethod: 'GCash',
      paymentOption: paymentOption === 'full' ? 'Full Payment' : '30% Downpayment',
      amountPaid: amountToPay,
      status: 'Pending',
      timestamp: serverTimestamp(),
    };

    try {
      await set(bookingRef, bookingData);
      setStep(3);
    } catch (error) {
      alert('Booking failed: ' + error.message);
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

    setUploading(true);
    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', 'resort_unsigned');

    try {
      const response = await fetch('https://api.cloudinary.com/v1_1/dnv6ezitm/image/upload', {
        method: 'POST',
        body: formData,
      });
      const data = await response.json();
      setReceiptUrl(data.secure_url);
    } catch (error) {
      alert('Upload failed. Please try again.');
    } finally {
      setUploading(false);
    }
  };

  if (step === 3) {
    return (
      <div className="modal-overlay">
        <div className="card modal-content" style={{ textAlign: 'center', padding: '48px 32px', maxWidth: '400px' }}>
          <div style={{
            width: '80px', height: '80px', background: '#ECFDF5',
            borderRadius: '50%', display: 'flex', justifyContent: 'center',
            alignItems: 'center', margin: '0 auto 24px'
          }}>
            <CheckCircle2 size={40} color="#10B981" />
          </div>
          <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0' }}>Request Sent!</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6' }}>
            Your reservation for <strong>{room.title}</strong> has been submitted. The host will review your proof of payment shortly.
          </p>
          <button className="btn btn-primary" onClick={onClose} style={{ marginTop: '32px', width: '100%' }}>Done</button>
        </div>
      </div>
    );
  }

  const selectionConflict = selectedDate && isSelectionConflicting(selectedDate, nights);

  return (
    <div className="modal-overlay" style={{ zIndex: 3000 }}>
      <div className="card modal-content" style={{ maxWidth: '500px', padding: '32px', borderRadius: '32px', maxHeight: '90vh', overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>{step === 1 ? 'Reserve Room' : 'Payment Proof'}</h2>
            <p style={{ margin: '4px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>{room.title}</p>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        {step === 1 ? (
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
              <div className="counter-control">
                <button type="button" onClick={() => { setNights(Math.max(1, nights - 1)); }} className="counter-btn">-</button>
                <div className="counter-value">
                   <span style={{ fontSize: '20px', fontWeight: 800 }}>{nights}</span>
                   <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', marginLeft: '4px' }}>NIGHTS</span>
                </div>
                <button type="button" onClick={() => { setNights(nights + 1); }} className="counter-btn">+</button>
              </div>
              {selectionConflict && (
                <div style={{ color: 'var(--primary)', fontSize: '13px', marginTop: '12px', display: 'flex', alignItems: 'center', gap: '8px', background: '#FEF2F2', padding: '10px', borderRadius: '10px', fontWeight: 600 }}>
                  <AlertCircle size={16} /> Overlaps with an existing booking.
                </div>
              )}
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Extras & Add-ons</label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px', marginBottom: '16px' }}>
                {addonOptions.map(addon => (
                  <button
                    key={addon}
                    type="button"
                    onClick={() => toggleAddon(addon)}
                    className={`addon-chip ${selectedAddons.includes(addon) ? 'active' : ''}`}
                  >
                    {addon} (₱{addonPrices[addon]})
                  </button>
                ))}
              </div>

              <div style={{ padding: '16px', background: '#F9FAFB', borderRadius: '20px', border: '1px solid #F3F4F6' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                   <span style={{ fontSize: '14px', fontWeight: 800 }}>Extra Bed</span>
                   <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--secondary)' }}>₱200 / bed</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                  <button type="button" onClick={() => setExtraBeds(Math.max(0, extraBeds - 1))} className="counter-btn-small">-</button>
                  <span style={{ fontWeight: 800, fontSize: '16px', minWidth: '20px', textAlign: 'center' }}>{extraBeds}</span>
                  <button type="button" onClick={() => setExtraBeds(Math.min(3, extraBeds + 1))} className="counter-btn-small">+</button>
                  <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>(Max 3)</span>
                </div>
              </div>
            </div>

            <div style={{ marginBottom: '32px' }}>
              <label className="input-label">Payment Option</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <button
                  type="button"
                  onClick={() => setPaymentOption('downpayment')}
                  style={{
                    padding: '16px', borderRadius: '16px', border: '2px solid',
                    borderColor: paymentOption === 'downpayment' ? 'var(--secondary)' : '#F3F4F6',
                    background: paymentOption === 'downpayment' ? 'rgba(29, 211, 176, 0.05)' : 'white',
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
                    borderColor: paymentOption === 'full' ? 'var(--secondary)' : '#F3F4F6',
                    background: paymentOption === 'full' ? 'rgba(29, 211, 176, 0.05)' : 'white',
                    cursor: 'pointer', textAlign: 'left', transition: 'all 0.2s'
                  }}
                >
                  <div style={{ fontSize: '14px', fontWeight: 800, color: paymentOption === 'full' ? 'var(--secondary)' : 'var(--text-main)' }}>100% Full Payment</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>₱{(totalAmount || 0).toLocaleString()}</div>
                </button>
              </div>
            </div>

            <div style={{ background: 'var(--light-bg)', padding: '20px', borderRadius: '24px', marginBottom: '24px', border: '1px solid #F3F4F6' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                  <span style={{ fontWeight: 700, color: 'var(--text-muted)' }}>Booking Total</span>
                  <span style={{ color: 'var(--text-main)', fontSize: '18px', fontWeight: 800 }}>₱{(totalAmount || 0).toLocaleString()}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: '12px', borderTop: '1px dashed #E5E7EB' }}>
                  <span style={{ fontWeight: 700, color: 'var(--text-muted)' }}>Amount Due Today ({paymentOption === 'full' ? '100%' : '30%'})</span>
                  <span style={{ color: 'var(--secondary)', fontSize: '24px', fontWeight: 800 }}>₱{(amountToPay || 0).toLocaleString()}</span>
                </div>
                {paymentOption === 'downpayment' && (
                  <p style={{ margin: '8px 0 0 0', fontSize: '11px', color: 'var(--text-muted)', fontStyle: 'italic', textAlign: 'right' }}>
                    Remaining ₱{((totalAmount || 0) * 0.7).toLocaleString()} to be paid at check-in
                  </p>
                )}
            </div>

            <button
              type="button"
              className="btn btn-primary"
              style={{ width: '100%', height: '56px', cursor: (!selectedDate || selectionConflict) ? 'not-allowed' : 'pointer' }}
              onClick={() => {
                console.log("Advancing step to 2");
                setStep(2);
              }}
              disabled={!selectedDate || selectionConflict}
            >
              Continue to Payment
            </button>
          </div>
        ) : (
          <div className="step-content">
            <div style={{ background: 'linear-gradient(135deg, #EFF6FF, #DBEAFE)', padding: '24px', borderRadius: '24px', marginBottom: '24px', border: '1px solid #BFDBFE' }}>
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
            </div>

            <div style={{ marginBottom: '24px' }}>
              <label className="input-label">Upload Proof of Payment</label>
              {receiptUrl ? (
                <div style={{ position: 'relative', borderRadius: '20px', overflow: 'hidden', boxShadow: 'var(--shadow)' }}>
                  <img src={receiptUrl} alt="Receipt" style={{ width: '100%', height: '200px', objectFit: 'cover' }} />
                  <button type="button" onClick={() => setReceiptUrl(null)} className="remove-img-btn"><X size={16} /></button>
                </div>
              ) : (
                <div className="upload-placeholder" onClick={() => document.getElementById('receiptInput').click()}>
                  <div style={{ background: 'white', padding: '12px', borderRadius: '14px', marginBottom: '12px', boxShadow: '0 4px 12px rgba(0,0,0,0.05)' }}>
                    <Upload color="var(--secondary)" size={24} />
                  </div>
                  <p style={{ fontWeight: 700, margin: 0, fontSize: '14px' }}>{uploading ? 'Processing Image...' : 'Tap to Upload Receipt'}</p>
                  <p style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '4px' }}>JPG, PNG or PDF up to 5MB</p>
                  <input type="file" id="receiptInput" hidden accept="image/*" onChange={handleFileUpload} disabled={uploading} />
                </div>
              )}
            </div>

            <div style={{ display: 'flex', gap: '12px' }}>
              <button type="button" className="btn" style={{ flex: 1, background: '#F3F4F6', color: 'var(--text-main)' }} onClick={() => setStep(1)}>Back</button>
              <button
                type="button"
                className="btn btn-primary"
                style={{ flex: 2 }}
                disabled={!receiptUrl || uploading}
                onClick={submitBooking}
              >
                Complete Reservation
              </button>
            </div>

            <div style={{ marginTop: '24px', display: 'flex', gap: '10px', alignItems: 'flex-start', background: '#F9FAFB', padding: '16px', borderRadius: '16px' }}>
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
        .close-btn { background: #F3F4F6; border: none; width: 36px; height: 36px; borderRadius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); }
        .close-btn:hover { background: #E5E7EB; transform: rotate(90deg); }

        /* Modern Calendar Styles */
        .modern-calendar { background: #F9FAFB; padding: 20px; borderRadius: 24px; border: 1px solid #F3F4F6; }
        .nav-btn { background: white; border: none; width: 32px; height: 32px; borderRadius: 10px; display: flex; align-items: center; justify-content: center; cursor: pointer; boxShadow: 0 2px 8px rgba(0,0,0,0.05); }
        .calendar-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 8px; }
        .day-label { text-align: center; font-size: 11px; font-weight: 800; color: var(--text-muted); padding-bottom: 10px; }
        .calendar-day { aspect-ratio: 1; border: none; background: white; borderRadius: 12px; font-size: 14px; font-weight: 700; cursor: pointer; transition: var(--transition); display: flex; align-items: center; justify-content: center; boxShadow: 0 2px 4px rgba(0,0,0,0.02); }
        .calendar-day:hover:not(:disabled) { transform: scale(1.1); boxShadow: 0 4px 12px rgba(0,0,0,0.1); z-index: 1; }
        .calendar-day.selected { background: var(--primary) !important; color: white !important; boxShadow: 0 8px 15px rgba(251, 54, 64, 0.3); transform: scale(1.1); z-index: 1; }
        .calendar-day.booked { background: #FEF2F2; color: #EF4444; text-decoration: line-through; cursor: not-allowed; opacity: 0.5; border: 1px dashed #FEE2E2; }
        .calendar-day.past { color: #E5E7EB; cursor: not-allowed; background: transparent; boxShadow: none; }
        .calendar-day.today { color: var(--secondary); border: 2px solid var(--secondary); }
        .calendar-day.other-month { opacity: 0.3; }
        .dot { width: 8px; height: 8px; borderRadius: 50%; display: inline-block; margin-right: 6px; }
        .dot.booked { background: #EF4444; }
        .dot.available { background: white; border: 1px solid #E5E7EB; }

        /* Counter Controls */
        .counter-control { display: flex; align-items: center; gap: 24px; background: #F3F4F6; padding: 12px 20px; borderRadius: 20px; width: fit-content; }
        .counter-btn { width: 40px; height: 40px; borderRadius: 14px; border: none; background: white; fontSize: 20px; font-weight: 700; cursor: pointer; display: flex; align-items: center; justify-content: center; boxShadow: 0 4px 10px rgba(0,0,0,0.05); transition: var(--transition); }
        .counter-btn:hover { background: var(--secondary); color: white; transform: translateY(-2px); }
        .counter-btn-small { width: 32px; height: 32px; borderRadius: 10px; border: none; background: white; fontSize: 18px; font-weight: 700; cursor: pointer; display: flex; align-items: center; justify-content: center; boxShadow: 0 2px 6px rgba(0,0,0,0.05); transition: var(--transition); }
        .counter-btn-small:hover { background: var(--secondary); color: white; }
        .counter-value { display: flex; align-items: baseline; }

        /* Addon Chips */
        .addon-chip { padding: 8px 16px; border-radius: 12px; border: 2px solid #F3F4F6; background: white; font-size: 13px; font-weight: 700; color: var(--text-muted); cursor: pointer; transition: var(--transition); }
        .addon-chip.active { border-color: var(--secondary); background: rgba(29, 211, 176, 0.05); color: var(--secondary); }
        .addon-chip:hover:not(.active) { border-color: #E5E7EB; background: #F9FAFB; }

        /* Upload UI */
        .upload-placeholder { border: 2px dashed #E5E7EB; border-radius: 24px; padding: 40px 20px; text-align: center; cursor: pointer; background: #F9FAFB; transition: var(--transition); }
        .upload-placeholder:hover { border-color: var(--secondary); background: white; }
        .remove-img-btn { position: absolute; top: 12px; right: 12px; background: rgba(0,0,0,0.5); color: white; border: none; width: 28px; height: 28px; borderRadius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; backdrop-filter: blur(4px); }
      `}</style>
    </div>
  );
};

export default BookingModal;
