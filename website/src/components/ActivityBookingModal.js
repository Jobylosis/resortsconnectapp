import React, { useState } from 'react';
import { X, Calendar as CalendarIcon, Clock, Users, ArrowRight, Info } from 'lucide-react';
import { format } from 'date-fns';
import { db } from '../firebase';
import { ref, push, set, get } from 'firebase/database';
import { sendOwnerBookingNotificationEmail } from '../services/emailService';

const DEFAULT_SCHEDULE = "Kayak, Boat ride to Pagsanjan falls, and Paddle board: 7:00 AM to 3:30 PM. Bar, Karaoke, and Dinner: 7:00 AM to 10:00 PM.";

const ActivityBookingModal = ({ activity, isOpen, onClose, ownerUid, propertyName, touristInfo, activitySchedule }) => {
  const [selectedDate, setSelectedDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [pax, setPax] = useState(1);
  const [loading, setLoading] = useState(false);

  if (!isOpen || !activity) return null;

  const scheduleText = activitySchedule || DEFAULT_SCHEDULE;

  const handleBook = async () => {
    if (pax < 1 || (activity.maxPax && pax > activity.maxPax)) {
      return alert("Invalid number of guests.");
    }
    
    setLoading(true);
    try {
      const bookingRef = push(ref(db, 'bookings'));
      const formattedBookingDate = selectedDate ? format(new Date(selectedDate), 'MMM dd, yyyy') : '';
      const calculatedTotal = Number(activity.price || 0) * pax;
      const guestDisplayName = touristInfo?.name || touristInfo?.fullName || 'Guest';

      const bookingData = {
        type: 'activity',
        activityId: activity.id,
        activityTitle: activity.title,
        ownerUid: ownerUid,
        propertyName: propertyName,
        touristUid: touristInfo?.uid || 'guest',
        touristName: guestDisplayName,
        date: selectedDate,
        bookingDate: formattedBookingDate,
        checkInDate: formattedBookingDate,
        nights: 1,
        timeSlot: 'Regular Operating Hours',
        pax: pax,
        totalPrice: calculatedTotal,
        status: 'Pending',
        timestamp: Date.now()
      };
      await set(bookingRef, bookingData);

      // Notify owner in notifications/${ownerUid}
      try {
        const notifRef = push(ref(db, `notifications/${ownerUid}`));
        await set(notifRef, {
          title: 'New Activity Booking',
          message: `${guestDisplayName} booked activity "${activity.title}" for ${formattedBookingDate || selectedDate}.`,
          type: 'new_booking',
          isRead: false,
          timestamp: Date.now(),
          bookingId: bookingRef.key
        });
      } catch (e) {
        console.warn('Could not send owner notification in DB:', e);
      }

      // EmailJS Owner Notification
      try {
        let ownerEmail = null;
        let ownerName = propertyName || 'Resort Owner';

        if (ownerUid) {
          const propSnap = await get(ref(db, `properties/${ownerUid}`));
          if (propSnap.exists()) {
            const propData = propSnap.val();
            ownerEmail = propData.contact?.email || propData.email;
          }

          if (!ownerEmail) {
            const userSnap = await get(ref(db, `users/${ownerUid}`));
            if (userSnap.exists()) {
              const uData = userSnap.val();
              ownerEmail = uData.email;
              ownerName = uData.firstName ? `${uData.firstName} ${uData.lastName || ''}`.trim() : ownerName;
            }
          }
        }

        if (ownerEmail) {
          sendOwnerBookingNotificationEmail({
            toEmail: ownerEmail,
            ownerName: ownerName,
            guestName: guestDisplayName,
            bookingType: 'activity',
            itemName: activity.title,
            propertyName: propertyName || 'Your Resort',
            checkInDate: formattedBookingDate || selectedDate,
            nights: 1,
            pax: pax,
            totalPrice: calculatedTotal,
            amountPaid: 0,
            paymentOption: 'Pay at Resort / Host confirmation',
            paymentMethod: 'Host Confirmation',
            referenceNo: 'N/A',
            bookingId: bookingRef.key
          }).catch(err => console.warn('[EmailJS] Owner activity notification error:', err));
        }
      } catch (emailErr) {
        console.warn('[EmailJS] Failed to send activity booking notification email:', emailErr);
      }

      alert("Activity booking submitted successfully! The host will confirm your booking.");
      onClose();
    } catch (err) {
      alert("Booking failed: " + err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.65)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: '24px', backdropFilter: 'blur(4px)' }}>
      <div style={{ background: 'var(--surface)', width: '100%', maxWidth: '520px', borderRadius: '24px', overflow: 'hidden', boxShadow: '0 20px 60px rgba(0,0,0,0.3)' }}>
        <div style={{ padding: '24px 32px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>Book Activity</h2>
            <p style={{ margin: '4px 0 0 0', color: 'var(--text-muted)', fontSize: '14px' }}>{activity.title}</p>
          </div>
          <button onClick={onClose} style={{ background: 'var(--light-bg)', border: 'none', width: '40px', height: '40px', borderRadius: '50%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: '28px 32px' }}>
          <div style={{ display: 'grid', gap: '20px' }}>
            {/* Operating Hours Notice */}
            <div style={{
              background: 'rgba(245, 158, 11, 0.08)',
              border: '1px solid rgba(245, 158, 11, 0.3)',
              borderRadius: '16px',
              padding: '16px',
              display: 'flex',
              gap: '12px',
              alignItems: 'flex-start'
            }}>
              <div style={{ background: '#F59E0B', color: 'white', borderRadius: '50%', width: '28px', height: '28px', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginTop: '2px' }}>
                <Clock size={16} />
              </div>
              <div>
                <div style={{ fontSize: '13px', fontWeight: 800, color: '#B45309', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '4px' }}>
                  Activity Operating Schedule
                </div>
                <div style={{ fontSize: '13px', color: 'var(--text-main)', lineHeight: '1.5', fontWeight: 600 }}>
                  {scheduleText}
                </div>
              </div>
            </div>

            {/* Date Picker */}
            <div>
              <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', textTransform: 'uppercase', letterSpacing: '1px' }}>Select Date</label>
              <div style={{ position: 'relative' }}>
                <CalendarIcon size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                <input 
                  type="date" 
                  className="input" 
                  style={{ paddingLeft: '48px', width: '100%' }} 
                  min={format(new Date(), 'yyyy-MM-dd')}
                  value={selectedDate}
                  onChange={e => setSelectedDate(e.target.value)}
                />
              </div>
            </div>

            {/* Pax */}
            <div>
              <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', textTransform: 'uppercase', letterSpacing: '1px' }}>Number of Guests</label>
              <div style={{ position: 'relative' }}>
                <Users size={18} style={{ position: 'absolute', left: '16px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                <input 
                  type="number" 
                  className="input" 
                  style={{ paddingLeft: '48px', width: '100%' }} 
                  min="1"
                  max={activity.maxPax || 100}
                  value={pax}
                  onChange={e => setPax(Number(e.target.value))}
                />
              </div>
              {activity.maxPax && <p style={{ margin: '8px 0 0 0', fontSize: '12px', color: 'var(--text-muted)' }}>Maximum {activity.maxPax} persons per booking.</p>}
            </div>

            <div style={{ padding: '16px 20px', background: 'var(--light-bg)', borderRadius: '16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '4px' }}>
              <div>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Total Amount</span>
                <div style={{ fontSize: '24px', fontWeight: 900, color: 'var(--text-main)' }}>₱{(Number(activity.price || 0) * pax).toLocaleString()}</div>
              </div>
              <button 
                className="btn btn-primary" 
                onClick={handleBook} 
                disabled={loading}
                style={{ padding: '12px 24px', display: 'flex', alignItems: 'center', gap: '8px', borderRadius: '14px', fontWeight: 800 }}
              >
                {loading ? 'Booking...' : 'Confirm Booking'}
                {!loading && <ArrowRight size={18} />}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ActivityBookingModal;
