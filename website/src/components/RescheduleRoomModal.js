import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, update, query, orderByChild, equalTo, onValue, push } from 'firebase/database';
import { X, ChevronLeft, ChevronRight, AlertCircle, CheckCircle2 } from 'lucide-react';
import {
  format, addDays, isBefore,
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  eachDayOfInterval, isSameDay, addMonths, subMonths,
  startOfDay
} from 'date-fns';
import { parseDateSafely } from './OwnerDashboard';

const RescheduleRoomModal = ({ booking, onClose }) => {
  const [selectedDate, setSelectedDate] = useState(null);
  const roomId = booking?.roomId || booking?.activityId;
  const nights = parseInt(booking?.nights || 1);
  const [reason, setReason] = useState('');
  const [bookedDates, setBookedDates] = useState([]);
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [loading, setLoading] = useState(true);
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    if (!roomId && !booking?.roomTitle) {
      setLoading(false);
      return;
    }

    const bookingsRef = ref(db, 'bookings');

    const unsubscribe = onValue(bookingsRef, (snapshot) => {
      const dates = [];
      if (snapshot.exists()) {
        const data = snapshot.val();
        const bookingsArray = Array.isArray(data)
          ? data.map((b, i) => [i.toString(), b]).filter(([id, b]) => b !== null)
          : Object.entries(data);

        bookingsArray.forEach(([id, b]) => {
          if (id === booking?.id) return;
          if (!b) return;

          // Check if booking belongs to this room (either by roomId, activityId, or roomTitle match)
          const matchesRoom = (roomId && (b.roomId === roomId || b.activityId === roomId)) ||
            (booking?.roomTitle && b.roomTitle && b.roomTitle.trim().toLowerCase() === booking.roomTitle.trim().toLowerCase());

          if (!matchesRoom) return;

          const status = (b.status || '').toLowerCase().trim();
          // Room bookings with confirmed, checked in, or reschedule requested occupy the room
          if (status === 'confirmed' || status === 'checked in' || status === 'reschedule requested') {
            try {
              const start = parseDateSafely(b.bookingDate || b.checkInDate || b.date);
              if (start) {
                const stayNights = parseInt(b.nights) || 1;
                for (let i = 0; i < stayNights; i++) {
                  dates.push(startOfDay(addDays(start, i)));
                }
              }
            } catch (e) {}
          }
        });
      }
      setBookedDates(dates);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [booking?.id, booking?.roomTitle, roomId]);

  const isDateBooked = (date) => {
    return bookedDates.some(bookedDate => isSameDay(bookedDate, date));
  };

  const isSelectionConflicting = (startDate, duration) => {
    for (let i = 0; i < duration; i++) {
      if (isDateBooked(addDays(startDate, i))) return true;
    }
    return false;
  };

  const handleReschedule = async () => {
    if (!selectedDate) return;
    if (!reason.trim()) {
      alert("Please provide a reason for the reschedule request.");
      return;
    }

    try {
      const formattedDate = format(selectedDate, 'MMM dd, yyyy');
      const updateData = {
        status: 'Reschedule Requested',
        requestedRescheduleDate: formattedDate,
        requestedRescheduleNights: nights,
        rescheduleReason: reason.trim(),
      };
      await update(ref(db, `bookings/${booking.id}`), updateData);

      if (booking.ownerUid) {
        const touristName = booking.touristName || booking.userName || 'A tourist';
        const itemTitle = booking.roomTitle || booking.activityTitle || 'room booking';
        const durLabel = `${nights} ${nights === 1 ? 'night' : 'nights'}`;
        await push(ref(db, `notifications/${booking.ownerUid}`), {
          title: 'Reschedule Requested',
          message: `${touristName} requested to reschedule room "${itemTitle}" to ${formattedDate} (${durLabel}). Reason: ${reason.trim()}`,
          type: 'reschedule_requested',
          isRead: false,
          timestamp: Date.now(),
          bookingId: booking.id,
        });
      }

      setSuccess(true);
    } catch (error) {
      alert('Reschedule request failed: ' + error.message);
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
            // Overlap conflict: starting on this day for the required `nights` intersects an existing booking
            const isConflict = !isPast && isSelectionConflicting(day, nights);

            let className = "calendar-day";
            if (!isCurrentMonth) className += " other-month";
            if (isBooked) className += " booked";
            else if (isConflict) className += " conflict";
            if (isSelected) className += " selected";
            if (isPast) className += " past";

            return (
              <button
                key={idx}
                type="button"
                className={className}
                disabled={isPast || isBooked || isConflict}
                title={
                  isBooked
                    ? "This room is already booked on this date"
                    : isConflict
                    ? `Cannot check in here: a ${nights}-night stay would overlap with an existing booking`
                    : ""
                }
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

  if (success) {
    return (
      <div className="modal-overlay" style={{ zIndex: 3000 }}>
        <div className="card modal-content" style={{ maxWidth: '450px', textAlign: 'center', padding: '40px 32px', borderRadius: '32px' }}>
          <div style={{
            width: '80px', height: '80px', background: '#EEF2FF',
            borderRadius: '50%', display: 'flex', justifyContent: 'center',
            alignItems: 'center', margin: '0 auto 24px'
          }}>
            <CheckCircle2 size={40} color="#4F46E5" />
          </div>
          <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0' }}>Request Sent!</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6' }}>
            Your request to reschedule for <strong>{format(selectedDate, 'MMM dd, yyyy')} ({nights} {nights === 1 ? 'Night' : 'Nights'})</strong> has been submitted to the host.
          </p>
          <button className="btn btn-primary" onClick={onClose} style={{ marginTop: '32px', width: '100%' }}>Done</button>
        </div>
      </div>
    );
  }

  const selectionConflict = selectedDate && isSelectionConflicting(selectedDate, nights);

  return (
    <div className="modal-overlay" style={{ zIndex: 3000 }}>
      <div className="card modal-content" style={{ maxWidth: '450px', padding: '32px', borderRadius: '32px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Reschedule Room Booking</h2>
            <p style={{ margin: '4px 0 0 0', fontSize: '14px', color: 'var(--secondary)', fontWeight: 700 }}>{booking.roomTitle || booking.activityTitle}</p>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        <div style={{ marginBottom: '24px' }}>
          <label className="input-label">Select New Check-in Date</label>
          {loading ? (
             <div style={{ textAlign: 'center', padding: '40px 0' }}><div className="loader"></div></div>
          ) : renderCalendar()}
        </div>

        <div style={{ marginBottom: '32px' }}>
          <label className="input-label">Duration of Stay</label>
          <div className="duration-stay-badge">
             <span style={{ fontSize: '20px', fontWeight: 900, color: 'var(--text-main)' }}>{nights}</span>
             <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-muted)', marginLeft: '6px' }}>{nights === 1 ? 'NIGHT' : 'NIGHTS'} (Fixed)</span>
          </div>
          {selectionConflict && (
            <div style={{ color: 'var(--primary)', fontSize: '13px', marginTop: '12px', display: 'flex', alignItems: 'center', gap: '8px', background: 'rgba(251, 54, 64, 0.15)', padding: '10px', borderRadius: '10px', fontWeight: 600 }}>
              <AlertCircle size={16} /> Selected range overlaps with an existing booking. Please choose a different start date.
            </div>
          )}
        </div>

        <div style={{ marginBottom: '24px' }}>
          <label className="input-label">Reason for Reschedule</label>
          <textarea 
            className="input" 
            placeholder="Please briefly explain why you need to reschedule (required)..." 
            value={reason} 
            onChange={(e) => setReason(e.target.value)} 
            style={{ width: '100%', height: '80px', resize: 'none', padding: '12px', borderRadius: '12px', border: '1px solid var(--border)', fontSize: '14px' }}
            maxLength="200"
          />
        </div>

        <button
          className="btn btn-primary"
          style={{ width: '100%', height: '56px' }}
          disabled={!selectedDate || selectionConflict || !reason.trim()}
          onClick={handleReschedule}
        >
          Send Reschedule Request
        </button>
      </div>

      <style>{`
        .input-label { display: block; font-size: 13px; font-weight: 800; color: var(--text-main); margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
        .close-btn { background: var(--light-bg); border: none; width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); border: 1px solid var(--border); }
        .close-btn:hover { background: var(--surface); transform: rotate(90deg); }

        .modern-calendar { background: var(--light-bg); padding: 20px; border-radius: 24px; border: 1px solid var(--border); }
        .nav-btn { background: var(--surface); border: 1px solid var(--border); color: var(--text-main); width: 32px; height: 32px; border-radius: 10px; display: flex; align-items: center; justify-content: center; cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,0.05); }
        .calendar-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 8px; }
        .day-label { text-align: center; font-size: 11px; font-weight: 800; color: var(--text-muted); padding-bottom: 10px; }
        .calendar-day { aspect-ratio: 1; border: none; background: var(--surface); color: var(--text-main); border-radius: 12px; font-size: 14px; font-weight: 700; cursor: pointer; transition: var(--transition); display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 4px rgba(0,0,0,0.02); }
        .calendar-day:hover:not(:disabled) { transform: scale(1.1); box-shadow: 0 4px 12px rgba(0,0,0,0.1); z-index: 1; }
        .calendar-day.selected { background: var(--primary) !important; color: white !important; box-shadow: 0 8px 15px rgba(251, 54, 64, 0.3); transform: scale(1.1); z-index: 1; }
        .calendar-day.booked { background: rgba(239, 68, 68, 0.1); color: #EF4444; text-decoration: line-through; cursor: not-allowed; opacity: 0.5; border: 1px dashed #FEE2E2; }
        .calendar-day.conflict { background: rgba(239, 68, 68, 0.05); color: #EF4444; cursor: not-allowed; opacity: 0.45; border: 1px dotted rgba(239, 68, 68, 0.3); }
        .calendar-day.past { color: #E5E7EB; cursor: not-allowed; background: transparent; box-shadow: none; }
        .calendar-day.today { color: var(--secondary); border: 2px solid var(--secondary); }
        .calendar-day.other-month { opacity: 0.3; }

        .duration-stay-badge {
          display: flex;
          align-items: baseline;
          justify-content: center;
          background: var(--light-bg);
          border: 1px solid var(--border);
          border-radius: 16px;
          padding: 12px 24px;
          width: fit-content;
          margin: 0 auto;
        }
      `}</style>
    </div>
  );
};

export default RescheduleRoomModal;
