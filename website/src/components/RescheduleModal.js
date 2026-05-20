import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { ref, update, query, orderByChild, equalTo, onValue } from 'firebase/database';
import { X, Calendar as CalendarIcon, ChevronLeft, ChevronRight, AlertCircle, CheckCircle2 } from 'lucide-react';
import {
  format, parse, addDays, isBefore,
  startOfMonth, endOfMonth, startOfWeek, endOfWeek,
  eachDayOfInterval, isSameDay, isToday, addMonths, subMonths,
  startOfDay
} from 'date-fns';

const RescheduleModal = ({ booking, onClose }) => {
  const [selectedDate, setSelectedDate] = useState(null);
  const [nights, setNights] = useState(parseInt(booking.nights) || 1);
  const [bookedDates, setBookedDates] = useState([]);
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [loading, setLoading] = useState(true);
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    if (!booking?.activityId) return;

    const bookingsRef = ref(db, 'bookings');
    const q = query(bookingsRef, orderByChild('activityId'), equalTo(booking.activityId));

    const unsubscribe = onValue(q, (snapshot) => {
      const dates = [];
      if (snapshot.exists()) {
        const data = snapshot.val();
        const bookingsArray = Array.isArray(data)
          ? data.map((b, i) => [i.toString(), b]).filter(([id, b]) => b !== null)
          : Object.entries(data);

        bookingsArray.forEach(([id, b]) => {
          if (id === booking.id) return; // Ignore current booking
          const status = (b.status || '').toLowerCase();
          if (status === 'confirmed' || status === 'checked in') {
            try {
              const start = parse(b.bookingDate, 'MMM dd, yyyy', new Date());
              const duration = parseInt(b.nights) || 1;
              for (let i = 0; i < duration; i++) {
                dates.push(startOfDay(addDays(start, i)));
              }
            } catch (e) {}
          }
        });
      }
      setBookedDates(dates);
      setLoading(false);
    });

    return () => unsubscribe();
  }, [booking?.id, booking?.activityId]);

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

    try {
      await update(ref(db, `bookings/${booking.id}`), {
        status: 'Reschedule Requested',
        requestedRescheduleDate: format(selectedDate, 'MMM dd, yyyy'),
        requestedRescheduleNights: nights,
      });
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

            let className = "calendar-day";
            if (!isCurrentMonth) className += " other-month";
            if (isBooked) className += " booked";
            if (isSelected) className += " selected";
            if (isPast) className += " past";

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

  if (success) {
    return (
      <div className="modal-overlay">
        <div className="card modal-content" style={{ textAlign: 'center', padding: '48px 32px', maxWidth: '400px' }}>
          <div style={{
            width: '80px', height: '80px', background: '#EEF2FF',
            borderRadius: '50%', display: 'flex', justifyContent: 'center',
            alignItems: 'center', margin: '0 auto 24px'
          }}>
            <CheckCircle2 size={40} color="#4F46E5" />
          </div>
          <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0' }}>Request Sent!</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6' }}>
            Your request to reschedule for <strong>{format(selectedDate, 'MMM dd, yyyy')} ({nights} Night/s)</strong> has been submitted to the host.
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
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Reschedule Stay</h2>
            <p style={{ margin: '4px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>{booking.activityTitle}</p>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        <div style={{ marginBottom: '24px' }}>
          <label className="input-label">Select New Start Date</label>
          {loading ? (
             <div style={{ textAlign: 'center', padding: '40px 0' }}><div className="loader"></div></div>
          ) : renderCalendar()}
        </div>

        <div style={{ marginBottom: '32px' }}>
          <label className="input-label">Duration of Stay</label>
          <div className="counter-control" style={{ margin: '0 auto' }}>
            <button type="button" onClick={() => { setNights(Math.max(1, nights - 1)); }} className="counter-btn">-</button>
            <div className="counter-value">
               <span style={{ fontSize: '20px', fontWeight: 800 }}>{nights}</span>
               <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', marginLeft: '4px' }}>NIGHTS</span>
            </div>
            <button type="button" onClick={() => {
              if (selectedDate && isSelectionConflicting(selectedDate, nights + 1)) {
                alert('Cannot extend stay: Date range overlaps with another booking.');
              } else {
                setNights(nights + 1);
              }
            }} className="counter-btn">+</button>
          </div>
          {selectionConflict && (
            <div style={{ color: 'var(--primary)', fontSize: '13px', marginTop: '12px', display: 'flex', alignItems: 'center', gap: '8px', background: '#FEF2F2', padding: '10px', borderRadius: '10px', fontWeight: 600 }}>
              <AlertCircle size={16} /> Selected range overlaps with an existing booking.
            </div>
          )}
        </div>

        <button
          className="btn btn-primary"
          style={{ width: '100%', height: '56px' }}
          disabled={!selectedDate || selectionConflict}
          onClick={handleReschedule}
        >
          Send Reschedule Request
        </button>
      </div>

      <style>{`
        .input-label { display: block; font-size: 13px; font-weight: 800; color: var(--text-main); margin-bottom: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
        .close-btn { background: var(--light-bg); border: none; width: 36px; height: 36px; borderRadius: 50%; display: flex; align-items: center; justify-content: center; cursor: pointer; color: var(--text-main); transition: var(--transition); border: 1px solid var(--border); }
        .close-btn:hover { background: var(--surface); transform: rotate(90deg); }

        .modern-calendar { background: var(--light-bg); padding: 20px; borderRadius: 24px; border: 1px solid var(--border); }
        .nav-btn { background: var(--surface); border: 1px solid var(--border); color: var(--text-main); width: 32px; height: 32px; borderRadius: 10px; display: flex; align-items: center; justify-content: center; cursor: pointer; boxShadow: 0 2px 8px rgba(0,0,0,0.05); }
        .calendar-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 8px; }
        .day-label { text-align: center; font-size: 11px; font-weight: 800; color: var(--text-muted); padding-bottom: 10px; }
        .calendar-day { aspect-ratio: 1; border: none; background: var(--surface); color: var(--text-main); borderRadius: 12px; font-size: 14px; font-weight: 700; cursor: pointer; transition: var(--transition); display: flex; align-items: center; justify-content: center; boxShadow: 0 2px 4px rgba(0,0,0,0.02); }
        .calendar-day:hover:not(:disabled) { transform: scale(1.1); boxShadow: 0 4px 12px rgba(0,0,0,0.1); z-index: 1; }
        .calendar-day.selected { background: var(--primary) !important; color: white !important; boxShadow: 0 8px 15px rgba(251, 54, 64, 0.3); transform: scale(1.1); z-index: 1; }
        .calendar-day.booked { background: #FEF2F2; color: #EF4444; text-decoration: line-through; cursor: not-allowed; opacity: 0.5; border: 1px dashed #FEE2E2; }
        .calendar-day.past { color: #E5E7EB; cursor: not-allowed; background: transparent; boxShadow: none; }
        .calendar-day.today { color: var(--secondary); border: 2px solid var(--secondary); }
        .calendar-day.other-month { opacity: 0.3; }

        /* Counter Controls */
        .counter-control { display: flex; align-items: center; gap: 24px; background: var(--light-bg); padding: 12px 20px; borderRadius: 20px; width: fit-content; border: 1px solid var(--border); }
        .counter-btn { width: 40px; height: 40px; borderRadius: 14px; border: 1px solid var(--border); background: var(--surface); color: var(--text-main); fontSize: 20px; font-weight: 700; cursor: pointer; display: flex; align-items: center; justify-content: center; boxShadow: 0 4px 10px rgba(0,0,0,0.05); transition: var(--transition); }
        .counter-btn:hover { background: var(--secondary); color: white; transform: translateY(-2px); }
        .counter-value { display: flex; align-items: baseline; }
      `}</style>
    </div>
  );
};

export default RescheduleModal;
