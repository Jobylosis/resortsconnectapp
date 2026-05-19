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
        const bookings = snapshot.val();
        Object.values(bookings).forEach(b => {
          if (b.id === booking.id) return; // Ignore current booking
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

  const handleReschedule = async () => {
    if (!selectedDate) return;

    try {
      await update(ref(db, `bookings/${booking.id}`), {
        status: 'Reschedule Requested',
        requestedRescheduleDate: format(selectedDate, 'MMM dd, yyyy'),
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
            Your request to reschedule for <strong>{format(selectedDate, 'MMM dd, yyyy')}</strong> has been submitted to the host.
          </p>
          <button className="btn btn-primary" onClick={onClose} style={{ marginTop: '32px', width: '100%' }}>Done</button>
        </div>
      </div>
    );
  }

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

        <div style={{ marginBottom: '32px' }}>
          <label className="input-label">Select New Date</label>
          {loading ? (
             <div style={{ textAlign: 'center', padding: '40px 0' }}><div className="loader"></div></div>
          ) : renderCalendar()}
        </div>

        <button
          className="btn btn-primary"
          style={{ width: '100%', height: '56px' }}
          disabled={!selectedDate}
          onClick={handleReschedule}
        >
          Send Reschedule Request
        </button>
      </div>
    </div>
  );
};

export default RescheduleModal;
