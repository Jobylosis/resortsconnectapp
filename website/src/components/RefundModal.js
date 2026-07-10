import React, { useState } from 'react';
import { db } from '../firebase';
import { ref, update } from 'firebase/database';
import { X, AlertCircle, CheckCircle2 } from 'lucide-react';

const RefundModal = ({ booking, onClose }) => {
  const [reason, setReason] = useState('');
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);

  const handleEmojiFilter = (value) => {
    const emojiRegex = /[\u{1f300}-\u{1f5ff}\u{1f600}-\u{1f64f}\u{1f680}-\u{1f6ff}\u{1f1e6}-\u{1f1ff}\u{2700}-\u{27bf}\u{1f900}-\u{1f9ff}\u{1f3fb}-\u{1f3ff}\u{2600}-\u{26ff}\u{1f100}-\u{1f1ff}]/gu;
    return value.replace(emojiRegex, '');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!reason.trim()) return;

    setLoading(true);
    try {
      await update(ref(db, `bookings/${booking.id}`), {
        status: 'Refund Requested',
        refundReason: reason.trim(),
      });
      setSuccess(true);
    } catch (error) {
      alert('Refund request failed: ' + error.message);
    } finally {
      setLoading(false);
    }
  };

  if (success) {
    return (
      <div className="modal-overlay">
        <div className="card modal-content" style={{ textAlign: 'center', padding: '48px 32px', maxWidth: '400px' }}>
          <div style={{
            width: '80px', height: '80px', background: 'rgba(239, 68, 68, 0.1)',
            borderRadius: '50%', display: 'flex', justifyContent: 'center',
            alignItems: 'center', margin: '0 auto 24px'
          }}>
            <CheckCircle2 size={40} color="var(--primary)" />
          </div>
          <h2 style={{ fontSize: '24px', fontWeight: 800, margin: '0 0 12px 0' }}>Request Submitted</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '15px', lineHeight: '1.6' }}>
            Your refund request for <strong>{booking.activityTitle}</strong> has been sent to the host for review.
          </p>
          <button className="btn btn-primary" onClick={onClose} style={{ marginTop: '32px', width: '100%' }}>Done</button>
        </div>
      </div>
    );
  }

  return (
    <div className="modal-overlay" style={{ zIndex: 3000 }}>
      <div className="card modal-content view-transition" style={{ maxWidth: '450px', padding: '32px', borderRadius: '32px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <div>
            <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800 }}>Request Refund</h2>
            <p style={{ margin: '4px 0 0 0', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 600 }}>{booking.activityTitle}</p>
          </div>
          <button onClick={onClose} className="close-btn"><X size={20} /></button>
        </div>

        <form onSubmit={handleSubmit}>
          <div style={{ marginBottom: '32px' }}>
            <label className="input-label">Reason for Refund</label>
            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '16px' }}>
               Please explain briefly why you are requesting a refund. The host will review your request.
            </p>
            <textarea
              className="input"
              style={{ height: '120px', resize: 'none', padding: '16px' }}
              placeholder="Enter your reason here..."
              value={reason}
              onChange={(e) => setReason(handleEmojiFilter(e.target.value))}
              required
              maxLength="500"
            />
          </div>

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', height: '56px' }}
            disabled={!reason.trim() || loading}
          >
            {loading ? <div className="loader small"></div> : 'Submit Refund Request'}
          </button>
        </form>
      </div>
    </div>
  );
};

export default RefundModal;
