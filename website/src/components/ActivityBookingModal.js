import React, { useState } from 'react';
import { X, Calendar as CalendarIcon, Clock, Users, ArrowRight } from 'lucide-react';
import { format, addDays } from 'date-fns';
import { db } from '../firebase';
import { ref, push, set } from 'firebase/database';

const ActivityBookingModal = ({ activity, isOpen, onClose, ownerUid, propertyName, touristInfo }) => {
  const [selectedDate, setSelectedDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [selectedSlot, setSelectedSlot] = useState('');
  const [pax, setPax] = useState(1);
  const [loading, setLoading] = useState(false);

  if (!isOpen || !activity) return null;

  const handleBook = async () => {
    if (!selectedSlot) return alert("Please select a time slot.");
    if (pax < 1 || (activity.maxPax && pax > activity.maxPax)) {
      return alert("Invalid number of pax.");
    }
    
    setLoading(true);
    try {
      const bookingRef = push(ref(db, 'bookings'));
      await set(bookingRef, {
        type: 'activity',
        activityId: activity.id,
        activityTitle: activity.title,
        ownerUid: ownerUid,
        propertyName: propertyName,
        touristUid: touristInfo?.uid || 'guest',
        touristName: touristInfo?.name || 'Guest',
        date: selectedDate,
        timeSlot: selectedSlot,
        pax: pax,
        totalPrice: Number(activity.price || 0) * pax,
        status: 'Pending',
        timestamp: Date.now()
      });
      alert("Activity booking submitted!");
      onClose();
    } catch (err) {
      alert("Booking failed: " + err.message);
    } finally {
      setLoading(false);
    }
  };

  const timeSlots = Array.isArray(activity.timeSlots) ? activity.timeSlots : [];

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.65)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: '24px' }}>
      <div style={{ background: 'var(--surface)', width: '100%', maxWidth: '500px', borderRadius: '24px', overflow: 'hidden' }}>
        <div style={{ padding: '24px 32px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '24px', fontWeight: 800 }}>Book Activity</h2>
            <p style={{ margin: '4px 0 0 0', color: 'var(--text-muted)', fontSize: '14px' }}>{activity.title}</p>
          </div>
          <button onClick={onClose} style={{ background: 'var(--light-bg)', border: 'none', width: '40px', height: '40px', borderRadius: '50%', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: '32px' }}>
          <div style={{ display: 'grid', gap: '24px' }}>
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

            {/* Time Slot Picker */}
            <div>
              <label style={{ display: 'block', fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)', marginBottom: '8px', textTransform: 'uppercase', letterSpacing: '1px' }}>Select Time Slot</label>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px' }}>
                {timeSlots.map((slot, i) => (
                  <button 
                    key={i} 
                    onClick={() => setSelectedSlot(slot)}
                    style={{ 
                      padding: '10px 16px', 
                      borderRadius: '12px', 
                      border: selectedSlot === slot ? '2px solid var(--primary)' : '1px solid var(--border)',
                      background: selectedSlot === slot ? 'rgba(var(--primary-rgb), 0.1)' : 'var(--light-bg)',
                      color: selectedSlot === slot ? 'var(--primary)' : 'var(--text-main)',
                      fontWeight: 700,
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '8px'
                    }}
                  >
                    <Clock size={16} /> {slot}
                  </button>
                ))}
                {timeSlots.length === 0 && <p style={{ color: 'var(--text-muted)' }}>No time slots available.</p>}
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
              {activity.maxPax && <p style={{ margin: '8px 0 0 0', fontSize: '12px', color: 'var(--text-muted)' }}>Maximum {activity.maxPax} persons per slot.</p>}
            </div>

            <div style={{ padding: '16px', background: 'var(--light-bg)', borderRadius: '16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '12px' }}>
              <div>
                <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-muted)' }}>Total Amount</span>
                <div style={{ fontSize: '24px', fontWeight: 900, color: 'var(--text-main)' }}>₱{(Number(activity.price || 0) * pax).toLocaleString()}</div>
              </div>
              <button 
                className="btn btn-primary" 
                onClick={handleBook} 
                disabled={loading || !selectedSlot}
                style={{ padding: '12px 24px', display: 'flex', alignItems: 'center', gap: '8px' }}
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
